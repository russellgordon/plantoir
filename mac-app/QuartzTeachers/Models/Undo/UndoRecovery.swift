import Foundation

/// Settles steps whose process died part way (plan 2.4).
///
/// Run inside the lock before every new step, every undo and every redo.
/// For each unfinished event whose process is gone, it reads what each op
/// changed and decides from the CONTENT, never from times:
///
/// - none of it took effect: the step `failed` (or the undo or redo is
///   ended and the step goes back to where it stood);
/// - all of it took effect: the step is completed (`applied`, `undone`,
///   `redone`);
/// - some of it took effect: what took effect is put back, and the step is
///   `rolledBack`, with one trail line;
/// - something it changed is now neither: nothing is written, and the step
///   is ended where nothing of it is trusted.
///
/// So a process that dies leaves the files as they were before its step or
/// as they were after it, never in between: the contract's
/// `undo.recoveryCases`. In SHADOW mode nothing is ever written into a
/// working folder: a step that partly took effect is marked `failed` and the
/// files are left exactly as the action left them.
///
/// A step whose working folder cannot be reached is left as it is, unsettled:
/// it waits, and Undo waits behind it (rulings 9 and 10).
nonisolated enum UndoRecovery {

    // MARK: - Functions

    /// Settles what can be settled. Never throws: a journal event that
    /// cannot be written is left for the next run.
    @discardableResult
    static func run(
        _ writer: UndoJournalWriter,
        mode: UndoMode,
        resolveRoot: (UndoWorkingFolder) -> URL?
    ) -> [UndoRecoveryResult] {
        var results: [UndoRecoveryResult] = []
        for record in writer.fold.inFlight {
            guard let process = record.process else {
                continue
            }
            if writer.journal.processIsAlive(process) {
                continue
            }
            guard let root = resolveRoot(record.step.workingFolder) else {
                continue
            }
            if let result = settle(record, root: root, writer: writer, mode: mode) {
                results.append(result)
            }
        }
        return results
    }

    /// Where every content op of a step stands now.
    static func census(of step: UndoStep, root: URL) -> (before: Int, after: Int, neither: Int) {
        var items: [String: UndoItem] = [:]
        var before: Int = 0
        var after: Int = 0
        var neither: Int = 0
        for op in step.ops where op.knownKind != .recompute {
            if items[op.path] == nil {
                items[op.path] = UndoItem.read(at: root.appendingPathComponent(op.path))
            }
            let state: UndoOpState = UndoCheck.state(of: op, in: items[op.path] ?? .absent)
            switch state {
            case .before:
                before += 1
            case .after:
                after += 1
            case .neither:
                neither += 1
            }
        }
        return (before: before, after: after, neither: neither)
    }

    static func settle(
        _ record: UndoStepRecord,
        root: URL,
        writer: UndoJournalWriter,
        mode: UndoMode
    ) -> UndoRecoveryResult? {
        let step: UndoStep = record.step
        let phase: UndoPhase
        let label: String
        switch record.phase {
        case .begun:
            phase = .begin
            label = "\(step.seq)-apply"
        case .undoing:
            phase = .undoing
            label = "\(step.seq)-undo"
        case .redoing:
            phase = .redoing
            label = "\(step.seq)-redo"
        default:
            return nil
        }
        var urls: [URL] = []
        for op in step.ops {
            urls.append(root.appendingPathComponent(op.path))
        }
        if mode == .live {
            UndoSwap.tidyLeftovers(label: label, beside: urls)
        }

        let counts: (before: Int, after: Int, neither: Int) = census(of: step, root: root)
        // Which state the step was moving FROM and TO.
        let startedFromBefore: Bool = phase == .begin || phase == .redoing
        let atStart: Int = startedFromBefore ? counts.before : counts.after
        let atEnd: Int = startedFromBefore ? counts.after : counts.before

        var outcome: UndoRecoveryResult.Outcome
        var event: UndoEventLine
        if counts.neither > 0 {
            outcome = .leftAlone
            event = UndoEventLine(seq: step.seq, event: .failed, phase: phase, reason: "changedDuring")
        } else if atEnd == 0 {
            outcome = .nothingTookEffect
            event = UndoEventLine(seq: step.seq, event: .failed, phase: phase, reason: "nothingTookEffect")
        } else if atStart == 0 {
            outcome = .completed
            let finishing: UndoEventKind
            switch phase {
            case .begin:
                finishing = .applied
            case .undoing:
                finishing = .undone
            case .redoing:
                finishing = .redone
            }
            event = UndoEventLine(seq: step.seq, event: finishing)
        } else if mode == .shadow {
            outcome = .leftAlone
            event = UndoEventLine(seq: step.seq, event: .failed, phase: phase, reason: "partlyTookEffect")
        } else {
            // Put back what took effect: an undo that died part way goes
            // forward again; a step or a redo goes backward.
            let back: UndoDirection = startedFromBefore ? .backward : .forward
            let plan: UndoPlan = UndoCheck.plan(step.ops, direction: back, root: root, journal: writer.journal)
            guard case .ready(let targets, _) = plan else {
                return nil
            }
            let swapped: UndoSwapResult = UndoSwap.swap(targets, label: label + "-recover")
            if swapped != UndoSwapResult.swapped {
                return nil
            }
            outcome = .rolledBack(files: targets.count)
            event = UndoEventLine(seq: step.seq, event: .rolledBack, phase: phase, reason: "partlyTookEffect")
            UndoTrailHook.rolledBackLine?(step.course, step.section, phase, targets.count)
        }
        do {
            try writer.append(event)
            try writer.sync()
        } catch {
            return nil
        }
        return UndoRecoveryResult(seq: step.seq, phase: phase, outcome: outcome)
    }
}

