import XCTest
@testable import QuartzTeachers

/// When Plantoir has an updater at all (#204): only a released app launched
/// as an app. Everything here is read off the real bundle, the real
/// `project.yml` and the real source — the three places that could drift
/// from the contract without a behaviour test noticing.
@MainActor
final class AppUpdatesStartTests: XCTestCase {

    // MARK: - shouldStart

    func testNeverUnderTheSuite() {
        XCTAssertFalse(AppUpdates.shouldStart(
            infoDictionary: AppUpdatesStartTests.releaseShaped,
            arguments: ["/Applications/Plantoir.app/Contents/MacOS/Plantoir"],
            isRunningTests: true,
            headlessFlags: AppUpdates.headlessFlags
        ))
    }

    /// Each launch that is not an app, named by its own constant rather than
    /// retyped — so a renamed flag cannot leave this list behind.
    func testNeverForALaunchThatIsNotAnApp() {
        let flags: [String] = [AssistMCPServer.flag, ScheduledDeploy.runFlag, AssistContract.flag]
        XCTAssertEqual(AppUpdates.headlessFlags, flags)
        for flag in flags {
            XCTAssertFalse(
                AppUpdates.shouldStart(
                    infoDictionary: AppUpdatesStartTests.releaseShaped,
                    arguments: ["/Applications/Plantoir.app/Contents/MacOS/Plantoir", flag, "/somewhere"],
                    isRunningTests: false,
                    headlessFlags: AppUpdates.headlessFlags
                ),
                "\(flag) would start an updater"
            )
        }
    }

    func testNeverWithoutAFeed() {
        var withoutFeed: [String: Any] = AppUpdatesStartTests.releaseShaped
        withoutFeed.removeValue(forKey: "SUFeedURL")
        var emptyFeed: [String: Any] = AppUpdatesStartTests.releaseShaped
        emptyFeed["SUFeedURL"] = ""
        for info in [withoutFeed, emptyFeed] {
            XCTAssertFalse(AppUpdates.shouldStart(
                infoDictionary: info,
                arguments: ["Plantoir"],
                isRunningTests: false,
                headlessFlags: AppUpdates.headlessFlags
            ))
        }
    }

    func testARealisedReleaseLaunchStartsOne() {
        XCTAssertTrue(AppUpdates.shouldStart(
            infoDictionary: AppUpdatesStartTests.releaseShaped,
            arguments: ["/Applications/Plantoir.app/Contents/MacOS/Plantoir", "-NSDocumentRevisionsDebugMode", "YES"],
            isRunningTests: false,
            headlessFlags: AppUpdates.headlessFlags
        ))
    }

    /// The suite never creates one: nothing in it calls `start`, and the
    /// delegate is never reached with the updater running.
    func testTheSuiteHasNoUpdater() {
        XCTAssertFalse(AppUpdates.shared.hasAnUpdater)
        XCTAssertFalse(AppUpdates.shared.isRunning)
    }

    // MARK: - The bundle this suite runs in — a development build

