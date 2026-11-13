import Foundation
import Observation

/// The two tables before a share (#833), by the word the launcher's rows
/// and the year's marker use for each.
nonisolated enum PlanShareTable: String, CaseIterable {
    case shared
    case notShared
}

/// One row of the two tables before a share of unit plans (#833): a
/// document as `share_plan.py` listed it (unitPlanning.share.documents),
/// read from its `PLANTOIR_PLAN_LISTS_DOCUMENT:` line. Nothing here reads a
/// file: the row is what the launcher printed.
nonisolated struct PlanShareDocument: Equatable, Hashable {

    // MARK: - Stored properties

    /// Where the file is in the plan, and the row's identity.
    let place: String
    let name: String
    /// The unit folder, empty for a file that is in no unit.
    let unit: String
    /// The unit's place in the list of plans.
    let unitOrder: Int
    /// The folders between the unit and the name.
    let folder: String
    let kind: String
    /// folder (in the unit's Answer Keys folder), hint (its name looks like
    /// a key), or nil.
    let answerKey: String?
    /// False for a file of a kind no share takes: it stays in Not shared.
    let movable: Bool
    /// Where `share_plan.py` started it: the rule, or a remembered choice.
    let start: PlanShareTable

    // MARK: - Computed properties

    var isAnswerKey: Bool {
        return answerKey != nil
    }

    /// startingPlace.mark: what the Note column says beside the name.
    var mark: String? {
        if !movable {
            return "cannotShare"
        }
        if answerKey == "folder" {
            return "answerKey"
        }
        if answerKey == "hint" {
            return "mayBeAnswerKey"
        }
        return nil
    }

    /// The Unit column's words.
    var unitShown: String {
        return unit.isEmpty ? PlanShareTableWording.noUnit : unit
    }

    // MARK: - Functions

    /// A row from its marker line's JSON, or nil for anything else.
    static func from(json: String) -> PlanShareDocument? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let place = object["place"] as? String, !place.isEmpty,
              let name = object["name"] as? String,
              let start = object["start"] as? String,
              let table = PlanShareTable(rawValue: start) else {
            return nil
        }
        return PlanShareDocument(
            place: place,
            name: name,
            unit: object["unit"] as? String ?? "",
            unitOrder: object["unitOrder"] as? Int ?? 0,
            folder: object["folder"] as? String ?? "",
            kind: object["kind"] as? String ?? "",
            answerKey: object["answerKey"] as? String,
            movable: object["movable"] as? Bool ?? false,
            start: table
        )
    }

    /// startingPlace.warns: an answer key in Shared in a share with no
    /// password carries the warning symbol and words.
    func warns(in table: PlanShareTable, isProtected: Bool) -> Bool {
        return isAnswerKey && table == .shared && !isProtected
    }

    /// startingPlace: where a document starts, the same rule `share_plan.py`
    /// runs (the app shows the start the launcher printed; this is run
    /// against the contract's decision table so both suites hold it).
    static func startingPlace(
        movable: Bool,
        answerKey: String?,
        isProtected: Bool,
        answerKeysTicked: Bool,
        remembered: PlanShareTable?
    ) -> PlanShareTable {
        if !movable {
            return .notShared
        }
        if let remembered = remembered {
            return remembered
        }
        if answerKey != nil {
            return (isProtected || answerKeysTicked) ? .shared : .notShared
        }
        return .shared
    }
}

