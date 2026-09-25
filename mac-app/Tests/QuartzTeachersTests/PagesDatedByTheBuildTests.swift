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
        runner.receiveOutput("📆 Gave 2 of your page(s) the date of the class that brings them.\r\n")
        runner.receiveOutput(
            "PLANTOIR_DATED: {\"course\": \"ICS4U\", \"section\": 1, \"pages\": [\"section1/index\", \"Exercises/Using Aggregate Functions\"]}\r\n"
        )
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains("PLANTOIR_DATED"), shown)
        XCTAssertTrue(shown.contains("Gave 2 of your page(s)"))

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("ICS4U/1 · the build gave 2 pages the date of their class: section1/index, Exercises/Using Aggregate Functions"), trail)
    }

    func testOrdinaryOutputAndBrokenLinesReportNothing() {
        XCTAssertTrue(PagesDatedByTheBuild.reports(in: "📆 Dated 3 page(s) from the first class that links to them.").isEmpty)
        XCTAssertTrue(PagesDatedByTheBuild.reports(in: "PLANTOIR_DATED: {not json").isEmpty)
        XCTAssertTrue(PagesDatedByTheBuild.reports(in: "PLANTOIR_DATED: {\"course\": \"X\", \"section\": 1, \"pages\": []}").isEmpty)
    }
}
