import CryptoKit
import Foundation

/// The list of changes for the whole app, kept on disk (#899, piece U1).
///
/// **The format** is `contracts/file-formats.json` → `undoJournal`, shared by
/// both apps and every outside-assistant process; **the rule** for writing it
/// is `contracts/shared-rules.json` → `undo.rule`. In short:
///
/// - It lives in `Library/Application Support/Plantoir/undo/` under the home
///   `RealHome.forFiles` answers (so it follows `--state-dir`, and the unit
///   suite gets its throwaway home), never in a working folder: one list
///   spans every working folder, and a working folder may be synced between
///   two computers.
/// - Nothing in it is ever replaced in place. Events are APPENDED, one JSON
///   object per line, to `journal-000001.jsonl` and its successors; content
///   too large to put in a line is a blob under `content/`, created under a
///   temporary name and renamed onto a name that does not exist yet.
/// - The head is never stored. It is FOLDED from the events every time the
///   list is read (`UndoFold`), so there is no second file to disagree with.
/// - Every change to it takes the one exclusive lock (`UndoLock`), reads the
///   journal fresh inside it, and holds it only for journal events, never
///   while a change is being applied.
///
/// Rejected, with the reasons in `documentation/09-mac-app.md` → "Undo and
/// Redo: one list for the app": a `head.json` (a replaced file, which Windows
/// refuses while a reader holds it), one file per step plus a head pointer, a
/// database, and AppKit's `UndoManager` (per window, in memory, unreadable by
/// any other process).
nonisolated final class UndoJournal: @unchecked Sendable {

    // MARK: - Stored properties

    /// The `undo/` folder itself.
    let folderURL: URL

    /// Which process this is, written into every event that starts work.
    let process: UndoProcess

    /// Whether the process an unfinished event names is still running.
    /// Injectable so a test can say "that process is gone" about itself.
    let processIsAlive: @Sendable (UndoProcess) -> Bool

    /// The clock pruning reads. Injectable so a test can be thirty days on.
    let now: @Sendable () -> Date

    /// The version every line written today carries.
    static let formatVersion: Int = 1

    /// The prefix and suffix of a segment's name.
    static let segmentPrefix: String = "journal-"
    static let segmentSuffix: String = ".jsonl"

    // MARK: - Initializer

    init(
        folderURL: URL,
        process: UndoProcess = UndoProcess.current(),
        processIsAlive: @escaping @Sendable (UndoProcess) -> Bool = UndoProcess.isStillRunning,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.folderURL = folderURL
        self.process = process
        self.processIsAlive = processIsAlive
        self.now = now
    }

    // MARK: - Computed properties

    var lockFileURL: URL {
        return folderURL.appendingPathComponent(".lock")
    }

    var contentFolderURL: URL {
        return folderURL.appendingPathComponent("content", isDirectory: true)
    }

    var computerIDFileURL: URL {
        return folderURL.appendingPathComponent("computer-id")
    }

    // MARK: - Functions

    /// The list as it stands, read without the lock. Safe because the file
    /// is only ever appended to: a reader sees a prefix of what is there,
    /// and a last line still being written has no line feed yet and is not
    /// counted.
    func read() throws -> UndoFold {
        var fold: UndoFold = UndoFold()
        for segment in try segmentNumbers() {
            let url: URL = segmentURL(number: segment)
            guard let data = try? Data(contentsOf: url) else {
                // Deleted by a prune between the listing and the read: it
                // held only steps that have left the list.
                continue
            }
            let lines: [Data] = UndoJournal.completeLines(in: data)
            for line in lines {
                guard let event = UndoEventLine.decoded(from: line) else {
                    fold.unreadableLines += 1
                    continue
                }
                fold.take(event, inSegment: segment)
            }
        }
        return fold
    }

    /// Runs `body` holding the list's lock, with the journal read fresh and
    /// any torn last line cut off first.
    @discardableResult
    func withLock<Result>(
        waitingAtMost seconds: Double = UndoSwitch.lockWaitSeconds,
        _ body: (UndoJournalWriter) throws -> Result
    ) throws -> Result {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let lock: UndoLock = try UndoLock.take(at: lockFileURL, waitingAtMost: seconds)
        defer {
            lock.release()
        }
        try cutTornLastLine()
        let writer: UndoJournalWriter = UndoJournalWriter(journal: self, fold: try read())
        defer {
            writer.close()
        }
        let result: Result = try body(writer)
        try writer.syncIfWritten()
        return result
    }

    /// This computer's identifier, made once and never changed. Created
    /// exclusively, so two processes starting at once agree on one.
    func computerID() throws -> String {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return try UndoIdentifierFile.readOrCreate(at: computerIDFileURL)
    }

    /// Segment numbers present, in order.
    func segmentNumbers() throws -> [Int] {
        var numbers: [Int] = []
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
        } catch {
            if !FileManager.default.fileExists(atPath: folderURL.path) {
                return []
            }
            throw error
        }
        for name in names {
            if let number = UndoJournal.segmentNumber(inName: name) {
                numbers.append(number)
            }
        }
        numbers.sort()
        return numbers
    }

    func segmentURL(number: Int) -> URL {
        return folderURL.appendingPathComponent(UndoJournal.segmentName(number: number))
    }

    /// `journal-000001.jsonl` for 1.
    static func segmentName(number: Int) -> String {
        var digits: String = String(number)
        while digits.count < 6 {
            digits = "0" + digits
        }
        return segmentPrefix + digits + segmentSuffix
    }

    /// The number in a segment's name, or nil for any other file.
    static func segmentNumber(inName name: String) -> Int? {
        if !name.hasPrefix(segmentPrefix) || !name.hasSuffix(segmentSuffix) {
            return nil
        }
        let middle: String = String(name.dropFirst(segmentPrefix.count).dropLast(segmentSuffix.count))
        if middle.isEmpty {
            return nil
        }
        for character in middle where !character.isASCII || !character.isNumber {
            return nil
        }
        return Int(middle)
    }

    /// Every line that ends in a line feed, without it. Bytes after the last
    /// line feed are a line still being written, or torn by a crash, and are
    /// not a line.
    static func completeLines(in data: Data) -> [Data] {
        var lines: [Data] = []
        var start: Int = data.startIndex
        var index: Int = data.startIndex
        while index < data.endIndex {
            if data[index] == 0x0A {
                if index > start {
                    lines.append(data.subdata(in: start..<index))
                }
                start = index + 1
            }
            index += 1
        }
        return lines
    }

    /// Cuts a torn last line off the newest segment. Inside the lock only:
    /// outside it, the "torn" line may be one another writer is finishing.
    func cutTornLastLine() throws {
        guard let last = try segmentNumbers().last else {
            return
        }
        let url: URL = segmentURL(number: last)
        guard let data = try? Data(contentsOf: url) else {
            return
        }
        if data.isEmpty || data[data.endIndex - 1] == 0x0A {
            return
        }
        var keep: Int = 0
        var index: Int = data.endIndex - 1
        while index >= data.startIndex {
            if data[index] == 0x0A {
                keep = index + 1
                break
            }
            index -= 1
        }
        let handle: FileHandle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        try handle.truncate(atOffset: UInt64(keep))
        try handle.synchronize()
    }

    /// Where a blob with this hash lives: `content/<first two>/<hash>`.
    func blobURL(sha: String) -> URL {
        let prefix: String = String(sha.prefix(2))
        return contentFolderURL
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(sha)
    }

    /// A blob's bytes, or nil when it is missing or does not hash to its own
    /// name (a blob is never trusted for content it does not prove).
    func readBlob(sha: String) -> Data? {
        guard let data = try? Data(contentsOf: blobURL(sha: sha)) else {
            return nil
        }
        if UndoHash.sha256(of: data) != sha {
            return nil
        }
        return data
    }
}

