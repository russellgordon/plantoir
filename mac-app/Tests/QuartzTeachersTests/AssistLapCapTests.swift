import XCTest
@testable import QuartzTeachers

/// One teacher action asks the model at most six times (#689).
///
/// Found proving #610's must-fails: a read hands its result back to the model
/// for another lap, and nothing counted the laps, so a model that kept
/// choosing the same read would loop for as long as the window stayed open
/// with nothing said to the teacher. The rule is
/// `contracts/shared-rules.json` → `assistantLapLimit`, and the scenario that
/// pins it on both platforms is in `assist-cases.json` → `scenarios`.
///
/// Every engine here answers through a FUSE — the scripted reply many more
/// times than the cap, then plain text — because `StubEngine` repeats its
/// last entry for ever, and code without the cap must fail on the count in
/// seconds rather than hang the suite.
@MainActor
final class AssistLapCapTests: XCTestCase {

    // MARK: - Types

    /// The replies this file serves, in the shape `AssistCutOffAnswerTests`
    /// builds them.
    private enum Canned {

        static func finished(tool: String, arguments: String) -> String {
            let escaped: String = escape(arguments)
            return #"{"choices":[{"finish_reason":"tool_calls","message":"#
                + #"{"role":"assistant","content":"","tool_calls":["#
                + #"{"id":"call-1","type":"function","function":"#
                + #"{"name":"\#(tool)","arguments":"\#(escaped)"}}]}}],"#
                + #""usage":{"completion_tokens":40}}"#
        }

        static func text(_ said: String) -> String {
            let escaped: String = escape(said)
            return #"{"choices":[{"finish_reason":"stop","message":"#
                + #"{"role":"assistant","content":"\#(escaped)"}}],"#
                + #""usage":{"completion_tokens":8}}"#
        }

        private static func escape(_ text: String) -> String {
            var escaped: String = text.replacingOccurrences(of: "\\", with: "\\\\")
            escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
            escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
            return escaped
        }
    }

    // MARK: - Stored properties

    /// A sentence that reaches the MODEL: it matches no fixed shape. Every
    /// test that counts requests depends on that, so it is checked rather
    /// than assumed (`testTheSentenceReachesTheModel`).
    private static let sentence: String = "Have a good look round this section and tell me what is in it"

    /// More scripted replies than any turn could use with the cap in place.
    private static let fuse: Int = AssistAgent.mostModelRequestsPerTurn * 3 + 2

    private static let listPages: String = Canned.finished(
        tool: "list_pages", arguments: #"{"course":"ICS3U","section":1}"#
    )

    // MARK: - Functions

    /// The sentence these tests and the contract's scenario type reaches the
    /// model: no card, no links question, no morning-or-evening or
    /// scheduling question, no time to say back. Without this the count
    /// would be measuring a card that then lapped, not a turn the model
    /// routed.
    func testTheSentenceReachesTheModel() throws {
        let sentence: String = AssistLapCapTests.sentence
        XCTAssertNil(AssistCardCommand.matching(sentence, windowCourse: "ICS3U", windowSection: 1))
        XCTAssertNil(AssistCardCommand.linksQuestion(sentence, windowCourse: "ICS3U", windowSection: 1))
        XCTAssertNil(AssistCardCommand.morningOrEvening(sentence))
        XCTAssertFalse(AssistCardCommand.asksWhenToSchedule(sentence))
        XCTAssertNil(AssistCardCommand.timeToSayAs(sentence))

        let scenario: [String: Any] = try AssistLapCapTests.scenario()
        let given: [String: Any] = try XCTUnwrap(scenario["given"] as? [String: Any])
        XCTAssertEqual(given["saying"] as? [String], [sentence], "the scenario's sentence is the one checked here")
    }

    /// The headline: a model that answers every request with the same read
    /// is asked six times, and the teacher is told, last, that it went
    /// round without finishing. The turn is wound back to the system prompt.
    func testARepeatedReadIsStoppedAfterSixRequests() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(AssistLapCapTests.fused(AssistLapCapTests.listPages))

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        await agent.say(AssistLapCapTests.sentence)

