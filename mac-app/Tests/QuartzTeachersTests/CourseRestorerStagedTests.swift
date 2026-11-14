import XCTest
@testable import QuartzTeachers

/// A whole-course restore through `CourseRestorer.restoreBackup`, the door
/// every whole-course restore goes through (#909). Each test is a fault the
/// old in-place restore reported, or reported as success, measured in the
/// #909 plan's 1.2; each is proven red on the old restore body.
final class CourseRestorerStagedTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testAReadOnlyFolderAtTheTopLeavesTheCourseAsItWas() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        XCTAssertEqual(chmod(fixture.courseURL.appendingPathComponent("Concepts").path, 0o555), 0)
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        XCTAssertThrowsError(try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                RestoreWholeCourseWording.leftAsItWasLocked(course: "ICS3U", name: "Concepts") + " " + RestoreWholeCourseWording.unlockIt
            )
        }
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live, "the old restore emptied the course up to Concepts")
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    @MainActor
    func testALockedFileAtTheTopLeavesTheCourseAsItWas() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        XCTAssertEqual(lchflags(fixture.courseURL.appendingPathComponent("index.md").path, UInt32(UF_IMMUTABLE)), 0)
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        XCTAssertThrowsError(try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL))
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live)
        XCTAssertTrue(RestoreSwap.itemExists(at: fixture.courseURL.appendingPathComponent("course_config.json")),
                      "the course is still in the sidebar")
    }

    @MainActor
    func testALockedPageInsideStillRestoresAndLeavesNothingStaged() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let page: URL = fixture.courseURL.appendingPathComponent("section1/All Classes/Unit 1, Day 1.md")
        XCTAssertEqual(lchflags(page.path, UInt32(UF_IMMUTABLE)), 0)
        let liveGit: Data = try Data(contentsOf: fixture.courseURL.appendingPathComponent(".git/HEAD"))

        // As the door runs it, with the course archived first: without an
        // archive the old copy is kept rather than removed (the
        // implementation review's I1), and this is about the removal.
        try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, archiveURL: fixture.zipURL
        )

        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), fixture.backupWithWhatIsKeptInPlace(liveGit: liveGit))
        XCTAssertEqual(fixture.leftInRestoring(), 0, "the old copy is unlocked on its way out")
        XCTAssertFalse(fixture.somethingWasKept(), "with an archive made first, the old copy is removed, not kept")
    }

    @MainActor
    func testWhatBackupsLeaveOutStaysWhereItIs() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)
        XCTAssertEqual(
            try String(contentsOf: fixture.courseURL.appendingPathComponent(".git/HEAD"), encoding: .utf8),
            "ref: refs/heads/main\n",
            "the old restore deleted .git, which is in neither the backup nor the archive"
        )
        XCTAssertEqual(try String(contentsOf: fixture.courseURL.appendingPathComponent("index.md"), encoding: .utf8), "BACKUP front page\n")
    }

    @MainActor
    func testARenameRecordSurvivesARestoreLeftAsItWas() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try UnitWordRenamer.recordRenameStarting(from: "Unit", to: "Module", courseDirectory: fixture.courseURL)
        let record: URL = UnitWordRenamer.renameMarkerURL(courseDirectory: fixture.courseURL)
        XCTAssertTrue(RestoreSwap.itemExists(at: record))
        XCTAssertEqual(chmod(fixture.courseURL.appendingPathComponent("section1").path, 0o555), 0)

        XCTAssertThrowsError(try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL))
        XCTAssertTrue(RestoreSwap.itemExists(at: record), "a restore that did not happen must not clear the record of a rename under way")
    }

    @MainActor
    func testASmallBackupIsRefusedUntilItsMediaIsPutBack() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture(smallBackupMarker: true)
        defer { fixture.tearDown() }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        XCTAssertThrowsError(try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                SharedMediaStore.Problem.mediaNotPutBack(fixture.zipURL.lastPathComponent).localizedDescription
            )
        }
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live, "the old restore deleted Media and said nothing")
    }

    @MainActor
    func testAnArrivalIsStagedBesideTheCourses() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try FileManager.default.removeItem(at: fixture.courseURL)
        var parents: [String] = []
        let hooks: RestoreSwap.Hooks = RestoreSwap.Hooks(
            step: { (_: String) throws in
            },
            move: { (source: URL, destination: URL) throws in
                parents.append(source.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)
                try FileManager.default.moveItem(at: source, to: destination)
            },
            moveBack: { (source: URL, destination: URL) throws in
                try FileManager.default.moveItem(at: source, to: destination)
            },
            flushes: false
        )
        try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: hooks)
        XCTAssertEqual(parents, ["restoring"], "one move, from courses/.internal/restoring/<id>/backup/")
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), fixture.backupFiles)
    }

    /// The walk that unlocks the old copy before removing it never follows
    /// a link (the plan review, M7): a locked file in a folder OUTSIDE the
    /// course, reached through a link in the old copy, stays locked and in
    /// place.
    func testTheUnlockingRemovalNeverFollowsALink() throws {
        let root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("unlock-walk-\(UUID().uuidString)")
        let outside: URL = root.appendingPathComponent("outside")
        let old: URL = root.appendingPathComponent("as-it-was")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let precious: URL = outside.appendingPathComponent("precious.md")
        try Data("keep\n".utf8).write(to: precious)
        XCTAssertEqual(lchflags(precious.path, UInt32(UF_IMMUTABLE)), 0)
        try FileManager.default.createSymbolicLink(at: old.appendingPathComponent("link"), withDestinationURL: outside)
        defer {
            _ = lchflags(precious.path, 0)
            try? FileManager.default.removeItem(at: root)
        }

        XCTAssertTrue(RestoreSwap.removeUnlocking(old))

        var status: stat = stat()
        XCTAssertEqual(lstat(precious.path, &status), 0, "the file behind the link is still there")
        XCTAssertNotEqual(status.st_flags & UInt32(UF_IMMUTABLE), 0, "and still locked")
    }

    // MARK: - Helpers

    @MainActor
    private func item(_ fixture: WholeCourseFixture) throws -> BackupItem {
        return try XCTUnwrap(BackupItem.from(fileURL: fixture.zipURL, courseCode: "ICS3U"))
    }
}
