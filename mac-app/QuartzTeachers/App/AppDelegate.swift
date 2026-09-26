import AppKit
import UserNotifications

/// The few things that still need an application delegate.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Functions

    /// Takes on the notification centre's questions before launch finishes,
    /// which is where Apple asks for it to be done.
    ///
    /// Behind the test guard: the test host IS Plantoir.app, and the suite
    /// must not touch the real notification centre at all (#212).
    func applicationWillFinishLaunching(_ notification: Notification) {
        if !WorkspaceModel.isRunningTests {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    /// A click on a scheduled publish's notification still waiting for the
    /// windows is dropped when the app goes to the background (#306), so it
    /// can never capture a window the teacher opens later.
    func applicationDidResignActive(_ notification: Notification) {
        SectionFromNotification.forgetPendingRequest()
    }

    /// Opens the trail for this launch.
    func applicationDidFinishLaunching(_ notification: Notification) {
        ActivityTrail.noteLaunch()
        if !WorkspaceModel.isRunningTests {
            // "It broke after the update" needs to know WHEN the update was
            // (#204) — written by the first launch of a new version, however
            // it got here.
            AppUpdates.noteIfThisIsANewVersion()
            // The updater, and ONLY here (#204): the assistant's server, a
            // scheduled publish and writing the contracts never reach this
            // method, `shouldStart` refuses their flags anyway, and a
            // development build has no feed, so none of them ever checks for
            // or installs anything. See `AppUpdates` for why it is not a
            // stored property of the app.
            if AppUpdates.shouldStart(
                infoDictionary: Bundle.main.infoDictionary ?? [:],
                arguments: CommandLine.arguments,
                isRunningTests: WorkspaceModel.isRunningTests,
                headlessFlags: AppUpdates.headlessFlags
            ) {
                AppUpdates.shared.start()
            }
        }
        // A launch started by a click on a notification may show no window of
        // its own; a click still waiting for one is decided now (#306).
        let launchedByANotification: Bool =
            notification.userInfo?[NSApplication.launchUserNotificationUserInfoKey] != nil
        SectionFromNotification.launchFinished(launchedByANotification: launchedByANotification)
        // Built websites are kept outside the working folder, so a folder the
        // teacher has thrown away leaves its builds behind with nothing left
        // to name them. Once a launch, off the main thread — it is a few
        // directory reads and touches nothing a window is about to show.
        if !WorkspaceModel.isRunningTests {
            Task.detached(priority: .utility) {
                BuildOutputLocation.discardBuildsForMissingWorkingFolders()
            }
            // Ask the helper programs which versions they are, off the main
            // thread, and only THEN write the trail's helpers line — about a
            // third of a second after the two lines above. Behind this guard
            // so the suite never probes the machine it runs on. The line is
            // written back on the main actor, where every other trail line
            // is written, so two writers never interleave one file.
            Task { @MainActor in
                let measurement: HelperMeasurement = await ProblemReportEnvironment.refreshHelpers().value
                ActivityTrail.noteHelpers(measurement.description)
            }
            // Watch for what a scheduled run leaves behind, so its notice
            // reaches a teacher who is already looking at that section. One
            // watcher for the app: the folder hangs off the home folder, not
            // off a working folder. Behind the same guard as the line above —
            // the suite must never watch the teacher's real Application
            // Support.
            ScheduledPublishWatcher.shared.start()
        }
    }

    /// Without this, modern macOS quietly declines to restore state at all.
    nonisolated func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// The moment to write down which folders are open: the windows are all
    /// still here. Waiting any later loses the answer — during termination
    /// the windows close one by one, and a list rewritten as they close
    /// shrinks to nothing.
    nonisolated func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return MainActor.assumeIsolated {
            // The question comes FIRST, and nothing is written down before it
            // is answered: a quit the teacher then calls off must leave the
            // app exactly as it was, and `isTerminating` is not a flag that
            // can be taken back.
            let underWay: String? = QuitConfirmation.workUnderWay()
            let reason: QuitConfirmation.Reason = QuitConfirmation.reason(
                forQuitReasonCode: AppDelegate.quitReasonCode()
            )
            if QuitConfirmation.shouldAsk(reason: reason, workUnderWay: underWay),
               let underWay {
                let choice: QuitConfirmation.Choice = AppDelegate.askAbout(underWay)
                ActivityTrail.note(
                    .quitAskedAboutWorkUnderWay,
                    QuitConfirmation.trailLine(workUnderWay: underWay, choice: choice)
                )
                if choice == .keepWorking {
                    return .terminateCancel
                }
            }

            // A new version ready to install (#204). The installer installs
            // on ANY quit once it is prepared, and quitting is never refused
            // — so with work still under way the update is SET ASIDE here,
            // and the quit waits only for the installer to be told
            // (`appUpdates.atQuit`). Asked after the question above, whose
            // "keep working" must leave the update exactly as it was.
            let updateAtQuit: UpdateGate.QuitAction = AppUpdates.shared.decideAtQuit()

            AppDelegate.letEverythingGo()

            if updateAtQuit == .setAside {
                AppUpdates.shared.setAsideForQuit {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
                return .terminateLater
            }
            return .terminateNow
        }
    }

    /// Everything a quit does once it is going ahead: write down the open
    /// folders, stop this app's previews, hand back its leases, and let the
    /// builders rest.
    @MainActor
    static func letEverythingGo() {
        WorkspaceModel.isTerminating = true
        WorkspaceModel.rememberOpenFolders()

        // Deal with the work this app OWNS before asking anything to
        // rest. A preview left running keeps its container busy, a busy
        // container is left alone by the quit script, and a container of
        // ours that is still up keeps the shared virtual machine up too —
        // so a quit with a preview open would otherwise free nothing at
        // all, which is the ordinary case rather than a corner of one.
        //
        // BOTH halves, in the Stop button's own order: the processes
        // inside the container first, then the launcher on this Mac.
        // Ending only the first would leave a `preview.sh` that the app
        // no longer owns — measured, a child on a pseudo-terminal is
        // reparented rather than killed when its parent goes — and the
        // quit script's host-side check would then see it and refuse to
        // stop anything, for the full length of its wait.
        for lease in PreviewLeases.active {
            PreviewStopper.stopSectionProcessesOnTheWayOut(
                courseCode: lease.courseCode,
                sectionNumber: lease.sectionNumber,
                workspaceURL: URL(fileURLWithPath: lease.folderPath)
            )
        }
        ScriptRunner.stopEveryLivePreview()

        // This app's work leases come down with it (#156) — tidiness
        // rather than safety: a lease whose process has gone is ignored
        // by every reader. A publish left running is not ended here (see
        // `stopEveryLivePreview`), and its lease goes anyway, because
        // the process that holds it is leaving; the quit script below
        // still refuses to rest the machine while its launcher runs.
        WorkLeaseRegistry.releaseEverything()

        // Let every folder's container rest — and if that leaves the
        // shared VM with nothing running at all, let the VM rest too.
        // Sequenced in one script: the emptiness check must come after
        // our own containers have stopped.
        var folders: [String] = []
        for model in WorkspaceModel.windowModels {
            if let path = model.workspaceURL?.path {
                if !folders.contains(path) {
                    folders.append(path)
                }
            }
        }
        FolderContainers.releaseEverythingAtQuit(folderPaths: folders)
    }

    /// The reason macOS gave for this quit, when it gave one.
    ///
    /// A log out, a restart and a shut down all arrive as the same
    /// `applicationShouldTerminate` an ordinary ⌘Q does; the only thing that
    /// tells them apart is the `kAEQuitReason` attribute on the Apple event
    /// being handled at that moment. Without reading it, a confirmation put
    /// up here would hold up the whole Mac logging out.
    @MainActor
    static func quitReasonCode() -> OSType? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return nil
        }
        guard let descriptor = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) else {
            return nil
        }
        return OSType(descriptor.enumCodeValue)
    }

    /// Puts the question up and waits for an answer.
    ///
    /// Only the presentation lives here. What is under way, whether to ask at
    /// all, and what each answer means are in `QuitConfirmation`, where they
    /// can be tested without a window on screen.
    @MainActor
    static func askAbout(_ workUnderWay: String) -> QuitConfirmation.Choice {
        if WorkspaceModel.isRunningTests {
            return .quitAnyway
        }
        let alert: NSAlert = NSAlert()
        alert.messageText = QuitConfirmation.question(about: workUnderWay)
        alert.informativeText = QuitConfirmation.explanation()
        alert.alertStyle = .warning
        // The titles AND their meanings come from one ordered list, because
        // `NSAlert` reports a POSITION and nothing else: two `addButton`
        // calls written out here could be reordered in one line and would
        // then swap what each answer means, so Keep Working would quit.
        for button in QuitConfirmation.buttonsInOrder {
            alert.addButton(withTitle: button.title)
        }
        let response: NSApplication.ModalResponse = alert.runModal()
        return QuitConfirmation.choice(
            atButtonIndex: response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        )
    }
}

// MARK: - Notifications about scheduled publishes

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Show a scheduled publish's notification even when Plantoir is the app
    /// in front (#212).
    ///
    /// macOS asks the app in front whether to show a notification of its own,
    /// and the default answer is not to. The notification is posted by the
    /// scheduled RUN — a separate Plantoir process — so a teacher working in
    /// Plantoir at half six should still see it arrive. Shown as a banner and
    /// kept in Notification Center; no sound, for the reason the permission
    /// asks for none.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .list]
    }

    /// A click on a scheduled publish's notification opens that section
    /// (#306), whether Plantoir was running or the click launched it.
    ///
    /// Thin on purpose: which responses count is decided by
    /// `NotificationClickTarget.requested`, and what the click does by
    /// `SectionFromNotification`, both tested. Returns at once — the window
    /// work happens on the main actor, and may wait there for the launch
    /// windows to decide their folders.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request: NotificationClickTarget.Request = NotificationClickTarget.requested(
            identifier: response.notification.request.identifier,
            isAClick: response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
        guard case .click(let target) = request else {
            return
        }
        await MainActor.run {
            SectionFromNotification.receive(target)
        }
    }
}
