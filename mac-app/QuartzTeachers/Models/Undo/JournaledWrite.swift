import Foundation

/// One thing a step changed, recorded so it can be checked and reversed.
///
/// U1 builds two kinds that change content, `writeFile` and `editLine`, and
/// records a third, `recompute`, which changes nothing by itself. The rest of
/// plan section 3.1 (`replaceText`, `editJSON`, `move`, the tree operations,
/// `external`) arrive with U2. Every kind records what it expects to find
/// before it may be undone (its `after`) and before it may be redone (its
/// `before`), and the check compares the CONTENT of exactly what it changed:
/// for a line, that line; for a file, its SHA-256. Never a time (ruling 4,
/// Windows' fact 6).
nonisolated struct UndoOp: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    /// `writeFile`, `editLine` or `recompute`.
    var kind: String

    /// Inside the working folder, with forward slashes:
    /// `courses/ICS3U/Section 1/Classes/Unit 1, Day 1.md`.
    var path: String

    /// `writeFile`: the file's SHA-256 before and after, each nil when there
    /// was no file. The bytes are blobs under the journal's `content/`.
    var beforeSha: String?
    var afterSha: String?

    /// `editLine`: the top-level front-matter key, and its entry before and
    /// after (the key's line and any lines its value runs on to, joined with
    /// a line feed, carriage returns kept), each nil when the key was absent.
    var key: String?
    var before: String?
    var after: String?

    /// `editLine`: the key whose entry this one follows, in the text where
    /// this one exists, so an entry that was added or removed goes back in
    /// the same place. Nil for the first entry in the block.
    var afterKey: String?

    /// `editLine`: the step gave the page its front matter, so undoing the
    /// last entry takes the fences away too.
    var createdTheBlock: Bool?

    /// `recompute`: which maintainer re-derives the file from the rule it is
    /// kept true by (`sectionFrontPage` for the section's landing page), and
    /// for which section. No check; run after the other ops (U2 runs it).
    var maintainer: String?
    var section: Int?

    // MARK: - Functions

    static func writeFile(path: String, beforeSha: String?, afterSha: String?) -> UndoOp {
        return UndoOp(kind: UndoOpKind.writeFile.rawValue, path: path, beforeSha: beforeSha, afterSha: afterSha)
    }

    static func editLine(
        path: String,
        key: String,
        before: String?,
        after: String?,
        afterKey: String?,
        createdTheBlock: Bool
    ) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.editLine.rawValue, path: path)
        op.key = key
        op.before = before
        op.after = after
        op.afterKey = afterKey
        if createdTheBlock {
            op.createdTheBlock = true
        }
        return op
    }

    static func recompute(path: String, maintainer: String, section: Int?) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.recompute.rawValue, path: path)
        op.maintainer = maintainer
        op.section = section
        return op
    }

    init(
        kind: String,
        path: String,
        beforeSha: String? = nil,
        afterSha: String? = nil
    ) {
        self.kind = kind
        self.path = path
        self.beforeSha = beforeSha
        self.afterSha = afterSha
    }

    /// The kind, or nil for one this app does not know.
    var knownKind: UndoOpKind? {
        return UndoOpKind(rawValue: kind)
    }
}

/// The kinds of op U1 knows.
nonisolated enum UndoOpKind: String, Sendable {
    case writeFile
    case editLine
    case recompute
}

/// One file before and after a change, as the action that made it saw it.
nonisolated struct UndoFileChange: Equatable, Sendable {

    // MARK: - Stored properties

    /// Inside the working folder, forward slashes.
    let relativePath: String

    /// Nil when there was no file.
    let before: Data?

    /// Nil when the change removed it.
    let after: Data?
}

