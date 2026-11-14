import Foundation

/// Every sentence a whole-course restore says (#909), as
/// `contracts/course-management.json` → `backups.restoreWholeCourse.wording`
/// holds them, so Windows shows the same words. Pinned by
/// `RestoreWholeCourseContractTests`.
nonisolated enum RestoreWholeCourseWording {

    // MARK: - Stored properties

    static let didNotFinishTitle: String = "A restore did not finish"

    /// The way to unlock an item, which differs by platform: the contract
    /// writes `unlockIt` once with the `{unlockInTheFileManager}`
    /// placeholder, and each app puts in its own (`wording.placeholders`,
    /// the implementation review's I6, after `deployTokens.placeholders`
    /// → `{deployingSettings}`).
    static let unlockInTheFileManagerPlaceholder: String = "{unlockInTheFileManager}"

    /// This platform's words for the placeholder.
    static let unlockInTheFileManagerOnThisPlatform: String =
        "In the Finder, select it, choose File ▸ Get Info, and untick Locked, or give yourself Read & Write under Sharing & Permissions."

    /// The contract's `unlockIt`, as written there.
    static let unlockItTemplate: String = "{unlockInTheFileManager}"

    // MARK: - Computed properties

    /// `unlockIt` with this platform's words put in.
    static var unlockIt: String {
        return unlockItTemplate.replacingOccurrences(
            of: unlockInTheFileManagerPlaceholder, with: unlockInTheFileManagerOnThisPlatform
        )
    }

    // MARK: - Functions

    static func leftAsItWas(course: String, reason: String) -> String {
        return "\(course) was left as it was, because the restore could not finish: \(reason)"
    }

    /// A move refused for a lock or a permission at the top of the course
    /// (Russell's held question M13: nothing changes and the item is named).
    /// This platform's way to unlock it follows (`unlockIt`); Windows also
    /// says `leftAsItWasInUse` for a file another program holds open, which
    /// the mac never meets.
    static func leftAsItWasLocked(course: String, name: String) -> String {
        return "\(course) was left as it was, because \"\(name)\" in it is locked or cannot be changed. "
             + "Unlock it, then restore again."
    }

    /// The course folder ITSELF is read-only or Locked (the implementation
    /// review's M-b), so it is the folder that is named.
    static func leftAsItWasFolderLocked(course: String) -> String {
        return "\(course) was left as it was, because its folder, \"\(course)\", is locked or cannot be changed. "
             + "Unlock the folder, then restore again."
    }

    static func leftAsItWasInUse(course: String, name: String) -> String {
        return "\(course) was left as it was, because \"\(name)\" in it is open in another program. "
             + "Close it there, then restore again."
    }

    static func notEnoughSpace(course: String, size: String) -> String {
        return "\(course) was left as it was, because the disk it is on does not have room for the restore. "
             + "About \(size) more free space is needed."
    }

    static func ranOutOfSpace(course: String) -> String {
        return "\(course) was left as it was, because the disk it is on ran out of room while the backup was being opened."
    }

    static func stoppedPartWay(course: String, keptAt: String) -> String {
        return "The restore of \(course) stopped part way, so \(course) may now hold some files from the backup "
             + "and some as they were. Nothing was deleted: the files that were set aside are in the folder "
             + "\"\(keptAt)\" inside your working folder."
    }

    static func stoppedPartWayNothingToOpen(course: String) -> String {
        return "The restore of \(course) stopped part way, so \(course) may now hold some files from the backup "
             + "and some as they were. Nothing was deleted, and none of your pages are left set aside."
    }

    /// Added after a stop that left the course without its settings file,
    /// so the sentence before it does not point at a course the sidebar
    /// does not show (the plan review, L4).
    static func notInTheSidebar(course: String) -> String {
        return "Until its settings are back, \(course) does not show in the sidebar."
    }

    /// After `notInTheSidebar`: how the teacher gets the course back (the
    /// implementation review's I1). A restore of a course folder no archive
    /// was made of keeps what is in it first (`CourseRestorer.restoreBackup`).
    static func restoreAgainToPutItRight(course: String) -> String {
        return "To put it right, restore a backup of \(course) again: what is in its folder now is kept first, not deleted."
    }

    /// The title of the alert a restore that worked shows when it kept
    /// files (`keptWhatWasInTheFolder`, `keptWhatTheArchiveMayNotHold`).
    static func restoredTitle(course: String) -> String {
        return "\(course) is restored"
    }

    /// After a restore over a course folder no archive was made of (the fix
    /// review's I-b): where what was in it went. Kept as the one-section
    /// restore's set-aside folders are, in the course's backups folder until
    /// the teacher deletes it.
    static func keptWhatWasInTheFolder(course: String, keptAt: String) -> String {
        return "What was in the \(course) folder before the restore is kept in the folder \"\(keptAt)\" inside your "
             + "working folder. Plantoir never deletes it: delete it yourself once you no longer need it."
    }

    /// After a restore that worked, when files of the course as it was may
    /// not be in the archive made first (the third case).
    static func keptWhatTheArchiveMayNotHold(course: String, keptAt: String) -> String {
        return "Some files that were in \(course) may not be in the copy that moved to Archived, because they were added "
             + "or changed while that copy was being made or are of a kind backups leave out. They are kept in the folder "
             + "\"\(keptAt)\" inside your working folder."
    }

    /// Under All Backups' total, when restores have kept folders beside the
    /// backups (#909 round four): the sidebar's size counts them too, so
    /// the two numbers are told apart.
    static func keptFoldersTake(size: String) -> String {
        return "Folders that restores kept beside them take a further \(size), counted in the size beside Backups."
    }

    /// The confirmation's last word on what happens to the course as it is,
    /// when it is a course the sidebar lists, so it is archived first: the
    /// paragraph the confirmation has always had, byte for byte.
    static let confirmArchived: String =
        "Nothing is lost, though: the version you have right now moves to Archived, at the bottom of the sidebar, where you can get it back."

    /// The confirmation's last word on what happens to the course as it is,
    /// when no archive will be made because the folder is not a course the
    /// sidebar lists (the fix review's I-b: it said the version moves to
    /// Archived, and nothing was archived).
    static func confirmKeptWithItsBackups(course: String) -> String {
        return "Nothing is lost, though: what is in the \(course) folder now is kept in a folder of its own with its "
             + "backups, and you are told where once the restore is done."
    }

    /// The same, when there is no course folder at all.
    static func confirmNoCourseFolder(course: String) -> String {
        return "There is no \(course) folder now, so nothing is replaced."
    }

    static func didNotFinish(course: String) -> String {
        return "The restore of \(course) from a backup did not finish, so \(course) was left as it was. "
             + "The backup is still in Backups, and you can restore it again."
    }

    /// `didNotFinish` for a restore from Archived (the implementation
    /// review's M-a): its zip is still in Archived, not in Backups.
    static func didNotFinishFromArchived(course: String) -> String {
        return "The restore of \(course) from Archived did not finish, so \(course) was left as it was. "
             + "Its archive is still in Archived, and you can restore it again."
    }

    static func newcomersKept(course: String, keptAt: String) -> String {
        return "Files made in \(course) while the restore was unfinished are in the folder \"\(keptAt)\" inside your working folder."
    }

    static func setAsideFilesKept(keptAt: String) -> String {
        return "A restore that did not finish had set some files aside. Nothing was deleted: they are in the "
             + "folder \"\(keptAt)\" inside your working folder."
    }

    static func anotherRestoreUnderWay(course: String) -> String {
        return "\(course) is being restored somewhere else right now, in another copy of Plantoir or on another "
             + "computer that uses this folder. Wait for that to finish, then restore."
    }

    /// The refusal for a record this computer wrote that nothing is
    /// restoring (the implementation review's M-d): a stop whose set-aside
    /// copy could not be moved, which the next opening tries again.
    static func anEarlierRestoreDidNotFinish(course: String) -> String {
        return "An earlier restore of \(course) did not finish, and the files it set aside could not be tidied away yet. "
             + "Quit Plantoir and open it again, then restore."
    }

    /// Said once per opening when another computer's restore of a course
    /// has not settled and the course has no settings here, so it is
    /// missing from the sidebar (the implementation review's I2). Which
    /// computer, and whether it is still at work, is not known here.
    static func unfinishedOnAnotherComputer(course: String) -> String {
        return "A restore of \(course) was started on another computer that uses this folder and, as far as this "
             + "computer can tell, has not finished. Until it does, \(course) does not show in the sidebar here, "
             + "and this computer moves none of its files. Opening Plantoir on the computer that started it lets it finish."
    }
}
