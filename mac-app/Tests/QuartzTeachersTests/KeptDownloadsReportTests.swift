import XCTest
@testable import QuartzTeachers

/// The build's report of what it downloaded for its pages the first time
/// they used it, or why it stopped without it (#674), read the way the app
/// reads it: out of the console and a scheduled publish's log, onto the
/// activity trail as `files for the site downloaded` or `files for the site
/// could not be downloaded`.
///
/// Every value comes from `contracts/shared-rules.json` → `keptDownloads`
/// (`marker.trailCases`, `marker.trailWords`, `kinds`) and the two events'
/// `mustRecord` entries; `scripts/test_phet.py` checks the Python prints
/// exactly `marker.cases`, so the two halves cannot drift.
@MainActor
final class KeptDownloadsReportTests: XCTestCase {

    // MARK: - Stored properties

    private var kept: [String: Any] = [:]
    private var mustRecord: [[String: Any]] = []
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Computed properties

    private var trail: String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        kept = try XCTUnwrap(all["keptDownloads"] as? [String: Any])
        let activityTrail: [String: Any] = try XCTUnwrap(all["activityTrail"] as? [String: Any])
        mustRecord = try XCTUnwrap(activityTrail["mustRecord"] as? [[String: Any]])
        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kept-downloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Functions

    private func marker() throws -> [String: Any] {
        return try XCTUnwrap(kept["marker"] as? [String: Any])
    }

    func testThePrefixIsTheContracts() throws {
        XCTAssertEqual(try marker()["prefix"] as? String, KeptDownloadsReport.markerPrefix)
    }

    /// Every trail case: the event and the sentence, word for word.
    func testEveryTrailCaseIsReadAsTheContractSays() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try marker()["trailCases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 0)
        for testCase in cases {
            let line: String = try XCTUnwrap(testCase["line"] as? String)
            let reports: [KeptDownloadsReport] = KeptDownloadsReport.reports(in: "📦 Building\n" + line + "\n")
            XCTAssertEqual(reports.count, 1, line)
            let report: KeptDownloadsReport = try XCTUnwrap(reports.first)
            XCTAssertEqual(report.event.rawValue, testCase["event"] as? String, line)
            XCTAssertEqual(report.trailSentence, testCase["sentence"] as? String, line)
        }
    }

    /// The words for each kind and each reason are the contract's.
    func testTheWordsAreTheContracts() throws {
        let kinds: [String: Any] = try XCTUnwrap(kept["kinds"] as? [String: Any])
        XCTAssertEqual(Set(kinds.keys), Set(KeptDownloadsReport.kindWords.keys))
        for (kind, value) in kinds {
            let said: [String: Any] = try XCTUnwrap(value as? [String: Any])
            let words: (one: String, several: String) = try XCTUnwrap(KeptDownloadsReport.kindWords[kind])
            XCTAssertEqual(said["one"] as? String, words.one)
            XCTAssertEqual(said["several"] as? String, words.several)
        }
        let trailWords: [String: Any] = try XCTUnwrap(try marker()["trailWords"] as? [String: Any])
        XCTAssertEqual(trailWords["why"] as? [String: String], KeptDownloadsReport.whyWords)
        var found: Bool = false
        for entry in mustRecord {
            if entry["event"] as? String == ActivityTrail.Event.filesForTheSiteCouldNotBeDownloaded.rawValue {
                XCTAssertEqual(entry["whyWords"] as? [String: String], KeptDownloadsReport.whyWords)
                found = true
            }
        }
        XCTAssertTrue(found, "the contract names the event")
    }

    /// Read from a run's output, the line lands on the trail under its course
    /// and section, and a line that is not a report leaves nothing.
    func testAReportLandsOnTheTrailUnderItsCourseAndSection() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try marker()["trailCases"] as? [[String: Any]])
        let line: String = try XCTUnwrap(cases.first?["line"] as? String)
        KeptDownloadsReport.noteOnTheTrail(from: "PLANTOIR_DOWNLOADED: {\"kind\":\"phet\"}\n" + line + "\n")
        let sentence: String = try XCTUnwrap(cases.first?["sentence"] as? String)
        XCTAssertTrue(trail.contains("SPH3U/1 · " + sentence), trail)
        var linesWritten: Int = 0
        for written in trail.components(separatedBy: "\n") {
            if written.contains(" · SPH3U/1 · ") || written.hasPrefix("SPH3U/1 · ") {
                linesWritten += 1
            }
        }
        XCTAssertEqual(linesWritten, 1, "the line with no count is not a report: " + trail)
    }

    /// The machine line never reaches the console a teacher reads.
    func testTheLineIsMachinery() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try marker()["cases"] as? [[String: Any]])
        for testCase in cases {
            let line: String = try XCTUnwrap(testCase["line"] as? String)
            XCTAssertTrue(KeptDownloadsReport.isMarkerLine(line))
            XCTAssertTrue(BuildMarkerLine.isMachineLine(line), line)
        }
    }

    /// The failure explanation's marker words are the contract's
    /// (`keptDownloads.stop.markerWords`, `markerWordsAlso`, `explained`).
    func testTheStopsMarkerWordsAreTheContracts() throws {
        let stop: [String: Any] = try XCTUnwrap(kept["stop"] as? [String: Any])
        XCTAssertEqual(
            FailureExplainer.keptDownloadsStopMarkers,
            [try XCTUnwrap(stop["markerWords"] as? String), try XCTUnwrap(stop["markerWordsAlso"] as? String)]
        )
        XCTAssertEqual(stop["explained"] as? String, FailureExplainer.keptDownloadsStopExplained)
        let first: [String: String] = try XCTUnwrap(stop["first"] as? [String: String])
        for (_, sentence) in first {
            for marker in FailureExplainer.keptDownloadsStopMarkers {
                XCTAssertTrue(sentence.contains(marker), sentence)
            }
        }
    }
}