/// What an action hands the door: everything about the step but its number.
nonisolated struct UndoStepDraft: Sendable {

    // MARK: - Stored properties

    let action: UndoAction

    let madeBy: String

    /// The working folder's root: the folder holding `courses/`.
    let workingFolderURL: URL

    /// Its canonical path (`FolderIdentity.canonicalPath` in the app).
    let workingFolderPath: String

    let course: String

    let section: Int?

    let actionClass: String

    let holds: String

    let changes: [UndoFileChange]

    /// Files kept true by a rule, re-derived after the other ops.
    let recomputes: [UndoOp]
}

/// How the door went.
nonisolated enum JournaledWriteOutcome: Equatable, Sendable {

    /// Recorded and made.
    case applied(seq: Int)

    /// Made, but not recorded: shadow mode, and the list could not be written.
    case appliedWithoutARecord

    /// Live mode, and the list could not be written: nothing was changed.
    case couldNotRecordTheStep

    /// Something was in the way, and nothing was changed.
    case refused(UndoRefusal)

    /// Nothing to change.
    case changedNothing

    /// A test stopped the work at a kill point, as a process that died
    /// there would have: nothing more was written, the list included.
    case stoppedByATest
}

/// What stands in the way of a change, an undo or a redo. Each names the
/// first page in the way, inside the working folder.
nonisolated enum UndoRefusal: Equatable, Sendable {

    /// What the step changed has been changed since (`undo.wording.pageChangedSince`).
    case changedSince(firstPath: String, others: Int)

    /// A file could not be swapped in, and the swaps already made were
    /// reversed (`undo.wording.fileIsInUse`).
    case fileIsInUse(path: String)

    /// Content the step needs is missing from the list.
    case contentMissing(path: String)
}

