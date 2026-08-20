import SwiftUI

/// Collects the same answers the command-line setup wizard asks for, then
/// creates the course by running the real `./setup.sh` (see
/// `NewCourseCreator`). Progress streams into a console at the bottom.
struct NewCourseWizardView: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace
    @Environment(\.dismiss) var dismiss

    @State var creator = NewCourseCreator()

    @State var courseCode: String = ""
    @State var courseName: String = ""

    /// The last name this view filled in automatically. Auto-fill only
    /// ever replaces its own suggestion, never a name the teacher typed.
    @State var lastAutoFilledName: String = ""
    @State var customShortName: String = ""
    @State var locale: String = "en-US"
    @State var sectionNumbersText: String = "1"
    @State var emoji: String = "📚"
    @State var colourSchemeID: String = "quartz-standard"
    @State var showsSectionMarker: Bool = true

    /// Whether the site title leads with the grade ("Grade 12 …").
    @State var showsGradeInTitle: Bool = true

    /// Whether the new course starts with the ready-made example content
    /// written for its course code (when the app has some).
    @State var prepopulatesExampleContent: Bool = true

    /// Whether a course code with no example content starts from its
    /// subject skeleton — folders that suit the subject, a semester of
    /// class pages to rename, and placeholders saying what belongs where.
    @State var startsFromSkeleton: Bool = true

    /// Whether the example content brings the official curriculum pages
    /// along with it.
    @State var includesCurriculumPages: Bool = true
    @State var includesCurriculumCoverage: Bool = true
    @State var includesCoverageNotes: Bool = true

    /// Whether the factory structure uses LCS's own words and folders
    /// (Grove Time, SIC, College Board Curriculum) instead of the
    /// school-neutral defaults.
    @State var usesLCSTerminology: Bool = false
    @State var fontChoice: FontChoice = FontChoice.systemDefault

    /// Where this course's sections deploy: Netlify (the default),
    /// Cloudflare Pages, or a folder on this Mac for teachers who upload to
    /// their own web host.
    @State var deployTarget: String = "netlify"
    @State var deployFolderPath: String = ""

    @State var expandOnFolderClick: Bool = false
    @State var showReadingTime: Bool = false
    @State var footerHTML: String = ""

    @State var sharedFolders: [String] = WizardDefaults.sharedFolders
    @State var sharedFiles: [String] = WizardDefaults.sharedFiles
    @State var perSectionFolders: [String] = WizardDefaults.perSectionFolders
    @State var perSectionFiles: [String] = WizardDefaults.perSectionFiles

    @State var validationProblem: String?
    @State var hasStarted: Bool = false

    /// What the progress header is called — the wizard creates a course,
    /// but the same sheet also adds the example course.
    @State var progressTitle: String = "Creating your course"

    // MARK: - Initializer

    init(creator: NewCourseCreator = NewCourseCreator(), startedForTesting: Bool = false) {
        _creator = State(initialValue: creator)
        if startedForTesting {
            _hasStarted = State(initialValue: true)
        }
    }

    // MARK: - Computed properties

    /// The teacher's Cloudflare Account ID, which belongs to the person
    /// rather than to this new course — so it is read from and written
    /// straight back to app settings rather than kept as wizard state.
    var cloudflareAccountIDBinding: Binding<String> {
        return Binding(
            get: { AppSettings.shared.cloudflareAccountID },
            set: { newValue in AppSettings.shared.cloudflareAccountID = newValue }
        )
    }

    /// The parsed timetable section numbers, e.g. "1,3" → [1, 3].
    /// What is wrong with the timetable sections as typed, or nil when
    /// nothing is. Written for the mistakes people actually make, and it
    /// matters beyond politeness: the parser silently DROPS pieces it
    /// cannot read, so "1,3 5" would quietly become just section 1.
    static func sectionNumbersProblem(_ text: String) -> String? {
        let trimmed: String = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Enter at least one section number — e.g. 1, or 1,3."
        }

        var seen: [Int] = []
        for rawPart in trimmed.components(separatedBy: ",") {
            let part: String = rawPart.trimmingCharacters(in: .whitespaces)
            if part.isEmpty {
                return "There’s an empty spot between commas."
            }
            if let number = Int(part) {
                if number < 1 {
                    // Careful wording: a teacher may well teach only
                    // sections 2, 4, and 5 of a course — nothing requires
                    // the list to include 1, only that each number is one.
                    return "“\(part)” isn’t a section number — sections are 1 or higher."
                }
                if seen.contains(number) {
                    return "Section \(number) is listed more than once."
                }
                seen.append(number)
                continue
            }
            // "1 3 5": every space-separated piece is a number, so the
            // separators are what went wrong.
            var allPiecesAreNumbers: Bool = true
            for piece in part.split(separator: " ") {
                if Int(piece) == nil {
                    allPiecesAreNumbers = false
                }
            }
            if allPiecesAreNumbers && part.contains(" ") {
                return "Use commas between section numbers — e.g. \(part.split(separator: " ").joined(separator: ","))."
            }
            return "“\(part)” isn’t a section number — sections are whole numbers, like 1 or 3."
        }
        return nil
    }

    /// The problem with the sections as typed, live.
    var sectionNumbersProblem: String? {
        return NewCourseWizardView.sectionNumbersProblem(sectionNumbersText)
    }

    /// The problem with the code as typed, live.
    ///
    /// Shown under the field AND checked again at Create, so the explanation
    /// and the gate can never disagree. The rule itself lives in
    /// `CourseCodeRule` rather than here: renaming a course asks the same
    /// question, and a wizard that accepted a code renaming would refuse is
    /// a wizard that hands a teacher a course they cannot re-type.
    var courseCodeProblem: String? {
        var existingCodes: [String] = []
        for course in workspace.courses {
            existingCodes.append(course.code)
        }
        return CourseCodeRule.problem(courseCode, existingCodes: existingCodes)
    }

    /// True when the example content, not the teacher, decides the
    /// course's folders and files — the pages were written for one exact
    /// layout, and a hand-edited structure would strand their links.
    var structureComesFromExampleContent: Bool {
        return prepopulatesExampleContent
            && ExampleContentCatalog.hasContent(forCode: courseCode)
    }

    var parsedSectionNumbers: [Int] {
        var result: [Int] = []
        let parts: [String] = sectionNumbersText.components(separatedBy: ",")
        for part in parts {
            let trimmed: String = part.trimmingCharacters(in: .whitespaces)
            if let number = Int(trimmed) {
                if number > 0 && !result.contains(number) {
                    result.append(number)
                }
            }
        }
        result.sort()
        return result
    }

    var isClubCode: Bool {
        let code: String = courseCode.trimmingCharacters(in: .whitespaces)
        if code.count < 4 {
            return false
        }
        let characters: [Character] = Array(code)
        return !characters[3].isNumber
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Course or Club")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding()

            if hasStarted {
                TaskProgressView(runner: creator.runner, title: progressTitle, canCancel: false)
                Spacer(minLength: 0)
            } else {
                exampleCourseInvitation
                wizardForm
            }

            Divider()

            HStack {
                // Cancel lives bottom-left while there is something to
                // cancel; the affirmative action (Create Course / Done)
                // is always bottom-right, per macOS convention.
                if !hasStarted || creator.isCreating {
                    Button("Cancel") {
                        if creator.isCreating {
                            creator.runner.terminate()
                        }
                        workspace.reloadCourses()
                        dismiss()
                    }
                    .accessibilityIdentifier("wizardCloseButton")
                }

                Spacer()

                if let validationProblem {
                    Text(validationProblem)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                if let problem = creator.preparationProblem {
                    Text(problem)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                if !hasStarted {
                    Button("Create Course") {
                        startCreation()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("createCourseButton")
                } else {
                    // Present throughout so the footer never reflows;
                    // enabled (and the default action) once work ends.
                    Button("Close") {
                        workspace.reloadCourses()
                        // Land the teacher inside what was just made,
                        // rather than back at an empty window.
                        if let exampleCode = creator.installedExampleCode {
                            workspace.selection = SidebarSelection.section(exampleCode, 1)
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(creator.isCreating)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("wizardCloseActionButton")
                }
            }
            .padding(12)
        }
        .frame(width: 680, height: 620)
        .interactiveDismissDisabled(creator.isCreating)
    }

    var wizardForm: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Course code", text: $courseCode)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("wizardCourseCodeField")
                        .onChange(of: courseCode) {
                            autoFillCourseName()
                            adoptSkeletonStructure()
                        }
                    if let problem = courseCodeProblem {
                        // The same orange every other inline warning
                        // wears — a duplicate code is the usual reason a
                        // filled-in form still won't submit, so it must
                        // never be a mystery.
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("courseCodeWarning")
                    } else {
                        ExampleCaption("e.g. ICS3U — or a club name like CODING")
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Course name", text: $courseName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("wizardCourseNameField")
                    ExampleCaption("e.g. Introduction to Computer Science")
                }

                // For known Ontario course codes, offer the same short and
                // formal names the command-line wizard suggests — the short
                // one first, because it is the one already filled in.
                if let knownNames = CourseNameCatalog.names(forCode: courseCode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggested names for \(courseCode.trimmingCharacters(in: .whitespaces).uppercased()):")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(knownNames.short) {
                                courseName = knownNames.short
                                lastAutoFilledName = knownNames.short
                            }
                            .accessibilityIdentifier("suggestedShortNameButton")
                            Button(knownNames.formal) {
                                courseName = knownNames.formal
                                lastAutoFilledName = knownNames.formal
                            }
                            .accessibilityIdentifier("suggestedFormalNameButton")
                        }
                        .font(.callout)
                    }
                }
                if isClubCode {
                    TextField("Short label beside emoji (≤ 12 characters)", text: $customShortName)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Timetable section numbers", text: $sectionNumbersText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("wizardSectionNumbersField")
                    if let problem = sectionNumbersProblem {
                        // The same orange every other warning wears.
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("sectionNumbersWarning")
                    } else {
                        ExampleCaption("e.g. 1,3 — comma-separated")
                    }
                }
                Picker("Language / region", selection: $locale) {
                    ForEach(LocaleCatalog.codes, id: \.self) { code in
                        Text(LocaleCatalog.displayName(forCode: code)).tag(code)
                    }
                }
            } header: {
                FormSectionHeader("Basics")
            }

            Section {
                if ExampleContentCatalog.hasContent(forCode: courseCode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Pre-populate course with example content", isOn: $prepopulatesExampleContent)
                            .accessibilityIdentifier("prepopulateToggle")
                        ExampleCaption("Working pages written for this course — keep, edit, or delete them as you build your own site. The example content also chooses the course's folders and files, so they fit the pages.")
                    }
                    if ExampleContentCatalog.includesCurriculum(forCode: courseCode) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Include \(ExampleContentCatalog.jurisdictionName(forCode: courseCode)) curriculum pages", isOn: $includesCurriculumPages)
                                .disabled(!prepopulatesExampleContent)
                                .accessibilityIdentifier("curriculumToggle")
                            ExampleCaption("Every expectation as its own page, so lessons and tasks can link to exactly what they address")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            // The map reads the site's links to the
                            // curriculum pages, so it cannot exist without
                            // them — but keeping the pages and declining
                            // the map is a perfectly reasonable choice.
                            Toggle("Include the curriculum coverage map", isOn: $includesCurriculumCoverage)
                                .disabled(!prepopulatesExampleContent || !includesCurriculumPages)
                                .accessibilityIdentifier("curriculumCoverageToggle")
                            ExampleCaption("A page showing every expectation coloured by how many pages address it — red in September, greener as the year goes on. Linked from Key Links, and kept out of the sidebar.")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            // The sections sit on the coverage page, so they
                            // cannot exist without it.
                            Toggle("Explain the map on the page", isOn: $includesCoverageNotes)
                                .disabled(!prepopulatesExampleContent
                                          || !includesCurriculumPages
                                          || !includesCurriculumCoverage)
                                .accessibilityIdentifier("coverageNotesToggle")
                            ExampleCaption("Two short sections at the foot of the map: what counts as addressing an expectation, and how to read it honestly — red in September is normal, red in May is not. Turn this off to publish the map on its own.")
                        }
                    }
                } else if let skeleton = SkeletonCatalog.family(forCode: courseCode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Start from a \(skeleton.label.lowercased()) skeleton", isOn: $startsFromSkeleton)
                            .accessibilityIdentifier("skeletonToggle")
                        ExampleCaption("There is no ready-made course for this code, but there is a starting point shaped for the subject: folders that suit it, four units of class pages to rename, a page explaining what the site can do, and placeholders saying what belongs where.")
                    }
                } else {
                    Text("Example content isn’t available for this course code yet, so the course will start with empty folders ready for your own pages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("noExampleContentNote")
                }
            } header: {
                FormSectionHeader("Starting Content")
            }

            Section {
                EmojiChoiceField(label: "Header emoji", emoji: $emoji)
                ColourSchemePickerView(selectedSchemeID: $colourSchemeID)
                // The sample follows the fields live and shows the
                // landing title as the build will compute it — type
                // "Drama" above with the grade and marker switches on
                // and the header previews "Grade 9 Drama, Section 1".
                FontChoiceEditorView(
                    choice: $fontChoice,
                    sampleHeadline: courseName.trimmingCharacters(in: .whitespaces).isEmpty
                        ? ""
                        : CourseConfiguration.landingTitle(
                            courseName: courseName,
                            courseCode: courseCode.trimmingCharacters(in: .whitespaces).uppercased(),
                            showsGrade: showsGradeInTitle,
                            showsSectionMarker: showsSectionMarker,
                            sectionNumber: parsedSectionNumbers.first ?? 1
                        )
                )
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show section marker in the site title", isOn: $showsSectionMarker)
                    ExampleCaption("e.g. “S1” appears beside the course code")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show the grade in the site title", isOn: $showsGradeInTitle)
                    if let warning = CourseConfiguration.gradeInTitleWarning(
                        courseName: courseName,
                        courseCode: courseCode.trimmingCharacters(in: .whitespaces).uppercased(),
                        showsGrade: showsGradeInTitle
                    ) {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("wizardGradeInTitleWarning")
                    } else {
                        ExampleCaption("e.g. “Grade 12” before the course name")
                    }
                }
            } header: {
                FormSectionHeader("Appearance", caption: "Applied to every section — fine-tune later in Settings")
            }

            Section {
                Picker("Sidebar folders expand when clicking", selection: $expandOnFolderClick) {
                    Text("Chevron or folder name").tag(true)
                    Text("Chevron only (name opens the folder)").tag(false)
                }
                Toggle("Show page read-time estimates to students", isOn: $showReadingTime)
            } header: {
                FormSectionHeader("Behaviour")
            }

            Section {
                PublishingChoiceView(
                    deployTarget: $deployTarget,
                    deployFolderPath: $deployFolderPath,
                    cloudflareAccountID: cloudflareAccountIDBinding
                )
            } header: {
                FormSectionHeader("Deploying", caption: "Netlify is the usual choice — change any time in Settings")
            }

            Section {
                if structureComesFromExampleContent {
                    Text("The example content chooses the folders and files for this course, so every page lands where its links expect it. Turn off pre-populating to choose your own structure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("structureFromExampleNote")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Use LCS-specific terminology", isOn: $usesLCSTerminology)
                            .accessibilityIdentifier("lcsTerminologyToggle")
                        ExampleCaption("e.g. “Grove Time” instead of “Extra Help”, plus the College Board Curriculum folder")
                    }
                    .onChange(of: usesLCSTerminology) { wasLCS, isLCS in
                        sharedFolders = WizardDefaults.switchingFactoryItems(
                            in: sharedFolders,
                            toFactory: isLCS ? WizardDefaults.lcsSharedFolders : WizardDefaults.sharedFolders,
                            fromFactory: wasLCS ? WizardDefaults.lcsSharedFolders : WizardDefaults.sharedFolders
                        )
                        sharedFiles = WizardDefaults.switchingFactoryItems(
                            in: sharedFiles,
                            toFactory: isLCS ? WizardDefaults.lcsSharedFiles : WizardDefaults.sharedFiles,
                            fromFactory: wasLCS ? WizardDefaults.lcsSharedFiles : WizardDefaults.sharedFiles
                        )
                    }

                    // The lists are long, so they stay collapsed until needed.
                    DisclosureGroup("Folders and files") {
                        StringListEditorView(title: "Shared folders", items: $sharedFolders)
                        StringListEditorView(title: "Shared files", hidesMarkdownExtension: true, items: $sharedFiles)
                        StringListEditorView(title: "Per-section folders", items: $perSectionFolders)
                        StringListEditorView(title: "Per-section files", hidesMarkdownExtension: true, items: $perSectionFiles)
                    }
                    .accessibilityIdentifier("structureDisclosure")
                }
            } header: {
                if structureComesFromExampleContent {
                    FormSectionHeader("Structure", caption: "Chosen by the example content")
                } else {
                    FormSectionHeader("Structure", caption: "Defaults are fine for most courses")
                }
            }

            Section {
                FooterEditorView(footerHTML: $footerHTML)
            } header: {
                FormSectionHeader("Footer")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Functions

    /// When a course code with no example content is entered, offer the
    /// folders its SUBJECT wants rather than the school-neutral factory
    /// list — a music course opens with Repertoire and Warm-Ups, a
    /// chemistry course with Investigations and Safety in the Lab. The
    /// lists stay editable; a list the teacher has already changed is left
    /// alone (see `SkeletonCatalog.structureToAdopt`).
    func adoptSkeletonStructure() {
        guard let skeleton = SkeletonCatalog.structureToAdopt(
            forCode: courseCode, currentSharedFolders: sharedFolders
        ) else {
            return
        }
        sharedFolders = skeleton.sharedFolders
        sharedFiles = skeleton.sharedFiles
        perSectionFolders = skeleton.perSectionFolders
        perSectionFiles = skeleton.perSectionFiles
    }

    /// When a known course code is entered, pre-fill the name with the
    /// SHORT name — but only if the name field is empty or still holds a
    /// previous auto-fill, so a teacher's own typing is never replaced.
    /// Why the short name rather than the formal one is explained on
    /// `CourseNameCatalog.defaultName(forCode:)`.
    func autoFillCourseName() {
        guard let suggestedName = CourseNameCatalog.defaultName(forCode: courseCode) else {
            return
        }
        let mayReplace: Bool = courseName.isEmpty || courseName == lastAutoFilledName
        if mayReplace {
            courseName = suggestedName
            lastAutoFilledName = suggestedName
        }
    }

    /// Offered above the form: someone who has never built a course learns
    /// far more from opening a finished one than from an empty form.
    var exampleCourseInvitation: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("New to this?")
                    .font(.headline)
                Text("Add a complete example course — a real Grade 9 science course you can explore, change, and remove whenever you like.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Add Example Course") {
                startExampleInstall()
            }
            .accessibilityIdentifier("addExampleCourseButton")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    // MARK: - Functions

    /// Adds the example course. Nothing else on this form is needed for it.
    func startExampleInstall() {
        validationProblem = nil
        guard let workspaceURL = workspace.workspaceURL else {
            validationProblem = "Choose a working folder first."
            return
        }
        progressTitle = "Adding the example course"
        hasStarted = true
        creator.installExampleCourse(workspaceURL: workspaceURL)
    }

    func startCreation() {
        validationProblem = nil

        let code: String = courseCode.trimmingCharacters(in: .whitespaces).uppercased()
        if code.isEmpty {
            validationProblem = "Enter a course code."
            return
        }
        // The same check the live warning under the field uses.
        if let problem = courseCodeProblem {
            validationProblem = problem
            return
        }
        if let problem = NewCourseWizardView.sectionNumbersProblem(sectionNumbersText) {
            validationProblem = problem
            return
        }
        guard let workspaceURL = workspace.workspaceURL else {
            validationProblem = "No working folder is selected."
            return
        }
        if deployTarget == "local_folder" {
            if let problem = CourseConfiguration.deployFolderProblem(forPath: deployFolderPath) {
                validationProblem = problem
                return
            }
        }
        if deployTarget == "cloudflare_pages" {
            if let problem = CourseConfiguration.cloudflareAccountProblem(forID: AppSettings.shared.cloudflareAccountID) {
                validationProblem = problem
                return
            }
        }

        var name: String = courseName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            name = "Course Website"
        }

        hasStarted = true
        creator.createCourse(
            configuration: buildConfigurationDictionary(code: code, name: name),
            workspaceURL: workspaceURL
        )
    }

    /// Assembles the same JSON shape the setup wizard saves, which the
    /// wizard then re-reads as its defaults when the app runs it.
    func buildConfigurationDictionary(code: String, name: String) -> [String: Any] {
        let sectionNumbers: [Int] = parsedSectionNumbers

        var emojiMap: [String: String] = [:]
        var markerMap: [String: Bool] = [:]
        var gradeMap: [String: Bool] = [:]
        var schemeMap: [String: String] = [:]
        var fontsSectionsMap: [String: Any] = [:]
        for sectionNumber in sectionNumbers {
            let key: String = "section\(sectionNumber)"
            emojiMap[key] = emoji
            markerMap[key] = showsSectionMarker
            gradeMap[key] = showsGradeInTitle
            schemeMap[key] = colourSchemeID
            fontsSectionsMap[key] = fontChoice.dictionaryRepresentation
        }

        // The structure written to disk is the one the skeleton chose,
        // whether or not the code field's onChange has run — a config that
        // disagreed with the pages about to be installed would leave empty
        // folders beside them.
        var chosenSharedFolders: [String] = sharedFolders
        var chosenSharedFiles: [String] = sharedFiles
        var chosenPerSectionFolders: [String] = perSectionFolders
        var chosenPerSectionFiles: [String] = perSectionFiles
        var skeleton: SkeletonCatalog.Family? = nil
        if startsFromSkeleton && SkeletonCatalog.hasSkeleton(forCode: code) {
            skeleton = SkeletonCatalog.family(forCode: code)
            if let adopted = SkeletonCatalog.structureToAdopt(
                forCode: code, currentSharedFolders: sharedFolders
            ) {
                chosenSharedFolders = adopted.sharedFolders
                chosenSharedFiles = adopted.sharedFiles
                chosenPerSectionFolders = adopted.perSectionFolders
                chosenPerSectionFiles = adopted.perSectionFiles
            }
        }

        var hiddenItems: [String] = []
        var expandableItems: [String] = []
        if let skeleton {
            // The skeleton decides its own sidebar, whatever the teacher
            // has since done to the folder list.
            let plan = SkeletonCatalog.sidebar(
                for: skeleton,
                sharedFolders: chosenSharedFolders,
                sharedFiles: chosenSharedFiles,
                perSectionFolders: chosenPerSectionFolders,
                perSectionFiles: chosenPerSectionFiles
            )
            hiddenItems = plan.hidden
            expandableItems = plan.expandable
        } else {
            for item in WizardDefaults.hiddenItems {
                let isKnown: Bool = chosenSharedFolders.contains(item)
                    || chosenSharedFiles.contains(item)
                    || chosenPerSectionFolders.contains(item)
                    || chosenPerSectionFiles.contains(item)
                    || item == "Media"
                if isKnown {
                    hiddenItems.append(item)
                }
            }
            for item in WizardDefaults.expandableItems {
                if chosenSharedFolders.contains(item) || chosenPerSectionFolders.contains(item) {
                    expandableItems.append(item)
                }
            }
        }

        return [
            "course_code": code,
            "course_name": name,
            "custom_short_name": isClubCode ? customShortName.trimmingCharacters(in: .whitespaces) : "",
            "locale": locale,
            "emojis": ["sections": emojiMap],
            "num_sections": sectionNumbers.count,
            "section_numbers": sectionNumbers,
            "shared_folders": chosenSharedFolders,
            "shared_files": chosenSharedFiles,
            "per_section_folders": chosenPerSectionFolders,
            "per_section_files": chosenPerSectionFiles,
            "hidden": hiddenItems,
            "expandable": expandableItems,
            "expandOnFolderClick": expandOnFolderClick,
            "footer_html": footerHTML,
            "show_reading_time": showReadingTime,
            "show_grade_in_title": ["sections": gradeMap],
            // The real wizard reads these as its defaults, exactly like
            // every other answer here. False when no content exists for
            // the code, so a stale true can never mean anything.
            "use_skeleton": SkeletonCatalog.hasSkeleton(forCode: code) && startsFromSkeleton,
            "prepopulate_example_content": ExampleContentCatalog.hasContent(forCode: code)
                && prepopulatesExampleContent,
            "include_curriculum_pages": ExampleContentCatalog.hasContent(forCode: code)
                && prepopulatesExampleContent
                && ExampleContentCatalog.includesCurriculum(forCode: code)
                && includesCurriculumPages,
            // Depends on the curriculum pages: without them the map has
            // nothing to colour, so it is forced off here as well as
            // disabled in the interface.
            "include_curriculum_coverage": CourseConfiguration.curriculumCoverageEnabled(
                codeHasExampleContent: ExampleContentCatalog.hasContent(forCode: code),
                prepopulatesExampleContent: prepopulatesExampleContent,
                payloadIncludesCurriculum: ExampleContentCatalog.includesCurriculum(forCode: code),
                includesCurriculumPages: includesCurriculumPages,
                includesCurriculumCoverage: includesCurriculumCoverage
            ),
            "include_coverage_notes": CourseConfiguration.coverageNotesEnabled(
                curriculumCoverageEnabled: CourseConfiguration.curriculumCoverageEnabled(
                    codeHasExampleContent: ExampleContentCatalog.hasContent(forCode: code),
                    prepopulatesExampleContent: prepopulatesExampleContent,
                    payloadIncludesCurriculum: ExampleContentCatalog.includesCurriculum(forCode: code),
                    includesCurriculumPages: includesCurriculumPages,
                    includesCurriculumCoverage: includesCurriculumCoverage
                ),
                includesCoverageNotes: includesCoverageNotes
            ),
            "use_lcs_terminology": usesLCSTerminology,
            "deploy_target": deployTarget,
            "deploy_folder_path": deployTarget == "local_folder"
                ? deployFolderPath.trimmingCharacters(in: .whitespaces)
                : "",
            "fonts": [
                "default": fontChoice.dictionaryRepresentation,
                "sections": fontsSectionsMap,
            ],
            "show_section_marker": ["sections": markerMap],
            "color_schemes": schemeMap,
        ]
    }
}
