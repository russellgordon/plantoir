import Foundation

/// Which of a course's two folder lists a name belongs to. Shared folders sit
/// beside the course; per-section folders exist once inside EVERY section, so
/// renaming one is several moves rather than one.
nonisolated enum FolderScope {

    case shared
    case perSection

    // MARK: - Computed properties

    /// The `course_config.json` key holding this scope's folder names.
    var configurationKey: String {
        switch self {
        case .shared:
            return "shared_folders"
        case .perSection:
            return "per_section_folders"
        }
    }

    /// The key this scope uses inside `excluded_items`.
    var exclusionKey: String {
        switch self {
        case .shared:
            return "shared"
        case .perSection:
            return "per_section"
        }
    }
}

/// What a rename actually did, so the teacher can be told rather than left to
/// guess.
struct FolderRenameOutcome {

    // MARK: - Stored properties

    /// How many folders moved on disk. One for a shared folder; one per
    /// section that HAD the folder, for a per-section one — which is not
    /// always every section, because a section a teacher never filled in may
    /// not have it.
    let foldersMoved: Int

    /// How many pages had a link pointing into the folder rewritten.
    let pagesRelinked: Int
}

/// What a rename will do (#899 U4b), read from the disk before anything is
/// written: `SpecialFolderRenamer.plan`, planned into one step by `apply`.
nonisolated struct FolderRenamePlan: Sendable {

    // MARK: - Stored properties

    /// The folders that move, in order.
    let moves: [Move]

    /// The pages whose qualified links change, at their places after the move.
    let pages: [Page]

    // MARK: - Computed properties

    var outcome: FolderRenameOutcome {
        return FolderRenameOutcome(foldersMoved: moves.count, pagesRelinked: pages.count)
    }

    /// One folder's move, judged by its listing.
    struct Move: Sendable {

        // MARK: - Stored properties

        let from: URL

        let to: URL

        let listingSha: String

        /// Whether what moves is a symbolic link (to a folder), read by
        /// `lstat` when planned: a link at the new name is this rename's
        /// only when the rename moved a link there (U4b2-5, review 1, L3).
        var isALink: Bool = false
    }

    /// One page relinked: the bytes read and the bytes it is left holding.
    struct Page: Sendable {

        // MARK: - Stored properties

        let url: URL

        let read: Data

        let rewritten: Data
    }
}

/// A planned step handed to the task that makes it off the main actor.
/// Unchecked, and safe for one reason only: the planner hands the step over
/// and does not touch it again until the task has finished
/// (`SpecialFolderRenamer.make`).
nonisolated struct StepHandedOver: @unchecked Sendable {

    // MARK: - Stored properties

    let step: JournaledStep
}

/// Something that stopped a rename before it could start.
struct FolderRenameProblem: LocalizedError {

    // MARK: - Stored properties

    let sentence: String

    // MARK: - Computed properties

    var errorDescription: String? { return sentence }
}

/// Renaming one of a course's folders from inside Plantoir — on disk, in every
/// section that has one, in the links that name it, and in every
/// `course_config.json` key that mentions it.
///
/// **Why this exists.** Until now the list editors changed the config and
/// nothing else: adding a name wrote an entry pointing at no folder, removing
/// one left a folder full of the teacher's work unreferenced, and renaming was
/// possible only in Obsidian — after which `preflight_update_course_config`
/// discovered the new name and APPENDED it, so the config ended up naming
/// both. Doing the rename here is the one place it can be WITNESSED, which is
/// what lets every key that names the folder be carried across in the same
/// breath instead of being discovered as a mismatch weeks later.
///
/// **It commits to disk immediately, and that is deliberate.** Course Settings
/// otherwise holds edits in memory until Save, with Cancel reverting them. A
/// folder that has really moved cannot be reverted by a Cancel, so pretending
/// otherwise would be a lie; the sheet says so before the teacher agrees. Only
/// the keys that name the folder are written, so their other unsaved edits
/// stay unsaved.
///
/// The sentences live in `contracts/shared-rules.json` → `specialNames.renameFolder`.
enum SpecialFolderRenamer {

    // MARK: - Stored properties

    /// Folders never walked when looking for pages to relink: build output,
    /// Obsidian's own settings, and the deploy markers. All are generated or
    /// private, and `.merged_output` in particular is a whole second copy of
    /// the course, so rewriting links in it would be both pointless and slow.
    nonisolated static let foldersNeverWalked: Set<String> = [
        ".merged_output", "merged_output", ".obsidian", ".netlify_sites",
        ".toolchain", "node_modules", ".git",
    ]

    /// Tests only: called as the plan is about to read each page, off the
    /// main actor, so a test can hold the plan open on an event (U4b part
    /// seven's review, M1). Nil in the app.
    nonisolated(unsafe) static var planReadsAPage: (@Sendable (URL) -> Void)?

    /// Tests only: called once the plan's detached walk has ended, however
    /// it ended, so a test can tell a cancelled plan has stopped. Nil in the
    /// app.
    nonisolated(unsafe) static var planHasEnded: (@Sendable () -> Void)?

    // MARK: - Functions

    /// Why this new name cannot be used, or nil when it can.
    ///
    /// Pure, so the rules can be tested without a course on disk. The
    /// filesystem's own objection — something already sitting where the folder
    /// would go — cannot be answered here and is raised by `rename` instead.
    nonisolated static func problem(
        renaming oldName: String,
        to rawNewName: String,
        existingNames: [String],
        isFinishingAnInterruptedRename: Bool = false
    ) -> String? {
        let newName: String = rawNewName.trimmingCharacters(in: .whitespaces)
        if newName.isEmpty {
            return SpecialNames.renameFolderProblemEmpty
        }
        if newName == oldName {
            return SpecialNames.renameFolderProblemUnchanged
        }
        if newName.contains("/") || newName.contains(":") {
            return SpecialNames.renameFolderProblemHasSeparator
        }
        if newName.hasPrefix(".") {
            return SpecialNames.renameFolderProblemIsHidden
        }
        if newName.lowercased() == "media" {
            return SpecialNames.renameFolderProblemIsMedia
        }
        if looksLikeASectionFolder(newName) {
            return SpecialNames.renameFolderProblemLooksLikeASection(name: newName)
        }
        for existing in existingNames {
            if existing == oldName {
                continue
            }
            if existing.caseInsensitiveCompare(newName) == .orderedSame {
                // Unless this is the SAME rename asking to be finished. A
                // rename moves folders, then rewrites links, then writes the
                // configuration; if it is interrupted after the move, the
                // folders are under the new name and the configuration still
                // says the old one. A build then DISCOVERS the new name on
                // disk and appends it, so the list holds both — and retrying
                // the rename was refused as a clash, with the class folder
                // also unremovable, leaving no way out but hand-editing the
                // JSON. The caller decides this by looking at the disk: the
                // old folder gone, the new one there. That is not two folders
                // competing for a name, it is one rename half done.
                if isFinishingAnInterruptedRename {
                    break
                }
                return SpecialNames.renameFolderProblemAlreadyUsed(name: newName)
            }
        }
        // There is deliberately NO refusal about the class folder keeping the
        // word "class" in its name. There was one for a day: `ClassFolder`
        // used to FIND that folder by looking for the word, so dropping it
        // handed the curriculum map a different folder with nothing said.
        // Russell's point (2026-09-01) was that the constraint was
        // Plantoir's vocabulary imposed on a teacher's — somebody who says
        // "Thread 2, Day 3" would sensibly call the folder "All Days" — so
        // the guess was replaced by a recorded `class_folder`, which
        // `renaming(_:to:scope:in:)` below writes as part of the rename.
        // A rule enforced because a lookup was weak is a rule to delete once
        // the lookup is fixed.
        return nil
    }

