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

    /// What this course calls a unit — "Unit 2, Day 3", or "Module 2, Day 3".
    /// Asked here because the ready-made pages are poured in this word, so
    /// nothing needs renaming afterwards. A course already in use changes it
    /// from Course Settings → Rename… (`UnitWordRenamer`), which renames the
    /// class pages and follows the links.
    @State var unitWord: String = ClassPageTerm.standard

    /// "This is a club" (#267). Follows `ClubCodeRule` — so CODING arrives
    /// ticked and ICS3U does not — until the teacher touches it, and from
    /// then on it is theirs. Wizard state only: what is written is the four
    /// words below and the numbered scheme, never an `is_club` flag, which
    /// could disagree with them.
    @State var isClubCourse: Bool = false
    @State var clubChoiceIsTheTeachers: Bool = false

    /// The club's words, each editable before Create and none switchable
    /// afterwards (Russell, 2026-09-24). `classFolderName` is the entry of
    /// `perSectionFolders` that holds the class pages, RECORDED as
    /// `class_folder` rather than guessed — "All Meetings" has no "class" in
    /// it for the guess to find.
    @State var classFolderName: String = ClubVocabulary.course.classFolder
    @State var frontPageHeading: String = ClubVocabulary.course.frontPageHeading
    @State var classNoun: ClassNoun = ClubVocabulary.course.noun

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

    /// What the last adoption put into the five lists above, so that turning
    /// the skeleton toggle off can put the defaults back for exactly the
    /// lists the teacher has NOT edited since. Nil until a skeleton is
    /// adopted, and nil again the moment one is given up.
    @State var adoptedStructure: WizardStructure.Lists?

    @State var validationProblem: String?
    @State var hasStarted: Bool = false

    /// What the progress header is called — the wizard creates a course,
    /// but the same sheet also adds the example course.
    @State var progressTitle: String = "Creating your course"

    // MARK: - Initializer

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
        gradedFolders: [String] = ["Tasks"],
        isClubCourse: Bool = false,
        classFolderName: String = ClubVocabulary.course.classFolder,
        unitWord: String = ClassPageTerm.standard,
        frontPageHeading: String = ClubVocabulary.course.frontPageHeading,
        classNoun: ClassNoun = ClubVocabulary.course.noun
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
        _isClubCourse = State(initialValue: isClubCourse)
        _clubChoiceIsTheTeachers = State(initialValue: isClubCourse)
        _classFolderName = State(initialValue: classFolderName)
        _unitWord = State(initialValue: unitWord)
        _frontPageHeading = State(initialValue: frontPageHeading)
        _classNoun = State(initialValue: classNoun)
    }

    // MARK: - Computed properties

    /// The five lists as the structure editor is showing them now.
    var currentStructure: WizardStructure.Lists {
        return WizardStructure.Lists(
            sharedFolders: sharedFolders,
            sharedFiles: sharedFiles,
            perSectionFolders: perSectionFolders,
            perSectionFiles: perSectionFiles,
            gradedFolders: gradedFolders
        )
    }

    /// The teacher's Cloudflare Account ID, which belongs to the person
    /// rather than to this new course — so it is read from and written
    /// straight back to app settings rather than kept as wizard state.
    var cloudflareAccountIDBinding: Binding<String> {
        return Binding(
            get: { AppSettings.shared.cloudflareAccountID },
            set: { newValue in AppSettings.shared.cloudflareAccountID = newValue }
        )
    }

    /// Why a club's class-pages folder cannot have this name, in the
    /// sentences a folder rename in Course Settings already uses
    /// (`SpecialFolderRenamer.problem`): empty, a "/" or ":", hidden, Media,
    /// a section folder's name, or the name of ANOTHER per-section folder.
    /// `perSectionFolders` holds the class folder itself, once, since the
    /// field renames its entry in place; that one entry is not a clash.
    static func clubClassFolderProblem(_ name: String, perSectionFolders: [String]) -> String? {
        let typed: String = name.trimmingCharacters(in: .whitespaces)
        var others: [String] = []
        var skippedItsOwnEntry: Bool = false
        for folder in perSectionFolders {
            if !skippedItsOwnEntry && folder == name {
                skippedItsOwnEntry = true
                continue
            }
            others.append(folder)
        }
        return SpecialFolderRenamer.problem(renaming: "", to: typed, existingNames: others)
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
        return takesExampleContent
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

    /// Whether the course will take the ready-made pages written for its
    /// code. Never for a club (#267): those pages are Unit/Day pages, which
    /// a numbered course does not read as class pages.
    var takesExampleContent: Bool {
        return prepopulatesExampleContent && !isClubCourse
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

    /// Whether the curriculum pages written for this code can be offered
    /// at all — taken with the payload, or brought along into the
    /// subject's skeleton when the payload is declined (GitHub issue
    /// #251). The rule itself lives in `CourseConfiguration` so that it
    /// can be tested: a SwiftUI `@State` property has no backing store
    /// until the view is on screen.
    var curriculumPagesOffered: Bool {
        return CourseConfiguration.curriculumPagesOffered(
            codeHasExampleContent: ExampleContentCatalog.hasContent(forCode: courseCode) && !isClubCourse,
            payloadIncludesCurriculum: ExampleContentCatalog.includesCurriculum(forCode: courseCode),
            prepopulatesExampleContent: takesExampleContent,
            skeletonIsOffered: SkeletonCatalog.hasSkeleton(
                forCode: courseCode, takingExampleContent: takesExampleContent, numbered: isClubCourse
            ),
            startsFromSkeleton: startsFromSkeleton
        )
    }

    var effectiveCurriculumPagesEnabled: Bool {
        return curriculumPagesOffered && includesCurriculumPages
    }

    var effectiveCurriculumCoverageEnabled: Bool {
        return CourseConfiguration.curriculumCoverageEnabled(
            curriculumPagesOffered: curriculumPagesOffered,
            includesCurriculumPages: includesCurriculumPages,
            includesCurriculumCoverage: includesCurriculumCoverage
        )
    }

    var wizardResolvedCurriculumFolder: String? {
        let declared: String? = ExampleContentCatalog.curriculumFolder(forCode: courseCode)
            ?? SkeletonCatalog.family(forCode: courseCode)?.curriculumFolder
        return CurriculumFolderRule.resolvedCurriculumFolder(configured: declared, in: sharedFolders)
    }

    /// What a teacher is told when this course will start with nothing in
    /// it and no ready-made pages exist for the code — either because no
    /// skeleton exists either, or because they have turned the skeleton
    /// down. Both are the same situation, so both say the same sentence
    /// (`WizardWording.noExampleContentNote`, pinned by the contract).
    var noExampleContentNote: some View {
        Text(WizardWording.noExampleContentNote)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("noExampleContentNote")
    }

    /// The same situation for a code that DOES have ready-made pages: the
    /// teacher declined them and then declined the skeleton too. A second
    /// sentence, because the first one opens by saying no example content
    /// is available for the code — which they have just been offered.
    ///
    /// Its own accessibility identifier rather than the other's: three
    /// sentences across two keys now, so sharing one would leave a test
    /// unable to say WHICH of them a teacher is reading. Windows matches
    /// (`contracts/shared-rules.json` → `wizard.whenTheNoteIsShown`).
    var noStartingContentNote: some View {
        Text(WizardWording.noStartingContentNote)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("noStartingContentNote")
    }

    /// Which of the two a teacher reads, once the course is set to start
    /// with nothing: the code's own situation decides, not the toggle they
    /// happened to use to get there.
    @ViewBuilder
    var noteForACourseStartingEmpty: some View {
        if ExampleContentCatalog.hasContent(forCode: courseCode) {
            noStartingContentNote
        } else {
            noExampleContentNote
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
                // The club choice follows the code until the teacher
                // touches it (#267).
                if !clubChoiceIsTheTeachers && isClubCourse != ClubCodeRule.isClub(courseCode) {
                    isClubCourse = ClubCodeRule.isClub(courseCode)
                }
            }
            .onChange(of: isClubCourse) { _, isAClubNow in
                applyClubChoice(isAClubNow)
            }
            // The structure editor must show what will actually be
            // created, in both directions — so the toggle adopts and
            // gives up, rather than only adopting.
            //
            // Attached HERE, to the whole sheet, rather than to the
            // Toggle itself: the Toggle lives inside an `else if let
            // skeleton` branch of the Starting Content section, and that
            // branch LEAVES the hierarchy the moment the typed code stops
            // having a skeleton — a handler that is not there cannot fire.
            // (Re-evaluating a body does not cost a handler: the LCS
            // switch's own `.onChange` sits inside a branch and works.
            // Disappearing is the case this avoids.)
            .onChange(of: startsFromSkeleton) { _, startsFromASkeletonNow in
                if startsFromASkeletonNow {
                    adoptSkeletonStructure()
                } else {
                    restoreGenericStructure()
                }
            }
            // Its sibling, and here for the same reason: turning the
            // example content OFF for a code that has some is what now
            // OFFERS the skeleton, so it has to move the structure editor
            // exactly as the skeleton toggle itself does. Without this the
            // toggle would read on, the lists would stay factory, and the
            // file would say `use_skeleton: true` beside folders the
            // skeleton's pages were not written for — the same "the wizard
            // lies about what it is about to make" bug the toggle's own
            // handler exists to prevent, in mirror image.
            //
            // The way back matters just as much: a teacher who declines the
            // example content, sees the subject's folders, and then changes
            // their mind must get today's file back, not a course taking
            // ready-made pages with a skeleton's folders written beside
            // them.
            .onChange(of: prepopulatesExampleContent) { _, takesExampleContentNow in
                if takesExampleContentNow {
                    restoreGenericStructure()
                } else {
                    adoptSkeletonStructure()
                }
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
                    Button(WizardWording.createCourseButton) {
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
                    // Shown for EVERY code, not only a club-looking one:
                    // the rule only decides where it starts (#267).
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(WizardWording.clubToggleLabel, isOn: Binding(
                            get: {
                                return isClubCourse
                            },
                            set: { newValue in
                                clubChoiceIsTheTeachers = true
                                isClubCourse = newValue
                            }
                        ))
                        .accessibilityIdentifier("clubToggle")
                        ExampleCaption(WizardWording.clubToggleCaption)
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
                if isClubCourse {
                    Text(WizardWording.clubStartingContentNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("clubStartingContentNote")
                } else {
                if ExampleContentCatalog.hasContent(forCode: courseCode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Pre-populate course with example content", isOn: $prepopulatesExampleContent)
                            .accessibilityIdentifier("prepopulateToggle")
                        ExampleCaption("Working pages written for this course — keep, edit, or delete them as you build your own site. The example content also chooses the course's folders and files, so they fit the pages.")
                    }
                }
                // A SIBLING of the example-content block rather than its
                // `else`, which is the whole of issue #248: a code with
                // ready-made pages has a skeleton too, and the moment the
                // teacher turns the pages down the skeleton is what the
                // course should start from. `hasSkeleton` carries that
                // rule for all three surfaces — this toggle, the
                // structure editor's adoption, and `use_skeleton` in the
                // file — so the three cannot drift apart again.
                //
                // Four states reach this section, and each says one thing:
                // taking ready-made pages, the block above alone; not
                // taking them (or having none) with a family for the
                // prefix, the toggle here; the toggle off, one of the two
                // notes; and no code typed at all, where no family
                // resolves and `noExampleContentNote` is what a teacher
                // reads before they have chosen anything.
                if SkeletonCatalog.hasSkeleton(
                    forCode: courseCode, takingExampleContent: prepopulatesExampleContent, numbered: isClubCourse
                ), let skeleton = SkeletonCatalog.family(forCode: courseCode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(
                            WizardWording.skeletonToggleLabel(
                                forFamilyNamed: skeleton.name, label: skeleton.label
                            ),
                            isOn: $startsFromSkeleton
                        )
                        .accessibilityIdentifier("skeletonToggle")
                        if ExampleContentCatalog.hasContent(forCode: courseCode) {
                            ExampleCaption(WizardWording.skeletonToggleCaptionWhenExampleContentIsDeclined)
                        } else {
                            ExampleCaption(WizardWording.skeletonToggleCaption)
                        }
                        // With the toggle off the teacher is in exactly
                        // the situation the no-content note describes, so
                        // it says so — in the words that are TRUE for
                        // this code, which is what
                        // `noteForACourseStartingEmpty` chooses between.
                        if !startsFromSkeleton {
                            noteForACourseStartingEmpty
                        }
                    }
                } else if !ExampleContentCatalog.hasContent(forCode: courseCode) {
                    noExampleContentNote
                }
                // BELOW the two toggles that govern them, so the
                // dependency reads top to bottom (GitHub issue #251).
                // They used to sit directly under the example-content
                // toggle, which was the only thing that could switch them
                // on; now a teacher who turns that off and keeps the
                // subject's skeleton gets the curriculum too, and three
                // live toggles above an off one — with a caption above
                // them still explaining the example content — read as
                // though the wrong thing had happened. Nothing moves for
                // a teacher taking the ready-made pages: the skeleton
                // block draws nothing for them, so these still follow the
                // example-content toggle directly.
                if ExampleContentCatalog.includesCurriculum(forCode: courseCode) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Live whenever the pages can be offered at
                        // all — which, since GitHub issue #251, is
                        // also the teacher who declined the ready-made
                        // pages and kept the subject's skeleton. The
                        // expectations written for their code exist;
                        // greying the toggle out told them otherwise.
                        Toggle("Include \(ExampleContentCatalog.jurisdictionName(forCode: courseCode)) curriculum pages", isOn: $includesCurriculumPages)
                            .disabled(!curriculumPagesOffered)
                            .accessibilityIdentifier("curriculumToggle")
                        ExampleCaption("Every expectation as its own page, so lessons and tasks can link to exactly what they address")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        // The map reads the site's links to the
                        // curriculum pages, so it cannot exist without
                        // them — but keeping the pages and declining
                        // the map is a perfectly reasonable choice.
                        Toggle("Include the curriculum coverage map", isOn: $includesCurriculumCoverage)
                            .disabled(!curriculumPagesOffered || !includesCurriculumPages)
                            .accessibilityIdentifier("curriculumCoverageToggle")
                        ExampleCaption("A page showing every expectation coloured by how many pages address it — red in September, greener as the year goes on. Linked from Key Links, and kept out of the sidebar.")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        // The sections sit on the coverage page, so they
                        // cannot exist without it.
                        Toggle("Explain the map on the page", isOn: $includesCoverageNotes)
                            .disabled(!curriculumPagesOffered
                                      || !includesCurriculumPages
                                      || !includesCurriculumCoverage)
                            .accessibilityIdentifier("coverageNotesToggle")
                        ExampleCaption("Two short sections at the foot of the map: what counts as addressing an expectation, and how to read it honestly — red in September is normal, red in May is not. Turn this off to publish the map on its own.")
                    }
                }
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

            // Asked of EVERY course, including a pre-populated one: the
            // ready-made pages are poured in this word rather than renamed
            // afterwards, which is why it cannot be moved into Settings later.
            Section {
                if isClubCourse {
                    // A club's words (#267): the page word is the same
                    // `unit_word` field, naming the whole of "Week 3".
                    LabeledContent(WizardWording.clubClassFolderLabel) {
                        TextField("", text: Binding(
                            get: {
                                return classFolderName
                            },
                            set: { newValue in
                                renameClassFolder(to: newValue)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("clubClassFolderField")
                    }
                    if let problem = NewCourseWizardView.clubClassFolderProblem(
                        classFolderName, perSectionFolders: perSectionFolders
                    ) {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("clubClassFolderProblem")
                    }
                    LabeledContent(WizardWording.clubFrontPageHeadingLabel) {
                        TextField("", text: $frontPageHeading)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("clubFrontPageHeadingField")
                    }
                    LabeledContent(WizardWording.clubPageWordLabel) {
                        TextField("", text: $unitWord)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("unitWordField")
                    }
                    if let problem = ClassPageTerm.problem(with: unitWord) {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("unitWordProblem")
                    } else {
                        ExampleCaption(WizardWording.clubPageWordCaption(word: ClassPageTerm.cleaned(unitWord)))
                    }
                    Picker(WizardWording.clubNounLabel, selection: $classNoun) {
                        Text("class").tag(ClassNoun.class)
                        Text("meeting").tag(ClassNoun.meeting)
                    }
                    .accessibilityIdentifier("clubNounPicker")
                } else {
                LabeledContent("What do you call a unit?") {
                    TextField("Unit", text: $unitWord, prompt: Text(ClassPageTerm.standard))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("unitWordField")
                }
                if let problem = ClassPageTerm.problem(with: unitWord) {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("unitWordProblem")
                } else {
                    ExampleCaption("Class pages will be named “\(ClassPageTerm.cleaned(unitWord)) 1, Day 1”. Some teachers say Module or Thread.")
                }
                }
            } header: {
                FormSectionHeader(
                    "Units",
                    caption: "Chosen once, when the course is made — the pages are named this way as they are written"
                )
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
                    Text(WizardWording.structureFromExampleNote)
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
                        // A club has no curriculum folder, whichever
                        // terminology's factory list just came back (#267).
                        if isClubCourse {
                            var kept: [String] = []
                            for folder in sharedFolders where !ClubFill.curriculumFolders.contains(folder) {
                                kept.append(folder)
                            }
                            sharedFolders = kept
                        }
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
                            title: GradedFolderWording.listTitle,
                            allItems: gradedFolderChoices,
                            members: gradedFoldersBinding,
                            protection: wizardGradedFolderProtection
                        )
                        Text(GradedFolderWording.caption)
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
    ///
    /// Does nothing while the toggle is OFF, which is not a detail: this
    /// runs on every change to the course code, so without the guard a
    /// teacher who declined the skeleton and then corrected a typo in the
    /// code would silently be given the skeleton's folders back.
    func adoptSkeletonStructure() {
        guard startsFromSkeleton && !isClubCourse else {
            return
        }
        guard let skeleton = SkeletonCatalog.structureToAdopt(
            forCode: courseCode,
            takingExampleContent: prepopulatesExampleContent,
            numbered: isClubCourse,
            currentSharedFolders: sharedFolders
        ) else {
            return
        }
        let adopted: WizardStructure.Lists = WizardStructure.adopting(skeleton)
        putIntoEditor(adopted)
        // Recorded so that turning the toggle off can tell a list the teacher
        // has edited since from one they never touched.
        adoptedStructure = adopted
    }

    /// The toggle went off: the skeleton's folders leave the editor and the
    /// generic defaults come back, list by list against what the adoption put
    /// there. The rule — and what it deliberately costs — is in
    /// `WizardStructure.restoringDefaults(in:adopted:usesLCSTerminology:)`.
    func restoreGenericStructure() {
        let restored: WizardStructure.Lists = WizardStructure.restoringDefaults(
            in: currentStructure,
            adopted: adoptedStructure,
            usesLCSTerminology: usesLCSTerminology
        )
        putIntoEditor(restored)
        adoptedStructure = nil
    }

    /// "This is a club" went on or off (#267). A skeleton's folders are
    /// given up first — a club takes none, and a code like CODING has
    /// already adopted the general one by the time the box ticks itself —
    /// then `ClubFill` moves the words and folders the teacher has not
    /// edited. Turning it off offers the subject's skeleton again.
    func applyClubChoice(_ isAClub: Bool) {
        if isAClub && adoptedStructure != nil {
            restoreGenericStructure()
        }
        let filled: ClubFillFields = ClubFill.applying(
            isClub: isAClub,
            to: ClubFillFields(
                sharedFolders: sharedFolders, perSectionFolders: perSectionFolders,
                classFolder: classFolderName, unitWord: unitWord,
                frontPageHeading: frontPageHeading, noun: classNoun
            ),
            usesLCSTerminology: usesLCSTerminology
        )
        sharedFolders = filled.sharedFolders
        perSectionFolders = filled.perSectionFolders
        classFolderName = filled.classFolder
        unitWord = filled.unitWord
        frontPageHeading = filled.frontPageHeading
        classNoun = filled.noun
        reconcileGradedFolders()
        if !isAClub {
            adoptSkeletonStructure()
        }
    }

    /// The class-pages folder renamed in the club's own row: the entry in
    /// the per-section list follows it, in its place.
    func renameClassFolder(to newName: String) {
        var folders: [String] = []
        var renamed: Bool = false
        for folder in perSectionFolders {
            if folder == classFolderName && !renamed {
                folders.append(newName)
                renamed = true
            } else {
                folders.append(folder)
            }
        }
        perSectionFolders = folders
        classFolderName = newName
    }

    /// Puts a set of lists into the structure editor.
    func putIntoEditor(_ lists: WizardStructure.Lists) {
        sharedFolders = lists.sharedFolders
        sharedFiles = lists.sharedFiles
        perSectionFolders = lists.perSectionFolders
        perSectionFiles = lists.perSectionFiles
        gradedFolders = lists.gradedFolders
    }

    /// The marks pool narrowed to the folders this course will actually have.
    /// The rule itself is `GradedFolderRule.reconciled(_:toFolders:)`, which
    /// says how it differs from Windows' and why; this stays as the name the
    /// call sites and their tests already use.
    static func reconciledGradedFolders(from gradedFolders: [String], validChoices: [String]) -> [String] {
        return GradedFolderRule.reconciled(gradedFolders, toFolders: validChoices)
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
        // "All Classes" is never removable (Russell, 2026-08-24); see
        // CourseSettingsView.perSectionFolderProtection.
        // The wizard has no recorded class folder to consult: the course does
        // not exist yet, and the name it will record is the one this rule is
        // about to pick. The literal is the right test here.
        if ClassFolder.isTheAllClassesFolder(folder) {
            return .blocked(reason: SpecialNames.classFolderBlocked)
        }
        // A club's class folder is protected by the name it was given
        // (#267): the literal alone left "All Meetings" deletable.
        if isClubCourse && folder == classFolderName {
            return .blocked(reason: SpecialNames.classFolderBlocked)
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
        // The same check the caption under the field shows. Refused here as
        // well because the pages would otherwise be written with names nothing
        // can read back — built, and then recognised by nothing.
        if let problem = ClassPageTerm.problem(with: unitWord) {
            validationProblem = problem
            return
        }
        // The club's class-pages folder is typed into a field of its own
        // rather than added through the list, so it gets the list's checks
        // here (#267 review): empty, a "/", or another folder's name would
        // otherwise go straight into `per_section_folders` and `class_folder`.
        if isClubCourse, let problem = NewCourseWizardView.clubClassFolderProblem(
            classFolderName, perSectionFolders: perSectionFolders
        ) {
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
        var chosenGradedFolders: [String] = gradedFolders
        var skeleton: SkeletonCatalog.Family? = nil
        if startsFromSkeleton && SkeletonCatalog.hasSkeleton(
            forCode: code, takingExampleContent: prepopulatesExampleContent, numbered: isClubCourse
        ) {
            skeleton = SkeletonCatalog.family(forCode: code)
            if let adopted = SkeletonCatalog.structureToAdopt(
                forCode: code,
                takingExampleContent: prepopulatesExampleContent,
                numbered: isClubCourse,
                currentSharedFolders: sharedFolders
            ) {
                let lateAdoption: WizardStructure.Lists = WizardStructure.adopting(adopted)
                chosenSharedFolders = lateAdoption.sharedFolders
                chosenSharedFiles = lateAdoption.sharedFiles
                chosenPerSectionFolders = lateAdoption.perSectionFolders
                chosenPerSectionFiles = lateAdoption.perSectionFiles
                // The marks pool comes with them. Leaving it behind wrote the
                // wizard's default ["Tasks"] beside the mathematics
                // skeleton's folders, whose assessed work is in Thinking
                // Tasks — the same silent loss row 359 exists about. Windows
                // sets all five here too (NewCourseDialog.BuildConfiguration).
                chosenGradedFolders = lateAdoption.gradedFolders
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

        // The rule the three curriculum keys are written from, asked once.
        // It reads the code this configuration is FOR rather than the
        // field's current contents, the same way every other key here does.
        let pagesOffered: Bool = CourseConfiguration.curriculumPagesOffered(
            codeHasExampleContent: ExampleContentCatalog.hasContent(forCode: code) && !isClubCourse,
            payloadIncludesCurriculum: ExampleContentCatalog.includesCurriculum(forCode: code),
            prepopulatesExampleContent: takesExampleContent,
            skeletonIsOffered: SkeletonCatalog.hasSkeleton(
                forCode: code, takingExampleContent: takesExampleContent, numbered: isClubCourse
            ),
            startsFromSkeleton: startsFromSkeleton
        )
        let coverageEnabled: Bool = CourseConfiguration.curriculumCoverageEnabled(
            curriculumPagesOffered: pagesOffered,
            includesCurriculumPages: includesCurriculumPages,
            includesCurriculumCoverage: includesCurriculumCoverage
        )

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
            // What this course calls a unit. Written even when it is the
            // default, so the file says out loud what the pages will be
            // called; an ABSENT key still means "Unit" for every course made
            // before the choice existed.
            "unit_word": ClassPageTerm.cleaned(unitWord),
            // Which per-section folder holds class pages, RECORDED rather than
            // left to be guessed from the word "class". Written at creation so
            // a teacher whose vocabulary is "Thread 2, Day 3" can call it
            // "All Days" without the next-class button and the curriculum map
            // quietly looking somewhere else.
            //
            // A club's (#267) is the name the teacher chose in the club's
            // own row: "All Meetings" has no "class" for the guess to find,
            // so the guess would fall back to whichever folder is FIRST.
            "class_folder": isClubCourse && chosenPerSectionFolders.contains(classFolderName)
                ? classFolderName
                : ClassFolder.name(inPerSectionFolders: chosenPerSectionFolders),
            // The real wizard reads these as its defaults, exactly like
            // every other answer here. False when no skeleton is offered
            // for the code — including a code whose ready-made pages the
            // teacher IS taking — so a stale true can never mean anything.
            "use_skeleton": SkeletonCatalog.hasSkeleton(
                forCode: code, takingExampleContent: prepopulatesExampleContent, numbered: isClubCourse
            ) && startsFromSkeleton,
            "prepopulate_example_content": ExampleContentCatalog.hasContent(forCode: code)
                && takesExampleContent,
            // Written exactly as they are for a payload course, because
            // the pages are the payload's either way: the teacher who
            // declined the ready-made lessons and kept the subject's
            // skeleton still gets the expectations written for their code
            // (GitHub issue #251). `setup_course.py` reads these three as
            // its answers, so false here means the launcher never runs its
            // new branch, whatever the interface showed.
            "include_curriculum_pages": pagesOffered && includesCurriculumPages,
            // Depends on the curriculum pages: without them the map has
            // nothing to colour, so it is forced off here as well as
            // disabled in the interface.
            "include_curriculum_coverage": coverageEnabled,
            "include_coverage_notes": CourseConfiguration.coverageNotesEnabled(
                curriculumCoverageEnabled: coverageEnabled,
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
        // How class pages are named, the front page's heading, and what the
        // assistant calls a page (#267) — written for a CLUB only. An ABSENT
        // key means today's "Unit 2, Day 3", "Most Recent Class" and
        // "class" (contracts/file-formats.json), so every other course's
        // file stays byte-for-byte what it was: the golden
        // `WizardStructureTests.testTheFileForEveryPathThatExistedBeforeIsUnchanged`
        // holds it to that, and a course has nothing to say in these keys
        // that their absence does not already say.
        if isClubCourse {
            let heading: String = frontPageHeading.trimmingCharacters(in: .whitespaces)
            config["class_page_scheme"] = ClassPageScheme.numbered.rawValue
            config["front_page_heading"] = heading.isEmpty ? ClubVocabulary.club.frontPageHeading : heading
            config["class_noun"] = classNoun.rawValue
        }

        let structureFromExample: Bool = takesExampleContent
            && ExampleContentCatalog.hasContent(forCode: code)
        if structureFromExample {
            // The payload's own pool, as the command line writes it (GitHub
            // issue #292). The app owns this answer, not `setup_course.py`:
            // setup runs over the file written here, keeps a saved pool, and
            // reads a saved file WITHOUT one as a course that was never
            // asked — it works the pool out from the manifest only when
            // there is no saved file at all, which only a command-line run
            // has. Leaving the key out, as this did from 2026-08-24, gave
            // every pre-populated course the historical "any folder with
            // 'task' in its name" rule instead of the payload's Tasks.
            //
            // Never `chosenGradedFolders`: the structure editors are
            // collapsed for a payload course, so that list is one the
            // teacher never saw. `takesExampleContent` is already false
            // for a club, which takes no ready-made pages (#267). An
            // unreadable manifest leaves the key absent, as before.
            // contracts/shared-rules.json → gradedFolders.newCourse.
            if let payloadPool = ExampleContentCatalog.marksPool(forCode: code) {
                config["graded_folders"] = payloadPool
            }
        } else {
            // Narrowed once more as the file is written, the way Windows does
            // it (NewCourseDialog.BuildConfiguration). The editor narrows the
            // pool wherever it changes the folder lists — a removal, a
            // skeleton given up — but the terminology switch does not, so a
            // teacher who ticked College Board Curriculum and then turned LCS
            // off would otherwise have that folder written into a course that
            // has no such folder. This is the ONLY net: since GitHub issue
            // #192 `setup_course.py` writes a saved pool back as it was
            // (gradedFolders.rerunningSetup), and it also makes both apps
            // write the same file.
            config["graded_folders"] = GradedFolderRule.reconciled(
                chosenGradedFolders,
                toFolders: chosenSharedFolders + chosenPerSectionFolders
            )
        }

        return config
    }
}
