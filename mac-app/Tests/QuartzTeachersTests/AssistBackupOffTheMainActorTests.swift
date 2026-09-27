import XCTest
@testable import QuartzTeachers

/// Every zip leaves the main thread (#351), and the assistant's window can say
/// what the wait is while one runs.
///
/// Until #351 each backup ran `/usr/bin/zip` and `waitUntilExit` on the main
/// thread, and the nested run loop re-entered SwiftUI: approving an assistant
/// change held the window for up to two minutes. The fact worth pinning is a
/// fact about the running program — which thread the zip ran on — because
/// `@concurrent` is an attribute an edit can lose without anything failing to
/// compile. `CourseArchiver.lastZipRanOnTheMainThread` is written inside the
/// ONE function that runs the zip, so no path to a zip goes unobserved.
@MainActor
final class AssistBackupOffTheMainActorTests: XCTestCase {

    // MARK: - Stored properties

    /// Copies a test is holding part-way, released by `releaseHeldCopies`.
    var heldCopies: [CheckedContinuation<Void, Never>] = []

    /// How many times the runner asked for a copy to be made.
    var copiesAskedFor: Int = 0

    // MARK: - Setting up

    override func setUp() async throws {
        try await super.setUp()
        heldCopies = []
        copiesAskedFor = 0
        CourseArchiver.lastZipRanOnTheMainThread = nil
    }

