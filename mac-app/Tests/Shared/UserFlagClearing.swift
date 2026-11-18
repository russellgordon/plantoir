import Darwin
import Foundation

/// Clears the user flags (`uchg` among them) on a folder and everything in
/// it, so the folder can then be removed: nothing inside a locked folder,
/// and no locked file, can be deleted (#978).
///
/// **Walked by file descriptor, so no path is resolved twice.** The folder
/// is opened once with `O_NOFOLLOW | O_DIRECTORY`; every entry in it is
/// looked at with `fstatat(…, AT_SYMLINK_NOFOLLOW)` relative to that open
/// folder, a subfolder is opened with `openat(…, O_NOFOLLOW | O_DIRECTORY)`,
/// and any other entry with `openat(…, O_SYMLINK)`, which opens a link
/// itself and never what it points at. Flags are changed through the
/// descriptor (`fchflags`). So an entry swapped for a link at any moment
/// is either refused (`O_NOFOLLOW` fails on it) or opened as the link: the
/// walk can never be led into the link's target. (Until 2026-11-18 the walk
/// listed folders by path, and a folder swapped for a link between its check
/// and its listing had the flags of the link's whole target cleared.)
///
/// An entry that cannot be opened (a socket, a file with no read
/// permission) keeps its flags; the removal after it then fails on that
/// entry alone, which is the safe way to fail.
///
/// Shared by both test targets: `TemporaryFolders` in the unit suite and
/// `UITestFolders` in the UI target.
enum UserFlagClearing {

    // MARK: - Functions

    /// Clears the flags on the folder at `path` and everything inside it.
    /// Does nothing when `path` is not a real folder (a link to one
    /// included): the open refuses it.
    static func clearFlags(inFolderAtPath path: String) {
        let folderDescriptor: Int32 = open(path, O_RDONLY | O_NOFOLLOW | O_DIRECTORY | O_CLOEXEC)
        if folderDescriptor < 0 {
            return
        }
        fchflags(folderDescriptor, 0)
        clearFlags(insideOpenFolder: folderDescriptor)
        close(folderDescriptor)
    }

    /// Clears the flags on the entry at `path` itself, a link as a link.
    static func clearFlags(onEntryAtPath path: String) {
        let entryDescriptor: Int32 = open(path, O_RDONLY | O_SYMLINK | O_NONBLOCK | O_CLOEXEC)
        if entryDescriptor < 0 {
            return
        }
        fchflags(entryDescriptor, 0)
        close(entryDescriptor)
    }

    /// The names in an open folder, `.` and `..` left out. The folder's
    /// own descriptor stays open: the listing reads through a duplicate.
    static func entryNames(inOpenFolder folderDescriptor: Int32) -> [String] {
        var names: [String] = []
        let listingDescriptor: Int32 = dup(folderDescriptor)
        if listingDescriptor < 0 {
            return names
        }
        guard let listing = fdopendir(listingDescriptor) else {
            close(listingDescriptor)
            return names
        }
        while let entry = readdir(listing) {
            var nameBytes = entry.pointee.d_name
            let nameLength: Int = Int(entry.pointee.d_namlen)
            let name: String = withUnsafeBytes(of: &nameBytes) { (rawBytes: UnsafeRawBufferPointer) -> String in
                return String(decoding: UnsafeRawBufferPointer(rebasing: rawBytes[0..<nameLength]), as: UTF8.self)
            }
            if name != "." && name != ".." {
                names.append(name)
            }
        }
        closedir(listing)
        return names
    }

    /// Clears the flags on everything inside an open folder, depth first.
    static func clearFlags(insideOpenFolder folderDescriptor: Int32) {
        for name in entryNames(inOpenFolder: folderDescriptor) {
            var status: stat = stat()
            if fstatat(folderDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) != 0 {
                continue
            }
            if (status.st_mode & S_IFMT) == S_IFDIR {
                let childDescriptor: Int32 = openat(
                    folderDescriptor, name, O_RDONLY | O_NOFOLLOW | O_DIRECTORY | O_CLOEXEC
                )
                if childDescriptor >= 0 {
                    fchflags(childDescriptor, 0)
                    clearFlags(insideOpenFolder: childDescriptor)
                    close(childDescriptor)
                    continue
                }
            }
            // A file, a link, or a folder swapped for a link since the
            // `fstatat`: opened as itself, never followed.
            let entryDescriptor: Int32 = openat(
                folderDescriptor, name, O_RDONLY | O_SYMLINK | O_NONBLOCK | O_CLOEXEC
            )
            if entryDescriptor >= 0 {
                fchflags(entryDescriptor, 0)
                close(entryDescriptor)
            }
        }
    }
}
