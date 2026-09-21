import XCTest
@testable import QuartzTeachers

/// What a teacher — and a Claude or Codex session — actually meets on a
/// course kept for reference.
///
/// The refusals are `ReferenceRefusalTests`. This is the other half: the
/// acts that are WITHHELD rather than refused, the shelf the sidebar builds,
/// and what the two assistant surfaces are told.
@MainActor
final class ReferenceInterfaceTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = URL(fileURLWithPath: "/")
    var workspace: WorkspaceModel = WorkspaceModel()
    var live: Course = ReferenceInterfaceTests.placeholder()
    var reference: Course = ReferenceInterfaceTests.placeholder()

    static func placeholder() -> Course {
        return Course(
            code: "", directoryURL: URL(fileURLWithPath: "/"),
            configuration: CourseConfiguration(values: [:], lastSavedData: Data())
        )
    }

    // MARK: - Setting up

    func prepare(alsoReference extra: [(folder: String, code: String, year: Int?)] = []) throws {
        let fileManager: FileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent("reference-interface-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: root.appendingPathComponent("courses"), withIntermediateDirectories: true
        )
        for launcher in ["preview.sh", "deploy.sh"] {
            try "#!/bin/bash\n".write(
                to: root.appendingPathComponent(launcher), atomically: true, encoding: .utf8
            )
        }
        let agents: URL = root.appendingPathComponent("LaunchAgents")
        try fileManager.createDirectory(at: agents, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = agents
        ScheduledDeploy.scheduledScriptsDirectoryOverride = root.appendingPathComponent("scheduled")
        let previousTrail: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent("trail"))

        try write(folder: "ICS3U", code: "ICS3U", year: nil, keptForReference: false)
        try write(folder: "ICS3U-2025", code: "ICS3U", year: 2025, keptForReference: true)
        for one in extra {
            try write(folder: one.folder, code: one.code, year: one.year, keptForReference: true)
        }

        workspace = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        for candidate in workspace.courses {
            if candidate.code == "ICS3U" { live = candidate }
            if candidate.code == "ICS3U-2025" { reference = candidate }
        }

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

    private func write(folder: String, code: String, year: Int?, keptForReference: Bool) throws {
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent(folder)
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        try Data("# lesson\n".utf8).write(
            to: courseURL.appendingPathComponent("section1").appendingPathComponent("index.md")
        )
        var values: [String: Any] = [
            "course_code": code,
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
        ]
        if keptForReference {
            values["kept_for_reference"] = true
            if let year {
                values["reference_school_year"] = year
            }
        }
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
    }

    private var today: CalendarDay {
        return CalendarDay(year: 2026, month: 9, day: 20)!
    }

    // MARK: - The shelf

    func testTheTwoListsAreSeparate() throws {
        try prepare()
        XCTAssertEqual(workspace.teachingCourses.count, 1)
        XCTAssertEqual(workspace.teachingCourses.first?.code, "ICS3U")
        XCTAssertEqual(workspace.referenceCourses.count, 1)
        XCTAssertEqual(workspace.referenceCourses.first?.code, "ICS3U-2025")
    }

    func testTheYearGroupsAreNewestFirstWithOtherLastAndNothingEmpty() throws {
        try prepare(alsoReference: [
            (folder: "ICS3U-2024", code: "ICS3U", year: 2024),
            (folder: "ADA1O-REF", code: "ADA1O", year: nil),
        ])
        let groups: [WorkspaceModel.ReferenceYearGroup] = workspace.referenceYearGroups(on: today)
        var titles: [String] = []
        for group in groups {
            titles.append(group.title)
        }
        XCTAssertEqual(titles, ["2025–26", "2024–25", SchoolYear.otherGroupName])
        // Nothing is drawn for a year nobody has a course in.
        XCTAssertFalse(titles.contains("2023–24"))
    }

    func testTheGroupsFollowTheFilterField() throws {
        try prepare(alsoReference: [(folder: "ADA1O-REF", code: "ADA1O", year: nil)])
        workspace.filterText = "ADA"
        XCTAssertEqual(workspace.teachingCourses.count, 0)
        XCTAssertEqual(workspace.referenceCourses.count, 1)
        XCTAssertEqual(workspace.referenceYearGroups(on: today).count, 1)
    }

    /// The uniqueness rule is asked of EVERY reference course, not of the
    /// filtered list: a code is taken whether or not the sidebar happens to
    /// be filtered right now.
    func testTheShelfIgnoresTheFilterField() throws {
        try prepare()
        workspace.filterText = "nothing matches this"
        XCTAssertEqual(workspace.shelvedReferenceCourses(on: today).count, 1)
    }

    // MARK: - Withheld, not merely refused

    /// The one the review found: a repair CREATES files inside the course,
    /// and the folders are deliberately unlocked so the preview works — so
    /// the write would have succeeded.
    func testSiteHealthRepairsAreWithheld() throws {
        try prepare()
        let mediaURL: URL = reference.directoryURL.appendingPathComponent("Media")
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaURL.path))

        XCTAssertFalse(SiteHealthRepair.restoreMediaFolder(in: reference))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: mediaURL.path),
            "A repair on a frozen course must not create a folder inside it."
        )
        XCTAssertFalse(SiteHealthRepair.restoreSectionIndex(forSection: 1, in: reference))

        // And the control: the live course is repaired exactly as before.
        XCTAssertTrue(SiteHealthRepair.restoreMediaFolder(in: live))
    }

    func testAddingASectionIsWithheld() throws {
        try prepare()
        XCTAssertThrowsError(try SectionAdder.addSection(2, to: reference)) { error in
            XCTAssertEqual(
                (error as? ReferenceCourseIsFrozen)?.errorDescription,
                ReferenceWording.staysAsItIs(course: "ICS3U")
            )
        }
    }

    /// Renaming would rewrite `course_code` to match the folder — replacing
    /// the code a teacher reads with a suffixed one on every surface.
    func testRenamingIsWithheld() throws {
        try prepare()
        XCTAssertThrowsError(
            try CourseRenamer.rename(
                reference, to: "ICS3U-OLD",
                coursesDirectoryURL: root.appendingPathComponent("courses"),
                existingCodes: ["ICS3U"],
                runner: SilentLaunchControl()
            )
        )
        XCTAssertEqual(reference.configuration.courseCode, "ICS3U")
    }

    func testRenamingAFolderInsideOneIsWithheld() throws {
        try prepare()
        XCTAssertThrowsError(
            try SpecialFolderRenamer.rename(
                "Concepts", to: "Ideas", scope: .shared,
                courseDirectory: reference.directoryURL, sectionNumbers: [1]
            )
        )
    }

    // MARK: - What the two assistant surfaces are told

    /// Decision (d): the LOCAL assistant is told nothing about a reference
    /// course — and `list_courses` reaches the teacher through a phrasing
    /// matched in code, so this is teacher-facing as well as model-facing.
    func testTheLocalAssistantNeverListsAReferenceCourse() async throws {
        try prepare()
        let localRunner: AssistToolRunner = AssistToolRunner(
            workspace: workspace, siteWork: StubSiteWork(), launchControl: SilentLaunchControl()
        )
        let said: String = await listed(from: localRunner)
        XCTAssertTrue(said.contains("ICS3U —"), said)
        XCTAssertFalse(said.contains("ICS3U-2025"), said)
        XCTAssertFalse(said.contains("kept for reference"), said)
    }

    /// And the opposite over MCP, deliberately: reading one is the point.
    func testTheMCPSurfaceListsThemWithEverythingNeededToAddressOne() async throws {
        try prepare()
        let mcpRunner: AssistToolRunner = AssistToolRunner(
            workspace: workspace, siteWork: StubSiteWork(),
            launchControl: SilentLaunchControl(), surface: .mcp
        )
        let said: String = await listed(from: mcpRunner)
        XCTAssertTrue(said.contains("ICS3U-2025"), "the name `locate` accepts")
        XCTAssertTrue(said.contains("course code: ICS3U"), "the code a teacher reads")
        XCTAssertTrue(said.contains("kept for reference — never deployed"), said)
        XCTAssertTrue(said.contains("2025–26"), "the year, so a session can say 'last year's'")
    }

    func testTheSessionBriefingNamesThem() throws {
        try prepare()
        let mcpRunner: AssistToolRunner = AssistToolRunner(
            workspace: workspace, siteWork: StubSiteWork(),
            launchControl: SilentLaunchControl(), surface: .mcp
        )
        let instructions: String = try XCTUnwrap(AssistMCPServer.instructions(for: mcpRunner))
        XCTAssertTrue(instructions.contains("ICS3U-2025"))
        XCTAssertTrue(instructions.contains("read-only"))

        // A folder with none says nothing at all: a briefing that restates
        // the obvious is one that gets skimmed.
        let quiet: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        XCTAssertNil(AssistMCPServer.instructions(
            for: AssistToolRunner(workspace: quiet, surface: .mcp)
        ))
    }

    /// M6: a bare code is never guessed at.
    func testABareCodeWithNoLiveCourseRefusesAndNamesTheCandidates() async throws {
        try prepare(alsoReference: [(folder: "MCV4U-2025", code: "MCV4U", year: 2025)])
        let runner: AssistToolRunner = AssistToolRunner(
            workspace: workspace, siteWork: StubSiteWork(),
            launchControl: SilentLaunchControl(), surface: .mcp
        )
        // MCV4U is taught by nobody here; one reference course shows it.
        let outcome: AssistToolOutcome = await runner.run(call: call(
            "read_page", ["course": "MCV4U", "section": 1, "page": "Anything"]
        ))
        XCTAssertTrue(outcome.detail.contains("MCV4U-2025"), outcome.detail)
        XCTAssertFalse(
            outcome.detail.contains("There is no course called"),
            "Naming the candidates beats 'no such course' when one is sitting right there."
        )

        // And the ordinary case is untouched: a bare code with a live course
        // resolves to the live one, exactly as it always has.
        let live: AssistToolOutcome = await runner.run(call: call(
            "check_section", ["course": "ICS3U", "section": 1]
        ))
        XCTAssertFalse(live.detail.contains("kept for reference"), live.detail)
    }

    // MARK: - The two outside doors

    /// Decision (s): the doors are not offered ON a reference course; a LIVE
    /// course's session is told they exist.
    func testTheGreetingNamesTheReferenceCoursesWithTheSameCode() throws {
        try prepare(alsoReference: [(folder: "MCV4U-2025", code: "MCV4U", year: 2025)])
        let mentioned: [String] = ClaudeCodeLauncher.referenceCoursesToMention(
            for: live, among: workspace.courses, today: today
        )
        XCTAssertEqual(mentioned, ["ICS3U-2025 (2025–26)"], "Same code only.")

        let greeting: String = ClaudeCodeLauncher.greeting(
            courseCode: "ICS3U", courseName: "Computer Science", referenceCourses: mentioned
        )
        XCTAssertTrue(greeting.contains("ICS3U-2025 (2025–26)"))
        XCTAssertTrue(greeting.contains("never deployed"))
    }

    /// The greeting for an ordinary course is BYTE-IDENTICAL to what it has
    /// always been, so #205's golden tests did not need re-pinning.
    func testAnOrdinaryCoursesGreetingDidNotMove() throws {
        try prepare()
        XCTAssertEqual(
            ClaudeCodeLauncher.greeting(courseCode: "ICS3U", courseName: "Computer Science"),
            ClaudeCodeLauncher.greeting(
                courseCode: "ICS3U", courseName: "Computer Science", referenceCourses: []
            )
        )
        XCTAssertTrue(
            ClaudeCodeLauncher.referenceCoursesToMention(
                for: reference, among: workspace.courses, today: today
            ).isEmpty,
            "A session is never opened on a reference course, so it is never told about itself."
        )
    }

    // MARK: - The calm note

    func testTheNoteIsShownOncePerCourse() throws {
        LockedPagesNote.defaults = TestDefaults.make()
        defer { LockedPagesNote.defaults = UserDefaults.standard }
        XCTAssertFalse(LockedPagesNote.hasBeenShown(courseCode: "ICS3U-2025"))
        LockedPagesNote.remember(courseCode: "ICS3U-2025")
        XCTAssertTrue(LockedPagesNote.hasBeenShown(courseCode: "ICS3U-2025"))
        XCTAssertFalse(LockedPagesNote.hasBeenShown(courseCode: "ADA1O-REF"))
    }

    // MARK: - Helpers

    private func call(_ name: String, _ arguments: [String: Any]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString, type: "function",
            function: AssistToolCall.Function(
                name: name, arguments: String(data: encoded, encoding: .utf8) ?? "{}"
            )
        )
    }

    private func listed(from runner: AssistToolRunner) async -> String {
        let outcome: AssistToolOutcome = await runner.run(call: call("list_courses", [:]))
        return outcome.detail
    }
}
