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

    // MARK: - Stored properties

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

    /// `<FOLDER>.import.<pid>.lease` — the shape `WorkLease` already uses.
    static func leaseName(for folderName: String, pid: Int32 = getpid()) -> String {
        return "\(folderName).import.\(pid).lease"
    }

    /// Says that THIS process is importing into that staging folder.
    ///
    /// Written outside the staging folder on purpose, so removing the folder
    /// does not remove the claim to it.
    static func takeLease(for folderName: String, inCoursesDirectory coursesDirectoryURL: URL) {
        let activity: URL = ReferenceStaging.activityDirectory(
            inCoursesDirectory: coursesDirectoryURL
        )
        try? FileManager.default.createDirectory(at: activity, withIntermediateDirectories: true)
        let lease: URL = activity.appendingPathComponent(ReferenceStaging.leaseName(for: folderName))
        try? Data("\(getpid())".utf8).write(to: lease)
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
    /// `kill(pid, 0)` asks the system whether the process exists without
    /// sending it anything. A recycled process id is the one case this cannot
    /// see through, and it is the same caveat every lease in this product
    /// carries; the direction it errs in is leaving a folder alone, which
    /// costs disk space until the next open rather than destroying work.
    static func someoneIsWorkingOn(_ stagingName: String, inCoursesDirectory coursesDirectoryURL: URL) -> Bool {
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
            if kill(pid, 0) == 0 {
                someoneIsAlive = true
                continue
            }
            // Its owner is gone, so the claim is stale and goes with the
            // folder it was about.
            try? FileManager.default.removeItem(at: lease)
        }
        return someoneIsAlive
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
            if ReferenceStaging.someoneIsWorkingOn(name, inCoursesDirectory: coursesDirectoryURL) {
                continue
            }
            if ReferenceStaging.remove(at: child) {
                swept.append(ReferenceStaging.courseFolderName(fromStaging: name))
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
