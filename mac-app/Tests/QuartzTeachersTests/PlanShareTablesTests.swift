import AppKit
import XCTest
@testable import QuartzTeachers

/// The two tables before a share of unit plans (#833) and the dialogs
/// beside them (#834), against the contract (contracts/shared-rules.json →
/// unitPlanning.share: wordsForTheTables, filterCases, countCases,
/// startingPlace, rememberedChoices, warningSheet, changePasswordCases,
/// theVerbIsShare). The shared Python's half is
/// scripts/test_unit_plan_site.py and test_share_plan.py.
@MainActor
final class PlanShareTablesTests: XCTestCase {

    // MARK: - Stored properties

    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-share-tables-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Functions

    private static func share() throws -> [String: Any] {
        let contracts: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts", isDirectory: true)
        let data: Data = try Data(contentsOf: contracts.appendingPathComponent("shared-rules.json"))
        let rules: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let planning: [String: Any] = try XCTUnwrap(rules["unitPlanning"] as? [String: Any])
        return try XCTUnwrap(planning["share"] as? [String: Any])
    }

    private static func section(_ key: String) throws -> [String: Any] {
        return try XCTUnwrap(try share()[key] as? [String: Any])
    }

    private static func cases(_ key: String) throws -> [[String: Any]] {
        return try XCTUnwrap(try section(key)["cases"] as? [[String: Any]])
    }

    /// A row as the launcher would print it.
    private static func document(
        _ place: String,
        unit: String = "unit",
        unitOrder: Int = 0,
        answerKey: String? = nil,
        movable: Bool = true,
        start: PlanShareTable = .shared
    ) -> PlanShareDocument {
        let name: String = String(place.split(separator: "/").last ?? "")
        return PlanShareDocument(
            place: place, name: name, unit: unit, unitOrder: unitOrder, folder: "pdfs",
            kind: name.hasSuffix(".txt") ? "Text" : "PDF", answerKey: answerKey, movable: movable, start: start
        )
    }

    private static func model(_ documents: [PlanShareDocument], isProtected: Bool = false) -> PlanShareTablesModel {
        var lists: PlanShareLists = PlanShareLists()
        lists.year = 2026
        lists.isProtected = isProtected
        lists.documents = documents
        lists.isComplete = true
        return PlanShareTablesModel(lists: lists)
    }

    private static func names(_ documents: [PlanShareDocument]) -> [String] {
        var result: [String] = []
        for document in documents {
            result.append(document.name)
        }
        return result
    }

    // MARK: - Tests: the contract's words and rules

    func testEveryTableWordIsTheContractsOwn() throws {
        var words: [String: String] = [:]
        for (key, value) in try PlanShareTablesTests.section("wordsForTheTables") where key != "rule" {
            words[key] = value as? String
        }
        XCTAssertEqual(Set(words.keys), Set(PlanShareTableWording.byKey.keys))
        for (key, value) in PlanShareTableWording.byKey {
            XCTAssertEqual(words[key], value, key)
        }
    }

    /// theVerbIsShare (Russell, 2026-11-13): no sentence a teacher reads
    /// about sharing plans says deploy or publish.
    func testNoSentenceAboutSharingPlansSaysDeployOrPublish() {
        var sentences: [String: String] = PlanSharingWording.byKey
        for (key, value) in PlanShareTableWording.byKey {
            sentences["tables." + key] = value
        }
        sentences["listsSheetTitle"] = PlanSharingWording.listsSheetTitle
        sentences["listsByName"] = PlanSharingWording.listsByName
        for (key, value) in sentences {
            for word in ["deploy", "publish"] {
                XCTAssertFalse(value.lowercased().contains(word), "\(key) says \(word)")
            }
        }
    }

