import Foundation

/// Replacing a course on the Reference Courses shelf with a new one, after a
/// warning and a backup (#572, second piece).
///
/// Offered beside the shelf rule's refusal ("You already have a ICS3U kept
/// for reference from 2025–26") at three doors: the New Course wizard,
/// Keep a Copy for Reference…, and an import of ONE course. Each door makes
/// the new course first, exactly as it would if nothing were in the way,
/// under the hidden staging name for the OLD course's folder
/// (`.plantoir-importing-<OLD>`), claimed and leased the way every
/// reference door claims a folder. Only then is this called, with the new
/// course already marked, neutralised and locked. Nothing of the old course
/// is touched until the new one exists.
///
/// **The worst fault is a teacher's reference course gone with no way back**,
/// so the order is the whole design:
///
/// 1. Refuse anything that is not a reference course in `courses/`, a course
///    that is previewing or being copied, and a course Obsidian has open as
///    a vault (plan review M2: the folder is about to be swapped, and
///    Obsidian's watcher is anchored to it).
/// 2. Back it up as an ordinary teacher-kind backup, which is never pruned
///    and which both apps already list.
/// 3. CHECK the backup (plan review M3): its listing must hold every file of
///    the course on disk, apart from the two things a zip of a course always
///    leaves out (the link to the built website and Finder's `.DS_Store`)
///    and Plantoir's own Obsidian add-ons. A zip nobody checked is not a
///    backup, and a course an older Plantoir or Windows made may hold a
///    folder called `build` or `out` that every zip of a course leaves out.
/// 4. Ask the first checks again, because the backup took time.
/// 5. Rename the old course aside, to `.plantoir-replacing-<OLD>`.
/// 6. Rename the new course in, under the OLD folder name. If that fails the
///    old course is renamed back.
/// 7. Remove the aside folder, unlocked first, and the old built website.
///
/// Every failure before step 5 leaves the old course exactly where it was.
/// A failure at 6 renames it back. Nothing on any failure path deletes the
/// old course: the only removal of it is step 7, after the new one is in
/// place, with a checked backup on disk. A quit or a crash between 5 and 7
/// leaves the aside folder, which `sweepLeftovers` recognises on the next
/// reading of the folder (plan review M1): renamed BACK when the old name is
/// free, removed only when the new course is in place and a backup is there.
///
/// **The replacement takes the replaced course's folder name** (the plan's
/// Q6), so the ordinary Restore from Backup on the backup made here is an
/// in-place restore: it archives the replacement and puts the old course
/// back. A new folder name would land the restored course beside the new one
/// in the same group, which the shelf rule forbids.
@MainActor
enum ReferenceReplacer {

    // MARK: - Types

    /// What a door asks to be replaced, and where the new course came from.
    struct Asked: Equatable {

        // MARK: - Stored properties

        /// The folder of the reference course being replaced: its identity,
        /// and the name the new course is given.
        let folderName: String

        /// Where the new course came from, as the trail says it: "a new
        /// course made from the ready-made pages", "a copy of ICS3U", "a
        /// course imported from ICS3U_backup_….zip".
        let source: String
    }

    /// Why a replace did not happen, in the sentence the teacher reads.
    enum Problem: LocalizedError, Equatable {
        case notOnTheShelf(course: String)
        case busy(course: String)
        case openInObsidian(course: String)
        case couldNotBackUp(course: String)
        /// A backup was made and did not hold the whole course (plan review
        /// M3; implementation review M1). The backup is KEPT and said, by the
        /// name its row has in Backups.
        case backupIsIncomplete(course: String, folder: String)
        case couldNotReplace(course: String)
        case couldNotPutBackYet(course: String)

        // MARK: - Computed properties

        var errorDescription: String? {
            switch self {
            case .notOnTheShelf(let course):
                return ReferenceReplaceWording.notOnTheShelf(course: course)
            case .busy(let course):
                return ReferenceReplaceWording.replaceWhileBusy(course: course)
            case .openInObsidian(let course):
                return ReferenceReplaceWording.openInObsidian(course: course)
            case .couldNotBackUp(let course):
                return ReferenceReplaceWording.couldNotBackUp(course: course)
            case .backupIsIncomplete(let course, let folder):
                return ReferenceReplaceWording.backupIsIncomplete(course: course, folder: folder)
            case .couldNotReplace(let course):
                return ReferenceReplaceWording.couldNotReplace(course: course)
            case .couldNotPutBackYet(let course):
                return ReferenceReplaceWording.couldNotPutBackYet(course: course)
            }
        }

        /// The key of its sentence in `referenceCourses.replacing.wording`,
        /// which is how the contract's cases name what is said.
        var wordingKey: String {
            switch self {
            case .notOnTheShelf:
                return "notOnTheShelf"
            case .busy:
                return "replaceWhileBusy"
            case .openInObsidian:
                return "openInObsidian"
            case .couldNotBackUp:
                return "couldNotBackUp"
            case .backupIsIncomplete:
                return "backupIsIncomplete"
            case .couldNotReplace:
                return "couldNotReplace"
            case .couldNotPutBackYet:
                return "couldNotPutBackYet"
            }
        }
    }

