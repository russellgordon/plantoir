import CryptoKit
import Darwin
import Foundation

/// One file's length, modification time and SHA-256 (GitHub #663, the mac's
/// half of Windows #559).
///
/// The time is in .NET ticks (100-nanosecond steps since 1 January 0001,
/// UTC), the unit Windows' `Toolchain\.hashes` uses, so the two platforms'
/// files read the same way even though neither ever reads the other's.
nonisolated struct ToolchainFingerprint: Equatable, Sendable {

    // MARK: - Stored properties

    let length: Int64
    let ticks: Int64

    /// Lower-case hex.
    let sha256: String

    // MARK: - Functions

    /// Whether this fingerprint is still the file's: the same length, and a
    /// time within the millisecond `WorkspaceModel.filesLookIdentical` allows.
    ///
    /// The same tolerance on BOTH sides — the manifest and the index — and
    /// that is a measured decision, not a copy of Windows' rule. Windows
    /// trusts a bundled file up to 2 s OLDER than its manifest, because its
    /// installer rounds every time down to 2 s; on the mac a DMG copy and a
    /// Sparkle install keep every time to the nanosecond
    /// (documentation/09-mac-app.md → "Comparing without reading (#663)"),
    /// so a looser rule here would only widen the window in which a file
    /// that moved on is trusted.
    func stillDescribes(_ stamp: ToolchainFingerprints.Stamp?) -> Bool {
        guard let stamp else {
            return false
        }
        if stamp.length != length {
            return false
        }
        let apart: Int64 = stamp.ticks > ticks ? stamp.ticks - ticks : ticks - stamp.ticks
        return apart < ToolchainFingerprints.ticksPerMillisecond
    }
}

