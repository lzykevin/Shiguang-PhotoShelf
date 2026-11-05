import XCTest
import Combine
import PhotoLibraryCore
@testable import PhotoShelf

extension WorkflowTests {
    func testFolderTreeAvailableImmediatelyAfterOfflineReopen() async throws {
        let (model, root, data) = try await scannedModel()
        let source = model.snapshot.sources[0].id
        for (index, photo) in model.snapshot.photos.enumerated() {
            let folder = root.appendingPathComponent(index == 0 ? "旅行/海边" : "旅行/山间")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: root.appendingPathComponent(photo.relativePath), to: folder.appendingPathComponent(photo.filename))
        }
        model.startScan(); try await wait(model)
        XCTAssertNil(model.issue)
        let persisted = try model.repository!.load()
        XCTAssertTrue(persisted.photos.allSatisfy { $0.relativePath.hasPrefix("旅行/") })
        XCTAssertEqual(persisted.photos.count, 2)
        // Real source disconnection: reopen without scanning or a reachable directory.
        try FileManager.default.removeItem(at: root)
        let reopened = LibraryModel(directory: data)
        XCTAssertTrue(reopened.offline.contains(source))
        XCTAssertEqual(reopened.folderNodes[source]?.map(\.name), ["旅行"])
        XCTAssertEqual(Set(reopened.folderNodes[source]?.first?.children.map(\.name) ?? []), ["海边", "山间"])
        reopened.editLibrary(name: "清空测试索引") { $0.photos = [] }
        XCTAssertTrue(reopened.folderNodes.isEmpty)
    }

    func testBatchAnnotationPublishesSnapshotOnceAndPersistsAll() async throws {
        let (model, _, _) = try await scannedModel()
        model.selection = Set(model.snapshot.photos.map(\.id))
        var publications = 0
        let subscription = model.$snapshot.dropFirst().sink { _ in publications += 1 }
        model.setRating(4)
        XCTAssertEqual(publications, 1, "Batch edits must not rebuild all folder paths once per photo")
        XCTAssertTrue(try model.repository!.load().photos.allSatisfy { $0.rating == 4 })
        withExtendedLifetime(subscription) {}
    }

    func testTagRenamePreservesSmartAlbumFiltersAndUndo() async throws {
        let (model, _, data) = try await scannedModel()
        model.selection = Set(model.snapshot.photos.map(\.id))
        model.addTag("海边")
        var album = Album(name: "海边精选")
        var query = PhotoQuery(); query.selectedTags = ["海边"]; query.navigation = .tag("海边")
        album.query = query
        model.editLibrary(name: "创建智能相册") { $0.albums.append(album) }
        model.navigation = .album(album.id)
        model.undoManager.removeAllActions(); model.undoManager.groupsByEvent = false
        model.undoManager.beginUndoGrouping()
        model.renameTag("海边")
        let request = try XCTUnwrap(model.namePrompt); model.namePrompt = nil
        request.completion("海岸")
        model.undoManager.endUndoGrouping()
        XCTAssertEqual(model.tagFilters, ["海岸"])
        XCTAssertEqual(model.snapshot.albums.last?.query?.selectedTags, ["海岸"])
        XCTAssertEqual(model.currentQuery().navigation, .tag("海岸"))
        XCTAssertEqual(model.currentQuery().apply(to: model.snapshot.photos).count, 2)
        let reopened = LibraryModel(directory: data)
        XCTAssertEqual(reopened.snapshot.albums.last?.query?.navigation, .tag("海岸"))
        model.undoManager.undo()
        XCTAssertEqual(model.snapshot.albums.last?.query?.selectedTags, ["海边"])
        XCTAssertEqual(model.currentQuery().apply(to: model.snapshot.photos).count, 2)
        XCTAssertTrue(model.snapshot.photos.allSatisfy { $0.tags == ["海边"] })
    }
}
