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
