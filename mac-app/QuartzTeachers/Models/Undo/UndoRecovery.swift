import Foundation

/// Settles steps whose process died part way (plan 2.4; `undo.rule.recovery`).
///
/// Run inside the lock before every new step, undo and redo. For each
/// unfinished event whose process is gone, it reads where each FILE the step
/// changed stands, by its content, never its times:
///
/// - every file where the work started: nothing took effect, `failed` (an
///   undo or redo ends, and the step is back where it stood);
/// - every file where the work was going: completed (`applied`, `undone`,
///   `redone`);
/// - some of each: what took effect is put back, `rolledBack`, a trail line;
/// - any file neither (changed by hand since the process died): every file
///   that CAN be verified is put back where the work started, the step is
///   `interrupted` naming the files in the way by path, the whole list is
///   CLEARED (reason `interrupted`, as ruling 13 clears for a refused step)
///   and a trail line is written. The journal never says done or failed
///   for a step that is half applied (the core review's I1).
///
/// In SHADOW nothing is written into a working folder: the outcome is
/// recorded and the files are left as the action left them.
///
/// Recovery's own repair is made inside the lock: the one exception to
/// "never while a change is applied", so two processes cannot repair the
/// same step at once. It is rare (a crash) and bounded by the step's size.
///
/// A step whose working folder cannot be reached, or that this version
/// cannot read, is left as it is.
nonisolated enum UndoRecovery {

    // MARK: - Functions

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
            if !record.isReadable {
                continue
            }
            guard let folder = record.step.workingFolder, let root = resolveRoot(folder) else {
                continue
            }
            if let result = settle(record, root: root, writer: writer, mode: mode) {
                results.append(result)
            }
        }
        return results
    }

    /// Where each file of a step stands: before, after or neither.
    static func fileStates(of step: UndoStep, root: URL) -> [(path: String, state: UndoOpState)] {
        var order: [String] = []
        var states: [String: UndoOpState] = [:]
        var items: [String: UndoItem] = [:]
        for op in step.ops {
            guard let kind = op.knownKind, kind != .recompute, let path = op.path else {
                continue
            }
            if items[path] == nil {
                items[path] = UndoItem.read(at: root.appendingPathComponent(path))
                order.append(path)
            }
            let state: UndoOpState = UndoCheck.state(of: op, in: items[path] ?? .absent)
            if let earlier = states[path] {
                if earlier != state {
                    states[path] = .neither
                }
            } else {
                states[path] = state
            }
        }
        var result: [(path: String, state: UndoOpState)] = []
        for path in order {
            result.append((path: path, state: states[path] ?? .neither))
        }
        return result
    }

    /// Where every content op of a step stands now, counted by file.
    static func census(of step: UndoStep, root: URL) -> (before: Int, after: Int, neither: Int) {
        var before: Int = 0
        var after: Int = 0
        var neither: Int = 0
        for file in fileStates(of: step, root: root) {
            switch file.state {
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
            if let path = op.path {
                urls.append(root.appendingPathComponent(path))
            }
        }
        if mode == .live {
            UndoSwap.tidyLeftovers(label: label, beside: urls)
        }

        // Which state the work was moving FROM, and TO.
        let startedFromBefore: Bool = phase == .begin || phase == .redoing
        let startState: UndoOpState = startedFromBefore ? .before : .after
        let files: [(path: String, state: UndoOpState)] = fileStates(of: step, root: root)
        var atStart: Int = 0
        var atEnd: Int = 0
        var inTheWay: [String] = []
        var endPaths: Set<String> = []
        for file in files {
            if file.state == .neither {
                inTheWay.append(file.path)
            } else if file.state == startState {
                atStart += 1
            } else {
                atEnd += 1
                endPaths.insert(file.path)
            }
        }

        var outcome: UndoRecoveryResult.Outcome
        var events: [UndoEventLine] = []
        if inTheWay.isEmpty && atEnd == 0 {
            outcome = .nothingTookEffect
            events.append(UndoEventLine(seq: step.seq, event: .failed, phase: phase, reason: "nothingTookEffect"))
        } else if inTheWay.isEmpty && atStart == 0 {
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
            if finishing == .applied {
                JournaledWrite.dropTheRedoBranch(below: step.seq, writer)
            }
            events.append(UndoEventLine(seq: step.seq, event: finishing))
        } else {
            // Put back every file that took effect and can be verified.
            var putBack: Int = 0
            if mode == .live && !endPaths.isEmpty {
                var opsToPutBack: [UndoOp] = []
                for op in step.ops {
                    if let path = op.path, endPaths.contains(path) {
                        opsToPutBack.append(op)
                    }
                }
                let back: UndoDirection = startedFromBefore ? .backward : .forward
                let plan: UndoPlan = UndoCheck.plan(opsToPutBack, direction: back, root: root, journal: writer.journal)
                guard case .ready(let targets, _) = plan else {
                    return nil
                }
                if UndoSwap.swap(targets, label: label + "-recover") != UndoSwapResult.swapped {
                    return nil
                }
                putBack = targets.count
            }
            if inTheWay.isEmpty && mode == .live {
                outcome = .rolledBack(files: putBack)
                events.append(UndoEventLine(seq: step.seq, event: .rolledBack, phase: phase, reason: "partlyTookEffect"))
                UndoTrailHook.rolledBackLine?(step.course ?? "", step.section, phase, putBack)
            } else if inTheWay.isEmpty {
                // Shadow: recorded, never repaired.
                outcome = .leftAlone
                events.append(UndoEventLine(seq: step.seq, event: .interrupted, phase: phase, reason: "partlyTookEffect", paths: Array(endPaths).sorted()))
                events.append(UndoEventLine(seq: step.seq, event: .cleared, reason: UndoClearing.interrupted.rawValue))
            } else {
                outcome = .interrupted(filesInTheWay: inTheWay.count, filesPutBack: putBack)
                events.append(UndoEventLine(seq: step.seq, event: .interrupted, phase: phase, reason: "changedByHand", paths: inTheWay))
                events.append(UndoEventLine(seq: step.seq, event: .cleared, reason: UndoClearing.interrupted.rawValue))
                if mode == .live {
                    // In shadow nothing was put back and nothing offered was
                    // cleared: the journal holds the outcome, the trail does not.
                    UndoTrailHook.interruptedLine?(step.course ?? "", step.section, phase, putBack, inTheWay.count)
                }
            }
        }
        do {
            for event in events {
                var written: UndoEventLine = event
                if written.event == UndoEventKind.cleared.rawValue {
                    written.seq = max(writer.fold.highestSeq, step.seq)
                }
                try writer.append(written)
            }
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
        case interrupted(filesInTheWay: Int, filesPutBack: Int)
        case leftAlone
    }
}

/// The limits on the DISK (rulings 3 and 5, `undo.rule.limits`). What is
/// OFFERED is judged when the list is read (`UndoFold.offer`); this decides
/// what may be deleted, later and more carefully.
nonisolated enum UndoPruning {

    // MARK: - Functions

    /// Prunes one OLDEST run of the list: past the newest fifty, or made
    /// more than thirty days plus a grace of thirty before the clock (never
    /// while the clock is behind the journal). It stops at the first step
    /// that stays, so no step newer than one kept is ever pruned. Then it
    /// deletes content and old segments nothing kept can name, unless the
    /// journal holds anything this version cannot read. Inside the lock
    /// only, and never failing a caller.
    static func prune(_ writer: UndoJournalWriter) {
        let fold: UndoFold = writer.fold
        let now: Date = writer.journal.now()
        let ageLimit: Double = Double(UndoSwitch.daysKept + UndoFold.deletionGraceDays) * 86_400
        let ageCutoff: Date = now.addingTimeInterval(-ageLimit)
        let trustTheClock: Bool = !fold.clockIsBehindTheJournal(now: now)
        let times: [Int: Date] = fold.effectiveTimes()
        let list: [UndoStepRecord] = fold.stepsOnTheList
        var remaining: Int = list.count
        for record in list {
            if record.phase.isInFlight || !record.isReadable {
                break
            }
            let tooMany: Bool = remaining > UndoSwitch.stepsKept
            var tooOld: Bool = false
            if trustTheClock, let time = times[record.step.seq], time < ageCutoff {
                tooOld = true
            }
            if !tooMany && !tooOld {
                break
            }
            do {
                try writer.append(UndoEventLine(seq: record.step.seq, event: .pruned, reason: tooMany ? "tooMany" : "tooOld"))
            } catch {
                return
            }
            remaining -= 1
        }
        if writer.fold.holdsAnythingUnreadable {
            return
        }
        deleteUnneededContent(writer)
        deleteUnneededSegments(writer)
    }

    /// Whether a step's content is still needed: while it is on the list.
    static func stillNeeds(_ record: UndoStepRecord) -> Bool {
        return record.phase.isOnTheList
    }

    /// Blobs no step still on the list names.
    static func deleteUnneededContent(_ writer: UndoJournalWriter) {
        var needed: Set<String> = []
        for seq in writer.fold.orderedSeqs {
            guard let record = writer.fold.records[seq], stillNeeds(record) else {
                continue
            }
            for op in record.step.ops {
                for name in op.namedBlobs {
                    needed.insert(name)
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
    /// step still on the list and are older than the segment holding the
    /// highest step number (so a number is never used twice).
    static func deleteUnneededSegments(_ writer: UndoJournalWriter) {
        guard let numbers = try? writer.journal.segmentNumbers(), numbers.count > 1 else {
            return
        }
        var needed: Set<Int> = []
        for seq in writer.fold.orderedSeqs {
            guard let record = writer.fold.records[seq], stillNeeds(record) else {
                continue
            }
            for segment in record.segments {
                needed.insert(segment)
            }
        }
        var index: Int = 0
        while index < numbers.count - 1 {
            let number: Int = numbers[index]
            if needed.contains(number) || number >= writer.fold.highestSeqSegment {
                return
            }
            try? FileManager.default.removeItem(at: writer.journal.segmentURL(number: number))
            UndoFoldCache.forget(writer.journal.folderURL)
            index += 1
        }
    }
}
