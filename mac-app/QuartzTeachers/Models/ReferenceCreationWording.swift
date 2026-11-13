import Foundation

/// Every sentence a teacher reads while making a course straight onto the
/// Reference Courses shelf (#572) — written once, here.
///
/// Retyped from `contracts/shared-rules.json` →
/// `referenceCourses.creating.wording` and pinned against it by
/// `ReferenceCreationTests`, the arrangement `ReferenceImportWording` uses.
/// Kept apart from `WizardWording` because these sentences belong to one act
/// that has three doors (the wizard's choice, the offer under the taken-code
/// refusal, and New Reference Course… on the shelf), and a file per act keeps
/// a sentence beside the thing that produces it.
///
/// **The machinery is never named.** A teacher is told where the course goes,
/// what it holds and what it will never do; nothing here says "staging",
/// "script" or "setup".
nonisolated enum ReferenceCreationWording {

    // MARK: - The choice in the wizard

    /// The toggle's label.
    static let toggleLabel: String = "Keep this course for reference"

    /// What the toggle means, under it.
    static let toggleCaption: String =
        "It goes on the Reference Courses shelf with the ready-made pages written for it, "
        + "to read and copy from. It is never deployed, and its pages are locked."

    /// Said where the choice would be, for a code that has no ready-made
    /// pages. A reference course of such a code would be a locked skeleton
    /// nobody can read from or add to, so the choice is not offered.
    static func noReadyMadePages(code: String) -> String {
        return "There are no ready-made pages for \(code) to keep for reference."
    }

    /// Said under the taken-code refusal, for a code that has ready-made
    /// pages: the second course of that code can be a reference one.
    static func offerUnderTheRefusal(code: String) -> String {
        return "To add another \(code) to read and copy from, keep this one for reference."
    }

    /// The button beside that offer. It turns the toggle on.
    static let offerButton: String = "Keep for Reference"

    /// The wizard's button while the toggle is on.
    static let createButton: String = "Create Reference Course"

    /// The progress title while it is made.
    static let creatingTitle: String = "Creating your reference course"

    // MARK: - When it is not made

    /// Setup did not finish, or the course could not be put on the shelf.
    static func couldNotBeMade(code: String) -> String {
        return "\(code) could not be set up for reference, so nothing was added to the "
            + "Reference Courses shelf."
    }

    /// Setup finished but the ready-made pages are not there (plan review
    /// H3): a locked course without them would be worth nothing.
    static func pagesDidNotLand(code: String) -> String {
        return "The ready-made pages for \(code) could not be installed, so nothing was added "
            + "to the Reference Courses shelf."
    }

    /// The teacher pressed Cancel while it was being made.
    static let stopped: String = "Stopped. Nothing was added to the Reference Courses shelf."

    // MARK: - The shelf's own door

    /// The item on the Reference Courses heading's menu, which opens the New
    /// Course wizard with the choice already made.
    static let newReferenceCourseMenuItem: String = "New Reference Course…"
}
