import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The "Input required" alert a running task asks a plain question in
/// (#1019): it holds a field the teacher can type into, and Send gives the
/// task what was typed.
///
/// Found by #1012's writer and its reviewer on 2026-11-20: with
/// `.borderedTextField()` (or any `.textFieldStyle`) on the field, SwiftUI
/// leaves the field OUT of the alert panel, so Send sent an empty line. These
/// tests host the real `TaskProgressView`, run a stub task that asks a plain
/// question on a real pseudo-terminal, and drive the alert the way a teacher
/// does: type, then Return (the default button, Send) or Escape (Cancel).
///
/// The HIG's Alerts page: "an alert can include a text field" "only if you
/// need people's input to resolve the situation"; "Always place the default
/// button on the trailing side"; "you don't want to make a Cancel button the
/// default button"; and Escape or Command-Period cancels an alert. Send is the
/// default because answering is what the task is waiting for; Cancel stops it.
@MainActor
final class InputRequiredAlertTests: XCTestCase {

    // MARK: - Stored properties

    /// What the stub task prints back, around whatever line it was sent.
    static let receivedMarker: String = "TASK RECEIVED ["

    // MARK: - Tests

    func testTheAlertHoldsAFieldAndReturnSendsWhatWasTyped() throws {
        let folder: URL = try InputRequiredAlertTests.makeAskingTask()
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let runner: ScriptRunner = ScriptRunner()
        let host: TableHost = TableHost(TaskProgressView(runner: runner, title: "Test task", canCancel: false))
        defer {
            runner.terminate()
            host.close()
        }
        runner.run(scriptNamed: "ask.sh", arguments: [], workingDirectory: folder)
        XCTAssertNil(runner.launchProblem, "the stub task should launch")

        let alert: NSWindow = try InputRequiredAlertTests.waitForTheAlert(runner: runner, host: host)
        let fields: [NSTextField] = InputRequiredAlertTests.editableFields(in: alert)
        XCTAssertEqual(fields.count, 1, "the Input required alert must hold one field to type the answer into (#1019)")
        guard let field = fields.first else {
            return
        }

        // What VoiceOver is given for the field, written to the log so the
        // measurement in documentation/09 can be checked again (#1019).
        print("INPUT-ALERT-AX label=[" + (field.accessibilityLabel() ?? "") + "] placeholder=[" + (field.placeholderString ?? "") + "] role=[" + (field.accessibilityRole()?.rawValue ?? "") + "] identifier=[" + field.accessibilityIdentifier() + "]")
        XCTAssertEqual(field.placeholderString, "Your answer", "the field's placeholder says what goes in it")

        let send: NSButton? = InputRequiredAlertTests.button(titled: "Send", in: alert)
        let cancel: NSButton? = InputRequiredAlertTests.button(titled: "Cancel", in: alert)
        XCTAssertEqual(send?.keyEquivalent, "\r", "Send is the default button: Return answers the question")
        XCTAssertEqual(cancel?.keyEquivalent, "\u{1b}", "Escape presses Cancel")

        XCTAssertTrue(alert.makeFirstResponder(field), "the field takes the typing focus")
        guard let editor = field.currentEditor() as? NSTextView else {
            XCTFail("the field has no editor to type into")
            return
        }
        editor.insertText("Room 214", replacementRange: editor.selectedRange())
        host.pump()

        XCTAssertTrue(alert.performKeyEquivalent(with: InputRequiredAlertTests.keyDown("\r", keyCode: 36, in: alert)), "Return is taken by the alert")
        let received: String = InputRequiredAlertTests.waitForTheTaskToEnd(runner: runner, host: host)
        XCTAssertTrue(received.contains(InputRequiredAlertTests.receivedMarker + "Room 214]"), "the task receives what was typed; it printed: " + received)
        XCTAssertFalse(runner.wasCancelled)
    }

    func testEscapeCancelsTheQuestion() throws {
        let folder: URL = try InputRequiredAlertTests.makeAskingTask()
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let runner: ScriptRunner = ScriptRunner()
        let host: TableHost = TableHost(TaskProgressView(runner: runner, title: "Test task", canCancel: false))
        defer {
            runner.terminate()
            host.close()
        }
        runner.run(scriptNamed: "ask.sh", arguments: [], workingDirectory: folder)

        let alert: NSWindow = try InputRequiredAlertTests.waitForTheAlert(runner: runner, host: host)
        XCTAssertTrue(alert.performKeyEquivalent(with: InputRequiredAlertTests.keyDown("\u{1b}", keyCode: 53, in: alert)), "Escape is taken by the alert")
        let received: String = InputRequiredAlertTests.waitForTheTaskToEnd(runner: runner, host: host)
        XCTAssertTrue(runner.wasCancelled, "Escape cancels the question")
        XCTAssertFalse(received.contains(InputRequiredAlertTests.receivedMarker), "a cancelled question sends the task no answer; it printed: " + received)
    }

    // MARK: - Functions

    /// A working folder holding `ask.sh`: a task that asks one plain question
    /// (not a credential, not the plan-share lists) and prints the answer.
    static func makeAskingTask() throws -> URL {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("input-required-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script: String = """
        printf 'Which room is the class in? '
        read reply
        echo "\(receivedMarker)$reply]"
        exit 0

        """
        try Data(script.utf8).write(to: folder.appendingPathComponent("ask.sh"))
        return folder
    }

    /// The alert hung on the host's window once the runner has seen the
    /// question (it waits for a quiet spell first, about three seconds).
    static func waitForTheAlert(runner: ScriptRunner, host: TableHost) throws -> NSWindow {
        let deadline: Date = Date().addingTimeInterval(15)
        while Date() < deadline {
            if runner.isAwaitingInput, let sheet = host.window.attachedSheet {
                host.pump()
                return sheet
            }
            host.pump(0.1)
        }
        XCTFail("no Input required alert appeared; awaiting input: " + String(runner.isAwaitingInput) + ", question: [" + runner.pendingQuestion + "]")
        throw CocoaError(.featureUnsupported)
    }

    /// Everything the task printed, once it has ended (or after ten seconds).
    static func waitForTheTaskToEnd(runner: ScriptRunner, host: TableHost) -> String {
        let deadline: Date = Date().addingTimeInterval(10)
        while runner.isRunning && Date() < deadline {
            host.pump(0.1)
        }
        return runner.transcript.recentText(maximumCharacters: 4000)
    }

    /// Every field in `window` a person can type into.
    static func editableFields(in window: NSWindow) -> [NSTextField] {
        var result: [NSTextField] = []
        if let content = window.contentView {
            collectEditableFields(in: content, into: &result)
        }
        return result
    }

    static func collectEditableFields(in view: NSView, into result: inout [NSTextField]) {
        if let field = view as? NSTextField, field.isEditable, !field.isHidden {
            result.append(field)
        }
        for subview in view.subviews {
            collectEditableFields(in: subview, into: &result)
        }
    }

    /// The button in `window` whose title is `title`, if there is one.
    static func button(titled title: String, in window: NSWindow) -> NSButton? {
        guard let content = window.contentView else {
            return nil
        }
        return findButton(titled: title, in: content)
    }

    static func findButton(titled title: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == title {
            return button
        }
        for subview in view.subviews {
            if let found = findButton(titled: title, in: subview) {
                return found
            }
        }
        return nil
    }

    /// A key press as the window would receive it from the keyboard.
    static func keyDown(_ characters: String, keyCode: UInt16, in window: NSWindow) -> NSEvent {
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
