import AppKit
import SwiftUI
import PhotoLibraryCore
import UniformTypeIdentifiers

@MainActor final class LibraryModel: ObservableObject {
    @Published var namePrompt: NamePrompt?
    @Published var comparisonIDs: [UUID] = []
    var canCompare: Bool { (2...4).contains(selection.count) && viewerID == nil && comparisonIDs.isEmpty }
    func beginComparison() {
        guard canCompare else { return }
        comparisonIDs = visible.filter { selection.contains($0.id) }.map(\.id)
    }
    private(set) var folderNodes: [UUID: [FolderNode]] = [:]
    private var folderPaths: [UUID: Set<String>] = [:]
    @Published var snapshot = LibrarySnapshot() { didSet { rebuildFolderNodes() } }
    private func rebuildFolderNodes() {
        var paths: [UUID: Set<String>] = [:]
        for photo in snapshot.photos {
            let path = (photo.relativePath as NSString).deletingLastPathComponent
            if !path.isEmpty { paths[photo.sourceID, default: []].insert(path) }
        }
        if paths != folderPaths {
            folderPaths = paths
            folderNodes = paths.mapValues { FolderNode.nodes(paths: $0) }
        }
    }
    @Published var visible: [Photo] = []
    @Published var selection = Set<UUID>()
    @Published var navigation: LibrarySelection = .all {
        didSet {
            guard navigation != oldValue else { return }
            if !restoringNavigation {
                backHistory.append(oldValue)
                if backHistory.count > 100 { backHistory.removeFirst() }
                forwardHistory.removeAll()
            }
            configureNavigation(); scheduleQuery()
        }
    }
    @Published private(set) var backHistory: [LibrarySelection] = []
    @Published private(set) var forwardHistory: [LibrarySelection] = []
    private var restoringNavigation = false
    @Published var folderSearch = ""
    @Published var folderSourceID: UUID?
    @Published var folderIncludesSubfolders = false
    var canNavigateBack: Bool { !backHistory.isEmpty && viewerID == nil && namePrompt == nil && !filterPopoverPresented }
    var canNavigateForward: Bool { !forwardHistory.isEmpty && viewerID == nil && namePrompt == nil && !filterPopoverPresented }
    func navigateBack() {
        guard canNavigateBack, let target = backHistory.popLast() else { return }
        forwardHistory.append(navigation)
        restoringNavigation = true; navigation = target; restoringNavigation = false
    }
    func navigateForward() {
        guard canNavigateForward, let target = forwardHistory.popLast() else { return }
        backHistory.append(navigation)
        restoringNavigation = true; navigation = target; restoringNavigation = false
    }
    @Published var search = "" { didSet { scheduleQuery() } }
    @Published var favoritesOnly = false { didSet { scheduleQuery() } }
    @Published var ratingFilters = Set<Int>() { didSet { scheduleQuery() } }
    @Published var sourceFilters = Set<UUID>() { didSet { scheduleQuery() } }
    @Published var availabilityFilters = Set<String>() { didSet { scheduleQuery() } }
    @Published var ratingFilter: Int? { didSet { scheduleQuery() } }
    @Published var formatFilters = Set<String>() { didSet { scheduleQuery() } }
    @Published var formatFilter = "全部格式" { didSet { scheduleQuery() } }
    @Published var tagFilters = Set<String>() { didSet { scheduleQuery() } }
    @Published var dateFilterEnabled = false { didSet { scheduleQuery() } }
    @Published var dateFrom = Calendar.current.date(byAdding: .year, value: -1, to: Date())! { didSet { scheduleQuery() } }
    @Published var dateTo = Date() { didSet { scheduleQuery() } }
    @Published var sort: PhotoSort = .dateDescending { didSet { UserDefaults.standard.set(sort.rawValue, forKey: "productSort"); scheduleQuery() } }
    @Published var scanning = false
    @Published var scanCount = 0
    @Published var scanName = ""
    @Published var offline = Set<UUID>()
    @Published var exporting = false
    @Published var exportCompleted = 0
    @Published var exportTotal = 0
    var exportProgress: Progress?
    @Published var issue: String?
    @Published var scanWarnings: [String] = []
    @Published var viewerID: UUID? { didSet { if let id = viewerID { recordVisit(id) } else if oldValue != nil { restoreAfterViewer(oldValue!) } } }
    @Published var viewerQueue: [UUID] = []
    var viewerAllIDs: [UUID] = []
    var viewerSelectedIDs: [UUID] = []
    @Published var slideshowRandom = UserDefaults.standard.bool(forKey: "slideshowRandom") {
        didSet { UserDefaults.standard.set(slideshowRandom, forKey: "slideshowRandom"); rebuildPlaybackQueue() }
    }
    @Published var slideshowLoop = UserDefaults.standard.bool(forKey: "slideshowLoop") {
        didSet { UserDefaults.standard.set(slideshowLoop, forKey: "slideshowLoop") }
    }
    @Published var slideshowSelectedOnly = false {
        didSet { rebuildPlaybackQueue() }
    }
    var viewerPhotos: [Photo] { let lookup = Dictionary(uniqueKeysWithValues:snapshot.photos.map { ($0.id,$0) }); return viewerQueue.compactMap { lookup[$0] } }
    @Published var inspector = false
    @Published var sidebar = true
    @Published var thumbnailSize: Double = 206
    @Published var gridLayout = "grid"
    @Published var showNames = UserDefaults.standard.object(forKey: "showPhotoNames") as? Bool ?? true
    @Published var folderSort = UserDefaults.standard.string(forKey: "folderSort") ?? "name" { didSet { UserDefaults.standard.set(folderSort, forKey: "folderSort") } }
    @Published var folderOrder = UserDefaults.standard.dictionary(forKey: "folderOrder") as? [String: [String]] ?? [:] { didSet { UserDefaults.standard.set(folderOrder, forKey: "folderOrder") } }
    var folderCreationCache: [String: Date] = [:]
    @Published var dateGrouping = true
    @Published var dateGroupingByDay = false
    @Published var filtersPresented = false
    @Published var sortingPresented = false
    @Published var filterPopoverPresented = false
    @Published var isQuerying = false
    @Published var inspectorWidth: CGFloat = 280
    @Published var sidebarWidth: CGFloat = 216
    let undoManager = UndoManager()
    let repository: LibraryRepository?
    private var scanTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var monitor: FolderMonitor?
    private var accessURLs: [UUID: URL] = [:]
    private var scanAgain = false
    private var pendingScanPaths: Set<String> = []
    private var watchedPaths: [String] = []
    private var checkedOnLaunch = false
    private var revision = 0

