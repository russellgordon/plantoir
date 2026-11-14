import Foundation

/// A working folder's own identifier: `courses/.internal/folder-id`, one
/// UUID, made the first time either app or an outside-assistant process
/// records a step in the folder (plan 4.1).
///
/// Needed because the folder's other name is a hash of its PATH
/// (`BuildOutputLocation.folderIdentifier`), and a step has to know its
/// folder again after the folder moves, or tell it apart from a different
/// folder now at the same path. Inside the folder, so it travels with it,
/// including to the other computer on a synced folder (where that computer's
/// own list then sees this one's changes as hand edits, and the content
/// checks refuse over them).
///
/// Made exclusively (`UndoIdentifierFile.readOrCreate`): two processes
/// making it at once agree on one. Not a step, and never undone.
nonisolated enum FolderIdentityFile {

    // MARK: - Functions

    static func fileURL(forWorkingFolder root: URL) -> URL {
        return root
            .appendingPathComponent("courses", isDirectory: true)
            .appendingPathComponent(".internal", isDirectory: true)
            .appendingPathComponent("folder-id")
    }

    /// The folder's identifier, made now if it has none.
    static func identifier(forWorkingFolder root: URL) throws -> String {
        return try UndoIdentifierFile.readOrCreate(at: fileURL(forWorkingFolder: root))
    }

    /// The folder's identifier, or nil when it has none yet. Never makes one.
    static func existingIdentifier(forWorkingFolder root: URL) -> String? {
        return UndoIdentifierFile.read(at: fileURL(forWorkingFolder: root))
    }
}

/// Whether a step's working folder can be reached, and where it is.
///
/// U1 knows one place to look: the path the step was made at, accepted only
/// when the folder there carries the step's identifier. Open Recent (and on
/// Windows its recent list) is the second place, added with the menu in U7.
/// A folder that cannot be reached is nil, and Undo waits for it.
nonisolated enum UndoReach {

    // MARK: - Functions

    @Sendable static func root(for folder: UndoWorkingFolder) -> URL? {
        let candidate: URL = URL(fileURLWithPath: folder.pathAtTheTime, isDirectory: true)
        guard let found = FolderIdentityFile.existingIdentifier(forWorkingFolder: candidate) else {
            return nil
        }
        if found != folder.id {
            return nil
        }
        return candidate
    }
}
