import XCTest

/// Every UI test launches the app through ONE door, `IsolatedLaunch`, which
/// hands it a state folder of its own (#154).
///
/// The flag is explicit, not a fallback: `UITEST_WORKSPACE` alone still gets
/// the real home, because the marketing captures need it. So what keeps the
/// NEXT UI test from launching unredirected — and writing the teacher's
/// trail and preferences — is this scan of the UI target's source.
final class UITestLaunchTripwireTests: XCTestCase {

    // MARK: - Stored properties

    /// Where an app under test may be created, and how many times.
    static let launchAllowances: [String: Int] = [
        // The door.
        "IsolatedLaunch.swift | XCUIApplication(": 1,
        "IsolatedLaunch.swift | launchEnvironment[\"UITEST_WORKSPACE\"]": 1,
        // The marketing captures drive the REAL toolchain — a real preview,
        // real helper programs — whose children resolve the real home, so a
        // state folder would break them. Run by `website/shots/capture.py`,
        // by hand, rarely; they write the real trail, and doc 09 says so.
        "MarketingScreenshotTests.swift | XCUIApplication(": 1,
        "MarketingScreenshotTests.swift | launchEnvironment[\"UITEST_WORKSPACE\"]": 1,
    ]

    static let needles: [String] = [
        "XCUIApplication(",
        "launchEnvironment[\"UITEST_WORKSPACE\"]",
    ]

    // MARK: - The scan

    func testEveryUITestLaunchesThroughTheOneDoor() throws {
        let folder: URL = RealHomeTripwireTests.testsFolderURL()
            .appendingPathComponent("QuartzTeachersUITests", isDirectory: true)
        let files: [URL] = ActivityTrailWiringTests.swiftFiles(under: folder)
        XCTAssertGreaterThanOrEqual(files.count, 4, "The scan found no UI test source at \(folder.path), so it checked nothing.")
        var found: [String: Int] = [:]
        var unexpected: [String] = []
        for fileURL in files {
            let relativePath: String = RealHomeTripwireTests.path(of: fileURL, under: folder)
            for hit in try RealHomeTripwireTests.hits(of: UITestLaunchTripwireTests.needles, in: fileURL) {
                let key: String = relativePath + " | " + hit.lookup
                found[key, default: 0] += 1
                if UITestLaunchTripwireTests.launchAllowances[key] == nil {
                    unexpected.append("\(relativePath):\(hit.lineNumber) launches the app with `\(hit.lookup)`")
                }
            }
        }
        XCTAssertEqual(
            unexpected, [],
            "Launch the app under test with IsolatedLaunch.launch(workspace:), which gives it a --state-dir of its own. A raw XCUIApplication writes the teacher's real trail and preferences."
        )
        RealHomeTripwireTests.assertCounts(found, match: UITestLaunchTripwireTests.launchAllowances, side: "launchAllowances")
    }
}
