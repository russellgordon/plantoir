import XCTest
@testable import QuartzTeachers

/// Every window-restoration failure found by hand this week, replayed as a
/// test — so none of them has to be found by hand again.
///
/// What cannot run here is macOS itself quitting and relaunching the app;
/// what CAN is every decision the app makes about the windows macOS hands
/// it, which is where every one of these bugs actually lived.
final class WindowRestorationScenarioTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func makeFolders(_ count: Int) throws -> [String] {
        var paths: [String] = []
        for _ in 0..<count {
            let url: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scenario-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            paths.append(url.path)
        }
        return paths
    }

    func removeAll(_ folders: [String]) {
        for path in folders {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// THE SWAP: both windows and both folders came back, paired wrongly,
    /// because macOS reopens windows in an order of its own and folders
    /// were being handed out by appearance order.
    @MainActor
    func testFoldersPairByFrameWhicheverOrderWindowsReopen() throws {
        let folders: [String] = try makeFolders(2)
        defer { removeAll(folders) }
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: folders[0], frame: "{{100, 100}, {900, 700}}"),
            WindowFolderMemory.Entry(path: folders[1], frame: "{{600, 300}, {1100, 720}}"),
        ])

        // The SECOND window reopens first.
        let late: WindowFolderClaimant = WindowFolderClaimant()
        let early: WindowFolderClaimant = WindowFolderClaimant()
        XCTAssertEqual(late.frameDidSettle("{{600, 300}, {1100, 720}}")?.path, folders[1])
        XCTAssertEqual(early.frameDidSettle("{{100, 100}, {900, 700}}")?.path, folders[0])
    }

    /// THE UNSETTLED FRAME: claiming at first sight of the window matched
    /// nothing, because a reopened window's frame settles a moment later.
    @MainActor
    func testAWindowKeepsTryingWhileItsFrameSettles() throws {
        let folders: [String] = try makeFolders(1)
        defer { removeAll(folders) }
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: folders[0], frame: "{{100, 100}, {900, 700}}"),
        ])

        let claimant: WindowFolderClaimant = WindowFolderClaimant()
        XCTAssertNil(claimant.frameDidSettle("{{0, 0}, {1100, 720}}"), "The cascade frame is not its restored frame")
        XCTAssertEqual(claimant.frameDidSettle("{{100, 100}, {900, 700}}")?.path, folders[0],
                       "The settled frame finds the folder")
    }

    /// THE CLOBBERED LIST: windows unregistering as they close during quit
    /// rewrote the list window by window, shrinking it to nothing.
    @MainActor
    func testQuittingDoesNotRewriteTheListAsWindowsClose() throws {
        let folders: [String] = try makeFolders(2)
        defer { removeAll(folders) }
        let defaults: UserDefaults = TestDefaults.make()

        let first: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        let second: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        first.chooseWorkspace(at: URL(fileURLWithPath: folders[0]))
        second.chooseWorkspace(at: URL(fileURLWithPath: folders[1]))
        WorkspaceModel.registerWindowModel(first)
        WorkspaceModel.registerWindowModel(second)
        defer {
            WorkspaceModel.isTerminating = false
            WorkspaceModel.unregisterWindowModel(first)
            WorkspaceModel.unregisterWindowModel(second)
        }

        // The quit snapshot, taken while both windows exist. The app's own
        // window is registered too in this hosted suite, so assert on OUR
        // two rather than the total.
        func recordedPaths() -> [String] {
            let stored = defaults.array(forKey: WindowFolderMemory.storageKey) as? [[String: String]] ?? []
            var paths: [String] = []
            for pair in stored {
                if let path = pair["path"] {
                    paths.append(path)
                }
            }
            return paths
        }
        WorkspaceModel.rememberOpenFolders(defaults: defaults)
        XCTAssertTrue(recordedPaths().contains(folders[0]))
        XCTAssertTrue(recordedPaths().contains(folders[1]))

        // Termination begins; windows close one by one. The list must not
        // shrink with them.
        WorkspaceModel.isTerminating = true
        WorkspaceModel.unregisterWindowModel(first)
        WorkspaceModel.unregisterWindowModel(second)
        XCTAssertTrue(recordedPaths().contains(folders[0]), "The quit snapshot must survive the windows closing")
        XCTAssertTrue(recordedPaths().contains(folders[1]), "The quit snapshot must survive the windows closing")
    }

    /// THE STALE INHERITANCE: a window the teacher opens mid-session must
    /// start fresh, not adopt an entry left over from launch.
    @MainActor
    func testAWindowOpenedLaterInheritsNothing() throws {
        let folders: [String] = try makeFolders(1)
        defer { removeAll(folders) }
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: folders[0], frame: "{{1, 1}, {900, 700}}"),
        ])
        // Launch was a while ago.
        WindowFolderMemory.claimsOpenUntil = Date(timeIntervalSinceNow: -1)

        let claimant: WindowFolderClaimant = WindowFolderClaimant()
        XCTAssertNil(claimant.frameDidSettle("{{1, 1}, {900, 700}}"))
        XCTAssertNil(claimant.giveUp(), "Claims are a launch-time affair")
    }

    /// THE KILLED APP: no frames were restored, so order is all there is —
    /// and it must still hand out each folder exactly once.
    @MainActor
    func testAKilledAppFallsBackToOrderWithoutDuplication() throws {
        let folders: [String] = try makeFolders(2)
        defer { removeAll(folders) }
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: folders[0], frame: "{{1, 1}, {900, 700}}"),
            WindowFolderMemory.Entry(path: folders[1], frame: "{{2, 2}, {900, 700}}"),
        ])

        let first: WindowFolderClaimant = WindowFolderClaimant()
        let second: WindowFolderClaimant = WindowFolderClaimant()
        _ = first.frameDidSettle("{{500, 500}, {1100, 720}}")
        _ = second.frameDidSettle("{{500, 500}, {1100, 720}}")
        XCTAssertEqual(first.giveUp()?.path, folders[0])
        XCTAssertEqual(second.giveUp()?.path, folders[1], "Each entry is handed out once")
        XCTAssertNil(second.giveUp(), "A claimant that has resolved never claims again")
    }

    /// THE RESTORED SELECTION: a window comes back by setting its folder
    /// FIRST and its remembered selection second, and clearing the selection
    /// on a folder change must not undo the second half of that.
    ///
    /// Named in GitHub issue #93 as the thing to check before fixing it, and
    /// it is the reason the clearing lives in the folder funnel rather than
    /// in `reloadCourses()` — a window that restores its folder and then its
    /// selection reloads courses in between.
    ///
    /// A real working folder with a real course, not a bare temporary
    /// directory: asserting that a selection naming nothing survives proves
    /// nothing, since a window showing "Course Not Found" would satisfy it.
    /// The selection has to NAME the course that is there, and go on naming
    /// it after everything the restoration then does.
    ///
    /// **What this does NOT do is tell the chosen design from the rejected
    /// one.** A selection naming a course that exists survives a
    /// validate-inside-`reloadCourses()` too; this is a regression guard on
    /// restoration, no more. The rejected design is pinned by
    /// `WorkingFolderSelectionTests.testACourseThatDisappearsFromThisFolder…`
    /// and by the contract case carrying `expectNamesALoadedCourse: false`,
    /// where the selection must survive naming NOTHING.
    @MainActor
    func testARestoredWindowKeepsTheSelectionItComesBackWith() throws {
        let folder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: folder) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        // The order `WindowRootView.adopt(_:how:)` uses, and the order that
        // matters: folder, then the sidebar as it was left.
        workspace.adoptRestoredPath(folder.path)
        workspace.selection = .section("EXC2O", 2)
        XCTAssertNotNil(workspace.selectedCourse, "the fixture's course should be there to name")

        // The two things that happen to a restored window afterwards and
        // could take the selection with them: the folder being chosen again
        // — which the funnel must read as the SAME folder rather than a
        // change — and an ordinary reload, which is what every rename,
        // backup, restore and archive causes.
        //
        // `chooseWorkspace` rather than `adoptRestoredPath` on purpose:
        // adopting returns early when the path is the one already set, so it
        // never reaches the funnel and would exercise nothing at all. The
        // picker has no such guard, so this is the route that really asks the
        // funnel whether the folder has changed.
        workspace.chooseWorkspace(at: folder)
        workspace.reloadCourses()

        XCTAssertEqual(
            workspace.selection, .section("EXC2O", 2),
            "A restored window must come back to what the teacher was looking at, and stay there"
        )
        XCTAssertNotNil(
            workspace.selectedCourse,
            "and the selection must still name the course, not merely be non-nil"
        )
    }

    /// THE DEFENSIVE HALF: no caller in the product reaches
    /// `adoptRestoredPath` with a folder already set — every one of them is
    /// a fresh model, and the method's own guard turns away the one route
    /// that would arrive with the SAME folder. It clears anyway, so that the
    /// rule belongs to adopting a folder rather than to one way of doing it.
    @MainActor
    func testAdoptingADifferentFolderClearsTheSelectionEvenThoughNothingDoesThat() throws {
        let folders: [String] = try makeFolders(2)
        defer { removeAll(folders) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.adoptRestoredPath(folders[0])
        workspace.selection = .course("ICS3U")

        workspace.adoptRestoredPath(folders[1])

        XCTAssertNil(workspace.selection)
    }

    /// THE SYSTEM SETTING: "Close windows when quitting" on means no WINDOW
    /// is replayed — the list loads empty, though it is still recorded. The
    /// FOLDER still comes back since #311; that half is
    /// `ReopeningTheLastWorkingFolderTests.testTheCloseWindowsSettingStillReopensTheLastFolder`.
    @MainActor
    func testTheCloseWindowsSettingMeansNoWindowIsReplayed() throws {
        let folders: [String] = try makeFolders(1)
        defer { removeAll(folders) }
        let defaults: UserDefaults = TestDefaults.make()
        WindowFolderMemory.record([WindowFolderMemory.Entry(path: folders[0], frame: "")], defaults: defaults)

        WindowFolderMemory.systemRestoresWindowsOverride = false
        defer { WindowFolderMemory.systemRestoresWindowsOverride = nil }
        WindowFolderMemory.resetForLoading()
        XCTAssertNil(WindowFolderMemory.claimNextEntry(defaults: defaults),
                     "The teacher asked for windows not to come back — the window set follows the setting")

        // And with the setting the other way, the same store restores.
        WindowFolderMemory.systemRestoresWindowsOverride = true
        WindowFolderMemory.resetForLoading()
        XCTAssertEqual(WindowFolderMemory.claimNextEntry(defaults: defaults)?.path, folders[0])
    }
}
