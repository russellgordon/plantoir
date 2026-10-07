import XCTest
@testable import QuartzTeachers

/// "Schedule a deploy at 6:30 am" and "cancel the scheduled deploy" —
/// answered in code, never by the model (#449, the mac's half of Windows'
/// #424).
///
/// **Why this file exists.** Measured on Windows (bundle 10, Intel UHD 620,
/// the small assistant): a sentence asking for a LATER deploy reached
/// `deploy_section` 10 of 10 — an immediate deploy behind the Deploy button —
/// and a teacher asking to call off a scheduled deploy was declined 10 of 10.
///
/// Every row is read from `contracts/assist-cases.json` → `scheduleAndCancel`,
/// which Windows' `ScheduleAndCancelFramesTests` reads too. Nothing is typed
/// here that could disagree with it — apart from the two settler tests at the
/// bottom, whose sentences are the authored scenarios' own neighbours.
@MainActor
final class ScheduleAndCancelFramesTests: XCTestCase {

    // MARK: - Stored properties

    private var root: URL?
    private var previousStore: ProblemReportStore?

    // MARK: - Functions

    override func tearDown() async throws {
        ScheduledDeploy.launchAgentsDirectoryOverride = nil
        ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        if let previousStore {
            ActivityTrail.store = previousStore
        }
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        try await super.tearDown()
    }

    // MARK: - The frames, row by row

