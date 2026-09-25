import XCTest
@testable import QuartzTeachers

/// What the backups take, and deleting several at once (issue #242).
///
/// The cases with inputs and outputs — what is pruned, what is counted, what
/// a delete removes and what it keeps — are contract data, run by
/// `CourseManagementContractTests`. This file pins what only the mac can
/// show: that the measuring leaves the main thread, that an overtaken
/// measurement cannot win, that a delete which fails part way still deletes
/// the rest, that another window on the same folder follows, and what the
/// trail and the teacher are told.
@MainActor
final class BackupSpaceTests: XCTestCase {

    // MARK: - Stored properties

    /// The scratch working folder, removed afterwards (never a real one).
    private var rootURL: URL?

    /// Files locked by a test, unlocked in `tearDown` so the folder can go.
    private var lockedURLs: [URL] = []

    // MARK: - Setting up

    override func tearDown() async throws {
        for url in lockedURLs {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path)
        }
        lockedURLs = []
        AssistActivity.store.active = nil
        AssistActivity.store.heldBackups = nil
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        try await super.tearDown()
    }

    // MARK: - Measuring

    /// `@concurrent` is load-bearing and nothing fails to compile without it,
    /// so the measurement records where it ran and this reads it.
    func testTheMeasurementRunsOffTheMainThread() async throws {
        let root: URL = try makeWorkingFolder()
        let zip: URL = try makeBackup(named: "ICS3U_backup_2026-09-01_120000.zip", course: "ICS3U", bytes: 1234, in: root)

        BackupSizes.lastPassRanOnTheMainThread = nil
        let sizes: [String: Int64] = await BackupSizes.measure([zip])

        XCTAssertEqual(sizes[zip.path], 1234)
        XCTAssertEqual(
            BackupSizes.lastPassRanOnTheMainThread, false,
            "the sizes were measured on the main thread — is `@concurrent` still on BackupSizes.measure?"
        )
    }

    /// A measurement that finishes after a newer one was started is thrown
    /// away. Otherwise a slow first measurement landing after a delete would
    /// put back sizes for zips that are gone, and a total that never shrinks.
    func testAMeasurementOvertakenByANewerOneIsIgnored() throws {
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        let older: (number: Int, fileURLs: [URL]) = model.beginMeasuringBackupSizes()
        let newer: (number: Int, fileURLs: [URL]) = model.beginMeasuringBackupSizes()

        model.finishMeasuringBackupSizes(newer.number, sizes: ["/new.zip": 2])
        model.finishMeasuringBackupSizes(older.number, sizes: ["/gone.zip": 1])

        XCTAssertEqual(model.backupSizes, ["/new.zip": 2])
    }

    /// A reload measures on its own, without anybody asking.
    func testOpeningAFolderMeasuresItsBackups() async throws {
        let root: URL = try makeWorkingFolder()
        _ = try makeBackup(named: "ICS3U_backup_2026-09-01_120000.zip", course: "ICS3U", bytes: 4096, in: root)
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        XCTAssertEqual(model.backupSizeMeasurementsStarted, 0)
        model.chooseWorkspace(at: root)
        let item: BackupItem = try XCTUnwrap(model.backupItems.first)
        // The reload started a measurement of its OWN — without it the header
        // total never appears until something else happens to measure.
        XCTAssertGreaterThanOrEqual(
            model.backupSizeMeasurementsStarted, 1,
            "opening a folder did not start measuring its backups — is it still in reloadCourses?"
        )

        // Waiting on the measurement the reload started, by starting one more
        // and awaiting it: the later measurement is the one that counts.
        await model.measureBackupSizes()

        XCTAssertEqual(model.backupSizes[item.id], 4096)
        XCTAssertTrue(model.backupSpace.isComplete)
        XCTAssertEqual(model.sizeDescription(of: item), BackupSizes.description(ofBytes: 4096))
    }

    /// A backup not measured yet makes the total INCOMPLETE rather than
    /// quietly smaller, so nothing shows a number that is wrong.
    func testATotalMissingABackupIsNotComplete() throws {
        let root: URL = try makeWorkingFolder()
        _ = try makeBackup(named: "ICS3U_backup_2026-09-01_120000.zip", course: "ICS3U", bytes: 10, in: root)
        _ = try makeBackup(named: "ICS3U_backup_2026-09-02_120000.zip", course: "ICS3U", bytes: 20, in: root)
        let items: [BackupItem] = WorkspaceModel.findBackupItems(in: root.appendingPathComponent("courses"))
        XCTAssertEqual(items.count, 2)

        let space: BackupSpace = BackupSpace.of(items, sizes: [items[0].id: 10])
        XCTAssertFalse(space.isComplete)
        XCTAssertEqual(space.totalCount, 2)
    }

    /// A backup a finished measurement could not size — gone from Finder
    /// between listing and measuring — is said to be unreadable and left out
    /// of the total, rather than leaving "Working out…" up for ever.
    func testABackupThatCannotBeSizedIsSaidSoAndLeftOutOfTheTotal() async throws {
        let root: URL = try makeWorkingFolder()
        _ = try makeBackup(named: "ICS3U_backup_2026-09-01_120000.zip", course: "ICS3U", bytes: 300, in: root)
        let vanishing: URL = try makeBackup(
            named: "ICS3U_backup_2026-09-02_120000.zip", course: "ICS3U", bytes: 700, in: root
        )
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        model.chooseWorkspace(at: root)
        let gone: BackupItem = try items(named: [vanishing], in: model)[0]
        try FileManager.default.removeItem(at: vanishing)

        await model.measureBackupSizes()

        let space: BackupSpace = model.backupSpace
        XCTAssertTrue(space.isComplete, "the measurement has finished, so nothing is still being worked out")
        XCTAssertEqual(space.unsizedCount, 1)
        XCTAssertEqual(space.totalBytes, 300)
        XCTAssertEqual(model.sizeDescription(of: gone), AssistWording.backupSizeCouldNotBeRead)
        // The Size column gets the SHORT form; the sentence is its tooltip.
        XCTAssertEqual(model.shortSizeDescription(of: gone), AssistWording.backupSizeCouldNotBeReadShort)
    }

    /// The confirmation says, BEFORE anything is deleted, that the open
    /// conversation's backup will be kept — and counts only what will go.
    func testTheConfirmationNamesTheKeptBackupAndCountsOnlyWhatGoes() throws {
        let root: URL = try makeWorkingFolder()
        _ = try makeBackup(named: "ICS3U_backup_2026-09-01_120000.zip", course: "ICS3U", bytes: 1, in: root)
        let held: URL = try makeBackup(
            named: "ICS3U_backup_2026-09-02_120000_assistant-section2.zip", course: "ICS3U", bytes: 1, in: root
        )
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        model.chooseWorkspace(at: root)
        var sizes: [String: Int64] = [:]
        for item in model.backupItems {
            sizes[item.id] = item.fileURL.lastPathComponent == held.lastPathComponent ? 9_000_000 : 1_000_000
        }
        AssistActivity.begin(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2)
        AssistActivity.holdBackups(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2) {
            return [held]
        }

        let message: String = WorkspaceModel.deleteConfirmation(
            for: model.backupItems,
            sizes: sizes,
            heldPaths: WorkspaceModel.heldBackupPaths(),
            active: AssistActivity.active
        )

        XCTAssertTrue(message.contains("It takes \(BackupSizes.description(ofBytes: 1_000_000))."), message)
        XCTAssertFalse(message.contains(BackupSizes.description(ofBytes: 10_000_000)), message)
        XCTAssertTrue(message.contains("One of these is kept: the assistant for ICS3U Section 2 is open"), message)
    }

    /// A selection of held backups ONLY has nothing to delete, so the button
    /// is disabled — never a confirmation saying "deletes them for good" that
    /// then deletes nothing.
    func testASelectionOfHeldBackupsOnlyHasNothingToDelete() throws {
        let root: URL = try makeWorkingFolder()
        let own: URL = try makeBackup(named: "ICS3U_backup_2026-09-01_120000.zip", course: "ICS3U", bytes: 1, in: root)
        let held: URL = try makeBackup(
            named: "ICS3U_backup_2026-09-02_120000_assistant-section2.zip", course: "ICS3U", bytes: 1, in: root
        )
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        model.chooseWorkspace(at: root)
        AssistActivity.begin(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2)
        AssistActivity.holdBackups(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2) {
            return [held]
        }
        let heldPaths: Set<String> = WorkspaceModel.heldBackupPaths()

        XCTAssertEqual(WorkspaceModel.deletableCount(of: try items(named: [held], in: model), heldPaths: heldPaths), 0)
        XCTAssertEqual(WorkspaceModel.deletableCount(of: try items(named: [own, held], in: model), heldPaths: heldPaths), 1)
    }

    /// The single "Delete Backup…" on the held backup refuses at once, with the
    /// multi-delete's own sentence, offers no confirmation, and deletes nothing.
    func testTheSingleDeleteOfAHeldBackupRefusesAsTheMultiDeleteDoes() throws {
        let root: URL = try makeWorkingFolder()
        let own: URL = try makeBackup(named: "ICS3U_backup_2026-09-01_120000.zip", course: "ICS3U", bytes: 1, in: root)
        let held: URL = try makeBackup(
            named: "ICS3U_backup_2026-09-02_120000_assistant-section2.zip", course: "ICS3U", bytes: 1, in: root
        )
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        model.chooseWorkspace(at: root)
        AssistActivity.begin(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2)
        AssistActivity.holdBackups(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2) {
            return [held]
        }
        let heldItem: BackupItem = try items(named: [held], in: model)[0]

        model.requestDeleteBackup(heldItem)

        XCTAssertNil(model.backupDeleteRequest, "a confirmation was offered for a backup that will not be deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: held.path))
        let multiSentence: String? = WorkspaceModel.problem(with: WorkspaceModel.BackupDeletion(
            deleted: [], keptForTheAssistant: [heldItem], failed: []
        ))
        XCTAssertNotNil(multiSentence)
        XCTAssertEqual(model.backupProblem, multiSentence)

        // Any other backup still gets the usual confirmation.
        model.backupProblem = nil
        let ownItem: BackupItem = try items(named: [own], in: model)[0]
        model.requestDeleteBackup(ownItem)
        XCTAssertEqual(model.backupDeleteRequest, ownItem)
        XCTAssertNil(model.backupProblem)
    }

    // MARK: - Deleting several

    /// One that cannot be deleted is reported, and the others are deleted
    /// anyway — a delete that stopped at the first failure would leave the
    /// teacher guessing which went.
    func testAFailedDeleteIsReportedAndTheRestAreStillDeleted() throws {
        let root: URL = try makeWorkingFolder()
        var zips: [URL] = []
        for day in 1...5 {
            zips.append(try makeBackup(
                named: "ICS3U_backup_2026-09-0\(day)_120000.zip", course: "ICS3U", bytes: 100, in: root
            ))
        }
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: zips[1].path)
        lockedURLs.append(zips[1])

        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        model.chooseWorkspace(at: root)
        let asked: [BackupItem] = try items(named: [zips[0], zips[1], zips[2]], in: model)
        model.selection = SidebarSelection.backup(asked[0].id)

        let deletion: WorkspaceModel.BackupDeletion = model.deleteBackups(asked)

        XCTAssertEqual(deletion.deleted.count, 2)
        XCTAssertEqual(deletion.failed.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: zips[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: zips[1].path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: zips[2].path))
        XCTAssertEqual(model.backupItems.count, 3, "the list is re-read once, after all of them")
        XCTAssertNil(model.selection, "the selection pointed at a backup that is gone")
        let problem: String = try XCTUnwrap(model.backupProblem)
        XCTAssertTrue(problem.hasPrefix("1 backup could not be deleted"), problem)
    }

    /// The backup an open conversation restores from is kept, the teacher is
    /// told which window to close, and a restore from one that went missing
    /// anyway is refused in plain words before anything is touched.
    func testTheBackupAnOpenConversationNeedsIsKept() throws {
        let root: URL = try makeWorkingFolder()
        let own: URL = try makeBackup(named: "ICS3U_backup_2026-09-01_120000.zip", course: "ICS3U", bytes: 1, in: root)
        let held: URL = try makeBackup(
            named: "ICS3U_backup_2026-09-02_120000_assistant-section2.zip", course: "ICS3U", bytes: 1, in: root
        )
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        model.chooseWorkspace(at: root)
        AssistActivity.begin(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2)
        AssistActivity.holdBackups(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2) {
            return [held]
        }

        let deletion: WorkspaceModel.BackupDeletion = model.deleteBackups(model.backupItems)

        XCTAssertEqual(deletion.deleted.count, 1)
        XCTAssertEqual(deletion.keptForTheAssistant.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: own.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: held.path), "the open conversation's backup was deleted")
        let problem: String = try XCTUnwrap(model.backupProblem)
        XCTAssertTrue(
            problem.hasPrefix(AssistActivity.closeTheAssistantFirst(try XCTUnwrap(AssistActivity.active))),
            problem
        )

        // Deleted anyway, from Finder: the restore says so plainly and early.
        try FileManager.default.removeItem(at: held)
        XCTAssertThrowsError(try AssistSectionRestore.restore(
            backupURL: held, courseCode: "ICS3U", sectionNumber: 2,
            coursesDirectoryURL: root.appendingPathComponent("courses")
        )) { error in
            XCTAssertEqual(
                error.localizedDescription,
                AssistSectionRestore.Problem.unreadableBackup(held.lastPathComponent).localizedDescription
            )
        }
    }

    /// Only the window holding the claim may say what it holds — a closing
    /// window's report must not outlive it.
    func testOnlyTheOpenAssistantsBackupsAreHeld() throws {
        let somewhere: URL = URL(fileURLWithPath: "/tmp/held.zip")
        AssistActivity.holdBackups(folderPath: "/tmp/f", courseCode: "ICS3U", sectionNumber: 1) {
            return [somewhere]
        }
        XCTAssertEqual(AssistActivity.backupsAnOpenConversationHolds(), [], "nothing is open, so nothing is held")

        AssistActivity.begin(folderPath: "/tmp/f", courseCode: "ICS3U", sectionNumber: 1)
        AssistActivity.holdBackups(folderPath: "/tmp/f", courseCode: "ICS3U", sectionNumber: 1) {
            return [somewhere]
        }
        XCTAssertEqual(AssistActivity.backupsAnOpenConversationHolds(), [somewhere])

        AssistActivity.end(folderPath: "/tmp/f", courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertEqual(AssistActivity.backupsAnOpenConversationHolds(), [], "the window closed and still held its backup")
    }

    /// Another window on the same folder re-reads its list, and lets go of a
    /// selection and a confirmation naming a zip that is gone (the plan
    /// review's M2 — Russell works with two windows on one folder).
    func testAnotherWindowOnTheFolderFollowsADelete() throws {
        let root: URL = try makeWorkingFolder()
        let first: URL = try makeBackup(named: "ICS3U_backup_2026-09-01_120000.zip", course: "ICS3U", bytes: 1, in: root)
        _ = try makeBackup(named: "ICS3U_backup_2026-09-02_120000.zip", course: "ICS3U", bytes: 1, in: root)
        let here: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        let there: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        let elsewhere: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        here.chooseWorkspace(at: root)
        there.chooseWorkspace(at: root)
        let otherRoot: URL = try makeSecondWorkingFolder()
        elsewhere.chooseWorkspace(at: otherRoot)
        let doomed: BackupItem = try items(named: [first], in: there)[0]
        there.selection = SidebarSelection.backup(doomed.id)
        there.backupRestoreRequest = doomed

        here.deleteBackups(try items(named: [first], in: here), following: [here, there, elsewhere])

        XCTAssertEqual(there.backupItems.count, 1)
        XCTAssertNil(there.selection)
        XCTAssertNil(there.backupRestoreRequest)
    }

    /// The trail names what went, by file name, and never anything on a page.
    func testTheTrailNamesTheBackupsThatWereDeleted() throws {
        let root: URL = try makeWorkingFolder()
        let zip: URL = try makeBackup(named: "ICS3U_backup_2026-09-01_120000.zip", course: "ICS3U", bytes: 1, in: root)
        let scratch: URL = root.appendingPathComponent("trail", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer { ActivityTrail.store = previousStore }

        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        model.chooseWorkspace(at: root)
        model.backupSizes = [try items(named: [zip], in: model)[0].id: 1_500_000]
        model.deleteBackups(model.backupItems)

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("deleted 1 backup of ICS3U, 1.5 MB: ICS3U_backup_2026-09-01_120000.zip"), trail)
    }

    /// Remembered with the window, like every other selection.
    func testAllBackupsIsRememberedWithTheWindow() {
        let stored: String = SidebarSelection.allBackups.storageValue
        XCTAssertEqual(SidebarSelection.fromStorageValue(stored), SidebarSelection.allBackups)
    }

    // MARK: - Helpers

    private func makeWorkingFolder() throws -> URL {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-space-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("courses/_backups"), withIntermediateDirectories: true
        )
        // A working folder is recognised by its launcher; without one the
        // folder is not read at all.
        FileManager.default.createFile(atPath: root.appendingPathComponent("preview.sh").path, contents: Data())
        rootURL = root
        return root
    }

    private func makeSecondWorkingFolder() throws -> URL {
        let root: URL = try XCTUnwrap(rootURL).appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("courses/_backups/ICS3U"), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: root.appendingPathComponent("preview.sh").path, contents: Data())
        return root
    }

    /// A zip of exactly `bytes` logical bytes — sparse, so a large one costs
    /// no disk.
    private func makeBackup(named name: String, course: String, bytes: Int64, in root: URL) throws -> URL {
        let folder: URL = root.appendingPathComponent("courses/_backups/\(course)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url: URL = folder.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle: FileHandle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(bytes))
        try handle.close()
        return url
    }

    private func items(named urls: [URL], in model: WorkspaceModel) throws -> [BackupItem] {
        var found: [BackupItem] = []
        for url in urls {
            var match: BackupItem? = nil
            for item in model.backupItems where item.fileURL.lastPathComponent == url.lastPathComponent {
                match = item
            }
            found.append(try XCTUnwrap(match, "\(url.lastPathComponent) is not in the list"))
        }
        return found
    }
}
