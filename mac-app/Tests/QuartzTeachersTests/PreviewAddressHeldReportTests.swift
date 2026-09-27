import XCTest
@testable import QuartzTeachers

/// `preview.sh`'s report that a preview's address was held by something else
/// on this Mac (GitHub #310), read the way the app reads it: out of the
/// console as it arrives, onto the activity trail, and never into what a
/// teacher sees.
///
/// Every sentence here comes from `contracts/shared-rules.json` →
/// `activityTrail.mustRecord."preview address held by another account"`; the
/// launcher's half of the marker is checked against the same entry by
/// `scripts/test_port_blocks.py` and `scripts/test_preview_reach.py`, so the
/// two cannot drift apart.
@MainActor
final class PreviewAddressHeldReportTests: XCTestCase {

    // MARK: - Stored properties

    private var entry: [String: Any] = [:]
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
        let trail: [String: Any] = try XCTUnwrap(all["activityTrail"] as? [String: Any])
        let required: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        for candidate in required {
            if candidate["event"] as? String == ActivityTrail.Event.previewAddressHeldByAnotherAccount.rawValue {
                entry = candidate
            }
        }
        XCTAssertFalse(entry.isEmpty, "the contract has no 'preview address held by another account' event")

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-address-held-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Functions

    private func contractLine(_ key: String) throws -> String {
        return try XCTUnwrap(entry[key] as? String, "the contract has no \(key)")
    }

    private func examples() throws -> [String] {
        let marker: [String: Any] = try XCTUnwrap(entry["marker"] as? [String: Any])
        return try XCTUnwrap(marker["examples"] as? [String])
    }

    private func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    // MARK: - Tests

    func testTheMarkerAndTheLinesAreTheContracts() throws {
        let marker: [String: Any] = try XCTUnwrap(entry["marker"] as? [String: Any])
        XCTAssertEqual(PreviewAddressHeldReport.markerPrefix, try XCTUnwrap(marker["prefix"] as? String),
                       "the app would stop hearing what preview.sh still prints")
        XCTAssertEqual(PreviewAddressHeldReport.lineWhenRemadeBeforeStarting,
                       try contractLine("lineWhenRemadeBeforeStarting"))
        XCTAssertEqual(PreviewAddressHeldReport.lineWhenRemade, try contractLine("lineWhenRemade"))
        XCTAssertEqual(PreviewAddressHeldReport.lineWhenRefused, try contractLine("lineWhenRefused"))
        XCTAssertEqual(PreviewAddressHeldReport.lineWhenUnchecked, try contractLine("lineWhenUnchecked"))
    }

    func testTheEventIsTheMacsAlone() throws {
        let appliesOn: [String] = try XCTUnwrap(entry["appliesOn"] as? [String])
        XCTAssertEqual(appliesOn, ["mac"])
    }

    func testEveryExampleIsUnderstood() throws {
        let lines: [String] = try examples()
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(
            PreviewAddressHeldReport.reports(in: lines[0]),
            [PreviewAddressHeldReport(outcome: .remadeBeforeStarting, address: 8081, place: "ICS4U/1")]
        )
        XCTAssertEqual(
            PreviewAddressHeldReport.reports(in: lines[1]),
            [PreviewAddressHeldReport(outcome: .remade, address: 8081, place: "ICS4U/2")]
        )
        XCTAssertEqual(
            PreviewAddressHeldReport.reports(in: lines[2]),
            [PreviewAddressHeldReport(outcome: .refused, address: 8101, place: "ICS4U/2")]
        )
        XCTAssertEqual(
            PreviewAddressHeldReport.reports(in: lines[3]),
            [PreviewAddressHeldReport(outcome: .unchecked, address: 8091, place: "ICS4U/2")]
        )
    }

