import SwiftUI
import UniformTypeIdentifiers
import PhotoLibraryCore

struct ContentView: View {
    @EnvironmentObject var model: LibraryModel
    @AppStorage("appearance") private var appearance = "system"
    @State private var sidebarDisplayWidth: CGFloat = 196
    @State private var inspectorDisplayWidth: CGFloat = 300
    @State private var searchFocused = false
    @State private var searchHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var dark: Bool { appearance == "dark" || (appearance == "system" && colorScheme == .dark) }
    private var p: DesignPalette { DesignPalette(dark: dark) }
    var body: some View {
        Group {
            Group {
                VStack(spacing:0) {
                    HStack(spacing:0) {
                        if model.sidebar {
                            VStack(spacing:0) {
                                HStack(spacing: 8) { PhotoShelfMark().frame(width: 22, height: 22).scaleEffect(0.82).frame(width: 18, height: 18); Text("拾光").font(.system(size:15,weight:.medium)); Spacer() }.padding(.horizontal,20).padding(.top,36).frame(height:72)
                                SidebarView()
                            }.frame(width:sidebarDisplayWidth).background(p.panel)
                            PaneDivider(width:$sidebarDisplayWidth,limits:180...300) { model.sidebarWidth = sidebarDisplayWidth; model.savePreferences() }
                        }
                        if model.navigation == .folders {
                            FolderOverview().frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                        VStack(spacing:0) {
                            productToolbar
                            Divider()
                            if model.filtersPresented { AdvancedFilters(); ActiveConditions(legacyOnly: true) }
                            else {
                                if model.sortingPresented { AdvancedFilters(sorting: true) }
                                ActiveConditions()
                            }
                            HStack(spacing:0) {
                                Group {
                                    if model.snapshot.sources.isEmpty { WelcomeView() }
                                    else if model.visible.isEmpty {
                                        VStack(spacing:14) {
                                            Image(systemName:"magnifyingglass").font(.system(size:26,weight:.light)).frame(width:64,height:64).background(p.raised.opacity(0.35),in:Circle())
                                            Text("没有匹配的照片").font(.system(size:15,weight:.medium)).foregroundStyle(Color.primary)
                                            Text(emptyDescription).font(.system(size:12))
                                            Button("清除筛选条件") { model.clearFilters() }.buttonStyle(RowFeedbackStyle()).font(.system(size:12,weight:.medium)).foregroundStyle(p.accent).padding(.horizontal,14).padding(.vertical,8).background(p.accent.opacity(0.10),in:RoundedRectangle(cornerRadius:6))
                                        }.foregroundStyle(p.muted).frame(maxWidth:.infinity,maxHeight:.infinity)
                                    } else if model.gridLayout == "gallery" { GalleryView(model:model) }
                                    else { PhotoGrid(model:model) }
                                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                                HStack(spacing: 0) {
                                    PaneDivider(width:$inspectorDisplayWidth,limits:250...380,reverse:true) { model.inspectorWidth = inspectorDisplayWidth; model.savePreferences() }
                                    InspectorView().frame(width:inspectorDisplayWidth)
                                }
                                .frame(width: model.inspector ? inspectorDisplayWidth + 1 : 0, alignment: .trailing)
                                .opacity(model.inspector ? 1 : 0)
                                .allowsHitTesting(model.inspector).accessibilityHidden(!model.inspector)
                            }
                        }
                        }
                    }
                    Divider(); statusBar
                }
            }
        }
        .background(p.canvas).tint(p.accent).accentColor(p.accent)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .frame(minWidth:1080,maxWidth:.infinity,minHeight:680,maxHeight:.infinity).ignoresSafeArea(.container,edges:.top)
        .background(ComparisonWindowPresenter(model: model).frame(width: 0, height: 0))
        .background(WindowTitleDragArea().frame(width: 0, height: 0))
        .sheet(item: $model.namePrompt) { request in
            NamePromptView(request: request) { model.namePrompt = nil }
        }
        .background(KeyboardBridge(model:model).frame(width:0,height:0))
        .background(ProductWindowBridge(model:model).frame(width:0,height:0))
        .alert("提示",isPresented:Binding(get:{model.issue != nil},set:{if !$0 {model.issue = nil}})) { Button("好") { model.issue = nil } } message: { Text(model.issue ?? "") }
        .onChange(of:model.inspector) { model.savePreferences() }
        .onChange(of:model.sidebar) { model.savePreferences() }
        .onChange(of:model.thumbnailSize) { model.savePreferences() }
        .onChange(of:model.showNames) { model.savePreferences() }
        .onChange(of:model.gridLayout) { model.savePreferences() }
        .onChange(of:model.dateGrouping) { model.savePreferences() }
        .onChange(of:model.dateGroupingByDay) { model.savePreferences() }
        .onAppear { sidebarDisplayWidth = model.sidebarWidth; inspectorDisplayWidth = model.inspectorWidth }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                            let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                            continuation.resume(returning: url?.isFileURL == true ? url : nil)
                        }
                    }
                    if let url { urls.append(url) }
                }
                if !urls.isEmpty { model.importFolders(urls) }
            }
            return !providers.isEmpty
        }
        .task { model.checkLibraryOnLaunch() }
    }
    private var productToolbar: some View {
        HStack(spacing:10) {
            Text(model.title).font(.system(size:13,weight:.semibold)).lineLimit(1).truncationMode(.middle).frame(width:150,alignment:.leading)
            HStack(spacing:2) {
                ForEach(-1...5,id:\.self) { value in
                    let active = value == -1 ? model.ratingFilters.isEmpty && !model.favoritesOnly : model.ratingFilters.contains(value)
                    Button { NSApp.keyWindow?.makeFirstResponder(nil); model.chooseRating(value < 0 ? nil : value, extending:NSApp.currentEvent?.modifierFlags.contains(.command) == true) } label: {
                        Text(value == -1 ? "全部" : value == 0 ? "未评分" : "\(value)星").font(.system(size:11,weight:active ? .semibold : .medium)).frame(width:value == 0 ? 46 : 32,height:26)
                            .foregroundStyle(active ? Color.accentColor : .secondary).background(active ? Color.accentColor.opacity(0.14) : .clear,in:RoundedRectangle(cornerRadius:5))
                    }.buttonStyle(RowFeedbackStyle()).accessibilityAddTraits(active ? .isSelected : []).help("按住 Command 点击可多选")
                }
                Rectangle().fill(p.line).frame(width: 1, height: 14).padding(.horizontal, 3)
                Button {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    model.favoritesOnly.toggle()
                } label: {
                    Image(systemName: model.favoritesOnly ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .medium)).frame(width: 32, height: 26)
                        .foregroundStyle(model.favoritesOnly ? Color.pink : p.muted)
                        .background(model.favoritesOnly ? Color.pink.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(RowFeedbackStyle()).accessibilityLabel("只看爱心收藏")
                    .accessibilityValue(model.favoritesOnly ? "已开启" : "已关闭")
                    .accessibilityAddTraits(model.favoritesOnly ? .isSelected : [])
                    .help("只看爱心收藏，可与星级组合；再次点击取消")
            }.padding(3).background(p.panel.opacity(0.65),in:RoundedRectangle(cornerRadius:8))
                .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(p.line.opacity(0.6),lineWidth:1) }
            Spacer(minLength:8)
            HStack(spacing:6) {
                Image(systemName:"magnifyingglass").font(.system(size:12)).foregroundStyle(searchFocused || searchHovered ? Color.accentColor : .secondary)
                StableSearchField(text:$model.search,focused:$searchFocused,hovered:$searchHovered).frame(height:16)
                Button { model.search = ""; NotificationCenter.default.post(name:Notification.Name("PhotoShelfFocusSearch"),object:nil) } label: { Image(systemName:"xmark.circle.fill").font(.system(size:11)).frame(width:14,height:20) }.buttonStyle(.plain).opacity(model.search.isEmpty ? 0 : 1).disabled(model.search.isEmpty).accessibilityHidden(model.search.isEmpty).accessibilityLabel("清除搜索")
            }.padding(.horizontal,9).frame(minWidth:100,idealWidth:160,maxWidth:184).frame(height:30).background(p.raised.opacity(searchFocused ? 0.65 : searchHovered ? 0.46 : 0.27),in:RoundedRectangle(cornerRadius:7))
                .overlay { RoundedRectangle(cornerRadius:7).strokeBorder(searchFocused ? p.accent.opacity(0.8) : searchHovered ? p.accent.opacity(0.4) : p.line,lineWidth:1) }
                .shadow(color:p.accent.opacity(searchFocused ? 0.09 : searchHovered ? 0.04 : 0),radius:3)
                .contentShape(Rectangle()).onHover { searchHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration:0.18),value:searchFocused)
                .animation(reduceMotion ? nil : .easeOut(duration:0.15),value:searchHovered)
                .onTapGesture { NotificationCenter.default.post(name:Notification.Name("PhotoShelfFocusSearch"),object:nil) }.help("搜索当前范围：" + model.title)
            Button {
                NSApp.keyWindow?.makeFirstResponder(nil)
                model.sortingPresented = false
                model.filtersPresented.toggle()
            } label: {
                Image(systemName: "line.3.horizontal.decrease").frame(width: 28, height: 28)
                    .foregroundStyle(model.advancedFilterCount > 0 || model.filtersPresented ? p.accent : p.muted)
                    .background(model.advancedFilterCount > 0 || model.filtersPresented ? p.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topTrailing) {
                        if model.advancedFilterCount > 0 { Circle().fill(p.accent).frame(width: 5,height: 5).offset(x: -2,y: 2) }
                    }
            }.buttonStyle(RowFeedbackStyle()).help("高级筛选").accessibilityLabel("高级筛选")

            Rectangle().fill(p.line).frame(width:1,height:18)
            Button {
                NSApp.keyWindow?.makeFirstResponder(nil)
                model.filtersPresented = false
                model.sortingPresented.toggle()
            } label: {
                Image(systemName: "arrow.up.arrow.down").frame(width: 28, height: 28)
                    .foregroundStyle(model.sortingPresented ? p.accent : p.muted)
                    .background(model.sortingPresented ? p.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }.buttonStyle(RowFeedbackStyle()).help("排序：" + model.sort.rawValue).accessibilityLabel("排序")
            HStack(spacing:2) {
                layoutButton("masonry", icon:"rectangle.grid.1x2", title:"瀑布流")
                layoutButton("justified", icon:"rectangle.grid.3x2", title:"等高排列")
                layoutButton("square", icon:"square.grid.2x2", title:"方形网格")
                layoutButton("gallery", icon:"rectangle.bottomthird.inset.filled", title:"画廊")
            }.padding(3).background(p.panel.opacity(0.65),in:RoundedRectangle(cornerRadius:7))
                .overlay { RoundedRectangle(cornerRadius:7).strokeBorder(p.line,lineWidth:1) }
            Menu {
                Picker("外观", selection: $appearance) {
                    Label("明亮", systemImage: "sun.max").foregroundStyle(.primary).tag("light")
                    Label("夜间", systemImage: "moon").foregroundStyle(.primary).tag("dark")
                    Label("跟随系统", systemImage: "circle.lefthalf.filled").foregroundStyle(.primary).tag("system")
                }.pickerStyle(.inline).tint(.primary)
            } label: {
                Image(systemName: appearance == "system" ? "circle.lefthalf.filled" : appearance == "dark" ? "moon" : "sun.max")
                    .resizable().scaledToFit().frame(width: 14, height: 14)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28)
                .tint(p.muted).help("外观").accessibilityLabel("外观")
            Button { model.inspector.toggle() } label: { Image(systemName:"sidebar.right").frame(width:28,height:28).contentShape(Rectangle()) }.help("显示或隐藏信息").accessibilityLabel("显示或隐藏信息")
            QuickSettingsMenu()
        }.font(.system(size:13)).foregroundStyle(p.muted).tint(p.muted).buttonStyle(QuietToolbarStyle()).padding(.horizontal,20).padding(.top,28).frame(height:72).background(p.canvas)
    }
    private func layoutButton(_ value: String, icon: String, title: String) -> some View {
        Button {
            NSApp.keyWindow?.makeFirstResponder(nil)
            model.gridLayout = value
        } label: {
            Image(systemName:icon).font(.system(size:12)).frame(width:27,height:26)
                .foregroundStyle(model.gridLayout == value ? p.accent : p.muted)
                .background(model.gridLayout == value ? p.accent.opacity(0.14) : .clear,in:RoundedRectangle(cornerRadius:5))
        }.buttonStyle(RowFeedbackStyle()).help(title).accessibilityLabel(title)
            .accessibilityAddTraits(model.gridLayout == value ? .isSelected : [])
    }
    private var emptyDescription: String {
        if model.scanning { return "照片会分批出现，你可以随时开始浏览。" }
        if model.filterCount > 0 || !model.search.isEmpty { return "试试调整搜索关键词或筛选条件。" }
        if model.navigation == .favorites { return "点击照片上的爱心，把喜欢的瞬间留在这里。" }
        if case .album = model.navigation { return "在全部照片中选择照片，右键加入这个相册。" }
        return "选择其他目录，或刷新当前照片来源。"
    }
    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.exporting {
                ProgressView(value: Double(model.exportCompleted), total: Double(max(1, model.exportTotal))).frame(width: 70)
                Text("正在导出 \(model.exportCompleted) / \(model.exportTotal)").monospacedDigit()
                Button("取消") { model.exportProgress?.cancel() }.buttonStyle(.link).help("完成当前文件后停止，保留已导出的副本")
            } else if model.scanning {
                ProgressView().controlSize(.small)
                Text("正在检查 \(model.scanName) · \(model.scanCount.formatted()) 张").lineLimit(1)
                Button("停止") { model.cancelScan() }.buttonStyle(.link)
            } else {
                Image(systemName: "internaldrive").foregroundStyle(.tertiary)
                Text("照片保留在原文件夹").foregroundStyle(.secondary)
                ViewThatFits { Text(model.navigation == .folders ? "按文件夹回看你的照片" : "双击或空格查看 · 0–5 评分").font(.system(size:10)).foregroundStyle(p.muted); EmptyView() }
            }
            Spacer(minLength: 5)
            Text("共 \((model.navigation == .folders ? model.snapshot.photos.count : model.visible.count).formatted()) 张照片" + (model.selection.isEmpty || model.navigation == .folders ? "" : " · 已选中 \(model.selection.count) 张"))
            if !model.offline.isEmpty { Label("\(model.offline.count) 个来源离线", systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(.orange) }
            if model.selection.count >= 2 && model.navigation != .folders {
                Button { model.beginComparison() } label: { Label("对比照片", systemImage: "rectangle.split.2x1") }
                    .disabled(!model.canCompare).help("选择 2–4 张照片进行对比 · D")
            }
            Spacer(minLength: 5)
            if model.navigation != .folders {
            Image(systemName: "photo").foregroundStyle(.secondary)
            Slider(value: $model.thumbnailSize, in: 128...320).controlSize(.mini).frame(width: 90).accessibilityLabel("缩略图大小")
            Image(systemName: "photo.fill").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11)).padding(.horizontal, 16).frame(height: 32).background(p.panel)
    }
}

