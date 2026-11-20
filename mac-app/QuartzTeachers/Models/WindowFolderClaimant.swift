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

    /// Offers the window's frame; claims the matching entry when there is
    /// one. Called once, when the frame is final (`WindowClaimRound`).
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
    ///
    /// `reservedFrames`: the frames other open windows have now. An entry
    /// remembered at one of them belongs to that window, which may not have
    /// looked yet, so it is never taken by order (#998).
    func giveUp(windowHasSettled: Bool = false, reservedFrames: [String] = []) -> WindowFolderMemory.Entry? {
        if windowHasSettled {
            isDone = true
            return nil
        }
        if isDone {
            return nil
        }
        isDone = true
        if let entry = WindowFolderMemory.claimNextEntry(skippingFrames: reservedFrames) {
            claimed = entry
            return entry
        }
        return nil
    }
}

