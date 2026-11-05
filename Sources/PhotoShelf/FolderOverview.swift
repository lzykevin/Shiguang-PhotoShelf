import SwiftUI
import PhotoLibraryCore

private struct FolderCover: Identifiable {
    let source: PhotoSource
    let path: String
    let photos: [Photo]
    var id: String { source.id.uuidString + "/" + path }
    var name: String { path.isEmpty ? source.name : (path as NSString).lastPathComponent }
}

struct FolderOverview: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.colorScheme) private var scheme
    private var p: DesignPalette { DesignPalette(dark: scheme == .dark) }
    private var folders: [FolderCover] {
        let grouped = Dictionary(grouping: model.snapshot.photos, by: \.sourceID)
        return model.sortedSources.filter { model.folderSourceID == nil || model.folderSourceID == $0.id }.flatMap { source -> [FolderCover] in
            let photos = (grouped[source.id] ?? []).sorted { $0.sortDate > $1.sortDate }
            @MainActor func orderedPaths(_ nodes: [FolderNode]) -> [String] {
                model.sortedFolders(nodes, source: source.id).flatMap { [$0.path] + orderedPaths($0.children) }
            }
            let paths = [""] + (model.folderIncludesSubfolders ? orderedPaths(model.folderNodes[source.id] ?? []) : [])
            return paths.map { path in
                FolderCover(source: source, path: path, photos: path.isEmpty ? photos : photos.filter { $0.relativePath.hasPrefix(path + "/") })
            }
        }.filter { model.folderSearch.isEmpty || ($0.name + " " + $0.source.name + " " + $0.path).localizedStandardContains(model.folderSearch) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("文件夹总览").font(.system(size: 15, weight: .semibold))
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(p.muted)
                    TextField("搜索文件夹", text: $model.folderSearch).textFieldStyle(.plain).accessibilityLabel("搜索文件夹")
                    if !model.folderSearch.isEmpty { Button { model.folderSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.font(.system(size: 12)).padding(.horizontal, 10).frame(width: 210, height: 30)
                    .background(p.raised.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                Button { model.addFolder() } label: { Label("关联文件夹", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).disabled(model.scanning)
                QuickSettingsMenu()
            }.padding(.horizontal, 24).padding(.top, 28).frame(height: 72)
            Divider()
            HStack(spacing: 16) {
                Text("\(folders.count) 个文件夹").font(.system(size: 12, weight: .medium)).monospacedDigit()
                Text("原片保留原位 · 点击封面浏览照片").font(.system(size: 11)).foregroundStyle(p.muted)
                Spacer()
                FolderSortMenu()
                Toggle("包含子文件夹", isOn: $model.folderIncludesSubfolders).toggleStyle(.checkbox).font(.system(size: 11))
                Picker("来源", selection: $model.folderSourceID) {
                    Text("所有来源").tag(nil as UUID?)
                    ForEach(model.snapshot.sources) { Text($0.name).tag(Optional($0.id)) }
                }.labelsHidden().frame(width: 140)
            }.padding(.horizontal, 24).frame(height: 52)
            if folders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(p.muted)
                    Text(model.folderSearch.isEmpty ? "把照片所在的文件夹连接到拾光" : "没有匹配的文件夹").font(.system(size: 15, weight: .medium))
                    Text(model.folderSearch.isEmpty ? "无需导入或复制，目录结构与原片保持不变。" : "试试其他名称，或切换来源范围。").font(.system(size: 12)).foregroundStyle(p.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 290), spacing: 22)], alignment: .leading, spacing: 28) {
                        ForEach(folders) { folder in
                            FolderCoverCard(folder: folder, offline: model.offline.contains(folder.source.id)) {
                                model.navigation = .source(folder.source.id, folder.path)
                            }.modifier(FolderReorder(source: folder.source.id, path: folder.path))
                        }
                    }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 28)
                }
            }
        }.background(p.canvas)
    }
}

private struct FolderCoverCard: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let folder: FolderCover
    let offline: Bool
    let action: () -> Void
    @State private var hovered = false
    private var p: DesignPalette { DesignPalette(dark: scheme == .dark) }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geometry in
                    let covers = Array(folder.photos.prefix(4))
                    ZStack {
                        p.raised
                        if covers.isEmpty {
                            Image(systemName: "folder").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(p.muted)
                        } else {
                            HStack(spacing: 3) {
                                tile(covers[0]).frame(width: covers.count == 1 ? geometry.size.width : geometry.size.width * 0.62)
                                if covers.count > 1 {
                                    VStack(spacing: 3) {
                                        ForEach(Array(covers.dropFirst())) { tile($0).frame(maxHeight: .infinity) }
                                    }
                                }
                            }
                        }
                        LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                        VStack { Spacer(); HStack {
                            Image(systemName: "folder.fill")
                            Spacer()
                            Text("\(folder.photos.count) 张").monospacedDigit()
                        }.font(.system(size: 11, weight: .medium)).foregroundStyle(.white).padding(12) }
                    }.clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(hovered ? p.accent.opacity(0.65) : p.line, lineWidth: 1) }
                        .shadow(color: .black.opacity(hovered ? 0.12 : 0.04), radius: hovered ? 8 : 3, y: 3)
                }.aspectRatio(1.4, contentMode: .fit)
                HStack(spacing: 6) {
                    Text(folder.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium)).foregroundStyle(p.accent).opacity(hovered ? 1 : 0)
                }
                HStack(spacing: 5) {
                    Circle().fill(offline ? Color.orange : Color.green.opacity(0.75)).frame(width: 5, height: 5)
                    Text(offline ? "来源离线 · 可浏览缓存" : folder.path.isEmpty ? "已关联 · 含子文件夹照片" : folder.source.name + " / " + folder.path)
                        .font(.system(size: 10)).foregroundStyle(p.muted).lineLimit(1).truncationMode(.middle)
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Color.primary)
            .onHover { hovered = $0 }.animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .help(folder.source.path + (folder.path.isEmpty ? "" : "/" + folder.path))
            .accessibilityLabel("\(folder.name)，\(folder.photos.count) 张照片\(offline ? "，来源离线" : "")，打开文件夹")
    }
    private func tile(_ photo: Photo) -> some View {
        FolderCoverImage(photo: photo, url: model.url(for: photo), key: model.cacheKey(photo))
    }
}

private struct FolderCoverImage: View {
    let photo: Photo
    let url: URL?
    let key: String
    @State private var image: NSImage?
    @State private var operation: Operation?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.secondary.opacity(0.08)
                if let image { Image(nsImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped() }
            }
        }.task(id: key) {
            operation?.cancel()
            operation = ThumbnailService.shared.load(url: url, key: key) { image = $0 }
        }.onDisappear { operation?.cancel() }
    }
}
