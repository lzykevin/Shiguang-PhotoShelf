import AppKit
import SwiftUI

@main struct DemoApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = DemoDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
@MainActor final class DemoDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let model = DemoModel()
    var window: NSWindow!
    var keyboard: Any?
    var movement: Any?
    var hideTask: DispatchWorkItem?
    var viewerControlFrames: [String: CGRect] = [:]
    var savedFrame: NSRect?
    var savedPresentation: NSApplication.PresentationOptions = []
    func pointerIsOverViewerControls(at location: NSPoint? = nil) -> Bool {
        guard model.viewing, let content = window.contentView else { return false }
        let location = location ?? window.mouseLocationOutsideOfEventStream
        // SwiftUI's named space is top-down; borderless NSWindow events are bottom-up.
        let point = CGPoint(x: location.x, y: content.bounds.height - location.y)
        return viewerControlFrames.values.contains { $0.insetBy(dx: -3, dy: -3).contains(point) }
    }
    func revealControls(at location: NSPoint? = nil) {
        guard model.viewing else { return }
        model.viewerControlsHovered = pointerIsOverViewerControls(at: location)
        model.controlsVisible = true
        hideTask?.cancel()
        guard !model.viewerControlsHovered else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.model.viewing else { return }
            // Recheck the real cursor at the deadline: view hover callbacks can be
            // missed while opacity/hit testing changes or an AX action is delivered.
            self.model.viewerControlsHovered = self.pointerIsOverViewerControls()
            guard !self.model.viewerControlsHovered else { return }
            self.model.controlsVisible = false
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline:.now()+2.5,execute:task)
    }
    func setImmersive(_ enabled: Bool) {
        hideTask?.cancel()
        model.viewerControlsHovered = false
        if enabled {
            savedFrame = window.frame
            savedPresentation = NSApp.presentationOptions
            window.styleMask = [.borderless]
            window.setFrame(window.screen?.frame ?? window.frame,display:true)
            NSApp.presentationOptions = [.autoHideMenuBar,.autoHideDock]
            model.controlsVisible = false
        } else {
            window.styleMask = [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            if let frame = savedFrame { window.setFrame(frame,display:true) }
            NSApp.presentationOptions = savedPresentation
        }
        window.makeKeyAndOrderFront(nil)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "退出拾光 Demo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); editItem.title = "编辑"; menu.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (name, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { edit.addItem(withTitle: name, action: Selector(action), keyEquivalent: key) }
        edit.addItem(.separator())
        edit.addItem(withTitle: "搜索照片", action: #selector(focusSearch), keyEquivalent: "f").target = self
        let winItem = NSMenuItem(); winItem.title = "窗口"; menu.addItem(winItem)
        let winMenu = NSMenu(title: "窗口"); winItem.submenu = winMenu
        winMenu.addItem(withTitle: "标准尺寸", action: #selector(standardSize), keyEquivalent: "1").target = self
        winMenu.addItem(withTitle: "紧凑尺寸", action: #selector(compactSize), keyEquivalent: "2").target = self
        winMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "重新开始演示", action: #selector(resetDemo), keyEquivalent: "r").target = self
        NSApp.mainMenu = menu
        window = DemoWindow(contentRect: NSRect(x: 0,y: 0,width: 1440,height: 920), styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView], backing: .buffered, defer: false)
        window.title = "拾光 · 交互 Demo"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1060,height: 680)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: DemoRoot().environmentObject(model))
        window.acceptsMouseMovedEvents = true
        movement = NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged,.leftMouseDown]) { [weak self] event in
            if let self, event.window === self.window { self.revealControls(at: event.locationInWindow) }
            return event
        }
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        keyboard = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, event.modifierFlags.intersection([.command,.option,.control]).isEmpty else { return event }
            if let editor = self.window.firstResponder as? NSTextView, editor.isEditable { return event }
            if self.window.firstResponder is NSTextField { return event }
            switch event.keyCode {
            case 49: if self.model.current != nil { self.model.viewing.toggle(); self.model.zoom = false }; return nil
            case 53: self.model.viewing = false; return nil
            case 123: self.model.step(-1); self.revealControls(); return nil
            case 124: self.model.step(1); self.revealControls(); return nil
            default:
                if let text = event.charactersIgnoringModifiers, let number = Int(text), (0...5).contains(number) { self.model.rate(number); self.revealControls(); return nil }
            }
            return event
        }
    }
    @objc func focusSearch() {
        guard !model.viewing else { return }
        NotificationCenter.default.post(name: Notification.Name("PhotoShelfFocusSearch"), object: nil)
    }
    @objc func standardSize() {
        guard !model.viewing else { return }
        window.setContentSize(NSSize(width:1440,height:920)); window.center()
    }
    @objc func compactSize() {
        guard !model.viewing else { return }
        window.setContentSize(NSSize(width:1060,height:680)); window.center()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let action = menuItem.action, [#selector(standardSize), #selector(compactSize), #selector(focusSearch)].contains(action) {
            return !model.viewing
        }
        return true
    }
    @objc func resetDemo() {
        model.ratings = [4:5,7:4,9:4,6:5]
        model.notes = [:]
        model.recent = [4,9,8]
        model.reverse = false
        model.showNames = true
        model.size = 230
        model.inspector = true
        model.zoom = false
        model.viewerControlsHovered = false
        model.controlsVisible = false
        model.navigate("全部照片")
        model.selection = 4
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

final class DemoWindow: NSWindow { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }
