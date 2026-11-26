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

    /// The plan the app's own path follows, in every build: a gone file
    /// gets the alert with one OK button and is never handed to Finder;
    /// with every file there, no alert, and Finder selects them all (the
    /// U4a sweep: the test above reads only the recorder's branch). MUST
    /// FAIL with the gone file handed to Finder or the alert skipped.
    func testShowInFinderTheAppsPathAlertsForAGoneFileAndSelectsOnlyWhatIsThere() throws {
        let folder: URL = root.appendingPathComponent(UndoKeptCopiesTests.pagePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let there: URL = folder.appendingPathComponent(".p1.md.plantoir-undo-1-apply-orig")
        try Data("kept".utf8).write(to: there)
        let gone: URL = folder.appendingPathComponent(".p1.md.plantoir-undo-1-undo-orig")

        let mixed: FolderActions.ShowInFinderPlan = FolderActions.showInFinderPlan([there, gone])
        XCTAssertEqual(mixed.alertSentence, FrontPageWording.keptGone([gone.lastPathComponent]))
        XCTAssertEqual(mixed.alertButtons, ["OK"])
        XCTAssertEqual(mixed.selected, [there])

        let allThere: FolderActions.ShowInFinderPlan = FolderActions.showInFinderPlan([there])
        XCTAssertNil(allThere.alertSentence)
        XCTAssertEqual(allThere.alertButtons, [])
        XCTAssertEqual(allThere.selected, [there])

        let allGone: FolderActions.ShowInFinderPlan = FolderActions.showInFinderPlan([gone])
        XCTAssertEqual(allGone.selected, [])
        XCTAssertNotNil(allGone.alertSentence)
    }

    /// The U4a sweep, LOW 1: the after content gone from the list and the
    /// list taking no new file, the Undo puts the page back FROM THE LIST,
    /// so the line never says it was put back "from what was kept beside
    /// it". MUST FAIL with the sentence as it was (said whenever anything
    /// was kept).
    func testTheKeptLineSaysFromTheListWhenThePageCameFromTheList() throws {
        try makeTheStep()
        try removeBlob(UndoKeptCopiesTests.after, andTakesNoNewOne: true)
        var lines: [String] = []
        let hookBefore = UndoTrailHook.keptWhatItReplacedLine
        UndoTrailHook.keptWhatItReplacedLine = { course, section, isUndo, keptOriginals, keptOfWhatItHoldsNow, putBackFromAKeptOriginal in
            lines.append(UndoTrail.keptWhatItReplacedLine(
                course: course, section: section, isUndo: isUndo, keptOriginals: keptOriginals,
                keptOfWhatItHoldsNow: keptOfWhatItHoldsNow, putBackFromAKeptOriginal: putBackFromAKeptOriginal
            ))
        }
        defer {
            UndoTrailHook.keptWhatItReplacedLine = hookBefore
        }

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))

        XCTAssertEqual(lines.count, 1)
        let line: String = lines.first ?? ""
        XCTAssertFalse(line.contains("from what was kept beside it"), line)
        XCTAssertTrue(line.contains("Undo put back “p1.md”, but the list could not keep a copy"), line)
    }

    /// U4b part one's review, LOW 1: a step of two pages, p1 put back from
    /// the list (its outgoing bytes refused and kept) and p2 put back from
    /// its kept original (the list took its bytes). The line says "from what
    /// was kept beside it" of p2 only, so of no page it names here. MUST
    /// FAIL decided per step (said of p1 because p2 used a kept original).
    func testTheKeptLineIsDecidedPageByPage() throws {
        let secondPath: String = "courses/TST1O/section1/p2.md"
        let secondBefore: Data = Data("What the second page held before, its own words.\n".utf8)
        let secondAfter: Data = Data("What the step left in the second page.\n".utf8)
        let second: URL = root.appendingPathComponent(secondPath)
        try secondBefore.write(to: second)
        let changes: [UndoFileChange] = [
            UndoFileChange(relativePath: UndoKeptCopiesTests.pagePath, before: UndoKeptCopiesTests.before, after: UndoKeptCopiesTests.after),
            UndoFileChange(relativePath: secondPath, before: secondBefore, after: secondAfter),
        ]
        let outcome: JournaledWriteOutcome = JournaledWrite.perform(
            UndoContractReplay.draft(changes: changes, root: root, action: "publishPages"), in: journal(), mode: .live
        )
        XCTAssertEqual(outcome, .applied(seq: 1))
        // The two blobs that are taken away live in different folders of
        // the list, so sealing p1's leaves p2's free to take its bytes again.
        XCTAssertNotEqual(
            journal().blobURL(sha: UndoHash.sha256(of: UndoKeptCopiesTests.after)).deletingLastPathComponent(),
            journal().blobURL(sha: UndoHash.sha256(of: secondBefore)).deletingLastPathComponent()
        )
        try removeBlob(UndoKeptCopiesTests.after, andTakesNoNewOne: true)
        try removeBlob(secondBefore, andTakesNoNewOne: false)
        try secondBefore.write(to: second.deletingLastPathComponent().appendingPathComponent(".p2.md.plantoir-undo-1-apply-orig"))
        var lines: [String] = []
        let hookBefore = UndoTrailHook.keptWhatItReplacedLine
        UndoTrailHook.keptWhatItReplacedLine = { course, section, isUndo, keptOriginals, keptOfWhatItHoldsNow, putBackFromAKeptOriginal in
            lines.append(UndoTrail.keptWhatItReplacedLine(
                course: course, section: section, isUndo: isUndo, keptOriginals: keptOriginals,
                keptOfWhatItHoldsNow: keptOfWhatItHoldsNow, putBackFromAKeptOriginal: putBackFromAKeptOriginal
            ))
        }
        defer {
            UndoTrailHook.keptWhatItReplacedLine = hookBefore
        }

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))

        XCTAssertEqual(try Data(contentsOf: second), secondBefore, "p2 was put back from its kept original")
        XCTAssertEqual(lines.count, 1)
        let line: String = lines.first ?? ""
        XCTAssertFalse(line.contains("from what was kept beside it"), line)
        XCTAssertTrue(line.contains("Undo put back “p1.md”, but the list could not keep a copy"), line)
    }

    /// The same line built for a step whose pages came both ways names each
    /// the way it came back.
    func testTheKeptLineNamesEachPageTheWayItCameBack() {
        let line: String = UndoTrail.keptWhatItReplacedLine(
            course: "ICS3U", section: 1, isUndo: true,
            keptOriginals: [".A.md.plantoir-undo-4-undo-orig"], keptOfWhatItHoldsNow: [".B.md.plantoir-undo-3-apply-orig"],
            putBackFromAKeptOriginal: ["B.md"]
        )
        XCTAssertTrue(line.contains("Undo put back “A.md”, and put back “B.md” from what was kept beside it, but the list"), line)
    }

    // MARK: - U4b2-4: two pages with the same name

    /// Two pages named `index.md` in two sections, made in one step whose
    /// four contents are the same as `testTheKeptLineIsDecidedPageByPage`'s.
    /// Returns both pages' paths and what the second held before.
    func makeTheStepOnTwoPagesNamedIndex() throws -> (first: String, second: String, secondBefore: Data) {
        let firstPath: String = "courses/TST1O/section1/index.md"
        let secondPath: String = "courses/TST1O/section2/index.md"
        let secondBefore: Data = Data("What the second page held before, its own words.\n".utf8)
        let secondAfter: Data = Data("What the step left in the second page.\n".utf8)
        let first: URL = root.appendingPathComponent(firstPath)
        let second: URL = root.appendingPathComponent(secondPath)
        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try UndoKeptCopiesTests.before.write(to: first)
        try secondBefore.write(to: second)
        let changes: [UndoFileChange] = [
            UndoFileChange(relativePath: firstPath, before: UndoKeptCopiesTests.before, after: UndoKeptCopiesTests.after),
            UndoFileChange(relativePath: secondPath, before: secondBefore, after: secondAfter),
        ]
        let outcome: JournaledWriteOutcome = JournaledWrite.perform(
            UndoContractReplay.draft(changes: changes, root: root, action: "publishPages"), in: journal(), mode: .live
        )
        XCTAssertEqual(outcome, .applied(seq: 1))
        XCTAssertNotEqual(
            journal().blobURL(sha: UndoHash.sha256(of: UndoKeptCopiesTests.after)).deletingLastPathComponent(),
            journal().blobURL(sha: UndoHash.sha256(of: secondBefore)).deletingLastPathComponent()
        )
        return (firstPath, secondPath, secondBefore)
    }

    /// Every 'undo kept what it replaced' line written while `body` runs.
    func keptLines(during body: () -> Void) -> [String] {
        var lines: [String] = []
        let hookBefore = UndoTrailHook.keptWhatItReplacedLine
        UndoTrailHook.keptWhatItReplacedLine = { course, section, isUndo, keptOriginals, keptOfWhatItHoldsNow, putBackFromAKeptOriginal in
            lines.append(UndoTrail.keptWhatItReplacedLine(
                course: course, section: section, isUndo: isUndo, keptOriginals: keptOriginals,
                keptOfWhatItHoldsNow: keptOfWhatItHoldsNow, putBackFromAKeptOriginal: putBackFromAKeptOriginal
            ))
        }
        body()
        UndoTrailHook.keptWhatItReplacedLine = hookBefore
        return lines
    }

    /// The part-two review of U4b, LOW 4, through the real Undo: section1's
    /// `index.md` put back from the list (its outgoing bytes refused and
    /// kept), section2's `index.md` put back from its kept original (the
    /// list took its bytes, so nothing of it is named). The line never says
    /// section1's page came "from what was kept beside it". MUST FAIL keyed
    /// by file name (section2's `index.md` made both match).
    func testTheKeptLineTellsTwoPagesWithTheSameNameApart() throws {
        let step = try makeTheStepOnTwoPagesNamedIndex()
        try removeBlob(UndoKeptCopiesTests.after, andTakesNoNewOne: true)
        try removeBlob(step.secondBefore, andTakesNoNewOne: false)
        let second: URL = root.appendingPathComponent(step.second)
        try step.secondBefore.write(to: second.deletingLastPathComponent().appendingPathComponent(".index.md.plantoir-undo-1-apply-orig"))

        var outcome: UndoOutcome? = nil
        let lines: [String] = keptLines {
            outcome = journal().undoNewest(resolveRoot: { _ in self.root })
        }

        XCTAssertEqual(outcome, .undone(seq: 1))
        XCTAssertEqual(try Data(contentsOf: second), step.secondBefore, "section2's page was put back from its kept original")
        XCTAssertEqual(lines.count, 1)
        let line: String = lines.first ?? ""
        XCTAssertFalse(line.contains("from what was kept beside it"), line)
        XCTAssertTrue(line.contains("Undo put back “index.md”, but the list could not keep a copy"), line)
    }

    /// The same two pages, both named on the line: section2's kept original
    /// stays too, since the list would not take its bytes. Each is named by
    /// its path inside the course, since both are `index.md`, and each the
    /// way it came back. MUST FAIL keyed by file name (both said "from what
    /// was kept beside it").
    func testTheKeptLineNamesTwoPagesWithTheSameNameByTheirPaths() throws {
        let step = try makeTheStepOnTwoPagesNamedIndex()
        try removeBlob(UndoKeptCopiesTests.after, andTakesNoNewOne: true)
        try removeBlob(step.secondBefore, andTakesNoNewOne: true)
        let second: URL = root.appendingPathComponent(step.second)
        try step.secondBefore.write(to: second.deletingLastPathComponent().appendingPathComponent(".index.md.plantoir-undo-1-apply-orig"))

        var outcome: UndoOutcome? = nil
        let lines: [String] = keptLines {
            outcome = journal().undoNewest(resolveRoot: { _ in self.root })
        }

        XCTAssertEqual(outcome, .undone(seq: 1))
        XCTAssertEqual(try Data(contentsOf: second), step.secondBefore)
        XCTAssertEqual(lines.count, 1)
        let line: String = lines.first ?? ""
        XCTAssertTrue(
            line.contains("Undo put back “section1/index.md”, and put back “section2/index.md” from what was kept beside it, but the list"),
            line
        )
        XCTAssertTrue(line.contains("What “section1/index.md” held a moment before is kept beside it as the hidden file “.index.md.plantoir-undo-1-undo-orig”."), line)
        XCTAssertTrue(line.contains("What “section2/index.md” holds now is kept beside it as the hidden file “.index.md.plantoir-undo-1-apply-orig”."), line)
    }

    /// The line built from kept files given by their paths: two pages named
    /// `index.md`, one each way, each named by its path inside the course.
    /// MUST FAIL keyed by file name.
    func testTheKeptLineKeysPagesByTheirPlaceInTheWorkingFolder() {
        let line: String = UndoTrail.keptWhatItReplacedLine(
            course: "ICS3U", section: 1, isUndo: true,
            keptOriginals: ["courses/ICS3U/Section 1/.index.md.plantoir-undo-4-undo-orig"],
            keptOfWhatItHoldsNow: ["courses/ICS3U/Section 2/.index.md.plantoir-undo-3-apply-orig"],
            putBackFromAKeptOriginal: ["courses/ICS3U/Section 2/index.md"]
        )
        XCTAssertTrue(
            line.hasPrefix("ICS3U/1 · Undo put back “Section 1/index.md”, and put back “Section 2/index.md” from what was kept beside it, but the list"),
            line
        )
        XCTAssertTrue(line.contains("What “Section 1/index.md” held a moment before is kept beside it as the hidden file “.index.md.plantoir-undo-4-undo-orig”."), line)
        XCTAssertTrue(line.contains("What “Section 2/index.md” holds now is kept beside it as the hidden file “.index.md.plantoir-undo-3-apply-orig”."), line)
    }
}
