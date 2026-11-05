import SwiftUI
import PhotoLibraryCore

struct PhotoPreview: View {
    let photo: Photo
    let url: URL?
    let cacheKey: String
    var size = 512
    @State private var image: NSImage?
    @State private var operation: Operation?
    var body: some View {
        ZStack {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: cacheKey + "\(size)") {
            operation?.cancel(); image = nil
            operation = ThumbnailService.shared.load(url: url, key: cacheKey, size: size) { image = $0 }
        }
        .onDisappear { operation?.cancel() }
    }
}

struct StarRating: View {
    var rating: Int?
    var size: CGFloat = 13
    var inactiveColor: Color? = nil
    var set: (Int) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = 0
    private var p: DesignPalette { DesignPalette(dark: colorScheme == .dark) }
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { value in
                Button { set(rating == value ? 0 : value) } label: {
                    Image(systemName: value <= (hover > 0 ? hover : rating ?? 0) ? "star.fill" : "star")
                        .font(.system(size: size, weight: .regular))
                        .foregroundStyle(value <= (hover > 0 ? hover : rating ?? 0) ? Color(red: 0.85, green: 0.68, blue: 0.38) : (inactiveColor ?? p.muted.opacity(0.8)))
                        .frame(width: 24, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).onHover { hover = $0 ? value : 0 }
                    .help(rating == value ? "再次点击清除评分 · 0" : "评为 \(value) 星 · \(value)")
                    .accessibilityLabel(rating == value ? "清除评分" : "评为 \(value) 星")
                    .accessibilityValue(rating.map { "当前 \($0) 星" } ?? "多个值")
            }
            Button { set(0) } label: {
                Image(systemName: "xmark.circle").font(.system(size: 11)).foregroundStyle(inactiveColor ?? p.muted)
                    .frame(width: 18, height: 30).contentShape(Rectangle())
            }.buttonStyle(RowFeedbackStyle()).help("清除星级 · 0").accessibilityLabel("清除评分")
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hover)
            .onChange(of: rating) { _, _ in hover = 0 }
    }
}

