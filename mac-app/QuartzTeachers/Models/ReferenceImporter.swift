import Foundation

/// "Import Courses for Reference…" — the whole act, without the sheet.
///
/// **This is `ReferenceCopier` with a different source.** Keeping a copy of a
/// course already in this folder and bringing one in from last year's folder
/// end the same way, and they end in the same function
/// (`ReferenceCopier.makeIntoAReferenceCourse`): cut loose from last year's
/// websites, marked, filed under its school year, left with nowhere to deploy
/// to, and locked. What is different is only the reading: somebody else's
/// folder, possibly on a disk that has to spin up, holding a built website
/// four times the size of the course itself.
///
/// Three rules this file exists to keep:
///
/// 1. **The source is never written to.** It may be the teacher's only copy
///    of last year. Everything here opens it for reading and writes only
///    inside the new folder.
/// 2. **A course that fails does not take the others with it.** A folder of
///    four courses where one has a problem imports three and says what
///    happened to the fourth.
/// 3. **Nothing half-made is left behind.** The lock is the last step, so
///    whatever is cleaned up on the way out is an ordinary folder — measured:
///    `removeItem` and `rm -rf` both refuse a locked tree.
@MainActor
enum ReferenceImporter {

    // MARK: - Types

    /// One course the teacher ticked, with the year they chose for it.
    struct Request: Identifiable, Equatable {

        // MARK: - Stored properties

        let course: ReferenceImportSource.FoundCourse

        /// The school year it is filed under, or nil for "Other".
        let schoolYear: Int?

        // MARK: - Computed properties

        var id: String {
            return course.id
        }
    }

    /// What happened to one course.
    enum Outcome: Equatable {
        case imported(ReferenceCopier.Made)
        case notImported(course: String, reason: String)

        /// The teacher stopped it. Always last, and everything before it in
        /// the list really is on the shelf.
        case stopped
    }

    /// Where a run has got to, for the sheet to draw.
    struct Progress: Sendable, Equatable {

        // MARK: - Stored properties

        /// The code a teacher reads.
        let courseCode: String

        /// Which of how many — "2 of 4" — counting from one.
        let courseNumber: Int
        let courseCount: Int

        let copiedBytes: Int64
        let totalBytes: Int64
    }

    // MARK: - Stored properties

    /// Everything an import leaves behind, in one set.
    ///
    /// Composed from the two lists that already exist rather than written out
    /// again: `CourseArchiver.excludedFromArchives` (last year's built
    /// website, `node_modules`, `.git`, the caches, `.DS_Store`),
    /// `ReferenceCopier.alsoLeftBehind` (yesterday's config) and
    /// `ReferenceImportSource.alsoLeftBehindOnImport` (a Finder duplicate of
    /// a config, and what an external disk leaves in a folder). A fourth list
    /// would be a fourth thing to keep in step.
    static var leftBehindNames: Set<String> {
        var names: Set<String> = []
        for name in CourseArchiver.excludedFromArchives {
            names.insert(name)
        }
        for name in ReferenceCopier.alsoLeftBehind {
            names.insert(name)
        }
        for name in ReferenceImportSource.alsoLeftBehindOnImport {
            names.insert(name)
        }
        return names
    }

    // MARK: - Functions

