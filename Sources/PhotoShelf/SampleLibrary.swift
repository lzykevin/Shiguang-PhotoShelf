import Foundation
import PhotoLibraryCore

struct SampleManifest: Decodable {
    struct Item: Decodable {
        let filename: String
        let rating: Int
        let tags: [String]
        let favorite: Bool
        let albumIDs: [UUID]
    }
    let albums: [Album]
    let tags: [String]
    let photos: [Item]
}

private actor SampleScanResult {
    var photos: [Photo] = []
    var warnings: [String] = []
    func append(_ batch: ScanBatch) { photos += batch.photos; warnings += batch.warnings }
}

extension LibraryModel {
    static var sampleResourceURL: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "Samples", withExtension: nil)
        #else
        return Bundle.main.url(forResource: "Samples", withExtension: nil)
        #endif
    }

    /// Copy the bundled examples into app-owned storage, then commit metadata once.
    /// Re-entering restores a detached sample source without resetting user edits.
    func loadSampleLibrary(resources: URL? = nil) async {
        guard !loadingSamples, !scanning, let repository else { return }
        loadingSamples = true
        defer { loadingSamples = false }
        do {
            guard let resources = resources ?? Self.sampleResourceURL else {
                throw LibraryError.unavailable("此构建未包含示例照片。")
            }
            let manifest = try JSONDecoder().decode(SampleManifest.self, from: Data(contentsOf: resources.appendingPathComponent("manifest.json")))
            guard !manifest.photos.isEmpty, Set(manifest.photos.map(\.filename)).count == manifest.photos.count,
                  manifest.photos.allSatisfy({ $0.filename == ($0.filename as NSString).lastPathComponent && !$0.filename.hasPrefix(".") }) else {
                throw LibraryError.unavailable("示例清单格式不正确。")
            }
            let root = repository.directory.appendingPathComponent("SamplePhotos", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for item in manifest.photos {
                let target = root.appendingPathComponent(item.filename)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.copyItem(at: resources.appendingPathComponent(item.filename), to: target)
                }
            }
            let bookmark = try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            if let index = snapshot.sources.firstIndex(where: { $0.path == root.path }) {
                var updated = snapshot
                updated.sources[index].detached = nil
                updated.sources[index].bookmark = bookmark
                try repository.commit(updated); snapshot = updated
            } else {
                let source = PhotoSource(name: "示例照片", path: root.path, bookmark: bookmark)
                let result = SampleScanResult()
                _ = try await PhotoScanner.scan(source: source, root: root) { await result.append($0) }
                var photos = await result.photos
                guard photos.count == manifest.photos.count, await result.warnings.isEmpty else {
                    throw LibraryError.unavailable("示例照片未完整读取，请重试。")
                }
                var updated = snapshot
                // New IDs prevent bundled album IDs from colliding with existing imports.
                let albumIDs = Dictionary(uniqueKeysWithValues: manifest.albums.map { ($0.id, UUID()) })
                for i in photos.indices {
                    guard let seed = manifest.photos.first(where: { $0.filename == photos[i].filename }) else { continue }
                    photos[i].rating = seed.rating; photos[i].tags = seed.tags
                    photos[i].isFavorite = seed.favorite
                    photos[i].albumIDs = seed.albumIDs.compactMap { albumIDs[$0] }
                }
                updated.sources.append(source); updated.photos += photos
                updated.albums += manifest.albums.map { album in
                    var copy = album; copy.id = albumIDs[album.id]!
                    return copy
                }
                updated.tags = Array(Set(updated.tags + manifest.tags)).sorted()
                try repository.commit(updated); snapshot = updated
            }
            refreshAccess(); navigation = .all; scheduleQuery()
        } catch { issue = "载入示例失败：\(error.localizedDescription)" }
    }
}
