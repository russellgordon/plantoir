import SwiftUI

/// The embedded website preview's Back, Forward and Reload Page, in the
/// system's own View menu (#457).
///
/// They were a menu of their own called "Preview" until v1.5.0. A
/// `CommandMenu("View")` would have made a SECOND View menu — macOS draws
/// one for every app, even with no window open (measured by the plan review)
/// — so they go into it, before its toolbar items. "Preview" is now the
/// Section menu's verb, which is what the word means everywhere else in
/// Plantoir.
///
/// The shortcuts live on MENU items rather than toolbar buttons because
/// a focused web view swallows key events before SwiftUI toolbar
/// shortcuts see them — menu key equivalents always work. (Back and
/// Forward would partly work anyway, since WebKit handles ⌘[ and ⌘]
/// natively, but Reload would not.)
struct ViewCommands: Commands {

    // MARK: - Stored properties

    @FocusedValue(\.previewController) var previewController

    @FocusedValue(\.workspace) var workspace: WorkspaceModel?

    // MARK: - Computed properties

    var enabled: Set<SubjectMenuRules.Item> {
        return SubjectMenuRules.enabledItems(MenuSituation.assemble(
            workspace: workspace, sidebar: nil, site: nil, settings: nil, previewController: previewController
        ))
    }

    // MARK: - Body

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Back") {
                MenuRoute.run(.back, in: workspace?.window) {
                    previewController?.goBack()
                }
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!enabled.contains(.back))

            Button("Forward") {
                MenuRoute.run(.forward, in: workspace?.window) {
                    previewController?.goForward()
                }
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!enabled.contains(.forward))

            Button("Reload Page") {
                MenuRoute.run(.reloadPage, in: workspace?.window) {
                    previewController?.reload()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!enabled.contains(.reloadPage))

            Divider()
        }
    }
}