/// The one door every write into a working folder goes through once the
/// switch is on (plan 3.3): it records the step, then makes the change.
///
/// In U1 only the trace replayer and the tests make changes through it; the
/// actions themselves are wired by U3 to U6. The one action recorded today is
/// publishing and hiding pages, and that goes through `beginInShadow` and
/// `finishInShadow` beside the action's own writes, because the action's
/// writes must not change while the list is off.
nonisolated enum JournaledWrite {

    // MARK: - Functions

    /// The ops that describe one file's change: `editLine` for each
    /// front-matter entry it changed when that is ALL it changed, otherwise
    /// one `writeFile`. The line form is only chosen when applying its ops to
    /// the before text gives the after text byte for byte, and undoing them
    /// gives the before text back, so a page the line model cannot describe
    /// exactly falls back to the whole file rather than to a guess.
    static func ops(for change: UndoFileChange) -> [UndoOp] {
        let wholeFile: UndoOp = UndoOp.writeFile(
            path: change.relativePath,
            beforeSha: UndoHash.sha256(ofOptional: change.before),
            afterSha: UndoHash.sha256(ofOptional: change.after)
        )
        guard let beforeData = change.before, let afterData = change.after else {
            return [wholeFile]
        }
        guard let beforeText = UndoText.decode(beforeData), let afterText = UndoText.decode(afterData) else {
            return [wholeFile]
        }
        if let lineOps = UndoLineOps.ops(path: change.relativePath, before: beforeText, after: afterText) {
            return lineOps
        }
        return [wholeFile]
    }

    /// Every op of a draft, in order, with the recomputes last.
    static func ops(for draft: UndoStepDraft) -> [UndoOp] {
        var result: [UndoOp] = []
        for change in draft.changes {
            if change.before == change.after {
                continue
            }
            for op in ops(for: change) {
                result.append(op)
            }
        }
        for op in draft.recomputes {
            result.append(op)
        }
        return result
    }

    /// Records the step, makes the change, and marks it made: the three
    /// phases of plan 2.4. The `begin` is on the disk before any file is
    /// touched, and the files are staged beside their targets and swapped in
    /// only when all are written (`UndoSwap`).
    static func perform(
        _ draft: UndoStepDraft,
        in journal: UndoJournal,
        mode: UndoMode
    ) -> JournaledWriteOutcome {
        let ops: [UndoOp] = ops(for: draft)
        var hasContentOp: Bool = false
        for op in ops where op.knownKind != .recompute {
            hasContentOp = true
        }
        if !hasContentOp {
            return .changedNothing
        }

        var targets: [UndoSwapTarget] = []
        for change in draft.changes where change.before != change.after {
            targets.append(UndoSwapTarget(
                url: draft.workingFolderURL.appendingPathComponent(change.relativePath),
                relativePath: change.relativePath,
                expected: change.before,
                replacement: change.after
            ))
        }

        let seq: Int
        do {
            seq = try begin(draft, ops: ops, in: journal, mode: mode)
        } catch {
            UndoTrailHook.couldNotRecord(draft: draft, mode: mode, problem: error)
            if mode == .live {
                return .couldNotRecordTheStep
            }
            // Shadow: the change goes ahead exactly as it would have.
            switch UndoSwap.swap(targets, label: "shadow") {
            case .swapped:
                return .appliedWithoutARecord
            case .refused(let refusal):
                return .refused(refusal)
            case .stoppedByATest:
                return .stoppedByATest
            }
        }

        if UndoKillPoints.stopsHere(.afterBegin) {
            return .stoppedByATest
        }

        switch UndoSwap.swap(targets, label: "\(seq)-apply") {
        case .refused(let refusal):
            finish(seq: seq, with: .failed, phase: .begin, reason: "refused", in: journal, mode: mode)
            return .refused(refusal)
        case .stoppedByATest:
            return .stoppedByATest
        case .swapped:
            break
        }

        if UndoKillPoints.stopsHere(.beforeApplied) {
            return .stoppedByATest
        }
        finish(seq: seq, with: .applied, phase: nil, reason: nil, in: journal, mode: mode)
        return .applied(seq: seq)
    }

    /// Phase one: under the lock, run recovery, cut the redo branch, take
    /// the next number, store the content, append `begin`, and sync.
    static func begin(
        _ draft: UndoStepDraft,
        ops: [UndoOp],
        in journal: UndoJournal,
        mode: UndoMode
    ) throws -> Int {
        let folderID: String = try FolderIdentityFile.identifier(forWorkingFolder: draft.workingFolderURL)
        let wait: Double = mode == .live ? UndoSwitch.lockWaitSeconds : UndoSwitch.shadowLockWaitSeconds
        return try journal.withLock(waitingAtMost: wait) { writer in
            UndoRecovery.run(writer, mode: mode, resolveRoot: UndoReach.root)
            for record in writer.fold.redoBranch {
                try writer.append(UndoEventLine(seq: record.step.seq, event: .dropped, reason: "newStep"))
            }
            for record in writer.fold.staleUndone {
                try writer.append(UndoEventLine(seq: record.step.seq, event: .dropped, reason: "newStep"))
            }
            var wholeFilePaths: Set<String> = []
            for op in ops where op.knownKind == .writeFile {
                wholeFilePaths.insert(op.path)
            }
            for change in draft.changes where wholeFilePaths.contains(change.relativePath) {
                if let before = change.before {
                    try writer.writeBlob(before)
                }
                if let after = change.after {
                    try writer.writeBlob(after)
                }
            }
            let seq: Int = writer.fold.highestSeq + 1
            let step: UndoStep = UndoStep(
                seq: seq,
                madeAt: UndoMoment.text(journal.now()),
                action: draft.action,
                madeBy: draft.madeBy,
                workingFolder: UndoWorkingFolder(id: folderID, pathAtTheTime: draft.workingFolderPath),
                course: draft.course,
                section: draft.section,
                actionClass: draft.actionClass,
                holds: draft.holds,
                ops: ops
            )
            try writer.append(UndoEventLine(seq: seq, event: .begin, step: step, process: journal.process))
            try writer.sync()
            return seq
        }
    }

    /// Phase three: append the closing event and prune. A failure here
    /// leaves the step unfinished, which recovery settles from the content
    /// once this process has gone.
    static func finish(
        seq: Int,
        with event: UndoEventKind,
        phase: UndoPhase?,
        reason: String?,
        in journal: UndoJournal,
        mode: UndoMode
    ) {
        // Longer than a begin waits: a step left unfinished holds Undo back
        // until its process has gone and recovery settles it.
        let wait: Double = mode == .live ? UndoSwitch.finishWaitSeconds : UndoSwitch.shadowLockWaitSeconds
        do {
            try journal.withLock(waitingAtMost: wait) { writer in
                try writer.append(UndoEventLine(seq: seq, event: event, phase: phase, reason: reason))
                UndoPruning.prune(writer)
            }
        } catch {
            UndoTrailHook.couldNotFinish(seq: seq, problem: error)
        }
    }

    // MARK: - Shadow recording beside an action's own writes

    /// Writes the `begin` of a step whose change the ACTION will make itself.
    /// Never throws and never blocks for long: while the switch is off, a
    /// list that cannot be written leaves a trail line and nothing else.
    static func beginInShadow(_ draft: UndoStepDraft, in journal: UndoJournal) -> UndoShadowTicket? {
        let ops: [UndoOp] = ops(for: draft)
        var hasContentOp: Bool = false
        for op in ops where op.knownKind != .recompute {
            hasContentOp = true
        }
        if !hasContentOp {
            return nil
        }
        do {
            let seq: Int = try begin(draft, ops: ops, in: journal, mode: .shadow)
            return UndoShadowTicket(seq: seq, draft: draft)
        } catch {
            UndoTrailHook.couldNotRecord(draft: draft, mode: .shadow, problem: error)
            return nil
        }
    }

    /// Closes a shadow step with what the action actually wrote: for each
    /// file it wrote, the bytes it left (nil: removed). When that is exactly
    /// what was recorded, the step is `applied`; otherwise it is `failed`
    /// with a reason and leaves the list, because a record that differs from
    /// the change would undo the wrong thing. Writes nothing into the working
    /// folder in any case. A nil `actuallyWritten` means the action stopped.
    ///
    /// Only what was WRITTEN is compared, not what each file held before: the
    /// record's before is the disk's own bytes, while an action may have read
    /// the file through `String(contentsOf:)`, which drops a byte-order mark
    /// (measured), and so remember a different before for the same file.
    static func finishInShadow(
        _ ticket: UndoShadowTicket?,
        actuallyWritten: [String: Data?]?,
        in journal: UndoJournal
    ) {
        guard let ticket else {
            return
        }
        guard let actuallyWritten else {
            finish(seq: ticket.seq, with: .failed, phase: .begin, reason: "actionStopped", in: journal, mode: .shadow)
            return
        }
        if wroteWhatWasRecorded(ticket.draft.changes, actuallyWritten) {
            finish(seq: ticket.seq, with: .applied, phase: nil, reason: nil, in: journal, mode: .shadow)
            return
        }
        finish(seq: ticket.seq, with: .failed, phase: .begin, reason: "differedFromTheRecord", in: journal, mode: .shadow)
        UndoTrailHook.couldNotRecord(
            draft: ticket.draft, mode: .shadow, problem: UndoShadowMismatch.differedFromTheRecord
        )
    }

    /// Whether the files written, and what each was left holding, are the
    /// ones the record says.
    static func wroteWhatWasRecorded(_ recorded: [UndoFileChange], _ written: [String: Data?]) -> Bool {
        var recordedAfter: [String: Data?] = [:]
        for change in recorded where change.before != change.after {
            recordedAfter[change.relativePath] = change.after
        }
        if recordedAfter.count != written.count {
            return false
        }
        for (path, after) in written {
            guard let expected = recordedAfter[path] else {
                return false
            }
            if expected != after {
                return false
            }
        }
        return true
    }

    // MARK: - The trace replayer's writer

    /// A page's text with one top-level key's entry set to `line`: the entry
    /// replaced when the key is there once, inserted at the top of the block
    /// when it is not, and a block made when the page has none. The writer
    /// the traces in `contracts/undo-traces.json` describe their steps with,
    /// so both apps make byte-identical changes from the same data. Nil when
    /// the key is there more than once.
    static func settingEntry(key: String, to line: String, in text: String) -> String? {
        guard let layout = UndoFrontMatter.layout(of: text) else {
            return "---\n" + line + "\n---\n" + text
        }
        let found: [UndoFrontMatter.Entry] = layout.entries(forKey: key)
        if found.count > 1 {
            return nil
        }
        var lines: [String] = layout.lines
        if let entry = found.first {
            // The new entry keeps the carriage return of the line it replaces.
            var replacement: String = line
            if lines[entry.start].hasSuffix("\r") && !line.hasSuffix("\r") {
                replacement += "\r"
            }
            lines.replaceSubrange(entry.start..<entry.end, with: [replacement])
            return lines.joined(separator: "\n")
        }
        var replacement: String = line
        if lines[layout.openIndex].hasSuffix("\r") && !line.hasSuffix("\r") {
            replacement += "\r"
        }
        lines.insert(replacement, at: layout.openIndex + 1)
        return lines.joined(separator: "\n")
    }
}

