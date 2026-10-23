import XCTest
@testable import QuartzTeachers

/// preview.sh's report of how getting Swift ready ended (#635), read the way
/// the app reads it: out of the console as it arrives and out of a scheduled
/// publish's log, onto the activity trail as `Swift got ready on this
/// computer` or `Swift could not be got ready`, and out of what a teacher sees.
///
/// Every value comes from `contracts/shared-rules.json` → the two events'
/// `mustRecord` entries and `codeRunnerBlocks.swift` (`windows.marker` and
/// `mac.example`); `scripts/test_swift_blocks.py` checks the launcher's Python
/// writes exactly `mac.example`, so the two halves cannot drift.
@MainActor
final class SwiftGotReadyReportTests: XCTestCase {

    // MARK: - Stored properties

    private var swift: [String: Any] = [:]
    private var gotReady: [String: Any] = [:]
    private var couldNot: [String: Any] = [:]
    private var machineLines: [String: Any] = [:]
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
        let runners: [String: Any] = try XCTUnwrap(all["codeRunnerBlocks"] as? [String: Any])
        swift = try XCTUnwrap(runners["swift"] as? [String: Any])
        let activityTrail: [String: Any] = try XCTUnwrap(all["activityTrail"] as? [String: Any])
        let mustRecord: [[String: Any]] = try XCTUnwrap(activityTrail["mustRecord"] as? [[String: Any]])
        for entry in mustRecord {
            if entry["event"] as? String == ActivityTrail.Event.swiftGotReady.rawValue {
                gotReady = entry
            }
            if entry["event"] as? String == ActivityTrail.Event.swiftCouldNotBeGotReady.rawValue {
                couldNot = entry
            }
        }
        let stripping: [String: Any] = try XCTUnwrap(all["transcriptStripping"] as? [String: Any])
        machineLines = try XCTUnwrap(stripping["machineLines"] as? [String: Any])

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-got-ready-\(UUID().uuidString)", isDirectory: true)
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
        let windows: [String: Any] = try XCTUnwrap(swift["windows"] as? [String: Any])
        return try XCTUnwrap(windows["marker"] as? [String: Any])
    }

    /// Windows' two examples and the Mac's one.
    private func examples() throws -> [String] {
        var found: [String] = try XCTUnwrap(try marker()["examples"] as? [String])
        let mac: [String: Any] = try XCTUnwrap(swift["mac"] as? [String: Any])
        found.append(try XCTUnwrap(mac["example"] as? String))
        return found
    }

    private func macExample() throws -> String {
        let mac: [String: Any] = try XCTUnwrap(swift["mac"] as? [String: Any])
        return try XCTUnwrap(mac["example"] as? String)
    }

    /// The event's `line`, filled from the marker's own JSON the way the
    /// contract describes it: gigabytes are bytes / 10⁹ with one decimal.
    private func expectedLine(for markerLine: String) throws -> String {
        let payload: String = try XCTUnwrap(markerLine.components(separatedBy: "PLANTOIR_SWIFT:").last)
        let object: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        let course: String = try XCTUnwrap(object["course"] as? String)
        let section: Int = try XCTUnwrap(object["section"] as? Int)
        if try XCTUnwrap(object["ready"] as? Bool) {
            let template: String = try XCTUnwrap(gotReady["line"] as? String)
            let bytes: Double = try XCTUnwrap(object["downloadedBytes"] as? Double)
            let seconds: Int = try XCTUnwrap(object["seconds"] as? Int)
            let tenths: Int = Int((bytes / 100_000_000).rounded())
            let gigabytes: String = "\(tenths / 10).\(tenths % 10)"
            return template
                .replacingOccurrences(of: "{course}", with: course)
                .replacingOccurrences(of: "{section}", with: String(section))
                .replacingOccurrences(of: "{seconds}", with: String(seconds))
                .replacingOccurrences(of: "{gigabytes}", with: gigabytes)
        }
        let template: String = try XCTUnwrap(couldNot["line"] as? String)
        let words: [String: String] = try XCTUnwrap(couldNot["whyWords"] as? [String: String])
        let reason: String = try XCTUnwrap(object["reason"] as? String)
        return template
            .replacingOccurrences(of: "{course}", with: course)
            .replacingOccurrences(of: "{section}", with: String(section))
            .replacingOccurrences(of: "{why}", with: try XCTUnwrap(words[reason]))
    }

    private func count(of words: String, in text: String) -> Int {
        return text.components(separatedBy: words).count - 1
    }

    // MARK: - The contract's values

    func testThePrefixAndTheWordsAreTheContracts() throws {
        XCTAssertEqual(SwiftGotReadyReport.markerPrefix, try XCTUnwrap(try marker()["prefix"] as? String),
                       "the app would stop hearing how getting Swift ready ended")
        let words: [String: String] = try XCTUnwrap(couldNot["whyWords"] as? [String: String])
        XCTAssertEqual(SwiftGotReadyReport.whyWords, words)
    }

    func testEveryExampleIsWrittenAsTheEventsLine() throws {
        for example in try examples() {
            let reports: [SwiftGotReadyReport] = SwiftGotReadyReport.reports(in: "building\n" + example + "\n")
            XCTAssertEqual(reports.count, 1, example)
            SwiftGotReadyReport.noteOnTheTrail(from: example)
            let expected: String = try expectedLine(for: example)
            XCTAssertEqual(count(of: expected, in: trail), 1, "\(expected)\n\(trail)")
            XCTAssertFalse(ScriptRunner.looksLikeQuestion(example))
        }
        let examples: [String] = try examples()
        XCTAssertEqual(SwiftGotReadyReport.reports(in: examples[0]).first?.event, .swiftGotReady)
        XCTAssertEqual(SwiftGotReadyReport.reports(in: examples[1]).first?.event, .swiftCouldNotBeGotReady)
    }

    func testACachedRebuildSaysNothingWasDownloaded() throws {
        let line: String = "PLANTOIR_SWIFT: {\"course\": \"ICS3U\", \"downloadedBytes\": 0, \"ready\": true, "
            + "\"seconds\": 6, \"section\": 2}"
        SwiftGotReadyReport.noteOnTheTrail(from: line)
        let expected: String = try expectedLine(for: line)
        XCTAssertTrue(expected.contains("0.0 GB"), expected)
        XCTAssertEqual(count(of: expected, in: trail), 1, trail)
    }

    func testTheConsoleRuleHidesTheLine() throws {
        let cases: [[String: Any]] = try XCTUnwrap(machineLines["cases"] as? [[String: Any]])
        var listed: Bool = false
        for entry in cases {
            if entry["line"] as? String == (try macExample()) {
                listed = entry["hidden"] as? Bool == true
            }
        }
        XCTAssertTrue(listed, "transcriptStripping.machineLines should carry the marker's line, hidden")
        for example in try examples() {
            XCTAssertTrue(BuildMarkerLine.isMachineLine(example), example)
            XCTAssertTrue(SwiftGotReadyReport.isMarkerLine("🦅 Making…" + example))
        }
    }

    func testAnUnknownReasonIsWrittenAsItsKeyAndABrokenLineLeavesNothing() {
        let newer: String = "PLANTOIR_SWIFT: {\"course\": \"ICS3U\", \"ready\": false, \"reason\": \"somethingNewer\", "
            + "\"section\": 1}"
        SwiftGotReadyReport.noteOnTheTrail(from: newer)
        XCTAssertTrue(trail.contains("ICS3U/1 · Swift could not be got ready on this computer: somethingNewer"), trail)

        XCTAssertTrue(SwiftGotReadyReport.reports(in: "PLANTOIR_SWIFT: {not json").isEmpty)
        XCTAssertTrue(SwiftGotReadyReport.reports(in: "PLANTOIR_SWIFT: {\"course\": \"ICS3U\", \"section\": 1}").isEmpty,
                      "a line with no ready is not a report")
        XCTAssertTrue(SwiftGotReadyReport.reports(in: "PLANTOIR_SWIFT: {\"ready\": false, \"section\": 1}").isEmpty,
                      "a failure with no reason is not a report")
        XCTAssertTrue(SwiftGotReadyReport.reports(in: "✅ Swift is ready.").isEmpty)
    }

    func testALineThatNamesNoCourseIsWrittenWithoutOne() throws {
        let line: String = "PLANTOIR_SWIFT: {\"ready\": false, \"reason\": \"waited\"}"
        let report: SwiftGotReadyReport = try XCTUnwrap(SwiftGotReadyReport.reports(in: line).first)
        XCTAssertNil(report.course)
        SwiftGotReadyReport.noteOnTheTrail(from: line)
        XCTAssertEqual(count(of: report.trailSentence, in: trail), 1, trail)
        XCTAssertFalse(trail.contains("/"), "a course and section were made up: \(trail)")
    }

    func testAMarkerGluedToHalfALineIsRead() throws {
        let glued: String = "🦅 Making 2 Swift programs ready to r" + (try macExample())
        XCTAssertEqual(SwiftGotReadyReport.reports(in: glued).count, 1)
    }

    // MARK: - Through the real readers

    /// Through the real runner, with real line endings: the line lands on the
    /// trail once, and the marker never reaches the console a teacher reads.
    func testARunRecordsItAndHidesTheMarker() throws {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("✅ Swift is ready.\r\n")
        runner.receiveOutput(try macExample() + "\r\n")
        runner.receiveOutput("ok\r\n")
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains("PLANTOIR_SWIFT"), shown)
        XCTAssertTrue(shown.contains("Swift is ready."), shown)
        XCTAssertEqual(count(of: try expectedLine(for: try macExample()), in: trail), 1, trail)
    }

    /// A scheduled publish's build writes to the run's own log, read once the
    /// run is done: the line is recorded from there, and an earlier night's
    /// line before the offset is not recorded again.
    func testAScheduledPublishRecordsItFromItsLog() throws {
        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS3U", sectionNumber: 1) + ".0a1b2c3d"
        let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
        try FileManager.default.createDirectory(
            at: log.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let lastNight: String = "PLANTOIR_SWIFT: {\"course\": \"ICS3U\", \"ready\": false, \"reason\": \"offline\", "
            + "\"section\": 1}\n"
        let tonight: String = "Building ICS3U…\n" + (try macExample()) + "\nDeploy complete\n"
        try (lastNight + tonight).write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(
            label: label,
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS3U", sectionNumber: 1),
            fromByteOffset: UInt64(lastNight.utf8.count),
            inHomeFolder: home
        )

        XCTAssertEqual(count(of: try expectedLine(for: try macExample()), in: trail), 1, trail)
        XCTAssertFalse(trail.contains(SwiftGotReadyReport.whyWords["offline"] ?? "?"),
                       "an earlier night's line was recorded again")
    }
}
