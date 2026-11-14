import Foundation
import Observation

/// The assistant's functions, run from the Section menu (#457 batch B).
///
/// Publish Pages…, Hide Pages…, Publish Class for a Date…, Rebuild Preview,
/// Undo Last Change, Add Next Class, Re-date Classes… and Make Room for
/// Classes… (and, since #897, Add Next Class in a New Unit and Duplicate as
/// Next Class…) are the assistant's tools, and they were reachable ONLY through
/// the assistant — so a teacher who declined its download could not publish
/// a page by name, take a change back, or make room for a class at all.
///
/// **One entry point, the tool's own.** Each item builds an `AssistToolCall`
/// in code and runs it through `AssistToolRunner.run(call:)` — the function
/// the model, a fixed phrasing and an outside assistant all reach — on a
/// runner whose surface is `.menu`. Never through a model: nothing here
/// needs one, or knows whether one was ever downloaded. REJECTED: lifting
/// each tool's private function into a shared typed one. The reference
/// course gate and the outside-change hold sit in `run(call:)` BEFORE the
/// tool is dispatched, so a menu calling an extracted function would skip
/// them unless they were copied, and a copy is the drift this design exists
/// to stop.
///
/// **One per window, and it keeps its undo list.** Held by the window's
/// `WorkspaceModel` (`sectionVerbs(for:)`) and made the first time an item
/// is used, so Undo Last Change takes back the last change made from the
/// menu in THIS window. The assistant's window keeps its own list.
/// REJECTED: a runner per action (no undo at all); sharing the assistant
/// window's runner (a larger refactor, and a teacher with no assistant has
/// no window for it to live in). Rebuilt when the window opens another
/// folder, which drops its undo list — a list of changes to a folder that is
/// no longer showing.
///
/// **Over its own `WorkspaceModel`**, adopted from the folder's path the way
/// `AssistSession.beginConversation` adopts one: a runner is never built
/// over a window's model (#322), because its per-call read refuses a
/// window's copy to keep that window's unsaved settings.
@Observable
@MainActor
final class SectionVerbs {

    // MARK: - Types

    /// A section, by course and number.
    struct SectionKey: Equatable, Sendable {
        let courseCode: String
        let sectionNumber: Int
    }

    // MARK: - Stored properties

    /// The working folder this window's runner works in.
    let folderPath: String

    /// The tool runner. Not private: a test reads what it wrote.
    @ObservationIgnored let toolRunner: AssistToolRunner

    /// The item running now, or nil. One at a time per window: the menu
    /// greys its verbs while one runs (`SubjectMenuRules.Situation.verbIsRunning`).
    private(set) var running: SubjectMenuRules.Item?

    /// The section the last change made from the menu was made in — what
    /// Undo Last Change would take back. Read off the runner after every
    /// item, because the runner's history is not observed.
    private(set) var lastChange: SectionKey?

    // MARK: - Computed properties

    var isRunning: Bool {
        return running != nil
    }

    /// The course whose copy is being saved before a change, for the line
    /// the sheet shows while it waits (#351's reason: a big course takes
    /// seconds to zip, and dots alone read as a hang).
    var courseBeingBackedUp: String? {
        return toolRunner.courseBeingBackedUp
    }

    // MARK: - Initializer

    init(folderPath: String,
         siteWork: AssistSiteWork? = nil,
         today: @escaping () -> CalendarDay = { return CalendarDay.today() }) {
        self.folderPath = folderPath
        let workspace: WorkspaceModel = WorkspaceModel()
        workspace.adoptRestoredPath(folderPath)
        self.toolRunner = AssistToolRunner(
            workspace: workspace, siteWork: siteWork, today: today, surface: .menu
        )
    }

    // MARK: - Functions

    /// The plan twin's answer: what the change WOULD do, with nothing
    /// written — the sheet's plan: `planTable` for the three page plans
    /// (#524), the card's text, `forTheCard`, for the rest.
    func plan(_ call: AssistToolCall) async -> AssistToolOutcome {
        return await toolRunner.run(call: call)
    }

