import XCTest
@testable import QuartzTeachers

/// Plan mode is what makes a router that is sometimes wrong safe to hand a
/// teacher. Each rule here is a decision about how much to trust the model on
/// a given Mac, so each is pinned.
@MainActor
final class AssistPlanModeTests: XCTestCase {

    // MARK: - Stored properties

    /// The writes with nothing to plan, and why. Listed here so that adding
    /// another is a decision somebody makes on purpose.
    private let ownReversal: Set<String> = [
        "rebuild_preview",         // changes no page
        "undo_last_change",        // IS the undo
        "deploy_section",          // waits on its own button already
        "cancel_scheduled_deploy", // remedied by scheduling it again
        "back_up_course",          // writes a zip beside the course, changes no page, and is its own safety net
    ]

    // MARK: - Functions

    private func makeDefaults() -> UserDefaults {
        let suite: String = "AssistPlanModeTests-\(UUID().uuidString)"
        let defaults: UserDefaults = UserDefaults(suiteName: suite)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }

    // MARK: - The small tier

    /// **Both assistants behave identically.** Same default, same count, same
    /// mention, same switch.
    ///
    /// The smaller one used to refuse to be turned off and was never told the
    /// setting existed, on the reasoning that one request in five going wrong
    /// is not a rate at which anybody should stop reading. That withheld a
    /// setting from exactly the machine where knowing about it matters most.
    /// The measured number is put in front of the teacher as a caution
    /// instead, which respects the measurement and the person.
    func testBothAssistantsFollowTheSameRules() {
        for tier in AssistModelTier.allCases {
            let mode: AssistPlanMode = AssistPlanMode(
                tier: tier, settings: AppSettings(defaults: makeDefaults())
            )
            XCTAssertTrue(mode.isOn, "\(tier) should ask by default")

            for _ in 0..<(AssistPlanMode.plansBeforeMentioningTheSetting - 1) {
                mode.recordAccepted()
            }
            XCTAssertFalse(mode.shouldOfferToStop, "\(tier): fourteen is not fifteen")

            mode.recordAccepted()
            XCTAssertTrue(mode.shouldOfferToStop,
                          "\(tier) was never told the setting exists")

            mode.stopAsking()
            XCTAssertFalse(mode.isOn, "\(tier) refused to be turned off")
        }
    }

    /// An answer given in Settings is honoured on both assistants — the
    /// teacher decides, whichever one is running.
    func testTheSettingIsHonouredOnBothAssistants() {
        let defaults: UserDefaults = makeDefaults()
        defaults.set(false, forKey: AppSettings.assistantAsksBeforeChangingKey)
        XCTAssertFalse(AssistPlanMode(tier: .small, settings: AppSettings(defaults: defaults)).isOn)
        XCTAssertFalse(AssistPlanMode(tier: .large, settings: AppSettings(defaults: defaults)).isOn)
    }

    // MARK: - The large tier

    func testPlansAreShownUntilATeacherSaysOtherwise() {
        let mode: AssistPlanMode = AssistPlanMode(tier: .large, settings: AppSettings(defaults: makeDefaults()))
        XCTAssertTrue(mode.isOn, "Plans are shown until a teacher says otherwise")
    }

    /// One sentence for both assistants, and it names where to change it.
    func testTheExplanationIsTheSameOnBothAndPointsAtTheSetting() {
        for tier in AssistModelTier.allCases {
            let mode: AssistPlanMode = AssistPlanMode(
                tier: tier, settings: AppSettings(defaults: makeDefaults())
            )
            XCTAssertTrue(mode.explanation.contains("Settings"), "\(tier): \(mode.explanation)")
            XCTAssertFalse(mode.explanation.contains("always shows"),
                           "\(tier) still claims it always shows plans: \(mode.explanation)")
        }
    }

