import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The tick tables of issue #266 — the marks list (`MembershipToggleListView`)
/// and Sidebar Visibility's Hide/Expandable table
/// (`SidebarVisibilityTableView`) — clicked, spaced and read as a teacher
/// would, through the real `NSTableView` a SwiftUI `Table` becomes.
///
/// The fault these exist for is the one that reports success: a box that
/// DRAWS ticked and WRITES the opposite, or writes a different row's item, or
/// the Hide box writing the Expandable list. Each was put in on purpose
/// (copy the source aside, break it, run, put it back) and turned the named
/// test red — recorded in `documentation/09-mac-app.md` → "Course Settings
/// lists are tables, and why".
@MainActor
final class TickTableTests: XCTestCase {

    // MARK: - Stored properties

    var trailFolderURL: URL?
    var previousStore: ProblemReportStore?

    // MARK: - Set up

    override func setUp() async throws {
        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tick-table-trail-\(UUID().uuidString)", isDirectory: true)
        trailFolderURL = folderURL
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
    }

    override func tearDown() async throws {
        if let previousStore {
            ActivityTrail.store = previousStore
        }
        if let trailFolderURL {
            try? FileManager.default.removeItem(at: trailFolderURL)
        }
    }

    // MARK: - Rows

    func testATickListShowsEachNameOnceTheFirstWinning() {
        let rows: [ListTableRow] = ListTableMetrics.uniqueRows(from: ["Concepts", "Tasks", "Tests", "Tasks", "index.md"])
        var names: [String] = []
        for row in rows {
            names.append(row.name)
        }
        XCTAssertEqual(names, ["Concepts", "Tasks", "Tests", "index.md"])
    }

    func testAnEditedListKeepsEveryEntryAndFindsItsNameWithoutParsing() {
        // A folder name may hold "|", the character the row id uses.
        let rows: [ListTableRow] = ListTableMetrics.positionedRows(from: ["A|B", "Tasks", "Tasks"])
        XCTAssertEqual(rows.count, 3)
        var ids: Set<String> = []
        for row in rows {
            ids.insert(row.id)
        }
        XCTAssertEqual(ids.count, 3, "Two rows share an id, so the table cannot tell them apart")
        XCTAssertEqual(ListTableMetrics.name(ofRowWithID: rows[0].id, in: rows), "A|B")
        XCTAssertEqual(ListTableMetrics.name(ofRowWithID: rows[2].id, in: rows), "Tasks")
        XCTAssertNil(ListTableMetrics.name(ofRowWithID: "nothing", in: rows))
        XCTAssertNil(ListTableMetrics.name(ofRowWithID: nil, in: rows))
    }

    func testTheHeightShowsEveryRowUpToTheCap() {
        XCTAssertEqual(ListTableMetrics.height(forRowCount: 3, showsHeader: false), 3 * 24 + 2)
        XCTAssertEqual(ListTableMetrics.height(forRowCount: 17, showsHeader: true), 17 * 24 + 28 + 2)
        XCTAssertEqual(ListTableMetrics.height(forRowCount: 0, showsHeader: false), 24 + 2)
        XCTAssertEqual(ListTableMetrics.height(forRowCount: 40, showsHeader: false), 20 * 24 + 2)
    }

    // MARK: - Layout, measured on the real table

    /// The frame is computed from 24-point rows and a 28-point header. If
    /// macOS ever draws either differently, the last row is clipped into an
    /// inner scroll (or an empty band appears) — so this reads both off the
    /// real `NSTableView` rather than trusting the numbers.
    func testTheRowAndHeaderHeightsAreTheOnesTheFrameAssumes() throws {
        let box: ListBox = ListBox(["Tasks"], second: [])
        let host: TableHost = TableHost(
            VStack {
                MembershipToggleListView(title: "Marks", allItems: ["Concepts", "Tasks", "Tests"], members: box.binding)
                SidebarVisibilityTableView(allItems: ["Concepts", "Tasks"], hidden: box.binding, expandable: box.secondBinding)
            }
        )
        defer { host.close() }
        let tables: [NSTableView] = host.tables()
        XCTAssertEqual(tables.count, 2)
        let marks: NSTableView = try XCTUnwrap(tables.first)
        let sidebar: NSTableView = try XCTUnwrap(tables.last)

        XCTAssertEqual(marks.rowHeight, ListTableMetrics.rowHeight)
        XCTAssertEqual(sidebar.rowHeight, ListTableMetrics.rowHeight)
        XCTAssertEqual(sidebar.headerView?.frame.height, ListTableMetrics.headerHeight)
        XCTAssertEqual(
            marks.enclosingScrollView?.frame.height,
            ListTableMetrics.height(forRowCount: 3, showsHeader: false),
            "The marks table is not the height its three rows need"
        )
        XCTAssertEqual(
            sidebar.enclosingScrollView?.frame.height,
            ListTableMetrics.height(forRowCount: 2, showsHeader: true)
        )
    }

