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

    /// A restore that fails part way, every file put back: the step it set
    /// aside is `interrupted` (partly applied or unknown, off the list),
    /// which is true of the disk, since the course again holds what the
    /// stopped save left (the new value); recovery never writes over it.
    func testARestoreThatFailsPartWayLeavesTheStepInterrupted() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try killASave(of: fixture.courseURL, code: "ICS3U")
        let seq: Int = try XCTUnwrap(try inFlight().first?.step.seq)
        let asTheSaveLeftIt: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        let hooks: RestoreSwap.Hooks = fixture.hooks(failForward: 2, failBack: nil, intruder: nil, seen: { (_: String) in })
        XCTAssertThrowsError(try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: hooks
        ))
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), asTheSaveLeftIt, "the restore did not put every file back")
        let fold: UndoFold = try UndoJournal(folderURL: listFolder).read()
        XCTAssertEqual(fold.records[seq]?.phase, .interrupted)

        await recoverAsAtALaunch(fixture.rootURL)
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), asTheSaveLeftIt, "recovery wrote over the course")
    }

    // MARK: - A one-section restore

    /// A step wholly inside the section a one-section restore replaces is
    /// set aside; one naming a section page AND a page every section shares
    /// (partly inside) is left in flight, today's behaviour, since no rule
    /// of the list says what it is once half of it is replaced (parked).
    func testAOneSectionRestoreSetsAsideOnlyAStepWhollyInsideTheSection() throws {
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
        XCTAssertEqual(fold.records[partlyInside]?.phase, .begun, "a step partly inside was set aside")
        XCTAssertEqual(fold.records[otherSection]?.phase, .begun, "another section's step was set aside")
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

    func inFlight() throws -> [UndoStepRecord] {
        return try UndoJournal(folderURL: listFolder).read().inFlight
    }

    func recoverAsAtALaunch(_ root: URL) async {
        let atLaunch: UndoJournal = UndoJournal(folderURL: listFolder, processIsAlive: { (_: UndoProcess) -> Bool in false })
        await UndoRecovery.recoverAndRederive(atLaunch, resolveRoot: { (_: UndoWorkingFolder) -> URL? in root })
    }
}
