import Foundation

/// The two sentences on the Marks tick list — its title, and the caption
/// below it. Authored in `contracts/shared-rules.json` → `gradedFolders`
/// .`wording`, proposed from Windows 2026-09-08 and adopted here 2026-09-09
/// ([issue #71](https://github.com/russellgordon/plantoir/issues/71)).
///
/// **One home rather than four literals.** The same two strings serve Course
/// Settings AND the New Course wizard, on both platforms. Before the contract
/// case there were four distinct strings written out as eight literals — a
/// title and a caption in each app, duplicated across that app's two surfaces
/// — and nothing pinned any of them. Windows' half is
/// `Plantoir.Core/Models/GradedFolderRule.cs` (`ListTitle`, `Caption`).
///
/// Three decisions inside the caption, each argued the other way first and
/// each recorded in full in the contract's own `why` rather than here:
///
/// - **The verbs.** It says "tick", never "add" or "remove". This is a tick
///   list with no Add button, so the mac's previous caption named two actions
///   the control does not offer — and "remove what you don't" invited the one
///   thing `SpecialNames.lastGradedFolderBlocked` refuses outright. **A
///   correction rather than a preference**, which is why a test asserts the
///   verbs are absent instead of leaving it to review.
/// - **The map's name.** "The curriculum coverage map" — what the flyout
///   raised from this very list and the switch beside it both call it, so the
///   screen says one name three times. `SpecialFoldersHelpView`'s "the
///   curriculum map" is knowingly left as the outlier on another surface:
///   **a recorded mixed state, not drift to be tidied up.**
/// - **Where the caption goes.** BELOW its list, on all four surfaces —
///   "a page in one of these" points at the list, and above it "these"
///   follows the section header "Marks" and refers to nothing. The mac has
///   always drawn it there; saying it out loud is what lets one string serve
///   four places.
///
/// One imprecision is inherited and flagged rather than fixed: the coverage
/// map's own word is "assessed", and this caption says "evaluated". It says
/// it because the `specialFoldersHelp` row has said it since that sheet was
/// written, so changing it is a separate piece on both platforms.
enum GradedFolderWording {

    // MARK: - Stored properties

    /// The title of the tick list. The mac's own wording, which Russell chose
    /// over Windows' — it is the closer match to `SpecialFoldersHelpView`'s
    /// already-pinned "Work that counts for marks".
    ///
    /// **Look before changing it.** `MembershipToggleListView` puts this
    /// title into the trail line a teacher's blocked untick leaves behind, and
    /// on Windows it is built into every marks checkbox's automation id.
    nonisolated static let listTitle: String =
        "Folders whose work counts for marks"

    /// The caption below the list.
    nonisolated static let caption: String =
        "Tick the folders holding work that counts for marks. The curriculum coverage map shows an expectation as evaluated when a page in one of these addresses it. Most courses keep “Tasks”; tick “Tests” or anything else you mark."
}
