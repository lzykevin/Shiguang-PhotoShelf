import XCTest
import CoreGraphics
import ImageIO
import CryptoKit
import AppKit
import PhotoLibraryCore
@testable import PhotoShelf

@MainActor final class WorkflowTests: XCTestCase {
    func testDetachReaddPreservesAllMetadataAcrossRestartAndBackup() async throws {
        let (model, root, data) = try await scannedModel()
        let source = try XCTUnwrap(model.snapshot.sources.first)
        var state = model.snapshot
        let album = Album(name: "保留相册")
        state.albums = [album]; state.tags = ["旅行"]
        for i in state.photos.indices {
            state.photos[i].rating = 5; state.photos[i].tags = ["旅行"]
            state.photos[i].note = "完整保留"; state.photos[i].isFavorite = true
            state.photos[i].albumIDs = [album.id]
            state.photos[i].lastViewed = Date(timeIntervalSince1970: 123456)
        }
        try model.repository!.commit(state); model.snapshot = state
        model.detachSource(source)
        XCTAssertNil(model.issue)
        XCTAssertTrue(model.activeSources.isEmpty)
        XCTAssertTrue(model.activePhotos.isEmpty)
        XCTAssertEqual(model.snapshot.photos, state.photos)
        let backup = try LibraryRepository.importData(LibraryRepository.exportData(model.snapshot))
        XCTAssertTrue(backup.sources[0].isDetached)
        for original in state.photos {
            var restored = try XCTUnwrap(backup.photos.first { $0.id == original.id })
            XCTAssertEqual(restored.addedDate.timeIntervalSince1970, original.addedDate.timeIntervalSince1970, accuracy: 0.000001)
            XCTAssertEqual(restored.modifiedDate.timeIntervalSince1970, original.modifiedDate.timeIntervalSince1970, accuracy: 0.000001)
            restored.addedDate = original.addedDate; restored.modifiedDate = original.modifiedDate
            XCTAssertEqual(restored, original)
        }
        let reopened = LibraryModel(directory: data)
        XCTAssertTrue(reopened.activeSources.isEmpty)
        XCTAssertEqual(reopened.snapshot.photos.sorted { $0.id.uuidString < $1.id.uuidString }, state.photos.sorted { $0.id.uuidString < $1.id.uuidString })
        reopened.addFolder(url: root); reopened.startScan(); try await wait(reopened)
        XCTAssertNil(reopened.issue)
        XCTAssertEqual(reopened.activeSources.map(\.id), [source.id])
        XCTAssertEqual(reopened.activePhotos.count, state.photos.count)
        for original in state.photos {
            XCTAssertEqual(reopened.snapshot.photos.first { $0.id == original.id }, original)
        }
        reopened.detachSource(source)
        reopened.addFolder(url: root); reopened.startScan(); try await wait(reopened)
        XCTAssertEqual(reopened.snapshot.photos.count, state.photos.count)
        XCTAssertEqual(reopened.snapshot.albums.map(\.id), [album.id])
        model.cancelScan(); reopened.cancelScan()
    }

    func testScopedScanPreservesOtherPhotosAndAnnotations() async throws {
        let (model, root, _) = try await scannedModel()
        let a = try XCTUnwrap(model.snapshot.photos.first { $0.filename == "a.png" })
        let b = try XCTUnwrap(model.snapshot.photos.first { $0.filename == "b.png" })
        model.setRating(4, ids: [a.id])
        let old = root.appendingPathComponent("a.png"), new = root.appendingPathComponent("renamed.png")
        try FileManager.default.moveItem(at: old, to: new)
        model.startScan(changedPaths: [old.path, new.path]); try await wait(model)
        let renamed = try XCTUnwrap(model.snapshot.photos.first { $0.id == a.id })
        XCTAssertEqual(renamed.filename, "renamed.png")
        XCTAssertEqual(renamed.rating, 4); XCTAssertFalse(renamed.missing)
        XCTAssertEqual(model.snapshot.photos.first { $0.id == b.id }, b)
        XCTAssertEqual(model.scanCount, 1)
        try FileManager.default.removeItem(at: new)
        model.startScan(changedPaths: [new.path]); try await wait(model)
        XCTAssertTrue(model.snapshot.photos.first { $0.id == a.id }!.missing)
        XCTAssertFalse(model.snapshot.photos.first { $0.id == b.id }!.missing)
        XCTAssertEqual(try model.repository!.load().photos.first { $0.id == a.id }?.rating, 4)
    }

