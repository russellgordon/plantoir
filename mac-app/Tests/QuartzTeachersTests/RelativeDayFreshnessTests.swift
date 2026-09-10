import XCTest
@testable import QuartzTeachers

/// "Tomorrow" means the day it is SAID, and a plan means the day it NAMED.
///
/// Both at once, which is the whole difficulty. The runner used to store the
/// day it was built on — one runner per conversation, one per `--mcp-stdio`
/// process — so a window left open across midnight published the class after
/// the day the conversation BEGAN, said "Published the class on …" and was
/// wrong about which. Reading the clock afresh fixes that and, on its own,
/// breaks the other half: plan mode reads one set of arguments twice, so a
/// word still carried at Go time is read again against a clock that has moved,
/// and a plan shown at 23:59 publishes something else at 00:01.
///
/// So the word is settled ONCE, where the call is made, and the clock is read
/// afresh everywhere else. Issue #143, from the Windows side.
@MainActor
final class RelativeDayFreshnessTests: XCTestCase {

    // MARK: - What a teacher asks for, and what they then agree to

    /// The card holds a DATE, not the word the teacher typed.
    func testTheWordIsSettledBeforeTheTeacherIsAsked() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(
            page: "Unit 1, Day 1", publish: "false", date: "2026-09-09", body: "one",
            in: made.course
        )

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner)
        await agent.say("publish tomorrow's class")

        let pending: AssistAgent.PendingApproval = try XCTUnwrap(agent.pendingApproval)
        XCTAssertEqual(
            pending.call.argumentValues["when"] as? String, "2026-09-09",
            "The waiting call carries the day it settled on, not the word it was sent"
        )
    }

    /// The midnight crossing: the plan named the 9th, so Go publishes the 9th,
    /// however long the card waited.
    func testApprovingAfterMidnightPublishesTheDayThePlanNamed() async throws {
        let clock: AssistFixture.TestClock = AssistFixture.TestClock(
            CalendarDay(year: 2026, month: 9, day: 8)!
        )
        let made = try AssistFixture.makeRunner(clock: clock)
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(
            page: "Unit 1, Day 1", publish: "false", date: "2026-09-09", body: "one",
            in: made.course
        )
        try AssistFixture.write(
            page: "Unit 1, Day 2", publish: "false", date: "2026-09-10", body: "two",
            in: made.course
        )

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner)
        await agent.say("publish tomorrow's class")
        XCTAssertNotNil(agent.pendingApproval, "Plan mode is on, so this waits")

        // The teacher leaves the card on screen, and the day turns.
        clock.day = CalendarDay(year: 2026, month: 9, day: 9)!
        await agent.approvePending()

        XCTAssertTrue(
            try published("Unit 1, Day 1", in: made.course),
            "The class the plan described is the class that was published"
        )
        XCTAssertFalse(
            try published("Unit 1, Day 2", in: made.course),
            "The class that was 'tomorrow' by the time Go was pressed is untouched"
        )
    }

    // MARK: - The clock is read afresh

    /// The same runner, the same word, two different days — which is the MCP
    /// process's case, where each request is its own resolution and there is
    /// no card in between.
    func testTheSameWordMeansADifferentDayTheNextDay() async throws {
        let clock: AssistFixture.TestClock = AssistFixture.TestClock(
            CalendarDay(year: 2026, month: 9, day: 8)!
        )
        let made = try AssistFixture.makeRunner(clock: clock)
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(
            page: "Unit 1, Day 1", publish: "false", date: "2026-09-09", body: "one",
            in: made.course
        )
        try AssistFixture.write(
            page: "Unit 1, Day 2", publish: "false", date: "2026-09-10", body: "two",
            in: made.course
        )

        _ = await made.runner.run(call: publishTomorrow())
        XCTAssertTrue(try published("Unit 1, Day 1", in: made.course))
        XCTAssertFalse(try published("Unit 1, Day 2", in: made.course))

        clock.day = CalendarDay(year: 2026, month: 9, day: 9)!
        _ = await made.runner.run(call: publishTomorrow())
        XCTAssertTrue(
            try published("Unit 1, Day 2", in: made.course),
            "A runner that outlives a day counts tomorrow from the day it is asked"
        )
    }

    // MARK: - What settling touches, and what it leaves alone

    func testADeployTimeIsNotMistakenForADay() throws {
        let deploy: AssistToolDefinition = try XCTUnwrap(tool(named: "schedule_deploy"))
        let arguments: [String: Any] = ["when": "2026-09-09 06:30"]
        let settled: [String: Any] = AssistToolRunner.settlingTheClassDay(
            in: arguments, forTool: deploy, today: CalendarDay(year: 2026, month: 9, day: 8)!
        )
        XCTAssertEqual(
            settled["when"] as? String, "2026-09-09 06:30",
            "A deploy's `when` is a day AND a time, and no business of this"
        )
    }

    func testADateAlreadyGivenAsADateIsUnchanged() throws {
        let settled: [String: Any] = try settle(["date": "2026-10-01"])
        XCTAssertEqual(settled["date"] as? String, "2026-10-01")
    }

    func testAWordItCannotReadIsLeftForTheRunnerToRefuse() throws {
        let settled: [String: Any] = try settle(["date": "next monday"])
        XCTAssertEqual(
            settled["date"] as? String, "next monday",
            "Left exactly as it arrived, so the teacher still gets the runner's own refusal"
        )
    }

    /// Both keys settle, and `date` still wins — the precedence `classPlan`
    /// reads them in. Pinned because settling reads BOTH and the runner reads
    /// ONE, and nothing else says those two orders must agree.
    func testTheDateIsPreferredToTheCardsWord() throws {
        let settled: [String: Any] = try settle(["date": "2026-10-01", "when": "tomorrow"])
        XCTAssertEqual(settled["date"] as? String, "2026-10-01", "The date the caller gave stands")
        XCTAssertEqual(settled["when"] as? String, "2026-09-09", "And the word beside it is still read")
    }

    /// The list of what carries a class day is the TOOL SURFACE, not a list
    /// kept beside it — so a tool added later cannot be quietly left out.
    func testEveryToolThatTakesAClassDateHasItSettled() throws {
        var checked: Int = 0
        for tool in AssistToolRunner.mcpTools where tool.parameters["date"] != nil {
            let settled: [String: Any] = AssistToolRunner.settlingTheClassDay(
                in: ["date": "tomorrow"], forTool: tool,
                today: CalendarDay(year: 2026, month: 9, day: 8)!
            )
            XCTAssertEqual(
                settled["date"] as? String, "2026-09-09",
                "\(tool.name) takes a class date and must have it settled"
            )
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "Something declares a class date, or this test is asleep")
    }

    // MARK: - Private

    private func settle(_ arguments: [String: Any]) throws -> [String: Any] {
        let publishing: AssistToolDefinition = try XCTUnwrap(tool(named: "publish_class_on"))
        return AssistToolRunner.settlingTheClassDay(
            in: arguments, forTool: publishing, today: CalendarDay(year: 2026, month: 9, day: 8)!
        )
    }

    /// The tool by that name, out of everything either client may call.
    private func tool(named name: String) -> AssistToolDefinition? {
        for tool in AssistToolRunner.mcpTools where tool.name == name {
            return tool
        }
        return nil
    }

    private func publishTomorrow() -> AssistToolCall {
        let arguments: [String: Any] = ["course": "ICS3U", "section": 1, "when": "tomorrow"]
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(
                name: "publish_class_on",
                arguments: String(data: encoded, encoding: .utf8) ?? "{}"
            )
        )
    }

    private func published(_ title: String, in course: Course) throws -> Bool {
        let text: String = try String(
            contentsOf: AssistFixture.pageURL(of: title, in: course), encoding: .utf8
        )
        return text.contains("publish: true")
    }
}