    /// Decision 5: a development build never updates itself, because it
    /// carries no feed. Read off the test host, which IS the Debug app.
    func testADevelopmentBuildCarriesNoFeed() throws {
        let info: [String: Any] = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "ca.russellgordon.Plantoir", "Not the app's own bundle")
        let feed: String = try XCTUnwrap(info["SUFeedURL"] as? String, "The key must be there, and empty")
        XCTAssertEqual(feed, "")
    }

    /// Every other key is the same in both configurations, so it is checked
    /// here against the contract.
    func testAskFirstAndDailyAreInTheBundle() throws {
        let info: [String: Any] = try XCTUnwrap(Bundle.main.infoDictionary)
        let rules: [String: Any] = try AppUpdatesContractTests.appUpdates()

        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
        let installsWithoutAsking: Bool = try XCTUnwrap(rules["installsWithoutAsking"] as? Bool)
        XCTAssertEqual(info["SUAllowsAutomaticUpdates"] as? Bool, installsWithoutAsking)
        let interval: Int = try XCTUnwrap(rules["checkEverySeconds"] as? Int)
        XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, interval)
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        let key: String = try XCTUnwrap(info["SUPublicEDKey"] as? String)
        XCTAssertEqual(key, "lYt8VK8iKB4jMy+b06j1m+GAedeTChAbX5NkMW2FSMw=", "The public half of the plantoir-macos key (#204)")
        XCTAssertNil(
            info["SUEnableInstallerLauncherService"],
            "Plantoir is not sandboxed; that key would turn on a service fetch-sparkle.sh removes"
        )
        XCTAssertNotNil(
            Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: nil),
            "MIT: the updater's licence travels with the app"
        )
    }

    /// The Release feed in `project.yml` is the contract's, and Debug's is
    /// empty — so a feed moved in one place and not the other fails.
    func testTheReleaseFeedIsTheContractsAndDebugHasNone() throws {
        let text: String = try String(contentsOf: AppUpdatesStartTests.repositoryFile("mac-app/project.yml"), encoding: .utf8)
        let rules: [String: Any] = try AppUpdatesContractTests.appUpdates()
        let feeds: [String: Any] = try XCTUnwrap(rules["feed"] as? [String: Any])
        let mac: String = try XCTUnwrap(feeds["mac"] as? String)

        XCTAssertEqual(AppUpdatesStartTests.value(of: "PLANTOIR_UPDATE_FEED_URL", under: "Release:", in: text), mac)
        XCTAssertEqual(AppUpdatesStartTests.value(of: "PLANTOIR_UPDATE_FEED_URL", under: "Debug:", in: text), "")
    }

    // MARK: - Where it is created

    /// `start()` is called from ONE place, `applicationDidFinishLaunching`,
    /// which the assistant's server, a scheduled publish and writing the
    /// contracts never reach; and nothing of the updater is a stored property
    /// of the `App` struct, whose stored properties are made BEFORE `init()`
    /// turns those launches away.
    func testTheUpdaterIsCreatedOnlyAfterLaunching() throws {
        let product: URL = AppUpdatesStartTests.repositoryFile("mac-app/QuartzTeachers")
        var startCalls: [String] = []
        var updaterConstructions: [String] = []
        let enumerator = FileManager.default.enumerator(at: product, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            if file.pathExtension != "swift" {
                continue
            }
            let lines: [Substring] = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
            for line in lines {
                let trimmed: String = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") {
                    continue
                }
                if trimmed.contains("AppUpdates.shared.start()") {
                    startCalls.append(file.lastPathComponent)
                }
                if trimmed.contains("SPUUpdater(") || trimmed.contains("SPUStandardUpdaterController") {
                    updaterConstructions.append(file.lastPathComponent)
                }
            }
        }
        XCTAssertEqual(startCalls, ["AppDelegate.swift"])
        XCTAssertEqual(updaterConstructions, ["AppUpdates.swift"])

        let delegate: String = try String(
            contentsOf: product.appendingPathComponent("App/AppDelegate.swift"), encoding: .utf8
        )
        let launch: Range<String.Index> = try XCTUnwrap(delegate.range(of: "func applicationDidFinishLaunching"))
        let start: Range<String.Index> = try XCTUnwrap(delegate.range(of: "AppUpdates.shared.start()"))
        let next: Range<String.Index> = try XCTUnwrap(delegate.range(of: "func applicationSupportsSecureRestorableState"))
        XCTAssertTrue(launch.upperBound < start.lowerBound && start.upperBound < next.lowerBound)

        let app: String = try String(
            contentsOf: product.appendingPathComponent("App/QuartzTeachersApp.swift"), encoding: .utf8
        )
        XCTAssertFalse(app.contains("import Sparkle"))
        XCTAssertFalse(app.contains("AppUpdates()"))
        XCTAssertFalse(app.contains("SPU"))
    }

    /// A user-defaults feed would point a released copy anywhere — a
    /// development feed by another name (the plan review's M4). `start`
    /// clears it BEFORE the updater starts. A source scan, because the only
    /// behavioural test would write the app's real defaults domain.
    func testAUserDefaultsFeedIsClearedBeforeTheUpdaterStarts() throws {
        let source: String = try String(
            contentsOf: AppUpdatesStartTests.repositoryFile("mac-app/QuartzTeachers/App/AppUpdates.swift"),
            encoding: .utf8
        )
        let startFunction: Range<String.Index> = try XCTUnwrap(source.range(of: "func start() {"))
        let cleared: Range<String.Index> = try XCTUnwrap(
            source.range(of: "clearFeedURLFromUserDefaults()", range: startFunction.upperBound..<source.endIndex)
        )
        let started: Range<String.Index> = try XCTUnwrap(
            source.range(of: "try made.start()", range: startFunction.upperBound..<source.endIndex)
        )
        XCTAssertTrue(cleared.lowerBound < started.lowerBound, "The feed is cleared after the updater starts")
    }

    // MARK: - Helpers

    static let releaseShaped: [String: Any] = [
        "SUFeedURL": "https://plantoir.app/updates/macos.xml",
        "SUPublicEDKey": "lYt8VK8iKB4jMy+b06j1m+GAedeTChAbX5NkMW2FSMw="
    ]

    static func repositoryFile(_ relative: String) -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
    }

    /// The quoted value of `key` on the first line after `section`.
    static func value(of key: String, under section: String, in text: String) -> String? {
        let lines: [Substring] = text.split(separator: "\n", omittingEmptySubsequences: false)
        var inside: Bool = false
        for line in lines {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed == section {
                inside = true
                continue
            }
            if inside && trimmed.hasPrefix(key + ":") {
                let rest: String = String(trimmed.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
                return rest.replacingOccurrences(of: "\"", with: "")
            }
        }
        return nil
    }
}