    /// A runner over the shared fixture, with the trail pointed at a scratch
    /// folder so nothing reaches the real one.
    private func makeRunner() throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        let trailFolder: URL = made.root.appendingPathComponent("trail")
        try FileManager.default.createDirectory(at: trailFolder, withIntermediateDirectories: true)
        let previousTrail: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
        let root: URL = made.root
        addTeardownBlock {
            MainActor.assumeIsolated {
                ActivityTrail.store = previousTrail
            }
            try? FileManager.default.removeItem(at: root)
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "false", body: "Two.", in: made.course)
        return made
    }

    private func publish(_ page: String, on runner: AssistToolRunner) async -> AssistToolOutcome {
        return await AssistFixture.run("publish_pages", with: ["pages": page], on: runner)
    }

    private func trail() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    private func backupLines(in text: String) -> [String] {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.contains("assistant backed up the course as") || line.contains("assistant could not back up") {
                lines.append(line)
            }
        }
        return lines
    }

    /// Replaces the runner's copier with one that stops part-way until the
    /// test lets it go, then makes the real copy.
    private func holdEveryCopy(on runner: AssistToolRunner) {
        runner.backUpACourse = { course, coursesDirectoryURL, maker in
            self.copiesAskedFor += 1
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.heldCopies.append(continuation)
            }
            return try await CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL, madeBy: maker)
        }
    }

    private func releaseHeldCopies() {
        let held: [CheckedContinuation<Void, Never>] = heldCopies
        heldCopies = []
        for continuation in held {
            continuation.resume()
        }
    }

    /// Lets other tasks run until `condition` holds, or fails after a while.
    private func waitUntil(_ what: String, _ condition: () -> Bool) async {
        var turns: Int = 0
        while !condition() {
            turns += 1
            if turns > 10_000 {
                XCTFail("Never saw: \(what)")
                return
            }
            await Task.yield()
        }
    }

    // MARK: - Off the main thread

    func testTheConversationsCopyIsZippedOffTheMainThread() async throws {
        let made: AssistFixture.Made = try makeRunner()
        _ = await publish("Unit 1, Day 1", on: made.runner)
        XCTAssertNotNil(made.runner.conversationBackupURL, "the write made its copy")
        XCTAssertEqual(CourseArchiver.lastZipRanOnTheMainThread, false,
                       "the assistant's copy was zipped on the main thread — the window froze while it ran (#351)")
    }

    func testTheBackUpToolZipsOffTheMainThread() async throws {
        let made: AssistFixture.Made = try makeRunner()
        let outcome: AssistToolOutcome = await AssistFixture.run("back_up_course", with: [:], on: made.runner)
        XCTAssertTrue(outcome.summary.hasPrefix("Backed up ICS3U to ICS3U_backup_"), outcome.summary)
        XCTAssertEqual(CourseArchiver.lastZipRanOnTheMainThread, false)
    }

    /// The other doors to a zip (Q3 of #351's plan: in this piece, not a
    /// follow-up) — Back Up Now, the archive a restore makes first, removing
    /// a section and removing a course.
    func testEveryOtherZipRunsOffTheMainThread() async throws {
        let made: AssistFixture.Made = try makeRunner()
        let coursesDirectoryURL: URL = made.root.appendingPathComponent("courses")

        CourseArchiver.lastZipRanOnTheMainThread = nil
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: made.root)
        var loaded: Course? = nil
        for candidate in workspace.courses where candidate.code == "ICS3U" {
            loaded = candidate
        }
        await workspace.backUp(try XCTUnwrap(loaded))
        XCTAssertNil(workspace.backupProblem)
        XCTAssertEqual(CourseArchiver.lastZipRanOnTheMainThread, false, "Back Up Now")

        CourseArchiver.lastZipRanOnTheMainThread = nil
        try await CourseArchiver.archiveCourse(made.course, coursesDirectoryURL: coursesDirectoryURL)
        XCTAssertEqual(CourseArchiver.lastZipRanOnTheMainThread, false, "the archive a restore makes first")

        CourseArchiver.lastZipRanOnTheMainThread = nil
        try await CourseArchiver.archiveAndRemoveSection(1, from: made.course, coursesDirectoryURL: coursesDirectoryURL)
        XCTAssertEqual(CourseArchiver.lastZipRanOnTheMainThread, false, "removing a section")

        CourseArchiver.lastZipRanOnTheMainThread = nil
        try await CourseArchiver.archiveAndRemoveCourse(made.course, coursesDirectoryURL: coursesDirectoryURL)
        XCTAssertEqual(CourseArchiver.lastZipRanOnTheMainThread, false, "removing a course")
    }

    // MARK: - What the window is shown

    func testTheWindowIsToldWhichCourseIsBeingCopiedAndThenThatItIsDone() async throws {
        let made: AssistFixture.Made = try makeRunner()
        holdEveryCopy(on: made.runner)
        XCTAssertNil(made.runner.courseBeingBackedUp)

        let runner: AssistToolRunner = made.runner
        let writing: Task<AssistToolOutcome, Never> = Task { @MainActor in
            return await self.publish("Unit 1, Day 1", on: runner)
        }
        await waitUntil("the copy to start") { return !heldCopies.isEmpty }
        XCTAssertEqual(made.runner.courseBeingBackedUp, "ICS3U",
                       "while the copy is being saved, the window can say whose")

        releaseHeldCopies()
        let outcome: AssistToolOutcome = await writing.value
        XCTAssertNil(made.runner.courseBeingBackedUp, "and the line goes when the copy is done")
        XCTAssertTrue(outcome.detail.contains("backed up"), outcome.detail)
    }

    func testAFailedCopyClearsTheLineIsNotRememberedAndIsTriedAgain() async throws {
        let made: AssistFixture.Made = try makeRunner()
        made.runner.backUpACourse = { _, _, _ in
            self.copiesAskedFor += 1
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "the disk is full"])
        }

        let first: AssistToolOutcome = await publish("Unit 1, Day 1", on: made.runner)
        XCTAssertNil(made.runner.courseBeingBackedUp, "a failed copy must not leave the line saying it is saving one")
        XCTAssertNil(made.runner.conversationBackupURL, "a failed copy is not a way back")
        XCTAssertFalse(first.detail.contains("backed up before this conversation"),
                       "the write must not claim a backup that failed: \(first.detail)")

        _ = await publish("Unit 1, Day 2", on: made.runner)
        XCTAssertEqual(copiesAskedFor, 2, "the next write tries again rather than trusting the failure")
        XCTAssertEqual(backupLines(in: trail()).count, 2)
        XCTAssertTrue(trail().contains("ICS3U/1 · assistant could not back up the course: the disk is full"), trail())
    }

    /// Two writes arriving while the first copy is still being zipped — which
    /// an outside assistant can now do, because the main thread is free —
    /// share that copy rather than making a second.
    func testTwoWritesDuringOneCopyShareIt() async throws {
        let made: AssistFixture.Made = try makeRunner()
        holdEveryCopy(on: made.runner)

        let runner: AssistToolRunner = made.runner
        let firstWrite: Task<AssistToolOutcome, Never> = Task { @MainActor in
            return await self.publish("Unit 1, Day 1", on: runner)
        }
        let secondWrite: Task<AssistToolOutcome, Never> = Task { @MainActor in
            return await self.publish("Unit 1, Day 2", on: runner)
        }
        await waitUntil("the copy to start") { return !heldCopies.isEmpty }
        // Long enough for the second write to reach the copy too, if it were
        // going to start one of its own.
        for _ in 0..<500 {
            await Task.yield()
        }
        XCTAssertEqual(copiesAskedFor, 1, "the second write started a copy of its own")

        releaseHeldCopies()
        let first: AssistToolOutcome = await firstWrite.value
        let second: AssistToolOutcome = await secondWrite.value
        XCTAssertTrue(first.detail.contains("backed up"), first.detail)
        XCTAssertTrue(second.detail.contains("backed up"), second.detail)
        let backups: [BackupItem] = WorkspaceModel.findBackupItems(
            in: made.root.appendingPathComponent("courses")
        )
        XCTAssertEqual(backups.count, 1)
    }

    // MARK: - The trail

    func testOneTrailLinePerRealCopyWithItsNameSizeAndTime() async throws {
        let made: AssistFixture.Made = try makeRunner()
        _ = await publish("Unit 1, Day 1", on: made.runner)
        let backupName: String = try XCTUnwrap(made.runner.conversationBackupURL?.lastPathComponent)

        var lines: [String] = backupLines(in: trail())
        XCTAssertEqual(lines.count, 1, trail())
        let line: String = try XCTUnwrap(lines.first)
        XCTAssertTrue(line.contains("ICS3U/1 · assistant backed up the course as \(backupName) ("), line)
        XCTAssertNotNil(line.range(of: #"\(\d+\.\d MB, \d+\.\d s\)$"#, options: .regularExpression), line)

        // Reusing the conversation's copy makes no zip, so it writes nothing.
        _ = await publish("Unit 1, Day 2", on: made.runner)
        lines = backupLines(in: trail())
        XCTAssertEqual(lines.count, 1, "the reused copy wrote a line of its own: \(trail())")
    }

    func testTheTrailLineReadsAsWritten() {
        XCTAssertEqual(
            ActivityTrail.assistantBackedUpLine(
                fileName: "EXC2O_backup_2026-09-26_101500_assistant-section1.zip",
                bytes: 3_240_000, seconds: 0.44
            ),
            "assistant backed up the course as EXC2O_backup_2026-09-26_101500_assistant-section1.zip (3.2 MB, 0.4 s)"
        )
    }

    // MARK: - The gap between a plan and its write (the review round's S2, B1)

    /// A write works its plan out again after the copy, and refuses one the
    /// course has outrun: here the page add_next_class was about to create
    /// is written by the teacher while the copy is being saved.
    func testAWriteRefusesAPlanTheCourseOutranDuringItsCopy() async throws {
        let made: AssistFixture.Made = try makeRunner()
        // The class dates, remembered by ANOTHER conversation, so this one
        // still has its first copy to make.
        let other: AssistToolRunner = AssistToolRunner(
            workspace: { () -> WorkspaceModel in
                let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
                workspace.chooseWorkspace(at: made.root)
                return workspace
            }(),
            siteWork: StubSiteWork(),
            today: { return CalendarDay(year: 2026, month: 9, day: 8)! },
            launchControl: SilentLaunchControl()
        )
        try AssistFixture.write(page: "Unit 4, Day 12", publish: "true", date: "2026-09-08", body: "Twelve.", in: made.course)
        _ = await AssistFixture.run(
            "remember_timetable", with: ["dates": "2026-09-08; 2026-09-10; 2026-09-14"], on: other
        )
        holdEveryCopy(on: made.runner)

        let runner: AssistToolRunner = made.runner
        let adding: Task<AssistToolOutcome, Never> = Task { @MainActor in
            return await AssistFixture.run("add_next_class", with: [:], on: runner)
        }
        await waitUntil("the copy to start") { return !heldCopies.isEmpty }
        let theirs: String = "---\ntitle: Unit 4, Day 13\npublish: false\n---\n\nWritten by the teacher meanwhile.\n"
        try theirs.write(to: AssistFixture.pageURL(of: "Unit 4, Day 13", in: made.course), atomically: true, encoding: .utf8)
        releaseHeldCopies()
        let outcome: AssistToolOutcome = await adding.value

        XCTAssertEqual(outcome.summary, AssistWording.changedWhileSavingACopy(course: "ICS3U", section: "1"), outcome.detail)
        XCTAssertEqual(
            try String(contentsOf: AssistFixture.pageURL(of: "Unit 4, Day 13", in: made.course), encoding: .utf8),
            theirs, "the teacher's page was written over"
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: AssistFixture.pageURL(of: "Unit 4, Day 14", in: made.course).path
        ), "a page was made from the plan the course outran")
    }

    /// The assistant's start-of-the-year copy goes through the same door:
    /// the window's line while it runs, and one trail line (#96 merged in).
    func testTheStartOfTheYearCopyGoesThroughTheDoor() async throws {
        let made: AssistFixture.Made = try makeRunner()
        try AssistFixture.write(page: "Unit 1, Day 3", publish: "true", body: "Three.", in: made.course)
        _ = await AssistFixture.run("publish_pages", with: ["pages": "Unit 1, Day 1, Unit 1, Day 2"], on: made.runner)
        let planned: AssistToolOutcome = await AssistFixture.run("plan_prepare_for_start_of_year", with: [:], on: made.runner)
        let code: String = try XCTUnwrap(StartOfYearPlanner.planCode(in: planned.detail), planned.detail)
        let linesBefore: Int = backupLines(in: trail()).count
        CourseArchiver.lastZipRanOnTheMainThread = nil
        holdEveryCopy(on: made.runner)

        let runner: AssistToolRunner = made.runner
        let preparing: Task<AssistToolOutcome, Never> = Task { @MainActor in
            return await AssistFixture.run("prepare_for_start_of_year", with: ["planCode": code], on: runner)
        }
        await waitUntil("the copy to start") { return !heldCopies.isEmpty }
        XCTAssertEqual(made.runner.courseBeingBackedUp, "ICS3U", "the window's line shows for this copy too")
        releaseHeldCopies()
        _ = await preparing.value

        XCTAssertEqual(copiesAskedFor, 1)
        XCTAssertEqual(backupLines(in: trail()).count, linesBefore + 1, trail())
        XCTAssertEqual(CourseArchiver.lastZipRanOnTheMainThread, false)
    }
}

