import Foundation

/// The note about a reference course's locked pages, asked for before
/// Obsidian opens: the course, and the folder Obsidian reveals once the note
/// is answered (the section's own when asked from a section).
struct LockedPagesNoteRequest: Identifiable {

    // MARK: - Stored properties

    let course: Course
    let folder: URL

    // MARK: - Computed properties

    var id: String {
        return course.code + "|" + folder.path
    }
}

extension WorkspaceModel {

    // MARK: - Functions

    /// Open in Obsidian — the ONE function every route calls: the section
    /// window's toolbar button, Course Settings' toolbar button, a row's
    /// context menu, and Course ▸ / Section ▸ Open in Obsidian (#457).
    ///
    /// On a course kept for reference it locks the pages again first (a
    /// folder back from another Mac or a backup is not locked until somebody
    /// asks) and, the first time, asks for the calm note BEFORE Obsidian
    /// opens rather than after the teacher has typed. Until the HIG sweep the
    /// toolbar called `FolderActions.openInObsidian` directly and skipped
    /// both — one command, two behaviours (deferred from batch A).
    ///
    /// Returns whether Obsidian was opened now; `false` means the note is
    /// waiting in `lockedPagesNoteRequest`. `lockAgain` is replaced only by a
    /// test, whose temporary course must stay deletable.
    @discardableResult
    func openInObsidian(
        course: Course,
        sectionNumber: Int?,
        lockAgain: @MainActor (Course) -> Void = ReferenceLock.ensureLockedInBackground
    ) -> Bool {
        let folder: URL = FolderActions.obsidianFolder(for: course, sectionNumber: sectionNumber)
        if course.isKeptForReference {
            lockAgain(course)
            if !LockedPagesNote.hasBeenShown(courseCode: course.code) {
                lockedPagesNoteRequest = LockedPagesNoteRequest(course: course, folder: folder)
                return false
            }
        }
        FolderActions.openInObsidian(revealing: folder, vaultURL: course.directoryURL)
        return true
    }

    /// The note was answered "Open in Obsidian": remember it was shown, and
    /// open the folder it was asked for.
    func openInObsidianAfterTheNote(_ request: LockedPagesNoteRequest) {
        LockedPagesNote.remember(courseCode: request.course.code)
        lockedPagesNoteRequest = nil
        FolderActions.openInObsidian(revealing: request.folder, vaultURL: request.course.directoryURL)
    }
}
