import XCTest
@testable import QuartzTeachers

/// A whole-course restore through the SAME entries the menus call (#909,
/// after the implementation review): `WorkspaceModel.restoreBackup` for
/// Restore from Backup…, and `WorkspaceModel.restore(_:)` for File ▸
/// Restore from Archive…, each on a temporary working folder.
///
/// Why this file exists: the review's W1 found that every whole-course
/// restore from Backups refused itself with `anotherRestoreUnderWay`, after
/// its archive was made, because the third refusal counted the restore's
/// own record. Every contract case injected the refusal, and every engine
/// test called `CourseRestorer.restoreBackup` below the door, so nothing ran
/// the door end to end. The reference replacer's path, the third door, is
/// `ReferenceReplacerTests` (the test that restores ICS3U-2025 from its
/// backup and `testEveryWholeCourseRestoreLeavesOneLine`), which go red the
/// same way.
@MainActor
final class WholeCourseRestoreDoorTests: XCTestCase {

    // MARK: - Functions: the doors

    /// Restore from Backup…, end to end: the course IS the backup's
    /// afterwards, with nothing staged and the one line on the trail. MUST
    /// FAIL on 7769cb7a7, where the third refusal found this restore's own
    /// record (W1).
    func testRestoreFromBackupsThroughTheMenusEntryPutsTheBackupBack() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        // A page the backup does not have, so "the backup's, byte for byte"
        // is checked both ways (the fix review's m-2): nothing of the course
        // as it was is left beside the backup's files.
        try WholeCourseFixture.write("LIVE only\n", to: fixture.courseURL.appendingPathComponent("Concepts/Made since.md"))
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        let liveGit: Data = try Data(contentsOf: fixture.courseURL.appendingPathComponent(".git/HEAD"))

        await workspace.restoreBackup(try WholeCourseRestoreDoorTests.backup(fixture))