    /// Whether this folder was the class folder for a reason, rather than by
    /// being first in the list.
    ///
    /// `ClassFolder.name` answers "where does a class page go?" and always
    /// answers SOMETHING — falling back to the first per-section folder, and
    /// then to a literal, so that a course always has an answer. That fallback
    /// is a guess of convenience, and it must not be frozen into the
    /// configuration by an unrelated rename: a course whose folders are
    /// `["Tasks", "Homework"]` would otherwise come out of renaming `Tasks`
    /// with `class_folder: "Assessments"` recorded for good, after which
    /// adding a real `All Classes` folder would never take over and the
    /// renamed folder could no longer be removed.
    ///
    /// So the key is written only when the answer was CONFIDENT: the course
    /// had already recorded this folder, or the folder names itself. Found by
    /// adversarial review, 2026-09-01.
    nonisolated static func wasSurelyTheClassFolder(
        _ name: String, in folders: [String], recorded: String?
    ) -> Bool {
        if let alreadyRecorded = ClassFolder.matching(recorded, in: folders) {
            return alreadyRecorded.caseInsensitiveCompare(name) == .orderedSame
        }
        if !name.lowercased().contains("class") {
            return false
        }
        return ClassFolder.name(inPerSectionFolders: folders)
            .caseInsensitiveCompare(name) == .orderedSame
    }

    /// Where a rename records that it has started, so that one interrupted
    /// half way can be recognised rather than guessed at.
    ///
    /// Kept while the switch is off (#899 U4b): the rename is one step,
    /// made in shadow, and shadow recovery repairs nothing, so a rename
    /// killed part way is finished from this record, as before. Dropping it
    /// belongs to the piece that turns the switch on (U7).
    ///
    /// Inside `courses/.internal/`, which is where this project already keeps
    /// transient per-course state (the work leases, the tokens). Deliberately
    /// NOT a key in `course_config.json`: the whole failure being handled here
    /// is that the configuration write did not happen.
    nonisolated static func renameMarkerURL(courseDirectory: URL) -> URL {
        return courseDirectory
            .deletingLastPathComponent()
            .appendingPathComponent(".internal")
            .appendingPathComponent("renames")
            .appendingPathComponent(courseDirectory.lastPathComponent + ".json")
    }

