import SwiftUI

/// The footer HTML editor, with a prompt explaining what belongs here and
/// a placeholder inside the box making it obvious that it accepts typing.
struct FooterEditorView: View {

    // MARK: - Stored properties

    @Binding var footerHTML: String

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Optional: type or paste HTML below to appear at the bottom of every page on your site — many teachers use a Creative Commons licence notice. Leave the box empty for no footer.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $footerHTML)
                    .font(.body.monospaced())
                    .frame(minHeight: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.tertiary)
                    )
                    // Named by its section's heading (#1012); the example
                    // drawn over the empty box is not a name.
                    .accessibilityLabel(Text("Footer"))
                    .accessibilityIdentifier("footerEditor")

                if footerHTML.isEmpty {
                    Text("For example: This site is licensed under <a href=\"…\">CC BY 4.0</a>.")
                        .font(.body.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
