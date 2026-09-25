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
            // Refused means neither answered NOR asked about (issue #194):
            // "deploy at 0:30" and "deploy at 7" keep their written reasons.
            XCTAssertNil(
                AssistCardCommand.morningOrEvening(input),
                "\"\(input)\" is in the contract as one that goes to the model and was asked about in code"
            )
            // …nor given a spelling to use (issue #277): "deploy at 13.30 pm"
            // and "deploy at 18:30 in the morning" keep their written reasons.
            XCTAssertNil(
                AssistCardCommand.timeToSayAs(input),
                "\"\(input)\" is in the contract as one that goes to the model and was given a spelling in code"
            )
        }
    }

    /// A time that is morning or evening is ASKED about, in code — and the two
    /// sentences the question names are both answered by the family, to the
    /// `when` the contract says (issue #194).
    ///
    /// **Both halves or neither, pinned.** A question that suggested a
    /// sentence the matcher then refused would send the teacher's answer to
    /// the model — the very thing the question exists to prevent — so every
    /// suggested answer is run through `matching` here rather than trusted.
    func testATimeThatIsMorningOrEveningIsAskedAboutAndItsAnswersAreUnderstood() throws {
        for row in try ScheduleDeployCardTests.rows(named: "asked") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is asked about for no stated reason")
            XCTAssertNil(
                AssistCardCommand.matching(input),
                "\"\(input)\" is in the contract as asked about, and was scheduled without asking"
            )
            let question: AssistTimeQuestion = try XCTUnwrap(
                AssistCardCommand.morningOrEvening(input),
                "\"\(input)\" is in the contract as asked about, and nothing asked"
            )
            XCTAssertNil(
                AssistCardCommand.timeToSayAs(input),
                "\"\(input)\" is in the contract as asked about, and was also given a spelling"
            )
            XCTAssertEqual(question.clock, row["expectClock"] as? String, input)
            XCTAssertEqual(question.sayMorning, row["expectSayMorning"] as? String, input)
            XCTAssertEqual(question.sayEvening, row["expectSayEvening"] as? String, input)

            let morning: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(question.sayMorning),
                "the question for \"\(input)\" suggests \"\(question.sayMorning)\", which matches nothing"
            )
            XCTAssertEqual(morning.toolName, "schedule_deploy", input)
            XCTAssertEqual(morning.arguments["when"], row["expectMorningWhen"] as? String, input)

            let evening: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(question.sayEvening),
                "the question for \"\(input)\" suggests \"\(question.sayEvening)\", which matches nothing"
            )
            XCTAssertEqual(evening.toolName, "schedule_deploy", input)
            XCTAssertEqual(evening.arguments["when"], row["expectEveningWhen"] as? String, input)
        }
    }

    /// A time the family answers is never ALSO asked about. The two tables
    /// cannot overlap, or the order of two `if`s in `AssistAgent.say` would
    /// decide what a teacher gets.
    func testATimeThatIsAnsweredIsNeverAlsoAskedAbout() throws {
        for row in try ScheduleDeployCardTests.rows(named: "accepted") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNil(AssistCardCommand.morningOrEvening(input), input)
            XCTAssertNil(AssistCardCommand.timeToSayAs(input), input)
        }
    }

    /// A time the family can read but does not set is answered with the ONE
    /// sentence to type — and that sentence is answered by the family, to the
    /// `when` the contract says (issue #277).
    ///
    /// Every row runs through the REAL matcher twice: once to show the
    /// teacher's own sentence is neither scheduled nor asked about, and once
    /// for the sentence handed back, so the reply can never name a sentence the
    /// app then fails to understand — the failure that would send the
    /// teacher's next turn to the model.
    func testATimeTheAppCanReadButNotSetIsAnsweredWithTheSpellingToUse() throws {
        for row in try ScheduleDeployCardTests.rows(named: "sayItAs") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is given a spelling for no stated reason")
            XCTAssertNil(
                AssistCardCommand.matching(input),
                "\"\(input)\" is in the contract as given a spelling, and was scheduled as written"
            )
            XCTAssertNil(
                AssistCardCommand.morningOrEvening(input),
                "\"\(input)\" is in the contract as given a spelling, and was asked about instead"
            )
            let respelling: AssistTimeRespelling = try XCTUnwrap(
                AssistCardCommand.timeToSayAs(input),
                "\"\(input)\" is in the contract as given a spelling, and none was given"
            )
            XCTAssertEqual(respelling.written, row["expectWritten"] as? String, input)
            XCTAssertEqual(respelling.say, row["expectSay"] as? String, input)
            XCTAssertEqual("\(respelling.onlyDifference)", row["expectOnlyDifference"] as? String, input)

            let handedBack: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(respelling.say),
                "the reply to \"\(input)\" names \"\(respelling.say)\", which matches nothing"
            )
            XCTAssertEqual(handedBack.toolName, "schedule_deploy", input)
            XCTAssertEqual(handedBack.arguments["when"], row["expectWhen"] as? String, input)
            XCTAssertNil(handedBack.arguments["section"], input)
            XCTAssertNil(handedBack.arguments["course"], input)
        }
    }

    /// The family's lists, by name. A list added to the contract that this
    /// suite does not read would be a list nothing tests — so adding one fails
    /// here until a test reads it.
    func testEveryListInTheFamilyIsReadByThisSuite() throws {
        let family: [String: Any] = try XCTUnwrap(
            ScheduleDeployCardTests.contract()["deployAtATime"] as? [String: Any]
        )
        var keys: [String] = []
        for key in family.keys {
            keys.append(key)
        }
        XCTAssertEqual(
            keys.sorted(),
            ["accepted", "asked", "note", "refused", "resolving", "sayItAs"]
        )
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
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            launchAgents.deletingLastPathComponent().appendingPathComponent("scheduled")
        defer {
            ScheduledDeploy.launchAgentsDirectoryOverride = nil
            ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
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
        // The scheduled card reads whether a deploy is already set for the
        // section (issue #195); it must read a folder this test owns, never
        // the real ~/Library/LaunchAgents of whoever runs the suite.
        let launchAgents: URL = made.root.appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = launchAgents
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            launchAgents.deletingLastPathComponent().appendingPathComponent("scheduled")
        defer {
            ScheduledDeploy.launchAgentsDirectoryOverride = nil
            ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        }
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

    /// "Deploy at 6:30" is asked about, and the model is never consulted —
    /// not on that turn, and not on the next one either (issue #194).
    ///
    /// The engine here is a real HTTP stub, so consulting it shows up as a
    /// request — on the smaller assistant that consultation was measured
    /// ending in an IMMEDIATE deploy for this shape of sentence. The turn after
    /// the question is an unrelated one that DOES go to the model, and what
    /// the model is sent then must not carry "6:30": appending the question or
    /// the teacher's sentence to the conversation "for context" would let the
    /// model act on it a turn later.
    func testAMorningOrEveningTimeIsAskedInCodeAndNeverReachesTheModel() async throws {
        let made = try AssistFixture.makeRunner(hasDeployedBefore: true)
        let launchAgents: URL = made.root.appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = launchAgents
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            launchAgents.deletingLastPathComponent().appendingPathComponent("scheduled")
        let scratch: URL = made.root.appendingPathComponent("trail", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        let engine: StubEngine = try StubEngine()
        defer {
            engine.stop()
            ActivityTrail.store = previousStore
            ScheduledDeploy.launchAgentsDirectoryOverride = nil
            ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
            try? FileManager.default.removeItem(at: made.root)
        }
        // Only the unrelated turn is meant to reach it. Were the question turn
        // to reach it too, `requestCount` below says so.
        engine.serve(ScheduleDeployCardTests.plainReply("Publishing makes a page visible to students."))

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        let messagesBefore: Int = agent.messages.count
        await agent.say("deploy at 6:30")

        XCTAssertEqual(engine.requestCount, 0, "the model was asked about a time the app asks the teacher about")
        XCTAssertEqual(agent.messages.count, messagesBefore, "the sentence or the question reached the model's conversation")
        XCTAssertNil(agent.pendingApproval, "a card went up for a time nobody has placed at morning or evening")
        let last: AssistAgent.Entry = try XCTUnwrap(agent.entries.last)
        XCTAssertEqual(last.speaker, .assistant)
        let question: AssistTimeQuestion = try XCTUnwrap(AssistCardCommand.morningOrEvening("deploy at 6:30"))
        XCTAssertEqual(
            last.text,
            AssistWording.morningOrEvening(
                clock: question.clock, sayMorning: question.sayMorning, sayEvening: question.sayEvening
            )
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: launchAgents.path), [],
            "nothing may be scheduled by a question"
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(AssistAgent.askedMorningOrEveningLine), trail)

        // The next turn goes to the model, and carries nothing of the last one.
        await agent.say("what does publishing mean here, in a few words")
        for body in engine.requestBodies {
            let sent: String = String(describing: body["messages"] ?? "")
            XCTAssertFalse(sent.contains("6:30"), "the model was sent the earlier time: \(sent)")
            XCTAssertFalse(sent.contains("morning or in the evening"), "the model was sent the question: \(sent)")
        }

        // And the answer the question names is understood, in code, with no model.
        let requestsSoFar: Int = engine.requestCount
        await agent.say(question.sayEvening)
        XCTAssertEqual(engine.requestCount, requestsSoFar, "the suggested answer went to the model")
        let pending: AssistAgent.PendingApproval = try XCTUnwrap(agent.pendingApproval)
        XCTAssertEqual(pending.call.function.name, "schedule_deploy")
        let when: String = try XCTUnwrap(pending.call.argumentValues["when"] as? String)
        XCTAssertTrue(when.hasSuffix("18:30"), when)
        agent.declinePending()
    }

    /// "Deploy at 6.30 pm" is answered in code with the spelling to use, and
    /// neither the sentence nor the reply reaches the model — on this turn or
    /// any later one (issue #277). The same proof as the morning-or-evening
    /// test above, for the same reason: sent to the model, this sentence was
    /// a deploy to students on the spot, ten trials out of ten.
    func testATimeWrittenAWayTheAppDoesNotSetIsAnsweredInCodeAndNeverReachesTheModel() async throws {
        let made = try AssistFixture.makeRunner(hasDeployedBefore: true)
        let launchAgents: URL = made.root.appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = launchAgents
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            launchAgents.deletingLastPathComponent().appendingPathComponent("scheduled")
        let scratch: URL = made.root.appendingPathComponent("trail", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        let engine: StubEngine = try StubEngine()
        defer {
            engine.stop()
            ActivityTrail.store = previousStore
            ScheduledDeploy.launchAgentsDirectoryOverride = nil
            ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
            try? FileManager.default.removeItem(at: made.root)
        }
        engine.serve(ScheduleDeployCardTests.plainReply("Publishing makes a page visible to students."))

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        let messagesBefore: Int = agent.messages.count
        await agent.say("deploy at 6.30 pm")

        XCTAssertEqual(engine.requestCount, 0, "the model was sent a time the app answers with a spelling")
        XCTAssertEqual(agent.messages.count, messagesBefore, "the sentence or the reply reached the model's conversation")
        XCTAssertNil(agent.pendingApproval, "a card went up for a time the app does not set as written")
        let last: AssistAgent.Entry = try XCTUnwrap(agent.entries.last)
        XCTAssertEqual(last.speaker, .assistant)
        let respelling: AssistTimeRespelling = try XCTUnwrap(AssistCardCommand.timeToSayAs("deploy at 6.30 pm"))
        XCTAssertEqual(
            last.text,
            AssistWording.sayTheTimeAs(
                written: respelling.written, say: respelling.say, onlyDifference: respelling.onlyDifference
            )
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: launchAgents.path), [],
            "nothing may be scheduled by a reply"
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(AssistAgent.askedToSayTheTimeAsLine), trail)

        // The next turn goes to the model, and carries nothing of the last one.
        await agent.say("what does publishing mean here, in a few words")
        XCTAssertEqual(engine.requestCount, 1, "the unrelated turn did not reach the model")
        for body in engine.requestBodies {
            let sent: String = String(describing: body["messages"] ?? "")
            XCTAssertFalse(sent.contains("6.30"), "the model was sent the earlier time: \(sent)")
            XCTAssertFalse(sent.contains("6:30"), "the model was sent the spelling: \(sent)")
            XCTAssertFalse(sent.contains("Nothing is set yet"), "the model was sent the reply: \(sent)")
        }

        // And the sentence the reply names is understood, in code, with no model.
        let requestsSoFar: Int = engine.requestCount
        await agent.say(respelling.say)
        XCTAssertEqual(engine.requestCount, requestsSoFar, "the suggested sentence went to the model")
        let pending: AssistAgent.PendingApproval = try XCTUnwrap(agent.pendingApproval)
        XCTAssertEqual(pending.call.function.name, "schedule_deploy")
        let when: String = try XCTUnwrap(pending.call.argumentValues["when"] as? String)
        XCTAssertTrue(when.hasSuffix("18:30"), when)
        agent.declinePending()
    }

    private static func plainReply(_ said: String) -> String {
        return #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":""#
            + said + #""}}],"usage":{"completion_tokens":4}}"#
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
