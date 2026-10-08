import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` → `openRecent` (#457): which folders
/// File ▸ Open Recent lists, in what order, under what titles, and what a
/// teacher is told when one cannot be opened.
///
/// Every list here has its own `TestDefaults.make()` store; the real
/// preferences are never read or written (`WindowFolderMemory.mayNotTouch`).
@MainActor
final class RecentWorkingFoldersTests: XCTestCase {

    // MARK: - Stored properties

    var scratch: URL = URL(fileURLWithPath: "/")

    // MARK: - Functions

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("recent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    static func section() throws -> [String: Any] {
        return try SharedRulesContractTests.section("openRecent")
    }

    func filled(_ path: String) -> String {
        return path.replacingOccurrences(of: "{home}", with: scratch.path)
    }

    func paths(of folders: [RememberedFolder]) -> [String] {
        var result: [String] = []
        for folder in folders {
            result.append(folder.path)
        }
        return result
    }

    // MARK: - Tests

    func testTheCapIsTheContracts() throws {
        XCTAssertEqual(RecentWorkingFolders.cap, try XCTUnwrap(RecentWorkingFoldersTests.section()["cap"] as? Int))
    }

    /// Every adding case, through the list itself — written to a store of
    /// its own, so "writes nothing" is counted rather than assumed.
    func testEveryAddingCaseGivesTheContractsList() throws {
        let cases: [[String: Any]] = try XCTUnwrap(RecentWorkingFoldersTests.section()["addingCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        for testCase in cases {
            let why: String = try XCTUnwrap(testCase["why"] as? String)
            if let platforms = testCase["appliesOn"] as? [String], !platforms.contains("mac") {
                continue
            }
            for folder in testCase["makeFolders"] as? [String] ?? [] {
                try FileManager.default.createDirectory(atPath: filled(folder), withIntermediateDirectories: true)
            }
            var before: [RememberedFolder] = []
            for path in try XCTUnwrap(testCase["before"] as? [String]) {
                before.append(RememberedFolder(path: filled(path), bookmark: nil))
            }
            let defaults: UserDefaults = TestDefaults.make()
            var stored: [[String: String]] = []
            for folder in before {
                stored.append(["path": folder.path, "bookmark": ""])
            }
            defaults.set(stored, forKey: RecentWorkingFolders.storageKey)
            let list: RecentWorkingFolders = RecentWorkingFolders(defaults: defaults)
            XCTAssertEqual(paths(of: list.entries), paths(of: before), "loaded as stored — \(why)")

            let opened: String = filled(try XCTUnwrap(testCase["opened"] as? String))
            list.noteOpened(RememberedFolder(path: opened, bookmark: nil))
            var expected: [String] = []
            for path in try XCTUnwrap(testCase["after"] as? [String]) {
                expected.append(filled(path))
            }
            XCTAssertEqual(paths(of: list.entries), expected, why)
            if let writes = testCase["writes"] as? Bool, writes == false {
                XCTAssertEqual(list.writeCount, 0, "nothing written — \(why)")
            } else {
                XCTAssertEqual(list.writeCount, 1, why)
                XCTAssertEqual(paths(of: RecentWorkingFolders(defaults: defaults).entries), expected, "and kept — \(why)")
            }
        }
    }

    func testEveryTitleCaseIsTheContracts() throws {
        let cases: [[String: Any]] = try XCTUnwrap(RecentWorkingFoldersTests.section()["titleCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 2)
        for testCase in cases {
            let folders: [String] = try XCTUnwrap(testCase["folders"] as? [String])
            let titles: [String] = try XCTUnwrap(testCase["titles"] as? [String])
            XCTAssertEqual(RecentWorkingFolders.titles(for: folders), titles)
        }
    }

    /// The wording, key by key, against the contract — and no sentence for
    /// the two reasons the picker's own words cover.
    func testEveryReasonSaysTheContractSentence() throws {
        let wording: [String: Any] = try XCTUnwrap(RecentWorkingFoldersTests.section()["wording"] as? [String: Any])
        XCTAssertEqual(
            OpenRecentWording.title(folderName: "Courses"),
            (try XCTUnwrap(wording["title"] as? String)).replacingOccurrences(of: "{folder}", with: "Courses")
        )
        for reason in RememberedFolder.Reason.allCases {
            let sentence: String? = OpenRecentWording.sentence(for: reason)
            XCTAssertEqual(sentence, wording[reason.rawValue] as? String, "openRecent.wording.\(reason.rawValue)")
        }
    }

    /// Clearing empties the list, keeps it empty, and leaves a line on the
    /// trail with how many there were (rule 5).
    func testClearingEmptiesTheListAndSaysSoOnTheTrail() throws {
        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch.appendingPathComponent("trail"))
        defer { ActivityTrail.store = previous }
        let defaults: UserDefaults = TestDefaults.make()
        let list: RecentWorkingFolders = RecentWorkingFolders(defaults: defaults)
        list.noteOpened(RememberedFolder(path: "/Users/t/Courses", bookmark: nil))
        list.noteOpened(RememberedFolder(path: "/Users/t/Clubs", bookmark: nil))
        list.clear()
        XCTAssertEqual(list.entries, [])
        XCTAssertEqual(RecentWorkingFolders(defaults: defaults).entries, [], "an empty list is kept, not re-seeded")
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("cleared File ▸ Open Recent (2 folders)"), trail)
    }

    /// The first launch after the update starts from the folders the Mac
    /// already knows about, so the menu is not empty.
    func testTheFirstReadIsSeededFromTheLastFolderAndTheWindows() throws {
        let defaults: UserDefaults = TestDefaults.make()
        WindowFolderMemory.recordLastWorkingFolder(RememberedFolder(path: "/Users/t/Courses", bookmark: nil), defaults: defaults)
        defaults.set([
            ["path": "/Users/t/Clubs", "frame": "{{0, 0}, {900, 700}}"],
            ["path": "/Users/t/Courses", "frame": "{{10, 10}, {900, 700}}"],
        ], forKey: WindowFolderMemory.storageKey)
        XCTAssertEqual(paths(of: RecentWorkingFolders(defaults: defaults).entries), ["/Users/t/Courses", "/Users/t/Clubs"])
    }

    /// The suite's own process never reads or writes the real list.
    func testTheRealPreferencesAreNeverTouchedUnderTheSuite() {
        let real: RecentWorkingFolders = RecentWorkingFolders(defaults: PlantoirDefaults.shared)
        XCTAssertEqual(real.entries, [])
        real.noteOpened(RememberedFolder(path: "/Users/t/Courses", bookmark: nil))
        XCTAssertEqual(real.entries, [])
        XCTAssertEqual(real.writeCount, 0)
    }

    /// No sentence names the machinery (rule 1).
    func testNoSentenceNamesTheMachinery() {
        for reason in RememberedFolder.Reason.allCases {
            let sentence: String = OpenRecentWording.sentence(for: reason) ?? ""
            for word in ["toolchain", "script", "Docker", "container", "Colima"] {
                XCTAssertFalse(sentence.localizedCaseInsensitiveContains(word), "\(reason): \(word)")
            }
        }
    }
}
