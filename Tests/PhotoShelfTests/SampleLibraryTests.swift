import XCTest
import PhotoLibraryCore
@testable import PhotoShelf

@MainActor final class SampleLibraryTests: XCTestCase {
    func testSamplesPersistWithoutOverwritingAndRestoreAfterDetach() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = LibraryModel(directory: directory)
        var original = model.snapshot
        let existing = Album(name: "我的相册")
        original.albums = [existing]; original.tags = ["我的标签"]
        try model.repository!.commit(original); model.snapshot = original
        await model.loadSampleLibrary()
        XCTAssertNil(model.issue)
        XCTAssertEqual(model.snapshot.photos.count, 11)
        XCTAssertEqual(model.snapshot.albums.count, 2)
        XCTAssertTrue(model.snapshot.albums.contains { $0.id == existing.id })
        XCTAssertEqual(Set(model.snapshot.tags), ["我的标签", "天空", "风景"])
        XCTAssertEqual(model.snapshot.photos.filter(\.isFavorite).count, 5)
        XCTAssertEqual(model.snapshot.photos.filter { !$0.albumIDs.isEmpty }.count, 2)
        XCTAssertTrue(model.snapshot.photos.allSatisfy { $0.note.isEmpty })
        let id = try XCTUnwrap(model.snapshot.photos.first?.id)
        model.selection = [id]; model.setRating(2)
        let source = try XCTUnwrap(model.snapshot.sources.first)
        model.detachSource(source)
        let reopened = LibraryModel(directory: directory)
        XCTAssertTrue(reopened.activeSources.isEmpty)
        await reopened.loadSampleLibrary()
        await reopened.loadSampleLibrary()
        XCTAssertNil(reopened.issue)
        XCTAssertEqual(reopened.snapshot.photos.count, 11)
        XCTAssertEqual(reopened.snapshot.albums.count, 2)
        XCTAssertEqual(reopened.activeSources.map(\.id), [source.id])
        XCTAssertEqual(reopened.snapshot.photos.first { $0.id == id }?.rating, 2)
        XCTAssertTrue(reopened.snapshot.photos.allSatisfy { reopened.url(for: $0) != nil })
        model.cancelScan(); reopened.cancelScan()
    }
}
