import Foundation
import Observation

/// One Rename folder started from a rename sheet (#899 U4b2-7): the task it
/// runs in, and the one rule for halting it. Until a rename's swap begins it
/// has written nothing, so nothing waits for it: Cancel, the sheet going
/// away, and a quit each end a rename that is only planning at once, through
/// `haltIfStillPlanning`, and the course is given back. A rename whose swap
/// has begun is never halted; a quit waits for it.
///
/// The sheet's view calls this and keeps only the calls: a view's `@State`
/// cannot be driven from a unit test, so the chain from the sheet's Cancel
/// to the plan is tested here (U4b part eight's review, L1).
@MainActor
@Observable
final class FolderRenameRun {

    // MARK: - Stored properties

    /// True from the press of Rename until the rename's task has ended.
    var isRenaming: Bool = false

    /// The rename's task, so that halting it cancels the very task its
    /// plan is awaited in. Nil once it has been halted or has ended.
    @ObservationIgnored var renameTask: Task<Void, Never>? = nil

    /// Whether the rename under way has begun its check and swap. Nil:
    /// it can never be halted.
    @ObservationIgnored var canNoLongerBeHalted: (() -> Bool)? = nil

    /// Every rename started from a sheet whose task has not yet ended, in
    /// any window: what a quit halts when they are only planning.
    static var runsUnderWay: [FolderRenameRun] = []

    // MARK: - Computed properties

    /// Whether halting now would leave nothing part way: no rename is
    /// running, or the one running is still only planning.
    var canBeHalted: Bool {
        if !isRenaming {
            return true
        }
        let swapHasBegun: Bool = canNoLongerBeHalted?() ?? true
        return !swapHasBegun
    }

    // MARK: - Functions

    /// Starts the rename. `onRename` is awaited inside this run's own task,
    /// never in a fresh one, so that halting the run reaches the plan.
    /// `whenFinished` hears the result of a rename that was not halted.
    func start(
        renaming oldName: String,
        to newName: String,
        using onRename: @escaping (_ oldName: String, _ newName: String) async -> RenameResult,
        canNoLongerBeHalted: (() -> Bool)?,
        whenFinished: @escaping @MainActor (_ result: RenameResult) -> Void
    ) {
        if isRenaming {
            return
        }
        isRenaming = true
        self.canNoLongerBeHalted = canNoLongerBeHalted
        FolderRenameRun.runsUnderWay.append(self)
        renameTask = Task { @MainActor in
            let result: RenameResult = await onRename(oldName, newName)
            isRenaming = false
            FolderRenameRun.forget(self)
            if Task.isCancelled {
                // Halted while it planned: the sheet is gone, and nothing
                // was changed.
                return
            }
            whenFinished(result)
        }
    }

    /// Cancels the rename if it is still only planning: its plan stops and
    /// the course is given back at once (U4b part seven's review, M1).
    /// Never once its check and swap have begun. Returns whether it could
    /// be halted (true too when nothing was running), so the sheet knows
    /// whether it may close. Cancel, the sheet going away and a quit all
    /// come here.
    @discardableResult
    func haltIfStillPlanning() -> Bool {
        if !canBeHalted {
            return false
        }
        renameTask?.cancel()
        renameTask = nil
        return true
    }

    /// A quit going ahead (#899 U4b2-7): every rename that is only planning
    /// is halted, the same way Cancel halts it; one whose swap has begun is
    /// left to finish, and the quit waits for it.
    static func haltEveryRunStillPlanning() {
        let runs: [FolderRenameRun] = runsUnderWay
        for run in runs {
            run.haltIfStillPlanning()
        }
    }

    /// Takes an ended run out of `runsUnderWay`.
    private static func forget(_ ended: FolderRenameRun) {
        var remaining: [FolderRenameRun] = []
        for run in runsUnderWay {
            if run !== ended {
                remaining.append(run)
            }
        }
        runsUnderWay = remaining
    }
}
