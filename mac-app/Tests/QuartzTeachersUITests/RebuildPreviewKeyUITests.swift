import AppKit
import XCTest

/// #990: Rebuild Preview is ⇧⌘Y, as Russell ruled on 2026-11-18, although a
/// stock Mac's Services menu gives ⇧⌘Y to Stickies' "Make Sticky" service
/// (Stickies' own `NSServices` entry, key `Y`, send types plain text, RTF
/// and flat RTFD, so it is offered only while text is selected). Apple's
/// Services Implementation Guide: "When an application already has a
/// shortcut with that key equivalent, the application's shortcut wins."
/// That was measured once, with the page's text selected, on 2026-11-19
/// (documentation 09, "Rebuild Preview's ⇧⌘Y beside the Stickies service").
///
/// What this test holds, from the second review on: a real ⇧⌘Y runs
/// Section ▸ Rebuild Preview (its "ran from a menu" line on the trail is the
/// proof the menu item ran). It presses the key with NOTHING selected, and
/// checks first that Plantoir ▸ Services offers no live Stickies item, so
/// even if the key ever regresses, the failing path cannot make a sticky
/// note: the service is not offered for a selection that holds no text. A
/// note made by the key could not be removed safely afterwards, because
/// this sandboxed runner cannot read or change Stickies' container, and a
/// note must never be picked out from the teacher's own by guessing.
///
/// A synthetic course in the runner's own temporary folder, `--state-dir`
/// (IsolatedLaunch) and a STUB `preview.sh`: nothing is built, and no
/// container is used. It skips while Stickies is running, and if Stickies
/// starts during the test anyway, the test FAILS and says to quit it by hand
/// (the sandboxed runner never quits another app). Opt-in (`PLANTOIR_UI_TESTS=1`): it needs the foreground. Part of
/// no gate, as the whole UI target is.
final class RebuildPreviewKeyUITests: XCTestCase {

    // MARK: - Stored properties

    private var stubPreviewPIDFileURL: URL?

    /// Whether Stickies was running just before the key was pressed; nil
    /// until then. A copy that was not running before and is running after
    /// fails the test; the test never quits it.
    private var stickiesWasRunningBeforeTheKey: Bool?

    static let stickiesBundleIdentifier: String = "com.apple.Stickies"

    // MARK: - Set up and tear down

    override func tearDown() {
        if let pidFileURL = stubPreviewPIDFileURL {
            StubLaunchers.reap(pidFileURL: pidFileURL, expectingNamePrefix: "python")
        }
        stubPreviewPIDFileURL = nil
        if stickiesWasRunningBeforeTheKey == false && RebuildPreviewKeyUITests.stickiesIsRunning() {
            // The runner is sandboxed and cannot quit another app, so the
            // test never tries: it says so and leaves Stickies alone.
            XCTFail("Stickies started during the test and is still running; quit it by hand; no note was made because nothing was selected")
        }
        stickiesWasRunningBeforeTheKey = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testShiftCommandYRebuildsThePreviewAndMakesNoStickyNote() throws {
        guard ProcessInfo.processInfo.environment["PLANTOIR_UI_TESTS"] == "1" else {
            throw XCTSkip("Opt-in: set PLANTOIR_UI_TESTS=1. This drives the real app and needs the foreground.")
        }
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

        // The sidebar's row, not the page, takes the key: an outline row
        // selection holds no text, so Stickies' service has nothing to take.
        sectionRow.click()

        // Plantoir ▸ Services offers no live Stickies item at the moment the
        // key is pressed, so a regressed key could not make a note.
        let appMenu: XCUIElement = application.menuBars.menuBarItems["Plantoir"]
        appMenu.click()
        let services: XCUIElement = appMenu.menuItems["Services"]
        XCTAssertTrue(services.waitForExistence(timeout: 5))
        services.hover()
        // The submenu always ends with Services Settings…, so once any item
        // is drawn the submenu is there to be read.
        XCTAssertTrue(services.menuItems.firstMatch.waitForExistence(timeout: 5), "the Services submenu opened")
        // "Make Sticky" in Stickies' Info.plist, "Make New Sticky Note" as
        // System Settings lists it: matched by the word both share.
        let stickyItems: XCUIElementQuery = services.menuItems.matching(
            NSPredicate(format: "title CONTAINS[c] %@", "sticky")
        )
        var liveStickyItems: Int = 0
        var index: Int = 0
        while index < stickyItems.count {
            if stickyItems.element(boundBy: index).isEnabled {
                liveStickyItems += 1
            }
            index += 1
        }
        application.typeKey(.escape, modifierFlags: [])
        application.typeKey(.escape, modifierFlags: [])
        guard liveStickyItems == 0 else {
            XCTFail("Stickies' service is live, so the key is not pressed: a regressed key would make a note")
            application.terminate()
            return
        }

        stickiesWasRunningBeforeTheKey = RebuildPreviewKeyUITests.stickiesIsRunning()
        if stickiesWasRunningBeforeTheKey == true {
            application.terminate()
            throw XCTSkip("Stickies started before the key was pressed, by something else")
        }
        let linesBefore: Int = launch.trailLines().count
        application.typeKey("y", modifierFlags: [.command, .shift])

        var rebuildLine: String? = nil
        let deadline: Date = Date().addingTimeInterval(60)
        while rebuildLine == nil && Date() < deadline {
            let lines: [String] = launch.trailLines()
            var lineIndex: Int = linesBefore
            while lineIndex < lines.count {
                if lines[lineIndex].contains("Section ▸ Rebuild Preview") {
                    rebuildLine = lines[lineIndex]
                }
                lineIndex += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertNotNil(rebuildLine, "⇧⌘Y ran Section ▸ Rebuild Preview")
        print("RebuildPreviewKeyUITests trail: \(rebuildLine ?? "none")")

        // Stickies would start at once if anything handed it the key; it is
        // given five seconds to appear, on purpose, as the window of
        // observation.
        let watchEnds: Date = Date().addingTimeInterval(5)
        var stickiesStarted: Bool = false
        while !stickiesStarted && Date() < watchEnds {
            stickiesStarted = RebuildPreviewKeyUITests.stickiesIsRunning()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertFalse(stickiesStarted, "⇧⌘Y started Stickies")

        let stopButton: XCUIElement = application.buttons["stopPreviewButton"].firstMatch
        if stopButton.exists {
            stopButton.click()
        }
        application.terminate()
    }

    // MARK: - Helpers

    static func stickiesIsRunning() -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: stickiesBundleIdentifier).isEmpty
    }
}
