import SwiftUI

/// The folder a teacher chose to import from, on its way to the sheet.
///
/// A `URL` cannot present a `.sheet(item:)` on its own — nothing identifies
/// it — and the path is the identity here: choosing the same folder twice is
/// the same request.
struct ReferenceImportRequest: Identifiable, Equatable {

    // MARK: - Stored properties

    let folderURL: URL

    // MARK: - Computed properties

    var id: String {
        return folderURL.path
    }
}

/// The folder chooser and the sheet behind it, as one modifier.
///
/// A modifier rather than two more lines on the sidebar's own chain, for a
/// reason the compiler gave: that chain is long enough that adding a
/// `fileImporter` and a `sheet` to it took the type-checker past its limit
/// ("unable to type-check this expression in reasonable time"). Two other
/// groups of modifiers there are already wrapped up this way for the same
/// reason.
struct ImportCoursesForReferencePresenter: ViewModifier {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    // MARK: - Functions

    func body(content: Content) -> some View {
        @Bindable var workspace = workspace

        return content
            .fileImporter(
                isPresented: $workspace.isChoosingFolderToImportFrom,
                allowedContentTypes: [.folder]
            ) { result in
                switch result {
                case .success(let folderURL):
                    workspace.referenceImportRequest = ReferenceImportRequest(folderURL: folderURL)
                case .failure:
                    break
                }
            }
            .sheet(item: $workspace.referenceImportRequest) { request in
                ImportCoursesForReferenceSheet(chosenURL: request.folderURL) { folderNames in
                    workspace.reloadCourses()
                    for folderName in folderNames {
                        workspace.revealReferenceCourse(folderName: folderName)
                    }
                    if let first = folderNames.first {
                        workspace.selection = SidebarSelection.course(first)
                    }
                }
            }
    }
}

/// "Import Courses for Reference…" — the sheet.
///
/// A teacher points at the folder they kept last year's classes in, ticks the
/// courses they want, chooses a school year for each, and presses Import.
/// Everything that decides anything is in `ReferenceImportSource`,
/// `ReferenceImporter` and `ReferenceCourseRule`; this file draws it.
///
/// **Four states, drawn one at a time**: reading the folder, choosing,
/// copying, and done. A single sheet rather than a wizard with pages,
/// because there is one decision to make and a list to tick.
struct ImportCoursesForReferenceSheet: View {

    // MARK: - Types

    /// What the sheet is doing.
    enum Stage: Equatable {
        case reading
        case refused(String)
        case choosing
        case copying
        case done
    }

    // MARK: - Stored properties

    /// The folder the teacher chose in the chooser.
    let chosenURL: URL

    /// Called once anything has landed, so the sidebar reloads and selects
    /// the first course that came across.
    let onImport: ([String]) -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(WorkspaceModel.self) var workspace

    @State var stage: Stage = .reading
    @State var source: ReferenceImportSource?

    /// Which courses are ticked, by folder name.
    @State var ticked: Set<String> = []

    /// The school year chosen for each course, by folder name. A folder name
    /// that is absent has not been decided yet and uses the proposal.
    @State var schoolYears: [String: Int?] = [:]

    @State var progress: ReferenceImporter.Progress?
    @State var outcomes: [ReferenceImporter.Outcome] = []

    /// The run itself, so Stop can cancel it.
    @State var run: Task<Void, Never>?

    /// The older-layout row whose shared folder is being chosen by hand, by
    /// folder name, and whether the chooser is up. A second chooser of the
    /// sheet's OWN: the one that opened this sheet belongs to the sidebar.
    @State var choosingSharedFor: String?
    @State var isChoosingShared: Bool = false

    /// Why the folder chosen for a row could not be its shared folder, by
    /// folder name. Said beside the row; the row keeps what it had.
    @State var sharedPickProblem: [String: String] = [:]

    /// The day the year lists are built from. A stored property rather than a
    /// call to the clock inside the body, so the lists cannot change under
    /// the teacher mid-sheet — and so a test can move it.
    let today: CalendarDay

    // MARK: - Computed properties

    var courses: [ReferenceImportSource.FoundCourse] {
        return source?.courses ?? []
    }

    var offeredYears: [Int] {
        return SchoolYear.offeredStartingYears(on: today)
    }

