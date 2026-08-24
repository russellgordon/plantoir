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

    /// The province the course-code picker is currently browsing —
    /// narrows its suggestion list, never gates typing a code straight
    /// through. Defaults to Ontario, the more common case, so nothing is
    /// disabled before a teacher has touched the form.
    @State var province: String = "ON"

    /// The course-code field's own focus state, published up by
    /// `CourseCodePickerView`. The field's on-screen position is read
    /// separately, via an anchor preference resolved at the top of
    /// `body` — see `CourseCodeFieldAnchorKey`. The popup stays open for
    /// as long as this is true — including once the typed text is
    /// already an exact code. An earlier version closed the popup the
    /// instant the text matched exactly, which Russell found
    /// disorienting in practice: finish typing "ICS3U" and the whole
    /// list vanishes, right when a teacher would expect to SEE the row
    /// they just typed confirming it's the right one (2026-08-22). It
    /// closes only when the field loses focus — a selection sets this to
    /// false itself (see `selectCourseCodeSuggestion`), and clicking
    /// elsewhere does the same the ordinary way SwiftUI focus works.
    @State var courseCodeFieldIsFocused: Bool = false

    /// True once Escape has closed the popup without moving focus out of
    /// the field — reset the moment the code changes (typing should
    /// reopen it) or the field regains focus. Kept separate from
    /// `courseCodeFieldIsFocused` because Escape should NOT blur the
    /// field, only hide the list — a teacher can keep typing right after,
    /// same as dismissing a native combo box's popup. Also what makes
    /// Escape here NOT fall through to dismissing the whole wizard sheet
    /// — see the `.onKeyPress(.escape)` on `CourseCodePickerView`'s field
    /// (Russell, 2026-08-22).
    @State var courseCodeSuggestionsManuallyDismissed: Bool = false

    /// Which suggestion the arrow keys are sitting on, or `nil` when the
    /// teacher has not walked the list — the state behind Russell's
    /// 2026-08-23 ask that up/down/Return work here the way they do in a
    /// real `NSComboBox`. Held as a CODE rather than an index because
    /// the list re-filters on every keystroke: an index would silently
    /// come to mean a different course, while a code that is no longer
    /// in the list resolves to no highlight at all, which is the honest
    /// answer.
    @State var highlightedCourseCode: String?

    /// Focus for the two plain fields, so `WizardFieldChrome` can draw
    /// their accent ring — a `ViewModifier` can't own focus for the view
    /// it decorates, so it has to be told.
    @FocusState var courseNameFieldHasFocus: Bool
    @FocusState var sectionNumbersFieldHasFocus: Bool
    @FocusState var customShortNameFieldHasFocus: Bool

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

    /// Extra destinations this course ALSO publishes to, beyond
    /// `deployTarget` — see `CourseConfiguration.additionalDeployTargets`.
    @State var additionalDeployTargets: [CourseConfiguration.AdditionalDeployTarget] = []

    @State var expandOnFolderClick: Bool = false
    @State var showReadingTime: Bool = false
    @State var footerHTML: String = ""

    @State var sharedFolders: [String] = WizardDefaults.sharedFolders
    @State var sharedFiles: [String] = WizardDefaults.sharedFiles
    @State var perSectionFolders: [String] = WizardDefaults.perSectionFolders
    @State var perSectionFiles: [String] = WizardDefaults.perSectionFiles
    @State var gradedFolders: [String] = ["Tasks"]

    @State var validationProblem: String?
    @State var hasStarted: Bool = false

    /// What the progress header is called — the wizard creates a course,
    /// but the same sheet also adds the example course.
    @State var progressTitle: String = "Creating your course"

    init(
        creator: NewCourseCreator = NewCourseCreator(),
        startedForTesting: Bool = false,
        courseCode: String = "",
        prepopulatesExampleContent: Bool = true,
        startsFromSkeleton: Bool = true,
        includesCurriculumPages: Bool = true,
        includesCurriculumCoverage: Bool = true,
        sharedFolders: [String] = WizardDefaults.sharedFolders,
        sharedFiles: [String] = WizardDefaults.sharedFiles,
        perSectionFolders: [String] = WizardDefaults.perSectionFolders,
        perSectionFiles: [String] = WizardDefaults.perSectionFiles,
        gradedFolders: [String] = ["Tasks"]
    ) {
        _creator = State(initialValue: creator)
        if startedForTesting {
            _hasStarted = State(initialValue: true)
        }
        _courseCode = State(initialValue: courseCode)
        _prepopulatesExampleContent = State(initialValue: prepopulatesExampleContent)
        _startsFromSkeleton = State(initialValue: startsFromSkeleton)
        _includesCurriculumPages = State(initialValue: includesCurriculumPages)
        _includesCurriculumCoverage = State(initialValue: includesCurriculumCoverage)
        _sharedFolders = State(initialValue: sharedFolders)
        _sharedFiles = State(initialValue: sharedFiles)
        _perSectionFolders = State(initialValue: perSectionFolders)
        _perSectionFiles = State(initialValue: perSectionFiles)
        _gradedFolders = State(initialValue: gradedFolders)
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

    /// Whether a specific course — or club — has been identified. Nothing
    /// else in the form means anything before this: the name, the
    /// timetable, the appearance, even the folder structure all take
    /// their defaults from the code, so every other field and section
    /// stays disabled until it is true. True the moment the code field
    /// holds anything at all, typed by hand or chosen from its
    /// suggestions — a club code with no catalog entry counts too.
    var hasChosenCourse: Bool {
        return !courseCode.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// How many rows the popup offers at once when searching — an empty
    /// query instead browses the WHOLE province catalog (`Int.max`,
    /// effectively uncapped), since the popup scrolls a long list fine.
    static let courseCodeSearchResultLimit: Int = 40

    var courseCodeSuggestions: [CourseCatalogEntry] {
        let trimmed: String = courseCode.trimmingCharacters(in: .whitespaces)
        let limit: Int = trimmed.isEmpty ? Int.max : NewCourseWizardView.courseCodeSearchResultLimit
        return CourseCatalog.matching(courseCode, inProvince: province, limit: limit)
    }

    var courseCodeSuggestionIDs: [String] {
        var result: [String] = []
        for suggestion in courseCodeSuggestions {
            result.append(suggestion.id)
        }
        return result
    }

    /// Whether the suggestion popup is on screen right now. One place
    /// rather than three: the overlay draws on it, its animation keys
    /// off it, and the chevron button TOGGLES on it — and a toggle that
    /// disagreed with what is drawn would need pressing twice.
    var courseCodeSuggestionsAreShown: Bool {
        !hasStarted && courseCodeFieldIsFocused && !courseCodeSuggestionsManuallyDismissed
    }

    /// The highlighted entry, resolved against the CURRENT list — `nil`
    /// if the highlight's code has been filtered away by further typing.
    var highlightedCourseCodeEntry: CourseCatalogEntry? {
        guard let highlightedCourseCode else {
            return nil
        }
        for entry in courseCodeSuggestions where entry.code == highlightedCourseCode {
            return entry
        }
        return nil
    }

    /// Whether this code names a club rather than a course — which is what
    /// puts the "Short label" field on screen and what decides whether
    /// `custom_short_name` is written into `course_config.json`. The rule
    /// itself lives in `ClubCodeRule`, and is a contract case, because
    /// Windows asks the same question and had the same bug.
    var isClubCode: Bool {
        return ClubCodeRule.isClub(courseCode)
    }

    var gradedFolderChoices: [String] {
        var choices: [String] = []
        for folder in sharedFolders {
            if !choices.contains(folder) {
                choices.append(folder)
            }
        }
        for folder in perSectionFolders {
            if !choices.contains(folder) {
                choices.append(folder)
            }
        }
        return choices
    }

    var gradedFoldersBinding: Binding<[String]> {
        return Binding(
            get: {
                return gradedFolders
            },
            set: { newValue in
                gradedFolders = newValue
            }
        )
    }

    var effectiveCurriculumPagesEnabled: Bool {
        return ExampleContentCatalog.hasContent(forCode: courseCode)
            && prepopulatesExampleContent
            && ExampleContentCatalog.includesCurriculum(forCode: courseCode)
            && includesCurriculumPages
    }

    var effectiveCurriculumCoverageEnabled: Bool {
        return CourseConfiguration.curriculumCoverageEnabled(
            codeHasExampleContent: ExampleContentCatalog.hasContent(forCode: courseCode),
            prepopulatesExampleContent: prepopulatesExampleContent,
            payloadIncludesCurriculum: ExampleContentCatalog.includesCurriculum(forCode: courseCode),
            includesCurriculumPages: includesCurriculumPages,
            includesCurriculumCoverage: includesCurriculumCoverage
        )
    }

    var wizardResolvedCurriculumFolder: String? {
        let declared: String? = ExampleContentCatalog.curriculumFolder(forCode: courseCode)
            ?? SkeletonCatalog.family(forCode: courseCode)?.curriculumFolder
        return CurriculumFolderRule.resolvedCurriculumFolder(configured: declared, in: sharedFolders)
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

    // MARK: - Body

    var body: some View {
        wizardContent
            .frame(width: 680, height: 620)
            // Resolves the anchor `CourseCodePickerView` published for the
            // code field into an actual rect via THIS outer
            // `GeometryReader`'s proxy, then draws the popup as a sibling
            // layer over the whole sheet — floating over the form rather
            // than living inside it. See the note on
            // `CourseCodeFieldAnchorKey` for why an anchor, not a
            // `GeometryReader`-computed `CGRect` preference straight from
            // the field: the field sits inside a `Form`'s `Section`,
            // which the anchor approach reads through reliably and the
            // plain preference approach (tried first, same day) did not.
            .onChange(of: courseCodeFieldIsFocused) { _, isFocused in
                if isFocused {
                    // Regaining focus always reopens the popup, even if
                    // Escape most recently closed it.
                    courseCodeSuggestionsManuallyDismissed = false
                }
            }
            .onChange(of: courseCode) {
                // Typing invalidates an Escape-driven dismissal — a
                // teacher who closed the popup and kept typing should
                // see it reopen against what they're typing now.
                courseCodeSuggestionsManuallyDismissed = false
                // …and starts the walk over. Keeping a highlight across
                // a re-filter would leave it pointing at a row that has
                // moved or gone, so Return would take something the
                // teacher never looked at.
                highlightedCourseCode = nil
            }
            .overlayPreferenceValue(CourseCodeFieldAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    if courseCodeSuggestionsAreShown, let anchor {
                        CourseCodeSuggestionsOverlay(
                            fieldFrame: proxy[anchor],
                            province: province,
                            entries: courseCodeSuggestions,
                            onSelect: selectCourseCodeSuggestion,
                            highlightedID: highlightedCourseCodeEntry?.id
                        )
                        // A quick fade + a short drop from the field,
                        // rather than snapping into place — the same
                        // motion a native popup's own appear animation
                        // uses, just gentler than its default speed.
                        .transition(
                            .opacity.combined(with: .offset(y: -6))
                        )
                    }
                }
                // Two things drive this animation: the popup appearing or
                // disappearing, and its ROWS changing as typing narrows
                // the list — both should move gently rather than snap,
                // so both are folded into one comparable value rather
                // than the boolean alone.
                .animation(
                    .easeOut(duration: 0.12),
                    value: CourseCodeSuggestionsAnimationKey(
                        isShown: courseCodeSuggestionsAreShown,
                        rowIDs: courseCodeSuggestionIDs
                    )
                )
            }
            .interactiveDismissDisabled(creator.isCreating)
    }

    var wizardContent: some View {
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
    }

    var wizardForm: some View {
        Form {
            Section {
                // Its own `Form` row, a sibling of the course-code row
                // below rather than bundled into the same one — a bare
                // `Picker` used as a row's whole content already gets
                // `Form`'s native side-by-side "label left, control
                // right" treatment (this looks unchanged from before),
                // and splitting it out is what lets `Form` give the
                // course-code row BELOW its own native styling too,
                // including the `Divider` between the two rows that
                // every other pair of rows in this dialog already has
                // (Russell, 2026-08-23: "There should also be a divider
                // between Province and Course Code, following the
                // example set by the rest of this dialog").
                Picker("Province", selection: $province) {
                    Text("Ontario").tag("ON")
                    Text("British Columbia").tag("BC")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("wizardProvincePicker")

                VStack(alignment: .leading, spacing: 4) {
                    // An EXPLICIT `LabeledContent`, not `Form`'s own
                    // automatic labelling. `Form` only extracts a row
                    // label from a bare `TextField(title:, text:)` used
                    // as the row's content; `CourseCodePickerView` is a
                    // view of ours, so `Form` had nothing to extract and
                    // "Course code" stayed INSIDE the field as
                    // placeholder text, unlike every other row here
                    // (Russell, 2026-08-23, comparing it to Course
                    // name). Writing the label ourselves puts it in the
                    // same leading column as Course name's, and hands
                    // the field the trailing column at the same width.
                    LabeledContent("Course code") {
                        CourseCodePickerView(
                            courseCode: $courseCode,
                            isFocused: $courseCodeFieldIsFocused,
                            onEscape: {
                                courseCodeSuggestionsManuallyDismissed = true
                                highlightedCourseCode = nil
                            },
                            // A TOGGLE, not an open: pressing a real
                            // combo box's arrow a second time puts the
                            // popup away again (Russell, 2026-08-23).
                            onRevealRequested: {
                                courseCodeSuggestionsManuallyDismissed = courseCodeSuggestionsAreShown
                                if courseCodeSuggestionsManuallyDismissed {
                                    highlightedCourseCode = nil
                                }
                            },
                            onMoveHighlight: moveCourseCodeHighlight,
                            onCommitHighlight: commitCourseCodeHighlight
                        )
                        .onChange(of: courseCode) {
                            autoFillCourseName()
                            adoptSkeletonStructure()
                        }
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
                        ExampleCaption("Type a code, or type what the course is called — e.g. “chem” finds SCH3U. Or type a club name like CODING.")
                    }
                }
                .padding(.bottom, 8)
                // Nothing below here means anything until a course (or
                // club) has actually been identified — see
                // `hasChosenCourse`.
                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        // The label is written out here rather than
                        // passed as the `TextField`'s own title, and
                        // that is what makes the typed text read
                        // LEADING. A title `Form` extracts for itself
                        // turns the row into a label/VALUE pair, and a
                        // value is trailing-aligned — Russell saw
                        // Timetable section numbers' "1" sitting
                        // against the field's right edge (2026-08-23),
                        // and `.multilineTextAlignment(.leading)` alone
                        // did NOT override it. Given an explicit
                        // `LabeledContent` the field is ordinary
                        // content again, and its text starts at the
                        // leading edge like any other text field's.
                        LabeledContent("Course name") {
                            // `WizardFieldChrome`, not
                            // `.roundedBorder`: every AppKit control
                            // this stands in for is 24pt tall and
                            // SwiftUI's own bezel is 26, which left
                            // this row 2pt out from the course-code
                            // field beside it (Russell, 2026-08-23).
                            // `.frame(height:)` does not fix that — see
                            // the note on `WizardFieldChrome`.
                            TextField("", text: $courseName)
                                .focused($courseNameFieldHasFocus)
                                .accessibilityIdentifier("wizardCourseNameField")
                                .modifier(WizardFieldChrome(
                                    isFocused: courseNameFieldHasFocus,
                                    trailingInset: CourseCodePickerView.textLeadingInset
                                ))
                        }
                        ExampleCaption("e.g. Chemistry")
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
                    // The same shape as Course Name and Timetable Section
                    // Numbers: an explicit `LabeledContent` so the label
                    // sits in the leading column and the typed text reads
                    // leading, plus `WizardFieldChrome` so the box is the
                    // same 24pt. It had neither — its label was still
                    // placeholder text inside the field and its value was
                    // pushed to the trailing edge, which is exactly the
                    // pre-`LabeledContent` look every other row was moved
                    // off (Russell, 2026-08-23, spotting the odd one out).
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Short label") {
                            TextField("", text: $customShortName)
                                .focused($customShortNameFieldHasFocus)
                                .accessibilityIdentifier("wizardCustomShortNameField")
                                .modifier(WizardFieldChrome(
                                    isFocused: customShortNameFieldHasFocus,
                                    trailingInset: CourseCodePickerView.textLeadingInset
                                ))
                        }
                        ExampleCaption("Shown beside the emoji — 12 characters at most")
                    }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        // See the note beside Course Name's own
                        // `LabeledContent` for why the label is written
                        // out rather than passed as the field's title.
                        LabeledContent("Timetable section numbers") {
                            // See Course Name's own note.
                            TextField("", text: $sectionNumbersText)
                                .focused($sectionNumbersFieldHasFocus)
                                .accessibilityIdentifier("wizardSectionNumbersField")
                                .modifier(WizardFieldChrome(
                                    isFocused: sectionNumbersFieldHasFocus,
                                    trailingInset: CourseCodePickerView.textLeadingInset
                                ))
                        }
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
                }
                .disabled(!hasChosenCourse)
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
            .disabled(!hasChosenCourse)

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
            .disabled(!hasChosenCourse)

            Section {
                Picker("Sidebar folders expand when clicking", selection: $expandOnFolderClick) {
                    Text("Chevron or folder name").tag(true)
                    Text("Chevron only (name opens the folder)").tag(false)
                }
                Toggle("Show page read-time estimates to students", isOn: $showReadingTime)
            } header: {
                FormSectionHeader("Behaviour")
            }
            .disabled(!hasChosenCourse)

            Section {
                PublishingChoiceView(
                    deployTarget: $deployTarget,
                    deployFolderPath: $deployFolderPath,
                    cloudflareAccountID: cloudflareAccountIDBinding,
                    additionalDeployTargets: $additionalDeployTargets
                )
            } header: {
                FormSectionHeader("Deploying", caption: "Netlify is the usual choice — change any time in Settings")
            }
            .disabled(!hasChosenCourse)

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
                        StringListEditorView(
                            title: "Shared folders",
                            items: $sharedFolders,
                            onRemove: { _ in reconcileGradedFolders() },
                            protection: wizardSharedFolderProtection
                        )
                        StringListEditorView(
                            title: "Shared files",
                            hidesMarkdownExtension: true,
                            items: $sharedFiles
                        )
                        StringListEditorView(
                            title: "Per-section folders",
                            items: $perSectionFolders,
                            onRemove: { _ in reconcileGradedFolders() },
                            protection: wizardPerSectionFolderProtection
                        )
                        StringListEditorView(
                            title: "Per-section files",
                            hidesMarkdownExtension: true,
                            items: $perSectionFiles,
                            protection: wizardPerSectionFileProtection
                        )
                    }
                    .accessibilityIdentifier("structureDisclosure")

                    VStack(alignment: .leading, spacing: 6) {
                        MembershipToggleListView(
                            title: "Folders whose work counts for marks",
                            allItems: gradedFolderChoices,
                            members: gradedFoldersBinding,
                            protection: wizardGradedFolderProtection
                        )
                        Text("The curriculum map uses this to show which expectations you have actually evaluated. Most courses keep “Tasks”; add “Tests” or anything else you mark, and remove what you don’t.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            } header: {
                if structureComesFromExampleContent {
                    FormSectionHeader("Structure", caption: "Chosen by the example content")
                } else {
                    FormSectionHeader("Structure", caption: "Defaults are fine for most courses")
                }
            }
            .disabled(!hasChosenCourse)

            Section {
                FooterEditorView(footerHTML: $footerHTML)
            } header: {
                FormSectionHeader("Footer")
            }
            .disabled(!hasChosenCourse)

            // Settings a teacher rarely needs to touch, tucked behind a
            // disclosure triangle at the very end rather than competing
            // with the ones almost everyone sets.
            Section {
                DisclosureGroup("Advanced") {
                    Picker("Language / region", selection: $locale) {
                        ForEach(LocaleCatalog.codes, id: \.self) { code in
                            Text(LocaleCatalog.displayName(forCode: code)).tag(code)
                        }
                    }
                    .padding(.top, 4)
                }
                .accessibilityIdentifier("advancedDisclosure")
            }
            .disabled(!hasChosenCourse)
        }
        .formStyle(.grouped)
    }

    // MARK: - Functions

    /// A row picked from `CourseCodeSuggestionsOverlay` — sets the code
    /// exactly like finishing typing one by hand, then drops focus so
    /// the popup closes.
    func selectCourseCodeSuggestion(_ entry: CourseCatalogEntry) {
        courseCode = entry.code
        courseCodeFieldIsFocused = false
        highlightedCourseCode = nil
    }

    /// Up or down pressed in the field: walks the popup's rows the way a
    /// real `NSComboBox` does. Returns whether the key was used, so the
    /// arrows keep moving the insertion point whenever there is no list
    /// to walk.
    ///
    /// Pressing down with the popup CLOSED opens it and takes the first
    /// row, which is what a combo box does and what makes the keyboard a
    /// complete path — otherwise a teacher who dismissed the list with
    /// Escape would have to reach for the mouse to get it back.
    func moveCourseCodeHighlight(by step: Int) -> Bool {
        let entries: [CourseCatalogEntry] = courseCodeSuggestions
        if entries.isEmpty {
            return false
        }
        if !courseCodeSuggestionsAreShown {
            if step < 0 {
                return false
            }
            courseCodeSuggestionsManuallyDismissed = false
            highlightedCourseCode = entries[0].code
            return true
        }

        var currentIndex: Int = -1
        for index in entries.indices where entries[index].code == highlightedCourseCode {
            currentIndex = index
        }
        // Deliberately CLAMPED rather than wrapping. A wrap turns one
        // key too many into a jump from the bottom of a 40-row list back
        // to the top, which reads as the list having jumped somewhere
        // else entirely; a native popup stops at the ends.
        var nextIndex: Int = currentIndex + step
        if nextIndex < 0 {
            nextIndex = 0
        }
        if nextIndex > entries.count - 1 {
            nextIndex = entries.count - 1
        }
        highlightedCourseCode = entries[nextIndex].code
        return true
    }

    /// Return pressed in the field: takes the highlighted row if the
    /// teacher has walked to one. Returns false otherwise, so Return
    /// still reaches the sheet's default button for someone who typed a
    /// code and never touched the arrows.
    func commitCourseCodeHighlight() -> Bool {
        guard courseCodeSuggestionsAreShown, let entry = highlightedCourseCodeEntry else {
            return false
        }
        selectCourseCodeSuggestion(entry)
        return true
    }

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
        if !skeleton.gradedFolders.isEmpty {
            gradedFolders = skeleton.gradedFolders
        } else {
            var counted: [String] = []
            for folder in skeleton.sharedFolders + skeleton.perSectionFolders {
                if folder.lowercased().contains("task") {
                    counted.append(folder)
                }
            }
            gradedFolders = counted
        }
    }

    static func reconciledGradedFolders(from gradedFolders: [String], validChoices: [String]) -> [String] {
        var result: [String] = []
        for folder in gradedFolders {
            if validChoices.contains(folder) {
                result.append(folder)
            }
        }
        return result
    }

    func reconcileGradedFolders() {
        gradedFolders = NewCourseWizardView.reconciledGradedFolders(
            from: gradedFolders, validChoices: gradedFolderChoices
        )
    }

    func wizardSharedFolderProtection(for folder: String) -> ItemProtection {
        if let resolvedCurriculum = wizardResolvedCurriculumFolder, folder == resolvedCurriculum {
            if effectiveCurriculumCoverageEnabled {
                return .blocked(reason: SpecialNames.curriculumFolderBlockedByCoverageMap)
            } else if effectiveCurriculumPagesEnabled {
                let jurisdiction: String = ExampleContentCatalog.jurisdictionName(forCode: courseCode)
                return .blocked(reason: SpecialNames.curriculumFolderBlockedByCurriculumPages(jurisdiction: jurisdiction))
            } else {
                return .consequential(
                    title: SpecialNames.removeCurriculumFolderTitle(for: folder),
                    message: SpecialNames.removeCurriculumFolderMessage
                )
            }
        }
        if gradedFolders.contains(folder) {
            if effectiveCurriculumCoverageEnabled && gradedFolders.count <= 1 {
                return .blocked(reason: SpecialNames.lastGradedFolderBlockedWizard)
            } else {
                return .consequential(
                    title: SpecialNames.removeGradedFolderTitle(for: folder),
                    message: SpecialNames.removeGradedFolderMessage
                )
            }
        }
        return .ordinary
    }

    func wizardPerSectionFolderProtection(for folder: String) -> ItemProtection {
        if perSectionFolders.count <= 1 {
            return .blocked(reason: SpecialNames.lastPerSectionFolderBlocked)
        }
        if gradedFolders.contains(folder) && effectiveCurriculumCoverageEnabled && gradedFolders.count <= 1 {
            return .blocked(reason: SpecialNames.lastGradedFolderBlockedWizard)
        }
        let classFolders: [String] = ClassFolder.names(inPerSectionFolders: perSectionFolders)
        if classFolders.contains(folder) {
            return .consequential(
                title: SpecialNames.removeClassFolderTitle(for: folder),
                message: SpecialNames.removeClassFolderMessage
            )
        }
        if gradedFolders.contains(folder) {
            return .consequential(
                title: SpecialNames.removeGradedFolderTitle(for: folder),
                message: SpecialNames.removeGradedFolderMessage
            )
        }
        return .ordinary
    }

    func wizardPerSectionFileProtection(for file: String) -> ItemProtection {
        let normalized: String = file.lowercased()
        if normalized == "index.md" || normalized == "index" {
            return .blocked(reason: SpecialNames.sectionIndexFileBlocked)
        }
        return .ordinary
    }

    func wizardGradedFolderProtection(for folder: String) -> ItemProtection {
        guard effectiveCurriculumCoverageEnabled else {
            return .ordinary
        }
        if gradedFolders.contains(folder) && gradedFolders.count <= 1 {
            return .blocked(reason: SpecialNames.lastGradedFolderBlockedWizard)
        }
        return .ordinary
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
        // Every ADDITIONAL destination gets the same check its primary
        // counterpart would — a redundancy target with no valid folder or
        // credential would just fail silently the first time a deploy
        // actually reaches it, which is exactly the surprise redundancy
        // is supposed to prevent.
        for target in additionalDeployTargets {
            if target.type == "local_folder" {
                if let problem = CourseConfiguration.deployFolderProblem(forPath: target.path) {
                    validationProblem = problem
                    return
                }
            }
            if target.type == "cloudflare_pages" {
                if let problem = CourseConfiguration.cloudflareAccountProblem(forID: AppSettings.shared.cloudflareAccountID) {
                    validationProblem = problem
                    return
                }
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
                    || item.lowercased() == "media"
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

        var config: [String: Any] = [
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

        // Omitted entirely rather than written as `[]` when nobody has
        // opted in — a course that never touches this feature writes the
        // exact same file the wizard has always written. See
        // `CourseConfiguration.additionalDeployTargets`, whose setter
        // does the identical thing on every later save.
        // Pruned against the primary one more time here, defensively —
        // the picker's own onChange keeps this consistent live on screen,
        // but the file written to disk must be correct even if some future
        // change to this view ever let the two disagree.
        let prunedAdditionalTargets: [CourseConfiguration.AdditionalDeployTarget] =
            CourseConfiguration.pruningAdditionalTargets(additionalDeployTargets, ofType: deployTarget)
        if !prunedAdditionalTargets.isEmpty {
            var encoded: [[String: Any]] = []
            for target in prunedAdditionalTargets {
                var entry: [String: Any] = ["type": target.type]
                if !target.path.isEmpty {
                    entry["path"] = target.path
                }
                encoded.append(entry)
            }
            config["additional_deploy_targets"] = encoded
        }
        let structureFromExample: Bool = prepopulatesExampleContent
            && ExampleContentCatalog.hasContent(forCode: code)
        if !structureFromExample {
            config["graded_folders"] = gradedFolders
        }

        return config
    }
}
