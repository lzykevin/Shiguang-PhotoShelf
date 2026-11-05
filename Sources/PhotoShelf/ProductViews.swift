import SwiftUI
import AppKit
import PhotoLibraryCore

struct ActiveConditions: View {
    var legacyOnly = false
    @EnvironmentObject var model: LibraryModel
    @Environment(\.colorScheme) private var scheme
    private var p: DesignPalette { DesignPalette(dark: scheme == .dark) }
    var body: some View {
        if legacyOnly ? (!model.sourceFilters.isEmpty || !model.availabilityFilters.isEmpty || !model.formatFilters.isEmpty || model.formatFilter != "全部格式") : model.advancedFilterCount > 0 {
            HStack(spacing: 10) {
                Text("筛选").font(.system(size: 11)).foregroundStyle(p.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if !legacyOnly && model.dateFilterEnabled { chip(model.dateFilterLabel, icon: "calendar") { model.dateFilterEnabled = false } }
                        ForEach(legacyOnly ? [] : model.tagFilters.sorted(), id: \.self) { tag in chip(tag, icon: "tag") { model.tagFilters.remove(tag) } }
                        ForEach(model.formatFilters.union(model.formatFilter == "全部格式" ? [] : [model.formatFilter]).sorted(), id: \.self) { format in
                            chip(format, icon: "photo") { model.formatFilters.remove(format); if model.formatFilter == format { model.formatFilter = "全部格式" } }
                        }
                        ForEach(model.sourceFilters.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                            chip(model.snapshot.sources.first(where: { $0.id == id })?.name ?? "未关联来源", icon: "folder") { model.sourceFilters.remove(id) }
                        }
                        ForEach(model.availabilityFilters.sorted(), id: \.self) { state in chip(state, icon: "externaldrive") { model.availabilityFilters.remove(state) } }
                    }
                }
                Button("清除") { model.clearAdvancedFilters() }.buttonStyle(RowFeedbackStyle()).font(.system(size: 11)).foregroundStyle(p.muted).help("清除高级条件，保留搜索和星级").accessibilityLabel("清除高级条件")
            }.padding(.horizontal, 20).frame(height: 40).background(p.canvas)
                .overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }
        }
    }
    private func chip(_ text: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(text).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                Image(systemName: "xmark").font(.system(size: 8, weight: .medium)).padding(.leading, 3)
            }.padding(.horizontal, 9).frame(height: 25).frame(maxWidth: 240)
                .foregroundStyle(p.accent).background(p.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(RowFeedbackStyle()).help("移除条件：" + text).accessibilityLabel("移除条件：" + text)
    }
}

private final class PhotoViewerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct ProductWindowBridge: NSViewRepresentable {
    @ObservedObject var model: LibraryModel
    @AppStorage("appearance") private var appearance = "system"
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        let appearance = appearance
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            coordinator.update(window, model: model, appearance: appearance)
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.closeViewer(restoreFocus: false)
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        var viewer: NSWindow?
        weak var library: NSWindow?
        weak var model: LibraryModel?
        var savedPresentation: NSApplication.PresentationOptions?
        var inputMonitor: Any?
        func update(_ window: NSWindow, model: LibraryModel, appearance: String) {
            library = window; self.model = model
            let desired: NSAppearance.Name? = appearance == "dark" ? .darkAqua : appearance == "light" ? .aqua : nil
            if window.appearance?.name != desired { window.appearance = desired.flatMap { NSAppearance(named: $0) } }
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbar = nil
            if model.viewerID != nil {
                guard viewer == nil else { return }
                let panel = PhotoViewerWindow(contentRect: window.screen?.frame ?? window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.identifier = NSUserInterfaceItemIdentifier("photoViewer")
                panel.isReleasedWhenClosed = false
                panel.backgroundColor = .black
                panel.appearance = NSAppearance(named: .darkAqua)
                panel.acceptsMouseMovedEvents = true
                panel.collectionBehavior = [.fullScreenAuxiliary]
                panel.delegate = self
                panel.contentView = NSHostingView(rootView: FullscreenViewer().environmentObject(model))
                viewer = panel
                savedPresentation = NSApp.presentationOptions
                NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
                inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                    if let viewer = self?.viewer, event.window === viewer {
                        NotificationCenter.default.post(name: .photoShelfViewerInput, object: viewer)
                    }
                    return event
                }
                panel.makeKeyAndOrderFront(nil)
            } else {
                closeViewer(restoreFocus: true)
            }
        }
        func closeViewer(restoreFocus: Bool) {
            guard let panel = viewer else { return }
            viewer = nil
            // Closing a viewer may also be triggered by Cmd-W or by removing the
            // library's hosting view, without another SwiftUI update afterwards.
            panel.delegate = nil
            panel.close()
            if let savedPresentation { NSApp.presentationOptions = savedPresentation }
            savedPresentation = nil
            if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
            inputMonitor = nil
            if model?.viewerID != nil { model?.viewerID = nil }
            if restoreFocus, library?.isVisible == true { library?.makeKeyAndOrderFront(nil) }
        }
        func windowWillClose(_ notification: Notification) {
            guard let closing = notification.object as? NSWindow, closing === viewer else { return }
            // AppKit is already closing this window; detach it before cleanup to
            // avoid recursively sending close through its delegate.
            closing.delegate = nil
            let original = savedPresentation
            viewer = nil
            savedPresentation = nil
            if let original { NSApp.presentationOptions = original }
            if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
            inputMonitor = nil
            model?.viewerID = nil
            if library?.isVisible == true { library?.makeKeyAndOrderFront(nil) }
        }
        deinit { if let inputMonitor { NSEvent.removeMonitor(inputMonitor) } }
    }
}

