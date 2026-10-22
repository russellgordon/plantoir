import AppKit
import XCTest

/// Gives the front back to whoever had it, after any test that left the test
/// host active (#633).
///
/// **Why.** The host is an accessory app with every window off the displays
/// (`UnitTestHostWindows`), but two classes still make it the ACTIVE app:
/// `MenuKeysBehindASheetTests` on purpose (a window's menu keys only reach the
/// menu bar while it is key in the active app), and
/// `AssistRevealsSectionOnScreenTests` through the product's own
/// `activate(ignoringOtherApps:)`. An active host takes the keyboard from the
/// person at this Mac, even with nothing of it on a display. MEASURED: without
/// this, the host stayed frontmost for the remaining 115 s of a 23-class run;
/// with it, the other app was frontmost again 82 ms and 2.3 s after those two
/// tests finished.
///
/// **What it does.** It remembers the last app other than the host that came
/// to the front — the one frontmost when the bundle loaded, then every one
/// activated since — and, when a test finishes with the host active, yields
/// activation to it and asks it forward. Only an ordinary app with a Dock tile
/// is remembered (`activationPolicy == .regular`): a background agent such as
/// `UserNotificationCenter` activates now and then, and yielding to it would
/// leave the keyboard nowhere useful. If that app has quit, or will not come
/// forward, the front goes to the Finder instead, which is always running.
/// `NSApp.deactivate()` is only the last resort: MEASURED in the implementation
/// review, on its own it left the host active and frontmost for the whole 5 s
/// it was watched. Never `hide`: that would order out the window the next tests
/// read.
///
/// Registered from the bundle's principal class (`PlantoirTestBundleSetup`),
/// so it is in place before the first test. It never activates the host
/// itself, and does nothing while the host is not active.
final class ActivationHandBack: NSObject, XCTestObservation {

    // MARK: - Stored properties

    /// The one observer, once registered.
    nonisolated(unsafe) static var shared: ActivationHandBack? = nil

    /// The last app other than the host that was frontmost.
    nonisolated(unsafe) var rememberedApp: NSRunningApplication? = nil

    // MARK: - Functions

    /// Idempotent.
    static func register() {
        if shared != nil {
            return
        }
        let made: ActivationHandBack = ActivationHandBack()
        shared = made
        made.rememberedApp = ActivationHandBack.otherApp(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            made,
            selector: #selector(ActivationHandBack.anAppWasActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        XCTestObservationCenter.shared.addTestObserver(made)
    }

    /// `app`, unless it is this test host or not an ordinary app with a Dock
    /// tile. An accessory or a background agent is never worth handing the
    /// front to.
    static func otherApp(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app else {
            return nil
        }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return nil
        }
        if app.activationPolicy != .regular {
            return nil
        }
        return app
    }

    @objc func anAppWasActivated(_ notification: Notification) {
        let app: NSRunningApplication? = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let other = ActivationHandBack.otherApp(app) {
            rememberedApp = other
        }
    }

    /// The Finder, which is always running and always an ordinary app: where
    /// the front goes when the remembered app cannot take it.
    static func finder() -> NSRunningApplication? {
        let running: [NSRunningApplication] = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        for app in running {
            if let usable = otherApp(app), !usable.isTerminated {
                return usable
            }
        }
        return nil
    }

    /// Yields the front to `app` and asks it forward. True when it agreed.
    @MainActor
    static func handTheFront(to app: NSRunningApplication?) -> Bool {
        guard let app else {
            return false
        }
        if app.isTerminated {
            return false
        }
        NSApp.yieldActivation(to: app)
        return app.activate()
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        if !Thread.isMainThread {
            return
        }
        let app: NSRunningApplication? = rememberedApp
        MainActor.assumeIsolated {
            ActivationHandBack.giveTheFrontBack(to: app)
        }
    }

    /// Gives the front to `rememberedApp`, or to the Finder when that app has
    /// gone or will not come forward, and only then simply deactivates. Does
    /// nothing unless the host is active.
    @MainActor
    static func giveTheFrontBack(to rememberedApp: NSRunningApplication?) {
        if !NSApp.isActive {
            return
        }
        if handTheFront(to: rememberedApp) {
            return
        }
        if handTheFront(to: finder()) {
            return
        }
        NSApp.deactivate()
    }
}
