import Foundation

/// Where a reference course is BUILT before anybody can see it.
///
/// **The fault this exists to close.** A reference course is made by copying
/// a course and then neutralising it — the marker written, last year's site
/// markers renamed aside, the destination emptied. Until 2026-09-20 the copy
/// was made at its FINAL name, so for the length of the copy `courses/ICS4U-2025/`
/// held last year's REAL site markers beside a config with no marker and no
/// `deploy_target` — which reads as Netlify. Measured: `./deploy.sh` run
/// against that half-made folder does not refuse at all. A crash, a quit or a
/// power cut in that window leaves an ordinary-looking live course in the
/// sidebar with a working Deploy button aimed at last year's class site; if
/// the source was itself frozen, the leftover cannot even be deleted.
///
/// The window was about two seconds for an APFS clone and the whole copy for
/// an external disk — which is exactly the case the importer is written for.
///
/// **The cure is a name, not a lock.** The copy is made under a DOT-PREFIXED
/// folder inside `courses/`, marked and neutralised and locked THERE, and
/// moved to its real name as the last act. `moveItem` within one folder is a
/// rename, so the step that makes it visible is atomic: there is no moment
/// when something under `courses/` is a course and is not yet a reference
/// course. Measured: renaming a folder whose contents carry the lock works,
/// and the lock survives it.
///
/// **Dot-prefixed because everything that looks for a course skips hidden
/// entries** — discovery, the backups list and the archives list all pass
/// `.skipsHiddenFiles`, and three tests pin that rather than trusting it.
///
/// **The launchers are a REFUSAL rather than an impossibility**, and this
/// comment said the opposite until it was measured: they applied no shape
/// check at all, `deploy.sh` uppercased the hidden name, the case-insensitive
/// volume resolved it, and the run went past the reference gate — which finds
/// nothing during the copy, because the marker is not written yet. All four
/// launchers now refuse a course argument beginning with a dot before
/// anything else. The app itself can never pass one: `CourseCodeRule` refuses
/// a leading dot and discovery never sees these folders.
@MainActor
enum ReferenceStaging {

    // MARK: - Types

    /// What a claim came to.
    enum Claim: Equatable {
        /// The folder is made, empty, and this caller owns it until
        /// `giveBack`. Only an owner ever removes a staging folder.
        case claimed
        /// Somebody else is making this course right now — another window of
        /// this app, or another copy of Plantoir. Nothing was removed.
        case someoneElseIsMakingIt
        /// It could not be started, for the reason given — said to the
        /// teacher as it stands.
        case couldNotStart(String)
    }

    /// How the step that makes the folder went. Separate from the thrown
    /// error so the rule can be run from the contract's cases without a disk
    /// that misbehaves on cue.
    enum CreateAnswer: Equatable {
        case made
        case alreadyThere
        case failed(String)
    }

    // MARK: - Stored properties

    /// Staging folders THIS process is making right now, by
    /// `claimKey(for:inCoursesDirectory:)`.
    ///
    /// Two windows are ONE process with one process id, so a lease file
    /// cannot tell them apart: window B would read window A's lease as its
    /// own. This can. Keyed by the folder's CANONICAL path rather than by the
    /// path as a window spelled it, because two windows can reach one working
    /// folder through a link, through `/private`, or in another case on a
    /// case-insensitive disk — and a set that missed would let window B clear
    /// window A's half-made copy away as a leftover, which is the fault this
    /// exists to close.
    static var claimedStagingKeys: Set<String> = []

    /// What every staging folder's name begins with.
    ///
    /// Distinctive on purpose: the sweep below REMOVES what it matches, and a
    /// teacher's own dot-folder — `.obsidian`, `.internal`, `.git` — must
    /// never be mistaken for one of ours.
    static let prefix: String = ".plantoir-importing-"

    // MARK: - Functions

    /// The hidden name a course is built under before it is given its real
    /// one.
    static func stagingName(for folderName: String) -> String {
        return ReferenceStaging.prefix + folderName
    }

    /// Whether this is one of ours.
    static func isStagingName(_ name: String) -> Bool {
        return name.hasPrefix(ReferenceStaging.prefix) && name.count > ReferenceStaging.prefix.count
    }

    /// Takes away a staging folder — unlocking first, because the lock is
    /// applied before the rename and `removeItem` refuses a locked tree.
    ///
    /// Returns whether the folder is gone afterwards, so a caller can say so
    /// rather than assume it.
    @discardableResult
    static func remove(at stagingURL: URL) -> Bool {
        let fileManager: FileManager = FileManager.default
        ReferenceLock.clearLock(at: stagingURL)
        try? fileManager.removeItem(at: stagingURL)
        return !fileManager.fileExists(atPath: stagingURL.path)
    }

    // MARK: - Saying that an import is under way

    /// Where a lease lives: `courses/.internal/activity/`, the folder this
    /// product already uses to say what is going on in a working folder.
    static func activityDirectory(inCoursesDirectory coursesDirectoryURL: URL) -> URL {
        return coursesDirectoryURL
            .appendingPathComponent(".internal").appendingPathComponent("activity")
    }

    /// `<FOLDER>.import.<pid>.lease` — the NAME shape every work lease has
    /// (`contracts/file-formats.json` → `workLease`). Its contents are the
    /// shared four lines `ProcessLiveness.leaseBody` writes.
    static func leaseName(for folderName: String, pid: Int32 = getpid()) -> String {
        return "\(folderName).import.\(pid).lease"
    }

    /// Says that THIS process is importing into that staging folder.
    ///
    /// Written outside the staging folder on purpose, so removing the folder
    /// does not remove the claim to it. The name is unchanged from before
    /// #245, so an older copy of Plantoir — which reads names only — still
    /// leaves the folder alone; the contents gained the process's name and
    /// start time, which is what lets a reader tell a recycled process id
    /// from the process that wrote the lease.
    static func takeLease(for folderName: String, inCoursesDirectory coursesDirectoryURL: URL) {
        let activity: URL = ReferenceStaging.activityDirectory(
            inCoursesDirectory: coursesDirectoryURL
        )
        try? FileManager.default.createDirectory(at: activity, withIntermediateDirectories: true)
        let lease: URL = activity.appendingPathComponent(ReferenceStaging.leaseName(for: folderName))
        try? Data(ProcessLiveness.leaseBody().utf8).write(to: lease, options: .atomic)
    }

    /// Gives it back. A lease that outlives its process is ignored rather
    /// than trusted, so a crash costs nothing; this is the tidy path.
    static func releaseLease(for folderName: String, inCoursesDirectory coursesDirectoryURL: URL) {
        let lease: URL = ReferenceStaging
            .activityDirectory(inCoursesDirectory: coursesDirectoryURL)
            .appendingPathComponent(ReferenceStaging.leaseName(for: folderName))
        try? FileManager.default.removeItem(at: lease)
    }

    /// Whether some LIVE process says it is importing into this staging
    /// folder.
    ///
    /// Who counts as alive is `ProcessLiveness`'s question, asked of the
    /// process id in the lease's name and the name and start time inside it:
    /// another account's process is alive (the system says it exists and is
    /// not ours to signal — until #245 that answer read as "gone" and the
    /// folder was swept), a process that has finished is gone, and a process
    /// id handed on to a different process is gone. A lease whose owner is
    /// gone is removed as it is read, because it goes with the folder it was
    /// about.
    ///
    /// - Parameter ignoredPid: a process id whose leases are not counted and
    ///   not removed — the claim passes its own, because a process is never
    ///   in its own way across processes (two windows are told apart by
    ///   `claimedStagingKeys`, not by a lease, since they share one id).
    static func someoneIsWorkingOn(
        _ stagingName: String,
        inCoursesDirectory coursesDirectoryURL: URL,
        ignoring ignoredPid: Int32? = nil
    ) -> Bool {
        let folderName: String = ReferenceStaging.courseFolderName(fromStaging: stagingName)
        let activity: URL = ReferenceStaging.activityDirectory(
            inCoursesDirectory: coursesDirectoryURL
        )
        guard let leases = try? FileManager.default.contentsOfDirectory(
            at: activity, includingPropertiesForKeys: nil, options: []
        ) else {
            return false
        }

        let prefix: String = "\(folderName).import."
        var someoneIsAlive: Bool = false
        for lease in leases {
            let name: String = lease.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(".lease") else {
                continue
            }
            let middle: String = String(
                name.dropFirst(prefix.count).dropLast(".lease".count)
            )
            guard let pid = Int32(middle) else {
                continue
            }
            if let ignoredPid = ignoredPid, pid == ignoredPid {
                continue
            }
            let text: String = (try? String(contentsOf: lease, encoding: .utf8)) ?? ""
            let recorded: (name: String?, start: String?) = ProcessLiveness.recordedFacts(
                inLeaseText: text
            )
            let judgedName: String? = ProcessLiveness.nameToCompare(recorded: recorded.name, kind: "import")
            if ProcessLiveness.ownerIsAlive(
                pid: pid, recordedName: judgedName, recordedStart: recorded.start
            ) {
                someoneIsAlive = true
                continue
            }
            // Its owner is gone, so the claim is stale and goes with the
            // folder it was about.
            try? FileManager.default.removeItem(at: lease)
        }
        return someoneIsAlive
    }

