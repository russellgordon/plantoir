import XCTest
@testable import QuartzTeachers

/// "Deploy at 6:30 AM" — the sentence the shelf offers, answered in code.
///
/// **Why this file exists.** The smaller assistant sent that sentence to
/// `deploy_section` ten trials out of ten and three times out of three in the
/// app itself, so a teacher who asked for half six tomorrow got a deploy to
/// students on the spot (`research/ai-assist/metal-routing-results.txt`, issue
/// #168). The fix is a parsed family that never reaches the model, and the
/// half of it that matters is the REFUSALS: a family that swallowed a spelling
/// it could not read would schedule a deploy at a time nobody chose.
///
/// Every case is read from `contracts/assist-cases.json` → `deployAtATime`,
/// which the Windows suite runs too. Nothing is typed here that could disagree
/// with it.
@MainActor
final class ScheduleDeployCardTests: XCTestCase {

    // MARK: - The grammar

    /// Every spelling the contract says is answered in code, is.
    func testDeployAtATimeIsAnsweredInCode() throws {
        for row in try ScheduleDeployCardTests.rows(named: "accepted") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            let command: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(input),
                "\"\(input)\" is in the contract as answered in code and matches nothing"
            )
            XCTAssertEqual(command.toolName, "schedule_deploy", input)
            XCTAssertEqual(command.arguments["when"], row["expectWhen"] as? String, input)
            // A card cannot honour another section, so it must never carry one.
            XCTAssertNil(command.arguments["section"], input)
            XCTAssertNil(command.arguments["course"], input)
        }
    }

    /// And every spelling it says goes to the model, does.
    ///
    /// The half that stops the family widening. A sentence that merely LOOKS
    /// like this one — a condition in it, a section named, an hour nobody can
    /// place at morning or evening — must fall through, because answering the
    /// wrong question with total confidence is worse than routing it.
    func testATimeThatCouldMeanTwoThingsGoesToTheModel() throws {
        for row in try ScheduleDeployCardTests.rows(named: "refused") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is refused for no stated reason")
            XCTAssertNil(
                AssistCardCommand.matching(input),
                "\"\(input)\" is in the contract as one that goes to the model and was matched in code"
            )
        }
    }

    // MARK: - Settling the moment

    /// The bare time becomes a whole moment, once, against an injected clock.
    ///
    /// Injected on purpose: the rule is "the next such time, counting today
    /// while it is still to come", and a test that read the machine's own
    /// clock would be a different test depending on when it ran. The time zone
    /// travels with the case for the same reason.
    func testTheMomentIsSettledAgainstTheRunnersClock() throws {
        for row in try ScheduleDeployCardTests.rows(named: "resolving") {
            let when: String = try XCTUnwrap(row["when"] as? String)
            let today: CalendarDay = try XCTUnwrap(CalendarDay(text: try XCTUnwrap(row["today"] as? String)))
            let zone: TimeZone = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(row["timeZone"] as? String)))
            let now: Date = try XCTUnwrap(
                ScheduleDeployCardTests.moment(try XCTUnwrap(row["now"] as? String), in: zone)
            )

            let settled: String? = AssistToolRunner.momentText(
                forTimeOfDay: when, today: today, now: now, timeZone: zone
            )
            XCTAssertEqual(settled, row["expectMoment"] as? String, "\(when) at \(now)")
        }
    }

    /// A wall time that does not exist settles onto one that does.
    ///
    /// **The one night a year this matters.** Clocks go forward at 02:00 on
    /// 8 March 2026 in Toronto, so 02:30 that morning never happens. Joining
    /// the day to the time would hand back "2026-03-08 02:30", which
    /// `moment(named:)` — the app's own reader — cannot read: the trail line
    /// would quietly lose its moment, the approval card would print the raw
    /// text instead of a weekday and a time, and approving it would fail with
    /// the app calling its own output unreadable. Building the text from the
    /// INSTANT is what makes "a settled moment always reads back" true rather
    /// than intended.
    ///
    /// A mac test rather than a contract row: the shift is what this
    /// platform's calendar does, and .NET throws on an invalid wall time
    /// instead — so the rule is named in the Windows handover as a trap for
    /// them to meet deliberately, rather than asserted as agreed behaviour
    /// before they have seen it.
    func testATimeThatDoesNotExistThatNightSettlesOntoOneThatDoes() throws {
        let zone: TimeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let springForward: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-03-08"))
        let beforeItJumps: Date = try XCTUnwrap(
            ScheduleDeployCardTests.moment("2026-03-08 01:00", in: zone)
        )

        let settled: String = try XCTUnwrap(AssistToolRunner.momentText(
            forTimeOfDay: "02:30", today: springForward, now: beforeItJumps, timeZone: zone
        ))
        XCTAssertEqual(settled, "2026-03-08 03:30")
        XCTAssertNotNil(
            ScheduleDeployCardTests.moment(settled, in: zone),
            "whatever comes out has to read back, or the card and the trail lose it"
        )

        // The explicit day word takes the same road, so the two cannot differ.
        let saidToday: String = try XCTUnwrap(AssistToolRunner.momentText(
            forTimeOfDay: "today 02:30", today: springForward, now: beforeItJumps, timeZone: zone
        ))
        XCTAssertEqual(saidToday, "2026-03-08 03:30")

        // …and so does "tomorrow", asked the evening before.
        let theNightBefore: Date = try XCTUnwrap(
            ScheduleDeployCardTests.moment("2026-03-07 22:00", in: zone)
        )
        let saidTomorrow: String = try XCTUnwrap(AssistToolRunner.momentText(
            forTimeOfDay: "tomorrow 02:30",
            today: try XCTUnwrap(CalendarDay(text: "2026-03-07")),
            now: theNightBefore, timeZone: zone
        ))
        XCTAssertEqual(saidTomorrow, "2026-03-08 03:30")
    }

    /// Every settled moment reads back, whatever the zone or the row.
    ///
    /// The invariant the trail line and the approval card both rest on, run
    /// across the contract's own `resolving` rows rather than asserted in
    /// prose: `matchedInCodeLine` appends a moment only when `moment(named:)`
    /// can read it, and `explain` names a weekday only then too.
    func testEverySettledMomentReadsBack() throws {
        for row in try ScheduleDeployCardTests.rows(named: "resolving") {
            let when: String = try XCTUnwrap(row["when"] as? String)
            let today: CalendarDay = try XCTUnwrap(CalendarDay(text: try XCTUnwrap(row["today"] as? String)))
            let zone: TimeZone = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(row["timeZone"] as? String)))
            let now: Date = try XCTUnwrap(
                ScheduleDeployCardTests.moment(try XCTUnwrap(row["now"] as? String), in: zone)
            )
            guard let settled = AssistToolRunner.momentText(
                forTimeOfDay: when, today: today, now: now, timeZone: zone
            ) else {
                continue
            }
            XCTAssertNotNil(
                ScheduleDeployCardTests.moment(settled, in: zone),
                "\(when) settled onto \(settled), which cannot be read back"
            )
        }
    }

    /// Settling twice changes nothing — which is what lets the agent settle a
    /// call, write its trail line from the settled arguments, and hand the
    /// same call on without reading the clock a second time.
    func testSettlingAnAlreadySettledMomentChangesNothing() throws {
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-19"))
        let zone: TimeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now: Date = try XCTUnwrap(ScheduleDeployCardTests.moment("2026-09-19 09:00", in: zone))

        let once: String = try XCTUnwrap(
            AssistToolRunner.momentText(forTimeOfDay: "06:30", today: today, now: now, timeZone: zone)
        )
        XCTAssertNil(
            AssistToolRunner.momentText(forTimeOfDay: once, today: today, now: now, timeZone: zone),
            "a whole moment must be handed back untouched, or the second settling moves it"
        )
    }

    /// The settler is chosen by the TOOL's own schema, not by a list kept
    /// beside it: a moment for the tools that declare `when` and no `date`,
    /// and nothing at all for the tool that takes a class day.
    func testOnlyTheToolsThatTakeAMomentAreSettled() throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-19"))
        let zone: TimeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now: Date = try XCTUnwrap(ScheduleDeployCardTests.moment("2026-09-19 09:00", in: zone))

        let scheduling: AssistToolDefinition = try XCTUnwrap(made.runner.definition(named: "schedule_deploy"))
        let settled: [String: Any] = AssistToolRunner.settlingTheDeployMoment(
            in: ["when": "06:30"], forTool: scheduling, today: today, now: now, timeZone: zone
        )
        XCTAssertEqual(settled["when"] as? String, "2026-09-20 06:30")

        // `publish_class_on`'s `when` is a class DAY. It must be left for the
        // day settler, and it is excluded by construction — the tool declares
        // `date`, so this one never looks at it.
        let publishing: AssistToolDefinition = try XCTUnwrap(made.runner.definition(named: "publish_class_on"))
        let untouched: [String: Any] = AssistToolRunner.settlingTheDeployMoment(
            in: ["when": "tomorrow"], forTool: publishing, today: today, now: now, timeZone: zone
        )
        XCTAssertEqual(untouched["when"] as? String, "tomorrow")
    }

    // MARK: - What the teacher and the trail see

    /// The card comes up, names the moment, and nothing is scheduled until a
    /// button is pressed.
    func testTheCardStillAsksBeforeAnythingIsScheduled() async throws {
        let made = try AssistFixture.makeRunner(hasDeployedBefore: true)
        let launchAgents: URL = made.root.appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = launchAgents
        defer {
            ScheduledDeploy.launchAgentsDirectoryOverride = nil
            try? FileManager.default.removeItem(at: made.root)
        }

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner)
        await agent.say("Deploy at 6:30 AM")

        let pending: AssistAgent.PendingApproval = try XCTUnwrap(
            agent.pendingApproval, "the sentence was answered in code and must still ask first"
        )
        XCTAssertEqual(pending.call.function.name, "schedule_deploy")
        // The fixture pins today to 2026-09-08 and the clock is the real one,
        // so 6:30 that morning has gone and the next such time is the 9th.
        // The DAY varies with the fixture; the rule does not.
        XCTAssertEqual(pending.call.argumentValues["when"] as? String, "2026-09-09 06:30")
        XCTAssertTrue(
            pending.explanation.contains("Section 1"),
            "the scheduled card names the section, the destination and the moment: \(pending.explanation)"
        )
        XCTAssertNotEqual(
            pending.explanation, AssistWording.deployApproval,
            "this is the card that names a moment, not the immediate one"
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: launchAgents.path), [],
            "nothing may be scheduled before the teacher presses the button"
        )

        agent.declinePending()
        XCTAssertNil(agent.pendingApproval)
    }

    /// The trail line carries the MOMENT the app settled on.
    ///
    /// The resolution today-or-tomorrow is a guess made in code, and the
    /// conversation is not on the trail — so without this, a teacher writing
    /// in to say "it went out on Saturday, I meant Friday" leaves a record of
    /// their sentence and of the tool, and nothing about the day that was
    /// chosen. The line is NAMED rather than typed here, the way every
    /// sentence is: `AssistAgent.matchedInCodeLine` is the one copy of it.
    func testTheTrailLineNamesTheMomentItSettledOn() async throws {
        let made = try AssistFixture.makeRunner(hasDeployedBefore: true)
        let scratch: URL = made.root.appendingPathComponent("trail", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: made.root)
        }

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner)
        await agent.say("Deploy at 6:30 AM")
        let pending: AssistAgent.PendingApproval = try XCTUnwrap(agent.pendingApproval)

        let expected: String = AssistAgent.matchedInCodeLine(for: pending.call)
        XCTAssertTrue(
            expected.contains("2026-09-09 06:30"),
            "the line has to carry the whole moment, not the time the teacher typed: \(expected)"
        )
        XCTAssertTrue(
            ActivityTrail.store.activityText(includingPrompts: true).contains(expected),
            "the trail does not carry the line the app builds for this: \(expected)"
        )

        agent.declinePending()
    }

    /// A phrasing that names no time leaves the line it always left. The
    /// moment is added only when there is one, so the existing families read
    /// exactly as they did.
    func testALineForAPhrasingWithNoTimeInItIsUnchanged() throws {
        let call: AssistToolCall = AssistToolCall(
            id: "1", type: "function",
            function: AssistToolCall.Function(name: "deploy_section", arguments: "{}")
        )
        let line: String = AssistAgent.matchedInCodeLine(for: call)
        XCTAssertTrue(line.contains("deploy_section"))
        XCTAssertFalse(line.contains(" for "), line)

        // …and a `when` that is a class DAY rather than a moment adds nothing
        // either: only a whole moment is ever written.
        let publishing: AssistToolCall = AssistToolCall(
            id: "2", type: "function",
            function: AssistToolCall.Function(
                name: "publish_class_on", arguments: "{\"when\":\"2026-09-09\"}"
            )
        )
        XCTAssertFalse(AssistAgent.matchedInCodeLine(for: publishing).contains(" for "))
    }

    // MARK: - Reading the contract

    private static func rows(named key: String) throws -> [[String: Any]] {
        let family: [String: Any] = try XCTUnwrap(
            contract()["deployAtATime"] as? [String: Any],
            "contracts/assist-cases.json has no deployAtATime"
        )
        XCTAssertNotNil(family["note"] as? String)
        let rows: [[String: Any]] = try XCTUnwrap(family[key] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty, "\(key) has been emptied out")
        return rows
    }

    private static func contract() throws -> [String: Any] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(
            contentsOf: repository.appendingPathComponent("contracts")
                .appendingPathComponent(AssistContract.casesFileName)
        )
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// "2026-09-19 09:00" in a named zone — the contract's own spelling, read
    /// the same way the app reads a settled moment.
    private static func moment(_ text: String, in zone: TimeZone) -> Date? {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)
    }
}
