import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The Section menu's page sheets and Start of Year (v1.8.6: #608, #621,
/// #622): the picker and the later-classes list as tables, the plan listing
/// only the pages that change with the rest behind a disclosure, and every
/// one of these sheets resizable from the size it opened at before.
///
/// Sentences are named by their `AssistWording` member, never quoted.
@MainActor
final class PageTablesSheetTests: XCTestCase {

    // MARK: - Stored properties

    /// The sizes these sheets had on `dev` before v1.8.6 touched them,
    /// measured by `fittingSize(of:)` with no product change made
    /// (2a4ca8e68, macOS 26.6; the record is the piece's closing comment).
    /// A sheet opens at its fitted size, so these are the sizes a teacher saw.
    static let soyWorstCaseHeight: CGFloat = 606
    static let soyTwentyClassesHeight: CGFloat = 478
    static let soyFewPagesHeight: CGFloat = 466
    static let planOfTwentyOnePagesHeight: CGFloat = 454
    static let hidePlanOfTwoRowsHeight: CGFloat = 214
    static let finishedTextHeight: CGFloat = 124
    static let workingHeight: CGFloat = 124
    static let reDateCardHeight: CGFloat = 412

    /// Start of Year's Page, Folder and Why at 560 on `dev`: with the table's
    /// scroll bar shown, and without it.
    static let soyColumnsWithAScrollBar: [CGFloat] = [118.5, 88.5, 248]
    static let soyColumnsWithoutAScrollBar: [CGFloat] = [124, 94, 254]

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        SectionMenuActivity.reset()
        SectionSchedulePrompt.shared.stopAsking()
        StartOfYearUndoRegistry.shared.forgetAll()
        try await super.tearDown()
    }

    // MARK: - The picker (#608)

    /// The picker is a table: one row per page offered, under Page, Folder
    /// and Date, and a date only beside a class.
    func testThePickerHasARowPerPageUnderPageFolderAndDate() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let model: SectionVerbSheetModel = PageTablesSheetTests.pickerModel(course: made.course, classes: 3, pages: 2)
        let sheet: SectionVerbSheet = SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
        let host: TableHost = TableHost(sheet, size: PageTablesSheetTests.fittingSize(of: sheet))
        defer {
            host.close()
        }
        let table: NSTableView = try XCTUnwrap(host.tables().first, "the picker is not a table")
        XCTAssertEqual(table.numberOfRows, 5)
        XCTAssertEqual(PageTablesSheetTests.titles(of: table), [
            AssistWording.menuPlanPageColumn, AssistWording.menuPlanFolderColumn, AssistWording.menuPickDateColumn,
        ])
        XCTAssertEqual(table.rowHeight, ListTableMetrics.rowHeight)
        let firstClass: SectionVerbSheetModel.PageRow = model.pageRows[0]
        let date: CalendarDay = try XCTUnwrap(firstClass.date)
        XCTAssertEqual(sheet.dateCell(for: firstClass),
                       AssistWording.laterClassesDay(weekday: date.weekdayName, date: date.text))
        XCTAssertEqual(sheet.dateCell(for: model.pageRows[4]), "", "a page that is not a class has no date")
        XCTAssertEqual(table.enclosingScrollView?.frame.height, ListTableMetrics.height(forRowCount: 5, showsHeader: true))
    }

    /// A click on a row's checkbox ticks that page in the model, and a second
    /// click unticks it.
    func testAClickOnAPickerCheckboxTicksThatPage() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let model: SectionVerbSheetModel = PageTablesSheetTests.pickerModel(course: made.course, classes: 3, pages: 2)
        let sheet: SectionVerbSheet = SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
        let host: TableHost = TableHost(sheet, size: PageTablesSheetTests.fittingSize(of: sheet))
        defer {
            host.close()
        }
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        XCTAssertTrue(model.ticked.isEmpty)
        host.clickCell(of: table, column: 0, row: 3)
        XCTAssertEqual(model.ticked, [model.pageRows[3].name], "the click did not tick the page in its row")
        host.clickCell(of: table, column: 0, row: 3)
        XCTAssertTrue(model.ticked.isEmpty, "a second click did not untick it")
    }

    /// Space ticks the selected row (selecting alone ticks nothing); with
    /// the table focused and a row selected, Return still reaches Continue
    /// and Escape Cancel; and Space typed in Find a Page ticks nothing.
    func testSpaceTicksTheSelectedRowAndReturnAndEscapeStillReachTheButtons() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let model: SectionVerbSheetModel = PageTablesSheetTests.pickerModel(course: made.course, classes: 3, pages: 2)
        let presses: KeyPresses = KeyPresses()
        let sheet: SectionVerbSheet = SectionVerbSheet(
            model: model, pressDefault: { presses.defaults += 1 }, cancel: { presses.cancels += 1 }
        )
        let host: TableHost = TableHost(sheet, size: PageTablesSheetTests.fittingSize(of: sheet))
        defer {
            host.close()
        }
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        host.select(row: 2, in: table)
        XCTAssertTrue(host.window.firstResponder === table, "the table did not take focus")
        XCTAssertTrue(model.ticked.isEmpty, "selecting a row ticked it")
        host.pressSpace()
        XCTAssertEqual(model.ticked, [model.pageRows[2].name], "Space did not tick the selected row")
        XCTAssertTrue(model.defaultButtonIsEnabled)
        host.press(keyCode: 36, characters: "\r")
        XCTAssertEqual(presses.defaults, 1, "Return did not reach Continue with a row selected")
        host.press(keyCode: 53, characters: "\u{1b}")
        XCTAssertEqual(presses.cancels, 1, "Escape did not reach Cancel with a row selected")
        host.pressSpace()
        XCTAssertTrue(model.ticked.isEmpty, "a second Space did not untick it")

        let field: NSTextField = try XCTUnwrap(PageTablesSheetTests.editableTextField(in: host.window), "no Find a Page field")
        XCTAssertTrue(host.window.makeFirstResponder(field))
        host.pump()
        host.pressSpace()
        XCTAssertTrue(model.ticked.isEmpty, "Space in Find a Page ticked a row")
    }

    /// Typing in Find a Page narrows the rows and leaves the sheet's height
    /// where it was: the table is counted from every page, not the ones the
    /// search leaves showing.
    func testSearchingNarrowsThePickerWithoutMovingTheSheet() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let model: SectionVerbSheetModel = PageTablesSheetTests.pickerModel(course: made.course, classes: 0, pages: 11)
        let sheet: SectionVerbSheet = SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
        let before: NSSize = PageTablesSheetTests.fittingSize(of: sheet)
        let host: TableHost = TableHost(sheet, size: before)
        defer {
            host.close()
        }
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        XCTAssertEqual(table.numberOfRows, 11)
        model.search = "Page 1"
        host.pump()
        XCTAssertEqual(table.numberOfRows, 3, "Page 1, Page 10 and Page 11")
        let after: NSSize = PageTablesSheetTests.fittingSize(of: sheet)
        XCTAssertEqual(after.height, before.height, "the sheet changed height as the teacher typed")
    }

    /// The later-classes question at Publish and Deploy is the same table:
    /// Page (with its checkbox) and Date, every class ticked to begin with,
    /// and a click unticking one.
    func testTheLaterClassesListIsATableAClickUnticks() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .laterClassesAtDeploy, course: made.course, sectionNumber: 1, title: "", item: nil
        )
        let first: CalendarDay = try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 11))
        let second: CalendarDay = try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 14))
        model.ask(about: [
            ClassesDatedLater.Flagged(place: "section1/All Classes/Unit 2, Day 5", title: "Unit 2, Day 5", date: first),
            ClassesDatedLater.Flagged(place: "section1/All Classes/Unit 2, Day 6", title: "Unit 2, Day 6", date: second),
        ], nextDay: CalendarDay(year: 2026, month: 9, day: 9))
        let sheet: SectionVerbSheet = SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
        let host: TableHost = TableHost(sheet, size: PageTablesSheetTests.fittingSize(of: sheet))
        defer {
            host.close()
        }
        let table: NSTableView = try XCTUnwrap(host.tables().first, "the later classes are not a table")
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(PageTablesSheetTests.titles(of: table), [AssistWording.menuPlanPageColumn, AssistWording.menuPickDateColumn])
        XCTAssertEqual(model.laterTicked.count, 2)
        host.clickCell(of: table, column: 0, row: 1)
        XCTAssertEqual(model.laterTicked, ["section1/All Classes/Unit 2, Day 5"], "the click did not untick the class in its row")
        host.select(row: 1, in: table)
        host.pressSpace()
        XCTAssertEqual(model.laterTicked.count, 2, "Space did not tick the selected class again")
    }

    /// The tallest picker — forty pages — still fits a 13-inch screen
    /// (`CopyPageChecklist.tallestSheet`), and its table is really there at
    /// twelve rows.
    func testTheTallestPickerStaysOnTheScreen() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let model: SectionVerbSheetModel = PageTablesSheetTests.pickerModel(course: made.course, classes: 20, pages: 20)
        let height: CGFloat = PageTablesSheetTests.fittingSize(
            of: SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
        ).height
        XCTAssertLessThanOrEqual(height, CopyPageChecklist.tallestSheet, "the forty-page picker is \(height) pt")
        let table: CGFloat = ListTableMetrics.height(forRowCount: SectionVerbSheet.mostPickerRowsShown, showsHeader: true)
        XCTAssertGreaterThanOrEqual(height, table + 120, "only \(height) pt: the table or the words around it collapsed")
        print("PageTablesSheetTests: forty-page picker \(height) pt against \(CopyPageChecklist.tallestSheet)")
    }

    // MARK: - The default size

    /// Every sheet whose content this piece did not mean to change opens at
    /// exactly the size it had before (#621: "the 560 × 620 budget stays the
    /// minimum / default"): Start of Year in three shapes, a plan with
    /// nothing already right, and the text stages. Start of Year's columns
    /// at 560 are dev's too, which is what its two-line rows are worked out
    /// from (`widestOneLineReason`).
    func testTheSheetsOpenAtTheSizeTheyHadBefore() async throws {
        var made: [URL] = []
        defer {
            for root in made {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let worst = try AssistFixture.makeRunner()
        made.append(worst.root)
        try StartOfYearPlanTableTests.layOutTheWorstCase(in: worst.course)
        let worstModel: StartOfYearSheetModel = StartOfYearPlanTableTests.model(
            worst, scheduledDeploy: Date(timeIntervalSince1970: 1_800_000_000)
        )
        worstModel.load()
        worstModel.notice = StartOfYearWording.changedSinceShown
        let twenty = try AssistFixture.makeRunner()
        made.append(twenty.root)
        try StartOfYearPlanTableTests.layOutClasses(20, in: twenty.course)
        let twentyModel: StartOfYearSheetModel = StartOfYearPlanTableTests.model(twenty)
        twentyModel.load()
        let few = try AssistFixture.makeRunner()
        made.append(few.root)
        try StartOfYearPlanTableTests.layOutAFewPages(in: few.course)
        let fewModel: StartOfYearSheetModel = StartOfYearPlanTableTests.model(few)
        fewModel.load()

        let sizes: [(String, NSSize, CGFloat)] = [
            ("Start of Year, worst case", PageTablesSheetTests.fittingSize(of: StartOfYearSheet(model: worstModel)),
             PageTablesSheetTests.soyWorstCaseHeight),
            ("Start of Year, twenty classes", PageTablesSheetTests.fittingSize(of: StartOfYearSheet(model: twentyModel)),
             PageTablesSheetTests.soyTwentyClassesHeight),
            ("Start of Year, three rows", PageTablesSheetTests.fittingSize(of: StartOfYearSheet(model: fewModel)),
             PageTablesSheetTests.soyFewPagesHeight),
        ]
        for (name, size, height) in sizes {
            XCTAssertEqual(size.width, 560, name)
            XCTAssertEqual(size.height, height, "\(name) opens at \(size.height) pt, not dev's \(height)")
        }
        for model in [twentyModel, fewModel] {
            let sheet: StartOfYearSheet = StartOfYearSheet(model: model)
            let host: TableHost = TableHost(sheet, size: PageTablesSheetTests.fittingSize(of: sheet))
            defer {
                host.close()
            }
            let table: NSTableView = try XCTUnwrap(host.tables().first)
            let scrollBar: Bool = table.enclosingScrollView?.verticalScroller?.isHidden == false
                && table.enclosingScrollView?.scrollerStyle == .legacy
            let expected: [CGFloat] = scrollBar
                ? PageTablesSheetTests.soyColumnsWithAScrollBar : PageTablesSheetTests.soyColumnsWithoutAScrollBar
            XCTAssertEqual(PageTablesSheetTests.widths(of: table), expected, "Start of Year's columns at 560 moved")
        }

        let plans = try AssistFixture.makeRunner(surface: .menu)
        made.append(plans.root)
        let twentyOne: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: plans)
        let planModel: SectionVerbSheetModel = PageTablesSheetTests.plannedModel(
            twentyOne, kind: .publishPages, course: plans.course
        )
        let hiding = try AssistFixture.makeRunner(surface: .menu)
        made.append(hiding.root)
        let hideOutcome: AssistToolOutcome = try await PageTablesSheetTests.planHidingAClassWhosePageStays(in: hiding)
        XCTAssertEqual(hideOutcome.planTable?.rows.count, 2)
        let hideModel: SectionVerbSheetModel = PageTablesSheetTests.plannedModel(
            hideOutcome, kind: .hidePages, course: hiding.course
        )
        let finished: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .result, course: plans.course, sectionNumber: 1, title: AssistWording.menuUndoLastChangeTitle,
            item: .undoLastChange, stage: .finished
        )
        finished.body = "Nothing to undo."
        let working: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .result, course: plans.course, sectionNumber: 1, title: AssistWording.menuUndoLastChangeTitle,
            item: .undoLastChange, stage: .working
        )
        let reDate: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .reDateClasses, course: plans.course, sectionNumber: 1,
            title: AssistWording.menuReDateTitle(course: "ICS3U", section: "1"),
            item: .reDateClasses, stage: .planned
        )
        reDate.body = twentyOne.forTheCard
        let verbSizes: [(String, SectionVerbSheetModel, CGFloat)] = [
            ("the plan of twenty-one pages", planModel, PageTablesSheetTests.planOfTwentyOnePagesHeight),
            ("a hide plan of two rows", hideModel, PageTablesSheetTests.hidePlanOfTwoRowsHeight),
            ("a finished sentence", finished, PageTablesSheetTests.finishedTextHeight),
            ("working", working, PageTablesSheetTests.workingHeight),
            ("a Re-date card", reDate, PageTablesSheetTests.reDateCardHeight),
        ]
        for (name, model, height) in verbSizes {
            let size: NSSize = PageTablesSheetTests.fittingSize(
                of: SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
            )
            XCTAssertEqual(size.width, 560, name)
            XCTAssertEqual(size.height, height, "\(name) opens at \(size.height) pt, not dev's \(height)")
        }
    }

    // MARK: - Helpers

    /// The size a sheet opens at: its content laid out at the sheet's width,
    /// as `StartOfYearPlanTableTests.measuredHeight` measures it.
    static func fittingSize(of view: some View) -> NSSize {
        let hostingView: NSHostingView = NSHostingView(rootView: AnyView(view))
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 2000)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize
    }

    static func widths(of table: NSTableView) -> [CGFloat] {
        var widths: [CGFloat] = []
        for column in table.tableColumns {
            widths.append(column.width)
        }
        return widths
    }

    static func titles(of table: NSTableView) -> [String] {
        var titles: [String] = []
        for column in table.tableColumns {
            titles.append(column.title)
        }
        return titles
    }

    /// The first text field a teacher can type in.
    static func editableTextField(in window: NSWindow) -> NSTextField? {
        guard let content = window.contentView else {
            return nil
        }
        return firstEditableTextField(in: content)
    }

    static func firstEditableTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        for subview in view.subviews {
            if let found = firstEditableTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    /// Publish Pages… at its first stage: `classes` classes, dated from
    /// 9 September, then `pages` concept pages — the order `rows` gives.
    static func pickerModel(course: Course, classes: Int, pages: Int) -> SectionVerbSheetModel {
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .publishPages, course: course, sectionNumber: 1,
            title: AssistWording.menuPublishPagesTitle(course: "ICS3U", section: "1"),
            item: .publishPages
        )
        var rows: [SectionVerbSheetModel.PageRow] = []
        var number: Int = 1
        while number <= classes {
            rows.append(SectionVerbSheetModel.PageRow(
                name: "section1/All Classes/Unit 1, Day \(number)", title: "Unit 1, Day \(number)",
                folder: "section1/All Classes",
                fileURL: course.directoryURL.appendingPathComponent("section1/All Classes/Unit 1, Day \(number).md"),
                isClass: true, date: CalendarDay(year: 2026, month: 9, day: 8 + number)
            ))
            number += 1
        }
        number = 1
        while number <= pages {
            rows.append(SectionVerbSheetModel.PageRow(
                name: "Concepts/Page \(number)", title: "Page \(number)", folder: "Concepts",
                fileURL: course.directoryURL.appendingPathComponent("Concepts/Page \(number).md"),
                isClass: false, date: nil
            ))
            number += 1
        }
        model.pageRows = rows
        return model
    }

    static func plannedModel(_ outcome: AssistToolOutcome, kind: SectionVerbSheetModel.Kind,
                             course: Course) -> SectionVerbSheetModel {
        let publishing: Bool = kind != .hidePages
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: kind, course: course, sectionNumber: 1,
            title: publishing
                ? AssistWording.menuPublishPagesTitle(course: "ICS3U", section: "1")
                : AssistWording.menuHidePagesTitle(course: "ICS3U", section: "1"),
            item: publishing ? .publishPages : .hidePages, stage: .planned
        )
        model.body = outcome.forTheCard
        model.planTable = outcome.planTable
        return model
    }

    /// Hiding a class whose linked page another visible class still links
    /// to: one page hides and one stays, with nothing already hidden.
    static func planHidingAClassWhosePageStays(in made: AssistFixture.Made) async throws -> AssistToolOutcome {
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "Uses [[Ohm]].", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-09", body: "Also [[Ohm]].", in: made.course)
        try "---\ntitle: Ohm\npublish: true\n---\nV = IR.\n".write(
            to: made.course.directoryURL.appendingPathComponent("Concepts/Ohm.md"), atomically: true, encoding: .utf8
        )
        return await made.runner.run(call: SectionVerbs.hidePages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: true
        ))
    }
}
