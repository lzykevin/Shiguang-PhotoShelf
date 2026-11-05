import SwiftUI
import AppKit
import PhotoLibraryCore

struct PhotoGrid: NSViewRepresentable {
    @ObservedObject var model: LibraryModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    @MainActor static func makeCollectionView() -> PhotoCollectionView {
        let collection = PhotoCollectionView()
        collection.isSelectable = true; collection.allowsMultipleSelection = true
        collection.backgroundColors = [.clear]
        let layout = PhotoFlowLayout(); layout.minimumInteritemSpacing = 14; layout.minimumLineSpacing = 16
        layout.sectionInset = NSEdgeInsets(top: 12, left: 22, bottom: 18, right: 22)
        collection.collectionViewLayout = layout
        // Switching from legacy to modern layout clears legacy registrations.
        collection.register(PhotoItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("photo"))
        collection.register(DateHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: NSUserInterfaceItemIdentifier("date"))
        return collection
    }
    func makeNSView(context: Context) -> NSScrollView {
        let collection = Self.makeCollectionView()
        collection.delegate = context.coordinator; collection.dataSource = context.coordinator
        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.openFromGesture(_:)))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        collection.addGestureRecognizer(doubleClick)
        collection.model = model
        let scroll = AnchoredPhotoScrollView(); scroll.documentView = collection
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        context.coordinator.collection = collection
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        // Capture the old position before SwiftUI changes the available width.
        if let scroll = scroll as? AnchoredPhotoScrollView {
            scroll.captureAnchor(selectedIDs: model.selection, sections: coordinator.sections)
        }
        coordinator.updateContent()
        if let layout = coordinator.collection?.collectionViewLayout as? PhotoFlowLayout {
            let target = CGFloat(model.thumbnailSize)
            if layout.targetWidth != target || layout.mode != model.gridLayout {
                coordinator.changeLayout(layout, targetWidth: target, mode: model.gridLayout, in: scroll)
            }
        }
        let paths = Set(coordinator.sections.enumerated().flatMap { section, value in
            value.1.enumerated().compactMap { item, photo in model.selection.contains(photo.id) ? IndexPath(item: item, section: section) : nil }
        })
        if coordinator.collection?.selectionIndexPaths != paths { coordinator.collection?.selectionIndexPaths = paths }
        if coordinator.needsRestore, !paths.isEmpty, let collection = coordinator.collection {
            coordinator.needsRestore = false
            DispatchQueue.main.async {
                guard let first = paths.sorted(by: { $0.section == $1.section ? $0.item < $1.item : $0.section < $1.section }).first,
                      let frame = collection.collectionViewLayout?.layoutAttributesForItem(at:first)?.frame,
                      let scroll = collection.enclosingScrollView else { return }
                let clip = scroll.contentView
                if clip.bounds.contains(frame) { return }
                let y = max(0,min(frame.midY-clip.bounds.height/2, collection.bounds.height-clip.bounds.height))
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
                    context.timingFunction = CAMediaTimingFunction(name:.easeOut)
                    clip.animator().setBoundsOrigin(NSPoint(x:clip.bounds.minX,y:y))
                } completionHandler: { scroll.reflectScrolledClipView(clip) }
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        var model: LibraryModel
        var photos: [Photo] = []
        var showNames = true
        var grouped = true
        var groupedByDay = false
        var needsRestore = true
        var sections: [(String, [Photo])] = []
        weak var collection: NSCollectionView?
        func changeLayout(_ layout: PhotoFlowLayout, targetWidth: CGFloat, mode: String, in scroll: NSScrollView) {
            guard let collection else { return }
            let clip = scroll.contentView
            let viewport = clip.bounds
            let visible = (layout.layoutAttributesForElements(in: viewport) ?? [])
                .filter { $0.representedElementCategory == .item && $0.frame.intersects(viewport) }
            // A visible selection is the strongest browsing anchor. An off-screen
            // selection must not pull the reader away from their current viewport.
            let candidates = visible.filter { item in item.indexPath.map { collection.selectionIndexPaths.contains($0) } ?? false }
            let anchor = (candidates.isEmpty ? visible : candidates).min {
                abs($0.frame.midY-viewport.midY) < abs($1.frame.midY-viewport.midY)
            }
            let anchorPoint = anchor.map { $0.frame.intersection(viewport).midY }
            let fraction = anchor.flatMap { item in anchorPoint.map { ($0-item.frame.minY)/max(1,item.frame.height) } } ?? 0.5
            let offset = (anchorPoint ?? viewport.midY)-viewport.minY
            layout.targetWidth = targetWidth; layout.mode = mode; layout.invalidateLayout()
            collection.layoutSubtreeIfNeeded()
            if let anchor, let path = anchor.indexPath, let frame = layout.layoutAttributesForItem(at:path)?.frame {
                let proposed = frame.minY + frame.height*fraction-offset
                let maxY = max(0,layout.collectionViewContentSize.height-viewport.height)
                clip.scroll(to:NSPoint(x:viewport.minX,y:min(max(0,proposed),maxY)))
                scroll.reflectScrolledClipView(clip)
            }

        }
        func updateContent() {
            let groupingChanged = grouped != model.dateGrouping || groupedByDay != model.dateGroupingByDay
            let namesChanged = showNames != model.showNames
            let photosChanged = photos != model.visible
            guard groupingChanged || namesChanged || photosChanged else { return }
            let previous = sections
            grouped = model.dateGrouping; showNames = model.showNames; photos = model.visible
            groupedByDay = model.dateGroupingByDay
            if grouped {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateFormat = groupedByDay ? "yyyy 年 M 月 d 日" : "yyyy 年 M 月"
                var result: [(String, [Photo])] = []
                for photo in photos {
                    let title = formatter.string(from: photo.sortDate)
                    if result.last?.0 == title { result[result.count - 1].1.append(photo) }
                    else { result.append((title, [photo])) }
                }
                sections = result
            } else { sections = [("", photos)] }
            let sameStructure = !groupingChanged && previous.count == sections.count && zip(previous, sections).allSatisfy {
                $0.0 == $1.0 && $0.1.map(\.id) == $1.1.map(\.id)
            }
            if sameStructure {
                // Ratings/tags/notes change cell content, not photo identity.
                // Keep the item, decoded thumbnail, hover and scroll position alive.
                for item in collection?.visibleItems() ?? [] {
                    guard let item = item as? PhotoItem, let path = collection?.indexPath(for: item),
                          sections.indices.contains(path.section), sections[path.section].1.indices.contains(path.item) else { continue }
                    let photo = sections[path.section].1[path.item]
                    if namesChanged || previous[path.section].1[path.item] != photo {
                        item.configure(photo: photo, url: model.url(for: photo), key: model.cacheKey(photo), offline: model.offline.contains(photo.sourceID), showNames: showNames, onFavorite: { [weak model] in model?.toggleFavorite(ids: [photo.id]) }, onRating: { [weak model] value in model?.setRating(value, ids: [photo.id]) })
                    }
                }
                let dimensionsChanged = zip(previous.flatMap { $0.1 }, photos).contains { $0.width != $1.width || $0.height != $1.height }
                if namesChanged || dimensionsChanged { collection?.collectionViewLayout?.invalidateLayout() }
            } else {
                // A filter, sort or month change really changes membership/order.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    collection?.reloadData()
                    collection?.collectionViewLayout?.invalidateLayout()
                    collection?.layoutSubtreeIfNeeded()
                }
            }
        }
        @objc func openFromGesture(_ recognizer: NSClickGestureRecognizer) {
            guard let collection, let path = collection.indexPathForItem(at: recognizer.location(in: collection)),
                  sections.indices.contains(path.section), sections[path.section].1.indices.contains(path.item) else { return }
            if let cell = collection.item(at: path)?.view as? PhotoCell,
               cell.containsHoverControl(cell.convert(recognizer.location(in: collection), from: collection)) { return }
            model.openViewer(sections[path.section].1[path.item].id)
        }
        init(_ model: LibraryModel) { self.model = model }
        func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].1.count }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("photo"), for: indexPath) as! PhotoItem
            let photo = sections[indexPath.section].1[indexPath.item]
            item.configure(photo: photo, url: model.url(for: photo), key: model.cacheKey(photo), offline: model.offline.contains(photo.sourceID), showNames: model.showNames, onFavorite: { [weak model] in model?.toggleFavorite(ids: [photo.id]) }, onRating: { [weak model] value in model?.setRating(value, ids: [photo.id]) })
            return item
        }
        func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> NSView {
            let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: NSUserInterfaceItemIdentifier("date"), for: indexPath) as! DateHeader
            view.label.stringValue = sections[indexPath.section].0
            view.count.stringValue = "\(sections[indexPath.section].1.count) 张照片"
            return view
        }
        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> NSSize { NSSize(width: 100, height: grouped ? 50 : 0) }
        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
            guard let layout = collectionViewLayout as? PhotoFlowLayout else { return NSSize(width: 200, height: 192) }
            let available = max(200, (collectionView.enclosingScrollView?.contentSize.width ?? 800) - 44)
            let columns = max(1, Int((available + 14) / (layout.targetWidth + 14)))
            let width = floor((available - CGFloat(columns - 1) * 14) / CGFloat(columns))
            return NSSize(width: width, height: width * 0.74 + 48)
        }
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { updateSelection(collectionView) }
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { updateSelection(collectionView) }
        private func updateSelection(_ collection: NSCollectionView) {
            model.selection = Set(collection.selectionIndexPaths.compactMap { path in
                guard path.section < sections.count, path.item < sections[path.section].1.count else { return nil }
                return sections[path.section].1[path.item].id
            })
        }
    }
}

