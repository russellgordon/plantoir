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
/// Opt-in: it needs the foreground. xcodebuild passes only `TEST_RUNNER_`
/// variables to the runner, so run it as
/// `TEST_RUNNER_PLANTOIR_UI_TESTS=1 xcodebuild … test -only-testing:QuartzTeachersUITests/UnitWordRowUITests`
/// — plain `PLANTOIR_UI_TESTS=1` skips every test here and looks green.
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

    /// A club's panel says Meetings and Create Club, and the course's words
    /// come back when the box is unticked (#368). Sentences are read from the
    /// contract (this target cannot import the app), never retyped. PRESENCE
    /// first: a grouped Form is lazy, so an off-screen header is not in the
    /// tree and an absence check alone would pass on nothing.
    func testAClubsPanelSaysMeetingsAndCreateClub() throws {
        try requireUITestsAreWanted()
        let rules: [String: Any] = try UnitWordRowUITests.wizardRules()
        let club: [String: Any] = try XCTUnwrap(rules["clubToggle"] as? [String: Any])
        let launch: IsolatedLaunch = try IsolatedLaunch.launch()
        let application: XCUIApplication = launch.application
        defer { application.typeKey("q", modifierFlags: .command) }

        let newCourseButton: XCUIElement = application.buttons["addCourseButton"].firstMatch
        XCTAssertTrue(newCourseButton.waitForExistence(timeout: 20))
        newCourseButton.click()
        let codeField: XCUIElement = application.textFields["wizardCourseCodeField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "The wizard never opened.")
        codeField.click()
        codeField.typeText("CODING")
        codeField.typeKey(.escape, modifierFlags: [])
        let toggle: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "clubToggle").firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "No club tick box.")
        let box: XCUIElement = toggle.checkBoxes.firstMatch.exists ? toggle.checkBoxes.firstMatch : toggle
        if box.value as? Int != 1 {
            box.click()
        }

        try checkPanel(in: application, saysTheWordsOf: club, createButton: club["createButton"] as? String,
                       notTheWordsOf: rules, otherButton: rules["createCourseButton"] as? String)
        box.click()
        try checkPanel(in: application, saysTheWordsOf: rules, createButton: rules["createCourseButton"] as? String,
                       notTheWordsOf: club, otherButton: club["createButton"] as? String)
        application.buttons["wizardCloseButton"].click()
    }

    private func checkPanel(in application: XCUIApplication, saysTheWordsOf words: [String: Any],
                            createButton: String?, notTheWordsOf other: [String: Any],
                            otherButton: String?) throws {
        let heading: String = try XCTUnwrap(words["namingHeading"] as? String)
        let otherHeading: String = try XCTUnwrap(other["namingHeading"] as? String)
        let otherCaption: String = try XCTUnwrap(other["namingCaption"] as? String)
        let unitField: XCUIElement = application.textFields["unitWordField"]
        var scrolls: Int = 0
        while !unitField.exists && scrolls < 12 {
            application.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200)
            scrolls += 1
        }
        XCTAssertTrue(unitField.waitForExistence(timeout: 5), "The naming rows never came into view.")
        // Label and value are asked SEPARATELY: a header's title is a label
        // with no value and its caption a value. Measured on the first runs:
        // one OR-predicate over both matched neither, and even
        // `staticTexts.matching(label == …)` found nothing while the tree
        // showed the text — `staticTexts[title]` and a `.any` label query
        // both find it, so presence is asked those two ways.
        let caption: String = try XCTUnwrap(words["namingCaption"] as? String)
        let byKey: XCUIElement = application.staticTexts[heading]
        let byLabel: XCUIElementQuery = application.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", heading))
        let found: Bool = byKey.waitForExistence(timeout: 5) || byLabel.count > 0
        print("#368 heading \(heading): by key \(byKey.exists), by label \(byLabel.count)")
        if !found {
            print("=== WIZARD TREE ===")
            print(application.debugDescription)
        }
        XCTAssertTrue(found, "The naming section is not headed \(heading).")
        XCTAssertGreaterThan(
            application.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", caption)).count, 0,
            "The naming section's caption is not \(caption)."
        )
        XCTAssertEqual(application.buttons["createCourseButton"].label, createButton)

        XCTAssertFalse(application.staticTexts[otherHeading].exists, "The panel still shows the heading \(otherHeading).")
        XCTAssertEqual(
            application.descendants(matching: .any).matching(NSPredicate(format: "label == %@", otherHeading)).count, 0,
            "The panel still shows the heading \(otherHeading)."
        )
        XCTAssertEqual(
            application.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", otherCaption)).count, 0,
            "The panel still shows the caption \(otherCaption)."
        )
        if let otherButton {
            XCTAssertEqual(application.buttons.matching(NSPredicate(format: "label == %@", otherButton)).count, 0,
                           "A button still says \(otherButton).")
        }
    }

    private static func wizardRules() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["wizard"] as? [String: Any])
    }
}
