import SwiftUI

/// The settings editor for one course: the same choices the setup wizard
/// offers, presented as a form. Save writes `course_config.json` — the file
/// the command-line scripts read — and Cancel reverts to the last save.
struct CourseSettingsView: View {

    // MARK: - Stored properties

    let course: Course

    @State var isShowingFoldersHelp: Bool = false
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
                        items: $configuration.sharedFolders,
                        onRemove: { name in
                            configuration.exclude(name, inScope: "shared")
                            ActivityTrail.note(.itemExcluded, "excluded shared folder " + name + " in " + course.code)
                        },
                        onAdd: { name in
                            if configuration.reinclude(name, inScope: "shared") {
                                ActivityTrail.note(.itemReincluded, "re-included shared folder " + name + " in " + course.code)
                            }
                        }
                    )
                    StringListEditorView(
                        title: "Shared files (all sections)",
                        hidesMarkdownExtension: true,
                        items: $configuration.sharedFiles,
                        onRemove: { name in
                            configuration.exclude(name, inScope: "shared")
                            ActivityTrail.note(.itemExcluded, "excluded shared file " + name + " in " + course.code)
                        },
                        onAdd: { name in
                            if configuration.reinclude(name, inScope: "shared") {
                                ActivityTrail.note(.itemReincluded, "re-included shared file " + name + " in " + course.code)
                            }
                        }
                    )
                    StringListEditorView(
                        title: "Per-section folders",
                        items: $configuration.perSectionFolders,
                        onRemove: { name in
                            configuration.exclude(name, inScope: "per_section")
                            ActivityTrail.note(.itemExcluded, "excluded per-section folder " + name + " in " + course.code)
                        },
                        onAdd: { name in
                            if configuration.reinclude(name, inScope: "per_section") {
                                ActivityTrail.note(.itemReincluded, "re-included per-section folder " + name + " in " + course.code)
                            }
                        }
                    )
                    StringListEditorView(
                        title: "Per-section files",
                        hidesMarkdownExtension: true,
                        items: $configuration.perSectionFiles,
                        onRemove: { name in
                            configuration.exclude(name, inScope: "per_section")
                            ActivityTrail.note(.itemExcluded, "excluded per-section file " + name + " in " + course.code)
                        },
                        onAdd: { name in
                            if configuration.reinclude(name, inScope: "per_section") {
                                ActivityTrail.note(.itemReincluded, "re-included per-section file " + name + " in " + course.code)
                            }
                        }
                    )
                    Text("Tip: you can also simply create new folders in Obsidian — they’re added to your site automatically the next time you preview (unless you have removed them here).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    FormSectionHeader("Content Structure")
                }

                Section {
                    MembershipToggleListView(
                        title: "Folders whose work counts for marks",
                        allItems: gradedFolderChoices,
                        members: gradedFoldersBinding
                    )
                    Text("The curriculum map uses this to show which expectations you have actually evaluated. Most courses keep “Tasks”; add “Tests” or anything else you mark, and remove what you don’t.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("What else does Plantoir use my folders for?") {
                        isShowingFoldersHelp = true
                    }
                    .buttonStyle(.link)
                } header: {
                    FormSectionHeader("Marks")
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
                .sheet(isPresented: $isShowingFoldersHelp) {
                    SpecialFoldersHelpView(course: course)
                }
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

    // MARK: - Computed properties

    /// Every folder that could hold work counting for marks.
    ///
    /// Not just the top-level lists. The build matches a graded folder at ANY
    /// DEPTH, so a course with `Portfolios/Tasks` has assessed work that the
    /// declared lists never mention — and a control that showed only the
    /// top-level folders would have let a teacher's first tick freeze a pool
    /// that silently dropped it. That is the same silent mark-loss that made
    /// seeding every course with ["Tasks"] unsafe, arriving through the
    /// interface instead.
    var gradedFolderChoices: [String] {
        var choices: [String] = []
        for folder in course.configuration.sharedFolders {
            if !choices.contains(folder) {
                choices.append(folder)
            }
        }
        for folder in course.configuration.perSectionFolders {
            if !choices.contains(folder) {
                choices.append(folder)
            }
        }
        for folder in CourseSettingsView.nestedFolderNames(in: course) {
            if !choices.contains(folder) {
                choices.append(folder)
            }
        }
        return choices
    }

    /// Folder names below the top level of a course, so the marks list can
    /// offer what the build can actually count.
    ///
    /// Deliberately shallow and cheap: build outputs, Plantoir's own
    /// bookkeeping and `Media` are skipped, and it stops at four levels deep.
    ///
    /// That cap means the list is not exhaustive, and the earlier claim that it
    /// was "complete before it can be frozen" was too strong — a graded folder
    /// buried five levels down is still absent. It is far more complete than
    /// the top-level lists alone, which is what the case that mattered needed,
    /// and the cap is what keeps this affordable on a course of a few thousand
    /// pages.
    static func nestedFolderNames(in course: Course) -> [String] {
        let skipped: Set<String> = [
            ".merged_output", "merged_output", ".internal", ".obsidian",
            "node_modules", "Media", ".git",
        ]
        // A section folder is not somewhere work lives — its CONTENTS are
        // merged into the site and its own name never appears in a page's path
        // there, so ticking it would count nothing. Its children are still
        // walked, because a graded folder inside a section certainly does count.
        let isSectionFolder: (String) -> Bool = { name in
            return name.lowercased().hasPrefix("section")
                && Int(name.dropFirst("section".count)) != nil
        }
        var names: [String] = []
        let manager: FileManager = FileManager.default
        guard let walker = manager.enumerator(
            at: course.directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return names
        }
        for case let url as URL in walker {
            if walker.level > 4 {
                walker.skipDescendants()
                continue
            }
            let name: String = url.lastPathComponent
            if skipped.contains(name) {
                walker.skipDescendants()
                continue
            }
            let isDirectory: Bool = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDirectory && !isSectionFolder(name) && !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    /// The pool, shown as ticks.
    ///
    /// When the course has never been asked (`gradedFolders` is nil), the
    /// folders the build currently counts are shown ticked — the historical
    /// rule, any folder whose name mentions tasks — so what a teacher sees is
    /// what is actually happening rather than a blank list. Nothing is written
    /// until they change something, and the moment they do, the answer becomes
    /// explicit and the historical rule stops applying to this course.
    ///
    /// Which is why the derived list must be as complete as it can afford to
    /// be: the first tick freezes it, so anything the build counts today and
    /// this list omits loses its marks without a word.
    var gradedFoldersBinding: Binding<[String]> {
        return Binding(
            get: {
                if let chosen = course.configuration.gradedFolders {
                    return chosen
                }
                var counted: [String] = []
                for folder in gradedFolderChoices {
                    if folder.lowercased().contains("task") {
                        counted.append(folder)
                    }
                }
                return counted
            },
            set: { newValue in
                course.configuration.gradedFolders = newValue
            }
        )
    }
}
