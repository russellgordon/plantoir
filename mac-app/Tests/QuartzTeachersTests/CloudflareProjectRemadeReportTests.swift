import XCTest
@testable import QuartzTeachers

/// A section's Cloudflare project made again (2026-09-30) leaves a line on the
/// trail, written by the app from the shared `deploy.py`'s marker.
///
/// Every word comes from the contract, never retyped here:
/// `contracts/shared-rules.json` → `activityTrail.mustRecord."cloudflare
/// project made again"`. `scripts/test_deploy_cloudflare_project.py` pins the
/// Python half: that `deploy.py` prints the marker when, and only when, it
/// made the project again.
@MainActor
final class CloudflareProjectRemadeReportTests: XCTestCase {

    // MARK: - Stored properties

    private var entry: [String: Any] = [:]
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        let contracts: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts", isDirectory: true)
        let sharedRules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: try Data(contentsOf: contracts.appendingPathComponent("shared-rules.json"))
            ) as? [String: Any]
        )
        let trail: [String: Any] = try XCTUnwrap(sharedRules["activityTrail"] as? [String: Any])
        let required: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        for candidate in required {
            if candidate["event"] as? String == ActivityTrail.Event.cloudflareProjectMadeAgain.rawValue {
                entry = candidate
            }
        }
        XCTAssertFalse(entry.isEmpty, "the contract has no 'cloudflare project made again' event")

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloudflare-remade-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Functions

    private func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    private func examples() throws -> [String] {
        let marker: [String: Any] = try XCTUnwrap(entry["marker"] as? [String: Any])
        return try XCTUnwrap(marker["examples"] as? [String])
    }

    // MARK: - Tests: the contract

    func testTheMarkerAndTheLineAreTheContractsOwn() throws {
        let marker: [String: Any] = try XCTUnwrap(entry["marker"] as? [String: Any])
        XCTAssertEqual(marker["prefix"] as? String, CloudflareProjectRemadeReport.markerPrefix)
        XCTAssertEqual(entry["line"] as? String, CloudflareProjectRemadeReport.line)
        XCTAssertNil(entry["appliesOn"], "both platforms run the same deploy.py, so both must record it")
    }

    func testEveryExampleIsUnderstoodAndWritten() throws {
        let lines: [String] = try examples()
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(
            CloudflareProjectRemadeReport.reports(in: lines[0]),
            [CloudflareProjectRemadeReport(place: "ICS4U/1", project: "ics4u-s1-2026-gordon", address: "ics4u-s1-2026-gordon.pages.dev")]
        )
        let spaced: [CloudflareProjectRemadeReport] = CloudflareProjectRemadeReport.reports(in: lines[1])
        XCTAssertEqual(spaced.count, 1, "a course whose code has a space must not drop the line")
        XCTAssertEqual(
            spaced.first?.trailSentence,
            "AP CALC/2 · the Cloudflare project ap-calc-s2-2026-gordon was not in this Cloudflare account, "
                + "so it was made again; the website is now at ap-calc-s2-2026-gordon-7x2.pages.dev"
        )
    }

    // MARK: - Tests: the trail

    /// Through the real runner — the Deploy button's and the assistant's path:
    /// the line reaches the trail, and never the console a teacher reads.
    func testARunRecordsItAndHidesTheLine() throws {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(" Using this section's existing Cloudflare project: ics4u-s1-2026-gordon\r\n")
        runner.receiveOutput(try examples()[0] + "\r\n")
        XCTAssertFalse(runner.transcript.displayText.contains(CloudflareProjectRemadeReport.markerPrefix))
        XCTAssertTrue(trailText().contains(
            "ICS4U/1 · the Cloudflare project ics4u-s1-2026-gordon was not in this Cloudflare account, "
                + "so it was made again; the website is now at ics4u-s1-2026-gordon.pages.dev"
        ), trailText())
    }

    /// A publish set for later: read from its log, as nobody watches it.
    func testAScheduledPublishRecordsItFromItsLog() throws {
        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS4U", sectionNumber: 1) + ".0a1b2c3d"
        let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ("Deploying ICS4U…\n" + (try examples()[0]) + "\n").write(to: log, atomically: true, encoding: .utf8)
        ScheduledDeploy.recordFolderProblems(
            label: label,
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS4U", sectionNumber: 1),
            fromByteOffset: 0,
            inHomeFolder: home
        )
        XCTAssertTrue(trailText().contains("ICS4U/1 · the Cloudflare project ics4u-s1-2026-gordon was not in this"), trailText())
    }

    /// Nothing but a place, a project name and a host name can reach the
    /// trail: a line carrying a path, a command or a missing field is refused.
    func testAPathOrACommandNeverReachesTheTrail() {
        let prefix: String = CloudflareProjectRemadeReport.markerPrefix
        XCTAssertTrue(CloudflareProjectRemadeReport.reports(in: prefix + " ICS4U/1 ics4u-s1").isEmpty)
        XCTAssertTrue(CloudflareProjectRemadeReport.reports(in: prefix + " ICS4U/1 /Users/t/secret a.pages.dev").isEmpty)
        XCTAssertTrue(CloudflareProjectRemadeReport.reports(in: prefix + " ICS4U/1 a b.pages.dev sh -c read").isEmpty)
        XCTAssertTrue(CloudflareProjectRemadeReport.reports(in: prefix + " setup a b.pages.dev").isEmpty)
        XCTAssertTrue(CloudflareProjectRemadeReport.reports(in: prefix + " ICS4U/1 a.b c.pages.dev").isEmpty)
    }
}
