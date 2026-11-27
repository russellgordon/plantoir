import XCTest
@testable import QuartzTeachers

/// #1055 M5: the kept-page guard (U4b3 kept-original-named and review fix
/// 1, "a put-back never writes over a file it did not expect") laid on a
/// plain step with no link anywhere. The step moves Day 3's page to Day 4
/// as Insert Class does for an ordinary class (a new file at Day 4 with the
/// page's content, Day 3's page removed) and writes a new page at Day 5; a
/// plain file is then written at Day 3 by someone else before the step's
/// last swap, which is refused, so the step cannot put Day 3's page back
/// over what is there.
final class UndoKeptPageUnderAVisibleNameTests: XCTestCase {

    // MARK: - Stored properties

    var parent: URL = FileManager.default.temporaryDirectory

    let section: String = "courses/TST1O/section1/"

    // MARK: - Setting up

    override func setUpWithError() throws {
        let name: String = "kept-page-" + UUID().uuidString
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        UndoKillPoints.fileInUseAtSwap = nil
        UndoKillPoints.hook = nil
        try? FileManager.default.removeItem(at: parent)
    }

    // MARK: - The kept-page guard on a plain step (#1055 M5)

    /// Going forward, a plain file written at Day 3 once its page has been
    /// removed, and the step's last swap then refused: the page is never
    /// put back over the file put there; both are left for recovery, the
    /// page's content kept.
    func testAFileWrittenWhereAPageWasRemovedIsNeverWrittenOver() throws {
        let laid: LaidStep = try layAPlainStep(named: "forward")
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(laid.ops, direction: .forward, root: laid.root, journal: laid.journal))
        let intruder: URL = laid.root.appendingPathComponent(day(3))
        let lastSwap: Int = targets.count - 1
        UndoKillPoints.fileInUseAtSwap = { index in
            if index == lastSwap {
                try? Data("Someone else's.\n".utf8).write(to: intruder)
                return true
            }
            return false
        }
        let result: UndoSwapResult = UndoSwap.swap(targets, label: "1-apply", root: laid.root)
        UndoKillPoints.fileInUseAtSwap = nil
        guard case .notPutBack(_, let kept) = result else {
            return XCTFail("the swap came to \(result), not notPutBack")
        }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try String(contentsOf: intruder, encoding: .utf8), "Someone else's.\n")
        XCTAssertTrue(try holdsSomewhere("Three.\n", root: laid.root), "the removed page is kept")
    }

    /// The Undo of a plain step that wrote new pages at Day 3 and Day 5: a
    /// plain file written at Day 3 once the Undo has taken its new page
    /// away, and the Undo's last swap then refused: the new page is never
    /// put back over the file put there, its content kept.
    func testAFileWrittenWhereTheUndoTookAPageAwayIsNeverWrittenOver() throws {
        let laid: LaidStep = try layAPlainNewPageStep(named: "backward")
        try makeItForward(laid)
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(laid.ops, direction: .backward, root: laid.root, journal: laid.journal))
        let intruder: URL = laid.root.appendingPathComponent(day(3))
        let lastSwap: Int = targets.count - 1
        UndoKillPoints.fileInUseAtSwap = { index in
            if index == lastSwap {
                try? Data("Someone else's.\n".utf8).write(to: intruder)
                return true
            }
            return false
        }
        let result: UndoSwapResult = UndoSwap.swap(targets, label: "1-undo", root: laid.root)
        UndoKillPoints.fileInUseAtSwap = nil
        guard case .notPutBack(_, let kept) = result else {
            return XCTFail("the swap came to \(result), not notPutBack")
        }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try String(contentsOf: intruder, encoding: .utf8), "Someone else's.\n")
        XCTAssertTrue(try holdsSomewhere("New.\n", root: laid.root), "the page taken away is kept")
    }

    /// The first of those made through the door by a process that dies,
    /// then recovered by another process: the file at Day 3 byte for byte,
    /// the removed page kept as `Unit 1, Day 3 (kept by Undo).md`, nothing
    /// left hidden, the trail told once with both names, the step
    /// `interrupted`.
    func testAPageRemovedWhosePlaceIsTakenIsKeptUnderAVisibleNameAfterRecovery() throws {
        let found: KeptPageProbe = try probeAKeptPage(visibleNameTaken: false)
        XCTAssertEqual(stagedLeft(under: found.root), [])
        XCTAssertEqual(UndoItem.read(at: found.root.appendingPathComponent(section + "Unit 1, Day 3 (kept by Undo).md")), .file(Data("Three.\n".utf8)))
        XCTAssertEqual(try String(contentsOf: found.root.appendingPathComponent(day(3)), encoding: .utf8), "Someone else's.\n")
        XCTAssertEqual(found.lines, [day(3) + " -> " + section + "Unit 1, Day 3 (kept by Undo).md"])
        XCTAssertEqual(found.phase, "interrupted", "the step is \(found.phase)")
    }

    /// The same with the visible name already taken: kept as `(kept by
    /// Undo 2)`, the taken name untouched.
    func testAPageKeptUnderAVisibleNameSkipsATakenName() throws {
        let found: KeptPageProbe = try probeAKeptPage(visibleNameTaken: true)
        XCTAssertEqual(stagedLeft(under: found.root), [])
        XCTAssertEqual(UndoItem.read(at: found.root.appendingPathComponent(section + "Unit 1, Day 3 (kept by Undo).md")), .file(Data("earlier\n".utf8)))
        XCTAssertEqual(UndoItem.read(at: found.root.appendingPathComponent(section + "Unit 1, Day 3 (kept by Undo 2).md")), .file(Data("Three.\n".utf8)))
        XCTAssertEqual(try String(contentsOf: found.root.appendingPathComponent(day(3)), encoding: .utf8), "Someone else's.\n")
        XCTAssertEqual(found.lines, [day(3) + " -> " + section + "Unit 1, Day 3 (kept by Undo 2).md"])
    }

    // MARK: - Laying a step

    struct LaidStep {

        // MARK: - Stored properties

        let root: URL

        let journal: UndoJournal

        let ops: [UndoOp]
    }

    struct KeptPageProbe {

        // MARK: - Stored properties

        let root: URL

        let lines: [String]

        let phase: String
    }

    func day(_ number: Int) -> String {
        return section + "Unit 1, Day \(number).md"
    }

    /// Day 3's page moved to Day 4 (a new file holding its content, Day 3's
    /// page removed), and a new page written at Day 5. No link anywhere.
    func layAPlainStep(named name: String) throws -> LaidStep {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: name)
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        try UndoContractReplay.write("Three.\n", to: day(3), in: root)
        let three: String = try store("Three.\n", in: journal)
        let ops: [UndoOp] = [
            UndoOp.writeFile(path: day(4), beforeSha: nil, afterSha: three),
            UndoOp.writeFile(path: day(3), beforeSha: three, afterSha: nil),
            UndoOp.writeFile(path: day(5), beforeSha: nil, afterSha: try store("Five.\n", in: journal)),
        ]
        return LaidStep(root: root, journal: journal, ops: ops)
    }

    /// A new page written at Day 5 and one at Day 3, so the Undo (swapped
    /// in the step's order reversed) takes Day 3's away first. No link
    /// anywhere.
    func layAPlainNewPageStep(named name: String) throws -> LaidStep {
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: name)
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        let root: URL = place.root
        try FileManager.default.createDirectory(at: root.appendingPathComponent(section), withIntermediateDirectories: true)
        let ops: [UndoOp] = [
            UndoOp.writeFile(path: day(5), beforeSha: nil, afterSha: try store("Five.\n", in: journal)),
            UndoOp.writeFile(path: day(3), beforeSha: nil, afterSha: try store("New.\n", in: journal)),
        ]
        return LaidStep(root: root, journal: journal, ops: ops)
    }

    func makeItForward(_ laid: LaidStep) throws {
        let targets: [UndoSwapTarget] = try readyTargets(UndoCheck.plan(laid.ops, direction: .forward, root: laid.root, journal: laid.journal))
        XCTAssertEqual(UndoSwap.swap(targets, label: "1-apply", root: laid.root), .swapped)
    }

    /// The plain step made through the door by a process that dies, with a
    /// file written at Day 3 once its page is removed and the last swap
    /// refused (and, when asked, the visible name taken first), then
    /// recovered by another process; the root, every 'undo kept a page
    /// under a visible name' line as "place -> visible name", and the
    /// step's phase.
    func probeAKeptPage(visibleNameTaken: Bool) throws -> KeptPageProbe {
        let laid: LaidStep = try layAPlainStep(named: "probe")
        let dying: UndoJournal = UndoJournal(
            folderURL: laid.journal.folderURL, process: UndoContractReplay.goneProcess,
            processIsAlive: { process in process.pid != UndoContractReplay.goneProcess.pid }
        )
        let blobs: [Data] = [Data("Three.\n".utf8), Data("Five.\n".utf8)]
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: laid.ops, blobs: blobs, root: laid.root, action: "insertClass")
        let intruder: URL = laid.root.appendingPathComponent(day(3))
        UndoKillPoints.fileInUseAtSwap = { index in
            if index == laid.ops.count - 1 {
                try? Data("Someone else's.\n".utf8).write(to: intruder)
                return true
            }
            return false
        }
        _ = JournaledWrite.perform(ops: draft, in: dying, mode: .live, places: UndoMemoryPlaces())
        UndoKillPoints.fileInUseAtSwap = nil
        if visibleNameTaken {
            try UndoContractReplay.write("earlier\n", to: section + "Unit 1, Day 3 (kept by Undo).md", in: laid.root)
        }
        var lines: [String] = []
        let hookBefore = UndoTrailHook.keptAPageLine
        UndoTrailHook.keptAPageLine = { _, _, place, keptAs in
            lines.append(place + " -> " + keptAs)
        }
        defer {
            UndoTrailHook.keptAPageLine = hookBefore
        }
        let survivor: UndoJournal = UndoJournal(
            folderURL: laid.journal.folderURL,
            processIsAlive: { process in process.pid != UndoContractReplay.goneProcess.pid }
        )
        try survivor.withLock { writer in
            UndoRecovery.run(writer, mode: .live, resolveRoot: { _ in laid.root })
        }
        let phase: String = (try survivor.read()).records[1]?.phase.rawValue ?? "missing"
        return KeptPageProbe(root: laid.root, lines: lines, phase: phase)
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

    /// Whether any file under the root, kept originals included, holds
    /// exactly this text, outside the journal.
    func holdsSomewhere(_ text: String, root: URL) throws -> Bool {
        let wanted: Data = Data(text.utf8)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            return false
        }
        while let name = walker.nextObject() as? String {
            if name.hasPrefix("courses/.internal") {
                continue
            }
            let url: URL = root.appendingPathComponent(name)
            let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: url.path)
            let type: FileAttributeType? = attributes[.type] as? FileAttributeType
            if type == .typeRegular, (try Data(contentsOf: url)) == wanted {
                return true
            }
        }
        return false
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
