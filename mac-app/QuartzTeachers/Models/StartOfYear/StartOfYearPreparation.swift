import Foundation

/// The APP's act of getting a section ready for the start of the year, and of
/// taking it back (#96). The sheet calls these; the MCP tools have their own
/// path through `AssistToolRunner`, and the two share the planner, the writer
/// and the trail's words.
///
/// The order is load-bearing, and it is the plan's:
///
/// 1. re-plan from disk, and write NOTHING if the plan differs from the one on
///    screen — the teacher gets the new one to read instead;
/// 2. back the course up (`.teacher`'s: they pressed the button) and REFUSE if
///    that fails — the largest single write the app makes is not made without
///    a way back;
/// 3. stop the section's preview if it is running and nothing blocks a build,
///    and wait for it — a preview serving pages as they are rewritten serves a
///    half-changed site;
/// 4. write;
/// 5. hold the undo;
/// 6. write the trail line;
/// 7. start the preview again if it was running.
enum StartOfYearPreparation {

    // MARK: - Types

    /// How pressing Go ended.
    enum Outcome {

        /// Written. Carries what the sheet shows afterwards.
        case done(Done)

        /// The section changed after the plan on screen was made; nothing was
        /// written, and here is the plan as it stands now.
        case changedSinceShown(StartOfYearPlan)

        /// Nothing was written, and this sentence says why.
        case refused(String)
    }

    struct Done {

        // MARK: - Stored properties

        let pagesWritten: Int
        let leftAlone: [String]
        let backupFileName: String

        /// Set when another program was building the course, so the preview
        /// was left as it was (#156).
        let previewNote: String?
    }

    /// How an undo ended.
    struct Undone {

        // MARK: - Stored properties

        let putBack: Int
        let skipped: [URL]
    }

    // MARK: - Functions

