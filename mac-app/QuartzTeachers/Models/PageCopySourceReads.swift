import Foundation

/// Which courses Copy a Page from This Course… is reading from right now,
/// in this app (#572 implementation review L3).
///
/// A copy pass reads pages and their pictures out of the SOURCE course and
/// takes no `CourseActivity` record, because a copy that only reads must not
/// make the source busy for its own previews. A replace renames the source's
/// folder, so it asks this as well: a reference course being read from is
/// busy to a replace and to nothing else.
@MainActor
enum PageCopySourceReads {

    // MARK: - Stored properties

    /// How many passes are reading each course folder, by its canonical path.
    static var readers: [String: Int] = [:]

    // MARK: - Functions

    /// A pass has started reading from the course in `folderURL`.
    static func begin(_ folderURL: URL) {
        let key: String = FolderIdentity.canonicalPath(folderURL.path)
        readers[key] = (readers[key] ?? 0) + 1
    }

    /// That pass has finished, however it finished.
    static func end(_ folderURL: URL) {
        let key: String = FolderIdentity.canonicalPath(folderURL.path)
        let left: Int = (readers[key] ?? 0) - 1
        if left > 0 {
            readers[key] = left
        } else {
            readers[key] = nil
        }
    }

    /// Whether a pass is reading from the course in `folderURL`.
    static func isReading(_ folderURL: URL) -> Bool {
        return (readers[FolderIdentity.canonicalPath(folderURL.path)] ?? 0) > 0
    }
}
