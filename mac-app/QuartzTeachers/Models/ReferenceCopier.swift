import Foundation

/// "Keep a Copy for Reference…" — the whole act, without the sheet.
///
/// The teacher's own course is left exactly as it is and keeps being taught.
/// What is made is a SNAPSHOT beside it: a new folder, carrying the pages and
/// the settings as they are today, marked as kept for reference, left with
/// nowhere to deploy to, and locked.
///
/// *Rejected: converting the course in place.* One config write and no
/// copying, and it is what a teacher means when they say "this one's just for
/// reference now" — but it has to answer a live site already on the web, a
/// scheduled deploy already on disk, a preview running right now and an open
/// section window whose Deploy button vanishes under their hand. And it is
/// permanent: frozen, never deployed, no way back. **A wrong copy is deleted;
/// a wrong conversion is restored from a zip if one exists.** That asymmetry
/// is the whole argument.
@MainActor
enum ReferenceCopier {

    // MARK: - Types

    /// What was made, for the trail line and for the sidebar to select.
    struct Made: Equatable {

        // MARK: - Stored properties

        /// The folder it was given — `ICS3U-2025`.
        let folderName: String

        /// The code a teacher reads — `ICS3U`.
        let displayCode: String

        /// The school year it was filed under, or nil for "Other".
        let schoolYear: Int?

        /// How many sections came across.
        let sectionCount: Int
    }

    /// Why a copy could not be made.
    enum Problem: LocalizedError, Equatable {
        case folderAlreadyExists(String)
        case couldNotCopy(String)

        // MARK: - Computed properties

        var errorDescription: String? {
            switch self {
            case .folderAlreadyExists(let folderName):
                return "There is already a course folder called \(folderName). Choose a different name."
            case .couldNotCopy(let reason):
                return "The copy could not be made: \(reason)"
            }
        }
    }

    // MARK: - Stored properties

    /// Things this copy deliberately leaves behind, beyond what an archive
    /// already leaves behind (`CourseArchiver.excludedFromArchives`, which
    /// carries `.merged_output`, `node_modules`, `.git`, the caches and
    /// `.DS_Store`).
    ///
    /// `.merged_output` earns its own sentence: it is a SYMLINK out to the
    /// builds folder, and following it would copy last year's whole built
    /// website — measured at 1.9 GB on one real course — into a folder that
    /// rebuilds it on demand anyway.
    static let alsoLeftBehind: [String] = [
        // Yesterday's config. The live folder can also hold a Finder
        // duplicate ("course_config copy.json"); the config is read by exact
        // name, never by glob, so a duplicate is carried across as an
        // ordinary file and mistaken for nothing.
        "course_config.backup.json",
    ]

    // MARK: - Functions

