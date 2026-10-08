import XCTest
@testable import QuartzTeachers

/// File ▸ Open Working Folder… and Open Recent with NO Plantoir window in
/// front (#457): the folder is chosen first, and the next new window opens
/// on it — as the teacher's own choice, so the #290 refusal, the "working
/// folder opened" line and the last-folder memory all apply. And Open
/// Recent in a window that is already open.
@MainActor
final class NewWindowOnAFolderTests: XCTestCase {

    // MARK: - Stored properties

    var scratch: URL = URL(fileURLWithPath: "/")
    var previousStore: ProblemReportStore = ActivityTrail.store

    // MARK: - Functions

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("newwindow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch.appendingPathComponent("trail"))
        WindowFolderMemory.reset(with: [])
        WorkspaceModel.folderForNextNewWindow = nil
        WorkspaceModel.folderToOpenInNextNewWindow = nil
    }

    override func tearDown() async throws {
        ActivityTrail.store = previousStore
        WorkingFolderReach.homeFolderOverride = nil
        WindowSettling.observer = nil
        WorkspaceModel.folderForNextNewWindow = nil
        WorkspaceModel.folderToOpenInNextNewWindow = nil
        WindowFolderMemory.resetForLoading()
        try? FileManager.default.removeItem(at: scratch)
    }

    func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    func makeWorkingFolder(_ name: String) throws -> URL {
        let url: URL = scratch.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("courses/ABC1O"), withIntermediateDirectories: true)
        try "#!/bin/bash\n".write(to: url.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Tests

    /// Open Working Folder… with no window: the new window opens the folder
    /// chosen, ONCE, writes "working folder opened", remembers it as the last
    /// folder and as the newest recent, and settles exactly once.
    func testAChosenFolderOpensInTheNewWindowAsAChoice() throws {
        var settled: Int = 0
        WindowSettling.observer = { model in
            settled += 1
        }
        let defaults: UserDefaults = TestDefaults.make()
        let last: URL = try makeWorkingFolder("last")
        let chosen: URL = try makeWorkingFolder("chosen")
        WindowFolderMemory.recordLastWorkingFolder(RememberedFolder.make(for: last), defaults: defaults)
        WorkspaceModel.folderToOpenInNextNewWindow = .chosen(chosen)

        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.adoptFolderForNewWindow(among: [model])

        XCTAssertEqual(model.workspaceURL?.path, chosen.path, "the folder chosen, not the last one")
        XCTAssertNil(WorkspaceModel.folderToOpenInNextNewWindow, "taken once")
        XCTAssertTrue(trailText().contains("opened the working folder " + chosen.path), trailText())
        XCTAssertFalse(trailText().contains("reopened the working folder"), "a choice, not a reopen")
        XCTAssertEqual(WindowFolderMemory.lastWorkingFolder(defaults: defaults)?.path, chosen.path)
        XCTAssertEqual(model.recentFolders.entries.first?.path, chosen.path)
        XCTAssertEqual(settled, 1)
    }

    /// A folder outside the home folder is refused with the picker's words
    /// (#290), and the window shows the picker — not the last folder.
    func testAChosenFolderOutOfReachIsRefused() throws {
        let home: URL = scratch.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        WorkingFolderReach.homeFolderOverride = home
        let outside: URL = try makeWorkingFolder("outside")
        WorkspaceModel.folderToOpenInNextNewWindow = .chosen(outside)

        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.adoptFolderForNewWindow(among: [model])

        XCTAssertNil(model.workspaceURL)
        XCTAssertEqual(model.folderNotOpened?.how, .chosen)
        XCTAssertEqual(model.folderNotOpened?.reason, .outsideHome)
        XCTAssertTrue(trailText().contains("refused the working folder"))
        XCTAssertTrue(model.hasSettledItsFolder)
    }

    /// Open Recent with no window, on a folder now in the Trash: the new
    /// window shows the picker with Open Recent's own sentence, the trail
    /// says why with the new occasion, and the list KEEPS the folder.
    func testARecentFolderInTheTrashSaysSoInItsOwnWords() throws {
        let home: URL = scratch.appendingPathComponent("home")
        let trashed: URL = home.appendingPathComponent(".Trash/Courses")
        try FileManager.default.createDirectory(at: trashed, withIntermediateDirectories: true)
        WorkingFolderReach.homeFolderOverride = home
        let defaults: UserDefaults = TestDefaults.make()
        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        model.recentFolders.noteOpened(RememberedFolder(path: trashed.path, bookmark: nil))
        WorkspaceModel.folderToOpenInNextNewWindow = .recent(RememberedFolder(path: trashed.path, bookmark: nil))

        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.adoptFolderForNewWindow(among: [model])

        XCTAssertNil(model.workspaceURL)
        XCTAssertEqual(model.folderNotOpened?.reason, .inTrash)
        XCTAssertEqual(model.folderNotOpened?.detail, OpenRecentWording.inTrash)
        XCTAssertEqual(model.folderNotOpened?.headline, OpenRecentWording.title(folderName: "Courses"))
        XCTAssertFalse(model.folderNotOpened?.isShownAsAlert ?? true, "on the picker, which the new window shows")
        XCTAssertTrue(trailText().contains("as a folder chosen from Open Recent — inTrash"), trailText())
        XCTAssertEqual(model.recentFolders.entries.first?.path, trashed.path, "kept: putting it back makes it good again")
    }

    /// Open Recent in a window already showing a folder: it switches THAT
    /// window (Russell's decision 3), as a choice, and a folder that cannot
    /// be opened is said in an alert over the folder the window keeps.
    func testOpenRecentInAnOpenWindowSwitchesItOrSaysWhyOverIt() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let first: URL = try makeWorkingFolder("first")
        let second: URL = try makeWorkingFolder("second")
        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.chooseWorkspace(at: first)
        XCTAssertEqual(model.workspaceURL?.path, first.path)

        model.openRecent(RememberedFolder.make(for: second))
        XCTAssertEqual(model.workspaceURL?.path, second.path)
        XCTAssertTrue(trailText().contains("opened the working folder " + second.path + " from File ▸ Open Recent"), trailText())
        XCTAssertEqual(paths(of: model.recentFolders.entries), [second.path, first.path])

        let gone: String = scratch.appendingPathComponent("gone").path
        model.openRecent(RememberedFolder(path: gone, bookmark: nil))
        XCTAssertEqual(model.workspaceURL?.path, second.path, "the window keeps its folder")
        XCTAssertEqual(model.folderNotOpened?.reason, .gone)
        XCTAssertTrue(model.folderNotOpened?.isShownAsAlert ?? false, "said over the courses, in an alert")
        XCTAssertEqual(model.folderNotOpened?.detail, OpenRecentWording.gone)
    }

