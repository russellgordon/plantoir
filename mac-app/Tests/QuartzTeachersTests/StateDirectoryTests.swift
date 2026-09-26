import XCTest
@testable import QuartzTeachers

/// `--state-dir` (#154): a folder that stands in for the home folder for
/// everything the app itself resolves, and what is refused under it.
///
/// Every rule is a pure function here, asked with made-up values, so no test
/// sets a process-wide static and the real home is never named. What the
/// flag does to the real app is proved through the window by
/// `StateDirectoryUITests`, in the UI target.
final class StateDirectoryTests: XCTestCase {

    // MARK: - Stored properties

    private let stateFolder: URL = URL(fileURLWithPath: "/private/tmp/plantoir-state-example", isDirectory: true)
    private let madeUpHome: URL = URL(fileURLWithPath: "/Users/teacher", isDirectory: true)

    // MARK: - Reading the flag

    func testNoFlagIsNoStateDirectory() throws {
        XCTAssertNil(try RealHome.stateDirectory(fromArguments: ["/Applications/Plantoir.app/Contents/MacOS/Plantoir"]))
        XCTAssertNil(try RealHome.stateDirectory(fromArguments: []))
    }

    func testAnAbsoluteFolderIsTaken() throws {
        let found: URL? = try RealHome.stateDirectory(
            fromArguments: ["Plantoir", "-ApplePersistenceIgnoreState", "YES", "--state-dir", "/tmp/x/../state"]
        )
        XCTAssertEqual(found?.path, "/tmp/state")
    }

    func testAFlagWithNothingAfterItIsRefused() {
        XCTAssertThrowsError(try RealHome.stateDirectory(fromArguments: ["Plantoir", "--state-dir"])) { error in
            XCTAssertEqual(error as? RealHome.StateDirectoryProblem, .missingValue)
        }
        XCTAssertThrowsError(try RealHome.stateDirectory(fromArguments: ["Plantoir", "--state-dir", "--mcp-stdio"])) { error in
            XCTAssertEqual(error as? RealHome.StateDirectoryProblem, .missingValue)
        }
    }

    func testARelativeFolderIsRefused() {
        XCTAssertThrowsError(try RealHome.stateDirectory(fromArguments: ["Plantoir", "--state-dir", "state"])) { error in
            XCTAssertEqual(error as? RealHome.StateDirectoryProblem, .notAbsolute("state"))
        }
    }

    /// `~` is not expanded: that would be a second way to ask for a home
    /// inside the function that replaces it.
    func testATildeIsRefused() {
        XCTAssertThrowsError(try RealHome.stateDirectory(fromArguments: ["Plantoir", "--state-dir", "~/state"])) { error in
            XCTAssertEqual(error as? RealHome.StateDirectoryProblem, .notAbsolute("~/state"))
        }
    }

    func testTheFlagTwiceIsRefused() {
        XCTAssertThrowsError(
            try RealHome.stateDirectory(fromArguments: ["Plantoir", "--state-dir", "/tmp/a", "--state-dir", "/tmp/b"])
        ) { error in
            XCTAssertEqual(error as? RealHome.StateDirectoryProblem, .givenMoreThanOnce)
        }
    }

    /// Nothing in the suite carries the flag, so the process-wide answer is
    /// nil here — the precondition every `=== UserDefaults.standard` guard
    /// relies on.
    func testTheSuiteRunsWithoutAStateDirectory() {
        XCTAssertNil(RealHome.stateDirectory)
        XCTAssertFalse(RealHome.isUnderUITest)
        XCTAssertTrue(RealHome.isRedirected)
    }

    // MARK: - Which home

