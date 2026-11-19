import XCTest
@testable import QuartzTeachers

/// What the door for a step given as ops (`JournaledWrite.perform(ops:)`)
/// and the take-out of a tree must refuse before anything changes (#899,
/// the hard review of U2b). Each test FAILED on c1c0624e5, where the
/// reviewer's probes showed the fault: a folder removed with no content in
/// the list, a file pulled in from outside the working folder, a step that
/// breaks `wholeOps` made and then stuck, and a Redo of a removed folder
/// whose content the list no longer holds deleting the folder for good.
final class UndoDoorGuardTests: XCTestCase {

    // MARK: - Stored properties

    var parent: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    // MARK: - Functions

    override func setUpWithError() throws {
        parent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UndoDoorGuard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        UndoContractReplay.registerTheFrontPageMaintainer()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: parent)
    }

    /// HIGH 1, probe A: a removeTree given no content is refused, and the
    /// teacher's folder is left exactly as it was.
    func testTheDoorRefusesToRemoveAFolderWhoseContentItWasNotGiven() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "a")
        let root: URL = made.root
        try UndoContractReplay.write("precious\n", to: "courses/TST1O/made/a.md", in: root)
        let folder: URL = root.appendingPathComponent("courses/TST1O/made")
        guard case .tree(let listing, _) = UndoTreeReading.read(at: folder) else {
            return XCTFail("no listing")
        }
        let op: UndoOp = UndoOp.tree(.removeTree, path: "courses/TST1O/made", listing: listing)
        let journal: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [op], blobs: [], root: root, action: "removeFolder")

        let outcome: JournaledWriteOutcome = JournaledWrite.perform(ops: draft, in: journal, mode: .live, places: UndoMemoryPlaces())

        XCTAssertEqual(outcome, .refused(.notReadable))
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("a.md"), encoding: .utf8), "precious\n")
        XCTAssertEqual(try journal.read().highestSeq, 0, "nothing is written to the list")
    }

    /// HIGH 1, probe B: a move from outside the working folder is refused,
    /// and nothing outside it moves.
    func testTheDoorRefusesAPathOutsideTheWorkingFolder() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "b")
        let root: URL = made.root
        let outside: URL = root.deletingLastPathComponent().appendingPathComponent("outside.md")
        try Data("outside\n".utf8).write(to: outside)
        let op: UndoOp = UndoOp.moveFile(from: "../outside.md", to: "courses/inside.md", sha: UndoHash.sha256(of: Data("outside\n".utf8)))
        let journal: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [op], blobs: [], root: root, action: "rollOver")

        XCTAssertEqual(JournaledWrite.perform(ops: draft, in: journal, mode: .live, places: UndoMemoryPlaces()), .refused(.notReadable))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("courses/inside.md").path))
    }

    /// HIGH 1: a path that is spelled inside the working folder but goes out
    /// through a link is refused too.
    func testTheDoorRefusesAPathThatLeavesThroughALink() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "link")
        let root: URL = made.root
        let elsewhere: URL = parent.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("away\n".utf8).write(to: elsewhere.appendingPathComponent("x.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("courses/away"), withDestinationURL: elsewhere)
        let op: UndoOp = UndoOp.moveFile(from: "courses/away/x.md", to: "courses/x.md", sha: UndoHash.sha256(of: Data("away\n".utf8)))
        let journal: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [op], blobs: [], root: root, action: "rollOver")

        XCTAssertEqual(JournaledWrite.perform(ops: draft, in: journal, mode: .live, places: UndoMemoryPlaces()), .refused(.notReadable))
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("x.md").path))
    }

    /// HIGH 1, probe C: a step that breaks `wholeOps` is never made.
    func testTheDoorRefusesAStepThatBreaksWholeOps() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "c")
        let root: URL = made.root
        let empty: UndoTreeListing = UndoTreeListing(folders: [], files: [])
        let first: UndoOp = UndoOp.tree(.createTree, path: "courses/TST1O/d", listing: empty)
        let second: UndoOp = UndoOp.tree(.createTree, path: "courses/TST1O/d/sub", listing: empty)
        let journal: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [first, second], blobs: [empty.data], root: root, action: "newFolder")

        XCTAssertEqual(JournaledWrite.perform(ops: draft, in: journal, mode: .live, places: UndoMemoryPlaces()), .refused(.notReadable))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("courses/TST1O/d").path))
    }

    /// HIGH 2: a Redo of a removed folder, once the list's copy of its
    /// content is gone, is refused and the folder stays.
    func testATakeOutIsRefusedWhenTheListCannotPutTheFolderBack() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "redo")
        let root: URL = made.root
        try UndoContractReplay.write("precious\n", to: "courses/TST1O/made/a.md", in: root)
        let folder: URL = root.appendingPathComponent("courses/TST1O/made")
        guard case .tree(let listing, let contents) = UndoTreeReading.read(at: folder, keepingContents: true) else {
            return XCTFail("no listing")
        }
        var blobs: [Data] = [listing.data]
        for (_, data) in contents {
            blobs.append(data)
        }
        let op: UndoOp = UndoOp.tree(.removeTree, path: "courses/TST1O/made", listing: listing)
        let journal: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [op], blobs: blobs, root: root, action: "removeFolder")
        XCTAssertEqual(JournaledWrite.perform(ops: draft, in: journal, mode: .live, places: UndoMemoryPlaces()), .applied(seq: 1))
        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1))
        // The list's content is lost (pruned, or a damaged disk).
        try FileManager.default.removeItem(at: journal.contentFolderURL)

        let redo: UndoOutcome = journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())

        XCTAssertEqual(redo, .refused(.contentMissing(path: "courses/TST1O/made"), clearedTheList: false))
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("a.md"), encoding: .utf8), "precious\n")
    }

    /// The second hard review of U2b, MEDIUM 1: a step with a recompute that
    /// died after its swaps is settled by the next write, and its front page
    /// IS re-derived. FAILED on 211f8d213, where the recovery inside the next
    /// write's begin dropped what it settled.
    func testTheNextWriteReDerivesAStepItsRecoverySettles() async throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "n")
        let root: URL = made.root
        try UndoContractReplay.write("page\n", to: "courses/TST1O/a.md", in: root)
        try UndoContractReplay.write("other\n", to: "courses/TST1O/c.md", in: root)
        let move: UndoOp = UndoOp.moveFile(from: "courses/TST1O/a.md", to: "courses/TST1O/b.md", sha: UndoHash.sha256(of: Data("page\n".utf8)))
        let recompute: UndoOp = UndoOp.recompute(path: "courses/TST1O/section1/index.md", maintainer: "sectionFrontPage", section: 1)
        let journal: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        UndoKillPoints.hook = { point in point == .beforeApplied }
        _ = JournaledWrite.perform(ops: UndoContractKinds.draft(ops: [move, recompute], blobs: [], root: root, action: "rollOver"), in: journal, mode: .live, places: UndoMemoryPlaces())
        UndoKillPoints.hook = nil
        _ = UndoContractReplay.takeTheRederived()
        let second: UndoOpsDraft = UndoContractKinds.draft(
            ops: [UndoOp.moveFile(from: "courses/TST1O/c.md", to: "courses/TST1O/d.md", sha: UndoHash.sha256(of: Data("other\n".utf8)))],
            blobs: [], root: root, action: "rollOver"
        )
        let later: UndoJournal = UndoJournal(folderURL: made.journalFolder, process: UndoProcess(host: "h", pid: 999_999, name: "x", started: "x"), processIsAlive: { _ in false })

        _ = await JournaledWrite.performAndRederive(ops: second, in: later, mode: .live, places: UndoMemoryPlaces())

        XCTAssertEqual(try later.read().records[1]?.phase, .done)
        XCTAssertEqual(UndoContractReplay.takeTheRederived(), ["courses/TST1O/section1/index.md#1"])
    }
}
