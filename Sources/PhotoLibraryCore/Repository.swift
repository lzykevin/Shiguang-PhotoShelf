import Foundation
import CoreData

/// Core Data is the durable source of truth. JSON payloads keep the portable backup
/// and on-disk model identical; separate records make rating writes incremental.
@MainActor public final class LibraryRepository {
    private let container: NSPersistentContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public let directory: URL

    public init(directory: URL, inMemory: Bool = false) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = NSManagedObjectModel()
        model.entities = ["Source", "Photo", "Album", "Tag"].map { name in
            let entity = NSEntityDescription()
            entity.name = name; entity.managedObjectClassName = "NSManagedObject"
            let id = NSAttributeDescription(); id.name = "key"; id.attributeType = .stringAttributeType; id.isOptional = false
            let data = NSAttributeDescription(); data.name = "payload"; data.attributeType = .binaryDataAttributeType; data.isOptional = false
            entity.properties = [id, data]; entity.uniquenessConstraints = [["key"]]
            return entity
        }
        container = NSPersistentContainer(name: "PhotoShelf", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("Library.sqlite"))
        if inMemory { description.type = NSInMemoryStoreType }
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private func readSnapshot() throws -> LibrarySnapshot {
        var snapshot = LibrarySnapshot()
        snapshot.sources = try fetch("Source", as: PhotoSource.self)
        snapshot.photos = try fetch("Photo", as: Photo.self)
        snapshot.albums = try fetch("Album", as: Album.self).enumerated().sorted {
            ($0.element.sortOrder ?? $0.offset) < ($1.element.sortOrder ?? $1.offset)
        }.map(\.element)
        snapshot.tags = try fetch("Tag", as: String.self).sorted()
        return snapshot
    }

    public func load() throws -> LibrarySnapshot {
        let snapshot = try readSnapshot()
        try ensureUpgradeBackup(snapshot)
        return snapshot
    }

    /// Run before the first write as well as load: callers need not load first.
    /// Internal upgrade backups preserve permissions; portable exports do not.
    private func ensureUpgradeBackup(_ existing: LibrarySnapshot? = nil) throws {
        let marker = directory.appendingPathComponent("ProductSchema-v3")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let snapshot = try existing ?? readSnapshot()
        if !snapshot.photos.isEmpty || !snapshot.sources.isEmpty || !snapshot.albums.isEmpty || !snapshot.tags.isEmpty {
            let backupEncoder = JSONEncoder()
            backupEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            backupEncoder.dateEncodingStrategy = .secondsSince1970
            try backupEncoder.encode(snapshot).write(to: directory.appendingPathComponent("BeforeUpgrade-v3-\(UUID().uuidString).json"), options: .atomic)
        }
        try Data("3".utf8).write(to: marker, options: .atomic)
    }

    public func commit(_ snapshot: LibrarySnapshot, replacing: Bool = false) throws {
        try Self.validate(snapshot)
        try ensureUpgradeBackup()
        let context = container.viewContext
        do {
            try sync("Source", values: snapshot.sources.map { ($0.id.uuidString, try encoder.encode($0)) }, replacing: replacing)
            try sync("Photo", values: snapshot.photos.map { ($0.id.uuidString, try encoder.encode($0)) }, replacing: replacing)
            try sync("Album", values: snapshot.albums.enumerated().map { index, value in
                var album = value; album.sortOrder = index
                return (album.id.uuidString, try encoder.encode(album))
            }, replacing: replacing)
            try sync("Tag", values: snapshot.tags.map { ($0, try encoder.encode($0)) }, replacing: replacing)
            if context.hasChanges { try context.save() }
        } catch { context.rollback(); throw error }
    }

    public func savePhotos(_ photos: [Photo]) throws {
        // Validate incremental writes against durable relationships without loading the photo table.
        var references = LibrarySnapshot()
        references.sources = try fetch("Source", as: PhotoSource.self)
        references.albums = try fetch("Album", as: Album.self)
        references.tags = try fetch("Tag", as: String.self)
        references.photos = photos
        try Self.validate(references)
        try ensureUpgradeBackup()
        do {
            for photo in photos { try upsert("Photo", key: photo.id.uuidString, data: encoder.encode(photo)) }
            if container.viewContext.hasChanges { try container.viewContext.save() }
        } catch { container.viewContext.rollback(); throw error }
    }

