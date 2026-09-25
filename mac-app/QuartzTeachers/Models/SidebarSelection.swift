import Foundation

/// What is currently selected in the sidebar: a whole course (settings view)
/// or one section of a course (preview/deploy view).
enum SidebarSelection: Hashable {
    case course(String)
    case section(String, Int)
    /// An archived course or section, identified by its archive.
    case archived(String)
    /// A saved backup of a course, identified by its zip.
    case backup(String)
    /// Every backup at once, with what they take and a way to delete several
    /// (issue #242).
    case allBackups
}

// MARK: - Storage form

extension SidebarSelection {

    /// A plain-string form for the per-window memory. Course codes never
    /// contain "|", so the pieces join safely.
    var storageValue: String {
        switch self {
        case .course(let code):
            return "course|\(code)"
        case .section(let code, let number):
            return "section|\(code)|\(number)"
        case .archived(let identifier):
            return "archived|\(identifier)"
        case .backup(let identifier):
            return "backup|\(identifier)"
        case .allBackups:
            return "allBackups"
        }
    }

    /// The selection a stored string names, or nil for anything
    /// unrecognized — including the empty string old entries carry.
    static func fromStorageValue(_ stored: String) -> SidebarSelection? {
        let pieces: [String] = stored.components(separatedBy: "|")
        switch pieces.first {
        case "course" where pieces.count == 2:
            return .course(pieces[1])
        case "section" where pieces.count == 3:
            if let number = Int(pieces[2]) {
                return .section(pieces[1], number)
            }
            return nil
        case "archived" where pieces.count == 2:
            return .archived(pieces[1])
        case "backup" where pieces.count == 2:
            return .backup(pieces[1])
        case "allBackups" where pieces.count == 1:
            return .allBackups
        default:
            return nil
        }
    }
}