/// The list's events, written by one holder of the lock.
nonisolated final class UndoJournalWriter {

    // MARK: - Stored properties

    let journal: UndoJournal

    /// The list as it was read when the lock was taken, kept up to date with
    /// every event this writer appends.
    private(set) var fold: UndoFold

    /// The segment being appended to, open for the lock's length.
    private var openSegment: (number: Int, handle: FileHandle)?

    private var wroteSomething: Bool = false

    // MARK: - Initializer

    init(journal: UndoJournal, fold: UndoFold) {
        self.journal = journal
        self.fold = fold
    }

    // MARK: - Functions

    /// Appends one event as one line. Not durable until the lock is released
    /// (`syncIfWritten`) or `sync()` is called.
    func append(_ event: UndoEventLine) throws {
        var line: Data = try event.encoded()
        line.append(0x0A)
        let handle: FileHandle = try segmentFor(adding: line.count)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        wroteSomething = true
        if let number = openSegment?.number {
            fold.take(event, inSegment: number)
        }
    }

    /// Makes every line appended so far durable before anything else
    /// happens: the `begin` of a step has to be on the disk before its
    /// change starts. `F_FULLFSYNC` asks the drive to flush its own cache
    /// too, which plain `fsync` does not on a Mac.
    func sync() throws {
        guard let handle = openSegment?.handle else {
            return
        }
        let descriptor: Int32 = handle.fileDescriptor
        if fcntl(descriptor, F_FULLFSYNC) != 0 {
            if fsync(descriptor) != 0 {
                throw UndoJournalError.couldNotSync(errno)
            }
        }
    }

    /// What every release of the lock does: a plain `fsync` of anything
    /// appended. Only a `begin`, `undoing` or `redoing` is made durable with
    /// `sync()` (`F_FULLFSYNC`), because those are what recovery cannot do
    /// without; a closing event lost to a power cut is put back by recovery
    /// from the content. Measured on the M4 Pro: `F_FULLFSYNC` of a 1 KB
    /// append 4.2 ms, a plain `fsync` 0.03 ms.
    func syncIfWritten() throws {
        if !wroteSomething {
            return
        }
        guard let handle = openSegment?.handle else {
            return
        }
        if fsync(handle.fileDescriptor) != 0 {
            throw UndoJournalError.couldNotSync(errno)
        }
    }

    func close() {
        if let handle = openSegment?.handle {
            try? handle.close()
        }
        openSegment = nil
    }

    /// Stores content as an immutable blob named by its SHA-256, and returns
    /// the name. A blob already there is left as it is: the same name is the
    /// same bytes.
    @discardableResult
    func writeBlob(_ data: Data) throws -> String {
        let sha: String = UndoHash.sha256(of: data)
        let finalURL: URL = journal.blobURL(sha: sha)
        if journal.readBlob(sha: sha) != nil {
            return sha
        }
        let folder: URL = finalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporaryURL: URL = folder.appendingPathComponent(".tmp-" + UUID().uuidString)
        try UndoFiles.writeDurably(data, to: temporaryURL)
        let renamed: Int32 = temporaryURL.withUnsafeFileSystemRepresentation { from in
            return finalURL.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else {
                    return -1
                }
                return renamex_np(from, to, UInt32(RENAME_EXCL))
            }
        }
        if renamed != 0 {
            let failure: Int32 = errno
            try? FileManager.default.removeItem(at: temporaryURL)
            if failure == EEXIST {
                // A blob of the same name is the same bytes, unless a crash
                // left a short one: then it is replaced through a fresh name.
                if journal.readBlob(sha: sha) != nil {
                    return sha
                }
                try? FileManager.default.removeItem(at: finalURL)
                return try writeBlob(data)
            }
            throw UndoJournalError.couldNotStoreContent(failure)
        }
        UndoFiles.syncFolder(folder)
        return sha
    }

    /// The segment a line of this size goes in: the newest, unless it has
    /// passed the size where a new one starts.
    private func segmentFor(adding byteCount: Int) throws -> FileHandle {
        if let openSegment {
            let size: UInt64 = try openSegment.handle.seekToEnd()
            if size < UInt64(UndoSwitch.segmentBytes) {
                return openSegment.handle
            }
            try? openSegment.handle.synchronize()
            try? openSegment.handle.close()
            self.openSegment = nil
            return try openNewSegment(number: openSegment.number + 1)
        }
        let numbers: [Int] = try journal.segmentNumbers()
        guard let last = numbers.last else {
            return try openNewSegment(number: 1)
        }
        let url: URL = journal.segmentURL(number: last)
        let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: url.path)
        let size: Int = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if size >= UndoSwitch.segmentBytes {
            return try openNewSegment(number: last + 1)
        }
        let handle: FileHandle = try FileHandle(forWritingTo: url)
        openSegment = (number: last, handle: handle)
        return handle
    }

    private func openNewSegment(number: Int) throws -> FileHandle {
        let url: URL = journal.segmentURL(number: number)
        if !FileManager.default.fileExists(atPath: url.path) {
            let created: Bool = FileManager.default.createFile(atPath: url.path, contents: Data())
            if !created {
                throw UndoJournalError.couldNotStartASegment(url.lastPathComponent)
            }
            UndoFiles.syncFolder(journal.folderURL)
        }
        let handle: FileHandle = try FileHandle(forWritingTo: url)
        openSegment = (number: number, handle: handle)
        return handle
    }
}

