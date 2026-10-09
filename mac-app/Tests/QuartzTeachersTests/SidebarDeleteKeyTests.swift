import XCTest
@testable import QuartzTeachers

/// The Delete key on a sidebar row (#457 item 4, the HIG sweep): it runs the
/// menu item `contracts/shared-rules.json` → `sidebarDeleteKey` names, under
/// that item's own enablement, so it asks the same question and can never do
/// what the greyed item would not.
@MainActor
final class SidebarDeleteKeyTests: XCTestCase {

    // MARK: - Tests

    func testEveryRowAsksForTheItemTheContractNames() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("sidebarDeleteKey")
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, SubjectMenuRules.Row.allCases.count, "one case per kind of row")
        for testCase in cases {
            let rowName: String = try XCTUnwrap(testCase["row"] as? String)
            let row: SubjectMenuRules.Row = try XCTUnwrap(SubjectMenuRules.Row(rawValue: rowName), "Unknown row \(rowName)")
            let expected: String? = testCase["item"] as? String
            XCTAssertEqual(SubjectMenuRules.deleteKeyItem(for: row)?.rawValue, expected, "row \(rowName)")
        }
    }

    /// A section of a course kept for reference: the key asks for Remove
    /// Section…, and that item is GREYED (`interface.whatIsWithheld`), so
    /// nothing is asked. Until the HIG sweep the item was live there.
    func testRemoveSectionIsWithheldOnAReferenceSection() {
        var situation: SubjectMenuRules.Situation = SubjectMenuRules.Situation()
        situation.hasFolder = true
        situation.obsidianInstalled = true
        situation.row = .section
        situation.keptForReference = true
        let enabled: Set<SubjectMenuRules.Item> = SubjectMenuRules.enabledItems(situation)
        XCTAssertFalse(enabled.contains(.removeSection), "Remove Section N is withheld on a reference course")
        situation.row = .course
        XCTAssertTrue(SubjectMenuRules.enabledItems(situation).contains(.removeCourse), "removing the whole course stays")
    }

    /// Under a sheet the key does nothing either: every item greys.
    func testNothingIsAskedUnderASheet() {
        for row in SubjectMenuRules.Row.allCases {
            var situation: SubjectMenuRules.Situation = SubjectMenuRules.Situation()
            situation.hasFolder = true
            situation.row = row
            situation.sheetIsUp = true
            if let item = SubjectMenuRules.deleteKeyItem(for: row) {
                XCTAssertFalse(SubjectMenuRules.enabledItems(situation).contains(item), "row \(row.rawValue)")
            }
        }
    }

    /// The sidebar wires the key to the menu item's own runner.
    func testTheSidebarRunsTheMenuItem() throws {
        let sidebar: String = try String(
            contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent("SidebarView.swift"), encoding: .utf8
        )
        XCTAssertTrue(sidebar.contains(".onDeleteCommand(perform: deleteKeyPressed)"))
        let body: String = SheetConventionScanTests.functionBody(named: "deleteKeyPressed", in: sidebar)
        XCTAssertTrue(body.contains("SubjectMenuRules.deleteKeyItem(for: menuCommands.situation.row)"))
        XCTAssertTrue(body.contains("performMenuItem(item)"), "through the item's own enablement check and closure")
    }
}

/// The sidebar's − button runs the same Remove item as the Delete key and
/// the menu bar, and is enabled exactly when that item is (#457, the HIG
/// sweep's implementation review: it still removed a reference section).
@MainActor
final class SidebarMinusButtonTests: XCTestCase {

    // MARK: - Tests

    func testTheMinusButtonIsGreyOnAReferenceSection() {
        var situation: SubjectMenuRules.Situation = SubjectMenuRules.Situation()
        situation.hasFolder = true
        situation.row = .section
        situation.keptForReference = true
        XCTAssertFalse(SubjectMenuRules.minusButtonIsEnabled(situation), "Remove Section N is withheld on a reference course")
        situation.row = .course
        XCTAssertTrue(SubjectMenuRules.minusButtonIsEnabled(situation), "removing the whole course stays")
        situation.keptForReference = false
        situation.row = .section
        XCTAssertTrue(SubjectMenuRules.minusButtonIsEnabled(situation))
        situation.copying = true
        XCTAssertFalse(SubjectMenuRules.minusButtonIsEnabled(situation), "not while the course is being copied")
        situation.copying = false
        situation.sheetIsUp = true
        XCTAssertFalse(SubjectMenuRules.minusButtonIsEnabled(situation), "not under a sheet")
        for row in [SubjectMenuRules.Row.backup, .archived, .allBackups, .none] {
            situation.sheetIsUp = false
            situation.row = row
            XCTAssertNil(SubjectMenuRules.minusButtonItem(for: row))
            XCTAssertFalse(SubjectMenuRules.minusButtonIsEnabled(situation), "row \(row.rawValue)")
        }
    }

    /// The button asks the rule and runs the item; it does not call
    /// `prepareRemoval` itself.
    func testTheButtonGoesThroughTheRule() throws {
        let sidebar: String = try String(
            contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent("SidebarView.swift"), encoding: .utf8
        )
        XCTAssertTrue(sidebar.contains(".disabled(!SubjectMenuRules.minusButtonIsEnabled(menuCommands.situation))"))
        XCTAssertTrue(sidebar.contains("if let item = SubjectMenuRules.minusButtonItem(for: menuCommands.situation.row) {"))
    }
}
