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

    /// The setting's name in lower case, as the alert says it.
    let setting: String

    /// The value before, as the teacher reads it.
    let valueBefore: String

    // MARK: - Computed properties

    var id: Int {
        return seq
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
struct SettingPutBackAlert: ViewModifier {

    // MARK: - Stored properties

    @Binding var offer: SettingPutBackOffer?

    let answer: (SettingPutBackAnswer) -> Void

    // MARK: - Computed properties

    var isPresented: Binding<Bool> {
        return Binding(
            get: { return offer != nil },
            set: { showing in
                if !showing && offer != nil {
                    answer(.notNow)
                }
            }
        )
    }

    // MARK: - Functions

    func body(content: Content) -> some View {
        content.alert(
            ReferenceWording.settingCouldNotBeChanged(setting: offer?.setting ?? ""),
            isPresented: isPresented,
            presenting: offer
        ) { _ in
            Button(ReferenceWording.notNowButton, role: .cancel) {
                answer(.notNow)
            }
            .keyboardShortcut(.cancelAction)
            Button(ReferenceWording.putItBackButton) {
                answer(.putItBack)
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("settingPutItBackButton")
        } message: { shown in
            Text(ReferenceWording.settingCanBePutBack(value: shown.valueBefore))
        }
    }
}

extension View {

    // MARK: - Functions

    func settingPutBackAlert(
        offer: Binding<SettingPutBackOffer?>, answer: @escaping (SettingPutBackAnswer) -> Void
    ) -> some View {
        return modifier(SettingPutBackAlert(offer: offer, answer: answer))
    }
}
