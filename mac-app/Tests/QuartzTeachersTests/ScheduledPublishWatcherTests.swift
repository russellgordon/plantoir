import XCTest
@testable import QuartzTeachers

/// A scheduled run finishing while the teacher is looking at that section must
/// move the counter the section's band and the sidebar's badge both follow.
///
/// **Not one sleep in this file, deliberately.** Every wait is an expectation
/// re-checked when the watcher's own counter moves, and the five-second bound on
/// each is a FAILURE bound rather than a pause: a passing test waits for as long
/// as the kernel takes and no longer. A test that slept for "long enough" would
/// be the thing Russell's rule against timed delays is about, and this file is
/// where such a delay would be most tempting.
///
/// Nothing of the teacher's is touched: every watcher here is made against a
/// temporary folder of its own, and `ScheduledPublishWatcher.shared` — which
/// points at the real Application Support — is never started from a test.
@MainActor
final class ScheduledPublishWatcherTests: XCTestCase {

    // MARK: - Types

    /// Watches the counter on a test's behalf, and fulfils its expectation the
    /// first time the condition holds.
    ///
    /// Its own small class rather than two functions on the test case: the
    /// re-registration has to be done from a `@Sendable` closure, and an
    /// `XCTestCase` cannot be captured by one. It keeps itself alive through
    /// the task it schedules, which is exactly as long as it is needed.
    @MainActor
    private final class CounterWaiter {

        // MARK: - Stored properties

        let watcher: ScheduledPublishWatcher
        let condition: @MainActor () -> Bool
        let waiting: XCTestExpectation

        // MARK: - Initializer

        init(
            watcher: ScheduledPublishWatcher,
            condition: @escaping @MainActor () -> Bool,
            waiting: XCTestExpectation
        ) {
            self.watcher = watcher
            self.condition = condition
            self.waiting = waiting
        }

        // MARK: - Functions

        /// Look now; if the answer is not there yet, look again the next time
        /// the counter moves. `withObservationTracking` reports one change and
        /// then forgets, so each look registers the next.
        func checkNowAndWheneverTheCounterMoves() {
            if condition() {
                waiting.fulfill()
                return
            }
            withObservationTracking {
                _ = watcher.generation
            } onChange: {
                Task { @MainActor in
                    self.checkNowAndWheneverTheCounterMoves()
                }
            }
        }
    }

    // MARK: - Stored properties

    private var home: URL!
    private var watcher: ScheduledPublishWatcher!

    // MARK: - Functions

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("scheduled-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        watcher?.stop()
        watcher = nil
        try? FileManager.default.removeItem(at: home)
        try super.tearDownWithError()
    }

    /// The folder this test's watcher watches.
    private var recordFolder: URL {
        return ScheduledPublishOutcome.directory(inHomeFolder: home)
    }

    /// Start watching, the way the app does at launch.
    private func startWatching() {
        watcher = ScheduledPublishWatcher(folder: recordFolder)
        watcher.start()
    }

    /// What this section's record says, if it can be read at all.
    private func recordForTheFixtureSection() -> ScheduledPublishOutcome.Stopped? {
        return ScheduledPublishOutcome.stopped(inHomeFolder: home, course: "ZZW1O", section: 1)
    }

    /// An expectation that is fulfilled as soon as `condition` holds, re-checked
    /// every time the watcher's counter moves.
    ///
    /// The re-check is driven by the observation itself rather than by a timer,
    /// which is what makes this deterministic. It never asserts an exact number
    /// of bumps: some ways of writing a file produce two events, both of them
    /// honest, and a test that counted them would fail for a reason that is not
    /// a fault.
    private func expectation(
        _ description: String,
        onceTrue condition: @escaping @MainActor () -> Bool
    ) -> XCTestExpectation {
        let waiting: XCTestExpectation = XCTestExpectation(description: description)
        waiting.assertForOverFulfill = false
        let waiter: CounterWaiter = CounterWaiter(
            watcher: watcher, condition: condition, waiting: waiting
        )
        waiter.checkNowAndWheneverTheCounterMoves()
        return waiting
    }

