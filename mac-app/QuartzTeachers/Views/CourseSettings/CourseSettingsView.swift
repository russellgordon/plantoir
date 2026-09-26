import SwiftUI

/// The settings editor for one course: the same choices the setup wizard
/// offers, presented as a form. Save writes `course_config.json` — the file
/// the command-line scripts read — and Cancel reverts to the last save.
struct CourseSettingsView: View {

    // MARK: - Stored properties

    let course: Course

    @State var isShowingFoldersHelp: Bool = false
    @State var isRenamingUnitWord: Bool = false

    /// What the last unit-word rename did, shown under the row until the
    /// sheet is opened again.
    @State var unitWordNotice: String? = nil
    @State var saveProblem: String?
    @State var didJustSave: Bool = false

    /// What the last Save could not reach — a preview or a publish of this
    /// course already running (issue #265). Unlike "Saved ✓" it does not
    /// fade after three seconds: it has to stay long enough to be read, so it
    /// stays until the next Save, Preview Again, or leaving this course.
    @State var saveNotice: SettingsSaveNotice? = nil

    /// Counts the times this window has become key, so the page is drawn
    /// again — and the course folder walked again for the marks questions —
    /// when the teacher comes back from Finder or Obsidian (issue #152). The
    /// floor now depends on what is on disk, and `onAppear` does not fire
    /// when a window merely becomes key again.
    @State var marksWalkGeneration: Int = 0

    /// Whether this window is key, read only to notice it BECOMING key.
    @Environment(\.controlActiveState) var controlActiveState: ControlActiveState

    // MARK: - Body

    var body: some View {
        @Bindable var configuration = course.configuration
        @Bindable var settings = AppSettings.shared
        // ONE walk of the course folder per drawing, shared by the Marks
        // checklist and by all three folder lists' protections (issue #152).
        // A walk per row cost 53 ms each on a 400-folder course; the rows are
        // drawn from this, and a click is decided afresh (`protectionWhenActedOn`).
        let _ = marksWalkGeneration
        let marks: MarksFloor.Snapshot = marksSnapshot()

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

                    // NOT a field saved with the form. Changing the word
                    // renames every class page in the course, so it goes
                    // through a sheet that shows the plan and commits straight
                    // away — Save and Revert never touch `unit_word`.
                    LabeledContent(UnitWordRenameWording.fieldLabel) {
                        HStack {
                            Text(configuration.unitWord)
                                .accessibilityIdentifier("unitWordValue")
                            Button(UnitWordRenameWording.renameButton) {
                                unitWordNotice = nil
                                isRenamingUnitWord = true
                            }
                            // A numbered course's word is part of the
                            // vocabulary chosen in the wizard (#267).
                            .disabled(configuration.classPageNaming.isNumbered)
                            .accessibilityIdentifier("renameUnitWordButton")
                        }
                    }
                    Text(UnitWordRenameWording.rowCaption(naming: configuration.classPageNaming))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if configuration.classPageNaming.isNumbered {
                        Text(UnitWordRenameWording.renameLockedNumbered)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("unitWordLockedNotice")
                    }
                    if let unitWordNotice {
                        Text(unitWordNotice)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("unitWordNotice")
                    }
                } header: {
                    FormSectionHeader("Settings — Overall")
                }

