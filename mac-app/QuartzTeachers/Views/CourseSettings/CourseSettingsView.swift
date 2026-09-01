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
                            dropFromMarksPool(name)
                            ActivityTrail.note(.itemExcluded, "excluded shared folder " + name + " in " + course.code)
                        },
                        onAdd: { name in
                            if configuration.reinclude(name, inScope: "shared") {
                                ActivityTrail.note(.itemReincluded, "re-included shared folder " + name + " in " + course.code)
                            }
                        },
                        protection: sharedFolderProtection,
                        renameProblem: { oldName, newName in
                            return folderRenameProblem(oldName, to: newName, scope: .shared)
                        },
                        onRename: { oldName, newName in
                            return renameFolder(oldName, to: newName, scope: .shared)
                        },
                        noticeAfterChange: { name, change in
                            return noticeAfterFolderChange(name, change: change, scope: .shared)
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
                            dropFromMarksPool(name)
                            ActivityTrail.note(.itemExcluded, "excluded per-section folder " + name + " in " + course.code)
                        },
                        onAdd: { name in
                            if configuration.reinclude(name, inScope: "per_section") {
                                ActivityTrail.note(.itemReincluded, "re-included per-section folder " + name + " in " + course.code)
                            }
                        },
                        protection: perSectionFolderProtection,
                        renameProblem: { oldName, newName in
                            return folderRenameProblem(oldName, to: newName, scope: .perSection)
                        },
                        onRename: { oldName, newName in
                            return renameFolder(oldName, to: newName, scope: .perSection)
                        },
                        noticeAfterChange: { name, change in
                            return noticeAfterFolderChange(name, change: change, scope: .perSection)
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
                        },
                        protection: perSectionFileProtection
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
                        members: gradedFoldersBinding,
                        protection: gradedFolderProtection
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

    /// A folder removed from the course leaves the marks pool as well, so the
    /// confirmation's promise ("Removing it will take it out of your course's
    /// marks pool") is kept, and `graded_folders` never names a folder the
    /// build has been told to exclude. Goes through `gradedFoldersBinding` so
    /// a never-asked course (nil pool) is materialised on the way, exactly as
    /// a tick would do it.
    func dropFromMarksPool(_ name: String) {
        let currentGraded: [String] = gradedFoldersBinding.wrappedValue
        if !currentGraded.contains(name) {
            return
        }
        var remaining: [String] = []
        for folder in currentGraded {
            if folder != name {
                remaining.append(folder)
            }
        }
        gradedFoldersBinding.wrappedValue = remaining
    }

    // MARK: - Renaming a folder

    /// Why this folder cannot take that name, or nil when it can.
    ///
    /// The names it is checked against are the ones in its OWN scope. A shared
    /// folder and a per-section folder may legitimately share a name — they
    /// live in different places on disk, and `discover_shared_items` and
    /// `discover_section_items` scan for them separately — so checking both
    /// lists would refuse a rename that is perfectly fine.
    func folderRenameProblem(_ oldName: String, to newName: String, scope: FolderScope) -> String? {
        let namesInScope: [String]
        switch scope {
        case .shared:
            namesInScope = course.configuration.sharedFolders
        case .perSection:
            namesInScope = course.configuration.perSectionFolders
        }
        return SpecialFolderRenamer.problem(
            renaming: oldName, to: newName, existingNames: namesInScope
        )
    }

    /// Renames the folder on disk and rewrites the configuration keys that
    /// named it, in that order.
    ///
    /// Disk first on purpose: if the move fails, nothing has been written and
    /// the course is exactly as it was. The other way round would leave a
    /// configuration naming a folder that is not there — which is the state
    /// this whole feature exists to make impossible.
    func renameFolder(_ oldName: String, to newName: String, scope: FolderScope) -> RenameResult {
        let outcome: FolderRenameOutcome
        do {
            outcome = try SpecialFolderRenamer.rename(
                oldName, to: newName, scope: scope,
                courseDirectory: course.directoryURL,
                sectionNumbers: course.configuration.sectionNumbers
            )
        } catch {
            return .failed(error.localizedDescription)
        }
        do {
            try course.configuration.recordOnDisk({ values in
                return SpecialFolderRenamer.renaming(oldName, to: newName, scope: scope, in: values)
            }, at: course.configFileURL)
        } catch {
            // Recorded BEFORE returning, and that ordering is the point: this
            // is the one outcome the trail exists for. The folder has moved
            // and the settings do not know, which is the state somebody will
            // be asked to explain later — and it was the one case with no line
            // at all, because the note used to sit after this block.
            ActivityTrail.note(
                .folderRenamed,
                "renamed the folder " + oldName + " to " + newName + " in " + course.code
                + " but could not write it to this course's settings — "
                + error.localizedDescription
            )
            // The folder HAS moved, so this is not "the rename failed" — it is
            // a rename whose bookkeeping did not land, and saying otherwise
            // would send the teacher looking for a folder under its old name.
            return .failed(
                "“\(oldName)” was renamed to “\(newName)”, but Plantoir could not write the "
                + "change to this course's settings: \(error.localizedDescription)"
            )
        }
        ActivityTrail.note(
            .folderRenamed,
            "renamed the folder " + oldName + " to " + newName + " in " + course.code
            + " (" + scope.configurationKey + ", " + String(outcome.foldersMoved) + " moved, "
            + String(outcome.pagesRelinked) + " pages relinked)"
        )
        // A rename that moved nothing is not a failure — a per-section folder
        // may legitimately be missing from a section a teacher never filled in
        // — but it must not be reported as though folders had moved. Told
        // plainly, because the alternative is a teacher going to Obsidian to
        // look for a folder that was never there.
        if outcome.foldersMoved == 0 {
            return .renamed(
                SpecialNames.renameFolderDone(from: oldName, to: newName)
                + " " + SpecialNames.renameFolderNothingWasThere
            )
        }
        return .renamed(
            SpecialNames.renameFolderDone(from: oldName, to: newName)
            + " " + SpecialNames.renameFolderRelinked(pages: outcome.pagesRelinked)
        )
    }

    /// What a teacher is told after adding or removing a folder — including
    /// the folder Plantoir has just made for them, which would otherwise
    /// appear in their vault unexplained.
    func noticeAfterFolderChange(_ name: String, change: ListChange, scope: FolderScope) -> String? {
        switch change {
        case .added:
            if createFoldersOnDisk(named: name, scope: scope) {
                ActivityTrail.note(
                    .folderCreated,
                    "created the folder " + name + " in " + course.code
                    + " (" + scope.configurationKey + ")"
                )
                return SpecialNames.addCreatesTheFolderMessage(name: name)
            }
            return nil
        case .removed:
            return SpecialNames.removeLeavesTheFolderOnDiskMessage(name: name)
        }
    }

    /// Makes the folder the teacher just named, wherever its scope says it
    /// lives, and reports whether anything was actually created.
    ///
    /// Adding a name used to write a configuration entry pointing at nothing,
    /// so the folder had to be made in Obsidian afterwards or the entry named
    /// something that did not exist. Nothing is put INSIDE it: an empty folder
    /// is the honest starting state, and inventing a page would put words in
    /// the teacher's mouth.
    func createFoldersOnDisk(named name: String, scope: FolderScope) -> Bool {
        let locations: [URL] = SpecialFolderRenamer.folderLocations(
            named: name, scope: scope,
            courseDirectory: course.directoryURL,
            sectionNumbers: course.configuration.sectionNumbers
        )
        var created: Bool = false
        for location in locations {
            if FileManager.default.fileExists(atPath: location.path) {
                continue
            }
            do {
                try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
                created = true
            } catch {
                // Re-adding a name whose folder is already there is the common
                // case and is not worth a word; a genuine failure shows up as
                // the folder simply not being there, which the build's own
                // checks already report in the teacher's own terms.
                continue
            }
        }
        return created
    }

    func sharedFolderProtection(for folder: String) -> ItemProtection {
        let resolvedCurriculum: String? = CurriculumFolderRule.resolvedCurriculumFolder(for: course)
        if let resolvedCurriculum, folder == resolvedCurriculum {
            if course.configuration.includesCurriculumCoverage {
                return .blocked(reason: SpecialNames.curriculumFolderBlockedByCoverageSetting)
            } else {
                return .consequential(
                    title: SpecialNames.removeCurriculumFolderTitle(for: folder),
                    message: SpecialNames.removeCurriculumFolderMessage
                )
            }
        }
        let currentGraded: [String] = gradedFoldersBinding.wrappedValue
        if currentGraded.contains(folder) {
            if course.configuration.includesCurriculumCoverage && currentGraded.count <= 1 {
                return .blocked(reason: SpecialNames.lastGradedFolderBlocked)
            } else {
                return .consequential(
                    title: SpecialNames.removeGradedFolderTitle(for: folder),
                    message: SpecialNames.removeGradedFolderMessage
                )
            }
        }
        return .ordinary
    }

    func perSectionFolderProtection(for folder: String) -> ItemProtection {
        if course.configuration.perSectionFolders.count <= 1 {
            return .blocked(reason: SpecialNames.lastPerSectionFolderBlocked)
        }
        let currentGraded: [String] = gradedFoldersBinding.wrappedValue
        if currentGraded.contains(folder) && course.configuration.includesCurriculumCoverage && currentGraded.count <= 1 {
            return .blocked(reason: SpecialNames.lastGradedFolderBlocked)
        }
        // "All Classes" — exactly that folder — is never removable (Russell,
        // 2026-08-24): the next-class button and the schedule write pages
        // into it, so a confirmation would be asking the teacher to break
        // both. Every other per-section folder can be added or removed.
        if ClassFolder.isTheAllClassesFolder(folder, configured: course.configuration.classFolder) {
            return .blocked(reason: SpecialNames.classFolderBlocked)
        }
        if currentGraded.contains(folder) {
            return .consequential(
                title: SpecialNames.removeGradedFolderTitle(for: folder),
                message: SpecialNames.removeGradedFolderMessage
            )
        }
        return .ordinary
    }

    func perSectionFileProtection(for file: String) -> ItemProtection {
        let normalized: String = file.lowercased()
        if normalized == "index.md" || normalized == "index" {
            return .blocked(reason: SpecialNames.sectionIndexFileBlocked)
        }
        return .ordinary
    }

    func gradedFolderProtection(for folder: String) -> ItemProtection {
        guard course.configuration.includesCurriculumCoverage else {
            return .ordinary
        }
        let currentGraded: [String] = gradedFoldersBinding.wrappedValue
        if currentGraded.contains(folder) && currentGraded.count <= 1 {
            return .blocked(reason: SpecialNames.lastGradedFolderBlocked)
        }
        return .ordinary
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
}
