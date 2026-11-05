import AppKit
import ImageIO
import CryptoKit

final class ThumbnailService: @unchecked Sendable {
    static let shared = ThumbnailService()
    private let memory = NSCache<NSString, NSImage>()
    private let queue = OperationQueue()
    private let directory: URL
    private let maintenance = DispatchQueue(label: "PhotoShelf.cacheMaintenance", qos: .utility)
    private let trimLock = NSLock()
    private var writesSinceTrim = 0
    init() {
        memory.totalCostLimit = 160 * 1024 * 1024
        queue.maxConcurrentOperationCount = 3; queue.qualityOfService = .userInitiated
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PhotoShelf/Thumbnails")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        scheduleTrim(force: true)
    }
    private func scheduleTrim(force: Bool = false) {
        trimLock.lock(); writesSinceTrim += 1
        let shouldTrim = force || writesSinceTrim >= 128
        if shouldTrim { writesSinceTrim = 0 }
        trimLock.unlock()
        guard shouldTrim else { return }
        maintenance.async { [directory] in
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
            var size = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            for file in files.sorted(by: { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }) {
                if size <= 768 * 1024 * 1024 { break }
                let bytes = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                try? FileManager.default.removeItem(at: file); size -= bytes
            }
        }
    }
    func load(url: URL?, key: String, size: Int = 512, completion: @escaping (NSImage?) -> Void) -> Operation? {
        let token = "\(key)-\(size)" as NSString
        if let cached = memory.object(forKey: token) { completion(cached); return nil }
        let file = directory.appendingPathComponent(SHA256.hash(data: Data(token.description.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg")
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation, weak self] in
            guard let self, let operation, !operation.isCancelled else { return }
            let image: NSImage? = autoreleasepool {
                if size <= 512,
                   let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                   let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                    let cached = NSImage(cgImage: cg, size: .zero)
                    // Disk hits must join the memory cache too, otherwise every
                    // navigation reload briefly replaces images with placeholders.
                    self.memory.setObject(cached, forKey: token, cost: cg.bytesPerRow * cg.height)
                    return cached
                }
                guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                    let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: size,
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary) else { return nil }
                if size <= 512 {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.84]) { try? data.write(to: file, options: .atomic); self.scheduleTrim() }
                }
                self.memory.setObject(NSImage(cgImage: cg, size: .zero), forKey: token, cost: cg.bytesPerRow * cg.height)
                return NSImage(cgImage: cg, size: .zero)
            }
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { if !operation.isCancelled { completion(image) } }
        }
        queue.addOperation(operation)
        return operation
    }
    func cacheUsageBytes() async -> Int64 {
        await withCheckedContinuation { continuation in
            maintenance.async { [directory] in
                let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                continuation.resume(returning: files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) })
            }
        }
    }
    func clear() { memory.removeAllObjects(); try? FileManager.default.removeItem(at: directory); try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
}
