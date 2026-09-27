import XCTest
@testable import QuartzTeachers

/// The build's report of the curriculum coverage maps it wrote (#128), read
/// the way the app reads it — out of the console as it arrives and out of a
/// scheduled publish's log, onto the activity trail — and every `PLANTOIR_`
/// line kept out of what a teacher sees, by one rule.
@MainActor
final class CoverageMapsBuiltTests: XCTestCase {

    // MARK: - Stored properties

    private var rules: [String: Any] = [:]
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

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
            .appendingPathComponent("coverage-maps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    private var section: [String: Any] {
        get throws {
            return try XCTUnwrap(rules["coverageMapsBuilt"] as? [String: Any])
        }
    }

    private let twoMaps: String =
        "PLANTOIR_MAPS: {\"course\": \"ICS3U\", \"section\": 1, \"maps\": ["
        + "{\"title\": \"Curriculum Coverage\", \"folder\": \"Ontario Curriculum\", \"expectations\": 42}, "
        + "{\"title\": \"College Board Curriculum Coverage\", \"folder\": \"College Board Curriculum\", \"expectations\": 18}]}"

    private let twoMapsOnTheTrail: String =
        "ICS3U/1 · the build made 2 curriculum maps: Curriculum Coverage from Ontario Curriculum (42 expectations), "
        + "College Board Curriculum Coverage from College Board Curriculum (18 expectations)"

    // MARK: - Tests

    func testTheMarkerAndTheEventMatchTheContract() throws {
        let marker: [String: Any] = try XCTUnwrap(try section["marker"] as? [String: Any])
        XCTAssertEqual(CoverageMapsBuilt.markerPrefix, try XCTUnwrap(marker["prefix"] as? String))
        let trailLine: [String: Any] = try XCTUnwrap(try section["trailLine"] as? [String: Any])
        XCTAssertEqual(ActivityTrail.Event.coverageMapsBuilt.rawValue, try XCTUnwrap(trailLine["event"] as? String))
    }

    /// The contract's examples — which `scripts/test_coverage_maps.py` checks
    /// are exactly what `build_site.announce_coverage_maps` prints.
    func testTheBuildsOwnLinesAreUnderstood() throws {
        let marker: [String: Any] = try XCTUnwrap(try section["marker"] as? [String: Any])
        let examples: [String] = try XCTUnwrap(marker["examples"] as? [String])
        XCTAssertEqual(examples.count, 2)
        let first: CoverageMapsBuilt = try XCTUnwrap(CoverageMapsBuilt.reports(in: examples[0]).first)
        XCTAssertEqual(first.course, "ICS3U")
        XCTAssertEqual(first.section, 1)
        XCTAssertEqual(first.maps, [
            CoverageMapsBuilt.Map(title: "Curriculum Coverage", folder: "Ontario Curriculum", expectations: 42),
            CoverageMapsBuilt.Map(title: "College Board Curriculum Coverage", folder: "College Board Curriculum", expectations: 18),
        ])
        let none: CoverageMapsBuilt = try XCTUnwrap(CoverageMapsBuilt.reports(in: examples[1]).first,
                                                     "an empty list is a report too: it answers “my map is missing”")
        XCTAssertEqual(none.maps, [])
    }

    func testTheTrailSentences() {
        let none: CoverageMapsBuilt = CoverageMapsBuilt(course: "ICS3U", section: 2, maps: [])
        XCTAssertEqual(none.trailSentence,
                       "the build made no curriculum map: no curriculum folder holds an expectation page")
        let one: CoverageMapsBuilt = CoverageMapsBuilt(course: "ICS3U", section: 1, maps: [
            CoverageMapsBuilt.Map(title: "Curriculum Coverage", folder: "Curriculum", expectations: 1),
        ])
        XCTAssertEqual(one.trailSentence,
                       "the build made 1 curriculum map: Curriculum Coverage from Curriculum (1 expectation)")
    }

    /// Through the real runner: on the trail, never in the console.
    func testARunRecordsTheMapsAndHidesTheLine() throws {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("🗺️  Curriculum Coverage (Ontario Curriculum): 42 expectations\r\n")
        runner.receiveOutput(twoMaps + "\r\n")
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains("PLANTOIR_MAPS"), shown)
        XCTAssertTrue(shown.contains("Curriculum Coverage (Ontario Curriculum)"))
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(twoMapsOnTheTrail), trail)
    }

    /// The build nobody watches: a scheduled publish reads its own log.
    func testAScheduledPublishRecordsTheMapsFromItsLog() throws {
        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS3U", sectionNumber: 1) + ".0a1b2c3d"
        let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lastNight: String = "PLANTOIR_MAPS: {\"course\": \"ICS3U\", \"section\": 1, \"maps\": []}\n"
        let tonight: String = "Deploying ICS3U…\n" + twoMaps + "\nDeploy complete\n"
        try (lastNight + tonight).write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(
            label: label,
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS3U", sectionNumber: 1),
            fromByteOffset: UInt64(lastNight.utf8.count),
            inHomeFolder: home
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(twoMapsOnTheTrail), trail)
        XCTAssertFalse(trail.contains("made no curriculum map"), "an earlier night's line was recorded again")
    }

    /// `transcriptStripping.machineLines`: one rule for every marker, known or
    /// not — through the rule itself and through the console a teacher reads.
    func testEveryMarkerLineIsHiddenByOneRule() throws {
        let stripping: [String: Any] = try XCTUnwrap(rules["transcriptStripping"] as? [String: Any])
        let machineLines: [String: Any] = try XCTUnwrap(stripping["machineLines"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(machineLines["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        for testCase in cases {
            let line: String = try XCTUnwrap(testCase["line"] as? String)
            let hidden: Bool = try XCTUnwrap(testCase["hidden"] as? Bool)
            XCTAssertEqual(BuildMarkerLine.isMachineLine(line), hidden, line)

            let runner: ScriptRunner = ScriptRunner()
            runner.receiveOutput("before\r\n")
            // While it is still arriving, and once it has.
            runner.receiveOutput(line)
            XCTAssertEqual(runner.transcript.displayText.contains(line), !hidden, "arriving: \(line)")
            runner.receiveOutput("\r\n")
            XCTAssertEqual(runner.transcript.displayText.contains(line), !hidden, "finished: \(line)")
        }
    }
}
