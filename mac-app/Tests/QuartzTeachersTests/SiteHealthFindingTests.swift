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