    /// Records that a rename is about to move folders. Written BEFORE the
    /// rename's step is made and cleared once it is made (or refused with
    /// nothing changed), so its presence means one thing: a rename got part
    /// way and stopped.
    ///
    /// Its format is `file-formats.json` → `folderRenameRecord`. `moved`
    /// (U4b2-5) is every place, inside the course and spelled with the new
    /// name, that this rename moves or an earlier run of it moved: what a
    /// later part-way ending may call "still called" the new name.
    /// `mayHaveMoved` (U4b2-6) is every place an earlier run's record that
    /// did not say what it moved (one Windows or an older build wrote) may
    /// have moved: a later ending says it cannot tell whether those are this
    /// rename's, and never names them as still called the new name. Each is
    /// an array of strings, left out when empty.
    nonisolated static func recordRenameStarting(
        from oldName: String, to newName: String, scope: FolderScope, courseDirectory: URL,
        moved: [String] = [], mayHaveMoved: [String] = []
    ) {
        let marker: URL = renameMarkerURL(courseDirectory: courseDirectory)
        var note: [String: Any] = [
            "from": oldName,
            "to": newName,
            "scope": scope.exclusionKey,
        ]
        if !moved.isEmpty {
            note["moved"] = moved
        }
        if !mayHaveMoved.isEmpty {
            note["mayHaveMoved"] = mayHaveMoved
        }
        try? FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONSerialization.data(withJSONObject: note, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: marker, options: [.atomic])
        }
    }

    /// A rename record as read (`file-formats.json` → `folderRenameRecord`).
    nonisolated struct RenameRecordNote: Equatable {

        // MARK: - Stored properties

        var from: String
        var to: String
        var scope: String

        /// The places it says it moved, or nil when it does not say (a
        /// record Windows or an older build wrote).
        var moved: [String]?

        /// The places an earlier run may have moved, whose record did not
        /// say (`recordRenameStarting`).
        var mayHaveMoved: [String]
    }

    /// The record's bytes as a note, or nil when they are not a record:
    /// `from`, `to` and `scope` must be strings. Every other key is read
    /// only if it is an array of strings and is otherwise taken as not
    /// said, so a key this build does not know, or one written in another
    /// shape, never makes the whole record unreadable (U4b2-5 review 2, L5).
    nonisolated static func readRenameRecord(_ record: Data?) -> RenameRecordNote? {
        guard let record,
              let object = try? JSONSerialization.jsonObject(with: record) as? [String: Any],
              let from = object["from"] as? String,
              let to = object["to"] as? String,
              let scope = object["scope"] as? String else {
            return nil
        }
        return RenameRecordNote(
            from: from, to: to, scope: scope,
            moved: stringsIn(object["moved"]),
            mayHaveMoved: stringsIn(object["mayHaveMoved"]) ?? []
        )
    }

    /// A JSON value as an array of strings, or nil when it is not one.
    nonisolated static func stringsIn(_ value: Any?) -> [String]? {
        guard let items = value as? [Any] else {
            return nil
        }
        var strings: [String] = []
        for item in items {
            guard let text = item as? String else {
                return nil
            }
            strings.append(text)
        }
        return strings
    }

    /// Clears the record. Called once the rename's step is made, at which
    /// point the rename is whole.
    nonisolated static func clearRenameRecord(courseDirectory: URL) {
        try? FileManager.default.removeItem(at: renameMarkerURL(courseDirectory: courseDirectory))
    }

    /// Whether this rename is one that already happened on disk and never
    /// finished.
    ///
    /// **Two things must agree, and the record is the one that matters.** The
    /// disk state alone — old folder gone, new folder there — is NOT enough,
    /// and reading it as enough was a real bug: it is also the state of a
    /// configuration entry whose folder was never created or was deleted in
    /// Obsidian, renamed onto a genuine second folder. Bypassing the clash
    /// check there would transfer the phantom entry's attributes onto a real
    /// folder — `hidden` among them, which would take that folder's pages off
    /// the next publish with nobody told. The two cases are indistinguishable
    /// on disk, so the disk cannot be the evidence.
    ///
    /// The record written before the folders move is what tells them apart. It
    /// is still checked against the disk as well, so a stale record left by
    /// something else cannot open the bypass on its own.
    /// The name a rename from this folder was heading for when it stopped, or
    /// nil when nothing was interrupted.
    ///
    /// Returns the TARGET rather than a yes/no, because the caller asks this
    /// when the rename sheet opens — before the teacher has typed anything —
    /// and the recorded target is both the answer and a sensible thing to fill
    /// the field with.
    nonisolated static func interruptedRenameTarget(
        from oldName: String,
        scope: FolderScope,
        courseDirectory: URL,
        sectionNumbers: [Int],
        fileManager: FileManager = .default
    ) -> String? {
        guard let note = readRenameRecord(try? Data(contentsOf: renameMarkerURL(courseDirectory: courseDirectory))),
              note.from.caseInsensitiveCompare(oldName) == .orderedSame,
              note.scope == scope.exclusionKey else {
            return nil
        }
        let target: String = note.to
        let agrees: Bool = looksLikeAnInterruptedRename(
            from: oldName, to: target, scope: scope,
            courseDirectory: courseDirectory, sectionNumbers: sectionNumbers,
            fileManager: fileManager
        )
        return agrees ? target : nil
    }

    nonisolated static func looksLikeAnInterruptedRename(
        from oldName: String,
        to newName: String,
        scope: FolderScope,
        courseDirectory: URL,
        sectionNumbers: [Int],
        fileManager: FileManager = .default
    ) -> Bool {
        let data: Data? = try? Data(contentsOf: renameMarkerURL(courseDirectory: courseDirectory))
        guard recordNames(data, from: oldName, to: newName, scope: scope) else {
            return false
        }
        let oldPlaces: [URL] = folderLocations(
            named: oldName, scope: scope,
            courseDirectory: courseDirectory, sectionNumbers: sectionNumbers
        )
        let newPlaces: [URL] = folderLocations(
            named: newName, scope: scope,
            courseDirectory: courseDirectory, sectionNumbers: sectionNumbers
        )
        for place in oldPlaces where fileManager.fileExists(atPath: place.path) {
            return false
        }
        for place in newPlaces where fileManager.fileExists(atPath: place.path) {
            return true
        }
        return false
    }

    /// Whether a name is one Plantoir gives a section's own folder.
    nonisolated static func looksLikeASectionFolder(_ name: String) -> Bool {
        let lowercased: String = name.lowercased()
        if !lowercased.hasPrefix("section") {
            return false
        }
        let tail: Substring = lowercased.dropFirst("section".count)
        if tail.isEmpty {
            return false
        }
        for character in tail {
            if !character.isNumber {
                return false
            }
        }
        return true
    }

    /// Every place on disk this folder lives, in the order they will be moved.
    nonisolated static func folderLocations(
        named name: String,
        scope: FolderScope,
        courseDirectory: URL,
        sectionNumbers: [Int]
    ) -> [URL] {
        switch scope {
        case .shared:
            return [courseDirectory.appendingPathComponent(name)]
        case .perSection:
            var locations: [URL] = []
            for number in sectionNumbers {
                locations.append(
                    courseDirectory
                        .appendingPathComponent("section\(number)")
                        .appendingPathComponent(name)
                )
            }
            return locations
        }
    }

    /// Moves the folder, then points every qualified link at its new name,
    /// as ONE step through the door (#899 U4b): every folder's move and
    /// every page's relink, all of them or none. The configuration is the
    /// caller's to plan into the same step (`CourseSettingsView.renameFolder`
    /// plans `course_config.json` too); this form, for a caller with no
    /// settings to change, makes the step itself.
    ///
    /// The rename record is this run's only while this run is unfinished
    /// (#899 U4b2-3): `RenameRecordClaim` decides every exit, the same one
    /// `CourseSettingsView.renameFolder` uses.
    @discardableResult
    nonisolated static func rename(
        _ oldName: String,
        to newName: String,
        scope: FolderScope,
        courseDirectory: URL,
        sectionNumbers: [Int],
        fileManager: FileManager = .default
    ) throws -> FolderRenameOutcome {
        let planned: FolderRenamePlan = try plan(
            oldName, to: newName, scope: scope,
            courseDirectory: courseDirectory, sectionNumbers: sectionNumbers, fileManager: fileManager
        )
        let step: JournaledStep = JournaledStep(
            courseCode: courseDirectory.lastPathComponent, courseDirectory: courseDirectory,
            section: nil, maker: UndoStepMaker.sheet("renameFolder"), holds: "course"
        )
        apply(planned, to: step)
        var record: RenameRecordClaim = RenameRecordClaim(
            from: oldName, to: newName, scope: scope, courseDirectory: courseDirectory,
            changesTheSettings: false
        )
        if !planned.moves.isEmpty {
            record.renameIsStarting(moving: planned.moves, sectionNumbers: sectionNumbers)
        }
        do {
            try step.make()
        } catch let stopped as JournaledStepError {
            record.stepWasNotMade(stopped)
            throw stopped
        } catch {
            record.nothingWasChanged()
            throw error
        }
        record.renameIsWhole()
        return planned.outcome
    }

    /// Whether a record's bytes name this rename: the same folder, the same
    /// target, the same scope.
    nonisolated static func recordNames(
        _ record: Data?, from oldName: String, to newName: String, scope: FolderScope
    ) -> Bool {
        guard recordNamesTheFolder(record, from: oldName, scope: scope),
              let note = readRenameRecord(record),
              note.to.caseInsensitiveCompare(newName) == .orderedSame else {
            return false
        }
        return true
    }

    /// Whether a record's bytes name a rename OF this folder, to any name:
    /// the same folder, the same scope.
    nonisolated static func recordNamesTheFolder(
        _ record: Data?, from oldName: String, scope: FolderScope
    ) -> Bool {
        guard let note = readRenameRecord(record),
              note.from.caseInsensitiveCompare(oldName) == .orderedSame,
              note.scope == scope.exclusionKey else {
            return false
        }
        return true
    }

    /// The trail line (`folder renamed`) when the record could not be left
    /// as this run must leave it (review 1 of U4b2-3, L2): a record left
    /// behind by mistake greys the one-section restore and may be read as an
    /// unfinished rename, so it is told rather than kept quiet.
    /// Said as the disk is (review 2, L-B): "renamed" only once the rename
    /// is whole, "did not rename" after a refusal that changed nothing.
    nonisolated static func renameNoteNotTidiedLine(
        renaming oldName: String, to newName: String, course: String, wasRenamed: Bool, said: String
    ) -> String {
        let whatHappened: String
        if wasRenamed {
            whatHappened = "renamed the folder " + oldName + " to " + newName + " in " + course + ", but"
        } else {
            whatHappened = "did not rename the folder " + oldName + " to " + newName + " in " + course + ", and"
        }
        return whatHappened
            + " could not tidy the note kept while a folder rename is unfinished (" + said + ")"
    }

    /// What a rename will do, read from the disk and written nowhere: each
    /// folder that moves (with its listing's SHA-256, the move's pair) and
    /// each page whose qualified links change (the bytes read, the bytes
    /// rewritten, at the page's place AFTER the move). Read off the main
    /// actor; `apply` plans it into a step.
    ///
    /// Nothing is planned unless EVERY destination is free, so a per-section
    /// rename cannot get half way through four sections: the step moves all
    /// of them or none. A page that cannot be read is left out, as before.
    nonisolated static func plan(
        _ oldName: String,
        to newName: String,
        scope: FolderScope,
        courseDirectory: URL,
        sectionNumbers: [Int],
        fileManager: FileManager = .default
    ) throws -> FolderRenamePlan {
        // Asked of the config on DISK, because this function takes a folder
        // rather than a loaded course — and a course kept for reference does
        // not have its folders renamed. Course Settings is not offered on one;
        // this catches every other caller.
        if let frozen = ReferenceLock.frozenCourseOnDisk(at: courseDirectory) {
            throw frozen
        }
        let locations: [URL] = folderLocations(
            named: oldName, scope: scope,
            courseDirectory: courseDirectory, sectionNumbers: sectionNumbers
        )

        var moves: [FolderRenamePlan.Move] = []
        for location in locations {
            // A Cancel stops the walk between folders and between pages
            // (part seven's review, M1): the plan writes nothing, so it can
            // stop anywhere.
            try Task.checkCancellation()
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: location.path, isDirectory: &isDirectory) {
                continue
            }
            if !isDirectory.boolValue {
                continue
            }
            let destination: URL = location
                .deletingLastPathComponent()
                .appendingPathComponent(newName)
            // A rename that only changes capitalisation asks the filesystem to
            // move a folder onto itself. On a case-insensitive volume — which
            // is the default on a Mac — the destination "exists" because it IS
            // the source, so the check below would refuse a rename that is
            // perfectly reasonable. The door judges it as one item under two
            // spellings (`undoJournal.opKinds.move`, U4b).
            let isOnlyACapitalisationChange: Bool =
                oldName.caseInsensitiveCompare(newName) == .orderedSame
            if !isOnlyACapitalisationChange && fileManager.fileExists(atPath: destination.path) {
                throw FolderRenameProblem(
                    sentence: SpecialNames.renameFolderProblemDestinationExists(name: newName)
                )
            }
            guard let listingSha = UndoTreeReading.read(at: location).listingSha else {
                // A folder whose content cannot be read cannot be judged as a
                // pair, so nothing is planned and nothing is changed.
                let refusal: UndoRefusal = .cannotTellNow(path: location.path)
                throw JournaledStepError.refused(refusal, fileName: location.lastPathComponent)
            }
            let isALink: Bool = presence(at: location, spelledExactly: false) == .link
            moves.append(FolderRenamePlan.Move(from: location, to: destination, listingSha: listingSha, isALink: isALink))
        }

        var pages: [FolderRenamePlan.Page] = []
        for pageURL in markdownPages(in: courseDirectory, fileManager: fileManager) {
            try Task.checkCancellation()
            planReadsAPage?(pageURL)
            try Task.checkCancellation()
            guard let read = try? Data(contentsOf: pageURL), let text = String(data: read, encoding: .utf8) else {
                continue
            }
            if FolderPathRewriter.countReferences(to: oldName, in: text) == 0 {
                continue
            }
            let rewritten: String = FolderPathRewriter.rewriting(text, folderNamed: oldName, to: newName)
            if rewritten == text {
                continue
            }
            pages.append(FolderRenamePlan.Page(
                url: placeAfter(moves, of: pageURL), read: read, rewritten: Data(rewritten.utf8)
            ))
        }
        return FolderRenamePlan(moves: moves, pages: inPathOrder(pages, under: courseDirectory))
    }

    /// Plans a rename OFF the main actor, and gives up waiting the moment the
    /// caller is cancelled (U4b part seven's review, M1): Cancel gives the
    /// course back at once.
    ///
    /// The walk runs in a detached task, because it must not hold the main
    /// actor, and a detached task does not inherit cancellation; so the
    /// caller's cancellation is forwarded to it (`withTaskCancellationHandler`)
    /// and `plan` stops at its next page (`Task.checkCancellation`). A read
    /// that blocks inside the system (an evicted iCloud page, a network
    /// volume gone away) cannot be interrupted, so the caller does not wait
    /// for the walk to stop: the result comes through a stream, whose
    /// `next()` returns nil as soon as the waiting task is cancelled. The
    /// walk then ends on its own, writes nothing, and whatever it finds is
    /// never read by anyone: the stream it would be delivered through has
    /// already been given up.
    nonisolated static func planHaltingAtCancel(
        _ oldName: String,
        to newName: String,
        scope: FolderScope,
        courseDirectory: URL,
        sectionNumbers: [Int]
    ) async throws -> FolderRenamePlan {
        let (results, delivery) = AsyncThrowingStream<FolderRenamePlan, Error>.makeStream()
        let walk: Task<Void, Never> = Task.detached(priority: .userInitiated) {
            do {
                let planned: FolderRenamePlan = try plan(
                    oldName, to: newName, scope: scope,
                    courseDirectory: courseDirectory, sectionNumbers: sectionNumbers
                )
                delivery.yield(planned)
                delivery.finish()
            } catch {
                delivery.finish(throwing: error)
            }
            planHasEnded?()
        }
        return try await withTaskCancellationHandler {
            var waiting: AsyncThrowingStream<FolderRenamePlan, Error>.Iterator = results.makeAsyncIterator()
            if let planned = try await waiting.next() {
                return planned
            }
            // Nil only when the wait was given up at Cancel.
            throw CancellationError()
        } onCancel: {
            walk.cancel()
        }
    }

    /// Plans a rename into `step`: each folder's move first, then each page
    /// at its place after the move, so a page inside a moved folder is an
    /// edit the move carries (`undoJournal.opKinds.wholeOps`).
    nonisolated static func apply(_ planned: FolderRenamePlan, to step: JournaledStep) {
        for move in planned.moves {
            step.moveFolder(move.from, to: move.to, listingSha: move.listingSha)
        }
        for page in planned.pages {
            step.write(page.rewritten, to: page.url, plannedFrom: page.read)
        }
    }

    /// Makes a planned rename's step OFF the main actor (U4b part four's
    /// review, M1): the door's check and its swap each read and hash every
    /// file in every moved folder, a megabyte at a time, which on the main
    /// actor froze the window for about half a second per gigabyte. The
    /// caller awaits it, showing the rename under way.
    ///
    /// The two reads are kept, not shared: the check is the step's judgement
    /// under the lock (the contract's `opKinds.move` rule, the same for a
    /// make, a Redo and recovery's put-back), and the swap's read is its last
    /// look just before the rename. Letting the first stand for the second
    /// would leave the time between them (staging every page) unseen, and
    /// letting the second stand for the first would make a forward move a
    /// case of its own in the contract.
    ///
    /// The step is handed over whole: the caller plans it, then touches it
    /// no more until this returns.
    nonisolated static func make(_ step: JournaledStep) async throws {
        let handed: StepHandedOver = StepHandedOver(step: step)
        try await Task.detached(priority: .userInitiated) {
            try handed.step.make()
        }.value
    }

    /// The sentence when a rename's step is refused and nothing was changed
    /// (`shared-rules.json` → `undo.wording.renameFolderNothingWasChanged`).
    nonisolated static func nothingWasChanged(renaming oldName: String, said: String) -> String {
        return "“\(oldName)” was not renamed, and nothing was changed: \(said)"
    }

    /// The sentence when a rename's step was refused part way and could not
    /// all be put back (`undo.wording.renameFolderStoppedPartWay`): `said`
    /// names each file kept beside its page.
    nonisolated static func stoppedPartWay(renaming oldName: String, said: String) -> String {
        return "“\(oldName)” was not renamed, and Plantoir could not put everything back as it was: \(said)"
    }

    /// The sentence when a rename's step stopped part way with a folder
    /// still at its new name, because its move back failed
    /// (`undo.wording.renameFolderRenamedOnlyInPart`): `places` are those
    /// folders inside the course, spelled with their new name.
    nonisolated static func renamedOnlyInPart(renaming oldName: String, to newName: String, places: [String], said: String) -> String {
        var joined: String = ""
        for place in places {
            if !joined.isEmpty {
                joined += ", "
            }
            joined += "“" + place + "”"
        }
        return "“\(oldName)” was renamed only in part, and Plantoir could not put everything back as it was. "
            + "Still called “\(newName)”: \(joined). \(said)"
    }

    /// The sentence when a rename's step stopped part way, no folder is
    /// known to be at its new name, and some place could not be read or may
    /// have been moved by an earlier run whose record did not say
    /// (`undo.wording.renameFolderMayBeRenamedInPart`, U4b2-6): never "was
    /// not renamed", which the app could not check.
    nonisolated static func mayBeRenamedInPart(renaming oldName: String, to newName: String, places: [String], said: String) -> String {
        var joined: String = ""
        for place in places {
            if !joined.isEmpty {
                joined += ", "
            }
            joined += "“" + place + "”"
        }
        return "“\(oldName)” may have been renamed only in part, and Plantoir could not put everything back as it was. "
            + "Plantoir could not tell whether this rename left these called “\(newName)”: \(joined). \(said)"
    }

    /// The trail line and the sentence of a rename's step stopped part way,
    /// from what it left at the new name (the final sweep, M1; U4b2-5;
    /// U4b2-6): renamed only in part when a folder of this rename is known
    /// to be at its new name; may have been renamed in part when none is but
    /// a place could not be read or may be an earlier run's; otherwise not
    /// renamed. The trail names every place either way.
    nonisolated static func partWayEnding(
        renaming oldName: String, to newName: String, course: String, scope: FolderScope,
        left: LeftAtTheNewName, keptBeside: Int, said: String
    ) -> (line: String, sentence: String) {
        if !left.places.isEmpty {
            let line: String = renamedOnlyInPartLine(
                renaming: oldName, to: newName, course: course, scope: scope, places: left.places,
                keptBeside: keptBeside, unreadable: left.unreadable, cannotTellWhose: left.cannotTellWhose
            )
            return (line: line, sentence: renamedOnlyInPart(renaming: oldName, to: newName, places: left.places, said: said))
        }
        if !left.cannotTell.isEmpty {
            let line: String = mayBeRenamedInPartLine(
                renaming: oldName, to: newName, course: course, scope: scope, keptBeside: keptBeside,
                unreadable: left.unreadable, cannotTellWhose: left.cannotTellWhose
            )
            return (line: line, sentence: mayBeRenamedInPart(renaming: oldName, to: newName, places: left.cannotTell, said: said))
        }
        let line: String = stoppedPartWayLine(
            renaming: oldName, to: newName, course: course, scope: scope, keptBeside: keptBeside
        )
        return (line: line, sentence: stoppedPartWay(renaming: oldName, said: said))
    }

    /// How many files were kept beside their pages, as a trail line says it.
    nonisolated static func keptBesideWords(_ count: Int) -> String {
        if count == 1 {
            return "1 file kept beside its page"
        }
        return String(count) + " files kept beside their pages"
    }

    /// The trail line (`folder renamed`) for a rename stopped part way with
    /// folders left at their new name (the final sweep, M1). It names the
    /// folders, which are the course's own special folders, and counts the
    /// kept files, never naming a page.
    nonisolated static func renamedOnlyInPartLine(
        renaming oldName: String, to newName: String, course: String, scope: FolderScope,
        places: [String], keptBeside: Int, unreadable: [String] = [], cannotTellWhose: [String] = []
    ) -> String {
        var joined: String = ""
        for place in places {
            if !joined.isEmpty {
                joined += ", "
            }
            joined += place
        }
        return "renamed the folder " + oldName + " to " + newName + " in " + course
            + " only in part, and could not put everything back (" + scope.configurationKey
            + ", still called " + newName + ": " + joined + "; " + keptBesideWords(keptBeside)
            + couldNotTellWords(unreadable) + couldNotTellWhoseWords(cannotTellWhose) + ")"
    }

    /// The trail's clause for places whose state could not be read
    /// (U4b2-5, review 1, L2), or nothing when every place was read.
    nonisolated static func couldNotTellWords(_ unreadable: [String]) -> String {
        if unreadable.isEmpty {
            return ""
        }
        var joined: String = ""
        for place in unreadable {
            if !joined.isEmpty {
                joined += ", "
            }
            joined += place
        }
        return "; could not tell whether these are at the new name: " + joined
    }

    /// The trail's clause for folders at the new name that an earlier run
    /// whose record did not say what it moved may have moved (U4b2-6), or
    /// nothing when there are none.
    nonisolated static func couldNotTellWhoseWords(_ cannotTellWhose: [String]) -> String {
        if cannotTellWhose.isEmpty {
            return ""
        }
        var joined: String = ""
        for place in cannotTellWhose {
            if !joined.isEmpty {
                joined += ", "
            }
            joined += place
        }
        return "; could not tell whether this rename moved these: " + joined
    }

    /// The trail line (`folder renamed`) for a rename stopped part way with
    /// every folder back at its old name but files kept beside their pages
    /// (the final sweep, M1).
    nonisolated static func stoppedPartWayLine(
        renaming oldName: String, to newName: String, course: String, scope: FolderScope, keptBeside: Int
    ) -> String {
        return "did not rename the folder " + oldName + " to " + newName + " in " + course
            + ", and could not put everything back (" + scope.configurationKey + ", "
            + keptBesideWords(keptBeside) + ")"
    }

    /// The trail line (`folder renamed`) for a rename stopped part way with
    /// no folder known to be at its new name but a place that could not be
    /// read or that an earlier run whose record did not say may have moved
    /// (U4b2-6): never "did not rename", which could not be checked.
    nonisolated static func mayBeRenamedInPartLine(
        renaming oldName: String, to newName: String, course: String, scope: FolderScope, keptBeside: Int,
        unreadable: [String], cannotTellWhose: [String]
    ) -> String {
        return "may have renamed the folder " + oldName + " to " + newName + " in " + course
            + " only in part, and could not put everything back (" + scope.configurationKey + ", "
            + keptBesideWords(keptBeside) + couldNotTellWords(unreadable) + couldNotTellWhoseWords(cannotTellWhose) + ")"
    }

    /// A place inside the course, as the trail and the sheet name it.
    nonisolated static func placeInside(_ url: URL, courseDirectory: URL) -> String {
        let prefix: String = courseDirectory.standardizedFileURL.path + "/"
        let path: String = url.standardizedFileURL.path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
    }

    /// The places, inside the course, that a record of this same rename
    /// says it moved (its `moved`), or nil when the record is not this
    /// rename's or does not say (a record Windows or an earlier version
    /// wrote).
    nonisolated static func placesMoved(
        byTheRecord record: Data?, renaming oldName: String, to newName: String, scope: FolderScope
    ) -> [String]? {
        guard recordNames(record, from: oldName, to: newName, scope: scope),
              let note = readRenameRecord(record),
              let moved = note.moved else {
            return nil
        }
        return moved
    }

    /// The places, inside the course, that an earlier run of this same
    /// rename may have moved without its record saying so (U4b2-5 review 2,
    /// L1 and L2): those its record carries as `mayHaveMoved`, and, when the
    /// record says nothing of what it moved, each folder now at the new name
    /// whose old name beside it is absent or cannot be read. Nothing here is
    /// known to be this rename's: a folder made by hand at the new name
    /// reads the same.
    nonisolated static func placesAnEarlierRunMayHaveMoved(
        byTheRecord record: Data?, renaming oldName: String, to newName: String, scope: FolderScope,
        courseDirectory: URL, sectionNumbers: [Int]
    ) -> [String] {
        guard recordNames(record, from: oldName, to: newName, scope: scope),
              let note = readRenameRecord(record) else {
            return []
        }
        var places: [String] = note.mayHaveMoved
        if note.moved != nil {
            return places
        }
        let isCaseOnly: Bool = oldName.caseInsensitiveCompare(newName) == .orderedSame
        let newPlaces: [URL] = folderLocations(
            named: newName, scope: scope, courseDirectory: courseDirectory, sectionNumbers: sectionNumbers
        )
        for place in newPlaces {
            let inside: String = placeInside(place, courseDirectory: courseDirectory)
            if places.contains(inside) {
                continue
            }
            let oldPlace: URL = place.deletingLastPathComponent().appendingPathComponent(oldName)
            switch presence(at: oldPlace, spelledExactly: isCaseOnly) {
            case .absent, .unreadable:
                break
            case .folder, .link, .somethingElse:
                continue
            }
            switch presence(at: place, spelledExactly: isCaseOnly) {
            case .folder, .unreadable:
                places.append(inside)
            case .absent, .link, .somethingElse:
                continue
            }
        }
        return places
    }

    /// What a rename stopped part way left at the new name
    /// (`foldersAtTheirNewName`).
    nonisolated struct LeftAtTheNewName: Equatable {

        // MARK: - Stored properties

        /// This rename's folders at the new name now, by place inside the
        /// course.
        var places: [String] = []

        /// This rename's places the disk could not be read at, each with
        /// what the system said: named on the trail, never guessed at.
        var unreadable: [String] = []

        /// Folders at the new name that an earlier run whose record did not
        /// say what it moved may have moved (`placesAnEarlierRunMayHaveMoved`):
        /// named on the trail as places it cannot tell are this rename's,
        /// never as still called the new name.
        var cannotTellWhose: [String] = []

        /// Every place in `unreadable` and `cannotTellWhose`, bare, as the
        /// sheet names them when nothing is known to be at the new name.
        var cannotTell: [String] = []
    }

    /// This rename's folders that are at the new name now, by place inside
    /// the course: what a rename stopped part way left renamed (U4b2-5).
    ///
    /// **A place counts only if it belongs to this rename AND the disk shows
    /// it at the new name** (review 1, M1). Belongs: the destination of one
    /// of this run's planned moves, or a place the record of the rename this
    /// run is finishing says it moved (`placesMoved(byTheRecord:)`; a run
    /// finishing an interrupted rename moves nothing itself, the earlier run
    /// did). A folder that was at the new name all along (one made by hand
    /// in a section with no folder at the old name) is never "still called"
    /// the new name. A record that names this rename but not its places
    /// (written by Windows or an earlier version) names none: the places it
    /// may have moved are `cannotTellWhose` (U4b2-6), told, never counted.
    ///
    /// The disk decides only which of those places are at the new name:
    /// a folder, by `lstat`, never followed; a link only where this run moved
    /// a link (review 1, L3); a capitalisation-only rename counts a place only
    /// when its directory lists the new spelling. Whatever is at the OLD name
    /// does not count (U4b part six's review, L1). A place that cannot be
    /// read (a refused `lstat`, a listing that fails) is neither counted nor
    /// taken as absent: it is returned in `unreadable` (review 1, L2).
    nonisolated static func foldersAtTheirNewName(
        renaming oldName: String, to newName: String, scope: FolderScope,
        courseDirectory: URL, sectionNumbers: [Int],
        planned moves: [FolderRenamePlan.Move], earlierRecord: Data?
    ) -> LeftAtTheNewName {
        var result: LeftAtTheNewName = LeftAtTheNewName()
        let isCaseOnly: Bool = oldName.caseInsensitiveCompare(newName) == .orderedSame
        let recorded: [String]? = placesMoved(byTheRecord: earlierRecord, renaming: oldName, to: newName, scope: scope)
        let mayHaveMoved: [String] = placesAnEarlierRunMayHaveMoved(
            byTheRecord: earlierRecord, renaming: oldName, to: newName, scope: scope,
            courseDirectory: courseDirectory, sectionNumbers: sectionNumbers
        )
        let newPlaces: [URL] = folderLocations(
            named: newName, scope: scope, courseDirectory: courseDirectory, sectionNumbers: sectionNumbers
        )
        for place in newPlaces {
            let inside: String = placeInside(place, courseDirectory: courseDirectory)
            var movedHereThisRun: Bool = false
            var movedALinkHere: Bool = false
            for move in moves {
                if move.to.standardizedFileURL.path == place.standardizedFileURL.path {
                    movedHereThisRun = true
                    movedALinkHere = move.isALink
                }
            }
            var belongs: Bool = movedHereThisRun
            if let recorded, recorded.contains(inside) {
                belongs = true
            }
            if !belongs {
                if !mayHaveMoved.contains(inside) {
                    continue
                }
                switch presence(at: place, spelledExactly: isCaseOnly) {
                case .folder:
                    result.cannotTellWhose.append(inside)
                    result.cannotTell.append(inside)
                case .unreadable(let said):
                    result.unreadable.append(inside + " (" + said + ")")
                    result.cannotTell.append(inside)
                case .absent, .link, .somethingElse:
                    continue
                }
                continue
            }
            switch presence(at: place, spelledExactly: isCaseOnly) {
            case .folder:
                result.places.append(inside)
            case .link:
                if movedALinkHere {
                    result.places.append(inside)
                }
            case .unreadable(let said):
                result.unreadable.append(inside + " (" + said + ")")
                result.cannotTell.append(inside)
            case .absent, .somethingElse:
                continue
            }
        }
        return result
    }

    /// What is at a path, read by `lstat` and never followed.
    nonisolated enum Presence: Equatable {
        case absent
        case folder
        case link
        case somethingElse
        case unreadable(String)
    }

    /// What is at `url`. `spelledExactly` (a capitalisation-only rename)
    /// also asks the directory's listing for this spelling, since another
    /// spelling "exists" there too on a case-insensitive volume. Only "no
    /// such file" is absent; any other refusal is `unreadable`.
    nonisolated static func presence(at url: URL, spelledExactly: Bool) -> Presence {
        var information: stat = stat()
        let found: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return lstat(path, &information)
        }
        if found != 0 {
            let code: Int32 = errno
            if code == ENOENT || code == ENOTDIR {
                return .absent
            }
            return .unreadable(String(cString: strerror(code)))
        }
        if spelledExactly {
            do {
                let listed: [String] = try FileManager.default.contentsOfDirectory(
                    atPath: url.deletingLastPathComponent().path
                )
                if !listed.contains(url.lastPathComponent) {
                    return .absent
                }
            } catch {
                return .unreadable(error.localizedDescription)
            }
        }
        let kind: mode_t = information.st_mode & S_IFMT
        if kind == S_IFDIR {
            return .folder
        }
        if kind == S_IFLNK {
            return .link
        }
        return .somethingElse
    }

    /// Where a page is once the folders move: under a move's `to` when it
    /// is inside its `from`.
    nonisolated static func placeAfter(_ moves: [FolderRenamePlan.Move], of url: URL) -> URL {
        let path: String = url.standardizedFileURL.path
        for move in moves {
            let from: String = move.from.standardizedFileURL.path
            if path.hasPrefix(from + "/") {
                return URL(fileURLWithPath: move.to.standardizedFileURL.path + String(path.dropFirst(from.count)))
            }
        }
        return url
    }

    /// A rename's pages in the one order of paths (`ClassPages.isInPathOrder`),
    /// each by its place after the move, never the order the disk listed
    /// them (hashed on APFS, sorted on HFS+ and NTFS): review 1 of U4b2-11,
    /// M1. Each place is read once, the course folder canonical and the page's
    /// own path inside it as written (`UndoFolderPlaces.placeResolvingOnlyAbove`):
    /// a carried page's place is built from the course's own spelling
    /// (`/var/...`) and a page outside from the walk's (`/private/var/...`),
    /// and a linked page is ordered by its own place, never its target's
    /// (review 2 of U4b2-11, LOW B).
    nonisolated static func inPathOrder(_ pages: [FolderRenamePlan.Page], under courseDirectory: URL) -> [FolderRenamePlan.Page] {
        var keyed: [(place: URL, page: FolderRenamePlan.Page)] = []
        for page in pages {
            let place: String = UndoFolderPlaces.placeResolvingOnlyAbove(courseDirectory, of: page.url)
                ?? UndoFolderPlaces.canonicalPath(of: page.url)
            keyed.append((place: URL(fileURLWithPath: place), page: page))
        }
        keyed.sort { first, second in
            return ClassPages.isInPathOrder(first.place, second.place)
        }
        var ordered: [FolderRenamePlan.Page] = []
        for entry in keyed {
            ordered.append(entry.page)
        }
        return ordered
    }

    /// Every Markdown page under a course, skipping generated and private trees.
    nonisolated static func markdownPages(in courseDirectory: URL, fileManager: FileManager = .default) -> [URL] {
        guard let walker = fileManager.enumerator(
            at: courseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var pages: [URL] = []
        for case let url as URL in walker {
            if foldersNeverWalked.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            if url.pathExtension.lowercased() == "md" {
                pages.append(url)
            }
        }
        return pages
    }

    /// The configuration with every key that named the old folder naming the
    /// new one instead.
    ///
    /// Pure and whole-dictionary, so it can be applied to the file and to the
    /// in-memory copy from the same code — the two cannot disagree about what
    /// a rename means. The keys are listed in the contract under
    /// `specialNames.renameFolder.carriesAcross`; a key added there and not
    /// here is what a reviewer should look for.
    nonisolated static func renaming(
        _ oldName: String,
        to newName: String,
        scope: FolderScope,
        in values: [String: Any],
        foldersWithPages: [String] = [],
        foldersWithLetterFirstPages: [String]? = nil
    ) -> [String: Any] {
        var updated: [String: Any] = values

        // Which special folder, if either, this WAS — worked out before the
        // list is rewritten, because both answers are derived from it.
        let perSectionFolders: [String] = values["per_section_folders"] as? [String] ?? []
        let sharedFolders: [String] = values["shared_folders"] as? [String] ?? []
        let wasTheClassFolder: Bool = (scope == .perSection) && wasSurelyTheClassFolder(
            oldName, in: perSectionFolders, recorded: values["class_folder"] as? String
        )
        // ONE OF the course's curriculum folders (#128) — the declared ones
        // and the ones it resolves to, the second read from the disk by the
        // caller (`foldersWithPages`), so a scratch two-curricula course renaming the
        // Ontario folder its map comes from is recognised even though the
        // by-name rule would have picked College Board.
        let declaredCurriculum: [String] = CurriculumFolderRule.declaredFolders(
            list: values["curriculum_folders"], legacy: values["curriculum_folder"]
        )
        let resolvedCurriculum: [String] = CurriculumFolderRule.resolvedFolders(
            declared: declaredCurriculum, in: sharedFolders, withPages: foldersWithPages,
            withLetterFirstPages: foldersWithLetterFirstPages
        )
        var wasACurriculumFolder: Bool = false
        if scope == .shared {
            for name in declaredCurriculum + resolvedCurriculum
            where name.caseInsensitiveCompare(oldName) == .orderedSame {
                wasACurriculumFolder = true
            }
        }

        updated[scope.configurationKey] = renaming(
            oldName, to: newName, inList: values[scope.configurationKey] as? [String] ?? []
        )

        // **Materialised on rename, not merely carried across.** A course made
        // from scratch has `curriculum_folder: null` and no `class_folder` at
        // all, so both are found by guessing at the name — "curriculum" in it,
        // or "class" in it. Rename `Curriculum` to `Expectations` without
        // writing the key and the guess stops finding it, the map is built
        // from nothing, and nobody is told; the coverage check does not fire,
        // because from its point of view the folder was never there. Writing
        // the name down at the one moment Plantoir WITNESSES the rename is the
        // whole reason renaming belongs in the app.
        if wasTheClassFolder {
            updated["class_folder"] = newName
        }
        if wasACurriculumFolder {
            // The declared list, or — for a course that declared nothing —
            // the folders it resolves to, with the old name replaced IN PLACE:
            // the primary folder stays primary, and its map keeps its title.
            let base: [String] = declaredCurriculum.isEmpty ? resolvedCurriculum : declaredCurriculum
            var materialised: [String] = []
            for name in base {
                if name.caseInsensitiveCompare(oldName) == .orderedSame {
                    materialised.append(newName)
                } else {
                    materialised.append(name)
                }
            }
            updated["curriculum_folders"] = materialised
            // The primary folder in the legacy key too, for an older Plantoir
            // that reads only that one (Russell's ruling on the #128 review).
            if let primary = materialised.first {
                updated["curriculum_folder"] = primary
            }
        }

        // Three flat lists that name folders from EITHER scope, so each is
        // rewritten whichever list the folder came from.
        //
        // **`hidden` is the one that matters, and it was missed until the real
        // app was driven on 2026-09-04.** It holds the folders and files kept
        // OUT of the built site. Leave it naming the old folder and a rename
        // silently UN-HIDES it: the very next publish puts pages the teacher
        // deliberately hid in front of students. The course this was found on
        // had "Curriculum" in that list. Publishing what a teacher hid is a
        // failure this project has already had once, from a different cause,
        // and it is the worst thing in this file's reach.
        for key in ["graded_folders", "hidden", "expandable"] {
            if let names = values[key] as? [String] {
                updated[key] = renaming(oldName, to: newName, inList: names)
            }
        }

        // **Scoped, both of them.** A shared folder and a per-section folder may
        // legitimately share a name — they are different folders in different
        // places, found by different scans — so renaming the shared `Tasks`
        // must not rewrite a course whose CLASS folder is a per-section
        // `Tasks`. The curriculum folder is shared and the class folder is
        // per-section, so each is carried only by a rename in its own scope.
        // Found by the suite on 2026-09-04, next door to a test that was
        // failing for a different reason.
        if scope == .shared, let curriculum = values["curriculum_folder"] as? String {
            if curriculum.caseInsensitiveCompare(oldName) == .orderedSame {
                updated["curriculum_folder"] = newName
            }
        }

        if scope == .perSection, let classFolder = values["class_folder"] as? String {
            if classFolder.caseInsensitiveCompare(oldName) == .orderedSame {
                updated["class_folder"] = newName
            }
        }

        // A folder that is excluded is not in the list a teacher can rename
        // from, so this is defence rather than a path anybody walks today. It
        // is here because the alternative — an exclusion silently attaching
        // itself to whatever folder is next called by the old name — is the
        // failure `excluded_items` was written to prevent.
        if let excluded = values["excluded_items"] as? [String: Any] {
            var rewritten: [String: Any] = excluded
            // This scope's list only, for the same reason as the two keys
            // above: `excluded_items` is keyed by scope precisely BECAUSE the
            // same bare name can exist in both, and rewriting the other
            // scope's entry would silently re-include a folder the teacher
            // excluded.
            if let names = excluded[scope.exclusionKey] as? [String] {
                rewritten[scope.exclusionKey] = renaming(oldName, to: newName, inList: names)
            }
            updated["excluded_items"] = rewritten
        }

        return updated
    }

    // MARK: - Private helpers

    /// One list of names with the old one replaced, keeping its position.
    /// One list of names with the old one replaced, keeping its position — and
    /// never leaving the new name in twice.
    ///
    /// The duplicate is not hypothetical: finishing an interrupted rename
    /// starts from a list that already holds BOTH names, because a build
    /// discovered the moved folder and appended it. Renaming the old entry
    /// then produces the new name twice, which a `ForEach(items, id: \.self)`
    /// renders with duplicate identities and which no later rename can undo.
    nonisolated private static func renaming(_ oldName: String, to newName: String, inList names: [String]) -> [String] {
        var result: [String] = []
        for name in names {
            let renamed: String = name.caseInsensitiveCompare(oldName) == .orderedSame ? newName : name
            var alreadyThere: Bool = false
            for kept in result where kept.caseInsensitiveCompare(renamed) == .orderedSame {
                alreadyThere = true
            }
            if !alreadyThere {
                result.append(renamed)
            }
        }
        return result
    }
}