    func testTheTrailSentenceFillsTheContractsLine() throws {
        let report: PreviewAddressHeldReport = PreviewAddressHeldReport(
            outcome: .refused, address: 8101, place: "ICS4U/2"
        )
        let expected: String = try contractLine("lineWhenRefused")
            .replacingOccurrences(of: "{place}", with: "ICS4U/2")
            .replacingOccurrences(of: "{address}", with: "8101")
        XCTAssertEqual(report.trailSentence, expected)
        XCTAssertFalse(report.trailSentence.contains("{"), report.trailSentence)
    }

    /// Through the real runner, with the line ending real output uses: the
    /// line lands on the trail, and never in the console a teacher reads.
    func testARunRecordsItAndHidesTheLine() throws {
        let runner: ScriptRunner = ScriptRunner()
        let example: String = try examples()[1]
        runner.receiveOutput("Something else is now using this folder's preview addresses…\r\n")
        runner.receiveOutput(example + "\r\n")
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains(PreviewAddressHeldReport.markerPrefix), shown)
        XCTAssertTrue(shown.contains("Something else is now using"), shown)

        let expected: String = try contractLine("lineWhenRemade")
            .replacingOccurrences(of: "{place}", with: "ICS4U/2")
            .replacingOccurrences(of: "{address}", with: "8081")
        XCTAssertTrue(trailText().contains(expected), trailText())
    }

    /// #153's guards, for this marker too. Glued to the tail of another
    /// line it is still read and still hidden; cut just after the colon, the
    /// half-arrived line is neither shown nor offered as a question.
    func testAMarkerGluedToAPartialLineIsReadAndHidden() throws {
        let example: String = try examples()[2]
        let glued: String = "Building ICS4U" + example
        XCTAssertEqual(PreviewAddressHeldReport.reports(in: glued).count, 1, glued)
        XCTAssertTrue(PreviewAddressHeldReport.isMarkerLine(glued))

        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(glued + "\r\n")
        XCTAssertFalse(runner.transcript.displayText.contains(PreviewAddressHeldReport.markerPrefix))
        let expected: String = try contractLine("lineWhenRefused")
            .replacingOccurrences(of: "{place}", with: "ICS4U/2")
            .replacingOccurrences(of: "{address}", with: "8101")
        XCTAssertTrue(trailText().contains(expected), trailText())
    }

    func testAMarkerCutAfterItsColonIsNeitherShownNorAQuestion() {
        let half: String = "Building ICS4U " + PreviewAddressHeldReport.markerPrefix
        XCTAssertFalse(ScriptRunner.looksLikeQuestion(half), "a half-arrived marker ends in a colon")
        XCTAssertFalse(ScriptRunner.looksLikeQuestion(PreviewAddressHeldReport.markerPrefix))

        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(half)
        XCTAssertFalse(runner.transcript.displayText.contains(PreviewAddressHeldReport.markerPrefix),
                       runner.transcript.displayText)
        XCTAssertFalse(
            runner.transcript.recentText(maximumCharacters: 4000).contains(PreviewAddressHeldReport.markerPrefix)
        )
    }

    func testOrdinaryOutputAndBrokenLinesReportNothing() {
        let prefix: String = PreviewAddressHeldReport.markerPrefix
        XCTAssertTrue(PreviewAddressHeldReport.reports(in: "Something else is now using this folder's preview addresses.").isEmpty)
        XCTAssertTrue(PreviewAddressHeldReport.reports(in: prefix + " moved 8081 ICS4U/1").isEmpty)
        XCTAssertTrue(PreviewAddressHeldReport.reports(in: prefix + " remade soon ICS4U/1").isEmpty)
        XCTAssertTrue(PreviewAddressHeldReport.reports(in: prefix + " remade 0 ICS4U/1").isEmpty)
        XCTAssertTrue(PreviewAddressHeldReport.reports(in: prefix + " remade 8081").isEmpty,
                      "a report that names no place")
        XCTAssertTrue(PreviewAddressHeldReport.reports(in: prefix + " remade 8081 ICS4U/1 extra").isEmpty)
        XCTAssertTrue(PreviewAddressHeldReport.reports(in: prefix).isEmpty)
    }
}