struct PaneDivider: View {
    @Binding var width: CGFloat
    var limits: ClosedRange<CGFloat>
    var reverse = false
    var onEnded: () -> Void = {}
    @GestureState private var dragTranslation: CGFloat?
    private func proposedWidth(for translation: CGFloat) -> CGFloat {
        min(max(width + translation * (reverse ? -1 : 1), limits.lowerBound), limits.upperBound)
    }
    var body: some View {
        Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
            .overlay {
                if let dragTranslation {
                    Rectangle().fill(Color.primary.opacity(0.45)).frame(width: 2)
                        .offset(x: (proposedWidth(for: dragTranslation) - width) * (reverse ? -1 : 1))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .overlay(Color.clear.frame(width: 9).contentShape(Rectangle()).gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($dragTranslation) { value, translation, transaction in
                        // Preview only: never resize either pane or invalidate the photo
                        // layout while the pointer is moving. Gesture cancellation also
                        // clears this guide without committing a width.
                        transaction.disablesAnimations = true
                        translation = value.translation.width
                    }
                    .onEnded { value in
                        let next = proposedWidth(for: value.translation.width)
                        guard next != width else { return }
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        withTransaction(transaction) { width = next; onEnded() }
                    }
            ))
            .zIndex(1)
            .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
    }
}

struct SidebarView: View {
    @State private var albumFrames: [UUID: CGRect] = [:]
    @GestureState private var albumDrag: AlbumDragPosition?
    private var albumDrop: (id: UUID, after: Bool)? {
        guard let albumDrag else { return nil }
        return albumInsertion(at: albumDrag.point, moving: albumDrag.id, frames: albumFrames)
    }
    @EnvironmentObject var model: LibraryModel
    @Environment(\.colorScheme) private var colorScheme
    private var p: DesignPalette { DesignPalette(dark: colorScheme == .dark) }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("照片库")
                    nav("全部照片", icon: "square.grid.2x2", value: .all, count: model.snapshot.photos.count)
                    nav("最近添加", icon: "clock", value: .recent)
                    nav("最近浏览", icon: "clock.arrow.circlepath", value: .viewed)
                    nav("爱心收藏", icon: "heart", value: .favorites, count: model.snapshot.photos.filter(\.isFavorite).count)
                    nav("五星精选", icon: "star", value: .fiveStar)
                    HStack(spacing: 4) {
                        Text("文件夹").font(.system(size: 13)).foregroundStyle(p.muted)
                        Spacer()
                        FolderSortMenu()
                        Button { model.addFolder() } label: {
                            Image(systemName: "plus.circle").font(.system(size: 13)).frame(width: 24, height: 24).contentShape(Rectangle())
                        }
                            .buttonStyle(RowFeedbackStyle()).foregroundStyle(.secondary)
                            .help("添加照片文件夹").accessibilityLabel("添加照片文件夹")
                            .disabled(model.scanning || model.repository == nil)
                    }.padding(.leading, 12).padding(.trailing, 4).padding(.top, 20).padding(.bottom, 8)
                    nav("文件夹总览", icon: "square.grid.2x2", value: .folders)
                    if model.snapshot.sources.isEmpty { Text("添加目录后显示在这里").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 12).padding(.vertical, 8) }
                    ForEach(model.sortedSources) { source in
                        SourceTree(source: source)
                    }
                    HStack { sectionTitle("相册"); Spacer(); SidebarCreateButton(title: "新建相册", placeholder: "相册名称") { model.createAlbum(named: $0) }.padding(.trailing, 10) }
                    ForEach(model.snapshot.albums) { album in
                        nav(album.name, icon: album.query == nil ? "rectangle.stack" : "line.3.horizontal.decrease.circle", value: .album(album.id))
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: AlbumRowFrames.self,
                                        value: [album.id: geometry.frame(in: .global)])
                                }
                            }
                            .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                                .updating($albumDrag) { value, state, transaction in
                                    transaction.disablesAnimations = true
                                    state = AlbumDragPosition(id: album.id, point: value.location)
                                }
                                .onEnded { value in
                                    if let target = albumInsertion(at: value.location, moving: album.id, frames: albumFrames) {
                                        model.reorderAlbum(album.id, relativeTo: target.id, after: target.after)
                                    }
                                })
                            .opacity(albumDrag?.id == album.id ? 0.55 : 1)
                            .overlay(alignment: albumDrop?.after == true ? .bottom : .top) {
                                if albumDrop?.id == album.id {
                                    Capsule().fill(Color.primary.opacity(0.5)).frame(height: 2)
                                        .padding(.horizontal, 8).allowsHitTesting(false)
                                }
                            }
                            .contextMenu {
                                Button("重命名…") { model.renameAlbum(album) }
                                Button("删除相册…") { model.deleteAlbum(album) }
                            }
                    }
                    if model.snapshot.albums.isEmpty { Text("用相册组织你的照片故事").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 12).padding(.vertical, 6) }
                    HStack { sectionTitle("标签"); Spacer(); SidebarCreateButton(title: "新建标签", placeholder: "标签名称") { model.addTag($0, to: []) }.padding(.trailing, 10) }
                    TagFlowLayout {
                        ForEach(model.snapshot.tags, id: \.self) { tag in
                            Button { model.navigation = .tag(tag) } label: {
                                Text(tag).font(.system(size:13)).lineLimit(1).padding(.horizontal,9).padding(.vertical,5)
                                    .background(model.navigation == .tag(tag) ? p.accent.opacity(0.25) : p.raised.opacity(0.65),in:RoundedRectangle(cornerRadius:5))
                            }.buttonStyle(RowFeedbackStyle()).contextMenu {
                                Button("重命名…") { model.renameTag(tag) }; Button("删除标签…") { model.deleteTag(tag) }
                            }
                        }
                    }.padding(.horizontal,10)
                }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 20)
            }
        }
        .background(p.panel)
        .onPreferenceChange(AlbumRowFrames.self) { albumFrames = $0 }
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.system(size: 13, weight: .regular)).foregroundStyle(p.muted).padding(.leading, 12).padding(.top, title == "照片库" ? 0 : 20).padding(.bottom, 8) }
    private func nav(_ title: String, icon: String, value: LibrarySelection, count: Int? = nil) -> some View {
        Button { model.navigation = value; model.viewerID = nil } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 18).foregroundStyle(p.muted)
                Text(title).fontWeight(.regular).lineLimit(1); Spacer(minLength: 0)
                if let count, count > 0 { Text(count.formatted()).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
            .foregroundStyle(Color.primary)
            .background(model.navigation == value ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(RowFeedbackStyle()).accessibilityAddTraits(model.navigation == value ? .isSelected : [])
    }
}