    init(directory: URL? = nil) {
        do {
            let dataDirectory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PhotoShelf")
            let repository = try LibraryRepository(directory: dataDirectory)
            let loaded = try repository.load()
            self.repository = repository
            snapshot = loaded
        } catch { repository = nil; issue = "无法打开本地数据库：\(error.localizedDescription)。请先备份应用数据目录。" }
        thumbnailSize = UserDefaults.standard.object(forKey: "thumbnailSize") as? Double ?? 206
        gridLayout = UserDefaults.standard.string(forKey: "productGridLayout") ?? "masonry"
        dateGrouping = UserDefaults.standard.object(forKey: "dateGrouping") as? Bool ?? true
        dateGroupingByDay = UserDefaults.standard.bool(forKey: "dateGroupingByDay")
        sidebarWidth = CGFloat(UserDefaults.standard.double(forKey: "sidebarWidth")).clamped(180...300, fallback: 196)
        inspectorWidth = CGFloat(UserDefaults.standard.double(forKey: "inspectorWidth")).clamped(250...380, fallback: 264)
        sidebar = UserDefaults.standard.object(forKey:"productSidebar") as? Bool ?? true
        sort = UserDefaults.standard.string(forKey: "productSort").flatMap(PhotoSort.init(rawValue:)) ?? .dateDescending
        rebuildFolderNodes(); refreshAccess(); scheduleQuery()
    }

    var selectedPhotos: [Photo] { snapshot.photos.filter { selection.contains($0.id) } }
    var focusedPhoto: Photo? {
        let id = viewerID ?? visible.first(where: { selection.contains($0.id) })?.id
        return snapshot.photos.first { $0.id == id }
    }
    var title: String {
        switch navigation {
        case .all: return "全部照片"
        case .folders: return "文件夹总览"
        case .recent: return "最近添加"
        case .viewed: return "最近浏览"
        case .favorites: return "爱心收藏"
        case .fiveStar: return "五星精选"
        case .unrated: return "未评分"
        case .source(let id, let path): return path.isEmpty ? snapshot.sources.first { $0.id == id }?.name ?? "文件夹" : (path as NSString).lastPathComponent
        case .album(let id): return snapshot.albums.first { $0.id == id }?.name ?? "相册"
        case .tag(let tag): return tag
        }
    }
    var filterCount: Int { (favoritesOnly ? 1 : 0) + (ratingFilter == nil && ratingFilters.isEmpty ? 0 : 1) + (sourceFilters.isEmpty ? 0 : 1) + (availabilityFilters.isEmpty ? 0 : 1) + (formatFilter == "全部格式" && formatFilters.isEmpty ? 0 : 1) + (tagFilters.isEmpty ? 0 : 1) + (dateFilterEnabled ? 1 : 0) }
    func url(for photo: Photo) -> URL? { offline.contains(photo.sourceID) || photo.missing ? nil : accessURLs[photo.sourceID]?.appendingPathComponent(photo.relativePath) }
    func cacheKey(_ photo: Photo) -> String { "\(photo.id)-\(photo.modifiedDate.timeIntervalSince1970)-\(photo.byteSize)" }

