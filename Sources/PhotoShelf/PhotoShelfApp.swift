import SwiftUI
import AppKit
import PhotoLibraryCore

@main struct PhotoShelfApp: App {
    @StateObject private var updater = AppUpdater.shared
    @StateObject private var model: LibraryModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    init() {
        let args = ProcessInfo.processInfo.arguments
        var directory: URL?
        if let index = args.firstIndex(of: "--data-directory"), args.indices.contains(index + 1) { directory = URL(fileURLWithPath: args[index + 1]) }
        _model = StateObject(wrappedValue: LibraryModel(directory: directory))
    }
    var body: some Scene {
        Window("拾光 PhotoShelf", id: "library") {
            ContentView().environmentObject(model)
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { updater.check() }.disabled(!updater.canCheck)
            }
            CommandGroup(replacing: .newItem) {
                Button("添加照片文件夹…") { model.addFolder() }.keyboardShortcut("o").disabled(model.scanning || model.repository == nil)
                Button("刷新照片来源") { model.startScan() }.keyboardShortcut("r").disabled(model.scanning || model.activeSources.isEmpty)
                Button("停止扫描") { model.cancelScan() }.disabled(!model.scanning)
                Divider()
                Button("新建相册…") { model.createAlbum() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(model.viewerID != nil || !model.comparisonIDs.isEmpty)
            }
            CommandGroup(after: .importExport) {
                Button("导出照片副本…") { model.exportOriginals() }.disabled(model.selection.isEmpty)
                Button("分享照片…") { model.sharePhotos() }.disabled(model.selection.isEmpty)
                Button("保存为智能相册…") { model.saveSmartAlbum() }.disabled(model.viewerID != nil || !model.comparisonIDs.isEmpty)
                Divider()
                Button("导出整理数据备份…") { model.exportBackup() }.disabled(model.repository == nil)
                Button("恢复整理数据备份…") { model.importBackup() }.disabled(model.scanning || model.repository == nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { activeUndoManager.undo() }.keyboardShortcut("z").disabled(!activeUndoManager.canUndo)
                Button("重做") { activeUndoManager.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!activeUndoManager.canRedo)
            }
            CommandMenu("浏览") {
                Button("后退") { model.navigateBack() }.keyboardShortcut("[").disabled(!model.canNavigateBack)
                Button("前进") { model.navigateForward() }.keyboardShortcut("]").disabled(!model.canNavigateForward)
            }
            CommandMenu("照片") {
                Button("对比所选照片…") { model.beginComparison() }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(!model.canCompare)
                Button(model.allTargetsFavorite ? "取消收藏" : "添加收藏") { model.toggleFavorite() }.disabled(model.favoriteTargets.isEmpty)
                Button("查看大图") { model.openViewer() }.disabled(model.visible.isEmpty)
                ForEach(0...5, id: \.self) { rating in Button(rating == 0 ? "清除星级    0" : "\(rating) 星    \(rating)") { model.setRating(rating) }.disabled(model.selection.isEmpty && model.viewerID == nil) }
                Divider()
                Button("添加标签…") { model.prompt(title: "添加标签") { tag in model.addTag(tag) } }.disabled(model.selection.isEmpty || model.viewerID != nil || !model.comparisonIDs.isEmpty)
                Menu("加入相册") { ForEach(model.snapshot.albums.filter { $0.query == nil }) { album in Button(album.name) { model.addToAlbum(album) } } }.disabled(model.selection.isEmpty)
                if case .album(let id) = model.navigation, let album = model.snapshot.albums.first(where: { $0.id == id && $0.query == nil }) {
                    Button("从当前相册移除") { model.removeFromAlbum(album) }.disabled(model.selection.isEmpty)
                }
                Button("用其他应用打开…") { if let photo = model.focusedPhoto { model.openExternally(photo) } }.disabled(model.focusedPhoto == nil)
                Button("在 Finder 中显示") { if let photo = model.focusedPhoto { model.reveal(photo) } }.disabled(model.focusedPhoto == nil)
            }
            CommandGroup(after: .textEditing) {
                Button("搜索照片") { NotificationCenter.default.post(name:Notification.Name("PhotoShelfFocusSearch"),object:nil) }.keyboardShortcut("f").disabled(model.viewerID != nil || !model.comparisonIDs.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button("显示／隐藏侧栏") { model.sidebar.toggle() }.keyboardShortcut("s", modifiers: [.command, .control])
                Button("显示／隐藏信息面板") { model.inspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        Settings { SettingsView().environmentObject(model) }
    }
    private var activeUndoManager: UndoManager {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable, let undo = editor.undoManager { return undo }
        return model.undoManager
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) { window.setFrameAutosaveName("PhotoShelfMain"); window.minSize = NSSize(width: 1080, height: 720) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct SettingsView: View {
    @ObservedObject private var updater = AppUpdater.shared
    @EnvironmentObject var model: LibraryModel
    @State private var cacheBytes: Int64?
    var body: some View {
        Form {
            Section("软件更新") {
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建")
                Toggle("自动检查更新", isOn: Binding(get: { updater.automaticChecks }, set: { updater.setAutomaticChecks($0) })).disabled(!updater.configured)
                Button("检查更新…") { updater.check() }.disabled(!updater.canCheck)
                Text(updater.configured ? "测试版通道 · 检查更新只访问版本信息，不上传照片或整理数据。" : "此构建尚未配置更新服务。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("浏览") {
                Toggle("按拍摄月份分组", isOn: $model.dateGrouping)
            }
            Section("照片来源") {
                ForEach(model.snapshot.sources) { source in
                    HStack { Text(source.name); Spacer(); Text(source.isDetached ? "已移除 · 整理信息已保留" : model.offline.contains(source.id) ? "离线" : "在线"); Button("重新关联") { model.rebind(source) }; Button("移除来源") { model.removeSource(source) }.disabled(source.isDetached) }
                }
            }
            Section("本地数据") {
                Text("原片只读。星级、标签、备注和相册保存在这台 Mac 上，与照片文件分开存储。").font(.caption).foregroundStyle(.secondary)
                Button("导出整理数据备份…") { model.exportBackup() }
                Button("恢复整理数据备份…") { model.importBackup() }
                Button("打开整理数据目录") { if let url = model.repository?.directory { NSWorkspace.shared.open(url) } }
                LabeledContent("缩略图缓存", value: cacheBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "正在统计…")
                Button("清理缩略图缓存") {
                    guard model.confirm(title: "清理缩略图缓存？", message: "缓存可从在线原片重建。离线照片将暂时无法显示预览，直到来源重新连接。整理信息不会丢失。") else { return }
                    ThumbnailService.shared.clear()
                    Task { cacheBytes = await ThumbnailService.shared.cacheUsageBytes() }
                }
            }
            Section("快捷键") {
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow("0–5", "设置星级（0 清除）")
                    shortcutRow("F", "收藏或取消收藏")
                    shortcutRow("D / ⇧⌘C", "对比所选照片")
                    shortcutRow("空格 / Esc", "查看大图 / 退出大图")
                    shortcutRow("← / →", "大图或画廊中切换照片")
                    shortcutRow("⌘← / ⌘→", "返回 / 前进")
                    shortcutRow("⌘[ / ⌘]", "返回 / 前进")
                    shortcutRow("⌘F", "搜索照片")
                    shortcutRow("⌘O / ⌘R", "添加文件夹 / 刷新来源")
                    shortcutRow("⇧⌘N", "新建相册")
                    shortcutRow("⌘Z / ⇧⌘Z", "撤销 / 重做")
                    shortcutRow("⌃⌘S / ⌥⌘I", "显示或隐藏侧栏 / 信息面板")
                }.font(.caption)

            }
        }.formStyle(.grouped).frame(width: 500, height: 560)
        .task { cacheBytes = await ThumbnailService.shared.cacheUsageBytes() }
        .onChange(of: model.dateGrouping) { _, _ in model.savePreferences() }
    }
    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(keys).monospaced().frame(width: 120, alignment: .leading)
            Text(description).foregroundStyle(.secondary)
        }
    }

}

struct KeyboardBridge: NSViewRepresentable {
    let model: LibraryModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class Coordinator {
        private var monitor: Any?
        private var mouseMonitor: Any?
        init(model: LibraryModel) {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp, .swipe]) { [weak model] event in
                MainActor.assumeIsolated {
                    guard let model, NSApp.isActive, let window = event.window ?? NSApp.keyWindow ?? NSApp.mainWindow,
                          window.identifier?.rawValue == "library",
                          window.attachedSheet == nil, NSApp.modalWindow == nil,
                          model.viewerID == nil, model.namePrompt == nil, !model.filterPopoverPresented else { return event }
                    if event.type == .swipe {
                        guard let direction = browserSwipeDirection(x: event.deltaX, y: event.deltaY),
                              !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField) else { return event }
                        if direction < 0 { model.navigateBack() } else { model.navigateForward() }
                        return nil
                    }
                    guard event.buttonNumber == 3 || event.buttonNumber == 4 else { return event }
                    if event.type == .otherMouseDown {
                        if event.buttonNumber == 3 { model.navigateBack() }
                        else { model.navigateForward() }
                    }
                    return nil
                }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
                let handled = MainActor.assumeIsolated { () -> Bool in
                if let model, NSApp.isActive, let window = event.window ?? NSApp.keyWindow,
                   window.identifier?.rawValue == "library", window.attachedSheet == nil, NSApp.modalWindow == nil,
                   model.viewerID == nil, model.namePrompt == nil, !model.filterPopoverPresented,
                   event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
                   [123, 124].contains(event.keyCode),
                   !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField) {
                    if !event.isARepeat {
                        if event.keyCode == 123 { model.navigateBack() } else { model.navigateForward() }
                    }
                    return true
                }
                guard let model, model.navigation != .folders, model.namePrompt == nil, !model.filterPopoverPresented, let window = event.window, window.isMainWindow, ["library", "photoViewer"].contains(window.identifier?.rawValue ?? ""),
                      window.attachedSheet == nil, NSApp.modalWindow == nil,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
                if let text = window.firstResponder as? NSTextView, text.isEditable { return false }
                if window.firstResponder is NSTextField { return false }
                if event.charactersIgnoringModifiers?.lowercased() == "d" {
                    guard model.canCompare else { return false }
                    if !event.isARepeat { model.beginComparison() }
                    return true
                }
                if event.charactersIgnoringModifiers?.lowercased() == "f" {
                    guard !model.favoriteTargets.isEmpty else { return false }
                    // Consume key repeats without repeatedly toggling the saved value.
                    if !event.isARepeat {
                        model.toggleFavorite()
                    }
                    return true
                }
                if let string = event.charactersIgnoringModifiers, let rating = Int(string), (0...5).contains(rating) {
                    model.setRating(rating); return true
                }
                switch event.keyCode {
                case 49: if model.viewerID == nil { model.openViewer() } else { model.viewerID = nil }; return true
                case 53: if model.viewerID != nil { model.viewerID = nil; return true }
                case 123: if model.viewerID != nil || model.gridLayout == "gallery" { model.step(-1); return true }
                case 124: if model.viewerID != nil || model.gridLayout == "gallery" { model.step(1); return true }
                default: break
                }
                return false
                }
                return handled ? nil : event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) }; if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) } }
    }
}

// AppKit swipe delta is positive for a rightward gesture (back), negative
// for leftward (forward). Only discrete swipe events use this mapping.
func browserSwipeDirection(x: CGFloat, y: CGFloat) -> Int? {
    guard x.isFinite, y.isFinite, abs(x) > abs(y), x != 0 else { return nil }
    return x > 0 ? -1 : 1
}