    /// Fifteen, and only once — the mention is about DISCOVERABILITY, and a
    /// suggestion declined is an answer.
    func testTheSettingIsMentionedAfterFifteenAndOnlyOnce() {
        let mode: AssistPlanMode = AssistPlanMode(tier: .large, settings: AppSettings(defaults: makeDefaults()))

        for _ in 0..<(AssistPlanMode.plansBeforeMentioningTheSetting - 1) {
            mode.recordAccepted()
        }
        XCTAssertFalse(mode.shouldOfferToStop, "Fourteen is not yet fifteen")

        mode.recordAccepted()
        XCTAssertTrue(mode.shouldOfferToStop)

        mode.keepAsking()
        XCTAssertTrue(mode.isOn)
        XCTAssertFalse(mode.shouldOfferToStop, "Declining once means not being pestered again")
    }

    /// The count is APP-WIDE and outlives the conversation it was earned in.
    ///
    /// It used to reset with every window, so a teacher working in short
    /// bursts could accept a hundred plans across twenty conversations and
    /// never be told the setting existed.
    func testThePlanCountIsAppWideAndSurvivesANewConversation() {
        let defaults: UserDefaults = makeDefaults()
        let first: AssistPlanMode = AssistPlanMode(tier: .large, settings: AppSettings(defaults: defaults))
        for _ in 0..<10 {
            first.recordAccepted()
        }

        let second: AssistPlanMode = AssistPlanMode(tier: .large, settings: AppSettings(defaults: defaults))
        XCTAssertEqual(second.plansAccepted, 10, "The count reset when the window did")
        for _ in 0..<5 {
            second.recordAccepted()
        }
        XCTAssertTrue(second.shouldOfferToStop, "Ten plus five is fifteen, across two windows")
    }

    /// Once told, never told again — in any window, ever.
    func testOnceMentionedItIsNeverMentionedAgain() {
        let defaults: UserDefaults = makeDefaults()
        let first: AssistPlanMode = AssistPlanMode(tier: .large, settings: AppSettings(defaults: defaults))
        for _ in 0..<AssistPlanMode.plansBeforeMentioningTheSetting {
            first.recordAccepted()
        }
        XCTAssertTrue(first.shouldOfferToStop)
        first.noteOfferShown()

        let later: AssistPlanMode = AssistPlanMode(tier: .large, settings: AppSettings(defaults: defaults))
        for _ in 0..<50 {
            later.recordAccepted()
        }
        XCTAssertFalse(later.shouldOfferToStop,
                       "A teacher was told twice about the same setting")
    }

    /// A Cancel does not undo a plan already agreed to. The count measures how
    /// much of the assistant's work this teacher has READ, and a Cancel is
    /// evidence of reading rather than evidence against it.
    func testACancelDoesNotUndoPlansAlreadyAgreedTo() {
        let mode: AssistPlanMode = AssistPlanMode(tier: .large, settings: AppSettings(defaults: makeDefaults()))
        for _ in 0..<4 {
            mode.recordAccepted()
        }
        mode.recordCancelled()
        XCTAssertEqual(mode.plansAccepted, 4)
    }

    /// The answer outlives the window it was given in.
    func testTurningItOffIsRemembered() {
        let defaults: UserDefaults = makeDefaults()
        let first: AssistPlanMode = AssistPlanMode(tier: .large, settings: AppSettings(defaults: defaults))
        first.stopAsking()
        XCTAssertFalse(first.isOn)

        XCTAssertFalse(AssistPlanMode(tier: .large, settings: AppSettings(defaults: defaults)).isOn,
                       "A new conversation keeps the teacher's answer")

        first.keepAsking()
        XCTAssertTrue(AssistPlanMode(tier: .large, settings: AppSettings(defaults: defaults)).isOn,
                      "And keeps it when they change their mind back")
    }

    // MARK: - What plan mode gates

