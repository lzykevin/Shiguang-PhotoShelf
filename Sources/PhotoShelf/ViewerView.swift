import SwiftUI
import PhotoLibraryCore

enum PhotoLoadState: Equatable { case loading, original, cached, unavailable }

struct ZoomPhoto: NSViewRepresentable {
    let photo: Photo
    let url: URL?
    let cacheKey: String
    let actualSize: Bool
    var zoomGroup: ComparisonZoomGroup? = nil
    var onDoubleClick: (() -> Void)? = nil
    var onNavigate: ((Int) -> Void)? = nil
    var scrollToZoom = false
    var onLoad: (PhotoLoadState) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.drawsBackground = true; scroll.backgroundColor = .black
        scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = false; scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none; scroll.verticalScrollElasticity = .none
        scroll.allowsMagnification = true; scroll.minMagnification = 0.01; scroll.maxMagnification = 8
        scroll.imageView.imageScaling = .scaleProportionallyUpOrDown
        scroll.canvas.addSubview(scroll.imageView)
        scroll.documentView = scroll.canvas
        zoomGroup?.add(scroll)
        return scroll
    }
    func updateNSView(_ scroll: ZoomScrollView, context: Context) {
        scroll.onDoubleClick = onDoubleClick
        scroll.onNavigate = onNavigate
        scroll.scrollToZoom = scrollToZoom
        let coordinator = context.coordinator
        // Source availability is part of the request identity: reconnecting a disk
        // must replace the cached preview even when its photo identity is unchanged.
        let requestKey = cacheKey + "|" + (url?.absoluteString ?? "offline")
        if coordinator.key != requestKey {
            scroll.cancelPendingNavigation()
            coordinator.operation?.cancel(); coordinator.key = requestKey
            // Keep the displayed image and its geometry until the next image is decoded.
            let pixels = NSSize(width: max(photo.width, 1), height: max(photo.height, 1))
            DispatchQueue.main.async { if coordinator.key == requestKey { onLoad(.loading) } }
            let deliver: (NSImage?, PhotoLoadState) -> Void = { [weak coordinator, weak scroll] image, state in
                guard coordinator?.key == requestKey, let scroll else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0; context.allowsImplicitAnimation = false
                    scroll.imagePixels = pixels
                    scroll.imageView.image = image
                    scroll.needsFit = true; scroll.needsLayout = true
                    scroll.layoutSubtreeIfNeeded()
                }
                DispatchQueue.main.async { if coordinator?.key == requestKey { onLoad(state) } }
            }
            coordinator.operation = ThumbnailService.shared.load(url: url, key: cacheKey, size: url == nil ? 512 : max(2048, max(photo.width, photo.height))) { [weak coordinator] image in
                guard let coordinator, coordinator.key == requestKey else { return }
                if let image { deliver(image, url == nil ? .cached : .original) }
                else if url != nil {
                    coordinator.operation = ThumbnailService.shared.load(url: nil, key: cacheKey) { image in
                        deliver(image, image == nil ? .unavailable : .cached)
                    }
                } else { deliver(nil, .unavailable) }
            }
        }
        if scroll.actualSize != actualSize { scroll.actualSize = actualSize; scroll.needsFit = true; scroll.needsLayout = true }
    }
    static func dismantleNSView(_ nsView: ZoomScrollView, coordinator: Coordinator) { coordinator.operation?.cancel(); nsView.cancelPendingNavigation() }
    final class Coordinator { var operation: Operation?; var key = "" }
}