        XCTAssertNil(workspace.backupProblem, workspace.backupProblem ?? "")
        XCTAssertEqual(
            try WholeCourseFixture.snapshot(of: fixture.courseURL), fixture.backupWithWhatIsKeptInPlace(liveGit: liveGit),
            "the course is the backup's, every file and nothing else"
        )
        XCTAssertEqual(
            try fixture.keptIn(folderStartingWith: "ICS3U not in the archive "), [:],
            "the archive holds the course as it was; nothing else is kept"
        )
        XCTAssertEqual(fixture.leftInRestoring(), 0, "nothing is left staged")
        XCTAssertTrue(fixture.trailText().contains("restored ICS3U (ICS3U) from \(fixture.zipURL.lastPathComponent)"), fixture.trailText())
        XCTAssertFalse(fixture.trailText().contains("did not go ahead"), fixture.trailText())
    }

    /// File ▸ Restore from Archive…, end to end: a whole course archived and
    /// removed comes back, staged, and the archive is used up.
    func testRestoreFromArchiveThroughTheMenusEntryPutsTheCourseBack() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        let course: Course = try XCTUnwrap(WholeCourseRestoreDoorTests.course("ICS3U", in: workspace))
        let archiveURL: URL = try await CourseArchiver.archiveCourse(course, coursesDirectoryURL: fixture.coursesDirectoryURL)
        try FileManager.default.removeItem(at: fixture.courseURL)
        workspace.reloadCourses()
        let archived: ArchivedItem = try XCTUnwrap(ArchivedItem.from(fileURL: archiveURL, courseCode: "ICS3U"))

        workspace.restore(archived)

        XCTAssertNil(workspace.restoreProblem, workspace.restoreProblem ?? "")
        var archivedFiles: [String: Data] = live
        archivedFiles[".git/HEAD"] = nil
        XCTAssertEqual(
            try WholeCourseFixture.snapshot(of: fixture.courseURL), archivedFiles,
            "the course is as it was archived, every file and nothing else (an archive leaves out .git)"
        )
        XCTAssertFalse(RestoreSwap.itemExists(at: archiveURL), "the archive is used up")
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    /// A course kept for reference, restored from Backups through the door:
    /// the backup's, and locked again afterwards.
    func testAReferenceCourseRestoredFromBackupsIsTheBackupsAndLockedAgain() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture(reference: true)
        defer { fixture.tearDown() }
        _ = ReferenceLock.lock(courseDirectory: fixture.courseURL)
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)

        let liveGit: Data = try Data(contentsOf: fixture.courseURL.appendingPathComponent(".git/HEAD"))

        await workspace.restoreBackup(try WholeCourseRestoreDoorTests.backup(fixture))

        XCTAssertNil(workspace.backupProblem, workspace.backupProblem ?? "")
        // The whole course, both ways (the fix review's m-2: this read one
        // page), and every page of it locked again.
        XCTAssertEqual(
            try WholeCourseFixture.snapshot(of: fixture.courseURL), fixture.backupWithWhatIsKeptInPlace(liveGit: liveGit)
        )
        for path in fixture.backupFiles.keys where path.hasSuffix(".md") {
            XCTAssertTrue(
                ReferenceLock.isLocked(fixture.courseURL.appendingPathComponent(path)),
                "\(path): the restored reference course is locked again"
            )
        }
    }

    // MARK: - Functions: what is said and recorded

    /// I4: a refused restore leaves a line naming the refusal and when it
    /// was asked. MUST FAIL on 7769cb7a7, which wrote nothing.
    func testARefusedRestoreLeavesALine() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        _ = try PreviewLeases.lease(folderPath: fixture.rootURL.path, courseCode: "ICS3U", sectionNumber: 1)
        defer { PreviewLeases.reset() }

        await workspace.restoreBackup(try WholeCourseRestoreDoorTests.backup(fixture))

        XCTAssertNotNil(workspace.backupProblem)
        let line: String = "a whole-course restore from \(fixture.zipURL.lastPathComponent) did not go ahead, and the course was left as it was: "
            + WholeCourseRestore.DidNotGoAhead.busy.rawValue + ", asked " + WholeCourseRestore.AskedWhen.beforeTheArchive.rawValue
        XCTAssertTrue(fixture.trailText().contains(line), fixture.trailText())
        XCTAssertEqual(LogRedactor.redacting(line), line)
    }

    /// I2 through the reading: another computer's unfinished restore, with
    /// the course missing its settings here, is said once per opening of
    /// the window, and nothing is moved by it.
    func testAnotherComputersUnfinishedRestoreIsSaidOncePerOpening() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        _ = try StagedRestore.make(
            fixture, phase: .swapping, movesMade: 2, computer: "ANOTHER-COMPUTER",
            writtenAt: Date().addingTimeInterval(-86_400)
        )
        let before: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        workspace.reloadCourses()
        XCTAssertEqual(workspace.backupProblem, RestoreWholeCourseWording.unfinishedOnAnotherComputer(course: "ICS3U"))
        XCTAssertEqual(workspace.backupProblemTitle, RestoreWholeCourseWording.didNotFinishTitle)
        workspace.backupProblem = nil
        workspace.reloadCourses()
        XCTAssertNil(workspace.backupProblem, "said once per opening")
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), before, "nothing moved")
    }

    /// M-e: what a settle says is added to a problem already showing,
    /// never dropped (the settle has already acted). MUST FAIL on
    /// 7769cb7a7, which dropped it.
    func testWhatTheSettleSaysIsAddedToAProblemAlreadyShowing() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        _ = try StagedRestore.make(fixture, phase: .swapping, movesMade: 2)
        workspace.backupProblem = "SHOWING ALREADY"

        workspace.reloadCourses()

        XCTAssertEqual(workspace.backupProblem, "SHOWING ALREADY\n\n" + RestoreWholeCourseWording.didNotFinish(course: "ICS3U"))
    }

    /// I1 and the fix review's I-b, the way out: restoring again over a
    /// course folder with no settings (what a stop leaves) keeps what is in
    /// it first, since no archive covers a folder the sidebar does not
    /// list; in a folder named for what it is, not a stop's; and the
    /// teacher is told where. The confirmation said it "moves to Archived";
    /// it says what happens. MUST FAIL on db38ed112: no sentence, the
    /// stop's name, and the Archived paragraph.
    func testRestoringAgainOverAFolderWithNoSettingsKeepsWhatIsInIt() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try FileManager.default.removeItem(at: fixture.courseURL.appendingPathComponent("course_config.json"))
        try WholeCourseFixture.write("written after the stop\n", to: fixture.courseURL.appendingPathComponent("Concepts/After the stop.md"))
        var asItWas: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        let liveGit: Data? = asItWas[".git/HEAD"]
        asItWas[".git/HEAD"] = nil
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        XCTAssertNil(WholeCourseRestoreDoorTests.course("ICS3U", in: workspace), "a folder with no settings is not a course")
        let item: BackupItem = try WholeCourseRestoreDoorTests.backup(fixture)
        XCTAssertEqual(
            workspace.wholeCourseRestoreConfirmation(for: item), RestoreWholeCourseWording.confirmKeptWithItsBackups(course: "ICS3U")
        )

        await workspace.restoreBackup(item)

        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), fixture.backupWithWhatIsKeptInPlace(liveGit: liveGit))
        XCTAssertEqual(try fixture.everythingKept(), asItWas, "everything that was in the folder is kept, and nothing else")
        let shelf: URL = fixture.coursesDirectoryURL.appendingPathComponent("_backups/ICS3U")
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: shelf.path)
        XCTAssertEqual(names.count, 1)
        let keptName: String = names.first ?? ""
        XCTAssertTrue(keptName.hasPrefix("ICS3U as it was before restoring again "), keptName)
        XCTAssertFalse(keptName.hasPrefix("ICS3U before a restore"), "never the stop's own name")
        XCTAssertEqual(workspace.backupProblemTitle, RestoreWholeCourseWording.restoredTitle(course: "ICS3U"))
        XCTAssertEqual(
            workspace.backupProblem,
            RestoreWholeCourseWording.keptWhatWasInTheFolder(course: "ICS3U", keptAt: "courses/_backups/ICS3U/" + keptName)
        )
        XCTAssertNil(BackupItem.from(fileURL: shelf.appendingPathComponent(keptName), courseCode: "ICS3U"), "it is not a backup")
        XCTAssertTrue(fixture.trailText().contains("a whole-course restore kept files instead of removing them"), fixture.trailText())
    }

    /// I-b: the confirmation says what truly happens, by the same test the
    /// door makes before it archives.
    func testTheConfirmationSaysWhatHappensToTheCourseAsItIs() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        let item: BackupItem = try WholeCourseRestoreDoorTests.backup(fixture)
        XCTAssertEqual(workspace.wholeCourseRestoreConfirmation(for: item), RestoreWholeCourseWording.confirmArchived)
        try FileManager.default.removeItem(at: fixture.courseURL)
        workspace.reloadCourses()
        XCTAssertEqual(workspace.wholeCourseRestoreConfirmation(for: item), RestoreWholeCourseWording.confirmNoCourseFolder(course: "ICS3U"))
    }

    // MARK: - Helpers

    /// A window's model on the fixture's working folder.
    static func openWorkspace(on fixture: WholeCourseFixture) throws -> WorkspaceModel {
        // What makes a folder a working folder to `reloadCourses`.
        try Data("#!/bin/bash\n".utf8).write(to: fixture.rootURL.appendingPathComponent("preview.sh"))
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: fixture.rootURL)
        workspace.reloadCourses()
        return workspace
    }

    static func backup(_ fixture: WholeCourseFixture) throws -> BackupItem {
        return try XCTUnwrap(BackupItem.from(fileURL: fixture.zipURL, courseCode: "ICS3U"))
    }

    static func course(_ code: String, in workspace: WorkspaceModel) -> Course? {
        for course in workspace.courses where course.code == code {
            return course
        }
        return nil
    }
}
