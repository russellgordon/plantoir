import Foundation

/// Which files the shared Media store may delete (#785): the rule that loses
/// a teacher's pictures if it is wrong, so it is written here with nothing
/// asked of the disk, and run against the contract's cases on both
/// platforms (`contracts/course-management.json` →
/// `backups.sharedMedia.sweepCases`).
///
/// `SharedMediaStore.sweep` gathers what is on disk into `Inputs`, asks
/// `decide`, and carries the answer out.
///
/// **The rule, in the order it is applied:**
///
/// 1. **Anything unreadable stops the whole sweep.** A small backup whose
///    list cannot be read, or a list of a kind or format this version does
///    not know, might name any file in the store, so nothing is deleted and
///    the reason is written on the trail.
/// 2. **What is still needed** is every checksum named by: a small backup
///    that is there; a backup's list whose zip is NOT there yet but that was
///    written less than a day ago; a step on the Undo list written less than
///    61 days ago (#899, by any computer); a backup being written, for a day
///    or while its process still runs on this computer; and a FINISHED
///    backup's pending list, for a day after it finished. Every age is a
///    moment a list wrote down, never a file's date. A pending list and a
///    list whose zip is not here that ANOTHER computer wrote count their day
///    from the LATER of that moment and when this computer first saw them,
///    so a computer whose clock runs behind, or a list that syncs late,
///    still gets its day here. A
///    moment more than a
///    day ahead of this computer's clock is counted from when this computer
///    first saw the list instead, so a wrong clock cannot pin files for
///    years.
/// 3. **Nothing is deleted the first time it is found unneeded.** This
///    computer writes down when it first found each file unneeded, and
///    deletes it only when a sweep a day or more later still finds it so;
///    FOURTEEN days once a second computer has written to the store, since
///    a file another computer has just started to rely on looks unneeded
///    here until that computer's lists arrive (#785 implementation review,
///    W3). No wait closes that race against a sync delay of any length: a
///    restore that then misses a picture names it, and never skips it.
/// 4. A file whose name is neither a checksum nor an unfinished copy (a sync
///    service's "abc… 2") is never touched.
/// 5. What a crash leaves that names nothing (an unpublished
///    `.writing-….zip`, an `.incoming-…` folder, a temporary list) goes once
///    its own date is more than a day old: it is no backup and no list, so
///    its date is the only thing to go by, and nothing writes for a day.
nonisolated enum SharedMediaSweepRule {

    // MARK: - Types

    /// One entry of `files/`, by its path under that folder (`ab/ab12…`).
    struct StoreEntry: Equatable, Sendable {

        // MARK: - Stored properties

        let relativePath: String

        /// The checksum its name spells, or nil for anything else.
        let checksum: String?

        /// An unfinished copy (`.incoming-…`), left by a write that stopped.
        let isUnfinishedCopy: Bool
    }

    /// A small backup zip that is in `_backups/<CODE>/`, with the checksums
    /// its list names, or nil when its list could not be read.
    struct BackupSeen: Equatable, Sendable {

        // MARK: - Stored properties

        let name: String
        let checksums: Set<String>?

        /// The computer its list says wrote it.
        var host: String? = nil
    }

    /// A copy in `lists/` of a backup's list whose zip is not in the
    /// working folder.
    struct ListWithoutItsZip: Equatable, Sendable {

        // MARK: - Stored properties

        let fileName: String
        let writtenAt: Date
        let checksums: Set<String>
        var host: String? = nil
    }

    /// A pending or Undo list, and for a pending one whether the process
    /// that wrote it is still running on this computer.
    struct HoldSeen: Equatable, Sendable {

        // MARK: - Stored properties

        let fileName: String
        let hold: SharedMediaHold
        let writerIsRunningHere: Bool
    }

    /// Something a crash left that names nothing: an unpublished zip, an
    /// unfinished list folder, a temporary list. By its path from the
    /// working folder's `courses` folder, with its own modification date.
    struct Leftover: Equatable, Sendable {

        // MARK: - Stored properties

        let path: String
        let modified: Date
    }

    struct Inputs: Equatable, Sendable {

        // MARK: - Stored properties

        let storeEntries: [StoreEntry]
        let backups: [BackupSeen]
        let listsWithoutTheirZips: [ListWithoutItsZip]
        let holds: [HoldSeen]

        /// Files in `lists/` or `pending/` that could not be read at all.
        let unreadableListFiles: [String]

        /// This computer's own record of when it first found each entry
        /// unneeded, by `relativePath`.
        let unneededSince: [String: Date]

        let now: Date
        let thisComputer: String

        /// This computer's record that another computer has written to the
        /// store, kept once found.
        var sharedWithAnotherComputer: Bool = false

        /// Another computer's sweep record is in the store.
        var anotherComputersSweepRecordIsThere: Bool = false

        /// When this computer first saw each list, by file name: every
        /// pending list and backup's list whose zip is not here that another
        /// computer wrote, and any list whose moment is more than a day ahead
        /// of this computer's clock.
        var listsFirstSeen: [String: Date] = [:]

        var leftovers: [Leftover] = []
    }

    /// Why a sweep kept everything.
    enum KeptEverything: Equatable, Sendable {
        case aBackupCouldNotBeRead(String)
        case aListCouldNotBeRead(String)
        case theStoreIsBusy
        case theStoreCouldNotBeRead(String)
    }

    struct Decision: Equatable, Sendable {

        // MARK: - Stored properties

        /// Set when nothing at all is deleted or rewritten.
        let keptEverything: KeptEverything?

        /// `files/` entries to delete, by relative path.
        let entriesToDelete: [String]

        /// Lists in `lists/` and `pending/` that protect nothing any more,
        /// removed AFTER the files.
        let listFilesToRemove: [String]

        /// The record to write back for this computer.
        let unneededSince: [String: Date]

        var sharedWithAnotherComputer: Bool = false
        var listsFirstSeen: [String: Date] = [:]
        var leftoversToRemove: [String] = []
    }

    // MARK: - Stored properties

    /// How long a pending list, a finished backup's pending list, and a
    /// backup's list whose zip is not here, are honoured: a day.
    static let pendingHonouredFor: TimeInterval = 24 * 60 * 60

    /// How long a step on the Undo list keeps its pictures (#899 plan 4.5):
    /// 61 days by the list's own written moment, one more than the 60 days
    /// the journal keeps a step on the disk (30 offered, and a grace of 30
    /// so a clock set wrong never destroys the list: `undo.rule.limits`).
    /// It was 31, which covered what is offered but not that grace: a step
    /// offered again once a wrong clock was put right would have lost its
    /// pictures (the core review of #899 U1's second round; the director's
    /// ruling 11 on its third).
    static let undoHonouredFor: TimeInterval = 61 * 24 * 60 * 60

    /// How long a file must have been found unneeded, by this computer,
    /// before it is deleted, when only this computer writes to the store.
    static let unneededFor: TimeInterval = 24 * 60 * 60

    /// The same once another computer has written to the store: fourteen
    /// days. It covers up to fourteen days between this computer first
    /// finding a file unneeded and another computer's lists naming it
    /// arriving here; the wait runs from that first finding, not from the
    /// other computer's backup. The cost is only that space comes back two
    /// weeks after a backup is deleted on a shared folder.
    static let unneededForWhenShared: TimeInterval = 14 * 24 * 60 * 60

    /// How far ahead of this computer's clock a written moment may be
    /// before it is counted from when this computer first saw it.
    static let futureAllowed: TimeInterval = 24 * 60 * 60

    /// How old a crash's leftover must be, by its own date, before it goes.
    static let leftoverAge: TimeInterval = 24 * 60 * 60

    // MARK: - Functions

    static func decide(_ inputs: Inputs) -> Decision {
        for backup in inputs.backups {
            if backup.checksums == nil {
                return keepingEverything(.aBackupCouldNotBeRead(backup.name), inputs)
            }
        }
        if let first = inputs.unreadableListFiles.first {
            return keepingEverything(.aListCouldNotBeRead(first), inputs)
        }

        var shared: Bool = inputs.sharedWithAnotherComputer || inputs.anotherComputersSweepRecordIsThere
        var firstSeen: [String: Date] = [:]
        var needed: Set<String> = []
        var listFilesToRemove: [String] = []

        for backup in inputs.backups {
            if let checksums = backup.checksums {
                needed.formUnion(checksums)
            }
            if let host = backup.host, host != inputs.thisComputer {
                shared = true
            }
        }
        for list in inputs.listsWithoutTheirZips {
            if let host = list.host, host != inputs.thisComputer {
                shared = true
            }
            let written: Date = honouredFrom(list.writtenAt, by: list.host, of: list.fileName, inputs, &firstSeen)
            if isYounger(than: pendingHonouredFor, writtenAt: written, now: inputs.now) {
                needed.formUnion(list.checksums)
            } else {
                listFilesToRemove.append(list.fileName)
            }
        }
        for seen in inputs.holds {
            if seen.hold.host != inputs.thisComputer {
                shared = true
            }
            if holdIsHonoured(seen, inputs, &firstSeen) {
                needed.formUnion(seen.hold.checksums)
            } else {
                listFilesToRemove.append(seen.fileName)
            }
        }

        let wait: TimeInterval = shared ? unneededForWhenShared : unneededFor
        var entriesToDelete: [String] = []
        var unneededSince: [String: Date] = [:]
        for entry in inputs.storeEntries {
            if let checksum = entry.checksum, needed.contains(checksum) {
                continue
            }
            if entry.checksum == nil && !entry.isUnfinishedCopy {
                continue
            }
            guard let firstFound = inputs.unneededSince[entry.relativePath] else {
                unneededSince[entry.relativePath] = inputs.now
                continue
            }
            // A moment in this computer's future is a clock that was wrong
            // when it was written: start again from now, which only ever
            // keeps a file longer.
            if firstFound > inputs.now {
                unneededSince[entry.relativePath] = inputs.now
                continue
            }
            if inputs.now.timeIntervalSince(firstFound) >= wait {
                entriesToDelete.append(entry.relativePath)
            } else {
                unneededSince[entry.relativePath] = firstFound
            }
        }

        var leftoversToRemove: [String] = []
        for leftover in inputs.leftovers {
            if inputs.now.timeIntervalSince(leftover.modified) > leftoverAge {
                leftoversToRemove.append(leftover.path)
            }
        }

        entriesToDelete.sort()
        listFilesToRemove.sort()
        leftoversToRemove.sort()
        return Decision(
            keptEverything: nil,
            entriesToDelete: entriesToDelete,
            listFilesToRemove: listFilesToRemove,
            unneededSince: unneededSince,
            sharedWithAnotherComputer: shared,
            listsFirstSeen: firstSeen,
            leftoversToRemove: leftoversToRemove
        )
    }

    /// The moment a list's age is counted from: its own written moment, or,
    /// when that is more than a day ahead of this computer's clock, the
    /// moment this computer first saw it (recorded in `firstSeen`).
    static func moment(
        _ written: Date,
        of fileName: String,
        _ inputs: Inputs,
        _ firstSeen: inout [String: Date]
    ) -> Date {
        if written.timeIntervalSince(inputs.now) <= futureAllowed {
            return written
        }
        let seen: Date = inputs.listsFirstSeen[fileName] ?? inputs.now
        firstSeen[fileName] = seen
        return seen
    }

    /// A pending list being written is honoured for a day from its own
    /// written moment (from the later of that and when this computer first
    /// saw it, when another computer wrote it: `honouredFrom`), and after
    /// that while the process that wrote it still runs on this computer (a
    /// process id means nothing on another computer). A FINISHED backup's
    /// pending list is honoured for a day after it finished (counted the
    /// same way), whatever runs. An Undo list is honoured for 61
    /// days, whoever wrote it.
    static func holdIsHonoured(_ seen: HoldSeen, _ inputs: Inputs, _ firstSeen: inout [String: Date]) -> Bool {
        switch seen.hold.kind {
        case .undo:
            let written: Date = moment(seen.hold.writtenAt, of: seen.fileName, inputs, &firstSeen)
            return isYounger(than: undoHonouredFor, writtenAt: written, now: inputs.now)
        case .pending:
            if let finished = seen.hold.finishedAt {
                let finishedMoment: Date = honouredFrom(finished, by: seen.hold.host, of: seen.fileName, inputs, &firstSeen)
                return isYounger(than: pendingHonouredFor, writtenAt: finishedMoment, now: inputs.now)
            }
            let written: Date = honouredFrom(seen.hold.writtenAt, by: seen.hold.host, of: seen.fileName, inputs, &firstSeen)
            if isYounger(than: pendingHonouredFor, writtenAt: written, now: inputs.now) {
                return true
            }
            return seen.hold.host == inputs.thisComputer && seen.writerIsRunningHere
        }
    }

    /// The moment a pending list, or a backup's list whose zip is not here,
    /// is honoured from. For a list ANOTHER computer wrote (or one that does
    /// not say), the LATER of its own moment and when this computer first
    /// saw it, recorded in `firstSeen`: a computer whose clock runs behind
    /// writes moments that look old here, and so does a list that syncs
    /// late. Counted from its own moment alone, either was removed the
    /// first time it was seen, and a picture it named could go (#785 fix
    /// review, M-a, measured with a clock two days behind). A list this
    /// computer wrote was dated by this clock and did not travel, so its own
    /// moment is kept: counting it from first sight would hold a deleted
    /// backup's pictures a day longer for nothing. A moment more than a day
    /// ahead counts from first sight, as `moment` does.
    static func honouredFrom(
        _ written: Date,
        by host: String?,
        of fileName: String,
        _ inputs: Inputs,
        _ firstSeen: inout [String: Date]
    ) -> Date {
        if host == inputs.thisComputer {
            return moment(written, of: fileName, inputs, &firstSeen)
        }
        let seen: Date = inputs.listsFirstSeen[fileName] ?? inputs.now
        firstSeen[fileName] = seen
        if written.timeIntervalSince(inputs.now) > futureAllowed {
            return seen
        }
        if written > seen {
            return written
        }
        return seen
    }

    /// True when less than `limit` has passed since `writtenAt`, and for a
    /// moment in the future.
    static func isYounger(than limit: TimeInterval, writtenAt: Date, now: Date) -> Bool {
        return now.timeIntervalSince(writtenAt) < limit
    }

    /// Nothing deleted, nothing removed, and this computer's record left as
    /// it was, so a sweep that could not see everything changes nothing.
    static func keepingEverything(_ why: KeptEverything, _ inputs: Inputs) -> Decision {
        return Decision(
            keptEverything: why,
            entriesToDelete: [],
            listFilesToRemove: [],
            unneededSince: inputs.unneededSince,
            sharedWithAnotherComputer: inputs.sharedWithAnotherComputer,
            listsFirstSeen: inputs.listsFirstSeen,
            leftoversToRemove: []
        )
    }
}
