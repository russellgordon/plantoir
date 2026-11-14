import Foundation

/// What the next reading of a working folder does with a restore that did
/// not finish (#909): the pure rule, then the pass over
/// `courses/.internal/restoring/` that applies it.
///
/// The rule is a function of facts alone, so `contracts/course-management
/// .json` → `backups.restoreWholeCourse.recoveryCases` runs it on both
/// platforms. Foundation only, like `RestoreSwap`, so the kill-point harness
/// compiles the same file.
nonisolated enum RestoreSettleRule {

    // MARK: - Types

    /// What a settle does with one staging folder.
    enum Action: String, Equatable, Sendable {
        /// Nothing: its owner is still at work, another settler holds it, or
        /// it is too young to judge.
        case leave
        /// Removed: it never held anything but an unpacked backup.
        case remove
        /// The way back over the recorded moves, then removed.
        case putBack
        /// The restore had happened: the steps after the commit, then
        /// removed.
        case finish
        /// Moved where a teacher can open it, never deleted.
        case keep
    }

    /// What the teacher is told about it, as a wording key, or nothing.
    enum Saying: String, Equatable, Sendable {
        case didNotFinish
        case stoppedPartWay
        case setAsideFilesKept
    }

    /// Everything the rule asks.
    struct Facts: Equatable, Sendable {

        // MARK: - Stored properties

        /// Whether the folder holds a record (`restore.json`, or one a
        /// settler claimed).
        var hasRecord: Bool

        /// The record's phase, when there is one.
        var phase: RestoreSwap.Phase?

        /// Whether the record's owner is still running (judged only for
        /// this computer's records).
        var ownerIsAlive: Bool

        /// Whether another settler's claim is held by a live process.
        var claimedByALiveSettler: Bool

        /// Whether the record was written on this computer.
        var writtenHere: Bool

        /// Seconds since the record was written, or since the folder was
        /// last changed when there is no record.
        var ageSeconds: Double

        /// For a folder with no record: whether it holds nothing but an
        /// unpacked backup (`backup/`) and a record's temporary file.
        var holdsOnlyAnUnpack: Bool

        /// For `swapping`: whether an original is at neither end of its move.
        var anOriginalIsAtNeitherEnd: Bool
    }

    // MARK: - Stored properties

    /// A folder with no record is judged only once it is a day old, so a
    /// staging folder an older build (or a section restore, which writes no
    /// record) is unpacking into right now is never taken.
    static let unrecordedWaitSeconds: Double = 86_400

    /// Another computer's record is left for fourteen days, 785a's wait for
    /// a second computer, and is then KEPT, never moved by (the plan review,
    /// M1): a sync client delivers renames out of order, so a way back
    /// computed from what has arrived is a guess.
    static let anotherComputersWaitSeconds: Double = 14 * 86_400

    // MARK: - Functions

    /// The decision, in order: a live settler's claim; no record (the
    /// review's H3: a folder that holds more than an unpack may hold the
    /// only copy of a section); another computer's record (M1); a live
    /// owner; then the phase.
    static func decide(_ facts: Facts) -> (action: Action, says: Saying?) {
        if facts.claimedByALiveSettler {
            return (.leave, nil)
        }
        if !facts.hasRecord {
            if facts.ageSeconds < unrecordedWaitSeconds {
                return (.leave, nil)
            }
            if facts.holdsOnlyAnUnpack {
                return (.remove, nil)
            }
            return (.keep, .setAsideFilesKept)
        }
        if !facts.writtenHere {
            if facts.ageSeconds < anotherComputersWaitSeconds {
                return (.leave, nil)
            }
            if facts.phase == .swapping {
                return (.keep, .stoppedPartWay)
            }
            return (.keep, nil)
        }
        if facts.ownerIsAlive {
            return (.leave, nil)
        }
        switch facts.phase {
        case .unpacking:
            return (.remove, nil)
        case .swapping:
            if facts.anOriginalIsAtNeitherEnd {
                return (.keep, .stoppedPartWay)
            }
            return (.putBack, .didNotFinish)
        case .done:
            return (.finish, nil)
        case .stopped:
            // Already said when it stopped; only its files are moved.
            return (.keep, nil)
        case nil:
            return (.keep, .setAsideFilesKept)
        }
    }
}

