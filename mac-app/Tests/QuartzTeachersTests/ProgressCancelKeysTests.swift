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
/// Since the second #988 review the keys reach Cancel as AppKit's
/// `cancelOperation(_:)` action, through the window's responder chain
/// (`CancelOperationResponder`, not a view), and a deploy asks "Stop the
/// deploy?" before it stops (Russell's ruling, 2026-11-19).
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
    func panel(runner: ScriptRunner, ledger: CancelLedger, takesTheCancelKeys: Bool, asksBeforeStopping: Bool = false) -> some View {
        return TaskProgressView(
            runner: runner,
            title: "Previewing EXC2O Section 1",
            takesTheCancelKeys: takesTheCancelKeys,
            asksBeforeStopping: asksBeforeStopping,
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

    // MARK: - The responder chain, not a view (#988 second review)

    /// The keys arrive through a responder in the window's chain, and that
    /// responder leaves the chain, joined up as it was, when the panel goes.
    func testTheKeysComeFromTheResponderChainAndLeaveWithThePanel() {
        let runner: ScriptRunner = runningRunner()
        let ledger: CancelLedger = CancelLedger()
        let shows: PanelShows = PanelShows()
        let view = VStack {
            if shows.panel {
                panel(runner: runner, ledger: ledger, takesTheCancelKeys: true)
            } else {
                Color.clear.frame(width: 700, height: 400)
            }
        }
        let window: NSWindow = windowShowing(view)
        XCTAssertTrue(ProgressCancelKeysTests.chainHoldsAResponder(window), "the panel put its responder into the window's chain")
        var current: NSResponder? = window.nextResponder
        while let responder = current {
            XCTAssertFalse(responder is CancelOperationResponder && responder is NSView, "the responder is not a view")
            current = responder.nextResponder
        }
        shows.panel = false
        XCTAssertTrue(runUntil(timeout: 2) { !ProgressCancelKeysTests.chainHoldsAResponder(window) }, "the responder left the chain with the panel")
        press(.escape, in: window)
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(ledger.cancelCount, 0, "with the panel gone, Escape stops nothing")
        close(window)
    }

    /// Whether the panel is drawn, for the test above.
    @Observable
    final class PanelShows {

        // MARK: - Stored properties

        var panel: Bool = true
    }

    static func chainHoldsAResponder(_ window: NSWindow) -> Bool {
        var current: NSResponder? = window.nextResponder
        while let responder = current {
            if responder is CancelOperationResponder {
                return true
            }
            current = responder.nextResponder
        }
        return false
    }

    /// The responder takes itself out of the chain and leaves the rest
    /// joined up as it was.
    func testUninstallLeavesTheChainAsItWas() {
        let window: NSWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let after: NSResponder = NSResponder()
        window.nextResponder = after
        let responder: CancelOperationResponder = CancelOperationResponder()
        responder.install(in: window)
        responder.install(in: window)
        XCTAssertTrue(window.nextResponder === responder)
        XCTAssertTrue(responder.nextResponder === after, "installed twice, it is in the chain once")
        responder.uninstall()
        XCTAssertTrue(window.nextResponder === after)
        XCTAssertFalse(CancelOperationResponder.chain(of: window, contains: responder))
    }

    // MARK: - A deploy asks first (Russell, 2026-11-19)

    /// The alert attached to the window, once it shows.
    func stopQuestion(in window: NSWindow) -> NSWindow? {
        _ = runUntil(timeout: 3) { window.attachedSheet != nil }
        return window.attachedSheet
    }

    func buttons(in sheet: NSWindow) -> [String: NSButton] {
        var found: [String: NSButton] = [:]
        var queue: [NSView] = []
        if let contentView = sheet.contentView {
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

    /// Escape on a running deploy asks "Stop the deploy?" and stops nothing.
    /// Continue Deploy holds Escape (and so Command-Period), Stop Deploy holds
    /// no key at all, so neither a second Escape nor a Return stops the
    /// deploy unread. Continue Deploy leaves it running; Stop Deploy stops it,
    /// once.
    func checkADeployAsksFirst(_ key: Key) {
        let runner: ScriptRunner = runningRunner()
        let ledger: CancelLedger = CancelLedger()
        let window: NSWindow = windowShowing(panel(runner: runner, ledger: ledger, takesTheCancelKeys: true, asksBeforeStopping: true))
        press(key, in: window)
        guard let sheet = stopQuestion(in: window) else {
            XCTFail("\(key) on a running deploy did not ask first")
            close(window)
            return
        }
        XCTAssertEqual(ledger.cancelCount, 0, "\(key) stopped the deploy without asking")
        let shown: [String: NSButton] = buttons(in: sheet)
        guard let continueButton = shown[DeployStopWording.continueButton], let stopButton = shown[DeployStopWording.stopButton] else {
            XCTFail("the question's buttons: \(Array(shown.keys))")
            close(window)
            return
        }
        XCTAssertEqual(continueButton.keyEquivalent, "\u{1b}", "Continue Deploy holds Escape")
        XCTAssertEqual(stopButton.keyEquivalent, "", "Stop Deploy is not the default and holds no key")
        XCTAssertGreaterThan(continueButton.frame.size.width, 0)
        // Continue Deploy: the question goes and the deploy runs on.
        continueButton.performClick(nil)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "Continue Deploy closed the question")
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(ledger.cancelCount, 0, "Continue Deploy stopped the deploy")
        // Asked again, Stop Deploy stops it.
        press(key, in: window)
        guard let again = stopQuestion(in: window), let stopAgain = buttons(in: again)[DeployStopWording.stopButton] else {
            XCTFail("\(key) did not ask again after Continue Deploy")
            close(window)
            return
        }
        stopAgain.performClick(nil)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 }, "Stop Deploy stopped the deploy")
        _ = runUntil(timeout: 0.7) { false }
        press(key, in: window)
        _ = runUntil(timeout: 0.7) { false }
        XCTAssertNil(window.attachedSheet, "once stopped, the key asks nothing more")
        XCTAssertEqual(ledger.cancelCount, 1)
        close(window)
    }

    func testEscapeOnADeployAsksFirst() {
        checkADeployAsksFirst(.escape)
    }

    func testCommandPeriodOnADeployAsksFirst() {
        checkADeployAsksFirst(.commandPeriod)
    }

    /// The question's words, as ruled.
    func testTheQuestionSaysWhatWasRuled() {
        XCTAssertEqual(DeployStopWording.title, "Stop the deploy?")
        XCTAssertEqual(DeployStopWording.stopButton, "Stop Deploy")
        XCTAssertEqual(DeployStopWording.continueButton, "Continue Deploy")
        XCTAssertTrue(DeployStopWording.message.contains("partly updated"))
    }

    /// A deploy that ends while its question is open has nothing to stop:
    /// the question goes, and nothing is stopped.
    func testTheQuestionGoesWhenTheDeployEnds() {
        let runner: ScriptRunner = runningRunner()
        let ledger: CancelLedger = CancelLedger()
        let window: NSWindow = windowShowing(panel(runner: runner, ledger: ledger, takesTheCancelKeys: true, asksBeforeStopping: true))
        press(.escape, in: window)
        XCTAssertNotNil(stopQuestion(in: window), "Escape asked first")
        runner.isRunning = false
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "the question went when the deploy ended")
        XCTAssertEqual(ledger.cancelCount, 0)
        close(window)
    }

    /// A preview stops at once, with no question (the ruling's other half).
    func testAPreviewStopsWithNoQuestion() {
        let runner: ScriptRunner = runningRunner()
        let ledger: CancelLedger = CancelLedger()
        let window: NSWindow = windowShowing(panel(runner: runner, ledger: ledger, takesTheCancelKeys: true))
        press(.escape, in: window)
        XCTAssertTrue(runUntil(timeout: 3) { ledger.cancelCount == 1 })
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertNil(window.attachedSheet, "a preview asks nothing")
        close(window)
    }

    /// The section window's deploy panel asks; its preview panel does not.
    func testTheSectionWindowAsksOnlyForTheDeploy() throws {
        let source: String = try String(contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent("Section/SectionDetailView.swift"), encoding: .utf8)
        var asking: Int = 0
        for chain in SheetConventionScanTests.chains(of: "TaskProgressView(", in: source, file: "SectionDetailView.swift") {
            if chain.arguments.contains("asksBeforeStopping: true") {
                asking += 1
                XCTAssertTrue(chain.arguments.contains("cancelDeploy()"), "the panel that asks is the deploy's")
            }
        }
        XCTAssertEqual(asking, 1, "exactly the deploy's panel asks first")
    }

    func testZZDiagnose() {
        let runner: ScriptRunner = runningRunner()
        let ledger: CancelLedger = CancelLedger()
        let window: NSWindow = windowShowing(panel(runner: runner, ledger: ledger, takesTheCancelKeys: true))
        var lines: [String] = []
        var current: NSResponder? = window.firstResponder
        while let r = current {
            lines.append("chain: \(type(of: r))")
            if let c = r as? CancelOperationResponder {
                lines.append("  enabled \(c.isEnabled) takes \(c.takesCancelOperation()) hasClosure \(c.pressCancel != nil)")
            }
            current = r.nextResponder
        }
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { return }
        let handled: Bool = window.performKeyEquivalent(with: event)
        lines.append("pke handled \(handled) count \(ledger.cancelCount)")
        window.sendEvent(event)
        _ = runUntil(timeout: 0.3) { false }
        lines.append("after sendEvent count \(ledger.cancelCount)")
        let tried: Bool = window.firstResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: nil) ?? false
        lines.append("tryToPerform from first responder \(tried) count \(ledger.cancelCount)")
        // A plain AppKit window with the responder put in by hand.
        let plain: NSWindow = NSWindow(contentRect: NSRect(x: -7000, y: -7000, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        plain.isReleasedWhenClosed = false
        plain.orderFrontRegardless()
        let byHand: CancelOperationResponder = CancelOperationResponder()
        var heard: Int = 0
        byHand.pressCancel = {
            heard += 1
        }
        byHand.isEnabled = true
        byHand.install(in: plain)
        lines.append("plain first responder \(String(describing: plain.firstResponder.map { (r: NSResponder) -> String in String(describing: type(of: r)) }))")
        if let plainEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: plain.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
            let pkeHandled: Bool = plain.performKeyEquivalent(with: plainEvent)
            plain.sendEvent(plainEvent)
            lines.append("plain pke \(pkeHandled) heard after sendEvent \(heard)")
            plain.keyDown(with: plainEvent)
            lines.append("plain heard after keyDown \(heard)")
        }
        let triedPlain: Bool = plain.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: nil)
        lines.append("plain tryToPerform \(triedPlain) heard \(heard)")
        lines.append("plain responds \(byHand.responds(to: #selector(NSResponder.cancelOperation(_:)))) takes \(byHand.takesCancelOperation())")
        plain.orderOut(nil)
        XCTFail(lines.joined(separator: "\n"))
        close(window)
    }
}