    /// What the check of a backup found.
    enum BackupCheck: Equatable, Sendable {
        /// Every file the course holds is in the backup. Carries what the
        /// course held, for the trail.
        case holdsTheCourse(files: Int, pages: Int, bytes: Int64)
        /// This many files of the course are not in it. A COUNT, never a
        /// name: a page's file name is its title, which the trail never
        /// carries.
        case isMissing(count: Int)
        /// The backup's listing, or a folder of the course, could not be
        /// read, so nothing can be said about it.
        case couldNotBeRead
    }

    /// Everything the act asks of the world outside it, in one replaceable
    /// place, so a test can make each step fail on cue and record the order
    /// the steps ran in. The defaults are the real thing.
    struct World {

        // MARK: - Stored properties

        /// Whether the course is busy: previewing, publishing, or held by a
        /// Claude or Codex session elsewhere, and, when `countingCopies`, a
        /// copy of it being saved. The act holds a copy record of its own
        /// for its whole length, so it asks the second time without copies.
        var isBusy: @MainActor (_ workingFolderPath: String, _ folderName: String, _ countingCopies: Bool) -> Bool

        /// Whether Obsidian has the course open as a vault, or a vault inside
        /// it, or cannot tell (`ReferenceReplacer.obsidianHoldsIt`).
        var obsidianHoldsIt: @MainActor (_ coursePath: String) -> Bool

        /// Makes the backup, and returns it.
        var backUp: @MainActor (_ course: Course, _ coursesDirectoryURL: URL) async throws -> URL

        /// Checks the backup against the course on disk.
        var checkTheBackUp: @MainActor (_ backupURL: URL, _ courseURL: URL) async -> BackupCheck

        /// One rename within `courses/`.
        var move: @MainActor (_ from: URL, _ to: URL) throws -> Void

        /// Removes a folder, unlocked first; says whether it is gone.
        var removeTree: @MainActor (_ folderURL: URL) -> Bool

        // MARK: - Initializer

        /// The real thing, asking Obsidian through `obsidianOpening` (the
        /// window's own seam, so a test that drives a window never reaches
        /// the teacher's Obsidian).
        init(obsidianOpening: ObsidianOpening = ObsidianOpening()) {
            isBusy = { workingFolderPath, folderName, countingCopies in
                return ReferenceReplacer.courseIsBusy(
                    workingFolderPath: workingFolderPath, folderName: folderName, countingCopies: countingCopies
                )
            }
            obsidianHoldsIt = { coursePath in
                return ReferenceReplacer.obsidianHoldsIt(
                    coursePath: coursePath,
                    obsidianRunning: obsidianOpening.isRunning(),
                    registryData: obsidianOpening.registryData()
                )
            }
            backUp = { course, coursesDirectoryURL in
                return try await CourseArchiver.backUpCourse(
                    course, coursesDirectoryURL: coursesDirectoryURL, madeBy: .teacher
                )
            }
            checkTheBackUp = { backupURL, courseURL in
                return await ReferenceReplacer.checkTheBackUp(backupURL, against: courseURL)
            }
            move = { from, to in
                try FileManager.default.moveItem(at: from, to: to)
            }
            removeTree = { folderURL in
                return ReferenceStaging.remove(at: folderURL)
            }
        }
    }

    /// What was replaced.
    struct Replaced: Equatable {

        // MARK: - Stored properties

        /// The folder the new course now has: the old one's.
        let folderName: String

        /// The code a teacher reads.
        let displayCode: String

        /// The group it sits in on the shelf.
        let group: String

        /// The backup of the old course, by its file name.
        let backupFileName: String
    }

    /// The warning a door shows before anything is made (`offer`).
    struct Warning: Identifiable, Equatable {

        // MARK: - Stored properties

        /// The folder of the course it is about.
        let folderName: String

        let title: String

        /// What the sheet asks (#834): the title, one sentence, the facts as
        /// rows, Replace and Cancel.
        let question: FactsQuestion

        // MARK: - Computed properties

        var id: String {
            return folderName
        }
    }

    /// What pressing Replace It… comes to.
    enum Offer: Equatable {
        /// The warning, to confirm or cancel.
        case warn(Warning)
        /// Refused before the warning, in the sentence the door shows.
        case refused(String)
    }

    /// What a sweep did about one leftover aside folder.
    struct SweepOutcome: Equatable {

        // MARK: - Types

        enum Kind: String, Equatable {
            /// The old course was renamed back to its own folder: the replace
            /// stopped before the new course was in place.
            case putBack
            /// The old copy was removed: the new course was in place and a
            /// backup of the folder is on disk.
            case tidiedAway
            /// The old name is free, but renaming it back failed.
            case couldNotPutBack
        }

        // MARK: - Stored properties

        let kind: Kind
        let folderName: String

        /// The backup the old copy was checked against before it was
        /// removed, by its file name, for `tidiedAway`.
        var backupFileName: String? = nil
    }

    // MARK: - Stored properties

    /// What the hidden folder an old course waits in is called, while its
    /// replacement is renamed in.
    ///
    /// Distinctive for the reason `ReferenceStaging.prefix` is: the sweep
    /// acts on what it matches, and a teacher's own dot-folder must never be
    /// mistaken for one of these. A dot-name, so nothing that looks for a
    /// course sees it: discovery, the backups list, the launchers (which
    /// refuse a dotted name) and Windows (`Workspace.cs` skips any `courses/`
    /// entry beginning with `.`).
    nonisolated static let asidePrefix: String = ".plantoir-replacing-"


