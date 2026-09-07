import AppKit
import ObjectiveC
import XCTest

/// Stops AppKit's sheet slide animation running inside the test host.
///
/// **Why this exists.** The unit suite runs against the app's real window, so
/// a test that sets alert state — `workspace.renameProblem`, say — puts a real
/// `NSAlert` sheet on screen, and clearing it takes the sheet down again.
/// Between 2026-09-01 and 09-07 that killed the test host 38 times, always
/// with the same stack and never in a shipped app. Read outward, it is:
///
///     XCTest pumps the runloop
///       CA::Transaction::commit()
///         -[NSWindow _layoutViewTree]                    <- a layout pass starts
///           NSHostingView.layout()
///             ViewGraph.updateOutputs -> preferencesDidChange()
///               AppKitDialogBridge.updateExistingAlert(allAlerts:id:)
///                 NSWindowEndWindowModalSession
///                   -[NSWindow(NSSheets) _orderOutRelativeToWindow:]
///                     -[NSSheetMoveHelper closeSheet]
///                       -[NSMoveHelper _doAnimation]     <- spins a NESTED runloop
///                         the display cycle is re-entered, and dereferences null
///
/// The load-bearing frame is the last one. SwiftUI ends the modal session from
/// inside `NSHostingView.layout()`, and AppKit's sheet animation then spins a
/// nested runloop from inside a display-cycle callback that is already running.
/// It is one call stack on one thread — not a race between two of them — so
/// there is no delay, and no amount of settling, that would make it safe. The
/// only way out is for that nested runloop not to be spun at all.
///
/// **What was tried and does not work.** `-NSAutomaticWindowAnimationsEnabled NO`
/// is the obvious lever and it is a dead end: AppKit reads the key on this very
/// path (hooking `-[NSUserDefaults objectForKey:]` during a sheet close shows it
/// consulted, beside `NSOrderOutSheetWhenEnded` and two others) and then ignores
/// it for the sheet move. Measured on macOS 26.6 with the animation timed
/// directly: 0.268 s without the flag, 0.268 s with it. Neither
/// `NSWindow.animationBehavior = .none` on the sheet, nor on its parent, nor
/// `endSheet` inside an `NSAnimationContext` group of zero duration, nor
/// `-NSOrderOutSheetWhenEnded NO`, nor leaving the parent window off screen
/// changes it either — all six measured between 0.264 s and 0.270 s.
///
/// **So the animation is removed instead.** `_doAnimation` is declared on
/// `NSMoveHelper`, which also animates ordinary window moves; overriding it
/// there would reach further than this needs to. `NSSheetMoveHelper` inherits
/// it without declaring its own, so adding an empty one to that subclass takes
/// sheets — and only sheets — out of the animation. Measured with the same
/// probe: the sheet still opens, still closes, the completion handler still
/// runs, the parent window is still usable for the next sheet, and
/// `NSMoveHelper`'s implementation runs zero times instead of once.
///
/// **This is test-host-only.** The file is in `QuartzTeachersTests`, so nothing
/// in the shipped app changes: a teacher's sheets slide exactly as they always
/// have. It is also not a way of hiding crashes — anything of ours that dies
/// still takes the host with it. It removes one AppKit animation, nothing else.
///
/// Installed from the test bundle's principal class, so it is in place before
/// the first test runs rather than before the first test that happens to
/// remember. `SheetAnimationSuppressorTests` fails loudly if that stops
/// happening, or if a future macOS moves the method out from under it.
@objc(PlantoirTestBundleSetup)
final class SheetAnimationSuppressor: NSObject {

    // MARK: - Nested types

    /// What happened when the override was installed, so a test can assert it
    /// rather than trusting that it did.
    enum Outcome: String {
        case notAttempted
        case addedToSheetMoveHelper
        case replacedSheetMoveHelpersOwn
        case classIsGone
        case methodIsGone
        case methodMovedToASharedSuperclass
    }

    // MARK: - Stored properties

    /// Set once, by `install()`.
    nonisolated(unsafe) static var outcome: Outcome = Outcome.notAttempted

    // MARK: - Initializer

    /// Named as the test bundle's `NSPrincipalClass`, which is instantiated
    /// when the bundle loads — before any test class is enumerated.
    override init() {
        super.init()
        SheetAnimationSuppressor.install()
    }

    // MARK: - Functions

    /// Idempotent: running it twice leaves the same one override in place.
    nonisolated static func install() {
        if outcome != Outcome.notAttempted {
            return
        }

        let selector: Selector = NSSelectorFromString("_doAnimation")

        guard let sheetMoveHelper: AnyClass = NSClassFromString("NSSheetMoveHelper") else {
            outcome = Outcome.classIsGone
            return
        }
        guard class_getInstanceMethod(sheetMoveHelper, selector) != nil else {
            outcome = Outcome.methodIsGone
            return
        }

        let doNothing: @convention(block) (AnyObject) -> Void = { _ in }
        let replacement: IMP = imp_implementationWithBlock(doNothing)

        // `class_addMethod` succeeds only while NSSheetMoveHelper inherits
        // `_doAnimation` rather than declaring its own — which is the shape
        // macOS 26.6 has, and the reason this can be scoped to sheets at all.
        if class_addMethod(sheetMoveHelper, selector, replacement, "v@:") {
            outcome = Outcome.addedToSheetMoveHelper
            return
        }

        // The add failed, so the class declares its own. Replace THAT one —
        // never a method inherited from NSMoveHelper, which also animates
        // ordinary window moves and is no business of this suite's.
        if let own: Method = declaredMethod(on: sheetMoveHelper, named: selector) {
            method_setImplementation(own, replacement)
            outcome = Outcome.replacedSheetMoveHelpersOwn
        } else {
            outcome = Outcome.methodMovedToASharedSuperclass
        }
    }

    /// The method a class declares ITSELF, ignoring anything it inherits.
    /// `class_getInstanceMethod` walks up the hierarchy; this deliberately
    /// does not.
    nonisolated static func declaredMethod(on someClass: AnyClass, named selector: Selector) -> Method? {
        var count: UInt32 = 0
        guard let methods: UnsafeMutablePointer<Method> = class_copyMethodList(someClass, &count) else {
            return nil
        }
        defer { free(UnsafeMutableRawPointer(methods)) }
        for index in 0..<Int(count) {
            if method_getName(methods[index]) == selector {
                return methods[index]
            }
        }
        return nil
    }
}
