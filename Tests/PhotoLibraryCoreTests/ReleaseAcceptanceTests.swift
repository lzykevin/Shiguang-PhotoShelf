import XCTest
import ImageIO
@testable import PhotoLibraryCore

extension LibraryTests {
    func testReleaseScanDeliversBatchesAndNestedPhotosWithoutDuplicates() async throws {
        let root = try temporary()
        let nested = root.appendingPathComponent("旅行/第一天")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        for index in 0..<70 { try writeImage(nested.appendingPathComponent("image-\(index).jpg")) }
        let collector = ReleaseBatchCollector()
        let source = PhotoSource(name: "旅行图库", path: root.path)
        let identities = try await PhotoScanner.scan(source: source, root: root) { await collector.add($0) }
        let batches = await collector.batches
        XCTAssertEqual(batches.map { $0.photos.count }, [64, 6])
        XCTAssertTrue(batches.allSatisfy { $0.warnings.isEmpty })
        let photos = batches.flatMap(\.photos)
        XCTAssertEqual(identities.count, 70)
        XCTAssertEqual(Set(photos.map(\.relativePath)).count, 70)
        XCTAssertTrue(photos.allSatisfy { $0.relativePath.hasPrefix("旅行/第一天/") }, "root=\(root.path) relative=\(photos.first?.relativePath ?? "nil")")
    }

    @MainActor func testReleaseInvalidRestoreLeavesExistingCatalogIntact() throws {
        let repo = try LibraryRepository(directory: temporary())
        let source = PhotoSource(name: "原图库", path: "/pictures")
        var state = LibrarySnapshot(); state.sources = [source]
        var item = photo(sourceID: source.id); item.rating = 5; item.isFavorite = true; item.note = "需要保留"
        state.photos = [item]
        try repo.commit(state)
        var invalid = state; invalid.photos[0].relativePath = "../outside.jpg"
        XCTAssertThrowsError(try repo.commit(invalid, replacing: true))
        XCTAssertEqual(try repo.load(), state)
        invalid = state; invalid.photos[0].filename = "../outside.jpg"
        XCTAssertThrowsError(try repo.commit(invalid, replacing: true))
        XCTAssertThrowsError(try LibraryRepository.importData(LibraryRepository.exportData(invalid)))
        XCTAssertEqual(try repo.load(), state)
        var future = state; future.version = 999
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        XCTAssertThrowsError(try LibraryRepository.importData(encoder.encode(future)))
        XCTAssertEqual(try repo.load(), state)
    }

    @MainActor func testReleaseThirtyThousandRecordPersistenceAndIncrementalSave() throws {
        let directory = try temporary()
        let repo = try LibraryRepository(directory: directory)
        let source = PhotoSource(name: "规模验收", path: "/pictures")
        var state = LibrarySnapshot(); state.sources = [source]
        state.photos = (0..<30_000).map { index in
            var item = photo("trip/\(index).jpg", sourceID: source.id)
            item.filename = "\(index).jpg"
            return item
        }
        let start = Date()
        try repo.commit(state)
        let loadStart = Date()
        let reopened = try LibraryRepository(directory: directory)
        XCTAssertEqual(try reopened.load().photos.count, 30_000)
        let updateStart = Date()
        var changed = state.photos[12_345]; changed.rating = 4; changed.isFavorite = true
        try reopened.savePhotos([changed])
        // Read through a new repository context to avoid Core Data's registered-object cache.
        let fresh = try LibraryRepository(directory: directory)
        let persisted = try fresh.load().photos.first { $0.id == changed.id }
        XCTAssertEqual(persisted?.rating, 4); XCTAssertEqual(persisted?.isFavorite, true)
        print("BENCHMARK 30k persistence commit=\(loadStart.timeIntervalSince(start))s load=\(updateStart.timeIntervalSince(loadStart))s; incremental save and fresh reads completed")
    }
}

private actor ReleaseBatchCollector {
    var batches: [ScanBatch] = []
    func add(_ batch: ScanBatch) { batches.append(batch) }
}
