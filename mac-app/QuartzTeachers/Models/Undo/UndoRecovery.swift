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
/// A put-back that cannot be planned (content it needs is missing, or a
/// file it must move is in the way) can never succeed later either: the
/// step is closed `interrupted` (reason `couldNotPutBack`, naming the files
/// left part way) and the list cleared, exactly as for a hand edit. A swap
/// that is refused (a file another program holds, the everyday case on
/// Windows) is tried again on a bounded schedule (`UndoRefusedSwaps`): at
/// once at an Undo or a Redo, and on the ordinary path one minute after the
/// first refusal, doubling to an hour, so an ordinary action pays nothing
/// for it in between (the director's ruling 5 on U1's third round; measured
/// before, 187 to 255 ms on every action for a 300-page put-back). A step
/// whose working folder cannot be reached, or that
/// this version cannot read, is left as it is while it is on the list, and
/// Undo is not available while it is the newest (ruling 10); pruning closes
/// it once it is past the limits (`UndoPruning`), so nothing stays in flight
/// for ever (the director's ruling 4 on U1's second reviews: measured
/// before, 121 steps and none pruned behind one such step).
///
/// A step closed `interrupted` leaves nothing of the journal's in a course:
/// its staged files are removed when it is closed, and when its folder could
/// not be reached then, by the first recovery in each process that can reach
/// it (`tidyClosedSteps`; the director's ruling 6 on U1's third round).
nonisolated enum UndoRecovery {

    // MARK: - Stored properties

    /// Closed steps whose staged files this process has already looked for,
    /// by list and step number.
    nonisolated(unsafe) private static var tidied: Set<String> = []

    private static let tidiedLock: NSLock = NSLock()

    // MARK: - Functions

    /// `trySwapsNow`: an Undo or a Redo, where a put-back refused earlier is
    /// tried again at once; false on the ordinary path, where it waits for
    /// its turn on `UndoRefusedSwaps`' schedule.
    @discardableResult
    static func run(
        _ writer: UndoJournalWriter,
        mode: UndoMode,
        trySwapsNow: Bool = true,
        resolveRoot: (UndoWorkingFolder) -> URL?
    ) -> [UndoRecoveryResult] {
        var results: [UndoRecoveryResult] = []
        let now: Date = writer.journal.now()
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
            let key: String = UndoRefusedSwaps.key(for: record, in: writer.journal)
            if !trySwapsNow && !UndoRefusedSwaps.isDue(key, now: now) {
                continue
            }
            var swapRefused: Bool = false
            if let result = settle(record, root: root, writer: writer, mode: mode, swapRefused: &swapRefused) {
                UndoRefusedSwaps.forget(key)
                results.append(result)
            } else if swapRefused {
                UndoRefusedSwaps.noteARefusal(key, now: now)
            }
        }
        if mode == .live {
            tidyClosedSteps(writer, resolveRoot: resolveRoot)
        }
        return results
    }

    /// Removes the staged files of every step closed `interrupted` that this
    /// process has not yet looked for and whose folder it can reach. Each is
    /// looked for once per process: a few folder listings, and only for the
    /// rare step that was closed.
    static func tidyClosedSteps(_ writer: UndoJournalWriter, resolveRoot: (UndoWorkingFolder) -> URL?) {
        for seq in writer.fold.orderedSeqs {
            guard let record = writer.fold.records[seq], record.phase == .interrupted else {
                continue
            }
            let key: String = writer.journal.folderURL.standardizedFileURL.path + "#" + String(seq)
            tidiedLock.lock()
            let done: Bool = tidied.contains(key)
            tidiedLock.unlock()
            if done {
                continue
            }
            guard let folder = record.step.workingFolder, let root = resolveRoot(folder) else {
                continue
            }
            tidyStagedFiles(of: record.step, root: root)
            tidiedLock.lock()
            tidied.insert(key)
            tidiedLock.unlock()
        }
    }

    /// Every staged file a step's apply, undo, redo or recovery left beside
    /// the files it names.
    static func tidyStagedFiles(of step: UndoStep, root: URL) {
        var urls: [URL] = []
        for op in step.ops {
            if let path = op.path {
                urls.append(root.appendingPathComponent(path))
            }
        }
        for work in ["apply", "undo", "redo"] {
            UndoSwap.tidyLeftovers(label: "\(step.seq)-\(work)", beside: urls)
        }
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

    /// Nil when nothing was written: `swapRefused` says whether that was a
    /// put-back refused because a file is in use.
    static func settle(
        _ record: UndoStepRecord,
        root: URL,
        writer: UndoJournalWriter,
        mode: UndoMode,
        swapRefused: inout Bool
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
                    // It can never be put back: closed, never left in flight.
                    var leftPartWay: [String] = Array(endPaths).sorted()
                    for path in inTheWay where !leftPartWay.contains(path) {
                        leftPartWay.append(path)
                    }
                    let closing: [UndoEventLine] = [
                        UndoEventLine(seq: step.seq, event: .interrupted, phase: phase, reason: "couldNotPutBack", paths: leftPartWay),
                        UndoEventLine(seq: step.seq, event: .cleared, reason: UndoClearing.interrupted.rawValue),
                    ]
                    if !UndoRecovery.write(closing, step: step, writer) {
                        return nil
                    }
                    UndoTrailHook.interruptedLine?(step.course ?? "", step.section, phase, 0, leftPartWay.count)
                    return UndoRecoveryResult(seq: step.seq, phase: phase, outcome: .interrupted(filesInTheWay: leftPartWay.count, filesPutBack: 0))
                }
                if UndoSwap.swap(targets, label: label + "-recover") != UndoSwapResult.swapped {
                    // A file in use: tried again on the schedule.
                    swapRefused = true
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
        if !UndoRecovery.write(events, step: step, writer) {
            return nil
        }
        return UndoRecoveryResult(seq: step.seq, phase: phase, outcome: outcome)
    }

    /// Appends recovery's lines, a clearing's `seq` the highest in the
    /// journal at that moment, and makes them durable.
    static func write(_ events: [UndoEventLine], step: UndoStep, _ writer: UndoJournalWriter) -> Bool {
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
            return false
        }
        return true
    }

    /// The phase an unfinished step's work ended in, for its closing line.
    static func endedPhase(of record: UndoStepRecord) -> UndoPhase? {
        switch record.phase {
        case .begun:
            return .begin
        case .undoing:
            return .undoing
        case .redoing:
            return .redoing
        default:
            return nil
        }
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
    /// that stays, so no step newer than one kept is ever pruned. A step a
    /// DEAD process left in flight (its folder unreachable, a file in use,
    /// or a step this version cannot read) is closed there as `interrupted`
    /// with reason `unsettled`, naming every file it names, rather than
    /// stopping the run for good; no clearing goes with it, because nothing
    /// older than it is offered any more and a clearing would take every
    /// newer step. A step a running process holds stops the run. A step this
    /// version cannot read is pruned like any other once past the limits.
    /// Then it deletes the content and old segments nothing kept can need.
    /// Inside the lock only, and never failing a caller. In shadow it writes
    /// nothing into a working folder.
    static func prune(
        _ writer: UndoJournalWriter,
        mode: UndoMode = .live,
        resolveRoot: (UndoWorkingFolder) -> URL? = UndoReach.root
    ) {
        let fold: UndoFold = writer.fold
        let now: Date = writer.journal.now()
        let ageLimit: Double = Double(UndoSwitch.daysKept + UndoFold.deletionGraceDays) * 86_400
        let ageCutoff: Date = now.addingTimeInterval(-ageLimit)
        let trustTheClock: Bool = !fold.clockIsBehindTheJournal(now: now)
        let times: [Int: Date] = fold.effectiveTimes()
        let list: [UndoStepRecord] = fold.stepsOnTheList
        var remaining: Int = list.count
        for record in list {
            let tooMany: Bool = remaining > UndoSwitch.stepsKept
            var tooOld: Bool = false
            if trustTheClock, let time = times[record.step.seq], time < ageCutoff {
                tooOld = true
            }
            if record.phase.isInFlight {
                if let process = record.process, writer.journal.processIsAlive(process) {
                    break
                }
                if !tooMany && !tooOld {
                    break
                }
                guard let ended = UndoRecovery.endedPhase(of: record) else {
                    break
                }
                var paths: [String] = []
                for op in record.step.ops {
                    if let path = op.path, !paths.contains(path) {
                        paths.append(path)
                    }
                }
                do {
                    try writer.append(UndoEventLine(seq: record.step.seq, event: .interrupted, phase: ended, reason: "unsettled", paths: paths))
                } catch {
                    return
                }
                // Nothing of the journal's is left in a course: its staged
                // files go now when its folder can be reached, or at the
                // first recovery that can reach it (`tidyClosedSteps`).
                if mode == .live, let folder = record.step.workingFolder, let root = resolveRoot(folder) {
                    UndoRecovery.tidyStagedFiles(of: record.step, root: root)
                }
                UndoRefusedSwaps.forget(UndoRefusedSwaps.key(for: record, in: writer.journal))
                remaining -= 1
                continue
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
        deleteUnneededContent(writer)
        deleteUnneededSegments(writer, now: now, trustTheClock: trustTheClock)
    }

    /// Whether a step's content is still needed: while it is on the list.
    static func stillNeeds(_ record: UndoStepRecord) -> Bool {
        return record.phase.isOnTheList
    }

    /// Blobs nothing kept can need: none a step on the list names (an op's
    /// `blobs` and hashes, and for a step this version cannot read every
    /// blob name its line holds), and none a line this version cannot read
    /// holds, while that line's segment is kept (the director's ruling 5 on
    /// U1's second reviews: an unreadable line stops the deletion only of
    /// what it could reference).
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
            for name in record.referencedBlobs {
                needed.insert(name)
            }
        }
        for barrier in writer.fold.barriers {
            for name in barrier.referencedBlobs {
                needed.insert(name)
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
    /// highest step number (so a number is never used twice). A segment
    /// holding a line this version cannot read goes too, once its bound is
    /// past the limits on the disk and the clock is trusted, like any other:
    /// its own record (the newest time written in it), or, for a segment
    /// with no readable time at all, the record of the first later segment
    /// that has one (`segmentBound`). Never for ever (the director's ruling 7
    /// on U1's third round: before it, such a segment kept itself and every
    /// newer segment for good).
    static func deleteUnneededSegments(_ writer: UndoJournalWriter, now: Date, trustTheClock: Bool) {
        guard let numbers = try? writer.journal.segmentNumbers(), numbers.count > 1 else {
            return
        }
        let ageLimit: Double = Double(UndoSwitch.daysKept + UndoFold.deletionGraceDays) * 86_400
        let ageCutoff: Date = now.addingTimeInterval(-ageLimit)
        let barrierSegments: Set<Int> = writer.fold.segmentsHoldingABarrier
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
            if barrierSegments.contains(number) {
                guard trustTheClock, let bound = segmentBound(number, among: numbers, writer.fold), bound < ageCutoff else {
                    return
                }
            }
            if (try? FileManager.default.removeItem(at: writer.journal.segmentURL(number: number))) == nil {
                return
            }
            writer.forgetSegment(number)
            index += 1
        }
    }

    /// The time a segment is judged by: the newest time written in it, or,
    /// when it holds none it can read, the newest time of the first later
    /// segment that has one. Lines are appended in order, so every line of a
    /// segment was written before every line of the segments after it, and
    /// under a clock that has not gone back the later segment's newest time
    /// is no earlier than this one's own would be: the bound keeps such a
    /// segment at least as long as its own time would have. Deleting a
    /// segment never takes a kept step's blob, which its step keeps. Nil
    /// when no later segment has a time either.
    static func segmentBound(_ number: Int, among numbers: [Int], _ fold: UndoFold) -> Date? {
        if let own = fold.segmentNewestAt[number] {
            return own
        }
        for later in numbers where later > number {
            if let found = fold.segmentNewestAt[later] {
                return found
            }
        }
        return nil
    }
}

/// When recovery next tries a put-back whose swap was refused because a file
/// is in use (the director's ruling 5 on U1's third round). Per process: a
/// process that has never seen the refusal tries at its first lock, and
/// after each refusal it waits one minute, then two, four and so on, never
/// more than an hour (`UndoSwitch.refusedSwapFirstRetrySeconds` and
/// `refusedSwapLongestWaitSeconds`). An Undo or a Redo tries at once
/// whatever the schedule, because that is when the teacher is waiting for
/// it. Bounded at the other end too: once the step is past the limits,
/// pruning closes it `unsettled` and it is forgotten here.
///
/// Rejected: trying at every lock (measured, the core review of U1's second
/// round: 187 to 255 ms on each of about 50 actions for a 300-page step,
/// against 7 to 11 ms for a free page); trying only once per process (a
/// file a program holds for a minute would then wait for the next launch).
nonisolated enum UndoRefusedSwaps {

    // MARK: - Stored properties

    /// By step: how many refusals in a row, and when to try next.
    nonisolated(unsafe) private static var schedule: [String: (refusals: Int, nextTry: Date)] = [:]

    private static let guardLock: NSLock = NSLock()

    // MARK: - Functions

    /// One step's work in one list: its number, where its work stands, and
    /// when it began, so a new list in a reused folder is never confused
    /// with an old one.
    static func key(for record: UndoStepRecord, in journal: UndoJournal) -> String {
        return journal.folderURL.standardizedFileURL.path + "#" + String(record.step.seq)
            + "#" + record.phase.rawValue + "#" + record.step.madeAt
    }

    static func isDue(_ key: String, now: Date) -> Bool {
        guardLock.lock()
        defer {
            guardLock.unlock()
        }
        guard let entry = schedule[key] else {
            return true
        }
        return now >= entry.nextTry
    }

    static func noteARefusal(_ key: String, now: Date) {
        guardLock.lock()
        defer {
            guardLock.unlock()
        }
        let refusals: Int = (schedule[key]?.refusals ?? 0) + 1
        var wait: Double = UndoSwitch.refusedSwapFirstRetrySeconds
        var doubled: Int = 1
        while doubled < refusals && wait < UndoSwitch.refusedSwapLongestWaitSeconds {
            wait = wait * 2
            doubled += 1
        }
        if wait > UndoSwitch.refusedSwapLongestWaitSeconds {
            wait = UndoSwitch.refusedSwapLongestWaitSeconds
        }
        schedule[key] = (refusals: refusals, nextTry: now.addingTimeInterval(wait))
    }

    static func forget(_ key: String) {
        guardLock.lock()
        schedule[key] = nil
        guardLock.unlock()
    }
}
