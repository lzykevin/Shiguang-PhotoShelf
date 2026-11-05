import SwiftUI
import PhotoLibraryCore

struct GalleryView: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.colorScheme) private var scheme
    private var photo: Photo? { model.visible.first { model.selection.contains($0.id) } ?? model.visible.first }
    private var palette: DesignPalette { DesignPalette(dark: scheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            if let photo {
                GeometryReader { geometry in
                    PhotoPreview(photo: photo, url: model.url(for: photo), cacheKey: model.cacheKey(photo), size: 2048)
                        .frame(width: max(0, geometry.size.width-64), height: max(0, geometry.size.height-40))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.openViewer(photo.id) }
                        .accessibilityLabel("\(photo.filename)，双击全屏查看")
                }
                HStack(spacing: 16) {
                    Button { model.step(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                        .disabled(photo.id == model.visible.first?.id).help("上一张 · ←")
                    VStack(spacing: 4) {
                        Text(photo.filename).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text("\((model.visible.firstIndex { $0.id == photo.id } ?? 0)+1) / \(model.visible.count)")
                            .font(.system(size: 10)).monospacedDigit().foregroundStyle(palette.muted)
                    }.frame(maxWidth: 260)
                    Button { model.step(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }
                        .disabled(photo.id == model.visible.last?.id).help("下一张 · →")
                    FavoriteButton(selected: photo.isFavorite) { model.toggleFavorite(ids: [photo.id]) }
                    StarRating(rating: photo.rating, size: 12) { model.selectPhoto(photo.id); model.setRating($0) }
                }
                .buttonStyle(QuietToolbarStyle()).padding(.bottom, 18)
                if model.url(for: photo) == nil {
                    Text("原片不可用 · 显示缓存预览").font(.system(size: 11)).foregroundStyle(palette.muted).padding(.bottom, 10)
                }
                Divider()
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(model.visible) { item in
                                Button { model.selectPhoto(item.id) } label: {
                                    PhotoPreview(photo: item, url: model.url(for: item), cacheKey: model.cacheKey(item))
                                        .frame(width: 82, height: 64)
                                        .padding(4)
                                        .background(item.id == photo.id ? palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(item.id == photo.id ? palette.accent : .clear, lineWidth: 1.5))
                                        .contentShape(Rectangle())
                                }.buttonStyle(RowFeedbackStyle()).help(item.filename)
                                    .accessibilityLabel(item.filename)
                                    .accessibilityAddTraits(item.id == photo.id ? .isSelected : [])
                                    .id(item.id)
                            }
                        }.padding(.horizontal, 24).padding(.vertical, 14)
                    }.frame(height: 100)
                        .onAppear { proxy.scrollTo(photo.id, anchor: .center) }
                        .onChange(of: photo.id) { proxy.scrollTo(photo.id, anchor: .center) }
                }
            }
        }
        .onAppear { if model.selection.isEmpty, let first = model.visible.first { model.selectPhoto(first.id) } }
        .onChange(of: model.visible.map(\.id)) {
            if !model.visible.contains(where: { model.selection.contains($0.id) }), let first = model.visible.first { model.selectPhoto(first.id) }
        }
    }
}
