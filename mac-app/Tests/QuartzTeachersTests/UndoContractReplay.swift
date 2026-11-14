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

    static func hash(of relativePath: String, in root: URL) -> String? {
        guard let data = UndoItem.read(at: root.appendingPathComponent(relativePath)).data else {
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
                    if case .undone(let seq) = outcome, seq != int(call["seq"]) {
                        failures.append("\(where_): undid \(seq), not \(int(call["seq"]) ?? -1)")
                    }
                    if case .redone(let seq) = outcome, seq != int(call["seq"]) {
                        failures.append("\(where_): redid \(seq), not \(int(call["seq"]) ?? -1)")
                    }
                    if case .refused(.changedSince(let first, let others), let cleared) = outcome {
                        if first != pathOfPage[string(call["page"]) ?? ""] {
                            failures.append("\(where_): named \(first), not page \(string(call["page"]) ?? "?")")
                        }
                        if others != int(call["others"]) {
                            failures.append("\(where_): \(others) others, not \(int(call["others"]) ?? -1)")
                        }
                        if !cleared {
                            failures.append("\(where_): the refusal did not clear the list (ruling 13)")
                        }
                    }
                case "handEdit":
                    try handEdit(string(call["kind"]) ?? "", at: pathOfPage[string(call["page"]) ?? ""] ?? "", in: root)
                case "clear":
                    let reason: UndoClearing = UndoClearing(rawValue: string(call["reason"]) ?? "") ?? .deploy
                    try journal.clearTheList(because: reason)
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
    /// would silently not check (the contract review's MINOR 9).
    static let checkKeys: Set<String> = ["name", "op", "current", "undo", "redo"]

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
            let relativePath: String = string(given["path"]) ?? "page.md"
            let url: URL = place.root.appendingPathComponent(UndoOp.isSafeRelativePath(relativePath) ? relativePath : "page.md")
            if let text = string(current["text"]) {
                try Data(text.utf8).write(to: url)
            } else if let hex = string(current["bytesHex"]) {
                try bytes(fromHex: hex).write(to: url)
            } else if current["folder"] as? Bool == true {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }

            // The op is DECODED from the case's JSON, so the lenient reader
            // is what is tested: a kind it does not know, a path that climbs
            // out, a number where text belongs.
            if string(given["kind"]) == "writeFile" {
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
            var clean: [String: Any] = [:]
            for (key, value) in given where !(value is NSNull) {
                clean[key] = value
            }
            let op: UndoOp = try JSONDecoder().decode(UndoOp.self, from: JSONSerialization.data(withJSONObject: clean))
            var undo: String = "notReadable"
            var redo: String = "notReadable"
            if op.isReadable {
                let state: UndoOpState = UndoCheck.state(of: op, in: UndoItem.read(at: url))
                undo = UndoCheck.verdict(for: state, direction: .backward).rawValue
                redo = UndoCheck.verdict(for: state, direction: .forward).rawValue
            }
            if undo != string(testCase["undo"]) {
                failures.append("checkCases '\(name)': undo is \(undo), not \(string(testCase["undo"]) ?? "?")")
            }
            if redo != string(testCase["redo"]) {
                failures.append("checkCases '\(name)': redo is \(redo), not \(string(testCase["redo"]) ?? "?")")
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
        "blobKept", "pendingRuling",
    ]

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

    static func runStackCases(under parent: URL) throws -> (cases: Int, failures: [String]) {
        let cases: [[String: Any]] = try undoBlock()["stackCases"] as? [[String: Any]] ?? []
        let traces: [String: Any] = try contract("undo-traces.json")
        var pagePath: String = ""
        var pageText: String = ""
        for page in traces["fixture"] as? [[String: Any]] ?? [] where string(page["page"]) == "p1" {
            pagePath = string(page["path"]) ?? ""
            pageText = string(page["text"]) ?? ""
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
            try write(pageText, to: secondPagePath, in: rootB)
            var clockDays: Double = 0
            var last: String = ""
            var linesBeforeClearing: Int = -1
            var linesAfterClearing: Int = -1
            var held: (seq: Int, change: UndoFileChange)? = nil
            var foreignBlob: String? = nil
            let folderOfB: String = rootB.path

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

            for value in testCase["calls"] as? [String] ?? [] {
                if value == "step" {
                    oneStep(folderRoot: root, path: pagePath, daysAgo: 0)
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
                    last = outcomeWord(journal().undoNewest(resolveRoot: resolve))
                } else if value == "redo" {
                    last = outcomeWord(journal().redoNewest(resolveRoot: resolve))
                } else if value == "editTheLineByHand" {
                    try handEdit("sameLine", at: pagePath, in: root)
                } else if value.hasPrefix("clear:") {
                    let reason: UndoClearing = UndoClearing(rawValue: String(value.dropFirst("clear:".count))) ?? .deploy
                    linesBeforeClearing = try lineCount(in: journal())
                    try journal().clearTheList(because: reason)
                    linesAfterClearing = try lineCount(in: journal())
                } else if value == "moveFolder:B" {
                    try FileManager.default.moveItem(at: rootB, to: rootBAway)
                } else if value == "restoreFolder:B" {
                    try FileManager.default.moveItem(at: rootBAway, to: rootB)
                } else if value == "foreignLine" {
                    let next: Int = try journal().read().highestSeq + 1
                    try appendRaw("{\"v\":2,\"seq\":\(next),\"event\":\"begin\",\"step\":{\"seq\":\(next),\"later\":true}}", to: journal())
                } else if value == "foreignStep" {
                    let next: Int = try journal().read().highestSeq + 1
                    let blob: Data = Data("content a newer Plantoir keeps".utf8)
                    let sha: String = UndoHash.sha256(of: blob)
                    try journal().withLock { writer in
                        try writer.writeBlob(blob)
                    }
                    foreignBlob = sha
                    let folderID: String = try FolderIdentityFile.identifier(forWorkingFolder: root)
                    let begin: String = "{\"v\":1,\"seq\":\(next),\"event\":\"begin\",\"at\":\"\(UndoMoment.text(Date()))\",\"step\":{\"seq\":\(next),\"madeAt\":\"\(UndoMoment.text(Date()))\",\"workingFolder\":{\"id\":\"\(folderID)\",\"pathAtTheTime\":\"\(root.path)\"},\"ops\":[{\"kind\":\"move\",\"from\":\"a.md\",\"to\":\"b.md\",\"blobs\":[\"\(sha)\"]}]}}"
                    try appendRaw(begin, to: journal())
                    try appendRaw("{\"v\":1,\"seq\":\(next),\"event\":\"applied\"}", to: journal())
                } else if value == "begin:held" {
                    let change: [UndoFileChange] = flip(in: root, at: pagePath)
                    let heldDraft: UndoStepDraft = draft(changes: change, root: root, action: "publishPages")
                    let seq: Int = try JournaledWrite.begin(heldDraft, ops: JournaledWrite.ops(for: heldDraft), in: journal(), mode: .live)
                    if let first = change.first {
                        held = (seq: seq, change: first)
                    }
                } else if value == "finish:held" {
                    if let held {
                        try (held.change.after ?? Data()).write(to: root.appendingPathComponent(held.change.relativePath))
                        JournaledWrite.finish(seq: held.seq, with: .applied, phase: nil, reason: nil, in: journal(), mode: .live)
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
            if let written = int(testCase["linesWritten"]), linesAfterClearing - linesBeforeClearing != written {
                failures.append("stackCases '\(name)': a clearing wrote \(linesAfterClearing - linesBeforeClearing) lines, not \(written)")
            }
            if let kept = testCase["blobKept"] as? Bool {
                let present: Bool = foreignBlob != nil && journal().readBlob(sha: foreignBlob ?? "") != nil
                if present != kept {
                    failures.append("stackCases '\(name)': the newer version's blob kept is \(present)")
                }
            }
            if fold.ignoredEvents != 0 {
                failures.append("stackCases '\(name)': \(fold.ignoredEvents) ignored events")
            }
        }
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
        "handEdit", "cleared", "pathsNamed", "moveFolderBeforeRecovery",
    ]

    static func runRecoveryCases(under parent: URL) throws -> (cases: Int, failures: [String]) {
        let cases: [[String: Any]] = try undoBlock()["recoveryCases"] as? [[String: Any]] ?? []
        var failures: [String] = []
        var number: Int = 0
        defer {
            UndoKillPoints.hook = nil
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
            let stepDraft: UndoStepDraft = draft(changes: changes(setting: edits, in: root), root: root, action: "publishPages")
            var afterHashes: [String?] = []

            if work == "step" {
                UndoKillPoints.hook = { point in point == stopAt }
                let outcome: JournaledWriteOutcome = JournaledWrite.perform(stepDraft, in: dying, mode: mode)
                UndoKillPoints.hook = nil
                if outcome != .stoppedByATest {
                    failures.append("recoveryCases '\(name)': the step was not stopped (\(outcome))")
                }
                for change in stepDraft.changes {
                    afterHashes.append(UndoHash.sha256(ofOptional: change.after))
                }
            } else {
                _ = JournaledWrite.perform(stepDraft, in: dying, mode: .live)
                afterHashes = [hash(of: first, in: root), hash(of: second, in: root)]
                if work == "redo" {
                    _ = dying.undoNewest(resolveRoot: { _ in root })
                }
                UndoKillPoints.hook = { point in point == stopAt }
                let outcome: UndoOutcome = work == "undo"
                    ? dying.undoNewest(resolveRoot: { _ in root })
                    : dying.redoNewest(resolveRoot: { _ in root })
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

            // Another process, which sees the first as gone, runs recovery.
            let survivor: UndoJournal = UndoJournal(
                folderURL: place.journalFolder,
                processIsAlive: { process in process.pid != 2_000_000_001 || alive }
            )
            try survivor.withLock { writer in
                UndoRecovery.run(writer, mode: mode, resolveRoot: resolveRoot)
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
            let phase: String = fold.records[1]?.phase.rawValue ?? "missing"
            if phase != string(testCase["phase"]) {
                failures.append("recoveryCases '\(name)': the step is \(phase), not \(string(testCase["phase"]) ?? "?")")
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
            if let undo = string(testCase["undo"]) {
                let outcome: String = outcomeWord(survivor.undoNewest(resolveRoot: resolveRoot))
                if outcome != undo {
                    failures.append("recoveryCases '\(name)': undo came to \(outcome), not \(undo)")
                }
            }
            if mode == .live && !alive && reachable && staysBeside(root) {
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
        default:
            return .beforeRedone
        }
    }

    // MARK: - undo.stepCases

    static let stepKeys: Set<String> = [
        "name", "pages", "handEdit", "undo", "named", "others", "files", "phase", "fileInUseAtSwap", "why",
    ]

    static func runStepCases(under parent: URL) throws -> (cases: Int, failures: [String]) {
        let cases: [[String: Any]] = try undoBlock()["stepCases"] as? [[String: Any]] ?? []
        var failures: [String] = []
        var number: Int = 0
        defer {
            UndoKillPoints.fileInUseAtSwap = nil
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
            var paths: [String] = []
            var edits: [(path: String, key: String, line: String)] = []
            var index: Int = 1
            while index <= pageCount {
                let path: String = "courses/TST1O/Section 1/Classes/Page \(index).md"
                try write("---\ntitle: Page \(index)\npublish: false\n---\nBody.\n", to: path, in: root)
                paths.append(path)
                edits.append((path: path, key: "publish", line: "publish: true"))
                index += 1
            }
            let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
            _ = JournaledWrite.perform(draft(changes: changes(setting: edits, in: root), root: root, action: "publishPages"), in: journal, mode: .live)
            let handEdit: String = string(testCase["handEdit"]) ?? ""
            var edited: [Int] = []
            if handEdit == "line of page 2" {
                edited = [2]
            } else if handEdit == "lines of pages 1 and 3" {
                edited = [1, 3]
            } else if handEdit != "none" {
                failures.append("stepCases '\(name)': handEdit '\(handEdit)' is not a value this replay knows")
            }
            for page in edited {
                try UndoContractReplay.handEdit("sameLine", at: paths[page - 1], in: root)
            }
            var snapshot: [String?] = []
            for path in paths {
                snapshot.append(hash(of: path, in: root))
            }
            if let swapIndex = int(testCase["fileInUseAtSwap"]) {
                UndoKillPoints.fileInUseAtSwap = { candidate in candidate == swapIndex }
            }
            let outcome: UndoOutcome = journal.undoNewest(resolveRoot: { _ in root })
            UndoKillPoints.fileInUseAtSwap = nil
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
        let previousHook: ((String, String, Int?, UndoMode, String) -> Void)? = UndoTrailHook.couldNotRecordLine
        UndoTrailHook.couldNotRecordLine = { _, _, _, mode, _ in
            if mode == .shadow {
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
