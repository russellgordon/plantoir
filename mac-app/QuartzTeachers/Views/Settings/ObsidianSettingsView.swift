import SwiftUI

/// Plantoir ▸ Settings ▸ Obsidian (#495): whether Plantoir adds Obsidian's
/// add-ons for diagrams and graphs to the courses that have them.
///
/// The one place the answer can be changed after it is given — the only way
/// back from "Don't ask again". On is yes; off is no; never asked shows as
/// off. Turning it off adds nothing new and removes nothing already added:
/// taking an add-on out of a course is the teacher's to do in Obsidian, where
/// they can see it.
struct ObsidianSettingsView: View {

    // MARK: - Computed properties

    var body: some View {
        Form {
            Section {
                Toggle(ObsidianFigureAddOnsWording.settingLabel, isOn: isOn)
                    .accessibilityIdentifier("obsidianFigureAddOnsToggle")
            } footer: {
                Text(ObsidianFigureAddOnsWording.settingFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        // `.contain` BEFORE the identifier (#353): without it SwiftUI puts
        // the container's identifier on every element inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("obsidianSettings")
    }

    /// The toggle's binding. The trail's line is written HERE, by the
    /// teacher's own change, rather than by watching the setting — the offer
    /// changes the same setting, and that is its own line (rule 5).
    private var isOn: Binding<Bool> {
        return Binding(
            get: { return AppSettings.shared.obsidianFigureAddOns == .yes },
            set: { turnedOn in
                AppSettings.shared.obsidianFigureAddOns = ObsidianSettingsView.answer(turnedOn: turnedOn)
                ActivityTrail.note(.obsidianAddOnsSettingChanged, ObsidianFigureAddOnsTrail.settingChanged(on: turnedOn))
            }
        )
    }

    // MARK: - Functions

    /// What the toggle stores.
    static func answer(turnedOn: Bool) -> ObsidianFigureAddOnsAnswer {
        return turnedOn ? .yes : .no
    }
}
