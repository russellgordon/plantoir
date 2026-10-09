import XCTest

/// Temporary: prints the assistant window's element tree so the marketing
/// capture can address the prompt shelf by what it actually is.
final class AssistantTreeDump: MarketingScreenshotCase {

    func testDumpAssistantTree() throws {
        let application: XCUIApplication = launchApp(workspacePath: try demoWorkspacePath())
        openSection(1, ofCourse: "ENG2D", in: application)

        let sectionRow: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "sidebar-ENG2D-section1")
            .firstMatch
        sectionRow.rightClick()
        // Inside Revise With ▸ since the HIG sweep (#457): the row's menu names
        // the command the way the menu bar does.
        // The context menu's own Revise With — the menu bar's Course and
        // Section menus carry one of the same title, closed and not hittable.
        var reviseWith: XCUIElement = application.menuItems["Revise With"]
        _ = reviseWith.waitForExistence(timeout: 15)
        for candidate in application.menuItems.matching(NSPredicate(format: "title == %@", "Revise With")).allElementsBoundByIndex where candidate.isHittable {
            reviseWith = candidate
        }
        reviseWith.hover()
        let assistantItem: XCUIElement = reviseWith.menuItems["Local AI Assistant…"]
        XCTAssertTrue(assistantItem.waitForExistence(timeout: 15))
        assistantItem.click()

        XCTAssertTrue(application.textFields["assistInputField"].waitForExistence(timeout: 240))
        Thread.sleep(forTimeInterval: 3.0)

        print("=== ASSISTANT TREE BEGIN ===")
        print(application.debugDescription)
        print("=== ASSISTANT TREE END ===")
    }
}
