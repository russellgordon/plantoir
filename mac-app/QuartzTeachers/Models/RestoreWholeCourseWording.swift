import Foundation

/// Every sentence a whole-course restore says (#909), as
/// `contracts/course-management.json` → `backups.restoreWholeCourse.wording`
/// holds them, so Windows shows the same words. Pinned by
/// `RestoreWholeCourseContractTests`.
nonisolated enum RestoreWholeCourseWording {

    // MARK: - Stored properties

    static let didNotFinishTitle: String = "A restore did not finish"

    // MARK: - Functions

    static func leftAsItWas(course: String, reason: String) -> String {
        return "\(course) was left as it was, because the restore could not finish: \(reason)"
    }

    /// A move refused for a lock or a permission at the top of the course
    /// (Russell's held question M13: nothing changes and the item is named).
    /// On the mac the Finder's way to unlock it follows
    /// (`unlockInTheFinder`); Windows says `leftAsItWasInUse` for a file
    /// another program holds open, which the mac never meets.
    static func leftAsItWasLocked(course: String, name: String) -> String {
        return "\(course) was left as it was, because \"\(name)\" in it is locked or cannot be changed. "
             + "Unlock it, then restore again."
    }

    static let unlockInTheFinder: String =
        "In the Finder, select it, choose File ▸ Get Info, and untick Locked, or give yourself Read & Write under Sharing & Permissions."

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

    static func didNotFinish(course: String) -> String {
        return "The restore of \(course) from a backup did not finish, so \(course) was left as it was. "
             + "The backup is still in Backups, and you can restore it again."
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
}
