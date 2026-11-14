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
///    list cannot be read (a zip still in the cloud with no copy of its list
///    beside it, a damaged zip, a list in a format this version does not
///    know) might name any file in the store, so nothing is deleted and the
///    reason is written on the trail.
/// 2. **What is still needed** is every checksum named by: a small backup
///    that is there; a backup's list whose zip is NOT there yet but that was
///    written less than a day ago (another computer's backup whose list has
///    synced before its zip); a step on the Undo list written less than 31
///    days ago (#899, by any computer); and a backup being written, for a
///    day, or for as long as its process is still running on this computer.
///    Every age is measured from the moment the list itself WROTE DOWN,
///    never from a file's dates.
/// 3. **Nothing is deleted the first time it is found unneeded.** This
///    computer writes down when it first found each file unneeded, and
///    deletes it only when a sweep a day or more after that still finds it
///    unneeded. That one rule covers what file dates cannot: a picture
///    copied into the store today keeps the date it was taken in 2024, and
///    a file another computer has just started to rely on looks exactly
///    like one nobody needs until that computer's list arrives.
/// 4. A file whose name is neither a checksum nor an unfinished copy (a sync
///    service's "abc… 2") is never touched.
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
    }

    /// A copy in `lists/` of a backup's list whose zip is not in the
    /// working folder.
    struct ListWithoutItsZip: Equatable, Sendable {

        // MARK: - Stored properties

        let fileName: String
        let writtenAt: Date
        let checksums: Set<String>
    }

    /// A pending or Undo list, and for a pending one whether the process
    /// that wrote it is still running on this computer.
    struct HoldSeen: Equatable, Sendable {

        // MARK: - Stored properties

        let fileName: String
        let hold: SharedMediaHold
        let writerIsRunningHere: Bool
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
    }

    // MARK: - Stored properties

    /// How long a pending list, and a backup's list whose zip is not here,
    /// are honoured by their written moment: a day.
    static let pendingHonouredFor: TimeInterval = 24 * 60 * 60

    /// How long a step on the Undo list keeps its pictures (#899 plan 4.5):
    /// 31 days by the list's own written moment, one more than the Undo
    /// list's own limit of 30 days.
    static let undoHonouredFor: TimeInterval = 31 * 24 * 60 * 60

    /// How long a file must have been found unneeded, by this computer,
    /// before it is deleted.
    static let unneededFor: TimeInterval = 24 * 60 * 60

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

        var needed: Set<String> = []
        var listFilesToRemove: [String] = []

        for backup in inputs.backups {
            if let checksums = backup.checksums {
                needed.formUnion(checksums)
            }
        }
        for list in inputs.listsWithoutTheirZips {
            if isYounger(than: pendingHonouredFor, writtenAt: list.writtenAt, now: inputs.now) {
                needed.formUnion(list.checksums)
            } else {
                listFilesToRemove.append(list.fileName)
            }
        }
        for seen in inputs.holds {
            if holdIsHonoured(seen, inputs) {
                needed.formUnion(seen.hold.checksums)
            } else {
                listFilesToRemove.append(seen.fileName)
            }
        }

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
            if inputs.now.timeIntervalSince(firstFound) >= unneededFor {
                entriesToDelete.append(entry.relativePath)
            } else {
                unneededSince[entry.relativePath] = firstFound
            }
        }

        entriesToDelete.sort()
        listFilesToRemove.sort()
        return Decision(
            keptEverything: nil,
            entriesToDelete: entriesToDelete,
            listFilesToRemove: listFilesToRemove,
            unneededSince: unneededSince
        )
    }

    /// A pending list is honoured for a day by its own written moment, and
    /// after that while the process that wrote it still runs on this
    /// computer (a process id means nothing on another computer). An Undo
    /// list is honoured for 31 days, whoever wrote it.
    static func holdIsHonoured(_ seen: HoldSeen, _ inputs: Inputs) -> Bool {
        switch seen.hold.kind {
        case .undo:
            return isYounger(than: undoHonouredFor, writtenAt: seen.hold.writtenAt, now: inputs.now)
        case .pending:
            if isYounger(than: pendingHonouredFor, writtenAt: seen.hold.writtenAt, now: inputs.now) {
                return true
            }
            return seen.hold.host == inputs.thisComputer && seen.writerIsRunningHere
        }
    }

    /// True when less than `limit` has passed since `writtenAt`, and for a
    /// moment in the future, which is another computer's clock running
    /// ahead: kept, which only ever keeps a file longer.
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
            unneededSince: inputs.unneededSince
        )
    }
}
