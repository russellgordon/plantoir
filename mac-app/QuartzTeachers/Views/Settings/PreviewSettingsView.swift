import SwiftUI

/// Plantoir ▸ Settings ▸ Preview: where a press of Preview opens the site
/// (#504, decision 504-5 — a pane of its own, between Assistant and
/// Deploying).
///
/// **Why app-wide.** Russell's comment on #504: whether a teacher wants the
/// front page or the page they were reading is how THEY work, not a fact
/// about a class, so it is asked once rather than in every course's
/// settings. Option gives the other choice for one press, and the Preview
/// button and Section ▸ Preview are titled by what will happen
/// (`PreviewStartPage.buttonTitle`).
struct PreviewSettingsView: View {

    // MARK: - Computed properties

    var body: some View {
        @Bindable var settings = AppSettings.shared
        Form {
            Section {
                Picker(PreviewStartPageWording.settingLabel, selection: $settings.previewOpensAt) {
                    Text(PreviewStartPageWording.frontPageChoice)
                        .tag(PreviewOpensAt.frontPage)
                    Text(PreviewStartPageWording.lastViewedChoice)
                        .tag(PreviewOpensAt.lastViewed)
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("previewOpensAtPicker")
            } footer: {
                Text(PreviewStartPageWording.optionNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        // A teacher's change, recorded once, in their words. The setting's
        // own `didSet` stores it; this is the trail's half (rule 5).
        .onChange(of: settings.previewOpensAt) { _, choice in
            ActivityTrail.note(.previewStartPageChosenInSettings, PreviewStartPage.settingChangedWords(choice))
        }
        // `.contain` BEFORE the identifier (#353): without it SwiftUI puts
        // the container's identifier on every element inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("previewSettings")
    }
}
