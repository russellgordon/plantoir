import XCTest
@testable import QuartzTeachers

/// Choosing an empty folder must offer initialization, and initializing
/// must produce a valid working folder with executable launcher scripts.
final class WorkspaceInitializationTests: XCTestCase {

    // MARK: - Functions

    func makeTemporaryFolder() throws -> URL {
        let url: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cq4t-init-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func testEmptyFolderOffersInitialization() throws {
        let folderURL: URL = try makeTemporaryFolder()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folderURL)

        XCTAssertTrue(workspace.workspaceCanBeInitialized, "An empty folder should offer setup")
        XCTAssertNil(workspace.workspaceProblem, "An empty folder should not read as an error")
    }

    @MainActor
    func testNonEmptyFolderWithoutScriptsKeepsPickerUpWithoutAnError() throws {
        let folderURL: URL = try makeTemporaryFolder()
        try Data("hello".utf8).write(to: folderURL.appendingPathComponent("unrelated.txt"))
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folderURL)

        XCTAssertFalse(workspace.workspaceCanBeInitialized, "A folder with existing content should not be silently taken over")
        XCTAssertTrue(workspace.workspaceIsUnrecognized, "The picker should stay up so a different folder can be chosen")
        XCTAssertNil(workspace.workspaceProblem, "An unfinished choice is not an error and should show no red text")
    }

    @MainActor
    func testInitializationProducesAValidWorkspace() throws {
        let folderURL: URL = try makeTemporaryFolder()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folderURL)
        workspace.initializeWorkspace()

        XCTAssertNil(workspace.workspaceProblem)
        XCTAssertFalse(workspace.workspaceCanBeInitialized, "The folder should now validate as a working folder")
        XCTAssertTrue(workspace.isShowingNewCourseWizard, "A fresh folder should lead straight into creating a course")

        let fileManager: FileManager = FileManager.default
        let scriptNames: [String] = ["setup.sh", "preview.sh", "deploy.sh"]
        for scriptName in scriptNames {
            let scriptPath: String = folderURL.appendingPathComponent(scriptName).path
            XCTAssertTrue(fileManager.fileExists(atPath: scriptPath), "\(scriptName) should be copied in")
            XCTAssertTrue(fileManager.isExecutableFile(atPath: scriptPath), "\(scriptName) should be executable")
        }
        XCTAssertTrue(fileManager.fileExists(atPath: folderURL.appendingPathComponent("courses").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folderURL.appendingPathComponent(".toolchain").appendingPathComponent("Dockerfile").path), "The .toolchain build recipe should be copied in")

        // The copied script must be the real launcher, not a stub.
        let previewContents: String = try String(contentsOf: folderURL.appendingPathComponent("preview.sh"), encoding: .utf8)
        XCTAssertTrue(previewContents.contains("ensure_container_runtime"), "The bundled script should be the current toolchain launcher")

        // Tidy the wizard flag so this test leaves no UI behind.
        workspace.isShowingNewCourseWizard = false
    }

    /// The path the BUTTON takes, which is not the one above.
    ///
    /// Setting up a folder copies the whole build recipe — 12,091 files —
    /// and doing that on the main thread beachballs the window with nothing
    /// on screen to say why. The button therefore calls the background form,
    /// and this pins that it produces exactly the same folder and leaves no
    /// "setting up" state behind. Without it, only the synchronous form the
    /// button no longer uses would be covered.
    @MainActor
    func testInitializingInTheBackgroundProducesTheSameWorkspace() async throws {
        let folderURL: URL = try makeTemporaryFolder()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folderURL)

        XCTAssertFalse(workspace.isInitializingWorkspace, "Nothing is being set up before the button is pressed")
        await workspace.initializeWorkspaceInBackground()

        XCTAssertFalse(workspace.isInitializingWorkspace, "The button must not be left saying \"Setting Up…\" forever")
        XCTAssertNil(workspace.workspaceProblem)
        XCTAssertFalse(workspace.workspaceCanBeInitialized, "The folder should now validate as a working folder")
        XCTAssertTrue(workspace.isShowingNewCourseWizard, "A fresh folder should lead straight into creating a course")

        let fileManager: FileManager = FileManager.default
        let scriptNames: [String] = ["setup.sh", "preview.sh", "deploy.sh"]
        for scriptName in scriptNames {
            let scriptPath: String = folderURL.appendingPathComponent(scriptName).path
            XCTAssertTrue(fileManager.isExecutableFile(atPath: scriptPath), "\(scriptName) should be copied in, executable")
        }
        XCTAssertTrue(fileManager.fileExists(atPath: folderURL.appendingPathComponent("courses").path))
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: folderURL.appendingPathComponent(".toolchain").appendingPathComponent("Dockerfile").path
            ),
            "The .toolchain build recipe must be mirrored by the background path too — row 279's defect, one thread over"
        )

        workspace.isShowingNewCourseWizard = false
    }
}