    // MARK: - Functions

    /// `.plantoir-replacing-<FOLDER>`.
    nonisolated static func asideName(for folderName: String) -> String {
        return ReferenceReplacer.asidePrefix + folderName
    }

    /// Whether a name in `courses/` is one of these.
    static func isAsideName(_ name: String) -> Bool {
        return name.hasPrefix(ReferenceReplacer.asidePrefix) && name.count > ReferenceReplacer.asidePrefix.count
    }

    /// The course in that folder as its settings say it is NOW, when it is a
    /// reference course directly inside `courses/`; nil otherwise. Read from
    /// disk rather than from a window's list, because the act must never
    /// replace a LIVE course, whatever a window last showed.
    static func courseOnTheShelf(folderName: String, coursesDirectoryURL: URL) -> Course? {
        if folderName.isEmpty || folderName.hasPrefix(".") || folderName.hasPrefix("_") || folderName.contains("/") {
            return nil
        }
        let folderURL: URL = coursesDirectoryURL.appendingPathComponent(folderName)
        guard let configuration = try? CourseConfiguration(
            contentsOf: folderURL.appendingPathComponent("course_config.json")
        ) else {
            return nil
        }
        let course: Course = Course(code: folderName, directoryURL: folderURL, configuration: configuration)
        if !course.isKeptForReference {
            return nil
        }
        return course
    }

    /// The group a reference course sits in, as the shelf names it: a group
    /// the teacher made and put it in, the no-year group under the name the
    /// teacher gave it, or its school year (#572, third piece). The
    /// replacement keeps the old course's folder name, and so its group.
    static func groupLabel(
        for course: Course,
        coursesDirectoryURL: URL,
        on day: CalendarDay = CalendarDay.today()
    ) -> String {
        let arrangement: ReferenceShelf.Arrangement = ReferenceShelfStore.read(
            inCoursesDirectory: coursesDirectoryURL
        ).arrangement
        let place: ReferenceShelf.Place = ReferenceShelf.place(
            ofFolder: course.code, schoolYear: course.schoolYear(on: day), in: arrangement
        )
        return ReferenceShelf.title(of: place, in: arrangement)
    }

    /// Why that course cannot be replaced right now, or nil — asked by a
    /// door BEFORE the new course is made, so a teacher is not kept waiting
    /// for a course that would then be refused. The act asks it all again.
    static func refusal(
        toReplace folderName: String,
        coursesDirectoryURL: URL,
        world: World = World()
    ) -> Problem? {
        guard let old = ReferenceReplacer.courseOnTheShelf(
            folderName: folderName, coursesDirectoryURL: coursesDirectoryURL
        ) else {
            return .notOnTheShelf(course: folderName)
        }
        let workingFolderPath: String = coursesDirectoryURL.deletingLastPathComponent().path
        if world.isBusy(workingFolderPath, folderName, true) {
            return .busy(course: old.displayCode)
        }
        if world.obsidianHoldsIt(old.directoryURL.path) {
            return .openInObsidian(course: old.displayCode)
        }
        return nil
    }

    /// What Replace It… beside the shelf rule's refusal shows: the refusal,
    /// when the course cannot be replaced right now, or the warning, which
    /// says what the course holds, when it was kept, what the backup will be
    /// called in Backups and that restoring it puts the old course back.
    /// The walk that counts the pages runs off the main actor.
    static func offer(
        toReplace folderName: String,
        coursesDirectoryURL: URL,
        world: World = World()
    ) async -> Offer {
        if let refusal = ReferenceReplacer.refusal(
            toReplace: folderName, coursesDirectoryURL: coursesDirectoryURL, world: world
        ) {
            return .refused(refusal.errorDescription ?? "")
        }
        guard let old = ReferenceReplacer.courseOnTheShelf(
            folderName: folderName, coursesDirectoryURL: coursesDirectoryURL
        ) else {
            return .refused(ReferenceReplaceWording.notOnTheShelf(course: folderName))
        }
        let course: String = old.displayCode
        let group: String = ReferenceReplacer.groupLabel(for: old, coursesDirectoryURL: coursesDirectoryURL)
        let counted: (files: Int, pages: Int, bytes: Int64) = await ReferenceReplacer.counting(
            courseDirectoryPath: old.directoryURL.path
        )
        let sections: String = ReferenceReplaceWording.sections(old.sectionNumbers.count)
        let pages: String = ReferenceReplaceWording.pages(counted.pages)
        let size: String = ReferenceImportWording.size(counted.bytes)

        var date: String?
        let created: Date? = try? old.directoryURL.resourceValues(forKeys: [.creationDateKey]).creationDate
        if let created {
            let formatter: DateFormatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            date = formatter.string(from: created)
        }
        let title: String = ReferenceReplaceWording.title(course: course, group: group)
        let question: FactsQuestion = FactsQuestion(
            title: title,
            message: ReferenceReplaceWording.message,
            rows: ReferenceReplaceWording.rows(sections: sections, pages: pages, size: size, date: date, folder: folderName),
            action: ReferenceReplaceWording.confirmButton,
            cancel: ReferenceReplaceWording.cancelButton
        )
        return .warn(Warning(folderName: folderName, title: title, question: question))
    }

