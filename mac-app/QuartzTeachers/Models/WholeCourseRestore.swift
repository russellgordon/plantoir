import Foundation

/// The app's half of a whole-course restore (#909): the rules Russell holds
/// (each behind one named constant, so a ruling the other way is one line),
/// the refusals, the space check, and the settle at a folder's reading. The
/// engine itself, which moves files, is `RestoreSwap` and `RestoreSettle`.
enum WholeCourseRestore {

    // MARK: - Types

    /// Why a restore may not start, or may not go on to its swap. Each has
    /// its own sentence; the order is `refusal(_:)`'s.
    struct RefusalFacts: Equatable {

        // MARK: - Stored properties

        /// This app is previewing, deploying or copying the course.
        var busyHere: Bool = false

        /// The assistant whose outside session holds the course
        /// (`doorCourseHold`), as the busy sentences name it.
        var revisingAssistant: String? = nil

        /// A restore of this course has a record that has not settled, other
        /// than the asking restore's own (the implementation review's W1).
        var unsettledRestore: Bool = false

        /// This computer wrote a record for the course that nothing is
        /// restoring: a stop whose set-aside copy could not be moved
        /// (`RestoreSettle.Unsettled.leftOver`, the review's M-d).
        var earlierRestoreLeftOver: Bool = false

        /// Another program holds a build or publish lease on the course,
        /// taken before this restore's own (`workLeases.declining`).
        var buildingElsewhere: Bool = false
    }

    /// Which refusal applies, by its wording key.
    enum Refusal: String, Equatable {
        case busy
        case claudeIsRevisingTheCourseRestore
        case anotherRestoreUnderWay
        case anEarlierRestoreDidNotFinish
        case courseIsBeingBuiltElsewhere
    }

    /// Why a whole-course restore did not go ahead, as the trail line says
    /// it (`course restore left as it was`, the implementation review's I4):
    /// a fixed phrase, never page text.
    enum DidNotGoAhead: String, Equatable {
        case busy = "refused: the course is previewing or deploying here"
        case outsideSession = "refused: an outside assistant's session holds the course"
        case anotherRestore = "refused: another restore of the course has not finished"
        case earlierRestore = "refused: an earlier restore of the course on this computer did not finish"
        case buildingElsewhere = "refused: another program is building the course"
        case notEnoughSpace = "not enough free space on its disk"
        case ranOutOfSpace = "the disk filled while the backup was being opened"
        case unreadable = "the backup could not be read"
        case mediaNotPutBack = "a small backup whose Media files were not put back"
        case aMoveFailed = "a file could not be moved, and every file went back"
        case lockedAtTheTop = "an item at the top of the course is locked or cannot be changed"
        case courseFolderLocked = "the course folder is locked or cannot be changed"
        case otherProblem = "it could not finish"

        /// The trail's kind for a refusal.
        static func refused(_ refusal: Refusal) -> DidNotGoAhead {
            switch refusal {
            case .busy:
                return .busy
            case .claudeIsRevisingTheCourseRestore:
                return .outsideSession
            case .anotherRestoreUnderWay:
                return .anotherRestore
            case .anEarlierRestoreDidNotFinish:
                return .earlierRestore
            case .courseIsBeingBuiltElsewhere:
                return .buildingElsewhere
            }
        }
    }

    /// When a refusal was asked, as the trail line says it.
    enum AskedWhen: String, Equatable {
        case beforeTheArchive = "before the archive"
        case afterTheArchive = "after the archive"
        case beforeTheSwap = "once the backup was opened, before anything moved"
        /// Another restore of the course on this computer held it when this
        /// one began (`RestoreSwap.holdTheCourse`).
        case whenItBegan = "when the restore began, before the backup was opened"
    }

    // MARK: - Stored properties

    /// Russell's held question M12: a restore never touches what backups
    /// leave out (a `.git`, `build`, `node_modules`), because they are in
    /// neither the backup nor the archive made first, so a restore that
    /// removed them destroyed them for good (measured: `.git` gone after a
    /// clean restore, the plan's 1.2). False puts back today's behaviour.
    static let leavesWhatBackupsLeaveOut: Bool = true