/// A shadow step written down, waiting for the action to finish.
nonisolated struct UndoShadowTicket: Sendable {

    // MARK: - Stored properties

    let seq: Int

    let draft: UndoStepDraft
}

/// Why a shadow step was not kept.
nonisolated enum UndoShadowMismatch: Error {
    case differedFromTheRecord
}

/// Text from bytes and back, exactly.
nonisolated enum UndoText {

    // MARK: - Functions

    /// The bytes as text, or nil when they are not UTF-8 exactly: decoding
    /// and encoding again must give the same bytes, so a byte-order mark is
    /// kept and an invalid sequence is refused rather than replaced.
    static func decode(_ data: Data) -> String? {
        let text: String = String(decoding: data, as: UTF8.self)
        if Data(text.utf8) != data {
            return nil
        }
        return text
    }

    /// Byte-for-byte equality. Swift's `==` on strings is canonical
    /// equivalence, which calls a precomposed é equal to a decomposed one:
    /// that is not what "exactly as the step left it" means.
    static func same(_ first: String?, _ second: String?) -> Bool {
        guard let first, let second else {
            return first == nil && second == nil
        }
        return Data(first.utf8) == Data(second.utf8)
    }
}

/// A page's front matter as lines and top-level entries.
///
/// The block is found with the reader both apps use
/// (`PageVisibilityReader.fenceIndices`: three dashes or more, blank lines
/// allowed before the opening fence). An ENTRY is a top-level key's line
/// and the lines its value runs on to: lines that start with a space or a
/// tab, and column-0 sequence items. A blank line, a column-0 comment or the
/// next key ends it. Lines are split on the line feed alone, so a carriage
/// return stays on its line and is compared like any other byte.
nonisolated struct UndoFrontMatter {

    // MARK: - Stored properties

    let lines: [String]

    let openIndex: Int

    let closeIndex: Int

    let entries: [Entry]

    /// One top-level key and the lines it spans, `start..<end`.
    struct Entry: Equatable {
        let key: String
        let start: Int
        let end: Int
    }

    // MARK: - Functions

    static func layout(of text: String) -> UndoFrontMatter? {
        guard let fences = PageVisibilityReader.fenceIndices(in: text) else {
            return nil
        }
        let lines: [String] = text.components(separatedBy: "\n")
        var entries: [Entry] = []
        var index: Int = fences.openIndex + 1
        while index < fences.closeIndex {
            guard let key = topLevelKey(inLine: lines[index]) else {
                index += 1
                continue
            }
            var end: Int = index + 1
            while end < fences.closeIndex && continuesAValue(lines[end]) {
                end += 1
            }
            entries.append(Entry(key: key, start: index, end: end))
            index = end
        }
        return UndoFrontMatter(lines: lines, openIndex: fences.openIndex, closeIndex: fences.closeIndex, entries: entries)
    }

    /// The key a column-0 line names, quotes taken off, or nil.
    static func topLevelKey(inLine rawLine: String) -> String? {
        let line: String = PageFrontmatter.trimmingCarriageReturn(rawLine)
        guard let first = line.first else {
            return nil
        }
        if first == " " || first == "\t" || first == "#" || first == "-" {
            return nil
        }
        guard let colon = line.firstIndex(of: ":") else {
            return nil
        }
        var key: String = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        if key.count >= 2 {
            let opening: Character = key[key.startIndex]
            let closing: Character = key[key.index(before: key.endIndex)]
            if (opening == "\"" || opening == "'") && closing == opening {
                key = String(key.dropFirst().dropLast())
            }
        }
        if key.isEmpty {
            return nil
        }
        return key
    }

    /// Whether a line carries on the value of the entry above it.
    static func continuesAValue(_ rawLine: String) -> Bool {
        let line: String = PageFrontmatter.trimmingCarriageReturn(rawLine)
        guard let first = line.first else {
            return false
        }
        if first == " " || first == "\t" {
            return !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return first == "-" && !line.hasPrefix("---")
    }

    func entries(forKey key: String) -> [Entry] {
        var found: [Entry] = []
        for entry in entries where entry.key == key {
            found.append(entry)
        }
        return found
    }

    /// The entry's lines joined with a line feed.
    func text(of entry: Entry) -> String {
        var part: [String] = []
        var index: Int = entry.start
        while index < entry.end {
            part.append(lines[index])
            index += 1
        }
        return part.joined(separator: "\n")
    }

    /// The key of the entry just before this one, or nil for the first.
    func keyBefore(_ entry: Entry) -> String? {
        var previous: String? = nil
        for candidate in entries {
            if candidate.start == entry.start {
                return previous
            }
            previous = candidate.key
        }
        return previous
    }
}

/// Where an `editLine` op's key stands in some text.
nonisolated enum UndoEntryReading: Equatable {
    /// No such key at the top level (or no front matter at all).
    case absent
    /// Exactly one entry, with this text.
    case entry(String)
    /// The key more than once, or the page cannot be read: never a guess.
    case unreadable
}

/// The `editLine` op: reading, applying, and finding them in a change.
nonisolated enum UndoLineOps {

    // MARK: - Functions

    /// How an op's key reads in this text.
    static func reading(key: String, in text: String) -> UndoEntryReading {
        guard let layout = UndoFrontMatter.layout(of: text) else {
            if PageVisibilityReader.pageTextOpensAFence(text) {
                return .unreadable
            }
            return .absent
        }
        let found: [UndoFrontMatter.Entry] = layout.entries(forKey: key)
        if found.isEmpty {
            return .absent
        }
        if found.count > 1 {
            return .unreadable
        }
        return .entry(layout.text(of: found[0]))
    }

    /// Whether a reading is what an entry text (nil: absent) says.
    static func reading(_ reading: UndoEntryReading, matches expected: String?) -> Bool {
        switch reading {
        case .absent:
            return expected == nil
        case .entry(let text):
            guard let expected else {
                return false
            }
            return UndoText.same(text, expected)
        case .unreadable:
            return false
        }
    }

    /// The text with the op's key moved from `from` to `to` (each nil for
    /// absent), or nil when the text does not read `from`.
    static func moving(_ op: UndoOp, from: String?, to: String?, in text: String) -> String? {
        guard let key = op.key else {
            return nil
        }
        let current: UndoEntryReading = reading(key: key, in: text)
        if !reading(current, matches: from) {
            return nil
        }
        if UndoText.same(from, to) {
            return text
        }
        guard let layout = UndoFrontMatter.layout(of: text) else {
            // No block: only a step that made one can put an entry here.
            guard let to, op.createdTheBlock == true else {
                return nil
            }
            return "---\n" + to + "\n---\n" + text
        }
        var lines: [String] = layout.lines
        let found: [UndoFrontMatter.Entry] = layout.entries(forKey: key)
        if let entry = found.first {
            if let to {
                lines.replaceSubrange(entry.start..<entry.end, with: to.components(separatedBy: "\n"))
                return lines.joined(separator: "\n")
            }
            lines.removeSubrange(entry.start..<entry.end)
            let wasTheOnlyEntry: Bool = layout.entries.count == 1
            let blockIsNowEmpty: Bool = wasTheOnlyEntry && layout.closeIndex - layout.openIndex - 1 == entry.end - entry.start
            if op.createdTheBlock == true && blockIsNowEmpty && layout.openIndex == 0 {
                // Both fences go, and the line feed after the closing one.
                lines.removeSubrange(0..<2)
            }
            return lines.joined(separator: "\n")
        }
        guard let to else {
            return text
        }
        var insertAt: Int = layout.openIndex + 1
        if let afterKey = op.afterKey {
            let anchors: [UndoFrontMatter.Entry] = layout.entries(forKey: afterKey)
            if anchors.count == 1 {
                insertAt = anchors[0].end
            }
        }
        lines.insert(contentsOf: to.components(separatedBy: "\n"), at: insertAt)
        return lines.joined(separator: "\n")
    }

    /// The `editLine` ops that turn `before` into `after`, or nil when the
    /// change is not only front-matter entries or the ops do not reproduce
    /// it exactly in both directions.
    static func ops(path: String, before: String, after: String) -> [UndoOp]? {
        if UndoText.same(before, after) {
            return []
        }
        let afterLayout: UndoFrontMatter? = UndoFrontMatter.layout(of: after)
        guard let afterLayout else {
            return nil
        }
        let beforeLayout: UndoFrontMatter? = UndoFrontMatter.layout(of: before)
        var result: [UndoOp] = []

        guard let beforeLayout else {
            // The step gave the page its front matter: one entry, made whole.
            if afterLayout.entries.count != 1 {
                return nil
            }
            let entry: UndoFrontMatter.Entry = afterLayout.entries[0]
            result.append(UndoOp.editLine(
                path: path, key: entry.key, before: nil,
                after: afterLayout.text(of: entry), afterKey: nil, createdTheBlock: true
            ))
            return verified(result, before: before, after: after)
        }

        var seenKeys: Set<String> = []
        for entry in afterLayout.entries {
            if seenKeys.contains(entry.key) {
                return nil
            }
            seenKeys.insert(entry.key)
            let inBefore: [UndoFrontMatter.Entry] = beforeLayout.entries(forKey: entry.key)
            if inBefore.count > 1 {
                return nil
            }
            let afterText: String = afterLayout.text(of: entry)
            var beforeText: String? = nil
            if let found = inBefore.first {
                beforeText = beforeLayout.text(of: found)
            }
            if UndoText.same(beforeText, afterText) {
                continue
            }
            result.append(UndoOp.editLine(
                path: path, key: entry.key, before: beforeText, after: afterText,
                afterKey: afterLayout.keyBefore(entry), createdTheBlock: false
            ))
        }
        for entry in beforeLayout.entries where !seenKeys.contains(entry.key) {
            if beforeLayout.entries(forKey: entry.key).count > 1 {
                return nil
            }
            seenKeys.insert(entry.key)
            result.append(UndoOp.editLine(
                path: path, key: entry.key, before: beforeLayout.text(of: entry), after: nil,
                afterKey: beforeLayout.keyBefore(entry), createdTheBlock: false
            ))
        }
        if result.isEmpty {
            return nil
        }
        return verified(result, before: before, after: after)
    }

    /// The ops, if applying them forward to `before` gives `after` and
    /// backward to `after` gives `before`, byte for byte.
    static func verified(_ ops: [UndoOp], before: String, after: String) -> [UndoOp]? {
        var forward: String = before
        for op in ops {
            guard let moved = moving(op, from: op.before, to: op.after, in: forward) else {
                return nil
            }
            forward = moved
        }
        if !UndoText.same(forward, after) {
            return nil
        }
        var backward: String = after
        var index: Int = ops.count - 1
        while index >= 0 {
            let op: UndoOp = ops[index]
            guard let moved = moving(op, from: op.after, to: op.before, in: backward) else {
                return nil
            }
            backward = moved
            index -= 1
        }
        if !UndoText.same(backward, before) {
            return nil
        }
        return ops
    }
}

/// The one spelling of a moment in the journal: UTC, to the second.
nonisolated enum UndoMoment {

    // MARK: - Functions

    static func text(_ moment: Date) -> String {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: moment)
    }

    static func date(_ text: String) -> Date? {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// The places a test or the harness stops a step, to prove what recovery
/// does with a process that dies there. Nil in the app: reaching a point
/// costs one check.
nonisolated enum UndoKillPoint: Equatable, Sendable {
    case afterBegin
    case beforeSwap(Int)
    case beforeApplied
    case afterUndoing
    case beforeUndone
    case afterRedoing
    case beforeRedone
}

nonisolated enum UndoKillPoints {

    // MARK: - Stored properties

    /// Answers true to stop the work at a point, exactly as a process that
    /// died there would stop: no reversal, no tidying, no journal event. A
    /// harness may instead end its own process there with `SIGKILL`. Set
    /// only by tests and the harness.
    nonisolated(unsafe) static var hook: ((UndoKillPoint) -> Bool)?

    /// Answers true to make the swap at this index fail as a file another
    /// program holds would (Windows' fact 5): the swaps already made are
    /// reversed and the file is named.
    nonisolated(unsafe) static var fileInUseAtSwap: ((Int) -> Bool)?

    // MARK: - Functions

    static func stopsHere(_ point: UndoKillPoint) -> Bool {
        guard let hook else {
            return false
        }
        return hook(point)
    }
}

/// How the list reaches the activity trail. The core leaves it empty so it
/// compiles on its own; the app sets it (`UndoTrail.install()`).
nonisolated enum UndoTrailHook {

    // MARK: - Stored properties

    /// A step could not be written down: the action's key, the course and
    /// section, the mode, and a word for why. Never page text.
    nonisolated(unsafe) static var couldNotRecordLine: ((_ action: String, _ course: String, _ section: Int?, _ mode: UndoMode, _ why: String) -> Void)?

    /// Recovery or a failed swap put files back: the course and section,
    /// what it ended, and how many files.
    nonisolated(unsafe) static var rolledBackLine: ((_ course: String, _ section: Int?, _ phase: UndoPhase, _ files: Int) -> Void)?

    // MARK: - Functions

    static func couldNotRecord(draft: UndoStepDraft, mode: UndoMode, problem: Error) {
        couldNotRecordLine?(draft.action.key, draft.course, draft.section, mode, UndoTrailHook.word(for: problem))
    }

    static func couldNotFinish(seq: Int, problem: Error) {
        couldNotRecordLine?("step \(seq)", "", nil, UndoSwitch.currentMode, UndoTrailHook.word(for: problem))
    }

    /// A word for a problem, never its description (which can carry a path).
    static func word(for problem: Error) -> String {
        if let journalError = problem as? UndoJournalError {
            switch journalError {
            case .lockBusy:
                return "the list was busy"
            case .couldNotOpenTheLock, .couldNotStartASegment, .couldNotStoreContent:
                return "the list could not be written"
            case .couldNotSync:
                return "the list could not be saved to the disk"
            case .couldNotEncode:
                return "the step could not be written as a line"
            case .notTheNewestStep:
                return "the list had moved on"
            }
        }
        if problem is UndoShadowMismatch {
            return "what was written differed from what was recorded"
        }
        return "the list could not be written"
    }
}
