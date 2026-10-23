import XCTest
@testable import QuartzTeachers

/// The build's report of something it put right in the teacher's own files
/// (#584), read the way the app reads it: out of the console as it arrives and
/// out of a scheduled publish's log, onto the activity trail as `folder problem
/// repaired`, and out of what a teacher sees.
///
/// Every value comes from `contracts/shared-rules.json` → `buildRepairs`;
/// `scripts/test_front_page_title_repair.py` checks the build prints exactly
/// the contract's example, so the two halves cannot drift.
@MainActor
final class BuildRepairReportTests: XCTestCase {

    // MARK: - Stored properties

    private var rules: [String: Any] = [:]
    private var activityTrail: [String: Any] = [:]
    private var machineLines: [String: Any] = [:]
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Computed properties

    private var trail: String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        rules = try XCTUnwrap(all["buildRepairs"] as? [String: Any])
        activityTrail = try XCTUnwrap(all["activityTrail"] as? [String: Any])
        let stripping: [String: Any] = try XCTUnwrap(all["transcriptStripping"] as? [String: Any])
        machineLines = try XCTUnwrap(stripping["machineLines"] as? [String: Any])

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("build-repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Functions

    private func marker() throws -> [String: Any] {
        return try XCTUnwrap(rules["marker"] as? [String: Any])
    }

    private func example() throws -> String {
        let examples: [String] = try XCTUnwrap(try marker()["examples"] as? [String])
        return try XCTUnwrap(examples.first)
    }

    private func expectedTrailLine(page: String) throws -> String {
        let repair: [String: Any] = try XCTUnwrap(rules["frontPageTitleQuoted"] as? [String: Any])
        let line: String = try XCTUnwrap(repair["trailLine"] as? String)
        return line.replacingOccurrences(of: "{page}", with: page)
    }

    private func count(of words: String, in text: String) -> Int {
        return text.components(separatedBy: words).count - 1
    }

    // MARK: - The contract's values

    func testTheMarkerAndTheEventAreTheContracts() throws {
        XCTAssertEqual(BuildRepairReport.markerPrefix, try XCTUnwrap(try marker()["prefix"] as? String),
                       "the app would stop hearing about repairs the build still makes")
        XCTAssertNotNil(rules[BuildRepairReport.frontPageTitleQuoted] as? [String: Any],
                        "the repair's key is not one of the contract's")
        let mustRecord: [[String: Any]] = try XCTUnwrap(activityTrail["mustRecord"] as? [[String: Any]])
        var named: Bool = false
        for entry in mustRecord {
            if entry["event"] as? String == ActivityTrail.Event.folderProblemRepaired.rawValue {
                let carries: String = entry["carries"] as? String ?? ""
                named = carries.contains(try expectedTrailLine(page: "section1/index"))
            }
        }
        XCTAssertTrue(named, "the trail event's own entry should name the line the build's repair leaves")
    }

    func testTheContractsExampleIsUnderstood() throws {
        let reports: [BuildRepairReport] = BuildRepairReport.reports(in: "building\n" + (try example()) + "\n")
        XCTAssertEqual(reports, [BuildRepairReport(
            course: "SPH4U", section: 1, repair: "frontPageTitleQuoted", page: "section1/index"
        )])
        XCTAssertEqual(reports.first?.trailSentence, try expectedTrailLine(page: "section1/index"))
        XCTAssertFalse(ScriptRunner.looksLikeQuestion(try example()))
    }

    func testTheConsoleRuleHidesTheLine() throws {
        let cases: [[String: Any]] = try XCTUnwrap(machineLines["cases"] as? [[String: Any]])
        var listed: Bool = false
        for entry in cases {
            if entry["line"] as? String == (try example()) {
                listed = entry["hidden"] as? Bool == true
            }
        }
        XCTAssertTrue(listed, "transcriptStripping.machineLines should carry the marker's line, hidden")
        XCTAssertTrue(BuildRepairReport.isMarkerLine("🔨 Building…" + (try example())))
    }

    func testAnUnknownRepairOrABrokenLineLeavesNothing() {
        let newer: String = "PLANTOIR_REPAIRED: {\"course\": \"SPH4U\", \"section\": 1, "
            + "\"repair\": \"somethingNewer\", \"page\": \"section1/index\"}"
        let reports: [BuildRepairReport] = BuildRepairReport.reports(in: newer)
        XCTAssertEqual(reports.count, 1)
        XCTAssertNil(reports.first?.trailSentence)
        BuildRepairReport.noteOnTheTrail(from: newer)
        XCTAssertFalse(trail.contains("SPH4U/1"), trail)

        XCTAssertTrue(BuildRepairReport.reports(in: "PLANTOIR_REPAIRED: {not json").isEmpty)
        XCTAssertTrue(BuildRepairReport.reports(in: "PLANTOIR_REPAIRED: {\"course\": \"SPH4U\", \"section\": \"1\", "
            + "\"repair\": \"frontPageTitleQuoted\", \"page\": \"section1/index\"}").isEmpty,
            "section must arrive as a number")
        XCTAssertTrue(BuildRepairReport.reports(in: "🔧 Put quotes around the title of the front page.").isEmpty)
    }

    // MARK: - Through the real readers

    /// Through the real runner, with real line endings: the repair lands on the
    /// trail once, and the marker never reaches the console a teacher reads.
    func testARunRecordsTheRepairAndHidesTheMarker() throws {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("🔧 Put quotes around the title of the front page of SPH4U Section 1.\r\n")
        runner.receiveOutput(try example() + "\r\n")
        runner.receiveOutput("ok\r\n")
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains("PLANTOIR_REPAIRED"), shown)
        XCTAssertTrue(shown.contains("Put quotes around the title"), shown)

        let expected: String = "SPH4U/1 · " + (try expectedTrailLine(page: "section1/index"))
        XCTAssertEqual(count(of: expected, in: trail), 1, trail)
    }

    /// A scheduled publish's build writes to the run's own log, read once the
    /// run is done: the repair is recorded from there, and an earlier night's
    /// line before the offset is not recorded again.
    func testAScheduledPublishRecordsTheRepairFromItsLog() throws {
        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "SPH4U", sectionNumber: 1) + ".0a1b2c3d"
        let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
        try FileManager.default.createDirectory(
            at: log.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let lastNight: String = "PLANTOIR_REPAIRED: {\"course\": \"SPH4U\", \"section\": 1, "
            + "\"repair\": \"frontPageTitleQuoted\", \"page\": \"section1/earlier\"}\n"
        let tonight: String = "Deploying SPH4U…\n" + (try example()) + "\nDeploy complete\n"
        try (lastNight + tonight).write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(
            label: label,
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "SPH4U", sectionNumber: 1),
            fromByteOffset: UInt64(lastNight.utf8.count),
            inHomeFolder: home
        )

        let expected: String = "SPH4U/1 · " + (try expectedTrailLine(page: "section1/index"))
        XCTAssertEqual(count(of: expected, in: trail), 1, trail)
        XCTAssertFalse(trail.contains("section1/earlier"), "an earlier night's line was recorded again")
    }
}
