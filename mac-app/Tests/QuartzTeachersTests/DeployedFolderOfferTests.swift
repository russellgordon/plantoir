import XCTest
@testable import QuartzTeachers

/// When a deployed folder can be opened in the browser, what it is called,
/// where the folder is, and which address it gets (#850):
/// `contracts/shared-rules.json` → `deployedFolderInBrowser` (`offeredCases`,
/// `wording`, `address`) and `folderPublishTarget.cases`, run rather than
/// retyped. Also the app-wide record: opening twice starts one show, Stop
/// ends it, and each leaves its trail line.
@MainActor
final class DeployedFolderOfferTests: XCTestCase {

    // MARK: - Functions

    static func section() throws -> [String: Any] {
        return try SharedRulesContractTests.section("deployedFolderInBrowser")
    }

    // MARK: - Tests: the contract

    func testEveryOfferedCaseDecidesAsTheContractSays() throws {
        let section: [String: Any] = try DeployedFolderOfferTests.section()
        let defaults: [String: Any] = try XCTUnwrap(section["offeredDefaults"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(section["offeredCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let given: [String: Any] = try XCTUnwrap(testCase["given"] as? [String: Any])
            var merged: [String: Any] = defaults
            for (key, value) in given {
                XCTAssertNotNil(defaults[key], "\(name): \(key) has no default")
                merged[key] = value
            }
            var facts: DeployedFolderOffer.Facts = DeployedFolderOffer.Facts()
            facts.hasFolderDestination = try XCTUnwrap(merged["hasFolderDestination"] as? Bool)
            facts.keptForReference = try XCTUnwrap(merged["keptForReference"] as? Bool)
            facts.deployIsRunning = try XCTUnwrap(merged["deployIsRunning"] as? Bool)
            facts.folderExists = try XCTUnwrap(merged["folderExists"] as? Bool)
            facts.sectionIndexExists = try XCTUnwrap(merged["sectionIndexExists"] as? Bool)

            let expected: DeployedFolderOffer.Decision
            if let word = testCase["expect"] as? String {
                expected = word == "offered" ? .offered : .absent
                XCTAssertTrue(word == "offered" || word == "absent", "\(name): \(word)")
            } else {
                let greyed: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
                let key: String = try XCTUnwrap(greyed["greyed"] as? String)
                expected = .greyed(reasonKey: key)
                XCTAssertNotNil(DeployedFolderOffer.sentence(forReasonKey: key), "\(name): no sentence for \(key)")
            }
            XCTAssertEqual(DeployedFolderOffer.decide(facts), expected, name)
        }
    }

    func testTheWordingIsTheContractsKeyByKey() throws {
        let section: [String: Any] = try DeployedFolderOfferTests.section()
        let wording: [String: String] = try XCTUnwrap(section["wording"] as? [String: String])
        XCTAssertEqual(wording, DeployedFolderWording.everyKey)
        XCTAssertEqual(DeployedFolderWording.notice(section: 3).contains("{section}"), false)
        XCTAssertEqual(DeployedFolderWording.menuItem, DeployedFolderWording.resultButton,
                       "one Open in Browser for both (Russell, 2026-11-13)")
    }

    /// The app finds a section's folder where `deploy.sh --to-folder` puts it.
    func testTheFolderIsWhereTheLauncherPutsIt() throws {
        let target: [String: Any] = try SharedRulesContractTests.section("folderPublishTarget")
        let cases: [[String: Any]] = try XCTUnwrap(target["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 4)
        for testCase in cases {
            let toFolder: String = try XCTUnwrap(testCase["toFolder"] as? String)
            let expectTarget: String = try XCTUnwrap(testCase["expectTarget"] as? String)
            let workingFolder: String = "/Users/teacher/Class Websites"
            let elsewhere: String = "/Volumes/School Drive"
            let given: String = toFolder.replacingOccurrences(of: "@ELSEWHERE@", with: elsewhere)
            let wanted: String = expectTarget
                .replacingOccurrences(of: "@WF@", with: workingFolder)
                .replacingOccurrences(of: "@ELSEWHERE@", with: elsewhere)
            XCTAssertEqual(
                DeployedFolderOffer.sectionFolderPath(setting: given, workingFolderPath: workingFolder, sectionNumber: 1),
                wanted, toFolder
            )
        }
    }

    func testTheFolderSettingIsTheCoursesOneFolderDestination() {
        XCTAssertEqual(DeployedFolderOffer.folderSetting(deployTarget: "local_folder", deployFolderPath: "/a", additional: []), "/a")
        XCTAssertNil(DeployedFolderOffer.folderSetting(deployTarget: "netlify", deployFolderPath: "", additional: []))
        XCTAssertEqual(
            DeployedFolderOffer.folderSetting(
                deployTarget: "cloudflare_pages", deployFolderPath: "",
                additional: [(type: "netlify", path: ""), (type: "local_folder", path: "/b")]
            ),
            "/b"
        )
        XCTAssertNil(DeployedFolderOffer.folderSetting(deployTarget: "local_folder", deployFolderPath: "  ", additional: []))
    }

    func testEveryAddressCase() throws {
        let section: [String: Any] = try DeployedFolderOfferTests.section()
        let address: [String: Any] = try XCTUnwrap(section["address"] as? [String: Any])
        XCTAssertEqual(address["firstPort"] as? Int, DeployedFolderAddress.firstPort)
        XCTAssertEqual(address["blockSize"] as? Int, DeployedFolderAddress.blockSize)
        let cases: [[String: Any]] = try XCTUnwrap(address["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 4)
        for testCase in cases {
            let path: String = try XCTUnwrap(testCase["canonicalPath"] as? String)
            let remembered: Int? = testCase["remembered"] as? Int
            let expectFirst: Int = try XCTUnwrap(testCase["expectFirst"] as? Int)
            let candidates: [Int] = DeployedFolderAddress.candidates(forCanonicalPath: path, remembered: remembered)
            XCTAssertEqual(candidates.first, expectFirst, "\(path) remembered \(String(describing: remembered))")
            XCTAssertEqual(candidates.count, DeployedFolderAddress.blockSize)
        }
    }

    // MARK: - Tests: the app-wide record

    /// Opening twice starts ONE show and hands the browser the same address
    /// both times; Stop ends it; the folder going away ends it and says so.
    func testOpeningTwiceStartsOneShowAndStopEndsIt() async throws {
        let fileManager: FileManager = FileManager.default
        let top: URL = fileManager.temporaryDirectory
            .appendingPathComponent("deployed-folder-shows-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let section: URL = top.appendingPathComponent("published").appendingPathComponent("section2")
        try fileManager.createDirectory(at: section, withIntermediateDirectories: true)
        try Data("home".utf8).write(to: section.appendingPathComponent("index.html"))
        let trailFolder: URL = top.appendingPathComponent("trail")
        try fileManager.createDirectory(at: trailFolder, withIntermediateDirectories: true)
        let previousTrail: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
        let shows: DeployedFolderShows = DeployedFolderShows.shared
        shows.resetForTests()
        defer {
            shows.resetForTests()
            ActivityTrail.store = previousTrail
            try? fileManager.removeItem(at: top)
        }
        let defaults: UserDefaults = TestDefaults.make()
        let workingFolder: String = top.path

        var handedOver: [URL] = []
        let first: Bool = await shows.open(
            sectionFolder: section, courseCode: "ICS3U", sectionNumber: 2, workingFolderPath: workingFolder,
            from: .result, defaults: defaults, openInBrowser: { address in
                handedOver.append(address)
                return true
            }
        )
        let second: Bool = await shows.open(
            sectionFolder: section, courseCode: "ICS3U", sectionNumber: 2, workingFolderPath: workingFolder,
            from: .sectionMenu, defaults: defaults, openInBrowser: { address in
                handedOver.append(address)
                return true
            }
        )
        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(shows.shows.count, 1, "pressed again, it started a second show")
        XCTAssertEqual(handedOver.count, 2)
        XCTAssertEqual(handedOver.first, handedOver.last, "the same address both times")
        let show: DeployedFolderShows.Show = try XCTUnwrap(
            shows.show(courseCode: "ICS3U", sectionNumber: 2, workingFolderPath: workingFolder)
        )
        XCTAssertEqual(
            DeployedFolderAddress.rememberedPort(forCanonicalPath: FolderIdentity.canonicalPath(section.path), defaults: defaults),
            show.port, "the address is remembered for the folder"
        )
        let answer: RawHTTP.Answer? = RawHTTP.exchange(
            port: show.port,
            request: DeployedFolderResolver.Request(method: "GET", target: "/", headers: [(name: "host", value: "127.0.0.1:\(show.port)")])
        )
        XCTAssertEqual(answer?.status, 200)

        shows.stop(courseCode: "ICS3U", sectionNumber: 2, workingFolderPath: workingFolder)
        XCTAssertTrue(shows.shows.isEmpty)
        XCTAssertFalse(RawHTTP.canConnect(address: "127.0.0.1", port: show.port), "still answering after Stop")

        let trail: String = DeployedFolderOfferTests.trailText(in: trailFolder)
        XCTAssertTrue(trail.contains(DeployedFolderShows.openedLine(from: .result, alreadyOpen: false, moved: false)))
        XCTAssertTrue(trail.contains(DeployedFolderShows.openedLine(from: .sectionMenu, alreadyOpen: true, moved: false)),
                      "the second press is on the trail as already open")
        XCTAssertFalse(trail.contains(section.path), "the trail names the folder's path")
        XCTAssertFalse(trail.contains("127.0.0.1"), "the trail names the address")
    }

    func testAFolderThatIsNotThereIsNotOpened() async throws {
        let shows: DeployedFolderShows = DeployedFolderShows.shared
        shows.resetForTests()
        let fileManager: FileManager = FileManager.default
        let top: URL = fileManager.temporaryDirectory.appendingPathComponent("deployed-folder-none-\(UUID().uuidString)")
        let trailFolder: URL = top.appendingPathComponent("trail")
        try fileManager.createDirectory(at: trailFolder, withIntermediateDirectories: true)
        let previousTrail: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
        defer {
            shows.resetForTests()
            ActivityTrail.store = previousTrail
            try? fileManager.removeItem(at: top)
        }
        var handed: Int = 0
        let opened: Bool = await shows.open(
            sectionFolder: top.appendingPathComponent("missing/section1"), courseCode: "ICS3U", sectionNumber: 1,
            workingFolderPath: top.path, from: .toolbar, defaults: TestDefaults.make(), openInBrowser: { _ in
                handed += 1
                return true
            }
        )
        XCTAssertFalse(opened)
        XCTAssertEqual(handed, 0)
        XCTAssertTrue(shows.shows.isEmpty)
        XCTAssertTrue(DeployedFolderOfferTests.trailText(in: trailFolder).contains(DeployedFolderShows.couldNotOpenLine(.folderNotFound)))
    }

    /// A made-up deployed section and a scratch trail, for the tests below.
    func makeASection(named name: String) throws -> (section: URL, top: URL, trail: URL) {
        let fileManager: FileManager = FileManager.default
        let top: URL = fileManager.temporaryDirectory
            .appendingPathComponent("deployed-folder-\(name)-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let section: URL = top.appendingPathComponent("published").appendingPathComponent("section1")
        try fileManager.createDirectory(at: section, withIntermediateDirectories: true)
        try Data("home".utf8).write(to: section.appendingPathComponent("index.html"))
        let trail: URL = top.appendingPathComponent("trail")
        try fileManager.createDirectory(at: trail, withIntermediateDirectories: true)
        return (section: section, top: top, trail: trail)
    }

    /// The implementation review's M1: two presses before the first has
    /// started must start ONE show, and Stop must leave nothing listening.
    /// Fails where the second press passed the "already shown" check while
    /// the first was still starting.
    func testTwoQuickPressesStartOneShowAndStopLeavesNothingListening() async throws {
        let made: (section: URL, top: URL, trail: URL) = try makeASection(named: "quick")
        let previousTrail: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: made.trail)
        let shows: DeployedFolderShows = DeployedFolderShows.shared
        shows.resetForTests()
        defer {
            shows.resetForTests()
            ActivityTrail.store = previousTrail
            try? FileManager.default.removeItem(at: made.top)
        }
        let defaults: UserDefaults = TestDefaults.make()
        let workingFolder: String = made.top.path
        // Both pressed before either has finished starting: two tasks on the
        // main actor, the second running while the first waits for its
        // listener.
        let section: URL = made.section
        let first: Task<Bool, Never> = Task { @MainActor in
            return await shows.open(
                sectionFolder: section, courseCode: "SCH3U", sectionNumber: 1, workingFolderPath: workingFolder,
                from: .toolbar, defaults: defaults, openInBrowser: { _ in true }
            )
        }
        let second: Task<Bool, Never> = Task { @MainActor in
            return await shows.open(
                sectionFolder: section, courseCode: "SCH3U", sectionNumber: 1, workingFolderPath: workingFolder,
                from: .result, defaults: defaults, openInBrowser: { _ in true }
            )
        }
        let answers: [Bool] = [await first.value, await second.value]
        XCTAssertEqual(answers, [true, true])
        XCTAssertEqual(shows.shows.count, 1, "two quick presses started two shows")
        let port: Int = try XCTUnwrap(shows.shows.first).port
        let neighbour: Int = port + 1
        let neighbourWasFree: Bool = !RawHTTP.canConnect(address: "127.0.0.1", port: neighbour)
        shows.stop(courseCode: "SCH3U", sectionNumber: 1, workingFolderPath: workingFolder)
        XCTAssertTrue(shows.shows.isEmpty)
        XCTAssertFalse(RawHTTP.canConnect(address: "127.0.0.1", port: port), "still listening after Stop")
        if neighbourWasFree {
            XCTAssertFalse(RawHTTP.canConnect(address: "127.0.0.1", port: neighbour), "a second listener was left behind")
        }
    }

    /// Stop on a section ends every show of it (the review's L5): one
    /// started before its deploy folder was changed included.
    func testStopEndsEveryShowOfTheSection() async throws {
        let made: (section: URL, top: URL, trail: URL) = try makeASection(named: "two")
        let other: URL = made.top.appendingPathComponent("moved").appendingPathComponent("section1")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("home".utf8).write(to: other.appendingPathComponent("index.html"))
        let previousTrail: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: made.trail)
        let shows: DeployedFolderShows = DeployedFolderShows.shared
        shows.resetForTests()
        defer {
            shows.resetForTests()
            ActivityTrail.store = previousTrail
            try? FileManager.default.removeItem(at: made.top)
        }
        let defaults: UserDefaults = TestDefaults.make()
        let workingFolder: String = made.top.path
        for folder in [made.section, other] {
            let opened: Bool = await shows.open(
                sectionFolder: folder, courseCode: "SCH3U", sectionNumber: 1, workingFolderPath: workingFolder,
                from: .sectionMenu, defaults: defaults, openInBrowser: { _ in true }
            )
            XCTAssertTrue(opened)
        }
        XCTAssertEqual(shows.shows.count, 2)
        shows.stop(courseCode: "SCH3U", sectionNumber: 1, workingFolderPath: workingFolder)
        XCTAssertTrue(shows.shows.isEmpty, "Stop left a show of the section running")
    }

    static func trailText(in folder: URL) -> String {
        var text: String = ""
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            if let contents = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) {
                text += contents
            }
        }
        return text
    }
}
