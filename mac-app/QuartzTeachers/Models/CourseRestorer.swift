import Foundation

/// Brings an archived course or section back into the working folder.
///
/// The archive holds the folder itself at its root — `section1/…` or
/// `IZN2O/…` — so restoring is an extract into the right parent. Nothing is
/// ever written over: if something already occupies the destination, the
/// restore stops and says so, because the thing in the way may be newer work.
enum CourseRestorer {

    // MARK: - Types

    /// Why a restore could not go ahead, in words a teacher can act on.
    enum Problem: LocalizedError {
        case courseAlreadyPresent(String)
        case courseMissing(String)
        case sectionAlreadyPresent(String, Int)
        case sectionMissingFromBackup(String, Int)
        case archiveUnreadable(String)

        var errorDescription: String? {
            switch self {
            case .courseAlreadyPresent(let code):
                return "\(code) is already in Courses & Clubs. Remove it first if you want the archived copy back."
            case .courseMissing(let code):
                return "\(code) is not in Courses & Clubs. Restore the course first, then restore this section into it."
            case .sectionAlreadyPresent(let code, let number):
                return "Section \(number) of \(code) already exists. Remove it first if you want the archived copy back."
            case .sectionMissingFromBackup(let code, let number):
                return "That copy of \(code) has no Section \(number) in it, so there is nothing to put back."
            case .archiveUnreadable(let reason):
                return "The archive could not be opened: \(reason)"
            }
        }
    }

    // MARK: - Functions