    func testTheHomeIsChosenInOrder() {
        // The unit suite wins, flag or not.
        XCTAssertEqual(
            RealHome.home(isInsideTestBundle: true, stateDirectory: nil, systemHome: madeUpHome),
            RealHome.homeWhileTesting
        )
        XCTAssertEqual(
            RealHome.home(isInsideTestBundle: true, stateDirectory: stateFolder, systemHome: madeUpHome),
            RealHome.homeWhileTesting
        )
        // Then the state folder.
        XCTAssertEqual(
            RealHome.home(isInsideTestBundle: false, stateDirectory: stateFolder, systemHome: madeUpHome),
            stateFolder
        )
        // Then the system's answer.
        XCTAssertEqual(
            RealHome.home(isInsideTestBundle: false, stateDirectory: nil, systemHome: madeUpHome),
            madeUpHome
        )
    }

    func testTheThrowawayFoldersAreForTestsWithoutAStateFolder() {
        XCTAssertTrue(RealHome.keepsTestStateInThrowawayFolders(isInsideTestBundle: true, isUnderUITest: false, stateDirectory: nil))
        XCTAssertTrue(RealHome.keepsTestStateInThrowawayFolders(isInsideTestBundle: true, isUnderUITest: false, stateDirectory: stateFolder))
        XCTAssertTrue(RealHome.keepsTestStateInThrowawayFolders(isInsideTestBundle: false, isUnderUITest: true, stateDirectory: nil))
        XCTAssertFalse(RealHome.keepsTestStateInThrowawayFolders(isInsideTestBundle: false, isUnderUITest: true, stateDirectory: stateFolder))
        XCTAssertFalse(RealHome.keepsTestStateInThrowawayFolders(isInsideTestBundle: false, isUnderUITest: false, stateDirectory: stateFolder))
        XCTAssertFalse(RealHome.keepsTestStateInThrowawayFolders(isInsideTestBundle: false, isUnderUITest: false, stateDirectory: nil))
    }

    // MARK: - The three folders #240 moved, state folder first

    func testBuildsGoUnderTheStateFolder() {
        let underState: URL = BuildOutputLocation.buildsRoot(
            isInsideTestBundle: false, isUnderUITest: true, stateDirectory: stateFolder, homeForFiles: madeUpHome
        )
        XCTAssertEqual(underState, BuildOutputLocation.buildsRoot(inHomeFolder: stateFolder))
        let uiTestWithoutState: URL = BuildOutputLocation.buildsRoot(
            isInsideTestBundle: false, isUnderUITest: true, stateDirectory: nil, homeForFiles: madeUpHome
        )
        XCTAssertEqual(uiTestWithoutState, BuildOutputLocation.buildsRootWhileTesting)
        let app: URL = BuildOutputLocation.buildsRoot(
            isInsideTestBundle: false, isUnderUITest: false, stateDirectory: nil, homeForFiles: madeUpHome
        )
        XCTAssertEqual(app, BuildOutputLocation.buildsRoot(inHomeFolder: madeUpHome))
    }

    func testScheduledNotesGoUnderTheStateFolder() {
        XCTAssertEqual(
            ScheduledDeploy.homeForScheduledNotes(
                isInsideTestBundle: false, isUnderUITest: true, stateDirectory: stateFolder, homeForFiles: madeUpHome
            ),
            stateFolder
        )
        XCTAssertEqual(
            ScheduledDeploy.homeForScheduledNotes(
                isInsideTestBundle: false, isUnderUITest: true, stateDirectory: nil, homeForFiles: madeUpHome
            ),
            RealHome.homeWhileTesting
        )
        XCTAssertEqual(
            ScheduledDeploy.homeForScheduledNotes(
                isInsideTestBundle: false, isUnderUITest: false, stateDirectory: nil, homeForFiles: madeUpHome
            ),
            madeUpHome
        )
    }

    func testLaunchFilesGoUnderTheStateFolder() {
        XCTAssertEqual(
            ClaudeCodeLauncher.supportDirectory(
                isInsideTestBundle: false, isUnderUITest: true, stateDirectory: stateFolder, homeForFiles: madeUpHome
            ).path,
            stateFolder.path + "/Library/Application Support/Plantoir/assist"
        )
        XCTAssertEqual(
            ClaudeCodeLauncher.supportDirectory(
                isInsideTestBundle: false, isUnderUITest: true, stateDirectory: nil, homeForFiles: madeUpHome
            ),
            ClaudeCodeLauncher.supportDirectoryWhileTesting
        )
    }

