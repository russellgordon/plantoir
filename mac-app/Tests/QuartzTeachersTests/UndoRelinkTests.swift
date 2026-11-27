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

    /// The new class page Insert Class writes in the chained kill table's
    /// shape of review 3 of mac-1.
    let newClassText: String = "New class.\n"


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
        UndoKillPoints.relinkExchangeBackFails = nil
        UndoKillPoints.beforeARenameBack = nil
        UndoKillPoints.hook = nil
        JournaledStep.modeOverride = nil
        UndoJournalLocation.folderOverride = nil
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

    /// The link-moving steps review F's kill table runs: each a set of
    /// links laid on class pages and ONE step moving them, as Insert Class
    /// makes it, highest first (U4b3 review F).
    enum ChainShape: CaseIterable {
        /// Review D: Day 5's link (`Unit 1, Day 2.md`) relinked to Day 6
        /// (`Unit 1, Day 3.md`), then Day 4's (`Unit 1, Day 1.md`) to Day 5
        /// (`Unit 1, Day 2.md`, the first move's old text).
        case twoChainedRelinks
        /// Review F: the same with three links, Day 6 to Day 7 first.
        case threeChainedRelinks
        /// Review F's "not probed": a plain link move of Day 5 (holding
        /// `Unit 1, Day 2.md`) to Day 6, then Day 4's link relinked to Day 5
        /// with that same text: the move's place is the relink's place.
        case aMoveThenARelinkIntoItsPlace
        /// The other order: Day 5's link relinked to Day 6 (`Unit 1, Day
        /// 2.md` becoming `Unit 1, Day 3.md`), then Day 4's link, holding
        /// `Unit 1, Day 2.md` too, moved plainly into Day 5.
        case aRelinkThenAMoveIntoItsPlace
        /// Review 3 of mac-1, MEDIUM: Insert Class at a day whose page is a
        /// link. Day 4's link (`Unit 1, Day 3.md`) relinked to Day 5
        /// (`Unit 1, Day 4.md`), then the new class page written at Day 4,
        /// the relink's `from`: the write's staged page and, going back, its
        /// kept original stand beside a relink's place, and are the step's,
        /// never the teacher's.
        case aNewClassWrittenAtTheRelinksFrom
    }

    /// One shape laid out: its folder, journal folder, draft, and the class
    /// days whose links it changes.
    struct LaidChain {

        // MARK: - Stored properties

        let root: URL

        let journalFolder: URL

        let draft: UndoOpsDraft

        let days: [Int]
    }

    /// Every stop point the door has, for a step of `swaps` swaps.
    func everyStopPoint(swaps: Int) -> [UndoKillPoint] {
        var points: [UndoKillPoint] = [.afterBegin, .afterTheCheck, .afterUndoing, .afterRedoing]
        var index: Int = 0
        while index < swaps {
            points.append(.beforeSwap(index))
            points.append(.relinkStaged(index))
            points.append(.relinkRenamedIn(index))
            index += 1
        }
        points.append(.beforeApplied)
        points.append(.beforeUndone)
        points.append(.beforeRedone)
        points.append(.whileDeletingAFolder)
        return points
    }

    /// Review F of U4b3, MEDIUM: two and three chained relinks, and a plain
    /// link move chained to a relink either way round, each killed at
    /// EVERY stop point of the door (`afterBegin`, `afterTheCheck`, each
    /// `beforeSwap`, both halves inside each relink's swap, `afterUndoing`,
    /// `afterRedoing`, `beforeApplied`, `beforeUndone`, `beforeRedone`,
    /// `whileDeletingAFolder`), going forward, back and forward again: after
    /// recovery every link of the step is exactly as before or exactly as
    /// after, nothing staged is left, and the step is settled on the side
    /// its links show. MUST FAIL with review D's rule (one look along the
    /// chain) and with plain link moves left out of the reading (9 of the
    /// 40 move-chained kills). Review 3 of mac-1, MEDIUM: Insert Class's
    /// new page written at the relink's `from` (`aNewClassWrittenAtTheRelinksFrom`)
    /// leaves nothing kept under a visible name and no empty day; MUST FAIL
    /// with every staged name beside a relink's place judged by the one
    /// rule (7 of its 20 kills, every run, F-J; each failing kill is
    /// gathered and asserted once at the end, review 4 of mac-1, LOW).
    func testChainedLinkMovesKilledAtEveryStopPointLoseNoLink() async throws {
        var reached: Int = 0
        var expected: Int = 0
        var faults: [String] = []
        for shape in ChainShape.allCases {
            let swaps: Int = shape == .threeChainedRelinks ? 3 : 2
            let relinks: Int = shape == .twoChainedRelinks || shape == .threeChainedRelinks ? swaps : 1
            for work in RelinkWork.allCases {
                for point in everyStopPoint(swaps: swaps) {
                    let killed: (reached: Bool, faults: [String]) = try await killAChain(shape, work, at: point)
                    if killed.reached {
                        reached += 1
                    }
                    for fault in killed.faults {
                        faults.append(fault)
                    }
                }
                // An apply: afterBegin, each swap, both halves of each
                // relink, beforeApplied. An Undo or a Redo: afterTheCheck,
                // afterUndoing or afterRedoing, the same swaps, beforeUndone
                // or beforeRedone.
                expected += work == .apply ? 2 + swaps + 2 * relinks : 3 + swaps + 2 * relinks
            }
        }
        // Every failing kill gathered and asserted ONCE, on the main actor
        // (review 4 of mac-1, LOW): XCTest dropped some failures recorded
        // after an `await`, so a count read from its summary was not the
        // code's. One fault line per failing kill.
        let reachedCount: Int = reached
        let expectedCount: Int = expected
        let failing: [String] = faults
        await MainActor.run {
            XCTAssertEqual(reachedCount, expectedCount)
            XCTAssertEqual(failing, [], "\(failing.count) failing kills")
        }
    }

    /// A swap of two links (Day 4 and Day 5, each relinked into the
    /// other's place) is not a step the door makes: a relink never renames
    /// over an occupied place, so the step is refused before anything
    /// changes, every link left as it was.
    func testTwoLinksSwappedInOneStepAreRefusedWithNothingChanged() throws {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "swapped")
        let root: URL = place.root
        try layLink(section + "Unit 1, Day 4.md", holding: "Unit 1, Day 1.md", root: root)
        try layLink(section + "Unit 1, Day 5.md", holding: "Unit 1, Day 2.md", root: root)
        let one: Data = Data("Unit 1, Day 1.md".utf8)
        let two: Data = Data("Unit 1, Day 2.md".utf8)
        let ops: [UndoOp] = [
            UndoOp.relinkLink(
                from: section + "Unit 1, Day 4.md", to: section + "Unit 1, Day 5.md",
                linkShaBefore: UndoHash.sha256(of: one), linkShaAfter: UndoHash.sha256(of: two)
            ),
            UndoOp.relinkLink(
                from: section + "Unit 1, Day 5.md", to: section + "Unit 1, Day 4.md",
                linkShaBefore: UndoHash.sha256(of: two), linkShaAfter: UndoHash.sha256(of: one)
            ),
        ]
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: ops, blobs: [one, two], root: root, action: "insertClass")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let outcome: JournaledWriteOutcome = JournaledWrite.perform(ops: draft, in: journal, mode: .live, places: UndoMemoryPlaces())
        XCTAssertNotEqual(outcome, .applied(seq: 1))
        XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: root), "Unit 1, Day 1.md")
        XCTAssertEqual(linkText(section + "Unit 1, Day 5.md", root: root), "Unit 1, Day 2.md")
        XCTAssertEqual(stagedLeft(under: root), [])
    }

    /// Returns whether the kill point was reached (and so tested), and one
    /// line per thing found wrong after recovery, gathered rather than
    /// asserted after the `await` (review 4 of mac-1, LOW).
    func killAChain(_ shape: ChainShape, _ work: RelinkWork, at point: UndoKillPoint) async throws -> (reached: Bool, faults: [String]) {
        let label: String = "\(shape)-\(work)-\(point)"
        let made: LaidChain = try layAChain(shape, named: "killed-" + label)
        let twin: LaidChain = try layAChain(shape, named: "twin-" + label)
        let root: URL = made.root
        let places: UndoMemoryPlaces = UndoMemoryPlaces()
        let linksBefore: [String?] = linksOn(twin.days, root: twin.root)
        let twinJournal: UndoJournal = UndoJournal(folderURL: twin.journalFolder)
        XCTAssertEqual(JournaledWrite.perform(ops: twin.draft, in: twinJournal, mode: .live, places: UndoMemoryPlaces()), .applied(seq: 1), label)
        let linksAfter: [String?] = linksOn(twin.days, root: twin.root)
        XCTAssertNotEqual(linksBefore, linksAfter, label)

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
            return (reached: false, faults: [])
        }
        var faults: [String] = []

        let survivor: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        await UndoRecovery.recoverAndRederive(survivor, resolveRoot: { _ in root }, places: places)
        let links: [String?] = linksOn(made.days, root: root)
        if links != linksBefore && links != linksAfter {
            faults.append("\(label): links \(links)")
        }
        let staged: [String] = stagedLeft(under: root)
        if !staged.isEmpty {
            faults.append("\(label): staged \(staged)")
        }
        // Undo's own staged items are never the teacher's: nothing is ever
        // kept under a visible name for them (review 3 of mac-1, MEDIUM).
        let kept: [String] = keptLeft(under: root)
        if !kept.isEmpty {
            faults.append("\(label): kept \(kept)")
        }
        if shape == .aNewClassWrittenAtTheRelinksFrom {
            // Whole after: the new class page at Day 4, never an empty day;
            // whole before: Day 4's link, and nothing else there.
            let dayFour: URL = root.appendingPathComponent(section + "Unit 1, Day 4.md")
            if links == linksAfter {
                let held: Data? = try? Data(contentsOf: dayFour)
                if held != Data(newClassText.utf8) {
                    faults.append("\(label): Day 4 is not the new class page")
                }
            } else if !UndoSwap.isALink(dayFour) {
                faults.append("\(label): Day 4 is not the link")
            }
        }
        let phase: UndoStepPhase? = try survivor.read().records[1]?.phase
        // Settled on the side its links show: done when they are as after,
        // failed or rolled back (an apply) or undone (an Undo or a Redo)
        // when they are as before.
        var settledPhases: [UndoStepPhase] = [.done]
        if links == linksBefore {
            settledPhases = work == .apply ? [.failed, .rolledBack] : [.undone]
        }
        var settledThere: Bool = false
        if let found = phase {
            settledThere = settledPhases.contains(found)
        }
        if !settledThere {
            faults.append("\(label): phase \(String(describing: phase))")
        }
        return (reached: true, faults: faults)
    }

    /// The links on these class days, each its text or nil.
    func linksOn(_ days: [Int], root: URL) -> [String?] {
        var links: [String?] = []
        for day in days {
            links.append(linkText(section + "Unit 1, Day \(day).md", root: root))
        }
        return links
    }

    /// The links `shape` starts from, and the draft of its step.
    func layAChain(_ shape: ChainShape, named name: String) throws -> LaidChain {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: name)
        let root: URL = place.root
        let one: Data = Data("Unit 1, Day 1.md".utf8)
        let two: Data = Data("Unit 1, Day 2.md".utf8)
        let three: Data = Data("Unit 1, Day 3.md".utf8)
        let four: Data = Data("Unit 1, Day 4.md".utf8)
        var ops: [UndoOp] = []
        var blobs: [Data] = [one, two, three]
        var days: [Int] = [4, 5, 6]
        switch shape {
        case .twoChainedRelinks:
            try layLink(section + "Unit 1, Day 4.md", holding: "Unit 1, Day 1.md", root: root)
            try layLink(section + "Unit 1, Day 5.md", holding: "Unit 1, Day 2.md", root: root)
            ops.append(relink(5, 6, from: two, to: three))
            ops.append(relink(4, 5, from: one, to: two))
        case .threeChainedRelinks:
            try layLink(section + "Unit 1, Day 4.md", holding: "Unit 1, Day 1.md", root: root)
            try layLink(section + "Unit 1, Day 5.md", holding: "Unit 1, Day 2.md", root: root)
            try layLink(section + "Unit 1, Day 6.md", holding: "Unit 1, Day 3.md", root: root)
            ops.append(relink(6, 7, from: three, to: four))
            ops.append(relink(5, 6, from: two, to: three))
            ops.append(relink(4, 5, from: one, to: two))
            blobs.append(four)
            days = [4, 5, 6, 7]
        case .aMoveThenARelinkIntoItsPlace:
            try layLink(section + "Unit 1, Day 4.md", holding: "Unit 1, Day 1.md", root: root)
            try layLink(section + "Unit 1, Day 5.md", holding: "Unit 1, Day 2.md", root: root)
            ops.append(UndoOp.moveLink(from: section + "Unit 1, Day 5.md", to: section + "Unit 1, Day 6.md", linkSha: UndoHash.sha256(of: two)))
            ops.append(relink(4, 5, from: one, to: two))
            blobs = [one, two]
        case .aRelinkThenAMoveIntoItsPlace:
            try layLink(section + "Unit 1, Day 4.md", holding: "Unit 1, Day 2.md", root: root)
            try layLink(section + "Unit 1, Day 5.md", holding: "Unit 1, Day 2.md", root: root)
            ops.append(relink(5, 6, from: two, to: three))
            ops.append(UndoOp.moveLink(from: section + "Unit 1, Day 4.md", to: section + "Unit 1, Day 5.md", linkSha: UndoHash.sha256(of: two)))
            blobs = [two, three]
        case .aNewClassWrittenAtTheRelinksFrom:
            // The texts lead inside, as Insert Class's do: Day 4's link to
            // Day 3's page, and Day 5's new link to the new class at Day 4.
            try UndoContractReplay.write("Three.\n", to: section + "Unit 1, Day 3.md", in: root)
            try layLink(section + "Unit 1, Day 4.md", holding: "Unit 1, Day 3.md", root: root)
            let newClass: Data = Data(newClassText.utf8)
            ops.append(relink(4, 5, from: three, to: four))
            ops.append(UndoOp.writeFile(path: section + "Unit 1, Day 4.md", beforeSha: nil, afterSha: UndoHash.sha256(of: newClass)))
            blobs = [three, four, newClass]
            days = [4, 5]
        }
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: ops, blobs: blobs, root: root, action: "insertClass")
        return LaidChain(root: root, journalFolder: place.journalFolder, draft: draft, days: days)
    }

    /// A relinking move of class day `start`'s link to day `end`.
    func relink(_ start: Int, _ end: Int, from before: Data, to after: Data) -> UndoOp {
        return UndoOp.relinkLink(
            from: section + "Unit 1, Day \(start).md", to: section + "Unit 1, Day \(end).md",
            linkShaBefore: UndoHash.sha256(of: before), linkShaAfter: UndoHash.sha256(of: after)
        )
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

    // MARK: - Where the link stands (mac-1)

    /// Day 4's link and the op re-pointing it where it stands: `from` and
    /// `to` both Day 4, the old text leading to Day 3's page (or out of the
    /// working folder, to a file or to nothing) and the new to Day 5's.
    func layARelinkWhereItStands(named name: String, leads: Leads) throws -> LaidRelink {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: name)
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let texts: (old: String, new: String) = try textsWhereItStands(leads, named: name, root: root)
        try layLink(section + "Unit 1, Day 4.md", holding: texts.old, root: root)
        let op: UndoOp = UndoOp.relinkLink(
            from: section + "Unit 1, Day 4.md", to: section + "Unit 1, Day 4.md",
            linkShaBefore: try store(texts.old, in: journal), linkShaAfter: try store(texts.new, in: journal)
        )
        return LaidRelink(root: root, journal: journal, op: op, oldText: texts.old, newText: texts.new)
    }

    /// The two texts a link re-pointed where it stands holds, and the files
    /// they lead to laid: inside, Day 3's and Day 5's pages by relative
    /// text; outside, two absolute texts naming files laid there, or
    /// naming nothing.
    func textsWhereItStands(_ leads: Leads, named name: String, root: URL) throws -> (old: String, new: String) {
        switch leads {
        case .inside:
            try UndoContractReplay.write("Three.\n", to: section + "Unit 1, Day 3.md", in: root)
            try UndoContractReplay.write("Five.\n", to: section + "Unit 1, Day 5.md", in: root)
            return (old: "Unit 1, Day 3.md", new: "Unit 1, Day 5.md")
        case .outToAFile:
            let three: URL = outside.appendingPathComponent(name + " Day 3.md")
            let five: URL = outside.appendingPathComponent(name + " Day 5.md")
            try Data("Outside three.\n".utf8).write(to: three)
            try Data("Outside four.\n".utf8).write(to: five)
            return (old: three.path, new: five.path)
        case .outToNothing:
            return (
                old: outside.appendingPathComponent(name + " gone 3.md").path,
                new: outside.appendingPathComponent(name + " gone 5.md").path
            )
        }
    }

    /// A `move` whose `from` and `to` are one place byte for byte, carrying
    /// the pair and nothing else, is readable; the same as a `moveApart` or
    /// a `setAside`, or with `sha`, `listingSha` or `linkSha` beside the
    /// pair, is not. MUST FAIL with the exception taken out of
    /// `shapeIsKnown` (M1).
    func testARelinkWhereTheLinkStandsIsReadableOnlyAsAMoveCarryingThePair() throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "readable-in-place", leads: .inside)
        XCTAssertTrue(UndoOp.shapeIsKnown(laid.op))
        let line: Data = try JSONEncoder().encode(laid.op)
        XCTAssertTrue(try JSONDecoder().decode(UndoOp.self, from: line).isReadable)

        var barriers: [String: UndoOp] = [:]
        var apart: UndoOp = laid.op
        apart.kind = UndoOpKind.moveApart.rawValue
        barriers["moveApart"] = apart
        var aside: UndoOp = laid.op
        aside.kind = UndoOpKind.setAside.rawValue
        barriers["setAside"] = aside
        var withSha: UndoOp = laid.op
        withSha.sha = laid.op.linkShaBefore
        barriers["sha beside the pair"] = withSha
        var withListing: UndoOp = laid.op
        withListing.listingSha = laid.op.linkShaBefore
        barriers["listingSha beside the pair"] = withListing
        var withLinkSha: UndoOp = laid.op
        withLinkSha.linkSha = laid.op.linkShaBefore
        barriers["linkSha beside the pair"] = withLinkSha
        var otherSpelling: UndoOp = laid.op
        otherSpelling.to = section + "unit 1, day 4.md"
        barriers["the same place spelled another way"] = otherSpelling
        for (label, op) in barriers {
            XCTAssertFalse(UndoOp.shapeIsKnown(op), label)
            let encoded: Data = try JSONEncoder().encode(op)
            XCTAssertFalse(try JSONDecoder().decode(UndoOp.self, from: encoded).isReadable, label)
        }
    }

    /// Judged at the ONE place, each way: the old text is before, the new
    /// after; nothing, a plain file, a folder or a third text is neither
    /// (changed since, Undo and Redo alike); a folder above that cannot be
    /// read is cannot tell. MUST FAIL with the place read for `to` by the
    /// old text (neither both ways, M2).
    func testARelinkWhereTheLinkStandsIsJudgedAtTheOnePlace() throws {
        let cases: [String] = ["old text", "new text", "nothing", "file", "folder", "third text", "unreadable"]
        for given in cases {
            let laid: LaidRelink = try layARelinkWhereItStands(named: "judged-\(given)", leads: .inside)
            let url: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
            if given != "old text" && given != "unreadable" {
                XCTAssertTrue(UndoSwap.removeALink(at: url), given)
            }
            switch given {
            case "new text":
                try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: laid.newText)
            case "file":
                try Data("A page.\n".utf8).write(to: url)
            case "folder":
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            case "third text":
                try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "Unit 1, Day 1.md")
            default:
                break
            }
            let folder: URL = laid.root.appendingPathComponent(section)
            if given == "unreadable" {
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
            }
            let state: UndoOpState = UndoCheck.wholeState(of: laid.op, root: laid.root, places: UndoMemoryPlaces())
            if given == "unreadable" {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            }
            let wanted: UndoOpState
            switch given {
            case "old text":
                wanted = .before
            case "new text":
                wanted = .after
            case "unreadable":
                wanted = .cannotTell
            default:
                wanted = .neither
            }
            XCTAssertEqual(state, wanted, given)
            let undo: UndoCheckVerdict = UndoCheck.verdict(for: state, direction: .backward)
            let redo: UndoCheckVerdict = UndoCheck.verdict(for: state, direction: .forward)
            if wanted == .neither {
                XCTAssertEqual(undo, .changedSince, given)
                XCTAssertEqual(redo, .changedSince, given)
            }
            if wanted == .before {
                XCTAssertEqual(undo, .alreadyBack, given)
                XCTAssertEqual(redo, .canRedo, given)
            }
            if wanted == .after {
                XCTAssertEqual(undo, .canUndo, given)
                XCTAssertEqual(redo, .alreadyRedone, given)
            }
        }
    }

    /// Swapped by the door going forward and back: the link holds exactly
    /// the new text, then the old, never followed; nothing staged is left,
    /// and whatever either text names, inside or out, a file or nothing, is
    /// byte for byte as it was. MUST FAIL with the staged link renamed in
    /// exclusively (every swap fails, M3).
    func testARelinkWhereTheLinkStandsGoesForwardAndBack() throws {
        for leads in Leads.allCases {
            let laid: LaidRelink = try layARelinkWhereItStands(named: "swapped-in-place-\(leads)", leads: leads)
            let outsideBefore: [String: String] = try outsideNow()
            let pagesBefore: [String: String] = try pagesBesideTheLink(laid.root)
            let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
            XCTAssertEqual(places(of: forward), [section + "Unit 1, Day 4.md"], "\(leads)")
            XCTAssertEqual(UndoSwap.swap(forward, label: "1-apply", root: laid.root), .swapped, "\(leads)")
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.newText, "\(leads)")
            XCTAssertEqual(stagedLeft(under: laid.root), [], "\(leads)")
            XCTAssertEqual(try pagesBesideTheLink(laid.root), pagesBefore, "\(leads)")

            let back: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .backward, root: laid.root, journal: laid.journal))
            XCTAssertEqual(UndoSwap.swap(back, label: "1-undo", root: laid.root), .swapped, "\(leads)")
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.oldText, "\(leads)")
            XCTAssertEqual(stagedLeft(under: laid.root), [], "\(leads)")
            XCTAssertEqual(try pagesBesideTheLink(laid.root), pagesBefore, "\(leads)")
            XCTAssertEqual(try outsideNow(), outsideBefore, "\(leads)")
        }
        try checkTheOutsideBytes()
    }

    /// A later target that fails after the link was re-pointed: the link
    /// is given its old text back the same way, nothing staged is left.
    func testALaterFailureGivesTheLinkWhereItStandsItsOldTextBack() throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "reversed-in-place", leads: .inside)
        try UndoContractReplay.write("Eight.\n", to: section + "Unit 1, Day 8.md", in: laid.root)
        let ops: [UndoOp] = [
            laid.op,
            UndoOp.moveFile(from: section + "Unit 1, Day 8.md", to: section + "Unit 1, Day 9.md", sha: UndoHash.sha256(of: Data("Eight.\n".utf8))),
        ]
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .forward, root: laid.root, journal: laid.journal))
        UndoKillPoints.fileInUseAtSwap = { index in
            return index == 1
        }
        let result: UndoSwapResult = UndoSwap.swap(targets, label: "1-apply", root: laid.root)
        UndoKillPoints.fileInUseAtSwap = nil
        XCTAssertEqual(result, .refused(.fileIsInUse(path: section + "Unit 1, Day 9.md")))
        XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.oldText)
        XCTAssertEqual(try text(section + "Unit 1, Day 8.md", root: laid.root), "Eight.\n")
        XCTAssertEqual(stagedLeft(under: laid.root), [])
    }

    /// The link where it stands made through `JournaledStep` with
    /// `relinkLink(p, to: p, textAfter:)`, its texts leading inside the
    /// working folder and out of it: one step with one op naming the one
    /// place twice, both texts in the list byte for byte, the link holding
    /// the new text, and the file it led to and the file it now leads to
    /// byte for byte as before (nothing written through it). Undo gives the
    /// old text back and Redo the new, each one step.
    func testARelinkWhereTheLinkStandsIsMadeThroughJournaledStepUndoneAndRedone() throws {
        for leads in [Leads.inside, Leads.outToAFile] {
            let laid: LaidRelink = try layARelinkWhereItStands(named: "step-in-place-\(leads)", leads: leads)
            let list: URL = parent.appendingPathComponent("list-in-place-\(leads)", isDirectory: true)
            UndoJournalLocation.folderOverride = list
            JournaledStep.modeOverride = .live
            let link: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
            let outsideBefore: [String: String] = try outsideNow()
            let pagesBefore: [String: String] = try pagesBesideTheLink(laid.root)
            let step: JournaledStep = stepWhereItStands(laid.root)
            XCTAssertTrue(step.relinkLink(link, to: link, textAfter: Data(laid.newText.utf8)), "\(leads)")
            try step.make()

            let journal: UndoJournal = UndoJournalLocation.standardJournal()
            let records: [Int: UndoStepRecord] = try journal.read().records
            XCTAssertEqual(records.count, 1, "\(leads)")
            let ops: [UndoOp] = try XCTUnwrap(records[1]).step.ops
            XCTAssertEqual(ops.count, 1, "\(leads)")
            let op: UndoOp = try XCTUnwrap(ops.first)
            XCTAssertEqual(op.from, section + "Unit 1, Day 4.md", "\(leads)")
            XCTAssertEqual(op.to, section + "Unit 1, Day 4.md", "\(leads)")
            XCTAssertTrue(op.isARelink, "\(leads)")
            XCTAssertNil(op.linkSha, "\(leads)")
            XCTAssertEqual(journal.readBlob(sha: try XCTUnwrap(op.linkShaBefore)), Data(laid.oldText.utf8), "\(leads)")
            XCTAssertEqual(journal.readBlob(sha: try XCTUnwrap(op.linkShaAfter)), Data(laid.newText.utf8), "\(leads)")
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.newText, "\(leads)")
            XCTAssertEqual(try pagesBesideTheLink(laid.root), pagesBefore, "\(leads)")

            let root: URL = laid.root
            XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1), "\(leads)")
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.oldText, "\(leads)")
            XCTAssertEqual(journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .redone(seq: 1), "\(leads)")
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.newText, "\(leads)")
            XCTAssertEqual(try journal.read().records.count, 1, "\(leads)")
            XCTAssertEqual(try pagesBesideTheLink(laid.root), pagesBefore, "\(leads)")
            XCTAssertEqual(stagedLeft(under: laid.root), [], "\(leads)")
            XCTAssertEqual(try outsideNow(), outsideBefore, "\(leads): something outside was read, written or made")
            JournaledStep.modeOverride = nil
            UndoJournalLocation.folderOverride = nil
        }
        try checkTheOutsideBytes()
    }

    /// A write, a new file or a removal planned at the link's one place in
    /// the same step refuses the step before anything changes: the place
    /// is never handed over, since the link stays there holding a text the
    /// step changes. MUST FAIL with the one place freed in `JournaledStep`
    /// (M5).
    func testAWriteAtTheOnePlaceRefusesTheStepBeforeAnythingChanges() throws {
        for planned in ["write", "writeNew", "remove"] {
            let laid: LaidRelink = try layARelinkWhereItStands(named: "write-in-place-\(planned)", leads: .inside)
            UndoJournalLocation.folderOverride = parent.appendingPathComponent("list-write-\(planned)", isDirectory: true)
            JournaledStep.modeOverride = .live
            let link: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
            let before: [String: String] = try folderNow(laid.root)
            let step: JournaledStep = stepWhereItStands(laid.root)
            XCTAssertTrue(step.relinkLink(link, to: link, textAfter: Data(laid.newText.utf8)), planned)
            switch planned {
            case "write":
                step.write("Written.\n", to: link)
            case "writeNew":
                step.writeNew(Data("Written.\n".utf8), to: link)
            default:
                step.remove(link)
            }
            XCTAssertThrowsError(try step.make(), planned) { error in
                guard case JournaledStepError.refused(.cannotTellNow, _) = error else {
                    XCTFail("\(planned): refused with \(error), not cannotTellNow")
                    return
                }
            }
            XCTAssertEqual(try folderNow(laid.root), before, planned)
            XCTAssertEqual(try UndoJournalLocation.standardJournal().read().records.count, 0, planned)
            JournaledStep.modeOverride = nil
            UndoJournalLocation.folderOverride = nil
        }
    }

    /// The link changed by hand between the plan and the make: refused
    /// changed since, nothing changed, the hand-made text kept.
    func testTheLinkChangedByHandBetweenPlanAndMakeIsRefused() throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "hand-in-place", leads: .inside)
        UndoJournalLocation.folderOverride = parent.appendingPathComponent("list-hand", isDirectory: true)
        JournaledStep.modeOverride = .live
        let link: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
        let step: JournaledStep = stepWhereItStands(laid.root)
        XCTAssertTrue(step.relinkLink(link, to: link, textAfter: Data(laid.newText.utf8)))
        XCTAssertTrue(UndoSwap.removeALink(at: link))
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "Unit 1, Day 1.md")
        let before: [String: String] = try classPagesNow(laid.root)
        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.refused(.changedSince, _) = error else {
                XCTFail("refused with \(error), not changedSince")
                return
            }
        }
        XCTAssertEqual(try classPagesNow(laid.root), before)
        XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), "Unit 1, Day 1.md")
        XCTAssertEqual(stagedLeft(under: laid.root), [])
        JournaledStep.modeOverride = nil
        UndoJournalLocation.folderOverride = nil
    }

    /// Killed inside the swap of a link re-pointed where it stands, going
    /// forward, back and forward again: with the new link staged beside it
    /// (`relinkStaged`), and with the two swapped and the old link not yet
    /// removed from the staged name (`relinkSwapped`), texts leading inside,
    /// out to a file and out to nothing. Recovery settles it whole each
    /// way: the link holds the old text or the new, the step is settled,
    /// and no staged item is left. Each run makes its own list. MUST FAIL
    /// with the staged tidy skipped (M4).
    func testARelinkWhereTheLinkStandsKilledInsideItsSwapIsWholeAfterRecovery() async throws {
        var reached: Int = 0
        for work in RelinkWork.allCases {
            for leads in Leads.allCases {
                for point in ["relinkStaged:0", "relinkSwapped:0"] {
                    if try await killARelinkWhereItStands(work, leads, at: point) {
                        reached += 1
                    }
                }
            }
        }
        XCTAssertEqual(reached, 3 * 3 * 2)
    }

    /// Returns whether the stop point was reached (and so tested).
    func killARelinkWhereItStands(_ work: RelinkWork, _ leads: Leads, at pointName: String) async throws -> Bool {
        let label: String = "in-place-\(work)-\(leads)-\(pointName)"
        let laid: LaidRelink = try layARelinkWhereItStands(named: "killed-" + label, leads: leads)
        let root: URL = laid.root
        let journalFolder: URL = root.deletingLastPathComponent().appendingPathComponent("undo", isDirectory: true)
        let draft: UndoOpsDraft = UndoContractKinds.draft(
            ops: [laid.op], blobs: [Data(laid.oldText.utf8), Data(laid.newText.utf8)], root: root, action: "insertClass"
        )
        let places: UndoMemoryPlaces = UndoMemoryPlaces()
        let point: UndoKillPoint = UndoContractReplay.killPoint(named: pointName)
        let dying: UndoJournal = UndoJournal(
            folderURL: journalFolder,
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
            _ = JournaledWrite.perform(ops: draft, in: dying, mode: .live, places: places)
        case .undo:
            XCTAssertEqual(JournaledWrite.perform(ops: draft, in: dying, mode: .live, places: places), .applied(seq: 1), label)
            UndoKillPoints.hook = stopsThere
            _ = dying.undoNewest(resolveRoot: { _ in root }, places: places)
        case .redo:
            XCTAssertEqual(JournaledWrite.perform(ops: draft, in: dying, mode: .live, places: places), .applied(seq: 1), label)
            XCTAssertEqual(dying.undoNewest(resolveRoot: { _ in root }, places: places), .undone(seq: 1), label)
            UndoKillPoints.hook = stopsThere
            _ = dying.redoNewest(resolveRoot: { _ in root }, places: places)
        }
        UndoKillPoints.hook = nil
        XCTAssertTrue(reachedIt, label)
        if !reachedIt {
            return false
        }
        // What the swap left at the stop point: the staged link beside the
        // place, holding the text going in (staged) or the text going out
        // (swapped); the place holding the other.
        let goingIn: String = work == .undo ? laid.oldText : laid.newText
        let goingOut: String = work == .undo ? laid.newText : laid.oldText
        let staged: [String] = stagedLeft(under: root)
        XCTAssertEqual(staged.count, 1, "\(label): \(staged)")
        if let name = staged.first {
            let stagedText: String? = linkText(name, root: root)
            let swapped: Bool = pointName.hasPrefix("relinkSwapped")
            XCTAssertEqual(stagedText, swapped ? goingOut : goingIn, label)
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: root), swapped ? goingIn : goingOut, label)
        }

        let survivor: UndoJournal = UndoJournal(folderURL: journalFolder)
        await UndoRecovery.recoverAndRederive(survivor, resolveRoot: { _ in root }, places: places)
        let now: String? = linkText(section + "Unit 1, Day 4.md", root: root)
        XCTAssertTrue(now == laid.oldText || now == laid.newText, "\(label): the link holds \(now ?? "nothing")")
        XCTAssertEqual(stagedLeft(under: root), [], label)
        let phase: UndoStepPhase? = try survivor.read().records[1]?.phase
        XCTAssertNotEqual(phase, .begun, label)
        XCTAssertNotEqual(phase, .undoing, label)
        XCTAssertNotEqual(phase, .redoing, label)
        XCTAssertNotEqual(phase, .interrupted, label)
        return true
    }

    // MARK: - Where the link stands: fix round one (mac-1)

    /// The same place spelled in another Unicode normalisation (`Café`
    /// composed in `from`, decomposed in `to`) is not ONE path byte for
    /// byte, so the op is not a relink where the link stands, and its two
    /// places overlap on the Mac: not readable. MUST FAIL with Swift's `==`
    /// (canonical equivalence) as the test (review 1, MEDIUM 1). (At the
    /// swap, Foundation's file URLs already give both spellings one `path`,
    /// measured: the two are one item on APFS, so the dispatch's question
    /// by URL is never asked of such an op, which is refused unread.)
    func testTheSamePlaceInAnotherUnicodeNormalisationIsNotARelinkWhereItStands() throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "normalisation", leads: .inside)
        var op: UndoOp = laid.op
        op.from = section + "Caf\u{E9}.md"
        op.to = section + "Cafe\u{301}.md"
        XCTAssertFalse(op.isARelinkWhereItStands)
        XCTAssertFalse(UndoOp.shapeIsKnown(op))
        let encoded: Data = try JSONEncoder().encode(op)
        XCTAssertFalse(try JSONDecoder().decode(UndoOp.self, from: encoded).isReadable)

    }

    /// A volume that refuses the one exchange (`RENAME_SWAP`, as SMB may):
    /// nothing has moved, nothing staged is left, and the refusal is
    /// `couldNotWrite` (the change could not be made in that folder), never
    /// `fileIsInUse`, which would tell the teacher the page is open
    /// somewhere when it is not (review 1, LOW 1).
    func testAVolumeThatRefusesTheExchangeIsRefusedWithATrueReason() throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "refused-exchange", leads: .inside)
        let place: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
        let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
        UndoKillPoints.relinkRenameInFails = { url in
            return url.standardizedFileURL.path == place.standardizedFileURL.path
        }
        let result: UndoSwapResult = UndoSwap.swap(forward, label: "1-apply", root: laid.root)
        UndoKillPoints.relinkRenameInFails = nil
        XCTAssertEqual(result, .refused(.couldNotWrite(path: section + "Unit 1, Day 4.md")))
        XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.oldText)
        XCTAssertEqual(stagedLeft(under: laid.root), [])
    }

    /// Every tidy recovery makes removes a staged link by the text it
    /// holds: a link under the step's staged name holding a THIRD text
    /// (neither of the step's) is not the step's: it is never removed, and
    /// (review 2's one rule) never left hidden: its place holds the step's
    /// old link, so it is kept under a visible name beside it, while the
    /// step is settled. MUST FAIL with any tidy removing a staged link by
    /// its name alone (review 1, LOW 2).
    func testRecoveryKeepsAStagedLinkHoldingAnotherTextVisible() async throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "third-text", leads: .inside)
        let root: URL = laid.root
        let journalFolder: URL = root.deletingLastPathComponent().appendingPathComponent("undo", isDirectory: true)
        let draft: UndoOpsDraft = UndoContractKinds.draft(
            ops: [laid.op], blobs: [Data(laid.oldText.utf8), Data(laid.newText.utf8)], root: root, action: "insertClass"
        )
        let places: UndoMemoryPlaces = UndoMemoryPlaces()
        let dying: UndoJournal = UndoJournal(
            folderURL: journalFolder,
            process: UndoContractReplay.goneProcess,
            processIsAlive: { process in process.pid != 2_000_000_001 }
        )
        UndoKillPoints.hook = { reached in
            return reached == .relinkStaged(0)
        }
        _ = JournaledWrite.perform(ops: draft, in: dying, mode: .live, places: places)
        UndoKillPoints.hook = nil
        let staged: [String] = stagedLeft(under: root)
        XCTAssertEqual(staged.count, 1, "\(staged)")
        let name: String = try XCTUnwrap(staged.first)
        let stagedURL: URL = root.appendingPathComponent(name)
        XCTAssertTrue(UndoSwap.removeALink(at: stagedURL))
        try FileManager.default.createSymbolicLink(atPath: stagedURL.path, withDestinationPath: "Unit 1, Day 1.md")

        let survivor: UndoJournal = UndoJournal(folderURL: journalFolder)
        await UndoRecovery.recoverAndRederive(survivor, resolveRoot: { _ in root }, places: places)
        XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: root), laid.oldText)
        XCTAssertEqual(linkText(section + "Unit 1, Day 4 (kept by Undo).md", root: root), "Unit 1, Day 1.md", "a staged link holding another text was removed")
        XCTAssertFalse(UndoSwap.isALink(root.appendingPathComponent(name)), "left under the hidden name")
        let phase: UndoStepPhase? = try survivor.read().records[1]?.phase
        XCTAssertNotEqual(phase, .begun)
    }

    /// A write, a new file or a removal planned at the link's one place
    /// BEFORE the relink is planned refuses the step before anything
    /// changes, as one planned after it does: the result never depends on
    /// the order the caller plans in (review 1, LOW 3).
    func testAWritePlannedAtTheOnePlaceBeforeTheRelinkRefusesTheStep() throws {
        for planned in ["write", "writeNew", "remove"] {
            let laid: LaidRelink = try layARelinkWhereItStands(named: "write-first-\(planned)", leads: .inside)
            UndoJournalLocation.folderOverride = parent.appendingPathComponent("list-write-first-\(planned)", isDirectory: true)
            JournaledStep.modeOverride = .live
            let link: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
            let before: [String: String] = try folderNow(laid.root)
            let step: JournaledStep = stepWhereItStands(laid.root)
            switch planned {
            case "write":
                step.write("Written.\n", to: link)
            case "writeNew":
                step.writeNew(Data("Written.\n".utf8), to: link)
            default:
                step.remove(link)
            }
            step.relinkLink(link, to: link, textAfter: Data(laid.newText.utf8))
            XCTAssertThrowsError(try step.make(), planned) { error in
                guard case JournaledStepError.refused(.cannotTellNow, _) = error else {
                    XCTFail("\(planned): refused with \(error), not cannotTellNow")
                    return
                }
            }
            XCTAssertEqual(try folderNow(laid.root), before, planned)
            XCTAssertEqual(try UndoJournalLocation.standardJournal().read().records.count, 0, planned)
            JournaledStep.modeOverride = nil
            UndoJournalLocation.folderOverride = nil
        }
    }

    /// The place changed under the swap (the teacher's own file put there
    /// between the staging and the exchange): the teacher's file is put
    /// back at the place, never left under the hidden staged name, the
    /// swap's own link is removed, and the refusal is changed since. Also
    /// when the exchange back is refused: the swap's own link is taken out
    /// and the teacher's file renamed back. MUST FAIL with the teacher's
    /// item left under the staged name (review 1, LOW 4).
    func testThePlaceChangedUnderTheSwapIsGivenBackEvenWhenTheExchangeBackFails() throws {
        for backFails in [false, true] {
            let laid: LaidRelink = try layARelinkWhereItStands(named: "changed-under-\(backFails)", leads: .inside)
            let place: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
            let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
            UndoKillPoints.hook = { reached in
                if reached == .relinkStaged(0) {
                    _ = UndoSwap.removeALink(at: place)
                    try? Data("The teacher's own.\n".utf8).write(to: place)
                }
                return false
            }
            if backFails {
                UndoKillPoints.relinkExchangeBackFails = { _ in
                    return true
                }
            }
            let result: UndoSwapResult = UndoSwap.swap(forward, label: "1-apply", root: laid.root)
            UndoKillPoints.hook = nil
            UndoKillPoints.relinkExchangeBackFails = nil
            XCTAssertEqual(result, .refused(.changedSince(firstPath: section + "Unit 1, Day 4.md", others: 0)), "\(backFails)")
            XCTAssertFalse(UndoSwap.isALink(place), "\(backFails)")
            XCTAssertEqual(try text(section + "Unit 1, Day 4.md", root: laid.root), "The teacher's own.\n", "\(backFails)")
            XCTAssertEqual(stagedLeft(under: laid.root), [], "\(backFails)")
        }
    }

    /// A second kill DURING recovery of a same-place relink: a step that
    /// re-points Day 4's link and then moves Day 8's page dies before the
    /// page's swap; recovery, putting the link's old text back, dies inside
    /// that put-back swap (the new link staged, or just after the exchange)
    /// or after its tidy; a third process's recovery settles it whole: the
    /// old text at Day 4, Day 8's page where it was, nothing staged.
    func testASecondKillDuringRecoveryOfARelinkWhereItStandsLosesNothing() async throws {
        var reachedInsideTheSwap: Int = 0
        for second in [UndoKillPoint.relinkStaged(0), UndoKillPoint.relinkSwapped(0), UndoKillPoint.afterRecoveryTidied] {
            let laid: LaidRelink = try layARelinkWhereItStands(named: "second-kill-\(second)", leads: .inside)
            let root: URL = laid.root
            try UndoContractReplay.write("Eight.\n", to: section + "Unit 1, Day 8.md", in: root)
            let ops: [UndoOp] = [
                laid.op,
                UndoOp.moveFile(from: section + "Unit 1, Day 8.md", to: section + "Unit 1, Day 9.md", sha: UndoHash.sha256(of: Data("Eight.\n".utf8))),
            ]
            let journalFolder: URL = root.deletingLastPathComponent().appendingPathComponent("undo", isDirectory: true)
            let draft: UndoOpsDraft = UndoContractKinds.draft(
                ops: ops, blobs: [Data(laid.oldText.utf8), Data(laid.newText.utf8)], root: root, action: "insertClass"
            )
            let places: UndoMemoryPlaces = UndoMemoryPlaces()
            let dying: UndoJournal = UndoJournal(
                folderURL: journalFolder,
                process: UndoContractReplay.goneProcess,
                processIsAlive: { process in process.pid != 2_000_000_001 }
            )
            UndoKillPoints.hook = { reached in
                return reached == .beforeSwap(1)
            }
            _ = JournaledWrite.perform(ops: draft, in: dying, mode: .live, places: places)
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: root), laid.newText, "\(second)")

            var reachedIt: Bool = false
            UndoKillPoints.hook = { reached in
                if reached == second {
                    reachedIt = true
                    return true
                }
                return false
            }
            let recovering: UndoJournal = UndoJournal(
                folderURL: journalFolder,
                process: UndoContractReplay.goneProcess,
                processIsAlive: { process in process.pid != 2_000_000_001 }
            )
            await UndoRecovery.recoverAndRederive(recovering, resolveRoot: { _ in root }, places: places)
            UndoKillPoints.hook = nil
            if reachedIt && second != .afterRecoveryTidied {
                reachedInsideTheSwap += 1
            }
            if second == .afterRecoveryTidied {
                XCTAssertTrue(reachedIt, "\(second)")
            }

            let survivor: UndoJournal = UndoJournal(folderURL: journalFolder)
            await UndoRecovery.recoverAndRederive(survivor, resolveRoot: { _ in root }, places: places)
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: root), laid.oldText, "\(second)")
            XCTAssertEqual(try text(section + "Unit 1, Day 8.md", root: root), "Eight.\n", "\(second)")
            XCTAssertFalse(standsAnything(section + "Unit 1, Day 9.md", root: root), "\(second)")
            XCTAssertEqual(stagedLeft(under: root), [], "\(second)")
            let phase: UndoStepPhase? = try survivor.read().records[1]?.phase
            XCTAssertNotEqual(phase, .begun, "\(second)")
            XCTAssertNotEqual(phase, .interrupted, "\(second)")
        }
        XCTAssertGreaterThanOrEqual(reachedInsideTheSwap, 1)
    }

    // MARK: - Where the link stands: fix round two (mac-1)

    /// Review 2, MEDIUM case (a): another program replaces the link at the
    /// place with the teacher's own file (or folder) between the staging
    /// and the exchange, and the process is killed just after the exchange
    /// (`relinkSwapped`): the teacher's item is under the staged name, the
    /// swap's new link at the place. Recovery never removes the teacher's
    /// item for its name: the place holds a link of the step's, so it is
    /// kept under a visible name beside the place (said on the trail), the
    /// link stays, nothing staged is left. MUST FAIL with the item deleted
    /// by the tidy.
    func testAKillAfterTheExchangeOnceThePlaceChangedGivesTheTeachersItemBack() async throws {
        for kind in ["file", "folder"] {
            let laid: LaidRelink = try layARelinkWhereItStands(named: "replaced-\(kind)", leads: .inside)
            let root: URL = laid.root
            let place: URL = root.appendingPathComponent(section + "Unit 1, Day 4.md")
            let journalFolder: URL = root.deletingLastPathComponent().appendingPathComponent("undo", isDirectory: true)
            let draft: UndoOpsDraft = UndoContractKinds.draft(
                ops: [laid.op], blobs: [Data(laid.oldText.utf8), Data(laid.newText.utf8)], root: root, action: "insertClass"
            )
            let places: UndoMemoryPlaces = UndoMemoryPlaces()
            let dying: UndoJournal = UndoJournal(
                folderURL: journalFolder,
                process: UndoContractReplay.goneProcess,
                processIsAlive: { process in process.pid != 2_000_000_001 }
            )
            UndoKillPoints.hook = { reached in
                if reached == .relinkStaged(0) {
                    _ = UndoSwap.removeALink(at: place)
                    if kind == "file" {
                        try? Data("The teacher's own.\n".utf8).write(to: place)
                    } else {
                        try? FileManager.default.createDirectory(at: place, withIntermediateDirectories: false)
                        try? Data("Inside.\n".utf8).write(to: place.appendingPathComponent("inside.md"))
                    }
                }
                return reached == .relinkSwapped(0)
            }
            _ = JournaledWrite.perform(ops: draft, in: dying, mode: .live, places: places)
            UndoKillPoints.hook = nil
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: root), laid.newText, kind)
            XCTAssertFalse(stagedLeft(under: root).isEmpty, kind)

            let survivor: UndoJournal = UndoJournal(folderURL: journalFolder)
            await UndoRecovery.recoverAndRederive(survivor, resolveRoot: { _ in root }, places: places)
            XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: root), laid.newText, kind)
            if kind == "file" {
                XCTAssertEqual(try? text(section + "Unit 1, Day 4 (kept by Undo).md", root: root), "The teacher's own.\n", kind)
            } else {
                XCTAssertEqual(try? text(section + "Unit 1, Day 4.md (kept by Undo)/inside.md", root: root), "Inside.\n", kind)
            }
            XCTAssertEqual(stagedLeft(under: root), [], kind)
        }
    }

    /// Review 2, MEDIUM case (b): the place is written twice by another
    /// program inside one live swap: the teacher's X replaces the link
    /// before the exchange, and the newest save X2 replaces the swap's own
    /// link after it. The newest save ends at the place, the older one is
    /// kept under a visible name beside it, nothing is under a hidden name,
    /// and the swap is refused changed since. MUST FAIL with X2 under the
    /// staged name.
    func testASecondWriteAtThePlaceInsideTheSwapLeavesTheNewestSaveAtThePlace() throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "written-twice", leads: .inside)
        let place: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
        let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
        UndoKillPoints.hook = { reached in
            if reached == .relinkStaged(0) {
                _ = UndoSwap.removeALink(at: place)
                try? Data("First save.\n".utf8).write(to: place)
            }
            if reached == .relinkSwapped(0) {
                let saved: URL = place.deletingLastPathComponent().appendingPathComponent("saving.tmp")
                try? Data("Newest save.\n".utf8).write(to: saved)
                _ = rename(saved.path, place.path)
            }
            return false
        }
        let said: [String] = try withTheKeptPageLine {
            let result: UndoSwapResult = UndoSwap.swap(
                forward, label: "1-apply", root: laid.root,
                tellingKept: UndoRecovery.tellingWhatIsKept(course: "TST1O", section: 1, root: laid.root)
            )
            UndoKillPoints.hook = nil
            XCTAssertEqual(result, .refused(.changedSince(firstPath: section + "Unit 1, Day 4.md", others: 0)))
        }
        XCTAssertEqual(try? text(section + "Unit 1, Day 4.md", root: laid.root), "Newest save.\n")
        XCTAssertEqual(try? text(section + "Unit 1, Day 4 (kept by Undo).md", root: laid.root), "First save.\n")
        XCTAssertEqual(stagedLeft(under: laid.root), [])
        // Review 3 of mac-1, LOW 1: the keep is said on the trail first, live
        // as in recovery. MUST FAIL with the live swap's keeps unsaid (F-K).
        XCTAssertEqual(said, [section + "Unit 1, Day 4.md -> " + section + "Unit 1, Day 4 (kept by Undo).md"])
    }

    /// Runs `body` with the kept-item trail line caught (mac-2: "undo kept
    /// an item found where a link was being changed"): each line said as
    /// `<place> -> <kept as>`, in order. The kept-page and kept-folder
    /// lines are caught too, each said as `untrue: …`, as nothing of the
    /// change removed, moved or set the item aside (the day27b-2 sweep,
    /// finding 1). MUST FAIL with a relink's keep said on either.
    func withTheKeptPageLine(_ body: () throws -> Void) throws -> [String] {
        var said: [String] = []
        let itemBefore = UndoTrailHook.keptAnItemFoundWhereALinkWasChangedLine
        let pageBefore = UndoTrailHook.keptAPageLine
        let folderBefore = UndoTrailHook.foundAFolderSetAsideLine
        UndoTrailHook.keptAnItemFoundWhereALinkWasChangedLine = { _, _, place, keptAs in
            said.append(place + " -> " + keptAs)
        }
        UndoTrailHook.keptAPageLine = { _, _, place, keptAs in
            said.append("untrue: " + place + " -> " + keptAs)
        }
        UndoTrailHook.foundAFolderSetAsideLine = { _, _, place, _, keptAs, _ in
            said.append("untrue: " + place + " -> " + (keptAs ?? ""))
        }
        defer {
            UndoTrailHook.keptAnItemFoundWhereALinkWasChangedLine = itemBefore
            UndoTrailHook.keptAPageLine = pageBefore
            UndoTrailHook.foundAFolderSetAsideLine = folderBefore
        }
        try body()
        return said
    }

    /// Review 3 of mac-1, LOW 2: the place changed under the swap, the
    /// exchange back refused, and another program fills the place in the
    /// instant before the teacher's item is renamed back: the item is never
    /// left under the hidden name, unsaid; it is kept under a visible name
    /// beside the place and said first, the other program's save standing
    /// at the place. MUST FAIL with a refused rename back left as it is
    /// (F-L).
    func testARenameBackRefusedKeepsTheTeachersItemVisibleAndSaid() throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "rename-back-refused", leads: .inside)
        let place: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
        let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
        UndoKillPoints.hook = { reached in
            if reached == .relinkStaged(0) {
                _ = UndoSwap.removeALink(at: place)
                try? Data("The teacher's own.\n".utf8).write(to: place)
            }
            return false
        }
        UndoKillPoints.relinkExchangeBackFails = { _ in
            return true
        }
        UndoKillPoints.beforeARenameBack = { url in
            try? Data("Another program.\n".utf8).write(to: url)
        }
        let said: [String] = try withTheKeptPageLine {
            let result: UndoSwapResult = UndoSwap.swap(
                forward, label: "1-apply", root: laid.root,
                tellingKept: UndoRecovery.tellingWhatIsKept(course: "TST1O", section: 1, root: laid.root)
            )
            XCTAssertEqual(result, .refused(.changedSince(firstPath: section + "Unit 1, Day 4.md", others: 0)))
        }
        UndoKillPoints.hook = nil
        UndoKillPoints.relinkExchangeBackFails = nil
        UndoKillPoints.beforeARenameBack = nil
        XCTAssertEqual(try? text(section + "Unit 1, Day 4.md", root: laid.root), "Another program.\n")
        XCTAssertEqual(try? text(section + "Unit 1, Day 4 (kept by Undo).md", root: laid.root), "The teacher's own.\n")
        XCTAssertEqual(stagedLeft(under: laid.root), [])
        XCTAssertEqual(said, [section + "Unit 1, Day 4.md -> " + section + "Unit 1, Day 4 (kept by Undo).md"])
    }

    /// Review 3 of mac-1, LOW 3, as review 2 of mac-2 (MEDIUM) settles it:
    /// an item under the staged name that is not a link is the teacher's
    /// WITHOUT being read (the step stages only links), so one that cannot
    /// be read just now (a folder no one may list) is never left hidden and
    /// never refuses the relink: it is kept under a visible name beside the
    /// place, said first, and the relink is made. MUST FAIL with a non-link
    /// read before it is judged (F-N).
    func testAnUnreadableItemUnderTheStagedNameIsKeptVisibleAndSaid() throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "unreadable-staged", leads: .inside)
        let place: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
        let stagedURL: URL = UndoSwap.besideURL(for: place, label: "1-apply", role: "new")
        let folder: URL = stagedURL.appendingPathComponent("inside", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: stagedURL.path)
        let keptPath: String = section + "Unit 1, Day 4.md (kept by Undo)"
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedURL.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: laid.root.appendingPathComponent(keptPath).path)
        }
        XCTAssertEqual(UndoTreeReading.read(at: stagedURL), .cannotRead, "the item is not unreadable here")
        let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
        let said: [String] = try withTheKeptPageLine {
            let result: UndoSwapResult = UndoSwap.swap(
                forward, label: "1-apply", root: laid.root,
                tellingKept: UndoRecovery.tellingWhatIsKept(course: "TST1O", section: 1, root: laid.root)
            )
            XCTAssertEqual(result, .swapped)
        }
        XCTAssertEqual(linkText(section + "Unit 1, Day 4.md", root: laid.root), laid.newText, "the relink made")
        XCTAssertTrue(UndoSwap.isAFolder(laid.root.appendingPathComponent(keptPath)), "the teacher's folder kept visible")
        XCTAssertFalse(standsAnything(section + ".Unit 1, Day 4.md.plantoir-undo-1-apply-new", root: laid.root), "nothing hidden")
        XCTAssertEqual(said, [section + "Unit 1, Day 4.md -> " + keptPath])
    }

    /// A step for the course the laid folder holds.
    func stepWhereItStands(_ root: URL) -> JournaledStep {
        return JournaledStep(
            courseCode: "TST1O", courseDirectory: root.appendingPathComponent("courses/TST1O", isDirectory: true),
            section: 1, maker: UndoStepMaker.sheet("insertClass")
        )
    }

    /// Every page in section 1 but the link itself, by name: what nothing
    /// may write through the link. The files outside are never opened here
    /// (their access times are `outsideNow`'s), only by
    /// `checkTheOutsideBytes` at the end.
    func pagesBesideTheLink(_ root: URL) throws -> [String: String] {
        var found: [String: String] = [:]
        for (name, held) in try classPagesNow(root) where name != "Unit 1, Day 4.md" {
            found[name] = held
        }
        return found
    }

    // MARK: - The lows riding with mac-2

    /// The day27b-2 sweep, finding 1: the line said when an item that was
    /// not Plantoir's is kept where a link was being changed is the
    /// contract's own (`activityTrail.mustRecord`, "undo kept an item found
    /// where a link was being changed"), and says nothing of a change that
    /// stopped or of anything removed, moved or set aside.
    func testTheKeptItemLineIsTheContractsAndTrueOnTheLivePath() throws {
        let rules: [String: Any] = try UndoContractReplay.contract("shared-rules.json")
        let trail: [String: Any] = rules["activityTrail"] as? [String: Any] ?? [:]
        var example: String? = nil
        for row in trail["mustRecord"] as? [[String: Any]] ?? [] {
            if row["event"] as? String == ActivityTrail.Event.undoKeptAnItemFoundWhereALinkWasChanged.rawValue {
                example = row["line"] as? String
            }
        }
        let line: String = UndoTrail.keptAnItemFoundWhereALinkWasChangedLine(
            course: "ICS3U", section: 1,
            place: "courses/ICS3U/section1/Unit 1, Day 4.md",
            keptAs: "courses/ICS3U/section1/Unit 1, Day 4 (kept by Undo).md"
        )
        XCTAssertEqual(line, example)
        for untrue in ["stopped", "removed", "moved away", "set aside", "staged", "exchange", "journal"] {
            XCTAssertFalse(line.contains(untrue), "\(untrue): \(line)")
        }
    }

    /// The day27b-2 sweep, point 3: a volume that refuses the exchange is
    /// refused `couldNotWrite`, and the reason said for it is true: never
    /// "the disk may be full" alone, as the disk is not full. MUST FAIL
    /// with the old clause ("nothing could be written beside … (the disk
    /// may be full)").
    func testAVolumeThatRefusesTheExchangeIsSaidTruly() throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "refused-exchange-said", leads: .inside)
        let place: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
        let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
        UndoKillPoints.relinkRenameInFails = { url in
            return url.standardizedFileURL.path == place.standardizedFileURL.path
        }
        let result: UndoSwapResult = UndoSwap.swap(forward, label: "1-apply", root: laid.root)
        UndoKillPoints.relinkRenameInFails = nil
        guard case .refused(let refusal) = result else {
            return XCTFail("not refused: \(result)")
        }
        let line: String = UndoTrail.leftNewestLine(course: "ICS3U", section: 1, isUndo: true, refusal: refusal)
        XCTAssertTrue(
            line.contains("because " + section + "Unit 1, Day 4.md could not be changed in its folder, which may be full or may not allow the change."),
            line
        )
        XCTAssertFalse(line.contains("nothing could be written beside"), line)
        XCTAssertFalse(line.contains("(the disk may be full)"), line)
    }

    /// Review 3 of mac-1, LOW 5: a teacher's file under the TWO-place
    /// relink's own staged name (`-new` beside `to`). The pre-clean follows
    /// the one rule: the file is kept under a visible name beside `to`, said
    /// first, and the relink is made; never left hidden with an untrue "in
    /// use". MUST FAIL with the pre-clean's result ignored.
    func testATeachersFileUnderTheTwoPlaceRelinksStagedNameIsKeptVisibleAndSaid() throws {
        let laid: LaidRelink = try layARelink(named: "two-place-pre-clean", leads: .inside)
        let to: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 5.md")
        let stagedURL: URL = UndoSwap.besideURL(for: to, label: "1-apply", role: "new")
        try Data("The teacher's own.\n".utf8).write(to: stagedURL)
        let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
        let said: [String] = try withTheKeptPageLine {
            let result: UndoSwapResult = UndoSwap.swap(
                forward, label: "1-apply", root: laid.root,
                tellingKept: UndoRecovery.tellingWhatIsKept(course: "TST1O", section: 1, root: laid.root)
            )
            XCTAssertEqual(result, .swapped)
        }
        XCTAssertEqual(linkText(section + "Unit 1, Day 5.md", root: laid.root), laid.newText, "the relink made")
        XCTAssertFalse(standsAnything(section + "Unit 1, Day 4.md", root: laid.root))
        XCTAssertEqual(try? text(section + "Unit 1, Day 5 (kept by Undo).md", root: laid.root), "The teacher's own.\n")
        XCTAssertEqual(stagedLeft(under: laid.root), [])
        XCTAssertEqual(said, [section + "Unit 1, Day 5.md -> " + section + "Unit 1, Day 5 (kept by Undo).md"])
    }

    /// Review 4 of mac-1, LOW: the place changed under the swap to an item
    /// that cannot be read (a folder no one may list). After the exchange
    /// it is not ours whatever it holds, so it is exchanged back unread:
    /// it stands at its place again, nothing is left under the staged name,
    /// refused changed since. MUST FAIL with the item left hidden and the
    /// refusal naming only the place.
    func testAnUnreadableItemFoundAtThePlaceAfterTheExchangeIsGivenBack() throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "unreadable-after", leads: .inside)
        let place: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: place.path)
            let stagedURL: URL = UndoSwap.besideURL(for: place, label: "1-apply", role: "new")
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedURL.path)
        }
        let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
        UndoKillPoints.hook = { reached in
            if reached == .relinkStaged(0) {
                _ = UndoSwap.removeALink(at: place)
                try? FileManager.default.createDirectory(at: place.appendingPathComponent("inside"), withIntermediateDirectories: true)
                try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: place.path)
            }
            return false
        }
        let result: UndoSwapResult = UndoSwap.swap(forward, label: "1-apply", root: laid.root)
        UndoKillPoints.hook = nil
        XCTAssertEqual(result, .refused(.changedSince(firstPath: section + "Unit 1, Day 4.md", others: 0)))
        XCTAssertTrue(UndoSwap.isAFolder(place), "the other program's folder at its place")
        XCTAssertEqual(stagedLeft(under: laid.root), [])
    }

    /// The same with the exchange back refused too. The item is the
    /// teacher's without being read (it is not a link), so it is given
    /// back by the one rule: the swap's own link is taken out of the place
    /// by its text and the item renamed back, refused changed since, and
    /// nothing is left under the hidden name (review 2 of mac-2, MEDIUM).
    /// MUST FAIL with a non-link read before it is judged (F-N).
    func testAnItemThatCannotGoBackByTheExchangeIsGivenBackUnread() throws {
        try checkAnItemThatCannotGoBack(live: false)
        try checkAnItemThatCannotGoBack(live: true)
    }

    func checkAnItemThatCannotGoBack(live: Bool) throws {
        let laid: LaidRelink = try layARelinkWhereItStands(named: "unreadable-stays-\(live)", leads: .inside)
        let place: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 4.md")
        let stagedURL: URL = UndoSwap.besideURL(for: place, label: "1-apply", role: "new")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: place.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedURL.path)
        }
        let forward: [UndoSwapTarget] = try readyTargets(UndoCheck.plan([laid.op], direction: .forward, root: laid.root, journal: laid.journal))
        UndoKillPoints.hook = { reached in
            if reached == .relinkStaged(0) {
                _ = UndoSwap.removeALink(at: place)
                try? FileManager.default.createDirectory(at: place.appendingPathComponent("inside"), withIntermediateDirectories: true)
                try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: place.path)
            }
            return false
        }
        UndoKillPoints.relinkExchangeBackFails = { _ in
            return true
        }
        let visiblePlace: String = section + "Unit 1, Day 4.md"
        if live {
            let blobs: [Data] = [Data(laid.oldText.utf8), Data(laid.newText.utf8)]
            let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [laid.op], blobs: blobs, root: laid.root, action: "insertClass")
            let outcome: JournaledWriteOutcome = JournaledWrite.perform(ops: draft, in: laid.journal, mode: .live, places: UndoMemoryPlaces())
            UndoKillPoints.hook = nil
            UndoKillPoints.relinkExchangeBackFails = nil
            XCTAssertEqual(outcome, .refused(.changedSince(firstPath: visiblePlace, others: 0)), "live")
        } else {
            let result: UndoSwapResult = UndoSwap.swap(forward, label: "1-apply", root: laid.root)
            UndoKillPoints.hook = nil
            UndoKillPoints.relinkExchangeBackFails = nil
            XCTAssertEqual(result, .refused(.changedSince(firstPath: visiblePlace, others: 0)))
        }
        XCTAssertTrue(UndoSwap.isAFolder(place), "the teacher's folder at its place: \(live)")
        XCTAssertFalse(standsAnything(section + ".Unit 1, Day 4.md.plantoir-undo-1-apply-new", root: laid.root), "nothing hidden: \(live)")
    }

    /// Review 2 of mac-2, MEDIUM: a kill just after the exchange, once the
    /// place had been replaced by a teacher's item no one may read (a
    /// folder no one may list; a file no one may read). Recovery's tidy
    /// judges the item under the relink's staged name by `lstat` alone: it
    /// is not a link, so it is the teacher's, and it is kept under a
    /// visible name beside the place (which holds the step's link) and
    /// said; nothing waits under the hidden name for a later try. MUST
    /// FAIL with a non-link read before it is judged (F-N).
    func testRecoverySettlesAnUnreadableItemUnderTheStagedNameVisiblyAndSaysSo() async throws {
        var faults: [String] = []
        for kind in ["folder", "file"] {
            let laid: LaidRelink = try layARelinkWhereItStands(named: "unreadable-recovered-\(kind)", leads: .inside)
            let root: URL = laid.root
            let place: URL = root.appendingPathComponent(section + "Unit 1, Day 4.md")
            let stagedURL: URL = UndoSwap.besideURL(for: place, label: "1-apply", role: "new")
            var keptPath: String = section + "Unit 1, Day 4 (kept by Undo).md"
            if kind == "folder" {
                keptPath = section + "Unit 1, Day 4.md (kept by Undo)"
            }
            let keptURL: URL = root.appendingPathComponent(keptPath)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedURL.path)
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: keptURL.path)
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: place.path)
            }
            let journalFolder: URL = root.deletingLastPathComponent().appendingPathComponent("undo", isDirectory: true)
            let draft: UndoOpsDraft = UndoContractKinds.draft(
                ops: [laid.op], blobs: [Data(laid.oldText.utf8), Data(laid.newText.utf8)], root: root, action: "insertClass"
            )
            let places: UndoMemoryPlaces = UndoMemoryPlaces()
            let dying: UndoJournal = UndoJournal(
                folderURL: journalFolder,
                process: UndoContractReplay.goneProcess,
                processIsAlive: { process in process.pid != 2_000_000_001 }
            )
            UndoKillPoints.hook = { reached in
                if reached == .relinkStaged(0) {
                    _ = UndoSwap.removeALink(at: place)
                    if kind == "file" {
                        try? Data("The teacher's own.\n".utf8).write(to: place)
                    } else {
                        try? FileManager.default.createDirectory(at: place.appendingPathComponent("inside"), withIntermediateDirectories: true)
                    }
                    try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: place.path)
                }
                return reached == .relinkSwapped(0)
            }
            _ = JournaledWrite.perform(ops: draft, in: dying, mode: .live, places: places)
            UndoKillPoints.hook = nil
            if kind == "folder" && UndoTreeReading.read(at: stagedURL) != .cannotRead {
                faults.append("\(kind): the folder under the staged name can be listed here")
            }
            if kind == "file" && (!standsAnything(section + ".Unit 1, Day 4.md.plantoir-undo-1-apply-new", root: root)
                || FileManager.default.isReadableFile(atPath: stagedURL.path)) {
                faults.append("\(kind): no unreadable file under the staged name here")
            }
            var said: [String] = []
            let itemBefore = UndoTrailHook.keptAnItemFoundWhereALinkWasChangedLine
            UndoTrailHook.keptAnItemFoundWhereALinkWasChangedLine = { _, _, placeSaid, keptAs in
                said.append(placeSaid + " -> " + keptAs)
            }
            let survivor: UndoJournal = UndoJournal(folderURL: journalFolder)
            await UndoRecovery.recoverAndRederive(survivor, resolveRoot: { _ in root }, places: places)
            UndoTrailHook.keptAnItemFoundWhereALinkWasChangedLine = itemBefore
            if linkText(section + "Unit 1, Day 4.md", root: root) != laid.newText {
                faults.append("\(kind): the step's link is not at the place")
            }
            if standsAnything(section + ".Unit 1, Day 4.md.plantoir-undo-1-apply-new", root: root) {
                faults.append("\(kind): left under the hidden name")
            }
            if !standsAnything(keptPath, root: root) {
                faults.append("\(kind): not kept under \(keptPath)")
            }
            if said != [section + "Unit 1, Day 4.md -> " + keptPath] {
                faults.append("\(kind): said \(said)")
            }
        }
        let failing: [String] = faults
        await MainActor.run {
            XCTAssertEqual(failing, [])
        }
    }

    /// The director's shape from Windows' kill table: a teacher's own page
    /// under a TWO-place relink's own staged name beside Day 5, a place
    /// only link moves name (Day 5's link moves on to Day 6 and Day 4's is
    /// relinked into Day 5). Made live, and killed before each swap and
    /// recovered: the page is never deleted; it is kept under a visible
    /// name and said (or given back), and nothing is left staged.
    func testATeachersPageUnderAChainedRelinksStagedNameIsNeverDeleted() async throws {
        let teachers: String = "The teacher's own page.\n"
        var points: [UndoKillPoint?] = [nil]
        for index in 0..<2 {
            points.append(.beforeSwap(index))
        }
        var faults: [String] = []
        for point in points {
            var label: String = "live"
            if let point {
                label = "\(point)"
            }
            let laid: LaidChain = try layAChain(.twoChainedRelinks, named: "teachers-page-" + label)
            let dayFive: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 5.md")
            try Data(teachers.utf8).write(to: UndoSwap.besideURL(for: dayFive, label: "1-apply", role: "new"))
            let journal: UndoJournal = UndoJournal(
                folderURL: laid.journalFolder,
                process: UndoContractReplay.goneProcess,
                processIsAlive: { process in process.pid != 2_000_000_001 }
            )
            var said: [String] = []
            let hookBefore = UndoTrailHook.keptAnItemFoundWhereALinkWasChangedLine
            UndoTrailHook.keptAnItemFoundWhereALinkWasChangedLine = { _, _, place, keptAs in
                said.append(place + " -> " + keptAs)
            }
            if let point {
                UndoKillPoints.hook = { reached in
                    return reached == point
                }
            }
            let outcome: JournaledWriteOutcome = JournaledWrite.perform(ops: laid.draft, in: journal, mode: .live, places: UndoMemoryPlaces())
            UndoKillPoints.hook = nil
            if point == nil && outcome != .applied(seq: 1) {
                faults.append("\(label): \(outcome)")
            }
            if point != nil {
                let root: URL = laid.root
                await UndoRecovery.recoverAndRederive(
                    UndoJournal(folderURL: laid.journalFolder), resolveRoot: { _ in root }, places: UndoMemoryPlaces()
                )
            }
            UndoTrailHook.keptAnItemFoundWhereALinkWasChangedLine = hookBefore
            var visibleHolders: [String] = []
            let asFound: String = "file " + Data(teachers.utf8).base64EncodedString()
            for (name, held) in try classPagesNow(laid.root) where held == asFound && !name.hasPrefix(".") {
                visibleHolders.append(name)
            }
            if visibleHolders.isEmpty {
                faults.append("\(label): the teacher's page is gone")
            }
            if !stagedLeft(under: laid.root).isEmpty {
                faults.append("\(label): staged \(stagedLeft(under: laid.root))")
            }
            var keptOnes: Int = 0
            for name in visibleHolders where name.contains("(kept by Undo)") {
                keptOnes += 1
            }
            if keptOnes != said.count {
                faults.append("\(label): kept \(visibleHolders), said \(said)")
            }
        }
        let failing: [String] = faults
        await MainActor.run {
            XCTAssertEqual(failing, [])
        }
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

    /// Every name under the root kept visible by Undo (`(kept by Undo`).
    func keptLeft(under root: URL) -> [String] {
        var found: [String] = []
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            return found
        }
        while let name = walker.nextObject() as? String {
            if name.contains("(kept by Undo") {
                found.append(name)
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