    /// The courses that are ticked, with the year each is filed under.
    var requests: [ReferenceImporter.Request] {
        var result: [ReferenceImporter.Request] = []
        for course in courses where ticked.contains(course.id) && course.problem == nil {
            result.append(ReferenceImporter.Request(
                course: course, schoolYear: schoolYear(for: course)
            ))
        }
        return result
    }

    /// What is wrong with a course as the choices stand, by folder name.
    ///
    /// The same rule the importer applies, said before the teacher presses
    /// the button rather than afterwards — and said **per row**, because one
    /// course that clashes must not stop the other three. That is the
    /// contract's own `oneCourseFailingDoesNotStopTheRest`, and disabling the
    /// button for all of them put it out of a teacher's reach.
    var troubleByCourse: [String: String] {
        var years: [String: Int?] = [:]
        for course in courses {
            // `.some` on purpose: assigning a bare nil to a dictionary whose
            // values are optional REMOVES the key, and "no year" is a year.
            years[course.id] = .some(schoolYear(for: course))
        }
        return ImportCoursesForReferenceSheet.troubleByCourse(
            courses: courses,
            ticked: ticked,
            years: years,
            onTheShelf: workspace.shelvedReferenceCourses(on: today)
        )
    }

    /// The rule behind `troubleByCourse`, with everything it reads passed in,
    /// so a test can pin which sentence a row gets.
    ///
    /// A clash with a course already ON THE SHELF says so
    /// (`codeAlreadyInThatYear`). A clash only with a row ticked ABOVE this
    /// one in the same sheet must not: nothing is kept yet, so "You already
    /// have…" would be false. Two sections of an older-layout course say they
    /// are sections; any other pair — `ICD2O-Exemplars`, which sorts above S1
    /// and takes its year from its pages, is the measured one — says the row
    /// above is also ticked for that year (`alsoTickedForThatYear`).
    static func troubleByCourse(
        courses: [ReferenceImportSource.FoundCourse],
        ticked: Set<String>,
        years: [String: Int?],
        onTheShelf: [ReferenceCourseRule.Shelved]
    ) -> [String: String] {
        var result: [String: String] = [:]
        var shelved: [ReferenceCourseRule.Shelved] = onTheShelf
        var tickedAbove: [ReferenceImportSource.FoundCourse] = []
        for course in courses {
            if let problem = course.problem {
                result[course.id] = problem
                continue
            }
            guard ticked.contains(course.id) else {
                continue
            }
            let year: Int? = years[course.id] ?? nil
            if let trouble = ReferenceCourseRule.trouble(
                placing: course.courseCode, inYear: year, among: shelved
            ) {
                let clashesOnlyInThisSheet: Bool = ReferenceCourseRule.trouble(
                    placing: course.courseCode, inYear: year, among: onTheShelf
                ) == nil
                var rowAbove: ReferenceImportSource.FoundCourse?
                if clashesOnlyInThisSheet {
                    let code: String = CourseCodeRule.normalized(course.courseCode)
                    for other in tickedAbove {
                        let otherYear: Int? = years[other.id] ?? nil
                        if rowAbove == nil && CourseCodeRule.normalized(other.courseCode) == code && otherYear == year {
                            rowAbove = other
                        }
                    }
                }
                guard let above = rowAbove else {
                    result[course.id] = trouble.sentence
                    continue
                }
                let bothAreSections: Bool = (course.olderLayout?.names.looksLikeAClass ?? false)
                    && (above.olderLayout?.names.looksLikeAClass ?? false)
                if bothAreSections {
                    result[course.id] = ReferenceImportWording.olderLayoutAnotherSectionOfTheSameCourse(
                        folder: above.folderName
                    )
                } else {
                    result[course.id] = ReferenceImportWording.alsoTickedForThatYear(
                        folder: above.folderName, course: CourseCodeRule.normalized(course.courseCode)
                    )
                }
                continue
            }
            // Counted as taken for the rows below it, exactly as the importer
            // counts a course it has just brought across.
            shelved.append(ReferenceCourseRule.Shelved(
                displayCode: course.courseCode, schoolYear: year, folderName: course.folderName
            ))
            tickedAbove.append(course)
        }
        return result
    }

    /// True when any row is an older-layout class, so the sheet says what
    /// is left behind of those.
    var hasOlderLayoutClasses: Bool {
        for course in courses where course.olderLayout != nil {
            return true
        }
        return false
    }

