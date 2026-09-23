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

    // MARK: - Body

    var body: some View {
        MainWindowView()
            .environment(workspace)
            .focusedSceneValue(\.workspace, workspace)
            .onAppear {
                WorkspaceModel.registerWindowModel(workspace)
                // Before the first frame commits: a mid-session window
                // takes the key window's folder here, so the picker never
                // shows on the way in. At launch this is a no-op and the
                // window claims below decide instead.
                workspace.adoptFolderForNewWindow()
                // A restored window's folder arrives a moment after the
                // window does. Until the claim resolves, hold quietly —
                // flashing the folder picker for a folder-less instant
                // reads as the wrong screen, not as loading.
                if workspace.workspaceURL == nil && WindowFolderMemory.aClaimMayStillArrive() {
                    workspace.isResolvingRestoredFolder = true
                }
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
                   let entry = claimant.frameDidSettle(NSStringFromRect(window.frame)) {
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
    func attemptClaim(for window: NSWindow, attemptsLeft: Int) {
        if let entry = claimant.frameDidSettle(NSStringFromRect(window.frame)) {
            adopt(entry, how: "matched by frame")
            return
        }
        // Once the claims have closed there is nothing to keep retrying
        // for — this is a mid-session window, and it should get its folder
        // (or its picker) right away rather than a second later.
        let claimsHaveClosed: Bool = Date() > WindowFolderMemory.claimsOpenUntil
        if attemptsLeft <= 0 || claimsHaveClosed {
            if let entry = claimant.giveUp() {
                adopt(entry, how: "fell back to order")
            } else {
                // Normally already handled in onAppear; harmless backstop.
                workspace.adoptFolderForNewWindow()
            }
            // The claim is settled either way; if no folder arrived, the
            // picker is now the honest screen to show.
            workspace.isResolvingRestoredFolder = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            attemptClaim(for: window, attemptsLeft: attemptsLeft - 1)
        }
    }

    /// Takes a remembered window as this window's own.
    func adopt(_ entry: WindowFolderMemory.Entry, how detail: String) {
        workspace.adoptRestoredPath(entry.path)
        // The sidebar as it was left: the same courses unfolded, the
        // Archived group open if it was, and the same course or section
        // selected.
        workspace.expandedCourseCodes = Set(entry.expandedCourses)
        workspace.isShowingArchived = entry.archivedExpanded
        workspace.isShowingBackups = entry.backupsExpanded
        workspace.isShowingReferenceCourses = entry.referenceExpanded
        workspace.expandedReferenceYears = Set(entry.expandedReferenceYears)
        if let selection = SidebarSelection.fromStorageValue(entry.selection) {
            workspace.selection = selection
        }
        workspace.isResolvingRestoredFolder = false
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