    /// Throws away the built website of a section whose PAGES have just been
    /// replaced.
    ///
    /// A restored section carries the timestamps it had when it was backed up,
    /// and those can be OLDER than the site that was built from it — so the
    /// freshness check reads "already up to date" and publishing ships the
    /// pages the teacher has just undone. The built site is derived and one
    /// build brings it back; the wrong site on a student's screen does not
    /// come back at all.
    ///
    /// **The staleness is older than the move.** It was true when
    /// `.merged_output` still sat inside the course folder, because a section
    /// restore replaces `section<N>` and never touched the built tree beside
    /// it. Moving the output out did not cause it and does not excuse it.
    private static func discardBuiltSite(
        forSection sectionNumber: Int,
        courseCode: String,
        coursesDirectoryURL: URL
    ) {
        BuildOutputLocation.discardSectionBuild(
            forWorkingFolder: coursesDirectoryURL.deletingLastPathComponent(),
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
    }

    /// Restores one archived item, then removes the archive — the content is
    /// live again, and a list of archived things should not include it.
    static func restore(_ item: ArchivedItem, coursesDirectoryURL: URL, courses: [Course]) throws {
        let fileManager: FileManager = FileManager.default
        let courseURL: URL = coursesDirectoryURL.appendingPathComponent(item.courseCode)

        if let sectionNumber = item.sectionNumber {
            var matchingCourse: Course?
            for course in courses {
                if course.code == item.courseCode {
                    matchingCourse = course
                }
            }
            guard let course = matchingCourse else {
                throw Problem.courseMissing(item.courseCode)
            }
            let sectionURL: URL = course.sectionDirectoryURL(forSection: sectionNumber)
            if fileManager.fileExists(atPath: sectionURL.path) {
                throw Problem.sectionAlreadyPresent(item.courseCode, sectionNumber)
            }

            try extract(item.fileURL, named: "section\(sectionNumber)", into: courseURL)
            try putSectionBack(sectionNumber, into: course)
            discardBuiltSite(
                forSection: sectionNumber,
                courseCode: item.courseCode,
                coursesDirectoryURL: coursesDirectoryURL
            )
        } else {
            if fileManager.fileExists(atPath: courseURL.path) {
                throw Problem.courseAlreadyPresent(item.courseCode)
            }
            try extract(item.fileURL, named: item.courseCode, into: coursesDirectoryURL)
        }

        try? fileManager.removeItem(at: item.fileURL)
    }

    /// Puts a backed-up course back. Unlike an archive restore, the
    /// backup zip STAYS — it only leaves when the teacher deletes it.
    ///
    /// When the course folder still exists, its CONTENTS are replaced
    /// rather than the folder itself: the folder is Obsidian's vault, and
    /// Obsidian's file watcher is anchored to it — swap the folder and
    /// Obsidian shows stale files until the vault is closed and reopened;
    /// swap the contents and it refreshes on its own. The caller has
    /// already archived the current version.
    static func restoreBackup(_ item: BackupItem, coursesDirectoryURL: URL) throws {
        let fileManager: FileManager = FileManager.default
        let destination: URL = coursesDirectoryURL.appendingPathComponent(item.courseCode)

        if !fileManager.fileExists(atPath: destination.path) {
            try extract(item.fileURL, named: item.courseCode, into: coursesDirectoryURL)
            return
        }

        let staging: URL = fileManager.temporaryDirectory.appendingPathComponent("restore-" + UUID().uuidString)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        // Unpack and verify BEFORE touching the course, so an unreadable
        // zip can never leave an emptied folder behind.
        let payload: URL = try unpack(item.fileURL, named: item.courseCode, into: staging)

        // Out with the current contents (hidden files included — the
        // backup carries its own .obsidian), in with the backup's.
        let currentChildren: [URL] = try fileManager.contentsOfDirectory(
            at: destination, includingPropertiesForKeys: nil, options: []
        )
        for child in currentChildren {
            try fileManager.removeItem(at: child)
        }
        let restoredChildren: [URL] = try fileManager.contentsOfDirectory(
            at: payload, includingPropertiesForKeys: nil, options: []
        )
        for child in restoredChildren {
            try fileManager.moveItem(at: child, to: destination.appendingPathComponent(child.lastPathComponent))
        }
    }

    // MARK: - Putting ONE section back

    /// Puts a single section of a backed-up course back, and nothing else.
    ///
    /// A whole-course restore is the wrong shape for the assistant's own
    /// backup. A teacher can easily have been editing Section 2 in Obsidian
    /// while chatting about Section 1, and `restoreBackup` would throw that
    /// away without a word. So exactly two things come back, and between them
    /// they are everything one conversation about one section could have
    /// changed:
    ///
    /// * **The section's own folder.** Its CONTENTS are replaced in place, for
    ///   the reason `restoreBackup` gives above — Obsidian's file watcher is
    ///   anchored to a folder's identity, so the folder itself is never
    ///   swapped, only emptied and refilled.
    ///
    /// * **This section's per-section keys in every course-level page.**
    ///   Publishing a shared page for one section writes
    ///   `publishForSection<N>` into a file that EVERY section shares, and
    ///   that file lives outside `section<N>/` — so a restore that only put
    ///   the folder back would leave the assistant's publishing decisions
    ///   standing. Every other section's keys, and every page's body, are left
    ///   byte for byte as they are.
    ///
    /// Nothing else in the zip is looked at. The zip itself stays, exactly as
    /// it does for a whole-course restore.
    static func restoreSection(
        _ sectionNumber: Int,
        from item: BackupItem,
        coursesDirectoryURL: URL
    ) throws {
        let fileManager: FileManager = FileManager.default
        let courseURL: URL = coursesDirectoryURL.appendingPathComponent(item.courseCode)
        if !fileManager.fileExists(atPath: courseURL.path) {
            throw Problem.courseMissing(item.courseCode)
        }

        let staging: URL = fileManager.temporaryDirectory.appendingPathComponent("restore-" + UUID().uuidString)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        // Unpack and check BEFORE touching the course, so an unreadable zip
        // can never leave an emptied section folder behind.
        let payload: URL = try unpack(item.fileURL, named: item.courseCode, into: staging)
        let folderName: String = "section\(sectionNumber)"
        let backedUpSectionURL: URL = payload.appendingPathComponent(folderName)
        var backedUpSectionIsFolder: ObjCBool = false
        let backedUpSectionExists: Bool = fileManager.fileExists(
            atPath: backedUpSectionURL.path, isDirectory: &backedUpSectionIsFolder
        )
        if !backedUpSectionExists || !backedUpSectionIsFolder.boolValue {
            throw Problem.sectionMissingFromBackup(item.courseCode, sectionNumber)
        }

        try replaceContents(
            of: courseURL.appendingPathComponent(folderName),
            with: backedUpSectionURL
        )
        restorePerSectionKeys(sectionNumber, inCourseAt: courseURL, from: payload)
        discardBuiltSite(
            forSection: sectionNumber,
            courseCode: item.courseCode,
            coursesDirectoryURL: coursesDirectoryURL
        )
    }

    /// Empties a folder and refills it from another, leaving the folder itself
    /// — and so its identity, which Obsidian's watcher holds on to — alone.
    private static func replaceContents(of liveURL: URL, with backedUpURL: URL) throws {
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(at: liveURL, withIntermediateDirectories: true)

        // Hidden files included: whatever the section had is what comes back.
        let currentChildren: [URL] = try fileManager.contentsOfDirectory(
            at: liveURL, includingPropertiesForKeys: nil, options: []
        )
        for child in currentChildren {
            try fileManager.removeItem(at: child)
        }
        let restoredChildren: [URL] = try fileManager.contentsOfDirectory(
            at: backedUpURL, includingPropertiesForKeys: nil, options: []
        )
        for child in restoredChildren {
            try fileManager.moveItem(at: child, to: liveURL.appendingPathComponent(child.lastPathComponent))
        }
    }

    /// Walks the course's SHARED pages — every markdown file outside the
    /// `section<N>` folders — and puts one section's per-section keys back the
    /// way the backup had them.
    ///
    /// Best-effort by design, and deliberately quiet: a page that has since
    /// been deleted, renamed or made unreadable is skipped rather than
    /// recreated. Nothing outside `section<N>/` is ever added or removed here,
    /// because nothing outside it is this section's to restore.
    private static func restorePerSectionKeys(
        _ sectionNumber: Int,
        inCourseAt courseURL: URL,
        from payload: URL
    ) {
        let fileManager: FileManager = FileManager.default
        guard let walker = fileManager.enumerator(at: courseURL, includingPropertiesForKeys: nil) else {
            return
        }
        while let entry = walker.nextObject() as? URL {
            let name: String = entry.lastPathComponent
            if namesASectionFolder(name) || CourseArchiver.excludedFromArchives.contains(name) {
                walker.skipDescendants()
                continue
            }
            if entry.pathExtension != "md" {
                continue
            }
            guard let relativePath = relativePath(of: entry, under: courseURL) else {
                continue
            }
            let backedUpPageURL: URL = payload.appendingPathComponent(relativePath)
            guard let backedUpText = try? String(contentsOf: backedUpPageURL, encoding: .utf8),
                  let liveText = try? String(contentsOf: entry, encoding: .utf8) else {
                continue
            }
            let rewritten: String = settingPerSectionKeys(
                sectionNumber, in: liveText, asIn: backedUpText
            )
            if rewritten != liveText {
                try? rewritten.write(to: entry, atomically: true, encoding: .utf8)
            }
        }
    }

    /// One page's text with a single section's per-section key lines put back
    /// exactly as the backup had them, and every other byte left alone.
    ///
    /// The backup's LINES are carried across verbatim rather than its values
    /// read and rewritten. That is what keeps a course written in the older
    /// `draftSection<N>` spelling in that spelling — the same care
    /// `AssistPageVisibility.setting` takes, arrived at more simply, because
    /// here the right line already exists and only has to be copied.
    ///
    /// Which lines count is asked of `SectionAdder.perSectionKeyNumber`, so
    /// this can never disagree with the code that writes them about what
    /// `draftSection2:` means.
    static func settingPerSectionKeys(
        _ sectionNumber: Int,
        in liveText: String,
        asIn backupText: String
    ) -> String {
        var restoredLines: [String] = []
        if let backupBlock = PageFrontmatter.block(in: backupText) {
            for line in backupBlock.lines {
                let bare: String = PageFrontmatter.trimmingCarriageReturn(line)
                if SectionAdder.perSectionKeyNumber(in: bare) == sectionNumber {
                    restoredLines.append(bare)
                }
            }
        }

        guard let liveBlock = PageFrontmatter.block(in: liveText) else {
            if restoredLines.isEmpty {
                return liveText
            }
            // No frontmatter at all, but the backup had keys: give the page a
            // block of its own, the way `AssistPageVisibility.setting` does.
            return "---\n" + restoredLines.joined(separator: "\n") + "\n---\n" + liveText
        }

        let lines: [String] = liveText.components(separatedBy: "\n")

        // Where the restored lines go when this section has none of its own
        // left on the page: after the last per-section key, so each section's
        // lines stay together and in order — the placement `SectionAdder`
        // uses when it adds a section's pair.
        var lastPerSectionIndex: Int = -1
        for index in (liveBlock.openIndex + 1)..<liveBlock.closeIndex {
            let bare: String = PageFrontmatter.trimmingCarriageReturn(lines[index])
            if SectionAdder.perSectionKeyNumber(in: bare) != nil {
                lastPerSectionIndex = index
            }
        }

        var rebuilt: [String] = []
        rebuilt.append(lines[liveBlock.openIndex])
        var placed: Bool = false
        for index in (liveBlock.openIndex + 1)..<liveBlock.closeIndex {
            let bare: String = PageFrontmatter.trimmingCarriageReturn(lines[index])
            if SectionAdder.perSectionKeyNumber(in: bare) == sectionNumber {
                // This section's own line: replaced by the backup's, or
                // dropped entirely when the backup had none. A key the
                // assistant added where there was none before must go.
                if !placed {
                    rebuilt.append(contentsOf: restoredLines)
                    placed = true
                }
                continue
            }
            rebuilt.append(lines[index])
            if index == lastPerSectionIndex && !placed {
                rebuilt.append(contentsOf: restoredLines)
                placed = true
            }
        }
        if !placed && !restoredLines.isEmpty {
            rebuilt.append(contentsOf: restoredLines)
        }
        for index in liveBlock.closeIndex..<lines.count {
            rebuilt.append(lines[index])
        }
        return rebuilt.joined(separator: "\n")
    }

    /// True for `section1`, `section12` — and false for `sections` or
    /// `section-notes`, which are a teacher's own folders.
    static func namesASectionFolder(_ name: String) -> Bool {
        let prefix: String = "section"
        guard name.hasPrefix(prefix) else {
            return false
        }
        let rest: Substring = name.dropFirst(prefix.count)
        if rest.isEmpty {
            return false
        }
        for character in rest where !character.isNumber {
            return false
        }
        return true
    }

    /// Where a file sits inside a folder, as a path that can be appended to
    /// another copy of that folder.
    private static func relativePath(of url: URL, under root: URL) -> String? {
        let rootPath: String = root.standardizedFileURL.path + "/"
        let path: String = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            return nil
        }
        return String(path.dropFirst(rootPath.count))
    }

