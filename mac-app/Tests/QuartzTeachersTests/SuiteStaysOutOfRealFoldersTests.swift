import XCTest
@testable import QuartzTeachers

/// The suite never reaches the teacher's own scheduled-deploy notes, agents
/// or assistant launch files — asked of the resolvers themselves, with every
/// override cleared, so a test that forgets to pass a home of its own is
/// still sent somewhere harmless (issue #240).
///
/// The same guard `BuildOutputLocationTests.testTheSuiteNeverBuildsIntoTheRealApplicationSupport`
/// keeps for built websites. Each case here was a real reach before the fix:
/// the success and findings sentinels were written and deleted for `ICS3U`
/// section 1, the `assist/` folder was written by both launcher doors, and
/// the agents folder was listed about 344 times in one run of the suite.
@MainActor
final class SuiteStaysOutOfRealFoldersTests: XCTestCase {

    // MARK: - Stored properties

    private var savedAgentsOverride: URL?
    private var savedScriptsOverride: URL?
    private var savedSupportOverride: URL?

    /// Where the teacher's own `Library` is, which nothing here may answer.
    private let realLibraryPath: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library").path

    // MARK: - Set-up

    override func setUp() {
        super.setUp()
        savedAgentsOverride = ScheduledDeploy.launchAgentsDirectoryOverride
        savedScriptsOverride = ScheduledDeploy.scheduledScriptsDirectoryOverride
        savedSupportOverride = ClaudeCodeLauncher.supportDirectoryOverride
        ScheduledDeploy.launchAgentsDirectoryOverride = nil
        ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        ClaudeCodeLauncher.supportDirectoryOverride = nil
    }

    override func tearDown() {
        ScheduledDeploy.launchAgentsDirectoryOverride = savedAgentsOverride
        ScheduledDeploy.scheduledScriptsDirectoryOverride = savedScriptsOverride
        ClaudeCodeLauncher.supportDirectoryOverride = savedSupportOverride
        super.tearDown()
    }

    // MARK: - The guards

    func testTheSuiteNeverTouchesTheRealScheduledNotes() {
        let success: URL = ScheduledDeploy.successSentinelURL(courseCode: "ICS3U", sectionNumber: 1)
        let findings: URL = ScheduledDeploy.findingsSentinelURL(courseCode: "ICS3U", sectionNumber: 1)
        let log: URL = ScheduledDeploy.logURL(courseCode: "ICS3U", sectionNumber: 1)
        let scripts: URL = ScheduledDeploy.scheduledScriptsDirectoryURL()

        XCTAssertFalse(success.path.hasPrefix(realLibraryPath), success.path)
        XCTAssertFalse(findings.path.hasPrefix(realLibraryPath), findings.path)
        XCTAssertFalse(log.path.hasPrefix(realLibraryPath), log.path)
        XCTAssertFalse(scripts.path.hasPrefix(realLibraryPath), scripts.path)

        // The stopped-run records: the sidebar's badge and the section's
        // notice read them whenever a window is built, and Dismiss deletes
        // one. They name their home explicitly, so this asks the home they
        // name rather than a resolver's default.
        let stopped: URL = ScheduledPublishOutcome.directory(inHomeFolder: ScheduledDeploy.homeForScheduledNotes)
        XCTAssertFalse(stopped.path.hasPrefix(realLibraryPath), stopped.path)
    }

    func testTheSuiteNeverReadsTheRealLaunchAgents() {
        let agents: URL = ScheduledDeploy.launchAgentsDirectoryURL()
        XCTAssertFalse(agents.path.hasPrefix(realLibraryPath), agents.path)
        let plist: URL = ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertFalse(plist.path.hasPrefix(realLibraryPath), plist.path)
    }

    func testTheSuiteNeverWritesTheRealAssistFolder() throws {
        let support: URL = try ClaudeCodeLauncher.supportDirectory()
        XCTAssertFalse(support.path.hasPrefix(realLibraryPath), support.path)
    }

    /// The redirect above would be DANGEROUS without this: a test that forgot
    /// the override would write its plist into the throwaway folder and then
    /// hand it to the real launchd. So the real launchctl refuses under the
    /// suite whether or not the override is set.
    func testTheRealLaunchControlRefusesEvenWithNoOverride() {
        let result = LaunchControl.run(arguments: ["print", "gui/501"])
        XCTAssertEqual(result.exitCode, -1)
        XCTAssertEqual(result.output, LaunchControl.refusedUnderATestRun)
    }

    // MARK: - The real rules, still pinned

    /// The redirect applies only when nobody names a home. A home named
    /// explicitly — as the app names the real one when it writes the script
    /// launchd will run — is used exactly.
    func testAHomeNamedExplicitlyIsUsedExactly() {
        let home: URL = URL(fileURLWithPath: "/Users/teacher", isDirectory: true)
        let label: String = ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1)

        XCTAssertEqual(
            ScheduledDeploy.successSentinelURL(courseCode: "ICS3U", sectionNumber: 1, inHomeFolder: home).path,
            "/Users/teacher/Library/Application Support/Plantoir/scheduled/\(label).succeeded"
        )
        XCTAssertEqual(
            ScheduledDeploy.findingsSentinelURL(courseCode: "ICS3U", sectionNumber: 1, inHomeFolder: home).path,
            "/Users/teacher/Library/Application Support/Plantoir/scheduled/\(label).findings"
        )
        XCTAssertEqual(
            ScheduledDeploy.logURL(courseCode: "ICS3U", sectionNumber: 1, inHomeFolder: home).path,
            "/Users/teacher/Library/Logs/Plantoir/\(label).log"
        )

        let script: String = ScheduledDeploy.oneShotCommand(
            courseCode: "ICS3U",
            sectionNumber: 1,
            workspaceURL: URL(fileURLWithPath: "/Users/teacher/Teaching"),
            deployArgumentsList: [["ICS3U", "1"]],
            homeFolder: home
        )
        XCTAssertTrue(
            script.contains("/Users/teacher/Library/Application Support/Plantoir/scheduled/\(label).succeeded"),
            "The script launchd runs must name the home it was given, not the suite's throwaway one."
        )
    }
}
