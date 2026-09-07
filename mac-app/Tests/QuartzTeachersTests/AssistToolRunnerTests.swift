import XCTest
@testable import QuartzTeachers

/// The tool surface the local model calls, and what running one does.
///
/// Most of what is pinned here is SHAPE rather than behaviour, and that is the
/// point. The safety of this feature is almost entirely a property of which
/// tools exist and what they are called: no destructive tool anywhere, publish
/// and unpublish as two separate verbs rather than one flag, a plan in front of
/// every write that changes a page, and a button in front of the one act that
/// reaches students. Those are the things a well-meaning refactor would quietly
/// undo, so those are the things with tests around them.
final class AssistToolRunnerTests: XCTestCase {

    // MARK: - The surface

    /// The exact twenty. Narrowed from the Windows server's full surface, which
    /// is far larger: a small local model routes worse the more it is shown,
    /// and these are the ones a teacher actually asks for.
    ///
    /// **The count is a measurement, and it has moved.** Routing accuracy was
    /// counted against FIFTEEN tools. Five have been added since — reading and
    /// recording a section's timetable, and the page for the next class — and
    /// each was a deliberate decision to spend some of that number. Anyone
    /// changing this figure again should say so out loud, and the accuracy is
    /// worth re-measuring rather than assumed to have survived.
    @MainActor
    func testTheSurfaceIsExactlyTheNarrowedTools() {
        let expected: Set<String> = [
            "list_pages", "read_page", "check_section",
            "plan_publish_class_on", "publish_class_on",
            "plan_publish_pages", "publish_pages",
            "plan_unpublish_pages", "unpublish_pages",
            "rebuild_preview", "undo_last_change",
            "deploy_section", "plan_scheduled_deploy", "schedule_deploy", "cancel_scheduled_deploy",
            "read_remembered_timetable", "plan_remember_timetable", "remember_timetable",
            "plan_add_next_class", "add_next_class",
            // Re-dating a whole section. On the surface so plan mode can find
            // its twin and an MCP client can call it; OFF the local list, so
            // the model's own choices are unchanged by it.
            "plan_re_date_classes", "re_date_classes",
        ]

        var names: Set<String> = []
        for tool in AssistToolRunner.tools {
            names.insert(tool.name)
        }
        XCTAssertEqual(names, expected)
        XCTAssertEqual(AssistToolRunner.tools.count, expected.count, "A tool is defined twice.")
    }

    /// What the LOCAL model is shown: thirteen of the twenty-two.
    ///
    /// Nine are left off because the model never has to NAME them, and every
    /// schema in the prompt costs a small router accuracy. The seven `plan_`
    /// twins are called IN CODE by plan mode, which builds the call from the
    /// write the model already chose; `remember_timetable` is off because dates
    /// the model supplies are dates it may have invented, and a wrong one
    /// silently puts a class on the wrong day; `re_date_classes` is off because
    /// its phrasings are matched in code and it is far too large a change to
    /// reach through a router. All nine still RUN — they are hidden from the
    /// list, not removed from the surface.
    @MainActor
    func testTheLocalModelIsShownExactlyThirteenToolsAndNoPlans() throws {
        let expected: Set<String> = [
            "list_pages", "read_page", "check_section",
            "publish_class_on", "publish_pages", "unpublish_pages",
            "rebuild_preview", "undo_last_change",
            "deploy_section", "schedule_deploy", "cancel_scheduled_deploy",
            "read_remembered_timetable", "add_next_class",
        ]

        var shown: Set<String> = []
        for tool in AssistToolRunner.localTools {
            shown.insert(tool.name)
        }
        XCTAssertEqual(shown, expected)
        XCTAssertEqual(AssistToolRunner.localTools.count, 13, "A tool is shown twice.")

        for tool in AssistToolRunner.localTools {
            XCTAssertFalse(
                tool.name.hasPrefix("plan_"),
                "\(tool.name) is a plan; plan mode calls those in code, so the model never names one."
            )
        }

        // And the runner really hands that list to the model.
        let runner: AssistToolRunner = try makeRunner().runner
        var handedOver: Set<String> = []
        for definition in runner.definitions {
            handedOver.insert(definition.name)
        }
        XCTAssertEqual(handedOver, expected)
    }

    /// Claude Code, on the other end of the MCP server, has no plan mode: it
    /// needs the twins by name to show a teacher what a write would do. So the
    /// seven hidden from the local list are still served there.
    @MainActor
    func testTheHiddenToolsAreStillServedToClaudeCode() throws {
        let runner: AssistToolRunner = try makeRunner().runner
        var overMCP: Set<String> = []
        for definition in runner.mcpDefinitions {
            overMCP.insert(definition.name)
        }

        let hidden: [String] = [
            "plan_publish_class_on", "plan_publish_pages", "plan_unpublish_pages",
            "plan_scheduled_deploy", "plan_remember_timetable", "plan_add_next_class",
            "remember_timetable",
        ]
        for name in hidden {
            XCTAssertTrue(overMCP.contains(name), "\(name) is missing from the MCP surface.")
            XCTAssertNotNil(runner.definition(named: name), "\(name) must still be runnable.")
        }

        // Reading the dates back is not the same act as writing them, and it
        // invents nothing, so it stays on both surfaces.
        var localNames: Set<String> = []
        for tool in AssistToolRunner.localTools {
            localNames.insert(tool.name)
        }
        XCTAssertTrue(localNames.contains("read_remembered_timetable"))
        XCTAssertTrue(overMCP.contains("read_remembered_timetable"))
    }

    /// Every tool the model may name can be found again by name — the gate
    /// reads `needsApproval` off the definition it looks up, so a name that
    /// does not look up is a write that never meets its gate.
    @MainActor
    func testEveryToolCanBeFoundByName() throws {
        let runner: AssistToolRunner = try makeRunner().runner
        for tool in AssistToolRunner.tools {
            XCTAssertEqual(runner.definition(named: tool.name)?.name, tool.name)
        }
        XCTAssertNil(runner.definition(named: "delete_everything"))
    }

    /// Only deploying asks for a button. Publishing is backed up and
    /// `undo_last_change` takes it back, and a gate in front of every write
    /// teaches a teacher to click through gates — which is worse than having no
    /// gate at all.
    @MainActor
    func testOnlyDeployingAndSchedulingADeployAskForApproval() {
        var needingApproval: Set<String> = []
        for tool in AssistToolRunner.tools where tool.needsApproval {
            needingApproval.insert(tool.name)
        }
        XCTAssertEqual(needingApproval, ["deploy_section", "schedule_deploy"])
    }

    /// Approval survives the rewrite that names the real course. The gate reads
    /// the runner's own definition, but nothing should depend on that: a tool
    /// that loses its gate on the way to the model is a bug waiting for a
    /// second caller.
    @MainActor
    func testNamingTheRealCourseKeepsTheApprovalGate() {
        for tool in AssistToolRunner.tools {
            let renamed: AssistToolDefinition = tool.namingTheRealCourse("EXC2O")
            XCTAssertEqual(renamed.needsApproval, tool.needsApproval, tool.name)
            XCTAssertEqual(renamed.readOnly, tool.readOnly, tool.name)
        }
    }

    /// Nothing destructive exists. In testing the model reliably declined
    /// "delete the Unit 1 folder" — not from judgement, but because it had no
    /// tool for it. Absence is the strongest guardrail available.
    @MainActor
    func testNoToolCanDestroyAnything() {
        let forbidden: [String] = ["delete", "remove", "rename", "archive", "erase", "destroy", "move"]
        for tool in AssistToolRunner.tools {
            for word in forbidden {
                XCTAssertFalse(
                    tool.name.contains(word),
                    "\(tool.name) contains “\(word)”, and nothing on this surface may destroy anything."
                )
            }
        }
    }

    /// Every write that changes what is IN a teacher's pages has a `plan_` twin
    /// that changes nothing.
    ///
    /// The three writes without one are each their own reversal: rebuilding a
    /// preview changes no page, undoing IS the undo, and cancelling a schedule
    /// only takes one away. Deploying has no plan because it has the one thing
    /// a plan is a substitute for — a button the teacher has to press.
    @MainActor
    func testEveryWriteThatChangesPagesHasAPlanTwin() {
        let ownReversal: Set<String> = [
            "rebuild_preview", "undo_last_change", "deploy_section", "cancel_scheduled_deploy",
        ]

        var names: Set<String> = []
        for tool in AssistToolRunner.tools {
            names.insert(tool.name)
        }

        for definition in AssistToolRunner.tools {
            if definition.readOnly || ownReversal.contains(definition.name) {
                continue
            }
            let twin: String = planName(for: definition.name)
            XCTAssertTrue(
                names.contains(twin),
                "\(definition.name) changes pages but has no \(twin) to show the teacher first."
            )
            XCTAssertEqual(
                tool(named: twin)?.readOnly, true, "\(twin) must change nothing."
            )
        }

        // And the plans really are plans.
        for tool in AssistToolRunner.tools where tool.name.hasPrefix("plan_") {
            XCTAssertTrue(tool.readOnly, "\(tool.name) is named a plan but is not read-only.")
            XCTAssertFalse(tool.needsApproval, "A plan changes nothing, so it never needs a button.")
        }
    }

    /// `schedule_deploy`'s twin is spelled differently from the rest, so the
    /// mapping is written down rather than assumed.
    private func planName(for toolName: String) -> String {
        if toolName == "schedule_deploy" {
            return "plan_scheduled_deploy"
        }
        return "plan_" + toolName
    }

    @MainActor
    private func tool(named name: String) -> AssistToolDefinition? {
        for definition in AssistToolRunner.tools where definition.name == name {
            return definition
        }
        return nil
    }

    // MARK: - The polarity rule

    /// Publishing and unpublishing are separate tools, and NOTHING on the
    /// surface can turn one into the other.
    ///
    /// This is the rule the whole design turns on. The single genuinely
    /// dangerous failure ever observed was polarity inversion: asked to HIDE a
    /// page, the model called publish with "include everything it links to"
    /// set. A boolean is a coin flip under pressure; a verb is not — so the
    /// verb lives in the tool's NAME, and there is now no boolean anywhere on
    /// the surface at all. `includeLinked` was the last one, and how far each
    /// verb reaches is `AssistPublishPlanner`'s rule instead.
    @MainActor
    func testPublishingAndUnpublishingAreSeparateVerbsWithNoFlagBetweenThem() {
        let pairs: [(String, String)] = [
            ("publish_pages", "unpublish_pages"),
            ("plan_publish_pages", "plan_unpublish_pages"),
        ]
        var names: Set<String> = []
        for tool in AssistToolRunner.tools {
            names.insert(tool.name)
        }
        for (publishing, unpublishing) in pairs {
            XCTAssertTrue(names.contains(publishing))
            XCTAssertTrue(names.contains(unpublishing))
        }

        // No boolean, anywhere — on either surface. Every one of them is an
        // argument the model has to decide, and deciding is the thing this
        // design keeps away from it.
        for tool in AssistToolRunner.mcpTools {
            for (name, property) in tool.parameters {
                XCTAssertNotEqual(
                    property.kind, .boolean,
                    "\(tool.name) takes a boolean called \(name); no tool on this surface takes one, "
                    + "because a boolean is what the model gets wrong under pressure."
                )
            }
            XCTAssertNil(tool.parameters["includeLinked"],
                         "\(tool.name) still asks the model how far to reach.")
        }
    }

