import XCTest
@testable import QuartzTeachers

/// Reading the toolchain's health findings out of a build's output.
///
/// The sentences themselves are the toolchain's — they come from
/// `contracts/shared-rules.json` → `siteHealth.checks` and travel inside the
/// marker line — so what is pinned here is the READING: that findings are
/// picked up at all, that they survive a long build, that the machinery stays
/// out of what a teacher sees, and that each one reaches the activity trail.
@MainActor
final class SiteHealthFindingTests: XCTestCase {

    // MARK: - Stored properties

    private let curriculumLine: String = """
    PLANTOIR_HEALTH: {"name": "curriculumCoverageFoundNothing", "sentence": \
    "The curriculum map for ICS3U Section 1 could not be built.", "detail": \
    "Plantoir looks for a folder whose name mentions the curriculum.", \
    "fixable": false, "course": "ICS3U", "section": 1}
    """

    private let mediaLine: String = """
    PLANTOIR_HEALTH: {"name": "mediaFolderMissing", "sentence": \
    "The Media folder for ICS3U is not there.", "detail": "Images live there.", \
    "fixable": true, "course": "ICS3U", "section": 1}
    """

    // MARK: - Functions

    func testAFindingIsReadOutOfTheOutput() {
        let found: [SiteHealthFinding] = SiteHealthFinding.findings(in: curriculumLine)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.name, "curriculumCoverageFoundNothing")
        XCTAssertEqual(found.first?.course, "ICS3U")
        XCTAssertEqual(found.first?.section, 1)
        XCTAssertEqual(found.first?.fixable, false)
        XCTAssertTrue(found.first?.sentence.contains("could not be built") ?? false)
    }

    /// Real output comes from a PTY and ends "\r\n", while every other test
    /// here supplies "\n".
    ///
    /// Worth pinning even though it already worked: this was written believing
    /// the trailing carriage return broke the JSON parse, and it does not —
    /// the test passes against the old code too. It now guards a difference
    /// between what the tests feed in and what a real build sends.
    func testAFindingSurvivesWindowsStyleLineEndings() {
        let asAPTYSendsIt: String = curriculumLine + "\r\n"
        let found: [SiteHealthFinding] = SiteHealthFinding.findings(in: asAPTYSendsIt)
        XCTAssertEqual(found.count, 1, "a finding must survive \\r\\n line endings")
        XCTAssertEqual(found.first?.name, "curriculumCoverageFoundNothing")
        XCTAssertTrue(SiteHealthFinding.isMarkerLine(curriculumLine + "\r"))
    }

    func testARunnerReadsAFindingOutOfCarriageReturnedOutput() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("Copying shared folders\r\n")
        runner.receiveOutput(curriculumLine + "\r\n")
        XCTAssertEqual(runner.healthFindings.count, 1)
    }

    /// The console a teacher reads must not show the machine line — checked
    /// with the line ending REAL output uses.
    ///
    /// The filter was written into the plain "\n" branch only, and every test
    /// here supplied "\n", so they all passed while a real build — which comes
    /// from a PTY and ends "\r\n" — showed the teacher a raw JSON blob. Found
    /// by reading the app's own saved transcript after driving it.
    func testTheMachineLineIsHiddenWithCarriageReturnedLineEndings() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("⚠️  The Media folder is not there.\r\n")
        runner.receiveOutput(mediaLine + "\r\n")
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains("PLANTOIR_HEALTH"), shown)
        XCTAssertTrue(shown.contains("The Media folder is not there."))
        XCTAssertEqual(runner.healthFindings.count, 1,
                       "and it must still have been READ before being hidden")
    }

    /// The bug that got all the way to a running app: Swift folds "\r\n" into
    /// ONE Character, so `split(separator: "\n")` never splits PTY output.
    ///
    /// A marker line then arrives glued to its neighbours — the text CONTAINS
    /// the prefix but does not START with it — and every finding is dropped.
    /// Every test here passed because they all used "\n". This one feeds a
    /// realistic multi-line chunk the way a build actually sends it.
    func testFindingsSurviveARealisticChunkOfPTYOutput() {
        let chunk: String = [
            "  📁 Copied per-section folder: All Classes",
            "",
            "📥 Copying per-section files...",
            curriculumLine,
            mediaLine,
            "🗺️  Curriculum Coverage: 50 expectations",
        ].joined(separator: "\r\n") + "\r\n"

        let found: [SiteHealthFinding] = SiteHealthFinding.findings(in: chunk)
        XCTAssertEqual(found.count, 2, "both findings must survive \\r\\n output")

        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(chunk)
        XCTAssertEqual(runner.healthFindings.count, 2)
        XCTAssertFalse(runner.transcript.displayText.contains("PLANTOIR_HEALTH"),
                       "and the machine lines stay out of what a teacher reads")
    }

    func testOrdinaryOutputCarriesNoFindings() {
        XCTAssertTrue(SiteHealthFinding.findings(in: """
        📁 Shared folders to include for 'Section 1':
         - Concepts
        🚀 Launching Quartz preview on http://localhost:8081
        """).isEmpty)
    }

    func testAMalformedLineIsIgnoredRatherThanCrashing() {
        XCTAssertTrue(SiteHealthFinding.findings(in: "PLANTOIR_HEALTH: {not json").isEmpty)
        XCTAssertTrue(SiteHealthFinding.findings(in: "PLANTOIR_HEALTH:").isEmpty)
        XCTAssertTrue(SiteHealthFinding.findings(in:
            #"PLANTOIR_HEALTH: {"detail": "no name and no sentence"}"#).isEmpty)
    }

    /// The bug this design exists to avoid.
    ///
    /// Every other structured-line reader in `ScriptRunner` works from
    /// `transcript.recentText(maximumCharacters: 8000)`, which is a TAIL. The
    /// health lines are printed in the middle of a build, so on a real build
    /// they are far outside that window by the end. Collecting as output
    /// arrives is what makes them survive.
    func testAFindingSurvivesABuildThatKeepsTalkingAfterwards() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(curriculumLine + "\n")
        for index in 0..<400 {
            runner.receiveOutput("  📄 Copied page number \(index) into the site\n")
        }
        XCTAssertEqual(runner.healthFindings.count, 1,
                       "a finding printed early must still be known at the end of a long build")
        XCTAssertEqual(runner.healthFindings.first?.name, "curriculumCoverageFoundNothing")
    }

    /// A marker line split across two PTY reads.
    ///
    /// Output arrives in chunks, not lines, and the health payload is the
    /// LONGEST line a build prints, so it is the likeliest of all to straddle a
    /// read boundary. Before the carry-over buffer, the two halves failed both
    /// the prefix test and the JSON parse and the finding vanished — no dialog,
    /// no answer, no trail line.
    func testAFindingSplitAcrossTwoReadsIsStillFound() {
        let whole: String = curriculumLine + "\n"
        let cut: String.Index = whole.index(whole.startIndex, offsetBy: whole.count / 2)
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(String(whole[whole.startIndex..<cut]))
        XCTAssertTrue(runner.healthFindings.isEmpty, "half a line is not a finding yet")
        runner.receiveOutput(String(whole[cut...]))
        XCTAssertEqual(runner.healthFindings.count, 1,
                       "the two halves must be read as one line")
    }

    /// And one printed as the very LAST output, with no trailing newline.
    ///
    /// The carry-over buffer is only drained by a later chunk containing a
    /// newline, so without a flush at the end of the run this finding was still
    /// lost — the same failure, moved to the end of the build.
    func testAFindingOnTheFinalUnterminatedLineIsStillFound() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("Copying shared folders\n")
        runner.receiveOutput(curriculumLine)   // no trailing newline
        XCTAssertTrue(runner.healthFindings.isEmpty)
        runner.simulateFinishForTesting(exitCode: 0)
        XCTAssertEqual(runner.healthFindings.count, 1,
                       "a finding printed last must survive the end of the run")
    }

    /// A deploy runs `preview.sh --build-only` and then `deploy.sh` on the SAME
    /// runner, keeping the transcript — and only the build phase announces
    /// health. Clearing findings unconditionally emptied the array between the
    /// two, so a deploy threw away the findings it had just collected.
    func testADeploysSecondPhaseKeepsTheBuildsFindings() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(curriculumLine + "\n")
        XCTAssertEqual(runner.healthFindings.count, 1)

        runner.prepareForContinuationForTesting(keepingTranscript: true)
        XCTAssertEqual(runner.healthFindings.count, 1,
                       "the deploy phase must not discard what the build found")

        runner.prepareForContinuationForTesting(keepingTranscript: false)
        XCTAssertTrue(runner.healthFindings.isEmpty,
                      "a genuinely new run starts clean")
    }

    func testTheSameFindingTwiceIsRememberedOnce() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(curriculumLine + "\n")
        runner.receiveOutput(curriculumLine + "\n")
        XCTAssertEqual(runner.healthFindings.count, 1)
    }

    func testSeveralFindingsAreAllKept() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(curriculumLine + "\n" + mediaLine + "\n")
        XCTAssertEqual(runner.healthFindings.count, 2)
        XCTAssertEqual(runner.healthFindings.last?.fixable, true)
    }

    /// Rule 1: the interface never names the machinery, and a raw JSON blob is
    /// machinery. The teacher-facing sentence is printed separately by the
    /// toolchain, so nothing is lost by hiding this.
    func testTheMachineLineNeverReachesWhatATeacherReads() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("⚠️  The Media folder for ICS3U is not there.\n")
        runner.receiveOutput(mediaLine + "\n")
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains("PLANTOIR_HEALTH"), shown)
        XCTAssertFalse(shown.contains("\"fixable\""), shown)
        XCTAssertTrue(shown.contains("The Media folder for ICS3U is not there."),
                      "the sentence a teacher reads must survive")
        XCTAssertEqual(runner.healthFindings.count, 1,
                       "hiding the line must not stop the app from reading it")
    }

    func testEveryFindingReachesTheActivityTrail() {
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("health-trail-\(UUID().uuidString)")
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = store
        defer { ActivityTrail.store = previous }

        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(curriculumLine + "\n")

        let trail: String = store.activityText(includingPrompts: false)
        XCTAssertTrue(trail.contains("found a problem with this course's folders"), trail)
        XCTAssertTrue(trail.contains("curriculumCoverageFoundNothing"), trail)
        // The NAME travels, not the wording: a sentence gets reworded, a name
        // is what somebody searching the trail months later can match on.
        XCTAssertFalse(trail.contains("could not be built"), trail)
    }
}

