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
            await ScriptRunnerWait(runner).untilTheRunChanges(orAfter: .seconds(60))
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
            await ScriptRunnerWait(runner).untilTheRunChanges(orAfter: .seconds(60))
            woke.fulfill()
        }
        await Task.yield()
        runner.simulateFinishForTesting(exitCode: 1)
        await fulfillment(of: [woke], timeout: 5)
    }

    /// Phase 1 decides on a launch problem (the run never started) and on
    /// the teacher's Stop; each wakes it at once.
    func testTheWaitWakesWhenTheRunCouldNotStart() async {
        let runner: ScriptRunner = ScriptRunner()
        let woke: XCTestExpectation = expectation(description: "woke on the launch problem")
        Task { @MainActor in
            await ScriptRunnerWait(runner).untilTheRunChanges(orAfter: .seconds(60))
            woke.fulfill()
        }
        await Task.yield()
        runner.launchProblem = "a launch problem invented for this test"
        await fulfillment(of: [woke], timeout: 5)
    }

    func testTheWaitWakesWhenTheTeacherStopsIt() async {
        let runner: ScriptRunner = ScriptRunner()
        let woke: XCTestExpectation = expectation(description: "woke on Stop")
        Task { @MainActor in
            await ScriptRunnerWait(runner).untilTheRunChanges(orAfter: .seconds(60))
            woke.fulfill()
        }
        await Task.yield()
        runner.wasStoppedByUser = true
        await fulfillment(of: [woke], timeout: 5)
    }

    /// A wait that ends at its bound keeps its one registration for the
    /// next wait rather than adding another, and the run's next change
    /// releases it.
    func testBoundedWaitsShareOneRegistrationAndAChangeReleasesIt() async {
        let runner: ScriptRunner = ScriptRunner()
        let wait: ScriptRunnerWait = ScriptRunnerWait(runner)
        await wait.untilTheRunChanges(orAfter: .milliseconds(10))
        XCTAssertTrue(wait.registrationIsLive)
        await wait.untilTheRunChanges(orAfter: .milliseconds(10))
        XCTAssertTrue(wait.registrationIsLive, "still the one registration")
        runner.launchProblem = "a change"
        XCTAssertFalse(wait.registrationIsLive, "released by the change it was waiting for")
        let began: Date = Date()
        await wait.untilTheRunChanges(orAfter: .seconds(60))
        XCTAssertLessThan(Date().timeIntervalSince(began), 5, "a change while nobody waited wakes the next wait at once")
    }

    /// Phase 1 waits through the watch, not a sleep.
    func testPhaseOneWaitsOnTheRun() throws {
        let source: String = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("QuartzTeachers/Views/Section/SectionDetailView.swift"),
            encoding: .utf8
        )
        let first: Range<String.Index> = try XCTUnwrap(source.range(of: "// Phase 1:"))
        let second: Range<String.Index> = try XCTUnwrap(source.range(of: "// Phase 2:"))
        let phaseOne: Substring = source[first.upperBound..<second.lowerBound]
        XCTAssertTrue(phaseOne.contains("await runChanges.untilTheRunChanges(orAfter:"))
        XCTAssertTrue(phaseOne.contains("previewRunner.hasAnnouncedQuartzLaunch"))
        XCTAssertFalse(phaseOne.contains("Task.sleep"))
    }

    func testTheWaitEndsAtItsBoundWhenNothingChanges() async {
        let runner: ScriptRunner = ScriptRunner()
        let began: Date = Date()
        await ScriptRunnerWait(runner).untilTheRunChanges(orAfter: .milliseconds(50))
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
