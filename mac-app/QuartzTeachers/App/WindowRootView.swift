import AppKit
import SwiftUI

/// One window's worth of app: its own working folder, remembered separately
/// from every other window's.
///
/// macOS restores the windows and their frames; the folders come from the
/// app's own list, keyed by frame. SwiftUI's per-window persistence is
/// deliberately not involved: both `@SceneStorage` and presented values
/// proved to share one value across the group's windows on restore — last
/// writer wins — which put every window on the same folder.
struct WindowRootView: View {

    // MARK: - Stored properties

    /// This window's own model. Each window has one. Created bare: the
    /// window-group closure runs on every render, so anything decided in
    /// an initializer here runs at the wrong moments — the folder is
    /// decided in onAppear instead, on the actual new window.
    @State var workspace: WorkspaceModel = WorkspaceModel()

    /// This window's claim on the remembered folders.
    @State var claimant: WindowFolderClaimant = WindowFolderClaimant()

    /// Identifies this window in the log, so two windows can be told apart.
    @State var windowIdentity: String = String(UUID().uuidString.prefix(4))

    /// Handed to `SectionFromNotification`, which opens a new window when a
    /// clicked notification's folder is open in none (#306).
    @Environment(\.openWindow) var openWindow

    // MARK: - Body

    var body: some View {
        MainWindowView()
            .environment(workspace)
            .focusedSceneValue(\.workspace, workspace)
            .onAppear {
                WorkspaceModel.registerWindowModel(workspace)
                // Every window installs it; any live one opens the next.
                SectionFromNotification.openMainWindow = {
                    openWindow(id: "main")
                }
                // Before the first frame commits, so the picker never shows
                // on the way in: the window decides its folder here — the
                // last working folder when it is on its own, the key
                // window's beside others (`WindowStartRule`). A window that
                // may yet claim a remembered one holds quietly instead, and
                // decides when the claim below resolves.
                workspace.adoptFolderForNewWindow()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didFinishRestoringWindowsNotification
            )) { _ in
                // AppKit has just finished state restoration, so every
                // restored frame is final — try the frame match NOW
                // rather than waiting for the settle-polling to notice.
                // Success only: on a mismatch the polling keeps running,
                // so this window cannot give up early and order-claim an
                // entry that rightly belongs to a sibling's frame.
                if let window = workspace.window,
                   let entry = claimant.frameDidSettle(
                       NSStringFromRect(window.frame),
                       windowHasSettled: workspace.hasSettledItsFolder
                   ) {
                    adopt(entry, how: "matched at restoration-complete")
                }
            }
            .background(WindowAccessor { window in
                workspace.window = window
                attemptClaim(for: window, attemptsLeft: 7)
                let folderPath: String = LogRedactor.redacting(workspace.workspaceURL?.path ?? "")
                AppLog.interface.info("""
                    window \(windowIdentity, privacy: .public) opened in \
                    "\(folderPath, privacy: .public)" \
                    at \(NSStringFromRect(window.frame), privacy: .public)
                    """)
                WorkspaceModel.rememberOpenFolders()
            })
            .onChange(of: workspace.workspaceURL) {
                let folderPath: String = LogRedactor.redacting(workspace.workspaceURL?.path ?? "")
                AppLog.interface.info("""
                    window \(windowIdentity, privacy: .public) moved to \
                    "\(folderPath, privacy: .public)"
                    """)
                WorkspaceModel.rememberOpenFolders()
                if workspace.window?.isKeyWindow == true, let path = workspace.workspaceURL?.path {
                    WorkspaceModel.mostRecentKeyFolderPath = path
                    workspace.rememberAsTheLastWorkingFolder()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                // Remember where the teacher is working, so the NEXT new
                // window can open there. A window with no folder yet (this
                // one, freshly opened) must not erase the memory.
                guard (notification.object as? NSWindow) === workspace.window else {
                    return
                }
                if let path = workspace.workspaceURL?.path {
                    WorkspaceModel.mostRecentKeyFolderPath = path
                    // And for the next LAUNCH: the last working folder is
                    // the one last in front, not the one last chosen (#311).
                    workspace.rememberAsTheLastWorkingFolder()
                }
            }
            .onDisappear {
                WorkspaceModel.unregisterWindowModel(workspace)
            }
    }

