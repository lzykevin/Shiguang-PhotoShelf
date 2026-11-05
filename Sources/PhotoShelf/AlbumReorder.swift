import SwiftUI

extension LibraryModel {
    @discardableResult
    func reorderAlbum(_ moving: UUID, relativeTo target: UUID, after: Bool) -> Bool {
        guard moving != target,
              let album = snapshot.albums.first(where: { $0.id == moving }),
              snapshot.albums.contains(where: { $0.id == target }) else { return false }
        var albums = snapshot.albums.filter { $0.id != moving }
        let index = albums.firstIndex { $0.id == target }!
        albums.insert(album, at: index + (after ? 1 : 0))
        guard albums.map(\.id) != snapshot.albums.map(\.id) else { return false }
        editLibrary(name: "调整相册顺序") { $0.albums = albums }
        return snapshot.albums.map(\.id) == albums.map(\.id)
    }
}

struct AlbumRowFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct AlbumDragPosition {
    let id: UUID
    let point: CGPoint
}

func albumInsertion(at point: CGPoint, moving: UUID, frames: [UUID: CGRect]) -> (id: UUID, after: Bool)? {
    let rows = frames.filter { $0.key != moving }
    guard let closest = rows.min(by: { abs($0.value.midY - point.y) < abs($1.value.midY - point.y) }),
          point.x >= closest.value.minX, point.x <= closest.value.maxX,
          point.y >= (frames.values.map(\.minY).min() ?? 0) - 16,
          point.y <= (frames.values.map(\.maxY).max() ?? 0) + 16 else { return nil }
    return (closest.key, point.y > closest.value.midY)
}
