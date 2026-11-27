import Foundation

/// A restore that replaces files of a course sets aside every Undo step
/// left in flight that names one of them (#899, the director's decisions
/// of 2026-11-27, ahead of U5, which makes a restore itself a step).
///
/// Without it a step that stopped part way (Get Ready for the Start of the
/// Year, say) stays in flight over a course that now holds the backup, and
/// the next recovery judges the RESTORED files against it: after a second
/// Get Ready it closed the old step as made (two on the list for one
/// change), or put back part of the second run's files.
///
/// When: only once the restore has actually replaced the files (every move
/// made, or stopped part way with some moved and not put back), inside the
/// list's lock held across the swap (`swapHoldingTheList`). A restore that
/// fails before its first move, or puts every file back, leaves each step
/// exactly as it was, in flight, so recovery and the Get Ready offer work
/// as before (the review of 2026-11-27, M1).
///
/// What: per FILE (the director's ruling on M2). The step's files the
/// restore replaced are set aside, never judged or written by recovery;
/// its other files stay in the step and are judged by content as before.
/// A step whose every file is set aside is closed `interrupted`, reason
/// `setAsideByARestore`, with every file it names and NO clearing, as
/// pruning closes a step it can never settle: partly applied or unknown,
/// off the list, which is true of a course holding the backup (files the
/// step never recorded) and of one stopped part way (some backup's, some
/// its own). A step with files left to judge gets a `filesReplacedByARestore` line and
/// stays in flight; recovery then judges only the rest, and closes it
/// `interrupted` with the files set aside rather than putting it on the
/// list, since what an Undo would act on was replaced. The earlier steps of
/// the course are left on the list, as a restore has always left them: an
/// Undo of one checks its files by content and refuses (and clears) when
/// the restore changed them (`undo.rule.clearing`). No clearing is
/// written, because it would take every other course's steps.
nonisolated enum UndoRestoreSetAside {

    // MARK: - Stored properties

    /// The reason word on the closing line (`file-formats.json` →
    /// `undoJournal.lineKeys.reason`).
    static let reason: String = "setAsideByARestore"

    // MARK: - Functions

    /// Whether `path` (inside the working folder) is `replaced` or inside it.
    static func isInside(_ path: String, _ replaced: String) -> Bool {
        if path == replaced {
            return true
        }
        return path.hasPrefix(replaced + "/")
    }

    /// The step's files, each once, in the order its ops name them.
    static func pathsNamed(by step: UndoStep) -> [String] {
        var paths: [String] = []
        for op in step.ops {
            for path in op.pathsNamed where !paths.contains(path) {
                paths.append(path)
            }
        }
        return paths
    }

    /// Whether `path` is inside any of `replaced`.
    static func isInsideAny(_ path: String, _ replaced: [String]) -> Bool {
        for place in replaced where isInside(path, place) {
            return true
        }
        return false
    }

    /// The step's ops that touch what the restore replaced: an op is
    /// inside when any file it names is under one of `replaced` (a move
    /// from inside to outside is inside: its one place was replaced).
    static func pathsInside(_ step: UndoStep, replaced: [String]) -> (inside: [String], outside: [String]) {
        var inside: [String] = []
        var outside: [String] = []
        for op in step.ops {
            var opIsInside: Bool = false
            for path in op.pathsNamed where isInsideAny(path, replaced) {
                opIsInside = true
            }
            for path in op.pathsNamed {
                if opIsInside {
                    if !inside.contains(path) {
                        inside.append(path)
                    }
                } else if !outside.contains(path) {
                    outside.append(path)
                }
            }
        }
        var outsideOnly: [String] = []
        for path in outside where !inside.contains(path) {
            outsideOnly.append(path)
        }
        return (inside: inside, outside: outsideOnly)
    }

    /// Whether the step was made in this working folder (by its identifier).
    static func isMade(_ step: UndoStep, inWorkingFolder workingFolderID: String) -> Bool {
        guard let folder = step.workingFolder else {
            return false
        }
        return folder.id.lowercased() == workingFolderID.lowercased()
    }

    /// The step without the ops that name a file set aside: what recovery
    /// judges, and the only files it may write (`filesReplacedByARestore` lines, #899).
    static func stepWithout(_ setAside: [String], _ step: UndoStep) -> UndoStep {
        var kept: [UndoOp] = []
        for op in step.ops {
            var namesOneSetAside: Bool = false
            for path in op.pathsNamed where setAside.contains(path) {
                namesOneSetAside = true
            }
            if !namesOneSetAside {
                kept.append(op)
            }
        }
        var reduced: UndoStep = step
        reduced.ops = kept
        return reduced
    }

    /// Thrown when the list's lock cannot be had: the restore does not
    /// start, and nothing has moved (review 2, L3).
    struct TheListIsBusy: Error, Equatable {}

    /// Runs the restore's `swap` holding the list's lock, and once it says
    /// the restore has replaced files (every move made, or stopped part
    /// way with some moved and not all put back), sets aside every step in
    /// flight whose files are among them, in the same lock, so no recovery
    /// can judge between the swap and the set-aside and no step can begin
    /// in between (the review of 2026-11-27, M1 and L1). A swap that moved
    /// nothing, or put every file back, sets nothing aside: each step stays
    /// in flight as recovery would have found it. A lock still held by
    /// another process after `finishWaitSeconds` stops the restore before
    /// it starts (`TheListIsBusy`), never a swap with no set-aside (review
    /// 2, L3). A list that cannot be read or written at all never stops the
    /// restore, which is how a teacher gets a course back: the swap runs,
    /// and when it replaced files the trail says any change left part way
    /// is still open. Returns the numbers of the steps it set aside.
    @discardableResult
    static func swapHoldingTheList(
        inside replaced: [String],
        workingFolderRoot: URL,
        course: String,
        journal: UndoJournal,
        mode: UndoMode = UndoSwitch.currentMode,
        _ swap: () -> Bool
    ) throws -> [Int] {
        guard let workingFolderID = FolderIdentityFile.existingIdentifier(forWorkingFolder: workingFolderRoot) else {
            // A folder with no identifier has never had a step made in it.
            _ = swap()
            return []
        }
        var swapRan: Bool = false
        var replacedFiles: Bool = false
        var setAside: [Int] = []
        do {
            try journal.withLock(waitingAtMost: UndoSwitch.finishWaitSeconds, inShadow: mode == .shadow) { writer in
                swapRan = true
                replacedFiles = swap()
                if replacedFiles {
                    setAside = try setAsideSteps(
                        inside: replaced, workingFolderID: workingFolderID, root: workingFolderRoot,
                        course: course, mode: mode, writer: writer
                    )
                }
            }
        } catch UndoJournalError.lockBusy where !swapRan {
            throw TheListIsBusy()
        } catch {
            if !swapRan {
                replacedFiles = swap()
            }
            if replacedFiles {
                UndoTrailHook.setAsideByARestoreLine?(course, nil, .begin, 0, 0, false)
            }
        }
        return setAside
    }

    /// The settle that finishes a restore found `done` at a later reading
    /// (`RestoreSettle`, `.finish`): the restore died after its commit and
    /// before its set-aside line, so the steps in flight in the course are
    /// set aside now, inside the list's lock, before recovery can judge
    /// them (review 2, L2). Idempotent: a step already set aside has no
    /// file newly inside. A settle that puts the course back sets nothing
    /// aside. A list that cannot be had is said on the trail.
    static func setAsideAfterASettledRestore(
        course: String,
        coursesDirectoryURL: URL,
        journal: UndoJournal = UndoJournalLocation.standardJournal(),
        mode: UndoMode = UndoSwitch.currentMode
    ) {
        let root: URL = coursesDirectoryURL.deletingLastPathComponent()
        guard let workingFolderID = FolderIdentityFile.existingIdentifier(forWorkingFolder: root) else {
            return
        }
        do {
            try journal.withLock(waitingAtMost: UndoSwitch.finishWaitSeconds, inShadow: mode == .shadow) { writer in
                _ = try setAsideSteps(
                    inside: ["courses/" + course], workingFolderID: workingFolderID, root: root,
                    course: course, mode: mode, writer: writer
                )
            }
        } catch {
            UndoTrailHook.setAsideByARestoreLine?(course, nil, .begin, 0, 0, false)
        }
    }

    /// Inside the lock: for each step in flight in this working folder that
    /// names a file the restore replaced, those files are set aside. When
    /// that is every file it names (or every one not set aside already),
    /// the step is closed `interrupted`, reason `setAsideByARestore`, with
    /// every file it names, and no clearing (as pruning closes a step it
    /// can never settle). Otherwise a `filesReplacedByARestore` line names the files set
    /// aside, and the step stays in flight for its other files, which
    /// recovery judges as before; it never writes into, or judges the step
    /// by, a file set aside (the director's ruling on M2). Its staged files
    /// beside the files set aside are tidied (live only), keeping any kept
    /// original that is the only copy.
    static func setAsideSteps(
        inside replaced: [String],
        workingFolderID: String,
        root: URL,
        course: String,
        mode: UndoMode,
        writer: UndoJournalWriter
    ) throws -> [Int] {
        var touched: [Int] = []
        for record in writer.fold.inFlight {
            if !isMade(record.step, inWorkingFolder: workingFolderID) {
                continue
            }
            guard let ended = UndoRecovery.endedPhase(of: record) else {
                continue
            }
            let split: (inside: [String], outside: [String]) = pathsInside(record.step, replaced: replaced)
            var newlyInside: [String] = []
            for path in split.inside where !record.setAsidePaths.contains(path) {
                newlyInside.append(path)
            }
            if newlyInside.isEmpty {
                continue
            }
            var stillJudged: [String] = []
            for path in split.outside where !record.setAsidePaths.contains(path) {
                stillJudged.append(path)
            }
            let paths: [String] = pathsNamed(by: record.step)
            if stillJudged.isEmpty {
                try writer.append(
                    UndoEventLine(seq: record.step.seq, event: .interrupted, phase: ended, reason: reason, paths: paths)
                )
            } else {
                try writer.append(
                    UndoEventLine(seq: record.step.seq, event: .filesReplacedByARestore, reason: reason, paths: newlyInside)
                )
            }
            touched.append(record.step.seq)
            if mode == .live {
                // The ops set aside now: none naming a file still judged
                // or one an earlier restore set aside.
                var notNow: [String] = stillJudged
                for path in record.setAsidePaths where !notNow.contains(path) {
                    notNow.append(path)
                }
                let theOpsSetAside: UndoStep = stepWithout(notNow, record.step)
                _ = UndoRecovery.tidyStagedFiles(of: theOpsSetAside, root: root, keepingOnlyCopies: true)
            }
            if stillJudged.isEmpty {
                UndoRefusedSwaps.forget(UndoRefusedSwaps.key(for: record, in: writer.journal))
            }
            UndoTrailHook.setAsideByARestoreLine?(
                record.step.course ?? course, record.step.section, ended, newlyInside.count, stillJudged.count, true
            )
        }
        return touched
    }
}
