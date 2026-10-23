import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The Section menu's page sheets and Start of Year (v1.8.6: #608, #621,
/// #622): the picker and the later-classes list as tables, the plan listing
/// only the pages that change with the rest behind a checkbox (a disclosure
/// until #654), and every one of these sheets resizable from the size it
/// opened at before — and, since #654, the answer after a plan fitted to its
/// sentence rather than left at the plan's height.
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

    // MARK: - The fold (#622)

    /// The rows a teacher reads are every row but the pages already the way
    /// they were asked to be: a change, a page an unpublish keeps, a linked
    /// class left as it is and a page with no room for a key all stay in
    /// view. And the rows folded away are exactly what the summary counts as
    /// "already".
    func testOnlyThePagesAlreadyRightFoldAway() async throws {
        var rows: [AssistPlanTable.Row] = []
        let changes: [AssistPlanTable.Change] = [
            .willBecomeVisible, .alreadyVisible, .willBecomeHidden, .staysVisible,
            .alreadyHidden, .staysAsItIs, .staysExactlyAsItIs,
        ]
        for change in changes {
            rows.append(AssistPlanTable.Row(
                position: rows.count, title: "Page \(rows.count)", folder: "Concepts", change: change, whatChanges: ""
            ))
        }
        let made: AssistPlanTable = AssistPlanTable(summary: "", rows: rows, notes: [])
        var toRead: [AssistPlanTable.Change] = []
        for row in made.rowsToRead {
            toRead.append(row.change)
        }
        XCTAssertEqual(toRead, [.willBecomeVisible, .willBecomeHidden, .staysVisible, .staysAsItIs, .staysExactlyAsItIs])
        var folded: [AssistPlanTable.Change] = []
        for row in made.rowsAlreadyRight {
            folded.append(row.change)
        }
        XCTAssertEqual(folded, [.alreadyVisible, .alreadyHidden])

        let plans = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: plans.root)
        }
        let outcome: AssistToolOutcome = try await PageTablesSheetTests.planAClassLinking(hidden: 4, visible: 16, in: plans)
        let table: AssistPlanTable = try XCTUnwrap(outcome.planTable, outcome.forTheCard)
        XCTAssertEqual(table.rowsToRead.count, 5)
        XCTAssertEqual(table.rowsAlreadyRight.count, 16)
        XCTAssertEqual(table.summary, AssistWording.menuPlanSummary(
            changing: 5, already: table.rowsAlreadyRight.count, publishing: true
        ))
    }

    /// The plan sheet opens with the pages already visible folded away
    /// under a CHECKBOX that wears `menuPlanShowAlready` (#654: a disclosure
    /// promised a fold below it, and the rows go into the table above); a
    /// click on it adds every one of them to the same table, which stays the
    /// height it was, and a second click takes them out again. A Hide plan
    /// does the same with `menuPlanShowAlready(publishing: false)`, and a
    /// plan with nothing already right has no checkbox.
    func testThePlanFoldsThePagesAlreadyRightUntilTheCheckboxIsTicked() async throws {
        var made: [URL] = []
        defer {
            for root in made {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let publishing = try AssistFixture.makeRunner(surface: .menu)
        made.append(publishing.root)
        let publish: AssistToolOutcome = try await PageTablesSheetTests.planAClassLinking(hidden: 4, visible: 16, in: publishing)
        let hiding = try AssistFixture.makeRunner(surface: .menu)
        made.append(hiding.root)
        let hide: AssistToolOutcome = try await PageTablesSheetTests.planHidingAClassLinkingHiddenPages(in: hiding)
        let cases: [(String, AssistToolOutcome, SectionVerbSheetModel.Kind, Course, Int, Int, String)] = [
            ("Publish", publish, .publishPages, publishing.course, 5, 21,
             AssistWording.menuPlanShowAlready(count: 16, publishing: true)),
            ("Hide", hide, .hidePages, hiding.course, 2, 4,
             AssistWording.menuPlanShowAlready(count: 2, publishing: false)),
        ]
        for (name, outcome, kind, course, closedRows, openRows, label) in cases {
            let model: SectionVerbSheetModel = PageTablesSheetTests.plannedModel(outcome, kind: kind, course: course)
            let sheet: SectionVerbSheet = SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
            XCTAssertEqual(sheet.alreadyRightLabel, label, name)
            let host: TableHost = TableHost(sheet, size: PageTablesSheetTests.fittingSize(of: sheet))
            defer {
                host.close()
            }
            let table: NSTableView = try XCTUnwrap(host.tables().first, name)
            XCTAssertFalse(model.showsAlreadyRight, "\(name): the checkbox is ticked to begin with")
            XCTAssertEqual(table.numberOfRows, closedRows, "\(name): the folded rows are drawn")
            let tableHeight: CGFloat? = table.enclosingScrollView?.frame.height
            let checkbox: NSButton = try XCTUnwrap(
                PageTablesSheetTests.checkbox(in: host.window),
                "\(name): no checkbox under the table (still a disclosure?)"
            )
            XCTAssertEqual(checkbox.state, .off, "\(name): the checkbox is drawn ticked")
            PageTablesSheetTests.click(checkbox, in: host)
            XCTAssertTrue(model.showsAlreadyRight, "\(name): a click did not tick the checkbox")
            XCTAssertEqual(checkbox.state, .on, "\(name): the checkbox is not drawn ticked")
            XCTAssertEqual(table.numberOfRows, openRows, "\(name): ticking it did not add the folded rows")
            XCTAssertEqual(table.enclosingScrollView?.frame.height, tableHeight, "\(name): the table grew when it was ticked")
            var last: [AssistPlanTable.Change] = []
            for row in sheet.drawnPlanRows.suffix(openRows - closedRows) {
                last.append(row.change)
            }
            XCTAssertEqual(last.count, openRows - closedRows)
            for change in last {
                XCTAssertTrue(AssistPlanTable.isAlreadyRight(change), "\(name): a folded row is not already right")
            }
            PageTablesSheetTests.click(checkbox, in: host)
            XCTAssertFalse(model.showsAlreadyRight, "\(name): a second click did not untick the checkbox")
            XCTAssertEqual(table.numberOfRows, closedRows, "\(name): unticking it did not take the rows out")
        }

        let nothingFolded = try AssistFixture.makeRunner(surface: .menu)
        made.append(nothingFolded.root)
        let twentyOne: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: nothingFolded)
        let plain: SectionVerbSheetModel = PageTablesSheetTests.plannedModel(twentyOne, kind: .publishPages, course: nothingFolded.course)
        let plainSheet: SectionVerbSheet = SectionVerbSheet(model: plain, pressDefault: {}, cancel: {})
        XCTAssertNil(plainSheet.alreadyRightLabel, "a checkbox with nothing to add")
        XCTAssertEqual(plainSheet.drawnPlanRows.count, 21)
    }

    // MARK: - Resizing (#621)

    /// Every one of these sheets, presented for real, is resizable, opens at
    /// its content's size (`fittingSize(of:)`, 560 wide), and cannot be made
    /// smaller than that: the size a teacher saw before is both the default
    /// and the minimum.
    func testEachSheetIsResizableAndOpensAtItsSmallestSize() async throws {
        var made: [URL] = []
        defer {
            for root in made {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let plans = try AssistFixture.makeRunner(surface: .menu)
        made.append(plans.root)
        let twentyOne: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: plans)
        let folding = try AssistFixture.makeRunner(surface: .menu)
        made.append(folding.root)
        let folded: AssistToolOutcome = try await PageTablesSheetTests.planAClassLinking(hidden: 4, visible: 16, in: folding)
        let models: [(String, SectionVerbSheetModel)] = [
            ("the picker", PageTablesSheetTests.pickerModel(course: plans.course, classes: 3, pages: 2)),
            ("the later classes", try PageTablesSheetTests.laterClassesModel(course: plans.course)),
            ("the plan of twenty-one pages", PageTablesSheetTests.plannedModel(twentyOne, kind: .publishPages, course: plans.course)),
            ("a plan with pages folded", PageTablesSheetTests.plannedModel(folded, kind: .publishPages, course: folding.course)),
        ]
        for (name, model) in models {
            let expected: NSSize = PageTablesSheetTests.fittingSize(
                of: SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
            )
            let host: SheetHost = SheetHost(SectionVerbSheet(model: model, pressDefault: {}, cancel: {}))
            defer {
                host.close()
            }
            let sheet: NSWindow = try XCTUnwrap(host.sheet, "\(name): no sheet was presented")
            XCTAssertTrue(sheet.styleMask.contains(.resizable), "\(name): the sheet cannot be resized")
            XCTAssertEqual(sheet.frame.width, 560, accuracy: 0.5, name)
            XCTAssertEqual(sheet.frame.height, expected.height, accuracy: 0.5, "\(name): it opened at another height")
            XCTAssertEqual(sheet.minSize.width, 560, accuracy: 0.5, "\(name): it can be made narrower than it opens")
            XCTAssertEqual(sheet.minSize.height, expected.height, accuracy: 0.5, "\(name): its smallest is not the size it opens at")
            XCTAssertFalse(host.reachedAScreen, "\(name): the sheet reached a display")
            print("PageTablesSheetTests: \(name) opens at \(sheet.frame.size), smallest \(sheet.minSize)")
        }
    }

    /// The plan review's B1: a sheet that opens on a two-row picker and moves
    /// to a plan of twenty-one rows grows to show it — the window is at
    /// least its minimum, and the plan's whole content fits — and moving on
    /// to a shorter stage does not shrink it again.
    func testASheetThatMovesToATallerStageGrowsToShowIt() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let twentyOne: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: made)
        let model: SectionVerbSheetModel = PageTablesSheetTests.pickerModel(course: made.course, classes: 0, pages: 2)
        let host: SheetHost = SheetHost(SectionVerbSheet(model: model, pressDefault: {}, cancel: {}))
        defer {
            host.close()
        }
        let sheet: NSWindow = try XCTUnwrap(host.sheet, "no sheet was presented")
        let opened: CGFloat = sheet.frame.height
        model.body = twentyOne.forTheCard
        model.planTable = twentyOne.planTable
        model.stage = .planned
        await host.settle()
        let needed: CGFloat = PageTablesSheetTests.fittingSize(
            of: SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
        ).height
        XCTAssertGreaterThan(needed, opened + 100, "the plan should need far more room than the picker")
        XCTAssertGreaterThanOrEqual(sheet.frame.height, sheet.minSize.height - 0.5,
                                    "the sheet stayed \(sheet.frame.height) pt under a minimum of \(sheet.minSize.height)")
        XCTAssertGreaterThanOrEqual(sheet.contentLayoutRect.height, needed - 0.5,
                                    "the plan needs \(needed) pt and the sheet has \(sheet.contentLayoutRect.height): the buttons are off its bottom")
        let grown: CGFloat = sheet.frame.height
        model.stage = .working
        await host.settle()
        XCTAssertEqual(sheet.frame.height, grown, accuracy: 0.5, "the sheet shrank on the way to a shorter stage")
        XCTAssertFalse(host.reachedAScreen, "the sheet reached a display")
    }

    /// #654: the answer after a plan — "Published 5 pages." and the like —
    /// is shown in a sheet fitted to it, not left at the plan's height. A
    /// Publish plan of twenty-one rows and a Hide plan, each presented for
    /// real, run for real, then shown finished: the sheet is the height the
    /// answer needs (`fittingSize(of:)` of the finished sheet), far below the
    /// plan's, still centred on its window, and the width a teacher dragged
    /// it to kept. Before #654 it stayed at the plan's height.
    func testTheAnswerAfterAPlanIsFittedToItsSentence() async throws {
        var made: [URL] = []
        defer {
            for root in made {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let publishing = try AssistFixture.makeRunner(surface: .menu)
        made.append(publishing.root)
        let publish: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: publishing)
        let hiding = try AssistFixture.makeRunner(surface: .menu)
        made.append(hiding.root)
        let hide: AssistToolOutcome = try await PageTablesSheetTests.planHidingAClassLinkingHiddenPages(in: hiding)
        let names: [String] = ["section1/All Classes/Unit 1, Day 1"]
        let cases: [(String, AssistToolOutcome, SectionVerbSheetModel.Kind, AssistFixture.Made, AssistToolCall, CGFloat)] = [
            ("Publish", publish, .publishPages, publishing,
             SectionVerbs.publishPages(course: "ICS3U", section: 1, names: names, planning: false), 560),
            ("Hide", hide, .hidePages, hiding,
             SectionVerbs.hidePages(course: "ICS3U", section: 1, names: names, planning: false), 700),
        ]
        for (name, outcome, kind, fixture, call, width) in cases {
            let model: SectionVerbSheetModel = PageTablesSheetTests.plannedModel(outcome, kind: kind, course: fixture.course)
            let host: SheetHost = SheetHost(SectionVerbSheet(model: model, pressDefault: {}, cancel: {}))
            defer {
                host.close()
            }
            let sheet: NSWindow = try XCTUnwrap(host.sheet, "\(name): no sheet was presented")
            if width != sheet.contentLayoutRect.width {
                host.resizeSheet(to: NSSize(width: width, height: sheet.contentLayoutRect.height))
            }
            let planHeight: CGFloat = sheet.frame.height
            let planMiddle: CGFloat = sheet.frame.midY

            model.stage = .working
            await host.settle()
            let done: AssistToolOutcome = await fixture.runner.run(call: call)
            model.body = done.summary
            model.stage = .finished
            await host.settle()

            let needed: CGFloat = PageTablesSheetTests.fittingSize(
                of: SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
            ).height
            XCTAssertEqual(sheet.contentLayoutRect.height, needed, accuracy: 0.5,
                           "\(name): the answer needs \(needed) pt and the sheet kept \(sheet.contentLayoutRect.height)")
            XCTAssertLessThan(sheet.frame.height, planHeight - 80,
                              "\(name): the answer's sheet is \(sheet.frame.height) pt against the plan's \(planHeight)")
            XCTAssertLessThan(sheet.frame.height, CopyPageChecklist.tallestSheet / 2,
                              "\(name): the answer's sheet is \(sheet.frame.height) pt")
            // MEASURED on macOS 26.6: AppKit keeps a sheet centred on the
            // window it hangs from, through a change of size, so the answer
            // sits where the plan's middle was.
            XCTAssertEqual(sheet.frame.midY, planMiddle, accuracy: 0.5, "\(name): the sheet moved off the middle of its window")
            XCTAssertEqual(sheet.contentLayoutRect.width, width, accuracy: 0.5, "\(name): the width the teacher made was lost")
            XCTAssertGreaterThanOrEqual(sheet.frame.height, sheet.minSize.height - 0.5, "\(name): under its minimum")
            XCTAssertFalse(host.reachedAScreen, "\(name): the sheet reached a display")
            print("PageTablesSheetTests: \(name) plan \(planHeight) pt, answer \(sheet.frame.height) pt (needs \(needed))")
        }
    }

    /// Russell's rulings on R8: ticking the checkbox moves neither the
    /// sheet nor its minimum; the folded rows go into the table, which
    /// scrolls inside the sheet; the last row can be scrolled to; and the
    /// table is inside the sheet, not hanging off its edge.
    func testOpeningTheFoldMovesNeitherTheSheetNorItsSmallestSize() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let folded: AssistToolOutcome = try await PageTablesSheetTests.planAClassLinking(hidden: 4, visible: 16, in: made)
        let model: SectionVerbSheetModel = PageTablesSheetTests.plannedModel(folded, kind: .publishPages, course: made.course)
        let host: SheetHost = SheetHost(SectionVerbSheet(model: model, pressDefault: {}, cancel: {}))
        defer {
            host.close()
        }
        let sheet: NSWindow = try XCTUnwrap(host.sheet, "no sheet was presented")
        let table: NSTableView = try XCTUnwrap(host.tables().first, "no table on the plan")
        XCTAssertEqual(table.numberOfRows, 5)
        let frame: NSRect = sheet.frame
        let smallest: NSSize = sheet.minSize
        let tableHeight: CGFloat? = table.enclosingScrollView?.frame.height

        model.showsAlreadyRight = true
        await host.settle()
        XCTAssertEqual(table.numberOfRows, 21, "opening it did not add the folded rows")
        XCTAssertEqual(sheet.frame.size, frame.size, "the sheet changed size when the checkbox was ticked")
        XCTAssertEqual(sheet.minSize, smallest, "the sheet's smallest size rose when the checkbox was ticked")
        XCTAssertGreaterThanOrEqual(sheet.frame.height, sheet.minSize.height - 0.5)
        XCTAssertEqual(table.enclosingScrollView?.frame.height, tableHeight, "the table grew when the checkbox was ticked")

        let scroll: NSScrollView = try XCTUnwrap(table.enclosingScrollView)
        let document: CGFloat = scroll.documentView?.frame.height ?? 0
        XCTAssertGreaterThan(document, scroll.contentView.bounds.height, "twenty-one rows should scroll inside the table")
        // A teacher's scroll wheel, not `scrollRowToVisible`, which scrolls in
        // code and so reaches the last row even in a table that cannot be
        // scrolled (the implementation review's B-F1, measured).
        XCTAssertTrue(scroll.hasVerticalScroller, "the table has no scroll bar")
        let top: CGFloat = scroll.contentView.bounds.origin.y
        let wheel: CGEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -2000, wheel2: 0, wheel3: 0
        ), "no scroll-wheel event")
        let event: NSEvent = try XCTUnwrap(NSEvent(cgEvent: wheel), "no scroll-wheel event")
        scroll.scrollWheel(with: event)
        host.pump()
        let moved: CGFloat = scroll.contentView.bounds.origin.y - top
        XCTAssertGreaterThan(moved, 0, "the scroll wheel did not move the table")
        XCTAssertTrue(table.visibleRect.intersects(table.rect(ofRow: 20)),
                      "the scroll wheel moved the table \(moved) pt and the last row is not shown")
        let content: NSView = try XCTUnwrap(sheet.contentView)
        let inWindow: NSRect = scroll.convert(scroll.bounds, to: nil)
        XCTAssertTrue(content.bounds.insetBy(dx: -0.5, dy: -0.5).contains(inWindow),
                      "the table \(inWindow) hangs outside the sheet \(content.bounds)")
        XCTAssertFalse(host.reachedAScreen, "the sheet reached a display")
    }

    /// The width a teacher adds goes to the Page column: dragged from 560 to
    /// 900 wide, Page gains more than Folder and What changes together.
    func testThePageColumnTakesTheWidthAdded() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let twentyOne: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: made)
        let model: SectionVerbSheetModel = PageTablesSheetTests.plannedModel(twentyOne, kind: .publishPages, course: made.course)
        let host: SheetHost = SheetHost(SectionVerbSheet(model: model, pressDefault: {}, cancel: {}))
        defer {
            host.close()
        }
        let sheet: NSWindow = try XCTUnwrap(host.sheet, "no sheet was presented")
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        let before: [CGFloat] = PageTablesSheetTests.widths(of: table)
        host.resizeSheet(to: NSSize(width: 900, height: sheet.contentLayoutRect.height))
        let after: [CGFloat] = PageTablesSheetTests.widths(of: table)
        XCTAssertEqual(after.count, 3)
        XCTAssertEqual(before.count, 3)
        if after.count == 3 && before.count == 3 {
            let page: CGFloat = after[0] - before[0]
            let others: CGFloat = (after[1] - before[1]) + (after[2] - before[2])
            XCTAssertGreaterThan(page, others, "Page gained \(page) pt and the other two \(others): \(before) to \(after)")
            print("PageTablesSheetTests: plan columns \(before) at 560, \(after) at 900")
        }
        XCTAssertFalse(host.reachedAScreen, "the sheet reached a display")
    }

    /// The height a teacher adds goes to the table: 300 pt more sheet is
    /// 300 pt more table, on the plan and on the picker.
    func testTheTableTakesTheHeightAdded() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let twentyOne: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: made)
        let models: [(String, SectionVerbSheetModel)] = [
            ("the plan", PageTablesSheetTests.plannedModel(twentyOne, kind: .publishPages, course: made.course)),
            ("the picker", PageTablesSheetTests.pickerModel(course: made.course, classes: 3, pages: 30)),
        ]
        for (name, model) in models {
            let host: SheetHost = SheetHost(SectionVerbSheet(model: model, pressDefault: {}, cancel: {}))
            defer {
                host.close()
            }
            let sheet: NSWindow = try XCTUnwrap(host.sheet, "\(name): no sheet was presented")
            let table: NSTableView = try XCTUnwrap(host.tables().first, name)
            let before: CGFloat = table.enclosingScrollView?.frame.height ?? 0
            let opened: NSSize = sheet.contentLayoutRect.size
            host.resizeSheet(to: NSSize(width: opened.width, height: opened.height + 300))
            let after: CGFloat = table.enclosingScrollView?.frame.height ?? 0
            XCTAssertEqual(after - before, 300, accuracy: 1, "\(name): the table grew \(after - before) pt of the 300 added")
            XCTAssertFalse(host.reachedAScreen, "\(name): the sheet reached a display")
        }
    }

    /// A Re-date card's text takes the height a teacher adds, as Start of
    /// Year's other stages do, instead of leaving a band above the buttons
    /// (the implementation review's A-F1), and it still opens at dev's size.
    func testAReDateCardsTextTakesTheHeightAdded() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let twentyOne: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: made)
        let reDate: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .reDateClasses, course: made.course, sectionNumber: 1,
            title: AssistWording.menuReDateTitle(course: "ICS3U", section: "1"),
            item: .reDateClasses, stage: .planned
        )
        reDate.body = twentyOne.forTheCard
        let host: SheetHost = SheetHost(SectionVerbSheet(model: reDate, pressDefault: {}, cancel: {}))
        defer {
            host.close()
        }
        let sheet: NSWindow = try XCTUnwrap(host.sheet, "no sheet was presented")
        XCTAssertEqual(sheet.frame.height, PageTablesSheetTests.reDateCardHeight, accuracy: 0.5,
                       "the card opened at another height")
        let scroll: NSScrollView = try XCTUnwrap(PageTablesSheetTests.firstScrollView(in: sheet.contentView),
                                                 "the card has no text area")
        let before: CGFloat = scroll.frame.height
        let opened: NSSize = sheet.contentLayoutRect.size
        host.resizeSheet(to: NSSize(width: opened.width, height: opened.height + 300))
        let after: CGFloat = scroll.frame.height
        XCTAssertEqual(after - before, 300, accuracy: 1, "the text area grew \(after - before) pt of the 300 added")
        print("PageTablesSheetTests: Re-date card's text \(before) pt at \(opened.height), \(after) pt at \(opened.height + 300)")
        XCTAssertFalse(host.reachedAScreen, "the sheet reached a display")
    }

    /// The tallest plan stage — twelve rows to read, pages folded under them
    /// and the notes at their cap — still fits a 13-inch screen
    /// (`CopyPageChecklist.tallestSheet`) with the checkbox, and every part
    /// is really there.
    func testTheTallestPlanStaysOnTheScreen() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        var rows: [AssistPlanTable.Row] = []
        while rows.count < 20 {
            let change: AssistPlanTable.Change = rows.count < 14 ? .willBecomeVisible : .alreadyVisible
            rows.append(AssistPlanTable.Row(
                position: rows.count, title: "Page \(rows.count)", folder: "Concepts", change: change, whatChanges: ""
            ))
        }
        var notes: [String] = []
        while notes.count < 8 {
            notes.append("Note \(notes.count + 1): a sentence long enough to take two lines in the sheet, so that the notes go past their cap and are measured at it.")
        }
        let table: AssistPlanTable = AssistPlanTable(
            summary: AssistWording.menuPlanSummary(changing: 14, already: 6, publishing: true), rows: rows, notes: notes
        )
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .publishPages, course: made.course, sectionNumber: 1,
            title: AssistWording.menuPublishPagesTitle(course: "ICS3U", section: "1"),
            item: .publishPages, stage: .planned
        )
        model.planTable = table
        let sheet: SectionVerbSheet = SectionVerbSheet(model: model, pressDefault: {}, cancel: {})
        XCTAssertNotNil(sheet.alreadyRightLabel, "the case has no checkbox")
        let height: CGFloat = PageTablesSheetTests.fittingSize(of: sheet).height
        XCTAssertLessThanOrEqual(height, CopyPageChecklist.tallestSheet, "the tallest plan is \(height) pt")
        let parts: CGFloat = ListTableMetrics.height(forRowCount: SectionVerbSheet.mostPlanRowsShown, showsHeader: true)
            + SectionVerbSheet.tallestPlanNotes + 20
        XCTAssertGreaterThanOrEqual(height, parts + 120, "only \(height) pt: the table, the checkbox or the notes collapsed")
        print("PageTablesSheetTests: tallest plan \(height) pt against \(CopyPageChecklist.tallestSheet)")
    }

    // MARK: - Start of Year (#621)

    /// Start of Year, presented for real: resizable, opening at its
    /// content's size, which is its smallest; 300 pt more sheet is 300 more
    /// table; and the width added goes to Page.
    func testStartOfYearIsResizableAndItsTableTakesTheRoom() throws {
        var made: [URL] = []
        defer {
            for root in made {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let twenty = try AssistFixture.makeRunner()
        made.append(twenty.root)
        try StartOfYearPlanTableTests.layOutClasses(20, in: twenty.course)
        let few = try AssistFixture.makeRunner()
        made.append(few.root)
        try StartOfYearPlanTableTests.layOutAFewPages(in: few.course)
        let models: [(String, StartOfYearSheetModel)] = [
            ("twenty classes", StartOfYearPlanTableTests.model(twenty)),
            ("three rows", StartOfYearPlanTableTests.model(few)),
        ]
        for (name, model) in models {
            model.load()
            let expected: NSSize = PageTablesSheetTests.fittingSize(of: StartOfYearSheet(model: model))
            let host: SheetHost = SheetHost(StartOfYearSheet(model: model))
            defer {
                host.close()
            }
            let sheet: NSWindow = try XCTUnwrap(host.sheet, "\(name): no sheet was presented")
            XCTAssertTrue(sheet.styleMask.contains(.resizable), "\(name): the sheet cannot be resized")
            XCTAssertEqual(sheet.frame.width, 560, accuracy: 0.5, name)
            XCTAssertEqual(sheet.frame.height, expected.height, accuracy: 0.5, "\(name): it opened at another height")
            XCTAssertEqual(sheet.minSize.width, 560, accuracy: 0.5, name)
            XCTAssertEqual(sheet.minSize.height, expected.height, accuracy: 0.5, "\(name): its smallest is not the size it opens at")

            let table: NSTableView = try XCTUnwrap(host.tables().first, name)
            let tableBefore: CGFloat = table.enclosingScrollView?.frame.height ?? 0
            let widthsBefore: [CGFloat] = PageTablesSheetTests.widths(of: table)
            let opened: NSSize = sheet.contentLayoutRect.size
            host.resizeSheet(to: NSSize(width: opened.width, height: opened.height + 300))
            let tableAfter: CGFloat = table.enclosingScrollView?.frame.height ?? 0
            XCTAssertEqual(tableAfter - tableBefore, 300, accuracy: 1, "\(name): the table grew \(tableAfter - tableBefore) pt of the 300 added")
            host.resizeSheet(to: NSSize(width: 900, height: opened.height + 300))
            let widthsAfter: [CGFloat] = PageTablesSheetTests.widths(of: table)
            XCTAssertEqual(widthsAfter.count, 3, name)
            if widthsAfter.count == 3 && widthsBefore.count == 3 {
                let page: CGFloat = widthsAfter[0] - widthsBefore[0]
                let others: CGFloat = (widthsAfter[1] - widthsBefore[1]) + (widthsAfter[2] - widthsBefore[2])
                XCTAssertGreaterThan(page, others, "\(name): Page gained \(page) pt and the other two \(others): \(widthsBefore) to \(widthsAfter)")
            }
            print("PageTablesSheetTests: Start of Year, \(name): opens \(sheet.minSize), columns \(widthsBefore) at 560, \(widthsAfter) at 900")
            XCTAssertFalse(host.reachedAScreen, "\(name): the sheet reached a display")
        }
    }

    /// Start of Year's other stages (reading, the result, the undo's lists, a
    /// problem) open exactly as tall as the scroll area they had — their
    /// content's height from 200 to 460 pt — and, unlike it, grow with a
    /// sheet made taller.
    func testStartOfYearsOtherStagesOpenAsTheyDidAndGrowWithTheSheet() throws {
        for lines in [1, 12, 60] {
            var sentences: [String] = []
            while sentences.count < lines {
                sentences.append("• Page \(sentences.count + 1)")
            }
            let before: some View = ScrollView {
                PageTablesSheetTests.lines(sentences)
            }
            .frame(minHeight: 200, maxHeight: 460)
            let now: some View = CappedScrollArea(cap: StartOfYearSheet.tallestOtherStage, growsWithItsSheet: true) {
                PageTablesSheetTests.lines(sentences)
            }
            .frame(minHeight: StartOfYearSheet.shortestOtherStage)
            let opened: CGFloat = PageTablesSheetTests.fittingSize(of: now).height
            XCTAssertEqual(opened, PageTablesSheetTests.fittingSize(of: before).height, "\(lines) lines open at another height")
            let host: TableHost = TableHost(now, size: NSSize(width: 560, height: opened + 300))
            defer {
                host.close()
            }
            let scroll: NSScrollView? = PageTablesSheetTests.firstScrollView(in: host.window.contentView)
            XCTAssertEqual(scroll?.frame.height ?? 0, opened + 300, accuracy: 1, "\(lines) lines: the area did not take the height added")
            print("PageTablesSheetTests: Start of Year's other stage, \(lines) lines, opens at \(opened)")
        }
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

    /// Lines of text as Start of Year's other stages lay them out.
    static func lines(_ sentences: [String]) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(sentences, id: \.self) { (sentence: String) in
                Text(sentence)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The first scroll view under `view`, depth first.
    static func firstScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else {
            return nil
        }
        if let scroll = view as? NSScrollView {
            return scroll
        }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) {
                return found
            }
        }
        return nil
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

    /// The #475 question at Deploy about two classes, both ticked.
    static func laterClassesModel(course: Course) throws -> SectionVerbSheetModel {
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .laterClassesAtDeploy, course: course, sectionNumber: 1, title: "", item: nil
        )
        let first: CalendarDay = try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 11))
        let second: CalendarDay = try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 14))
        model.ask(about: [
            ClassesDatedLater.Flagged(place: "section1/All Classes/Unit 2, Day 5", title: "Unit 2, Day 5", date: first),
            ClassesDatedLater.Flagged(place: "section1/All Classes/Unit 2, Day 6", title: "Unit 2, Day 6", date: second),
        ], nextDay: CalendarDay(year: 2026, month: 9, day: 9))
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

    /// A hidden class, Unit 1, Day 1, linking `hidden` hidden concept pages
    /// and `visible` visible ones: the class and the hidden pages change,
    /// and the visible ones are already visible — #622's "5 pages would
    /// change, 16 already visible" with 4 and 16.
    static func planAClassLinking(hidden: Int, visible: Int, in made: AssistFixture.Made) async throws -> AssistToolOutcome {
        var links: String = ""
        var number: Int = 1
        while number <= hidden {
            links += "[[Hidden \(number)]] "
            try "---\ntitle: Hidden \(number)\npublish: false\n---\nIdea.\n".write(
                to: made.course.directoryURL.appendingPathComponent("Concepts/Hidden \(number).md"),
                atomically: true, encoding: .utf8
            )
            number += 1
        }
        number = 1
        while number <= visible {
            links += "[[Seen \(number)]] "
            try "---\ntitle: Seen \(number)\npublish: true\n---\nIdea.\n".write(
                to: made.course.directoryURL.appendingPathComponent("Concepts/Seen \(number).md"),
                atomically: true, encoding: .utf8
            )
            number += 1
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: links, in: made.course)
        return await made.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: true
        ))
    }

    /// Hiding a visible class that links one visible page and two hidden
    /// ones: two pages hide, and two are already hidden.
    static func planHidingAClassLinkingHiddenPages(in made: AssistFixture.Made) async throws -> AssistToolOutcome {
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "Uses [[Ohm]], [[Gone 1]] and [[Gone 2]].",
                                in: made.course)
        let concepts: URL = made.course.directoryURL.appendingPathComponent("Concepts")
        try "---\ntitle: Ohm\npublish: true\n---\nV = IR.\n".write(
            to: concepts.appendingPathComponent("Ohm.md"), atomically: true, encoding: .utf8
        )
        for name in ["Gone 1", "Gone 2"] {
            try "---\ntitle: \(name)\npublish: false\n---\nGone.\n".write(
                to: concepts.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8
            )
        }
        return await made.runner.run(call: SectionVerbs.hidePages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: true
        ))
    }

    /// The checkbox anywhere in `window` (#654). MEASURED on macOS 26.6:
    /// SwiftUI draws a checkbox-style `Toggle` as a 16-point AppKit button
    /// with no title of its own (the label beside it is SwiftUI's), no
    /// accessibility role, a mixed state allowed, and the bezel a switch
    /// button carries — `.flexiblePush`, raw value 2, the old
    /// `.regularSquare`; a disclosure's triangle is not one.
    static func checkbox(in window: NSWindow) -> NSButton? {
        guard let content = window.contentView else {
            return nil
        }
        return checkbox(under: content)
    }

    static func checkbox(under view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.bezelStyle == .flexiblePush, button.allowsMixedState {
            return button
        }
        for subview in view.subviews {
            if let found = checkbox(under: subview) {
                return found
            }
        }
        return nil
    }

    /// A click at the middle of a view, as `TableHost.clickCell` clicks.
    static func click(_ view: NSView, in host: TableHost) {
        let frame: NSRect = view.convert(view.bounds, to: nil)
        let point: NSPoint = NSPoint(x: frame.midX, y: frame.midY)
        for type in [NSEvent.EventType.leftMouseDown, NSEvent.EventType.leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: host.window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) {
                host.window.sendEvent(event)
            }
        }
        host.pump()
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
