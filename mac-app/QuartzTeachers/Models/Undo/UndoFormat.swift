import Foundation

// The journal's lines, steps and ops, as `contracts/file-formats.json` →
// `undoJournal` describes them (#899, U1).
//
// **Every object here is OPEN.** A reader keeps a line, a step or an op it
// cannot fully read: it never drops it, never reuses its number, and never
// deletes what it might name. Lines are never rewritten, so "keeping" is the
// same as leaving the bytes where they are; what matters is that nothing a
// reader does not understand is treated as absent (the director's rulings 1
// and 2 on U1's review). So every decoder below is lenient: it never throws,
// and says instead whether what it read is readable by this version.

/// One line of the journal, as written.
nonisolated struct UndoEventLine: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    /// The format's version: the number 1.
    var v: Int

    /// The step the event is about; for `cleared`, the highest step number
    /// in the journal when the clearing was written.
    var seq: Int

    /// One of `UndoEventKind`.
    var event: String

    /// When it was written: UTC, ISO 8601 to the second.
    var at: String?

    /// The whole step, on `begin` only.
    var step: UndoStep?

    /// Which process started the work, on `begin`, `undoing` and `redoing`.
    var process: UndoProcess?

    /// What a `failed`, `rolledBack` or `interrupted` ended: `begin`,
    /// `undoing` or `redoing`.
    var phase: String?

    /// A word, never page text.
    var reason: String?

    /// `interrupted` only: the files left neither before nor after, inside
    /// the working folder. Paths, never content.
    var paths: [String]?

    // MARK: - Initializer

    init(
        seq: Int,
        event: UndoEventKind,
        at moment: Date? = nil,
        step: UndoStep? = nil,
        process: UndoProcess? = nil,
        phase: UndoPhase? = nil,
        reason: String? = nil,
        paths: [String]? = nil
    ) {
        self.v = UndoJournal.formatVersion
        self.seq = seq
        self.event = event.rawValue
        if let moment {
            self.at = UndoMoment.text(moment)
        }
        self.step = step
        self.process = process
        self.phase = phase?.rawValue
        self.reason = reason
        self.paths = paths
    }

    // MARK: - Functions

    /// The line's bytes: one JSON object, keys sorted, no line feed inside.
    /// Readers never compare these bytes; the sorting is for a person
    /// reading a diff.
    func encoded() throws -> Data {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data = try encoder.encode(self)
        for byte in data where byte == 0x0A {
            throw UndoJournalError.couldNotEncode
        }
        return data
    }

    /// The line typed, or nil when this version cannot read it. Lenient
    /// about what it can (a step's or an op's unknown fields are kept and
    /// marked); strict about the envelope (`v`, `event`, `seq`).
    static func decoded(from line: Data) -> UndoEventLine? {
        return UndoReadLine.read(line).event
    }
}

/// A line as read: its number whenever it has one, even when nothing else
/// of it can be read, so a newer version's step number is never reused.
nonisolated struct UndoReadLine: Sendable {

    // MARK: - Stored properties

    /// The line's `seq` when it holds a whole number there, whatever else.
    let seq: Int?

    /// When it says it was written, when it says so in a form this reads.
    let at: Date?

    /// The event, or nil: the line is not one this version can read.
    let event: UndoEventLine?

    /// For a line this version cannot read, and for a `begin` whose step it
    /// cannot read: every blob name its text holds (64 lower-case hex
    /// characters standing alone), so pruning keeps exactly what such a
    /// line could need (the director's ruling 5 on U1's second reviews).
    /// Empty for every line this version reads.
    var referencedBlobs: [String] = []

    // MARK: - Functions

    static func read(_ line: Data) -> UndoReadLine {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return UndoReadLine(seq: nil, at: nil, event: nil, referencedBlobs: blobNames(in: line))
        }
        let seq: Int? = wholeNumber(object["seq"])
        var at: Date? = nil
        if let text = object["at"] as? String {
            at = UndoMoment.date(text)
        }
        guard wholeNumber(object["v"]) == UndoJournal.formatVersion,
              let kindText = object["event"] as? String,
              let kind = UndoEventKind(rawValue: kindText),
              let seq else {
            return UndoReadLine(seq: seq, at: at, event: nil, referencedBlobs: blobNames(in: line))
        }
        if kind == .note {
            // Neutral: whatever else it carries, every reader passes over it.
            var note: UndoEventLine = UndoEventLine(seq: seq, event: .note)
            note.at = object["at"] as? String
            return UndoReadLine(seq: seq, at: at, event: note)
        }
        guard let event = try? JSONDecoder().decode(UndoEventLine.self, from: line) else {
            return UndoReadLine(seq: seq, at: at, event: nil, referencedBlobs: blobNames(in: line))
        }
        if kind == .begin {
            guard let step = event.step, step.seq == seq else {
                return UndoReadLine(seq: seq, at: at, event: nil, referencedBlobs: blobNames(in: line))
            }
            if !step.isReadable {
                return UndoReadLine(seq: seq, at: at, event: event, referencedBlobs: blobNames(in: line))
            }
        }
        if let phase = event.phase, UndoPhase(rawValue: phase) == nil {
            return UndoReadLine(seq: seq, at: at, event: nil, referencedBlobs: blobNames(in: line))
        }
        return UndoReadLine(seq: seq, at: at, event: event)
    }

    /// Every run of exactly 64 lower-case hexadecimal characters in the
    /// bytes, bounded by anything else: a blob name, wherever it sits.
    static func blobNames(in line: Data) -> [String] {
        var names: [String] = []
        var run: [UInt8] = []
        func endTheRun() {
            if run.count == 64 {
                let name: String = String(decoding: run, as: UTF8.self)
                if !names.contains(name) {
                    names.append(name)
                }
            }
            run = []
        }
        for byte in line {
            let isDigit: Bool = byte >= 0x30 && byte <= 0x39
            let isLowerHex: Bool = byte >= 0x61 && byte <= 0x66
            if isDigit || isLowerHex {
                run.append(byte)
            } else {
                endTheRun()
            }
        }
        endTheRun()
        return names
    }

    /// A JSON number that is a whole number (never a Boolean), or nil.
    static func wholeNumber(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else {
            return nil
        }
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }
        let double: Double = number.doubleValue
        if double.rounded() != double || double < 0 || double > 9_000_000_000_000_000 {
            return nil
        }
        return number.intValue
    }
}

