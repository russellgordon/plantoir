import XCTest
@testable import QuartzTeachers

/// The journal core of #899 (piece U1), against the contract: the traces in
/// `contracts/undo-traces.json` and the cases in `shared-rules.json` → `undo`.
/// The work is done by `UndoContractReplay`, which the standalone harness
/// runs too; each test here asserts it found nothing wrong.
///
/// Everything happens in folders under the temporary directory: the lists
/// these tests make are their own, never the app's.
final class UndoJournalContractTests: XCTestCase {

    // MARK: - Stored properties

    var scratchURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Setting up

    override func setUp() {
        scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-contract-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        UndoKillPoints.hook = nil
        UndoKillPoints.fileInUseAtSwap = nil
        try? FileManager.default.removeItem(at: scratchURL)
    }

    // MARK: - Tests

    /// Every trace, through the door and the list. MUST FAIL on the code
    /// before #899 at the first `redo` of any trace: today's history
    /// (`AssistChangeHistory`) has no redo at all, and it has no list that
    /// outlives the runner, so no trace can even be expressed against it.
    func testEveryTraceReplaysAsTheContractSays() throws {
        let result: (traces: Int, calls: Int, failures: [String]) = try UndoContractReplay.replayTraces(under: scratchURL)
        XCTAssertEqual(result.traces, 20)
        XCTAssertGreaterThan(result.calls, 400)
        XCTAssertEqual(result.failures, [])
    }

    /// "Publish, edit the body, undo": MUST FAIL against today's whole-file
    /// compare, which is copied into `UndoContractReplay` as the reference
    /// (`AssistUndoVerdict.of`'s skip path) and says `leftAlone`; the line
    /// check says `canUndo` (ruling 4).
    func testABodyEditDoesNotStopTheLineBeingUndone() {
        let verdicts: (today: String, journal: String) = UndoContractReplay.publishEditBodyUndo()
        XCTAssertEqual(verdicts.today, "leftAlone", "the reference no longer says what today's code says")
        XCTAssertEqual(verdicts.journal, UndoCheckVerdict.canUndo.rawValue)
    }

    /// Today's verdict for the same page, asked of the real code, so the
    /// reference above cannot drift from it.
    @MainActor
    func testTheReferenceIsTodaysVerdict() throws {
        let url: URL = scratchURL.appendingPathComponent("page.md")
        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
        let before: String = "---\ntitle: Day\npublish: false\n---\nBody.\n"
        let after: String = "---\ntitle: Day\npublish: true\n---\nBody.\n"
        try (after + "Written in Obsidian since.\n").write(to: url, atomically: true, encoding: .utf8)
        let verdict: AssistUndoVerdict = AssistUndoVerdict.of(AssistSavedFile(fileURL: url, before: before, after: after))
        XCTAssertEqual(verdict, .leftAlone)
    }

    func testCheckCases() throws {
        let result: (cases: Int, failures: [String]) = try UndoContractReplay.runCheckCases(under: scratchURL)
        XCTAssertGreaterThanOrEqual(result.cases, 20)
        XCTAssertEqual(result.failures, [])
    }

    func testStackCases() throws {
        let result: (cases: Int, failures: [String]) = try UndoContractReplay.runStackCases(under: scratchURL)
        XCTAssertGreaterThanOrEqual(result.cases, 15)
        XCTAssertEqual(result.failures, [])
    }

    func testStepCases() throws {
        let result: (cases: Int, failures: [String]) = try UndoContractReplay.runStepCases(under: scratchURL)
        XCTAssertEqual(result.cases, 3)
        XCTAssertEqual(result.failures, [])
    }

    /// Every kill point: a process that stops there leaves the files before
    /// or after, never between. (The harness also kills real processes at
    /// the same points with SIGKILL.)
    func testRecoveryCases() throws {
        let result: (cases: Int, failures: [String]) = try UndoContractReplay.runRecoveryCases(under: scratchURL)
        XCTAssertEqual(result.cases, 15)
        XCTAssertEqual(result.failures, [])
    }

    func testATornLastLineIsIgnoredThenCutOff() throws {
        XCTAssertEqual(try UndoContractReplay.tornLastLine(under: scratchURL), [])
    }

