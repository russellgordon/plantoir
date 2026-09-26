import Foundation

/// Which folder a window starts on (#311): the one decision each window
/// makes, once.
///
/// **The folder always comes back; the window SET follows macOS.** When
/// macOS brings windows back ("Close windows when quitting an application"
/// turned off), each claims its own remembered folder exactly as before.
/// When it does not — the system default, which is why a fresh account
/// always met the picker — the FIRST window takes the last working folder,
/// which is the folder of the window last in front. A window opened when no
/// other window is open (a Dock click after closing the last one) takes it
/// too. Windows' `RestoreWindowsOnLaunch` + `WorkspacePath` is the same shape.
///
/// Pure, so the contract's launch cases (`reopeningTheLastWorkingFolder.
/// launchCases`) run through the same function the windows do.
nonisolated enum WindowStartRule {

    // MARK: - Types

    enum Start: Equatable, Sendable {
        /// Something asked for this window to show a particular folder (the
        /// assistant revealing a section, #306's notification click).
        case requested(String)
        /// A remembered window may still claim this one: wait quietly.
        case waitForRememberedWindow
        /// Reopen the last working folder.
        case lastWorkingFolder
        /// Open where the teacher already is, beside that window (⌘N).
        case sameAsOpenWindow(String)
        /// The folder picker.
        case picker
    }

    // MARK: - Functions

    /// The decision for one window that has not claimed a remembered one.
    ///
    /// - `isDuringLaunch`: the launch-time claims are still open. A second
    ///   window that appears then without a claim of its own shows the
    ///   picker rather than inheriting: that is macOS restoring a window
    ///   whose folder was not recorded (it was a picker, or it came back
    ///   after a log-in with windows otherwise not kept), and putting it on
    ///   the first window's folder would be two windows on one folder that
    ///   nobody asked for.
    /// - `otherWindowCount`: windows open besides this one, with a folder or not.
    static func start(
        requestedFolder: String?,
        aClaimMayStillArrive: Bool,
        isDuringLaunch: Bool,
        otherWindowCount: Int,
        otherOpenFolderPaths: [String],
        mostRecentKeyPath: String?,
        hasLastWorkingFolder: Bool
    ) -> Start {
        if let requestedFolder {
            return .requested(requestedFolder)
        }
        if aClaimMayStillArrive {
            return .waitForRememberedWindow
        }
        if otherWindowCount == 0 {
            if hasLastWorkingFolder {
                return .lastWorkingFolder
            }
            return .picker
        }
        if isDuringLaunch {
            return .picker
        }
        if let path = WindowStartRule.folderBesideOpenWindows(
            otherOpenFolderPaths: otherOpenFolderPaths,
            mostRecentKeyPath: mostRecentKeyPath
        ) {
            return .sameAsOpenWindow(path)
        }
        return .picker
    }

    /// The folder a new window beside open ones takes: the key window's,
    /// falling back to any open window's folder. Nil when none has one.
    static func folderBesideOpenWindows(otherOpenFolderPaths: [String], mostRecentKeyPath: String?) -> String? {
        if otherOpenFolderPaths.isEmpty {
            return nil
        }
        if let mostRecentKeyPath, otherOpenFolderPaths.contains(mostRecentKeyPath) {
            return mostRecentKeyPath
        }
        return otherOpenFolderPaths[0]
    }

    /// A whole launch, played window by window through `start` — what the
    /// contract's launch cases assert. Returns each window's folder in the
    /// order the windows appear, nil for the picker.
    ///
    /// - `windowsComeBack`: macOS restores the windows (on the mac, the
    ///   system setting; on Windows, `RestoreWindowsOnLaunch`).
    /// - `windowsLeftOpen`: the folders of the windows open at quit.
    /// - `lastWorkedIn`: the last working folder remembered.
    /// - `windowsMacOSOpens`: how many windows appear WITHOUT a remembered
    ///   folder to claim — 1 for an ordinary launch; more after a log-in
    ///   that brought windows back although the setting said not to.
    static func playLaunch(
        windowsComeBack: Bool,
        windowsLeftOpen: [String],
        lastWorkedIn: String?,
        windowsMacOSOpens: Int
    ) -> [String?] {
        var folders: [String?] = []
        if windowsComeBack && !windowsLeftOpen.isEmpty {
            // Each restored window claims its own entry.
            for path in windowsLeftOpen {
                folders.append(path)
            }
            return folders
        }
        var windowIndex: Int = 0
        while windowIndex < windowsMacOSOpens {
            var openFolders: [String] = []
            for folder in folders {
                if let folder {
                    openFolders.append(folder)
                }
            }
            let start: Start = WindowStartRule.start(
                requestedFolder: nil,
                aClaimMayStillArrive: false,
                isDuringLaunch: true,
                otherWindowCount: folders.count,
                otherOpenFolderPaths: openFolders,
                mostRecentKeyPath: nil,
                hasLastWorkingFolder: lastWorkedIn != nil
            )
            switch start {
            case .lastWorkingFolder:
                folders.append(lastWorkedIn)
            case .requested(let path), .sameAsOpenWindow(let path):
                folders.append(path)
            case .waitForRememberedWindow, .picker:
                folders.append(nil)
            }
            windowIndex += 1
        }
        return folders
    }
}

/// The single point where a window's folder becomes final — claimed,
/// reopened, refused, inherited or left to the picker. Called exactly once
/// per window, by `WorkspaceModel.settleItsFolder()`.
///
/// A seam, empty today: #306 (open the section a notification names) fills
/// it, so a click that arrived while the window was still deciding is
/// answered the moment it has decided rather than a second later.
@MainActor
enum WindowSettling {

    // MARK: - Stored properties

    /// Told of every window that settles — for tests counting that each
    /// window settles once.
    static var observer: ((WorkspaceModel) -> Void)?

    // MARK: - Functions

    static func windowSettled(_ model: WorkspaceModel) {
        if let observer {
            observer(model)
        }
    }
}