                // The words the course was made with (#267): shown, and
                // LOCKED — a club's are chosen in the wizard and are not
                // switchable afterwards, and an existing course (CODING
                // included) can never become one from here.
                Section {
                    LabeledContent(WizardWording.settingsPageNamingLabel) {
                        Text(WizardWording.settingsPageNamingValue(configuration.classPageNaming))
                            .accessibilityIdentifier("pageNamingValue")
                    }
                    LabeledContent(WizardWording.settingsFrontPageHeadingLabel) {
                        Text(WizardWording.settingsFrontPageHeadingValue(
                            configuration.recordedFrontPageHeading
                        ))
                        .accessibilityIdentifier("frontPageHeadingValue")
                    }
                    LabeledContent(WizardWording.settingsNounLabel) {
                        Text(configuration.classNoun.rawValue)
                            .accessibilityIdentifier("classNounValue")
                    }
                    Text(WizardWording.settingsLockedCaption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    FormSectionHeader("Class Pages")
                }

                Section {
                    PublishingChoiceView(
                        deployTarget: $configuration.deployTarget,
                        deployFolderPath: $configuration.deployFolderPath,
                        cloudflareAccountID: $settings.cloudflareAccountID,
                        additionalDeployTargets: $configuration.additionalDeployTargets
                    )
                    ScheduledDeployLatenessPicker(
                        days: $configuration.scheduledDeployMayRunLateDays
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
                            folderWasRemoved(name, scope: .shared)
                        },
                        onAdd: { name in
                            folderWasAdded(name, scope: .shared)
                        },
                        protection: { folder in
                            return sharedFolderProtection(for: folder, marks: marks)
                        },
                        protectionWhenActedOn: sharedFolderProtection,
                        renameProblem: { oldName, newName, finishing in
                            return folderRenameProblem(
                                oldName, to: newName, scope: .shared, finishing: finishing
                            )
                        },
                        interruptedRenameTarget: { oldName in
                            return SpecialFolderRenamer.interruptedRenameTarget(
                                from: oldName, scope: .shared,
                                courseDirectory: course.directoryURL,
                                sectionNumbers: course.configuration.sectionNumbers
                            )
                        },
                        onRename: { oldName, newName in
                            return await renameFolder(oldName, to: newName, scope: .shared)
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
                            fileWasRemoved(name, scope: .shared)
                        },
                        onAdd: { name in
                            fileWasAdded(name, scope: .shared)
                        }
                    )
                    StringListEditorView(
                        title: "Per-section folders",
                        items: $configuration.perSectionFolders,
                        onRemove: { name in
                            folderWasRemoved(name, scope: .perSection)
                        },
                        onAdd: { name in
                            folderWasAdded(name, scope: .perSection)
                        },
                        protection: { folder in
                            return perSectionFolderProtection(for: folder, marks: marks)
                        },
                        protectionWhenActedOn: perSectionFolderProtection,
                        renameProblem: { oldName, newName, finishing in
                            return folderRenameProblem(
                                oldName, to: newName, scope: .perSection, finishing: finishing
                            )
                        },
                        interruptedRenameTarget: { oldName in
                            return SpecialFolderRenamer.interruptedRenameTarget(
                                from: oldName, scope: .perSection,
                                courseDirectory: course.directoryURL,
                                sectionNumbers: course.configuration.sectionNumbers
                            )
                        },
                        onRename: { oldName, newName in
                            return await renameFolder(oldName, to: newName, scope: .perSection)
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
                            fileWasRemoved(name, scope: .perSection)
                        },
                        onAdd: { name in
                            fileWasAdded(name, scope: .perSection)
                        },
                        protection: perSectionFileProtection
                    )
                    Text(SpecialNames.contentStructureTip)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    FormSectionHeader("Content Structure")
                }

