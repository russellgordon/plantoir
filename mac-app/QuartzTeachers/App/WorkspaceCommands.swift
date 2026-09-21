import SwiftUI

/// File-menu items that act on the window with focus, since each window has
/// its own working folder.
struct WorkspaceCommands: View {

    // MARK: - Stored properties

    @FocusedValue(\.workspace) var workspace: WorkspaceModel?

    // MARK: - Body

    var body: some View {
        Button("Open Working Folder…") {
            workspace?.isChoosingWorkspace = true
        }
        .keyboardShortcut("o", modifiers: [.command])
        .disabled(workspace == nil)

        // Beside Open Working Folder…, because it is the same kind of act:
        // it starts by choosing a folder. It is NOT on the sidebar's + button
        // — that button opens the New Course wizard on a single click, and
        // turning it into a menu would put a menu between a teacher and the
        // thing they press most often.
        Button(ReferenceImportWording.menuItem) {
            workspace?.isChoosingFolderToImportFrom = true
        }
        .disabled(workspace?.coursesDirectoryURL == nil)

        Button("Restore from Archive…") {
            workspace?.restoreRequest = workspace?.selectedArchivedItem
        }
        .disabled(workspace?.selectedArchivedItem == nil)

        Button("Reload Courses") {
            workspace?.reloadCourses()
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(workspace == nil)
    }
}