    /// Makes the copy. The original is not touched.
    ///
    /// The order is deliberate and the LOCK IS LAST. Measured: `rm -rf` and
    /// `FileManager.removeItem` both refuse a locked tree — so a failure
    /// part-way through a locked copy would leave a folder the teacher cannot
    /// delete. Everything that can fail happens while the folder is still
    /// ordinary.
    static func keepACopy(
        of course: Course,
        named folderName: String,
        schoolYear: Int?,
        coursesDirectoryURL: URL,
        at moment: Date = Date()
    ) throws -> Made {
        let fileManager: FileManager = FileManager.default
        let destinationURL: URL = coursesDirectoryURL.appendingPathComponent(folderName)
        if fileManager.fileExists(atPath: destinationURL.path) {
            throw Problem.folderAlreadyExists(folderName)
        }

        // Built under a HIDDEN name and renamed into place as the last act.
        // The course being copied is a LIVE one, so until the marker is
        // written and the site markers are renamed aside the copy is an
        // ordinary course pointing at the ORIGINAL's class website — and a
        // crash in that window would leave one in the sidebar. The window is
        // small here (a local clone) and it is the same window the importer
        // had; one answer for both. `ReferenceStaging` says why a dot-folder
        // closes it.
        let stagingURL: URL = coursesDirectoryURL.appendingPathComponent(
            ReferenceStaging.stagingName(for: folderName)
        )
        if !ReferenceStaging.someoneIsWorkingOn(
            stagingURL.lastPathComponent, inCoursesDirectory: coursesDirectoryURL
        ) {
            ReferenceStaging.remove(at: stagingURL)
        }
        // A second window reading this working folder sweeps leftover staging
        // folders; this says the folder is in use so that the sweep leaves it
        // alone. Quick here — a local clone — but "quick" is not a guarantee.
        ReferenceStaging.takeLease(for: folderName, inCoursesDirectory: coursesDirectoryURL)
        defer {
            ReferenceStaging.releaseLease(for: folderName, inCoursesDirectory: coursesDirectoryURL)
        }

        do {
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
            try ReferenceCopier.copyContents(of: course.directoryURL, into: stagingURL)
            // The lock TRAVELS through `FileManager.copyItem`, so a copy taken
            // from a course that is already frozen arrives frozen — and then
            // the two steps below cannot happen: the site markers cannot be
            // renamed aside, and the half-written folder cannot be removed.
            // Measured: `moveItem` and `removeItem` both refuse a locked tree
            // outright, so the failure path left a folder the teacher could
            // delete from neither the app nor Finder.
            //
            // Cleared HERE, immediately, so the copy is an ordinary folder for
            // the whole of the risky stretch and the "lock LAST" order below
            // still holds. Nothing today copies from a frozen course — "Keep a
            // Copy for Reference…" is withheld on one — but a guard that
            // depends on a menu item being withheld somewhere else is a guard
            // one edit from being gone.
            ReferenceLock.clearLock(at: stagingURL)
        } catch {
            // Nothing is locked yet, so the half-written folder is an
            // ordinary one and goes away cleanly.
            ReferenceStaging.remove(at: stagingURL)
            if let problem = error as? Problem {
                throw problem
            }
            throw Problem.couldNotCopy(error.localizedDescription)
        }

        let staged: Made
        do {
            staged = try ReferenceCopier.makeIntoAReferenceCourse(
                at: stagingURL, schoolYear: schoolYear, at: moment
            )
            // The one step that makes it visible, and the only one that has
            // to be atomic: a rename within `courses/`. Measured: a folder
            // whose contents carry the lock renames cleanly, and the lock
            // survives.
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        } catch {
            // The lock may be ON by now — it is applied inside the call
            // above — so the clear comes first, and both are `ReferenceStaging`'s
            // job rather than two more lines here.
            ReferenceStaging.remove(at: stagingURL)
            throw Problem.couldNotCopy(error.localizedDescription)
        }

        // `staged` was made under the hidden name; everything else in it was
        // read from the settings and is right.
        let made: Made = Made(
            folderName: folderName,
            displayCode: staged.displayCode,
            schoolYear: staged.schoolYear,
            sectionCount: staged.sectionCount
        )
        ActivityTrail.note(
            .courseKeptForReference,
            ReferenceCopier.trailLine(for: made, copiedFrom: course.displayCode)
        )
        return made
    }

