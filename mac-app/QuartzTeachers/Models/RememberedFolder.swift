import Foundation

/// A working folder Plantoir remembers from last time, and whether it can be
/// reopened now (#311, with #290's reach check folded in).
///
/// Found by a PLAIN bookmark first and its path second, so a folder renamed
/// or moved on the same disk reopens where it now is. Measured 2026-09-26 on
/// this Mac: a plain bookmark follows a rename (`isStale` comes back true);
/// it ALSO follows a move into the Trash and resolves to `~/.Trash/<name>`,
/// where the folder still exists — so a bookmark leading into a Trash is
/// refused rather than followed. A security-scoped bookmark was rejected:
/// the app is not sandboxed, and unsandboxed one is created and "starts"
/// and grants nothing a plain one lacks outside the folders macOS protects.
/// Whether it would help inside them (Desktop, Documents, with permission
/// denied) could not be measured on 2026-09-26 — the Mac's screen was
/// locked, so the permission question could not be answered — and is on
/// Russell's list in documentation/09-mac-app.md.
nonisolated struct RememberedFolder: Equatable, Sendable {

    // MARK: - Types

    /// Why a remembered folder cannot be reopened. The raw values are the
    /// contract's keys (`reopeningTheLastWorkingFolder.wording`).
    enum Reason: String, CaseIterable, Sendable {
        case gone
        case inTrash
        case driveNotConnected
        case unreadable
        case outsideHome
        case coursesOutsideHome
    }

    /// What was found on the disk, before anything is decided.
    struct Facts: Equatable, Sendable {
        /// Where the folder is now: the bookmark's answer when it had one
        /// that resolved, otherwise the remembered path.
        var resolvedPath: String
        /// The remembered path, as it was written down.
        var rememberedPath: String
        var existsAsDirectory: Bool
        var isInsideTrash: Bool
        var volumeIsMissing: Bool
        var isReadable: Bool
        var reachRefusal: WorkingFolderReach.WhichPath?
    }

    /// What to do with it.
    enum Outcome: Equatable, Sendable {
        /// Reopen at `path`; `movedFrom` is the remembered path when the
        /// bookmark found the folder somewhere else.
        case reopen(path: String, movedFrom: String?)
        case cannotReopen(Reason, folderName: String, path: String)
    }

    // MARK: - Stored properties

    let path: String
    let bookmark: Data?

    // MARK: - Computed properties

    /// The folder's own name, for the sentence.
    var folderName: String {
        return URL(fileURLWithPath: path).lastPathComponent
    }

    // MARK: - Functions

    /// Remembers a folder: its path, and a plain bookmark when one can be
    /// made (nil otherwise — the path alone still works).
    static func make(for url: URL) -> RememberedFolder {
        let bookmark: Data? = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return RememberedFolder(path: url.path, bookmark: bookmark)
    }

    /// Looks at the disk. Resolved `.withoutUI` and `.withoutMounting`, so an
    /// unmounted network share never raises a mount prompt or holds launch.
    /// `trashRoots` is injectable so a test never touches the real Trash.
    static func observe(_ remembered: RememberedFolder, trashRoots: [String]? = nil) -> Facts {
        var resolvedPath: String = remembered.path
        if let bookmark = remembered.bookmark {
            var isStale: Bool = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                resolvedPath = url.path
            }
        }
        var inTrash: Bool = RememberedFolder.isInTrash(resolvedPath, trashRoots: trashRoots)
        // The bookmark followed the folder into a Trash, but the original
        // place holds a folder again (put back from a backup, or a copy):
        // that is the folder the teacher means.
        if inTrash && resolvedPath != remembered.path
            && RememberedFolder.isDirectory(atPath: remembered.path)
            && !RememberedFolder.isInTrash(remembered.path, trashRoots: trashRoots) {
            resolvedPath = remembered.path
            inTrash = false
        }
        // The drive is asked about BEFORE the folder: a path under a
        // `/Volumes/<name>` that is not mounted is answered from the name
        // alone, without touching anything under it.
        let volumeIsMissing: Bool = RememberedFolder.volumeIsMissing(for: resolvedPath)
        var exists: Bool = false
        var readable: Bool = false
        var reach: WorkingFolderReach.WhichPath?
        if !volumeIsMissing {
            exists = RememberedFolder.isDirectory(atPath: resolvedPath)
            if exists {
                readable = (try? FileManager.default.contentsOfDirectory(atPath: resolvedPath)) != nil
                if let refusal = WorkingFolderReach.refusal(forFolder: URL(fileURLWithPath: resolvedPath)) {
                    reach = refusal.whichPath
                }
            }
        }
        return Facts(
            resolvedPath: resolvedPath,
            rememberedPath: remembered.path,
            existsAsDirectory: exists,
            isInsideTrash: inTrash,
            volumeIsMissing: volumeIsMissing,
            isReadable: readable,
            reachRefusal: reach
        )
    }

    /// The decision, in this order: the Trash first (a trashed folder
    /// EXISTS, so asking existence first would reopen it), then a drive that
    /// is not connected, then gone, then unreadable, then out of the
    /// builder's reach — and otherwise, reopen.
    static func decide(_ facts: Facts) -> Outcome {
        let folderName: String = URL(fileURLWithPath: facts.rememberedPath).lastPathComponent
        if facts.isInsideTrash {
            return .cannotReopen(.inTrash, folderName: folderName, path: facts.resolvedPath)
        }
        if facts.volumeIsMissing {
            return .cannotReopen(.driveNotConnected, folderName: folderName, path: facts.resolvedPath)
        }
        if !facts.existsAsDirectory {
            return .cannotReopen(.gone, folderName: folderName, path: facts.resolvedPath)
        }
        if !facts.isReadable {
            return .cannotReopen(.unreadable, folderName: folderName, path: facts.resolvedPath)
        }
        if let which = facts.reachRefusal {
            switch which {
            case .workingFolder:
                return .cannotReopen(.outsideHome, folderName: folderName, path: facts.resolvedPath)
            case .coursesFolder:
                return .cannotReopen(.coursesOutsideHome, folderName: folderName, path: facts.resolvedPath)
            }
        }
        var movedFrom: String?
        if facts.resolvedPath != facts.rememberedPath {
            movedFrom = facts.rememberedPath
        }
        return .reopen(path: facts.resolvedPath, movedFrom: movedFrom)
    }

    /// True when a path lies in a Trash: a folder named `.Trash` or
    /// `.Trashes` anywhere along it (the home Trash, a drive's Trash, iCloud
    /// Drive's, another account's), or under one of `trashRoots` when a
    /// test supplies them. Compared by folder names, not by prefix, so case
    /// and the `/System/Volumes/Data` spelling do not matter.
    static func isInTrash(_ path: String, trashRoots: [String]?) -> Bool {
        if let trashRoots {
            for root in trashRoots {
                if WorkingFolderReach.isInside(canonicalFolderPath: path, canonicalHomePath: root) {
                    return true
                }
            }
            return false
        }
        for name in URL(fileURLWithPath: path).pathComponents {
            if name == ".Trash" || name == ".Trashes" {
                return true
            }
        }
        return false
    }

    /// True when a folder is there (not a file).
    static func isDirectory(atPath path: String) -> Bool {
        var isFolder: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
        return exists && isFolder.boolValue
    }

    /// True when the path is on a drive under `/Volumes` that is not there.
    /// A stale, empty mount point left by an unclean eject reads as present,
    /// and the folder then reads as gone — honest, if less specific.
    static func volumeIsMissing(for path: String) -> Bool {
        let names: [String] = URL(fileURLWithPath: path).pathComponents
        // ["/", "Volumes", "<drive>", …]
        if names.count < 3 || names[1] != "Volumes" {
            return false
        }
        let volumePath: String = "/Volumes/" + names[2]
        return !FileManager.default.fileExists(atPath: volumePath)
    }
}

