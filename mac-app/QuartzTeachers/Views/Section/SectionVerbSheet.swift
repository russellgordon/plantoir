import SwiftUI
import Observation

/// Everything one of the Section menu's sheets shows and does, apart from the
/// drawing (#457 batch B) — the arrangement `LinksChecklistSheetModel` uses.
///
/// One sheet for every function that needs one, moving through stages:
/// CHOOSING (which pages, which day, where to make room), then — for Publish
/// Pages… only — the question about classes dated later (#475), then the
/// PLAN (the multi-page change seen before it happens, which is the
/// assistant's plan card in the menu's form: for Publish Pages…, Hide
/// Pages… and Publish Class for a Date…, a summary over a table of every
/// page, the plan twin's `planTable` (#524); for Re-date and Make Room, the
/// card's own text, `forTheCard`), then WORKING, then FINISHED (what the
/// tool said). A refusal
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

    /// The plan as rows, when the plan is a page plan (#524) — shown at
    /// `.planned` in place of `body`.
    var planTable: AssistPlanTable?

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

    /// Space on the picker's selected row (#608): ticks it, or unticks it.
    /// Only a row the search leaves showing — a row the teacher cannot see
    /// is never changed by a key.
    func flipTick(ofRowWithID id: String?) {
        for row in shownRows where row.id == id {
            if ticked.contains(row.name) {
                ticked.remove(row.name)
            } else {
                ticked.insert(row.name)
            }
        }
    }

    /// Space on the later-classes list's selected row (#608).
    func flipLaterTick(ofClassWithID id: String?) {
        for page in laterClasses where page.id == id {
            if laterTicked.contains(page.place) {
                laterTicked.remove(page.place)
            } else {
                laterTicked.insert(page.place)
            }
        }
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

    /// The plan table's order: plan order to begin with; a column header
    /// sorts by that column (#524, the `AllBackupsView` precedent).
    @State var planSortOrder: [KeyPathComparator<AssistPlanTable.Row>] = [KeyPathComparator(\.position)]

    /// The picker's and the later-classes list's selected row (#608): what
    /// Space ticks. Selecting a row is not ticking it.
    @State var pickedRowID: String? = nil
    @State var pickedLaterClassID: String? = nil

    static let tallestList: CGFloat = 340

    /// How many rows the picker and the later-classes list show before the
    /// table scrolls inside itself (#608): twelve, as the plan that follows
    /// shows, so the two steps of one flow are the same height — 318 pt,
    /// under the 340 the list of checkboxes was capped at.
    static let mostPickerRowsShown: Int = 12

    /// How many plan rows show before the table scrolls inside itself, and
    /// how tall the notes under it may grow: one height budget for the plan
    /// stage (#524), so a unit's worth of pages and a long note together
    /// still leave Cancel and Publish on a 13-inch screen.
    static let mostPlanRowsShown: Int = 12
    static let tallestPlanNotes: CGFloat = 120

    // MARK: - Computed properties

    /// The plan table's rows, in the order the teacher sorted them.
    var sortedPlanRows: [AssistPlanTable.Row] {
        guard let table = model.planTable else {
            return []
        }
        return table.rows.sorted(using: planSortOrder)
    }

    /// The table's height: every row up to `mostPlanRowsShown`, then it
    /// scrolls inside itself. A `Table` has no natural height.
    var planTableHeight: CGFloat {
        var shown: Int = model.planTable?.rows.count ?? 0
        if shown > SectionVerbSheet.mostPlanRowsShown {
            shown = SectionVerbSheet.mostPlanRowsShown
        }
        return ListTableMetrics.height(forRowCount: shown, showsHeader: true)
    }

    /// The picker's height (#608): counted from EVERY page offered, not the
    /// ones the search leaves showing, so the sheet stays still while the
    /// teacher types; up to `mostPickerRowsShown`, then it scrolls inside.
    var pickerTableHeight: CGFloat {
        var shown: Int = model.pageRows.count
        if shown > SectionVerbSheet.mostPickerRowsShown {
            shown = SectionVerbSheet.mostPickerRowsShown
        }
        return ListTableMetrics.height(forRowCount: shown, showsHeader: true)
    }

    /// The later-classes list's height (#608), the same way.
    var laterClassesTableHeight: CGFloat {
        var shown: Int = model.laterClasses.count
        if shown > SectionVerbSheet.mostPickerRowsShown {
            shown = SectionVerbSheet.mostPickerRowsShown
        }
        return ListTableMetrics.height(forRowCount: shown, showsHeader: true)
    }

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
            // The one sheet title shape (#457's HIG sweep, `SheetTitle`).
            VStack(alignment: .leading, spacing: 12) {
                content
                buttons
            }
            .padding([.horizontal, .bottom], 20)
            .sheetTitle(sheetTitle)
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
        case .planned where model.planTable != nil:
            planTable
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

    /// The page plan (#524): the summary, a read-only table with a row for
    /// every page, and the card's other sentences under it.
    @ViewBuilder
    var planTable: some View {
        if let table = model.planTable {
            Text(table.summary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sectionVerbSheetPlanSummary")
            // No `selection:`: the rows are read, not chosen.
            Table(sortedPlanRows, sortOrder: $planSortOrder) {
                TableColumn(AssistWording.menuPlanPageColumn, value: \.title) { (row: AssistPlanTable.Row) in
                    Text(row.title)
                        .help(row.title)
                }
                .width(min: 90, ideal: 130)
                TableColumn(AssistWording.menuPlanFolderColumn, value: \.folder) { (row: AssistPlanTable.Row) in
                    Text(row.folder)
                        .foregroundStyle(.secondary)
                        .help(row.folder)
                }
                .width(min: 80, ideal: 110)
                TableColumn(AssistWording.menuPlanChangeColumn, value: \.whatChanges) { (row: AssistPlanTable.Row) in
                    // A date move or a reason is long; the tooltip has it whole.
                    Text(row.whatChanges)
                        .help(row.whatChanges)
                }
                // The widest: it carries the longest words (a date move, a
                // reason). Three equal columns, as first drawn, cut it at
                // about twenty letters in the real 560-point sheet.
                .width(min: 180, ideal: 240)
            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: planTableHeight)
            .accessibilityIdentifier("sectionVerbSheetPlanTable")
            if !table.notes.isEmpty {
                CappedScrollArea(cap: SectionVerbSheet.tallestPlanNotes) {
                    VStack(alignment: .leading, spacing: 6) {
                        // By position: two notes may say the same words.
                        ForEach(0..<table.notes.count, id: \.self) { (position: Int) in
                            Text(table.notes[position])
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sectionVerbSheetPlanNotes")
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
                pickerTable
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

    /// The pages to tick (#608): a bordered, banded table — Page (with its
    /// checkbox), Folder and Date — the look of the plan that follows it, so
    /// the two steps of one flow look alike. A click on a box ticks it;
    /// Space ticks the selected row. Its rows are in the order `rows` gives
    /// (classes by date, then the rest by folder), and no header sorts them.
    var pickerTable: some View {
        Table(model.shownRows, selection: $pickedRowID) {
            TableColumn(AssistWording.menuPlanPageColumn) { (row: SectionVerbSheetModel.PageRow) in
                Toggle(row.title, isOn: model.binding(for: row))
                    .toggleStyle(.checkbox)
                    .lineLimit(1)
                    .help(row.title)
                    .accessibilityIdentifier("sectionVerbRow-\(row.name)")
            }
            .width(min: 90, ideal: 130)
            TableColumn(AssistWording.menuPlanFolderColumn) { (row: SectionVerbSheetModel.PageRow) in
                Text(row.folder)
                    .foregroundStyle(.secondary)
                    .help(row.folder)
            }
            .width(min: 80, ideal: 110, max: 140)
            TableColumn(AssistWording.menuPickDateColumn) { (row: SectionVerbSheetModel.PageRow) in
                Text(dateCell(for: row))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150, max: 180)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: pickerTableHeight)
        .onKeyPress(.space) {
            if pickedRowID == nil {
                return .ignored
            }
            model.flipTick(ofRowWithID: pickedRowID)
            return .handled
        }
        .accessibilityIdentifier("sectionVerbSheetPickerTable")
    }

    @ViewBuilder
    var laterClasses: some View {
        Text(model.kind == .laterClassesAtDeploy
             ? AssistWording.laterClassesAtDeploy(nextDay: model.nextClassDay, noun: model.noun)
             : AssistWording.laterClassesAtPublish(nextDay: model.nextClassDay, noun: model.noun))
            .fixedSize(horizontal: false, vertical: true)
        // The same shape as the picker (#608): a checkbox and the class's
        // title, then its day.
        Table(model.laterClasses, selection: $pickedLaterClassID) {
            TableColumn(AssistWording.menuPlanPageColumn) { (page: ClassesDatedLater.Flagged) in
                Toggle(page.title, isOn: model.laterBinding(for: page))
                    .toggleStyle(.checkbox)
                    .lineLimit(1)
                    .help(page.title)
                    .accessibilityIdentifier("laterClassRow-\(page.place)")
            }
            .width(min: 90, ideal: 130)
            TableColumn(AssistWording.menuPickDateColumn) { (page: ClassesDatedLater.Flagged) in
                Text(AssistWording.laterClassesDay(weekday: page.date.weekdayName, date: page.date.text))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150, max: 180)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: laterClassesTableHeight)
        .onKeyPress(.space) {
            if pickedLaterClassID == nil {
                return .ignored
            }
            model.flipLaterTick(ofClassWithID: pickedLaterClassID)
            return .handled
        }
        .accessibilityIdentifier("laterClassesTable")
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
    /// be pressed; otherwise it is a plain grey button with no key
    /// (`defaultButton(isEnabled:)`, #457's HIG sweep).
    var defaultButton: some View {
        Button(model.defaultButtonTitle) {
            pressDefault()
        }
        .defaultButton(isEnabled: model.defaultButtonIsEnabled)
        .accessibilityIdentifier("sectionVerbSheetDefault")
    }

    // MARK: - Functions

    /// The picker's Date cell: a class's day, as the later-classes question
    /// says it; nothing for a page that is not a class.
    func dateCell(for row: SectionVerbSheetModel.PageRow) -> String {
        if let date = row.date, row.isClass {
            return AssistWording.laterClassesDay(weekday: date.weekdayName, date: date.text)
        }
        return ""
    }
}
