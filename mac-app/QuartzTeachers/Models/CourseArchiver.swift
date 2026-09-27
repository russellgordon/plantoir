import Foundation

/// Removes a course or one of its sections from the working folder —
/// but never destroys the content: the folder is zipped into
/// `courses/_backups/<CODE>/` first, matching the archive the setup
/// wizard writes before it changes a course.
enum CourseArchiver {

    // MARK: - Functions

    /// How many of the ASSISTANT's backups of one course are kept.
    ///
    /// A course full of images makes a large zip, and the assistant saves one
    /// per conversation whether or not anybody asked for it, so without a
    /// limit a term of chats fills a disk with copies of copies.
    ///
    /// A teacher's OWN backups are never counted here and never pruned. They
    /// made those on purpose; deciding on their behalf that a backup from
    /// last month has expired is not the app's call to make.
    static let mostBackupsKept: Int = 5

    /// Saves a copy of an entire course — and touches nothing: the course
    /// stays exactly where it is. Made on purpose before risky editing so
    /// there is always a way back. Returns the backup that was written.
    ///
    /// The name (`<CODE>_backup_<timestamp>.zip`) is what separates a
    /// backup from an archive in the shared `_backups` folder, and who made
    /// it rides in the same name — see `BackupMaker`.
    ///
    /// The oldest backups of this course are pruned afterwards, so the
    /// folder settles at `mostBackupsKept` instead of growing forever — with
    /// one exception, added with the calendar fix: a backup whose stamp
    /// cannot be true is neither counted nor deleted. See `pruneBackups`.
    ///
    /// **Async, and the zip runs off the main actor** (#351): every zip in
    /// the app goes through `zipping`, which is `@concurrent`. The course's
    /// folder and code are read HERE, on the caller's actor, and only those
    /// cross; pruning comes back to this actor afterwards, because it is a
    /// directory listing and a few deletes, measured in milliseconds.
    @discardableResult
    static func backUpCourse(
        _ course: Course,
        coursesDirectoryURL: URL,
        madeBy maker: BackupMaker = .teacher
    ) async throws -> URL {
        let backupURL: URL = try await backingUp(
            courseDirectoryPath: course.directoryURL.path,
            code: course.code,
            coursesDirectoryPath: coursesDirectoryURL.path,
            nameSuffix: maker.nameSuffix
        )
        pruneBackups(forCourseCode: course.code, coursesDirectoryURL: coursesDirectoryURL)
        return backupURL
    }

    /// Deletes the oldest backups of one course until only
    /// `mostBackupsKept` of them are left — counting only those whose stamp
    /// could be true, since the sort that decides which are "oldest" is a
    /// sort on the date in the file's NAME.
    ///
    /// Only backups: archives (`<CODE>_<timestamp>.zip`) and the setup
    /// wizard's automatic zips (`<timestamp>.zip`) share this folder, and
    /// deleting one of those would throw away the only copy of something a
    /// teacher deliberately put away. `BackupItem.from` accepts nothing but
    /// this convention's own names, so asking it is the whole safeguard.
    static func pruneBackups(forCourseCode courseCode: String, coursesDirectoryURL: URL) {
        let backupsURL: URL = coursesDirectoryURL
            .appendingPathComponent("_backups")
            .appendingPathComponent(courseCode)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: backupsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        // ONLY the assistant's own backups are pruned.
        //
        // A teacher's backup is a decision — they pressed Back Up because they
        // were about to do something they were unsure of, or the app saved one
        // on their behalf before adding a section. Deleting that on a schedule
        // they never agreed to is the app overruling them about their own
        // work. The assistant's are different in kind: it makes one per
        // conversation whether or not anybody asked, so it is the assistant's
        // job to clear up after itself.
        //
        // A consequence worth knowing: the five kept are five ASSISTANT
        // backups. A teacher with twenty of their own keeps all twenty, and
        // they do not crowd out the assistant's five.
        var backups: [BackupItem] = []
        for fileURL in contents {
            guard let backup = BackupItem.from(fileURL: fileURL, courseCode: courseCode) else {
                continue
            }
            guard case .assistant = backup.maker else {
                continue
            }
            // A stamp that cannot be true is not allowed to decide what gets
            // DELETED. `ArchiveStamp` still reads such a name — a zip carried
            // from a Mac whose calendar this one does not use, say — so the
            // teacher can see it and restore it; but its date is the one
            // thing about it that is known to be wrong, and this list is
            // sorted by date before the tail of it is thrown away. A copy
            // stamped 2569 would sort as the NEWEST thing in the folder and
            // quietly take a real backup's place among the five that are
            // kept. Left out, it is never counted and never deleted.
            guard ArchiveStamp.couldHaveBeenStamped(backup.backedUpAt) else {
                continue
            }
            backups.append(backup)
        }
        if backups.count <= mostBackupsKept {
            return
        }

        // Newest first. Two backups made in the same second are ordered by
        // name, so the answer is the same every time it is asked.
        backups.sort { first, second in
            if first.backedUpAt == second.backedUpAt {
                return first.fileURL.lastPathComponent > second.fileURL.lastPathComponent
            }
            return first.backedUpAt > second.backedUpAt
        }

        var keptSoFar: Int = 0
        for backup in backups {
            keptSoFar += 1
            if keptSoFar > mostBackupsKept {
                try? FileManager.default.removeItem(at: backup.fileURL)
            }
        }
    }

