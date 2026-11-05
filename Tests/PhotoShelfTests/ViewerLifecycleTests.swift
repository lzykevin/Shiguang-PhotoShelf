import XCTest
import AppKit
@testable import PhotoShelf

@MainActor final class ViewerLifecycleTests: XCTestCase {
    func testDismantlingViewerRestoresPresentationAndReleasesWindow() {
        _ = NSApplication.shared
        let original = NSApp.presentationOptions
        defer { NSApp.presentationOptions = original }
        let coordinator = ProductWindowBridge.Coordinator()
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        coordinator.viewer = window
        coordinator.savedPresentation = original
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        ProductWindowBridge.dismantleNSView(NSView(), coordinator: coordinator)
        XCTAssertNil(coordinator.viewer)
        XCTAssertNil(coordinator.savedPresentation)
        XCTAssertNil(coordinator.inputMonitor)
        XCTAssertEqual(NSApp.presentationOptions, original)
        coordinator.closeViewer(restoreFocus: false)
        XCTAssertEqual(NSApp.presentationOptions, original)
    }

    func testExternalViewerCloseRestoresPresentationWithoutSwiftUIUpdate() {
        _ = NSApplication.shared
        let original = NSApp.presentationOptions
        defer { NSApp.presentationOptions = original }
        let coordinator = ProductWindowBridge.Coordinator()
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        coordinator.viewer = window
        coordinator.savedPresentation = original
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        coordinator.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        XCTAssertNil(coordinator.viewer)
        XCTAssertNil(coordinator.savedPresentation)
        XCTAssertEqual(NSApp.presentationOptions, original)
        window.close()
    }
}