/// What recovery did with one step.
nonisolated struct UndoRecoveryResult: Equatable, Sendable {

    // MARK: - Stored properties

    let seq: Int

    let phase: UndoPhase

    let outcome: Outcome

    enum Outcome: Equatable, Sendable {
        case nothingTookEffect
        case completed
        case rolledBack(files: Int)
        case leftAlone
    }
}

/// The limits: fifty steps and thirty days, across the app (rulings 3, 5).
nonisolated enum UndoPruning {

    // MARK: - Functions

    /// Prunes the oldest steps past the limits, then deletes the content and
    /// the old segments nothing on the list needs. Inside the lock only.
    /// Never fails a caller: what it cannot delete is tried next time.
    static func prune(_ writer: UndoJournalWriter) {
        let cutoff: Date = writer.journal.now().addingTimeInterval(-Double(UndoSwitch.daysKept) * 86_400)
        var settled: [UndoStepRecord] = []
        for record in writer.fold.stepsOnTheList where !record.phase.isInFlight {
            settled.append(record)
        }
        var excess: Int = settled.count - UndoSwitch.stepsKept
        for record in settled {
            var tooOld: Bool = false
            if let made = UndoMoment.date(record.step.madeAt), made < cutoff {
                tooOld = true
            }
            if excess > 0 || tooOld {
                let reason: String = excess > 0 ? "tooMany" : "tooOld"
                do {
                    try writer.append(UndoEventLine(seq: record.step.seq, event: .pruned, reason: reason))
                } catch {
                    return
                }
                excess -= 1
            }
        }
        deleteUnneededContent(writer)
        deleteUnneededSegments(writer)
    }

    /// Blobs no step still on the list (or still being made) names.
    static func deleteUnneededContent(_ writer: UndoJournalWriter) {
        var needed: Set<String> = []
        for record in writer.fold.stepsOnTheList {
            for op in record.step.ops {
                if let sha = op.beforeSha {
                    needed.insert(sha)
                }
                if let sha = op.afterSha {
                    needed.insert(sha)
                }
            }
        }
        let content: URL = writer.journal.contentFolderURL
        guard let prefixes = try? FileManager.default.contentsOfDirectory(atPath: content.path) else {
            return
        }
        for prefix in prefixes {
            let folder: URL = content.appendingPathComponent(prefix, isDirectory: true)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
                continue
            }
            for name in names where !needed.contains(name) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }

    /// Old segments, from the oldest end only, while they hold no event of a
    /// step still on the list. Deleting from the oldest end keeps every
    /// later event of a step whose `begin` is still there, so a step can
    /// never come back to life because the line that ended it was deleted.
    /// The newest segment is never deleted: it carries the highest number.
    static func deleteUnneededSegments(_ writer: UndoJournalWriter) {
        guard let numbers = try? writer.journal.segmentNumbers(), numbers.count > 1 else {
            return
        }
        var needed: Set<Int> = []
        for record in writer.fold.stepsOnTheList {
            for segment in record.segments {
                needed.insert(segment)
            }
        }
        var index: Int = 0
        while index < numbers.count - 1 {
            let number: Int = numbers[index]
            if needed.contains(number) {
                return
            }
            try? FileManager.default.removeItem(at: writer.journal.segmentURL(number: number))
            index += 1
        }
    }
}