/// Why the list could not be written.
nonisolated enum UndoJournalError: Error, Equatable {
    case lockBusy
    case couldNotOpenTheLock(Int32)
    case couldNotSync(Int32)
    case couldNotStoreContent(Int32)
    case couldNotStartASegment(String)
    case couldNotEncode
    case notTheNewestStep(Int)
}

/// One line of the journal.
nonisolated struct UndoEventLine: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    /// The format's version: 1.
    var v: Int

    /// The step the event is about.
    var seq: Int

    /// `begin`, `applied`, `rolledBack`, `undoing`, `undone`, `redoing`,
    /// `redone`, `failed`, `dropped`, `pruned` or `cleared`.
    var event: String

    /// The whole step, on `begin` only.
    var step: UndoStep?

    /// Which process started the work, on `begin`, `undoing` and `redoing`.
    var process: UndoProcess?

    /// What a `failed` or `rolledBack` ended: `begin`, `undoing` or
    /// `redoing`.
    var phase: String?

    /// Why, in a word or two, for `failed`, `rolledBack`, `dropped`,
    /// `pruned` and `cleared` (`changedSince` for ruling 13's clearing):
    /// never page text.
    var reason: String?

    // MARK: - Initializer

    init(
        seq: Int,
        event: UndoEventKind,
        step: UndoStep? = nil,
        process: UndoProcess? = nil,
        phase: UndoPhase? = nil,
        reason: String? = nil
    ) {
        self.v = UndoJournal.formatVersion
        self.seq = seq
        self.event = event.rawValue
        self.step = step
        self.process = process
        self.phase = phase?.rawValue
        self.reason = reason
    }

    // MARK: - Functions

    /// The line's bytes: keys sorted, slashes not escaped, so two writers of
    /// the same event write the same bytes on either platform.
    func encoded() throws -> Data {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data = try encoder.encode(self)
        for byte in data where byte == 0x0A {
            throw UndoJournalError.couldNotEncode
        }
        return data
    }

    /// One line read back, or nil when it does not parse or is from a
    /// version this app does not know.
    static func decoded(from line: Data) -> UndoEventLine? {
        guard let event = try? JSONDecoder().decode(UndoEventLine.self, from: line) else {
            return nil
        }
        if event.v != UndoJournal.formatVersion {
            return nil
        }
        if UndoEventKind(rawValue: event.event) == nil {
            return nil
        }
        return event
    }
}

