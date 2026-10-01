import SwiftUI

/// What fills a section's detail column when there is nothing running and
/// nothing to show yet.
///
/// **It FILLS the space it is offered, and that is the whole reason it is its
/// own view.** The column is a `ZStack`, which centres a child that claims less
/// height than it is given. This placeholder used to claim only the height of
/// its own words, so the stack centred the whole base layer — and anything above
/// the placeholder, which today means the scheduled-publish notice, floated in
/// the middle of the window with empty space above it instead of sitting under
/// the toolbar where it belongs. Measured on this Mac (2026-09-19) at 800 × 720:
/// this placeholder claimed **189 points** of the 720 it was offered, and the
/// notice above it took the layer to **246** — so the stack put 237 points of
/// nothing above the notice. Filling, it claims all 720.
///
/// Filling is the fix rather than pinning the notice to the top with an
/// alignment, because the placeholder should still be CENTRED in whatever room
/// is left once the notice has taken its share — `ContentUnavailableView`
/// centres its own content inside the space it is given, so asking it for all
/// the space asks for both things at once. And it is emphatically not a fixed
/// height: a rigid height in this column is the failure class issue #211
/// closed (`documentation/09-mac-app.md` → "A blank window").
///
/// The console has always filled, by way of the `Spacer(minLength: 0)` at the
/// bottom of `consoleArea`, which is why the notice sat correctly the moment
/// anything was running and wrongly when nothing was.
struct NoPreviewPlaceholderView: View {

    // MARK: - Stored properties

    /// Whether this section publishes into a folder on this Mac, which changes
    /// what the Deploy button is described as doing.
    let deploysToLocalFolder: Bool

    /// The code a teacher reads, for a course that is never deployed. Empty
    /// for every ordinary course, which is all this view ever saw before.
    var keptForReferenceCode: String = ""

    // MARK: - Computed properties

    /// What the teacher is invited to do next.
    var invitation: String {
        // A reference course has no Deploy button, so inviting them to press
        // one would be pointing at something that is not there.
        if !keptForReferenceCode.isEmpty {
            return ReferenceWording.neverDeployed(course: keptForReferenceCode)
        }
        if deploysToLocalFolder {
            return "Click Preview to build this section's website and see it here, "
                 + "or Deploy to copy it to your deploy folder."
        }
        return "Click Preview to build this section's website and see it here, "
             + "or Deploy to put it online."
    }

    // MARK: - Body

    var body: some View {
        ContentUnavailableView(
            "No Preview Running",
            systemImage: "globe",
            description: Text(invitation)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