    /// Press Go.
    ///
    /// `backUp` is injectable so a test can make the backup fail; it is
    /// `CourseArchiver.backUpCourse(…, madeBy: .teacher)` otherwise.
    static func carryOut(
        shownFingerprint: String,
        forSection sectionNumber: Int,
        in course: Course,
        workspaceURL: URL,
        today: CalendarDay,
        backUp: (Course, URL) throws -> URL = { course, coursesDirectoryURL in
            return try CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL, madeBy: .teacher)
        }
    ) async -> Outcome {
        let folderPath: String = workspaceURL.path
        let scheduled: Date? = ScheduledDeploy.nextRun(
            courseCode: course.code, sectionNumber: sectionNumber, inWorkingFolder: workspaceURL
        )

        // 1. Re-plan from disk.
        let planned: Result<StartOfYearPlan, StartOfYearProblem> = StartOfYearPlanner.plan(
            forSection: sectionNumber, in: course, workspaceURL: workspaceURL,
            today: today, scheduledDeploy: scheduled
        )
        let plan: StartOfYearPlan
        switch planned {
        case .failure(let problem):
            noteNotDone(problem.trailReason, course: course, section: sectionNumber)
            return .refused(problem.sentence)
        case .success(let fresh):
            plan = fresh
        }
        if plan.fingerprint != shownFingerprint {
            noteNotDone("changedSinceShown", course: course, section: sectionNumber)
            return .changedSinceShown(plan)
        }
        if plan.changesNothing {
            noteNotDone("nothingToDo", course: course, section: sectionNumber)
            return .refused(StartOfYearWording.nothingToDo(
                first: plan.firstClass.displayTitle, nouns: plan.noun.plural
            ))
        }

        // 2. A backup, or nothing.
        let coursesDirectoryURL: URL = workspaceURL.appendingPathComponent("courses", isDirectory: true)
        let backupURL: URL
        do {
            backupURL = try backUp(course, coursesDirectoryURL)
        } catch {
            noteNotDone("backupFailed", course: course, section: sectionNumber)
            return .refused(StartOfYearWording.backupFailed(course: course.displayCode))
        }

        // 3. Stop the preview, unless another program holds the course — its
        // build is not ours to end, and a preview stopped now could not be
        // started again (#156).
        let blocked: WorkLeaseFiles.Holding? = WorkLeaseRegistry.whatBlocksABuild(
            folderPath: folderPath, courseCode: course.code, afterTaking: false
        )
        let controller: SectionWindowControllers.Controller? = SectionWindowControllers.shared.controller(
            folderPath: folderPath, courseCode: course.code, sectionNumber: sectionNumber
        )
        var wasRunning: Bool = false
        if blocked == nil, let controller, controller.isPreviewRunning() {
            wasRunning = true
            await controller.stopPreview()
        }

        // 4. Write.
        let applied: (change: AssistChange, leftAlone: [String])
        do {
            applied = try StartOfYearPlanner.apply(plan, in: course)
        } catch {
            noteNotDone("writeFailed", course: course, section: sectionNumber)
            if wasRunning, let controller {
                controller.startPreview()
            }
            return .refused(StartOfYearWording.writeFailed(backup: backupURL.lastPathComponent))
        }

        // 5. Hold the undo.
        StartOfYearUndoRegistry.shared.record(
            StartOfYearUndoRegistry.Entry(
                change: applied.change,
                backupFileName: backupURL.lastPathComponent,
                visibilityAfter: StartOfYearUndoRegistry.visibilitySnapshot(
                    forSection: sectionNumber, in: course, workspaceURL: workspaceURL
                ),
                scheduledDeploy: scheduled
            ),
            folderPath: folderPath, courseCode: course.code, sectionNumber: sectionNumber
        )

        // 6. The trail.
        ActivityTrail.note(
            .sectionMadeReadyForTheStartOfTheYear,
            ActivityTrail.sectionMadeReadyLine(
                source: "app",
                classes: plan.classChangeCount,
                otherPagesByReason: plan.otherChangesByReason,
                leftAsTheyWere: plan.publishPlan.noRoomForAKey.count + applied.leftAlone.count,
                backupFileName: backupURL.lastPathComponent,
                previewRebuilt: wasRunning
            ),
            course: course.code, section: sectionNumber
        )

        // 7. The preview back up, built from what is on disk now.
        if wasRunning, let controller {
            controller.startPreview()
        }

        var previewNote: String? = nil
        if blocked != nil {
            previewNote = AssistWording.courseIsBeingBuiltElsewhere(course: course.displayCode)
        }
        return .done(Done(
            pagesWritten: max(0, plan.changeCount - applied.leftAlone.count),
            leftAlone: applied.leftAlone,
            backupFileName: backupURL.lastPathComponent,
            previewNote: previewNote
        ))
    }

    /// The files an undo would put back, and the ones it would leave because
    /// they changed after the change was made — asked before the teacher
    /// agrees, so the undo sheet can list both.
    static func whatAnUndoWouldDo(_ entry: StartOfYearUndoRegistry.Entry) -> (putBack: [URL], skipped: [URL]) {
        var putBack: [URL] = []
        var skipped: [URL] = []
        for file in entry.change.files {
            let current: String? = try? String(contentsOf: file.fileURL, encoding: .utf8)
            if current != file.after {
                skipped.append(file.fileURL)
            } else {
                putBack.append(file.fileURL)
            }
        }
        return (putBack, skipped)
    }

    /// Take the held change back: stop the preview, put the files back by the
    /// assistant's own skip rule, write the trail line, start the preview.
    static func undo(
        _ entry: StartOfYearUndoRegistry.Entry,
        forSection sectionNumber: Int,
        in course: Course,
        workspaceURL: URL
    ) async -> Undone {
        let folderPath: String = workspaceURL.path
        let blocked: WorkLeaseFiles.Holding? = WorkLeaseRegistry.whatBlocksABuild(
            folderPath: folderPath, courseCode: course.code, afterTaking: false
        )
        let controller: SectionWindowControllers.Controller? = SectionWindowControllers.shared.controller(
            folderPath: folderPath, courseCode: course.code, sectionNumber: sectionNumber
        )
        var wasRunning: Bool = false
        if blocked == nil, let controller, controller.isPreviewRunning() {
            wasRunning = true
            await controller.stopPreview()
        }

        let history: AssistChangeHistory = AssistChangeHistory()
        history.record(entry.change)
        let result: AssistUndoResult = history.undo()

        // Offered once. A partial undo is not offered again: the pages it put
        // back no longer match what the change left, so the section is no
        // longer the one the undo was made for, and the rest is the
        // backup's job — the sentence after it names the backup.
        StartOfYearUndoRegistry.shared.forget(
            folderPath: folderPath, courseCode: course.code, sectionNumber: sectionNumber
        )

        ActivityTrail.note(
            .startOfTheYearChangeUndone,
            ActivityTrail.startOfYearUndoneLine(
                source: "app", putBack: result.restored.count, leftAsTheyAre: result.skipped.count
            ),
            course: course.code, section: sectionNumber
        )

        if wasRunning, let controller {
            controller.startPreview()
        }
        return Undone(putBack: result.restored.count, skipped: result.skipped)
    }

    // MARK: - Private helpers

    private static func noteNotDone(_ reason: String, course: Course, section: Int) {
        ActivityTrail.note(
            .startOfTheYearNotDone,
            ActivityTrail.startOfYearNotDoneLine(source: "app", reason: reason),
            course: course.code, section: section
        )
    }
}
