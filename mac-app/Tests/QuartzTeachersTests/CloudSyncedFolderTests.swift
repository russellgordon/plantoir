import XCTest
@testable import QuartzTeachers

/// A working folder a cloud service keeps in sync: how it is recognised, what
/// a teacher is told, and WHEN — a choice in the picker for a folder they
/// just chose, a quiet notice for one the window restored, and nothing at
/// all once they have gone past it.
///
/// The detection rule and the sentences are pinned to
/// `contracts/shared-rules.json` → `cloudSyncedFolders`, so Windows recognises
/// the same folders and says the same things.
@MainActor
final class CloudSyncedFolderTests: XCTestCase {

    // MARK: - Stored properties

    private var contract: [String: Any] = [:]

    /// A stand-in for the real detector, so a temporary folder can read as
    /// synced without putting one in iCloud.
    private var previousDetector: ((URL) -> CloudSyncedFolder?)?

    // MARK: - Functions

    override func setUpWithError() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        contract = try XCTUnwrap(all["cloudSyncedFolders"] as? [String: Any])
        previousDetector = WorkspaceModel.syncDetector
    }

    override func tearDown() {
        if let previousDetector {
            WorkspaceModel.syncDetector = previousDetector
        }
    }

    func makeTemporaryFolder() throws -> URL {
        let url: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Makes every folder read as synced by the named service.
    func pretendEveryFolderIsSynced(by serviceName: String) {
        WorkspaceModel.syncDetector = { folderURL in
            return CloudSyncedFolder(serviceName: serviceName, folderPath: folderURL.path)
        }
    }

    // MARK: - Recognising a synced folder

    /// The contract's cases, run against the pure rule. The home folder in
    /// the contract is a placeholder so the cases read the same on Windows.
    func testTheContractsDetectionCasesHold() throws {
        let detection: [String: Any] = try XCTUnwrap(contract["detection"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(detection["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6, "the contract lost detection cases")

        let homePath: String = "/Users/teacher"
        for testCase in cases {
            let path: String = try XCTUnwrap(testCase["path"] as? String)
                .replacingOccurrences(of: "{home}", with: homePath)
            let expected: String? = testCase["expectService"] as? String
            let found: String? = CloudSyncDetector.serviceName(forPath: path, homePath: homePath)
            XCTAssertEqual(found, expected, "\(path): \(testCase["why"] as? String ?? "")")
        }
    }

    /// The name for a service Plantoir does not know is the contract's, not
    /// an invented one.
    func testTheUnknownServiceNameIsTheContracts() throws {
        let detection: [String: Any] = try XCTUnwrap(contract["detection"] as? [String: Any])
        XCTAssertEqual(detection["unknownServiceName"] as? String, CloudSyncDetector.unknownServiceName)
    }

    /// A temporary folder is not in iCloud, so the real detector says nothing
    /// about it — which is what keeps every other test in this suite from
    /// tripping over the note.
    func testAnOrdinaryFolderIsNotSynced() throws {
        let folderURL: URL = try makeTemporaryFolder()
        XCTAssertNil(CloudSyncDetector.syncedFolder(at: folderURL))
    }

    // MARK: - What the teacher is told

    /// Every sentence in the contract is the one the app says, with the
    /// service filled in where the contract has `{service}`.
    func testTheWordingIsTheContracts() throws {
        let wording: [String: Any] = try XCTUnwrap(contract["wording"] as? [String: Any])
        let service: String = "iCloud Drive"
        func expected(_ key: String) throws -> String {
            return try XCTUnwrap(wording[key] as? String, "no \(key) in the contract")
                .replacingOccurrences(of: "{service}", with: service)
        }
        XCTAssertEqual(try expected("headline"), CloudSyncWording.headline(service: service))
        XCTAssertEqual(try expected("summary"), CloudSyncWording.summary)
        XCTAssertEqual(try expected("notesStayPut"), CloudSyncWording.notesStayPut)
        XCTAssertEqual(try expected("buildFilesAreCopied"), CloudSyncWording.buildFilesAreCopied(service: service))
        XCTAssertEqual(try expected("offloadedPagesAreSlow"), CloudSyncWording.offloadedPagesAreSlow(service: service))
        XCTAssertEqual(try expected("syncingCanInterruptAMove"), CloudSyncWording.syncingCanInterruptAMove(service: service))
        XCTAssertEqual(try expected("whatToDo"), CloudSyncWording.whatToDo)
        XCTAssertEqual(try expected("useAnywayButton"), CloudSyncWording.useAnywayButton)
        XCTAssertEqual(try expected("dismissNoticeButton"), CloudSyncWording.dismissNoticeButton)
    }

    /// The explanation is the contract's sentences in the contract's ORDER —
    /// reassurance first, the choice last.
    func testTheExplanationReadsInTheContractsOrder() throws {
        let wording: [String: Any] = try XCTUnwrap(contract["wording"] as? [String: Any])
        let order: [String] = try XCTUnwrap(wording["explanationOrder"] as? [String])
        let service: String = "Dropbox"
        var expectedSentences: [String] = []
        for key in order {
            expectedSentences.append(
                try XCTUnwrap(wording[key] as? String).replacingOccurrences(of: "{service}", with: service)
            )
        }
        XCTAssertEqual(CloudSyncWording.explanation(service: service), expectedSentences)
    }

    /// The contract's ban on machinery words, applied to every sentence.
    func testNoSentenceMentionsTheMachinery() {
        let forbidden: [String] = ["sync client", "file provider", "dataless", "evict", "toolchain", "container", "Docker", "script", "build root", "environment variable"]
        for sentence in CloudSyncWording.explanation(service: "OneDrive") + [CloudSyncWording.summary, CloudSyncWording.headline(service: "OneDrive")] {
            for word in forbidden {
                XCTAssertFalse(
                    sentence.localizedCaseInsensitiveContains(word),
                    "\"\(sentence)\" mentions \"\(word)\" — a teacher should never read the machinery"
                )
            }
        }
    }

    // MARK: - When it is shown

    /// A synced folder the teacher just CHOSE stops at the picker with the
    /// choice — and the window shows no notice, because the choice is the
    /// stronger form of the same thing.
    func testAChosenSyncedFolderAsksForADecision() throws {
        pretendEveryFolderIsSynced(by: "iCloud Drive")
        let folderURL: URL = try makeTemporaryFolder()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folderURL)

        XCTAssertEqual(workspace.syncedFolder?.serviceName, "iCloud Drive")
        XCTAssertTrue(workspace.needsCloudSyncDecision, "a folder the teacher just chose is the moment to decide")
        XCTAssertFalse(workspace.isShowingCloudSyncNotice, "not the notice as well")
    }

    /// A synced folder the window RESTORED gets the notice, never the
    /// picker: the teacher did not choose anything just now, and the
    /// courses must be there when the window opens.
    func testARestoredSyncedFolderShowsTheNoticeInstead() throws {
        pretendEveryFolderIsSynced(by: "Dropbox")
        let folderURL: URL = try makeTemporaryFolder()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.adoptRestoredPath(folderURL.path)

        XCTAssertEqual(workspace.syncedFolder?.serviceName, "Dropbox")
        XCTAssertTrue(workspace.isShowingCloudSyncNotice, "a restored folder gets the quiet notice")
        XCTAssertFalse(workspace.needsCloudSyncDecision, "and is never stopped at the picker")
    }

    /// A synced folder the picker will not take anyway — neither a working
    /// folder nor empty — is not asked about: the teacher is about to
    /// choose again, and the guidance saying what to choose is the message.
    func testAnUnrecognisedSyncedFolderIsNotAskedAbout() throws {
        pretendEveryFolderIsSynced(by: "iCloud Drive")
        let folderURL: URL = try makeTemporaryFolder()
        try Data("hello".utf8).write(to: folderURL.appendingPathComponent("unrelated.txt"))
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folderURL)

        XCTAssertTrue(workspace.workspaceIsUnrecognized)
        XCTAssertFalse(workspace.needsCloudSyncDecision, "nothing to decide about a folder that cannot be used")
        XCTAssertFalse(workspace.isShowingCloudSyncNotice)
    }

    /// An ordinary folder shows nothing, whichever way it arrived.
    func testAnOrdinaryFolderShowsNothing() throws {
        WorkspaceModel.syncDetector = { _ in
            return nil
        }
        let folderURL: URL = try makeTemporaryFolder()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folderURL)
        XCTAssertNil(workspace.syncedFolder)
        XCTAssertFalse(workspace.needsCloudSyncDecision)
        XCTAssertFalse(workspace.isShowingCloudSyncNotice)
    }

    // MARK: - Going past it, once

    /// "Use This Folder Anyway" clears the choice, and the folder is not
    /// asked about again — in this window, and in a window opened later on
    /// the same preferences.
    func testGoingAheadIsRememberedForThatFolder() throws {
        pretendEveryFolderIsSynced(by: "OneDrive")
        let folderURL: URL = try makeTemporaryFolder()
        let defaults: UserDefaults = TestDefaults.make()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: defaults)
        workspace.chooseWorkspace(at: folderURL)
        XCTAssertTrue(workspace.needsCloudSyncDecision)

        workspace.acknowledgeCloudSync()
        XCTAssertFalse(workspace.needsCloudSyncDecision)
        XCTAssertFalse(workspace.isShowingCloudSyncNotice)
        XCTAssertEqual(workspace.syncedFolder?.serviceName, "OneDrive", "still known to be synced — only the note is done with")

        let later: WorkspaceModel = WorkspaceModel(defaults: defaults)
        later.chooseWorkspace(at: folderURL)
        XCTAssertFalse(later.needsCloudSyncDecision, "the note is shown once per folder")
        later.adoptRestoredPath(folderURL.path)
        XCTAssertFalse(later.isShowingCloudSyncNotice, "and not as a notice either")
    }

    /// Remembered PER FOLDER: going past the note for one synced folder says
    /// nothing about a second one.
    func testASecondSyncedFolderGetsItsOwnNote() throws {
        pretendEveryFolderIsSynced(by: "Google Drive")
        let firstURL: URL = try makeTemporaryFolder()
        let secondURL: URL = try makeTemporaryFolder()
        let defaults: UserDefaults = TestDefaults.make()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: defaults)
        workspace.chooseWorkspace(at: firstURL)
        workspace.acknowledgeCloudSync()

        workspace.chooseWorkspace(at: secondURL)
        XCTAssertTrue(workspace.needsCloudSyncDecision, "a different folder deserves its own note")
    }

    /// Setting up an EMPTY synced folder is the decision: the note was
    /// beside the button, and pressing it answers it.
    func testSettingUpAnEmptySyncedFolderCountsAsGoingAhead() throws {
        pretendEveryFolderIsSynced(by: "iCloud Drive")
        let folderURL: URL = try makeTemporaryFolder()
        let defaults: UserDefaults = TestDefaults.make()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: defaults)
        workspace.chooseWorkspace(at: folderURL)
        XCTAssertTrue(workspace.workspaceCanBeInitialized)
        XCTAssertTrue(workspace.needsCloudSyncDecision, "the note is shown beside the set-up offer")

        workspace.initializeWorkspace()
        XCTAssertNil(workspace.workspaceProblem)
        XCTAssertFalse(workspace.needsCloudSyncDecision, "setting it up was the answer")
        XCTAssertTrue(workspace.hasAcknowledgedCloudSync(forPath: folderURL.path))
        workspace.isShowingNewCourseWizard = false
    }

    /// Both moments leave their line on the trail, in words a teacher would
    /// recognise, naming the service and never the folder in the clear.
    func testBothMomentsLeaveALineOnTheTrail() throws {
        let scratchFolderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-sync-trail-\(UUID().uuidString)", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: scratchFolderURL)
        }

        pretendEveryFolderIsSynced(by: "iCloud Drive")
        let folderURL: URL = try makeTemporaryFolder()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folderURL)
        workspace.acknowledgeCloudSync()

        let trailText: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trailText.contains("kept in sync with iCloud Drive"), trailText)
        XCTAssertTrue(trailText.contains("chose to use the working folder anyway"), trailText)
    }
}
