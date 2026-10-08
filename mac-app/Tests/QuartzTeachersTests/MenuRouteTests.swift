import AppKit
import XCTest
@testable import QuartzTeachers

/// `MenuRoute` — the guard every menu item's action passes through (#457) —
/// on its own. `MenuKeysBehindASheetTests` cannot see it: with the item
/// greyed, the key never reaches the route. But greying follows
/// `sheetIsUp`, which AppKit's sheet notifications set, and an app-modal
/// panel (`NSAlert.runModal`, an Open panel) never sets it — so the route's
/// own question to the window is the only guard there.
@MainActor
final class MenuRouteTests: XCTestCase {

    // MARK: - Functions

    func settle(seconds: Double = 0.4) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: - Tests

    func testTheRouteRunsNothingBehindASheet() async throws {
        guard let window = WorkspaceModel.windowModels.first?.window else {
            XCTFail("No window model registered; the interface is not on screen")
            return
        }
        XCTAssertNil(MenuRoute.interceptForTests)
        var ran: Int = 0

        // The control: nothing attached, so the action runs.
        MenuRoute.run(.deploy, in: window) {
            ran += 1
        }
        XCTAssertEqual(ran, 1, "with nothing attached the route runs the action")

        let sheet: NSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.beginSheet(sheet, completionHandler: nil)
        await settle()
        defer {
            window.endSheet(sheet)
        }
        XCTAssertNotNil(window.attachedSheet, "the sheet is attached")
        XCTAssertFalse(MenuRoute.windowIsFree(window))
        MenuRoute.run(.deploy, in: window) {
            ran += 1
        }
        MenuRoute.run(.openWorkingFolder, in: window) {
            ran += 1
        }
        XCTAssertEqual(ran, 1, "behind a sheet the route runs nothing")
    }

    /// No window at all (`in: nil`, File with nothing open) is free.
    func testNoWindowIsFree() {
        XCTAssertNil(NSApp.modalWindow, "the suite runs no modal session")
        XCTAssertTrue(MenuRoute.windowIsFree(nil))
        var ran: Int = 0
        MenuRoute.run(.openWorkingFolder, in: nil) {
            ran += 1
        }
        XCTAssertEqual(ran, 1, "File with no window open still opens a folder")
    }
}
