import Foundation

/// How much space a working folder's backups take — measured, never guessed
/// (issue #242).
///
/// **Why this exists.** A teacher's own backups are never pruned (Russell's
/// decision, 2026-09-21: a backup made on purpose before a risky change should
/// not vanish because ten more were made after it), and each one carries the
/// whole course, Media included — measured at 467 MB for a real course. So the
/// space has to be VISIBLE, per course and in total, or a teacher who backs up
/// weekly finds tens of gigabytes gone at the end of a term with nothing that
/// told them.
///
/// **The LOGICAL size, never the size on this disk.** A working folder kept in
/// iCloud Drive can have its backups evicted to the cloud, and an evicted file
/// takes almost nothing on this disk while costing its whole size in the
/// teacher's iCloud storage — and costing it again on this disk the moment it
/// is restored. Measured on the sparse shape of an evicted file: logical
/// 244.84 GB, on disk "Zero KB". `fileSize` is the logical size;
/// `totalFileAllocatedSize` is the on-disk one and would tell that teacher
/// their backups take nothing. `sizeIsLogical` in
/// `contracts/course-management.json` → `backups` carries the rule.
nonisolated enum BackupSizes {

    // MARK: - Stored properties

    /// Whether the last measurement ran on the main thread.
    ///
    /// Written by every measurement and read by exactly one test — the seam
    /// `CoursePageCopier.lastPassRanOnTheMainThread` is, for the same reason:
    /// `@concurrent` is an annotation that can be lost in an edit without
    /// anything failing to compile, and a measurement that silently moved
    /// back onto the main thread passes every other assertion. Nothing in the
    /// product reads it.
    nonisolated(unsafe) static var lastPassRanOnTheMainThread: Bool?

    // MARK: - Functions

    /// The logical size of each file, in bytes, keyed by its path — the key
    /// `BackupItem.id` is. A file that cannot be read (deleted meanwhile, a
    /// volume gone) is left out rather than counted as nothing.
    ///
    /// **`@concurrent`, and that attribute is load-bearing**: this target
    /// builds with `SWIFT_APPROACHABLE_CONCURRENCY`, under which a plain
    /// `nonisolated async` function runs on its CALLER's actor — the main one,
    /// here. Measured cheap (23 real zips in 12.2 ms cold; 500 sparse 467 MB
    /// zips in 3.4 ms), but a working folder on a slow or network volume is not
    /// this Mac's SSD, and a sidebar that waits on a remote `stat` per backup
    /// is a window that cannot draw.
    @concurrent
    static func measure(_ fileURLs: [URL]) async -> [String: Int64] {
        BackupSizes.noteTheThread()
        var sizes: [String: Int64] = [:]
        for fileURL in fileURLs {
            if let size = BackupSizes.logicalSize(of: fileURL) {
                sizes[fileURL.path] = size
            }
        }
        return sizes
    }

    /// Reads the thread from a SYNCHRONOUS context, which is the honest place
    /// to ask: `Thread.isMainThread` is unavailable from an async function.
    static func noteTheThread() {
        BackupSizes.lastPassRanOnTheMainThread = Thread.isMainThread
    }

    /// One file's logical size, in bytes, or nil when it cannot be read.
    static func logicalSize(of fileURL: URL) -> Int64? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    /// "105.6 MB" — the way Finder writes a file's size, so the number a
    /// teacher reads here is the number they see when they look.
    static func description(ofBytes bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// What the backups take, per course and in total — the numbers the Backups
/// header and the All Backups pane show.
///
/// Counts backups only. Archives and the setup wizard's automatic zips share
/// `_backups/`, but they are not in the Backups list, cannot be deleted from
/// it, and are never offered for deletion there — so counting them would
/// state a total the teacher cannot act on. `BackupItem.from` decides what a
/// backup is, as it does everywhere else.
struct BackupSpace: Equatable {

    // MARK: - Types

    /// One course's share.
    struct CourseShare: Equatable {
        let courseCode: String
        let count: Int
        let bytes: Int64
    }

    // MARK: - Stored properties

    /// Each course that has backups, in course-code order.
    let courses: [CourseShare]

    /// Every backup's size added together.
    let totalBytes: Int64

    /// How many backups there are.
    let totalCount: Int

    /// Whether every backup has been measured. A total missing some is not
    /// shown, because a number that is quietly too small is worse than none.
    let isComplete: Bool

    /// How many backups a FINISHED measurement could not size — a zip deleted
    /// in Finder between listing and measuring, or one that cannot be read.
    /// They are left out of the total and said so beside each one, rather
    /// than leaving "Working out…" up for a measurement that has ended.
    let unsizedCount: Int

    // MARK: - Functions

    /// The space `items` take, from sizes keyed by `BackupItem.id`.
    ///
    /// `measured` is every backup a finished measurement LOOKED at, whether or
    /// not it could size it; a backup in it with no size is unsized rather than
    /// still to come. Nil means "only what has a size was looked at".
    static func of(
        _ items: [BackupItem],
        sizes: [String: Int64],
        measured: Set<String>? = nil
    ) -> BackupSpace {
        var bytesByCourse: [String: Int64] = [:]
        var countByCourse: [String: Int] = [:]
        var totalBytes: Int64 = 0
        var measuredCount: Int = 0
        var unsizedCount: Int = 0
        for item in items {
            countByCourse[item.courseCode, default: 0] += 1
            guard let size = sizes[item.id] else {
                if let measured, measured.contains(item.id) {
                    unsizedCount += 1
                    measuredCount += 1
                }
                continue
            }
            bytesByCourse[item.courseCode, default: 0] += size
            totalBytes += size
            measuredCount += 1
        }

        var courseCodes: [String] = []
        for code in countByCourse.keys {
            courseCodes.append(code)
        }
        courseCodes.sort()

        var courses: [CourseShare] = []
        for code in courseCodes {
            courses.append(CourseShare(
                courseCode: code,
                count: countByCourse[code] ?? 0,
                bytes: bytesByCourse[code] ?? 0
            ))
        }
        return BackupSpace(
            courses: courses,
            totalBytes: totalBytes,
            totalCount: items.count,
            isComplete: measuredCount == items.count,
            unsizedCount: unsizedCount
        )
    }
}
