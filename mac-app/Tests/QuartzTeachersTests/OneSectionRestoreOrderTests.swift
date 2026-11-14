import XCTest
@testable import QuartzTeachers

/// The order of work around Restore from Backup…'s "Restore Section N"
/// (#897 C, implementation review INCOMPLETE 4): what is offered, the whole
/// course archived FIRST, and every refusal leaving the course and Archived
/// as they were. Through `WorkspaceModel`, the way the alert calls it.
@MainActor
final class OneSectionRestoreOrderTests: XCTestCase {

    // MARK: - Functions

    /// A working folder with ICS3U (Section 1) open in a workspace, the
    /// trail pointed at a folder of its own, and a page to change.
    private func makeWorkspace() throws -> (root: URL, workspace: WorkspaceModel, course: Course, page: URL) {
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
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "Original.", in: made.course)
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: made.root)
        var found: Course? = nil
        for candidate in workspace.courses where candidate.code == "ICS3U" {
            found = candidate
        }
        let course: Course = try XCTUnwrap(found)
        return (made.root, workspace, course, AssistFixture.pageURL(of: "Unit 1, Day 1", in: course))
    }

    private func menuBackup(of course: Course, root: URL) async throws -> BackupItem {
        let url: URL = try await CourseArchiver.backUpCourse(
            course, coursesDirectoryURL: root.appendingPathComponent("courses"), madeBy: .menu(sectionNumber: 1)
        )
        return try XCTUnwrap(BackupItem.from(fileURL: url, courseCode: "ICS3U"))
    }

    private func archiveCount(_ root: URL) -> Int {
        return WorkspaceModel.findArchivedItems(in: root.appendingPathComponent("courses")).count
    }

    // MARK: - What is offered

    /// The Section menu's backup offers its section; a teacher's own does
    /// not; and the request works the offer out once, when it is set.
    func testTheOfferIsWorkedOutWhenTheRequestIsSet() async throws {
        let (root, workspace, course, _) = try makeWorkspace()
        let menuItem: BackupItem = try await menuBackup(of: course, root: root)
        let teacherURL: URL = try await CourseArchiver.backUpCourse(
            course, coursesDirectoryURL: root.appendingPathComponent("courses")
        )
        let teacherItem: BackupItem = try XCTUnwrap(BackupItem.from(fileURL: teacherURL, courseCode: "ICS3U"))

        workspace.backupRestoreRequest = menuItem
        XCTAssertEqual(workspace.backupRestoreOfferedSection, 1)
        workspace.backupRestoreRequest = teacherItem
        XCTAssertNil(workspace.backupRestoreOfferedSection)
        workspace.backupRestoreRequest = nil
        XCTAssertNil(workspace.backupRestoreOfferedSection)
    }

    /// An unfinished rename, or a section folder that is not there, takes
    /// the offer away.
    func testAnUnfinishedRenameOrAMissingFolderIsNotOffered() async throws {
        let (root, workspace, course, _) = try makeWorkspace()
        let item: BackupItem = try await menuBackup(of: course, root: root)
        let marker: URL = UnitWordRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: marker, atomically: true, encoding: .utf8)
        XCTAssertNil(workspace.oneSectionRestoreOffer(for: item))
        try FileManager.default.removeItem(at: marker)
        XCTAssertEqual(workspace.oneSectionRestoreOffer(for: item), 1)

        let aside: URL = root.appendingPathComponent("section1-aside")
        try FileManager.default.moveItem(at: course.sectionDirectoryURL(forSection: 1), to: aside)
        XCTAssertNil(workspace.oneSectionRestoreOffer(for: item), "a section whose folder is gone")
    }

    // MARK: - The order of work

    /// The whole course is archived first, then the section comes back, the
    /// trail says so, and the finished line is shown.
    func testTheCourseIsArchivedFirstAndTheSectionComesBack() async throws {
        let (root, workspace, course, page) = try makeWorkspace()
        let item: BackupItem = try await menuBackup(of: course, root: root)
        try "Changed since.".write(to: page, atomically: true, encoding: .utf8)
        XCTAssertEqual(archiveCount(root), 0)

        await workspace.restoreOneSection(1, from: item)

        XCTAssertEqual(archiveCount(root), 1, "the whole course as it was is in Archived")
        XCTAssertFalse(try String(contentsOf: page, encoding: .utf8).contains("Changed since."))
        XCTAssertEqual(workspace.backupProblemTitle, OneSectionRestoreWording.doneTitle(section: 1, course: "ICS3U"))
        XCTAssertTrue(ActivityTrail.store.activityText(includingPrompts: true)
            .contains("put the section back from " + item.fileURL.lastPathComponent))
    }

    /// A course previewing or deploying is refused BEFORE anything is
    /// archived, and nothing is written on the trail.
    func testABusyCourseIsRefusedBeforeTheArchive() async throws {
        let (root, workspace, course, page) = try makeWorkspace()
        let item: BackupItem = try await menuBackup(of: course, root: root)
        try "Changed since.".write(to: page, atomically: true, encoding: .utf8)
        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        defer { CourseActivity.endPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1) }

        await workspace.restoreOneSection(1, from: item)

        XCTAssertEqual(workspace.backupProblem,
                       "ICS3U is previewing or deploying right now. Stop that first, then restore.")
        XCTAssertEqual(archiveCount(root), 0, "a refused click leaves nothing in Archived")
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), "Changed since.")
        XCTAssertFalse(ActivityTrail.store.activityText(includingPrompts: true).contains("put the section back"))
    }

    /// A section the Section menu is changing right now is refused, before
    /// the archive.
    func testASectionBeingChangedIsRefused() async throws {
        let (root, workspace, course, page) = try makeWorkspace()
        let item: BackupItem = try await menuBackup(of: course, root: root)
        try "Changed since.".write(to: page, atomically: true, encoding: .utf8)
        SectionMenuActivity.begin(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        defer { SectionMenuActivity.end(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1) }

        await workspace.restoreOneSection(1, from: item)

        XCTAssertEqual(workspace.backupProblem, OneSectionRestoreWording.busy(section: 1, course: "ICS3U"))
        XCTAssertEqual(archiveCount(root), 0)
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), "Changed since.")
    }

    /// A rename that became unfinished after the alert opened is asked again
    /// at the click, before the archive.
    func testAnUnfinishedRenameIsAskedAgainAtTheClick() async throws {
        let (root, workspace, course, page) = try makeWorkspace()
        let item: BackupItem = try await menuBackup(of: course, root: root)
        workspace.backupRestoreRequest = item
        XCTAssertEqual(workspace.backupRestoreOfferedSection, 1)
        let marker: URL = UnitWordRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: marker, atomically: true, encoding: .utf8)
        try "Changed since.".write(to: page, atomically: true, encoding: .utf8)

        await workspace.restoreOneSection(1, from: item)

        XCTAssertEqual(workspace.backupProblem, OneSectionRestoreWording.renameUnfinished(section: 1, course: "ICS3U"))
        XCTAssertEqual(archiveCount(root), 0)
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), "Changed since.")
    }

    /// The course's word for a unit changed on disk since the backup (no
    /// reload in between, as after a build): refused with the naming
    /// sentence BEFORE anything is archived.
    func testANamingChangeIsRefusedBeforeTheArchive() async throws {
        let (root, workspace, course, page) = try makeWorkspace()
        let item: BackupItem = try await menuBackup(of: course, root: root)
        let configData: Data = try Data(contentsOf: course.configFileURL)
        var values: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: configData) as? [String: Any])
        values["unit_word"] = "Module"
        try JSONSerialization.data(withJSONObject: values).write(to: course.configFileURL)
        try "Changed since.".write(to: page, atomically: true, encoding: .utf8)

        await workspace.restoreOneSection(1, from: item)

        XCTAssertEqual(workspace.backupProblem, OneSectionRestoreWording.namingChanged(section: 1, course: "ICS3U"))
        XCTAssertEqual(archiveCount(root), 0)
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), "Changed since.")
    }

    /// A backup that has no folder for the section (made before the section
    /// existed) is refused BEFORE anything is archived.
    func testASectionMissingFromTheBackupIsRefusedBeforeTheArchive() async throws {
        let (root, workspace, course, _) = try makeWorkspace()
        let url: URL = try await CourseArchiver.backUpCourse(
            course, coursesDirectoryURL: root.appendingPathComponent("courses"), madeBy: .menu(sectionNumber: 2)
        )
        let item: BackupItem = try XCTUnwrap(BackupItem.from(fileURL: url, courseCode: "ICS3U"))
        // Section 2 is added after the backup.
        try FileManager.default.createDirectory(
            at: course.sectionDirectoryURL(forSection: 2), withIntermediateDirectories: true
        )
        let configData: Data = try Data(contentsOf: course.configFileURL)
        var values: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: configData) as? [String: Any])
        values["section_numbers"] = [1, 2]
        values["num_sections"] = 2
        try JSONSerialization.data(withJSONObject: values).write(to: course.configFileURL)
        workspace.reloadCourses()

        await workspace.restoreOneSection(2, from: item)

        XCTAssertEqual(
            workspace.backupProblem,
            CourseRestorer.Problem.sectionMissingFromBackup("ICS3U", 2).localizedDescription
        )
        XCTAssertEqual(archiveCount(root), 0)
    }

    /// A publish that begins DURING the archive is refused after it, and the
    /// section is not touched (the archive stays: it is a copy, harmless).
    func testAPublishThatBeganDuringTheArchiveIsRefusedAfterIt() async throws {
        let (root, workspace, course, page) = try makeWorkspace()
        let item: BackupItem = try await menuBackup(of: course, root: root)
        try "Changed since.".write(to: page, atomically: true, encoding: .utf8)

        let restoring: Task<Void, Never> = Task { @MainActor in
            await workspace.restoreOneSection(1, from: item)
        }
        var turns: Int = 0
        while !workspace.isBeingCopied("ICS3U") && turns < 10_000 {
            turns += 1
            await Task.yield()
        }
        XCTAssertTrue(workspace.isBeingCopied("ICS3U"), "the archive never started")
        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        defer { CourseActivity.endPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1) }
        await restoring.value

        XCTAssertEqual(workspace.backupProblem,
                       "ICS3U is previewing or deploying right now. Stop that first, then restore.")
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), "Changed since.")
    }
}