    /// How many files and pages the course holds, and how large it is, by
    /// the same walk the backup check makes, leaving out what it leaves out.
    @concurrent
    nonisolated static func counting(courseDirectoryPath: String) async -> (files: Int, pages: Int, bytes: Int64) {
        let check: BackupCheck = ReferenceReplacer.compare(
            zipNames: nil, courseDirectoryURL: URL(fileURLWithPath: courseDirectoryPath), mayBeMissing: []
        )
        if case .holdsTheCourse(let files, let pages, let bytes) = check {
            return (files: files, pages: pages, bytes: bytes)
        }
        return (files: 0, pages: 0, bytes: 0)
    }

    /// Replaces the reference course `asked.folderName` with the course made
    /// in `stagingURL`, in the order this type's comment gives.
    ///
    /// The staged course is the act's from here on: on every failure it is
    /// removed, and the old course is where it was (or, for
    /// `couldNotPutBackYet`, in the aside folder the next reading puts back).
    /// The caller still owns the claim and gives it back afterwards.
    ///
    /// Writes ONE line for how it ended: `referenceCourseReplaced` or
    /// `referenceCourseCouldNotBeReplaced`.
    static func replace(
        _ asked: Asked,
        withStagedAt stagingURL: URL,
        coursesDirectoryURL: URL,
        world: World = World()
    ) async throws -> Replaced {
        let fileManager: FileManager = FileManager.default
        let folderName: String = asked.folderName
        let workingFolderPath: String = coursesDirectoryURL.deletingLastPathComponent().path
        let oldURL: URL = coursesDirectoryURL.appendingPathComponent(folderName)
        let asideURL: URL = coursesDirectoryURL.appendingPathComponent(ReferenceReplacer.asideName(for: folderName))

        // 1. Only a reference course, only one nobody is using.
        guard let old = ReferenceReplacer.courseOnTheShelf(
            folderName: folderName, coursesDirectoryURL: coursesDirectoryURL
        ) else {
            throw ReferenceReplacer.givingUp(
                .notOnTheShelf(course: folderName), asked: asked, group: nil,
                stagingURL: stagingURL, world: world
            )
        }
        let course: String = old.displayCode
        let group: String = ReferenceReplacer.groupLabel(for: old, coursesDirectoryURL: coursesDirectoryURL)
        if world.isBusy(workingFolderPath, folderName, true) {
            throw ReferenceReplacer.givingUp(
                .busy(course: course), asked: asked, group: group, stagingURL: stagingURL, world: world
            )
        }
        if world.obsidianHoldsIt(oldURL.path) {
            throw ReferenceReplacer.givingUp(
                .openInObsidian(course: course), asked: asked, group: group, stagingURL: stagingURL, world: world
            )
        }
        // An aside folder of that name already there is an earlier replace
        // the sweep has not settled. Never written over: it may be the only
        // copy of a course outside a backup.
        if fileManager.fileExists(atPath: asideURL.path) {
            throw ReferenceReplacer.givingUp(
                .couldNotReplace(course: course), asked: asked, group: group, stagingURL: stagingURL,
                world: world, detail: "an earlier replace of it has not been settled yet"
            )
        }

        // The course counts as being copied for the whole act, so nothing
        // else in this app (a removal, a restore, another backup, a preview)
        // starts on it until the swap is over.
        CourseActivity.beginCopy(folderPath: workingFolderPath, courseCode: folderName, displayCode: course)
        defer {
            CourseActivity.endCopy(folderPath: workingFolderPath, courseCode: folderName)
        }

        // 2. The backup.
        let backupURL: URL
        do {
            backupURL = try await world.backUp(old, coursesDirectoryURL)
        } catch {
            // The code `zip` stopped with, never its own words: they name
            // the file it could not read, and a page's file name is its title.
            let code: Int = (error as NSError).code
            throw ReferenceReplacer.givingUp(
                .couldNotBackUp(course: course), asked: asked, group: group, stagingURL: stagingURL,
                world: world, detail: "the backup could not be written (code \(code))"
            )
        }

        // 3. The backup, checked. One that does not hold the course is
        // KEPT, and said: it is most of the course, and removing it would be
        // a delete on a failure path. The teacher reads where it is.
        let check: BackupCheck = await world.checkTheBackUp(backupURL, oldURL)
        guard case .holdsTheCourse(let files, let pages, let bytes) = check else {
            throw ReferenceReplacer.givingUp(
                .backupIsIncomplete(course: course, folder: folderName), asked: asked, group: group,
                stagingURL: stagingURL, world: world,
                detail: ReferenceReplacer.describe(check, backupFileName: backupURL.lastPathComponent)
            )
        }

        // 4. Asked again: the backup can take a minute, and a preview, an
        // Obsidian window or a hand edit of the settings could have arrived
        // in it.
        if ReferenceReplacer.courseOnTheShelf(folderName: folderName, coursesDirectoryURL: coursesDirectoryURL) == nil {
            throw ReferenceReplacer.givingUp(
                .notOnTheShelf(course: course), asked: asked, group: group, stagingURL: stagingURL, world: world
            )
        }
        if world.isBusy(workingFolderPath, folderName, false) {
            throw ReferenceReplacer.givingUp(
                .busy(course: course), asked: asked, group: group, stagingURL: stagingURL, world: world
            )
        }
        if world.obsidianHoldsIt(oldURL.path) {
            throw ReferenceReplacer.givingUp(
                .openInObsidian(course: course), asked: asked, group: group, stagingURL: stagingURL, world: world
            )
        }

        // 5. The old course aside: one rename within `courses/`, which works
        // on a locked tree and keeps its lock.
        do {
            try world.move(oldURL, asideURL)
        } catch {
            throw ReferenceReplacer.givingUp(
                .couldNotReplace(course: course), asked: asked, group: group, stagingURL: stagingURL,
                world: world, detail: error.localizedDescription
            )
        }

        // 6. The new course in, under the old name. On a failure the old
        // course goes back to where it was BEFORE the staged one is removed.
        do {
            try world.move(stagingURL, oldURL)
        } catch {
            let reason: String = error.localizedDescription
            do {
                try world.move(asideURL, oldURL)
            } catch {
                throw ReferenceReplacer.givingUp(
                    .couldNotPutBackYet(course: course), asked: asked, group: group, stagingURL: stagingURL,
                    world: world, detail: reason + "; putting it back: " + error.localizedDescription
                )
            }
            throw ReferenceReplacer.givingUp(
                .couldNotReplace(course: course), asked: asked, group: group, stagingURL: stagingURL,
                world: world, detail: reason
            )
        }

        // 7. The old course's own folder goes, now that the new one is in
        // place and a checked backup is on disk. A removal that fails is
        // not a failed replace: the next reading of the folder takes it.
        let backupFileName: String = backupURL.lastPathComponent
        let asideIsGone: Bool = world.removeTree(asideURL)
        BuildOutputLocation.discardBuiltSites(
            forWorkingFolder: coursesDirectoryURL.deletingLastPathComponent(),
            courseCode: folderName
        )

        let replaced: Replaced = Replaced(
            folderName: folderName,
            displayCode: course,
            group: group,
            backupFileName: backupFileName
        )
        ActivityTrail.note(
            .referenceCourseReplaced,
            ReferenceReplacer.trailLine(
                for: replaced,
                source: asked.source,
                sections: old.sectionNumbers.count,
                files: files,
                pages: pages,
                bytes: bytes,
                oldCopyIsGone: asideIsGone
            )
        )
        return replaced
    }

