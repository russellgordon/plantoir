import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// #997, part of the HIG review (#975): Tab in the class-dates box (ruling
/// Q-C) and the Settings panes' sizes (D42). The sidebar's two findings are
/// read off the accessibility tree in `AccessibilityTreeTests`, and the
/// Publish Pages picker's in `PageTablesSheetTests`.
@MainActor
final class LayoutAndSmallBehaviourTests: XCTestCase {

    // MARK: - Functions

    /// Every text view in a view tree that is not a field editor.
    static func textViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        if let textView = view as? NSTextView, !textView.isFieldEditor {
            found.append(textView)
        }
        for subview in view.subviews {
            for inner in textViews(in: subview) {
                found.append(inner)
            }
        }
        return found
    }

    /// Every scroll view in a view tree.
    static func scrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scrollView = view as? NSScrollView {
            found.append(scrollView)
        }
        for subview in view.subviews {
            for inner in scrollViews(in: subview) {
                found.append(inner)
            }
        }
        return found
    }

    /// A Tab key press, or Shift-Tab, as the keyboard delivers it.
    static func tabKey(shifted: Bool, in window: NSWindow) throws -> NSEvent {
        var flags: NSEvent.ModifierFlags = []
        if shifted {
            flags = [.shift]
        }
        let characters: String = shifted ? "\u{19}" : "\t"
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: NSPoint.zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 48
        ))
    }

    /// The size a pane takes, laid out at the Settings window's width.
    static func fittedSize(of pane: some View) -> NSSize {
        let hostingView: NSHostingView = NSHostingView(rootView: AnyView(pane.settingsPaneFitsItsContent()))
        hostingView.frame = NSRect(x: 0, y: 0, width: PlantoirSettingsView.paneWidth, height: 2000)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize
    }

    // MARK: - Tab in the class-dates box (ruling Q-C)

    /// Tab leaves the dates box for the next control, and Shift-Tab for the
    /// one before, and neither types a tab character into the dates. Before
    /// #997 the box was a `TextEditor`, which typed a tab and kept the focus.
    func testTabAndShiftTabLeaveTheDatesBoxAndTypeNothing() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let host: TableHost = TableHost(
            SectionScheduleSheet(course: made.course, sectionNumber: 1), size: NSSize(width: 600, height: 620)
        )
        defer {
            host.close()
        }
        host.pump(0.4)
        let content: NSView = try XCTUnwrap(host.window.contentView)
        let boxes: [NSTextView] = LayoutAndSmallBehaviourTests.textViews(in: content)
        XCTAssertEqual(boxes.count, 1, "the sheet should hold one dates box")
        let box: NSTextView = try XCTUnwrap(boxes.first)
        XCTAssertTrue(host.window.firstResponder === box, "the dates box does not have the focus as the sheet opens")
        box.string = "2026-09-08"
        box.setSelectedRange(NSRange(location: 10, length: 0))

        XCTAssertTrue(host.window.makeFirstResponder(box))
        box.keyDown(with: try LayoutAndSmallBehaviourTests.tabKey(shifted: false, in: host.window))
        host.pump(0.1)
        XCTAssertEqual(box.string, "2026-09-08", "Tab typed into the dates box")
        XCTAssertFalse(host.window.firstResponder === box, "Tab left the focus in the dates box")
        print("LayoutAndSmallBehaviourTests: Tab moved to \(String(describing: host.window.firstResponder))")

        XCTAssertTrue(host.window.makeFirstResponder(box))
        box.keyDown(with: try LayoutAndSmallBehaviourTests.tabKey(shifted: true, in: host.window))
        host.pump(0.1)
        XCTAssertEqual(box.string, "2026-09-08", "Shift-Tab typed into the dates box")
        XCTAssertFalse(host.window.firstResponder === box, "Shift-Tab left the focus in the dates box")

        // Return still starts a new line: the box is for one date per line.
        XCTAssertTrue(host.window.makeFirstResponder(box))
        box.insertNewline(nil)
        XCTAssertEqual(box.string, "2026-09-08\n")
    }

    /// What is typed reaches the sheet: the box's text is the binding's.
    func testWhatIsTypedInTheDatesBoxReachesTheBinding() throws {
        var typed: String = ""
        let binding: Binding<String> = Binding(get: { return typed }, set: { (text: String) in typed = text })
        let host: TableHost = TableHost(
            ClassDatesTextBox(text: binding, accessibilityName: AccessibilityNames.classDates, identifier: "datesBox"),
            size: NSSize(width: 400, height: 200)
        )
        defer {
            host.close()
        }
        host.pump(0.2)
        let box: NSTextView = try XCTUnwrap(LayoutAndSmallBehaviourTests.textViews(in: try XCTUnwrap(host.window.contentView)).first)
        XCTAssertTrue(host.window.makeFirstResponder(box))
        box.insertText("2026-09-08", replacementRange: NSRange(location: NSNotFound, length: 0))
        host.pump(0.1)
        XCTAssertEqual(typed, "2026-09-08")
    }

    // MARK: - The Settings panes' sizes (D42)

    /// Each pane is as tall as what it holds, so the window, which takes the
    /// chosen pane's size, is small for Preview and Obsidian and tall enough
    /// for Assistant. Before #997 every pane opened at 560 × 648.
    func testEachSettingsPaneIsAsTallAsWhatItHolds() {
        let assistant: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: AssistantSettingsView())
        let preview: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: PreviewSettingsView())
        let obsidian: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: ObsidianSettingsView())
        print("LayoutAndSmallBehaviourTests: Settings panes Assistant \(assistant), Preview \(preview), Obsidian \(obsidian)")
        for size in [assistant, preview, obsidian] {
            XCTAssertEqual(size.width, PlantoirSettingsView.paneWidth)
        }
        XCTAssertLessThan(preview.height, 300, "Preview is mostly empty space")
        XCTAssertLessThan(obsidian.height, 300, "Obsidian is mostly empty space")
        XCTAssertGreaterThan(assistant.height, preview.height + 100, "the panes share one height")
    }

    /// At its own size the Assistant pane shows everything it holds without
    /// scrolling, where at 560 it scrolled.
    func testTheAssistantPaneDoesNotScrollAtItsOwnSize() throws {
        let size: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: AssistantSettingsView())
        let host: TableHost = TableHost(AssistantSettingsView().settingsPaneFitsItsContent(), size: size)
        defer {
            host.close()
        }
        host.pump(0.4)
        let scrollViews: [NSScrollView] = LayoutAndSmallBehaviourTests.scrollViews(in: try XCTUnwrap(host.window.contentView))
        XCTAssertFalse(scrollViews.isEmpty, "the pane's form has no scroll view to read")
        for scrollView in scrollViews {
            let held: CGFloat = scrollView.documentView?.frame.height ?? 0
            let shown: CGFloat = scrollView.contentView.bounds.height
            print("LayoutAndSmallBehaviourTests: Assistant pane at \(size) holds \(held) pt and shows \(shown) pt")
            XCTAssertLessThanOrEqual(held, shown + 1, "the Assistant pane scrolls at its own size \(size)")
        }
    }
}
