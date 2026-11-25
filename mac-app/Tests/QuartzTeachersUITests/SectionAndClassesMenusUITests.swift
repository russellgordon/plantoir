import AppKit
import XCTest

/// #990 (grouping A): the Section and Classes menus are drawn from
/// `SubjectMenuLayout` with `ForEach` inside `CommandMenu`, so this checks
/// in the running app that they still follow the window live, as the
/// hand-drawn menu did:
///
/// - with a COURSE row selected every Section and Classes item is drawn and
///   dimmed;
/// - with a SECTION row selected the Classes items come live, Preview is
///   live and Rebuild Preview is dimmed (no preview runs);
/// - while a preview runs, Section's first item reads Stop Preview and
///   Rebuild Preview is live; once it is stopped, Preview is back and
///   Rebuild Preview dims again;
/// - with a club selected the Classes menu is titled Meetings, and Classes
///   again on a course (#990, 2026-11-20 evening).
///
/// A synthetic course in the runner's own temporary folder, `--state-dir`
/// (IsolatedLaunch) and a STUB `preview.sh`: nothing is built and no
/// container is used. Opt-in (`PLANTOIR_UI_TESTS=1`): it needs the
/// foreground. Part of no gate, as the whole UI target is.
final class SectionAndClassesMenusUITests: XCTestCase {

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

    // MARK: - Helpers

    /// Opens a menu of the menu bar and returns its item with this title,
    /// once it is drawn.
    static func item(_ title: String, inMenu menu: String, of application: XCUIApplication) -> XCUIElement {
        let menuBarItem: XCUIElement = application.menuBars.menuBarItems[menu]
        menuBarItem.click()
        let found: XCUIElement = menuBarItem.menuItems[title]
        _ = found.waitForExistence(timeout: 5)
        return found
    }

