import SwiftUI
import Observation

/// Everything one of the Section menu's sheets shows and does, apart from the
/// drawing (#457 batch B) — the arrangement `LinksChecklistSheetModel` uses.
///
/// One sheet for every function that needs one, moving through stages:
/// CHOOSING (which pages, which day, where to make room), then — for Publish
/// Pages… only — the question about classes dated later (#475), then the
/// PLAN (the plan twin's own card, `forTheCard`: the multi-page change is
/// seen before it happens, which is the assistant's plan card in the
/// menu's form), then WORKING, then FINISHED (what the tool said). A refusal
/// at the plan goes straight to FINISHED with OK alone, as the assistant
/// shows a refusing twin with no Go.
///
/// The same sheet asks the #475 question at Deploy (`kind == .laterClassesAtDeploy`),
/// shows the class dates sheet when a function needs dates first
/// (`.classDates`), and shows the answer of a function that has no sheet of
/// its own (`.result`: Undo Last Change, a refused Rebuild Preview, Add Next
/// Class). One `.sheet` rather than several, because a view presents one
/// sheet at a time anyway and modelling that is what keeps them in order.
@Observable
@MainActor
final class SectionVerbSheetModel: Identifiable {

    // MARK: - Types

    enum Kind: Equatable {
        case publishPages
        case hidePages
        case publishClass
        case reDateClasses
        case makeRoom
        case laterClassesAtDeploy
        case classDates
        case result
    }

    enum Stage: Equatable {
        case choosing
        case askingAboutLaterClasses
        case planned
        case working
        case finished
    }

    /// A page the teacher can tick.
    struct PageRow: Identifiable, Equatable {

        // MARK: - Stored properties

        /// The name the call carries: folder, then file name
        /// (`SectionVerbs.name(ofPageAt:in:)`).
        let name: String

        /// What the teacher sees the page called.
        let title: String

        /// Where it is, in the teacher's words.
        let folder: String

        let fileURL: URL
        let isClass: Bool
        let date: CalendarDay?

        // MARK: - Computed properties

        var id: String {
            return name
        }
    }

    /// A class page Make Room for Classes… can put the new class in front of.
    struct ClassRow: Identifiable, Equatable {

        // MARK: - Stored properties

        let title: String
        let unit: Int
        let day: Int

        // MARK: - Computed properties

        var id: String {
            return title
        }
    }

    // MARK: - Stored properties

    let id: UUID = UUID()
    let kind: Kind
    let course: Course
    let sectionNumber: Int
    let title: String
    let item: SubjectMenuRules.Item?

    var stage: Stage

    /// The page rows — hidden pages to publish, or visible ones to hide.
    var pageRows: [PageRow] = []
    var ticked: Set<String> = []
    var search: String = ""

    /// Publish Class for a Date…'s day.
    var day: Date = Date()

    /// Make Room for Classes…'s class, by title, and how many to make room for.
    var classRows: [ClassRow] = []
    var chosenClass: String = ""
    var howMany: Int = 1

    /// #475: the classes asked about, and the ones ticked to hide (all, to
    /// begin with). `nextClassDay` is the day they are after, as a row says
    /// a day.
    var laterClasses: [ClassesDatedLater.Flagged] = []
    var laterTicked: Set<String> = []
    var nextClassDay: String = ""

    /// The plan's card, or the tool's answer.
    var body: String = ""

    /// The call waiting on the default button at the plan.
    var pendingCall: AssistToolCall?

    /// The class dates sheet's reason line, and what runs once the dates are
    /// written down.
    var reason: String = ""
    var afterTheDates: (() -> Void)?

    /// The #475 question at Deploy: the teacher's answer goes here, once,
    /// and where it was asked from, for the trail.
    var answerAtDeploy: ((LaterClassesAnswer) -> Void)?
    var route: String = ""

    // MARK: - Computed properties

    var noun: ClassNoun {
        return course.configuration.classNoun
    }

