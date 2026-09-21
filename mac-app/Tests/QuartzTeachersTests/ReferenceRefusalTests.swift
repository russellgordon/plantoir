import XCTest
@testable import QuartzTeachers

/// A course kept for reference is NEVER deployed — every door the mac owns.
///
/// The fifteen doors and the chokepoint each is caught at are data:
/// `contracts/shared-rules.json` → `referenceCourses.refusal.doors`. This file
/// drives the Swift ones. The shared Python's doors are
/// `scripts/test_reference_course.py`, which starts the real launcher, and the
/// two structural checks in `verify.sh`.
///
/// **A missed door is a deploy that REPORTS SUCCESS**, which is the worst
/// direction this feature can fail in, so the refusals are deliberately
/// layered and each layer is tested on its own rather than through the one in
/// front of it.
@MainActor
final class ReferenceRefusalTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = URL(fileURLWithPath: "/")
    var workspace: WorkspaceModel = WorkspaceModel()
    var runner: AssistToolRunner = AssistToolRunner(workspace: WorkspaceModel())
    var siteWork: StubSiteWork = StubSiteWork()

    /// The course a teacher is teaching.
    var live: Course = Course(
        code: "ICS3U", directoryURL: URL(fileURLWithPath: "/"),
        configuration: CourseConfiguration(values: [:], lastSavedData: Data())
    )

    /// Last year's, kept for reference — a DIFFERENT folder, the same code.
    var reference: Course = Course(
        code: "ICS3U-2025", directoryURL: URL(fileURLWithPath: "/"),
        configuration: CourseConfiguration(values: [:], lastSavedData: Data())
    )

    // MARK: - Setting up

    /// A working folder holding ICS3U and ICS3U-2025, both with a section 1
    /// that has been deployed before — so nothing else refuses first and a
    /// green test is green for the right reason.
    func prepare() throws {
        let fileManager: FileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent("reference-refusal-\(UUID().uuidString)")
        let coursesURL: URL = root.appendingPathComponent("courses")
        try fileManager.createDirectory(at: coursesURL, withIntermediateDirectories: true)
        // Hermetic, and it is not a formality: `chooseWorkspace` reloads the
        // courses, which runs the reference upkeep, which ASKS FOR THE
        // AGENTS. Without this override that question reaches the teacher's
        // own ~/Library/LaunchAgents. Nothing here can match one — the
        // agents are filtered on their recorded working folder and this one
        // is a fresh temp dir — but a test that believes it is hermetic and
        // is not will be believed by the next person to add to it.
        let agentsDirectory: URL = root.appendingPathComponent("LaunchAgents")
        try fileManager.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = agentsDirectory
        ScheduledDeploy.scheduledScriptsDirectoryOverride = root.appendingPathComponent("scheduled")
        let previousTrail: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent("trail"))
        for launcher in ["preview.sh", "deploy.sh"] {
            try "#!/bin/bash\n".write(
                to: root.appendingPathComponent(launcher), atomically: true, encoding: .utf8
            )
        }

        try makeCourseFolder(named: "ICS3U", code: "ICS3U", keptForReference: false)
        try makeCourseFolder(named: "ICS3U-2025", code: "ICS3U", keptForReference: true)

        workspace = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        var foundLive: Course? = nil
        var foundReference: Course? = nil
        for candidate in workspace.courses {
            if candidate.code == "ICS3U" { foundLive = candidate }
            if candidate.code == "ICS3U-2025" { foundReference = candidate }
        }
        live = try XCTUnwrap(foundLive)
        reference = try XCTUnwrap(foundReference)
        XCTAssertTrue(reference.isKeptForReference)
        XCTAssertEqual(reference.displayCode, "ICS3U", "The code a teacher reads.")

        siteWork = StubSiteWork()
        runner = AssistToolRunner(
            workspace: workspace,
            siteWork: siteWork,
            today: { return CalendarDay(year: 2026, month: 9, day: 8)! },
            launchControl: SilentLaunchControl()
        )
        SectionWindowControllers.shared.forgetAll()

        let treeRoot: URL = root
        addTeardownBlock {
            MainActor.assumeIsolated {
                ScheduledDeploy.launchAgentsDirectoryOverride = nil
                ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
                ActivityTrail.store = previousTrail
                ReferenceLock.clearLock(at: treeRoot)
            }
            try? FileManager.default.removeItem(at: treeRoot)
        }
    }

    private func makeCourseFolder(named folderName: String, code: String, keptForReference: Bool) throws {
        let fileManager: FileManager = FileManager.default
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent(folderName)
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        // Deployed before, so `ScheduledDeploy.problem` has no other reason to
        // refuse — the reference check must be what fires.
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent(".netlify_sites"), withIntermediateDirectories: true
        )
        try "{}".write(
            to: courseURL.appendingPathComponent(".netlify_sites/section1.json"),
            atomically: true, encoding: .utf8
        )
        var configuration: [String: Any] = [
            "course_code": code,
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        if keptForReference {
            configuration["kept_for_reference"] = true
            configuration["reference_school_year"] = 2025
            configuration["deploy_target"] = "local_folder"
            configuration["deploy_folder_path"] = ""
        }
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
    }

    private func call(_ name: String, _ arguments: [String: Any]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString, type: "function",
            function: AssistToolCall.Function(
                name: name, arguments: String(data: encoded, encoding: .utf8) ?? "{}"
            )
        )
    }

    private var expectedRefusal: String {
        return AssistWording.deployRefusedForAReferenceCourse(course: "ICS3U")
    }

    // MARK: - The sentence

    /// One rule, one sentence — said by the app, by the shared Python and by
    /// both launchers. A teacher refused at the button and again at the
    /// Terminal must not read two explanations of one thing.
    func testTheSentenceIsTheContractsSentence() throws {
        let rules: [String: Any] = try ReferenceRefusalTests.rules()
        let refusal: [String: Any] = try XCTUnwrap(rules["refusal"] as? [String: Any])
        let template: String = try XCTUnwrap(refusal["sentence"] as? String)
        XCTAssertEqual(AssistWording.deployRefusedForAReferenceCourse(course: "{course}"), template)
    }

    func testTheContractStillNamesEveryDoor() throws {
        let rules: [String: Any] = try ReferenceRefusalTests.rules()
        let refusal: [String: Any] = try XCTUnwrap(rules["refusal"] as? [String: Any])
        let doors: [[String: Any]] = try XCTUnwrap(refusal["doors"] as? [[String: Any]])
        XCTAssertEqual(
            doors.count, 15,
            "Fifteen doors were enumerated from the code, twice, independently. A door dropped from "
            + "this list is a door nobody is looking at."
        )
        for door in doors {
            XCTAssertNotNil(door["door"] as? String)
            XCTAssertNotNil(door["chokepoint"] as? String, "\(door) names no chokepoint")
        }
    }

    // MARK: - The Swift doors

    /// Door 1 — the section window's Deploy button, through the same function
    /// the button and the assistant both press.
    func testTheDeployButtonRefuses() throws {
        try prepare()
        let refusal: AssistSiteWorkResult = SectionDetailView.refusalForAReferenceCourse(reference)
            ?? AssistSiteWorkResult(succeeded: true, message: "nothing refused")
        XCTAssertFalse(refusal.succeeded)
        XCTAssertEqual(refusal.message, expectedRefusal)
        XCTAssertTrue(refusal.isAboutTheDestination, "The window shows it as an alert.")
        XCTAssertNil(
            SectionDetailView.refusalForAReferenceCourse(live),
            "The course they are teaching deploys exactly as it always did."
        )
    }

    /// Doors 2, 3, 4 and 5 — every way `deploy_section` is reached.
    func testDeploySectionRefuses() async throws {
        try prepare()
        let outcome: AssistToolOutcome = await runner.run(
            call: call("deploy_section", ["course": "ICS3U-2025", "section": 1])
        )
        XCTAssertEqual(outcome.detail, expectedRefusal)
        XCTAssertEqual(siteWork.deploys, 0, "Nothing may reach the launcher.")
    }

    /// And the live course still deploys — the control, without which a
    /// refusal of everything would pass every test here.
    func testTheLiveCourseStillDeploys() async throws {
        try prepare()
        let outcome: AssistToolOutcome = await runner.run(
            call: call("deploy_section", ["course": "ICS3U", "section": 1])
        )
        XCTAssertEqual(siteWork.deploys, 1, outcome.detail)
    }

    /// Door 6 and 7 — `schedule_deploy`, and door 10, `plan_scheduled_deploy`,
    /// which describes a deploy that cannot happen.
    func testSchedulingRefusesAndSoDoesPlanningIt() async throws {
        try prepare()
        let scheduled: AssistToolOutcome = await runner.run(call: call(
            "schedule_deploy", ["course": "ICS3U-2025", "section": 1, "when": "2026-09-09 06:30"]
        ))
        XCTAssertTrue(scheduled.detail.contains("kept for reference"), scheduled.detail)

        let planned: AssistToolOutcome = await runner.run(call: call(
            "plan_scheduled_deploy", ["course": "ICS3U-2025", "section": 1, "when": "2026-09-09 06:30"]
        ))
        XCTAssertTrue(
            planned.detail.contains("kept for reference"),
            "A plan that describes a deploy which cannot happen teaches a session to try it: \(planned.detail)"
        )
    }

    /// Door 8 — the sidebar's Schedule Deploy… sheet, which asks
    /// `ScheduledDeploy.problem` directly.
    func testTheScheduleSheetRefusesWhateverTimeWasAsked() throws {
        try prepare()
        let inThePast: Date = Date(timeIntervalSince1970: 0)
        let problem: String? = ScheduledDeploy.problem(
            course: reference, sectionNumber: 1,
            when: inThePast, now: Date(), cloudflareAccountID: ""
        )
        XCTAssertEqual(
            problem, expectedRefusal,
            "Refused BEFORE 'that time has already passed' — telling the teacher to pick another "
            + "time sends them round a loop that ends in the same place."
        )
    }

    /// Door 3/5's backstop — the headless path an MCP client and a scheduled
    /// deploy take.
    func testTheHeadlessDeployPathRefuses() async throws {
        try prepare()
        let work: AssistToolchainWork = AssistToolchainWork(workspace: workspace)
        let result: AssistSiteWorkResult = await work.deploy(course: reference, sectionNumber: 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, expectedRefusal)
    }

    // MARK: - The write gate

    /// Every tool that writes is refused, and the three that are allowed are
    /// the three the contract names — asked of the tool's own `readOnly`
    /// flag, so a tool added later meets the gate without anybody remembering.
    func testTheWriteGateIsExactlyWhatTheContractSays() async throws {
        try prepare()
        let rules: [String: Any] = try ReferenceRefusalTests.rules()
        let refusal: [String: Any] = try XCTUnwrap(rules["refusal"] as? [String: Any])
        var allowed: Set<String> = []
        for entry in try XCTUnwrap(refusal["toolsStillAllowed"] as? [[String: Any]]) {
            let tool: String = try XCTUnwrap(entry["tool"] as? String)
            XCTAssertNotNil(entry["why"] as? String, "\(tool) is allowed for a reason; say it.")
            allowed.insert(tool)
        }
        XCTAssertEqual(
            allowed, AssistToolRunner.toolsAllowedOnAReferenceCourse,
            "The exemptions are contract DATA. An exemption that exists only in the Swift is a hole "
            + "nothing can see."
        )

        // Driven from each tool's OWN SCHEMA, never from a fixed dictionary.
        // The first version of this test passed `course` to every write tool,
        // including `undo_last_change`, which declares no parameters at all —
        // so it proved the gate against an argument no client ever sends.
        var toolsWithNoCourseArgument: [String] = []
        for tool in AssistToolRunner.mcpTools where !tool.readOnly {
            if tool.parameters["course"] == nil {
                toolsWithNoCourseArgument.append(tool.name)
            }
        }
        XCTAssertEqual(
            toolsWithNoCourseArgument, ["undo_last_change"],
            "A write tool with no `course` argument cannot be gated by its arguments. Exactly one "
            + "exists, and it is gated by the course the pending change belongs to. A new one has "
            + "to be given the same treatment deliberately — which is what this assertion asks for."
        )

        var refusedNames: [String] = []
        var ranNames: [String] = []
        for tool in AssistToolRunner.mcpTools where !tool.readOnly {
            // The one tool with no `course` is gated by the pending change's
            // course instead, and has its own test — it cannot be driven from
            // here, because a pending change on a reference course would have
            // to have been WRITTEN to one first, which is the thing that
            // cannot happen.
            if toolsWithNoCourseArgument.contains(tool.name) {
                continue
            }
            var arguments: [String: Any] = [:]
            if tool.parameters["course"] != nil {
                arguments["course"] = "ICS3U-2025"
            }
            if tool.parameters["section"] != nil {
                arguments["section"] = 1
            }
            let outcome: AssistToolOutcome = await runner.run(call: call(tool.name, arguments))
            // Two sentences, chosen by what was asked for: a deploy is told it
            // is never deployed, everything else that the course stays as it
            // is. Both are refusals at the same gate.
            if outcome.detail == ReferenceWording.staysAsItIs(course: "ICS3U")
                || outcome.detail == expectedRefusal {
                refusedNames.append(tool.name)
            } else {
                ranNames.append(tool.name)
            }
        }
        XCTAssertEqual(
            Set(ranNames), allowed,
            "Exactly the exempt tools get past the gate. Anything else here is a write reaching a "
            + "frozen course."
        )
        XCTAssertFalse(refusedNames.isEmpty)
    }

    /// GATE BY DIRECTION: the act that STOPS a deploy is never refused.
    ///
    /// A course marked by hand while an alarm was already set must still be
    /// able to have that alarm turned off from the app.
    func testCancellingAScheduledDeployIsNeverRefused() async throws {
        try prepare()
        let outcome: AssistToolOutcome = await runner.run(
            call: call("cancel_scheduled_deploy", ["course": "ICS3U-2025", "section": 1])
        )
        XCTAssertNotEqual(outcome.detail, ReferenceWording.staysAsItIs(course: "ICS3U"))
        XCTAssertFalse(outcome.detail.contains("kept for reference"), outcome.detail)
    }

    /// Reads work, which is the point of keeping the course at all.
    func testReadingAReferenceCourseWorks() async throws {
        try prepare()
        let outcome: AssistToolOutcome = await runner.run(
            call: call("check_section", ["course": "ICS3U-2025", "section": 1])
        )
        XCTAssertFalse(outcome.detail.contains("kept for reference"), outcome.detail)
    }

    /// `undo_last_change` names no course, so it is gated by the course the
    /// PENDING change belongs to — the real schema, not an injected argument.
    ///
    /// **Why this test can only go this far, said rather than left as a
    /// weakness.** To watch the gate REFUSE an undo, this conversation would
    /// have to have written to a reference course first — which is what every
    /// other guard in this file exists to prevent. So what is pinned is the
    /// shape: undo answers from the history rather than from an argument, and
    /// when the history is empty it says its own sentence rather than
    /// silently doing nothing. The assertion that no OTHER write tool may
    /// arrive without a `course` argument is in the gate test above, and that
    /// is what stops this becoming a hole later.
    func testUndoIsGatedByTheCourseItWouldTouch() async throws {
        try prepare()
        let nothing: AssistToolOutcome = await runner.run(call: call("undo_last_change", [:]))
        XCTAssertEqual(nothing.detail, AssistWording.nothingToUndo)
    }

    // MARK: - The two acts, backstopped

    /// `ScheduledDeploy.scheduleDeploy` is the function that WRITES the
    /// plist; `problem()` is only advice about it.
    func testWritingTheScheduleItselfRefuses() throws {
        try prepare()
        let problem: String? = ScheduledDeploy.scheduleDeploy(
            course: reference,
            sectionNumber: 1,
            when: Date().addingTimeInterval(3600),
            workspaceURL: root,
            cloudflareAccountID: "",
            runner: SilentLaunchControl()
        )
        XCTAssertEqual(problem, expectedRefusal)
    }

    /// `MultiDestinationDeployRunner.run` is the function that starts
    /// `deploy.sh`. It simply does not start.
    func testTheDeployRunnerItselfDoesNotStart() async throws {
        try prepare()
        let deployRunner: MultiDestinationDeployRunner = MultiDestinationDeployRunner()
        await deployRunner.run(
            course: reference,
            sectionNumber: 1,
            destinations: reference.configuration.allDeployDestinations,
            cloudflareAccountID: "",
            workingDirectory: root,
            needsBuild: false
        )
        XCTAssertTrue(deployRunner.legs.isEmpty, "Not one leg may be started.")
        XCTAssertFalse(deployRunner.isRunning)
    }

    // MARK: - The refusal does not depend on the lock

    /// An ENTIRELY UNLOCKED reference course is refused at every door just the
    /// same.
    ///
    /// This is the one that must never regress: if the two were coupled, a
    /// course restored from a backup, or one whose folder had been on a second
    /// Mac, would become deployable — and a deploy that reports success is the
    /// worst direction this can fail in.
    func testAnUnlockedReferenceCourseIsStillRefusedEverywhere() async throws {
        try prepare()
        ReferenceLock.unlock(courseDirectory: reference.directoryURL)
        let page: URL = reference.directoryURL
            .appendingPathComponent("course_config.json")
        XCTAssertFalse(ReferenceLock.isLocked(page))

        let deployed: AssistToolOutcome = await runner.run(
            call: call("deploy_section", ["course": "ICS3U-2025", "section": 1])
        )
        XCTAssertEqual(deployed.detail, expectedRefusal)
        XCTAssertEqual(siteWork.deploys, 0)

        XCTAssertEqual(
            ScheduledDeploy.problem(
                course: reference, sectionNumber: 1,
                when: Date().addingTimeInterval(3600), now: Date(), cloudflareAccountID: ""
            ),
            expectedRefusal
        )

        let work: AssistToolchainWork = AssistToolchainWork(workspace: workspace)
        let headless: AssistSiteWorkResult = await work.deploy(course: reference, sectionNumber: 1)
        XCTAssertFalse(headless.succeeded)

        XCTAssertNotNil(SectionDetailView.refusalForAReferenceCourse(reference))
    }

    // MARK: - A refusal that reaches the teacher rather than a log

    /// A deploy set to happen on its own runs with the app closed; without
    /// this the app shows the generic "did not finish" and the real reason
    /// stays in a file nobody opens.
    func testTheLaunchersRefusalBecomesTheSentenceTheTeacherReads() {
        // NAMED, never quoted. Russell edits these sentences, and a test that
        // types one out is a copy that keeps passing after the product's
        // words change.
        let output: String = "🔎 Checking whether your website builder is up to date…\n\n"
            + "❌ " + expectedRefusal + "\n"
        XCTAssertEqual(FailureExplainer.explanation(in: output), expectedRefusal)
    }

    // MARK: - Helpers

    private static func rules() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["referenceCourses"] as? [String: Any])
    }
}
