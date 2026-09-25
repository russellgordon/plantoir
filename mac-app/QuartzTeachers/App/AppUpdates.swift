import AppKit
import Observation
import Sparkle
import SwiftUI

/// Plantoir finding and installing its own new versions (#204).
///
/// **What is settled, and where.** Ask first, check once a day, never install
/// while work is under way, never a development feed, quit never refused:
/// `contracts/shared-rules.json` → `appUpdates`, from the decisions on #204.
/// The reasoning, what was measured and what was rejected:
/// `documentation/09-mac-app.md` → "Updating itself".
///
/// **Created only in `applicationDidFinishLaunching`, and only when the bundle
/// carries a feed.** Never as a stored property of the `App` struct: Swift
/// initialises those BEFORE `init()` runs, so the updater would start inside
/// the assistant's server and inside a scheduled publish, before the checks
/// that turn those launches away. Three independent things keep it out of
/// them — they never reach `applicationDidFinishLaunching`, `shouldStart`
/// refuses their flags, and nothing is created until `start()` — and
/// `AppUpdatesStartTests` pins each.
///
/// **Holding an install.** The updater's own window asks the teacher to
/// "Install and Relaunch". Its answer passes through `HoldingUserDriver`, which
/// hands it here instead of straight to the installer: with nothing under way
/// it goes on at once; with work under way (`UpdateGate`) it is KEPT, the
/// teacher is told why, and the install goes on by itself the moment the
/// work is done (Russell, #204 Q3). Keeping the answer — rather than letting
/// the installer have it and postponing its relaunch — is what makes a quit
/// safe: the installer, once prepared, installs on ANY quit, and the only
/// thing that stands it down is being told "skip" before it has been told
/// "install" (the plan review's H1; `SPUCoreBasedUpdateDriver`
/// `finishInstallationWithResponse:` → `cancelUpdate`). So a quit with the
/// answer still here and work under way sets the update aside
/// (`UpdateGate.quitAction`).
@Observable
final class AppUpdates: NSObject, SPUUpdaterDelegate {

    // MARK: - Stored properties

    static let shared: AppUpdates = AppUpdates()

    /// Whether an updater exists — false in every development build, which
    /// has no feed, and in the test host. The menu item is drawn only when
    /// this is true.
    private(set) var isRunning: Bool = false

    /// The updater's own answer, kept in step with it: false while an update
    /// session is open — including while an install is held here, which is
    /// what stops a second "Install" from reaching the installer.
    private(set) var canCheckForUpdates: Bool = false

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var userDriver: HoldingUserDriver?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// Where an update stands, as far as quitting is concerned.
    @ObservationIgnored private(set) var prepared: UpdateGate.PreparedUpdate = .none

    /// The installer's question, still unanswered: "Install and Relaunch?".
    @ObservationIgnored private var readyReply: ((SPUUserUpdateChoice) -> Void)?

    /// The installer's LAST question, "may I relaunch now?", answered "not
    /// yet" (`updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)`).
    @ObservationIgnored private var postponedInstall: (() -> Void)?

    /// What the install is being held for, in the teacher's words.
    @ObservationIgnored private var heldWork: String?

    /// The version in hand, "1.3.2 (3120)".
    @ObservationIgnored private var versionInHand: String?

    /// How the install now under way came about, for `update installing`.
    @ObservationIgnored private var installMoment: UpdateTrail.InstallMoment = .straightAway

    /// Watches for held work to end.
    @ObservationIgnored private var watchTask: Task<Void, Never>?

    /// The notice saying why the install is waiting.
    @ObservationIgnored private var heldNotice: NSAlert?

    /// Versions already written as `update found` in this launch.
    @ObservationIgnored private var versionsFoundThisLaunch: [String] = []

    /// Whether the check now running is one the teacher asked for.
    @ObservationIgnored private var teacherAskedForThisCheck: Bool = false

    /// Whether a failure of the DAILY check has been written this launch.
    @ObservationIgnored private var hasNotedADailyCheckFailure: Bool = false

    /// What finishes a quit that is waiting for a set-aside update to stand
    /// down.
    @ObservationIgnored private var quitWaiter: (() -> Void)?

    // MARK: - Computed properties

    /// This version, "1.3.1 (3100)".
    static var runningVersion: String {
        let info: [String: Any] = Bundle.main.infoDictionary ?? [:]
        let version: String = info["CFBundleShortVersionString"] as? String ?? "?"
        let build: String = info["CFBundleVersion"] as? String ?? "?"
        return UpdateTrail.versionText(version: version, build: build)
    }

