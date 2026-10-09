import Foundation

/// The title of the alert a backup, restore or deletion problem is shown in:
/// it names the act that failed (#457, the HIG sweep). Until then every one
/// of them was titled "Could not do that", which names nothing on the day a
/// teacher most needs to know what went wrong.
enum BackupProblemTitle {

    // MARK: - Stored properties

    /// Only for a problem no act has named — never expected to show.
    static let generic: String = "Could not do that"

    static let deletingArchive: String = "Could not delete the archive"

    // MARK: - Functions

    static func backingUp(_ courseCode: String) -> String {
        return "Could not back up \(courseCode)"
    }

    static func restoring(_ courseCode: String) -> String {
        return "Could not restore \(courseCode)"
    }

    static func deletingBackups(count: Int) -> String {
        if count == 1 {
            return "Could not delete the backup"
        }
        return "Could not delete the backups"
    }
}
