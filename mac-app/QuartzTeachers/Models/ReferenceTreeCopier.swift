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
/// **Names are carried as the bytes the file system gave, and that is the
/// whole reason this file talks to POSIX instead of to `FileManager`.**
/// A name is read with `readdir`, kept as bytes, and handed to `copyfile()`
/// as bytes. Rebuilding a destination from `URL.lastPathComponent` — which is
/// what this file did until 2026-09-20 — passes the name through
/// `URL`'s file-system representation, and that DECOMPOSES it: measured, a
/// file created as `App\u{00e9}tit.jpg` (`c3 a9`) arrived as
/// `Appe\u{0301}tit.jpg` (`65 cc 81`).
///
/// That is not cosmetic. The page that embeds the image still spells the name
/// the old way, so the embed no longer resolves, and Quartz then emits neither
/// the `<img>` nor the asset — the picture simply vanishes from the built
/// site, with no error anywhere. Four files in Russell's own ICS4U are of this
/// shape. Measured, same source name, three ways:
///
/// | how the copy is made | name on disk afterwards |
/// |---|---|
/// | `copyItem` of a whole DIRECTORY | its CONTENTS unchanged, its own NAME **decomposed** |
/// | per-file `copyItem` to a REBUILT `URL` | **decomposed** |
/// | `readdir` bytes → `copyfile()` | unchanged, both forms |
///
/// The first row is the one that was written down wrongly twice: copying a
/// directory preserves what is inside it, and the entry name itself still
/// goes through `appendingPathComponent`. That is why "Keep a Copy for
/// Reference…" comes through here too (`copySynchronously`) rather than
/// keeping a loop of its own.
///
/// **`nonisolated` and `@concurrent`, deliberately**: see `copy`.
nonisolated enum ReferenceTreeCopier {

    // MARK: - Types

    /// One thing to copy.
    struct Item: Sendable, Equatable {

        // MARK: - Stored properties

        /// Where it sits inside the course — `Media/diagram.png` — as the
        /// BYTES the file system gave, joined with `/`. Never a `String`:
        /// the bytes are the name, and anything else is a re-spelling of it.
        let relativePath: [UInt8]

        /// Folders are made rather than copied, so the order matters: the
        /// walk lists a folder before anything inside it.
        let isDirectory: Bool

        /// Zero for a folder and for a symlink.
        let byteCount: Int64

        /// The source's permissions, so a copied folder is as open as the one
        /// it came from. Files carry their own through `copyfile`.
        let mode: mode_t

        /// When it was last changed, for the school-year proposal. Nil when
        /// the file system would not say.
        let modified: Date?

        // MARK: - Computed properties

        /// The name as text, for a message or a suffix test. Read-only, and
        /// never used to build a path.
        var text: String {
            return String(decoding: relativePath, as: UTF8.self)
        }

        /// True for a symbolic link, which the walk lists and never follows.
        ///
        /// Asked by the older-layout import (`OlderCourseLayout.plan`), which
        /// must never copy one: a link in a reference course is a door out of
        /// it that the lock and the census cannot see through. See
        /// `copy(placements:into:reportingEveryBytes:progress:)`.
        var isSymbolicLink: Bool {
            return (mode & S_IFMT) == S_IFLNK
        }
    }

    /// One thing to copy from SOMEWHERE into a course, and where it lands.
    ///
    /// The older-layout import brings a course together from two folders —
    /// the class's own folder and the shared folder beside it — and puts some
    /// of it under a different path (`Thread 1/Day 1.md` becomes
    /// `section1/Thread 1/Day 1.md`). So each item carries the folder it is
    /// read from and the BYTES of the path it is written to; the name is
    /// never rebuilt from text, for the reason at the top of this file.
    struct Placement: Sendable, Equatable {

        // MARK: - Stored properties

        /// The folder `item.relativePath` is read from.
        let sourceRoot: URL

        /// What is copied. A folder is MADE at `destination`, never copied.
        let item: Item

        /// Where it lands inside the new course, as bytes joined with `/`.
        let destination: [UInt8]

        // MARK: - Computed properties

        /// The destination as text, for a message or a test. Never a path.
        var destinationText: String {
            return String(decoding: destination, as: UTF8.self)
        }
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

        /// Folders inside the course that could not be read at all.
        ///
        /// **Never silently skipped.** A folder the old disk will not hand
        /// over contributes no files, and an import that copied none of them
        /// and reported success would be the quiet kind of data loss: the
        /// teacher would find out next year. The course is refused instead,
        /// naming the folder.
        let unreadableFolders: [String]

        /// Which of the paths asked to be left behind (`leavingBehindPaths`,
        /// or `leavingBehindIfALink` that turned out to be a link) were
        /// actually there, in the order the walk met them. The older layouts
        /// count their add-on entries from this (#255).
        let pathsLeftBehind: [String]
    }

    /// Why a copy stopped.
    enum Trouble: LocalizedError, Equatable {
        case couldNotCopy(name: String, reason: String)
        case couldNotRead(name: String)

        // MARK: - Computed properties

        var errorDescription: String? {
            switch self {
            case .couldNotCopy(let name, let reason):
                return "\(name) could not be copied: \(reason)"
            case .couldNotRead(let name):
                return ReferenceImportWording.couldNotReadFolder(folder: name)
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
    ///
    /// **`leavingBehindPaths` is matched against WHERE a thing is, not what
    /// it is called** (#255): `.obsidian/plugins` stays behind while a
    /// teacher's own `Unit 1/plugins` folder of pages comes. Skipped before it
    /// is so much as `lstat`-ed, like a name, so nothing inside it can refuse
    /// the course. `leavingBehindIfALink` is skipped only when `lstat` says it
    /// is a link — a real `.obsidian` comes, a linked one does not. Both
    /// default to empty, and they are separate from `leftBehindNames` on
    /// purpose: a caller overriding the names (the sheet does, and tests do)
    /// cannot drop the add-ons rule by accident. `ObsidianAddOns` says why.
    static func walk(
        courseAt courseURL: URL,
        leavingBehind leftBehindNames: Set<String>,
        leavingBehindPaths leftBehindPaths: Set<String> = [],
        leavingBehindIfALink leftBehindLinks: Set<String> = []
    ) -> Survey {
        var items: [Item] = []
        var unreadable: [String] = []
        var pathsLeftBehind: [String] = []
        var fileCount: Int = 0
        var byteCount: Int64 = 0
        var pageCount: Int = 0
        var pageYears: [Int] = []

        ReferenceTreeCopier.walk(
            folderAt: ReferenceTreeCopier.pathBytes(of: courseURL),
            relativePath: [],
            rules: WalkRules(names: leftBehindNames, paths: leftBehindPaths, links: leftBehindLinks),
            items: &items,
            unreadable: &unreadable,
            pathsLeftBehind: &pathsLeftBehind
        )

        for item in items where !item.isDirectory {
            fileCount += 1
            byteCount += item.byteCount
            if item.text.hasSuffix(".md") {
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
            unreadableFolders: unreadable,
            pathsLeftBehind: pathsLeftBehind
        )
    }

    /// The same walk, for the callers that want only the numbers.
    static func survey(
        courseAt courseURL: URL,
        leavingBehind leftBehindNames: Set<String>,
        leavingBehindPaths leftBehindPaths: Set<String> = [],
        leavingBehindIfALink leftBehindLinks: Set<String> = []
    ) -> Survey {
        return ReferenceTreeCopier.walk(
            courseAt: courseURL,
            leavingBehind: leftBehindNames,
            leavingBehindPaths: leftBehindPaths,
            leavingBehindIfALink: leftBehindLinks
        )
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
    ///
    /// **`@concurrent`, and that attribute is load-bearing.** A plain
    /// `nonisolated async` function would run on its CALLER's actor in this
    /// project, because `project.yml` sets `SWIFT_APPROACHABLE_CONCURRENCY:
    /// YES` — which turns on `NonisolatedNonsendingByDefault`. Measured: the
    /// same function body reports `Thread.isMainThread == true` with that
    /// flag and `false` with `@concurrent`. Without it the loop below holds
    /// the main actor for the whole copy: the progress bar cannot draw and
    /// **the Stop button cannot be clicked at all** — on the slow external
    /// disk this file exists to serve, that is minutes of a frozen window.
    /// `Task.detached` would also leave the main actor and was rejected: it
    /// is not a child of the calling task, so `run?.cancel()` would not reach
    /// the loop. `@concurrent` leaves the actor and stays a child.
    @concurrent
    static func copy(
        _ survey: Survey,
        from courseURL: URL,
        into destinationURL: URL,
        reportingEveryBytes: Int64 = 4 * 1024 * 1024,
        progress: @Sendable (Int64) -> Void
    ) async throws {
        let source: [UInt8] = ReferenceTreeCopier.pathBytes(of: courseURL)
        let destination: [UInt8] = ReferenceTreeCopier.pathBytes(of: destinationURL)
        var copiedBytes: Int64 = 0
        var reportedBytes: Int64 = 0

        for item in survey.items {
            try Task.checkCancellation()
            try ReferenceTreeCopier.copy(item, from: source, into: destination)
            copiedBytes += item.byteCount

            if copiedBytes - reportedBytes >= reportingEveryBytes {
                reportedBytes = copiedBytes
                progress(copiedBytes)
            }
        }

        progress(copiedBytes)
    }

    /// The same copy, without the waiting: no progress and no cancellation,
    /// for the caller that has neither.
    ///
    /// **"Keep a Copy for Reference…" is that caller.** It copies a course
    /// that is already in this working folder, on this volume, so the clone
    /// is instant and there is nothing to watch — but it must carry names the
    /// same way, and until 2026-09-20 it did not: its own loop rebuilt each
    /// destination from `URL.lastPathComponent`, which decomposed the
    /// TOP-LEVEL names (`Theme` with a grave accent came out decomposed)
    /// while preserving everything inside them. One copier with two entry
    /// points, rather than two copiers that agree about most names.
    static func copySynchronously(
        _ survey: Survey,
        from courseURL: URL,
        into destinationURL: URL
    ) throws {
        let source: [UInt8] = ReferenceTreeCopier.pathBytes(of: courseURL)
        let destination: [UInt8] = ReferenceTreeCopier.pathBytes(of: destinationURL)
        for item in survey.items {
            try ReferenceTreeCopier.copy(item, from: source, into: destination)
        }
    }

    /// Copies a list of placements into a folder that exists and is empty.
    ///
    /// The older-layout import's entry point. The same byte-for-byte copy as
    /// `copy(_:from:into:)`, with one difference that is the point of it:
    /// **a symbolic link is REFUSED, never copied.** The planner has already
    /// left every link out (`OlderCourseLayout.plan`), so this should never
    /// fire; it is here so that a future planner bug fails loudly instead of
    /// quietly making a reference course with a live link inside it — one the
    /// lock cannot lock, the census does not count, and the preview cannot
    /// follow out of the working folder. The modern route keeps copying a link
    /// as a link (its only one is `.merged_output`, which is left behind),
    /// deliberately unchanged: see `documentation/09-mac-app.md`.
    ///
    /// `@concurrent` for the same measured reason as `copy(_:from:into:)`.
    @concurrent
    static func copy(
        placements: [Placement],
        into destinationURL: URL,
        reportingEveryBytes: Int64 = 4 * 1024 * 1024,
        progress: @Sendable (Int64) -> Void
    ) async throws {
        let destination: [UInt8] = ReferenceTreeCopier.pathBytes(of: destinationURL)
        var copiedBytes: Int64 = 0
        var reportedBytes: Int64 = 0

        for placement in placements {
            try Task.checkCancellation()
            if placement.item.isSymbolicLink {
                throw Trouble.couldNotCopy(
                    name: placement.item.text,
                    reason: "it points somewhere else rather than holding anything"
                )
            }
            let from: [CChar] = ReferenceTreeCopier.path(
                ReferenceTreeCopier.pathBytes(of: placement.sourceRoot), placement.item.relativePath
            )
            let to: [CChar] = ReferenceTreeCopier.path(destination, placement.destination)
            try ReferenceTreeCopier.copy(
                from: from, to: to, isDirectory: placement.item.isDirectory,
                mode: placement.item.mode, name: placement.destinationText
            )
            copiedBytes += placement.item.byteCount

            if copiedBytes - reportedBytes >= reportingEveryBytes {
                reportedBytes = copiedBytes
                progress(copiedBytes)
            }
        }

        progress(copiedBytes)
    }

    /// The names of the things directly inside a folder, as the BYTES the
    /// file system gave, in a stable order.
    ///
    /// The reading half of this file's rule, for a caller that copies a
    /// handful of named files rather than a whole course — "Copy a Page from
    /// This Course…" resolving a page's pictures against the course's `Media`
    /// folder. Measured on this Mac: `readdir`,
    /// `FileManager.contentsOfDirectory(at:)` → `lastPathComponent` and
    /// `contentsOfDirectory(atPath:)` all hand back the stored bytes
    /// unchanged, so the READ was never the problem — it is the WRITE that
    /// re-spells a name, which is what `create` and `copyFile` below exist
    /// for.
    static func names(inFolderAt folderURL: URL) -> [[UInt8]] {
        guard let directory = opendir(ReferenceTreeCopier.path(
            ReferenceTreeCopier.pathBytes(of: folderURL), []
        )) else {
            return []
        }
        defer { closedir(directory) }

        var found: [[UInt8]] = []
        while let entry = readdir(directory) {
            var name: [UInt8] = []
            let length: Int = Int(entry.pointee.d_namlen)
            withUnsafeBytes(of: entry.pointee.d_name) { raw in
                for index in 0..<length {
                    name.append(raw[index])
                }
            }
            if name == Array(".".utf8) || name == Array("..".utf8) {
                continue
            }
            found.append(name)
        }
        found.sort { first, second in
            return String(decoding: first, as: UTF8.self) < String(decoding: second, as: UTF8.self)
        }
        return found
    }

    /// Writes a NEW file whose name is exactly these bytes, and refuses if
    /// anything is already there.
    ///
    /// **`Data.write(to:options:.withoutOverwriting)` cannot be used for a
    /// name that has to survive**, and that is measured rather than assumed:
    /// building the destination with `appendingPathComponent` passes the name
    /// through `URL`'s file-system representation, which DECOMPOSES it. Same
    /// Mac, same run — a file read back as `41 70 70 c3 a9 …` (NFC) was
    /// written out as `41 70 70 65 cc 81 …` (NFD). A page that embeds the
    /// picture still spells the name the old way, so on a volume that
    /// compares names byte for byte the embed no longer resolves and the
    /// picture vanishes from the built site with no error anywhere.
    ///
    /// `O_EXCL` is the same "never overwrite" guarantee `.withoutOverwriting`
    /// gives, taken from the system call it is built on: there is no
    /// check-then-write window, and a file that appears in between makes this
    /// throw rather than replace.
    static func create(_ data: Data, named nameBytes: [UInt8], inFolderAt folderURL: URL) throws {
        var relative: [UInt8] = []
        relative.append(contentsOf: nameBytes)
        let target: [CChar] = ReferenceTreeCopier.path(
            ReferenceTreeCopier.pathBytes(of: folderURL), relative
        )
        let name: String = String(decoding: nameBytes, as: UTF8.self)

        let descriptor: Int32 = open(target, O_CREAT | O_EXCL | O_WRONLY, 0o644)
        if descriptor < 0 {
            throw Trouble.couldNotCopy(name: name, reason: ReferenceTreeCopier.reason(errno))
        }
        defer { close(descriptor) }

        var written: Int = 0
        let bytes: [UInt8] = Array(data)
        while written < bytes.count {
            let count: Int = bytes.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else {
                    return -1
                }
                return write(descriptor, base + written, bytes.count - written)
            }
            if count <= 0 {
                throw Trouble.couldNotCopy(name: name, reason: ReferenceTreeCopier.reason(errno))
            }
            written += count
        }
    }

    /// Copies one file between two folders, keeping the name's bytes — and
    /// refusing if anything is already at the destination.
    ///
    /// `COPYFILE_CLONE` implies `COPYFILE_EXCL`, measured: a second
    /// `copyfile` onto the same destination returns −1 with `EEXIST` rather
    /// than replacing what is there. So "never overwrite the teacher's
    /// picture" is the system call's own guarantee here, not a check this
    /// code does first.
    static func copyFile(
        named sourceNameBytes: [UInt8],
        fromFolderAt sourceFolderURL: URL,
        into destinationFolderURL: URL,
        as destinationNameBytes: [UInt8]
    ) throws {
        let from: [CChar] = ReferenceTreeCopier.path(
            ReferenceTreeCopier.pathBytes(of: sourceFolderURL), sourceNameBytes
        )
        let to: [CChar] = ReferenceTreeCopier.path(
            ReferenceTreeCopier.pathBytes(of: destinationFolderURL), destinationNameBytes
        )
        if copyfile(from, to, nil, copyfile_flags_t(COPYFILE_CLONE)) != 0 {
            throw Trouble.couldNotCopy(
                name: String(decoding: sourceNameBytes, as: UTF8.self),
                reason: ReferenceTreeCopier.reason(errno)
            )
        }
    }

    /// A `URL` for one named thing inside a folder — for ASKING about it
    /// (size, contents, the locked flag), and NEVER for writing it.
    ///
    /// **This DOES re-spell the name, and that is why nothing writes through
    /// it.** Measured: `URL(fileURLWithPath:)` handed the whole path as one
    /// string decomposes it exactly as `appendingPathComponent` does —
    /// `App\u{00e9}tit` (`c3 a9`) comes back out of `.path` as `65 cc 81`.
    /// A LOOKUP survives that on APFS and HFS+, which compare names without
    /// regard to normalisation, so reading is safe here; a WRITE would land
    /// under the wrong name, which is what `create` and `copyFile` avoid by
    /// appending raw bytes to `pathBytes(of:)`. On a volume that compares
    /// names byte for byte, a read through this would fail — in the safe
    /// direction, since a page that cannot be read back is deleted and
    /// reported.
    static func url(named nameBytes: [UInt8], inFolderAt folderURL: URL) -> URL {
        return URL(fileURLWithPath: folderURL.path + "/" + String(decoding: nameBytes, as: UTF8.self))
    }

    /// One file, one folder or one symlink — the only place bytes become a
    /// path, so the two loops above cannot disagree about a name.
    private static func copy(_ item: Item, from source: [UInt8], into destination: [UInt8]) throws {
        let from: [CChar] = ReferenceTreeCopier.path(source, item.relativePath)
        let to: [CChar] = ReferenceTreeCopier.path(destination, item.relativePath)
        try ReferenceTreeCopier.copy(
            from: from, to: to, isDirectory: item.isDirectory, mode: item.mode, name: item.text
        )
    }

    /// The one place a file is cloned or a folder is made, shared by both
    /// entry points so they cannot disagree about how.
    private static func copy(
        from: [CChar],
        to: [CChar],
        isDirectory: Bool,
        mode: mode_t,
        name: String
    ) throws {
        if isDirectory {
            if mkdir(to, mode & 0o7777) != 0 {
                throw Trouble.couldNotCopy(
                    name: name, reason: ReferenceTreeCopier.reason(errno)
                )
            }
            // `mkdir` is filtered by the process umask, so the folder is made
            // and then given the permissions the source had.
            _ = chmod(to, mode & 0o7777)
            return
        }

        // `copyfile` with the source and destination as BYTES. The name is
        // never re-spelled, `COPYFILE_CLONE` keeps the file system's own fast
        // path (485 MB in 0.09 s on one APFS volume), and it copies a symlink
        // AS a link rather than following it.
        if copyfile(from, to, nil, copyfile_flags_t(COPYFILE_CLONE)) != 0 {
            throw Trouble.couldNotCopy(
                name: name, reason: ReferenceTreeCopier.reason(errno)
            )
        }
    }

    // MARK: - Private helpers

    /// What one walk leaves behind: by name at any depth, by path from the
    /// top of the walk, and by path only when it is a link.
    private struct WalkRules {

        // MARK: - Stored properties

        let names: Set<String>
        let paths: Set<String>
        let links: Set<String>
    }

    /// One folder, then everything in it. Folders come before their contents
    /// so the copy can make each one before writing into it.
    ///
    /// `readdir` rather than `FileManager`, for the names: see the note at
    /// the top of this file.
    private static func walk(
        folderAt folderPath: [UInt8],
        relativePath: [UInt8],
        rules: WalkRules,
        items: inout [Item],
        unreadable: inout [String],
        pathsLeftBehind: inout [String]
    ) {
        guard let directory = opendir(ReferenceTreeCopier.path(folderPath, [])) else {
            var name: String = String(decoding: relativePath, as: UTF8.self)
            if name.isEmpty {
                name = String(decoding: folderPath, as: UTF8.self)
            }
            unreadable.append(name)
            return
        }
        defer { closedir(directory) }

        var children: [[UInt8]] = []
        while let entry = readdir(directory) {
            var name: [UInt8] = []
            let length: Int = Int(entry.pointee.d_namlen)
            withUnsafeBytes(of: entry.pointee.d_name) { raw in
                for index in 0..<length {
                    name.append(raw[index])
                }
            }
            if name == Array(".".utf8) || name == Array("..".utf8) {
                continue
            }
            children.append(name)
        }
        // A stable order, so two walks of the same folder agree and a test
        // can say what it expects.
        children.sort { first, second in
            return String(decoding: first, as: UTF8.self) < String(decoding: second, as: UTF8.self)
        }

        for name in children {
            // Every name on the skip list is ASCII, so comparing the text is
            // exact here however the rest of the tree is spelled.
            if rules.names.contains(String(decoding: name, as: UTF8.self)) {
                continue
            }

            var childRelative: [UInt8] = relativePath
            if !childRelative.isEmpty {
                childRelative.append(ReferenceTreeCopier.separator)
            }
            childRelative.append(contentsOf: name)

            // Where it is, as text — exact for the ASCII paths the rules
            // name. Skipped before `lstat`, so nothing inside is looked at.
            let childText: String = String(decoding: childRelative, as: UTF8.self)
            if rules.paths.contains(childText) {
                pathsLeftBehind.append(childText)
                continue
            }

            var childPath: [UInt8] = folderPath
            childPath.append(ReferenceTreeCopier.separator)
            childPath.append(contentsOf: name)

            var status: stat = stat()
            if lstat(ReferenceTreeCopier.path(childPath, []), &status) != 0 {
                unreadable.append(String(decoding: childRelative, as: UTF8.self))
                continue
            }

            // A symlink is copied AS a link, so nothing is followed and
            // nothing outside the course is read — unless the caller asked for
            // that link to stay behind altogether.
            if (status.st_mode & S_IFMT) == S_IFLNK {
                if rules.links.contains(childText) {
                    pathsLeftBehind.append(childText)
                    continue
                }
                items.append(Item(
                    relativePath: childRelative, isDirectory: false,
                    byteCount: 0, mode: status.st_mode, modified: nil
                ))
                continue
            }

            if (status.st_mode & S_IFMT) == S_IFDIR {
                items.append(Item(
                    relativePath: childRelative, isDirectory: true,
                    byteCount: 0, mode: status.st_mode, modified: nil
                ))
                ReferenceTreeCopier.walk(
                    folderAt: childPath,
                    relativePath: childRelative,
                    rules: rules,
                    items: &items,
                    unreadable: &unreadable,
                    pathsLeftBehind: &pathsLeftBehind
                )
                continue
            }

            items.append(Item(
                relativePath: childRelative,
                isDirectory: false,
                byteCount: Int64(status.st_size),
                mode: status.st_mode,
                modified: Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec))
            ))
        }
    }

    /// `/`.
    private static let separator: UInt8 = 47

    /// A folder's path as bytes.
    ///
    /// From the `String`, not from `URL`'s file-system representation: the
    /// latter is what decomposes a name, and while a LOOKUP survives that on
    /// an APFS volume (which compares names normalisation-insensitively), a
    /// network share or an exFAT disk — exactly where an old working folder
    /// tends to live — does not.
    static func pathBytes(of url: URL) -> [UInt8] {
        return Array(url.path.utf8)
    }

    /// `root` + `/` + `relative`, null-terminated, for POSIX.
    static func path(_ root: [UInt8], _ relative: [UInt8]) -> [CChar] {
        var bytes: [UInt8] = root
        if !relative.isEmpty {
            bytes.append(ReferenceTreeCopier.separator)
            bytes.append(contentsOf: relative)
        }
        var result: [CChar] = []
        for byte in bytes {
            result.append(CChar(bitPattern: byte))
        }
        result.append(0)
        return result
    }

    /// What the system said went wrong, in its own words.
    private static func reason(_ code: Int32) -> String {
        guard let text = strerror(code) else {
            return "error \(code)"
        }
        return String(cString: text)
    }
}