/// What a teacher is told when the working folder from last time cannot be
/// reopened. The one home for these sentences;
/// `contracts/shared-rules.json` → `reopeningTheLastWorkingFolder.wording`
/// is pinned against `sentence(for:folderName:)` by a test.
nonisolated enum ReopenWording {

    // MARK: - Functions

    static func gone(folderName: String) -> String {
        return "“\(folderName)”, the working folder you had open last time, can’t be found — if you moved it, choose it again from its new place."
    }

    static func inTrash(folderName: String) -> String {
        return "“\(folderName)”, the working folder you had open last time, is in the Trash — put it back and choose it again, or choose another folder."
    }

    static func driveNotConnected(folderName: String) -> String {
        return "“\(folderName)”, the working folder you had open last time, is on a drive that isn’t connected — connect it and open Plantoir again, or choose another folder."
    }

    /// Points at the setting, because that is the fix that lasts: a folder
    /// macOS protects (Desktop, Documents, a removable drive) that Plantoir
    /// was not allowed into. Choosing it again in the picker is offered too.
    static func unreadable(folderName: String) -> String {
        return "Plantoir isn’t allowed to open “\(folderName)”, the working folder you had open last time — turn Plantoir on in System Settings ▸ Privacy & Security ▸ Files and Folders, or choose the folder again."
    }

    static func outsideHome(folderName: String) -> String {
        return "The working folder Plantoir had open last time, “\(folderName)”, is not inside your home folder, so Plantoir cannot build websites from it. " + WorkingFolderReachWording.whatToDo
    }

    static func coursesOutsideHome(folderName: String) -> String {
        return "The working folder Plantoir had open last time, “\(folderName)”, keeps its courses outside your home folder, so Plantoir cannot build websites from it. " + WorkingFolderReachWording.whatToDoForCourses
    }

    static func sentence(for reason: RememberedFolder.Reason, folderName: String) -> String {
        switch reason {
        case .gone:
            return gone(folderName: folderName)
        case .inTrash:
            return inTrash(folderName: folderName)
        case .driveNotConnected:
            return driveNotConnected(folderName: folderName)
        case .unreadable:
            return unreadable(folderName: folderName)
        case .outsideHome:
            return outsideHome(folderName: folderName)
        case .coursesOutsideHome:
            return coursesOutsideHome(folderName: folderName)
        }
    }
}

