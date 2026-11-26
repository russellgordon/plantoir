import Foundation

/// Putting ONE section back to how it was when a conversation started.
///
/// The assistant saves a copy of the whole course before the first change of a
/// conversation — see `AssistToolRunner.conversationBackupURL`. That copy is
/// whole because a zip of a folder is whole; it is not a licence to put the
/// whole thing back. A teacher can be marking Section 2 in Obsidian while they
/// chat about Section 1, and a whole-course restore would silently undo an
/// evening's marking to fix a publishing mistake. So this puts back only what a
/// conversation about ONE section could have changed, and says so in words
/// before it does.
///
/// The wording lives here rather than in the window for one reason: the
/// sentence a teacher reads before pressing the button and the sentence the
/// transcript records afterwards have to describe the same act, and keeping
/// them beside the code that performs it is what keeps them honest.
enum AssistSectionRestore {

    // MARK: - Types

    /// Why a restore could not go ahead, in words a teacher can act on.
    enum Problem: LocalizedError {
        case nothingToRestore
        case noWorkingFolder
        case unreadableBackup(String)
        /// A Rename folder of the course is under way in some window (#909,
        /// the review after the merge of `dev`, HIGH 1): the rename's own
        /// sentence, `undo.wording.renameFolderUnderWay`.
        case folderRenameUnderWay(String)

        var errorDescription: String? {
            switch self {
            case .nothingToRestore:
                return "This conversation hasn't changed anything yet, so there is nothing to put back."
            case .noWorkingFolder:
                return "Plantoir cannot find the working folder these courses live in."
            case .unreadableBackup(let name):
                return "The copy saved for this conversation (\(name)) could not be read."
            case .folderRenameUnderWay(let course):
                return CourseActivity.folderRenameIsUnderWay(course: course)
            }
        }
    }

    // MARK: - Functions

    /// What the banner's button says. The ellipsis is the promise that a
    /// question comes next — pressing this alone changes nothing.
    static func buttonTitle(sectionNumber: Int) -> String {
        return "Restore Section \(sectionNumber)…"
    }

    /// The banner's own line, which is also what makes the button make sense:
    /// a Restore offered before anything has changed would be a puzzle.
    static func bannerTitle(sectionNumber: Int) -> String {
        return "This conversation has changed Section \(sectionNumber)."
    }

    static func bannerDetail() -> String {
        return "A copy from before it started is saved."
    }

    /// The question at the top of the confirmation.
    static func confirmationTitle(courseCode: String, sectionNumber: Int) -> String {
        return "Put \(courseCode) Section \(sectionNumber) back to how it was?"
    }

    /// The three things a teacher has to know before saying yes.
    ///
    /// The third paragraph is the whole reason this is a question rather than a
    /// button. Everything else here a teacher would guess correctly; that their
    /// OWN work in this section — typed in Obsidian, minutes ago, having
    /// nothing to do with the assistant — goes back too is the one nobody
    /// guesses. It is said plainly, in the second person, and it is not
    /// softened.
    static func confirmationMessage(courseCode: String, sectionNumber: Int) -> String {
        return """
        Section \(sectionNumber) goes back to exactly how it was when this conversation started — \
        its pages, and whether the course's shared pages are published for Section \(sectionNumber).

        Your other sections are not touched. Their pages, and their own publishing, stay exactly \
        as they are.

        Anything YOU changed in Section \(sectionNumber) since this conversation started goes back \
        too — work done in Obsidian included. Plantoir cannot bring that part back.
        """
    }

    /// The button that actually does it. Named after the act rather than
    /// "OK", so a teacher skimming the sheet still reads what will happen.
    static func goAheadTitle(sectionNumber: Int) -> String {
        return "Restore Section \(sectionNumber)"
    }

    /// What the transcript records afterwards, so the conversation holds the
    /// whole story of what happened during it.
    ///
    /// `settingsNotPutBack` is how many shared pages kept their current
    /// setting because there was nowhere on them to put the backup's back
    /// (`CourseRestorer.restoreSection`, #182). Almost always 0, and then the
    /// message is exactly what it always was; otherwise it says so, because
    /// "put back to how it was" would not be true of those pages.
    static func doneMessage(courseCode: String, sectionNumber: Int, settingsNotPutBack: Int = 0) -> String {
        let done: String = "Put \(courseCode) Section \(sectionNumber) back to how it was when this conversation "
             + "started. Nothing in your other sections was touched. Ask me to rebuild the preview to "
             + "see it."
        if settingsNotPutBack <= 0 {
            return done
        }
        return done + " " + AssistWording.sharedPagesWhoseSettingsCouldNotBePutBack(
            count: settingsNotPutBack, section: String(sectionNumber)
        )
    }

    /// What the window says once the section is back, line by line:
    /// `doneMessage` first, unchanged (#897 froze it), then, when the
    /// restore kept folders backups leave out from inside the section,
    /// Russell's sentence for them as a line of its own (#909, ruling 1 of
    /// 2026-11-26: "the window route gets a sentence of its own").
    static func doneLines(courseCode: String, sectionNumber: Int, putBack: CourseRestorer.SectionPutBack) -> [String] {
        var lines: [String] = [
            doneMessage(courseCode: courseCode, sectionNumber: sectionNumber, settingsNotPutBack: putBack.pagesNotPutBack)
        ]
        if let keptAt = putBack.leftOutFoldersKeptAt,
           let kept = OneSectionRestoreWording.leftOutKept(inside: putBack.leftOutFoldersKept, keptAt: keptAt) {
            lines.append(kept)
        }
        return lines
    }