    var courseName: String {
        return course.displayCode
    }

    /// The rows the search leaves showing, in order.
    var shownRows: [PageRow] {
        let wanted: String = search.trimmingCharacters(in: .whitespaces).lowercased()
        if wanted.isEmpty {
            return pageRows
        }
        var shown: [PageRow] = []
        for row in pageRows {
            if row.title.lowercased().contains(wanted) || row.folder.lowercased().contains(wanted) {
                shown.append(row)
            }
        }
        return shown
    }

    /// The pages ticked, in the rows' order.
    var tickedRows: [PageRow] {
        var chosen: [PageRow] = []
        for row in pageRows where ticked.contains(row.name) {
            chosen.append(row)
        }
        return chosen
    }

    /// The sentence above the choice.
    var intro: String {
        switch kind {
        case .publishPages:
            if pageRows.isEmpty {
                return AssistWording.menuNoHiddenPages(course: courseName, section: String(sectionNumber))
            }
            return AssistWording.menuPickPagesToPublish
        case .hidePages:
            if pageRows.isEmpty {
                return AssistWording.menuNoVisiblePages(course: courseName, section: String(sectionNumber))
            }
            return AssistWording.menuPickPagesToHide
        case .publishClass:
            return AssistWording.menuPickClassDay(noun: noun)
        case .makeRoom:
            return AssistWording.menuMakeRoomAt(noun: noun)
        default:
            return ""
        }
    }

    /// The default button's title at each stage.
    var defaultButtonTitle: String {
        switch stage {
        case .choosing:
            return AssistWording.menuContinueButton
        case .askingAboutLaterClasses:
            if kind == .laterClassesAtDeploy {
                return AssistWording.hideTickedAndDeployButton
            }
            if laterTicked.isEmpty {
                return AssistWording.publishThemAllButton
            }
            return AssistWording.leaveOutAndContinueButton(count: laterTicked.count)
        case .planned:
            switch kind {
            case .hidePages:
                return AssistWording.menuHideButton
            case .reDateClasses:
                return AssistWording.menuReDateButton
            case .makeRoom:
                return AssistWording.menuMakeRoomButton
            default:
                return AssistWording.menuPublishButton
            }
        case .working, .finished:
            return AssistWording.menuDoneButton
        }
    }

    /// Whether the default button can be pressed now.
    var defaultButtonIsEnabled: Bool {
        switch stage {
        case .choosing:
            switch kind {
            case .publishPages, .hidePages:
                return !ticked.isEmpty
            case .makeRoom:
                return !chosenClass.isEmpty
            default:
                return true
            }
        case .working:
            return false
        default:
            return true
        }
    }

    // MARK: - Initializer

    init(kind: Kind, course: Course, sectionNumber: Int, title: String,
         item: SubjectMenuRules.Item?, stage: Stage = .choosing) {
        self.kind = kind
        self.course = course
        self.sectionNumber = sectionNumber
        self.title = title
        self.item = item
        self.stage = stage
    }

    // MARK: - Functions