    // MARK: - The marks table

    func makeMarksTable(members: ListBox, blocked: String? = nil) -> TableHost {
        return TableHost(
            MembershipToggleListView(
                title: GradedFolderWording.listTitle,
                allItems: ["Concepts", "Tasks", "Tests", "Tasks"],
                members: members.binding,
                protection: { folder in
                    if folder == blocked {
                        return .blocked(reason: SpecialNames.lastGradedFolderBlocked)
                    }
                    return .ordinary
                }
            )
        )
    }

    /// Clicking a box adds exactly that row's item, and clicking it again
    /// takes exactly that item out. Red if the box draws the opposite of what
    /// it writes, or if a row's box acts on another row's item.
    func testClickingABoxTicksExactlyThatRowsItem() throws {
        let members: ListBox = ListBox(["Tasks"])
        let host: TableHost = makeMarksTable(members: members)
        defer { host.close() }
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        XCTAssertEqual(table.numberOfRows, 3, "Tasks is offered twice and must be shown once")

        host.clickCell(of: table, column: 0, row: 0)
        XCTAssertEqual(members.names, ["Tasks", "Concepts"])
        host.clickCell(of: table, column: 0, row: 2)
        XCTAssertEqual(members.names, ["Tasks", "Concepts", "Tests"])
        host.clickCell(of: table, column: 0, row: 0)
        XCTAssertEqual(members.names, ["Tasks", "Tests"])
        host.clickCell(of: table, column: 0, row: 1)
        XCTAssertEqual(members.names, ["Tests"])
    }

    /// A protected member stays ticked when clicked, and the trail says the
    /// teacher was told why.
    func testClickingABlockedMemberChangesNothing() throws {
        let members: ListBox = ListBox(["Tasks"])
        let host: TableHost = makeMarksTable(members: members, blocked: "Tasks")
        defer { host.close() }
        let table: NSTableView = try XCTUnwrap(host.tables().first)

        host.clickCell(of: table, column: 0, row: 1)
        XCTAssertEqual(members.names, ["Tasks"])
        XCTAssertTrue(trailText().contains("was told Tasks cannot be unticked under " + GradedFolderWording.listTitle))
    }

    /// Every box draws exactly what the list holds.
    func testEveryBoxDrawsWhatTheListHolds() {
        let members: ListBox = ListBox(["Tasks", "Legacy"])
        let list: MembershipToggleListView = MembershipToggleListView(
            title: "Marks", allItems: ["Concepts", "Tasks", "Tests"], members: members.binding
        )
        for item in ["Concepts", "Tasks", "Tests"] {
            XCTAssertEqual(
                list.membershipBinding(for: item, protection: .ordinary).wrappedValue,
                members.names.contains(item), item
            )
        }
    }

    /// Space does what a click does — including refusing to untick a
    /// protected member. A Space path that worked out protection differently
    /// would untick it silently.
    func testSpaceOnTheSelectedRowDoesWhatAClickDoes() throws {
        let members: ListBox = ListBox(["Tasks"])
        let host: TableHost = makeMarksTable(members: members, blocked: "Tasks")
        defer { host.close() }
        let table: NSTableView = try XCTUnwrap(host.tables().first)

        host.select(row: 2, in: table)
        host.pressSpace()
        XCTAssertEqual(members.names, ["Tasks", "Tests"])

        let list: MembershipToggleListView = MembershipToggleListView(
            title: GradedFolderWording.listTitle, allItems: ["Tasks"], members: members.binding,
            protection: { folder in
                return .blocked(reason: SpecialNames.lastGradedFolderBlocked)
            }
        )
        list.toggleMembership(of: "Tasks")
        XCTAssertEqual(members.names, ["Tasks", "Tests"], "Space unticked a protected folder")
    }

