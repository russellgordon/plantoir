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
///   Rebuild Preview dims again.
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

        // Stopped from the menu: Preview again, Rebuild dimmed again.
        SectionAndClassesMenusUITests.item("Stop Preview", inMenu: "Section", of: application).click()
        var previewIsBack: Bool = false
        let deadline: Date = Date().addingTimeInterval(30)
        while !previewIsBack && Date() < deadline {
            previewIsBack = SectionAndClassesMenusUITests.isLive("Preview", inMenu: "Section", of: application).live
            if !previewIsBack {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }
        XCTAssertTrue(previewIsBack, "Section ▸ Preview is back once the preview stopped")
        XCTAssertFalse(SectionAndClassesMenusUITests.isLive("Rebuild Preview", inMenu: "Section", of: application).live,
                       "Rebuild Preview dims again once the preview stopped")
        application.terminate()
    }
}
