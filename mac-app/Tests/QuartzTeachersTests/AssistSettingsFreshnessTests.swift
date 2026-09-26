import XCTest
@testable import QuartzTeachers

/// The assistant acts on a course's settings as they are SAVED NOW, not as
/// they were when its window opened or the outside-assistant server started
/// (GitHub #322).
///
/// Russell set ICS3U to deploy to a folder, then asked the assistant to
/// deploy it at 3:54 PM, and was refused as "never been deployed … what to
/// call the website": the assistant's copy of the settings still said
/// Netlify. The same stale copy put "to Netlify" on the approval card, and
/// sent a headless outside-assistant deploy to the OLD destination with a
/// success message. Every test here changes the file on disk AFTER the runner
/// was made — the way Course Settings in another window does — and then calls.
///
/// The contract cases (`shared-rules.json` → `assistantReadsSettingsAtTheCall`)
/// are run by `SharedRulesContractTests`; these are the mac's own, including
/// the two things only the mac can get wrong: a window's unsaved edits, and
/// the folder-level work `reloadCourses()` does.
@MainActor
final class AssistSettingsFreshnessTests: XCTestCase {

    // MARK: - Types

    /// Site work that records where each deploy was handed.
    final class RecordingSiteWork: AssistSiteWork {

        // MARK: - Stored properties

        private(set) var destinationTypesSeen: [[String]] = []

        // MARK: - Functions

        func rebuildPreview(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {
            return AssistSiteWorkResult(succeeded: true, message: "rebuilt")
        }

        func deploy(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {
            var types: [String] = []
            for destination in course.configuration.allDeployDestinations {
                types.append(destination.type)
            }
            destinationTypesSeen.append(types)
            return AssistSiteWorkResult(
                succeeded: true,
                message: AssistWording.deployed(course: course.code, section: String(sectionNumber))
            )
        }
    }

    /// A working folder, a model no window shows, and a runner over it.
    struct World {
        let root: URL
        let workspace: WorkspaceModel
        let runner: AssistToolRunner
        let siteWork: RecordingSiteWork
    }

    // MARK: - Stored properties

    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var trailFolderURL: URL = FileManager.default.temporaryDirectory
    private var roots: [URL] = []

    // MARK: - Functions

    override func setUpWithError() throws {
        trailFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("freshness-trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: trailFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        ScheduledDeploy.launchAgentsDirectoryOverride = nil
        ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        SectionWindowControllers.shared.forgetAll()
        try? FileManager.default.removeItem(at: trailFolderURL)
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// ICS3U on disk (no deploy target, so Netlify), a model of the folder
    /// that no window shows, and a runner over it on the given surface.
    /// LaunchAgents and the one-shot scripts go into the scratch folder.
    private func makeWorld(hasDeployedBefore: Bool = false,
                           surface: AssistToolRunner.Surface = .local) throws -> World {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(
            hasDeployedBefore: hasDeployedBefore, surface: surface
        )
        roots.append(made.root)
        let agents: URL = made.root.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = agents
        ScheduledDeploy.scheduledScriptsDirectoryOverride = made.root.appendingPathComponent("scheduled")

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: made.root)
        let siteWork: RecordingSiteWork = RecordingSiteWork()
        let runner: AssistToolRunner = AssistToolRunner(
            workspace: workspace,
            siteWork: siteWork,
            today: { return CalendarDay(year: 2026, month: 9, day: 8)! },
            launchControl: SilentLaunchControl(),
            surface: surface
        )
        SectionWindowControllers.shared.forgetAll()
        return World(root: made.root, workspace: workspace, runner: runner, siteWork: siteWork)
    }

    private func configURL(_ code: String, in root: URL) -> URL {
        return root.appendingPathComponent("courses").appendingPathComponent(code)
            .appendingPathComponent("course_config.json")
    }

    /// Course Settings in ANOTHER window saves "deploy to this folder": a
    /// separate copy read from the file, changed, and written back.
    @discardableResult
    private func saveFolderDestinationElsewhere(in root: URL) throws -> URL {
        let folder: URL = root.appendingPathComponent("published-here")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let otherCopy: CourseConfiguration = try CourseConfiguration(contentsOf: configURL("ICS3U", in: root))
        otherCopy.deployTarget = "local_folder"
        otherCopy.deployFolderPath = folder.path
        try otherCopy.write(to: configURL("ICS3U", in: root))
        return folder
    }

    /// Another program saves these keys into a course's settings file.
    private func saveElsewhere(_ changes: [String: Any], to code: String, in root: URL) throws {
        let url: URL = configURL(code, in: root)
        var values: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        for (key, value) in changes {
            values[key] = value
        }
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted])
            .write(to: url, options: [.atomic])
    }

