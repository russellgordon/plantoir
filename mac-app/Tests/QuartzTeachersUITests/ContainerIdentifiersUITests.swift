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

        let group: XCUIElement = application.descendants(matching: .any)["backupsGroup"]
        XCTAssertTrue(group.waitForExistence(timeout: 20), "No Backups header in the sidebar.")
        let total: XCUIElement = application.descendants(matching: .any)["backupsTotal"]
        if !total.waitForExistence(timeout: 20) {
            print("=== BACKUPS HEADER TREE ===")
            print(group.debugDescription)
            XCTFail("The Backups total has no identifier of its own: the header's swallowed it (#353).")
        }
    }
}