/// Why the folder a window was about to open is not open: the one slot the
/// picker (or, for a window that keeps its folder, an alert) reads.
nonisolated struct FolderNotOpened: Equatable, Sendable {

    // MARK: - Types

    enum How: Equatable, Sendable {
        /// Chosen in the picker (only ever refused for being out of reach).
        case chosen
        /// Remembered from last time.
        case remembered
    }

    // MARK: - Stored properties

    let how: How
    let reason: RememberedFolder.Reason
    let folderPath: String
    let folderName: String

    /// True when it is said in an alert rather than on the picker: a folder
    /// chosen from a window that keeps showing its courses. Decided when the
    /// refusal happens, so the answer does not change under it afterwards.
    var isShownAsAlert: Bool = false

    // MARK: - Computed properties

    /// The first, bold sentence — nil for a remembered folder, whose whole
    /// explanation is `detail`.
    var headline: String? {
        if how == .remembered {
            return nil
        }
        if reason == .coursesOutsideHome {
            return WorkingFolderReachWording.coursesHeadline(folderName: folderName)
        }
        return WorkingFolderReachWording.headline(folderName: folderName)
    }

    /// What is said under the headline, or on its own.
    var detail: String {
        if how == .chosen {
            if reason == .coursesOutsideHome {
                return WorkingFolderReachWording.whatToDoForCourses
            }
            return WorkingFolderReachWording.whatToDo
        }
        return ReopenWording.sentence(for: reason, folderName: folderName)
    }

    /// Whether to show the folder's path bar above the words: only for a
    /// folder that is THERE. For a gone, trashed or unplugged one the path
    /// bar's crumbs would be wrong or dead, and the name in the sentence is
    /// enough.
    var showsPathBar: Bool {
        return reason == .outsideHome || reason == .coursesOutsideHome
    }
}