final class ZoomScrollView: NSScrollView {
    weak var zoomGroup: ComparisonZoomGroup?
    let canvas = NSView()
    let imageView = NSImageView()
    var imagePixels = NSSize(width: 1, height: 1)
    var actualSize = false
    var needsFit = true
    private var previousSize = NSSize.zero
    private var dragOrigin: NSPoint?
    private var mouseOrigin: NSPoint?
    private var didDrag = false
    private var pendingNavigation: DispatchWorkItem?
    var scrollToZoom = false
    private var wheelAnchor: NSPoint?
    private var lastWheelTime: TimeInterval = 0
    private var suppressWheelMomentum = false
    override func layout() {
        super.layout()
        if contentSize != previousSize { previousSize = contentSize; if !actualSize { needsFit = true } }
        let refit = needsFit
        needsFit = false
        let scale = window?.backingScaleFactor ?? 2
        let dimensions = NSSize(width: imagePixels.width / scale, height: imagePixels.height / scale)
        if refit {
            let fit = max(0.01, min(contentSize.width / dimensions.width, contentSize.height / dimensions.height))
            magnification = actualSize ? 1 : min(maxMagnification, fit)
        }
        // Keep the document at least as large as the visible area. Centering the
        // image inside a positive-coordinate canvas avoids negative clip origins
        // being clamped by AppKit during window resize and magnification changes.
        let visible = contentView.bounds.size
        let canvasSize = NSSize(width: max(dimensions.width, visible.width), height: max(dimensions.height, visible.height))
        if canvas.frame.size != canvasSize { canvas.setFrameSize(canvasSize) }
        let imageFrame = NSRect(x: (canvasSize.width - dimensions.width) / 2, y: (canvasSize.height - dimensions.height) / 2, width: dimensions.width, height: dimensions.height)
        if imageView.frame != imageFrame { imageView.frame = imageFrame }
        if refit {
            contentView.scroll(to: NSPoint(x: max(0, (canvasSize.width - visible.width) / 2), y: max(0, (canvasSize.height - visible.height) / 2)))
            reflectScrolledClipView(contentView)
        }
    }
    override func scrollWheel(with event: NSEvent) {
        cancelPendingNavigation()
        // A zoom gesture must not turn into an inertial pan when Command is released.
        if !event.momentumPhase.isEmpty && (scrollToZoom || suppressWheelMomentum || event.modifierFlags.contains(.command)) { return }
        suppressWheelMomentum = false
        guard scrollToZoom || event.modifierFlags.contains(.command), imageView.image != nil else {
            wheelAnchor = nil
            super.scrollWheel(with: event); return
        }
        suppressWheelMomentum = true
        let factor = Self.wheelZoomFactor(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
        guard factor != 1 else { return }
        // Hold the anchor during a burst; tiny pointer movements must not pan the image.
        if wheelAnchor == nil || event.timestamp - lastWheelTime > 0.2 || event.phase == .began {
            wheelAnchor = event.locationInWindow
        }
        lastWheelTime = event.timestamp
        zoom(by: factor, at: wheelAnchor ?? event.locationInWindow)
    }
    static func wheelZoomFactor(delta: CGFloat, precise: Bool) -> CGFloat {
        guard delta.isFinite else { return 1 }
        // Ignore OS acceleration for notched wheels. One notch changes scale by 4%.
        let step = precise ? min(0.04, max(-0.04, delta * 0.0025)) : min(1, max(-1, delta)) * log(1.04)
        return exp(step)
    }
    func zoom(by factor: CGFloat, at windowPoint: NSPoint) {
        guard factor.isFinite, factor > 0 else { return }
        layoutSubtreeIfNeeded()
        let imagePoint = imageView.convert(windowPoint, from: nil)
        let anchor = contentView.convert(windowPoint, from: nil)
        let bounds = contentView.bounds
        let fraction = NSPoint(x: (anchor.x - bounds.minX) / max(1, bounds.width),
                               y: (anchor.y - bounds.minY) / max(1, bounds.height))
        let target = min(maxMagnification, max(minMagnification, magnification * factor))
        guard target != magnification else { return }
        setMagnification(target, centeredAt: anchor)
        needsLayout = true; layoutSubtreeIfNeeded()
        // Derive the final position from the image detail, not an already-clamped
        // intermediate scroll origin. This prevents cumulative drift at fit size.
        var visible = contentView.bounds
        visible.origin = NSPoint(x: imageView.frame.minX + imagePoint.x - visible.width * fraction.x,
                                 y: imageView.frame.minY + imagePoint.y - visible.height * fraction.y)
        contentView.scroll(to: contentView.constrainBoundsRect(visible).origin)
        reflectScrolledClipView(contentView)
        zoomGroup?.changed(self)
    }
    override func magnify(with event: NSEvent) { super.magnify(with: event); needsLayout = true; layoutSubtreeIfNeeded(); zoomGroup?.changed(self) }
    var onDoubleClick: (() -> Void)?
    var onNavigate: ((Int) -> Void)?
    func cancelPendingNavigation() { pendingNavigation?.cancel(); pendingNavigation = nil }
    override func mouseDown(with event: NSEvent) {
        cancelPendingNavigation()
        if event.clickCount == 2, let onDoubleClick { onDoubleClick(); return }
        mouseOrigin = event.locationInWindow; dragOrigin = event.locationInWindow; didDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let previous = dragOrigin, let start = mouseOrigin else { return }
        if !didDrag {
            guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3 else { return }
            didDrag = true; NSCursor.closedHand.push()
        }
        let point = event.locationInWindow, origin = contentView.bounds.origin
        contentView.scroll(to: NSPoint(x: origin.x - (point.x - previous.x) / magnification, y: origin.y - (point.y - previous.y) / magnification)); reflectScrolledClipView(contentView); dragOrigin = point; zoomGroup?.changed(self)
    }
    override func mouseUp(with event: NSEvent) {
        defer { mouseOrigin = nil; dragOrigin = nil; didDrag = false }
        if didDrag { NSCursor.pop(); return }
        guard mouseOrigin != nil, event.clickCount == 1, onNavigate != nil else { return }
        let direction = convert(event.locationInWindow, from: nil).x < bounds.midX ? -1 : 1
        // Let a second click cancel navigation so double-click exits the same photo.
        let task = DispatchWorkItem { [weak self] in self?.onNavigate?(direction) }
        pendingNavigation = task
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: task)
    }
}