/// Who owns the interrupted-rename record during one rename (#899 U4b2-3).
///
/// **The record exists only while the rename that wrote it is unfinished,
/// and nothing clears a record another run wrote.** The record is one file
/// per course, so a run that writes its own has replaced whatever was there:
/// another folder's interrupted rename. This reads that earlier record before
/// anything is written and, on every exit, leaves the file as the rule says:
///
/// - refused with nothing changed (`nothingWasChanged`, which a changed-since
///   retry calls too before it plans again): the earlier record put back byte
///   for byte, or no record when there was none;
/// - stopped part way (`leftPartWay`) or killed (`stoppedByATest`, as a
///   process that died): this run's record kept, so the rename can be
///   recognised and finished (`interruptedRenameTarget`);
/// - whole (`renameIsWhole`): a record of THIS rename (same folder, same
///   target) is cleared, since this run finished it. A record of a rename of
///   this folder to ANOTHER name is cleared only when the old name is gone
///   for good: when this run moved the folders, or when the caller changes
///   the settings away from the old name (`changesTheSettings`, true from
///   `renameFolder`), so the sheet for that name never opens again (review
///   1, L3). A `rename` that moved nothing and changes no settings leaves
///   that record, because the settings still name the old folder and the
///   recorded rename can still be finished (review 2, L-A). Any other
///   earlier record is put back if this run replaced it, and left alone if
///   this run wrote nothing.
///
/// One window is accepted (review 1, L1): a kill between this run's write
/// and the put-back leaves only this run's record, so the earlier one is lost,
/// as it always was before U4b2-3. U7 drops the record altogether.
nonisolated struct RenameRecordClaim {

    // MARK: - Stored properties

    let oldName: String
    let newName: String
    let scope: FolderScope
    let courseDirectory: URL
    let marker: URL

    /// Whether the caller writes the settings away from the old name when
    /// the rename is whole (`renameFolder` does; `rename` does not).
    let changesTheSettings: Bool

    /// The record on disk before this run wrote anything, if any.
    let earlierRecord: Data?

    /// Whether the record on disk is this run's own.
    private(set) var thisRunWroteTheRecord: Bool = false

    // MARK: - Initializer

    /// Read once, before the record is written for the first time.
    init(
        from oldName: String, to newName: String, scope: FolderScope, courseDirectory: URL,
        changesTheSettings: Bool
    ) {
        self.oldName = oldName
        self.newName = newName
        self.scope = scope
        self.courseDirectory = courseDirectory
        self.changesTheSettings = changesTheSettings
        self.marker = SpecialFolderRenamer.renameMarkerURL(courseDirectory: courseDirectory)
        self.earlierRecord = try? Data(contentsOf: marker)
    }

    // MARK: - Functions

    /// Written BEFORE the rename's step is made, when folders will move.
    /// It names every place this rename has moved: this run's moves and,
    /// when the earlier record is of this same rename, the places it says
    /// an earlier run moved (U4b2-5), so a later ending still knows them.
    ///
    /// The places an earlier run may have moved without its record saying
    /// so are carried forward as `mayHaveMoved` (U4b2-6), so a later ending
    /// still says it cannot tell, rather than that nothing was renamed.
    mutating func renameIsStarting(moving moves: [FolderRenamePlan.Move], sectionNumbers: [Int]) {
        var moved: [String] = []
        if let recorded = SpecialFolderRenamer.placesMoved(
            byTheRecord: earlierRecord, renaming: oldName, to: newName, scope: scope
        ) {
            for place in recorded {
                moved.append(place)
            }
        }
        for move in moves {
            let place: String = SpecialFolderRenamer.placeInside(move.to, courseDirectory: courseDirectory)
            if !moved.contains(place) {
                moved.append(place)
            }
        }
        var mayHaveMoved: [String] = []
        for place in SpecialFolderRenamer.placesAnEarlierRunMayHaveMoved(
            byTheRecord: earlierRecord, renaming: oldName, to: newName, scope: scope,
            courseDirectory: courseDirectory, sectionNumbers: sectionNumbers
        ) {
            if !moved.contains(place) {
                mayHaveMoved.append(place)
            }
        }
        SpecialFolderRenamer.recordRenameStarting(
            from: oldName, to: newName, scope: scope, courseDirectory: courseDirectory,
            moved: moved, mayHaveMoved: mayHaveMoved
        )
        thisRunWroteTheRecord = true
    }

    /// The step was not made: kept when it stopped part way or was killed,
    /// otherwise nothing was changed.
    mutating func stepWasNotMade(_ stopped: JournaledStepError) {
        switch stopped {
        case .leftPartWay, .stoppedByATest:
            return
        default:
            nothingWasChanged()
        }
    }

    /// Refused with nothing changed: the record as it was before this run.
    mutating func nothingWasChanged() {
        if thisRunWroteTheRecord {
            putBackTheEarlierRecord(renameIsWhole: false)
            thisRunWroteTheRecord = false
        }
    }

    /// The step is made, so this rename is whole.
    mutating func renameIsWhole() {
        let finishesTheRecordedRename: Bool = SpecialFolderRenamer.recordNames(
            earlierRecord, from: oldName, to: newName, scope: scope
        )
        let recordsThisFolder: Bool = SpecialFolderRenamer.recordNamesTheFolder(
            earlierRecord, from: oldName, scope: scope
        )
        let oldNameIsGone: Bool = thisRunWroteTheRecord || changesTheSettings
        if finishesTheRecordedRename || (recordsThisFolder && oldNameIsGone) {
            removeTheRecord(renameIsWhole: true)
        } else if thisRunWroteTheRecord {
            putBackTheEarlierRecord(renameIsWhole: true)
        }
        thisRunWroteTheRecord = false
    }

    /// The earlier run's bytes written back, or no record when there was none.
    private func putBackTheEarlierRecord(renameIsWhole: Bool) {
        guard let earlierRecord else {
            removeTheRecord(renameIsWhole: renameIsWhole)
            return
        }
        do {
            try earlierRecord.write(to: marker, options: [.atomic])
        } catch {
            noteNotTidied(error, renameIsWhole: renameIsWhole)
        }
    }

    private func removeTheRecord(renameIsWhole: Bool) {
        if !FileManager.default.fileExists(atPath: marker.path) {
            return
        }
        do {
            try FileManager.default.removeItem(at: marker)
        } catch {
            noteNotTidied(error, renameIsWhole: renameIsWhole)
        }
    }

    private func noteNotTidied(_ error: Error, renameIsWhole: Bool) {
        ActivityTrail.note(.folderRenamed, SpecialFolderRenamer.renameNoteNotTidiedLine(
            renaming: oldName, to: newName, course: courseDirectory.lastPathComponent,
            wasRenamed: renameIsWhole, said: error.localizedDescription
        ))
    }
}