    /// Run a line of shell and wait for it, the way launchd runs the wrapper.
    private func runShell(_ command: String) throws {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    /// Write a record the way the generated wrapper does today: both lines into
    /// a temporary file beside the record folder, then one `mv`.
    ///
    /// The real shell rather than `ScheduledPublishOutcome.recordStopped`,
    /// because Foundation's atomic write is a DIFFERENT shape — it produces two
    /// events in the watched folder, the first of them with no file there at all
    /// — and this suite should exercise what launchd actually runs.
    private func writeRecordTheWayTheWrapperDoes(
        kind: ScheduledPublishOutcome.Kind,
        destination: String
    ) throws {
        let record: URL = ScheduledPublishOutcome.recordURL(
            inHomeFolder: home, course: "ZZW1O", section: 1
        )
        let partial: URL = ScheduledPublishOutcome.partialRecordURL(
            inHomeFolder: home, course: "ZZW1O", section: 1
        )
        try runShell(
            "/bin/mkdir -p '\(recordFolder.path)'; "
            + "/bin/echo '\(kind.rawValue)' > '\(partial.path)'; "
            + "/bin/echo '\(destination)' >> '\(partial.path)'; "
            + "/bin/mv '\(partial.path)' '\(record.path)'"
        )
    }

    // MARK: - A run that finishes while the teacher is looking

    /// The fault issue #216 was opened for.
    func testARecordArrivingMovesTheCounterWithTheWholeRecordThere() async throws {
        startWatching()
        let showsUp: XCTestExpectation = expectation("the finished run reaches the app") {
            return self.recordForTheFixtureSection() != nil
        }
        try writeRecordTheWayTheWrapperDoes(kind: .succeeded, destination: "Netlify")
        await fulfillment(of: [showsUp], timeout: 5)

        let stopped = try XCTUnwrap(recordForTheFixtureSection())
        XCTAssertEqual(stopped.kind, .succeeded)
        XCTAssertEqual(stopped.destination, "Netlify")
    }

    /// **A job scheduled by an OLDER build still shows its notice live.**
    ///
    /// Its wrapper was written to disk when the section was scheduled and is not
    /// rewritten until it is scheduled again, so it still writes its record with
    /// two `echo`s: the first creates the file (one folder event, carrying an
    /// empty file), and the second changes no directory entry at all — measured,
    /// zero folder events for the line that completes the record. The two halves
    /// are run as two separate shells here, with the arrival of the first waited
    /// on in between, so the completing write LANDS AFTER the folder event has
    /// been dealt with. That is the case a folder watch alone can never see, and
    /// the case this test exists for.
    func testARecordWrittenInTwoStepsIsNoticedWhenTheSecondLineLands() async throws {
        startWatching()
        let record: URL = ScheduledPublishOutcome.recordURL(
            inHomeFolder: home, course: "ZZW1O", section: 1
        )

        let halfArrives: XCTestExpectation = expectation("the half-written record is seen") {
            return FileManager.default.fileExists(atPath: record.path)
        }
        try runShell(
            "/bin/mkdir -p '\(recordFolder.path)'; "
            + "/bin/echo 'did not finish' > '\(record.path)'"
        )
        await fulfillment(of: [halfArrives], timeout: 5)
        XCTAssertNil(
            recordForTheFixtureSection(),
            "Half a record must read as no record — the notice would name a destination nobody wrote"
        )

        let finished: XCTestExpectation = expectation("the completing line reaches the app") {
            return self.recordForTheFixtureSection() != nil
        }
        try runShell("/bin/echo 'Netlify' >> '\(record.path)'")
        await fulfillment(of: [finished], timeout: 5)

        let stopped = try XCTUnwrap(recordForTheFixtureSection())
        XCTAssertEqual(stopped.kind, .didNotFinish)
        XCTAssertEqual(stopped.destination, "Netlify")
    }

    /// A record cleared from somewhere else — the Dismiss button in another
    /// window, or a later run that got through — reaches this one too.
    func testClearingARecordMovesTheCounter() async throws {
        try writeRecordTheWayTheWrapperDoes(kind: .neededAnAnswer, destination: "Netlify")
        startWatching()
        XCTAssertNotNil(recordForTheFixtureSection(), "The fixture record should be readable")

        let goesAway: XCTestExpectation = expectation("the cleared record reaches the app") {
            return self.recordForTheFixtureSection() == nil
        }
        ScheduledPublishOutcome.clear(inHomeFolder: home, course: "ZZW1O", section: 1)
        await fulfillment(of: [goesAway], timeout: 5)
    }

    /// The folder does not have to be there already.
    func testTheFolderIsMadeIfItIsNotThereYet() async throws {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: recordFolder.path),
            "This test means nothing if the folder already exists"
        )
        startWatching()
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordFolder.path))

        let showsUp: XCTestExpectation = expectation("a record in the new folder is seen") {
            return self.recordForTheFixtureSection() != nil
        }
        try writeRecordTheWayTheWrapperDoes(kind: .succeeded, destination: "your deploy folder")
        await fulfillment(of: [showsUp], timeout: 5)
    }

    /// A watch is on an open file descriptor, so a folder that is thrown away
    /// and made again leaves the original watch deaf. Measured: a record written
    /// into a recreated folder produces no events at all on the old descriptor,
    /// so re-arming is load-bearing rather than defensive.
    func testAFolderThatIsThrownAwayAndMadeAgainIsStillWatched() async throws {
        startWatching()
        let before: Int = watcher.generation
        // The counter moves for the folder going only once the new watch is
        // armed, which is what lets the record below be written straight
        // afterwards without a sleep to cover the gap.
        let noticesTheFolderGoing: XCTestExpectation = expectation("the folder going is seen") {
            return self.watcher.generation > before
        }
        try runShell("/bin/rm -rf '\(recordFolder.path)'")
        await fulfillment(of: [noticesTheFolderGoing], timeout: 5)

        let showsUp: XCTestExpectation = expectation("a record in the new folder is seen") {
            return self.recordForTheFixtureSection() != nil
        }
        try writeRecordTheWayTheWrapperDoes(kind: .succeeded, destination: "Netlify")
        await fulfillment(of: [showsUp], timeout: 5)
    }

    /// The commonest way a teacher comes back: the app was open all night and
    /// they bring it to the front in the morning.
    func testComingBackToTheFrontLooksAgain() async throws {
        startWatching()
        let before: Int = watcher.generation
        let looksAgain: XCTestExpectation = expectation("coming back to the front looks again") {
            return self.watcher.generation > before
        }
        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
        await fulfillment(of: [looksAgain], timeout: 5)
    }

    /// Dismiss says so itself rather than waiting on the filesystem, which is
    /// what keeps the sidebar's badge and the section's band in step.
    func testSayingSoByHandMovesTheCounter() {
        startWatching()
        let before: Int = watcher.generation
        watcher.noteChanged()
        XCTAssertGreaterThan(watcher.generation, before)
    }
}