extension Notification.Name {
    static let photoShelfViewerInput = Notification.Name("PhotoShelfViewerInput")
}

struct FullscreenViewer: View {
    @EnvironmentObject var model: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var interaction = ViewerInteractionTracker()
    @State private var actualSize = false
    @State private var playing = false
    @AppStorage("slideshowInterval") private var slideInterval = 5
    private let intervals = [2, 3, 5, 10, 15, 30, 60]
    @State private var loadState: PhotoLoadState = .loading
    @State private var canShowOriginal = false
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black
                if let photo = model.focusedPhoto {
                    ZoomPhoto(photo:photo,url:model.url(for:photo),cacheKey:model.cacheKey(photo),actualSize:actualSize, onDoubleClick: { model.viewerID = nil }, onNavigate: { model.step($0) }, scrollToZoom: true) { state in
                        loadState = state
                        // Keep control contrast stable while the next image is decoding.
                        if state != .loading { canShowOriginal = state == .original }
                    }
                    if loadState == .unavailable {
                        VStack(spacing:12) {
                            Image(systemName:"photo.badge.exclamationmark").font(.system(size:36))
                            Text("无法显示这张照片").font(.system(size:16,weight:.medium))
                            Text("原片不可用，且没有缓存预览。重新连接来源后重试。").font(.system(size:12)).foregroundStyle(.secondary)
                        }.foregroundStyle(.white.opacity(0.8))
                    }
                    VStack {
                        HStack(spacing:14) {
                            Button { model.viewerID = nil } label: { Image(systemName:"xmark").font(.system(size:13,weight:.medium)).frame(width:30,height:30) }.help("退出全屏 · Esc")
                            VStack(alignment:.leading,spacing:5) {
                                Text(photo.filename).font(.system(size:14,weight:.medium)).lineLimit(1).truncationMode(.middle)
                                Text("\(photo.width) × \(photo.height) · \(photo.format)").font(.system(size:11)).foregroundStyle(.white.opacity(0.65))
                                if loadState == .cached { Text("原片不可用 · 显示缓存预览，清晰度有限").font(.system(size:11)).foregroundStyle(.orange) }
                            }
                            Spacer()
                            Text("\((model.viewerQueue.firstIndex(of:photo.id) ?? 0)+1) / \(model.viewerQueue.count)").font(.system(size:12)).monospacedDigit().foregroundStyle(.white.opacity(0.72))
                        }.padding(.horizontal,28).padding(.top,20).padding(.bottom,24)
                            .background(LinearGradient(colors:[.black.opacity(0.78),.clear],startPoint:.top,endPoint:.bottom))
                            .contentShape(Rectangle()).background(controlFrame("header"))
                            .onHover { interaction.setHovered("header", hovered:$0) }
                        Spacer()
                        HStack(spacing:16) {
                            Button { model.step(-1) } label: { Image(systemName:"chevron.left").font(.system(size:13,weight:.medium)).frame(width:28,height:30) }.help("上一张 · ←").disabled(!model.slideshowLoop && model.viewerQueue.first == photo.id)
                            Rectangle().fill(.white.opacity(0.14)).frame(width:1,height:18).accessibilityHidden(true)
                            HStack(spacing: 0) {
                                Button {
                                    if !playing { model.preparePlayback() }
                                    playing.toggle()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: playing ? "pause.fill" : "play.fill")
                                            .font(.system(size: 12, weight: .medium)).frame(width: 13)
                                        Text("\(slideInterval) 秒").font(.system(size: 11)).monospacedDigit()
                                    }.foregroundStyle(.white).frame(width: 67, height: 30)
                                }.disabled(model.viewerQueue.isEmpty)
                                    .help(playing ? "暂停播放" : "播放照片 · 每 \(slideInterval) 秒 · \(model.slideshowLoop ? "循环播放" : "到最后一张自动停止")")
                                    .accessibilityLabel(playing ? "暂停播放" : "播放照片")
                                Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 14).accessibilityHidden(true)
                                Menu {
                                    Picker("播放顺序", selection: $model.slideshowRandom) {
                                        Label("顺序播放", systemImage: "arrow.right").tag(false)
                                        Label("随机播放", systemImage: "shuffle").tag(true)
                                    }.pickerStyle(.inline)
                                    Toggle("循环播放", isOn: $model.slideshowLoop)
                                    Toggle("只播放选中照片（\(model.viewerSelectedIDs.count) 张）", isOn: $model.slideshowSelectedOnly)
                                        .disabled(model.viewerSelectedIDs.isEmpty)
                                    Divider()
                                    ForEach(intervals, id: \.self) { seconds in
                                        Button { slideInterval = seconds } label: {
                                            if slideInterval == seconds {
                                                Label("每 \(seconds) 秒", systemImage: "checkmark")
                                            } else { Text("每 \(seconds) 秒") }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white).frame(width: 25, height: 30)
                                }.menuStyle(.borderlessButton).menuIndicator(.hidden).tint(.white).fixedSize()
                                    .help("播放设置：顺序、循环、范围与间隔").accessibilityLabel("播放设置")
                            }.background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.1), lineWidth: 1) }
                            Rectangle().fill(.white.opacity(0.14)).frame(width:1,height:18).accessibilityHidden(true)
                            FavoriteButton(selected: photo.isFavorite, unselectedColor: .white.opacity(0.85)) { model.toggleFavorite(ids: [photo.id]) }
                            StarRating(rating:photo.rating,size:14,inactiveColor:.white.opacity(0.78)) { model.setRating($0) }
                            Rectangle().fill(.white.opacity(0.14)).frame(width:1,height:18).accessibilityHidden(true)
                            Button { if loadState == .original { actualSize.toggle() } } label: { Text(actualSize ? "适合窗口" : "100%").font(.system(size:11)).frame(width:58,height:28) }.disabled(!canShowOriginal).help("滚轮缩放 · 放大后拖动查看 · 点击左右半边切图")
                            Button { model.step(1) } label: { Image(systemName:"chevron.right").font(.system(size:13,weight:.medium)).frame(width:28,height:30) }.help("下一张 · →").disabled(!model.slideshowLoop && model.viewerQueue.last == photo.id)
                        }.padding(.horizontal,16).padding(.vertical,9)
                            .background(Color(white: 0.08).opacity(0.92),in:RoundedRectangle(cornerRadius:14))
                            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
                            .overlay { RoundedRectangle(cornerRadius:14).strokeBorder(.white.opacity(0.22),lineWidth:1) }
                            .shadow(color:.black.opacity(0.45),radius:18,y:6)
                            .environment(\.colorScheme, .dark)
                            .contentShape(RoundedRectangle(cornerRadius:14)).background(controlFrame("dock"))
                            .onHover { interaction.setHovered("dock", hovered:$0) }.padding(.bottom,28)
                    }.buttonStyle(QuietToolbarStyle()).foregroundStyle(.white).opacity(interaction.visible ? 1 : 0).allowsHitTesting(interaction.visible).accessibilityHidden(!interaction.visible)
                        .animation(reduceMotion ? nil : .easeInOut(duration:0.2),value:interaction.visible)
                }
            }
        }.coordinateSpace(name:"productViewer")
            .background(ViewerPointerBridge(tracker:interaction))
            .onPreferenceChange(ProductViewerFramesKey.self) { interaction.frames = $0 }
            .preferredColorScheme(.dark).ignoresSafeArea()
            .onChange(of:model.viewerID) { actualSize = false }
             .task(id: "\(playing)-\(slideInterval)-\(model.slideshowRandom)-\(model.slideshowLoop)-\(model.slideshowSelectedOnly)-\(model.viewerID?.uuidString ?? "")") {
                guard playing, model.viewerID != nil else { return }
                while !Task.isCancelled && playing && model.viewerID != nil {
                    do { try await Task.sleep(for: .seconds(max(2, slideInterval))) }
                    catch { return }
                    guard !Task.isCancelled, playing, model.viewerID != nil else { return }
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if !model.advancePlayback() { playing = false }
                    }
                }
            }
            .onAppear {
                if !intervals.contains(slideInterval) { slideInterval = 5 }
                interaction.start()
            }
            .onDisappear { playing = false; interaction.stop() }
    }
    private func controlFrame(_ name: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key:ProductViewerFramesKey.self,
                                   value:[name:geometry.frame(in:.named("productViewer"))])
        }.allowsHitTesting(false)
    }
}