/// The two files that let the mirror compare without reading (#663).
///
/// - The **manifest**, `toolchain.hashes` at the root of the app's
///   Resources, written by the build (`BuildScripts/write_toolchain_hashes.py`,
///   a build phase in project.yml) FROM THE BUNDLE after Xcode has copied the
///   resources — so it describes the files the app actually carries, with
///   their own times. It is at the Resources root and in none of the four
///   mirrored folders, so it is never mirrored itself.
/// - The **index**, one per working folder: the manifest last applied to that
///   folder's `.toolchain`, with each copy's OWN length and time read back
///   from the disk. It lives under the home `RealHome` resolves, so the
///   teacher never sees it, it does not travel with a copied folder, and a
///   `--state-dir` run and the unit suite keep their own.
nonisolated enum ToolchainFingerprints {

    /// A file's length and modification time, as `stat` gives them.
    nonisolated struct Stamp: Equatable, Sendable {

        // MARK: - Stored properties

        let length: Int64
        let ticks: Int64
    }

    // MARK: - Stored properties

    /// The manifest's name at the root of the app's Resources.
    static let manifestName: String = "toolchain.hashes"

    /// 1 January 0001 to 1 January 1970, in ticks.
    static let ticksAtUnixEpoch: Int64 = 621_355_968_000_000_000

    static let ticksPerSecond: Int64 = 10_000_000
    static let ticksPerMillisecond: Int64 = 10_000

    // MARK: - Functions

    /// Where the working folders' indexes live:
    /// `~/Library/Application Support/Plantoir/toolchain-index`.
    static func indexFolder(inHomeFolder homeFolder: URL = RealHome.forFiles) -> URL {
        return homeFolder
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("toolchain-index", isDirectory: true)
    }

    /// How long an index may go unused before the launch-time sweep removes
    /// it (#683). Longer than the longest ordinary gap in a school year, the
    /// summer (about seventy days), because a folder whose index went is
    /// read in full once — about a second or two — and an index kept costs
    /// at most about 2 MB.
    static let unusedIndexLifetime: TimeInterval = 90 * 24 * 60 * 60

    /// How old a temporary index (`<id>.hashes.<pid>.tmp`, left only when a
    /// write was interrupted) must be before the sweep removes it.
    static let leftoverTemporaryIndexLifetime: TimeInterval = 24 * 60 * 60

    /// One working folder's index, named by the same eight characters its
    /// builds folder and its container are (`BuildOutputLocation.folderIdentifier`).
    static func indexURL(forWorkingFolder workingFolderURL: URL, in indexFolder: URL) -> URL {
        let identifier: String = BuildOutputLocation.folderIdentifier(forWorkingFolder: workingFolderURL.path)
        return indexFolder.appendingPathComponent(identifier + ".hashes")
    }

    /// The file's length and time, or nil when it is not there.
    static func stamp(of url: URL) -> Stamp? {
        var status: stat = stat()
        if stat(url.path, &status) != 0 {
            return nil
        }
        let seconds: Int64 = Int64(status.st_mtimespec.tv_sec)
        let nanoseconds: Int64 = Int64(status.st_mtimespec.tv_nsec)
        let ticks: Int64 = ticksAtUnixEpoch + seconds * ticksPerSecond + nanoseconds / 100
        return Stamp(length: Int64(status.st_size), ticks: ticks)
    }

    /// The file's SHA-256 in lower-case hex, read in pieces; nil when it
    /// cannot be read.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }
        var hasher: SHA256 = SHA256()
        while true {
            // `read(upToCount:)` THROWS for a read that failed and answers
            // nil (or empty data) at the end of the file — two different
            // things, kept apart here.
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 1 << 20)
            } catch {
                return nil
            }
            guard let chunk, !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }
        var hex: String = ""
        for byte in hasher.finalize() {
            hex += String(format: "%02x", byte)
        }
        return hex
    }

    /// Whether two files can be taken for the same file without reading them:
    /// the same length, and times within a millisecond. A tolerance rather
    /// than equality because a date used to make its round trip through the
    /// file system as a floating-point number of seconds, and an exact
    /// comparison could fail on the last bit for two stamps that are the same
    /// moment; a millisecond is far tighter than any real edit. Nil on either
    /// side — a file that is not there — is never identical.
    static func lookIdentical(_ one: Stamp?, _ other: Stamp?) -> Bool {
        guard let one, let other else {
            return false
        }
        if one.length != other.length {
            return false
        }
        let apart: Int64 = one.ticks > other.ticks ? one.ticks - other.ticks : other.ticks - one.ticks
        return apart < ticksPerMillisecond
    }

    /// The SHA-256 of bytes already in hand, in lower-case hex.
    static func sha256(of data: Data) -> String {
        var hex: String = ""
        for byte in SHA256.hash(data: data) {
            hex += String(format: "%02x", byte)
        }
        return hex
    }

    /// Reads a manifest or an index; nil when there is none or it cannot be
    /// read. A line that does not parse is skipped, so that one file is simply
    /// read, as it was before #663.
    static func read(_ url: URL) -> [String: ToolchainFingerprint]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        var entries: [String: ToolchainFingerprint] = [:]
        for line in text.split(separator: "\n") {
            let parts: [Substring] = line.split(separator: "\t", omittingEmptySubsequences: false)
            if parts.count != 4 {
                continue
            }
            guard let length = Int64(parts[1]), let ticks = Int64(parts[2]) else {
                continue
            }
            if length < 0 || ticks < 0 || parts[3].count != 64 {
                continue
            }
            entries[String(parts[0])] = ToolchainFingerprint(
                length: length, ticks: ticks, sha256: parts[3].lowercased()
            )
        }
        return entries
    }

    /// Marks an index USED, now (#683): its modification time is set to the
    /// moment, so that time means "last used" rather than "last changed".
    /// Called at the START of a pass, as soon as the index has been read, so
    /// the launch-time sweep cannot mistake a folder being opened for one
    /// left alone. Nothing else reads the index's own time, and the access
    /// time is no substitute: APFS moves it only when it is older than the
    /// modification time (measured on 2026-11-01: an index read on Oct 31
    /// still had an access time of Oct 24, its last write).
    static func markUsed(_ url: URL) {
        _ = utimes(url.path, nil)
    }

    /// Removes the indexes in `indexFolder` that have gone unused for longer
    /// than `lifetime`, and temporary indexes older than a day, and nothing
    /// else (#683). Answers the names it removed.
    ///
    /// An index names no working folder — only eight characters of a hash
    /// of its path — so whether its folder still exists cannot be asked of
    /// it; age is the rule. A wrongly removed index costs one pass that
    /// reads the copies in full and writes it again. Never given a default
    /// folder: the caller names the folder, so a test cannot reach the real
    /// one by leaving an argument out.
    @discardableResult
    static func pruneIndexes(
        in indexFolder: URL,
        now: Date,
        unusedFor lifetime: TimeInterval = unusedIndexLifetime
    ) -> [String] {
        let fileManager: FileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: indexFolder.path) else {
            return []
        }
        var removed: [String] = []
        for name in names.sorted() {
            let isIndex: Bool = name.hasSuffix(".hashes")
            let isLeftover: Bool = name.hasSuffix(".tmp") && name.contains(".hashes.")
            if !isIndex && !isLeftover {
                continue
            }
            let url: URL = indexFolder.appendingPathComponent(name)
            // Never follows a link: only a plain file is one of ours.
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let type = attributes[.type] as? FileAttributeType,
                  type == .typeRegular,
                  let modified = attributes[.modificationDate] as? Date else {
                continue
            }
            let limit: TimeInterval = isIndex ? lifetime : leftoverTemporaryIndexLifetime
            if now.timeIntervalSince(modified) <= limit {
                continue
            }
            if (try? fileManager.removeItem(at: url)) != nil {
                removed.append(name)
            }
        }
        return removed
    }

    /// Removes the index named by a builds folder's own NAME (#683) — the
    /// same eight characters — when the builds sweep has found that folder's
    /// working folder gone. By name, never by hashing the recorded path
    /// again: `folderIdentifier` resolves the path through the folder
    /// itself, which no longer exists, so it is not guaranteed to give the
    /// same eight characters back.
    static func removeIndex(named identifier: String, in indexFolder: URL) {
        if identifier.isEmpty || identifier.contains("/") {
            return
        }
        let url: URL = indexFolder.appendingPathComponent(identifier + ".hashes")
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes an index whole or not at all: a temporary file beside it, then
    /// a rename over it.
    static func write(_ entries: [String: ToolchainFingerprint], to url: URL) throws {
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var keys: [String] = []
        for key in entries.keys {
            keys.append(key)
        }
        keys.sort()
        var text: String = ""
        for key in keys {
            if let entry = entries[key] {
                text += "\(key)\t\(entry.length)\t\(entry.ticks)\t\(entry.sha256)\n"
            }
        }
        let temporaryURL: URL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".\(ProcessInfo.processInfo.processIdentifier).tmp")
        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }
        try Data(text.utf8).write(to: temporaryURL)
        if rename(temporaryURL.path, url.path) != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

