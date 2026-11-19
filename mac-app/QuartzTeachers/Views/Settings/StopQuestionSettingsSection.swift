import SwiftUI

/// The Stopping section at the top of Plantoir ▸ Settings ▸ Deploying
/// (#988, ruling 4): where "Stop the deploy?" and "Stop this share?" are
/// turned back on after "Don't ask again". One row per question, each its
/// own setting (ruling 2), both on by default.
///
/// The rows are the switches a grouped form draws for a `Toggle`, as the
/// Obsidian and Assistant panes draw theirs. Toggles,
/// https://developer.apple.com/design/human-interface-guidelines/toggles:
/// "Within a grouped form, consider using a mini switch to control the
/// setting in a single row", and "In general, don't replace a checkbox with
/// a switch. If you're already using a checkbox in your interface, it's
/// probably best to keep using it" — the Settings window uses switches, so
/// these match it. Settings: "Put general, infrequently changed settings in
/// your custom settings area."
struct StopQuestionSettingsSection: View {

    // MARK: - Stored properties

    /// Where the two answers are read and remembered.
    let settings: AppSettings

    // MARK: - Computed properties

    var body: some View {
        Section {
            Toggle(StopQuestion.deploy.settingLabel, isOn: StopQuestionSettingsSection.isOn(.deploy, in: settings))
                .accessibilityIdentifier(StopQuestion.deploy.settingIdentifier)
            Toggle(StopQuestion.share.settingLabel, isOn: StopQuestionSettingsSection.isOn(.share, in: settings))
                .accessibilityIdentifier(StopQuestion.share.settingIdentifier)
        } header: {
            Text(StopQuestionSettingsWording.sectionHeader)
        } footer: {
            Text(StopQuestionSettingsWording.footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Functions

    /// A row's binding. The trail line is written here, by the teacher's own
    /// change, so opening the pane writes nothing.
    static func isOn(_ question: StopQuestion, in settings: AppSettings) -> Binding<Bool> {
        return Binding(
            get: { return question.isAsked(in: settings) },
            set: { (turnedOn: Bool) in
                question.setAsked(turnedOn, in: settings, from: .settings)
            }
        )
    }
}
