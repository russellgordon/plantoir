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

    /// Whether a quit is going ahead (U4b2-7 review 1, M1), observable so
    /// every rename sheet greys its Rename the moment it is set.
    static let closing: Closing = Closing()

    // MARK: - Computed properties

    /// Whether a quit is going ahead: set in the same main-actor turn as the
    /// quit decides (`AppDelegate.quitWaitsAfterHaltingWhatOnlyPlans`), after
    /// the work-under-way question, so a quit called off never sets it; no
    /// quit that has gone ahead is called off afterwards. From then on no
    /// rename may start and none may begin its swap, so the quit's wait,
    /// which counts only swaps already begun, can never miss one.
    static var quitIsGoingAhead: Bool {
        get {
            return closing.quitIsGoingAhead
        }
        set {
            closing.quitIsGoingAhead = newValue
        }
    }

    /// Whether Rename may be pressed: nothing is running, and no quit is
    /// going ahead. The sheet's Rename is disabled, visibly, whenever this
    /// is false, and `start` refuses then too.
    var canStart: Bool {
        return !isRenaming && !FolderRenameRun.quitIsGoingAhead
    }

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
        if !canStart {
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

    /// The one place a rename passes from planning to swapping
    /// (`CourseSettingsView.renameFolder`): refused, with nothing marked,
    /// once a quit is going ahead (review 1, M1), or when the claim is no
    /// longer held. Called on the main actor in the same turn as the
    /// rename's own cancellation check, so the quit lands either before it
    /// (refused) or after it (the swap has begun and is waited for).
    static func swapBegins(_ claim: CourseActivity.FolderRenameRecord) -> Bool {
        if quitIsGoingAhead {
            return false
        }
        return CourseActivity.folderRenameSwapBegins(claim)
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

extension FolderRenameRun {

    /// The quit's latch, in an observable object of its own, since a static
    /// stored property is not observed.
    @MainActor
    @Observable
    final class Closing {

        // MARK: - Stored properties

        var quitIsGoingAhead: Bool = false
    }
}

/// The renames a Course Settings page owns (#899 U4b2-8, review 1's M1):
/// one run for each folder list that can rename. Kept by the page, never by
/// a list or a row, because the page is what owns them going away: a list
/// in the page's grouped `Form` is drawn lazily, and a row leaving the
/// visible area (the window made shorter, the form scrolled) is not the
/// teacher leaving the rename. When the page itself goes (Settings left for
/// Planning, the course closed or switched, the window closed), every
/// rename still only planning is halted through the one rule,
/// `FolderRenameRun.haltIfStillPlanning`; one whose swap has begun is left
/// to finish.
@MainActor
@Observable
final class CourseSettingsRenames {

    // MARK: - Stored properties

    /// The shared folders list's rename.
    let sharedFolders: FolderRenameRun = FolderRenameRun()

    /// The per-section folders list's rename.
    let perSectionFolders: FolderRenameRun = FolderRenameRun()

    // MARK: - Functions

    /// The page is going away: halts each of its renames that is still
    /// only planning.
    func pageIsGoingAway() {
        sharedFolders.haltIfStillPlanning()
        perSectionFolders.haltIfStillPlanning()
    }
}