    var activeSources: [PhotoSource] { snapshot.sources.filter { !$0.isDetached } }
    var activePhotos: [Photo] {
        let ids = Set(activeSources.map(\.id))
        return snapshot.photos.filter { ids.contains($0.sourceID) }
    }

    func scheduleQuery() {
        queryTask?.cancel()
        let query = currentQuery()
        let photos = activePhotos, albums = snapshot.albums
        revision += 1; let token = revision
        isQuerying = true
        queryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) { query.apply(to: photos, albums: albums) }.value
            guard !Task.isCancelled, let self, self.revision == token else { return }
            self.isQuerying = false
            guard self.comparisonIDs.isEmpty else { return }
            self.visible = results
            // Keep a currently reviewed photo in the inspector even when its rating
            // causes it to leave a filtered grid. Closing review returns to the results.
            if self.viewerID == nil { self.selection.formIntersection(Set(results.map(\.id))) }
        }
    }
    func clearFilters() {
        favoritesOnly = false
        ratingFilters = []; sourceFilters = []; availabilityFilters = []; ratingFilter = nil; formatFilters = []; formatFilter = "全部格式"; tagFilters = []; dateFilterEnabled = false; search = ""
    }
    func selectPhoto(_ id: UUID) { selection = [id] }
    func openViewer(_ id: UUID? = nil) {
        if let id = id ?? visible.first(where: { selection.contains($0.id) })?.id ?? visible.first?.id {
            viewerAllIDs = visible.map(\.id)
            viewerSelectedIDs = viewerAllIDs.filter { selection.contains($0) }
            slideshowSelectedOnly = false
            viewerQueue = viewerAllIDs
            selection = [id]; viewerID = id
            rebuildPlaybackQueue()
        }
    }
    func step(_ delta: Int) {
        let visible = viewerID == nil ? self.visible : viewerPhotos
        guard !visible.isEmpty else { return }
        let current = viewerID ?? visible.first(where: { selection.contains($0.id) })?.id
        let index = visible.firstIndex { $0.id == current } ?? (delta > 0 ? -1 : 1)
        let targetIndex = index + delta
        let nextIndex = viewerID != nil && slideshowLoop
            ? (targetIndex % visible.count + visible.count) % visible.count
            : min(max(targetIndex, 0), visible.count - 1)
        let next = visible[nextIndex]
        selection = [next.id]
        if viewerID != nil { viewerID = next.id }
    }

    var favoriteTargets: [Photo] {
        if let id = viewerID { return snapshot.photos.filter { $0.id == id } }
        return selectedPhotos
    }
    var allTargetsFavorite: Bool { !favoriteTargets.isEmpty && favoriteTargets.allSatisfy(\.isFavorite) }
    func toggleFavorite(ids: Set<UUID>? = nil) {
        let targets = ids ?? Set(favoriteTargets.map(\.id))
        let photos = snapshot.photos.filter { targets.contains($0.id) }
        guard !photos.isEmpty else { return }
        let value = !photos.allSatisfy(\.isFavorite)
        editPhotos(ids: targets, name: value ? "添加收藏" : "取消收藏") { $0.isFavorite = value }
    }
    func setRating(_ value: Int, ids targets: Set<UUID>? = nil) {
        let ids = targets ?? viewerID.map { Set([$0]) } ?? selection
        editPhotos(ids: ids, name: "设置星级") { $0.rating = min(max(value, 0), 5) }
    }
    func addTag(_ name: String, to ids: Set<UUID>? = nil) {
        let tag = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        let target = ids ?? selection
        editLibrary(name: "添加标签") { state in
            if !state.tags.contains(tag) { state.tags.append(tag); state.tags.sort() }
            for i in state.photos.indices where target.contains(state.photos[i].id) {
                if !state.photos[i].tags.contains(tag) { state.photos[i].tags.append(tag) }
            }
        }
    }
    func removeTag(_ tag: String, ids: Set<UUID>) { editPhotos(ids: ids, name: "移除标签") { $0.tags.removeAll { $0 == tag } } }
    func renameTag(_ tag: String) {
        prompt(title: "重命名标签", value: tag) { [self] replacement in
        guard replacement != tag else { return }
        editLibrary(name: "重命名标签") { state in
            state.tags.removeAll { $0 == tag }; if !state.tags.contains(replacement) { state.tags.append(replacement) }; state.tags.sort()
            for i in state.photos.indices where state.photos[i].tags.contains(tag) {
                state.photos[i].tags = Array(Set(state.photos[i].tags.map { $0 == tag ? replacement : $0 })).sorted()
            }
            for i in state.albums.indices {
                guard var query = state.albums[i].query else { continue }
                if query.selectedTags.remove(tag) != nil { query.selectedTags.insert(replacement) }
                if query.navigation == .tag(tag) { query.navigation = .tag(replacement) }
                state.albums[i].query = query
            }
        }
        guard !snapshot.tags.contains(tag), snapshot.tags.contains(replacement) else { return }
        if tagFilters.remove(tag) != nil { tagFilters.insert(replacement) }
        if navigation == .tag(tag) { navigation = .tag(replacement) }
        }
    }
    func deleteTag(_ tag: String) {
        guard confirm(title: "删除标签“\(tag)”？", message: "将从所有照片移除此标签。照片文件保持原位。") else { return }
        editLibrary(name: "删除标签") { state in
            state.tags.removeAll { $0 == tag }
            for i in state.photos.indices { state.photos[i].tags.removeAll { $0 == tag } }
        }
        if navigation == .tag(tag) { navigation = .all }
    }
    func createAlbum() {
        prompt(title: "新建相册", placeholder: "例如：旅行精选") { [weak self] name in
            self?.createAlbum(named: name)
        }
    }
    func createAlbum(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let album = Album(name: name)
        editLibrary(name: "新建相册") { $0.albums.append(album) }
        if snapshot.albums.contains(where: { $0.id == album.id }) { navigation = .album(album.id) }
    }
    func renameAlbum(_ album: Album) {
        prompt(title: "重命名相册", value: album.name) { [self] name in
        editLibrary(name: "重命名相册") { state in if let i = state.albums.firstIndex(where: { $0.id == album.id }) { state.albums[i].name = name } }
        }
    }
    func deleteAlbum(_ album: Album) {
        guard confirm(title: "删除相册“\(album.name)”？", message: "仅移除虚拟相册及成员关系，原片和评分不受影响。") else { return }
        editLibrary(name: "删除相册") { state in
            state.albums.removeAll { $0.id == album.id }
            for i in state.photos.indices { state.photos[i].albumIDs.removeAll { $0 == album.id } }
        }
        if navigation == .album(album.id) { navigation = .all }
    }
    func addToAlbum(_ album: Album) { guard snapshot.albums.contains(where: { $0.id == album.id && $0.query == nil }) else { return }; editPhotos(ids: selection, name: "加入相册") { if !$0.albumIDs.contains(album.id) { $0.albumIDs.append(album.id) } } }
    func removeFromAlbum(_ album: Album) { guard snapshot.albums.contains(where: { $0.id == album.id && $0.query == nil }) else { return }; editPhotos(ids: selection, name: "移出相册") { $0.albumIDs.removeAll { $0 == album.id } } }
    func setNote(_ text: String, photoID: UUID) { editPhotos(ids: [photoID], name: "编辑备注") { $0.note = text } }

    private func editPhotos(ids: Set<UUID>, name: String, edit: (inout Photo) -> Void) {
        guard !ids.isEmpty, let repository else { return }
        let old = snapshot.photos.filter { ids.contains($0.id) }
        var changed = old; for i in changed.indices { edit(&changed[i]) }
        guard old != changed else { return }
        do {
            try repository.savePhotos(changed)
            let lookup = Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0) })
            var updated = snapshot
            for i in updated.photos.indices { if let photo = lookup[updated.photos[i].id] { updated.photos[i] = photo } }
            snapshot = updated
            undoManager.registerUndo(withTarget: self) { model in model.restoreAnnotations(old, name: name) }
            undoManager.setActionName(name); scheduleQuery()
        } catch { issue = "保存失败：\(error.localizedDescription)" }
    }
    private func restoreAnnotations(_ photos: [Photo], name: String) {
        let values = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        editPhotos(ids: Set(values.keys), name: name) { photo in
            guard let old = values[photo.id] else { return }
            photo.isFavorite = old.isFavorite
            photo.rating = old.rating; photo.tags = old.tags.filter { snapshot.tags.contains($0) }
            photo.note = old.note; photo.albumIDs = old.albumIDs.filter { id in snapshot.albums.contains { $0.id == id } }
        }
    }
    func editLibrary(name: String, edit: (inout LibrarySnapshot) -> Void) {
        var updated = snapshot; edit(&updated)
        let before = snapshot
        guard updated != before else { return }
        do {
            guard let repository else { throw LibraryError.unavailable("数据库不可用") }; try repository.commit(updated); snapshot = updated
            undoManager.registerUndo(withTarget: self) { $0.restoreCatalog(before, name: name) }; undoManager.setActionName(name)
            scheduleQuery()
        } catch { issue = "保存失败：\(error.localizedDescription)" }
    }
    private func restoreCatalog(_ old: LibrarySnapshot, name: String) {
        let activeAlbumID: UUID? = { if case .album(let id) = navigation { return id }; return nil }()
        let previousQuery = snapshot.albums.first { $0.id == activeAlbumID }?.query
        let annotations = Dictionary(uniqueKeysWithValues: old.photos.map { ($0.id, $0) })
        editLibrary(name: name) { state in
            state.albums = old.albums; state.tags = old.tags
            for i in state.photos.indices {
                let current = state.photos[i]
                if let oldPhoto = annotations[current.id] { state.photos[i] = current.retainingAnnotations(from: oldPhoto) }
                state.photos[i].tags.removeAll { !state.tags.contains($0) }
                state.photos[i].albumIDs.removeAll { id in !state.albums.contains { $0.id == id } }
            }
        }
        if let activeAlbumID, previousQuery != snapshot.albums.first(where: { $0.id == activeAlbumID })?.query {
            configureNavigation(); scheduleQuery()
        }
    }

    func addFolder() {
        guard repository != nil, !scanning else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true; panel.prompt = "关联文件夹"; panel.message = "照片保持原位置。应用只读取原片，评分和标签另存于本机。"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addFolder(url: url) }
        refreshAccess(); startScan()
    }
    func addFolder(url: URL) {
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        if activeSources.contains(where: { root.path == $0.path || root.path.hasPrefix($0.path + "/") }) {
            issue = "此文件夹已包含在现有照片来源中，无需重复添加。"; return
        }
        do {
            let bookmark = try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            let source = PhotoSource(name: root.lastPathComponent, path: root.path, bookmark: bookmark)
            var updated = snapshot
            guard !activeSources.contains(where: { $0.path.hasPrefix(root.path + "/") }) else {
                issue = "此目录包含已经关联的照片来源。请继续使用现有来源，或先备份整理数据并在图库设置中调整关联。现有照片和整理信息保持不变。"
                return
            }
            if let index = updated.sources.firstIndex(where: { $0.isDetached && $0.path == root.path }) {
                updated.sources[index].detached = nil
                updated.sources[index].bookmark = bookmark
            } else {
                updated.sources.append(source)
            }
            guard let repository else { throw LibraryError.unavailable("数据库不可用") }; try repository.commit(updated); snapshot = updated; undoManager.removeAllActions()
        } catch { issue = error.localizedDescription }
    }
    func promptRenameFolder(sourceID: UUID, path: String) {
        guard !scanning, !offline.contains(sourceID),
              let root = accessURLs[sourceID] else { return }
        let folder = path.isEmpty ? root : root.appendingPathComponent(path)
        prompt(title: "重命名本地文件夹", value: folder.lastPathComponent,
               placeholder: "文件夹名称") { [weak self] name in
            guard let self, name != folder.lastPathComponent else { return }
            guard Self.validFolderName(name) else {
                self.issue = "名称不能为空，不能是 . 或 ..，也不能包含 /、: 或控制字符。"; return
            }
            let panel = NSOpenPanel()
            panel.canChooseFiles = false; panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false; panel.canCreateDirectories = false
            panel.directoryURL = folder.deletingLastPathComponent()
            panel.prompt = "授权并重命名"
            panel.message = "将同步修改本地文件夹名称。请选择父目录“\(folder.deletingLastPathComponent().lastPathComponent)”以授权本次操作。照片整理信息会保留。"
            guard panel.runModal() == .OK, let parent = panel.url else { return }
            self.renameFolder(sourceID: sourceID, path: path, name: name, authorizedParent: parent)
        }
    }
    static func validFolderName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name != "." && name != ".." &&
        name.rangeOfCharacter(from: CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))) == nil
    }
    func renameFolder(sourceID: UUID, path: String, name: String, authorizedParent: URL) {
        guard !scanning else { issue = "请等待扫描完成后再重命名。"; return }
        let accessed = authorizedParent.startAccessingSecurityScopedResource()
        defer { if accessed { authorizedParent.stopAccessingSecurityScopedResource() } }
        do {
            guard Self.validFolderName(name), let repository,
                  let index = snapshot.sources.firstIndex(where: { $0.id == sourceID }),
                  let root = accessURLs[sourceID], !offline.contains(sourceID) else {
                throw LibraryError.unavailable("文件夹不可用或名称无效。")
            }
            let old = (path.isEmpty ? root : root.appendingPathComponent(path)).standardizedFileURL
            let parent = authorizedParent.standardizedFileURL.resolvingSymlinksInPath()
            guard old.deletingLastPathComponent().resolvingSymlinksInPath() == parent,
                  path.isEmpty || old.path.hasPrefix(root.standardizedFileURL.path + "/") else {
                throw LibraryError.unavailable("请选择待重命名文件夹的直接父目录。")
            }
            if old.lastPathComponent == name { return }
            let destination = parent.appendingPathComponent(name, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw LibraryError.unavailable("此位置已存在同名文件或文件夹，请换一个名称。")
            }
            let values = try old.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw LibraryError.unavailable("只能重命名真实文件夹。")
            }
            // Prepare a recovery copy before modifying the filesystem.
            try LibraryRepository.exportData(snapshot).write(to: repository.directory.appendingPathComponent("BeforeFolderRename-\(UUID().uuidString).json"), options: .atomic)
            let prefix = path.isEmpty ? "" : (path as NSString).deletingLastPathComponent
            let newPath = prefix.isEmpty ? name : prefix + "/" + name
            func remap(_ value: String) -> String {
                guard !path.isEmpty else { return value }
                if value == path { return newPath }
                if value.hasPrefix(path + "/") { return newPath + value.dropFirst(path.count) }
                return value
            }
            var updated = snapshot
            if path.isEmpty {
                updated.sources[index].name = name; updated.sources[index].path = destination.path
            } else {
                for i in updated.photos.indices where updated.photos[i].sourceID == sourceID {
                    updated.photos[i].relativePath = remap(updated.photos[i].relativePath)
                }
            }
            try FileManager.default.moveItem(at: old, to: destination)
            do {
                if path.isEmpty {
                    updated.sources[index].bookmark = try destination.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                }
                try repository.commit(updated)
            } catch {
                do { try FileManager.default.moveItem(at: destination, to: old) }
                catch { throw LibraryError.unavailable("整理数据保存失败，文件夹也未能恢复。新位置：\(destination.path)。请重新关联此位置；重命名前备份已保留。") }
                throw error
            }
            snapshot = updated
            func remapSelection(_ value: LibrarySelection) -> LibrarySelection {
                if case let .source(id, relative) = value, id == sourceID { return .source(id, remap(relative)) }
                return value
            }
            backHistory = backHistory.map(remapSelection); forwardHistory = forwardHistory.map(remapSelection)
            restoringNavigation = true; navigation = remapSelection(navigation); restoringNavigation = false
            let keyPrefix = sourceID.uuidString + "|"
            func remapKey(_ key: String) -> String {
                key.hasPrefix(keyPrefix) ? keyPrefix + remap(String(key.dropFirst(keyPrefix.count))) : key
            }
            folderOrder = Dictionary(uniqueKeysWithValues: folderOrder.map { (remapKey($0.key), $0.value.map(remapKey)) })
            folderCreationCache.removeAll()
            // Old undo snapshots contain pre-rename paths and must not restore them.
            undoManager.removeAllActions()
            refreshAccess(); scheduleQuery()
        } catch { issue = "重命名失败：" + error.localizedDescription }
    }

    func rebind(_ source: PhotoSource) {
        guard !scanning else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = "选择“\(source.name)”对应的原文件夹。仅在能确认文件身份时保留关联；无法匹配的旧照片将显示缺失。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        guard !activeSources.contains(where: { $0.id != source.id && (root.path == $0.path || root.path.hasPrefix($0.path + "/") || $0.path.hasPrefix(root.path + "/")) }) else {
            issue = "选择的目录与另一个照片来源重叠。"; return
        }
        do {
            var updated = snapshot
            guard let i = updated.sources.firstIndex(where: { $0.id == source.id }) else { return }
            updated.sources[i].detached = nil
            updated.sources[i].path = root.path
            updated.sources[i].bookmark = try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            guard let repository else { throw LibraryError.unavailable("数据库不可用") }; try repository.commit(updated); snapshot = updated
            refreshAccess(); startScan()
        } catch { issue = error.localizedDescription }
    }
    func removeSource(_ source: PhotoSource) {
        guard !scanning, confirm(title: "移除来源“\(source.name)”？", message: "将隐藏此来源并停止扫描。评分、标签、备注、收藏和相册关联全部保留，重新添加同一文件夹即可恢复。原照片不会删除，移除前仍会自动备份。") else { return }
        detachSource(source)
    }

    func detachSource(_ source: PhotoSource) {
        guard !scanning, let index = snapshot.sources.firstIndex(where: { $0.id == source.id }), !snapshot.sources[index].isDetached else { return }
        do {
            guard let directory = repository?.directory else { throw LibraryError.unavailable("数据库不可用") }
            try LibraryRepository.exportData(snapshot).write(to: directory.appendingPathComponent("BeforeDetach-\(UUID().uuidString).json"), options: .atomic)
        } catch { issue = "解绑前备份失败，来源已保留：\(error.localizedDescription)"; return }
        var updated = snapshot; updated.sources[index].detached = true
        updated.sources[index].bookmark = nil
        do { guard let repository else { throw LibraryError.unavailable("数据库不可用") }; try repository.commit(updated); snapshot = updated; undoManager.removeAllActions(); navigation = .all; refreshAccess(); scheduleQuery() }
        catch { issue = error.localizedDescription }
    }
    private func refreshAccess() {
        for url in accessURLs.values { url.stopAccessingSecurityScopedResource() }
        accessURLs = [:]; offline = []
        var refreshed = snapshot
        var renewedBookmark = false
        for source in activeSources {
            do {
                var stale = false
                let url: URL
                if let bookmark = source.bookmark {
                    url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                } else { offline.insert(source.id); continue }
                _ = url.startAccessingSecurityScopedResource()
                accessURLs[source.id] = url
                if !FileManager.default.isReadableFile(atPath: url.path) { offline.insert(source.id) }
                if stale, let index = snapshot.sources.firstIndex(where: { $0.id == source.id }) {
                    refreshed.sources[index].bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                    renewedBookmark = true
                }
            } catch { offline.insert(source.id) }
        }
        if renewedBookmark {
            do {
                guard let repository else { throw LibraryError.unavailable("数据库不可用") }
                try repository.commit(refreshed); snapshot = refreshed
            } catch { issue = "文件夹授权更新未能保存：\(error.localizedDescription)" }
        }
        let paths = accessURLs.values.map(\.path).sorted()
        if paths != watchedPaths {
            watchedPaths = paths
            monitor = FolderMonitor(paths: paths) { [weak self] changed in
                guard let self else { return }
                self.pendingScanPaths.formUnion(changed)
                self.watchTask?.cancel()
                self.watchTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled, let self, !self.scanning else { return }
                    let paths = self.pendingScanPaths; self.pendingScanPaths = []
                    self.startScan(changedPaths: paths)
                }
            }
        }
    }

    func checkLibraryOnLaunch() {
        guard !checkedOnLaunch else { return }
        checkedOnLaunch = true
        if !activeSources.isEmpty { startScan() }
    }

    func startScan(changedPaths: Set<String>? = nil) {
        guard repository != nil else { return }
        if scanning {
            if let changedPaths { pendingScanPaths.formUnion(changedPaths) }
            else { scanAgain = true }
            return
        }
        do { try LibraryRepository.validate(snapshot) }
        catch { issue = "索引检查失败：\(error.localizedDescription)"; return }
        refreshAccess()
        scanning = true; scanCount = 0; scanWarnings = []; scanAgain = false
        let sources = activeSources
        scanTask = Task { [weak self] in
            guard let self else { return }
            for source in sources {
                guard !Task.isCancelled else { break }
                guard let root = self.accessURLs[source.id], !self.offline.contains(source.id) else { continue }
                let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
                let scopes: [String]
                if let changedPaths {
                    scopes = PhotoScanner.normalizedScopes(changedPaths.compactMap { path in
                        let path = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
                        if path == rootPath { return "" }
                        if path.hasPrefix(rootPath + "/") { return String(path.dropFirst(rootPath.count + 1)) }
                        return nil
                    })
                    if scopes.isEmpty { continue }
                } else { scopes = [""] }
                let existing = self.snapshot.photos.filter { $0.sourceID == source.id }
                self.scanName = source.name
                do {
                    let worker = Task.detached(priority: .utility) { [weak self] in
                        try await PhotoScanner.scan(source: source, root: root, existing: existing, relativePaths: scopes) { [weak self] batch in
                            await self?.receive(batch)
                        }
                    }
                    let identities = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    guard !Task.isCancelled else { break }
                    var updated = self.snapshot
                    var availabilityChanges: [Photo] = []
                    for i in updated.photos.indices where updated.photos[i].sourceID == source.id && PhotoScanner.covers(updated.photos[i].relativePath, scopes: scopes) {
                        let missing = !identities.contains(updated.photos[i].identity + "\u{0}" + updated.photos[i].relativePath)
                        if updated.photos[i].missing != missing {
                            updated.photos[i].missing = missing; availabilityChanges.append(updated.photos[i])
                        }
                    }
                    guard let sourceIndex = updated.sources.firstIndex(where: { $0.id == source.id }) else { continue }
                    updated.sources[sourceIndex].lastScan = Date()
                    guard let repository = self.repository else { throw LibraryError.unavailable("数据库不可用") }
                    try repository.saveScanCompletion(source: updated.sources[sourceIndex], photos: availabilityChanges)
                    self.snapshot = updated
                } catch is CancellationError { break }
                catch { self.scanWarnings.append(error.localizedDescription) }
            }
            self.scanning = false; self.scanName = ""; self.scheduleQuery()
            if !self.scanWarnings.isEmpty { self.issue = "扫描提示（已有照片仍可浏览）：\n" + self.scanWarnings.prefix(8).joined(separator: "\n") }
            let pending = self.pendingScanPaths; self.pendingScanPaths = []
            if self.scanAgain { self.startScan() }
            else if !pending.isEmpty { self.startScan(changedPaths: pending) }
        }
    }
    private func receive(_ batch: ScanBatch) {
        var updated = snapshot
        scanCount += batch.checkedCount; scanWarnings.append(contentsOf: batch.warnings)
        guard !batch.photos.isEmpty else { return }
        // Build lookup once per batch, not once per incoming photo.
        let old = Dictionary(grouping: updated.photos.indices, by: { "\(updated.photos[$0].sourceID)|\(updated.photos[$0].identity)" })
        var changed: [Photo] = []
        for photo in batch.photos {
            let candidates = old["\(photo.sourceID)|\(photo.identity)"] ?? []
            let relocated: Int? = candidates.count == 1 && candidates.first.map { index in
                guard let oldURL = accessURLs[updated.photos[index].sourceID]?.appendingPathComponent(updated.photos[index].relativePath) else { return false }
                return !FileManager.default.fileExists(atPath: oldURL.path)
            } == true ? candidates.first : nil
            let match = candidates.first { updated.photos[$0].relativePath == photo.relativePath } ?? relocated
            if let i = match {
                let merged = photo.retainingAnnotations(from: updated.photos[i])
                if merged != updated.photos[i] { updated.photos[i] = merged; changed.append(merged) }
            } else { updated.photos.append(photo); changed.append(photo) }
        }
        do { guard let repository else { throw LibraryError.unavailable("数据库不可用") }; try repository.savePhotos(changed); snapshot = updated } catch { scanWarnings.append("索引保存失败：\(error.localizedDescription)"); cancelScan() }
        // Publishing/filtering every 512 items keeps initial results usable without
        // running a full query for every metadata read.
        if scanCount <= 64 || scanCount % 512 < 64 { scheduleQuery() }
    }
    func cancelScan() { scanAgain = false; pendingScanPaths = []; watchTask?.cancel(); scanTask?.cancel() }

    func exportBackup() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "PhotoShelf-整理备份.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try LibraryRepository.exportData(snapshot).write(to: url, options: .atomic) } catch { issue = error.localizedDescription }
    }
    func importBackup() {
        guard !scanning else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try LibraryRepository.importData(Data(contentsOf: url))
            guard confirm(title: "恢复整理数据？", message: "备份包含 \(imported.photos.count) 张照片的整理信息。恢复将替换当前索引；不会修改原片。恢复后需为每个来源重新授权原文件夹。") else { return }
            // Back up the current database content before a destructive catalog replacement.
            if let directory = repository?.directory {
                try LibraryRepository.exportData(snapshot).write(to: directory.appendingPathComponent("BeforeRestore-\(Int(Date().timeIntervalSince1970)).json"), options: .atomic)
            }
            guard let repository else { throw LibraryError.unavailable("数据库不可用") }; try repository.commit(imported, replacing: true); snapshot = imported
            undoManager.removeAllActions(); navigation = .all; selection = []; viewerID = nil
            refreshAccess(); scheduleQuery()
            issue = "恢复完成。请在左侧来源菜单选择“重新授权／绑定目录”。未确认身份的照片不会自动套用评分。"
        } catch { issue = error.localizedDescription }
    }
    func reveal(_ photo: Photo) { if let url = url(for: photo) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    func savePreferences() {
        UserDefaults.standard.set(inspector,forKey:"productInspector"); UserDefaults.standard.set(sidebar,forKey:"productSidebar")
        UserDefaults.standard.set(thumbnailSize, forKey: "thumbnailSize")
        UserDefaults.standard.set(gridLayout, forKey: "productGridLayout")
        UserDefaults.standard.set(dateGrouping, forKey: "dateGrouping")
        UserDefaults.standard.set(dateGroupingByDay, forKey: "dateGroupingByDay")
        UserDefaults.standard.set(showNames, forKey: "showPhotoNames")
        UserDefaults.standard.set(Double(sidebarWidth), forKey: "sidebarWidth")
        UserDefaults.standard.set(Double(inspectorWidth), forKey: "inspectorWidth")
    }
    func prompt(title: String, value: String = "", placeholder: String = "", completion: @escaping (String) -> Void) {
        guard namePrompt == nil else { return }
        namePrompt = NamePrompt(title: title, value: value, placeholder: placeholder, completion: completion)
    }
    func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private extension CGFloat {
    func clamped(_ range: ClosedRange<CGFloat>, fallback: CGFloat) -> CGFloat { self == 0 ? fallback : Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

struct NamePrompt: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let placeholder: String
    let completion: (String) -> Void
}