/// The two tables' words (contracts/shared-rules.json → unitPlanning.share
/// .wordsForTheTables), named by key; `PlanShareTablesTests` compares each.
nonisolated enum PlanShareTableWording {

    // MARK: - Stored properties

    static let sharedTable: String = "Shared ({count})"
    static let notSharedTable: String = "Not shared ({count})"
    static let countAll: String = "{n}"
    static let countFiltered: String = "{shown} of {total}"
    static let columnName: String = "Name"
    static let columnUnit: String = "Unit"
    static let columnFolder: String = "Folder"
    static let columnKind: String = "Kind"
    static let columnNote: String = "Note"
    static let noUnit: String = "Not in a unit"
    static let moveToNotShared: String = "Don't Share"
    static let moveToShared: String = "Share"
    static let moveToNotSharedHelp: String = "Move the selected documents to Not shared"
    static let moveToSharedHelp: String = "Move the selected documents to Shared"
    static let movedToNotShared: String = "{n} moved to Not shared."
    static let movedToShared: String = "{n} moved to Shared."
    static let searchPrompt: String = "Search Documents"
    static let unitPopup: String = "Unit"
    static let allUnits: String = "All Units"
    static let keysOnly: String = "Answer Keys Only"
    static let noteAnswerKey: String = "Answer key"
    static let noteMayBe: String = "May be an answer key"
    static let noteOpenKey: String = "Answer key, open to anyone with the address"
    static let noteCannotShare: String = "Plantoir shares PDFs, text files, pages and pictures, not files of this kind. Save it as a PDF to share it."
    static let ownFilesLine: String = "The plan's own pages, pictures, stylesheets and fonts ({n} files) always go and are not listed here."
    static let shareCounts: String = "{shared} document(s) will be shared and {heldBack} held back."
    static let emptyTable: String = "(none)"

    // MARK: - Computed properties

    static var byKey: [String: String] {
        return [
            "sharedTable": sharedTable,
            "notSharedTable": notSharedTable,
            "countAll": countAll,
            "countFiltered": countFiltered,
            "columnName": columnName,
            "columnUnit": columnUnit,
            "columnFolder": columnFolder,
            "columnKind": columnKind,
            "columnNote": columnNote,
            "noUnit": noUnit,
            "moveToNotShared": moveToNotShared,
            "moveToShared": moveToShared,
            "moveToNotSharedHelp": moveToNotSharedHelp,
            "moveToSharedHelp": moveToSharedHelp,
            "movedToNotShared": movedToNotShared,
            "movedToShared": movedToShared,
            "searchPrompt": searchPrompt,
            "unitPopup": unitPopup,
            "allUnits": allUnits,
            "keysOnly": keysOnly,
            "noteAnswerKey": noteAnswerKey,
            "noteMayBe": noteMayBe,
            "noteOpenKey": noteOpenKey,
            "noteCannotShare": noteCannotShare,
            "ownFilesLine": ownFilesLine,
            "shareCounts": shareCounts,
            "emptyTable": emptyTable,
        ]
    }
}

/// What the two tables show and hold (#833): where each document is now,
/// what the search field, the Unit popup and Answer Keys Only let through,
/// each table's own sort, and the moves. A filter changes what is SHOWN,
/// never what is shared (unitPlanning.share.filterCases): a hidden document
/// keeps its place, the headers count what is showing against the total,
/// the sentence by Share counts everything, and a move acts only on rows
/// that are both selected and showing.
@MainActor
@Observable
final class PlanShareTablesModel {

    // MARK: - Stored properties

    typealias Table = PlanShareTable

    /// One column a table can be sorted by.
    enum Column: String, CaseIterable {
        case name
        case unit
        case folder
        case kind
        case note
    }

    /// A sort: a column and its direction.
    struct SortKey: Equatable {
        let column: Column
        let ascending: Bool
    }

    let lists: PlanShareLists

    /// Where each document is now, by place.
    var places: [String: Table] = [:]

    /// The search field's text.
    var query: String = ""

    /// The Unit popup: nil for All Units.
    var unit: String?

    /// Answer Keys Only.
    var keysOnly: Bool = false

    /// The rows selected in each table, by place.
    var selection: [Table: Set<String>] = [.shared: [], .notShared: []]

    /// Each table's own sort; by unit in the plan's order, then by name.
    var sort: [Table: [SortKey]] = [
        .shared: [SortKey(column: .unit, ascending: true), SortKey(column: .name, ascending: true)],
        .notShared: [SortKey(column: .unit, ascending: true), SortKey(column: .name, ascending: true)],
    ]

    /// The last move, said by VoiceOver.
    var lastAnnouncement: String = ""

    // MARK: - Computed properties

