import XCTest

/// #397 through the real window, once: Preview asks about today's class, Show
/// on Front Page changes the file and the preview then starts; Not Today is
/// remembered and the preview starts. A synthetic course in the runner's own
/// temporary folder, `--state-dir` (IsolatedLaunch) and a STUB `preview.sh` —
/// nothing is built, and no container is used.
final class TodaysClassOnTheFrontPageUITests: XCTestCase {

    // MARK: - Stored properties

    private var stubPreviewPIDFileURL: URL?

    // MARK: - Set up and tear down

    override func tearDown() {
        if let pidFileURL = stubPreviewPIDFileURL {
            StubLaunchers.reap(pidFileURL: pidFileURL, expectingNamePrefix: "python")
        }
        stubPreviewPIDFileURL = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testPreviewAsksShowsAndRemembersNotToday() throws {
        let fixtureURL: URL = try UITestFolders.makeFixture()
        let sectionURL: URL = fixtureURL.appendingPathComponent("courses/EXC2O/section1")
        let classesURL: URL = sectionURL.appendingPathComponent("All Classes")
        try FileManager.default.createDirectory(at: classesURL, withIntermediateDirectories: true)

        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let today: String = formatter.string(from: Date())
        let yesterday: String = formatter.string(from: Date().addingTimeInterval(-86_400))
        try TodaysClassOnTheFrontPageUITests.classPage("Unit 9, Day 1", on: yesterday)
            .write(to: classesURL.appendingPathComponent("Unit 9, Day 1.md"), atomically: true, encoding: .utf8)
        try TodaysClassOnTheFrontPageUITests.classPage("Unit 9, Day 2", on: today)
            .write(to: classesURL.appendingPathComponent("Unit 9, Day 2.md"), atomically: true, encoding: .utf8)
        let indexURL: URL = sectionURL.appendingPathComponent("index.md")
        let showingYesterday: String = "---\ntitle: Section 1\npublish: true\ncreated: \(yesterday)T07:00:00.000-0400\n---\n"
            + "# Most Recent Class\n\n![[Unit 9, Day 1]]\n"
        try showingYesterday.write(to: indexURL, atomically: true, encoding: .utf8)

        let publicURL: URL = fixtureURL.appendingPathComponent("courses/EXC2O/.merged_output/section1/public")
        stubPreviewPIDFileURL = try StubLaunchers.writeStubPreviewScript(in: fixtureURL, buildingInto: publicURL)

        let application: XCUIApplication = try IsolatedLaunch.launch(workspace: fixtureURL).application
        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        courseRow.click()
        application.typeKey(.rightArrow, modifierFlags: [])
        let sectionRow: XCUIElement = application.outlines.staticTexts["Section 1"]
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 10))
        sectionRow.click()

