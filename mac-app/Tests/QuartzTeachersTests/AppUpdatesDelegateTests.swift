import Sparkle
import XCTest
@testable import QuartzTeachers

/// The updater's hooks, the held install and the set-aside at quit (#204),
/// driven through the REAL delegate and wrapper with a stand-in for the
/// updater's windows — so nothing appears on screen and nothing is fetched.
///
/// Resets `CourseActivity` around each test, like `QuitConfirmationTests`;
/// the mac suite runs its classes one at a time (`parallelizable = "NO"`).
@MainActor
final class AppUpdatesDelegateTests: XCTestCase {

    // MARK: - Stored properties

    private var scratchTrail: URL?
    private var previousStore: ProblemReportStore?

    // MARK: - Set up

    override func setUp() async throws {
        CourseActivity.reset()
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-trail-\(UUID().uuidString)", isDirectory: true)
        scratchTrail = folder
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folder)
    }

    override func tearDown() async throws {
        CourseActivity.reset()
        if let previousStore {
            ActivityTrail.store = previousStore
        }
        if let scratchTrail {
            try? FileManager.default.removeItem(at: scratchTrail)
        }
    }

    // MARK: - The hooks are the ones the updater calls

    /// A near-miss Swift name COMPILES — with one warning — and the updater
    /// never calls it: spelled `…untilInvoking:`, the install gate would
    /// silently never run (measured for #204's plan). Asked of the runtime,
    /// which is what the updater asks.
    func testTheDelegateAnswersEveryHookItRelies() {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let hooks: [(String, Selector)] = [
            ("the install gate's last look", #selector(SPUUpdaterDelegate.updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:))),
            ("update stopped", #selector(SPUUpdaterDelegate.updater(_:didAbortWithError:))),
            ("update found", #selector(SPUUpdaterDelegate.updater(_:didFindValidUpdate:))),
            ("update answered", #selector(SPUUpdaterDelegate.updater(_:userDidMake:forUpdate:state:))),
            ("update installing", #selector(SPUUpdaterDelegate.updater(_:willInstallUpdate:))),
            ("the end of a session", #selector(SPUUpdaterDelegate.updater(_:didFinishUpdateCycleFor:error:)))
        ]
        for (purpose, selector) in hooks {
            XCTAssertTrue(updates.responds(to: selector), "\(purpose): the updater will never call it")
        }
        let driver: HoldingUserDriver = HoldingUserDriver(standard: StandInWindows(), owner: updates)
        XCTAssertTrue(driver.responds(to: #selector(SPUUserDriver.showReady(toInstallAndRelaunch:))))
    }

    // MARK: - Install and Relaunch

    /// Nothing under way: the teacher's Install reaches the installer at once.
    func testInstallGoesStraightThroughWhenNothingIsUnderWay() {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let windows: StandInWindows = StandInWindows()
        let driver: HoldingUserDriver = HoldingUserDriver(standard: windows, owner: updates)
        updates.adopt(driver)
        var answers: [SPUUserUpdateChoice] = []

        driver.showReady { choice in
            answers.append(choice)
        }
        XCTAssertEqual(updates.prepared, .readyToInstall)
        windows.pressInstallAndRelaunch()

        XCTAssertEqual(answers, [.install])
        XCTAssertEqual(updates.prepared, .none)
    }

    /// Work under way: the answer is KEPT — the installer hears nothing —
    /// and it goes on by itself the moment the work ends (Russell, Q3).
    func testInstallIsHeldWhilePublishingAndGoesOnWhenItEnds() async throws {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let windows: StandInWindows = StandInWindows()
        let driver: HoldingUserDriver = HoldingUserDriver(standard: windows, owner: updates)
        updates.adopt(driver)
        var answers: [SPUUserUpdateChoice] = []
        let installed: XCTestExpectation = expectation(description: "the install went on")

        CourseActivity.beginPublish(folderPath: "/pretend", courseCode: "ADA1O", sectionNumber: 2)
        driver.showReady { choice in
            answers.append(choice)
            installed.fulfill()
        }
        windows.pressInstallAndRelaunch()

        XCTAssertEqual(answers, [], "The installer was told while a publish was under way")
        XCTAssertEqual(updates.prepared, .heldForWork)
        XCTAssertTrue(windows.wasDismissed, "The updater's own window was left up with a button that does nothing")
        let work: String = try XCTUnwrap(QuitConfirmation.workUnderWay(
            publishes: CourseActivity.activePublishes, previews: []
        ))
        XCTAssertTrue(
            try AppUpdatesDelegateTests.trailText().contains(UpdateTrail.heldLine(work: work, version: "?")),
            "The trail does not say what the install was held for, in the words the teacher was shown"
        )

        CourseActivity.endPublish(folderPath: "/pretend", courseCode: "ADA1O", sectionNumber: 2)
        await fulfillment(of: [installed], timeout: 10)
        XCTAssertEqual(answers, [.install])
        XCTAssertEqual(updates.prepared, .none)
    }

    // MARK: - Quitting

    /// H1: a quit with the install held and the work still going tells the
    /// installer to stand down ("skip") — never "install" — and the quit
    /// waits only for the updater to say the session is over.
    func testAQuitWhileHeldSetsTheUpdateAside() throws {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let windows: StandInWindows = StandInWindows()
        let driver: HoldingUserDriver = HoldingUserDriver(standard: windows, owner: updates)
        updates.adopt(driver)
        var answers: [SPUUserUpdateChoice] = []

        CourseActivity.beginPublish(folderPath: "/pretend", courseCode: "ADA1O", sectionNumber: 2)
        driver.showReady { choice in
            answers.append(choice)
        }
        windows.pressInstallAndRelaunch()
        XCTAssertEqual(updates.prepared, .heldForWork)

        XCTAssertEqual(updates.decideAtQuit(), .setAside)
        var quitFinished: Bool = false
        updates.setAsideForQuit {
            quitFinished = true
        }
        XCTAssertEqual(answers, [.skip], "The installer was not told to stand down")
        XCTAssertFalse(quitFinished, "The quit went ahead before the updater confirmed")

        updates.updater(AppUpdatesDelegateTests.unstartedUpdater(), didFinishUpdateCycleFor: .updates, error: nil)
        XCTAssertTrue(quitFinished)
        XCTAssertEqual(updates.prepared, .none)
        XCTAssertTrue(try AppUpdatesDelegateTests.trailText().contains("aside"))
    }

    /// Ready and nothing under way: the quit lets it install on the way out,
    /// and says so.
    func testAQuitWithNothingUnderWayLetsItInstall() throws {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let windows: StandInWindows = StandInWindows()
        let driver: HoldingUserDriver = HoldingUserDriver(standard: windows, owner: updates)
        updates.adopt(driver)
        var answers: [SPUUserUpdateChoice] = []
        driver.showReady { choice in
            answers.append(choice)
        }
        XCTAssertEqual(updates.decideAtQuit(), .installsAsItQuits)
        XCTAssertEqual(answers, [], "Nothing needs saying to the installer: it installs as the app quits")
        XCTAssertTrue(try AppUpdatesDelegateTests.trailText().contains("as Plantoir quits"))
    }

    func testAQuitWithNothingPreparedDoesNothing() {
        XCTAssertEqual(AppUpdatesDelegateTests.updatesReadingOnlyThisApp().decideAtQuit(), .nothingToDo)
    }

    // MARK: - The menu item while held (the slice-1 review's M2)

    /// A click while held re-shows the notice and is not a new check the
    /// teacher asked for: the updater is never asked.
    func testCheckingWhileHeldDoesNotStartACheck() throws {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let windows: StandInWindows = StandInWindows()
        let driver: HoldingUserDriver = HoldingUserDriver(standard: windows, owner: updates)
        updates.adopt(driver)
        CourseActivity.beginPublish(folderPath: "/pretend", courseCode: "ADA1O", sectionNumber: 2)
        driver.showReady { _ in }
        windows.pressInstallAndRelaunch()
        XCTAssertTrue(updates.isHoldingAnInstall)
        let shownBefore: Int = updates.heldNoticesShown
        updates.checkForUpdates()
        XCTAssertEqual(updates.heldNoticesShown, shownBefore + 1, "The menu item did not bring the held notice back")
        XCTAssertTrue(updates.isHoldingAnInstall, "The held install was disturbed by the menu item")
        XCTAssertEqual(updates.prepared, .heldForWork)
    }

    // MARK: - The resumed window (the slice-1 review's L3)

    /// When a check finds an installer already prepared, the updater's window
    /// offers Install and Relaunch again. That answer comes through the same
    /// gate: held while publishing, and a quit then sets it aside.
    func testTheResumedWindowIsHeldAndSetAsideLikeTheReadyOne() throws {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let windows: StandInWindows = StandInWindows()
        let driver: HoldingUserDriver = HoldingUserDriver(standard: windows, owner: updates)
        updates.adopt(driver)
        var answers: [SPUUserUpdateChoice] = []
        CourseActivity.beginPublish(folderPath: "/pretend", courseCode: "ADA1O", sectionNumber: 2)
        driver.showUpdateFound(
            with: SUAppcastItem.empty(),
            state: AppUpdatesDelegateTests.state(.installing)
        ) { choice in
            answers.append(choice)
        }
        XCTAssertEqual(updates.prepared, .readyToInstall)
        windows.answerTheUpdateWindow(.install)
        XCTAssertEqual(answers, [], "The resumed window's Install reached the installer while publishing")
        XCTAssertEqual(updates.prepared, .heldForWork)
        XCTAssertEqual(updates.decideAtQuit(), .setAside)
        updates.setAsideForQuit {}
        XCTAssertEqual(answers, [.skip])
        // The updater's resumed window reports the forwarded skip as a choice
        // before acting on it; the trail must not call it the teacher's.
        updates.updater(
            AppUpdatesDelegateTests.unstartedUpdater(),
            userDidMake: .skip,
            forUpdate: SUAppcastItem.empty(),
            state: AppUpdatesDelegateTests.state(.installing)
        )
        XCTAssertFalse(
            try AppUpdatesDelegateTests.trailText().contains(UpdateTrail.Answer.skip.rawValue),
            "A set-aside was written as the teacher's Skip"
        )
    }

    /// "Install on Quit" keeps the answer, so a quit with work under way can
    /// still set it aside.
    func testInstallOnQuitInTheResumedWindowKeepsTheAnswer() throws {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let windows: StandInWindows = StandInWindows()
        let driver: HoldingUserDriver = HoldingUserDriver(standard: windows, owner: updates)
        updates.adopt(driver)
        var answers: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(
            with: SUAppcastItem.empty(),
            state: AppUpdatesDelegateTests.state(.installing)
        ) { choice in
            answers.append(choice)
        }
        windows.answerTheUpdateWindow(.dismiss)
        XCTAssertEqual(answers, [])
        XCTAssertTrue(
            try AppUpdatesDelegateTests.trailText().contains(UpdateTrail.answeredLine(answer: .installOnQuit, version: "?")),
            "Install on Quit never reaches the updater, so the trail line is ours to write"
        )
        CourseActivity.beginPreviewBuild(folderPath: "/pretend", courseCode: "ENG2D", sectionNumber: 1)
        XCTAssertEqual(updates.decideAtQuit(), .setAside)
    }

    /// Stages other than installing are passed straight through.
    func testAnOrdinaryOfferIsPassedStraightThrough() {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let windows: StandInWindows = StandInWindows()
        let driver: HoldingUserDriver = HoldingUserDriver(standard: windows, owner: updates)
        var answers: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(
            with: SUAppcastItem.empty(),
            state: AppUpdatesDelegateTests.state(.notDownloaded)
        ) { choice in
            answers.append(choice)
        }
        windows.answerTheUpdateWindow(.install)
        XCTAssertEqual(answers, [.install])
        XCTAssertEqual(updates.prepared, .none)
    }

    // MARK: - The installer's last look

    func testTheLastLookHoldsOnlyWhenWorkIsUnderWay() {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let updater: SPUUpdater = AppUpdatesDelegateTests.unstartedUpdater()
        var ran: Int = 0
        XCTAssertFalse(updates.updater(updater, shouldPostponeRelaunchForUpdate: SUAppcastItem.empty()) {
            ran += 1
        })
        XCTAssertEqual(updates.prepared, .none)

        CourseActivity.beginPreviewBuild(folderPath: "/pretend", courseCode: "ENG2D", sectionNumber: 1)
        XCTAssertTrue(updates.updater(updater, shouldPostponeRelaunchForUpdate: SUAppcastItem.empty()) {
            ran += 1
        })
        XCTAssertEqual(updates.prepared, .postponedAtInstall)
        XCTAssertEqual(ran, 0)
        XCTAssertEqual(updates.decideAtQuit(), .installsAsItQuits, "The answer has gone; the quit cannot stop it")
    }

    // MARK: - The trail

    /// The updater says nothing when an administrator's password was asked
    /// for and not given (4007): the trail does, and a failed DAILY check is
    /// written at most once a launch.
    func testStopsAreWrittenOnceForTheDailyCheck() throws {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let updater: SPUUpdater = AppUpdatesDelegateTests.unstartedUpdater()
        let offline: NSError = NSError(domain: "SUSparkleErrorDomain", code: 2001)
        updates.updater(updater, didAbortWithError: offline)
        updates.updater(updater, didAbortWithError: offline)
        let nothingNew: NSError = NSError(domain: "SUSparkleErrorDomain", code: 1001)
        updates.updater(updater, didAbortWithError: nothingNew)

        let trail: String = try AppUpdatesDelegateTests.trailText()
        XCTAssertEqual(AppUpdatesDelegateTests.count(of: "[2001]", in: trail), 1)
        XCTAssertEqual(AppUpdatesDelegateTests.count(of: "[1001]", in: trail), 0)
    }

    func testNothingNewIsWrittenOnlyWhenTheTeacherAsked() throws {
        let updates: AppUpdates = AppUpdatesDelegateTests.updatesReadingOnlyThisApp()
        let updater: SPUUpdater = AppUpdatesDelegateTests.unstartedUpdater()
        let nothingNew: NSError = NSError(domain: "SUSparkleErrorDomain", code: 1001)
        updates.updater(updater, didFinishUpdateCycleFor: .updatesInBackground, error: nothingNew)
        XCTAssertFalse(try AppUpdatesDelegateTests.trailText().contains("is the newest"))
    }

    // MARK: - Helpers

    /// An `AppUpdates` whose gate sees this app's own record and nothing of
    /// the machine: no process table, no lease folders (the slice-1 review's
    /// L4). The test host shares an executable with the Debug app a teacher
    /// opens, so the live scan could find that app's scheduled publish.
    static func updatesReadingOnlyThisApp() -> AppUpdates {
        let updates: AppUpdates = AppUpdates()
        updates.factsProvider = {
            return UpdateGate.Facts(
                publishes: CourseActivity.activePublishes,
                previewBuilds: CourseActivity.activePreviewBuilds,
                previews: [],
                otherCopies: [],
                leases: []
            )
        }
        return updates
    }

    /// The updater's state object has no public initializer; made through the
    /// runtime and set by key, the way the updater itself would hold it.
    static func state(_ stage: SPUUserUpdateStage) -> SPUUserUpdateState {
        let made: AnyObject = (SPUUserUpdateState.self as AnyObject)
            .perform(NSSelectorFromString("new"))
            .takeRetainedValue()
        guard let state = made as? SPUUserUpdateState else {
            fatalError("SPUUserUpdateState could not be made")
        }
        state.setValue(stage.rawValue, forKey: "stage")
        return state
    }

    static func unstartedUpdater() -> SPUUpdater {
        return SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: StandInWindows(),
            delegate: nil
        )
    }

    static func trailText() throws -> String {
        let folder: URL = ActivityTrail.store.folderURL
        var text: String = ""
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(name)) {
                text += String(decoding: data, as: UTF8.self)
            }
        }
        return text
    }

    static func count(of needle: String, in text: String) -> Int {
        return text.components(separatedBy: needle).count - 1
    }
}

/// The updater's windows, without a window: records what it was asked, and
/// can press "Install and Relaunch".
final class StandInWindows: NSObject, SPUUserDriver {

    // MARK: - Stored properties

    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var foundReply: ((SPUUserUpdateChoice) -> Void)?
    private(set) var wasDismissed: Bool = false

    // MARK: - Functions

    func pressInstallAndRelaunch() {
        let reply: ((SPUUserUpdateChoice) -> Void)? = readyReply
        readyReply = nil
        reply?(.install)
    }

    func answerTheUpdateWindow(_ choice: SPUUserUpdateChoice) {
        let reply: ((SPUUserUpdateChoice) -> Void)? = foundReply
        foundReply = nil
        reply?(choice)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        readyReply = reply
    }

    func dismissUpdateInstallation() {
        wasDismissed = true
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {}
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        foundReply = reply
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {}
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {}
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {}
}
