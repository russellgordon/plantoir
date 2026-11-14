import XCTest
@testable import QuartzTeachers

/// The build's report of which course files its site leaves off, and what the
/// check after the build put right (#901), read the way the app reads it: out
/// of the console and a scheduled deploy's log, onto the activity trail as
/// `site leaves off files no published page uses`.
///
/// Every value comes from `contracts/shared-rules.json` → `siteFiles.marker`
/// (`prefix`, `trailCases`) and the event's `mustRecord` entry;
/// `scripts/test_site_files.py` checks the Python prints exactly each
/// case's line, so the two halves cannot drift.
@MainActor
final class SiteFilesReportTests: XCTestCase {

    // MARK: - Stored properties

    private var marker: [String: Any] = [:]
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
        let siteFiles: [String: Any] = try XCTUnwrap(all["siteFiles"] as? [String: Any])
        marker = try XCTUnwrap(siteFiles["marker"] as? [String: Any])
        let activityTrail: [String: Any] = try XCTUnwrap(all["activityTrail"] as? [String: Any])
        mustRecord = try XCTUnwrap(activityTrail["mustRecord"] as? [[String: Any]])
        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("site-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Functions

    private func trailCases() throws -> [[String: Any]] {
        return try XCTUnwrap(marker["trailCases"] as? [[String: Any]])
    }

    private func entry() throws -> [String: Any] {
        for candidate in mustRecord {
            if candidate["event"] as? String == ActivityTrail.Event.siteLeavesOffFilesNoPublishedPageUses.rawValue {
                return candidate
            }
        }
        XCTFail("the contract does not name the event")
        return [:]
    }

    func testThePrefixIsTheContracts() throws {
        XCTAssertEqual(marker["prefix"] as? String, SiteFilesReport.markerPrefix)
    }

    /// Every trail case: whether it is written, and the sentence, word for word.
    func testEveryTrailCaseIsReadAsTheContractSays() throws {
        let cases: [[String: Any]] = try trailCases()
        XCTAssertGreaterThanOrEqual(cases.count, 9)
        for testCase in cases {
            let line: String = try XCTUnwrap(testCase["line"] as? String)
            let reports: [SiteFilesReport] = SiteFilesReport.reports(in: "🏗️ Building\n" + line + "\n")
            XCTAssertEqual(reports.count, 1, line)
            let report: SiteFilesReport = try XCTUnwrap(reports.first)
            XCTAssertEqual(report.isWorthWriting, testCase["written"] as? Bool, line)
            if let sentence = testCase["sentence"] as? String {
                XCTAssertEqual(report.trailSentence, sentence, line)
            }
        }
    }

    /// The sentence is the contract's line with the counts filled in, in both
    /// of its shapes, with the parts said only when their count is above zero
    /// (`notZero`) present exactly when it is.
    func testTheSentencesAreTheContractsLines() throws {
        let found: [String: Any] = try entry()
        let line: String = try XCTUnwrap(found["line"] as? String)
        let sorted: String = try XCTUnwrap(found["lineWhenSortedAfterTheBuild"] as? String)
        let notZero: [String: Any] = try XCTUnwrap(found["notZero"] as? [String: Any])
        let failedPart: String = try XCTUnwrap(notZero["putBackFailed"] as? String)
        let keptPart: String = try XCTUnwrap(notZero["kept"] as? String)
        let filled: (String, String) -> String = { (template: String, parts: String) -> String in
            return template
                .replacingOccurrences(of: "{course}/{section} · ", with: "")
                .replacingOccurrences(of: "{leftOff}", with: "7")
                .replacingOccurrences(of: "{putBack}", with: "1")
                .replacingOccurrences(of: "{takenOut}", with: "2")
                .replacingOccurrences(of: "{notZero}", with: parts)
        }
        let plain: SiteFilesReport = SiteFilesReport(
            course: "SCH3U", section: 2, leftOff: 7, putBack: 1, putBackFailed: 0, takenOut: 2,
            unreferenced: 0, firstTime: false, changed: true, assetsEmitter: "plantoir"
        )
        XCTAssertEqual(plain.trailSentence, filled(line, ""))
        let both: SiteFilesReport = SiteFilesReport(
            course: "SCH3U", section: 2, leftOff: 7, putBack: 1, putBackFailed: 3, takenOut: 2,
            unreferenced: 4, firstTime: false, changed: true, assetsEmitter: "plantoir"
        )
        // Four no page names, two of them taken out: two kept (notZero.keptRule).
        let bothParts: String = failedPart.replacingOccurrences(of: "{putBackFailed}", with: "3")
            + keptPart.replacingOccurrences(of: "{kept}", with: "2")
        XCTAssertEqual(both.trailSentence, filled(line, bothParts))
        let quartz: SiteFilesReport = SiteFilesReport(
            course: "SCH3U", section: 2, leftOff: 7, putBack: 1, putBackFailed: 0, takenOut: 2,
            unreferenced: 4, firstTime: false, changed: true, assetsEmitter: SiteFilesReport.quartzsOwnEmitter
        )
        let quartzParts: String = keptPart.replacingOccurrences(of: "{kept}", with: "2")
        XCTAssertEqual(quartz.trailSentence, filled(sorted, quartzParts))
        // Every file no page names was taken out: nothing is kept, so nothing
        // is said about it (901a fix review, M2).
        let allTakenOut: SiteFilesReport = SiteFilesReport(
            course: "SCH3U", section: 2, leftOff: 7, putBack: 1, putBackFailed: 0, takenOut: 2,
            unreferenced: 2, firstTime: false, changed: true, assetsEmitter: "plantoir"
        )
        XCTAssertEqual(allTakenOut.keptBecauseMentioned, 0)
        XCTAssertEqual(allTakenOut.trailSentence, filled(line, ""))
    }

    /// A file no page names that is still on the site (the site's text
    /// mentions it, so the check kept it) is written even when nothing else
    /// changed: it is what a problem report needs.
    func testAFileNoPageNamesIsWorthWriting() throws {
        let kept: SiteFilesReport = SiteFilesReport(
            course: "SCH3U", section: 2, leftOff: 12, putBack: 0, putBackFailed: 0, takenOut: 0,
            unreferenced: 1, firstTime: false, changed: false, assetsEmitter: "plantoir"
        )
        XCTAssertTrue(kept.isWorthWriting)
        let quiet: SiteFilesReport = SiteFilesReport(
            course: "SCH3U", section: 2, leftOff: 12, putBack: 0, putBackFailed: 0, takenOut: 0,
            unreferenced: 0, firstTime: false, changed: false, assetsEmitter: "plantoir"
        )
        XCTAssertFalse(quiet.isWorthWriting)
    }

    /// Read from a run's output, a line worth writing lands on the trail under
    /// its course and section; one that is not, and one with no count, leave
    /// nothing.
    func testAReportLandsOnTheTrailUnderItsCourseAndSection() throws {
        var written: String = ""
        var quiet: String = ""
        for testCase in try trailCases() {
            let line: String = try XCTUnwrap(testCase["line"] as? String)
            if testCase["written"] as? Bool == true && written.isEmpty {
                written = line
            }
            if testCase["written"] as? Bool == false && quiet.isEmpty {
                quiet = line
            }
        }
        XCTAssertFalse(written.isEmpty)
        XCTAssertFalse(quiet.isEmpty)
        SiteFilesReport.noteOnTheTrail(from: "PLANTOIR_SITE_FILES: {\"course\":\"SCH3U\"}\n" + quiet + "\n" + written + "\n")
        let report: SiteFilesReport = try XCTUnwrap(SiteFilesReport.reports(in: written).first)
        XCTAssertTrue(trail.contains("SCH3U/2 · " + report.trailSentence), trail)
        var linesWritten: Int = 0
        for line in trail.components(separatedBy: "\n") {
            if line.contains("SCH3U/2 · ") {
                linesWritten += 1
            }
        }
        XCTAssertEqual(linesWritten, 1, trail)
    }

    /// The machine line never reaches the console a teacher reads.
    func testTheLineIsMachinery() throws {
        for testCase in try trailCases() {
            let line: String = try XCTUnwrap(testCase["line"] as? String)
            XCTAssertTrue(SiteFilesReport.isMarkerLine(line))
            XCTAssertTrue(BuildMarkerLine.isMachineLine(line), line)
        }
    }

    /// What the trail keeps passes through the problem report's redactor
    /// unchanged: it carries counts and a course code, nothing to take out.
    func testTheTrailLinePassesTheRedactorUnchanged() throws {
        for testCase in try trailCases() {
            guard let sentence = testCase["sentence"] as? String else {
                continue
            }
            let line: String = "2026-11-14 09:00:00 · SCH3U/2 · " + sentence
            XCTAssertEqual(LogRedactor.redacting(line), line)
        }
    }
}
