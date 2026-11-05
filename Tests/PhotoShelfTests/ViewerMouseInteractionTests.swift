import XCTest
import AppKit
@testable import PhotoShelf

@MainActor final class ViewerMouseInteractionTests: XCTestCase {
    private func event(_ type: NSEvent.EventType, x: CGFloat, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 100), modifierFlags: [],
                          timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                          clickCount: clicks, pressure: 0)!
    }
    private func settleClick() async throws {
        try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
    }
    func testSingleClickNavigatesButDoubleClickOnlyExits() async throws {
        let view = ZoomScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var steps: [Int] = []; var exits = 0
        view.onNavigate = { steps.append($0) }; view.onDoubleClick = { exits += 1 }
        view.mouseDown(with: event(.leftMouseDown, x: 350))
        view.mouseUp(with: event(.leftMouseUp, x: 350))
        try await settleClick()
        XCTAssertEqual(steps, [1])
        view.mouseDown(with: event(.leftMouseDown, x: 50))
        view.mouseUp(with: event(.leftMouseUp, x: 50))
        try await settleClick()
        XCTAssertEqual(steps, [1, -1])
        view.mouseDown(with: event(.leftMouseDown, x: 350))
        view.mouseUp(with: event(.leftMouseUp, x: 350))
        view.mouseDown(with: event(.leftMouseDown, x: 350, clicks: 2))
        view.mouseUp(with: event(.leftMouseUp, x: 350, clicks: 2))
        try await settleClick()
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(steps, [1, -1], "Double click must not switch the photo before exiting")
    }
    func testDraggingAndClosingCancelClickNavigation() async throws {
        let view = ZoomScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var steps = 0; view.onNavigate = { _ in steps += 1 }
        view.mouseDown(with: event(.leftMouseDown, x: 300))
        view.mouseDragged(with: event(.leftMouseDragged, x: 250))
        view.mouseUp(with: event(.leftMouseUp, x: 250))
        try await settleClick()
        XCTAssertEqual(steps, 0)
        view.mouseDown(with: event(.leftMouseDown, x: 300))
        view.mouseUp(with: event(.leftMouseUp, x: 300))
        view.cancelPendingNavigation()
        try await settleClick()
        XCTAssertEqual(steps, 0)
    }
}