final class PhotoFlowLayout: NSCollectionViewFlowLayout {
    var targetWidth: CGFloat = 206
    var mode = "masonry"
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool { newBounds.width != collectionView?.bounds.width }
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard let collectionView, let delegate = collectionView.delegate as? PhotoGrid.Coordinator else { return super.layoutAttributesForElements(in: rect) }
        return justifiedAttributes(delegate: delegate, width: collectionView.enclosingScrollView?.contentSize.width ?? collectionView.bounds.width).filter { $0.frame.intersects(rect) }
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let collectionView, let delegate = collectionView.delegate as? PhotoGrid.Coordinator else { return super.layoutAttributesForItem(at: indexPath) }
        _ = justifiedAttributes(delegate: delegate, width: collectionView.enclosingScrollView?.contentSize.width ?? collectionView.bounds.width)
        return cachedItems[indexPath]
    }
    override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let collectionView, let delegate = collectionView.delegate as? PhotoGrid.Coordinator else {
            return super.layoutAttributesForSupplementaryView(ofKind: elementKind, at: indexPath)
        }
        return justifiedAttributes(delegate: delegate, width: collectionView.enclosingScrollView?.contentSize.width ?? collectionView.bounds.width).first {
            $0.representedElementKind == elementKind && $0.indexPath == indexPath
        }
    }
    override var collectionViewContentSize: NSSize {
        guard let collectionView, let delegate = collectionView.delegate as? PhotoGrid.Coordinator else { return super.collectionViewContentSize }
        let width = collectionView.enclosingScrollView?.contentSize.width ?? collectionView.bounds.width
        return NSSize(width: width, height: (justifiedAttributes(delegate: delegate, width: width).map(\.frame.maxY).max() ?? 0) + 22)
    }
    private var cachedItems: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    private var cachedWidth: CGFloat = 0
    private var cachedToken = ""
    private var cachedAttributes: [NSCollectionViewLayoutAttributes] = []
    private func justifiedAttributes(delegate: PhotoGrid.Coordinator, width: CGFloat) -> [NSCollectionViewLayoutAttributes] {
        let token = "\(mode)-\(delegate.model.showNames)-\(delegate.model.visible.count)-\(delegate.model.dateGrouping)-\(delegate.model.dateGroupingByDay)-\(targetWidth)-\(delegate.model.sort.rawValue)-\(delegate.model.visible.first?.id.uuidString ?? "")-\(delegate.model.search)-\(delegate.model.title)-\(delegate.model.filterCount)"
        if cachedWidth == width, cachedToken == token { return cachedAttributes }
        var attributes: [NSCollectionViewLayoutAttributes] = []; var y: CGFloat = 0
        let available = max(200, width - 32), gap: CGFloat = 12
        let caption: CGFloat = delegate.model.showNames ? 34 : 6
        for (section, content) in delegate.sections.enumerated() {
            if delegate.grouped {
                let header = NSCollectionViewLayoutAttributes(forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, with: IndexPath(item: 0, section: section))
                header.frame = NSRect(x: 0, y: y, width: width, height: 50); attributes.append(header); y += 50
            }
            if mode != "justified" {
                let columns = max(1,Int((available+gap)/(targetWidth+gap)))
                let w = floor((available-CGFloat(columns-1)*gap)/CGFloat(columns))
                var bottoms = Array(repeating:y+12,count:columns)
                for (index,photo) in content.1.enumerated() {
                    let column = bottoms.indices.min(by:{bottoms[$0]<bottoms[$1]}) ?? 0
                    let ratio = CGFloat(max(photo.width,1))/CGFloat(max(photo.height,1))
                    let item = NSCollectionViewLayoutAttributes(forItemWith:IndexPath(item:index,section:section))
                    item.frame = NSRect(x:16+CGFloat(column)*(w+gap),y:bottoms[column],width:w,height:(mode == "square" ? w : w/max(0.1,ratio))+caption)
                    attributes.append(item); bottoms[column] = item.frame.maxY+gap
                }
                y = bottoms.max() ?? y
                continue
            }
            y += 12
            var row: [(Int, CGFloat)] = []; var ratios: CGFloat = 0
            func flush(last: Bool) {
                guard !row.isEmpty else { return }
                let height = min(targetWidth * 0.9, (available - gap * CGFloat(row.count - 1)) / ratios)
                var x: CGFloat = 16
                for (index, ratio) in row {
                    let item = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: section))
                    item.frame = NSRect(x: x, y: y, width: floor(height * ratio), height: height + caption)
                    attributes.append(item); x += floor(height * ratio) + gap
                }
                y += height + caption + gap; row = []; ratios = 0
            }
            for (index, photo) in content.1.enumerated() {
                let ratio = min(2.4, max(0.55, CGFloat(max(photo.width, 1)) / CGFloat(max(photo.height, 1))))
                row.append((index, ratio)); ratios += ratio
                if ratios * targetWidth * 0.74 + CGFloat(row.count - 1) * gap >= available { flush(last: false) }
            }
            flush(last: true); y += 10
        }
        cachedItems = Dictionary(uniqueKeysWithValues: attributes.compactMap { item in
            guard item.representedElementCategory == .item, let path = item.indexPath else { return nil }
            return (path, item)
        })
        cachedWidth = width; cachedToken = token; cachedAttributes = attributes
        return attributes
    }
    override func invalidateLayout() { cachedToken = ""; super.invalidateLayout() }
}