/// The events a line can carry: the table of moves is `UndoFold.phase`.
nonisolated enum UndoEventKind: String, Sendable, CaseIterable {
    case begin
    case applied
    case rolledBack
    case interrupted
    case undoing
    case undone
    case redoing
    case redone
    case failed
    case dropped
    case pruned
    /// The whole list cleared: a refused Undo (ruling 13) and an interrupted
    /// step (the director's ruling 7 on U1's first reviews).
    case cleared
    /// A neutral line every reader passes over: it moves no step, is never a
    /// barrier, never stops deletion and never clears. Known to every reader
    /// from the first version, so a later version can record something an
    /// older reader must simply skip (the director's ruling 2 on U1's second
    /// reviews); U1 writes none outside the contract's cases and traces.
    case note
}

/// What a `failed`, `rolledBack` or `interrupted` event ended.
nonisolated enum UndoPhase: String, Sendable {
    case begin
    case undoing
    case redoing
}

/// One thing the teacher did once: everything it changed, in order.
///
/// Open: only `seq`, `madeAt` and `ops` are required. A step with no
/// working folder (a preference, from U4) or no course is readable as long
/// as none of its ops needs a folder.
nonisolated struct UndoStep: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    var seq: Int

    /// When it was made, UTC. For display and the limits only: never a check
    /// of whether a file has changed since (ruling 4, W6).
    var madeAt: String

    var action: UndoAction?

    /// `menu`, `sheet`, `wizard`, `builtInAssistant:<conversation id>` or
    /// `outsideAssistant:<client name>:<session id>`.
    var madeBy: String?

    var workingFolder: UndoWorkingFolder?

    var course: String?

    var section: Int?

    /// A, B or D (`undo.classes`, from U3).
    var actionClass: String?

    /// `section` or `course`.
    var holds: String?

    var ops: [UndoOp]

    /// False when this version cannot read the whole step: then it is kept,
    /// and Undo and Redo are not available while it is at or above the head.
    /// Worked out when read; never written.
    var isReadable: Bool = true

    /// The `holds` values this version knows. A step carrying any other is
    /// one it cannot read: it would take the wrong lease, or none, to undo
    /// it (`undoJournal.stepKeys.holds`, the Fable sweep's T2). Absent is
    /// readable. `madeBy`, `class` and `action.key` are open: never checked.
    static let holdsThisVersionKnows: Set<String> = ["section", "course"]

    enum CodingKeys: String, CodingKey {
        case seq
        case madeAt
        case action
        case madeBy
        case workingFolder
        case course
        case section
        case actionClass = "class"
        case holds
        case ops
    }

    // MARK: - Initializer

    init(
        seq: Int,
        madeAt: String,
        action: UndoAction?,
        madeBy: String?,
        workingFolder: UndoWorkingFolder?,
        course: String?,
        section: Int?,
        actionClass: String?,
        holds: String?,
        ops: [UndoOp]
    ) {
        self.seq = seq
        self.madeAt = madeAt
        self.action = action
        self.madeBy = madeBy
        self.workingFolder = workingFolder
        self.course = course
        self.section = section
        self.actionClass = actionClass
        self.holds = holds
        self.ops = ops
    }

    /// Never throws for a step it cannot read; marks it instead. Throws only
    /// when there is no object at all, or no number.
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int.self, forKey: .seq)
        var readable: Bool = true
        let made: String? = UndoLenient.string(container, .madeAt, &readable)
        madeAt = made ?? ""
        if made == nil || UndoMoment.date(madeAt) == nil {
            readable = false
        }
        action = UndoLenient.value(UndoAction.self, container, .action, &readable)
        madeBy = UndoLenient.string(container, .madeBy, &readable)
        workingFolder = UndoLenient.value(UndoWorkingFolder.self, container, .workingFolder, &readable)
        course = UndoLenient.string(container, .course, &readable)
        section = UndoLenient.int(container, .section, &readable)
        actionClass = UndoLenient.string(container, .actionClass, &readable)
        holds = UndoLenient.string(container, .holds, &readable)
        if let given = holds, !UndoStep.holdsThisVersionKnows.contains(given) {
            readable = false
        }
        if let decoded = try? container.decode([UndoOp].self, forKey: .ops) {
            ops = decoded
        } else {
            ops = []
            readable = false
        }
        var needsAFolder: Bool = false
        for op in ops {
            if !op.isReadable {
                readable = false
            }
            if !op.pathsNamed.isEmpty {
                needsAFolder = true
            }
        }
        if needsAFolder && workingFolder == nil {
            readable = false
        }
        if !UndoStep.wholeOpsStandAlone(ops) {
            readable = false
        }
        isReadable = readable
    }

    /// A move's places, a tree's folder and everything in it, and an
    /// external op's target are named by no other op of the step (U2). Such
    /// an op is checked and changed as a whole against the disk as it is,
    /// never against what an earlier op of the same step would leave, so a
    /// step where two ops share a place is one this version cannot read: it
    /// is a barrier, never undone in a guessed order.
    static func wholeOpsStandAlone(_ ops: [UndoOp]) -> Bool {
        var index: Int = 0
        while index < ops.count {
            let op: UndoOp = ops[index]
            if op.isWhole {
                var other: Int = 0
                while other < ops.count {
                    if other != index {
                        let second: UndoOp = ops[other]
                        if let target = op.target, second.target == target {
                            return false
                        }
                        // U4b: an edit inside what a move moved, named at its
                        // new place and written after it, is the one op that
                        // may share a move's place (opKinds.wholeOps' order).
                        if other > index && UndoOp.moveCarries(op, second) {
                            other += 1
                            continue
                        }
                        for mine in op.pathsNamed {
                            for theirs in second.pathsNamed where UndoOp.placesOverlap(mine, theirs) {
                                return false
                            }
                        }
                    }
                    other += 1
                }
            }
            index += 1
        }
        return true
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seq, forKey: .seq)
        try container.encode(madeAt, forKey: .madeAt)
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(madeBy, forKey: .madeBy)
        try container.encodeIfPresent(workingFolder, forKey: .workingFolder)
        try container.encodeIfPresent(course, forKey: .course)
        try container.encodeIfPresent(section, forKey: .section)
        try container.encodeIfPresent(actionClass, forKey: .actionClass)
        try container.encodeIfPresent(holds, forKey: .holds)
        try container.encode(ops, forKey: .ops)
    }
}

