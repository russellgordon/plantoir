import XCTest
@testable import QuartzTeachers

/// The op kinds U2 defines (#899), where the contract's cases cannot reach:
/// the app's own front-page rule as the `sectionFrontPage` maintainer, the
/// app's preferences as an `external` place, and the guarantees of the
/// swap that no case observes (a move never replaces, a JSON member's
/// neighbours are kept, a folder taken out is never lost). The rules
/// themselves are `undo.checkCases`, `listingCases`, `stackCases` and
/// `recoveryCases`, replayed by `UndoJournalContractTests`.
final class UndoOpKindsTests: XCTestCase {

    // MARK: - Stored properties

    var scratchURL: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    // MARK: - Functions

    override func setUpWithError() throws {
        scratchURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UndoOpKindsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchURL)
        UndoContractReplay.registerTheFrontPageMaintainer()
    }

    /// The maintainer re-derives the landing page by the app's own rule,
    /// from the pages as they stand: a newer class published since is the
    /// one it points at. MUST FAIL with a runner that writes nothing.
    @MainActor
    func testTheFrontPageIsRederivedByTheAppsOwnRule() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "one", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-10", body: "two", in: made.course)
        let indexURL: URL = SectionIndexPointer.indexURL(forSection: 1, in: made.course)
        let index: String = "---\ntitle: Section 1\ncreated: 2026-08-01T09:00:00.000-0400\npublish: true\n---\n# Most Recent Class\n![[Unit 1, Day 1]]\n"
        try index.write(to: indexURL, atomically: true, encoding: .utf8)
        let root: URL = made.course.directoryURL.deletingLastPathComponent().deletingLastPathComponent()
        let path: String = try XCTUnwrap(UndoFolderPlaces.relativePath(of: indexURL, under: root))
        let op: UndoOp = UndoOp.recompute(path: path, maintainer: "sectionFrontPage", section: 1)

        XCTAssertTrue(UndoSectionFrontPage.rederive(op, root: root))

        let after: String = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(after.contains("![[Unit 1, Day 2]]"), after)
    }

    /// A recompute naming a page that is not the section's landing page is
    /// refused, writing nothing.
    @MainActor
    func testTheFrontPageMaintainerRefusesAnotherPage() throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let root: URL = made.course.directoryURL.deletingLastPathComponent().deletingLastPathComponent()
        let op: UndoOp = UndoOp.recompute(path: "courses/\(made.course.code)/notes.md", maintainer: "sectionFrontPage", section: 1)
        XCTAssertFalse(UndoSectionFrontPage.rederive(op, root: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(op.path ?? "").path))
    }

    /// One of the app's preferences, set and taken back through the list,
    /// in a step with no working folder.
    func testAPreferenceIsUndoneAndRedoneThroughTheList() throws {
        // A store of the test's own, never the app's (the hard review of
        // U2b, MEDIUM 6: under the unit suite PlantoirDefaults.shared is the
        // real preferences of ca.russellgordon.Plantoir).
        let suiteName: String = "UndoOpKindsTests-\(UUID().uuidString)"
        let store: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            store.removePersistentDomain(forName: suiteName)
        }
        let places: UndoAppPreferences = UndoAppPreferences(store: store)
        let key: String = "aPreference"
        store.set("before", forKey: key)
        let journal: UndoJournal = UndoJournal(folderURL: scratchURL.appendingPathComponent("undo", isDirectory: true))
        let op: UndoOp = UndoOp.external(target: "preference:" + key, before: .string("before"), after: .string("after"))
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [op], blobs: [], root: nil, action: "setPreference")

        XCTAssertEqual(JournaledWrite.perform(ops: draft, in: journal, mode: .live, places: places), .applied(seq: 1))
        XCTAssertEqual(store.string(forKey: key), "after")
        XCTAssertEqual(journal.undoNewest(places: places), .undone(seq: 1))
        XCTAssertEqual(store.string(forKey: key), "before")
        XCTAssertEqual(journal.redoNewest(places: places), .redone(seq: 1))
        XCTAssertEqual(store.string(forKey: key), "after")
        XCTAssertNil(PlantoirDefaults.shared.object(forKey: key), "the app's own store is never touched")
    }

    /// U4b2-9 (the part-two review of U4b, LOW 2): an edit spelled with
    /// other capitals than the move's `to` (`Renamed/a.md` under a move to
    /// `renamed`) is carried by the move, and the swap that takes it back
    /// leaves the edit's own kept files out of the move's pair and follows
    /// them when the folder moves, by the same comparison
    /// (`UndoOp.partInside`). The Undo of an untouched step goes back and
    /// leaves nothing of its own behind; so does the Redo. FAILED before the
    /// one comparison, when `ownFilesInside` and `followTheMove` compared
    /// paths as spelled.
    func testAnEditSpelledWithOtherCapitalsUnderACarryingMoveIsUndoneAndRedone() throws {
        let root: URL = scratchURL.appendingPathComponent("folder", isDirectory: true)
        let journal: UndoJournal = UndoJournal(folderURL: scratchURL.appendingPathComponent("undo", isDirectory: true))
        let places: UndoMemoryPlaces = UndoMemoryPlaces()
        let oldFolder: String = "courses/TST1O/media"
        let newFolder: String = "courses/TST1O/renamed"
        try UndoContractReplay.write("Intro.\nLine one: old.\nEnd.\n", to: oldFolder + "/a.md", in: root)
        try UndoContractReplay.write("B\n", to: oldFolder + "/b.md", in: root)
        let listingSha: String = try XCTUnwrap(UndoTreeReading.read(at: root.appendingPathComponent(oldFolder)).listingSha)
        let move: UndoOp = UndoOp.moveFolder(from: oldFolder, to: newFolder, listingSha: listingSha)
        let edit: UndoOp = UndoOp.replaceText(
            path: "courses/TST1O/Renamed/a.md", before: "old", after: "new", contextBefore: "Line one: ", contextAfter: ".\n"
        )
        XCTAssertTrue(UndoOp.moveCarries(move, edit), "the move carries the edit, compared without regard to case")
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [move, edit], blobs: [], root: root, action: "renameFolder")
        XCTAssertEqual(JournaledWrite.perform(ops: draft, in: journal, mode: .live, places: places), .applied(seq: 1))
        let movedPage: URL = root.appendingPathComponent(newFolder + "/a.md")
        XCTAssertEqual(try String(contentsOf: movedPage, encoding: .utf8), "Intro.\nLine one: new.\nEnd.\n")

        XCTAssertEqual(journal.undoNewest(places: places), .undone(seq: 1))
        let pageBack: URL = root.appendingPathComponent(oldFolder + "/a.md")
        XCTAssertEqual(try String(contentsOf: pageBack, encoding: .utf8), "Intro.\nLine one: old.\nEnd.\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(newFolder).path))
        XCTAssertEqual(namesLeftBySwaps(under: root), [], "the Undo leaves nothing of its own")

        XCTAssertEqual(journal.redoNewest(places: places), .redone(seq: 1))
        XCTAssertEqual(try String(contentsOf: movedPage, encoding: .utf8), "Intro.\nLine one: new.\nEnd.\n")
        XCTAssertEqual(namesLeftBySwaps(under: root), [], "the Redo leaves nothing of its own")
    }

    /// Review 1 of U4b2-9, L1: an edit spelled with other capitals BELOW the
    /// move's `to` (`Renamed/Sub/a.md` where the disk has `sub`) is matched
    /// to the moved folder's listing by the same comparison, so the Undo of
    /// an untouched step goes back and the Redo comes again. FAILED before,
    /// when the override was looked up as spelled (changed since).
    func testAnEditSpelledWithOtherCapitalsBelowTheMovesToIsUndoneAndRedone() throws {
        let root: URL = scratchURL.appendingPathComponent("folder", isDirectory: true)
        let journal: UndoJournal = UndoJournal(folderURL: scratchURL.appendingPathComponent("undo", isDirectory: true))
        let places: UndoMemoryPlaces = UndoMemoryPlaces()
        let oldFolder: String = "courses/TST1O/media"
        let newFolder: String = "courses/TST1O/renamed"
        try UndoContractReplay.write("Intro.\nLine one: old.\nEnd.\n", to: oldFolder + "/sub/a.md", in: root)
        try UndoContractReplay.write("B\n", to: oldFolder + "/b.md", in: root)
        let listingSha: String = try XCTUnwrap(UndoTreeReading.read(at: root.appendingPathComponent(oldFolder)).listingSha)
        let move: UndoOp = UndoOp.moveFolder(from: oldFolder, to: newFolder, listingSha: listingSha)
        let edit: UndoOp = UndoOp.replaceText(
            path: "courses/TST1O/Renamed/Sub/a.md", before: "old", after: "new", contextBefore: "Line one: ", contextAfter: ".\n"
        )
        let draft: UndoOpsDraft = UndoContractKinds.draft(ops: [move, edit], blobs: [], root: root, action: "renameFolder")
        XCTAssertEqual(JournaledWrite.perform(ops: draft, in: journal, mode: .live, places: places), .applied(seq: 1))

        XCTAssertEqual(journal.undoNewest(places: places), .undone(seq: 1))
        let pageBack: URL = root.appendingPathComponent(oldFolder + "/sub/a.md")
        XCTAssertEqual(try String(contentsOf: pageBack, encoding: .utf8), "Intro.\nLine one: old.\nEnd.\n")
        XCTAssertEqual(namesLeftBySwaps(under: root), [], "the Undo leaves nothing of its own")

        XCTAssertEqual(journal.redoNewest(places: places), .redone(seq: 1))
        let movedPage: URL = root.appendingPathComponent(newFolder + "/sub/a.md")
        XCTAssertEqual(try String(contentsOf: movedPage, encoding: .utf8), "Intro.\nLine one: new.\nEnd.\n")
        XCTAssertEqual(namesLeftBySwaps(under: root), [], "the Redo leaves nothing of its own")
    }

    /// Review 1 of U4b2-9, L3: under a capitalisation-only move, an edit is
    /// carried when its part at the folder is spelled as `to`, and not when
    /// it is spelled as `from`, whatever the capitals ABOVE the folder.
    /// FAILED before, when the whole path was compared as spelled.
    func testACaseOnlyMoveTellsItsSidesApartByTheFoldersOwnPart() {
        let move: UndoOp = UndoOp.moveFolder(from: "courses/TST1O/Media", to: "courses/TST1O/media", listingSha: String(repeating: "a", count: 64))
        let atFrom: UndoOp = UndoOp.replaceText(path: "courses/tst1o/Media/a.md", before: "old", after: "new", contextBefore: "", contextAfter: "")
        let atTo: UndoOp = UndoOp.replaceText(path: "courses/tst1o/media/a.md", before: "old", after: "new", contextBefore: "", contextAfter: "")
        XCTAssertFalse(UndoOp.moveCarries(move, atFrom), "named at the from spelling of the folder")
        XCTAssertTrue(UndoOp.moveCarries(move, atTo), "named at the to spelling of the folder")
    }

    /// Review 1 of U4b2-9, L2: the writer's own judgement of a carried
    /// place (`JournaledStep.placeOnDiskNow`, and the name it gives it,
    /// `namedPath`) is the one comparison: a place spelled `Renamed/a.md`
    /// under a planned move to `renamed` is read under `media` and named at
    /// `renamed`. FAILED before, when both compared as spelled.
    @MainActor
    func testTheWriterJudgesACarriedPlaceByTheOneComparison() throws {
        let root: URL = scratchURL.appendingPathComponent("folder", isDirectory: true)
        let course: URL = root.appendingPathComponent("courses/TST1O", isDirectory: true)
        try UndoContractReplay.write("A\n", to: "courses/TST1O/media/a.md", in: root)
        let step: JournaledStep = JournaledStep(
            courseCode: "TST1O", courseDirectory: course, section: nil, maker: UndoStepMaker.sheet("renameFolder")
        )
        XCTAssertTrue(step.moveFolder(course.appendingPathComponent("media"), to: course.appendingPathComponent("renamed")))
        let spelledOtherwise: URL = course.appendingPathComponent("Renamed/a.md")
        XCTAssertEqual(JournaledStep.key(of: step.placeOnDiskNow(spelledOtherwise)), JournaledStep.key(of: course.appendingPathComponent("media/a.md")))
        XCTAssertEqual(step.namedPath(of: spelledOtherwise, under: root), "courses/TST1O/renamed/a.md")
    }

    /// U4b2-10 (the part-two review of U4b, L3): the judgement alone. A
    /// moved folder holding folders made for a carried edit's files, with
    /// those files left out, holds the content: each made folder, holding
    /// nothing else, is left out with them (`made`, `made/one`, and
    /// `sub/deeper` inside the content's own `sub`), while a folder of the
    /// content's that holds a file (`sub`) or a folder (`keep`) besides a
    /// file left out stays. FAILED before, when the override kept every
    /// folder listed.
    func testAFolderMadeForALeftOutFileIsLeftOutOfTheMovesJudgement() throws {
        let folder: URL = scratchURL.appendingPathComponent("renamed", isDirectory: true)
        try UndoContractReplay.write("A\n", to: "a.md", in: folder)
        try UndoContractReplay.write("B\n", to: "sub/b.md", in: folder)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("keep/empty"), withIntermediateDirectories: true)
        let listingSha: String = try XCTUnwrap(UndoTreeReading.read(at: folder).listingSha)
        try UndoContractReplay.write("X\n", to: "sub/deeper/x.md", in: folder)
        try UndoContractReplay.write("X\n", to: "keep/x.md", in: folder)
        try UndoContractReplay.write("X\n", to: "made/one/x.md", in: folder)
        let move: UndoOp = UndoOp.moveFolder(from: "media", to: "renamed", listingSha: listingSha)
        let leftOut: [String: UndoItem] = ["Sub/deeper/x.md": .absent, "keep/x.md": .absent, "made/one/x.md": .absent]

        let reading = UndoMoveSide.readNamingFoldersLeftOut(move, at: folder, overriding: leftOut)
        XCTAssertEqual(reading.side, .holdsTheContent)
        XCTAssertEqual(reading.foldersLeftOut, ["made/one", "sub/deeper", "made"], "deepest first, as the disk spells them")
        XCTAssertEqual(UndoMoveSide.read(move, at: folder, overriding: leftOut), .holdsTheContent)
    }

    /// U4b2-10: an empty folder the teacher put inside the made folder is
    /// never left out, so the made folder is not either: changed since.
    func testAFolderPutInsideTheMadeFolderKeepsItInTheJudgement() throws {
        let folder: URL = scratchURL.appendingPathComponent("renamed", isDirectory: true)
        try UndoContractReplay.write("A\n", to: "a.md", in: folder)
        let listingSha: String = try XCTUnwrap(UndoTreeReading.read(at: folder).listingSha)
        try UndoContractReplay.write("X\n", to: "sub/x.md", in: folder)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub/mine"), withIntermediateDirectories: true)
        let move: UndoOp = UndoOp.moveFolder(from: "media", to: "renamed", listingSha: listingSha)

        let reading = UndoMoveSide.readNamingFoldersLeftOut(move, at: folder, overriding: ["sub/x.md": .absent])
        XCTAssertEqual(reading.side, .holdsSomethingElse)
        XCTAssertEqual(reading.foldersLeftOut, [])
    }

    /// U4b2-10: a moved folder that held an empty folder of its own, in
    /// which a carried edit then made a file, holds the content once the
    /// file is left out; that folder is the content's, never left out (nor
    /// tidied away).
    func testAnEmptyFolderOfTheContentsOwnIsKeptInTheJudgement() throws {
        let folder: URL = scratchURL.appendingPathComponent("renamed", isDirectory: true)
        try UndoContractReplay.write("A\n", to: "a.md", in: folder)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let listingSha: String = try XCTUnwrap(UndoTreeReading.read(at: folder).listingSha)
        try UndoContractReplay.write("X\n", to: "sub/x.md", in: folder)
        let move: UndoOp = UndoOp.moveFolder(from: "media", to: "renamed", listingSha: listingSha)

        let reading = UndoMoveSide.readNamingFoldersLeftOut(move, at: folder, overriding: ["sub/x.md": .absent])
        XCTAssertEqual(reading.side, .holdsTheContent)
        XCTAssertEqual(reading.foldersLeftOut, [])
    }

    /// The one comparison itself: part by part, without regard to case,
    /// the rest spelled as the path spells it.
    func testThePartInsideAPlaceIsFoundWithoutRegardToCase() {
        XCTAssertEqual(UndoOp.partInside("courses/X/renamed", of: "courses/X/Renamed/a/b.md"), "a/b.md")
        XCTAssertEqual(UndoOp.partInside("courses/X/renamed", of: "courses/X/RENAMED"), "")
        XCTAssertNil(UndoOp.partInside("courses/X/renamed", of: "courses/X/renamedToo/a.md"))
        XCTAssertNil(UndoOp.partInside("courses/X/renamed", of: "courses/X"))
        XCTAssertEqual(UndoOp.partInside("/tmp/w/Media", of: "/tmp/w/media/.plantoir-undo-1-x"), ".plantoir-undo-1-x")
    }

    /// Every name a swap leaves beside a page (`UndoSwap.stagedMarker`)
    /// anywhere under `root`.
    func namesLeftBySwaps(under root: URL) -> [String] {
        var found: [String] = []
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            return found
        }
        while let inside = walker.nextObject() as? String {
            if (inside as NSString).lastPathComponent.contains(UndoSwap.stagedMarker) {
                found.append(inside)
            }
        }
        return found
    }

    /// A move is one rename that never replaces: with something already at
    /// the destination it refuses and both stay as they were.
    func testAMoveNeverReplacesWhatIsAtItsDestination() throws {
        let from: URL = scratchURL.appendingPathComponent("a.json")
        let to: URL = scratchURL.appendingPathComponent("b.json")
        try Data("a".utf8).write(to: from)
        try Data("b".utf8).write(to: to)
        XCTAssertFalse(UndoSwap.renameExclusively(from, onto: to))
        XCTAssertEqual(try Data(contentsOf: from), Data("a".utf8))
        XCTAssertEqual(try Data(contentsOf: to), Data("b".utf8))
    }

    /// The hard review of U2b, LOW a (probe F): an editJSON changes only
    /// the bytes of the value at its key path; every other byte of the file
    /// (spacing, key order, 1.50, an escaped slash, a key written twice
    /// elsewhere) stays as it was. FAILED on c1c0624e5, which rewrote the
    /// whole file.
    func testAJSONMemberIsChangedByItsOwnBytesAlone() throws {
        let original: String = "{\n    \"zeta\": 1.50,\n    \"alpha\": \"a\\/b \\u00e9\",\n    \"dup\": 1,\n    \"dup\": 2,\n    \"school_year\": \"2026-2027\"\n}\n"
        let op: UndoOp = UndoOp.editJSON(path: "c.json", keyPath: ["school_year"], before: .string("2025-2026"), after: .string("2026-2027"))
        let moved: UndoItem = try XCTUnwrap(UndoJSONMember.moved(op, from: .file(Data(original.utf8)), direction: .backward))
        let text: String = String(decoding: try XCTUnwrap(moved.data), as: UTF8.self)
        XCTAssertEqual(text, original.replacingOccurrences(of: "\"2026-2027\"", with: "\"2025-2026\""))
    }

    /// A member added goes after the last one, spaced as that one is; a
    /// member taken out takes its own comma; nothing else moves.
    func testAJSONMemberAddedAndTakenOutTouchesOnlyItsOwnBytes() throws {
        let original: String = "{\n  \"a\" : 1,\n  \"b\" : 0.10\n}\n"
        let added: UndoOp = UndoOp.editJSON(path: "c.json", keyPath: ["c"], before: nil, after: .string("x"))
        let withIt: UndoItem = try XCTUnwrap(UndoJSONMember.moved(added, from: .file(Data(original.utf8)), direction: .forward))
        let addedText: String = String(decoding: try XCTUnwrap(withIt.data), as: UTF8.self)
        XCTAssertEqual(addedText, "{\n  \"a\" : 1,\n  \"b\" : 0.10,\n  \"c\" : \"x\"\n}\n")
        let back: UndoItem = try XCTUnwrap(UndoJSONMember.moved(added, from: withIt, direction: .backward))
        XCTAssertEqual(String(decoding: try XCTUnwrap(back.data), as: UTF8.self), original)
        let first: UndoOp = UndoOp.editJSON(path: "c.json", keyPath: ["a"], before: nil, after: .number(1))
        let without: UndoItem = try XCTUnwrap(UndoJSONMember.moved(first, from: .file(Data(original.utf8)), direction: .backward))
        XCTAssertEqual(String(decoding: try XCTUnwrap(without.data), as: UTF8.self), "{\n  \"b\" : 0.10\n}\n")
    }

    /// The key written twice on the path: refused, never a guess.
    func testAJSONKeyWrittenTwiceOnThePathIsRefused() throws {
        let original: String = "{\"school_year\": \"2026-2027\", \"school_year\": \"2026-2027\"}\n"
        let op: UndoOp = UndoOp.editJSON(path: "c.json", keyPath: ["school_year"], before: .string("2025-2026"), after: .string("2026-2027"))
        XCTAssertNil(UndoJSONMember.moved(op, from: .file(Data(original.utf8)), direction: .backward))
    }

    /// A folder taken out by an undo is renamed aside, never deleted, until
    /// every change of the step has gone in: a later change refused (a file
    /// in use) puts it back whole.
    func testAFolderTakenOutComesBackWhenALaterSwapIsRefused() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let folder: URL = root.appendingPathComponent("made", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("A\n".utf8).write(to: folder.appendingPathComponent("a.md"))
        try Data("B\n".utf8).write(to: folder.appendingPathComponent("sub/b.md"))
        try Data("old\n".utf8).write(to: root.appendingPathComponent("page.md"))
        guard case .tree(let listing, _) = UndoTreeReading.read(at: folder) else {
            return XCTFail("the folder could not be listed")
        }
        let targets: [UndoSwapTarget] = [
            UndoSwapTarget(url: folder, relativePath: "made", change: .takeTree(listingSha: listing.sha)),
            UndoSwapTarget(url: root.appendingPathComponent("page.md"), relativePath: "page.md", expected: Data("old\n".utf8), replacement: Data("new\n".utf8)),
        ]
        UndoKillPoints.fileInUseAtSwap = { index in index == 1 }
        defer {
            UndoKillPoints.fileInUseAtSwap = nil
        }
        XCTAssertEqual(UndoSwap.swap(targets, label: "9-undo"), .refused(.fileIsInUse(path: "page.md")))
        XCTAssertEqual(UndoTreeReading.read(at: folder).listingSha, listing.sha)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("page.md")), Data("old\n".utf8))
        XCTAssertEqual(UndoContractKinds.stagedLeftovers(in: root), [])
    }

    /// A folder taken out whose `-orig` name another Mac's list or an
    /// earlier list already holds is set aside under the next free name and
    /// the take-out goes in; the folder under the taken name is never
    /// touched (the first review of U3c, LOW 3). MUST FAIL with the old
    /// `isAFolderSetAside(asideURL)` refusal, which answered fileIsInUse for
    /// good.
    func testAFolderTakenOutGoesAsideUnderTheNextFreeName() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let folder: URL = root.appendingPathComponent("made", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("A\n".utf8).write(to: folder.appendingPathComponent("a.md"))
        guard case .tree(let listing, _) = UndoTreeReading.read(at: folder) else {
            return XCTFail("the folder could not be listed")
        }
        let foreign: URL = UndoSwap.besideURL(for: folder, label: "9-undo", role: "orig")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        try Data("Another list's folder.\n".utf8).write(to: foreign.appendingPathComponent("theirs.md"))
        let targets: [UndoSwapTarget] = [
            UndoSwapTarget(url: folder, relativePath: "made", change: .takeTree(listingSha: listing.sha)),
        ]
        XCTAssertEqual(UndoSwap.swap(targets, label: "9-undo", root: root), .swapped)
        XCTAssertEqual(UndoTreeReading.read(at: folder), .absent, "the folder was not taken out")
        XCTAssertEqual(try Data(contentsOf: foreign.appendingPathComponent("theirs.md")), Data("Another list's folder.\n".utf8))
        XCTAssertEqual(UndoContractKinds.stagedLeftovers(in: root), [foreign.lastPathComponent, foreign.lastPathComponent + "/theirs.md"])
    }

    /// A file that appears at the name a swap chose for a kept original, in
    /// the instant after the name was found free, is never overwritten or
    /// removed: the original is kept under the next free name and the swap
    /// goes in (the first review of U3c, LOW 4). Both ways a kept original
    /// is made are proved: a hard link, and the copy a volume without links
    /// falls back to (`keep`, reached here by making the link refuse as
    /// such a volume does). MUST FAIL with `copyfile` without
    /// `COPYFILE_EXCL` and the name not tried again.
    func testAFileThatAppearsAtTheKeptNameIsNeverOverwrittenOrRemoved() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let page: URL = root.appendingPathComponent("page.md")
        try Data("old\n".utf8).write(to: page)
        let theirs: Data = Data("What another Mac kept.\n".utf8)

        // The copy a volume without hard links falls back to refuses a name
        // that is taken and leaves what is there whole.
        let taken: URL = root.appendingPathComponent(".taken")
        try theirs.write(to: taken)
        XCTAssertEqual(UndoSwap.keepByCopying(page, as: taken), EEXIST)
        XCTAssertEqual(try Data(contentsOf: taken), theirs)
        try FileManager.default.removeItem(at: taken)

        // The swap: a file appears at its chosen name after the name was
        // found free; the original goes under the next free name.
        var placedAt: URL? = nil
        UndoKillPoints.beforeKeepingTheOriginal = { _, url in
            if placedAt == nil {
                try? theirs.write(to: url)
                placedAt = url
            }
        }
        defer {
            UndoKillPoints.beforeKeepingTheOriginal = nil
        }
        let targets: [UndoSwapTarget] = [
            UndoSwapTarget(url: page, relativePath: "page.md", expected: Data("old\n".utf8), replacement: Data("new\n".utf8)),
        ]
        XCTAssertEqual(UndoSwap.swap(targets, label: "9-undo", root: root), .swapped)
        XCTAssertEqual(try Data(contentsOf: page), Data("new\n".utf8))
        let placed: URL = try XCTUnwrap(placedAt)
        XCTAssertEqual(try Data(contentsOf: placed), theirs, "the file that appeared was overwritten or removed")
        XCTAssertEqual(UndoContractKinds.stagedLeftovers(in: root).count, 1, "\(UndoContractKinds.stagedLeftovers(in: root))")
    }

    /// A process that died with a teacher's folder renamed aside (a tree
    /// taken out) never has that folder deleted by recovery's tidying: it
    /// is put back where it was, so it is judged as the work found it, even
    /// when the list's copy of its content is gone. MUST FAIL with the
    /// tidying of U1, which removed every staged item it found.
    func testAFolderSetAsideByADeadProcessIsPutBackNeverDeleted() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let folder: URL = root.appendingPathComponent("made", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("kept\n".utf8).write(to: folder.appendingPathComponent("a.md"))
        guard case .tree(let listing, _) = UndoTreeReading.read(at: folder) else {
            return XCTFail("no listing")
        }
        let aside: URL = UndoSwap.besideURL(for: folder, label: "5-undo", role: "orig")
        XCTAssertTrue(UndoSwap.renameExclusively(folder, onto: aside))

        XCTAssertTrue(UndoSwap.tidyLeftovers(label: "5-undo", beside: [folder], asideListings: [folder.standardizedFileURL.path: listing.sha]))

        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("a.md")), Data("kept\n".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path))
    }

    /// Russell's ruling of 2026-11-19: when something now holds its place,
    /// the folder set aside is renamed to a visible name beside it, whole,
    /// never merged or overwritten, and the trail is told before the
    /// rename. FAILED on 5c55a7d7d, which left it hidden for good.
    func testAFolderSetAsideIsKeptUnderAVisibleNameWhenItsPlaceIsTaken() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let folder: URL = root.appendingPathComponent("made", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("kept\n".utf8).write(to: folder.appendingPathComponent("a.md"))
        let aside: URL = UndoSwap.besideURL(for: folder, label: "5-undo", role: "orig")
        XCTAssertTrue(UndoSwap.renameExclusively(folder, onto: aside))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("other\n".utf8).write(to: folder.appendingPathComponent("other.md"))

        var found: [UndoAsideFolder] = []
        var asideWhenTold: Bool = false
        XCTAssertTrue(UndoSwap.tidyLeftovers(label: "5-undo", beside: [folder], onAside: { told in
            found.append(told)
            asideWhenTold = FileManager.default.fileExists(atPath: aside.path)
        }))

        let kept: URL = root.appendingPathComponent("made (kept by Undo)")
        XCTAssertEqual(try Data(contentsOf: kept.appendingPathComponent("a.md")), Data("kept\n".utf8))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("other.md")), Data("other\n".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.keptAs?.lastPathComponent, "made (kept by Undo)")
        XCTAssertTrue(asideWhenTold, "the trail is told before the rename")
        XCTAssertEqual(UndoContractKinds.stagedLeftovers(in: root), [])
    }

    /// And when that visible name is taken too, the next number is used,
    /// never the taken one.
    func testAVisibleNameThatIsTakenIsNeverUsed() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let folder: URL = root.appendingPathComponent("made", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("kept\n".utf8).write(to: folder.appendingPathComponent("a.md"))
        let aside: URL = UndoSwap.besideURL(for: folder, label: "5-undo", role: "orig")
        XCTAssertTrue(UndoSwap.renameExclusively(folder, onto: aside))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let taken: URL = root.appendingPathComponent("made (kept by Undo)")
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: true)
        try Data("earlier\n".utf8).write(to: taken.appendingPathComponent("e.md"))

        XCTAssertTrue(UndoSwap.tidyLeftovers(label: "5-undo", beside: [folder]))

        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("made (kept by Undo 2)/a.md")), Data("kept\n".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: taken.path), ["e.md"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path))
    }

    /// The fourth review of U2b, LOW 3: a place that cannot be read now is
    /// not "something else holds it". The folder is left as it is, nothing
    /// is said, and a later try looks again. FAILED on 5c55a7d7d, which
    /// said something else held the place.
    func testAFolderWhosePlaceCannotBeReadIsLeftForALaterTry() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let parent: URL = root.appendingPathComponent("unit", isDirectory: true)
        let folder: URL = parent.appendingPathComponent("made", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("kept\n".utf8).write(to: folder.appendingPathComponent("a.md"))
        let aside: URL = UndoSwap.besideURL(for: folder, label: "5-undo", role: "orig")
        XCTAssertTrue(UndoSwap.renameExclusively(folder, onto: aside))
        // Something unreadable now holds its place: a folder that cannot be listed.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        guard UndoTreeReading.read(at: folder) == .cannotRead else {
            throw XCTSkip("this account can read a folder with no permissions")
        }

        var found: [UndoAsideFolder] = []
        XCTAssertFalse(UndoSwap.tidyLeftovers(label: "5-undo", beside: [folder], onAside: { told in found.append(told) }))

        XCTAssertEqual(found, [], "nothing untrue is said")
        XCTAssertTrue(FileManager.default.fileExists(atPath: aside.appendingPathComponent("a.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent("made (kept by Undo)").path))
    }

    /// The fourth review of U2b, MEDIUM: a folder a swap took out is renamed
    /// to its `-gone` name before it is deleted, so a delete cut short is
    /// finished by recovery's tidying, never put back half empty. FAILED on
    /// 5c55a7d7d, which deleted the `-orig` folder in place.
    func testAFolderWhoseDeleteIsCutShortIsFinishedNeverPutBack() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let folder: URL = root.appendingPathComponent("made", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("A\n".utf8).write(to: folder.appendingPathComponent("a.md"))
        try Data("B\n".utf8).write(to: folder.appendingPathComponent("sub/b.md"))
        guard case .tree(let listing, _) = UndoTreeReading.read(at: folder) else {
            return XCTFail("the folder could not be listed")
        }
        let targets: [UndoSwapTarget] = [
            UndoSwapTarget(url: folder, relativePath: "made", change: .takeTree(listingSha: listing.sha)),
        ]
        var named: [String] = []
        UndoKillPoints.hook = { point in
            if point == .whileDeletingAFolder {
                // As a recursive delete that died part way would leave it.
                if let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) {
                    named = names
                    for name in names where name.hasSuffix("-gone") {
                        try? FileManager.default.removeItem(at: root.appendingPathComponent(name).appendingPathComponent("a.md"))
                    }
                }
                return true
            }
            return false
        }
        defer {
            UndoKillPoints.hook = nil
        }
        XCTAssertEqual(UndoSwap.swap(targets, label: "9-apply"), .stoppedByATest)
        UndoKillPoints.hook = nil
        XCTAssertEqual(named, [".made.plantoir-undo-9-apply-gone"])

        XCTAssertTrue(UndoSwap.tidyLeftovers(label: "9-apply", beside: [folder], asideListings: [folder.standardizedFileURL.path: listing.sha]))

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "never put back half deleted")
        XCTAssertEqual(UndoContractKinds.stagedLeftovers(in: root), [])
    }

    /// The director's rule after U2b's third review (probe D), replacing
    /// "keep a changed folder aside": a folder set aside is the teacher's
    /// own, and goes back in its place whenever that place is free, changed
    /// or not; recovery then finds it in the way. FAILED on 1d0d5c2dd, which
    /// left it hidden for good.
    func testAChangedAsideFolderGoesBackInItsFreePlace() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let folder: URL = root.appendingPathComponent("made", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("one\n".utf8).write(to: folder.appendingPathComponent("a.md"))
        guard case .tree(let listing, _) = UndoTreeReading.read(at: folder) else {
            return XCTFail("no listing")
        }
        let aside: URL = UndoSwap.besideURL(for: folder, label: "5-redo", role: "orig")
        XCTAssertTrue(UndoSwap.renameExclusively(folder, onto: aside))
        try Data("half\n".utf8).write(to: aside.appendingPathComponent("stray.md"))

        var found: [UndoAsideFolder] = []
        XCTAssertTrue(UndoSwap.tidyLeftovers(label: "5-redo", beside: [folder], asideListings: [folder.standardizedFileURL.path: listing.sha], onAside: { aside in found.append(aside) }))

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("stray.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path))
        XCTAssertEqual(found.first?.putBack, true)
        XCTAssertEqual(found.first?.matched, false)
    }

    /// MEDIUM 3 (probe D): a recovery's own aside folder is never given a
    /// visible working name. FAILED on c1c0624e5, which renamed it to
    /// `made.plantoir-undo-5-apply-recover-orig`.
    func testARecoverysAsideFolderIsNeverGivenAVisibleName() throws {
        let root: URL = scratchURL.appendingPathComponent("wf3", isDirectory: true)
        let folder: URL = root.appendingPathComponent("made", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("kept\n".utf8).write(to: folder.appendingPathComponent("a.md"))
        guard case .tree(let listing, _) = UndoTreeReading.read(at: folder) else {
            return XCTFail("no listing")
        }
        let aside: URL = UndoSwap.besideURL(for: folder, label: "5-apply-recover", role: "orig")
        XCTAssertTrue(UndoSwap.renameExclusively(folder, onto: aside))

        _ = UndoSwap.tidyLeftovers(label: "5-apply", beside: [folder], asideListings: [folder.standardizedFileURL.path: listing.sha])

        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(names, ["made"], "put back in its own place, under its own name")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("a.md")), Data("kept\n".utf8))
    }

    /// The fourth review of U2b, LOW 6: nothing is STAGED through a link
    /// that leaves the working folder, even when the plan was made before
    /// the link. Stopped just before the first swap, the swap would have
    /// left its staged file outside. FAILS with the staging check taken out
    /// (it answers stoppedByATest, a staged file in the outside folder).
    func testNothingIsStagedThroughALinkThatLeavesTheWorkingFolder() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let outside: URL = scratchURL.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("old\n".utf8).write(to: outside.appendingPathComponent("page.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        let targets: [UndoSwapTarget] = [
            UndoSwapTarget(url: root.appendingPathComponent("linked/page.md"), relativePath: "linked/page.md", expected: Data("old\n".utf8), replacement: Data("new\n".utf8)),
        ]
        UndoKillPoints.hook = { point in point == .beforeSwap(0) }
        defer {
            UndoKillPoints.hook = nil
        }

        XCTAssertEqual(UndoSwap.swap(targets, label: "7-apply", root: root), .refused(.changedSince(firstPath: "linked/page.md", others: 0)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), ["page.md"])
    }

    /// LOW 6: recovery's tidying never removes a staged-looking file through
    /// a link that leaves the working folder. FAILS with the tidy's check
    /// taken out (the outside file is deleted).
    func testTheTidyingNeverReachesThroughALinkOutside() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let outside: URL = scratchURL.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile: URL = outside.appendingPathComponent(".page.md.plantoir-undo-7-apply-new")
        try Data("not the list's\n".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)

        _ = UndoSwap.tidyLeftovers(label: "7-apply", beside: [root.appendingPathComponent("linked/page.md")], root: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    /// LOW 6: a re-derivation never runs a maintainer on a place through a
    /// link that leaves the working folder. FAILS with the re-derivation's
    /// check taken out (the runner is called).
    func testARederivationNeverRunsThroughALinkOutside() async throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let outside: URL = scratchURL.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        let calls: UndoRunnerCalls = UndoRunnerCalls()
        UndoMaintainers.register("containmentTestMaintainer") { op, _ in
            calls.note(op.path ?? "")
        }
        defer {
            UndoMaintainers.forget("containmentTestMaintainer")
        }
        let inside: UndoOp = UndoOp.recompute(path: "index.md", maintainer: "containmentTestMaintainer", section: 1)
        let throughTheLink: UndoOp = UndoOp.recompute(path: "linked/index.md", maintainer: "containmentTestMaintainer", section: 1)

        await UndoMaintainers.rederive([throughTheLink, inside], root: root)

        XCTAssertEqual(calls.paths, ["index.md"])
    }

    /// The director's ruling on U2b's review: a page that cannot be read
    /// just now is "cannot tell", never changed since. Undo is refused
    /// without clearing the list, and works once the page can be read.
    /// FAILED before the ruling, when the read failure counted as a hand
    /// edit and cleared the list (UndoItem.read gave notAFile).
    func testAPageThatCannotBeReadNowIsRefusedWithoutClearingTheList() throws {
        let made = try UndoContractReplay.scratch(under: scratchURL, named: "unreadable")
        let root: URL = made.root
        let path: String = "courses/TST1O/page.md"
        try UndoContractReplay.write("---\ntitle: Day\npublish: false\n---\nBody.\n", to: path, in: root)
        let journal: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        let changes: [UndoFileChange] = UndoContractReplay.changes(setting: [(path: path, key: "publish", line: "publish: true")], in: root)
        XCTAssertEqual(JournaledWrite.perform(UndoContractReplay.draft(changes: changes, root: root, action: "publishPages"), in: journal, mode: .live), .applied(seq: 1))
        let url: URL = root.appendingPathComponent(path)
        XCTAssertEqual(chmod(url.path, 0), 0)

        let refused: UndoOutcome = journal.undoNewest(resolveRoot: { _ in root })
        _ = chmod(url.path, 0o644)

        XCTAssertEqual(refused, .refused(.cannotTellNow(path: path), clearedTheList: false))
        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }), .undone(seq: 1))
    }

    /// The hard review of U2b, MEDIUM 5: the app's OWN runner (on the main
    /// actor) can be registered and is awaited after an Undo, outside the
    /// list's lock: the landing page follows the newest class.
    @MainActor
    func testTheAppsOwnFrontPageRunnerIsRegisteredAndRunAfterAnUndo() async throws {
        let made = try AssistFixture.makeRunner()
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "one", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-10", body: "two", in: made.course)
        let indexURL: URL = SectionIndexPointer.indexURL(forSection: 1, in: made.course)
        try "---\ntitle: Section 1\ncreated: 2026-08-01T09:00:00.000-0400\npublish: true\n---\n# Most Recent Class\n![[Unit 1, Day 1]]\n".write(to: indexURL, atomically: true, encoding: .utf8)
        let root: URL = made.course.directoryURL.deletingLastPathComponent().deletingLastPathComponent()
        let indexPath: String = try XCTUnwrap(UndoFolderPlaces.relativePath(of: indexURL, under: root))
        let notes: String = "courses/\(made.course.code)/notes.md"
        try UndoContractReplay.write("Line one: old.\n", to: notes, in: root)
        let ops: [UndoOp] = [
            UndoOp.replaceText(path: notes, before: "old", after: "new", contextBefore: "Line one: ", contextAfter: ".\n"),
            UndoOp.recompute(path: indexPath, maintainer: "sectionFrontPage", section: 1),
        ]
        let journal: UndoJournal = UndoJournal(folderURL: scratchURL.appendingPathComponent("undo", isDirectory: true))
        UndoMaintainers.registerTheAppsFrontPage()
        XCTAssertEqual(JournaledWrite.perform(ops: UndoContractKinds.draft(ops: ops, blobs: [], root: root, action: "editPage"), in: journal, mode: .live), .applied(seq: 1))

        let outcome: UndoOutcome = await journal.undoNewestAndRederive(resolveRoot: { _ in root })

        XCTAssertEqual(outcome, .undone(seq: 1))
        let index: String = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(index.contains("![[Unit 1, Day 2]]"), index)
    }

    /// Without a runner for its maintainer, a step holding a `recompute` is
    /// not available: it is never undone with its re-derivation skipped
    /// (the hard review of U2b, LOW d: Undo itself is asked, not only
    /// `canRun`).
    func testAStepWhoseMaintainerHasNoRunnerIsNotAvailable() throws {
        let made = try UndoContractReplay.scratch(under: scratchURL, named: "norunner")
        let root: URL = made.root
        let notes: String = "courses/TST1O/notes.md"
        try UndoContractReplay.write("Line one: old.\n", to: notes, in: root)
        let ops: [UndoOp] = [
            UndoOp.replaceText(path: notes, before: "old", after: "new", contextBefore: "Line one: ", contextAfter: ".\n"),
            UndoOp.recompute(path: "courses/TST1O/section1/index.md", maintainer: "sectionFrontPage", section: 1),
        ]
        let journal: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        XCTAssertEqual(JournaledWrite.perform(ops: UndoContractKinds.draft(ops: ops, blobs: [], root: root, action: "editPage"), in: journal, mode: .live), .applied(seq: 1))
        UndoMaintainers.forget("sectionFrontPage")
        XCTAssertFalse(UndoMaintainers.canRun(ops))

        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }), .notAvailable)

        UndoContractReplay.registerTheFrontPageMaintainer()
        XCTAssertTrue(UndoMaintainers.canRun(ops))
        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }), .undone(seq: 1))
    }

    /// The second hard review of U2b, LOW: called from the main actor, the
    /// async entry points do the journal's work (the lock's wait, the check,
    /// the swaps) OFF it (`@concurrent`; the project builds with approachable
    /// concurrency, where a plain nonisolated async function would stay on
    /// the caller's actor).
    @MainActor
    func testTheJournalsWorkRunsOffTheMainActorWhenCalledFromIt() async throws {
        let made = try UndoContractReplay.scratch(under: scratchURL, named: "offmain")
        let root: URL = made.root
        try UndoContractReplay.write("Line one: old.\n", to: "courses/TST1O/notes.md", in: root)
        let op: UndoOp = UndoOp.replaceText(path: "courses/TST1O/notes.md", before: "old", after: "new", contextBefore: "Line one: ", contextAfter: ".\n")
        let journal: UndoJournal = UndoJournal(folderURL: made.journalFolder)
        XCTAssertEqual(JournaledWrite.perform(ops: UndoContractKinds.draft(ops: [op], blobs: [], root: root, action: "editPage"), in: journal, mode: .live), .applied(seq: 1))
        let seenOnMain: UndoMainThreadFlag = UndoMainThreadFlag()
        UndoKillPoints.hook = { point in
            if point == .afterTheCheck {
                seenOnMain.record(Thread.isMainThread)
            }
            return false
        }
        defer {
            UndoKillPoints.hook = nil
        }

        let outcome: UndoOutcome = await journal.undoNewestAndRederive(resolveRoot: { _ in root })

        XCTAssertEqual(outcome, .undone(seq: 1))
        XCTAssertEqual(seenOnMain.value, false, "the check ran on the main thread")
    }
}

/// Whether a hook saw the main thread, safe to set from any thread.
final class UndoMainThreadFlag: @unchecked Sendable {

    // MARK: - Stored properties

    private var seen: Bool? = nil

    private let guardLock: NSLock = NSLock()

    // MARK: - Computed properties

    var value: Bool? {
        guardLock.lock()
        defer {
            guardLock.unlock()
        }
        return seen
    }

    // MARK: - Functions

    func record(_ onMain: Bool) {
        guardLock.lock()
        seen = onMain
        guardLock.unlock()
    }
}

/// What a test runner was called with, from whichever actor it runs on.
final class UndoRunnerCalls: @unchecked Sendable {

    // MARK: - Stored properties

    private let guardLock: NSLock = NSLock()

    private var notedPaths: [String] = []

    // MARK: - Computed properties

    var paths: [String] {
        guardLock.lock()
        defer {
            guardLock.unlock()
        }
        return notedPaths
    }

    // MARK: - Functions

    func note(_ path: String) {
        guardLock.lock()
        notedPaths.append(path)
        guardLock.unlock()
    }
}
