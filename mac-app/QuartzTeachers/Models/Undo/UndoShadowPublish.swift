import Foundation

/// Publishing and hiding pages (`AssistToolRunner.carryOut`), written to the
/// list in SHADOW beside the action's own writes (#899, U1's one edit).
///
/// The action keeps writing exactly as it did: `AssistPublishPlanner.apply`
/// is not touched, its result is not changed, and its order of effects is
/// not changed. Before it runs, this works out what it WILL write, with the
/// same functions it uses (`AssistPageVisibility.setting`,
/// `PageFrontmatter.settingCreated`), and records that as a step; after it
/// runs, the step is kept only if what was written is exactly what was
/// recorded. The section's front page is recorded as a `recompute` op, the
/// rule that keeps it true, rather than as content (plan 3.1, review 13).
///
/// Every failure here is swallowed: the list is not in use yet, so it can
/// never block, slow noticeably or change the teacher's action (plan 4.9).
///
/// The list itself is read and written OFF the main actor: the pages are
/// read here, then the lock, the read of the journal and the writes run on a
/// task of their own, which the action waits for. A process's first read of
/// the journal is a whole one (100 to 300 ms and more at a year's steady 2
/// to 6 MB, the core review of U1's second round), and it must never hold
/// the window (the director's ruling 8 on U1's third round).
/// When U3 wires this action through `JournaledWrite.perform` itself, this
/// file goes.
@MainActor
enum UndoShadowPublish {

    // MARK: - Functions

    /// Writes the step down, or answers nil when there is nothing to record
    /// or the list could not take it.
    static func begin(
        _ plan: AssistPublishPlan,
        forSection sectionNumber: Int,
        in course: Course,
        workingFolderURL: URL?,
        madeBy: String,
        journal: UndoJournal
    ) async -> UndoShadowTicket? {
        let root: URL = workingFolderURL
            ?? course.directoryURL.deletingLastPathComponent().deletingLastPathComponent()
        let predicted: [UndoFileChange] = predictedChanges(plan, forSection: sectionNumber, in: course, root: root)
        if predicted.isEmpty {
            return nil
        }
        var recomputes: [UndoOp] = []
        if let frontPage = relativePath(of: SectionIndexPointer.indexURL(forSection: sectionNumber, in: course), under: root) {
            recomputes.append(UndoOp.recompute(path: frontPage, maintainer: "sectionFrontPage", section: sectionNumber))
        }
        let draft: UndoStepDraft = UndoStepDraft(
            action: UndoAction(
                key: plan.publishes ? "publishPages" : "hidePages",
                arguments: ["pageCount": String(predicted.count)]
            ),
            madeBy: madeBy,
            workingFolderURL: root,
            workingFolderPath: FolderIdentity.canonicalPath(root.path),
            course: course.code,
            section: sectionNumber,
            actionClass: "A",
            holds: "section",
            changes: predicted,
            recomputes: recomputes
        )
        let recording: Task<UndoShadowTicket?, Never> = Task.detached(priority: .userInitiated) {
            return JournaledWrite.beginInShadow(draft, in: journal)
        }
        return await recording.value
    }

    /// Closes the step with what `apply` actually wrote (nil: it threw).
    static func finish(
        _ ticket: UndoShadowTicket?,
        written change: AssistChange?,
        forSection sectionNumber: Int,
        in course: Course,
        journal: UndoJournal
    ) async {
        guard let ticket else {
            return
        }
        guard let change else {
            await closeOffTheMainActor(ticket, actuallyWritten: nil, in: journal)
            return
        }
        let frontPage: URL = SectionIndexPointer.indexURL(forSection: sectionNumber, in: course).standardizedFileURL
        var written: [String: Data?] = [:]
        for file in change.files {
            if file.fileURL.standardizedFileURL == frontPage {
                continue
            }
            guard let path = relativePath(of: file.fileURL, under: ticket.draft.workingFolderURL) else {
                continue
            }
            var after: Data? = nil
            if let text = file.after {
                after = Data(text.utf8)
            }
            written[path] = after
        }
        await closeOffTheMainActor(ticket, actuallyWritten: written, in: journal)
    }

