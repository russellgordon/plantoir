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

        // As `MenuKeysBehindASheetTests` asks for it.
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
        guard NSApp.isActive else {
            throw XCTSkip("The host could not be made active in this session (#315), so there is nothing to hand back.")
        }

        handBack.testCaseDidFinish(self)

        var handedBack: Bool = false
        var polls: Int = 0
        while polls < 20 {
            if let front = frontmostPID(), front != ourPID {
                handedBack = true
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
            polls += 1
        }
        XCTAssertTrue(handedBack, "another app is frontmost within a second of the hand-back")
    }
}