    var isProtected: Bool {
        return lists.isProtected
    }

    /// The units in the list of plans' order, for the popup.
    var units: [String] {
        var seen: [String] = []
        var ordered: [PlanShareDocument] = []
        for document in lists.documents {
            if !seen.contains(document.unit) {
                seen.append(document.unit)
                ordered.append(document)
            }
        }
        ordered.sort { (first: PlanShareDocument, second: PlanShareDocument) -> Bool in
            if first.unitOrder != second.unitOrder {
                return first.unitOrder < second.unitOrder
            }
            return first.unit < second.unit
        }
        var result: [String] = []
        for document in ordered {
            result.append(document.unit)
        }
        return result
    }

    /// The full counts, whatever is showing.
    var sharedCount: Int {
        return documents(in: .shared, filtered: false).count
    }

    var heldBackCount: Int {
        return documents(in: .notShared, filtered: false).count
    }

    /// Answer keys of either kind that sit in Shared now.
    var answerKeysInShared: Int {
        var count: Int = 0
        for document in documents(in: .shared, filtered: false) where document.isAnswerKey {
            count += 1
        }
        return count
    }

    /// The sentence by Share: the full counts (wordsForTheTables.shareCounts).
    var shareCountsSentence: String {
        return PlanShareTablesModel.shareCounts(shared: sharedCount, heldBack: heldBackCount)
    }

    // MARK: - Initializer

    init(lists: PlanShareLists) {
        self.lists = lists
        for document in lists.documents {
            places[document.place] = document.start
        }
    }

    // MARK: - Functions

    /// The documents in a table, filtered or all, in the table's sort.
    func documents(in table: Table, filtered: Bool = true) -> [PlanShareDocument] {
        var found: [PlanShareDocument] = []
        for document in lists.documents {
            if places[document.place] != table {
                continue
            }
            if filtered && !PlanShareTablesModel.matches(document, query: query, unit: unit, keysOnly: keysOnly) {
                continue
            }
            found.append(document)
        }
        let keys: [SortKey] = sort[table] ?? []
        found.sort { (first: PlanShareDocument, second: PlanShareDocument) -> Bool in
            return PlanShareTablesModel.comes(first, before: second, by: keys, in: table, isProtected: lists.isProtected)
        }
        return found
    }

    /// A table's header: its title and a count that never hides how many
    /// documents it holds (countCases).
    func header(for table: Table) -> String {
        return PlanShareTablesModel.header(
            for: table,
            shown: documents(in: table).count,
            total: documents(in: table, filtered: false).count
        )
    }

    /// Moves the given places to a table: only documents that can be moved,
    /// and only ones the filter is showing in the other table. Returns how
    /// many moved, and keeps the sentence VoiceOver is to say.
    @discardableResult
    func move(_ chosen: Set<String>, to table: Table) -> Int {
        var showing: Set<String> = []
        for other in Table.allCases where other != table {
            for document in documents(in: other) {
                showing.insert(document.place)
            }
        }
        var moved: Int = 0
        for document in lists.documents {
            if !chosen.contains(document.place) || !document.movable || !showing.contains(document.place) {
                continue
            }
            if places[document.place] != table {
                places[document.place] = table
                moved += 1
            }
        }
        for each in Table.allCases {
            var kept: Set<String> = []
            for place in selection[each] ?? [] where places[place] == each {
                kept.insert(place)
            }
            selection[each] = kept
        }
        if moved > 0 {
            let words: String = table == .shared ? PlanShareTableWording.movedToShared : PlanShareTableWording.movedToNotShared
            lastAnnouncement = words.replacingOccurrences(of: "{n}", with: String(moved))
        }
        return moved
    }

    /// The selected rows of a table that are showing: what a move button
    /// acts on.
    func visibleSelection(in table: Table) -> Set<String> {
        var result: Set<String> = []
        let chosen: Set<String> = selection[table] ?? []
        for document in documents(in: table) where chosen.contains(document.place) && document.movable {
            result.insert(document.place)
        }
        return result
    }

