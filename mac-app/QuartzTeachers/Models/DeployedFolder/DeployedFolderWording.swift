import Foundation

/// What a teacher reads about a deployed folder opened in the browser (#850).
/// The contract's copy is `contracts/shared-rules.json` →
/// `deployedFolderInBrowser.wording`, compared key by key by
/// `DeployedFolderOfferTests`; tests and documents name these, never quote
/// them.
///
/// None of them promises how a web host will behave (the plan review's H1):
/// a folder deploy is the one destination whose host is unknown, and #849
/// measured a plain host answering 404 for every page link. They say what
/// Plantoir shows, and nothing about where the folder goes next. Rule 1: no
/// word for what answers the browser.
nonisolated enum DeployedFolderWording {

    // MARK: - Stored properties

    /// Beside Show in Finder, under a finished deploy to a folder. The same
    /// name as Preview's, by Russell's ruling of 2026-11-13: one Open in
    /// Browser for both.
    static let resultButton: String = "Open in Browser"

    /// Section ▸ Open in Browser and the toolbar's button: the preview when
    /// one is showing, the deployed folder otherwise.
    static let menuItem: String = "Open in Browser"

    /// Section ▸ and the section row's context menu, while it is shown.
    static let stopMenuItem: String = "Stop Showing Deployed Folder"

    /// The one-line notice in the section's window while it is shown.
    static let notice: String = "Section {section}’s deployed folder is open in your web browser."

    /// The notice's button, and what VoiceOver says it does.
    static let stopButton: String = "Stop"
    static let stopHint: String = "Stop showing the deployed folder in your web browser"

    /// The help on Open in Browser when it opens the deployed folder.
    static let help: String = "Open the deployed folder in your web browser, so its links and features work"

    /// The help on Open in Browser when it opens the preview (its words
    /// before #850, kept).
    static let previewHelp: String = "Open this preview in your web browser"

    /// Why Open in Browser is greyed for the deployed folder.
    static let notDeployedYet: String = "Nothing has been deployed to this section’s folder yet. Deploy it first."
    static let folderNotFound: String = "Plantoir can’t find this section’s deploy folder. If it’s on a drive, connect the drive, or deploy again."

    /// Said in the notice's place when the folder went away while shown.
    static let stoppedFolderGone: String = "Your deployed folder is no longer where it was, so Plantoir stopped showing it."

    /// The alert when it could not be opened.
    static let couldNotOpenTitle: String = "Your Deployed Folder Could Not Be Opened"
    static let couldNotOpen: String = "Plantoir could not show this folder in your web browser. Try again, or restart your computer if it happens again."

    /// Under a finished deploy to a folder, in place of the note that said
    /// the pages would only look right on a web host.
    static let renderNote: String = "Opened straight from the folder, its pages won’t work. Click Open in Browser to see them working."

    // MARK: - Functions

    /// The notice for one section.
    static func notice(section: Int) -> String {
        return notice.replacingOccurrences(of: "{section}", with: String(section))
    }

    /// Every key and its sentence, for the contract test.
    static var everyKey: [String: String] {
        return [
            "resultButton": resultButton,
            "menuItem": menuItem,
            "stopMenuItem": stopMenuItem,
            "notice": notice,
            "stopButton": stopButton,
            "stopHint": stopHint,
            "help": help,
            "previewHelp": previewHelp,
            "notDeployedYet": notDeployedYet,
            "folderNotFound": folderNotFound,
            "stoppedFolderGone": stoppedFolderGone,
            "couldNotOpenTitle": couldNotOpenTitle,
            "couldNotOpen": couldNotOpen,
            "renderNote": renderNote,
        ]
    }
}
