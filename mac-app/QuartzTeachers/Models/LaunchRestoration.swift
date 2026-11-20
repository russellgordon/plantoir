import AppKit
import Foundation

/// Whether macOS has finished putting this launch's windows back, and work
/// that waits for it (#998).
///
/// A restored window gives up looking for its remembered folder by frame
/// only once this has happened (`WindowClaimRound`). Measured with a probe
/// app (a SwiftUI `WindowGroup`, 2026-11-19; documentation 09, "When a
/// restored window looks for its folder"):
///
/// - `NSApplication.didFinishRestoringWindowsNotification` is posted on
///   EVERY launch, on macOS 26.7.3 and 15.7.7 alike: two windows restored,
///   none restored, and no saved state at all.
/// - On 26.7.3 every frame is restored before it, and the windows' content
///   joins them after it. On 15.7.7 the content joins each window before it,
///   with the restored frame, and SwiftUI then moves and resizes the window,
///   also before it.
///
/// So by this moment every restored window exists and has been handed its
/// frame, on both. It is recorded from `applicationWillFinishLaunching`,
/// before any window exists. Nothing else marks it: if it were ever not
/// posted, a launching window would keep its quiet spinner rather than
/// guess, and no launch measured has done that.
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