/// What one pass of the working-folder mirror knows without reading (#663):
/// the bundle's manifest, the folder's index from the last pass, and the
/// index this pass is building.
///
/// A same-length file whose time differs is compared WITHOUT reading only
/// when both fingerprints still describe their files; when only the
/// manifest does, the copy alone is hashed; otherwise both are read, exactly
/// as before. A fingerprint that no longer describes its file is not used at
/// all, so a stale manifest or a copy edited in place costs reads, never a
/// missed copy. Used on one thread, inside one `copyToolchainFiles` call.
nonisolated final class ToolchainMirrorPass {

    // MARK: - Stored properties

    private let bundled: [String: ToolchainFingerprint]?
    private let applied: [String: ToolchainFingerprint]?

    /// The index this pass leaves: every copy whose content is known, with
    /// its own length and time.
    private(set) var next: [String: ToolchainFingerprint] = [:]

    // MARK: - Initializer

    init(bundled: [String: ToolchainFingerprint]?, applied: [String: ToolchainFingerprint]?) {
        self.bundled = bundled
        self.applied = applied
    }

    // MARK: - Functions

    /// The bundled file's hash, if the manifest still describes it.
    func bundledHash(_ relative: String, stamp: ToolchainFingerprints.Stamp?) -> String? {
        guard let entry = bundled?[relative] else {
            return nil
        }
        if entry.stillDescribes(stamp) {
            return entry.sha256
        }
        return nil
    }

    /// The copy's hash, if the last pass's index still describes it.
    func appliedHash(_ relative: String, stamp: ToolchainFingerprints.Stamp?) -> String? {
        guard let entry = applied?[relative] else {
            return nil
        }
        if entry.stillDescribes(stamp) {
            return entry.sha256
        }
        return nil
    }

    /// Records the copy as holding `sha256`, with the length and time READ
    /// BACK from the disk: `copyModificationDate` swallows a failure, so a
    /// copy whose stamp did not take is recorded with the time it has.
    func remember(_ relative: String, copy copyURL: URL, sha256: String) {
        guard let stamp = ToolchainFingerprints.stamp(of: copyURL) else {
            return
        }
        remember(relative, stamp: stamp, sha256: sha256)
    }

    /// The same, for a copy whose stamp was just read and has not been
    /// touched since — the cheap match, which writes nothing.
    func remember(_ relative: String, stamp: ToolchainFingerprints.Stamp, sha256: String) {
        next[relative] = ToolchainFingerprint(length: stamp.length, ticks: stamp.ticks, sha256: sha256)
    }

    /// Carries the last pass's entry for a copy into this pass's index, when
    /// it still describes the copy: the copy has not changed since its hash
    /// was taken, whatever the manifest can or cannot say about the bundle.
    func keepWhatIsStillKnown(_ relative: String, stamp: ToolchainFingerprints.Stamp) {
        guard let entry = applied?[relative] else {
            return
        }
        if entry.stillDescribes(stamp) {
            next[relative] = entry
        }
    }

    /// Whether `next` says anything the index on disk does not.
    func indexChanged() -> Bool {
        guard let applied else {
            return !next.isEmpty
        }
        return applied != next
    }
}
