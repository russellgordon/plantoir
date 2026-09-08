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

        var errorDescription: String? {
            switch self {
            case .nothingToRestore:
                return "This conversation hasn't changed anything yet, so there is nothing to put back."
            case .noWorkingFolder:
                return "Plantoir cannot find the working folder these courses live in."
            case .unreadableBackup(let name):
                return "The copy saved for this conversation (\(name)) could not be read."
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
    static func doneMessage(courseCode: String, sectionNumber: Int) -> String {
        return "Put \(courseCode) Section \(sectionNumber) back to how it was when this conversation "
             + "started. Nothing in your other sections was touched. Ask me to rebuild the preview to "
             + "see it."
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
    /// It should not happen — a restore that got as far as succeeding had a
    /// backup — but a line naming no file is still worth more than a crash or
    /// an empty one.
    static let unnamedBackup: String = "a copy made when it started"

    /// Do it — or refuse, when there is nothing saved to go back to.
    ///
    /// A conversation that has only READ has no backup, which is exactly the
    /// case where a restore would be a surprise rather than a rescue.
    static func restore(
        backupURL: URL?,
        courseCode: String,
        sectionNumber: Int,
        coursesDirectoryURL: URL?
    ) throws {
        guard let backupURL else {
            throw Problem.nothingToRestore
        }
        guard let coursesDirectoryURL else {
            throw Problem.noWorkingFolder
        }
        guard let item = BackupItem.from(fileURL: backupURL, courseCode: courseCode) else {
            throw Problem.unreadableBackup(backupURL.lastPathComponent)
        }
        try CourseRestorer.restoreSection(
            sectionNumber, from: item, coursesDirectoryURL: coursesDirectoryURL
        )
    }
}
