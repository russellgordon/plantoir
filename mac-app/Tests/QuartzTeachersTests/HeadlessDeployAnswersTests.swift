import XCTest
@testable import QuartzTeachers

/// GitHub #378's cause, folded into its fix: a deploy or rebuild started for
/// a caller with no window — an assistant working from another app over MCP,
/// or the in-app assistant with no section window open — runs its launchers
/// with `--non-interactive`, so a question refuses with exit 3 instead of
/// waiting for ever on a terminal nobody reads, and the refusal reaches the
/// assistant's reply as a named sentence (`AssistWording.deployNeedsAnAnswer`,
/// `.previewBuildNeedsAnAnswer`). The window's own Deploy never passes the
/// flag: there a question becomes a dialog the teacher answers.
///
/// MF-6 of the #378 plan. The launchers are stand-ins in a throwaway working
/// folder that write down the words they were run with and exit as told, so
/// nothing is built or published.
///
/// Resets `CourseActivity`, `PreviewLeases` and `WorkLeaseRegistry` —
/// process-wide state — around every test; safe only because the scheme runs
/// test classes one at a time (`parallelizable = "NO"`).
@MainActor
final class HeadlessDeployAnswersTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = URL(fileURLWithPath: "/")
    var workspace: WorkspaceModel = WorkspaceModel()
    var course: Course = Course(
        code: "ICS3U", directoryURL: URL(fileURLWithPath: "/"),
        configuration: CourseConfiguration(values: [:], lastSavedData: Data())
    )
    var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Setting up

    override func setUp() async throws {
        CourseActivity.reset()
        PreviewLeases.reset()
        WorkLeaseRegistry.reset()
        ScriptRunner.refusesNewRuns = false

        let fileManager: FileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent("headless-answers-378-\(UUID().uuidString)")
        let coursesURL: URL = root.appendingPathComponent("courses")
        try fileManager.createDirectory(at: coursesURL, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = root.appendingPathComponent("LaunchAgents")
        ScheduledDeploy.scheduledScriptsDirectoryOverride = root.appendingPathComponent("scheduled")
        previousTrail = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent("trail"))

        let courseURL: URL = coursesURL.appendingPathComponent("ICS3U")
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))

        try stubLaunchers(buildExits: 0, deployExits: 3)

        workspace = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        var found: Course? = nil
        for candidate in workspace.courses where candidate.code == "ICS3U" {
            found = candidate
        }
        course = try XCTUnwrap(found)
        SectionWindowControllers.shared.forgetAll()
    }

    override func tearDown() async throws {
        CourseActivity.reset()
        PreviewLeases.reset()
        WorkLeaseRegistry.reset()
        ScheduledDeploy.launchAgentsDirectoryOverride = nil
        ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    /// Stand-in launchers: each writes the words it was run with to a file
    /// beside it, then exits with the code given.
    func stubLaunchers(buildExits: Int, deployExits: Int) throws {
        let build: String = "#!/bin/bash\necho \"$*\" >> \"\(root.path)/preview-words.txt\"\nexit \(buildExits)\n"
        let deploy: String = "#!/bin/bash\necho \"$*\" >> \"\(root.path)/deploy-words.txt\"\nexit \(deployExits)\n"
        try build.write(to: root.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        try deploy.write(to: root.appendingPathComponent("deploy.sh"), atomically: true, encoding: .utf8)
    }

    func wordsGiven(to launcher: String) -> String {
        let url: URL = root.appendingPathComponent(launcher + "-words.txt")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Tests

    /// The windowless deploy passes --non-interactive to BOTH legs, and a
    /// question at the destination reaches the reply as the named sentence —
    /// not `deployDidNotFinish`, which reads as something broken.
    func testAHeadlessDeployThatMeetsAQuestionSaysSo() async throws {
        let work: AssistToolchainWork = AssistToolchainWork(workspace: workspace)
        let result: AssistSiteWorkResult = await work.deploy(course: course, sectionNumber: 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(
            result.message.hasPrefix(AssistWording.deployNeedsAnAnswer(course: "ICS3U", section: "1")),
            result.message
        )
        XCTAssertTrue(wordsGiven(to: "deploy").contains("--non-interactive"), wordsGiven(to: "deploy"))
        if !wordsGiven(to: "preview").isEmpty {
            XCTAssertTrue(wordsGiven(to: "preview").contains("--build-only --non-interactive"), wordsGiven(to: "preview"))
        }
        XCTAssertTrue(
            ActivityTrail.store.activityText(includingPrompts: true).contains("stopped at a question nobody was there to answer"),
            ActivityTrail.store.activityText(includingPrompts: true)
        )
    }

    /// The build leg asking is told apart from the destination asking.
    func testAHeadlessDeployWhoseBuildMeetsAQuestionSaysSo() async throws {
        try stubLaunchers(buildExits: 3, deployExits: 0)
        let work: AssistToolchainWork = AssistToolchainWork(workspace: workspace)
        let result: AssistSiteWorkResult = await work.deploy(course: course, sectionNumber: 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, AssistWording.deployNeedsAnAnswer(course: "ICS3U", section: "1"))
        XCTAssertEqual(wordsGiven(to: "deploy"), "", "nothing may be sent when the build did not finish")
        XCTAssertTrue(wordsGiven(to: "preview").contains("--non-interactive"), wordsGiven(to: "preview"))
    }

    /// The headless rebuild passes it too, and says so.
    func testAHeadlessRebuildThatMeetsAQuestionSaysSo() async throws {
        try stubLaunchers(buildExits: 3, deployExits: 0)
        let work: AssistToolchainWork = AssistToolchainWork(workspace: workspace)
        let result: AssistSiteWorkResult = await work.rebuildPreview(course: course, sectionNumber: 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, AssistWording.previewBuildNeedsAnAnswer(course: "ICS3U", section: "1"))
        XCTAssertEqual(wordsGiven(to: "preview"), "ICS3U 1 --build-only --non-interactive\n")
    }

    /// The window's Deploy goes through the same runner WITHOUT the flag, and
    /// an exit 3 there (which it cannot really produce) is no answer-sentence.
    func testTheWindowsDeployNeverPassesTheFlag() async throws {
        let runner: MultiDestinationDeployRunner = MultiDestinationDeployRunner()
        await runner.run(
            course: course,
            sectionNumber: 1,
            destinations: course.configuration.allDeployDestinations,
            cloudflareAccountID: "",
            workingDirectory: root,
            needsBuild: true
        )
        XCTAssertFalse(wordsGiven(to: "deploy").contains("--non-interactive"), wordsGiven(to: "deploy"))
        XCTAssertFalse(wordsGiven(to: "preview").contains("--non-interactive"), wordsGiven(to: "preview"))
        let said: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
            course: "ICS3U", section: "1", destinationCount: 1, outcome: runner.outcome
        )
        XCTAssertEqual(said.message, AssistWording.deployDidNotFinish(course: "ICS3U", section: "1"))
    }

    /// Two destinations, one asking and one going out: both are said.
    func testAPartOfAMultiDestinationDeployThatAskedIsNamed() {
        let netlify: CourseConfiguration.DeployDestination = CourseConfiguration.DeployDestination(type: "netlify", path: "")
        let cloudflare: CourseConfiguration.DeployDestination =
            CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")
        let outcome: MultiDestinationDeployRunner.Outcome = MultiDestinationDeployRunner.Outcome(
            anySucceeded: true,
            failedDestinations: [cloudflare],
            succeededDestinations: [netlify],
            destinationsThatNeededAnAnswer: [cloudflare]
        )
        let said: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
            course: "ICS3U", section: "1", destinationCount: 2, outcome: outcome
        )
        XCTAssertFalse(said.succeeded)
        XCTAssertEqual(
            said.message,
            AssistWording.deployNeedsAnAnswerAt(
                course: "ICS3U", section: "1", destinations: DeployCommand.destinationDescription(for: cloudflare)
            ) + " " + AssistWording.deployWentOutTo(destinations: DeployCommand.destinationDescription(for: netlify))
        )
    }
}