    func testWatcherAutomaticallyIndexesNewFile() async throws {
        let (model, root, _) = try await scannedModel()
        try createPhoto(root.appendingPathComponent("new.png"))
        for _ in 0..<60 {
            if model.snapshot.photos.contains(where: { $0.filename == "new.png" }) && !model.scanning { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertTrue(model.snapshot.photos.contains(where: { $0.filename == "new.png" && !$0.missing }))
        XCTAssertTrue(model.snapshot.photos.allSatisfy { !$0.missing })
        model.cancelScan()
    }

    func testPlaybackScopeOrderAndLoop() async throws {
        let (model, _, _) = try await scannedModel()
        let oldRandom = model.slideshowRandom, oldLoop = model.slideshowLoop
        defer { model.slideshowRandom = oldRandom; model.slideshowLoop = oldLoop }
        model.slideshowRandom = false; model.slideshowLoop = false
        let ids = model.visible.map(\.id)
        guard ids.count == 2 else { XCTFail("Expected two queried photos before playback"); return }
        model.selection = Set(ids)
        model.openViewer(ids[0])
        XCTAssertEqual(model.viewerSelectedIDs, ids)
        XCTAssertEqual(model.viewerQueue, ids)
        XCTAssertEqual(model.selection, [ids[0]])
        XCTAssertTrue(model.advancePlayback())
        XCTAssertEqual(model.viewerID, ids[1])
        XCTAssertFalse(model.advancePlayback())
        model.slideshowLoop = true
        XCTAssertTrue(model.advancePlayback())
        XCTAssertEqual(model.viewerID, ids[0])
        model.step(-1)
        XCTAssertEqual(model.viewerID, ids[1])
        model.slideshowRandom = true
        XCTAssertEqual(Set(model.viewerQueue), Set(ids))
        XCTAssertEqual(model.viewerQueue.first, ids[1])
        XCTAssertTrue(model.advancePlayback())
        let final = model.viewerID
        XCTAssertTrue(model.advancePlayback())
        XCTAssertNotEqual(model.viewerID, final)
        model.viewerID = nil
        model.selection = [ids[0]]
        model.openViewer(ids[0])
        model.slideshowSelectedOnly = true
        XCTAssertEqual(model.viewerQueue, [ids[0]])
        XCTAssertTrue(model.advancePlayback())
        XCTAssertEqual(model.viewerID, ids[0])
        model.slideshowLoop = false
        XCTAssertFalse(model.advancePlayback())
        model.slideshowSelectedOnly = false
        XCTAssertEqual(Set(model.viewerQueue), Set(ids))
        model.viewerID = nil
    }

    func testAlbumReorderingPersistsAndSupportsUndo() async throws {
        let dir = try directory()
        let model = LibraryModel(directory: dir)
        let albums = [Album(name: "A"), Album(name: "B"), Album(name: "C")]
        model.editLibrary(name: "测试相册") { $0.albums = albums }
        model.undoManager.removeAllActions()
        model.navigation = .album(albums[0].id)
        XCTAssertTrue(model.reorderAlbum(albums[0].id, relativeTo: albums[2].id, after: true))
        XCTAssertEqual(model.snapshot.albums.map(\.name), ["B", "C", "A"])
        XCTAssertEqual(model.navigation, .album(albums[0].id))
        XCTAssertEqual(try LibraryRepository(directory: dir).load().albums.map(\.name), ["B", "C", "A"])
        model.undoManager.undo()
        XCTAssertEqual(try LibraryRepository(directory: dir).load().albums.map(\.name), ["A", "B", "C"])
        model.undoManager.redo()
        XCTAssertEqual(model.snapshot.albums.map(\.name), ["B", "C", "A"])
        XCTAssertTrue(model.reorderAlbum(albums[0].id, relativeTo: albums[1].id, after: false))
        XCTAssertEqual(model.snapshot.albums.map(\.name), ["A", "B", "C"])
        XCTAssertFalse(model.reorderAlbum(albums[0].id, relativeTo: albums[0].id, after: true))
        let legacy = try JSONDecoder().decode(Album.self, from: Data("{\"id\":\"\(UUID())\",\"name\":\"旧相册\"}".utf8))
        XCTAssertNil(legacy.sortOrder)
    }

    func testComparisonKeepsQueueAndRatesOnlyTarget() async throws {
        let (model, _, _) = try await scannedModel()
        let ids = model.visible.map(\.id)
        model.selection = Set(ids)
        model.beginComparison()
        XCTAssertEqual(model.comparisonIDs, ids)
        model.setRating(5, ids: [ids[0]])
        XCTAssertEqual(model.snapshot.photos.first { $0.id == ids[0] }?.rating, 5)
        XCTAssertEqual(model.snapshot.photos.first { $0.id == ids[1] }?.rating, 0)
        model.undoManager.undo()
        XCTAssertEqual(model.snapshot.photos.first { $0.id == ids[0] }?.rating, 0)
        model.ratingFilters = [5]
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.comparisonIDs, ids)
        XCTAssertEqual(model.selection, Set(ids))
        XCTAssertEqual(model.visible.map(\.id), ids)
        model.comparisonIDs = []; model.scheduleQuery()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(model.visible.isEmpty)
    }

    func testComparisonZoomCanLinkAndUnlink() {
        let group = ComparisonZoomGroup()
        func make() -> ZoomScrollView {
            let view = ZoomScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            view.allowsMagnification = true; view.minMagnification = 0.01; view.maxMagnification = 8
            view.imagePixels = NSSize(width: 800, height: 600)
            view.imageView.image = NSImage(size: NSSize(width: 800, height: 600))
            view.canvas.addSubview(view.imageView); view.documentView = view.canvas
            view.needsLayout = true; view.layoutSubtreeIfNeeded(); group.add(view)
            return view
        }
        let first = make(), second = make()
        first.zoom(by: 2, at: NSPoint(x: 200, y: 150))
        XCTAssertEqual(first.magnification, second.magnification, accuracy: 0.01)
        let old = second.magnification
        group.enabled = false
        first.zoom(by: 1.5, at: NSPoint(x: 200, y: 150))
        XCTAssertEqual(second.magnification, old, accuracy: 0.01)
    }

    func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoShelfWorkflow-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    func createPhoto(_ url: URL) throws {
        let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
    func scannedModel() async throws -> (LibraryModel, URL, URL) {
        let base = try directory(), originals = base.appendingPathComponent("Originals"), data = base.appendingPathComponent("Data")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try createPhoto(originals.appendingPathComponent("a.png")); try createPhoto(originals.appendingPathComponent("b.png"))
        let model = LibraryModel(directory: data); model.addFolder(url: originals); model.startScan(); try await wait(model)
        XCTAssertEqual(model.snapshot.photos.count, 2); XCTAssertNil(model.issue)
        return (model, originals, data)
    }
    func wait(_ model: LibraryModel) async throws {
        for _ in 0..<500 {
            if !model.scanning && !model.isQuerying { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Scan or query timed out")
    }
    func testFullRatingTagAlbumPersistenceAndOriginalHash() async throws {
        let (model, root, data) = try await scannedModel()
        let file = root.appendingPathComponent("a.png"), hash = SHA256.hash(data: try Data(contentsOf: file))
        let ids = Set(model.snapshot.photos.map(\.id)); model.selection = ids
        model.setRating(4); model.addTag("风景"); model.setNote("这张照片值得保留", photoID: model.snapshot.photos[0].id)
        XCTAssertTrue(model.snapshot.photos.allSatisfy { $0.rating == 4 && $0.tags == ["风景"] })
        let reopened = LibraryModel(directory: data)
        XCTAssertTrue(reopened.snapshot.photos.allSatisfy { $0.rating == 4 && $0.tags == ["风景"] })
        XCTAssertEqual(reopened.snapshot.photos[0].note + reopened.snapshot.photos[1].note, "这张照片值得保留")
        XCTAssertEqual(hash, SHA256.hash(data: try Data(contentsOf: file)))
    }
    func testBatchUndoRedoPersists() async throws {
        let (model, _, _) = try await scannedModel(); model.selection = Set(model.snapshot.photos.map(\.id))
        model.undoManager.groupsByEvent = false; model.undoManager.beginUndoGrouping(); model.setRating(5); model.undoManager.endUndoGrouping()
        XCTAssertTrue(model.snapshot.photos.allSatisfy { $0.rating == 5 })
        model.undoManager.undo(); XCTAssertTrue(model.snapshot.photos.allSatisfy { $0.rating == 0 })
        model.undoManager.redo(); XCTAssertTrue(model.snapshot.photos.allSatisfy { $0.rating == 5 })
        XCTAssertTrue(try model.repository!.load().photos.allSatisfy { $0.rating == 5 })
    }
    func testExternalRenameAndMissingFilePreserveRating() async throws {
        let (model, root, _) = try await scannedModel()
        let original = model.snapshot.photos.first { $0.filename == "a.png" }!; model.selection = [original.id]; model.setRating(3)
        let new = root.appendingPathComponent("renamed.png")
        try FileManager.default.moveItem(at: root.appendingPathComponent("a.png"), to: new)
        model.startScan(); try await wait(model)
        let renamed = model.snapshot.photos.first { $0.id == original.id }!
        XCTAssertEqual(renamed.filename, "renamed.png"); XCTAssertEqual(renamed.rating, 3); XCTAssertFalse(renamed.missing)
        try FileManager.default.removeItem(at: new); model.startScan(); try await wait(model)
        XCTAssertTrue(model.snapshot.photos.first { $0.id == original.id }!.missing)
        XCTAssertEqual(model.snapshot.photos.first { $0.id == original.id }!.rating, 3)
    }
    func testParentSourceOverlapPreservesExistingAssociation() async throws {
        let (model, root, _) = try await scannedModel(); let old = model.snapshot.photos[0]
        model.selection = [old.id]; model.setRating(2)
        model.addFolder(url: root.deletingLastPathComponent())
        XCTAssertEqual(model.snapshot.sources.count, 1)
        XCTAssertEqual(model.snapshot.photos.first { $0.id == old.id }!.rating, 2)
        XCTAssertEqual(model.snapshot.photos.first { $0.id == old.id }!.relativePath, old.relativePath)
        XCTAssertEqual(model.snapshot.sources.first?.id, old.sourceID)
        XCTAssertNotNil(model.issue)
    }
    func testAnnotationUndoDoesNotRevertExternalRename() async throws {
        let (model, root, _) = try await scannedModel(); let original = model.snapshot.photos.first { $0.filename == "a.png" }!
        model.undoManager.groupsByEvent = false; model.selection = [original.id]
        model.undoManager.beginUndoGrouping(); model.setRating(5); model.undoManager.endUndoGrouping()
        try FileManager.default.moveItem(at: root.appendingPathComponent("a.png"), to: root.appendingPathComponent("new.png"))
        model.startScan(); try await wait(model); model.undoManager.undo()
        let current = model.snapshot.photos.first { $0.id == original.id }!
        XCTAssertEqual(current.filename, "new.png"); XCTAssertEqual(current.rating, 0)
    }
    func testOfflineDirectoryRetainsCatalog() async throws {
        let (model, root, _) = try await scannedModel(); model.selection = Set(model.snapshot.photos.map(\.id)); model.setRating(4)
        try FileManager.default.moveItem(at: root, to: root.deletingLastPathComponent().appendingPathComponent("Disconnected"))
        // Bookmark resolution may track same-volume moves; remove the location to emulate disconnection.
        try FileManager.default.removeItem(at: root.deletingLastPathComponent().appendingPathComponent("Disconnected"))
        model.startScan(); try await wait(model)
        XCTAssertEqual(model.snapshot.photos.count, 2); XCTAssertTrue(model.snapshot.photos.allSatisfy { $0.rating == 4 })
        XCTAssertFalse(model.offline.isEmpty)
    }
    func testHardLinkGetsSeparateRecordAndMissingState() async throws {
        let (model, root, _) = try await scannedModel()
        let first = model.snapshot.photos.first { $0.filename == "a.png" }!
        model.selection = [first.id]; model.setRating(4)
        try FileManager.default.linkItem(at: root.appendingPathComponent("a.png"), to: root.appendingPathComponent("linked.png"))
        model.startScan(); try await wait(model)
        XCTAssertEqual(model.snapshot.photos.count, 3)
        XCTAssertEqual(model.snapshot.photos.first { $0.filename == "linked.png" }!.rating, 0)
        try FileManager.default.removeItem(at: root.appendingPathComponent("linked.png"))
        model.startScan(); try await wait(model)
        XCTAssertTrue(model.snapshot.photos.first { $0.filename == "linked.png" }!.missing)
        XCTAssertFalse(model.snapshot.photos.first { $0.id == first.id }!.missing)
    }
    func testCachedThumbnailSurvivesMissingSourceAndNewService() async throws {
        let directory = try directory(), file = directory.appendingPathComponent("cache-test.png")
        try createPhoto(file)
        let key = "test-\(UUID())"
        let first = ThumbnailService()
        let loaded: NSImage? = await withCheckedContinuation { continuation in
            _ = first.load(url: file, key: key) { continuation.resume(returning: $0) }
        }
        XCTAssertNotNil(loaded)
        try FileManager.default.removeItem(at: file)
        let reopened = ThumbnailService()
        let cached: NSImage? = await withCheckedContinuation { continuation in
            _ = reopened.load(url: nil, key: key) { continuation.resume(returning: $0) }
        }
        XCTAssertNotNil(cached)
        // A second visit after a disk hit must finish synchronously, without
        // sending the cell back through an empty placeholder/loading frame.
        var immediate: NSImage?
        let operation = reopened.load(url: nil, key: key) { immediate = $0 }
        XCTAssertNil(operation)
        XCTAssertTrue(immediate === cached)
    }
}

extension WorkflowTests {
    func testFrozenViewerQueueAndRecentPersistence() async throws {
        let (model,_,data) = try await scannedModel()
        model.navigation = .unrated
        try await Task.sleep(for:.milliseconds(150))
        let ids = model.visible.map(\.id)
        model.openViewer(ids[0]); model.setRating(5)
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertEqual(model.viewerQueue,ids)
        XCTAssertEqual(model.viewerID,ids[0])
        model.step(1); XCTAssertEqual(model.viewerID,ids[1])
        model.viewerID = nil
        XCTAssertEqual(model.visible.count,1)
        let reopened = LibraryModel(directory:data)
        XCTAssertEqual(reopened.snapshot.photos.filter { $0.lastViewed != nil }.count,2)
    }
    func testSmartAlbumAndMultiRatingQueryRoundtrip() async throws {
        let (model,_,data) = try await scannedModel()
        let ids = model.snapshot.photos.map(\.id)
        model.selection = [ids[0]]; model.setRating(4)
        model.selection = [ids[1]]; model.setRating(5)
        var album = Album(name:"旅行")
        album.query = PhotoQuery(); album.query?.ratings = [4,5]
        model.editLibrary(name:"智能相册") { $0.albums.append(album) }
        model.navigation = .album(album.id)
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertEqual(model.visible.count,2)
        model.selection = [ids[1]]; model.setRating(2)
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertEqual(model.visible.map(\.id),[ids[0]])
        let reopened = LibraryModel(directory:data)
        XCTAssertEqual(reopened.snapshot.albums.first?.query?.ratings,[4,5])
        let backup = try LibraryRepository.exportData(reopened.snapshot)
        XCTAssertEqual(try LibraryRepository.importData(backup).albums,reopened.snapshot.albums)
    }
    func testAdvancedFilterResetPreservesScopeSearchAndRatings() async throws {
        let (model, _, _) = try await scannedModel()
        let source = try XCTUnwrap(model.snapshot.sources.first)
        model.navigation = .source(source.id, "")
        model.search = "旅行"; model.ratingFilters = [4,5]
        model.sourceFilters = [source.id]; model.tagFilters = ["风景"]
        model.formatFilter = "PNG"; model.availabilityFilters = ["在线"]
        model.setDateRange(from: Date(), to: Date())
        XCTAssertEqual(model.advancedFilterCount,5)
        model.clearAdvancedFilters()
        XCTAssertEqual(model.advancedFilterCount,0)
        XCTAssertEqual(model.search,"旅行"); XCTAssertEqual(model.ratingFilters,[4,5])
        XCTAssertEqual(model.navigation,.source(source.id,""))
        model.filtersPresented = true; model.navigation = .all
        XCTAssertFalse(model.filtersPresented); XCTAssertTrue(model.search.isEmpty)
        XCTAssertTrue(model.ratingFilters.isEmpty)
    }
    func testAdvancedConditionsCombineAndDateIncludesWholeDay() async throws {
        let (model, _, _) = try await scannedModel()
        let calendar = Calendar.current, day = calendar.startOfDay(for: Date())
        let end = try XCTUnwrap(calendar.date(byAdding:.day,value:1,to:day))
        var photos = model.snapshot.photos
        photos[0].rating = 4; photos[0].tags = ["旅行"]
        photos[1].rating = 5; photos[1].tags = ["家庭"]
        photos[0].modifiedDate = end.addingTimeInterval(-1)
        photos[1].modifiedDate = end
        model.ratingFilters = [4,5]; model.tagFilters = ["旅行","夜景"]
        model.formatFilters = [photos[0].format]; model.availabilityFilters = ["在线"]
        model.setDateRange(from: end.addingTimeInterval(-1),to:day)
        let query = model.currentQuery()
        XCTAssertEqual(query.dateFrom,day); XCTAssertEqual(query.dateTo,end)
        XCTAssertEqual(query.apply(to:photos,albums:[]).map(\.id),[photos[0].id])
        model.tagFilters = ["家庭"]; XCTAssertTrue(model.currentQuery().apply(to:photos,albums:[]).isEmpty)
        model.clearAdvancedFilters()
        XCTAssertEqual(model.currentQuery().apply(to:photos,albums:[]).count,2)
    }
    func testWheelZoomIgnoresAccelerationAndReversesExactly() {
        XCTAssertEqual(ZoomScrollView.wheelZoomFactor(delta:1,precise:false),1.04,accuracy:0.00001)
        XCTAssertEqual(ZoomScrollView.wheelZoomFactor(delta:20,precise:false),1.04,accuracy:0.00001)
        for precise in [true,false] {
            for delta: CGFloat in [0,1,5,100] {
                let up = ZoomScrollView.wheelZoomFactor(delta:delta,precise:precise)
                let down = ZoomScrollView.wheelZoomFactor(delta:-delta,precise:precise)
                XCTAssertEqual(up * down,1,accuracy:0.00001)
                XCTAssertLessThanOrEqual(up,exp(0.04)+0.00001)
            }
        }
    }
    func testViewerWheelZoomClampsAndKeepsImageAnchor() {
        let scroll = ZoomScrollView(frame: NSRect(x:0,y:0,width:800,height:600))
        scroll.allowsMagnification = true; scroll.minMagnification = 0.01; scroll.maxMagnification = 8
        scroll.imagePixels = NSSize(width:4000,height:3000)
        scroll.canvas.addSubview(scroll.imageView); scroll.documentView = scroll.canvas
        scroll.layoutSubtreeIfNeeded()
        let pointer = NSPoint(x:320,y:240)
        let before = scroll.imageView.convert(pointer, from:nil)
        let initial = scroll.magnification
        scroll.zoom(by:2,at:pointer)
        XCTAssertEqual(scroll.magnification,initial * 2,accuracy:0.001)
        let after = scroll.imageView.convert(pointer, from:nil)
        XCTAssertEqual(before.x,after.x,accuracy:1)
        XCTAssertEqual(before.y,after.y,accuracy:1)
        scroll.zoom(by:1000,at:pointer)
        XCTAssertEqual(scroll.magnification,8,accuracy:0.001)
        scroll.zoom(by:0.000001,at:pointer)
        XCTAssertEqual(scroll.magnification,0.01,accuracy:0.001)
    }
    func testFavoritesPersistUndoRescanAndBackupWithoutChangingRating() async throws {
        let (model, _, data) = try await scannedModel()
        let ids = Set(model.snapshot.photos.map(\.id))
        model.selection = ids
        model.setRating(4)
        model.undoManager.removeAllActions()
        model.toggleFavorite()
        XCTAssertTrue(model.snapshot.photos.allSatisfy(\.isFavorite))
        XCTAssertTrue(model.snapshot.photos.allSatisfy { $0.rating == 4 })
        model.undoManager.undo()
        XCTAssertTrue(model.snapshot.photos.allSatisfy { !$0.isFavorite })
        model.undoManager.redo()
        XCTAssertTrue(model.snapshot.photos.allSatisfy(\.isFavorite))
        model.startScan(); try await wait(model)
        XCTAssertTrue(model.snapshot.photos.allSatisfy(\.isFavorite))
        let reopened = LibraryModel(directory:data)
        XCTAssertTrue(reopened.snapshot.photos.allSatisfy(\.isFavorite))
        let restored = try LibraryRepository.importData(LibraryRepository.exportData(reopened.snapshot))
        XCTAssertTrue(restored.photos.allSatisfy(\.isFavorite))
        var query = PhotoQuery(); query.navigation = .favorites
        XCTAssertEqual(query.apply(to:restored.photos).count,2)
        model.navigation = .favorites
        try await Task.sleep(for:.milliseconds(150))
        let first = try XCTUnwrap(model.visible.first)
        model.openViewer(first.id)
        let queue = model.viewerQueue
        model.toggleFavorite()
        XCTAssertEqual(model.viewerID,first.id); XCTAssertEqual(model.viewerQueue,queue)
        model.viewerID = nil
        XCTAssertEqual(model.visible.count,1)
        XCTAssertTrue(model.visible.allSatisfy(\.isFavorite))
    }
    func testFavoriteQuickFilterCombinesWithRatingsAndSmartAlbum() async throws {
        let (model, _, _) = try await scannedModel()
        let first = model.snapshot.photos[0].id, second = model.snapshot.photos[1].id
        model.selection = [first,second]; model.setRating(4)
        model.toggleFavorite(ids:[first])
        model.favoritesOnly = true; model.ratingFilters = [4,5]
        XCTAssertEqual(model.currentQuery().apply(to:model.snapshot.photos).map(\.id),[first])
        var album = Album(name:"收藏四五星"); album.query = model.currentQuery()
        model.editLibrary(name:"测试智能相册") { $0.albums.append(album) }
        let restored = try LibraryRepository.importData(LibraryRepository.exportData(model.snapshot))
        XCTAssertEqual(restored.albums.first?.query?.favoritesOnly,true)
        model.navigation = .album(album.id)
        XCTAssertTrue(model.favoritesOnly); XCTAssertEqual(model.ratingFilters,[4,5])
        model.clearAdvancedFilters(); XCTAssertTrue(model.favoritesOnly)
        model.chooseRating(nil,extending:false)
        XCTAssertFalse(model.favoritesOnly); XCTAssertTrue(model.ratingFilters.isEmpty)
        model.favoritesOnly = true; model.navigation = .all
        XCTAssertFalse(model.favoritesOnly)
    }
    func testLegacyPhotosWithoutFavoriteStillDecode() async throws {
        let (model, _, _) = try await scannedModel()
        let bytes = try LibraryRepository.exportData(model.snapshot)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        var photos = try XCTUnwrap(json["photos"] as? [[String:Any]])
        for i in photos.indices { photos[i].removeValue(forKey:"favorite") }
        json["photos"] = photos; json["version"] = 2
        let legacy = try LibraryRepository.importData(JSONSerialization.data(withJSONObject:json))
        XCTAssertTrue(legacy.photos.allSatisfy { !$0.isFavorite })
        XCTAssertEqual(legacy.photos.map(\.id),model.snapshot.photos.map(\.id))
    }
    func testExportCancellationKeepsCompletedCopies() throws {
        let base = try directory(), output = base.appendingPathComponent("Export")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let file = base.appendingPathComponent("photo.png"); try createPhoto(file)
        let original = try Data(contentsOf:file)
        let progress = Progress(totalUnitCount:3)
        var updates: [Int] = []
        let report = OriginalExporter.copy([("one.png",file),("two.png",file),("three.png",file)],to:output,progress:progress) { completed in
            updates.append(completed); progress.cancel()
        }
        XCTAssertEqual(report.success,1)
        XCTAssertEqual(report.unprocessed,2)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(updates,[1])
        XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("one.png")),original)
        XCTAssertFalse(FileManager.default.fileExists(atPath:output.appendingPathComponent("two.png").path))
        XCTAssertEqual(try Data(contentsOf:file),original)
    }
    func testOriginalExportAvoidsOverwriteAndReportsUnavailable() throws {
        let base = try directory(), output = base.appendingPathComponent("Export")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let file = base.appendingPathComponent("photo.png"); try createPhoto(file)
        let first = OriginalExporter.copy([("photo.png",file),("missing.png",nil)],to:output)
        XCTAssertEqual(first.success,1); XCTAssertEqual(first.failures.count,1)
        let second = OriginalExporter.copy([("photo.png",file)],to:output)
        XCTAssertEqual(second.success,1)
        XCTAssertEqual(try Data(contentsOf:file),try Data(contentsOf:output.appendingPathComponent("photo (1).png")))
    }
}

@MainActor private final class ReloadTrackingCollection: NSCollectionView {
    var reloadCount = 0
    override func reloadData() { reloadCount += 1; super.reloadData() }
}

extension WorkflowTests {
    func testRatingUpdatesDoNotReloadPhotoCollection() async throws {
        let (model, _, _) = try await scannedModel()
        let coordinator = PhotoGrid.Coordinator(model)
        let collection = ReloadTrackingCollection()
        coordinator.collection = collection
        coordinator.updateContent()
        let initialReloads = collection.reloadCount
        let id = try XCTUnwrap(model.visible.first?.id)
        model.selection = [id]
        for rating in [1, 3, 5, 0] {
            model.setRating(rating)
            try await Task.sleep(for: .milliseconds(180))
            coordinator.updateContent()
            XCTAssertEqual(coordinator.sections.flatMap { $0.1 }.first { $0.id == id }?.rating, rating)
            XCTAssertEqual(collection.reloadCount, initialReloads, "Metadata changes must retain existing photo items")
        }
        model.ratingFilters = [5]
        try await Task.sleep(for: .milliseconds(180))
        coordinator.updateContent()
        XCTAssertTrue(coordinator.photos.isEmpty)
        XCTAssertGreaterThan(collection.reloadCount, initialReloads, "Real membership changes must refresh the grid")
    }
}

extension WorkflowTests {
    func testLayoutSwitchKeepsVisibleSelectionAndScrollAnchor() async throws {
        let (model, _, _) = try await scannedModel()
        let template = try XCTUnwrap(model.visible.first)
        model.dateGrouping = false
        model.visible = (0..<100).map { index in
            var photo = template; photo.id = UUID(); photo.filename = "\(index).png"
            photo.width = index % 3 == 0 ? 300 : 600; photo.height = 400
            return photo
        }
        let coordinator = PhotoGrid.Coordinator(model)
        let collection = PhotoGrid.makeCollectionView()
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:700,height:320))
        scroll.documentView = collection
        collection.frame = NSRect(x:0,y:0,width:700,height:320)
        collection.delegate = coordinator; collection.dataSource = coordinator; coordinator.collection = collection
        coordinator.updateContent()
        let layout = try XCTUnwrap(collection.collectionViewLayout as? PhotoFlowLayout)
        collection.layoutSubtreeIfNeeded()
        let selected = IndexPath(item:48,section:0)
        collection.selectionIndexPaths = [selected]
        model.selection = [model.visible[48].id]
        let frame = try XCTUnwrap(layout.layoutAttributesForItem(at:selected)?.frame)
        scroll.contentView.scroll(to:NSPoint(x:0,y:frame.midY-160))
        for mode in ["square", "justified", "masonry"] {
            coordinator.changeLayout(layout,targetWidth:206,mode:mode,in:scroll)
            let newFrame = try XCTUnwrap(layout.layoutAttributesForItem(at:selected)?.frame)
            XCTAssertEqual(newFrame.midY-scroll.contentView.bounds.minY,160,accuracy:2)
            XCTAssertEqual(collection.selectionIndexPaths,[selected])
            XCTAssertEqual(model.selection,[model.visible[48].id])
        }
        collection.selectionIndexPaths = [IndexPath(item:0,section:0)]
        model.selection = [model.visible[0].id]
        coordinator.changeLayout(layout,targetWidth:206,mode:"square",in:scroll)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY,500,"Offscreen selection must not drag the viewport back to the top")
        XCTAssertEqual(model.selection,[model.visible[0].id])
    }
}

