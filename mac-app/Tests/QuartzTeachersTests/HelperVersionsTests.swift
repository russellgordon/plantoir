import XCTest
@testable import QuartzTeachers

/// The problem report's Helpers line says what is INSTALLED, measured, and
/// where it came from — never the versions the launchers would download,
/// stated as fact (issue #222).
///
/// Every measurement here runs STUB programs in a scratch folder, with a
/// `PATH` holding only that folder and `/usr/bin:/bin`. A test that inherited
/// the real `PATH` would find this Mac's own Homebrew programs and pass for
/// the wrong reason.
final class HelperVersionsTests: XCTestCase {

    // MARK: - Stored properties

    private var stubFolderURL: URL = URL(fileURLWithPath: "/")

    /// The shared measured answer as it was before each test, put back
    /// afterwards so nothing measured here reaches another test's record.
    private var previousMeasurement: String?

    // MARK: - Set-up

    override func setUpWithError() throws {
        stubFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("helper-stubs-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: stubFolderURL, withIntermediateDirectories: true)
        previousMeasurement = ProblemReportEnvironment.measuredHelperDescription
    }

    override func tearDownWithError() throws {
        ProblemReportEnvironment.measuredHelperDescription = previousMeasurement
        try? FileManager.default.removeItem(at: stubFolderURL)
    }

    // MARK: - Measuring

    func testTheHelpersLineReportsWhatIsInstalledNotWhatIsPinned() throws {
        try writeStub(named: "colima", body: "echo 'colima version 9.9.1'")
        try writeStub(named: "limactl", body: "echo 'limactl version 9.9.2'")
        try writeStub(
            named: "docker",
            body: """
            if [ "$1" = "buildx" ]; then echo 'github.com/docker/buildx v9.9.4 abcdef'; exit 0; fi
            echo 'Docker version 9.9.3, build x'
            """
        )

        let helpers: String = ProblemReportEnvironment.measureHelpers(
            environment: stubEnvironment(),
            toolsFolder: "/nonexistent/tools/bin"
        )

        XCTAssertTrue(helpers.contains("Docker CLI 9.9.3"), helpers)
        XCTAssertTrue(helpers.contains("Colima 9.9.1"), helpers)
        XCTAssertTrue(helpers.contains("Lima 9.9.2"), helpers)
        XCTAssertTrue(helpers.contains("Buildx 9.9.4"), helpers)
        XCTAssertFalse(helpers.contains("29.7.2"), helpers)
        XCTAssertTrue(helpers.hasPrefix("llama.cpp b10435 (Metal) · "), helpers)
    }

    func testMeasuringStoresNothingShared() throws {
        try writeStub(named: "colima", body: "echo 'colima version 9.9.1'")
        let before: String = ProblemReportEnvironment.helperDescription

        _ = ProblemReportEnvironment.measureHelpers(
            environment: stubEnvironment(),
            toolsFolder: "/nonexistent/tools/bin"
        )

        XCTAssertEqual(ProblemReportEnvironment.helperDescription, before)
        XCTAssertFalse(ProblemReportEnvironment.helperDescription.contains("9.9.1"))
    }

    func testAMissingHelperIsSaidToBeMissing() {
        let helpers: String = ProblemReportEnvironment.measureHelpers(
            environment: ["PATH": "/usr/bin:/bin", "HOME": stubFolderURL.path],
            toolsFolder: "/nonexistent/tools/bin"
        )

        XCTAssertTrue(helpers.contains("Colima not found (would install v0.10.3)"), helpers)
        XCTAssertTrue(helpers.contains("Lima not found (would install 2.2.0)"), helpers)
        XCTAssertTrue(helpers.contains("Docker CLI not found (would install 29.7.2)"), helpers)
        XCTAssertTrue(helpers.contains("Buildx not found (would install v0.36.1)"), helpers)
        XCTAssertFalse(helpers.contains("Colima v0.10.3 ·"), helpers)
    }

    /// A program that never answers must not hold the check up for ever.
    func testAHelperThatNeverAnswersDoesNotHoldTheCheckUp() throws {
        try writeStub(named: "colima", body: "sleep 8")
        let startedAt: Date = Date()

        let helpers: String = ProblemReportEnvironment.measureHelpers(
            environment: stubEnvironment(),
            toolsFolder: "/nonexistent/tools/bin",
            timeLimit: .seconds(1)
        )

        let elapsed: TimeInterval = Date().timeIntervalSince(startedAt)
        XCTAssertLessThan(elapsed, 4, "The check waited \(elapsed)s for a program that never answered.")
        XCTAssertTrue(helpers.contains("Colima not checked (pinned v0.10.3)"), helpers)
    }

    /// The check runs off the main thread, and only it stores the answer.
    /// Asserted, not believed: under approachable concurrency a plain
    /// `nonisolated async` function would run on the main actor.
    func testRefreshingMeasuresOffTheMainThreadAndRemembers() async throws {
        try writeStub(named: "colima", body: "echo 'colima version 9.9.1'")

        let measurement: HelperMeasurement = await ProblemReportEnvironment.refreshHelpers(
            environment: stubEnvironment(),
            toolsFolder: "/nonexistent/tools/bin"
        ).value

        XCTAssertFalse(measurement.ranOnTheMainThread)
        XCTAssertTrue(measurement.description.contains("Colima 9.9.1"), measurement.description)
        XCTAssertEqual(ProblemReportEnvironment.helperDescription, measurement.description)
    }

    // MARK: - Reading the output

    /// The four outputs measured on this Mac on 2026-09-23, all Homebrew's.
    func testRealOutputFromHomebrewReadsAsHomebrew() {
        let output: String = [
            "colima\tcolima version 0.10.3\t/opt/homebrew/bin/colima",
            "limactl\tlimactl version 2.2.0\t/opt/homebrew/bin/limactl",
            "docker\tDocker version 29.7.1, build e9452d6e78\t/opt/homebrew/bin/docker",
            "buildx\tgithub.com/docker/buildx v0.36.1 Homebrew\t",
            ""
        ].joined(separator: "\n")

        let helpers: String = ProblemReportEnvironment.helperDescription(
            fromProbeOutput: output,
            toolsFolder: "/Users/teacher/Library/Application Support/Plantoir/tools/bin"
        )

        XCTAssertEqual(
            helpers,
            "llama.cpp b10435 (Metal) · Colima 0.10.3 (Homebrew) · Lima 2.2.0 (Homebrew) · Docker CLI 29.7.1 (Homebrew) · Buildx 0.36.1 (Homebrew)"
        )
    }

    func testPlantoirsOwnCopyIsNamedWithoutItsPath() {
        let toolsFolder: String = "/Users/teacher/Library/Application Support/Plantoir/tools/bin"
        let output: String = [
            "colima\tcolima version 0.10.3\t" + toolsFolder + "/colima",
            "limactl\tlimactl version 2.2.0\t" + toolsFolder + "/limactl",
            "docker\tDocker version 29.7.2, build 1234567\t" + toolsFolder + "/docker",
            "buildx\tgithub.com/docker/buildx v0.36.1 0123abc\t"
        ].joined(separator: "\n")

        let helpers: String = ProblemReportEnvironment.helperDescription(
            fromProbeOutput: output,
            toolsFolder: toolsFolder
        )

        XCTAssertEqual(
            helpers,
            "llama.cpp b10435 (Metal) · Colima 0.10.3 (Plantoir's copy) · Lima 2.2.0 (Plantoir's copy) · Docker CLI 29.7.2 (Plantoir's copy) · Buildx 0.36.1"
        )
        XCTAssertFalse(helpers.contains("teacher"), helpers)
    }

    /// `/usr/local/bin` is Intel Homebrew's folder AND where Docker Desktop
    /// puts its link; only where the link leads tells them apart.
    func testALinkIntoAnotherAppIsNotCalledHomebrew() {
        let output: String = "docker\tDocker version 28.0.1, build abc\t/usr/local/bin/docker\n"

        let helpers: String = ProblemReportEnvironment.helperDescription(
            fromProbeOutput: output,
            toolsFolder: "/Users/teacher/Library/Application Support/Plantoir/tools/bin",
            resolvingLinks: { path in
                if path == "/usr/local/bin/docker" {
                    return "/Applications/Docker.app/Contents/Resources/bin/docker"
                }
                return path
            }
        )

        XCTAssertTrue(helpers.contains("Docker CLI 28.0.1 (found in /usr/local/bin)"), helpers)

        let intelHomebrew: String = ProblemReportEnvironment.helperDescription(
            fromProbeOutput: output,
            toolsFolder: "/Users/teacher/Library/Application Support/Plantoir/tools/bin",
            resolvingLinks: { path in
                return "/usr/local/Cellar/docker/28.0.1/bin/docker"
            }
        )
        XCTAssertTrue(intelHomebrew.contains("Docker CLI 28.0.1 (Homebrew)"), intelHomebrew)
    }

    func testNothingThatReadsAsAVersionIsNotFound() {
        let output: String = [
            "colima\t\t",
            "limactl\tlimactl: something went wrong\t/opt/homebrew/bin/limactl",
            "docker\t\t",
            "buildx\tdocker: 'buildx' is not a docker command.\t"
        ].joined(separator: "\n")

        let helpers: String = ProblemReportEnvironment.helperDescription(
            fromProbeOutput: output,
            toolsFolder: "/nonexistent"
        )

        XCTAssertTrue(helpers.contains("Colima not found (would install v0.10.3)"), helpers)
        XCTAssertTrue(helpers.contains("Lima found, version unreadable (Homebrew)"), helpers)
        XCTAssertTrue(helpers.contains("Docker CLI not found (would install 29.7.2)"), helpers)
        XCTAssertTrue(helpers.contains("Buildx not found (would install v0.36.1)"), helpers)
    }

    func testAnEmptyAnswerSaysNothingWasChecked() {
        let helpers: String = ProblemReportEnvironment.helperDescription(
            fromProbeOutput: "",
            toolsFolder: "/nonexistent"
        )

        for helper in ProblemReportEnvironment.pinnedHelpers {
            XCTAssertTrue(
                helpers.contains(helper.displayName + " not checked (pinned " + helper.pinnedVersion + ")"),
                helpers
            )
        }
    }

    func testVersionNumbersAreReadFromEachShapeOfLine() {
        XCTAssertEqual(ProblemReportEnvironment.versionNumber(in: "colima version 0.10.3"), "0.10.3")
        XCTAssertEqual(ProblemReportEnvironment.versionNumber(in: "Docker version 29.7.1, build e9452d6e78"), "29.7.1")
        XCTAssertEqual(ProblemReportEnvironment.versionNumber(in: "github.com/docker/buildx v0.36.1 Homebrew"), "0.36.1")
        XCTAssertNil(ProblemReportEnvironment.versionNumber(in: "docker: 'buildx' is not a docker command."))
        XCTAssertNil(ProblemReportEnvironment.versionNumber(in: ""))
    }

    /// A folder found under the home folder reaches the trail without the
    /// teacher's account name — the trail redacts on the way in.
    func testAFolderUnderTheHomeFolderIsRedactedOnTheTrail() throws {
        let scratchURL: URL = stubFolderURL.appendingPathComponent("trail", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchURL)
        defer { ActivityTrail.store = previousStore }

        let helpers: String = ProblemReportEnvironment.helperDescription(
            fromProbeOutput: "colima\tcolima version 0.10.3\t/Users/somebodyelse/bin/colima\n",
            toolsFolder: "/nonexistent"
        )
        ActivityTrail.noteHelpers(helpers)

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("Colima 0.10.3 (found in /Users/"), trail)
        XCTAssertFalse(trail.contains("somebodyelse"), trail)
    }

    // MARK: - The pins

    /// The unmeasured line names what the launchers would download, so the
    /// two must not drift: `setup.sh` is where the downloads are pinned.
    func testThePinnedVersionsAreTheOnesSetupDownloads() throws {
        let setupURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac-app
            .deletingLastPathComponent()   // repository
            .appendingPathComponent("setup.sh")
        let setupText: String = try String(contentsOf: setupURL, encoding: .utf8)

        for helper in ProblemReportEnvironment.pinnedHelpers {
            let pinLine: String = helper.setupVariable + "=\"" + helper.pinnedVersion + "\""
            XCTAssertTrue(
                setupText.contains(pinLine),
                "setup.sh no longer carries \(pinLine) — the Helpers line would name a version the launchers do not download."
            )
        }
    }

    // MARK: - Functions

    private func stubEnvironment() -> [String: String] {
        return ["PATH": stubFolderURL.path + ":/usr/bin:/bin", "HOME": stubFolderURL.path]
    }

    private func writeStub(named name: String, body: String) throws {
        let url: URL = stubFolderURL.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