    /// Imports each ticked course, in order, and says what happened to every
    /// one of them.
    ///
    /// `existingFolderNames` and `alreadyShelved` are the state of this
    /// working folder as the run starts; both GROW as courses land, so the
    /// second course of a run is checked against the first. Without that, two
    /// courses with the same code — which one folder cannot hold, but two
    /// chosen folders can over two runs — would collide only on disk.
    static func importCourses(
        _ requests: [Request],
        into coursesDirectoryURL: URL,
        existingFolderNames: [String],
        alreadyShelved: [ReferenceCourseRule.Shelved],
        from sourceFolderURL: URL,
        leavingBehind leftBehindNames: Set<String>? = nil,
        progress: @escaping @Sendable @MainActor (Progress) -> Void
    ) async -> [Outcome] {
        let fileManager: FileManager = FileManager.default
        let namesToLeaveBehind: Set<String> = leftBehindNames ?? ReferenceImporter.leftBehindNames
        var folderNames: [String] = existingFolderNames
        var shelved: [ReferenceCourseRule.Shelved] = alreadyShelved
        var outcomes: [Outcome] = []
        var courseNumber: Int = 0

        for request in requests {
            courseNumber += 1
            let displayCode: String = request.course.courseCode

            // The shelf rule first, before anything is read or written: a
            // course that cannot be filed is refused with a sentence, and the
            // rest of the run carries on.
            if let trouble = ReferenceCourseRule.trouble(
                placing: displayCode, inYear: request.schoolYear, among: shelved
            ) {
                outcomes.append(.notImported(course: displayCode, reason: trouble.sentence))
                continue
            }

            let folderName: String = ReferenceCourseRule.proposedFolderName(
                forCode: displayCode,
                schoolYear: request.schoolYear,
                existingFolderNames: folderNames
            )
            let destinationURL: URL = coursesDirectoryURL.appendingPathComponent(folderName)
            if fileManager.fileExists(atPath: destinationURL.path) {
                let problem: ReferenceCopier.Problem = .folderAlreadyExists(folderName)
                outcomes.append(.notImported(
                    course: displayCode, reason: problem.errorDescription ?? folderName
                ))
                continue
            }

            // Built under a HIDDEN name and renamed into place as the last
            // act, so nothing under `courses/` is ever a course that is not
            // already a reference course. `ReferenceStaging` says why.
            let stagingURL: URL = coursesDirectoryURL.appendingPathComponent(
                ReferenceStaging.stagingName(for: folderName)
            )
            ReferenceStaging.remove(at: stagingURL)

            do {
                let made: ReferenceCopier.Made = try await ReferenceImporter.importOneCourse(
                    request,
                    named: folderName,
                    stagedAt: stagingURL,
                    into: destinationURL,
                    leavingBehind: namesToLeaveBehind,
                    courseNumber: courseNumber,
                    courseCount: requests.count,
                    progress: progress
                )
                ActivityTrail.note(
                    .courseImportedForReference,
                    ReferenceImporter.trailLine(for: made, broughtInFrom: sourceFolderURL)
                )
                outcomes.append(.imported(made))
                folderNames.append(folderName)
                shelved.append(ReferenceCourseRule.Shelved(
                    displayCode: made.displayCode,
                    schoolYear: made.schoolYear,
                    folderName: made.folderName
                ))
            } catch is CancellationError {
                // Stopped by the teacher. What was in hand is removed —
                // unlocked first, because a source that was itself frozen
                // hands its locks to the copy — and the run ends here.
                ReferenceImporter.tidyAway(
                    stagingURL, course: displayCode, broughtInFrom: sourceFolderURL
                )
                ActivityTrail.note(
                    .courseImportForReferenceStopped,
                    ReferenceImporter.stoppedTrailLine(
                        course: displayCode, broughtInFrom: sourceFolderURL
                    )
                )
                outcomes.append(.stopped)
                return outcomes
            } catch {
                ReferenceImporter.tidyAway(
                    stagingURL, course: displayCode, broughtInFrom: sourceFolderURL
                )
                let reason: String = error.localizedDescription
                ActivityTrail.note(
                    .courseCouldNotBeImportedForReference,
                    "could not import \(displayCode) for reference "
                    + "from \(sourceFolderURL.lastPathComponent) — \(reason)"
                )
                outcomes.append(.notImported(course: displayCode, reason: reason))
            }
        }

        return outcomes
    }

    /// The trail line for a course that came across — what a teacher would
    /// recognise, and enough to explain a report months later.
    ///
    /// Names the folder it was read FROM, which is the one thing an import
    /// records that a copy does not: the answer to "where did this ICS4U come
    /// from" is a folder somewhere else on this Mac.
    static func trailLine(for made: ReferenceCopier.Made, broughtInFrom sourceFolderURL: URL) -> String {
        var year: String = ReferenceImportWording.noSchoolYear
        if let startingYear = made.schoolYear {
            year = SchoolYear.label(forStartingYear: startingYear)
        }
        let sections: String = made.sectionCount == 1 ? "1 section" : "\(made.sectionCount) sections"
        return "imported \(made.displayCode) for reference from \(sourceFolderURL.lastPathComponent) "
             + "as \(made.folderName) — \(year), \(sections)"
    }

    /// The trail line for a run the teacher stopped.
    static func stoppedTrailLine(course: String, broughtInFrom sourceFolderURL: URL) -> String {
        return "stopped importing \(course) for reference "
             + "from \(sourceFolderURL.lastPathComponent) — nothing was kept for that course"
    }

    // MARK: - Private helpers