    /// The wizard's Structure section is disabled until a course is chosen,
    /// and a disabled `Table` still takes keys (measured). Space must not tick.
    func testADisabledTableIgnoresSpace() throws {
        let members: ListBox = ListBox([])
        let host: TableHost = TableHost(
            MembershipToggleListView(title: "Marks", allItems: ["Concepts", "Tasks"], members: members.binding)
                .disabled(true)
        )
        defer { host.close() }
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        host.select(row: 1, in: table)
        host.pressSpace()
        XCTAssertEqual(members.names, [])
    }

    // MARK: - The Sidebar Visibility table

    /// Each column writes its OWN list: a click on Hide changes `hidden` and
    /// nothing else, a click on Expandable changes `expandable` and nothing
    /// else. Red if the columns are swapped — the fault that would hide a
    /// folder a teacher asked to expand, and save it that way.
    func testEachColumnWritesOnlyItsOwnList() throws {
        let lists: ListBox = ListBox(["Media", "Tasks"], second: ["Concepts"])
        let host: TableHost = TableHost(
            SidebarVisibilityTableView(
                allItems: ["Concepts", "Tasks", "Tests", "Tasks", "Notes.md"],
                hidden: lists.binding, expandable: lists.secondBinding
            )
        )
        defer { host.close() }
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        XCTAssertEqual(table.numberOfRows, 4, "Tasks is declared twice and must be shown once")

        host.clickCell(of: table, column: 0, row: 2)
        XCTAssertEqual(lists.names, ["Media", "Tasks", "Tests"], "Hide did not hide Tests")
        XCTAssertEqual(lists.secondNames, ["Concepts"], "Hide changed the Expandable list")

        host.clickCell(of: table, column: 1, row: 2)
        XCTAssertEqual(lists.names, ["Media", "Tasks", "Tests"], "Expandable changed the Hide list")
        XCTAssertEqual(lists.secondNames, ["Concepts", "Tests"], "Expandable did not expand Tests")

        host.clickCell(of: table, column: 0, row: 1)
        XCTAssertEqual(lists.names, ["Media", "Tests"], "Unticking Hide on Tasks lost Media, which no row shows")
        host.clickCell(of: table, column: 1, row: 0)
        XCTAssertEqual(lists.secondNames, ["Tests"])
        host.clickCell(of: table, column: 0, row: 3)
        XCTAssertEqual(lists.names, ["Media", "Tests", "Notes.md"], "A file row wrote a name other than its stored one")
    }

    /// Space flips Hide on the selected row, and a disabled table ignores it.
    func testSpaceInTheSidebarTableFlipsHide() throws {
        let lists: ListBox = ListBox([], second: [])
        let host: TableHost = TableHost(
            VStack {
                SidebarVisibilityTableView(allItems: ["Concepts", "Tasks"], hidden: lists.binding, expandable: lists.secondBinding)
                SidebarVisibilityTableView(allItems: ["Concepts", "Tasks"], hidden: lists.binding, expandable: lists.secondBinding)
                    .disabled(true)
            }
        )
        defer { host.close() }
        let tables: [NSTableView] = host.tables()
        XCTAssertEqual(tables.count, 2)

        host.select(row: 1, in: tables[0])
        host.pressSpace()
        XCTAssertEqual(lists.names, ["Tasks"])
        XCTAssertEqual(lists.secondNames, [])

        host.select(row: 0, in: tables[1])
        host.pressSpace()
        XCTAssertEqual(lists.names, ["Tasks"], "A disabled table took Space")
    }

    // MARK: - Functions

    func trailText() -> String {
        guard let trailFolderURL else {
            return ""
        }
        let fileURL: URL = trailFolderURL.appendingPathComponent("activity.txt")
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }
}
