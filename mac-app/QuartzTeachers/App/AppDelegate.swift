import AppKit

/// The few things that still need an application delegate.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Functions

    /// Opens the trail for this launch.
    func applicationDidFinishLaunching(_ notification: Notification) {
        ActivityTrail.noteLaunch()
        // Built websites are kept outside the working folder, so a folder the
        // teacher has thrown away leaves its builds behind with nothing left
        // to name them. Once a launch, off the main thread — it is a few
        // directory reads and touches nothing a window is about to show.
        if !WorkspaceModel.isRunningTests {
            Task.detached(priority: .utility) {
                BuildOutputLocation.discardBuildsForMissingWorkingFolders()
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
            let underWay: String? = QuitConfirmation.workUnderWay(
                publishes: CourseActivity.activePublishes
            )
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

            WorkspaceModel.isTerminating = true
            WorkspaceModel.rememberOpenFolders()

            // Deal with the work this app OWNS before asking anything to
            // rest. A preview left running keeps its container busy, a busy
            // container is left alone by the quit script, and a container of
            // ours that is still up keeps the shared virtual machine up too —
            // so a quit with a preview open would otherwise free nothing at
            // all, which is the ordinary case rather than a corner of one.
            for lease in PreviewLeases.active {
                PreviewStopper.stopSectionProcessesOnTheWayOut(
                    courseCode: lease.courseCode,
                    sectionNumber: lease.sectionNumber,
                    workspaceURL: URL(fileURLWithPath: lease.folderPath)
                )
            }

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
            return .terminateNow
        }
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
        // First button is the default one, and the safe answer is the default
        // answer: a teacher who hits Return without reading keeps their work.
        alert.addButton(withTitle: QuitConfirmation.keepWorkingButton)
        alert.addButton(withTitle: QuitConfirmation.quitAnywayButton)
        if alert.runModal() == .alertSecondButtonReturn {
            return .quitAnyway
        }
        return .keepWorking
    }
}
