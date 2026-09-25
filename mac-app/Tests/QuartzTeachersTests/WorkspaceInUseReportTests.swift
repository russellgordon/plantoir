import XCTest
@testable import QuartzTeachers

/// A launcher's report that a folder's workspace was in use when it needed
/// remaking (GitHub #94), read the way the app reads it: out of the console
/// as it arrives and out of a scheduled publish's log, onto the activity
/// trail, and never into what a teacher sees.
///
/// Every sentence here comes from `contracts/shared-rules.json` →
/// `activityTrail.mustRecord."workspace was in use"`; the launcher's half of
/// the marker is checked against the same entry by
/// `scripts/test_port_blocks.py`, so the two cannot drift apart.
@MainActor
final class WorkspaceInUseReportTests: XCTestCase {

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
            if candidate["event"] as? String == ActivityTrail.Event.workspaceWasInUse.rawValue {
                entry = candidate
            }
        }
        XCTAssertFalse(entry.isEmpty, "the contract has no 'workspace was in use' event")

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-in-use-\(UUID().uuidString)", isDirectory: true)
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
        XCTAssertEqual(WorkspaceInUseReport.markerPrefix, try XCTUnwrap(marker["prefix"] as? String),
                       "the app would stop hearing what the launchers still print")
        XCTAssertEqual(WorkspaceInUseReport.lineWhenItWaited, try contractLine("lineWhenItWaited"))
        XCTAssertEqual(WorkspaceInUseReport.lineWhenAPreviewWasOpen, try contractLine("lineWhenAPreviewWasOpen"))
        XCTAssertEqual(WorkspaceInUseReport.lineWhenWorkDidNotFinish, try contractLine("lineWhenWorkDidNotFinish"))
    }

    func testEveryExampleIsUnderstood() throws {
        let lines: [String] = try examples()
        XCTAssertEqual(lines.count, 3)
        let waited: [WorkspaceInUseReport] = WorkspaceInUseReport.reports(in: lines[0])
        XCTAssertEqual(waited, [WorkspaceInUseReport(outcome: .waited, seconds: 14, place: "ICS4U/1", openPreview: "")])
        let preview: [WorkspaceInUseReport] = WorkspaceInUseReport.reports(in: lines[1])
        XCTAssertEqual(
            preview,
            [WorkspaceInUseReport(outcome: .aPreviewWasOpen, seconds: 20, place: "ICS4U/2", openPreview: "ICS4U/1")]
        )
        let work: [WorkspaceInUseReport] = WorkspaceInUseReport.reports(in: lines[2])
        XCTAssertEqual(work, [WorkspaceInUseReport(outcome: .workDidNotFinish, seconds: 600, place: "setup", openPreview: "")])
    }

    func testTheTrailSentenceFillsTheContractsLine() throws {
        let report: WorkspaceInUseReport = WorkspaceInUseReport(
            outcome: .aPreviewWasOpen, seconds: 20, place: "ICS4U/2", openPreview: "ICS4U/1"
        )
        let expected: String = try contractLine("lineWhenAPreviewWasOpen")
            .replacingOccurrences(of: "{place}", with: "ICS4U/2")
            .replacingOccurrences(of: "{preview}", with: "ICS4U/1")
        XCTAssertEqual(report.trailSentence, expected)
        XCTAssertFalse(report.trailSentence.contains("{"), report.trailSentence)
    }

    /// Through the real runner, with the line ending real output uses: the
    /// line lands on the trail, and never in the console a teacher reads.
    func testARunRecordsItAndHidesTheLine() throws {
        let runner: ScriptRunner = ScriptRunner()
        let example: String = try examples()[0]
        runner.receiveOutput("Rebuilding your workspace…\r\n")
        runner.receiveOutput(example + "\r\n")
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains(WorkspaceInUseReport.markerPrefix), shown)
        XCTAssertTrue(shown.contains("Rebuilding your workspace"), shown)

        let expected: String = try contractLine("lineWhenItWaited")
            .replacingOccurrences(of: "{place}", with: "ICS4U/1")
            .replacingOccurrences(of: "{seconds}", with: "14")
        XCTAssertTrue(trailText().contains(expected), trailText())
    }

    /// A publish set for later runs with nobody watching a console: its
    /// launchers' output goes to the run's own log, read once it is done.
    /// A publish that stood down on an open preview at half six is the one
    /// this line exists for.
    func testAScheduledPublishRecordsItFromItsLog() throws {
        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        // The job's own label, as the run takes it from its script (#237).
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS4U", sectionNumber: 2) + ".0a1b2c3d"
        let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
        try FileManager.default.createDirectory(
            at: log.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let lastNight: String = try examples()[2] + "\n"
        let tonight: String = "Deploying ICS4U…\n" + (try examples()[1]) + "\n"
        try (lastNight + tonight).write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(
            label: label,
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS4U", sectionNumber: 2),
            fromByteOffset: UInt64(lastNight.utf8.count),
            inHomeFolder: home
        )

        let expected: String = try contractLine("lineWhenAPreviewWasOpen")
            .replacingOccurrences(of: "{place}", with: "ICS4U/2")
            .replacingOccurrences(of: "{preview}", with: "ICS4U/1")
        XCTAssertTrue(trailText().contains(expected), trailText())
        XCTAssertFalse(trailText().contains("setup ·"), "an earlier night's line was recorded again")
    }

    /// #153's three guards, for this marker too. Glued to the tail of another
    /// line it is still read and still hidden; cut just after the colon, the
    /// half-arrived line is neither shown nor offered as a question.
    func testAMarkerGluedToAPartialLineIsReadAndHidden() throws {
        let example: String = try examples()[0]
        let glued: String = "Building ICS4U" + example
        XCTAssertEqual(WorkspaceInUseReport.reports(in: glued).count, 1, glued)
        XCTAssertTrue(WorkspaceInUseReport.isMarkerLine(glued))

        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(glued + "\r\n")
        XCTAssertFalse(runner.transcript.displayText.contains(WorkspaceInUseReport.markerPrefix))
        let expected: String = try contractLine("lineWhenItWaited")
            .replacingOccurrences(of: "{place}", with: "ICS4U/1")
            .replacingOccurrences(of: "{seconds}", with: "14")
        XCTAssertTrue(trailText().contains(expected), trailText())
    }

    func testAMarkerCutAfterItsColonIsNeitherShownNorAQuestion() {
        let half: String = "Building ICS4U " + WorkspaceInUseReport.markerPrefix
        XCTAssertFalse(ScriptRunner.looksLikeQuestion(half), "a half-arrived marker ends in a colon")
        XCTAssertFalse(ScriptRunner.looksLikeQuestion(WorkspaceInUseReport.markerPrefix))

        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(half)
        XCTAssertFalse(runner.transcript.displayText.contains(WorkspaceInUseReport.markerPrefix),
                       runner.transcript.displayText)
        XCTAssertFalse(runner.transcript.recentText(maximumCharacters: 4000).contains(WorkspaceInUseReport.markerPrefix))
    }

    func testOrdinaryOutputAndBrokenLinesReportNothing() {
        let prefix: String = WorkspaceInUseReport.markerPrefix
        XCTAssertTrue(WorkspaceInUseReport.reports(in: "Something in this folder is still running.").isEmpty)
        XCTAssertTrue(WorkspaceInUseReport.reports(in: prefix + " slept 14 ICS4U/1").isEmpty)
        XCTAssertTrue(WorkspaceInUseReport.reports(in: prefix + " waited soon ICS4U/1").isEmpty)
        XCTAssertTrue(WorkspaceInUseReport.reports(in: prefix + " preview 20 ICS4U/2").isEmpty,
                      "a refusal for a preview that names none")
        XCTAssertTrue(WorkspaceInUseReport.reports(in: prefix).isEmpty)
    }
}
