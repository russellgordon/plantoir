import SwiftUI

/// How a Course Settings change went once it reached the door (#899).
enum SettingWriteResult: Equatable {

    /// Saved, including a change that stopped part way and that Plantoir
    /// finished at once by content: nothing is said.
    case saved

    /// Not made (refused, or stopped and put back): the sentence to show.
    case refused(String)

    /// Stopped part way and could not be finished: step `seq` is left in
    /// flight, and the caller offers to put it back.
    case couldNotFinish(seq: Int)
}

/// The offer the alert makes: which step, which setting, and what it held.
struct SettingPutBackOffer: Equatable, Identifiable {

    // MARK: - Stored properties

    let seq: Int

    /// The setting's name in lower case, as the alert says it: "school
    /// year", "course name", or "course settings" for several at once.
    let setting: String

    /// The value before, as the teacher reads it; nil when several settings
    /// changed at once and they go back together.
    let valueBefore: String?

    // MARK: - Computed properties

    var id: Int {
        return seq
    }

    /// The alert's informative text: the one value it goes back to, or the
    /// settings put back as they were.
    var informativeText: String {
        if let valueBefore {
            return ReferenceWording.settingCanBePutBack(value: valueBefore)
        }
        return ReferenceWording.settingsCanBePutBack
    }
}

/// The trail's lines for a setting's stop and its answer (#899, the
/// settings sweep's LOW A4): every caller of the alert leaves the same
/// three, so a stop somebody is asked about next week can be explained.
enum SettingStopTrail {

    // MARK: - Functions

    static func offered(setting: String, course: String) -> String {
        return "the " + setting + " for " + course + " could not be changed — stopped part way, offered to put back"
    }

    static func notNow(setting: String, course: String) -> String {
        return "the " + setting + " for " + course + " was left as it stopped (Not Now): the next launch settles it"
    }

    static func putItBack(setting: String, course: String, verdict: UndoPutBackVerdict) -> String {
        if verdict == .putBack {
            return "the " + setting + " for " + course + " was put back as it was (Put It Back)"
        }
        return "the " + setting + " for " + course + " could not be put back either (Put It Back): left for the next launch"
    }
}

/// The teacher's answer.
enum SettingPutBackAnswer: Equatable {
    case notNow
    case putItBack
}

/// The alert a Course Settings field shows when its change stopped part way
/// and Plantoir could not finish it (#899, Russell's ruling of 2026-11-26):
/// one call per field, with its own setting's name and old value.
///
/// HIG, Alerts: "Cancel buttons are typically on the leading side of a
/// row"; "Always place the default button on the trailing side of a row";
/// Put It Back is the default because it is the fix being offered and
/// nothing is lost by it. Not Now is the cancel role, so Escape answers it,
/// and Put It Back is the default action, so Return does: both shown on
/// the buttons themselves, no hidden key catcher.
///
/// The app's usual alert pattern (`SidebarView.removalRequestIsPresented`):
/// closing the alert only clears the offer, and each button acts on the
/// offer the alert was handed, so the outcome never depends on whether
/// SwiftUI closes the alert before or after it runs the button's action
/// (the first review of #899's settings piece, HIGH 1).
struct SettingPutBackAlert: ViewModifier {

    // MARK: - Stored properties

    @Binding var offer: SettingPutBackOffer?

    let answer: (SettingPutBackAnswer, SettingPutBackOffer) -> Void

    // MARK: - Computed properties

    var isPresented: Binding<Bool> {
        return Binding(
            get: { return offer != nil },
            set: { showing in
                if !showing {
                    alertClosed()
                }
            }
        )
    }

    // MARK: - Functions

    /// The alert closed: the offer is cleared, nothing is answered.
    func alertClosed() {
        offer = nil
    }

    /// A button was pressed: its answer, on the offer the alert showed.
    func answered(_ chosen: SettingPutBackAnswer, with shown: SettingPutBackOffer) {
        offer = nil
        answer(chosen, shown)
    }

    func body(content: Content) -> some View {
        content.alert(
            ReferenceWording.settingCouldNotBeChanged(setting: offer?.setting ?? ""),
            isPresented: isPresented,
            presenting: offer
        ) { shown in
            Button(ReferenceWording.notNowButton, role: .cancel) {
                answered(.notNow, with: shown)
            }
            .keyboardShortcut(.cancelAction)
            Button(ReferenceWording.putItBackButton) {
                answered(.putItBack, with: shown)
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("settingPutItBackButton")
        } message: { shown in
            Text(shown.informativeText)
        }
    }
}

extension View {

    // MARK: - Functions

    func settingPutBackAlert(
        offer: Binding<SettingPutBackOffer?>,
        answer: @escaping (SettingPutBackAnswer, SettingPutBackOffer) -> Void
    ) -> some View {
        return modifier(SettingPutBackAlert(offer: offer, answer: answer))
    }
}