    /// Publish Pages… (the hidden pages) or Hide Pages… (the visible ones).
    static func choosingPages(publishing: Bool, course: Course, sectionNumber: Int, workspaceURL: URL?) -> SectionVerbSheetModel {
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: publishing ? .publishPages : .hidePages,
            course: course, sectionNumber: sectionNumber,
            title: publishing
                ? AssistWording.menuPublishPagesTitle(course: course.displayCode, section: String(sectionNumber))
                : AssistWording.menuHidePagesTitle(course: course.displayCode, section: String(sectionNumber)),
            item: publishing ? .publishPages : .hidePages
        )
        model.pageRows = rows(publishing: publishing, course: course, sectionNumber: sectionNumber, workspaceURL: workspaceURL)
        return model
    }

    /// The pages a teacher may tick: classes first, by date, then the rest by
    /// folder and title — the order `ClassPages.pagesTheAssistantLists`
    /// gives, which leaves out the How I Teach page (#209). A page whose
    /// flag the app cannot read is offered to BOTH lists: publishing or hiding
    /// it writes the flag out in full, which is how such a page is mended.
    static func rows(publishing: Bool, course: Course, sectionNumber: Int, workspaceURL: URL?) -> [PageRow] {
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: sectionNumber, in: course, workspaceURL: workspaceURL
        )
        var classRows: [PageRow] = []
        var otherRows: [PageRow] = []
        for page in graph.pages {
            let offered: Bool = publishing
                ? (!page.isVisibleToStudents || !page.visibilityIsCertain)
                : page.isVisibleToStudents
            if !offered {
                continue
            }
            let row: PageRow = PageRow(
                name: SectionVerbs.name(ofPageAt: page.fileURL, in: course),
                title: page.displayTitle,
                folder: StartOfYearPageNaming.folder(
                    of: page.fileURL, courseDirectoryURL: course.directoryURL, courseCode: course.code
                ),
                fileURL: page.fileURL,
                isClass: page.isClassPage,
                date: page.date
            )
            if row.isClass {
                classRows.append(row)
            } else {
                otherRows.append(row)
            }
        }
        classRows.sort { first, second in
            switch (first.date, second.date) {
            case (let left?, let right?):
                if left != right {
                    return left < right
                }
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                break
            }
            return first.title.lowercased() < second.title.lowercased()
        }
        otherRows.sort { first, second in
            if first.folder.lowercased() != second.folder.lowercased() {
                return first.folder.lowercased() < second.folder.lowercased()
            }
            return first.title.lowercased() < second.title.lowercased()
        }
        var all: [PageRow] = classRows
        for row in otherRows {
            all.append(row)
        }
        return all
    }

    /// The classes Make Room for Classes… can put a new one in front of:
    /// every class page named with numbers, in order.
    static func classRows(course: Course, sectionNumber: Int) -> [ClassRow] {
        var found: [ClassRow] = []
        for page in ClassPages.list(forSection: sectionNumber, in: course) {
            guard let numbers = page.unitAndDay else {
                continue
            }
            found.append(ClassRow(title: page.title, unit: numbers.unit, day: numbers.day))
        }
        found.sort { first, second in
            if first.unit != second.unit {
                return first.unit < second.unit
            }
            return first.day < second.day
        }
        return found
    }

    /// The day Publish Class for a Date… offers first: the section's next
    /// class day from its class dates, or tomorrow when it has none.
    static func firstDayOffered(course: Course, sectionNumber: Int, today: CalendarDay) -> CalendarDay {
        let tomorrow: CalendarDay = AssistToolRunner.shifting(today, byDays: 1) ?? today
        guard let timetable = try? SectionTimetableStore.read(forSection: sectionNumber, in: course, today: today) else {
            return tomorrow
        }
        for day in timetable.dates where day > today {
            return day
        }
        return tomorrow
    }

    /// Noon on `day` in this Mac's own time zone — what the date picker is
    /// given, so reading it back with `CalendarDay.today(_:)` names the same
    /// day whatever the zone.
    static func noon(of day: CalendarDay) -> Date {
        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        var components: DateComponents = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 12
        return calendar.date(from: components) ?? Date()
    }

    func binding(for row: PageRow) -> Binding<Bool> {
        return Binding(
            get: { return self.ticked.contains(row.name) },
            set: { isOn in
                if isOn {
                    self.ticked.insert(row.name)
                } else {
                    self.ticked.remove(row.name)
                }
            }
        )
    }

    func laterBinding(for page: ClassesDatedLater.Flagged) -> Binding<Bool> {
        return Binding(
            get: { return self.laterTicked.contains(page.place) },
            set: { isOn in
                if isOn {
                    self.laterTicked.insert(page.place)
                } else {
                    self.laterTicked.remove(page.place)
                }
            }
        )
    }

    /// The #475 question's rows: the classes, all ticked to begin with.
    func ask(about flagged: [ClassesDatedLater.Flagged], nextDay: CalendarDay?) {
        laterClasses = flagged
        laterTicked = []
        for page in flagged {
            laterTicked.insert(page.place)
        }
        if let nextDay {
            nextClassDay = AssistWording.laterClassesDay(weekday: nextDay.weekdayName, date: nextDay.text)
        }
        stage = .askingAboutLaterClasses
    }

    /// The classes asked about that are UNticked: kept published.
    var laterKept: [ClassesDatedLater.Flagged] {
        var kept: [ClassesDatedLater.Flagged] = []
        for page in laterClasses where !laterTicked.contains(page.place) {
            kept.append(page)
        }
        return kept
    }

    /// The classes asked about that are ticked.
    var laterHidden: [ClassesDatedLater.Flagged] {
        var hidden: [ClassesDatedLater.Flagged] = []
        for page in laterClasses where laterTicked.contains(page.place) {
            hidden.append(page)
        }
        return hidden
    }
}

