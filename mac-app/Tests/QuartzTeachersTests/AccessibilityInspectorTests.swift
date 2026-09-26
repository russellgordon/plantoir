import AppKit
import XCTest
@testable import QuartzTeachers

/// When a test that reads the real window through the accessibility tree
/// skips, and — the half that matters more — when it must NOT (#249, #315).
final class AccessibilityInspectorTests: XCTestCase {

    // MARK: - Stored properties

    /// Every #249 test runs in an unlocked session on the console, so their
    /// meaning is exactly what it was before the session was read.
    let unlocked: AccessibilityInspector.SessionFacts = AccessibilityInspector.SessionFacts.unlockedOnTheConsole
    let locked: AccessibilityInspector.SessionFacts = AccessibilityInspector.SessionFacts(isScreenLocked: true, isOnTheConsole: true)
    let switchedAway: AccessibilityInspector.SessionFacts = AccessibilityInspector.SessionFacts(isScreenLocked: false, isOnTheConsole: false)
    let lockedAndSwitchedAway: AccessibilityInspector.SessionFacts = AccessibilityInspector.SessionFacts(isScreenLocked: true, isOnTheConsole: false)

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
        XCTAssertNotNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false, session: unlocked))
    }

    func testAnotherWindowOnTheShowingSpaceDoesNotHideThatTheTestsWindowIsNot() {
        // The assistant or Settings sitting on the showing desktop says
        // nothing about the window the test reads.
        let windows: [AccessibilityInspector.WindowFacts] = [
            facts(tests: false, visible: true, showing: true),
            facts(tests: true, visible: true, showing: false),
        ]
        XCTAssertNotNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false, session: unlocked))
    }

    func testAWindowInTheTreeIsRead() {
        let showing: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: true)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: showing, testsWindowIsInTheTree: true, session: unlocked))
        let notShowing: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: false)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: notShowing, testsWindowIsInTheTree: true, session: unlocked))
    }

    func testAWindowMissingFromTheTreeOnTheShowingSpaceStillFails() {
        let alone: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: true)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: alone, testsWindowIsInTheTree: false, session: unlocked))
        let besideAnOffSpaceWindow: [AccessibilityInspector.WindowFacts] = [
            facts(tests: true, visible: true, showing: true),
            facts(tests: false, visible: true, showing: false),
        ]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: besideAnOffSpaceWindow, testsWindowIsInTheTree: false, session: unlocked))
    }

    func testTheTestsWindowGoneWhileAnotherSitsOffSpaceStillFails() {
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: false, visible: true, showing: false)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false, session: unlocked))
    }

    func testNoWindowAtAllStillFails() {
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: [], testsWindowIsInTheTree: false, session: unlocked))
    }

    func testAHiddenTestWindowStillFails() {
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: false, showing: false)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false, session: unlocked))
    }

    func testTheReasonNamesTheSpace() {
        // Test-internal wording, not a sentence a teacher reads.
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: false)]
        let reason: String = AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false, session: unlocked) ?? ""
        XCTAssertTrue(reason.contains("Space"), "The skip must say why, so an extra skip in the totals can be read")
    }

    // #315: a locked screen, and another account on the screen.

    func testALockedScreenIsSkippedWithAReason() {
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: true)]
        let reason: String? = AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false, session: locked)
        XCTAssertNotNil(reason)
        XCTAssertTrue((reason ?? "").contains("locked"), "The skip must name the lock")
        XCTAssertTrue((reason ?? "").contains("#315"))
        XCTAssertFalse((reason ?? "").contains("Space"), "A lock is not a Space problem")
    }

    func testASessionSwitchedAwayIsSkippedWithAReason() {
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: true)]
        let reason: String? = AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false, session: switchedAway)
        XCTAssertNotNil(reason)
        XCTAssertTrue((reason ?? "").contains("#315"))
        XCTAssertFalse((reason ?? "").contains("Space"), "Another account on the screen is not a Space problem")
    }

    func testAReadableWindowIsReadEvenOnALockedScreen() {
        // The session can only EXPLAIN a missing window, never cause a skip
        // while the window can be read.
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: true, showing: true)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: true, session: lockedAndSwitchedAway))
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: true, session: locked))
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: true, session: switchedAway))
    }

    func testTheTestsWindowGoneOnALockedScreenStillFails() {
        let onlyAnother: [AccessibilityInspector.WindowFacts] = [facts(tests: false, visible: true, showing: true)]
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: onlyAnother, testsWindowIsInTheTree: false, session: locked))
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: [], testsWindowIsInTheTree: false, session: locked))
        XCTAssertNil(AccessibilityInspector.reasonTheWindowCannotBeRead(windows: [], testsWindowIsInTheTree: false, session: switchedAway))
    }

    func testAHiddenWindowOnALockedScreenIsSkipped() {
        // Pins the order: the session is asked before the window's
        // visibility, which is not what a skip on a locked screen rests on.
        let windows: [AccessibilityInspector.WindowFacts] = [facts(tests: true, visible: false, showing: false)]
        let reason: String? = AccessibilityInspector.reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: false, session: locked)
        XCTAssertNotNil(reason)
        XCTAssertTrue((reason ?? "").contains("#315"))
    }

    func testTheLockKeyIsRead() {
        // The key is spelled out here rather than read from the constant,
        // so a misspelt constant fails.
        let lockedBool: AccessibilityInspector.SessionFacts = AccessibilityInspector.sessionFacts(from: ["CGSSessionScreenIsLocked": true])
        XCTAssertTrue(lockedBool.isScreenLocked)
        let lockedNumber: AccessibilityInspector.SessionFacts = AccessibilityInspector.sessionFacts(from: ["CGSSessionScreenIsLocked": NSNumber(value: 1)])
        XCTAssertTrue(lockedNumber.isScreenLocked)
        let unlockedBool: AccessibilityInspector.SessionFacts = AccessibilityInspector.sessionFacts(from: ["CGSSessionScreenIsLocked": false])
        XCTAssertFalse(unlockedBool.isScreenLocked)
        XCTAssertTrue(lockedBool.isOnTheConsole, "A lock alone says nothing about the console")
    }

    func testTheConsoleKeyIsRead() {
        let offNumber: AccessibilityInspector.SessionFacts = AccessibilityInspector.sessionFacts(from: ["kCGSSessionOnConsoleKey": 0])
        XCTAssertFalse(offNumber.isOnTheConsole)
        let onNumber: AccessibilityInspector.SessionFacts = AccessibilityInspector.sessionFacts(from: ["kCGSSessionOnConsoleKey": 1])
        XCTAssertTrue(onNumber.isOnTheConsole)
        let offBool: AccessibilityInspector.SessionFacts = AccessibilityInspector.sessionFacts(from: ["kCGSSessionOnConsoleKey": false])
        XCTAssertFalse(offBool.isOnTheConsole)
        XCTAssertFalse(offBool.isScreenLocked, "Measured: a switched-away session carries no lock key")
    }

    func testAnUnknownSessionNeverSkips() {
        let noDictionary: AccessibilityInspector.SessionFacts = AccessibilityInspector.sessionFacts(from: nil)
        XCTAssertFalse(noDictionary.isScreenLocked)
        XCTAssertTrue(noDictionary.isOnTheConsole)
        let emptyDictionary: AccessibilityInspector.SessionFacts = AccessibilityInspector.sessionFacts(from: [:])
        XCTAssertFalse(emptyDictionary.isScreenLocked)
        XCTAssertTrue(emptyDictionary.isOnTheConsole)
    }

    /// The live half of #315: while the tree can read the test's window,
    /// the session really does read as unlocked and on the console — so a
    /// reader stuck on "locked" cannot hide behind the tree check.
    @MainActor
    func testTheLiveSessionReadsUnlockedWhenTheWindowIsReadable() async throws {
        guard let workspace = WorkspaceModel.windowModels.first else {
            throw XCTSkip("The interface is not on screen in this run")
        }
        guard let window = workspace.window else {
            XCTFail("The window model does not know its window, so the session check cannot be compared with it")
            return
        }
        if !AccessibilityInspector.treeHoldsWindow(matching: window) {
            throw XCTSkip("The accessibility tree cannot see the test window in this run (screen locked, another account on the screen, or another Space showing), so there is no readable window to compare the session with (#315)")
        }
        let session: AccessibilityInspector.SessionFacts = AccessibilityInspector.currentSessionFacts()
        XCTAssertFalse(session.isScreenLocked, "The tree reads the window, so the screen cannot be locked")
        XCTAssertTrue(session.isOnTheConsole, "The tree reads the window, so this session owns the screen")
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
