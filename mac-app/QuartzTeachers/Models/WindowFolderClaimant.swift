import Foundation

/// One window's pursuit of its remembered folder.
///
/// A reopened window that lost its value tries to find its folder by frame
/// while the frame settles, and falls back to order only when told to give
/// up. Each window claims at most once — the discipline that keeps two
/// windows from taking the same entry, or one window from taking two.
@MainActor
final class WindowFolderClaimant {

    // MARK: - Stored properties

    /// What this window claimed, once it has.
    private(set) var claimed: WindowFolderMemory.Entry?

    /// True once this window has claimed or given up.
    private var isDone: Bool = false

    // MARK: - Functions

    /// Offers the window's current frame; claims the matching entry when
    /// there is one. The frame settles a moment after the window exists,
    /// so this is called repeatedly until it matches or time runs out.
    ///
    /// `windowHasSettled`: the window's folder is already decided (reopened,
    /// requested, left to the picker). Such a window never claims — one
    /// decision per window (#311 review B1) — and leaves the entry for the
    /// window it belongs to.
    func frameDidSettle(_ frame: String, windowHasSettled: Bool = false) -> WindowFolderMemory.Entry? {
        if windowHasSettled {
            isDone = true
            return nil
        }
        if isDone {
            return nil
        }
        if let entry = WindowFolderMemory.claimEntry(matchingFrame: frame) {
            isDone = true
            claimed = entry
            return entry
        }
        return nil
    }

    /// The frame never matched: take the next entry by order — the path
    /// for launches where no frames were restored at all.
    func giveUp(windowHasSettled: Bool = false) -> WindowFolderMemory.Entry? {
        if windowHasSettled {
            isDone = true
            return nil
        }
        if isDone {
            return nil
        }
        isDone = true
        if let entry = WindowFolderMemory.claimNextEntry() {
            claimed = entry
            return entry
        }
        return nil
    }
}
