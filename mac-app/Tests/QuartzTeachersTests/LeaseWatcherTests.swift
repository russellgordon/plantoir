import Darwin
import Observation
import XCTest
@testable import QuartzTeachers

/// Deploy greys and un-greys while another program holds the course (GitHub
/// #729): `contracts/shared-rules.json` → `returningToASectionMidDeploy
/// .heldElsewhere`, walked here as data against the REAL `LeaseWatcher` on
/// real files, with real processes as the other programs.
///
/// A holder is a `/bin/sleep` this test starts, and its lease is written the
/// way a lease is (`Data.write(.atomic)`), with the name and start time the
/// process table reports for it, so `ProcessLiveness` reads it as alive.
/// Every wait is on the watcher's `generation` with a deadline that FAILS the
/// test, never a sleep that waits for success.
///
/// Serial with the other classes that reset process-wide statics
/// (`SectionRuns`, `CourseActivity`): the scheme runs classes one at a time.
@MainActor
final class LeaseWatcherTests: XCTestCase {

    // MARK: - Stored properties

    /// The holders this test started, ended in tear down.
    private var holders: [Process] = []

    /// How long an event may take before the test fails. The measured worst
    /// was 0.03 s under load (W6); this is the test's limit, not the app's.
    private let deadline: TimeInterval = 5

    // MARK: - Set up

    override func setUp() async throws {
        SectionRuns.shared.reset()
        CourseActivity.reset()
    }

    override func tearDown() async throws {
        for holder in holders where holder.isRunning {
            kill(holder.processIdentifier, SIGKILL)
            holder.waitUntilExit()
        }
        holders = []
        SectionRuns.shared.reset()
        CourseActivity.reset()
    }

    // MARK: - The contract's cases