    // MARK: - Claiming a staging folder

    /// The key a staging folder is known by in `claimedStagingKeys`: the
    /// `courses/` folder's real path (links resolved, `/private` kept, the
    /// disk's own spelling of each name — `FolderIdentity.canonicalPath`,
    /// the one answer every folder comparison uses since #189) and the
    /// staging name in lower case.
    static func claimKey(for folderName: String, inCoursesDirectory coursesDirectoryURL: URL) -> String {
        let coursesPath: String = FolderIdentity.canonicalPath(coursesDirectoryURL.path)
        return coursesPath + "/" + ReferenceStaging.stagingName(for: folderName).lowercased()
    }

    /// Takes the staging folder for `folderName`, or says why not.
    ///
    /// **One act, on the main actor, with no suspension inside it**, so two
    /// windows cannot interleave in it. In order:
    ///
    /// 1. Already claimed in this process → someone else (another window).
    /// 2. Take our lease, THEN look for another process's live lease. Of two
    ///    processes, the one that looks second always sees the first one's
    ///    lease, so they can never both go on; at worst both step back and
    ///    both say so, which is a refusal a teacher can retry, never a copy
    ///    removed under somebody.
    /// 3. A leftover of that name — nobody live owns it now — is cleared;
    ///    one that will not go is a reason not to start.
    /// 4. The folder is made EXCLUSIVELY. Already there means somebody slipped
    ///    in between 3 and 4: someone else, and nothing is removed.
    ///
    /// Every answer but `.claimed` gives the lease back and removes nothing
    /// it did not put there.
    static func claim(
        _ folderName: String,
        inCoursesDirectory coursesDirectoryURL: URL,
        removingLeftover removeLeftover: (URL) -> Bool = { stagingURL in
            return ReferenceStaging.remove(at: stagingURL)
        },
        creating create: (URL) -> CreateAnswer = { stagingURL in
            return ReferenceStaging.createExclusively(at: stagingURL)
        }
    ) -> Claim {
        let key: String = ReferenceStaging.claimKey(
            for: folderName, inCoursesDirectory: coursesDirectoryURL
        )
        if ReferenceStaging.claimedStagingKeys.contains(key) {
            return .someoneElseIsMakingIt
        }

        let stagingName: String = ReferenceStaging.stagingName(for: folderName)
        let stagingURL: URL = coursesDirectoryURL.appendingPathComponent(stagingName)

        ReferenceStaging.takeLease(for: folderName, inCoursesDirectory: coursesDirectoryURL)
        if ReferenceStaging.someoneIsWorkingOn(
            stagingName, inCoursesDirectory: coursesDirectoryURL, ignoring: getpid()
        ) {
            ReferenceStaging.releaseLease(for: folderName, inCoursesDirectory: coursesDirectoryURL)
            return .someoneElseIsMakingIt
        }

        if FileManager.default.fileExists(atPath: stagingURL.path) {
            if !removeLeftover(stagingURL) {
                ReferenceStaging.releaseLease(
                    for: folderName, inCoursesDirectory: coursesDirectoryURL
                )
                return .couldNotStart(ReferenceImportWording.leftoverInTheWay)
            }
        }

        let answer: CreateAnswer = create(stagingURL)
        switch answer {
        case .made:
            ReferenceStaging.claimedStagingKeys.insert(key)
            return .claimed
        case .alreadyThere:
            ReferenceStaging.releaseLease(for: folderName, inCoursesDirectory: coursesDirectoryURL)
            return .someoneElseIsMakingIt
        case .failed(let reason):
            ReferenceStaging.releaseLease(for: folderName, inCoursesDirectory: coursesDirectoryURL)
            return .couldNotStart(reason)
        }
    }