    /// Writes an archive of an entire course folder without removing it —
    /// for restores, which replace the course's CONTENTS in place so
    /// Obsidian's file watcher (anchored to the folder) keeps up.
    /// Returns the archive that was written.
    @discardableResult
    static func archiveCourse(_ course: Course, coursesDirectoryURL: URL) async throws -> URL {
        return try await zipping(
            folderPath: course.directoryURL.path,
            archiveName: timestampedName(prefix: course.code),
            courseCode: course.code,
            coursesDirectoryPath: coursesDirectoryURL.path
        )
    }

    /// Archives and removes an entire course folder.
    /// Returns the archive that was written.
    @discardableResult
    static func archiveAndRemoveCourse(_ course: Course, coursesDirectoryURL: URL) async throws -> URL {
        let archiveURL: URL = try await archiveCourse(course, coursesDirectoryURL: coursesDirectoryURL)
        try FileManager.default.removeItem(at: course.directoryURL)
        // The built website lives OUTSIDE the working folder now, so removing
        // the course folder no longer removes it — see `BuildOutputLocation`.
        // Two reasons it has to go with the course: it is otherwise invisible
        // litter in Application Support that nothing will ever name again, and
        // a course of the same code restored later would find a built site
        // older than its own pages and be told it was up to date.
        BuildOutputLocation.discardBuild(
            forWorkingFolder: coursesDirectoryURL.deletingLastPathComponent(),
            courseCode: course.code
        )
        return archiveURL
    }

    /// Archives and removes one section folder, and takes that section
    /// out of the course's saved settings so it stops being listed.
    @discardableResult
    static func archiveAndRemoveSection(
        _ sectionNumber: Int,
        from course: Course,
        coursesDirectoryURL: URL
    ) async throws -> URL {
        let sectionURL: URL = course.sectionDirectoryURL(forSection: sectionNumber)
        let archiveURL: URL = try await zipping(
            folderPath: sectionURL.path,
            archiveName: timestampedName(prefix: "\(course.code)-section\(sectionNumber)"),
            courseCode: course.code,
            coursesDirectoryPath: coursesDirectoryURL.path
        )
        if FileManager.default.fileExists(atPath: sectionURL.path) {
            try FileManager.default.removeItem(at: sectionURL)
        }
        // This section's built website goes with it, for the same reason the
        // whole course's does: a section restored later carries the timestamps
        // it had when it was archived, which can be OLDER than the site built
        // from it — so a build left standing would read as up to date and
        // publish pages the teacher had already replaced.
        BuildOutputLocation.discardSectionBuild(
            forWorkingFolder: coursesDirectoryURL.deletingLastPathComponent(),
            courseCode: course.code,
            sectionNumber: sectionNumber
        )

        var remainingSections: [Int] = []
        for existingSection in course.sectionNumbers {
            if existingSection != sectionNumber {
                remainingSections.append(existingSection)
            }
        }
        course.configuration.setSectionNumbers(remainingSections)
        try course.configuration.write(to: course.configFileURL)

        return archiveURL
    }

    /// Things that are rebuilt rather than written, and so are left out of
    /// an archive. `.merged_output` is the important one: it holds a whole
    /// Quartz checkout with its dependencies, which dwarfs the course a
    /// teacher actually wrote and can always be produced again.
    ///
    /// The same list the setup wizard uses for its own backups.
    nonisolated static let excludedFromArchives: [String] = [
        ".merged_output",
        "node_modules",
        ".git",
        ".quartz-cache",
        ".cache",
        "dist",
        "build",
        "out",
        "__pycache__",
        ".DS_Store",
    ]

