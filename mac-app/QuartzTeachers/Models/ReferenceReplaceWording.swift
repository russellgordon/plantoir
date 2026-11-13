import Foundation

/// What a teacher reads about replacing a reference course (#572, second
/// piece). Every sentence is `contracts/shared-rules.json` →
/// `referenceCourses.replacing.wording`, and a test holds each one to it.
///
/// `{course}` is the code a teacher reads (`ICS3U`), `{group}` the group it
/// sits in on the shelf (`2025–26`, or `Other`), and `{folder}` the name its
/// row carries in Backups, which is its folder's.
nonisolated enum ReferenceReplaceWording {

    // MARK: - Stored properties

    /// The button beside the shelf rule's refusal.
    static let replaceButton: String = "Replace It…"

    /// The warning's destructive button.
    static let confirmButton: String = "Replace"

    /// The warning's default button.
    static let cancelButton: String = "Cancel"

    // MARK: - Functions

    /// The warning's title.
    static func title(course: String, group: String) -> String {
        return "Replace \(course) in \(group)?"
    }

    /// The warning's body: what the course on the shelf holds and when it
    /// was kept, then what Plantoir does first and how to get it back (plan
    /// review M9: the backup's name, where it is, and what restoring it
    /// does).
    static func body(
        course: String,
        group: String,
        sections: String,
        pages: String,
        size: String,
        date: String,
        folder: String
    ) -> String {
        return "\(course) in \(group) holds \(sections), \(pages) and \(size), and was kept on \(date). "
             + ReferenceReplaceWording.whatHappensFirst(course: course, folder: folder)
    }

    /// The same body when the day it was kept cannot be read.
    static func bodyWithoutADate(
        course: String,
        group: String,
        sections: String,
        pages: String,
        size: String,
        folder: String
    ) -> String {
        return "\(course) in \(group) holds \(sections), \(pages) and \(size). "
             + ReferenceReplaceWording.whatHappensFirst(course: course, folder: folder)
    }

    /// "1 section" or "3 sections".
    static func sections(_ count: Int) -> String {
        return count == 1 ? "1 section" : "\(count) sections"
    }

    /// "1 page" or "40 pages".
    static func pages(_ count: Int) -> String {
        return count == 1 ? "1 page" : "\(count) pages"
    }

    /// Refused while the course is previewing, or a copy of it is being
    /// saved: the folder is about to be swapped.
    static func replaceWhileBusy(course: String) -> String {
        return "\(course) is previewing or being backed up right now. Wait for that to finish, then replace it."
    }

    /// Refused while Obsidian has the course open as a vault (plan review
    /// M2): swapping the folder would leave Obsidian showing pages that are
    /// no longer there.
    static func openInObsidian(course: String) -> String {
        return "\(course) is open in Obsidian. Close it there first, then replace it."
    }

    /// Refused for anything that is not on the Reference Courses shelf. No
    /// door offers it; this is the act's own guard.
    static func notOnTheShelf(course: String) -> String {
        return "Only a course kept for reference can be replaced, and \(course) is not one."
    }

    /// The backup could not be made, or did not hold the whole course.
    static func couldNotBackUp(course: String) -> String {
        return "\(course) could not be backed up, so it was not replaced."
    }

    /// A backup was made and did not hold every file of the course: the
    /// course is left exactly as it was, the backup is kept and said by the
    /// name its row has in Backups, and the teacher is told what they can
    /// do (implementation review M1).
    static func backupIsIncomplete(course: String, folder: String) -> String {
        return "\(course) was not replaced, and it is exactly as it was: some of its files could not go into "
             + "a backup. The backup that was made is in Backups in the sidebar as \(folder), without those "
             + "files. Keep \(course) and choose another school year for the new one, or delete that backup "
             + "if you do not need it."
    }

    /// Replace was pressed for a course that has since moved to another
    /// school year or gone, so nothing was replaced.
    static func notTheCourseInTheWay(folder: String) -> String {
        return "\(folder) is no longer in the way in that school year, so nothing was replaced. Look at the choices again."
    }

    /// Something after the backup failed, and the course was put back.
    static func couldNotReplace(course: String) -> String {
        return "\(course) could not be replaced. It is as it was."
    }

    /// Something after the backup failed, and putting the course back failed
    /// too. The next reading of the folder puts it back.
    static func couldNotPutBackYet(course: String) -> String {
        return "\(course) could not be replaced, and it could not be put back straight away. "
             + "Plantoir puts it back the next time this working folder is opened, "
             + "and its backup is in Backups in the sidebar."
    }

    /// Said once a replace has happened, where a sheet stays up to say so.
    static func replacedNote(course: String, group: String, folder: String) -> String {
        return "The \(course) in \(group) was replaced. Its backup is in Backups in the sidebar as \(folder)."
    }

    // MARK: - Private helpers

    private static func whatHappensFirst(course: String, folder: String) -> String {
        return "Plantoir backs it up first, and the backup is listed in Backups in the sidebar as \(folder). "
             + "Restoring that backup puts this \(course) back in place of the new one."
    }
}