    /// Russell's held question M13: a locked or read-only item at the top
    /// of the course means nothing changes, and the item is named. False
    /// clears Finder's Locked flag on the course's top-level items before
    /// the swap instead.
    static let aLockedItemAtTheTopChangesNothing: Bool = true

    /// Russell's held question M11: the teacher is told once after an
    /// interrupted restore was put right (`didNotFinish`). False leaves only
    /// the trail line.
    static let tellsTheTeacherOnceAfterPuttingRight: Bool = true

    /// For tests: the free space the check reads instead of the volume's.
    static var freeSpaceForTests: Int64? = nil

    // MARK: - Computed properties

    /// The top-level names a restore leaves where they are: every name a
    /// backup leaves out (`CourseArchiver.excludedFromArchives`) except the
    /// built site's link, which is derived and is thrown away with the old
    /// copy as before (the restore discards the built site anyway, and a
    /// legacy `.merged_output` FOLDER kept in place would be a stale site).
    static var keptInPlace: [String] {
        if !leavesWhatBackupsLeaveOut {
            return []
        }
        var names: [String] = []
        for name in CourseArchiver.excludedFromArchives where name != BuildOutputLocation.linkName {
            names.append(name)
        }
        return names
    }

    // MARK: - Functions: the refusals

    /// The refusal that applies, in order: this app's own work on the
    /// course, an outside session's hold, an unsettled restore, another
    /// program's build. Asked before the archive, after it, and immediately
    /// before the swap (the plan review, M3).
    static func refusal(_ facts: RefusalFacts) -> Refusal? {
        if facts.busyHere {
            return .busy
        }
        if facts.revisingAssistant != nil {
            return .claudeIsRevisingTheCourseRestore
        }
        if facts.unsettledRestore {
            return .anotherRestoreUnderWay
        }
        if facts.earlierRestoreLeftOver {
            return .anEarlierRestoreDidNotFinish
        }
        if facts.buildingElsewhere {
            return .courseIsBeingBuiltElsewhere
        }
        return nil
    }

    /// The sentence for a refusal.
    static func sentence(for refusal: Refusal, courseCode: String, assistant: String?) -> String {
        switch refusal {
        case .busy:
            return "\(courseCode) is previewing or deploying right now. Stop that first, then restore."
        case .claudeIsRevisingTheCourseRestore:
            return AssistWording.sessionIsRevisingTheCourse(course: courseCode, then: "restore", assistant: assistant ?? "")
        case .anotherRestoreUnderWay:
            return RestoreWholeCourseWording.anotherRestoreUnderWay(course: courseCode)
        case .anEarlierRestoreDidNotFinish:
            return RestoreWholeCourseWording.anEarlierRestoreDidNotFinish(course: courseCode)
        case .courseIsBeingBuiltElsewhere:
            return AssistWording.courseIsBeingBuiltElsewhere(course: courseCode)
        }
    }

    // MARK: - Functions: space

    /// How much more free space the restore needs on the course's own disk,
    /// or nil when there is room (the plan review, M2). Asked BEFORE the
    /// archive, which is written to the same disk and would otherwise eat
    /// what room there was: the archive (at most the course's size) plus
    /// the unpacked backup (its uncompressed size, read from the zip's
    /// directory, measured `real 0.00` for a 100 MB backup).
    static func spaceShortfall(courseURL: URL?, zipURL: URL, coursesDirectoryURL: URL) -> Int64? {
        guard let unpacked = uncompressedSize(ofZipAt: zipURL) else {
            // Unknown: the unpack's own check is the fallback.
            return nil
        }
        var courseBytes: Int64? = nil
        if let courseURL {
            courseBytes = sizeOfWhatAnArchiveHolds(courseURL)
        }
        guard let free = freeSpace(at: coursesDirectoryURL) else {
            return nil
        }
        return shortfall(courseBytes: courseBytes, unpackedBytes: unpacked, free: free)
    }

