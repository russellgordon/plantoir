import XCTest
@testable import QuartzTeachers

/// The preview's wait for its server waits on what it is waiting for (#998):
/// the run's own state, read as it changes, and for the one late reload the
/// build landing, not a guessed 900 ms.
@MainActor
final class PreviewWaitDependencyTests: XCTestCase {

    // MARK: - Functions

    // MARK: - The launch line, collected as it arrives

    func testTheLaunchLineIsNotedAsItArrivesEvenWhenSplitAcrossChunks() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("Building...\n🚀 Launching Quartz ")
        XCTAssertFalse(runner.hasAnnouncedQuartzLaunch, "half a line is not the line")
        runner.receiveOutput("preview on http://localhost:8081\n")
        XCTAssertTrue(runner.hasAnnouncedQuartzLaunch)
    }

    func testTheWordsMatchWhatTheBuilderPrints() throws {
        let script: String = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("scripts/build_site.py"),
            encoding: .utf8
        )
        XCTAssertTrue(script.contains(ScriptRunner.quartzLaunchLine + " on http://localhost:"))
    }

    func testANewRunForgetsThePreviousRunsLaunchLine() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("🚀 Launching Quartz preview on http://localhost:8081\n")
        XCTAssertTrue(runner.hasAnnouncedQuartzLaunch)
        runner.prepareForContinuationForTesting(keepingTranscript: false)
        XCTAssertFalse(runner.hasAnnouncedQuartzLaunch)
    }

    // MARK: - Waiting for the run to change

    /// The wait wakes on the change, long before its bound. Under the old
    /// one-second sleep this could not be told apart from a slow machine;
    /// with a bound of a minute, a wait that only woke at its bound fails
    /// the five-second expectation.
    func testTheWaitWakesWhenTheRunSaysItsServerIsLaunching() async {
        let runner: ScriptRunner = ScriptRunner()
        let woke: XCTestExpectation = expectation(description: "woke on the change")
        Task { @MainActor in
            await ScriptRunnerWait.untilTheRunChanges(runner, orAfter: .seconds(60))
            woke.fulfill()
        }
        await Task.yield()
        runner.receiveOutput("🚀 Launching Quartz preview on http://localhost:8081\n")
        await fulfillment(of: [woke], timeout: 5)
        XCTAssertTrue(runner.hasAnnouncedQuartzLaunch)
    }

    func testTheWaitWakesWhenTheRunEnds() async {
        let runner: ScriptRunner = ScriptRunner()
        runner.isRunning = true
        let woke: XCTestExpectation = expectation(description: "woke on the end")
        Task { @MainActor in
            await ScriptRunnerWait.untilTheRunChanges(runner, orAfter: .seconds(60))
            woke.fulfill()
        }
        await Task.yield()
        runner.simulateFinishForTesting(exitCode: 1)
        await fulfillment(of: [woke], timeout: 5)
    }

    func testTheWaitEndsAtItsBoundWhenNothingChanges() async {
        let runner: ScriptRunner = ScriptRunner()
        let began: Date = Date()
        await ScriptRunnerWait.untilTheRunChanges(runner, orAfter: .milliseconds(50))
        XCTAssertLessThan(Date().timeIntervalSince(began), 5)
    }

    // MARK: - The late build's reload

    /// The race the 900 ms reload lost: the build lands on the third reading,
    /// later than any fixed delay chosen in advance. The reload must wait for
    /// it, and must not come before it.
    func testTheLateReloadComesWhenTheBuildLandsAndNotBefore() async {
        let before: Date = Date(timeIntervalSince1970: 1_000)
        let landed: Date = Date(timeIntervalSince1970: 2_000)
        var readings: [Date?] = [before, before, landed]
        var readingsTaken: Int = 0
        var pauses: Int = 0
        let shouldReload: Bool = await PreviewLateBuild.waitForTheBuildToLand(
            siteAsItWas: before,
            whenWritten: {
                readingsTaken += 1
                return readings.removeFirst()
            },
            theRunIsStillTheOne: {
                return true
            },
            limit: 600,
            pause: {
                pauses += 1
            }
        )
        XCTAssertTrue(shouldReload)
        XCTAssertEqual(readingsTaken, 3, "read until the build landed")
        XCTAssertEqual(pauses, 2)
    }

    func testAFirstEverBuildLandingCounts() async {
        let shouldReload: Bool = await PreviewLateBuild.waitForTheBuildToLand(
            siteAsItWas: nil,
            whenWritten: {
                return Date(timeIntervalSince1970: 2_000)
            },
            theRunIsStillTheOne: {
                return true
            },
            limit: 600,
            pause: {
            }
        )
        XCTAssertTrue(shouldReload)
    }

    func testNoReloadForARunThatEndedOrWasReplacedFirst() async {
        let before: Date = Date(timeIntervalSince1970: 1_000)
        var stillTheOne: Bool = true
        let shouldReload: Bool = await PreviewLateBuild.waitForTheBuildToLand(
            siteAsItWas: before,
            whenWritten: {
                return before
            },
            theRunIsStillTheOne: {
                return stillTheOne
            },
            limit: 600,
            pause: {
                stillTheOne = false
            }
        )
        XCTAssertFalse(shouldReload)
    }

    func testNoReloadOnceTheLimitHasPassed() async {
        let before: Date = Date(timeIntervalSince1970: 1_000)
        var clock: Date = Date(timeIntervalSince1970: 0)
        let shouldReload: Bool = await PreviewLateBuild.waitForTheBuildToLand(
            siteAsItWas: before,
            whenWritten: {
                return before
            },
            theRunIsStillTheOne: {
                return true
            },
            limit: 600,
            now: {
                return clock
            },
            pause: {
                clock = clock.addingTimeInterval(1)
            }
        )
        XCTAssertFalse(shouldReload)
        XCTAssertEqual(clock.timeIntervalSince1970, 600, accuracy: 0.001)
    }

    /// The guess is gone from the view.
    func testThePreviewWaitHasNoGuessedReloadDelay() throws {
        let source: String = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("QuartzTeachers/Views/Section/SectionDetailView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains(".milliseconds(900)"))
        XCTAssertFalse(source.contains("displayText.contains(\"Launching Quartz preview\")"))
    }
}