final class PhotoCollectionView: NSCollectionView {
    weak var model: LibraryModel?
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // Let AppKit track the entire gesture, including rubber-band selection
        // starting in empty space, instead of consuming the initial mouse-down.
        super.mouseDown(with: event)
        if let coordinator = dataSource as? PhotoGrid.Coordinator {
            model?.selection = Set(selectionIndexPaths.compactMap { path in
                guard coordinator.sections.indices.contains(path.section),
                      coordinator.sections[path.section].1.indices.contains(path.item) else { return nil }
                return coordinator.sections[path.section].1[path.item].id
            })
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        if let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)), !selectionIndexPaths.contains(path),
           let coordinator = dataSource as? PhotoGrid.Coordinator {
            selectionIndexPaths = [path]; model.selection = [coordinator.sections[path.section].1[path.item].id]
        }
        let menu = NSMenu()
        let compare = ActionMenuItem(title: "对比所选照片（2–4 张） · D") { model.beginComparison() }
        compare.isEnabled = model.canCompare; menu.addItem(compare)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: model.allTargetsFavorite ? "取消收藏" : "添加收藏") { model.toggleFavorite() })
        menu.addItem(.separator())
        for rating in 0...5 {
            let item = ActionMenuItem(title: rating == 0 ? "清除星级" : String(repeating: "★", count: rating)) { model.setRating(rating) }; menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "添加标签…") { model.prompt(title: "添加标签") { name in model.addTag(name) } })
        for album in model.snapshot.albums where album.query == nil { menu.addItem(ActionMenuItem(title: "加入相册：\(album.name)") { model.addToAlbum(album) }) }
        if case .album(let id) = model.navigation, let album = model.snapshot.albums.first(where: { $0.id == id }) {
            menu.addItem(ActionMenuItem(title: "从当前相册移除") { model.removeFromAlbum(album) })
        }
        menu.addItem(ActionMenuItem(title:"导出照片副本…") { model.exportOriginals() })
        menu.addItem(ActionMenuItem(title:"分享…") { model.sharePhotos() })
        if let photo = model.focusedPhoto { menu.addItem(ActionMenuItem(title: "在 Finder 中显示") { model.reveal(photo) }) }
        return menu
    }
}

