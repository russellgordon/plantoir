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
        MainActor.assumeIsolated {
            WorkspaceModel.isTerminating = true
            WorkspaceModel.rememberOpenFolders()
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
        return .terminateNow
    }
}
