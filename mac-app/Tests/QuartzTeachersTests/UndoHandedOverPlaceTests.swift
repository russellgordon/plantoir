import XCTest
@testable import QuartzTeachers

/// U4b3 of #899, the door pieces: a HANDED-OVER place, one an earlier op of
/// a step leaves (a move away, a removal) and a later op fills (a move in,
/// a new file), at least one a file's or a link's move. Insert Class makes
/// such steps when a later class is a symbolic link (U4b3 part 2): the link
/// moves up a day and the class below it, or the new class, fills its
/// place. No step readable today holds one (`UndoStep.wholeOpsStandAlone`),
/// so the check is called directly here.
final class UndoHandedOverPlaceTests: XCTestCase {

    // MARK: - Stored properties

    var parent: URL = FileManager.default.temporaryDirectory

    var outside: URL = FileManager.default.temporaryDirectory

    let section: String = "courses/TST1O/section1/"

    // MARK: - Setting up

    override func setUpWithError() throws {
        let name: String = "handed-over-" + UUID().uuidString
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        outside = FileManager.default.temporaryDirectory.appendingPathComponent(name + "-outside", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        UndoKillPoints.fileInUseAtSwap = nil
        UndoKillPoints.hook = nil
        try? FileManager.default.removeItem(at: parent)
        try? FileManager.default.removeItem(at: outside)
    }

    // MARK: - Going forward (door-1)

    func testShapeAAfterALinksMoveIsPlannedAndSwapped() throws {
        try checkShapeA(leadingOut: false)
    }

    func testShapeAWithTheLinkLeadingOutIsPlannedAndSwapped() throws {
        try checkShapeA(leadingOut: true)
    }

    func testShapeBBeforeALinksMoveIsPlannedAndSwapped() throws {
        try checkShapeB(leadingOut: false)
    }

    func testShapeBWithTheLinkLeadingOutIsPlannedAndSwapped() throws {
        try checkShapeB(leadingOut: true)
    }

    func testShapeCTwoLinksInARowArePlannedAndSwapped() throws {
        try checkShapeC(leadingOut: false)
    }

    func testShapeCWithTheLinksLeadingOutArePlannedAndSwapped() throws {
        try checkShapeC(leadingOut: true)
    }

    /// Shape A, and a plain file put at Day 3 once the link has left it,
    /// before the new page goes in: the swap's own last look refuses it,
    /// naming Day 3, and the file put there is left whole, never replaced.
    func testAPlaceFilledSinceTheLinkLeftIsRefused() throws {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "filled")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let target: String = try layLibraryPage("Day 3.md", text: "Linked.\n", root: root)
        try layLink(section + "Unit 1, Day 3.md", leadingTo: target, root: root)
        let ops: [UndoOp] = [
            UndoOp.moveLink(from: section + "Unit 1, Day 3.md", to: section + "Unit 1, Day 4.md", linkSha: try linkSha(section + "Unit 1, Day 3.md", root: root)),
            UndoOp.writeFile(path: section + "Unit 1, Day 3.md", beforeSha: nil, afterSha: try store("New.\n", in: journal)),
        ]
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .forward, root: root, journal: journal))
        let intruder: URL = root.appendingPathComponent(section + "Unit 1, Day 3.md")
        UndoKillPoints.fileInUseAtSwap = { index in
            if index == 1 {
                try? Data("Someone else's.\n".utf8).write(to: intruder)
            }
            return false
        }
        let result: UndoSwapResult = UndoSwap.swap(targets, label: "1-apply", root: root)
        UndoKillPoints.fileInUseAtSwap = nil
        // The link cannot go back over the file put at its place: left
        // where it is for recovery, nothing lost (door-3 settles it).
        XCTAssertEqual(result, .notPutBack(.changedSince(firstPath: section + "Unit 1, Day 3.md", others: 0), keptOriginals: []))
        XCTAssertEqual(try String(contentsOf: intruder, encoding: .utf8), "Someone else's.\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent(section + "Unit 1, Day 4.md").path), "../library/Day 3.md")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("courses/TST1O/library/Day 3.md"), encoding: .utf8), "Linked.\n")
        // Left as it stands for recovery, as every `notPutBack` is: the new
        // page's staged file beside Day 3, in its own folder.
        XCTAssertEqual(stagedLeft(under: root), [section + ".Unit 1, Day 3.md" + UndoSwap.stagedMarker + "1-apply-new"])
    }

    /// Shape A, and the link replaced by a plain file between the plan and
    /// the swap: the link's move finds Day 3 changed, refused naming it, and
    /// nothing is changed.
    func testALinkReplacedBeforeTheSwapIsRefusedAndNothingChanges() throws {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "replaced")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let target: String = try layLibraryPage("Day 3.md", text: "Linked.\n", root: root)
        try layLink(section + "Unit 1, Day 3.md", leadingTo: target, root: root)
        let ops: [UndoOp] = [
            UndoOp.moveLink(from: section + "Unit 1, Day 3.md", to: section + "Unit 1, Day 4.md", linkSha: try linkSha(section + "Unit 1, Day 3.md", root: root)),
            UndoOp.writeFile(path: section + "Unit 1, Day 3.md", beforeSha: nil, afterSha: try store("New.\n", in: journal)),
        ]
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .forward, root: root, journal: journal))
        let day3: URL = root.appendingPathComponent(section + "Unit 1, Day 3.md")
        try FileManager.default.removeItem(at: day3)
        try Data("Someone else's.\n".utf8).write(to: day3)
        let result: UndoSwapResult = UndoSwap.swap(targets, label: "1-apply", root: root)
        XCTAssertEqual(result, .refused(.changedSince(firstPath: section + "Unit 1, Day 3.md", others: 0)))
        XCTAssertEqual(try String(contentsOf: day3, encoding: .utf8), "Someone else's.\n")
        XCTAssertFalse(exists(section + "Unit 1, Day 4.md", root: root))
        XCTAssertEqual(stagedLeft(under: root), [])
    }

    /// Inertness: the new page at Day 3 written BEFORE the link's move (the
    /// filler first) is no handover, and is planned exactly as today.
    func testAFillerBeforeItsLeaverIsPlannedAsToday() throws {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "filler-first")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let target: String = try layLibraryPage("Day 3.md", text: "Linked.\n", root: root)
        try layLink(section + "Unit 1, Day 3.md", leadingTo: target, root: root)
        let ops: [UndoOp] = [
            UndoOp.writeFile(path: section + "Unit 1, Day 3.md", beforeSha: nil, afterSha: try store("New.\n", in: journal)),
            UndoOp.moveLink(from: section + "Unit 1, Day 3.md", to: section + "Unit 1, Day 4.md", linkSha: try linkSha(section + "Unit 1, Day 3.md", root: root)),
        ]
        XCTAssertEqual(UndoCheck.handovers(in: ops), [])
        let plan: UndoPlan = UndoCheck.plan(ops, direction: .forward, root: root, journal: journal)
        XCTAssertEqual(plan, .refused(.changedSince(firstPath: section + "Unit 1, Day 3.md", others: 0)))
    }

    /// Inertness: a readable U4b step (a folder's move carrying an edit,
    /// and a page outside it) is planned to the same targets in the same
    /// order as the order the plan has always given: carried move, files,
    /// other whole ops.
    func testAReadableStepKeepsTodaysTargetsInTodaysOrder() throws {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "readable")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        try UndoContractReplay.write("Inside.\n", to: "courses/TST1O/Old/a.md", in: root)
        try UndoContractReplay.write("Outside.\n", to: "courses/TST1O/b.md", in: root)
        try UndoContractReplay.write("Moved.\n", to: "courses/TST1O/c.md", in: root)
        let listingSha: String = try XCTUnwrap(UndoTreeReading.read(at: root.appendingPathComponent("courses/TST1O/Old")).listingSha)
        let cSha: String = UndoHash.sha256(of: Data("Moved.\n".utf8))
        let ops: [UndoOp] = [
            UndoOp.writeFile(path: "courses/TST1O/b.md", beforeSha: try store("Outside.\n", in: journal), afterSha: try store("Outside, relinked.\n", in: journal)),
            UndoOp.moveFile(from: "courses/TST1O/c.md", to: "courses/TST1O/d.md", sha: cSha),
            UndoOp.moveFolder(from: "courses/TST1O/Old", to: "courses/TST1O/New", listingSha: listingSha),
            UndoOp.writeFile(path: "courses/TST1O/New/a.md", beforeSha: try store("Inside.\n", in: journal), afterSha: try store("Inside, relinked.\n", in: journal)),
        ]
        XCTAssertEqual(UndoCheck.handovers(in: ops), [])
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .forward, root: root, journal: journal))
        var places: [String] = []
        for target in targets {
            places.append(target.relativePath)
        }
        XCTAssertEqual(places, ["courses/TST1O/New", "courses/TST1O/b.md", "courses/TST1O/New/a.md", "courses/TST1O/d.md"])
    }

    // MARK: - Going back (door-2)

    func testShapeAGoesBackAndForthWhole() throws {
        let laid: LaidStep = try layShapeA(leadingOut: false)
        try checkThereAndBack(laid)
    }

    func testShapeAWithTheLinkLeadingOutGoesBackAndForthWhole() throws {
        let laid: LaidStep = try layShapeA(leadingOut: true)
        try checkThereAndBack(laid)
    }

    func testShapeBGoesBackAndForthWhole() throws {
        let laid: LaidStep = try layShapeB(leadingOut: false)
        try checkThereAndBack(laid)
    }

    func testShapeBWithTheLinkLeadingOutGoesBackAndForthWhole() throws {
        let laid: LaidStep = try layShapeB(leadingOut: true)
        try checkThereAndBack(laid)
    }

    func testShapeCGoesBackAndForthWhole() throws {
        let laid: LaidStep = try layShapeC(leadingOut: false)
        try checkThereAndBack(laid)
    }

    func testShapeCWithTheLinksLeadingOutGoesBackAndForthWhole() throws {
        let laid: LaidStep = try layShapeC(leadingOut: true)
        try checkThereAndBack(laid)
    }

    /// Shape B going back is planned in the step's ops reversed: Day 2's
    /// new page taken back, the link moved Day 3 to Day 2, Day 3's page
    /// written again, Day 4's removed.
    func testShapeBGoesBackInTheStepsOrderReversed() throws {
        let laid: LaidStep = try layShapeB(leadingOut: false)
        try makeItForward(laid)
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(laid.ops, direction: .backward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(places(of: targets), [
            section + "Unit 1, Day 2.md", section + "Unit 1, Day 2.md", section + "Unit 1, Day 3.md", section + "Unit 1, Day 4.md",
        ])
        guard case .file = targets[0].change else {
            return XCTFail("Day 2's new page is taken back first, then the link moved")
        }
        XCTAssertNotEqual(targets[1].change, .file)
        XCTAssertTrue(targets[2].handedOver)
    }

    /// Shape A made, then Day 3's new page edited by hand: going back is
    /// refused naming Day 3, and nothing is changed.
    func testGoingBackOverAnEditedNewPageIsRefused() throws {
        let laid: LaidStep = try layShapeA(leadingOut: false)
        try makeItForward(laid)
        try Data("New, edited by hand.\n".utf8).write(to: laid.root.appendingPathComponent(section + "Unit 1, Day 3.md"))
        let after: [String: String] = try folderNow(laid.root)
        let plan: UndoPlan = UndoCheck.plan(laid.ops, direction: .backward, root: laid.root, journal: laid.journal)
        XCTAssertEqual(plan, .refused(.changedSince(firstPath: section + "Unit 1, Day 3.md", others: 0)))
        XCTAssertEqual(try folderNow(laid.root), after)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: laid.root.appendingPathComponent(section + "Unit 1, Day 4.md").path), "../library/Day 3.md")
    }

    /// Shape B made, then the link moved by hand away from Day 3 and a plain
    /// file put there: going back is refused naming Day 3, nothing changed.
    func testGoingBackOverAFileWhereTheLinkWasIsRefused() throws {
        let laid: LaidStep = try layShapeB(leadingOut: false)
        try makeItForward(laid)
        let day3: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 3.md")
        try FileManager.default.moveItem(at: day3, to: laid.root.appendingPathComponent(section + "Elsewhere.md"))
        try Data("Someone else's.\n".utf8).write(to: day3)
        let after: [String: String] = try folderNow(laid.root)
        let plan: UndoPlan = UndoCheck.plan(laid.ops, direction: .backward, root: laid.root, journal: laid.journal)
        guard case .refused(.changedSince(let firstPath, _)) = plan else {
            return XCTFail("the plan came to \(plan), not refused changedSince")
        }
        XCTAssertEqual(firstPath, section + "Unit 1, Day 3.md")
        XCTAssertEqual(try folderNow(laid.root), after)
    }

    // MARK: - Recovery's judgement (door-3)

    /// Shape A's table: each disk state, made by hand.
    func testRecoveryJudgesShapeAsPairTogether() throws {
        let laid: LaidStep = try layShapeA(leadingOut: false)
        let day3: String = section + "Unit 1, Day 3.md"
        let day4: String = section + "Unit 1, Day 4.md"
        let move: String = day3 + " → " + day4
        // Link at P, Q free: all before.
        XCTAssertEqual(try judged(laid), [move: .before, day3: .before])
        // P free, link at Q: part way.
        try FileManager.default.moveItem(at: laid.root.appendingPathComponent(day3), to: laid.root.appendingPathComponent(day4))
        XCTAssertEqual(try judged(laid), [move: .after, day3: .before])
        // New at P, link at Q: all after.
        try UndoContractReplay.write("New.\n", to: day3, in: laid.root)
        XCTAssertEqual(try judged(laid), [move: .after, day3: .after])
        // Something else at P, link at Q: both in the way.
        try UndoContractReplay.write("Someone else's.\n", to: day3, in: laid.root)
        XCTAssertEqual(try judged(laid), [move: .neither, day3: .neither])
    }

    /// Shape B's table, at Day 3: the removal and the link's move into it.
    func testRecoveryJudgesShapeBsPairTogether() throws {
        let laid: LaidStep = try layShapeB(leadingOut: false)
        let day2: String = section + "Unit 1, Day 2.md"
        let day3: String = section + "Unit 1, Day 3.md"
        let move: String = day2 + " → " + day3
        // Three at P, link at Day 2: all before.
        var states: [String: UndoOpState] = try judged(laid)
        XCTAssertEqual(states[day3], .before)
        XCTAssertEqual(states[move], .before)
        // P free, link at Day 2: part way.
        try FileManager.default.removeItem(at: laid.root.appendingPathComponent(day3))
        states = try judged(laid)
        XCTAssertEqual(states[day3], .after)
        XCTAssertEqual(states[move], .before)
        // Link at P, Day 2 free: all after.
        try FileManager.default.moveItem(at: laid.root.appendingPathComponent(day2), to: laid.root.appendingPathComponent(day3))
        states = try judged(laid)
        XCTAssertEqual(states[day3], .after)
        XCTAssertEqual(states[move], .after)
        // A link at P with another target: both in the way.
        try FileManager.default.removeItem(at: laid.root.appendingPathComponent(day3))
        try layLink(day3, leadingTo: try layLibraryPage("Other.md", text: "Other.\n", root: laid.root), root: laid.root)
        states = try judged(laid)
        XCTAssertEqual(states[day3], .neither)
        XCTAssertEqual(states[move], .neither)
    }

    /// Shape C's first and third rows: the first link's move away from Day
    /// 3 and the second link's move into it.
    func testRecoveryJudgesShapeCsPairTogether() throws {
        let laid: LaidStep = try layShapeC(leadingOut: false)
        let day2: String = section + "Unit 1, Day 2.md"
        let day3: String = section + "Unit 1, Day 3.md"
        let day4: String = section + "Unit 1, Day 4.md"
        let first: String = day3 + " → " + day4
        let second: String = day2 + " → " + day3
        var states: [String: UndoOpState] = try judged(laid)
        XCTAssertEqual(states[first], .before)
        XCTAssertEqual(states[second], .before)
        try FileManager.default.moveItem(at: laid.root.appendingPathComponent(day3), to: laid.root.appendingPathComponent(day4))
        try FileManager.default.moveItem(at: laid.root.appendingPathComponent(day2), to: laid.root.appendingPathComponent(day3))
        states = try judged(laid)
        XCTAssertEqual(states[first], .after)
        XCTAssertEqual(states[second], .after)
    }

    /// Each shape stopped before every swap in turn, going forward and
    /// going back: all before, part way or all after, never in the way.
    func testAStepStoppedAtAnySwapIsNeverInTheWay() throws {
        let shapes: [String] = ["A", "B", "C"]
        for shape in shapes {
            for direction in [UndoDirection.forward, UndoDirection.backward] {
                var index: Int = 0
                var stopped: Bool = true
                while stopped {
                    let laid: LaidStep = try lay(shape)
                    if direction == .backward {
                        try makeItForward(laid)
                    }
                    let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(laid.ops, direction: direction, root: laid.root, journal: laid.journal))
                    let stopAt: Int = index
                    UndoKillPoints.hook = { point in
                        point == .beforeSwap(stopAt)
                    }
                    let result: UndoSwapResult = UndoSwap.swap(targets, label: "1-test", root: laid.root)
                    UndoKillPoints.hook = nil
                    stopped = result == .stoppedByATest
                    let census: (before: Int, after: Int, neither: Int) = UndoRecovery.census(of: step(laid.ops), root: laid.root)
                    XCTAssertEqual(census.neither, 0, "shape \(shape) \(direction) stopped before swap \(index)")
                    if stopped && index > 0 {
                        XCTAssertGreaterThan(census.before, 0, "shape \(shape) \(direction) at \(index)")
                        XCTAssertGreaterThan(census.after, 0, "shape \(shape) \(direction) at \(index)")
                    }
                    index += 1
                }
                XCTAssertGreaterThanOrEqual(index, 3, "shape \(shape) has at least two swaps")
            }
        }
    }

    /// Door-1's place filled since the link left: the swap left the link
    /// at Day 4 and someone's file at Day 3. Recovery finds both in the way,
    /// so neither is put back over the other and nothing is lost.
    func testAPlaceFilledSinceTheLinkLeftIsInTheWayForRecovery() throws {
        let laid: LaidStep = try layShapeA(leadingOut: false)
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(laid.ops, direction: .forward, root: laid.root, journal: laid.journal))
        let intruder: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 3.md")
        UndoKillPoints.fileInUseAtSwap = { index in
            if index == 1 {
                try? Data("Someone else's.\n".utf8).write(to: intruder)
            }
            return false
        }
        _ = UndoSwap.swap(targets, label: "1-apply", root: laid.root)
        UndoKillPoints.fileInUseAtSwap = nil
        let census: (before: Int, after: Int, neither: Int) = UndoRecovery.census(of: step(laid.ops), root: laid.root)
        XCTAssertEqual(census.neither, 2)
    }

    /// Shape A made and taken back, its new page kept beside Day 3 as the
    /// swap keeps an original: the list holds it, judged with the link's
    /// move that hands Day 3 over.
    func testTheListHoldsAKeptOriginalAtAHandedOverPlace() throws {
        let laid: LaidStep = try layShapeA(leadingOut: false)
        try makeItForward(laid)
        let back: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(laid.ops, direction: .backward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(UndoSwap.swap(back, label: "1-undo", root: laid.root), .swapped)
        let place: URL = laid.root.appendingPathComponent(section + "Unit 1, Day 3.md")
        let kept: URL = laid.root.appendingPathComponent(section + ".Unit 1, Day 3.md-kept-by-test")
        try Data("New.\n".utf8).write(to: kept)
        XCTAssertTrue(UndoRecovery.listHolds(step(laid.ops), root: laid.root, from: laid.journal)(kept, place))
    }

    /// Inertness: a readable U4b step (a folder's move carrying an edit, a
    /// file's move, a page outside) is judged by place as it always was.
    func testAReadableStepIsJudgedAsToday() throws {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "readable-states")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        try UndoContractReplay.write("Inside.\n", to: "courses/TST1O/Old/a.md", in: root)
        try UndoContractReplay.write("Outside.\n", to: "courses/TST1O/b.md", in: root)
        try UndoContractReplay.write("Moved.\n", to: "courses/TST1O/c.md", in: root)
        let listingSha: String = try XCTUnwrap(UndoTreeReading.read(at: root.appendingPathComponent("courses/TST1O/Old")).listingSha)
        let ops: [UndoOp] = [
            UndoOp.writeFile(path: "courses/TST1O/b.md", beforeSha: try store("Outside.\n", in: journal), afterSha: try store("Outside, relinked.\n", in: journal)),
            UndoOp.moveFile(from: "courses/TST1O/c.md", to: "courses/TST1O/d.md", sha: UndoHash.sha256(of: Data("Moved.\n".utf8))),
            UndoOp.moveFolder(from: "courses/TST1O/Old", to: "courses/TST1O/New", listingSha: listingSha),
            UndoOp.writeFile(path: "courses/TST1O/New/a.md", beforeSha: try store("Inside.\n", in: journal), afterSha: try store("Inside, relinked.\n", in: journal)),
        ]
        var found: [String] = []
        for file in UndoRecovery.fileStates(of: step(ops), root: root, journal: journal) {
            found.append(file.path + " " + "\(file.state)")
        }
        XCTAssertEqual(found, [
            "courses/TST1O/b.md before", "courses/TST1O/c.md before", "courses/TST1O/Old before", "courses/TST1O/New/a.md before",
        ])
    }

    // MARK: - Readable by shape (door-4)

    func testShapesAAndBAndCAreReadable() {
        XCTAssertTrue(UndoStep.wholeOpsStandAlone(shapeAOps()))
        XCTAssertTrue(UndoStep.wholeOpsStandAlone([
            UndoOp.writeFile(path: day(4), beforeSha: nil, afterSha: fakeSha("3")),
            UndoOp.writeFile(path: day(3), beforeSha: fakeSha("3"), afterSha: nil),
            UndoOp.moveLink(from: day(2), to: day(3), linkSha: fakeSha("l")),
            UndoOp.writeFile(path: day(2), beforeSha: nil, afterSha: fakeSha("n")),
        ]))
        XCTAssertTrue(UndoStep.wholeOpsStandAlone([
            UndoOp.moveLink(from: day(3), to: day(4), linkSha: fakeSha("l")),
            UndoOp.moveLink(from: day(2), to: day(3), linkSha: fakeSha("m")),
            UndoOp.writeFile(path: day(2), beforeSha: nil, afterSha: fakeSha("n")),
        ]))
    }

    func testAFillerBeforeItsLeaverIsUnreadable() {
        XCTAssertFalse(UndoStep.wholeOpsStandAlone([
            UndoOp.writeFile(path: day(3), beforeSha: nil, afterSha: fakeSha("n")),
            UndoOp.moveLink(from: day(3), to: day(4), linkSha: fakeSha("l")),
        ]))
    }

    func testAThirdOpAtTheHandedOverPlaceIsUnreadable() {
        var ops: [UndoOp] = shapeAOps()
        ops.append(UndoOp.replaceText(path: day(3), before: "New", after: "Newer", contextBefore: "", contextAfter: ".\n"))
        XCTAssertFalse(UndoStep.wholeOpsStandAlone(ops))
    }

    func testAPlaceInsideAMovedFoldersFromIsUnreadable() {
        let folder: String = section + "media"
        XCTAssertFalse(UndoStep.wholeOpsStandAlone([
            UndoOp.moveFolder(from: folder, to: section + "renamed", listingSha: fakeSha("f")),
            UndoOp.writeFile(path: folder + "/a.md", beforeSha: nil, afterSha: fakeSha("n")),
        ]))
        XCTAssertFalse(UndoStep.wholeOpsStandAlone([
            UndoOp.moveFolder(from: folder, to: section + "renamed", listingSha: fakeSha("f")),
            UndoOp.writeFile(path: folder, beforeSha: nil, afterSha: fakeSha("n")),
        ]))
    }

    func testACaseOnlyMoveNeverHandsAPlaceOver() {
        XCTAssertFalse(UndoStep.wholeOpsStandAlone([
            UndoOp.moveFile(from: day(3), to: section + "Unit 1, day 3.md", sha: fakeSha("p")),
            UndoOp.writeFile(path: day(3), beforeSha: nil, afterSha: fakeSha("n")),
        ]))
    }

    func testAMoveApartNeverHandsAPlaceOver() {
        XCTAssertFalse(UndoStep.wholeOpsStandAlone([
            UndoOp.moveFileApart(from: day(3), to: day(4), sha: fakeSha("p")),
            UndoOp.writeFile(path: day(3), beforeSha: nil, afterSha: fakeSha("n")),
        ]))
    }

    func testAHandoverInAStepThatCarriesAnEditIsUnreadable() {
        var ops: [UndoOp] = shapeAOps()
        ops.append(UndoOp.moveFile(from: section + "a.md", to: section + "b.md", sha: fakeSha("a")))
        ops.append(UndoOp.replaceText(path: section + "b.md", before: "old", after: "new", contextBefore: "", contextAfter: ".\n"))
        XCTAssertFalse(UndoStep.wholeOpsStandAlone(ops))
        // Without the handover, the same carried edit is readable (U4b).
        XCTAssertTrue(UndoStep.wholeOpsStandAlone([ops[2], ops[3]]))
    }

    func testAPlaceHandedOverTwiceIsUnreadable() {
        var ops: [UndoOp] = shapeAOps()
        ops.append(UndoOp.writeFile(path: day(3), beforeSha: fakeSha("n"), afterSha: nil))
        ops.append(UndoOp.moveLink(from: day(2), to: day(3), linkSha: fakeSha("m")))
        XCTAssertEqual(UndoCheck.handovers(in: ops).count, 2)
        XCTAssertFalse(UndoStep.wholeOpsStandAlone(ops))
    }

    /// The step as a reader reads it back from the journal: readable.
    func testAHandedOverStepIsReadBackReadable() throws {
        let made: UndoStep = UndoStep(
            seq: 1, madeAt: "2026-11-26T12:00:00Z",
            action: UndoAction(key: "insertClass", arguments: [:]),
            madeBy: "menu", workingFolder: UndoWorkingFolder(id: "00000000-0000-0000-0000-000000000000", pathAtTheTime: parent.path),
            course: "TST1O", section: 1, actionClass: "A", holds: "section", ops: shapeAOps()
        )
        let readBack: UndoStep = try JSONDecoder().decode(UndoStep.self, from: JSONEncoder().encode(made))
        XCTAssertTrue(readBack.isReadable)
    }

    // MARK: - Killed and recovered (door-5)

    /// Each of door-4's two shapes, made through the door and killed before
    /// EVERY swap in turn, going forward and (its Undo) going back, until a
    /// kill point is no longer reached: once recovery has run, the folder
    /// is whole before or whole after, the library byte for byte as laid,
    /// nothing staged left, the step settled.
    func testAHandedOverStepKilledBeforeAnyOfItsSwapsIsWholeAfterRecovery() throws {
        try killAtEverySwap(leadingOut: false)
    }

    /// The same, the links leading OUT of the working folder: nothing
    /// outside it read or written.
    func testAHandedOverStepLeadingOutKilledBeforeAnyOfItsSwapsIsWholeAfterRecovery() throws {
        try killAtEverySwap(leadingOut: true)
    }

    func killAtEverySwap(leadingOut: Bool) throws {
        for shape in ["A", "B"] {
            for backward in [false, true] {
                let whole: (before: [String: String], after: [String: String]) = try madeWhole(shape, leadingOut: leadingOut)
                var index: Int = 0
                while try killAndRecover(shape, leadingOut: leadingOut, backward: backward, at: index, whole: whole) {
                    index += 1
                }
                let swaps: Int = shape == "A" ? 2 : 4
                XCTAssertEqual(index, swaps, "shape \(shape), backward \(backward): one kill before each swap")
            }
        }
    }

    /// The folder as laid, and as the step leaves it made whole.
    func madeWhole(_ shape: String, leadingOut: Bool) throws -> (before: [String: String], after: [String: String]) {
        let laid: LaidStep = shape == "A" ? try layShapeA(leadingOut: leadingOut) : try layShapeB(leadingOut: leadingOut)
        let before: [String: String] = try snapshot(laid.root)
        try makeItForward(laid)
        return (before: before, after: try snapshot(laid.root))
    }

    /// `folderNow` but for the folder's own identifier, which each laying
    /// makes anew.
    func snapshot(_ root: URL) throws -> [String: String] {
        var found: [String: String] = try folderNow(root)
        found["courses/.internal/folder-id"] = nil
        found["courses/.internal"] = nil
        return found
    }

    /// Returns whether the kill point was reached (and so tested).
    func killAndRecover(
        _ shape: String, leadingOut: Bool, backward: Bool, at index: Int,
        whole: (before: [String: String], after: [String: String])
    ) throws -> Bool {
        let laid: LaidStep = shape == "A" ? try layShapeA(leadingOut: leadingOut) : try layShapeB(leadingOut: leadingOut)
        let outsideBefore: [String: Data] = try outsideNow()
        var blobs: [Data] = [Data("New.\n".utf8)]
        if shape == "B" {
            blobs.append(Data("Three.\n".utf8))
        }
        let dying: UndoJournal = UndoJournal(
            folderURL: laid.journal.folderURL, process: UndoContractReplay.goneProcess,
            processIsAlive: { process in process.pid != UndoContractReplay.goneProcess.pid }
        )
        let places: UndoMemoryPlaces = UndoMemoryPlaces()
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: laid.ops, blobs: blobs, root: laid.root, action: "insertClass")
        var reached: Bool = false
        UndoKillPoints.hook = { point in
            point == .beforeSwap(index)
        }
        if backward {
            UndoKillPoints.hook = nil
            let made: JournaledWriteOutcome = JournaledWrite.perform(ops: draft, in: dying, mode: .live, places: places)
            XCTAssertEqual(try snapshot(laid.root), whole.after, "shape \(shape): the step made whole (\(made))")
            UndoKillPoints.hook = { point in
                point == .beforeSwap(index)
            }
            reached = dying.undoNewest(resolveRoot: { _ in laid.root }, places: places) == .stoppedByATest
        } else {
            let outcome: JournaledWriteOutcome = JournaledWrite.perform(ops: draft, in: dying, mode: .live, places: places)
            reached = outcome == .stoppedByATest
            if !reached && index == 0 {
                XCTFail("shape \(shape): the step was never stopped (\(outcome))")
            }
        }
        UndoKillPoints.hook = nil
        if !reached {
            return false
        }
        let survivor: UndoJournal = UndoJournal(
            folderURL: laid.journal.folderURL,
            processIsAlive: { process in process.pid != UndoContractReplay.goneProcess.pid }
        )
        try survivor.withLock { writer in
            UndoRecovery.run(writer, mode: .live, resolveRoot: { _ in laid.root })
        }
        let label: String = "shape \(shape), backward \(backward), killed before swap \(index)"
        let now: [String: String] = try snapshot(laid.root)
        XCTAssertTrue(now == whole.before || now == whole.after, "\(label): not whole (\(now))")
        XCTAssertEqual(try outsideNow(), outsideBefore, label)
        if !leadingOut {
            let library: [String] = try FileManager.default.contentsOfDirectory(atPath: laid.root.appendingPathComponent("courses/TST1O/library").path)
            XCTAssertEqual(library.count, 1, label)
        }
        XCTAssertEqual(stagedLeft(under: laid.root), [], label)
        let phase: String = (try survivor.read()).records[1]?.phase.rawValue ?? "missing"
        XCTAssertTrue(["failed", "rolledBack", "done", "undone"].contains(phase), "\(label): the step is \(phase)")
        return true
    }

    // MARK: - Functions

    func day(_ number: Int) -> String {
        return section + "Unit 1, Day \(number).md"
    }

    /// A well-formed hash, one per name, for a step judged by shape only.
    func fakeSha(_ name: String) -> String {
        return UndoHash.sha256(of: Data(name.utf8))
    }

    func shapeAOps() -> [UndoOp] {
        return [
            UndoOp.moveLink(from: day(3), to: day(4), linkSha: fakeSha("l")),
            UndoOp.writeFile(path: day(3), beforeSha: nil, afterSha: fakeSha("n")),
        ]
    }

    /// An in-memory step holding these ops.
    func step(_ ops: [UndoOp]) -> UndoStep {
        return UndoStep(
            seq: 1, madeAt: "2026-11-26T12:00:00Z",
            action: UndoAction(key: "insertClass", arguments: [:]),
            madeBy: "menu", workingFolder: nil, course: "TST1O", section: 1,
            actionClass: "A", holds: "section", ops: ops
        )
    }

    /// Recovery's judgement of a laid step, by place.
    func judged(_ laid: LaidStep) throws -> [String: UndoOpState] {
        var found: [String: UndoOpState] = [:]
        for file in UndoRecovery.fileStates(of: step(laid.ops), root: laid.root, journal: laid.journal) {
            XCTAssertNil(found[file.path], "one place judged twice: \(file.path)")
            found[file.path] = file.state
        }
        return found
    }

    func lay(_ shape: String) throws -> LaidStep {
        if shape == "A" {
            return try layShapeA(leadingOut: false)
        }
        if shape == "B" {
            return try layShapeB(leadingOut: false)
        }
        return try layShapeC(leadingOut: false)
    }

    /// A step laid on disk as it stands before the step: its folder, its
    /// journal and its ops.
    struct LaidStep {

        // MARK: - Stored properties

        let root: URL

        let journal: UndoJournal

        let ops: [UndoOp]
    }

    func layShapeA(leadingOut: Bool) throws -> LaidStep {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "back-a")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let target: String = try linkTarget(named: "Day 3.md", text: "Linked.\n", root: root, leadingOut: leadingOut)
        try layLink(section + "Unit 1, Day 3.md", leadingTo: target, root: root)
        let ops: [UndoOp] = [
            UndoOp.moveLink(from: section + "Unit 1, Day 3.md", to: section + "Unit 1, Day 4.md", linkSha: try linkSha(section + "Unit 1, Day 3.md", root: root)),
            UndoOp.writeFile(path: section + "Unit 1, Day 3.md", beforeSha: nil, afterSha: try store("New.\n", in: journal)),
        ]
        return LaidStep(root: root, journal: journal, ops: ops)
    }

    func layShapeB(leadingOut: Bool) throws -> LaidStep {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "back-b")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let target: String = try linkTarget(named: "Day 2.md", text: "Linked.\n", root: root, leadingOut: leadingOut)
        try layLink(section + "Unit 1, Day 2.md", leadingTo: target, root: root)
        try UndoContractReplay.write("Three.\n", to: section + "Unit 1, Day 3.md", in: root)
        let three: String = try store("Three.\n", in: journal)
        let ops: [UndoOp] = [
            UndoOp.writeFile(path: section + "Unit 1, Day 4.md", beforeSha: nil, afterSha: three),
            UndoOp.writeFile(path: section + "Unit 1, Day 3.md", beforeSha: three, afterSha: nil),
            UndoOp.moveLink(from: section + "Unit 1, Day 2.md", to: section + "Unit 1, Day 3.md", linkSha: try linkSha(section + "Unit 1, Day 2.md", root: root)),
            UndoOp.writeFile(path: section + "Unit 1, Day 2.md", beforeSha: nil, afterSha: try store("New.\n", in: journal)),
        ]
        return LaidStep(root: root, journal: journal, ops: ops)
    }

    func layShapeC(leadingOut: Bool) throws -> LaidStep {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "back-c")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let target3: String = try linkTarget(named: "Day 3.md", text: "Linked three.\n", root: root, leadingOut: leadingOut)
        let target2: String = try linkTarget(named: "Day 2.md", text: "Linked two.\n", root: root, leadingOut: leadingOut)
        try layLink(section + "Unit 1, Day 3.md", leadingTo: target3, root: root)
        try layLink(section + "Unit 1, Day 2.md", leadingTo: target2, root: root)
        let ops: [UndoOp] = [
            UndoOp.moveLink(from: section + "Unit 1, Day 3.md", to: section + "Unit 1, Day 4.md", linkSha: try linkSha(section + "Unit 1, Day 3.md", root: root)),
            UndoOp.moveLink(from: section + "Unit 1, Day 2.md", to: section + "Unit 1, Day 3.md", linkSha: try linkSha(section + "Unit 1, Day 2.md", root: root)),
            UndoOp.writeFile(path: section + "Unit 1, Day 2.md", beforeSha: nil, afterSha: try store("New.\n", in: journal)),
        ]
        return LaidStep(root: root, journal: journal, ops: ops)
    }

    /// The step made going forward, as door-1 plans and swaps it.
    func makeItForward(_ laid: LaidStep, label: String = "1-apply") throws {
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(laid.ops, direction: .forward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(UndoSwap.swap(targets, label: label, root: laid.root), .swapped)
    }

    /// The step taken back, made again (a Redo) and taken back again: each
    /// goes in, and each time it is back the folder and the folder outside
    /// are byte for byte as they were before the step, nothing staged left.
    func checkThereAndBack(_ laid: LaidStep) throws {
        let before: [String: String] = try folderNow(laid.root)
        let outsideBefore: [String: Data] = try outsideNow()
        try makeItForward(laid)
        let made: [String: String] = try folderNow(laid.root)
        XCTAssertNotEqual(made, before)
        let back: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(laid.ops, direction: .backward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(UndoSwap.swap(back, label: "1-undo", root: laid.root), .swapped)
        XCTAssertEqual(try folderNow(laid.root), before)
        XCTAssertEqual(try outsideNow(), outsideBefore)
        try makeItForward(laid, label: "1-redo")
        XCTAssertEqual(try folderNow(laid.root), made)
        let again: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(laid.ops, direction: .backward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(UndoSwap.swap(again, label: "1-undo", root: laid.root), .swapped)
        XCTAssertEqual(try folderNow(laid.root), before)
        XCTAssertEqual(try outsideNow(), outsideBefore)
        XCTAssertEqual(stagedLeft(under: laid.root), [])
    }

    /// Everything under the root, by relative path: a link by where it
    /// leads, a file by its bytes, a folder as a folder. Never followed
    /// through a link.
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

    func checkShapeA(leadingOut: Bool) throws {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "a")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let target: String = try linkTarget(named: "Day 3.md", text: "Linked.\n", root: root, leadingOut: leadingOut)
        try layLink(section + "Unit 1, Day 3.md", leadingTo: target, root: root)
        let before: [String: Data] = try outsideNow()
        let ops: [UndoOp] = [
            UndoOp.moveLink(from: section + "Unit 1, Day 3.md", to: section + "Unit 1, Day 4.md", linkSha: try linkSha(section + "Unit 1, Day 3.md", root: root)),
            UndoOp.writeFile(path: section + "Unit 1, Day 3.md", beforeSha: nil, afterSha: try store("New.\n", in: journal)),
        ]
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .forward, root: root, journal: journal))
        XCTAssertEqual(places(of: targets), [section + "Unit 1, Day 4.md", section + "Unit 1, Day 3.md"])
        XCTAssertEqual(UndoSwap.swap(targets, label: "1-apply", root: root), .swapped)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent(section + "Unit 1, Day 4.md").path), target)
        XCTAssertEqual(try text(section + "Unit 1, Day 3.md", root: root), "New.\n")
        try checkTheLibraryAndOutside(root: root, leadingOut: leadingOut, before: before, names: ["Day 3.md"])
        XCTAssertEqual(stagedLeft(under: root), [])
    }

    func checkShapeB(leadingOut: Bool) throws {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "b")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let target: String = try linkTarget(named: "Day 2.md", text: "Linked.\n", root: root, leadingOut: leadingOut)
        try layLink(section + "Unit 1, Day 2.md", leadingTo: target, root: root)
        try UndoContractReplay.write("Three.\n", to: section + "Unit 1, Day 3.md", in: root)
        let before: [String: Data] = try outsideNow()
        let three: String = try store("Three.\n", in: journal)
        let ops: [UndoOp] = [
            UndoOp.writeFile(path: section + "Unit 1, Day 4.md", beforeSha: nil, afterSha: three),
            UndoOp.writeFile(path: section + "Unit 1, Day 3.md", beforeSha: three, afterSha: nil),
            UndoOp.moveLink(from: section + "Unit 1, Day 2.md", to: section + "Unit 1, Day 3.md", linkSha: try linkSha(section + "Unit 1, Day 2.md", root: root)),
            UndoOp.writeFile(path: section + "Unit 1, Day 2.md", beforeSha: nil, afterSha: try store("New.\n", in: journal)),
        ]
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .forward, root: root, journal: journal))
        XCTAssertEqual(places(of: targets), [
            section + "Unit 1, Day 4.md", section + "Unit 1, Day 3.md", section + "Unit 1, Day 3.md", section + "Unit 1, Day 2.md",
        ])
        XCTAssertEqual(UndoSwap.swap(targets, label: "1-apply", root: root), .swapped)
        XCTAssertEqual(try text(section + "Unit 1, Day 4.md", root: root), "Three.\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent(section + "Unit 1, Day 3.md").path), target)
        XCTAssertEqual(try text(section + "Unit 1, Day 2.md", root: root), "New.\n")
        try checkTheLibraryAndOutside(root: root, leadingOut: leadingOut, before: before, names: ["Day 2.md"])
        XCTAssertEqual(stagedLeft(under: root), [])
    }

    func checkShapeC(leadingOut: Bool) throws {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "c")
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        let target3: String = try linkTarget(named: "Day 3.md", text: "Linked three.\n", root: root, leadingOut: leadingOut)
        let target2: String = try linkTarget(named: "Day 2.md", text: "Linked two.\n", root: root, leadingOut: leadingOut)
        try layLink(section + "Unit 1, Day 3.md", leadingTo: target3, root: root)
        try layLink(section + "Unit 1, Day 2.md", leadingTo: target2, root: root)
        let before: [String: Data] = try outsideNow()
        let ops: [UndoOp] = [
            UndoOp.moveLink(from: section + "Unit 1, Day 3.md", to: section + "Unit 1, Day 4.md", linkSha: try linkSha(section + "Unit 1, Day 3.md", root: root)),
            UndoOp.moveLink(from: section + "Unit 1, Day 2.md", to: section + "Unit 1, Day 3.md", linkSha: try linkSha(section + "Unit 1, Day 2.md", root: root)),
            UndoOp.writeFile(path: section + "Unit 1, Day 2.md", beforeSha: nil, afterSha: try store("New.\n", in: journal)),
        ]
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(ops, direction: .forward, root: root, journal: journal))
        XCTAssertEqual(places(of: targets), [section + "Unit 1, Day 4.md", section + "Unit 1, Day 3.md", section + "Unit 1, Day 2.md"])
        XCTAssertEqual(UndoSwap.swap(targets, label: "1-apply", root: root), .swapped)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent(section + "Unit 1, Day 4.md").path), target3)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent(section + "Unit 1, Day 3.md").path), target2)
        XCTAssertEqual(try text(section + "Unit 1, Day 2.md", root: root), "New.\n")
        try checkTheLibraryAndOutside(root: root, leadingOut: leadingOut, before: before, names: ["Day 3.md", "Day 2.md"])
        XCTAssertEqual(stagedLeft(under: root), [])
    }

    /// The page a link leads to: in `library/` (relative target), or in the
    /// folder outside the working folder (absolute target).
    func linkTarget(named name: String, text: String, root: URL, leadingOut: Bool) throws -> String {
        if leadingOut {
            let url: URL = outside.appendingPathComponent(name)
            try Data(text.utf8).write(to: url)
            return url.path
        }
        return try layLibraryPage(name, text: text, root: root)
    }

    func layLibraryPage(_ name: String, text: String, root: URL) throws -> String {
        try UndoContractReplay.write(text, to: "courses/TST1O/library/" + name, in: root)
        return "../library/" + name
    }

    func layLink(_ relativePath: String, leadingTo destination: String, root: URL) throws {
        let url: URL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    func linkSha(_ relativePath: String, root: URL) throws -> String {
        return try XCTUnwrap(UndoTreeReading.linkSha(at: root.appendingPathComponent(relativePath)))
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

    func exists(_ relativePath: String, root: URL) -> Bool {
        let url: URL = root.appendingPathComponent(relativePath)
        return (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Every file in the folder outside, by name, with its bytes.
    func outsideNow() throws -> [String: Data] {
        var found: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: outside.path) {
            found[name] = try Data(contentsOf: outside.appendingPathComponent(name))
        }
        return found
    }

    /// The pages links lead to, byte for byte as laid, and the folder
    /// outside exactly as it was.
    func checkTheLibraryAndOutside(root: URL, leadingOut: Bool, before: [String: Data], names: [String]) throws {
        XCTAssertEqual(try outsideNow(), before)
        if leadingOut {
            return
        }
        for name in names {
            let data: Data = try Data(contentsOf: root.appendingPathComponent("courses/TST1O/library/" + name))
            XCTAssertTrue(data == Data("Linked.\n".utf8) || data == Data("Linked three.\n".utf8) || data == Data("Linked two.\n".utf8))
        }
        let library: [String] = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("courses/TST1O/library").path)
        XCTAssertEqual(library.count, names.count)
    }

    /// Every name under the root holding the swap's staged marker.
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
