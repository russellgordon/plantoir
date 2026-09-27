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




    /// - Parameter alsoCourse: a SECOND course in the same working folder,
    ///   with sections 1 and 2. Added for the window-binding tests, which need
    ///   a course a window is not for; defaulted to none, so every existing
    ///   caller gets exactly the folder it always got.
    @MainActor
    static func makeRunner(hasDeployedBefore: Bool = false,
                            registeringPreview: Bool = false,
                            alsoCourse: String? = nil,
                            clock: TestClock? = nil,
                            openMainWindow: (@MainActor () -> Void)? = nil,
                            surface: AssistToolRunner.Surface = .local) throws
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

        if let secondCode = alsoCourse {
            let secondURL: URL = root.appendingPathComponent("courses")
                .appendingPathComponent(secondCode)
            try fileManager.createDirectory(
                at: secondURL.appendingPathComponent("section1/All Classes"),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: secondURL.appendingPathComponent("section2/All Classes"),
                withIntermediateDirectories: true
            )
            let second: [String: Any] = [
                "course_code": secondCode,
                "course_name": "Another course entirely",
                "section_numbers": [1, 2],
                "num_sections": 2,
                "per_section_folders": ["All Classes"],
                "per_section_files": [],
            ]
            try JSONSerialization.data(withJSONObject: second, options: [.prettyPrinted])
                .write(to: secondURL.appendingPathComponent("course_config.json"))
        }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        // Looked up BY CODE rather than taken as `.first`. A second course
        // whose code sorts before ICS3U would otherwise change what every
        // existing caller's `course` is, which is a failure in twenty tests
        // for a reason nobody would find.
        var found: Course? = nil
        for candidate in workspace.courses where candidate.code == "ICS3U" {
            found = candidate
        }
        let course: Course = try XCTUnwrap(found)

        let siteWork: StubSiteWork = StubSiteWork()
        // Pinned to 2026-09-08 unless a test hands in a clock of its own: a
        // test must not be a different test depending on when it runs.
        let reading: TestClock = clock ?? TestClock(CalendarDay(year: 2026, month: 9, day: 8)!)
        let runner: AssistToolRunner = AssistToolRunner(
            workspace: workspace,
            siteWork: siteWork,
            today: { return reading.day },
            launchControl: SilentLaunchControl(),
            openMainWindow: openMainWindow,
            surface: surface
        )

        SectionWindowControllers.shared.forgetAll()
        if registeringPreview {
            FakePreview.shared.register(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        }
        return (root, course, runner, siteWork)
    }

    /// An agent wired to a runner, with a client that is never reached: every
    /// message these tests send is a card phrasing, matched in code.
    ///
    /// `engineAt` points it at a real address instead — `StubEngine.baseURL`
    /// for a test about what the model answered. `asksBeforeChanging` is the
    /// plan-mode switch, and it defaults to what a teacher has: **on**. A test
    /// about what a tool DOES to the disk has to turn it off, or the write is
    /// held behind a plan and the assertion passes for the wrong reason.
    @MainActor
    static func makeAgent(tools: AssistToolRunner,
                          engineAt engineURL: URL? = nil,
                          asksBeforeChanging: Bool = true) -> AssistAgent {
        let settings: AppSettings = AppSettings(defaults: TestDefaults.make())
        settings.assistantAsksBeforeChanging = asksBeforeChanging
        return AssistAgent(
            courseCode: "ICS3U",
            sectionNumber: 1,
            client: AssistModelClient(baseURL: engineURL ?? URL(string: "http://127.0.0.1:1")!),
            tools: tools,
            planMode: AssistPlanMode(tier: .small, settings: settings)
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

    // MARK: - Fixtures shared by the plan-mode and card-argument walks (#150)

    /// Points scheduled-publish lookups at a throwaway folder for the length
    /// of one test.
    ///
    /// Without it `plistURL` resolves to the REAL ~/Library/LaunchAgents, and
    /// the fixture's course is ICS3U — a course a teacher plausibly has
    /// scheduled — so a test could read, boot out or delete their agent.
    @MainActor
    static func keepScheduledPublishingInside(_ root: URL, for testCase: XCTestCase) throws {
        let agentsDirectory: URL = root.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(
            at: agentsDirectory, withIntermediateDirectories: true
        )
        ScheduledDeploy.launchAgentsDirectoryOverride = agentsDirectory
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            agentsDirectory.deletingLastPathComponent().appendingPathComponent("scheduled")
        testCase.addTeardownBlock {
            MainActor.assumeIsolated {
                ScheduledDeploy.launchAgentsDirectoryOverride = nil
                ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
            }
        }
    }

    /// A Unit/Day section with enough in it that every plan tool has
    /// something real to work out, and every argument a card sends has
    /// something to change (#150).
    ///
    /// Units 1–5 in mixed publish states, a class on every day of the first
    /// week (weekend included), Unit 2, Day 3 linking to Day 4, a
    /// timetable of 53 dates from the pinned day onward, a site marker, and a
    /// curriculum folder with one expectation and one Concepts page to point
    /// at it. Richer than any one test needs on purpose: a walk over EVERY
    /// plan tool and EVERY card argument has to be run on one world, or a
    /// case that finds nothing to do passes for the wrong reason.
    @MainActor
    static func makeRichSection(for testCase: XCTestCase) throws -> Made {
        let made: Made = try makeRunner(hasDeployedBefore: true)
        try keepScheduledPublishingInside(made.root, for: testCase)

        let pages: [(title: String, publish: String, date: String, body: String)] = [
            ("Unit 1, Day 1", "true", "2026-09-08", "One."),
            ("Unit 1, Day 2", "false", "2026-09-09", "Two."),
            ("Unit 2, Day 3", "true", "2026-09-10", "See [[Unit 2, Day 4]]."),
            ("Unit 2, Day 4", "false", "2026-09-11", "Four."),
            ("Unit 3, Day 1", "false", "2026-09-14", "Three one."),
            ("Unit 3, Day 2", "false", "2026-09-15", "The body of three two."),
            ("Unit 3, Day 3", "false", "2026-09-16", "Three three."),
            ("Unit 3, Day 4", "false", "2026-09-17", "Three four."),
            ("Unit 3, Day 5", "false", "2026-09-18", "Three five."),
            ("Unit 4, Day 1", "false", "2026-09-21", "Four one."),
            ("Unit 4, Day 21", "true", "2026-09-22", "Four twenty-one."),
            ("Unit 5, Day 1", "false", "2026-09-23", "Five one."),
            // A class on the weekend too, so "publish saturday's class" and
            // "publish sunday's class" find one: the card walks say every
            // day's phrasing, and a day with no class is answered with a
            // refusal rather than a plan.
            ("Unit 5, Day 2", "false", "2026-09-12", "Five two."),
            ("Unit 5, Day 3", "false", "2026-09-13", "Five three."),
        ]
        for page in pages {
            try write(page: page.title, publish: page.publish, date: page.date, body: page.body,
                      in: made.course)
        }

        var dates: [String] = []
        for day in 8...30 {
            dates.append(String(format: "2026-09-%02d", day))
        }
        for day in 1...30 {
            dates.append(String(format: "2026-10-%02d", day))
        }
        try SectionTimetableStore.applyRememberTimetable(
            try SectionTimetableStore.planRememberTimetable(
                dates: dates, source: "timetable.xlsx, block H", forSection: 1, in: made.course
            )
        )

        // The curriculum, as a payload writes it: an expectation page with the
        // block anchor a transclusion points at, and a Concepts page to add
        // it to.
        let curriculumURL: URL = made.course.directoryURL.appendingPathComponent("Curriculum")
        try FileManager.default.createDirectory(at: curriculumURL, withIntermediateDirectories: true)
        try """
        ---
        transcludeTitleSize: h4
        tags:
          - A1
        ---
        use a variety of problem-solving strategies to solve programming problems ^text
        """.write(to: curriculumURL.appendingPathComponent("A1.1.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: Loops
        publishForSection1: true
        createdSection1: 2026-09-08T07:00:00.000-0400
        ---

        A loop repeats work.
        """.write(
            to: made.course.directoryURL.appendingPathComponent("Concepts/Loops.md"),
            atomically: true, encoding: .utf8
        )
        return made
    }

    /// A section with class dates on file and one page sitting on the wrong
    /// day, built on the shared fixture so the course, its settings and its
    /// site marker are the ones every other assistant test uses.
    ///
    /// Moved here from `RolloverWebsiteTests` (#150), because it is the world
    /// in which a rollover's `rollover` and `website` arguments change the
    /// answer — the rich section above has nothing for them to change — and
    /// the card-argument walk needs it too.
    @MainActor
    static func makeSectionNeedingReDating(
        withMarker: Bool = false,
        for testCase: XCTestCase
    ) throws -> Made {
        let made: Made = try makeRunner(hasDeployedBefore: withMarker)
        try keepScheduledPublishingInside(made.root, for: testCase)

        let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2026-09-08", "2026-09-10"], source: "timetable.xlsx, block H",
            forSection: 1, in: made.course
        )
        try SectionTimetableStore.applyRememberTimetable(plan)

        // Dated a day the section does not meet, so a re-date has something
        // real to move and does not stop at "already on the right day".
        let classesURL: URL = made.course.directoryURL
            .appendingPathComponent("section1/All Classes")
        try """
        ---
        title: Unit 1, Day 1
        date: 2020-01-15
        ---
        Something to move.
        """.write(
            to: classesURL.appendingPathComponent("Unit 1, Day 1.md"),
            atomically: true, encoding: .utf8
        )
        return made
    }

    /// A numbered course with four hidden weeks, Week 2 linking to Week 3,
    /// and a timetable the pages do not sit on — so re-dating moves them.
    ///
    /// Moved here from `ClubNounTests` (#150) so the card walks can match a
    /// club's own families in the world they are written for.
    @MainActor
    static func makeClub(noun: ClassNoun) throws -> Made {
        let made: Made = try makeRunner()
        try setClubNaming(noun, in: made.course)
        var day: Int = 8
        for title in ["Week 1", "Week 2", "Week 3", "Week 4"] {
            var body: String = "The words of \(title)."
            if title == "Week 2" {
                body += " Carry on in [[Week 3]]."
            }
            try write(
                page: title, publish: "false",
                date: String(format: "2026-09-%02d", day),
                body: body, in: made.course
            )
            day += 1
        }
        try SectionTimetableStore.applyRememberTimetable(
            try SectionTimetableStore.planRememberTimetable(
                dates: ["2026-09-08", "2026-09-09", "2026-09-14", "2026-09-16", "2026-09-21",
                        "2026-09-23", "2026-09-28", "2026-09-30", "2026-10-05"],
                source: "timetable.xlsx, block H", forSection: 1, in: made.course
            )
        )
        return made
    }

    /// The club above with a meeting on every day a card names — Saturday
    /// the 12th, Sunday the 13th and Monday the 14th as well — so each
    /// "publish <day>'s meeting" finds one rather than being refused.
    @MainActor
    static func makeBusyClub() throws -> Made {
        let made: Made = try makeClub(noun: .meeting)
        let more: [(title: String, date: String)] = [
            ("Week 5", "2026-09-12"), ("Week 6", "2026-09-13"), ("Week 7", "2026-09-14"),
        ]
        for page in more {
            try write(page: page.title, publish: "false", date: page.date,
                      body: "The words of \(page.title).", in: made.course)
        }
        return made
    }

    /// A section with a site whose pages are ALREADY on their days: the one
    /// world where a rollover's own words change what its plan says.
    ///
    /// While there are dates to move, a rollover's plan and a re-date's are
    /// the same plan, and the website question is asked after Go. With nothing
    /// to move, the twin answers the question instead (`rollover` alone),
    /// or plans the answer (`website`) — see `RolloverWebsiteTests`'
    /// `testTheTwinAnswersTheWebsiteQuestionRatherThanProposingIt`. Reached by
    /// re-dating the section for real, so "already right" is whatever the
    /// re-date says it is rather than a date written here by hand.
    @MainActor
    static func makeSectionAlreadyReDated(for testCase: XCTestCase) async throws -> Made {
        let made: Made = try makeSectionNeedingReDating(withMarker: true, for: testCase)
        let reDated: AssistToolOutcome = await run("re_date_classes", with: [:], on: made.runner)
        XCTAssertFalse(reDated.summary.isEmpty, "The fixture's own re-date said nothing.")
        return made
    }

    /// Writes a club's naming to disk, which is where the runner reads it.
    @MainActor
    static func setClubNaming(_ noun: ClassNoun, in course: Course) throws {
        course.configuration.unitWord = "Week"
        course.configuration.classPageScheme = .numbered
        course.configuration.classNoun = noun
        try course.configuration.write(
            to: course.directoryURL.appendingPathComponent("course_config.json")
        )
    }

    /// Runs one tool on a runner, directly, with this window's course and
    /// section filled in under whatever the arguments say.
    @MainActor
    static func run(_ tool: String,
                    with arguments: [String: Any],
                    on runner: AssistToolRunner) async -> AssistToolOutcome {
        var full: [String: Any] = ["course": "ICS3U", "section": 1]
        for (key, value) in arguments {
            full[key] = value
        }
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: full)) ?? Data("{}".utf8)
        return await runner.run(call: AssistToolCall(
            id: UUID().uuidString, type: "function",
            function: AssistToolCall.Function(name: tool, arguments: String(decoding: encoded, as: UTF8.self))
        ))
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