/// The events a line can carry.
nonisolated enum UndoEventKind: String, Sendable, CaseIterable {
    case begin
    case applied
    case rolledBack
    case undoing
    case undone
    case redoing
    case redone
    case failed
    case dropped
    case pruned
    /// Undo refused the head because what it changed was changed by hand
    /// since, and the whole list was cleared (Russell's ruling 13 on #899).
    /// Its `seq` is the refused step's; it takes every step that is done or
    /// undone at that point in the journal off the list, so nothing before
    /// it can be undone or redone. Steps begun after it are untouched.
    case cleared
}

/// What a `failed` or `rolledBack` event ended.
nonisolated enum UndoPhase: String, Sendable {
    case begin
    case undoing
    case redoing
}

/// One thing the teacher did once: everything it changed, in order.
nonisolated struct UndoStep: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    var seq: Int

    /// When it was made, in UTC (`2026-11-13T21:04:05Z`). For display and
    /// for the thirty-day limit only: never a check of whether a file has
    /// changed since, which is judged by content (ruling 4, W6).
    var madeAt: String

    /// What the menu will call it: a wording key and its arguments, so either
    /// platform renders the name in its own words.
    var action: UndoAction

    /// `menu`, `sheet`, `wizard`, `builtInAssistant:<conversation id>`,
    /// `outsideAssistant:<client name>:<session id>` or `scheduledRun`.
    var madeBy: String

    var workingFolder: UndoWorkingFolder

    var course: String

    var section: Int?

    /// A, B, C or D (`undo.classes`).
    var actionClass: String

    /// Which lease an undo of it takes: `section` or `course`.
    var holds: String

    var ops: [UndoOp]

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

    /// The folder's own identifier (`courses/.internal/folder-id`).
    var id: String

    /// Where it was, canonical, when the step was made.
    var pathAtTheTime: String
}

