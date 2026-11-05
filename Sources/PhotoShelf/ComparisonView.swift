import SwiftUI
import AppKit
import PhotoLibraryCore

struct ComparisonView: View {
    @EnvironmentObject var model: LibraryModel
    @StateObject private var zoom = ComparisonZoomGroup()
    @State private var linked = true
    @State private var actualSize = false
    private var photos: [Photo] { model.comparisonIDs.compactMap { id in model.snapshot.photos.first { $0.id == id } } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("照片对比").font(.system(size: 14, weight: .semibold))
                Text("\(photos.count) 张").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Toggle("同步缩放与移动", isOn: $linked).toggleStyle(.checkbox).font(.system(size: 12))
                Button(actualSize ? "适合窗口" : "100%") { actualSize.toggle() }.frame(width: 80)
                Button("完成") { model.comparisonIDs = [] }.keyboardShortcut(.cancelAction)
            }.padding(.leading, 96).padding(.trailing, 12).frame(height: 36)
                .background {
                    WindowTitleDragArea(nativeTitleTrailingInset: 340)
                        .padding(.leading, 84).padding(.trailing, 340)
                }
                .help("滚轮缩放，拖动查看细节")
            Divider()
            GeometryReader { geometry in
                let columns = photos.count == 3 ? 3 : 2
                let rows = photos.count > 3 ? 2 : 1
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                    ForEach(photos) { photo in
                        ComparisonTile(photo: photo, actualSize: actualSize, zoom: zoom)
                            .frame(height: max(120, (geometry.size.height - CGFloat(rows - 1) * 8) / CGFloat(rows)))
                    }
                }
            }.padding(8)
        }.frame(minWidth: 800, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: linked) { zoom.enabled = linked }
            .onDisappear { model.comparisonIDs = []; model.scheduleQuery() }
    }
}

private struct ComparisonTile: View {
    @EnvironmentObject var model: LibraryModel
    let photo: Photo
    let actualSize: Bool
    let zoom: ComparisonZoomGroup
    @State private var state: PhotoLoadState = .loading
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                ZoomPhoto(photo: photo, url: model.url(for: photo), cacheKey: model.cacheKey(photo), actualSize: actualSize, zoomGroup: zoom, scrollToZoom: true) { state = $0 }
                if state == .unavailable {
                    Label("原片与缓存不可用", systemImage: "photo.badge.exclamationmark").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }
                if state == .loading { ProgressView().controlSize(.small) }
            }.frame(maxHeight: .infinity)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    photoLabel.frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
                    ratingControls.fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    photoLabel
                    HStack { Spacer(minLength: 0); ratingControls }
                }
            }.padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
        }.clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1), lineWidth: 1) }
    }
    private var photoLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(photo.filename).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle).help(photo.filename)
            Text(state == .cached ? "缓存预览" : "\(photo.width) × \(photo.height)").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    private var ratingControls: some View {
        HStack(spacing: 6) {
            StarRating(rating: photo.rating, size: 13) { model.setRating($0, ids: [photo.id]) }
            FavoriteButton(selected: photo.isFavorite) { model.toggleFavorite(ids: [photo.id]) }
        }
    }
}

/// Shares relative zoom and normalized image center, so different photo dimensions remain aligned.
final class ComparisonZoomGroup: ObservableObject {
    var enabled = true
    private let views = NSHashTable<ZoomScrollView>.weakObjects()
    private var updating = false
    func add(_ view: ZoomScrollView) { views.add(view); view.zoomGroup = self }
    func changed(_ source: ZoomScrollView) {
        guard enabled, !updating, source.imageView.image != nil else { return }
        updating = true; defer { updating = false }
        let image = source.imageView.frame
        let visible = source.contentView.bounds
        let center = NSPoint(x: (visible.midX - image.minX) / max(1, image.width), y: (visible.midY - image.minY) / max(1, image.height))
        let fit = min(source.contentSize.width / max(1, image.width), source.contentSize.height / max(1, image.height))
        let factor = source.magnification / max(0.01, fit)
        for target in views.allObjects where target !== source && target.imageView.image != nil {
            target.layoutSubtreeIfNeeded()
            let rect = target.imageView.frame
            let targetFit = min(target.contentSize.width / max(1, rect.width), target.contentSize.height / max(1, rect.height))
            target.magnification = min(target.maxMagnification, max(target.minMagnification, targetFit * factor))
            target.needsLayout = true; target.layoutSubtreeIfNeeded()
            let frame = target.imageView.frame
            var bounds = target.contentView.bounds
            bounds.origin = NSPoint(x: frame.minX + center.x * frame.width - bounds.width / 2, y: frame.minY + center.y * frame.height - bounds.height / 2)
            target.contentView.scroll(to: target.contentView.constrainBoundsRect(bounds).origin)
            target.reflectScrolledClipView(target.contentView)
        }
    }
}
