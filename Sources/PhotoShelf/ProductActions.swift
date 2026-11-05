import AppKit
import PhotoLibraryCore

extension LibraryModel {
    func configureNavigation() {
        filtersPresented = false; sortingPresented = false
        clearFilters()
        if case .album(let id) = navigation, let query = snapshot.albums.first(where: { $0.id == id })?.query {
            favoritesOnly = query.favoritesOnly
            search = query.search; ratingFilters = query.ratings; ratingFilter = query.rating
            formatFilters = query.formats; formatFilter = query.format; tagFilters = query.selectedTags; sourceFilters = query.sources
            availabilityFilters = query.availability; sort = query.sort
            if let from = query.dateFrom, let to = query.dateTo { dateFrom = from; dateTo = to.addingTimeInterval(-1); dateFilterEnabled = true }
        }
    }
    func currentQuery() -> PhotoQuery {
        var query = PhotoQuery()
        if case .album(let id) = navigation, let saved = snapshot.albums.first(where: { $0.id == id })?.query { query.navigation = saved.navigation }
        else { query.navigation = navigation }
        query.favoritesOnly = favoritesOnly
        query.search = search; query.rating = ratingFilter; query.ratings = ratingFilters
        query.formats = formatFilters; query.format = formatFilter; query.selectedTags = tagFilters; query.sources = sourceFilters
        query.availability = availabilityFilters; query.offlineSources = offline; query.sort = sort
        if dateFilterEnabled {
            query.dateFrom = Calendar.current.startOfDay(for: dateFrom)
            query.dateTo = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: dateTo))
        }
        return query
    }
    var advancedFilterCount: Int {
        (sourceFilters.isEmpty ? 0 : 1) + (availabilityFilters.isEmpty ? 0 : 1)
        + (formatFilters.isEmpty && formatFilter == "全部格式" ? 0 : 1)
        + (tagFilters.isEmpty ? 0 : 1) + (dateFilterEnabled ? 1 : 0)
    }
    var dateFilterLabel: String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: dateFrom) + " – " + formatter.string(from: dateTo)
    }
    func clearAdvancedFilters() {
        sourceFilters = []; availabilityFilters = []; formatFilters = []
        formatFilter = "全部格式"; tagFilters = []; dateFilterEnabled = false
    }
    func setDateRange(from: Date, to: Date) {
        dateFrom = Calendar.current.startOfDay(for: min(from, to))
        dateTo = Calendar.current.startOfDay(for: max(from, to))
        dateFilterEnabled = true
    }
    func chooseRating(_ value: Int?, extending: Bool) {
        ratingFilter = nil
        guard let value else { ratingFilters = []; favoritesOnly = false; return }
        if extending { if ratingFilters.contains(value) { ratingFilters.remove(value) } else { ratingFilters.insert(value) } }
        else { ratingFilters = [value] }
    }
    func saveSmartAlbum() {
        let savedQuery = currentQuery()
        prompt(title: "保存为智能相册") { [self] name in
        var album = Album(name: name); var query = savedQuery; query.offlineSources = []
        album.query = query
        editLibrary(name: "创建智能相册") { $0.albums.append(album) }
        if snapshot.albums.contains(where: { $0.id == album.id }) { navigation = .album(album.id) }
        }
    }
    func recordVisit(_ id: UUID) {
        guard let i = snapshot.photos.firstIndex(where: { $0.id == id }), let repository else { return }
        var photo = snapshot.photos[i]; photo.lastViewed = Date()
        do { try repository.savePhotos([photo]); snapshot.photos[i] = photo }
        catch { issue = "浏览记录保存失败：\(error.localizedDescription)" }
    }
    func restoreAfterViewer(_ id: UUID) {
        let results = currentQuery().apply(to:activePhotos, albums:snapshot.albums)
        visible = results
        let ids = Set(results.map(\.id))
        if ids.contains(id) { selection = [id] }
        else {
            let index = viewerQueue.firstIndex(of:id) ?? 0
            let nearby = Array(viewerQueue.dropFirst(index)) + Array(viewerQueue.prefix(index).reversed())
            selection = nearby.first(where: { ids.contains($0) }).map { [$0] } ?? results.first.map { [$0.id] } ?? []
        }
    }
    func importFolders(_ urls: [URL]) {
        guard !scanning else { issue = "请等待当前扫描结束后再添加文件夹。"; return }
        for url in urls {
            guard (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true else { issue = "请拖入照片文件夹。"; continue }
            addFolder(url:url)
        }
        startScan()
    }
    func openExternally(_ photo: Photo) {
        guard let url = url(for:photo) else { issue = "来源离线或文件缺失，无法打开原片。"; return }
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath:"/Applications"); panel.allowedContentTypes = [.application]
        panel.message = "选择用于打开照片的应用"; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let application = panel.url else { return }
        NSWorkspace.shared.open([url], withApplicationAt:application, configuration:NSWorkspace.OpenConfiguration()) { _,error in
            if let error { Task { @MainActor in self.issue = error.localizedDescription } }
        }
    }
    func exportOriginals() {
        guard !exporting else { return }
        let photos = selectedPhotos
        guard !photos.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.prompt = "导出副本"; panel.message = "复制原始文件，不修改原片；同名文件自动避让。"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let inputs = photos.map { ($0.filename, url(for:$0)) }
        let progress = Progress(totalUnitCount: Int64(inputs.count))
        exportProgress = progress; exportCompleted = 0; exportTotal = inputs.count; exporting = true
        Task {
            let report = await Task.detached(priority:.utility) {
                OriginalExporter.copy(inputs, to:destination, progress:progress) { completed in
                    Task { @MainActor in
                        guard self.exportProgress === progress else { return }
                        self.exportCompleted = completed
                    }
                }
            }.value
            exporting = false; exportProgress = nil
            issue = "已导出 \(report.success) 张。" + (report.unprocessed > 0 ? "\n已取消，尚未处理 \(report.unprocessed) 张；已导出的副本保留。" : "") + (report.failures.isEmpty ? "" : "\n未导出：\n" + report.failures.joined(separator:"\n"))
        }
    }
    func sharePhotos() {
        let photos = selectedPhotos, urls = selectedPhotos.compactMap { url(for:$0) }
        guard urls.count == photos.count, !urls.isEmpty else { issue = "所选照片中存在离线或缺失原片，请先恢复来源。"; return }
        guard let view = NSApp.keyWindow?.contentView else { return }
        NSSharingServicePicker(items:urls).show(relativeTo:NSRect(x:view.bounds.midX,y:view.bounds.midY,width:1,height:1),of:view,preferredEdge:.minY)
    }
}

enum OriginalExporter {
    static func copy(_ inputs: [(String,URL?)], to destination: URL, progress: Progress? = nil, onProgress: (Int) -> Void = { _ in }) -> (success:Int, failures:[String], unprocessed:Int) {
        let scoped = destination.startAccessingSecurityScopedResource(); defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        var success = 0, failures: [String] = []
        var processed = 0
        for (name,url) in inputs {
            if progress?.isCancelled == true { break }
            defer {
                processed += 1
                progress?.completedUnitCount = Int64(processed)
                onProgress(processed)
            }
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { failures.append("\(name)：无效文件名"); continue }
            guard let url else { failures.append("\(name)：来源离线或文件缺失"); continue }
            let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
            var target = destination.appendingPathComponent(name), suffix = 1
            while FileManager.default.fileExists(atPath:target.path) {
                target = destination.appendingPathComponent("\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")); suffix += 1
            }
            do { try FileManager.default.copyItem(at:url,to:target); success += 1 }
            catch { failures.append("\(name)：\(error.localizedDescription)") }
        }
        return (success,failures,inputs.count - processed)
    }
}
