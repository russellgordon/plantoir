import AppKit
import ApplicationServices
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Tab and Shift-Tab in the class-dates box (#997, ruling Q-C on #975),
/// pressed as the keyboard presses them, in a KEY window of the ACTIVE
/// app, and the control that then has the focus named, as VoiceOver is
/// told it (`AccessibilityTree.focusedElement`). The first review of #997
/// found the earlier test proved nothing: its window was never key, and it
/// asserted only that the focus was no longer in the box.
///
/// Which control is next depends on Keyboard Navigation (System Settings >
/// Keyboard, `AppleKeyboardUIMode`): with it on, Tab reaches every control,
/// so Shift-Tab from the box goes back to the route picker above it; with
/// it off, Tab moves between text boxes only, so both keys go to the one
/// other box, "Where these came from". Each test asserts the order for the
/// mode this Mac is in, and says which; the main Mac runs with it on, the
/// second Mac with it off.
///
/// These take the front from whatever the person at the Mac is using, so
/// they run only when asked (`PLANTOIR_KEY_TESTS=1`, as
/// `ProgressCancelKeysTests`), under the screen lock.
@MainActor
final class ClassDatesBoxKeyTests: XCTestCase {

    // MARK: - Stored properties

    var openWindows: [NSWindow] = []

    // MARK: - Functions

    override func tearDown() async throws {
        for window in openWindows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
            window.orderOut(nil)
            window.contentViewController = nil
        }
        openWindows = []
        // The unit host is an accessory app (#633); bringing it forward
        // made it a regular one.
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func runUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end: Date = Date(timeIntervalSinceNow: timeout)
        while Date() < end {
            if condition() {
                return true
            }
            // Events are handed out as the app's own loop does, so an
            // activation and a key arrive while waiting.
            if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.02), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        }
        return condition()
    }

    func settle(_ seconds: TimeInterval) {
        _ = runUntil(timeout: seconds) { return false }
    }

    /// `content` in a window of its own, the key window of the active app,
    /// off every display. Skips unless asked for, or when the host cannot
    /// take the front.
    func keyWindow(hosting content: some View, size: NSSize) throws -> NSWindow {
        if ProcessInfo.processInfo.environment["PLANTOIR_KEY_TESTS"] != "1" {
            throw XCTSkip("Takes the front to press real keys; set PLANTOIR_KEY_TESTS=1 (TEST_RUNNER_PLANTOIR_KEY_TESTS=1 for xcodebuild) on a Mac nobody is using.")
        }
        let origin: NSPoint = TableHost.offScreenOrigin(for: size)
        let window: NSWindow = OffScreenWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.title = "class-dates-keys-\(UUID().uuidString)"
        window.contentViewController = NSHostingController(rootView: content.frame(width: size.width, height: size.height, alignment: .top))
        window.setFrameOrigin(origin)
        openWindows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.isActive {
            let application: AXUIElement = AXUIElementCreateApplication(getpid())
            AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        for _ in 1...2 where !NSApp.isActive {
            // As `ProgressCancelKeysTests`: asked through Launch Services,
            // naming this running host's own bundle, which brings this copy
            // forward and opens no other.
            let opener: Process = Process()
            opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            opener.arguments = [Bundle.main.bundleURL.path]
            try? opener.run()
            opener.waitUntilExit()
            _ = runUntil(timeout: 10) { return NSApp.isActive }
        }
        window.makeKeyAndOrderFront(nil)
        if !runUntil(timeout: 5, { return NSApp.isActive && window.isKeyWindow }) {
            window.makeKeyAndOrderFront(nil)
        }
        if !runUntil(timeout: 5, { return NSApp.isActive && window.isKeyWindow }) {
            throw XCTSkip("The test host could not be made the active app with its window key (a locked screen, another Space or another account using the Mac, #315).")
        }
        settle(0.6)
        return window
    }

    /// Tab, or Shift-Tab, down and up, through the app as the keyboard
    /// sends it, to whichever window is key.
    func pressTab(shifted: Bool) throws {
        guard let target = NSApp.keyWindow else {
            throw XCTSkip("No key window when Tab was pressed: another app took the front midway (#846).")
        }
        var flags: NSEvent.ModifierFlags = []
        if shifted {
            flags = [.shift]
        }
        let characters: String = shifted ? "\u{19}" : "\t"
        for type in [NSEvent.EventType.keyDown, NSEvent.EventType.keyUp] {
            let event: NSEvent = try XCTUnwrap(NSEvent.keyEvent(
                with: type, location: NSPoint.zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: target.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 48
            ))
            NSApp.sendEvent(event)
        }
        settle(0.3)
    }

    /// The identifier of the control that has the focus, as VoiceOver is
    /// told it. A text field being typed in reports the field editor AppKit
    /// lends it, and a segmented picker the segment, neither of which
    /// carries the control's identifier; so where the focused element has
    /// none, the control is the innermost element of the window's tree,
    /// with an identifier, that holds the focused element's middle.
    func focusedControl(inWindowTitled title: String) -> String {
        guard let focused = AccessibilityTree.focusedElement() else {
            return "nothing"
        }
        if !focused.identifier.isEmpty {
            return focused.identifier
        }
        if !focused.frame.isNull {
            let middle: CGPoint = CGPoint(x: focused.frame.midX, y: focused.frame.midY)
            let read: AccessibilityTree = AccessibilityTree(ofWindowTitled: title)
            var innermost: String = ""
            for element in read.elements {
                if !element.identifier.isEmpty && !element.frame.isNull && element.frame.contains(middle) {
                    innermost = element.identifier
                }
            }
            if !innermost.isEmpty {
                return innermost
            }
        }
        return "\(focused.role) [\(focused.label)] [\(focused.title)]"
    }

    /// The order the keys take around the box in whichever sheet holds it.
    /// With Keyboard Navigation on, Tab goes on to "Where these came from"
    /// and Shift-Tab back to the route picker; with it off, both go to
    /// "Where these came from", the only other text box.
    func assertTabAndShiftTabNameTheirControls(in window: NSWindow, box: NSTextView, treeTitle: String) throws {
        let isOn: Bool = NSApp.isFullKeyboardAccessEnabled
        print("ClassDatesBoxKeyTests: Keyboard Navigation \(isOn ? "on" : "off"); window key \(window.isKeyWindow)")
        XCTAssertTrue(window.isKeyWindow, "the window holding the box is not key")
        XCTAssertTrue(window.firstResponder === box, "the box does not have the focus as the sheet opens")
        XCTAssertEqual(focusedControl(inWindowTitled: treeTitle), "sectionScheduleTypedField", "VoiceOver is not told the box has the focus")
        box.insertText("2026-09-08", replacementRange: NSRange(location: NSNotFound, length: 0))

        try pressTab(shifted: false)
        let afterTab: String = focusedControl(inWindowTitled: treeTitle)
        print("ClassDatesBoxKeyTests: Tab from the box went to \(afterTab)")
        XCTAssertEqual(afterTab, "sectionScheduleSourceField", "Tab from the box (Keyboard Navigation \(isOn ? "on" : "off"))")
        XCTAssertEqual(box.string, "2026-09-08", "Tab typed into the box")

        try pressTab(shifted: true)
        XCTAssertEqual(focusedControl(inWindowTitled: treeTitle), "sectionScheduleTypedField", "Shift-Tab from Where these came from did not come back to the box")

        try pressTab(shifted: true)
        let afterShiftTab: String = focusedControl(inWindowTitled: treeTitle)
        print("ClassDatesBoxKeyTests: Shift-Tab from the box went to \(afterShiftTab)")
        if isOn {
            XCTAssertEqual(afterShiftTab, "sectionScheduleRoutePicker", "Shift-Tab from the box, Keyboard Navigation on")
        } else {
            XCTAssertEqual(afterShiftTab, "sectionScheduleSourceField", "Shift-Tab from the box, Keyboard Navigation off")
        }
        XCTAssertEqual(box.string, "2026-09-08", "Shift-Tab typed into the box")
    }

    /// Class Dates…'s own sheet.
    func testTabAndShiftTabFromTheDatesBoxNameTheNextControls() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let window: NSWindow = try keyWindow(
            hosting: SectionScheduleSheet(course: made.course, sectionNumber: 1), size: NSSize(width: 600, height: 620)
        )
        let content: NSView = try XCTUnwrap(window.contentView)
        let box: NSTextView = try XCTUnwrap(LayoutAndSmallBehaviourTests.textViews(in: content).first, "no dates box")
        try assertTabAndShiftTabNameTheirControls(in: window, box: box, treeTitle: window.title)
    }

    /// The same box where Add Class, Make Room and Roll Over show it: the
    /// Class Dates stage of `SectionVerbSheet`, hung as a sheet from a key
    /// window, as a section's window hangs it (`askForDatesFirst`).
    func testTabAndShiftTabInTheVerbSheetsDatesBoxNameTheNextControls() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .classDates, course: made.course, sectionNumber: 1, title: "", item: .classDates
        )
        model.reason = AssistWording.datesToMakeRoom(noun: made.course.configuration.classNoun)
        let presentation: SheetHostPresentation = SheetHostPresentation()
        SheetsHungOffScreenStayThere.install()
        let window: NSWindow = try keyWindow(
            hosting: SheetHostRoot(presentation: presentation, content: AnyView(SectionVerbSheet(model: model, pressDefault: {}, cancel: {}))),
            size: NSSize(width: 1200, height: 900)
        )
        presentation.isShown = true
        XCTAssertTrue(runUntil(timeout: 3) { return window.attachedSheet?.isKeyWindow == true }, "the verb sheet did not open in front")
        let sheet: NSWindow = try XCTUnwrap(window.attachedSheet)
        let box: NSTextView = try XCTUnwrap(
            LayoutAndSmallBehaviourTests.textViews(in: try XCTUnwrap(sheet.contentView)).first, "no dates box in the verb sheet"
        )
        try assertTabAndShiftTabNameTheirControls(in: sheet, box: box, treeTitle: window.title)
    }
}