    /// Runs one item's call, with the menu's claim on the section held for
    /// the whole of it (`SectionMenuActivity`), and one line on the trail.
    ///
    /// `counts` is what the line says besides how it ended — "3 pages
    /// ticked" — and never a page's title.
    func perform(
        _ call: AssistToolCall,
        item: SubjectMenuRules.Item,
        courseCode: String,
        sectionNumber: Int,
        counts: String = ""
    ) async -> AssistToolOutcome {
        running = item
        SectionMenuActivity.begin(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)
        let before: SectionKey? = currentLastChange()
        let changesBefore: Int = toolRunner.changeCount
        let writesBefore: Int = toolRunner.writesWithNoNewUndoEntry
        let outcome: AssistToolOutcome = await toolRunner.run(call: call)
        let changesAfter: Int = toolRunner.changeCount
        let writesAfter: Int = toolRunner.writesWithNoNewUndoEntry
        lastChange = currentLastChange()
        SectionMenuActivity.end(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)
        running = nil

        // Something was written when the undo list moved, when the change it
        // would take back moved, OR when the runner wrote files with no new
        // undo entry (#531: Make Room, a partial undo, a publish that stopped
        // part way — each "changed nothing" here until then). The depth
        // alone is not the signal; it is what tells "took the last change
        // back" from "carried out" — and, for Undo, a whole undo (the entry
        // came off the list) from a partial one (it stayed, files went back:
        // "took part of the last change back", ruling L2 on #531).
        let undoListMoved: Bool = changesAfter != changesBefore || before != lastChange
        var ending: String = "changed nothing"
        if item == .undoLastChange {
            ending = SectionVerbs.undoEnding(
                undoListMoved: undoListMoved, wroteWithNoNewUndoEntry: writesAfter != writesBefore
            )
        } else if undoListMoved || writesAfter != writesBefore {
            ending = "carried out"
        } else if item == .rebuildPreview {
            let rebuilding: String = AssistWording.previewIsRebuilding(course: courseCode, section: String(sectionNumber))
            let builtHeadless: String = AssistWording.builtWithNoWindowOpen(course: courseCode, section: String(sectionNumber))
            if outcome.summary == rebuilding || outcome.summary == builtHeadless {
                ending = "rebuilt"
            } else {
                ending = "not rebuilt"
            }
        }
        SectionVerbs.noteRan(item, ending: ending, counts: counts, courseCode: courseCode, sectionNumber: sectionNumber)
        return outcome
    }

    /// How Undo Last Change's "ran from a menu" line ends — the three
    /// endings of #531, in one place so `undoFiles.presses` in the contract
    /// (#555) can name them per press. A press that only found files already
    /// back takes the entry off, so it ends "took the last change back".
    static func undoEnding(undoListMoved: Bool, wroteWithNoNewUndoEntry: Bool) -> String {
        if undoListMoved {
            return "took the last change back"
        }
        if wroteWithNoNewUndoEntry {
            return "took part of the last change back"
        }
        return "changed nothing"
    }

    /// A plan the teacher cancelled, or a sheet closed before anything ran.
    func noteCancelled(_ item: SubjectMenuRules.Item, courseCode: String, sectionNumber: Int, counts: String = "") {
        SectionVerbs.noteRan(item, ending: "cancelled at the plan", counts: counts,
                             courseCode: courseCode, sectionNumber: sectionNumber)
    }

    private func currentLastChange() -> SectionKey? {
        guard let pending = toolRunner.lastChange else {
            return nil
        }
        return SectionKey(courseCode: pending.courseCode, sectionNumber: pending.sectionNumber)
    }

    /// Whether Undo Last Change would act on this section.
    func lastChangeIsIn(courseCode: String, sectionNumber: Int) -> Bool {
        guard let lastChange else {
            return false
        }
        return lastChange.courseCode.lowercased() == courseCode.lowercased() && lastChange.sectionNumber == sectionNumber
    }