private struct SidebarFolderName: View {
    let name: String
    @State private var availableWidth: CGFloat = .greatestFiniteMagnitude
    private var truncated: Bool {
        (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width > availableWidth + 1
    }
    var body: some View {
        Text(name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            .background(GeometryReader { geometry in
                Color.clear.onAppear { availableWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { availableWidth = geometry.size.width }
            })
            .help(truncated ? name : "")
    }
}

struct FolderNode: Identifiable {
    let path: String
    let name: String
    let children: [FolderNode]
    var id: String { path }
    static func nodes(paths: Set<String>, prefix: String = "") -> [FolderNode] {
        let names = Set(paths.compactMap { path -> String? in
            let remaining = prefix.isEmpty ? path : path.hasPrefix(prefix + "/") ? String(path.dropFirst(prefix.count + 1)) : ""
            return remaining.split(separator: "/").first.map(String.init)
        }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return names.map { name in let full = prefix.isEmpty ? name : prefix + "/" + name; return FolderNode(path: full, name: name, children: nodes(paths: paths, prefix: full)) }
    }
}
struct SourceTree: View {
    @EnvironmentObject var model: LibraryModel
    @Environment(\.colorScheme) private var colorScheme
    let source: PhotoSource
    @State private var expanded = true
    private var p: DesignPalette { DesignPalette(dark: colorScheme == .dark) }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(model.sortedFolders(model.folderNodes[source.id] ?? [], source: source.id)) { node in FolderRow(sourceID: source.id, node: node) }
        } label: {
            Button { model.navigation = .source(source.id, ""); model.viewerID = nil } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.offline.contains(source.id) ? "externaldrive.badge.exclamationmark" : "folder")
                        .font(.system(size: 13)).frame(width: 18).foregroundStyle(p.muted)
                    SidebarFolderName(name: source.name); Spacer(minLength: 0)
                    if model.offline.contains(source.id) { Circle().fill(p.muted).frame(width: 5, height: 5) }
                }.foregroundStyle(Color.primary).padding(.horizontal, 5).frame(height: 32).contentShape(Rectangle())
                    .background(model.navigation == .source(source.id, "") ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(RowFeedbackStyle())
                .accessibilityAddTraits(model.navigation == .source(source.id, "") ? .isSelected : [])
        }
        .disclosureGroupStyle(FolderDisclosureStyle(name: source.name))
        .modifier(FolderReorder(source: source.id, path: ""))
        .contextMenu {
            Button("重命名本地文件夹…") { model.promptRenameFolder(sourceID: source.id, path: "") }.disabled(model.scanning || model.offline.contains(source.id))
            Button("刷新") { model.startScan() }.disabled(model.scanning)
            Button("重新授权／绑定目录…") { model.rebind(source) }.disabled(model.scanning)
            Divider(); Button("移除来源…") { model.removeSource(source) }.disabled(model.scanning)
        }
        .padding(.leading, 4).padding(.trailing, 2).padding(.top, 6)
    }
}
struct FolderRow: View {
    @EnvironmentObject var model: LibraryModel
    @Environment(\.colorScheme) private var colorScheme
    let sourceID: UUID
    let node: FolderNode
    @State private var expanded = false
    private var p: DesignPalette { DesignPalette(dark: colorScheme == .dark) }
    private var selected: Bool { model.navigation == .source(sourceID, node.path) }
    var body: some View {
        if node.children.isEmpty { button.padding(.leading, 20) }
        else {
            DisclosureGroup(isExpanded: $expanded) { ForEach(model.sortedFolders(node.children, source: sourceID)) { child in FolderRow(sourceID: sourceID, node: child) } } label: { button }
                .disclosureGroupStyle(FolderDisclosureStyle(name: node.name))
        }
    }
    private var button: some View {
        Button { model.navigation = .source(sourceID, node.path); model.viewerID = nil } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder").font(.system(size: 13)).frame(width: 18)
                    .foregroundStyle(p.muted)
                SidebarFolderName(name: node.name)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.primary).padding(.horizontal, 5).frame(height: 32).contentShape(Rectangle())
            .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(RowFeedbackStyle())
            .accessibilityAddTraits(selected ? .isSelected : [])
            .modifier(FolderReorder(source: sourceID, path: node.path))
            .contextMenu {
                Button("重命名本地文件夹…") { model.promptRenameFolder(sourceID: sourceID, path: node.path) }
                    .disabled(model.scanning || model.offline.contains(sourceID))
            }
    }
}