/// The pass over `courses/.internal/restoring/` at a folder's reading.
nonisolated enum RestoreSettle {

    // MARK: - Types

    /// What the pass needs from the app.
    struct Context {

        // MARK: - Stored properties

        let computer: String

        /// This process's lease body, written as its claim.
        let owner: String

        let processID: Int32

        /// Whether the process a lease body names is still the one that
        /// wrote it (`ProcessLiveness.ownerIsAlive`).
        let ownerIsAlive: (String) -> Bool

        let now: Date

        let stamp: () -> String

        /// The after-commit steps for a course (`RestoreSwap.Context
        /// .afterCommit`), for a settle that finds `done`.
        let afterCommit: (String) -> Void

        /// Run once a settle has moved a course's files back (put back as
        /// it was, or stopped part way): lock it again when it is kept for
        /// reference, as a live restore that fails does (the implementation
        /// review's I3: a crash mid-swap left a reference course put back
        /// with its pages unlocked, because `justBeforeTheSwap` had unlocked
        /// them). Asked of the settings as they are, so a course left
        /// without them is not touched.
        let afterPuttingBack: (String) -> Void

        let hooks: RestoreSwap.Hooks
    }

    /// What was done with one staging folder.
    struct Settled: Equatable {

        // MARK: - Stored properties

        /// The course its record names, or nil for a folder with no record.
        let course: String?

        /// The backup's file name, from the record.
        let backup: String?

        /// Where that zip came from (`RestoreSwap.Source`), from the record;
        /// nil for a folder with no record.
        let from: RestoreSwap.Source?

        /// What was found: a phase, or "an unrecorded folder".
        let found: String

        let action: RestoreSettleRule.Action

        /// What the teacher is told, when anything.
        let says: RestoreSettleRule.Saying?

        /// Where its files were kept, as a path inside the working folder,
        /// for `keep` (and a blocked `putBack`).
        let keptAt: String?

        /// Whether a teacher would find a page there.
        let holdsSomethingToOpen: Bool

        /// Where newcomers met by the way back were kept, when any were.
        let newcomersKeptAt: String?
    }

    // MARK: - Functions

    /// Settles every staging folder, or only those whose record names
    /// `onlyCourse` (Undo's U5 calls it per course before its own recovery,
    /// the plan review, M8). Each acts only under a claim: `restore.json`
    /// renamed to `restore.settling.<pid>.json`, one rename winning, with
    /// the settler's lease body beside it so a settler that dies is judged
    /// itself (the review's H2: two settlers at once told a false mix three
    /// times in four).
    static func settle(
        coursesDirectoryURL: URL,
        onlyCourse: String? = nil,
        context: Context
    ) -> [Settled] {
        let fileManager: FileManager = FileManager.default
        let restoring: URL = RestoreSwap.restoringFolder(coursesDirectoryURL)
        guard let names = try? fileManager.contentsOfDirectory(atPath: restoring.path) else {
            return []
        }
        var settled: [Settled] = []
        for listed in names.sorted() {
            var name: String = listed
            if let original = folderNameBackFromADeadClaim(listed, in: restoring) {
                name = original
            } else if listed.hasPrefix(".") {
                continue
            }
            let staging: URL = restoring.appendingPathComponent(name)
            var isFolder: ObjCBool = false
            if !fileManager.fileExists(atPath: staging.path, isDirectory: &isFolder) || !isFolder.boolValue {
                continue
            }
            if let outcome = settleOne(
                staging, coursesDirectoryURL: coursesDirectoryURL, onlyCourse: onlyCourse, context: context
            ) {
                settled.append(outcome)
            }
        }
        // `restoring` and `.internal` go when they are left empty.
        if rmdir(restoring.path) == 0 {
            _ = rmdir(restoring.deletingLastPathComponent().path)
        }
        return settled
    }

    /// What kind of unsettled record a course has, for the refusals.
    enum Unsettled: String, Equatable, Sendable {
        /// Its owner is at work, another settler holds it, or another
        /// computer wrote it: `anotherRestoreUnderWay`.
        case underWay
        /// Written on this computer by a process that is gone, or by this
        /// very process, and not settled: a stop whose set-aside copy could
        /// not be moved to the backups folder. Nothing is restoring it, so
        /// "being restored somewhere else" would be untrue (the
        /// implementation review's M-d): `anEarlierRestoreDidNotFinish`.
        case leftOver
    }

    /// Whether a course has a restore that has not settled: a record for it
    /// that the pass left alone (its owner is at work, another settler holds
    /// it, or another computer wrote it). A new restore of that course is
    /// refused (`anotherRestoreUnderWay`).
    static func unsettledRecordExists(forCourse courseCode: String, coursesDirectoryURL: URL) -> Bool {
        let anyComputer: String = ""
        return unsettledRecord(
            forCourse: courseCode, coursesDirectoryURL: coursesDirectoryURL, otherThan: nil,
            computer: anyComputer, owner: anyComputer,
            ownerIsAlive: { (_: String) -> Bool in
                return true
            }
        ) != nil
    }

    /// The unsettled record a course has, other than the one in `ownStaging`
    /// (a restore asking about itself, which wrote its own record before it
    /// asks: the implementation review's W1), or nil.
    static func unsettledRecord(
        forCourse courseCode: String,
        coursesDirectoryURL: URL,
        otherThan ownStaging: URL?,
        computer: String,
        owner: String,
        ownerIsAlive: (String) -> Bool
    ) -> Unsettled? {
        let fileManager: FileManager = FileManager.default
        let restoring: URL = RestoreSwap.restoringFolder(coursesDirectoryURL)
        guard let names = try? fileManager.contentsOfDirectory(atPath: restoring.path) else {
            return nil
        }
        var found: Unsettled? = nil
        for name in names.sorted() where !name.hasPrefix(".") {
            if let ownStaging, name == ownStaging.lastPathComponent {
                continue
            }
            let staging: URL = restoring.appendingPathComponent(name)
            guard let file = recordFile(in: staging), let record = RestoreSwap.readRecord(at: file.url),
                  record.course.caseInsensitiveCompare(courseCode) == .orderedSame else {
                continue
            }
            var settlerIsAlive: Bool = false
            if let claimedBy = file.claimedBy {
                let settler: URL = staging.appendingPathComponent(RestoreSwap.settlerPrefix + String(claimedBy))
                if let body = try? String(contentsOf: settler, encoding: .utf8), body != owner {
                    settlerIsAlive = ownerIsAlive(body)
                }
            }
            let writtenHere: Bool = !computer.isEmpty && record.computer == computer
            let ownerIsGoneOrThisProcess: Bool = record.owner == owner || !ownerIsAlive(record.owner)
            if writtenHere && ownerIsGoneOrThisProcess && !settlerIsAlive {
                if found == nil {
                    found = .leftOver
                }
                continue
            }
            return .underWay
        }
        return found
    }

    /// The restores another computer wrote that this one leaves alone (the
    /// plan review's M1) while the course they name has no settings here,
    /// so it is missing from the sidebar: each as a `Settled` whose action
    /// is `leave`, keyed by its staging folder's name. Older than
    /// `anotherComputersWaitSeconds` they are kept by `settle` instead, so
    /// they are not listed. The implementation review's I2: without a
    /// sentence the course vanished for up to two weeks with nothing said.
    static func unfinishedOnAnotherComputer(
        coursesDirectoryURL: URL,
        computer: String,
        now: Date
    ) -> [(staging: String, outcome: Settled)] {
        let fileManager: FileManager = FileManager.default
        let restoring: URL = RestoreSwap.restoringFolder(coursesDirectoryURL)
        guard let names = try? fileManager.contentsOfDirectory(atPath: restoring.path) else {
            return []
        }
        var found: [(staging: String, outcome: Settled)] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let staging: URL = restoring.appendingPathComponent(name)
            guard let file = recordFile(in: staging), let record = RestoreSwap.readRecord(at: file.url),
                  record.computer != computer else {
                continue
            }
            var ageSeconds: Double = age(ofFolder: staging, now: now)
            if let written = parsedMoment(record.writtenAt) {
                ageSeconds = now.timeIntervalSince(written)
            }
            if ageSeconds >= RestoreSettleRule.anotherComputersWaitSeconds {
                continue
            }
            let settings: URL = coursesDirectoryURL
                .appendingPathComponent(record.course)
                .appendingPathComponent(RestoreSwap.settingsFileName)
            if RestoreSwap.itemExists(at: settings) {
                continue
            }
            let outcome: Settled = Settled(
                course: record.course, backup: record.backup, from: source(of: record), found: record.phase.rawValue,
                action: .leave, says: nil, keptAt: nil, holdsSomethingToOpen: false, newcomersKeptAt: nil
            )
            found.append((staging: name, outcome: outcome))
        }
        return found
    }

    /// The record file in a staging folder, and who has claimed it.
    static func recordFile(in staging: URL) -> (url: URL, claimedBy: Int32?)? {
        let plain: URL = staging.appendingPathComponent(RestoreSwap.recordName)
        if RestoreSwap.itemExists(at: plain) {
            return (plain, nil)
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: staging.path) else {
            return nil
        }
        for name in names.sorted() where name.hasPrefix(RestoreSwap.settlingPrefix) && name.hasSuffix(".json") {
            let middle: String = String(name.dropFirst(RestoreSwap.settlingPrefix.count).dropLast(".json".count))
            if let pid = Int32(middle) {
                return (staging.appendingPathComponent(name), pid)
            }
        }
        return nil
    }

    /// The facts the rule asks, read from one staging folder.
    static func facts(
        of staging: URL,
        record: RestoreSwap.Record?,
        claimedBy: Int32?,
        coursesDirectoryURL: URL,
        context: Context
    ) -> RestoreSettleRule.Facts {
        var facts: RestoreSettleRule.Facts = RestoreSettleRule.Facts(
            hasRecord: record != nil,
            phase: record?.phase,
            ownerIsAlive: false,
            claimedByALiveSettler: false,
            writtenHere: true,
            ageSeconds: 0,
            holdsOnlyAnUnpack: false,
            anOriginalIsAtNeitherEnd: false
        )
        if let claimedBy, claimedBy != context.processID {
            let settler: URL = staging.appendingPathComponent(RestoreSwap.settlerPrefix + String(claimedBy))
            if let body = try? String(contentsOf: settler, encoding: .utf8) {
                facts.claimedByALiveSettler = context.ownerIsAlive(body)
            }
        }
        guard let record else {
            facts.ageSeconds = age(ofFolder: staging, now: context.now)
            facts.holdsOnlyAnUnpack = holdsOnlyAnUnpack(staging)
            return facts
        }
        facts.writtenHere = record.computer == context.computer
        if facts.writtenHere {
            facts.ownerIsAlive = context.ownerIsAlive(record.owner)
        }
        if let written = parsedMoment(record.writtenAt) {
            facts.ageSeconds = context.now.timeIntervalSince(written)
        } else {
            facts.ageSeconds = age(ofFolder: staging, now: context.now)
        }
        if record.phase == .swapping {
            facts.anOriginalIsAtNeitherEnd = RestoreSwap.anOriginalIsAtNeitherEnd(
                record.moves, coursesDirectoryURL: coursesDirectoryURL
            )
        }
        return facts
    }

    /// Settles one staging folder, or returns nil when it is left alone.
    static func settleOne(
        _ staging: URL,
        coursesDirectoryURL: URL,
        onlyCourse: String?,
        context: Context
    ) -> Settled? {
        let found: (url: URL, claimedBy: Int32?)? = recordFile(in: staging)
        var record: RestoreSwap.Record? = nil
        if let found {
            record = RestoreSwap.readRecord(at: found.url)
        }
        if let onlyCourse {
            guard let record, record.course.caseInsensitiveCompare(onlyCourse) == .orderedSame else {
                return nil
            }
        }
        if found != nil && record == nil {
            // A record that does not read is left alone: what it describes
            // cannot be known, and nothing it guards is deleted.
            return nil
        }
        let before: RestoreSettleRule.Facts = facts(
            of: staging, record: record, claimedBy: found?.claimedBy,
            coursesDirectoryURL: coursesDirectoryURL, context: context
        )
        if RestoreSettleRule.decide(before).action == .leave {
            return nil
        }

        // The claim: the settler's body first, then one rename that only one
        // process can win. A folder with no record is claimed by renaming the
        // folder itself into a name of this process's own.
        var claimed: URL = staging
        var claimedRecord: URL? = nil
        if let found {
            let settlerFile: URL = staging.appendingPathComponent(RestoreSwap.settlerPrefix + String(context.processID))
            try? Data(context.owner.utf8).write(to: settlerFile)
            let mine: URL = staging.appendingPathComponent(
                RestoreSwap.settlingPrefix + String(context.processID) + ".json"
            )
            if found.url.standardizedFileURL.path != mine.standardizedFileURL.path {
                if rename(found.url.path, mine.path) != 0 {
                    try? FileManager.default.removeItem(at: settlerFile)
                    return nil
                }
            }
            claimedRecord = mine
            // Read again under the claim: it is the record that is acted on.
            record = RestoreSwap.readRecord(at: mine)
        } else {
            let mine: URL = staging.deletingLastPathComponent()
                .appendingPathComponent(".settling-" + String(context.processID) + "-" + staging.lastPathComponent)
            if rename(staging.path, mine.path) != 0 {
                return nil
            }
            claimed = mine
        }
        // Asked again of the record as it is under the claim. A folder with
        // no record keeps the facts read before: renaming it to claim it can
        // change its modification date, and its age is what was judged.
        var facts: RestoreSettleRule.Facts = before
        if record != nil {
            facts = self.facts(
                of: claimed, record: record, claimedBy: nil,
                coursesDirectoryURL: coursesDirectoryURL, context: context
            )
        }
        let decided: (action: RestoreSettleRule.Action, says: RestoreSettleRule.Saying?) = RestoreSettleRule.decide(facts)
        let foundName: String = record?.phase.rawValue ?? "an unrecorded folder"
        let swapContext: RestoreSwap.Context = swapContext(for: record?.course ?? "", context: context)

        switch decided.action {
        case .leave:
            releaseClaim(claimed, claimedRecord: claimedRecord, original: staging, context: context)
            return nil
        case .remove:
            RestoreSwap.removeStaging(claimed)
            return Settled(
                course: record?.course, backup: record?.backup, from: source(of: record), found: foundName, action: .remove,
                says: nil, keptAt: nil, holdsSomethingToOpen: false, newcomersKeptAt: nil
            )
        case .finish:
            guard let record else {
                return nil
            }
            let tidied: Bool = RestoreSwap.finishAfterTheCommit(
                staging: claimed, context: swapContext, hooks: context.hooks
            )
            if !tidied {
                releaseClaim(claimed, claimedRecord: claimedRecord, original: staging, context: context)
            }
            return Settled(
                course: record.course, backup: record.backup, from: source(of: record), found: foundName, action: .finish,
                says: nil, keptAt: nil, holdsSomethingToOpen: false, newcomersKeptAt: nil
            )
        case .putBack:
            guard var record else {
                return nil
            }
            let courseURL: URL = coursesDirectoryURL.appendingPathComponent(record.course)
            let back: RestoreSwap.WayBack = RestoreSwap.wayBack(
                record.moves,
                coursesDirectoryURL: coursesDirectoryURL,
                courseURL: courseURL,
                newcomersURL: claimed.appendingPathComponent(RestoreSwap.newcomersName),
                hooks: context.hooks
            )
            context.afterPuttingBack(record.course)
            if back.everyFileIsBack {
                let newcomersAt: String? = RestoreSwap.keepNewcomers(
                    in: claimed, courseCode: record.course,
                    coursesDirectoryURL: coursesDirectoryURL, context: swapContext
                )
                if newcomersAt == nil {
                    RestoreSwap.removeStaging(claimed)
                }
                return Settled(
                    course: record.course, backup: record.backup, from: source(of: record), found: foundName, action: .putBack,
                    says: .didNotFinish, keptAt: nil, holdsSomethingToOpen: false, newcomersKeptAt: newcomersAt
                )
            }
            // Blocked: nothing is deleted while it holds an original.
            record.phase = .stopped
            record.writtenAt = RestoreSettle.momentText(context.now)
            if let claimedRecord {
                try? RestoreSwap.writeRecord(record, to: claimedRecord, flushes: context.hooks.flushes)
            }
            let kept: (path: String, holdsSomethingToOpen: Bool) = RestoreSwap.keepTheSetAside(
                staging: claimed, courseCode: record.course,
                coursesDirectoryURL: coursesDirectoryURL, context: swapContext
            )
            if RestoreSwap.itemExists(at: claimed) {
                releaseClaim(claimed, claimedRecord: claimedRecord, original: staging, context: context)
            }
            return Settled(
                course: record.course, backup: record.backup, from: source(of: record), found: foundName, action: .keep,
                says: .stoppedPartWay, keptAt: kept.path, holdsSomethingToOpen: kept.holdsSomethingToOpen,
                newcomersKeptAt: nil
            )
        case .keep:
            if let record, record.computer == context.computer {
                // This computer's own: the set-aside copy and any newcomers
                // go to the backups folder, as a live stop does.
                let kept: (path: String, holdsSomethingToOpen: Bool) = RestoreSwap.keepTheSetAside(
                    staging: claimed, courseCode: record.course,
                    coursesDirectoryURL: coursesDirectoryURL, context: swapContext
                )
                context.afterPuttingBack(record.course)
                if RestoreSwap.itemExists(at: claimed) {
                    releaseClaim(claimed, claimedRecord: claimedRecord, original: staging, context: context)
                }
                return Settled(
                    course: record.course, backup: record.backup, from: source(of: record), found: foundName, action: .keep,
                    says: decided.says, keptAt: kept.path, holdsSomethingToOpen: kept.holdsSomethingToOpen,
                    newcomersKeptAt: nil
                )
            }
            // Another computer's record, or no record: the whole folder, as
            // one item, nothing inside it moved.
            let courseCode: String? = record?.course ?? courseNamed(inUnrecorded: claimed)
            let name: String = record == nil ? "Files a restore set aside" : "\(courseCode ?? "A course") restore from another computer"
            if let claimedRecord {
                // Its record keeps its own name, so whoever reads the kept
                // folder sees what it was.
                _ = rename(claimedRecord.path, claimed.appendingPathComponent(RestoreSwap.recordName).path)
            }
            try? FileManager.default.removeItem(
                at: claimed.appendingPathComponent(RestoreSwap.settlerPrefix + String(context.processID))
            )
            guard let kept = RestoreSwap.moveToTheBackupsFolder(
                claimed, courseCode: courseCode, name: name,
                coursesDirectoryURL: coursesDirectoryURL, context: swapContext
            ) else {
                if claimed.standardizedFileURL.path != staging.standardizedFileURL.path {
                    _ = rename(claimed.path, staging.path)
                }
                return nil
            }
            return Settled(
                course: record?.course, backup: record?.backup, from: source(of: record), found: foundName, action: .keep,
                says: decided.says,
                keptAt: RestoreSwap.insideTheWorkingFolder(kept, coursesDirectoryURL: coursesDirectoryURL),
                holdsSomethingToOpen: RestoreSwap.holdsAnyFile(kept), newcomersKeptAt: nil
            )
        }
    }

    /// A folder with no record is claimed by renaming it to
    /// `.settling-<pid>-<name>`. When that process is gone, the folder is
    /// renamed back and its name returned, so a settler that died part way
    /// never leaves a teacher's files hidden for good. Nil for any other
    /// name, or a claim whose process is still running.
    static func folderNameBackFromADeadClaim(_ listed: String, in restoring: URL) -> String? {
        let prefix: String = ".settling-"
        guard listed.hasPrefix(prefix) else {
            return nil
        }
        let rest: Substring = listed.dropFirst(prefix.count)
        guard let dash = rest.firstIndex(of: "-"), let pid = Int32(rest[rest.startIndex..<dash]) else {
            return nil
        }
        let original: String = String(rest[rest.index(after: dash)...])
        if original.isEmpty {
            return nil
        }
        if kill(pid, 0) == 0 || errno == EPERM {
            return nil
        }
        if rename(restoring.appendingPathComponent(listed).path, restoring.appendingPathComponent(original).path) != 0 {
            return nil
        }
        return original
    }

    /// Gives a claim back, so the next reading can try again: the record
    /// renamed to `restore.json`, the settler's file removed, a claimed
    /// folder renamed back.
    static func releaseClaim(_ claimed: URL, claimedRecord: URL?, original: URL, context: Context) {
        if let claimedRecord, RestoreSwap.itemExists(at: claimedRecord) {
            _ = rename(claimedRecord.path, claimed.appendingPathComponent(RestoreSwap.recordName).path)
        }
        try? FileManager.default.removeItem(
            at: claimed.appendingPathComponent(RestoreSwap.settlerPrefix + String(context.processID))
        )
        if claimed.standardizedFileURL.path != original.standardizedFileURL.path {
            _ = rename(claimed.path, original.path)
        }
    }

    /// Where a record's zip came from, `backups` when it does not say;
    /// nil for a folder with no record.
    static func source(of record: RestoreSwap.Record?) -> RestoreSwap.Source? {
        guard let record else {
            return nil
        }
        return record.from ?? RestoreSwap.Source.backups
    }

    /// The restore engine's context for the pieces a settle reuses.
    static func swapContext(for courseCode: String, context: Context) -> RestoreSwap.Context {
        return RestoreSwap.Context(
            computer: context.computer,
            owner: context.owner,
            now: { () -> String in
                return RestoreSettle.momentText(Date())
            },
            stamp: context.stamp,
            keptInPlace: [],
            archiveURL: nil,
            checkPayload: { (_: URL) throws in
            },
            putMediaBack: { (_: URL, _: URL?) throws in
            },
            refuseUnlessMediaWasPutBack: { (_: URL) throws in
            },
            beforeTheSwap: { (_: URL) throws in
            },
            justBeforeTheSwap: { () in
            },
            afterCommit: { () in
                context.afterCommit(courseCode)
            },
            keepingWhatWasReplaced: nil
        )
    }

    /// The course a record-less folder was unpacking, where it says: the
    /// one folder under `backup/` (the menu's section restore), or the one
    /// course-looking folder at its top (the assistant window's).
    static func courseNamed(inUnrecorded staging: URL) -> String? {
        let fileManager: FileManager = FileManager.default
        let unpacked: URL = staging.appendingPathComponent(RestoreSwap.unpackName)
        for folder in [unpacked, staging] {
            guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
                continue
            }
            for name in names.sorted() where !name.hasPrefix(".") {
                let settings: URL = folder.appendingPathComponent(name).appendingPathComponent(RestoreSwap.settingsFileName)
                if RestoreSwap.itemExists(at: settings) {
                    return name
                }
            }
        }
        return nil
    }

    /// Whether a folder holds nothing but an unpacked backup and a record's
    /// temporary file (the review's H3).
    static func holdsOnlyAnUnpack(_ staging: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: staging.path) else {
            return false
        }
        for name in names where name != RestoreSwap.unpackName && name != RestoreSwap.temporaryRecordName {
            return false
        }
        return true
    }

    /// Seconds since a folder last changed.
    static func age(ofFolder url: URL, now: Date) -> Double {
        let values: URLResourceValues? = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let changed = values?.contentModificationDate else {
            return 0
        }
        return now.timeIntervalSince(changed)
    }

    /// A record's moment as written (ISO 8601, with or without fractions).
    static func parsedMoment(_ text: String) -> Date? {
        let withFractions: ISO8601DateFormatter = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let moment = withFractions.date(from: text) {
            return moment
        }
        let plain: ISO8601DateFormatter = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    /// A moment as a record writes it.
    static func momentText(_ moment: Date) -> String {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: moment)
    }
}