    /// The line for a course that was replaced.
    static func trailLine(
        for replaced: Replaced,
        source: String,
        sections: Int,
        files: Int,
        pages: Int,
        bytes: Int64,
        oldCopyIsGone: Bool
    ) -> String {
        var line: String = "replaced \(replaced.folderName) on the reference shelf "
            + "(\(replaced.displayCode), \(replaced.group)) with \(source) — the old one held "
            + "\(ReferenceReplaceWording.sections(sections)), \(files) files, "
            + "\(ReferenceReplaceWording.pages(pages)) and \(ReferenceImportWording.size(bytes)), "
            + "and is in the backup \(replaced.backupFileName)"
        if !oldCopyIsGone {
            line += "; its own folder could not be tidied away yet, and is the next time this working folder is opened"
        }
        return line
    }

    /// The line for a course that was not replaced, and why.
    static func failureTrailLine(
        folderName: String,
        course: String,
        group: String?,
        source: String,
        sentence: String,
        detail: String?
    ) -> String {
        var line: String = "could not replace \(folderName) on the reference shelf"
        if let group {
            line += " (\(course), \(group))"
        }
        line += " with \(source) — \(sentence)"
        if let detail, !detail.isEmpty {
            line += " (\(detail))"
        }
        return line
    }

    /// Whether Obsidian holds the course: the open-state rule #742 settled
    /// (`ObsidianFigureAddOnsOffer.courseIsOpen`, `openStateCases`: open, or
    /// cannot tell), or an open vault INSIDE the course, which the swap
    /// would strand just the same (`FolderActions.openVaultWouldBeStranded`).
    /// A vault that CONTAINS the course is not affected: its own root does
    /// not move, and Obsidian follows a rename inside a vault.
    static func obsidianHoldsIt(coursePath: String, obsidianRunning: Bool, registryData: Data?) -> Bool {
        if ObsidianFigureAddOnsOffer.courseIsOpen(
            coursePath: coursePath, obsidianRunning: obsidianRunning, registryData: registryData
        ) {
            return true
        }
        let openVaults: [String] = ObsidianFigureAddOnsOffer.vaultsOpen(
            obsidianRunning: obsidianRunning, registryData: registryData
        )
        return FolderActions.openVaultWouldBeStranded(byMoving: coursePath, openVaultPaths: openVaults)
    }