/// A step's name, as data.
nonisolated struct UndoAction: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    var key: String

    var arguments: [String: String]
}

/// Which working folder a step was made in.
nonisolated struct UndoWorkingFolder: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    /// The folder's own identifier (`courses/.internal/folder-id`), lower case.
    var id: String

    /// Where it was, canonical, when the step was made.
    var pathAtTheTime: String
}

/// The process that started a piece of work.
nonisolated struct UndoProcess: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    /// For a person reading the file. Never compared.
    var host: String

    var pid: Int32

    /// The name the process table reports.
    var name: String

    /// When it started, as `ProcessLiveness.startTimeText` writes it.
    var started: String

    // MARK: - Functions

    /// This process.
    static func current() -> UndoProcess {
        let pid: Int32 = getpid()
        var name: String = ProcessInfo.processInfo.processName
        var started: String = ""
        let table: ProcessLiveness.TableAnswer = ProcessLiveness.askTheProcessTable(pid: pid)
        if case .found(let tableName, _, let startTime) = table {
            if !tableName.isEmpty {
                name = tableName
            }
            started = startTime
        }
        return UndoProcess(host: UndoProcess.hostName(), pid: pid, name: name, started: started)
    }

    /// The work leases' liveness rule.
    @Sendable static func isStillRunning(_ process: UndoProcess) -> Bool {
        return ProcessLiveness.ownerIsAlive(
            pid: process.pid,
            recordedName: process.name,
            recordedStart: process.started
        )
    }

    /// The host name from the kernel, which answers at once.
    static func hostName() -> String {
        var buffer: [CChar] = [CChar](repeating: 0, count: 256)
        if gethostname(&buffer, buffer.count) != 0 {
            return ""
        }
        var bytes: [UInt8] = []
        for character in buffer {
            if character == 0 {
                break
            }
            bytes.append(UInt8(bitPattern: character))
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// One thing a step changed, recorded so it can be checked and reversed.
///
/// Open: `kind` is the only key every op has. An op inside a working folder
/// has `path` (a `move` has `from` and `to` instead); one that needs content
/// from the journal names every blob in `blobs`, whatever its kind, so a
/// pruner that cannot read the op still keeps what it needs. U1 wrote
/// `writeFile` and `editLine` and recorded `recompute`; U2 defines
/// `replaceText`, `editJSON`, `move`, `createTree`, `removeTree` and
/// `external` (`undoJournal.opKinds`). The shapes still reserved for U5
/// (`trash`, `storeHeld`) are kinds this version does not know. An op this
/// version cannot read makes its step unreadable; it is never guessed at.
nonisolated struct UndoOp: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    var kind: String

    /// Inside the working folder (relative to the folder that holds
    /// `courses/`), forward slashes, as the file system spells it.
    var path: String?

    /// Every blob this op needs from `content/`.
    var blobs: [String]?

    /// `writeFile`: the whole file's SHA-256 before and after, nil for none.
    var beforeSha: String?
    var afterSha: String?

    /// `editLine`: the key, and its entry before and after. `replaceText`:
    /// the hunk's text before and after.
    var key: String?
    var before: String?
    var after: String?

    /// `editLine`: the key of the entry before this one.
    var afterKey: String?

    /// `editLine`: the step gave the page its front matter.
    var createdTheBlock: Bool?

    /// `recompute`: the maintainer, and for which section.
    var maintainer: String?
    var section: Int?

    /// `replaceText`: the text either side of the hunk, kept as it was.
    var contextBefore: String?
    var contextAfter: String?

    /// `editJSON`: the members to walk, from the top-level object down.
    var keyPath: [String]?

    /// `editJSON` and `external`: the value before and after, any JSON. Nil
    /// is "no such member" (or "not set"); `.null` is JSON's null.
    var valueBefore: UndoJSON?
    var valueAfter: UndoJSON?

    /// `move`: where the item was and where it went.
    var from: String?
    var to: String?

    /// `move` of a file: its SHA-256. Never a blob: the file itself is
    /// what moves.
    var sha: String?

    /// `move` of a folder, `createTree` and `removeTree`: the SHA-256 of
    /// the folder's listing (`UndoTreeListing`).
    var listingSha: String?

    /// `move` of a symbolic link (U4b2-14): the SHA-256 of the bytes the
    /// link holds, its target as written, read with `readlink`. The link
    /// itself is what moves; what it leads to is never read or touched.
    var linkSha: String?

    /// `external`: what outside the working folder it changed.
    var target: String?

    /// False when this version cannot read the op. Never written.
    var isReadable: Bool = true

    /// The `recompute` maintainers this version can run. Any other makes the
    /// op unreadable (`undoJournal.opKinds.recompute`).
    static let maintainersThisVersionKnows: Set<String> = ["sectionFrontPage"]

    /// The `external` targets this version can read and write, by the part
    /// before the first colon: `preference:<name>` is one of the app's own
    /// preferences; `scheduledDeploy:<label>` (U3b) is a deploy set for
    /// later, its LaunchAgent and the script it runs. Any other makes the op
    /// unreadable.
    static let externalTargetsThisVersionKnows: Set<String> = ["preference", UndoOp.scheduledDeployFamily]

    /// The family of a deploy set for later (`scheduledDeploy:<label>`).
    static let scheduledDeployFamily: String = "scheduledDeploy"

    enum CodingKeys: String, CodingKey {
        case kind
        case path
        case blobs
        case beforeSha
        case afterSha
        case key
        case before
        case after
        case afterKey
        case createdTheBlock
        case maintainer
        case section
        case contextBefore
        case contextAfter
        case keyPath
        case from
        case to
        case sha
        case listingSha
        case linkSha
        case target
        // Read only to say the op cannot be read: a later piece's meaning.
        case element
        case heldBy
    }

    // MARK: - Initializer

    init(kind: String, path: String?) {
        self.kind = kind
        self.path = path
    }

    /// Never throws: an op that is not an object, or that this version
    /// cannot read, comes back marked unreadable.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            kind = ""
            isReadable = false
            return
        }
        var readable: Bool = true
        kind = UndoLenient.string(container, .kind, &readable) ?? ""
        path = UndoLenient.string(container, .path, &readable)
        blobs = UndoLenient.value([String].self, container, .blobs, &readable)
        beforeSha = UndoLenient.string(container, .beforeSha, &readable)
        afterSha = UndoLenient.string(container, .afterSha, &readable)
        key = UndoLenient.string(container, .key, &readable)
        let valuesAreJSON: Bool = kind == UndoOpKind.editJSON.rawValue || kind == UndoOpKind.external.rawValue
        if valuesAreJSON {
            // Any JSON, null included: a member that is there holding null
            // is not a member that is absent.
            valueBefore = UndoLenient.json(container, .before, &readable)
            valueAfter = UndoLenient.json(container, .after, &readable)
        } else {
            before = UndoLenient.string(container, .before, &readable)
            after = UndoLenient.string(container, .after, &readable)
        }
        afterKey = UndoLenient.string(container, .afterKey, &readable)
        createdTheBlock = UndoLenient.value(Bool.self, container, .createdTheBlock, &readable)
        maintainer = UndoLenient.string(container, .maintainer, &readable)
        section = UndoLenient.int(container, .section, &readable)
        contextBefore = UndoLenient.string(container, .contextBefore, &readable)
        contextAfter = UndoLenient.string(container, .contextAfter, &readable)
        keyPath = UndoLenient.value([String].self, container, .keyPath, &readable)
        from = UndoLenient.string(container, .from, &readable)
        to = UndoLenient.string(container, .to, &readable)
        sha = UndoLenient.string(container, .sha, &readable)
        listingSha = UndoLenient.string(container, .listingSha, &readable)
        linkSha = UndoLenient.string(container, .linkSha, &readable)
        target = UndoLenient.string(container, .target, &readable)
        // `element` (editJSON) and `heldBy` (removeTree) are the reserved
        // shapes' keys for meanings a later piece settles: an op carrying
        // either is one this version cannot undo by its own rule, so it is
        // one it cannot read (`undoJournal.unknown.keys`).
        if container.contains(.element) && kind == UndoOpKind.editJSON.rawValue {
            readable = false
        }
        if container.contains(.heldBy) && kind == UndoOpKind.removeTree.rawValue {
            readable = false
        }
        isReadable = readable && UndoOp.shapeIsKnown(self)
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(blobs, forKey: .blobs)
        try container.encodeIfPresent(beforeSha, forKey: .beforeSha)
        try container.encodeIfPresent(afterSha, forKey: .afterSha)
        try container.encodeIfPresent(key, forKey: .key)
        if let valueBefore {
            try container.encode(valueBefore, forKey: .before)
        } else {
            try container.encodeIfPresent(before, forKey: .before)
        }
        if let valueAfter {
            try container.encode(valueAfter, forKey: .after)
        } else {
            try container.encodeIfPresent(after, forKey: .after)
        }
        try container.encodeIfPresent(afterKey, forKey: .afterKey)
        try container.encodeIfPresent(createdTheBlock, forKey: .createdTheBlock)
        try container.encodeIfPresent(maintainer, forKey: .maintainer)
        try container.encodeIfPresent(section, forKey: .section)
        try container.encodeIfPresent(contextBefore, forKey: .contextBefore)
        try container.encodeIfPresent(contextAfter, forKey: .contextAfter)
        try container.encodeIfPresent(keyPath, forKey: .keyPath)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encodeIfPresent(sha, forKey: .sha)
        try container.encodeIfPresent(listingSha, forKey: .listingSha)
        try container.encodeIfPresent(linkSha, forKey: .linkSha)
        try container.encodeIfPresent(target, forKey: .target)
    }

    // MARK: - Computed properties

    var knownKind: UndoOpKind? {
        if !isReadable {
            return nil
        }
        return UndoOpKind(rawValue: kind)
    }

    /// Every blob the op names, from `blobs`, its two hashes and its
    /// listing.
    var namedBlobs: [String] {
        var names: [String] = []
        for name in blobs ?? [] {
            names.append(name)
        }
        if let beforeSha {
            names.append(beforeSha)
        }
        if let afterSha {
            names.append(afterSha)
        }
        // A moved folder's listing is never a blob: the folder itself is
        // what moves (opKinds.move). Found by the first folder moved through
        // the door (U4b).
        let isAMove: Bool = knownKind == .move || knownKind == .moveApart || knownKind == .setAside
        if let listingSha, !isAMove, !names.contains(listingSha) {
            names.append(listingSha)
        }
        return names
    }

    /// Every path inside the working folder the op names: its `path`, or a
    /// move's `from` and `to`. Empty for an `external` op.
    var pathsNamed: [String] {
        var paths: [String] = []
        if let path {
            paths.append(path)
        }
        if let from {
            paths.append(from)
        }
        if let to {
            paths.append(to)
        }
        return paths
    }

    /// The name recovery and a refusal use for this op's place: its path, a
    /// move's `from`, or an external op's target.
    var placeName: String {
        if let path {
            return path
        }
        if let from {
            return from
        }
        return target ?? kind
    }

    /// Where a teacher finds the item a step names now, going this way: a
    /// `move`'s `to` before it is undone and its `from` before it is redone
    /// (U4b: a refused Undo of a rename names the renamed folder, never the
    /// place it had before the step); `placeName` for every other op.
    func placeAsFound(going direction: UndoDirection) -> String {
        if knownKind == .move, let from, let to {
            return direction == .backward ? to : from
        }
        return placeName
    }

    /// A move, a tree or an external op: checked and changed as a whole, on
    /// its own, never folded into another op's file (`UndoStep`'s rule that
    /// no other op of the step names its places).
    var isWhole: Bool {
        guard let kind = knownKind else {
            return false
        }
        return kind == .move || kind == .moveApart || kind == .setAside || kind == .createTree || kind == .removeTree || kind == .external
    }

    /// Whether an undo or a redo that finds this op changed since leaves it
    /// where it is and goes on with the rest of the step, reporting it
    /// (`moveApart`, `setAside`, and an `external` op on a scheduled deploy:
    /// the rollover's records, its leftovers and the schedule it removed,
    /// U3b). Making the
    /// step never leaves one apart: a step is made whole or not at all.
    var standsApart: Bool {
        guard let kind = knownKind else {
            return false
        }
        if kind == .moveApart || kind == .setAside {
            return true
        }
        if kind == .external, let target = target {
            return target.hasPrefix(UndoOp.scheduledDeployFamily + ":")
        }
        return false
    }

    // MARK: - Functions

    static func writeFile(path: String, beforeSha: String?, afterSha: String?) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.writeFile.rawValue, path: path)
        op.beforeSha = beforeSha
        op.afterSha = afterSha
        var named: [String] = []
        if let beforeSha {
            named.append(beforeSha)
        }
        if let afterSha {
            named.append(afterSha)
        }
        op.blobs = named
        return op
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

    static func replaceText(
        path: String,
        before: String,
        after: String,
        contextBefore: String,
        contextAfter: String
    ) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.replaceText.rawValue, path: path)
        op.before = before
        op.after = after
        op.contextBefore = contextBefore
        op.contextAfter = contextAfter
        return op
    }

    static func editJSON(path: String, keyPath: [String], before: UndoJSON?, after: UndoJSON?) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.editJSON.rawValue, path: path)
        op.keyPath = keyPath
        op.valueBefore = before
        op.valueAfter = after
        return op
    }

    static func moveFile(from: String, to: String, sha: String) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.move.rawValue, path: nil)
        op.from = from
        op.to = to
        op.sha = sha
        return op
    }

    /// A file moved that stands apart from its step (`moveApart`).
    static func moveFileApart(from: String, to: String, sha: String) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.moveApart.rawValue, path: nil)
        op.from = from
        op.to = to
        op.sha = sha
        return op
    }

    /// A leftover file set aside, standing apart from its step on its own
    /// (`setAside`).
    static func setFileAside(from: String, to: String, sha: String) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.setAside.rawValue, path: nil)
        op.from = from
        op.to = to
        op.sha = sha
        return op
    }

    static func moveFolder(from: String, to: String, listingSha: String) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.move.rawValue, path: nil)
        op.from = from
        op.to = to
        op.listingSha = listingSha
        return op
    }

    /// A symbolic link moved as itself (U4b2-14, opKinds.move): judged by
    /// `linkSha`, the SHA-256 of its target as written.
    static func moveLink(from: String, to: String, linkSha: String) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.move.rawValue, path: nil)
        op.from = from
        op.to = to
        op.linkSha = linkSha
        return op
    }

    /// `createTree` or `removeTree`: blobs are the listing's and every
    /// file's content, so the tree can be made again.
    static func tree(_ kind: UndoOpKind, path: String, listing: UndoTreeListing) -> UndoOp {
        var op: UndoOp = UndoOp(kind: kind.rawValue, path: path)
        op.listingSha = listing.sha
        var names: [String] = [listing.sha]
        for file in listing.files where !names.contains(file.sha) {
            names.append(file.sha)
        }
        op.blobs = names
        return op
    }

    static func external(target: String, before: UndoJSON?, after: UndoJSON?) -> UndoOp {
        var op: UndoOp = UndoOp(kind: UndoOpKind.external.rawValue, path: nil)
        op.target = target
        op.valueBefore = before
        op.valueAfter = after
        return op
    }

    /// Whether an op read from the journal has a shape this version can act
    /// on: a known kind, safe paths, and the fields that kind needs.
    static func shapeIsKnown(_ op: UndoOp) -> Bool {
        guard let kind = UndoOpKind(rawValue: op.kind) else {
            return false
        }
        for name in op.namedBlobs where !UndoOp.isBlobName(name) {
            return false
        }
        if let sha = op.sha, !UndoOp.isBlobName(sha) {
            return false
        }
        if let linkSha = op.linkSha, !UndoOp.isBlobName(linkSha) {
            return false
        }
        switch kind {
        case .move, .moveApart, .setAside:
            // No `path`: `from` and `to` follow path's rules, differ, and
            // neither holds the other. Exactly one of a file's `sha`, a
            // folder's `listingSha` and a link's `linkSha` (U4b2-14): a
            // reader that knows no `linkSha` finds neither of the other two,
            // so it cannot read the op rather than misread it.
            guard op.path == nil, let from = op.from, let to = op.to else {
                return false
            }
            if !UndoOp.isSafeRelativePath(from) || !UndoOp.isSafeRelativePath(to) {
                return false
            }
            // One exception (U4b): a capitalisation-only rename, the two
            // spellings one place on a case-insensitive volume.
            if UndoOp.placesOverlap(from, to) && !op.isCaseOnlyMove {
                return false
            }
            var contents: Int = 0
            for given in [op.sha, op.listingSha, op.linkSha] where given != nil {
                contents += 1
            }
            return contents == 1
        case .external:
            guard op.path == nil, let target = op.target else {
                return false
            }
            guard let colon = target.firstIndex(of: ":") else {
                return false
            }
            let family: String = String(target[target.startIndex..<colon])
            let name: String = String(target[target.index(after: colon)...])
            if name.isEmpty || !UndoOp.externalTargetsThisVersionKnows.contains(family) {
                return false
            }
            return op.valueBefore != nil || op.valueAfter != nil
        default:
            break
        }
        guard let path = op.path, UndoOp.isSafeRelativePath(path) else {
            return false
        }
        switch kind {
        case .writeFile:
            return op.beforeSha != nil || op.afterSha != nil
        case .editLine:
            return op.key != nil && (op.before != nil || op.after != nil)
        case .recompute:
            // A maintainer this version does not know is a re-derivation it
            // cannot run, so the op is one it cannot read and its step is a
            // barrier (`undoJournal.opKinds.recompute`, the Fable sweep's T1).
            guard let maintainer = op.maintainer else {
                return false
            }
            return UndoOp.maintainersThisVersionKnows.contains(maintainer)
        case .replaceText:
            // Every part present (an empty string is a part), and the two
            // windows differ, or the hunk could never tell its states apart.
            guard let before = op.before, let after = op.after,
                  let contextBefore = op.contextBefore, let contextAfter = op.contextAfter else {
                return false
            }
            return !UndoText.same(contextBefore + before + contextAfter, contextBefore + after + contextAfter)
        case .editJSON:
            guard let keyPath = op.keyPath, !keyPath.isEmpty else {
                return false
            }
            if op.valueBefore == nil && op.valueAfter == nil {
                return false
            }
            return op.valueBefore != op.valueAfter
        case .createTree, .removeTree:
            guard let listingSha = op.listingSha, let blobs = op.blobs else {
                return false
            }
            return blobs.contains(listingSha)
        case .move, .moveApart, .setAside, .external:
            return false
        }
    }

    /// Whether `edit` is an edit (a `writeFile`, an `editLine`, a
    /// `replaceText` or an `editJSON`) of the file a `move` moved, or of a
    /// file inside the folder it moved, named at the NEW place and naming
    /// nothing inside the old one (U4b, opKinds.wholeOps). Such an edit is
    /// made, and redone, after the move, and taken back before it; the move
    /// is judged against what it holds once that step's own edits inside
    /// are taken back. Whether it comes after the move in the step's ops is
    /// the caller's to check. "At or inside `to`" is `partInside`, the one
    /// comparison, without regard to case (U4b2-9).
    static func moveCarries(_ move: UndoOp, _ edit: UndoOp) -> Bool {
        guard move.knownKind == .move, let from = move.from, let to = move.to, let path = edit.path else {
            return false
        }
        // A link's move carries nothing (U4b2-14, review 1, MEDIUM 1): a
        // link is neither a file nor a folder the move moved, so an edit
        // under its `to` breaks opKinds.wholeOps and the step is unreadable.
        if move.linkSha != nil {
            return false
        }
        switch edit.knownKind {
        case .writeFile, .editLine, .replaceText, .editJSON:
            break
        default:
            return false
        }
        if edit.from != nil || edit.to != nil || edit.target != nil {
            return false
        }
        if UndoOp.partInside(to, of: path) == nil {
            return false
        }
        if move.isCaseOnlyMove {
            // The two spellings are one place: the edit is named at the new
            // spelling, never at the old one. Only the moved item's own part
            // is compared as spelled, the parts above it by `partInside`
            // (review 1 of U4b2-9, L3).
            let fromParts: [Substring] = from.split(separator: "/", omittingEmptySubsequences: false)
            let pathParts: [Substring] = path.split(separator: "/", omittingEmptySubsequences: false)
            return pathParts[fromParts.count - 1] != fromParts[fromParts.count - 1]
        }
        return !UndoOp.placesOverlap(from, path)
    }

    /// U4b: a `move` whose `from` and `to` are spelled alike but for case,
    /// and differ in their last part only (`Media` to `media`): a
    /// capitalisation-only rename, readable although the two places overlap
    /// as `placesOverlap` compares them (opKinds.move). On a case-insensitive
    /// volume the two spellings are one place, judged by the spelling its
    /// folder lists (`UndoMoveSide.spellingListed`); on a case-sensitive one
    /// they are two places, judged as any move.
    var isCaseOnlyMove: Bool {
        guard knownKind == .move, let from, let to, from != to, from.lowercased() == to.lowercased() else {
            return false
        }
        return (from as NSString).deletingLastPathComponent == (to as NSString).deletingLastPathComponent
    }

    /// The place `path`, named inside a move's `to`, had before the move:
    /// the same path under its `from`.
    static func placeBeforeTheMove(_ path: String, from: String, to: String) -> String {
        guard let inside = UndoOp.partInside(to, of: path) else {
            return path
        }
        return inside.isEmpty ? from : from + "/" + inside
    }

    /// U4b2-9: the part of `path` inside `place`, spelled as `path` spells
    /// it: "" when `path` is `place` itself, nil when it is neither the
    /// place nor inside it. Compared part by part WITHOUT regard to case,
    /// the ONE comparison for "at or inside": `placesOverlap`,
    /// `moveCarries`, a swap's own files inside a moved folder
    /// (`ownFilesInside`) and following them when it moves
    /// (`followTheMove`), and a carried page's place before the move. The
    /// working folder's volume is case-insensitive on the Mac by default
    /// and on Windows, so `Renamed/a.md` is inside `renamed` there; the
    /// part-two review of U4b, LOW 2, found `moveCarries` matching without
    /// regard to case while the swap compared as spelled.
    static func partInside(_ place: String, of path: String) -> String? {
        let placeParts: [Substring] = place.split(separator: "/", omittingEmptySubsequences: false)
        let pathParts: [Substring] = path.split(separator: "/", omittingEmptySubsequences: false)
        if pathParts.count < placeParts.count {
            return nil
        }
        var index: Int = 0
        while index < placeParts.count {
            if placeParts[index].lowercased() != pathParts[index].lowercased() {
                return nil
            }
            index += 1
        }
        var rest: [Substring] = []
        while index < pathParts.count {
            rest.append(pathParts[index])
            index += 1
        }
        return rest.joined(separator: "/")
    }

    /// Whether two places are the same, or one is a folder holding the
    /// other (compared part by part, by `partInside`).
    ///
    /// Compared WITHOUT regard to case: a Mac's volume (and Windows') is
    /// usually case-insensitive, so `a.json` and `A.json` are one place
    /// there, and a move between them or two ops naming them is refused as
    /// a step this version cannot read (the hard review of U2b, MEDIUM 7).
    static func placesOverlap(_ first: String, _ second: String) -> Bool {
        return UndoOp.partInside(first, of: second) != nil || UndoOp.partInside(second, of: first) != nil
    }

    /// A path a step may name: relative, forward slashes, no `.` or `..`
    /// part, no empty part, no drive letter, no backslash, no NUL.
    static func isSafeRelativePath(_ path: String) -> Bool {
        if path.isEmpty || path.hasPrefix("/") || path.contains("\\") || path.contains("\u{0}") {
            return false
        }
        let parts: [Substring] = path.split(separator: "/", omittingEmptySubsequences: false)
        for part in parts {
            if part.isEmpty || part == "." || part == ".." {
                return false
            }
        }
        let characters: [Character] = Array(path)
        if characters.count >= 2 && characters[1] == ":" && characters[0].isLetter {
            return false
        }
        return true
    }

    /// 64 lower-case hexadecimal characters.
    static func isBlobName(_ name: String) -> Bool {
        if name.count != 64 {
            return false
        }
        for scalar in name.unicodeScalars {
            let isDigit: Bool = scalar.value >= 48 && scalar.value <= 57
            let isLowerHex: Bool = scalar.value >= 97 && scalar.value <= 102
            if !isDigit && !isLowerHex {
                return false
            }
        }
        return true
    }
}

