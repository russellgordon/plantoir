import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The two stop questions' settings (#988, Russell's rulings of
/// 2026-11-19): "Don't ask again" on each question, each its own setting,
/// remembered only with the stop, and turned back on in Settings ▸
/// Deploying ▸ Stopping. The pressed-key half is in
/// `ProgressCancelKeysTests` (opt-in); these run in every suite.
@MainActor
final class StopQuestionTests: XCTestCase {

    // MARK: - Stored properties

    /// The suite behind this test's settings, removed when it ends.
    var suiteName: String = ""

    // MARK: - Functions

    override func setUp() async throws {
        useThrowawayTrail(prefix: "stop-question-trail")
        suiteName = "StopQuestionTests-" + UUID().uuidString
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// Settings of this test's own, never the teacher's.
    func freshSettings() throws -> AppSettings {
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return AppSettings(defaults: defaults)
    }

    func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    // MARK: - Tests

    /// Both questions are asked until the teacher says otherwise.
    func testBothQuestionsAreOnByDefault() throws {
        let settings: AppSettings = try freshSettings()
        XCTAssertTrue(StopQuestion.deploy.isAsked(in: settings))
        XCTAssertTrue(StopQuestion.share.isAsked(in: settings))
    }

    /// The tick with the stop is remembered; without the tick nothing is.
    func testTheTickWithStopIsRemembered() throws {
        let settings: AppSettings = try freshSettings()
        StopQuestion.deploy.stopWasChosen(dontAskAgainTicked: false, in: settings)
        XCTAssertTrue(settings.asksBeforeStoppingADeploy, "an unticked box changed nothing")
        XCTAssertFalse(trailText().contains("Ask before stopping"), "nothing changed, so nothing was written")
        StopQuestion.deploy.stopWasChosen(dontAskAgainTicked: true, in: settings)
        XCTAssertFalse(settings.asksBeforeStoppingADeploy, "the tick with Stop Deploy turned the question off")
        XCTAssertTrue(trailText().contains(StopQuestion.trailLine(for: .deploy, asked: false, from: .dontAskAgain)), trailText())
    }

    /// Cancel never reaches the setting: the panel's Cancel in the question
    /// has an empty action, and only the stopping button reads the box.
    func testCancelInTheQuestionRemembersNothing() throws {
        let source: String = try String(contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent("Console/TaskProgressView.swift"), encoding: .utf8)
        let code: String = TextFieldStyleScanTests.codeWithoutComments(source)
        XCTAssertTrue(code.contains("Button(questionShown.stopButton) {\n                                        chooseStop()"), "the stopping button reads the box")
        XCTAssertTrue(code.contains("Button(questionShown.cancelButton, role: .cancel) {\n                                    }"), "the question's Cancel does nothing")
        XCTAssertEqual(code.components(separatedBy: "stopWasChosen(").count - 1, 1, "one place remembers the box: chooseStop")
        // The Cancel button's modifiers run from its identifier to the end
        // of the `if cancelIsShowing` block: the question and its box are
        // both there, so the box is on the button and nowhere wider.
        let afterTheCancel: String = try XCTUnwrap(code.components(separatedBy: ".accessibilityIdentifier(\"taskCancelButton\")").dropFirst().first)
        let buttonChain: String = try XCTUnwrap(afterTheCancel.components(separatedBy: "} else if let exitCode = runner.lastExitCode").first)
        let onTheCancel: Bool = buttonChain.contains(".alert(questionShown.title") && buttonChain.contains(".dialogSuppressionToggle(StopQuestionSettingsWording.dontAskAgain, isSuppressed: $dontAskAgain)")
        XCTAssertEqual(code.components(separatedBy: ".dialogSuppressionToggle(").count - 1, 1, "one box in the panel")
        XCTAssertTrue(onTheCancel, "the box is on the panel's Cancel, so it reaches only the stop question (#731)")
    }

    /// Each setting silences only its own question.
    func testEachSettingSilencesOnlyItsOwnQuestion() throws {
        let settings: AppSettings = try freshSettings()
        StopQuestion.share.stopWasChosen(dontAskAgainTicked: true, in: settings)
        XCTAssertFalse(StopQuestion.share.isAsked(in: settings))
        XCTAssertTrue(StopQuestion.deploy.isAsked(in: settings), "silencing the share's question left the deploy's on")
        StopQuestion.share.setAsked(true, in: settings, from: .settings)
        StopQuestion.deploy.stopWasChosen(dontAskAgainTicked: true, in: settings)
        XCTAssertFalse(StopQuestion.deploy.isAsked(in: settings))
        XCTAssertTrue(StopQuestion.share.isAsked(in: settings), "silencing the deploy's question left the share's on")
    }

    /// The Settings rows turn each question back on, write one line per
    /// change, and are the same settings the boxes turn off.
    func testTheSettingsRowsTurnEachBackOn() throws {
        let settings: AppSettings = try freshSettings()
        for question in [StopQuestion.deploy, StopQuestion.share] {
            question.stopWasChosen(dontAskAgainTicked: true, in: settings)
            let row: Binding<Bool> = StopQuestionSettingsSection.isOn(question, in: settings)
            XCTAssertFalse(row.wrappedValue, "\(question): the row shows the question off")
            row.wrappedValue = true
            XCTAssertTrue(question.isAsked(in: settings), "\(question): the row turned it back on")
            XCTAssertTrue(trailText().contains(StopQuestion.trailLine(for: question, asked: true, from: .settings)), trailText())
        }
        XCTAssertTrue(settings.asksBeforeStoppingADeploy)
        XCTAssertTrue(settings.asksBeforeStoppingAShare)
    }

    /// An answer is remembered across launches, each under its own key.
    func testTheAnswersAreRememberedApart() throws {
        let settings: AppSettings = try freshSettings()
        StopQuestion.deploy.setAsked(false, in: settings, from: .settings)
        let later: AppSettings = try freshSettings()
        XCTAssertFalse(later.asksBeforeStoppingADeploy)
        XCTAssertTrue(later.asksBeforeStoppingAShare)
        XCTAssertNotEqual(AppSettings.asksBeforeStoppingADeployKey, AppSettings.asksBeforeStoppingAShareKey)
    }

    /// Settings ▸ Deploying opens with the Stopping section, drawn from the
    /// app's own settings.
    func testDeployingOpensWithTheStoppingSection() throws {
        let source: String = try String(contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent("Settings/DeployingSettingsView.swift"), encoding: .utf8)
        let code: String = TextFieldStyleScanTests.codeWithoutComments(source)
        let form: String = try XCTUnwrap(code.components(separatedBy: "Form {").dropFirst().first)
        let stopping: Range<String.Index> = try XCTUnwrap(form.range(of: "StopQuestionSettingsSection(settings: settings)"))
        let netlify: Range<String.Index> = try XCTUnwrap(form.range(of: "DeployTokenRows(panel: netlifyToken)"))
        XCTAssertTrue(stopping.lowerBound < netlify.lowerBound, "Stopping is the pane's first section")
    }

    /// The words, as ruled.
    func testTheWordsAreTheRuledOnes() {
        XCTAssertEqual(ShareStopWording.title, "Stop this share?")
        XCTAssertEqual(ShareStopWording.message, "The unit plans may be left partly shared until you share them again.")
        XCTAssertEqual(ShareStopWording.stopButton, "Stop Share")
        XCTAssertEqual(ShareStopWording.cancelButton, "Cancel")
        XCTAssertEqual(StopQuestionSettingsWording.dontAskAgain, "Don't ask again")
        XCTAssertEqual(StopQuestionSettingsWording.sectionHeader, "Stopping")
        XCTAssertEqual(StopQuestionSettingsWording.asksBeforeStoppingADeploy, "Ask before stopping a deploy")
        XCTAssertEqual(StopQuestionSettingsWording.asksBeforeStoppingAShare, "Ask before stopping a share of unit plans")
        XCTAssertEqual(StopQuestionSettingsWording.footer, "When one is off, Cancel stops that task at once, and so do the Escape key and Command-Period.")
        XCTAssertEqual(StopQuestion.deploy.title, DeployStopWording.title)
        XCTAssertEqual(StopQuestion.share.stopButton, ShareStopWording.stopButton)
    }
}