    /// The same backup as `backUpCourse`, for a caller that has a FOLDER
    /// rather than a loaded course — without the pruning, which a caller that
    /// wants it does back on its own actor.
    ///
    /// **A real backup takes real time.** Measured on Russell's ICS4U with
    /// this very command: **9.7 s and 467 MB**, because `Media` is not in
    /// `excludedFromArchives` and 487 MB of pictures are zipped every time.
    /// `Course` is `@Observable` and not `Sendable`, so the folder and the
    /// code are what cross rather than the course itself.
    ///
    /// `nameSuffix` is `BackupMaker.nameSuffix`, read by the caller: empty
    /// for a teacher's backup, which is never pruned — see `pruneBackups`.
    @concurrent
    static func backingUp(
        courseDirectoryPath: String,
        code: String,
        coursesDirectoryPath: String,
        nameSuffix: String = ""
    ) async throws -> URL {
        return try await zipping(
            folderPath: courseDirectoryPath,
            archiveName: timestampedName(prefix: "\(code)_backup", suffix: nameSuffix),
            courseCode: code,
            coursesDirectoryPath: coursesDirectoryPath
        )
    }

    /// Whether the most recent zip ran on the main thread. Written by
    /// `archive` — the one function that runs `/usr/bin/zip`, so no path to
    /// a zip goes unobserved — and READ by tests only (#351), the same seam
    /// `CoursePageCopier.lastPassRanOnTheMainThread` is: `@concurrent` is an
    /// annotation an edit can lose without anything failing to compile.
    /// Nothing in the product reads it.
    nonisolated(unsafe) static var lastZipRanOnTheMainThread: Bool?

    /// **The one door every zip goes through, and it is off the main actor**
    /// (#351).
    ///
    /// `@concurrent`, and the attribute is load-bearing: this target builds
    /// with `SWIFT_APPROACHABLE_CONCURRENCY`, under which a plain
    /// `nonisolated async` function runs on its CALLER's actor. Until #351
    /// every zip ran on the main thread, and `Process.waitUntilExit` spins a
    /// nested run loop there that re-enters SwiftUI's transaction flush:
    /// approving an assistant change held the window for up to two minutes
    /// (#154's samples: 726 of 732 main-thread samples in
    /// `NSHostingView.beginTransaction`, 93 busy seconds in 122) — on a
    /// fixture course a few kilobytes big, so it was the re-entered run
    /// loop, not the size of the zip. Paths and names cross, never a
    /// `Course`.
    @concurrent
    private static func zipping(
        folderPath: String,
        archiveName: String,
        courseCode: String,
        coursesDirectoryPath: String
    ) async throws -> URL {
        return try archive(
            folderURL: URL(fileURLWithPath: folderPath),
            named: archiveName,
            forCourseCode: courseCode,
            coursesDirectoryURL: URL(fileURLWithPath: coursesDirectoryPath)
        )
    }

    /// Zips a folder into `courses/_backups/<CODE>/<name>.zip`.
    ///
    /// Synchronous and private: the only caller is `zipping`, which is what
    /// keeps it off the main actor.
    nonisolated private static func archive(
        folderURL: URL,
        named archiveName: String,
        forCourseCode courseCode: String,
        coursesDirectoryURL: URL
    ) throws -> URL {
        CourseArchiver.lastZipRanOnTheMainThread = Thread.isMainThread
        let backupsURL: URL = coursesDirectoryURL
            .appendingPathComponent("_backups")
            .appendingPathComponent(courseCode)
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        let archiveURL: URL = backupsURL.appendingPathComponent(archiveName)

        // Zipped with the system's own tool rather than NSFileCoordinator,
        // because this one can leave things out — and a course's built
        // output is many times the size of the course itself.
        var arguments: [String] = ["-r", "-q", "-X", archiveURL.path, folderURL.lastPathComponent]
        arguments.append("-x")
        for name in excludedFromArchives {
            arguments.append("*/\(name)/*")
            arguments.append("*/\(name)")
        }

        let zipper: Process = Process()
        zipper.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipper.arguments = arguments
        zipper.currentDirectoryURL = folderURL.deletingLastPathComponent()
        let errors: Pipe = Pipe()
        zipper.standardError = errors
        try zipper.run()
        zipper.waitUntilExit()
        if zipper.terminationStatus != 0 {
            let data: Data = errors.fileHandleForReading.readDataToEndOfFile()
            let reason: String = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(
                domain: "CourseArchiver",
                code: Int(zipper.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Could not write the archive: \(reason.trimmingCharacters(in: .whitespacesAndNewlines))"]
            )
        }
        return archiveURL
    }

    /// "ICS3U_2026-08-09_141530.zip", or with a suffix,
    /// "ICS3U_backup_2026-08-09_141530_assistant-section1.zip".
    ///
    /// The moment is spelled by `ArchiveStamp`, which is also what reads it
    /// back — a writer with a formatter of its own is how the two came to
    /// disagree in the first place.
    nonisolated private static func timestampedName(prefix: String, suffix: String = "") -> String {
        return "\(prefix)_\(ArchiveStamp.text(for: Date()))\(suffix).zip"
    }
}