    // MARK: - The trail

    /// `ranFromAMenu`: "Section ▸ Publish Pages… — carried out, 3 pages
    /// ticked". Never a page's title.
    static func ranLine(_ item: SubjectMenuRules.Item, ending: String, counts: String) -> String {
        var line: String = "\(menuPath(of: item)) — \(ending)"
        if !counts.isEmpty {
            line += ", " + counts
        }
        return line
    }

    static func noteRan(_ item: SubjectMenuRules.Item, ending: String, counts: String,
                        courseCode: String, sectionNumber: Int) {
        ActivityTrail.note(
            .ranFromAMenu, ranLine(item, ending: ending, counts: counts),
            course: courseCode, section: sectionNumber
        )
    }

    /// Where the item is, the way a teacher would say it.
    static func menuPath(of item: SubjectMenuRules.Item) -> String {
        switch item {
        case .publishPages:
            return "Section ▸ Publish Pages…"
        case .hidePages:
            return "Section ▸ Hide Pages…"
        case .publishClassForADate:
            return "Section ▸ Publish Class for a Date…"
        case .rebuildPreview:
            return "Section ▸ Rebuild Preview"
        case .undoLastChange:
            return "Section ▸ Undo Last Change"
        case .addNextClass:
            return "Section ▸ Add Next Class"
        case .addNextClassInANewUnit:
            return "Section ▸ Add Next Class in a New Unit"
        case .duplicateAsNextClass:
            return "Section ▸ Duplicate as Next Class…"
        case .reDateClasses:
            return "Section ▸ Re-date Classes…"
        case .makeRoomForClasses:
            return "Section ▸ Make Room for Classes…"
        case .classDates:
            return "Section ▸ Class Dates…"
        default:
            return item.rawValue
        }
    }

    // MARK: - The calls, built in code