final class ActionMenuItem: NSMenuItem {
    let perform: () -> Void
    init(title: String, perform: @escaping () -> Void) { self.perform = perform; super.init(title: title, action: #selector(invoke), keyEquivalent: ""); target = self }
    required init(coder: NSCoder) { fatalError() }
    @objc private func invoke() { perform() }
}

final class PhotoItem: NSCollectionViewItem {
    private var operation: Operation?
    private var token = ""
    override func loadView() { view = PhotoCell() }
    override var isSelected: Bool { didSet { (view as? PhotoCell)?.selected = isSelected } }
    override func prepareForReuse() { operation?.cancel(); token = ""; (view as? PhotoCell)?.resetFeedback(); super.prepareForReuse() }
    func configure(photo: Photo, url: URL?, key: String, offline: Bool, showNames: Bool, onFavorite: @escaping () -> Void = {}, onRating: @escaping (Int) -> Void = { _ in }) {
        guard let cell = view as? PhotoCell else { return }
        cell.showNames = showNames
        cell.name.stringValue = photo.filename
        cell.rating = photo.rating
        cell.ratingAction = onRating
        cell.favoriteAction = onFavorite; cell.isFavorite = photo.isFavorite
        cell.badge.stringValue = offline ? "离线" : photo.missing ? "文件缺失" : photo.decodeError ? "无法解码" : (photo.format == "DNG" || PhotoScanner.extensions.contains(photo.format.lowercased()) && !["JPEG", "JPG", "PNG", "HEIC", "HEIF", "TIFF", "TIF"].contains(photo.format)) ? "RAW" : ""
        cell.setAccessibilityElement(true); cell.setAccessibilityLabel("\(photo.filename)，\(photo.rating) 星\(photo.isFavorite ? "，已收藏" : "")\(offline ? "，离线" : "")")
        cell.setAccessibilityRole(.button)
        guard token != key else { return }; token = key; operation?.cancel(); cell.image.image = nil
        cell.placeholder.isHidden = false
        operation = ThumbnailService.shared.load(url: url, key: key) { [weak self] image in
                guard let self, self.token == key, let cell = self.view as? PhotoCell else { return }
                cell.image.image = image; cell.placeholder.isHidden = image != nil
        }
    }
}

final class PhotoCell: NSView {
    let image = PhotoThumbnailView(), name = NSTextField(labelWithString: ""), badge = NSTextField(labelWithString: "")
    let placeholder = NSImageView()
    private let favoriteButton = PhotoHoverButton()
    private var favoriteHovered = false
    var favoriteAction: (() -> Void)?
    var isFavorite = false { didSet { updateFavorite() } }
    @objc private func favoriteClicked() { favoriteAction?() }
    private func updateFavorite() {
        favoriteButton.image = NSImage(systemSymbolName: (isFavorite || favoriteHovered) ? "heart.fill" : "heart", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        favoriteButton.contentTintColor = isFavorite ? .systemPink : .white
        favoriteButton.isHidden = !isFavorite && !hovering && !selected
        favoriteButton.toolTip = isFavorite ? "取消收藏" : "添加收藏"
        favoriteButton.setAccessibilityLabel(favoriteButton.toolTip)
    }
    private let ratingControls = NSView()
    private var ratingButtons: [NSButton] = []
    private func previewRating(_ value: Int) {
        for button in ratingButtons {
            button.image = NSImage(systemSymbolName: button.tag <= value ? "star.fill" : "star", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        }
    }
    var ratingAction: ((Int) -> Void)?
    @objc private func ratingClicked(_ sender: NSButton) {
        ratingAction?(rating == sender.tag ? 0 : sender.tag)
    }
    func containsHoverControl(_ point: NSPoint) -> Bool {
        (!ratingControls.isHidden && ratingControls.frame.contains(point)) ||
        (!favoriteButton.isHidden && favoriteButton.frame.contains(point))
    }
    private let ratingBadge = PhotoRatingBadgeHost(rootView: PhotoRatingBadge(rating: 0))
    var selected = false { didSet { updateFeedback(animated: false) } }
    private var hovering = false
    private var tracking: NSTrackingArea?
    private let imageBorder = CALayer()
    private let borderView = PhotoBorderOverlay()
    private var accent: NSColor { effectiveAppearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua ? NSColor(calibratedRed:0.43,green:0.62,blue:0.94,alpha:1) : NSColor(calibratedRed:0.18,green:0.39,blue:0.73,alpha:1) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect:.zero, options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect], owner:self, userInfo:nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; updateFeedback(animated: true) }
    override func mouseExited(with event: NSEvent) { hovering = false; favoriteHovered = false; previewRating(0); updateFeedback(animated: true) }
    func resetFeedback() { hovering = false; favoriteHovered = false; previewRating(0); updateFeedback(animated:false) }
    private func updateFeedback(animated: Bool) {
        guard let layer else { return }
        let primary = effectiveAppearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua ? NSColor.white : NSColor.black
        let background = selected ? accent.withAlphaComponent(0.10) : primary.withAlphaComponent(hovering ? 0.045 : 0)
        let border = selected ? accent : NSColor.white.withAlphaComponent(hovering ? 0.35 : 0.04)
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.14 : 0
        if duration > 0 {
            for (target, key, destination) in [(layer, "backgroundColor", background.cgColor), (imageBorder, "borderColor", border.cgColor)] {
                let animation = CABasicAnimation(keyPath:key)
                animation.fromValue = target.presentation()?.value(forKey:key) ?? target.value(forKey:key)
                animation.toValue = destination; animation.duration = duration; animation.timingFunction = CAMediaTimingFunction(name:.easeOut)
                target.add(animation,forKey:key)
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.backgroundColor = background.cgColor; imageBorder.borderColor = border.cgColor; imageBorder.borderWidth = selected ? 1.5 : 1
        CATransaction.commit()
        updateFavorite()
        ratingControls.isHidden = !hovering
        ratingBadge.isHidden = rating == 0 || hovering
        name.font = .systemFont(ofSize:12,weight:selected ? .medium : .regular)
        name.textColor = primary.withAlphaComponent(selected ? 1 : 0.78)
    }
    var showNames = true { didSet { name.isHidden = !showNames; needsLayout = true } }
    var rating = 0 { didSet { updateStars() } }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.cornerRadius = 5; image.imageScaling = .scaleProportionallyUpOrDown
        name.font = .systemFont(ofSize: 12); name.textColor = .secondaryLabelColor; name.lineBreakMode = .byTruncatingTail
        badge.font = .systemFont(ofSize: 9, weight: .medium); badge.textColor = .secondaryLabelColor; badge.alignment = .right
        placeholder.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "暂无预览"); placeholder.contentTintColor = .tertiaryLabelColor
        [image, name, ratingBadge, badge, placeholder].forEach(addSubview)
        favoriteButton.isBordered = false; favoriteButton.bezelStyle = .regularSquare
        favoriteButton.onHover = { [weak self] entered in
            self?.favoriteHovered = entered; self?.updateFavorite()
        }
        favoriteButton.target = self; favoriteButton.action = #selector(favoriteClicked)
        favoriteButton.wantsLayer = true; favoriteButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.48).cgColor
        favoriteButton.layer?.cornerRadius = 13
        addSubview(favoriteButton)
        ratingControls.wantsLayer = true
        ratingControls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        ratingControls.layer?.cornerRadius = 13
        ratingControls.isHidden = true
        for value in 1...5 {
            let button = PhotoHoverButton()
            button.onHover = { [weak self] entered in self?.previewRating(entered ? value : 0) }
            button.isBordered = false; button.bezelStyle = .regularSquare
            button.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            button.contentTintColor = .white
            button.tag = value; button.target = self; button.action = #selector(ratingClicked(_:))
            ratingControls.addSubview(button); ratingButtons.append(button)
        }
        addSubview(ratingControls)
        borderView.wantsLayer = true; borderView.layer?.addSublayer(imageBorder); addSubview(borderView); imageBorder.cornerRadius = 4; updateFeedback(animated:false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateStars(); updateFeedback(animated:false) }
    private func updateStars() {
        ratingBadge.isHidden = rating == 0 || hovering
        for button in ratingButtons {
            button.toolTip = rating == button.tag ? "取消 \(button.tag) 星评分" : "评为 \(button.tag) 星"
            button.setAccessibilityLabel(button.toolTip)
            button.setAccessibilityValue("当前 \(rating) 星")
        }
        ratingBadge.rootView = PhotoRatingBadge(rating: rating)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        image.frame = NSRect(x:1,y:1,width:bounds.width-2,height:bounds.height-(showNames ? 35 : 7))
        image.wantsLayer = true; image.layer?.cornerRadius = 4; image.layer?.masksToBounds = true
        CATransaction.begin(); CATransaction.setDisableActions(true); borderView.frame = image.frame; imageBorder.frame = borderView.bounds; CATransaction.commit()
        placeholder.frame = NSRect(x:bounds.midX-18,y:(bounds.height-(showNames ? 34 : 6))/2-18,width:36,height:36)
        name.frame = NSRect(x:4,y:bounds.height-23,width:bounds.width-8,height:18)
        let ratingSize = ratingBadge.fittingSize
        ratingBadge.frame = NSRect(x: image.frame.maxX - 8 - ratingSize.width,
                                   y: image.frame.maxY - 8 - ratingSize.height,
                                   width: ratingSize.width, height: ratingSize.height)
        ratingControls.frame = NSRect(x: image.frame.minX + 7, y: image.frame.maxY - 34, width: 114, height: 26)
        for (index, button) in ratingButtons.enumerated() {
            button.frame = NSRect(x: 2 + CGFloat(index) * 22, y: 0, width: 22, height: 26)
        }
        favoriteButton.frame = NSRect(x:image.frame.maxX-34,y:image.frame.minY+8,width:26,height:26)
        badge.frame = NSRect(x:5,y:5,width:70,height:18)
    }

}

private final class PhotoHoverButton: NSButton {
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

final class DateHeader: NSView, NSCollectionViewSectionHeaderView {
    let label = NSTextField(labelWithString: ""), count = NSTextField(labelWithString: "")
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); label.font = .systemFont(ofSize: 14, weight: .semibold); count.font = .systemFont(ofSize: 11); count.textColor = .secondaryLabelColor; addSubview(label); addSubview(count) }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); label.frame = NSRect(x: 24, y: 7, width: bounds.width - 48, height: 25); count.frame = NSRect(x: 24, y: 33, width: bounds.width - 48, height: 15) }
}

