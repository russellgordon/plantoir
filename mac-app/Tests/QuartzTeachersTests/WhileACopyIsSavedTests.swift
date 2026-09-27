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

    /// Two copies begun in the same second share a name, so a second zip
    /// would ADD to the first rather than show as a second file — the
    /// copy under way is recorded by hand here, and the press must make
    /// nothing at all.
    func testBackUpNowWhileACopyIsSavingMakesNone() async throws {
        let (root, workspace, course) = try makeWorkspace()
        CourseActivity.beginCopy(folderPath: root.path, courseCode: "ICS3U")
        await workspace.backUp(course)
        XCTAssertEqual(WorkspaceModel.findBackupItems(in: root.appendingPathComponent("courses")).count, 0,
                       "a second press during a zip made a second copy")
        CourseActivity.endCopy(folderPath: root.path, courseCode: "ICS3U")
        await workspace.backUp(course)
        XCTAssertEqual(WorkspaceModel.findBackupItems(in: root.appendingPathComponent("courses")).count, 1)
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

    // MARK: - Every busy reader sees the copy (the second review, SF1)

    func testACopyMakesTheCourseBusyForEveryReader() throws {
        let (root, _, _) = try makeWorkspace()
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: root.path, courseCode: "ICS3U"))
        CourseActivity.beginCopy(folderPath: root.path, courseCode: "ICS3U")
        XCTAssertTrue(CourseActivity.courseIsBusy(folderPath: root.path, courseCode: "ICS3U"))
        XCTAssertEqual(
            CourseActivity.busyDescription(folderPath: root.path, courseCode: "ICS3U"),
            CourseActivity.availableOnceTheCopyIsSaved
        )
        CourseActivity.endCopy(folderPath: root.path, courseCode: "ICS3U")
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: root.path, courseCode: "ICS3U"))
    }

    /// The assistant's preview refuses BEFORE stopping anything: the window's
    /// own Preview refuses during a copy, so a stop first would end a running
    /// preview and start nothing.
    func testTheAssistantsPreviewRefusesWhileACopyIsSaved() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        CourseActivity.beginCopy(folderPath: made.root.path, courseCode: "ICS3U")
        let outcome: AssistToolOutcome = await AssistFixture.run("rebuild_preview", with: [:], on: made.runner)
        XCTAssertTrue(outcome.detail.contains(AssistWording.courseIsBeingCopied(course: "ICS3U")), outcome.detail)
        XCTAssertEqual(made.siteWork.previewRebuilds, 0, "a build was started during the copy")
    }

    /// With no window, the site work itself refuses — the build and the
    /// publish both.
    func testTheSiteWorkRefusesToBuildOrPublishWhileACopyIsSaved() async throws {
        let (root, workspace, course) = try makeWorkspace()
        CourseActivity.beginCopy(folderPath: root.path, courseCode: "ICS3U")
        let work: AssistToolchainWork = AssistToolchainWork(workspace: workspace)
        let rebuilt: AssistSiteWorkResult = await work.rebuildPreview(course: course, sectionNumber: 1)
        XCTAssertFalse(rebuilt.succeeded)
        XCTAssertEqual(rebuilt.message, AssistWording.courseIsBeingCopied(course: "ICS3U"))
        let published: AssistSiteWorkResult = await work.deploy(course: course, sectionNumber: 1)
        XCTAssertFalse(published.succeeded)
        XCTAssertEqual(published.message, AssistWording.courseIsBeingCopied(course: "ICS3U"))
        XCTAssertTrue(CourseActivity.activePreviewBuilds.isEmpty)
    }

    func testARemovalRefusesWhileTheCourseIsBusy() async throws {
        let (root, _, course) = try makeWorkspace()
        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        let result: ScheduledDeployCleanup.RemovalResult = await ScheduledDeployCleanup.removeCourse(
            course, coursesDirectoryURL: root.appendingPathComponent("courses"), runner: SilentLaunchControl()
        )
        XCTAssertFalse(result.didRemove)
        XCTAssertEqual(result.problem, ScheduledDeployCleanup.removalWaitsWhileBusy(course: "ICS3U"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: course.directoryURL.path))
        // Refused BEFORE anything: no archive made, nothing turned off.
        XCTAssertEqual(WorkspaceModel.findBackupItems(in: root.appendingPathComponent("courses")).count, 0)
        let archives: [String] = (try? FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent("courses/_backups/ICS3U").path
        )) ?? []
        XCTAssertEqual(archives, [], "the refused removal zipped the course first")
    }

    /// A publish that begins during the removal's zip: the archive is made,
    /// the course is NOT deleted.
    func testARemovalDeletesNothingWhenTheCourseBecameBusyDuringItsZip() async throws {
        let (root, workspace, course) = try makeWorkspace()
        let removing: Task<ScheduledDeployCleanup.RemovalResult, Never> = Task { @MainActor in
            return await ScheduledDeployCleanup.removeCourse(
                course, coursesDirectoryURL: root.appendingPathComponent("courses"), runner: SilentLaunchControl()
            )
        }
        await waitForTheCopyToStart(in: workspace)
        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        let result: ScheduledDeployCleanup.RemovalResult = await removing.value
        XCTAssertFalse(result.didRemove)
        XCTAssertTrue(FileManager.default.fileExists(atPath: course.directoryURL.path),
                      "the course was deleted under a publish that began during the zip")
    }

    func testTheQuitQuestionNamesTheCourseAsATeacherReadsIt() {
        CourseActivity.beginCopy(folderPath: "/pretend", courseCode: "ICS4U-2025", displayCode: "ICS4U")
        XCTAssertEqual(QuitConfirmation.workUnderWay(), "saving a copy of ICS4U")
    }
}

