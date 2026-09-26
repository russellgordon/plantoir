import XCTest
@testable import QuartzTeachers

/// A click on a scheduled publish's notification opens THAT section (#306):
/// `contracts/shared-rules.json` → `scheduledPublishStopped.notification.onClick`,
/// played twice — against the pure `decide`, and through the router with real
/// working folders on disk, real window models and the real settle hook.
///
/// Nothing here reaches a real window or activates the app hosting the
/// suite: the router's window list, its way of bringing a window forward and
/// its way of opening a new window are all stand-ins, put back in `tearDown`.
/// No real notification is ever posted. Every model has `TestDefaults.make()`.
@MainActor
final class SectionFromNotificationTests: XCTestCase {

    // MARK: - Stored properties

    private var scratch: URL = URL(fileURLWithPath: "/nonexistent")
    private var home: URL = URL(fileURLWithPath: "/nonexistent")
    private var previousStore: ProblemReportStore = ActivityTrail.store

    /// The window models the router sees, front to back.
    private var windows: [WorkspaceModel] = []

    /// What the router brought forward, in order; nil is the app alone.
    private var broughtForward: [WorkspaceModel?] = []

    /// How many new windows the router asked for.
    private var windowsOpened: Int = 0

    /// The model a new window was given, when the stand-in made one.
    private var openedModels: [WorkspaceModel] = []

    /// Whether the stand-in opener makes the window at once.
    private var opensAtOnce: Bool = true

    /// Models whose window has a dialog in front of it.
    private var withASheet: [WorkspaceModel] = []

    /// Every model registered as a window, to unregister.
    private var registered: [WorkspaceModel] = []