    /// A call, as a client would send it.
    static func call(_ name: String, _ arguments: [String: Any]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])) ?? Data("{}".utf8)
        return AssistToolCall(
            id: "menu-" + UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(name: name, arguments: String(decoding: encoded, as: UTF8.self))
        )
    }

    /// Publish Pages… (or its plan): the pages by FOLDER and name, as a JSON
    /// array (#457's plan review, finding 3). A bare file name is refused
    /// when two pages share it — every shipped course has five to nine
    /// called `_DUPLICATE ME` — and a name holding a semicolon would be split
    /// in two by the tool's own list reading; the folder form is the one
    /// `AssistSectionGraph.pagesWhoseFileIsCalled` already honours.
    static func publishPages(course: String, section: Int, names: [String], planning: Bool) -> AssistToolCall {
        return call(planning ? "plan_publish_pages" : "publish_pages",
                    ["course": course, "section": section, "pages": names])
    }

    /// Hide Pages… (or its plan). `unpublish_pages`: a verb in the tool's
    /// NAME, never a flag (the polarity rule at the top of the runner).
    static func hidePages(course: String, section: Int, names: [String], planning: Bool) -> AssistToolCall {
        return call(planning ? "plan_unpublish_pages" : "unpublish_pages",
                    ["course": course, "section": section, "pages": names])
    }

    static func publishClass(course: String, section: Int, on day: CalendarDay, planning: Bool) -> AssistToolCall {
        return call(planning ? "plan_publish_class_on" : "publish_class_on",
                    ["course": course, "section": section, "date": day.text])
    }

    static func rebuildPreview(course: String, section: Int) -> AssistToolCall {
        return call("rebuild_preview", ["course": course, "section": section])
    }

    static func undoLastChange() -> AssistToolCall {
        return call("undo_last_change", [:])
    }

    static func addNextClass(course: String, section: Int) -> AssistToolCall {
        return call("add_next_class", ["course": course, "section": section])
    }

    /// Add Next Class in a New Unit (#897): `unit: "next"`, the argument the
    /// window's "Start a new unit for the next class" phrasing sends. The
    /// runner already read it; no schema shows it, so nothing the local
    /// model is shown moves.
    static func addNextClassInANewUnit(course: String, section: Int) -> AssistToolCall {
        return call("add_next_class", ["course": course, "section": section, "unit": "next"])
    }

    /// Duplicate as Next Class… (or its plan, #897): the source named by its
    /// FILE inside the course (`coursePath(ofPageAt:in:)`), in an argument
    /// the runner reads from the menu only
    /// (`AssistToolRunner.menuDuplicateFileArgument`). Never `duplicate`,
    /// the window's title-named argument: a title can fit two pages, and that
    /// path puts the copy right after the source and moves later classes,
    /// where Russell's ruling puts it at the end.
    static func duplicateAsNextClass(course: String, section: Int, sourcePath: String, planning: Bool) -> AssistToolCall {
        return call(planning ? "plan_add_next_class" : "add_next_class",
                    ["course": course, "section": section, AssistToolRunner.menuDuplicateFileArgument: sourcePath])
    }

    /// Re-date Classes… (or its plan). No `website` key, ever: that key
    /// makes it a rollover, which the menu is not.
    static func reDateClasses(course: String, section: Int, planning: Bool) -> AssistToolCall {
        return call(planning ? "plan_re_date_classes" : "re_date_classes",
                    ["course": course, "section": section])
    }

    static func makeRoom(course: String, section: Int, unit: Int, atDay: Int, howMany: Int, planning: Bool) -> AssistToolCall {
        return call(planning ? "plan_make_room_for_classes" : "make_room_for_classes",
                    ["course": course, "section": section, "unit": unit, "atDay": atDay, "howMany": howMany])
    }

    /// What a page is called in the call: its folder within the course, then
    /// its file name without `.md` — "section1/All Classes/Unit 2, Day 3".
    static func name(ofPageAt fileURL: URL, in course: Course) -> String {
        let folder: String = StartOfYearPageNaming.folder(
            of: fileURL, courseDirectoryURL: course.directoryURL, courseCode: course.code
        )
        return folder + "/" + fileURL.deletingPathExtension().lastPathComponent
    }

    /// A page's path inside its course folder, `.md` included —
    /// "section1/All Classes/Unit 2, Day 3.md" — for the menu's duplicate
    /// (#897), which names exactly one file.
    static func coursePath(ofPageAt fileURL: URL, in course: Course) -> String {
        let page: String = fileURL.standardizedFileURL.path
        let folder: String = course.directoryURL.standardizedFileURL.path + "/"
        if page.hasPrefix(folder) {
            return String(page.dropFirst(folder.count))
        }
        return fileURL.lastPathComponent
    }

    // MARK: - What the #897 items are greyed by

    /// The three facts Add Next Class in a New Unit and Duplicate as Next
    /// Class… are greyed by. Read when the section window is shown, when it
    /// comes to the front and after each function, never per drawing of the
    /// menu (the plan review's amendment 4).
    struct ClassFacts: Equatable {

        // MARK: - Stored properties

        var classPagesAreNumbered: Bool = false
        var unitWordRenameUnfinished: Bool = false
        var hasAClassPage: Bool = false
    }

    static func classFacts(forSection sectionNumber: Int, in course: Course) -> ClassFacts {
        var facts: ClassFacts = ClassFacts()
        facts.classPagesAreNumbered = course.configuration.classPageNaming.isNumbered
        facts.unitWordRenameUnfinished = unitWordRenameRecordIsThere(for: course)
        facts.hasAClassPage = hasAClassPage(forSection: sectionNumber, in: course)
        return facts
    }

    /// The cheap fact: the record a unit-word rename leaves while it runs is
    /// on disk. The full check, which reads every class folder and clears a
    /// stale record, runs at the click (`UnitWordRenamer.interruptedRenameTarget`,
    /// in the runner).
    static func unitWordRenameRecordIsThere(for course: Course) -> Bool {
        let record: URL = UnitWordRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        return FileManager.default.fileExists(atPath: record.path)
    }

    /// Whether the section's class folders hold any page but their landing
    /// pages: the names only, no page read.
    static func hasAClassPage(forSection sectionNumber: Int, in course: Course) -> Bool {
        for folderName in ClassFolder.names(for: course) {
            let root: URL = course.sectionDirectoryURL(forSection: sectionNumber).appendingPathComponent(folderName)
            for pageURL in ClassPages.markdownPages(under: root) where pageURL.lastPathComponent.lowercased() != "index.md" {
                return true
            }
        }
        return false
    }

    // MARK: - Class dates

    /// Whether this section has no class dates on file — asked BEFORE Add
    /// Next Class, Re-date Classes… and Make Room for Classes…, so the
    /// section window asks for them itself (#457's plan review, blocker 1)
    /// rather than the tool leaving a request only the assistant's window
    /// can show.
    static func hasNoTimetable(forSection sectionNumber: Int, in course: Course) -> Bool {
        let remembered: SectionTimetable? = try? SectionTimetableStore.read(forSection: sectionNumber, in: course)
        return remembered == nil
    }
}

