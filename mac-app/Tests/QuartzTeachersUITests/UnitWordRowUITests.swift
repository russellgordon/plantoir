import XCTest

/// The unit-word rows, through the real window (#354).
///
/// The setup wizard's "What do you call a unit?" row drew the field's TITLE
/// beside it — a second "Unit" — because a titled field in a grouped form
/// shows its title. `LabeledFieldTripwireTests` holds the source to an empty
/// title; this looks at what is drawn. Course Settings has its own row, a
/// value and a Rename… button, which is checked here so a change to one row
/// is not mistaken for the other.
///
/// Opt-in (`PLANTOIR_UI_TESTS=1`): it needs the foreground.
final class UnitWordRowUITests: XCTestCase {

    private func requireUITestsAreWanted() throws {
        guard ProcessInfo.processInfo.environment["PLANTOIR_UI_TESTS"] == "1" else {
            throw XCTSkip("Opt-in: set PLANTOIR_UI_TESTS=1. This drives the real app and needs the foreground.")
        }
    }

    func testTheWizardsUnitRowShowsItsLabelOnce() throws {
        try requireUITestsAreWanted()
        let launch: IsolatedLaunch = try IsolatedLaunch.launch()
        let application: XCUIApplication = launch.application
        defer { application.typeKey("q", modifierFlags: .command) }

        let newCourseButton: XCUIElement = application.buttons["addCourseButton"].firstMatch
        XCTAssertTrue(newCourseButton.waitForExistence(timeout: 20))
        newCourseButton.click()
        let codeField: XCUIElement = application.textFields["wizardCourseCodeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "The wizard never opened.")
        codeField.click()
        codeField.typeText("ICS3U")
        codeField.typeKey(.escape, modifierFlags: [])

        let unitField: XCUIElement = application.textFields["unitWordField"]
        XCTAssertTrue(unitField.waitForExistence(timeout: 10), "No unit-word field in the wizard.")
        let secondLabel: NSPredicate = NSPredicate(format: "value == %@ OR label == %@", "Unit", "Unit")
        let strays: XCUIElementQuery = application.staticTexts.matching(secondLabel)
        if strays.count > 0 {
            print("=== WIZARD UNIT ROW TREE ===")
            print(application.debugDescription)
        }
        XCTAssertEqual(strays.count, 0, "The wizard's unit row draws the field's title \"Unit\" beside it (#354).")
        XCTAssertNotEqual(unitField.label, "Unit", "The field still carries \"Unit\" as its title.")
        application.buttons["wizardCloseButton"].click()
    }

    func testCourseSettingsKeepsItsOwnUnitRow() throws {
        try requireUITestsAreWanted()
        let launch: IsolatedLaunch = try IsolatedLaunch.launch()
        let application: XCUIApplication = launch.application
        defer { application.typeKey("q", modifierFlags: .command) }

        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 20))
        courseRow.click()
        let value: XCUIElement = application.staticTexts["unitWordValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 10), "Course Settings shows no unit word.")
        XCTAssertTrue(application.buttons["renameUnitWordButton"].exists, "Course Settings has no Rename… button.")
    }
}
