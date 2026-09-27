import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The sidebar cannot be dragged wider than its maximum (#213).
///
/// `ProgressViewSizeTests.testTheFolderNoteKeepsEveryLineAtEveryColumnTheWindowAllows`
/// proves the note keeps its lines at `WindowChrome.narrowestDetailColumn`;
/// this proves no narrower column can be reached, by dragging the divider the
/// way a teacher would — `setPosition(700, ofDividerAt: 0)`, the drag that left
/// a 200-wide column before the cap. Neither test alone is the fix: one is a
/// width nobody can reach, the other a maximum with nothing to protect.
/// The split view is hosted with the SAME modifier the window uses.
@MainActor
final class SidebarWidthTests: XCTestCase {

    // MARK: - Functions

    private func findSplitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView {
            return split
        }
        for child in view.subviews {
            if let found = findSplitView(in: child) {
                return found
            }
        }
        return nil
    }

    // MARK: - Tests

    func testTheSidebarCannotBeDraggedWiderThanItsMaximum() throws {
        let root = NavigationSplitView {
            List {
                Text("ICS4U")
            }
            .plantoirSidebarColumnWidth()
        } detail: {
            Color.clear
        }
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WindowChrome.minimumWindowWidth, height: WindowChrome.minimumWindowHeight),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: root)
        window.setContentSize(NSSize(width: WindowChrome.minimumWindowWidth, height: WindowChrome.minimumWindowHeight))
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        guard let content = window.contentView, let split = findSplitView(in: content),
              split.arrangedSubviews.count >= 2 else {
            throw XCTSkip("The split view was not laid out in a window that is not on screen, so there is no divider to drag.")
        }
        split.setPosition(700, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        let sidebarWidth: CGFloat = split.arrangedSubviews[0].frame.width
        let detailWidth: CGFloat = split.arrangedSubviews[split.arrangedSubviews.count - 1].frame.width
        XCTAssertLessThanOrEqual(sidebarWidth, WindowChrome.sidebarMaximumWidth + WindowChrome.splitViewGutter,
                                 "the sidebar was dragged to \(sidebarWidth)")
        XCTAssertGreaterThanOrEqual(
            detailWidth, WindowChrome.narrowestDetailColumn,
            "dragging the sidebar left a \(detailWidth)-wide column, narrower than the \(WindowChrome.narrowestDetailColumn) "
                + "the folder note is proved at"
        )
    }
}