/// The drawing of `SectionVerbSheetModel`.
struct SectionVerbSheet: View {

    // MARK: - Stored properties

    var model: SectionVerbSheetModel

    /// The default button, at every stage — the section window decides what
    /// it does.
    var pressDefault: () -> Void

    /// Cancel, at every stage it is offered.
    var cancel: () -> Void

    /// Keep All and Deploy, beside the default at #475's question (#475,
    /// the director's ruling on the implementation review's finding 1).
    var keepAll: () -> Void = {}

    /// The window's runner, read for the copy being saved before a change
    /// while the sheet waits (#351) — read here, in the sheet's own body, so
    /// the line follows it.
    var verbs: SectionVerbs?

    static let tallestList: CGFloat = 340

    // MARK: - Body

    var body: some View {
        if model.kind == .classDates {
            SectionScheduleSheet(
                course: model.course,
                sectionNumber: model.sectionNumber,
                reason: model.reason,
                onRemembered: { _ in
                    model.afterTheDates?()
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // The title band every sheet wears since #457's HIG sweep:
                // `.headline`, leading, 52 points tall, the sheet's own side
                // margin — written out here because batch C's `SheetTitle`
                // (`.sheetTitle(_:)`) is not on this branch; when the two
                // merge, this becomes `.sheetTitle(title)`.
                Text(sheetTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                VStack(alignment: .leading, spacing: 12) {
                    content
                    buttons
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(width: 560)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sectionVerbSheet")
            // #475's question at Deploy, gone without an answer — the window
            // closed under it, say — is a Cancel: nothing deploys.
            .onDisappear {
                if model.kind == .laterClassesAtDeploy {
                    model.answerAtDeploy?(.cancelled)
                }
            }
        }
    }

    // MARK: - Parts

    @ViewBuilder
    var content: some View {
        switch model.stage {
        case .choosing:
            choosing
        case .askingAboutLaterClasses:
            laterClasses
        case .planned, .finished:
            CappedScrollArea(cap: SectionVerbSheet.tallestList) {
                Text(model.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sectionVerbSheetBody")
            }
        case .working:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                if let courseBeingBackedUp = verbs?.courseBeingBackedUp {
                    Text(AssistWording.menuSavingACopy(course: courseBeingBackedUp))
                } else {
                    Text(AssistWording.menuWorking)
                }
            }
        }
    }

    @ViewBuilder
    var choosing: some View {
        Text(model.intro)
            .fixedSize(horizontal: false, vertical: true)
        switch model.kind {
        case .publishPages, .hidePages:
            if !model.pageRows.isEmpty {
                TextField(AssistWording.menuFindAPage, text: Binding(
                    get: { return model.search },
                    set: { text in model.search = text }
                ))
                .borderedTextField()
                .accessibilityIdentifier("sectionVerbSheetSearch")
                CappedScrollArea(cap: SectionVerbSheet.tallestList) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.shownRows) { row in
                            Toggle(isOn: model.binding(for: row)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.title)
                                    Text(secondLine(for: row))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel(row.title)
                            .accessibilityValue(secondLine(for: row))
                            .accessibilityIdentifier("sectionVerbRow-\(row.name)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .publishClass:
            DatePicker("", selection: Binding(
                get: { return model.day },
                set: { day in model.day = day }
            ), displayedComponents: [.date])
            .labelsHidden()
            .datePickerStyle(.field)
            .accessibilityIdentifier("sectionVerbSheetDay")
        case .makeRoom:
            Picker("", selection: Binding(
                get: { return model.chosenClass },
                set: { title in model.chosenClass = title }
            )) {
                ForEach(model.classRows) { row in
                    Text(row.title).tag(row.title)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("sectionVerbSheetClass")
            Stepper(value: Binding(
                get: { return model.howMany },
                set: { count in model.howMany = count }
            ), in: 1...10) {
                Text("\(model.howMany)")
                    .monospacedDigit()
            }
            .accessibilityIdentifier("sectionVerbSheetHowMany")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    var laterClasses: some View {
        Text(model.kind == .laterClassesAtDeploy
             ? AssistWording.laterClassesAtDeploy(nextDay: model.nextClassDay, noun: model.noun)
             : AssistWording.laterClassesAtPublish(nextDay: model.nextClassDay, noun: model.noun))
            .fixedSize(horizontal: false, vertical: true)
        CappedScrollArea(cap: SectionVerbSheet.tallestList) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.laterClasses) { page in
                    Toggle(isOn: model.laterBinding(for: page)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(page.title)
                            Text(AssistWording.laterClassesDay(weekday: page.date.weekdayName, date: page.date.text))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(page.title)
                    .accessibilityIdentifier("laterClassRow-\(page.place)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Text(AssistWording.laterClassesKeptNote(noun: model.noun))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    var sheetTitle: String {
        if model.stage == .askingAboutLaterClasses {
            return AssistWording.laterClassesTitle(noun: model.noun)
        }
        return model.title
    }

    var buttons: some View {
        HStack {
            Spacer()
            if model.stage != .finished {
                Button(AssistWording.menuCancelButton, role: .cancel) {
                    cancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(model.stage == .working)
                .accessibilityIdentifier("sectionVerbSheetCancel")
            }
            if model.kind == .laterClassesAtDeploy && model.stage == .askingAboutLaterClasses {
                Button(AssistWording.keepAllAndDeployButton) {
                    keepAll()
                }
                .accessibilityIdentifier("sectionVerbSheetKeepAll")
            }
            defaultButton
        }
    }

    /// The default button takes Return and wears the accent ONLY while it can
    /// be pressed; otherwise it is a plain grey button with no key — the
    /// shape #364 gave Course Settings' Save, and batch C's
    /// `defaultButton(isEnabled:)` makes one modifier (#457's HIG sweep).
    /// Written out here because that helper is not on this branch; when the
    /// two merge, this becomes `.defaultButton(isEnabled:)`.
    @ViewBuilder
    var defaultButton: some View {
        if model.defaultButtonIsEnabled {
            Button(model.defaultButtonTitle) {
                pressDefault()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("sectionVerbSheetDefault")
        } else {
            Button(model.defaultButtonTitle) {
                pressDefault()
            }
            .disabled(true)
            .accessibilityIdentifier("sectionVerbSheetDefault")
        }
    }

    // MARK: - Functions

    func secondLine(for row: SectionVerbSheetModel.PageRow) -> String {
        if let date = row.date, row.isClass {
            return row.folder + " · " + AssistWording.laterClassesDay(weekday: date.weekdayName, date: date.text)
        }
        return row.folder
    }
}
