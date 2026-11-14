import CryptoKit
import Foundation

/// The list of changes for the whole app, kept on disk (#899, piece U1).
///
/// **The format** is `contracts/file-formats.json` → `undoJournal`, shared by
/// both apps and every outside-assistant process; **the rule** for writing it
/// is `contracts/shared-rules.json` → `undo.rule`. In short:
///
/// - It lives in `Library/Application Support/Plantoir/undo/` under the home
///   `RealHome.forFiles` answers, never in a working folder.
/// - Nothing in it is ever replaced in place. Events are APPENDED, one JSON
///   object per line, to `journal-000001.jsonl` and its successors; content
///   too large for a line is a blob under `content/`.
/// - The head is never stored. It is FOLDED from the events (`UndoFold`).
///   The fold is kept per process and read on from where it stopped, with the
///   bytes before that point checked, so a lock hold reads only what is new
///   (the core review's W4).
/// - Every change takes the one exclusive lock (`UndoLock`), reads the
///   journal fresh inside it, and holds it only for journal events (and, the
///   one exception, recovery's own repair of a dead process's step).
/// - A line this version cannot read is kept, its number is never reused,
///   nothing it might name is deleted, and Undo and Redo are not available
///   while it stands at or above the head (`UndoFold.offer`).
///
/// Rejected, with the reasons in `documentation/09-mac-app.md` → "Undo and
/// Redo: one list for the app": a `head.json`, one file per step plus a head
/// pointer, a database, and AppKit's `UndoManager`.
nonisolated final class UndoJournal: @unchecked Sendable {

    // MARK: - Stored properties

    /// The `undo/` folder itself.
    let folderURL: URL

    /// Which process this is, written into every event that starts work.
    let process: UndoProcess

    /// Whether the process an unfinished event names is still running.
    let processIsAlive: @Sendable (UndoProcess) -> Bool

    /// The clock. Injectable so a test can be thirty days on.
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
    /// is only ever appended to. Reads on from where this process last
    /// stopped (`UndoFoldCache`).
    func read() throws -> UndoFold {
        return try UndoFoldCache.read(self)
    }

    /// The list as Undo and Redo see it now, the limits applied.
    func offer() throws -> UndoOffer {
        return try read().offer(now: now())
    }

    /// Runs `body` holding the list's lock, with the journal read fresh,
    /// any torn last line cut off, and any closing event this process could
    /// not write earlier written first.
    @discardableResult
    func withLock<Result>(
        waitingAtMost seconds: Double = UndoSwitch.lockWaitSeconds,
        inShadow: Bool = false,
        _ body: (UndoJournalWriter) throws -> Result
    ) throws -> Result {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let lock: UndoLock = try UndoLock.take(at: lockFileURL, waitingAtMost: seconds, inShadow: inShadow)
        defer {
            lock.release()
        }
        try cutTornLastLine()
        let writer: UndoJournalWriter = UndoJournalWriter(journal: self, fold: try read())
        defer {
            writer.close()
        }
        for pending in UndoFoldCache.takePendingClosings(for: folderURL) {
            if writer.fold.records[pending.seq]?.phase.isInFlight == true {
                if pending.event == UndoEventKind.applied.rawValue {
                    JournaledWrite.dropTheRedoBranch(below: pending.seq, writer)
                }
                try writer.append(pending)
            }
        }
        let result: Result = try body(writer)
        try writer.syncIfWritten()
        return result
    }

    /// This computer's identifier, made once and never changed.
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

    /// Every line that ends in a line feed, without it, and where each ends.
    static func completeLines(in data: Data) -> [Data] {
        var lines: [Data] = []
        for found in completeLinesWithEnds(in: data) {
            lines.append(found.line)
        }
        return lines
    }

    static func completeLinesWithEnds(in data: Data) -> [(line: Data, end: Int)] {
        var lines: [(line: Data, end: Int)] = []
        var start: Int = data.startIndex
        var index: Int = data.startIndex
        while index < data.endIndex {
            if data[index] == 0x0A {
                if index > start {
                    lines.append((line: data.subdata(in: start..<index), end: index + 1))
                }
                start = index + 1
            }
            index += 1
        }
        return lines
    }

    /// Cuts a torn last line off the newest segment, reading one byte and,
    /// only when it is not a line feed, back to the last line feed. Inside
    /// the lock only.
    func cutTornLastLine() throws {
        guard let last = try segmentNumbers().last else {
            return
        }
        let url: URL = segmentURL(number: last)
        guard let handle = try? FileHandle(forUpdating: url) else {
            return
        }
        defer {
            try? handle.close()
        }
        let size: UInt64 = try handle.seekToEnd()
        if size == 0 {
            return
        }
        try handle.seek(toOffset: size - 1)
        let lastByte: Data = handle.readData(ofLength: 1)
        if lastByte.first == 0x0A {
            return
        }
        var keep: UInt64 = 0
        var chunkEnd: UInt64 = size
        while chunkEnd > 0 {
            let chunkStart: UInt64 = chunkEnd > 65_536 ? chunkEnd - 65_536 : 0
            try handle.seek(toOffset: chunkStart)
            let chunk: Data = handle.readData(ofLength: Int(chunkEnd - chunkStart))
            var index: Int = chunk.count - 1
            var found: Bool = false
            while index >= 0 {
                if chunk[chunk.startIndex + index] == 0x0A {
                    keep = chunkStart + UInt64(index) + 1
                    found = true
                    break
                }
                index -= 1
            }
            if found {
                break
            }
            chunkEnd = chunkStart
        }
        try handle.truncate(atOffset: keep)
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
    /// name.
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

/// The fold each process keeps of each list, read on from where it stopped.
///
/// Per process rather than per `UndoJournal`, because the app makes a new
/// `UndoJournal` for every action. Each segment's remembered end is checked
/// before it is trusted: the file must be the same file, at least that long,
/// with the bytes just before the end the ones read last time, and no
/// segment may have appeared below the newest one read or gone from
/// anywhere but the oldest end (where pruning deletes, and only what is off
/// the list). Anything else, a rewrite by another process included, and the
/// whole journal is read again.
nonisolated enum UndoFoldCache {

    // MARK: - Stored properties

    /// One folder's fold and how far it has been read.
    struct Entry {

        // MARK: - Stored properties

        var fold: UndoFold

        /// Each segment's byte offset read up to: always just after a line feed.
        var ends: [Int: Int]

        /// The bytes just before each end, compared before reading on.
        var tails: [Int: Data]

        /// How many complete lines of each segment have been read.
        var lineCounts: [Int: Int]

        /// Each segment's file number, so a file put in its place (by any
        /// means) is read whole again.
        var fileNumbers: [Int: UInt64] = [:]
    }

    nonisolated(unsafe) private static var entries: [String: Entry] = [:]

    nonisolated(unsafe) private static var pendingClosings: [String: [UndoEventLine]] = [:]

    private static let guardLock: NSLock = NSLock()

    /// How many bytes before a remembered end are compared.
    static let tailBytes: Int = 64

    /// How many full reads and how many read-ons this process has made,
    /// for the harness's measurements.
    nonisolated(unsafe) static var fullReads: Int = 0
    nonisolated(unsafe) static var readOns: Int = 0

    // MARK: - Functions

    static func read(_ journal: UndoJournal) throws -> UndoFold {
        let key: String = journal.folderURL.standardizedFileURL.path
        guardLock.lock()
        let cached: Entry? = entries[key]
        guardLock.unlock()

        let numbers: [Int] = try journal.segmentNumbers()
        var entry: Entry
        if let cached, stillValid(cached, numbers: numbers, journal: journal) {
            entry = cached
            for (number, _) in cached.ends where !numbers.contains(number) {
                entry.ends[number] = nil
                entry.tails[number] = nil
                entry.lineCounts[number] = nil
                entry.fileNumbers[number] = nil
            }
            readOns += 1
        } else {
            entry = Entry(fold: UndoFold(), ends: [:], tails: [:], lineCounts: [:])
            fullReads += 1
        }
        for number in numbers {
            let from: Int = entry.ends[number] ?? 0
            let url: URL = journal.segmentURL(number: number)
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                continue
            }
            let size: UInt64 = (try? handle.seekToEnd()) ?? 0
            if Int(size) <= from {
                try? handle.close()
                entry.fold.segmentsSeen.insert(number)
                continue
            }
            try? handle.seek(toOffset: UInt64(from))
            let data: Data = handle.readData(ofLength: Int(size) - from)
            try? handle.close()
            var lineIndex: Int = entry.lineCounts[number] ?? 0
            var newEnd: Int = from
            for found in UndoJournal.completeLinesWithEnds(in: data) {
                entry.fold.take(UndoReadLine.read(found.line), at: UndoPosition(segment: number, line: lineIndex))
                lineIndex += 1
                newEnd = from + found.end
            }
            // A blank line still moves the end on.
            var index: Int = data.count - 1
            while index >= 0 {
                if data[data.startIndex + index] == 0x0A {
                    newEnd = max(newEnd, from + index + 1)
                    break
                }
                index -= 1
            }
            entry.ends[number] = newEnd
            entry.lineCounts[number] = lineIndex
            entry.tails[number] = tail(of: url, endingAt: newEnd)
            entry.fileNumbers[number] = fileNumber(of: url)
            entry.fold.segmentsSeen.insert(number)
        }
        guardLock.lock()
        entries[key] = entry
        guardLock.unlock()
        return entry.fold
    }

    /// Whether a remembered fold can be read on from.
    static func stillValid(_ entry: Entry, numbers: [Int], journal: UndoJournal) -> Bool {
        var newestRead: Int = 0
        for (number, _) in entry.ends {
            newestRead = max(newestRead, number)
        }
        var lowestPresent: Int = Int.max
        for number in numbers {
            lowestPresent = min(lowestPresent, number)
        }
        for (number, end) in entry.ends {
            if !numbers.contains(number) {
                // Deleted from the oldest end, as pruning deletes: what it
                // held is off the list, so the fold stays good.
                if number < lowestPresent {
                    continue
                }
                return false
            }
            let url: URL = journal.segmentURL(number: number)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.intValue else {
                return false
            }
            if size < end {
                return false
            }
            if let remembered = entry.fileNumbers[number], remembered != fileNumber(of: url) {
                return false
            }
            if tail(of: url, endingAt: end) != (entry.tails[number] ?? Data()) {
                return false
            }
        }
        for number in numbers where number < newestRead && entry.ends[number] == nil {
            return false
        }
        return true
    }

    /// The file's number on its volume, or 0 when it cannot be read.
    static func fileNumber(of url: URL) -> UInt64 {
        var information: stat = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return stat(path, &information)
        }
        if result != 0 {
            return 0
        }
        return UInt64(information.st_ino)
    }

    /// The last bytes before a position in a file.
    static func tail(of url: URL, endingAt end: Int) -> Data {
        if end <= 0 {
            return Data()
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Data()
        }
        defer {
            try? handle.close()
        }
        let start: Int = max(0, end - tailBytes)
        try? handle.seek(toOffset: UInt64(start))
        return handle.readData(ofLength: end - start)
    }

    /// How many complete lines of a segment this process has read: where
    /// the next line appended to it will stand.
    static func lineCount(of journal: UndoJournal, segment: Int) -> Int {
        guardLock.lock()
        let count: Int = entries[journal.folderURL.standardizedFileURL.path]?.lineCounts[segment] ?? 0
        guardLock.unlock()
        return count
    }

    /// Forgets a folder's fold, so the next read is a full one.
    static func forget(_ folderURL: URL) {
        guardLock.lock()
        entries[folderURL.standardizedFileURL.path] = nil
        guardLock.unlock()
    }

    /// A closing event this process could not write (the lock was busy):
    /// written at its next lock instead, so a step it made is not left in
    /// flight for the life of the process (the core review's I3).
    static func keepPendingClosing(_ event: UndoEventLine, for folderURL: URL) {
        guardLock.lock()
        pendingClosings[folderURL.standardizedFileURL.path, default: []].append(event)
        guardLock.unlock()
    }

    static func takePendingClosings(for folderURL: URL) -> [UndoEventLine] {
        guardLock.lock()
        let key: String = folderURL.standardizedFileURL.path
        let found: [UndoEventLine] = pendingClosings[key] ?? []
        pendingClosings[key] = nil
        guardLock.unlock()
        return found
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
    private var openSegment: (number: Int, handle: FileHandle, lines: Int)?

    private var wroteSomething: Bool = false

    // MARK: - Initializer

    init(journal: UndoJournal, fold: UndoFold) {
        self.journal = journal
        self.fold = fold
    }

    // MARK: - Functions

    /// Appends one event as one line, stamped with the clock.
    func append(_ event: UndoEventLine) throws {
        var stamped: UndoEventLine = event
        if stamped.at == nil {
            stamped.at = UndoMoment.text(journal.now())
        }
        var line: Data = try stamped.encoded()
        let encodedLine: Data = line
        line.append(0x0A)
        let handle: FileHandle = try segmentFor(adding: line.count)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        wroteSomething = true
        if let segment = openSegment {
            fold.take(UndoReadLine.read(encodedLine), at: UndoPosition(segment: segment.number, line: segment.lines))
            openSegment = (number: segment.number, handle: segment.handle, lines: segment.lines + 1)
        }
    }

    /// Makes every line appended so far durable before anything else
    /// happens: `F_FULLFSYNC`, which also flushes the drive's own cache.
    /// Used for `begin`, `undoing` and `redoing`, which recovery cannot do
    /// without; every other release of the lock is a plain `fsync`
    /// (measured: 4.0 ms against 0.03 ms on an M4 Pro).
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

    /// Stores content as an immutable blob named by its SHA-256.
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

    /// The segment a line goes in: the newest, unless it has passed the size
    /// where a new one starts.
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
        openSegment = (number: last, handle: handle, lines: UndoFoldCache.lineCount(of: journal, segment: last))
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
        openSegment = (number: number, handle: handle, lines: UndoFoldCache.lineCount(of: journal, segment: number))
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
    case identifierBeingMade
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

    /// Writes bytes to a NEW file (exclusive create) and pushes them to the
    /// disk before returning.
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
        fchmod(descriptor, mode)
        if fsync(descriptor) != 0 {
            throw UndoJournalError.couldNotSync(errno)
        }
    }

    /// Pushes a folder's entries to the disk. Best effort.
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

/// A file that holds one identifier, made once: the list's `computer-id` and
/// a working folder's `folder-id` (`undoJournal.identifierFiles`).
///
/// Written as the UUID in lower case and a line feed. Read leniently: a
/// byte-order mark, white space and carriage returns are ignored and either
/// case is accepted; the identifier is compared in lower case.
///
/// Made exclusively, so two processes making it at once agree on one: a
/// hard link onto the name where the volume has links (the file appears
/// whole), and where it has none (exFAT, FAT, many SMB shares: the core
/// review's I2) an exclusive create of the name, written in one write. A file
/// that holds no identifier never blocks for good: one that is not empty, or
/// that has been empty for more than two seconds (a creator that died
/// between creating it and writing it), is set aside under a new name and a
/// new identifier made. One empty and younger than that is a creator at
/// work: not yet, and the next attempt reads its identifier.
nonisolated enum UndoIdentifierFile {

    // MARK: - Stored properties

    /// How long an empty file may be a creator at work.
    static let emptyFileGraceSeconds: Double = 2.0

    // MARK: - Functions

    static func readOrCreate(at url: URL) throws -> String {
        if let existing = read(at: url) {
            return existing
        }
        let folder: URL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            let size: Int = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let changed: Date = (attributes[.modificationDate] as? Date) ?? Date.distantPast
            if size == 0 && Date().timeIntervalSince(changed) < emptyFileGraceSeconds {
                throw UndoJournalError.identifierBeingMade
            }
            setAside(url)
        }
        let identifier: String = UUID().uuidString.lowercased()
        let contents: Data = Data((identifier + "\n").utf8)
        let temporaryURL: URL = folder.appendingPathComponent(".tmp-" + url.lastPathComponent + "-" + UUID().uuidString)
        try UndoFiles.writeDurably(contents, to: temporaryURL)
        let linked: Int32 = temporaryURL.withUnsafeFileSystemRepresentation { from in
            return url.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else {
                    return -1
                }
                return link(from, to)
            }
        }
        let linkFailure: Int32 = errno
        try? FileManager.default.removeItem(at: temporaryURL)
        if linked == 0 {
            UndoFiles.syncFolder(folder)
            return identifier
        }
        if linkFailure == EEXIST {
            if let existing = read(at: url) {
                return existing
            }
            throw UndoJournalError.identifierBeingMade
        }
        // No hard links here: an exclusive create of the name itself.
        do {
            try UndoFiles.writeDurably(contents, to: url)
        } catch UndoJournalError.couldNotStoreContent(let failure) where failure == EEXIST {
            if let existing = read(at: url) {
                return existing
            }
            throw UndoJournalError.identifierBeingMade
        }
        UndoFiles.syncFolder(folder)
        return identifier
    }

    /// The identifier, lower case, or nil when the file is missing or does
    /// not hold one.
    static func read(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        var text: String = String(decoding: data, as: UTF8.self)
        if text.unicodeScalars.first == "\u{FEFF}" {
            text = String(String.UnicodeScalarView(text.unicodeScalars.dropFirst()))
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = UUID(uuidString: text) else {
            return nil
        }
        return parsed.uuidString.lowercased()
    }

    /// Moves a file that holds no identifier out of the way, keeping it.
    static func setAside(_ url: URL) {
        let asideURL: URL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".unreadable-" + UUID().uuidString.lowercased())
        try? FileManager.default.moveItem(at: url, to: asideURL)
    }
}
