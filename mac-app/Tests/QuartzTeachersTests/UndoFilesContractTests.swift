import XCTest
@testable import QuartzTeachers

/// What Undo Last Change does with each file a change touched, and when the
/// change comes off the list (#555). Every row is read from
/// `contracts/assist-cases.json` → `undoFiles`, so Windows runs the same
/// rows against its own undo; nothing typed here could disagree with them.
///
/// The rows drive the real `AssistChangeHistory` against real files in a
/// temporary folder. MUST FAIL on the code before #555, where every
/// `alreadyBack` row came out left alone and the second press of the first
/// `presses` row kept the change on the list.
@MainActor
final class UndoFilesContractTests: XCTestCase {

    // MARK: - Stored properties

    private var folders: [URL] = []

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
        folders = []
        try await super.tearDown()
    }

    // MARK: - Tests

    /// Every `files` row: one saved file, one press, one verdict — and the
    /// disk afterwards holds BEFORE for a file put back, and is untouched
    /// otherwise.
    func testEveryFileRowGetsItsVerdict() throws {
        let rows: [[String: Any]] = try UndoFilesContractTests.family(key: "files")
        XCTAssertGreaterThanOrEqual(rows.count, 14, "files rows have gone missing")
        var verdictsSeen: Set<String> = []
        for row in rows {
            let name: String = try XCTUnwrap(row["name"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(name) has no stated reason")
            let expect: String = try XCTUnwrap(row["expect"] as? String, name)
            verdictsSeen.insert(expect)
            let folder: URL = try makeFolder()
            let fileURL: URL = folder.appendingPathComponent("page.md")
            let before: String? = row["before"] as? String
            let after: String? = row["after"] as? String
            try UndoFilesContractTests.lay(row, at: fileURL)
            let laidOut: Data? = UndoFilesContractTests.contents(of: fileURL)

            let file: AssistSavedFile = AssistSavedFile(fileURL: fileURL, before: before, after: after)
            XCTAssertEqual(AssistUndoVerdict.of(file).rawValue, expect, "\(name): verdict before the press")

            let history: AssistChangeHistory = AssistChangeHistory()
            history.record(UndoFilesContractTests.change(of: [file]))
            let result: AssistUndoResult = history.undo()
            var verdict: String = "leftAlone"
            if result.restored.contains(fileURL) {
                verdict = "putBack"
            } else if result.alreadyBack.contains(fileURL) {
                verdict = "alreadyBack"
            }
            XCTAssertEqual(verdict, expect, name)
            XCTAssertEqual(history.isEmpty, expect != "leftAlone", "\(name): whether the change came off the list")

            if expect == "putBack" {
                if let before {
                    XCTAssertEqual(try? String(contentsOf: fileURL, encoding: .utf8), before, "\(name): not put back")
                } else {
                    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "\(name): not removed")
                }
            } else {
                XCTAssertTrue(UndoFilesContractTests.isUntouched(fileURL, was: laidOut, row: row), "\(name): the file was changed")
            }
        }
        XCTAssertEqual(verdictsSeen, ["putBack", "alreadyBack", "leftAlone"], "a verdict has no row")
    }

    /// Every `presses` row: several files, Undo pressed step by step, with
    /// the counts, the change left on the list, the sentence and the trail
    /// ending each press must give.
    func testEveryPressRowEndsAsTheContractSays() throws {
        let rows: [[String: Any]] = try UndoFilesContractTests.family(key: "presses")
        XCTAssertGreaterThanOrEqual(rows.count, 3, "presses rows have gone missing")
        for row in rows {
            let name: String = try XCTUnwrap(row["name"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(name) has no stated reason")
            let folder: URL = try makeFolder()
            var saved: [AssistSavedFile] = []
            for fileRow in try XCTUnwrap(row["files"] as? [[String: Any]], name) {
                let fileName: String = try XCTUnwrap(fileRow["name"] as? String, name)
                let fileURL: URL = folder.appendingPathComponent(fileName)
                try UndoFilesContractTests.lay(fileRow, at: fileURL)
                saved.append(AssistSavedFile(
                    fileURL: fileURL, before: fileRow["before"] as? String, after: fileRow["after"] as? String
                ))
            }
            let history: AssistChangeHistory = AssistChangeHistory()
            history.record(UndoFilesContractTests.change(of: saved))

            let steps: [[String: Any]] = try XCTUnwrap(row["steps"] as? [[String: Any]], name)
            for (index, step) in steps.enumerated() {
                let label: String = "\(name), press \(index + 1)"
                if let edits = step["edit"] as? [String: Any] {
                    for (fileName, text) in edits {
                        let fileURL: URL = folder.appendingPathComponent(fileName)
                        if let text = text as? String {
                            try text.write(to: fileURL, atomically: true, encoding: .utf8)
                        } else {
                            try? FileManager.default.removeItem(at: fileURL)
                        }
                    }
                }
                let entriesBefore: Int = history.changes.count
                let result: AssistUndoResult = history.undo()
                XCTAssertEqual(result.restored.count, step["expectPutBack"] as? Int, "\(label): put back")
                XCTAssertEqual(result.alreadyBack.count, step["expectAlreadyBack"] as? Int, "\(label): already back")
                XCTAssertEqual(result.skipped.count, step["expectLeftAlone"] as? Int, "\(label): left alone")
                XCTAssertEqual(history.changes.count, step["expectEntriesLeft"] as? Int, "\(label): changes left")
                XCTAssertEqual(result.answer.rawValue, step["expectSentence"] as? String, "\(label): sentence")
                // The runner counts a write with no new undo entry exactly
                // when it answers undidPartly (`undoLastChange`); the Section
                // menu's ending is read from that and from the list moving.
                let ending: String = SectionVerbs.undoEnding(
                    undoListMoved: history.changes.count != entriesBefore,
                    wroteWithNoNewUndoEntry: result.answer == .undidPartly
                )
                XCTAssertEqual(ending, step["expectEnding"] as? String, "\(label): trail ending")
            }
        }
    }

    /// Each sentence a press can be answered with is a real `AssistWording`
    /// key in the generated contract, so a row cannot name one that does not
    /// exist on either platform.
    func testEverySentenceNamedIsAWordingKey() throws {
        let wordingFile: [String: Any] = try UndoFilesContractTests.contractFile(named: AssistContract.wordingFileName)
        let wording: [String: Any] = try XCTUnwrap(wordingFile["wording"] as? [String: Any])
        for answer in [AssistUndoAnswer.nothingToUndo, .couldNotUndo, .undid, .undidPartly] {
            XCTAssertNotNil(wording[answer.rawValue], "\(answer.rawValue) is not a wording key")
        }
    }

    // MARK: - Helpers

    private func makeFolder() throws -> URL {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UndoFiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        return folder
    }

    private static func change(of files: [AssistSavedFile]) -> AssistChange {
        return AssistChange(
            whatHappened: "published 2 pages", courseCode: "ICS3U", sectionNumber: 1,
            rebuildsThePreview: false, files: files
        )
    }

    /// Put at the path what the row says is there now.
    private static func lay(_ row: [String: Any], at fileURL: URL) throws {
        let kind: String? = row["currentKind"] as? String
        if kind == "folder" {
            try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
            return
        }
        if kind == "notUTF8" {
            try Data([0xFF, 0xFE, 0x00, 0xC3, 0x28]).write(to: fileURL)
            return
        }
        XCTAssertNil(kind, "unknown currentKind \(kind ?? "")")
        if let current = row["current"] as? String {
            try current.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private static func contents(of fileURL: URL) -> Data? {
        return try? Data(contentsOf: fileURL)
    }

    private static func isUntouched(_ fileURL: URL, was laidOut: Data?, row: [String: Any]) -> Bool {
        var isFolder: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isFolder)
        if (row["currentKind"] as? String) == "folder" {
            return exists && isFolder.boolValue
        }
        if laidOut == nil {
            return !exists
        }
        return contents(of: fileURL) == laidOut
    }

    private static func family(key: String) throws -> [[String: Any]] {
        let contract: [String: Any] = try contractFile(named: AssistContract.casesFileName)
        let family: [String: Any] = try XCTUnwrap(
            contract["undoFiles"] as? [String: Any], "contracts/assist-cases.json has no undoFiles"
        )
        XCTAssertNotNil(family["note"] as? String)
        return try XCTUnwrap(family[key] as? [[String: Any]], "undoFiles has no \(key)")
    }

    private static func contractFile(named name: String) throws -> [String: Any] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(
            contentsOf: repository.appendingPathComponent("contracts").appendingPathComponent(name)
        )
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
