import AppKit
import XCTest
@testable import QuartzTeachers

/// The quit question's keys, pressed for real on the `NSAlert` the app puts
/// up (#987, D7): Cancel leads and answers Escape and Command-Period, Quit
/// Anyway trails, and no button is the default, so Return answers nothing.
/// The alert is shown as a sheet on a window off the screen, rather than
/// with `runModal`, so a test can press its keys and read the answer.
///
/// Until #987 the buttons were Keep Working (the default) and Quit Anyway,
/// and NSAlert gave Escape to neither, because neither was titled Cancel.
@MainActor
final class QuitAlertKeysTests: XCTestCase {

    // MARK: - Types

    enum Key {
        case escape
        case returnKey
        case commandPeriod
    }

    // MARK: - Functions

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

    /// Puts the quit question up on a window off the screen, presses `key`,
    /// and returns what was chosen, or nil while the question still stands.
    private func answer(after key: Key) -> QuitConfirmation.Choice? {
        let answers: [QuitConfirmation.Choice?] = answers(after: [key])
        return answers.first ?? nil
    }

    /// Puts the quit question up once and presses each of `keys` in turn,
    /// returning what had been chosen after each (nil while the question
    /// still stood).
    private func answers(after keys: [Key]) -> [QuitConfirmation.Choice?] {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        let alert: NSAlert = AppDelegate.quitAlert(about: "deploying EXC2O Section 1")
        var chosen: QuitConfirmation.Choice?
        alert.beginSheetModal(for: window) { (response: NSApplication.ModalResponse) in
            chosen = QuitConfirmation.choice(
                atButtonIndex: response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            )
        }
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet != nil }, "the quit question opened")
        _ = runUntil(timeout: 0.3) { false }
        let sheet: NSWindow = alert.window
        var answeredAfterEach: [QuitConfirmation.Choice?] = []
        for key in keys {
            send(key, to: sheet)
            _ = runUntil(timeout: 1) { chosen != nil }
            answeredAfterEach.append(chosen)
        }
        // Each answer was read above, before the sheet is ended here, which
        // answers it too.
        if window.attachedSheet != nil {
            window.endSheet(sheet)
            _ = runUntil(timeout: 1) { window.attachedSheet == nil }
        }
        window.orderOut(nil)
        return answeredAfterEach
    }

    /// Sends `key` to the quit question's window.
    private func send(_ key: Key, to sheet: NSWindow) {
        let characters: String
        let code: UInt16
        var modifiers: NSEvent.ModifierFlags = []
        switch key {
        case .escape:
            characters = "\u{1b}"
            code = 53
        case .returnKey:
            characters = "\r"
            code = 36
        case .commandPeriod:
            characters = "."
            code = 47
            modifiers = [.command]
        }
        if let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: sheet.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        ) {
            if !sheet.performKeyEquivalent(with: event) {
                sheet.sendEvent(event)
            }
        }
    }

    // MARK: - Tests

    func testTheButtonsAreCancelLeadingAndQuitAnywayTrailing() {
        let alert: NSAlert = AppDelegate.quitAlert(about: "deploying EXC2O Section 1")
        alert.layout()
        XCTAssertEqual(alert.buttons.count, 2)
        if alert.buttons.count == 2 {
            let quitAnyway: NSButton = alert.buttons[0]
            let cancel: NSButton = alert.buttons[1]
            XCTAssertEqual(quitAnyway.title, QuitConfirmation.quitAnywayButton)
            XCTAssertEqual(cancel.title, "Cancel")
            XCTAssertEqual(quitAnyway.keyEquivalent, "", "Quit Anyway is the default")
            XCTAssertEqual(cancel.keyEquivalent, "\u{1b}", "Cancel does not answer Escape")
            let cancelX: CGFloat = cancel.convert(cancel.bounds, to: nil).minX
            let quitX: CGFloat = quitAnyway.convert(quitAnyway.bounds, to: nil).minX
            XCTAssertLessThan(cancelX, quitX, "Cancel leads and Quit Anyway trails")
        }
    }

    func testEscapeIsCancel() {
        XCTAssertEqual(answer(after: .escape), .keepWorking)
    }

    func testCommandPeriodIsCancel() {
        XCTAssertEqual(answer(after: .commandPeriod), .keepWorking)
    }

    /// Return answers nothing, and then Escape, on the same question, is
    /// Cancel: the positive check that the keys reach it (#987 review).
    func testReturnAnswersNothing() {
        let answered: [QuitConfirmation.Choice?] = answers(after: [.returnKey, .escape])
        XCTAssertEqual(answered.count, 2)
        if answered.count == 2 {
            XCTAssertNil(answered[0], "Return answered the quit question")
            XCTAssertEqual(answered[1], .keepWorking, "after Return, Escape did not reach the quit question")
        }
    }
}
