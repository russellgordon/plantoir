import Foundation

/// Words the New Course wizard shows a teacher. Authored in
/// `contracts/shared-rules.json` → `wizard`.
///
/// Why a sentence earns a constant here, and why the keys are authored
/// rather than generated, is in the contract's own `wizard` block — not
/// repeated here.
enum WizardWording {

    // MARK: - Stored properties

    /// The affirmative button on the wizard's last step.
    nonisolated static let createCourseButton: String = "Create Course"

    /// Shown under Starting Content when the new course will begin with
    /// nothing in it — no ready-made pages exist for the code and no
    /// skeleton either, OR the teacher has turned the skeleton down. Both
    /// are the same situation for a teacher, so both are told the same
    /// thing rather than a second sentence being invented for the second
    /// one. Windows says it in both places too (`NoExampleContentNote()`).
    nonisolated static let noExampleContentNote: String =
        "Example content isn’t available for this course code yet, so the "
        + "course will start with empty folders ready for your own pages."

    /// Shown under Starting Content when a course code that DOES have
    /// ready-made pages will start with nothing: the teacher turned the
    /// example content down and then turned the skeleton down too.
    ///
    /// A second sentence rather than a reword of `noExampleContentNote`,
    /// whose first clause — "Example content isn't available for this
    /// course code yet" — is plainly false to somebody who has just
    /// declined it. Leaving that sentence exactly as it is also leaves the
    /// ~1,900 codes with no payload reading what they have always read.
    nonisolated static let noStartingContentNote: String =
        "This course will start with empty folders ready for your own pages."

    /// Shown in place of the structure editor while the example content is
    /// choosing this course's folders and files.
    ///
    /// Its second sentence had to move with issue #248: turning
    /// pre-populating off used to leave the school-neutral factory lists on
    /// screen, and now leaves the SUBJECT's, which is a different offer.
    /// Pinned here rather than left as a literal in the view for the reason
    /// the contract gives — it is a sentence a teacher reads, and the two
    /// apps had no way to notice the other rewording it.
    nonisolated static let structureFromExampleNote: String =
        "The example content chooses the folders and files for this course, "
        + "so every page lands where its links expect it. Turn off "
        + "pre-populating to start from the subject’s own structure instead, "
        + "and change it however you like."

    /// The skeleton toggle's own label, for a subject the app can name.
    /// `{subject}` is the family's label, lowercased.
    nonisolated static let skeletonToggleLabelTemplate: String =
        "Start from a {subject} skeleton"

    /// The same label for the GENERAL family — club codes, custom codes,
    /// and any prefix the map does not carry (MCMPR11, the one British
    /// Columbia code with ready-made pages, is among them).
    ///
    /// Its own sentence because the general family's label is "This
    /// Course", written for the skeleton's own pages, and the template
    /// renders it as "Start from a this course skeleton" — which has been
    /// on screen for club codes since the toggle existed and reads as a
    /// typo. Windows renders the identical string.
    nonisolated static let skeletonToggleLabelForAGeneralSkeleton: String =
        "Start from a general course skeleton"

    /// The caption under the skeleton toggle for a code with NO ready-made
    /// pages of its own.
    nonisolated static let skeletonToggleCaption: String =
        "There is no ready-made course for this code, but there is a starting "
        + "point shaped for the subject: folders that suit it, four units of "
        + "class pages to rename, a page explaining what the site can do, and "
        + "placeholders saying what belongs where."

    /// The caption under the skeleton toggle for a code that HAS ready-made
    /// pages which the teacher has just turned down — where the sentence
    /// above opens with something untrue.
    nonisolated static let skeletonToggleCaptionWhenExampleContentIsDeclined: String =
        "There is also a starting point shaped for the subject: folders that "
        + "suit it, four units of class pages to rename, a page explaining "
        + "what the site can do, and placeholders saying what belongs where."

    // MARK: - Functions

    /// What the skeleton toggle says for one family.
    nonisolated static func skeletonToggleLabel(forFamilyNamed familyName: String,
                                                label: String) -> String {
        if familyName == SkeletonCatalog.generalFamilyName {
            return skeletonToggleLabelForAGeneralSkeleton
        }
        return skeletonToggleLabelTemplate.replacingOccurrences(
            of: "{subject}", with: label.lowercased()
        )
    }
}
