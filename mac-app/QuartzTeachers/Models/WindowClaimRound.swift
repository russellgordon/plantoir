import AppKit
import Foundation

/// One window's search for its remembered folder at launch: when it tries
/// its frame, and when it gives up to the next folder by order (#998).
///
/// Before #998 a window tried its frame every 150 ms, seven times, and gave
/// up after the seventh: about a second of spinner, and a wait whose length
/// was a guess. It now tries whenever its frame can have become the right
/// one, and gives up only when every window macOS restored has had its
/// chance:
///
/// - **It tries at hand-over, at every move or resize of its own window,
///   and when macOS says it has finished restoring windows.** Measured
///   (documentation 09, "When a restored window looks for its folder"): on
///   macOS 26.7.3 the restored frame is in place before the hand-over; on
///   macOS 15.7.7 the window is handed over WITH its restored frame, before
///   the restoration notification, and SwiftUI then moves and resizes it to
///   another frame. So the hand-over reading is the one that matches on 15,
///   and no single later reading would do on both.
/// - **It gives up when restoration has finished, one pass of the main actor
///   after that moment** (a task enqueued then), never on a clock. Every
///   restored window has been handed over by then: on 26 all of them in the
///   pass the give-up is enqueued behind, on 15 before the notification.
/// - **It never takes, by order, an entry remembered at another open
///   window's frame.** That entry belongs to the other window, which may be
///   handed over in a later pass (`WindowFolderMemory.claimNextEntry
///   (skippingFrames:)`). So a window whose frame matches nothing cannot
///   take a sibling's folder whatever order the two arrive in, and when only
///   such entries are left it shows the picker.
///
/// The round is over once the window claims, gives up, or has already
/// settled its folder; its observers go with it. A window opened after
/// claims have closed (`WindowFolderMemory.claimsOpenUntil`) finds nothing
/// to claim and settles at the give-up.
@MainActor
final class WindowClaimRound {

    // MARK: - Stored properties

    let claimant: WindowFolderClaimant
    let frame: () -> String
    let windowHasSettled: () -> Bool
    let otherWindowFrames: () -> [String]
    let restoration: LaunchRestoration
    let adopt: (WindowFolderMemory.Entry, String) -> Void
    let settleWithNoEntry: () -> Void

    /// True once the window has claimed, given up or turned out settled.
    private(set) var isOver: Bool = false

    private var giveUpIsQueued: Bool = false

    private var observers: [NSObjectProtocol] = []

    // MARK: - Initializer

    /// - Parameters:
    ///   - claimant: this window's claim.
    ///   - frame: reads the window's frame, as `NSStringFromRect` writes it.
    ///   - windowHasSettled: reads whether its folder is already decided.
    ///   - otherWindowFrames: reads every other open window's frame.
    ///   - restoration: the launch's restoration record.
    ///   - adopt: takes an entry, with the words for the trail of how.
    ///   - settleWithNoEntry: nothing was claimed; the window shows the
    ///     picker or its own folder.
    init(
        claimant: WindowFolderClaimant,
        frame: @escaping () -> String,
        windowHasSettled: @escaping () -> Bool,
        otherWindowFrames: @escaping () -> [String],
        restoration: LaunchRestoration = LaunchRestoration.shared,
        adopt: @escaping (WindowFolderMemory.Entry, String) -> Void,
        settleWithNoEntry: @escaping () -> Void
    ) {
        self.claimant = claimant
        self.frame = frame
        self.windowHasSettled = windowHasSettled
        self.otherWindowFrames = otherWindowFrames
        self.restoration = restoration
        self.adopt = adopt
        self.settleWithNoEntry = settleWithNoEntry
    }

    // MARK: - Functions

    /// Starts the round at hand-over. `window` is watched for moves and
    /// resizes; nil watches nothing (tests call `frameChanged` themselves).
    ///
    /// The round keeps itself alive until it is over: its observers and the
    /// restoration record hold it, and let go when it ends.
    func begin(watching window: NSWindow?) {
        tryTheFrame()
        if isOver {
            return
        }
        if let window {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                let observer: NSObjectProtocol = NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: nil
                ) { _ in
                    // Posted by AppKit on the main thread, as the window moves.
                    MainActor.assumeIsolated {
                        self.frameChanged()
                    }
                }
                observers.append(observer)
            }
        }
        restoration.whenFinished {
            self.restorationFinished()
        }
    }

    /// The window moved or was resized.
    func frameChanged() {
        tryTheFrame()
    }

    /// macOS has finished restoring windows: one more reading, then the
    /// give-up, one pass of the main actor later.
    func restorationFinished() {
        tryTheFrame()
        if isOver || giveUpIsQueued {
            return
        }
        giveUpIsQueued = true
        Task { @MainActor in
            self.giveUp()
        }
    }

    private func tryTheFrame() {
        if isOver {
            return
        }
        if windowHasSettled() {
            _ = claimant.giveUp(windowHasSettled: true)
            end()
            return
        }
        if let entry = claimant.frameDidSettle(frame(), windowHasSettled: false) {
            end()
            adopt(entry, "matched by frame")
        }
    }

    private func giveUp() {
        tryTheFrame()
        if isOver {
            return
        }
        end()
        if let entry = claimant.giveUp(windowHasSettled: false, reservedFrames: otherWindowFrames()) {
            adopt(entry, "fell back to order")
            return
        }
        // No remembered window for this one: macOS brought back a window
        // whose folder was not recorded, the entries left belong to other
        // windows, or claims have closed (a window opened mid-session). The
        // picker is the honest screen; it does NOT inherit a sibling's folder.
        settleWithNoEntry()
    }

    private func end() {
        isOver = true
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }
}
