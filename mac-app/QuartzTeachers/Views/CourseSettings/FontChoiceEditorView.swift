import SwiftUI

/// Edits the header/body pairing and code font for one section, offering
/// the wizard's curated choices plus free-form custom entry.
struct FontChoiceEditorView: View {

    // MARK: - Stored properties

    @Binding var choice: FontChoice

    /// The text the header-font sample renders. Once a course has a name,
    /// the sample shows THAT — the teacher previews their own site's
    /// headline, not a stand-in course's.
    var sampleHeadline: String = ""

    // MARK: - Computed properties

    /// The pairing picker works on a "header|body" combined tag so custom
    /// pairings can appear as one extra option.
    var pairingTagBinding: Binding<String> {
        return Binding(
            get: {
                return choice.header + "|" + choice.body
            },
            set: { newTag in
                let parts: [String] = newTag.components(separatedBy: "|")
                if parts.count == 2 {
                    choice.header = parts[0]
                    choice.body = parts[1]
                }
            }
        )
    }

    var pairingOptions: [(tag: String, label: String)] {
        var result: [(tag: String, label: String)] = []
        for pairing in FontCatalog.pairings {
            let tag: String = pairing.header + "|" + pairing.body
            let label: String = FontCatalog.pairingLabel(header: pairing.header, body: pairing.body)
            result.append((tag: tag, label: label))
        }
        let currentTag: String = choice.header + "|" + choice.body
        var isKnown: Bool = false
        for option in result {
            if option.tag == currentTag {
                isKnown = true
            }
        }
        if !isKnown {
            result.append((tag: currentTag, label: "Custom: \(choice.header) — \(choice.body)"))
        }
        return result
    }

    var codeFontOptions: [String] {
        var result: [String] = FontCatalog.codeFonts
        if !result.contains(choice.code) {
            result.append(choice.code)
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        // The picker and its sample share ONE form row, so no divider
        // separates a setting from its preview.
        VStack(alignment: .leading, spacing: 8) {
            Picker("Header & body fonts", selection: pairingTagBinding) {
                ForEach(pairingOptions, id: \.tag) { option in
                    Text(option.label).tag(option.tag)
                }
            }

            // Live previews rendered in the actual fonts (bundled with
            // the app); an unavailable font falls back to the system font.
            SampleBox {
                Text(FontChoiceEditorView.headlineSample(for: sampleHeadline))
                    .font(FontChoiceEditorView.previewFont(family: choice.header, size: 19))
                Text("Body text on your site will look like this sentence does.")
                    .font(FontChoiceEditorView.previewFont(family: choice.body, size: 13))
            }
            .accessibilityIdentifier("fontPairingPreview")
        }

        VStack(alignment: .leading, spacing: 8) {
            Picker("Code font", selection: $choice.code) {
                ForEach(codeFontOptions, id: \.self) { fontName in
                    Text(fontName).tag(fontName)
                }
            }

            SampleBox {
                Text("for number in range(10):  # code samples use this font")
                    .font(FontChoiceEditorView.previewFont(family: choice.code, size: 12))
            }
            .accessibilityIdentifier("codeFontPreview")
        }
    }

    // MARK: - Functions

    /// The headline the sample shows: the course's own name once it has
    /// one, and a stand-in until then.
    static func headlineSample(for courseName: String) -> String {
        let trimmed: String = courseName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Grade 11 Computer Science"
        }
        return trimmed
    }

    /// A preview font for a site font family. The "Helvetica, Arial"
    /// system pairing previews in the system font, which is what a site
    /// with that choice shows on a Mac (San Francisco, #629); every other
    /// family is bundled with the app and registered at launch.
    static func previewFont(family: String, size: CGFloat) -> Font {
        if family == "Helvetica, Arial" {
            return Font.system(size: size)
        }
        return Font.custom(family, size: size)
    }
}
