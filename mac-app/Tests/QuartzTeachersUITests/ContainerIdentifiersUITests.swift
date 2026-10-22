import XCTest

/// An identifier on a container does not swallow the identifiers inside it
/// (#353), read off the real tree.
///
/// SwiftUI applies `.accessibilityIdentifier` on a plain stack to EVERY element
/// inside it, so an inner identifier never reaches the tree: the credential
/// sheet's field and Send button were both reported as "credentialSheet"
/// (2026-09-26). `.accessibilityElement(children: .contain)` before the
/// identifier makes the stack an element of its own and keeps its children's.
/// The credential sheet is proved by `NewSiteDialogUITests`, which now finds
/// its field and button by identifier; this proves the Backups header, the
/// one other container a fixture can show without a synced folder, a copy or
/// a preview. The in-process tree does not reach hosted SwiftUI, so there is
/// no unit test for this (measured on the #213 attempt).
///
/// Opt-in (`PLANTOIR_UI_TESTS=1`): it needs the foreground.
final class ContainerIdentifiersUITests: XCTestCase {

    func testTheBackupsHeaderKeepsItsTotalsIdentifier() throws {
        guard ProcessInfo.processInfo.environment["PLANTOIR_UI_TESTS"] == "1" else {
            throw XCTSkip("Opt-in: set PLANTOIR_UI_TESTS=1. This drives the real app and needs the foreground.")
        }
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        let backupsURL: URL = fixtureURL.appendingPathComponent("courses/_backups/EXC2O")
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4096).write(
            to: backupsURL.appendingPathComponent("EXC2O_backup_2026-09-20_101500.zip")
        )

        let launch: IsolatedLaunch = try IsolatedLaunch.launch(workspace: fixtureURL)
        let application: XCUIApplication = launch.application
        defer { application.typeKey("q", modifierFlags: .command) }

        // Read off the real tree, 2026-09-26. A List section's header is
        // merged into ONE static text ("Backups, 4 KB"). With an identifier
        // on the header too, it read "backupsGroup-backupsGroup" and
        // `backupsTotal` was dead; the header's own was dropped (nothing read
        // it), and the text carries `backupsTotal`.
        let total: XCUIElement = application.descendants(matching: .any)["backupsTotal"]
        if !total.waitForExistence(timeout: 20) {
            print("=== SIDEBAR TREE ===")
            print(application.outlines.firstMatch.debugDescription)
            XCTFail("The Backups total has no identifier of its own: the header's swallowed it (#353).")
        }
    }

    /// The start-of-year sheet's Go keeps its own identifier (#366). Before
    /// the fix, Cancel and "Put These into Draft" both read back as
    /// `startOfYearSheet`. Since #589 the plan's table is found by its own
    /// identifier too, and its Why header is clicked twice to sort it, the
    /// way the marketing capture does — the first row must change, or the
    /// capture's sort is a click whose effect nobody checked. Cancelled at
    /// the end: nothing is written.
    func testTheStartOfYearSheetKeepsItsButtonsIdentifiers() throws {
        guard ProcessInfo.processInfo.environment["PLANTOIR_UI_TESTS"] == "1" else {
            throw XCTSkip("Opt-in: set PLANTOIR_UI_TESTS=1. This drives the real app and needs the foreground.")
        }
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        // Two published classes, so the plan has something after Day 1 and
        // Go is offered (the shape AssistantRolloverUITests writes).
        let classesURL: URL = fixtureURL.appendingPathComponent("courses/EXC2O/section1/All Classes")
        try FileManager.default.createDirectory(at: classesURL, withIntermediateDirectories: true)
        for day in [1, 2] {
            try """
            ---
            title: Unit 1, Day \(day)
            date: 2026-09-0\(day + 7)
            publish: true
            ---
            A class.
            """.write(
                to: classesURL.appendingPathComponent("Unit 1, Day \(day).md"),
                atomically: true, encoding: .utf8
            )
        }
        // A page nothing links to, so the table has a second reason to sort
        // by (#589): Day 2 "comes after …", this one "nothing links to it".
        let conceptsURL: URL = fixtureURL.appendingPathComponent("courses/EXC2O/Concepts")
        try FileManager.default.createDirectory(at: conceptsURL, withIntermediateDirectories: true)
        try "---\ntitle: Unlinked Notes\npublishForSection1: true\n---\n\nNotes.\n".write(
            to: conceptsURL.appendingPathComponent("Unlinked Notes.md"), atomically: true, encoding: .utf8
        )

        let launch: IsolatedLaunch = try IsolatedLaunch.launch(workspace: fixtureURL)
        let application: XCUIApplication = launch.application
        defer { application.typeKey("q", modifierFlags: .command) }

        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 30), "EXC2O should be in the sidebar")
        courseRow.click()
        application.typeKey(.rightArrow, modifierFlags: [])
        let sectionRow: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "sidebar-EXC2O-section1").firstMatch
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 20), "Section 1 should be in the sidebar")
        sectionRow.rightClick()
        let item: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "startOfYear-EXC2O-section1").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15), "The section menu should offer to get ready (#96)")
        item.click()

        let go: XCUIElement = application.buttons["startOfYearGo"]
        if !go.waitForExistence(timeout: 30) {
            print("=== SHEET TREE ===")
            print(application.sheets.firstMatch.debugDescription)
            XCTFail("Go has no identifier of its own: the sheet's swallowed it (#366).")
        }
        let table: XCUIElement = startOfYearPlanTable(in: application)
        if !table.waitForExistence(timeout: 10) {
            print("=== SHEET TREE ===")
            print(application.sheets.firstMatch.debugDescription)
            XCTFail("The plan's table has no identifier of its own (#589).")
        } else {
            let unsorted: String = firstRowReason(in: table)
            sortStartOfYearPlanByReasonDescending(table, whyTitle: try startOfYearWording("reasonColumn"))
            let sorted: String = firstRowReason(in: table)
            print("#589 first row's reason: unsorted “\(unsorted)”, after two clicks on Why “\(sorted)”")
            if sorted == unsorted {
                print("=== TABLE TREE ===")
                print(table.debugDescription)
            }
            XCTAssertNotEqual(sorted, unsorted, "Two clicks on the Why header did not sort the table (#589)")
            XCTAssertEqual(sorted, try startOfYearWording("reasonNothingLinks"))
        }
        let cancel: XCUIElement = application.sheets.firstMatch.buttons["Cancel"]
        XCTAssertTrue(cancel.exists, "The sheet should offer Cancel")
        XCTAssertNotEqual(cancel.identifier, "startOfYearSheet", "Cancel carries the sheet's identifier (#366)")
        cancel.click()
    }
}