    /// Bringing a window to the front does NOT reorder Open Recent (the plan
    /// review: it would reorder on every app switch, each a menu rebuild).
    func testComingToTheFrontDoesNotTouchTheRecents() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let first: URL = try makeWorkingFolder("first")
        let second: URL = try makeWorkingFolder("second")
        let one: WorkspaceModel = WorkspaceModel(defaults: defaults)
        let two: WorkspaceModel = WorkspaceModel(defaults: defaults)
        WorkspaceModel.registerWindowModel(one)
        WorkspaceModel.registerWindowModel(two)
        defer {
            WorkspaceModel.unregisterWindowModel(one)
            WorkspaceModel.unregisterWindowModel(two)
        }
        one.chooseWorkspace(at: first)
        two.chooseWorkspace(at: second)
        let list: RecentWorkingFolders = one.recentFolders
        let writes: Int = list.writeCount
        one.rememberAsTheLastWorkingFolder()
        two.rememberAsTheLastWorkingFolder()
        one.rememberAsTheLastWorkingFolder()
        XCTAssertEqual(list.writeCount, writes, "focus is not an open")
    }

    /// The menu's choice is dropped when the app goes to the background, as
    /// a notification's is — a window opened an hour later is not captured.
    func testGoingToTheBackgroundDropsTheChoice() throws {
        WorkspaceModel.folderToOpenInNextNewWindow = .chosen(scratch)
        AppDelegate().applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        XCTAssertNil(WorkspaceModel.folderToOpenInNextNewWindow)
    }

    func paths(of folders: [RememberedFolder]) -> [String] {
        var result: [String] = []
        for folder in folders {
            result.append(folder.path)
        }
        return result
    }
}
