import AppKit
import CoreGraphics
import XCTest
@testable import QuartzTeachers

/// The unit suite's host puts nothing on any display, has no Dock tile and no
/// menu bar of its own, and stays out of a teacher's Plantoir and of the app a
/// UI test drives (#633). Every live test here was red on the old code: the
/// main window sat on a display, its sheets and alerts landed there too, and
/// the host was a regular app.
///
/// Placement is checked twice — by AppKit's frame and by the WINDOW SERVER's
/// bounds against `CGDisplayBounds` — because the window server is what the
/// person at the Mac sees. These tests never call the installer: a second
/// install would replace the chain `SheetsHungOffScreenStayThere` builds on
/// top of it.
@MainActor
final class UnitTestHostWindowsTests: XCTestCase {

    // MARK: - Stored properties

    /// Three displays, one of them left of and below the main one, so the
    /// formula has negative origins to get beyond.
    let fakeDisplays: [NSRect] = [
        NSRect(x: 0, y: 0, width: 1512, height: 982),
        NSRect(x: 1512, y: -98, width: 1920, height: 1080),
        NSRect(x: -1920, y: -300, width: 1920, height: 1080),
    ]

    // MARK: - Functions

    /// The test host's main window, or a skip when this session has none
    /// (a hidden or locked session, #315), as `AppKitBookkeepingGuardTests`
    /// does.
    func mainWindow() throws -> NSWindow {
        var found: NSWindow? = nil
        for window in NSApp.windows where window.frameAutosaveName.hasPrefix("main-AppWindow") {
            found = window
        }
        guard let window = found else {
            throw XCTSkip("No main window in this host (a hidden or locked session, #315), so there is nothing to place.")
        }
        return window
    }