    /// Whether the course is busy, as `World.isBusy` asks it.
    static func courseIsBusy(workingFolderPath: String, folderName: String, countingCopies: Bool) -> Bool {
        if countingCopies && CourseActivity.courseIsBusy(folderPath: workingFolderPath, courseCode: folderName) {
            return true
        }
        for lease in PreviewLeases.active {
            if lease.courseCode == folderName && FolderIdentity.isSameFolder(lease.folderPath, workingFolderPath) {
                return true
            }
        }
        if CourseActivity.coursePublishIsRunning(folderPath: workingFolderPath, courseCode: folderName) {
            return true
        }
        // A Copy a Page pass reading from it (implementation review L3).
        let courseURL: URL = URL(fileURLWithPath: workingFolderPath)
            .appendingPathComponent("courses").appendingPathComponent(folderName)
        if PageCopySourceReads.isReading(courseURL) {
            return true
        }
        return CourseActivity.isRevisedElsewhere(folderPath: workingFolderPath, courseCode: folderName)
    }

    // MARK: - Checking a backup

    /// The real check: what may be missing is read here, on the main actor
    /// (Plantoir's own add-on folders, by their marker), and the listing and
    /// the walk run off it.
    static func checkTheBackUp(_ backupURL: URL, against courseURL: URL) async -> BackupCheck {
        var mayBeMissing: [String] = []
        let pluginsURL: URL = courseURL
            .appendingPathComponent(ObsidianAddOns.settingsFolderName)
            .appendingPathComponent("plugins")
        for name in ObsidianFigureAddOns.plantoirAddOnFolders(inPluginsAt: pluginsURL) {
            mayBeMissing.append(ObsidianAddOns.settingsFolderName + "/plugins/" + name)
        }
        return await ReferenceReplacer.checking(
            backupPath: backupURL.path, courseDirectoryPath: courseURL.path, mayBeMissing: mayBeMissing
        )
    }

    /// The names every zip of a course leaves out that the check accepts
    /// missing, wherever they sit: the link to the built website, which is
    /// rebuilt from the pages, and Finder's own `.DS_Store`. Nothing else in
    /// `CourseArchiver.excludedFromArchives` is accepted, because those names
    /// (`build`, `out`, `dist`…) can be a teacher's own folders in a course
    /// an older Plantoir or Windows made.
    nonisolated static let mayAlwaysBeMissing: [String] = [".DS_Store"]

    /// The one name accepted missing only at the TOP of the course: the link
    /// to the built website lives there and nowhere else, and a teacher's
    /// own `section1/.merged_output/` deeper down is a folder of theirs
    /// (implementation review L7).
    nonisolated static let mayBeMissingAtTheTop: [String] = [".merged_output"]

    /// The listing and the walk, off the main actor (`@concurrent`, for the
    /// reason `CourseArchiver.zipping` gives).
    @concurrent
    nonisolated static func checking(
        backupPath: String,
        courseDirectoryPath: String,
        mayBeMissing: [String]
    ) async -> BackupCheck {
        guard let listing = ReferenceReplacer.zipListing(atPath: backupPath) else {
            return .couldNotBeRead
        }
        return ReferenceReplacer.compare(
            zipNames: listing,
            courseDirectoryURL: URL(fileURLWithPath: courseDirectoryPath),
            mayBeMissing: mayBeMissing
        )
    }

    /// Every name in a zip, or nil when it could not be listed.
    ///
    /// **Two tools, because neither is enough alone** (implementation review
    /// H1, measured). `zipinfo -1` reads the central directory, so it refuses
    /// a truncated zip; but macOS's ZipInfo 3.00 prints every byte outside
    /// ASCII as `?` under every locale, so `Thème.md` came back as
    /// `The??me.md` and every course with an accent, a curly apostrophe or an
    /// en dash in a page's name was refused. `tar -tf` (bsdtar) under a UTF-8
    /// locale spells the names as stored, but it streams the local headers
    /// and listed a zip cut to 300 bytes as if it were whole. So: `zipinfo`
    /// must exit 0, the names are `tar`'s, and the two counts must agree.
    nonisolated static func zipListing(atPath zipPath: String) -> [String]? {
        guard let central = ReferenceReplacer.listing(
            "/usr/bin/zipinfo", ["-1", zipPath], environment: nil
        ) else {
            return nil
        }
        guard let names = ReferenceReplacer.listing(
            "/usr/bin/tar", ["-tf", zipPath], environment: ["LC_ALL": "en_US.UTF-8"]
        ) else {
            return nil
        }
        if names.count != central.count {
            return nil
        }
        return names
    }