    /// What the app writes into the year's marker when Share is pressed
    /// (rememberedChoices): every earlier entry of a document still listed,
    /// with each document whose place now differs from where it started.
    func choicesToWrite(previous: [String: String]) -> [String: String] {
        var choices: [String: String] = [:]
        for document in lists.documents where document.movable {
            if let earlier = previous[document.place], Table(rawValue: earlier) != nil {
                choices[document.place] = earlier
            }
            let now: Table = places[document.place] ?? document.start
            if now != document.start {
                choices[document.place] = now.rawValue
            }
        }
        return choices
    }

    /// The Note column's words for a row where it is now.
    func note(for document: PlanShareDocument) -> String {
        let table: Table = places[document.place] ?? document.start
        if !document.movable {
            return PlanShareTableWording.noteCannotShare
        }
        if document.warns(in: table, isProtected: lists.isProtected) {
            return PlanShareTableWording.noteOpenKey
        }
        if document.answerKey == "folder" {
            return PlanShareTableWording.noteAnswerKey
        }
        if document.answerKey == "hint" {
            return PlanShareTableWording.noteMayBe
        }
        return ""
    }

    // MARK: - Functions: the contract's rules, with no view

    /// filterCases: every word of the query inside the name, the unit or
    /// the kind, case and accents folded; then the unit and keys-only.
    static func matches(_ document: PlanShareDocument, query: String, unit: String?, keysOnly: Bool) -> Bool {
        if let unit = unit, document.unit != unit {
            return false
        }
        if keysOnly && !document.isAnswerKey {
            return false
        }
        let haystack: String = fold(document.name + "\n" + document.unit + "\n" + document.kind)
        for word in query.split(whereSeparator: { (character: Character) -> Bool in
            return character.isWhitespace
        }) {
            if !haystack.contains(fold(String(word))) {
                return false
            }
        }
        return true
    }

    static func fold(_ text: String) -> String {
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// countCases.
    static func header(for table: Table, shown: Int, total: Int) -> String {
        var count: String = PlanShareTableWording.countAll.replacingOccurrences(of: "{n}", with: String(total))
        if shown != total {
            count = PlanShareTableWording.countFiltered
                .replacingOccurrences(of: "{shown}", with: String(shown))
                .replacingOccurrences(of: "{total}", with: String(total))
        }
        let title: String = table == .shared ? PlanShareTableWording.sharedTable : PlanShareTableWording.notSharedTable
        return title.replacingOccurrences(of: "{count}", with: count)
    }

    /// countCases.shareCountsCases.
    static func shareCounts(shared: Int, heldBack: Int) -> String {
        return PlanShareTableWording.shareCounts
            .replacingOccurrences(of: "{shared}", with: String(shared))
            .replacingOccurrences(of: "{heldBack}", with: String(heldBack))
    }

    /// One table's order: each key in turn, then the place, so two rows
    /// never tie.
    static func comes(
        _ first: PlanShareDocument,
        before second: PlanShareDocument,
        by keys: [SortKey],
        in table: Table,
        isProtected: Bool
    ) -> Bool {
        for key in keys {
            let order: ComparisonResult = compare(first, second, by: key.column, in: table, isProtected: isProtected)
            if order == .orderedSame {
                continue
            }
            return key.ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return first.place < second.place
    }

    static func compare(
        _ first: PlanShareDocument,
        _ second: PlanShareDocument,
        by column: Column,
        in table: Table,
        isProtected: Bool
    ) -> ComparisonResult {
        switch column {
        case .unit:
            if first.unitOrder != second.unitOrder {
                return first.unitOrder < second.unitOrder ? .orderedAscending : .orderedDescending
            }
            return first.unit.localizedStandardCompare(second.unit)
        case .name:
            return first.name.localizedStandardCompare(second.name)
        case .folder:
            return first.folder.localizedStandardCompare(second.folder)
        case .kind:
            return first.kind.localizedStandardCompare(second.kind)
        case .note:
            let firstNote: String = first.mark ?? ""
            let secondNote: String = second.mark ?? ""
            return firstNote.localizedStandardCompare(secondNote)
        }
    }
}
