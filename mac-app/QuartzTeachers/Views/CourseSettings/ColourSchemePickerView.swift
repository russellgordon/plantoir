import SwiftUI

/// A picker over the toolchain's colour schemes, with a small swatch of
/// each scheme's light-mode colours beside its name.
struct ColourSchemePickerView: View {

    // MARK: - Stored properties

    @Binding var selectedSchemeID: String

    // MARK: - Body

    var body: some View {
        // The picker and its swatch preview share ONE form row, so no
        // divider separates the setting from its preview.
        VStack(alignment: .leading, spacing: 8) {
            Picker("Colour scheme", selection: $selectedSchemeID) {
                if selectedSchemeID.isEmpty {
                    Text(CourseSettingsWording.colourSchemeNoneChosen).tag("")
                }
                ForEach(ColourSchemeCatalog.schemes) { scheme in
                    Text(scheme.name).tag(scheme.id)
                }
            }

            if let scheme = ColourSchemeCatalog.scheme(withID: selectedSchemeID) {
                SampleBox {
                    HStack(spacing: 4) {
                        Text("Preview:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach(scheme.swatchHexValues, id: \.self) { hexValue in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hexString: hexValue))
                                .frame(width: 22, height: 14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(.quaternary)
                                )
                        }
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }
}