/// Explicit indentation keeps parent and child rows distinct on every macOS version.
private struct FolderDisclosureStyle: DisclosureGroupStyle {
    let name: String
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button { configuration.isExpanded.toggle() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .regular))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary).frame(width: 20, height: 30)
                        .contentShape(Rectangle())
                }.buttonStyle(RowFeedbackStyle())
                    .accessibilityLabel("\(configuration.isExpanded ? "收起" : "展开")\(name)")
                    .accessibilityValue(configuration.isExpanded ? "已展开" : "已收起")
                configuration.label
            }
            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: 0) { configuration.content }
                    .padding(.leading, 18)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.11))
                            .frame(width: 1).padding(.leading, 9).padding(.vertical, 3)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
            }
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var model: LibraryModel
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Color.accentColor.opacity(0.08)).frame(width: 100, height: 100)
                Image(systemName: "photo.stack").font(.system(size: 43, weight: .light)).foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 9) {
                Text("给每一张照片，一个位置").font(.system(size: 25, weight: .semibold))
                Text("从一个本地文件夹开始，浏览、评分，整理你的回忆。\n照片保持原位，所有标记只保存在这台 Mac 上。")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            }
            Button { model.addFolder() } label: { Label("添加照片文件夹", systemImage: "folder.badge.plus").padding(.horizontal, 12).padding(.vertical, 5) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.repository == nil)
            HStack(spacing: 22) {
                Label("原片只读", systemImage: "lock.shield")
                Label("0–5 星分级", systemImage: "star")
                Label("完全本地", systemImage: "internaldrive")
            }.font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 6)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SidebarCreateButton: View {
    let title: String
    let placeholder: String
    let create: (String) -> Void
    @State private var presented = false
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Button { presented = true } label: {
            Image(systemName: "plus.circle").font(.system(size: 13))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(RowFeedbackStyle()).foregroundStyle(.secondary)
        .help(title).accessibilityLabel(title)
        .popover(isPresented: $presented, arrowEdge: .trailing) {
            NamePromptView(request: NamePrompt(title: title, value: "", placeholder: placeholder, completion: create), compact: true) {
                presented = false
            }
            .preferredColorScheme(colorScheme)
        }
    }
}

