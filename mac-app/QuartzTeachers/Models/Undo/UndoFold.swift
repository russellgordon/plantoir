import Foundation

/// Where a step stands, folded from its events.
nonisolated enum UndoStepPhase: String, Sendable {
    /// Written down; its change is under way (or its process died).
    case begun
    /// Its change is made: on the list.
    case done
    /// Being undone.
    case undoing
    /// Undone: above the head.
    case undone
    /// Being redone.
    case redoing
    /// Never happened, or nothing of it took effect.
    case failed
    /// Part of it took effect and recovery put that back.
    case rolledBack
    /// Its process died part way and a file changed by hand stopped
    /// recovery putting all of it back: partly applied, its files named.
    case interrupted
    /// Its redo was cut off by a newer step.
    case dropped
    /// Past what the list keeps on the disk.
    case pruned
    /// Taken off by a `cleared` line.
    case cleared

    /// Whether some process is still working on it.
    var isInFlight: Bool {
        return self == .begun || self == .undoing || self == .redoing
    }

    /// Whether it is on the list at all.
    var isOnTheList: Bool {
        return self == .done || self == .undone || isInFlight
    }
}

/// Where a line is: its segment, and its place in it.
nonisolated struct UndoPosition: Comparable, Hashable, Sendable {

    // MARK: - Stored properties

    let segment: Int

    let line: Int

    // MARK: - Functions

    static func < (first: UndoPosition, second: UndoPosition) -> Bool {
        if first.segment != second.segment {
            return first.segment < second.segment
        }
        return first.line < second.line
    }
}

/// A line this version could not read, kept as a reason to stop.
nonisolated struct UndoBarrier: Equatable, Sendable {

    // MARK: - Stored properties

    /// Its `seq` when it has one.
    let seq: Int?

    let position: UndoPosition

    /// Every blob name its text holds: kept while its segment is.
    var referencedBlobs: [String] = []

    /// Counted in `UndoFold.unreadableLines` (a duplicate `begin`, or one
    /// with no step, is a barrier that is not).
    var isAnUnreadableLine: Bool = false
}

/// One step and where it stands.
nonisolated struct UndoStepRecord: Equatable, Sendable {

    // MARK: - Stored properties

    let step: UndoStep

    var phase: UndoStepPhase

    /// The process of the newest event that started work on it.
    var process: UndoProcess?

    /// Every segment holding one of its events.
    var segments: Set<Int>

    /// Where its `begin` is.
    let beginPosition: UndoPosition

    /// A clearing happened while it was in flight; when its work ends on the
    /// list, it leaves it (`undo.rule.clearing`: the director's ruling 3 on
    /// U1's second reviews, a fixed rule for every clearing).
    var clearedWhileInFlight: Bool = false

    /// For a step this version cannot read: every blob name its `begin` line
    /// holds, kept while the step is on the list.
    var referencedBlobs: [String] = []

    /// The step's `madeAt`, read once when its `begin` is folded.
    let madeAt: Date?

    // MARK: - Computed properties

    var isReadable: Bool {
        return step.isReadable
    }

    // MARK: - Initializer

    init(step: UndoStep, phase: UndoStepPhase, process: UndoProcess?, segments: Set<Int>, beginPosition: UndoPosition) {
        self.step = step
        self.phase = phase
        self.process = process
        self.segments = segments
        self.beginPosition = beginPosition
        self.madeAt = UndoMoment.date(step.madeAt)
    }
}

/// What Undo or Redo may act on, as offered at a moment.
nonisolated enum UndoAvailability: Equatable, Sendable {
    /// This step.
    case step(UndoStepRecord)
    /// Nothing on the list.
    case nothing
    /// A newer step is still being made, undone or redone.
    case anotherChangeIsUnderWay(UndoStepRecord)
    /// The list holds, at or above the head, something this version cannot
    /// read: greyed, plain "Undo", and never past it (the director's ruling 1).
    case notReadable
}

/// The list as offered at one moment: the limits applied (ruling 4).
nonisolated struct UndoOffer: Equatable, Sendable {

    // MARK: - Stored properties

    let undo: UndoAvailability

    let redo: UndoAvailability

    /// Every step offered, oldest first.
    let offered: [UndoStepRecord]

    /// The moment the list was judged at (`UndoFold.referenceTime`).
    let judgedAt: Date

    // MARK: - Computed properties

    var head: UndoStepRecord? {
        var found: UndoStepRecord? = nil
        for record in offered where record.phase == .done {
            found = record
        }
        return found
    }

    var redoCandidate: UndoStepRecord? {
        if case .step(let record) = redo {
            return record
        }
        return nil
    }
}

