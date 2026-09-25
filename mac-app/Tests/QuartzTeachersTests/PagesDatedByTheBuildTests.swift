import XCTest
@testable import QuartzTeachers

/// The build's report of the pages it gave their class's date (#275, #276),
/// read the way the app reads it: out of the console as it arrives, onto the
/// activity trail, and out of what a teacher sees.
@MainActor
final class PagesDatedByTheBuildTests: XCTestCase {

    // MARK: - Stored properties

    private var section: [String: Any] = [:]
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        section = try XCTUnwrap(all["pagesDatedByTheBuild"] as? [String: Any])

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pages-dated-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Tests

    func testTheMarkerPrefixMatchesTheContract() throws {
        let marker: [String: Any] = try XCTUnwrap(section["marker"] as? [String: Any])
        XCTAssertEqual(PagesDatedByTheBuild.markerPrefix, try XCTUnwrap(marker["prefix"] as? String),
                       "the app would stop hearing about pages the build still rewrites")
        let trailLine: [String: Any] = try XCTUnwrap(section["trailLine"] as? [String: Any])
        XCTAssertEqual(ActivityTrail.Event.pagesDatedByTheBuild.rawValue,
                       try XCTUnwrap(trailLine["event"] as? String))
    }

    /// Lines the build prints, as the contract carries them — re-checked
    /// against `build_site.announce_dated_pages` by
    /// `scripts/test_dates_follow_the_class.py`, so the two halves cannot drift.
    func testTheBuildsOwnLinesAreUnderstood() throws {
        let marker: [String: Any] = try XCTUnwrap(section["marker"] as? [String: Any])
        let examples: [String] = try XCTUnwrap(marker["examples"] as? [String])
        XCTAssertFalse(examples.isEmpty)
        for example in examples {
            let reports: [PagesDatedByTheBuild] = PagesDatedByTheBuild.reports(in: example)
            XCTAssertEqual(reports.count, 1, example)
            let report: PagesDatedByTheBuild = try XCTUnwrap(reports.first)
            XCTAssertEqual(report.course, "ICS4U")
            XCTAssertEqual(report.section, 1, "section must arrive as a number")
            XCTAssertEqual(report.pages, ["section1/index", "Exercises/Using Aggregate Functions"])
        }
    }

    func testTheTrailLineCountsFirstAndShortensALongList() {
        let two: PagesDatedByTheBuild = PagesDatedByTheBuild(
            course: "ICS4U", section: 1, pages: ["section1/index", "Exercises/Joins"]
        )
        XCTAssertEqual(two.trailSentence,
                       "the build gave 2 pages the date of their class: section1/index, Exercises/Joins")
        let one: PagesDatedByTheBuild = PagesDatedByTheBuild(course: "ICS4U", section: 1, pages: ["Exercises/Joins"])
        XCTAssertEqual(one.trailSentence, "the build gave 1 page the date of their class: Exercises/Joins")

        var many: [String] = []
        for number in 1...45 {
            many.append("Exercises/Page \(number)")
        }
        let long: PagesDatedByTheBuild = PagesDatedByTheBuild(course: "ICS4U", section: 1, pages: many)
        XCTAssertTrue(long.trailSentence.hasPrefix("the build gave 45 pages"))
        XCTAssertTrue(long.trailSentence.hasSuffix("Exercises/Page 40 and 5 more"), long.trailSentence)
    }

    /// Through the real runner, with the line ending real output uses: the
    /// line lands on the trail, and never in the console a teacher reads.
    func testARunRecordsTheNamesAndHidesTheLine() throws {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("📆 Gave 2 of your page(s) the date of the first class that links to them.\r\n")
        runner.receiveOutput(
            "PLANTOIR_DATED: {\"course\": \"ICS4U\", \"section\": 1, \"pages\": [\"section1/index\", \"Exercises/Using Aggregate Functions\"]}\r\n"
        )
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains("PLANTOIR_DATED"), shown)
        XCTAssertTrue(shown.contains("Gave 2 of your page(s)"))

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("ICS4U/1 · the build gave 2 pages the date of their class: section1/index, Exercises/Using Aggregate Functions"), trail)
    }

    /// A scheduled publish runs with nobody watching a console: its build's
    /// output goes to the run's own log, and the run reads that log once it
    /// is done. The trail line has to come from there, or the build likeliest
    /// to rewrite a teacher's files — the first one after a class goes
    /// visible, often at half six in the morning — leaves no trace.
    func testAScheduledPublishRecordsTheNamesFromItsLog() throws {
        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        let log: URL = ScheduledDeploy.logURL(courseCode: "ICS4U", sectionNumber: 1, inHomeFolder: home)
        try FileManager.default.createDirectory(
            at: log.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let lastNight: String = "PLANTOIR_DATED: {\"course\": \"ICS4U\", \"section\": 1, \"pages\": [\"Exercises/Joins\"]}\n"
        let tonight: String = "Deploying ICS4U…\n"
            + "PLANTOIR_DATED: {\"course\": \"ICS4U\", \"section\": 1, \"pages\": [\"section1/index\", \"Exercises/Using Aggregate Functions\"]}\n"
            + "Deploy complete\n"
        try (lastNight + tonight).write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS4U", sectionNumber: 1),
            fromByteOffset: UInt64(lastNight.utf8.count),
            inHomeFolder: home
        )

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("ICS4U/1 · the build gave 2 pages the date of their class: section1/index, Exercises/Using Aggregate Functions"), trail)
        XCTAssertFalse(trail.contains("Exercises/Joins"), "an earlier night's line was recorded again")
    }

    func testOrdinaryOutputAndBrokenLinesReportNothing() {
        XCTAssertTrue(PagesDatedByTheBuild.reports(in: "📆 Dated 3 page(s) from the first class that links to them.").isEmpty)
        XCTAssertTrue(PagesDatedByTheBuild.reports(in: "PLANTOIR_DATED: {not json").isEmpty)
        XCTAssertTrue(PagesDatedByTheBuild.reports(in: "PLANTOIR_DATED: {\"course\": \"X\", \"section\": 1, \"pages\": []}").isEmpty)
    }

    /// The same two console leaks #153 found in the health line (the director
    /// ruled this marker gets the same fix): a marker glued to the tail of
    /// somebody else's half line was DROPPED — no trail line — while the raw
    /// JSON was shown; and half a marker was shown until its newline arrived.
    func testAGluedOrHalfArrivedLineIsReadAndNeverShown() throws {
        let marker: String = "PLANTOIR_DATED: {\"course\": \"ICS4U\", \"section\": 1, \"pages\": [\"section1/index\"]}"
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("Building…")
        runner.receiveOutput(marker + "\r\n")
        runner.receiveOutput("ok\r\n")
        let cut: String.Index = marker.index(marker.startIndex, offsetBy: 30)
        runner.receiveOutput(String(marker[..<cut]))
        let whileArriving: String = runner.transcript.displayText
        XCTAssertFalse(whileArriving.contains("PLANTOIR_DATED"), whileArriving)
        XCTAssertFalse(runner.transcript.recentText(maximumCharacters: 8000).contains("PLANTOIR_DATED"))
        runner.receiveOutput(String(marker[cut...]) + "\r\n")

        let shown: String = runner.transcript.displayText
        XCTAssertEqual(shown, "ok", "the glued line goes whole, and the finished half line with it")

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        let expected: String = "ICS4U/1 · the build gave 1 page the date of their class: section1/index"
        XCTAssertEqual(trail.components(separatedBy: expected).count - 1, 2,
                       "the glued line and the split line are each read once: \(trail)")
    }
}
