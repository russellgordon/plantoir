import Foundation

/// A restore that replaces a course settles every Undo step left in flight
/// in that course BEFORE it moves anything (#899, the director's decision
/// of 2026-11-27, ahead of U5, which makes a restore itself a step).
///
/// Without it a step that stopped part way (Get Ready for the Start of the
/// Year, say) stays in flight over a course that now holds the backup, and
/// the next recovery judges the RESTORED files against it: after a second
/// Get Ready it closed the old step as made (two on the list for one
/// change), or put back part of the second run's files.
///
/// Each such step is closed exactly as pruning closes a step that can never
/// be settled (`undo.rule.limits`, reason `unsettled`): `interrupted`, with
/// the reason `setAsideByARestore` and every file it names, and NO clearing.
/// That is true of the disk whichever way the restore then goes: if it
/// finishes, the step's files are the backup's, which the step never
/// recorded; if it fails part way and puts every file back, they are as the
/// stopped step left them, partly made or not, which is what `interrupted`
/// says (partly applied or unknown, off the list). Recovery never judges it
/// again. The earlier steps of the course are left on the list, as a
/// restore has always left them: an Undo of one checks its files by content
/// and refuses (and clears) when the restore changed them, the rule for a
/// file changed by hand (`undo.rule.clearing`). No clearing is written,
/// because it would take every other course's steps, those in flight
/// included, and those are not the restore's to touch.
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

    /// Whether the step lies inside what the restore replaces: made in this
    /// working folder (by its identifier) and naming at least one file under
    /// `replaced` (one stopped file there is enough: none of the step can be
    /// judged honestly once part of it is replaced).
    static func liesInside(_ step: UndoStep, workingFolderID: String, replaced: String) -> Bool {
        guard let folder = step.workingFolder, folder.id.lowercased() == workingFolderID.lowercased() else {
            return false
        }
        for path in pathsNamed(by: step) where isInside(path, replaced) {
            return true
        }
        return false
    }

    /// Closes every step in flight whose files lie inside `replaced` (a
    /// path inside the working folder at `workingFolderRoot`, such as
    /// `courses/ICS3U` for a whole course), inside the list's own lock, and
    /// leaves one trail line for each. Steps of other courses and other
    /// working folders are never touched. Returns the numbers of the steps
    /// it closed. A list that cannot be locked or written changes nothing
    /// and never stops the restore: the step then stays in flight, as before
    /// this rule, and is said on the trail.
    @discardableResult
    static func setAsideStepsInFlight(
        inside replaced: String,
        workingFolderRoot: URL,
        course: String,
        journal: UndoJournal,
        mode: UndoMode = UndoSwitch.currentMode
    ) -> [Int] {
        guard let workingFolderID = FolderIdentityFile.existingIdentifier(forWorkingFolder: workingFolderRoot) else {
            // A folder with no identifier has never had a step made in it.
            return []
        }
        var closed: [Int] = []
        do {
            try journal.withLock(waitingAtMost: UndoSwitch.finishWaitSeconds, inShadow: mode == .shadow) { writer in
                for record in writer.fold.inFlight {
                    if !liesInside(record.step, workingFolderID: workingFolderID, replaced: replaced) {
                        continue
                    }
                    guard let ended = UndoRecovery.endedPhase(of: record) else {
                        continue
                    }
                    let paths: [String] = pathsNamed(by: record.step)
                    try writer.append(
                        UndoEventLine(seq: record.step.seq, event: .interrupted, phase: ended, reason: reason, paths: paths)
                    )
                    closed.append(record.step.seq)
                    // Nothing of the journal's is left in the course: its
                    // staged files go now, a kept original that is the only
                    // copy of what its page held stays (as pruning tidies a
                    // step it closes unsettled). In shadow nothing is
                    // written into the working folder.
                    if mode == .live {
                        _ = UndoRecovery.tidyStagedFiles(of: record.step, root: workingFolderRoot, keepingOnlyCopies: true)
                    }
                    UndoRefusedSwaps.forget(UndoRefusedSwaps.key(for: record, in: writer.journal))
                    UndoTrailHook.setAsideByARestoreLine?(
                        record.step.course ?? course, record.step.section, ended, paths.count, true
                    )
                }
            }
        } catch {
            UndoTrailHook.setAsideByARestoreLine?(course, nil, .begin, 0, false)
        }
        return closed
    }
}