/// Remembering the working folder across launches.
final class WorkspacePersistenceTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    /// A brand-new model adopts nothing on its own: a lone new window
    /// shows the picker, and restored or inherited folders arrive through
    /// the window claims and the new-window policy — never silently from
    /// the last-used preference.
    func testAFreshModelStartsWithoutAFolder() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: defaults)
        workspace.chooseWorkspace(at: folderURL)

        let reopened: WorkspaceModel = WorkspaceModel(defaults: defaults)
        XCTAssertNil(reopened.workspaceURL, "A fresh window opens without a folder, even after one was chosen before")
        XCTAssertEqual(defaults.string(forKey: WorkspaceModel.storedPathKey), folderURL.path,
                       "The choice is still recorded, for preference migration")
    }

    /// A mid-session window knows its folder the moment its model exists —
    /// the fix for the picker flashing before the inherited folder arrived.
    @MainActor
    func testAMidSessionWindowKnowsItsFolderImmediately() throws {
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let savedDeadline: Date = WindowFolderMemory.claimsOpenUntil
        let savedKeyPath: String? = WorkspaceModel.mostRecentKeyFolderPath
        defer {
            WindowFolderMemory.claimsOpenUntil = savedDeadline
            WorkspaceModel.mostRecentKeyFolderPath = savedKeyPath
        }

        // Mid-session: claims are long closed, and a key window worked here.
        WindowFolderMemory.claimsOpenUntil = Date(timeIntervalSinceNow: -60)
        let keyWindowModel: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        keyWindowModel.adoptRestoredPath(folderURL.path)
        WorkspaceModel.registerWindowModel(keyWindowModel)
        WorkspaceModel.mostRecentKeyFolderPath = folderURL.path
        defer { WorkspaceModel.unregisterWindowModel(keyWindowModel) }

        let newWindowModel: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        newWindowModel.adoptFolderForNewWindow()
        XCTAssertEqual(newWindowModel.workspaceURL?.path, folderURL.path,
                       "The folder must be known before anything renders")
    }

    /// What a brand-new window opens to, by policy: nothing when it is
    /// the only window; the key window's folder otherwise.
    @MainActor
    func testANewWindowFollowsTheKeyWindow() {
        XCTAssertNil(WorkspaceModel.folderForNewWindow(otherOpenFolderPaths: [], mostRecentKeyPath: "/a"),
                     "With no other windows open, a new window has no folder — even if one was key earlier")
        XCTAssertEqual(WorkspaceModel.folderForNewWindow(otherOpenFolderPaths: ["/a", "/b"], mostRecentKeyPath: "/b"), "/b",
                       "The key window's folder wins")
        XCTAssertEqual(WorkspaceModel.folderForNewWindow(otherOpenFolderPaths: ["/a", "/b"], mostRecentKeyPath: "/gone"), "/a",
                       "A stale key memory falls back to an open window's folder")
        XCTAssertEqual(WorkspaceModel.folderForNewWindow(otherOpenFolderPaths: ["/a"], mostRecentKeyPath: nil), "/a",
                       "No key memory yet still inherits from the open window")
    }

    @MainActor
    func testAWindowAdoptsTheFolderItWasRestoredWith() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: defaults)
        workspace.adoptRestoredPath(folderURL.path)
        XCTAssertEqual(workspace.workspaceURL?.path, folderURL.path)
    }

    @MainActor
    func testARestoredFolderThatIsGoneIsIgnored() {
        let defaults: UserDefaults = TestDefaults.make()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: defaults)
        workspace.adoptRestoredPath("/nowhere/this/does/not/exist")
        XCTAssertNil(workspace.workspaceURL)
    }

    @MainActor
    func testATestNeverWritesIntoTheRealPreferences() throws {
        let before: String? = UserDefaults.standard.string(forKey: WorkspaceModel.storedPathKey)
        let defaults: UserDefaults = TestDefaults.make()
        let folderURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: defaults)
        workspace.chooseWorkspace(at: folderURL)

        let after: String? = UserDefaults.standard.string(forKey: WorkspaceModel.storedPathKey)
        XCTAssertEqual(before, after, "A test must leave the teacher's own working folder alone")
    }
}

/// A working folder's launchers stay current with the app.
final class LauncherRefreshTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testAStaleLauncherIsReplaced() throws {
        let fileManager: FileManager = FileManager.default
        let workspace: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lr-\(UUID().uuidString)")
        let source: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lrsrc-\(UUID().uuidString)")
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workspace)
            try? fileManager.removeItem(at: source)
        }

        try "#!/bin/bash\necho new".write(to: source.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        try "#!/bin/bash\necho old".write(to: workspace.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)

        let refreshed = WorkspaceModel.refreshLaunchers(
            in: workspace,
            from: ["preview.sh": source.appendingPathComponent("preview.sh")]
        )
        XCTAssertEqual(refreshed, ["preview.sh"])
        let contents: String = try String(contentsOf: workspace.appendingPathComponent("preview.sh"), encoding: .utf8)
        XCTAssertTrue(contents.contains("echo new"))

        let attributes = try fileManager.attributesOfItem(atPath: workspace.appendingPathComponent("preview.sh").path)
        let permissions: Int = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(permissions & 0o111, 0o111, "The refreshed script must stay executable")
    }

    @MainActor
    func testACurrentLauncherIsLeftAlone() throws {
        let fileManager: FileManager = FileManager.default
        let workspace: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lr-\(UUID().uuidString)")
        let source: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lrsrc-\(UUID().uuidString)")
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workspace)
            try? fileManager.removeItem(at: source)
        }
        try "same".write(to: source.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        try "same".write(to: workspace.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        XCTAssertEqual(WorkspaceModel.refreshLaunchers(in: workspace, from: ["preview.sh": source.appendingPathComponent("preview.sh")]), [])
    }

    @MainActor
    func testAMissingLauncherIsNotCreated() throws {
        // A folder without launchers has never been initialized; creating
        // one script in it would leave a half-initialized folder.
        let fileManager: FileManager = FileManager.default
        let workspace: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lr-\(UUID().uuidString)")
        let source: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lrsrc-\(UUID().uuidString)")
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workspace)
            try? fileManager.removeItem(at: source)
        }
        try "new".write(to: source.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        XCTAssertEqual(WorkspaceModel.refreshLaunchers(in: workspace, from: ["preview.sh": source.appendingPathComponent("preview.sh")]), [])
        XCTAssertFalse(fileManager.fileExists(atPath: workspace.appendingPathComponent("preview.sh").path))
    }
}
