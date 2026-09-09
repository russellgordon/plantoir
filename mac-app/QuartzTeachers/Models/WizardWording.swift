import Foundation

/// Words the New Course wizard shows a teacher. Authored in
/// `contracts/shared-rules.json` → `wizard`.
///
/// Only the affirmative button lives here today, and it earns a constant for
/// one reason: it is the first thing a teacher presses in this app, both
/// platforms have said the same word since the wizard existed, and until
/// 2026-09-08 nothing pinned it anywhere. Windows asserted it in
/// `NewCourseWizardUiTests`, which is opt-in behind `PLANTOIR_UI_TESTS=1` and
/// so the weakest place a shared sentence can live; the mac asserted it
/// nowhere at all. Two apps agreeing by habit is not the same as two apps
/// agreeing on purpose, and the only notice of a drift would have been a
/// teacher reading a different button from the one in the other platform's
/// screenshots.
enum WizardWording {

    // MARK: - Stored properties

    /// The affirmative button on the wizard's last step.
    nonisolated static let createCourseButton: String = "Create Course"
}