private struct NamePromptView: View {
    let request: NamePrompt
    let close: () -> Void
    let compact: Bool
    @State private var name: String
    @FocusState private var focused: Bool
    init(request: NamePrompt, compact: Bool = false, close: @escaping () -> Void) {
        self.request = request
        self.compact = compact
        self.close = close
        _name = State(initialValue: request.value)
    }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 20) {
            Text(request.title).font(.system(size: compact ? 13 : 18, weight: .medium))
            TextField(request.placeholder.isEmpty ? "输入名称" : request.placeholder, text: $name)
                .textFieldStyle(.roundedBorder).focused($focused).accessibilityLabel("名称")
                .onSubmit { submit() }
            HStack(spacing: 12) {
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button(compact ? "创建" : "确定", action: submit).keyboardShortcut(.defaultAction).disabled(trimmed.isEmpty)
            }
        }
        .controlSize(compact ? .small : .regular)
        .padding(compact ? 14 : 28).frame(width: compact ? 248 : 360)
        .onAppear { focused = true }
    }
    private func submit() {
        guard !trimmed.isEmpty else { return }
        close()
        request.completion(trimmed)
    }
}

struct QuickSettingsMenu: View {
    @EnvironmentObject private var model: LibraryModel
    var body: some View {
        Menu {
            Toggle("显示照片名称", isOn: $model.showNames)
            Toggle("按日期分组", isOn: grouping(byDay: true))
            Toggle("按月份分组", isOn: grouping(byDay: false))
            Divider()
            Toggle("显示左侧栏", isOn: $model.sidebar)
        } label: {
            Image(systemName: "gearshape").font(.system(size: 13))
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("常用设置").accessibilityLabel("常用设置")
    }
    private func grouping(byDay: Bool) -> Binding<Bool> {
        Binding(get: { model.dateGrouping && model.dateGroupingByDay == byDay }, set: { enabled in
            if enabled { model.dateGroupingByDay = byDay }
            model.dateGrouping = enabled
        })
    }
}