private struct ProductViewerFramesKey: PreferenceKey {
    static var defaultValue: [String:CGRect] = [:]
    static func reduce(value: inout [String:CGRect], nextValue: () -> [String:CGRect]) { value.merge(nextValue(),uniquingKeysWith: { _, new in new }) }
}

private final class ViewerInteractionTracker: ObservableObject {
    @Published var visible = false
    var frames: [String:CGRect] = [:]
    private var hoveredRegions: Set<String> = []
    weak var view: NSView?
    private weak var activeWindow: NSWindow?
    private var observer: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var hideTask: DispatchWorkItem?
    func attach(_ view: NSView) { self.view = view }
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName:.photoShelfViewerInput,object:nil,queue:.main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow else { return }
            self.activeWindow = window
            self.reveal()
        }
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.view?.window?.isVisible == true else { return }
                self.setHovered("menu", hovered: true)
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                self?.setHovered("menu", hovered: false)
            }
        ]
    }
    func setHovered(_ region: String, hovered: Bool) {
        guard hoveredRegions.contains(region) != hovered else { return }
        if hovered { hoveredRegions.insert(region) } else { hoveredRegions.remove(region) }
        // Separate regions prevent an exit from one control from cancelling the
        // hover that has already begun over another control.
        reveal()
    }
    private func hoveringControls() -> Bool {
        if !hoveredRegions.isEmpty { return true }
        guard let window = activeWindow ?? view?.window else { return false }
        // Named viewer coordinates cover the window content, not the background
        // representable whose bounds can differ during a style transition.
        guard let surface = window.contentView else { return false }
        let local = surface.convert(window.mouseLocationOutsideOfEventStream, from:nil)
        let point = CGPoint(x:local.x,y:surface.isFlipped ? local.y : surface.bounds.height-local.y)
        return frames.values.contains { $0.insetBy(dx:-3,dy:-3).contains(point) }
    }
    func reveal() {
        visible = true; hideTask?.cancel()
        guard !hoveringControls() else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.hoveringControls() else { return }
            self.visible = false
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline:.now()+2.5,execute:task)
    }
    func stop() {
        hideTask?.cancel(); hideTask = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }; menuObservers = []
        frames = [:]; hoveredRegions = []; view = nil; activeWindow = nil
    }
    deinit {
        hideTask?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

private struct ViewerPointerBridge: NSViewRepresentable {
    let tracker: ViewerInteractionTracker
    func makeNSView(context:Context) -> NSView { let view = NSView(); tracker.attach(view); return view }
    func updateNSView(_ view:NSView,context:Context) { tracker.attach(view) }
}