extension WorkflowTests {
    func testFolderNavigationBackForwardAndBranch() async throws {
        let (model, _, _) = try await scannedModel()
        let source = model.snapshot.sources[0].id
        model.navigation = .folders
        model.folderSearch = "旅行"
        model.folderIncludesSubfolders = true
        model.navigation = .source(source, "旅行")
        model.navigateBack()
        XCTAssertEqual(model.navigation, .folders)
        XCTAssertEqual(model.folderSearch, "旅行")
        XCTAssertTrue(model.folderIncludesSubfolders)
        model.navigateForward()
        XCTAssertEqual(model.navigation, .source(source, "旅行"))
        model.navigateBack()
        model.navigation = .favorites
        XCTAssertFalse(model.canNavigateForward)
        let history = model.backHistory
        model.navigation = .favorites
        XCTAssertEqual(model.backHistory, history)
        model.namePrompt = NamePrompt(title: "测试", value: "", placeholder: "", completion: { _ in })
        model.navigateBack()
        XCTAssertEqual(model.navigation, .favorites)
        model.namePrompt = nil
        model.navigateBack()
        XCTAssertEqual(model.navigation, .folders)
    }
}

extension WorkflowTests {
    func testBrowserSwipeDirectionIgnoresVerticalAndEmptyGestures() {
        XCTAssertEqual(browserSwipeDirection(x: 1, y: 0), -1)
        XCTAssertEqual(browserSwipeDirection(x: -1, y: 0), 1)
        XCTAssertNil(browserSwipeDirection(x: 0, y: 1))
        XCTAssertNil(browserSwipeDirection(x: 0, y: 0))
        XCTAssertNil(browserSwipeDirection(x: 0.1, y: 1))
        XCTAssertNil(browserSwipeDirection(x: .nan, y: 0))
    }
}

