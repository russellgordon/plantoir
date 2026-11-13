import XCTest
@testable import QuartzTeachers

/// A deploy that built the site first leaves one line on the trail, saying
/// why (#768, #748 part 2). Every word comes from the contract, never retyped
/// here: `contracts/shared-rules.json` → `activityTrail.mustRecord."site built
/// again before deploying"`. `scripts/test_build_freshness_reuse.py` pins
/// deploy.sh's own lines to the same words.
@MainActor
final class BuiltBeforeDeployingReportTests: XCTestCase {

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
            if candidate["event"] as? String == ActivityTrail.Event.siteBuiltAgainBeforeDeploying.rawValue {
                entry = candidate
            }
        }
        XCTAssertFalse(entry.isEmpty, "the contract has no 'site built again before deploying' event")

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("built-before-deploying-\(UUID().uuidString)", isDirectory: true)
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

    private func marker() throws -> [String: Any] {
        return try XCTUnwrap(entry["marker"] as? [String: Any])
    }

    func testTheWordsAreTheContracts() throws {
        XCTAssertEqual(BuiltBeforeDeployingReport.line, entry["line"] as? String)
        XCTAssertEqual(BuiltBeforeDeployingReport.lineWhenItHadNotBeenBuilt, entry["lineWhenItHadNotBeenBuilt"] as? String)
        XCTAssertEqual(BuiltBeforeDeployingReport.whyWords, entry["whyWords"] as? [String: String])
        XCTAssertEqual(BuiltBeforeDeployingReport.markerPrefix, try marker()["prefix"] as? String)
    }

    /// Every reason the app can build for has words, so no build is written
    /// as another reason's.
    func testEveryReasonTheAppGivesHasItsOwnLine() {
        var lines: Set<String> = []
        for reason in BuildFreshness.RebuildReason.allCases {
            let sentence: String = BuiltBeforeDeployingReport.sentence(for: reason)
            XCTAssertFalse(sentence.isEmpty, reason.rawValue)
            XCTAssertFalse(sentence.contains("{"), sentence)
            lines.insert(sentence)
        }
        XCTAssertEqual(lines.count, BuildFreshness.RebuildReason.allCases.count)
        XCTAssertNotNil(BuiltBeforeDeployingReport.whyWords["toolchain"], "deploy.sh's own reason")
    }

    func testTheContractsExamplesAreRead() throws {
        let examples: [String] = try XCTUnwrap(try marker()["examples"] as? [String])
        for example in examples {
            XCTAssertEqual(BuiltBeforeDeployingReport.reports(in: "before\n" + example + "\nafter\n").count, 1, example)
        }
        let spaced: [BuiltBeforeDeployingReport] = BuiltBeforeDeployingReport.reports(
            in: BuiltBeforeDeployingReport.markerPrefix + " neverBuilt AP+CALC/2\n"
        )
        XCTAssertEqual(spaced.first?.trailSentence,
                       BuiltBeforeDeployingReport.wholeLine(reason: "neverBuilt", place: "AP CALC/2"))
    }

    /// A marker that is not the shape, or a reason with no words, writes
    /// nothing: a path or a wrong reason never reaches the trail.
    func testAnythingElseWritesNothing() {
        let text: String = [
            BuiltBeforeDeployingReport.markerPrefix + " pages",
            BuiltBeforeDeployingReport.markerPrefix + " pages /Users/someone/courses",
            BuiltBeforeDeployingReport.markerPrefix + " because-of-this ICS4U/1",
            BuiltBeforeDeployingReport.markerPrefix + " somethingElse ICS4U/1",
        ].joined(separator: "\n")
        BuiltBeforeDeployingReport.noteOnTheTrail(from: text)
        XCTAssertFalse(trailText().contains("before deploying it"), trailText())
    }

    func testAScheduledRunsMarkerWritesTheLine() {
        BuiltBeforeDeployingReport.noteOnTheTrail(from: BuiltBeforeDeployingReport.markerPrefix + " pages ICS4U/1\n")
        let expected: String = BuiltBeforeDeployingReport.wholeLine(reason: "pages", place: "ICS4U/1") ?? "?"
        XCTAssertTrue(trailText().contains(expected), trailText())
    }

    /// The scheduled deploy's log reader asks it, beside the folder report.
    func testTheScheduledLogReaderAsksIt() throws {
        var sourceURL: URL?
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: ActivityTrailWiringTests.productSourceFolderURL()) {
            if fileURL.lastPathComponent == "ScheduledDeploy.swift" {
                sourceURL = fileURL
            }
        }
        let source: String = try String(contentsOf: try XCTUnwrap(sourceURL), encoding: .utf8)
        XCTAssertTrue(source.contains("BuiltBeforeDeployingReport.noteOnTheTrail(from: text)"))
        XCTAssertTrue(source.contains("BuiltBeforeDeployingReport.markerPrefix"))
    }
}