    /// Where the window server has `window`, in its own coordinates.
    func serverBounds(of window: NSWindow) -> CGRect? {
        let windowID: CGWindowID = CGWindowID(window.windowNumber)
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]] else {
            return nil
        }
        guard let first = list.first,
              let boundsDictionary = first[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
    }

    /// Whether `bounds`, in the window server's coordinates, overlaps any
    /// active display.
    func overlapsAnActiveDisplay(_ bounds: CGRect) -> Bool {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays: [CGDirectDisplayID] = Array(repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        for display in displays where CGDisplayBounds(display).intersects(bounds) {
            return true
        }
        return false
    }

    /// Fails unless `window` is off every display, as AppKit AND the window
    /// server see it.
    func assertOffEveryDisplay(_ window: NSWindow, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertFalse(TableHost.isOnAScreen(window.frame),
                       "\(what) overlaps a display: \(NSStringFromRect(window.frame))", file: file, line: line)
        let bounds: CGRect = try XCTUnwrap(serverBounds(of: window), "the window server knows \(what)", file: file, line: line)
        XCTAssertFalse(overlapsAnActiveDisplay(bounds),
                       "the window server has \(what) on a display: \(bounds)", file: file, line: line)
    }

    func settle(seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: - Tests: the live host

    func testTheHostIsAnAccessoryWithNoDockTileOrMenuBar() {
        XCTAssertTrue(UnitTestHostWindows.isInstalled, "the app installs the placement at launch inside the unit host")
        XCTAssertEqual(NSApp.activationPolicy(), NSApplication.ActivationPolicy.accessory)
    }

    func testTheMainWindowIsOrderedInButOffEveryDisplay() throws {
        let window: NSWindow = try mainWindow()
        XCTAssertTrue(window.isVisible, "the window is still ordered in, so the tests that read it can")
        XCTAssertNil(window.screen, "AppKit puts the window on no screen")
        try assertOffEveryDisplay(window, "the main window")
    }

    func testASheetAndAnAlertOnTheMainWindowStayOffAndTheWindowStaysPut() async throws {
        let window: NSWindow = try mainWindow()
        let originBefore: NSPoint = window.frame.origin

        let sheet: NSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.beginSheet(sheet, completionHandler: nil)
        await settle(seconds: 0.5)
        try assertOffEveryDisplay(sheet, "a sheet on the main window")
        try assertOffEveryDisplay(window, "the main window with a sheet up")
        window.endSheet(sheet)
        sheet.orderOut(nil)
        await settle(seconds: 0.3)

        let alert: NSAlert = NSAlert()
        alert.messageText = "A placement check"
        alert.beginSheetModal(for: window, completionHandler: nil)
        await settle(seconds: 0.5)
        try assertOffEveryDisplay(alert.window, "an alert on the main window")
        window.endSheet(alert.window)
        await settle(seconds: 0.3)

        // Pinned, not merely kept off: AppKit's sheet helper moves the parent
        // after a sheet, and a window that drifts is still off every display,
        // so only its origin shows the difference (measured: -5920 to -24070
        // over 23 classes without the pin).
        XCTAssertEqual(window.frame.origin, originBefore, "the main window stays where it was after a sheet and an alert")
    }

    // MARK: - Tests: the decisions

    func testOnlyTheUnitTestHostIsQuieted() {
        var count: Int = 0
        for insideTestBundle in [false, true] {
            for underUITest in [false, true] {
                for stateDirectory in [false, true] {
                    let quiet: Bool = UnitTestHostWindows.quietsThisProcess(
                        isInsideTestBundle: insideTestBundle,
                        isUnderUITest: underUITest,
                        hasStateDirectory: stateDirectory
                    )
                    XCTAssertEqual(quiet, insideTestBundle,
                                   "test bundle \(insideTestBundle), UI test \(underUITest), state folder \(stateDirectory)")
                    count += 1
                }
            }
        }
        XCTAssertEqual(count, 8)
    }

    func testATeacherAUITestedAppAndACaptureAreLeftAlone() {
        XCTAssertFalse(UnitTestHostWindows.quietsThisProcess(isInsideTestBundle: false, isUnderUITest: false, hasStateDirectory: false),
                       "a teacher's Plantoir")
        XCTAssertFalse(UnitTestHostWindows.quietsThisProcess(isInsideTestBundle: false, isUnderUITest: false, hasStateDirectory: true),
                       "the app a UI test launches with --state-dir")
        XCTAssertFalse(UnitTestHostWindows.quietsThisProcess(isInsideTestBundle: false, isUnderUITest: true, hasStateDirectory: false),
                       "a marketing capture (UITEST_WORKSPACE)")
        XCTAssertFalse(UnitTestHostWindows.quietsThisProcess(isInsideTestBundle: false, isUnderUITest: true, hasStateDirectory: true),
                       "a UI test that also names a workspace")
    }

    func testTheOffScreenOriginIsBeyondEveryDisplayIncludingNegativeOnes() {
        let size: NSSize = NSSize(width: 1000, height: 800)
        let origin: NSPoint = UnitTestHostWindows.offScreenOrigin(for: size, displays: fakeDisplays)
        XCTAssertEqual(origin, NSPoint(x: -1920 - 1000 - 4000, y: -300 - 800 - 4000))
        let frame: NSRect = NSRect(origin: origin, size: size)
        XCTAssertFalse(UnitTestHostWindows.overlapsADisplay(frame, displays: fakeDisplays))
    }

    func testAWindowThatIsNotASheetIsPinnedWhereverItIsAsked() {
        let size: NSSize = NSSize(width: 1000, height: 800)
        let pinned: NSPoint = UnitTestHostWindows.offScreenOrigin(for: size, displays: fakeDisplays)
        let onADisplay: NSRect = NSRect(x: 100, y: 100, width: 1000, height: 800)
        let elsewhereOff: NSRect = NSRect(x: -30000, y: -30000, width: 1000, height: 800)
        XCTAssertEqual(UnitTestHostWindows.placement(of: onADisplay, isASheet: false, displays: fakeDisplays).origin, pinned)
        XCTAssertEqual(UnitTestHostWindows.placement(of: elsewhereOff, isASheet: false, displays: fakeDisplays).origin, pinned,
                       "already off the displays, and still put back at the one origin, so it cannot drift")
    }

    func testASheetStaysBesideItsParentUnlessThatIsOnADisplay() {
        let besideTheParent: NSRect = NSRect(x: -6500, y: -5000, width: 300, height: 120)
        XCTAssertEqual(UnitTestHostWindows.placement(of: besideTheParent, isASheet: true, displays: fakeDisplays), besideTheParent)
        let onADisplay: NSRect = NSRect(x: 200, y: 200, width: 300, height: 120)
        let moved: NSRect = UnitTestHostWindows.placement(of: onADisplay, isASheet: true, displays: fakeDisplays)
        XCTAssertFalse(UnitTestHostWindows.overlapsADisplay(moved, displays: fakeDisplays))
        XCTAssertEqual(moved.size, onADisplay.size)
    }
}
