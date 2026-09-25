import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The name tables of issue #266 — the four Content Structure lists in
/// Course Settings and the wizard — driven through the real `NSTableView`:
/// the Delete key removes the selected entry through `requestRemoval(of:)`,
/// so a protected entry stays; and a disabled table (the wizard before a
/// course is chosen) takes no Delete at all.
@MainActor
final class NameTableTests: XCTestCase {

    // MARK: - Stored properties

    var trailFolderURL: URL?
    var previousStore: ProblemReportStore?

    // MARK: - Set up

    override func setUp() async throws {
        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("name-table-trail-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Tests

    func makeEditor(_ box: ListBox) -> StringListEditorView {
        return StringListEditorView(
            title: "Per-section folders",
            items: box.binding,
            protection: { folder in
                if folder == "All Classes" {
                    return .blocked(reason: SpecialNames.classFolderBlocked)
                }
                return .ordinary
            }
        )
    }

    /// Delete on a selected entry removes exactly that entry; on a blocked
    /// one it removes nothing.
    func testDeleteRemovesTheSelectedEntryUnlessItIsProtected() throws {
        let box: ListBox = ListBox(["All Classes", "Tasks", "Tests"])
        let host: TableHost = TableHost(makeEditor(box))
        defer { host.close() }
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertEqual(table.rowHeight, ListTableMetrics.rowHeight)

        host.select(row: 0, in: table)
        host.pressDelete()
        XCTAssertEqual(box.names, ["All Classes", "Tasks", "Tests"], "Delete removed a protected folder")

        host.select(row: 2, in: table)
        host.pressDelete()
        XCTAssertEqual(box.names, ["All Classes", "Tasks"], "Delete did not remove the selected folder")
    }

    /// The wizard's Structure section is disabled until a course is chosen,
    /// and a disabled `Table` still takes keys (measured). Delete must not
    /// remove anything there.
    func testADisabledTableIgnoresDelete() throws {
        let box: ListBox = ListBox(["Tasks", "Tests"])
        let host: TableHost = TableHost(makeEditor(box).disabled(true))
        defer { host.close() }
        let table: NSTableView = try XCTUnwrap(host.tables().first)
        host.select(row: 1, in: table)
        host.pressDelete()
        XCTAssertEqual(box.names, ["Tasks", "Tests"], "A disabled table took Delete")
    }

    /// Every way to remove goes through `requestRemoval(of:)` — read off the
    /// source, because the − button and the row menu cannot be pressed from
    /// a unit test.
    func testEveryRemovalControlAsksTheProtectionFirst() throws {
        let sourceURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac-app
            .appendingPathComponent("QuartzTeachers/Views/CourseSettings/StringListEditorView.swift")
        let source: String = try String(contentsOf: sourceURL, encoding: .utf8)
        var callers: Int = 0
        var searchRange: Range<String.Index>? = source.startIndex..<source.endIndex
        while let range = searchRange, let found = source.range(of: "requestRemoval(of: ", range: range) {
            callers = callers + 1
            searchRange = found.upperBound..<source.endIndex
        }
        // The − button, the Delete key and the row menu's Remove.
        XCTAssertEqual(callers, 3, "A removal control no longer goes through requestRemoval(of:)")
        var directRemovals: Int = 0
        searchRange = source.startIndex..<source.endIndex
        while let range = searchRange, let found = source.range(of: "removeItem(named: ", range: range) {
            directRemovals = directRemovals + 1
            searchRange = found.upperBound..<source.endIndex
        }
        // requestRemoval's ordinary case and the alert's Remove, and nothing else.
        XCTAssertEqual(directRemovals, 2, "Something removes an entry without asking its protection")
    }
}
