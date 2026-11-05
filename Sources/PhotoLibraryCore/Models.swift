import Foundation

public struct PhotoSource: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var bookmark: Data?
    public var lastScan: Date?
    public var detached: Bool?
    public var isDetached: Bool { detached == true }
    public init(id: UUID = UUID(), name: String, path: String, bookmark: Data? = nil) {
        self.id = id; self.name = name; self.path = path; self.bookmark = bookmark
    }
}

public struct Photo: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var sourceID: UUID
    public var relativePath: String
    public var identity: String
    public var filename: String
    public var format: String
    public var byteSize: Int64
    public var width: Int
    public var height: Int
    public var captureDate: Date?
    public var modifiedDate: Date
    public var addedDate = Date()
    public var lastViewed: Date?
    public var camera: String?
    public var lens: String?
    public var exposure: String?
    private var favorite: Bool?
    public var isFavorite: Bool {
        get { favorite ?? false }
        set { favorite = newValue ? true : nil }
    }
    public var rating = 0
    public var tags: [String] = []
    public var note = ""
    public var albumIDs: [UUID] = []
    public var missing = false
    public var decodeError = false
    public var sortDate: Date { captureDate ?? modifiedDate }
    public init(sourceID: UUID, relativePath: String, identity: String, filename: String,
                format: String, byteSize: Int64, width: Int, height: Int,
                captureDate: Date?, modifiedDate: Date, camera: String? = nil,
                lens: String? = nil, exposure: String? = nil, decodeError: Bool = false) {
        self.sourceID = sourceID; self.relativePath = relativePath; self.identity = identity
        self.filename = filename; self.format = format; self.byteSize = byteSize
        self.width = width; self.height = height; self.captureDate = captureDate
        self.modifiedDate = modifiedDate; self.camera = camera; self.lens = lens
        self.exposure = exposure; self.decodeError = decodeError
    }
    public func retainingAnnotations(from old: Photo) -> Photo {
        var copy = self
        copy.isFavorite = old.isFavorite
        copy.id = old.id; copy.rating = old.rating; copy.tags = old.tags
        copy.lastViewed = old.lastViewed; copy.note = old.note; copy.albumIDs = old.albumIDs; copy.addedDate = old.addedDate
        return copy
    }
}

public struct Album: Codable, Identifiable, Equatable, Sendable {
    public var sortOrder: Int?
    public var query: PhotoQuery?
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var version = 3
    public var sources: [PhotoSource] = []
    public var photos: [Photo] = []
    public var albums: [Album] = []
    public var tags: [String] = []
    public init() {}
}

public enum PhotoSort: String, CaseIterable, Codable, Sendable {
    case dateDescending = "拍摄时间：从新到旧"
    case dateAscending = "拍摄时间：从旧到新"
    case name = "文件名"
    case rating = "星级：从高到低"
    case added = "添加时间"
    case nameDescending = "文件名：倒序"
    case ratingAscending = "星级：从低到高"
    case addedAscending = "添加时间：从旧到新"

    public var field: PhotoSortField {
        switch self {
        case .dateDescending, .dateAscending: return .date
        case .name, .nameDescending: return .name
        case .rating, .ratingAscending: return .rating
        case .added, .addedAscending: return .added
        }
    }
    public var ascending: Bool {
        switch self {
        case .dateAscending, .name, .ratingAscending, .addedAscending: return true
        default: return false
        }
    }
    public static func order(field: PhotoSortField, ascending: Bool) -> PhotoSort {
        switch field {
        case .date: return ascending ? .dateAscending : .dateDescending
        case .name: return ascending ? .name : .nameDescending
        case .rating: return ascending ? .ratingAscending : .rating
        case .added: return ascending ? .addedAscending : .added
        }
    }
}

public enum PhotoSortField: String, CaseIterable, Sendable {
    case date = "拍摄日期", added = "添加日期", name = "文件名", rating = "星级"
    public func directionLabel(ascending: Bool) -> String {
        switch self {
        case .date, .added: return ascending ? "从旧到新" : "从新到旧"
        case .name: return ascending ? "名称正序" : "名称倒序"
        case .rating: return ascending ? "从低到高" : "从高到低"
        }
    }
}

public enum LibrarySelection: Hashable, Codable, Sendable {
    case all, folders, recent, viewed, favorites, fiveStar, unrated, source(UUID, String), album(UUID), tag(String)
}

