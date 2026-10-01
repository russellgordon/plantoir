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
        let fixtureURL: URL = try FixtureWorkspace.materialize()
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
        let notToday: XCUIElement = application.windows.buttons["Not Today"].firstMatch
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
        XCTAssertFalse(application.windows.buttons["Not Today"].firstMatch.waitForExistence(timeout: 4), "asked again after Not Today")
        XCTAssertTrue(application.webViews.firstMatch.waitForExistence(timeout: 90))
        application.buttons["stopPreviewButton"].firstMatch.click()
        application.terminate()
    }

    // MARK: - Helpers

    private static func classPage(_ title: String, on day: String) -> String {
        return "---\ntitle: \(title)\npublish: true\ncreated: \(day)T07:00:00.000-0400\n---\n\n\(title)\n"
    }
}
