import Foundation

/// What the door made of a one-file step that stopped part way while this
/// process is still running (#899, Russell's ruling of 2026-11-26: "Plantoir
/// finishes it, and if it can't, Plantoir offers to automatically put it
/// back").
nonisolated enum UndoStoppedStepVerdict: Equatable, Sendable {

    /// The file holds the whole new value: closed as made, on the list.
    case finished(seq: Int)

    /// The file holds the old value: closed as put back, off the list.
    case putBack

    /// The check could not read the file, could not close the step, or
    /// could not get the list's lock: the step is left in flight, and the
    /// caller offers to put it back (`putBackAtOnce`), which can succeed.
    /// Recovery settles it at the next launch otherwise.
    case couldNotFinish(seq: Int)

    /// Closed without the change, and nothing to offer: the file holds
    /// neither value (another program wrote it, or it is half written), so
    /// the door's own rule for a file changed by hand closed the step and
    /// cleared the list (`undo.rule.recovery`), or the step was already
    /// closed without it. Put It Back could not succeed and is never
    /// offered; nothing is written over what the file holds. The caller says
    /// the save's own failure sentence (#899, fix round one).
    case notMade
}

/// How a Put It Back went.
nonisolated enum UndoPutBackVerdict: Equatable, Sendable {

    /// The old value is on the disk and the step is closed.
    case putBack

    /// The old value could not be written, or the step could not be closed.
    case couldNotPutBack
}