public struct PhotoQuery: Codable, Equatable, Sendable {
    public var favoritesOnly = false
    public var ratings: Set<Int> = []
    public var sources: Set<UUID> = []
    public var availability: Set<String> = []
    public var offlineSources: Set<UUID> = []
    public var navigation: LibrarySelection = .all
    public var search = ""
    public var rating: Int? = nil
    public var format = "全部格式"
    public var formats: Set<String> = []
    public var selectedTags: Set<String> = []
    public var dateFrom: Date? = nil
    public var dateTo: Date? = nil
    public var sort: PhotoSort = .dateDescending
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case favoritesOnly, ratings, sources, availability, offlineSources, navigation, search, rating, format, formats, selectedTags, dateFrom, dateTo, sort
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        favoritesOnly = try values.decodeIfPresent(Bool.self, forKey: .favoritesOnly) ?? false
        ratings = try values.decodeIfPresent(Set<Int>.self, forKey: .ratings) ?? []
        sources = try values.decodeIfPresent(Set<UUID>.self, forKey: .sources) ?? []
        availability = try values.decodeIfPresent(Set<String>.self, forKey: .availability) ?? []
        offlineSources = try values.decodeIfPresent(Set<UUID>.self, forKey: .offlineSources) ?? []
        navigation = try values.decodeIfPresent(LibrarySelection.self, forKey: .navigation) ?? .all
        search = try values.decodeIfPresent(String.self, forKey: .search) ?? ""
        rating = try values.decodeIfPresent(Int.self, forKey: .rating)
        format = try values.decodeIfPresent(String.self, forKey: .format) ?? "全部格式"
        formats = try values.decodeIfPresent(Set<String>.self, forKey: .formats) ?? []
        selectedTags = try values.decodeIfPresent(Set<String>.self, forKey: .selectedTags) ?? []
        dateFrom = try values.decodeIfPresent(Date.self, forKey: .dateFrom)
        dateTo = try values.decodeIfPresent(Date.self, forKey: .dateTo)
        sort = try values.decodeIfPresent(PhotoSort.self, forKey: .sort) ?? .dateDescending
    }
    public func apply(to photos: [Photo], albums: [Album] = []) -> [Photo] {
        let terms = search.split(whereSeparator: \.isWhitespace).map(String.init)
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let albumNames = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0.name) })
        let effectiveRatings = ratings.isEmpty ? Set(rating.map { [$0] } ?? []) : ratings
        let effectiveFormats = formats.isEmpty ? (format == "全部格式" ? [] : Set([format])) : formats
        return photos.filter { photo in
            if favoritesOnly && !photo.isFavorite { return false }
            switch navigation {
            case .all, .folders: break
            case .recent: if photo.addedDate < recentCutoff { return false }
            case .viewed: if photo.lastViewed == nil { return false }
            case .favorites: if !photo.isFavorite { return false }
            case .fiveStar: if photo.rating != 5 { return false }
            case .unrated: if photo.rating != 0 { return false }
            case .source(let id, let path):
                guard photo.sourceID == id else { return false }
                if !path.isEmpty && !photo.relativePath.hasPrefix(path + "/") { return false }
            case .album(let id): if !photo.albumIDs.contains(id) { return false }
            case .tag(let name): if !photo.tags.contains(name) { return false }
            }
            if !effectiveRatings.isEmpty && !effectiveRatings.contains(photo.rating) { return false }
            if !sources.isEmpty && !sources.contains(photo.sourceID) { return false }
            let state = offlineSources.contains(photo.sourceID) ? "离线" : photo.missing ? "缺失" : "在线"
            if !availability.isEmpty && !availability.contains(state) { return false }
            if !effectiveFormats.isEmpty && !effectiveFormats.contains(photo.format) { return false }
            if !selectedTags.isEmpty && selectedTags.isDisjoint(with: photo.tags) { return false }
            if let dateFrom, photo.sortDate < dateFrom { return false }
            if let dateTo, photo.sortDate >= dateTo { return false }
            if terms.isEmpty { return true }
            let text = ([photo.filename, photo.note] + photo.tags + photo.albumIDs.compactMap { albumNames[$0] }).joined(separator: " ")
            return terms.allSatisfy { text.localizedStandardContains($0) }
        }.sorted { a, b in
            if navigation == .viewed, a.lastViewed != b.lastViewed { return (a.lastViewed ?? .distantPast) > (b.lastViewed ?? .distantPast) }
            switch sort {
            case .dateDescending: if a.sortDate != b.sortDate { return a.sortDate > b.sortDate }
            case .dateAscending: if a.sortDate != b.sortDate { return a.sortDate < b.sortDate }
            case .name: if a.filename != b.filename { return a.filename.localizedStandardCompare(b.filename) == .orderedAscending }
            case .rating: if a.rating != b.rating { return a.rating > b.rating }
            case .added: if a.addedDate != b.addedDate { return a.addedDate > b.addedDate }
            case .addedAscending: if a.addedDate != b.addedDate { return a.addedDate < b.addedDate }
            case .ratingAscending: if a.rating != b.rating { return a.rating < b.rating }
            case .nameDescending: if a.filename != b.filename { return a.filename.localizedStandardCompare(b.filename) == .orderedDescending }
            }
            return a.id.uuidString < b.id.uuidString
        }
    }
}

public enum LibraryError: LocalizedError {
    case unsupportedBackup, invalidBackup(String), unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedBackup: return "备份版本不受支持。"
        case .invalidBackup(let reason): return "备份无效：\(reason)"
        case .unavailable(let reason): return reason
        }
    }
}
