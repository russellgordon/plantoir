import XCTest
@testable import QuartzTeachers

/// The world an assistant test runs in: a course on disk, a workspace pointed
/// at it, a runner wired to a stub that never starts Docker.
///
/// Shared rather than copied, and for a reason worth stating. Two test files
/// now drive the same behaviour — the hand-written cases in
/// `AssistToolRunnerTests`, and `AssistScenarioTests`, which runs the cases in
/// `contracts/assist-cases.json` that the Windows suite also runs. If those two
/// built their course-on-disk differently, the same scenario would quietly
/// mean two different things, which is exactly the drift the contract exists to
/// stop. One fixture, one meaning.
enum AssistFixture {

    // MARK: - Types

    /// What `makeRunner` hands back. Named, because two test files now pass it
    /// around and a four-part tuple in a parameter list is unreadable.
    typealias Made = (root: URL, course: Course, runner: AssistToolRunner, siteWork: StubSiteWork)

    /// A clock a test can MOVE, so one conversation can be asked the same
    /// thing on two different days.
    ///
    /// The runner reads its day through a function rather than storing a date
    /// (issue #143: a window left open across midnight resolved "tomorrow"
    /// against the day it opened). A test that pins the day passes nothing and
    /// gets 2026-09-08, the day every assist test is written against; a test
    /// about the midnight crossing itself makes one of these, hands it in, and
    /// turns the page mid-test.
    final class TestClock {

        // MARK: - Stored properties

        /// The day this clock currently reads.
        var day: CalendarDay

        // MARK: - Initializer

        init(_ day: CalendarDay) {
            self.day = day
        }
    }




    @MainActor
    static func makeRunner(hasDeployedBefore: Bool = false,
                            registeringPreview: Bool = false,
                            clock: TestClock? = nil,
                            openMainWindow: (@MainActor () -> Void)? = nil) throws
        -> (root: URL, course: Course, runner: AssistToolRunner, siteWork: StubSiteWork) {
        let fileManager: FileManager = FileManager.default
        let root: URL = fileManager.temporaryDirectory
            .appendingPathComponent("assist-tools-\(UUID().uuidString)")
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("Concepts"), withIntermediateDirectories: true
        )
        // A working folder is recognised by its launchers; a stub is enough,
        // and nothing in these tests ever runs one.
        try "#!/bin/bash\n".write(
            to: root.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8
        )
        try "#!/bin/bash\n".write(
            to: root.appendingPathComponent("deploy.sh"), atomically: true, encoding: .utf8
        )
        if hasDeployedBefore {
            // The marker `deploy.py` leaves the first time a section goes out.
            // Without it, scheduling is refused — deploying a section for the
            // first time asks what to call the website.
            try fileManager.createDirectory(
                at: courseURL.appendingPathComponent(".netlify_sites"), withIntermediateDirectories: true
            )
            try "{}".write(
                to: courseURL.appendingPathComponent(".netlify_sites/section1.json"),
                atomically: true, encoding: .utf8
            )
        }

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

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        let course: Course = try XCTUnwrap(workspace.courses.first)

        let siteWork: StubSiteWork = StubSiteWork()
        // Pinned to 2026-09-08 unless a test hands in a clock of its own: a
        // test must not be a different test depending on when it runs.
        let reading: TestClock = clock ?? TestClock(CalendarDay(year: 2026, month: 9, day: 8)!)
        let runner: AssistToolRunner = AssistToolRunner(
            workspace: workspace,
            siteWork: siteWork,
            today: { return reading.day },
            launchControl: SilentLaunchControl(),
            openMainWindow: openMainWindow
        )

        SectionWindowControllers.shared.forgetAll()
        if registeringPreview {
            FakePreview.shared.register(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        }
        return (root, course, runner, siteWork)
    }

    /// An agent wired to a runner, with a client that is never reached: every
    /// message these tests send is a card phrasing, matched in code.
    @MainActor
    static func makeAgent(tools: AssistToolRunner) -> AssistAgent {
        return AssistAgent(
            courseCode: "ICS3U",
            sectionNumber: 1,
            client: AssistModelClient(baseURL: URL(string: "http://127.0.0.1:1")!),
            tools: tools,
            planMode: AssistPlanMode(tier: .small, settings: AppSettings(defaults: TestDefaults.make()))
        )
    }

    @MainActor
    static func write(page title: String,
                       publish: String,
                       date: String = "2026-09-08",
                       body: String,
                       in course: Course) throws {
        let text: String = """
        ---
        title: \(title)
        publish: \(publish)
        created: \(date)T07:00:00.000-0400
        ---

        \(body)
        """
        try text.write(
            to: ClassPages.folderURL(forSection: 1, in: course).appendingPathComponent(title + ".md"),
            atomically: true, encoding: .utf8
        )
    }

    @MainActor
    static func pageURL(of title: String, in course: Course) -> URL {
        return ClassPages.folderURL(forSection: 1, in: course).appendingPathComponent(title + ".md")
    }
}

/// Records what it was asked to do instead of starting Docker.
@MainActor
final class StubSiteWork: AssistSiteWork {

    // MARK: - Stored properties

    private(set) var previewRebuilds: Int = 0
    private(set) var deploys: Int = 0

    // MARK: - Functions

    // The REAL sentences, not a stub's own words. A fixture that answers
    // "Deployed." lets a scenario assert the contract's wording and pass
    // against something the product never says — which is how the first run of
    // the scenario suite failed, correctly.
    func rebuildPreview(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {
        previewRebuilds += 1
        return AssistSiteWorkResult(
            succeeded: true,
            message: AssistWording.rebuiltForACallerWithNoWindow(
                course: course.code, section: String(sectionNumber)
            )
        )
    }

    func deploy(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {
        deploys += 1
        return AssistSiteWorkResult(
            succeeded: true,
            message: AssistWording.deployed(course: course.code, section: String(sectionNumber))
        )
    }
}

/// Watches what would be asked of launchd without asking it.
struct SilentLaunchControl: LaunchControlRunning {
    func bootstrap(plistURL: URL) -> String? {
        return nil
    }

    func bootOut(label: String) {
    }
}