/// A one-file step that stopped part way, judged AT ONCE by content with
/// the same check recovery uses (`undo.rule.recovery`), instead of being
/// left in flight until this process has gone.
nonisolated enum UndoStoppedStep {

    // MARK: - Functions

    /// Whether the step's ops all edit members of ONE JSON file: the steps
    /// that are judged at once (Course Settings' fields, Set School Year).
    static func isOneFileJSONStep(_ ops: [UndoOp]) -> Bool {
        var paths: Set<String> = []
        var hasAnEdit: Bool = false
        for op in ops {
            if op.knownKind == .recompute {
                continue
            }
            if op.knownKind != .editJSON {
                return false
            }
            hasAnEdit = true
            paths.insert(op.placeName)
        }
        return hasAnEdit && paths.count == 1
    }

    /// The in-flight record numbered `seq`, if it is still in flight.
    static func inFlightRecord(_ seq: Int, _ writer: UndoJournalWriter) -> UndoStepRecord? {
        for record in writer.fold.inFlight where record.step.seq == seq {
            return record
        }
        return nil
    }

    /// Judges step `seq` by content and closes it, exactly as recovery
    /// would settle it once this process had gone: a file holding the new
    /// value closes it as made, one holding the old value closes it as put
    /// back, and the leftover copy beside it is tidied away as recovery
    /// tidies it. Left in flight when the file cannot be read or the step
    /// cannot be closed.
    static func judgeAtOnce(
        seq: Int,
        in journal: UndoJournal,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) -> UndoStoppedStepVerdict {
        do {
            return try journal.withLock(waitingAtMost: UndoSwitch.finishWaitSeconds) { writer -> UndoStoppedStepVerdict in
                guard let record = inFlightRecord(seq, writer) else {
                    // Already closed (by recovery, or an earlier judgement):
                    // said as it was closed, never offered.
                    if writer.fold.records[seq]?.phase == .done {
                        return .finished(seq: seq)
                    }
                    return .notMade
                }
                guard let root = UndoCheck.root(of: record.step, resolveRoot: UndoReach.root) else {
                    return .couldNotFinish(seq: seq)
                }
                var swapRefused: Bool = false
                var leftFor: UndoRefusal? = nil
                let result: UndoRecoveryResult? = UndoRecovery.settle(
                    record, root: root, writer: writer, mode: .live, places: places,
                    swapRefused: &swapRefused, leftFor: &leftFor
                )
                guard let result else {
                    return .couldNotFinish(seq: seq)
                }
                switch result.outcome {
                case .completed:
                    return .finished(seq: seq)
                case .nothingTookEffect, .rolledBack:
                    return .putBack
                case .interrupted, .leftAlone:
                    // Closed by the rule for a file changed by hand, the
                    // file holding neither value: nothing to offer.
                    return .notMade
                }
            }
        } catch {
            // The lock was not got: the step is still in flight and Put It
            // Back, which takes the lock again, can succeed.
            return .couldNotFinish(seq: seq)
        }
    }

    /// Put It Back: writes what step `seq` changed back to what it held
    /// before, through the door as recovery would, and closes the step as
    /// put back. Only a step still in flight is put back: one closed
    /// meanwhile is never swapped with no line on the list, and counts as
    /// put back only when its file already holds every old value.
    static func putBackAtOnce(
        seq: Int,
        in journal: UndoJournal,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) -> UndoPutBackVerdict {
        do {
            return try journal.withLock(waitingAtMost: UndoSwitch.finishWaitSeconds) { writer -> UndoPutBackVerdict in
                var known: UndoStepRecord? = nil
                for (_, candidate) in writer.fold.records where candidate.step.seq == seq {
                    known = candidate
                }
                guard let known, let root = UndoCheck.root(of: known.step, resolveRoot: UndoReach.root) else {
                    return .couldNotPutBack
                }
                let stepOps: [UndoOp] = known.step.ops
                guard let record = inFlightRecord(seq, writer) else {
                    for op in stepOps where op.knownKind == .editJSON {
                        if !JSONMemberCheck.holdsTheValueBefore(op, root: root) {
                            return .couldNotPutBack
                        }
                    }
                    return .putBack
                }
                let label: String = "\(seq)-recover"
                var opsToPutBack: [UndoOp] = []
                for op in stepOps where op.knownKind == .editJSON {
                    if JSONMemberCheck.holdsTheValueAfter(op, root: root) {
                        opsToPutBack.append(op)
                    } else if !JSONMemberCheck.holdsTheValueBefore(op, root: root) {
                        // Neither value, or unreadable: nothing is written
                        // over what the file holds now.
                        return .couldNotPutBack
                    }
                }
                if !opsToPutBack.isEmpty {
                    let plan: UndoPlan = UndoCheck.plan(
                        opsToPutBack, direction: .backward, root: root, journal: journal, places: places, ownSeq: seq
                    )
                    guard case .ready(let targets, _, _) = plan else {
                        return .couldNotPutBack
                    }
                    guard case .swapped = UndoSwap.swap(targets, label: label, places: places, root: root) else {
                        return .couldNotPutBack
                    }
                }
                do {
                    let closing: UndoEventLine = opsToPutBack.isEmpty
                        ? UndoEventLine(seq: seq, event: .failed, phase: .begin, reason: "nothingTookEffect")
                        : UndoEventLine(seq: seq, event: .rolledBack, phase: .begin, reason: "partlyTookEffect")
                    if !UndoRecovery.write([closing], step: record.step, writer) {
                        return .couldNotPutBack
                    }
                    if !opsToPutBack.isEmpty {
                        // The same trail line recovery leaves for a step
                        // it put back (the first review, LOW 2).
                        UndoTrailHook.rolledBackLine?(
                            record.step.course ?? "", record.step.section, .begin, opsToPutBack.count
                        )
                    }
                    let urls: [URL] = UndoRecovery.placesStagedBeside(of: record.step, root: root)
                    let listHolds: (URL, URL) -> Bool = UndoRecovery.listHolds(record.step, root: root, from: journal)
                    _ = UndoSwap.tidyLeftovers(
                        label: "\(seq)-apply", beside: urls, root: root, keepingOnlyCopies: true, unlessTheListHolds: listHolds,
                        linksOfTheStep: UndoRecovery.links(of: record.step, root: root)
                    )
                    _ = UndoSwap.tidyLeftovers(
                        label: label, beside: urls, root: root, keepingOnlyCopies: true, unlessTheListHolds: listHolds,
                        linksOfTheStep: UndoRecovery.links(of: record.step, root: root)
                    )
                }
                return .putBack
            }
        } catch {
            return .couldNotPutBack
        }
    }
}

/// One `editJSON` op's member judged in the file as it is now, by the
/// same check recovery and Undo use (`UndoCheck.state(of:in:)`).
nonisolated enum JSONMemberCheck {

    // MARK: - Functions

    static func state(of op: UndoOp, root: URL) -> UndoOpState {
        guard let path = op.path else {
            return .neither
        }
        return UndoCheck.state(of: op, in: UndoItem.read(at: root.appendingPathComponent(path)))
    }

    static func holdsTheValueAfter(_ op: UndoOp, root: URL) -> Bool {
        return state(of: op, root: root) == .after
    }

    static func holdsTheValueBefore(_ op: UndoOp, root: URL) -> Bool {
        return state(of: op, root: root) == .before
    }
}
