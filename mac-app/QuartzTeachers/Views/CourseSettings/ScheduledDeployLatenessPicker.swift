import SwiftUI

/// How late a deploy set to happen on its own may still go ahead.
///
/// Course-level, beside the other deploying settings, because that is where a
/// teacher would look for it — and because the value is read at the scheduled
/// moment from the course's own settings file, so changing it here changes
/// what a deploy already scheduled will do.
///
/// **In Course Settings and NOT in the new-course wizard.** A brand-new course
/// has nothing scheduled and cannot have — `ScheduledDeploy.problem` refuses to
/// schedule a section that has never been deployed — so the wizard would be
/// asking a question with no consequence at the moment it is asked.
///
/// A short fixed list rather than a number field, and deliberately with no
/// "always" on it: "never expires" is the annual repeat this whole piece exists
/// to close, offered as a setting.
struct ScheduledDeployLatenessPicker: View {

    // MARK: - Stored properties

    @Binding var days: Int

    // MARK: - Computed properties

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(ScheduledDeployLateness.settingTitle, selection: $days) {
                ForEach(ScheduledDeployLateness.offeredDays, id: \.self) { offered in
                    Text(ScheduledDeployLateness.choiceLabel(days: offered)).tag(offered)
                }
            }
            .accessibilityIdentifier("scheduledDeployLatenessPicker")
            ExampleCaption(ScheduledDeployLateness.settingCaption)
        }
    }
}
