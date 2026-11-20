import AppKit
import Foundation

/// Whether macOS has finished putting this launch's windows back, and work
/// that waits for it (#998).
///
/// A restored window looks for its remembered folder by its frame
/// (`WindowRootView.attemptClaim`), so it must not look before macOS has
/// restored the frame. Until #998 it retried every 150 ms, seven times,
/// because "a reopened window's frame settles a moment after the window
/// exists". Measured on macOS 26.7.3 with a SwiftUI `WindowGroup` (a probe
/// app; 2026-11-19), the order at launch is:
///
/// 1. `applicationWillFinishLaunching`;
/// 2. AppKit restores every window's frame (`NSWindow.didMoveNotification`
///    for each, at its remembered place);
/// 3. `NSApplication.didFinishRestoringWindowsNotification`, posted on
///    every launch, with two windows restored, with none, and with no saved
///    state at all;
/// 4. `applicationDidFinishLaunching`;
/// 5. each window's content joins it (`WindowAccessor`), every restored
///    window in the same pass of the main actor, before a task enqueued by
///    the first of them runs, and each with its frame already final.
///
/// So the frame is final when the window is handed over, and the moment to
/// wait for, if it ever comes later, is step 3. This records step 3 from
/// before any window exists, and runs what waited for it then. It also
/// explains why `WindowRootView`'s own `onReceive` for step 3 could never
/// fire at launch: SwiftUI subscribes when the view appears, at step 5.
@MainActor
final class LaunchRestoration {

    // MARK: - Stored properties

    /// The app's one record, filled from `AppDelegate`.
    static let shared: LaunchRestoration = LaunchRestoration()

    /// True once macOS has said it has finished restoring windows.
    private(set) var hasFinished: Bool = false

    /// Work waiting for that moment, in the order it asked.
    private var waiting: [() -> Void] = []

    /// The notification observer, kept so it lives as long as the app.
    private var observer: NSObjectProtocol?

    // MARK: - Functions

    /// Starts listening. Called from `applicationWillFinishLaunching`,
    /// which is before restoration begins (step 1 above).
    func startListening() {
        if observer != nil {
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishRestoringWindowsNotification,
            object: nil,
            queue: nil
        ) { _ in
            // Posted on the main thread, by AppKit, during launch.
            MainActor.assumeIsolated {
                LaunchRestoration.shared.restorationFinished()
            }
        }
    }

    /// Runs `action` now when restoration has finished, or the moment it
    /// does.
    func whenFinished(_ action: @escaping () -> Void) {
        if hasFinished {
            action()
            return
        }
        waiting.append(action)
    }

    /// macOS has finished restoring windows: runs whatever waited for it.
    func restorationFinished() {
        if hasFinished {
            return
        }
        hasFinished = true
        let actions: [() -> Void] = waiting
        waiting = []
        for action in actions {
            action()
        }
    }
}
