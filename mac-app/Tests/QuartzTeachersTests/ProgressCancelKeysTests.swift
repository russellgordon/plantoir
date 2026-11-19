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
/// web page's, and must not stop the preview underneath it.
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
    func press(_ key: Key, in window: NSWindow) {
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
            isARepeat: false, keyCode: code
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
        // Pressed again once the task is stopping, nothing more runs: the
        // Cancel button has gone, and its key with it.
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

    /// The section window gives the panel the keys only while no site
    /// covers it.
    func testTheSectionWindowGivesTheKeysOnlyWhileNoSiteIsShowing() {
        XCTAssertTrue(SectionDetailView.progressPanelTakesTheCancelKeys(previewIsShowing: false))
        XCTAssertFalse(SectionDetailView.progressPanelTakesTheCancelKeys(previewIsShowing: true))
    }
}
