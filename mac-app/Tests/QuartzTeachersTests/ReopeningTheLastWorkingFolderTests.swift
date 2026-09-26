import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` → `reopeningTheLastWorkingFolder`
/// (#311): the folder comes back at every launch, the window set follows
/// macOS, each window decides once, and a folder that cannot be reopened is
/// said in one sentence and kept.
///
/// Nothing here reads or writes the teacher's real preferences: every model
/// has `TestDefaults.make()`, and the one test that asks the REAL store does
/// so only to prove it answers nothing.
final class ReopeningTheLastWorkingFolderTests: XCTestCase {

    // MARK: - Stored properties

    var scratch: URL = URL(fileURLWithPath: "/")
    var previousStore: ProblemReportStore = ActivityTrail.store

    // MARK: - Functions

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("reopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch.appendingPathComponent("trail"))
        await MainActor.run {
            WindowFolderMemory.reset(with: [])
            WorkspaceModel.folderForNextNewWindow = nil
        }
    }

    override func tearDown() async throws {
        ActivityTrail.store = previousStore
        WorkingFolderReach.homeFolderOverride = nil
        await MainActor.run {
            WindowSettling.observer = nil
            WorkspaceModel.folderForNextNewWindow = nil
            WindowFolderMemory.resetForLoading()
        }
        // chmod 000 folders must be made readable again to be removed.
        restoreReadable(scratch)
        try? FileManager.default.removeItem(at: scratch)
    }

    func restoreReadable(_ url: URL) {
        let enumerator = FileManager.default.enumerator(atPath: url.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        while let item = enumerator?.nextObject() as? String {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.appendingPathComponent(item).path)
        }
    }

    @MainActor
    static func section() throws -> [String: Any] {
        return try SharedRulesContractTests.section("reopeningTheLastWorkingFolder")
    }

    static func appliesToTheMac(_ entry: [String: Any]) -> Bool {
        guard let platforms = entry["appliesOn"] as? [String] else {
            return true
        }
        return platforms.contains("mac")
    }

    func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    func makeFolder(_ name: String, in parent: URL? = nil) throws -> URL {
        let url: URL = (parent ?? scratch).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A folder shaped the way a working folder is: the launcher and a course.
    func makeWorkingFolder(_ name: String) throws -> URL {
        let url: URL = try makeFolder(name)
        try "#!/bin/bash\n".write(to: url.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        try makeFolder("courses/ABC1O", in: url)
        return url
    }

    // MARK: - The contract: launches

    /// Every launch case, played window by window through the same rule the
    /// windows use.
    @MainActor
    func testEveryLaunchCaseOpensTheWindowsTheContractSays() throws {
        let cases: [[String: Any]] = try XCTUnwrap(ReopeningTheLastWorkingFolderTests.section()["launchCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7)
        for launch in cases {
            if !ReopeningTheLastWorkingFolderTests.appliesToTheMac(launch) {
                continue
            }
            let name: String = launch["name"] as? String ?? "?"
            let comeBack: Bool = try XCTUnwrap(launch["windowsComeBack"] as? Bool, name)
            let leftOpen: [String] = try XCTUnwrap(launch["windowsLeftOpen"] as? [String], name)
            let last: String? = launch["lastWorkedIn"] as? String
            let opens: Int = try XCTUnwrap(launch["windowsMacOSOpens"] as? Int, name)
            let expected: [Any] = try XCTUnwrap(launch["expectWindows"] as? [Any], name)
            var expectedFolders: [String?] = []
            for element in expected {
                expectedFolders.append(element as? String)
            }
            let played: [String?] = WindowStartRule.playLaunch(
                windowsComeBack: comeBack, windowsLeftOpen: leftOpen, lastWorkedIn: last, windowsMacOSOpens: opens
            )
            XCTAssertEqual(played, expectedFolders, "launch case “\(name)”")
        }
    }

    // MARK: - The contract: folders

    /// Every folder case, on a real throwaway folder, through the reopen
    /// decision the windows use. The Trash is an injected root, never the
    /// real one; the home folder is a throwaway `home/`.
    @MainActor
    func testEveryFolderCaseIsDecidedAsTheContractSays() throws {
        let cases: [[String: Any]] = try XCTUnwrap(ReopeningTheLastWorkingFolderTests.section()["folderCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 11)
        let home: URL = try makeFolder("home")
        let outside: URL = try makeFolder("outside")
        let trash: URL = try makeFolder("home/.FakeTrash")
        WorkingFolderReach.homeFolderOverride = home
        var played: Int = 0
        for folderCase in cases {
            if !ReopeningTheLastWorkingFolderTests.appliesToTheMac(folderCase) {
                continue
            }
            let name: String = folderCase["name"] as? String ?? "?"
            let make: String = try XCTUnwrap(folderCase["make"] as? String, name)
            let expect: String = try XCTUnwrap(folderCase["expect"] as? String, name)
            let slug: String = UUID().uuidString
            var remembered: RememberedFolder
            var expectedPath: String?
            switch make {
            case "there":
                let url: URL = try makeWorkingFolder("home/\(slug)")
                remembered = RememberedFolder.make(for: url)
                expectedPath = url.path
            case "deleted":
                let url: URL = try makeWorkingFolder("home/\(slug)")
                remembered = RememberedFolder.make(for: url)
                try FileManager.default.removeItem(at: url)
            case "inTrash":
                let url: URL = try makeWorkingFolder("home/\(slug)")
                remembered = RememberedFolder.make(for: url)
                try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(slug))
            case "renamed":
                let url: URL = try makeWorkingFolder("home/\(slug)")
                remembered = RememberedFolder.make(for: url)
                let renamed: URL = home.appendingPathComponent(slug + " renamed")
                try FileManager.default.moveItem(at: url, to: renamed)
                expectedPath = FolderIdentity.canonicalPath(renamed.path)
            case "trashedButOriginalBack":
                let url: URL = try makeWorkingFolder("home/\(slug)")
                remembered = RememberedFolder.make(for: url)
                try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(slug))
                _ = try makeWorkingFolder("home/\(slug)")
                expectedPath = url.path
            case "driveNotConnected":
                remembered = RememberedFolder(path: "/Volumes/\(slug)/Course Notes", bookmark: nil)
            case "unreadable":
                let url: URL = try makeWorkingFolder("home/\(slug)")
                remembered = RememberedFolder.make(for: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
            case "outsideHome":
                let url: URL = try makeWorkingFolder("outside/\(slug)")
                remembered = RememberedFolder.make(for: url)
            case "coursesLinkedOutside":
                let url: URL = try makeFolder("home/\(slug)")
                try "#!/bin/bash\n".write(to: url.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
                let target: URL = try makeFolder("\(slug)-courses", in: outside)
                try FileManager.default.createSymbolicLink(at: url.appendingPathComponent("courses"), withDestinationURL: target)
                remembered = RememberedFolder.make(for: url)
            case "emptied":
                let url: URL = try makeFolder("home/\(slug)")
                remembered = RememberedFolder.make(for: url)
                expectedPath = url.path
            case "notAWorkingFolder":
                let url: URL = try makeFolder("home/\(slug)")
                try "notes".write(to: url.appendingPathComponent("shopping.txt"), atomically: true, encoding: .utf8)
                remembered = RememberedFolder.make(for: url)
                expectedPath = url.path
            default:
                XCTFail("folder case “\(name)” has a `make` this suite does not know: \(make)")
                continue
            }
            let outcome: RememberedFolder.Outcome = RememberedFolder.decide(
                RememberedFolder.observe(remembered, trashRoots: [trash.path])
            )
            switch outcome {
            case .reopen(let path, _):
                XCTAssertEqual(expect, "reopen", "folder case “\(name)” reopened, but the contract says \(expect)")
                if let expectedPath {
                    XCTAssertEqual(FolderIdentity.canonicalPath(path), FolderIdentity.canonicalPath(expectedPath), "folder case “\(name)”")
                }
            case .cannotReopen(let reason, _, _):
                XCTAssertEqual(reason.rawValue, expect, "folder case “\(name)”")
            }
            played += 1
        }
        XCTAssertGreaterThanOrEqual(played, 11)
    }

    /// Every reason's sentence, THROUGH `sentence(for:)` — so swapping two
    /// reasons' sentences is caught, not only a changed word.
    @MainActor
    func testEveryReasonSaysTheContractSentence() throws {
        let wording: [String: Any] = try XCTUnwrap(ReopeningTheLastWorkingFolderTests.section()["wording"] as? [String: Any])
        for reason in RememberedFolder.Reason.allCases {
            let template: String = try XCTUnwrap(wording[reason.rawValue] as? String, "no wording for \(reason.rawValue)")
            XCTAssertEqual(
                ReopenWording.sentence(for: reason, folderName: "Course Notes"),
                template.replacingOccurrences(of: "{folder}", with: "Course Notes"),
                "ReopenWording and reopeningTheLastWorkingFolder.wording.\(reason.rawValue) disagree"
            )
        }
    }

    /// Rule 1: no machinery in what a teacher reads.
    @MainActor
    func testNoSentenceNamesTheMachinery() {
        let forbidden: [String] = ["toolchain", "container", "docker", "script", "virtual machine", "mount", " vm", "bookmark"]
        var sentences: [String] = []
        for reason in RememberedFolder.Reason.allCases {
            sentences.append(ReopenWording.sentence(for: reason, folderName: "X"))
        }
        sentences.append(WorkingFolderReachWording.headline(folderName: "X"))
        sentences.append(WorkingFolderReachWording.coursesHeadline(folderName: "X"))
        sentences.append(WorkingFolderReachWording.whatToDo)
        sentences.append(WorkingFolderReachWording.whatToDoForCourses)
        for sentence in sentences {
            for word in forbidden {
                XCTAssertFalse(sentence.lowercased().contains(word), "“\(sentence)” names “\(word)”")
            }
        }
    }

    // MARK: - The contract: memory

    @MainActor
    func testEveryMemoryCaseHolds() throws {
        let cases: [[String: Any]] = try XCTUnwrap(ReopeningTheLastWorkingFolderTests.section()["memoryCases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 3)
        for memoryCase in cases {
            let expect: String = try XCTUnwrap(memoryCase["expect"] as? String)
            switch expect {
            case "stillRemembered":
                try aFailedReopenKeepsTheMemory()
            case "replacedAndSentenceGone":
                try choosingAnotherFolderReplacesItAndTakesTheSentenceAway()
            case "notWritten":
                try aModelNoWindowShowsNeverWritesIt()
            default:
                XCTFail("memory case expects \(expect), which this suite does not know")
            }
        }
    }

    @MainActor
    func aFailedReopenKeepsTheMemory() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let gone: String = scratch.appendingPathComponent("unplugged-\(UUID().uuidString)").path
        WindowFolderMemory.recordLastWorkingFolder(RememberedFolder(path: gone, bookmark: nil), defaults: defaults)
        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        XCTAssertFalse(model.reopen(try XCTUnwrap(model.lastWorkingFolder()), occasion: .lastWorkingFolder))
        XCTAssertEqual(model.folderNotOpened?.reason, .gone)
        XCTAssertEqual(model.lastWorkingFolder()?.path, gone, "a folder that could not be reopened must stay remembered")
    }

    @MainActor
    func choosingAnotherFolderReplacesItAndTakesTheSentenceAway() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let gone: String = scratch.appendingPathComponent("gone-\(UUID().uuidString)").path
        WindowFolderMemory.recordLastWorkingFolder(RememberedFolder(path: gone, bookmark: nil), defaults: defaults)
        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.reopen(try XCTUnwrap(model.lastWorkingFolder()), occasion: .lastWorkingFolder)
        XCTAssertNotNil(model.folderNotOpened)

        let other: URL = try makeWorkingFolder("other-\(UUID().uuidString)")
        model.chooseWorkspace(at: other)
        XCTAssertNil(model.folderNotOpened, "choosing a folder must take the sentence away")
        XCTAssertEqual(model.lastWorkingFolder()?.path, other.path, "the chosen folder is the last one now")
    }

    @MainActor
    func aModelNoWindowShowsNeverWritesIt() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let folder: URL = try makeWorkingFolder("bare-\(UUID().uuidString)")
        let bare: WorkspaceModel = WorkspaceModel(defaults: defaults)
        bare.adoptRestoredPath(folder.path)
        bare.rememberAsTheLastWorkingFolder()
        XCTAssertTrue(bare.reopen(RememberedFolder.make(for: folder), occasion: .lastWorkingFolder) || bare.workspaceURL != nil)
        bare.rememberAsTheLastWorkingFolder()
        XCTAssertNil(defaults.dictionary(forKey: WindowFolderMemory.lastFolderKey),
                     "a model no window shows (the assistant's, the MCP server's) must never write the last working folder")
        XCTAssertFalse(trailText().contains("reopened the working folder"),
                       "nor write a reopen onto the trail")
    }

    // MARK: - The live route

    /// A window's lone launch — no other window, nothing to replay, the
    /// close-windows setting at its default — reopens the last folder and
    /// says so on the trail.
    @MainActor
    func testTheCloseWindowsSettingStillReopensTheLastFolder() throws {
        WindowFolderMemory.systemRestoresWindowsOverride = false
        defer { WindowFolderMemory.systemRestoresWindowsOverride = nil }
        let folder: URL = try makeWorkingFolder("last-\(UUID().uuidString)")
        let defaults: UserDefaults = TestDefaults.make()
        WindowFolderMemory.record([WindowFolderMemory.Entry(path: folder.path, frame: "{{1, 1}, {900, 700}}")], defaults: defaults)
        WindowFolderMemory.recordLastWorkingFolder(RememberedFolder.make(for: folder), defaults: defaults)
        WindowFolderMemory.resetForLoading()
        XCTAssertNil(WindowFolderMemory.claimNextEntry(defaults: defaults), "the window SET still follows the setting")

        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.adoptFolderForNewWindow(among: [model])
        XCTAssertEqual(model.workspaceURL?.path, folder.path, "the FOLDER comes back whatever the setting says")
        XCTAssertTrue(model.hasSettledItsFolder)
        XCTAssertFalse(model.isResolvingRestoredFolder)
        XCTAssertTrue(trailText().contains("working folder reopened") || trailText().contains("reopened the working folder"))
    }

    /// A gone folder: the picker, the sentence, and one trail line with the reason.
    @MainActor
    func testAGoneFolderShowsThePickerAndSaysWhy() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let gone: String = scratch.appendingPathComponent("Course Notes").path
        WindowFolderMemory.recordLastWorkingFolder(RememberedFolder(path: gone, bookmark: nil), defaults: defaults)
        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.adoptFolderForNewWindow(among: [model])
        XCTAssertNil(model.workspaceURL)
        XCTAssertTrue(model.isShowingPicker)
        XCTAssertEqual(model.folderNotOpened?.detail, ReopenWording.gone(folderName: "Course Notes"))
        XCTAssertFalse(model.folderNotOpened?.showsPathBar ?? true)
        XCTAssertTrue(trailText().contains("did not reopen the working folder"))
        XCTAssertTrue(trailText().contains("— gone"))
    }

    /// One decision per window (#311 review B1): once a window has settled —
    /// here on a failed reopen — nothing decides again, the sentence stays,
    /// and the settle seam heard from it exactly once.
    @MainActor
    func testAWindowDecidesOnceAndTheSeamHearsItOnce() throws {
        var settled: Int = 0
        WindowSettling.observer = { model in
            settled += 1
        }
        let defaults: UserDefaults = TestDefaults.make()
        let gone: String = scratch.appendingPathComponent("gone-\(UUID().uuidString)").path
        WindowFolderMemory.recordLastWorkingFolder(RememberedFolder(path: gone, bookmark: nil), defaults: defaults)
        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        model.adoptFolderForNewWindow(among: [model])
        let sentence: String? = model.folderNotOpened?.detail
        XCTAssertNotNil(sentence)

        // The late backstop and a sibling now open: neither decides again.
        let sibling: URL = try makeWorkingFolder("sibling-\(UUID().uuidString)")
        let siblingModel: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        siblingModel.adoptRestoredPath(sibling.path)
        WindowFolderMemory.claimsOpenUntil = Date(timeIntervalSinceNow: -1)
        model.adoptFolderForNewWindow(among: [model, siblingModel])
        model.settleItsFolder()
        XCTAssertNil(model.workspaceURL, "a window whose folder had gone must not become a second window on a sibling's folder")
        XCTAssertEqual(model.folderNotOpened?.detail, sentence, "and the sentence that said why must stay")
        XCTAssertEqual(settled, 1, "each window settles exactly once")
    }

    /// #311 review B2: a second window at launch with no remembered folder of
    /// its own shows the picker; it never inherits the first one's folder.
    @MainActor
    func testASecondLaunchWindowShowsThePickerRatherThanInheriting() {
        let start: WindowStartRule.Start = WindowStartRule.start(
            requestedFolder: nil, aClaimMayStillArrive: false, isDuringLaunch: true,
            otherWindowCount: 1, otherOpenFolderPaths: ["/B"], mostRecentKeyPath: "/B", hasLastWorkingFolder: true
        )
        XCTAssertEqual(start, .picker)
        // Mid-session, ⌘N beside the same window still inherits (row 84 kept).
        let later: WindowStartRule.Start = WindowStartRule.start(
            requestedFolder: nil, aClaimMayStillArrive: false, isDuringLaunch: false,
            otherWindowCount: 1, otherOpenFolderPaths: ["/B"], mostRecentKeyPath: "/B", hasLastWorkingFolder: true
        )
        XCTAssertEqual(later, .sameAsOpenWindow("/B"))
        // A Dock click after closing the last window reopens (Q2).
        let alone: WindowStartRule.Start = WindowStartRule.start(
            requestedFolder: nil, aClaimMayStillArrive: false, isDuringLaunch: false,
            otherWindowCount: 0, otherOpenFolderPaths: [], mostRecentKeyPath: nil, hasLastWorkingFolder: true
        )
        XCTAssertEqual(alone, .lastWorkingFolder)
    }

    /// #311 review M1.3: a window the assistant opens for a section takes THAT
    /// folder, before anything else, exactly once — and writes no reopen.
    @MainActor
    func testARequestedFolderWinsAndIsTakenOnce() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let last: URL = try makeWorkingFolder("last-\(UUID().uuidString)")
        let wanted: URL = try makeWorkingFolder("wanted-\(UUID().uuidString)")
        WindowFolderMemory.recordLastWorkingFolder(RememberedFolder.make(for: last), defaults: defaults)
        WorkspaceModel.folderForNextNewWindow = wanted.path

        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.adoptFolderForNewWindow(among: [model])
        XCTAssertEqual(model.workspaceURL?.path, wanted.path)
        XCTAssertNil(WorkspaceModel.folderForNextNewWindow, "taken once")
        XCTAssertFalse(trailText().contains("reopened the working folder"), "no reopen the teacher never saw")
    }

    /// A remembered WINDOW's folder that is gone is handed out now, so its
    /// window can say why — it used to be skipped in silence.
    @MainActor
    func testAGoneWindowFolderIsStillHandedOut() {
        let gone: String = scratch.appendingPathComponent("gone").path
        WindowFolderMemory.reset(with: [WindowFolderMemory.Entry(path: gone, frame: "{{1, 1}, {900, 700}}")])
        XCTAssertEqual(WindowFolderMemory.claimNextEntry()?.path, gone)
    }

    /// The bookmark goes into the window list and comes back out of it.
    @MainActor
    func testTheWindowListCarriesTheBookmark() throws {
        let folder: URL = try makeWorkingFolder("listed-\(UUID().uuidString)")
        let defaults: UserDefaults = TestDefaults.make()
        let bookmark: Data? = RememberedFolder.make(for: folder).bookmark
        XCTAssertNotNil(bookmark)
        WindowFolderMemory.record([WindowFolderMemory.Entry(path: folder.path, frame: "f", bookmark: bookmark)], defaults: defaults)
        WindowFolderMemory.systemRestoresWindowsOverride = true
        defer { WindowFolderMemory.systemRestoresWindowsOverride = nil }
        WindowFolderMemory.resetForLoading()
        XCTAssertEqual(WindowFolderMemory.claimNextEntry(defaults: defaults)?.bookmark, bookmark)
    }

    /// Upgrading from a build that kept only the last CHOSEN folder.
    @MainActor
    func testTheLastChosenFolderIsReadWhenNothingNewerIsThere() {
        let defaults: UserDefaults = TestDefaults.make()
        defaults.set("/somewhere/Course Notes", forKey: WorkspaceModel.storedPathKey)
        XCTAssertEqual(WindowFolderMemory.lastWorkingFolder(defaults: defaults)?.path, "/somewhere/Course Notes")
    }

    /// R1: under the hosted suite the REAL preferences answer nothing, and
    /// are never written. Asserted structurally, so it is not vacuous on a
    /// Mac whose real preferences happen to hold no folder.
    @MainActor
    func testTheRealPreferencesAreNeverReadOrWrittenUnderTheSuite() throws {
        XCTAssertTrue(WindowFolderMemory.mayNotTouch(UserDefaults.standard))
        XCTAssertNil(WindowFolderMemory.lastWorkingFolder(defaults: UserDefaults.standard))
        let model: WorkspaceModel = WorkspaceModel()
        XCTAssertNil(model.lastWorkingFolder())
        let folder: URL = try makeWorkingFolder("never-\(UUID().uuidString)")
        let before: Any? = UserDefaults.standard.object(forKey: WindowFolderMemory.lastFolderKey)
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.chooseWorkspace(at: folder)
        let after: Any? = UserDefaults.standard.object(forKey: WindowFolderMemory.lastFolderKey)
        XCTAssertEqual(String(describing: before), String(describing: after))
        // And no window of the hosted app, on the real store, adopted a folder
        // from it on its own.
        for windowModel in WorkspaceModel.windowModels where windowModel !== model {
            XCTAssertNil(windowModel.folderNotOpened, "the hosted app's own window must not have tried to reopen anything")
        }
    }

    /// A renamed folder reopens where it is now and is remembered there.
    @MainActor
    func testARenamedFolderReopensWhereItIsAndIsRememberedThere() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let folder: URL = try makeWorkingFolder("before-\(UUID().uuidString)")
        WindowFolderMemory.recordLastWorkingFolder(RememberedFolder.make(for: folder), defaults: defaults)
        let renamed: URL = scratch.appendingPathComponent("after-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: folder, to: renamed)

        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.adoptFolderForNewWindow(among: [model])
        let opened: String = try XCTUnwrap(model.workspaceURL?.path)
        XCTAssertTrue(FolderIdentity.isSameFolder(opened, renamed.path))
        XCTAssertTrue(FolderIdentity.isSameFolder(try XCTUnwrap(model.lastWorkingFolder()?.path), renamed.path))
        XCTAssertTrue(trailText().contains("found where it had been moved"))
    }
}
