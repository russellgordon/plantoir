import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The Start of Year sheet's pages as a table (#589): a row for every page
/// going into draft — classes first, then pages — with its folder and why,
/// the look #524 gave Publish Pages; and the sheet still fitting on a
/// 13-inch screen in its worst case.
///
/// Every plan here comes from `StartOfYearPlanner.plan`, the call the sheet
/// itself makes, on a course laid out on disk. Sentences are named by their
/// `StartOfYearWording` member, never quoted.
@MainActor
final class StartOfYearPlanTableTests: XCTestCase {

    // MARK: - Stored properties

    private var previousTrail: ProblemReportStore = ActivityTrail.store
    private var trailFolder: URL = URL(fileURLWithPath: "/")

    // MARK: - Set up and tear down

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
        trailFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("start-of-year-table-trail-\(UUID().uuidString)")
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
        StartOfYearUndoRegistry.shared.forgetAll()
    }

    override func tearDown() async throws {
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: trailFolder)
        StartOfYearUndoRegistry.shared.forgetAll()
    }

    // MARK: - The rows

    /// A row for every page the write will change, classes first, each with
    /// the reason clause the plan's own line gives it — and every row's line
    /// is in `describe()`, so the table and the plan an outside assistant is
    /// shown cannot drift apart.
    func testTheTableHasARowForEveryPageGoingIntoDraft() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try StartOfYearPlanTableTests.layOutAFewPages(in: made.course)
        let plan: StartOfYearPlan = try StartOfYearPlanTableTests.plan(made)
        let rows: [StartOfYearPlanRow] = plan.tableRows()

        var expected: [StartOfYearDraft] = []
        for draft in plan.draftsThatChange(plan.classDrafts) {
            expected.append(draft)
        }
        for draft in plan.draftsThatChange(plan.pageDrafts) {
            expected.append(draft)
        }
        XCTAssertEqual(rows.count, expected.count)
        XCTAssertEqual(rows.count, plan.changeCount, "a row for every page the write changes")

        var seen: [String] = []
        for row in rows {
            seen.append("\(row.folder)/\(row.title) \(row.reasonKey)")
        }
        XCTAssertEqual(seen, [
            "section1/All Classes/Unit 1, Day 2 laterClass",
            "Concepts/Watt firstUsedLater",
            "Concepts/Ohm onlyHiddenPagesLinkToIt",
        ])

        let first: String = plan.firstClass.displayTitle
        let described: [String] = plan.describe().components(separatedBy: "\n")
        var index: Int = 0
        while index < rows.count {
            let row: StartOfYearPlanRow = rows[index]
            let draft: StartOfYearDraft = expected[index]
            XCTAssertEqual(row.position, index)
            XCTAssertEqual(row.why, draft.reason.sentence(first: first))
            XCTAssertTrue(described.contains("• " + StartOfYearWording.draftLine(name: plan.name(of: draft.page), reason: row.why)),
                          "describe() has no line for “\(row.title)”: \(plan.describe())")
            index += 1
        }
        XCTAssertEqual(rows[2].why, StartOfYearWording.reasonOnlyHiddenPagesLink(page: "Notes"))
    }

    // MARK: - The sheet

    /// Twenty classes: the sheet draws one table row for every one of them,
    /// under the three column names, on the measured bordered-table metrics,
    /// and scrolls inside after `mostPlanRowsShown`.
    func testTheSheetShowsOneTableRowPerPage() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try StartOfYearPlanTableTests.layOutClasses(20, in: made.course)
        let model: StartOfYearSheetModel = StartOfYearPlanTableTests.model(made)
        model.load()
        guard case .ready(let plan) = model.stage else {
            return XCTFail("no plan: \(model.stage)")
        }
        XCTAssertEqual(plan.tableRows().count, 19)
        let host: TableHost = TableHost(StartOfYearSheet(model: model), size: NSSize(width: 560, height: 900))
        defer {
            host.close()
        }
        let table: NSTableView = try XCTUnwrap(host.tables().first, "no table on the Start of Year sheet")
        XCTAssertEqual(table.numberOfRows, 19)
        var titles: [String] = []
        for column in table.tableColumns {
            titles.append(column.title)
        }
        XCTAssertEqual(titles, [
            AssistWording.menuPlanPageColumn, AssistWording.menuPlanFolderColumn, StartOfYearWording.reasonColumn,
        ])
        XCTAssertEqual(table.headerView?.frame.height, ListTableMetrics.headerHeight)
        XCTAssertEqual(table.rect(ofRow: 0).height, ListTableMetrics.rowHeight)
        XCTAssertEqual(table.enclosingScrollView?.frame.height, StartOfYearSheet.tallestPlanTable)
        XCTAssertEqual(StartOfYearSheet.tallestPlanTable,
                       ListTableMetrics.height(forRowCount: StartOfYearSheet.mostPlanRowsShown, showsHeader: true))
    }

    /// A few rows, one of them carrying the longest kind of reason: that row
    /// takes two lines, so the reason reads whole, and the table is exactly
    /// as tall as the rows it draws — the height worked out before drawing
    /// agrees with the real table, with no inner scroll and no empty band.
    func testAShortTableIsAsTallAsItsRowsAndTheLongestReasonReadsWhole() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try StartOfYearPlanTableTests.layOutAFewPages(in: made.course)
        let model: StartOfYearSheetModel = StartOfYearPlanTableTests.model(made)
        let host: TableHost = TableHost(StartOfYearSheet(model: model), size: NSSize(width: 560, height: 900))
        defer {
            host.close()
        }
        let table: NSTableView = try XCTUnwrap(host.tables().first, "no table on the Start of Year sheet")
        XCTAssertEqual(table.numberOfRows, 3)
        var drawn: CGFloat = ListTableMetrics.headerHeight + ListTableMetrics.borderAllowance
        var heights: [CGFloat] = []
        var row: Int = 0
        while row < table.numberOfRows {
            heights.append(table.rect(ofRow: row).height)
            drawn += table.rect(ofRow: row).height
            row += 1
        }
        XCTAssertEqual(heights, [ListTableMetrics.rowHeight, ListTableMetrics.rowHeight, StartOfYearSheet.twoLineRowHeight],
                       "the longest reason should take two lines and the others one")
        XCTAssertEqual(table.enclosingScrollView?.frame.height, drawn,
                       "the table's frame and its rows disagree: a scroll inside, or an empty band")
    }

    /// Return is Go while the table has focus — the table must not swallow
    /// the sheet's default key. The backup is made to fail, so the press is
    /// seen by the sheet refusing and nothing is written. (Escape goes
    /// through `dismiss`, which this host cannot observe; the opt-in
    /// `ContainerIdentifiersUITests.testTheStartOfYearSheetKeepsItsButtonsIdentifiers`
    /// presses it in the running app, after clicking the table's header.)
    func testReturnGoesWhileTheTableHasFocus() async throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try StartOfYearPlanTableTests.layOutAFewPages(in: made.course)
        let model: StartOfYearSheetModel = StartOfYearPlanTableTests.model(made)
        let host: TableHost = TableHost(StartOfYearSheet(model: model), size: NSSize(width: 560, height: 900))
        defer {
            host.close()
        }
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        host.select(row: 1, in: table)
        XCTAssertTrue(host.window.firstResponder === table, "the table did not take focus")
        host.press(keyCode: 36, characters: "\r")
        var waited: Int = 0
        while waited < 20 {
            if case .problem = model.stage {
                break
            }
            // Go starts a Task on the main actor; let it run.
            try await Task.sleep(for: .milliseconds(100))
            host.pump(0.05)
            waited += 1
        }
        guard case .problem(let sentence) = model.stage else {
            return XCTFail("Return did not reach Go with the table focused (notice: \(model.notice ?? "none"))")
        }
        XCTAssertEqual(sentence, StartOfYearWording.backupFailed(course: "ICS3U"))
    }

    // MARK: - The height budget

    /// The worst case: the "changed since" notice, all three warnings, a
    /// page with no room for a key, links left pointing at hidden pages, a
    /// class already in draft, and more rows than the table shows. The sheet
    /// stays within `CopyPageChecklist.tallestSheet` — and, the other
    /// direction, every part is really there at its cap, so a collapsed
    /// table or area cannot pass.
    func testTheWorstCaseSheetStaysOnTheScreen() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try StartOfYearPlanTableTests.layOutTheWorstCase(in: made.course)
        let moment: Date = Date(timeIntervalSince1970: 1_800_000_000)
        let model: StartOfYearSheetModel = StartOfYearPlanTableTests.model(made, scheduledDeploy: moment)
        model.load()
        model.notice = StartOfYearWording.changedSinceShown
        guard case .ready(let plan) = model.stage else {
            return XCTFail("no plan: \(model.stage)")
        }
        // The case really is the worst one before it is measured.
        XCTAssertEqual(plan.warnings().count, 3, "\(plan.warnings())")
        XCTAssertFalse(plan.publishPlan.noRoomForAKey.isEmpty, "no page with no room for a key")
        XCTAssertFalse(plan.danglingSources.isEmpty, "no links left pointing at hidden pages")
        XCTAssertGreaterThan(plan.classesAlreadyInDraft, 0)
        XCTAssertGreaterThan(plan.tableRows().count, StartOfYearSheet.mostPlanRowsShown)

        let height: CGFloat = StartOfYearPlanTableTests.measuredHeight(of: StartOfYearSheet(model: model))
        XCTAssertLessThanOrEqual(
            height, CopyPageChecklist.tallestSheet,
            "The Start of Year sheet is \(height) pt tall; Cancel and Go go off a 1280 × 800 screen past \(CopyPageChecklist.tallestSheet)"
        )
        // The lower bound: the table and both capped areas are there at their
        // caps, with the title band, the summary and the buttons around them.
        let parts: CGFloat = StartOfYearSheet.tallestPlanTable + StartOfYearSheet.tallestPlanIntro
            + StartOfYearSheet.tallestPlanNotes
        XCTAssertGreaterThanOrEqual(
            height, parts + 120,
            "The sheet is only \(height) pt: the table or an area under or over it has collapsed"
        )
        print("StartOfYearPlanTableTests: worst-case sheet \(height) pt against \(CopyPageChecklist.tallestSheet)")
    }

    /// In the same worst case, every warning and the first line of the intro
    /// are inside the area above the table without scrolling (#589's
    /// implementation review, S1: at a 100 pt cap the scheduled deploy's
    /// warning — "will put these changes in front of students" — was below
    /// the fold, and overlay scroll bars give no sign there is more). The
    /// notice and warnings are laid out exactly as the sheet lays them out,
    /// with the intro's first line under them, at the area's width. This
    /// builds its OWN copy of the area from the sheet's pieces
    /// (`mustBeReadBeforeGo`, `planIntroSpacing`): a longer sentence or a
    /// smaller cap turns it red, but it would not see `planView` putting the
    /// intro back above the warnings or padding the area (#589's fixes
    /// review, F3). The fixture's first class is "Unit 1, Day 1"; the claim
    /// about the intro's first line holds for short titles only (F2).
    func testEveryWarningAndTheIntrosFirstLineAreInView() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try StartOfYearPlanTableTests.layOutTheWorstCase(in: made.course)
        let moment: Date = Date(timeIntervalSince1970: 1_800_000_000)
        let model: StartOfYearSheetModel = StartOfYearPlanTableTests.model(made, scheduledDeploy: moment)
        model.load()
        guard case .ready(let plan) = model.stage else {
            return XCTFail("no plan: \(model.stage)")
        }
        XCTAssertEqual(plan.warnings().count, 3, "\(plan.warnings())")
        let opening = VStack(alignment: .leading, spacing: StartOfYearSheet.planIntroSpacing) {
            StartOfYearSheet.mustBeReadBeforeGo(plan, notice: StartOfYearWording.changedSinceShown)
            Text(StartOfYearWording.intro(first: plan.firstClass.displayTitle, noun: plan.noun.singular))
                .lineLimit(1)
        }
        .frame(width: 520, alignment: .leading)
        let height: CGFloat = StartOfYearPlanTableTests.measuredHeight(of: opening, width: 520)
        XCTAssertLessThanOrEqual(
            height, StartOfYearSheet.tallestPlanIntro,
            "The notice, the three warnings and the intro's first line need \(height) pt; the area above the table shows \(StartOfYearSheet.tallestPlanIntro) before it scrolls"
        )
        // The other direction: the four orange lines and the intro's first
        // line are really there (each is at least one 16-point line).
        XCTAssertGreaterThanOrEqual(height, 5 * 16, "only \(height) pt: something in the opening is not showing")
        print("StartOfYearPlanTableTests: notice, three warnings and the intro's first line \(height) pt against \(StartOfYearSheet.tallestPlanIntro)")
    }

    /// The `firstClassIsHidden` warning quotes the first class's title, so a
    /// long one makes the warnings taller: with a 40-character title the
    /// notice and all three warnings still fit the area above the table
    /// (the intro's first line may then scroll; #589's fixes review, F2).
    func testTheWarningsStayInViewWithALongFirstClassTitle() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try StartOfYearPlanTableTests.layOutTheWorstCase(in: made.course)
        let longTitle: String = "Unit 1, Day 1: Welcome to Computer Study"
        XCTAssertEqual(longTitle.count, 40)
        try "---\ntitle: \(longTitle)\npublish: false\ncreated: 2026-09-01T07:00:00.000-0400\n---\n\nSee [[Marks]].\n".write(
            to: ClassPages.folderURL(forSection: 1, in: made.course).appendingPathComponent("Unit 1, Day 1.md"),
            atomically: true, encoding: .utf8
        )
        let moment: Date = Date(timeIntervalSince1970: 1_800_000_000)
        let model: StartOfYearSheetModel = StartOfYearPlanTableTests.model(made, scheduledDeploy: moment)
        model.load()
        guard case .ready(let plan) = model.stage else {
            return XCTFail("no plan: \(model.stage)")
        }
        XCTAssertEqual(plan.firstClass.displayTitle, longTitle)
        XCTAssertEqual(plan.warnings().count, 3, "\(plan.warnings())")
        let warnings = VStack(alignment: .leading, spacing: StartOfYearSheet.planIntroSpacing) {
            StartOfYearSheet.mustBeReadBeforeGo(plan, notice: StartOfYearWording.changedSinceShown)
        }
        .frame(width: 520, alignment: .leading)
        let height: CGFloat = StartOfYearPlanTableTests.measuredHeight(of: warnings, width: 520)
        XCTAssertLessThanOrEqual(
            height, StartOfYearSheet.tallestPlanIntro,
            "With a 40-character first class, the notice and three warnings need \(height) pt against \(StartOfYearSheet.tallestPlanIntro)"
        )
        XCTAssertGreaterThanOrEqual(height, 4 * 16, "only \(height) pt: a warning is not showing")
        print("StartOfYearPlanTableTests: notice and three warnings, 40-character first class, \(height) pt against \(StartOfYearSheet.tallestPlanIntro)")
    }

    /// In the worst case — the table full, so the notes area is at its floor
    /// — what must be read before Go under the table ends inside the cap:
    /// publishing from now on, the links left pointing at hidden pages (said
    /// nowhere after Go) and the pages with no room for a key, whole. Read
    /// off the sheet's REAL notes (`planNotes` reports where each ends), so a
    /// reordering or a smaller cap turns this red (#589's fixes reviews, F1
    /// and R1). The undo's limit, which the result repeats, may scroll.
    func testTheSentencesUnderTheTableAreInView() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try StartOfYearPlanTableTests.layOutTheWorstCase(in: made.course)
        let moment: Date = Date(timeIntervalSince1970: 1_800_000_000)
        let model: StartOfYearSheetModel = StartOfYearPlanTableTests.model(made, scheduledDeploy: moment)
        model.load()
        guard case .ready(let plan) = model.stage else {
            return XCTFail("no plan: \(model.stage)")
        }
        XCTAssertFalse(plan.publishPlan.noRoomForAKey.isEmpty)
        XCTAssertFalse(plan.danglingSources.isEmpty)
        XCTAssertGreaterThan(plan.classesAlreadyInDraft, 0)
        let cap: CGFloat = StartOfYearSheet.notesCap(for: plan.tableRows())
        XCTAssertEqual(cap, StartOfYearSheet.tallestPlanNotes, "a full table leaves the notes at their floor")
        let bottoms: NoteBottoms = NoteBottoms()
        let notes = StartOfYearSheet.planNotes(plan, first: plan.firstClass.displayTitle) { (name: String, bottom: CGFloat) in
            bottoms.byName[name] = bottom
        }
        let host: TableHost = TableHost(notes, size: NSSize(width: 520, height: 900))
        defer {
            host.close()
        }
        for name in ["publishingFromNowOn", "linksLeftHeading", "noRoomForAKey"] {
            let bottom: CGFloat = try XCTUnwrap(bottoms.byName[name], "\(name) was never laid out")
            XCTAssertGreaterThan(bottom, 0)
            XCTAssertLessThanOrEqual(bottom, cap, "\(name) ends at \(bottom) pt, below the notes area's \(cap) pt")
            print("StartOfYearPlanTableTests: \(name) ends at \(bottom) pt against \(cap)")
        }
    }

    /// A short table gives its unused height to the notes (#589's fixes
    /// review, R3): with three rows the notes area may grow past its floor.
    func testAShortTableGivesItsRoomToTheNotes() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try StartOfYearPlanTableTests.layOutAFewPages(in: made.course)
        let plan: StartOfYearPlan = try StartOfYearPlanTableTests.plan(made)
        let rows: [StartOfYearPlanRow] = plan.tableRows()
        XCTAssertEqual(rows.count, 3)
        let unused: CGFloat = StartOfYearSheet.tallestPlanTable - StartOfYearSheet.planTableHeight(for: rows)
        XCTAssertGreaterThan(unused, 0)
        XCTAssertEqual(StartOfYearSheet.notesCap(for: rows), StartOfYearSheet.tallestPlanNotes + unused)
        XCTAssertGreaterThan(StartOfYearSheet.notesCap(for: rows), StartOfYearSheet.tallestPlanNotes)
    }

    /// A plan of three rows and no warnings is a short sheet: no area
    /// reserves its cap, and the table is its rows.
    func testAShortPlanMakesAShortSheet() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try StartOfYearPlanTableTests.layOutAFewPages(in: made.course)
        let model: StartOfYearSheetModel = StartOfYearPlanTableTests.model(made)
        model.load()
        guard case .ready(let plan) = model.stage else {
            return XCTFail("no plan: \(model.stage)")
        }
        let height: CGFloat = StartOfYearPlanTableTests.measuredHeight(of: StartOfYearSheet(model: model))
        let parts: CGFloat = StartOfYearSheet.tallestPlanTable + StartOfYearSheet.tallestPlanIntro
            + StartOfYearSheet.tallestPlanNotes
        XCTAssertLessThan(height, parts + 100, "A three-row plan is \(height) pt tall — something reserves space it does not use")
        XCTAssertGreaterThanOrEqual(
            height, StartOfYearSheet.planTableHeight(for: plan.tableRows()) + 200,
            "A three-row plan is only \(height) pt tall: its table or its sentences are not showing"
        )
        print("StartOfYearPlanTableTests: three-row sheet \(height) pt")
    }

    // MARK: - Helpers

    /// Lays the sheet out at its own width and reports the height its
    /// content claims, after forcing a layout pass — as
    /// `CopyPageChecklistSizeTests.measuredHeight` does.
    static func measuredHeight(of view: some View, width: CGFloat = 560) -> CGFloat {
        let hostingView: NSHostingView = NSHostingView(rootView: AnyView(view))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 2000)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    static func model(_ made: AssistFixture.Made, scheduledDeploy: Date? = nil) -> StartOfYearSheetModel {
        return StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady,
            today: { return CalendarDay(year: 2026, month: 9, day: 8)! },
            backUp: { _, _ in
                throw CocoaError(.fileWriteNoPermission)
            },
            scheduledDeploy: { _, _, _ in
                return scheduledDeploy
            }
        )
    }

    static func plan(_ made: AssistFixture.Made) throws -> StartOfYearPlan {
        switch StartOfYearPlanner.plan(
            forSection: 1, in: made.course, workspaceURL: made.root,
            today: CalendarDay(year: 2026, month: 9, day: 8)!
        ) {
        case .failure(let problem):
            throw problem
        case .success(let plan):
            return plan
        }
    }

    /// Unit 1, Day 1 and Day 2 (both visible, Day 2 linking Watt); Ohm,
    /// which only the hidden page Notes links to. Three rows: Day 2 (comes
    /// after Day 1), Watt (first used in Day 2), Ohm (only Notes links to it
    /// — the longest kind of reason).
    static func layOutAFewPages(in course: Course) throws {
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "One.", in: course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-09",
                                body: "See [[Watt]].", in: course)
        try StartOfYearTests.writeCoursePage("Watt", links: [], in: course)
        try StartOfYearTests.writeCoursePage("Ohm", links: [], in: course)
        try "---\ntitle: Notes\npublishForSection1: false\n---\n\nSee [[Ohm]].\n".write(
            to: course.directoryURL.appendingPathComponent("Concepts/Notes.md"), atomically: true, encoding: .utf8
        )
    }

    /// `count` visible classes, Unit 1, Day 1 onwards, all after today but
    /// the first.
    static func layOutClasses(_ count: Int, in course: Course) throws {
        var day: Int = 1
        while day <= count {
            try AssistFixture.write(page: "Unit 1, Day \(day)", publish: "true",
                                    date: String(format: "2026-09-%02d", day + 7), body: "Day \(day).", in: course)
            day += 1
        }
    }

    /// Every sentence the plan can add at once: the first class in draft,
    /// classes dated before today going into draft, a class already in
    /// draft, Marks (kept, as the first class links it) left linking two
    /// pages going into draft, and Full, whose settings have no room for a
    /// key. Twenty classes, so the table is past its rows. The scheduled
    /// deploy, the third warning, is the model's to inject.
    static func layOutTheWorstCase(in course: Course) throws {
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-01",
                                body: "See [[Marks]].", in: course)
        var day: Int = 2
        while day <= 20 {
            let body: String = day == 2 ? "See [[Watt]] and [[Volt]]." : "Day \(day)."
            try AssistFixture.write(page: "Unit 1, Day \(day)", publish: "true",
                                    date: String(format: "2026-09-%02d", day), body: body, in: course)
            day += 1
        }
        try AssistFixture.write(page: "Unit 1, Day 21", publish: "false", date: "2026-09-21", body: "Later.", in: course)
        for concept in ["Watt", "Volt"] {
            try StartOfYearTests.writeCoursePage(concept, links: [], in: course)
        }
        try StartOfYearTests.writeCoursePage("Marks", links: ["Watt", "Volt"], in: course)
        try "---\n  title: Full\n---\nBody.\n".write(
            to: course.directoryURL.appendingPathComponent("Concepts/Full.md"), atomically: true, encoding: .utf8
        )
    }
}

/// Where the notes' two must-read sentences end, collected outside the view.
@MainActor
final class NoteBottoms {

    // MARK: - Stored properties

    var byName: [String: CGFloat] = [:]
}
