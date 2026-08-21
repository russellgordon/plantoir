import SwiftUI

/// The settings editor for one course: the same choices the setup wizard
/// offers, presented as a form. Save writes `course_config.json` — the file
/// the command-line scripts read — and Cancel reverts to the last save.
struct CourseSettingsView: View {

    // MARK: - Stored properties

    let course: Course

    @State var saveProblem: String?
    @State var didJustSave: Bool = false

    // MARK: - Body

    var body: some View {
        @Bindable var configuration = course.configuration
        @Bindable var settings = AppSettings.shared

        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Course name", text: $configuration.courseName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("courseNameField")

                    if configuration.isClub {
                        TextField("Short label beside emoji (clubs, ≤ 12 characters)", text: $configuration.customShortName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("customShortNameField")
                    }

                    Picker("Language / region (Quartz locale)", selection: $configuration.locale) {
                        ForEach(LocaleCatalog.codes, id: \.self) { code in
                            Text(LocaleCatalog.displayName(forCode: code))
                                .tag(code)
                        }
                    }

                    Toggle("Show page read-time estimates to students", isOn: $configuration.showReadingTime)
                        .accessibilityIdentifier("readingTimeToggle")

                    // The map is drawn from this site's own links to the
                    // curriculum pages, and its explanatory sections live on
                    // it — so the second switch is off and unavailable
                    // whenever the first one is off.
                    Toggle("Publish the curriculum coverage map", isOn: $configuration.includesCurriculumCoverage)
                        .accessibilityIdentifier("coverageToggle")
                    Toggle("Explain the map on the page", isOn: $configuration.includesCoverageNotes)
                        .disabled(!configuration.includesCurriculumCoverage)
                        .accessibilityIdentifier("coverageNotesToggle")

                    Picker("Sidebar folders expand when clicking", selection: $configuration.expandOnFolderClick) {
                        Text("Chevron or folder name").tag(true)
                        Text("Chevron only (name opens the folder)").tag(false)
                    }
                } header: {
                    FormSectionHeader("Settings — Overall")
                }

                Section {
                    PublishingChoiceView(
                        deployTarget: $configuration.deployTarget,
                        deployFolderPath: $configuration.deployFolderPath,
                        cloudflareAccountID: $settings.cloudflareAccountID,
                        additionalDeployTargets: $configuration.additionalDeployTargets
                    )
                } header: {
                    FormSectionHeader("Deploying")
                }

                Section {
                    FooterEditorView(footerHTML: $configuration.footerHTML)
                } header: {
                    FormSectionHeader("Footer")
                }

                Section {
                    StringListEditorView(
                        title: "Shared folders (all sections)",
                        items: $configuration.sharedFolders
                    )
                    StringListEditorView(
                        title: "Shared files (all sections)",
                        hidesMarkdownExtension: true,
                        items: $configuration.sharedFiles
                    )
                    StringListEditorView(
                        title: "Per-section folders",
                        items: $configuration.perSectionFolders
                    )
                    StringListEditorView(
                        title: "Per-section files",
                        hidesMarkdownExtension: true,
                        items: $configuration.perSectionFiles
                    )
                    Text("Tip: you can also simply create new folders in Obsidian — they’re added to your site automatically the next time you preview.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    FormSectionHeader("Content Structure")
                }

                Section {
                    MembershipToggleListView(
                        title: "Hide from the site's sidebar",
                        allItems: configuration.allSidebarItems,
                        members: $configuration.hiddenItems
                    )
                    MembershipToggleListView(
                        title: "Expandable in the site's sidebar",
                        allItems: configuration.allSidebarItems,
                        members: $configuration.expandableItems
                    )
                } header: {
                    FormSectionHeader("Sidebar Visibility")
                }

                ForEach(course.sectionNumbers, id: \.self) { sectionNumber in
                    SectionSettingsView(
                        configuration: configuration,
                        sectionNumber: sectionNumber
                    )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                // "Revert", not "Cancel": this is a settings form, not a
                // dialog — the button puts the values back the way the last
                // save left them.
                Button("Revert") {
                    try? course.configuration.discardChanges()
                }
                .disabled(!course.configuration.hasUnsavedChanges)
                .accessibilityIdentifier("revertButton")

                Spacer()

                if let saveProblem {
                    Text(saveProblem)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                if didJustSave {
                    Text("Saved ✓")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .accessibilityIdentifier("savedConfirmation")
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!course.configuration.hasUnsavedChanges || savingProblem != nil)
                .accessibilityIdentifier("saveButton")
            }
            .padding(12)
        }
        .navigationTitle(course.code)
        .toolbar {
            ToolbarItem {
                Button("Open in Obsidian", systemImage: "square.and.pencil") {
                    FolderActions.openInObsidian(revealing: course.directoryURL, vaultURL: course.directoryURL)
                }
                .disabled(!FolderActions.obsidianIsInstalled)
                .help("Edit this course's pages in Obsidian")
                .accessibilityIdentifier("openCourseInObsidianButton")
            }
        }
        .navigationSubtitle(course.configuration.courseName)
    }

    // MARK: - Computed properties

    /// Why saving is blocked right now, or nil when it isn't. A deploy
    /// destination that cannot be reached must not reach disk: the deploy
    /// would quietly have nowhere to go, and would only say so much later.
    var savingProblem: String? {
        if course.configuration.deployTarget == "local_folder" {
            if let problem = CourseConfiguration.deployFolderProblem(forPath: course.configuration.deployFolderPath) {
                return problem
            }
        }
        if course.configuration.deploysToCloudflare {
            if let problem = CourseConfiguration.cloudflareAccountProblem(forID: AppSettings.shared.cloudflareAccountID) {
                return problem
            }
        }
        // Every ADDITIONAL destination gets the same check — a redundancy
        // target with no valid folder or credential would otherwise only
        // fail the first time a deploy actually reached it.
        for target in course.configuration.additionalDeployTargets {
            if target.type == "local_folder" {
                if let problem = CourseConfiguration.deployFolderProblem(forPath: target.path) {
                    return problem
                }
            }
            if target.type == "cloudflare_pages" {
                if let problem = CourseConfiguration.cloudflareAccountProblem(forID: AppSettings.shared.cloudflareAccountID) {
                    return problem
                }
            }
        }
        return nil
    }

    // MARK: - Functions

    func save() {
        saveProblem = nil
        if let savingProblem {
            saveProblem = savingProblem
            return
        }
        do {
            try course.configuration.write(to: course.configFileURL)
            ActivityTrail.note(.settingsSaved, "saved the settings for " + course.code)
            didJustSave = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                didJustSave = false
            }
        } catch {
            saveProblem = "Could not save: \(error.localizedDescription)"
            ActivityTrail.note(.settingsCouldNotBeSaved, "could not save the settings for " + course.code + " — " + error.localizedDescription)
        }
    }
}
