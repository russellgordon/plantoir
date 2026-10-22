import AppKit
import ApplicationServices
import XCTest
@testable import QuartzTeachers

/// After a test leaves the host active, the front goes back to whoever had it
/// (#633). Run alone, the host is never active, so "the host is not active"
/// would pass with no hand-back at all (measured in the plan review); this
/// test therefore activates the host the way `MenuKeysBehindASheetTests`
/// does, and calls the observer itself.
@MainActor
final class ActivationHandBackTests: XCTestCase {

    // MARK: - Functions

    /// The pid at the front, as the system sees it.
    func frontmostPID() -> pid_t? {
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// Makes the host active the way `MenuKeysBehindASheetTests` asks for it.
    /// True when it worked within a second.
    func makeTheHostActive() async -> Bool {
        let ourPID: pid_t = ProcessInfo.processInfo.processIdentifier
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.isActive {
            let application: AXUIElement = AXUIElementCreateApplication(ourPID)
            AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        var waited: Int = 0
        while !NSApp.isActive && waited < 20 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        return NSApp.isActive
    }

    /// True once an app other than the host is frontmost, polled for a second.
    func anotherAppComesToTheFront() async -> Bool {
        let ourPID: pid_t = ProcessInfo.processInfo.processIdentifier
        var polls: Int = 0
        while polls < 20 {
            if let front = frontmostPID(), front != ourPID {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
            polls += 1
        }
        return false
    }

    /// The first running app, other than the host, that has no Dock tile.
    func someAppWithoutADockTile() -> NSRunningApplication? {
        let ourPID: pid_t = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            if app.processIdentifier == ourPID {
                continue
            }
            if app.activationPolicy == .accessory || app.activationPolicy == .prohibited {
                return app
            }
        }
        return nil
    }

    // MARK: - Tests

    func testTheFrontGoesBackAfterATestLeavesTheHostActive() async throws {
        let ourPID: pid_t = ProcessInfo.processInfo.processIdentifier
        let handBack: ActivationHandBack = try XCTUnwrap(ActivationHandBack.shared, "registered by the bundle's principal class")
        guard let before = frontmostPID(), before != ourPID else {
            throw XCTSkip("No other app is at the front in this session, so there is nothing to give the front back to.")
        }
        // Tidy even if the assertion below fails, so a broken hand-back does
        // not leave the keyboard with the test host.
        defer {
            if NSApp.isActive {
                NSApp.deactivate()
            }
        }

        let isActive: Bool = await makeTheHostActive()
        guard isActive else {
            throw XCTSkip("The host could not be made active in this session (#315), so there is nothing to hand back.")
        }

        handBack.testCaseDidFinish(self)

        let handedBack: Bool = await anotherAppComesToTheFront()
        XCTAssertTrue(handedBack, "another app is frontmost within a second of the hand-back")
    }

    /// With no app to go back to, the host still gives up the front: to the
    /// Finder. `NSApp.deactivate()` alone left it frontmost for 5 s (measured
    /// in the implementation review).
    func testWithNoAppToGoBackToTheHostStillGivesUpTheFront() async throws {
        let ourPID: pid_t = ProcessInfo.processInfo.processIdentifier
        guard let before = frontmostPID(), before != ourPID else {
            throw XCTSkip("No other app is at the front in this session, so there is nobody to give the front back to afterwards.")
        }
        let personsApp: NSRunningApplication? = NSRunningApplication(processIdentifier: before)
        // Tidy: the Finder took the front for this test, so give it back to
        // whoever had it, even if the assertion below fails.
        defer {
            ActivationHandBack.giveTheFrontBack(to: personsApp)
        }

        let isActive: Bool = await makeTheHostActive()
        guard isActive else {
            throw XCTSkip("The host could not be made active in this session (#315), so there is nothing to hand back.")
        }

        ActivationHandBack.giveTheFrontBack(to: nil)

        let handedBack: Bool = await anotherAppComesToTheFront()
        XCTAssertTrue(handedBack, "with no remembered app, another app is frontmost within a second of the hand-back")

        // Back to the host for a moment so the tidy above, which only acts
        // while the host is active, can hand the front to the person's app.
        _ = await makeTheHostActive()
    }

    /// Only an ordinary app with a Dock tile is remembered, at the first
    /// capture and on every activation since: a background agent activating
    /// must not become where the front goes.
    func testAnAppWithoutADockTileIsNeverRemembered() throws {
        let finder: NSRunningApplication = try XCTUnwrap(ActivationHandBack.finder(), "the Finder is running")
        guard let agent = someAppWithoutADockTile() else {
            throw XCTSkip("No accessory or background app is running in this session.")
        }

        // The first capture.
        XCTAssertNil(ActivationHandBack.otherApp(agent), "an app without a Dock tile is not remembered at the first capture")

        // An activation, on an observer of its own so the registered one is untouched.
        let observer: ActivationHandBack = ActivationHandBack()
        observer.anAppWasActivated(Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: finder]
        ))
        XCTAssertEqual(observer.rememberedApp?.processIdentifier, finder.processIdentifier, "an ordinary app is remembered")
        observer.anAppWasActivated(Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: agent]
        ))
        XCTAssertEqual(observer.rememberedApp?.processIdentifier, finder.processIdentifier, "an app without a Dock tile activating does not replace it")
    }
}
