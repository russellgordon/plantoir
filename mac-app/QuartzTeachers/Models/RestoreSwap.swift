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
    }

    /// What one restore did when it worked.
    struct Restored: Equatable {

        // MARK: - Stored properties

        let movesMade: Int

        /// True when the set-aside copy could not be removed (a locked file
        /// deep inside, say): the staging folder stays with its `done`
        /// record and the next reading removes it.
        let leftTidyingForLater: Bool
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

    // MARK: - Stored properties

    static let recordName: String = "restore.json"
    static let temporaryRecordName: String = ".restore.json.tmp"
    static let settlingPrefix: String = "restore.settling."
    static let settlerPrefix: String = "settler."
    static let settingsFileName: String = "course_config.json"
    static let unpackName: String = "backup"
    static let asideName: String = "as-it-was"
    static let newcomersName: String = "made while the restore was unfinished"

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
        let courseURL: URL = coursesDirectoryURL.appendingPathComponent(courseCode)
        let isAnArrival: Bool = !itemExists(at: courseURL)
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
        let unpacked: URL = staging.appendingPathComponent(unpackName)
        let payload: URL
        do {
            try writeRecord(record, in: staging, hooks: hooks)
            try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
            payload = try unpack(zipURL, named: courseCode, into: unpacked)
            try context.checkPayload(payload)
            try context.putMediaBack(unpacked, isAnArrival ? nil : courseURL)
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
            try writeRecord(record, in: staging, hooks: hooks)
        } catch {
            removeStaging(staging)
            throw error
        }

        context.justBeforeTheSwap()
        do {
            try swap(moves, coursesDirectoryURL: coursesDirectoryURL, hooks: hooks)
        } catch let stopped as SwapStopped {
            let back: WayBack = wayBack(
                moves,
                coursesDirectoryURL: coursesDirectoryURL,
                courseURL: courseURL,
                newcomersURL: staging.appendingPathComponent(newcomersName),
                hooks: hooks
            )
            if back.everyFileIsBack {
                let kept: String? = keepNewcomers(
                    in: staging, courseCode: courseCode, coursesDirectoryURL: coursesDirectoryURL, context: context
                )
                if kept == nil {
                    removeStaging(staging)
                }
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
                staging: staging, courseCode: courseCode, coursesDirectoryURL: coursesDirectoryURL, context: context
            )
            throw Failure.stoppedPartWay(keptAt: kept.path, holdsSomethingToOpen: kept.holdsSomethingToOpen)
        }

        record.phase = .done
        record.writtenAt = context.now()
        do {
            try writeRecord(record, in: staging, hooks: hooks)
        } catch {
            // Every move was made, so the restore has happened: a record that
            // could not say so is tidied by the reading that finds it, which
            // sees every original aside and every backup item in.
        }
        let tidied: Bool = finishAfterTheCommit(staging: staging, context: context, hooks: hooks)
        return Restored(movesMade: moves.count, leftTidyingForLater: !tidied)
    }

    /// What is left to do once the restore has happened, by the restore
    /// itself and by a settle that finds `done`: the app's own after-commit
    /// steps, Undo's seam, then the old copy and the staging folder removed.
    /// Returns false when something could not be removed; the `done` record
    /// stays with it and the next reading tries again.
    @discardableResult
    static func finishAfterTheCommit(staging: URL, context: Context, hooks: Hooks) -> Bool {
        context.afterCommit()
        let aside: URL = staging.appendingPathComponent(asideName)
        if itemExists(at: aside) {
            context.keepingWhatWasReplaced?(aside)
        }
        do {
            try hooks.step("remove the old copy")
        } catch {
            return false
        }
        var removed: Bool = true
        if itemExists(at: aside) {
            removed = removeUnlocking(aside)
        }
        if !removed {
            return false
        }
        do {
            try hooks.step("remove staging")
        } catch {
            return false
        }
        removeStaging(staging)
        return !itemExists(at: staging)
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
    /// copies by then. When that move fails, the staging folder stays with
    /// its `stopped` record, and its own path is what is said.
    static func keepTheSetAside(
        staging: URL,
        courseCode: String,
        coursesDirectoryURL: URL,
        context: Context
    ) -> (path: String, holdsSomethingToOpen: Bool) {
        let aside: URL = staging.appendingPathComponent(asideName)
        let newcomers: URL = staging.appendingPathComponent(newcomersName)
        var keptAside: URL? = nil
        var everythingMoved: Bool = true
        if itemExists(at: aside) {
            keptAside = moveToTheBackupsFolder(
                aside, courseCode: courseCode, name: "\(courseCode) before a restore",
                coursesDirectoryURL: coursesDirectoryURL, context: context
            )
            if keptAside == nil {
                everythingMoved = false
            }
        }
        if itemExists(at: newcomers) {
            if moveToTheBackupsFolder(
                newcomers, courseCode: courseCode, name: "\(courseCode) made while a restore was unfinished",
                coursesDirectoryURL: coursesDirectoryURL, context: context
            ) == nil {
                everythingMoved = false
            }
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
            newcomers, courseCode: courseCode, name: "\(courseCode) made while a restore was unfinished",
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
        var shelf: URL = coursesDirectoryURL.appendingPathComponent("_backups")
        if let courseCode {
            shelf = shelf.appendingPathComponent(courseCode)
        }
        do {
            try fileManager.createDirectory(at: shelf, withIntermediateDirectories: true)
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
        do {
            try fileManager.moveItem(at: item, to: destination)
            return destination
        } catch {
            return nil
        }
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