        XCTAssertEqual(engine.requestCount, AssistAgent.mostModelRequestsPerTurn, "the turn was not capped")
        XCTAssertEqual(agent.entries.last?.text, AssistWording.wentRoundWithoutFinishing)
        XCTAssertEqual(agent.activity, .idle)
        XCTAssertNil(agent.pendingApproval)
        // Six reads ran, and the transcript keeps every one of them: only
        // what the model is sent is wound back.
        XCTAssertEqual(toolResults(in: agent).count, AssistAgent.mostModelRequestsPerTurn)
        XCTAssertEqual(agent.messages.count, 1, "the turn was not taken back out of the conversation")
        XCTAssertEqual(agent.messages.first?.role, "system")
    }

    /// The other re-entry: a tool name that exists nowhere is answered
    /// "There is no tool by that name." and handed straight back, without
    /// passing through `execute`. Capped the same way.
    func testANameThatIsNoToolIsStoppedTheSameWay() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        let noSuchTool: String = Canned.finished(tool: "look_round_everything", arguments: "{}")
        engine.serve(AssistLapCapTests.fused(noSuchTool))

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        await agent.say(AssistLapCapTests.sentence)

        XCTAssertEqual(engine.requestCount, AssistAgent.mostModelRequestsPerTurn, "the turn was not capped")
        XCTAssertEqual(agent.entries.last?.text, AssistWording.wentRoundWithoutFinishing)
        XCTAssertEqual(agent.activity, .idle)
        XCTAssertEqual(agent.messages.count, 1)
    }

    /// Five reads and then an answer is a turn that FINISHED inside the cap:
    /// six requests, the model's own answer, and no cap sentence.
    func testATurnThatFinishesOnTheSixthRequestIsAnswered() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        var served: [String] = []
        while served.count < AssistAgent.mostModelRequestsPerTurn - 1 {
            served.append(AssistLapCapTests.listPages)
        }
        served.append(Canned.text("It has three pages."))
        engine.serve(served)

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        await agent.say(AssistLapCapTests.sentence)

        XCTAssertEqual(engine.requestCount, AssistAgent.mostModelRequestsPerTurn)
        XCTAssertEqual(agent.entries.last?.text, "It has three pages.")
        XCTAssertFalse(transcript(of: agent).contains(AssistWording.wentRoundWithoutFinishing))
    }

    /// The count is per teacher action, not per window: two turns of four
    /// requests each (three reads, then an answer) are both answered.
    ///
    /// Four and four on purpose: eight in all is past the cap, so without
    /// `say()` starting the count again the second turn's third read would
    /// be the seventh request, and the turn would end on
    /// `AssistWording.wentRoundWithoutFinishing` after six requests rather
    /// than on its answer after eight. Three and three (six in all) would
    /// pass with the reset deleted.
    func testEachSentenceStartsTheCountAgain() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        let listPages: String = AssistLapCapTests.listPages
        engine.serve([
            listPages, listPages, listPages, Canned.text("First answer."),
            listPages, listPages, listPages, Canned.text("Second answer."),
        ])

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        await agent.say(AssistLapCapTests.sentence)
        await agent.say(AssistLapCapTests.sentence)

        XCTAssertGreaterThan(8, AssistAgent.mostModelRequestsPerTurn, "the two turns together must pass the cap")
        XCTAssertEqual(engine.requestCount, 8)
        XCTAssertEqual(agent.entries.last?.text, "Second answer.")
        XCTAssertTrue(transcript(of: agent).contains("First answer."))
        XCTAssertFalse(transcript(of: agent).contains(AssistWording.wentRoundWithoutFinishing))
    }

    /// The trail says it happened, with the count and the tool in words, and
    /// never the teacher's sentence.
    func testTheTrailRecordsTheStop() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lap-cap-trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: folderURL)
        }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(AssistLapCapTests.fused(AssistLapCapTests.listPages))

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        await agent.say(AssistLapCapTests.sentence)

        let trail: String = ActivityTrail.store.activityText(includingPrompts: false)
        // Once, not once per lap.
        let stopped: String = "went round 6 times in one turn without finishing"
        XCTAssertEqual(trail.components(separatedBy: stopped).count - 1, 1, trail)
        XCTAssertTrue(trail.contains("last choosing list pages"), trail)
        XCTAssertTrue(trail.contains("taken back out of the conversation"), trail)
        XCTAssertFalse(trail.contains("good look round"), "the teacher's sentence is on a line of its own")
    }

    /// Go is a teacher action of its own: it starts the count again, and the
    /// turn after it begins at the approved call's RESULT, so a wind-back
    /// from a lap after Go can never erase a call that has run (as Windows'
    /// `Approve` does).
    func testGoMovesTheTurnPastTheApprovedResult() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner)
        await agent.say("Publish Unit 1, Day 1")
        XCTAssertNotNil(agent.pendingApproval, "the card this test presses Go on did not come up")
        XCTAssertEqual(agent.messageCountAtTheStartOfTheTurn, 1)
        XCTAssertEqual(agent.sentenceThisTurnBeganWith, "Publish Unit 1, Day 1")

        await agent.approvePending()

        XCTAssertGreaterThan(agent.messages.count, 1)
        XCTAssertEqual(agent.messages.last?.role, "tool", "the approved call's result is the last message")
        XCTAssertEqual(
            agent.messageCountAtTheStartOfTheTurn, agent.messages.count,
            "a lap after Go would wind back past a call that has already run"
        )
        // A lap after Go begins with a tool result, so there is no sentence
        // for the settlers to read (Windows empties `_typedThisTurn` here).
        XCTAssertEqual(agent.sentenceThisTurnBeganWith, "", "Go kept the sentence of the turn before it")
    }

    /// The number is the contract's, and the scenario counts it.
    func testTheCapIsTheContractsNumber() throws {
        let rule: [String: Any] = try SharedRulesContractTests.section("assistantLapLimit")
        XCTAssertEqual(rule["mostModelRequestsPerTurn"] as? Int, AssistAgent.mostModelRequestsPerTurn)
        XCTAssertEqual(AssistAgent.mostModelRequestsPerTurn, 6, "Windows' MostStepsPerTurn is 6; neither moves alone")
        XCTAssertEqual(rule["wording"] as? String, "wording.wentRoundWithoutFinishing")
        XCTAssertEqual(
            rule["trailEvent"] as? String, ActivityTrail.Event.assistantWentRoundWithoutFinishing.rawValue
        )
        XCTAssertEqual(rule["appliesOn"] as? [String], ["mac", "windows"])

        let scenario: [String: Any] = try AssistLapCapTests.scenario()
        XCTAssertEqual(scenario["expectModelRequests"] as? Int, AssistAgent.mostModelRequestsPerTurn)
    }

    // MARK: - Helpers

    /// The scripted reply through the fuse, then plain text.
    private static func fused(_ reply: String) -> [String] {
        var served: [String] = []
        while served.count < fuse {
            served.append(reply)
        }
        served.append(Canned.text("Here it is."))
        return served
    }

    /// The contract's scenario for the cap, found by its `modelReplyAnswers`.
    private static func scenario() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/assist-cases.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let scenarios: [String: Any] = try XCTUnwrap(all["scenarios"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(scenarios["cases"] as? [[String: Any]])
        var found: [[String: Any]] = []
        for entry in cases {
            let given: [String: Any] = entry["given"] as? [String: Any] ?? [:]
            if given["modelReplyAnswers"] as? String == "everyRequest" {
                found.append(entry)
            }
        }
        XCTAssertEqual(found.count, 1, "one scenario pins the lap cap")
        return try XCTUnwrap(found.first)
    }

    private func transcript(of agent: AssistAgent) -> String {
        var lines: [String] = []
        for entry in agent.entries {
            lines.append(entry.text)
        }
        return lines.joined(separator: "\n")
    }

    /// The names of the tools whose results reached the transcript.
    private func toolResults(in agent: AssistAgent) -> [String] {
        var names: [String] = []
        for entry in agent.entries {
            if case .toolResult(let name) = entry.speaker {
                names.append(name)
            }
        }
        return names
    }
}