/// The list, folded from the events: the only way the head is ever known.
nonisolated struct UndoFold: Equatable, Sendable {

    // MARK: - Stored properties

    /// How far a written time may be ahead of the clock and still be
    /// trusted: a day. A line further ahead was written by a clock set
    /// forward, or the clock is now set back.
    static let clockToleranceSeconds: Double = 86_400

    /// Content is deleted only this long after a step stops being offered
    /// for age, so a clock set forward and put right brings the list back.
    static let deletionGraceDays: Int = 30

    /// Every step whose `begin` was read, by sequence number.
    var records: [Int: UndoStepRecord] = [:]

    /// Their numbers in the order their `begin`s were read: rising.
    var orderedSeqs: [Int] = []

    /// The highest `seq` in ANY line, readable or not, so a number is never
    /// used twice.
    var highestSeq: Int = 0

    /// The segment holding that line: never deleted.
    var highestSeqSegment: Int = 0

    /// Lines that are not readable JSON objects, or not of this version.
    var unreadableLines: Int = 0

    /// Events naming a step whose `begin` is not there, or that do not follow
    /// from where the step stands.
    var ignoredEvents: Int = 0

    /// Every line this version could not read, where it is.
    var barriers: [UndoBarrier] = []

    /// Every segment that holds any line.
    var segmentsSeen: Set<Int> = []

    /// The newest written time on any line.
    var newestWrittenAt: Date? = nil

    /// Each segment's own record: the newest written time on any line in
    /// it. A segment holding a barrier is deleted only once this is past
    /// the limits on the disk (the director's ruling 5 on U1's second
    /// reviews).
    var segmentNewestAt: [Int: Date] = [:]

    /// The most recent clearing: its `seq` and where it is.
    var lastClearingSeq: Int = 0
    var lastClearingPosition: UndoPosition? = nil

    // MARK: - Computed properties

    /// Every step on the list, oldest first, before the limits are applied.
    var stepsOnTheList: [UndoStepRecord] {
        var result: [UndoStepRecord] = []
        for seq in orderedSeqs {
            if let record = records[seq], record.phase.isOnTheList {
                result.append(record)
            }
        }
        return result
    }

    /// Steps some process is working on.
    var inFlight: [UndoStepRecord] {
        var result: [UndoStepRecord] = []
        for record in stepsOnTheList where record.phase.isInFlight {
            result.append(record)
        }
        return result
    }

    /// The newest step on the list that is not undone.
    var newestNotUndone: UndoStepRecord? {
        var found: UndoStepRecord? = nil
        for record in stepsOnTheList where record.phase != .undone {
            found = record
        }
        return found
    }

    /// Undone steps a newer step has cut off, not yet marked `dropped`.
    var staleUndone: [UndoStepRecord] {
        let floor: Int = newestNotUndone?.step.seq ?? 0
        var result: [UndoStepRecord] = []
        for record in stepsOnTheList where record.phase == .undone && record.step.seq < floor {
            result.append(record)
        }
        return result
    }

    /// The segments that hold a line this version cannot read.
    var segmentsHoldingABarrier: Set<Int> {
        var result: Set<Int> = []
        for barrier in barriers {
            result.insert(barrier.position.segment)
        }
        return result
    }

    // MARK: - Functions

    /// Takes one line into the fold.
    mutating func take(_ line: UndoReadLine, at position: UndoPosition) {
        segmentsSeen.insert(position.segment)
        if let seq = line.seq, seq >= highestSeq {
            highestSeq = seq
            highestSeqSegment = position.segment
        }
        if let at = line.at {
            if let newest = newestWrittenAt {
                if at > newest {
                    newestWrittenAt = at
                }
            } else {
                newestWrittenAt = at
            }
            if let segmentNewest = segmentNewestAt[position.segment] {
                if at > segmentNewest {
                    segmentNewestAt[position.segment] = at
                }
            } else {
                segmentNewestAt[position.segment] = at
            }
        }
        guard let event = line.event, let kind = UndoEventKind(rawValue: event.event) else {
            unreadableLines += 1
            barriers.append(UndoBarrier(
                seq: line.seq, position: position,
                referencedBlobs: line.referencedBlobs, isAnUnreadableLine: true
            ))
            return
        }
        if kind == .note {
            return
        }
        if kind == .cleared {
            takeClearing(seq: event.seq, at: position)
            return
        }
        if kind == .begin {
            guard let step = event.step else {
                barriers.append(UndoBarrier(seq: event.seq, position: position, referencedBlobs: line.referencedBlobs))
                return
            }
            if records[event.seq] != nil {
                // Two steps with one number: never a guess.
                barriers.append(UndoBarrier(seq: event.seq, position: position, referencedBlobs: line.referencedBlobs))
                return
            }
            var record: UndoStepRecord = UndoStepRecord(
                step: step, phase: .begun, process: event.process,
                segments: [position.segment], beginPosition: position
            )
            record.referencedBlobs = line.referencedBlobs
            records[event.seq] = record
            orderedSeqs.append(event.seq)
            return
        }
        guard var record = records[event.seq] else {
            ignoredEvents += 1
            return
        }
        guard var next = UndoFold.phase(after: record.phase, on: kind, phase: event.phase) else {
            ignoredEvents += 1
            return
        }
        if record.clearedWhileInFlight && (next == .done || next == .undone) {
            next = .cleared
        }
        record.phase = next
        record.segments.insert(position.segment)
        if kind == .undoing || kind == .redoing {
            record.process = event.process
        }
        records[event.seq] = record
    }

    /// A `cleared` line: everything done or undone with a number up to its
    /// own leaves the list, and a step in flight then (another process's,
    /// begun before the clearing was written) leaves it when its work ends:
    /// its own `applied`, `undone` or `redone` records nothing undoable. One
    /// fixed rule for every clearing (the director's ruling 3 on U1's second
    /// reviews, replacing the constant that was held for Russell).
    mutating func takeClearing(seq: Int, at position: UndoPosition) {
        lastClearingSeq = max(lastClearingSeq, seq)
        lastClearingPosition = position
        for number in orderedSeqs where number <= seq {
            guard var record = records[number] else {
                continue
            }
            if record.phase == .done || record.phase == .undone {
                record.phase = .cleared
                record.segments.insert(position.segment)
                records[number] = record
            } else if record.phase.isInFlight {
                record.clearedWhileInFlight = true
                record.segments.insert(position.segment)
                records[number] = record
            }
        }
    }

    /// Forgets what a deleted segment held that only it could hold: its
    /// barriers and its own record of time. Called when a segment is
    /// deleted from the oldest end, so the fold kept by a process agrees
    /// with a fold read whole afterwards.
    mutating func forgetSegment(_ number: Int) {
        var kept: [UndoBarrier] = []
        for barrier in barriers {
            if barrier.position.segment == number {
                if barrier.isAnUnreadableLine {
                    unreadableLines -= 1
                }
            } else {
                kept.append(barrier)
            }
        }
        barriers = kept
        segmentNewestAt[number] = nil
        segmentsSeen.remove(number)
    }

    /// The table of moves (`undoJournal.folding.moves`): where a step goes
    /// from where it stands on each event, or nil when the event does not
    /// follow (and is ignored).
    static func phase(after current: UndoStepPhase, on kind: UndoEventKind, phase: String?) -> UndoStepPhase? {
        switch kind {
        case .begin, .cleared, .note:
            return nil
        case .applied:
            return current == .begun ? .done : nil
        case .undoing:
            return current == .done ? .undoing : nil
        case .undone:
            return current == .undoing ? .undone : nil
        case .redoing:
            return current == .undone ? .redoing : nil
        case .redone:
            return current == .redoing ? .done : nil
        case .failed, .rolledBack, .interrupted:
            guard let phase, let ended = UndoPhase(rawValue: phase) else {
                return nil
            }
            let expected: UndoStepPhase
            let returnsTo: UndoStepPhase
            switch ended {
            case .begin:
                expected = .begun
                returnsTo = kind == .failed ? .failed : .rolledBack
            case .undoing:
                expected = .undoing
                returnsTo = .done
            case .redoing:
                expected = .redoing
                returnsTo = .undone
            }
            if current != expected {
                return nil
            }
            if kind == .interrupted {
                return .interrupted
            }
            return returnsTo
        case .dropped:
            return current == .undone ? .dropped : nil
        case .pruned:
            if current == .done || current == .undone {
                return .pruned
            }
            return nil
        }
    }

    /// Each step's time for the limits: its own `madeAt`, or the latest one
    /// before it in the list when that is later, so a clock set back for one
    /// step never makes it look older than the steps before it (the core
    /// review's W1). Rising with the sequence, so the steps past a limit are
    /// always one oldest run.
    func effectiveTimes() -> [Int: Date] {
        var result: [Int: Date] = [:]
        var running: Date? = nil
        for seq in orderedSeqs {
            guard let record = records[seq] else {
                continue
            }
            if let made = record.madeAt {
                if let current = running {
                    if made > current {
                        running = made
                    }
                } else {
                    running = made
                }
            }
            if let running {
                result[seq] = running
            }
        }
        return result
    }

    /// The moment the list is judged at: the clock, or the latest step time
    /// that is no more than a day ahead of the clock, when one is. A step
    /// time further ahead of the clock is not trusted, so a clock set forward
    /// and put right brings the list back.
    func referenceTime(now: Date) -> Date {
        var judged: Date = now
        let times: [Int: Date] = effectiveTimes()
        for (_, time) in times {
            if time > judged && time.timeIntervalSince(now) <= UndoFold.clockToleranceSeconds {
                judged = time
            }
        }
        return judged
    }

    /// Whether the clock is behind some written time by more than a day:
    /// then nothing is deleted for age.
    func clockIsBehindTheJournal(now: Date) -> Bool {
        guard let newestWrittenAt else {
            return false
        }
        return newestWrittenAt.timeIntervalSince(now) > UndoFold.clockToleranceSeconds
    }

    /// The list as Undo and Redo see it at `now`: steps older than thirty
    /// days by `referenceTime` are not offered, and nothing older than the
    /// newest of them either (one list, linear); then the newest fifty.
    func offer(now: Date) -> UndoOffer {
        let judged: Date = referenceTime(now: now)
        let cutoffTime: Date = judged.addingTimeInterval(-Double(UndoSwitch.daysKept) * 86_400)
        let times: [Int: Date] = effectiveTimes()
        let all: [UndoStepRecord] = stepsOnTheList

        var expiredThrough: Int = 0
        for record in all {
            if let time = times[record.step.seq], time < cutoffTime {
                expiredThrough = record.step.seq
            }
        }
        var remaining: [UndoStepRecord] = []
        for record in all where record.step.seq > expiredThrough {
            remaining.append(record)
        }
        var offered: [UndoStepRecord] = []
        let skip: Int = max(0, remaining.count - UndoSwitch.stepsKept)
        var index: Int = 0
        for record in remaining {
            if index >= skip {
                offered.append(record)
            } else {
                expiredThrough = max(expiredThrough, record.step.seq)
            }
            index += 1
        }

        var newest: UndoStepRecord? = nil
        for record in offered where record.phase != .undone {
            newest = record
        }
        let blocked: Bool = barrierBlocks(above: newest, expiredThrough: expiredThrough)

        var undo: UndoAvailability = .nothing
        var redo: UndoAvailability = .nothing
        if let newest, newest.phase.isInFlight {
            undo = .anotherChangeIsUnderWay(newest)
            redo = .anotherChangeIsUnderWay(newest)
        } else {
            if let newest {
                undo = .step(newest)
            }
            let floor: Int = newest?.step.seq ?? 0
            for record in offered where record.phase == .undone && record.step.seq > floor {
                redo = .step(record)
                break
            }
            if blocked {
                undo = .notReadable
                redo = .notReadable
            } else {
                if case .step(let record) = undo, !record.isReadable {
                    undo = .notReadable
                    redo = .notReadable
                }
                if case .step(let record) = redo, !record.isReadable {
                    redo = .notReadable
                }
            }
        }
        return UndoOffer(undo: undo, redo: redo, offered: offered, judgedAt: judged)
    }

    /// Whether a line this version cannot read stands at or above a step
    /// (or anywhere above the cut-off, when there is no step): by its number
    /// when it has one, by its place in the journal when it has none. Lines
    /// before the last clearing, or in the oldest run past the limits, no
    /// longer count.
    func barrierBlocks(above step: UndoStepRecord?, expiredThrough: Int) -> Bool {
        var expiredPosition: UndoPosition? = nil
        if expiredThrough > 0, let record = records[expiredThrough] {
            expiredPosition = record.beginPosition
        }
        for barrier in barriers {
            if let seq = barrier.seq {
                if seq <= lastClearingSeq || seq <= expiredThrough {
                    continue
                }
                guard let step else {
                    return true
                }
                if seq >= step.step.seq {
                    return true
                }
            } else {
                if let clearing = lastClearingPosition, barrier.position < clearing {
                    continue
                }
                if let expiredPosition, barrier.position < expiredPosition {
                    continue
                }
                guard let step else {
                    return true
                }
                if barrier.position > step.beginPosition {
                    return true
                }
            }
        }
        // An unreadable step on the list above the head is a barrier too.
        for record in stepsOnTheList where !record.isReadable && record.step.seq > expiredThrough {
            guard let step else {
                return true
            }
            if record.step.seq >= step.step.seq {
                return true
            }
        }
        return false
    }
}
