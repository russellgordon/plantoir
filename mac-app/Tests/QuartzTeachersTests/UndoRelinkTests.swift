import XCTest
@testable import QuartzTeachers

/// U4b3 of #899, the third stretch: a RELINKING move, a symbolic link's
/// move that changes the text it holds (`linkShaBefore` at `from`,
/// `linkShaAfter` at `to`, both blobs). Insert Class makes one when a later
/// class links to a class page the step renames (relink-5). The check and
/// the swap are called directly (relink-1), and a step holding one is read
/// from the journal, undone and redone through the list (relink-2).
final class UndoRelinkTests: XCTestCase {

    // MARK: - Stored properties

    var parent: URL = FileManager.default.temporaryDirectory

    var outside: URL = FileManager.default.temporaryDirectory

    let section: String = "courses/TST1O/section1/"

    /// Where the relinked link's texts lead.
    enum Leads: CaseIterable {
        /// To pages of the section, by relative text.
        case inside
        /// To files outside the working folder, by absolute text.
        case outToAFile
        /// To nothing outside the working folder.
        case outToNothing
    }

    /// One relinking move laid out: the folder, its journal, the op and
    /// the two texts.
    struct LaidRelink {

        // MARK: - Stored properties

        let root: URL

        let journal: UndoJournal

        let op: UndoOp

        let oldText: String

        let newText: String
    }

    // MARK: - Setting up

