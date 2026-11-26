import XCTest
@testable import QuartzTeachers

/// A restore and a Rename folder of the same course never work on it at once
/// (#909, the review after the merge of `dev`, HIGH 1).
///
/// On `dev`, `restoreBackup` asked `structuralRefusal`, which refuses first
/// while a Rename folder of the course is under way (#899 U4b). #909's
/// `wholeCourseRestoreRefusal` replaced those calls and did not ask, and the
/// merge dropped the check without a conflict: with a second window open,
/// the rename's off-main swap and the restore could both work on the course.
///
/// Every restore route is asked here through the entry its control calls,
/// with a rename's claim held in `CourseActivity` exactly as the rename sheet
/// holds it; the other direction asks `FolderRenameRun.swapBegins`, the one
/// place a rename passes from planning to swapping.
@MainActor
final class RestoreDuringAFolderRenameTests: XCTestCase {

    // MARK: - Functions: set up

    override func setUp() async throws {
        CourseActivity.reset()
    }

    override func tearDown() async throws {
        CourseActivity.reset()
    }

    // MARK: - Functions: every restore route refuses during a rename

    /// Restore from Backup…'s whole course, while the rename only plans and
    /// once its swap has begun: refused before the archive, nothing changed,
    /// nothing archived, the rename's own sentence, and the trail says why.
    /// MUST FAIL on cb61de8c5, where `wholeCourseRestoreRefusal` did not ask.
    func testAWholeCourseRestoreIsRefusedWhileAFolderOfTheCourseIsRenamed() async throws {
        for swapHasBegun in [false, true] {
            let fixture: WholeCourseFixture = try WholeCourseFixture()
            defer { fixture.tearDown() }
            let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
            let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
            let claim: CourseActivity.FolderRenameRecord = try XCTUnwrap(RestoreDuringAFolderRenameTests.claim(workspace))
            if swapHasBegun {
                XCTAssertTrue(FolderRenameRun.swapBegins(claim))
            }

            await workspace.restoreBackup(try WholeCourseRestoreDoorTests.backup(fixture))

            let label: String = swapHasBegun ? "swapping" : "planning"
            XCTAssertEqual(workspace.backupProblem, CourseActivity.folderRenameIsUnderWay(course: "ICS3U"), label)
            XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live, "nothing changed (\(label))")
            XCTAssertEqual(RestoreDuringAFolderRenameTests.archives(fixture), [], "nothing archived (\(label))")
            XCTAssertEqual(fixture.leftInRestoring(), 0, label)
            XCTAssertTrue(
                fixture.trailText().contains(WholeCourseRestore.DidNotGoAhead.folderRename.rawValue),
                fixture.trailText()
            )
            XCTAssertTrue(CourseActivity.courseIsRenamingAFolder(
                folderPath: claim.folderPath, courseCode: "ICS3U"
            ), "the restore does not halt the rename (\(label))")
            CourseActivity.endFolderRename(claim)
        }
    }

    /// The whole course's refusal after the archive and before the swap asks
    /// the same facts: a rename that begins during the archive's zip is
    /// counted then too (`wholeCourseRestoreRefusal` is the one question).
    func testTheWholeCourseRefusalCountsARenameFirst() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        XCTAssertNil(workspace.wholeCourseRestoreRefusal(courseCode: "ICS3U", ownStaging: nil))
        let claim: CourseActivity.FolderRenameRecord = try XCTUnwrap(RestoreDuringAFolderRenameTests.claim(workspace))
        defer { CourseActivity.endFolderRename(claim) }
        let refused = try XCTUnwrap(workspace.wholeCourseRestoreRefusal(courseCode: "ICS3U", ownStaging: nil))
        XCTAssertEqual(refused.refusal, WholeCourseRestore.Refusal.folderRenameUnderWay)
        XCTAssertEqual(refused.sentence, CourseActivity.folderRenameIsUnderWay(course: "ICS3U"))
    }

    /// Restore from Backup…'s Restore Section N: refused, nothing archived.
    func testAOneSectionRestoreFromTheMenuIsRefusedWhileAFolderIsRenamed() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        let claim: CourseActivity.FolderRenameRecord = try XCTUnwrap(RestoreDuringAFolderRenameTests.claim(workspace))
        defer { CourseActivity.endFolderRename(claim) }

        await workspace.restoreOneSection(1, from: try WholeCourseRestoreDoorTests.backup(fixture))

        XCTAssertEqual(workspace.backupProblem, CourseActivity.folderRenameIsUnderWay(course: "ICS3U"))
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live)
        XCTAssertEqual(RestoreDuringAFolderRenameTests.archives(fixture), [])
    }

    /// Restore from Archive… (File menu, the sidebar's row, the detail's
    /// button: all call `restore(_:)`): refused, the archive untouched.
    func testARestoreFromArchivedIsRefusedWhileAFolderIsRenamed() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        let course: Course = try XCTUnwrap(WholeCourseRestoreDoorTests.course("ICS3U", in: workspace))
        let archiveURL: URL = try await CourseArchiver.archiveCourse(course, coursesDirectoryURL: fixture.coursesDirectoryURL)
        let archived: ArchivedItem = try XCTUnwrap(ArchivedItem.from(fileURL: archiveURL, courseCode: "ICS3U"))
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        let claim: CourseActivity.FolderRenameRecord = try XCTUnwrap(RestoreDuringAFolderRenameTests.claim(workspace))
        defer { CourseActivity.endFolderRename(claim) }

        workspace.restore(archived)

        XCTAssertEqual(workspace.restoreProblem, CourseActivity.folderRenameIsUnderWay(course: "ICS3U"))
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live)
        XCTAssertTrue(RestoreSwap.itemExists(at: archiveURL), "the archive is not used up")
    }

    /// The assistant window's Restore Section N…: refused before anything
    /// moves, with the rename's sentence.
    func testTheAssistantsSectionRestoreIsRefusedWhileAFolderIsRenamed() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        XCTAssertFalse(AssistSectionRestore.waitsForARename(
            courseCode: "ICS3U", coursesDirectoryURL: fixture.coursesDirectoryURL
        ))
        let claim: CourseActivity.FolderRenameRecord = try XCTUnwrap(RestoreDuringAFolderRenameTests.claim(workspace))
        defer { CourseActivity.endFolderRename(claim) }
        XCTAssertTrue(AssistSectionRestore.waitsForARename(
            courseCode: "ICS3U", coursesDirectoryURL: fixture.coursesDirectoryURL
        ))

        XCTAssertThrowsError(try AssistSectionRestore.restore(
            backupURL: fixture.zipURL, courseCode: "ICS3U", sectionNumber: 1,
            coursesDirectoryURL: fixture.coursesDirectoryURL
        )) { error in
            XCTAssertEqual(error.localizedDescription, CourseActivity.folderRenameIsUnderWay(course: "ICS3U"))
        }
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live)
    }

    // MARK: - Functions: a rename's swap refuses during a restore

    /// While a whole-course restore holds the course, a rename planned
    /// meanwhile cannot pass to its swap, and its claim is left unmarked;
    /// once the restore ends, it can.
    func testARenamesSwapIsRefusedWhileTheCourseIsBeingRestored() throws {
        let folderPath: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("rename-during-restore-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folderPath) }
        let claim: CourseActivity.FolderRenameRecord = try XCTUnwrap(
            CourseActivity.beginFolderRename(folderPath: folderPath, courseCode: "ICS3U")
        )
        defer { CourseActivity.endFolderRename(claim) }

        CourseActivity.beginRestore(folderPath: folderPath, courseCode: "ICS3U")
        XCTAssertTrue(CourseActivity.courseIsBeingRestored(folderPath: folderPath, courseCode: "ICS3U"))
        XCTAssertFalse(FolderRenameRun.swapBegins(claim), "no swap while the course is being restored")
        XCTAssertFalse(CourseActivity.folderRenameIsSwapping(folderPath: folderPath, courseCode: "ICS3U"))
        // Another course's restore does not hold this one.
        CourseActivity.endRestore(folderPath: folderPath, courseCode: "ICS3U")
        CourseActivity.beginRestore(folderPath: folderPath, courseCode: "MPM2D")
        XCTAssertTrue(FolderRenameRun.swapBegins(claim), "another course's restore holds nothing here")
        CourseActivity.endRestore(folderPath: folderPath, courseCode: "MPM2D")
    }

    // MARK: - Functions: the commands are disabled

    /// The restore commands' disabled state reads the same model state: the
    /// sidebar's, the window's and All Backups' Restore… for a backup, the
    /// archived row's, and the Course and File menus' items through
    /// `SubjectMenuRules` with the row's `structuralHold`.
    func testTheRestoreCommandsWaitWhileAFolderIsRenamed() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        XCTAssertFalse(workspace.restoreOfABackupWaits("ICS3U"))
        XCTAssertFalse(workspace.restoreFromArchivedWaits("ICS3U"))
        let claim: CourseActivity.FolderRenameRecord = try XCTUnwrap(RestoreDuringAFolderRenameTests.claim(workspace))
        XCTAssertTrue(workspace.restoreOfABackupWaits("ICS3U"))
        XCTAssertTrue(workspace.restoreFromArchivedWaits("ICS3U"))
        XCTAssertFalse(workspace.restoreOfABackupWaits("MPM2D"), "another course is free")

        var backupRow: SubjectMenuRules.Situation = SubjectMenuRules.Situation()
        backupRow.hasFolder = true
        backupRow.row = .backup
        XCTAssertTrue(SubjectMenuRules.enabledItems(backupRow).contains(.restoreFromBackup))
        backupRow.structuralHold = workspace.restoreOfABackupWaits("ICS3U")
        XCTAssertFalse(SubjectMenuRules.enabledItems(backupRow).contains(.restoreFromBackup))

        var archivedRow: SubjectMenuRules.Situation = SubjectMenuRules.Situation()
        archivedRow.hasFolder = true
        archivedRow.row = .archived
        XCTAssertTrue(SubjectMenuRules.enabledItems(archivedRow).contains(.restoreFromArchive))
        archivedRow.structuralHold = workspace.restoreFromArchivedWaits("ICS3U")
        XCTAssertFalse(SubjectMenuRules.enabledItems(archivedRow).contains(.restoreFromArchive))

        CourseActivity.endFolderRename(claim)
        XCTAssertFalse(workspace.restoreOfABackupWaits("ICS3U"), "live again once the rename ends")
        XCTAssertFalse(workspace.restoreFromArchivedWaits("ICS3U"))
    }

    // MARK: - Functions: a record left by an interrupted rename

    /// The director's decision of 2026-11-26: a record left on disk by a
    /// rename that was killed earlier (no claim is held, so nothing is under
    /// way) does not refuse a whole-course restore, and the restore KEEPS it
    /// byte for byte (`RenameRecordClaim.aWholeCourseRestoreReplacedTheCourse`).
    /// The rename's reader checks a record against the disk, so a record the
    /// restored course does not match offers nothing, and one it still
    /// matches (a backup made after the kill holds the half-renamed folders)
    /// lets the teacher finish the rename from the sheet.
    func testARecordLeftByAnInterruptedRenameIsKeptByAWholeCourseRestore() async throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let workspace: WorkspaceModel = try WholeCourseRestoreDoorTests.openWorkspace(on: fixture)
        SpecialFolderRenamer.recordRenameStarting(
            from: "Concepts", to: "Ideas", scope: .shared, courseDirectory: fixture.courseURL, moved: ["Concepts"]
        )
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: fixture.courseURL)
        let recordBefore: Data = try Data(contentsOf: record)

        await workspace.restoreBackup(try WholeCourseRestoreDoorTests.backup(fixture))

        XCTAssertNil(workspace.backupProblem, workspace.backupProblem ?? "")
        XCTAssertEqual(try? Data(contentsOf: record), recordBefore, "the record is kept byte for byte")
        XCTAssertNil(
            SpecialFolderRenamer.interruptedRenameTarget(
                from: "Concepts", scope: .shared, courseDirectory: fixture.courseURL, sectionNumbers: [1]
            ),
            "the restored course still has Concepts, so the record offers nothing"
        )
        try FileManager.default.moveItem(
            at: fixture.courseURL.appendingPathComponent("Concepts"), to: fixture.courseURL.appendingPathComponent("Ideas")
        )
        XCTAssertEqual(
            SpecialFolderRenamer.interruptedRenameTarget(
                from: "Concepts", scope: .shared, courseDirectory: fixture.courseURL, sectionNumbers: [1]
            ),
            "Ideas",
            "a course left half renamed still offers to finish the rename"
        )
    }

    // MARK: - Helpers

    /// A Rename folder's claim on ICS3U, as the rename sheet takes it.
    static func claim(_ workspace: WorkspaceModel) -> CourseActivity.FolderRenameRecord? {
        guard let folderPath = workspace.workspaceURL?.path else {
            return nil
        }
        return CourseActivity.beginFolderRename(folderPath: folderPath, courseCode: "ICS3U")
    }

    /// Every zip under `courses/`, by file name: the fixture's backup sits
    /// beside `courses/`, so any zip here is an archive a restore made.
    static func archives(_ fixture: WholeCourseFixture) -> [String] {
        var zips: [String] = []
        guard let walk = FileManager.default.enumerator(atPath: fixture.coursesDirectoryURL.path) else {
            return zips
        }
        while let path = walk.nextObject() as? String {
            if path.hasSuffix(".zip") {
                zips.append(path)
            }
        }
        return zips.sorted()
    }
}
