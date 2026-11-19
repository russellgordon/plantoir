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
        let path: String = try XCTUnwrap(UndoShadowPublish.relativePath(of: indexURL, under: root))
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

    /// Setting one member writes the file in the app's own JSON form and
    /// keeps every other member, numbers as they were read.
    func testAJSONMemberKeepsItsNeighbours() throws {
        let original: Data = Data("{\"big\": 12345678901234, \"half\": 0.5, \"nested\": {\"list\": [1, \"two\", null]}, \"school_year\": \"2026-2027\"}\n".utf8)
        let op: UndoOp = UndoOp.editJSON(path: "c.json", keyPath: ["school_year"], before: .string("2025-2026"), after: .string("2026-2027"))
        let moved: UndoItem = try XCTUnwrap(UndoJSONMember.moved(op, from: .file(original), direction: .backward))
        let data: Data = try XCTUnwrap(moved.data)
        let object: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["school_year"] as? String, "2025-2026")
        XCTAssertEqual((object["big"] as? NSNumber)?.int64Value, 12_345_678_901_234)
        XCTAssertEqual((object["half"] as? NSNumber)?.doubleValue, 0.5)
        XCTAssertEqual(data.last, 0x0A)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"school_year\" : \"2025-2026\""))
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

    /// And when something now holds its place, the folder is left aside,
    /// still whole, rather than deleted.
    func testAFolderSetAsideIsLeftWhenItsPlaceIsTaken() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        let folder: URL = root.appendingPathComponent("made", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("kept\n".utf8).write(to: folder.appendingPathComponent("a.md"))
        let aside: URL = UndoSwap.besideURL(for: folder, label: "5-undo", role: "orig")
        XCTAssertTrue(UndoSwap.renameExclusively(folder, onto: aside))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertFalse(UndoSwap.tidyLeftovers(label: "5-undo", beside: [folder]))

        XCTAssertEqual(try Data(contentsOf: aside.appendingPathComponent("a.md")), Data("kept\n".utf8))
    }

    /// The hard review of U2b, MEDIUM 3 (probe E): an aside folder changed
    /// since it was set aside is never put in the teacher's place; it stays
    /// aside, hidden and whole. FAILED on c1c0624e5, which put it back.
    func testAChangedAsideFolderIsNeverPutInTheTeachersPlace() throws {
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

        XCTAssertFalse(UndoSwap.tidyLeftovers(label: "5-redo", beside: [folder], asideListings: [folder.standardizedFileURL.path: listing.sha]))

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: aside.appendingPathComponent("stray.md").path))
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

    /// Without a runner for its maintainer, a step holding a `recompute` is
    /// not available: it is never undone with its re-derivation skipped.
    func testAStepWhoseMaintainerHasNoRunnerIsNotAvailable() throws {
        UndoMaintainers.forget("sectionFrontPage")
        let ops: [UndoOp] = [UndoOp.recompute(path: "courses/X/section1/index.md", maintainer: "sectionFrontPage", section: 1)]
        XCTAssertFalse(UndoMaintainers.canRun(ops))
        UndoContractReplay.registerTheFrontPageMaintainer()
        XCTAssertTrue(UndoMaintainers.canRun(ops))
    }
}
