import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The Section menu's plan as a table (#524): Publish Pages…, Hide Pages…
/// and Publish Class for a Date… show the plan as a summary over a row for
/// every page, built from the same plan, in the same call, as the card.
///
/// Every plan here comes from the call the sheet itself makes
/// (`SectionVerbs.publishPages(…, planning: true)` and its siblings, through
/// `run(call:)` on the menu's surface), so the rows and the card are one
/// outcome's two halves. Sentences are named by their `AssistWording`
/// member, never quoted.
@MainActor
final class PublishPlanTableTests: XCTestCase {

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        SectionMenuActivity.reset()
        SectionSchedulePrompt.shared.stopAsking()
        try await super.tearDown()
    }

    // MARK: - The rows

    /// A hidden class links a hidden concept page (which takes the class's
    /// date) and a visible one; two hidden pages share a title, as every
    /// shipped course's `_DUPLICATE ME` pages do. Every page has a row, and
    /// every change row is the card's own line for that page, named the way
    /// the card names it — the test that the table and the card cannot drift.
    func testTheTableHasARowForEveryPageTheCardNames() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try PublishPlanTableTests.layOutAClassWithLinks(in: made.course)
        let outcome: AssistToolOutcome = await made.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1,
            names: ["section1/All Classes/Unit 1, Day 4", "section1/All Classes/_DUPLICATE ME", "Concepts/_DUPLICATE ME"],
            planning: true
        ))
        XCTAssertTrue(outcome.isPlan, outcome.summary)
        let table: AssistPlanTable = try XCTUnwrap(outcome.planTable, "a menu page plan carries its rows")

        var seen: [String] = []
        for row in table.rows {
            seen.append("\(row.folder)/\(row.title) \(row.change)")
        }
        XCTAssertEqual(seen.sorted(), [
            "Concepts/Notes willBecomeVisible",
            "Concepts/Seen alreadyVisible",
            "Concepts/_DUPLICATE ME willBecomeVisible",
            "section1/All Classes/Unit 1, Day 4 willBecomeVisible",
            "section1/All Classes/_DUPLICATE ME willBecomeVisible",
        ])
        XCTAssertEqual(table.summary, AssistWording.menuPlanSummary(changing: 4, already: 1, publishing: true))
        XCTAssertTrue(table.notes.isEmpty, "\(table.notes)")

        let cardLines: [String] = outcome.forTheCard.components(separatedBy: "\n")
        var checked: Int = 0
        for row in table.rows {
            switch row.change {
            case .willBecomeVisible:
                XCTAssertTrue(row.whatChanges.hasPrefix(AssistWording.planWillBecomeVisible), row.whatChanges)
                // The card names a page whose title another page also has
                // with its folder (#425); the table has a Folder column.
                let shown: String = row.title == "_DUPLICATE ME"
                    ? StartOfYearWording.pageNameInFolder(page: row.title, folder: row.folder)
                    : StartOfYearWording.pageName(page: row.title)
                XCTAssertTrue(cardLines.contains("\(shown) \(row.whatChanges)."),
                              "the card has no line for “\(row.title)”: \(outcome.forTheCard)")
                checked += 1
            case .alreadyVisible:
                XCTAssertEqual(row.whatChanges, AssistWording.menuPlanAlreadyVisible)
            default:
                XCTFail("\(row.title): \(row.change)")
            }
        }
        XCTAssertEqual(checked, 4)
    }

    /// The concept page that takes the class's date says so in its own row,
    /// with the same piece the card's line is made of.
    func testADateMoveIsSaidInTheRowOfItsPage() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try PublishPlanTableTests.layOutAClassWithLinks(in: made.course)
        let outcome: AssistToolOutcome = await made.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 4"], planning: true
        ))
        let table: AssistPlanTable = try XCTUnwrap(outcome.planTable)
        var notes: AssistPlanTable.Row?
        for row in table.rows where row.title == "Notes" {
            notes = row
        }
        let row: AssistPlanTable.Row = try XCTUnwrap(notes)
        XCTAssertEqual(row.whatChanges, AssistWording.planWillBecome(visible: true, withTheDatesOf: ["Unit 1, Day 4"]))
        XCTAssertTrue(outcome.forTheCard.components(separatedBy: "\n").contains("“Notes” \(row.whatChanges)."))
    }

    /// Hiding a class whose linked page another visible class still links
    /// to: the page that stays is a row, with the card's reason.
    func testHidingListsWhatStaysAndWhy() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "Uses [[Ohm]].", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-09", body: "Also [[Ohm]].", in: made.course)
        try "---\ntitle: Ohm\npublish: true\n---\nV = IR.\n".write(
            to: made.course.directoryURL.appendingPathComponent("Concepts/Ohm.md"), atomically: true, encoding: .utf8
        )
        let outcome: AssistToolOutcome = await made.runner.run(call: SectionVerbs.hidePages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: true
        ))
        let table: AssistPlanTable = try XCTUnwrap(outcome.planTable, outcome.forTheCard)
        var staying: [AssistPlanTable.Row] = []
        var hiding: [AssistPlanTable.Row] = []
        for row in table.rows {
            if row.change == .staysVisible {
                staying.append(row)
            } else if row.change == .willBecomeHidden {
                hiding.append(row)
            }
        }
        XCTAssertEqual(hiding.count, 1)
        XCTAssertEqual(hiding.first?.whatChanges, AssistWording.planWillBecomeHidden)
        XCTAssertEqual(staying.count, 1, outcome.forTheCard)
        let ohm: AssistPlanTable.Row = try XCTUnwrap(staying.first)
        XCTAssertEqual(ohm.title, "Ohm")
        let reason: AssistPublishKept.Reason = .stillLinkedFrom("Unit 1, Day 2")
        XCTAssertEqual(ohm.whatChanges, AssistWording.planStaysVisibleBecause(reason.finishing(noun: .class)))
        XCTAssertTrue(outcome.forTheCard.components(separatedBy: "\n").contains(
            AssistPublishPlan.stayingVisibleLine(title: "Ohm", reason: reason, noun: .class)
        ), outcome.forTheCard)
        XCTAssertEqual(table.summary, AssistWording.menuPlanSummary(changing: 1, already: 0, publishing: false))
    }

    /// A class linking twenty hidden pages: the card lists fifteen changes
    /// and counts the rest; the table lists all twenty-one.
    func testEveryPageIsListedPastTheCardsFifteen() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let outcome: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: made)
        let table: AssistPlanTable = try XCTUnwrap(outcome.planTable)
        XCTAssertEqual(table.rows.count, 21)
        var visible: Int = 0
        for row in table.rows where row.change == .willBecomeVisible {
            visible += 1
        }
        XCTAssertEqual(visible, 21)
        XCTAssertEqual(outcome.forTheCard.components(separatedBy: AssistWording.planWillBecomeVisible).count - 1, 15,
                       "the card's own cap moved")
    }

    /// A page whose settings have no room for a key (indented, so the writer
    /// declines it): a row of its own, and
    /// the card's sentence about it, word for word, under the table.
    func testAPageLeftAloneHasARowAndTheCardsSentence() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try "---\n  title: Full\n---\nBody.\n".write(
            to: made.course.directoryURL.appendingPathComponent("Concepts/Full.md"), atomically: true, encoding: .utf8
        )
        // Visible (it has no flag), so hiding it is what reaches the writer.
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "One.", in: made.course)
        let outcome: AssistToolOutcome = await made.runner.run(call: SectionVerbs.hidePages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1", "Concepts/Full"], planning: true
        ))
        let table: AssistPlanTable = try XCTUnwrap(outcome.planTable, outcome.forTheCard)
        var leftAlone: [String] = []
        for row in table.rows where row.change == .staysExactlyAsItIs {
            XCTAssertEqual(row.whatChanges, AssistWording.menuPlanStaysExactlyAsItIs)
            leftAlone.append(row.title)
        }
        XCTAssertEqual(leftAlone, ["Full"], outcome.forTheCard)
        let sentence: String = AssistPublishPlan.sayingPagesWithNoRoomForAKey(named: ["Full"], fromTheMenu: true)
        XCTAssertEqual(table.notes, [sentence])
        XCTAssertTrue(outcome.forTheCard.contains(sentence))
    }

    /// Only a page plan asked for from the menu carries rows: not Re-date,
    /// and not the assistant's plan of the same pages.
    func testOnlyAMenuPagePlanCarriesATable() async throws {
        let menu = try AssistFixture.makeRunner(surface: .menu)
        let assistant = try AssistFixture.makeRunner(surface: .local)
        defer {
            try? FileManager.default.removeItem(at: menu.root)
            try? FileManager.default.removeItem(at: assistant.root)
        }
        try MenuVoiceTests.layOutAUnitWithDates(in: menu.course)
        try MenuVoiceTests.layOutAUnitWithDates(in: assistant.course)
        let reDate: AssistToolOutcome = await menu.runner.run(call: SectionVerbs.reDateClasses(
            course: "ICS3U", section: 1, planning: true
        ))
        XCTAssertNil(reDate.planTable)
        let byTheClass: AssistToolOutcome = await menu.runner.run(call: SectionVerbs.publishClass(
            course: "ICS3U", section: 1, on: try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 9)), planning: true
        ))
        XCTAssertNotNil(byTheClass.planTable, byTheClass.forTheCard)
        let asked: AssistToolOutcome = await assistant.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 2"], planning: true
        ))
        XCTAssertTrue(asked.isPlan, asked.summary)
        XCTAssertNil(asked.planTable)
    }

    // MARK: - The sheet

    /// The planned sheet draws one table row per page — all twenty-one, past
    /// the card's fifteen — under the three column names, on the measured
    /// bordered-table metrics, and scrolls inside after twelve.
    func testThePlannedSheetShowsOneTableRowPerPage() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let outcome: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: made)
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .publishPages, course: made.course, sectionNumber: 1,
            title: AssistWording.menuPublishPagesTitle(course: "ICS3U", section: "1"),
            item: .publishPages, stage: .planned
        )
        model.body = outcome.forTheCard
        model.planTable = outcome.planTable
        let host: TableHost = TableHost(
            SectionVerbSheet(model: model, pressDefault: {}, cancel: {}),
            size: NSSize(width: 560, height: 900)
        )
        defer {
            host.close()
        }
        let table: NSTableView = try XCTUnwrap(host.tables().first, "no table on the planned sheet")
        XCTAssertEqual(table.numberOfRows, 21)
        var titles: [String] = []
        for column in table.tableColumns {
            titles.append(column.title)
        }
        XCTAssertEqual(titles, [
            AssistWording.menuPlanPageColumn, AssistWording.menuPlanFolderColumn, AssistWording.menuPlanChangeColumn,
        ])
        XCTAssertEqual(table.rowHeight, ListTableMetrics.rowHeight)
        XCTAssertEqual(table.headerView?.frame.height, ListTableMetrics.headerHeight)
        XCTAssertEqual(table.enclosingScrollView?.frame.height,
                       ListTableMetrics.height(forRowCount: SectionVerbSheet.mostPlanRowsShown, showsHeader: true))
    }

    /// Return is Publish and Escape is Cancel while the table has focus —
    /// the table must not swallow the sheet's default and cancel keys.
    /// Measured first (#524): an in-process key event sent to the hosted
    /// window reaches both buttons with the table first responder and
    /// without, so this harness can see a key go missing.
    func testReturnPublishesAndEscapeCancelsWhileTheTableHasFocus() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let outcome: AssistToolOutcome = try await PublishPlanTableTests.planAClassLinkingTwentyPages(in: made)
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .publishPages, course: made.course, sectionNumber: 1,
            title: AssistWording.menuPublishPagesTitle(course: "ICS3U", section: "1"),
            item: .publishPages, stage: .planned
        )
        model.planTable = outcome.planTable
        let presses: KeyPresses = KeyPresses()
        let host: TableHost = TableHost(
            SectionVerbSheet(
                model: model,
                pressDefault: { presses.defaults += 1 },
                cancel: { presses.cancels += 1 }
            ),
            size: NSSize(width: 560, height: 900)
        )
        defer {
            host.close()
        }
        XCTAssertTrue(model.defaultButtonIsEnabled)
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        host.select(row: 2, in: table)
        XCTAssertTrue(host.window.firstResponder === table, "the table did not take focus")
        host.press(keyCode: 36, characters: "\r")
        XCTAssertEqual(presses.defaults, 1, "Return did not reach Publish with the table focused")
        XCTAssertEqual(presses.cancels, 0)
        host.press(keyCode: 53, characters: "\u{1b}")
        XCTAssertEqual(presses.cancels, 1, "Escape did not reach Cancel with the table focused")
        XCTAssertEqual(presses.defaults, 1)
    }

    // MARK: - Helpers

    /// A hidden class, Unit 1, Day 4, linking a hidden concept page and a
    /// visible one; and two hidden pages called `_DUPLICATE ME`.
    static func layOutAClassWithLinks(in course: Course) throws {
        try MenuVoiceTests.layOutAUnitWithDates(in: course)
        try AssistFixture.write(page: "Unit 1, Day 4", publish: "false", date: "2026-09-11",
                                body: "Links [[Notes]] and [[Seen]].", in: course)
        let concepts: URL = course.directoryURL.appendingPathComponent("Concepts")
        try "---\ntitle: Notes\npublish: false\n---\nNotes.\n".write(
            to: concepts.appendingPathComponent("Notes.md"), atomically: true, encoding: .utf8
        )
        try "---\ntitle: Seen\npublish: true\n---\nSeen.\n".write(
            to: concepts.appendingPathComponent("Seen.md"), atomically: true, encoding: .utf8
        )
        for folder in [ClassPages.folderURL(forSection: 1, in: course), concepts] {
            try "---\ntitle: _DUPLICATE ME\npublish: false\n---\nCopy me.\n".write(
                to: folder.appendingPathComponent("_DUPLICATE ME.md"), atomically: true, encoding: .utf8
            )
        }
    }

    /// The plan of a hidden class that links twenty hidden concept pages.
    static func planAClassLinkingTwentyPages(in made: AssistFixture.Made) async throws -> AssistToolOutcome {
        var links: String = ""
        for number in 1...20 {
            links += "[[Concept \(number)]] "
            try "---\ntitle: Concept \(number)\npublish: false\n---\nIdea.\n".write(
                to: made.course.directoryURL.appendingPathComponent("Concepts/Concept \(number).md"),
                atomically: true, encoding: .utf8
            )
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: links, in: made.course)
        return await made.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: true
        ))
    }
}

/// What the hosted sheet's two buttons were pressed, counted outside the
/// view so the test can read them.
@MainActor
final class KeyPresses {

    // MARK: - Stored properties

    var defaults: Int = 0
    var cancels: Int = 0
}