    /// Whether an updater was ever created in this process — for the test
    /// that proves the suite never creates one.
    var hasAnUpdater: Bool {
        return updater != nil
    }

    // MARK: - Functions

    /// Whether this launch should have an updater at all.
    ///
    /// No under tests; no for the assistant's server, a scheduled publish, or
    /// writing the contracts (each read from its own constant, never retyped);
    /// no when the bundle has no feed — every development build.
    nonisolated static func shouldStart(
        infoDictionary: [String: Any],
        arguments: [String],
        isRunningTests: Bool,
        headlessFlags: [String]
    ) -> Bool {
        if isRunningTests {
            return false
        }
        for flag in headlessFlags {
            if arguments.contains(flag) {
                return false
            }
        }
        guard let feed = infoDictionary["SUFeedURL"] as? String else {
            return false
        }
        return !feed.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The flags that turn this binary into something other than an app.
    static var headlessFlags: [String] {
        return [AssistMCPServer.flag, ScheduledDeploy.runFlag, AssistContract.flag]
    }

    /// Creates the updater and starts its daily check. Called once, from
    /// `applicationDidFinishLaunching`, and only when `shouldStart` says so.
    func start() {
        if updater != nil {
            return
        }
        let driver: HoldingUserDriver = HoldingUserDriver(hostBundle: Bundle.main, owner: self)
        let made: SPUUpdater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: driver,
            delegate: self
        )
        // The updater reads a feed address from the user defaults BEFORE the
        // Info.plist, so `defaults write … SUFeedURL …` would point a released
        // Plantoir somewhere else — a development feed by another name
        // (decision 5; the plan review's M4). Cleared every launch.
        _ = made.clearFeedURLFromUserDefaults()
        userDriver = driver
        updater = made
        // The updater changes this on the main thread (it is a main-actor
        // type), so the observation is delivered there too.
        canCheckObservation = made.observe(\.canCheckForUpdates, options: [.initial, .new]) { observed, _ in
            MainActor.assumeIsolated {
                AppUpdates.shared.canCheckForUpdates = observed.canCheckForUpdates
            }
        }
        do {
            try made.start()
            isRunning = true
        } catch {
            let code: Int = (error as NSError).code
            ActivityTrail.note(.updateStopped, UpdateTrail.stoppedLine(version: nil, code: code))
        }
    }

    /// Check for Updates…, from the menu.
    func checkForUpdates() {
        guard let updater else {
            return
        }
        teacherAskedForThisCheck = true
        updater.checkForUpdates()
    }

    // MARK: - Functions: the install, held and let go

    /// The installer is prepared and asking "Install and Relaunch?". The
    /// question is kept here until the teacher answers it.
    func updateIsReady(reply: @escaping (SPUUserUpdateChoice) -> Void) {
        readyReply = reply
        prepared = .readyToInstall
    }

    /// The teacher answered the updater's "Install and Relaunch".
    func teacherAnsweredReady(_ choice: SPUUserUpdateChoice) {
        if choice != .install {
            forwardReady(choice)
            return
        }
        guard let work = UpdateGate.workUnderWay() else {
            installNow(.straightAway)
            return
        }
        prepared = .heldForWork
        // The updater's own "Ready to Install" window stays up with a button
        // that now does nothing; close it so the only thing on screen says
        // what is happening.
        userDriver?.closeTheUpdatersWindows()
        hold(for: work)
    }

