import XCTest
@testable import QuartzTeachers

/// The launchers' reports about a first run (GitHub #312) — which helper
/// programs were installed and where from, and how the website builder was
/// created — read the way the app reads them: out of the console as it
/// arrives and out of a scheduled publish's log, onto the activity trail, and
/// never into what a teacher sees.
///
/// Every sentence comes from `contracts/shared-rules.json` →
/// `activityTrail.mustRecord`, "helper programs installed" and "website
/// builder created". The launchers' half of the markers is checked against the
/// same entries by `scripts/test_helper_bootstrap.py`, which runs the real
/// first-run block, so the two halves cannot drift apart.
@MainActor
final class HelperBootstrapReportTests: XCTestCase {

    // MARK: - Stored properties

    private var installedEntry: [String: Any] = [:]
    private var createdEntry: [String: Any] = [:]
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let trail: [String: Any] = try XCTUnwrap(all["activityTrail"] as? [String: Any])
        let required: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        for candidate in required {
            if candidate["event"] as? String == ActivityTrail.Event.helperProgramsInstalled.rawValue {
                installedEntry = candidate
            }
            if candidate["event"] as? String == ActivityTrail.Event.websiteBuilderCreated.rawValue {
                createdEntry = candidate
            }
        }
        XCTAssertFalse(installedEntry.isEmpty, "the contract has no 'helper programs installed' event")
        XCTAssertFalse(createdEntry.isEmpty, "the contract has no 'website builder created' event")

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("helper-bootstrap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Functions

    private func line(_ entry: [String: Any], _ key: String) throws -> String {
        return try XCTUnwrap(entry[key] as? String, "the contract has no \(key)")
    }

    private func examples(_ entry: [String: Any]) throws -> [String] {
        let marker: [String: Any] = try XCTUnwrap(entry["marker"] as? [String: Any])
        return try XCTUnwrap(marker["examples"] as? [String])
    }

    private func words(_ entry: [String: Any], _ key: String) throws -> [String: String] {
        return try XCTUnwrap(entry[key] as? [String: String], "the contract has no \(key)")
    }

    private func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    // MARK: - Tests

    func testTheMarkersAndTheLinesAreTheContracts() throws {
        let installedMarker: [String: Any] = try XCTUnwrap(installedEntry["marker"] as? [String: Any])
        let createdMarker: [String: Any] = try XCTUnwrap(createdEntry["marker"] as? [String: Any])
        XCTAssertEqual(HelperBootstrapReport.installedMarkerPrefix, try XCTUnwrap(installedMarker["prefix"] as? String))
        XCTAssertEqual(HelperBootstrapReport.createdMarkerPrefix, try XCTUnwrap(createdMarker["prefix"] as? String))
        XCTAssertEqual(HelperBootstrapReport.lineWhenBundled, try line(installedEntry, "lineWhenBundled"))
        XCTAssertEqual(HelperBootstrapReport.lineWhenDownloaded, try line(installedEntry, "lineWhenDownloaded"))
        XCTAssertEqual(HelperBootstrapReport.whyWords, try words(installedEntry, "whyWords"))
        XCTAssertEqual(HelperBootstrapReport.whyNotWords, try words(installedEntry, "whyNotWords"))
        XCTAssertEqual(HelperBootstrapReport.lineWhenSeeded, try line(createdEntry, "lineWhenSeeded"))
        XCTAssertEqual(HelperBootstrapReport.lineWhenCreatedByDownloading, try line(createdEntry, "lineWhenDownloaded"))
        XCTAssertEqual(HelperBootstrapReport.lineWhenSeedRefused, try line(createdEntry, "lineWhenSeedRefused"))
        XCTAssertEqual(HelperBootstrapReport.lineWhenSeedFailed, try line(createdEntry, "lineWhenSeedFailed"))
    }

    func testBothEventsAreTheMacsAlone() throws {
        XCTAssertEqual(installedEntry["appliesOn"] as? [String], ["mac"])
        XCTAssertEqual(createdEntry["appliesOn"] as? [String], ["mac"])
    }

    func testEveryInstalledExampleIsUnderstood() throws {
        let lines: [String] = try examples(installedEntry)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(
            HelperBootstrapReport.reports(in: lines[0]),
            [HelperBootstrapReport(
                event: .helperProgramsInstalled,
                trailSentence: "set up Colima v0.10.3, Lima 2.2.0 and Docker CLI 29.7.2 for the website builder from inside Plantoir — not yet on this Mac"
            )]
        )
        XCTAssertEqual(
            HelperBootstrapReport.reports(in: lines[1]).first?.trailSentence,
            "set up Colima v0.10.3, Lima 2.2.0 and Docker CLI 29.7.2 for the website builder from inside Plantoir — replacing copies set up before Plantoir kept a record of them"
        )
        XCTAssertEqual(
            HelperBootstrapReport.reports(in: lines[2]).first?.trailSentence,
            "downloaded Buildx v0.36.1 for the website builder — not yet on this Mac; Plantoir's own copy was not used because this Plantoir does not carry one"
        )
        XCTAssertEqual(
            HelperBootstrapReport.reports(in: lines[3]).first?.trailSentence,
            "downloaded Docker CLI 29.7.2 for the website builder — replacing a damaged copy; Plantoir's own copy was not used because it did not pass its check"
        )
    }

    /// The bundled line and the downloaded line are the whole point of the
    /// event — a download that should have been a copy is the silent failure
    /// — so they must never be swapped.
    func testFromInsideAndDownloadedAreNeverConfused() throws {
        let pins: String = "colima=v0.10.3,lima=2.2.0,docker=29.7.2,buildx=v0.36.1"
        let bundled: [HelperBootstrapReport] = HelperBootstrapReport.reports(
            in: HelperBootstrapReport.installedMarkerPrefix + " bundled missing limactl " + pins
        )
        let downloaded: [HelperBootstrapReport] = HelperBootstrapReport.reports(
            in: HelperBootstrapReport.installedMarkerPrefix + " downloaded missing limactl " + pins + " other-arch"
        )
        XCTAssertTrue(bundled.first?.trailSentence.contains("from inside Plantoir") ?? false)
        XCTAssertFalse(bundled.first?.trailSentence.hasPrefix("downloaded") ?? true)
        XCTAssertTrue(downloaded.first?.trailSentence.hasPrefix("downloaded Lima 2.2.0") ?? false)
        XCTAssertTrue(downloaded.first?.trailSentence.contains("it is for another kind of Mac") ?? false)
    }

    func testEveryCreatedExampleIsUnderstood() throws {
        let lines: [String] = try examples(createdEntry)
        XCTAssertEqual(lines.count, 4)
        let seeded: String = try line(createdEntry, "lineWhenSeeded").replacingOccurrences(of: "{seconds}", with: "27")
        XCTAssertEqual(
            HelperBootstrapReport.reports(in: lines[0]),
            [HelperBootstrapReport(event: .websiteBuilderCreated, trailSentence: seeded)]
        )
        XCTAssertEqual(
            HelperBootstrapReport.reports(in: lines[1]).first?.trailSentence,
            try line(createdEntry, "lineWhenDownloaded").replacingOccurrences(of: "{seconds}", with: "41")
        )
        XCTAssertEqual(
            HelperBootstrapReport.reports(in: lines[2]).first?.trailSentence,
            try line(createdEntry, "lineWhenSeedRefused").replacingOccurrences(of: "{seconds}", with: "44")
        )
        XCTAssertEqual(
            HelperBootstrapReport.reports(in: lines[3]).first?.trailSentence,
            try line(createdEntry, "lineWhenSeedFailed").replacingOccurrences(of: "{seconds}", with: "255")
        )
    }

    /// Through the real runner, with the line ending real output uses: both
    /// lines land on the trail, and neither in the console a teacher reads.
    func testARunRecordsThemAndHidesTheLines() throws {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("📦 Getting what your website builder needs ready…\r\n")
        runner.receiveOutput(try examples(installedEntry)[0] + "\r\n")
        runner.receiveOutput("🚀 First start: setting up your website builder (6 CPUs · 12 GB of memory).\r\n")
        runner.receiveOutput(try examples(createdEntry)[0] + "\r\n")
        let shown: String = runner.transcript.displayText
        XCTAssertFalse(shown.contains(HelperBootstrapReport.installedMarkerPrefix), shown)
        XCTAssertFalse(shown.contains(HelperBootstrapReport.createdMarkerPrefix), shown)
        XCTAssertTrue(shown.contains("Getting what your website builder needs ready"), shown)
        XCTAssertTrue(trailText().contains("from inside Plantoir — not yet on this Mac"), trailText())
        XCTAssertTrue(trailText().contains("created the website builder from the starting disk inside Plantoir in 27 s"), trailText())
    }

    /// A scheduled publish is started by Plantoir itself, so it carries the
    /// app's helpers folder and can install from it while nobody watches.
    func testAScheduledPublishRecordsThemFromItsLog() throws {
        let home: URL = scratchFolderURL.appendingPathComponent("home", isDirectory: true)
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS4U", sectionNumber: 2) + ".0a1b2c3d"
        let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lastNight: String = try examples(createdEntry)[1] + "\n"
        let tonight: String = "Deploying ICS4U…\n" + (try examples(installedEntry)[3]) + "\n"
        try (lastNight + tonight).write(to: log, atomically: true, encoding: .utf8)

        ScheduledDeploy.recordFolderProblems(
            label: label,
            section: (courseDirectory: URL(fileURLWithPath: "/tmp"), courseCode: "ICS4U", sectionNumber: 2),
            fromByteOffset: UInt64(lastNight.utf8.count),
            inHomeFolder: home
        )

        XCTAssertTrue(trailText().contains("downloaded Docker CLI 29.7.2 for the website builder"), trailText())
        XCTAssertFalse(trailText().contains("in 41 s"), "an earlier night's line was recorded again")
    }

    /// #153's guards, for these markers too.
    func testAMarkerGluedOrCutIsReadAndHiddenAndNeverAQuestion() throws {
        let glued: String = "Building ICS4U" + (try examples(createdEntry)[2])
        XCTAssertEqual(HelperBootstrapReport.reports(in: glued).count, 1, glued)
        XCTAssertTrue(HelperBootstrapReport.isMarkerLine(glued))
        let half: String = "Building ICS4U " + HelperBootstrapReport.installedMarkerPrefix
        XCTAssertFalse(ScriptRunner.looksLikeQuestion(half), "a half-arrived marker ends in a colon")
        XCTAssertFalse(ScriptRunner.looksLikeQuestion(HelperBootstrapReport.createdMarkerPrefix))

        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(half)
        XCTAssertFalse(runner.transcript.displayText.contains(HelperBootstrapReport.installedMarkerPrefix))
        XCTAssertFalse(
            runner.transcript.recentText(maximumCharacters: 4000).contains(HelperBootstrapReport.installedMarkerPrefix)
        )
    }

    func testOrdinaryOutputAndBrokenLinesReportNothing() {
        let installed: String = HelperBootstrapReport.installedMarkerPrefix
        let created: String = HelperBootstrapReport.createdMarkerPrefix
        let pins: String = "colima=v0.10.3,lima=2.2.0,docker=29.7.2,buildx=v0.36.1"
        XCTAssertTrue(HelperBootstrapReport.reports(in: "📦 Getting what your website builder needs ready…").isEmpty)
        XCTAssertTrue(HelperBootstrapReport.reports(in: installed + " bundled missing colima").isEmpty)
        XCTAssertTrue(HelperBootstrapReport.reports(in: installed + " bundled lost colima " + pins).isEmpty)
        XCTAssertTrue(HelperBootstrapReport.reports(in: installed + " copied missing colima " + pins).isEmpty)
        XCTAssertTrue(HelperBootstrapReport.reports(in: installed + " bundled missing podman " + pins).isEmpty)
        XCTAssertTrue(HelperBootstrapReport.reports(in: installed + " downloaded missing colima " + pins).isEmpty,
                      "a download that does not say why the app's copy was not used")
        XCTAssertTrue(HelperBootstrapReport.reports(in: installed + " downloaded missing colima " + pins + " lost").isEmpty)
        XCTAssertTrue(HelperBootstrapReport.reports(in: installed + " bundled missing colima colima=v0.10.3").isEmpty == false,
                      "only the versions of the programs named are needed")
        XCTAssertTrue(HelperBootstrapReport.reports(in: installed + " bundled missing docker colima=v0.10.3").isEmpty)
        XCTAssertTrue(HelperBootstrapReport.reports(in: created + " seeded").isEmpty)
        XCTAssertTrue(HelperBootstrapReport.reports(in: created + " seeded soon").isEmpty)
        XCTAssertTrue(HelperBootstrapReport.reports(in: created + " grown 20").isEmpty)
        XCTAssertTrue(HelperBootstrapReport.reports(in: created + " seeded 20 extra").isEmpty)
    }
}