/// One of the assistant's functions asked for from a section row's context
/// menu, waiting for that section's window to take it.
struct SectionVerbRequest: Equatable, Identifiable {

    // MARK: - Stored properties

    let id: UUID = UUID()
    let item: SubjectMenuRules.Item
    let courseCode: String
    let sectionNumber: Int
}

/// Which sections the Section menu is changing right now — the menu's own
/// claim (#457's ruling on the plan review): never the assistant window's
/// `AssistActivity` hold, which it would replace, reopening #242. While a
/// menu change runs on a section, the in-app assistant's change to the same
/// section is refused before anything is written (`AssistToolRunner.
/// menuChangeHeldBack`), so two undo lists never interleave.
@MainActor
enum SectionMenuActivity {

    // MARK: - Types

    struct Key: Hashable {

        // MARK: - Stored properties

        let folderPath: String
        let courseCode: String
        let sectionNumber: Int

        // MARK: - Initializer

        init(folderPath: String, courseCode: String, sectionNumber: Int) {
            self.folderPath = FolderIdentity.canonicalPath(URL(fileURLWithPath: folderPath).standardizedFileURL.path)
            self.courseCode = courseCode.lowercased()
            self.sectionNumber = sectionNumber
        }
    }

    @Observable
    final class Store {
        var changing: [Key: Int] = [:]
    }

    // MARK: - Stored properties

    static let store: Store = Store()

    // MARK: - Functions

    static func begin(folderPath: String, courseCode: String, sectionNumber: Int) {
        let key: Key = Key(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)
        store.changing[key] = (store.changing[key] ?? 0) + 1
    }

    static func end(folderPath: String, courseCode: String, sectionNumber: Int) {
        let key: Key = Key(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)
        let left: Int = (store.changing[key] ?? 1) - 1
        if left <= 0 {
            store.changing.removeValue(forKey: key)
        } else {
            store.changing[key] = left
        }
    }

    /// Whether the menu is changing that section — or, with no section, any
    /// section of the course.
    static func isChanging(folderPath: String, courseCode: String, sectionNumber: Int?) -> Bool {
        for (key, _) in store.changing {
            let probe: Key = Key(folderPath: folderPath, courseCode: courseCode, sectionNumber: key.sectionNumber)
            if probe.folderPath != key.folderPath || probe.courseCode != key.courseCode {
                continue
            }
            if let sectionNumber, sectionNumber != key.sectionNumber {
                continue
            }
            return true
        }
        return false
    }

    /// Tests only.
    static func reset() {
        store.changing = [:]
    }
}