    /// Live: refused before anything changes. Shadow: goes ahead, one trail line.
    func testAListThatCannotBeWritten() throws {
        XCTAssertEqual(try UndoContractReplay.unwritableList(under: scratchURL), [])
    }

    /// Two writers in one process, each with its own `UndoJournal` (so its
    /// own lock descriptor), 200 steps each at the same time. The two-PROCESS
    /// test is the harness's here and U7's in the app.
    func testTwoWritersFoldIntoOneList() async throws {
        let result: (steps: Int, failures: [String]) = try await UndoContractReplay.twoWritersInOneProcess(under: scratchURL, stepsEach: 200)
        XCTAssertEqual(result.steps, 400)
        XCTAssertEqual(result.failures, [])
    }

    // MARK: - The format

    /// The events the Swift fold knows are exactly the contract's.
    func testTheEventsAreTheFormats() throws {
        let formats: [String: Any] = try UndoContractReplay.contract("file-formats.json")
        let journal: [String: Any] = try XCTUnwrap(formats["undoJournal"] as? [String: Any])
        let events: [String: Any] = try XCTUnwrap(journal["events"] as? [String: Any])
        var contractEvents: [String] = []
        for (name, _) in events {
            contractEvents.append(name)
        }
        contractEvents.sort()
        var swiftEvents: [String] = []
        for kind in UndoEventKind.allCases {
            swiftEvents.append(kind.rawValue)
        }
        swiftEvents.sort()
        XCTAssertEqual(swiftEvents, contractEvents)
    }

    /// The clearing reasons are the contract's, in its order.
    func testTheClearReasonsAreTheContracts() throws {
        let block: [String: Any] = try UndoContractReplay.undoBlock()
        let reasons: [String] = try XCTUnwrap(block["clearReasons"] as? [String])
        var swiftReasons: [String] = []
        for reason in UndoClearing.allCases {
            swiftReasons.append(reason.rawValue)
        }
        XCTAssertEqual(swiftReasons, reasons)
    }

    /// A line is one JSON object with its keys sorted, ending in a line feed
    /// and holding none inside it, even when a page's text has many.
    func testALineIsOneSortedObject() throws {
        var op: UndoOp = UndoOp.editLine(path: "a.md", key: "tags", before: "tags:\n  - a", after: "tags:\n  - b", afterKey: nil, createdTheBlock: false)
        op.section = nil
        let step: UndoStep = UndoStep(
            seq: 7, madeAt: "2026-11-13T21:04:05Z",
            action: UndoAction(key: "publishPages", arguments: ["pageCount": "1"]),
            madeBy: "menu", workingFolder: UndoWorkingFolder(id: "X", pathAtTheTime: "/w"),
            course: "ICS3U", section: 1, actionClass: "A", holds: "section", ops: [op]
        )
        let data: Data = try UndoEventLine(seq: 7, event: .begin, step: step).encoded()
        for byte in data {
            XCTAssertNotEqual(byte, 0x0A)
        }
        let text: String = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\"event\":\"begin\",\"seq\":7,\"step\":{\"action\""), text)
        XCTAssertTrue(text.contains("\"class\":\"A\""), text)
        XCTAssertEqual(UndoEventLine.decoded(from: data)?.step, step)
    }

    /// The working folder's identifier is made once, exclusively, and read
    /// back the same.
    func testTheFolderIdentifierIsMadeOnce() throws {
        let root: URL = scratchURL.appendingPathComponent("wf", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertNil(FolderIdentityFile.existingIdentifier(forWorkingFolder: root))
        let first: String = try FolderIdentityFile.identifier(forWorkingFolder: root)
        let second: String = try FolderIdentityFile.identifier(forWorkingFolder: root)
        XCTAssertEqual(first, second)
        XCTAssertEqual(UndoReach.root(for: UndoWorkingFolder(id: first, pathAtTheTime: root.path)), root)
        XCTAssertNil(UndoReach.root(for: UndoWorkingFolder(id: UUID().uuidString, pathAtTheTime: root.path)))
    }
}
