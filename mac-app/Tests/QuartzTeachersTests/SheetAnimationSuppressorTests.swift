import AppKit
import CoreFoundation
import ObjectiveC
import XCTest
@testable import QuartzTeachers

/// Pins the one thing standing between this suite and a segfaulting test host.
///
/// `SheetAnimationSuppressor` explains the crash and why the sheet animation has
/// to go. These tests exist so that it cannot stop working QUIETLY — if the
/// principal class is dropped from `project.yml`, or a future macOS stops
/// honouring the switch, the suite says so here rather than going back to dying
/// a third of the time and blaming whichever test was running.
final class SheetAnimationSuppressorTests: XCTestCase {

    // MARK: - Functions

    /// The bundle's principal class is what throws the switch, and it is
    /// declared in `project.yml`. A regenerated project that lost the setting
    /// would leave every other test passing and the crash back.
    func testTheTestBundleAsksForTheSuppressorByName() throws {
        let bundle: Bundle = try XCTUnwrap(Bundle(for: SheetAnimationSuppressorTests.self))
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "NSPrincipalClass") as? String,
            "PlantoirTestBundleSetup",
            "the test bundle must name SheetAnimationSuppressor as its principal class"
        )
        XCTAssertTrue(
            bundle.principalClass === SheetAnimationSuppressor.self,
            "and that name must still resolve to this class"
        )
    }

    /// Thrown before any test ran, not lazily by whoever remembered.
    func testTheAnimationWasSkippedBeforeTheSuiteStarted() {
        XCTAssertEqual(
            SheetAnimationSuppressor.outcome,
            SheetAnimationSuppressor.Outcome.sheetsSkipTheirAnimation,
            "expected NSSheetMoveHelper's own shouldSkipAnimation to have been forced true"
        )
    }

    /// The SHAPE the scoping rests on, which is all this one checks:
    /// `shouldSkipAnimation` is declared on `NSSheetMoveHelper` AND on its
    /// superclass `NSMoveHelper`, which animates ordinary window moves. Because
    /// the subclass has its own, replacing it leaves window moves alone. If
    /// macOS ever collapses the two, this says so in one sentence instead of
    /// leaving somebody to read a crash report.
    ///
    /// It deliberately does NOT prove the switch was thrown — it passes either
    /// way, since the two classes ship different implementations regardless.
    /// That is `testTheAnimationWasSkippedBeforeTheSuiteStarted`'s job, and the
    /// runloop test below's.
    func testOnlySheetsWereTakenOutOfTheAnimation() throws {
        let selector: Selector = NSSelectorFromString("shouldSkipAnimation")
        let sheetMoveHelper: AnyClass = try XCTUnwrap(NSClassFromString("NSSheetMoveHelper"))
        let moveHelper: AnyClass = try XCTUnwrap(NSClassFromString("NSMoveHelper"))

        XCTAssertTrue(
            class_getSuperclass(sheetMoveHelper) === moveHelper,
            "NSSheetMoveHelper is expected to be an NSMoveHelper"
        )

        let sheetSwitch: Method = try XCTUnwrap(
            SheetAnimationSuppressor.declaredMethod(on: sheetMoveHelper, named: selector),
            "the sheet subclass must still declare its own switch — that is what makes this scoped"
        )
        let moveSwitch: Method = try XCTUnwrap(
            SheetAnimationSuppressor.declaredMethod(on: moveHelper, named: selector),
            "and NSMoveHelper must still declare the one ordinary window moves use"
        )
        XCTAssertFalse(
            method_getImplementation(sheetSwitch) == method_getImplementation(moveSwitch),
            "an ordinary window move must still animate — only sheets were changed"
        )
    }

    /// The one that would catch a regression: a real `NSAlert` sheet is raised
    /// on a real window and taken down again, and AppKit's private animation
    /// runloop mode must never be entered while that happens.
    ///
    /// That mode is the frame the 38 crash reports die in — a nested runloop
    /// spun from inside a display-cycle callback. Watching for the mode itself,
    /// rather than timing the close, is what makes this a test rather than a
    /// stopwatch: it fails for the reason that matters and cannot be talked out
    /// of failing by a busy machine.
    @MainActor
    func testASheetGoesUpAndDownWithoutTheNestedAnimationRunLoop() async throws {
        var nestedModeWasEntered: Bool = false
        let observer: CFRunLoopObserver = try XCTUnwrap(CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.allActivities.rawValue, true, 0
        ) { _, _ in
            nestedModeWasEntered = true
        })
        let mode: CFRunLoopMode = CFRunLoopMode(
            SheetAnimationSuppressor.animationRunLoopMode as CFString
        )
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, mode)
        defer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, mode) }

        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.makeKeyAndOrderFront(nil)

        var completionRan: Bool = false
        let alert: NSAlert = NSAlert()
        alert.messageText = "A sheet the suite raised on purpose"
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in
            completionRan = true
        }
        try await Task.sleep(for: .seconds(0.4))
        XCTAssertNotNil(window.attachedSheet, "the sheet went up")

        let sheet: NSWindow = try XCTUnwrap(window.attachedSheet)
        window.endSheet(sheet)
        try await Task.sleep(for: .seconds(0.4))

        XCTAssertNil(window.attachedSheet, "and came back down")
        XCTAssertTrue(completionRan, "with its completion handler run")
        XCTAssertFalse(alert.window.isVisible, "and its window off screen")
        XCTAssertFalse(
            nestedModeWasEntered,
            """
            AppKit spun its animation runloop for a sheet. That is the nested loop \
            the test host segfaults inside — see SheetAnimationSuppressor.
            """
        )

        // Given back rather than merely hidden: an ordered-out window stays in
        // NSApp.windows for the rest of the run, and this suite has tests that
        // photograph whatever window is up.
        alert.window.close()
        window.close()
    }
}
