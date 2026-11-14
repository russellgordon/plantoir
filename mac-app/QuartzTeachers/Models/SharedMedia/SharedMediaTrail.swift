import Foundation

/// The trail's words for the shared Media store (#785). Counts, sizes and
/// backup FILE names only: a backup's name is a course code, a moment and
/// who made it, while a picture's name is the teacher's own and can carry a
/// student's (#785 plan review, amendment 5), so no Media path is ever
/// written here.
extension ActivityTrail {

    // MARK: - Functions

    /// "ICS3U · saved ICS3U_backup_…_shared-media.zip, keeping its Media
    /// files once: 118 already kept, 2 added (4.1 MB)".
    nonisolated static func backupKeptItsMediaOnceLine(
        course: String,
        backupFileName: String,
        alreadyKept: Int,
        added: Int,
        bytesAdded: Int64
    ) -> String {
        let size: String = ByteCountFormatter.string(fromByteCount: bytesAdded, countStyle: .file)
        return "\(course) · saved \(backupFileName), keeping its Media files once: "
            + "\(alreadyKept) already kept, \(added) added (\(size))"
    }

    /// What a sweep did, or why it kept everything.
    nonisolated static func sharedMediaSweptLine(_ result: SharedMediaStore.SweepResult) -> String {
        if let why = result.keptEverything {
            return "kept every file in the backups' shared Media: " + sharedMediaKeptWords(why)
        }
        let size: String = ByteCountFormatter.string(fromByteCount: result.bytesFreed, countStyle: .file)
        let files: String = result.filesDeleted == 1 ? "1 file" : "\(result.filesDeleted) files"
        let lists: String = result.listsRemoved == 1 ? "1 list" : "\(result.listsRemoved) lists"
        return "removed \(files) no backup needs from the backups' shared Media (\(size)), "
            + "and \(lists) that kept nothing any more"
    }

    nonisolated static func sharedMediaKeptWords(_ why: SharedMediaSweepRule.KeptEverything) -> String {
        switch why {
        case .aBackupCouldNotBeRead(let name):
            return "the list in \(name) could not be read"
        case .aListCouldNotBeRead(let name):
            return "\(name) could not be read"
        case .theStoreIsBusy:
            return "a backup or a restore was using it"
        case .theStoreCouldNotBeRead(let what):
            return "\(what) could not be read"
        }
    }

    /// "ICS3U · restoring ICS3U_backup_…_shared-media.zip: 2 of 120 Media
    /// files could not be found". The count, never which.
    nonisolated static func backupMediaNotFoundLine(
        course: String,
        backupFileName: String,
        missing: Int,
        listed: Int
    ) -> String {
        return "\(course) · restoring \(backupFileName): \(missing) of \(listed) Media files "
            + "could not be found in the backups' shared Media or in the course"
    }
}