    /// One tool's listing, a line per name, or nil when it did not exit 0.
    nonisolated static func listing(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String]?
    ) -> [String]? {
        let lister: Process = Process()
        lister.executableURL = URL(fileURLWithPath: executable)
        lister.arguments = arguments
        if let environment {
            lister.environment = environment
        }
        let output: Pipe = Pipe()
        lister.standardOutput = output
        lister.standardError = Pipe()
        do {
            try lister.run()
        } catch {
            return nil
        }
        // Read before waiting: a listing of thousands of names is larger
        // than a pipe holds, and a writer blocked on a full pipe never exits.
        let data: Data = output.fileHandleForReading.readDataToEndOfFile()
        lister.waitUntilExit()
        if lister.terminationStatus != 0 {
            return nil
        }
        let text: String = String(decoding: data, as: UTF8.self)
        var names: [String] = []
        for line in text.components(separatedBy: "\n") {
            var name: String = line
            if name.hasSuffix("\r") {
                name.removeLast()
            }
            if !name.isEmpty {
                names.append(name)
            }
        }
        return names
    }

    /// Whether `zipNames` holds every file under the course folder, by its
    /// path from the folder `courses/` (the shape a backup's names have:
    /// `ICS3U-2025/section1/index.md`).
    ///
    /// Names are compared in one Unicode form, because a disk and a zip can
    /// spell `Thème` two ways that are the same name.
    ///
    /// `zipNames` nil counts the course without comparing it with anything,
    /// for the warning's numbers.
    ///
    /// `inTheZipAs` is the folder name the zip's entries begin with, when it
    /// is not the course folder's own: the sweep checks an aside folder
    /// against a backup made under the course's real name.
    nonisolated static func compare(
        zipNames: [String]?,
        courseDirectoryURL: URL,
        mayBeMissing: [String],
        inTheZipAs zipFolderName: String? = nil
    ) -> BackupCheck {
        var inTheZip: Set<String> = []
        for name in zipNames ?? [] {
            var bare: String = name
            while bare.hasSuffix("/") {
                bare.removeLast()
            }
            inTheZip.insert(bare.precomposedStringWithCanonicalMapping)
        }

        let fileManager: FileManager = FileManager.default
        let folderName: String = zipFolderName ?? courseDirectoryURL.lastPathComponent
        // Asked of the folder's resolved path, because the walk hands back
        // `/private/var/…` for a folder named `/var/…`, and a count of path
        // components taken from one spelling is wrong for the other.
        let basePath: String = courseDirectoryURL.resolvingSymlinksInPath().path
        var couldNotRead: Bool = false
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let walker = fileManager.enumerator(
            at: courseDirectoryURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in
                couldNotRead = true
                return true
            }
        ) else {
            return .couldNotBeRead
        }

        var files: Int = 0
        var pages: Int = 0
        var bytes: Int64 = 0
        var missing: Int = 0
        for case let entryURL as URL in walker {
            // The entry's own name is never resolved: a link stays a link.
            let parentPath: String = entryURL.deletingLastPathComponent().resolvingSymlinksInPath().path
            var relative: String = entryURL.lastPathComponent
            if parentPath != basePath {
                guard parentPath.hasPrefix(basePath + "/") else {
                    couldNotRead = true
                    continue
                }
                relative = String(parentPath.dropFirst(basePath.count + 1)) + "/" + relative
            }
            let values: URLResourceValues? = try? entryURL.resourceValues(forKeys: Set(keys))
            let isLink: Bool = values?.isSymbolicLink ?? false
            let isFolder: Bool = (values?.isDirectory ?? false) && !isLink

            if ReferenceReplacer.mayAlwaysBeMissing.contains(entryURL.lastPathComponent)
                || ReferenceReplacer.mayBeMissingAtTheTop.contains(relative)
                || ReferenceReplacer.isUnder(relative, anyOf: mayBeMissing) {
                if isFolder {
                    walker.skipDescendants()
                }
                continue
            }
            if isFolder {
                continue
            }
            files += 1
            if entryURL.pathExtension.lowercased() == "md" {
                pages += 1
            }
            bytes += Int64(values?.fileSize ?? 0)
            if zipNames == nil {
                continue
            }
            let zipName: String = (folderName + "/" + relative).precomposedStringWithCanonicalMapping
            if !inTheZip.contains(zipName) {
                missing += 1
            }
        }
        if couldNotRead {
            return .couldNotBeRead
        }
        if missing > 0 {
            return .isMissing(count: missing)
        }
        return .holdsTheCourse(files: files, pages: pages, bytes: bytes)
    }

    // MARK: - Settling a replace that did not finish

    /// Settles the aside folders a replace left behind because the app
    /// quit, crashed or lost power part way (plan review M1), and says what
    /// it did about each. Called when a working folder is read, BEFORE the
    /// courses are listed, so a course put back is in the list that reading
    /// makes.
    ///
    /// * Somebody is still replacing it (this app's claim on the folder, or
    ///   a live lease from another copy of Plantoir): left alone.
    /// * The old folder name is FREE: the replace stopped before the new
    ///   course was in, so the old course is renamed back. Never removed.
    /// * The old name holds a course AND a backup in `_backups/<OLD>/` is
    ///   OPENED and found to hold every file of the old copy (the same check
    ///   the replace made; implementation review L1): the aside folder is
    ///   removed, unlocked first. A file merely NAMED like a backup is not
    ///   trusted.
    /// * Otherwise (no backup, or none that holds it): left alone, hidden,
    ///   rather than removed with no copy anywhere.
    ///
    /// The check runs `zipinfo` and `tar` here, on the main actor, for each
    /// leftover only. A folder holds one only after a crash part way through
    /// a replace, so an ordinary reading of a folder runs neither.
    @discardableResult
    static func sweepLeftovers(inCoursesDirectory coursesDirectoryURL: URL) -> [SweepOutcome] {
        let fileManager: FileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: coursesDirectoryURL, includingPropertiesForKeys: nil, options: []
        ) else {
            return []
        }

        var outcomes: [SweepOutcome] = []
        for child in children {
            let name: String = child.lastPathComponent
            guard ReferenceReplacer.isAsideName(name) else {
                continue
            }
            let folderName: String = String(name.dropFirst(ReferenceReplacer.asidePrefix.count))
            let key: String = ReferenceStaging.claimKey(for: folderName, inCoursesDirectory: coursesDirectoryURL)
            if ReferenceStaging.claimedStagingKeys.contains(key) {
                continue
            }
            if ReferenceStaging.someoneIsWorkingOn(
                ReferenceStaging.stagingName(for: folderName), inCoursesDirectory: coursesDirectoryURL
            ) {
                continue
            }

            let courseURL: URL = coursesDirectoryURL.appendingPathComponent(folderName)
            if !fileManager.fileExists(atPath: courseURL.path) {
                do {
                    try fileManager.moveItem(at: child, to: courseURL)
                    outcomes.append(SweepOutcome(kind: .putBack, folderName: folderName))
                } catch {
                    outcomes.append(SweepOutcome(kind: .couldNotPutBack, folderName: folderName))
                }
                continue
            }
            guard let backupFileName = ReferenceReplacer.backupThatHolds(
                child, folderName: folderName, coursesDirectoryURL: coursesDirectoryURL
            ) else {
                continue
            }
            if ReferenceStaging.remove(at: child) {
                outcomes.append(SweepOutcome(kind: .tidiedAway, folderName: folderName, backupFileName: backupFileName))
            }
        }
        return outcomes
    }

    /// The trail line for one leftover settled.
    static func trailLine(for outcome: SweepOutcome) -> String {
        switch outcome.kind {
        case .putBack:
            return "put \(outcome.folderName) back on the reference shelf — a replace of it did not finish"
        case .tidiedAway:
            return "tidied away the old copy of \(outcome.folderName) left by a replace — "
                 + "the backup \(outcome.backupFileName ?? "?") was opened and holds it"
        case .couldNotPutBack:
            return "could not put \(outcome.folderName) back on the reference shelf after a replace that "
                 + "did not finish — it is tried again the next time this working folder is opened"
        }
    }

    // MARK: - Private helpers

    /// Removes the staged course, writes the failure line, and hands back
    /// the problem to throw.
    private static func givingUp(
        _ problem: Problem,
        asked: Asked,
        group: String?,
        stagingURL: URL,
        world: World,
        detail: String? = nil
    ) -> Problem {
        _ = world.removeTree(stagingURL)
        var course: String = asked.folderName
        switch problem {
        case .notOnTheShelf(let named), .busy(let named), .openInObsidian(let named),
             .couldNotBackUp(let named), .couldNotReplace(let named), .couldNotPutBackYet(let named):
            course = named
        case .backupIsIncomplete(let named, _):
            course = named
        }
        ActivityTrail.note(
            .referenceCourseCouldNotBeReplaced,
            ReferenceReplacer.failureTrailLine(
                folderName: asked.folderName,
                course: course,
                group: group,
                source: asked.source,
                sentence: problem.errorDescription ?? "",
                detail: detail
            )
        )
        return problem
    }

    /// What a check that failed found, for the trail.
    private static func describe(_ check: BackupCheck, backupFileName: String) -> String {
        switch check {
        case .holdsTheCourse:
            return ""
        case .isMissing(let count):
            let files: String = count == 1 ? "1 file" : "\(count) files"
            return "the backup \(backupFileName) is kept, and does not hold \(files) of the course"
        case .couldNotBeRead:
            return "the backup \(backupFileName) could not be checked"
        }
    }

    /// Whether `relative` is one of `paths` or inside one.
    nonisolated private static func isUnder(_ relative: String, anyOf paths: [String]) -> Bool {
        for path in paths {
            if relative == path || relative.hasPrefix(path + "/") {
                return true
            }
        }
        return false
    }

    /// The newest backup in `courses/_backups/<FOLDER>/` that holds every
    /// file of `asideURL`, by its file name, or nil when none does.
    private static func backupThatHolds(_ asideURL: URL, folderName: String, coursesDirectoryURL: URL) -> String? {
        let folderURL: URL = coursesDirectoryURL
            .appendingPathComponent("_backups").appendingPathComponent(folderName)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        var backups: [BackupItem] = []
        for fileURL in contents {
            if let backup = BackupItem.from(fileURL: fileURL, courseCode: folderName) {
                backups.append(backup)
            }
        }
        backups.sort { first, second in
            return first.backedUpAt > second.backedUpAt
        }
        var mayBeMissing: [String] = []
        let pluginsURL: URL = asideURL
            .appendingPathComponent(ObsidianAddOns.settingsFolderName)
            .appendingPathComponent("plugins")
        for name in ObsidianFigureAddOns.plantoirAddOnFolders(inPluginsAt: pluginsURL) {
            mayBeMissing.append(ObsidianAddOns.settingsFolderName + "/plugins/" + name)
        }
        for backup in backups {
            guard let names = ReferenceReplacer.zipListing(atPath: backup.fileURL.path) else {
                continue
            }
            let check: BackupCheck = ReferenceReplacer.compare(
                zipNames: names, courseDirectoryURL: asideURL, mayBeMissing: mayBeMissing, inTheZipAs: folderName
            )
            if case .holdsTheCourse = check {
                return backup.fileURL.lastPathComponent
            }
        }
        return nil
    }
}