/// The process that started a piece of work, so recovery can tell whether
/// it is still running.
nonisolated struct UndoProcess: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    /// For a person reading the file. Never compared: a Mac's host name can
    /// change with the network it is on, and the list is this computer's own.
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

    /// The liveness rule the work leases use: the pid, then the name and the
    /// start time, erring toward alive when the system cannot be asked.
    @Sendable static func isStillRunning(_ process: UndoProcess) -> Bool {
        return ProcessLiveness.ownerIsAlive(
            pid: process.pid,
            recordedName: process.name,
            recordedStart: process.started
        )
    }

    /// The host name from the kernel, which answers at once (unlike
    /// `ProcessInfo.hostName`, which may wait on the network).
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

/// Where a step stands, folded from its events.
nonisolated enum UndoStepPhase: String, Sendable {
    /// Written down; its change is under way (or its process died).
    case begun
    /// Its change is made: it is on the list, and may be the head.
    case done
    /// Being undone.
    case undoing
    /// Undone: above the head, the redo candidate if it is the lowest.
    case undone
    /// Being redone.
    case redoing
    /// Never happened, or nothing of it took effect.
    case failed
    /// Part of it took effect and recovery put it back.
    case rolledBack
    /// Its redo was cut off by a newer step.
    case dropped
    /// Older than the list keeps.
    case pruned
    /// Taken off by a `cleared` event (ruling 13).
    case cleared

    /// Whether some process is still working on it.
    var isInFlight: Bool {
        return self == .begun || self == .undoing || self == .redoing
    }

    /// Whether it is on the list at all.
    var isOnTheList: Bool {
        return self == .done || self == .undone || isInFlight
    }
}

/// One step and where it stands.
nonisolated struct UndoStepRecord: Equatable, Sendable {

    // MARK: - Stored properties

    let step: UndoStep

    var phase: UndoStepPhase

    /// The process of the newest event that started work on it.
    var process: UndoProcess?

    /// Every segment holding one of its events.
    var segments: Set<Int>
}

