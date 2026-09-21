import Foundation

/// Walking a course folder, and copying it somewhere else a file at a time.
///
/// Split out from `ReferenceCopier` — which copies a course that is already
/// in this working folder, where everything is small and local and one
/// `copyItem` of each top-level folder is the whole job — because an IMPORT
/// reads somebody's old folder, and that folder may be on an external disk, a
/// network share or a drive that has to spin up. Measured on this Mac: the
/// real ICS4U's 485 MB of media copied in **0.09 s** within the same APFS
/// volume, because the file system clones rather than copies. The same bytes
/// off a USB 2 disk are minutes. So the copy reports progress, can be
/// cancelled between files, and runs off the main actor — all three of which
/// need the file list in hand before the copying starts.
///
/// **`nonisolated`, deliberately**: every function here is called from a
/// detached task, and nothing it touches belongs to the interface.
nonisolated enum ReferenceTreeCopier {

    // MARK: - Types

    /// One thing to copy.
    struct Item: Sendable, Equatable {

        // MARK: - Stored properties

        /// Where it sits inside the course — `Media/diagram.png`.
        let relativePath: String

        /// Folders are made rather than copied, so the order matters: the
        /// walk lists a folder before anything inside it.
        let isDirectory: Bool

        /// Zero for a folder and for a symlink.
        let byteCount: Int64

        /// When it was last changed, for the school-year proposal. Nil when
        /// the file system would not say.
        let modified: Date?
    }

    /// What one walk found, for the sheet to show before anything is copied.
    struct Survey: Sendable {

        // MARK: - Stored properties

        let items: [Item]
        let fileCount: Int
        let byteCount: Int64
        let pageCount: Int

        /// The school year each page was last changed in — the raw material
        /// for `ReferenceImportSource.suggestedSchoolYear`.
        let pageYears: [Int]

        /// The names that were left behind, deduplicated, in the order they
        /// were met. What the summary tells the teacher was not copied.
        let leftBehind: [String]
    }

    /// Why a copy stopped.
    enum Trouble: LocalizedError, Equatable {
        case couldNotCopy(name: String, reason: String)

        // MARK: - Computed properties

        var errorDescription: String? {
            switch self {
            case .couldNotCopy(let name, let reason):
                return "\(name) could not be copied: \(reason)"
            }
        }
    }

    // MARK: - Functions

    /// Every file and folder that will be copied, in the order they must be
    /// made, with everything left behind already gone.
    ///
    /// **A name in `leftBehindNames` is skipped WITHOUT being looked
    /// inside**, and that is the whole reason this walk is hand-written
    /// rather than an enumerator with a filter. On a folder made by an older
    /// Plantoir, `.merged_output` is a real directory holding last year's
    /// entire built website — measured at 1.9 GB per course, four fifths of
    /// what is on disk — and merely not COPYING it while still walking it
    /// would cost more time than copying the course.
    ///
    /// Symlinks are copied as links and never followed: today's
    /// `.merged_output` is one, pointing out of the working folder
    /// altogether, and following it would copy the built site back into the
    /// course it came from.
    static func walk(courseAt courseURL: URL, leavingBehind leftBehindNames: Set<String>) -> Survey {
        var items: [Item] = []
        var leftBehind: [String] = []
        var fileCount: Int = 0
        var byteCount: Int64 = 0
        var pageCount: Int = 0
        var pageYears: [Int] = []

        ReferenceTreeCopier.walk(
            folderAt: courseURL,
            relativePath: "",
            leftBehindNames: leftBehindNames,
            items: &items,
            leftBehind: &leftBehind
        )

        for item in items where !item.isDirectory {
            fileCount += 1
            byteCount += item.byteCount
            if item.relativePath.hasSuffix(".md") {
                pageCount += 1
                if let modified = item.modified {
                    // `CalendarDay.today(_:)` is "the calendar day this
                    // moment falls on, in the teacher's own time zone" — the
                    // day they would name if asked. It reads oddly of a date
                    // in the past and it is the right function: a page
                    // changed late on 31 July must not slide into August and
                    // propose the wrong school year.
                    let dayItChanged: CalendarDay = CalendarDay.today(modified)
                    pageYears.append(SchoolYear.startingYear(on: dayItChanged))
                }
            }
        }

        return Survey(
            items: items,
            fileCount: fileCount,
            byteCount: byteCount,
            pageCount: pageCount,
            pageYears: pageYears,
            leftBehind: leftBehind
        )
    }

    /// The same walk, for the callers that want only the numbers.
    static func survey(courseAt courseURL: URL, leavingBehind leftBehindNames: Set<String>) -> Survey {
        return ReferenceTreeCopier.walk(courseAt: courseURL, leavingBehind: leftBehindNames)
    }

    /// Copies what the walk found into a folder that does not exist yet.
    ///
    /// **Nothing in the source is opened for writing, renamed or removed.**
    /// The source may be the teacher's only copy of last year, and an import
    /// that damaged it would be unforgivable in a way a failed import is not.
    ///
    /// Cancellation is checked before each item, so the most that is left
    /// half-made is one file — and the caller removes the whole destination
    /// on the way out, which it can do because nothing has been locked yet.
    ///
    /// `progress` is handed the running byte count, no more often than every
    /// `reportingEveryBytes`, plus once at the end. It is called on whatever
    /// thread the copy is running on, so a caller that touches the interface
    /// hops to the main actor itself.
    /// **`async` and `nonisolated`, which is what puts it off the main
    /// actor**: Swift runs a `nonisolated async` function on the shared
    /// executor rather than on the caller's actor, so the window keeps
    /// drawing while a slow disk is read — and because it is an ordinary
    /// child of the calling task rather than a detached one, `Task.cancel()`
    /// on the import reaches the loop below. A detached task would not be
    /// cancelled by it, which is the trap this comment exists for.
    static func copy(
        _ survey: Survey,
        from courseURL: URL,
        into destinationURL: URL,
        reportingEveryBytes: Int64 = 4 * 1024 * 1024,
        progress: @Sendable (Int64) -> Void
    ) async throws {
        let fileManager: FileManager = FileManager.default
        var copiedBytes: Int64 = 0
        var reportedBytes: Int64 = 0

        for item in survey.items {
            try Task.checkCancellation()

            let source: URL = courseURL.appendingPathComponent(item.relativePath)
            let destination: URL = destinationURL.appendingPathComponent(item.relativePath)
            do {
                if item.isDirectory {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                } else {
                    try fileManager.copyItem(at: source, to: destination)
                    copiedBytes += item.byteCount
                }
            } catch {
                throw Trouble.couldNotCopy(
                    name: item.relativePath, reason: error.localizedDescription
                )
            }

            if copiedBytes - reportedBytes >= reportingEveryBytes {
                reportedBytes = copiedBytes
                progress(copiedBytes)
            }
        }

        progress(copiedBytes)
    }

    // MARK: - Private helpers

    /// One folder, then everything in it. Folders come before their contents
    /// so the copy can make each one before writing into it.
    private static func walk(
        folderAt folderURL: URL,
        relativePath: String,
        leftBehindNames: Set<String>,
        items: inout [Item],
        leftBehind: inout [String]
    ) {
        let fileManager: FileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else {
            return
        }

        var sorted: [URL] = children
        sorted.sort { first, second in
            return first.lastPathComponent < second.lastPathComponent
        }

        for child in sorted {
            let name: String = child.lastPathComponent
            if leftBehindNames.contains(name) {
                var alreadyNoted: Bool = false
                for noted in leftBehind where noted == name {
                    alreadyNoted = true
                }
                if !alreadyNoted {
                    leftBehind.append(name)
                }
                continue
            }

            let childPath: String = relativePath.isEmpty ? name : relativePath + "/" + name
            let values: URLResourceValues? = try? child.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
            )

            // A symlink is copied AS a link: `copyItem` copies the link
            // itself, so nothing is followed and nothing outside the course
            // is read.
            if values?.isSymbolicLink == true {
                items.append(Item(
                    relativePath: childPath, isDirectory: false, byteCount: 0, modified: nil
                ))
                continue
            }

            if values?.isDirectory == true {
                items.append(Item(
                    relativePath: childPath, isDirectory: true, byteCount: 0, modified: nil
                ))
                ReferenceTreeCopier.walk(
                    folderAt: child,
                    relativePath: childPath,
                    leftBehindNames: leftBehindNames,
                    items: &items,
                    leftBehind: &leftBehind
                )
                continue
            }

            var byteCount: Int64 = 0
            if let size = values?.fileSize {
                byteCount = Int64(size)
            }
            items.append(Item(
                relativePath: childPath,
                isDirectory: false,
                byteCount: byteCount,
                modified: values?.contentModificationDate
            ))
        }
    }
}