    /// One course: read it, copy it under a hidden name, make it into a
    /// reference course THERE, and rename it into place as the last act.
    private static func importOneCourse(
        _ request: Request,
        named folderName: String,
        stagedAt stagingURL: URL,
        into destinationURL: URL,
        leavingBehind leftBehindNames: Set<String>,
        courseNumber: Int,
        courseCount: Int,
        progress: @escaping @Sendable @MainActor (Progress) -> Void
    ) async throws -> ReferenceCopier.Made {
        let fileManager: FileManager = FileManager.default
        let sourceURL: URL = request.course.directoryURL
        let displayCode: String = request.course.courseCode

        // Walked again rather than trusted from the sheet: the sheet's
        // numbers were read when it opened, and the copy has to be of what is
        // there now.
        let survey: ReferenceTreeCopier.Survey = await ReferenceImporter.surveyOffTheMainActor(
            courseAt: sourceURL, leavingBehind: leftBehindNames
        )

        // A folder the old disk will not hand over is never skipped in
        // silence: the course is refused, naming the folder. An import that
        // copied none of it and reported success is the quiet kind of loss.
        if let unreadable = survey.unreadableFolders.first {
            throw ReferenceTreeCopier.Trouble.couldNotRead(name: unreadable)
        }

        progress(Progress(
            courseCode: displayCode,
            courseNumber: courseNumber,
            courseCount: courseCount,
            copiedBytes: 0,
            totalBytes: survey.byteCount
        ))

        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)

        let totalBytes: Int64 = survey.byteCount
        try await ReferenceTreeCopier.copy(
            survey, from: sourceURL, into: stagingURL
        ) { copiedBytes in
            Task { @MainActor in
                progress(Progress(
                    courseCode: displayCode,
                    courseNumber: courseNumber,
                    courseCount: courseCount,
                    copiedBytes: copiedBytes,
                    totalBytes: totalBytes
                ))
            }
        }

        // The lock TRAVELS through a copy, so a course that was itself frozen
        // — an old folder holding a reference course — arrives frozen, and
        // then its site markers cannot be renamed aside and the folder cannot
        // be removed either. Cleared HERE, immediately, so what follows works
        // on an ordinary folder and the "lock LAST" order still holds.
        ReferenceLock.clearLock(at: stagingURL)

        // Leases name processes on whichever machine wrote them, so a copied
        // one names a process that was never doing anything here.
        try? fileManager.removeItem(
            at: stagingURL.appendingPathComponent(".internal").appendingPathComponent("activity")
        )

        // Marked, filed, neutralised and LOCKED while still hidden.
        let staged: ReferenceCopier.Made = try ReferenceCopier.makeIntoAReferenceCourse(
            at: stagingURL, schoolYear: request.schoolYear
        )

        // The one step that makes it visible, and the only one that has to be
        // atomic: a rename within `courses/`. Measured: a folder whose
        // contents carry the lock renames cleanly, and the lock survives.
        try fileManager.moveItem(at: stagingURL, to: destinationURL)

        // `staged` was made under the hidden name, so the folder it reports
        // is that one; everything else in it — the code a teacher reads, the
        // year, the section count — was read from the settings and is right.
        return ReferenceCopier.Made(
            folderName: folderName,
            displayCode: staged.displayCode,
            schoolYear: staged.schoolYear,
            sectionCount: staged.sectionCount
        )
    }

    /// The walk, off the main actor.
    ///
    /// `@concurrent` is what moves it there — a plain `nonisolated async`
    /// function runs on its CALLER's actor in this project, which is the main
    /// one here. See `ReferenceTreeCopier.copy` for the measurement.
    @concurrent
    private nonisolated static func surveyOffTheMainActor(
        courseAt courseURL: URL,
        leavingBehind leftBehindNames: Set<String>
    ) async -> ReferenceTreeCopier.Survey {
        return ReferenceTreeCopier.survey(courseAt: courseURL, leavingBehind: leftBehindNames)
    }

    /// Takes away the hidden folder this run made and did not finish.
    ///
    /// **Unlock, then remove, and in that order** — `removeItem` refuses a
    /// locked tree outright, and a half-made folder the teacher can delete
    /// from neither the app nor Finder is a worse outcome than the failure
    /// that produced it.
    ///
    /// **A removal that FAILS says so on the trail**, rather than leaving the
    /// run to look tidy while a folder full of last year's material sits
    /// there. Nothing is put in front of the teacher: the folder is hidden,
    /// the next time this working folder is read it is swept
    /// (`ReferenceStaging.sweepLeftovers`), and the one thing they asked
    /// about — the course — is already reported as not imported.
    private static func tidyAway(_ stagingURL: URL, course: String, broughtInFrom sourceFolderURL: URL) {
        if ReferenceStaging.remove(at: stagingURL) {
            return
        }
        ActivityTrail.note(
            .courseCouldNotBeImportedForReference,
            "could not tidy away the unfinished import of \(course) "
            + "from \(sourceFolderURL.lastPathComponent) — it is tidied away "
            + "the next time this working folder is opened"
        )
    }
}