        // 1. Preview → the question → Show on Front Page.
        application.buttons["previewButton"].firstMatch.click()
        let show: XCUIElement = application.windows.buttons["Show on Front Page"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 15), "Preview did not ask about today's class")
        XCTAssertTrue(application.staticTexts["Show Unit 9, Day 2 on the front page?"].firstMatch.exists)
        show.click()
        let webView: XCUIElement = application.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 90), "The preview did not start after Show on Front Page")
        let afterYes: String = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(afterYes.contains("![[Unit 9, Day 2]]"), afterYes)
        XCTAssertTrue(afterYes.contains("created: \(today)"), afterYes)
        application.buttons["stopPreviewButton"].firstMatch.click()
        XCTAssertTrue(application.buttons["previewButton"].waitForExistence(timeout: 15))

        // 2. The page moved back by hand → asked again → Not Today.
        try showingYesterday.write(to: indexURL, atomically: true, encoding: .utf8)
        application.buttons["previewButton"].firstMatch.click()
        let notToday: XCUIElement = application.windows.buttons["Not Now"].firstMatch
        XCTAssertTrue(notToday.waitForExistence(timeout: 15), "Preview did not ask the second time")
        notToday.click()
        XCTAssertTrue(application.webViews.firstMatch.waitForExistence(timeout: 90),
                      "The preview did not start after Not Today")
        XCTAssertEqual(try String(contentsOf: indexURL, encoding: .utf8), showingYesterday)
        let record: URL = fixtureURL.appendingPathComponent(
            "courses/EXC2O/.publish_state/section1.front-page-not-today.json"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.path), "Not Today was not remembered")
        application.buttons["stopPreviewButton"].firstMatch.click()
        XCTAssertTrue(application.buttons["previewButton"].waitForExistence(timeout: 15))

        // 3. Asked no more today: Preview goes straight to the preview.
        application.buttons["previewButton"].firstMatch.click()
        XCTAssertFalse(application.windows.buttons["Not Now"].firstMatch.waitForExistence(timeout: 4), "asked again after Not Today")
        XCTAssertTrue(application.webViews.firstMatch.waitForExistence(timeout: 90))
        application.buttons["stopPreviewButton"].firstMatch.click()
        application.terminate()
    }

    /// #899 U3c, Russell's ruling of 2026-11-20, night: Show on Front Page
    /// goes in while another program edits the page at the same instant (the
    /// app's debug-only `--ui-test-edit-races-the-swap`), so what the page
    /// held a moment before is kept in a hidden file beside it. ONE alert
    /// names that file, with one OK; never "The Front Page Was Not Changed";
    /// OK closes it and the preview starts.
    func testShowGoingInPartWayNamesTheKeptFileInOneAlert() throws {
        let fixtureURL: URL = try UITestFolders.makeFixture()
        let sectionURL: URL = fixtureURL.appendingPathComponent("courses/EXC2O/section1")
        let classesURL: URL = sectionURL.appendingPathComponent("All Classes")
        try FileManager.default.createDirectory(at: classesURL, withIntermediateDirectories: true)

        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let today: String = formatter.string(from: Date())
        let yesterday: String = formatter.string(from: Date().addingTimeInterval(-86_400))
        try TodaysClassOnTheFrontPageUITests.classPage("Unit 9, Day 1", on: yesterday)
            .write(to: classesURL.appendingPathComponent("Unit 9, Day 1.md"), atomically: true, encoding: .utf8)
        try TodaysClassOnTheFrontPageUITests.classPage("Unit 9, Day 2", on: today)
            .write(to: classesURL.appendingPathComponent("Unit 9, Day 2.md"), atomically: true, encoding: .utf8)
        let indexURL: URL = sectionURL.appendingPathComponent("index.md")
        let showingYesterday: String = "---\ntitle: Section 1\npublish: true\ncreated: \(yesterday)T07:00:00.000-0400\n---\n"
            + "# Most Recent Class\n\n![[Unit 9, Day 1]]\n"
        try showingYesterday.write(to: indexURL, atomically: true, encoding: .utf8)

        let publicURL: URL = fixtureURL.appendingPathComponent("courses/EXC2O/.merged_output/section1/public")
        stubPreviewPIDFileURL = try StubLaunchers.writeStubPreviewScript(in: fixtureURL, buildingInto: publicURL)

        let application: XCUIApplication = try IsolatedLaunch.launch(
            workspace: fixtureURL, extraArguments: ["--ui-test-edit-races-the-swap", "index.md"]
        ).application
        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        courseRow.click()
        application.typeKey(.rightArrow, modifierFlags: [])
        let sectionRow: XCUIElement = application.outlines.staticTexts["Section 1"]
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 10))
        sectionRow.click()

        application.buttons["previewButton"].firstMatch.click()
        let show: XCUIElement = application.windows.buttons["Show on Front Page"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 15), "Preview did not ask about today's class")
        show.click()

        // The one alert, naming the hidden file that is really on the disk.
        let title: XCUIElement = application.staticTexts["The front page now shows Unit 9, Day 2."].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15), "no alert naming what was kept")
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: sectionURL.path)
        var keptName: String? = nil
        for name in names where name.hasPrefix(".index.md.plantoir-undo-") && name.hasSuffix("-orig") {
            keptName = name
        }
        let kept: String = try XCTUnwrap(keptName, "no kept file beside the front page: \(names)")
        let keptText: String = try String(contentsOf: sectionURL.appendingPathComponent(kept), encoding: .utf8)
        XCTAssertTrue(keptText.contains("Edited in Obsidian as the change went in."), keptText)
        let message: String = "What the front page held a moment before is kept beside it, hidden, as “\(kept)”."
        XCTAssertTrue(application.staticTexts[message].firstMatch.exists, "the alert does not name \(kept)")
        XCTAssertFalse(application.staticTexts["The Front Page Was Not Changed"].firstMatch.exists)
        let afterYes: String = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(afterYes.contains("![[Unit 9, Day 2]]"), afterYes)

        // One button, OK; it closes the alert and the preview starts.
        // The alert is the sheet (or dialog) holding the title: its buttons
        // are exactly one, OK.
        var alertButtons: [String] = []
        for container in [application.sheets, application.dialogs] {
            let holding: XCUIElement = container.containing(.staticText, identifier: "The front page now shows Unit 9, Day 2.").firstMatch
            if holding.exists {
                for index in 0..<holding.buttons.count {
                    let button: XCUIElement = holding.buttons.element(boundBy: index)
                    alertButtons.append(button.title.isEmpty ? button.label : button.title)
                }
            }
        }
        XCTAssertEqual(alertButtons, ["OK"], "the alert's buttons")
        let ok: XCUIElement = application.buttons["OK"].firstMatch
        XCTAssertTrue(ok.exists, "the alert has no OK")
        ok.click()
        XCTAssertTrue(application.webViews.firstMatch.waitForExistence(timeout: 90), "The preview did not start after OK")
        XCTAssertFalse(title.exists)
        application.buttons["stopPreviewButton"].firstMatch.click()
        application.terminate()
    }

    // MARK: - Helpers

    private static func classPage(_ title: String, on day: String) -> String {
        return "---\ntitle: \(title)\npublish: true\ncreated: \(day)T07:00:00.000-0400\n---\n\n\(title)\n"
    }
}