    func testEveryFilterCase() throws {
        let section: [String: Any] = try PlanShareTablesTests.section("filterCases")
        var documents: [PlanShareDocument] = []
        for row in try XCTUnwrap(section["documents"] as? [[String: Any]]) {
            documents.append(PlanShareDocument(
                place: try XCTUnwrap(row["place"] as? String),
                name: try XCTUnwrap(row["name"] as? String),
                unit: try XCTUnwrap(row["unit"] as? String),
                unitOrder: 0,
                folder: "",
                kind: try XCTUnwrap(row["kind"] as? String),
                answerKey: row["answerKey"] as? String,
                movable: true,
                start: .shared
            ))
        }
        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            var matched: [String] = []
            for document in documents where PlanShareTablesModel.matches(
                document,
                query: try XCTUnwrap(testCase["query"] as? String),
                unit: testCase["unit"] as? String,
                keysOnly: testCase["keysOnly"] as? Bool ?? false
            ) {
                matched.append(document.name)
            }
            XCTAssertEqual(matched, testCase["matches"] as? [String], "\(testCase)")
        }
    }

    func testEveryCountCase() throws {
        let section: [String: Any] = try PlanShareTablesTests.section("countCases")
        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let table: PlanShareTable = try XCTUnwrap(PlanShareTable(rawValue: try XCTUnwrap(testCase["table"] as? String)))
            let header: String = PlanShareTablesModel.header(
                for: table,
                shown: try XCTUnwrap(testCase["shown"] as? Int),
                total: try XCTUnwrap(testCase["total"] as? Int)
            )
            XCTAssertEqual(header, testCase["header"] as? String, "\(testCase)")
        }
        for testCase in try XCTUnwrap(section["shareCountsCases"] as? [[String: Any]]) {
            XCTAssertEqual(
                PlanShareTablesModel.shareCounts(
                    shared: try XCTUnwrap(testCase["shared"] as? Int),
                    heldBack: try XCTUnwrap(testCase["heldBack"] as? Int)
                ),
                testCase["sentence"] as? String
            )
        }
    }

    func testEveryStartingPlaceCase() throws {
        for testCase in try PlanShareTablesTests.cases("startingPlace") {
            let movable: Bool = (testCase["class"] as? String) == "document"
            let answerKey: String? = testCase["answerKey"] as? String
            let isProtected: Bool = try XCTUnwrap(testCase["protected"] as? Bool)
            var remembered: PlanShareTable?
            if let word = testCase["remembered"] as? String {
                remembered = PlanShareTable(rawValue: word)
            }
            let start: PlanShareTable = PlanShareDocument.startingPlace(
                movable: movable,
                answerKey: answerKey,
                isProtected: isProtected,
                answerKeysTicked: try XCTUnwrap(testCase["tick"] as? Bool),
                remembered: remembered
            )
            XCTAssertEqual(start.rawValue, testCase["start"] as? String, "\(testCase)")
            let document: PlanShareDocument = PlanShareTablesTests.document(
                "u/x.pdf", answerKey: answerKey, movable: movable, start: start
            )
            XCTAssertEqual(document.mark, testCase["mark"] as? String, "\(testCase)")
            XCTAssertEqual(document.warns(in: start, isProtected: isProtected), testCase["warns"] as? Bool, "\(testCase)")
        }
    }

    /// rememberedChoices: what the app writes when Share is pressed.
    func testEveryRememberedChoiceCase() throws {
        for testCase in try PlanShareTablesTests.cases("rememberedChoices") {
            let before: [String: String] = testCase["before"] as? [String: String] ?? [:]
            var documents: [PlanShareDocument] = []
            for place in try XCTUnwrap(testCase["listed"] as? [String]) {
                var start: PlanShareTable = .shared
                if let earlier = before[place], let table = PlanShareTable(rawValue: earlier) {
                    start = table
                }
                documents.append(PlanShareTablesTests.document(place, start: start))
            }
            let model: PlanShareTablesModel = PlanShareTablesTests.model(documents)
            for (place, word) in try XCTUnwrap(testCase["moved"] as? [String: String]) {
                model.places[place] = PlanShareTable(rawValue: word)
            }
            XCTAssertEqual(model.choicesToWrite(previous: before), testCase["after"] as? [String: String], "\(testCase)")
        }
    }

    // MARK: - Tests: a filter changes what is shown, never what is shared

    func testAFilteredOutDocumentKeepsItsPlaceAndTheCountsSayAll() {
        let model: PlanShareTablesModel = PlanShareTablesTests.model([
            PlanShareTablesTests.document("unit/pdfs/Quiz 1.pdf"),
            PlanShareTablesTests.document("unit/pdfs/Lab.pdf"),
            PlanShareTablesTests.document("unit/Answer Keys/Quiz 1 Key.pdf", answerKey: "folder", start: .notShared),
        ])
        model.query = "quiz"
        XCTAssertEqual(PlanShareTablesTests.names(model.documents(in: .shared)), ["Quiz 1.pdf"])
        XCTAssertEqual(model.header(for: .shared), "Shared (1 of 2)")
        XCTAssertEqual(model.places["unit/pdfs/Lab.pdf"], .shared, "hidden, and still shared")
        XCTAssertEqual(model.shareCountsSentence, "2 document(s) will be shared and 1 held back.")
        model.query = ""
        XCTAssertEqual(model.header(for: .shared), "Shared (2)")
    }

    func testAMoveActsOnlyOnSelectedRowsThatAreShowing() {
        let model: PlanShareTablesModel = PlanShareTablesTests.model([
            PlanShareTablesTests.document("unit/pdfs/Quiz 1.pdf"),
            PlanShareTablesTests.document("unit/pdfs/Lab.pdf"),
        ])
        model.selection[.shared] = ["unit/pdfs/Quiz 1.pdf", "unit/pdfs/Lab.pdf"]
        model.query = "lab"
        XCTAssertEqual(model.visibleSelection(in: .shared), ["unit/pdfs/Lab.pdf"])
        XCTAssertEqual(model.move(model.visibleSelection(in: .shared), to: .notShared), 1)
        XCTAssertEqual(model.places["unit/pdfs/Lab.pdf"], .notShared)
        XCTAssertEqual(model.places["unit/pdfs/Quiz 1.pdf"], .shared, "a hidden selected row did not move")
        // A hidden row named directly does not move either.
        XCTAssertEqual(model.move(["unit/pdfs/Quiz 1.pdf"], to: .notShared), 0)
        XCTAssertEqual(model.lastAnnouncement, "1 moved to Not shared.")
    }

    func testAFileThatCannotBeSharedNeverMoves() {
        let model: PlanShareTablesModel = PlanShareTablesTests.model([
            PlanShareTablesTests.document("unit/Lesson 3.docx", movable: false, start: .notShared),
        ])
        XCTAssertEqual(model.move(["unit/Lesson 3.docx"], to: .shared), 0)
        XCTAssertEqual(model.note(for: model.lists.documents[0]), PlanShareTableWording.noteCannotShare)
    }

    func testAnAnswerKeyInSharedInAnOpenShareIsMarked() {
        let key: PlanShareDocument = PlanShareTablesTests.document("unit/pdfs/Quiz 1 - Solutions.pdf", answerKey: "hint", start: .notShared)
        let open: PlanShareTablesModel = PlanShareTablesTests.model([key])
        XCTAssertEqual(open.note(for: key), PlanShareTableWording.noteMayBe)
        open.move([key.place], to: .shared)
        XCTAssertEqual(open.note(for: key), PlanShareTableWording.noteOpenKey)
        XCTAssertEqual(open.answerKeysInShared, 1)
        let protected: PlanShareTablesModel = PlanShareTablesTests.model([key], isProtected: true)
        protected.move([key.place], to: .shared)
        XCTAssertEqual(protected.note(for: key), PlanShareTableWording.noteMayBe)
    }

    func testEachTableSortsOnItsOwnAndStartsByUnitThenName() {
        let model: PlanShareTablesModel = PlanShareTablesTests.model([
            PlanShareTablesTests.document("b/pdfs/Zebra.pdf", unit: "b", unitOrder: 0),
            PlanShareTablesTests.document("a/pdfs/Apple.pdf", unit: "a", unitOrder: 1),
            PlanShareTablesTests.document("b/pdfs/Bee.pdf", unit: "b", unitOrder: 0),
            PlanShareTablesTests.document("a/pdfs/Key.pdf", unit: "a", unitOrder: 1, start: .notShared),
        ])
        XCTAssertEqual(PlanShareTablesTests.names(model.documents(in: .shared)), ["Bee.pdf", "Zebra.pdf", "Apple.pdf"],
                       "unit b comes first in the list of plans")
        model.sort[.shared] = [PlanShareTablesModel.SortKey(column: .name, ascending: false)]
        XCTAssertEqual(PlanShareTablesTests.names(model.documents(in: .shared)), ["Zebra.pdf", "Bee.pdf", "Apple.pdf"])
        XCTAssertEqual(model.sort[.notShared]?.first?.column, .unit, "sorting one table leaves the other alone")
        XCTAssertEqual(model.units, ["b", "a"])
    }

    // MARK: - Tests: drag and drop between two real tables

    /// Several selected rows dragged from Shared land in Not shared; a row
    /// that cannot be moved is not dragged; a table does not take its own.
    func testDraggingSeveralRowsToTheOtherTableMovesThemAll() throws {
        let model: PlanShareTablesModel = PlanShareTablesTests.model([
            PlanShareTablesTests.document("unit/pdfs/A.pdf"),
            PlanShareTablesTests.document("unit/pdfs/B.pdf"),
            PlanShareTablesTests.document("unit/pdfs/C.pdf"),
            PlanShareTablesTests.document("unit/Notes.docx", movable: false, start: .notShared),
        ])
        let shared: PlanShareDocumentTable.Coordinator = PlanShareDocumentTable.Coordinator(model: model, table: .shared)
        let sharedTable: NSTableView = PlanShareDocumentTable.makeTable(coordinator: shared)
        shared.tableView = sharedTable
        shared.show(rows: model.documents(in: .shared), selected: [], header: model.header(for: .shared))
        let held: PlanShareDocumentTable.Coordinator = PlanShareDocumentTable.Coordinator(model: model, table: .notShared)
        let heldTable: NSTableView = PlanShareDocumentTable.makeTable(coordinator: held)
        held.tableView = heldTable
        held.show(rows: model.documents(in: .notShared), selected: [], header: model.header(for: .notShared))

        XCTAssertEqual(sharedTable.numberOfColumns, 5)
        XCTAssertTrue(sharedTable.allowsMultipleSelection)
        XCTAssertTrue(sharedTable.usesAlternatingRowBackgroundColors)
        XCTAssertNil(held.tableView(heldTable, pasteboardWriterForRow: 0), "a file that cannot be shared is not dragged")

        let pasteboard: NSPasteboard = NSPasteboard(name: NSPasteboard.Name("plan-share-test-\(UUID().uuidString)"))
        defer {
            pasteboard.releaseGlobally()
        }
        pasteboard.clearContents()
        var writers: [any NSPasteboardWriting] = []
        for row in [0, 2] {
            writers.append(try XCTUnwrap(shared.tableView(sharedTable, pasteboardWriterForRow: row)))
        }
        pasteboard.writeObjects(writers)
        let places: Set<String> = PlanShareDocumentTable.Coordinator.places(on: pasteboard)
        XCTAssertEqual(places, ["unit/pdfs/A.pdf", "unit/pdfs/C.pdf"])
        XCTAssertTrue(PlanShareDocumentTable.Coordinator.isFromAnotherTable(sharedTable, than: heldTable))
        XCTAssertFalse(PlanShareDocumentTable.Coordinator.isFromAnotherTable(heldTable, than: heldTable))
        XCTAssertTrue(held.drop(places))
        XCTAssertEqual(model.places["unit/pdfs/A.pdf"], .notShared)
        XCTAssertEqual(model.places["unit/pdfs/C.pdf"], .notShared)
        XCTAssertEqual(model.places["unit/pdfs/B.pdf"], .shared)
        XCTAssertEqual(model.lastAnnouncement, "2 moved to Not shared.")
    }

    func testAClickOnAColumnHeaderSortsThatTable() {
        let model: PlanShareTablesModel = PlanShareTablesTests.model([PlanShareTablesTests.document("unit/pdfs/A.pdf")])
        let coordinator: PlanShareDocumentTable.Coordinator = PlanShareDocumentTable.Coordinator(model: model, table: .shared)
        let table: NSTableView = PlanShareDocumentTable.makeTable(coordinator: coordinator)
        coordinator.tableView = table
        XCTAssertEqual(table.sortDescriptors.first?.key, "unit", "by unit, then name, at first")
        table.sortDescriptors = [NSSortDescriptor(key: "kind", ascending: false)]
        XCTAssertEqual(model.sort[.shared], [PlanShareTablesModel.SortKey(column: .kind, ascending: false)])
    }

    // MARK: - Tests: the choices reach the year's marker

    func testWritingTheChoicesKeepsEveryOtherKeyOfTheMarker() throws {
        let marker: URL = scratchFolderURL.appendingPathComponent(".cloudflare_sites/plans-2026.json")
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"name": "x", "address": "https://x.pages.dev/", "state": "shared", "newPasswordWaiting": true}"#
            .write(to: marker, atomically: true, encoding: .utf8)
        XCTAssertTrue(PlanSharing.writeChoices(["unit/pdfs/A.pdf": "notShared"], to: marker))
        let object: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as? [String: Any])
        XCTAssertEqual(object["name"] as? String, "x")
        XCTAssertEqual(object["state"] as? String, "shared")
        XCTAssertEqual(object["newPasswordWaiting"] as? Bool, true)
        XCTAssertEqual(object["documents"] as? [String: String], ["unit/pdfs/A.pdf": "notShared"])
        XCTAssertEqual(PlanSharing.rememberedChoices(markerURL: marker), ["unit/pdfs/A.pdf": "notShared"])
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: marker.deletingLastPathComponent().path)
        XCTAssertEqual(names, ["plans-2026.json"], "no temporary file is left beside it")
        // A marker that does not exist yet is made with the choices alone,
        // and reads as not shared.
        let fresh: URL = scratchFolderURL.appendingPathComponent(".cloudflare_sites/plans-2027.json")
        XCTAssertTrue(PlanSharing.writeChoices([:], to: fresh))
        XCTAssertNil(PlanSharing.marker(from: try Data(contentsOf: fresh), year: 2027))
        // A marker that is not a JSON object is left alone.
        try "not json".write(to: marker, atomically: true, encoding: .utf8)
        XCTAssertFalse(PlanSharing.writeChoices([:], to: marker))
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "not json")
    }

    func testTheSheetsShareWritesTheChoicesBeforeTheYes() throws {
        let runner: ScriptRunner = ScriptRunner()
        runner.planShareCourseDirectory = scratchFolderURL
        let model: PlanShareTablesModel = PlanShareTablesTests.model([PlanShareTablesTests.document("unit/pdfs/A.pdf")])
        model.places["unit/pdfs/A.pdf"] = .notShared
        XCTAssertTrue(TaskProgressView.writeTheChoices(of: model, runner: runner))
        let marker: URL = PlanSharing.markerURL(courseDirectory: scratchFolderURL, year: 2026)
        XCTAssertEqual(PlanSharing.rememberedChoices(markerURL: marker), ["unit/pdfs/A.pdf": "notShared"])
        runner.planShareCourseDirectory = nil
        XCTAssertFalse(TaskProgressView.writeTheChoices(of: model, runner: runner), "no course folder: a no, never a yes")
    }

    // MARK: - Tests: the dialogs (#834)

    func testEveryWarningSheetCase() throws {
        for testCase in try PlanShareTablesTests.cases("warningSheet") {
            let rows: [FactsQuestionRow] = PlanSharing.warningRows(
                shared: try XCTUnwrap(testCase["shared"] as? Int),
                heldBack: try XCTUnwrap(testCase["heldBack"] as? Int),
                keysInShared: try XCTUnwrap(testCase["keysInShared"] as? Int)
            )
            var labels: [String] = []
            for row in rows {
                labels.append(row.label)
            }
            var expected: [String] = []
            for key in try XCTUnwrap(testCase["rows"] as? [String]) {
                expected.append(try XCTUnwrap(PlanSharingWording.byKey[key], key))
            }
            XCTAssertEqual(labels, expected, "\(testCase)")
            XCTAssertEqual(rows[1].value, testCase["documentsRow"] as? String)
            if let keys = testCase["answerKeysRow"] as? String {
                XCTAssertEqual(rows[2].value, keys)
            }
        }
    }

    func testTheNewPasswordDialogsEarlierYearsRowIsThereOnlyWithAnEarlierYear() {
        XCTAssertEqual(PlanSharing.newPasswordRows(earlierYearShared: false).count, 2)
        let rows: [FactsQuestionRow] = PlanSharing.newPasswordRows(earlierYearShared: true)
        XCTAssertEqual(rows.last, FactsQuestionRow(label: PlanSharingWording.earlierYearsLabel, value: PlanSharingWording.earlierYearsValue))
    }

    /// changePasswordCases, as the app reads them: the dialog after a save
    /// for plans with an address; the bar's line from the marker, so a
    /// relaunch keeps it, until a share proves the address.
    func testEveryChangePasswordCase() throws {
        for testCase in try PlanShareTablesTests.cases("changePasswordCases") {
            let event: String = try XCTUnwrap(testCase["event"] as? String)
            let hasAddress: Bool = try XCTUnwrap(testCase["markerHasAddress"] as? Bool)
            if event == "passwordSaved" {
                let outcome: String? = PlanSharing.passwordSavedOutcome(
                    in: "PLANTOIR_PLAN_PASSWORD_SAVED: SNC2D 2026 \(hasAddress ? "waiting" : "notShared")\n"
                )
                XCTAssertEqual(PlanShareRunner.owesTheNewPasswordDialog(choice: .changePassword, outcome: outcome),
                               testCase["dialog"] as? Bool, "\(testCase)")
                XCTAssertFalse(PlanShareRunner.owesTheNewPasswordDialog(choice: .shareAgain, outcome: outcome))
            }
            // What share_plan.py leaves in the marker after the event.
            var object: [String: Any] = ["address": "https://x.pages.dev/", "state": "shared"]
            switch event {
            case "passwordSaved", "relaunch", "shareFailed", "shareDeclined":
                if hasAddress {
                    object["newPasswordWaiting"] = true
                }
            default:
                break
            }
            if event == "shareFailed" {
                object["state"] = "sending"
            }
            let marker: PlanSharing.Marker? = hasAddress
                ? PlanSharing.marker(from: try JSONSerialization.data(withJSONObject: object), year: 2026)
                : nil
            XCTAssertEqual(PlanSharing.showsNewPasswordWaiting(marker), testCase["lineAfter"] as? Bool, "\(testCase)")
        }
    }
}