/// The kinds of op this version can act on.
nonisolated enum UndoOpKind: String, Sendable {
    case writeFile
    case editLine
    case recompute
    /// U2: a hunk of a page's body, found by the text either side of it.
    case replaceText
    /// U2: one member of a JSON file, found by its key path.
    case editJSON
    /// U2: a file or a folder moved, reversed only as a whole pair.
    case move
    /// U3b: a move judged as `move` is, which STANDS APART from the rest of
    /// its step: when an undo or a redo finds its pair changed since (a
    /// deploy wrote a new marker in the place a rollover emptied), it is
    /// left where it is and reported, and the rest of the step goes ahead
    /// (Russell's ruling of 2026-11-19 on Q3; #959). A kind of its own,
    /// never a key on `move`: an older reader would undo a key's meaning by
    /// the old rule (`undoJournal.unknown.keys`).
    case moveApart
    /// U3b: a move judged as `move` is, which stands apart from its step ON
    /// ITS OWN: a leftover no deploy reads, set aside by a rollover (an old
    /// website record brought in from the built output, or a current record
    /// no deploy can read). An undo or a redo that finds its pair changed
    /// since leaves it and names it, as for `moveApart`, but it is never one
    /// of the step's group of `moveApart` records: a file no deploy reads
    /// never decides which website the section is on (the review of U3b's
    /// fixes, LOW 3). Its own kind for the reason `moveApart` is.
    case setAside
    /// U2: a folder made, with everything in it.
    case createTree
    /// U2: a folder removed, with everything in it kept in the list.
    case removeTree
    /// U2: something outside every working folder (one of the app's
    /// preferences in this version).
    case external
}

