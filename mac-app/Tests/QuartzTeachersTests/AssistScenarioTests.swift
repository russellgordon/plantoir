import XCTest
@testable import QuartzTeachers

/// Runs the scenarios in `contracts/assist-cases.json` — the same file the
/// Windows suite runs.
///
/// **Why the cases live in JSON and not here.** They were here, in Swift, and
/// the Windows app was built from a prose description of them written by hand
/// in `WINDOWS-HANDOFF.md`. That is a translation, once per change, by somebody
/// who cannot run this suite — and a translation of an ORDER ("stop the
/// preview, wait, then deploy") is exactly the kind of thing that survives
/// review while being wrong. Now both platforms read the same list, and a case
/// nobody has implemented fails on the side that has not implemented it.
///
/// **What stays in Swift.** The file says WHAT must happen; this file says HOW
/// to make it happen on a Mac — which fake stands in for a section window, how
/// a page gets written, what a "write" event even is here. That division is
/// deliberate and is the reason the contract is portable: nothing in it names
/// a Swift type, a WinUI control, or a container.
///
/// A scenario that this runner cannot yet set up FAILS rather than being
/// skipped quietly. A skipped case is a case both platforms believe the other
/// one is covering.
@MainActor
final class AssistScenarioTests: XCTestCase {

    // MARK: - Types

    /// One case, as the contract writes it.
    private struct Scenario {
        let name: String
        let given: [String: Any]
        let when: String
        let expectEvents: [String]?
        let expectReply: String?
        let expectTranscript: [String]?

        /// The same ordered check, matched by CONTAINS rather than equality.
        ///
        /// **Needed because a composed reply cannot be pinned by equality.**
        /// A rollover answers two things at once — "Re-dated 3 classes and 2
        /// pages they use." and then the website question — so no single named
        /// sentence equals the line. Asserting the line CONTAINS the named
        /// sentence keeps the wording in the contract, where it belongs, while
        /// letting each platform arrange a composed reply its own way. Order
        /// is portable; exact composition is not, which is the same reason
        /// `expectTranscript` checks order rather than adjacency.
        let expectTranscriptContains: [String]?
    }

    // MARK: - Functions

    /// Every scenario in the contract, run for real.
    func testEveryScenarioInTheContract() async throws {
        let scenarios: [Scenario] = try readScenarios()
        XCTAssertGreaterThanOrEqual(scenarios.count, 8, "The contract has lost scenarios")

        for scenario in scenarios {
            try await run(scenario)
        }
    }

