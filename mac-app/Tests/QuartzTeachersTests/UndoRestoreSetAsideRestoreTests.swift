import XCTest
@testable import QuartzTeachers

/// What a restore does with an Undo step left in flight (#899, ahead of U5:
/// `UndoRestoreSetAside`): a settings step in its course, a step in another
/// course, a restore that fails part way, and a one-section restore. Each
/// step in flight is a Course Settings save killed after its swap and before
/// `applied`, as a save whose put-back was declined (Not Now) is left: the
/// file holds the new value and the step is open.
@MainActor
final class UndoRestoreSetAsideRestoreTests: XCTestCase {

    // MARK: - Stored properties

    var listFolder: URL = FileManager.default.temporaryDirectory

    // MARK: - Setting up

    override func setUp() async throws {
        listFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-restore-set-aside-\(UUID().uuidString)", isDirectory: true)
        UndoJournalLocation.folderOverride = listFolder
        JournaledStep.modeOverride = .live
    }

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        JournaledStep.modeOverride = nil
        UndoKillPoints.hook = nil
        try? FileManager.default.removeItem(at: listFolder)
    }

    // MARK: - A whole-course restore

    /// Restore from Backup… with a settings step in flight in the course:
    /// afterwards nothing is in flight, recovery as at a launch changes no
    /// file of the restored course, and the next change is not refused.
    func testRestoreFromBackupSetsAsideASettingsStepInFlight() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try killASave(of: fixture.courseURL, code: "ICS3U")
        XCTAssertEqual(try inFlight().count, 1)

        try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)
        XCTAssertEqual(try inFlight().count, 0, "the restore left the settings step in flight")
        let restored: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        XCTAssertEqual(restored["course_config.json"], fixture.backupFiles["course_config.json"], "the course is not the backup's")

        await recoverAsAtALaunch(fixture.rootURL)
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), restored, "recovery changed the restored course")

        let course: Course = try load(fixture.courseURL, code: "ICS3U")
        course.configuration.hiddenItems = ["Concepts"]
        XCTAssertNoThrow(try course.configuration.writeAsOneStep(
            to: course.configFileURL, madeBy: UndoStepMaker.sheet("saveCourseSettings")
        ), "the next change was refused")
    }

    /// A step in flight in ANOTHER course survives the restore and is
    /// recovered as before: closed as made, its file holding the new value.
    func testAnotherCoursesStepSurvivesTheRestoreAndIsRecovered() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let otherURL: URL = fixture.coursesDirectoryURL.appendingPathComponent("ICS4U")
        try FileManager.default.createDirectory(at: otherURL, withIntermediateDirectories: true)
        let settings: [String: Any] = ["course_code": "ICS4U", "course_name": "Other course", "section_numbers": [1]]
        try JSONSerialization.data(withJSONObject: settings).write(to: otherURL.appendingPathComponent("course_config.json"))
        try killASave(of: otherURL, code: "ICS4U")
        let seq: Int = try XCTUnwrap(try inFlight().first?.step.seq)

        try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)
        XCTAssertEqual(try inFlight().count, 1, "another course's step was touched by the restore")

        await recoverAsAtALaunch(fixture.rootURL)
        let fold: UndoFold = try UndoJournal(folderURL: listFolder).read()
        XCTAssertEqual(fold.records[seq]?.phase, .done, "recovery no longer settles the other course's step")
        let reloaded: CourseConfiguration = try CourseConfiguration(contentsOf: otherURL.appendingPathComponent("course_config.json"))
        XCTAssertEqual(reloaded.hiddenItems, ["Media"])
    }

    /// A restore whose first move fails moves nothing: the step is left
    /// exactly as it was, in flight, and recovery settles it as before
    /// (closed as made, the file at the new value). The review of
    /// 2026-11-27, M1.
    func testARestoreThatFailsBeforeItsFirstMoveLeavesTheStepInFlight() async throws {
        try await assertAFailedRestoreLeavesTheStepInFlight(failForward: 1)
    }

    /// A restore that fails part way and puts every file back leaves the
    /// step exactly as it was, in flight, and recovery settles it as before.
    func testARestoreThatPutsEveryFileBackLeavesTheStepInFlight() async throws {
        try await assertAFailedRestoreLeavesTheStepInFlight(failForward: 2)
    }

    /// A restore that stops part way with files moved and NOT all put back:
    /// the course is part backup, part its own. The step is closed
    /// `interrupted` (set aside: partly applied or unknown, off the list),
    /// which is true of that disk; recovery never writes over it.
    func testARestoreThatStopsPartWaySetsTheStepAside() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try killASave(of: fixture.courseURL, code: "ICS3U")
        let seq: Int = try XCTUnwrap(try inFlight().first?.step.seq)

        let hooks: RestoreSwap.Hooks = fixture.hooks(failForward: 3, failBack: 1, intruder: nil, seen: { (_: String) in })
        XCTAssertThrowsError(try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: hooks
        ))
        let fold: UndoFold = try UndoJournal(folderURL: listFolder).read()
        XCTAssertEqual(fold.records[seq]?.phase, .interrupted, "a restore that stopped part way left the step in flight")
        let asTheRestoreLeftIt: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        await recoverAsAtALaunch(fixture.rootURL)
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), asTheRestoreLeftIt, "recovery wrote over the course")
    }

    func assertAFailedRestoreLeavesTheStepInFlight(failForward: Int) async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try killASave(of: fixture.courseURL, code: "ICS3U")
        let seq: Int = try XCTUnwrap(try inFlight().first?.step.seq)
        let asTheSaveLeftIt: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        let hooks: RestoreSwap.Hooks = fixture.hooks(failForward: failForward, failBack: nil, intruder: nil, seen: { (_: String) in })
        XCTAssertThrowsError(try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: hooks
        ))
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), asTheSaveLeftIt, "the restore did not put every file back")
        let fold: UndoFold = try UndoJournal(folderURL: listFolder).read()
        XCTAssertEqual(fold.records[seq]?.phase, .begun, "a restore that left the course as it was took the step from recovery")

        await recoverAsAtALaunch(fixture.rootURL)
        let recovered: UndoFold = try UndoJournal(folderURL: listFolder).read()
        XCTAssertEqual(recovered.records[seq]?.phase, .done, "recovery no longer settles the step by content")
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), asTheSaveLeftIt, "recovery wrote over the course")
    }

    // MARK: - The lock across the swap (review 2)

    /// While the swap moves files the list's lock is held, so no recovery
    /// can judge and no step can begin between the swap and the set-aside:
    /// a try for the lock from inside a move is refused (review 2, L1).
    func testTheListsLockIsHeldWhileTheSwapMoves() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try killASave(of: fixture.courseURL, code: "ICS3U")
        let journal: UndoJournal = UndoJournal(folderURL: listFolder)
        var triesRefused: Int = 0
        var tries: Int = 0
        let hooks: RestoreSwap.Hooks = RestoreSwap.Hooks(
            step: { (_: String) throws in },
            move: { (source: URL, destination: URL) throws in
                tries += 1
                do {
                    try journal.withLock(waitingAtMost: 0) { (_: UndoJournalWriter) in }
                } catch UndoJournalError.lockBusy {
                    triesRefused += 1
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            moveBack: { (source: URL, destination: URL) throws in
                try FileManager.default.moveItem(at: source, to: destination)
            },
            flushes: false
        )
        try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: hooks)
        XCTAssertGreaterThan(tries, 0)
        XCTAssertEqual(triesRefused, tries, "the list's lock was free while the swap moved files")
    }

    /// A list whose lock cannot be had: the restore does not start (no
    /// move, the course as it was, the step still in flight), rather than
    /// swap with no set-aside (review 2, L3).
    func testARestoreThatCannotHaveTheListDoesNotStart() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try killASave(of: fixture.courseURL, code: "ICS3U")
        let seq: Int = try XCTUnwrap(try inFlight().first?.step.seq)
        let asTheSaveLeftIt: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        let journal: UndoJournal = UndoJournal(folderURL: listFolder)
        let held: UndoLock = try UndoLock.take(at: journal.lockFileURL, waitingAtMost: 0)
        defer { held.release() }

        XCTAssertThrowsError(try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL))
        held.release()
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), asTheSaveLeftIt, "the restore went ahead without the list")
        XCTAssertEqual(try UndoJournal(folderURL: listFolder).read().records[seq]?.phase, .begun)
    }

    /// A restore that died after its commit and before the set-aside line:
    /// the settle that finishes it at the next reading sets the step aside,
    /// so recovery never judges the restored course (review 2, L2).
    func testASettleThatFinishesARestoreSetsTheStepAside() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try killASave(of: fixture.courseURL, code: "ICS3U")
        let seq: Int = try XCTUnwrap(try inFlight().first?.step.seq)
        // As a kill after `done` leaves it: every move made, nothing set aside.
        _ = try StagedRestore.make(fixture, phase: .done, movesMade: Int.max, archived: true)
        XCTAssertEqual(try UndoJournal(folderURL: listFolder).read().records[seq]?.phase, .begun)

        WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)
        XCTAssertEqual(
            try UndoJournal(folderURL: listFolder).read().records[seq]?.phase, .interrupted,
            "the settle finished the restore and left the step in flight"
        )
        let restored: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        await recoverAsAtALaunch(fixture.rootURL)
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), restored, "recovery wrote over the restored course")
    }

    /// A one-section restore writes the section's per-section keys into
    /// the shared pages inside the same lock (review 2, L4).
    func testAOneSectionRestoreWritesItsKeysInsideTheLock() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let id: String = try FolderIdentityFile.identifier(forWorkingFolder: fixture.rootURL)
        _ = try beginAStep(writing: ["courses/ICS3U/section1/a.md"], in: UndoWorkingFolder(id: id, pathAtTheTime: fixture.rootURL.path))
        let journal: UndoJournal = UndoJournal(folderURL: listFolder)
        var keysReached: Bool = false
        var refusedThere: Bool = false
        let hooks: CourseRestorer.SectionSwapHooks = CourseRestorer.SectionSwapHooks(
            move: { (source: URL, destination: URL) throws in
                try FileManager.default.moveItem(at: source, to: destination)
            },
            reached: { (point: CourseRestorer.SwapPoint) throws in
                if point != .perSectionKeysPutBack {
                    return
                }
                keysReached = true
                do {
                    try journal.withLock(waitingAtMost: 0) { (_: UndoJournalWriter) in }
                } catch UndoJournalError.lockBusy {
                    refusedThere = true
                }
            }
        )
        try CourseRestorer.restoreSection(1, from: try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: hooks)
        XCTAssertTrue(keysReached)
        XCTAssertTrue(refusedThere, "the per-section keys were written outside the list's lock")
    }

    // MARK: - A one-section restore

    /// Each file a one-section restore replaces is set aside: a step wholly
    /// inside the section is closed; one naming a section page AND a page
    /// outside keeps the outside page, in flight; another section's step is
    /// untouched (the director's ruling on M2).
    func testAOneSectionRestoreSetsAsideTheFilesItReplaces() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let id: String = try FolderIdentityFile.identifier(forWorkingFolder: fixture.rootURL)
        let folder: UndoWorkingFolder = UndoWorkingFolder(id: id, pathAtTheTime: fixture.rootURL.path)
        let sectionPage: String = "courses/ICS3U/section1/All Classes/Unit 1, Day 1.md"
        let whollyInside: Int = try beginAStep(writing: [sectionPage], in: folder)
        let partlyInside: Int = try beginAStep(writing: [sectionPage, "courses/ICS3U/index.md"], in: folder)
        let otherSection: Int = try beginAStep(writing: ["courses/ICS3U/section2/a.md"], in: folder)

        try CourseRestorer.restoreSection(1, from: try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)

        let fold: UndoFold = try UndoJournal(folderURL: listFolder).read()
        XCTAssertEqual(fold.records[whollyInside]?.phase, .interrupted, "the section's own step was left in flight")
        XCTAssertEqual(fold.records[partlyInside]?.phase, .begun, "a step partly inside was closed whole")
        XCTAssertEqual(fold.records[partlyInside]?.setAsidePaths, [sectionPage], "the replaced page was not set aside")
        XCTAssertEqual(fold.records[otherSection]?.phase, .begun, "another section's step was set aside")
        XCTAssertEqual(fold.records[otherSection]?.setAsidePaths, [])
    }

    /// The reviewer's case (M2): a step writing a section page made, a
    /// second section page not made, and two files outside the section
    /// (one made, one not), stopped part way; the backup holds the made
    /// page as the step left it. A section-1 restore, then recovery at a
    /// launch: no restored page is written (the restored page and the
    /// missing one are as the restore left them), and the outside files
    /// are settled by content: some of each, so the made one is put back.
    func testRecoveryNeverWritesARestoredPageAndSettlesTheRestByContent() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let id: String = try FolderIdentityFile.identifier(forWorkingFolder: fixture.rootURL)
        let folder: UndoWorkingFolder = UndoWorkingFolder(id: id, pathAtTheTime: fixture.rootURL.path)
        let madePage: String = "courses/ICS3U/section1/All Classes/Unit 1, Day 1.md"
        let pageNotMade: String = "courses/ICS3U/section1/All Classes/Unit 1, Day 2.md"
        let madeOutside: String = "courses/ICS3U/index.md"
        let outsideNotMade: String = "courses/ICS3U/Concepts/Unit 1/Concept 1.md"
        // As the step left the live course: the section page at the
        // backup's bytes (the backup was taken while it was in flight).
        try WholeCourseFixture.write("BACKUP class\n", to: fixture.rootURL.appendingPathComponent(madePage))
        let seq: Int = try beginAStep(changes: [
            (path: madePage, before: "START class\n", after: "BACKUP class\n"),
            (path: pageNotMade, before: nil, after: "made by the step\n"),
            (path: madeOutside, before: "START front page\n", after: "LIVE front page\n"),
            (path: outsideNotMade, before: "LIVE concept\n", after: "made by the step\n"),
        ], in: folder)

        try CourseRestorer.restoreSection(1, from: try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)
        let fold: UndoFold = try UndoJournal(folderURL: listFolder).read()
        XCTAssertEqual(fold.records[seq]?.phase, .begun)
        let restoredPage: Data? = try? Data(contentsOf: fixture.rootURL.appendingPathComponent(madePage))
        XCTAssertEqual(restoredPage, Data("BACKUP class\n".utf8))

        await recoverAsAtALaunch(fixture.rootURL)
        XCTAssertEqual(
            try? Data(contentsOf: fixture.rootURL.appendingPathComponent(madePage)), Data("BACKUP class\n".utf8),
            "recovery wrote into a page the restore replaced"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.rootURL.appendingPathComponent(pageNotMade).path),
            "recovery made a page inside the restored section"
        )
        XCTAssertEqual(
            try? Data(contentsOf: fixture.rootURL.appendingPathComponent(madeOutside)), Data("START front page\n".utf8),
            "the outside file was not settled by content (some of each: put back)"
        )
        XCTAssertEqual(
            try? Data(contentsOf: fixture.rootURL.appendingPathComponent(outsideNotMade)), Data("LIVE concept\n".utf8)
        )
        let recovered: UndoFold = try UndoJournal(folderURL: listFolder).read()
        XCTAssertEqual(recovered.records[seq]?.phase, .interrupted, "a step with files set aside went back on the list")
        XCTAssertEqual(recovered.inFlight.count, 0)
    }

    // MARK: - Helpers

    func item(_ fixture: WholeCourseFixture) throws -> BackupItem {
        return try XCTUnwrap(BackupItem.from(fileURL: fixture.zipURL, courseCode: "ICS3U"))
    }

    func load(_ courseURL: URL, code: String) throws -> Course {
        let loaded: CourseConfiguration = try CourseConfiguration(contentsOf: courseURL.appendingPathComponent("course_config.json"))
        return Course(code: code, directoryURL: courseURL, configuration: loaded)
    }

    /// A Course Settings save killed after its swap, before `applied`.
    func killASave(of courseURL: URL, code: String) throws {
        let course: Course = try load(courseURL, code: code)
        course.configuration.hiddenItems = ["Media"]
        UndoKillPoints.hook = { (reached: UndoKillPoint) -> Bool in
            return reached == .beforeApplied
        }
        XCTAssertThrowsError(try course.configuration.writeAsOneStep(
            to: course.configFileURL, madeBy: UndoStepMaker.sheet("saveCourseSettings")
        ))
        UndoKillPoints.hook = nil
    }

    /// A `begin` with no work after it, as a step a process stopped in.
    func beginAStep(writing paths: [String], in folder: UndoWorkingFolder) throws -> Int {
        let journal: UndoJournal = UndoJournal(folderURL: listFolder)
        return try journal.withLock { (writer: UndoJournalWriter) -> Int in
            let seq: Int = writer.fold.highestSeq + 1
            var ops: [UndoOp] = []
            for path in paths {
                ops.append(UndoOp(kind: "writeFile", path: path))
            }
            let step: UndoStep = UndoStep(
                seq: seq, madeAt: "2026-11-27T00:00:00Z", action: nil, madeBy: nil, workingFolder: folder,
                course: "ICS3U", section: 1, actionClass: nil, holds: nil, ops: ops
            )
            try writer.append(UndoEventLine(seq: seq, event: .begin, step: step, process: journal.process))
            return seq
        }
    }

    /// A `begin` with real whole-file changes, their bytes in the list, and
    /// no work after it, as a step a process stopped in.
    func beginAStep(changes: [(path: String, before: String?, after: String?)], in folder: UndoWorkingFolder) throws -> Int {
        let journal: UndoJournal = UndoJournal(folderURL: listFolder)
        return try journal.withLock { (writer: UndoJournalWriter) -> Int in
            let seq: Int = writer.fold.highestSeq + 1
            var ops: [UndoOp] = []
            for change in changes {
                var op: UndoOp = UndoOp(kind: "writeFile", path: change.path)
                var blobs: [String] = []
                if let before = change.before {
                    let sha: String = try writer.writeBlob(Data(before.utf8))
                    op.beforeSha = sha
                    blobs.append(sha)
                }
                if let after = change.after {
                    let sha: String = try writer.writeBlob(Data(after.utf8))
                    op.afterSha = sha
                    blobs.append(sha)
                }
                op.blobs = blobs
                ops.append(op)
            }
            let step: UndoStep = UndoStep(
                seq: seq, madeAt: "2026-11-27T00:00:00Z", action: nil, madeBy: nil, workingFolder: folder,
                course: "ICS3U", section: 1, actionClass: nil, holds: nil, ops: ops
            )
            try writer.append(UndoEventLine(seq: seq, event: .begin, step: step, process: journal.process))
            return seq
        }
    }

    func inFlight() throws -> [UndoStepRecord] {
        return try UndoJournal(folderURL: listFolder).read().inFlight
    }

    func recoverAsAtALaunch(_ root: URL) async {
        let atLaunch: UndoJournal = UndoJournal(folderURL: listFolder, processIsAlive: { (_: UndoProcess) -> Bool in false })
        await UndoRecovery.recoverAndRederive(atLaunch, resolveRoot: { (_: UndoWorkingFolder) -> URL? in root })
    }
}