    /// Gives a claimed staging folder back: out of this process's set, lease
    /// released. It does NOT remove the folder — by now its owner has either
    /// renamed it into place or tidied it away, and if the tidy failed it is
    /// ordinary litter for the next sweep.
    static func giveBack(_ folderName: String, inCoursesDirectory coursesDirectoryURL: URL) {
        let key: String = ReferenceStaging.claimKey(
            for: folderName, inCoursesDirectory: coursesDirectoryURL
        )
        ReferenceStaging.claimedStagingKeys.remove(key)
        ReferenceStaging.releaseLease(for: folderName, inCoursesDirectory: coursesDirectoryURL)
    }

    /// Makes the staging folder, refusing one that is already there —
    /// making a folder is exclusive, which is what makes it the last word
    /// between two processes that both passed the lease check.
    ///
    /// Asked through `FileManager` rather than `mkdir` so any OTHER failure
    /// is said in the same sentence the import has always given for it.
    /// Measured: an existing folder — or an existing file of that name —
    /// throws Cocoa error 516 over POSIX 17 (`EEXIST`).
    static func createExclusively(at stagingURL: URL) -> CreateAnswer {
        do {
            try FileManager.default.createDirectory(
                at: stagingURL, withIntermediateDirectories: false
            )
            return .made
        } catch let error as NSError {
            if ReferenceStaging.saysAlreadyThere(error) {
                return .alreadyThere
            }
            return .failed(error.localizedDescription)
        }
    }

    /// Whether an error from making a folder means "something of that name is
    /// already there".
    static func saysAlreadyThere(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST) {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(EEXIST)
        }
        return false
    }

    /// Clears away staging folders left by an import that never finished —
    /// the app quit, the Mac lost power — and says which ones it took.
    ///
    /// Called when a working folder is read, beside the other things that are
    /// re-asserted there. A leftover is invisible to the sidebar, so without
    /// this it would sit in `courses/` for ever, holding a copy of a course
    /// nobody can see.
    ///
    /// **A folder somebody is still working on is left alone**, and that is
    /// not a nicety. `reloadCourses` is reached by File ▸ Reload Courses
    /// (offered while the import sheet is up), by a SECOND WINDOW on the same
    /// working folder, and by `Plantoir --mcp-stdio` — which is how a Claude
    /// Code session starts, and is the arrangement the product describes as
    /// normal. Without this check, one of those sweeps the tree out from
    /// under a running copy: the copy then fails with a system error the
    /// teacher cannot act on, and if it lands after the lock and before the
    /// rename, a FINISHED reference course is thrown away.
    ///
    /// The liveness question is asked of a lease naming a process, never of a
    /// folder's age: a threshold is a guessed duration, and a guessed
    /// duration is wrong on a slow disk — which is the very case an import
    /// takes minutes on.
    @discardableResult
    static func sweepLeftovers(inCoursesDirectory coursesDirectoryURL: URL) -> [String] {
        let fileManager: FileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: coursesDirectoryURL, includingPropertiesForKeys: nil, options: []
        ) else {
            return []
        }

        var swept: [String] = []
        for child in children {
            let name: String = child.lastPathComponent
            guard ReferenceStaging.isStagingName(name) else {
                continue
            }
            // This app's own claims first: they do not depend on a lease file
            // having been written, which is `try?` and can fail on a folder
            // whose `.internal` cannot be made.
            let folderName: String = ReferenceStaging.courseFolderName(fromStaging: name)
            let key: String = ReferenceStaging.claimKey(
                for: folderName, inCoursesDirectory: coursesDirectoryURL
            )
            if ReferenceStaging.claimedStagingKeys.contains(key) {
                continue
            }
            if ReferenceStaging.someoneIsWorkingOn(name, inCoursesDirectory: coursesDirectoryURL) {
                continue
            }
            if ReferenceStaging.remove(at: child) {
                swept.append(folderName)
            }
        }
        return swept
    }

    /// The folder name an unfinished import was going to end up as.
    static func courseFolderName(fromStaging stagingName: String) -> String {
        return String(stagingName.dropFirst(ReferenceStaging.prefix.count))
    }

    /// The trail line for a leftover tidied away.
    static func trailLine(for folderNames: [String]) -> String {
        var names: String = ""
        for name in folderNames {
            if !names.isEmpty {
                names += ", "
            }
            names += name
        }
        let count: String = folderNames.count == 1 ? "an unfinished import" : "unfinished imports"
        return "tidied away \(count) left behind by an earlier run — \(names)"
    }
}