    /// What to say under the list when nothing can be imported at all.
    var entryProblem: String? {
        if requests.isEmpty {
            return ReferenceImportWording.tickSomething
        }
        if canImport {
            return nil
        }
        return ReferenceImportWording.tickSomething
    }

    /// True while at least one ticked course can actually come across.
    var canImport: Bool {
        let trouble: [String: String] = troubleByCourse
        for request in requests where trouble[request.course.id] == nil {
            return true
        }
        return false
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ReferenceImportWording.title)
                .font(.headline)

            switch stage {
            case .reading:
                readingView
            case .refused(let sentence):
                refusedView(sentence)
            case .choosing:
                choosingView
            case .copying:
                copyingView
            case .done:
                doneView
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            await readTheFolder()
        }
        .fileImporter(
            isPresented: $isChoosingShared,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let folderURL):
                chooseShared(folderURL)
            case .failure:
                break
            }
        }
        .fileDialogDefaultDirectory(folderBesideTheChosenClass)
    }

    // MARK: - The states

    var readingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(chosenURL.lastPathComponent)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
        }
    }

    func refusedView(_ sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sentence)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("importRefusal")
            HStack {
                Spacer()
                Button("OK", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    var choosingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ReferenceImportWording.explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(courses) { course in
                        courseRow(course)
                    }
                }
            }
            .frame(maxHeight: 260)

            Text(ReferenceImportWording.builtWebsitesAreNotCopied)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasOlderLayoutClasses {
                Text(ReferenceImportWording.olderLayoutAddOnsAreLeftBehind)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("importAddOnsNote")
            }

            // The calm note, said where the teacher is deciding rather than
            // after the fact. No icon, and no "cannot".
            VStack(alignment: .leading, spacing: 4) {
                Text(ReferenceWording.pagesAreLocked)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let entryProblem {
                Text(entryProblem)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("importProblem")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button(ReferenceImportWording.importButton) {
                    startImporting()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
                .accessibilityIdentifier("importButton")
            }
        }
    }

    func courseRow(_ course: ReferenceImportSource.FoundCourse) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Toggle(isOn: tickBinding(for: course)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.courseCode)
                        .font(.body.bold())
                    if !course.courseName.isEmpty {
                        Text(course.courseName)
                            .foregroundStyle(.secondary)
                    }
                    Text(ReferenceImportWording.courseSummary(
                        sections: course.sectionNumbers.count,
                        pages: course.pageCount,
                        bytes: course.byteCount
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    // Why this one cannot come across, beside the row it is
                    // about rather than as one sentence under the list.
                    if let trouble = troubleByCourse[course.id] {
                        Text(trouble)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("importTrouble-\(course.folderName)")
                    }

                    if course.olderLayout != nil {
                        olderLayoutLines(course)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .disabled(course.problem != nil)
            .accessibilityIdentifier("importTick-\(course.folderName)")

            Spacer()

            Picker(ReferenceImportWording.schoolYearLabel, selection: yearBinding(for: course)) {
                ForEach(offeredYears, id: \.self) { year in
                    Text(SchoolYear.label(forStartingYear: year)).tag(Int?.some(year))
                }
                Text(SchoolYear.otherGroupName).tag(Int?.none)
            }
            .labelsHidden()
            .frame(width: 120)
            .disabled(!ticked.contains(course.id))
            .accessibilityIdentifier("importYear-\(course.folderName)")
        }
    }

    /// Under an older-layout row: where its shared pages come from (or that
    /// they will be missing), any warning or refusal about a folder chosen
    /// by hand, the note beside a second section of the same course, and the
    /// button that chooses the shared folder.
    @ViewBuilder
    func olderLayoutLines(_ course: ReferenceImportSource.FoundCourse) -> some View {
        if let facts = course.olderLayout {
            if let sentence = OlderCourseLayout.sentence(about: facts.shared) {
                let isShort: Bool = facts.shared.state == .notFound || facts.shared.state == .partlyFound
                Text(sentence)
                    .font(.callout)
                    .foregroundStyle(isShort ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("importShared-\(course.folderName)")
            }
            if let warning = facts.chosenWarning {
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("importSharedWarning-\(course.folderName)")
            }
            if let problem = sharedPickProblem[course.id] {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("importSharedProblem-\(course.folderName)")
            }
            if !ticked.contains(course.id), course.problem == nil,
               let sibling = tickedSibling(of: course, before: false) {
                Text(ReferenceImportWording.olderLayoutAnotherSectionOfTheSameCourse(folder: sibling.folderName))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("importSibling-\(course.folderName)")
            }
            if facts.shared.linkCount > 0 && course.problem == nil {
                Button(ReferenceImportWording.olderLayoutChooseSharedButton) {
                    choosingSharedFor = course.id
                    isChoosingShared = true
                }
                .controlSize(.small)
                .accessibilityIdentifier("importChooseShared-\(course.folderName)")
            }
        }
    }

    var copyingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let progress {
                Text(ReferenceImportWording.copying(course: progress.courseCode))
                ProgressView(
                    value: Double(progress.copiedBytes),
                    total: Double(max(progress.totalBytes, 1))
                )
                Text(ReferenceImportWording.copiedSoFar(
                    bytes: progress.copiedBytes, of: progress.totalBytes
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            HStack {
                Spacer()
                Button("Stop", role: .cancel) {
                    run?.cancel()
                }
                .accessibilityIdentifier("importStopButton")
            }
        }
    }

    var doneView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ReferenceImportWording.doneTitle)
                .font(.body.bold())

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(outcomes.enumerated()), id: \.offset) { _, outcome in
                    Text(ImportCoursesForReferenceSheet.line(for: outcome))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("importSummary")

            Text(ReferenceImportWording.whereTheyAre)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(ReferenceImportWording.builtWebsitesAreNotCopied)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasOlderLayoutClasses {
                Text(ReferenceImportWording.olderLayoutAddOnsAreLeftBehind)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(ReferenceWording.pagesAreLocked)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("importDoneButton")
            }
        }
    }

    /// One line of the summary, for one course.
    static func line(for outcome: ReferenceImporter.Outcome) -> String {
        switch outcome {
        case .imported(let made):
            var year: String = ReferenceImportWording.noSchoolYear
            if let startingYear = made.schoolYear {
                year = SchoolYear.label(forStartingYear: startingYear)
            }
            return ReferenceImportWording.imported(
                course: made.displayCode, year: year, sections: made.sectionCount
            )
        case .importedWithSomethingMissing(let made, let sharedPagesMissing, let leftOut):
            var year: String = ReferenceImportWording.noSchoolYear
            if let startingYear = made.schoolYear {
                year = SchoolYear.label(forStartingYear: startingYear)
            }
            var line: String
            if sharedPagesMissing {
                line = ReferenceImportWording.olderLayoutImportedWithSharedMissing(
                    course: made.displayCode, year: year
                )
            } else {
                line = ReferenceImportWording.imported(
                    course: made.displayCode, year: year, sections: made.sectionCount
                ) + "."
            }
            if !leftOut.isEmpty {
                line += " " + ReferenceImportWording.olderLayoutLeftOut(count: leftOut.count, names: leftOut)
            }
            return line
        case .notImported(let course, let reason):
            return ReferenceImportWording.couldNotImport(course: course, reason: reason)
        case .stopped:
            return ReferenceImportWording.stopped
        }
    }

    // MARK: - Initializer

    init(chosenURL: URL, today: CalendarDay = CalendarDay.today(), onImport: @escaping ([String]) -> Void) {
        self.chosenURL = chosenURL
        self.today = today
        self.onImport = onImport
    }

    // MARK: - Functions

    /// Reads the chosen folder, off the main actor, and decides what the
    /// sheet shows.
    func readTheFolder() async {
        guard stage == .reading else {
            return
        }
        let outcome: ReferenceImportSource.Outcome = await ReferenceImportSource.read(
            chosen: chosenURL,
            workingFolderURL: workspace.workspaceURL,
            leavingBehind: ReferenceImporter.leftBehindNames,
            on: today
        )
        switch outcome {
        case .refused(let refusal):
            stage = .refused(refusal.sentence)
        case .found(let found):
            source = found
            ticked = found.tickedWhenOpened
            stage = .choosing
        }
    }

    /// The year chosen for a course, or the one proposed for it.
    func schoolYear(for course: ReferenceImportSource.FoundCourse) -> Int? {
        if let chosen = schoolYears[course.id] {
            return chosen
        }
        return course.suggestedSchoolYear
    }

    func tickBinding(for course: ReferenceImportSource.FoundCourse) -> Binding<Bool> {
        return Binding(
            get: { return ticked.contains(course.id) },
            set: { isOn in
                if isOn {
                    ticked.insert(course.id)
                } else {
                    ticked.remove(course.id)
                }
            }
        )
    }

    func yearBinding(for course: ReferenceImportSource.FoundCourse) -> Binding<Int?> {
        return Binding(
            get: { return schoolYear(for: course) },
            set: { year in schoolYears[course.id] = year }
        )
    }

    /// Another older-layout section of the same course, ticked for the same
    /// school year — the row this one would clash with. `before` limits it
    /// to rows ABOVE this one, the order the shelf rule counts them in.
    func tickedSibling(
        of course: ReferenceImportSource.FoundCourse,
        before: Bool
    ) -> ReferenceImportSource.FoundCourse? {
        // Only a class NAMED as a section of the course (`ICS3U-S2-2023-24`)
        // is "another section" of it; `ICD2O-Exemplars` is not, even when its
        // pages' dates give it the same year.
        guard let facts = course.olderLayout, facts.names.looksLikeAClass else {
            return nil
        }
        let code: String = CourseCodeRule.normalized(course.courseCode)
        let year: Int? = schoolYear(for: course)
        for other in courses {
            if other.id == course.id {
                if before {
                    return nil
                }
                continue
            }
            guard let otherFacts = other.olderLayout, otherFacts.names.looksLikeAClass,
                  ticked.contains(other.id), other.problem == nil else {
                continue
            }
            if CourseCodeRule.normalized(other.courseCode) == code && schoolYear(for: other) == year {
                return other
            }
        }
        return nil
    }

    /// Where the shared-folder chooser opens: beside the class it is for.
    var folderBesideTheChosenClass: URL? {
        guard let choosingSharedFor else {
            return nil
        }
        for course in courses where course.id == choosingSharedFor {
            return course.directoryURL.deletingLastPathComponent()
        }
        return nil
    }

    /// The teacher chose a shared folder for one row: check it off the main
    /// actor and either re-measure that row with it or say beside the row
    /// why it cannot be the one.
    func chooseShared(_ folderURL: URL) {
        guard let rowID = choosingSharedFor else {
            return
        }
        var chosenCourse: ReferenceImportSource.FoundCourse?
        for course in courses where course.id == rowID {
            chosenCourse = course
        }
        guard let course = chosenCourse else {
            return
        }
        let openFolderURL: URL? = workspace.workspaceURL
        let day: CalendarDay = today
        Task { @MainActor in
            let choice: ReferenceImportSource.SharedChoice = await ReferenceImportSource.chooseShared(
                for: course,
                sharedFolderURL: folderURL,
                workingFolderURL: openFolderURL,
                leavingBehind: ReferenceImporter.leftBehindNames,
                on: day
            )
            switch choice {
            case .refused(let sentence):
                sharedPickProblem[rowID] = sentence
            case .accepted(let remeasured):
                sharedPickProblem[rowID] = nil
                guard var updated = source else {
                    return
                }
                var index: Int = 0
                for existing in updated.courses {
                    if existing.id == rowID {
                        updated.courses[index] = remeasured
                    }
                    index += 1
                }
                source = updated
            }
        }
    }

    func startImporting() {
        guard let coursesDirectoryURL = workspace.coursesDirectoryURL,
              let source else {
            return
        }
        let chosen: [ReferenceImporter.Request] = requests
        var folderNames: [String] = []
        for course in workspace.courses {
            folderNames.append(course.code)
        }
        let shelved: [ReferenceCourseRule.Shelved] = workspace.shelvedReferenceCourses(on: today)
        stage = .copying

        run = Task { @MainActor in
            let results: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
                chosen,
                into: coursesDirectoryURL,
                existingFolderNames: folderNames,
                alreadyShelved: shelved,
                from: source.rootURL,
                progress: { step in
                    progress = step
                }
            )
            outcomes = results
            stage = .done

            var landed: [String] = []
            for outcome in results {
                if case .imported(let made) = outcome {
                    landed.append(made.folderName)
                }
                if case .importedWithSomethingMissing(let made, _, _) = outcome {
                    landed.append(made.folderName)
                }
            }
            onImport(landed)
        }
    }
}
