import AppKit
import XCTest
@testable import QuartzTeachers

/// When a test that reads the real window through the accessibility tree
/// skips, and — the half that matters more — when it must NOT (#249).
final class AccessibilityInspectorTests: XCTestCase {

    // MARK: - Functions

    func facts(tests: Bool, visible: Bool, showing: Bool) -> AccessibilityInspector.WindowFacts {
        return AccessibilityInspector.WindowFacts(
            isTheTestsWindow: tests,
            isVisible: visible,
            isOnTheShowingSpace: showing
        )
    }

    func testAWindowOnAnotherSpaceIsSkippedWithAReason() {
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: false)]
        XCTAssertNotNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false))
    }

    func testAnotherWindowOnTheShowingSpaceDoesNotHideThatTheTestsWindowIsNot() {
        // The assistant or Settings sitting on the showing desktop says
        // nothing about the window the test reads.
        let windows: [AccessibilityInspector.WindowFacts] = [
            facts(tests: false, visible: true, showing: true),
            facts(tests: true, visible: true, showing: false),
        ]
        XCTAssertNotNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false))
    }

    func testAWindowInTheTreeIsRead() {
        let showing: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: true)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: showing, testsWindowIsInTheTree: true))
        let notShowing: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: false)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: notShowing, testsWindowIsInTheTree: true))
    }

    func testAWindowMissingFromTheTreeOnTheShowingSpaceStillFails() {
        let alone: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: true)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: alone, testsWindowIsInTheTree: false))
        let besideAnOffSpaceWindow: [AccessibilityInspector.WindowFacts] = [
            facts(tests: true, visible: true, showing: true),
            facts(tests: false, visible: true, showing: false),
        ]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: besideAnOffSpaceWindow, testsWindowIsInTheTree: false))
    }

    func testTheTestsWindowGoneWhileAnotherSitsOffSpaceStillFails() {
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: false, visible: true, showing: false)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false))
    }

    func testNoWindowAtAllStillFails() {
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: [], testsWindowIsInTheTree: false))
    }

    func testAHiddenTestWindowStillFails() {
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: false, showing: false)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false))
    }

    func testTheReasonNamesTheSpace() {
        // Test-internal wording, not a sentence a teacher reads.
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: false)]
        let reason: String = AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false) ?? ""
        XCTAssertTrue(reason.contains("Space"), "The skip must say why, so an extra skip in the totals can be read")
    }

    /// The live half: on the showing desktop the tree really does list the
    /// test's window, so the frame match the skip relies on is not dead code.
    @MainActor
    func testTheTestsWindowIsFoundInTheTreeWhenItIsShowing() async throws {
        guard let workspace = WorkspaceModel.windowModels.first else {
            throw XCTSkip("The interface is not on screen in this run")
        }
        guard let window = workspace.window else {
            XCTFail("The window model does not know its window, so the Space check cannot work")
            return
        }
        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(window)
        if !window.isOnActiveSpace {
            throw XCTSkip("The test window is not on the showing Space")
        }
        XCTAssertTrue(AccessibilityInspector.treeHoldsWindow(matching: window),
                      "The accessibility tree should list the test's own window by its frame")
    }
}
