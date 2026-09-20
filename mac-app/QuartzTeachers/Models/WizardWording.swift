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
}