/// The overnight path: a scheduled deploy publishes anyway and leaves what it
/// found for somebody to read when they are next at the machine.
@MainActor
final class ScheduledDeployFolderProblemTests: XCTestCase {

    // MARK: - Functions

    private func markerLine(_ name: String) -> String {
        return """
        PLANTOIR_HEALTH: {"name": "\(name)", "sentence": "Something is wrong.", \
        "detail": "More about it.", "fixable": false, "course": "ICS3U", "section": 1}
        """
    }

    override func tearDown() {
        _ = ScheduledDeploy.takeFolderProblems(courseCode: "ICS3U", sectionNumber: 1)
        super.tearDown()
    }

    func testFindingsAreReadOutOfTheLogAndReportedOnce() throws {
        let log: URL = ScheduledDeploy.logURL(courseCode: "ICS3U", sectionNumber: 1)
        try FileManager.default.createDirectory(
            at: log.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let previousLog: String? = try? String(contentsOf: log, encoding: .utf8)
        defer {
            if let previousLog {
                try? previousLog.write(to: log, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: log)
            }
        }
        try("Deploying ICS3U…\n" + markerLine("mediaFolderMissing") + "\nDeploy complete\n")
            .write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(section: (
            courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS3U", sectionNumber: 1
        ), fromByteOffset: 0)

        let first: [SiteHealthFinding] = ScheduledDeploy.takeFolderProblems(
            courseCode: "ICS3U", sectionNumber: 1
        )
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.name, "mediaFolderMissing")

        // Consumed: reported once, not every time the app opens.
        XCTAssertTrue(ScheduledDeploy.takeFolderProblems(
            courseCode: "ICS3U", sectionNumber: 1
        ).isEmpty)
    }