    /// Adds the section number back to the course's settings, in order.
    /// Archiving took it out; restoring has to put it back or the section
    /// exists on disk while the course carries on ignoring it.
    private static func putSectionBack(_ sectionNumber: Int, into course: Course) throws {
        var numbers: [Int] = course.sectionNumbers
        if !numbers.contains(sectionNumber) {
            numbers.append(sectionNumber)
        }
        numbers.sort()
        course.configuration.setSectionNumbers(numbers)
        try course.configuration.write(to: course.configFileURL)
    }

    /// Unpacks the archive somewhere safe, checks it holds what its name
    /// promised, and only then moves it into place.
    private static func extract(_ archiveURL: URL, named expectedName: String, into destinationParent: URL) throws {
        let fileManager: FileManager = FileManager.default
        let staging: URL = fileManager.temporaryDirectory.appendingPathComponent("restore-" + UUID().uuidString)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let payload: URL = try unpack(archiveURL, named: expectedName, into: staging)

        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        try fileManager.moveItem(at: payload, to: destinationParent.appendingPathComponent(expectedName))
    }

    /// Unzips into the given staging folder and returns the payload — the
    /// folder the archive's name promised, or the single folder it holds.
    private static func unpack(_ archiveURL: URL, named expectedName: String, into staging: URL) throws -> URL {
        let fileManager: FileManager = FileManager.default

        let unzip: Process = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", archiveURL.path, staging.path]
        let errors: Pipe = Pipe()
        unzip.standardError = errors
        try unzip.run()
        unzip.waitUntilExit()
        if unzip.terminationStatus != 0 {
            let data: Data = errors.fileHandleForReading.readDataToEndOfFile()
            let reason: String = String(data: data, encoding: .utf8) ?? "unknown error"
            throw Problem.archiveUnreadable(reason.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var payload: URL = staging.appendingPathComponent(expectedName)
        if !fileManager.fileExists(atPath: payload.path) {
            // Fall back to whatever single folder the archive held, so an
            // archive made by another version still restores.
            let entries: [URL] = (try? fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            if entries.count == 1 {
                payload = entries[0]
            } else {
                throw Problem.archiveUnreadable("it does not contain \(expectedName)")
            }
        }
        return payload
    }
}
