import SwiftUI

/// The per-section settings for one section of a course: header emoji,
/// colour scheme, fonts, and the "S1" marker toggle.
struct SectionSettingsView: View {

    // MARK: - Stored properties

    @Bindable var configuration: CourseConfiguration

    let sectionNumber: Int

    // MARK: - Computed properties

    var emojiBinding: Binding<String> {
        return Binding(
            get: { configuration.emoji(forSection: sectionNumber) },
            set: { newEmoji in configuration.setEmoji(newEmoji, forSection: sectionNumber) }
        )
    }

    var gradeInTitleBinding: Binding<Bool> {
        return Binding(
            get: { configuration.showsGradeInTitle(forSection: sectionNumber) },
            set: { newValue in configuration.setShowsGradeInTitle(newValue, forSection: sectionNumber) }
        )
    }

    var markerBinding: Binding<Bool> {
        return Binding(
            get: { configuration.showsSectionMarker(forSection: sectionNumber) },
            set: { newValue in configuration.setShowsSectionMarker(newValue, forSection: sectionNumber) }
        )
    }

    var schemeBinding: Binding<String> {
        return Binding(
            get: { configuration.colourSchemeID(forSection: sectionNumber) },
            set: { newSchemeID in configuration.setColourSchemeID(newSchemeID, forSection: sectionNumber) }
        )
    }

    /// Every destination this section's custom-domain fields cover —
    /// every configured destination EXCEPT a local folder, which has no
    /// domain concept at all (a domain is something a browser visits, and
    /// a folder is not). The overwhelming majority of courses have
    /// exactly one destination, and see exactly the field they always
    /// have — see `customDomainFieldLabel(destination:destinationCount:)`.
    var customDomainDestinations: [CourseConfiguration.DeployDestination] {
        var result: [CourseConfiguration.DeployDestination] = []
        for destination in configuration.allDeployDestinations where destination.type != "local_folder" {
            result.append(destination)
        }
        return result
    }

    func customDomainBinding(forDestinationType destinationType: String) -> Binding<String> {
        return Binding(
            get: { configuration.customDomain(forSection: sectionNumber, destinationType: destinationType) },
            set: { newDomain in
                configuration.setCustomDomain(
                    CourseConfiguration.normalizedCustomDomain(newDomain),
                    forSection: sectionNumber,
                    destinationType: destinationType
                )
            }
        )
    }

    /// A gentle warning when the entry does not read as a domain.
    func customDomainProblem(forDestinationType destinationType: String) -> String? {
        let domain: String = configuration.customDomain(forSection: sectionNumber, destinationType: destinationType)
        if domain.isEmpty {
            return nil
        }
        if domain.contains(" ") || !domain.contains(".") {
            return "That doesn’t look like a domain — e.g. ics3u.yourschool.ca"
        }
        return nil
    }

    var fontBinding: Binding<FontChoice> {
        return Binding(
            get: { configuration.fontChoice(forSection: sectionNumber) },
            set: { newChoice in configuration.setFontChoice(newChoice, forSection: sectionNumber) }
        )
    }

    // MARK: - Body

    var body: some View {
        Section {
            EmojiChoiceField(label: "Header emoji", emoji: emojiBinding)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show section marker in the site title", isOn: markerBinding)
                ExampleCaption("e.g. “S\(sectionNumber)” appears beside the course code")
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show the grade in the site title", isOn: gradeInTitleBinding)
                    .accessibilityIdentifier("gradeInTitleToggle-section\(sectionNumber)")
                if let warning = CourseConfiguration.gradeInTitleWarning(
                    courseName: configuration.courseName,
                    courseCode: configuration.courseCode,
                    showsGrade: configuration.showsGradeInTitle(forSection: sectionNumber)
                ) {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("gradeInTitleWarning-section\(sectionNumber)")
                } else {
                    ExampleCaption("e.g. “Grade 12” before the course name — applied the next time this section builds")
                }
            }

            ColourSchemePickerView(selectedSchemeID: schemeBinding)

            // The sample shows the landing title as the build will
            // actually compute it — grade prefix and section marker
            // included, exactly as this section's switches say.
            FontChoiceEditorView(
                choice: fontBinding,
                sampleHeadline: configuration.courseName.trimmingCharacters(in: .whitespaces).isEmpty
                    ? ""
                    : CourseConfiguration.landingTitle(
                        courseName: configuration.courseName,
                        courseCode: configuration.courseCode,
                        showsGrade: configuration.showsGradeInTitle(forSection: sectionNumber),
                        showsSectionMarker: configuration.showsSectionMarker(forSection: sectionNumber),
                        sectionNumber: sectionNumber
                    )
            )

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 16) {
                    // One field per destination that can even HAVE a
                    // domain (never a local folder) — labelled by service
                    // name only once there is more than one to tell apart,
                    // so the overwhelming majority of courses (one
                    // destination) see exactly the field they always have.
                    ForEach(customDomainDestinations, id: \.type) { destination in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(
                                SectionSettingsView.customDomainFieldLabel(
                                    destination: destination,
                                    destinationCount: customDomainDestinations.count
                                ),
                                text: customDomainBinding(forDestinationType: destination.type)
                            )
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("customDomainField-section\(sectionNumber)-\(destination.type)")
                            if let problem = customDomainProblem(forDestinationType: destination.type) {
                                Text(problem)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                ExampleCaption(SectionSettingsView.customDomainCaption(forDestinationType: destination.type))
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        } header: {
            FormSectionHeader("Section \(sectionNumber) Settings")
        }
    }

    // MARK: - Functions

    /// "Custom domain" for the overwhelming majority — exactly one
    /// destination, exactly the field a course has always had. Once more
    /// than one destination is configured, names WHICH service this
    /// particular field is for — a domain meant for Netlify would
    /// otherwise read as though it applied to Cloudflare Pages too, which
    /// was the actual bug this per-destination shape replaces.
    static func customDomainFieldLabel(
        destination: CourseConfiguration.DeployDestination,
        destinationCount: Int
    ) -> String {
        if destinationCount <= 1 {
            return "Custom domain"
        }
        return "\(DeployCommand.destinationDescription(for: destination)) custom domain"
    }

    /// Names the actual service this field's default address comes from —
    /// correct even in the single-destination case, where the field used
    /// to say "Netlify" unconditionally regardless of what a course's one
    /// destination actually was (a Cloudflare-only course saw a caption
    /// naming the wrong host).
    static func customDomainCaption(forDestinationType destinationType: String) -> String {
        let serviceName: String = destinationType == "cloudflare_pages" ? "Cloudflare Pages" : "Netlify"
        return "e.g. ics3u.yourschool.ca — links to your live site will use this domain instead of the \(serviceName) address. Your site must already answer there (set the domain up in \(serviceName) first). Leave empty to use the \(serviceName) address."
    }
}
