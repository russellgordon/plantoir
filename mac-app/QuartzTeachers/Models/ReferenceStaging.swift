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
/// `.skipsHiddenFiles`, and three tests pin that rather than trusting it. The
/// launchers take a course CODE and build `courses/<CODE>`, and a code cannot
/// begin with a dot (`CourseCodeRule`), so nothing on the command line can
/// name one of these either.
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

    /// Clears away staging folders left by an import that never finished —
    /// the app quit, the Mac lost power — and says which ones it took.
    ///
    /// Called when a working folder is read, beside the other things that are
    /// re-asserted there. A leftover is invisible to the sidebar, so without
    /// this it would sit in `courses/` for ever, holding a copy of a course
    /// nobody can see.
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
