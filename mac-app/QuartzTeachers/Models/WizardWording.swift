import Foundation

/// Words the New Course wizard shows a teacher. Authored in
/// `contracts/shared-rules.json` → `wizard`.
///
/// Only the affirmative button lives here today. Why one string earns a
/// constant, and why the key is authored rather than generated, is in the
/// contract's own `wizard` block — not repeated here.
enum WizardWording {

    // MARK: - Stored properties

    /// The affirmative button on the wizard's last step.
    nonisolated static let createCourseButton: String = "Create Course"
}