    /// Reads answer immediately; writes wait. Gating reads would make every
    /// question two clicks and train people to press Go without reading.
    ///
    /// Over the WHOLE surface — all thirty-two tools either client may call —
    /// since #327. It used to walk the twenty-two in `tools`, and the one
    /// write whose twin was named wrong lived in the other ten.
    func testOnlyWritesHaveAPlanTwin() {
        for tool in AssistToolRunner.mcpTools {
            if tool.readOnly {
                XCTAssertNil(tool.planTwinName, "\(tool.name) changes nothing, so it must not be gated")
            } else {
                XCTAssertNotNil(tool.planTwinName, "\(tool.name) changes pages and must be showable first")
            }
        }
    }

    /// Every write on the whole surface is either showable first or has
    /// nothing to plan — nothing in between.
    ///
    /// This test found a real bug when it was first written: `planTwinName`
    /// named a twin for every write, including four that have none, so plan
    /// mode would have asked the runner for `plan_rebuild_preview`, been told
    /// there is no such tool, and shown the teacher an error where their plan
    /// should be. Walking all thirty-two found the second (#327):
    /// `add_curriculum_mentions` named `plan_add_curriculum_mentions`, which
    /// does not exist, so the gate ran the write with no plan at all.
    func testEveryWriteIsEitherShowableOrItsOwnReversal() {
        var names: Set<String> = []
        for tool in AssistToolRunner.mcpTools {
            names.insert(tool.name)
        }

        for tool in AssistToolRunner.mcpTools where !tool.readOnly {
            if ownReversal.contains(tool.name) {
                continue
            }
            guard let twin = tool.planTwinName else {
                return XCTFail("\(tool.name) changes pages but cannot be shown first")
            }
            XCTAssertTrue(names.contains(twin),
                          "\(tool.name) would be gated behind \(twin), which does not exist — "
                          + "if its twin is named irregularly, list the pair in "
                          + "AssistToolDefinition.irregularPlanTwins")
        }
    }

    /// And those really are the only writes without a twin, so the list above
    /// cannot quietly fall out of step with the surface.
    func testNoOtherWriteIsMissingItsTwin() {
        var names: Set<String> = []
        for tool in AssistToolRunner.mcpTools {
            names.insert(tool.name)
        }
        var missing: [String] = []
        for tool in AssistToolRunner.mcpTools where !tool.readOnly {
            guard let twin = tool.planTwinName, names.contains(twin) else {
                missing.append(tool.name)
                continue
            }
        }
        XCTAssertEqual(
            Set(missing), ownReversal,
            "The set of writes with no plan twin changed — decide deliberately what plan mode does with the new one"
        )
    }

    /// The other direction: every `plan_` tool that exists is the twin of
    /// exactly one write. A twin nobody's name reaches is a plan the gate can
    /// never show — which is what `plan_curriculum_mentions` was until #327.
    func testEveryPlanToolIsSomeWritesTwin() {
        var twinOf: [String: [String]] = [:]
        for tool in AssistToolRunner.mcpTools where !tool.readOnly {
            if let twin = tool.planTwinName {
                twinOf[twin, default: []].append(tool.name)
            }
        }
        var planTools: Int = 0
        for tool in AssistToolRunner.mcpTools where tool.name.hasPrefix("plan_") {
            planTools += 1
            XCTAssertEqual(
                (twinOf[tool.name] ?? []).count, 1,
                "\(tool.name) is the twin of \(twinOf[tool.name] ?? []) — it must be exactly one write's, "
                + "or plan mode can never show it"
            )
        }
        XCTAssertGreaterThanOrEqual(planTools, 10)
    }

