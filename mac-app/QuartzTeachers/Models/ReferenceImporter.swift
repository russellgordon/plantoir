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

        /// An older-layout class that came across with something MISSING:
        /// some or all of its shared pages and pictures (none were found
        /// beside it and none were chosen, or the folder held only some),
        /// and/or files that were left out because they only pointed
        /// somewhere else or would have taken a name the course uses — each
        /// NAMED. Its own case so the summary says so; never a refusal
        /// (Russell, decision 2).
        case importedWithSomethingMissing(ReferenceCopier.Made, sharedPagesMissing: Bool, leftOut: [String])
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
            // CLAIMED as one act: the folder is made, empty, before the first
            // `await`, and only a claimer ever removes a staging folder. Two
            // windows are one process with one process id, and until #245 the
            // second of them read the first one's lease as a live owner, went
            // on, failed to make the folder that was already there — and its
            // own tidy-up removed the FIRST window's half-made copy.
            // `ReferenceStaging.claim` says the order and why.
            let claim: ReferenceStaging.Claim = ReferenceStaging.claim(
                folderName, inCoursesDirectory: coursesDirectoryURL
            )
            switch claim {
            case .claimed:
                break
            case .someoneElseIsMakingIt:
                ReferenceImporter.noteNotImported(
                    displayCode,
                    from: sourceFolderURL,
                    because: ReferenceImportWording.alreadyBeingImported
                )
                outcomes.append(.notImported(
                    course: displayCode, reason: ReferenceImportWording.alreadyBeingImported
                ))
                continue
            case .couldNotStart(let reason):
                ReferenceImporter.noteNotImported(displayCode, from: sourceFolderURL, because: reason)
                outcomes.append(.notImported(course: displayCode, reason: reason))
                continue
            }
            // Given back however this course ends — imported, failed or
            // stopped — and only AFTER the catch blocks below have tidied
            // away what was ours, so a sweep can never land in between.
            defer {
                ReferenceStaging.giveBack(folderName, inCoursesDirectory: coursesDirectoryURL)
            }

            do {
                let made: ReferenceCopier.Made
                if let facts = request.course.checkoutLayout {
                    let result: (made: ReferenceCopier.Made, plan: QuartzCheckoutLayout.Plan) =
                        try await ReferenceImporter.importOneWebsite(
                            request,
                            facts: facts,
                            named: folderName,
                            stagedAt: stagingURL,
                            into: destinationURL,
                            leavingBehind: namesToLeaveBehind,
                            courseNumber: courseNumber,
                            courseCount: requests.count,
                            progress: progress
                        )
                    made = result.made
                    // Named after the WEBSITE folder the pages were read
                    // from, not the folder of shortcuts it was reached from.
                    ActivityTrail.note(
                        .courseImportedForReference,
                        ReferenceImporter.trailLine(for: made, broughtInFrom: request.course.directoryURL)
                    )
                    ActivityTrail.note(
                        .courseImportedFromAClassWebsiteFolder,
                        ReferenceImporter.checkoutLayoutTrailLine(facts: facts, made: made, plan: result.plan)
                    )
                    if result.plan.lost.isEmpty {
                        outcomes.append(.imported(made))
                    } else {
                        outcomes.append(.importedWithSomethingMissing(
                            made, sharedPagesMissing: false, leftOut: result.plan.lostPaths
                        ))
                    }
                } else if request.course.olderLayout != nil {
                    let result: (made: ReferenceCopier.Made, plan: OlderCourseLayout.Plan) =
                        try await ReferenceImporter.importOneOlderClass(
                            request,
                            named: folderName,
                            stagedAt: stagingURL,
                            into: destinationURL,
                            leavingBehind: namesToLeaveBehind,
                            courseNumber: courseNumber,
                            courseCount: requests.count,
                            progress: progress
                        )
                    made = result.made
                    // Named after the CLASS folder, not the folder of classes
                    // it sat in: "where did this ICS3U come from" is answered
                    // by ICS3U-S1-2023-24.
                    ActivityTrail.note(
                        .courseImportedForReference,
                        ReferenceImporter.trailLine(for: made, broughtInFrom: request.course.directoryURL)
                    )
                    ActivityTrail.note(
                        .courseImportedFromTheOlderLayout,
                        ReferenceImporter.olderLayoutTrailLine(
                            classFolderName: request.course.folderName, made: made, plan: result.plan
                        )
                    )
                    let sharedPagesMissing: Bool = !result.plan.shared.missingNames.isEmpty
                    let leftOut: [String] = result.plan.leftOutAndLost
                    if !sharedPagesMissing && leftOut.isEmpty {
                        outcomes.append(.imported(made))
                    } else {
                        outcomes.append(.importedWithSomethingMissing(
                            made, sharedPagesMissing: sharedPagesMissing, leftOut: leftOut
                        ))
                    }
                } else {
                    let result: (made: ReferenceCopier.Made, addOnsLeftBehind: ObsidianAddOns.Found) =
                        try await ReferenceImporter.importOneCourse(
                        request,
                        named: folderName,
                        stagedAt: stagingURL,
                        into: destinationURL,
                        leavingBehind: namesToLeaveBehind,
                        courseNumber: courseNumber,
                        courseCount: requests.count,
                        progress: progress
                    )
                    made = result.made
                    // The one route whose line names the add-ons left behind:
                    // the two older layouts count theirs on their own second
                    // line, and saying it twice would be two answers (#255).
                    ActivityTrail.note(
                        .courseImportedForReference,
                        ReferenceImporter.trailLine(
                            for: made, broughtInFrom: sourceFolderURL,
                            addOnsLeftBehind: result.addOnsLeftBehind
                        )
                    )
                    outcomes.append(.imported(made))
                }
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
                ReferenceImporter.noteNotImported(displayCode, from: sourceFolderURL, because: reason)
                outcomes.append(.notImported(course: displayCode, reason: reason))
            }
        }

        return outcomes
    }

    /// The trail line for a course that did not come across, and why — the
    /// same line whether the copy failed part way or never started because
    /// the course is being imported somewhere else right now.
    private static func noteNotImported(_ course: String, from sourceFolderURL: URL, because reason: String) {
        ActivityTrail.note(
            .courseCouldNotBeImportedForReference,
            "could not import \(course) for reference "
            + "from \(sourceFolderURL.lastPathComponent) — \(reason)"
        )
    }

    /// The trail line for a course that came across — what a teacher would
    /// recognise, and enough to explain a report months later.
    ///
    /// Names the folder it was read FROM, which is the one thing an import
    /// records that a copy does not: the answer to "where did this ICS4U come
    /// from" is a folder somewhere else on this Mac.
    ///
    /// Shared by all three import routes. `addOnsLeftBehind` is passed by the
    /// MODERN route only (#255) — read by `ObsidianAddOns.found` from the
    /// course being imported, folder names only — and adds nothing when
    /// there were none, so every other line is exactly what it was.
    static func trailLine(
        for made: ReferenceCopier.Made,
        broughtInFrom sourceFolderURL: URL,
        addOnsLeftBehind: ObsidianAddOns.Found = ObsidianAddOns.Found()
    ) -> String {
        var year: String = ReferenceImportWording.noSchoolYear
        if let startingYear = made.schoolYear {
            year = SchoolYear.label(forStartingYear: startingYear)
        }
        let sections: String = made.sectionCount == 1 ? "1 section" : "\(made.sectionCount) sections"
        return "imported \(made.displayCode) for reference from \(sourceFolderURL.lastPathComponent) "
             + "as \(made.folderName) — \(year), \(sections)"
             + ObsidianAddOns.trailClause(for: addOnsLeftBehind)
    }

    /// The second trail line for an older-layout class: where its shared
    /// pages came from and HOW that folder was found, how much of what the
    /// class used was there, what is missing, and what was left out. "Where
    /// are this course's pictures" is the question a report about one of
    /// these will ask, and only this line answers it. Folder and file NAMES
    /// only; never what is written on a page.
    static func olderLayoutTrailLine(
        classFolderName: String,
        made: ReferenceCopier.Made,
        plan: OlderCourseLayout.Plan
    ) -> String {
        let shared: OlderCourseLayout.SharedContent = plan.shared
        var from: String
        switch shared.howFound {
        case .notNeeded:
            from = "no shared pages needed"
        case .byItsName:
            from = "shared pages from \(shared.folderName ?? "?") (found by its name)"
        case .chosen:
            from = "shared pages from \(shared.folderName ?? "?") (chosen by hand)"
        case .none:
            from = "no shared folder found or chosen"
        }
        var line: String = "imported \(classFolderName) from the older layout as \(made.folderName) — \(from)"
        if shared.linkCount > 0 {
            line += ", \(shared.foundNames.count) of \(shared.linkCount) brought across"
            if shared.missingNames.isEmpty {
                line += "; nothing missing"
            } else {
                line += "; missing: " + shared.missingNames.joined(separator: ", ")
            }
        }
        var addOns: Int = 0
        for entry in plan.leftOut where entry.reason == .addOns {
            addOns += 1
        }
        line += "; \(plan.linksReplaced) links replaced by the shared folder's own"
        let lost: [String] = plan.leftOutAndLost
        if lost.isEmpty {
            line += "; nothing else left out"
        } else {
            line += "; left out \(lost.count): " + lost.joined(separator: ", ")
        }
        line += "; \(addOns) Obsidian add-on entries left behind"
        if plan.createsEmptyMedia {
            line += "; an empty Media folder was made"
        }
        return line
    }

    /// The second trail line for a class kept in the 2024–25 layout: where
    /// its pages were read from (and through which shortcut), which section
    /// and HOW that was told, which course pages folder, and then — as two
    /// separate clauses — what was LEFT BEHIND, by kind with counts, and what
    /// was LOST, by name. "Which copy, and what did not come" is the question
    /// a report about one of these asks, and only this line answers it.
    /// Folder and file NAMES only, never what is written on a page; the
    /// trail redacts on the way in.
    static func checkoutLayoutTrailLine(
        facts: QuartzCheckoutLayout.Facts,
        made: ReferenceCopier.Made,
        plan: QuartzCheckoutLayout.Plan
    ) -> String {
        var line: String = "imported \(plan.courseCode) section \(facts.section ?? 0) from \(facts.place)"
        if let shortcut = facts.shortcutName {
            line += " (through the shortcut \(shortcut))"
        }
        line += " as \(made.folderName) — section told by "
        switch facts.sectionFrom {
        case .frontPage:
            line += "its front page"
        case .folderName:
            line += "its folder's name"
        case .onlyOne:
            line += "being the only one"
        case .none:
            line += "nothing"
        }
        if let named = facts.sectionTheNameSays, named != facts.section {
            line += " (its folder's name says section \(named))"
        }
        line += "; \(plan.fileCount) files from \(facts.coursePagesFolderName ?? "?")"
        if let word = plan.unitWord {
            line += "; class pages called \(word)"
            if plan.placeholderPages > 0 {
                let noun: String = plan.placeholderPages == 1 ? "page" : "pages"
                line += " (\(plan.placeholderPages) placeholder \(noun) set aside)"
            }
        } else {
            line += "; no single word for its class pages"
        }
        var behind: [String] = []
        behind.append("the website's own program files (\(plan.leftBehind[.theBuildersOwnFiles] ?? 0))")
        if !plan.notLookedInside.isEmpty {
            behind.append("not looked inside: " + plan.notLookedInside.joined(separator: ", "))
        }
        behind.append("\(plan.leftBehind[.shortcutsReplaced] ?? 0) links replaced by what they showed")
        if !plan.editingFolderNames.isEmpty {
            behind.append(
                "editing folders " + plan.editingFolderNames.joined(separator: ", ")
                + " (\(plan.leftBehind[.editingFolders] ?? 0))"
            )
        }
        if !plan.otherSectionNames.isEmpty {
            behind.append(
                "other sections " + plan.otherSectionNames.joined(separator: ", ")
                + " (\(plan.leftBehind[.anotherSectionsPages] ?? 0))"
            )
        }
        if (plan.leftBehind[.notOnTheWebsite] ?? 0) > 0 {
            behind.append("not on the website (\(plan.leftBehind[.notOnTheWebsite] ?? 0))")
        }
        behind.append("Obsidian add-on entries (\(plan.leftBehind[.addOns] ?? 0))")
        line += "; left behind, not lost: " + behind.joined(separator: ", ")
        if plan.lost.isEmpty {
            line += "; nothing lost"
        } else {
            line += "; lost \(plan.lost.count): " + plan.lostPaths.joined(separator: ", ")
        }
        if plan.createsEmptyMedia {
            line += "; an empty Media folder was made"
        }
        return line
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
    ) async throws -> (made: ReferenceCopier.Made, addOnsLeftBehind: ObsidianAddOns.Found) {
        let fileManager: FileManager = FileManager.default
        let sourceURL: URL = request.course.directoryURL
        let displayCode: String = request.course.courseCode

        // What of `.obsidian` stays behind, for the trail line (#255): read
        // again rather than trusted from the sheet, like the walk below.
        let addOnsLeftBehind: ObsidianAddOns.Found = ObsidianAddOns.found(inCourseAt: sourceURL)

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

        // The staging folder is already there, empty: making it was part of
        // the claim (`ReferenceStaging.claim`), so it is ours to fill.

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
        let made: ReferenceCopier.Made = ReferenceCopier.Made(
            folderName: folderName,
            displayCode: staged.displayCode,
            schoolYear: staged.schoolYear,
            sectionCount: staged.sectionCount
        )
        return (made: made, addOnsLeftBehind: addOnsLeftBehind)
    }

    /// One OLDER-layout class: planned again (the sheet's numbers were read
    /// when it opened), copied piece by piece into the hidden folder, given
    /// its settings, and then made into a reference course by exactly the
    /// code every other import uses. Everything after the copy is
    /// `importOneCourse`'s own sequence.
    private static func importOneOlderClass(
        _ request: Request,
        named folderName: String,
        stagedAt stagingURL: URL,
        into destinationURL: URL,
        leavingBehind leftBehindNames: Set<String>,
        courseNumber: Int,
        courseCount: Int,
        progress: @escaping @Sendable @MainActor (Progress) -> Void
    ) async throws -> (made: ReferenceCopier.Made, plan: OlderCourseLayout.Plan) {
        let displayCode: String = request.course.courseCode
        let shared: OlderCourseLayout.SharedContent? = request.course.olderLayout?.shared

        let plan: OlderCourseLayout.Plan = await ReferenceImporter.planOffTheMainActor(
            classFolderURL: request.course.directoryURL,
            sharedFolderURL: shared?.folderURL,
            howFound: shared?.howFound ?? .none,
            leavingBehind: leftBehindNames
        )
        if let unreadable = plan.unreadableFolders.first {
            throw ReferenceTreeCopier.Trouble.couldNotRead(name: unreadable)
        }

        progress(Progress(
            courseCode: displayCode,
            courseNumber: courseNumber,
            courseCount: courseCount,
            copiedBytes: 0,
            totalBytes: plan.byteCount
        ))

        // The staging folder is already there, empty: making it was part of
        // the claim (`ReferenceStaging.claim`), so it is ours to fill.

        let totalBytes: Int64 = plan.byteCount
        try await ReferenceTreeCopier.copy(
            placements: plan.placements, into: stagingURL
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

        let made: ReferenceCopier.Made = try ReferenceImporter.finishPlacedImport(
            stagedAt: stagingURL,
            into: destinationURL,
            named: folderName,
            settingsValues: plan.settingsValues(),
            createsEmptyMedia: plan.createsEmptyMedia,
            schoolYear: request.schoolYear
        )
        return (made: made, plan: plan)
    }

    /// Everything after the copy, for both routes that PLACE files rather
    /// than copy a course whole (#254's older layout, #256's website
    /// folders) — one sequence, not two: an empty `Media` when nothing
    /// supplied one, the settings through the one writer, the lock a frozen
    /// source handed over cleared, marked, filed, neutralised and LOCKED by
    /// `ReferenceCopier`, and renamed into place as the last act.
    private static func finishPlacedImport(
        stagedAt stagingURL: URL,
        into destinationURL: URL,
        named folderName: String,
        settingsValues: [String: Any],
        createsEmptyMedia: Bool,
        schoolYear: Int?
    ) throws -> ReferenceCopier.Made {
        let fileManager: FileManager = FileManager.default

        // Nothing supplied `Media`: an empty one, so the build does not
        // announce on every preview what the sheet already said, and the
        // built site's Media is not a link to nothing.
        if createsEmptyMedia {
            try fileManager.createDirectory(
                at: stagingURL.appendingPathComponent("Media"), withIntermediateDirectories: false
            )
        }

        // Settings, through the one writer every other config goes through.
        let settings: CourseConfiguration = CourseConfiguration(
            values: settingsValues, lastSavedData: Data()
        )
        try settings.write(to: stagingURL.appendingPathComponent(ReferenceImportSource.configFileName))

        // As `importOneCourse`: a source that was itself frozen hands its
        // locks to the copy.
        ReferenceLock.clearLock(at: stagingURL)

        let staged: ReferenceCopier.Made = try ReferenceCopier.makeIntoAReferenceCourse(
            at: stagingURL, schoolYear: schoolYear
        )
        try fileManager.moveItem(at: stagingURL, to: destinationURL)

        return ReferenceCopier.Made(
            folderName: folderName,
            displayCode: staged.displayCode,
            schoolYear: staged.schoolYear,
            sectionCount: staged.sectionCount
        )
    }

    /// One class kept in the 2024–25 layout: its first section planned again
    /// (the sheet's numbers were read when it opened), copied piece by piece
    /// into the hidden folder, and finished exactly as #254's route is.
    private static func importOneWebsite(
        _ request: Request,
        facts: QuartzCheckoutLayout.Facts,
        named folderName: String,
        stagedAt stagingURL: URL,
        into destinationURL: URL,
        leavingBehind leftBehindNames: Set<String>,
        courseNumber: Int,
        courseCount: Int,
        progress: @escaping @Sendable @MainActor (Progress) -> Void
    ) async throws -> (made: ReferenceCopier.Made, plan: QuartzCheckoutLayout.Plan) {
        let displayCode: String = request.course.courseCode

        let plan: QuartzCheckoutLayout.Plan = await ReferenceImporter.planWebsiteOffTheMainActor(
            facts: facts, leavingBehind: leftBehindNames
        )
        if let unreadable = plan.unreadableFolders.first {
            throw ReferenceTreeCopier.Trouble.couldNotRead(name: unreadable)
        }

        progress(Progress(
            courseCode: displayCode,
            courseNumber: courseNumber,
            courseCount: courseCount,
            copiedBytes: 0,
            totalBytes: plan.byteCount
        ))

        // The staging folder is already there, empty: making it was part of
        // the claim (`ReferenceStaging.claim`), so it is ours to fill.

        let totalBytes: Int64 = plan.byteCount
        try await ReferenceTreeCopier.copy(
            placements: plan.placements, into: stagingURL
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

        let made: ReferenceCopier.Made = try ReferenceImporter.finishPlacedImport(
            stagedAt: stagingURL,
            into: destinationURL,
            named: folderName,
            settingsValues: plan.settingsValues(),
            createsEmptyMedia: plan.createsEmptyMedia,
            schoolYear: request.schoolYear
        )
        return (made: made, plan: plan)
    }

    /// The website plan, off the main actor. `@concurrent` for the reason
    /// `surveyOffTheMainActor` gives.
    @concurrent
    private nonisolated static func planWebsiteOffTheMainActor(
        facts: QuartzCheckoutLayout.Facts,
        leavingBehind leftBehindNames: Set<String>
    ) async -> QuartzCheckoutLayout.Plan {
        return QuartzCheckoutLayout.plan(facts: facts, leavingBehind: leftBehindNames)
    }

    /// The older-layout plan, off the main actor. `@concurrent` for the
    /// reason `surveyOffTheMainActor` gives.
    @concurrent
    private nonisolated static func planOffTheMainActor(
        classFolderURL: URL,
        sharedFolderURL: URL?,
        howFound: OlderCourseLayout.HowFound,
        leavingBehind leftBehindNames: Set<String>
    ) async -> OlderCourseLayout.Plan {
        return OlderCourseLayout.plan(
            classFolderURL: classFolderURL,
            sharedFolderURL: sharedFolderURL,
            howFound: howFound,
            leavingBehind: leftBehindNames
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
        // Without the Obsidian add-ons, and without `.obsidian` at all when
        // it is a link (#255) — the rule every route keeps. Passed here
        // rather than folded into `leftBehindNames`, which a caller may
        // override and which matches at every depth.
        return ReferenceTreeCopier.survey(
            courseAt: courseURL,
            leavingBehind: leftBehindNames,
            leavingBehindPaths: ObsidianAddOns.leftBehindFromTheCourse,
            leavingBehindIfALink: ObsidianAddOns.leftBehindWhenALinkFromTheCourse
        )
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
