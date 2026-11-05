import SwiftUI
import AppKit

/// A dedicated empty title strip: never overlays search fields or toolbar buttons.
struct WindowTitleDragArea: NSViewRepresentable {
    var nativeTitleTrailingInset: CGFloat = 8
    func makeNSView(context: Context) -> TitleDragView { TitleDragView() }
    func updateNSView(_ view: TitleDragView, context: Context) {
        view.nativeTitleTrailingInset = nativeTitleTrailingInset
    }
}
final class TitleDragView: NSView {
    var nativeTitleTrailingInset: CGFloat = 8
    private var restoreFrame: NSRect?
    private var titleMonitor: Any?
    private var suppressMouseUp = false
    private var isResizing = false
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let titleMonitor { NSEvent.removeMonitor(titleMonitor); self.titleMonitor = nil }
        suppressMouseUp = false
        guard window != nil else { return }
        // The native title bar sits outside SwiftUI's content hit-testing area.
        // Catch its double click before AppKit applies the system title-bar action.
        titleMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if event.type == .leftMouseUp, self.suppressMouseUp {
                self.suppressMouseUp = false
                return nil
            }
            guard event.type == .leftMouseDown, event.clickCount == 2,
                  !window.styleMask.contains(.fullScreen), window.attachedSheet == nil,
                  window.convertPoint(toScreen: event.locationInWindow).x < window.frame.maxX - self.nativeTitleTrailingInset,
                  Self.isNativeTitlePoint(window.convertPoint(toScreen: event.locationInWindow), frame: window.frame) else { return event }
            self.suppressMouseUp = true
            self.toggleMaximized(window)
            return nil
        }
    }
    static func isNativeTitlePoint(_ point: NSPoint, frame: NSRect) -> Bool {
        let distanceFromTop = frame.maxY - point.y
        return point.x >= frame.minX + 84 && point.x < frame.maxX - 8 && distanceFromTop >= 0 && distanceFromTop < 28
    }
    private func toggleMaximized(_ window: NSWindow) {
        guard !isResizing, let screen = window.screen else { return }
        let target: NSRect
        if let previous = restoreFrame, window.frame == screen.visibleFrame {
            target = previous
            restoreFrame = nil
        } else {
            restoreFrame = window.frame
            target = screen.visibleFrame
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.setFrame(target, display: true)
            return
        }
        // Let AppKit choose the native resize duration and animation curve.
        isResizing = true
        defer { isResizing = false }
        window.setFrame(target, display: true, animate: true)
    }
    override func mouseDown(with event: NSEvent) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if event.clickCount == 2 { toggleMaximized(window) }
        else { window.performDrag(with: event) }
    }
    deinit { if let titleMonitor { NSEvent.removeMonitor(titleMonitor) } }
}

struct ComparisonWindowPresenter: NSViewRepresentable {
    @ObservedObject var model: LibraryModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        let presenting = !model.comparisonIDs.isEmpty
        DispatchQueue.main.async { coordinator.update(presenting: presenting, parent: view.window) }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.window?.close()
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        let model: LibraryModel
        var window: NSWindow?
        init(model: LibraryModel) { self.model = model }
        func update(presenting: Bool, parent: NSWindow?) {
            if !presenting { window?.close(); return }
            guard window == nil else { return }
            let screen = parent?.screen ?? NSScreen.main
            let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 900)
            let frame = NSRect(x: available.midX - min(1200, available.width - 60) / 2,
                               y: available.midY - min(800, available.height - 60) / 2,
                               width: min(1200, available.width - 60), height: min(800, available.height - 60))
            let panel = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "照片对比"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            panel.minSize = NSSize(width: 800, height: 560)
            panel.isReleasedWhenClosed = false; panel.delegate = self
            panel.appearance = parent?.appearance
            panel.identifier = NSUserInterfaceItemIdentifier("comparison")
            panel.contentView = NSHostingView(rootView: ComparisonView().environmentObject(model))
            window = panel
            panel.makeKeyAndOrderFront(nil)
        }
        func windowWillClose(_ notification: Notification) {
            window = nil
            model.comparisonIDs = []; model.scheduleQuery()
        }
    }
}