/// The list, folded from the events: the only way the head is ever known.
nonisolated struct UndoFold: Equatable, Sendable {

    // MARK: - Stored properties

    /// Every step whose `begin` was read, by sequence number.
    var records: [Int: UndoStepRecord] = [:]

    /// The highest sequence number in any line, `begin` or not.
    var highestSeq: Int = 0

    /// Lines that did not parse, or were from another version.
    var unreadableLines: Int = 0

    /// Events naming a step whose `begin` is not there (its segment was
    /// deleted) or that do not follow from where the step stood.
    var ignoredEvents: Int = 0

    /// Every segment that holds any line.
    var segmentsSeen: Set<Int> = []

    // MARK: - Computed properties

    /// Every step on the list, oldest first.
    var stepsOnTheList: [UndoStepRecord] {
        var result: [UndoStepRecord] = []
        for seq in sortedSeqs() {
            if let record = records[seq], record.phase.isOnTheList {
                result.append(record)
            }
        }
        return result
    }

    /// The newest step on the list that is not undone. Undo acts on it when
    /// it is done, and refuses while it is in flight.
    var newestNotUndone: UndoStepRecord? {
        var found: UndoStepRecord? = nil
        for record in stepsOnTheList where record.phase != .undone {
            found = record
        }
        return found
    }

    /// The head: the newest step that is done, or nil.
    var head: UndoStepRecord? {
        var found: UndoStepRecord? = nil
        for record in stepsOnTheList where record.phase == .done {
            found = record
        }
        return found
    }

    /// Undone steps that still count as the redo branch: above every step
    /// that is not undone. An undone step BELOW one is stale, because a step
    /// began after it was undone; the next writer drops it.
    var redoBranch: [UndoStepRecord] {
        let floor: Int = newestNotUndone?.step.seq ?? 0
        var result: [UndoStepRecord] = []
        for record in stepsOnTheList where record.phase == .undone && record.step.seq > floor {
            result.append(record)
        }
        return result
    }

    /// Undone steps a newer step has cut off, not yet marked `dropped`.
    var staleUndone: [UndoStepRecord] {
        let floor: Int = newestNotUndone?.step.seq ?? 0
        var result: [UndoStepRecord] = []
        for record in stepsOnTheList where record.phase == .undone && record.step.seq < floor {
            result.append(record)
        }
        return result
    }

    /// What Redo puts back: the most recently undone step, the lowest of the
    /// branch.
    var redoCandidate: UndoStepRecord? {
        return redoBranch.first
    }

    /// Steps some process is working on.
    var inFlight: [UndoStepRecord] {
        var result: [UndoStepRecord] = []
        for record in stepsOnTheList where record.phase.isInFlight {
            result.append(record)
        }
        return result
    }

    // MARK: - Functions

    func sortedSeqs() -> [Int] {
        var seqs: [Int] = []
        for (seq, _) in records {
            seqs.append(seq)
        }
        seqs.sort()
        return seqs
    }

    /// Takes one event into the fold. An event that does not follow from
    /// where its step stands is counted and ignored, so a journal written by
    /// a later version, or by hand, cannot move a step somewhere impossible.
    mutating func take(_ event: UndoEventLine, inSegment segment: Int) {
        segmentsSeen.insert(segment)
        if event.seq > highestSeq {
            highestSeq = event.seq
        }
        guard let kind = UndoEventKind(rawValue: event.event) else {
            ignoredEvents += 1
            return
        }
        if kind == .cleared {
            // Not about one step: everything on the list that is not in
            // flight leaves it. Applied in journal order, so a step begun
            // after the clearing is not touched by it.
            var takenOff: Int = 0
            for seq in sortedSeqs() {
                guard var record = records[seq] else {
                    continue
                }
                if record.phase == .done || record.phase == .undone {
                    record.phase = .cleared
                    record.segments.insert(segment)
                    records[seq] = record
                    takenOff += 1
                }
            }
            if takenOff == 0 {
                ignoredEvents += 1
            }
            return
        }
        if kind == .begin {
            guard let step = event.step, step.seq == event.seq, records[event.seq] == nil else {
                ignoredEvents += 1
                return
            }
            records[event.seq] = UndoStepRecord(step: step, phase: .begun, process: event.process, segments: [segment])
            return
        }
        guard var record = records[event.seq] else {
            ignoredEvents += 1
            return
        }
        guard let next = UndoFold.phase(after: record.phase, on: kind, phase: event.phase) else {
            ignoredEvents += 1
            return
        }
        record.phase = next
        record.segments.insert(segment)
        if kind == .undoing || kind == .redoing {
            record.process = event.process
        }
        records[event.seq] = record
    }

    /// The table of moves: where a step goes from where it stands on each
    /// event, or nil when the event does not follow.
    static func phase(after current: UndoStepPhase, on kind: UndoEventKind, phase: String?) -> UndoStepPhase? {
        switch kind {
        case .begin:
            return nil
        case .applied:
            return current == .begun ? .done : nil
        case .undoing:
            return current == .done ? .undoing : nil
        case .undone:
            return current == .undoing ? .undone : nil
        case .redoing:
            return current == .undone ? .redoing : nil
        case .redone:
            return current == .redoing ? .done : nil
        case .failed, .rolledBack:
            guard let phase, let ended = UndoPhase(rawValue: phase) else {
                return nil
            }
            switch ended {
            case .begin:
                if current != .begun {
                    return nil
                }
                return kind == .failed ? .failed : .rolledBack
            case .undoing:
                return current == .undoing ? .done : nil
            case .redoing:
                return current == .redoing ? .undone : nil
            }
        case .dropped:
            return current == .undone ? .dropped : nil
        case .pruned:
            if current == .done || current == .undone {
                return .pruned
            }
            return nil
        case .cleared:
            return nil
        }
    }
}

