import XCTest
@testable import QuartzTeachers

/// A working folder's workspace made again (GitHub #684) leaves a line on the
/// trail, with the reason, written by the app from the launchers' marker.
///
/// Every word comes from the contract, never retyped here:
/// `contracts/shared-rules.json` → `activityTrail.mustRecord."folder set up
/// again"`. `scripts/test_port_blocks.py` pins the launcher half: that every
/// remake prints the marker, with a reason the contract has words for, and
/// only once the new workspace exists.
@MainActor
final class FolderSetUpAgainReportTests: XCTestCase {

    // MARK: - Stored properties

    private var entry: [String: Any] = [:]
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        let contracts: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts", isDirectory: true)
        let sharedRules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: try Data(contentsOf: contracts.appendingPathComponent("shared-rules.json"))
            ) as? [String: Any]
        )
        let trail: [String: Any] = try XCTUnwrap(sharedRules["activityTrail"] as? [String: Any])
        let required: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        for candidate in required {
            if candidate["event"] as? String == ActivityTrail.Event.folderSetUpAgain.rawValue {
                entry = candidate
            }
        }
        XCTAssertFalse(entry.isEmpty, "the contract has no 'folder set up again' event")

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder-set-up-again-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Functions

    private func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    private func examples() throws -> [String] {
        let marker: [String: Any] = try XCTUnwrap(entry["marker"] as? [String: Any])
        return try XCTUnwrap(marker["examples"] as? [String])
    }

    private func contractWords() throws -> [String: String] {
        return try XCTUnwrap(entry["whyWords"] as? [String: String])
    }

    // MARK: - Tests: the contract

    func testTheMarkerTheLinesAndTheWordsAreTheContractsOwn() throws {
        let marker: [String: Any] = try XCTUnwrap(entry["marker"] as? [String: Any])
        XCTAssertEqual(marker["prefix"] as? String, FolderSetUpAgainReport.markerPrefix)
        XCTAssertEqual(entry["line"] as? String, FolderSetUpAgainReport.line)
        XCTAssertEqual(entry["lineWithoutAReason"] as? String, FolderSetUpAgainReport.lineWithoutAReason)
        XCTAssertEqual(try contractWords(), FolderSetUpAgainReport.whyWords)
        XCTAssertEqual(entry["appliesOn"] as? [String], ["mac"], "Windows has no workspace to make again")
    }

    func testEveryExampleIsUnderstoodAndWritten() throws {
        let lines: [String] = try examples()
        XCTAssertEqual(lines.count, 3)
        let words: [String: String] = try contractWords()
        XCTAssertEqual(
            FolderSetUpAgainReport.reports(in: lines[0]).first?.trailSentence,
            "ICS4U/1 · set this folder up again — " + (words["update"] ?? "")
        )
        XCTAssertEqual(
            FolderSetUpAgainReport.reports(in: lines[1]).first?.trailSentence,
            "setup · set this folder up again — " + (words["thisMacOnly"] ?? "")
        )
        let spaced: [FolderSetUpAgainReport] = FolderSetUpAgainReport.reports(in: lines[2])
        XCTAssertEqual(spaced.count, 1, "a course whose code has a space must not drop the line")
        XCTAssertEqual(spaced.first?.trailSentence, "AP CALC/2 · set this folder up again — " + (words["buildsOutside"] ?? ""))
    }

    /// A reason this app has no words for is still a remake that happened:
    /// the line is written without a reason, never with a wrong one.
    func testAReasonWithNoWordsWritesTheLineWithoutOne() {
        let report: [FolderSetUpAgainReport] = FolderSetUpAgainReport.reports(
            in: FolderSetUpAgainReport.markerPrefix + " somethingNew ICS4U/2"
        )
        XCTAssertEqual(report.first?.trailSentence, "ICS4U/2 · set this folder up again")
        let unknown: [FolderSetUpAgainReport] = FolderSetUpAgainReport.reports(
            in: FolderSetUpAgainReport.markerPrefix + " unknown setup"
        )
        XCTAssertEqual(unknown.first?.trailSentence, "setup · set this folder up again")
    }

    // MARK: - Tests: the trail

    /// Through the real runner — Preview's and the assistant's path: the line
    /// reaches the trail, and never the console a teacher reads.
    func testARunRecordsItAndHidesTheLine() throws {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("♻️  Plantoir has been updated, so it is setting this folder up again to use the update…\r\n")
        runner.receiveOutput(try examples()[0] + "\r\n")
        XCTAssertFalse(runner.transcript.displayText.contains(FolderSetUpAgainReport.markerPrefix))
        XCTAssertTrue(trailText().contains("ICS4U/1 · set this folder up again — " + (try contractWords()["update"] ?? "")), trailText())
    }

    /// A publish set for later: read from its log, as nobody watches it.
    func testAScheduledPublishRecordsItFromItsLog() throws {
        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS4U", sectionNumber: 1) + ".0a1b2c3d"
        let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ("Deploying ICS4U…\n" + (try examples()[0]) + "\n").write(to: log, atomically: true, encoding: .utf8)
        ScheduledDeploy.recordFolderProblems(
            label: label,
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS4U", sectionNumber: 1),
            fromByteOffset: 0,
            inHomeFolder: home
        )
        XCTAssertTrue(trailText().contains("ICS4U/1 · set this folder up again — "), trailText())
    }

    /// Nothing but a reason word and a place can reach the trail.
    func testAPathOrACommandNeverReachesTheTrail() {
        let prefix: String = FolderSetUpAgainReport.markerPrefix
        XCTAssertTrue(FolderSetUpAgainReport.reports(in: prefix + " update").isEmpty)
        XCTAssertTrue(FolderSetUpAgainReport.reports(in: prefix + " update ICS4U/1 extra").isEmpty)
        XCTAssertTrue(FolderSetUpAgainReport.reports(in: prefix + " /Users/t/secret ICS4U/1").isEmpty)
        XCTAssertTrue(FolderSetUpAgainReport.reports(in: prefix + " update /Users/t/secret").isEmpty)
        XCTAssertTrue(FolderSetUpAgainReport.reports(in: prefix + " up-date ICS4U/1").isEmpty)
    }
}
