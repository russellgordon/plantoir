import SwiftUI

/// The ONE style every editable text field in Plantoir wears: the bordered,
/// rounded field Course name has always had (#374, Russell 2026-09-27:
/// "every text field … should use the clearly differentiated style used for
/// Course name", never the borderless look).
///
/// This is the only place `.roundedBorder` is written. A field that needs a
/// different shape — the wizard's 24pt fields beside the course-code picker,
/// the searchable picker, the sidebar's rename card, the assistant's composer
/// — draws its own border and is listed, with its reason, in
/// `TextFieldStyleScanTests`, which fails on any field that has neither.
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
