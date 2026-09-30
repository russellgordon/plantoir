import XCTest
@testable import QuartzTeachers

/// GitHub #378: what a launcher waits for is named in the status line
/// (decision 3), and work left behind by a program that had closed is ended
/// and written on the trail (decision 2).
///
/// Every word comes from the contract, never retyped here:
/// `contracts/app-rules.json` → `previewPorts.whenTheWorkspaceIsInUse
/// .sentences` for the words the status line shares with the launchers'
/// console, and `contracts/shared-rules.json` → `activityTrail.mustRecord
/// ."left-over work stopped"` for the trail line. `scripts/test_port_blocks.py`
/// runs the launchers' half against the same keys.
@MainActor
final class WorkspaceWaitTests: XCTestCase {

    // MARK: - Stored properties

    private var sentences: [String: Any] = [:]
    private var leftoverEntry: [String: Any] = [:]
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        let contracts: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts", isDirectory: true)
        let appRules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: try Data(contentsOf: contracts.appendingPathComponent("app-rules.json"))
            ) as? [String: Any]
        )
        let ports: [String: Any] = try XCTUnwrap(appRules["previewPorts"] as? [String: Any])
        let inUse: [String: Any] = try XCTUnwrap(ports["whenTheWorkspaceIsInUse"] as? [String: Any])
        sentences = try XCTUnwrap(inUse["sentences"] as? [String: Any])

        let sharedRules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: try Data(contentsOf: contracts.appendingPathComponent("shared-rules.json"))
            ) as? [String: Any]
        )
        let trail: [String: Any] = try XCTUnwrap(sharedRules["activityTrail"] as? [String: Any])
        let required: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        for candidate in required {
            if candidate["event"] as? String == ActivityTrail.Event.leftoverWorkStopped.rawValue {
                leftoverEntry = candidate
            }
        }
        XCTAssertFalse(leftoverEntry.isEmpty, "the contract has no 'left-over work stopped' event")

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-wait-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Functions

    private func group(_ key: String) throws -> [String: String] {
        let raw: [String: Any] = try XCTUnwrap(sentences[key] as? [String: Any], "no sentences.\(key)")
        var words: [String: String] = [:]
        for (name, value) in raw {
            if name == "why" || name == "joined" {
                continue
            }
            words[name] = try XCTUnwrap(value as? String)
        }
        return words
    }

    private func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    /// R6's console, as the reproduction printed it, with the lines the
    /// launcher now prints for the app.
    private func theWaitAsALauncherPrintsIt(origin: String) -> [String] {
        return [
            "🚀 Starting container if needed...\r\n",
            "♻️  Plantoir has been updated, so it is setting this folder up again to use the update…\r\n",
            "⏳ Waiting for somebody to finish deploying MPM2D section 2 before Plantoir sets this folder up again…\r\n",
            "PLANTOIR_WAITING_FOR: publish MPM2D/2 \(origin)\r\n",
        ]
    }

    // MARK: - Tests: the words are the contract's

    func testTheSharedWordsAreTheContracts() throws {
        XCTAssertEqual(WorkspaceWords.originWords, try group("origins"))
        XCTAssertEqual(WorkspaceWords.doingWords, try group("doing"))
        XCTAssertEqual(WorkspaceWords.leftoverWords, try group("leftovers"))
        let status: [String: String] = try group("statusLine")
        XCTAssertEqual(WorkspaceWords.statusLineForWork, status["work"])
        XCTAssertEqual(WorkspaceWords.statusLineForAPreview, status["preview"])
        XCTAssertEqual(WorkspaceWords.statusLineForSomethingElse, status["somethingElse"])
        XCTAssertEqual(WorkspaceWords.statusLineCounter, status["counter"])
    }

    func testTheTrailLineAndMarkerAreTheContracts() throws {
        let marker: [String: Any] = try XCTUnwrap(leftoverEntry["marker"] as? [String: Any])
        XCTAssertEqual(LeftoverWorkReport.markerPrefix, try XCTUnwrap(marker["prefix"] as? String))
        XCTAssertEqual(LeftoverWorkReport.line, try XCTUnwrap(leftoverEntry["line"] as? String))
    }

    func testNoneOfTheWordsSaysWorkspaceOrNamesTheMachinery() throws {
        var lines: [String] = []
        for key in ["origins", "doing", "leftovers", "statusLine"] {
            for (_, value) in try group(key) {
                lines.append(value)
            }
        }
        lines.append(LeftoverWorkReport.line)
        for line in lines {
            let lowered: String = line.lowercased()
            for forbidden in ["workspace", "container", "docker", "script", "process", "launcher"] {
                XCTAssertFalse(lowered.contains(forbidden), "\(forbidden): \(line)")
            }
        }
    }

    // MARK: - Tests: the status line

    /// Every origin and every kind, rendered from the contract's templates.
    func testEveryWaitRendersTheContractsStatusLine() throws {
        let origins: [String: String] = try group("origins")
        let doing: [String: String] = try group("doing")
        let status: [String: String] = try group("statusLine")
        for (originWord, originWords) in origins {
            for (kind, doingTemplate) in doing {
                let place: String = kind == "setup" ? "-" : "MPM2D/2"
                let waits: [WorkspaceWait] = WorkspaceWait.waits(in: ["PLANTOIR_WAITING_FOR: \(kind) \(place) \(originWord)"])
                XCTAssertEqual(waits.count, 1)
                let doingWords: String = doingTemplate
                    .replacingOccurrences(of: "{course}", with: "MPM2D")
                    .replacingOccurrences(of: "{section}", with: "2")
                let expected: String = try XCTUnwrap(status["work"])
                    .replacingOccurrences(of: "{origin}", with: originWords)
                    .replacingOccurrences(of: "{doing}", with: doingWords)
                XCTAssertEqual(waits.first?.statusSentence, expected)
            }
        }
        let preview: [WorkspaceWait] = WorkspaceWait.waits(in: ["PLANTOIR_WAITING_FOR: preview ICS4U/1 -"])
        XCTAssertEqual(
            preview.first?.statusSentence,
            try XCTUnwrap(status["preview"]).replacingOccurrences(of: "{course}", with: "ICS4U")
                .replacingOccurrences(of: "{section}", with: "1")
        )
        let unnamed: [WorkspaceWait] = WorkspaceWait.waits(in: ["PLANTOIR_WAITING_FOR: work - terminal"])
        XCTAssertEqual(unnamed.first?.statusSentence, status["somethingElse"])
    }

    /// Through the real runner: the status line names the wait with its own
    /// counter, and "over" gives it back. MUST-FAIL: without the marker
    /// handling this reads "… still working… (59s)".
    func testTheStatusLineNamesWhatIsWaitedForThenGivesItBack() {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.preview
        runner.isRunning = true
        for chunk in theWaitAsALauncherPrintsIt(origin: "claude") {
            runner.receiveOutput(chunk)
        }
        let began: Date = runner.waitingSince ?? Date()
        let later: Date = began.addingTimeInterval(59)
        runner.lastOutputAt = began
        XCTAssertEqual(
            runner.milestoneText(asOf: later),
            "Waiting for Revise with Claude to finish deploying MPM2D section 2… (59s)"
        )
        XCTAssertFalse(runner.transcript.displayText.contains("PLANTOIR_WAITING_FOR"),
                       "the marker is machinery (rule 1)")

        runner.receiveOutput("PLANTOIR_WAITING_FOR: over\r\n")
        // Back to the step's own label and the quiet timer, which is what the
        // line said for the whole wait before #378.
        XCTAssertTrue(runner.milestoneText(asOf: later).hasPrefix("Gathering your content…"),
                      runner.milestoneText(asOf: later))
    }

    /// The wait began in the same stretch of output as the step before it:
    /// reaching that step must not give the line back.
    func testAWaitArrivingWithTheStepBeforeItIsKept() {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.preview
        runner.isRunning = true
        runner.receiveOutput(theWaitAsALauncherPrintsIt(origin: "scheduled").joined())
        XCTAssertEqual(runner.waitingSentence, "Waiting for a scheduled deploy to finish deploying MPM2D section 2…")
    }

    /// A launcher killed mid-wait prints no "over": the next step, or the run
    /// ending, gives the line back (plan risk 5).
    func testALostOverIsRecoveredByTheNextStepOrTheEnd() {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.preview
        runner.isRunning = true
        for chunk in theWaitAsALauncherPrintsIt(origin: "window") {
            runner.receiveOutput(chunk)
        }
        XCTAssertFalse(runner.waitingSentence.isEmpty)
        runner.receiveOutput("📁 Copying shared folders…\r\n")
        XCTAssertEqual(runner.waitingSentence, "")

        for chunk in theWaitAsALauncherPrintsIt(origin: "window") {
            runner.receiveOutput(chunk)
        }
        runner.simulateFinishForTesting(exitCode: 1)
        XCTAssertEqual(runner.waitingSentence, "")
        XCTAssertNil(runner.waitingSince)
    }

    func testMalformedWaitLinesSayNothing() {
        XCTAssertTrue(WorkspaceWait.waits(in: ["PLANTOIR_WAITING_FOR: dancing MPM2D/2 claude"]).isEmpty)
        XCTAssertTrue(WorkspaceWait.waits(in: ["PLANTOIR_WAITING_FOR: publish MPM2D/2"]).isEmpty)
        XCTAssertTrue(WorkspaceWait.waits(in: ["⏳ Waiting for something"]).isEmpty)
    }

    // MARK: - Tests: the trail

    func testEveryExampleIsUnderstoodAndWritten() throws {
        let marker: [String: Any] = try XCTUnwrap(leftoverEntry["marker"] as? [String: Any])
        let examples: [String] = try XCTUnwrap(marker["examples"] as? [String])
        XCTAssertEqual(examples.count, 2)
        XCTAssertEqual(LeftoverWorkReport.reports(in: examples[0]),
                       [LeftoverWorkReport(place: "ICS4U/1", items: ["publish:MPM2D/2"])])
        XCTAssertEqual(
            LeftoverWorkReport.reports(in: examples[1]),
            [LeftoverWorkReport(place: "setup", items: ["build:ICS4U/1", "preview:ICS4U/2", "other"])]
        )
        XCTAssertEqual(
            LeftoverWorkReport(place: "setup", items: ["build:ICS4U/1", "preview:ICS4U/2", "other"]).trailSentence,
            "setup · stopped a build of ICS4U section 1, a preview of ICS4U section 2 and something else, "
                + "left running in this folder after the program that started it had closed, before setting the folder up again"
        )
    }

    /// Through the real runner: the line reaches the trail, and never the
    /// console a teacher reads.
    func testARunRecordsItAndHidesTheLine() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("🧹 Stopped a deploy of MPM2D section 2, left running after the program that started it had closed. Your pages were not touched.\r\n")
        runner.receiveOutput("PLANTOIR_LEFTOVER_STOPPED: ICS4U/1 publish:MPM2D/2\r\n")
        XCTAssertFalse(runner.transcript.displayText.contains(LeftoverWorkReport.markerPrefix))
        XCTAssertTrue(trailText().contains(
            "ICS4U/1 · stopped a deploy of MPM2D section 2, left running in this folder"
        ), trailText())
    }

    /// A publish set for later: read from its log, as nobody watches it.
    func testAScheduledPublishRecordsItFromItsLog() throws {
        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS4U", sectionNumber: 2) + ".0a1b2c3d"
        let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Deploying ICS4U…\nPLANTOIR_LEFTOVER_STOPPED: ICS4U/2 build:ICS4U/1\n".write(to: log, atomically: true, encoding: .utf8)
        ScheduledDeploy.recordFolderProblems(
            label: label,
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS4U", sectionNumber: 2),
            fromByteOffset: 0,
            inHomeFolder: home
        )
        XCTAssertTrue(trailText().contains("ICS4U/2 · stopped a build of ICS4U section 1"), trailText())
    }

    /// Nothing but kinds, courses and sections can reach the trail: a line
    /// carrying a path or a command is refused whole.
    func testAPathOrACommandNeverReachesTheTrail() {
        XCTAssertTrue(LeftoverWorkReport.reports(in: "PLANTOIR_LEFTOVER_STOPPED: ICS4U/1 /Users/t/secret").isEmpty)
        XCTAssertTrue(LeftoverWorkReport.reports(in: "PLANTOIR_LEFTOVER_STOPPED: ICS4U/1 publish:MPM2D/2 sh -c read").isEmpty)
        XCTAssertTrue(LeftoverWorkReport.reports(in: "PLANTOIR_LEFTOVER_STOPPED: ICS4U/1").isEmpty)
        XCTAssertTrue(LeftoverWorkReport.reports(in: "PLANTOIR_LEFTOVER_STOPPED: /Users/t publish:MPM2D/2").isEmpty)
        XCTAssertTrue(LeftoverWorkReport.reports(in: "PLANTOIR_LEFTOVER_STOPPED: ICS4U/1 publish:setup").isEmpty)
    }
}