                Section {
                    MembershipToggleListView(
                        title: GradedFolderWording.listTitle,
                        allItems: marks.choices,
                        members: gradedFoldersBinding(offered: marks.choices),
                        protection: { folder in
                            return gradedFolderProtection(for: folder, marks: marks)
                        },
                        protectionWhenActedOn: gradedFolderProtection
                    )
                    Text(GradedFolderWording.caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(SpecialFoldersHelpView.openedBy) {
                        isShowingFoldersHelp = true
                    }
                    .buttonStyle(.link)
                } header: {
                    FormSectionHeader("Marks")
                }

                Section {
                    SidebarVisibilityTableView(
                        allItems: configuration.allSidebarItems,
                        hidden: $configuration.hiddenItems,
                        expandable: $configuration.expandableItems
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

            if let saveNotice {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(saveNotice.sentences, id: \.self) { sentence in
                            Text(sentence)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // The preview this was about has stopped, or its
                        // window closed: say so rather than leave a button
                        // that does nothing (the review's L2).
                        if !saveNotice.sectionsToPreviewAgain.isEmpty
                            && sectionsStillPreviewed(offered: saveNotice.sectionsToPreviewAgain).isEmpty {
                            Text(SpecialNames.settingsPreviewAgainNothingOpen)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("settingsPreviewAgainNothingOpen")
                        }
                    }
                    Spacer()
                    if !saveNotice.sectionsToPreviewAgain.isEmpty {
                        Button("Preview Again") {
                            previewAgain(sections: sectionsStillPreviewed(offered: saveNotice.sectionsToPreviewAgain))
                        }
                        .disabled(sectionsStillPreviewed(offered: saveNotice.sectionsToPreviewAgain).isEmpty)
                        .accessibilityIdentifier("settingsPreviewAgainButton")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .accessibilityIdentifier("settingsSaveNotice")
            }

            HStack {
                // "Revert", not "Cancel": this is a settings form, not a
                // dialog — the button puts the values back the way the last
                // save left them. The FILE's values, not this copy's memory
                // of them: another window may have saved since (issue #265).
                Button("Revert") {
                    revertToFile()
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
        .navigationTitle(course.displayCode)
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
                .sheet(isPresented: $isRenamingUnitWord) {
                    UnitWordRenameSheet(course: course) { sentence in
                        unitWordNotice = sentence
                    }
                }
                .accessibilityIdentifier("openCourseInObsidianButton")
            }
        }
        .navigationSubtitle(course.configuration.courseName)
        .onAppear {
            // The file may have moved on since this window read it: a build
            // adds folders it discovers, and another window on the same
            // folder may have saved. Never over unsaved edits (issue #265).
            course.configuration.reloadIfNothingUnsaved(url: course.configFileURL)
        }
        .onChange(of: controlActiveState) { oldState, newState in
            if newState == .key {
                marksWalkGeneration += 1
            }
        }
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
    ///
    /// The rule itself is `GradedFolderChoices`, so that the walk — its depth
    /// cap, its skip list, its order and the folders a teacher has REMOVED —
    /// can be run against the contract's own cases instead of living in a view
    /// nothing tests.
    var gradedFolderChoices: [String] {
        return GradedFolderChoices.choices(
            for: course.configuration, courseDirectory: course.directoryURL
        )
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
        return gradedFoldersBinding(offered: nil)
    }

    /// The same, inferring a never-asked course's pool from `offered` — the
    /// list the page was drawn with — rather than walking the course folder
    /// again. Nil walks, as the property above does.
    func gradedFoldersBinding(offered: [String]?) -> Binding<[String]> {
        return Binding(
            get: {
                if let chosen = course.configuration.gradedFolders {
                    return chosen
                }
                // The offered list is already de-duplicated by exact name, so
                // asking the shared rule — which de-duplicates too — gives the
                // answer the hand-written loop here gave.
                if let offered {
                    return GradedFolderRule.inferredPool(from: offered)
                }
                return GradedFolderRule.inferredPool(from: gradedFolderChoices)
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
            // What the file hid BEFORE this Save, for the trail — read from
            // the file, not this copy, because the file is what the site was
            // built from.
            var hiddenBefore: [String] = []
            if let onDisk = try? CourseConfiguration(contentsOf: course.configFileURL) {
                hiddenBefore = onDisk.hiddenItems
            }
            let result: CourseConfiguration.WriteResult = try course.configuration.write(to: course.configFileURL)
            let notice: SettingsSaveNotice? = SettingsSaveNotice.afterSave(
                folderPath: workingFolderPath,
                courseCode: course.code,
                previewLeases: PreviewLeases.active,
                publishes: CourseActivity.activePublishes,
                replacedChangesFromElsewhere: result.replacedChangesFromElsewhere
            )
            saveNotice = notice
            ActivityTrail.note(.settingsSaved, SettingsSaveNotice.trailLine(
                courseCode: course.code,
                hiddenBefore: hiddenBefore,
                hiddenAfter: course.configuration.hiddenItems,
                result: result,
                notice: notice
            ))
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

    /// The working folder this course lives in — the folder a preview's
    /// lease and a publish's record name.
    var workingFolderPath: String {
        return course.directoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    /// Of `offered`, the sections whose preview Preview Again can still reach.
    /// Reads `PreviewLeases.active`, which is observable, so this view is
    /// drawn again when a preview stops or its window closes.
    func sectionsStillPreviewed(offered: [Int]) -> [Int] {
        let folderPath: String = workingFolderPath
        let courseCode: String = course.code
        return SettingsSaveNotice.sectionsStillPreviewed(
            offered: offered,
            folderPath: folderPath,
            courseCode: courseCode,
            previewLeases: PreviewLeases.active,
            previewIsRunning: { section in
                guard let controller = SectionWindowControllers.shared.controller(
                    folderPath: folderPath, courseCode: courseCode, sectionNumber: section
                ) else {
                    return nil
                }
                return controller.isPreviewRunning()
            }
        )
    }

    /// Builds each open preview of this course again, so it shows what was
    /// just saved. The preview belongs to the section's own view — in another
    /// window, since leaving a section for its course's settings stops that
    /// section's preview — so this goes through the same registered controls
    /// the assistant uses, which stop and start it the way its own button
    /// does. A section whose preview has since stopped is left alone.
    func previewAgain(sections: [Int]) {
        // The preview sentence is answered; a sentence about the Save itself
        // (another window's sidebar change replaced) stays to be read.
        saveNotice = saveNotice?.withoutPreviewAgain()
        let folderPath: String = workingFolderPath
        let courseCode: String = course.code
        Task { @MainActor in
            var rebuilt: [String] = []
            for section in sections {
                guard let controller = SectionWindowControllers.shared.controller(
                    folderPath: folderPath, courseCode: courseCode, sectionNumber: section
                ) else {
                    continue
                }
                if controller.previewState() == .notRunning {
                    continue
                }
                await controller.stopPreview()
                controller.startPreview()
                rebuilt.append(String(section))
            }
            if !rebuilt.isEmpty {
                ActivityTrail.note(
                    .previewAgainAfterSettingsSaved,
                    "previewed " + courseCode + " again after saving its settings (section "
                        + rebuilt.joined(separator: ", ") + ")"
                )
            } else {
                // The button is disabled when nothing is reachable, so this
                // is the instant between drawing it and pressing it — rare,
                // and still worth a line rather than silence.
                ActivityTrail.note(
                    .previewAgainAfterSettingsSaved,
                    "pressed Preview Again for " + courseCode + ", but no preview of it was open any more"
                )
            }
        }
    }

    /// A folder removed from the course leaves the marks pool as well — with
    /// the two exceptions `contracts/shared-rules.json` →
    /// `gradedFolders.removingAFolder` pins, both of which exist to stop a
    /// removal quietly taking marks OFF the coverage map. The rule is
    /// `MarksPoolRemoval.poolAfterRemoving`, which the marks floor asks too,
    /// so the removal and the floor cannot disagree about what a removal
    /// leaves in the pool (issue #152).
    ///
    /// Called after the name has already left its list and been written into
    /// `excluded_items`, which is what makes `gradedFolderChoices` — walked
    /// again HERE, not the drawing's snapshot — the right question to ask.
    /// That order is `folderWasRemoved`'s, and issue #183's must-fails pin it.
    func dropFromMarksPool(_ name: String) {
        let current: [String]? = course.configuration.gradedFolders
        let remaining: [String]? = MarksPoolRemoval.poolAfterRemoving(
            name, from: current, choicesAfter: gradedFolderChoices
        )
        if remaining != current {
            course.configuration.gradedFolders = remaining
        }
    }

    // MARK: - Adding and removing folders and files

    /// What removing a name from one of the Content Structure lists does
    /// beyond taking it out of the list: records it in `excluded_items`, so
    /// the build stops publishing it, and takes it out of the marks pool.
    ///
    /// Named methods rather than closures written at the call site so that a
    /// test can run exactly what the list runs — the goldens for issue #266
    /// drive these, and a closure in `body` cannot be reached from a test.
    ///
    /// **The trail line is written HERE, on the click, saved or not** —
    /// Russell's decision of 2026-09-06
    /// (overnight/issues/09-item-excluded-trail-on-click.md), confirmed for
    /// issue #152 after a first build recorded at the write instead. The
    /// attempt must leave a trace even if the teacher crashes before saving;
    /// a Revert that takes it back writes `exclusions reverted`
    /// (`revertToFile()`). `contracts/shared-rules.json` →
    /// `excludedItems.recordedOnClick`.
    func folderWasRemoved(_ name: String, scope: FolderScope) {
        course.configuration.exclude(name, inScope: scope.exclusionKey)
        dropFromMarksPool(name)
        ActivityTrail.note(.itemExcluded, "excluded " + trailWord(for: scope) + " folder " + name + " in " + course.code)
    }

    /// A folder name added back to a list is taken out of `excluded_items`.
    func folderWasAdded(_ name: String, scope: FolderScope) {
        if course.configuration.reinclude(name, inScope: scope.exclusionKey) {
            ActivityTrail.note(.itemReincluded, "re-included " + trailWord(for: scope) + " folder " + name + " in " + course.code)
        }
    }

    /// The file twin of `folderWasRemoved`: a file is never in the marks pool.
    func fileWasRemoved(_ name: String, scope: FolderScope) {
        course.configuration.exclude(name, inScope: scope.exclusionKey)
        ActivityTrail.note(.itemExcluded, "excluded " + trailWord(for: scope) + " file " + name + " in " + course.code)
    }

    /// The file twin of `folderWasAdded`.
    func fileWasAdded(_ name: String, scope: FolderScope) {
        if course.configuration.reinclude(name, inScope: scope.exclusionKey) {
            ActivityTrail.note(.itemReincluded, "re-included " + trailWord(for: scope) + " file " + name + " in " + course.code)
        }
    }

    /// How the trail names a scope: "shared" or "per-section".
    func trailWord(for scope: FolderScope) -> String {
        switch scope {
        case .shared:
            return "shared"
        case .perSection:
            return "per-section"
        }
    }

    /// What the Revert button does: puts the form back to the FILE (issue
    /// #265), and — when that took back exclusion changes whose click lines
    /// are already on the trail — says so, with how many (issue #152).
    func revertToFile() {
        let sharedBefore: [String] = course.configuration.excludedItems(forScope: FolderScope.shared.exclusionKey)
        let perSectionBefore: [String] = course.configuration.excludedItems(forScope: FolderScope.perSection.exclusionKey)
        do {
            try course.configuration.revertToFile(at: course.configFileURL)
        } catch {
            return
        }
        let sharedAfter: [String] = course.configuration.excludedItems(forScope: FolderScope.shared.exclusionKey)
        let perSectionAfter: [String] = course.configuration.excludedItems(forScope: FolderScope.perSection.exclusionKey)
        let takenBack: Int = CourseSettingsView.namesThatDiffer(sharedBefore, sharedAfter)
            + CourseSettingsView.namesThatDiffer(perSectionBefore, perSectionAfter)
        if takenBack > 0 {
            var noun: String = " unsaved exclusion changes"
            if takenBack == 1 {
                noun = " unsaved exclusion change"
            }
            ActivityTrail.note(
                .exclusionsReverted,
                "reverted " + String(takenBack) + noun + " in " + course.code
            )
        }
    }

    /// How many names are in one list and not the other, either way round.
    static func namesThatDiffer(_ first: [String], _ second: [String]) -> Int {
        var count: Int = 0
        for name in first {
            if !second.contains(name) {
                count += 1
            }
        }
        for name in second {
            if !first.contains(name) {
                count += 1
            }
        }
        return count
    }

    // MARK: - Renaming a folder

    /// Why this folder cannot take that name, or nil when it can.
    ///
    /// The names it is checked against are the ones in its OWN scope. A shared
    /// folder and a per-section folder may legitimately share a name — they
    /// live in different places on disk, and `discover_shared_items` and
    /// `discover_section_items` scan for them separately — so checking both
    /// lists would refuse a rename that is perfectly fine.
    func folderRenameProblem(
        _ oldName: String, to newName: String, scope: FolderScope, finishing: Bool = false
    ) -> String? {
        let namesInScope: [String]
        switch scope {
        case .shared:
            namesInScope = course.configuration.sharedFolders
        case .perSection:
            namesInScope = course.configuration.perSectionFolders
        }
        // `finishing` is settled once when the sheet opens, not here: it
        // touches the filesystem, and this runs on every keystroke.
        return SpecialFolderRenamer.problem(
            renaming: oldName, to: newName, existingNames: namesInScope,
            isFinishingAnInterruptedRename: finishing
        )
    }

    /// Renames the folder on disk and rewrites the configuration keys that
    /// named it, in that order.
    ///
    /// Disk first on purpose: if the move fails, nothing has been written and
    /// the course is exactly as it was. The other way round would leave a
    /// configuration naming a folder that is not there — which is the state
    /// this whole feature exists to make impossible.
    func renameFolder(_ oldName: String, to newName: String, scope: FolderScope) async -> RenameResult {
        let outcome: FolderRenameOutcome
        // OFF the main thread. The move is quick; reading every page in the
        // course to rewrite links is not, on an iCloud-backed vault where an
        // evicted file downloads on read. The configuration write below stays
        // on the main actor, because it touches the observable model.
        let courseDirectory: URL = course.directoryURL
        let sectionNumbers: [Int] = course.configuration.sectionNumbers
        do {
            outcome = try await Task.detached(priority: .userInitiated) {
                return try SpecialFolderRenamer.rename(
                    oldName, to: newName, scope: scope,
                    courseDirectory: courseDirectory,
                    sectionNumbers: sectionNumbers
                )
            }.value
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
        // The configuration is written, so the rename is whole and the record
        // of it having started can go. Anything that leaves this record behind
        // is, by definition, a rename that did not finish.
        SpecialFolderRenamer.clearRenameRecord(courseDirectory: course.directoryURL)
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
        //
        // Guarded on the LINKS as well as the folders: a page can carry a
        // qualified link into a folder no section actually has, and saying
        // "only this course's settings changed" while pages were rewritten
        // would be false. Rare, and this sentence exists to be exact.
        if outcome.foldersMoved == 0 && outcome.pagesRelinked == 0 {
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

    // MARK: - What a removal or an untick may do

    /// One walk of the course folder, and what the Marks checklist offers
    /// from it — what the page's marks questions are answered from
    /// (`MarksFloor`, issue #152). The body takes one per drawing; every
    /// one-argument protection below takes its own, which is the fresh walk
    /// a teacher's click is decided with.
    func marksSnapshot() -> MarksFloor.Snapshot {
        return MarksFloor.snapshot(
            sharedFolders: course.configuration.sharedFolders,
            perSectionFolders: course.configuration.perSectionFolders,
            courseDirectory: course.directoryURL,
            excludedShared: course.configuration.excludedItems(forScope: FolderScope.shared.exclusionKey),
            excludedPerSection: course.configuration.excludedItems(forScope: FolderScope.perSection.exclusionKey)
        )
    }

    /// What the marks floor reads from this course's settings.
    var marksSettings: MarksFloor.Settings {
        return MarksFloor.Settings(
            sharedFolders: course.configuration.sharedFolders,
            perSectionFolders: course.configuration.perSectionFolders,
            gradedFolders: course.configuration.gradedFolders,
            includesCurriculumCoverage: course.configuration.includesCurriculumCoverage
        )
    }

    /// How the floor's answer about removing `folder` is shown.
    func removalProtection(for folder: String, outcome: MarksFloor.Outcome) -> ItemProtection {
        switch outcome {
        case .refused:
            return .blocked(reason: SpecialNames.lastGradedFolderBlocked)
        case .confirmed:
            return .consequential(
                title: SpecialNames.removeGradedFolderTitle(for: folder),
                message: SpecialNames.removeGradedFolderMessage
            )
        case .ordinary:
            return .ordinary
        }
    }

    /// Asked with a FRESH walk: what a click is decided with, and what every
    /// test through `CourseSettingsGestureScript` calls. Nothing but the
    /// two-argument form with a new snapshot — if the two ever did different
    /// things, every test through the script would stay green while the page
    /// drew something else (the #183 seam; `testTheBodyDrawsTheMarksQuestionsFromOneWalk`).
    func sharedFolderProtection(for folder: String) -> ItemProtection {
        return sharedFolderProtection(for: folder, marks: marksSnapshot())
    }

    func sharedFolderProtection(for folder: String, marks: MarksFloor.Snapshot) -> ItemProtection {
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
        let outcome: MarksFloor.Outcome = MarksFloor.outcome(
            of: .remove(folder, .shared), settings: marksSettings, snapshot: marks
        )
        return removalProtection(for: folder, outcome: outcome)
    }

    /// Asked with a fresh walk — see `sharedFolderProtection(for:)`.
    func perSectionFolderProtection(for folder: String) -> ItemProtection {
        return perSectionFolderProtection(for: folder, marks: marksSnapshot())
    }

    func perSectionFolderProtection(for folder: String, marks: MarksFloor.Snapshot) -> ItemProtection {
        if course.configuration.perSectionFolders.count <= 1 {
            return .blocked(reason: SpecialNames.lastPerSectionFolderBlocked)
        }
        let outcome: MarksFloor.Outcome = MarksFloor.outcome(
            of: .remove(folder, .perSection), settings: marksSettings, snapshot: marks
        )
        if outcome == .refused {
            return .blocked(reason: SpecialNames.lastGradedFolderBlocked)
        }
        // "All Classes" — exactly that folder — is never removable (Russell,
        // 2026-08-24): the next-class button and the schedule write pages
        // into it, so a confirmation would be asking the teacher to break
        // both. Every other per-section folder can be added or removed.
        if ClassFolder.isTheAllClassesFolder(folder, configured: course.configuration.classFolder) {
            return .blocked(reason: SpecialNames.classFolderBlocked)
        }
        return removalProtection(for: folder, outcome: outcome)
    }

    func perSectionFileProtection(for file: String) -> ItemProtection {
        let normalized: String = file.lowercased()
        if normalized == "index.md" || normalized == "index" {
            return .blocked(reason: SpecialNames.sectionIndexFileBlocked)
        }
        return .ordinary
    }

    /// The Marks checklist's untick, asked with a fresh walk — see
    /// `sharedFolderProtection(for:)`.
    func gradedFolderProtection(for folder: String) -> ItemProtection {
        return gradedFolderProtection(for: folder, marks: marksSnapshot())
    }

    func gradedFolderProtection(for folder: String, marks: MarksFloor.Snapshot) -> ItemProtection {
        let outcome: MarksFloor.Outcome = MarksFloor.outcome(
            of: .untick(folder), settings: marksSettings, snapshot: marks
        )
        if outcome == .refused {
            return .blocked(reason: SpecialNames.lastGradedFolderBlocked)
        }
        return .ordinary
    }
}
