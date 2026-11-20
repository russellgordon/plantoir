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

    /// The size a pane takes, laid out at the Settings window's width, on
    /// a screen that allows it `tallest` points.
    static func fittedSize(of pane: some View, tallest: CGFloat = 4000) -> NSSize {
        let hostingView: NSHostingView = NSHostingView(rootView: AnyView(pane.settingsPaneFitsItsContent(tallest: tallest)))
        hostingView.frame = NSRect(x: 0, y: 0, width: PlantoirSettingsView.paneWidth, height: 2000)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize
    }

    /// The scroll view that holds a pane's form: the one with the tallest
    /// document.
    static func formScrollView(in view: NSView) -> NSScrollView? {
        var tallestScrollView: NSScrollView?
        var tallestHeld: CGFloat = -1
        for scrollView in scrollViews(in: view) {
            let held: CGFloat = scrollView.documentView?.frame.height ?? 0
            if held > tallestHeld {
                tallestHeld = held
                tallestScrollView = scrollView
            }
        }
        return tallestScrollView
    }

    /// A window's frame as an assistive app is told frames: screen points
    /// with the origin at the top left of the main display.
    static func topLeftFrame(of window: NSWindow) -> CGRect {
        var mainHeight: CGFloat = 0
        if let first = NSScreen.screens.first {
            mainHeight = first.frame.height
        }
        let frame: NSRect = window.frame
        return CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
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

    // MARK: - The dates box: paste, undo, the route picker, the verb sheet

    /// A box on its own, bound to `typed`, with its text view.
    static func hostedBox(_ binding: Binding<String>) throws -> (host: TableHost, box: NSTextView) {
        let host: TableHost = TableHost(
            ClassDatesTextBox(text: binding, accessibilityName: AccessibilityNames.classDates, identifier: "datesBox"),
            size: NSSize(width: 400, height: 200)
        )
        host.pump(0.2)
        let box: NSTextView = try XCTUnwrap(LayoutAndSmallBehaviourTests.textViews(in: try XCTUnwrap(host.window.contentView)).first)
        return (host, box)
    }

    /// Every segmented control in a view tree.
    static func segmentedControls(in view: NSView) -> [NSSegmentedControl] {
        var found: [NSSegmentedControl] = []
        if let control = view as? NSSegmentedControl {
            found.append(control)
        }
        for subview in view.subviews {
            for inner in segmentedControls(in: subview) {
                found.append(inner)
            }
        }
        return found
    }

    /// Several lines pasted at once arrive whole, one date per line, in the
    /// binding. Pasted from a pasteboard of the test's own, read the way
    /// Paste reads the general one, so the person's clipboard is untouched.
    func testPastingSeveralLinesReachesTheBinding() throws {
        var typed: String = ""
        let binding: Binding<String> = Binding(get: { return typed }, set: { (text: String) in typed = text })
        let hosted = try LayoutAndSmallBehaviourTests.hostedBox(binding)
        defer {
            hosted.host.close()
        }
        let pasteboard: NSPasteboard = NSPasteboard(name: NSPasteboard.Name("LayoutAndSmallBehaviourTests-\(UUID().uuidString)"))
        defer {
            pasteboard.releaseGlobally()
        }
        let column: String = "Date\n2026-09-08\n2026-09-10\n\n2026-09-14"
        pasteboard.clearContents()
        pasteboard.setString(column, forType: .string)
        XCTAssertTrue(hosted.host.window.makeFirstResponder(hosted.box))
        XCTAssertTrue(hosted.box.readSelection(from: pasteboard, type: .string), "the box would not paste text")
        hosted.host.pump(0.1)
        XCTAssertEqual(hosted.box.string, column)
        XCTAssertEqual(typed, column, "the pasted lines did not reach the binding")
        XCTAssertEqual(typed.components(separatedBy: "\n").count, 5)
    }

    /// Undo and Redo inside the box change the binding as well as the box.
    func testUndoAndRedoInTheDatesBoxReachTheBinding() throws {
        var typed: String = ""
        let binding: Binding<String> = Binding(get: { return typed }, set: { (text: String) in typed = text })
        let hosted = try LayoutAndSmallBehaviourTests.hostedBox(binding)
        defer {
            hosted.host.close()
        }
        XCTAssertTrue(hosted.host.window.makeFirstResponder(hosted.box))
        // Pasted text already in the box, then a line typed: Undo takes the
        // typing back and leaves what was there, and Redo puts it back.
        hosted.box.string = "2026-09-08"
        binding.wrappedValue = "2026-09-08"
        hosted.box.setSelectedRange(NSRange(location: 10, length: 0))
        hosted.box.insertText("\n2026-09-10", replacementRange: NSRange(location: NSNotFound, length: 0))
        hosted.host.pump(0.1)
        XCTAssertEqual(typed, "2026-09-08\n2026-09-10")
        let undoManager: UndoManager = try XCTUnwrap(hosted.box.undoManager, "the box has no undo manager")
        XCTAssertTrue(undoManager.canUndo, "typing in the box left nothing to undo")

        undoManager.undo()
        hosted.host.pump(0.1)
        XCTAssertEqual(hosted.box.string, "2026-09-08", "Undo did not take back the typed line")
        XCTAssertEqual(typed, "2026-09-08", "Undo changed the box but not the binding")

        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        hosted.host.pump(0.1)
        XCTAssertEqual(hosted.box.string, "2026-09-08\n2026-09-10", "Redo did not put the typed line back")
        XCTAssertEqual(typed, "2026-09-08\n2026-09-10", "Redo changed the box but not the binding")
    }

    /// The box takes the focus when the sheet opens on it, and not when the
    /// route picker is moved off Typed and back onto it: the keyboard stays
    /// where it was (#997). Before, the new box took the focus as it was
    /// drawn, so arrowing from Upload to Typed pulled the keyboard out of
    /// the picker.
    func testChoosingTypedAgainLeavesTheFocusWhereItWas() throws {
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
        let firstBox: NSTextView = try XCTUnwrap(LayoutAndSmallBehaviourTests.textViews(in: content).first)
        XCTAssertTrue(host.window.firstResponder === firstBox, "the box does not have the focus as the sheet opens on it")
        let picker: NSSegmentedControl = try XCTUnwrap(LayoutAndSmallBehaviourTests.segmentedControls(in: content).first, "no route picker")
        XCTAssertEqual(picker.segmentCount, SectionScheduleSheet.Route.allCases.count)

        // The focus goes to the picker where it can take it (Keyboard
        // Navigation on); otherwise it is left on nothing in the sheet.
        if !host.window.makeFirstResponder(picker) {
            XCTAssertTrue(host.window.makeFirstResponder(nil))
        }
        let before: NSResponder? = host.window.firstResponder
        for segment in [1, 0] {
            picker.selectedSegment = segment
            _ = picker.sendAction(picker.action, to: picker.target)
            host.pump(0.3)
        }
        let boxes: [NSTextView] = LayoutAndSmallBehaviourTests.textViews(in: content)
        XCTAssertEqual(boxes.count, 1, "Typed is not showing its box again")
        let secondBox: NSTextView = try XCTUnwrap(boxes.first)
        XCTAssertFalse(secondBox === firstBox, "the route picker did not draw a new box (nothing was tested)")
        print("LayoutAndSmallBehaviourTests: after Upload and back to Typed the focus is on \(String(describing: host.window.firstResponder)), was \(String(describing: before))")
        XCTAssertFalse(host.window.firstResponder === secondBox, "choosing Typed again pulled the focus into the box")
        XCTAssertTrue(host.window.firstResponder === before, "the focus moved when Typed was chosen again")
    }

    /// The box inside Add Class, Make Room and Roll Over: with no class
    /// dates on file, each opens `SectionVerbSheet` on its Class Dates
    /// stage (`askForDatesFirst`), and that sheet's box takes the focus as
    /// it opens, and Tab and Shift-Tab leave it and type nothing.
    func testTheBoxInTheVerbSheetTakesTheFocusAndTabLeavesIt() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .classDates, course: made.course, sectionNumber: 1, title: "", item: .classDates
        )
        model.reason = AssistWording.datesForTheNextPage(noun: made.course.configuration.classNoun)
        let host: SheetHost = SheetHost(SectionVerbSheet(model: model, pressDefault: {}, cancel: {}))
        defer {
            host.close()
        }
        let sheet: NSWindow = try XCTUnwrap(host.sheet, "the verb sheet did not open")
        let boxes: [NSTextView] = LayoutAndSmallBehaviourTests.textViews(in: try XCTUnwrap(sheet.contentView))
        XCTAssertEqual(boxes.count, 1, "the verb sheet's Class Dates stage should hold one dates box")
        let box: NSTextView = try XCTUnwrap(boxes.first)
        XCTAssertTrue(sheet.firstResponder === box, "the box does not have the focus as the verb sheet opens")
        box.insertText("2026-09-08", replacementRange: NSRange(location: NSNotFound, length: 0))

        box.keyDown(with: try LayoutAndSmallBehaviourTests.tabKey(shifted: false, in: sheet))
        host.pump(0.1)
        XCTAssertEqual(box.string, "2026-09-08", "Tab typed into the box")
        XCTAssertFalse(sheet.firstResponder === box, "Tab left the focus in the box")
        let afterTab: NSResponder? = sheet.firstResponder
        XCTAssertTrue(afterTab is NSText, "Tab went to \(String(describing: afterTab)), not to the Where these came from field")

        XCTAssertTrue(sheet.makeFirstResponder(box))
        box.keyDown(with: try LayoutAndSmallBehaviourTests.tabKey(shifted: true, in: sheet))
        host.pump(0.1)
        XCTAssertEqual(box.string, "2026-09-08", "Shift-Tab typed into the box")
        XCTAssertFalse(sheet.firstResponder === box, "Shift-Tab left the focus in the box")
    }

    // MARK: - The Settings panes' sizes (D42)

    /// Each pane is as tall as what it holds, so the window, which takes the
    /// chosen pane's size, is small for Preview and Obsidian and tall enough
    /// for Assistant. Before #997 every pane opened at 560 x 648. Every pane
    /// is measured and printed, Deploying with its Stopping section (#988)
    /// and Other Assistants included.
    func testEachSettingsPaneIsAsTallAsWhatItHolds() {
        let assistant: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: AssistantSettingsView())
        let preview: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: PreviewSettingsView())
        let obsidian: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: ObsidianSettingsView())
        let deploying: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: DeployingSettingsView())
        let otherAssistants: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: OtherAssistantsSettingsView())
        print("LayoutAndSmallBehaviourTests: Settings panes' own heights: Assistant \(assistant.height), Preview \(preview.height), Obsidian \(obsidian.height), Deploying \(deploying.height), Other Assistants \(otherAssistants.height)")
        for size in [assistant, preview, obsidian, deploying, otherAssistants] {
            XCTAssertEqual(size.width, PlantoirSettingsView.paneWidth)
            XCTAssertGreaterThan(size.height, 100, "a pane folded to nothing")
        }
        XCTAssertLessThan(preview.height, 300, "Preview is mostly empty space")
        XCTAssertLessThan(obsidian.height, 300, "Obsidian is mostly empty space")
        XCTAssertGreaterThan(assistant.height, preview.height + 100, "the panes share one height")
    }

    /// At its own size the Assistant pane shows everything it holds without
    /// scrolling, where at 560 it scrolled.
    func testTheAssistantPaneDoesNotScrollAtItsOwnSize() throws {
        let size: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: AssistantSettingsView())
        let host: TableHost = TableHost(AssistantSettingsView().settingsPaneFitsItsContent(tallest: 4000), size: size)
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

    /// A pane taller than the screen allows is held to what it allows, and
    /// its form scrolls to its last control. The first version of #997 let
    /// the 674 pt Assistant pane run past a short screen (1280 x 800 with
    /// the Dock, or a scaled 1024 x 640) with no way to its bottom, where
    /// the last download's button (Download, or Remove…) is.
    func testATallPaneScrollsToItsLastControlOnAShortScreen() throws {
        let own: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: AssistantSettingsView())
        let tallest: CGFloat = 400
        XCTAssertGreaterThan(own.height, tallest + 100, "the Assistant pane is not tall enough to test this with")
        let held: NSSize = LayoutAndSmallBehaviourTests.fittedSize(of: AssistantSettingsView(), tallest: tallest)
        print("LayoutAndSmallBehaviourTests: the Assistant pane, \(own.height) pt of content, is held to \(held.height) pt")
        XCTAssertEqual(held.height, tallest, accuracy: 1, "the pane is not held to what the screen allows")

        let host: TableHost = TableHost(AssistantSettingsView().settingsPaneFitsItsContent(tallest: tallest), size: held)
        defer {
            host.close()
        }
        let title: String = "settings-pane-\(UUID().uuidString)"
        host.window.title = title
        host.pump(0.5)
        let scrollView: NSScrollView = try XCTUnwrap(
            LayoutAndSmallBehaviourTests.formScrollView(in: try XCTUnwrap(host.window.contentView)),
            "the pane's form has no scroll view"
        )
        let document: NSView = try XCTUnwrap(scrollView.documentView)
        let shown: CGFloat = scrollView.contentView.bounds.height
        print("LayoutAndSmallBehaviourTests: held at \(tallest) pt the form holds \(document.frame.height) pt and shows \(shown) pt")
        XCTAssertGreaterThan(document.frame.height, shown + 100, "the form does not hold more than it shows, so nothing scrolls")

        // To the end, as a teacher scrolls: the last control is then on show.
        var end: NSPoint = NSPoint(x: 0, y: 0)
        if document.isFlipped {
            end = NSPoint(x: 0, y: document.frame.height - shown)
        }
        document.scroll(end)
        host.pump(0.5)
        let visible: NSRect = document.visibleRect
        if document.isFlipped {
            XCTAssertEqual(visible.maxY, document.frame.height, accuracy: 1, "the form did not scroll to its end")
        } else {
            XCTAssertEqual(visible.minY, 0, accuracy: 1, "the form did not scroll to its end")
        }

        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(host.window)
        let read: AccessibilityTree = AccessibilityTree(ofWindowTitled: title)
        XCTAssertTrue(read.foundTheWindow, "the hosted window is not in the accessibility tree")
        let lastTier: AssistModelTier = try XCTUnwrap(AssistModelTier.allCases.last)
        let suffix: String = lastTier.rawValue.prefix(1).uppercased() + lastTier.rawValue.dropFirst()
        var lastControl: AccessibilityTree.Element?
        for prefix in ["assistantDownload", "assistantRemove", "assistantStopDownload"] {
            if let found = read.elements(identifiedAs: prefix + suffix).first {
                lastControl = found
            }
        }
        let control: AccessibilityTree.Element = try XCTUnwrap(lastControl, "the last download's button is not in the window after scrolling: \(read.described())")
        let windowFrame: CGRect = LayoutAndSmallBehaviourTests.topLeftFrame(of: host.window)
        print("LayoutAndSmallBehaviourTests: the last control \(control.identifier) at \(control.frame), window \(windowFrame)")
        XCTAssertTrue(windowFrame.contains(control.frame), "the last control \(control.identifier) is not on show after scrolling to the end")
    }

    /// What the cap allows on the short screens the review named. 1280 x
    /// 800 with the Dock shows about 705 pt; a scaled 1024 x 640 about
    /// 560 pt; on either the Assistant pane's 674 pt of content and the
    /// window around it do not fit, so the pane is held and scrolls.
    func testThePaneCapLeavesRoomForTheWindowAroundIt() {
        let laptop: CGFloat = SettingsPaneHeight.tallest(onScreenShowing: 705)
        let scaled: CGFloat = SettingsPaneHeight.tallest(onScreenShowing: 560)
        print("LayoutAndSmallBehaviourTests: pane cap \(laptop) pt at 705 visible, \(scaled) pt at 560 visible, \(SettingsPaneHeight.tallestOnThisScreen()) pt on this Mac")
        XCTAssertEqual(laptop + SettingsPaneHeight.windowChrome + SettingsPaneHeight.screenMargin * 2, 705, accuracy: 0.5)
        XCTAssertLessThan(scaled + SettingsPaneHeight.windowChrome, 560)
        XCTAssertLessThan(laptop, 674, "the Assistant pane would run off a 1280 x 800 screen")
        XCTAssertEqual(SettingsPaneHeight.tallest(onScreenShowing: 100), SettingsPaneHeight.fewest)
    }
}