    override func setUpWithError() throws {
        let name: String = "relink-" + UUID().uuidString
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        outside = FileManager.default.temporaryDirectory.appendingPathComponent(name + "-outside", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        UndoKillPoints.fileInUseAtSwap = nil
        UndoKillPoints.relinkRenameInFails = nil
        UndoKillPoints.hook = nil
        try? FileManager.default.removeItem(at: parent)
        try? FileManager.default.removeItem(at: outside)
    }

    // MARK: - Judged and swapped (relink-1)

    /// Going forward the link at Day 4 is replaced by one at Day 5 holding
    /// exactly the new text; going back, the old link with the old text
    /// byte for byte. Whatever either text names, inside or out, a file or
    /// nothing, is never read, written or made.
    func testARelinkGoesForwardAndBackHoldingEachSidesOwnText() throws {
        for leads in Leads.allCases {
            let laid: LaidRelink = try layARelink(named: "there-and-back", leads: leads)
            let outsideBefore: [String: String] = try outsideNow()
            let insideBefore: String? = try? text(section + "Unit 1, Day 3.md", root: laid.root)
            let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
            XCTAssertEqual(forward.count, 1, "\(leads)")
            XCTAssertEqual(UndoSwap.swap(forward, label: "1-apply", root: laid.root), .swapped, "\(leads)")
            XCTAssertEqual(linkText(section + "Unit 1, Day 5.md", root: laid.root), laid.newText, "\(leads)")
            XCTAssertFalse(standsAnything(section + "Unit 1, Day 4.md", root: laid.root), "\(leads)")
            XCTAssertEqual(stagedLeft(under: laid.root), [], "\(leads)")
            XCTAssertEqual(try outsideNow(), outsideBefore, "\(leads)")
            XCTAssertEqual(try? text(section + "Unit 1, Day 3.md", root: laid.root), insideBefore, "\(leads)")

            let back: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .backward, root: laid.root, journal: laid.journal))
            XCTAssertEqual(back.count, 1, "\(leads)")
            XCTAssertEqual(UndoSwap.swap(back, label: "1-undo", root: laid.root), .swapped, "\(leads)")
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.oldText, "\(leads)")
            XCTAssertFalse(standsAnything(section + "Unit 1, Day 5.md", root: laid.root), "\(leads)")
            XCTAssertEqual(stagedLeft(under: laid.root), [], "\(leads)")
            XCTAssertEqual(try outsideNow(), outsideBefore, "\(leads)")
            XCTAssertEqual(try? text(section + "Unit 1, Day 3.md", root: laid.root), insideBefore, "\(leads)")
        }
        try checkTheOutsideBytes()
    }

    /// A side holding the OTHER side's text, a plain file, a folder or
    /// nothing where the content should be is changed since, both ways.
    func testASideHoldingSomethingElseIsChangedSinceBothWays() throws {
        let replacements: [String] = ["other text", "file", "folder", "nothing"]
        for replacement in replacements {
            for direction in [UndoDirection.forward, UndoDirection.backward] {
                let laid: LaidRelink = try layARelink(named: "else-\(replacement)-\(direction)", leads: .inside)
                let source: String = direction == .forward ? "Unit 1, Day 4.md" : "Unit 1, Day 5.md"
                if direction == .backward {
                    try makeItForward(laid)
                }
                let url: URL = laid.root.appendingPathComponent(section + source)
                XCTAssertTrue(UndoSwap.removeALink(at: url))
                switch replacement {
                case "other text":
                    let otherText: String = direction == .forward ? laid.newText : laid.oldText
                    try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: otherText)
                case "file":
                    try Data("A page.\n".utf8).write(to: url)
                case "folder":
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                default:
                    break
                }
                let before: [String: String] = try folderNow(laid.root)
                let plan: UndoPlan = UndoCheck.plan([laid.op], direction: direction, root: laid.root, journal: laid.journal)
                XCTAssertTrue(isChangedSince(plan), "\(replacement) \(direction): \(plan)")
                XCTAssertEqual(try folderNow(laid.root), before)
            }
        }
    }

    /// Both links standing (the new one renamed in, the old not yet
    /// removed) is neither state: changed since, both ways, and nothing is
    /// removed (an Undo never removes a link the teacher made).
    func testBothLinksStandingIsChangedSinceBothWays() throws {
        for direction in [UndoDirection.forward, UndoDirection.backward] {
            let laid: LaidRelink = try layARelink(named: "both-\(direction)", leads: .inside)
            try layLink(section + "Unit 1, Day 5.md", holding: laid.newText, root: laid.root)
            let before: [String: String] = try folderNow(laid.root)
            let plan: UndoPlan = UndoCheck.plan([laid.op], direction: direction, root: laid.root, journal: laid.journal)
            XCTAssertTrue(isChangedSince(plan), "\(direction): \(plan)")
            XCTAssertEqual(try folderNow(laid.root), before)
        }
    }

    /// A side that cannot be read is cannot tell now, and the list is kept
    /// whole: both texts still in it.
    func testASideThatCannotBeReadIsCannotTellNow() throws {
        let laid: LaidRelink = try layARelink(named: "unreadable", leads: .inside)
        let folder: URL = laid.root.appendingPathComponent(section)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: folder.path)
        let plan: UndoPlan = UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        guard case .refused(.cannotTellNow) = plan else {
            XCTFail("the plan came to \(plan), not cannot tell now")
            return
        }
        XCTAssertNotNil(try laid.journal.blobContent(sha: try XCTUnwrap(laid.op.linkShaBefore)))
        XCTAssertNotNil(try laid.journal.blobContent(sha: try XCTUnwrap(laid.op.linkShaAfter)))
        XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.oldText)
    }

    /// Either text missing from the list: content missing, nothing changed.
    func testATextMissingFromTheListIsContentMissing() throws {
        for missing in ["before", "after"] {
            let laid: LaidRelink = try layARelink(named: "missing-\(missing)", leads: .inside)
            let absent: String = UndoHash.sha256(of: Data("Not in the list.\n".utf8))
            let op: UndoOp = UndoOp.relinkLink(
                from: section + "Unit 1, Day 4.md", to: section + "Unit 1, Day 5.md",
                linkShaBefore: missing == "before" ? absent : try XCTUnwrap(laid.op.linkShaBefore),
                linkShaAfter: missing == "after" ? absent : try XCTUnwrap(laid.op.linkShaAfter)
            )
            if missing == "before" {
                // Laid with the text the op names, so only the list lacks it.
                XCTAssertTrue(UndoSwap.removeALink(at: laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")))
                try layLink(section + "Unit 1, Day 4.md", holding: "Not in the list.\n", root: laid.root)
            }
            let before: [String: String] = try folderNow(laid.root)
            let plan: UndoPlan = UndoCheck.plan([op], direction: .forward, root: laid.root, journal: laid.journal)
            guard case .refused(.contentMissing) = plan else {
                XCTFail("\(missing): the plan came to \(plan), not content missing")
                continue
            }
            XCTAssertEqual(try folderNow(laid.root), before)
        }
    }

    /// A second target that fails after the relink went in: the relink is
    /// reversed the same way the other way round, the old link back with
    /// its text, nothing at Day 5 and nothing staged left.
    func testALaterFailureReversesTheRelink() throws {
        let laid: LaidRelink = try layARelink(named: "reversed", leads: .inside)
        try UndoContractReplay.write("Eight.\n", to: section + "Unit 1, Day 8.md", in: laid.root)
        let ops: [UndoOp] = [
            laid.op,
            UndoOp.moveFile(from: section + "Unit 1, Day 8.md", to: section + "Unit 1, Day 9.md", sha: UndoHash.sha256(of: Data("Eight.\n".utf8))),
        ]
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .forward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(places(of: targets), [section + "Unit 1, Day 5.md", section + "Unit 1, Day 9.md"])
        UndoKillPoints.fileInUseAtSwap = { index in
            return index == 1
        }
        let result: UndoSwapResult = UndoSwap.swap(targets, label: "1-apply", root: laid.root)
        UndoKillPoints.fileInUseAtSwap = nil
        XCTAssertEqual(result, .refused(.fileIsInUse(path: section + "Unit 1, Day 9.md")))
        XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.oldText)
        XCTAssertFalse(standsAnything(section + "Unit 1, Day 5.md", root: laid.root))
        XCTAssertFalse(standsAnything(section + "Unit 1, Day 9.md", root: laid.root))
        XCTAssertEqual(try text(section + "Unit 1, Day 8.md", root: laid.root), "Eight.\n")
        XCTAssertEqual(stagedLeft(under: laid.root), [])
    }

    /// The new link cannot be renamed in: the old link is never removed
    /// first, so it stands with its text, and nothing is left staged.
    func testARenameInThatFailsLeavesTheOldLinkWhole() throws {
        let laid: LaidRelink = try layARelink(named: "rename-fails", leads: .inside)
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
        UndoKillPoints.relinkRenameInFails = { _ in
            return true
        }
        let result: UndoSwapResult = UndoSwap.swap(targets, label: "1-apply", root: laid.root)
        UndoKillPoints.relinkRenameInFails = nil
        XCTAssertEqual(result, .refused(.fileIsInUse(path: section + "Unit 1, Day 4.md")))
        XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.oldText)
        XCTAssertFalse(standsAnything(section + "Unit 1, Day 5.md", root: laid.root))
        XCTAssertEqual(stagedLeft(under: laid.root), [])
    }

    /// The relink LEAVES a handed-over place: it leaves Day 4, and the page
    /// at Day 3 moves into it. Planned and swapped in the step's order,
    /// both ways.
    func testARelinkLeavingAHandedOverPlaceGoesBothWays() throws {
        let laid: LaidRelink = try layARelink(named: "leaver", leads: .inside)
        let threeSha: String = UndoHash.sha256(of: Data("Three.\n".utf8))
        let ops: [UndoOp] = [
            laid.op,
            UndoOp.moveFile(from: section + "Unit 1, Day 3.md", to: section + "Unit 1, Day 4.md", sha: threeSha),
        ]
        let before: [String: String] = try folderNow(laid.root)
        let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .forward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(places(of: forward), [section + "Unit 1, Day 5.md", section + "Unit 1, Day 4.md"])
        XCTAssertEqual(UndoSwap.swap(forward, label: "1-apply", root: laid.root), .swapped)
        XCTAssertEqual(linkText(section + "Unit 1, Day 5.md", root: laid.root), laid.newText)
        XCTAssertEqual(try text(section + "Unit 1, Day 4.md", root: laid.root), "Three.\n")
        XCTAssertFalse(standsAnything(section + "Unit 1, Day 3.md", root: laid.root))
        let back: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .backward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(places(of: back), [section + "Unit 1, Day 3.md", section + "Unit 1, Day 4.md"])
        XCTAssertEqual(UndoSwap.swap(back, label: "1-undo", root: laid.root), .swapped)
        XCTAssertEqual(try folderNow(laid.root), before)
        XCTAssertEqual(stagedLeft(under: laid.root), [])
    }

    /// The relink FILLS a handed-over place: the page at Day 5 is removed,
    /// and the link moves into its place. Planned and swapped in the step's
    /// order, both ways.
    func testARelinkFillingAHandedOverPlaceGoesBothWays() throws {
        let laid: LaidRelink = try layARelink(named: "filler", leads: .inside)
        try UndoContractReplay.write("Five.\n", to: section + "Unit 1, Day 5.md", in: laid.root)
        let five: String = try store("Five.\n", in: laid.journal)
        let ops: [UndoOp] = [
            UndoOp.writeFile(path: section + "Unit 1, Day 5.md", beforeSha: five, afterSha: nil),
            laid.op,
        ]
        let before: [String: String] = try folderNow(laid.root)
        let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .forward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(places(of: forward), [section + "Unit 1, Day 5.md", section + "Unit 1, Day 5.md"])
        XCTAssertEqual(UndoSwap.swap(forward, label: "1-apply", root: laid.root), .swapped)
        XCTAssertEqual(linkText(section + "Unit 1, Day 5.md", root: laid.root), laid.newText)
        XCTAssertFalse(standsAnything(section + "Unit 1, Day 4.md", root: laid.root))
        let back: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .backward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(UndoSwap.swap(back, label: "1-undo", root: laid.root), .swapped)
        XCTAssertEqual(try folderNow(laid.root), before)
        XCTAssertEqual(stagedLeft(under: laid.root), [])
    }

    // MARK: - Readable (relink-2)

    /// A journal line holding a relinking move is one this version reads:
    /// the two texts travel as keys of their own, never as `linkSha`, and
    /// the op read back is the op written.
    func testARelinkFromTheJournalIsReadable() throws {
        let laid: LaidRelink = try layARelink(named: "readable", leads: .inside)
        let line: Data = try JSONEncoder().encode(laid.op)
        let object: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        XCTAssertNil(object["linkSha"])
        XCTAssertEqual(object["linkShaBefore"] as? String, laid.op.linkShaBefore)
        XCTAssertEqual(object["linkShaAfter"] as? String, laid.op.linkShaAfter)
        XCTAssertEqual(object["blobs"] as? [String], [try XCTUnwrap(laid.op.linkShaBefore), try XCTUnwrap(laid.op.linkShaAfter)])
        let read: UndoOp = try JSONDecoder().decode(UndoOp.self, from: line)
        XCTAssertTrue(read.isReadable)
        XCTAssertTrue(UndoOp.shapeIsKnown(laid.op))
        XCTAssertTrue(read.isALinksMove)
        XCTAssertEqual(read.linkShaBefore, laid.op.linkShaBefore)
        XCTAssertEqual(read.linkShaAfter, laid.op.linkShaAfter)
    }

    /// A step holding a relinking move, made through the door with both
    /// texts, then undone and redone through the list: each side holds its
    /// own text byte for byte each time, and whatever the texts name,
    /// inside or out, a file or nothing, is never read, written or made.
    func testARelinkStepIsMadeUndoneAndRedoneThroughTheList() throws {
        for leads in Leads.allCases {
            let laid: LaidRelink = try layARelink(named: "through-the-list-\(leads)", leads: leads)
            let outsideBefore: [String: String] = try outsideNow()
            let insideBefore: String? = try? text(section + "Unit 1, Day 3.md", root: laid.root)
            let blobs: [Data] = [Data(laid.oldText.utf8), Data(laid.newText.utf8)]
            let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [laid.op], blobs: blobs, root: laid.root, action: "insertClass")
            let places: UndoMemoryPlaces = UndoMemoryPlaces()
            XCTAssertEqual(JournaledWrite.perform(ops: draft, in: laid.journal, mode: .live, places: places), .applied(seq: 1), "\(leads)")
            XCTAssertEqual(linkText(section + "Unit 1, Day 5.md", root: laid.root), laid.newText, "\(leads)")
            XCTAssertFalse(standsAnything(section + "Unit 1, Day 4.md", root: laid.root), "\(leads)")

            XCTAssertEqual(laid.journal.undoNewest(resolveRoot: { _ in laid.root }, places: places), .undone(seq: 1), "\(leads)")
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.oldText, "\(leads)")
            XCTAssertFalse(standsAnything(section + "Unit 1, Day 5.md", root: laid.root), "\(leads)")

            XCTAssertEqual(laid.journal.redoNewest(resolveRoot: { _ in laid.root }, places: places), .redone(seq: 1), "\(leads)")
            XCTAssertEqual(linkText(section + "Unit 1, Day 5.md", root: laid.root), laid.newText, "\(leads)")
            XCTAssertFalse(standsAnything(section + "Unit 1, Day 4.md", root: laid.root), "\(leads)")

            XCTAssertEqual(stagedLeft(under: laid.root), [], "\(leads)")
            XCTAssertEqual(try outsideNow(), outsideBefore, "\(leads)")
            XCTAssertEqual(try? text(section + "Unit 1, Day 3.md", root: laid.root), insideBefore, "\(leads)")
        }
        try checkTheOutsideBytes()
    }

    /// The same move with `linkSha` given as well is a shape this version
    /// cannot read: the door refuses it before anything changes, and a step
    /// another version wrote holding it is a barrier on top of the list,
    /// never undone, never a reason to clear the steps below it.
    func testARelinkWithLinkShaGivenAsWellIsABarrier() throws {
        let laid: LaidRelink = try layARelink(named: "barrier", leads: .inside)
        var both: UndoOp = laid.op
        both.linkSha = laid.op.linkShaBefore
        XCTAssertFalse(UndoOp.shapeIsKnown(both))
        let line: Data = try JSONEncoder().encode(both)
        XCTAssertFalse(try JSONDecoder().decode(UndoOp.self, from: line).isReadable)
        let blobs: [Data] = [Data(laid.oldText.utf8), Data(laid.newText.utf8)]
        let places: UndoMemoryPlaces = UndoMemoryPlaces()
        let before: [String: String] = try folderNow(laid.root)
        let refused: JournaledWriteOutcome = JournaledWrite.perform(
            ops: UndoContractKinds.draft(ops: [both], blobs: blobs, root: laid.root, action: "insertClass"),
            in: laid.journal, mode: .live, places: places
        )
        XCTAssertEqual(refused, .refused(.notReadable))
        XCTAssertEqual(try folderNow(laid.root), before)

        // The readable step first, then the barrier written raw on top.
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [laid.op], blobs: blobs, root: laid.root, action: "insertClass")
        XCTAssertEqual(JournaledWrite.perform(ops: draft, in: laid.journal, mode: .live, places: places), .applied(seq: 1))
        let ops: String = "[" + String(decoding: line, as: UTF8.self) + "]"
        try UndoContractKinds.appendAStepChangingNothing(ops: ops, root: laid.root, journal: laid.journal)
        let made: [String: String] = try folderNow(laid.root)
        XCTAssertEqual(laid.journal.undoNewest(resolveRoot: { _ in laid.root }, places: places), .notAvailable)
        XCTAssertEqual(try folderNow(laid.root), made)
        XCTAssertEqual(try laid.journal.read().records.count, 2, "the list is kept")
    }

    // MARK: - Killed and recovered (relink-3)

    /// The two steps holding a relinking move the recovery tests kill.
    enum RelinkShape: CaseIterable {
        /// The relink on its own: Day 4's link to Day 5.
        case alone
        /// The relink, then Day 3's page moved into Day 4 and a new page
        /// written at Day 3 (Insert Class's own shape).
        case leavingAHandedOverPlace
    }

    /// Which of the step's three moves is stopped.
    enum RelinkWork: CaseIterable {
        case apply
        case undo
        case redo
    }

    /// Killed at every moment of every swap (before each, and inside the
    /// relink's: its new link staged, then renamed in beside the old), going
    /// forward and back, for both shapes and for texts leading inside, out
    /// to a file and out to nothing (the relink alone: a step whose page
    /// moves into a place a link leading out leaves is refused by the door,
    /// `notReadable`, before anything changes): after recovery every class page is
    /// whole before or whole after, the link at one name only holding that
    /// side's text, nothing staged left anywhere under the root, and
    /// nothing outside read, written or made. MUST FAIL with recovery's
    /// removal of the link just made skipped (M1) or taken from the
    /// source's name instead (M2).
    func testARelinkKilledAtAnyMomentIsWholeAfterRecovery() async throws {
        try layTheOutsideFiles()
        let outsideBefore: [String: String] = try outsideNow()
        var reached: Int = 0
        for shape in RelinkShape.allCases {
            for work in RelinkWork.allCases {
                let allLeads: [Leads] = shape == .alone ? Leads.allCases : [.inside]
                for leads in allLeads {
                    var index: Int = 0
                    while index < 4 {
                        let points: [UndoKillPoint] = [.beforeSwap(index), .relinkStaged(index), .relinkRenamedIn(index)]
                        for point in points {
                            if try await killARelink(shape, work, leads, at: point) {
                                reached += 1
                            }
                        }
                        index += 1
                    }
                }
            }
        }
        // alone: one swap and two inside it, for three works and three
        // leads; leaving: three swaps and two inside the relink's, for three
        // works.
        XCTAssertEqual(reached, 3 * 3 * 3 + 5 * 3)
        XCTAssertEqual(try outsideNow(), outsideBefore)
        try checkTheOutsideBytes()
    }

    /// An Undo asked for while a link the teacher made stands at the
    /// relink's other name (both links standing): refused as a change
    /// since, and neither link removed. MUST FAIL with recovery's removal
    /// applied in a plan too (M3).
    func testAnUndoWithBothLinksStandingRemovesNothing() throws {
        let laid: LaidRelink = try layARelink(named: "hand-made", leads: .inside)
        let blobs: [Data] = [Data(laid.oldText.utf8), Data(laid.newText.utf8)]
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [laid.op], blobs: blobs, root: laid.root, action: "insertClass")
        let places: UndoMemoryPlaces = UndoMemoryPlaces()
        XCTAssertEqual(JournaledWrite.perform(ops: draft, in: laid.journal, mode: .live, places: places), .applied(seq: 1))
        try layLink(section + "Unit 1, Day 4.md", holding: laid.oldText, root: laid.root)
        let outcome: UndoOutcome = laid.journal.undoNewest(resolveRoot: { _ in laid.root }, places: places)
        guard case .refused(.changedSince, _) = outcome else {
            XCTFail("the undo came to \(outcome), not changedSince")
            return
        }
        XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.oldText)
        XCTAssertEqual(linkText(section + "Unit 1, Day 5.md", root: laid.root), laid.newText)
        XCTAssertEqual(stagedLeft(under: laid.root), [])
    }

    /// Returns whether the kill point was reached (and so tested).
    @discardableResult
    func killARelink(_ shape: RelinkShape, _ work: RelinkWork, _ leads: Leads, at point: UndoKillPoint) async throws -> Bool {
        let label: String = "\(shape)-\(work)-\(leads)-\(point)"
        let made: (root: URL, journalFolder: URL, draft: UndoOpsDraft, oldText: String, newText: String) = try layAKilledRelink(shape, leads, named: "killed-" + label)
        let twin: (root: URL, journalFolder: URL, draft: UndoOpsDraft, oldText: String, newText: String) = try layAKilledRelink(shape, leads, named: "twin-" + label)
        let root: URL = made.root
        let places: UndoMemoryPlaces = UndoMemoryPlaces()

        // What the class pages hold before and after: the twin's, made whole.
        let before: [String: String] = try classPagesNow(twin.root)
        let twinJournal: UndoJournal = UndoJournal(folderURL: twin.journalFolder)
        XCTAssertEqual(JournaledWrite.perform(ops: twin.draft, in: twinJournal, mode: .live, places: UndoMemoryPlaces()), .applied(seq: 1), label)
        let after: [String: String] = try classPagesNow(twin.root)
        XCTAssertNotEqual(before, after, label)

        let dying: UndoJournal = UndoJournal(
            folderURL: made.journalFolder,
            process: UndoContractReplay.goneProcess,
            processIsAlive: { process in process.pid != 2_000_000_001 }
        )
        var reachedIt: Bool = false
        let stopsThere: (UndoKillPoint) -> Bool = { reached in
            if reached == point {
                reachedIt = true
                return true
            }
            return false
        }
        switch work {
        case .apply:
            UndoKillPoints.hook = stopsThere
            _ = JournaledWrite.perform(ops: made.draft, in: dying, mode: .live, places: places)
        case .undo:
            XCTAssertEqual(JournaledWrite.perform(ops: made.draft, in: dying, mode: .live, places: places), .applied(seq: 1), label)
            UndoKillPoints.hook = stopsThere
            _ = dying.undoNewest(resolveRoot: { _ in root }, places: places)
        case .redo:
            XCTAssertEqual(JournaledWrite.perform(ops: made.draft, in: dying, mode: .live, places: places), .applied(seq: 1), label)
            XCTAssertEqual(dying.undoNewest(resolveRoot: { _ in root }, places: places), .undone(seq: 1), label)
            UndoKillPoints.hook = stopsThere
            _ = dying.redoNewest(resolveRoot: { _ in root }, places: places)
        }
        UndoKillPoints.hook = nil
        if !reachedIt {
            return false
        }

        let survivor: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        await UndoRecovery.recoverAndRederive(survivor, resolveRoot: { _ in root }, places: places)
        let now: [String: String] = try classPagesNow(root)
        XCTAssertTrue(now == before || now == after, "\(label): neither whole before nor whole after: \(now)")
        let atFour: String? = linkText(section + "Unit 1, Day 4.md", root: root)
        let atFive: String? = linkText(section + "Unit 1, Day 5.md", root: root)
        XCTAssertTrue((atFour == made.oldText && atFive == nil) || (atFour == nil && atFive == made.newText), "\(label): links \(atFour ?? "none") and \(atFive ?? "none")")
        XCTAssertEqual(stagedLeft(under: root), [], label)
        let phase: UndoStepPhase? = try survivor.read().records[1]?.phase
        XCTAssertNotEqual(phase, .begun, label)
        XCTAssertNotEqual(phase, .undoing, label)
        XCTAssertNotEqual(phase, .redoing, label)
        XCTAssertNotEqual(phase, .interrupted, label)
        return true
    }

    /// A Day 3 page and Day 4's link holding the old text, and the draft of
    /// the step `shape` names. The texts: inside, `Unit 1, Day 3.md`
    /// becoming `Unit 1, Day 4.md`; outside, absolute texts naming files
    /// laid there, or naming nothing.
    func layAKilledRelink(_ shape: RelinkShape, _ leads: Leads, named name: String) throws -> (root: URL, journalFolder: URL, draft: UndoOpsDraft, oldText: String, newText: String) {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: name)
        let root: URL = place.root
        var oldText: String = "Unit 1, Day 3.md"
        var newText: String = "Unit 1, Day 4.md"
        switch leads {
        case .inside:
            break
        case .outToAFile:
            try layTheOutsideFiles()
            oldText = outside.appendingPathComponent("Outside Day 3.md").path
            newText = outside.appendingPathComponent("Outside Day 4.md").path
        case .outToNothing:
            oldText = outside.appendingPathComponent("Gone 3.md").path
            newText = outside.appendingPathComponent("Gone 4.md").path
        }
        try UndoContractReplay.write("Three.\n", to: section + "Unit 1, Day 3.md", in: root)
        try layLink(section + "Unit 1, Day 4.md", holding: oldText, root: root)
        let old: Data = Data(oldText.utf8)
        let new: Data = Data(newText.utf8)
        var ops: [UndoOp] = [
            UndoOp.relinkLink(
                from: section + "Unit 1, Day 4.md", to: section + "Unit 1, Day 5.md",
                linkShaBefore: UndoHash.sha256(of: old), linkShaAfter: UndoHash.sha256(of: new)
            ),
        ]
        var blobs: [Data] = [old, new]
        if shape == .leavingAHandedOverPlace {
            let three: Data = Data("Three.\n".utf8)
            let written: Data = Data("New.\n".utf8)
            ops.append(UndoOp.moveFile(from: section + "Unit 1, Day 3.md", to: section + "Unit 1, Day 4.md", sha: UndoHash.sha256(of: three)))
            ops.append(UndoOp.writeFile(path: section + "Unit 1, Day 3.md", beforeSha: nil, afterSha: UndoHash.sha256(of: written)))
            blobs.append(written)
        }
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: ops, blobs: blobs, root: root, action: "insertClass")
        return (root: root, journalFolder: place.journalFolder, draft: draft, oldText: oldText, newText: newText)
    }

    /// The two files the outside texts name, laid once.
    func layTheOutsideFiles() throws {
        let three: URL = outside.appendingPathComponent("Outside Day 3.md")
        let four: URL = outside.appendingPathComponent("Outside Day 4.md")
        if !FileManager.default.fileExists(atPath: three.path) {
            try Data("Outside three.\n".utf8).write(to: three)
            try Data("Outside four.\n".utf8).write(to: four)
        }
    }

    /// Everything in section 1, by path inside it (`folderNow`).
    func classPagesNow(_ root: URL) throws -> [String: String] {
        return try folderNow(root.appendingPathComponent(section))
    }

    // MARK: - Helpers

    /// A link at Day 4 and the op moving it to Day 5 with a new text: in
    /// the section, `Unit 1, Day 3.md` becoming `Unit 1, Day 4.md` (the
    /// page Day 3 laid beside it); outside, two absolute texts naming
    /// files laid there, or naming nothing.
    func layARelink(named name: String, leads: Leads) throws -> LaidRelink {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: name)
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let oldText: String
        let newText: String
        switch leads {
        case .inside:
            try UndoContractReplay.write("Three.\n", to: section + "Unit 1, Day 3.md", in: root)
            oldText = "Unit 1, Day 3.md"
            newText = "Unit 1, Day 4.md"
        case .outToAFile:
            let three: URL = outside.appendingPathComponent(name + " Day 3.md")
            let four: URL = outside.appendingPathComponent(name + " Day 4.md")
            try Data("Outside three.\n".utf8).write(to: three)
            try Data("Outside four.\n".utf8).write(to: four)
            oldText = three.path
            newText = four.path
        case .outToNothing:
            oldText = outside.appendingPathComponent(name + " gone 3.md").path
            newText = outside.appendingPathComponent(name + " gone 4.md").path
        }
        try layLink(section + "Unit 1, Day 4.md", holding: oldText, root: root)
        let op: UndoOp = UndoOp.relinkLink(
            from: section + "Unit 1, Day 4.md", to: section + "Unit 1, Day 5.md",
            linkShaBefore: try store(oldText, in: journal), linkShaAfter: try store(newText, in: journal)
        )
        return LaidRelink(root: root, journal: journal, op: op, oldText: oldText, newText: newText)
    }

    func makeItForward(_ laid: LaidRelink) throws {
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(UndoSwap.swap(targets, label: "1-apply", root: laid.root), .swapped)
    }

    func layLink(_ relativePath: String, holding text: String, root: URL) throws {
        let url: URL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: text)
    }

    /// The text the link at the place holds, or nil when no link is there.
    func linkText(_ relativePath: String, root: URL) -> String? {
        return try? FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent(relativePath).path)
    }

    /// Whether anything at all stands at the place, a link leading nowhere
    /// included (`lstat`).
    func standsAnything(_ relativePath: String, root: URL) -> Bool {
        var information: stat = stat()
        return lstat(root.appendingPathComponent(relativePath).path, &information) == 0
    }

    func store(_ text: String, in journal: UndoJournal) throws -> String {
        let data: Data = Data(text.utf8)
        _ = try journal.withLock { writer in
            try writer.writeBlob(data)
        }
        return UndoHash.sha256(of: data)
    }

    func readyTargets(_ plan: UndoPlan) throws -> [UndoSwapTarget] {
        guard case .ready(let targets, _, _) = plan else {
            XCTFail("the plan came to \(plan), not ready")
            throw CocoaError(.featureUnsupported)
        }
        return targets
    }

    func isChangedSince(_ plan: UndoPlan) -> Bool {
        if case .refused(.changedSince) = plan {
            return true
        }
        return false
    }

    func places(of targets: [UndoSwapTarget]) -> [String] {
        var found: [String] = []
        for target in targets {
            found.append(target.relativePath)
        }
        return found
    }

    func text(_ relativePath: String, root: URL) throws -> String {
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Every file in the folder outside, by name, with its access and
    /// modification times, read with `lstat` only (this look never opens
    /// them, so any change of time is the swap's): nothing made there, and
    /// nothing there read or written.
    func outsideNow() throws -> [String: String] {
        var found: [String: String] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: outside.path) {
            let url: URL = outside.appendingPathComponent(name)
            var information: stat = stat()
            XCTAssertEqual(lstat(url.path, &information), 0)
            found[name] = "\(information.st_atimespec.tv_sec).\(information.st_atimespec.tv_nsec) \(information.st_mtimespec.tv_sec).\(information.st_mtimespec.tv_nsec)"
        }
        return found
    }

    /// The files laid outside, byte for byte as laid.
    func checkTheOutsideBytes() throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: outside.path) {
            let data: Data = try Data(contentsOf: outside.appendingPathComponent(name))
            let laid: Bool = data == Data("Outside three.\n".utf8) || data == Data("Outside four.\n".utf8)
            XCTAssertTrue(laid, name)
        }
    }

    /// Everything under the root, by relative path: a link by its text, a
    /// file by its bytes, a folder as a folder. Never followed.
    func folderNow(_ root: URL) throws -> [String: String] {
        var found: [String: String] = [:]
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            return found
        }
        while let name = walker.nextObject() as? String {
            let url: URL = root.appendingPathComponent(name)
            let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: url.path)
            let type: FileAttributeType? = attributes[.type] as? FileAttributeType
            if type == .typeSymbolicLink {
                found[name] = "link to " + (try FileManager.default.destinationOfSymbolicLink(atPath: url.path))
            } else if type == .typeDirectory {
                found[name] = "folder"
            } else {
                found[name] = "file " + (try Data(contentsOf: url)).base64EncodedString()
            }
        }
        return found
    }

    func stagedLeft(under root: URL) -> [String] {
        var found: [String] = []
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            return found
        }
        while let name = walker.nextObject() as? String {
            if name.contains(UndoSwap.stagedMarker) {
                found.append(name)
            }
        }
        return found
    }
}
