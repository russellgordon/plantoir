import XCTest
@testable import QuartzTeachers

/// The progress header refreshes every second while a task runs. With a
/// long transcript (a deploy uploading hundreds of files), recomputing
/// its labels must stay cheap — otherwise the main thread stalls and the
/// whole window stops drawing.
final class ProgressPerformanceTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func makeRunnerWithLongTranscript(lineCount: Int) -> ScriptRunner {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.deploy
        runner.isRunning = true
        runner.receiveOutput( "Getting this folder's website builder ready…\n")
        for lineNumber in 1...lineCount {
            runner.receiveOutput( "  …uploaded \(lineNumber)/\(lineCount) required files to the site\n")
        }
        return runner
    }

    @MainActor
    func testProgressLabelsStayCheapWithALongTranscript() {
        let runner: ScriptRunner = makeRunnerWithLongTranscript(lineCount: 5000)

        // One refresh of the progress header reads all of these.
        let started: Date = Date()
        for _ in 0..<5 {
            _ = runner.milestonesReached
            _ = runner.progressFraction
            _ = runner.currentMilestoneLabel
            _ = runner.stepDescription
            _ = runner.mayBeWaitingForInput(asOf: Date())
        }
        let elapsed: TimeInterval = Date().timeIntervalSince(started)

        XCTAssertLessThan(
            elapsed,
            0.5,
            "Five progress refreshes took \(elapsed)s with a long transcript — the main thread would stall"
        )
    }

    @MainActor
    func testTranscriptStaysBoundedSoMemoryCannotRunAway() {
        let runner: ScriptRunner = makeRunnerWithLongTranscript(lineCount: 10000)
        XCTAssertLessThanOrEqual(
            runner.transcript.lines.count,
            TranscriptBuilder.maximumRetainedLines,
            "The transcript should keep only its most recent lines"
        )
    }
}
