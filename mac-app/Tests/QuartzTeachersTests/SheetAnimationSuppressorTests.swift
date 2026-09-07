import AppKit
import ObjectiveC
import XCTest
@testable import QuartzTeachers

/// Pins the one thing standing between this suite and a segfaulting test host.
///
/// `SheetAnimationSuppressor` explains the crash and why the animation has to
/// go. These tests exist so that it cannot stop working QUIETLY — if the
/// principal class is dropped from `project.yml`, or macOS moves the method,
/// the suite says so here rather than going back to dying twice in ten runs
/// and blaming whichever test was running at the time.
final class SheetAnimationSuppressorTests: XCTestCase {

    // MARK: - Functions

    /// The bundle's principal class is what installs the override, and it is
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

    /// Installed before any test ran, not lazily by whoever remembered.
    func testTheAnimationWasSuppressedBeforeTheSuiteStarted() {
        XCTAssertEqual(
            SheetAnimationSuppressor.outcome,
            SheetAnimationSuppressor.Outcome.addedToSheetMoveHelper,
            "expected the empty override to have been added to NSSheetMoveHelper"
        )
    }

    /// The shape this depends on: `_doAnimation` belongs to `NSMoveHelper`,
    /// which animates ordinary window moves too, and `NSSheetMoveHelper`
    /// inherits it. That is what lets sheets be taken out of the animation on
    /// their own. If macOS ever changes it, this says so in one sentence
    /// instead of leaving somebody to read a crash report.
    func testOnlySheetsWereTakenOutOfTheAnimation() throws {
        let selector: Selector = NSSelectorFromString("_doAnimation")
        let sheetMoveHelper: AnyClass = try XCTUnwrap(NSClassFromString("NSSheetMoveHelper"))
        let moveHelper: AnyClass = try XCTUnwrap(NSClassFromString("NSMoveHelper"))

        XCTAssertTrue(
            class_getSuperclass(sheetMoveHelper) === moveHelper,
            "NSSheetMoveHelper is expected to be an NSMoveHelper"
        )
        XCTAssertNotNil(
            SheetAnimationSuppressor.declaredMethod(on: sheetMoveHelper, named: selector),
            "the sheet subclass should now declare its own (empty) _doAnimation"
        )

        let sheetImplementation: IMP? = SheetAnimationSuppressor
            .declaredMethod(on: sheetMoveHelper, named: selector)
            .map { method in return method_getImplementation(method) }
        let moveImplementation: IMP? = SheetAnimationSuppressor
            .declaredMethod(on: moveHelper, named: selector)
            .map { method in return method_getImplementation(method) }

        XCTAssertNotNil(moveImplementation, "NSMoveHelper still declares the real one")
        XCTAssertFalse(
            sheetImplementation == moveImplementation,
            "an ordinary window move must still animate — only sheets were changed"
        )
    }

    /// And the point of all of it: a sheet raised on a real window comes down
    /// again, completely, without AppKit spinning a nested runloop to do it.
    /// This is the case that used to kill the host.
    @MainActor
    func testASheetStillOpensAndClosesCompletely() async throws {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

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
    }
}
