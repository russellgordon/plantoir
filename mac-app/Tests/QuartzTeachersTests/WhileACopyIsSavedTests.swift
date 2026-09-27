import XCTest
@testable import QuartzTeachers

/// While a copy of a course is being zipped, nothing changes the course under
/// it (#351's review, S1).
///
/// The zip runs off the main actor now, so the window stays live for the
/// minute it can take. Before, the frozen main thread made every one of these
/// impossible; now each is refused by a record of the copy
/// (`CourseActivity.beginCopy`), and a restore asks again, after its zip,
/// whether a preview or publish began meanwhile.
///
/// The interleaving is deterministic, not a race: the work under test runs on
/// the main actor until its zip, and cannot resume until this test suspends —
/// so what the test does between "the copy has started" and its own await
/// happens, reliably, during the zip.
@MainActor
final class WhileACopyIsSavedTests: XCTestCase {

    // MARK: - Setting up

    override func setUp() async throws {
        try await super.setUp()
        CourseActivity.reset()
    }

    override func tearDown() async throws {
        CourseActivity.reset()
        try await super.tearDown()
    }

    private func makeWorkspace() throws -> (root: URL, workspace: WorkspaceModel, course: Course) {
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
        return (made.root, workspace, try XCTUnwrap(found))
    }

    /// Lets the task under test run up to its zip.
    private func waitForTheCopyToStart(in workspace: WorkspaceModel) async {
        var turns: Int = 0
        while !workspace.isBeingCopied("ICS3U") && turns < 10_000 {
            turns += 1
            await Task.yield()
        }
        XCTAssertTrue(workspace.isBeingCopied("ICS3U"), "the copy never started")
    }

    // MARK: - Tests

    func testTheCourseCountsAsBeingCopiedOnlyWhileItsZipRuns() async throws {
        let (_, workspace, course) = try makeWorkspace()
        XCTAssertFalse(workspace.isBeingCopied("ICS3U"))
        let backingUp: Task<Void, Never> = Task { @MainActor in
            await workspace.backUp(course)
        }
        await waitForTheCopyToStart(in: workspace)
        XCTAssertEqual(QuitConfirmation.workUnderWay(), "saving a copy of ICS3U", "⌘Q asks while it runs")
        await backingUp.value
        XCTAssertFalse(workspace.isBeingCopied("ICS3U"), "and stops counting when it is done")
        XCTAssertNil(QuitConfirmation.workUnderWay())
    }

    func testASecondBackUpWhileTheFirstIsSavingMakesNoSecondCopy() async throws {
        let (root, workspace, course) = try makeWorkspace()
        let first: Task<Void, Never> = Task { @MainActor in
            await workspace.backUp(course)
        }
        await waitForTheCopyToStart(in: workspace)
        await workspace.backUp(course)
        await first.value
        let backups: [BackupItem] = WorkspaceModel.findBackupItems(in: root.appendingPathComponent("courses"))
        XCTAssertEqual(backups.count, 1, "a second press during the zip made a second full copy")
    }

    func testARestoreRefusesAPreviewOrPublishThatBeganDuringItsZip() async throws {
        let (root, workspace, course) = try makeWorkspace()
        let coursesURL: URL = root.appendingPathComponent("courses")
        try await CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesURL)
        let item: BackupItem = try XCTUnwrap(WorkspaceModel.findBackupItems(in: coursesURL).first)
        let pageURL: URL = AssistFixture.pageURL(of: "Unit 1, Day 1", in: course)
        try "Changed since.".write(to: pageURL, atomically: true, encoding: .utf8)

        let restoring: Task<Void, Never> = Task { @MainActor in
            await workspace.restoreBackup(item)
        }
        await waitForTheCopyToStart(in: workspace)
        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        await restoring.value

        XCTAssertEqual(
            workspace.backupProblem,
            "ICS3U is previewing or deploying right now. Stop that first, then restore."
        )
        XCTAssertEqual(try String(contentsOf: pageURL, encoding: .utf8), "Changed since.",
                       "the course was replaced under a publish that began during the zip")
    }

    func testAReferenceCourseIsUnlockedOnlyAfterItsArchiveIsMade() async throws {
        let (root, _, course) = try makeWorkspace()
        let coursesURL: URL = root.appendingPathComponent("courses")
        var archivesWhenUnlocking: Int = -1
        try await CourseArchiver.archiveAndRemoveCourse(course, coursesDirectoryURL: coursesURL) {
            let archives: [String] = (try? FileManager.default.contentsOfDirectory(
                atPath: coursesURL.appendingPathComponent("_backups/ICS3U").path
            )) ?? []
            archivesWhenUnlocking = archives.count
        }
        XCTAssertEqual(archivesWhenUnlocking, 1, "the course was unlocked before its archive existed")
    }
}