    /// The arithmetic, alone (`spaceCases`): the archive (at most the
    /// course's own bytes; none for an arrival) plus the unpacked backup,
    /// against the free space. Nil when there is room.
    nonisolated static func shortfall(courseBytes: Int64?, unpackedBytes: Int64, free: Int64) -> Int64? {
        let needed: Int64 = (courseBytes ?? 0) + unpackedBytes
        if free >= needed {
            return nil
        }
        return needed - free
    }

    /// The free space the system says important work may use, on the
    /// volume that holds this folder.
    static func freeSpace(at url: URL) -> Int64? {
        if let freeSpaceForTests {
            return freeSpaceForTests
        }
        let values: URLResourceValues? = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// A zip's uncompressed total from its central directory (`unzip -Zt`:
    /// "45 files, 104859157 bytes uncompressed, ..."), or nil.
    nonisolated static func uncompressedSize(ofZipAt zipURL: URL) -> Int64? {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Zt", zipURL.path]
        let output: Pipe = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data: Data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            return nil
        }
        return uncompressedSize(inSummary: String(data: data, encoding: .utf8) ?? "")
    }

    /// The number before " bytes uncompressed" in `unzip -Zt`'s line.
    nonisolated static func uncompressedSize(inSummary summary: String) -> Int64? {
        for part in summary.components(separatedBy: ",") {
            let trimmed: String = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix("bytes uncompressed") {
                let number: String = trimmed.replacingOccurrences(of: "bytes uncompressed", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return Int64(number)
            }
        }
        return nil
    }

    /// The bytes of every file an archive of the course would hold: links
    /// are not followed and the names backups leave out are skipped at any
    /// depth, as `CourseArchiver` zips.
    nonisolated static func sizeOfWhatAnArchiveHolds(_ courseURL: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: courseURL, includingPropertiesForKeys: keys, options: []) else {
            return 0
        }
        var total: Int64 = 0
        while let entry = walker.nextObject() as? URL {
            if CourseArchiver.excludedFromArchives.contains(entry.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            let values: URLResourceValues? = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                walker.skipDescendants()
                continue
            }
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    /// A size as the Finder writes one ("1.2 GB").
    nonisolated static func sizeText(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Functions: the restore

    /// Restores a whole course from a backup zip, staged, and says what
    /// went wrong in the contract's words. `beforeTheSwap` is the refusals
    /// asked a third time; it throws to refuse.
    ///
    /// The seam for Undo (#899, U5) is `restore(fromZipAt:…)` itself: U5's
    /// undo of a whole-course restore is a staged restore of the archive
    /// made first, and its redo one of the backup again, so it needs a zip
    /// URL rather than a `BackupItem`. `keepingWhatWasReplaced` is handed
    /// the set-aside copy before it is deleted; no door passes one today,
    /// and U5's plan reads the archive instead (the plan review, M8).
    ///
    /// `keepsWhatWasReplaced` keeps the set-aside copy in the backups
    /// folder instead, recorded first (the fix review's I-a): the door
    /// passes it when no archive was made of a course folder that is there.
    /// `archiveBegan` is when the archive made first began, so the files of
    /// the set-aside copy written after it are kept.
    @discardableResult
    static func restore(
        fromZipAt zipURL: URL,
        courseCode: String,
        from source: RestoreSwap.Source = RestoreSwap.Source.backups,
        coursesDirectoryURL: URL,
        archiveURL: URL? = nil,
        archiveBegan: Date? = nil,
        keepsWhatWasReplaced: Bool = false,
        beforeTheSwap: @escaping (URL) throws -> Void = { (_: URL) throws in },
        hooks: RestoreSwap.Hooks = RestoreSwap.Hooks.real,
        keepingWhatWasReplaced: ((URL) -> Void)? = nil
    ) throws -> RestoreSwap.Restored {
        let courseURL: URL = coursesDirectoryURL.appendingPathComponent(courseCode)
        let backupFileName: String = zipURL.lastPathComponent
        let workingFolderURL: URL = coursesDirectoryURL.deletingLastPathComponent()
        let context: RestoreSwap.Context = RestoreSwap.Context(
            computer: SharedMediaStore.thisComputer,
            owner: ProcessLiveness.leaseBody(),
            now: { () -> String in
                return RestoreSettle.momentText(Date())
            },
            stamp: { () -> String in
                return ArchiveStamp.text(for: Date())
            },
            keptInPlace: keptInPlace,
            archiveURL: archiveURL,
            checkPayload: { (payload: URL) throws in
                if (try? CourseConfiguration(contentsOf: payload.appendingPathComponent("course_config.json"))) == nil {
                    throw CourseRestorer.Problem.archiveUnreadable("its course settings could not be read")
                }
            },
            putMediaBack: { (_: URL, _: URL?) throws in
                // 785b puts a small backup's Media back here. Until then a
                // small backup is refused by the guard below, with nothing
                // moved, and never restored as if it were whole (#908).
            },
            refuseUnlessMediaWasPutBack: { (unpacked: URL) throws in
                try SharedMediaStore.refuseUnlessItsMediaWasPutBack(unpackedAt: unpacked, backupFileName: backupFileName)
            },
            beforeTheSwap: beforeTheSwap,
            justBeforeTheSwap: { () in
                CourseRestorer.unlockForARestore(courseAt: courseURL)
                if !aLockedItemAtTheTopChangesNothing {
                    clearLocksAtTheTop(of: courseURL)
                }
                // Before the swap rather than after the commit (the plan
                // review, M9): a crash after the commit would otherwise
                // leave the old built site for a scheduled deploy to
                // publish over the restored pages.
                BuildOutputLocation.discardBuiltSites(forWorkingFolder: workingFolderURL, courseCode: courseCode)
            },
            afterCommit: { () in
                afterTheCommit(courseURL: courseURL)
            },
            keepingWhatWasReplaced: keepingWhatWasReplaced,
            keepsWhatWasReplaced: keepsWhatWasReplaced,
            archiveBegan: archiveBegan
        )
        do {
            let restored: RestoreSwap.Restored = try RestoreSwap.restore(
                fromZipAt: zipURL,
                courseCode: courseCode,
                backupFileName: backupFileName,
                from: source,
                coursesDirectoryURL: coursesDirectoryURL,
                context: context,
                hooks: hooks
            )
            noteWhatWasKept(restored, courseCode: courseCode)
            return restored
        } catch let failure as RestoreSwap.Failure {
            // Locked again whatever happened: a reference course left as it
            // was is still a reference course.
            CourseRestorer.lockAfterARestore(courseAt: courseURL)
            noteLeftAsItWas(failure, courseCode: courseCode, backupFileName: backupFileName)
            throw problem(for: failure, courseCode: courseCode, courseURL: courseURL, archived: archiveURL != nil)
        } catch {
            CourseRestorer.lockAfterARestore(courseAt: courseURL)
            noteLeftAsItWas(error, courseCode: courseCode, backupFileName: backupFileName)
            throw error
        }
    }

    // MARK: - Functions: the trail

    /// The trail line for a restore that did not go ahead (the
    /// implementation review's I4): which course, which backup, and why, in
    /// a fixed phrase. A stop part way writes its own line instead.
    static func noteDidNotGoAhead(
        _ kind: DidNotGoAhead,
        courseCode: String,
        backupFileName: String,
        detail: String? = nil,
        asked: AskedWhen? = nil,
        newcomersKeptAt: String? = nil
    ) {
        ActivityTrail.note(
            .courseRestoreLeftAsItWas,
            ActivityTrail.courseRestoreLeftAsItWasLine(
                backup: backupFileName, why: kind.rawValue, detail: detail, asked: asked?.rawValue,
                newcomersKeptAt: newcomersKeptAt
            ),
            course: courseCode,
            section: 0
        )
    }

    /// The line for what the engine reported, when it left the course as
    /// it was.
    static func noteLeftAsItWas(_ failure: RestoreSwap.Failure, courseCode: String, backupFileName: String) {
        switch failure {
        case .unreadable:
            noteDidNotGoAhead(.unreadable, courseCode: courseCode, backupFileName: backupFileName)
        case .noSpace:
            noteDidNotGoAhead(.ranOutOfSpace, courseCode: courseCode, backupFileName: backupFileName)
        case .leftAsItWas(_, let lockedItem, let courseFolderIsLocked, let newcomersKeptAt):
            if courseFolderIsLocked {
                noteDidNotGoAhead(.courseFolderLocked, courseCode: courseCode, backupFileName: backupFileName)
            } else if let lockedItem {
                noteDidNotGoAhead(
                    .lockedAtTheTop, courseCode: courseCode, backupFileName: backupFileName, detail: lockedItem
                )
            } else {
                noteDidNotGoAhead(
                    .aMoveFailed, courseCode: courseCode, backupFileName: backupFileName, newcomersKeptAt: newcomersKeptAt
                )
            }
        case .stoppedPartWay:
            // Its own event, `course restore stopped part way`.
            return
        case .anotherRestoreHoldsTheCourse:
            noteDidNotGoAhead(
                .anotherRestore, courseCode: courseCode, backupFileName: backupFileName, asked: .whenItBegan
            )
        }
    }

    /// The line for what a restore that worked kept in the backups folder
    /// (`course restore kept files`), when it kept anything: the paths,
    /// never a page.
    static func noteWhatWasKept(_ restored: RestoreSwap.Restored, courseCode: String) {
        if let keptAt = restored.keptWhatWasReplacedAt {
            ActivityTrail.note(
                .courseRestoreKeptFiles,
                ActivityTrail.courseRestoreKeptFilesLine(keptAt: keptAt, why: ActivityTrail.KeptBecause.noArchive),
                course: courseCode,
                section: 0
            )
        }
        if let keptAt = restored.keptWhatTheArchiveMayNotHoldAt {
            ActivityTrail.note(
                .courseRestoreKeptFiles,
                ActivityTrail.courseRestoreKeptFilesLine(keptAt: keptAt, why: ActivityTrail.KeptBecause.notInTheArchive),
                course: courseCode,
                section: 0
            )
        }
    }

    /// What a restore that worked tells the teacher about what it kept, or
    /// nil when it kept nothing (the fix review's I-b: nothing said where
    /// the folder went).
    static func sentenceForWhatWasKept(_ restored: RestoreSwap.Restored, courseCode: String) -> String? {
        var sentences: [String] = []
        if let keptAt = restored.keptWhatWasReplacedAt {
            sentences.append(RestoreWholeCourseWording.keptWhatWasInTheFolder(course: courseCode, keptAt: keptAt))
        }
        if let keptAt = restored.keptWhatTheArchiveMayNotHoldAt {
            sentences.append(RestoreWholeCourseWording.keptWhatTheArchiveMayNotHold(course: courseCode, keptAt: keptAt))
        }
        if sentences.isEmpty {
            return nil
        }
        return sentences.joined(separator: "\n\n")
    }

    /// The line for an error that is not the engine's own: a backup whose
    /// settings do not read, a small backup refused, anything else. A
    /// refusal is noted by the door that refused, which knows which one.
    static func noteLeftAsItWas(_ error: Error, courseCode: String, backupFileName: String) {
        if let problem = error as? CourseRestorer.Problem {
            switch problem {
            case .refused:
                return
            case .archiveUnreadable:
                noteDidNotGoAhead(.unreadable, courseCode: courseCode, backupFileName: backupFileName)
                return
            default:
                break
            }
        }
        if let problem = error as? SharedMediaStore.Problem, case .mediaNotPutBack = problem {
            noteDidNotGoAhead(.mediaNotPutBack, courseCode: courseCode, backupFileName: backupFileName)
            return
        }
        noteDidNotGoAhead(.otherProblem, courseCode: courseCode, backupFileName: backupFileName)
    }

    /// The steps after the commit, safe to run twice (a settle that finds
    /// `done` runs them again): the rename records go with the pages they
    /// described, moved here from BEFORE the restore so one that fails no
    /// longer clears them; and the course is locked again when it is kept
    /// for reference.
    static func afterTheCommit(courseURL: URL) {
        UnitWordRenamer.clearRenameRecord(courseDirectory: courseURL)
        SpecialFolderRenamer.clearRenameRecord(courseDirectory: courseURL)
        CourseRestorer.lockAfterARestore(courseAt: courseURL)
    }

    /// M13's other answer: Finder's Locked flag cleared on the course's
    /// top-level items.
    static func clearLocksAtTheTop(of courseURL: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: courseURL.path) else {
            return
        }
        for name in names {
            RestoreSwap.clearLockAndMakeWritable(courseURL.appendingPathComponent(name))
        }
    }

    /// The contract's sentence for what the engine reports.
    static func problem(
        for failure: RestoreSwap.Failure,
        courseCode: String,
        courseURL: URL,
        archived: Bool
    ) -> CourseRestorer.Problem {
        switch failure {
        case .unreadable(let reason):
            return .archiveUnreadable(reason)
        case .noSpace:
            return .courseRanOutOfSpace(courseCode)
        case .leftAsItWas(let reason, let lockedItem, let courseFolderIsLocked, let newcomersKeptAt):
            if courseFolderIsLocked {
                return .courseFolderLocked(courseCode)
            }
            if let lockedItem {
                return .courseLeftAsItWasLocked(courseCode, lockedItem)
            }
            return .courseLeftAsItWas(courseCode, reason, newcomersKeptAt: newcomersKeptAt)
        case .anotherRestoreHoldsTheCourse:
            return .refused(RestoreWholeCourseWording.anotherRestoreUnderWay(course: courseCode))
        case .stoppedPartWay(let keptAt, let holdsSomethingToOpen):
            let settingsAreBack: Bool = RestoreSwap.itemExists(at: courseURL.appendingPathComponent("course_config.json"))
            ActivityTrail.note(
                .courseRestoreStoppedPartWay,
                ActivityTrail.courseRestoreStoppedPartWayLine(keptAt: keptAt, atTheNextReading: false),
                course: courseCode,
                section: 0
            )
            return .courseRestoreStoppedPartWay(
                courseCode, keptAt: holdsSomethingToOpen ? keptAt : nil, archived: archived,
                settingsAreBack: settingsAreBack
            )
        }
    }

    // MARK: - Functions: the next reading

    /// Settles every restore that did not finish in this folder, writes a
    /// trail line for each, and returns what the teacher is to be told,
    /// once, in order. Called by `reloadCourses` before the folder is
    /// listed, so a course put back is in the list that reading makes.
    ///
    /// `onlyCourse` settles that course's records alone: Undo's U5 calls it
    /// before its own recovery looks at the course (the plan review, M8).
    @discardableResult
    static func settleUnfinishedRestores(in coursesDirectoryURL: URL, onlyCourse: String? = nil) -> [String] {
        let context: RestoreSettle.Context = RestoreSettle.Context(
            computer: SharedMediaStore.thisComputer,
            owner: ProcessLiveness.leaseBody(),
            processID: getpid(),
            ownerIsAlive: { (body: String) -> Bool in
                return ownerIsAlive(leaseBody: body)
            },
            now: Date(),
            stamp: { () -> String in
                return ArchiveStamp.text(for: Date())
            },
            afterCommit: { (courseCode: String) in
                afterTheCommit(courseURL: coursesDirectoryURL.appendingPathComponent(courseCode))
            },
            afterPuttingBack: { (courseCode: String) in
                CourseRestorer.lockAfterARestore(courseAt: coursesDirectoryURL.appendingPathComponent(courseCode))
            },
            hooks: RestoreSwap.Hooks.real
        )
        let settled: [RestoreSettle.Settled] = RestoreSettle.settle(
            coursesDirectoryURL: coursesDirectoryURL, onlyCourse: onlyCourse, context: context
        )
        var said: [String] = []
        for outcome in settled {
            ActivityTrail.note(.unfinishedRestoreSettled, ActivityTrail.unfinishedRestoreSettledLine(outcome))
            if outcome.says == .stoppedPartWay, let keptAt = outcome.keptAt {
                ActivityTrail.note(
                    .courseRestoreStoppedPartWay,
                    ActivityTrail.courseRestoreStoppedPartWayLine(keptAt: keptAt, atTheNextReading: true),
                    course: outcome.course ?? "",
                    section: 0
                )
            }
            if let sentence = sentence(for: outcome, coursesDirectoryURL: coursesDirectoryURL) {
                said.append(sentence)
            }
        }
        if !tellsTheTeacherOnceAfterPuttingRight {
            return []
        }
        return said
    }

    /// Another computer's restores this computer leaves alone while their
    /// course is missing here (the implementation review's I2): the
    /// sentence for each one not in `alreadyTold`, with a trail line, and
    /// the staging names now told, so the caller says each once per
    /// opening. Nothing is moved: another computer's record is never acted
    /// on by moving files (the plan review's M1).
    static func unfinishedOnAnotherComputer(
        in coursesDirectoryURL: URL,
        alreadyTold: Set<String>
    ) -> (said: [String], told: [String]) {
        let found: [(staging: String, outcome: RestoreSettle.Settled)] = RestoreSettle.unfinishedOnAnotherComputer(
            coursesDirectoryURL: coursesDirectoryURL, computer: SharedMediaStore.thisComputer, now: Date()
        )
        var said: [String] = []
        var told: [String] = []
        for entry in found where !alreadyTold.contains(entry.staging) {
            ActivityTrail.note(.unfinishedRestoreSettled, ActivityTrail.unfinishedRestoreSettledLine(entry.outcome))
            said.append(RestoreWholeCourseWording.unfinishedOnAnotherComputer(course: entry.outcome.course ?? ""))
            told.append(entry.staging)
        }
        return (said: said, told: told)
    }

    /// What the teacher is told about one settled folder, or nil.
    static func sentence(for outcome: RestoreSettle.Settled, coursesDirectoryURL: URL) -> String? {
        let course: String = outcome.course ?? ""
        var sentence: String? = nil
        switch outcome.says {
        case .didNotFinish:
            if outcome.from == RestoreSwap.Source.archived {
                sentence = RestoreWholeCourseWording.didNotFinishFromArchived(course: course)
            } else {
                sentence = RestoreWholeCourseWording.didNotFinish(course: course)
            }
        case .stoppedPartWay:
            if let keptAt = outcome.keptAt, outcome.holdsSomethingToOpen {
                sentence = RestoreWholeCourseWording.stoppedPartWay(course: course, keptAt: keptAt)
            } else {
                sentence = RestoreWholeCourseWording.stoppedPartWayNothingToOpen(course: course)
            }
            let settings: URL = coursesDirectoryURL.appendingPathComponent(course).appendingPathComponent("course_config.json")
            if !RestoreSwap.itemExists(at: settings) {
                sentence = (sentence ?? "") + " " + RestoreWholeCourseWording.notInTheSidebar(course: course)
                    + " " + RestoreWholeCourseWording.restoreAgainToPutItRight(course: course)
            }
        case .setAsideFilesKept:
            if let keptAt = outcome.keptAt, outcome.holdsSomethingToOpen {
                sentence = RestoreWholeCourseWording.setAsideFilesKept(keptAt: keptAt)
            }
        case nil:
            sentence = nil
        }
        if let newcomers = outcome.newcomersKeptAt {
            let kept: String = RestoreWholeCourseWording.newcomersKept(course: course, keptAt: newcomers)
            if let said = sentence {
                sentence = said + " " + kept
            } else {
                sentence = kept
            }
        }
        return sentence
    }

    /// Whether the process a lease body names is still the one that wrote
    /// it, as every lease reader judges one.
    nonisolated static func ownerIsAlive(leaseBody body: String) -> Bool {
        let unixText: String = body.replacingOccurrences(of: "\r\n", with: "\n")
        guard let first = unixText.split(separator: "\n", omittingEmptySubsequences: false).first,
              let pid = Int32(first.trimmingCharacters(in: .whitespaces)) else {
            return false
        }
        let facts: (name: String?, start: String?) = ProcessLiveness.recordedFacts(inLeaseText: body)
        return ProcessLiveness.ownerIsAlive(pid: pid, recordedName: facts.name, recordedStart: facts.start)
    }
}
