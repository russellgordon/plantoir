import XCTest
@testable import QuartzTeachers

/// Drives the REAL window to answer one question: when the model's
/// expansion state is set programmatically — as restoration does — do
/// the sidebar's disclosure groups actually unfold?
final class SidebarRestorationProbeTests: XCTestCase {

    @MainActor
    func settle(seconds: Double = 0.7) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    @MainActor
    func testProgrammaticExpansionUnfoldsTheRealSidebar() async throws {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        guard let workspace = WorkspaceModel.windowModels.first else {
            XCTFail("No window model registered; the interface is not on screen")
            return
        }

        workspace.chooseWorkspace(at: fixtureURL)
        workspace.expandedCourseCodes = []
        await settle()

        // Collapsed baseline: the course row shows, its sections do not.
        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(workspace.window)
        var labels: [String] = AccessibilityInspector.collectAllLabels()
        XCTAssertTrue(labels.contains("EXC2O"))
        XCTAssertFalse(labels.contains("Section 1"),
                       "Baseline should be collapsed; found sections already visible")

        // The restoration path: expansion arrives on the model, not by
        // a click.
        workspace.expandedCourseCodes = ["EXC2O"]
        await settle()

        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(workspace.window)
        labels = AccessibilityInspector.collectAllLabels()
        XCTAssertTrue(labels.contains("Section 1"),
                      "Setting the model's expansion must unfold the group; labels: \(labels.prefix(40))")
    }

    @MainActor
    func testExpansionSetBeforeTheSidebarExistsStillUnfolds() async throws {
        // The REAL restoration order: the sidebar does not exist yet
        // (picker/placeholder branch), the claim resolves — folder and
        // expansion land on the model together — and only THEN is the
        // sidebar created. A freshly created DisclosureGroup must honour
        // an initial binding of true.
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        guard let workspace = WorkspaceModel.windowModels.first else {
            XCTFail("No window model registered; the interface is not on screen")
            return
        }

        // Tear the sidebar down entirely.
        workspace.workspaceURL = nil
        workspace.expandedCourseCodes = []
        await settle()
        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(workspace.window)
        var labels: [String] = AccessibilityInspector.collectAllLabels()
        XCTAssertFalse(labels.contains("EXC2O"), "Sidebar should be gone")

        // Exactly what adopt() does, in its order.
        workspace.adoptRestoredPath(fixtureURL.path)
        workspace.expandedCourseCodes = ["EXC2O"]
        await settle()

        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(workspace.window)
        labels = AccessibilityInspector.collectAllLabels()
        XCTAssertTrue(labels.contains("EXC2O"), "Sidebar should be back")
        XCTAssertTrue(labels.contains("Section 1"),
                      "A fresh sidebar must honour pre-set expansion; labels: \(labels.prefix(40))")
    }
}
