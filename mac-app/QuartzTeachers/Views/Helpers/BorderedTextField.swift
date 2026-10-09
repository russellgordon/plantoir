import SwiftUI

/// The ONE style every editable text field in Plantoir wears: the bordered,
/// rounded field Course name has always had (#374, Russell 2026-09-27:
/// "every text field … should use the clearly differentiated style used for
/// Course name", never the borderless look).
///
/// This is the only place `.roundedBorder` is written, and every field wears
/// it — `TextFieldStyleScanTests` fails on any field that does not, and has
/// no allow-list (#457). (The wizard's fields and the searchable picker drew
/// a 24pt imitation of this bezel until #456; the sidebar's rename card, the
/// assistant's composer and an alert's field were exempt until #457.)
struct BorderedTextField: ViewModifier {

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.roundedBorder)
    }
}

extension View {

    // MARK: - Functions

    /// The bordered style every editable text field wears (#374).
    func borderedTextField() -> some View {
        return modifier(BorderedTextField())
    }
}
