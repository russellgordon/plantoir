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

    // MARK: - Functions

    static func read(_ line: Data) -> UndoReadLine {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return UndoReadLine(seq: nil, at: nil, event: nil)
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
            return UndoReadLine(seq: seq, at: at, event: nil)
        }
        guard let event = try? JSONDecoder().decode(UndoEventLine.self, from: line) else {
            return UndoReadLine(seq: seq, at: at, event: nil)
        }
        if kind == .begin {
            guard let step = event.step, step.seq == seq else {
                return UndoReadLine(seq: seq, at: at, event: nil)
            }
        }
        if let phase = event.phase, UndoPhase(rawValue: phase) == nil {
            return UndoReadLine(seq: seq, at: at, event: nil)
        }
        return UndoReadLine(seq: seq, at: at, event: event)
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
    /// The whole list cleared: rulings 13, 14 and 16, and an interrupted
    /// step (the director's ruling 7 on U1's review).
    case cleared
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
            if op.path != nil {
                needsAFolder = true
            }
        }
        if needsAFolder && workingFolder == nil {
            readable = false
        }
        isReadable = readable
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
/// has `path`; one that needs content from the journal names every blob in
/// `blobs`, whatever its kind, so a pruner that cannot read the op still
/// keeps what it needs. U1 writes `writeFile` and `editLine` and records
/// `recompute`; the shapes reserved for U2 to U5 are in the contract
/// (`undoJournal.opKinds`). An op this version cannot read makes its step
/// unreadable; it is never guessed at.
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

    /// `editLine`: the key, and its entry before and after.
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

    /// False when this version cannot read the op. Never written.
    var isReadable: Bool = true

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
        before = UndoLenient.string(container, .before, &readable)
        after = UndoLenient.string(container, .after, &readable)
        afterKey = UndoLenient.string(container, .afterKey, &readable)
        createdTheBlock = UndoLenient.value(Bool.self, container, .createdTheBlock, &readable)
        maintainer = UndoLenient.string(container, .maintainer, &readable)
        section = UndoLenient.int(container, .section, &readable)
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
        try container.encodeIfPresent(before, forKey: .before)
        try container.encodeIfPresent(after, forKey: .after)
        try container.encodeIfPresent(afterKey, forKey: .afterKey)
        try container.encodeIfPresent(createdTheBlock, forKey: .createdTheBlock)
        try container.encodeIfPresent(maintainer, forKey: .maintainer)
        try container.encodeIfPresent(section, forKey: .section)
    }

    // MARK: - Computed properties

    var knownKind: UndoOpKind? {
        if !isReadable {
            return nil
        }
        return UndoOpKind(rawValue: kind)
    }

    /// Every blob the op names, from `blobs` and its two hashes.
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
        return names
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

    /// Whether an op read from the journal has a shape this version can act
    /// on: a known kind, a safe path, and the fields that kind needs.
    static func shapeIsKnown(_ op: UndoOp) -> Bool {
        guard let kind = UndoOpKind(rawValue: op.kind) else {
            return false
        }
        guard let path = op.path, UndoOp.isSafeRelativePath(path) else {
            return false
        }
        for name in op.namedBlobs where !UndoOp.isBlobName(name) {
            return false
        }
        switch kind {
        case .writeFile:
            return op.beforeSha != nil || op.afterSha != nil
        case .editLine:
            return op.key != nil && (op.before != nil || op.after != nil)
        case .recompute:
            return op.maintainer != nil
        }
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

/// The kinds of op U1 can act on.
nonisolated enum UndoOpKind: String, Sendable {
    case writeFile
    case editLine
    case recompute
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

    /// A moment as the journal writes it, or with fractions of a second.
    static func date(_ text: String) -> Date? {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let plain = formatter.date(from: text) {
            return plain
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
