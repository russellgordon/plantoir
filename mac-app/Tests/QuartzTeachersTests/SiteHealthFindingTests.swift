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
    /// Most other structured-line readers in `ScriptRunner` work from
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

    func testEveryFindingReachesTheActivityTrail() throws {
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("health-trail-\(UUID().uuidString)")
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = store
        defer { ActivityTrail.store = previous }

        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(curriculumLine + "\n")

        let trail: String = store.activityText(includingPrompts: false)
        let finding: SiteHealthFinding = try XCTUnwrap(SiteHealthFinding.findings(in: curriculumLine).first)
        XCTAssertTrue(trail.contains("ICS3U/1 · " + finding.trailSentence), trail)
        XCTAssertTrue(trail.contains("curriculumCoverageFoundNothing"), trail)
        // The NAME travels, not the wording: a sentence gets reworded, a name
        // is what somebody searching the trail months later can match on.
        XCTAssertFalse(trail.contains("could not be built"), trail)
    }

    // MARK: - #153: the console never shows a marker, and never loses one

    /// Something else wrote half a line into the terminal, and the marker was
    /// glued to its tail. Measured against the old code: the raw JSON was
    /// SHOWN and the finding was DROPPED — no dialog, no trail line, and
    /// nothing in the assistant's answer.
    func testAMarkerGluedToAPartialLineIsReadAndHidden() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("Building…")
        runner.receiveOutput(mediaLine + "\r\n")
        runner.receiveOutput("done\r\n")
        XCTAssertEqual(runner.healthFindings.count, 1, "a glued marker must still be read")
        XCTAssertEqual(runner.healthFindings.first?.name, "mediaFolderMissing")
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains(SiteHealthFinding.markerPrefix), shown)
        XCTAssertEqual(shown, "done", "the glued line goes whole, chatter and all")
    }

    /// The health payload is the longest line a build prints, so it is the
    /// likeliest to arrive in two chunks — and until the newline arrived, the
    /// first half was on screen as raw JSON, through BOTH ways of reading the
    /// transcript.
    func testAHalfArrivedMarkerIsNotShownWhileItArrives() {
        var transcript: TranscriptBuilder = TranscriptBuilder()
        transcript.append(rawText: "ok\r\n")
        let cut: String.Index = mediaLine.index(mediaLine.startIndex, offsetBy: 60)
        transcript.append(rawText: String(mediaLine[..<cut]))
        XCTAssertEqual(transcript.displayText, "ok")
        XCTAssertFalse(transcript.recentText(maximumCharacters: 8000).contains(SiteHealthFinding.markerPrefix))
        transcript.append(rawText: String(mediaLine[cut...]) + "\r\n")
        XCTAssertEqual(transcript.displayText, "ok")
        XCTAssertFalse(transcript.recentText(maximumCharacters: 8000).contains(SiteHealthFinding.markerPrefix))
    }

    /// Half a marker cut after `"sentence":` ends in a colon — a question's
    /// shape — so after a quiet spell the prompt check would have offered raw
    /// JSON to the teacher as something to answer.
    func testHalfAMarkerIsNeverAQuestion() {
        let cut: String.Index = mediaLine.index(mediaLine.startIndex, offsetBy: 60)
        let half: String = String(mediaLine[..<cut]).trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(half.hasSuffix(":"), half)
        XCTAssertFalse(ScriptRunner.looksLikeQuestion(half))
        XCTAssertFalse(ScriptRunner.looksLikeQuestion("PLANTOIR_DATED: {\"course\":"))
        XCTAssertTrue(ScriptRunner.looksLikeQuestion("Enter Netlify site name:"), "real prompts still ask")
    }

    /// The trail sentence is the one the contract writes down — read out of
    /// `activityTrail.mustRecord` → "folder problem found" → `carries`, not
    /// retyped here. The mac wrote a straight apostrophe where the contract
    /// and Windows both write a curly one.
    func testTheTrailSentenceIsTheContractsOwn() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let trail: [String: Any] = try XCTUnwrap(all["activityTrail"] as? [String: Any])
        let events: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        var carries: String = ""
        for event in events {
            if (event["event"] as? String) == ActivityTrail.Event.folderProblemFound.rawValue {
                carries = try XCTUnwrap(event["carries"] as? String)
            }
        }
        let pieces: [String] = carries.components(separatedBy: "'")
        XCTAssertEqual(pieces.count, 3,
                       "carries must hold exactly two ASCII quotes around its example, or this reads the wrong span: \(carries)")
        guard pieces.count == 3 else {
            return
        }
        let example: String = pieces[1]

        let finding: SiteHealthFinding = SiteHealthFinding(
            name: "curriculumCoverageFoundNothing", sentence: "", detail: "",
            fixable: false, course: "ICS3U", section: 1
        )
        XCTAssertEqual(finding.trailSentence, example)
    }

    /// Item 3 of #153, checked rather than asserted: the assistant (and
    /// `Plantoir --mcp-stdio`) builds its answer from the findings, never from
    /// the console — so a glued finding reaches the answer, and no machinery
    /// does.
    func testTheAssistantsAnswerCarriesAGluedFindingAndNoMachinery() throws {
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("health-trail-\(UUID().uuidString)")
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = store
        defer {
            ActivityTrail.store = previous
            try? FileManager.default.removeItem(at: folderURL)
        }

        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("Building…")
        runner.receiveOutput(mediaLine + "\r\n")
        runner.receiveOutput("done\r\n")

        let answer: String = SiteHealthFinding.appending(to: "Done.", from: runner)
        XCTAssertTrue(answer.contains("The Media folder for ICS3U is not there."), answer)
        XCTAssertFalse(answer.contains(SiteHealthFinding.markerPrefix), answer)
        XCTAssertFalse(answer.contains("\"fixable\""), answer)

        let trail: String = store.activityText(includingPrompts: false)
        XCTAssertTrue(trail.contains("(mediaFolderMissing)"), trail)
    }
}