extension WorkflowTests {
    func testInspectorIsIndependentOfPhotoSelection() async throws {
        let (model, _, _) = try await scannedModel()
        XCTAssertFalse(model.inspector)
        model.selection = [model.snapshot.photos[0].id]
        XCTAssertFalse(model.inspector)
        model.selection = []
        XCTAssertFalse(model.inspector)
        model.inspector = true
        model.selection = [model.snapshot.photos[1].id]
        XCTAssertTrue(model.inspector)
        model.selection = []
        XCTAssertTrue(model.inspector)
        model.search = "a"
        XCTAssertTrue(model.inspector)
    }
}

extension WorkflowTests {
    func testInspectorResizeKeepsScrolledSelectionAnchor() async throws {
        let (model, _, _) = try await scannedModel()
        let template = try XCTUnwrap(model.visible.first)
        model.dateGrouping = false
        model.visible = (0..<100).map { index in
            var photo = template; photo.id = UUID(); photo.filename = "\(index).png"
            photo.width = index % 3 == 0 ? 300 : 600; photo.height = 400
            return photo
        }
        let coordinator = PhotoGrid.Coordinator(model)
        let collection = PhotoGrid.makeCollectionView()
        let scroll = AnchoredPhotoScrollView(frame:NSRect(x:0,y:0,width:700,height:320))
        scroll.documentView = collection
        collection.frame = NSRect(x:0,y:0,width:700,height:320)
        collection.delegate = coordinator; collection.dataSource = coordinator; coordinator.collection = collection
        coordinator.updateContent()
        let layout = try XCTUnwrap(collection.collectionViewLayout as? PhotoFlowLayout)
        collection.layoutSubtreeIfNeeded()
        let selected = IndexPath(item:48,section:0)
        collection.selectionIndexPaths = [selected]
        model.selection = [model.visible[48].id]
        let frame = try XCTUnwrap(layout.layoutAttributesForItem(at:selected)?.frame)
        scroll.contentView.scroll(to:NSPoint(x:0,y:frame.midY-160))
        scroll.captureAnchor(selectedIDs: model.selection, sections: coordinator.sections)
        for width: CGFloat in [680, 620, 560, 500, 560, 620, 700] {
            scroll.setFrameSize(NSSize(width: width, height: 320))
            let newFrame = try XCTUnwrap(layout.layoutAttributesForItem(at:selected)?.frame)
            XCTAssertEqual(newFrame.midY-scroll.contentView.bounds.minY,160,accuracy:2)
            XCTAssertEqual(model.selection,[model.visible[48].id])
        }
    }
}