    // MARK: - Set up and tear down

    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("section-from-notification-\(UUID().uuidString)", isDirectory: true)
        home = scratch.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch.appendingPathComponent("trail"))
        WorkingFolderReach.homeFolderOverride = home
        WindowFolderMemory.reset(with: [])
        WorkspaceModel.folderForNextNewWindow = nil
        installStandIns()
    }

    override func tearDown() async throws {
        SectionFromNotification.resetForTests()
        for model in registered {
            WorkspaceModel.unregisterWindowModel(model)
        }
        registered = []
        windows = []
        openedModels = []
        withASheet = []
        WorkspaceModel.folderForNextNewWindow = nil
        WindowFolderMemory.resetForLoading()
        WorkingFolderReach.homeFolderOverride = nil
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratch)
        try await super.tearDown()
    }

    // MARK: - The contract

    /// Every case's `action` and `window`, against the pure rule.
    func testEveryOnClickCaseIsDecidedAsTheContractSays() throws {
        let cases: [[String: Any]] = try Self.cases()
        XCTAssertGreaterThanOrEqual(cases.count, 16)
        var played: Int = 0
        for oneCase in cases {
            if !Self.appliesToTheMac(oneCase) {
                continue
            }
            let name: String = try XCTUnwrap(oneCase["name"] as? String)
            var states: [SectionFromNotification.WindowState] = []
            for window in try XCTUnwrap(oneCase["windows"] as? [[String: Any]], name) {
                states.append(SectionFromNotification.WindowState(
                    folder: try Self.relation(window, name),
                    hasSettled: window["settled"] as? Bool ?? true,
                    isBusy: window["busy"] as? Bool ?? false
                ))
            }
            let carries: Bool = try XCTUnwrap(oneCase["carries"] as? Bool, name)
            var target: NotificationClickTarget?
            if carries {
                target = NotificationClickTarget(workingFolderPath: "/this", course: "ICS3U", section: 2)
            }
            let decision: SectionFromNotification.Decision = SectionFromNotification.decide(
                target: target,
                windows: states,
                isLaunching: oneCase["launching"] as? Bool ?? false,
                folderExists: oneCase["folderExists"] as? Bool ?? true,
                sectionInFolder: oneCase["sectionInFolder"] as? Bool ?? true
            )
            let expect: [String: Any] = try XCTUnwrap(oneCase["expect"] as? [String: Any], name)
            let action: String = try XCTUnwrap(expect["action"] as? String, name)
            let window: Int? = expect["window"] as? Int
            let selects: Bool = expect["selectsTheSection"] as? Bool ?? false
            switch decision {
            case .wait:
                XCTAssertEqual(action, "wait", name)
            case .bringForwardOnly(_, let brought):
                XCTAssertEqual(action, "bringForwardOnly", name)
                XCTAssertEqual(brought, window, name)
            case .useWindow(let used, let selected):
                XCTAssertEqual(action, "useWindow", name)
                XCTAssertEqual(used, window, name)
                XCTAssertEqual(selected, selects, name)
            case .adoptInto(let used):
                XCTAssertEqual(action, "adoptInto", name)
                XCTAssertEqual(used, window, name)
            case .openNewWindow:
                XCTAssertEqual(action, "openNewWindow", name)
            }
            played += 1
        }
        XCTAssertGreaterThanOrEqual(played, 16)
    }

    /// Every case again, through the router: real folders, real models, the
    /// real settle hook — checking what the pure rule cannot: the selection,
    /// the windows left alone, a window opened, the record, the trail line.
    func testEveryOnClickCasePlaysThroughTheRouter() throws {
        let cases: [[String: Any]] = try Self.cases()
        for oneCase in cases {
            if !Self.appliesToTheMac(oneCase) {
                continue
            }
            try play(oneCase)
        }
    }

    // MARK: - The router, case by case

    /// A window already on the folder — spelled differently from the run's
    /// spelling (`/private/var` against `/var`) — is used; no window opens.
    func testAWindowOnTheFolderIsSelectedAndNoWindowIsOpened() throws {
        let folder: URL = try makeWorkingFolder("this")
        let model: WorkspaceModel = try window(on: folder)
        windows = [model]
        // `/var` is a link to `/private/var`: the same folder, spelled as
        // `/bin/pwd -P` (and so launchd's working directory) would spell it.
        var otherSpelling: String = folder.path
        if folder.path.hasPrefix("/var/") {
            otherSpelling = "/private" + folder.path
        }
        XCTAssertNotEqual(otherSpelling, folder.path, "the fixture must exercise two spellings")

        SectionFromNotification.receive(target(otherSpelling, section: 2))

        XCTAssertEqual(model.selection, .section("ICS3U", 2))
        XCTAssertTrue(model.expandedCourseCodes.contains("ICS3U"))
        XCTAssertEqual(windowsOpened, 0)
        XCTAssertTrue(broughtForward.count == 1 && broughtForward[0] === model)
        XCTAssertNil(SectionFromNotification.request)
    }

    /// A window on ANOTHER folder keeps its folder and selection; a new
    /// window opens on the section's folder, takes it before it decides
    /// anything else, and then shows the section. The folder set aside for
    /// it is taken exactly once.
    func testAWindowOnAnotherFolderIsLeftAloneAndANewOneOpens() throws {
        let folderA: URL = try makeWorkingFolder("a")
        let folderB: URL = try makeWorkingFolder("b")
        let modelA: WorkspaceModel = try window(on: folderA)
        modelA.selection = .course("ICS3U")
        windows = [modelA]
        opensAtOnce = false

        SectionFromNotification.receive(target(folderB.path, section: 1))

        XCTAssertEqual(windowsOpened, 1)
        XCTAssertEqual(modelA.workspaceURL?.path, folderA.path)
        XCTAssertEqual(modelA.selection, .course("ICS3U"))
        XCTAssertEqual(WorkspaceModel.folderForNextNewWindow, folderB.path)

        // The new window appears (claims closed: a mid-session window).
        WindowFolderMemory.claimsOpenUntil = Date().addingTimeInterval(-1)
        let fresh: WorkspaceModel = newModel()
        windows.insert(fresh, at: 0)
        fresh.adoptFolderForNewWindow(among: windows)

        XCTAssertEqual(fresh.workspaceURL?.path, folderB.path)
        XCTAssertEqual(fresh.selection, .section("ICS3U", 1))
        XCTAssertNil(WorkspaceModel.folderForNextNewWindow, "taken once")
        XCTAssertNil(SectionFromNotification.request)
        XCTAssertEqual(modelA.selection, .course("ICS3U"))

        // A window the teacher opens later is not handed B by the click.
        SectionFromNotification.windowSettled(fresh)
        XCTAssertNil(WorkspaceModel.folderForNextNewWindow)
    }

    /// Review H1: the click's window at LAUNCH — claims still open, and a
    /// remembered window left unclaimed — takes the section's folder, claims
    /// nothing, and leaves the leftover where it was.
    func testTheClicksWindowTakesItsFolderWhileClaimsAreOpen() throws {
        let folderA: URL = try makeWorkingFolder("a")
        let folderB: URL = try makeWorkingFolder("b")
        let leftover: URL = try makeWorkingFolder("leftover")
        let modelA: WorkspaceModel = try window(on: folderA)
        windows = [modelA]
        opensAtOnce = false
        SectionFromNotification.receive(target(folderB.path, section: 1))
        XCTAssertEqual(windowsOpened, 1)

        WindowFolderMemory.reset(with: [WindowFolderMemory.Entry(path: leftover.path, frame: "{{0, 0}, {900, 700}}")])
        XCTAssertTrue(Date() <= WindowFolderMemory.claimsOpenUntil, "claims are open")
        let fresh: WorkspaceModel = newModel()
        windows.insert(fresh, at: 0)
        fresh.adoptFolderForNewWindow(among: windows)
        XCTAssertEqual(fresh.workspaceURL?.path, folderB.path)
        XCTAssertTrue(fresh.hasSettledItsFolder)

        // Its claimant, as `WindowRootView.attemptClaim` drives it, claims nothing.
        let claimant: WindowFolderClaimant = WindowFolderClaimant()
        XCTAssertNil(claimant.frameDidSettle("{{0, 0}, {900, 700}}", windowHasSettled: fresh.hasSettledItsFolder))
        XCTAssertNil(claimant.giveUp(windowHasSettled: fresh.hasSettledItsFolder))
        XCTAssertEqual(WindowFolderMemory.claimNextEntry()?.path, leftover.path, "the leftover is still there")
        XCTAssertEqual(fresh.workspaceURL?.path, folderB.path)
        XCTAssertEqual(fresh.selection, .section("ICS3U", 1))
        XCTAssertNil(WorkspaceModel.folderForNextNewWindow)
    }

    /// A window with no folder takes the section's folder, through #311's one
    /// route, and shows the section.
    func testTheFolderChooserTakesTheFolder() throws {
        let folder: URL = try makeWorkingFolder("this")
        let chooser: WorkspaceModel = newModel()
        chooser.settleItsFolder()
        windows = [chooser]

        SectionFromNotification.receive(target(folder.path, section: 2))

        XCTAssertEqual(chooser.workspaceURL?.path, folder.path)
        XCTAssertEqual(chooser.selection, .section("ICS3U", 2))
        XCTAssertEqual(windowsOpened, 0)
    }

    /// Nothing is decided while a window is still finding its folder; the
    /// moment it has, the click is answered — and a second settle of the same
    /// window (review M1) does not select again.
    func testNothingIsDecidedUntilLaunchWindowsSettle() throws {
        let folder: URL = try makeWorkingFolder("this")
        markTheLaunchSettled()
        let restoring: WorkspaceModel = newModel()
        windows = [restoring]

        SectionFromNotification.receive(target(folder.path, section: 2))
        XCTAssertNotNil(SectionFromNotification.request, "parked")
        XCTAssertEqual(broughtForward.count, 0)
        XCTAssertEqual(windowsOpened, 0)

        // Its claim lands: it reopens the folder it was on last time.
        XCTAssertTrue(restoring.reopen(RememberedFolder(path: folder.path, bookmark: nil), occasion: .rememberedWindow))
        XCTAssertNil(restoring.selection)
        restoring.settleItsFolder()
        XCTAssertEqual(restoring.selection, .section("ICS3U", 2))
        XCTAssertNil(SectionFromNotification.request)

        restoring.selection = .course("ICS3U")
        restoring.settleItsFolder()
        SectionFromNotification.windowSettled(restoring)
        XCTAssertEqual(restoring.selection, .course("ICS3U"), "a served click never selects again")
    }

    /// Review H2: a click that launches Plantoir arrives before any window
    /// exists. It waits; the first window to settle answers it — here, one
    /// still choosing a folder.
    func testAClickBeforeTheFirstWindowWaitsForIt() throws {
        let folder: URL = try makeWorkingFolder("this")
        windows = []

        SectionFromNotification.receive(target(folder.path, section: 2))
        XCTAssertEqual(windowsOpened, 0, "no window opened beside the one launch is about to show")
        XCTAssertNotNil(SectionFromNotification.request)

        let first: WorkspaceModel = newModel()
        windows = [first]
        first.settleItsFolder()
        XCTAssertEqual(first.workspaceURL?.path, folder.path)
        XCTAssertEqual(first.selection, .section("ICS3U", 2))
        XCTAssertEqual(windowsOpened, 0)
    }

    /// A folder that is not there only brings the app forward.
    func testAGoneFolderOnlyBringsTheAppForward() throws {
        let folderA: URL = try makeWorkingFolder("a")
        let modelA: WorkspaceModel = try window(on: folderA)
        modelA.selection = .course("ICS3U")
        windows = [modelA]
        let gone: String = scratch.appendingPathComponent("home/gone").path

        SectionFromNotification.receive(target(gone, section: 1))

        XCTAssertEqual(windowsOpened, 0)
        XCTAssertNil(WorkspaceModel.folderForNextNewWindow)
        XCTAssertEqual(modelA.workspaceURL?.path, folderA.path)
        XCTAssertEqual(modelA.selection, .course("ICS3U"))
        XCTAssertTrue(broughtForward.count == 1 && broughtForward[0] == nil)
        XCTAssertEqual(trailLines(), ["ICS3U/1 · " + SectionFromNotification.Outcome.folderGone.line])
    }

    /// A window mid-rename, or with a dialog in front of it, keeps its
    /// selection — the #293 focus-loss commit is the harm.
    func testABusyWindowKeepsItsSelection() throws {
        let folder: URL = try makeWorkingFolder("this")
        let renaming: WorkspaceModel = try window(on: folder)
        renaming.selection = .course("ICS3U")
        renaming.renamingCourseCode = "ICS3U"
        windows = [renaming]
        SectionFromNotification.receive(target(folder.path, section: 2))
        XCTAssertEqual(renaming.selection, .course("ICS3U"))
        XCTAssertTrue(broughtForward.count == 1 && broughtForward[0] === renaming)

        renaming.renamingCourseCode = nil
        withASheet = [renaming]
        broughtForward = []
        SectionFromNotification.receive(target(folder.path, section: 2))
        XCTAssertEqual(renaming.selection, .course("ICS3U"))
        XCTAssertEqual(windowsOpened, 0)
    }

    /// A section no longer in the folder is not guessed at, in a window
    /// already there or a new one.
    func testAMissingSectionIsNotGuessedAt() throws {
        let folder: URL = try makeWorkingFolder("this")
        let model: WorkspaceModel = try window(on: folder)
        model.selection = .course("ICS3U")
        windows = [model]
        SectionFromNotification.receive(target(folder.path, section: 9))
        XCTAssertEqual(model.selection, .course("ICS3U"))

        let other: URL = try makeWorkingFolder("other")
        let onOther: WorkspaceModel = try window(on: other)
        windows = [onOther]
        SectionFromNotification.receive(target(folder.path, section: 9))
        XCTAssertEqual(openedModels.count, 1)
        XCTAssertEqual(openedModels.first?.workspaceURL?.path, folder.path)
        XCTAssertNil(openedModels.first?.selection)
    }

    /// A click still waiting when the app goes to the background is dropped,
    /// and with it the folder set aside for a new window (review H1).
    func testAParkedRequestIsForgottenWhenTheAppGoesInactive() throws {
        let folder: URL = try makeWorkingFolder("this")
        markTheLaunchSettled()
        let restoring: WorkspaceModel = newModel()
        windows = [restoring]
        SectionFromNotification.receive(target(folder.path, section: 2))
        SectionFromNotification.forgetPendingRequest()
        restoring.settleItsFolder()
        XCTAssertNil(restoring.workspaceURL)
        XCTAssertNil(restoring.selection)

        let other: URL = try makeWorkingFolder("other")
        let onOther: WorkspaceModel = try window(on: other)
        windows = [onOther]
        opensAtOnce = false
        SectionFromNotification.receive(target(folder.path, section: 2))
        XCTAssertEqual(WorkspaceModel.folderForNextNewWindow, folder.path)
        SectionFromNotification.forgetPendingRequest()
        XCTAssertNil(WorkspaceModel.folderForNextNewWindow, "a later window is not given it")
        XCTAssertNil(SectionFromNotification.request)
    }

    // MARK: - Functions

    /// Play one contract case through the router.
    private func play(_ oneCase: [String: Any]) throws {
        let name: String = try XCTUnwrap(oneCase["name"] as? String)
        SectionFromNotification.resetForTests()
        installStandIns()
        windows = []
        broughtForward = []
        openedModels = []
        withASheet = []
        windowsOpened = 0
        WorkspaceModel.folderForNextNewWindow = nil
        WindowFolderMemory.claimsOpenUntil = Date().addingTimeInterval(-1)
        ActivityTrail.store = ProblemReportStore(folderURL: scratch.appendingPathComponent("trail-\(UUID().uuidString)"))

        let slug: String = String(UUID().uuidString.prefix(6))
        let thisFolder: URL = try makeWorkingFolder("this-" + slug)
        let otherFolder: URL = try makeWorkingFolder("other-" + slug)
        let launching: Bool = oneCase["launching"] as? Bool ?? false
        if !launching {
            markTheLaunchSettled()
        }

        var built: [WorkspaceModel] = []
        var before: [(path: String?, selection: SidebarSelection?)] = []
        for window in try XCTUnwrap(oneCase["windows"] as? [[String: Any]], name) {
            let relation: SectionFromNotification.FolderRelation = try Self.relation(window, name)
            let settled: Bool = window["settled"] as? Bool ?? true
            let model: WorkspaceModel = newModel()
            switch relation {
            case .this:
                model.adoptRestoredPath(thisFolder.path)
                model.selection = .course("ICS3U")
            case .other:
                model.adoptRestoredPath(otherFolder.path)
                model.selection = .course("ICS3U")
            case .none:
                break
            }
            if window["busy"] as? Bool ?? false {
                model.renamingCourseCode = relation == .none ? "NEW" : "ICS3U"
            }
            built.append(model)
            before.append((model.workspaceURL?.path, model.selection))
        }
        // Settled only once every window is built, so a settle cannot answer
        // a click nobody has made yet.
        let windowList: [[String: Any]] = try XCTUnwrap(oneCase["windows"] as? [[String: Any]], name)
        var index: Int = 0
        while index < built.count {
            if windowList[index]["settled"] as? Bool ?? true {
                built[index].settleItsFolder()
            }
            index += 1
        }
        windows = built

        let folderExists: Bool = oneCase["folderExists"] as? Bool ?? true
        let sectionInFolder: Bool = oneCase["sectionInFolder"] as? Bool ?? true
        var path: String = thisFolder.path
        if !folderExists {
            path = home.appendingPathComponent("gone-" + slug).path
        }
        let section: Int = sectionInFolder ? 2 : 9
        let home2: URL = scratch.appendingPathComponent("records-" + slug)
        let folderID: String = BuildOutputLocation.folderIdentifier(forWorkingFolder: thisFolder.path)
        XCTAssertTrue(ScheduledPublishOutcome.recordStopped(
            ScheduledPublishOutcome.Stopped(kind: .succeeded, destination: "Netlify", when: Date()),
            inHomeFolder: home2, course: "ICS3U", section: section, folderID: folderID
        ), name)

        let carries: Bool = try XCTUnwrap(oneCase["carries"] as? Bool, name)
        if carries {
            SectionFromNotification.receive(target(path, section: section))
        } else {
            SectionFromNotification.receive(nil)
        }

        let expect: [String: Any] = try XCTUnwrap(oneCase["expect"] as? [String: Any], name)
        let action: String = try XCTUnwrap(expect["action"] as? String, name)
        if action == "wait" {
            XCTAssertNotNil(SectionFromNotification.request, name)
            XCTAssertEqual(broughtForward.count, 0, name)
            XCTAssertEqual(windowsOpened, 0, name)
            XCTAssertEqual(trailLines(), [], name)
            return
        }
        XCTAssertNil(SectionFromNotification.request, "\(name): the click is over")
        XCTAssertNil(WorkspaceModel.folderForNextNewWindow, name)

        var used: WorkspaceModel?
        if let window = expect["window"] as? Int {
            used = built[window]
        }
        if action == "openNewWindow" {
            used = openedModels.first
            XCTAssertEqual(used?.workspaceURL?.path, thisFolder.path, name)
        }
        if action == "adoptInto" {
            XCTAssertEqual(used?.workspaceURL?.path, thisFolder.path, name)
        }
        if let opens = expect["opensAWindow"] as? Bool {
            XCTAssertEqual(windowsOpened, opens ? 1 : 0, name)
        }
        let selects: Bool = try XCTUnwrap(expect["selectsTheSection"] as? Bool, name)
        if let used {
            if selects {
                XCTAssertEqual(used.selection, .section("ICS3U", section), name)
                XCTAssertTrue(used.expandedCourseCodes.contains("ICS3U"), name)
            } else if action == "openNewWindow" {
                XCTAssertNil(used.selection, name)
            } else {
                var usedIndex: Int = 0
                while usedIndex < built.count && built[usedIndex] !== used {
                    usedIndex += 1
                }
                XCTAssertEqual(used.selection, before[usedIndex].selection, name)
            }
            XCTAssertTrue(broughtForward.count == 1 && broughtForward[0] === used, name)
        } else {
            XCTAssertFalse(selects, name)
            XCTAssertTrue(broughtForward.count == 1 && broughtForward[0] == nil, name)
        }
        // Every listed window the click did not use keeps its folder and selection.
        index = 0
        while index < built.count {
            if built[index] !== used {
                XCTAssertEqual(built[index].workspaceURL?.path, before[index].path, "\(name): window \(index)")
                XCTAssertEqual(built[index].selection, before[index].selection, "\(name): window \(index)")
            }
            index += 1
        }
        // The record the band reads is untouched, whatever the click did.
        XCTAssertNotNil(ScheduledPublishOutcome.stopped(
            inHomeFolder: home2, course: "ICS3U", section: section, folderID: folderID
        ), name)

        let trailSays: String = try XCTUnwrap(oneCase["trailSays"] as? String, "\(name) has no trailSays")
        if carries {
            XCTAssertEqual(trailLines(), ["ICS3U/\(section) · " + trailSays], name)
        } else {
            XCTAssertEqual(trailLines(), [trailSays], name)
        }
    }

    /// The router's stand-ins: this test's windows, no real activation, and an
    /// opener that makes a window model the way `WindowRootView` does.
    private func installStandIns() {
        SectionFromNotification.windowsFrontToBack = { [unowned self] () -> [WorkspaceModel] in
            return self.windows
        }
        SectionFromNotification.bringForward = { [unowned self] (model: WorkspaceModel?) in
            self.broughtForward.append(model)
        }
        SectionFromNotification.sheetIsUp = { [unowned self] (model: WorkspaceModel) -> Bool in
            for withSheet in self.withASheet {
                if withSheet === model {
                    return true
                }
            }
            return false
        }
        SectionFromNotification.openMainWindow = { [unowned self] in
            self.windowsOpened += 1
            if !self.opensAtOnce {
                return
            }
            let fresh: WorkspaceModel = self.newModel()
            self.openedModels.append(fresh)
            self.windows.insert(fresh, at: 0)
            fresh.adoptFolderForNewWindow(among: self.windows)
        }
    }

    /// A settle from a window of an earlier moment in this launch: the app is
    /// past its first window.
    private func markTheLaunchSettled() {
        newModel().settleItsFolder()
    }

    private func newModel() -> WorkspaceModel {
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        WorkspaceModel.registerWindowModel(model)
        registered.append(model)
        return model
    }

    private func window(on folder: URL) throws -> WorkspaceModel {
        let model: WorkspaceModel = newModel()
        model.adoptRestoredPath(folder.path)
        XCTAssertEqual(model.workspaceURL?.path, folder.path)
        model.settleItsFolder()
        return model
    }

    private func target(_ path: String, section: Int) -> NotificationClickTarget {
        return NotificationClickTarget(workingFolderPath: path, course: "ICS3U", section: section)
    }

    /// A working folder inside the test's home, with ICS3U sections 1 and 2.
    private func makeWorkingFolder(_ name: String) throws -> URL {
        let fileManager: FileManager = FileManager.default
        let root: URL = home.appendingPathComponent(name, isDirectory: true)
        let course: URL = root.appendingPathComponent("courses/ICS3U")
        for section in ["section1", "section2"] {
            try fileManager.createDirectory(
                at: course.appendingPathComponent(section).appendingPathComponent("All Classes"),
                withIntermediateDirectories: true
            )
        }
        try "#!/bin/bash\n".write(to: root.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        try "#!/bin/bash\n".write(to: root.appendingPathComponent("deploy.sh"), atomically: true, encoding: .utf8)
        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: course.appendingPathComponent("course_config.json"))
        return root
    }

    /// The trail's lines about a click, in order, without their timestamps.
    private func trailLines() -> [String] {
        var outcomes: [String] = []
        let all: [SectionFromNotification.Outcome] = [
            .shown, .shownInNewWindow, .shownInChooser, .busy, .sectionGone, .folderGone, .namesNothing,
        ]
        for outcome in all {
            outcomes.append(outcome.line)
        }
        var lines: [String] = []
        let text: String = ActivityTrail.store.activityText(includingPrompts: true)
        for line in text.components(separatedBy: "\n") {
            for outcome in outcomes {
                if let range = line.range(of: outcome), range.upperBound == line.endIndex {
                    var start: String.Index = range.lowerBound
                    if let prefix = line.range(of: "ICS3U/"), prefix.upperBound <= range.lowerBound {
                        start = prefix.lowerBound
                    }
                    lines.append(String(line[start...]))
                    break
                }
            }
        }
        return lines
    }

    private static func cases() throws -> [[String: Any]] {
        let section: [String: Any] = try SharedRulesContractTests.section("scheduledPublishStopped")
        let notification: [String: Any] = try XCTUnwrap(section["notification"] as? [String: Any])
        let onClick: [String: Any] = try XCTUnwrap(notification["onClick"] as? [String: Any], "No notification.onClick")
        XCTAssertNotNil(onClick["howToRunACase"] as? String)
        XCTAssertNotNil(onClick["rule"] as? String)
        return try XCTUnwrap(onClick["cases"] as? [[String: Any]])
    }

    private static func appliesToTheMac(_ entry: [String: Any]) -> Bool {
        guard let platforms = entry["appliesOn"] as? [String] else {
            return true
        }
        return platforms.contains("mac")
    }

    private static func relation(_ window: [String: Any], _ name: String) throws -> SectionFromNotification.FolderRelation {
        let folder: String = try XCTUnwrap(window["folder"] as? String, name)
        switch folder {
        case "this":
            return .this
        case "other":
            return .other
        case "none":
            return .none
        default:
            XCTFail("\(name): a window on '\(folder)'")
            return .none
        }
    }
}
