import XCTest
import ImageIO
import CoreGraphics
import CryptoKit
@testable import PhotoLibraryCore

final class LibraryTests: XCTestCase {
    func photo(_ name: String = "lake.jpg", sourceID: UUID = UUID()) -> Photo {
        Photo(sourceID: sourceID, relativePath: name, identity: name, filename: name, format: "JPG", byteSize: 128, width: 32, height: 24, captureDate: nil, modifiedDate: Date(timeIntervalSince1970: 1000))
    }
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoShelfTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func writeImage(_ url: URL, orientation: Int = 1) throws {
        let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation, kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:18 16:32:00"], kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Test Camera"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
    func testQueryCombinesFiltersAndSearchesAnnotations() {
        var a = photo(); a.rating = 4; a.tags = ["旅行", "风景"]; a.note = "云南湖边"
        var b = photo("portrait.jpg"); b.rating = 5; b.tags = ["人像"]
        var query = PhotoQuery(); query.search = "云南 旅行"; query.rating = 4; query.selectedTags = ["风景", "人像"]
        XCTAssertEqual(query.apply(to: [a, b]).map(\.id), [a.id])
        query.rating = 5; XCTAssertTrue(query.apply(to: [a, b]).isEmpty)
    }
    func testUnratedAndFolderBoundaries() {
        let source = UUID(); var a = photo("trip/a.jpg", sourceID: source); var b = photo("trip2/b.jpg", sourceID: source)
        a.rating = 0; b.rating = 1
        var query = PhotoQuery(); query.navigation = .source(source, "trip")
        XCTAssertEqual(query.apply(to: [a, b]).map(\.id), [a.id])
        query.navigation = .unrated; XCTAssertEqual(query.apply(to: [a, b]).map(\.id), [a.id])
    }
    func testSortAndDateFallback() {
        var a = photo("a.jpg"); a.captureDate = Date(timeIntervalSince1970: 2000)
        let b = photo("b.jpg")
        var query = PhotoQuery(); XCTAssertEqual(query.apply(to: [b, a]).map(\.id), [a.id, b.id])
        query.dateFrom = Date(timeIntervalSince1970: 1500); query.dateTo = Date(timeIntervalSince1970: 2500)
        XCTAssertEqual(query.apply(to: [a, b]).count, 1)
    }
    func testSortFieldsSupportBothDirectionsAndNaturalNames() {
        var a = photo("image2.jpg"), b = photo("image10.jpg")
        a.captureDate = Date(timeIntervalSince1970: 2000)
        b.captureDate = Date(timeIntervalSince1970: 3000)
        a.addedDate = Date(timeIntervalSince1970: 4000)
        b.addedDate = Date(timeIntervalSince1970: 5000)
        a.rating = 1; b.rating = 5
        for field in PhotoSortField.allCases {
            var query = PhotoQuery()
            query.sort = .order(field: field, ascending: true)
            XCTAssertEqual(query.apply(to: [b, a]).map(\.id), [a.id, b.id], field.rawValue)
            query.sort = .order(field: field, ascending: false)
            XCTAssertEqual(query.apply(to: [a, b]).map(\.id), [b.id, a.id], field.rawValue)
        }
    }
    func testSortPersistenceRetainsLegacyCasesAndNewDirections() throws {
        XCTAssertEqual(PhotoSort(rawValue: "文件名"), .name)
        XCTAssertEqual(PhotoSort(rawValue: "添加时间"), .added)
        XCTAssertEqual(PhotoSort(rawValue: "星级：从高到低"), .rating)
        for order in PhotoSort.allCases {
            XCTAssertEqual(PhotoSort.order(field: order.field, ascending: order.ascending), order)
            var query = PhotoQuery(); query.sort = order
            let decoded = try JSONDecoder().decode(PhotoQuery.self, from: JSONEncoder().encode(query))
            XCTAssertEqual(decoded.sort, order)
        }
    }
    func testRenameRetainsAnnotationsAndReplacementDoesNot() {
        var old = photo(); old.rating = 5; old.tags = ["风景"]; old.note = "喜欢"
        var renamed = old; renamed.filename = "renamed.jpg"; renamed.relativePath = renamed.filename; renamed.rating = 0; renamed.tags = []; renamed.note = ""
        let result = ScanMerge.merge(existing: [old], incoming: [renamed])
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].id, old.id); XCTAssertEqual(result[0].rating, 5); XCTAssertEqual(result[0].note, "喜欢")
        var replacement = renamed; replacement.identity = "new-file"
        let replaced = ScanMerge.merge(existing: [old], incoming: [replacement]); XCTAssertEqual(replaced.count, 2)
    }
    @MainActor func testCoreDataReopenAndIncrementalRating() async throws {
        let directory = try temporary()
        let source = PhotoSource(name: "Pictures", path: "/pictures")
        var snapshot = LibrarySnapshot(); snapshot.sources = [source]; snapshot.photos = [photo(sourceID: source.id)]
        let repository = try LibraryRepository(directory: directory); try repository.commit(snapshot)
        var rated = snapshot.photos[0]; rated.rating = 4; rated.note = "备注"; try repository.savePhotos([rated])
        let reopened = try LibraryRepository(directory: directory)
        let loaded = try reopened.load(); XCTAssertEqual(loaded.photos[0].rating, 4); XCTAssertEqual(loaded.photos[0].note, "备注")
    }
    @MainActor func testBackupRoundtripDoesNotExportPermissions() async throws {
        var snapshot = LibrarySnapshot(); let source = PhotoSource(name: "Pictures", path: "/pictures", bookmark: Data([1, 2, 3]))
        snapshot.sources = [source]; let album = Album(name: "精选"); snapshot.albums = [album]; snapshot.tags = ["风景"]
        var p = photo(sourceID: source.id); p.rating = 3; p.tags = snapshot.tags; p.albumIDs = [album.id]; snapshot.photos = [p]
        let data = try LibraryRepository.exportData(snapshot), restored = try LibraryRepository.importData(data)
        XCTAssertNil(restored.sources[0].bookmark); XCTAssertEqual(restored.photos[0].rating, 3); XCTAssertEqual(restored.photos[0].albumIDs, [album.id])
        XCTAssertEqual(restored.photos[0].addedDate.timeIntervalSince1970, snapshot.photos[0].addedDate.timeIntervalSince1970, accuracy: 0.000001)
    }
    @MainActor func testRejectsInvalidBackupPathsAndReferences() async throws {
        var state = LibrarySnapshot(); let source = PhotoSource(name: "Pictures", path: "/pictures"); state.sources = [source]
        state.photos = [photo("../../escape.jpg", sourceID: source.id)]
        XCTAssertThrowsError(try LibraryRepository.validate(state))
        state.photos[0].relativePath = "safe.jpg"; state.photos[0].rating = 6
        XCTAssertThrowsError(try LibraryRepository.validate(state))
        state.photos[0].rating = 0; state.photos[0].albumIDs = [UUID()]
        XCTAssertThrowsError(try LibraryRepository.validate(state))
        state.photos[0].albumIDs = []; state.photos[0].tags = ["unknown"]
        XCTAssertThrowsError(try LibraryRepository.validate(state))
    }
    @MainActor func testRemovedRecordsStayRemoved() async throws {
        let repository = try LibraryRepository(directory: temporary())
        var state = LibrarySnapshot(); let source = PhotoSource(name: "Pictures", path: "/pictures"); state.sources = [source]; state.photos = [photo(sourceID: source.id)]
        try repository.commit(state); state.photos = []; state.sources = []; try repository.commit(state)
        XCTAssertTrue(try repository.load().photos.isEmpty)
    }
    func testScannerReadsEXIFAndNeverModifiesOriginals() async throws {
        let directory = try temporary(), file = directory.appendingPathComponent("sample.jpg")
        try writeImage(file)
        let before = SHA256.hash(data: try Data(contentsOf: file))
        let collector = Collector()
        let source = PhotoSource(name: "Test", path: directory.path)
        _ = try await PhotoScanner.scan(source: source, root: directory) { await collector.add($0.photos) }
        let photos = await collector.photos
        XCTAssertEqual(photos.count, 1); XCTAssertEqual(photos[0].width, 32); XCTAssertNotNil(photos[0].captureDate)
        XCTAssertTrue(photos[0].camera?.contains("Test Camera") == true)
        XCTAssertEqual(before, SHA256.hash(data: try Data(contentsOf: file)))
    }
    func testScannerSkipsHiddenPackagesSymlinksAndKeepsCorruptPhoto() async throws {
        let directory = try temporary()
        try writeImage(directory.appendingPathComponent("good.jpg"))
        try writeImage(directory.appendingPathComponent(".hidden.jpg"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link.jpg"), withDestinationURL: directory.appendingPathComponent("good.jpg"))
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("bad.dng"))
        let package = directory.appendingPathComponent("Test.app"); try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true); try writeImage(package.appendingPathComponent("inside.jpg"))
        let collector = Collector(), source = PhotoSource(name: "Test", path: directory.path)
        _ = try await PhotoScanner.scan(source: source, root: directory) { await collector.add($0.photos) }
        let photos = await collector.photos
        XCTAssertEqual(Set(photos.map(\.filename)), ["good.jpg", "bad.dng"])
        XCTAssertTrue(photos.first { $0.filename == "bad.dng" }!.decodeError)
    }
    func testScannerDetectsIdentityAcrossRename() async throws {
        let directory = try temporary(), first = directory.appendingPathComponent("first.jpg"), second = directory.appendingPathComponent("second.jpg")
        try writeImage(first)
        let source = PhotoSource(name: "Test", path: directory.path), a = Collector(), b = Collector()
        _ = try await PhotoScanner.scan(source: source, root: directory) { await a.add($0.photos) }
        try FileManager.default.moveItem(at: first, to: second)
        _ = try await PhotoScanner.scan(source: source, root: directory) { await b.add($0.photos) }
        let firstID = await a.photos[0].identity, secondID = await b.photos[0].identity
        XCTAssertEqual(firstID, secondID)
    }
    func testIncrementalScanSkipsUnchangedAndLimitsScope() async throws {
        let root = try temporary(), a = root.appendingPathComponent("a.jpg"), b = root.appendingPathComponent("b.jpg")
        try writeImage(a); try writeImage(b)
        let source = PhotoSource(name: "增量", path: root.path), first = Collector()
        let all = try await PhotoScanner.scan(source: source, root: root) { await first.add($0.photos) }
        let existing = await first.photos
        XCTAssertEqual(existing.count, 2)
        let unchanged = Collector()
        let same = try await PhotoScanner.scan(source: source, root: root, existing: existing) { await unchanged.add($0.photos) }
        let unchangedPhotos = await unchanged.photos
        XCTAssertTrue(unchangedPhotos.isEmpty)
        XCTAssertEqual(same, all)
        try writeImage(a, orientation: 6)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: a.path)
        let changed = Collector()
        let scoped = try await PhotoScanner.scan(source: source, root: root, existing: existing, relativePaths: ["a.jpg"]) { await changed.add($0.photos) }
        let changedPhotos = await changed.photos
        XCTAssertEqual(changedPhotos.map(\.filename), ["a.jpg"])
        XCTAssertEqual(changedPhotos.first?.width, 24)
        XCTAssertEqual(scoped.count, 1)
        try FileManager.default.removeItem(at: a)
        let absent = try await PhotoScanner.scan(source: source, root: root, existing: existing, relativePaths: ["a.jpg"]) { _ in }
        XCTAssertTrue(absent.isEmpty)
        XCTAssertEqual(PhotoScanner.normalizedScopes(["trip/a.jpg", "trip", "trip2/b.jpg", "../outside"]), ["trip", "trip2/b.jpg"])
        XCTAssertFalse(PhotoScanner.covers("trip2/b.jpg", scopes: ["trip"]))
    }

    func testCancellationStopsScanner() async throws {
        let directory = try temporary(); try writeImage(directory.appendingPathComponent("sample.jpg"))
        let source = PhotoSource(name: "Test", path: directory.path)
        let task = Task { try await PhotoScanner.scan(source: source, root: directory) { _ in } }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    @MainActor func testVersionOneBackupWithoutNewFieldsPreservesAnnotations() throws {
        let source = PhotoSource(name: "旧图库", path: "/pictures")
        var state = LibrarySnapshot(); state.version = 1; state.sources = [source]
        let album = Album(name: "旅行"); state.albums = [album]; state.tags = ["海边"]
        var item = photo(sourceID: source.id); item.addedDate = Date(timeIntervalSince1970: 1234); item.rating = 5; item.note = "记忆"; item.tags = state.tags; item.albumIDs = [album.id]
        state.photos = [item]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LibraryRepository.exportData(state)) as? [String: Any])
        var rows = try XCTUnwrap(json["photos"] as? [[String: Any]])
        rows[0].removeValue(forKey: "lastViewed"); json["photos"] = rows
        var albums = try XCTUnwrap(json["albums"] as? [[String: Any]])
        albums[0].removeValue(forKey: "query"); json["albums"] = albums
        let restored = try LibraryRepository.importData(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.photos, state.photos); XCTAssertNil(restored.albums[0].query)
        let repository = try LibraryRepository(directory: temporary())
        try repository.commit(restored)
        XCTAssertEqual(try repository.load().photos, state.photos)
    }

    func testQueryFacetsUseOrWithinAndAcrossAndLegacyFieldsDecode() throws {
        let source = UUID(), other = UUID()
        var a = photo("a.jpg", sourceID: source); a.rating = 4; a.tags = ["海边"]
        var b = photo("b.png", sourceID: source); b.rating = 5; b.tags = ["旅行"]; b.format = "PNG"
        var excluded = b; excluded.id = UUID(); excluded.sourceID = other
        var query = PhotoQuery(); query.ratings = [4, 5]; query.rating = 1
        query.formats = ["JPG", "PNG"]; query.format = "TIFF"
        query.selectedTags = ["海边", "旅行"]; query.sources = [source]
        XCTAssertEqual(Set(query.apply(to: [a, b, excluded]).map(\.id)), [a.id, b.id])
        query.availability = ["缺失", "离线"]; b.missing = true
        XCTAssertEqual(query.apply(to: [a, b]).map(\.id), [b.id])
        query.offlineSources = [source]
        XCTAssertEqual(query.apply(to: [a, b]).count, 2)
        let legacy = try JSONDecoder().decode(PhotoQuery.self, from: Data(#"{"rating":4,"format":"JPG"}"#.utf8))
        XCTAssertEqual(legacy.apply(to: [a, b]).map(\.id), [a.id])
        XCTAssertTrue(legacy.formats.isEmpty)
    }

    @MainActor func testUpgradeBackupPrecedesWriteAndIncludesEmptySourcesAndPermissions() throws {
        let directory = try temporary(), repository = try LibraryRepository(directory: directory)
        var state = LibrarySnapshot()
        state.sources = [PhotoSource(name: "空来源", path: "/pictures", bookmark: Data([1, 2, 3]))]
        try repository.commit(state)
        // Simulate the absence of a product-version marker in an existing v1 store.
        try FileManager.default.removeItem(at: directory.appendingPathComponent("ProductSchema-v3"))
        var updated = state; updated.sources[0].name = "重命名"
        try repository.commit(updated)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("BeforeUpgrade-v3-") }
        XCTAssertEqual(files.count, 1)
        let before = try LibraryRepository.importData(Data(contentsOf: XCTUnwrap(files.first)))
        XCTAssertEqual(before.sources, state.sources)
        _ = try repository.load()
        let afterFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("BeforeUpgrade-v3-") }
        XCTAssertEqual(afterFiles.count, 1)
    }

    @MainActor func testInvalidIncrementalWriteCannotDamageDurablePhoto() throws {
        let repository = try LibraryRepository(directory: temporary())
        let source = PhotoSource(name: "Pictures", path: "/pictures")
        var state = LibrarySnapshot(); state.sources = [source]; state.photos = [photo(sourceID: source.id)]
        try repository.commit(state)
        var invalid = state.photos[0]; invalid.rating = 9
        XCTAssertThrowsError(try repository.savePhotos([invalid]))
        invalid.rating = 4; invalid.sourceID = UUID()
        XCTAssertThrowsError(try repository.savePhotos([invalid]))
        XCTAssertEqual(try repository.load().photos, state.photos)
    }

    @MainActor func testSmartAlbumRejectsNestedAndInvalidConditions() throws {
        var state = LibrarySnapshot(), first = Album(name: "智能相册"), second = Album(name: "嵌套")
        first.query = PhotoQuery(); second.query = PhotoQuery(); second.query?.navigation = .album(first.id)
        state.albums = [first, second]
        XCTAssertThrowsError(try LibraryRepository.validate(state))
        state.albums = [first]; state.albums[0].query?.rating = -1
        XCTAssertThrowsError(try LibraryRepository.validate(state))
        state.albums[0].query?.rating = nil; state.albums[0].query?.navigation = .source(UUID(), "../escape")
        XCTAssertThrowsError(try LibraryRepository.validate(state))
    }

    func testThirtyThousandPhotoQueryPerformance() {
        let source = UUID()
        let photos = (0..<30_000).map { index -> Photo in var p = photo("photo-\(index).jpg", sourceID: source); p.rating = index % 6; p.tags = ["旅行"]; return p }
        var query = PhotoQuery(); query.rating = 4; query.search = "旅行"
        let start = Date(); let result = query.apply(to: photos); let elapsed = Date().timeIntervalSince(start)
        print("BENCHMARK 30,000 photos filter: \(String(format: "%.3f", elapsed))s; matches: \(result.count)")
        XCTAssertEqual(result.count, 5000); XCTAssertLessThan(elapsed, 0.5)
    }
}

private actor Collector {
    var photos: [Photo] = []
    func add(_ items: [Photo]) { photos.append(contentsOf: items) }
}