    func testAProblemPutRightStopsBeingReported() throws {
        let log: URL = ScheduledDeploy.logURL(courseCode: "ICS3U", sectionNumber: 1)
        try FileManager.default.createDirectory(
            at: log.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let previousLog: String? = try? String(contentsOf: log, encoding: .utf8)
        defer {
            if let previousLog {
                try? previousLog.write(to: log, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: log)
            }
        }
        let section = (courseDirectory: URL(fileURLWithPath: "/tmp"),
                       courseCode: "ICS3U", sectionNumber: 1)

        let firstNight: String = markerLine("mediaFolderMissing") + "\n"
        try firstNight.write(to: log, atomically: true, encoding: .utf8)
        ScheduledDeploy.recordFolderProblems(section: section, fromByteOffset: 0)

        // The next night's run is clean — and launchd APPENDS to this log, it
        // never truncates it, so the first night's marker line is still in the
        // file. An earlier version of this test wrote the file fresh, which is
        // not what happens on a real machine, and it hid the bug completely:
        // the whole log was being re-read every night, so a problem the teacher
        // had fixed went on being reported forever.
        let sizeBeforeSecondRun: UInt64 = UInt64(firstNight.utf8.count)
        try (firstNight + "Deploy complete\n").write(to: log, atomically: true, encoding: .utf8)
        ScheduledDeploy.recordFolderProblems(
            section: section, fromByteOffset: sizeBeforeSecondRun
        )

        XCTAssertTrue(
            ScheduledDeploy.takeFolderProblems(courseCode: "ICS3U", sectionNumber: 1).isEmpty,
            "a problem that has been put right must stop being reported"
        )
    }
}