/// The overnight path: a scheduled deploy publishes anyway and leaves what it
/// found for somebody to read when they are next at the machine.
///
/// Every call names a throwaway home. The course is `ICS3U` section 1 — "a
/// course a teacher plausibly has" — so before issue #240 these tests deleted
/// the real `~/Library/Application Support/Plantoir/scheduled/…findings` file
/// of whoever ran the suite, and wrote (then restored) the real log.
@MainActor
final class ScheduledDeployFolderProblemTests: XCTestCase {

    // MARK: - Stored properties

    private var homeFolderURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Set-up

    override func setUpWithError() throws {
        homeFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder-problems-home-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: homeFolderURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: homeFolderURL)
    }

    // MARK: - Functions

    private func markerLine(_ name: String) -> String {
        return """
        PLANTOIR_HEALTH: {"name": "\(name)", "sentence": "Something is wrong.", \
        "detail": "More about it.", "fixable": false, "course": "ICS3U", "section": 1}
        """
    }

    private func writableLogURL() throws -> URL {
        let log: URL = ScheduledDeploy.logURL(courseCode: "ICS3U", sectionNumber: 1, inHomeFolder: homeFolderURL)
        try FileManager.default.createDirectory(
            at: log.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return log
    }

    func testFindingsAreReadOutOfTheLogAndReportedOnce() throws {
        let log: URL = try writableLogURL()
        try("Deploying ICS3U…\n" + markerLine("mediaFolderMissing") + "\nDeploy complete\n")
            .write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(section: (
            courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS3U", sectionNumber: 1
        ), fromByteOffset: 0, inHomeFolder: homeFolderURL)

        let first: [SiteHealthFinding] = ScheduledDeploy.takeFolderProblems(
            courseCode: "ICS3U", sectionNumber: 1, inHomeFolder: homeFolderURL
        )
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.name, "mediaFolderMissing")

        // Consumed: reported once, not every time the app opens.
        XCTAssertTrue(ScheduledDeploy.takeFolderProblems(
            courseCode: "ICS3U", sectionNumber: 1, inHomeFolder: homeFolderURL
        ).isEmpty)
    }

    /// The overnight path leaves its own trail line (#153). Before, a
    /// scheduled run's findings reached the trail only if somebody later
    /// opened the section — and even then nothing noted them — so the path
    /// the check exists for left no line at all.
    func testAScheduledRunLeavesTheTrailLineItself() throws {
        let folderURL: URL = homeFolderURL.appendingPathComponent("trail", isDirectory: true)
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = store
        defer { ActivityTrail.store = previous }

        let log: URL = try writableLogURL()
        let lastNight: String = markerLine("sectionIndexMissing") + "\n"
        let tonight: String = "Deploying ICS3U…\n"
            + markerLine("mediaFolderMissing") + "\n"
            + markerLine("curriculumCoverageFoundNothing") + "\n"
            + markerLine("mediaFolderMissing") + "\n"
            + "Deploy complete\n"
        try (lastNight + tonight).write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(section: (
            courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS3U", sectionNumber: 1
        ), fromByteOffset: UInt64(lastNight.utf8.count), inHomeFolder: homeFolderURL)

        let media: SiteHealthFinding = try XCTUnwrap(
            SiteHealthFinding.findings(in: markerLine("mediaFolderMissing")).first
        )
        let curriculum: SiteHealthFinding = try XCTUnwrap(
            SiteHealthFinding.findings(in: markerLine("curriculumCoverageFoundNothing")).first
        )
        let trail: String = store.activityText(includingPrompts: false)
        XCTAssertEqual(trail.components(separatedBy: "ICS3U/1 · " + media.trailSentence).count - 1, 1,
                       "one line per DISTINCT finding: \(trail)")
        XCTAssertEqual(trail.components(separatedBy: "ICS3U/1 · " + curriculum.trailSentence).count - 1, 1, trail)
        XCTAssertFalse(trail.contains("sectionIndexMissing"), "an earlier night's finding was noted again")

        // Reading the record when the section is opened notes nothing more:
        // one run's finding is one line, whether or not anybody looks.
        let linesBefore: Int = trail.components(separatedBy: "\n").count
        let taken: [SiteHealthFinding] = ScheduledDeploy.takeFolderProblems(
            courseCode: "ICS3U", sectionNumber: 1, inHomeFolder: homeFolderURL
        )
        XCTAssertEqual(taken.count, 2, "a finding printed twice is kept once, so the dialog lists it once")
        let linesAfter: Int = store.activityText(includingPrompts: false).components(separatedBy: "\n").count
        XCTAssertEqual(linesAfter, linesBefore)
    }

    func testAProblemPutRightStopsBeingReported() throws {
        let log: URL = try writableLogURL()
        let section = (courseDirectory: URL(fileURLWithPath: "/tmp"),
                       courseCode: "ICS3U", sectionNumber: 1)

        let firstNight: String = markerLine("mediaFolderMissing") + "\n"
        try firstNight.write(to: log, atomically: true, encoding: .utf8)
        ScheduledDeploy.recordFolderProblems(section: section, fromByteOffset: 0, inHomeFolder: homeFolderURL)

        // The next night's run is clean — and launchd APPENDS to this log, it
        // never truncates it, so the first night's marker line is still in the
        // file. An earlier version of this test wrote the file fresh, which is
        // not what happens on a real machine, and it hid the bug completely:
        // the whole log was being re-read every night, so a problem the teacher
        // had fixed went on being reported forever.
        let sizeBeforeSecondRun: UInt64 = UInt64(firstNight.utf8.count)
        try (firstNight + "Deploy complete\n").write(to: log, atomically: true, encoding: .utf8)
        ScheduledDeploy.recordFolderProblems(
            section: section, fromByteOffset: sizeBeforeSecondRun, inHomeFolder: homeFolderURL
        )

        XCTAssertTrue(
            ScheduledDeploy.takeFolderProblems(
                courseCode: "ICS3U", sectionNumber: 1, inHomeFolder: homeFolderURL
            ).isEmpty,
            "a problem that has been put right must stop being reported"
        )
    }
}