    /// Publishing takes the pages it links to WITHOUT being asked. There is no
    /// argument for it any more: a published page whose links lead to pages
    /// students cannot see is the failure the rule exists to prevent.
    @MainActor
    func testPublishingTakesTheLinkedPagesWithNoArgument() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "false", body: "See [[Loops]].", in: made.course)
        try write(courseLevelPage: "Loops", publishForSection1: "false",
                  body: "See [[Snippets]].", in: made.course)
        try write(courseLevelPage: "Snippets", publishForSection1: "false",
                  body: "Some code.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: true"))
        // Followed all the way along, as publishing a class already was.
        XCTAssertTrue(text(ofCourseLevelPage: "Loops", in: made.course).contains("publishForSection1: true"))
        XCTAssertTrue(text(ofCourseLevelPage: "Snippets", in: made.course).contains("publishForSection1: true"))
    }

    /// Unpublishing the class the section's landing page points at must move
    /// the pointer, or every student lands on a transclusion of a page that
    /// is not there.
    ///
    /// Found in testing exactly that way: `section1/index.md` transcluded
    /// Unit 4, Day 19, Day 19 was unpublished, and `check_section` reported
    /// the broken link the unpublish had just created.
    @MainActor
    func testUnpublishingTheNewestClassRepointsTheSectionIndex() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "one", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-10", body: "two", in: made.course)
        try writeSectionIndex(pointingAt: "Unit 1, Day 2", in: made.course)

        _ = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 2"]
        ))

        let index: String = try sectionIndexText(in: made.course)
        XCTAssertTrue(index.contains("![[Unit 1, Day 1]]"),
                      "The landing page must follow the newest class students can still see")
        XCTAssertFalse(index.contains("![[Unit 1, Day 2]]"),
                       "…and must not still point at the one just hidden")
        XCTAssertTrue(index.contains("created: 2026-09-08"),
                      "Its date moves with it: a front page dated later than its newest lesson reads as stale")
    }

    /// The same invariant in the other direction. Stating it once means
    /// publishing a newer class is covered without a second rule.
    @MainActor
    func testPublishingANewerClassMovesTheIndexForward() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "one", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "false", date: "2026-09-10", body: "two", in: made.course)
        try writeSectionIndex(pointingAt: "Unit 1, Day 1", in: made.course)

        _ = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 2"]
        ))

        let index: String = try sectionIndexText(in: made.course)
        XCTAssertTrue(index.contains("![[Unit 1, Day 2]]"), index)
        XCTAssertTrue(index.contains("created: 2026-09-10"), index)
    }

    /// When multiple published classes share the same date (e.g. multi-class
    /// day or overflow), the landing page follows the highest Unit x, Day y.
    @MainActor
    func testSectionIndexSelectsHighestUnitDayWhenDatesAreEqual() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 20", publish: "true", date: "2027-01-18", body: "twenty", in: made.course)
        try write(page: "Unit 4, Day 21", publish: "false", date: "2027-01-18", body: "twenty one", in: made.course)
        try writeSectionIndex(pointingAt: "Unit 4, Day 20", in: made.course)

        _ = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4, Day 21"]
        ))

        let index: String = try sectionIndexText(in: made.course)
        XCTAssertTrue(index.contains("![[Unit 4, Day 21]]"), index)
        XCTAssertTrue(index.contains("created: 2027-01-18"), index)
    }

    /// The landing page transcludes other things too. Repointing Key Links at
    /// a lesson would be a far worse bug than the one this fixes.
    @MainActor
    func testOnlyTheClassTransclusionIsRepointed() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "one", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-10", body: "two", in: made.course)
        try writeSectionIndex(pointingAt: "Unit 1, Day 2", in: made.course)

        _ = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 2"]
        ))

        let index: String = try sectionIndexText(in: made.course)
        XCTAssertTrue(index.contains("![[Key Links]]"), "Left exactly as it was")
        XCTAssertTrue(index.contains("![[Help Sessions]]"), "Left exactly as it was")
    }

    /// Undo has to take the landing page back with the lessons. Restoring the
    /// classes and leaving the front page pointing at the wrong one would be a
    /// worse state than either.
    @MainActor
    func testUndoTakesTheSectionIndexBackToo() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "one", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-10", body: "two", in: made.course)
        try writeSectionIndex(pointingAt: "Unit 1, Day 2", in: made.course)

        _ = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 2"]
        ))
        _ = await made.runner.run(call: call("undo_last_change", arguments: [:]))

        let index: String = try sectionIndexText(in: made.course)
        XCTAssertTrue(index.contains("![[Unit 1, Day 2]]"),
                      "Undo put the lesson back, so it must put the pointer back")
    }

    /// The ORDER is the requirement: the preview stops, the files change, the
    /// preview starts again. Not "all three happen".
    ///
    /// A preview left serving while the pages beneath it are rewritten is
    /// serving a half-changed site. The first attempt at this posted a request
    /// for a view to notice, which meant the stop landed whenever SwiftUI next
    /// evaluated a body — sometimes after the writes, and silently.
    ///
    /// The second attempt called the stop in the right place but did not WAIT
    /// for it. Stopping reaches into the container and kills the section's
    /// processes, so a stop still finishing when the rebuild began killed the
    /// rebuild — leaving no preview and a site on disk from the last build
    /// that was allowed to complete. That is why the fake's stop takes time
    /// and reports beginning and ending separately.
    @MainActor
    func testAWriteStopsThePreviewThenWritesThenStartsIt() async throws {
        let made = try makeRunner(registeringPreview: true)
        defer {
            FakePreview.shared.forget()
            try? FileManager.default.removeItem(at: made.root)
        }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "one", in: made.course)
        FakePreview.shared.watch(pageAt: pageURL(of: "Unit 1, Day 1", in: made.course))

        _ = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))

        XCTAssertEqual(FakePreview.shared.events,
                       ["stop-begins", "stop-ends", "write", "start"],
                       "The stop must FINISH before the writes, and the start come after them")
    }

    /// "Preview" on its own stops a running preview and starts it again,
    /// rather than leaving it up. The running preview IS the stale thing the
    /// teacher is asking to have refreshed.
    @MainActor
    func testPreviewStopsAndRestartsARunningPreview() async throws {
        let made = try makeRunner(registeringPreview: true)
        defer {
            FakePreview.shared.forget()
            try? FileManager.default.removeItem(at: made.root)
        }

        _ = await made.runner.run(call: call(
            "rebuild_preview", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertEqual(FakePreview.shared.events, ["stop-begins", "stop-ends", "start"],
                       "A running preview must be stopped, waited for, and started again")
    }

    /// Cancel answers a cancelled DEPLOY with the fact and nothing else.
    ///
    /// It used to say "Left as it was — nothing was changed." — true, and
    /// reassurance about something nobody was worried about: a teacher who has
    /// just pressed Cancel knows nothing was changed. A PLAN keeps that
    /// wording, because there the reassurance IS the answer — the plan
    /// described changes to pages, and whether they happened is the part in
    /// doubt. Both branches are asserted, because the obvious tidy-up is to
    /// give them one sentence again.
    @MainActor
    func testCancellingADeploySaysTheDeployWasCancelled() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let agent: AssistAgent = makeAgent(tools: made.runner)
        // The card phrasing is matched in code, so this never reaches a model.
        await agent.say("deploy now")
        XCTAssertNotNil(agent.pendingApproval, "Deploying always waits for a button")
        XCTAssertTrue(agent.pendingIsDeploy)

        agent.declinePending()

        XCTAssertEqual(agent.entries.last?.text, AssistWording.deployWasCancelled)
    }

    /// The other branch: a cancelled plan still says nothing was changed.
    @MainActor
    func testCancellingAPlanStillSaysNothingWasChanged() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        // A class page dated tomorrow, so "publish tomorrow's class" has
        // something real to plan about. `makeRunner` pins today to
        // 2026-09-08, which is what makes "tomorrow" a fixed date here rather
        // than a test that means something different every day.
        try write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-09", body: "one", in: made.course)

        let agent: AssistAgent = makeAgent(tools: made.runner)
        XCTAssertTrue(agent.planMode.isOn, "The smaller tier cannot turn plan mode off")
        await agent.say("publish tomorrow's class")
        XCTAssertNotNil(agent.pendingApproval)
        XCTAssertFalse(agent.pendingIsDeploy, "Publishing is a plan, not a deploy")

        agent.declinePending()

        XCTAssertEqual(agent.entries.last?.text, AssistWording.planWasCancelled)
    }

    /// Deploying from the assistant is the two buttons a teacher would press,
    /// in the order they would press them: Stop Preview, then Deploy.
    ///
    /// It used to be neither. The assistant ran `deploy.sh` in a runner of its
    /// own that nothing on screen was watching, and a running preview made
    /// that refuse outright — so the teacher approved a deploy, watched a
    /// spinner, and saw nothing happen anywhere. Both halves are asserted
    /// here: the stop must FINISH before the deploy begins, because stop mode
    /// kills a section's processes by working directory and would take the
    /// build with them.
    @MainActor
    func testDeployingStopsARunningPreviewFirstAndThenPressesDeploy() async throws {
        let made = try makeRunner(registeringPreview: true)
        defer {
            FakePreview.shared.forget()
            try? FileManager.default.removeItem(at: made.root)
        }

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "deploy_section", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertEqual(FakePreview.shared.events, ["stop-begins", "stop-ends", "deploy"],
                       "Deploy must wait for the preview to be fully stopped")
        XCTAssertEqual(made.siteWork.deploys, 0,
                       "With a window open the deploy goes through it, not the assistant's own runner")
        // The whole answer, and nothing about what it had to do to obey: the
        // stopped preview is deliberately not narrated.
        //
        // Asked of AssistWording rather than typed again. The sentence exists
        // once, and `contracts/assist-wording.json` is generated from it, so a
        // test that quoted its own copy could pass while the contract Windows
        // is built from said something else.
        XCTAssertEqual(outcome.summary, FakePreview.deployedMessage)
    }

    /// The other order, and the one a teacher meets most: no preview running.
    /// Nothing is stopped, and the window's Deploy is pressed just the same.
    @MainActor
    func testDeployingWithNoPreviewRunningJustDeploys() async throws {
        let made = try makeRunner(registeringPreview: true)
        defer {
            FakePreview.shared.forget()
            try? FileManager.default.removeItem(at: made.root)
        }
        // Stop it the way the teacher would have, before asking to deploy.
        _ = await made.runner.run(call: call(
            "deploy_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "deploy_section", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertEqual(FakePreview.shared.events,
                       ["stop-begins", "stop-ends", "deploy", "deploy"],
                       "A preview already stopped is not stopped again")
        XCTAssertEqual(outcome.summary, FakePreview.deployedMessage)
    }

    /// With no section window open there is nothing to press, and the deploy
    /// falls back to running the launcher itself — the path Claude Code over
    /// MCP and a deploy scheduled for half six in the morning both take.
    @MainActor
    func testDeployingWithNoSectionWindowOpenRunsTheLauncherItself() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        SectionWindowControllers.shared.forgetAll()

        _ = await made.runner.run(call: call(
            "deploy_section", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertEqual(made.siteWork.deploys, 1)
    }

    /// With no section window open there is nothing to drive, and the answer
    /// must say so rather than claim a preview nobody can see.
    @MainActor
    func testWithNoSectionWindowOpenTheAnswerSaysTheSiteWasBuilt() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        SectionWindowControllers.shared.forgetAll()

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "one", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))

        XCTAssertTrue(outcome.detail.contains("no window is showing it"), outcome.detail)
    }

    /// A class page is a ROOT, not an orphan.
    ///
    /// The rule the courses are built to is that every page must be reachable
    /// FROM a class page; the class page itself is reached through the site's
    /// own navigation, and normally nothing wikilinks to it. Counting them
    /// made a perfectly healthy 86-period course report 84 pages "linked from
    /// nowhere" — every one of them a lesson — which teaches a teacher to
    /// ignore the whole check.
    @MainActor
    func testClassPagesAreNotCountedAsLinkedFromNowhere() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        // Two lessons nothing links to, and one concept page that IS linked.
        try write(page: "Unit 1, Day 1", publish: "true", body: "See [[Loops]].", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", body: "More practice.", in: made.course)
        try write(courseLevelPage: "Loops", publishForSection1: "true",
                  body: "About loops.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "check_section", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertFalse(outcome.detail.contains("linked from nowhere"), outcome.detail)
        XCTAssertTrue(outcome.detail.contains("None of the visible pages link to unpublished pages"),
                      outcome.detail)
    }

    /// A page that is genuinely stranded is still reported — the fix above
    /// must not turn the check off.
    @MainActor
    func testAStrandedPageIsStillReported() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", body: "A lesson.", in: made.course)
        try write(courseLevelPage: "Loops", publishForSection1: "true",
                  body: "Nothing points at this.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "check_section", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertTrue(outcome.detail.contains("1 visible page is linked from nowhere"), outcome.detail)
        XCTAssertTrue(outcome.detail.contains("Loops"), outcome.detail)
    }

    /// The plan card shows the teacher `forTheCard`, not `detail`.
    ///
    /// `detail` ends with a sentence addressed to whatever is reading a plan
    /// on a surface with no Go and Cancel of its own — Claude Code over MCP.
    /// It appeared on the card for a while, directly above the very buttons
    /// it was describing, telling a teacher to "show this to the teacher".
    @MainActor
    func testAPlanCardDoesNotShowTheSentenceWrittenForTheModel() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", body: "A lesson.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "plan_unpublish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))

        XCTAssertTrue(outcome.detail.contains("ask before going ahead"),
                      "Claude Code has no plan mode, so it still has to be told to ask")
        XCTAssertFalse(outcome.forTheCard.contains("ask before going ahead"),
                       "The card has Go and Cancel underneath it; saying it as well is noise")
        XCTAssertFalse(outcome.forTheCard.contains("Show this to the teacher"),
                       "…and it addresses the teacher as though they were the model")
        XCTAssertTrue(outcome.forTheCard.contains("Unit 1, Day 1"),
                      "The plan itself is still all there")
    }

    /// A start date with no end date and no pages named means "everything
    /// from here to the end of the course", which is what a mistyped request
    /// for ONE lesson turns into — measured at 10 trials out of 10 on
    /// "publsh tomorows class … and the stuff it links to". It is refused
    /// rather than planned, and the refusal says what to do instead.
    @MainActor
    func testAnOpenEndedPublishIsRefusedRatherThanPlanned() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "false", body: "A lesson.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "", "onOrAfter": "2026-09-08"]
        ))

        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"),
                      "Nothing may be published by an open-ended range")
        XCTAssertTrue(outcome.detail.contains("publish_class_on"),
                      "The refusal has to name what to do for one day, or the model cannot correct itself")
        XCTAssertTrue(outcome.detail.contains("before"),
                      "…and how to ask for a stretch of classes")
    }

    /// The same shape is allowed for UNPUBLISHING: hiding work back to a date
    /// is a real thing to want, it exposes nothing, and the same backup undoes
    /// it. The asymmetry is deliberate.
    @MainActor
    func testAnOpenEndedUnpublishIsStillAllowed() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", body: "A lesson.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "", "onOrAfter": "2020-01-01"]
        ))

        XCTAssertFalse(outcome.detail.contains("almost certainly not what was meant"),
                       "Unpublishing must not inherit publishing's refusal")
    }

    /// Unpublishing is NOT the mirror image. A page the named ones are the only
    /// link to comes down with them — and so does what only THAT page linked
    /// to, which is why the rule is worked out to a fixed point.
    @MainActor
    func testUnpublishingTakesAPageLinkedOnlyByTheOneComingDown() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", body: "See [[Loops]].", in: made.course)
        try write(courseLevelPage: "Loops", publishForSection1: "true",
                  body: "See [[Snippets]].", in: made.course)
        try write(courseLevelPage: "Snippets", publishForSection1: "true",
                  body: "Some code.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"))
        XCTAssertTrue(text(ofCourseLevelPage: "Loops", in: made.course).contains("publishForSection1: false"))
        XCTAssertTrue(
            text(ofCourseLevelPage: "Snippets", in: made.course).contains("publishForSection1: false"),
            "A page only the page only THAT page linked to still comes down."
        )
    }

    /// When a teacher names specific pages, date boundaries supplied in the
    /// same call (such as dateline leakage from the prompt) must be ignored so
    /// other classes in the date range are not accidentally swept.
    @MainActor
    func testNamedPagesPublishAndUnpublishIgnoreExtraneousDateBounds() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "Lesson 1.", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-09", body: "Lesson 2.", in: made.course)

        // Unpublish Unit 1, Day 1 with an extraneous onOrAfter date that covers Day 2 as well.
        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages",
            arguments: [
                "course": "ICS3U",
                "section": 1,
                "pages": "Unit 1, Day 1",
                "onOrAfter": "2026-09-08",
            ]
        ))
        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"),
                      "The named page must be unpublished.")
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("publish: true"),
                      "Other classes in the date range must remain untouched when a specific page was named.")
    }

    /// Reported from a real course (ADA1O Section 1): unpublishing a class
    /// said four pages were staying published because **"index"** still linked
    /// to them.
    ///
    /// Every folder in a course has an `index.md`, so "index" is a name the
    /// teacher cannot act on — the page they would go and open is the one the
    /// sidebar calls **Portfolios**. Naming it that way is not cosmetic: the
    /// whole purpose of the "stays published" list is to let a teacher go and
    /// look at the page holding a link, and a name that matches eleven pages
    /// tells them nowhere to go.
    @MainActor
    func testAFolderLandingPageIsNamedAfterItsFolderNotAfterItsFile() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 23", publish: "true",
                  body: "See [[Journal Checklist]].", in: made.course)
        try write(courseLevelPage: "Journal Checklist", inFolder: "Portfolios",
                  publishForSection1: "true", body: "What to hand in.", in: made.course)
        try write(folderIndex: "Portfolios", titled: "Portfolios", publishForSection1: "true",
                  body: "The hub: [[Journal Checklist]].", in: made.course)

        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_unpublish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4, Day 23"]
        ))

        XCTAssertTrue(
            planned.detail.contains("“Portfolios” still links to it."),
            "The teacher must be told the page they can actually go and open: \(planned.detail)"
        )
        XCTAssertFalse(
            planned.detail.contains("index"),
            "“index” names eleven pages and none of them to a teacher: \(planned.detail)"
        )
    }

    /// The trap the fix above would otherwise have walked into.
    ///
    /// Referrers used to be remembered by FILE NAME, and every folder landing
    /// page is called `index` — so looking the name back up returned whichever
    /// `index.md` the folder walk happened to reach first. While the answer was
    /// printed as "index" that was invisible. Printing it as a folder name
    /// turns it into a CONFIDENTLY WRONG answer, which is worse than a useless
    /// one: a teacher sent to Concepts to find a link that is in Portfolios
    /// concludes the assistant is lying and stops reading the list.
    @MainActor
    func testTheRightFolderIsNamedWhenSeveralFoldersHaveALandingPage() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 23", publish: "true",
                  body: "See [[Journal Checklist]].", in: made.course)
        try write(courseLevelPage: "Journal Checklist", inFolder: "Portfolios",
                  publishForSection1: "true", body: "What to hand in.", in: made.course)
        // Sorts before Portfolios, and links to something else entirely.
        try write(courseLevelPage: "Stage Directions", inFolder: "Concepts",
                  publishForSection1: "true", body: "Upstage, downstage.", in: made.course)
        try write(folderIndex: "Concepts", titled: "Concepts", publishForSection1: "true",
                  body: "Ideas: [[Stage Directions]].", in: made.course)
        try write(folderIndex: "Portfolios", titled: "Portfolios", publishForSection1: "true",
                  body: "The hub: [[Journal Checklist]].", in: made.course)

        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_unpublish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4, Day 23"]
        ))

        XCTAssertTrue(
            planned.detail.contains("“Portfolios” still links to it."),
            "Named the wrong folder's landing page: \(planned.detail)"
        )
        XCTAssertFalse(
            planned.detail.contains("“Concepts” still links to it."),
            "Concepts does not link to Journal Checklist: \(planned.detail)"
        )
    }

    /// The rule that keeps this from breaking another class: a page something
    /// else still links to stays published — and the plan SAYS so, naming what
    /// still links to it.
    @MainActor
    func testUnpublishingKeepsAPageAnotherPageStillLinksToAndSaysWhy() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 3, Day 1", publish: "true", body: "See [[Ohm's Law]].", in: made.course)
        try write(page: "Unit 3, Day 2", publish: "true", body: "See [[Ohm's Law]].", in: made.course)
        try write(courseLevelPage: "Ohm's Law", publishForSection1: "true",
                  body: "Voltage over current.", in: made.course)

        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 3, Day 1"]
        ))
        XCTAssertTrue(planned.detail.contains("Ohm's Law"))
        XCTAssertTrue(
            planned.detail.contains("“Unit 3, Day 2” still links to it."),
            "A teacher has to see that the tool thought about it: \(planned.detail)"
        )

        let done: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 3, Day 1"]
        ))
        XCTAssertFalse(done.shouldContinue)
        XCTAssertTrue(text(ofPage: "Unit 3, Day 1", in: made.course).contains("publish: false"))
        XCTAssertTrue(text(ofPage: "Unit 3, Day 2", in: made.course).contains("publish: true"))
        XCTAssertTrue(
            text(ofCourseLevelPage: "Ohm's Law", in: made.course).contains("publishForSection1: true"),
            "Hiding this week's lesson must not leave last week's pointing at nothing."
        )
    }

    /// Three kinds of page never come down by following a link, whatever the
    /// link count: a folder's landing page, anything the section's Key Links
    /// offers, and any curriculum page.
    ///
    /// Each is reached from somewhere other than a lesson, so counting links
    /// says nothing useful about whether it is still wanted. Both pages that
    /// link to Key Links' entry are taken down here, so the reference rule
    /// alone would have swept it — the exclusion is what saves it.
    @MainActor
    func testAFolderIndexKeyLinksAndCurriculumAreNeverUnpublishedByFollowingLinks() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true",
                  body: "See [[Concepts/index]], [[Course Outline]], [[A1.1]] and [[Loops]].",
                  in: made.course)
        try write(sectionPage: "Key Links", publish: "true",
                  body: "See [[Course Outline]].", in: made.course)
        try write(courseLevelPage: "index", inFolder: "Concepts",
                  publishForSection1: "true", body: "The concepts.", in: made.course)
        try write(courseLevelPage: "Course Outline", inFolder: "Concepts",
                  publishForSection1: "true", body: "How the class runs.", in: made.course)
        try write(courseLevelPage: "A1.1", inFolder: "Curriculum",
                  publishForSection1: "true", body: "Describe an algorithm. ^text", in: made.course)
        try write(courseLevelPage: "Loops", publishForSection1: "true",
                  body: "About loops.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1; Key Links"]
        ))
        XCTAssertFalse(outcome.shouldContinue)

        // The pages the teacher named came down, because they asked.
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"))
        // And the page nothing else needs came down with them.
        XCTAssertTrue(text(ofCourseLevelPage: "Loops", in: made.course).contains("publishForSection1: false"))

        // The three that never do.
        XCTAssertTrue(
            text(ofCourseLevelPage: "index", inFolder: "Concepts", in: made.course)
                .contains("publishForSection1: true"),
            "A folder's landing page is the way IN to a folder, never an orphan."
        )
        XCTAssertTrue(
            text(ofCourseLevelPage: "Course Outline", inFolder: "Concepts", in: made.course)
                .contains("publishForSection1: true"),
            "A page this section's Key Links offers stays."
        )
        XCTAssertTrue(
            text(ofCourseLevelPage: "A1.1", inFolder: "Curriculum", in: made.course)
                .contains("publishForSection1: true"),
            "A curriculum page stays — build_site.py's own rule, any folder named for curriculum."
        )

        XCTAssertTrue(outcome.detail.contains("folder's landing page"), outcome.detail)
        XCTAssertTrue(outcome.detail.contains("Key Links"), outcome.detail)
        XCTAssertTrue(outcome.detail.contains("curriculum page"), outcome.detail)
    }

    /// The verb reaches the FILE without passing through anything that could
    /// flip it: hiding a page with "include everything it links to" set hides
    /// the linked pages too, and publishes nothing.
    @MainActor
    func testHidingWithLinkedPagesNeverPublishesAnything() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", body: "See [[Loops]].", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "false", body: "Nothing yet.", in: made.course)
        try write(courseLevelPage: "Loops", publishForSection1: "true", body: "About loops.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))

        XCTAssertFalse(outcome.shouldContinue, "A write ends the turn.")
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"))
        XCTAssertTrue(text(ofCourseLevelPage: "Loops", in: made.course).contains("publishForSection1: false"))
        // The page that was already hidden is untouched, not toggled.
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("publish: false"))
    }

    // MARK: - Naming the real course

    /// With `for example ICS3U` left in the schema, a request that named no
    /// course copied ICS3U out of the examples nine times out of nine. So every
    /// mention of the placeholder is replaced before the model ever sees it —
    /// in the parameter descriptions, which is where the examples live.
    @MainActor
    func testNamingTheRealCourseRewritesEveryParameterDescription() {
        var placeholdersFound: Int = 0
        for tool in AssistToolRunner.tools {
            for (_, property) in tool.parameters where property.description.contains("ICS3U") {
                placeholdersFound += 1
            }
        }
        XCTAssertGreaterThan(placeholdersFound, 0, "The placeholder has to be there to be worth replacing.")

        for tool in AssistToolRunner.tools {
            let renamed: AssistToolDefinition = tool.namingTheRealCourse("EXC2O")
            XCTAssertFalse(renamed.description.contains("ICS3U"), tool.name)
            for (name, property) in renamed.parameters {
                XCTAssertFalse(
                    property.description.contains("ICS3U"),
                    "\(tool.name).\(name) still names the placeholder course."
                )
            }
            if let course = renamed.parameters["course"] {
                XCTAssertTrue(course.description.contains("EXC2O"))
            }
        }
    }

    /// The description is rewritten too. None of the fifteen happens to name
    /// the placeholder in its own description — the shortening rule cuts the
    /// sentences that did — so the rewrite is proved on a definition built for
    /// the purpose rather than left untested.
    @MainActor
    func testNamingTheRealCourseRewritesTheDescriptionAsWell() {
        let invented: AssistToolDefinition = AssistToolDefinition(
            name: "list_pages",
            description: "List the pages in ICS3U.",
            parameters: ["course": AssistSchemaProperty(kind: .string, description: "For example ICS3U.")],
            required: ["course"],
            readOnly: true,
            needsApproval: false
        )
        let renamed: AssistToolDefinition = invented.namingTheRealCourse("EXC2O")
        XCTAssertEqual(renamed.description, "List the pages in EXC2O.")
        XCTAssertEqual(renamed.parameters["course"]?.description, "For example EXC2O.")
    }

    // MARK: - The phrasings that were measured

    /// The `TEACHERS SAY` clauses are what took routing from 69% to 91%. They
    /// are copied from the Windows server rather than reworded, so this pins
    /// the ones that must survive a tidy-up.
    @MainActor
    func testTheMeasuredPhrasingsAreStillThere() throws {
        let mustSay: [String: String] = [
            "publish_class_on": "TEACHERS SAY: \"publish tomorrow's class\"",
            "unpublish_pages": "\"take Unit 4, Day 5 back down\"",
            "rebuild_preview": "TEACHERS SAY: \"preview the site\"",
            "undo_last_change": "TEACHERS SAY: \"undo that\"",
            "deploy_section": "TEACHERS SAY: \"deploy the site\"",
            "check_section": "TEACHERS SAY: \"what do students see right now?\"",
            "add_next_class": "TEACHERS SAY: \"add an entry for the next class\"",
            "read_remembered_timetable": "TEACHERS SAY: \"when does this class meet?\"",
        ]
        for (name, phrasing) in mustSay {
            let definition: AssistToolDefinition = try XCTUnwrap(tool(named: name))
            XCTAssertTrue(definition.description.contains(phrasing), "\(name) lost a measured phrasing.")
        }
    }

    /// Every phrasing the assistant window offers as a card routes to a tool
    /// that exists. The cards never reach the model, so a name that does not
    /// match is a button that does nothing at all.
    @MainActor
    func testEveryCardPhrasingNamesARealTool() throws {
        let phrasings: [String] = [
            "what would students see in this section right now?",
            "what do students see right now?",
            "rebuild the preview",
            "undo that",
            "deploy now",
            "deploy this section now",
            "deploy",
            "publish tomorrow's class",
        ]
        // Checked against what the LOCAL model is shown, because a card is a
        // shortcut past the model to a tool the window promises.
        var names: Set<String> = []
        for tool in AssistToolRunner.localTools {
            names.insert(tool.name)
        }
        for phrasing in phrasings {
            let command: AssistCardCommand = try XCTUnwrap(AssistCardCommand.matching(phrasing))
            XCTAssertTrue(names.contains(command.toolName), phrasing)
        }
    }

    /// "Publish tomorrow's class" is matched in code and never reaches the
    /// model, so the word "tomorrow" arrives at the runner literally. It has to
    /// be understood there or the card publishes nothing.
    @MainActor
    func testTheCardsWordForTomorrowIsUnderstood() {
        let today: CalendarDay = CalendarDay(year: 2026, month: 9, day: 8)!
        XCTAssertEqual(AssistToolRunner.day(named: "tomorrow", today: today)?.text, "2026-09-09")
        XCTAssertEqual(AssistToolRunner.day(named: "today", today: today)?.text, "2026-09-08")
        XCTAssertEqual(AssistToolRunner.day(named: "2026-10-01", today: today)?.text, "2026-10-01")
        XCTAssertNil(AssistToolRunner.day(named: "next Tuesday", today: today))
    }

    // MARK: - Running the tools

    @MainActor
    func testListingAndReadingPages() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", body: "See [[Loops]].", in: made.course)
        try write(courseLevelPage: "Loops", publishForSection1: "true", body: "About loops.", in: made.course)

        let listed: AssistToolOutcome = await made.runner.run(call: call(
            "list_pages", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(listed.shouldContinue, "A read hands back so the model can answer.")
        XCTAssertTrue(listed.detail.contains("Unit 1, Day 1.md"))
        XCTAssertTrue(listed.detail.contains("Loops.md"))

        let filtered: AssistToolOutcome = await made.runner.run(call: call(
            "list_pages", arguments: ["course": "ICS3U", "section": 1, "matching": "Loops"]
        ))
        XCTAssertFalse(filtered.detail.contains("Unit 1, Day 1.md"))

        let read: AssistToolOutcome = await made.runner.run(call: call(
            "read_page", arguments: ["course": "ICS3U", "section": 1, "page": "unit 1, day 1"]
        ))
        XCTAssertTrue(read.detail.contains("See [[Loops]]."), "Titles match without regard to case.")

        let missing: AssistToolOutcome = await made.runner.run(call: call(
            "read_page", arguments: ["course": "ICS3U", "section": 1, "page": "Unit 9, Day 9"]
        ))
        XCTAssertTrue(missing.detail.contains("No page in ICS3U Section 1 is called"))
    }

    /// What `check_section` is for: the two things the publishing tools cannot
    /// see for themselves.
    @MainActor
    func testCheckSectionReportsBrokenLinksAndPagesNothingLinksTo() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        // A visible class pointing at a hidden page: a student clicks and finds
        // nothing.
        try write(page: "Unit 1, Day 1", publish: "true", body: "See [[Loops]].", in: made.course)
        try write(courseLevelPage: "Loops", publishForSection1: "false", body: "About loops.", in: made.course)
        // A visible page nothing links to: still in the site's explorer, and no
        // link-following rule will ever reach it.
        //
        // A COURSE-LEVEL page deliberately. Written as a class page it would
        // not count, and rightly: class pages are the roots a section is
        // navigated from, so nothing linking to one is its ordinary state.
        try write(courseLevelPage: "Field Trip", publishForSection1: "true",
                  body: "The museum.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "check_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        // The answer is complete and deterministic, so the turn ENDS with it:
        // a model lap after it could only restate the same facts as a second
        // bubble, which is what the transcript used to show.
        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(outcome.detail.contains("Students would see 2 pages in ICS3U Section 1."))
        XCTAssertTrue(outcome.detail.contains("Loops"))
        XCTAssertTrue(outcome.detail.contains("(hidden)"))
        XCTAssertTrue(outcome.detail.contains("linked from nowhere"))
        XCTAssertTrue(outcome.detail.contains("Field Trip"))
    }

    /// The coarse tool. "Publish tomorrow's class" resolves the linked pages
    /// ITSELF rather than leaving the model to chain calls — the decision that
    /// took an 8-of-8 failure to 8-of-8 correct.
    @MainActor
    func testPublishingAClassByDatePublishesWhatItLinksTo() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-08",
                  body: "See [[Loops]].", in: made.course)
        try write(courseLevelPage: "Loops", publishForSection1: "false",
                  body: "See [[Snippets]].", in: made.course)
        try write(courseLevelPage: "Snippets", publishForSection1: "false",
                  body: "Some code.", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "false", date: "2026-09-10",
                  body: "Nothing here.", in: made.course)

        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_publish_class_on", arguments: ["course": "ICS3U", "section": 1, "date": "2026-09-08"]
        ))
        XCTAssertTrue(planned.shouldContinue)
        XCTAssertTrue(planned.detail.contains("Nothing has been changed."))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"),
                      "A plan changes nothing.")

        let done: AssistToolOutcome = await made.runner.run(call: call(
            "publish_class_on", arguments: ["course": "ICS3U", "section": 1, "date": "2026-09-08"]
        ))
        XCTAssertFalse(done.shouldContinue)
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: true"))
        // Followed transitively: the class links to Loops, and Loops links to
        // Snippets. Stopping at one hop leaves a student one click from
        // nothing.
        XCTAssertTrue(text(ofCourseLevelPage: "Loops", in: made.course).contains("publishForSection1: true"))
        XCTAssertTrue(text(ofCourseLevelPage: "Snippets", in: made.course).contains("publishForSection1: true"))
        // The class nobody asked about is left exactly as it was.
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("publish: false"))
        XCTAssertEqual(made.siteWork.previewRebuilds, 1, "A change rebuilds the preview by itself.")
    }

    /// No class on that day is a sentence, not a crash — and nothing is
    /// written.
    @MainActor
    func testPublishingAClassOnADayWithNoClassChangesNothing() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-08", body: "Loops.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "publish_class_on", arguments: ["course": "ICS3U", "section": 1, "date": "2026-12-25"]
        ))
        XCTAssertFalse(outcome.shouldContinue, "A refused write is still the end of the turn.")
        XCTAssertTrue(outcome.summary.contains("can't find a class"), outcome.summary)
        XCTAssertFalse(outcome.summary.contains("list_pages"),
                       "A tool name was shown to a teacher: \(outcome.summary)")
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"))
    }

    /// The older spelling means the OPPOSITE, is read correctly, and is written
    /// back in the spelling the teacher used.
    @MainActor
    func testTheOlderDraftSpellingIsReadAndKept() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let page: String = """
        ---
        title: Unit 1, Day 1
        draft: true
        created: 2026-09-08T07:00:00.000-0400
        ---

        Loops.
        """
        let url: URL = ClassPages.folderURL(forSection: 1, in: made.course)
            .appendingPathComponent("Unit 1, Day 1.md")
        try page.write(to: url, atomically: true, encoding: .utf8)

        // `draft: true` is a page students cannot see, so the check must count
        // it as hidden rather than as published.
        let checked: AssistToolOutcome = await made.runner.run(call: call(
            "check_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(checked.detail.contains("Students would see 0 pages in ICS3U Section 1."))

        let published: AssistToolOutcome = await made.runner.run(call: call(
            "publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        XCTAssertFalse(published.shouldContinue)
        let after: String = text(ofPage: "Unit 1, Day 1", in: made.course)
        XCTAssertTrue(after.contains("draft: false"), "The teacher's own spelling is kept, inverted.")
        XCTAssertFalse(after.contains("publish:"), "No second key is invented behind their back.")
    }

    /// Choosing classes by date, so "hide everything from next Monday on" is
    /// one call and the comparison is never something the model does.
    @MainActor
    func testPagesCanBeChosenByDateRatherThanByName() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "One.", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-10", body: "Two.", in: made.course)
        try write(page: "Unit 1, Day 3", publish: "true", date: "2026-09-14", body: "Three.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages",
            arguments: ["course": "ICS3U", "section": 1, "onOrAfter": "2026-09-10"]
        ))
        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: true"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("publish: false"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 3", in: made.course).contains("publish: false"))
    }

    /// Undo puts exactly those pages back — and leaves alone anything the
    /// teacher has edited since, because losing ten minutes of their writing to
    /// "undo that" would be far worse than not undoing at all.
    @MainActor
    func testUndoPutsPagesBackAndLeavesNewerWorkAlone() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "false", body: "Two.", in: made.course)

        let nothingYet: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))
        XCTAssertEqual(nothingYet.summary, AssistWording.nothingToUndo)

        _ = await made.runner.run(call: call(
            "publish_pages",
            arguments: ["course": "ICS3U", "section": 1,
                        "pages": "Unit 1, Day 1; Unit 1, Day 2"]
        ))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: true"))

        let undone: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))
        XCTAssertFalse(undone.shouldContinue)
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("publish: false"))

        // Now publish again, edit one of them the way a teacher would, and undo.
        _ = await made.runner.run(call: call(
            "publish_pages",
            arguments: ["course": "ICS3U", "section": 1,
                        "pages": "Unit 1, Day 1; Unit 1, Day 2"]
        ))
        let edited: String = text(ofPage: "Unit 1, Day 2", in: made.course) + "\n\nWritten since.\n"
        try edited.write(
            to: ClassPages.folderURL(forSection: 1, in: made.course)
                .appendingPathComponent("Unit 1, Day 2.md"),
            atomically: true, encoding: .utf8
        )

        let partly: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("Written since."),
                      "Newer work is never thrown away by an undo.")
        XCTAssertTrue(partly.detail.contains("left alone"), partly.detail)
    }

    // MARK: - Asking for the schedule when it is missing

    /// A request that needs the dates, from a teacher who has never given
    /// them, opens the sheet that collects them.
    ///
    /// The sheet already existed and was wired to exactly two paths — adding a
    /// class, and reading the timetable back — so any OTHER request depending
    /// on the schedule failed with an explanation and no way forward. "I can't
    /// find a class on Monday" is not something a teacher who has never given
    /// their dates can act on; what they need is the question nobody asked.
    @MainActor
    func testARequestNeedingTheScheduleAsksForItWhenThereIsNone() async throws {
        let made = try makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
            SectionSchedulePrompt.shared.stopAsking()
        }
        SectionSchedulePrompt.shared.stopAsking()

        try write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-08",
                  body: "One.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "publish_class_on", arguments: ["course": "ICS3U", "section": 1, "when": "saturday"]
        ))

        XCTAssertFalse(outcome.shouldContinue)
        // OFFERED now, not opened — a form on top of the sentence explaining
        // why it appeared is a demand rather than a question.
        XCTAssertNil(SectionSchedulePrompt.shared.request,
                     "A form appeared before the teacher had read the request")
        let asked = try XCTUnwrap(
            SectionSchedulePrompt.shared.offer,
            "The teacher was told no class could be found and never asked for their dates"
        )
        XCTAssertEqual(asked.courseCode, "ICS3U")
        XCTAssertEqual(asked.sectionNumber, 1)
        XCTAssertFalse(asked.reason.isEmpty, "The sheet has to say why it is asking")
    }

    /// And it does NOT ask when the dates are already on file — the request
    /// failed for some other reason, and a sheet about dates would be
    /// answering a question nobody asked.
    @MainActor
    func testItDoesNotAskForTheScheduleWhenOneIsAlreadyOnFile() async throws {
        let made = try makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
            SectionSchedulePrompt.shared.stopAsking()
        }

        try write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-08",
                  body: "One.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))
        SectionSchedulePrompt.shared.stopAsking()

        _ = await made.runner.run(call: call(
            "publish_class_on", arguments: ["course": "ICS3U", "section": 1, "when": "saturday"]
        ))

        XCTAssertNil(SectionSchedulePrompt.shared.request,
                     "A sheet was opened about dates that are already on file")
        XCTAssertNil(SectionSchedulePrompt.shared.offer,
                     "It asked about dates that are already on file")
    }

    // MARK: - Starting a new unit

    /// The clean case: the last class is Unit 4, Day 12 and nothing follows it.
    @MainActor
    func testStartingANewUnitAfterTheLastClassMakesDayOneOfTheNextUnit() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 11", publish: "true", date: "2026-09-08",
                  body: "Eleven.", in: made.course)
        try write(page: "Unit 4, Day 12", publish: "true", date: "2026-09-10",
                  body: "Twelve.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; 2026-09-10; 2026-09-14"]
        ))

        let command = try XCTUnwrap(
            AssistCardCommand.matching("Start a new unit for the next class")
        )
        var arguments: [String: Any] = ["course": "ICS3U", "section": 1]
        for (key, value) in command.arguments {
            arguments[key] = value
        }
        let outcome: AssistToolOutcome = await made.runner.run(
            call: call(command.toolName, arguments: arguments)
        )

        XCTAssertTrue(outcome.summary.contains("Unit 5, Day 1"), outcome.summary)
        let made5: String = text(ofPage: "Unit 5, Day 1", in: made.course)
        XCTAssertFalse(made5.isEmpty, "Unit 5, Day 1 was not created")
        XCTAssertTrue(made5.contains("publish: false"), "A new class page must start hidden")
        XCTAssertTrue(made5.contains("created: 2026-09-14"),
                      "It should take the next date with no class against it: \(made5)")
    }

    /// The case with pages already written but not published.
    ///
    /// Unit 4 has Days 13 and 14 sitting unpublished. Publication state has
    /// nothing to do with where the next class goes — the new unit still
    /// begins at Day 1, and it takes the next date with no class against it,
    /// which is decided by how many pages exist rather than by what students
    /// can see.
    @MainActor
    func testUnpublishedClassesStillCountWhenStartingANewUnit() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 12", publish: "true", date: "2026-09-08",
                  body: "Twelve.", in: made.course)
        try write(page: "Unit 4, Day 13", publish: "false", date: "2026-09-10",
                  body: "Thirteen.", in: made.course)
        try write(page: "Unit 4, Day 14", publish: "false", date: "2026-09-14",
                  body: "Fourteen.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; 2026-09-10; 2026-09-14; 2026-09-16"]
        ))

        _ = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1, "unit": "next"]
        ))

        let made5: String = text(ofPage: "Unit 5, Day 1", in: made.course)
        XCTAssertFalse(made5.isEmpty, "Unit 5, Day 1 was not created")
        XCTAssertTrue(made5.contains("publish: false"))
        XCTAssertTrue(made5.contains("created: 2026-09-16"),
                      "The three existing pages hold the first three dates: \(made5)")
    }

    /// Without the instruction, the unit carries on as before.
    @MainActor
    func testTheNextClassStaysInTheSameUnitUnlessAskedOtherwise() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 12", publish: "true", date: "2026-09-08",
                  body: "Twelve.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))

        _ = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertFalse(text(ofPage: "Unit 4, Day 13", in: made.course).isEmpty,
                       "The plain request should carry the unit on")
        XCTAssertTrue(text(ofPage: "Unit 5, Day 1", in: made.course).isEmpty,
                      "It started a new unit without being asked")
    }

    /// The numbering rule on its own, including the empty section.
    @MainActor
    func testANewUnitAlwaysBeginsAtDayOne() {
        func summary(_ title: String) -> ClassPageSummary {
            return ClassPageSummary(
                title: title,
                fileURL: URL(fileURLWithPath: "/c/section1/All Classes/\(title).md"),
                date: nil
            )
        }
        XCTAssertEqual(
            NextClassPlanner.firstDayOfANewUnit(after: [summary("Unit 4, Day 12")]).title,
            "Unit 5, Day 1"
        )
        XCTAssertEqual(
            NextClassPlanner.firstDayOfANewUnit(
                after: [summary("Unit 4, Day 12"), summary("Unit 4, Day 14")]
            ).title,
            "Unit 5, Day 1",
            "The day a unit ran to does not change where the next unit starts"
        )
        // Nothing numbered yet: there is no unit to move past.
        XCTAssertEqual(
            NextClassPlanner.firstDayOfANewUnit(after: [summary("Field Trip")]).title,
            "Unit 1, Day 1"
        )
    }

    // MARK: - Re-dating a whole section

    /// The September job: last year's course, this year's dates.
    ///
    /// Classes take dates BY POSITION — the first class the first date — and
    /// the pages each class uses move with it. A page Key Links points at goes
    /// to the first day of class.
    @MainActor
    func testReDatingPutsClassesOnThisYearsDatesByPosition() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2025-09-08",
                  body: "See [[Stage Directions]].", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", date: "2025-09-10",
                  body: "See [[Blocking]].", in: made.course)
        try write(page: "Unit 2, Day 1", publish: "true", date: "2025-09-14",
                  body: "Nothing linked.", in: made.course)
        try write(courseLevelPage: "Stage Directions", publishForSection1: "true",
                  dated: "2025-09-08", body: "Upstage.", in: made.course)
        try write(courseLevelPage: "Blocking", publishForSection1: "true",
                  dated: "2025-09-10", body: "Where to stand.", in: made.course)
        try write(courseLevelPage: "Drama Journal", inFolder: "Portfolios",
                  publishForSection1: "true", dated: "2025-09-08",
                  body: "All year.", in: made.course)
        try writeKeyLinks(pointingAt: ["Drama Journal"], in: made.course)

        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; 2026-09-10; 2026-09-14; 2026-09-16"]
        ))

        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_re_date_classes", arguments: ["course": "ICS3U", "section": 1]
        ))
        print("\n===== RE-DATE PLAN =====\n\(planned.detail)\n=====\n")
        XCTAssertTrue(planned.isPlan, planned.detail)

        _ = await made.runner.run(call: call(
            "re_date_classes", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("created: 2026-09-08"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("created: 2026-09-10"))
        XCTAssertTrue(text(ofPage: "Unit 2, Day 1", in: made.course).contains("created: 2026-09-14"))

        XCTAssertTrue(
            text(ofCourseLevelPage: "Stage Directions", in: made.course)
                .contains("createdSection1: 2026-09-08")
        )
        XCTAssertTrue(
            text(ofCourseLevelPage: "Blocking", in: made.course)
                .contains("createdSection1: 2026-09-10")
        )
        XCTAssertTrue(
            text(ofCourseLevelPage: "Drama Journal", inFolder: "Portfolios", in: made.course)
                .contains("createdSection1: 2026-09-08"),
            "A page Key Links points at should sit on the first day of class"
        )
    }

    /// More classes than days is the ORDINARY case, not an error.
    ///
    /// It used to refuse outright — which reads as careful and is the
    /// opposite: it left every page on last year's dates, the state the
    /// teacher asked to be rid of, over a few classes at the end they had not
    /// thought about yet. A year is rarely the same length twice. The
    /// leftovers land on the last class date, together, where they cannot be
    /// missed, and the teacher moves or deletes them as part of planning.
    @MainActor
    func testClassesWithNoDayOfTheirOwnGoOnTheLastOne() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        for day in 1...4 {
            try write(page: "Unit 1, Day \(day)", publish: "true", date: "2025-09-0\(day + 7)",
                      body: "Class \(day).", in: made.course)
        }
        // Landing page initially pointed at Day 4
        try writeSectionIndex(pointingAt: "Unit 1, Day 4", in: made.course)

        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))

        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_re_date_classes", arguments: ["course": "ICS3U", "section": 1]
        ))
        print("\n===== OVERFLOW PLAN =====\n\(planned.detail)\n=====\n")
        XCTAssertTrue(planned.detail.contains("2 classes have no day of their own"), planned.detail)
        XCTAssertTrue(planned.detail.contains("Move, publish or delete them"), planned.detail)

        _ = await made.runner.run(call: call(
            "re_date_classes", arguments: ["course": "ICS3U", "section": 1]
        ))

        // The ones that fit stay published and get their scheduled dates.
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("created: 2026-09-08"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: true"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("created: 2026-09-10"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("publish: true"))

        // And the ones that do not land on the last day as drafts (publish: false).
        XCTAssertTrue(text(ofPage: "Unit 1, Day 3", in: made.course).contains("created: 2026-09-10"),
                      "An overflow class was left on last year's date")
        XCTAssertTrue(text(ofPage: "Unit 1, Day 3", in: made.course).contains("publish: false"),
                      "An overflow class must become a draft")
        XCTAssertTrue(text(ofPage: "Unit 1, Day 4", in: made.course).contains("created: 2026-09-10"),
                      "An overflow class was left on last year's date")
        XCTAssertTrue(text(ofPage: "Unit 1, Day 4", in: made.course).contains("publish: false"),
                      "An overflow class must become a draft")

        // The landing page should now transclude the last in-bounds published class (Unit 1, Day 2).
        let indexText: String = try sectionIndexText(in: made.course)
        XCTAssertTrue(indexText.contains("![[Unit 1, Day 2]]"),
                      "The section index must repoint to the newest published class, not an overflow draft: \(indexText)")
    }

    /// Curriculum pages are left alone: the toolchain dates those itself on
    /// every build, to the LATEST date, and it does it to the copy it
    /// publishes — so anything written here would be overwritten.
    @MainActor
    func testReDatingLeavesCurriculumPagesAlone() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2025-09-08",
                  body: "See [[A1.1]].", in: made.course)
        try write(courseLevelPage: "A1.1", inFolder: "Curriculum",
                  publishForSection1: "true", dated: "2025-09-08",
                  body: "An expectation.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))

        _ = await made.runner.run(call: call(
            "re_date_classes", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertTrue(
            text(ofCourseLevelPage: "A1.1", inFolder: "Curriculum", in: made.course)
                .contains("createdSection1: 2025-09-08"),
            "A curriculum page was re-dated; build_site.py owns those"
        )
    }

    /// One undo takes the whole re-dating back.
    @MainActor
    func testUndoingAReDatingPutsEveryDateBack() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2025-09-08",
                  body: "One.", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", date: "2025-09-10",
                  body: "Two.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))
        _ = await made.runner.run(call: call(
            "re_date_classes", arguments: ["course": "ICS3U", "section": 1]
        ))

        let undone: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))
        XCTAssertTrue(undone.summary.contains("re-dated"), undone.summary)
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("created: 2025-09-08"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("created: 2025-09-10"))
    }

    /// Without dates it asks for them, through the same offer as everything
    /// else — re-dating IS the schedule, applied.
    @MainActor
    func testReDatingWithNoDatesAsksForThem() async throws {
        let made = try makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
            SectionSchedulePrompt.shared.stopAsking()
        }
        SectionSchedulePrompt.shared.stopAsking()

        try write(page: "Unit 1, Day 1", publish: "true", date: "2025-09-08",
                  body: "One.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "re_date_classes", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertTrue(outcome.summary.contains(AssistWording.mayIAskForYourDates), outcome.summary)
        XCTAssertNotNil(SectionSchedulePrompt.shared.offer)
        XCTAssertNil(SectionSchedulePrompt.shared.request, "It opened a form unasked")
    }

    // MARK: - Asking for the class dates rather than demanding them

    /// The sheet is OFFERED, not opened. It used to appear on top of the
    /// sentence explaining why it had appeared.
    @MainActor
    func testNeedingDatesOffersRatherThanOpeningTheSheet() async throws {
        let made = try makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
            SectionSchedulePrompt.shared.stopAsking()
        }
        SectionSchedulePrompt.shared.stopAsking()

        try write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-08",
                  body: "One.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertNil(SectionSchedulePrompt.shared.request,
                     "A form appeared before the teacher had read the request")
        let offer = try XCTUnwrap(
            SectionSchedulePrompt.shared.offer,
            "Nothing asked the teacher for their dates"
        )
        XCTAssertEqual(offer.courseCode, "ICS3U")
        XCTAssertTrue(outcome.summary.contains(AssistWording.mayIAskForYourDates), outcome.summary)

        // Yes opens it; nothing else does.
        SectionSchedulePrompt.shared.acceptOffer()
        XCTAssertNotNil(SectionSchedulePrompt.shared.request)
        XCTAssertNil(SectionSchedulePrompt.shared.offer)
    }

    /// And declining opens nothing at all.
    @MainActor
    func testDecliningTheOfferOpensNothing() async throws {
        let made = try makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
            SectionSchedulePrompt.shared.stopAsking()
        }
        SectionSchedulePrompt.shared.stopAsking()

        try write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-08",
                  body: "One.", in: made.course)
        _ = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))

        SectionSchedulePrompt.shared.declineOffer()
        XCTAssertNil(SectionSchedulePrompt.shared.offer)
        XCTAssertNil(SectionSchedulePrompt.shared.request)
    }

    /// A teacher who VOLUNTEERS dates gets the sheet straight away — asking
    /// "may I ask you for your dates?" of somebody offering them reads as not
    /// listening.
    @MainActor
    func testARevisedListOpensTheSheetWithoutAsking() async throws {
        let made = try makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
            SectionSchedulePrompt.shared.stopAsking()
        }
        SectionSchedulePrompt.shared.stopAsking()

        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))
        SectionSchedulePrompt.shared.stopAsking()

        let command = try XCTUnwrap(
            AssistCardCommand.matching("I have a revised list of class dates")
        )
        var arguments: [String: Any] = ["course": "ICS3U", "section": 1]
        for (key, value) in command.arguments {
            arguments[key] = value
        }
        let outcome: AssistToolOutcome = await made.runner.run(
            call: call(command.toolName, arguments: arguments)
        )

        XCTAssertNotNil(SectionSchedulePrompt.shared.request,
                        "The teacher offered their dates and nothing opened")
        XCTAssertNil(SectionSchedulePrompt.shared.offer, "It asked a question already answered")
        XCTAssertTrue(outcome.summary.contains("replaces"), outcome.summary)
    }

    /// Where the dates came from is not a clause that finishes the sentence
    /// about how many there are.
    @MainActor
    func testTheTimetableSummaryDoesNotTrailOffIntoItsSource() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10", "source": "typed in by hand"]
        ))
        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "read_remembered_timetable", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertFalse(outcome.summary.contains("meets on 2 recorded days, from typed in by hand"),
                       "The sentence trails off into where the dates came from: \(outcome.summary)")
        XCTAssertTrue(outcome.summary.contains("Where they came from: typed in by hand"), outcome.summary)
    }

    // MARK: - "What dates am I teaching?"

    /// The week first, then an offer — and the offer names words the window
    /// actually understands.
    ///
    /// The answer used to carry no dates at all: a count and two endpoints, so
    /// a teacher asking what they were teaching was told how many days there
    /// were and left to go and look.
    /// The next upcoming classes first, with page titles and dates, and an offer
    /// for all dates — without continuing into the LLM.
    @MainActor
    func testTheTimetableAnswersWithUpcomingClassesThenOffersTheRest() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "one", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-10", body: "two", in: made.course)

        // The fixture's clock is 2026-09-08. Three upcoming dates are shown;
        // the fourth is beyond the top 3.
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; 2026-09-10; 2026-09-14; 2026-09-24"]
        ))

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "read_remembered_timetable", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertFalse(outcome.shouldContinue, "Deterministic answer finishes turn immediately")
        XCTAssertTrue(outcome.summary.contains("Your next 3 upcoming classes for ICS3U Section 1:"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains("Tuesday, 2026-09-08 — Unit 1, Day 1"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains("Thursday, 2026-09-10 — Unit 1, Day 2"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains("Monday, 2026-09-14 — (page not yet created)"), outcome.summary)
        XCTAssertFalse(outcome.summary.contains("Thursday, 2026-09-24"), outcome.summary)

        // The offer, and the words it names must be words the window matches.
        XCTAssertTrue(outcome.summary.contains("There is 1 more."), outcome.summary)
        let offered: String = "show me all the dates"
        XCTAssertTrue(outcome.summary.lowercased().contains(offered), outcome.summary)
        XCTAssertEqual(AssistCardCommand.matching(offered)?.toolName, "read_remembered_timetable",
                       "The assistant offered words nothing understands")
    }

    /// Taking the offer up lists the lot.
    @MainActor
    func testAskingForTheRestListsEveryDate() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; 2026-09-10; 2026-09-14; 2026-09-24"]
        ))

        let command = try XCTUnwrap(AssistCardCommand.matching("Show me all the dates"))
        var arguments: [String: Any] = ["course": "ICS3U", "section": 1]
        for (key, value) in command.arguments {
            arguments[key] = value
        }
        let outcome: AssistToolOutcome = await made.runner.run(
            call: call(command.toolName, arguments: arguments)
        )

        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(outcome.summary.contains("Every date on file for ICS3U Section 1:"), outcome.summary)
        for every in ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-24"] {
            XCTAssertTrue(outcome.summary.contains(every), "\(every) missing: \(outcome.summary)")
        }
    }

    /// Before the semester starts, it shows the first classes of the semester.
    @MainActor
    func testBeforeSemesterStartsShowsFirstClasses() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-11-02; 2026-11-04"]
        ))

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "read_remembered_timetable", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(outcome.summary.contains("The semester begins on Monday, 2026-11-02. The first 2 classes are:"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains("2026-11-02"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains("2026-11-04"), outcome.summary)
    }

    // MARK: - "Publish Monday's class"

    /// Every weekday is a fixed phrasing, so the date is worked out in code and
    /// cannot be one the model invented.
    @MainActor
    func testEachWeekdaysClassIsAFixedPhrasing() {
        for day in ["Monday", "Tuesday", "Wednesday", "Thursday",
                    "Friday", "Saturday", "Sunday"] {
            let matched = AssistCardCommand.matching("Publish \(day)'s class")
            XCTAssertEqual(matched?.toolName, "publish_class_on", day)
            XCTAssertEqual(matched?.arguments["when"], day.lowercased(), day)
        }
    }

    /// "monday" means the next Monday — and TODAY when today is a Monday,
    /// which is the reading a person gives it while preparing that morning.
    @MainActor
    func testAWeekdayNameResolvesForwardsAndCountsToday() throws {
        // 2026-08-17 is a Monday.
        let monday: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-08-17"))
        let sunday: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-08-16"))

        XCTAssertEqual(AssistToolRunner.day(named: "monday", today: sunday)?.text, "2026-08-17")
        XCTAssertEqual(AssistToolRunner.day(named: "monday", today: monday)?.text, "2026-08-17",
                       "Asked on a Monday, “Monday” is today's class")
        XCTAssertEqual(AssistToolRunner.day(named: "friday", today: monday)?.text, "2026-08-21")
        XCTAssertEqual(AssistToolRunner.day(named: "sunday", today: monday)?.text, "2026-08-23")

        // The apostrophe belongs to the phrasing, not to the day.
        XCTAssertEqual(AssistToolRunner.day(named: "monday's", today: sunday)?.text, "2026-08-17")

        // The forms that already worked still do.
        XCTAssertEqual(AssistToolRunner.day(named: "tomorrow", today: sunday)?.text, "2026-08-17")
        XCTAssertEqual(AssistToolRunner.day(named: "2026-10-06", today: sunday)?.text, "2026-10-06")
        XCTAssertNil(AssistToolRunner.day(named: "someday", today: sunday))
    }

    /// A weekday with no class stops and says so — in words, without naming a
    /// tool at a teacher.
    @MainActor
    func testAWeekdayWithNoClassStopsAndExplains() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-08",
                  body: "The only class.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "publish_class_on", arguments: ["course": "ICS3U", "section": 1, "when": "saturday"]
        ))

        XCTAssertFalse(outcome.shouldContinue, "It has to stop, not carry on")
        XCTAssertTrue(outcome.summary.contains("Saturday"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains("can't find a class"), outcome.summary)
        XCTAssertFalse(outcome.summary.contains("list_pages"),
                       "A tool name was shown to a teacher: \(outcome.summary)")
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"),
                      "Nothing should have been published")
    }

    /// And a weekday that DOES have a class publishes that class.
    @MainActor
    func testAWeekdayWithAClassPublishesThatClass() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        // The fixture's clock is fixed at 2026-09-08, which IS a Tuesday — so
        // this exercises the today-counts rule as well: asked on a Tuesday for
        // "Tuesday's class", a teacher means the one they are about to teach.
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-08"))
        let tuesday: CalendarDay = try XCTUnwrap(
            AssistToolRunner.day(named: "tuesday", today: today)
        )
        XCTAssertEqual(tuesday.text, "2026-09-08")
        try write(page: "Unit 2, Day 3", publish: "false", date: tuesday.text,
                  body: "Tuesday's lesson.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "publish_class_on", arguments: ["course": "ICS3U", "section": 1, "when": "tuesday"]
        ))

        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(text(ofPage: "Unit 2, Day 3", in: made.course).contains("publish: true"),
                      outcome.summary)
    }

    // MARK: - Only a VISIBLE page keeps another one published

    /// A page held up by a draft nobody has published comes down.
    ///
    /// "X still links to it" was counted whether or not students could see X,
    /// so a page could sit visible, reachable from nothing, kept alive by a
    /// page that is not there.
    @MainActor
    func testAHiddenPageDoesNotKeepAnotherPagePublished() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", body: "See [[Ohm's Law]].", in: made.course)
        // Written but never published — so it cannot be a reason to keep
        // anything visible.
        try write(page: "Unit 1, Day 2", publish: "false", body: "Also [[Ohm's Law]].",
                  in: made.course)
        try write(courseLevelPage: "Ohm's Law", publishForSection1: "true",
                  body: "Voltage over current.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))

        // The rule this proves is written down in
        // shared-rules.json → followingLinks, so both apps run it.
        XCTAssertTrue(
            text(ofCourseLevelPage: "Ohm's Law", in: made.course).contains("publishForSection1: false"),
            "A page was left visible, reachable from nothing, held up by a draft: \(outcome.detail)"
        )
        XCTAssertFalse(outcome.detail.contains("Unit 1, Day 2"),
                       "A hidden page was named as a reason to keep something: \(outcome.detail)")
    }

    /// And a VISIBLE page still keeps it, which is the rule that stops one
    /// class being broken to tidy another.
    @MainActor
    func testAVisiblePageStillKeepsAnotherPagePublished() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", body: "See [[Ohm's Law]].", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", body: "Also [[Ohm's Law]].", in: made.course)
        try write(courseLevelPage: "Ohm's Law", publishForSection1: "true",
                  body: "Voltage over current.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))

        XCTAssertTrue(
            text(ofCourseLevelPage: "Ohm's Law", in: made.course).contains("publishForSection1: true"),
            "Hiding this week's lesson broke last week's"
        )
        XCTAssertTrue(outcome.detail.contains("“Unit 1, Day 2” still links to it"), outcome.detail)
    }

    /// The corollary, which already held and is now pinned: publishing a class
    /// publishes the hidden pages it links to, and SAYS so in the plan.
    @MainActor
    func testPublishingAClassPublishesTheHiddenPagesItLinksToAndSaysSo() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "false", body: "See [[Ohm's Law]].", in: made.course)
        try write(courseLevelPage: "Ohm's Law", publishForSection1: "false",
                  body: "Voltage over current.", in: made.course)

        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        XCTAssertTrue(planned.detail.contains("“Ohm's Law” will become visible"),
                      "The plan did not disclose the linked page: \(planned.detail)")

        _ = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        XCTAssertTrue(
            text(ofCourseLevelPage: "Ohm's Law", in: made.course).contains("publishForSection1: true")
        )
    }

    /// The four kinds of page the visible-referrer rule must never reach.
    ///
    /// Narrowing "X still links to it" to VISIBLE referrers made more pages
    /// eligible to come down, so the exclusions above it matter more than they
    /// did. Each is checked with the ONLY page linking to it hidden — the
    /// exact situation the narrowing created — and each must survive:
    ///
    /// * a page **Key Links** points at,
    /// * **All Classes**, and every other folder landing page,
    /// * anything under **Curriculum**,
    /// * the **index page of a sidebar folder**.
    ///
    /// They sit above the referrer test in `reasonToKeep`, so this is a test
    /// that the ORDER is load-bearing rather than incidental.
    @MainActor
    func testTheKindsOfPageThatAreNeverTakenDownByFollowingLinks() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        // The class being unpublished links to one of each.
        try write(page: "Unit 1, Day 1", publish: "true",
                  body: "See [[Drama Journal]], [[All Classes]], [[A1.1]] and [[Portfolios]].",
                  in: made.course)
        // …and the ONLY other page linking to them is hidden, so without the
        // exclusions every one of these would now be swept.
        try write(page: "Unit 1, Day 2", publish: "false",
                  body: "Also [[Drama Journal]], [[All Classes]], [[A1.1]] and [[Portfolios]].",
                  in: made.course)

        try write(courseLevelPage: "Drama Journal", inFolder: "Portfolios",
                  publishForSection1: "true", body: "The journal.", in: made.course)
        try write(courseLevelPage: "A1.1", inFolder: "Curriculum",
                  publishForSection1: "true", body: "An expectation.", in: made.course)
        try write(folderIndex: "Portfolios", titled: "Portfolios",
                  publishForSection1: "true", body: "The hub.", in: made.course)
        try writeKeyLinks(pointingAt: ["Drama Journal"], in: made.course)
        try writeAllClassesIndex(in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        XCTAssertFalse(outcome.shouldContinue)

        XCTAssertTrue(
            text(ofCourseLevelPage: "Drama Journal", inFolder: "Portfolios", in: made.course)
                .contains("publishForSection1: true"),
            "A page Key Links points at was taken down"
        )
        XCTAssertTrue(
            text(ofCourseLevelPage: "A1.1", inFolder: "Curriculum", in: made.course)
                .contains("publishForSection1: true"),
            "A curriculum page was taken down"
        )
        XCTAssertTrue(
            folderIndexText("Portfolios", in: made.course).contains("publishForSection1: true"),
            "A sidebar folder's landing page was taken down"
        )
        XCTAssertTrue(
            allClassesIndexText(in: made.course).contains("publish: true"),
            "All Classes was taken down"
        )
    }

    /// A section's Key Links page, which decides what a section cannot do
    /// without.
    @MainActor
    private func writeKeyLinks(pointingAt titles: [String], in course: Course) throws {
        var body: String = "---\ntitle: Key Links\npublish: true\n"
        body += "created: 2026-09-08T07:00:00.000-0400\n---\n\n"
        for title in titles {
            body += "- [[\(title)]]\n"
        }
        let folder: URL = course.directoryURL.appendingPathComponent("section1")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try body.write(to: folder.appendingPathComponent("Key Links.md"),
                       atomically: true, encoding: .utf8)
    }

    /// The All Classes listing, which is a folder landing page.
    @MainActor
    private func writeAllClassesIndex(in course: Course) throws {
        let body: String = """
        ---
        title: All Classes
        publish: true
        created: 2026-09-08T07:00:00.000-0400
        ---

        One page per class.
        """
        let folder: URL = ClassPages.folderURL(forSection: 1, in: course)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try body.write(to: folder.appendingPathComponent("index.md"),
                       atomically: true, encoding: .utf8)
    }

    @MainActor
    private func folderIndexText(_ folder: String, in course: Course) -> String {
        let url: URL = course.directoryURL.appendingPathComponent(folder)
            .appendingPathComponent("index.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @MainActor
    private func allClassesIndexText(in course: Course) -> String {
        let url: URL = ClassPages.folderURL(forSection: 1, in: course)
            .appendingPathComponent("index.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Duplicating a class

    /// "Duplicate Unit 3, Day 2 as my next class" — the copy is the next day
    /// of the same unit, with the source's content and a date of its own.
    @MainActor
    func testDuplicatingAClassCopiesItToTheNextDayWithItsOwnDate() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 3, Day 1", publish: "true", date: "2026-09-08",
                  body: "First.", in: made.course)
        try write(page: "Unit 3, Day 2", publish: "true", date: "2026-09-10",
                  body: "The workshop plan, written out in full.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; 2026-09-10; 2026-09-14; 2026-09-16"]
        ))

        let command = try XCTUnwrap(
            AssistCardCommand.matching("Duplicate Unit 3, Day 2 as my next class")
        )
        XCTAssertEqual(command.arguments["duplicate"], "Unit 3, Day 2")
        var arguments: [String: Any] = ["course": "ICS3U", "section": 1]
        for (key, value) in command.arguments {
            arguments[key] = value
        }
        let outcome: AssistToolOutcome = await made.runner.run(
            call: call(command.toolName, arguments: arguments)
        )

        let copy: String = text(ofPage: "Unit 3, Day 3", in: made.course)
        XCTAssertFalse(copy.isEmpty, "Unit 3, Day 3 was not created: \(outcome.detail)")
        XCTAssertTrue(copy.contains("The workshop plan, written out in full."),
                      "The content was not copied: \(copy)")
        XCTAssertTrue(copy.contains("title: Unit 3, Day 3"), copy)
        XCTAssertTrue(copy.contains("created: 2026-09-14"),
                      "The copy should take the next free date: \(copy)")
        XCTAssertTrue(copy.contains("publish: false"),
                      "A duplicate of a PUBLISHED lesson must still start hidden: \(copy)")
        // The source is untouched.
        XCTAssertTrue(text(ofPage: "Unit 3, Day 2", in: made.course).contains("publish: true"))
    }

    /// And when the next day already exists, the classes after it shift along
    /// to make room — which is `ClassInsertionPlanner`'s job, renaming from the
    /// highest day down so nothing is written over.
    @MainActor
    func testDuplicatingShiftsLaterClassesToMakeRoom() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 3, Day 1", publish: "false", date: "2026-09-08",
                  body: "First.", in: made.course)
        try write(page: "Unit 3, Day 2", publish: "false", date: "2026-09-10",
                  body: "The one to copy.", in: made.course)
        try write(page: "Unit 3, Day 3", publish: "false", date: "2026-09-14",
                  body: "Was Day 3.", in: made.course)
        try write(page: "Unit 3, Day 4", publish: "false", date: "2026-09-16",
                  body: "Was Day 4.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; 2026-09-10; 2026-09-14; 2026-09-16; 2026-09-18"]
        ))

        _ = await made.runner.run(call: call(
            "add_next_class",
            arguments: ["course": "ICS3U", "section": 1, "duplicate": "Unit 3, Day 2"]
        ))

        // The copy landed at Day 3, and the old Day 3 and Day 4 moved along.
        XCTAssertTrue(text(ofPage: "Unit 3, Day 3", in: made.course).contains("The one to copy."))
        XCTAssertTrue(text(ofPage: "Unit 3, Day 4", in: made.course).contains("Was Day 3."))
        XCTAssertTrue(text(ofPage: "Unit 3, Day 5", in: made.course).contains("Was Day 4."))
    }

    /// A page nobody has is refused in words.
    @MainActor
    func testDuplicatingAPageThatIsNotThereIsRefused() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try write(page: "Unit 3, Day 1", publish: "false", date: "2026-09-08",
                  body: "One.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class",
            arguments: ["course": "ICS3U", "section": 1, "duplicate": "Unit 9, Day 9"]
        ))
        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(outcome.summary.contains("Unit 9, Day 9"), outcome.summary)
    }

    // MARK: - A whole unit at a time

    /// The phrasings are matched in code, for any unit number.
    @MainActor
    func testWholeUnitPhrasingsAreMatchedInCode() {
        for unit in [1, 4, 12] {
            XCTAssertEqual(
                AssistCardCommand.matching("Unpublish Unit \(unit)")?.arguments["pages"],
                "Unit \(unit)"
            )
            XCTAssertEqual(
                AssistCardCommand.matching("Unpublish Unit \(unit)")?.toolName, "unpublish_pages"
            )
            XCTAssertEqual(
                AssistCardCommand.matching("Publish Unit \(unit)")?.toolName, "publish_pages"
            )
        }
        // One page, not a unit — this must still go to the model, which has a
        // page title to read out of it.
        XCTAssertNil(AssistCardCommand.matching("Publish Unit 4, Day 3"))
    }

    /// "Unpublish Unit 4" takes every class in the unit down and says one
    /// thing about it.
    @MainActor
    func testUnpublishingAWholeUnitTakesEveryClassDownAndReportsOnce() async throws {
        let made = try makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
            FakePreview.shared.forget()
        }

        for day in 1...3 {
            try write(page: "Unit 4, Day \(day)", publish: "true", date: "2026-09-0\(day + 7)",
                      body: "Day \(day).", in: made.course)
        }
        try write(page: "Unit 5, Day 1", publish: "true", date: "2026-09-14",
                  body: "A later unit.", in: made.course)

        FakePreview.shared.register(
            folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1
        )

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4"]
        ))

        XCTAssertEqual(outcome.summary, "Unit 4 was unpublished.")
        for day in 1...3 {
            XCTAssertTrue(
                text(ofPage: "Unit 4, Day \(day)", in: made.course).contains("publish: false"),
                "Unit 4, Day \(day) is still published"
            )
        }
        XCTAssertTrue(text(ofPage: "Unit 5, Day 1", in: made.course).contains("publish: true"),
                      "A class outside the unit was taken down")

        // Stopped once, started once — not once per page.
        XCTAssertEqual(FakePreview.shared.events.filter { $0 == "stop-begins" }.count, 1)
        XCTAssertEqual(FakePreview.shared.events.filter { $0 == "start" }.count, 1)
        XCTAssertEqual(FakePreview.shared.events.first, "stop-begins")
        XCTAssertEqual(FakePreview.shared.events.last, "start")
    }

    /// "Publish Unit 5" is the mirror, walking Day 1 forwards.
    @MainActor
    func testPublishingAWholeUnitPutsEveryClassUp() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        for day in 1...3 {
            try write(page: "Unit 5, Day \(day)", publish: "false", date: "2026-09-0\(day + 7)",
                      body: "Day \(day).", in: made.course)
        }

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 5"]
        ))

        XCTAssertEqual(outcome.summary, "Unit 5 was published.")
        for day in 1...3 {
            XCTAssertTrue(
                text(ofPage: "Unit 5, Day \(day)", in: made.course).contains("publish: true"),
                "Unit 5, Day \(day) is still hidden"
            )
        }
    }

    /// The whole unit is ONE thing on the undo list, not one page of it.
    @MainActor
    func testUndoingAWholeUnitPutsAllOfItBack() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        for day in 1...3 {
            try write(page: "Unit 4, Day \(day)", publish: "true", date: "2026-09-0\(day + 7)",
                      body: "Day \(day).", in: made.course)
        }

        _ = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4"]
        ))
        let undone: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))

        XCTAssertEqual(undone.summary, AssistWording.undid("unpublished Unit 4"))
        for day in 1...3 {
            XCTAssertTrue(
                text(ofPage: "Unit 4, Day \(day)", in: made.course).contains("publish: true"),
                "Unit 4, Day \(day) did not come back"
            )
        }
    }

    /// A unit already in the state asked for says so, and writes nothing.
    @MainActor
    func testAUnitAlreadyHiddenSaysSo() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 1", publish: "false", date: "2026-09-08",
                  body: "One.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4"]
        ))
        XCTAssertEqual(outcome.summary, "Unit 4 is already hidden.")
    }

    /// A unit nobody has is said plainly.
    @MainActor
    func testAUnitThatDoesNotExistIsRefusedInWords() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08",
                  body: "One.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 9"]
        ))
        XCTAssertTrue(outcome.summary.contains("can't find any class pages in Unit 9"),
                      outcome.summary)
    }

    // MARK: - Adding several days to a unit

    /// "Add five more days to Unit 4" continues from the last day that EXISTS
    /// in that unit — published or not — and dates them from the schedule.
    @MainActor
    func testAddingMoreDaysToAUnitContinuesFromTheLastOneThatExists() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 1", publish: "true", date: "2026-09-08",
                  body: "One.", in: made.course)
        try write(page: "Unit 4, Day 2", publish: "false", date: "2026-09-10",
                  body: "Written, not shown.", in: made.course)
        // Two pages already hold the first two dates, so five more days needs
        // seven dates on file.
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; 2026-09-10; 2026-09-14; 2026-09-16; "
                               + "2026-09-18; 2026-09-22; 2026-09-24"]
        ))

        let command = try XCTUnwrap(AssistCardCommand.matching("Add five more days to unit 4"))
        XCTAssertEqual(command.toolName, "add_next_class")
        var arguments: [String: Any] = ["course": "ICS3U", "section": 1]
        for (key, value) in command.arguments {
            arguments[key] = value
        }
        _ = await made.runner.run(call: call(command.toolName, arguments: arguments))

        // Day 2 exists but is hidden — numbering still continues past it, so
        // the five new days are 3 to 7 rather than 2 to 6.
        for day in 3...7 {
            let page: String = text(ofPage: "Unit 4, Day \(day)", in: made.course)
            XCTAssertFalse(page.isEmpty, "Unit 4, Day \(day) was not created")
            XCTAssertTrue(page.contains("publish: false"), "Day \(day) should start hidden")
        }
        // Two pages existed, so the new ones take the third date onwards.
        let expected: [Int: String] = [
            3: "2026-09-14", 4: "2026-09-16", 5: "2026-09-18",
            6: "2026-09-22", 7: "2026-09-24",
        ]
        for (day, date) in expected {
            XCTAssertTrue(
                text(ofPage: "Unit 4, Day \(day)", in: made.course).contains("created: \(date)"),
                "Unit 4, Day \(day) should fall on \(date)"
            )
        }
    }

    /// Running out of dates does not stop a page being made.
    ///
    /// It used to refuse. A teacher who has just finished teaching and wants
    /// tomorrow's page does not want to be sent away to record dates first —
    /// so the pages are made on the LAST class date, stacked where they cannot
    /// be missed, and the plan says how many are sharing it.
    @MainActor
    func testPagesPastTheEndOfTheTimetableGoOnTheLastDay() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 1", publish: "true", date: "2026-09-08",
                  body: "One.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class",
            arguments: ["course": "ICS3U", "section": 1, "unit": "4", "days": "3"]
        ))

        // One page had a date of its own; the other two share the last day.
        XCTAssertTrue(text(ofPage: "Unit 4, Day 2", in: made.course).contains("created: 2026-09-10"))
        XCTAssertTrue(text(ofPage: "Unit 4, Day 3", in: made.course).contains("created: 2026-09-10"),
                      "A page past the end of the timetable was not created")
        XCTAssertTrue(text(ofPage: "Unit 4, Day 4", in: made.course).contains("created: 2026-09-10"),
                      "A page past the end of the timetable was not created")
        XCTAssertTrue(outcome.detail.contains("share the last day"), outcome.detail)
    }

    /// And a single next class, past the end, is made the same way.
    @MainActor
    func testTheNextClassIsStillMadeWhenTheDatesHaveRunOut() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08",
                  body: "One.", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-10",
                  body: "Two.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))

        XCTAssertTrue(text(ofPage: "Unit 1, Day 3", in: made.course).contains("created: 2026-09-10"),
                      "The teacher was sent away to record dates instead of getting their page")
        XCTAssertTrue(outcome.detail.contains("shares the last day"), outcome.detail)
    }

    /// The digits work as well as the words.
    @MainActor
    func testAddingDaysAcceptsAWordOrANumber() {
        for phrasing in ["Add five more days to unit 4", "Add 5 more days to unit 4"] {
            let matched = AssistCardCommand.matching(phrasing)
            XCTAssertEqual(matched?.arguments["days"], "5", phrasing)
            XCTAssertEqual(matched?.arguments["unit"], "4", phrasing)
        }
        XCTAssertNil(AssistCardCommand.matching("Add more days to unit 4"))
    }

    // MARK: - Asking for something that is already done

    /// "Publish Unit 4, Day 23" on a class that is already published gets four
    /// words back, not a plan.
    @MainActor
    func testPublishingAPageThatIsAlreadyPublishedSaysSoAndNothingElse() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 23", publish: "true", date: "2026-09-08",
                  body: "See [[Bananas]].", in: made.course)
        try write(courseLevelPage: "Bananas", publishForSection1: "true",
                  body: "Yellow.", in: made.course)

        for tool in ["plan_publish_pages", "publish_pages"] {
            let outcome: AssistToolOutcome = await made.runner.run(call: call(
                tool, arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4, Day 23"]
            ))
            XCTAssertEqual(outcome.summary, "It's already been published.", tool)
            XCTAssertEqual(outcome.detail, "It's already been published.", tool)
            XCTAssertFalse(outcome.isPlan, "\(tool) asked to approve a no-op")
            // None of the plan's furniture.
            for furniture in ["would change", "Shall I", "Nothing needed changing",
                              "already visible", "Section 1: publishing"] {
                XCTAssertFalse(outcome.detail.contains(furniture),
                               "\(tool) still says “\(furniture)”: \(outcome.detail)")
            }
        }
    }

    /// And the mirror, for hiding.
    @MainActor
    func testUnpublishingAPageThatIsAlreadyHiddenSaysSo() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 23", publish: "false", date: "2026-09-08",
                  body: "Nothing yet.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4, Day 23"]
        ))
        XCTAssertEqual(outcome.summary, "It's already hidden.")
    }

    /// Two pages, both already done, get the plural.
    @MainActor
    func testTwoPagesAlreadyPublishedGetThePlural() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08",
                  body: "One.", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-10",
                  body: "Two.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1; Unit 1, Day 2"]
        ))
        XCTAssertEqual(outcome.summary, "They have already been published.")
    }

    /// A page that does NOT exist still gets the full answer — "already done"
    /// and "no such page" are different things and must not be confused.
    @MainActor
    func testANameThatMatchesNoPageStillGetsTheFullAnswer() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 23", publish: "true", date: "2026-09-08",
                  body: "Done.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4, Day 23; Bananas"]
        ))
        XCTAssertNotEqual(outcome.summary, "It's already been published.")
        XCTAssertTrue(outcome.detail.contains("Bananas"),
                      "The page nobody has was not mentioned: \(outcome.detail)")
    }

    /// And a page that genuinely needs publishing is unaffected.
    @MainActor
    func testAPageThatNeedsPublishingStillGetsAPlan() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 23", publish: "false", date: "2026-09-08",
                  body: "Ready.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "plan_publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4, Day 23"]
        ))
        XCTAssertTrue(outcome.isPlan)
        XCTAssertTrue(outcome.detail.contains("will become visible"), outcome.detail)
    }

    // MARK: - What check_section says about the preview

    /// Three states, three different things worth saying — and for one of
    /// them, that nothing is.
    ///
    /// Reported: a teacher looking at a finished preview was told their pages
    /// would appear "once any rebuild in progress finishes", about a rebuild
    /// that had finished minutes earlier. The sentence sat behind a single
    /// boolean meaning "is the launcher running", which stays true for as long
    /// as the site is SERVED — so building and built looked identical.
    @MainActor
    func testWhatIsSaidAboutThePreviewDependsOnWhatItIsDoing() async throws {
        let made = try makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
            FakePreview.shared.forget()
        }
        try write(page: "Unit 1, Day 1", publish: "true", body: "One.", in: made.course)

        // Building: say when the pages will appear.
        FakePreview.shared.register(
            folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1, showing: .building
        )
        var outcome: AssistToolOutcome = await made.runner.run(call: call(
            "check_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(outcome.summary.contains("The preview is building now"), outcome.summary)
        XCTAssertFalse(outcome.summary.contains("Say “Preview”"), outcome.summary)

        // Showing: they are looking at it. Say nothing.
        FakePreview.shared.register(
            folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1, showing: .showing
        )
        outcome = await made.runner.run(call: call(
            "check_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertFalse(outcome.summary.contains("preview is building"), outcome.summary)
        XCTAssertFalse(outcome.summary.contains("once any rebuild"), outcome.summary)
        XCTAssertFalse(outcome.summary.contains("Say “Preview”"),
                       "Told to preview a section already on screen: \(outcome.summary)")

        // Nothing up at all: offer.
        FakePreview.shared.register(
            folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1, showing: .notRunning
        )
        outcome = await made.runner.run(call: call(
            "check_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(outcome.summary.contains("Nothing is being previewed"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains("Say “Preview”"), outcome.summary)
    }

    /// With no section window at all there is nothing on screen either, so the
    /// same offer is the right answer.
    @MainActor
    func testCheckingWithNoWindowOpenSuggestsAPreview() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        SectionWindowControllers.shared.forgetAll()

        try write(page: "Unit 1, Day 1", publish: "true", body: "One.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "check_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(outcome.summary.contains("Nothing is being previewed"), outcome.summary)
    }

    // MARK: - How a plan reads

    /// The plan a teacher actually sees, printed, for both verbs.
    ///
    /// It reported `Bananas  —  publishForSection1: hidden → visible  (linked
    /// from a page you named)` — four pieces of bookkeeping wearing a page
    /// title, including the name of a line in a file. This pins the shape it
    /// reads in now, and prints it so a person can look at it rather than
    /// taking a diff's word for it.
    @MainActor
    func testAPlanReadsAsSentencesWithNoMarkdownOrMachinery() async throws {
        for publishing in [false, true] {
            let made = try makeRunner()
            defer { try? FileManager.default.removeItem(at: made.root) }

            let was: String = publishing ? "false" : "true"
            try write(page: "Unit 4, Day 24", publish: was, date: "2027-01-19",
                      body: "See [[Bananas]].", in: made.course)
            try write(courseLevelPage: "Bananas", publishForSection1: was,
                      dated: "2026-09-08", body: "Yellow.", in: made.course)

            let outcome: AssistToolOutcome = await made.runner.run(call: call(
                publishing ? "plan_publish_pages" : "plan_unpublish_pages",
                arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4, Day 24"]
            ))

            print("\n===== \(publishing ? "PUBLISHING" : "UNPUBLISHING") =====")
            print(outcome.detail)
            print("=====================\n")

            let becoming: String = publishing ? "visible" : "hidden"
            XCTAssertTrue(outcome.detail.contains("“Unit 4, Day 24” will become \(becoming)."),
                          outcome.detail)
            if publishing {
                // The date is a clause on the page's OWN line, not a second
                // list a teacher has to match up by name.
                XCTAssertTrue(
                    outcome.detail.contains(
                        "“Bananas” will become visible, with the same date as “Unit 4, Day 24”."
                    ),
                    outcome.detail
                )
                XCTAssertFalse(outcome.detail.contains("students have not seen before"),
                               "The date block is still there: \(outcome.detail)")
                XCTAssertFalse(outcome.detail.contains("2026-09-08"),
                               "A raw date is still being shown: \(outcome.detail)")
            } else {
                XCTAssertTrue(outcome.detail.contains("“Bananas” will become hidden."),
                              outcome.detail)
            }

            // None of the machinery, in either direction.
            for machinery in ["**", "→", "publishForSection1", "publish: hidden",
                              "publish: visible", "(linked from a page you named)"] {
                XCTAssertFalse(outcome.detail.contains(machinery),
                               "“\(machinery)” is still in the plan: \(outcome.detail)")
            }
            // The grammar bug that reached a teacher: "1 page students is …".
            XCTAssertFalse(outcome.detail.contains("students is "), outcome.detail)
        }
    }

    // MARK: - A class dates the pages it brings with it

    /// The reported change: publishing a class page by NAME dates the pages it
    /// links to, when this publish is the first time students will see them.
    ///
    /// The date a page carries is what orders it on the site, and a page
    /// written weeks early carried the day its FILE was made — which is a fact
    /// about the teacher's evening, not about the course. It should turn up
    /// under the class that brings it.
    @MainActor
    func testPublishingAClassDatesTheNeverSeenPagesItLinksTo() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 2, Day 3", publish: "false", date: "2026-10-06",
                  body: "See [[Blocking and Stage Areas]].", in: made.course)
        try write(courseLevelPage: "Blocking and Stage Areas", publishForSection1: "false",
                  dated: "2026-08-01", body: "Upstage, downstage.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 2, Day 3"]
        ))
        XCTAssertFalse(outcome.shouldContinue)

        let linked: String = text(ofCourseLevelPage: "Blocking and Stage Areas", in: made.course)
        XCTAssertTrue(linked.contains("publishForSection1: true"), linked)
        XCTAssertTrue(linked.contains("createdSection1: 2026-10-06"),
                      "The page a class brought with it kept the day its file was made: \(linked)")
    }

    /// A page students can ALREADY see keeps its date.
    ///
    /// It has a place on the site somebody may have linked to or looked at, and
    /// republishing a class must not shuffle work that was already out.
    @MainActor
    func testAPageStudentsCanAlreadySeeKeepsItsDate() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 2, Day 3", publish: "false", date: "2026-10-06",
                  body: "See [[Drama Journal]].", in: made.course)
        try write(courseLevelPage: "Drama Journal", publishForSection1: "true",
                  dated: "2026-08-01", body: "Write it up.", in: made.course)

        _ = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 2, Day 3"]
        ))

        let linked: String = text(ofCourseLevelPage: "Drama Journal", in: made.course)
        XCTAssertTrue(linked.contains("createdSection1: 2026-08-01"),
                      "A page already out was re-dated underneath the teacher: \(linked)")
    }

    /// A never-seen page moves even when SEVERAL classes link to it.
    ///
    /// The rule used to leave a shared page alone — "it belongs to none of
    /// them" — which is sound for a page already on the site and beside the
    /// point for one nobody can reach. A page students cannot see has no place
    /// to be left in; it has only the day its file was made.
    @MainActor
    func testASharedPageNobodyHasSeenStillTakesTheClassesDate() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 2, Day 3", publish: "false", date: "2026-10-06",
                  body: "See [[Journal Checklist]].", in: made.course)
        try write(page: "Unit 3, Day 1", publish: "false", date: "2026-11-02",
                  body: "See [[Journal Checklist]] again.", in: made.course)
        try write(page: "Unit 4, Day 2", publish: "false", date: "2026-12-01",
                  body: "And [[Journal Checklist]].", in: made.course)
        try write(courseLevelPage: "Journal Checklist", publishForSection1: "false",
                  dated: "2026-08-01", body: "What to hand in.", in: made.course)

        _ = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 2, Day 3"]
        ))

        let linked: String = text(ofCourseLevelPage: "Journal Checklist", in: made.course)
        XCTAssertTrue(linked.contains("createdSection1: 2026-10-06"), linked)
    }

    /// When several classes are published at once, the EARLIEST claims a page
    /// they share — the same convention the course installer already follows.
    @MainActor
    func testTheEarliestClassClaimsAPageSeveralOfThemBring() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 2", publish: "false", date: "2026-12-01",
                  body: "See [[Warm-Up Routine]].", in: made.course)
        try write(page: "Unit 2, Day 3", publish: "false", date: "2026-10-06",
                  body: "See [[Warm-Up Routine]].", in: made.course)
        try write(courseLevelPage: "Warm-Up Routine", publishForSection1: "false",
                  dated: "2026-08-01", body: "Stretch.", in: made.course)

        // Named LATEST first, so an implementation that simply took the first
        // title it was given would get this wrong.
        _ = await made.runner.run(call: call(
            "publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4, Day 2; Unit 2, Day 3"]
        ))

        let linked: String = text(ofCourseLevelPage: "Warm-Up Routine", in: made.course)
        XCTAssertTrue(linked.contains("createdSection1: 2026-10-06"),
                      "The later class claimed a page the earlier one brings: \(linked)")
    }

    /// A class page's date is its place in the schedule. Nothing may move it.
    @MainActor
    func testOneClassNeverRedatesAnother() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 2, Day 3", publish: "false", date: "2026-10-06",
                  body: "Carrying on from [[Unit 2, Day 2]].", in: made.course)
        try write(page: "Unit 2, Day 2", publish: "false", date: "2026-10-05",
                  body: "The one before.", in: made.course)

        _ = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 2, Day 3"]
        ))

        XCTAssertTrue(text(ofPage: "Unit 2, Day 2", in: made.course).contains("created: 2026-10-05"),
                      "A class was moved off its own day in the schedule")
    }

    /// Publishing an ordinary page moves nothing — there is no class day to
    /// inherit, and inventing one would be worse than leaving it alone.
    @MainActor
    func testPublishingAnOrdinaryPageMovesNoDates() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(courseLevelPage: "Stage Directions", publishForSection1: "false",
                  dated: "2026-08-01", body: "See [[Blocking and Stage Areas]].", in: made.course)
        try write(courseLevelPage: "Blocking and Stage Areas", publishForSection1: "false",
                  dated: "2026-08-02", body: "Upstage.", in: made.course)

        _ = await made.runner.run(call: call(
            "publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Stage Directions"]
        ))

        XCTAssertTrue(
            text(ofCourseLevelPage: "Blocking and Stage Areas", in: made.course)
                .contains("createdSection1: 2026-08-02"),
            "An ordinary page dated a page it links to"
        )
    }

    /// The two ways of saying the same thing agree.
    ///
    /// This is the bug that started it: "Publish tomorrow's class" worked the
    /// dates out and "Publish Unit 2, Day 3" — naming the very same page —
    /// passed an empty list, so the same teacher got two different results
    /// depending on which sentence they used.
    @MainActor
    func testNamingTheClassAndNamingItsDayGiveTheSameDates() async throws {
        for byName in [true, false] {
            let made = try makeRunner()
            defer { try? FileManager.default.removeItem(at: made.root) }

            try write(page: "Unit 2, Day 3", publish: "false", date: "2026-10-06",
                      body: "See [[Blocking and Stage Areas]].", in: made.course)
            try write(courseLevelPage: "Blocking and Stage Areas", publishForSection1: "false",
                      dated: "2026-08-01", body: "Upstage.", in: made.course)

            if byName {
                _ = await made.runner.run(call: call(
                    "publish_pages",
                    arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 2, Day 3"]
                ))
            } else {
                _ = await made.runner.run(call: call(
                    "publish_class_on",
                    arguments: ["course": "ICS3U", "section": 1, "date": "2026-10-06"]
                ))
            }

            XCTAssertTrue(
                text(ofCourseLevelPage: "Blocking and Stage Areas", in: made.course)
                    .contains("createdSection1: 2026-10-06"),
                "byName=\(byName) did not date the page the class brought"
            )
        }
    }

    // MARK: - What an undo SAYS

    /// Reported from a real course: "Undid unpublished 2 pages in ADA1O
    /// Section 1."
    ///
    /// Three faults in one sentence. It was ungrammatical — a past-tense
    /// clause pushed into a slot that wanted a noun. It counted FILES, so
    /// hiding one class read as two pages, because the section's landing page
    /// is repointed in the same change. And it named neither the page the
    /// teacher asked about nor the fact that they had asked for the undo.
    @MainActor
    func testTheUndoReadsAsASentenceAndNamesThePage() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 4, Day 23", publish: "true", body: "The last class.", in: made.course)

        _ = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 4, Day 23"]
        ))
        let undone: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))

        XCTAssertEqual(undone.summary, AssistWording.undid("unpublished Unit 4, Day 23"))
        XCTAssertTrue(undone.summary.contains("Unit 4, Day 23"),
                      "The teacher asked about a class, not about a number of files")
        XCTAssertFalse(undone.summary.contains("Undid unpublished"),
                       "Ungrammatical: \(undone.summary)")
        XCTAssertFalse(undone.summary.contains("2 pages"),
                       "The landing page following along is bookkeeping, not what was asked for")
    }

    /// Every kind of change reads as a sentence, not only the reported one.
    ///
    /// "Undo that" applies to whatever was done last, so each producer of an
    /// undoable change has to supply a clause that survives being dropped into
    /// one. A clause that only reads well for publishing is a bug waiting for
    /// whichever teacher uses the other tool first.
    @MainActor
    func testEveryKindOfChangeUndoesIntoAGrammaticalSentence() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "false", body: "Two.", in: made.course)

        _ = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        let one: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))
        XCTAssertEqual(one.summary, AssistWording.undid("published Unit 1, Day 1"))

        _ = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1,
                                         "pages": "Unit 1, Day 1; Unit 1, Day 2"]
        ))
        let two: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))
        XCTAssertEqual(two.summary, AssistWording.undid("published Unit 1, Day 1 and Unit 1, Day 2"))

        // Whatever the shape, it is one sentence about a person doing a thing.
        for summary in [one.summary, two.summary] {
            XCTAssertTrue(summary.hasPrefix("Earlier, you "), summary)
            XCTAssertTrue(summary.hasSuffix("."), summary)
        }
    }

    /// The failure that read as a success.
    ///
    /// When every file has been edited since, NOTHING goes back — and the old
    /// code fell through to the same "Undid …" sentence it used when the undo
    /// had worked. A teacher was told their change had been taken back while
    /// not one file had moved.
    @MainActor
    func testAnUndoThatCouldNotPutAnythingBackSaysSoRatherThanClaimingSuccess() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        _ = await made.runner.run(call: call(
            "publish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))

        // The teacher writes the lesson, in Obsidian, before changing their
        // mind about publishing it.
        let pageURL: URL = ClassPages.folderURL(forSection: 1, in: made.course)
            .appendingPathComponent("Unit 1, Day 1.md")
        let indexURL: URL = made.course.directoryURL
            .appendingPathComponent("section1").appendingPathComponent("index.md")
        for url in [pageURL, indexURL] where FileManager.default.fileExists(atPath: url.path) {
            let now: String = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try (now + "\n\nWritten since.\n").write(to: url, atomically: true, encoding: .utf8)
        }

        let outcome: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))

        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: true"),
                      "Nothing should have gone back")
        XCTAssertFalse(outcome.summary.hasPrefix("Earlier, you published Unit 1, Day 1. Then"),
                       "Reported success while changing nothing: \(outcome.summary)")
        XCTAssertTrue(outcome.summary.contains("I have not changed anything"), outcome.summary)
    }

    // MARK: - What an undo DOES to the preview

    /// Reported from a real course: the undo made the file edits and left the
    /// preview serving the state the teacher had just asked to leave.
    ///
    /// The order is the assertion, not the presence of the events. Stop,
    /// write, start — and the stop must FINISH before the write, because a
    /// preview left serving while the pages beneath it are rewritten is
    /// serving a half-changed site.
    @MainActor
    func testUndoingStopsThePreviewWaitsWritesAndStartsItAgain() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        defer { FakePreview.shared.forget() }

        try write(page: "Unit 1, Day 1", publish: "true", body: "One.", in: made.course)

        _ = await made.runner.run(call: call(
            "unpublish_pages", arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))

        FakePreview.shared.register(
            folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1
        )
        FakePreview.shared.watch(pageAt: ClassPages.folderURL(forSection: 1, in: made.course)
            .appendingPathComponent("Unit 1, Day 1.md"))

        _ = await made.runner.run(call: call("undo_last_change"))

        XCTAssertEqual(
            FakePreview.shared.events,
            ["stop-begins", "stop-ends", "write", "start"],
            "The undo must stop the preview, wait for it, then write, then start it again"
        )
    }

    /// And it does NOT rebuild for a change that never touched the preview.
    ///
    /// A created class page arrives unpublished, so making it changed nothing
    /// the preview shows and taking it away changes nothing either. A blanket
    /// rebuild would make "undo that" the slowest thing in the window for the
    /// one change needing it least.
    @MainActor
    func testUndoingSomethingThePreviewNeverShowedDoesNotRebuildIt() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        defer { FakePreview.shared.forget() }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "One.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))
        _ = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))

        FakePreview.shared.register(
            folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1
        )
        _ = await made.runner.run(call: call("undo_last_change"))

        XCTAssertEqual(FakePreview.shared.events, [],
                       "Nothing the preview shows changed, so nothing should have been rebuilt")
    }

    // MARK: - Taking back a page that was created

    /// "Undo that" after adding a class page used to answer that the
    /// conversation had changed nothing — while the page sat in the teacher's
    /// folder. The undo list held before-and-after copies, and a created page
    /// has no "before", so nothing was recorded at all.
    @MainActor
    func testUndoTakesAwayAClassPageItCreated() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "One.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))

        let added: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(added.detail.contains("takes the page away again"),
                      "The teacher has to be told the way out: \(added.detail)")

        let created: [URL] = try classPageURLs(in: made.course).filter { url in
            return url.lastPathComponent != "Unit 1, Day 1.md"
                && url.lastPathComponent.lowercased() != "index.md"
        }
        XCTAssertEqual(created.count, 1, "One page should have been created")

        let undone: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))

        XCTAssertTrue(undone.summary.hasPrefix("Earlier, you added the class page "), undone.summary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: created[0].path),
                       "The page it created is still there after an undo")
    }

    /// And it leaves the page alone once the teacher has written in it — the
    /// same rule that protects an edited page from an undo of a publish.
    @MainActor
    func testUndoLeavesACreatedPageAloneOnceTheTeacherHasWrittenInIt() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "One.", in: made.course)
        _ = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1, "dates": "2026-09-08; 2026-09-10"]
        ))
        _ = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))

        let created: [URL] = try classPageURLs(in: made.course).filter { url in
            return url.lastPathComponent != "Unit 1, Day 1.md"
                && url.lastPathComponent.lowercased() != "index.md"
        }
        XCTAssertEqual(created.count, 1)
        let lesson: String = (try? String(contentsOf: created[0], encoding: .utf8)) ?? ""
        try (lesson + "\n\nWhat we did today.\n").write(
            to: created[0], atomically: true, encoding: .utf8
        )

        let undone: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: created[0].path),
                      "An undo threw away work the teacher had written")
        XCTAssertTrue(undone.summary.contains("I have not changed anything"), undone.summary)
    }

    /// Every class page file in a section, for the two tests above.
    @MainActor
    private func classPageURLs(in course: Course) throws -> [URL] {
        let folder: URL = ClassPages.folderURL(forSection: 1, in: course)
        let all: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        var pages: [URL] = []
        for url in all where url.pathExtension.lowercased() == "md" {
            pages.append(url)
        }
        return pages
    }

    // MARK: - Backing up, once per conversation

    /// One conversation, one backup — however many commands it runs.
    ///
    /// A vault full of images makes a slow, fat zip, and a chat with six
    /// commands in it used to make six near-identical ones. The first write
    /// saves the copy; the undo history covers everything after it.
    @MainActor
    func testAConversationWithThreeWritesBacksUpExactlyOnce() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let coursesDirectoryURL: URL = made.root.appendingPathComponent("courses")

        try write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        try write(page: "Unit 1, Day 2", publish: "false", body: "Two.", in: made.course)

        _ = await made.runner.run(call: call(
            "publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        _ = await made.runner.run(call: call(
            "publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 2"]
        ))
        let third: AssistToolOutcome = await made.runner.run(call: call(
            "unpublish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))

        // All three really wrote.
        XCTAssertTrue(text(ofPage: "Unit 1, Day 1", in: made.course).contains("publish: false"))
        XCTAssertTrue(text(ofPage: "Unit 1, Day 2", in: made.course).contains("publish: true"))
        XCTAssertTrue(third.detail.contains("backed up"),
                      "Every write still tells the teacher there is a way back")

        let backups: [BackupItem] = WorkspaceModel.findBackupItems(in: coursesDirectoryURL)
        XCTAssertEqual(backups.count, 1, "Three writes in one chat make ONE backup")
        XCTAssertEqual(backups[0].maker, .assistant(sectionNumber: 1),
                       "And it says who made it, and what it was for")

        // What the assistant's window reads to offer a way back to where the
        // conversation started.
        XCTAssertTrue(made.runner.hasConversationBackup)
        // Compared by name: the temporary folder is reached through a symlink,
        // so the two URLs spell the same file differently.
        XCTAssertEqual(made.runner.conversationBackupURL?.lastPathComponent,
                       backups[0].fileURL.lastPathComponent)
    }

    /// A conversation that only reads makes no backup at all — there is
    /// nothing to go back from.
    @MainActor
    func testAReadOnlyConversationMakesNoBackup() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let coursesDirectoryURL: URL = made.root.appendingPathComponent("courses")

        try write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)

        _ = await made.runner.run(call: call(
            "list_pages", arguments: ["course": "ICS3U", "section": 1]
        ))
        _ = await made.runner.run(call: call(
            "read_page", arguments: ["course": "ICS3U", "section": 1, "page": "Unit 1, Day 1"]
        ))
        _ = await made.runner.run(call: call(
            "check_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        _ = await made.runner.run(call: call(
            "plan_publish_pages",
            arguments: ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))

        XCTAssertEqual(
            WorkspaceModel.findBackupItems(in: coursesDirectoryURL).count, 0,
            "Reading — and planning, which changes nothing — copies nothing"
        )
        XCTAssertFalse(made.runner.hasConversationBackup)
        XCTAssertNil(made.runner.conversationBackupURL)
    }

    /// The gate is the tool's own answer, not a list kept beside it, and the
    /// explanation is the sentence the teacher reads before pressing anything.
    @MainActor
    func testDeployingAsksForAButtonAndSaysWhyInPlainWords() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let definition: AssistToolDefinition = try XCTUnwrap(made.runner.definition(named: "deploy_section"))
        XCTAssertTrue(definition.needsApproval)

        let explanation: String = made.runner.explain(call: call(
            "deploy_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        // The fact and the advice, and nothing that restates the request:
        // the act is named by the "Shall I deploy?" the agent says next, and
        // the section is on the window's own title bar.
        XCTAssertEqual(explanation, AssistWording.deployApproval)
        // No tool name, no machinery — this sentence is read by a teacher.
        XCTAssertFalse(explanation.contains("deploy_section"), explanation)

        // Approved, it runs — through the app's own script runner, stubbed here
        // so a unit test never starts Docker.
        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "deploy_section", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertEqual(made.siteWork.deploys, 1)
    }

    /// A deploy set for later goes through the app's own launchd machinery, and
    /// the plan names the classes it would ship WITHOUT — which is the whole
    /// value of planning it: a deploy that runs perfectly at half six and puts
    /// up a site missing tomorrow's class is the failure worth catching while
    /// somebody is awake.
    @MainActor
    func testPlanningAndSettingADeployForLater() async throws {
        let made = try makeRunner(hasDeployedBefore: true)
        defer {
            try? FileManager.default.removeItem(at: made.root)
            ScheduledDeploy.launchAgentsDirectoryOverride = nil
        }
        ScheduledDeploy.launchAgentsDirectoryOverride = made.root.appendingPathComponent("LaunchAgents")

        try write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)

        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_scheduled_deploy",
            arguments: ["course": "ICS3U", "section": 1,
                        "when": "2030-09-09 06:30", "classes": "Unit 1, Day 1"]
        ))
        XCTAssertTrue(planned.shouldContinue, "A plan is a read.")
        XCTAssertTrue(planned.detail.contains("NOT published, so the deploy would ship without it."))
        XCTAssertTrue(planned.detail.contains("awake"))
        XCTAssertTrue(planned.detail.contains("Nothing has been changed."))

        // Nothing is set by planning it.
        XCTAssertNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1))

        let set: AssistToolOutcome = await made.runner.run(call: call(
            "schedule_deploy",
            arguments: ["course": "ICS3U", "section": 1, "when": "2030-09-09 06:30"]
        ))
        XCTAssertFalse(set.shouldContinue)
        XCTAssertTrue(set.summary.contains("Scheduled:"))
        XCTAssertNotNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1))

        let cancelled: AssistToolOutcome = await made.runner.run(call: call(
            "cancel_scheduled_deploy", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(cancelled.summary.contains("Cancelled"))
        XCTAssertNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1))
    }

    /// Everything a scheduled deploy would ASK at half six is asked now
    /// instead. A section nobody has deployed yet would sit at a prompt with
    /// nobody there, so it is refused before anything is written.
    @MainActor
    func testADeployThatWouldAskAQuestionAtNightIsRefusedNow() async throws {
        let made = try makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
            ScheduledDeploy.launchAgentsDirectoryOverride = nil
        }
        ScheduledDeploy.launchAgentsDirectoryOverride = made.root.appendingPathComponent("LaunchAgents")

        let refused: AssistToolOutcome = await made.runner.run(call: call(
            "schedule_deploy",
            arguments: ["course": "ICS3U", "section": 1, "when": "2030-09-09 06:30"]
        ))
        XCTAssertTrue(refused.summary.contains("Nothing was scheduled."))
        XCTAssertTrue(refused.summary.contains("never been deployed"))
        XCTAssertNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1))

        // Cancelling when nothing is set is safe, and says so.
        let cancelled: AssistToolOutcome = await made.runner.run(call: call(
            "cancel_scheduled_deploy", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(cancelled.summary.contains("no deploy scheduled"))

        // A time nobody could read is a sentence, not a schema error.
        let unreadable: AssistToolOutcome = await made.runner.run(call: call(
            "schedule_deploy",
            arguments: ["course": "ICS3U", "section": 1, "when": "half six tomorrow"]
        ))
        XCTAssertTrue(unreadable.summary.contains("isn't a time I can read"))
    }

    /// A course the teacher does not have is a sentence, not a stack trace.
    @MainActor
    func testAnUnknownCourseIsRefusedInWords() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "check_section", arguments: ["course": "MPM2D", "section": 1]
        ))
        XCTAssertTrue(outcome.detail.contains("no course called “MPM2D”"))

        let unknownTool: AssistToolOutcome = await made.runner.run(call: call("set_publish"))
        XCTAssertTrue(unknownTool.detail.contains("no tool called"))
    }

    // MARK: - Fixtures
    //
    // The world these tests run in is built by `AssistFixture`, shared with
    // `AssistScenarioTests` so that a case written once means one thing.

    @MainActor
    private func makeRunner(hasDeployedBefore: Bool = false,
                            registeringPreview: Bool = false) throws
        -> (root: URL, course: Course, runner: AssistToolRunner, siteWork: StubSiteWork) {
        return try AssistFixture.makeRunner(
            hasDeployedBefore: hasDeployedBefore, registeringPreview: registeringPreview
        )
    }

    @MainActor
    private func makeAgent(tools: AssistToolRunner) -> AssistAgent {
        return AssistFixture.makeAgent(tools: tools)
    }

    private func call(_ name: String, arguments: [String: Any] = [:]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(
                name: name, arguments: String(decoding: encoded, as: UTF8.self)
            )
        )
    }

    @MainActor
    private func write(page title: String,
                       publish: String,
                       date: String = "2026-09-08",
                       body: String,
                       in course: Course) throws {
        try AssistFixture.write(page: title, publish: publish, date: date, body: body, in: course)
    }

    @MainActor
    private func pageURL(of title: String, in course: Course) -> URL {
        return AssistFixture.pageURL(of: title, in: course)
    }

    /// A section's landing page, shaped like the real ones: a class
    /// transclusion under a heading, and two that are NOT classes.
    @MainActor
    private func writeSectionIndex(pointingAt classTitle: String, in course: Course) throws {
        let text: String = """
        ---
        title: Section 1
        created: 2026-08-01T09:00:00.000-0400
        publish: true
        ---
        # Most Recent Class
        ![[\(classTitle)]]

        ![[Help Sessions]]
        ![[Key Links]]
        """
        try text.write(
            to: SectionIndexPointer.indexURL(forSection: 1, in: course),
            atomically: true, encoding: .utf8
        )
    }

    @MainActor
    private func sectionIndexText(in course: Course) throws -> String {
        return try String(
            contentsOf: SectionIndexPointer.indexURL(forSection: 1, in: course), encoding: .utf8
        )
    }

    /// A page in the section's own folder rather than in its classes folder —
    /// which is where a real course keeps `Key Links.md`. Section-local, so it
    /// carries the plain `publish:` key.
    @MainActor
    private func write(sectionPage title: String,
                       publish: String,
                       body: String,
                       in course: Course) throws {
        let text: String = """
        ---
        title: \(title)
        publish: \(publish)
        ---

        \(body)
        """
        try text.write(
            to: course.sectionDirectoryURL(forSection: 1).appendingPathComponent(title + ".md"),
            atomically: true, encoding: .utf8
        )
    }

    @MainActor
    private func write(courseLevelPage title: String,
                       inFolder folder: String = "Concepts",
                       publishForSection1: String,
                       dated: String = "2026-09-08",
                       body: String,
                       in course: Course) throws {
        let text: String = """
        ---
        title: \(title)
        publishForSection1: \(publishForSection1)
        createdSection1: \(dated)T07:00:00.000-0400
        ---

        \(body)
        """
        let folderURL: URL = course.directoryURL.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try text.write(
            to: folderURL.appendingPathComponent(title + ".md"),
            atomically: true, encoding: .utf8
        )
    }

    /// A folder's landing page — `index.md` inside a folder, which is what
    /// every folder in a real course has and what the fixtures could not make
    /// until the naming bug was reported.
    @MainActor
    private func write(folderIndex folder: String,
                       titled title: String?,
                       publishForSection1: String,
                       body: String,
                       in course: Course) throws {
        var frontmatter: String = "---\n"
        if let title {
            frontmatter += "title: \(title)\n"
        }
        frontmatter += "publishForSection1: \(publishForSection1)\n"
        frontmatter += "createdSection1: 2026-09-08T07:00:00.000-0400\n---\n\n"

        let folderURL: URL = course.directoryURL.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try (frontmatter + body).write(
            to: folderURL.appendingPathComponent("index.md"),
            atomically: true, encoding: .utf8
        )
    }

    @MainActor
    private func text(ofPage title: String, in course: Course) -> String {
        let url: URL = ClassPages.folderURL(forSection: 1, in: course)
            .appendingPathComponent(title + ".md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @MainActor
    private func text(ofCourseLevelPage title: String,
                      inFolder folder: String = "Concepts",
                      in course: Course) -> String {
        let url: URL = course.directoryURL.appendingPathComponent(folder)
            .appendingPathComponent(title + ".md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
