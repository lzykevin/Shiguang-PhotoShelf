import XCTest
@testable import PhotoShelf
final class ExportBoundaryTests: XCTestCase {
    func testExportRejectsPathAsName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.jpg")
        try Data([1, 2, 3]).write(to: source)
        let result = OriginalExporter.copy([("../outside.jpg", source), ("safe.jpg", source)], to: output)
        XCTAssertEqual(result.success, 1)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("outside.jpg").path))
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("safe.jpg")), Data([1, 2, 3]))
    }
}
