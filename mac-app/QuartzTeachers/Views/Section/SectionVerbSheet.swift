import AppKit
import SwiftUI
import Observation

/// Everything one of the Section menu's sheets shows and does, apart from the
/// drawing (#457 batch B) — the arrangement `LinksChecklistSheetModel` uses.
///
/// One sheet for every function that needs one, moving through stages:
/// CHOOSING (which pages, which day, where to make room), then the
/// PLAN (the multi-page change seen before it happens, which is the
/// assistant's plan card in the menu's form: for Publish Pages…, Hide
/// Pages… and Publish Class for a Date…, a summary over a table of every
/// page, the plan twin's `planTable` (#524); for Re-date and Make Room, the
/// card's own text, `forTheCard`), then WORKING, then FINISHED (what the
/// tool said). A refusal
/// at the plan goes straight to FINISHED with OK alone, as the assistant
/// shows a refusing twin with no Go. Publish Pages… never asks about
/// classes dated later (#694): publishing changes only the preview, and a
/// teacher publishes next week's classes precisely to check them there.
///
/// The same sheet asks the #475 question at Deploy (`kind == .laterClassesAtDeploy`,
/// and the only place it is asked: every class starts ticked, and a ticked
/// class goes out — #694),
/// shows the class dates sheet when a function needs dates first
/// (`.classDates`), and shows the answer of a function that has no sheet of
/// its own (`.result`: Undo Last Change, a refused Rebuild Preview). One `.sheet` rather than several, because a view presents one
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
        /// Add Class… (#897): how the class is added, then — for a copy —
        /// the class to copy and the plan.
        case addClass
        /// Roll Over to a New Year… (#897 piece B): the dates, the website
        /// question where there is a website (`RollOverFromTheMenu`), then
        /// the plan. Drawn by `rollOverChoosing`.
        case rollOver
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

    /// A class page Add Class… can copy (#897): one of this
    /// section's own, named by its FILE (`path`), never by its title.
    struct SourceRow: Identifiable, Equatable {

        // MARK: - Stored properties

        /// The page's path inside the course, `.md` included
        /// (`SectionVerbs.coursePath(ofPageAt:in:)`): what the call carries.
        let path: String

        /// The file name without `.md`, as Make Room's list shows a class.
        let title: String

        let date: CalendarDay?

        // MARK: - Computed properties

        var id: String {
            return path
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

    /// The page rows — hidden pages to publish, or visible ones to hide — in
    /// the order the call carries them. Setting them builds the tree of
    /// checkboxes once (#900), never per draw.
    var pageRows: [PageRow] = [] {
        didSet {
            buildTheTree()
        }
    }
    var ticked: Set<String> = []
    var search: String = "" {
        didSet {
            openGroupsForTheSearch(from: oldValue)
        }
    }

    /// The tree of checkboxes (#900): `pageRows` grouped under their unit or
    /// folder (`PageTickTree.groups`), built when the rows are set.
    var pageGroups: [PageTickTree.Group] = []

    /// The groups drawn open, and the ones the teacher had open before a
    /// search opened every group it shows (put back when it is cleared).
    var openGroups: Set<PageTickTree.RowID> = []
    var openGroupsBeforeTheSearch: Set<PageTickTree.RowID>?

    /// Pages a group's box ticked that were not ticked before the click,
    /// and not touched by their own box since: counted on the trail line
    /// only (", 12 by a group's box"), so a report of pages published
    /// unmeant can be read. A page the teacher had already ticked by hand
    /// is not counted when a box then covers it. Never a title.
    var tickedByAGroupsBox: Set<String> = []

    /// Publish Class for a Date…'s day.
    var day: Date = Date()

    /// Make Room for Classes…'s class, by title, and how many to make room for.
    var classRows: [ClassRow] = []
    var chosenClass: String = ""
    var howMany: Int = 1

    /// Add Class…'s ways (#897): the ones this section can use now, in the
    /// sheet's order (`SubjectMenuRules.addClassWays`), and the one chosen.
    var addClassFacts: SubjectMenuRules.AddClassFacts = SubjectMenuRules.AddClassFacts()
    var way: SubjectMenuRules.AddClassWay?

    /// Add Class…'s classes to copy, and the one chosen, by path.
    var sourceRows: [SourceRow] = []
    var chosenSource: String?

    /// Roll Over to a New Year…'s dates and website answer (#897 piece B).
    var rollOver: RollOverFromTheMenu.Choice = RollOverFromTheMenu.Choice()

    /// #475: the classes asked about at Deploy, and the ones ticked to GO
    /// OUT (all, to begin with — a ticked box always means included, #694).
    /// `nextClassDay` is the day they are after, as a row says a day.
    var laterClasses: [ClassesDatedLater.Flagged] = []
    var laterTicked: Set<String> = []
    var nextClassDay: String = ""

    /// The plan's card, or the tool's answer.
    var body: String = ""

    /// The plan as rows, when the plan is a page plan (#524) — shown at
    /// `.planned` in place of `body`.
    var planTable: AssistPlanTable?

    /// Whether the plan's checkbox is ticked (#622; a checkbox since #654):
    /// the pages already the way they were asked to be, added to the table.
    /// Unticked for every new plan.
    var showsAlreadyRight: Bool = false

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

    /// The offered pages as the tree reads them, in `pageRows`' order.
    var tickPages: [PageTickTree.Page] {
        var pages: [PageTickTree.Page] = []
        for row in pageRows {
            pages.append(SectionVerbSheetModel.tickPage(of: row))
        }
        return pages
    }

    /// The tree's rows for the search as it stands (#900): groups with a
    /// shown page under them, and those pages. Linear in pages, no file read.
    var tickRows: [PageTickTree.Row] {
        return PageTickTree.rows(of: pageGroups, search: search)
    }

    /// The class groups' names, in the course's noun.
    var groupNames: PageTickTree.GroupNames {
        return PageTickTree.GroupNames(
            otherClasses: AssistWording.menuPageGroupOtherClasses(noun: noun),
            allClasses: AssistWording.menuPageGroupAllClasses(noun: noun)
        )
    }

    /// Ticked pages the search leaves out of view (#900): still ticked, and
    /// still in the plan, as before the tree.
    var tickedButNotShown: Int {
        return PageTickTree.tickedButNotShown(tickPages, ticked: ticked, search: search)
    }

    /// How many ticked pages a group's box ticked last (#900), for the trail.
    var tickedByAGroupsBoxCount: Int {
        var count: Int = 0
        for name in tickedByAGroupsBox where ticked.contains(name) {
            count += 1
        }
        return count
    }

    /// The ways Add Class… can use now, in the sheet's order.
    var availableWays: [SubjectMenuRules.AddClassWay] {
        return SubjectMenuRules.addClassWays(addClassFacts)
    }

    /// The course's word for a unit, as a sentence says it ("module").
    /// "unit" in a numbered course, whose word is the pages' whole name
    /// ("Week") and never a unit (the fix review's finding 1). A word in
    /// capitals (an acronym) is left as it is.
    var unitWord: String {
        let naming: ClassPageNaming = course.configuration.classPageNaming
        if naming.isNumbered {
            return "unit"
        }
        if naming.word.count > 1 && naming.word == naming.word.uppercased() {
            return naming.word
        }
        return naming.word.lowercased()
    }

    /// The line a way is drawn with (`SubjectMenuRules.label(of:_:)`).
    func label(of way: SubjectMenuRules.AddClassWay) -> String {
        return SectionVerbSheet.sentence(for: SubjectMenuRules.label(of: way, addClassFacts), noun: noun, unit: unitWord)
    }

    /// Why each greyed way is greyed, one sentence per reason, in the ways'
    /// order (#897a review, finding 1): a greyed radio button alone says
    /// "no" and not what to do about it.
    var greyedReasons: [(line: SubjectMenuRules.AddClassReasonLine, sentence: String)] {
        var reasons: [(line: SubjectMenuRules.AddClassReasonLine, sentence: String)] = []
        for line in SubjectMenuRules.reasonLines(addClassFacts) {
            reasons.append((line, SectionVerbSheet.sentence(for: line, noun: noun, unit: unitWord)))
        }
        return reasons
    }

    /// The search for Add Class…'s list. A chosen class the search hides is
    /// let go, so Continue never copies a row the teacher cannot see
    /// (#897a review, finding 13).
    func searchTheSources(for text: String) {
        search = text
        var stillShown: Bool = false
        for row in shownSourceRows where row.path == chosenSource {
            stillShown = true
        }
        if !stillShown {
            chosenSource = nil
        }
    }

    /// The classes Add Class… shows for the search.
    var shownSourceRows: [SourceRow] {
        let wanted: String = search.trimmingCharacters(in: .whitespaces).lowercased()
        if wanted.isEmpty {
            return sourceRows
        }
        var shown: [SourceRow] = []
        for row in sourceRows where row.title.lowercased().contains(wanted) {
            shown.append(row)
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
        case .addClass:
            return AssistWording.menuHowToAddAClass(noun: noun)
        case .rollOver:
            return AssistWording.menuRollOverIntro(noun: noun)
        default:
            return ""
        }
    }

    /// The default button's title at each stage.
    var defaultButtonTitle: String {
        switch stage {
        case .choosing:
            // A way that adds at once says so on its button; a copy has a
            // plan to show first.
            if kind == .addClass && (way == .nextInThisUnit || way == .inANewUnit) {
                return AssistWording.menuAddButton
            }
            return AssistWording.menuContinueButton
        case .askingAboutLaterClasses:
            return AssistWording.deployTickedButton
        case .planned:
            switch kind {
            case .hidePages:
                return AssistWording.menuHideButton
            case .reDateClasses:
                return AssistWording.menuReDateButton
            case .makeRoom:
                return AssistWording.menuMakeRoomButton
            case .addClass:
                return AssistWording.menuDuplicateButton
            case .rollOver:
                return AssistWording.menuRollOverButton
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
            case .addClass:
                guard let way, availableWays.contains(way) else {
                    return false
                }
                return way != .asACopyOfAClass || chosenSource != nil
            case .rollOver:
                // Nothing is sent until the website question, where it is
                // asked, has an answer.
                return rollOver.websiteSent != nil
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

    /// The classes Add Class… can copy (#897): every page in
    /// this section's class folders, numbered or not (the plan review's
    /// amendment 8), in `ClassPages.list`'s order — dated ones by date, the
    /// rest by name after them. This section's only (Russell's ruling).
    static func sourceRows(course: Course, sectionNumber: Int) -> [SourceRow] {
        var found: [SourceRow] = []
        for page in ClassPages.list(forSection: sectionNumber, in: course) {
            found.append(SourceRow(
                path: SectionVerbs.coursePath(ofPageAt: page.fileURL, in: course),
                title: page.title,
                date: page.date
            ))
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
        return binding(forPageNamed: row.name)
    }

    /// A page's own checkbox: ticks or unticks that page alone.
    func binding(forPageNamed name: String) -> Binding<Bool> {
        return Binding(
            get: { return self.ticked.contains(name) },
            set: { isOn in
                if isOn {
                    self.ticked.insert(name)
                } else {
                    self.ticked.remove(name)
                }
                self.tickedByAGroupsBox.remove(name)
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
            tickedByAGroupsBox.remove(row.name)
        }
    }

    /// Space on the tree's selected row, and a click on a group's box
    /// (#900): a page flips alone; a group does what its box does. Only a row
    /// the search leaves showing, looked up afresh in the tree as it stands,
    /// so the box and Space act on the same pages whatever a cell last drew.
    func flip(_ id: PageTickTree.RowID?) {
        guard let id, let row = PageTickTree.row(withID: id, in: tickRows) else {
            return
        }
        switch id {
        case .page(let name):
            flipTick(ofRowWithID: name)
        case .group:
            click(group: row)
        }
    }

    /// A click on a group's box (#900), decided by the tree's rule
    /// (`PageTickTree.clicking`): it ticks every shown page under it unless
    /// every one is already ticked, and then it unticks them. A page the
    /// search hides is never changed. The box and Space reach it through
    /// `flip(_:)`, which looks the row up afresh.
    func click(group row: PageTickTree.Row) {
        let before: Set<String> = ticked
        ticked = PageTickTree.clicking(row.shownPageNames, ticked: ticked)
        for name in row.shownPageNames {
            if ticked.contains(name) {
                if !before.contains(name) {
                    tickedByAGroupsBox.insert(name)
                }
            } else {
                tickedByAGroupsBox.remove(name)
            }
        }
    }

    /// A group's box as it is drawn now: over every page under it, shown or
    /// hidden, so it is never drawn ticked while one of them is not.
    func state(of row: PageTickTree.Row) -> PageTickTree.State {
        return PageTickTree.boxState(of: row, ticked: ticked)
    }

    /// The box of the group with `id` in the tree as it stands; off when the
    /// search no longer draws it.
    func state(ofRowWithID id: PageTickTree.RowID) -> PageTickTree.State {
        guard let row = PageTickTree.row(withID: id, in: tickRows) else {
            return .off
        }
        return state(of: row)
    }

    /// How many of a group's pages are ticked, shown or hidden: the "n" of
    /// its "n of m ticked".
    func tickedCount(of row: PageTickTree.Row) -> Int {
        return PageTickTree.count(of: row.everyPageName, in: ticked)
    }

    /// A group's count as its row shows it and VoiceOver hears it
    /// (`menuPageGroupTickedCount`, "2 of 3 ticked"): over every page under
    /// it, so a mixed box beside pages the search hides says why.
    func tickedCountLine(of row: PageTickTree.Row) -> String {
        return AssistWording.menuPageGroupTickedCount(ticked: tickedCount(of: row), of: row.everyPageName.count)
    }

    /// Whether a group is drawn open; the table's own triangle, Right and
    /// Left change it.
    func isOpen(_ id: PageTickTree.RowID) -> Binding<Bool> {
        return Binding(
            get: { return self.openGroups.contains(id) },
            set: { open in
                if open {
                    self.openGroups.insert(id)
                } else {
                    self.openGroups.remove(id)
                }
            }
        )
    }

    /// The tree, built once from the rows (#900), every group folded or
    /// open as `PageTickTree.groupsStartFolded` says.
    func buildTheTree() {
        pageGroups = PageTickTree.groups(
            of: tickPages,
            naming: course.configuration.classPageNaming,
            courseCode: course.code,
            names: groupNames
        )
        openGroups = []
        openGroupsBeforeTheSearch = nil
        if !PageTickTree.groupsStartFolded {
            for id in PageTickTree.groupIDs(in: PageTickTree.rows(of: pageGroups, search: "")) {
                openGroups.insert(id)
            }
        }
    }

    /// While the search has text, every group holding a shown page is open,
    /// so a match is never hidden inside a folded group; clearing the search
    /// puts back the groups that were open before it (#900, the plan's rule 9).
    func openGroupsForTheSearch(from previous: String) {
        if kind != .publishPages && kind != .hidePages {
            return
        }
        let wanted: String = search.trimmingCharacters(in: .whitespaces)
        let wasSearching: Bool = !previous.trimmingCharacters(in: .whitespaces).isEmpty
        if wanted.isEmpty {
            if wasSearching, let before = openGroupsBeforeTheSearch {
                openGroups = before
            }
            openGroupsBeforeTheSearch = nil
            return
        }
        if openGroupsBeforeTheSearch == nil {
            openGroupsBeforeTheSearch = openGroups
        }
        for id in PageTickTree.groupIDs(in: tickRows) {
            openGroups.insert(id)
        }
    }

    /// One row as the tree reads it.
    static func tickPage(of row: PageRow) -> PageTickTree.Page {
        return PageTickTree.Page(name: row.name, title: row.title, folder: row.folder, isClass: row.isClass, date: row.date)
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

    /// The #475 question's rows: the classes, all ticked to begin with, so
    /// Return deploys every one of them (#694, Russell's ruling 1).
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

    /// The classes asked about that are TICKED: kept published at their
    /// dates, and deployed (#694).
    var laterKept: [ClassesDatedLater.Flagged] {
        var kept: [ClassesDatedLater.Flagged] = []
        for page in laterClasses where laterTicked.contains(page.place) {
            kept.append(page)
        }
        return kept
    }

    /// The classes asked about that the teacher UNticked: hidden before the
    /// deploy, so the preview is left showing what students will see
    /// (#694, Russell's ruling 2).
    var laterHidden: [ClassesDatedLater.Flagged] {
        var hidden: [ClassesDatedLater.Flagged] = []
        for page in laterClasses where !laterTicked.contains(page.place) {
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

    /// The window's runner, read for the copy being saved before a change
    /// while the sheet waits (#351) — read here, in the sheet's own body, so
    /// the line follows it.
    var verbs: SectionVerbs?

    /// How many rows Add Class…'s copy list shows before it scrolls
    /// (`mostSourceRowsShown`); a test lays the sheet out at twelve too, so
    /// the cap is a measured choice (the fix review's finding 2).
    var sourceRowsShown: Int = SectionVerbSheet.mostSourceRowsShown

    /// The plan table's order: plan order to begin with; a column header
    /// sorts by that column (#524, the `AllBackupsView` precedent).
    @State var planSortOrder: [KeyPathComparator<AssistPlanTable.Row>] = [KeyPathComparator(\.position)]

    /// The picker's and the later-classes list's selected row (#608): what
    /// Space ticks. Selecting a row is not ticking it.
    @State var pickedRowID: PageTickTree.RowID? = nil
    @State var pickedLaterClassID: String? = nil

    static let tallestList: CGFloat = 340

    /// The sheet's width to open with, and the narrowest it can be made
    /// (#621): what it was before it could be resized.
    static let width: CGFloat = 560

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

    /// The fewest rows the plan table is tall enough for when pages are
    /// folded under it (#622, the director's ruling on R8): the table is as
    /// tall as the rows a teacher reads, and ticking the checkbox adds the
    /// rest INSIDE it — the sheet never grows when it is ticked — so a plan of
    /// one or two changes keeps room for the folded rows to scroll in. Five,
    /// Start of Year's own budget (`StartOfYearSheet.mostPlanRowsShown`).
    static let fewestPlanRowsUnderAFold: Int = 5

    /// The gap between the plan table and the checkbox under it (#622, #654):
    /// 6 pt, so the checkbox reads as the table's, and so the worst plan
    /// stays within `CopyPageChecklist.tallestSheet` (`planTable`).
    static let foldSpacing: CGFloat = 6

    // MARK: - Computed properties

    /// The plan table's rows as drawn (#622): the rows to read, and the
    /// pages already the way they were asked to be only while the
    /// checkbox is ticked. They come last in plan order, so ticking it
    /// appends them. A plan with nothing else to read shows every row.
    var drawnPlanRows: [AssistPlanTable.Row] {
        guard let table = model.planTable else {
            return []
        }
        if !SectionVerbSheet.foldsAlreadyRight(table) {
            return table.rows
        }
        var drawn: [AssistPlanTable.Row] = table.rowsToRead
        if model.showsAlreadyRight {
            for row in table.rowsAlreadyRight {
                drawn.append(row)
            }
        }
        return drawn
    }

    /// The words of the checkbox under the plan table (#622, #654) — "Show the
    /// 16 pages already visible" — or nil when the plan folds nothing away.
    var alreadyRightLabel: String? {
        guard let table = model.planTable, SectionVerbSheet.foldsAlreadyRight(table) else {
            return nil
        }
        return AssistWording.menuPlanShowAlready(
            count: table.rowsAlreadyRight.count,
            publishing: table.rowsAlreadyRight.first?.change != .alreadyHidden
        )
    }

    /// The plan table's rows, in the order the teacher sorted them.
    var sortedPlanRows: [AssistPlanTable.Row] {
        return drawnPlanRows.sorted(using: planSortOrder)
    }

    /// The table's height: the rows a teacher reads up to
    /// `mostPlanRowsShown`, then it scrolls inside itself. A `Table` has no
    /// natural height. It is counted with the checkbox UNTICKED, and never
    /// fewer than `fewestPlanRowsUnderAFold` (or every row, when there are
    /// fewer) while pages are folded under it, so ticking the checkbox
    /// changes neither the table's height nor the sheet's (#622).
    var planTableHeight: CGFloat {
        guard let table = model.planTable else {
            return ListTableMetrics.height(forRowCount: 0, showsHeader: true)
        }
        var shown: Int = table.rows.count
        if SectionVerbSheet.foldsAlreadyRight(table) {
            shown = table.rowsToRead.count
            var floor: Int = SectionVerbSheet.fewestPlanRowsUnderAFold
            if floor > table.rows.count {
                floor = table.rows.count
            }
            if shown < floor {
                shown = floor
            }
        }
        if shown > SectionVerbSheet.mostPlanRowsShown {
            shown = SectionVerbSheet.mostPlanRowsShown
        }
        return ListTableMetrics.height(forRowCount: shown, showsHeader: true)
    }

    /// The picker's height (#608): counted from EVERY page offered and every
    /// group (#900, the plan review's amendment 26), not the rows the search
    /// or a folded group leaves showing, so the sheet stays still while the
    /// teacher types or opens a group; up to `mostPickerRowsShown`, then it
    /// scrolls inside.
    var pickerTableHeight: CGFloat {
        var shown: Int = model.pageRows.count + SectionVerbSheet.groupCount(model.pageGroups)
        if shown > SectionVerbSheet.mostPickerRowsShown {
            shown = SectionVerbSheet.mostPickerRowsShown
        }
        return ListTableMetrics.height(forRowCount: shown, showsHeader: true)
    }

    /// How many classes Add Class…'s list shows before it scrolls inside
    /// itself (#897). Fewer than the picker's twelve: this sheet also carries
    /// the three ways, a line saying why one is greyed and the copy's own
    /// instruction above the search, an ESTIMATED 150 pt more than Publish
    /// Pages…'s picker, whose forty-page case is measured against the 620 pt
    /// a 13-inch screen allows (`CopyPageChecklist.tallestSheet`). Seven rows
    /// give back 120 of them (`ListTableMetrics`: 24 pt a row).
    /// `DuplicateAsNextClassTests.testTheTallestAddClassSheetStaysOnTheScreen`
    /// lays it out at seven and at twelve and prints both, which is the
    /// measurement this number waits on (deferred: it needs the test host).
    static let mostSourceRowsShown: Int = 7

    /// Add Class…'s list of classes to copy (#897), the same way.
    var sourceTableHeight: CGFloat {
        var shown: Int = model.sourceRows.count
        if shown > sourceRowsShown {
            shown = sourceRowsShown
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
                // Every stage stays flexible (#621): the content is wrapped
                // in ONE stack before the flexible frame — a frame on a
                // multi-view builder frames each child, which gave the table
                // 223 of 628 pt and the summary 560 — and the frame takes any
                // height the teacher adds, at the top, so the buttons stay at
                // the bottom. Not a `Spacer`: it adds a spacing (12 pt) to
                // the size every stage opens at.
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .frame(maxHeight: .infinity, alignment: .top)
                buttons
            }
            .padding([.horizontal, .bottom], 20)
            .sheetTitle(sheetTitle)
            // 560 wide and its content's height to open with, which is also
            // the smallest the sheet can be made; no largest (#621). A table
            // takes the height added (`flexibleTableHeight`), its Page column
            // the width.
            .frame(minWidth: SectionVerbSheet.width, idealWidth: SectionVerbSheet.width, maxWidth: .infinity)
            // Grown to every stage's minimum, and fitted to the answer once
            // there is one (#654): the plan's height is the plan's alone.
            .background(SheetGrowsToItsMinimum(fitsItsContent: model.stage == .finished).accessibilityHidden(true))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sectionVerbSheet")
            // `.fitted` is what makes a sheet resizable at all — the default
            // sizing is not, and snaps back on every change (measured) — and
            // it opens the sheet at the size above.
            .presentationSizing(.fitted)
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
            CappedScrollArea(cap: SectionVerbSheet.tallestList, growsWithItsSheet: true) {
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
    /// every page a teacher reads before Go, the pages already the way they
    /// were asked to be behind a checkbox under it (#622, #654), and the card's
    /// other sentences.
    @ViewBuilder
    var planTable: some View {
        if let table = model.planTable {
            Text(table.summary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sectionVerbSheetPlanSummary")
            // The table and the checkbox under it as one part, 6 pt apart
            // rather than 12: the checkbox belongs to the table, and the
            // worst plan (twelve rows, the checkbox and the notes at their
            // cap) is 609 pt that way — 616 with the disclosure #654
            // replaced, which was 622 with a full spacing, over the 620 a
            // 13-inch screen allows (`CopyPageChecklist.tallestSheet`). The
            // cap is the PLAN's: the answer after it is fitted to its own
            // sentence (`SheetGrowsToItsMinimum.fitsItsContent`).
            VStack(alignment: .leading, spacing: SectionVerbSheet.foldSpacing) {
                planRowsTable
                if let alreadyRightLabel {
                    // A checkbox, not a disclosure (#654): ticking it adds
                    // the rows to the table ABOVE it (`drawnPlanRows`), one
                    // table and one sort, as #589 chose one table over two —
                    // so a triangle promised a fold that never opened below
                    // it.
                    Toggle(
                        alreadyRightLabel,
                        isOn: Binding(
                            get: { return model.showsAlreadyRight },
                            set: { isTicked in model.showsAlreadyRight = isTicked }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("sectionVerbSheetPlanAlreadyRight")
                }
            }
            .layoutPriority(1)
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

    /// The plan's rows: Page, Folder and What changes. No `selection:`: the
    /// rows are read, not chosen. Page has no largest width and the other
    /// two do, so the width a teacher adds goes to the titles (#621); at 560
    /// the caps change nothing (131/121/220, as before).
    var planRowsTable: some View {
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
            .width(min: 80, ideal: 110, max: 140)
            TableColumn(AssistWording.menuPlanChangeColumn, value: \.whatChanges) { (row: AssistPlanTable.Row) in
                // A date move or a reason is long; the tooltip has it whole.
                Text(row.whatChanges)
                    .help(row.whatChanges)
            }
            // The widest at 560: it carries the longest words (a date move,
            // a reason). Three equal columns, as first drawn, cut it at about
            // twenty letters in the real 560-point sheet.
            .width(min: 180, ideal: 240, max: 320)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .flexibleTableHeight(planTableHeight)
        .accessibilityIdentifier("sectionVerbSheetPlanTable")
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
                // A ticked page the search hides is still in the plan (#900):
                // said, so a plan longer than the ticks in view is no surprise.
                if model.tickedButNotShown > 0 {
                    Text(AssistWording.menuTickedButNotShown(count: model.tickedButNotShown))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sectionVerbSheetTickedButNotShown")
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
        case .addClass:
            // One line per way, in the contract's order; a way this section
            // cannot use is drawn greyed, never left out, so the sheet reads
            // the same every time.
            Picker("", selection: Binding(
                get: { return model.way },
                set: { chosen in model.way = chosen }
            )) {
                ForEach(SubjectMenuRules.AddClassWay.allCases, id: \.self) { (way: SubjectMenuRules.AddClassWay) in
                    Text(model.label(of: way))
                        .tag(Optional(way))
                        .disabled(!model.availableWays.contains(way))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .accessibilityIdentifier("sectionVerbSheetAddClassWay")
            // Each line its own identifier, by its reason (the fix review's
            // finding 8), so a test can tell two apart.
            ForEach(model.greyedReasons, id: \.line) { (reason: (line: SubjectMenuRules.AddClassReasonLine, sentence: String)) in
                Text(reason.sentence)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sectionVerbSheetAddClassGreyed-\(reason.line.rawValue)")
            }
            if model.way == .asACopyOfAClass && !model.sourceRows.isEmpty {
                Text(AssistWording.menuPickClassToDuplicate(noun: model.noun))
                    .fixedSize(horizontal: false, vertical: true)
                TextField(AssistWording.menuFindAPage, text: Binding(
                    get: { return model.search },
                    set: { text in model.searchTheSources(for: text) }
                ))
                .borderedTextField()
                .accessibilityIdentifier("sectionVerbSheetSearch")
                sourceTable
            }
        case .rollOver:
            rollOverChoosing
        default:
            EmptyView()
        }
    }

    /// The classes to copy (#897): one chosen by selecting its row, in the
    /// picker's look (#608) — Page and Date — with no checkboxes, because
    /// exactly one class is copied.
    var sourceTable: some View {
        Table(model.shownSourceRows, selection: Binding(
            get: { return model.chosenSource },
            set: { path in model.chosenSource = path }
        )) {
            TableColumn(AssistWording.menuPlanPageColumn) { (row: SectionVerbSheetModel.SourceRow) in
                Text(row.title)
                    .lineLimit(1)
                    .help(row.title)
                    .accessibilityIdentifier("sectionVerbSource-\(row.path)")
            }
            .width(min: 120, ideal: 220)
            TableColumn(AssistWording.menuPickDateColumn) { (row: SectionVerbSheetModel.SourceRow) in
                Text(sourceDateCell(for: row))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150, max: 180)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .flexibleTableHeight(sourceTableHeight)
        .accessibilityIdentifier("sectionVerbSheetSourceTable")
    }

    /// The pages to tick (#608), as a tree of checkboxes since #900: a
    /// bordered, banded table — Page (with its checkbox), Folder and Date —
    /// the look of the plan that follows it, so the two steps of one flow
    /// look alike. Each unit, the classes outside any unit, and each folder
    /// is a group with a box of its own that ticks or clears every shown
    /// page under it and is drawn mixed when only some are ticked
    /// (`PageTickTree`). A click on a box ticks it; Space ticks the selected
    /// row, a group's box included; Right and Left open and close a group.
    /// No header sorts the rows.
    ///
    /// `Table(of:selection:columns:rows:)` with `DisclosureTableRow`, not
    /// `Table(_:children:)`, whose groups cannot be opened from the model
    /// (the plan review's amendment 23): the search opens every group it
    /// shows.
    var pickerTable: some View {
        Table(of: PageTickTree.Row.self, selection: $pickedRowID) {
            TableColumn(AssistWording.menuPlanPageColumn) { (row: PageTickTree.Row) in
                pageCell(for: row)
            }
            .width(min: 90, ideal: 130)
            TableColumn(AssistWording.menuPlanFolderColumn) { (row: PageTickTree.Row) in
                Text(row.page?.folder ?? "")
                    .foregroundStyle(.secondary)
                    .help(row.page?.folder ?? "")
            }
            .width(min: 80, ideal: 110, max: 140)
            TableColumn(AssistWording.menuPickDateColumn) { (row: PageTickTree.Row) in
                Text(dateCell(for: row))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150, max: 180)
        } rows: {
            ForEach(model.tickRows) { (row: PageTickTree.Row) in
                PageTickTableRows(row: row, isOpen: model.isOpen)
            }
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .flexibleTableHeight(pickerTableHeight)
        .onKeyPress(.space) {
            if pickedRowID == nil {
                return .ignored
            }
            model.flip(pickedRowID)
            return .handled
        }
        .accessibilityIdentifier("sectionVerbSheetPickerTable")
    }

    /// The Page cell: a group's box (an AppKit checkbox whose state the model
    /// sets, so it can be mixed and a click is the model's rule), or a page's
    /// own checkbox.
    @ViewBuilder
    func pageCell(for row: PageTickTree.Row) -> some View {
        if row.isGroup {
            let id: PageTickTree.RowID = row.id
            GroupTickBox(
                title: row.title,
                state: model.state(of: row),
                valueDescription: model.tickedCountLine(of: row),
                identifier: SectionVerbSheet.identifier(of: row),
                click: {
                    // By id, looked up afresh: the same path as Space.
                    model.flip(id)
                    return model.state(ofRowWithID: id)
                }
            )
            .help(row.title)
        } else if let page = row.page {
            Toggle(page.title, isOn: model.binding(forPageNamed: page.name))
                .toggleStyle(.checkbox)
                .lineLimit(1)
                .help(page.title)
                .accessibilityIdentifier("sectionVerbRow-\(page.name)")
        }
    }

    @ViewBuilder
    var laterClasses: some View {
        Text(AssistWording.laterClassesAtDeploy(nextDay: model.nextClassDay, noun: model.noun))
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
        .flexibleTableHeight(laterClassesTableHeight)
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

    /// Whether the plan folds its already-right pages away (#622): only when
    /// there are some, and something else to read above them.
    static func foldsAlreadyRight(_ table: AssistPlanTable) -> Bool {
        return !table.rowsAlreadyRight.isEmpty && !table.rowsToRead.isEmpty
    }

    /// One way's line in Add Class…'s sheet (#897).
    /// A way's line. `unit` is the course's own word, as a sentence says it.
    static func sentence(for label: SubjectMenuRules.AddClassLabel, noun: ClassNoun, unit: String) -> String {
        switch label {
        case .nextInTheUnitUnderWay:
            return AssistWording.menuAddClassNextInThisUnit(noun: noun, unit: unit)
        case .nextInANumberedCourse:
            return AssistWording.menuAddClassNextInThisUnit(noun: noun, numbered: true)
        case .inANewUnitInTheCoursesWord:
            return AssistWording.menuAddClassInANewUnit(noun: noun, unit: unit)
        case .inANewUnitPlainly:
            return AssistWording.menuAddClassInANewUnit(noun: noun)
        case .asACopy:
            return AssistWording.menuAddClassAsACopy(noun: noun)
        }
    }

    /// One line under the ways (#897).
    static func sentence(for line: SubjectMenuRules.AddClassReasonLine, noun: ClassNoun, unit: String) -> String {
        switch line {
        case .theCourseHasNoUnits:
            return AssistWording.menuAddClassGreyedNoUnits(noun: noun)
        case .thereIsNoClassToCopy:
            return AssistWording.menuAddClassGreyedNothingToCopy(noun: noun)
        case .aRenameHoldsBackANewUnitAndACopy:
            return AssistWording.menuAddClassGreyedRenameUnfinished(noun: noun, unit: unit)
        case .aRenameHoldsBackANewUnit:
            return AssistWording.menuAddClassGreyedRenameUnfinished(noun: noun, unit: unit, copy: false)
        case .aRenameHoldsBackACopy:
            // Reached only in a numbered course: anywhere else the rename
            // holds the new unit back too (`whyGreyed`'s order). There the
            // renamed word is the pages' own name.
            return AssistWording.menuAddClassGreyedRenameUnfinished(noun: noun, newUnit: false, numbered: true)
        }
    }

    /// The source list's Date cell (#897), as the picker writes a day.
    func sourceDateCell(for row: SectionVerbSheetModel.SourceRow) -> String {
        if let date = row.date {
            return AssistWording.laterClassesDay(weekday: date.weekdayName, date: date.text)
        }
        return ""
    }

    /// The picker's Date cell: a class's day, as the later-classes question
    /// says it; nothing for a page that is not a class.
    func dateCell(for row: SectionVerbSheetModel.PageRow) -> String {
        if let date = row.date, row.isClass {
            return AssistWording.laterClassesDay(weekday: date.weekdayName, date: date.text)
        }
        return ""
    }

    /// The tree's Date cell (#900): a class page's day; nothing for a page
    /// that is not a class; and for a group, how many of its pages are
    /// ticked ("2 of 3 ticked", `menuPageGroupTickedCount`), so a sighted
    /// teacher reads the count VoiceOver hears, and a folded group, or one
    /// the search narrows, says what its box covers.
    func dateCell(for row: PageTickTree.Row) -> String {
        if row.isGroup {
            return model.tickedCountLine(of: row)
        }
        if let page = row.page, let date = page.date, page.isClass {
            return AssistWording.laterClassesDay(weekday: date.weekdayName, date: date.text)
        }
        return ""
    }

    /// A tree row's accessibility identifier: a group by its key ("unit 4",
    /// "folder Concepts/Loops"), so two folders of one name stay apart.
    static func identifier(of row: PageTickTree.Row) -> String {
        switch row.id {
        case .group(let key):
            return "sectionVerbGroup-" + key
        case .page(let name):
            return "sectionVerbRow-" + name
        }
    }

    /// How many groups the tree holds, at every depth: counted into the
    /// picker's height with the pages (#900).
    static func groupCount(_ groups: [PageTickTree.Group]) -> Int {
        var count: Int = 0
        for group in groups {
            count += 1 + groupCount(group.groups)
        }
        return count
    }
}

/// The tree's rows (#900): a group as a row that opens onto the rows under
/// it, at any depth, or a page. Recursive, so it needs `@TableRowBuilder` on
/// its body (measured by the plan review: without it the two branches do not
/// typecheck).
struct PageTickTableRows: TableRowContent {

    // MARK: - Stored properties

    typealias TableRowValue = PageTickTree.Row

    let row: PageTickTree.Row
    let isOpen: (PageTickTree.RowID) -> Binding<Bool>

    // MARK: - Computed properties

    @TableRowBuilder<PageTickTree.Row>
    var tableRowBody: some TableRowContent<PageTickTree.Row> {
        if let children = row.children {
            DisclosureTableRow(row, isExpanded: isOpen(row.id)) {
                ForEach(children) { (child: PageTickTree.Row) in
                    PageTickTableRows(row: child, isOpen: isOpen)
                }
            }
        } else {
            TableRow(row)
        }
    }
}

/// A group's box in the tree (#900): an AppKit checkbox that can show a
/// MIXED state, a dash, when only some pages under it are ticked.
///
/// Its state is SET from the model on every update and a click calls the
/// model's rule (`SectionVerbSheetModel.flip(_:)` with the group's id, the
/// path Space takes), so AppKit's own off, on, mixed cycle never decides
/// what is ticked: a click ticks the shown pages under the group unless
/// every one is already ticked, in which case it unticks them, and a page
/// the search hides is never changed (`PageTickTree`'s rule). The box is
/// read over every page under it, hidden ones included. Rejected: SwiftUI's
/// `Toggle(sources:isOn:)`, which draws the mixed state but leaves which way
/// a click on it goes to the framework (the plan review's amendment 24).
///
/// VoiceOver hears the group's name, the checkbox and its state from
/// AppKit, and "5 of 12 ticked" as the value's description, the same count
/// the row's Date cell shows.
struct GroupTickBox: NSViewRepresentable {

    // MARK: - Stored properties

    let title: String
    let state: PageTickTree.State
    let valueDescription: String
    let identifier: String

    /// The model's rule, answering the box's state after it.
    let click: () -> PageTickTree.State

    // MARK: - Functions

    func makeCoordinator() -> Coordinator {
        return Coordinator(click: click)
    }

    func makeNSView(context: Context) -> NSButton {
        let box: NSButton = NSButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        box.allowsMixedState = true
        box.lineBreakMode = .byTruncatingTail
        box.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        update(box)
        return box
    }

    func updateNSView(_ box: NSButton, context: Context) {
        context.coordinator.click = click
        update(box)
    }

    /// The box as the model says it is, whatever a click has just done to it.
    func update(_ box: NSButton) {
        box.title = title
        box.state = GroupTickBox.controlState(for: state)
        box.setAccessibilityLabel(title)
        box.setAccessibilityValueDescription(valueDescription)
        box.setAccessibilityIdentifier(identifier)
    }

    /// AppKit's state for the tree's.
    static func controlState(for state: PageTickTree.State) -> NSControl.StateValue {
        switch state {
        case .on:
            return .on
        case .off:
            return .off
        case .mixed:
            return .mixed
        }
    }

    /// Carries the click to the model, and draws the state the model then
    /// answers, over whatever AppKit's own cycle has just drawn.
    final class Coordinator: NSObject {

        // MARK: - Stored properties

        var click: () -> PageTickTree.State

        // MARK: - Initializer

        init(click: @escaping () -> PageTickTree.State) {
            self.click = click
        }

        // MARK: - Functions

        @objc func clicked(_ sender: NSButton) {
            let after: PageTickTree.State = click()
            sender.state = GroupTickBox.controlState(for: after)
        }
    }
}
