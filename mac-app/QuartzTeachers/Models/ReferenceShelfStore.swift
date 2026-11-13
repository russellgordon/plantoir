import Foundation

/// Reads and changes the Reference Courses shelf's arrangement,
/// `courses/.internal/reference-shelf.json` (#572, third piece).
///
/// **Where it lives, and why.** In the WORKING FOLDER, beside `profile.json`,
/// `timetable/` and `activity/`, because the arrangement belongs to the
/// folder: a second Mac on the same folder in iCloud Drive sees the same
/// groups, and so will Windows once it reads the file. Not in each course's
/// `course_config.json`, because a group exists with no course in it, and
/// not in the app's preferences, because a second Mac would then disagree
/// about where every course is.
///
/// **It does not travel with a backup or an archive, deliberately.** Both
/// are of ONE course (`courses/<FOLDER>/`), and a group is the folder's, not
/// the course's. A backup restored in place keeps the folder name, so the
/// course stays in its group; a course that was REMOVED and comes back from
/// Archived or from a backup lands by its school year, like every other
/// arrival, and the teacher moves it again (plan review H2: a freed folder
/// name is the name the next course of that code and year is given, so a
/// placement that outlived its course would file a stranger in its group).
///
/// **Every change is read, decided and written under one lock**: an
/// exclusive `flock` on `courses/.internal`, taken by every window and every
/// process on this Mac (the MCP server is the app, run again), so two windows
/// changing groups at once queue rather than undo each other. The file is
/// read FRESH inside the lock, the change is decided against what it says
/// then, and the result is written atomically (a temporary file renamed over
/// the old one). Two Macs writing at the same moment through iCloud: the
/// later write wins, which costs at most one rename or one move.
///
/// **A file it cannot read is never written over.** Unreadable, or written
/// by a newer Plantoir: the shelf shows the year layout (or what it
/// understands) and every change is refused with a sentence, so a half-synced
/// copy of the teacher's groups is not replaced by an empty one.
///
/// **Nothing here touches a course folder.** It reads whether a folder is
/// there, and that is all.
///
/// `nonisolated`: it does nothing a window owns, and a removal or a restore
/// may run it off the main actor.
nonisolated enum ReferenceShelfStore {

    // MARK: - Types

    /// How a change ended.
    enum Outcome {
        /// Changed and written. Carries what the file now says.
        case changed(ReferenceShelf.Arrangement)

        /// Nothing needed changing; nothing was written.
        case unchanged(ReferenceShelf.Arrangement)

        /// Refused, with the sentence the teacher reads.
        case refused(String)

        // MARK: - Computed properties

        var refusal: String? {
            if case .refused(let sentence) = self {
                return sentence
            }
            return nil
        }
    }

    // MARK: - Stored properties

    /// Posted on the main actor after a change is written, with the courses
    /// folder's path as the object, so another window on the same folder
    /// redraws its shelf.
    static let didChange: Notification.Name = Notification.Name("ReferenceShelfStore.didChange")

    // MARK: - Functions

    /// The file, for a courses folder.
    static func fileURL(inCoursesDirectory coursesDirectoryURL: URL) -> URL {
        return coursesDirectoryURL.appendingPathComponent(ReferenceShelf.relativePath)
    }

    /// What the file says now. A file that is not there is `.absent`; one
    /// that is there and cannot be opened is `.unreadable`.
    static func read(inCoursesDirectory coursesDirectoryURL: URL) -> ReferenceShelf.Reading {
        let url: URL = ReferenceShelfStore.fileURL(inCoursesDirectory: coursesDirectoryURL)
        if !FileManager.default.fileExists(atPath: url.path) {
            return .absent
        }
        guard let data = try? Data(contentsOf: url) else {
            return .unreadable
        }
        return ReferenceShelf.reading(data)
    }

    /// Changes the arrangement: under the lock, read fresh, let `apply`
    /// decide (it returns a sentence to refuse, or nil), prune what nobody
    /// needs, and write atomically when something changed.
    ///
    /// A folder with no file and nothing to keep gets no file: an arrival
    /// clearing a placement that was never there writes nothing.
    static func change(
        inCoursesDirectory coursesDirectoryURL: URL,
        _ apply: (inout ReferenceShelf.Arrangement) -> String?
    ) -> Outcome {
        let internalURL: URL = coursesDirectoryURL.appendingPathComponent(".internal")
        do {
            try FileManager.default.createDirectory(at: internalURL, withIntermediateDirectories: true)
        } catch {
            return .refused(ReferenceGroupWording.couldNotSaveGroups)
        }
        let lock: Int32 = ReferenceShelfStore.takeLock(on: internalURL)
        defer {
            ReferenceShelfStore.releaseLock(lock)
        }

        let fileURL: URL = ReferenceShelfStore.fileURL(inCoursesDirectory: coursesDirectoryURL)
        let reading: ReferenceShelf.Reading = ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL)
        if let refusal = reading.refusal {
            return .refused(refusal)
        }
        let before: ReferenceShelf.Arrangement = reading.arrangement
        var arrangement: ReferenceShelf.Arrangement = before
        if let refusal = apply(&arrangement) {
            return .refused(refusal)
        }
        arrangement = ReferenceShelf.pruned(arrangement) { folderName in
            return ReferenceShelfStore.folderIsThere(folderName, inCoursesDirectory: coursesDirectoryURL)
        }

        if case .absent = reading, arrangement.isEmpty {
            return .unchanged(arrangement)
        }
        // Nothing the change or the pruning moved: the file is left exactly
        // as it is, hand-written layout and all.
        if case .read = reading, ReferenceShelf.saysTheSame(arrangement, before) {
            return .unchanged(arrangement)
        }
        guard let newData = try? ReferenceShelf.encoded(arrangement) else {
            return .refused(ReferenceGroupWording.couldNotSaveGroups)
        }
        if let oldData = try? Data(contentsOf: fileURL), oldData == newData {
            return .unchanged(arrangement)
        }
        do {
            try newData.write(to: fileURL, options: [.atomic])
        } catch {
            return .refused(ReferenceGroupWording.couldNotSaveGroups)
        }
        return .changed(arrangement)
    }

    /// True while a course of that folder name is on disk, or a replace or
    /// an import of it is part way (its hidden folder is there).
    static func folderIsThere(_ folderName: String, inCoursesDirectory coursesDirectoryURL: URL) -> Bool {
        if folderName.isEmpty || folderName.contains("/") {
            return false
        }
        let fileManager: FileManager = FileManager.default
        let names: [String] = [
            folderName,
            ReferenceReplacer.asideName(for: folderName),
            ReferenceStaging.stagingName(for: folderName),
        ]
        for name in names {
            if fileManager.fileExists(atPath: coursesDirectoryURL.appendingPathComponent(name).path) {
                return true
            }
        }
        return false
    }

    /// Tells every window on that folder to read the shelf again.
    static func announceChange(inCoursesDirectory coursesDirectoryURL: URL) {
        let path: String = coursesDirectoryURL.path
        Task { @MainActor in
            NotificationCenter.default.post(name: ReferenceShelfStore.didChange, object: path)
        }
    }

    // MARK: - What the teacher does

    /// New Group…: makes an empty group. Returns its id, or the sentence.
    static func makeGroup(
        named typed: String,
        coursesDirectoryURL: URL
    ) -> Result<String, ReferenceShelfRefusal> {
        let name: String = ReferenceShelf.normalizedName(typed)
        var madeID: String = ""
        let outcome: Outcome = ReferenceShelfStore.change(inCoursesDirectory: coursesDirectoryURL) { arrangement in
            if let problem = ReferenceShelf.nameProblem(typed, renaming: nil, arrangement: arrangement) {
                return problem.sentence
            }
            madeID = ReferenceShelf.newGroupID(avoiding: arrangement)
            arrangement.groups.append(ReferenceShelf.MadeGroup(id: madeID, name: name))
            return nil
        }
        if let refusal = outcome.refusal {
            ActivityTrail.note(
                .referenceGroupsNotChanged,
                ReferenceShelfStore.notChangedLine(asked: "make the group \"\(name)\"", sentence: refusal)
            )
            return .failure(ReferenceShelfRefusal(sentence: refusal))
        }
        ActivityTrail.note(.referenceGroupMade, "made the group \"\(name)\" on the Reference Courses shelf")
        ReferenceShelfStore.announceChange(inCoursesDirectory: coursesDirectoryURL)
        return .success(madeID)
    }

    /// Rename Group…: a made group, or the no-year group. A year group has
    /// no name of its own to change (Russell, 2026-11-12).
    static func renameGroup(
        _ place: ReferenceShelf.Place,
        to typed: String,
        coursesDirectoryURL: URL
    ) -> ReferenceShelfRefusal? {
        let name: String = ReferenceShelf.normalizedName(typed)
        var oldName: String = ""
        let outcome: Outcome = ReferenceShelfStore.change(inCoursesDirectory: coursesDirectoryURL) { arrangement in
            if let problem = ReferenceShelf.nameProblem(typed, renaming: place, arrangement: arrangement) {
                return problem.sentence
            }
            switch place {
            case .year:
                return ReferenceGroupWording.couldNotSaveGroups
            case .noYear:
                oldName = arrangement.noYearTitle
                // "Other" typed back is the default, and is kept as no name.
                if name == SchoolYear.otherGroupName {
                    arrangement.noYearGroupName = nil
                } else {
                    arrangement.noYearGroupName = name
                }
            case .made(let id):
                var renamed: [ReferenceShelf.MadeGroup] = []
                var found: Bool = false
                for group in arrangement.groups {
                    if group.id == id {
                        oldName = group.name
                        renamed.append(ReferenceShelf.MadeGroup(id: id, name: name))
                        found = true
                    } else {
                        renamed.append(group)
                    }
                }
                if !found {
                    return ReferenceGroupWording.couldNotSaveGroups
                }
                arrangement.groups = renamed
            }
            return nil
        }
        if let refusal = outcome.refusal {
            ActivityTrail.note(
                .referenceGroupsNotChanged,
                ReferenceShelfStore.notChangedLine(asked: "rename a group to \"\(name)\"", sentence: refusal)
            )
            return ReferenceShelfRefusal(sentence: refusal)
        }
        if case .changed = outcome {
            var line: String = "renamed the group \"\(oldName)\" to \"\(name)\""
            if place == .noYear {
                line += " (the group for courses with no school year)"
            }
            ActivityTrail.note(.referenceGroupRenamed, line)
            ReferenceShelfStore.announceChange(inCoursesDirectory: coursesDirectoryURL)
        }
        return nil
    }

    /// Remove Group: the group goes, and every course in it goes back to the
    /// group its school year puts it in. No course is removed, renamed or
    /// moved on disk. Refused when that would put two courses of one code in
    /// one group.
    static func removeGroup(
        withID id: String,
        coursesDirectoryURL: URL,
        entries: [ReferenceShelf.Entry]
    ) -> ReferenceShelfRefusal? {
        var groupName: String = ""
        var wentBack: Int = 0
        let outcome: Outcome = ReferenceShelfStore.change(inCoursesDirectory: coursesDirectoryURL) { arrangement in
            guard let group = arrangement.group(withID: id) else {
                return nil
            }
            groupName = group.name
            var shelved: [ReferenceCourseRule.Shelved] = ReferenceShelfStore.shelved(entries, in: arrangement)
            for entry in entries where arrangement.placements[entry.folderName] == id {
                let target: ReferenceShelf.Place = ReferenceShelf.Place.forYear(entry.schoolYear)
                if let inTheWay = ReferenceCourseRule.courseInTheWay(
                    placing: entry.displayCode, in: target, among: shelved, ignoring: entry.folderName
                ) {
                    return ReferenceGroupWording.removeWouldClash(
                        group: group.name,
                        course: CourseCodeRule.normalized(inTheWay.displayCode),
                        target: ReferenceShelf.title(of: target, in: arrangement)
                    )
                }
                // The next course out of the group must meet this one where
                // it lands.
                shelved = ReferenceShelfStore.replacing(entry.folderName, with: nil, in: shelved)
                wentBack += 1
            }
            var groups: [ReferenceShelf.MadeGroup] = []
            for kept in arrangement.groups where kept.id != id {
                groups.append(kept)
            }
            arrangement.groups = groups
            // An entry the reader left aside because it repeated this id
            // goes too, or the group would come back under that entry's name
            // the next time the file is read.
            var keptEntries: [Any] = []
            for entry in arrangement.keptGroupEntries {
                if let object = entry as? [String: Any], let keptID = object["id"] as? String, keptID == id {
                    continue
                }
                keptEntries.append(entry)
            }
            arrangement.keptGroupEntries = keptEntries
            var placements: [String: String] = [:]
            for (folderName, placedIn) in arrangement.placements where placedIn != id {
                placements[folderName] = placedIn
            }
            arrangement.placements = placements
            return nil
        }
        if let refusal = outcome.refusal {
            ActivityTrail.note(
                .referenceGroupsNotChanged,
                ReferenceShelfStore.notChangedLine(asked: "remove the group \"\(groupName)\"", sentence: refusal)
            )
            return ReferenceShelfRefusal(sentence: refusal)
        }
        if case .changed = outcome {
            ActivityTrail.note(
                .referenceGroupRemoved,
                "removed the group \"\(groupName)\"; \(ReferenceGroupWording.courses(wentBack)) went back to "
                    + "the groups their school years put them in, and no course was removed"
            )
            ReferenceShelfStore.announceChange(inCoursesDirectory: coursesDirectoryURL)
        }
        return nil
    }

    /// Move to Group ▸: puts one reference course in a made group, or back
    /// where its school year puts it (`.year` or `.noYear` for its own year;
    /// any other year is refused, since the year is Set School Year's). The
    /// shelf rule is asked of the target, ignoring the course itself.
    static func move(
        _ entry: ReferenceShelf.Entry,
        to target: ReferenceShelf.Place,
        coursesDirectoryURL: URL,
        entries: [ReferenceShelf.Entry]
    ) -> ReferenceShelfRefusal? {
        var fromTitle: String = ""
        var toTitle: String = ""
        let outcome: Outcome = ReferenceShelfStore.change(inCoursesDirectory: coursesDirectoryURL) { arrangement in
            let from: ReferenceShelf.Place = ReferenceShelf.place(
                ofFolder: entry.folderName, schoolYear: entry.schoolYear, in: arrangement
            )
            fromTitle = ReferenceShelf.title(of: from, in: arrangement)
            switch target {
            case .year, .noYear:
                if target != ReferenceShelf.Place.forYear(entry.schoolYear) {
                    return ReferenceGroupWording.couldNotSaveGroups
                }
            case .made(let id):
                if arrangement.group(withID: id) == nil {
                    return ReferenceGroupWording.couldNotSaveGroups
                }
            }
            toTitle = ReferenceShelf.title(of: target, in: arrangement)
            if from == target {
                return nil
            }
            let shelved: [ReferenceCourseRule.Shelved] = ReferenceShelfStore.shelved(entries, in: arrangement)
            if let trouble = ReferenceCourseRule.trouble(
                placing: entry.displayCode, in: target, named: toTitle, among: shelved, ignoring: entry.folderName
            ) {
                return trouble.sentence
            }
            if case .made(let id) = target {
                arrangement.placements[entry.folderName] = id
            } else {
                arrangement.placements.removeValue(forKey: entry.folderName)
            }
            return nil
        }
        let course: String = "\(entry.displayCode) (\(entry.folderName))"
        if let refusal = outcome.refusal {
            ActivityTrail.note(
                .referenceGroupsNotChanged,
                ReferenceShelfStore.notChangedLine(asked: "move \(course) to \"\(toTitle)\"", sentence: refusal)
            )
            return ReferenceShelfRefusal(sentence: refusal)
        }
        if case .changed = outcome {
            ActivityTrail.note(
                .referenceCourseMovedToAGroup, "moved \(course) from \"\(fromTitle)\" to \"\(toTitle)\""
            )
            ReferenceShelfStore.announceChange(inCoursesDirectory: coursesDirectoryURL)
        }
        return nil
    }

    /// Start the Groups Again…: the way out of an arrangement that cannot be
    /// read. The file is MOVED aside, never deleted and never written over,
    /// under a dated name beside it (`reference-shelf.unreadable-<stamp>.json`,
    /// with `-2`, `-3`… when that name is taken), and the shelf is the year
    /// layout again with every control working. Refused for a file a NEWER
    /// Plantoir wrote, which an older one leaves exactly as it is, and does
    /// nothing at all to a file that can be read or is not there. Returns the
    /// name the file was kept under, or the refusal.
    static func startAgain(
        coursesDirectoryURL: URL,
        at moment: Date = Date()
    ) -> Result<String?, ReferenceShelfRefusal> {
        let internalURL: URL = coursesDirectoryURL.appendingPathComponent(".internal")
        let lock: Int32 = ReferenceShelfStore.takeLock(on: internalURL)
        defer {
            ReferenceShelfStore.releaseLock(lock)
        }
        let fileURL: URL = ReferenceShelfStore.fileURL(inCoursesDirectory: coursesDirectoryURL)
        switch ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL) {
        case .absent, .read:
            return .success(nil)
        case .newer:
            let sentence: String = ReferenceGroupWording.arrangedByANewerPlantoir
            ActivityTrail.note(
                .referenceGroupsNotChanged,
                ReferenceShelfStore.notChangedLine(asked: "start the groups again", sentence: sentence)
            )
            return .failure(ReferenceShelfRefusal(sentence: sentence))
        case .unreadable:
            break
        }
        let stamp: String = ArchiveStamp.text(for: moment)
        var attempt: Int = 1
        while attempt < 1000 {
            var keptName: String = "reference-shelf.unreadable-\(stamp).json"
            if attempt > 1 {
                keptName = "reference-shelf.unreadable-\(stamp)-\(attempt).json"
            }
            let keptURL: URL = internalURL.appendingPathComponent(keptName)
            if FileManager.default.fileExists(atPath: keptURL.path) {
                attempt += 1
                continue
            }
            do {
                // A move, which refuses a name that is there: an earlier
                // copy kept aside is never written over.
                try FileManager.default.moveItem(at: fileURL, to: keptURL)
            } catch {
                break
            }
            ActivityTrail.note(
                .referenceGroupsStartedAgain,
                "started the groups on the Reference Courses shelf again; the arrangement that could not be read "
                    + "was kept beside it as \(keptName)"
            )
            ReferenceShelfStore.announceChange(inCoursesDirectory: coursesDirectoryURL)
            return .success(keptName)
        }
        let sentence: String = ReferenceGroupWording.couldNotSaveGroups
        ActivityTrail.note(
            .referenceGroupsNotChanged,
            ReferenceShelfStore.notChangedLine(asked: "start the groups again", sentence: sentence)
        )
        return .failure(ReferenceShelfRefusal(sentence: sentence))
    }

    // MARK: - What every door that lands a course does

    /// Writes where a course that has just ARRIVED goes, at the moment it
    /// arrives (plan review H2): the made group the wizard was told, or no
    /// placement at all, so a folder name freed by a removal never inherits
    /// the old course's group. Silent on the screen, because the arrival
    /// says what happened; a refusal (the file cannot be read) leaves a line.
    ///
    /// Not called by a replace, which keeps the replaced course's folder
    /// name and therefore its group, or by a restore in place, which keeps
    /// the course.
    @discardableResult
    static func recordArrival(
        of folderName: String,
        inMadeGroup id: String?,
        coursesDirectoryURL: URL
    ) -> ReferenceShelfRefusal? {
        // A folder with no arrangement has no placement to clear, and no
        // group to put a course in: nothing to lock, read or write.
        let fileURL: URL = ReferenceShelfStore.fileURL(inCoursesDirectory: coursesDirectoryURL)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            return nil
        }
        let outcome: Outcome = ReferenceShelfStore.change(inCoursesDirectory: coursesDirectoryURL) { arrangement in
            if let id, arrangement.group(withID: id) != nil {
                arrangement.placements[folderName] = id
            } else {
                arrangement.placements.removeValue(forKey: folderName)
                arrangement.keptPlacementEntries.removeValue(forKey: folderName)
            }
            return nil
        }
        if let refusal = outcome.refusal {
            ActivityTrail.note(
                .referenceGroupsNotChanged,
                ReferenceShelfStore.notChangedLine(asked: "record which group \(folderName) is in", sentence: refusal)
            )
            return ReferenceShelfRefusal(sentence: refusal)
        }
        if case .changed = outcome {
            ReferenceShelfStore.announceChange(inCoursesDirectory: coursesDirectoryURL)
        }
        return nil
    }

    /// Forgets a course that has been REMOVED (Remove Course…), so its
    /// folder name, freed now, carries no group to the next course given it.
    static func forgetRemoved(_ folderName: String, coursesDirectoryURL: URL) {
        // The same write as an arrival with no group.
        ReferenceShelfStore.recordArrival(of: folderName, inMadeGroup: nil, coursesDirectoryURL: coursesDirectoryURL)
    }

    // MARK: - Helpers

    /// The shelf rule's view of the courses, with each one's made group as
    /// `arrangement` says it.
    static func shelved(
        _ entries: [ReferenceShelf.Entry],
        in arrangement: ReferenceShelf.Arrangement
    ) -> [ReferenceCourseRule.Shelved] {
        var result: [ReferenceCourseRule.Shelved] = []
        for entry in entries {
            var madeGroupID: String?
            if case .made(let id) = ReferenceShelf.place(
                ofFolder: entry.folderName, schoolYear: entry.schoolYear, in: arrangement
            ) {
                madeGroupID = id
            }
            result.append(ReferenceCourseRule.Shelved(
                displayCode: entry.displayCode,
                schoolYear: entry.schoolYear,
                folderName: entry.folderName,
                madeGroupID: madeGroupID
            ))
        }
        return result
    }

    /// `shelved` with one course's made group changed.
    static func replacing(
        _ folderName: String,
        with madeGroupID: String?,
        in shelved: [ReferenceCourseRule.Shelved]
    ) -> [ReferenceCourseRule.Shelved] {
        var result: [ReferenceCourseRule.Shelved] = []
        for existing in shelved {
            if existing.folderName == folderName {
                result.append(ReferenceCourseRule.Shelved(
                    displayCode: existing.displayCode,
                    schoolYear: existing.schoolYear,
                    folderName: existing.folderName,
                    madeGroupID: madeGroupID
                ))
            } else {
                result.append(existing)
            }
        }
        return result
    }

    /// The trail line for a change that did not happen.
    static func notChangedLine(asked: String, sentence: String) -> String {
        return "did not \(asked) on the Reference Courses shelf: \(sentence)"
    }

    /// An exclusive lock on the folder, waiting for whoever holds it. -1
    /// when the folder cannot be opened, and the change goes ahead unlocked
    /// (the atomic write still keeps the file whole).
    static func takeLock(on folderURL: URL) -> Int32 {
        let folder: Int32 = folderURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return open(path, O_RDONLY | O_CLOEXEC)
        }
        if folder < 0 {
            return -1
        }
        var result: Int32 = flock(folder, LOCK_EX)
        while result != 0 && errno == EINTR {
            result = flock(folder, LOCK_EX)
        }
        return folder
    }

    static func releaseLock(_ folder: Int32) {
        if folder < 0 {
            return
        }
        flock(folder, LOCK_UN)
        close(folder)
    }
}

/// A group change the teacher asked for that did not happen, as the sentence
/// they read.
nonisolated struct ReferenceShelfRefusal: Error, Equatable {

    // MARK: - Stored properties

    let sentence: String
}
