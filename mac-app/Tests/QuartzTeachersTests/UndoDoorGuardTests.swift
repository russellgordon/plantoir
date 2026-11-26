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

    /// The second hard review of U2b, MEDIUM 2: a folder on a step's path
    /// replaced by a link to outside AFTER the door: Undo moves nothing out.
    /// FAILED on 211f8d213, which moved the page into the outside folder.
    func testUndoNeverMovesAFileOutThroughALinkMadeAfterTheDoor() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "l")
        let root: URL = made.root
        try UndoContractReplay.write("page\n", to: "courses/TST1O/old/a.md", in: root)
        let move: UndoOp = UndoOp.moveFile(from: "courses/TST1O/old/a.md", to: "courses/TST1O/a.md", sha: UndoHash.sha256(of: Data("page\n".utf8)))
        let journal: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        XCTAssertEqual(JournaledWrite.perform(ops: UndoContractKinds.draft(ops: [move], blobs: [], root: root, action: "rollOver"), in: journal, mode: .live, places: UndoMemoryPlaces()), .applied(seq: 1))
        let oldFolder: URL = root.appendingPathComponent("courses/TST1O/old")
        try FileManager.default.removeItem(at: oldFolder)
        let outside: URL = parent.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: oldFolder, withDestinationURL: outside)

        let undone: UndoOutcome = journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())

        XCTAssertEqual(undone, .refused(.changedSince(firstPath: "courses/TST1O/old/a.md", others: 0), clearedTheList: true))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("courses/TST1O/a.md").path))
    }

    /// U4b2-2 (the part-ten review of U4b, LOW 2): a link made after the
    /// door that takes only a move's new place out: Undo moves nothing out
    /// and names the new place, the one that changed, never the old one.
    func testUndoRefusedBecauseOnlyTheNewPlaceLeadsOutNamesTheNewPlace() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "u-to")
        let root: URL = made.root
        let journal: UndoJournal = try makeTheMove(from: "courses/TST1O/b.md", to: "courses/TST1O/new/b.md", root: root, journalFolder: made.journalFolder)
        let outside: URL = try linkOutside(["courses/TST1O/new"], root: root)

        let undone: UndoOutcome = journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())

        XCTAssertEqual(undone, .refused(.changedSince(firstPath: "courses/TST1O/new/b.md", others: 0), clearedTheList: true))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("courses/TST1O/b.md").path))
    }

    /// U4b2-2: both of a move's places lead out: Undo names the old place,
    /// the first in the order path, from, to (as before U4b).
    func testUndoRefusedBecauseBothPlacesLeadOutNamesTheOldPlace() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "u-both")
        let root: URL = made.root
        let journal: UndoJournal = try makeTheMove(from: "courses/TST1O/old/c.md", to: "courses/TST1O/new/c.md", root: root, journalFolder: made.journalFolder)
        let outside: URL = try linkOutside(["courses/TST1O/old", "courses/TST1O/new"], root: root)

        let undone: UndoOutcome = journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())

        XCTAssertEqual(undone, .refused(.changedSince(firstPath: "courses/TST1O/old/c.md", others: 0), clearedTheList: true))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    /// U4b2-2: undone, then the old place's folder replaced by a link to
    /// outside: Redo moves nothing out and names the old place.
    func testRedoRefusedBecauseOnlyTheOldPlaceLeadsOutNamesTheOldPlace() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "r-from")
        let root: URL = made.root
        let journal: UndoJournal = try makeTheMove(from: "courses/TST1O/old/a.md", to: "courses/TST1O/a.md", root: root, journalFolder: made.journalFolder)
        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1))
        try FileManager.default.removeItem(at: root.appendingPathComponent("courses/TST1O/old/a.md"))
        let outside: URL = try linkOutside(["courses/TST1O/old"], root: root)
        try Data("page\n".utf8).write(to: outside.appendingPathComponent("a.md"))

        let redone: UndoOutcome = journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())

        XCTAssertEqual(redone, .refused(.changedSince(firstPath: "courses/TST1O/old/a.md", others: 0), clearedTheList: false))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), ["a.md"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("courses/TST1O/a.md").path))
    }

    /// U4b2-2: undone, then the new place's folder replaced by a link to
    /// outside: Redo moves nothing out and names the new place, never the
    /// old one, where the page still is.
    func testRedoRefusedBecauseOnlyTheNewPlaceLeadsOutNamesTheNewPlace() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "r-to")
        let root: URL = made.root
        let journal: UndoJournal = try makeTheMove(from: "courses/TST1O/b.md", to: "courses/TST1O/new/b.md", root: root, journalFolder: made.journalFolder)
        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1))
        let outside: URL = try linkOutside(["courses/TST1O/new"], root: root)

        let redone: UndoOutcome = journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())

        XCTAssertEqual(redone, .refused(.changedSince(firstPath: "courses/TST1O/new/b.md", others: 0), clearedTheList: false))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("courses/TST1O/b.md").path))
    }

    /// U4b2-2: both places lead out at the Redo: it names the old place.
    func testRedoRefusedBecauseBothPlacesLeadOutNamesTheOldPlace() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "r-both")
        let root: URL = made.root
        let journal: UndoJournal = try makeTheMove(from: "courses/TST1O/old/c.md", to: "courses/TST1O/new/c.md", root: root, journalFolder: made.journalFolder)
        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1))
        try FileManager.default.removeItem(at: root.appendingPathComponent("courses/TST1O/old/c.md"))
        let outside: URL = try linkOutside(["courses/TST1O/old", "courses/TST1O/new"], root: root)
        try Data("page\n".utf8).write(to: outside.appendingPathComponent("c.md"))

        let redone: UndoOutcome = journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())

        XCTAssertEqual(redone, .refused(.changedSince(firstPath: "courses/TST1O/old/c.md", others: 0), clearedTheList: false))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), ["c.md"])
    }

    /// U4b2-2 review 1, MEDIUM 1: the link is made AFTER the plan, before
    /// the staging (`afterTheCheck`), and takes only the move's new place
    /// out: the check made just before the change names the new place, the
    /// one that leads out, never the old.
    func testUndoRefusedAtTheStagingCheckNamesTheNewPlaceThatLeadsOut() throws {
        let outcome: UndoOutcome = try refusedBetweenThePlanAndTheChange(redo: false, at: .afterTheCheck, named: "s-u")
        XCTAssertEqual(firstPathNamed(by: outcome), "courses/TST1O/new/b.md")
    }

    /// The same, the link made just before the swap (`beforeSwap(0)`).
    func testUndoRefusedAtTheSwapCheckNamesTheNewPlaceThatLeadsOut() throws {
        let outcome: UndoOutcome = try refusedBetweenThePlanAndTheChange(redo: false, at: .beforeSwap(0), named: "w-u")
        XCTAssertEqual(firstPathNamed(by: outcome), "courses/TST1O/new/b.md")
    }

    /// Redo, the link made after the plan, before the staging, taking only
    /// the move's old place out (where a Redo takes the page from): it is
    /// named, never the new place, which is as the Undo left it.
    func testRedoRefusedAtTheStagingCheckNamesTheOldPlaceThatLeadsOut() throws {
        let outcome: UndoOutcome = try refusedBetweenThePlanAndTheChange(redo: true, at: .afterTheCheck, named: "s-r")
        XCTAssertEqual(firstPathNamed(by: outcome), "courses/TST1O/old/a.md")
    }

    /// Redo, the link made just before the swap.
    func testRedoRefusedAtTheSwapCheckNamesTheOldPlaceThatLeadsOut() throws {
        let outcome: UndoOutcome = try refusedBetweenThePlanAndTheChange(redo: true, at: .beforeSwap(0), named: "w-r")
        XCTAssertEqual(firstPathNamed(by: outcome), "courses/TST1O/old/a.md")
    }

    /// For an Undo, a move of courses/TST1O/b.md into courses/TST1O/new,
    /// undone with `new` replaced by a link to outside at `point`; for a
    /// Redo, a move of courses/TST1O/old/a.md to courses/TST1O/a.md, undone
    /// and then redone with `old` replaced so. Either way the plan has
    /// passed before the link is made, the page is then reached only
    /// through the link, and nothing is moved through it.
    func refusedBetweenThePlanAndTheChange(redo: Bool, at point: UndoKillPoint, named name: String) throws -> UndoOutcome {
        let made = try UndoContractReplay.scratch(under: parent, named: name)
        let root: URL = made.root
        let from: String = redo ? "courses/TST1O/old/a.md" : "courses/TST1O/b.md"
        let to: String = redo ? "courses/TST1O/a.md" : "courses/TST1O/new/b.md"
        let linkedFolder: String = redo ? "courses/TST1O/old" : "courses/TST1O/new"
        let pageName: String = redo ? "a.md" : "b.md"
        let journal: UndoJournal = try makeTheMove(from: from, to: to, root: root, journalFolder: made.journalFolder)
        if redo {
            XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1))
        }
        // Where the page is now: the place the link will take out.
        let movesTo: String = redo ? to : from
        let outside: URL = parent.appendingPathComponent("outside", isDirectory: true)
        var linked: Bool = false
        var linkFailure: String? = nil
        UndoKillPoints.hook = { reached in
            if reached == point && !linked {
                linked = true
                do {
                    _ = try self.linkOutside([linkedFolder], root: root)
                    // The page went with the folder; it is reached through
                    // the link now.
                    try Data("page\n".utf8).write(to: outside.appendingPathComponent(pageName))
                } catch {
                    linkFailure = "\(error)"
                }
            }
            return false
        }
        defer {
            UndoKillPoints.hook = nil
        }

        let outcome: UndoOutcome = redo
            ? journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())
            : journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())

        XCTAssertTrue(linked, "the link was made at \(point)")
        XCTAssertNil(linkFailure)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [pageName], "nothing moved through the link")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(movesTo).path))
        return outcome
    }

    /// The first place a changed-since refusal names, or nil.
    func firstPathNamed(by outcome: UndoOutcome) -> String? {
        if case .refused(.changedSince(let firstPath, _), _) = outcome {
            return firstPath
        }
        XCTFail("not refused as changed since: \(outcome)")
        return nil
    }

    /// One step of one move through the door: the page (made first,
    /// holding `page`) from `from` to `to`.
    func makeTheMove(from: String, to: String, root: URL, journalFolder: URL) throws -> UndoJournal {
        try UndoContractReplay.write("page\n", to: from, in: root)
        let move: UndoOp = UndoOp.moveFile(from: from, to: to, sha: UndoHash.sha256(of: Data("page\n".utf8)))
        let journal: UndoJournal = UndoJournal(folderURL: journalFolder)
        let made: JournaledWriteOutcome = JournaledWrite.perform(
            ops: UndoContractKinds.draft(ops: [move], blobs: [], root: root, action: "rollOver"), in: journal, mode: .live, places: UndoMemoryPlaces()
        )
        XCTAssertEqual(made, .applied(seq: 1))
        return journal
    }

    /// Each folder replaced, after the door, by a link to one folder
    /// outside the working folder, which is answered.
    func linkOutside(_ folders: [String], root: URL) throws -> URL {
        let outside: URL = parent.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        for folder in folders {
            let place: URL = root.appendingPathComponent(folder)
            try? FileManager.default.removeItem(at: place)
            try FileManager.default.createSymbolicLink(at: place, withDestinationURL: outside)
        }
        return outside
    }

    /// The second hard review of U2b, MEDIUM 3 (probe T): a Redo of a
    /// removed folder that dies with the folder aside, a file saved into it
    /// meanwhile: recovery keeps it aside, whole, and records the step
    /// interrupted, never settled as if the folder were gone. FAILED on
    /// 211f8d213, which settled the redo as done.
    func testAFolderChangedWhileAsideIsInTheWayNotSettled() async throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "t")
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
        XCTAssertEqual(JournaledWrite.perform(ops: UndoContractKinds.draft(ops: [op], blobs: blobs, root: root, action: "removeFolder"), in: journal, mode: .live, places: UndoMemoryPlaces()), .applied(seq: 1))
        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1))
        UndoKillPoints.hook = { point in point == .beforeSwap(0) }
        _ = journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())
        UndoKillPoints.hook = nil
        let aside: URL = UndoSwap.besideURL(for: folder, label: "1-redo", role: "orig")
        XCTAssertTrue(UndoSwap.renameExclusively(folder, onto: aside))
        try Data("saved during the walk\n".utf8).write(to: aside.appendingPathComponent("new.md"))
        let later: UndoJournal = UndoJournal(folderURL: made.journalFolder, processIsAlive: { _ in false })

        await UndoRecovery.recoverAndRederive(later, resolveRoot: { _ in root }, places: UndoMemoryPlaces())

        XCTAssertEqual(try later.read().records[1]?.phase, .interrupted)
        // The director's rule after the third review: back in its own place,
        // the teacher's new file with it, nothing left hidden.
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("new.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path))
    }

    /// The third hard review of U2b, LOW 2 (probe B): a dead step that keeps
    /// a file true by a rule, behind plain undoNewest (which cannot
    /// re-derive), is not available, never "under way" for ever.
    func testAPlainUndoBehindADeadFrontPageStepIsNotAvailable() throws {
        let made = try UndoContractReplay.scratch(under: parent, named: "b")
        let root: URL = made.root
        try UndoContractReplay.write("page\n", to: "courses/TST1O/a.md", in: root)
        let move: UndoOp = UndoOp.moveFile(from: "courses/TST1O/a.md", to: "courses/TST1O/b.md", sha: UndoHash.sha256(of: Data("page\n".utf8)))
        let recompute: UndoOp = UndoOp.recompute(path: "courses/TST1O/section1/index.md", maintainer: "sectionFrontPage", section: 1)
        let dying: UndoJournal = UndoJournal(folderURL: made.journalFolder, process: UndoProcess(host: "h", pid: 2_000_000_002, name: "gone", started: "1"))
        UndoKillPoints.hook = { point in point == .beforeApplied }
        _ = JournaledWrite.perform(ops: UndoContractKinds.draft(ops: [move, recompute], blobs: [], root: root, action: "rollOver"), in: dying, mode: .live, places: UndoMemoryPlaces())
        UndoKillPoints.hook = nil
        let later: UndoJournal = UndoJournal(folderURL: made.journalFolder, processIsAlive: { process in process.pid != 2_000_000_002 })

        XCTAssertEqual(later.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .notAvailable)
    }
}