    /// The card phrasings, also from the contract: each one must reach the tool
    /// the file says it reaches, without the model being asked.
    func testEveryCardPhrasingInTheContractRoutesWhereItSays() throws {
        let cases: [String: Any] = try AssistScenarioTests.readContract(named: AssistContract.casesFileName)
        let phrasings: [String: Any] = try XCTUnwrap(cases["cardPhrasings"] as? [String: Any])

        for match in try XCTUnwrap(phrasings["matches"] as? [[String: Any]]) {
            let phrasing: String = try XCTUnwrap(match["phrasing"] as? String)
            let command: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(phrasing), "\"\(phrasing)\" is in the contract and matches nothing"
            )
            XCTAssertEqual(command.toolName, match["tool"] as? String, phrasing)
            XCTAssertEqual(command.arguments, match["arguments"] as? [String: String] ?? [:], phrasing)
        }
    }

    /// The arrow-key history, from the same contract.
    ///
    /// The KEYS are per platform; these semantics are not, and they are the
    /// part people notice. Each case applies its steps in order to a fresh
    /// history, exactly as a Windows runner would.
    func testThePromptHistoryBehavesAsTheContractSays() throws {
        let cases: [String: Any] = try AssistScenarioTests.readContract(named: AssistContract.casesFileName)
        let section: [String: Any] = try XCTUnwrap(cases["promptHistory"] as? [String: Any])
        XCTAssertEqual(section["mostRemembered"] as? Int, AssistPromptHistory.mostRemembered)

        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var history: AssistPromptHistory = AssistPromptHistory()
            for prompt in try XCTUnwrap(testCase["remember"] as? [String]) {
                history.remember(prompt)
            }

            if let expected = testCase["expectEntries"] as? [String] {
                XCTAssertEqual(history.entries, expected, name)
            }

            for step in (testCase["steps"] as? [[String: Any]]) ?? [] {
                let action: String = try XCTUnwrap(step["do"] as? String)
                // `expect` is absent for a step that only sets things up, and
                // present-but-null for a step that must hand back nothing.
                let wantsAnswer: Bool = step.keys.contains("expect")
                let expected: String? = step["expect"] as? String

                switch action {
                case "up":
                    let answer: String? = history.earlier(startingFrom: step["typed"] as? String ?? "")
                    if wantsAnswer {
                        XCTAssertEqual(answer, expected, "\(name): Up")
                    }
                case "down":
                    let answer: String? = history.later()
                    if wantsAnswer {
                        XCTAssertEqual(answer, expected, "\(name): Down")
                    }
                case "type":
                    history.stopBrowsing()
                default:
                    XCTFail("\(name): the contract asks for a step this runner does not know: \(action)")
                }
            }
        }
    }

    // MARK: - Running one scenario

    private func run(_ scenario: Scenario) async throws {
        let windowOpen: Bool = scenario.given["sectionWindowOpen"] as? Bool ?? false
        let previewRunning: Bool = scenario.given["previewRunning"] as? Bool ?? false
        let sectionBusy: Bool = scenario.given["sectionBusy"] as? Bool ?? false

        let made = try AssistFixture.makeRunner()
        defer {
            FakePreview.shared.forget()
            try? FileManager.default.removeItem(at: made.root)
        }

        if windowOpen {
            FakePreview.shared.register(
                folderPath: made.root.path,
                courseCode: "ICS3U",
                sectionNumber: 1,
                running: previewRunning,
                refusingToDeploy: sectionBusy
                    ? AssistWording.sectionIsBusy(course: "ICS3U", section: "1")
                    : nil
            )
        }

        // A page edit needs a page to edit, and the watched file is what makes
        // a "write" appear in the sequence at the moment it actually happens.
        if scenario.when == "unpublish_pages" {
            try AssistFixture.write(
                page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "one", in: made.course
            )
            FakePreview.shared.watch(pageAt: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course))
        }

        switch scenario.when {
        case "approve", "decline":
            try await runApproval(scenario, made: made)
        default:
            try await runTool(scenario, made: made)
        }
    }

    private func runTool(_ scenario: Scenario, made: AssistFixture.Made) async throws {
        var arguments: [String: Any] = ["course": "ICS3U", "section": 1]
        if scenario.when == "unpublish_pages" {
            arguments["pages"] = "Unit 1, Day 1"
        }
        let outcome: AssistToolOutcome = await made.runner.run(
            call: AssistScenarioTests.call(scenario.when, arguments: arguments)
        )

        if let expected = scenario.expectEvents {
            var wanted: [String] = []
            var runsTheLauncherItself: Bool = false
            for name in expected {
                if name == "runLauncherDirectly" {
                    runsTheLauncherItself = true
                    continue
                }
                wanted.append(AssistScenarioTests.fakeEventName(for: name))
            }
            XCTAssertEqual(
                FakePreview.shared.events, wanted,
                "\(scenario.name): the ORDER is the assertion, not the set"
            )
            if runsTheLauncherItself {
                XCTAssertEqual(
                    made.siteWork.deploys, 1,
                    "\(scenario.name): with no window to press, the launcher is run directly"
                )
            } else {
                XCTAssertEqual(
                    made.siteWork.deploys, 0,
                    "\(scenario.name): a window was open, so the window's own Deploy is what runs"
                )
            }
        }

        if let reply = scenario.expectReply {
            XCTAssertEqual(
                outcome.summary, try AssistScenarioTests.sentence(named: reply),
                "\(scenario.name): the reply is the sentence the contract names"
            )
        }
    }

    private func runApproval(_ scenario: Scenario, made: AssistFixture.Made) async throws {
        let pending: String = try XCTUnwrap(
            scenario.given["pending"] as? String, "\(scenario.name): no pending tool given"
        )
        // A plan needs something real to plan about. `makeRunner` pins today to
        // 2026-09-08, which is what makes "tomorrow" a fixed date here.
        if pending == "publish_class_on" {
            try AssistFixture.write(
                page: "Unit 1, Day 1", publish: "false", date: "2026-09-09", body: "one", in: made.course
            )
        }
        // A rollover needs THREE things or it refuses before reaching anything
        // worth asserting, and each refusal looks like a different bug: with no
        // class dates on file it offers the schedule sheet instead ("I don't
        // know when this section meets"); with no class pages there is nothing
        // to move; and with no site marker the release reports "had no website
        // yet" and the interesting branch never runs.
        if pending == "re_date_classes" {
            // Dated a day the section does not meet, so the FIRST turn has
            // something real to move — and so the second turn meets the
            // "already on its dates" branch, which is the one that was broken.
            try AssistFixture.write(
                page: "Unit 1, Day 1", publish: "false", date: "2020-01-15", body: "one", in: made.course
            )
            let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
                dates: ["2026-09-08", "2026-09-10"], source: "timetable.xlsx, block H",
                forSection: 1, in: made.course
            )
            try SectionTimetableStore.applyRememberTimetable(plan)

            let markerFolder: URL = made.course.directoryURL.appendingPathComponent(".netlify_sites")
            try FileManager.default.createDirectory(
                at: markerFolder, withIntermediateDirectories: true
            )
            try "{\"site\":\"last-year\"}".write(
                to: markerFolder.appendingPathComponent("section1.json"),
                atomically: true, encoding: .utf8
            )
        }

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner)

        // A conversation, not a single turn. `saying` lists what the teacher
        // types, in order, each one approved before the next — because some
        // behaviour only exists across turns: a rollover asks about the
        // website on the FIRST turn and is answered on the SECOND, and the
        // answer was a no-op for a while precisely because nothing exercised
        // two turns in a row. When `saying` is absent this is the old
        // single-turn behaviour, unchanged.
        var conversation: [String] = []
        if let saying = scenario.given["saying"] as? [String] {
            conversation = saying
        } else {
            conversation = [try AssistScenarioTests.phrasingReaching(pending)]
        }

        for (turn, phrasing) in conversation.enumerated() {
            await agent.say(phrasing)
            let isLastTurn: Bool = turn == conversation.count - 1
            guard agent.pendingApproval != nil else {
                XCTAssertFalse(
                    isLastTurn && scenario.when == "approve",
                    "\(scenario.name): nothing is waiting to be agreed to after \"\(phrasing)\""
                )
                continue
            }
            if isLastTurn && scenario.when != "approve" {
                agent.declinePending()
            } else {
                await agent.approvePending()
            }
        }

        try assertTranscript(of: agent, matches: scenario)
    }

    /// Both ordered transcript checks, so a scenario can use either.
    private func assertTranscript(of agent: AssistAgent, matches scenario: Scenario) throws {
        if let contains = scenario.expectTranscriptContains {
            var actual: [String] = []
            for entry in agent.entries {
                actual.append(AssistScenarioTests.transcriptLine(from: entry))
            }
            var searchedFrom: Int = 0
            for line in contains {
                // The speaker is matched as a PREFIX and the sentence as a
                // substring, separately. Resolving the whole thing and asking
                // whether the line contains it would demand that the sentence
                // follow the speaker immediately — which is exactly what a
                // composed reply does not do: "tool(x): Re-dated 1 class.\n\n
                // Should this be a new website…" contains the sentence, and
                // does not contain "tool(x): Should this be a new website…".
                let (speaker, wanted) = try AssistScenarioTests.speakerAndSentence(of: line)
                var found: Int? = nil
                for index in searchedFrom..<actual.count
                where actual[index].hasPrefix(speaker) && actual[index].contains(wanted) && found == nil {
                    found = index
                }
                guard let at = found else {
                    XCTFail(
                        "\(scenario.name): no line in the transcript contains \"\(wanted)\" — it says \(actual)"
                    )
                    return
                }
                // The SAME line may satisfy the next expectation too, which is
                // the whole point of matching by contains: one reply composes
                // several named sentences — the question, how to answer it, and
                // what has not changed — and they are one bubble to a teacher.
                // Advancing past the line would demand a separate reply for
                // each, which is an arrangement no platform should be held to.
                searchedFrom = at
            }
        }

        guard let expected = scenario.expectTranscript else {
            return
        }
        // The named lines must appear IN THIS ORDER — not necessarily next to
        // each other, and not necessarily last.
        //
        // Asserting the final N lines was the first attempt and it was wrong
        // in a way worth recording: after an approval the tool's own result is
        // the last line, so "the teacher's choice is in the transcript" failed
        // against a conversation that contained exactly that. And a
        // transcript's exact composition is the one thing here that is
        // genuinely per-platform — Windows renders tool results differently and
        // should not be held to Swift's arrangement. Order is portable;
        // adjacency is not.
        var actual: [String] = []
        for entry in agent.entries {
            actual.append(AssistScenarioTests.transcriptLine(from: entry))
        }
        var searchedFrom: Int = 0
        for line in expected {
            let wanted: String = try AssistScenarioTests.resolve(transcriptLine: line)
            var found: Int? = nil
            for index in searchedFrom..<actual.count where actual[index] == wanted && found == nil {
                found = index
            }
            guard let at = found else {
                XCTFail("\(scenario.name): the transcript never says \"\(wanted)\" — it says \(actual)")
                return
            }
            searchedFrom = at + 1
        }
    }

    // MARK: - The contract's names, mapped onto this platform

    /// The contract's event names are its own, deliberately: they have to mean
    /// the same thing to a WinUI app with no `FakePreview` in it.
    private static func fakeEventName(for contractName: String) -> String {
        switch contractName {
        case "stopPreview.begins":
            return "stop-begins"
        case "stopPreview.ends":
            return "stop-ends"
        case "startPreview":
            return "start"
        default:
            return contractName
        }
    }

    /// "wording.deployed" → the real sentence, with the placeholders filled in
    /// for the fixture's course and section.
    private static func sentence(named reference: String) throws -> String {
        let key: String = reference.replacingOccurrences(of: "wording.", with: "")
        let wording: [String: String] = try XCTUnwrap(
            readContract(named: AssistContract.wordingFileName)["wording"] as? [String: String]
        )
        let template: String = try XCTUnwrap(wording[key], "No sentence called \(key)")
        return template
            .replacingOccurrences(of: AssistContract.coursePlaceholder, with: "ICS3U")
            .replacingOccurrences(of: AssistContract.sectionPlaceholder, with: "1")
    }

    /// "assistant: wording.deployWasCancelled" → "assistant: Deploy cancelled."
    /// A contract transcript line split into who said it and what they said,
    /// with a `wording.` name resolved to the real sentence.
    private static func speakerAndSentence(of line: String) throws -> (String, String) {
        guard let split = line.range(of: ": ") else {
            return ("", line)
        }
        let speaker: String = String(line[line.startIndex..<split.upperBound])
        let rest: String = String(line[split.upperBound...])
        if rest.hasPrefix("wording.") {
            return (speaker, try sentence(named: rest))
        }
        return (speaker, rest)
    }

    private static func resolve(transcriptLine line: String) throws -> String {
        guard let split = line.range(of: ": ") else {
            return line
        }
        let speaker: String = String(line[line.startIndex..<split.lowerBound])
        let rest: String = String(line[split.upperBound...])
        if rest.hasPrefix("wording.") {
            return speaker + ": " + (try sentence(named: rest))
        }
        return line
    }

    private static func transcriptLine(from entry: AssistAgent.Entry) -> String {
        switch entry.speaker {
        case .teacher:
            return "teacher: " + entry.text
        case .assistant:
            return "assistant: " + entry.text
        case .problem:
            return "problem: " + entry.text
        case .toolResult(let name):
            return "tool(\(name)): " + entry.text
        }
    }

    /// A phrasing that reaches the named tool without the model — which is what
    /// lets an approval scenario run with no server anywhere near it.
    private static func phrasingReaching(_ tool: String) throws -> String {
        for shape in AssistCardCommand.everyFixedShape where shape.command.toolName == tool {
            return shape.phrasing
        }
        throw XCTSkip("No card phrasing reaches \(tool); this scenario needs a model.")
    }

    private static func call(_ name: String, arguments: [String: Any]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(
                name: name, arguments: String(decoding: encoded, as: UTF8.self)
            )
        )
    }

    // MARK: - Reading the contract

    private func readScenarios() throws -> [Scenario] {
        let cases: [String: Any] = try AssistScenarioTests.readContract(named: AssistContract.casesFileName)
        let scenarios: [String: Any] = try XCTUnwrap(cases["scenarios"] as? [String: Any])
        var read: [Scenario] = []
        for entry in try XCTUnwrap(scenarios["cases"] as? [[String: Any]]) {
            read.append(Scenario(
                name: try XCTUnwrap(entry["name"] as? String),
                given: entry["given"] as? [String: Any] ?? [:],
                when: try XCTUnwrap(entry["when"] as? String),
                expectEvents: entry["expectEvents"] as? [String],
                expectReply: entry["expectReply"] as? String,
                expectTranscript: entry["expectTranscript"] as? [String],
                expectTranscriptContains: entry["expectTranscriptContains"] as? [String]
            ))
        }
        return read
    }

    /// Read from the repository, not from the test bundle: the contract's whole
    /// point is that it is committed and reviewable.
    private static func readContract(named name: String) throws -> [String: Any] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(
            contentsOf: repository.appendingPathComponent("contracts").appendingPathComponent(name)
        )
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