struct InspectorView: View {
    @EnvironmentObject var model: LibraryModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editingNote: Bool
    private var p: DesignPalette { DesignPalette(dark: colorScheme == .dark) }
    @State private var tagInput = ""
    @State private var noteDraft = ""
    @State private var notePhotoID: UUID?
    @State private var saveTask: Task<Void, Never>?
    var body: some View {
        ScrollView {
            if model.selectedPhotos.count > 1 && model.viewerID == nil { batchInspector }
            else if let photo = model.focusedPhoto { singleInspector(photo) }
            else {
                VStack(spacing: 13) {
                    Image(systemName: "photo").font(.system(size: 24, weight: .light))
                    Text("选择照片以查看信息").font(.system(size: 12))
                    Text("按 0–5 评分 · 空格查看大图").font(.system(size: 10))
                }.foregroundStyle(p.muted).frame(maxWidth: .infinity).padding(.top, 72)
            }
        }
        .background(p.inspector)
        .onDisappear { flushNote() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in flushNote() }
    }
    private func singleInspector(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                FavoriteButton(selected: photo.isFavorite) { model.toggleFavorite(ids: [photo.id]) }
                Text("照片信息").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(photo.format).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(p.muted)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(p.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
            }.padding(.bottom, 14)
            PhotoPreview(photo: photo, url: model.url(for: photo), cacheKey: model.cacheKey(photo))
                .frame(height: 132).frame(maxWidth: .infinity)
                .background(p.canvas, in: RoundedRectangle(cornerRadius: 6)).clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(p.line, lineWidth: 1) }
            Text(photo.filename).font(.system(size: 16, weight: .semibold)).textSelection(.enabled).lineLimit(2).padding(.top, 16)
            if model.offline.contains(photo.sourceID) || photo.missing {
                Label(model.offline.contains(photo.sourceID) ? "来源离线 · 已保留整理信息" : "原文件缺失 · 已保留整理信息", systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange).padding(.top, 8)
            }
            if photo.decodeError {
                Label("系统暂不支持此照片的预览", systemImage: "photo.badge.exclamationmark")
                    .font(.system(size: 11)).foregroundStyle(p.muted).padding(.top, 8)
            }
            HStack(spacing: 4) {
                Text("评分").font(.system(size: 12)).foregroundStyle(p.muted)
                Spacer(minLength: 2)
                StarRating(rating: photo.rating) { value in
                    if model.viewerID == nil { model.selection = [photo.id] }; model.setRating(value)
                }.id(photo.id)
            }.padding(.top, 10)
            sectionDivider
            caption("标签")
            if !photo.tags.isEmpty { tagList(photo.tags, ids: [photo.id]).padding(.top, 9) }
            tagField(ids: [photo.id]).padding(.top, 9)
            sectionDivider
            caption("备注")
            ZStack(alignment: .topLeading) {
                if noteDraft.isEmpty { Text("记下这个瞬间…").font(.system(size: 12)).foregroundStyle(p.muted).padding(10).allowsHitTesting(false) }
                TextEditor(text: $noteDraft).font(.system(size: 12)).lineSpacing(4).scrollContentBackground(.hidden)
                    .focused($editingNote).padding(6).frame(minHeight: 82, maxHeight: 120)
            }.background(p.canvas.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(editingNote ? p.accent.opacity(0.65) : p.line, lineWidth: 1) }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: editingNote)
                .padding(.top, 9).accessibilityLabel("照片备注")
                .onChange(of: photo.id, initial: true) { flushNote(); notePhotoID = photo.id; noteDraft = photo.note }
                .onChange(of: photo.note) { if noteDraft != photo.note { saveTask?.cancel(); noteDraft = photo.note } }
                .onChange(of: noteDraft) {
                    saveTask?.cancel()
                    let text = noteDraft, id = notePhotoID
                    saveTask = Task { try? await Task.sleep(for: .milliseconds(450)); guard !Task.isCancelled, let id else { return }; model.setNote(text, photoID: id) }
                }
            sectionDivider
            caption("文件信息")
            VStack(spacing: 12) {
                info(photo.captureDate == nil ? "修改时间" : "拍摄时间", photo.sortDate.formatted(date: .numeric, time: .shortened))
                info("尺寸", photo.width > 0 ? "\(photo.width) × \(photo.height)" : "未知")
                info("格式", photo.format)
                info("大小", ByteCountFormatter.string(fromByteCount: photo.byteSize, countStyle: .file))
                let albumNames = model.snapshot.albums.filter { $0.query == nil && photo.albumIDs.contains($0.id) }.map(\.name)
                info("所在相册", albumNames.isEmpty ? "未加入相册" : albumNames.joined(separator: "、"))
                if let camera = photo.camera { info("相机", camera) }
                if let lens = photo.lens { info("镜头", lens) }
                if let exposure = photo.exposure, !exposure.isEmpty { info("拍摄参数", exposure) }
            }.padding(.top, 14)
            if photo.captureDate == nil {
                Text("未读取到拍摄时间，排序使用文件修改时间。")
                    .font(.system(size: 11)).foregroundStyle(p.muted).padding(.top, 12)
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "folder")
                Text(photo.relativePath).lineLimit(3).textSelection(.enabled)
            }.font(.system(size: 11)).foregroundStyle(p.muted).padding(.top, 22)
            Button("在 Finder 中显示") { model.reveal(photo) }
                .buttonStyle(RowFeedbackStyle()).font(.system(size: 11)).foregroundStyle(p.accent)
                .padding(.top, 9).disabled(model.offline.contains(photo.sourceID) || photo.missing)
        }.padding(18)
    }
    private var sectionDivider: some View {
        Rectangle().fill(p.line).frame(height: 1).padding(.vertical, 16)
    }
    private var batchInspector: some View {
        let photos = model.selectedPhotos
        let ratings = Set(photos.map(\.rating))
        let common = photos.dropFirst().reduce(Set(photos.first?.tags ?? [])) { $0.intersection($1.tags) }
        let all = Set(photos.flatMap(\.tags))
        return VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "photo.stack").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(.secondary).padding(.top, 15)
            Text("已选择 \(photos.count) 张照片").font(.headline)
            HStack {
                Text("已收藏 \(photos.filter(\.isFavorite).count) / \(photos.count) 张").font(.system(size:12)).foregroundStyle(p.muted)
                Spacer()
                Button(model.allTargetsFavorite ? "取消全部收藏" : "全部收藏") { model.toggleFavorite() }.buttonStyle(RowFeedbackStyle()).foregroundStyle(p.accent)
            }
            caption(ratings.count > 1 ? "星级 · 多个值" : "统一设置星级")
            StarRating(rating: ratings.count == 1 ? ratings.first : nil) { model.setRating($0) }
            Divider(); caption("共同标签")
            tagList(common.sorted(), ids: model.selection)
            if all != common {
                caption("部分照片的标签")
                tagList(all.subtracting(common).sorted(), ids: model.selection)
                Text("移除会对所有选中照片生效；添加会保留原有标签。").font(.caption).foregroundStyle(.secondary)
            }
            tagField(ids: model.selection)
            Divider(); caption("相册归属")
            if model.snapshot.albums.filter({ $0.query == nil }).isEmpty { Button("新建相册…") { model.createAlbum() } }
            ForEach(model.snapshot.albums.filter { $0.query == nil }) { album in
                let count = photos.filter { $0.albumIDs.contains(album.id) }.count
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(album.name).lineLimit(1)
                        Text(count == photos.count ? "全部已加入" : count == 0 ? "尚未加入" : "部分已加入 · \(count) 张")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if count < photos.count { Button("加入") { model.addToAlbum(album) }.buttonStyle(.link) }
                    if count > 0 { Button("移出") { model.removeFromAlbum(album) }.buttonStyle(.link) }
                }.font(.system(size: 12))
            }
            Text("批量操作可用 ⌘Z 撤销。").font(.caption).foregroundStyle(.tertiary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func caption(_ title: String) -> some View { Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(p.muted) }
    private func info(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) { Text(title).foregroundStyle(p.muted); Spacer(minLength: 4); Text(value).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.system(size: 12))
    }
    private func tagList(_ tags: [String], ids: Set<UUID>) -> some View {
        TagFlowLayout {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 0) {
                    Button { flushNote(); model.navigation = .tag(tag) } label: {
                        Text(tag).lineLimit(1).padding(.leading, 9).padding(.trailing, 5).padding(.vertical, 6)
                    }.buttonStyle(RowFeedbackStyle()).help("查看带有“\(tag)”的照片")
                    Button { model.removeTag(tag, ids: ids) } label: {
                        Image(systemName: "xmark").font(.system(size: 8)).frame(width: 22, height: 25).contentShape(Rectangle())
                    }.buttonStyle(RowFeedbackStyle()).help("移除标签").accessibilityLabel("移除标签 \(tag)")
                }.font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.8))
                    .background(p.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
    private func tagField(ids: Set<UUID>) -> some View {
        HStack {
            StableTagField(text: $tagInput) { model.addTag(tagInput, to: ids); tagInput = "" }.frame(height: 16)
            Menu {
                ForEach(model.snapshot.tags, id: \.self) { tag in Button(tag) { model.addTag(tag, to: ids) } }
                if model.snapshot.tags.isEmpty { Text("输入名称后按回车创建") }
            } label: { Image(systemName: "plus.circle") }.menuStyle(.borderlessButton).fixedSize()
        }.padding(8).background(p.canvas.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(p.line, lineWidth: 1) }
    }
    private func flushNote() {
        saveTask?.cancel()
        if let id = notePhotoID, let photo = model.snapshot.photos.first(where: { $0.id == id }), photo.note != noteDraft { model.setNote(noteDraft, photoID: id) }
    }
}

struct TagFlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { arrange(subviews, width: proposal.width ?? 250).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, point) in result.points.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0; var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += line + 6; line = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + 6; line = max(line, size.height)
        }
        return (CGSize(width: width, height: y + line), points)
    }
}
