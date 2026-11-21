import Foundation
@testable import QuartzTeachers

/// Runs the contract's Undo cases against the real journal and door, and
/// answers with what went wrong (an empty list when nothing did).
///
/// Written without XCTest on purpose: the `Undo*Tests` classes assert its
/// answers are empty, and the standalone harness under the director's
/// scratchpad (`measure/899-u1/`) compiles this same file beside copies of
/// `Models/Undo/` and runs every case for real, without the app (#899, U1).
nonisolated enum UndoContractReplay {

    // MARK: - Reading the contract

    static func repositoryURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["PLANTOIR_REPOSITORY"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func contract(_ name: String) throws -> [String: Any] {
        let url: URL = repositoryURL().appendingPathComponent("contracts").appendingPathComponent(name)
        let data: Data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReplayProblem.notAnObject(name)
        }
        return object
    }

    static func undoBlock() throws -> [String: Any] {
        guard let block = try contract("shared-rules.json")["undo"] as? [String: Any] else {
            throw ReplayProblem.notAnObject("shared-rules.json -> undo")
        }
        return block
    }

    enum ReplayProblem: Error {
        case notAnObject(String)
    }

    /// A JSON value as an optional string: NSNull and absence are nil.
    static func string(_ value: Any?) -> String? {
        return value as? String
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    // MARK: - The front page's maintainer

    /// Every re-derivation the replay's runner was asked for, as
    /// "<path>#<section>", in order.
    nonisolated(unsafe) static var rederived: [String] = []

    static let rederivedLock: NSLock = NSLock()

    /// Registers a runner for `sectionFrontPage` that records each call and
    /// writes nothing, so the cases prove WHEN a re-derivation runs; the
    /// app's own front-page rule is tested on its own
    /// (`UndoOpKindsTests.testTheFrontPageIsRederivedByTheAppsOwnRule`).
    /// Without a runner, a step holding a `recompute` is not available
    /// (`UndoMaintainers`).
    static func registerTheFrontPageMaintainer() {
        UndoMaintainers.register("sectionFrontPage") { op, _ in
            recordARederivation(op)
        }
    }

    static func recordARederivation(_ op: UndoOp) {
        rederivedLock.lock()
        rederived.append((op.path ?? "") + "#" + String(op.section ?? 0))
        rederivedLock.unlock()
    }

    static func takeTheRederived() -> [String] {
        rederivedLock.lock()
        defer {
            rederivedLock.unlock()
        }
        let taken: [String] = rederived
        rederived = []
        return taken
    }

    // MARK: - A scratch working folder

    /// A fresh folder with a working folder (`wf`) and a list (`undo`).
    static func scratch(under parent: URL, named name: String) throws -> (root: URL, journalFolder: URL) {
        let folder: URL = parent.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        let root: URL = folder.appendingPathComponent("wf", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("courses"), withIntermediateDirectories: true)
        return (root: root, journalFolder: folder.appendingPathComponent("undo", isDirectory: true))
    }

    static func write(_ text: String, to relativePath: String, in root: URL) throws {
        let url: URL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A file's SHA-256, or a folder's listing's (U4a: Add folder's tree);
    /// nil when there is neither.
    static func hash(of relativePath: String, in root: URL) -> String? {
        let url: URL = root.appendingPathComponent(relativePath)
        guard let data = UndoItem.read(at: url).data else {
            if case .tree(let listing, _) = UndoTreeReading.read(at: url) {
                return listing.sha
            }
            return nil
        }
        return UndoHash.sha256(of: data)
    }

    static func draft(changes: [UndoFileChange], root: URL, action: String) -> UndoStepDraft {
        return UndoStepDraft(
            action: UndoAction(key: action, arguments: ["pageCount": String(changes.count)]),
            madeBy: "menu",
            workingFolderURL: root,
            workingFolderPath: root.path,
            course: "TST1O",
            section: 1,
            actionClass: "A",
            holds: "section",
            changes: changes,
            recomputes: []
        )
    }

    /// The change one `step` makes: each page's key set to its line with the
    /// traces' writer, pages that are gone or declined left alone, sorted by
    /// path as the generator sorts them.
    static func changes(setting edits: [(path: String, key: String, line: String)], in root: URL) -> [UndoFileChange] {
        var newText: [String: String] = [:]
        var oldData: [String: Data] = [:]
        for edit in edits {
            let current: String
            if let pending = newText[edit.path] {
                current = pending
            } else {
                guard let data = UndoItem.read(at: root.appendingPathComponent(edit.path)).data,
                      let text = UndoText.decode(data) else {
                    continue
                }
                oldData[edit.path] = data
                current = text
            }
            guard let changed = JournaledWrite.settingEntry(key: edit.key, to: edit.line, in: current) else {
                continue
            }
            newText[edit.path] = changed
        }
        var paths: [String] = []
        for (path, _) in newText {
            paths.append(path)
        }
        paths.sort()
        var result: [UndoFileChange] = []
        for path in paths {
            let before: Data? = oldData[path]
            let after: Data = Data((newText[path] ?? "").utf8)
            if before == after {
                continue
            }
            result.append(UndoFileChange(relativePath: path, before: before, after: after))
        }
        return result
    }

    /// The traces' hand edits, as the generator makes them.
    static func handEdit(_ kind: String, at relativePath: String, in root: URL) throws {
        let url: URL = root.appendingPathComponent(relativePath)
        if kind == "deletePage" {
            try FileManager.default.removeItem(at: url)
            return
        }
        guard let data = UndoItem.read(at: url).data, let text = UndoText.decode(data) else {
            return
        }
        if kind == "body" {
            try Data((text + "A line the teacher wrote in Obsidian.\n").utf8).write(to: url)
            return
        }
        guard let layout = UndoFrontMatter.layout(of: text) else {
            return
        }
        let key: String = kind == "otherKey" ? "title" : "publish"
        let found: [UndoFrontMatter.Entry] = layout.entries(forKey: key)
        if found.count != 1 {
            return
        }
        var lines: [String] = layout.lines
        let old: String = lines[found[0].start]
        let ending: String = old.hasSuffix("\r") ? "\r" : ""
        let bare: String = PageFrontmatter.trimmingCarriageReturn(old)
        lines[found[0].start] = bare + (kind == "otherKey" ? " (edited)" : " # checked") + ending
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
    }

    /// What an undo or a redo left apart (U3b), or nothing.
    static func leftApart(of outcome: UndoOutcome) -> [String] {
        switch outcome {
        case .undone(_, let leftApart, _), .redone(_, let leftApart, _):
            return leftApart
        default:
            return []
        }
    }

    /// What an undo or a redo named as starting at the next login.
    static func startsAtTheNextLogin(of outcome: UndoOutcome) -> [String] {
        switch outcome {
        case .undone(_, _, let starts), .redone(_, _, let starts):
            return starts
        default:
            return []
        }
    }

    static func outcomeWord(_ outcome: UndoOutcome) -> String {
        switch outcome {
        case .undone:
            return "undone"
        case .redone:
            return "redone"
        case .nothingToUndo:
            return "nothingToUndo"
        case .nothingToRedo:
            return "nothingToRedo"
        case .anotherChangeIsUnderWay:
            return "anotherChangeIsUnderWay"
        case .notAvailable:
            return "notAvailable"
        case .refused(let refusal, _):
            switch refusal {
            case .changedSince:
                return "changedSince"
            case .fileIsInUse:
                return "fileIsInUse"
            case .cannotTellNow:
                return "cannotTellNow"
            case .couldNotWrite:
                return "couldNotWrite"
            case .contentMissing:
                return "contentMissing"
            case .notReadable:
                return "notReadable"
            }
        case .listUnavailable:
            return "listUnavailable"
        case .stoppedByATest:
            return "stoppedByATest"
        }
    }

    // MARK: - contracts/undo-traces.json

    /// Replays every trace. Answers how many traces and calls were run, and
    /// what disagreed with the contract.
    static func replayTraces(under parent: URL) throws -> (traces: Int, calls: Int, failures: [String]) {
        registerTheFrontPageMaintainer()
        let document: [String: Any] = try contract("undo-traces.json")
        let fixture: [[String: Any]] = document["fixture"] as? [[String: Any]] ?? []
        let traces: [[String: Any]] = document["traces"] as? [[String: Any]] ?? []
        var pathOfPage: [String: String] = [:]
        for page in fixture {
            if let id = string(page["page"]), let path = string(page["path"]) {
                pathOfPage[id] = path
            }
        }
        var pageIDs: [String] = []
        for page in fixture {
            if let id = string(page["page"]) {
                pageIDs.append(id)
            }
        }

        var failures: [String] = []
        var callCount: Int = 0
        for trace in traces {
            let name: String = string(trace["name"]) ?? "?"
            let place: (root: URL, journalFolder: URL) = try scratch(under: parent, named: name)
            let root: URL = place.root
            for page in fixture {
                // From the exact bytes: Foundation's JSON reader drops a
                // byte-order mark inside a string, and page p6 starts with one.
                let url: URL = root.appendingPathComponent(string(page["path"]) ?? "")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes(fromHex: string(page["utf8Hex"]) ?? "").write(to: url)
            }
            let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
            let calls: [[String: Any]] = trace["calls"] as? [[String: Any]] ?? []
            var lastUndoIndex: Int = -1
            var index: Int = 0
            while index < calls.count {
                if string(calls[index]["call"]) == "undo" {
                    lastUndoIndex = index
                }
                index += 1
            }
            var afterUndoingAll: [String: String?] = [:]

            index = 0
            for call in calls {
                callCount += 1
                let where_: String = "\(name) call \(index + 1)"
                let kind: String = string(call["call"]) ?? ""
                let expect: String? = string(call["expect"])
                switch kind {
                case "step":
                    var edits: [(path: String, key: String, line: String)] = []
                    for set in call["set"] as? [[String: Any]] ?? [] {
                        edits.append((
                            path: pathOfPage[string(set["page"]) ?? ""] ?? "",
                            key: string(set["key"]) ?? "",
                            line: string(set["line"]) ?? ""
                        ))
                    }
                    let changes: [UndoFileChange] = UndoContractReplay.changes(setting: edits, in: root)
                    let outcome: JournaledWriteOutcome = JournaledWrite.perform(
                        draft(changes: changes, root: root, action: string(call["action"]) ?? "publishPages"),
                        in: journal, mode: .live
                    )
                    if expect == "applied" {
                        if outcome != .applied(seq: int(call["seq"]) ?? -1) {
                            failures.append("\(where_): step came to \(outcome), not applied \(int(call["seq"]) ?? -1)")
                        }
                    } else if outcome != .changedNothing {
                        failures.append("\(where_): step came to \(outcome), not changedNothing")
                    }
                case "undo", "redo":
                    let outcome: UndoOutcome = kind == "undo"
                        ? journal.undoNewest(resolveRoot: { _ in root })
                        : journal.redoNewest(resolveRoot: { _ in root })
                    let word: String = outcomeWord(outcome)
                    if word != expect {
                        failures.append("\(where_): \(kind) came to \(word), not \(expect ?? "?")")
                    }
                    if case .undone(let seq, _, _) = outcome, seq != int(call["seq"]) {
                        failures.append("\(where_): undid \(seq), not \(int(call["seq"]) ?? -1)")
                    }
                    if case .redone(let seq, _, _) = outcome, seq != int(call["seq"]) {
                        failures.append("\(where_): redid \(seq), not \(int(call["seq"]) ?? -1)")
                    }
                    if case .refused(.changedSince(let first, let others), let cleared) = outcome {
                        if first != pathOfPage[string(call["page"]) ?? ""] {
                            failures.append("\(where_): named \(first), not page \(string(call["page"]) ?? "?")")
                        }
                        if others != int(call["others"]) {
                            failures.append("\(where_): \(others) others, not \(int(call["others"]) ?? -1)")
                        }
                        if kind == "undo" && !cleared {
                            failures.append("\(where_): the refused undo did not clear the list (ruling 13)")
                        }
                        if kind == "redo" && cleared {
                            failures.append("\(where_): the refused redo cleared the list (ruling 20 drops only the redo)")
                        }
                    }
                case "move":
                    // U2: the page moved aside as one `move`, through the
                    // door that plans a step's ops forward.
                    let from: String = pathOfPage[string(call["page"]) ?? ""] ?? ""
                    let content: Data = UndoItem.read(at: root.appendingPathComponent(from)).data ?? Data()
                    let op: UndoOp = UndoOp.moveFile(from: from, to: string(call["to"]) ?? "", sha: UndoHash.sha256(of: content))
                    let outcome: JournaledWriteOutcome = JournaledWrite.perform(
                        ops: UndoContractKinds.draft(ops: [op], blobs: [], root: root, action: "movePage"),
                        in: journal, mode: .live
                    )
                    if outcome != .applied(seq: int(call["seq"]) ?? -1) {
                        failures.append("\(where_): move came to \(outcome), not applied \(int(call["seq"]) ?? -1)")
                    }
                case "handEdit":
                    try handEdit(string(call["kind"]) ?? "", at: pathOfPage[string(call["page"]) ?? ""] ?? "", in: root)
                case "note":
                    try appendNote(to: journal)
                default:
                    failures.append("\(where_): unknown call \(kind)")
                }

                let offer: UndoOffer = try journal.offer()
                let head: Int? = offer.head?.step.seq
                let redo: Int? = offer.redoCandidate?.step.seq
                if head != int(call["head"]) {
                    failures.append("\(where_): head \(String(describing: head)), not \(String(describing: int(call["head"])))")
                }
                if redo != int(call["redo"]) {
                    failures.append("\(where_): redo \(String(describing: redo)), not \(String(describing: int(call["redo"])))")
                }
                if index == lastUndoIndex {
                    for id in pageIDs {
                        afterUndoingAll[id] = hash(of: pathOfPage[id] ?? "", in: root)
                    }
                }
                index += 1
            }

            let expectedAfterUndoing: [String: Any] = trace["afterUndoingAll"] as? [String: Any] ?? [:]
            let expectedFinal: [String: Any] = trace["final"] as? [String: Any] ?? [:]
            for id in pageIDs {
                let wantedAfterUndoing: String? = string(expectedAfterUndoing[id])
                let gotAfterUndoing: String? = afterUndoingAll[id] ?? nil
                if wantedAfterUndoing != gotAfterUndoing {
                    failures.append("\(name): page \(id) after undoing everything is not the contract's")
                }
                if string(expectedFinal[id]) != hash(of: pathOfPage[id] ?? "", in: root) {
                    failures.append("\(name): page \(id) at the end is not the contract's")
                }
            }
            if staysBeside(root) {
                failures.append("\(name): a staged file was left beside a page")
            }
            let fold: UndoFold = try journal.read()
            if fold.unreadableLines != 0 || fold.ignoredEvents != 0 {
                failures.append("\(name): \(fold.unreadableLines) unreadable lines, \(fold.ignoredEvents) ignored events")
            }
        }
        return (traces: traces.count, calls: callCount, failures: failures)
    }

    /// Whether any staged file is left anywhere under the working folder.
    static func staysBeside(_ root: URL) -> Bool {
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            return false
        }
        while let item = walker.nextObject() as? String {
            if (item as NSString).lastPathComponent.contains(UndoSwap.stagedMarker) {
                return true
            }
        }
        return false
    }

    // MARK: - undo.checkCases

    /// Every key a check case may carry: anything else is a case the replay
    /// would silently not check (the contract review's MINOR 9). `why` is a
    /// reason for a person and is never compared.
    static let checkKeys: Set<String> = ["name", "op", "current", "undo", "redo", "why"]

    /// Puts what a case's `current` (or one side of a move's) describes at
    /// a place: text, raw bytes, an empty folder, a tree, or nothing.
    static func place(_ current: [String: Any], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let text = string(current["text"]) {
            try Data(text.utf8).write(to: url)
        } else if let hex = string(current["bytesHex"]) {
            try bytes(fromHex: hex).write(to: url)
        } else if current["folder"] as? Bool == true {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else if let target = string(current["link"]) {
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
        } else if let tree = current["tree"] as? [String: Any] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for folder in tree["folders"] as? [String] ?? [] {
                try FileManager.default.createDirectory(at: url.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            for (path, text) in tree["files"] as? [String: String] ?? [:] {
                let fileURL: URL = url.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: fileURL)
            }
            for (path, target) in tree["links"] as? [String: String] ?? [:] {
                try FileManager.default.createSymbolicLink(atPath: url.appendingPathComponent(path).path, withDestinationPath: target)
            }
        }
        if current["cannotBeRead"] as? Bool == true {
            // Unreadable just now: no permission (`cannotBeRead`).
            _ = chmod(url.path, 0)
            madeUnreadable.append(url)
        }
    }

    /// Places a case made unreadable, given their permissions back once
    /// the case is checked, so the scratch folder can be removed.
    nonisolated(unsafe) static var madeUnreadable: [URL] = []

    static func giveBackPermissions() {
        for url in madeUnreadable {
            _ = chmod(url.path, 0o755)
        }
        madeUnreadable = []
    }

    /// A case's `listing` (or `tree`) as the listing this version makes.
    static func listing(from tree: [String: Any]) -> UndoTreeListing {
        var files: [UndoTreeListing.File] = []
        for (path, text) in tree["files"] as? [String: String] ?? [:] {
            if (path as NSString).lastPathComponent == UndoTreeListing.ignoredName {
                continue
            }
            files.append(UndoTreeListing.File(path: path, sha: UndoHash.sha256(of: Data(text.utf8))))
        }
        var folders: [String] = []
        for folder in tree["folders"] as? [String] ?? [] where (folder as NSString).lastPathComponent != UndoTreeListing.ignoredName {
            folders.append(folder)
        }
        return UndoTreeListing(folders: folders, files: files)
    }

    /// An external place holding one value, for a case.
    struct CasePlaces: UndoExternalPlaces {

        // MARK: - Stored properties

        let reading: UndoExternalReading

        // MARK: - Functions

        func read(_ target: String) -> UndoExternalReading {
            return reading
        }

        func write(_ target: String, _ value: UndoJSON?) -> Bool {
            return false
        }
    }

    static func runCheckCases(under parent: URL) throws -> (cases: Int, failures: [String]) {
        let cases: [[String: Any]] = try undoBlock()["checkCases"] as? [[String: Any]] ?? []
        var failures: [String] = []
        var number: Int = 0
        for testCase in cases {
            number += 1
            let name: String = string(testCase["name"]) ?? "?"
            failures += unknownKeys(in: testCase, allowed: checkKeys, list: "checkCases", name: name)
            let place: (root: URL, journalFolder: URL) = try scratch(under: parent, named: "check-\(number)")
            let current: [String: Any] = testCase["current"] as? [String: Any] ?? [:]
            var given: [String: Any] = testCase["op"] as? [String: Any] ?? [:]
            let kind: String = string(given["kind"]) ?? ""
            let relativePath: String = string(given["path"]) ?? "page.md"
            let url: URL = place.root.appendingPathComponent(UndoOp.isSafeRelativePath(relativePath) ? relativePath : "page.md")
            if kind == "move" || kind == "moveApart" || kind == "setAside" {
                if let from = string(given["from"]), UndoOp.isSafeRelativePath(from), let side = current["atFrom"] as? [String: Any] {
                    try self.place(side, at: place.root.appendingPathComponent(from))
                }
                if let to = string(given["to"]), UndoOp.isSafeRelativePath(to), to != string(given["from"]),
                   let side = current["atTo"] as? [String: Any] {
                    if FileManager.default.fileExists(atPath: place.root.appendingPathComponent(to).path) == false {
                        try self.place(side, at: place.root.appendingPathComponent(to))
                    }
                }
            } else if kind != "external" {
                try self.place(current, at: url)
            }
            var places: CasePlaces = CasePlaces(reading: .notSet)
            if current["unreadable"] as? Bool == true {
                places = CasePlaces(reading: .cannotTell)
            } else if current.keys.contains("preference") {
                let data: Data = try JSONSerialization.data(withJSONObject: ["v": current["preference"] ?? NSNull()])
                let wrapped: [String: UndoJSON] = try JSONDecoder().decode([String: UndoJSON].self, from: data)
                places = CasePlaces(reading: .value(wrapped["v"] ?? .null))
            }

            // The op is DECODED from the case's JSON, so the lenient reader
            // is what is tested: a kind it does not know, a path that climbs
            // out, a number where text belongs.
            if kind == "writeFile" {
                var names: [String] = []
                if let text = string(given["beforeText"]) {
                    given["beforeSha"] = UndoHash.sha256(of: Data(text.utf8))
                    names.append(UndoHash.sha256(of: Data(text.utf8)))
                }
                if let text = string(given["afterText"]) {
                    given["afterSha"] = UndoHash.sha256(of: Data(text.utf8))
                    names.append(UndoHash.sha256(of: Data(text.utf8)))
                }
                given["blobs"] = names
                given["beforeText"] = nil
                given["afterText"] = nil
            }
            if let text = string(given["contentText"]) {
                given["sha"] = UndoHash.sha256(of: Data(text.utf8))
                given["contentText"] = nil
            }
            if let tree = given["listing"] as? [String: Any] {
                let made: UndoTreeListing = listing(from: tree)
                given["listingSha"] = made.sha
                if kind == "createTree" || kind == "removeTree" {
                    var names: [String] = [made.sha]
                    for file in made.files where !names.contains(file.sha) {
                        names.append(file.sha)
                    }
                    given["blobs"] = names
                }
                given["listing"] = nil
            }
            // A JSON null is a value for editJSON and external (a member or
            // a preference holding null); for every other kind it is absent.
            let keepsNull: Bool = kind == "editJSON" || kind == "external"
            var clean: [String: Any] = [:]
            for (key, value) in given where keepsNull || !(value is NSNull) {
                clean[key] = value
            }
            let op: UndoOp = try JSONDecoder().decode(UndoOp.self, from: JSONSerialization.data(withJSONObject: clean))
            var undo: String = "notReadable"
            var redo: String = "notReadable"
            if op.isReadable {
                let state: UndoOpState
                if op.isWhole {
                    state = UndoCheck.wholeState(of: op, root: place.root, places: places)
                } else {
                    state = UndoCheck.state(of: op, in: UndoItem.read(at: url))
                }
                undo = UndoCheck.verdict(for: state, direction: .backward).rawValue
                redo = UndoCheck.verdict(for: state, direction: .forward).rawValue
            }
            giveBackPermissions()
            if undo != string(testCase["undo"]) {
                failures.append("checkCases '\(name)': undo is \(undo), not \(string(testCase["undo"]) ?? "?")")
            }
            if redo != string(testCase["redo"]) {
                failures.append("checkCases '\(name)': redo is \(redo), not \(string(testCase["redo"]) ?? "?")")
            }
        }
        return (cases: cases.count, failures: failures)
    }

    // MARK: - undo-json-cases.json -> editJSONCases

    /// The bytes of an editJSON move, exactly (the hard review of U2b, LOW a).
    /// The cases live in their own file, out of shared-rules.json, because
    /// some hold keys that differ only by case, which Windows PowerShell 5.1
    /// cannot read (#899 W6).
    static func runEditJSONCases() throws -> (cases: Int, failures: [String]) {
        let cases: [[String: Any]] = try contract("undo-json-cases.json")["editJSONCases"] as? [[String: Any]] ?? []
        var failures: [String] = []
        for testCase in cases {
            let name: String = string(testCase["name"]) ?? "?"
            failures += unknownKeys(in: testCase, allowed: ["name", "file", "op", "direction", "result"], list: "editJSONCases", name: name)
            let given: [String: Any] = testCase["op"] as? [String: Any] ?? [:]
            let op: UndoOp = try JSONDecoder().decode(UndoOp.self, from: JSONSerialization.data(withJSONObject: given))
            let direction: UndoDirection = string(testCase["direction"]) == "undo" ? .backward : .forward
            let file: Data = Data((string(testCase["file"]) ?? "").utf8)
            var result: String? = nil
            if let moved = UndoJSONMember.moved(op, from: .file(file), direction: direction), let data = moved.data {
                result = String(decoding: data, as: UTF8.self)
            }
            if result != string(testCase["result"]) {
                failures.append("editJSONCases '\(name)': came to \(String(describing: result))")
            }
        }
        return (cases: cases.count, failures: failures)
    }

    // MARK: - undo.listingCases

    static func runListingCases() throws -> (cases: Int, failures: [String]) {
        let cases: [[String: Any]] = try undoBlock()["listingCases"] as? [[String: Any]] ?? []
        var failures: [String] = []
        for testCase in cases {
            let name: String = string(testCase["name"]) ?? "?"
            failures += unknownKeys(in: testCase, allowed: ["name", "tree", "listing", "listingSha", "why"], list: "listingCases", name: name)
            let made: UndoTreeListing = listing(from: testCase["tree"] as? [String: Any] ?? [:])
            if made.text != string(testCase["listing"]) {
                failures.append("listingCases '\(name)': the listing is \(made.text.debugDescription)")
            }
            if made.sha != string(testCase["listingSha"]) {
                failures.append("listingCases '\(name)': the listing's hash is \(made.sha)")
            }
            if UndoTreeListing.parse(made.data)?.text != made.text {
                failures.append("listingCases '\(name)': the listing does not read back as itself")
            }
        }
        return (cases: cases.count, failures: failures)
    }

    static func unknownKeys(in testCase: [String: Any], allowed: Set<String>, list: String, name: String) -> [String] {
        var failures: [String] = []
        for (key, _) in testCase where !allowed.contains(key) {
            failures.append("\(list) '\(name)': the key '\(key)' is one this replay does not check")
        }
        return failures
    }

    static func bytes(fromHex hex: String) -> Data {
        var data: Data = Data()
        var characters: [Character] = []
        for character in hex {
            characters.append(character)
        }
        var index: Int = 0
        while index + 1 < characters.count {
            if let byte = UInt8(String([characters[index], characters[index + 1]]), radix: 16) {
                data.append(byte)
            }
            index += 2
        }
        return data
    }

    // MARK: - undo.stackCases

    static let stackKeys: Set<String> = [
        "name", "calls", "head", "redo", "onTheList", "onTheListCount", "oldestOnTheList",
        "expectLast", "cleared", "clearedSeq", "linesWritten", "onTheDisk", "physicallyPruned",
        "blobKept", "interrupted", "markers", "folderKept", "rederived", "nothingMovedOutside",
        "keptOriginalLeft", "foreignKeptOriginalUntouched", "keptWhatItReplacedLines", "keptBesideThePage", "why",
        "leftApart", "schoolYear", "cloudflareMarkers", "leftoverMarkers", "startsAtTheNextLogin",
        "movedFolder", "caseOnlyFolder",
    ]

    /// Holds a step begun from inside a hook, so the case can finish it.
    final class HeldStep {

        // MARK: - Stored properties

        var seq: Int = 0

        var change: UndoFileChange? = nil
    }

    static func intList(_ value: Any?) -> [Int]? {
        guard let numbers = value as? [NSNumber] else {
            return nil
        }
        var result: [Int] = []
        for number in numbers {
            result.append(number.intValue)
        }
        return result
    }

    static func runStackCases(under parent: URL) async throws -> (cases: Int, failures: [String]) {
        registerTheFrontPageMaintainer()
        let cases: [[String: Any]] = try undoBlock()["stackCases"] as? [[String: Any]] ?? []
        let traces: [String: Any] = try contract("undo-traces.json")
        var pagePath: String = ""
        var pageText: String = ""
        var otherPagePath: String = ""
        var otherPageText: String = ""
        for page in traces["fixture"] as? [[String: Any]] ?? [] {
            if string(page["page"]) == "p1" {
                pagePath = string(page["path"]) ?? ""
                pageText = string(page["text"]) ?? ""
            }
            if string(page["page"]) == "p2" {
                otherPagePath = string(page["path"]) ?? ""
                otherPageText = string(page["text"]) ?? ""
            }
        }
        let secondPagePath: String = pagePath.replacingOccurrences(of: "TST1O", with: "TST2O")
        var failures: [String] = []
        var number: Int = 0
        for testCase in cases {
            number += 1
            let name: String = string(testCase["name"]) ?? "?"
            failures += unknownKeys(in: testCase, allowed: stackKeys, list: "stackCases", name: name)
            if !testCase.keys.contains("head") || !testCase.keys.contains("redo") {
                failures.append("stackCases '\(name)': no head or redo to check")
            }
            let place: (root: URL, journalFolder: URL) = try scratch(under: parent, named: "stack-\(number)")
            let root: URL = place.root
            let second: (root: URL, journalFolder: URL) = try scratch(under: parent, named: "stack-\(number)-b")
            let rootB: URL = second.root
            let rootBAway: URL = rootB.deletingLastPathComponent().appendingPathComponent("wf-away", isDirectory: true)
            try write(pageText, to: pagePath, in: root)
            try write(otherPageText, to: otherPagePath, in: root)
            try write(pageText, to: secondPagePath, in: rootB)
            var clockDays: Double = 0
            var last: String = ""
            var lastLeftApart: [String] = []
            var lastStartsAtTheNextLogin: [String] = []
            var linesBeforeTheDeploy: Int = -1
            var linesAfterTheDeploy: Int = -1
            let held: HeldStep = HeldStep()
            var foreignBlob: String? = nil
            var foreignKept: (url: URL, bytes: Data)? = nil
            var contentFolderMadeReadOnly: URL? = nil
            var unreadableKeptOriginals: [URL] = []
            var keptWhatItReplacedLines: Int = 0
            let keptWhatItReplacedHookBefore = UndoTrailHook.keptWhatItReplacedLine
            UndoTrailHook.keptWhatItReplacedLine = { _, _, _, _, _, _ in
                keptWhatItReplacedLines += 1
            }
            defer {
                UndoTrailHook.keptWhatItReplacedLine = keptWhatItReplacedHookBefore
                if let contentFolderMadeReadOnly {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: contentFolderMadeReadOnly.path)
                }
                for keptURL in unreadableKeptOriginals {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: keptURL.path)
                }
            }
            let folderOfB: String = rootB.path
            let places: UndoMemoryPlaces = UndoMemoryPlaces()
            registerTheFrontPageMaintainer()
            _ = takeTheRederived()

            func journal(daysAgo: Int = 0) -> UndoJournal {
                let moment: Date = Date().addingTimeInterval((clockDays - Double(daysAgo)) * 86_400)
                return UndoJournal(folderURL: place.journalFolder, now: { moment })
            }

            func resolve(_ folder: UndoWorkingFolder) -> URL? {
                return UndoReach.root(for: folder)
            }

            func flip(in folderRoot: URL, at path: String) -> [UndoFileChange] {
                var line: String = "publish: true"
                if let data = UndoItem.read(at: folderRoot.appendingPathComponent(path)).data,
                   let text = UndoText.decode(data),
                   UndoLineOps.reading(key: "publish", in: text) == .entry("publish: true") {
                    line = "publish: false"
                }
                return changes(setting: [(path: path, key: "publish", line: line)], in: folderRoot)
            }

            func oneStep(folderRoot: URL, path: String, daysAgo: Int) {
                let outcome: JournaledWriteOutcome = JournaledWrite.perform(
                    draft(changes: flip(in: folderRoot, at: path), root: folderRoot, action: "publishPages"),
                    in: journal(daysAgo: daysAgo), mode: .live
                )
                if case .applied = outcome {
                    last = "applied"
                } else {
                    last = "\(outcome)"
                }
            }

            func beginHeld() throws {
                let change: [UndoFileChange] = flip(in: root, at: pagePath)
                let heldDraft: UndoStepDraft = draft(changes: change, root: root, action: "publishPages")
                held.seq = try JournaledWrite.begin(heldDraft, ops: JournaledWrite.ops(for: heldDraft), in: journal(), mode: .live)
                held.change = change.first
            }

            /// One flip of p1 written by another version of Plantoir: a begin
            /// line written raw, the page changed, then `applied`. The
            /// variant gives the begin a value this version does not write.
            func stepFromAnotherVersion(_ variant: String) throws {
                let change: [UndoFileChange] = flip(in: root, at: pagePath)
                let made: UndoStepDraft = draft(changes: change, root: root, action: "publishPages")
                var opObjects: [[String: Any]] = []
                for op in JournaledWrite.ops(for: made) {
                    if let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(op)) as? [String: Any] {
                        opObjects.append(object)
                    }
                }
                let next: Int = try journal().read().highestSeq + 1
                let moment: String = UndoMoment.text(journal().now())
                let folderID: String = try FolderIdentityFile.identifier(forWorkingFolder: root)
                var step: [String: Any] = [
                    "seq": next,
                    "madeAt": moment,
                    "action": ["key": "publishPages", "arguments": ["pageCount": "1"]],
                    "madeBy": "menu",
                    "workingFolder": ["id": folderID, "pathAtTheTime": root.path],
                    "course": "TST1O",
                    "section": 1,
                    "class": "A",
                    "holds": "section",
                ]
                let frontPage: [String: Any] = ["kind": "recompute", "path": "courses/TST1O/Section 1/index.md", "section": 1]
                if variant == "theFrontPageMaintainer" {
                    var op: [String: Any] = frontPage
                    op["maintainer"] = "sectionFrontPage"
                    opObjects.append(op)
                } else if variant == "aMaintainerNobodyKnows" {
                    var op: [String: Any] = frontPage
                    op["maintainer"] = "aMaintainerNobodyKnows"
                    opObjects.append(op)
                } else if variant == "aHoldsNobodyKnows" {
                    step["holds"] = "workingFolder"
                } else if variant == "openStrings" {
                    step["madeBy"] = "outsideAssistant:A client: with colons:session-7"
                    step["class"] = "Z"
                    step["action"] = ["key": "aKeyNobodyKnows", "arguments": [String: String]()]
                } else if variant == "twoWholeOpsOnOnePlace" {
                    // Breaks opKinds.wholeOps: a folder made inside another
                    // folder the same step makes.
                    let empty: UndoTreeListing = UndoTreeListing(folders: [], files: [])
                    for path in ["courses/TST1O/made", "courses/TST1O/made/inner"] {
                        opObjects.append(["kind": "createTree", "path": path, "listingSha": empty.sha, "blobs": [empty.sha]])
                    }
                } else if variant == "aKeyOnAKnownOp" {
                    if !opObjects.isEmpty {
                        opObjects[0]["onlyWhen"] = "aConditionNobodyKnows"
                    }
                } else {
                    failures.append("stackCases '\(name)': unknown variant \(variant)")
                }
                step["ops"] = opObjects
                let process: Any = try JSONSerialization.jsonObject(with: JSONEncoder().encode(UndoProcess.current()))
                let begin: [String: Any] = ["v": 1, "seq": next, "event": "begin", "at": moment, "step": step, "process": process]
                let beginData: Data = try JSONSerialization.data(withJSONObject: begin, options: [.sortedKeys])
                try appendRaw(String(decoding: beginData, as: UTF8.self), to: journal())
                if let first = change.first {
                    try (first.after ?? Data()).write(to: root.appendingPathComponent(first.relativePath))
                }
                try appendRaw("{\"v\":1,\"seq\":\(next),\"event\":\"applied\",\"at\":\"\(moment)\"}", to: journal())
            }

            for value in testCase["calls"] as? [String] ?? [] {
                if value.hasPrefix("stepFromAnotherVersion:") {
                    try stepFromAnotherVersion(String(value.dropFirst("stepFromAnotherVersion:".count)))
                } else if value == "step" {
                    oneStep(folderRoot: root, path: pagePath, daysAgo: 0)
                } else if value == "stepOn:p2" {
                    oneStep(folderRoot: root, path: otherPagePath, daysAgo: 0)
                } else if value == "step@B" {
                    oneStep(folderRoot: rootB, path: secondPagePath, daysAgo: 0)
                } else if value.hasPrefix("step:") && value.hasSuffix("daysAgo") {
                    let days: Int = Int(value.dropFirst("step:".count).dropLast("daysAgo".count)) ?? 0
                    oneStep(folderRoot: root, path: pagePath, daysAgo: days)
                } else if value.hasPrefix("steps:") {
                    let count: Int = Int(value.dropFirst("steps:".count)) ?? 0
                    var made: Int = 0
                    while made < count {
                        oneStep(folderRoot: root, path: pagePath, daysAgo: 0)
                        made += 1
                    }
                } else if value.hasPrefix("clock:") {
                    clockDays = Double(value.dropFirst("clock:".count).replacingOccurrences(of: "+", with: "")) ?? 0
                } else if value == "undo" {
                    let outcome: UndoOutcome = await journal().undoNewestAndRederive(resolveRoot: { folder in UndoReach.root(for: folder) }, places: places)
                    last = outcomeWord(outcome)
                    lastLeftApart = leftApart(of: outcome)
                    lastStartsAtTheNextLogin = startsAtTheNextLogin(of: outcome)
                } else if value == "redo" {
                    let outcome: UndoOutcome = await journal().redoNewestAndRederive(resolveRoot: { folder in UndoReach.root(for: folder) }, places: places)
                    last = outcomeWord(outcome)
                    lastLeftApart = leftApart(of: outcome)
                    lastStartsAtTheNextLogin = startsAtTheNextLogin(of: outcome)
                } else if UndoContractKinds.calls.contains(value) {
                    if let answered = try UndoContractKinds.call(value, root: root, journal: journal(), places: places) {
                        last = answered
                    }
                } else if value == "editTheLineByHand" {
                    try handEdit("sameLine", at: pagePath, in: root)
                } else if value == "undoWhileAStepBegins" {
                    // Another process begins a step after this undo has
                    // checked its ops and before it answers the refusal.
                    var begun: Bool = false
                    UndoKillPoints.hook = { point in
                        if point == .afterTheCheck && !begun {
                            begun = true
                            try? beginHeld()
                        }
                        return false
                    }
                    last = outcomeWord(journal().undoNewest(resolveRoot: resolve))
                    UndoKillPoints.hook = nil
                } else if value == "deploy" {
                    // What a deploy leaves: a fragment of the section's
                    // published-pages record, and nothing in the list.
                    linesBeforeTheDeploy = try rawLineCount(in: journal())
                    try writeAFragment(courseFolder: root.appendingPathComponent("courses/TST1O"), section: 1, places: ["Section 1/Classes/Day 1"])
                    linesAfterTheDeploy = try rawLineCount(in: journal())
                } else if value == "note" {
                    try appendNote(to: journal())
                } else if value == "begin:dead@B" {
                    // A step in folder B whose process then died, before any
                    // file was touched.
                    let change: [UndoFileChange] = flip(in: rootB, at: secondPagePath)
                    let deadDraft: UndoStepDraft = draft(changes: change, root: rootB, action: "publishPages")
                    let moment: Date = Date().addingTimeInterval(clockDays * 86_400)
                    let dying: UndoJournal = UndoJournal(folderURL: place.journalFolder, process: goneProcess, now: { moment })
                    _ = try JournaledWrite.begin(deadDraft, ops: JournaledWrite.ops(for: deadDraft), in: dying, mode: .live)
                } else if value == "moveFolder:B" {
                    try FileManager.default.moveItem(at: rootB, to: rootBAway)
                } else if value == "restoreFolder:B" {
                    try FileManager.default.moveItem(at: rootBAway, to: rootB)
                } else if value == "foreignLine" {
                    let next: Int = try journal().read().highestSeq + 1
                    try appendRaw("{\"v\":2,\"seq\":\(next),\"event\":\"begin\",\"step\":{\"seq\":\(next),\"later\":true}}", to: journal())
                } else if value == "foreignBlobLine" {
                    // A newer version's step this version cannot read at all,
                    // naming a blob: nothing in it can say the blob is needed.
                    let next: Int = try journal().read().highestSeq + 1
                    let blob: Data = Data("content a newer Plantoir keeps for a line this one cannot read".utf8)
                    let sha: String = UndoHash.sha256(of: blob)
                    try journal().withLock { writer in
                        try writer.writeBlob(blob)
                    }
                    foreignBlob = sha
                    try appendRaw("{\"v\":2,\"seq\":\(next),\"event\":\"begin\",\"step\":{\"seq\":\(next),\"ops\":[{\"kind\":\"later\",\"blobs\":[\"\(sha)\"]}]}}", to: journal())
                    try appendRaw("{\"v\":2,\"seq\":\(next),\"event\":\"applied\"}", to: journal())
                } else if value == "foreignStep" {
                    let next: Int = try journal().read().highestSeq + 1
                    let blob: Data = Data("content a newer Plantoir keeps".utf8)
                    let sha: String = UndoHash.sha256(of: blob)
                    try journal().withLock { writer in
                        try writer.writeBlob(blob)
                    }
                    foreignBlob = sha
                    let folderID: String = try FolderIdentityFile.identifier(forWorkingFolder: root)
                    let begin: String = "{\"v\":1,\"seq\":\(next),\"event\":\"begin\",\"at\":\"\(UndoMoment.text(Date()))\",\"step\":{\"seq\":\(next),\"madeAt\":\"\(UndoMoment.text(Date()))\",\"workingFolder\":{\"id\":\"\(folderID)\",\"pathAtTheTime\":\"\(root.path)\"},\"ops\":[{\"kind\":\"aKindNobodyKnows\",\"from\":\"a.md\",\"to\":\"b.md\",\"blobs\":[\"\(sha)\"]}]}}"
                    try appendRaw(begin, to: journal())
                    try appendRaw("{\"v\":1,\"seq\":\(next),\"event\":\"applied\"}", to: journal())
                } else if value.hasPrefix("cleared:") {
                    // A clearing written by some version for a reason of its
                    // own: every reader honours it whatever the reason.
                    let reason: String = String(value.dropFirst("cleared:".count))
                    try journal().withLock { writer in
                        try writer.append(UndoEventLine(seq: writer.fold.highestSeq, event: .cleared, reason: reason))
                    }
                } else if value == "goLive" {
                    try journal().clearTheListAsTheSwitchGoesLive()
                } else if value == "wholeFileStep" {
                    // p1's publish line flipped AND a line added to its body:
                    // one writeFile op, whose content is a blob.
                    var wholeFile: [UndoFileChange] = []
                    for change in flip(in: root, at: pagePath) {
                        let after: Data = (change.after ?? Data()) + Data("A line the step added.\n".utf8)
                        wholeFile.append(UndoFileChange(relativePath: change.relativePath, before: change.before, after: after))
                    }
                    let outcome: JournaledWriteOutcome = JournaledWrite.perform(
                        draft(changes: wholeFile, root: root, action: "publishPages"), in: journal(), mode: .live
                    )
                    if case .applied = outcome {
                        last = "applied"
                    } else {
                        last = "\(outcome)"
                    }
                } else if value == "removeContent" {
                    try FileManager.default.removeItem(at: journal().contentFolderURL)
                } else if value == "contentCannotBeStored" {
                    // The list's content folder, empty and taking no new
                    // file (a full or read-only disk, as far as the list can
                    // tell): no blob can be written from here on.
                    let contentURL: URL = journal().contentFolderURL
                    if UndoItem.read(at: contentURL) == .absent {
                        try FileManager.default.createDirectory(at: contentURL, withIntermediateDirectories: true)
                    }
                    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: contentURL.path)
                    contentFolderMadeReadOnly = contentURL
                } else if value == "beforeContentGoneAndCannotBeStored" {
                    // Only the newest step's content for what p1 held before
                    // is gone from the list, and the list's folder for it
                    // takes no new file: what p1 held after is still there
                    // (the second review of U3c, MEDIUM).
                    let fold: UndoFold = try journal().read()
                    var removedOne: Bool = false
                    if let head = fold.offer(now: journal().now()).head {
                        for op in head.step.ops where op.path == pagePath && op.knownKind == .writeFile {
                            if let sha = op.beforeSha {
                                let blobURL: URL = journal().blobURL(sha: sha)
                                try FileManager.default.removeItem(at: blobURL)
                                let prefixFolder: URL = blobURL.deletingLastPathComponent()
                                try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: prefixFolder.path)
                                contentFolderMadeReadOnly = prefixFolder
                                removedOne = true
                            }
                        }
                    }
                    if !removedOne {
                        failures.append("stackCases '\(name)': no whole-file step whose before content to take away")
                    }
                } else if value == "afterContentGone" {
                    // Only the newest step's content for what p1 holds after
                    // it is gone from the list; the list still takes a new
                    // file unless a later call says otherwise (U4a review 1,
                    // LOW 4: U3c review 3's probe shape).
                    let fold: UndoFold = try journal().read()
                    var removedOne: Bool = false
                    if let head = fold.offer(now: journal().now()).head {
                        for op in head.step.ops where op.path == pagePath && op.knownKind == .writeFile {
                            if let sha = op.afterSha {
                                // The blob and, when it is then empty, the
                                // folder it was in: a later write of the blob
                                // makes that folder again, so a list taking
                                // no new file (`contentCannotBeStored`, which
                                // seals the content folder) cannot take it.
                                let blobURL: URL = journal().blobURL(sha: sha)
                                try FileManager.default.removeItem(at: blobURL)
                                let prefixFolder: URL = blobURL.deletingLastPathComponent()
                                if (try? FileManager.default.contentsOfDirectory(atPath: prefixFolder.path))?.isEmpty == true {
                                    try FileManager.default.removeItem(at: prefixFolder)
                                }
                                removedOne = true
                            }
                        }
                    }
                    if !removedOne {
                        failures.append("stackCases '\(name)': no whole-file step whose after content to take away")
                    }
                } else if value == "keepTheOriginal" {
                    // The newest step's kept original of p1, as a swap whose
                    // tidy could not remove it leaves it: what p1 held before.
                    let fold: UndoFold = try journal().read()
                    var keptOne: Bool = false
                    if let head = fold.offer(now: journal().now()).head {
                        for op in head.step.ops where op.path == pagePath && op.knownKind == .writeFile {
                            if let sha = op.beforeSha, let before = try journal().blobContent(sha: sha) {
                                let keptURL: URL = UndoSwap.besideURL(for: root.appendingPathComponent(pagePath), label: "\(head.step.seq)-apply", role: "orig")
                                try before.write(to: keptURL)
                                keptOne = true
                            }
                        }
                    }
                    if !keptOne {
                        failures.append("stackCases '\(name)': no whole-file step to keep the original of")
                    }
                } else if value == "foreignKeptOriginal" {
                    // A kept original left under the next step's own label by
                    // another Mac or an earlier list.
                    let next: Int = try journal().read().highestSeq + 1
                    let foreignURL: URL = UndoSwap.besideURL(for: root.appendingPathComponent(pagePath), label: "\(next)-apply", role: "orig")
                    let foreignBytes: Data = Data("What another Mac's list kept.\n".utf8)
                    try foreignBytes.write(to: foreignURL)
                    foreignKept = (url: foreignURL, bytes: foreignBytes)
                } else if value == "makeTheKeptOriginalUnreadable" {
                    // There and unreadable just now, as a cloud placeholder
                    // not downloaded is.
                    for staged in UndoContractKinds.stagedLeftovers(in: root) where staged.hasSuffix("-orig") {
                        let keptURL: URL = root.appendingPathComponent(staged)
                        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: keptURL.path)
                        unreadableKeptOriginals.append(keptURL)
                    }
                } else if value == "changeTheKeptOriginal" {
                    for staged in UndoContractKinds.stagedLeftovers(in: root) where staged.hasSuffix("-orig") {
                        let keptURL: URL = root.appendingPathComponent(staged)
                        if case .file(let data) = UndoItem.read(at: keptURL) {
                            try (data + Data("A line added to the kept original.\n".utf8)).write(to: keptURL)
                        }
                    }
                } else if value == "begin:held" {
                    try beginHeld()
                } else if value == "finish:held" {
                    if let change = held.change {
                        try (change.after ?? Data()).write(to: root.appendingPathComponent(change.relativePath))
                        JournaledWrite.finish(seq: held.seq, with: .applied, phase: nil, reason: nil, in: journal(), mode: .live)
                    } else {
                        failures.append("stackCases '\(name)': no step was held to finish")
                    }
                } else {
                    failures.append("stackCases '\(name)': unknown call \(value)")
                }
            }
            _ = folderOfB

            let fold: UndoFold = try journal().read()
            let offer: UndoOffer = fold.offer(now: journal().now())
            if offer.head?.step.seq != int(testCase["head"]) {
                failures.append("stackCases '\(name)': head \(String(describing: offer.head?.step.seq))")
            }
            if offer.redoCandidate?.step.seq != int(testCase["redo"]) {
                failures.append("stackCases '\(name)': redo \(String(describing: offer.redoCandidate?.step.seq))")
            }
            var listed: [Int] = []
            for record in offer.offered {
                listed.append(record.step.seq)
            }
            if let wanted = intList(testCase["onTheList"]), listed != wanted {
                failures.append("stackCases '\(name)': offered \(listed), not \(wanted)")
            }
            if let count = int(testCase["onTheListCount"]) {
                if listed.count != count || listed.first != int(testCase["oldestOnTheList"]) {
                    failures.append("stackCases '\(name)': \(listed.count) offered from \(String(describing: listed.first))")
                }
            }
            if let wanted = intList(testCase["onTheDisk"]) {
                var onDisk: [Int] = []
                for record in fold.stepsOnTheList {
                    onDisk.append(record.step.seq)
                }
                if onDisk != wanted {
                    failures.append("stackCases '\(name)': on the disk \(onDisk), not \(wanted)")
                }
            }
            if let wanted = intList(testCase["physicallyPruned"]) {
                var pruned: [Int] = []
                for seq in fold.orderedSeqs where fold.records[seq]?.phase == .pruned {
                    pruned.append(seq)
                }
                if pruned != wanted {
                    failures.append("stackCases '\(name)': pruned \(pruned), not \(wanted)")
                }
            }
            if let expectLast = string(testCase["expectLast"]), expectLast != last {
                failures.append("stackCases '\(name)': the last call came to \(last), not \(expectLast)")
            }
            let clearings: [UndoEventLine] = try clearingLines(in: journal())
            if let cleared = string(testCase["cleared"]) {
                var reasons: [String] = []
                for line in clearings {
                    reasons.append(line.reason ?? "")
                }
                if !reasons.contains(cleared) {
                    failures.append("stackCases '\(name)': no clearing for \(cleared) (found \(reasons))")
                }
            }
            if let wantedSeq = int(testCase["clearedSeq"]), clearings.last?.seq != wantedSeq {
                failures.append("stackCases '\(name)': the clearing's seq is \(String(describing: clearings.last?.seq)), not \(wantedSeq)")
            }
            if let written = int(testCase["linesWritten"]), linesAfterTheDeploy - linesBeforeTheDeploy != written {
                failures.append("stackCases '\(name)': a deploy wrote \(linesAfterTheDeploy - linesBeforeTheDeploy) lines to the list, not \(written)")
            }
            if let wanted = intList(testCase["interrupted"]) {
                var interrupted: [Int] = []
                for seq in fold.orderedSeqs where fold.records[seq]?.phase == .interrupted {
                    interrupted.append(seq)
                }
                if interrupted != wanted {
                    failures.append("stackCases '\(name)': interrupted \(interrupted), not \(wanted)")
                }
            }
            if let kept = testCase["blobKept"] as? Bool {
                let present: Bool = foreignBlob != nil && journal().readBlob(sha: foreignBlob ?? "") != nil
                if present != kept {
                    failures.append("stackCases '\(name)': the newer version's blob kept is \(present)")
                }
            }
            if let wanted = string(testCase["markers"]), UndoContractKinds.markers(in: root) != wanted {
                failures.append("stackCases '\(name)': the markers are \(UndoContractKinds.markers(in: root)), not \(wanted)")
            }
            if let kept = testCase["folderKept"] as? Bool, UndoContractKinds.folderIsThere(in: root) != kept {
                failures.append("stackCases '\(name)': the folder is there: \(!kept)")
            }
            if let wanted = string(testCase["caseOnlyFolder"]), UndoContractKinds.caseOnlyFolder(in: root) != wanted {
                failures.append("stackCases '\(name)': the folder renamed in its capitals is \(UndoContractKinds.caseOnlyFolder(in: root)), not \(wanted)")
            }
            if let wanted = string(testCase["movedFolder"]), UndoContractKinds.movedFolder(in: root) != wanted {
                failures.append("stackCases '\(name)': the moved folder is \(UndoContractKinds.movedFolder(in: root)), not \(wanted)")
            }
            if let wanted = int(testCase["keptWhatItReplacedLines"]), keptWhatItReplacedLines != wanted {
                failures.append("stackCases '\(name)': \(keptWhatItReplacedLines) 'undo kept what it replaced' lines, not \(wanted)")
            }
            if testCase["foreignKeptOriginalUntouched"] as? Bool == true {
                if let foreignKept, UndoItem.read(at: foreignKept.url) != .file(foreignKept.bytes) {
                    failures.append("stackCases '\(name)': the other list's kept original was changed or removed")
                } else if foreignKept == nil {
                    failures.append("stackCases '\(name)': no other list's kept original was made")
                }
            }
            if let wanted = int(testCase["keptBesideThePage"]) {
                // Every file kept beside p1 under a staged name, any step's.
                let folder: URL = root.appendingPathComponent(pagePath).deletingLastPathComponent()
                let prefix: String = "." + URL(fileURLWithPath: pagePath).lastPathComponent + UndoSwap.stagedMarker
                var keptFiles: Int = 0
                for entry in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                    if entry.hasPrefix(prefix) && entry.hasSuffix("-orig") {
                        keptFiles += 1
                    }
                }
                if keptFiles != wanted {
                    failures.append("stackCases '\(name)': \(keptFiles) files kept beside the page, not \(wanted)")
                }
            }
            if let kept = testCase["keptOriginalLeft"] as? Bool {
                var beside: Bool = false
                for staged in UndoContractKinds.stagedLeftovers(in: root) {
                    if staged.hasSuffix("-orig") {
                        beside = true
                    } else {
                        failures.append("stackCases '\(name)': staged files left behind: \(staged)")
                    }
                }
                if beside != kept {
                    failures.append("stackCases '\(name)': a kept original beside p1 is \(beside)")
                }
            }
            if let wanted = string(testCase["cloudflareMarkers"]), UndoContractKinds.cloudflareMarkers(in: root) != wanted {
                failures.append("stackCases '\(name)': the second host's markers are \(UndoContractKinds.cloudflareMarkers(in: root)), not \(wanted)")
            }
            if let wanted = string(testCase["leftoverMarkers"]), UndoContractKinds.leftoverMarkers(in: root) != wanted {
                failures.append("stackCases '\(name)': the leftover's places are \(UndoContractKinds.leftoverMarkers(in: root)), not \(wanted)")
            }
            if let wanted = testCase["startsAtTheNextLogin"] as? [String], lastStartsAtTheNextLogin != wanted {
                failures.append("stackCases '\(name)': starts at the next login \(lastStartsAtTheNextLogin), not \(wanted)")
            }
            if let wanted = testCase["leftApart"] as? [String], lastLeftApart != wanted {
                failures.append("stackCases '\(name)': left apart \(lastLeftApart), not \(wanted)")
            }
            if let wanted = string(testCase["schoolYear"]), UndoContractKinds.schoolYear(in: root) != wanted {
                failures.append("stackCases '\(name)': the school year is \(UndoContractKinds.schoolYear(in: root) ?? "absent"), not \(wanted)")
            }
            if testCase["nothingMovedOutside"] as? Bool == true {
                let outsideNames: [String] = (try? FileManager.default.contentsOfDirectory(atPath: UndoContractKinds.outside(of: root).path)) ?? []
                if !outsideNames.isEmpty {
                    failures.append("stackCases '\(name)': moved out of the working folder: \(outsideNames)")
                }
            }
            let rederived: Int = takeTheRederived().count
            if let wanted = int(testCase["rederived"]), rederived != wanted {
                failures.append("stackCases '\(name)': the front page was re-derived \(rederived) times, not \(wanted)")
            }
            let leftovers: [String] = UndoContractKinds.stagedLeftovers(in: root)
            if !leftovers.isEmpty && testCase["keptOriginalLeft"] as? Bool != true {
                failures.append("stackCases '\(name)': staged files left behind: \(leftovers)")
            }
            if fold.ignoredEvents != 0 {
                failures.append("stackCases '\(name)': \(fold.ignoredEvents) ignored events")
            }
        }
        registerTheFrontPageMaintainer()
        return (cases: cases.count, failures: failures)
    }

    /// Appends a line exactly as given: the stand-in for a newer version.
    static func appendRaw(_ line: String, to journal: UndoJournal) throws {
        try journal.withLock { writer in
            let numbers: [Int] = try journal.segmentNumbers()
            let number: Int = numbers.last ?? 1
            let url: URL = journal.segmentURL(number: number)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            let handle: FileHandle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
            try handle.close()
            _ = writer
        }
    }

    static func lines(in journal: UndoJournal) throws -> [UndoEventLine] {
        var result: [UndoEventLine] = []
        for number in try journal.segmentNumbers() {
            let data: Data = (try? Data(contentsOf: journal.segmentURL(number: number))) ?? Data()
            for line in UndoJournal.completeLines(in: data) {
                if let event = UndoEventLine.decoded(from: line) {
                    result.append(event)
                }
            }
        }
        return result
    }

    static func lineCount(in journal: UndoJournal) throws -> Int {
        return try lines(in: journal).count
    }

    /// Every complete line in the journal, read or not.
    static func rawLineCount(in journal: UndoJournal) throws -> Int {
        var count: Int = 0
        for number in try journal.segmentNumbers() {
            let data: Data = (try? Data(contentsOf: journal.segmentURL(number: number))) ?? Data()
            count += UndoJournal.completeLines(in: data).count
        }
        return count
    }

    /// A `note` line, as a later version might write one: its `seq` the
    /// highest in the journal, an `about`, and keys this version does not
    /// know, one of them a `phase` no event has. Every reader passes over it.
    static func appendNote(to journal: UndoJournal) throws {
        let highest: Int = try journal.read().highestSeq
        let line: String = "{\"about\":\"aLaterRecord\",\"at\":\"\(UndoMoment.text(journal.now()))\",\"event\":\"note\",\"later\":{\"pages\":[1,2]},\"phase\":\"notOneOfTheThree\",\"reason\":7,\"seq\":\(highest),\"v\":1}"
        try appendRaw(line, to: journal)
    }

    /// One fragment of a section's published-pages record, as a deploy
    /// writes it (`contracts/file-formats.json` → `publishedPagesRecord`).
    static func writeAFragment(courseFolder: URL, section: Int, places: [String]) throws {
        let folder: URL = courseFolder
            .appendingPathComponent(".publish_state", isDirectory: true)
            .appendingPathComponent("section\(section).published-pages", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let object: [String: Any] = ["version": 1, "course": courseFolder.lastPathComponent, "section": section, "buildId": "b1", "places": places]
        let data: Data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: folder.appendingPathComponent("20261113T210405Z-netlify.json"))
    }

    static func clearingLines(in journal: UndoJournal) throws -> [UndoEventLine] {
        var found: [UndoEventLine] = []
        for event in try lines(in: journal) where event.event == UndoEventKind.cleared.rawValue {
            found.append(event)
        }
        return found
    }

    static func clearingReasons(in journal: UndoJournal) throws -> [String] {
        var reasons: [String] = []
        for event in try clearingLines(in: journal) {
            reasons.append(event.reason ?? "")
        }
        return reasons
    }

    // MARK: - undo.recoveryCases

    /// A process that never existed, standing for one that died.
    static let goneProcess: UndoProcess = UndoProcess(host: "", pid: 2_000_000_001, name: "gone", started: "1.000000")

    static let recoveryKeys: Set<String> = [
        "name", "work", "stopAt", "mode", "processAlive", "files", "phase", "head", "undo",
        "handEdit", "cleared", "pathsNamed", "moveFolderBeforeRecovery", "wholeFile",
        "contentRemovedBeforeRecovery", "fileInUseDuringRecovery", "anotherStepInFlight", "stepInFlight",
        "afterAnOrdinaryStep", "withAMove", "deployBeforeRecovery", "markers", "rederived", "why",
        "withATree", "withAPreference", "folderKept", "preference", "recoveredBy", "changeTheFolderSetAside", "keptAside", "somethingInItsPlace", "nextWrite", "ordinaryWriteOn",
        "halfDeleteTheGoneFolder", "visibleNameTaken", "recoveryStopsAfterTheTidy", "keptVisibleAs", "folderLines",
        "changeTheKeptOriginal", "keptOriginalsBeside", "fileInUseAtTheUndo", "leftLines", "editRacesTheSwap",
        "keptOriginalUnreadable", "contentInTheList", "contentCannotBeStored", "keptNoLongerInTheList",
        "keptOriginalsAfterTheTidy", "keptContentGoneAndCannotBeStored", "withAMovedFolder", "movedFolder", "keptCopyLeftInsideTheFolder",
    ]

    static func runRecoveryCases(under parent: URL) async throws -> (cases: Int, failures: [String]) {
        registerTheFrontPageMaintainer()
        let cases: [[String: Any]] = try undoBlock()["recoveryCases"] as? [[String: Any]] ?? []
        var failures: [String] = []
        var number: Int = 0
        defer {
            UndoKillPoints.hook = nil
            UndoKillPoints.fileInUseAtSwap = nil
        }
        for testCase in cases {
            number += 1
            let name: String = string(testCase["name"]) ?? "?"
            failures += unknownKeys(in: testCase, allowed: recoveryKeys, list: "recoveryCases", name: name)
            let place: (root: URL, journalFolder: URL) = try scratch(under: parent, named: "recovery-\(number)")
            let root: URL = place.root
            let first: String = "courses/TST1O/Section 1/Classes/A.md"
            let second: String = "courses/TST1O/Section 1/Classes/B.md"
            let pathOf: [String: String] = ["first": first, "second": second]
            let beforeText: String = "---\ntitle: A\npublish: false\n---\nBody.\n"
            try write(beforeText, to: first, in: root)
            try write(beforeText.replacingOccurrences(of: "title: A", with: "title: B"), to: second, in: root)
            let beforeHashes: [String?] = [hash(of: first, in: root), hash(of: second, in: root)]

            // Another, RUNNING process begins a step on a third page first,
            // and is still at work when recovery clears the list.
            var heldSeq: Int = 0
            var heldChange: UndoFileChange? = nil
            if testCase["anotherStepInFlight"] as? Bool == true {
                let third: String = "courses/TST1O/Section 1/Classes/C.md"
                try write(beforeText.replacingOccurrences(of: "title: A", with: "title: C"), to: third, in: root)
                let heldChanges: [UndoFileChange] = changes(setting: [(path: third, key: "publish", line: "publish: true")], in: root)
                let heldDraft: UndoStepDraft = draft(changes: heldChanges, root: root, action: "publishPages")
                heldSeq = try JournaledWrite.begin(heldDraft, ops: JournaledWrite.ops(for: heldDraft), in: UndoJournal(folderURL: place.journalFolder), mode: .live)
                heldChange = heldChanges.first
            }
            let workSeq: Int = heldSeq + 1

            let alive: Bool = testCase["processAlive"] as? Bool == true
            let dying: UndoJournal = UndoJournal(
                folderURL: place.journalFolder,
                process: goneProcess,
                processIsAlive: { process in process.pid != 2_000_000_001 || alive }
            )
            let mode: UndoMode = string(testCase["mode"]) == "shadow" ? .shadow : .live
            let work: String = string(testCase["work"]) ?? "step"
            let stopAt: UndoKillPoint = killPoint(named: string(testCase["stopAt"]) ?? "")
            let edits: [(path: String, key: String, line: String)] = [
                (path: first, key: "publish", line: "publish: true"),
                (path: second, key: "publish", line: "publish: true"),
            ]
            var stepChanges: [UndoFileChange] = changes(setting: edits, in: root)
            if testCase["wholeFile"] as? Bool == true {
                // The body changes too, so each page is one writeFile op
                // whose content is a blob.
                var wholeFileChanges: [UndoFileChange] = []
                for change in stepChanges {
                    let after: Data = (change.after ?? Data()) + Data("A line the step added.\n".utf8)
                    wholeFileChanges.append(UndoFileChange(relativePath: change.relativePath, before: change.before, after: after))
                }
                stepChanges = wholeFileChanges
            }
            let stepDraft: UndoStepDraft = draft(changes: stepChanges, root: root, action: "publishPages")
            var afterHashes: [String?] = []
            // U2: the same two pages, plus a rollover's marker moved aside
            // and the section's front page kept by its rule, as one step
            // through the door that plans its ops forward.
            let withAMove: Bool = testCase["withAMove"] as? Bool == true
            let withATree: Bool = testCase["withATree"] as? Bool == true
            let withAPreference: Bool = testCase["withAPreference"] as? Bool == true
            // U4b: the same two pages, plus a folder moved and a page inside
            // it edited at its new place (opKinds.wholeOps' order).
            let withAMovedFolder: Bool = testCase["withAMovedFolder"] as? Bool == true
            var folderOps: [UndoOp] = []
            if withAMovedFolder {
                for (fileName, content) in UndoContractKinds.mediaFiles {
                    try write(content, to: UndoContractKinds.mediaFolder + "/" + fileName, in: root)
                }
                if let listingSha = UndoTreeReading.read(at: root.appendingPathComponent(UndoContractKinds.mediaFolder)).listingSha {
                    folderOps.append(UndoOp.moveFolder(from: UndoContractKinds.mediaFolder, to: UndoContractKinds.renamedFolder, listingSha: listingSha))
                    folderOps.append(UndoOp.replaceText(
                        path: UndoContractKinds.renamedFolder + "/a.md", before: "old", after: "new", contextBefore: "Line one: ", contextAfter: ".\n"
                    ))
                }
            }
            let places: UndoMemoryPlaces = UndoMemoryPlaces()
            _ = places.write(UndoContractKinds.preference, .string("a"))
            var treeBlobs: [Data] = []
            var treeOp: UndoOp? = nil
            if withATree {
                for (path, content) in UndoContractKinds.extraFiles {
                    try write(content, to: UndoContractKinds.extraFolder + "/" + path, in: root)
                }
                if case .tree(let listing, let contents) = UndoTreeReading.read(at: root.appendingPathComponent(UndoContractKinds.extraFolder), keepingContents: true) {
                    treeBlobs.append(listing.data)
                    for (_, data) in contents {
                        treeBlobs.append(data)
                    }
                    treeOp = UndoOp.tree(.removeTree, path: UndoContractKinds.extraFolder, listing: listing)
                }
            }
            func makeTheStep() -> JournaledWriteOutcome {
                if !withAMove && !withATree && !withAPreference && !withAMovedFolder {
                    return JournaledWrite.perform(stepDraft, in: dying, mode: mode)
                }
                var ops: [UndoOp] = []
                var blobs: [Data] = []
                for change in stepChanges {
                    for op in JournaledWrite.ops(for: change) {
                        ops.append(op)
                        if op.knownKind == .writeFile {
                            if let before = change.before {
                                blobs.append(before)
                            }
                            if let after = change.after {
                                blobs.append(after)
                            }
                        }
                    }
                }
                if withAPreference {
                    ops.append(UndoOp.external(target: UndoContractKinds.preference, before: .string("a"), after: .string("b")))
                }
                if let treeOp {
                    ops.append(treeOp)
                    for blob in treeBlobs {
                        blobs.append(blob)
                    }
                }
                if withAMove || withATree {
                    ops.append(UndoOp.moveFile(
                        from: UndoContractKinds.markerFrom, to: UndoContractKinds.markerTo,
                        sha: UndoHash.sha256(of: Data(UndoContractKinds.oldMarker.utf8))
                    ))
                }
                for folderOp in folderOps {
                    ops.append(folderOp)
                }
                if withAMove {
                    ops.append(UndoOp.recompute(path: "courses/TST1O/Section 1/index.md", maintainer: "sectionFrontPage", section: 1))
                }
                let opsDraft: UndoOpsDraft = UndoContractKinds.draft(ops: ops, blobs: blobs, root: root, action: "rollOver")
                return JournaledWrite.perform(ops: opsDraft, in: dying, mode: mode, places: places)
            }
            if withAMove || withATree {
                try write(UndoContractKinds.oldMarker, to: UndoContractKinds.markerFrom, in: root)
            }

            let racedPage: String? = string(testCase["editRacesTheSwap"])
            if work == "step", let racedPage {
                // Another program edits the page IN PLACE between the swap's
                // re-read and its rename (into the inode the kept original
                // is a link to), and putting the original back fails: the
                // step answers part way and is left in flight.
                let racedName: String = ((pathOf[racedPage] ?? racedPage) as NSString).lastPathComponent
                UndoKillPoints.beforeTheRename = { _, url in
                    guard url.lastPathComponent == racedName, let handle = try? FileHandle(forWritingTo: url) else {
                        return
                    }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: Data("Edited in Obsidian.\n".utf8))
                    try? handle.close()
                }
                UndoKillPoints.putBackFailsAt = { index in index == 0 }
                let outcome: JournaledWriteOutcome = makeTheStep()
                UndoKillPoints.beforeTheRename = nil
                UndoKillPoints.putBackFailsAt = nil
                guard case .leftPartWay = outcome else {
                    failures.append("recoveryCases '\(name)': the step was not left part way (\(outcome))")
                    continue
                }
                for change in stepDraft.changes {
                    afterHashes.append(UndoHash.sha256(ofOptional: change.after))
                }
            } else if work == "step" {
                UndoKillPoints.hook = { point in point == stopAt }
                let outcome: JournaledWriteOutcome = makeTheStep()
                UndoKillPoints.hook = nil
                if outcome != .stoppedByATest {
                    failures.append("recoveryCases '\(name)': the step was not stopped (\(outcome))")
                }
                for change in stepDraft.changes {
                    afterHashes.append(UndoHash.sha256(ofOptional: change.after))
                }
            } else {
                _ = makeTheStep()
                afterHashes = [hash(of: first, in: root), hash(of: second, in: root)]
                if work == "redo" {
                    _ = dying.undoNewest(resolveRoot: { _ in root }, places: places)
                }
                UndoKillPoints.hook = { point in point == stopAt }
                let outcome: UndoOutcome = work == "undo"
                    ? dying.undoNewest(resolveRoot: { _ in root }, places: places)
                    : dying.redoNewest(resolveRoot: { _ in root }, places: places)
                UndoKillPoints.hook = nil
                if outcome != .stoppedByATest {
                    failures.append("recoveryCases '\(name)': the \(work) was not stopped (\(outcome))")
                }
            }
            if let page = string(testCase["handEdit"]), let path = pathOf[page] {
                try handEdit("sameLine", at: path, in: root)
            }
            let asLeft: [String?] = [hash(of: first, in: root), hash(of: second, in: root)]
            let reachable: Bool = testCase["moveFolderBeforeRecovery"] as? Bool != true
            let resolveRoot: (UndoWorkingFolder) -> URL? = { _ in reachable ? root : nil }
            if testCase["contentRemovedBeforeRecovery"] as? Bool == true {
                try FileManager.default.removeItem(at: dying.contentFolderURL)
            }
            var unreadableKept: [URL] = []
            defer {
                for keptURL in unreadableKept {
                    let mode: Int = keptURL == dying.contentFolderURL ? 0o755 : 0o644
                    try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: keptURL.path)
                }
            }
            if testCase["contentCannotBeStored"] as? Bool == true {
                // The list's content folder, there and taking no new file.
                let contentURL: URL = dying.contentFolderURL
                if UndoItem.read(at: contentURL) == .absent {
                    try FileManager.default.createDirectory(at: contentURL, withIntermediateDirectories: true)
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: contentURL.path)
                unreadableKept.append(contentURL)
            }
            var foldersMadeReadOnly: [URL] = []
            defer {
                for folder in foldersMadeReadOnly {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
                }
            }
            if let page = string(testCase["keptContentGoneAndCannotBeStored"]), let path = pathOf[page] {
                // Only the content a page's kept originals hold is gone from
                // the list, and the list's folder for it takes no new file;
                // every other blob is still there (the second review of
                // U3c, MEDIUM).
                let place: URL = root.appendingPathComponent(path)
                let folder: URL = place.deletingLastPathComponent()
                let prefix: String = "." + place.lastPathComponent + UndoSwap.stagedMarker
                for staged in try FileManager.default.contentsOfDirectory(atPath: folder.path)
                where staged.hasPrefix(prefix) && staged.hasSuffix("-orig") {
                    guard case .file(let data) = UndoItem.read(at: folder.appendingPathComponent(staged)) else {
                        continue
                    }
                    let blobURL: URL = dying.blobURL(sha: UndoHash.sha256(of: data))
                    if UndoItem.read(at: blobURL) != .absent {
                        try FileManager.default.removeItem(at: blobURL)
                    }
                    let prefixFolder: URL = blobURL.deletingLastPathComponent()
                    if UndoItem.read(at: prefixFolder) == .absent {
                        try FileManager.default.createDirectory(at: prefixFolder, withIntermediateDirectories: true)
                    }
                    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: prefixFolder.path)
                    foldersMadeReadOnly.append(prefixFolder)
                }
                if foldersMadeReadOnly.isEmpty {
                    failures.append("recoveryCases '\(name)': no kept original beside \(page) whose content to take away")
                }
            }
            if testCase["keptOriginalUnreadable"] as? Bool == true {
                // A kept original that is there and cannot be read just now,
                // as a cloud placeholder not downloaded cannot.
                for staged in UndoContractKinds.stagedLeftovers(in: root) where staged.hasSuffix("-orig") {
                    let keptURL: URL = root.appendingPathComponent(staged)
                    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: keptURL.path)
                    unreadableKept.append(keptURL)
                }
                if unreadableKept.isEmpty {
                    failures.append("recoveryCases '\(name)': no kept original to make unreadable")
                }
            }
            if testCase["changeTheKeptOriginal"] as? Bool == true {
                // A kept original that no longer hashes to what the journal
                // recorded for its page.
                var changed: Int = 0
                for staged in UndoContractKinds.stagedLeftovers(in: root) where staged.hasSuffix("-orig") {
                    let keptURL: URL = root.appendingPathComponent(staged)
                    if case .file(let data) = UndoItem.read(at: keptURL) {
                        try (data + Data("A line added to the kept original.\n".utf8)).write(to: keptURL)
                        changed += 1
                    }
                }
                if changed == 0 {
                    failures.append("recoveryCases '\(name)': no kept original to change")
                }
            }
            if testCase["changeTheFolderSetAside"] as? Bool == true {
                // A file saved into the teacher's folder while the dead
                // process had it set aside.
                let aside: URL = UndoSwap.besideURL(for: root.appendingPathComponent(UndoContractKinds.extraFolder), label: "\(workSeq)-apply", role: "orig")
                try Data("saved while it was aside\n".utf8).write(to: aside.appendingPathComponent("new.md"))
            }
            if testCase["somethingInItsPlace"] as? Bool == true {
                try write("someone else's\n", to: UndoContractKinds.extraFolder + "/other.md", in: root)
            }
            if testCase["halfDeleteTheGoneFolder"] as? Bool == true {
                // As a delete that died part way leaves the folder it renamed
                // to its `-gone` name: one of its files already gone.
                let parentFolder: URL = root.appendingPathComponent(UndoContractKinds.extraFolder).deletingLastPathComponent()
                var halfDeleted: Bool = false
                for name in (try? FileManager.default.contentsOfDirectory(atPath: parentFolder.path)) ?? [] where name.hasSuffix("-gone") {
                    try FileManager.default.removeItem(at: parentFolder.appendingPathComponent(name).appendingPathComponent("a.md"))
                    halfDeleted = true
                }
                if !halfDeleted {
                    failures.append("recoveryCases '\(name)': no folder under its -gone name to half delete")
                }
            }
            if testCase["keptCopyLeftInsideTheFolder"] as? Bool == true {
                // As a tidy that could not remove it leaves it: the undo's
                // kept copy of a.md, inside the folder moved back (U4b).
                let page: URL = root.appendingPathComponent(UndoContractKinds.mediaFolder + "/a.md")
                let held: String = (UndoContractKinds.mediaFiles["a.md"] ?? "").replacingOccurrences(of: "Line one: old.", with: "Line one: new.")
                try Data(held.utf8).write(to: UndoSwap.besideURL(for: page, label: "\(workSeq)-undo", role: "orig"))
            }
            if testCase["visibleNameTaken"] as? Bool == true {
                try write("earlier\n", to: UndoContractKinds.extraFolder + " (kept by Undo)/earlier.md", in: root)
            }
            if testCase["deployBeforeRecovery"] as? Bool == true {
                // A deploy wrote a new marker in the place the move emptied.
                try? FileManager.default.removeItem(at: root.appendingPathComponent(UndoContractKinds.markerFrom))
                try write(UndoContractKinds.newMarker, to: UndoContractKinds.markerFrom, in: root)
            }
            _ = takeTheRederived()
            var folderLines: Int = 0
            let trailHookBefore = UndoTrailHook.foundAFolderSetAsideLine
            UndoTrailHook.foundAFolderSetAsideLine = { _, _, _, _, _, _ in
                folderLines += 1
            }
            var keptNamedOnTheTrail: [String] = []
            var couldNotPutBackLines: Int = 0
            let couldNotPutBackHookBefore = UndoTrailHook.couldNotPutBackLine
            UndoTrailHook.couldNotPutBackLine = { _, _, _, _, keptOriginals in
                couldNotPutBackLines += 1
                keptNamedOnTheTrail += keptOriginals
            }
            var keptAsNoLongerInTheList: [String] = []
            let keptAnOriginalHookBefore = UndoTrailHook.keptAnOriginalLine
            UndoTrailHook.keptAnOriginalLine = { _, _, _, keptOriginals, noLongerInTheList in
                couldNotPutBackLines += 1
                keptNamedOnTheTrail += keptOriginals
                keptAsNoLongerInTheList += noLongerInTheList
            }
            var leftLines: Int = 0
            let leftHookBefore = UndoTrailHook.leftNewestLine
            UndoTrailHook.leftNewestLine = { _, _, _, _ in
                leftLines += 1
            }
            defer {
                UndoTrailHook.foundAFolderSetAsideLine = trailHookBefore
                UndoTrailHook.couldNotPutBackLine = couldNotPutBackHookBefore
                UndoTrailHook.keptAnOriginalLine = keptAnOriginalHookBefore
                UndoTrailHook.leftNewestLine = leftHookBefore
            }

            // Another process, which sees the first as gone, runs recovery.
            let survivor: UndoJournal = UndoJournal(
                folderURL: place.journalFolder,
                processIsAlive: { process in process.pid != 2_000_000_001 || alive }
            )
            if testCase["fileInUseDuringRecovery"] as? Bool == true {
                UndoKillPoints.fileInUseAtSwap = { _ in true }
            }
            let recoveredBy: String = string(testCase["recoveredBy"]) ?? "recovery"
            let otherPage: String = "courses/TST1O/Section 1/Classes/C.md"
            if recoveredBy != "recovery" {
                try write(beforeText.replacingOccurrences(of: "title: A", with: "title: C"), to: otherPage, in: root)
            }
            if recoveredBy == "theNextWrite" {
                // The next write through the app's door for ops, which
                // recovers and re-derives before it begins.
                let content: Data = UndoItem.read(at: root.appendingPathComponent(otherPage)).data ?? Data()
                let next: UndoOp = UndoOp.moveFile(from: otherPage, to: otherPage + ".moved", sha: UndoHash.sha256(of: content))
                _ = await JournaledWrite.performAndRederive(
                    ops: UndoContractKinds.draft(ops: [next], blobs: [], root: root, action: "rollOver"),
                    in: survivor, mode: .live, places: places
                )
            } else if recoveredBy == "anOrdinaryWrite" {
                // A write through U1's door, whose recovery cannot re-derive:
                // it refuses while the step waits for one that will.
                let onPage: String = string(testCase["ordinaryWriteOn"]) == "first" ? first : otherPage
                let thirdChanges: [UndoFileChange] = changes(setting: [(path: onPage, key: "title", line: "title: Written over")], in: root)
                let written: JournaledWriteOutcome = JournaledWrite.perform(draft(changes: thirdChanges, root: root, action: "publishPages"), in: survivor, mode: .live)
                let word: String = written == .anotherChangeIsUnderWay ? "anotherChangeIsUnderWay" : (written == .changedNothing ? "changedNothing" : "\(written)")
                if let wanted = string(testCase["nextWrite"]), wanted != word {
                    failures.append("recoveryCases '\(name)': the ordinary write came to \(word), not \(wanted)")
                }
            } else if mode == .live {
                // As the app recovers: under the lock, then the re-derivation
                // of what it settled, awaited outside it.
                if testCase["recoveryStopsAfterTheTidy"] as? Bool == true {
                    // A recovery that dies once it has tidied, before it
                    // writes to the list; then the next one.
                    UndoKillPoints.hook = { point in point == .afterRecoveryTidied }
                    await UndoRecovery.recoverAndRederive(survivor, resolveRoot: { _ in reachable ? root : nil }, places: places)
                    UndoKillPoints.hook = nil
                    let stands: String = (try survivor.read()).records[workSeq]?.phase.rawValue ?? "missing"
                    if stands == UndoStepPhase.interrupted.rawValue {
                        failures.append("recoveryCases '\(name)': the stopped recovery wrote to the list (\(stands))")
                    }
                    if let pages = testCase["keptOriginalsAfterTheTidy"] as? [String] {
                        // The tidy before the plan kept each named page's
                        // kept original, though the list gives its bytes.
                        var keptPlaces: [String] = []
                        for staged in UndoContractKinds.stagedLeftovers(in: root) {
                            let stagedName: String = (staged as NSString).lastPathComponent
                            if stagedName.hasSuffix("-orig"), let keptPlace = UndoSwap.placeOfStagedName(stagedName) {
                                keptPlaces.append(keptPlace)
                            }
                        }
                        var wantedPlaces: [String] = []
                        for page in pages {
                            wantedPlaces.append(((pathOf[page] ?? page) as NSString).lastPathComponent)
                        }
                        if keptPlaces.sorted() != wantedPlaces.sorted() {
                            failures.append("recoveryCases '\(name)': the tidy before the plan left kept originals beside \(keptPlaces), not \(wantedPlaces)")
                        }
                    }
                }
                await UndoRecovery.recoverAndRederive(survivor, resolveRoot: { _ in reachable ? root : nil }, places: places)
            } else {
                try survivor.withLock { writer in
                    UndoRecovery.run(writer, mode: mode, resolveRoot: resolveRoot)
                }
            }
            UndoKillPoints.fileInUseAtSwap = nil
            let rederivedByRecovery: Int = takeTheRederived().count
            if let wanted = int(testCase["rederived"]), rederivedByRecovery != wanted {
                failures.append("recoveryCases '\(name)': recovery re-derived the front page \(rederivedByRecovery) times, not \(wanted)")
            }
            if let wanted = string(testCase["markers"]), UndoContractKinds.markers(in: root) != wanted {
                failures.append("recoveryCases '\(name)': the markers are \(UndoContractKinds.markers(in: root)), not \(wanted)")
            }
            if let kept = testCase["folderKept"] as? Bool, UndoContractKinds.folderIsThere(in: root) != kept {
                failures.append("recoveryCases '\(name)': the folder is there: \(!kept)")
            }
            if let wanted = string(testCase["movedFolder"]), UndoContractKinds.movedFolder(in: root) != wanted {
                failures.append("recoveryCases '\(name)': the moved folder is \(UndoContractKinds.movedFolder(in: root)), not \(wanted)")
            }
            if let wanted = string(testCase["preference"]), places.read(UndoContractKinds.preference) != .value(.string(wanted)) {
                failures.append("recoveryCases '\(name)': the preference is \(places.read(UndoContractKinds.preference)), not \(wanted)")
            }
            if let wanted = string(testCase["keptVisibleAs"]) {
                let keptFile: URL = root.appendingPathComponent(wanted).appendingPathComponent("a.md")
                if !FileManager.default.fileExists(atPath: keptFile.path) {
                    failures.append("recoveryCases '\(name)': the folder is not kept as \(wanted)")
                }
            }
            if let wanted = int(testCase["folderLines"]), folderLines != wanted {
                failures.append("recoveryCases '\(name)': \(folderLines) 'undo found a folder set aside' lines, not \(wanted)")
            }
            let leftovers: [String] = UndoContractKinds.stagedLeftovers(in: root)
            let keptBeside: [String]? = testCase["keptOriginalsBeside"] as? [String]
            if let keptBeside {
                // Exactly one kept original beside each page named, nothing
                // else staged, and the trail line names exactly those.
                var wantedFolders: [String] = []
                for page in keptBeside {
                    wantedFolders.append(((pathOf[page] ?? page) as NSString).lastPathComponent)
                }
                var foundPages: [String] = []
                var foundNames: [String] = []
                for staged in leftovers {
                    let stagedName: String = (staged as NSString).lastPathComponent
                    if stagedName.hasSuffix("-orig"), let place = UndoSwap.placeOfStagedName(stagedName) {
                        foundPages.append(place)
                        foundNames.append(stagedName)
                    } else {
                        foundPages.append(stagedName)
                    }
                }
                if foundPages.sorted() != wantedFolders.sorted() {
                    failures.append("recoveryCases '\(name)': kept beside \(foundPages), not \(wantedFolders) (\(leftovers))")
                }
                if couldNotPutBackLines != 1 || keptNamedOnTheTrail.sorted() != foundNames.sorted() {
                    failures.append("recoveryCases '\(name)': the trail line naming kept originals named \(keptNamedOnTheTrail) in \(couldNotPutBackLines) lines, on the disk \(foundNames)")
                }
            }
            if let noLonger = testCase["keptNoLongerInTheList"] as? Bool {
                // Why each kept original is said to be kept: every one is
                // exactly what the list recorded (true), or none is (false).
                let wanted: [String] = noLonger ? keptNamedOnTheTrail.sorted() : []
                if keptAsNoLongerInTheList.sorted() != wanted || keptNamedOnTheTrail.isEmpty {
                    failures.append("recoveryCases '\(name)': said as no longer in the list \(keptAsNoLongerInTheList) of \(keptNamedOnTheTrail)")
                }
            }
            if let wanted = testCase["keptAside"] as? Bool {
                let stillAside: Bool = !leftovers.isEmpty
                if stillAside != wanted {
                    failures.append("recoveryCases '\(name)': a folder kept aside is \(stillAside) (\(leftovers))")
                }
            } else if withATree && !leftovers.isEmpty {
                failures.append("recoveryCases '\(name)': staged items left: \(leftovers)")
            }
            if let heldChange {
                try (heldChange.after ?? Data()).write(to: root.appendingPathComponent(heldChange.relativePath))
                JournaledWrite.finish(seq: heldSeq, with: .applied, phase: nil, reason: nil, in: UndoJournal(folderURL: place.journalFolder), mode: .live)
            }

            let now: [String?] = [hash(of: first, in: root), hash(of: second, in: root)]
            var wanted: [String?]? = nil
            switch string(testCase["files"]) ?? "" {
            case "before":
                wanted = beforeHashes
            case "after":
                wanted = afterHashes
            case "asLeft":
                wanted = asLeft
            case "firstBeforeSecondEdited":
                wanted = [beforeHashes[0], asLeft[1]]
            case "secondAfterFirstEdited":
                wanted = [asLeft[0], afterHashes[1]]
            case "unchecked":
                wanted = nil
            default:
                failures.append("recoveryCases '\(name)': files '\(string(testCase["files"]) ?? "")' is not a value this replay knows")
            }
            if let wanted, now != wanted {
                failures.append("recoveryCases '\(name)': the files are not \(string(testCase["files"]) ?? "?")")
            }
            let fold: UndoFold = try survivor.read()
            let phase: String = fold.records[workSeq]?.phase.rawValue ?? "missing"
            if phase != string(testCase["phase"]) {
                failures.append("recoveryCases '\(name)': the step is \(phase), not \(string(testCase["phase"]) ?? "?")")
            }
            if let wanted = string(testCase["stepInFlight"]) {
                let heldPhase: String = fold.records[heldSeq]?.phase.rawValue ?? "missing"
                if heldSeq == 0 || heldPhase != wanted {
                    failures.append("recoveryCases '\(name)': the other process's step is \(heldPhase), not \(wanted)")
                }
            }
            let offer: UndoOffer = fold.offer(now: Date())
            if testCase.keys.contains("head") && offer.head?.step.seq != int(testCase["head"]) {
                failures.append("recoveryCases '\(name)': head \(String(describing: offer.head?.step.seq))")
            }
            if let cleared = string(testCase["cleared"]) {
                if !(try clearingReasons(in: survivor)).contains(cleared) {
                    failures.append("recoveryCases '\(name)': no clearing for \(cleared)")
                }
            }
            if let named = testCase["pathsNamed"] as? [String] {
                var wantedPaths: [String] = []
                for page in named {
                    wantedPaths.append(pathOf[page] ?? page)
                }
                var foundPaths: [String] = []
                for line in try lines(in: survivor) where line.event == UndoEventKind.interrupted.rawValue {
                    foundPaths = line.paths ?? []
                }
                if foundPaths != wantedPaths {
                    failures.append("recoveryCases '\(name)': the interrupted line names \(foundPaths)")
                }
            }
            if let wanted = string(testCase["afterAnOrdinaryStep"]) {
                // Another step, at once, through the door: the ordinary path,
                // where a refused put-back waits for its time.
                let third: String = "courses/TST1O/Section 1/Classes/C.md"
                try write(beforeText.replacingOccurrences(of: "title: A", with: "title: C"), to: third, in: root)
                let thirdChanges: [UndoFileChange] = changes(setting: [(path: third, key: "publish", line: "publish: true")], in: root)
                _ = JournaledWrite.perform(draft(changes: thirdChanges, root: root, action: "publishPages"), in: survivor, mode: .live)
                let stands: String = (try survivor.read()).records[workSeq]?.phase.rawValue ?? "missing"
                if stands != wanted {
                    failures.append("recoveryCases '\(name)': after an ordinary step the step is \(stands), not \(wanted)")
                }
            }
            if let undo = string(testCase["undo"]) {
                if testCase["fileInUseAtTheUndo"] as? Bool == true {
                    UndoKillPoints.fileInUseAtSwap = { _ in true }
                }
                let outcome: String = outcomeWord(survivor.undoNewest(resolveRoot: resolveRoot))
                UndoKillPoints.fileInUseAtSwap = nil
                if outcome != undo {
                    failures.append("recoveryCases '\(name)': undo came to \(outcome), not \(undo)")
                }
            }
            if let wanted = int(testCase["leftLines"]), leftLines != wanted {
                failures.append("recoveryCases '\(name)': \(leftLines) 'undo refused for a change left part way' lines, not \(wanted)")
            }
            if let pages = testCase["contentInTheList"] as? [String] {
                // Both of each named page's recorded contents are in the
                // list again: what the kept original gave, and what the page
                // held as it was put back.
                for page in pages {
                    let index: Int = page == "second" ? 1 : 0
                    for sha in [beforeHashes[index], afterHashes.count > index ? afterHashes[index] : nil] {
                        if let sha, survivor.readBlob(sha: sha) == nil {
                            failures.append("recoveryCases '\(name)': the list does not hold \(page)'s content \(sha.prefix(8))")
                        }
                    }
                }
            }
            if mode == .live && !alive && reachable && testCase["keptAside"] as? Bool != true && keptBeside == nil
                && testCase["keptOriginalUnreadable"] as? Bool != true && staysBeside(root) {
                failures.append("recoveryCases '\(name)': recovery left a staged file beside a page")
            }
        }
        return (cases: cases.count, failures: failures)
    }

    static func killPoint(named name: String) -> UndoKillPoint {
        if name.hasPrefix("beforeSwap:") {
            return .beforeSwap(Int(name.dropFirst("beforeSwap:".count)) ?? 0)
        }
        switch name {
        case "afterBegin":
            return .afterBegin
        case "beforeApplied":
            return .beforeApplied
        case "afterUndoing":
            return .afterUndoing
        case "beforeUndone":
            return .beforeUndone
        case "afterRedoing":
            return .afterRedoing
        case "whileDeletingAFolder":
            return .whileDeletingAFolder
        default:
            return .beforeRedone
        }
    }

    // MARK: - undo.deployedCases

    static let deployedKeys: Set<String> = [
        "name", "moves", "changesMoreThanVisibility", "record", "destinations", "siteMarkers", "answer", "why",
    ]

    /// Ruling 19's question, as data: does a website show what the move
    /// takes back (`UndoWebsite.answer`)?
    static func runDeployedCases() throws -> (cases: Int, failures: [String]) {
        let cases: [[String: Any]] = try undoBlock()["deployedCases"] as? [[String: Any]] ?? []
        var failures: [String] = []
        for testCase in cases {
            let name: String = string(testCase["name"]) ?? "?"
            failures += unknownKeys(in: testCase, allowed: deployedKeys, list: "deployedCases", name: name)
            var moves: [UndoWebsite.PageMove] = []
            for move in testCase["moves"] as? [[String: Any]] ?? [] {
                guard let path = string(move["path"]), let place = UndoWebsite.place(ofPath: path),
                      let before = move["visibleBefore"] as? Bool, let after = move["visibleAfter"] as? Bool else {
                    failures.append("deployedCases '\(name)': a move this replay cannot read")
                    continue
                }
                moves.append(UndoWebsite.PageMove(place: place, visibleBeforeTheMove: before, visibleAfterTheMove: after))
            }
            var record: [UndoWebsite.Fragment] = []
            for fragment in testCase["record"] as? [[String: Any]] ?? [] {
                record.append(UndoWebsite.Fragment(name: string(fragment["name"]) ?? "", places: fragment["places"] as? [String]))
            }
            guard let destinations = testCase["destinations"] as? [String] else {
                failures.append("deployedCases '\(name)': no destinations")
                continue
            }
            var siteMarkers: Set<String> = []
            for destination in testCase["siteMarkers"] as? [String] ?? [] {
                siteMarkers.insert(destination)
            }
            let answer: UndoWebsite.Answer = UndoWebsite.answer(
                moves: moves,
                changesMoreThanVisibility: testCase["changesMoreThanVisibility"] as? Bool == true,
                record: record,
                destinations: destinations,
                siteMarkers: siteMarkers
            )
            if answer.rawValue != string(testCase["answer"]) {
                failures.append("deployedCases '\(name)': \(answer.rawValue), not \(string(testCase["answer"]) ?? "?")")
            }
        }
        return (cases: cases.count, failures: failures)
    }

    // MARK: - undo.stepCases

    static let stepKeys: Set<String> = [
        "name", "pages", "step", "handEdit", "undo", "named", "others", "files", "phase", "fileInUseAtSwap",
        "stagingFailsAt", "why",
    ]

    static func runStepCases(under parent: URL) throws -> (cases: Int, failures: [String]) {
        registerTheFrontPageMaintainer()
        let cases: [[String: Any]] = try undoBlock()["stepCases"] as? [[String: Any]] ?? []
        var failures: [String] = []
        var number: Int = 0
        defer {
            UndoKillPoints.fileInUseAtSwap = nil
            UndoKillPoints.stagingWriteFailsAt = nil
        }
        for testCase in cases {
            number += 1
            let name: String = string(testCase["name"]) ?? "?"
            failures += unknownKeys(in: testCase, allowed: stepKeys, list: "stepCases", name: name)
            guard let pageCount = int(testCase["pages"]), pageCount > 0 else {
                failures.append("stepCases '\(name)': no number of pages")
                continue
            }
            let place: (root: URL, journalFolder: URL) = try scratch(under: parent, named: "steps-\(number)")
            let root: URL = place.root
            let stepKind: String = string(testCase["step"]) ?? "oneLine"
            if stepKind != "oneLine" && stepKind != "twoLines" {
                failures.append("stepCases '\(name)': step '\(stepKind)' is not a value this replay knows")
                continue
            }
            var paths: [String] = []
            var edits: [(path: String, key: String, line: String)] = []
            var twoLineChanges: [UndoFileChange] = []
            var index: Int = 1
            while index <= pageCount {
                let path: String = "courses/TST1O/Section 1/Classes/Page \(index).md"
                if stepKind == "twoLines" {
                    // The step takes `draft: true` away and adds
                    // `publish: false`: two line ops on one page.
                    let before: String = "---\ntitle: Page \(index)\ndraft: true\n---\nBody.\n"
                    let after: String = "---\ntitle: Page \(index)\npublish: false\n---\nBody.\n"
                    try write(before, to: path, in: root)
                    twoLineChanges.append(UndoFileChange(relativePath: path, before: Data(before.utf8), after: Data(after.utf8)))
                } else {
                    try write("---\ntitle: Page \(index)\npublish: false\n---\nBody.\n", to: path, in: root)
                    edits.append((path: path, key: "publish", line: "publish: true"))
                }
                paths.append(path)
                index += 1
            }
            let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
            let stepChanges: [UndoFileChange] = stepKind == "twoLines" ? twoLineChanges : changes(setting: edits, in: root)
            if stepKind == "twoLines" {
                for change in stepChanges {
                    var lineOps: Int = 0
                    for op in JournaledWrite.ops(for: change) where op.knownKind == .editLine {
                        lineOps += 1
                    }
                    if lineOps != 2 {
                        failures.append("stepCases '\(name)': the step on \(change.relativePath) is \(lineOps) line ops, not 2")
                    }
                }
            }
            _ = JournaledWrite.perform(draft(changes: stepChanges, root: root, action: "publishPages"), in: journal, mode: .live)
            let handEdit: String = string(testCase["handEdit"]) ?? ""
            var edited: [Int] = []
            var frontMatterRemoved: [Int] = []
            if handEdit == "line of page 2" {
                edited = [2]
            } else if handEdit == "lines of pages 1 and 3" {
                edited = [1, 3]
            } else if handEdit == "front matter of page 2 removed" {
                frontMatterRemoved = [2]
            } else if handEdit != "none" {
                failures.append("stepCases '\(name)': handEdit '\(handEdit)' is not a value this replay knows")
            }
            for page in edited {
                try UndoContractReplay.handEdit("sameLine", at: paths[page - 1], in: root)
            }
            for page in frontMatterRemoved {
                // The whole block, both fences included, taken out by hand:
                // only the body is left.
                try write("Body.\n", to: paths[page - 1], in: root)
            }
            var snapshot: [String?] = []
            for path in paths {
                snapshot.append(hash(of: path, in: root))
            }
            if let swapIndex = int(testCase["fileInUseAtSwap"]) {
                UndoKillPoints.fileInUseAtSwap = { candidate in candidate == swapIndex }
            }
            if let stagingIndex = int(testCase["stagingFailsAt"]) {
                UndoKillPoints.stagingWriteFailsAt = { candidate in candidate == stagingIndex }
            }
            let outcome: UndoOutcome = journal.undoNewest(resolveRoot: { _ in root })
            UndoKillPoints.fileInUseAtSwap = nil
            UndoKillPoints.stagingWriteFailsAt = nil
            if outcomeWord(outcome) != string(testCase["undo"]) {
                failures.append("stepCases '\(name)': undo came to \(outcomeWord(outcome))")
            }
            if let named = string(testCase["named"]) {
                let wantedPage: Int = Int(named.dropFirst("page ".count)) ?? 0
                var namedPath: String? = nil
                var others: Int? = nil
                if case .refused(.changedSince(let first, let count), _) = outcome {
                    namedPath = first
                    others = count
                }
                if case .refused(.fileIsInUse(let path), _) = outcome {
                    namedPath = path
                    others = 0
                }
                if case .refused(.couldNotWrite(let path), _) = outcome {
                    namedPath = path
                    others = 0
                }
                if wantedPage < 1 || wantedPage > paths.count || namedPath != paths[wantedPage - 1] {
                    failures.append("stepCases '\(name)': named \(namedPath ?? "nothing")")
                }
                if others != int(testCase["others"]) {
                    failures.append("stepCases '\(name)': \(String(describing: others)) others")
                }
            }
            var now: [String?] = []
            for path in paths {
                now.append(hash(of: path, in: root))
            }
            switch string(testCase["files"]) ?? "" {
            case "unchanged":
                if now != snapshot {
                    failures.append("stepCases '\(name)': files were written")
                }
            case "changed":
                if now == snapshot {
                    failures.append("stepCases '\(name)': no file was written")
                }
            default:
                failures.append("stepCases '\(name)': files '\(string(testCase["files"]) ?? "")' is not a value this replay knows")
            }
            if let phase = string(testCase["phase"]) {
                let fold: UndoFold = try journal.read()
                if fold.records[1]?.phase.rawValue != phase {
                    failures.append("stepCases '\(name)': the step is \(fold.records[1]?.phase.rawValue ?? "missing")")
                }
            }
            if staysBeside(root) {
                failures.append("stepCases '\(name)': a staged file was left beside a page")
            }
        }
        return (cases: cases.count, failures: failures)
    }

    // MARK: - Two writers, one process

    /// Two journals on one folder (each opens the lock itself), each making
    /// `stepsEach` steps on its own page from its own task at the same time.
    /// Every step must get its own number, each writer's numbers must rise,
    /// and nothing may be lost.
    static func twoWritersInOneProcess(under parent: URL, stepsEach: Int) async throws -> (steps: Int, failures: [String]) {
        let place: (root: URL, journalFolder: URL) = try scratch(under: parent, named: "two-writers")
        let root: URL = place.root
        let pages: [String] = ["courses/TST1O/Section 1/Classes/W1.md", "courses/TST1O/Section 1/Classes/W2.md"]
        for page in pages {
            try write("---\ntitle: W\npublish: false\n---\n", to: page, in: root)
        }
        let folder: URL = place.journalFolder
        var numbersByWriter: [[Int]] = []
        await withTaskGroup(of: [Int].self) { group in
            for page in pages {
                group.addTask {
                    return UndoContractReplay.writeSteps(count: stepsEach, onPage: page, root: root, journalFolder: folder)
                }
            }
            for await numbers in group {
                numbersByWriter.append(numbers)
            }
        }
        return (steps: stepsEach * 2, failures: try checkInterleaving(numbersByWriter, stepsEach: stepsEach, journalFolder: folder))
    }

    /// One writer's steps: flips its page's line `count` times, answering
    /// the step number of each.
    static func writeSteps(count: Int, onPage page: String, root: URL, journalFolder: URL) -> [Int] {
        let journal: UndoJournal = UndoJournal(folderURL: journalFolder)
        var numbers: [Int] = []
        var made: Int = 0
        while made < count {
            let line: String = made % 2 == 0 ? "publish: true" : "publish: false"
            let outcome: JournaledWriteOutcome = JournaledWrite.perform(
                draft(changes: changes(setting: [(path: page, key: "publish", line: line)], in: root), root: root, action: "publishPages"),
                in: journal, mode: .live
            )
            if case .applied(let seq) = outcome {
                numbers.append(seq)
            } else {
                numbers.append(-1)
            }
            made += 1
        }
        return numbers
    }

    static func checkInterleaving(_ numbersByWriter: [[Int]], stepsEach: Int, journalFolder: URL) throws -> [String] {
        var failures: [String] = []
        var all: Set<Int> = []
        for numbers in numbersByWriter {
            if numbers.count != stepsEach {
                failures.append("a writer made \(numbers.count) steps, not \(stepsEach)")
            }
            var previous: Int = 0
            for number in numbers {
                if number <= previous {
                    failures.append("a writer's step numbers did not rise: \(number) after \(previous)")
                }
                previous = number
                all.insert(number)
            }
        }
        let total: Int = stepsEach * numbersByWriter.count
        if all.count != total {
            failures.append("\(all.count) distinct step numbers for \(total) steps")
        }
        let fold: UndoFold = try UndoJournal(folderURL: journalFolder).read()
        if fold.records.count != total || fold.highestSeq != total {
            failures.append("the list holds \(fold.records.count) steps up to \(fold.highestSeq), not \(total)")
        }
        for (_, record) in fold.records where record.phase != .done && record.phase != .pruned {
            failures.append("step \(record.step.seq) is \(record.phase.rawValue)")
        }
        if fold.offer(now: Date()).offered.count != min(total, UndoSwitch.stepsKept) {
            failures.append("\(fold.offer(now: Date()).offered.count) offered, not \(min(total, UndoSwitch.stepsKept))")
        }
        if fold.unreadableLines != 0 || fold.ignoredEvents != 0 {
            failures.append("\(fold.unreadableLines) unreadable lines, \(fold.ignoredEvents) ignored events")
        }
        return failures
    }

    // MARK: - A torn last line

    static func tornLastLine(under parent: URL) throws -> [String] {
        var failures: [String] = []
        let place: (root: URL, journalFolder: URL) = try scratch(under: parent, named: "torn")
        let root: URL = place.root
        let page: String = "courses/TST1O/Section 1/Classes/T.md"
        try write("---\ntitle: T\npublish: false\n---\n", to: page, in: root)
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        _ = JournaledWrite.perform(draft(changes: changes(setting: [(path: page, key: "publish", line: "publish: true")], in: root), root: root, action: "publishPages"), in: journal, mode: .live)
        let before: UndoFold = try journal.read()

        let segment: URL = journal.segmentURL(number: 1)
        let handle: FileHandle = try FileHandle(forWritingTo: segment)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"v\":1,\"seq\":2,\"event\":\"beg".utf8))
        try handle.close()

        let torn: UndoFold = try journal.read()
        if torn != before {
            failures.append("a reader counted the torn line")
        }
        let outcome: JournaledWriteOutcome = JournaledWrite.perform(
            draft(changes: changes(setting: [(path: page, key: "publish", line: "publish: false")], in: root), root: root, action: "hidePages"),
            in: journal, mode: .live
        )
        if outcome != .applied(seq: 2) {
            failures.append("the next writer came to \(outcome), not step 2")
        }
        let data: Data = try Data(contentsOf: segment)
        if data.last != 0x0A {
            failures.append("the segment does not end in a line feed")
        }
        var parsed: Int = 0
        for line in UndoJournal.completeLines(in: data) {
            if UndoEventLine.decoded(from: line) == nil {
                failures.append("a line in the segment does not parse")
            } else {
                parsed += 1
            }
        }
        if parsed != 4 {
            failures.append("\(parsed) lines, not 4 (two begins, two applieds)")
        }
        return failures
    }

    // MARK: - A list that cannot be written

    /// Live: refused before anything changes. Shadow: the change goes ahead
    /// exactly as it would have, and one trail line says the list missed it.
    static func unwritableList(under parent: URL) throws -> [String] {
        var failures: [String] = []
        let place: (root: URL, journalFolder: URL) = try scratch(under: parent, named: "unwritable")
        let root: URL = place.root
        let page: String = "courses/TST1O/Section 1/Classes/U.md"
        try write("---\ntitle: U\npublish: false\n---\n", to: page, in: root)
        // A FILE where the list's folder would go: nothing can be made under it.
        try Data("not a folder".utf8).write(to: place.journalFolder)
        let blocked: UndoJournal = UndoJournal(folderURL: place.journalFolder.appendingPathComponent("undo"))
        let edits: [(path: String, key: String, line: String)] = [(path: page, key: "publish", line: "publish: true")]
        let before: String? = hash(of: page, in: root)

        let live: JournaledWriteOutcome = JournaledWrite.perform(draft(changes: changes(setting: edits, in: root), root: root, action: "publishPages"), in: blocked, mode: .live)
        if live != .couldNotRecordTheStep {
            failures.append("live: \(live), not couldNotRecordTheStep")
        }
        if hash(of: page, in: root) != before {
            failures.append("live: the page changed although the step was not recorded")
        }

        var trailLines: Int = 0
        let previousHook: ((String, String, Int?, UndoUnrecordedChange, String) -> Void)? = UndoTrailHook.couldNotRecordLine
        UndoTrailHook.couldNotRecordLine = { _, _, _, change, _ in
            if change == .wentAhead {
                trailLines += 1
            }
        }
        let shadow: JournaledWriteOutcome = JournaledWrite.perform(draft(changes: changes(setting: edits, in: root), root: root, action: "publishPages"), in: blocked, mode: .shadow)
        UndoTrailHook.couldNotRecordLine = previousHook
        if shadow != .appliedWithoutARecord {
            failures.append("shadow: \(shadow), not appliedWithoutARecord")
        }
        if hash(of: page, in: root) == before {
            failures.append("shadow: the page did not change")
        }
        if trailLines != 1 {
            failures.append("shadow: \(trailLines) trail lines, not 1")
        }
        return failures
    }

    // MARK: - The must-fail reference: today's whole-file compare

    /// `AssistUndoVerdict.of` as it stands at origin/dev
    /// (`Models/Assist/AssistChangeHistory.swift`, the skip path): a file
    /// is put back only when it is EXACTLY the whole text the change left,
    /// and left alone otherwise. Copied here as the reference the line check
    /// is measured against, so the case below shows the old code red.
    static func wholeFileVerdictOfToday(before: String?, after: String?, current: String?) -> String {
        if current == before {
            return "alreadyBack"
        }
        if current == after {
            return "putBack"
        }
        return "leftAlone"
    }

    /// "Publish, edit the body, undo": today's compare leaves the page alone
    /// (red), the journal's line check can undo it (green).
    static func publishEditBodyUndo() -> (today: String, journal: String) {
        let before: String = "---\ntitle: Day\npublish: false\n---\nBody.\n"
        let after: String = "---\ntitle: Day\npublish: true\n---\nBody.\n"
        let edited: String = after + "Written in Obsidian since.\n"
        let ops: [UndoOp] = JournaledWrite.ops(for: UndoFileChange(relativePath: "p.md", before: Data(before.utf8), after: Data(after.utf8)))
        var journal: String = "noOps"
        if let op = ops.first {
            let state: UndoOpState = UndoCheck.state(of: op, in: .file(Data(edited.utf8)))
            journal = UndoCheck.verdict(for: state, direction: .backward).rawValue
        }
        return (today: wholeFileVerdictOfToday(before: before, after: after, current: edited), journal: journal)
    }
}