    /// `JournaledWrite.finishInShadow` on a task of its own, waited for.
    static func closeOffTheMainActor(
        _ ticket: UndoShadowTicket,
        actuallyWritten: [String: Data?]?,
        in journal: UndoJournal
    ) async {
        let closing: Task<Void, Never> = Task.detached(priority: .userInitiated) {
            JournaledWrite.finishInShadow(ticket, actuallyWritten: actuallyWritten, in: journal)
        }
        await closing.value
    }

    /// What `AssistPublishPlanner.apply` will write, page by page: the same
    /// gathering, the same writers, in the same order, and nothing written.
    /// `before` is each file's bytes on the disk, read now.
    static func predictedChanges(
        _ plan: AssistPublishPlan,
        forSection sectionNumber: Int,
        in course: Course,
        root: URL
    ) -> [UndoFileChange] {
        var editsByPath: [String: (url: URL, isSectionLocal: Bool)] = [:]
        var publishByPath: [String: Bool] = [:]
        var dateByPath: [String: CalendarDay] = [:]
        for change in plan.changes {
            let path: String = change.page.fileURL.path
            editsByPath[path] = (change.page.fileURL, change.page.isSectionLocal)
            publishByPath[path] = change.willBeVisible
        }
        for move in plan.dateMoves {
            let path: String = move.page.fileURL.path
            editsByPath[path] = (move.page.fileURL, move.page.isSectionLocal)
            dateByPath[path] = move.to
        }
        var paths: [String] = []
        for (path, _) in editsByPath {
            paths.append(path)
        }
        paths.sort()

        let tail: String = ClassPages.siblingTimeAndOffset(
            from: ClassPages.list(forSection: sectionNumber, in: course),
            forSection: sectionNumber
        )

        var result: [UndoFileChange] = []
        for path in paths {
            guard let edit = editsByPath[path] else {
                continue
            }
            guard let disk = try? Data(contentsOf: edit.url),
                  let read = try? String(contentsOf: edit.url, encoding: .utf8) else {
                continue
            }
            var text: String = read
            if let published = publishByPath[path] {
                text = AssistPageVisibility.setting(
                    published: published, in: text,
                    forSection: sectionNumber, isSectionLocal: edit.isSectionLocal
                ).text
            }
            if let day = dateByPath[path] {
                text = PageFrontmatter.settingCreated(
                    in: text,
                    key: PageFrontmatter.createdKey(forSection: sectionNumber, isSectionLocal: edit.isSectionLocal),
                    to: day,
                    fallbackTail: tail
                ).text
            }
            if text == read {
                continue
            }
            guard let relative = relativePath(of: edit.url, under: root) else {
                // A page outside the working folder cannot be named in a
                // step: said on the trail, never silently skipped.
                UndoTrailHook.couldNotRecordLine?(
                    plan.publishes ? "publishPages" : "hidePages", course.code, sectionNumber,
                    .shadow, "a page is outside the working folder"
                )
                return []
            }
            result.append(UndoFileChange(relativePath: relative, before: disk, after: Data(text.utf8)))
        }
        return result
    }

    /// The path inside the working folder, with forward slashes, or nil.
    /// Both sides have their links resolved the same way, so a folder
    /// reached through `/var` or a linked folder is still the same folder
    /// (the core review: a differently spelled root recorded nothing).
    static func relativePath(of url: URL, under root: URL) -> String? {
        let rootPath: String = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let path: String = url.resolvingSymlinksInPath().standardizedFileURL.path
        if !path.hasPrefix(rootPath) {
            return nil
        }
        return String(path.dropFirst(rootPath.count))
    }
}