    /// The installer's last question before relaunching. Asked again here in
    /// case work began in the instant since the teacher's Install — after
    /// which the answer has gone, and a quit would install anyway (the one
    /// case `appUpdates.atQuit` says cannot be prevented).
    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard let work = UpdateGate.workUnderWay() else {
            return false
        }
        postponedInstall = installHandler
        prepared = .postponedAtInstall
        hold(for: work)
        return true
    }

    /// Says why the install is waiting, and waits.
    private func hold(for work: String) {
        heldWork = work
        ActivityTrail.note(
            .updateHeldWhileWorkIsUnderWay,
            UpdateTrail.heldLine(work: work, version: versionInHand ?? "?")
        )
        showHeldNotice(work: work)
        watchTask?.cancel()
        watchTask = Task { @MainActor in
            await AppUpdates.shared.waitUntilNothingIsUnderWay()
        }
    }

    /// Returns once nothing is under way, or when the wait is cancelled.
    ///
    /// Event-driven, never on a clock: it wakes when this app's own record of
    /// publishes and preview builds changes, when a process it is waiting for
    /// ends, or when a lease folder changes — and then asks the whole gate
    /// again, because new work may have started meanwhile. Each round arms its
    /// watches FIRST and asks SECOND, so work that ends in between is seen.
    private func waitUntilNothingIsUnderWay() async {
        while !Task.isCancelled {
            let facts: UpdateGate.Facts = UpdateGate.currentFacts()
            if UpdateGate.workUnderWay(facts: facts) == nil {
                heldWorkIsDone()
                return
            }
            let targets = UpdateGate.watchTargets(for: facts)
            var streams: [AsyncStream<Void>] = [AppUpdates.changesInThisApp()]
            for pid in targets.processIDs {
                streams.append(ProcessEnding.ends(of: pid))
            }
            for folder in targets.leaseFolders {
                streams.append(AppUpdates.changes(at: folder))
            }
            if UpdateGate.workUnderWay() == nil {
                heldWorkIsDone()
                return
            }
            await AppUpdates.firstOf(streams)
        }
    }

    /// The held work is over: install and open again, straight away
    /// (Russell, #204 Q3 — the teacher already said yes).
    private func heldWorkIsDone() {
        let work: String = heldWork ?? ""
        switch prepared {
        case .heldForWork:
            installNow(.afterHeldWork(work))
        case .postponedAtInstall:
            installMoment = .afterHeldWork(work)
            let handler: (() -> Void)? = postponedInstall
            postponedInstall = nil
            prepared = .none
            heldWork = nil
            closeHeldNotice()
            handler?()
        case .none, .readyToInstall:
            break
        }
    }

    /// Gives the installer the teacher's Install.
    private func installNow(_ moment: UpdateTrail.InstallMoment) {
        installMoment = moment
        prepared = .none
        heldWork = nil
        watchTask?.cancel()
        watchTask = nil
        closeHeldNotice()
        forwardReady(.install)
    }

    /// Hands an answer to the installer's question, once.
    private func forwardReady(_ choice: SPUUserUpdateChoice) {
        guard let reply = readyReply else {
            return
        }
        readyReply = nil
        if choice != .install {
            prepared = .none
        }
        reply(choice)
    }

    // MARK: - Functions: quitting

    /// What this quit does to a prepared update, and writes the line for an
    /// install that will happen as Plantoir goes. `.setAside` is left to
    /// `setAsideForQuit`, which the caller then runs.
    func decideAtQuit() -> UpdateGate.QuitAction {
        if prepared == .none {
            return .nothingToDo
        }
        let work: String? = UpdateGate.workUnderWay()
        let action: UpdateGate.QuitAction = UpdateGate.quitAction(prepared: prepared, workUnderWay: work != nil)
        if action == .installsAsItQuits {
            var stillGoing: String? = nil
            if prepared == .postponedAtInstall {
                stillGoing = work
            }
            noteInstalling(moment: .asPlantoirQuits(workStillGoing: stillGoing))
        }
        if action == .setAside {
            heldWork = work
        }
        return action
    }

    /// Tells the installer to stand down, and calls `whenDone` once the
    /// updater says the session is over — which is when the installer has
    /// been told, and the quit may finish.
    ///
    /// **The one timed wait here, and it is a bound, not a guess.** If the
    /// updater never reports the end of the session, the quit would hang for
    /// ever — and a quit during a log out holds up the whole Mac. So after ten
    /// seconds the quit goes ahead regardless, and the trail says the
    /// installer may not have heard. The signal that finishes the wait is the
    /// updater's own `didFinishUpdateCycleFor`; the clock only caps it.
    func setAsideForQuit(whenDone: @escaping () -> Void) {
        let work: String = heldWork ?? ""
        ActivityTrail.note(
            .updateSetAside,
            UpdateTrail.setAsideLine(version: versionInHand ?? "?", work: work)
        )
        quitWaiter = whenDone
        watchTask?.cancel()
        watchTask = nil
        closeHeldNotice()
        heldWork = nil
        forwardReady(.skip)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            AppUpdates.shared.finishWaitingQuit(heardBack: false)
        }
    }

    /// Lets a waiting quit go.
    private func finishWaitingQuit(heardBack: Bool) {
        guard let waiter = quitWaiter else {
            return
        }
        quitWaiter = nil
        if !heardBack {
            ActivityTrail.note(
                .updateStopped,
                "the installer did not confirm it had stood down within ten seconds of quitting; "
                    + "Plantoir \(versionInHand ?? "?") may install as Plantoir quits"
            )
        }
        waiter()
    }

    /// Writes `update installing`, and leaves the note the NEW version reads
    /// at its first launch to say it was installed by its own updater.
    private func noteInstalling(moment: UpdateTrail.InstallMoment) {
        let version: String = versionInHand ?? "?"
        ActivityTrail.note(
            .updateInstalling,
            UpdateTrail.installingLine(from: AppUpdates.runningVersion, to: version, moment: moment)
        )
        if let versionInHand {
            UserDefaults.standard.set(versionInHand, forKey: UpdateTrail.installingVersionKey)
        }
    }

    // MARK: - Functions: what the teacher is shown

    /// The held notice — NOT modal. A modal window here would stop the very
    /// work it is waiting for from being seen to end, and would be on screen
    /// when the app quits to install.
    private func showHeldNotice(work: String) {
        closeHeldNotice()
        if WorkspaceModel.isRunningTests {
            return
        }
        let alert: NSAlert = NSAlert()
        alert.messageText = UpdateWording.heldTitle(work: work)
        alert.informativeText = UpdateWording.heldExplanation
        alert.alertStyle = .informational
        alert.addButton(withTitle: UpdateWording.okButton)
        let button: NSButton = alert.buttons[0]
        button.target = self
        button.action = #selector(closeHeldNotice)
        alert.layout()
        alert.window.center()
        alert.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        heldNotice = alert
    }

    @objc private func closeHeldNotice() {
        heldNotice?.window.orderOut(nil)
        heldNotice = nil
    }

    /// The managed-Mac refusal, which the updater drops in silence.
    private func showNeedsAdministrator() {
        if WorkspaceModel.isRunningTests {
            return
        }
        let alert: NSAlert = NSAlert()
        alert.messageText = UpdateWording.needsAdministratorTitle
        alert.informativeText = UpdateWording.needsAdministratorExplanation
        alert.alertStyle = .warning
        alert.addButton(withTitle: UpdateWording.okButton)
        alert.runModal()
    }

    /// The session is over however it ended: nothing is prepared any more.
    private func sessionEnded() {
        prepared = .none
        readyReply = nil
        postponedInstall = nil
        heldWork = nil
        watchTask?.cancel()
        watchTask = nil
        closeHeldNotice()
        teacherAskedForThisCheck = false
    }

    // MARK: - Functions: the updater's reports, for the trail

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let found: String = UpdateTrail.versionText(
            version: item.displayVersionString, build: item.versionString
        )
        versionInHand = found
        if versionsFoundThisLaunch.contains(found) {
            return
        }
        versionsFoundThisLaunch.append(found)
        ActivityTrail.note(
            .updateFound,
            UpdateTrail.foundLine(
                found: found,
                running: AppUpdates.runningVersion,
                teacherAsked: teacherAskedForThisCheck,
                important: item.isCriticalUpdate
            )
        )
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let answer: UpdateTrail.Answer
        switch choice {
        case .install:
            answer = .install
        case .skip:
            answer = .skip
        default:
            answer = .notNow
        }
        let version: String = UpdateTrail.versionText(
            version: updateItem.displayVersionString, build: updateItem.versionString
        )
        ActivityTrail.note(.updateAnswered, UpdateTrail.answeredLine(answer: answer, version: version))
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        versionInHand = UpdateTrail.versionText(version: item.displayVersionString, build: item.versionString)
        noteInstalling(moment: installMoment)
    }

    /// Every stop but "nothing new" (1001), which the end of the cycle
    /// reports. The updater says NOTHING to the teacher when the daily check
    /// cannot update, nor when an administrator's password was asked for and
    /// not given (4007) — so the trail says it, and for 4007 the teacher is
    /// told in our words.
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let code: Int = (error as NSError).code
        if code == 1001 {
            return
        }
        noteStopped(code: code)
        if UpdateTrail.needsAnAdministrator(code: code) {
            showNeedsAdministrator()
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        if let error {
            let code: Int = (error as NSError).code
            if code == 1001 && teacherAskedForThisCheck {
                ActivityTrail.note(
                    .updateCheckFoundNothingNew,
                    UpdateTrail.nothingNewLine(running: AppUpdates.runningVersion)
                )
            }
            // "Authorize later" (4008) never reaches `didAbortWithError`.
            if code == 4008 {
                noteStopped(code: code)
            }
        }
        sessionEnded()
        finishWaitingQuit(heardBack: true)
    }

    /// `update stopped`, at most once per launch for the daily check.
    private func noteStopped(code: Int) {
        if !teacherAskedForThisCheck {
            if hasNotedADailyCheckFailure {
                return
            }
            hasNotedADailyCheckFailure = true
        }
        ActivityTrail.note(.updateStopped, UpdateTrail.stoppedLine(version: versionInHand, code: code))
    }

    // MARK: - Functions: the version this launch is

    /// Writes `app updated` when this launch's version differs from the last
    /// one's — by its own updater, or by hand.
    static func noteIfThisIsANewVersion(defaults: UserDefaults = UserDefaults.standard) {
        if let line = UpdateTrail.appUpdatedLine(current: AppUpdates.runningVersion, defaults: defaults) {
            ActivityTrail.note(.appUpdated, line)
        }
    }

    // MARK: - Functions: waiting for an event

    /// Yields once when this app's own publishes or preview builds change.
    nonisolated static func changesInThisApp() -> AsyncStream<Void> {
        return AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            MainActor.assumeIsolated {
                withObservationTracking {
                    _ = CourseActivity.store.activePublishes
                    _ = CourseActivity.store.activePreviewBuilds
                } onChange: {
                    continuation.yield(())
                    continuation.finish()
                }
            }
        }
    }

    /// Yields once when a lease folder changes.
    nonisolated static func changes(at folder: URL) -> AsyncStream<Void> {
        return AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task: Task<Void, Never> = Task {
                let events: AsyncStream<ScheduledPublishWatcher.Change> = ScheduledPublishWatcher.changes(
                    at: folder, watching: [.write, .delete, .rename, .extend]
                )
                for await _ in events {
                    continuation.yield(())
                    break
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Returns when the first of several streams yields — or when any of
    /// them finishes, or the task is cancelled.
    nonisolated static func firstOf(_ streams: [AsyncStream<Void>]) async {
        await withTaskGroup(of: Void.self) { group in
            for stream in streams {
                group.addTask {
                    for await _ in stream {
                        return
                    }
                }
            }
            _ = await group.next()
            group.cancelAll()
        }
    }
}

// MARK: - The updater's own window, with the Install answer passing through here

/// The updater's standard windows, unchanged, except that the teacher's
/// answer to "Install and Relaunch" comes to `AppUpdates` first.
///
/// A thin wrapper rather than a user interface of our own: the updater's
/// windows are localized into 35 languages and maintained by it, and a second
/// set would be ours to keep in step for ever. Every call but two is passed
/// straight through.
final class HoldingUserDriver: NSObject, SPUUserDriver {

    // MARK: - Stored properties

    private let standard: SPUStandardUserDriver
    private weak var owner: AppUpdates?

    // MARK: - Initializer

    init(hostBundle: Bundle, owner: AppUpdates) {
        self.standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        self.owner = owner
        super.init()
    }

    // MARK: - Functions: the two that are not simply passed on

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let owner else {
            standard.showReady(toInstallAndRelaunch: reply)
            return
        }
        owner.updateIsReady(reply: reply)
        standard.showReady { choice in
            AppUpdates.shared.teacherAnsweredReady(choice)
        }
    }

    /// Closes the updater's windows while the install is held.
    func closeTheUpdatersWindows() {
        standard.dismissUpdateInstallation()
    }

    // MARK: - Functions: passed straight through

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        standard.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        standard.showInstallingUpdate(
            withApplicationTerminated: applicationTerminated,
            retryTerminatingApplication: retryTerminatingApplication
        )
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        standard.dismissUpdateInstallation()
    }

    func showUpdateInFocus() {
        standard.showUpdateInFocus()
    }
}

// MARK: - The menu item

/// "Check for Updates…" under "About Plantoir" — drawn only when there is an
/// updater, so a development build has no item that could never work, and
/// greyed out while an update session is open (including while an install is
/// held).
struct CheckForUpdatesButton: View {

    // MARK: - Stored properties

    var updates: AppUpdates = AppUpdates.shared

    // MARK: - Body

    var body: some View {
        if updates.isRunning {
            Button(UpdateWording.menuItem) {
                updates.checkForUpdates()
            }
            .disabled(!updates.canCheckForUpdates)
        }
    }
}
