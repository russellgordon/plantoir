import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The sidebar's − button, driven end to end in the real window: select a
/// course, press the button through the accessibility tree, and require
/// the confirmation alert to actually appear. Guards against presentation
/// regressions — the alert logic can be perfect while the alert itself
/// never shows.
final class RemovalButtonTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func settle(seconds: Double = 0.8) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    @MainActor
    func testMinusButtonAsksBeforeRemoving() async throws {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        guard let workspace = WorkspaceModel.windowModels.first else {
            XCTFail("No window model registered; the interface is not on screen")
            return
        }

        workspace.chooseWorkspace(at: fixtureURL)
        await settle()
        XCTAssertFalse(workspace.courses.isEmpty, "Fixture should contain a course")

        // Select the course, as clicking its sidebar row would.
        let courseCode: String = workspace.courses[0].code
        workspace.selection = SidebarSelection.course(courseCode)
        await settle()

        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(workspace.window)
        XCTAssertTrue(AccessibilityInspector.press(identifier: "removeSelectedButton"),
                      "The − button should be present and enabled with a course selected")
        await settle()

        // The desktop can change after the press. If it has, the alert may
        // already be up, so close it before skipping — the next test must
        // not find it covering the window.
        do {
            try AccessibilityInspector.skipUnlessTheWindowCanBeRead(workspace.window)
        } catch {
            await closeTheAlert(in: workspace)
            throw error
        }
        let labels: [String] = AccessibilityInspector.collectAllLabels()
        var alertAppeared: Bool = false
        for label in labels {
            if label.contains("Remove \(courseCode)?") {
                alertAppeared = true
            }
        }
        XCTAssertTrue(alertAppeared,
                      "Pressing − must show the confirmation alert; labels seen: \(labels.suffix(25))")

        await closeTheAlert(in: workspace)
    }

    /// Closes the alert so later tests find the window as they left it.
    @MainActor
    func closeTheAlert(in workspace: WorkspaceModel) async {
        _ = AccessibilityInspector.press(identifier: "Cancel")
        for label in ["Cancel"] where AccessibilityInspector.press(identifier: label) {
            break
        }
        await settle(seconds: 0.3)
        for window in NSApp.windows where window.isSheet {
            window.close()
        }
        workspace.selection = nil
        await settle(seconds: 0.3)
    }
}