private final class PhotoBorderOverlay: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PhotoThumbnailView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        guard let image, abs(bounds.width-bounds.height) < 2, image.size.width > 0, image.size.height > 0 else {
            super.draw(dirtyRect); return
        }
        let side = min(image.size.width,image.size.height)
        let source = NSRect(x:(image.size.width-side)/2,y:(image.size.height-side)/2,width:side,height:side)
        image.draw(in:bounds,from:source,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
}


// Keep the photo rating badge identical to the approved DemoPhotoTile.
private struct PhotoRatingBadge: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 8))
            Text("\(rating)").font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.48), in: Capsule())
        .fixedSize()
        .accessibilityHidden(true)
    }
}

private final class PhotoRatingBadgeHost: NSHostingView<PhotoRatingBadge> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Keeps the selected (or nearest visible) photo at the same vertical screen
/// position while the inspector changes the grid's available width.
final class AnchoredPhotoScrollView: NSScrollView {
    private var anchor: (path: IndexPath, fraction: CGFloat, offset: CGFloat)?
    private var lastWidth: CGFloat = 0
    func captureAnchor(selectedIDs: Set<UUID>, sections: [(String, [Photo])]) {
        guard let collection = documentView as? NSCollectionView,
              let layout = collection.collectionViewLayout else { return }
        let viewport = contentView.bounds
        let visible = (layout.layoutAttributesForElements(in: viewport) ?? []).filter {
            $0.representedElementCategory == .item && $0.frame.intersects(viewport)
        }
        let selected = visible.filter { item in
            guard let path = item.indexPath, sections.indices.contains(path.section), sections[path.section].1.indices.contains(path.item) else { return false }
            return selectedIDs.contains(sections[path.section].1[path.item].id)
        }
        guard let item = (selected.isEmpty ? visible : selected).min(by: { abs($0.frame.midY - viewport.midY) < abs($1.frame.midY - viewport.midY) }), let path = item.indexPath else { return }
        let point = item.frame.intersection(viewport).midY
        anchor = (path, (point - item.frame.minY) / max(1, item.frame.height), point - viewport.minY)
    }
    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(newSize.width - frame.width) > 0.1
        if changed, anchor == nil, let collection = documentView as? NSCollectionView,
           let coordinator = collection.dataSource as? PhotoGrid.Coordinator {
            captureAnchor(selectedIDs: coordinator.model.selection, sections: coordinator.sections)
        }
        super.setFrameSize(newSize)
        guard changed, let anchor, let collection = documentView as? NSCollectionView,
              let layout = collection.collectionViewLayout else { return }
        layout.invalidateLayout()
        collection.layoutSubtreeIfNeeded()
        guard let frame = layout.layoutAttributesForItem(at: anchor.path)?.frame else { self.anchor = nil; return }
        let y = frame.minY + frame.height * anchor.fraction - anchor.offset
        let maxY = max(0, layout.collectionViewContentSize.height - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
        reflectScrolledClipView(contentView)
        lastWidth = newSize.width
    }
    override func scrollWheel(with event: NSEvent) {
        anchor = nil
        super.scrollWheel(with: event)
    }
}
