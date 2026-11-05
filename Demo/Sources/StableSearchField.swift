import SwiftUI
import AppKit

/// A single AppKit editor keeps placeholder and editing baselines identical.
struct StableSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    @Binding var hovered: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.placeholderString = "搜索照片、标签"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("搜索照片")
        field.delegate = context.coordinator
        field.onFocus = { context.coordinator.parent.focused = true }
        field.onBlur = { context.coordinator.parent.focused = false }
        field.onHoverChange = { context.coordinator.parent.hovered = $0 }
        return field
    }
    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }
    final class Field: NSTextField {
        var onFocus: (() -> Void)?
        var onBlur: (() -> Void)?
        var onHoverChange: ((Bool) -> Void)?
        private var outsideClickMonitor: Any?
        private var focusObserver: NSObjectProtocol?
        override init(frame: NSRect) {
            super.init(frame: frame)
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved, .leftMouseDragged]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                // Include the icon, clear button and padding surrounding the native editor.
                let fieldRect = self.convert(self.bounds, to: nil)
                let searchRect = NSRect(x: fieldRect.minX - 27, y: fieldRect.minY - 7,
                                        width: fieldRect.width + 56, height: 30)
                let inside = searchRect.contains(event.locationInWindow)
                self.onHoverChange?(inside)
                if !inside && (event.type == .leftMouseDown || event.type == .rightMouseDown) {
                    if window.firstResponder === self || (self.currentEditor() != nil && window.firstResponder === self.currentEditor()) {
                        window.makeFirstResponder(nil)
                    }
                    self.onBlur?()
                }
                return event
            }
            focusObserver = NotificationCenter.default.addObserver(forName: Notification.Name("PhotoShelfFocusSearch"), object: nil, queue: .main) { [weak self] _ in
                guard let self, self.window?.isKeyWindow == true else { return }
                self.window?.makeFirstResponder(self)
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }; if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) } }
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocus?() }
            return accepted
        }
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 16) }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: StableSearchField
        init(_ parent: StableSearchField) { self.parent = parent }
        func controlTextDidChange(_ note: Notification) { if let field = note.object as? NSTextField { parent.text = field.stringValue } }
        func controlTextDidBeginEditing(_ note: Notification) { parent.focused = true }
        func controlTextDidEndEditing(_ note: Notification) { parent.focused = false }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            if parent.text.isEmpty { control.window?.makeFirstResponder(nil); parent.focused = false }
            else { parent.text = ""; control.stringValue = "" }
            return true
        }
    }
}