/// Reading a field without throwing: absent and null are nil; a value of
/// the wrong type is nil AND marks what holds it unreadable.
nonisolated enum UndoLenient {

    // MARK: - Functions

    static func string<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key, _ readable: inout Bool) -> String? {
        return value(String.self, container, key, &readable)
    }

    static func int<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key, _ readable: inout Bool) -> Int? {
        return value(Int.self, container, key, &readable)
    }

    static func value<Value: Decodable, Key: CodingKey>(
        _ type: Value.Type,
        _ container: KeyedDecodingContainer<Key>,
        _ key: Key,
        _ readable: inout Bool
    ) -> Value? {
        if !container.contains(key) {
            return nil
        }
        if (try? container.decodeNil(forKey: key)) == true {
            return nil
        }
        if let found = try? container.decode(type, forKey: key) {
            return found
        }
        readable = false
        return nil
    }

    /// Any JSON value, null included: absent is nil, a null is `.null`. A
    /// value no JSON reader takes marks what holds it unreadable.
    static func json<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key, _ readable: inout Bool) -> UndoJSON? {
        if !container.contains(key) {
            return nil
        }
        if let found = try? container.decode(UndoJSON.self, forKey: key) {
            return found
        }
        readable = false
        return nil
    }
}

/// The one spelling of a moment in the journal: UTC, to the second.
///
/// Read by hand for the form every line is written in, because the fold reads
/// a moment for every line and every step: a date formatter made per call
/// cost about 80 microseconds each, which made a one-page publish cost 83 ms
/// against a 4 MB journal (measured in the U1 harness, M4 Pro). Any other
/// ISO 8601 form falls back to the formatter.
nonisolated enum UndoMoment {

    // MARK: - Stored properties

    /// Formatters are safe to share between threads (Apple's Data Formatting
    /// Guide); these are made once and never changed.
    nonisolated(unsafe) private static let writing: ISO8601DateFormatter = {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    nonisolated(unsafe) private static let readingWithFractions: ISO8601DateFormatter = {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Functions

    static func text(_ moment: Date) -> String {
        return writing.string(from: moment)
    }

    /// A moment as the journal writes it, or any ISO 8601 moment with an
    /// offset or fractions of a second.
    static func date(_ text: String) -> Date? {
        if let quick = UndoMoment.quickDate(text) {
            return quick
        }
        if let plain = writing.date(from: text) {
            return plain
        }
        return readingWithFractions.date(from: text)
    }

    /// `2026-11-13T21:04:05Z` exactly, read without a formatter; nil for any
    /// other shape (which the formatter then reads).
    static func quickDate(_ text: String) -> Date? {
        let bytes: [UInt8] = Array(text.utf8)
        if bytes.count != 20 || bytes[4] != 0x2D || bytes[7] != 0x2D || bytes[10] != 0x54
            || bytes[13] != 0x3A || bytes[16] != 0x3A || bytes[19] != 0x5A {
            return nil
        }
        func number(_ from: Int, _ count: Int) -> Int? {
            var value: Int = 0
            var index: Int = from
            while index < from + count {
                let byte: UInt8 = bytes[index]
                if byte < 0x30 || byte > 0x39 {
                    return nil
                }
                value = value * 10 + Int(byte - 0x30)
                index += 1
            }
            return value
        }
        guard let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2) else {
            return nil
        }
        if month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60 {
            return nil
        }
        // Days from 1970-01-01 to the date in the proleptic Gregorian
        // calendar (Howard Hinnant's days_from_civil).
        let shiftedYear: Int = month <= 2 ? year - 1 : year
        let era: Int = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra: Int = shiftedYear - era * 400
        let shiftedMonth: Int = month > 2 ? month - 3 : month + 9
        let dayOfYear: Int = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra: Int = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days: Int = era * 146_097 + dayOfEra - 719_468
        let seconds: Int = days * 86_400 + hour * 3_600 + minute * 60 + second
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}