    // MARK: - What a state folder refuses

    /// A plist written under a state folder and handed to the real launchd
    /// would still fire a real publish at a real time.
    func testLaunchdIsReachedOnlyByTheAppProper() {
        XCTAssertTrue(LaunchControl.mayReachLaunchd(overrideIsSet: false, isRunningTests: false, stateDirectory: nil))
        XCTAssertFalse(LaunchControl.mayReachLaunchd(overrideIsSet: true, isRunningTests: false, stateDirectory: nil))
        XCTAssertFalse(LaunchControl.mayReachLaunchd(overrideIsSet: false, isRunningTests: true, stateDirectory: nil))
        XCTAssertFalse(LaunchControl.mayReachLaunchd(overrideIsSet: false, isRunningTests: false, stateDirectory: stateFolder))
    }

    /// The quit script can stop the shared virtual machine (CLAUDE.md rule 7).
    func testContainersAreFreedOnlyByTheAppProper() {
        XCTAssertTrue(FolderContainers.mayFreeContainersAtQuit(isInsideTestBundle: false, isUnderUITest: false, isRedirected: false))
        XCTAssertFalse(FolderContainers.mayFreeContainersAtQuit(isInsideTestBundle: true, isUnderUITest: false, isRedirected: true))
        XCTAssertFalse(FolderContainers.mayFreeContainersAtQuit(isInsideTestBundle: false, isUnderUITest: true, isRedirected: false))
        XCTAssertFalse(FolderContainers.mayFreeContainersAtQuit(isInsideTestBundle: false, isUnderUITest: false, isRedirected: true))
    }

    /// A redirected run starts from its own folder, not from the teacher's
    /// old-name preferences.
    func testTheOldNameMigrationNeverRunsUnderAStateFolder() {
        XCTAssertTrue(WorkspaceModel.mayMigratePreferences(isRunningTests: false, stateDirectory: nil, intoTheSharedStore: true))
        XCTAssertFalse(WorkspaceModel.mayMigratePreferences(isRunningTests: false, stateDirectory: stateFolder, intoTheSharedStore: true))
        XCTAssertFalse(WorkspaceModel.mayMigratePreferences(isRunningTests: true, stateDirectory: nil, intoTheSharedStore: true))
        XCTAssertFalse(WorkspaceModel.mayMigratePreferences(isRunningTests: false, stateDirectory: nil, intoTheSharedStore: false))
    }

    /// Nothing may be posted, or permission asked for, from the suite; the
    /// same `isRedirected` a state folder sets decides it.
    func testTheSuitePostsNoNotifications() {
        XCTAssertTrue(ScheduledPublishNotice.defaultPoster() is QuietNotifications)
    }

    // MARK: - The preferences door

    func testWithoutAStateFolderTheStoreIsTheStandardOne() {
        XCTAssertTrue(PlantoirDefaults.makeStore(stateDirectory: nil) === UserDefaults.standard)
    }

    func testTheStoreIsAFileInsideTheStateFolder() throws {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let key: String = "stateDirectoryProbe-\(UUID().uuidString)"
        let store: UserDefaults = PlantoirDefaults.makeStore(stateDirectory: folder)
        XCTAssertFalse(store === UserDefaults.standard)
        store.set("written", forKey: key)
        XCTAssertTrue(store.synchronize())
        let file: URL = folder
            .appendingPathComponent("Library/Preferences/ca.russellgordon.Plantoir.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "No preferences file at \(file.path)")
        XCTAssertEqual(PlantoirDefaults.preferencesPath(inStateDirectory: folder) + ".plist", file.path)
        // The negative half: the standard store never saw it.
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
        store.removeObject(forKey: key)
        store.synchronize()
    }
}
