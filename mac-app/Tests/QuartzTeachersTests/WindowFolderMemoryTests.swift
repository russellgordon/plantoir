import XCTest
@testable import QuartzTeachers

/// Windows coming back in the folders they were left in.
final class WindowFolderMemoryTests: XCTestCase {

    // MARK: - Functions

    /// Folders that really exist, so the memory does not skip them.
    @MainActor
    func makeFolders(_ count: Int) throws -> [String] {
        var paths: [String] = []
        for _ in 0..<count {
            let url: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wfm-\(UUID().uuidString)")
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

    @MainActor
    func testTheLaunchWindowTakesTheFirstEntryFolderAndFrame() throws {
        let folders: [String] = try makeFolders(2)
        defer { removeAll(folders) }
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: folders[0], frame: "{{100, 100}, {900, 700}}"),
            WindowFolderMemory.Entry(path: folders[1], frame: "{{300, 200}, {1100, 720}}"),
        ])
        let first = WindowFolderMemory.claimNextEntry()
        XCTAssertEqual(first?.path, folders[0])
        XCTAssertEqual(first?.frame, "{{100, 100}, {900, 700}}")
    }

    @MainActor
    func testAReopenedWindowFindsItsFolderByItsFrame() throws {
        let folders: [String] = try makeFolders(2)
        defer { removeAll(folders) }
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: folders[0], frame: "{{100, 100}, {900, 700}}"),
            WindowFolderMemory.Entry(path: folders[1], frame: "{{300, 200}, {1100, 720}}"),
        ])
        // The SECOND window is reopened first — macOS chooses its own
        // order, which is exactly what swapped the folders.
        XCTAssertEqual(WindowFolderMemory.claimEntry(matchingFrame: "{{300, 200}, {1100, 720}}")?.path, folders[1])
        XCTAssertEqual(WindowFolderMemory.claimEntry(matchingFrame: "{{100, 100}, {900, 700}}")?.path, folders[0])
        XCTAssertFalse(WindowFolderMemory.hasEntriesToClaim())
    }

    @MainActor
    func testAnEmptyFrameNeverMatches() throws {
        let folders: [String] = try makeFolders(1)
        defer { removeAll(folders) }
        WindowFolderMemory.reset(with: [WindowFolderMemory.Entry(path: folders[0], frame: "")])
        XCTAssertNil(WindowFolderMemory.claimEntry(matchingFrame: ""),
                     "Two windows with no recorded frame must not both match the first entry")
        XCTAssertEqual(WindowFolderMemory.claimNextEntry()?.path, folders[0], "Order still hands it out")
    }

    @MainActor
    /// Reversed by #311: a gone folder used to be skipped, so its window
    /// met the picker with no word about why. It is handed out now, in
    /// order, and the window that takes it says what happened
    /// (`WorkspaceModel.reopen`, `ReopeningTheLastWorkingFolderTests`).
    func testAFolderThatHasGoneIsStillHandedOutSoItsWindowCanSayWhy() throws {
        let folders: [String] = try makeFolders(2)
        defer { removeAll([folders[1]]) }
        try FileManager.default.removeItem(atPath: folders[0])
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: folders[0], frame: ""),
            WindowFolderMemory.Entry(path: folders[1], frame: ""),
        ])
        XCTAssertEqual(WindowFolderMemory.claimNextEntry()?.path, folders[0],
                       "The gone folder's window must get its entry, to say why it could not be reopened")
        XCTAssertEqual(WindowFolderMemory.claimNextEntry()?.path, folders[1])
    }

    @MainActor
    func testNothingRememberedMeansNothingClaimed() {
        WindowFolderMemory.reset(with: [])
        XCTAssertNil(WindowFolderMemory.claimNextEntry())
    }

    @MainActor
    func testTheListSurvivesARelaunch() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let folders: [String] = try makeFolders(1)
        defer { removeAll(folders) }
        WindowFolderMemory.record([WindowFolderMemory.Entry(path: folders[0], frame: "{{1, 2}, {3, 4}}")], defaults: defaults)
        let stored = defaults.array(forKey: WindowFolderMemory.storageKey) as? [[String: String]]
        XCTAssertEqual(stored?.first?["path"], folders[0])
        XCTAssertEqual(stored?.first?["frame"], "{{1, 2}, {3, 4}}")
    }

    @MainActor
    func testATestNeverWritesIntoTheRealPreferences() throws {
        let before = UserDefaults.standard.array(forKey: WindowFolderMemory.storageKey) as? [[String: String]]
        WindowFolderMemory.record([WindowFolderMemory.Entry(path: "/somewhere/made/up", frame: "")])
        let after = UserDefaults.standard.array(forKey: WindowFolderMemory.storageKey) as? [[String: String]]
        XCTAssertEqual(before, after, "A test must not disturb the teacher's own open windows")
    }

    // MARK: - Holding for a pending claim

    @MainActor
    func testAClaimMayStillArriveWhileEntriesRemainAndClaimsAreOpen() {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp", frame: "{{0, 0}, {800, 600}}"),
        ])
        let now: Date = Date()
        WindowFolderMemory.claimsOpenUntil = now.addingTimeInterval(10)
        XCTAssertTrue(WindowFolderMemory.aClaimMayStillArrive(asOf: now))
    }

    @MainActor
    func testNoClaimCanArriveOnceClaimsHaveClosed() {
        WindowFolderMemory.reset(with: [
            WindowFolderMemory.Entry(path: "/tmp", frame: "{{0, 0}, {800, 600}}"),
        ])
        let now: Date = Date()
        WindowFolderMemory.claimsOpenUntil = now.addingTimeInterval(-1)
        XCTAssertFalse(WindowFolderMemory.aClaimMayStillArrive(asOf: now),
                       "A mid-session window must never hold for a claim")
    }

    @MainActor
    func testNoClaimCanArriveWithNothingLeftToClaim() {
        WindowFolderMemory.reset(with: [])
        let now: Date = Date()
        WindowFolderMemory.claimsOpenUntil = now.addingTimeInterval(10)
        XCTAssertFalse(WindowFolderMemory.aClaimMayStillArrive(asOf: now),
                       "A fresh first launch shows the picker immediately")
    }

    // MARK: - Sidebar expansion rides with the folder

    @MainActor
    func testExpansionStateSurvivesTheStorageRoundTrip() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let folders: [String] = try makeFolders(1)
        defer { removeAll(folders) }
        WindowFolderMemory.record([
            WindowFolderMemory.Entry(
                path: folders[0],
                frame: "{{1, 2}, {3, 4}}",
                expandedCourses: ["ADA1O", "MTH1W"],
                archivedExpanded: true
            ),
        ], defaults: defaults)

        WindowFolderMemory.resetForLoading()
        WindowFolderMemory.systemRestoresWindowsOverride = true
        defer { WindowFolderMemory.systemRestoresWindowsOverride = nil }
        let entry = WindowFolderMemory.claimEntry(matchingFrame: "{{1, 2}, {3, 4}}", defaults: defaults)
        XCTAssertEqual(entry?.expandedCourses, ["ADA1O", "MTH1W"])
        XCTAssertEqual(entry?.archivedExpanded, true)
    }

    @MainActor
    func testAnOldEntryWithoutExpansionLoadsClosed() throws {
        // Entries recorded before this feature carry no expansion keys;
        // they must load as all-collapsed, not fail.
        let defaults: UserDefaults = TestDefaults.make()
        let folders: [String] = try makeFolders(1)
        defer { removeAll(folders) }
        defaults.set([["path": folders[0], "frame": "{{5, 6}, {7, 8}}"]],
                     forKey: WindowFolderMemory.storageKey)

        WindowFolderMemory.resetForLoading()
        WindowFolderMemory.systemRestoresWindowsOverride = true
        defer { WindowFolderMemory.systemRestoresWindowsOverride = nil }
        let entry = WindowFolderMemory.claimEntry(matchingFrame: "{{5, 6}, {7, 8}}", defaults: defaults)
        XCTAssertEqual(entry?.expandedCourses, [])
        XCTAssertEqual(entry?.archivedExpanded, false)
    }

    @MainActor
    func testRememberOpenFoldersRecordsEachWindowsExpansion() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let folders: [String] = try makeFolders(1)
        defer { removeAll(folders) }
        let model: WorkspaceModel = WorkspaceModel()
        model.workspaceURL = URL(fileURLWithPath: folders[0])
        model.expandedCourseCodes = ["ICS3U"]
        model.isShowingArchived = true
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }

        WorkspaceModel.rememberOpenFolders(defaults: defaults)
        let stored = defaults.array(forKey: WindowFolderMemory.storageKey) as? [[String: String]]
        let entry = stored?.first { $0["path"] == folders[0] }
        XCTAssertEqual(entry?["expanded"], "ICS3U")
        XCTAssertEqual(entry?["archived"], "1")
    }

    @MainActor
    func testSelectionSurvivesTheStorageRoundTrip() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let folders: [String] = try makeFolders(1)
        defer { removeAll(folders) }
        WindowFolderMemory.record([
            WindowFolderMemory.Entry(
                path: folders[0],
                frame: "{{9, 9}, {9, 9}}",
                selection: SidebarSelection.section("ICS3U", 2).storageValue
            ),
        ], defaults: defaults)

        WindowFolderMemory.resetForLoading()
        WindowFolderMemory.systemRestoresWindowsOverride = true
        defer { WindowFolderMemory.systemRestoresWindowsOverride = nil }
        let entry = WindowFolderMemory.claimEntry(matchingFrame: "{{9, 9}, {9, 9}}", defaults: defaults)
        XCTAssertEqual(SidebarSelection.fromStorageValue(entry?.selection ?? ""),
                       .section("ICS3U", 2))
    }

    @MainActor
    func testEverySelectionKindRoundTripsThroughItsStorageForm() {
        let selections: [SidebarSelection] = [
            .course("ADA1O"),
            .section("MTH1W", 3),
            .archived("2026-01-15-ICS3U"),
            .backup("/folder/_backups/ICS3U/ICS3U_backup_2026-08-11_221530.zip"),
        ]
        for selection in selections {
            XCTAssertEqual(SidebarSelection.fromStorageValue(selection.storageValue), selection)
        }
        XCTAssertNil(SidebarSelection.fromStorageValue(""),
                     "An old entry with no selection restores none")
        XCTAssertNil(SidebarSelection.fromStorageValue("section|ICS3U|not-a-number"))
    }
}
