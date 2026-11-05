import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ScanBatch: Sendable {
    public var photos: [Photo]
    public var warnings: [String]
    public var checkedCount: Int = 0
}

public enum PhotoScanner {
    public static let extensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "dng", "cr2", "cr3", "nef", "nrw", "arw", "raf", "orf", "rw2", "pef", "srw", "raw"]

    /// Batches are delivered before the entire directory is read. Enumeration is
    /// read-only and never enters packages or symbolic links.
    public static func scan(source: PhotoSource, root: URL, existing: [Photo] = [],
                            relativePaths: [String]? = nil,
                            batch: @escaping @Sendable (ScanBatch) async -> Void) async throws -> Set<String> {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: root.path) else {
            throw LibraryError.unavailable("无法访问目录：\(source.name)。请连接硬盘或重新授权。")
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .volumeUUIDStringKey]
        let known = Dictionary(existing.filter { $0.sourceID == source.id }.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        let errors = EnumerationErrors()
        var pending: [Photo] = [], identities = Set<String>(), checked = 0
        let scopes = normalizedScopes(relativePaths ?? [""])
        for scope in scopes {
            try Task.checkCancellation()
            guard !scope.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { continue }
            let target = root.appendingPathComponent(scope).standardizedFileURL
            var ancestor = target
            var insidePackage = false
            while ancestor.path != root.path && ancestor.path.hasPrefix(root.path + "/") {
                if (try? ancestor.resourceValues(forKeys: [.isPackageKey]).isPackage) == true { insidePackage = true; break }
                ancestor.deleteLastPathComponent()
            }
            if insidePackage { continue }
            guard target.path == root.path || target.path.hasPrefix(root.path + "/") else { continue }
            // A deleted path is a successful empty scan of that scope. Permission
            // failures are errors, never evidence that indexed photos disappeared.
            let targetValues: URLResourceValues
            do { targetValues = try target.resourceValues(forKeys: Set(keys)) }
            catch {
                let e = error as NSError
                if e.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(e.code) { continue }
                errors.append("\(target.lastPathComponent)：\(error.localizedDescription)"); continue
            }
            if targetValues.isSymbolicLink == true { continue }
            // Do not traverse a symlink in an intermediate path of a file event.
            guard target.resolvingSymlinksInPath().path == target.path else { continue }
            var enumerator: FileManager.DirectoryEnumerator?
            if targetValues.isDirectory == true {
                enumerator = FileManager.default.enumerator(at: target, includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
                        errors.append("\(url.lastPathComponent)：\(error.localizedDescription)"); return true
                    })
                if enumerator == nil { errors.append("无法扫描：\(target.lastPathComponent)"); continue }
            }
            var single: URL? = enumerator == nil ? target : nil
            while let url = enumerator.flatMap({ nextURL($0) }) ?? single {
                single = nil
                try Task.checkCancellation()
                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    if values.isSymbolicLink == true { enumerator?.skipDescendants(); continue }
                    guard values.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) else { continue }
                    let url = url.standardizedFileURL.resolvingSymlinksInPath()
                    let relative = String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let identity = fileIdentity(url: url, values: values)
                    identities.insert(identity + "\u{0}" + relative)
                    checked += 1
                    if let old = known[relative], old.identity == identity,
                       old.byteSize == Int64(values.fileSize ?? 0),
                       old.modifiedDate == (values.contentModificationDate ?? .distantPast), !old.decodeError {
                        if old.missing { var restored = old; restored.missing = false; pending.append(restored) }
                    } else {
                        pending.append(autoreleasepool { read(url: url, sourceID: source.id, root: root, values: values, identity: identity) })
                    }
                    if checked == 64 {
                        await batch(ScanBatch(photos: pending, warnings: [], checkedCount: checked))
                        pending.removeAll(keepingCapacity: true); checked = 0
                    }
                } catch { errors.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            }
        }
        try Task.checkCancellation()
        await batch(ScanBatch(photos: pending, warnings: errors.values, checkedCount: checked))
        if !errors.values.isEmpty { throw LibraryError.unavailable("扫描未完整完成：\(errors.values.prefix(3).joined(separator: "；"))。已有记录已保留。") }
        return identities
    }

    public static func normalizedScopes(_ paths: [String]) -> [String] {
        var result: [String] = []
        for path in Set(paths).sorted(by: { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }) {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { continue }
            if !result.contains(where: { covers(path, scopes: [$0]) }) { result.append(path) }
        }
        return result
    }

    public static func covers(_ path: String, scopes: [String]) -> Bool {
        scopes.contains { $0.isEmpty || path == $0 || path.hasPrefix($0 + "/") }
    }

    private static func fileIdentity(url: URL, values: URLResourceValues) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let inode = (attributes?[.systemFileNumber] as? NSNumber)?.stringValue ?? url.path
        let volume = values.volumeUUIDString ?? "volume-unavailable"
        return volume == "volume-unavailable" ? "path:\(url.standardizedFileURL.path)" : "\(volume):\(inode)"
    }

    private static func nextURL(_ enumerator: FileManager.DirectoryEnumerator) -> URL? { enumerator.nextObject() as? URL }

    private static func read(url: URL, sourceID: UUID, root: URL, values: URLResourceValues, identity: String) -> Photo {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        let relative = String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        let props = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff[kCGImagePropertyTIFFDateTime] as? String
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        var camera = [tiff[kCGImagePropertyTIFFMake] as? String, tiff[kCGImagePropertyTIFFModel] as? String].compactMap { $0 }.joined(separator: " ")
        if camera.isEmpty { camera = "" }
        let aperture = (exif[kCGImagePropertyExifFNumber] as? NSNumber).map { "ƒ/\($0)" }
        let focal = (exif[kCGImagePropertyExifFocalLength] as? NSNumber).map { "\($0) mm" }
        let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first.map { "ISO \($0)" }
        let shutter = (exif[kCGImagePropertyExifExposureTime] as? NSNumber).map { value -> String in
            let seconds = value.doubleValue
            return seconds > 0 && seconds < 1 ? "1/\(Int((1 / seconds).rounded())) s" : "\(seconds) s"
        }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        return Photo(sourceID: sourceID, relativePath: relative, identity: identity, filename: url.lastPathComponent,
            format: url.pathExtension.uppercased(), byteSize: Int64(values.fileSize ?? 0),
            width: orientation >= 5 ? height : width, height: orientation >= 5 ? width : height,
            captureDate: dateString.flatMap { formatter.date(from: $0) }, modifiedDate: values.contentModificationDate ?? .distantPast,
            camera: camera.isEmpty ? nil : camera, lens: exif[kCGImagePropertyExifLensModel] as? String,
            exposure: [aperture, shutter, iso, focal].compactMap { $0 }.joined(separator: " · "), decodeError: source == nil || width == 0)
    }
}

private final class EnumerationErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var values: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ string: String) { lock.lock(); defer { lock.unlock() }; storage.append(string) }
}

public enum ScanMerge {
    public static func merge(existing: [Photo], incoming: [Photo]) -> [Photo] {
        // Hard links can share a file ID; path disambiguates these without conflating annotations.
        var result = existing
        for photo in incoming {
            let candidates = result.indices.filter { result[$0].sourceID == photo.sourceID && result[$0].identity == photo.identity }
            let match = candidates.first { result[$0].relativePath == photo.relativePath } ?? (candidates.count == 1 ? candidates.first : nil)
            if let match { result[match] = photo.retainingAnnotations(from: result[match]) }
            else { result.append(photo) }
        }
        return result
    }
}
