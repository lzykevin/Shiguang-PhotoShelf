import XCTest
import Foundation
import PhotoLibraryCore
@testable import PhotoShelf

extension WorkflowTests {
    func testSmartAlbumRejectsManualMembershipAndBatchPartialTagRemoval() async throws {
        let (model, _, data) = try await scannedModel()
        let first = model.snapshot.photos[0].id
        var smart = Album(name: "自动精选"); var query = PhotoQuery(); query.ratings = [5]; smart.query = query
        let manual = Album(name: "旅行")
        model.editLibrary(name: "相册") { $0.albums += [smart, manual] }
        model.addTag("海边", to: [first])
        model.selection = Set(model.snapshot.photos.map(\.id))
        model.addToAlbum(smart)
        XCTAssertTrue(model.snapshot.photos.allSatisfy { !$0.albumIDs.contains(smart.id) })
        model.addToAlbum(manual)
        XCTAssertTrue(model.snapshot.photos.allSatisfy { $0.albumIDs.contains(manual.id) })
        model.removeTag("海边", ids: model.selection)
        model.removeFromAlbum(manual)
        let reopened = LibraryModel(directory: data)
        XCTAssertTrue(reopened.snapshot.photos.allSatisfy { $0.tags.isEmpty && $0.albumIDs.isEmpty })
    }

    func testFormatSetRoundTripAndNavigationClearsTemporaryFilters() async throws {
        let (model, _, _) = try await scannedModel()
        model.formatFilters = ["PNG", "JPEG"]
        model.ratingFilters = [4, 5]
        let query = model.currentQuery()
        XCTAssertEqual(query.formats, ["PNG", "JPEG"])
        var album = Album(name: "组合"); album.query = query
        model.editLibrary(name: "智能相册") { $0.albums.append(album) }
        model.navigation = .album(album.id)
        XCTAssertEqual(model.formatFilters, ["PNG", "JPEG"])
        model.navigation = .all
        XCTAssertTrue(model.formatFilters.isEmpty)
        XCTAssertTrue(model.ratingFilters.isEmpty)
    }

    func testScanSaveFailureKeepsPublishedAndPersistentCatalogInSync() async throws {
        let (model, root, data) = try await scannedModel()
        let old = model.snapshot.photos
        // Reject the incremental save through repository validation and verify rollback.
        model.snapshot.photos[0].rating = 6
        try createPhoto(root.appendingPathComponent("new.png"))
        model.startScan(); try await wait(model)
        XCTAssertEqual(Set(model.snapshot.photos.map(\.id)), Set(old.map(\.id)))
        XCTAssertEqual(Set(try model.repository!.load().photos.map(\.id)), Set(old.map(\.id)))
        XCTAssertNotNil(model.issue)
        model.snapshot.photos[0].rating = 0
        model.startScan(); try await wait(model)
        XCTAssertEqual(model.snapshot.photos.count, 3)
    }
}
