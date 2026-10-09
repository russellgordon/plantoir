import AppKit
import SwiftUI

/// Help ▸ Plantoir Help: opens plantoir.app's support page in the
/// browser (#457, the HIG sweep — Russell: the support page).
///
/// It replaces the item macOS draws for an app with no help book, which
/// opened "Help isn't available for Plantoir" — a menu item that did
/// nothing a teacher could use. A help book was rejected: the support page
/// is already where the answers live, kept up to date with each release,
/// and a second copy inside the app would drift from it.
struct PlantoirHelpCommand: View {

    // MARK: - Stored properties

    /// The page it opens. Measured live on 2026-10-08: 200, with `/support`
    /// redirecting to it.
    static let supportPage: URL = URL(string: "https://plantoir.app/support/")!

    // MARK: - Body

    var body: some View {
        Button("Plantoir Help") {
            ActivityTrail.note(.plantoirHelpOpened, "Help ▸ Plantoir Help — opened the support page in the browser")
            NSWorkspace.shared.open(PlantoirHelpCommand.supportPage)
        }
        // No ⌘?: macOS keeps it for the Help menu's own search field, and
        // SwiftUI drew none when one was asked for (measured in the menu-bar
        // golden, #457).
    }
}
