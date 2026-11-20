import AppKit
import XCTest

/// #990: Rebuild Preview is ⇧⌘Y, as Russell ruled on 2026-11-18, although a
/// stock Mac's Services menu gives ⇧⌘Y to Stickies' "Make Sticky" service
/// (Stickies' own `NSServices` entry, key `Y`, which needs selected text).
/// Apple's Services Implementation Guide: "When an application already has
/// a shortcut with that key equivalent, the application's shortcut wins."
/// This test is the measurement that sentence is true for Plantoir: with
/// a preview running and the page's text SELECTED, so the service is live
/// in the Services menu, a real ⇧⌘Y runs Rebuild Preview (its "ran from a
/// menu" line on the trail) and Stickies is not started.
///
/// A synthetic course in the runner's own temporary folder, `--state-dir`
/// (IsolatedLaunch) and a STUB `preview.sh`: nothing is built, and no
/// container is used. It skips, saying so, when Stickies is already
/// running, because then a new note could not be told from the teacher's
/// own. Part of no gate, as the whole UI target is.
final class RebuildPreviewKeyUITests: XCTestCase {

    // MARK: - Stored properties

    private var stubPreviewPIDFileURL: URL?

    static let stickiesBundleIdentifier: String = "com.apple.Stickies"

    // MARK: - Set up and tear down

    override func tearDown() {
        if let pidFileURL = stubPreviewPIDFileURL {
            StubLaunchers.reap(pidFileURL: pidFileURL, expectingNamePrefix: "python")
        }
        stubPreviewPIDFileURL = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testShiftCommandYRebuildsThePreviewAndMakesNoStickyNote() throws {
        if RebuildPreviewKeyUITests.stickiesIsRunning() {
            throw XCTSkip("Stickies is already running, so a note made by the key could not be told from the teacher's own")
        }

        let fixtureURL: URL = try UITestFolders.makeFixture()
        let publicURL: URL = fixtureURL.appendingPathComponent("courses/EXC2O/.merged_output/section1/public")
        stubPreviewPIDFileURL = try StubLaunchers.writeStubPreviewScript(in: fixtureURL, buildingInto: publicURL)

        let launch: IsolatedLaunch = try IsolatedLaunch.launch(workspace: fixtureURL)
        let application: XCUIApplication = launch.application
        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 10))
        courseRow.click()
        application.typeKey(.rightArrow, modifierFlags: [])
        let sectionRow: XCUIElement = application.outlines.staticTexts["Section 1"]
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 10))
        sectionRow.click()

        application.buttons["previewButton"].firstMatch.click()
        let webView: XCUIElement = application.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 90), "The preview did not start")

        // The page's text selected, so Stickies' service has something to
        // take: without a selection the service is not live at all, and the
        // key would prove nothing.
        webView.click()
        application.typeKey("a", modifierFlags: [.command])

        // Plantoir ▸ Services offers Stickies' item, live, at the moment
        // the key is pressed.
        let appMenu: XCUIElement = application.menuBars.menuBarItems["Plantoir"]
        appMenu.click()
        let services: XCUIElement = appMenu.menuItems["Services"]
        XCTAssertTrue(services.waitForExistence(timeout: 5))
        services.hover()
        // "Make Sticky" in Stickies' Info.plist, "Make New Sticky Note" as
        // System Settings lists it: matched by the word both share.
        let makeSticky: XCUIElement = services.menuItems.matching(
            NSPredicate(format: "title CONTAINS[c] %@", "sticky")
        ).firstMatch
        XCTAssertTrue(makeSticky.waitForExistence(timeout: 5), "Stickies' service is in the Services menu")
        XCTAssertTrue(makeSticky.isEnabled, "and live, with the page's text selected")
        application.typeKey(.escape, modifierFlags: [])
        application.typeKey(.escape, modifierFlags: [])

        let linesBefore: Int = launch.trailLines().count
        application.typeKey("y", modifierFlags: [.command, .shift])

        var rebuildLine: String? = nil
        let deadline: Date = Date().addingTimeInterval(60)
        while rebuildLine == nil && Date() < deadline {
            let lines: [String] = launch.trailLines()
            var index: Int = linesBefore
            while index < lines.count {
                if lines[index].contains("Section ▸ Rebuild Preview") {
                    rebuildLine = lines[index]
                }
                index += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertNotNil(rebuildLine, "⇧⌘Y ran Section ▸ Rebuild Preview")
        print("RebuildPreviewKeyUITests trail: \(rebuildLine ?? "none")")

        // The service would start Stickies at once; it is given five seconds
        // to appear, on purpose, as the window of observation.
        let watchEnds: Date = Date().addingTimeInterval(5)
        var stickiesStarted: Bool = false
        while !stickiesStarted && Date() < watchEnds {
            stickiesStarted = RebuildPreviewKeyUITests.stickiesIsRunning()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertFalse(stickiesStarted, "⇧⌘Y started Stickies: the service took the key")

        application.buttons["stopPreviewButton"].firstMatch.click()
        application.terminate()
    }

    // MARK: - Helpers

    static func stickiesIsRunning() -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: stickiesBundleIdentifier).isEmpty
    }
}