    /// What the breadcrumb trail records afterwards — a different audience
    /// from `doneMessage`, and a different job.
    ///
    /// `doneMessage` is read inside the conversation, by a teacher who has
    /// just pressed the button and knows what they did. This is read months
    /// later, by somebody looking at a section whose pages are older than the
    /// changes listed above them, and it is the only line that explains why.
    ///
    /// It is a function rather than a string typed at the call site so that a
    /// test can pin it by NAME. A quoted copy in a test is the one that keeps
    /// passing after the words change.
    ///
    /// The file name and nothing else: which copy it came from is what makes
    /// the line worth having, and it says nothing about what is written on any
    /// page — `contracts/shared-rules.json` → `activityTrail.mustRecord`,
    /// "never a page".
    static func trailLine(backupFileName: String) -> String {
        return "put the section back to how it was when this conversation started, from "
             + backupFileName
    }

    /// What `trailLine` says when the backup's name is somehow not to hand.
    /// A restore that got as far as succeeding had a backup — `restore` refuses
    /// without one — so this is defence rather than a case that happens. A line
    /// naming no file is still worth more than no line at all.
    static let unnamedBackup: String = "a copy made when it started"

    /// Writes the restore onto the breadcrumb trail.
    ///
    /// Its own function so that the whole line a teacher's problem report will
    /// carry — the course and section prefix included — can be pinned by a
    /// test. Calling `ActivityTrail.note`'s two-argument overload by mistake
    /// would silently drop the `ICS3U/1 · ` prefix that
    /// `contracts/shared-rules.json` → `activityTrail.mustRecord` requires
    /// ("which course and section, AND the file name"), and nothing about the
    /// call site would look wrong.
    static func noteRestored(courseCode: String, sectionNumber: Int, backupURL: URL?) {
        ActivityTrail.note(
            .sectionRestored,
            trailLine(backupFileName: backupURL?.lastPathComponent ?? unnamedBackup),
            course: courseCode,
            section: sectionNumber
        )
    }

    /// What the trail records when some shared pages could not have their
    /// setting put back — a COUNT, never which pages (`contracts/
    /// shared-rules.json` → `activityTrail.mustRecord`, `page settings left
    /// as they were`). Nothing is written when the count is 0.
    static func notePagesNotPutBack(_ count: Int, courseCode: String, sectionNumber: Int) {
        if count <= 0 {
            return
        }
        ActivityTrail.note(
            .pageSettingsLeftAsTheyWere,
            ActivityTrail.pageSettingsLeftAsTheyWereLine(act: "putting the section back", pages: count),
            course: courseCode,
            section: sectionNumber
        )
    }

    /// Whether Restore Section N… waits for a Rename folder of the course
    /// under way in any window (#909): the window's button is disabled while
    /// it is true, and `restore` refuses then too.
    @MainActor
    static func waitsForARename(courseCode: String, coursesDirectoryURL: URL?) -> Bool {
        guard let coursesDirectoryURL else {
            return false
        }
        return CourseActivity.courseIsRenamingAFolder(
            folderPath: coursesDirectoryURL.deletingLastPathComponent().path, courseCode: courseCode
        )
    }

    /// Do it — or refuse, when there is nothing saved to go back to, or while a
    /// Rename folder of the course is under way (`waitsForARename`).
    ///
    /// A conversation that has only READ has no backup, which is exactly the
    /// case where a restore would be a surprise rather than a rescue.
    ///
    /// Returns how many shared pages kept their current setting because
    /// there was nowhere on them to put the backup's back — see
    /// `doneMessage`.
    @MainActor
    @discardableResult
    static func restore(
        backupURL: URL?,
        courseCode: String,
        sectionNumber: Int,
        coursesDirectoryURL: URL?
    ) throws -> Int {
        let putBack: CourseRestorer.SectionPutBack = try restoreSayingWhatWasKept(
            backupURL: backupURL, courseCode: courseCode,
            sectionNumber: sectionNumber, coursesDirectoryURL: coursesDirectoryURL
        )
        return putBack.pagesNotPutBack
    }

    /// `restore`, saying what it kept as well (#909), for `doneLines`.
    @MainActor
    static func restoreSayingWhatWasKept(
        backupURL: URL?,
        courseCode: String,
        sectionNumber: Int,
        coursesDirectoryURL: URL?
    ) throws -> CourseRestorer.SectionPutBack {
        guard let backupURL else {
            throw Problem.nothingToRestore
        }
        guard let coursesDirectoryURL else {
            throw Problem.noWorkingFolder
        }
        if waitsForARename(courseCode: courseCode, coursesDirectoryURL: coursesDirectoryURL) {
            throw Problem.folderRenameUnderWay(courseCode)
        }
        guard let item = BackupItem.from(fileURL: backupURL, courseCode: courseCode) else {
            throw Problem.unreadableBackup(backupURL.lastPathComponent)
        }
        // A copy that is no longer there — deleted in Finder, since the app
        // refuses to delete it while this window is open (#242) — is refused
        // with the same plain sentence BEFORE anything is touched, rather
        // than with the unzip tool's own error part way through.
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            throw Problem.unreadableBackup(backupURL.lastPathComponent)
        }
        return try CourseRestorer.restoreSectionSayingWhatWasKept(
            sectionNumber, from: item, coursesDirectoryURL: coursesDirectoryURL
        )
    }
}