    // MARK: - Functions

    /// Finds this window's folder by its frame, retrying briefly because a
    /// reopened window's frame settles a moment after the window exists.
    /// The claimant claims at most once, and claims close shortly after
    /// launch — a window opened mid-session inherits nothing.
    ///
    /// A window that has already settled its folder — decided in onAppear,
    /// or claimed at restoration-complete — never claims, and never reaches
    /// the give-up below: one decision per window (#311 review B1). Before
    /// that rule the give-up's "harmless backstop" could have become a
    /// second decision, putting a window whose folder had gone onto a
    /// sibling's folder and wiping the sentence that said why.
    func attemptClaim(for window: NSWindow, attemptsLeft: Int) {
        // The claimant refuses for a settled window and marks itself done,
        // so the give-up below is never reached for one either.
        if workspace.hasSettledItsFolder {
            _ = claimant.giveUp(windowHasSettled: true)
            return
        }
        if let entry = claimant.frameDidSettle(
            NSStringFromRect(window.frame),
            windowHasSettled: workspace.hasSettledItsFolder
        ) {
            adopt(entry, how: "matched by frame")
            return
        }
        // Once the claims have closed there is nothing to keep retrying
        // for — this is a mid-session window, and it should get its folder
        // (or its picker) right away rather than a second later.
        let claimsHaveClosed: Bool = Date() > WindowFolderMemory.claimsOpenUntil
        if attemptsLeft <= 0 || claimsHaveClosed {
            if let entry = claimant.giveUp(windowHasSettled: workspace.hasSettledItsFolder) {
                adopt(entry, how: "fell back to order")
            } else {
                // No remembered window for this one: macOS brought back a
                // window whose folder was not recorded. The picker is the
                // honest screen — it does NOT inherit a sibling's folder.
                workspace.settleItsFolder()
            }
            return
        }
        // A bounded retry while the frame settles; the restoration-complete
        // notification above is the real signal, and this the fallback.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            attemptClaim(for: window, attemptsLeft: attemptsLeft - 1)
        }
    }

    /// Takes a remembered window as this window's own.
    ///
    /// Through `reopen`, the one route by which a window gets a remembered
    /// folder back — so a folder gone, in the Trash, on a drive not plugged
    /// in, unreadable or out of the builder's reach is said in one sentence
    /// rather than silently skipped.
    func adopt(_ entry: WindowFolderMemory.Entry, how detail: String) {
        let reopened: Bool = workspace.reopen(
            RememberedFolder(path: entry.path, bookmark: entry.bookmark),
            occasion: .rememberedWindow
        )
        // The sidebar as it was left — only when the folder came back: the
        // same courses unfolded, the Archived group open if it was, and the
        // same course or section selected.
        if reopened {
            workspace.expandedCourseCodes = Set(entry.expandedCourses)
            workspace.isShowingArchived = entry.archivedExpanded
            workspace.isShowingBackups = entry.backupsExpanded
            workspace.isShowingReferenceCourses = entry.referenceExpanded
            workspace.expandedReferenceYears = Set(entry.expandedReferenceYears)
            if let selection = SidebarSelection.fromStorageValue(entry.selection) {
                workspace.selection = selection
            }
        }
        workspace.settleItsFolder()
        let claimedPath: String = LogRedactor.redacting(entry.path)
        AppLog.interface.info("""
            window \(windowIdentity, privacy: .public) claimed \
            "\(claimedPath, privacy: .public)" — \(detail, privacy: .public), \
            expanded: [\(entry.expandedCourses.joined(separator: ","), privacy: .public)], \
            archived: \(entry.archivedExpanded, privacy: .public), \
            selection: "\(entry.selection, privacy: .public)"
            """)
    }
}
