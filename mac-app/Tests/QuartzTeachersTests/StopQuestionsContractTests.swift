import SwiftUI
import XCTest
@testable import QuartzTeachers

/// `contracts/shared-rules.json` → `stopQuestions`, run rather than retyped
/// (#1009, the mac's side of the section added from Windows): every word of
/// the two stop questions and their Settings section pinned to the Swift
/// constants (`DeployStopWording`, `ShareStopWording`,
/// `StopQuestionSettingsWording`, through `StopQuestion`), the trail line's
/// two shapes, and the 14 `cases` played step by step through the panel's
/// own model, `StopQuestionAsking`, and the Settings row's own binding,
/// `StopQuestionSettingsSection.isOn`. The behaviour itself was built and
/// ruled on #988; `StopQuestionTests` holds the same behaviour in the mac's
/// own words.
@MainActor
final class StopQuestionsContractTests: XCTestCase {

    // MARK: - Stored properties

    /// The suites behind this test's settings, removed when it ends.
    var suiteNames: [String] = []

    // MARK: - Functions

    override func tearDown() async throws {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames = []
    }

    /// `shared-rules.json` → `stopQuestions`.
    static func stopQuestions() throws -> [String: Any] {
        return try WorkLeaseLivenessTests.sharedRules(["stopQuestions"])
    }

    /// Settings of this test's own, never the teacher's.
    func freshSettings() throws -> AppSettings {
        let suiteName: String = "StopQuestionsContractTests-" + UUID().uuidString
        suiteNames.append(suiteName)
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return AppSettings(defaults: defaults)
    }

    /// The contract's name for a question, as the mac's question.
    func question(named name: String) throws -> StopQuestion {
        var found: StopQuestion? = nil
        switch name {
        case "deploy":
            found = StopQuestion.deploy
        case "share":
            found = StopQuestion.share
        default:
            found = nil
        }
        return try XCTUnwrap(found, "The contract names a question \(name) that the mac does not have")
    }

