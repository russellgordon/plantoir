import AppKit
import ApplicationServices
import Observation
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Escape and Command-Period stop a running preview or deploy (#988, the
/// HIG review's finding D6), pressed for real.
///
/// Keyboards, https://developer.apple.com/design/human-interface-guidelines/keyboards:
/// "Esc: Cancel the current action or process"; "Command-Period: Cancel an
/// operation." Progress indicators: "When it's feasible, let people halt
/// processing."
///
/// **The visible Cancel holds the key** (`TaskCancelButton`, a real push
/// button whose `performKeyEquivalent` takes Escape and Command-Period while
/// `TaskProgressView.cancelKeysAreLive`), and refuses it while a box is being
/// typed in (read when the key arrives), while a sheet, an alert or a
/// popover is in front, and while a preview's site covers the panel. No invisible view, responder or
/// key catcher (Russell's rule): the third #988 review found the earlier
/// responder-chain route did nothing in a window whose content is a hosting
/// CONTROLLER, the shape the app's own windows have.
///
/// So every key here is pressed the way a teacher's is: the panel is drawn
/// in a window whose content is an `NSHostingController`, made the key
/// window of the active app, with the panel appearing after the window is
/// up (as a preview's does), and the key-down goes through
/// `NSApp.sendEvent`, the route a real key takes (key equivalents first,
/// then the first responder). When the host cannot be made the active app
/// with that window key (a locked screen, another Space, another account
/// using the Mac, #315), those tests skip and say so: a key sent to a window
/// that is not key proves nothing about what a teacher sees. None of them
/// depends on Keyboard Navigation (System Settings ▸ Keyboard,
/// `AppleKeyboardUIMode`): measured on the main Mac with it off and on.
///
/// **Opt-in** (`PLANTOIR_KEY_TESTS=1`, passed to xcodebuild as
/// `TEST_RUNNER_PLANTOIR_KEY_TESTS=1`): bringing the host forward takes the
/// front from the person at the Mac, and a key they type meanwhile goes to
/// the test host. Without it the pressed-key tests skip, saying so, and the
/// rule and source tests below still run. The merge gate runs them after the
/// suite (`vm-tools/gate-here.sh`), unless the screen is in use.
///
/// Measured failing before #988: the panel's Cancel carried no key, so both
/// keys reached nothing.
@MainActor
final class ProgressCancelKeysTests: XCTestCase {

    // MARK: - Types

    /// The keys a test sends.
    enum Key {
        case escape
        case commandPeriod
        case returnKey
    }

    /// How many times the panel's Cancel ran, and what else answered a key.
    @Observable
    final class Ledger {

        // MARK: - Stored properties

        var cancelCount: Int = 0
        var text: String = "abc"
        var fieldEscapeCount: Int = 0
        var showsPanel: Bool = false
        var showsSheet: Bool = false
        var sheetHoldsEscape: Bool = true
        var sheetCancelCount: Int = 0
        var showsAlert: Bool = false
        var alertCancelCount: Int = 0
        /// A text view (`TextEditor`) beside the Filter field.
        var showsNotes: Bool = false
        var notes: String = "Notes"
        /// A field with no use for Escape (no `onExitCommand`).
        var showsRename: Bool = false
        var renameText: String = "Section 1"
        /// The panel opens with its console showing.
        var showsDetails: Bool = false
    }

    /// The section window's shape around the panel: a sidebar, a filter
    /// box in the detail column, and the panel, which appears only once a
    /// task starts, after the window is up.
    struct SectionShape: View {

        // MARK: - Stored properties

        let ledger: Ledger
        let runner: ScriptRunner
        let takesTheCancelKeys: Bool
        let stopQuestion: StopQuestion?
        let settings: AppSettings

        // MARK: - Computed properties

        var body: some View {
            NavigationSplitView {
                List {
                    Text("EXC2O")
                    Text("Section 1")
                }
            } detail: {
                VStack(alignment: .leading) {
                    TextField("Filter", text: textBinding)
                        .frame(width: 200)
                        .onExitCommand {
                            ledger.fieldEscapeCount += 1
                            ledger.text = ""
                        }
                    if ledger.showsRename {
                        TextField("Rename", text: renameBinding)
                            .frame(width: 200)
                    }
                    if ledger.showsNotes {
                        TextEditor(text: notesBinding)
                            .frame(width: 200, height: 40)
                    }
                    if ledger.showsPanel {
                        TaskProgressView(
                            runner: runner,
                            title: stopQuestion == nil ? "Previewing EXC2O Section 1" : "Deploying EXC2O Section 1",
                            showingDetailsForTesting: ledger.showsDetails,
                            takesTheCancelKeys: takesTheCancelKeys,
                            stopQuestion: stopQuestion,
                            settings: settings,
                            onCancel: {
                                ledger.cancelCount += 1
                            }
                        )
                    }
                    Spacer()
                }
                .padding()
            }
            .frame(width: 900, height: 500)
            .sheet(isPresented: sheetBinding) {
                VStack {
                    Text("A question")
                    if ledger.sheetHoldsEscape {
                        Button("Cancel", role: .cancel) {
                            ledger.sheetCancelCount += 1
                            ledger.showsSheet = false
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                }
                .frame(width: 300, height: 120)
            }
            .alert("A question?", isPresented: alertBinding) {
                Button("Cancel", role: .cancel) {
                    ledger.alertCancelCount += 1
                }
                .keyboardShortcut(.cancelAction)
            }
        }

        var textBinding: Binding<String> {
            return Binding(get: { ledger.text }, set: { (value: String) in ledger.text = value })
        }

        var renameBinding: Binding<String> {
            return Binding(get: { ledger.renameText }, set: { (value: String) in ledger.renameText = value })
        }

        var notesBinding: Binding<String> {
            return Binding(get: { ledger.notes }, set: { (value: String) in ledger.notes = value })
        }

        var sheetBinding: Binding<Bool> {
            return Binding(get: { ledger.showsSheet }, set: { (value: Bool) in ledger.showsSheet = value })
        }

        var alertBinding: Binding<Bool> {
            return Binding(get: { ledger.showsAlert }, set: { (value: Bool) in ledger.showsAlert = value })
        }
    }

    // MARK: - Stored properties

    var openWindows: [NSWindow] = []

    /// This test's own settings, so a ticked "Don't ask again" never
    /// reaches the teacher's preferences or another test.
    /// Made in `setUp`.
    var settings: AppSettings!

    /// The suite behind `settings`, removed when the test ends.
    var settingsSuiteName: String = ""

    // MARK: - Functions

    override func setUp() async throws {
        useThrowawayTrail(prefix: "progress-cancel-keys-trail")
        settingsSuiteName = "ProgressCancelKeysTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuiteName))
        settings = AppSettings(defaults: defaults)
    }

    override func tearDown() async throws {
        for window in openWindows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
            window.orderOut(nil)
            window.contentViewController = nil
        }
        openWindows = []
        UserDefaults.standard.removePersistentDomain(forName: settingsSuiteName)
        // The unit host is an accessory app with no Dock tile or menu bar
        // (#633); bringing it forward made it a regular one.
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func runUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end: Date = Date(timeIntervalSinceNow: timeout)
        while Date() < end {
            if condition() {
                return true
            }
            // Events are handed out as the app's own loop does, so an
            // activation and the window becoming key arrive while waiting
            // (a bare run loop leaves them queued until the test ends).
            if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.02), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        }
        return condition()
    }

    private func runUntilActive(timeout: TimeInterval) -> Bool {
        return runUntil(timeout: timeout) { NSApp.isActive }
    }

    /// Has the window's SwiftUI content apply what changed since it was
    /// last drawn, before the next key. The button reads a box being typed
    /// in itself when the key arrives, so this matters only for what SwiftUI
    /// hands it (`holdsTheCancelKeys`), such as a question that has closed.
    private func applyPendingViewUpdates(in window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private func settle(_ seconds: TimeInterval) {
        _ = runUntil(timeout: seconds) { false }
    }

    /// A runner that reads as a task in progress, as a preview's build does.
    func runningRunner() -> ScriptRunner {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.preview
        runner.isRunning = true
        return runner
    }

    /// The window, built as the app builds its own (a hosting controller as
    /// content), made the key window of the active app, with the panel
    /// appearing after it is up. Skips when the host cannot take the front.
    func keyWindow(ledger: Ledger, runner: ScriptRunner, takesTheCancelKeys: Bool = true, stopQuestion: StopQuestion? = nil, keepsAppKitsFocus: Bool = false) throws -> NSWindow {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: 900, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // These tests take the front from whatever the person at the Mac is
        // using, so they run only when asked (#988, 2026-11-19: a key typed
        // by the person while one runs would go to the test host).
        if ProcessInfo.processInfo.environment["PLANTOIR_KEY_TESTS"] != "1" {
            throw XCTSkip("Takes the front to press real keys; set PLANTOIR_KEY_TESTS=1 (TEST_RUNNER_PLANTOIR_KEY_TESTS=1 for xcodebuild) on a Mac nobody is using.")
        }
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SectionShape(
            ledger: ledger,
            runner: runner,
            takesTheCancelKeys: takesTheCancelKeys,
            stopQuestion: stopQuestion,
            settings: settings
        ))
        openWindows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.isActive {
            let application: AXUIElement = AXUIElementCreateApplication(getpid())
            AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        for _ in 1...2 where !NSApp.isActive {
            // Both refused (macOS's cooperative activation, with another
            // app in front, and no accessibility grant for this build):
            // asked through Launch Services, as the Dock asks. It names this
            // running host's own bundle, so it brings this copy forward and
            // opens no other. It also makes the host a regular app, which
            // `tearDown` undoes (`UnitTestHostWindowsTests`).
            let opener: Process = Process()
            opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            opener.arguments = [Bundle.main.bundleURL.path]
            try? opener.run()
            opener.waitUntilExit()
            _ = runUntilActive(timeout: 10)
        }
        window.makeKeyAndOrderFront(nil)
        if !runUntil(timeout: 5, { NSApp.isActive && window.isKeyWindow }) {
            window.makeKeyAndOrderFront(nil)
        }
        if !runUntil(timeout: 5, { NSApp.isActive && window.isKeyWindow }) {
            throw XCTSkip("The test host could not be made the active app with its window key (a locked screen, another Space or another account using the Mac, #315), so a key could not be pressed the way a teacher presses it.")
        }
        settle(0.5)
        // With Keyboard Navigation on, AppKit gives the Filter box the
        // focus when the window becomes key (measured on the main Mac):
        // the box then owns Escape, as it should. These tests start with
        // focus in no box, as after a click on the panel; the box's own
        // cases are `testEscapeInATextFieldIsTheFields` and
        // `testWithKeyboardNavigationOnTheFilterFieldHasEscapeFirst`.
        if !keepsAppKitsFocus {
            _ = window.makeFirstResponder(nil)
            if KeyWindowTextEditing.isEditingText(in: window) {
                XCTFail("focus left the Filter box but the window still reads it as being edited")
            }
        }
        ledger.showsPanel = true
        if !runUntil(timeout: 3, { cancelButton(in: window) != nil }) {
            XCTFail("the panel's Cancel was never drawn")
        }
        settle(0.3)
        return window
    }

    /// A key-down as the keyboard sends it, through `NSApp.sendEvent`, to
    /// whichever window is key.
    func press(_ key: Key, isARepeat: Bool = false) throws {
        guard let target = NSApp.keyWindow else {
            throw XCTSkip("No key window when the key was pressed: another app took the front midway (#846).")
        }
        NSApp.sendEvent(try keyEvent(key, in: target, isARepeat: isARepeat))
    }

    /// The key-down the keyboard sends for `key`, addressed to `target`.
    func keyEvent(_ key: Key, in target: NSWindow, isARepeat: Bool = false) throws -> NSEvent {
        let characters: String
        let code: UInt16
        var modifiers: NSEvent.ModifierFlags = []
        switch key {
        case .escape:
            characters = "\u{1b}"
            code = 53
        case .commandPeriod:
            characters = "."
            code = 47
            modifiers = [.command]
        case .returnKey:
            characters = "\r"
            code = 36
        }
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: target.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: isARepeat, keyCode: code
        ))
    }

    func findTextField(in view: NSView) -> NSTextField? {
        for child in view.subviews {
            if let field = child as? NSTextField, field.isEditable {
                return field
            }
            if let found = findTextField(in: child) {
                return found
            }
        }
        return nil
    }

    /// The panel's visible Cancel, an AppKit push button (`TaskCancelButton`).
    func cancelButton(in window: NSWindow) -> CancelKeyNSButton? {
        var queue: [NSView] = []
        if let contentView = window.contentView {
            queue.append(contentView)
        }
        while !queue.isEmpty {
            let view: NSView = queue.removeFirst()
            if let button = view as? CancelKeyNSButton {
                return button
            }
            for child in view.subviews {
                queue.append(child)
            }
        }
        return nil
    }

    /// The first editable text view under `view` that is not a field editor.
    func findTextView(in view: NSView) -> NSTextView? {
        for child in view.subviews {
            if let textView = child as? NSTextView, textView.isEditable, !textView.isFieldEditor {
                return textView
            }
            if let found = findTextView(in: child) {
                return found
            }
        }
        return nil
    }

    /// The editable text field whose placeholder is `placeholder`.
    func findTextField(placeholder: String, in view: NSView) -> NSTextField? {
        for child in view.subviews {
            if let field = child as? NSTextField, field.isEditable, field.placeholderString == placeholder {
                return field
            }
            if let found = findTextField(placeholder: placeholder, in: child) {
                return found
            }
        }
        return nil
    }

    /// A mouse-down and mouse-up at `point` (window coordinates), queued
    /// as the mouse queues them, handed out by the app's own event loop.
    func postClick(at point: NSPoint, in window: NSWindow, clickCount: Int = 1) throws {
        for eventType in [NSEvent.EventType.leftMouseDown, NSEvent.EventType.leftMouseUp] {
            let click: NSEvent = try XCTUnwrap(NSEvent.mouseEvent(
                with: eventType, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: clickCount, pressure: 1
            ))
            NSApp.postEvent(click, atStart: false)
        }
    }

    /// The middle of `view`, in its window's coordinates.
    func middle(of view: NSView) -> NSPoint {
        return view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    }

    /// Puts the focus in the Filter field and waits until it is being
    /// edited. Skips if another app takes the front meanwhile.
    func focusTheFilterField(in window: NSWindow) throws -> NSTextField {
        let contentView: NSView = try XCTUnwrap(window.contentView)
        let field: NSTextField = try XCTUnwrap(findTextField(in: contentView), "the Filter field")
        XCTAssertTrue(window.makeFirstResponder(field), "the field took focus")
        _ = runUntil(timeout: 3) { KeyWindowTextEditing.isEditingText(in: window) || !window.isKeyWindow }
        if !window.isKeyWindow {
            throw XCTSkip("Another app took the front while the field took focus (#846), so the window was no longer key.")
        }
        XCTAssertTrue(KeyWindowTextEditing.isEditingText(in: window), "the field is being edited")
        // SwiftUI learns that its field has the focus when it next updates
        // the view; until then the field's own Escape (`onExitCommand`) has
        // nothing to run (measured, run `988-n4`). A teacher cannot type
        // inside that gap.
        applyPendingViewUpdates(in: window)
        settle(0.2)
        return field
    }

    /// The AppKit buttons of the alert attached to `window`, by title.
    func alertButtons(in window: NSWindow) -> [String: NSButton] {
        var found: [String: NSButton] = [:]
        var queue: [NSView] = []
        if let contentView = window.attachedSheet?.contentView {
            queue.append(contentView)
        }
        while !queue.isEmpty {
            let view: NSView = queue.removeFirst()
            if let button = view as? NSButton, !button.title.isEmpty {
                found[button.title] = button
            }
            for child in view.subviews {
                queue.append(child)
            }
        }
        return found
    }

    // MARK: - Tests: a preview stops at once

    func checkTheKeyStopsAPreview(_ key: Key) throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner)
        XCTAssertFalse(window.firstResponder is NSText, "nothing is being typed in")
        try press(key)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "\(key) did not stop the running preview")
        settle(0.5)
        XCTAssertNil(window.attachedSheet, "a preview stops with no question")
        // Once pressed, the run's Cancel has gone, and its key with it.
        try press(key)
        settle(0.5)
        XCTAssertEqual(ledger.cancelCount, 1, "\(key): Cancel ran once, not again on a second press")
    }

    func testEscapeStopsARunningPreview() throws {
        try checkTheKeyStopsAPreview(.escape)
    }

    func testCommandPeriodStopsARunningPreview() throws {
        try checkTheKeyStopsAPreview(.commandPeriod)
    }

    /// A held key repeats faster than the panel redraws: Cancel still acts
    /// once per run.
    func testAHeldKeyStopsOnce() throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        _ = try keyWindow(ledger: ledger, runner: runner)
        try press(.escape)
        try press(.escape, isARepeat: true)
        try press(.escape, isARepeat: true)
        try press(.commandPeriod)
        settle(0.7)
        XCTAssertEqual(ledger.cancelCount, 1, "Cancel ran more than once for one run")
    }

    // MARK: - Tests: nothing fires while something else owns the key

    /// Typing in a box, Escape is the box's (the Filter field clears) and
    /// Command-Period is not the panel's either; the task keeps running.
    /// Measured failing on the first #988 shape, which held the key always.
    func testEscapeInATextFieldIsTheFields() throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner)
        // A window that is no longer key proves nothing about the keys (run
        // c4, 2026-11-19: another app took the front here).
        _ = try focusTheFilterField(in: window)
        try press(.escape)
        settle(0.7)
        XCTAssertEqual(ledger.cancelCount, 0, "Escape in the field stopped the running task")
        XCTAssertEqual(ledger.fieldEscapeCount, 1, "the field's own Escape ran")
        XCTAssertEqual(ledger.text, "", "Escape cleared the field")
        try press(.commandPeriod)
        settle(0.7)
        XCTAssertEqual(ledger.cancelCount, 0, "Command-Period in the field stopped the running task")
        // Focus leaves the field: the key is Cancel's again, at once.
        _ = window.makeFirstResponder(nil)
        XCTAssertFalse(KeyWindowTextEditing.isEditingText(in: window), "the editing ended")
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "Escape stops the task again once no box is being typed in")
    }

    /// What happens today with Keyboard Navigation on and no click yet
    /// (the fourth #988 review): AppKit gives the window's first text box
    /// the focus when the window becomes key (the app's own sidebar Filter
    /// field, `SidebarView`), so Escape is the box's and the running task
    /// keeps running until the teacher clicks somewhere else. Russell's
    /// ruling on #988 (2026-11-19, evening): left as built. While a box has
    /// the focus, Escape and Command-Period are both the box's; a click on
    /// Cancel still stops the task.
    func testWithKeyboardNavigationOnTheFilterFieldHasEscapeFirst() throws {
        if !NSApp.isFullKeyboardAccessEnabled {
            throw XCTSkip("Keyboard Navigation is off (System Settings > Keyboard), so AppKit gives no box the focus when the window becomes key.")
        }
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner, keepsAppKitsFocus: true)
        XCTAssertTrue(window.firstResponder is NSText, "with Keyboard Navigation on, the Filter box has the focus once the window is key")
        XCTAssertTrue(KeyWindowTextEditing.isEditingText(in: window), "the box reads as being typed in")
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.fieldEscapeCount == 1 }, "Escape went to the box")
        settle(0.3)
        XCTAssertEqual(ledger.cancelCount, 0, "Escape did not stop the task while the box had the focus")
        // A click elsewhere (focus in no box) gives the key back to Cancel.
        _ = window.makeFirstResponder(nil)
        XCTAssertFalse(KeyWindowTextEditing.isEditingText(in: window))
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "after the click, Escape stops the task")
    }

    /// The fastest a teacher's own input can come: a click in the Filter
    /// field and then a key, both already waiting in the event queue before
    /// the app handles either (the app busy for longer than the gap between
    /// them). Each event is handed out by the app's own event loop, as a
    /// real one is. Measured failing on the main Mac with a SwiftUI
    /// shortcut on Cancel (run `988-n2`, Keyboard Navigation on): SwiftUI
    /// had not yet taken the key off Cancel, and Escape stopped the task;
    /// with the press then refused afterwards (head 314a75dc0) Cancel still
    /// took the key off the box. Cancel now refuses the key when it
    /// arrives, so the task runs on and the box answers the key exactly as
    /// it does with no Cancel in the window.
    func checkAKeyRightAfterAClickInTheFieldStopsNothing(_ key: Key) throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner)
        let contentView: NSView = try XCTUnwrap(window.contentView)
        let field: NSTextField = try XCTUnwrap(findTextField(in: contentView), "the Filter field")
        XCTAssertFalse(window.firstResponder is NSText, "no box has the focus before the click")
        // What the box does with this queued click and key when no Cancel
        // is in the window at all, measured first in the same window: the
        // box's answer with the panel showing must be the same. (Measured,
        // run `988-n4`: SwiftUI's own field runs no `onExitCommand` for an
        // Escape queued straight behind the click that focused it, Cancel
        // or no Cancel, because SwiftUI learns of the focus only when it
        // next updates the view. That part is SwiftUI's, not Cancel's.)
        ledger.showsPanel = false
        XCTAssertTrue(runUntil(timeout: 3) { cancelButton(in: window) == nil }, "the panel went")
        try postClick(at: middle(of: field), in: window)
        NSApp.postEvent(try keyEvent(key, in: window), atStart: false)
        XCTAssertTrue(runUntil(timeout: 3) { window.firstResponder is NSText }, "the click put the focus in the field")
        settle(0.5)
        let escapesWithNoCancel: Int = ledger.fieldEscapeCount
        let textWithNoCancel: String = ledger.text
        _ = window.makeFirstResponder(nil)
        ledger.fieldEscapeCount = 0
        ledger.text = "abc"
        ledger.showsPanel = true
        XCTAssertTrue(runUntil(timeout: 3) { cancelButton(in: window) != nil }, "the panel is back")
        settle(0.3)
        XCTAssertFalse(window.firstResponder is NSText, "no box has the focus before the click")
        // Now with the panel: the same click and key, queued together.
        try postClick(at: middle(of: field), in: window)
        NSApp.postEvent(try keyEvent(key, in: window), atStart: false)
        XCTAssertTrue(runUntil(timeout: 3) { window.firstResponder is NSText }, "the click put the focus in the field")
        _ = runUntil(timeout: 1) { ledger.cancelCount > 0 }
        XCTAssertEqual(ledger.cancelCount, 0, "\(key) straight after a click in the field stopped the running task")
        XCTAssertEqual(ledger.fieldEscapeCount, escapesWithNoCancel, "the box answered the queued \(key) as it does with no Cancel in the window")
        XCTAssertEqual(ledger.text, textWithNoCancel, "the box's text is as it is with no Cancel in the window")
        // The next press is the box's as ever.
        if key == .escape {
            let before: Int = ledger.fieldEscapeCount
            applyPendingViewUpdates(in: window)
            settle(0.2)
            try press(.escape)
            XCTAssertTrue(runUntil(timeout: 3) { ledger.fieldEscapeCount == before + 1 }, "Escape again was the field's")
            XCTAssertEqual(ledger.cancelCount, 0)
        }
    }

    func testEscapeRightAfterAClickInTheFieldStopsNothing() throws {
        try checkAKeyRightAfterAClickInTheFieldStopsNothing(.escape)
    }

    func testCommandPeriodRightAfterAClickInTheFieldStopsNothing() throws {
        try checkAKeyRightAfterAClickInTheFieldStopsNothing(.commandPeriod)
    }

    /// A text view that has no use for Escape (it completes a word with it)
    /// keeps both keys while it is typed in; the task runs on. Restores the
    /// text-view case the first pressed-key shape had (99668b985 removed it
    /// with the responder route).
    func testNeitherKeyStopsATaskWhileATextViewIsTypedIn() throws {
        let ledger: Ledger = Ledger()
        ledger.showsNotes = true
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner)
        let contentView: NSView = try XCTUnwrap(window.contentView)
        let textView: NSTextView = try XCTUnwrap(findTextView(in: contentView), "the notes text view")
        XCTAssertTrue(window.makeFirstResponder(textView), "the text view took focus")
        XCTAssertTrue(KeyWindowTextEditing.isEditingText(in: window), "the text view reads as being typed in")
        try press(.escape)
        try press(.commandPeriod)
        settle(0.7)
        if !window.isKeyWindow {
            throw XCTSkip("Another app took the front midway (#846).")
        }
        XCTAssertEqual(ledger.cancelCount, 0, "a key typed in a text view stopped the running task")
        XCTAssertNil(window.attachedSheet)
        _ = window.makeFirstResponder(nil)
        try press(.commandPeriod)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "Command-Period stops the task once the text view lets go of the focus")
    }

    /// A field with no use for Escape hands it back up the responder chain
    /// to the window, which offers it to Cancel again: refused again, so the
    /// task runs on and nothing loops (the loop measured at head 314a75dc0's
    /// writer, who rejected passing the key on for that reason).
    func testEscapeInAFieldWithNoUseForItStopsNothing() throws {
        let ledger: Ledger = Ledger()
        ledger.showsRename = true
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner)
        let contentView: NSView = try XCTUnwrap(window.contentView)
        let field: NSTextField = try XCTUnwrap(findTextField(placeholder: "Rename", in: contentView), "the Rename field")
        XCTAssertTrue(window.makeFirstResponder(field), "the field took focus")
        XCTAssertTrue(runUntil(timeout: 3) { KeyWindowTextEditing.isEditingText(in: window) }, "the field is being edited")
        try press(.escape)
        try press(.commandPeriod)
        settle(0.7)
        if !window.isKeyWindow {
            throw XCTSkip("Another app took the front midway (#846).")
        }
        XCTAssertEqual(ledger.cancelCount, 0, "a key in a field with no use for it stopped the running task")
        XCTAssertEqual(ledger.renameText, "Section 1", "the field's text is as it was")
    }

    /// VoiceOver's VO-Space, Voice Control's "Click Cancel" and Switch
    /// Control press Cancel through accessibility, with no event of their
    /// own: while a box has the focus and the last event taken off the queue
    /// was a key typed in it, the press still stops the task. Measured
    /// failing at head 314a75dc0 (the fifth #988 review): the press read
    /// `NSApp.currentEvent`, took itself for that key, and stopped nothing.
    func testAnAccessibilityPressStopsTheTaskWhileABoxHasTheFocus() throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner)
        _ = try focusTheFilterField(in: window)
        let typed: NSEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: "x", charactersIgnoringModifiers: "x",
            isARepeat: false, keyCode: 7
        ))
        NSApp.postEvent(typed, atStart: false)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.text.hasSuffix("x") }, "the key was typed in the box")
        XCTAssertEqual(NSApp.currentEvent?.type, .keyDown, "the last event taken off the queue is the typed key")
        XCTAssertTrue(KeyWindowTextEditing.isEditingText(in: window), "the box still has the focus")
        let button: CancelKeyNSButton = try XCTUnwrap(cancelButton(in: window))
        // The push button's cell is its accessibility element (measured,
        // `testTheCancelButtonIsTheSizeAndKindOfTheOneItReplaced`).
        let element: NSCell = try XCTUnwrap(button.cell)
        XCTAssertEqual(element.accessibilityRole(), .button)
        // Its Bool answer was measured false although the press ran (run
        // `988-n4`), so the test reads what the press did, not the answer.
        _ = element.accessibilityPerformPress()
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "an accessibility press on Cancel did not stop the task while a box had the focus")
    }

    /// A real click on Cancel, through the event queue, stops the task while
    /// a box has the focus (Russell's ruling on #988, 2026-11-19 evening).
    func testAClickOnCancelStopsTheTaskWhileABoxHasTheFocus() throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner)
        _ = try focusTheFilterField(in: window)
        let button: CancelKeyNSButton = try XCTUnwrap(cancelButton(in: window))
        try postClick(at: middle(of: button), in: window)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "a click on Cancel did not stop the task while a box had the focus")
    }

    /// Clicking in the console to select some of its output does not count
    /// as typing in a box: the console's text is selectable, not editable,
    /// so Escape still stops the task (the fifth #988 review's low). Prints
    /// what the click made the first responder, for the record.
    func testSelectingConsoleTextLeavesTheKeysWithCancel() throws {
        let ledger: Ledger = Ledger()
        ledger.showsDetails = true
        let runner: ScriptRunner = runningRunner()
        runner.transcript.append(rawText: "Building EXC2O Section 1\nCopying the pages\nStill working\n")
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner)
        let contentView: NSView = try XCTUnwrap(window.contentView)
        var console: NSScrollView? = nil
        var queue: [NSView] = [contentView]
        while !queue.isEmpty {
            let view: NSView = queue.removeFirst()
            if let scrollView = view as? NSScrollView, middle(of: scrollView).x > 400 {
                console = scrollView
            }
            for child in view.subviews {
                queue.append(child)
            }
        }
        let consoleView: NSScrollView = try XCTUnwrap(console, "the console's scroll view")
        let frame: NSRect = consoleView.convert(consoleView.bounds, to: nil)
        // The first line of output, near the console's top leading corner.
        let onTheText: NSPoint = NSPoint(x: frame.minX + 40, y: frame.maxY - 20)
        try postClick(at: onTheText, in: window, clickCount: 2)
        settle(0.5)
        var responder: String = "none"
        if let shown = window.firstResponder {
            responder = String(describing: type(of: shown))
        }
        var responderIsEditable: String = "not text"
        if let text = window.firstResponder as? NSText {
            responderIsEditable = text.isEditable ? "editable" : "selectable only"
        }
        print("PROGRESS-CANCEL-KEYS console click: firstResponder=\(responder) (\(responderIsEditable)) Keyboard Navigation on: \(NSApp.isFullKeyboardAccessEnabled)")
        XCTAssertFalse(KeyWindowTextEditing.isEditingText(in: window), "selecting console text reads as typing in a box")
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "Escape did not stop the task after console text was selected")
    }

    /// A sheet in front: Escape is the sheet's, and a sheet that has no use
    /// for Escape does not pass it to the panel behind it either.
    func testNeitherKeyStopsATaskBehindASheet() throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner)
        ledger.showsSheet = true
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet?.isKeyWindow == true }, "the sheet is in front")
        settle(0.5)
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.sheetCancelCount == 1 }, "the sheet's Cancel took Escape")
        XCTAssertEqual(ledger.cancelCount, 0, "Escape in a sheet stopped the task behind it")
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil && window.isKeyWindow })
        settle(0.5)
        ledger.sheetHoldsEscape = false
        ledger.showsSheet = true
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet?.isKeyWindow == true }, "the second sheet is in front")
        settle(0.5)
        try press(.escape)
        try press(.commandPeriod)
        settle(0.7)
        XCTAssertEqual(ledger.cancelCount, 0, "a key in a sheet with no use for it stopped the task behind it")
    }

    /// An alert in front: Escape and Command-Period are its Cancel's.
    func testNeitherKeyStopsATaskBehindAnAlert() throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner)
        for key in [Key.escape, Key.commandPeriod] {
            ledger.showsAlert = true
            XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet?.isKeyWindow == true }, "the alert is in front")
            XCTAssertTrue(runUntil(timeout: 3) { alertButtons(in: window)["Cancel"] != nil }, "the alert's Cancel is drawn")
            try press(key)
            XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "\(key) closed the alert")
            XCTAssertTrue(runUntil(timeout: 3) { window.isKeyWindow }, "the window is key again")
        }
        XCTAssertEqual(ledger.alertCancelCount, 2, "the alert's Cancel took both keys")
        XCTAssertEqual(ledger.cancelCount, 0, "a key in an alert stopped the task behind it")
    }

    /// With the preview's site in front of the panel the keys are the web
    /// page's: they never stop the preview underneath.
    func testNeitherKeyStopsATaskWhoseSiteCoversThePanel() throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        _ = try keyWindow(ledger: ledger, runner: runner, takesTheCancelKeys: false)
        try press(.escape)
        try press(.commandPeriod)
        settle(0.7)
        XCTAssertEqual(ledger.cancelCount, 0, "a key stopped a preview whose site was in front of the panel")
    }

    // MARK: - Tests: a deploy asks first

    /// Escape or Command-Period on a running deploy asks "Stop the deploy?"
    /// and stops nothing. In the question, Escape and Command-Period are
    /// Cancel's and the deploy runs on; Return is Stop Deploy's, the plain
    /// default, and stops it once.
    func checkADeployAsksFirst(_ key: Key) throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner, stopQuestion: .deploy)
        try press(key)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet?.isKeyWindow == true }, "\(key) on a running deploy asked first")
        settle(0.5)
        XCTAssertEqual(ledger.cancelCount, 0, "\(key) stopped the deploy without asking")
        let shown: [String: NSButton] = alertButtons(in: window)
        let stopButton: NSButton = try XCTUnwrap(shown[DeployStopWording.stopButton], "the buttons: \(Array(shown.keys))")
        let cancelButton: NSButton = try XCTUnwrap(shown[DeployStopWording.cancelButton], "the buttons: \(Array(shown.keys))")
        XCTAssertEqual(stopButton.keyEquivalent, "\r", "Stop Deploy is the default")
        XCTAssertEqual(cancelButton.keyEquivalent, "\u{1b}", "Cancel holds Escape")
        XCTAssertNotEqual(stopButton.bezelColor, NSColor.systemRed, "Stop Deploy is not drawn red")
        try press(key)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "\(key) in the question chose Cancel")
        settle(0.7)
        XCTAssertEqual(ledger.cancelCount, 0, "Cancel in the question stopped the deploy")
        XCTAssertTrue(runUntil(timeout: 3) { window.isKeyWindow })
        try press(key)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet?.isKeyWindow == true }, "\(key) asked again")
        settle(0.5)
        try press(.returnKey)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "Return chose Stop Deploy and stopped the deploy")
        settle(0.7)
        try press(key)
        settle(0.7)
        XCTAssertNil(window.attachedSheet, "once stopped, the key asks nothing more")
        XCTAssertEqual(ledger.cancelCount, 1)
    }

    func testEscapeOnADeployAsksFirst() throws {
        try checkADeployAsksFirst(.escape)
    }

    func testCommandPeriodOnADeployAsksFirst() throws {
        try checkADeployAsksFirst(.commandPeriod)
    }

    /// A deploy that ends while its question is open has nothing to stop:
    /// the question goes, and nothing is stopped.
    func testTheQuestionGoesWhenTheDeployEnds() throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner, stopQuestion: .deploy)
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet != nil }, "Escape asked first")
        runner.isRunning = false
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "the question went when the deploy ended")
        XCTAssertEqual(ledger.cancelCount, 0)
    }

    // MARK: - Tests: "Don't ask again" and a question turned off

    /// The suppression box in the question attached to `window`.
    func dontAskAgainBox(in window: NSWindow) throws -> NSButton {
        let shown: [String: NSButton] = alertButtons(in: window)
        return try XCTUnwrap(shown[StopQuestionSettingsWording.dontAskAgain], "the question's box; the buttons: \(Array(shown.keys))")
    }

    /// Ticked, then Stop Deploy: the deploy's question is off from then on,
    /// and the share's is still on. Measured failing before ruling 2 was
    /// built: the question had no box.
    func testTheTickWithStopIsRemembered() throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner, stopQuestion: .deploy)
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet?.isKeyWindow == true }, "Escape asked first")
        settle(0.5)
        let box: NSButton = try dontAskAgainBox(in: window)
        XCTAssertEqual(box.state, .off, "the box starts unticked")
        box.performClick(nil)
        settle(0.3)
        XCTAssertEqual(box.state, .on)
        try press(.returnKey)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "Stop Deploy stopped the deploy")
        XCTAssertFalse(settings.asksBeforeStoppingADeploy, "the tick with Stop Deploy turned the deploy's question off")
        XCTAssertTrue(settings.asksBeforeStoppingAShare, "the share's question is its own setting")
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(StopQuestion.trailLine(for: .deploy, asked: false, from: .dontAskAgain)), trail)
    }

    /// Ticked, then Cancel: nothing is remembered, and the next press asks
    /// again with the box unticked (ruling 3).
    func testTheTickWithCancelIsNotRemembered() throws {
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner, stopQuestion: .deploy)
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet?.isKeyWindow == true }, "Escape asked first")
        settle(0.5)
        try dontAskAgainBox(in: window).performClick(nil)
        settle(0.3)
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "Escape in the question chose Cancel")
        settle(0.5)
        XCTAssertEqual(ledger.cancelCount, 0, "Cancel stopped nothing")
        XCTAssertTrue(settings.asksBeforeStoppingADeploy, "the tick with Cancel was remembered")
        XCTAssertTrue(runUntil(timeout: 3) { window.isKeyWindow })
        try press(.commandPeriod)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet?.isKeyWindow == true }, "the question is asked again")
        settle(0.5)
        XCTAssertEqual(try dontAskAgainBox(in: window).state, .off, "the box is unticked again")
    }

    /// With a question off, Cancel's keys stop that task at once, as a
    /// preview's do: no question, once per run.
    func checkTheKeyStopsAtOnceWhenOff(_ key: Key, question: StopQuestion) throws {
        question.setAsked(false, in: settings, from: .settings)
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner, stopQuestion: question)
        try press(key)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "\(key) did not stop the task at once with \(question) off")
        settle(0.5)
        XCTAssertNil(window.attachedSheet, "nothing was asked")
        try press(key)
        settle(0.5)
        XCTAssertEqual(ledger.cancelCount, 1, "once per run")
    }

    func testEscapeStopsADeployAtOnceWhenItsQuestionIsOff() throws {
        try checkTheKeyStopsAtOnceWhenOff(.escape, question: .deploy)
    }

    func testCommandPeriodStopsAShareAtOnceWhenItsQuestionIsOff() throws {
        try checkTheKeyStopsAtOnceWhenOff(.commandPeriod, question: .share)
    }

    /// The deploy's question off leaves the share's asking: Escape on a
    /// share asks "Stop this share?", Return is Stop Share's.
    func testAShareStillAsksWithTheDeploysQuestionOff() throws {
        StopQuestion.deploy.setAsked(false, in: settings, from: .settings)
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner, stopQuestion: .share)
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet?.isKeyWindow == true }, "Escape on a share asked first")
        settle(0.5)
        XCTAssertEqual(ledger.cancelCount, 0)
        let shown: [String: NSButton] = alertButtons(in: window)
        let stopButton: NSButton = try XCTUnwrap(shown[ShareStopWording.stopButton], "the buttons: \(Array(shown.keys))")
        XCTAssertEqual(stopButton.keyEquivalent, "\r", "Stop Share is the default")
        XCTAssertNotEqual(stopButton.bezelColor, NSColor.systemRed, "Stop Share is not drawn red")
        XCTAssertNil(shown[DeployStopWording.stopButton], "the share's question, not the deploy's")
        try press(.returnKey)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "Return chose Stop Share")
        XCTAssertTrue(settings.asksBeforeStoppingAShare, "an unticked box changed nothing")
    }

    // MARK: - Tests: the rule and the source

    /// Every case of the rule the visible Cancel's key follows.
    func testCancelHoldsTheKeysOnlyWhenNothingElseWantsThem() {
        XCTAssertTrue(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: true, runIsUnderWay: true, isAskingToStop: false, windowIsKey: true))
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: false, cancelIsShowing: true, runIsUnderWay: true, isAskingToStop: false, windowIsKey: true), "a site covers the panel")
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: false, runIsUnderWay: true, isAskingToStop: false, windowIsKey: true), "Cancel is not showing")
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: true, runIsUnderWay: false, isAskingToStop: false, windowIsKey: true), "nothing is running")
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: true, runIsUnderWay: true, isAskingToStop: true, windowIsKey: true), "the question is open")
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: true, runIsUnderWay: true, isAskingToStop: false, windowIsKey: false), "something else is in front")
    }

    /// The button's own rule, read when a key arrives: it takes a cancel
    /// key only while it holds the keys, its window is key, and no text is
    /// being edited there.
    func testCancelTakesAKeyOnlyWhenNoBoxIsBeingTypedIn() {
        XCTAssertTrue(CancelKeyNSButton.takesTheCancelKey(holdsTheCancelKeys: true, windowIsKey: true, textIsBeingEdited: false))
        XCTAssertFalse(CancelKeyNSButton.takesTheCancelKey(holdsTheCancelKeys: true, windowIsKey: true, textIsBeingEdited: true), "a box is being typed in")
        XCTAssertFalse(CancelKeyNSButton.takesTheCancelKey(holdsTheCancelKeys: false, windowIsKey: true, textIsBeingEdited: false), "the panel does not hold the keys")
        XCTAssertFalse(CancelKeyNSButton.takesTheCancelKey(holdsTheCancelKeys: true, windowIsKey: false, textIsBeingEdited: false), "the window is not key")
    }

    /// The keys the button answers: Escape, and Command-Period; not Period,
    /// not Option-Escape, not Return.
    func testTheCancelKeysAreEscapeAndCommandPeriod() throws {
        func key(_ characters: String, _ code: UInt16, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            return try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
            ))
        }
        XCTAssertTrue(CancelKeyNSButton.isACancelKey(try key("\u{1b}", 53, [])))
        XCTAssertTrue(CancelKeyNSButton.isACancelKey(try key(".", 47, [.command])))
        XCTAssertFalse(CancelKeyNSButton.isACancelKey(try key(".", 47, [])), "Period alone")
        XCTAssertFalse(CancelKeyNSButton.isACancelKey(try key(".", 47, [.command, .shift])), "Shift-Command-Period")
        XCTAssertFalse(CancelKeyNSButton.isACancelKey(try key("\u{1b}", 53, [.option])), "Option-Escape")
        XCTAssertFalse(CancelKeyNSButton.isACancelKey(try key("\r", 36, [])), "Return")
    }

    /// Only editable text is a box: selectable text (the console's output)
    /// is not, an editable text view is, and nothing focused is not. No
    /// front needed: the first responder of a window that is not key.
    func testOnlyEditableTextIsABox() throws {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        openWindows.append(window)
        let textView: NSTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView?.addSubview(textView)
        XCTAssertFalse(KeyWindowTextEditing.isEditingText(in: window), "nothing has the focus")
        XCTAssertFalse(KeyWindowTextEditing.isEditingText(in: nil), "no window")
        textView.isEditable = false
        textView.isSelectable = true
        XCTAssertTrue(window.makeFirstResponder(textView))
        XCTAssertFalse(KeyWindowTextEditing.isEditingText(in: window), "selectable text is not a box")
        textView.isEditable = true
        XCTAssertTrue(KeyWindowTextEditing.isEditingText(in: window), "an editable text view is a box")
    }

    /// The visible Cancel looks as the SwiftUI `.bordered` Cancel it
    /// replaced: a regular push button of the same size, titled Cancel to
    /// VoiceOver, with Escape shown as its key only while it holds the keys,
    /// and able to take the focus with Keyboard Navigation on.
    func testTheCancelButtonIsTheSizeAndKindOfTheOneItReplaced() throws {
        let swiftUIButton: NSView = NSHostingView(rootView: Button("Cancel") {}.buttonStyle(.bordered))
        let appKitButton: NSView = NSHostingView(rootView: TaskCancelButton(
            title: "Cancel", accessibilityIdentifier: "taskCancelButton", holdsTheCancelKeys: true, action: {}
        ))
        let wanted: NSSize = swiftUIButton.fittingSize
        let drawn: NSSize = appKitButton.fittingSize
        print("PROGRESS-CANCEL-KEYS Cancel size: SwiftUI .bordered \(wanted), TaskCancelButton \(drawn)")
        XCTAssertEqual(drawn.width, wanted.width, accuracy: 1, "the same width")
        XCTAssertEqual(drawn.height, wanted.height, accuracy: 1, "the same height")
        appKitButton.layoutSubtreeIfNeeded()
        var hosted: CancelKeyNSButton? = nil
        var queue: [NSView] = [appKitButton]
        while !queue.isEmpty {
            let view: NSView = queue.removeFirst()
            if let found = view as? CancelKeyNSButton {
                hosted = found
            }
            for child in view.subviews {
                queue.append(child)
            }
        }
        let button: CancelKeyNSButton = try XCTUnwrap(hosted, "the push button is in the view")
        XCTAssertEqual(button.bezelStyle, .push, "a push button, as SwiftUI's .bordered draws on the Mac")
        XCTAssertEqual(button.controlSize, .regular)
        XCTAssertFalse(button.isHidden)
        XCTAssertEqual(button.alphaValue, 1)
        // AppKit makes a push button's CELL the accessibility element
        // (measured: the NSButton itself reads AXUnknown and is not an
        // element; its cell is AXButton), so the cell is what VoiceOver
        // reads and what AXPress is performed on.
        let element: NSCell = try XCTUnwrap(button.cell)
        print("PROGRESS-CANCEL-KEYS Cancel accessibility: role=\(String(describing: element.accessibilityRole())) title=\(String(describing: element.accessibilityTitle())) element=\(element.isAccessibilityElement())")
        // No `keyEquivalent`: the button takes its keys only through
        // `performKeyEquivalent`, one route, decided when the key arrives.
        XCTAssertEqual(button.keyEquivalent, "", "the keys are decided in performKeyEquivalent alone")
        XCTAssertTrue(element.isAccessibilityElement(), "Cancel is an accessibility element")
        XCTAssertEqual(element.accessibilityRole(), .button)
        XCTAssertEqual(element.accessibilityTitle(), "Cancel", "VoiceOver reads it as Cancel")
        XCTAssertTrue(button.acceptsFirstResponder || !NSApp.isFullKeyboardAccessEnabled, "with Keyboard Navigation on, Cancel can take the focus")
    }

    /// The key is on the visible Cancel, and nothing in the console is a
    /// hidden key catcher: Russell's rule, no invisible controls. The one
    /// AppKit view there is the visible Cancel itself, a push button with a
    /// title; nothing watches the event stream, adds a responder of its own,
    /// or hides a view.
    func testTheKeyIsOnTheVisibleCancel() throws {
        let consoleURL: URL = TextFieldStyleScanTests.viewsURL().appendingPathComponent("Console")
        let panel: String = try String(contentsOf: consoleURL.appendingPathComponent("TaskProgressView.swift"), encoding: .utf8)
        var found: Bool = false
        for chain in SheetConventionScanTests.chains(of: "TaskCancelButton(", in: panel, file: "TaskProgressView.swift") {
            if chain.arguments.contains("title: \"Cancel\"") && chain.arguments.contains("holdsTheCancelKeys: cancelKeysAreLive") && chain.arguments.contains("taskCancelButton") {
                found = true
            }
        }
        XCTAssertTrue(found, "the panel's visible Cancel holds the cancel keys while they are live")
        var representables: [String] = []
        for file in UserFacingLabelWordsTests.swiftFiles(under: consoleURL) {
            let code: String = TextFieldStyleScanTests.codeWithoutComments(try String(contentsOf: file, encoding: .utf8))
            if code.contains("NSViewRepresentable") {
                representables.append(file.lastPathComponent)
            }
            XCTAssertFalse(code.contains(": NSResponder"), "\(file.lastPathComponent) adds a responder")
            XCTAssertFalse(code.contains("addLocalMonitorForEvents"), "\(file.lastPathComponent) watches the keys")
            XCTAssertFalse(code.contains("addGlobalMonitorForEvents"), "\(file.lastPathComponent) watches the keys")
            XCTAssertFalse(code.contains("isHidden = true"), "\(file.lastPathComponent) hides a view")
            XCTAssertFalse(code.contains("alphaValue = 0"), "\(file.lastPathComponent) hides a view")
            XCTAssertFalse(code.contains("NSApp.currentEvent"), "\(file.lastPathComponent) guesses what pressed a button")
        }
        XCTAssertEqual(representables, ["TaskCancelButton.swift"], "the only AppKit view in the console is the visible Cancel")
        let button: String = TextFieldStyleScanTests.codeWithoutComments(try String(contentsOf: consoleURL.appendingPathComponent("TaskCancelButton.swift"), encoding: .utf8))
        XCTAssertTrue(button.contains("final class CancelKeyNSButton: NSButton"), "the representable is a button")
        XCTAssertTrue(button.contains("button.title = title"), "with a title a person sees")
    }

    /// A new run of the same runner can be cancelled again.
    func testANewRunCanBeCancelledAgain() {
        let once: CancelOncePerRun = CancelOncePerRun()
        let first: Date = Date(timeIntervalSince1970: 100)
        let second: Date = Date(timeIntervalSince1970: 200)
        XCTAssertTrue(once.pressOnce(forRunStartedAt: first))
        XCTAssertFalse(once.pressOnce(forRunStartedAt: first))
        XCTAssertTrue(once.pressOnce(forRunStartedAt: second))
    }

    /// The section window gives the panel the keys only while no site
    /// covers it.
    func testTheSectionWindowGivesTheKeysOnlyWhileNoSiteIsShowing() {
        XCTAssertTrue(SectionDetailView.progressPanelTakesTheCancelKeys(previewIsShowing: false))
        XCTAssertFalse(SectionDetailView.progressPanelTakesTheCancelKeys(previewIsShowing: true))
    }

    /// The question's words, as ruled.
    func testTheQuestionSaysWhatWasRuled() {
        XCTAssertEqual(DeployStopWording.title, "Stop the deploy?")
        XCTAssertEqual(DeployStopWording.stopButton, "Stop Deploy")
        XCTAssertEqual(DeployStopWording.cancelButton, "Cancel")
        XCTAssertTrue(DeployStopWording.message.contains("partly updated"))
    }

    /// The section window's deploy panel asks; its preview panel does not.
    func testTheSectionWindowAsksOnlyForTheDeploy() throws {
        let source: String = try String(contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent("Section/SectionDetailView.swift"), encoding: .utf8)
        var asking: Int = 0
        for chain in SheetConventionScanTests.chains(of: "TaskProgressView(", in: source, file: "SectionDetailView.swift") {
            if chain.arguments.contains("stopQuestion:") {
                XCTAssertTrue(chain.arguments.contains("stopQuestion: .deploy"), "the section window asks the deploy's question")
                asking += 1
                XCTAssertTrue(chain.arguments.contains("cancelDeploy()"), "the panel that asks is the deploy's")
            }
        }
        XCTAssertEqual(asking, 1, "exactly the deploy's panel asks first")
    }

    /// A plan share asks "Stop this share?", and its Cancel holds the stop
    /// keys as the deploy's does (Russell, 2026-11-19, ruling 1).
    func testAShareAsksAndItsCancelHoldsTheKeys() throws {
        let source: String = try String(contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent("Planning/PlanShareConsoleSheet.swift"), encoding: .utf8)
        var panels: Int = 0
        for chain in SheetConventionScanTests.chains(of: "TaskProgressView(", in: source, file: "PlanShareConsoleSheet.swift") {
            panels += 1
            XCTAssertTrue(chain.arguments.contains("stopQuestion: .share"), "the share asks its own question")
            XCTAssertFalse(chain.arguments.contains("takesTheCancelKeys: false"), "the share's Cancel holds the keys")
        }
        XCTAssertEqual(panels, 1)
    }

    /// What the app's own windows are made of, so the window above is the
    /// same shape: content from a hosting controller.
    func testTheAppsWindowsAreTheShapeTheseTestsUse() throws {
        guard let window = WorkspaceModel.windowModels.first?.window else {
            throw XCTSkip("No app window is registered in this run")
        }
        var controller: String = "none"
        if let shownController = window.contentViewController {
            controller = String(describing: type(of: shownController))
        }
        var content: String = "none"
        if let shownContent = window.contentView {
            content = String(describing: type(of: shownContent))
        }
        print("PROGRESS-CANCEL-KEYS app window: controller=\(controller.prefix(80)) content=\(content.prefix(80))")
        print("PROGRESS-CANCEL-KEYS Keyboard Navigation on: \(NSApp.isFullKeyboardAccessEnabled)")
        XCTAssertNotNil(window.contentViewController, "the app's window has a content view controller")
    }
}