    /// Turns a folder that has just been COPIED into a reference course: cut
    /// loose from last year's websites, marked, filed under its year, left
    /// with nowhere to deploy to, and locked — in that order.
    ///
    /// **The one implementation of the dangerous sequence**, called by both
    /// ways a reference course is made: "Keep a Copy for Reference…" above,
    /// and "Import Courses for Reference…" (`ReferenceImporter`), which is
    /// the same act with a different source. A second copy of this order is a
    /// second thing to keep in step, and the thing it would be out of step
    /// about is whether a course can reach last year's live website.
    ///
    /// Two things the caller owes, because only the caller knows them:
    ///
    /// * the folder is an ORDINARY, unlocked copy when this is called. The
    ///   lock travels through `FileManager.copyItem`, so a copy taken from a
    ///   course that is already frozen arrives frozen — and then the site
    ///   markers cannot be renamed aside and the folder cannot be removed
    ///   either. Both callers clear it the moment their copy finishes,
    ///   because both need an ordinary folder for their own failure path.
    /// * removing the folder if this throws. What was half-made is the
    ///   caller's to clean up, and only it knows whether the folder was there
    ///   before.
    static func makeIntoAReferenceCourse(
        at destinationURL: URL,
        schoolYear: Int?,
        at moment: Date = Date()
    ) throws -> Made {
        let folderName: String = destinationURL.lastPathComponent
        let configuration: CourseConfiguration = try CourseConfiguration(
            contentsOf: destinationURL.appendingPathComponent("course_config.json")
        )
        let copy: Course = Course(
            code: folderName, directoryURL: destinationURL, configuration: configuration
        )

        // Cut every section loose from the website it was publishing to,
        // BEFORE the marker is written — so a failure here leaves a folder
        // that is not yet a reference course rather than one that is and is
        // still pinned to last year's live site.
        //
        // Renamed aside rather than deleted, by the same function the
        // rollover uses: the file holds the site id and the admin address,
        // which a teacher may still want. Two fail-safes fall out of it — a
        // deploy that somehow ran would make a NEW site rather than overwrite
        // last year's, and a section that has never deployed cannot be
        // scheduled at all.
        for sectionNumber in copy.sectionNumbers {
            _ = DeployCommand.releaseSite(forSection: sectionNumber, in: copy, at: moment)
        }

        // `course_code` is deliberately NOT touched: it stays the real code,
        // which is what the teacher reads and what keeps this copy's preview
        // titles right. Only the FOLDER carries the year.
        copy.configuration.keptForReference = true
        copy.configuration.referenceSchoolYear = schoolYear
        copy.configuration.neutraliseForReference()
        try copy.configuration.write(to: copy.configFileURL)

        // Through the same re-assertion everything else uses, rather than a
        // lock of its own: "right after a reference course is made" is one of
        // the points the rule names, and a second way of doing it is a second
        // thing to keep in step. It also VERIFIES — in a cloud-synced folder
        // the file provider clears the flag again while the copy uploads, and
        // this is where that shows up as a count on the trail rather than as
        // a course that quietly is not frozen.
        let locked: ReferenceLock.Outcome = ReferenceLock.ensureLocked(copy)
        if locked.didNotTake > 0 {
            ActivityTrail.note(
                .referenceCoursePagesLockedAgain,
                ReferenceCourseUpkeep.trailLine(for: locked, course: copy.displayCode)
            )
        }

        // Asked of the INDEPENDENT census rather than of the walk that just
        // ran: a walk that stopped early reports success about the files it
        // reached, which is exactly how nine editable pages once sat inside
        // a course the app called frozen. A course made here and not
        // completely locked is worth a line whichever way it happened —
        // nothing is put in front of the teacher, because the course is real
        // and the next re-assertion takes another pass at it.
        if !locked.everythingThatShouldBeLockedIs {
            ActivityTrail.note(
                .referenceCoursePagesLockedAgain,
                "made \(copy.displayCode) for reference and \(locked.lockedOnDisk) of "
                + "\(locked.shouldBeLocked) of its files are locked"
            )
        }

        return Made(
            folderName: folderName,
            displayCode: copy.displayCode,
            schoolYear: schoolYear,
            sectionCount: copy.sectionNumbers.count
        )
    }

    /// The trail line — what a teacher would recognise, and enough to explain
    /// a report months later.
    static func trailLine(for made: Made, copiedFrom source: String) -> String {
        var year: String = "no school year"
        if let startingYear = made.schoolYear {
            year = SchoolYear.label(forStartingYear: startingYear)
        }
        let sections: String = made.sectionCount == 1 ? "1 section" : "\(made.sectionCount) sections"
        return "kept a copy of \(source) for reference as \(made.folderName) — "
             + "shown as \(made.displayCode), \(year), \(sections)"
    }

    // MARK: - Private helpers

    /// Copies everything the teacher wrote, and nothing that is rebuilt.
    /// Copies everything the teacher wrote, and nothing that is rebuilt —
    /// through the SAME copier the import uses.
    ///
    /// It used to have a loop of its own: `contentsOfDirectory`, then
    /// `copyItem` to `destination.appendingPathComponent(child.lastPathComponent)`.
    /// That preserved the names INSIDE each folder and decomposed the
    /// top-level ones, because the rebuilt component goes through `URL`'s
    /// file-system representation — measured, a folder called `Thème` arrived
    /// spelled the other way, and a page that links to something inside it by
    /// the old spelling no longer resolves in the built site. Nothing in the
    /// four real courses measured has a non-ASCII top-level name, so nobody
    /// had met it; that is luck, not a design.
    private static func copyContents(of sourceURL: URL, into destinationURL: URL) throws {
        var leftBehind: Set<String> = []
        for name in CourseArchiver.excludedFromArchives {
            leftBehind.insert(name)
        }
        for name in ReferenceCopier.alsoLeftBehind {
            leftBehind.insert(name)
        }
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.survey(
            courseAt: sourceURL, leavingBehind: leftBehind
        )
        if let unreadable = survey.unreadableFolders.first {
            throw ReferenceTreeCopier.Trouble.couldNotRead(name: unreadable)
        }
        try ReferenceTreeCopier.copySynchronously(
            survey, from: sourceURL, into: destinationURL
        )

        // Leases belong to processes on whichever machine wrote them, so a
        // copied one names a process that was never doing anything here.
        let leases: URL = destinationURL
            .appendingPathComponent(".internal").appendingPathComponent("activity")
        try? FileManager.default.removeItem(at: leases)
    }

}