    /// Commit only the source scan stamp and availability changes, not the whole catalog.
    public func saveScanCompletion(source: PhotoSource, photos: [Photo]) throws {
        var references = LibrarySnapshot()
        references.sources = try fetch("Source", as: PhotoSource.self)
        references.albums = try fetch("Album", as: Album.self)
        references.tags = try fetch("Tag", as: String.self)
        references.photos = photos
        try Self.validate(references)
        guard references.sources.contains(where: { $0.id == source.id }),
              photos.allSatisfy({ $0.sourceID == source.id }) else {
            throw LibraryError.unavailable("照片来源已变更，请重新刷新")
        }
        try ensureUpgradeBackup()
        do {
            try upsert("Source", key: source.id.uuidString, data: encoder.encode(source))
            for photo in photos { try upsert("Photo", key: photo.id.uuidString, data: encoder.encode(photo)) }
            if container.viewContext.hasChanges { try container.viewContext.save() }
        } catch { container.viewContext.rollback(); throw error }
    }

    private func fetch<T: Decodable>(_ name: String, as: T.Type) throws -> [T] {
        try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: name)).map {
            try decoder.decode(T.self, from: $0.value(forKey: "payload") as! Data)
        }
    }
    private func upsert(_ name: String, key: String, data: Data) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: name)
        request.predicate = NSPredicate(format: "key == %@", key); request.fetchLimit = 1
        let object = try container.viewContext.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: name, into: container.viewContext)
        if object.value(forKey: "payload") as? Data != data {
            object.setValue(key, forKey: "key"); object.setValue(data, forKey: "payload")
        }
    }
    private func sync(_ name: String, values: [(String, Data)], replacing: Bool) throws {
        let existing = try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: name))
        var objects = Dictionary(uniqueKeysWithValues: existing.map { ($0.value(forKey: "key") as! String, $0) })
        for (key, data) in values {
            let object = objects.removeValue(forKey: key) ?? NSEntityDescription.insertNewObject(forEntityName: name, into: container.viewContext)
            if object.value(forKey: "payload") as? Data != data {
                object.setValue(key, forKey: "key"); object.setValue(data, forKey: "payload")
            }
        }
        // Every caller supplies a complete snapshot; removed objects must stay removed.
        for object in objects.values { container.viewContext.delete(object) }
    }

    public static func exportData(_ snapshot: LibrarySnapshot) throws -> Data {
        var portable = snapshot
        portable.version = 3
        for index in portable.sources.indices { portable.sources[index].bookmark = nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(portable)
    }
    public static func importData(_ data: Data) throws -> LibrarySnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let seconds = try? value.decode(Double.self) { return Date(timeIntervalSince1970: seconds) }
            let text = try value.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid date")
        }
        let snapshot = try decoder.decode(LibrarySnapshot.self, from: data)
        try validate(snapshot)
        return snapshot
    }
    public static func validate(_ snapshot: LibrarySnapshot) throws {
        guard (1...3).contains(snapshot.version) else { throw LibraryError.unsupportedBackup }
        let sources = Set(snapshot.sources.map(\.id)), albums = Set(snapshot.albums.map(\.id))
        guard sources.count == snapshot.sources.count,
              albums.count == snapshot.albums.count,
              Set(snapshot.photos.map(\.id)).count == snapshot.photos.count,
              Set(snapshot.tags).count == snapshot.tags.count else { throw LibraryError.invalidBackup("存在重复标识") }
        for album in snapshot.albums {
            if let query = album.query {
                guard query.ratings.isSubset(of:Set(0...5)), query.rating.map({ (0...5).contains($0) }) ?? true, query.availability.isSubset(of:["在线","离线","缺失"]), query.dateFrom == nil || query.dateTo == nil || query.dateFrom! < query.dateTo! else { throw LibraryError.invalidBackup("智能相册条件不正确") }
                if case .source(_, let path) = query.navigation,
                   path.hasPrefix("/") || path.split(separator: "/").contains("..") {
                    throw LibraryError.invalidBackup("智能相册文件夹条件不正确")
                }
                if case .album(let id) = query.navigation, snapshot.albums.first(where:{$0.id == id})?.query != nil { throw LibraryError.invalidBackup("不支持智能相册嵌套") }
            }
        }
        for photo in snapshot.photos {
            let parts = photo.relativePath.split(separator: "/")
            guard sources.contains(photo.sourceID), (0...5).contains(photo.rating),
                  !photo.relativePath.hasPrefix("/"), !parts.contains(".."), !parts.contains("."), !parts.isEmpty,
                  !photo.relativePath.contains("\0"), photo.filename == parts.last.map(String.init),
                  Set(photo.albumIDs).isSubset(of: albums), Set(photo.tags).isSubset(of: Set(snapshot.tags)) else {
                throw LibraryError.invalidBackup("照片关联、路径或星级不正确")
            }
        }
    }
}