    /// The two irregular pairs, pinned so nobody "tidies" them.
    func testTheIrregularTwinsArePinned() {
        XCTAssertEqual(AssistToolDefinition.irregularPlanTwins, [
            "schedule_deploy": "plan_scheduled_deploy",
            "add_curriculum_mentions": "plan_curriculum_mentions",
        ])
        var checked: Int = 0
        for tool in AssistToolRunner.mcpTools {
            if tool.name == "schedule_deploy" {
                XCTAssertEqual(tool.planTwinName, "plan_scheduled_deploy")
                checked += 1
            }
            if tool.name == "add_curriculum_mentions" {
                XCTAssertEqual(tool.planTwinName, "plan_curriculum_mentions")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 2, "One of the irregular writes is no longer on the surface.")
    }

    // MARK: - Every plan can be accepted (#150)

    /// Every `plan_` tool on the surface, run on a happy path, says it IS a
    /// plan — which is the only thing that puts a Go button under it.
    ///
    /// The mark is `AssistToolOutcome.isPlan`, and only `.planned` sets it.
    /// Swift's type cannot be wrong the way Windows' `string` return was
    /// (#70), but the CONSTRUCTOR can: `isPlan` defaults to false, so a twin
    /// whose happy path is built with `.read`, `.wrote` or a bare initializer
    /// compiles, reads correctly in every text assertion, and makes its write
    /// unrunnable from the window — `AssistAgent.showPlan` prints an unmarked
    /// outcome as an answer and offers nothing to press.
    ///
    /// Walks every tool whose name begins `plan_` on the MCP surface — what
    /// EXISTS — rather than deriving twins through `planTwinName`, which is
    /// the map this test is guarding and so cannot also be its list: the
    /// derivation once missed `plan_curriculum_mentions` entirely (#327). A
    /// `plan_` tool with no case below FAILS, so a new twin cannot be skipped
    /// by forgetting it.
    func testEveryPlanToolOnTheSurfaceCanSayItIsAPlan() async throws {
        // A moment two days ahead of the REAL clock: `plan_scheduled_deploy`
        // reads `Date()`, and a fixed date in the past is answered "That
        // deploy cannot be scheduled." — which is ALSO marked as a plan, so a
        // fixed date would pass this test for the wrong reason.
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let later: Date = Date().addingTimeInterval(2 * 24 * 60 * 60)
        let whenAhead: String = formatter.string(from: later)

        let happyArguments: [String: [String: Any]] = [
            "plan_publish_class_on": ["date": "2026-09-09"],
            "plan_publish_pages": ["pages": "Unit 1, Day 2"],
            "plan_unpublish_pages": ["pages": "Unit 1, Day 1"],
            "plan_scheduled_deploy": ["when": whenAhead],
            "plan_remember_timetable": ["dates": "2026-11-02, 2026-11-03"],
            "plan_add_next_class": [:],
            "plan_re_date_classes": [:],
            "plan_add_classes": ["unit": 6, "howMany": 2],
            "plan_make_room_for_classes": ["unit": 3, "atDay": 2],
            "plan_curriculum_mentions": ["page": "Loops", "codes": "A1.1"],
        ]

        var ranCount: Int = 0
        for tool in AssistToolRunner.mcpTools where tool.name.hasPrefix("plan_") {
            guard let arguments = happyArguments[tool.name] else {
                XCTFail("No happy-path case for \(tool.name) — add one; a plan nobody has proved "
                        + "can be ACCEPTED is the #70 defect.")
                continue
            }
            let made: AssistFixture.Made = try AssistFixture.makeRichSection(for: self)
            defer { try? FileManager.default.removeItem(at: made.root) }

            let outcome: AssistToolOutcome = await AssistFixture.run(
                tool.name, with: arguments, on: made.runner
            )
            ranCount += 1
            XCTAssertTrue(
                outcome.isPlan,
                "\(tool.name) answered its happy path without marking it a plan, so the window would "
                + "print it as an answer and offer no Go: \(outcome.summary)"
            )
            // The one twin whose REFUSAL is also marked a plan (#150 §6.2):
            // prove this case really is the happy path.
            if tool.name == "plan_scheduled_deploy" {
                XCTAssertNotEqual(
                    outcome.summary, "That deploy cannot be scheduled.",
                    "The scheduled-deploy case reached the refusal, which is marked a plan too — "
                    + "so this passed without proving anything: \(outcome.detail)"
                )
            }
        }
        XCTAssertEqual(ranCount, happyArguments.count,
                       "A case names a plan tool the surface no longer has, or one was skipped.")
        XCTAssertGreaterThanOrEqual(ranCount, 10, "The walk ran fewer plan tools than exist today.")
    }

    /// Every card that reaches a write with a twin stops at Go in plan mode —
    /// the part a teacher actually meets.
    ///
    /// Derived from the card tables themselves (`everyFixedShape` and
    /// `everyParsedShape`), taking every command whose tool changes pages,
    /// does not wait on a button of its own, and has a twin on the surface.
    /// Each goes through `AssistAgent.say` with plan mode ON, which is what a
    /// teacher has. A phrasing in a club's own noun, and a family matched only
    /// in a numbered course, is said in a club; everything else in the rich
    /// Unit/Day section.
    func testEveryCardThatReachesAPlannedWriteStopsAtGo() async throws {
        var sentences: [(phrasing: String, tool: String, inAClub: Bool)] = []
        for shape in AssistCardCommand.everyFixedShape {
            sentences.append((shape.phrasing, shape.command.toolName,
                              shape.phrasing.contains("meeting")))
        }
        for family in AssistCardCommand.everyParsedShape {
            sentences.append((family.example, family.tool,
                              family.numberedPageWord != nil || family.example.contains("meeting")))
        }

        var surfaceNames: Set<String> = []
        for tool in AssistToolRunner.mcpTools {
            surfaceNames.insert(tool.name)
        }

        var checked: Int = 0
        for sentence in sentences {
            var definition: AssistToolDefinition? = nil
            for tool in AssistToolRunner.mcpTools where tool.name == sentence.tool {
                definition = tool
            }
            guard let write = definition, !write.readOnly, !write.needsApproval,
                  let twin = write.planTwinName, surfaceNames.contains(twin) else {
                continue
            }

            let made: AssistFixture.Made = sentence.inAClub
                ? try AssistFixture.makeBusyClub()
                : try AssistFixture.makeRichSection(for: self)
            defer { try? FileManager.default.removeItem(at: made.root) }

            let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner)
            await agent.say(sentence.phrasing)
            checked += 1

            XCTAssertEqual(
                agent.pendingApproval?.call.function.name, sentence.tool,
                "“\(sentence.phrasing)” reaches \(sentence.tool) and did not stop at Go: "
                + (agent.entries.last?.text ?? "nothing said")
            )
            XCTAssertEqual(toolResults(in: agent), [],
                           "“\(sentence.phrasing)” ran something before the teacher said Go.")
            XCTAssertEqual(agent.entries.last?.text, AssistWording.planQuestion,
                           "“\(sentence.phrasing)” did not end with the plan question.")
        }
        XCTAssertGreaterThanOrEqual(checked, 20, "The walk found fewer gated cards than exist today.")
    }

    /// The headline case end to end: "make room for a class at Unit 3, Day 4"
    /// is a plan a teacher can read AND accept — the sentence #70 is about,
    /// declared in the contract since #150.
    func testTheArticleFormOfMakeRoomIsAPlanThatCanBeAccepted() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRichSection(for: self)
        defer { try? FileManager.default.removeItem(at: made.root) }

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner)
        await agent.say("make room for a class at Unit 3, Day 4")
        XCTAssertEqual(agent.pendingApproval?.call.function.name, "make_room_for_classes")
        XCTAssertEqual(agent.entries.last?.text, AssistWording.planQuestion)

        await agent.approvePending()
        XCTAssertEqual(toolResults(in: agent), ["make_room_for_classes"], "Go did not run the write.")
        let movedOn: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 3, Day 5", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(movedOn.contains("Three four."),
                      "Unit 3, Day 4 was not moved on to Day 5 to make room:\n\(movedOn)")
    }

    // MARK: - Helpers

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