    /// Every `heldElsewhere` case: the leases laid out, the watcher started,
    /// Deploy's availability and help asked the way the view asks them, then
    /// what happens next, with nobody touching anything.
    func testEveryHeldElsewhereCase() async throws {
        let section: [String: Any] = try SharedRulesContractTests.section("returningToASectionMidDeploy")
        let heldElsewhere: [String: Any] = try XCTUnwrap(section["heldElsewhere"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(heldElsewhere["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 13)
        for testCase in cases {
            try await runHeldElsewhereCase(testCase)
        }
    }

    /// One case.
    private func runHeldElsewhereCase(_ testCase: [String: Any]) async throws {
        let name: String = try XCTUnwrap(testCase["name"] as? String)
        SectionRuns.shared.reset()
        CourseActivity.reset()
        let folder: URL = try makeWorkingFolder()
        let anotherFolder: URL = try makeWorkingFolder()
        let courses: URL = folder.appendingPathComponent("courses", isDirectory: true)
        let watcher: LeaseWatcher = LeaseWatcher(coursesDirectory: courses)
        defer {
            watcher.stop()
        }

        var leases: [URL] = []
        var livingHolders: [Process] = []
        for hold in try XCTUnwrap(testCase["holds"] as? [[String: Any]], name) {
            let kind: String = try XCTUnwrap(hold["kind"] as? String)
            let course: String = try XCTUnwrap(hold["course"] as? String)
            let holder: String = try XCTUnwrap(hold["holder"] as? String)
            let folderWord: String = try XCTUnwrap(hold["folder"] as? String)
            let into: URL = folderWord == "this" ? courses : anotherFolder.appendingPathComponent("courses")
            switch holder {
            case "another":
                let process: Process = try startAHolder()
                livingHolders.append(process)
                leases.append(try writeLease(kind: kind, course: course, for: process.processIdentifier, into: into))
            case "gone":
                leases.append(try writeLease(kind: kind, course: course, for: try aProcessThatHasEnded(), into: into))
            case "this":
                let written = WorkLeaseFiles.write(kind: kind, courseCode: course, coursesDirectory: into)
                leases.append(try XCTUnwrap(written, name).url)
            default:
                XCTFail("\(name): a holder this test does not know: \(holder)")
            }
        }

        watcher.start()
        let sectionNumber: Int = (testCase["section"] as? String) == "sibling" ? 2 : 1
        let folderReady: Bool = try XCTUnwrap(testCase["folderReady"] as? Bool, name)
        let readinessReason: String? = folderReady ? nil : "The folder is still getting ready."

        if (testCase["button"] as? String) == "none" {
            // Unchanged by #729: no button is drawn on a course kept for
            // reference, and the menu's Deploy… asks the same.
            XCTAssertEqual(testCase["keptForReference"] as? Bool, true, name)
            let view: String = try readSource("QuartzTeachers/Views/Section/SectionDetailView.swift")
            XCTAssertTrue(view.contains("if !course.isKeptForReference {\n                    Button(\"Deploy\""), name)
            XCTAssertTrue(view.contains("deployButtonEnabled: deployButtonIsEnabled && !course.isKeptForReference"), name)
            return
        }

        let expectedBefore: Bool = try XCTUnwrap(testCase["deployAvailable"] as? Bool, name)
        XCTAssertEqual(
            availability(watcher: watcher, folder: folder, section: sectionNumber, folderReady: folderReady),
            expectedBefore, "\(name): Deploy before anything happens"
        )
        let help: String = SectionDetailView.deployHelp(
            folderReadinessReason: readinessReason,
            heldElsewhere: watcher.holding(forCourse: "EXC2O") != nil,
            courseCode: "EXC2O"
        )
        switch try XCTUnwrap(testCase["help"] as? String, name) {
        case "heldElsewhere":
            XCTAssertEqual(help, try contractHelp(course: "EXC2O"), name)
        case "folderReadinessReason":
            XCTAssertEqual(help, readinessReason, name)
        case "ordinary":
            XCTAssertEqual(help, SectionDetailView.deployOrdinaryHelp, name)
        default:
            XCTFail("\(name): a help this test does not know")
        }

        let then: String = try XCTUnwrap(testCase["then"] as? String, name)
        if then == "nothing" {
            return
        }
        let expectedAfter: Bool = try XCTUnwrap(testCase["afterThen"] as? Bool, name)
        switch then {
        case "theHolderRemovesItsLease":
            for lease in leases {
                try FileManager.default.removeItem(at: lease)
            }
        case "theHolderIsKilled":
            for process in livingHolders {
                kill(process.processIdentifier, SIGKILL)
            }
            for lease in leases {
                XCTAssertTrue(FileManager.default.fileExists(atPath: lease.path), "\(name): the lease must stay")
            }
        default:
            XCTFail("\(name): a then this test does not know: \(then)")
        }
        let moved: Bool = await waitUntil(watcher) {
            self.availability(watcher: watcher, folder: folder, section: sectionNumber, folderReady: folderReady)
                == expectedAfter
        }
        XCTAssertTrue(moved, "\(name): Deploy must become available again with no click, within \(deadline) s")
    }

    // MARK: - Events, one at a time

    /// A killed holder leaves its lease and no file event follows: the
    /// holder's process ending is what un-greys Deploy. Without the process
    /// watch this times out, which is the stuck grey #729 must never have.
    func testAKilledHolderUngreysDeployWithNoFileEvent() async throws {
        let folder: URL = try makeWorkingFolder()
        let courses: URL = folder.appendingPathComponent("courses", isDirectory: true)
        let holder: Process = try startAHolder()
        try writeLease(kind: "publish", course: "EXC2O", for: holder.processIdentifier, into: courses)
        let watcher: LeaseWatcher = LeaseWatcher(coursesDirectory: courses)
        watcher.start()
        defer {
            watcher.stop()
        }
        XCTAssertNotNil(watcher.holding(forCourse: "EXC2O"))
        XCTAssertEqual(watcher.holderWatchCount, 1)
        let eventsBefore: Int = watcher.folderEvents
        kill(holder.processIdentifier, SIGKILL)
        let cleared: Bool = await waitUntil(watcher) {
            watcher.holding(forCourse: "EXC2O") == nil
        }
        XCTAssertTrue(cleared, "a killed holder must un-grey Deploy within \(deadline) s")
        XCTAssertEqual(watcher.folderEvents, eventsBefore, "no file event came: the process ending did it")
        XCTAssertEqual(watcher.holderWatchCount, 0)
    }

    /// A lease written and removed is seen both ways by the folder watch.
    func testALeaseWrittenAndRemovedIsSeenBothWays() async throws {
        let folder: URL = try makeWorkingFolder()
        let courses: URL = folder.appendingPathComponent("courses", isDirectory: true)
        let watcher: LeaseWatcher = LeaseWatcher(coursesDirectory: courses)
        watcher.start()
        defer {
            watcher.stop()
        }
        XCTAssertNil(watcher.holding(forCourse: "EXC2O"))
        let holder: Process = try startAHolder()
        let lease: URL = try writeLease(kind: "build", course: "exc2o", for: holder.processIdentifier, into: courses)
        let held: Bool = await waitUntil(watcher) {
            watcher.holding(forCourse: "EXC2O")?.pid == holder.processIdentifier
        }
        XCTAssertTrue(held, "a lease written with Data.write(.atomic) must be seen")
        try FileManager.default.removeItem(at: lease)
        let cleared: Bool = await waitUntil(watcher) {
            watcher.holding(forCourse: "EXC2O") == nil
        }
        XCTAssertTrue(cleared, "a lease removed must be seen")
    }

    /// No activity folder at the start (nor `.internal`): the folder above
    /// is watched, and the first lease, which makes both, is still seen.
    /// Nothing is created by the watcher itself.
    func testTheWatchMovesDownWhenTheActivityFolderAppears() async throws {
        let folder: URL = try makeWorkingFolder()
        let courses: URL = folder.appendingPathComponent("courses", isDirectory: true)
        try FileManager.default.removeItem(at: courses.appendingPathComponent(".internal"))
        let watcher: LeaseWatcher = LeaseWatcher(coursesDirectory: courses)
        watcher.start()
        defer {
            watcher.stop()
        }
        XCTAssertTrue(watcher.folderIsWatched, "courses/ is watched while the activity folder does not exist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: courses.appendingPathComponent(".internal").path),
                       "the watcher creates nothing")
        let holder: Process = try startAHolder()
        try writeLease(kind: "build", course: "EXC2O", for: holder.processIdentifier, into: courses)
        let held: Bool = await waitUntil(watcher) {
            watcher.holding(forCourse: "EXC2O") != nil
        }
        XCTAssertTrue(held)
    }

    // MARK: - The order the folders appear in (#729 implementation review, M-b1)

    /// `.internal` made ALONE first (a deploy's token record, a rename's
    /// record), and only later the activity folder, by the first lease. The
    /// first build of `LeaseWatcher` stayed on `courses/` and heard nothing
    /// inside `.internal` for the rest of the session (measured 0 of 20).
    func testInternalMadeAloneFirstThenALease() async throws {
        let (courses, watcher) = try startedWithNoInternalFolder()
        defer {
            watcher.stop()
        }
        let before: Int = watcher.folderEvents
        try FileManager.default.createDirectory(
            at: courses.appendingPathComponent(".internal/tokens"), withIntermediateDirectories: true
        )
        await waitForAFolderEvent(watcher, after: before)
        try await expectALeaseToBeSeen(in: courses, by: watcher, "`.internal` first, then the activity folder")
    }

    /// Both made at once by the first lease (W5's shape). Passed before the
    /// fix too: the activity folder was already there at the event.
    func testInternalAndTheActivityFolderMadeTogether() async throws {
        let (courses, watcher) = try startedWithNoInternalFolder()
        defer {
            watcher.stop()
        }
        try await expectALeaseToBeSeen(in: courses, by: watcher, "both made together")
    }

    /// `.internal` removed while its activity folder is watched, made again
    /// alone, then a lease (a course restore, or a tidy of `.internal`). The
    /// first build stayed on `courses/` here too.
    func testInternalRemovedThenMadeAgainAloneThenALease() async throws {
        let folder: URL = try makeWorkingFolder()
        let courses: URL = folder.appendingPathComponent("courses", isDirectory: true)
        let watcher: LeaseWatcher = LeaseWatcher(coursesDirectory: courses)
        watcher.start()
        defer {
            watcher.stop()
        }
        var before: Int = watcher.folderEvents
        try FileManager.default.removeItem(at: courses.appendingPathComponent(".internal"))
        await waitForAFolderEvent(watcher, after: before)
        before = watcher.folderEvents
        try FileManager.default.createDirectory(
            at: courses.appendingPathComponent(".internal"), withIntermediateDirectories: true
        )
        await waitForAFolderEvent(watcher, after: before)
        try await expectALeaseToBeSeen(in: courses, by: watcher, "`.internal` removed, then made again alone")
    }

    /// Only the activity folder removed and made again by a lease. Passed
    /// before the fix too: the watch moved to `.internal`, which saw it come
    /// back.
    func testTheActivityFolderRemovedThenMadeAgain() async throws {
        let folder: URL = try makeWorkingFolder()
        let courses: URL = folder.appendingPathComponent("courses", isDirectory: true)
        let watcher: LeaseWatcher = LeaseWatcher(coursesDirectory: courses)
        watcher.start()
        defer {
            watcher.stop()
        }
        let before: Int = watcher.folderEvents
        try FileManager.default.removeItem(at: WorkLeaseFiles.activityDirectory(coursesDirectory: courses))
        await waitForAFolderEvent(watcher, after: before)
        try await expectALeaseToBeSeen(in: courses, by: watcher, "the activity folder removed and made again")
    }

    /// `.internal` renamed away while watched, a lease written into a new
    /// one, then that one removed and the first renamed back with a lease in
    /// it. A watch is on an open folder, not a path: the first build kept
    /// watching the renamed folder and heard nothing at the path.
    func testInternalRenamedAwayAndBack() async throws {
        let folder: URL = try makeWorkingFolder()
        let courses: URL = folder.appendingPathComponent("courses", isDirectory: true)
        let internalFolder: URL = courses.appendingPathComponent(".internal")
        let away: URL = courses.appendingPathComponent(".internal-away")
        let watcher: LeaseWatcher = LeaseWatcher(coursesDirectory: courses)
        watcher.start()
        defer {
            watcher.stop()
        }
        var before: Int = watcher.folderEvents
        try FileManager.default.moveItem(at: internalFolder, to: away)
        await waitForAFolderEvent(watcher, after: before)
        let lease: URL = try await expectALeaseToBeSeen(in: courses, by: watcher, "a new `.internal` after a rename")
        try FileManager.default.removeItem(at: lease)
        _ = await waitUntil(watcher) {
            watcher.holding(forCourse: "EXC2O") == nil
        }
        before = watcher.folderEvents
        try FileManager.default.removeItem(at: internalFolder)
        await waitForAFolderEvent(watcher, after: before)
        before = watcher.folderEvents
        try FileManager.default.moveItem(at: away, to: internalFolder)
        await waitForAFolderEvent(watcher, after: before)
        try await expectALeaseToBeSeen(in: courses, by: watcher, "`.internal` renamed back")
    }

    /// Stopping lets go of the folder watch and every process watch (W12).
    func testStoppingLetsGoOfEveryWatch() async throws {
        let folder: URL = try makeWorkingFolder()
        let courses: URL = folder.appendingPathComponent("courses", isDirectory: true)
        let holder: Process = try startAHolder()
        try writeLease(kind: "build", course: "EXC2O", for: holder.processIdentifier, into: courses)
        let watchers: LeaseWatchers = LeaseWatchers()
        watchers.follow([folder])
        let watcher: LeaseWatcher = try XCTUnwrap(watchers.watcher(forFolder: folder))
        XCTAssertTrue(watcher.folderIsWatched)
        XCTAssertEqual(watcher.holderWatchCount, 1)
        watchers.follow([])
        XCTAssertNil(watchers.watcher(forFolder: folder))
        XCTAssertFalse(watcher.folderIsWatched)
        XCTAssertEqual(watcher.holderWatchCount, 0)
    }

    /// The help is the contract's sentence, and says nothing about the
    /// machinery (CLAUDE.md rule 1).
    func testTheHelpIsTheContractsSentence() throws {
        XCTAssertEqual(SectionDetailView.deployIsHeldElsewhere(course: "ICS3U"), try contractHelp(course: "ICS3U"))
        let sentence: String = SectionDetailView.deployIsHeldElsewhere(course: "ICS3U").lowercased()
        for word in ["lease", "process", "program", "script", "container", "docker", "toolchain"] {
            XCTAssertFalse(sentence.contains(word), "the help says \(word)")
        }
    }

    // MARK: - Helpers

    /// What the view asks, for course EXC2O in `folder`.
    private func availability(watcher: LeaseWatcher, folder: URL, section: Int, folderReady: Bool) -> Bool {
        let run: SectionDeployRun = SectionRuns.shared.deploy(folder: folder, courseCode: "EXC2O", sectionNumber: section)
        return SectionDetailView.deployIsAvailable(
            run: run,
            folderPath: folder.path,
            courseCode: "EXC2O",
            sectionNumber: section,
            isBeingCopied: false,
            folderIsGettingReady: !folderReady,
            heldElsewhere: watcher.holding(forCourse: "EXC2O") != nil
        )
    }

    /// Waits for `condition`, re-asking it whenever the watcher's answer
    /// moves, until `deadline`. False when it never held.
    private func waitUntil(_ watcher: LeaseWatcher, _ condition: @escaping () -> Bool) async -> Bool {
        let giveUpAt: Date = Date().addingTimeInterval(deadline)
        while !condition() {
            let remaining: TimeInterval = giveUpAt.timeIntervalSinceNow
            if remaining <= 0 {
                return false
            }
            let moved: XCTestExpectation = XCTestExpectation(description: "the watcher's answer moved")
            withObservationTracking {
                _ = watcher.generation
            } onChange: {
                moved.fulfill()
            }
            // Asked again after arming, so a move in between is not lost.
            if condition() {
                return true
            }
            _ = await XCTWaiter().fulfillment(of: [moved], timeout: remaining)
        }
        return true
    }

    /// A working folder with `courses/` but no `.internal`, watched.
    private func startedWithNoInternalFolder() throws -> (URL, LeaseWatcher) {
        let folder: URL = try makeWorkingFolder()
        let courses: URL = folder.appendingPathComponent("courses", isDirectory: true)
        try FileManager.default.removeItem(at: courses.appendingPathComponent(".internal"))
        let watcher: LeaseWatcher = LeaseWatcher(coursesDirectory: courses)
        watcher.start()
        return (courses, watcher)
    }

    /// A live holder's lease written into `courses`, and the watcher seeing
    /// it, or the test fails. Returns the lease.
    @discardableResult
    private func expectALeaseToBeSeen(in courses: URL, by watcher: LeaseWatcher, _ label: String) async throws -> URL {
        let holder: Process = try startAHolder()
        let lease: URL = try writeLease(kind: "build", course: "EXC2O", for: holder.processIdentifier, into: courses)
        let held: Bool = await waitUntil(watcher) {
            watcher.holding(forCourse: "EXC2O")?.pid == holder.processIdentifier
        }
        XCTAssertTrue(held, "\(label): the lease must be seen within \(deadline) s, with nothing else happening")
        return lease
    }

    /// Lets a folder event that has been caused reach the watcher, so the
    /// next step happens after it rather than in the same moment. Gives up
    /// after two seconds without failing: a watch that hears nothing (the
    /// fault these tests exist for) fails at the next step instead.
    private func waitForAFolderEvent(_ watcher: LeaseWatcher, after count: Int) async {
        let giveUpAt: Date = Date().addingTimeInterval(2)
        while watcher.folderEvents <= count && Date() < giveUpAt {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// The contract's sentence for a course.
    private func contractHelp(course: String) throws -> String {
        let section: [String: Any] = try SharedRulesContractTests.section("returningToASectionMidDeploy")
        let heldElsewhere: [String: Any] = try XCTUnwrap(section["heldElsewhere"] as? [String: Any])
        let help: String = try XCTUnwrap(heldElsewhere["help"] as? String)
        return help.replacingOccurrences(of: "{course}", with: course)
    }

    /// A working folder with `courses/.internal/activity/`.
    private func makeWorkingFolder() throws -> URL {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeaseWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("courses/.internal/activity", isDirectory: true),
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }
        return folder
    }

    /// A live process that is not this one.
    private func startAHolder() throws -> Process {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["120"]
        try process.run()
        holders.append(process)
        return process
    }

    /// The id of a process that has ended.
    private func aProcessThatHasEnded() throws -> Int32 {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    /// A lease for `pid`, written as a lease is written: atomically, with the
    /// name and start time the process table reports (none for a process
    /// that has ended, so its lease reads as stale).
    @discardableResult
    private func writeLease(kind: String, course: String, for pid: Int32, into courses: URL) throws -> URL {
        var name: String = "true"
        var started: String = "1.000000"
        if case .found(let tableName, _, let startTime) = ProcessLiveness.askTheProcessTable(pid: pid) {
            name = tableName
            started = startTime
        }
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: courses)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url: URL = directory.appendingPathComponent(WorkLeaseFiles.fileName(courseCode: course, kind: kind, pid: pid))
        let body: String = "\(pid)\n\(name)\n\(ProcessLiveness.leaseMomentText(Date()))\n\(started)\n"
        try Data(body.utf8).write(to: url, options: .atomic)
        return url
    }

    private func readSource(_ relativePath: String) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
