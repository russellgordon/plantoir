import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Section ▸ Publish Pages… and Hide Pages… as a tree of checkboxes (#900):
/// the grouping rule against `contracts/class-planning.json` → `pagesToTick`,
/// the sheet's model on top of it, the drawn box's mixed state, and the
/// promise that makes the piece safe: a unit's box sends exactly what ticking
/// its pages one by one sent, so the plan, the write and the undo step are
/// the existing ones.
///
/// Sentences are named by their `AssistWording` member, never quoted.
@MainActor
final class PageTickTreeTests: XCTestCase {

    // MARK: - Stored properties

    var roots: [URL] = []

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        SectionMenuActivity.reset()
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
        roots = []
        try await super.tearDown()
    }

    // MARK: - The contract

    /// Every `pagesToTick` case: the tree for its search and ticks, the
    /// count of ticked pages out of view, each click's ticks and state, and
    /// the names the call carries after them.
    func testEveryCaseIsTheContracts() throws {
        let section: [String: Any] = try PageTickTreeTests.contractSection()
        XCTAssertNotNil(section["note"] as? String)
        XCTAssertNotNil(section["why"] as? String)
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 14)
        var checks: Int = 0
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let naming: ClassPageNaming = ClassPageNaming(
                word: try XCTUnwrap(testCase["term"] as? String),
                scheme: ClassPageScheme.reading(testCase["scheme"] as? String)
            )
            let noun: ClassNoun = ClassNoun.reading(testCase["noun"] as? String)
            let names: PageTickTree.GroupNames = PageTickTree.GroupNames(
                otherClasses: AssistWording.menuPageGroupOtherClasses(noun: noun),
                allClasses: AssistWording.menuPageGroupAllClasses(noun: noun)
            )
            let offered: [PageTickTree.Page] = try PageTickTreeTests.pages(of: testCase)
            let groups: [PageTickTree.Group] = PageTickTree.groups(
                of: offered, naming: naming, courseCode: try XCTUnwrap(testCase["course"] as? String), names: names
            )
            let search: String = try XCTUnwrap(testCase["search"] as? String)
            var ticked: Set<String> = Set(try XCTUnwrap(testCase["ticked"] as? [String]))
            let rows: [PageTickTree.Row] = PageTickTree.rows(of: groups, search: search)
            if let expected = testCase["expectTree"] {
                checks += 1
                XCTAssertEqual(
                    try PageTickTreeTests.canonical(PageTickTreeTests.describe(rows, ticked: ticked)),
                    try PageTickTreeTests.canonical(expected), name
                )
            }
            if let count = testCase["expectGroupCount"] as? Int {
                checks += 1
                XCTAssertEqual(rows.count, count, name)
            }
            if let expected = testCase["expectNotShownTicked"] as? Int {
                checks += 1
                XCTAssertEqual(PageTickTree.tickedButNotShown(offered, ticked: ticked, search: search), expected, name)
            }
            for click in (testCase["clicks"] as? [[String: Any]]) ?? [] {
                let path: [String] = try XCTUnwrap(click["group"] as? [String])
                let group: PageTickTree.Group = try XCTUnwrap(PageTickTree.group(at: path, in: groups), "\(name): \(path)")
                let row: PageTickTree.Row = try XCTUnwrap(
                    PageTickTree.row(withID: .group(group.key), in: PageTickTree.rows(of: groups, search: search)),
                    "\(name): \(path) is not drawn"
                )
                ticked = PageTickTree.clicking(row.shownPageNames, ticked: ticked)
                checks += 1
                if let expected = click["expectTicked"] as? [String] {
                    XCTAssertEqual(ticked, Set(expected), "\(name): after \(path)")
                }
                if let expected = click["expectTickedCount"] as? Int {
                    XCTAssertEqual(ticked.count, expected, "\(name): after \(path)")
                }
                if let expected = click["expectState"] as? String {
                    XCTAssertEqual(PageTickTree.state(of: row.shownPageNames, ticked: ticked).rawValue, expected, "\(name): after \(path)")
                }
            }
            if let expected = testCase["expectSent"] as? [String] {
                checks += 1
                XCTAssertEqual(PageTickTree.namesToSend(offered, ticked: ticked), expected, name)
            }
            if let expected = testCase["expectSentCount"] as? Int {
                checks += 1
                XCTAssertEqual(PageTickTree.namesToSend(offered, ticked: ticked).count, expected, name)
            }
        }
        XCTAssertGreaterThanOrEqual(checks, 45, "the cases have stopped being read")
    }

    /// The two class groups' names in the contract are the wording keys it
    /// names, in both nouns, and a club's twin says meetings.
    func testTheGroupNamesAreTheWordingTheContractNames() {
        XCTAssertNotEqual(AssistWording.menuPageGroupOtherClasses(), AssistWording.menuPageGroupOtherClasses(noun: .meeting))
        XCTAssertNotEqual(AssistWording.menuPageGroupAllClasses(), AssistWording.menuPageGroupAllClasses(noun: .meeting))
        XCTAssertTrue(AssistWording.menuPageGroupOtherClasses(noun: .meeting).contains("meeting"))
        XCTAssertTrue(AssistWording.menuPageGroupAllClasses(noun: .meeting).contains("meeting"))
        XCTAssertFalse(AssistWording.menuPageGroupAllClasses(noun: .meeting).contains("class"))
    }

    // MARK: - The sheet's model

    /// The model builds the tree from the rows it is given, with the course's
    /// naming and noun: a club's classes are one group named for meetings.
    func testTheTreeIsBuiltFromTheRowsInTheCoursesWords() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        roots.append(made.root)
        made.course.configuration.unitWord = "Week"
        made.course.configuration.classPageScheme = .numbered
        made.course.configuration.classNoun = .meeting
        let model: SectionVerbSheetModel = PageTickTreeTests.model(course: made.course, rows: [
            PageTickTreeTests.classRow("Week 2", day: 16, in: made.course),
            PageTickTreeTests.classRow("Week 1", day: 9, in: made.course),
            PageTickTreeTests.otherRow("Concepts", "Loops", in: made.course),
        ])
        var titles: [String] = []
        for row in model.tickRows {
            titles.append(row.title)
        }
        XCTAssertEqual(titles, [AssistWording.menuPageGroupAllClasses(noun: .meeting), "Concepts"])
        let meetings: PageTickTree.Row = model.tickRows[0]
        XCTAssertEqual(meetings.shownPageNames, ["section1/All Classes/Week 1", "section1/All Classes/Week 2"])
        XCTAssertEqual(PageTickTree.groupsStartFolded, model.openGroups.isEmpty, "the groups do not start as the rule says")
    }

    /// A click on a unit's box: mixed goes to every page ticked, ticked goes
    /// to none, and the trail's count says how many a group's box ticked; a
    /// page's own box afterwards takes that page out of the count.
    func testAUnitsBoxTicksEveryPageAndTheTrailCountsIt() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        roots.append(made.root)
        let model: SectionVerbSheetModel = PageTickTreeTests.unitModel(course: made.course, classes: 3, pages: 1)
        let unit: PageTickTree.Row = model.tickRows[0]
        model.binding(forPageNamed: "section1/All Classes/Unit 1, Day 2").wrappedValue = true
        XCTAssertEqual(model.state(of: unit), .mixed)
        model.click(group: unit)
        XCTAssertEqual(model.state(of: unit), .on)
        XCTAssertEqual(model.ticked.count, 3, "a mixed box did not tick every page under it")
        XCTAssertEqual(model.tickedByAGroupsBoxCount, 3)
        XCTAssertFalse(model.ticked.contains("Concepts/Page 1"), "a unit's box ticked a page that is not one of its classes")
        model.binding(forPageNamed: "section1/All Classes/Unit 1, Day 3").wrappedValue = false
        XCTAssertEqual(model.state(of: unit), .mixed)
        XCTAssertEqual(model.tickedByAGroupsBoxCount, 2)
        model.click(group: unit)
        model.click(group: unit)
        XCTAssertTrue(model.ticked.isEmpty, "a ticked box did not clear its pages")
        XCTAssertEqual(model.tickedByAGroupsBoxCount, 0)
    }

    /// Space on a selected group does what its box does; on a page, it flips
    /// that page alone; on a row the search hides, nothing.
    func testSpaceOnAGroupTicksItsShownPages() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        roots.append(made.root)
        let model: SectionVerbSheetModel = PageTickTreeTests.unitModel(course: made.course, classes: 3, pages: 2)
        model.search = "Day 1"
        let unitID: PageTickTree.RowID = model.tickRows[0].id
        model.flip(unitID)
        XCTAssertEqual(model.ticked, ["section1/All Classes/Unit 1, Day 1"], "Space on a group changed a page the search hides")
        model.flip(.page("section1/All Classes/Unit 1, Day 1"))
        XCTAssertTrue(model.ticked.isEmpty)
        model.flip(.page("Concepts/Page 1"))
        XCTAssertTrue(model.ticked.isEmpty, "Space changed a page the search hides")
    }

    /// The search opens every group it shows, so a match is never inside a
    /// folded group; clearing it puts back the groups that were open before.
    func testTheSearchOpensItsGroupsAndClearingItPutsThemBack() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        roots.append(made.root)
        let model: SectionVerbSheetModel = PageTickTreeTests.unitModel(course: made.course, classes: 3, pages: 2)
        let concepts: PageTickTree.RowID = .group("folder Concepts")
        model.openGroups = [concepts]
        model.search = "Day"
        XCTAssertEqual(model.openGroups, [.group("unit 1"), concepts])
        model.search = "Day 2"
        XCTAssertTrue(model.openGroups.contains(.group("unit 1")))
        model.search = ""
        XCTAssertEqual(model.openGroups, [concepts], "clearing the search did not put the open groups back")
        XCTAssertNil(model.openGroupsBeforeTheSearch)
    }

    // MARK: - What Publish writes

    /// THE promise of #900: a unit's box sends the same call, byte for byte,
    /// as ticking its pages one by one, and through the real runner on the
    /// menu's surface it writes the same files, says the same thing and
    /// leaves ONE undo step holding every page (#899's shadow list, written
    /// through its door by `carryOut`). Run for Publish and for Hide.
    func testAUnitsBoxWritesWhatTickingItsPagesOneByOneWrote() async throws {
        for publishing in [true, false] {
            let byPage = try PageTickTreeTests.courseWithAUnit(publishing: publishing)
            roots.append(byPage.made.root)
            let byUnit = try PageTickTreeTests.courseWithAUnit(publishing: publishing)
            roots.append(byUnit.made.root)

            let onePageAtATime: SectionVerbSheetModel = SectionVerbSheetModel.choosingPages(
                publishing: publishing, course: byPage.made.course, sectionNumber: 1, workspaceURL: byPage.made.root
            )
            for row in onePageAtATime.pageRows where row.isClass {
                onePageAtATime.binding(for: row).wrappedValue = true
            }
            let oneUnit: SectionVerbSheetModel = SectionVerbSheetModel.choosingPages(
                publishing: publishing, course: byUnit.made.course, sectionNumber: 1, workspaceURL: byUnit.made.root
            )
            let unit: PageTickTree.Row = try XCTUnwrap(PageTickTree.row(withID: .group("unit 1"), in: oneUnit.tickRows))
            oneUnit.click(group: unit)

            let pageNames: [String] = PageTickTreeTests.names(of: onePageAtATime)
            let unitNames: [String] = PageTickTreeTests.names(of: oneUnit)
            XCTAssertEqual(unitNames.count, 3, "the unit's box did not tick its three classes")
            XCTAssertEqual(unitNames, pageNames)
            let pageCall: AssistToolCall = publishing
                ? SectionVerbs.publishPages(course: "ICS3U", section: 1, names: pageNames, planning: false)
                : SectionVerbs.hidePages(course: "ICS3U", section: 1, names: pageNames, planning: false)
            let unitCall: AssistToolCall = publishing
                ? SectionVerbs.publishPages(course: "ICS3U", section: 1, names: unitNames, planning: false)
                : SectionVerbs.hidePages(course: "ICS3U", section: 1, names: unitNames, planning: false)
            XCTAssertEqual(Data(unitCall.function.arguments.utf8), Data(pageCall.function.arguments.utf8))
            XCTAssertEqual(unitCall.function.name, pageCall.function.name)

            UndoJournalLocation.folderOverride = byPage.list
            let pageOutcome: AssistToolOutcome = await byPage.made.runner.run(call: pageCall)
            UndoJournalLocation.folderOverride = byUnit.list
            let unitOutcome: AssistToolOutcome = await byUnit.made.runner.run(call: unitCall)
            UndoJournalLocation.folderOverride = nil

            XCTAssertEqual(unitOutcome.summary, pageOutcome.summary)
            XCTAssertEqual(unitOutcome.detail, pageOutcome.detail)
            XCTAssertEqual(
                try PageTickTreeTests.everyPage(in: byUnit.made.course),
                try PageTickTreeTests.everyPage(in: byPage.made.course),
                "a unit's box wrote something different"
            )
            let fold: UndoFold = try UndoJournal(folderURL: byUnit.list).read()
            XCTAssertEqual(fold.records.count, 1, "a unit's box is not one undo step")
            let record: UndoStepRecord = try XCTUnwrap(fold.records[1])
            var classesInTheStep: Set<String> = []
            for op in record.step.ops where op.kind == "editLine" && op.key == "publish" {
                let path: String = op.path ?? ""
                if path.contains("/All Classes/Unit 1, Day ") {
                    classesInTheStep.insert(path)
                }
            }
            XCTAssertEqual(classesInTheStep.count, 3, "the one step does not hold every class of the unit: \(classesInTheStep)")
            XCTAssertEqual(record.step.madeBy, "menu")
        }
    }

    // MARK: - The drawn box

    /// The group's box is drawn MIXED when only some of its pages are
    /// ticked, a click on it ticks every page and draws it on, and a second
    /// click clears them: the model decides, never AppKit's own cycle.
    func testTheDrawnBoxIsMixedAndAClickTicksEveryPage() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        roots.append(made.root)
        let model: SectionVerbSheetModel = PageTickTreeTests.unitModel(course: made.course, classes: 3, pages: 2)
        model.binding(forPageNamed: "section1/All Classes/Unit 1, Day 2").wrappedValue = true
        let sheet: SectionVerbSheet = SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
        let host: TableHost = TableHost(sheet, size: PageTablesSheetTests.fittingSize(of: sheet))
        defer {
            host.close()
        }
        let table: NSTableView = try XCTUnwrap(host.tables().first, "the picker is not a table")
        XCTAssertEqual(table.numberOfRows, 2, "the groups do not start folded")
        let box: NSButton = try XCTUnwrap(PageTickTreeTests.button(identified: "sectionVerbGroup-unit 1", in: host.window))
        XCTAssertTrue(box.allowsMixedState)
        XCTAssertEqual(box.state, .mixed, "a unit with one page of three ticked is not drawn mixed")
        XCTAssertEqual(box.accessibilityValueDescription(), AssistWording.menuPageGroupTickedCount(ticked: 1, of: 3))
        PageTablesSheetTests.click(box, in: host)
        XCTAssertEqual(model.ticked.count, 3, "a click on a mixed box did not tick every page")
        XCTAssertEqual(box.state, .on)
        PageTablesSheetTests.click(box, in: host)
        XCTAssertTrue(model.ticked.isEmpty, "a click on a ticked box did not clear its pages")
        XCTAssertEqual(box.state, .off)
    }

    /// A ticked page the search hides is said under the table.
    func testATickedPageTheSearchHidesIsSaid() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        roots.append(made.root)
        let model: SectionVerbSheetModel = PageTickTreeTests.unitModel(course: made.course, classes: 3, pages: 2)
        model.binding(forPageNamed: "Concepts/Page 1").wrappedValue = true
        model.search = "Day"
        XCTAssertEqual(model.tickedButNotShown, 1)
        XCTAssertEqual(PageTickTreeTests.names(of: model), ["Concepts/Page 1"], "a ticked page out of view left the plan")
    }

    // MARK: - Helpers

    static func contractSection() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/class-planning.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["pagesToTick"] as? [String: Any])
    }

    /// A case's pages: the generated ones first, then its own.
    static func pages(of testCase: [String: Any]) throws -> [PageTickTree.Page] {
        var made: [PageTickTree.Page] = []
        if let generate = testCase["generate"] as? [String: Any] {
            let unit: Int = try XCTUnwrap(generate["unit"] as? Int)
            let days: Int = try XCTUnwrap(generate["days"] as? Int)
            let folder: String = try XCTUnwrap(generate["folder"] as? String)
            var day: Int = 1
            while day <= days {
                let title: String = "Unit \(unit), Day \(day)"
                made.append(PageTickTree.Page(name: folder + "/" + title, title: title, folder: folder, isClass: true, date: nil))
                day += 1
            }
        }
        for raw in try XCTUnwrap(testCase["pages"] as? [[String: Any]]) {
            var date: CalendarDay? = nil
            if let text = raw["date"] as? String {
                date = try XCTUnwrap(CalendarDay(text: text))
            }
            made.append(PageTickTree.Page(
                name: try XCTUnwrap(raw["name"] as? String),
                title: try XCTUnwrap(raw["title"] as? String),
                folder: try XCTUnwrap(raw["folder"] as? String),
                isClass: try XCTUnwrap(raw["isClass"] as? Bool),
                date: date
            ))
        }
        return made
    }

    /// The tree as the contract writes it: each group's name, state, pages
    /// directly in it, and its groups.
    static func describe(_ rows: [PageTickTree.Row], ticked: Set<String>) -> [[String: Any]] {
        var nodes: [[String: Any]] = []
        for row in rows where row.isGroup {
            var node: [String: Any] = [
                "group": row.title,
                "state": PageTickTree.state(of: row.shownPageNames, ticked: ticked).rawValue,
            ]
            var direct: [String] = []
            var inner: [PageTickTree.Row] = []
            for child in row.children ?? [] {
                if child.isGroup {
                    inner.append(child)
                } else if let page = child.page {
                    direct.append(page.name)
                }
            }
            node["pages"] = direct
            let groups: [[String: Any]] = describe(inner, ticked: ticked)
            if !groups.isEmpty {
                node["groups"] = groups
            }
            nodes.append(node)
        }
        return nodes
    }

    static func canonical(_ value: Any) throws -> String {
        let data: Data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func model(course: Course, rows: [SectionVerbSheetModel.PageRow]) -> SectionVerbSheetModel {
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .publishPages, course: course, sectionNumber: 1,
            title: AssistWording.menuPublishPagesTitle(course: "ICS3U", section: "1"),
            item: .publishPages
        )
        model.pageRows = rows
        return model
    }

    /// Publish Pages… with `classes` classes of Unit 1 and `pages` concept
    /// pages, as `PageTablesSheetTests.pickerModel` lays them out.
    static func unitModel(course: Course, classes: Int, pages: Int) -> SectionVerbSheetModel {
        return PageTablesSheetTests.pickerModel(course: course, classes: classes, pages: pages)
    }

    static func classRow(_ title: String, day: Int, in course: Course) -> SectionVerbSheetModel.PageRow {
        return SectionVerbSheetModel.PageRow(
            name: "section1/All Classes/" + title, title: title, folder: "section1/All Classes",
            fileURL: course.directoryURL.appendingPathComponent("section1/All Classes/\(title).md"),
            isClass: true, date: CalendarDay(year: 2026, month: 9, day: day)
        )
    }

    static func otherRow(_ folder: String, _ title: String, in course: Course) -> SectionVerbSheetModel.PageRow {
        return SectionVerbSheetModel.PageRow(
            name: folder + "/" + title, title: title, folder: folder,
            fileURL: course.directoryURL.appendingPathComponent("\(folder)/\(title).md"),
            isClass: false, date: nil
        )
    }

    /// The names the sheet's Continue sends (`planTheChoice` reads them so).
    static func names(of model: SectionVerbSheetModel) -> [String] {
        var names: [String] = []
        for row in model.tickedRows {
            names.append(row.name)
        }
        return names
    }

    /// A course on the menu's surface with Unit 1, Days 1 to 3 (hidden to
    /// publish, visible to hide), linking a concept page, and an undo list of
    /// its own.
    static func courseWithAUnit(publishing: Bool) throws -> (made: AssistFixture.Made, list: URL) {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(surface: .menu)
        let flag: String = publishing ? "false" : "true"
        try AssistFixture.write(page: "Unit 1, Day 1", publish: flag, date: "2026-09-08", body: "Uses [[Ohm]].", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: flag, date: "2026-09-09", body: "Two.", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 3", publish: flag, date: "2026-09-10", body: "Three.", in: made.course)
        try "---\ntitle: Ohm\npublish: \(flag)\n---\nV = IR.\n".write(
            to: made.course.directoryURL.appendingPathComponent("Concepts/Ohm.md"), atomically: true, encoding: .utf8
        )
        let list: URL = made.root.appendingPathComponent("undo-list", isDirectory: true)
        return (made: made, list: list)
    }

    /// Every Markdown file in the course, by path inside it, with its bytes.
    static func everyPage(in course: Course) throws -> [String: Data] {
        var pages: [String: Data] = [:]
        for url in ClassPages.markdownPages(under: course.directoryURL) {
            pages[SectionVerbs.coursePath(ofPageAt: url, in: course)] = try Data(contentsOf: url)
        }
        return pages
    }

    static func button(identified identifier: String, in window: NSWindow) -> NSButton? {
        guard let content = window.contentView else {
            return nil
        }
        return button(identified: identifier, under: content)
    }

    static func button(identified identifier: String, under view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.accessibilityIdentifier() == identifier {
            return button
        }
        for subview in view.subviews {
            if let found = button(identified: identifier, under: subview) {
                return found
            }
        }
        return nil
    }
}
