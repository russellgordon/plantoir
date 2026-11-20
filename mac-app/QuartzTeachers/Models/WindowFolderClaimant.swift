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

/// When a window tries its frame, and when it gives up and takes the next
/// remembered folder by order (#998).
///
/// Before #998 a window tried its frame every 150 ms, seven times, and gave
/// up after the seventh: about a second during which a restored window
/// showed its quiet spinner rather than its folder, and a wait whose length
/// was a guess. What the wait was for is two things, and this waits for
/// those instead:
///
/// - **The frame is final.** macOS restores every frame before it says it
///   has finished restoring windows (`LaunchRestoration`, measured), so the
///   frame is tried once, at that moment or at once when it has passed.
/// - **Every sibling has tried its own frame first.** A window whose frame
///   matches nothing must not take the next entry by order while a sibling
///   whose frame matches that very entry has not yet looked, or the two
///   windows swap folders. Every window restored at launch is handed over in
///   the same pass of the main actor (measured), so the give-up is enqueued
///   on the main actor after that pass, never timed.
///
/// A window that has already settled its folder never claims, now or when
/// the give-up comes round (#311 review B1).
@MainActor
enum WindowClaimRound {

    // MARK: - Functions

    /// - Parameters:
    ///   - claimant: this window's claim.
    ///   - frame: reads the window's frame, as `NSStringFromRect` writes it.
    ///   - windowHasSettled: reads whether its folder is already decided.
    ///   - restoration: the launch's restoration record.
    ///   - adopt: takes an entry, with the words for the trail of how.
    ///   - settleWithNoEntry: nothing was claimed; the window shows the
    ///     picker or its own folder.
    static func begin(
        claimant: WindowFolderClaimant,
        frame: @escaping () -> String,
        windowHasSettled: @escaping () -> Bool,
        restoration: LaunchRestoration = LaunchRestoration.shared,
        adopt: @escaping (WindowFolderMemory.Entry, String) -> Void,
        settleWithNoEntry: @escaping () -> Void
    ) {
        if windowHasSettled() {
            _ = claimant.giveUp(windowHasSettled: true)
            return
        }
        restoration.whenFinished {
            if let entry = claimant.frameDidSettle(frame(), windowHasSettled: windowHasSettled()) {
                adopt(entry, "matched by frame")
                return
            }
            if windowHasSettled() {
                return
            }
            Task { @MainActor in
                WindowClaimRound.giveUp(
                    claimant: claimant,
                    windowHasSettled: windowHasSettled(),
                    adopt: adopt,
                    settleWithNoEntry: settleWithNoEntry
                )
            }
        }
    }

    /// The frame matched nothing and every sibling has looked: the next
    /// entry by order, or none.
    static func giveUp(
        claimant: WindowFolderClaimant,
        windowHasSettled: Bool,
        adopt: (WindowFolderMemory.Entry, String) -> Void,
        settleWithNoEntry: () -> Void
    ) {
        if windowHasSettled {
            _ = claimant.giveUp(windowHasSettled: true)
            return
        }
        if let entry = claimant.giveUp(windowHasSettled: false) {
            adopt(entry, "fell back to order")
            return
        }
        // No remembered window for this one: macOS brought back a window
        // whose folder was not recorded, or claims have closed (a window
        // opened mid-session). The picker is the honest screen; it does NOT
        // inherit a sibling's folder.
        settleWithNoEntry()
    }
}
