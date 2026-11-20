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
/// **The visible Cancel holds the key** (`.keyboardShortcut(.cancelAction)`
/// while `TaskProgressView.cancelKeysAreLive`), and lets go of it while a box
/// is being typed in, while a sheet, an alert or a popover is in front, and
/// while a preview's site covers the panel. No invisible view, responder or
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
                    if ledger.showsPanel {
                        TaskProgressView(
                            runner: runner,
                            title: stopQuestion == nil ? "Previewing EXC2O Section 1" : "Deploying EXC2O Section 1",
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
    /// last drawn, before the next key. The watch on the first responder
    /// flips at once, inside `makeFirstResponder`, but the panel's Cancel
    /// takes up or lets go of its key only when SwiftUI next updates the
    /// view, which waits for a turn of the run loop; a key sent before then
    /// meets the button as it was. Measured on the main Mac on 2026-11-19
    /// (`988-n2`, Keyboard Navigation on): pressed with no update between,
    /// Escape in the Filter field stopped the task, and Escape after focus
    /// left the box did nothing. A teacher cannot press a key inside that
    /// gap; the test could.
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
            if !runUntil(timeout: 3, { !KeyWindowTextEditing.shared.isEditingText }) {
                XCTFail("focus left the Filter box but the watch still read it as being edited")
            }
        }
        ledger.showsPanel = true
        // The panel's SwiftUI Cancel is not an AppKit view a test can wait
        // for, so this one wait stays timed.
        settle(0.7)
        return window
    }

    /// A key-down as the keyboard sends it, through `NSApp.sendEvent`, to
    /// whichever window is key.
    func press(_ key: Key, isARepeat: Bool = false) throws {
        guard let target = NSApp.keyWindow else {
            throw XCTSkip("No key window when the key was pressed: another app took the front midway (#846).")
        }
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
        let event: NSEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: target.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: isARepeat, keyCode: code
        ))
        NSApp.sendEvent(event)
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
        let contentView: NSView = try XCTUnwrap(window.contentView)
        let field: NSTextField = try XCTUnwrap(findTextField(in: contentView), "the Filter field")
        XCTAssertTrue(window.makeFirstResponder(field), "the field took focus")
        XCTAssertTrue(runUntil(timeout: 3) { window.firstResponder is NSText }, "the field is being edited")
        // The watch follows the KEY window, and reads false while none is
        // (run c4, 2026-11-19: another app took the front here, so the
        // window resigned key and the watch, rightly, saw no editing). A
        // window that is no longer key proves nothing about the keys.
        _ = runUntil(timeout: 3) { KeyWindowTextEditing.shared.isEditingText || !window.isKeyWindow }
        if !window.isKeyWindow {
            throw XCTSkip("Another app took the front while the field took focus (#846), so the window was no longer key.")
        }
        XCTAssertTrue(KeyWindowTextEditing.shared.isEditingText, "the watch saw the field being edited")
        applyPendingViewUpdates(in: window)
        try press(.escape)
        settle(0.7)
        XCTAssertEqual(ledger.cancelCount, 0, "Escape in the field stopped the running task")
        XCTAssertEqual(ledger.fieldEscapeCount, 1, "the field's own Escape ran")
        XCTAssertEqual(ledger.text, "", "Escape cleared the field")
        try press(.commandPeriod)
        settle(0.7)
        XCTAssertEqual(ledger.cancelCount, 0, "Command-Period in the field stopped the running task")
        // Focus leaves the field: the key is Cancel's again.
        _ = window.makeFirstResponder(nil)
        XCTAssertTrue(runUntil(timeout: 3) { !KeyWindowTextEditing.shared.isEditingText }, "the watch saw the editing end")
        applyPendingViewUpdates(in: window)
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "Escape stops the task again once no box is being typed in")
    }

    /// What happens today with Keyboard Navigation on and no click yet
    /// (the fourth #988 review): AppKit gives the window's first text box
    /// the focus when the window becomes key (the app's own sidebar Filter
    /// field, `SidebarView`), so Escape is the box's and the running task
    /// keeps running until the teacher clicks somewhere else. Russell's
    /// ruling on #988 (2026-11-19): it is left as it is; Command-Period and
    /// the Cancel button still stop the task.
    func testWithKeyboardNavigationOnTheFilterFieldHasEscapeFirst() throws {
        if !NSApp.isFullKeyboardAccessEnabled {
            throw XCTSkip("Keyboard Navigation is off (System Settings > Keyboard), so AppKit gives no box the focus when the window becomes key.")
        }
        let ledger: Ledger = Ledger()
        let runner: ScriptRunner = runningRunner()
        let window: NSWindow = try keyWindow(ledger: ledger, runner: runner, keepsAppKitsFocus: true)
        XCTAssertTrue(window.firstResponder is NSText, "with Keyboard Navigation on, the Filter box has the focus once the window is key")
        XCTAssertTrue(runUntil(timeout: 3) { KeyWindowTextEditing.shared.isEditingText }, "the watch reads the box as being typed in")
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.fieldEscapeCount == 1 }, "Escape went to the box")
        settle(0.3)
        XCTAssertEqual(ledger.cancelCount, 0, "Escape did not stop the task while the box had the focus")
        // A click elsewhere (focus in no box) gives the key back to Cancel.
        _ = window.makeFirstResponder(nil)
        XCTAssertTrue(runUntil(timeout: 3) { !KeyWindowTextEditing.shared.isEditingText })
        applyPendingViewUpdates(in: window)
        try press(.escape)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "after the click, Escape stops the task")
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
        XCTAssertTrue(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: true, runIsUnderWay: true, isAskingToStop: false, windowIsKey: true, textIsBeingEdited: false))
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: false, cancelIsShowing: true, runIsUnderWay: true, isAskingToStop: false, windowIsKey: true, textIsBeingEdited: false), "a site covers the panel")
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: false, runIsUnderWay: true, isAskingToStop: false, windowIsKey: true, textIsBeingEdited: false), "Cancel is not showing")
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: true, runIsUnderWay: false, isAskingToStop: false, windowIsKey: true, textIsBeingEdited: false), "nothing is running")
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: true, runIsUnderWay: true, isAskingToStop: true, windowIsKey: true, textIsBeingEdited: false), "the question is open")
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: true, runIsUnderWay: true, isAskingToStop: false, windowIsKey: false, textIsBeingEdited: false), "something else is in front")
        XCTAssertFalse(TaskProgressView.cancelHoldsTheKeys(takesTheCancelKeys: true, cancelIsShowing: true, runIsUnderWay: true, isAskingToStop: false, windowIsKey: true, textIsBeingEdited: true), "a box is being typed in")
    }

    /// The key is on the visible Cancel, and the console draws no helper
    /// view of its own (no representable, no responder): Russell's rule, no
    /// invisible controls.
    func testTheKeyIsOnTheVisibleCancel() throws {
        let consoleURL: URL = TextFieldStyleScanTests.viewsURL().appendingPathComponent("Console")
        let panel: String = try String(contentsOf: consoleURL.appendingPathComponent("TaskProgressView.swift"), encoding: .utf8)
        var found: Bool = false
        for chain in SheetConventionScanTests.chains(of: "Button(", in: panel, file: "TaskProgressView.swift") {
            if chain.arguments.hasPrefix("(\"Cancel\"") && chain.chain.contains(".keyboardShortcut(cancelKeysAreLive ? .cancelAction : nil)") && chain.chain.contains("taskCancelButton") {
                found = true
            }
        }
        XCTAssertTrue(found, "the panel's visible Cancel holds the cancel key while it is live")
        for file in UserFacingLabelWordsTests.swiftFiles(under: consoleURL) {
            let code: String = TextFieldStyleScanTests.codeWithoutComments(try String(contentsOf: file, encoding: .utf8))
            XCTAssertFalse(code.contains("NSViewRepresentable"), "\(file.lastPathComponent) draws a helper view")
            XCTAssertFalse(code.contains(": NSResponder"), "\(file.lastPathComponent) adds a responder")
        }
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
