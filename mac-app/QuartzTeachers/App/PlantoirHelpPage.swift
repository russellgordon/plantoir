import AppKit
import SwiftUI

/// Opens one of Help's pages by its id (#839's outline, one anchor a page):
/// the Help book's page when the app carries the book, and plantoir.app's
/// support page until it does.
///
/// The book is wired into the app by #839's own piece (P1); this is the one
/// place #855's links go through, so that piece changes one function and
/// every link follows. Until then the anchor is still written on the trail,
/// so a report can say which page the teacher was after.
nonisolated enum PlantoirHelpPage {

    // MARK: - Functions

    /// Opens the page `anchor`.
    @MainActor
    static func open(anchor: String) {
        if let book = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String {
            ActivityTrail.note(.plantoirHelpOpened, "opened Plantoir Help at the page \(anchor)")
            NSHelpManager.shared.openHelpAnchor(anchor, inBook: book)
            return
        }
        ActivityTrail.note(
            .plantoirHelpOpened,
            "opened the support page in the browser, asked for Help's page \(anchor)"
        )
        NSWorkspace.shared.open(PlantoirHelpCommand.supportPage)
    }
}

/// Set Up an Assistant… in Revise With ▸ and Set Up an Assistant… in
/// Help ▸ (#855, ruling 3): both open Settings ▸ Other Assistants and
/// install nothing themselves. ONE view for every place it is drawn, so the
/// menu bar's item and every row's context menu item cannot differ.
struct SetUpAnotherAssistantButton: View {

    // MARK: - Stored properties

    @Environment(\.openSettings) private var openSettings

    let title: String
    let from: AssistantSetUpOpenedFrom

    // MARK: - Body

    var body: some View {
        Button(title) {
            AssistantSetUpCentre.pendingOpenedFrom = from
            SettingsPane.select(.otherAssistants)
            openSettings()
        }
    }
}