    /// Every accepted row reaches its tool, with the `when` the row names.
    func testEveryAcceptedRowIsAnsweredInCode() throws {
        let rows: [[String: Any]] = try ScheduleAndCancelFramesTests.rows(named: "accepted")
        XCTAssertGreaterThanOrEqual(rows.count, 10, "accepted rows have gone missing")
        for row in rows {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is accepted for no stated reason")
            let command: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(input),
                "\"\(input)\" is in the contract as answered in code and matches nothing"
            )
            XCTAssertEqual(command.toolName, row["expectTool"] as? String, input)
            XCTAssertEqual(command.arguments["when"], row["expectWhen"] as? String, input)
            // A card binds THIS window's section, so it must never carry one.
            XCTAssertNil(command.arguments["section"], input)
            XCTAssertNil(command.arguments["course"], input)
            XCTAssertFalse(AssistCardCommand.asksWhenToSchedule(input), "\(input) is answered AND asked")
        }
    }

    /// Every asksForTheTime row is asked about — and is not also answered.
    func testEveryRowWithNoTimeItCanSetIsAskedAbout() throws {
        let rows: [[String: Any]] = try ScheduleAndCancelFramesTests.rows(named: "asksForTheTime")
        XCTAssertGreaterThanOrEqual(rows.count, 7, "asksForTheTime rows have gone missing")
        for row in rows {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is asked about for no stated reason")
            XCTAssertNil(AssistCardCommand.matching(input), "\"\(input)\" was answered rather than asked about")
            XCTAssertTrue(AssistCardCommand.asksWhenToSchedule(input), "\"\(input)\" was not asked about")
        }
    }

    /// Every refused row falls through to the model: not answered, not asked
    /// morning-or-evening, not given a spelling, and not asked for a time.
    ///
    /// Stronger than Windows' check on purpose: `deployFrame` drops a trailing
    /// "?" itself, so "schedule a deploy at 6:30 am?" rewritten before its "?"
    /// was refused would come out as a scheduled deploy here.
    func testEveryRefusedRowGoesToTheModel() throws {
        let rows: [[String: Any]] = try ScheduleAndCancelFramesTests.rows(named: "refused")
        XCTAssertGreaterThanOrEqual(rows.count, 11, "refused rows have gone missing")
        for row in rows {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is refused for no stated reason")
            XCTAssertNil(AssistCardCommand.matching(input), "\"\(input)\" was matched in code")
            XCTAssertNil(AssistCardCommand.morningOrEvening(input), "\"\(input)\" was asked morning or evening")
            XCTAssertNil(AssistCardCommand.timeToSayAs(input), "\"\(input)\" was given a spelling")
            XCTAssertFalse(AssistCardCommand.asksWhenToSchedule(input), "\"\(input)\" was asked for a time")
        }
    }

    /// The three things that fall through AFTER the opening, which no
    /// contract row exercises on its own: a negation later in the sentence,
    /// and a course code this Mac has never heard of (recognised by its
    /// shape, so it is not answered as if it were this window's course).
    func testANegationOrAnUnknownCodeAfterTheOpeningGoesToTheModel() {
        let toTheModel: [String] = [
            "schedule a deploy, but not tomorrow",
            "schedule a deploy tomorrow, no",
            "schedule a deploy and don’t send it yet",
            "schedule a deploy for zzz9q tomorrow",
            "schedule the deploy for both courses",
        ]
        for sentence in toTheModel {
            XCTAssertNil(AssistCardCommand.matching(sentence), sentence)
            XCTAssertFalse(AssistCardCommand.asksWhenToSchedule(sentence), sentence)
        }
    }

    /// The example the question names is a sentence the family accepts, so a
    /// teacher who types it gets the scheduled deploy's card on the next turn.
    func testTheExampleTheQuestionNamesIsAccepted() throws {
        let said: String = AssistWording.scheduleADeployNeedsATime
        let quoted: String = try XCTUnwrap(
            said.components(separatedBy: "“").last?.components(separatedBy: "”").first
        )
        let command: AssistCardCommand = try XCTUnwrap(AssistCardCommand.matching(quoted), quoted)
        XCTAssertEqual(command.toolName, "schedule_deploy")
        XCTAssertEqual(command.arguments["when"], "tomorrow 06:30")
    }

    /// "Schedule a deploy at 6:30" is asked morning-or-evening exactly as
    /// "deploy at 6:30" is, with the same two answer sentences.
    func testAScheduleWithAnAmbiguousTimeIsAskedMorningOrEvening() throws {
        let asked: AssistTimeQuestion = try XCTUnwrap(AssistCardCommand.morningOrEvening("schedule a deploy at 6:30"))
        let plain: AssistTimeQuestion = try XCTUnwrap(AssistCardCommand.morningOrEvening("deploy at 6:30"))
        XCTAssertEqual(asked.sayMorning, plain.sayMorning)
        XCTAssertEqual(asked.sayEvening, plain.sayEvening)
        XCTAssertFalse(AssistCardCommand.asksWhenToSchedule("schedule a deploy at 6:30"))
    }

    // MARK: - Through the agent

    /// An accepted schedule puts the scheduled deploy's card up, with no
    /// model asked; nothing is scheduled before the button.
    func testAnAcceptedScheduleReachesTheCardWithNoModel() async throws {
        let (made, launchAgents, engine) = try prepare()
        defer { engine.stop() }
        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)

        await agent.say("schedule a deploy at 6:30 am")

        XCTAssertEqual(engine.requestCount, 0, "the model was asked")
        let pending: AssistAgent.PendingApproval = try XCTUnwrap(agent.pendingApproval)
        XCTAssertEqual(pending.call.function.name, "schedule_deploy")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: launchAgents.path), [])
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(AssistAgent.matchedInCodeLine(for: pending.call)), trail)
        agent.declinePending()
    }

    /// The prompt shelf's own card cancels in code, with no model asked —
    /// and the deploy set beforehand is really gone afterwards. The trail
    /// line alone would not prove it: it is written BEFORE the tool runs.
    func testTheShelfsCancelCardCancelsTheScheduledDeployWithNoModel() async throws {
        let (made, _, engine) = try prepare()
        defer { engine.stop() }
        let set: AssistToolOutcome = await made.runner.run(call: AssistToolCall(
            id: "set", type: "function",
            function: AssistToolCall.Function(
                name: "schedule_deploy",
                arguments: #"{"course":"ICS3U","section":1,"when":"2030-09-09 06:30"}"#
            )
        ))
        XCTAssertTrue(set.summary.contains("Scheduled:"), set.summary)
        XCTAssertNotNil(
            ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: made.root),
            "the fixture did not set a deploy to cancel"
        )
        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)

        await agent.say("Cancel scheduled deploy")

        XCTAssertEqual(engine.requestCount, 0, "the model was asked")
        XCTAssertNil(agent.pendingApproval, "cancelling needs no card")
        XCTAssertNil(
            ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: made.root),
            "the shelf's cancel card left the scheduled deploy in place"
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("matched in code, not sent to the model — ran cancel_scheduled_deploy"), trail)
    }

    /// "Schedule a deploy" with no time is asked about in code: one assistant
    /// line, the named sentence, no card, no model, and its own trail line.
    func testAScheduleWithNoTimeIsAskedInCode() async throws {
        let (made, launchAgents, engine) = try prepare()
        defer { engine.stop() }
        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        let messagesBefore: Int = agent.messages.count
        let entriesBefore: Int = agent.entries.count

        await agent.say("Schedule a deploy for tomorrow")

        XCTAssertEqual(engine.requestCount, 0, "the model was asked")
        XCTAssertEqual(agent.messages.count, messagesBefore, "the sentence or the question reached the model's conversation")
        XCTAssertNil(agent.pendingApproval)
        var assistantLines: [String] = []
        for entry in agent.entries.dropFirst(entriesBefore) where entry.speaker == .assistant {
            assistantLines.append(entry.text)
        }
        XCTAssertEqual(assistantLines, [AssistWording.scheduleADeployNeedsATime])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: launchAgents.path), [])
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(AssistAgent.askedWhenToScheduleLine), trail)
    }

    // MARK: - Settler S1: a deploy-now answer to a later time

    /// The model answers a later-time sentence with deploy_section: no card,
    /// nothing run, the time asked for — and the trail says what the model
    /// chose WITHOUT claiming it waited for the button (ruling 1).
    func testADeployNowForALaterTimeIsAskedAboutAndTheTrailSaysNoButton() async throws {
        let (made, _, engine) = try prepare()
        defer { engine.stop() }
        engine.serve(ScheduleAndCancelFramesTests.toolCallReply(
            tool: "deploy_section", arguments: #"{"course":"ICS3U","section":1}"#
        ))
        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        let messagesBefore: Int = agent.messages.count

        await agent.say("Push it live tonight please")

        XCTAssertEqual(engine.requestCount, 1)
        XCTAssertNil(agent.pendingApproval, "a Deploy-now card went up for a later time")
        XCTAssertEqual(agent.messages.count, messagesBefore, "the turn was not wound back")
        XCTAssertEqual(agent.entries.last?.text, AssistWording.scheduleADeployNeedsATime)
        XCTAssertEqual(made.siteWork.deploys, 0)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(AssistAgent.choseADeployNowForALaterTimeLine), trail)
        XCTAssertFalse(trail.contains("waited for the button"), trail)
    }

    /// A sentence with no later-time word still gets the Deploy-now card, and
    /// the trail still says it waited for the button.
    func testADeployNowForNowStillReachesTheCard() async throws {
        let (made, _, engine) = try prepare()
        defer { engine.stop() }
        engine.serve(ScheduleAndCancelFramesTests.toolCallReply(
            tool: "deploy_section", arguments: #"{"course":"ICS3U","section":1}"#
        ))
        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)

        await agent.say("Push the next section live")

        let pending: AssistAgent.PendingApproval = try XCTUnwrap(agent.pendingApproval)
        XCTAssertEqual(pending.call.function.name, "deploy_section")
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("waited for the button"), trail)
        XCTAssertFalse(trail.contains(AssistAgent.choseADeployNowForALaterTimeLine), trail)
        agent.declinePending()
    }

    /// The later-time words, as whole words — and the words left out on
    /// purpose ("next", "soon", "after", "today" alone).
    func testTheLaterTimeWords() {
        let later: [String] = [
            "Deploy this section at 6:30 tomorrow morning, before school starts.",
            "deploy it tonight", "put it up on Friday", "deploy at 7", "deploy at 7 pm",
            "send it at 6.30", "deploy it later", "push tomorrow's class live", "schedule it",
        ]
        for sentence in later {
            XCTAssertTrue(AssistAgent.saysALaterTime(sentence), sentence)
        }
        let now: [String] = [
            "deploy the next section", "deploy it soon", "deploy it after all", "deploy today",
            "deploy now", "deploy at once", "deploy section 12", "Saturdays are quiet", "",
        ]
        for sentence in now {
            XCTAssertFalse(AssistAgent.saysALaterTime(sentence), sentence)
        }
    }

    // MARK: - Settler S2: a model-sent unit "next"

    /// The model's unit "next" is dropped unless the teacher said "unit";
    /// everything else in the call is kept.
    func testAModelSentNextUnitIsDroppedUnlessTheTeacherSaidUnit() {
        let call: AssistToolCall = AssistToolCall(
            id: "1", type: "function",
            function: AssistToolCall.Function(
                name: "add_next_class", arguments: #"{"course":"ICS3U","section":1,"unit":"Next","days":0}"#
            )
        )
        let settled: [String: Any] = AssistAgent.withoutAnUnaskedNewUnit(call, typed: "Add the next class")
            .argumentValues
        XCTAssertNil(settled["unit"])
        XCTAssertEqual(settled["days"] as? Int, 0)
        XCTAssertEqual(settled["course"] as? String, "ICS3U")

        let asked: [String: Any] = AssistAgent.withoutAnUnaskedNewUnit(call, typed: "Start the next Unit")
            .argumentValues
        XCTAssertEqual(asked["unit"] as? String, "Next")

        let numbered: AssistToolCall = AssistToolCall(
            id: "2", type: "function",
            function: AssistToolCall.Function(name: "add_next_class", arguments: #"{"unit":"3"}"#)
        )
        XCTAssertEqual(
            AssistAgent.withoutAnUnaskedNewUnit(numbered, typed: "Add the next class").argumentValues["unit"]
                as? String,
            "3"
        )
    }

    // MARK: - Helpers

    /// A runner with a redirected trail and LaunchAgents folder, and an engine
    /// that answers anything with plain words — so a lap nobody should have
    /// taken is counted rather than left waiting.
    private func prepare() throws -> (AssistFixture.Made, URL, StubEngine) {
        let made = try AssistFixture.makeRunner(hasDeployedBefore: true)
        root = made.root
        let launchAgents: URL = made.root.appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = launchAgents
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            launchAgents.deletingLastPathComponent().appendingPathComponent("scheduled")
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(
            folderURL: made.root.appendingPathComponent("trail", isDirectory: true)
        )
        let engine: StubEngine = try StubEngine()
        engine.serve(
            #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Here it is."}}],"#
            + #""usage":{"completion_tokens":4}}"#
        )
        return (made, launchAgents, engine)
    }

    private static func toolCallReply(tool: String, arguments: String) -> String {
        var escaped: String = ""
        for character in arguments {
            if character == "\"" {
                escaped.append("\\\"")
            } else {
                escaped.append(character)
            }
        }
        return #"{"choices":[{"finish_reason":"tool_calls","message":"#
            + #"{"role":"assistant","content":"","tool_calls":["#
            + #"{"id":"call-1","type":"function","function":"#
            + #"{"name":""# + tool + #"","arguments":""# + escaped + #""}}]}}],"#
            + #""usage":{"completion_tokens":48}}"#
    }

    private static func rows(named key: String) throws -> [[String: Any]] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(
            contentsOf: repository.appendingPathComponent("contracts")
                .appendingPathComponent(AssistContract.casesFileName)
        )
        let contract: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let family: [String: Any] = try XCTUnwrap(
            contract["scheduleAndCancel"] as? [String: Any],
            "contracts/assist-cases.json has no scheduleAndCancel"
        )
        XCTAssertNotNil(family["note"] as? String)
        return try XCTUnwrap(family[key] as? [[String: Any]], "scheduleAndCancel has no \(key)")
    }
}
