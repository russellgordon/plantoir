import AppKit
import XCTest
@testable import QuartzTeachers

/// The view `WindowAccessor` installs hands over its window the moment it
/// joins one, with nothing timed behind it (#998).
///
/// Until #998 a fifty-millisecond `DispatchQueue.main.asyncAfter` poll stood
/// behind `viewDidMoveToWindow` "for anything installed into a view hierarchy
/// that is not yet in a window". These tests measure that case: AppKit tells
/// a view deep in a hierarchy when the hierarchy joins a window, so the poll
/// never had anything to catch. None of them waits; each asserts on the line
/// after the change that should have delivered the window.
@MainActor
final class WindowAccessorTests: XCTestCase {

    // MARK: - Stored properties

    var windows: [NSWindow] = []

    // MARK: - Functions

    override func tearDown() {
        for window in windows {
            window.close()
        }
        windows = []
        super.tearDown()
    }

    func makeWindow() -> NSWindow {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        // Closed by tearDown, which must not free it under ARC as well.
        window.isReleasedWhenClosed = false
        windows.append(window)
        return window
    }

    func testTheWindowIsHandedOverTheMomentTheViewJoinsIt() {
        var handedOver: [NSWindow] = []
        let reader: NSView = WindowAccessor.makeWindowReadingView { window in
            handedOver.append(window)
        }
        XCTAssertTrue(handedOver.isEmpty, "no window yet, nothing handed over")

        let window: NSWindow = makeWindow()
        window.contentView?.addSubview(reader)

        XCTAssertEqual(handedOver.count, 1, "handed over at once, not after a wait")
        XCTAssertTrue(handedOver.first === window)
    }

    /// The case the old poll was kept for: the view is put into a hierarchy
    /// that is not in any window yet, and the hierarchy joins one later.
    func testAViewInAHierarchyThatJoinsAWindowLaterIsToldAtThatMoment() {
        var handedOver: [NSWindow] = []
        let reader: NSView = WindowAccessor.makeWindowReadingView { window in
            handedOver.append(window)
        }
        let outer: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 50))
        let inner: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
        outer.addSubview(inner)
        inner.addSubview(reader)
        XCTAssertTrue(handedOver.isEmpty, "the hierarchy is in no window yet")

        let window: NSWindow = makeWindow()
        window.contentView = outer

        XCTAssertEqual(handedOver.count, 1, "AppKit told the view as its hierarchy joined the window")
        XCTAssertTrue(handedOver.first === window)
    }

    /// Handed over once only: a view moved to a second window does not
    /// claim a second remembered folder or place a second window.
    func testTheWindowIsHandedOverOnceEvenWhenTheViewMoves() {
        var handedOver: [NSWindow] = []
        let reader: NSView = WindowAccessor.makeWindowReadingView { window in
            handedOver.append(window)
        }
        let first: NSWindow = makeWindow()
        first.contentView?.addSubview(reader)
        reader.removeFromSuperview()
        let second: NSWindow = makeWindow()
        second.contentView?.addSubview(reader)

        XCTAssertEqual(handedOver.count, 1)
        XCTAssertTrue(handedOver.first === first)
    }

    /// The house rule, held in the file itself: no timed retry and no GCD.
    /// This is the assertion that fails on the code before #998.
    func testTheAccessorWaitsOnNoTimer() throws {
        let source: String = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("QuartzTeachers/Views/Helpers/WindowAccessor.swift"),
            encoding: .utf8
        )
        for forbidden in ["DispatchQueue.main", "asyncAfter(", "Task.sleep", "Timer."] {
            XCTAssertFalse(source.contains(forbidden), "WindowAccessor.swift uses \(forbidden)")
        }
    }
}
