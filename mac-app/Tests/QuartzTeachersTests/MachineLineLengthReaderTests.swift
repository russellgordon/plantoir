import XCTest
@testable import QuartzTeachers

/// The build's machine lines are capped at 4,000 characters (#666): a
/// `PLANTOIR_DATED:`, `PLANTOIR_KEPT_OFF:` or `PLANTOIR_MAPS:` line that would
/// be longer keeps its first entries and adds `count` (the true total) and
/// `more`. These tests run `contracts/shared-rules.json` →
/// `machineLineLength.readerExamples` through the mac's three readers (#704),
/// by both of the paths a line reaches them: the console of a run the app
/// started, and a scheduled publish's own log. Windows runs the same rows
/// through its readers (`MachineLineLengthContractTests`).
///
/// Only the readers' existing surface is used — `reports(in:)`, `pages`,
/// `maps` and `trailSentence` — so this file compiles against the readers as
/// they were before #704, which is how it was proved to fail there.
@MainActor
final class MachineLineLengthReaderTests: XCTestCase {

    // MARK: - Stored properties

    private var rule: [String: Any] = [:]
    private var allRules: [String: Any] = [:]
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    /// What one reader made of one line: who it is about, how many entries
    /// the line itself carried, and the sentence it would write on the trail.
    private struct Reading {
        let course: String
        let section: Int
        let shown: Int
        let trailSentence: String
    }

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        allRules = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        rule = try XCTUnwrap(allRules["machineLineLength"] as? [String: Any])

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("machine-line-length-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Tests

    /// Every row, through the reader its marker belongs to and then through
    /// the real console reader: the right course and section, the entries the
    /// line carried, the TRUE count in the trail sentence — and the line kept
    /// out of the console a teacher reads.
    func testEveryReaderExampleIsReadWithItsTrueCount() throws {
        let examples: [[String: Any]] = try readerExamples()
        XCTAssertEqual(examples.count, 6,
                       "a readerExamples row was added or lost; contracts/README.md's census counts them, "
                       + "and a row added on Windows is a request for the mac to read it")

        for example in examples {
            guard let line = example["line"] as? String,
                  let expect = example["expect"] as? [String: Any],
                  let course = expect["course"] as? String,
                  let section = expect["section"] as? Int,
                  let shown = expect["shown"] as? Int,
                  let trailLine = expect["trailLine"] as? String else {
                XCTFail("a readerExamples row is missing a field: \(example)")
                continue
            }
            let readings: [Reading] = read(line)
            guard readings.count == 1, let reading = readings.first else {
                XCTFail("expected one report, got \(readings.count): \(line)")
                continue
            }
            XCTAssertEqual(reading.course, course, line)
            XCTAssertEqual(reading.section, section, line)
            XCTAssertEqual(reading.shown, shown, "the entries the line carries: \(line)")
            XCTAssertEqual(reading.trailSentence, trailLine, line)

            let runner: ScriptRunner = ScriptRunner()
            runner.receiveOutput(line + "\r\n")
            let console: String = runner.transcript.displayText
            XCTAssertFalse(console.contains("PLANTOIR_"), "the console showed a machine line: \(console)")
            let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
            XCTAssertTrue(trail.contains("\(course)/\(section) · \(trailLine)"),
                          "the console reader did not write the true count: \(trail)")
        }
    }

    /// A scheduled publish reads its build's lines out of its own log, by a
    /// second path (`ScheduledDeploy.recordFolderProblems`); a shortened line
    /// read there must say the same true count.
    func testAScheduledPublishReadsTheSameCount() throws {
        let examples: [[String: Any]] = try readerExamples()
        var lines: [String] = []
        var expected: [String] = []
        for example in examples {
            guard let line = example["line"] as? String,
                  let expect = example["expect"] as? [String: Any],
                  let course = expect["course"] as? String,
                  let section = expect["section"] as? Int,
                  let trailLine = expect["trailLine"] as? String else {
                XCTFail("a readerExamples row is missing a field: \(example)")
                continue
            }
            lines.append(line)
            expected.append("\(course)/\(section) · \(trailLine)")
        }

        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS4U", sectionNumber: 1) + ".0a1b2c3d"
        let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
        try FileManager.default.createDirectory(
            at: log.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let text: String = "Deploying ICS4U…\n" + lines.joined(separator: "\n") + "\nDeploy complete\n"
        try text.write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(
            label: label,
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS4U", sectionNumber: 1),
            fromByteOffset: 0,
            inHomeFolder: home
        )

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        for sentence in expected {
            XCTAssertTrue(trail.contains(sentence), "the scheduled log reader missed: \(sentence)\n\(trail)")
        }
    }

    /// Every marker the rule shortens has at least one row, and is a marker
    /// the mac reads — so a list added to the rule without a reader here, or
    /// without an example, is noticed.
    func testEveryListTheRuleNamesHasAReaderExample() throws {
        let lists: [String: Any] = try XCTUnwrap(rule["lists"] as? [String: Any])
        let macPrefixes: [String] = [
            PagesDatedByTheBuild.markerPrefix,
            HowITeachKeptOffReport.markerPrefix,
            CoverageMapsBuilt.markerPrefix
        ]
        let examples: [[String: Any]] = try readerExamples()
        for prefix in lists.keys {
            XCTAssertTrue(macPrefixes.contains(prefix), "the mac has no reader for \(prefix)")
            var hasRow: Bool = false
            for example in examples {
                if let line = example["line"] as? String, line.hasPrefix(prefix) {
                    hasRow = true
                }
            }
            XCTAssertTrue(hasRow, "no readerExamples row for \(prefix)")
        }
    }

    /// A line short enough to need no shortening carries no `count`, and is
    /// read exactly as before: every entry named, nothing "more" and nothing
    /// "not named".
    func testAWholeLineIsReadAsBefore() throws {
        let sections: [[String: Any]] = [
            try XCTUnwrap(try XCTUnwrap(allRules["pagesDatedByTheBuild"] as? [String: Any])["marker"] as? [String: Any]),
            try XCTUnwrap(try XCTUnwrap(allRules["howITeachPage"] as? [String: Any])["keptOffMarker"] as? [String: Any]),
            try XCTUnwrap(try XCTUnwrap(allRules["coverageMapsBuilt"] as? [String: Any])["marker"] as? [String: Any])
        ]
        var linesRead: Int = 0
        for marker in sections {
            let examples: [String] = try XCTUnwrap(marker["examples"] as? [String])
            for line in examples {
                let readings: [Reading] = read(line)
                XCTAssertEqual(readings.count, 1, line)
                for reading in readings {
                    linesRead += 1
                    XCTAssertFalse(reading.trailSentence.contains(" more"), reading.trailSentence)
                    XCTAssertFalse(reading.trailSentence.contains("not named"), reading.trailSentence)
                }
            }
        }
        XCTAssertEqual(linesRead, 4, "the three markers' whole-line examples: one dated, one kept off, two maps")
    }

    // MARK: - Functions

    private func readerExamples() throws -> [[String: Any]] {
        return try XCTUnwrap(rule["readerExamples"] as? [[String: Any]])
    }

    /// The line, through whichever of the three readers its marker belongs to.
    private func read(_ line: String) -> [Reading] {
        var readings: [Reading] = []
        if line.hasPrefix(PagesDatedByTheBuild.markerPrefix) {
            for report in PagesDatedByTheBuild.reports(in: line) {
                readings.append(Reading(course: report.course, section: report.section,
                                        shown: report.pages.count, trailSentence: report.trailSentence))
            }
        } else if line.hasPrefix(HowITeachKeptOffReport.markerPrefix) {
            for report in HowITeachKeptOffReport.reports(in: line) {
                readings.append(Reading(course: report.course, section: report.section,
                                        shown: report.pages.count, trailSentence: report.trailSentence))
            }
        } else if line.hasPrefix(CoverageMapsBuilt.markerPrefix) {
            for report in CoverageMapsBuilt.reports(in: line) {
                readings.append(Reading(course: report.course, section: report.section,
                                        shown: report.maps.count, trailSentence: report.trailSentence))
            }
        } else {
            XCTFail("no mac reader for this line: \(line)")
        }
        return readings
    }
}
