import AppKit
import SwiftUI

/// The File menu (#457), usable with NO window open.
///
/// Russell, 2026-10-08: with no Plantoir window open, the File menu offered
/// "New ▸ New Plantoir Window / New Assistant Window" and greyed everything
/// else — so choosing a different working folder meant opening a window on
/// the old one first, and the assistant could be opened with no course
/// behind it. Now:
///
/// - **New Window ⌘N** replaces SwiftUI's automatic New submenu
///   (`replacing: .newItem`), which is also what removed "New Assistant
///   Window": the assistant is opened for a section, from Revise With ▸
///   Local AI Assistant…, and never on its own. Moving ⌘N to a top-level
///   item fixed a second thing in passing: `SectionFromNotification`'s
///   opener looks for ⌘N one level down and never found it in the
///   submenu, so a notification clicked with no window open parked instead
///   of opening one (#306).
/// - **Open Working Folder… ⌘O and Open Recent** work with no window: they
///   choose a folder first and then open a window on it. With a Plantoir
///   window in front they switch THAT window (Russell's decision 3), as
///   Open Working Folder… always has.
/// - **New Course… ⇧⌘N** lives here only, not also in Course: the same
///   words twice in the menu bar is what #457 item 4 rules out.
///
/// Close ⌘W is the system's own item in `.saveItem` and is left alone.
struct FileCommands: Commands {

    // MARK: - Stored properties

    @FocusedValue(\.workspace) var workspace: WorkspaceModel?

    /// Handed in by the App, where the environment is the app's own.
    let openWindow: OpenWindowAction

    /// Read in the body, so the menu follows the list.
    var recentFolders: RecentWorkingFolders = RecentWorkingFolders.shared

    // MARK: - Computed properties

    var enabled: Set<SubjectMenuRules.Item> {
        return SubjectMenuRules.enabledItems(MenuSituation.assemble(
            workspace: workspace, sidebar: nil, site: nil, settings: nil, previewController: nil
        ).withArchivedRow(workspace?.selectedArchivedItem != nil))
    }

    // MARK: - Body

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("New Course…") {
                MenuRoute.run(.newCourse, in: workspace?.window) {
                    workspace?.isShowingNewCourseWizard = true
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!enabled.contains(.newCourse))

            Divider()

            Button("Open Working Folder…") {
                openWorkingFolder()
            }
            .keyboardShortcut("o", modifiers: [.command])

            openRecentMenu

            Divider()

            // Beside Open Working Folder… in spirit, because it starts by
            // choosing a folder. It is NOT on the sidebar's + button — that
            // opens the New Course wizard on a single click.
            Button(ReferenceImportWording.menuItem) {
                MenuRoute.run(.importCoursesForReference, in: workspace?.window) {
                    workspace?.isChoosingFolderToImportFrom = true
                }
            }
            .disabled(!enabled.contains(.importCoursesForReference))

            Button("Restore from Archive…") {
                MenuRoute.run(.restoreFromArchive, in: workspace?.window) {
                    workspace?.restoreRequest = workspace?.selectedArchivedItem
                }
            }
            .disabled(!enabled.contains(.restoreFromArchive))

            Button("Reload Courses") {
                MenuRoute.run(.reloadCourses, in: workspace?.window) {
                    workspace?.reloadCoursesFromTheMenu()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!enabled.contains(.reloadCourses))
        }
    }

    /// File ▸ Open Recent: newest first, then Clear Menu.
    var openRecentMenu: some View {
        let entries: [RememberedFolder] = recentFolders.entries
        var paths: [String] = []
        for entry in entries {
            paths.append(entry.path)
        }
        let titles: [String] = RecentWorkingFolders.titles(for: paths)
        return Menu("Open Recent") {
            ForEach(0..<entries.count, id: \.self) { index in
                Button(titles[index]) {
                    openRecent(entries[index])
                }
            }
            if !entries.isEmpty {
                Divider()
            }
            Button("Clear Menu") {
                recentFolders.clear()
            }
            .disabled(entries.isEmpty)
        }
    }

    // MARK: - Functions

    /// The window in front, when it is a Plantoir window that may act now.
    var freeWindowModel: WorkspaceModel? {
        guard let workspace, MenuRoute.windowIsFree(workspace.window) else {
            return nil
        }
        return workspace
    }

    /// With a Plantoir window in front: that window's own chooser, as
    /// always. With none (or a sheet up on it): an Open panel of the app's
    /// own, then a NEW window on the folder chosen.
    func openWorkingFolder() {
        if let model = freeWindowModel {
            model.isChoosingWorkspace = true
            return
        }
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        if panel.runModal() != .OK {
            return
        }
        guard let url = panel.url else {
            return
        }
        WorkspaceModel.folderToOpenInNextNewWindow = .chosen(url)
        openWindow(id: "main")
    }

    /// A folder from Open Recent: in the window in front, or a new one.
    func openRecent(_ folder: RememberedFolder) {
        if let model = freeWindowModel {
            model.openRecent(folder)
            return
        }
        WorkspaceModel.folderToOpenInNextNewWindow = .recent(folder)
        openWindow(id: "main")
    }
}

extension SubjectMenuRules.Situation {

    // MARK: - Functions

    /// The File menu reads the window directly rather than the sidebar's
    /// value; this is the one sidebar fact it needs.
    func withArchivedRow(_ isArchived: Bool) -> SubjectMenuRules.Situation {
        var copy: SubjectMenuRules.Situation = self
        if isArchived {
            copy.row = .archived
        }
        return copy
    }
}
