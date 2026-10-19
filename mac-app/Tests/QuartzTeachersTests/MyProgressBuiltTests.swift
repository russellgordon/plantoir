import XCTest
@testable import QuartzTeachers

/// What a build did about the My Progress page (#545), read the way the app
/// reads it — out of the console as it arrives and out of a scheduled
/// publish's log, onto the activity trail — and the two course settings the
/// build honours, read as the contract's cases say.
@MainActor
final class MyProgressBuiltTests: XCTestCase {

    // MARK: - Stored properties

    private var rules: [String: Any] = [:]
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    private let built: String =
        "PLANTOIR_MY_PROGRESS: {\"course\": \"ICS3U\", \"section\": 1, \"built\": true, \"pages\": 12, \"reason\": \"built\"}"

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        rules = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    private func section(_ name: String) throws -> [String: Any] {
        return try XCTUnwrap(rules[name] as? [String: Any])
    }

    // MARK: - Tests

    func testTheMarkerAndTheEventMatchTheContract() throws {
        let marker: [String: Any] = try XCTUnwrap(try section("myProgressBuilt")["marker"] as? [String: Any])
        XCTAssertEqual(MyProgressBuilt.markerPrefix, try XCTUnwrap(marker["prefix"] as? String))
        let trailLine: [String: Any] = try XCTUnwrap(try section("myProgressBuilt")["trailLine"] as? [String: Any])
        XCTAssertEqual(ActivityTrail.Event.myProgressBuilt.rawValue, try XCTUnwrap(trailLine["event"] as? String))
    }

    /// The contract's examples — which `scripts/test_my_progress.py` checks
    /// are exactly what `my_progress.announce` prints — each read, and each
    /// written on the trail in the shape the contract gives for its reason.
    func testTheBuildsOwnLinesAreUnderstoodAndSaidInTheirShape() throws {
        let built: [String: Any] = try section("myProgressBuilt")
        let marker: [String: Any] = try XCTUnwrap(built["marker"] as? [String: Any])
        let examples: [String] = try XCTUnwrap(marker["examples"] as? [String])
        let trailLine: [String: Any] = try XCTUnwrap(built["trailLine"] as? [String: Any])
        let shapes: [String: String] = try XCTUnwrap(trailLine["shapes"] as? [String: String])
        XCTAssertEqual(examples.count, 3)
        for example in examples {
            let report: MyProgressBuilt = try XCTUnwrap(MyProgressBuilt.reports(in: example).first, example)
            let shape: String = try XCTUnwrap(shapes[report.reason], report.reason)
            let filled: String = shape
                .replacingOccurrences(of: "N page(s)", with: report.pages == 1 ? "1 page" : "\(report.pages) pages")
            XCTAssertEqual(report.trailSentence, filled, example)
        }
        let first: MyProgressBuilt = try XCTUnwrap(MyProgressBuilt.reports(in: examples[0]).first)
        XCTAssertEqual(first, MyProgressBuilt(course: "ICS3U", section: 1, built: true, pages: 12, reason: "built"))
    }

    func testOnePageIsOnePage() {
        let one: MyProgressBuilt = MyProgressBuilt(course: "ICS3U", section: 1, built: true, pages: 1, reason: "built")
        XCTAssertEqual(one.trailSentence, "the build made the My Progress page: 1 page with success criteria to tick")
    }

    /// Through the real runner: on the trail, never in the console.
    func testARunRecordsItAndHidesTheLine() throws {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("📈 My Progress: counted the success criteria on 12 page(s).\r\n")
        runner.receiveOutput(built + "\r\n")
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains("PLANTOIR_MY_PROGRESS"), shown)
        XCTAssertTrue(shown.contains("My Progress: counted"))
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("ICS3U/1 · the build made the My Progress page: 12 pages with success criteria to tick"), trail)
    }

    /// The build nobody watches: a scheduled publish reads its own log.
    func testAScheduledPublishRecordsItFromItsLog() throws {
        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS3U", sectionNumber: 1) + ".0a1b2c3d"
        let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lastNight: String =
            "PLANTOIR_MY_PROGRESS: {\"course\": \"ICS3U\", \"section\": 1, \"built\": false, \"pages\": 0, \"reason\": \"noSuccessCriteria\"}\n"
        let tonight: String = "Deploying ICS3U…\n" + built + "\nDeploy complete\n"
        try (lastNight + tonight).write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(
            label: label,
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS3U", sectionNumber: 1),
            fromByteOffset: UInt64(lastNight.utf8.count),
            inHomeFolder: home
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("the build made the My Progress page: 12 pages"), trail)
        XCTAssertFalse(trail.contains("made no My Progress page"), "an earlier night's line was recorded again")
    }

    /// `myProgress.config.cases`, through the read-only accessors: the switch
    /// read as `include_curriculum_coverage` is, and the heading list (an
    /// empty answer means the build's defaults).
    func testTheSettingsReadAsTheContractSays() throws {
        let config: [String: Any] = try XCTUnwrap(try section("myProgress")["config"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(config["cases"] as? [[String: Any]])
        let headings: [String: Any] = try XCTUnwrap(try section("myProgress")["headings"] as? [String: Any])
        let defaults: [String] = try XCTUnwrap(headings["defaults"] as? [String])
        XCTAssertGreaterThanOrEqual(cases.count, 14)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let values: [String: Any] = try XCTUnwrap(testCase["config"] as? [String: Any])
            let sectionNumber: Int = try XCTUnwrap(testCase["section"] as? Int)
            let wanted: Bool = try XCTUnwrap(testCase["wanted"] as? Bool)
            let expected: [String] = try XCTUnwrap(testCase["headings"] as? [String])
            let configuration: CourseConfiguration = CourseConfiguration(values: values, lastSavedData: Data())
            XCTAssertEqual(configuration.includesMyProgress(inSection: sectionNumber), wanted, name)
            let read: [String] = configuration.successCriteriaHeadings
            XCTAssertEqual(read.isEmpty ? defaults : read, expected, name)
        }
    }
}