    private func call(_ name: String, _ arguments: [String: Any]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString, type: "function",
            function: AssistToolCall.Function(name: name, arguments: String(decoding: encoded, as: UTF8.self))
        )
    }

    private let scheduling: [String: Any] = ["course": "ICS3U", "section": 1, "when": "2030-09-09 06:30"]

    private func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: false)
    }

    // MARK: - The report

    /// #322 as it happened: before the fix this was refused with "has never
    /// been deployed, so deploying it asks what to call the website".
    func testASettingsSaveAfterTheWindowOpenedIsSeenWhenScheduling() async throws {
        let world: World = try makeWorld()
        let folder: URL = try saveFolderDestinationElsewhere(in: world.root)

        let outcome: AssistToolOutcome = await world.runner.run(call: call("schedule_deploy", scheduling))

        XCTAssertTrue(outcome.summary.hasPrefix("Scheduled:"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains(folder.path), outcome.summary)
        let agents: [URL] = try FileManager.default.contentsOfDirectory(
            at: world.root.appendingPathComponent("LaunchAgents"), includingPropertiesForKeys: nil
        )
        XCTAssertEqual(agents.count, 1, "the scheduled deploy's plist should have been written")
    }

    func testTheApprovalCardNamesTheDestinationSavedNow() throws {
        let world: World = try makeWorld()
        let folder: URL = try saveFolderDestinationElsewhere(in: world.root)

        let card: String = world.runner.explain(call: call("schedule_deploy", scheduling))

        XCTAssertTrue(card.contains("to a folder on this computer at"), card)
        XCTAssertFalse(card.contains(folder.path), "the card names a folder by kind, not by path: \(card)")
        XCTAssertFalse(card.contains("Netlify"), card)
    }

    /// The fail-OPEN one: an outside assistant, no window, deploying a course
    /// that has since been moved to a folder.
    func testAnOutsideAssistantsDeployGoesWhereTheCourseDeploysNow() async throws {
        let world: World = try makeWorld(hasDeployedBefore: true, surface: .mcp)
        try saveFolderDestinationElsewhere(in: world.root)

        _ = await world.runner.run(call: call("deploy_section", ["course": "ICS3U", "section": 1]))

        XCTAssertEqual(world.siteWork.destinationTypesSeen, [["local_folder"]])
    }

    func testASectionAddedAfterOpeningIsFound() async throws {
        let world: World = try makeWorld()
        let courseURL: URL = world.root.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section2/All Classes"), withIntermediateDirectories: true
        )
        try saveElsewhere(["section_numbers": [1, 2], "num_sections": 2], to: "ICS3U", in: world.root)

        let outcome: AssistToolOutcome = await world.runner.run(
            call: call("check_section", ["course": "ICS3U", "section": 2])
        )

        XCTAssertTrue(outcome.summary.contains("ICS3U Section 2"), outcome.summary)
    }

    func testACourseCreatedAfterTheServerStartedIsListed() async throws {
        let world: World = try makeWorld(surface: .mcp)
        let secondURL: URL = world.root.appendingPathComponent("courses/SPH4U")
        try FileManager.default.createDirectory(
            at: secondURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        let second: [String: Any] = [
            "course_code": "SPH4U", "course_name": "Physics", "section_numbers": [1], "num_sections": 1,
        ]
        try JSONSerialization.data(withJSONObject: second)
            .write(to: secondURL.appendingPathComponent("course_config.json"))

        let outcome: AssistToolOutcome = await world.runner.run(call: call("list_courses", [:]))

        XCTAssertTrue(outcome.detail.contains("SPH4U"), outcome.detail)
        XCTAssertTrue(outcome.detail.contains("ICS3U"), outcome.detail)
    }

    // MARK: - What the reading must never do

    /// A window's model holds Course Settings' UNSAVED edits. Reading the
    /// file into it would throw them away, so the reading refuses a model a
    /// window shows.
    func testReadingAtTheCallNeverTouchesAWindowsCopy() async throws {
        let world: World = try makeWorld()
        WorkspaceModel.registerWindowModel(world.workspace)
        defer { WorkspaceModel.unregisterWindowModel(world.workspace) }
        var course: Course? = nil
        for candidate in world.workspace.courses where candidate.code == "ICS3U" {
            course = candidate
        }
        let unsaved: Course = try XCTUnwrap(course)
        unsaved.configuration.courseName = "An edit nobody has saved yet"

        _ = await world.runner.run(call: call("list_courses", [:]))

        var after: Course? = nil
        for candidate in world.workspace.courses where candidate.code == "ICS3U" {
            after = candidate
        }
        XCTAssertTrue(after === unsaved, "the window's course object was replaced")
        XCTAssertEqual(after?.configuration.courseName, "An edit nobody has saved yet")
    }

    /// Only the courses: none of the folder-level work `reloadCourses()`
    /// does. Launcher refreshing is switched off under test, so the witness
    /// is `workspaceProblem`, which `reloadCourses()` clears and a reading at
    /// the call leaves alone.
    func testReadingAtTheCallDoesNotReloadTheFolder() async throws {
        let world: World = try makeWorld()
        world.workspace.workspaceProblem = "left as it was"

        _ = await world.runner.run(call: call("list_courses", [:]))

        XCTAssertEqual(world.workspace.workspaceProblem, "left as it was")
    }

    /// Structural: the runner reads the course list in ONE place, and that
    /// place reads the disk first. A seventh way in, added later, cannot be a
    /// stale reader nobody noticed.
    func testTheRunnerReadsCoursesOnlyThroughTheFreshReading() throws {
        let productFolderURL: URL = ActivityTrailWiringTests.productSourceFolderURL()
        var runnerURL: URL? = nil
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: productFolderURL) {
            if fileURL.lastPathComponent == "AssistToolRunner.swift" {
                runnerURL = fileURL
            }
        }
        let source: String = try String(contentsOf: try XCTUnwrap(runnerURL), encoding: .utf8)
        var previousCodeLine: String = ""
        var reads: [String] = []
        for line in source.components(separatedBy: "\n") {
            let trimmedLine: String = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("//") || trimmedLine.isEmpty {
                continue
            }
            if trimmedLine.range(of: "workspace\\.courses\\b", options: .regularExpression) != nil {
                reads.append(previousCodeLine + " ⏎ " + trimmedLine)
            }
            previousCodeLine = trimmedLine
        }
        XCTAssertEqual(reads.count, 1, "AssistToolRunner reads workspace.courses outside coursesAsSavedNow: \(reads)")
        XCTAssertEqual(reads.first, "workspace.readCoursesAsSavedNow() ⏎ return workspace.courses")
    }

    // MARK: - The trail (the widened "scheduled deploy could not be set")

    func testARefusalAtTheActIsOnTheTrailWithItsDestination() async throws {
        let world: World = try makeWorld()

        let outcome: AssistToolOutcome = await world.runner.run(call: call("schedule_deploy", scheduling))

        XCTAssertTrue(outcome.summary.hasPrefix("Nothing was scheduled."), outcome.summary)
        let when: Date = try XCTUnwrap(AssistToolRunner.moment(named: "2030-09-09 06:30"))
        let expected: String = "ICS3U/1 · could not set a scheduled deploy for "
            + ScheduledDeploy.dayAndTimeText(when)
            + ": refused before anything was written, deploying to Netlify: "
            + "ICS3U Section 1 has never been deployed to Netlify, so deploying it there asks what to call the website."
        XCTAssertTrue(trailText().contains(expected), trailText())
    }

    func testAFolderDestinationIsNamedByKindNotByPath() async throws {
        let world: World = try makeWorld()
        let folder: URL = try saveFolderDestinationElsewhere(in: world.root)
        try FileManager.default.removeItem(at: folder)

        let outcome: AssistToolOutcome = await world.runner.run(call: call("schedule_deploy", scheduling))

        XCTAssertTrue(outcome.summary.hasPrefix("Nothing was scheduled."), outcome.summary)
        let trail: String = trailText()
        XCTAssertTrue(trail.contains("refused before anything was written, deploying to a folder: "), trail)
        XCTAssertFalse(trail.contains("published-here"), trail)
    }

    /// The card and the plan twin are advisory and repeat; only an attempt
    /// to schedule leaves the line.
    func testTheCardAndThePlanLeaveNoRefusalLine() async throws {
        let world: World = try makeWorld()

        _ = world.runner.explain(call: call("schedule_deploy", scheduling))
        _ = await world.runner.run(call: call("plan_scheduled_deploy", scheduling))

        XCTAssertFalse(trailText().contains("could not set a scheduled deploy"), trailText())
    }
}
