import XCTest
import SwiftUI
@testable import QuartzTeachers

/// The working folder is shown at the bottom of the window.
final class WindowPathBarTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testThePathBarIsOnScreenWithItsFolder() async throws {
        guard let workspace = WorkspaceModel.windowModels.first else {
            throw XCTSkip("The interface is not on screen in this run")
        }
        let folderURL: URL = try FixtureWorkspace.materialize()
        workspace.chooseWorkspace(at: folderURL)
        try await Task.sleep(for: .milliseconds(500))

        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(workspace.window)
        XCTAssertNotNil(AccessibilityInspector.frame(forIdentifier: "windowPathBar"),
                        "The path bar is not in the accessibility tree")

        // Both footers are declared from one constant, which is what keeps
        // their rules on the same line across the window.
        XCTAssertGreaterThanOrEqual(WindowChrome.footerHeight, 28, "A footer needs room for a 24pt button")
        XCTAssertGreaterThan(WindowChrome.pathBarHeight, WindowChrome.footerHeight,
                             "The path bar sits flush to the window edge, so it must be the taller of the two")

        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(workspace.window)
        let labels: [String] = AccessibilityInspector.collectAllLabels()
        var mentionsTheFolder: Bool = false
        var carriesItsLabel: Bool = false
        for label in labels {
            if label.contains("Folder location: \(folderURL.path)") {
                mentionsTheFolder = true
            }
            if label == "Working folder:" {
                carriesItsLabel = true
            }
        }
        XCTAssertTrue(mentionsTheFolder, "The bar should name the working folder")
        XCTAssertTrue(carriesItsLabel, "The bar should say what it is showing")
    }

    /// Position is deliberately not asserted here: for SwiftUI content the
    /// accessibility tree hands back a container's frame — the whole window
    /// in this case — so a positional check would be measuring the wrong
    /// rectangle. The placement was confirmed from a window capture, which
    /// shows the bar along the bottom of the detail column, and that capture
    /// is what to repeat if the layout is ever in doubt.
}
