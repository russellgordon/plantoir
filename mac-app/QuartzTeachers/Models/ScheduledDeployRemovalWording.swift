import Foundation

/// What a teacher reads when taking away a scheduled deploy (#987, Russell
/// 2026-11-18: "the verb for taking away a scheduled deploy is Remove, not
/// cancel"). Until then the command, the question and both of its buttons
/// said cancel, so backing out and going ahead shared a verb. Contract:
/// `shared-rules.json` → `scheduledDeployCancellation.removingOne`.
nonisolated enum ScheduledDeployRemovalWording {

    // MARK: - Stored properties

    /// Section ▸ Remove Scheduled Deploy…, and the same item in a section's
    /// right-click menu.
    static let menuItem: String = "Remove Scheduled Deploy…"

    /// The question's title: a full question, so sentence case and a
    /// question mark (Alerts).
    static let question: String = "Remove the scheduled deploy?"

    /// The button that removes it, trailing.
    static let removeButton: String = "Remove"

    /// The button that backs out, leading, with Escape.
    static let cancelButton: String = "Cancel"

    /// The message when the time is not known.
    static let messageWithoutTime: String = "This section will no longer deploy on its own."

    // MARK: - Functions

    /// The message under the question: which section, when, and what
    /// removing it means.
    static func message(courseCode: String, sectionNumber: Int, time: String, day: String) -> String {
        return "\(courseCode) Section \(sectionNumber) is set to deploy on its own at \(time) on \(day). "
            + "Removing it means it will not go out then, and the site stays as it is until you deploy it yourself."
    }
}
