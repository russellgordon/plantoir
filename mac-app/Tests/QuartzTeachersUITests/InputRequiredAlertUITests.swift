import AppKit
import XCTest

/// #1019, in the real app: a task that asks a plain question shows the
/// "Input required" alert WITH a field, the teacher types an answer, Return
/// presses Send (the default button), and the task receives what was typed.
///
/// Until #1019 the field carried `.borderedTextField()` and SwiftUI left it
/// out of the alert, so Send sent the task an empty line. The unit test
/// `InputRequiredAlertTests` holds the same thing in process; this one drives
/// the window once through the accessibility interface a person's tools use,
/// and logs what that interface says about the field (its label, placeholder
/// and identifier), which is what VoiceOver is given.
///
/// A synthetic course in the runner's own temporary folder, `--state-dir`
/// (IsolatedLaunch) and a STUB `preview.sh` that asks one question, writes
/// the answer into the fixture and exits: nothing is built, and no container
/// is used. Opt-in (`PLANTOIR_UI_TESTS=1`): it needs the foreground. Part of
/// no gate, as the whole UI target is.
@MainActor
final class InputRequiredAlertUITests: XCTestCase {

    // MARK: - Tests

    func testTheTeacherTypesAnAnswerAndTheTaskReceivesIt() throws {
        guard ProcessInfo.processInfo.environment["PLANTOIR_UI_TESTS"] == "1" else {
            throw XCTSkip("Opt-in: set PLANTOIR_UI_TESTS=1. This drives the real app and needs the foreground.")
        }

        let fixtureURL: URL = try UITestFolders.makeFixture()
        let answerURL: URL = fixtureURL.appendingPathComponent("stub-answer.txt")
        let stubScript: String = """
        #!/bin/bash
        for argument in "$@"; do
            if [ "$argument" = "--stop" ]; then
                exit 0
            fi
        done
        echo "Getting this folder's website builder ready…"
        printf 'Which room is the class in? '
        read reply
        printf '%s' "$reply" > "\(answerURL.path)"
        echo "Thanks."
        exit 0

        """
        let scriptURL: URL = fixtureURL.appendingPathComponent("preview.sh")
        try Data(stubScript.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let launch: IsolatedLaunch = try IsolatedLaunch.launch(workspace: fixtureURL)
        let application: XCUIApplication = launch.application
        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        courseRow.click()
        application.typeKey(.rightArrow, modifierFlags: [])
        let sectionRow: XCUIElement = application.outlines.staticTexts["Section 1"]
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 10))
        sectionRow.click()

        application.buttons["previewButton"].firstMatch.click()

        // The runner publishes the question after a quiet spell of about
        // three seconds.
        let answerField: XCUIElement = application.textFields.matching(
            NSPredicate(format: "placeholderValue == %@", "Your answer")
        ).firstMatch
        XCTAssertTrue(answerField.waitForExistence(timeout: 30), "the Input required alert holds a field to type the answer into (#1019)")
        print("INPUT-ALERT-UI-AX label=[" + answerField.label + "] placeholder=[" + (answerField.placeholderValue ?? "") + "] identifier=[" + answerField.identifier + "] title=[" + answerField.title + "]")
        let sendButton: XCUIElement = application.buttons["Send"].firstMatch
        XCTAssertTrue(sendButton.exists, "the alert has its Send button")

        answerField.click()
        answerField.typeText("Room 214")
        application.typeKey(.return, modifierFlags: [])

        var received: String = ""
        let deadline: Date = Date().addingTimeInterval(20)
        while received.isEmpty && Date() < deadline {
            received = (try? String(contentsOf: answerURL, encoding: .utf8)) ?? ""
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertEqual(received, "Room 214", "the task receives what was typed")
        application.terminate()
    }
}