    /// The lines written to the trail since it was made, without their
    /// timestamps ("<time> · <what>" becomes "<what>").
    func trailLinesWritten() -> [String] {
        let text: String = ActivityTrail.store.activityText(includingPrompts: true)
        var written: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.isEmpty {
                continue
            }
            if let separator = line.range(of: " · ") {
                written.append(String(line[separator.upperBound...]))
            } else {
                written.append(line)
            }
        }
        return written
    }

    // MARK: - Tests: the words

    /// Each question's title, message and buttons, and its Settings row, are
    /// the contract's `questions`.
    func testTheQuestionsWordsAreTheContracts() throws {
        let rules: [String: Any] = try StopQuestionsContractTests.stopQuestions()
        let questions: [String: Any] = try XCTUnwrap(rules["questions"] as? [String: Any])
        XCTAssertEqual(questions.count, 2, "two questions: the deploy's and the share's")
        for name in ["deploy", "share"] {
            let words: [String: Any] = try XCTUnwrap(questions[name] as? [String: Any], name)
            let asked: StopQuestion = try question(named: name)
            XCTAssertEqual(asked.title, try XCTUnwrap(words["title"] as? String), "\(name): title")
            XCTAssertEqual(asked.message, try XCTUnwrap(words["message"] as? String), "\(name): message")
            XCTAssertEqual(asked.stopButton, try XCTUnwrap(words["stopButton"] as? String), "\(name): stopButton")
            XCTAssertEqual(asked.cancelButton, try XCTUnwrap(words["cancelButton"] as? String), "\(name): cancelButton")
            XCTAssertEqual(asked.settingLabel, try XCTUnwrap(words["settingLabel"] as? String), "\(name): settingLabel")
        }
        // The constants themselves, not only what `StopQuestion` hands on.
        let deploy: [String: Any] = try XCTUnwrap(questions["deploy"] as? [String: Any])
        XCTAssertEqual(DeployStopWording.title, deploy["title"] as? String)
        XCTAssertEqual(DeployStopWording.message, deploy["message"] as? String)
        XCTAssertEqual(DeployStopWording.stopButton, deploy["stopButton"] as? String)
        XCTAssertEqual(DeployStopWording.cancelButton, deploy["cancelButton"] as? String)
        XCTAssertEqual(StopQuestionSettingsWording.asksBeforeStoppingADeploy, deploy["settingLabel"] as? String)
        let share: [String: Any] = try XCTUnwrap(questions["share"] as? [String: Any])
        XCTAssertEqual(ShareStopWording.title, share["title"] as? String)
        XCTAssertEqual(ShareStopWording.message, share["message"] as? String, "the share's sentence about a share left partly shared")
        XCTAssertEqual(ShareStopWording.stopButton, share["stopButton"] as? String)
        XCTAssertEqual(ShareStopWording.cancelButton, share["cancelButton"] as? String)
        XCTAssertEqual(StopQuestionSettingsWording.asksBeforeStoppingAShare, share["settingLabel"] as? String)
        // The sentence for after #992 is not in the app yet (ruling 1 on
        // #988): it must differ from today's, or the change would be lost.
        let later: String = try XCTUnwrap(share["messageOnceAllOrNothing"] as? String)
        XCTAssertNotEqual(later, ShareStopWording.message)
    }

    /// The box and the Settings section are the contract's `wording`.
    func testTheBoxAndTheSectionAreTheContracts() throws {
        let rules: [String: Any] = try StopQuestionsContractTests.stopQuestions()
        let wording: [String: Any] = try XCTUnwrap(rules["wording"] as? [String: Any])
        XCTAssertEqual(StopQuestionSettingsWording.dontAskAgain, try XCTUnwrap(wording["dontAskAgain"] as? String))
        XCTAssertEqual(StopQuestionSettingsWording.sectionHeader, try XCTUnwrap(wording["sectionHeader"] as? String))
        XCTAssertEqual(StopQuestionSettingsWording.footer, try XCTUnwrap(wording["footer"] as? String), "the mac's footer names Escape and Command-Period")
    }

    /// The trail event is the app's, and each of its two shapes, filled with
    /// a question's own words, is the line the mac writes.
    func testTheTrailLinesAreTheContracts() throws {
        let rules: [String: Any] = try StopQuestionsContractTests.stopQuestions()
        let trail: [String: Any] = try XCTUnwrap(rules["trail"] as? [String: Any])
        XCTAssertEqual(ActivityTrail.Event.stopQuestionSettingChanged.rawValue, try XCTUnwrap(trail["event"] as? String))
        let fromSettings: String = try XCTUnwrap(trail["fromSettings"] as? String)
        let fromDontAskAgain: String = try XCTUnwrap(trail["fromDontAskAgain"] as? String)
        let onOrOff: [String: Any] = try XCTUnwrap(trail["onOrOff"] as? [String: Any])
        for asked in [StopQuestion.deploy, StopQuestion.share] {
            for turnedOn in [true, false] {
                let onOrOffWord: String = try XCTUnwrap(onOrOff[turnedOn ? "true" : "false"] as? String)
                var settingsLine: String = fromSettings.replacingOccurrences(of: "{settingLabel}", with: asked.settingLabel)
                settingsLine = settingsLine.replacingOccurrences(of: "{onOrOff}", with: onOrOffWord)
                XCTAssertEqual(StopQuestion.trailLine(for: asked, asked: turnedOn, from: .settings), settingsLine)
                var boxLine: String = fromDontAskAgain.replacingOccurrences(of: "{settingLabel}", with: asked.settingLabel)
                boxLine = boxLine.replacingOccurrences(of: "{onOrOff}", with: onOrOffWord)
                boxLine = boxLine.replacingOccurrences(of: "{title}", with: asked.title)
                XCTAssertEqual(StopQuestion.trailLine(for: asked, asked: turnedOn, from: .dontAskAgain), boxLine)
            }
        }
    }

    // MARK: - Tests: the cases

    /// Every case, step by step, through the panel's model and the Settings
    /// row, as `howToRunACase` says. What stops is what `TaskProgressView`
    /// stops: Cancel stops when the model says so and the task can still be
    /// stopped; Stop Deploy or Stop Share stops a task that is still running.
    func testEveryCaseIsTheMacs() throws {
        let rules: [String: Any] = try StopQuestionsContractTests.stopQuestions()
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 14, "The case list has shrunk")
        var namesSeen: [String] = []
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            XCTAssertFalse(namesSeen.contains(name), "two cases are called \(name)")
            namesSeen.append(name)
            try runCase(testCase, name: name)
        }
    }

    /// One case, on settings and a trail of its own.
    func runCase(_ testCase: [String: Any], name: String) throws {
        useThrowawayTrail(prefix: "stop-questions-contract")
        let settings: AppSettings = try freshSettings()
        let before: [String: Any] = try XCTUnwrap(testCase["settingsBefore"] as? [String: Any], name)
        settings.asksBeforeStoppingADeploy = try XCTUnwrap(before["deploy"] as? Bool, name)
        settings.asksBeforeStoppingAShare = try XCTUnwrap(before["share"] as? Bool, name)
        XCTAssertEqual(trailLinesWritten(), [], "\(name): setting up wrote nothing")

        var asked: StopQuestion? = nil
        if let questionName = testCase["question"] as? String {
            asked = try question(named: questionName)
        }
        let asking: StopQuestionAsking = StopQuestionAsking(question: asked, settings: settings)
        var taskRunning: Bool = try XCTUnwrap(testCase["taskRunning"] as? Bool, name)

        let steps: [String] = try XCTUnwrap(testCase["steps"] as? [String], name)
        let stopsAfterStep: [Bool] = try XCTUnwrap(testCase["stopsAfterStep"] as? [Bool], name)
        let asksAfterStep: [Bool] = try XCTUnwrap(testCase["asksAfterStep"] as? [Bool], name)
        XCTAssertEqual(stopsAfterStep.count, steps.count, "\(name): one stopsAfterStep per step")
        XCTAssertEqual(asksAfterStep.count, steps.count, "\(name): one asksAfterStep per step")

        var index: Int = 0
        while index < steps.count && index < stopsAfterStep.count && index < asksAfterStep.count {
            let step: String = steps[index]
            var stopsNow: Bool = false
            switch step {
            case "pressCancel":
                let modelSaysStop: Bool = asking.pressCancel(taskCanStillBeStopped: taskRunning)
                stopsNow = modelSaysStop && taskRunning
            case "tickDontAskAgain":
                XCTAssertTrue(asking.isAsking, "\(name), step \(index + 1): the box is ticked on an open question")
                asking.dontAskAgain = true
            case "chooseStop":
                asking.chooseStop()
                stopsNow = taskRunning
            case "chooseCancel":
                asking.chooseCancel()
            case "taskEnded":
                taskRunning = false
                asking.taskEnded()
            case "settingsTurnOn", "settingsTurnOff":
                let rowQuestion: StopQuestion = try XCTUnwrap(asked, "\(name): a Settings step needs a question")
                let row: Binding<Bool> = StopQuestionSettingsSection.isOn(rowQuestion, in: settings)
                row.wrappedValue = step == "settingsTurnOn"
            default:
                XCTFail("\(name): the contract names a step \(step), which this runner does not know")
            }
            if stopsNow {
                taskRunning = false
            }
            XCTAssertEqual(stopsNow, stopsAfterStep[index], "\(name), step \(index + 1) (\(step)): stops")
            XCTAssertEqual(asking.isAsking, asksAfterStep[index], "\(name), step \(index + 1) (\(step)): asks")
            index += 1
        }

        let after: [String: Any] = try XCTUnwrap(testCase["settingsAfter"] as? [String: Any], name)
        XCTAssertEqual(settings.asksBeforeStoppingADeploy, try XCTUnwrap(after["deploy"] as? Bool, name), "\(name): the deploy's setting after")
        XCTAssertEqual(settings.asksBeforeStoppingAShare, try XCTUnwrap(after["share"] as? Bool, name), "\(name): the share's setting after")
        let expectedTrail: [String] = try XCTUnwrap(testCase["trail"] as? [String], name)
        XCTAssertEqual(trailLinesWritten(), expectedTrail, "\(name): the trail lines")
    }

    // MARK: - Tests: what a stopped deploy ends as

    /// `stopQuestions.aStoppedDeploy` (added with Windows' #1009, third
    /// review): each case's legs built by hand on the mac's own runner, then
    /// its `outcome` (the published stamp's rule, `recordWhatWentOut`) and the
    /// one place that words it for the window and the assistant,
    /// `MultiDestinationDeployRunner.result`.
    func testEveryStoppedDeployCaseIsTheMacs() throws {
        let section: [String: Any] = try XCTUnwrap(
            try StopQuestionsContractTests.stopQuestions()["aStoppedDeploy"] as? [String: Any]
        )
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7)
        for testCase in cases {
            try playStoppedDeployCase(testCase)
        }
    }

    /// One case of `aStoppedDeploy`, as `howToRunACase` says.
    func playStoppedDeployCase(_ testCase: [String: Any]) throws {
        let name: String = try XCTUnwrap(testCase["name"] as? String)
        let legEntries: [[String: Any]] = try XCTUnwrap(testCase["legs"] as? [[String: Any]], name)
        var legs: [MultiDestinationDeployRunner.Leg] = []
        for entry in legEntries {
            let type: String = try XCTUnwrap(entry["type"] as? String, name)
            let path: String = type == "local_folder" ? "/sites" : ""
            var leg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
                destination: CourseConfiguration.DeployDestination(type: type, path: path)
            )
            let state: String = try XCTUnwrap(entry["state"] as? String, name)
            switch state {
            case "deployed":
                leg.isFinished = true
                leg.succeeded = true
            case "stoppedDuring":
                leg.isFinished = true
                leg.succeeded = false
            case "notReached":
                break
            default:
                XCTFail("\(name): the contract names a leg state \(state), which this runner does not know")
            }
            legs.append(leg)
        }
        let run: MultiDestinationDeployRunner = MultiDestinationDeployRunner()
        run.legs = legs
        run.wasCancelled = try XCTUnwrap(testCase["stopped"] as? Bool, name)
        let outcome: MultiDestinationDeployRunner.Outcome = run.outcome

        let everyDeployed: Bool = try XCTUnwrap(testCase["everyDestinationDeployed"] as? Bool, name)
        XCTAssertEqual(outcome.allSucceeded, everyDeployed, "\(name): every destination deployed")
        let numbers: [Int] = try XCTUnwrap(testCase["notDeployedTo"] as? [Int], name)
        var notDeployed: [CourseConfiguration.DeployDestination] = []
        var notDeployedNames: [String] = []
        for number in numbers {
            let destination: CourseConfiguration.DeployDestination = legs[number - 1].destination
            notDeployed.append(destination)
            notDeployedNames.append(DeployCommand.destinationDescription(for: destination))
        }
        XCTAssertEqual(outcome.failedDestinations, notDeployed, "\(name): the destinations not deployed")

        let told: String = try XCTUnwrap(testCase["told"] as? String, name)
        var expected: String = ""
        switch told {
        case "deployed":
            expected = AssistWording.deployed(course: "STPKY", section: "1")
        case "deployDidNotFinish":
            expected = AssistWording.deployDidNotFinish(course: "STPKY", section: "1")
        case "deployedToMultipleDestinations":
            expected = AssistWording.deployedToMultipleDestinations(
                course: "STPKY", section: "1", destinationCount: legs.count
            )
        case "deployPartiallySucceeded":
            expected = AssistWording.deployPartiallySucceeded(
                course: "STPKY", section: "1",
                failedDestinations: MultiDestinationDeployRunner.joinedWithAnd(notDeployedNames)
            )
        case "deployToMultipleDestinationsDidNotFinish":
            expected = AssistWording.deployToMultipleDestinationsDidNotFinish(course: "STPKY", section: "1")
        default:
            XCTFail("\(name): the contract names a sentence \(told), which this runner does not know")
        }
        let result: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
            course: "STPKY", section: "1", destinationCount: legs.count, outcome: outcome
        )
        XCTAssertEqual(result.message, expected, "\(name): what the assistant is told")
    }
}