/// The one hash.
nonisolated enum UndoHash {

    // MARK: - Functions

    /// The hash of the bytes, or nil for no file.
    static func sha256(ofOptional data: Data?) -> String? {
        guard let data else {
            return nil
        }
        return sha256(of: data)
    }

    static func sha256(of data: Data) -> String {
        let digest: SHA256.Digest = SHA256.hash(data: data)
        var text: String = ""
        for byte in digest {
            let pair: String = String(byte, radix: 16)
            if pair.count == 1 {
                text += "0"
            }
            text += pair
        }
        return text
    }
}

/// Small file-system helpers the list and the swaps share.
nonisolated enum UndoFiles {

    // MARK: - Functions

    /// Writes bytes and pushes them to the disk before returning.
    static func writeDurably(_ data: Data, to url: URL, mode: mode_t = 0o644) throws {
        let descriptor: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode)
        }
        if descriptor < 0 {
            throw UndoJournalError.couldNotStoreContent(errno)
        }
        defer {
            close(descriptor)
        }
        var written: Int = 0
        let total: Int = data.count
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            while written < total {
                let result: Int = Darwin.write(descriptor, base.advanced(by: written), total - written)
                if result < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw UndoJournalError.couldNotStoreContent(errno)
                }
                written += result
            }
        }
        // The mode is set again because `open` honours the umask.
        fchmod(descriptor, mode)
        if fsync(descriptor) != 0 {
            throw UndoJournalError.couldNotSync(errno)
        }
    }

    /// Pushes a folder's entries (a rename, a new file) to the disk. Best
    /// effort: a folder that cannot be opened is left to the next sync.
    static func syncFolder(_ folderURL: URL) {
        let descriptor: Int32 = folderURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return open(path, O_RDONLY | O_CLOEXEC)
        }
        if descriptor < 0 {
            return
        }
        fsync(descriptor)
        close(descriptor)
    }
}

/// A file that holds one identifier, made once and never replaced: the
/// list's `computer-id` and a working folder's `folder-id`.
nonisolated enum UndoIdentifierFile {

    // MARK: - Functions

    /// The identifier in the file, making it first when there is none.
    ///
    /// Made EXCLUSIVELY: written whole under a temporary name, then linked
    /// onto the real name, which fails when it already exists. So the file
    /// is never seen half-written, and two processes making it at the same
    /// moment end up with the same one: the second reads the first's.
    static func readOrCreate(at url: URL) throws -> String {
        if let existing = read(at: url) {
            return existing
        }
        let folder: URL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let identifier: String = UUID().uuidString
        let temporaryURL: URL = folder.appendingPathComponent(".tmp-" + url.lastPathComponent + "-" + UUID().uuidString)
        try UndoFiles.writeDurably(Data((identifier + "\n").utf8), to: temporaryURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        let linked: Int32 = temporaryURL.withUnsafeFileSystemRepresentation { from in
            return url.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else {
                    return -1
                }
                return link(from, to)
            }
        }
        if linked == 0 {
            UndoFiles.syncFolder(folder)
            return identifier
        }
        if let existing = read(at: url) {
            return existing
        }
        throw UndoJournalError.couldNotStoreContent(errno)
    }

    /// The identifier, or nil when the file is missing or does not hold one.
    static func read(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let text: String = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = UUID(uuidString: text) else {
            return nil
        }
        return parsed.uuidString
    }
}
