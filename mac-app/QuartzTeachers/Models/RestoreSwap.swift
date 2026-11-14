import Foundation

/// The staged swap a whole-course restore makes (#909), and the settling of
/// one that did not finish.
///
/// Written against Foundation alone, with every app-specific step handed in
/// as a closure (`Context`), so the very same file is compiled into the
/// standalone kill-point harness that SIGKILLs it before each step
/// (`documentation/09-mac-app.md` → "Restoring a whole course: staged, and
/// settled at the next reading (#909)"). An XCTest cannot kill its own host.
///
/// The shape, in one paragraph: the backup is unpacked into
/// `courses/.internal/restoring/<id>/backup/`, beside the courses and on
/// their volume, and checked; a record of every move is written and flushed
/// before the first one; the course's own top-level items move aside into
/// `as-it-was/` (renamed, never deleted), with `course_config.json` FIRST,
/// and the backup's move in with `course_config.json` LAST, so every state
/// in between reads as "not a course" to the sidebar, `build_site.py` and
/// the scheduled deploy (the #909 plan review, H1: 8 of 23 kill points read
/// as a course that was a mix in directory order, 0 of 23 this way). A
/// failure moves everything back, last first. A crash leaves the record,
/// and the next reading of the folder settles it (`settle`).
///
/// The course folder itself is never moved: it is Obsidian's vault.
nonisolated enum RestoreSwap {

    // MARK: - Types

    /// Where a restore is. Written into the record before the step it names.
    enum Phase: String, Codable, Equatable, Sendable {
        /// The staging folder exists and the backup is being unpacked into
        /// it. Nothing in the course has moved.
        case unpacking
        /// The moves are listed and some may have been made.
        case swapping
        /// Every move was made: the restore has happened. What is left is
        /// tidying (`afterCommit`, removing the old copy).
        case done
        /// A move failed and a move back failed too. What was set aside is
        /// being kept where a teacher can open it.
        case stopped
    }

    /// Where the zip a restore puts back came from, so what is said after
    /// one that did not finish names the right place (the implementation
    /// review's M-a: "The backup is still in Backups" was untrue after a
    /// Restore from Archive that crashed, whose zip is still in Archived).
    enum Source: String, Codable, Equatable, Sendable {
        case backups
        case archived
    }

    /// One planned move, as paths relative to `courses/`, with `/` between
    /// parts (Windows normalises them).
    struct Move: Codable, Equatable, Sendable {

        // MARK: - Stored properties

        let from: String
        let to: String

        /// True for a move of the course's own item aside; false for a move
        /// of the backup's item in. The way back treats them differently:
        /// only an `out` move carries an original.
        let out: Bool
    }

    /// The record `restore.json` holds (`contracts/file-formats.json` →
    /// `restoreRecord`).
    struct Record: Codable, Equatable, Sendable {

        // MARK: - Stored properties

        var version: Int = 1
        var kind: String = "course"
        var course: String
        var backup: String
        /// Where `backup` came from. Nil reads as `backups`.
        var from: Source? = nil
        var archive: String?
        var phase: Phase
        var moves: [Move]
        var computer: String
        var owner: String
        var writtenAt: String
        /// Room for Undo (#899, U5): the journal step this restore belongs
        /// to, filled by U5. Nil until then.
        var journalStep: String?
        /// True when the set-aside copy is KEPT in the backups folder after
        /// the commit rather than removed: no archive was made of a course
        /// folder that is there. Decided by the engine under its hold, in
        /// the step that writes the moves (`swapping`), so a settle that
        /// finds `done` after a crash keeps it too (the fix review's I-a:
        /// the settle removed it, 45 of 45 files). Nil reads as false.
        var keepsWhatWasReplaced: Bool? = nil
        /// Folders inside the course the archive left out on purpose
        /// (Plantoir's own Obsidian add-ons, `ObsidianFigureAddOns
        /// .backupExclusions`), as paths inside it: removed with the copy,
        /// as before, because the next pass puts them back. Everything
        /// else the archive's listing does not hold is kept.
        var leftOutOnPurpose: [String]? = nil
        /// The moment the archive made first began, when one was. A file of
        /// the set-aside copy written at or after it may not be in that
        /// archive, so it is kept rather than removed with the copy.
        var archiveBegan: String? = nil
        /// A file in the backup's items with a time later than this was
        /// written while they were in the course, and is kept by a way back
        /// (`keepWhatWasWrittenIntoTheBackupsItems`): the moment the record
        /// went to `swapping`, or the backup zip's own time plus
        /// `zipTimeRoundingSeconds` when that is later. Kept when the record
        /// goes on to `stopped`, whose `writtenAt` is later.
        var writtenAfter: String? = nil
    }

    /// How the engine moves, flushes and reaches each step. `real`
    /// everywhere but the tests and the harness.
    struct Hooks {

        // MARK: - Stored properties

        /// Called before every record write, every move and each of the two
        /// removals at the end, with a short name of the step. The harness
        /// counts these and kills the process before the k-th.
        let step: (String) throws -> Void

        /// A forward move.
        let move: (URL, URL) throws -> Void

        /// A move made by the way back (and a newcomer moved aside).
        let moveBack: (URL, URL) throws -> Void

        /// Whether a record is flushed to the disk (`F_FULLFSYNC`) before it
        /// is renamed into place, and the folder after.
        let flushes: Bool

        // MARK: - Computed properties

        static var real: Hooks {
            return Hooks(
                step: { (_: String) throws in
                },
                move: { (source: URL, destination: URL) throws in
                    try FileManager.default.moveItem(at: source, to: destination)
                },
                moveBack: { (source: URL, destination: URL) throws in
                    try FileManager.default.moveItem(at: source, to: destination)
                },
                flushes: true
            )
        }
    }

    /// Everything a restore needs from the app, as closures and values, so
    /// this file knows nothing of it.
    struct Context {

        // MARK: - Stored properties

        /// This computer (`SharedMediaStore.thisComputer`).
        let computer: String

        /// This process's lease body (`ProcessLiveness.leaseBody()`).
        let owner: String

        /// The moment as the record writes it.
        let now: () -> String

        /// A stamp for a kept folder's name (`ArchiveStamp.text`).
        let stamp: () -> String

        /// Top-level names a restore leaves where they are
        /// (`WholeCourseRestore.keptInPlace`).
        let keptInPlace: [String]

        /// The archive made first, flushed before the first move, because
        /// after the commit it is the only copy of the course as it was.
        let archiveURL: URL?

        /// Checks the unpacked course folder (its settings read). Throws to
        /// refuse, with nothing moved.
        let checkPayload: (URL) throws -> Void

        /// Puts a small backup's Media back into the unpacked folder (785b's
        /// slot), handed the unpacked root and the live course when there is
        /// one. Today: nothing to put back.
        let putMediaBack: (URL, URL?) throws -> Void

        /// The guard every restore door calls before anything moves
        /// (`SharedMediaStore.refuseUnlessItsMediaWasPutBack`), handed the
        /// unpacked root.
        let refuseUnlessMediaWasPutBack: (URL) throws -> Void

        /// Asked immediately before the record goes to `swapping`: the
        /// refusals asked a third time (the #909 plan review, M3). Handed
        /// this restore's OWN staging folder, so a refusal that asks whether
        /// another restore of the course is under way counts every record
        /// but this one: it is written before this is asked (the
        /// implementation review's W1, which refused every restore from
        /// Backups with `anotherRestoreUnderWay`). Throws to refuse, with
        /// nothing moved.
        let beforeTheSwap: (URL) throws -> Void

        /// Run just before the first move: unlock a course kept for
        /// reference, throw away the built site (the review's M9: a crash
        /// after the commit must not leave the old site for a scheduled
        /// deploy to publish over the restored pages).
        let justBeforeTheSwap: () -> Void

        /// Run after the commit, and again by a settle that finds `done`:
        /// clear the rename records, lock again if kept for reference. Must
        /// be safe to run twice.
        let afterCommit: () -> Void

        /// Undo's seam (#899, U5): handed the set-aside copy before it is
        /// deleted. Nil on every door today.
        let keepingWhatWasReplaced: ((URL) -> Void)?

        /// When the archive made first began, or nil when none was made
        /// (`Record.archiveBegan`).
        var archiveBegan: Date? = nil

        /// `Record.leftOutOnPurpose`: the folders inside the course the
        /// archive made first left out on purpose, as paths inside it.
        var leftOutOnPurpose: [String] = []
    }

    /// What a restore that did not happen comes to.
    enum Failure: Error, Equatable {
        /// The backup could not be unpacked or does not hold the course.
        case unreadable(String)
        /// The disk ran out of room while the backup was being unpacked
        /// beside the course. Nothing moved.
        case noSpace
        /// A move failed and every file went back where it was. `reason` is
        /// the file system's words with no staging path in them;
        /// `lockedItem` names the course's top-level item when the move was
        /// refused for a lock or a permission.
        /// `courseFolderIsLocked` says the course folder ITSELF refused
        /// (read-only, or Locked in the Finder), so it is the folder that is
        /// named and not the item that happened to move first (the
        /// implementation review's M-b: `course_config.json` was named).
        /// `newcomersKeptAt` is where items found in an original's way were
        /// kept, as a path inside the working folder, when there were any.
        case leftAsItWas(reason: String, lockedItem: String?, courseFolderIsLocked: Bool, newcomersKeptAt: String?)
        /// A move failed and a move back failed too. `keptAt` is where the
        /// set-aside files are, as a path inside the working folder;
        /// `holdsSomethingToOpen` says whether anything at all was kept there
        /// (a hidden folder such as `.obsidian` included: the review's M-c).
        case stoppedPartWay(keptAt: String, holdsSomethingToOpen: Bool)
        /// Another restore of the same course, started on this computer at
        /// the same moment, holds it (`holdTheCourse`). Nothing was written
        /// and nothing moved (the fix review's m-1: two at once were both
        /// refused 2 or 3 times in 10 on APFS and 10 in 10 on exFAT).
        case anotherRestoreHoldsTheCourse
    }

    /// What one restore did when it worked.
    struct Restored: Equatable {

        // MARK: - Stored properties

        let movesMade: Int

        /// True when the set-aside copy could not be removed or kept (a
        /// locked file deep inside, say, or a backups folder that refuses):
        /// the staging folder stays with its `done` record and the next
        /// reading tries again. Nothing in it is removed meanwhile.
        let leftTidyingForLater: Bool

        /// Where the set-aside copy was kept, as a path inside the working
        /// folder, when the record says to keep it.
        var keptWhatWasReplacedAt: String? = nil

        /// Where the files of the set-aside copy that the archive may not
        /// hold were kept, as a path inside the working folder.
        var keptWhatTheArchiveMayNotHoldAt: String? = nil
    }

    /// What the steps after the commit came to.
    struct Finished: Equatable {

        // MARK: - Stored properties

        /// Whether the staging folder is gone.
        let tidied: Bool

        /// `Restored.keptWhatWasReplacedAt`.
        let keptWhatWasReplacedAt: String?

        /// `Restored.keptWhatTheArchiveMayNotHoldAt`.
        let keptWhatTheArchiveMayNotHoldAt: String?
    }

    /// Whether this process holds the course for its restore.
    enum CourseHold: Equatable {
        /// Held, through this open folder, until it is closed.
        case held(Int32)
        /// Another restore of the course holds it now.
        case heldByAnotherRestore
        /// The volume does not lock: the records alone decide, as before.
        case notHeld
    }

    /// What the way back came to.
    struct WayBack: Equatable {

        // MARK: - Stored properties

        let everyFileIsBack: Bool

        /// Items found where an original had to go back, moved into the
        /// staging folder's `newcomersName` folder first, as paths inside
        /// the course.
        let newcomers: [String]
    }

    /// One file a zip holds, as its central directory lists it.
    struct ArchiveEntry: Equatable {

        // MARK: - Stored properties

        /// The size of the file the zip stored, uncompressed.
        let size: UInt64

        /// The modification time the zip recorded (MS-DOS form: local
        /// time, to the even second), or nil when it does not read.
        let recordedTime: Date?
    }

    /// What a zip holds, read from its central directory alone (no file in
    /// it is unpacked): every file by its path inside the course, the
    /// zip's first path part (the course folder's name) taken off, and
    /// every folder those paths pass through. Paths are compared in
    /// Unicode's composed form, since a zip keeps a name's bytes as the
    /// disk gave them.
    ///
    /// Measured on 2026-11-14 for a 500 MB course (`909/round4/listing/`):
    /// see `documentation/09-mac-app.md` → round four.
    struct ArchiveListing {

        // MARK: - Stored properties

        let files: [String: ArchiveEntry]
        let folders: Set<String>

        // MARK: - Functions

        /// The entry for a path inside the course, or nil.
        func file(at inside: String) -> ArchiveEntry? {
            return files[inside.precomposedStringWithCanonicalMapping]
        }

        /// Whether anything at all is listed at this path: a file, or a
        /// folder with something in it.
        func holdsAnything(at inside: String) -> Bool {
            let key: String = inside.precomposedStringWithCanonicalMapping
            return files[key] != nil || folders.contains(key)
        }

        /// The listing of the zip at `url`, or nil when it cannot be read
        /// (missing, cut short, not a zip): then nothing is known to be in
        /// it. Reads the end record, the zip64 end record when the counts
        /// or offsets overflow, then every central directory entry.
        static func read(_ url: URL) -> ArchiveListing? {
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                return nil
            }
            defer { try? handle.close() }
            guard let length = try? handle.seekToEnd(), length >= 22 else {
                return nil
            }
            let tailLength: UInt64 = min(length, 22 + 65_535 + 20)
            guard (try? handle.seek(toOffset: length - tailLength)) != nil,
                  let tail = try? handle.read(upToCount: Int(tailLength)) else {
                return nil
            }
            let tailBytes: [UInt8] = [UInt8](tail)
            var endAt: Int = -1
            var position: Int = tailBytes.count - 22
            while position >= 0 {
                if readUInt32(tailBytes, position) == 0x0605_4b50 {
                    endAt = position
                    break
                }
                position -= 1
            }
            if endAt < 0 {
                return nil
            }
            var directorySize: UInt64 = UInt64(readUInt32(tailBytes, endAt + 12))
            var directoryOffset: UInt64 = UInt64(readUInt32(tailBytes, endAt + 16))
            let entryCount: UInt64 = UInt64(readUInt16(tailBytes, endAt + 10))
            if directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF || entryCount == 0xFFFF {
                // The zip64 locator sits just before the end record.
                let locatorAt: Int = endAt - 20
                guard locatorAt >= 0, readUInt32(tailBytes, locatorAt) == 0x0706_4b50 else {
                    return nil
                }
                let zip64EndOffset: UInt64 = readUInt64(tailBytes, locatorAt + 8)
                guard (try? handle.seek(toOffset: zip64EndOffset)) != nil,
                      let zip64End = try? handle.read(upToCount: 56) else {
                    return nil
                }
                let zip64Bytes: [UInt8] = [UInt8](zip64End)
                guard zip64Bytes.count >= 56, readUInt32(zip64Bytes, 0) == 0x0606_4b50 else {
                    return nil
                }
                directorySize = readUInt64(zip64Bytes, 40)
                directoryOffset = readUInt64(zip64Bytes, 48)
            }
            guard directoryOffset + directorySize <= length,
                  (try? handle.seek(toOffset: directoryOffset)) != nil,
                  let directory = try? handle.read(upToCount: Int(directorySize)) else {
                return nil
            }
            return parse([UInt8](directory))
        }

        /// Every central directory entry in `bytes`.
        static func parse(_ bytes: [UInt8]) -> ArchiveListing? {
            var files: [String: ArchiveEntry] = [:]
            var folders: Set<String> = []
            var position: Int = 0
            while position + 46 <= bytes.count {
                if readUInt32(bytes, position) != 0x0201_4b50 {
                    return nil
                }
                let dosTime: UInt16 = readUInt16(bytes, position + 12)
                let dosDate: UInt16 = readUInt16(bytes, position + 14)
                var size: UInt64 = UInt64(readUInt32(bytes, position + 24))
                let nameLength: Int = Int(readUInt16(bytes, position + 28))
                let extraLength: Int = Int(readUInt16(bytes, position + 30))
                let commentLength: Int = Int(readUInt16(bytes, position + 32))
                let nameStart: Int = position + 46
                let extraStart: Int = nameStart + nameLength
                let next: Int = extraStart + extraLength + commentLength
                if next > bytes.count {
                    return nil
                }
                if size == 0xFFFF_FFFF {
                    // The zip64 extra field carries the real size first.
                    var extraAt: Int = extraStart
                    while extraAt + 4 <= extraStart + extraLength {
                        let tag: UInt16 = readUInt16(bytes, extraAt)
                        let fieldLength: Int = Int(readUInt16(bytes, extraAt + 2))
                        if tag == 0x0001 && fieldLength >= 8 {
                            size = readUInt64(bytes, extraAt + 4)
                            break
                        }
                        extraAt += 4 + fieldLength
                    }
                }
                let nameBytes: ArraySlice<UInt8> = bytes[nameStart..<extraStart]
                if let name = String(bytes: nameBytes, encoding: .utf8) {
                    let parts: [Substring] = name.split(separator: "/")
                    if parts.count >= 2 {
                        var inside: String = ""
                        for (index, part) in parts.enumerated() where index > 0 {
                            if !inside.isEmpty {
                                folders.insert(inside.precomposedStringWithCanonicalMapping)
                                inside += "/"
                            }
                            inside += String(part)
                        }
                        let key: String = inside.precomposedStringWithCanonicalMapping
                        if name.hasSuffix("/") {
                            folders.insert(key)
                        } else {
                            files[key] = ArchiveEntry(size: size, recordedTime: dosMoment(date: dosDate, time: dosTime))
                        }
                    }
                }
                position = next
            }
            return ArchiveListing(files: files, folders: folders)
        }

        /// An MS-DOS date and time as a moment, read in this Mac's time
        /// zone, as zip wrote it.
        static func dosMoment(date: UInt16, time: UInt16) -> Date? {
            var parts: DateComponents = DateComponents()
            parts.year = 1980 + Int(date >> 9)
            parts.month = Int((date >> 5) & 0x0F)
            parts.day = Int(date & 0x1F)
            parts.hour = Int(time >> 11)
            parts.minute = Int((time >> 5) & 0x3F)
            parts.second = Int(time & 0x1F) * 2
            var calendar: Calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone.current
            return calendar.date(from: parts)
        }

        static func readUInt16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
            return UInt16(bytes[at]) | (UInt16(bytes[at + 1]) << 8)
        }

        static func readUInt32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
            var value: UInt32 = 0
            for index in 0..<4 {
                value |= UInt32(bytes[at + index]) << (8 * UInt32(index))
            }
            return value
        }

        static func readUInt64(_ bytes: [UInt8], _ at: Int) -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<8 {
                value |= UInt64(bytes[at + index]) << (8 * UInt64(index))
            }
            return value
        }
    }

    // MARK: - Stored properties

    static let recordName: String = "restore.json"
    static let temporaryRecordName: String = ".restore.json.tmp"
    static let settlingPrefix: String = "restore.settling."
    static let settlerPrefix: String = "settler."
    static let settingsFileName: String = "course_config.json"
    static let unpackName: String = "backup"
    static let asideName: String = "as-it-was"
    static let newcomersName: String = "made while the restore was unfinished"

    /// The names a backup leaves out (`CourseArchiver.excludedFromArchives`)
    /// that are kept when they are found DEEPER in the set-aside copy than
    /// its top (`section1/Unit 2/My App/.git`): they are in neither the
    /// backup nor the archive made first, so removing them with the copy
    /// destroyed them, which Russell's M12 ruling forbids at the top (the
    /// fix review's third case, found by the round-three implementer). Left
    /// out of this list, and removed with the copy as before: the built
    /// site's link, Finder's `.DS_Store` and the three caches, each of which
    /// is made again and would otherwise leave a kept folder after nearly
    /// every restore.
    static let leftOutNamesKeptAtAnyDepth: [String] = ["node_modules", ".git", "dist", "build", "out"]

    /// Russell's ruling on #909's held question (2026-11-14): a name in
    /// `leftOutNamesKeptAtAnyDepth` found below the top of the set-aside
    /// copy is PUT BACK where it was in the restored course (when its
    /// folder is there and nothing is in its place), rather than kept
    /// aside. One that cannot go back is kept aside as before.
    static let putsDeeperLeftOutNamesBack: Bool = true

    /// The other names a backup leaves out: made again (the built site's
    /// link, Finder's `.DS_Store`, the three caches), so they are removed
    /// with the set-aside copy and never kept. With
    /// `leftOutNamesKeptAtAnyDepth` they are `CourseArchiver
    /// .excludedFromArchives`, which a test pins.
    static let leftOutNamesMadeAgain: [String] = [".merged_output", ".quartz-cache", ".cache", "__pycache__", ".DS_Store"]

    /// How much later than a file's creation its change must be to count as
    /// a change made after it was unpacked. A zip stores a time to the even
    /// second, rounded up, so a file unpacked from a backup made a moment
    /// ago can carry a modification time up to two seconds after it was
    /// written to the disk; and a file the archive's listing holds has a
    /// recorded time within this of its own (`heldByTheArchive`).
    static let zipTimeRoundingSeconds: Double = 2

    // MARK: - Functions: names a teacher reads

    /// The folder the set-aside copy is kept in when the record says to
    /// keep it: what was in a course folder no archive was made of. A name
    /// of its own, so it is never taken for a stop's kept folder (the fix
    /// review's I-b: both were "<CODE> before a restore").
    static func keptBeforeRestoringAgainName(_ courseCode: String) -> String {
        return "\(courseCode) as it was before restoring again"
    }

    /// The folder the files of the set-aside copy that the archive may not
    /// hold are kept in.
    static func notInTheArchiveName(_ courseCode: String) -> String {
        return "\(courseCode) not in the archive"
    }

    /// A stop's kept folder.
    static func stoppedRestoreName(_ courseCode: String) -> String {
        return "\(courseCode) before a restore"
    }

    /// The newcomers' kept folder.
    static func newcomersKeptName(_ courseCode: String) -> String {
        return "\(courseCode) made while a restore was unfinished"
    }

    // MARK: - Functions: holding the course

    /// Holds the course for one restore against another restore of it
    /// started on this computer at the same moment, in another copy of
    /// Plantoir (the fix review's m-1). An advisory lock (`flock`) on the
    /// course's own backups folder, `courses/_backups/<CODE>/`, made if it
    /// is missing: a folder that is there for every course with a backup or
    /// an archive, is never moved or removed by a restore, and holds the
    /// zip being restored. The system lets go of the lock when the process
    /// ends, however it ends, so a crash never leaves it held.
    ///
    /// Taken before the first record is written, so a restore that loses
    /// writes nothing another can count: exactly one of two goes ahead.
    /// Measured on 2026-11-14: a second process's `LOCK_NB` on a folder
    /// another holds is refused with EWOULDBLOCK on APFS and on exFAT
    /// (fskit), and granted at once after the holder is killed. Rejected:
    /// telling the two apart by their records' times (a record whose write
    /// straddles the other's whole check lets both through), a lock FILE
    /// in `courses/.internal/restoring/` (it would stop that folder being
    /// removed when empty, and removing it races the next restore), and
    /// the course folder itself (an arrival has none).
    ///
    /// Another computer is not held by this: a synced folder carries no
    /// lock. Its record is what the third refusal counts, as before.
    static func holdTheCourse(_ courseCode: String, coursesDirectoryURL: URL) -> CourseHold {
        let shelf: URL = coursesDirectoryURL.appendingPathComponent("_backups").appendingPathComponent(courseCode)
        try? FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
        var descriptor: Int32 = open(shelf.path, O_RDONLY)
        if descriptor < 0 {
            // A backups folder that cannot be made: the courses folder, which
            // every restore of every course can open, so two restores that
            // both fall back here still exclude each other.
            descriptor = open(coursesDirectoryURL.path, O_RDONLY)
        }
        if descriptor < 0 {
            return .notHeld
        }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            return .held(descriptor)
        }
        let reason: Int32 = errno
        close(descriptor)
        if reason == EWOULDBLOCK {
            return .heldByAnotherRestore
        }
        return .notHeld
    }

    /// Lets go of a hold.
    static func letGo(_ hold: CourseHold) {
        if case .held(let descriptor) = hold {
            close(descriptor)
        }
    }

    // MARK: - Functions: where things are

    /// `courses/.internal/restoring`, where every restore stages.
    static func restoringFolder(_ coursesDirectoryURL: URL) -> URL {
        return coursesDirectoryURL
            .appendingPathComponent(".internal")
            .appendingPathComponent("restoring")
    }

    /// A path relative to `courses/` (or to any folder `url` was built
    /// from), compared as TEXT. Every URL here is built from the one
    /// `coursesDirectoryURL` by appending, so the prefix always matches.
    /// Not `standardizedFileURL`, measured wrong here: it drops `/private`
    /// from `/private/tmp/...` only for a path that exists, so a planned
    /// destination and its existing parent came out with different
    /// prefixes and a move was sent into `courses/private/tmp/...`.
    static func relative(_ url: URL, to coursesDirectoryURL: URL) -> String {
        let root: String = trimmedPath(coursesDirectoryURL) + "/"
        let path: String = trimmedPath(url)
        if path.hasPrefix(root) {
            return String(path.dropFirst(root.count))
        }
        return path
    }

    /// A URL's path without a trailing slash.
    static func trimmedPath(_ url: URL) -> String {
        var path: String = url.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// A path relative to `courses/` made whole again.
    static func absolute(_ relativePath: String, in coursesDirectoryURL: URL) -> URL {
        var url: URL = coursesDirectoryURL
        for part in relativePath.split(separator: "/") {
            url = url.appendingPathComponent(String(part))
        }
        return url
    }

    /// Whether anything is at this path, a link included, without following
    /// it (`FileManager.fileExists` follows a link, so a link to nothing
    /// would read as missing).
    static func itemExists(at url: URL) -> Bool {
        var status: stat = stat()
        return lstat(url.path, &status) == 0
    }

    // MARK: - Functions: the record

    /// Writes the record: a temporary file, flushed, renamed into place,
    /// then the folder flushed, so a power cut leaves the old record or the
    /// new one and never half of one.
    static func writeRecord(_ record: Record, in staging: URL, hooks: Hooks) throws {
        try hooks.step("record " + record.phase.rawValue)
        try writeRecord(record, to: staging.appendingPathComponent(recordName), flushes: hooks.flushes)
    }

    /// Writes a record to a named file by way of a temporary one.
    static func writeRecord(_ record: Record, to destination: URL, flushes: Bool) throws {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data = try encoder.encode(record)
        let folder: URL = destination.deletingLastPathComponent()
        let temporary: URL = folder.appendingPathComponent(temporaryRecordName)
        try data.write(to: temporary)
        if flushes {
            flush(temporary)
        }
        if rename(temporary.path, destination.path) != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
        if flushes {
            flush(folder)
        }
    }

    /// `F_FULLFSYNC`: past the disk's own cache, as `fsync` alone is not on
    /// a Mac.
    static func flush(_ url: URL) {
        let descriptor: Int32 = open(url.path, O_RDONLY)
        if descriptor < 0 {
            return
        }
        _ = fcntl(descriptor, F_FULLFSYNC)
        close(descriptor)
    }

    /// The record in a file, or nil when there is none that reads.
    static func readRecord(at url: URL) -> Record? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    // MARK: - Functions: the plan

    /// Every move a whole-course restore makes, in order: each of the
    /// course's top-level items aside, settings FIRST; then each of the
    /// backup's in, settings LAST (the plan review, H1). A name kept in
    /// place is never moved; one the backup also carries stays in staging
    /// and goes with it. The rest go in name order, so the plan is the same
    /// on every run and on both platforms.
    static func planCourseSwap(
        courseURL: URL,
        payloadURL: URL,
        asideURL: URL,
        coursesDirectoryURL: URL,
        keptInPlace: [String]
    ) throws -> [Move] {
        let fileManager: FileManager = FileManager.default
        var liveNames: [String] = []
        for name in try fileManager.contentsOfDirectory(atPath: courseURL.path) where !keptInPlace.contains(name) {
            liveNames.append(name)
        }
        var backupNames: [String] = []
        for name in try fileManager.contentsOfDirectory(atPath: payloadURL.path) where !keptInPlace.contains(name) {
            backupNames.append(name)
        }
        var moves: [Move] = []
        for name in settingsAtTheEdge(liveNames, first: true) {
            moves.append(Move(
                from: relative(courseURL.appendingPathComponent(name), to: coursesDirectoryURL),
                to: relative(asideURL.appendingPathComponent(name), to: coursesDirectoryURL),
                out: true
            ))
        }
        for name in settingsAtTheEdge(backupNames, first: false) {
            moves.append(Move(
                from: relative(payloadURL.appendingPathComponent(name), to: coursesDirectoryURL),
                to: relative(courseURL.appendingPathComponent(name), to: coursesDirectoryURL),
                out: false
            ))
        }
        return moves
    }

    /// Names in order, with the settings file first or last.
    static func settingsAtTheEdge(_ names: [String], first: Bool) -> [String] {
        var others: [String] = []
        var hasSettings: Bool = false
        for name in names.sorted() {
            if name == settingsFileName {
                hasSettings = true
            } else {
                others.append(name)
            }
        }
        if !hasSettings {
            return others
        }
        if first {
            return [settingsFileName] + others
        }
        return others + [settingsFileName]
    }

    // MARK: - Functions: the swap and the way back

    /// Makes the moves in order. Throws `SwapStopped` carrying how many were
    /// made and the error of the one that failed.
    static func swap(_ moves: [Move], coursesDirectoryURL: URL, hooks: Hooks) throws {
        var made: Int = 0
        for move in moves {
            let from: URL = absolute(move.from, in: coursesDirectoryURL)
            let to: URL = absolute(move.to, in: coursesDirectoryURL)
            do {
                try hooks.step("move " + from.lastPathComponent)
                try FileManager.default.createDirectory(
                    at: to.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try hooks.move(from, to)
            } catch {
                throw SwapStopped(made: made, failed: move, underlying: error)
            }
            made += 1
        }
    }

    /// Thrown by `swap`.
    struct SwapStopped: Error {

        // MARK: - Stored properties

        let made: Int
        let failed: Move
        let underlying: Error
    }

    /// Makes the recorded moves backwards, last first, judging each by which
    /// of its two ends holds something, so it serves both a failure in this
    /// process and a crash found at the next reading:
    ///
    /// * an `out` move whose set-aside end is empty was not made (or is
    ///   back): skipped. One whose set-aside end holds the original and
    ///   whose course end is free goes back. One whose course end is TAKEN
    ///   (Obsidian, open on the vault through the hours after a crash,
    ///   recreating `.obsidian/`) is never skipped and never deleted (the
    ///   plan review, H4): the newcomer moves into `newcomersURL` first, and
    ///   then the original goes back; if either move fails it is BLOCKED.
    /// * an `in` move whose staging end still holds the backup's item was
    ///   not made: skipped. One whose course end holds it goes back.
    ///
    /// **The settings are the last thing to go back, and only over a course
    /// whose every other file is back** (the implementation review's I1).
    /// The course's own `course_config.json` moves out FIRST, so it is the
    /// last move back; when any earlier move back failed it stays aside,
    /// with the set-aside copy that is kept, and the course reads as no
    /// course (`notInTheSidebar`), so nothing builds or deploys a mix.
    /// Measured on the shipped engine before this: 101 of 119 double-fault
    /// mixes had their settings back. Likewise the backup's settings move in
    /// LAST, so they are the first move back; when that move back fails the
    /// way back stops there, and the course is left wholly the backup's
    /// rather than a mix under the backup's settings.
    static func wayBack(
        _ moves: [Move],
        coursesDirectoryURL: URL,
        courseURL: URL,
        newcomersURL: URL,
        hooks: Hooks
    ) -> WayBack {
        let fileManager: FileManager = FileManager.default
        let settingsInTheCourse: String = relative(courseURL.appendingPathComponent(settingsFileName), to: coursesDirectoryURL)
        var everyFileIsBack: Bool = true
        var newcomers: [String] = []
        for move in moves.reversed() {
            let from: URL = absolute(move.from, in: coursesDirectoryURL)
            let to: URL = absolute(move.to, in: coursesDirectoryURL)
            if !itemExists(at: to) {
                continue
            }
            let isTheSettings: Bool = (move.out ? move.from : move.to) == settingsInTheCourse
            if move.out {
                if itemExists(at: from) {
                    let insideTheCourse: String = relative(from, to: courseURL)
                    let keptNewcomer: URL = absolute(insideTheCourse, in: newcomersURL)
                    do {
                        try fileManager.createDirectory(
                            at: keptNewcomer.deletingLastPathComponent(), withIntermediateDirectories: true
                        )
                        try hooks.moveBack(from, keptNewcomer)
                        newcomers.append(insideTheCourse)
                    } catch {
                        everyFileIsBack = false
                        continue
                    }
                }
                if isTheSettings && !everyFileIsBack {
                    // I1: over a mix, the settings stay aside.
                    continue
                }
                do {
                    try hooks.moveBack(to, from)
                } catch {
                    everyFileIsBack = false
                }
            } else {
                if itemExists(at: from) {
                    // Never made: the backup's copy is still in staging, and
                    // what is in the course is not the backup's.
                    continue
                }
                do {
                    try fileManager.createDirectory(
                        at: from.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    try hooks.moveBack(to, from)
                } catch {
                    everyFileIsBack = false
                    if isTheSettings {
                        // The backup's settings would not leave, and every
                        // other move was made: stop here, so the course is
                        // the backup's whole rather than a mix under them.
                        return WayBack(everyFileIsBack: false, newcomers: newcomers)
                    }
                }
            }
        }
        return WayBack(everyFileIsBack: everyFileIsBack, newcomers: newcomers)
    }

    /// Whether an `out` move's original is at NEITHER end: evidence that the
    /// old copy was already being deleted, which can only happen if the
    /// `done` record was lost. A settle that finds it moves nothing (the
    /// plan's R7).
    static func anOriginalIsAtNeitherEnd(_ moves: [Move], coursesDirectoryURL: URL) -> Bool {
        for move in moves where move.out {
            let from: URL = absolute(move.from, in: coursesDirectoryURL)
            let to: URL = absolute(move.to, in: coursesDirectoryURL)
            if !itemExists(at: from) && !itemExists(at: to) {
                return true
            }
        }
        return false
    }

    // MARK: - Functions: one restore

    /// Restores a whole course from a backup zip, staged (#909). Every step
    /// before the commit can stop with the course as it was; see
    /// `contracts/course-management.json` → `backups.restoreWholeCourse`.
    ///
    /// When `courseCode`'s folder is not there, this is an ARRIVAL: one
    /// planned move of the whole unpacked folder into place, staged the
    /// same way, so on another volume it is still a rename.
    static func restore(
        fromZipAt zipURL: URL,
        courseCode: String,
        backupFileName: String,
        from source: Source = Source.backups,
        coursesDirectoryURL: URL,
        context: Context,
        hooks: Hooks = Hooks.real
    ) throws -> Restored {
        let fileManager: FileManager = FileManager.default
        let hold: CourseHold = holdTheCourse(courseCode, coursesDirectoryURL: coursesDirectoryURL)
        if hold == .heldByAnotherRestore {
            throw Failure.anotherRestoreHoldsTheCourse
        }
        defer { letGo(hold) }
        let courseURL: URL = coursesDirectoryURL.appendingPathComponent(courseCode)
        let staging: URL = restoringFolder(coursesDirectoryURL).appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        var record: Record = Record(
            course: courseCode,
            backup: backupFileName,
            from: source,
            archive: context.archiveURL?.lastPathComponent,
            phase: .unpacking,
            moves: [],
            computer: context.computer,
            owner: context.owner,
            writtenAt: context.now()
        )
        if let began = context.archiveBegan {
            record.archiveBegan = momentTextRoundedDown(began)
        }
        if !context.leftOutOnPurpose.isEmpty {
            record.leftOutOnPurpose = context.leftOutOnPurpose
        }
        let unpacked: URL = staging.appendingPathComponent(unpackName)
        let payload: URL
        do {
            try writeRecord(record, in: staging, hooks: hooks)
            try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
            payload = try unpack(zipURL, named: courseCode, into: unpacked)
            try context.checkPayload(payload)
            try context.putMediaBack(unpacked, itemExists(at: courseURL) ? courseURL : nil)
            try context.refuseUnlessMediaWasPutBack(unpacked)
            if let archiveURL = context.archiveURL {
                flush(archiveURL)
            }
            try context.beforeTheSwap(staging)
        } catch {
            removeStaging(staging)
            throw error
        }

        let aside: URL = staging.appendingPathComponent(asideName)
        var moves: [Move] = []
        // Whether this is an arrival, and so whether the set-aside copy is
        // the only copy of what was in the folder, is decided HERE, under
        // the hold, in the step that writes the moves it acts on (the
        // round-three review: the door decided it a moment earlier, and a
        // folder made in that gap had its one page removed). No archive
        // and a folder that is there: the copy is kept whole.
        let isAnArrival: Bool = !itemExists(at: courseURL)
        if context.archiveURL == nil && !isAnArrival {
            record.keepsWhatWasReplaced = true
        }
        do {
            if isAnArrival {
                moves.append(Move(
                    from: relative(payload, to: coursesDirectoryURL),
                    to: relative(courseURL, to: coursesDirectoryURL),
                    out: false
                ))
            } else {
                try fileManager.createDirectory(at: aside, withIntermediateDirectories: true)
                moves = try planCourseSwap(
                    courseURL: courseURL,
                    payloadURL: payload,
                    asideURL: aside,
                    coursesDirectoryURL: coursesDirectoryURL,
                    keptInPlace: context.keptInPlace
                )
            }
            record.phase = .swapping
            record.moves = moves
            record.writtenAt = context.now()
            record.writtenAfter = writtenAfterMoment(swapping: record.writtenAt, zipURL: zipURL)
            try writeRecord(record, in: staging, hooks: hooks)
        } catch {
            removeStaging(staging)
            throw error
        }

        context.justBeforeTheSwap()
        let writtenAfter: Date? = writtenAfterMoment(of: record)
        do {
            try swap(moves, coursesDirectoryURL: coursesDirectoryURL, hooks: hooks)
        } catch let stopped as SwapStopped {
            let newcomersURL: URL = staging.appendingPathComponent(newcomersName)
            let back: WayBack = wayBack(
                moves,
                coursesDirectoryURL: coursesDirectoryURL,
                courseURL: courseURL,
                newcomersURL: newcomersURL,
                hooks: hooks
            )
            // What was written into the backup's items while they were in
            // the course goes with the newcomers, never with the staging
            // folder (the third case).
            let everyWrittenFileIsOut: Bool = keepWhatWasWrittenIntoTheBackupsItems(
                moves, after: writtenAfter, courseURL: courseURL,
                coursesDirectoryURL: coursesDirectoryURL, newcomersURL: newcomersURL
            )
            if back.everyFileIsBack {
                var kept: String? = nil
                if everyWrittenFileIsOut {
                    kept = keepNewcomers(
                        in: staging, courseCode: courseCode, coursesDirectoryURL: coursesDirectoryURL, context: context
                    )
                    if kept == nil {
                        removeStaging(staging)
                    }
                }
                // Otherwise the staging folder stays with its `swapping`
                // record, and the next reading puts the rest out.
                let lockedItem: String? = lockedItemName(stopped, courseURL: courseURL, coursesDirectoryURL: coursesDirectoryURL)
                throw Failure.leftAsItWas(
                    reason: reasonWithoutStagingPaths(stopped.underlying),
                    lockedItem: lockedItem,
                    courseFolderIsLocked: lockedItem != nil && folderRefusesChanges(courseURL),
                    newcomersKeptAt: kept
                )
            }
            record.phase = .stopped
            record.writtenAt = context.now()
            try? writeRecord(record, to: staging.appendingPathComponent(recordName), flushes: hooks.flushes)
            let kept: (path: String, holdsSomethingToOpen: Bool) = keepTheSetAside(
                staging: staging, courseCode: courseCode, coursesDirectoryURL: coursesDirectoryURL, context: context,
                mayRemoveWhatIsLeft: everyWrittenFileIsOut
            )
            throw Failure.stoppedPartWay(keptAt: kept.path, holdsSomethingToOpen: kept.holdsSomethingToOpen)
        }

        record.phase = .done
        record.writtenAt = context.now()
        do {
            try writeRecord(record, in: staging, hooks: hooks)
        } catch {
            // Every move was made, so the restore has happened. A record
            // that could not say so stays `swapping`: if anything is left
            // below, the reading that finds it puts the course back, which
            // loses nothing.
        }
        let finished: Finished = finishAfterTheCommit(
            staging: staging, record: record, coursesDirectoryURL: coursesDirectoryURL, context: context, hooks: hooks
        )
        return Restored(
            movesMade: moves.count,
            leftTidyingForLater: !finished.tidied,
            keptWhatWasReplacedAt: finished.keptWhatWasReplacedAt,
            keptWhatTheArchiveMayNotHoldAt: finished.keptWhatTheArchiveMayNotHoldAt
        )
    }

    /// What is left to do once the restore has happened, by the restore
    /// itself and by a settle that finds `done`: the app's own after-commit
    /// steps; then the set-aside copy KEPT when the record says so, or else
    /// the files of it the archive may not hold kept and Undo's seam handed
    /// the rest; then the old copy and the staging folder removed.
    ///
    /// **Nothing is removed that is not known to be somewhere else.** When a
    /// keep fails (the backups folder refuses, say), the copy is not
    /// removed: the result is not tidied, the `done` record stays with it,
    /// and the next reading tries again from the record (the fix review's
    /// I-a: the keep's result was ignored, and a settle passed no keep at
    /// all; each removed 45 of 45 files).
    @discardableResult
    static func finishAfterTheCommit(
        staging: URL,
        record: Record,
        coursesDirectoryURL: URL,
        context: Context,
        hooks: Hooks
    ) -> Finished {
        context.afterCommit()
        let aside: URL = staging.appendingPathComponent(asideName)
        var keptAt: String? = nil
        var notInTheArchiveAt: String? = nil
        if itemExists(at: aside) {
            if record.keepsWhatWasReplaced == true {
                do {
                    try hooks.step("keep the old copy")
                } catch {
                    return Finished(tidied: false, keptWhatWasReplacedAt: nil, keptWhatTheArchiveMayNotHoldAt: nil)
                }
                guard let kept = moveToTheBackupsFolder(
                    aside, courseCode: record.course, name: keptBeforeRestoringAgainName(record.course),
                    coursesDirectoryURL: coursesDirectoryURL, context: context
                ) else {
                    return Finished(tidied: false, keptWhatWasReplacedAt: nil, keptWhatTheArchiveMayNotHoldAt: nil)
                }
                keptAt = insideTheWorkingFolder(kept, coursesDirectoryURL: coursesDirectoryURL)
            } else {
                do {
                    try hooks.step("keep what the archive may not hold")
                } catch {
                    return Finished(tidied: false, keptWhatWasReplacedAt: nil, keptWhatTheArchiveMayNotHoldAt: nil)
                }
                var archiveBegan: Date? = nil
                if let began = record.archiveBegan {
                    archiveBegan = RestoreSettle.parsedMoment(began)
                }
                // What the archive HOLDS, read from its own listing: the live
                // restore's archive, or the one the record names for a settle.
                var listing: ArchiveListing? = nil
                if let archive = context.archiveURL ?? archiveNamed(in: record, coursesDirectoryURL: coursesDirectoryURL) {
                    listing = ArchiveListing.read(archive)
                }
                let gathered: (keptAt: String?, everythingMoved: Bool) = keepWhatTheArchiveMayNotHold(
                    aside, courseCode: record.course, listing: listing, archiveBegan: archiveBegan,
                    leftOutOnPurpose: record.leftOutOnPurpose ?? [],
                    coursesDirectoryURL: coursesDirectoryURL, context: context
                )
                notInTheArchiveAt = gathered.keptAt
                if !gathered.everythingMoved {
                    return Finished(tidied: false, keptWhatWasReplacedAt: nil, keptWhatTheArchiveMayNotHoldAt: notInTheArchiveAt)
                }
                context.keepingWhatWasReplaced?(aside)
            }
        }
        do {
            try hooks.step("remove the old copy")
        } catch {
            return Finished(tidied: false, keptWhatWasReplacedAt: keptAt, keptWhatTheArchiveMayNotHoldAt: notInTheArchiveAt)
        }
        var removed: Bool = true
        if itemExists(at: aside) {
            removed = removeUnlocking(aside)
        }
        if !removed {
            return Finished(tidied: false, keptWhatWasReplacedAt: keptAt, keptWhatTheArchiveMayNotHoldAt: notInTheArchiveAt)
        }
        do {
            try hooks.step("remove staging")
        } catch {
            return Finished(tidied: false, keptWhatWasReplacedAt: keptAt, keptWhatTheArchiveMayNotHoldAt: notInTheArchiveAt)
        }
        removeStaging(staging)
        return Finished(
            tidied: !itemExists(at: staging), keptWhatWasReplacedAt: keptAt, keptWhatTheArchiveMayNotHoldAt: notInTheArchiveAt
        )
    }

    // MARK: - Functions: keeping what exists nowhere else

    /// Moves out of the set-aside copy, before it is removed, every file
    /// the archive made first does not hold, into
    /// `courses/_backups/<CODE>/<CODE> not in the archive <stamp>/` at its
    /// path inside the course (round three's third case; round four's rule,
    /// `contracts/course-management.json` → `keptFolders.notInTheArchive`):
    ///
    /// * anything named in `leftOutNamesKeptAtAnyDepth`, at any depth: a
    ///   `.git` inside a section's sample project is in neither the backup
    ///   nor the archive;
    /// * every file and link the archive's own LISTING does not hold
    ///   (`heldByTheArchive`): a path and size the zip carries, with the
    ///   time the zip recorded for it, and none of the file's own times at
    ///   or after `archiveBegan`. Hidden files are judged the same way (the
    ///   round-three review: an edit to the timetable was lost). When the
    ///   listing cannot be read, nothing is known to be held, so every file
    ///   is kept.
    ///
    /// Removed with the copy: `leftOutNamesMadeAgain`, which are made
    /// again, and `leftOutOnPurpose`, the add-on folders the next pass puts
    /// back.
    ///
    /// Until round four a file was judged by its creation and content
    /// times alone, and a file that ARRIVED after the zip's scan with old
    /// dates (`mv`, `cp -p`, `ditto`, a folder moved in) was in neither the
    /// archive nor a kept folder: 6 of 6 such files lost on APFS (the
    /// round-three review's `edges.py`).
    ///
    /// Returns where they went, and false when any could not be moved: then
    /// the copy must not be removed.
    static func keepWhatTheArchiveMayNotHold(
        _ aside: URL,
        courseCode: String,
        listing: ArchiveListing?,
        archiveBegan: Date?,
        leftOutOnPurpose: [String],
        coursesDirectoryURL: URL,
        context: Context
    ) -> (keptAt: String?, everythingMoved: Bool) {
        let keys: [URLResourceKey] = [
            .isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey
        ]
        guard let walker = FileManager.default.enumerator(at: aside, includingPropertiesForKeys: keys, options: []) else {
            return (nil, true)
        }
        var picked: [String] = []
        while let entry = walker.nextObject() as? URL {
            let inside: String = relative(entry, to: aside)
            let name: String = entry.lastPathComponent
            if leftOutNamesKeptAtAnyDepth.contains(name) {
                walker.skipDescendants()
                // Russell's ruling on #909 (2026-11-14): put back where it
                // was in the restored course when its folder is there and
                // nothing is in its place; otherwise kept aside as before.
                if putsDeeperLeftOutNamesBack && putBackIntoTheCourse(
                    inside, from: aside, courseURL: coursesDirectoryURL.appendingPathComponent(courseCode)
                ) {
                    continue
                }
                picked.append(inside)
                continue
            }
            if leftOutNamesMadeAgain.contains(name) || isInside(inside, anyOf: leftOutOnPurpose) {
                walker.skipDescendants()
                continue
            }
            let values: URLResourceValues? = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                walker.skipDescendants()
                // A link: zip follows it, so the archive holds what it
                // pointed at under its path. One that is not listed is kept
                // as a link; what it points at is never touched.
                if listing?.holdsAnything(at: inside) != true {
                    picked.append(inside)
                }
                continue
            }
            if values?.isRegularFile != true {
                continue
            }
            if !heldByTheArchive(inside, values: values, listing: listing, archiveBegan: archiveBegan) {
                picked.append(inside)
            }
        }
        if picked.isEmpty {
            return (nil, true)
        }
        guard let folder = newFolderInTheBackupsFolder(
            courseCode: courseCode, name: notInTheArchiveName(courseCode),
            coursesDirectoryURL: coursesDirectoryURL, stamp: context.stamp()
        ) else {
            return (nil, false)
        }
        var everythingMoved: Bool = true
        for inside in picked {
            let destination: URL = absolute(inside, in: folder)
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: absolute(inside, in: aside), to: destination)
            } catch {
                everythingMoved = false
            }
        }
        return (insideTheWorkingFolder(folder, coursesDirectoryURL: coursesDirectoryURL), everythingMoved)
    }

    /// Moves an item of the set-aside copy to the same path in the restored
    /// course, never over anything and only into a folder that is there.
    /// True when it moved.
    static func putBackIntoTheCourse(_ inside: String, from aside: URL, courseURL: URL) -> Bool {
        let destination: URL = absolute(inside, in: courseURL)
        let parent: URL = destination.deletingLastPathComponent()
        var status: stat = stat()
        if lstat(parent.path, &status) != 0 || (status.st_mode & S_IFMT) != S_IFDIR {
            return false
        }
        if itemExists(at: destination) {
            return false
        }
        do {
            try FileManager.default.moveItem(at: absolute(inside, in: aside), to: destination)
            return true
        } catch {
            return false
        }
    }

    /// Whether the archive made first holds this file of the set-aside copy
    /// as it is now: its listing carries the path (Unicode-normalised) with
    /// the same size and a recorded time within `zipTimeRoundingSeconds` of
    /// the file's content time, and neither the file's creation nor its
    /// content time is at or after `archiveBegan` (a page saved in place in
    /// the moments after zip read it keeps its size and can land in the
    /// same two-second step).
    ///
    /// Decided by what the archive HOLDS, not by a clock alone: a file
    /// moved, copied or dragged in after the zip's scan keeps its old dates
    /// but is not in the listing, so it is kept. What still escapes: a file
    /// replaced at the same path, before the archive began's clock says so,
    /// by another of the very same size whose content time is within two
    /// seconds of the old one's (`knownLimits`).
    static func heldByTheArchive(
        _ inside: String,
        values: URLResourceValues?,
        listing: ArchiveListing?,
        archiveBegan: Date?
    ) -> Bool {
        guard let listing, let entry = listing.file(at: inside) else {
            return false
        }
        guard let size = values?.fileSize, UInt64(size) == entry.size else {
            return false
        }
        guard let changed = values?.contentModificationDate else {
            return false
        }
        guard let recorded = entry.recordedTime, abs(recorded.timeIntervalSince(changed)) <= zipTimeRoundingSeconds else {
            return false
        }
        if let archiveBegan {
            let made: Date = values?.creationDate ?? Date.distantPast
            if made >= archiveBegan || changed >= archiveBegan {
                return false
            }
        }
        return true
    }

    /// Whether a path inside the course is one of `folders` or inside one.
    static func isInside(_ inside: String, anyOf folders: [String]) -> Bool {
        for folder in folders {
            if inside == folder || inside.hasPrefix(folder + "/") {
                return true
            }
        }
        return false
    }

    /// The archive a record names, in the course's backups folder, where
    /// `CourseArchiver` writes it, or nil.
    static func archiveNamed(in record: Record, coursesDirectoryURL: URL) -> URL? {
        guard let name = record.archive else {
            return nil
        }
        return coursesDirectoryURL
            .appendingPathComponent("_backups")
            .appendingPathComponent(record.course)
            .appendingPathComponent(name)
    }

    /// After a way back: every file inside the backup's items that went
    /// back to staging and was made or changed after the swap began is
    /// moved into `newcomersURL`, at its path inside the course, so the
    /// staging folder's removal never takes it (the third case). A crash
    /// mid-swap leaves the backup's folders in the course for the hours
    /// until the next reading, and Obsidian, open on the vault, writes a
    /// teacher's pages into them; the way back carried those pages into
    /// staging, and its removal deleted them.
    ///
    /// Judged by the file's own times against `Record.writtenAfter`: a
    /// creation, content or inode time later than it. The inode time is
    /// what shows a page moved in from elsewhere on APFS (it keeps its old
    /// dates). For an item at the top of the course the inode time is not
    /// asked, because the swap's own renames change it. A file unpacked
    /// from the backup and untouched since has no time later than it
    /// (`writtenAfterMoment`), so it is never taken.
    ///
    /// Returns false when any could not be moved: the staging folder must
    /// then stay.
    static func keepWhatWasWrittenIntoTheBackupsItems(
        _ moves: [Move],
        after writtenAfter: Date?,
        courseURL: URL,
        coursesDirectoryURL: URL,
        newcomersURL: URL
    ) -> Bool {
        guard let writtenAfter else {
            return true
        }
        let fileManager: FileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .isSymbolicLinkKey, .isRegularFileKey, .creationDateKey, .contentModificationDateKey, .attributeModificationDateKey
        ]
        var everythingMoved: Bool = true
        for move in moves where !move.out {
            let staged: URL = absolute(move.from, in: coursesDirectoryURL)
            if !itemExists(at: staged) {
                continue
            }
            var insideTheCourse: String = ""
            let destinationInTheCourse: URL = absolute(move.to, in: coursesDirectoryURL)
            if trimmedPath(destinationInTheCourse) != trimmedPath(courseURL) {
                insideTheCourse = relative(destinationInTheCourse, to: courseURL)
            }
            var picked: [(from: URL, inside: String)] = []
            let topValues: URLResourceValues? = try? staged.resourceValues(forKeys: Set(keys))
            if topValues?.isSymbolicLink == true {
                continue
            }
            if topValues?.isRegularFile == true {
                if wasWrittenAfter(writtenAfter, values: topValues, atTheTop: true) {
                    picked.append((from: staged, inside: insideTheCourse))
                }
            } else if let walker = fileManager.enumerator(at: staged, includingPropertiesForKeys: keys, options: []) {
                while let entry = walker.nextObject() as? URL {
                    let values: URLResourceValues? = try? entry.resourceValues(forKeys: Set(keys))
                    if values?.isSymbolicLink == true {
                        walker.skipDescendants()
                        continue
                    }
                    if values?.isRegularFile != true {
                        continue
                    }
                    if wasWrittenAfter(writtenAfter, values: values, atTheTop: false) {
                        let below: String = relative(entry, to: staged)
                        let inside: String = insideTheCourse.isEmpty ? below : insideTheCourse + "/" + below
                        picked.append((from: entry, inside: inside))
                    }
                }
            }
            for file in picked {
                let destination: URL = unusedURL(absolute(file.inside, in: newcomersURL))
                do {
                    try fileManager.createDirectory(
                        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(at: file.from, to: destination)
                } catch {
                    everythingMoved = false
                }
            }
        }
        return everythingMoved
    }

    /// `Record.writtenAfter` for a swap whose record was written at
    /// `swapping`, from this zip. Measured on 2026-11-14 with a file ditto
    /// unpacked: on APFS its creation and content times are the zip's and
    /// its inode time the unpack's; on exFAT its creation time is the
    /// unpack's and its content and inode times the zip's. The zip's times
    /// are no later than the zip file itself plus the rounding, and the
    /// unpack is before the record, so a file untouched since has no time
    /// later than this.
    static func writtenAfterMoment(swapping: String, zipURL: URL) -> String {
        var moment: Date = RestoreSettle.parsedMoment(swapping) ?? Date()
        let values: URLResourceValues? = try? zipURL.resourceValues(forKeys: [.contentModificationDateKey])
        if let zipTime = values?.contentModificationDate {
            let latest: Date = zipTime.addingTimeInterval(zipTimeRoundingSeconds)
            if latest > moment {
                moment = latest
            }
        }
        return momentTextRoundedDown(moment)
    }

    /// A moment as a record writes it, to the millisecond, rounded DOWN, so
    /// a file written in the same millisecond is judged written after it:
    /// the side that keeps. Measured: a page saved within a millisecond of
    /// the moment was kept in one run of the harness and not in the next
    /// before this.
    static func momentTextRoundedDown(_ moment: Date) -> String {
        let milliseconds: Double = (moment.timeIntervalSinceReferenceDate * 1000).rounded(.down)
        return RestoreSettle.momentText(Date(timeIntervalSinceReferenceDate: milliseconds / 1000))
    }

    /// A record's `writtenAfter`, or for a record an older build wrote,
    /// nil: nothing is judged written, as before.
    static func writtenAfterMoment(of record: Record) -> Date? {
        guard let after = record.writtenAfter else {
            return nil
        }
        return RestoreSettle.parsedMoment(after)
    }

    /// `keepWhatWasWrittenIntoTheBackupsItems`' test for one file.
    static func wasWrittenAfter(_ moment: Date, values: URLResourceValues?, atTheTop: Bool) -> Bool {
        if let made = values?.creationDate, made > moment {
            return true
        }
        if let changed = values?.contentModificationDate, changed > moment {
            return true
        }
        if !atTheTop, let inode = values?.attributeModificationDate, inode > moment {
            return true
        }
        return false
    }

    /// A URL with " (2)", " (3)" and so on before its extension until
    /// nothing is there.
    static func unusedURL(_ url: URL) -> URL {
        if !itemExists(at: url) {
            return url
        }
        let folder: URL = url.deletingLastPathComponent()
        let stem: String = url.deletingPathExtension().lastPathComponent
        let pathExtension: String = url.pathExtension
        var attempt: Int = 2
        while attempt < 1000 {
            var name: String = stem + " (\(attempt))"
            if !pathExtension.isEmpty {
                name += "." + pathExtension
            }
            let candidate: URL = folder.appendingPathComponent(name)
            if !itemExists(at: candidate) {
                return candidate
            }
            attempt += 1
        }
        return url
    }

    /// Removes a tree, clearing Finder's Locked flag and making folders
    /// writable on the way, WITHOUT following a link (the plan review, M7):
    /// a course can hold a link to a folder outside it, and a walk that
    /// followed it would unlock the teacher's files elsewhere, or loop.
    /// Measured necessary: a locked page nested in the old copy refuses
    /// `removeItem` (the plan's 1.3).
    static func removeUnlocking(_ root: URL) -> Bool {
        clearLockAndMakeWritable(root)
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey]
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: []) {
            while let entry = walker.nextObject() as? URL {
                let values: URLResourceValues? = try? entry.resourceValues(forKeys: Set(keys))
                if values?.isSymbolicLink == true {
                    walker.skipDescendants()
                    continue
                }
                clearLockAndMakeWritable(entry)
            }
        }
        do {
            try FileManager.default.removeItem(at: root)
            return true
        } catch {
            return false
        }
    }

    /// Clears `uchg` on the item itself (never a link's target) and gives a
    /// folder write and search permission for its owner.
    static func clearLockAndMakeWritable(_ url: URL) {
        var status: stat = stat()
        if lstat(url.path, &status) != 0 {
            return
        }
        if (status.st_mode & S_IFMT) == S_IFLNK {
            return
        }
        if status.st_flags & UInt32(UF_IMMUTABLE) != 0 {
            _ = lchflags(url.path, status.st_flags & ~UInt32(UF_IMMUTABLE))
        }
        if (status.st_mode & S_IFMT) == S_IFDIR {
            _ = chmod(url.path, status.st_mode | S_IRWXU)
        }
    }

    /// Removes a staging folder, then `restoring` and `.internal` when each
    /// is left empty (`rmdir`, which refuses a folder that is not, so a
    /// lease written into `.internal/activity/` meanwhile is never taken).
    static func removeStaging(_ staging: URL) {
        try? FileManager.default.removeItem(at: staging)
        var parent: URL = staging.deletingLastPathComponent()
        for _ in 0..<2 {
            if rmdir(parent.path) != 0 {
                return
            }
            parent = parent.deletingLastPathComponent()
        }
    }

    // MARK: - Functions: unpacking

    /// Unzips into `staging` with `ditto` and returns the folder the name
    /// promised, or the single folder the zip holds. A full disk is
    /// `Failure.noSpace`, recognised by `ditto`'s own words for ENOSPC
    /// ("No space left on device"; a contract case).
    static func unpack(_ archiveURL: URL, named expectedName: String, into staging: URL) throws -> URL {
        let fileManager: FileManager = FileManager.default
        let unzip: Process = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", archiveURL.path, staging.path]
        let errors: Pipe = Pipe()
        unzip.standardError = errors
        try unzip.run()
        let data: Data = errors.fileHandleForReading.readDataToEndOfFile()
        unzip.waitUntilExit()
        if unzip.terminationStatus != 0 {
            let reason: String = String(data: data, encoding: .utf8) ?? "unknown error"
            if saysTheDiskIsFull(reason) {
                throw Failure.noSpace
            }
            throw Failure.unreadable(reason.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var payload: URL = staging.appendingPathComponent(expectedName)
        if !fileManager.fileExists(atPath: payload.path) {
            let entries: [URL] = (try? fileManager.contentsOfDirectory(
                at: staging, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            if entries.count == 1 {
                payload = staging.appendingPathComponent(entries[0].lastPathComponent)
            } else {
                throw Failure.unreadable("it does not contain \(expectedName)")
            }
        }
        return payload
    }

    /// Whether an unpacker's message is the disk being full.
    static func saysTheDiskIsFull(_ message: String) -> Bool {
        return message.contains("No space left on device") || message.contains("ENOSPC")
    }

    // MARK: - Functions: what is said

    /// The file system's reason for a failed move, with no path from inside
    /// `courses/.internal/` in it (the plan review, M6): Foundation names
    /// both ends ("“section1” couldn’t be moved to “as-it-was”"), and a
    /// teacher must not be shown a staging folder or an id. The POSIX words
    /// when the error carries them; otherwise the message when it names no
    /// staging folder; otherwise a plain phrase.
    static func reasonWithoutStagingPaths(_ error: Error) -> String {
        if let code = posixCode(of: error) {
            return String(cString: strerror(code))
        }
        let said: String = error.localizedDescription
        if mentionsStaging(said) {
            return "a file could not be moved"
        }
        return said
    }

    /// Whether a sentence names a staging folder.
    static func mentionsStaging(_ text: String) -> Bool {
        let markers: [String] = [".internal", "restoring", asideName, newcomersName, "restore.json"]
        for marker in markers where text.contains(marker) {
            return true
        }
        return false
    }

    /// The POSIX error code inside an error, where there is one.
    static func posixCode(of error: Error) -> Int32? {
        let nsError: NSError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return Int32(nsError.code)
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return posixCode(of: underlying)
        }
        return nil
    }

    /// The course's top-level item a move was refused for, when it was
    /// refused for a lock or a permission (EPERM, EACCES, or Foundation's
    /// write-permission error), or nil.
    static func lockedItemName(_ stopped: SwapStopped, courseURL: URL, coursesDirectoryURL: URL) -> String? {
        let nsError: NSError = stopped.underlying as NSError
        var refused: Bool = nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError
        if let code = posixCode(of: stopped.underlying), code == EPERM || code == EACCES {
            refused = true
        }
        if !refused {
            return nil
        }
        let inTheCourse: URL = absolute(stopped.failed.out ? stopped.failed.from : stopped.failed.to, in: coursesDirectoryURL)
        let rest: String = relative(inTheCourse, to: courseURL)
        if let first = rest.split(separator: "/").first {
            return String(first)
        }
        return nil
    }

    /// Whether a folder itself refuses changes to what is in it: Locked in
    /// the Finder, or without write permission for this account. Measured
    /// by the implementation review (M-b): `chmod a-w` on the course gave
    /// `Permission denied`, `chflags uchg` `Operation not permitted`, both
    /// on the first move out, `course_config.json`.
    static func folderRefusesChanges(_ folder: URL) -> Bool {
        var status: stat = stat()
        if lstat(folder.path, &status) != 0 {
            return false
        }
        if status.st_flags & UInt32(UF_IMMUTABLE) != 0 {
            return true
        }
        return access(folder.path, W_OK) != 0
    }

    // MARK: - Functions: keeping what a stopped restore set aside

    /// Moves the set-aside copy (and any newcomers) to where a teacher can
    /// open it, `courses/_backups/<CODE>/<CODE> before a restore <stamp>`,
    /// then removes what is left of staging, which holds only the backup's
    /// copies by then (what was written into them is among the newcomers
    /// first, `keepWhatWasWrittenIntoTheBackupsItems`; when that could not
    /// all be moved, `mayRemoveWhatIsLeft` is false and nothing is removed).
    /// When that move fails, the staging folder stays with its `stopped`
    /// record, and its own path is what is said.
    static func keepTheSetAside(
        staging: URL,
        courseCode: String,
        coursesDirectoryURL: URL,
        context: Context,
        mayRemoveWhatIsLeft: Bool = true
    ) -> (path: String, holdsSomethingToOpen: Bool) {
        let aside: URL = staging.appendingPathComponent(asideName)
        let newcomers: URL = staging.appendingPathComponent(newcomersName)
        var keptAside: URL? = nil
        var everythingMoved: Bool = mayRemoveWhatIsLeft
        if itemExists(at: aside) {
            keptAside = moveToTheBackupsFolder(
                aside, courseCode: courseCode, name: stoppedRestoreName(courseCode),
                coursesDirectoryURL: coursesDirectoryURL, context: context
            )
            if keptAside == nil {
                everythingMoved = false
            }
        }
        if itemExists(at: newcomers) {
            if moveToTheBackupsFolder(
                newcomers, courseCode: courseCode, name: newcomersKeptName(courseCode),
                coursesDirectoryURL: coursesDirectoryURL, context: context
            ) == nil {
                everythingMoved = false
            }
        }
        if !mayRemoveWhatIsLeft, let keptAside {
            return (insideTheWorkingFolder(keptAside, coursesDirectoryURL: coursesDirectoryURL), holdsAnyFile(keptAside))
        }
        if everythingMoved {
            let said: URL = keptAside ?? aside
            // Anything kept is named, hidden folders included (the
            // implementation review's M-c: a stop that kept only `.internal`
            // with the timetable, or `.obsidian`, said where nothing was).
            let holds: Bool = keptAside != nil && holdsAnyFile(said)
            removeStaging(staging)
            return (insideTheWorkingFolder(said, coursesDirectoryURL: coursesDirectoryURL), holds)
        }
        return (insideTheWorkingFolder(staging, coursesDirectoryURL: coursesDirectoryURL), holdsAnyFile(staging))
    }

    /// Moves newcomers kept by a way back that otherwise worked to the
    /// backups folder. Returns where, as a path inside the working folder,
    /// or nil when there were none. When the move fails the staging folder
    /// is left (with them in it) and its path is returned.
    static func keepNewcomers(
        in staging: URL,
        courseCode: String,
        coursesDirectoryURL: URL,
        context: Context
    ) -> String? {
        let newcomers: URL = staging.appendingPathComponent(newcomersName)
        if !itemExists(at: newcomers) {
            return nil
        }
        if let kept = moveToTheBackupsFolder(
            newcomers, courseCode: courseCode, name: newcomersKeptName(courseCode),
            coursesDirectoryURL: coursesDirectoryURL, context: context
        ) {
            removeStaging(staging)
            return insideTheWorkingFolder(kept, coursesDirectoryURL: coursesDirectoryURL)
        }
        return insideTheWorkingFolder(newcomers, coursesDirectoryURL: coursesDirectoryURL)
    }

    /// Moves an item into `courses/_backups/<CODE>/` under a name with a
    /// stamp, never over anything there. Nil when it could not.
    /// `courseCode` nil puts it in `courses/_backups/` itself.
    static func moveToTheBackupsFolder(
        _ item: URL,
        courseCode: String?,
        name: String,
        coursesDirectoryURL: URL,
        context: Context
    ) -> URL? {
        return moveToTheBackupsFolder(
            item, courseCode: courseCode, name: name, coursesDirectoryURL: coursesDirectoryURL, stamp: context.stamp()
        )
    }

    /// The same, with the stamp given.
    static func moveToTheBackupsFolder(
        _ item: URL,
        courseCode: String?,
        name: String,
        coursesDirectoryURL: URL,
        stamp: String
    ) -> URL? {
        let fileManager: FileManager = FileManager.default
        guard let destination = unusedPlaceInTheBackupsFolder(
            courseCode: courseCode, name: name, coursesDirectoryURL: coursesDirectoryURL, stamp: stamp
        ) else {
            return nil
        }
        do {
            try fileManager.moveItem(at: item, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// A new, empty folder in `courses/_backups/<CODE>/` under a name with a
    /// stamp, or nil when it could not be made.
    static func newFolderInTheBackupsFolder(
        courseCode: String?,
        name: String,
        coursesDirectoryURL: URL,
        stamp: String
    ) -> URL? {
        guard let destination = unusedPlaceInTheBackupsFolder(
            courseCode: courseCode, name: name, coursesDirectoryURL: coursesDirectoryURL, stamp: stamp
        ) else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            return destination
        } catch {
            return nil
        }
    }

    /// A path in `courses/_backups/<CODE>/` (the folder made if missing)
    /// that nothing is at: `<name> <stamp>`, then ` (2)` and on.
    static func unusedPlaceInTheBackupsFolder(
        courseCode: String?,
        name: String,
        coursesDirectoryURL: URL,
        stamp: String
    ) -> URL? {
        var shelf: URL = coursesDirectoryURL.appendingPathComponent("_backups")
        if let courseCode {
            shelf = shelf.appendingPathComponent(courseCode)
        }
        do {
            try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let base: String = name + " " + stamp
        var destination: URL = shelf.appendingPathComponent(base)
        var attempt: Int = 2
        while itemExists(at: destination) && attempt < 100 {
            destination = shelf.appendingPathComponent(base + " (\(attempt))")
            attempt += 1
        }
        return destination
    }

    /// A path inside the working folder (the folder that holds `courses/`).
    static func insideTheWorkingFolder(_ url: URL, coursesDirectoryURL: URL) -> String {
        return relative(url, to: coursesDirectoryURL.deletingLastPathComponent())
    }

    /// Whether a folder holds any file at all, at any depth.
    static func holdsAnyFile(_ folder: URL) -> Bool {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return false
        }
        while let entry = walker.nextObject() as? URL {
            let isFolder: Bool = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isFolder {
                return true
            }
        }
        return false
    }
}