    /// `contracts/shared-rules.json` → `subjectMenus.layout.itemTitles.items`
    /// (#1027), read rather than retyped.
    static func itemTitles() throws -> [String: [String: String]] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let menus: [String: Any] = try XCTUnwrap(all["subjectMenus"] as? [String: Any])
        let layout: [String: Any] = try XCTUnwrap(menus["layout"] as? [String: Any])
        let itemTitles: [String: Any] = try XCTUnwrap(layout["itemTitles"] as? [String: Any])
        return try XCTUnwrap(itemTitles["items"] as? [String: [String: String]])
    }

    /// With `PLANTOIR_UI_CAPTURE_DIR` set, a picture of the screen with the
    /// menu open, kept in the test's results as an attachment named
    /// `fileName` (the runner may not write outside its own folders), and the
    /// menu closed again.
    func captureIfAsked(menu: String, of application: XCUIApplication, named fileName: String) {
        guard let folder = ProcessInfo.processInfo.environment["PLANTOIR_UI_CAPTURE_DIR"], !folder.isEmpty else {
            return
        }
        application.menuBars.menuBarItems[menu].click()
        let attachment: XCTAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        application.typeKey(.escape, modifierFlags: [])
    }

    /// Whether the item is drawn and can be pressed, with the menu closed again.
    static func isLive(_ title: String, inMenu menu: String, of application: XCUIApplication) -> (drawn: Bool, live: Bool) {
        let found: XCUIElement = item(title, inMenu: menu, of: application)
        let answer: (drawn: Bool, live: Bool) = (found.exists, found.exists && found.isEnabled)
        application.typeKey(.escape, modifierFlags: [])
        return answer
    }

    // MARK: - Tests

    func testTheMenusFollowTheSelectionAndThePreviewLive() throws {
        guard ProcessInfo.processInfo.environment["PLANTOIR_UI_TESTS"] == "1" else {
            throw XCTSkip("Opt-in: set PLANTOIR_UI_TESTS=1. This drives the real app and needs the foreground.")
        }
        let fixtureURL: URL = try UITestFolders.makeFixture()
        let publicURL: URL = fixtureURL.appendingPathComponent("courses/EXC2O/.merged_output/section1/public")
        stubPreviewPIDFileURL = try StubLaunchers.writeStubPreviewScript(in: fixtureURL, buildingInto: publicURL)

        let launch: IsolatedLaunch = try IsolatedLaunch.launch(workspace: fixtureURL)
        let application: XCUIApplication = launch.application
        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        courseRow.click()

        // A course row: drawn, every one dimmed.
        for (menu, title) in [("Section", "Publish Pages…"), ("Section", "Remove Section"), ("Classes", "Add Class…"),
                              ("Classes", "Class Dates…"), ("Classes", "Get Ready for the Start of the Year…")] {
            let state: (drawn: Bool, live: Bool) = SectionAndClassesMenusUITests.isLive(title, inMenu: menu, of: application)
            XCTAssertTrue(state.drawn, "\(menu) ▸ \(title) is drawn on a course row")
            XCTAssertFalse(state.live, "\(menu) ▸ \(title) is dimmed on a course row")
        }

        // A section row: Classes comes live, Preview live, Rebuild dimmed.
        application.typeKey(.rightArrow, modifierFlags: [])
        let sectionRow: XCUIElement = application.outlines.staticTexts["Section 1"]
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 10))
        sectionRow.click()
        XCTAssertTrue(SectionAndClassesMenusUITests.isLive("Class Dates…", inMenu: "Classes", of: application).live,
                      "Classes ▸ Class Dates… comes live on a section row")
        XCTAssertTrue(SectionAndClassesMenusUITests.isLive("Add Class…", inMenu: "Classes", of: application).live)
        XCTAssertTrue(SectionAndClassesMenusUITests.isLive("Preview", inMenu: "Section", of: application).live)
        XCTAssertFalse(SectionAndClassesMenusUITests.isLive("Rebuild Preview", inMenu: "Section", of: application).live,
                       "Rebuild Preview is dimmed with no preview")

        // A preview running: Stop Preview, and Rebuild Preview live.
        application.buttons["previewButton"].firstMatch.click()
        XCTAssertTrue(application.webViews.firstMatch.waitForExistence(timeout: 90), "The preview did not start")
        sectionRow.click()
        let stop: (drawn: Bool, live: Bool) = SectionAndClassesMenusUITests.isLive("Stop Preview", inMenu: "Section", of: application)
        XCTAssertTrue(stop.drawn && stop.live, "Section ▸ Stop Preview while a preview runs")
        XCTAssertFalse(SectionAndClassesMenusUITests.isLive("Preview", inMenu: "Section", of: application).drawn,
                       "no Preview item while one runs")
        XCTAssertTrue(SectionAndClassesMenusUITests.isLive("Rebuild Preview", inMenu: "Section", of: application).live,
                      "Rebuild Preview comes live while a preview runs")

        // Stopped from the menu: Preview again, Rebuild dimmed again. The
        // window's own button turns back into Preview when the preview has
        // stopped (its identifier follows the same running state the menu
        // reads), so the test waits on that element, then opens the menu once.
        SectionAndClassesMenusUITests.item("Stop Preview", inMenu: "Section", of: application).click()
        XCTAssertTrue(application.buttons["previewButton"].firstMatch.waitForExistence(timeout: 30),
                      "the window's Preview button is back once the preview stopped")
        XCTAssertTrue(SectionAndClassesMenusUITests.isLive("Preview", inMenu: "Section", of: application).live,
                      "Section ▸ Preview is back once the preview stopped")
        XCTAssertFalse(SectionAndClassesMenusUITests.isLive("Rebuild Preview", inMenu: "Section", of: application).live,
                       "Rebuild Preview dims again once the preview stopped")
        application.terminate()
    }

    /// Russell's ruling on #990 (2026-11-20 evening): "in a club the menu
    /// itself is titled Meetings, on both platforms, so no sentence a club's
    /// teacher reads says 'class'." The title follows the selected course
    /// live (`subjectMenus.layout.titleForAMeeting`): a course reads Classes,
    /// a club (its pages called meetings) reads Meetings with the same items,
    /// and back. MUST FAIL with the menu titled by an ordinary course's noun
    /// whatever is selected.
    func testTheClassesMenuIsTitledMeetingsWhileAClubIsSelected() throws {
        guard ProcessInfo.processInfo.environment["PLANTOIR_UI_TESTS"] == "1" else {
            throw XCTSkip("Opt-in: set PLANTOIR_UI_TESTS=1. This drives the real app and needs the foreground.")
        }
        let fixtureURL: URL = try UITestFolders.makeFixture()
        try SectionAndClassesMenusUITests.addAClub(named: "CODING", besideTheExampleCourseIn: fixtureURL)

        let launch: IsolatedLaunch = try IsolatedLaunch.launch(workspace: fixtureURL)
        let application: XCUIApplication = launch.application
        let menuBar: XCUIElement = application.menuBars.firstMatch
        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        let clubRow: XCUIElement = application.outlines.staticTexts["CODING"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        XCTAssertTrue(clubRow.waitForExistence(timeout: 10))

        courseRow.click()
        XCTAssertTrue(menuBar.menuBarItems["Classes"].waitForExistence(timeout: 5), "a course's menu bar reads Classes")
        XCTAssertFalse(menuBar.menuBarItems["Meetings"].exists, "no Meetings menu for a course")

        clubRow.click()
        XCTAssertTrue(menuBar.menuBarItems["Meetings"].waitForExistence(timeout: 5), "a club's menu bar reads Meetings")
        XCTAssertTrue(menuBar.menuBarItems["Classes"].waitForNonExistence(timeout: 5), "no Classes menu while a club is selected")
        // #1027: its items say meeting (`subjectMenus.layout.itemTitles`),
        // each where the course has its class twin, and none says class.
        // MUST FAIL with an item's title read in an ordinary course's noun.
        for (name, titles) in try SectionAndClassesMenusUITests.itemTitles() {
            let menu: String = name == "publishClassForADate" ? "Section" : "Meetings"
            let meetingTitle: String = try XCTUnwrap(titles["titleForAMeeting"])
            XCTAssertTrue(
                SectionAndClassesMenusUITests.isLive(meetingTitle, inMenu: menu, of: application).drawn,
                "\(menu) does not hold \(meetingTitle) in a club"
            )
            XCTAssertFalse(
                SectionAndClassesMenusUITests.isLive(try XCTUnwrap(titles["title"]), inMenu: menu, of: application).drawn,
                "\(menu) still holds \(titles["title"] ?? "") in a club"
            )
        }
        captureIfAsked(menu: "Meetings", of: application, named: "mac-meetings-menu.png")

        courseRow.click()
        XCTAssertTrue(menuBar.menuBarItems["Classes"].waitForExistence(timeout: 5), "back to Classes on a course")
        XCTAssertTrue(menuBar.menuBarItems["Meetings"].waitForNonExistence(timeout: 5))
        application.terminate()
    }

    /// A club beside the Example Course: its copy, coded `code` (a code with
    /// no grade digit, as a club's is), whose class pages are called
    /// meetings (`class_noun`).
    static func addAClub(named code: String, besideTheExampleCourseIn fixtureURL: URL) throws {
        let coursesURL: URL = fixtureURL.appendingPathComponent("courses")
        let clubURL: URL = coursesURL.appendingPathComponent(code)
        try FileManager.default.copyItem(at: coursesURL.appendingPathComponent("EXC2O"), to: clubURL)
        let configURL: URL = clubURL.appendingPathComponent("course_config.json")
        let read: Any = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL))
        var configuration: [String: Any] = try XCTUnwrap(read as? [String: Any], "the fixture's course_config.json")
        configuration["course_code"] = code
        configuration["course_name"] = "Coding Club"
        configuration["class_noun"] = "meeting"
        let written: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
        try written.write(to: configURL)
    }
}