extension WorkflowTests {
    func testNativeTitleHitAreaIncludesTopAndExcludesControlsAndToolbar() {
        let frame = NSRect(x: 200, y: 100, width: 1200, height: 800)
        XCTAssertTrue(TitleDragView.isNativeTitlePoint(NSPoint(x: 800, y: 899), frame: frame))
        XCTAssertTrue(TitleDragView.isNativeTitlePoint(NSPoint(x: 800, y: 880), frame: frame))
        XCTAssertFalse(TitleDragView.isNativeTitlePoint(NSPoint(x: 220, y: 890), frame: frame))
        XCTAssertFalse(TitleDragView.isNativeTitlePoint(NSPoint(x: 800, y: 850), frame: frame))
        XCTAssertFalse(TitleDragView.isNativeTitlePoint(NSPoint(x: 800, y: 901), frame: frame))
    }
}

extension WorkflowTests {
    func testRenameFolderPreservesAnnotationsAndDiskContents() async throws {
        let (model, root, data) = try await scannedModel()
        let source = try XCTUnwrap(model.snapshot.sources.first)
        let child = root.appendingPathComponent("Child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try createPhoto(child.appendingPathComponent("nested.png"))
        model.startScan(); try await wait(model)
        let photo = try XCTUnwrap(model.snapshot.photos.first { $0.filename == "nested.png" })
        let bytes = try Data(contentsOf: child.appendingPathComponent("nested.png"))
        model.setRating(5, ids: [photo.id]); model.addTag("Keep", to: [photo.id])
        model.navigation = .source(source.id, "Child")
        model.renameFolder(sourceID: source.id, path: "Child", name: "Renamed", authorizedParent: root)
        XCTAssertNil(model.issue)
        XCTAssertEqual(model.navigation, .source(source.id, "Renamed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: child.path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Renamed/nested.png")), bytes)
        let renamed = try XCTUnwrap(model.snapshot.photos.first { $0.id == photo.id })
        XCTAssertEqual(renamed.relativePath, "Renamed/nested.png")
        XCTAssertEqual(renamed.rating, 5); XCTAssertEqual(renamed.tags, ["Keep"])
        model.renameFolder(sourceID: source.id, path: "", name: "NewRoot", authorizedParent: root.deletingLastPathComponent())
        XCTAssertNil(model.issue)
        let newRoot = root.deletingLastPathComponent().appendingPathComponent("NewRoot")
        XCTAssertEqual(model.snapshot.sources.first?.name, "NewRoot")
        XCTAssertEqual(model.url(for: renamed)?.standardizedFileURL.resolvingSymlinksInPath(), newRoot.appendingPathComponent("Renamed/nested.png").resolvingSymlinksInPath())
        model.startScan(); try await wait(model)
        XCTAssertEqual(model.snapshot.photos.count, 3)
        XCTAssertEqual(model.snapshot.photos.first { $0.id == photo.id }?.rating, 5)
        XCTAssertFalse(model.snapshot.photos.contains { $0.missing })
        let reopened = LibraryModel(directory: data)
        XCTAssertEqual(reopened.snapshot.photos.first { $0.id == photo.id }?.tags, ["Keep"])
        XCTAssertEqual(reopened.snapshot.sources.first?.name, "NewRoot")
        model.cancelScan(); reopened.cancelScan()
    }
    func testRenameFolderRejectsCollisionsAndInvalidNames() async throws {
        let (model, root, _) = try await scannedModel()
        let id = try XCTUnwrap(model.snapshot.sources.first?.id)
        let before = model.snapshot
        model.renameFolder(sourceID: id, path: "", name: "Data", authorizedParent: root.deletingLastPathComponent())
        XCTAssertNotNil(model.issue)
        XCTAssertEqual(model.snapshot, before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        for value in ["", ".", "..", "a/b", "a:b", "a\n"] { XCTAssertFalse(LibraryModel.validFolderName(value)) }
        model.cancelScan()
    }
}
