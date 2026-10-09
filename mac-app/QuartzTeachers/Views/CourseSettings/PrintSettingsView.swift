import SwiftUI

/// Course Settings' Printing section (#454): what a printed handout carries in
/// its corners. Course-wide, because a handout is the same paper for every
/// section. The build composes the corners from these four keys on every
/// build (scripts/print_settings.py; contracts/shared-rules.json →
/// printablePages.corners), so the sketch below follows the same rule.
struct PrintSettingsView: View {

    // MARK: - Stored properties

    @Bindable var configuration: CourseConfiguration

    /// The code a teacher reads, for the sketch.
    let displayedCourseCode: String

    /// The page label as a handout prints it on the first page of three -
    /// the contract's own words (printablePages.words.pageLabel), filled.
    private static let pageLabelSketch: String = CourseSettingsWording.printedPageLabel
        .replacingOccurrences(of: "{n}", with: "1")
        .replacingOccurrences(of: "{total}", with: "3")

    // MARK: - Computed properties

    /// What the top left corner will say, by the build's rule.
    private var topLeftSketch: String {
        return sketch(for: "header_left")
    }

    /// What the bottom left corner will say.
    private var bottomLeftSketch: String {
        return sketch(for: "footer_left")
    }

    /// What the top right corner will say: the chosen blanks.
    private var topRightSketch: String {
        var pieces: [String] = []
        for blank in configuration.printBlanks {
            pieces.append(CourseSettingsWording.printingBlank(blank) + " ______")
        }
        return pieces.joined(separator: "   ")
    }

    // MARK: - Body

    var body: some View {
        TextField(CourseSettingsWording.printingSchoolName, text: $configuration.printSchoolName)
            .borderedTextField()
            .accessibilityIdentifier("printSchoolNameField")

        VStack(alignment: .leading, spacing: 4) {
            Text(CourseSettingsWording.printingBlanks)
            HStack(spacing: 16) {
                ForEach(CourseConfiguration.printBlankOrder, id: \.self) { blank in
                    Toggle(CourseSettingsWording.printingBlank(blank), isOn: blankBinding(blank))
                        .accessibilityIdentifier("printBlank_" + blank)
                }
            }
        }

        Picker(CourseSettingsWording.printingSchoolNameGoes, selection: $configuration.printSchoolNameAt) {
            ForEach(CourseConfiguration.printPlaces, id: \.self) { place in
                Text(CourseSettingsWording.printingPlace(place)).tag(place)
            }
        }
        .accessibilityIdentifier("printSchoolNameAtPicker")

        Picker(CourseSettingsWording.printingCourseCodeGoes, selection: $configuration.printCourseCodeAt) {
            ForEach(CourseConfiguration.printPlaces, id: \.self) { place in
                Text(CourseSettingsWording.printingPlace(place)).tag(place)
            }
        }
        .accessibilityIdentifier("printCourseCodeAtPicker")

        SampleBox {
            HStack(alignment: .top) {
                Text(topLeftSketch)
                Spacer()
                Text(topRightSketch)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 28)
            HStack(alignment: .bottom) {
                Text(bottomLeftSketch)
                Spacer()
                Text(PrintSettingsView.pageLabelSketch)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("printCornersSketch")

        ExampleCaption(CourseSettingsWording.printingCaption)
    }

    // MARK: - Functions

    /// The school name and the course code that print at `place`, school
    /// first, joined the way the build joins them.
    private func sketch(for place: String) -> String {
        var pieces: [String] = []
        let school: String = configuration.printSchoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !school.isEmpty && configuration.printSchoolNameAt == place {
            pieces.append(school)
        }
        if !displayedCourseCode.isEmpty && configuration.printCourseCodeAt == place {
            pieces.append(displayedCourseCode.uppercased())
        }
        return pieces.joined(separator: " · ")
    }

    /// A switch for one blank that writes the whole list in print order.
    private func blankBinding(_ blank: String) -> Binding<Bool> {
        return Binding<Bool>(
            get: {
                return configuration.printBlanks.contains(blank)
            },
            set: { isOn in
                var chosen: [String] = []
                for existing in configuration.printBlanks {
                    if existing != blank {
                        chosen.append(existing)
                    }
                }
                if isOn {
                    chosen.append(blank)
                }
                configuration.printBlanks = chosen
            }
        )
    }
}
