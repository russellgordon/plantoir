import AppKit
import ObjectiveC
import XCTest

/// Asks AppKit to skip the sheet animation inside the test host.
///
/// **Why this exists.** The unit suite runs against the app's real window, so a
/// test that sets alert state — `workspace.renameProblem`, say — puts a real
/// `NSAlert` sheet on screen, and clearing it takes the sheet down again.
/// Between 2026-09-01 and 09-07 that killed the test host 38 times, always with
/// the same stack. Read outward, it is:
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
/// nested runloop — in its own private `_NSMoveTimerRunLoopMode` — from inside a
/// display-cycle callback that is already running. It is one call stack on one
/// thread, not a race between two of them, so there is no delay and no amount of
/// settling that would make it safe. The nested runloop has to not be spun.
///
/// **What does NOT work, measured rather than assumed.**
/// `-NSAutomaticWindowAnimationsEnabled NO` is the obvious lever and it is a
/// dead end: AppKit reads the key on this very path (hooking
/// `-[NSUserDefaults objectForKey:]` during a close shows it consulted, beside
/// `NSOrderOutSheetWhenEnded` and two others) and then ignores it for the sheet
/// move — 0.268 s animating without the flag, 0.268 s with it. Neither
/// `NSWindow.animationBehavior = .none` on the sheet, nor on its parent, nor
/// `endSheet` inside a zero-duration `NSAnimationContext` group, nor
/// `-NSOrderOutSheetWhenEnded NO`, nor leaving the parent window off screen
/// changes it either: all six landed between 0.264 s and 0.270 s on macOS 26.6.
///
/// **What does work is AppKit's own switch.** `NSSheetMoveHelper` declares its
/// own `-shouldSkipAnimation`, overriding `NSMoveHelper`'s, and forcing it to
/// answer true is how AppKit itself takes sheets out of the animation. Measured
/// with the same probe: `beginSheetModal` blocks for 0.020 s instead of 0.281 s,
/// `endSheet` for 0.008 s instead of 0.267 s, the sheet's frame is identical to
/// the point, the completion handler still runs, the window takes another sheet
/// afterwards — and a runloop observer registered for `_NSMoveTimerRunLoopMode`
/// never fires, which is the whole point.
///
/// **Why the switch rather than an empty `_doAnimation`.** Overriding
/// `_doAnimation` with an empty method also works, and was what this file did
/// first. The switch is better for three reasons. AppKit's own skip path leaves
/// the state AppKit intends to leave, by construction, rather than by our having
/// probed that dropping `setUpAnimation`/`cleanUpAnimation` happens to be
/// symmetric. `shouldSkipAnimation` is declared on `NSSheetMoveHelper` itself,
/// so one `method_setImplementation` scopes the change to sheets with no
/// `class_addMethod` and no fallback to reason about — where `_doAnimation` is
/// declared only on `NSMoveHelper`, which animates ordinary window moves too.
/// And it puts the test host in a configuration AppKit already ships to real
/// people, instead of one nobody runs.
///
/// **This is test-host-only, and it is not a way of hiding crashes.** The file
/// is in `QuartzTeachersTests`, so nothing in the shipped app changes and a
/// teacher's sheets animate exactly as they always have; it is not in
/// `Tests/Shared` either, so the out-of-process UI target is untouched.
/// Anything of ours that dies still takes the host with it.
///
/// **One thing it does cost, said plainly.** The crash mechanism is reachable in
/// the shipping app: `GUI-IMPROVEMENTS.md` row 391 records this exact stack
/// killing Plantoir on 2026-09-05, when a rename dismissed a sheet and raised an
/// alert in the same breath. That was fixed at source, and the rule against it
/// is `contracts/shared-rules.json` → `siteHealth.repair.oneAlertAtATime`. After
/// this change the test host is no longer a place that failure would show up —
/// but it never was: the 38 crashes here were the suite's own state changes, not
/// a product defect, and row 391's crash was found by driving the real app, not
/// by the suite. Every Plantoir crash report on this Mac carries
/// `libXCTestBundleInject.dylib`, so none of them is a teacher's; that is not
/// the same as saying no teacher could ever meet one.
///
/// Installed from the test bundle's principal class, so it is in place before
/// the first test class is enumerated rather than before the first test that
/// remembers. `SheetAnimationSuppressorTests` fails loudly if that stops
/// happening, or if a future macOS stops honouring the switch.
@objc(PlantoirTestBundleSetup)
final class SheetAnimationSuppressor: NSObject {

    // MARK: - Nested types

    /// What happened when the switch was thrown, so a test can assert it rather
    /// than trusting that it was.
    enum Outcome: String {
        case notAttempted
        case sheetsSkipTheirAnimation
        case theSheetHelperIsGone
        case theSwitchIsGone
    }

    // MARK: - Stored properties

    /// Set once, by `install()`.
    nonisolated(unsafe) static var outcome: Outcome = Outcome.notAttempted

    /// The private runloop mode AppKit's move animation spins. Named here
    /// because the test that matters watches for it.
    static let animationRunLoopMode: String = "_NSMoveTimerRunLoopMode"

    // MARK: - Initializer

    /// Named as the test bundle's `NSPrincipalClass`, which is instantiated
    /// when the bundle loads — before any test class is enumerated.
    override init() {
        super.init()
        SheetAnimationSuppressor.install()
    }

    // MARK: - Functions

    /// Idempotent: running it twice leaves the same one switch thrown.
    nonisolated static func install() {
        if outcome != Outcome.notAttempted {
            return
        }

        guard let sheetMoveHelper: AnyClass = NSClassFromString("NSSheetMoveHelper") else {
            outcome = Outcome.theSheetHelperIsGone
            return
        }

        // Deliberately the method NSSheetMoveHelper declares ITSELF. It
        // overrides NSMoveHelper's, and replacing the subclass's own is what
        // leaves ordinary window moves animating.
        guard let ownSwitch: Method = declaredMethod(
            on: sheetMoveHelper,
            named: NSSelectorFromString("shouldSkipAnimation")
        ) else {
            outcome = Outcome.theSwitchIsGone
            return
        }

        let alwaysSkip: @convention(block) (AnyObject) -> Bool = { _ in return true }
        method_setImplementation(ownSwitch, imp_implementationWithBlock(alwaysSkip))
        outcome = Outcome.sheetsSkipTheirAnimation
    }

    /// The method a class declares ITSELF, ignoring anything it inherits.
    /// `class_getInstanceMethod` walks up the hierarchy; this deliberately does
    /// not, because the whole scoping argument rests on the difference.
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
