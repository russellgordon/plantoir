import XCTest
@testable import QuartzTeachers

/// The three lows of U3c's third review, fixed in U4a (#899):
///
/// 1. With both contents gone and the list taking no new file, every Undo
///    and Redo kept another hidden full copy beside the page and nothing
///    removed them: now one kept copy per content per page.
/// 2. Show in Finder for a kept file that is gone brought Finder forward on
///    an unrelated window: now it says the file is no longer there.
/// 3. An Undo whose AFTER content was gone from the list deleted the only
///    copy, and the Redo came to `contentMissing`: now the outgoing bytes go
///    into the list, or are kept beside the page when it will not take them.
@MainActor
final class UndoKeptCopiesTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = FileManager.default.temporaryDirectory

    var listFolder: URL = FileManager.default.temporaryDirectory

    var readOnlyFolders: [URL] = []

    static let pagePath: String = "courses/TST1O/section1/p1.md"

    static let before: Data = Data("What the page held before.\n".utf8)

    static let after: Data = Data("What the step left in the page, a whole new text.\n".utf8)

    // MARK: - Setting up

    override func setUp() async throws {
        let unique: String = UUID().uuidString
        root = FileManager.default.temporaryDirectory.appendingPathComponent("undo-kept-\(unique)", isDirectory: true)
        listFolder = FileManager.default.temporaryDirectory.appendingPathComponent("undo-kept-list-\(unique)", isDirectory: true)
        let page: URL = root.appendingPathComponent(UndoKeptCopiesTests.pagePath)
        try FileManager.default.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
        try UndoKeptCopiesTests.before.write(to: page)
    }

    override func tearDown() async throws {
        for folder in readOnlyFolders {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        readOnlyFolders = []
        #if DEBUG
        FolderActions.showInFinderRecorder = nil
        FolderActions.goneRecorder = nil
        #endif
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: listFolder)
    }

    // MARK: - Helpers

    func journal() -> UndoJournal {
        return UndoJournal(folderURL: listFolder)
    }

    /// One whole-file step on p1: its content is two blobs.
    func makeTheStep() throws {
        let change: UndoFileChange = UndoFileChange(
            relativePath: UndoKeptCopiesTests.pagePath, before: UndoKeptCopiesTests.before, after: UndoKeptCopiesTests.after
        )
        let outcome: JournaledWriteOutcome = JournaledWrite.perform(
            UndoContractReplay.draft(changes: [change], root: root, action: "publishPages"), in: journal(), mode: .live
        )
        XCTAssertEqual(outcome, .applied(seq: 1))
        let ops: [UndoOp] = try XCTUnwrap(try journal().read().records[1]).step.ops
        XCTAssertEqual(ops.first?.knownKind, .writeFile)
    }

    /// Takes one blob out of the list; with `andTakesNoNewOne`, its folder
    /// then takes no new file.
    func removeBlob(_ data: Data, andTakesNoNewOne: Bool) throws {
        let blobURL: URL = journal().blobURL(sha: UndoHash.sha256(of: data))
        try FileManager.default.removeItem(at: blobURL)
        if andTakesNoNewOne {
            let folder: URL = blobURL.deletingLastPathComponent()
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
            readOnlyFolders.append(folder)
        }
    }

    /// Every hidden file beside p1.
    func keptBesideThePage() throws -> [String] {
        let folder: URL = root.appendingPathComponent(UndoKeptCopiesTests.pagePath).deletingLastPathComponent()
        var names: [String] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasPrefix(".p1.md") {
            names.append(name)
        }
        return names.sorted()
    }

    func pageNow() throws -> Data {
        return try Data(contentsOf: root.appendingPathComponent(UndoKeptCopiesTests.pagePath))
    }

    // MARK: - LOW 3: the only copy of the after content

    /// The after content gone from the list: the Undo puts the page back
    /// and writes what it took off into the list, so the Redo is made.
    /// MUST FAIL before the fix: the Redo came to `contentMissing`.
    func testAnUndoWhoseAfterContentIsGoneStoresItAndTheRedoIsMade() throws {
        try makeTheStep()
        try removeBlob(UndoKeptCopiesTests.after, andTakesNoNewOne: false)

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))
        XCTAssertEqual(try pageNow(), UndoKeptCopiesTests.before)
        XCTAssertEqual(try keptBesideThePage(), [], "the list holds it, so nothing is kept beside the page")
        XCTAssertEqual(journal().redoNewest(resolveRoot: { _ in self.root }), .redone(seq: 1))
        XCTAssertEqual(try pageNow(), UndoKeptCopiesTests.after)
    }

    /// The after content gone AND the list taking no new file: the Undo
    /// keeps what it took off beside the page, and the Redo is made from
    /// that kept file. MUST FAIL before the fix: the swap's tidy deleted
    /// the only copy.
    func testAnUndoWhoseAfterContentTheListWillNotTakeKeepsItAndTheRedoIsMade() throws {
        try makeTheStep()
        try removeBlob(UndoKeptCopiesTests.after, andTakesNoNewOne: true)

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))
        XCTAssertEqual(try keptBesideThePage().count, 1, "the only copy of the after content is kept beside the page")
        XCTAssertEqual(journal().redoNewest(resolveRoot: { _ in self.root }), .redone(seq: 1))
        XCTAssertEqual(try pageNow(), UndoKeptCopiesTests.after)
    }

    // MARK: - LOW 1: no pile of kept copies

    /// Both contents gone, the list taking no new file, a kept original of
    /// what p1 held before: seven moves each go, and leave at most ONE kept
    /// copy per content beside the page. MUST FAIL before the fix: seven
    /// moves left eight copies.
    func testUndoAndRedoAgainAndAgainKeepOneCopyPerContent() throws {
        try makeTheStep()
        let page: URL = root.appendingPathComponent(UndoKeptCopiesTests.pagePath)
        try UndoKeptCopiesTests.before.write(to: UndoSwap.besideURL(for: page, label: "1-apply", role: "orig"))
        try FileManager.default.removeItem(at: journal().contentFolderURL)
        try FileManager.default.createDirectory(at: journal().contentFolderURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: journal().contentFolderURL.path)
        readOnlyFolders.append(journal().contentFolderURL)

        var moves: Int = 0
        while moves < 7 {
            let outcome: UndoOutcome = moves % 2 == 0
                ? journal().undoNewest(resolveRoot: { _ in self.root })
                : journal().redoNewest(resolveRoot: { _ in self.root })
            XCTAssertEqual(UndoContractReplay.outcomeWord(outcome), moves % 2 == 0 ? "undone" : "redone", "move \(moves + 1)")
            moves += 1
        }
        XCTAssertEqual(try pageNow(), UndoKeptCopiesTests.before)
        let kept: [String] = try keptBesideThePage()
        XCTAssertLessThanOrEqual(kept.count, 2, "\(kept)")
        var contents: Set<Data> = []
        let folder: URL = page.deletingLastPathComponent()
        for name in kept {
            contents.insert(try Data(contentsOf: folder.appendingPathComponent(name)))
        }
        XCTAssertTrue(contents.contains(UndoKeptCopiesTests.after), "what the Redo needs is still kept")
        XCTAssertEqual(contents.count, kept.count, "one copy per content")
    }

    // MARK: - LOW 2: Show in Finder for a file that is gone

    /// A kept file that is no longer there is named, never asked of Finder;
    /// one that is there is shown. MUST FAIL before the fix: every file was
    /// handed to Finder unchecked.
    func testShowInFinderSaysAKeptFileIsGoneAndShowsOnlyWhatIsThere() throws {
        let folder: URL = root.appendingPathComponent(UndoKeptCopiesTests.pagePath).deletingLastPathComponent()
        let there: URL = folder.appendingPathComponent(".p1.md.plantoir-undo-1-apply-orig")
        try Data("kept".utf8).write(to: there)
        let gone: URL = folder.appendingPathComponent(".p1.md.plantoir-undo-1-undo-orig")
        #if DEBUG
        var shown: [[URL]] = []
        var said: [[String]] = []
        FolderActions.showInFinderRecorder = { files in shown.append(files) }
        FolderActions.goneRecorder = { names in said.append(names) }

        FolderActions.showInFinder(files: [gone])
        XCTAssertEqual(shown, [], "nothing is asked of Finder when the file is gone")
        XCTAssertEqual(said, [[".p1.md.plantoir-undo-1-undo-orig"]])

        FolderActions.showInFinder(files: [there, gone])
        XCTAssertEqual(shown, [[there]])
        #endif
        XCTAssertEqual(
            FrontPageWording.keptGone([gone.lastPathComponent]),
            "“.p1.md.plantoir-undo-1-undo-orig” is no longer there, so there is nothing to show."
        )
    }
}
