import AppKit
import Observation
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Escape and Command-Period stop a running preview or deploy (#988, the
/// HIG review's finding D6), pressed for real: the progress panel is drawn
/// in an `NSWindow` that is never put on the screen, a key-down is sent to
/// that window, and the test reads whether the panel's Cancel ran.
///
/// Keyboards, https://developer.apple.com/design/human-interface-guidelines/keyboards:
/// "Esc: Cancel the current action or process"; "Command-Period: Cancel an
/// operation." Progress indicators: "When it's feasible, let people halt
/// processing."
///
/// Measured failing before #988: the panel's Cancel carried no key, so both
/// keys reached nothing and `cancelCount` stayed 0.
///
/// The keys belong to the panel only while it is the thing in front. Once a
/// preview's site covers the panel (`takesTheCancelKeys` false), Escape is the
/// web page's, and must not stop the preview underneath it. And they follow
/// focus (#988 review): typed in a text field in the same window, Escape is
/// the field's (the Filter field clears, a rename backs out) and the task
/// keeps running. Measured failing on the first #988 shape
/// (`.keyboardShortcut(.cancelAction)` on Cancel): the panel took Escape and
/// the field's `.onExitCommand` never ran.
@MainActor
final class ProgressCancelKeysTests: XCTestCase {

    // MARK: - Types

    /// The keys a test sends.
    enum Key {
        case escape
        case commandPeriod
    }

    /// How many times the panel's Cancel ran.
    @Observable
    final class CancelLedger {

        // MARK: - Stored properties

        var cancelCount: Int = 0
    }

    // MARK: - Functions

    override func setUp() async throws {
        useThrowawayTrail(prefix: "progress-cancel-keys-trail")
    }

    private func runUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end: Date = Date(timeIntervalSinceNow: timeout)
        while Date() < end {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }

    /// A runner that reads as a task in progress, as a preview's build does.
    func runningRunner() -> ScriptRunner {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.preview
        runner.isRunning = true
        return runner
    }

    /// A window off the screen holding the progress panel, settled.
    func windowShowing(_ view: some View) -> NSWindow {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: 700, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        // The keys are given out once the view has first appeared.
        _ = runUntil(timeout: 0.7) { false }
        return window
    }

    func close(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Sends `key` to the window as AppKit delivers a key-down: offered as a
    /// key equivalent first, then sent as an event.
    func press(_ key: Key, in window: NSWindow, isARepeat: Bool = false) {
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
        }
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: isARepeat, keyCode: code
        ) else {
            XCTFail("could not make the key")
            return
        }
        if !window.performKeyEquivalent(with: event) {
            window.sendEvent(event)
        }
    }

    /// The panel as the section window draws it for a running task.
    func panel(runner: ScriptRunner, ledger: CancelLedger, takesTheCancelKeys: Bool) -> some View {
        return TaskProgressView(
            runner: runner,
            title: "Previewing EXC2O Section 1",
            takesTheCancelKeys: takesTheCancelKeys,
            onCancel: {
                ledger.cancelCount += 1
                runner.wasCancelled = true
            }
        )
        .frame(width: 700, height: 400)
    }

    func checkTheKeyCancels(_ key: Key, what: String) {
        let runner: ScriptRunner = runningRunner()
        let ledger: CancelLedger = CancelLedger()
        let window: NSWindow = windowShowing(panel(runner: runner, ledger: ledger, takesTheCancelKeys: true))
        press(key, in: window)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount > 0 }, "\(what) did not stop the running task")
        // Pressed again once the task is stopping and the panel has redrawn,
        // nothing more runs: the Cancel button has gone, and its key with it.
        // (Pressed before the redraw, the key still reaches the button, as a
        // second click would; measured on the main Mac, 2026-11-19.)
        _ = runUntil(timeout: 0.7) { false }
        press(key, in: window)
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(ledger.cancelCount, 1, "\(what): Cancel ran once, not again on a second press")
        close(window)
    }

    func testEscapeStopsARunningTask() {
        checkTheKeyCancels(.escape, what: "Escape")
    }

    func testCommandPeriodStopsARunningTask() {
        checkTheKeyCancels(.commandPeriod, what: "Command-Period")
    }

    /// With the preview's site in front of the panel, Escape and
    /// Command-Period are not the panel's: a teacher pressing Escape on a
    /// web page must not stop the preview they are looking at. The same
    /// panel with the keys given (above) proves the press reaches it.
    func testNeitherKeyStopsATaskWhoseSiteCoversThePanel() {
        for key in [Key.escape, Key.commandPeriod] {
            let runner: ScriptRunner = runningRunner()
            let ledger: CancelLedger = CancelLedger()
            let window: NSWindow = windowShowing(panel(runner: runner, ledger: ledger, takesTheCancelKeys: false))
            press(key, in: window)
            _ = runUntil(timeout: 0.7) { false }
            XCTAssertEqual(ledger.cancelCount, 0, "\(key) stopped a preview whose site was in front of the panel")
            close(window)
        }
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

    /// What a field beside the panel did with Escape.
    @Observable
    final class FieldLedger {

        // MARK: - Stored properties

        var text: String = "abc"
        var isRenaming: Bool = true
        var backedOutCount: Int = 0
    }

    /// A field beside the running panel, focused, as the sidebar's Filter
    /// field (Escape clears it) or the course Rename field (Escape backs out
    /// of the rename, `SidebarView`'s `.onExitCommand`) sits in the window
    /// while a deploy runs. Stand-ins with the same mechanism, not the
    /// sidebar itself.
    func checkEscapeIsTheField(clearsText: Bool, what: String) {
        let runner: ScriptRunner = runningRunner()
        let ledger: CancelLedger = CancelLedger()
        let field: FieldLedger = FieldLedger()
        let binding: Binding<String> = Binding(
            get: { field.text },
            set: { (value: String) in field.text = value }
        )
        let view = VStack {
            TextField(what, text: binding)
                .frame(width: 200)
                .onExitCommand {
                    field.backedOutCount += 1
                    if clearsText {
                        field.text = ""
                    } else {
                        field.isRenaming = false
                    }
                }
            panel(runner: runner, ledger: ledger, takesTheCancelKeys: true)
        }
        let window: NSWindow = windowShowing(view)
        guard let contentView = window.contentView, let textField = findTextField(in: contentView) else {
            XCTFail("\(what): no field")
            close(window)
            return
        }
        XCTAssertTrue(window.makeFirstResponder(textField), "\(what): the field took focus")
        _ = runUntil(timeout: 0.3) { false }
        XCTAssertTrue(window.firstResponder is NSText, "\(what): the field is being edited")
        press(.escape, in: window)
        _ = runUntil(timeout: 0.7) { false }
        XCTAssertEqual(ledger.cancelCount, 0, "\(what): Escape in the field stopped the running task")
        XCTAssertTrue(runner.isRunning && !runner.wasCancelled, "\(what): the task keeps running")
        XCTAssertEqual(field.backedOutCount, 1, "\(what): the field's own Escape ran")
        if clearsText {
            XCTAssertEqual(field.text, "", "\(what): Escape cleared the field")
        } else {
            XCTAssertFalse(field.isRenaming, "\(what): Escape backed out of the rename")
        }
        // Command-Period in the field is not the panel's either.
        if !clearsText {
            press(.commandPeriod, in: window)
            _ = runUntil(timeout: 0.5) { false }
            XCTAssertEqual(ledger.cancelCount, 0, "\(what): Command-Period in the field stopped the running task")
        }
        close(window)
    }

    func testEscapeInTheFilterFieldClearsItAndTheTaskKeepsRunning() {
        checkEscapeIsTheField(clearsText: true, what: "Filter")
    }

    func testEscapeInTheRenameFieldBacksOutAndTheTaskKeepsRunning() {
        checkEscapeIsTheField(clearsText: false, what: "Rename")
    }

    /// With focus on the panel itself (its hosting view the first
    /// responder), Escape stops the task.
    func testEscapeWithFocusOnThePanelStopsTheTask() {
        let runner: ScriptRunner = runningRunner()
        let ledger: CancelLedger = CancelLedger()
        let window: NSWindow = windowShowing(panel(runner: runner, ledger: ledger, takesTheCancelKeys: true))
        if let contentView = window.contentView {
            _ = window.makeFirstResponder(contentView)
        }
        XCTAssertFalse(window.firstResponder is NSText)
        press(.escape, in: window)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "Escape with focus on the panel did not stop the task")
        close(window)
    }

    /// A held key repeats faster than the panel redraws, and a plan share's
    /// cancel never sets `wasCancelled`: Cancel still acts once per run.
    func testAHeldKeyCancelsOnceEvenWhenTheRunnerIsNotMarkedCancelled() {
        let runner: ScriptRunner = runningRunner()
        let ledger: CancelLedger = CancelLedger()
        let view = TaskProgressView(
            runner: runner,
            title: "Sharing",
            onCancel: {
                ledger.cancelCount += 1
            }
        )
        .frame(width: 700, height: 400)
        let window: NSWindow = windowShowing(view)
        press(.escape, in: window)
        press(.escape, in: window, isARepeat: true)
        press(.escape, in: window, isARepeat: true)
        press(.escape, in: window)
        _ = runUntil(timeout: 0.7) { false }
        press(.escape, in: window)
        press(.commandPeriod, in: window)
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(ledger.cancelCount, 1, "Cancel ran more than once for one run")
        XCTAssertFalse(runner.wasCancelled, "the stand-in never marks the runner")
        close(window)
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
}
