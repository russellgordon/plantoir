import Foundation

/// One file before and after a change, as the action that made it saw it.
nonisolated struct UndoFileChange: Equatable, Sendable {

    // MARK: - Stored properties

    /// Inside the working folder, forward slashes.
    let relativePath: String

    /// Nil when there was no file.
    let before: Data?

    /// Nil when the change removed it.
    let after: Data?
}

/// What an action hands the door: everything about the step but its number.
nonisolated struct UndoStepDraft: Sendable {

    // MARK: - Stored properties

    let action: UndoAction

    let madeBy: String

    /// The working folder's root: the folder holding `courses/`.
    let workingFolderURL: URL

    /// Its canonical path (`FolderIdentity.canonicalPath` in the app).
    let workingFolderPath: String

    let course: String

    let section: Int?

    let actionClass: String

    let holds: String

    let changes: [UndoFileChange]

    /// Files kept true by a rule, re-derived after the other ops.
    let recomputes: [UndoOp]
}

/// A step given as its ops, for the kinds U2 defines: everything about the
/// step but its number, and the content its ops need from the list.
nonisolated struct UndoOpsDraft: Sendable {

    // MARK: - Stored properties

    let action: UndoAction

    let madeBy: String

    /// The working folder's root (the folder holding `courses/`), or nil
    /// for a step none of whose ops names a path.
    let workingFolderURL: URL?

    let workingFolderPath: String?

    let course: String?

    let section: Int?

    let actionClass: String?

    let holds: String?

    let ops: [UndoOp]

    /// Every blob the ops name that holds content (a tree's listing and
    /// files, a whole file's bytes), stored before the begin.
    let blobs: [Data]
}

/// How the door went.
nonisolated enum JournaledWriteOutcome: Equatable, Sendable {

    /// Recorded and made.
    case applied(seq: Int)

    /// Made, but not recorded: shadow mode, and the list could not be written.
    case appliedWithoutARecord

    /// Live mode, and the list could not be written: nothing was changed.
    case couldNotRecordTheStep

    /// Live mode, and a step that keeps a file true by a rule was left part
    /// way by a process that died, on the same course: it must be settled
    /// and re-derived first (`performAndRederive`, `undoNewestAndRederive`),
    /// so this door changes nothing (the third hard review of U2b, LOW 1).
    case anotherChangeIsUnderWay

    /// Something was in the way, and nothing was changed.
    case refused(UndoRefusal)

    /// Refused part way: a swap could not be reversed, so a page holds the
    /// new content while its original is kept beside it (`keptOriginals`,
    /// staged names in the page's own folder). The step is left in flight
    /// for recovery; the teacher is told only part was changed.
    case leftPartWay(UndoRefusal, keptOriginals: [String])

    /// A one-file JSON step stopped part way and its content could not be
    /// judged or the step closed at once (`UndoStoppedStep.judgeAtOnce`):
    /// left in flight, and the caller offers to put it back (#899).
    case couldNotFinish(seq: Int, UndoRefusal)

    /// A one-file JSON step stopped part way whose file holds neither value
    /// (another program wrote it, or it is half written), closed by the
    /// door's own rule for a file changed by hand: the list cleared, nothing
    /// offered, nothing written over the file (#899, fix round one).
    case notMade(seq: Int)

    /// Nothing to change.
    case changedNothing

    /// A test stopped the work at a kill point, as a process that died
    /// there would have: nothing more was written, the list included.
    case stoppedByATest
}

/// What stands in the way of a change, an undo or a redo. Each names the
/// first page in the way, inside the working folder.
nonisolated enum UndoRefusal: Equatable, Sendable {

    /// What the step changed has been changed since (`undo.wording.pageChangedSince`).
    case changedSince(firstPath: String, others: Int)

    /// A file could not be swapped in, and the swaps already made were
    /// reversed (`undo.wording.fileIsInUse`).
    case fileIsInUse(path: String)

    /// A file it must read is there and could not be read just now (no
    /// permission, a disk error, a cloud file not downloaded): cannot tell
    /// whether it was changed, so refused for now and never a reason to
    /// clear the list (the director's ruling on U2b's review).
    case cannotTellNow(path: String)

    /// A new content could not be written beside its page: the disk is
    /// full, or the folder will not take a new file (read-only, no
    /// permission). Nothing was swapped and nothing of the step is left
    /// beside any page (`undo.rule.stagedThenSwapped`; the Fable sweep of
    /// U1, F1). Never `fileIsInUse`, which would tell the teacher a file is
    /// open somewhere when it is not.
    case couldNotWrite(path: String)

    /// Content the step needs is missing from the list.
    case contentMissing(path: String)

    /// The step holds an op this version cannot read.
    case notReadable
}

/// The one door every write into a working folder goes through once the
/// switch is on (plan 3.3): it records the step, then makes the change.
///
/// In U1 only the trace replayer and the tests make changes through it; the
/// actions themselves are wired by U3 to U6. The one action recorded today is
/// publishing and hiding pages, and that goes through `beginInShadow` and
/// `finishInShadow` beside the action's own writes, because the action's
/// writes must not change while the list is off.
nonisolated enum JournaledWrite {

    // MARK: - Functions

    /// The ops that describe one file's change: `editLine` for each
    /// front-matter entry it changed when that is ALL it changed, otherwise
    /// one `writeFile`. The line form is only chosen when applying its ops to
    /// the before text gives the after text byte for byte, and undoing them
    /// gives the before text back, so a page the line model cannot describe
    /// exactly falls back to the whole file rather than to a guess.
    static func ops(for change: UndoFileChange) -> [UndoOp] {
        let wholeFile: UndoOp = UndoOp.writeFile(
            path: change.relativePath,
            beforeSha: UndoHash.sha256(ofOptional: change.before),
            afterSha: UndoHash.sha256(ofOptional: change.after)
        )
        guard let beforeData = change.before, let afterData = change.after else {
            return [wholeFile]
        }
        guard let beforeText = UndoText.decode(beforeData), let afterText = UndoText.decode(afterData) else {
            return [wholeFile]
        }
        if let lineOps = UndoLineOps.ops(path: change.relativePath, before: beforeText, after: afterText) {
            return lineOps
        }
        return [wholeFile]
    }

    /// Every op of a draft, in order, with the recomputes last.
    static func ops(for draft: UndoStepDraft) -> [UndoOp] {
        var result: [UndoOp] = []
        for change in draft.changes {
            if change.before == change.after {
                continue
            }
            for op in ops(for: change) {
                result.append(op)
            }
        }
        for op in draft.recomputes {
            result.append(op)
        }
        return result
    }

    /// Records the step, makes the change, and marks it made: the three
    /// phases of plan 2.4. The `begin` is on the disk before any file is
    /// touched, and the files are staged beside their targets and swapped in
    /// only when all are written (`UndoSwap`).
    static func perform(
        _ draft: UndoStepDraft,
        in journal: UndoJournal,
        mode: UndoMode
    ) -> JournaledWriteOutcome {
        let ops: [UndoOp] = ops(for: draft)
        var hasContentOp: Bool = false
        for op in ops where op.knownKind != .recompute {
            hasContentOp = true
        }
        if !hasContentOp {
            return .changedNothing
        }

        var targets: [UndoSwapTarget] = []
        for change in draft.changes where change.before != change.after {
            targets.append(UndoSwapTarget(
                url: draft.workingFolderURL.appendingPathComponent(change.relativePath),
                relativePath: change.relativePath,
                expected: change.before,
                replacement: change.after
            ))
        }

        let seq: Int
        do {
            seq = try begin(draft, ops: ops, in: journal, mode: mode)
        } catch UndoJournalError.notTheNewestStep where mode == .live {
            return .anotherChangeIsUnderWay
        } catch {
            if mode == .live {
                UndoTrailHook.couldNotRecord(draft: draft, change: .nothingWasChanged, problem: error)
                return .couldNotRecordTheStep
            }
            // Shadow: the change goes ahead exactly as it would have, all
            // of it or none, its staged names noted so a kill part way
            // leaves nothing of Plantoir's in the course for long. The trail
            // line says what then happened (the U3 sweep, finding 2).
            switch UndoShadowStaging.swap(targets, noting: journal) {
            case .swapped:
                UndoTrailHook.couldNotRecord(draft: draft, change: .wentAhead, problem: error)
                return .appliedWithoutARecord
            case .refused(let refusal):
                UndoTrailHook.couldNotRecord(draft: draft, change: .nothingWasChanged, problem: error)
                return .refused(refusal)
            case .notPutBack(let refusal, let keptOriginals):
                UndoTrailHook.couldNotRecord(draft: draft, change: .stoppedPartWay, problem: error)
                return .leftPartWay(refusal, keptOriginals: keptOriginals)
            case .stoppedByATest:
                return .stoppedByATest
            }
        }

        if UndoKillPoints.stopsHere(.afterBegin) {
            return .stoppedByATest
        }

        switch UndoSwap.swap(targets, label: "\(seq)-apply", root: draft.workingFolderURL) {
        case .refused(let refusal):
            finish(seq: seq, with: .failed, phase: .begin, reason: "refused", in: journal, mode: mode)
            return .refused(refusal)
        case .notPutBack(let refusal, let keptOriginals):
            // Left IN FLIGHT, never `failed`: a page may be new with its
            // original beside it, so recovery settles it from the content
            // once this process is gone (`undo.rule.recovery`).
            return .leftPartWay(refusal, keptOriginals: keptOriginals)
        case .stoppedByATest:
            return .stoppedByATest
        case .swapped:
            break
        }

        if UndoKillPoints.stopsHere(.beforeApplied) {
            return .stoppedByATest
        }
        finish(seq: seq, with: .applied, phase: nil, reason: nil, in: journal, mode: mode)
        return .applied(seq: seq)
    }

    /// Phase one: under the lock, run recovery, take the next number, store
    /// the content, append `begin`, and sync. The redo branch is cut when the
    /// step is APPLIED, not here, so a step that is refused or never written
    /// leaves Redo as it was (the core review's M3).
    static func begin(
        _ draft: UndoStepDraft,
        ops: [UndoOp],
        in journal: UndoJournal,
        mode: UndoMode
    ) throws -> Int {
        let folderID: String = try FolderIdentityFile.identifier(forWorkingFolder: draft.workingFolderURL)
        let wait: Double = mode == .live ? UndoSwitch.lockWaitSeconds : UndoSwitch.shadowLockWaitSeconds
        return try journal.withLock(waitingAtMost: wait, inShadow: mode == .shadow) { writer in
            UndoRecovery.run(writer, mode: mode, trySwapsNow: false, resolveRoot: UndoReach.root)
            if mode == .live, let waiting = UndoRecovery.deadStepThatKeepsAFileTrue(writer, course: draft.course) {
                throw UndoJournalError.notTheNewestStep(waiting)
            }
            var wholeFilePaths: Set<String> = []
            for op in ops where op.knownKind == .writeFile {
                if let path = op.path {
                    wholeFilePaths.insert(path)
                }
            }
            for change in draft.changes where wholeFilePaths.contains(change.relativePath) {
                if let before = change.before {
                    try writer.writeBlob(before)
                }
                if let after = change.after {
                    try writer.writeBlob(after)
                }
            }
            let seq: Int = writer.fold.highestSeq + 1
            let step: UndoStep = UndoStep(
                seq: seq,
                madeAt: UndoMoment.text(journal.now()),
                action: draft.action,
                madeBy: draft.madeBy,
                workingFolder: UndoWorkingFolder(id: folderID, pathAtTheTime: draft.workingFolderPath),
                course: draft.course,
                section: draft.section,
                actionClass: draft.actionClass,
                holds: draft.holds,
                ops: ops
            )
            try writer.append(UndoEventLine(seq: seq, event: .begin, step: step, process: journal.process))
            try writer.sync()
            return seq
        }
    }

    /// Phase three: append the closing event and prune. When the event is
    /// `applied`, every undone step below it is dropped first: the new step
    /// cut the redo branch. When the lock cannot be had, the closing event
    /// is kept and written at this process's next lock, so the step is not
    /// left in flight for the life of the process (the core review's I3).
    static func finish(
        seq: Int,
        with event: UndoEventKind,
        phase: UndoPhase?,
        reason: String?,
        in journal: UndoJournal,
        mode: UndoMode
    ) {
        // Longer than a begin waits: a step left unfinished holds Undo back
        // until its process has gone and recovery settles it.
        let wait: Double = mode == .live ? UndoSwitch.finishWaitSeconds : UndoSwitch.shadowLockWaitSeconds
        let closing: UndoEventLine = UndoEventLine(seq: seq, event: event, phase: phase, reason: reason)
        do {
            try journal.withLock(waitingAtMost: wait, inShadow: mode == .shadow) { writer in
                if event == .applied {
                    JournaledWrite.dropTheRedoBranch(below: seq, writer)
                }
                try writer.append(closing)
                // Recovery before the prune, in this hold (the Windows
                // recovery review's 14).
                UndoRecovery.run(writer, mode: mode, trySwapsNow: false, resolveRoot: UndoReach.root)
                UndoPruning.prune(writer, mode: mode)
            }
        } catch {
            UndoFoldCache.keepPendingClosing(closing, for: journal.folderURL)
            UndoTrailHook.couldNotFinish(seq: seq, event: event, problem: error)
        }
    }

    /// Drops every undone step below a step that has just taken effect.
    static func dropTheRedoBranch(below seq: Int, _ writer: UndoJournalWriter) {
        for record in writer.fold.stepsOnTheList where record.phase == .undone && record.step.seq < seq {
            try? writer.append(UndoEventLine(seq: record.step.seq, event: .dropped, reason: "newStep"))
        }
    }

    // MARK: - A step given as ops (U2's kinds)

    /// Records a step given as its ops (any kind this version defines),
    /// then makes it: the begin is on the disk first, with every blob the
    /// ops need; then the ops are planned FORWARD from what is on the disk,
    /// exactly as a Redo plans them, so a step is made by the same check
    /// and the same staged swap that later undoes and redoes it; then
    /// `applied`. Refused (and closed `failed`) when anything is not as the
    /// step expects. The kinds U1 writes keep `perform`, which works their
    /// ops out from the files' before and after.
    ///
    /// U2 adds the door; the actions that will use it (a rollover's marker
    /// moves, New Course's tree, a preference) are wired by U3 and U4, and
    /// how a shadow step of these kinds is recorded beside an action's own
    /// writes is settled there. Here a list that cannot be written refuses
    /// the step before anything changes, in either mode.
    static func perform(
        ops draft: UndoOpsDraft,
        in journal: UndoJournal,
        mode: UndoMode,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) -> JournaledWriteOutcome {
        var hasContentOp: Bool = false
        for op in draft.ops where op.knownKind != .recompute {
            hasContentOp = true
        }
        if !hasContentOp {
            return .changedNothing
        }
        // Nothing changes until the step is one every reader can undo: it
        // reads back readable (every shape and the wholeOps rule), every
        // path stays inside the working folder through its links, and every
        // blob it names is given or already held, with the right hash (the
        // hard review of U2b, HIGH 1).
        switch JournaledWrite.vet(draft, in: journal) {
        case .acceptable:
            break
        case .refused:
            return .refused(.notReadable)
        case .listUnreadable:
            return .couldNotRecordTheStep
        }
        let seq: Int
        do {
            seq = try beginOps(draft, in: journal, mode: mode, places: places)
        } catch UndoJournalError.notTheNewestStep where mode == .live {
            return .anotherChangeIsUnderWay
        } catch {
            return .couldNotRecordTheStep
        }
        if UndoKillPoints.stopsHere(.afterBegin) {
            return .stoppedByATest
        }
        let root: URL = draft.workingFolderURL ?? URL(fileURLWithPath: "/", isDirectory: true)
        let plan: UndoPlan = UndoCheck.plan(draft.ops, direction: .forward, root: root, journal: journal, places: places)
        guard case .ready(let targets, let recomputes, _) = plan else {
            finish(seq: seq, with: .failed, phase: .begin, reason: "refused", in: journal, mode: mode)
            if case .refused(let refusal) = plan {
                return .refused(refusal)
            }
            // Content the step needs is in the list and cannot be read just
            // now: nothing was changed, and the step is not made.
            return .couldNotRecordTheStep
        }
        switch UndoSwap.swap(targets, label: "\(seq)-apply", places: places, root: draft.workingFolderURL) {
        case .refused(let refusal):
            finish(seq: seq, with: .failed, phase: .begin, reason: "refused", in: journal, mode: mode)
            return .refused(refusal)
        case .notPutBack(let refusal, let keptOriginals):
            // A one-file JSON step (a Course Settings field, Set School
            // Year) is judged at once by content and closed, as recovery
            // would close it, so nothing is left in flight while the app is
            // open (#899, Russell's ruling of 2026-11-26).
            if mode == .live && UndoStoppedStep.isOneFileJSONStep(draft.ops) {
                return JournaledWrite.closedAtOnce(seq: seq, refusal: refusal, in: journal, places: places)
            }
            // Left IN FLIGHT, never `failed`: a page may be new with its
            // original beside it, so recovery settles it from the content
            // once this process is gone (`undo.rule.recovery`).
            return .leftPartWay(refusal, keptOriginals: keptOriginals)
        case .stoppedByATest:
            return .stoppedByATest
        case .swapped:
            break
        }
        if UndoKillPoints.stopsHere(.beforeApplied) {
            return .stoppedByATest
        }
        // Re-derived by the caller once this answers
        // (`performAndRederive(ops:)`), outside the lock.
        _ = recomputes
        finish(seq: seq, with: .applied, phase: nil, reason: nil, in: journal, mode: mode)
        return .applied(seq: seq)
    }

    /// The door's answer for a one-file JSON step judged at once after it
    /// stopped part way: made, put back (nothing changed, said as a
    /// refusal is), or left for the caller to offer Put It Back.
    static func closedAtOnce(
        seq: Int, refusal: UndoRefusal, in journal: UndoJournal, places: UndoExternalPlaces
    ) -> JournaledWriteOutcome {
        switch UndoStoppedStep.judgeAtOnce(seq: seq, in: journal, places: places) {
        case .finished(let finishedSeq):
            return .applied(seq: finishedSeq)
        case .putBack:
            return .refused(refusal)
        case .couldNotFinish(let leftSeq):
            return .couldNotFinish(seq: leftSeq, refusal)
        case .notMade:
            return .notMade(seq: seq)
        }
    }

    /// What the door found when it vetted a step before writing anything.
    enum Vetting: Equatable {
        case acceptable
        case refused
        case listUnreadable
    }

    /// The checks `perform(ops:)` makes before the begin line.
    static func vet(_ draft: UndoOpsDraft, in journal: UndoJournal) -> Vetting {
        // 1. Read back as a reader of this version reads it.
        var folder: UndoWorkingFolder? = nil
        if let url = draft.workingFolderURL {
            folder = UndoWorkingFolder(id: "00000000-0000-0000-0000-000000000000", pathAtTheTime: url.path)
        }
        let step: UndoStep = UndoStep(
            seq: 1, madeAt: UndoMoment.text(journal.now()), action: draft.action, madeBy: draft.madeBy,
            workingFolder: folder, course: draft.course, section: draft.section,
            actionClass: draft.actionClass, holds: draft.holds, ops: draft.ops
        )
        guard let encoded = try? JSONEncoder().encode(step),
              let readBack = try? JSONDecoder().decode(UndoStep.self, from: encoded),
              readBack.isReadable else {
            return .refused
        }
        // 2. Every path inside the working folder, its links resolved. A
        // file change at a place a link's move hands over is judged on the
        // folders above it only, as the plan judges it (U4b3 door-1): the
        // link standing there is moved, never written through, wherever it
        // leads (U4b3 door-5, a link leading out of the working folder).
        var judgedAbove: Set<Int> = []
        for handover in UndoCheck.handovers(in: readBack.ops) where handover.aLinkMoves {
            judgedAbove.insert(handover.leaverIndex)
            judgedAbove.insert(handover.fillerIndex)
        }
        var opIndex: Int = 0
        for op in readBack.ops {
            let aboveOnly: Bool = judgedAbove.contains(opIndex) && !op.isWhole
            opIndex += 1
            for path in op.pathsNamed {
                guard let root = draft.workingFolderURL else {
                    return .refused
                }
                let inside: Bool = aboveOnly
                    ? UndoPlaces.staysInsideAbove(root, path)
                    : UndoPlaces.staysInside(root, path, namedBy: op)
                if !inside {
                    return .refused
                }
            }
        }
        // 3. Every blob it names, given or already held, hashing to its name.
        var given: [String: Data] = [:]
        for blob in draft.blobs {
            given[UndoHash.sha256(of: blob)] = blob
        }
        func content(_ name: String) throws -> Data? {
            if let data = given[name] {
                return data
            }
            return try journal.blobContent(sha: name)
        }
        do {
            for op in readBack.ops {
                for name in op.namedBlobs where try content(name) == nil {
                    return .refused
                }
                if op.knownKind == .createTree || op.knownKind == .removeTree, let listingSha = op.listingSha {
                    guard let data = try content(listingSha), let listing = UndoTreeListing.parse(data) else {
                        return .refused
                    }
                    for file in listing.files where !(op.blobs ?? []).contains(file.sha) {
                        return .refused
                    }
                }
            }
        } catch {
            return .listUnreadable
        }
        return .acceptable
    }

    /// `perform(ops:)`, then the re-derivation of the step's `recompute`
    /// files, awaited outside the lock (`UndoMaintainers`). In shadow too:
    /// the door made the change itself, so it keeps the files a rule keeps
    /// true itself (the hard review of U2b, LOW c).
    @concurrent
    static func performAndRederive(
        ops draft: UndoOpsDraft,
        in journal: UndoJournal,
        mode: UndoMode,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) async -> JournaledWriteOutcome {
        // A step that died part way and keeps a file true by a rule is
        // settled AND re-derived first: the recovery inside the begin below
        // leaves such a step for this one (the second hard review, MEDIUM 1).
        if mode == .live {
            await UndoRecovery.recoverAndRederive(journal, resolveRoot: { folder in UndoReach.root(for: folder) }, places: places)
        }
        let outcome: JournaledWriteOutcome = perform(ops: draft, in: journal, mode: mode, places: places)
        if case .applied = outcome, let root = draft.workingFolderURL {
            await UndoMaintainers.rederive(draft.ops, root: root)
        } else if case .appliedWithoutARecord = outcome, let root = draft.workingFolderURL {
            await UndoMaintainers.rederive(draft.ops, root: root)
        }
        return outcome
    }

    /// Phase one for a step given as ops: the same as `begin`, with the
    /// draft's own blobs stored and no working folder when none is needed.
    static func beginOps(
        _ draft: UndoOpsDraft,
        in journal: UndoJournal,
        mode: UndoMode,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) throws -> Int {
        var folder: UndoWorkingFolder? = nil
        if let url = draft.workingFolderURL {
            let folderID: String = try FolderIdentityFile.identifier(forWorkingFolder: url)
            folder = UndoWorkingFolder(id: folderID, pathAtTheTime: draft.workingFolderPath ?? url.path)
        }
        let wait: Double = mode == .live ? UndoSwitch.lockWaitSeconds : UndoSwitch.shadowLockWaitSeconds
        return try journal.withLock(waitingAtMost: wait, inShadow: mode == .shadow) { writer in
            UndoRecovery.run(writer, mode: mode, trySwapsNow: false, resolveRoot: UndoReach.root, places: places)
            if mode == .live, let waiting = UndoRecovery.deadStepThatKeepsAFileTrue(writer, course: draft.course) {
                throw UndoJournalError.notTheNewestStep(waiting)
            }
            for blob in draft.blobs {
                try writer.writeBlob(blob)
            }
            let seq: Int = writer.fold.highestSeq + 1
            let step: UndoStep = UndoStep(
                seq: seq,
                madeAt: UndoMoment.text(journal.now()),
                action: draft.action,
                madeBy: draft.madeBy,
                workingFolder: folder,
                course: draft.course,
                section: draft.section,
                actionClass: draft.actionClass,
                holds: draft.holds,
                ops: draft.ops
            )
            try writer.append(UndoEventLine(seq: seq, event: .begin, step: step, process: journal.process))
            try writer.sync()
            return seq
        }
    }

    // MARK: - Shadow recording beside an action's own writes

    /// Writes the `begin` of a step whose change the ACTION will make itself.
    /// Never throws and never blocks for long: while the switch is off, a
    /// list that cannot be written leaves a trail line and nothing else.
    static func beginInShadow(_ draft: UndoStepDraft, in journal: UndoJournal) -> UndoShadowTicket? {
        let ops: [UndoOp] = ops(for: draft)
        var hasContentOp: Bool = false
        for op in ops where op.knownKind != .recompute {
            hasContentOp = true
        }
        if !hasContentOp {
            return nil
        }
        do {
            let seq: Int = try begin(draft, ops: ops, in: journal, mode: .shadow)
            return UndoShadowTicket(seq: seq, draft: draft)
        } catch {
            UndoTrailHook.couldNotRecord(draft: draft, change: .wentAhead, problem: error)
            return nil
        }
    }

    /// Closes a shadow step with what the action actually wrote: for each
    /// file it wrote, the bytes it left (nil: removed). When that is exactly
    /// what was recorded, the step is `applied`; otherwise it is `failed`
    /// with a reason and leaves the list, because a record that differs from
    /// the change would undo the wrong thing. Writes nothing into the working
    /// folder in any case. A nil `actuallyWritten` means the action stopped.
    ///
    /// Only what was WRITTEN is compared, not what each file held before: the
    /// record's before is the disk's own bytes, while an action may have read
    /// the file through `String(contentsOf:)`, which drops a byte-order mark
    /// (measured), and so remember a different before for the same file.
    static func finishInShadow(
        _ ticket: UndoShadowTicket?,
        actuallyWritten: [String: Data?]?,
        in journal: UndoJournal
    ) {
        guard let ticket else {
            return
        }
        guard let actuallyWritten else {
            finish(seq: ticket.seq, with: .failed, phase: .begin, reason: "actionStopped", in: journal, mode: .shadow)
            return
        }
        if wroteWhatWasRecorded(ticket.draft.changes, actuallyWritten) {
            finish(seq: ticket.seq, with: .applied, phase: nil, reason: nil, in: journal, mode: .shadow)
            return
        }
        finish(seq: ticket.seq, with: .failed, phase: .begin, reason: "differedFromTheRecord", in: journal, mode: .shadow)
        UndoTrailHook.couldNotRecord(
            draft: ticket.draft, change: .wentAhead, problem: UndoShadowMismatch.differedFromTheRecord
        )
    }

    /// Whether the files written, and what each was left holding, are the
    /// ones the record says.
    static func wroteWhatWasRecorded(_ recorded: [UndoFileChange], _ written: [String: Data?]) -> Bool {
        var recordedAfter: [String: Data?] = [:]
        for change in recorded where change.before != change.after {
            recordedAfter[change.relativePath] = change.after
        }
        if recordedAfter.count != written.count {
            return false
        }
        for (path, after) in written {
            guard let expected = recordedAfter[path] else {
                return false
            }
            if expected != after {
                return false
            }
        }
        return true
    }

    // MARK: - The trace replayer's writer

    /// A page's text with one top-level key's entry set to `line`: the entry
    /// replaced when the key is there once, inserted at the top of the block
    /// when it is not, and a block made when the page has none. The writer
    /// the traces in `contracts/undo-traces.json` describe their steps with,
    /// so both apps make byte-identical changes from the same data. Nil when
    /// the key is there more than once.
    ///
    /// A leading byte-order mark is DROPPED first, because that is what
    /// today's publish does: it reads the page with `String(contentsOf:)`,
    /// which drops one (measured), as .NET's `File.ReadAllText` does, and
    /// writes the text back without it (the contract review's INCOMPLETE 5).
    static func settingEntry(key: String, to line: String, in pageText: String) -> String? {
        var text: String = pageText
        if text.unicodeScalars.first == "\u{FEFF}" {
            text = String(String.UnicodeScalarView(text.unicodeScalars.dropFirst()))
        }
        guard let layout = UndoFrontMatter.layout(of: text) else {
            return "---\n" + line + "\n---\n" + text
        }
        let found: [UndoFrontMatter.Entry] = layout.entries(forKey: key)
        if found.count > 1 {
            return nil
        }
        var lines: [String] = layout.lines
        if let entry = found.first {
            // The new entry keeps the carriage return of the line it replaces.
            var replacement: String = line
            if lines[entry.start].hasSuffix("\r") && !line.hasSuffix("\r") {
                replacement += "\r"
            }
            lines.replaceSubrange(entry.start..<entry.end, with: [replacement])
            return lines.joined(separator: "\n")
        }
        var replacement: String = line
        if lines[layout.openIndex].hasSuffix("\r") && !line.hasSuffix("\r") {
            replacement += "\r"
        }
        lines.insert(replacement, at: layout.openIndex + 1)
        return lines.joined(separator: "\n")
    }
}

/// A shadow step written down, waiting for the action to finish.
nonisolated struct UndoShadowTicket: Sendable {

    // MARK: - Stored properties

    let seq: Int

    let draft: UndoStepDraft
}

/// Why a shadow step was not kept.
nonisolated enum UndoShadowMismatch: Error {
    case differedFromTheRecord
}

/// Text from bytes and back, exactly.
nonisolated enum UndoText {

    // MARK: - Functions

    /// The bytes as text, or nil when they are not UTF-8 exactly: decoding
    /// and encoding again must give the same bytes, so a byte-order mark is
    /// kept and an invalid sequence is refused rather than replaced.
    static func decode(_ data: Data) -> String? {
        let text: String = String(decoding: data, as: UTF8.self)
        if Data(text.utf8) != data {
            return nil
        }
        return text
    }

    /// Byte-for-byte equality. Swift's `==` on strings is canonical
    /// equivalence, which calls a precomposed é equal to a decomposed one:
    /// that is not what "exactly as the step left it" means.
    static func same(_ first: String?, _ second: String?) -> Bool {
        guard let first, let second else {
            return first == nil && second == nil
        }
        return Data(first.utf8) == Data(second.utf8)
    }
}

/// A page's front matter as lines and top-level entries.
///
/// The block is found with the reader both apps use
/// (`PageVisibilityReader.fenceIndices`: three dashes or more, blank lines
/// allowed before the opening fence). An ENTRY is a top-level key's line
/// and the lines its value runs on to: lines that start with a space or a
/// tab, and column-0 sequence items. A blank line, a column-0 comment or the
/// next key ends it. Lines are split on the line feed alone, so a carriage
/// return stays on its line and is compared like any other byte.
nonisolated struct UndoFrontMatter {

    // MARK: - Stored properties

    let lines: [String]

    let openIndex: Int

    let closeIndex: Int

    let entries: [Entry]

    /// One top-level key and the lines it spans, `start..<end`.
    struct Entry: Equatable {

        // MARK: - Stored properties

        let key: String

        let start: Int

        let end: Int
    }

    // MARK: - Functions

    static func layout(of text: String) -> UndoFrontMatter? {
        guard let fences = PageVisibilityReader.fenceIndices(in: text) else {
            return nil
        }
        let lines: [String] = text.components(separatedBy: "\n")
        var entries: [Entry] = []
        var index: Int = fences.openIndex + 1
        while index < fences.closeIndex {
            guard let key = topLevelKey(inLine: lines[index]) else {
                index += 1
                continue
            }
            var end: Int = index + 1
            while end < fences.closeIndex && continuesAValue(lines[end]) {
                end += 1
            }
            entries.append(Entry(key: key, start: index, end: end))
            index = end
        }
        return UndoFrontMatter(lines: lines, openIndex: fences.openIndex, closeIndex: fences.closeIndex, entries: entries)
    }

    /// The key a column-0 line names, quotes taken off, or nil.
    static func topLevelKey(inLine rawLine: String) -> String? {
        let line: String = PageFrontmatter.trimmingCarriageReturn(rawLine)
        guard let first = line.first else {
            return nil
        }
        if first == " " || first == "\t" || first == "#" || first == "-" {
            return nil
        }
        guard let colon = line.firstIndex(of: ":") else {
            return nil
        }
        var key: String = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        if key.count >= 2 {
            let opening: Character = key[key.startIndex]
            let closing: Character = key[key.index(before: key.endIndex)]
            if (opening == "\"" || opening == "'") && closing == opening {
                key = String(key.dropFirst().dropLast())
            }
        }
        if key.isEmpty {
            return nil
        }
        return key
    }

    /// Whether a line carries on the value of the entry above it.
    static func continuesAValue(_ rawLine: String) -> Bool {
        let line: String = PageFrontmatter.trimmingCarriageReturn(rawLine)
        guard let first = line.first else {
            return false
        }
        if first == " " || first == "\t" {
            return !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return first == "-" && !line.hasPrefix("---")
    }

    func entries(forKey key: String) -> [Entry] {
        var found: [Entry] = []
        for entry in entries where entry.key == key {
            found.append(entry)
        }
        return found
    }

    /// The entry's lines joined with a line feed.
    func text(of entry: Entry) -> String {
        var part: [String] = []
        var index: Int = entry.start
        while index < entry.end {
            part.append(lines[index])
            index += 1
        }
        return part.joined(separator: "\n")
    }

    /// The key of the entry just before this one, or nil for the first.
    func keyBefore(_ entry: Entry) -> String? {
        var previous: String? = nil
        for candidate in entries {
            if candidate.start == entry.start {
                return previous
            }
            previous = candidate.key
        }
        return previous
    }
}

/// Where an `editLine` op's key stands in some text.
nonisolated enum UndoEntryReading: Equatable {
    /// No such key at the top level (or no front matter at all).
    case absent
    /// Exactly one entry, with this text.
    case entry(String)
    /// The key more than once, or the page cannot be read: never a guess.
    case unreadable
}

/// The `editLine` op: reading, applying, and finding them in a change.
nonisolated enum UndoLineOps {

    // MARK: - Functions

    /// How an op's key reads in this text.
    static func reading(key: String, in text: String) -> UndoEntryReading {
        guard let layout = UndoFrontMatter.layout(of: text) else {
            if PageVisibilityReader.pageTextOpensAFence(text) {
                return .unreadable
            }
            return .absent
        }
        let found: [UndoFrontMatter.Entry] = layout.entries(forKey: key)
        if found.isEmpty {
            return .absent
        }
        if found.count > 1 {
            return .unreadable
        }
        return .entry(layout.text(of: found[0]))
    }

    /// Whether a reading is what an entry text (nil: absent) says.
    static func reading(_ reading: UndoEntryReading, matches expected: String?) -> Bool {
        switch reading {
        case .absent:
            return expected == nil
        case .entry(let text):
            guard let expected else {
                return false
            }
            return UndoText.same(text, expected)
        case .unreadable:
            return false
        }
    }

    /// The text with the op's key moved from `from` to `to` (each nil for
    /// absent), or nil when the text does not read `from`.
    static func moving(_ op: UndoOp, from: String?, to: String?, in text: String) -> String? {
        guard let key = op.key else {
            return nil
        }
        let current: UndoEntryReading = reading(key: key, in: text)
        if !reading(current, matches: from) {
            return nil
        }
        if UndoText.same(from, to) {
            return text
        }
        guard let layout = UndoFrontMatter.layout(of: text) else {
            // No block: only a step that made one can put an entry here.
            guard let to, op.createdTheBlock == true else {
                return nil
            }
            return "---\n" + to + "\n---\n" + text
        }
        var lines: [String] = layout.lines
        let found: [UndoFrontMatter.Entry] = layout.entries(forKey: key)
        if let entry = found.first {
            if let to {
                lines.replaceSubrange(entry.start..<entry.end, with: to.components(separatedBy: "\n"))
                return lines.joined(separator: "\n")
            }
            lines.removeSubrange(entry.start..<entry.end)
            let wasTheOnlyEntry: Bool = layout.entries.count == 1
            let blockIsNowEmpty: Bool = wasTheOnlyEntry && layout.closeIndex - layout.openIndex - 1 == entry.end - entry.start
            if op.createdTheBlock == true && blockIsNowEmpty && layout.openIndex == 0 {
                // Both fences go, and the line feed after the closing one.
                lines.removeSubrange(0..<2)
            }
            return lines.joined(separator: "\n")
        }
        guard let to else {
            return text
        }
        var insertAt: Int = layout.openIndex + 1
        if let afterKey = op.afterKey {
            let anchors: [UndoFrontMatter.Entry] = layout.entries(forKey: afterKey)
            if anchors.count == 1 {
                insertAt = anchors[0].end
            }
        }
        lines.insert(contentsOf: to.components(separatedBy: "\n"), at: insertAt)
        return lines.joined(separator: "\n")
    }

    /// The `editLine` ops that turn `before` into `after`, or nil when the
    /// change is not only front-matter entries or the ops do not reproduce
    /// it exactly in both directions.
    static func ops(path: String, before: String, after: String) -> [UndoOp]? {
        if UndoText.same(before, after) {
            return []
        }
        let afterLayout: UndoFrontMatter? = UndoFrontMatter.layout(of: after)
        guard let afterLayout else {
            return nil
        }
        let beforeLayout: UndoFrontMatter? = UndoFrontMatter.layout(of: before)
        var result: [UndoOp] = []

        guard let beforeLayout else {
            // The step gave the page its front matter: one entry, made whole.
            if afterLayout.entries.count != 1 {
                return nil
            }
            let entry: UndoFrontMatter.Entry = afterLayout.entries[0]
            result.append(UndoOp.editLine(
                path: path, key: entry.key, before: nil,
                after: afterLayout.text(of: entry), afterKey: nil, createdTheBlock: true
            ))
            return verified(result, before: before, after: after)
        }

        var seenKeys: Set<String> = []
        for entry in afterLayout.entries {
            if seenKeys.contains(entry.key) {
                return nil
            }
            seenKeys.insert(entry.key)
            let inBefore: [UndoFrontMatter.Entry] = beforeLayout.entries(forKey: entry.key)
            if inBefore.count > 1 {
                return nil
            }
            let afterText: String = afterLayout.text(of: entry)
            var beforeText: String? = nil
            if let found = inBefore.first {
                beforeText = beforeLayout.text(of: found)
            }
            if UndoText.same(beforeText, afterText) {
                continue
            }
            result.append(UndoOp.editLine(
                path: path, key: entry.key, before: beforeText, after: afterText,
                afterKey: afterLayout.keyBefore(entry), createdTheBlock: false
            ))
        }
        for entry in beforeLayout.entries where !seenKeys.contains(entry.key) {
            if beforeLayout.entries(forKey: entry.key).count > 1 {
                return nil
            }
            seenKeys.insert(entry.key)
            result.append(UndoOp.editLine(
                path: path, key: entry.key, before: beforeLayout.text(of: entry), after: nil,
                afterKey: beforeLayout.keyBefore(entry), createdTheBlock: false
            ))
        }
        if result.isEmpty {
            return nil
        }
        return verified(result, before: before, after: after)
    }

    /// The ops, if applying them forward to `before` gives `after` and
    /// backward to `after` gives `before`, byte for byte.
    static func verified(_ ops: [UndoOp], before: String, after: String) -> [UndoOp]? {
        var forward: String = before
        for op in ops {
            guard let moved = moving(op, from: op.before, to: op.after, in: forward) else {
                return nil
            }
            forward = moved
        }
        if !UndoText.same(forward, after) {
            return nil
        }
        var backward: String = after
        var index: Int = ops.count - 1
        while index >= 0 {
            let op: UndoOp = ops[index]
            guard let moved = moving(op, from: op.after, to: op.before, in: backward) else {
                return nil
            }
            backward = moved
            index -= 1
        }
        if !UndoText.same(backward, before) {
            return nil
        }
        return ops
    }
}

/// The places a test or the harness stops a step, to prove what recovery
/// does with a process that dies there. Nil in the app: reaching a point
/// costs one check.
nonisolated enum UndoKillPoint: Equatable, Sendable {
    case afterBegin
    /// An undo or redo has checked its ops and has written nothing yet: a
    /// contract case begins another process's step here, to prove a
    /// clearing takes a step in flight (`undo.rule.clearing`).
    case afterTheCheck
    case beforeSwap(Int)
    case beforeApplied
    case afterUndoing
    case beforeUndone
    case afterRedoing
    case beforeRedone
    /// A swap that took a folder out has renamed it to its `-gone` name
    /// and has not finished deleting it.
    case whileDeletingAFolder
    /// Recovery has tidied what a dead process left (a folder put back or
    /// kept under a visible name) and has written nothing to the list yet.
    case afterRecoveryTidied
}

nonisolated enum UndoKillPoints {

    // MARK: - Stored properties

    /// Answers true to stop the work at a point, exactly as a process that
    /// died there would stop: no reversal, no tidying, no journal event. A
    /// harness may instead end its own process there with `SIGKILL`. Set
    /// only by tests and the harness.
    nonisolated(unsafe) static var hook: ((UndoKillPoint) -> Bool)?

    /// Answers true to make the swap at this index fail as a file another
    /// program holds would (Windows' fact 5): the swaps already made are
    /// reversed and the file is named.
    nonisolated(unsafe) static var fileInUseAtSwap: ((Int) -> Bool)?

    /// Answers true to make the staging write at this index fail as a full
    /// disk does: the staged file is CREATED, then writing into it fails
    /// (measured by the Fable sweep of U1 on a 3 MB disk image: the file is
    /// left at 0 bytes). Set only by tests.
    nonisolated(unsafe) static var stagingWriteFailsAt: ((Int) -> Bool)?

    /// Answers true to make a read of the list fail as a failing disk or a
    /// network home that drops mid-read does (`UndoFileReads`). Set only by
    /// tests.
    nonisolated(unsafe) static var readOfTheListFails: (() -> Bool)?

    /// Answers true to make opening this file of the list (a segment, a
    /// blob, or a working folder's identifier file) fail as a failing disk,
    /// a permission or too many open files does (`UndoFileReads.openFile`):
    /// never as a file that is gone. Set only by tests.
    nonisolated(unsafe) static var openFails: ((URL) -> Bool)?

    /// Answers an error number to make keeping the original at this index
    /// fail as the copy a volume without hard links falls back to does
    /// (`UndoSwap.keep`); nil lets it go ahead. Set only by tests.
    nonisolated(unsafe) static var keepingTheOriginalFails: ((Int) -> Int32?)?

    /// Called with a file's index and the name its original is about to be
    /// kept under, after that name was found free and before the original
    /// is kept there: a test puts a file at that name, as another Mac
    /// syncing the folder could in that instant (the first review of U3c,
    /// LOW 4). Set only by tests.
    nonisolated(unsafe) static var beforeKeepingTheOriginal: ((Int, URL) -> Void)?

    /// Called with a file's index and place just after its original is kept
    /// and before the new content is renamed in: a test edits the file IN
    /// PLACE there, as another program racing the swap would. Set only by
    /// tests.
    nonisolated(unsafe) static var beforeTheRename: ((Int, URL) -> Void)?

    /// Answers true to make putting a file back fail at this index while a
    /// swap is being reversed, as a file another program holds does on
    /// Windows. Set only by tests.
    nonisolated(unsafe) static var putBackFailsAt: ((Int) -> Bool)?

    /// Called with the list's folder once its segments are listed and
    /// before any of them is opened: a test takes a segment away there, as
    /// a sync service or a person could in that instant (#1004). Set only
    /// by tests.
    nonisolated(unsafe) static var afterTheSegmentsAreListed: ((URL) -> Void)?

    /// Called with an identifier file's place once its bytes were read and
    /// found to hold no identifier, before anything else looks at the name:
    /// a test puts a good file there, as another process could in that
    /// instant (#1004). Set only by tests.
    nonisolated(unsafe) static var afterAnIdentifierFileIsRead: ((URL) -> Void)?

    /// Called with an identifier file's place after the last look that it
    /// is still the file read and before it is renamed aside (#1004). Set
    /// only by tests.
    nonisolated(unsafe) static var beforeAnIdentifierFileIsSetAside: ((URL) -> Void)?

    /// Called with an identifier file's place just before a file set aside
    /// from it is put back: a test takes the name there, as a third process
    /// could (#1004). Set only by tests.
    nonisolated(unsafe) static var beforeAnIdentifierFileIsPutBack: ((URL) -> Void)?

    // MARK: - Functions

    static func stopsHere(_ point: UndoKillPoint) -> Bool {
        guard let hook else {
            return false
        }
        return hook(point)
    }
}

/// What became of a change the list could not record, as the
/// `undo could not record a step` line says it: written only once that is
/// known, never before the write that can still refuse (the U3 sweep,
/// finding 2: the line said "The change went ahead" before a shadow swap
/// that refused, always for a page that is a link).
nonisolated enum UndoUnrecordedChange: Equatable, Sendable {
    /// Made, all of it, without a record (switch off).
    case wentAhead
    /// Refused before anything changed.
    case nothingWasChanged
    /// Refused part way: some files hold the new content, what each held
    /// before kept beside it.
    case stoppedPartWay
    /// Made and recorded, but its closing line could not be written now;
    /// it is written at this process's next lock.
    case madeButNotClosed
}

/// How the list reaches the activity trail. The core leaves it empty so it
/// compiles on its own; the app sets it (`UndoTrail.install()`).
nonisolated enum UndoTrailHook {

    // MARK: - Stored properties

    /// A step could not be written down: the action's key, the course and
    /// section, what became of the change, and a word for why. Never page
    /// text.
    nonisolated(unsafe) static var couldNotRecordLine: ((_ action: String, _ course: String, _ section: Int?, _ change: UndoUnrecordedChange, _ why: String) -> Void)?

    /// Recovery or a failed swap put files back: the course and section,
    /// what it ended, and how many files.
    nonisolated(unsafe) static var rolledBackLine: ((_ course: String, _ section: Int?, _ phase: UndoPhase, _ files: Int) -> Void)?

    /// Recovery found a step half applied with a file changed by hand in the
    /// way: the course and section, what it ended, how many files were put
    /// back and how many were in the way. The list was cleared.
    nonisolated(unsafe) static var interruptedLine: ((_ course: String, _ section: Int?, _ phase: UndoPhase, _ putBack: Int, _ inTheWay: Int) -> Void)?

    /// Recovery could not put back a step left part way, because content it
    /// needs is gone from the list and no kept original beside its page
    /// matches: the course and section, what it ended, how many files were
    /// left part way, and the hidden name of every kept original still
    /// beside its page (never removed: the only copy of what it held). The
    /// list was cleared.
    nonisolated(unsafe) static var couldNotPutBackLine: ((_ course: String, _ section: Int?, _ phase: UndoPhase, _ leftPartWay: Int, _ keptOriginals: [String]) -> Void)?

    /// Recovery settled a step left part way (made, nothing taken effect, or
    /// put back) and kept beside a page a kept original that the list does
    /// not hold, such as an edit another program made as the swap went in:
    /// the course and section, what it ended, and each kept original's
    /// hidden name. Never removed: the only copy of what it holds.
    /// `noLongerInTheList` names those whose bytes are exactly what the list
    /// recorded for the page, kept because the list no longer holds that
    /// content (its blob gone, or the list would not take it); every other
    /// one differs from what the list recorded (the first review of U3c,
    /// LOW 2).
    nonisolated(unsafe) static var keptAnOriginalLine: ((_ course: String, _ section: Int?, _ phase: UndoPhase, _ keptOriginals: [String], _ noLongerInTheList: [String]) -> Void)?

    /// An Undo (`isUndo`) or a Redo put a page back from its kept original
    /// and the list would not take all it needs for the step: the course
    /// and section, the hidden name what each page held a moment before is
    /// kept under beside it (`keptOriginals`, the first review of U3c,
    /// MEDIUM), and the hidden name of each kept original it put back whose
    /// bytes the list would not take, which stays beside its page
    /// (`keptOfWhatItHoldsNow`, the second review's MEDIUM). The step stays
    /// on the list with both directions offered: the next Undo or Redo of it
    /// uses those files (Russell's ruling of 2026-11-20, night). Every kept
    /// file is given by its path in the working folder (its page's folder
    /// plus its hidden name), and `putBackFromAKeptOriginal` names pages by
    /// their paths, so two pages with the same name in two folders are told
    /// apart (the part-two review of U4b, LOW 4). `pagesOfTheStep` is every
    /// page the step changes, by path, so a named page that shares its file
    /// name with any of them is named by its path (U4b2-4 review 1, LOW 1).
    nonisolated(unsafe) static var keptWhatItReplacedLine: ((_ course: String, _ section: Int?, _ isUndo: Bool, _ keptOriginals: [String], _ keptOfWhatItHoldsNow: [String], _ putBackFromAKeptOriginal: [String], _ pagesOfTheStep: [String]) -> Void)?

    /// An Undo (`isUndo`) or a Redo was refused because the newest step is
    /// a gone process's that recovery has just tried and left: the course
    /// and section, and the refusal, which names the file. The list is kept.
    nonisolated(unsafe) static var leftNewestLine: ((_ course: String, _ section: Int?, _ isUndo: Bool, _ refusal: UndoRefusal) -> Void)?

    /// Recovery found a teacher's folder set aside by a dead process and is
    /// about to put it back in its place though it changed while aside
    /// (with what changed; `keptAs` nil), or to keep it under the visible
    /// name `keptAs` beside its place because something else now holds
    /// that place. The course and section, its place, its hidden name.
    nonisolated(unsafe) static var foundAFolderSetAsideLine: ((_ course: String, _ section: Int?, _ place: String, _ hiddenName: String, _ keptAs: String?, _ changes: String) -> Void)?

    /// U4b3 kept-original-named: recovery is about to keep a page a step
    /// that stopped removed or moved away, found only in its hidden kept
    /// original, under the visible name `keptAs` beside its place, because
    /// something else now holds that place. The course and section, the
    /// place and the visible name, both inside the working folder.
    nonisolated(unsafe) static var keptAPageLine: ((_ course: String, _ section: Int?, _ place: String, _ keptAs: String) -> Void)?

    /// #899, ahead of U5: a restore replacing a course closed a step left
    /// in flight there (`UndoRestoreSetAside`), so recovery never judges the
    /// restored files against it. The course and section, which work had
    /// stopped, how many files the step names, and whether the list could
    /// be reached at all (`closed` false: nothing was closed).
    nonisolated(unsafe) static var setAsideByARestoreLine: ((_ course: String, _ section: Int?, _ phase: UndoPhase, _ files: Int, _ stillJudged: Int, _ closed: Bool) -> Void)?

    // MARK: - Functions

    static func couldNotRecord(draft: UndoStepDraft, change: UndoUnrecordedChange, problem: Error) {
        couldNotRecordLine?(draft.action.key, draft.course, draft.section, change, UndoTrailHook.word(for: problem))
    }

    /// The closing line of a step could not be written: a step that took
    /// effect was made (its closing is written at the next lock); one that
    /// failed changed nothing.
    static func couldNotFinish(seq: Int, event: UndoEventKind, problem: Error) {
        let change: UndoUnrecordedChange = event == .failed ? .nothingWasChanged : .madeButNotClosed
        couldNotRecordLine?("step \(seq)", "", nil, change, UndoTrailHook.word(for: problem))
    }

    /// The line for a change made without a record, by how the write went.
    static func couldNotRecord(
        action: String, course: String, section: Int?, why: String, after outcome: () throws -> Void
    ) throws {
        do {
            try outcome()
        } catch JournaledStepError.leftPartWay(let refusal, let fileName, let keptOriginals) {
            couldNotRecordLine?(action, course, section, .stoppedPartWay, why)
            throw JournaledStepError.leftPartWay(refusal, fileName: fileName, keptOriginals: keptOriginals)
        } catch {
            couldNotRecordLine?(action, course, section, .nothingWasChanged, why)
            throw error
        }
        couldNotRecordLine?(action, course, section, .wentAhead, why)
    }

    /// A word for a problem, never its description (which can carry a path).
    static func word(for problem: Error) -> String {
        if let journalError = problem as? UndoJournalError {
            switch journalError {
            case .lockBusy:
                return "the list was busy"
            case .couldNotOpenTheLock, .couldNotStartASegment, .couldNotStoreContent:
                return "the list could not be written"
            case .couldNotSync:
                return "the list could not be saved to the disk"
            case .couldNotRead:
                return "the list could not be read"
            case .couldNotEncode:
                return "the step could not be written as a line"
            case .notTheNewestStep:
                return "the list had moved on"
            case .identifierBeingMade:
                return "the working folder's identifier was being made"
            }
        }
        if problem is UndoShadowMismatch {
            return "what was written differed from what was recorded"
        }
        return "the list could not be written"
    }
}

/// The staged names of a swap made in SHADOW without the list: the door's
/// fallback when the list cannot take the step (`JournaledWrite.perform`),
/// and `JournaledStep.writePlainly` for a step that cannot be named. No
/// `begin` names their files, so recovery's tidy of a closed step cannot
/// find them (the first review of U3a, LOW 8). Each swap has a label of its
/// own (`shadow-<pid>-<id>`), and before staging its targets are noted in
/// `shadow-staged/` in the list's folder under this process. The note goes
/// when the swap has finished or was refused whole; it stays when the swap
/// was stopped or could not be put back. A note whose process is gone is
/// tidied by the next recovery (under the lock, before every step) and the
/// next read ahead: its `-new` files are removed, and so is a kept `-orig`
/// whose page holds the same bytes; a kept original that differs from its
/// page is the only copy of what the page held and stays beside it (the
/// second review of U3a, MEDIUM c). The teacher's files are left exactly as
/// the process left them, as shadow recovery leaves them
/// (`undo.rule.recovery`).
///
/// When the list's folder cannot take the note (the list unwritable, the
/// disk full), the swap still goes ahead untracked, as the action must, and
/// what a kill leaves of it is not found again. A note is a few hundred
/// bytes and is written once per such swap, which is rare: a step that
/// cannot be named, or a list that could not take it.
nonisolated enum UndoShadowStaging {

    // MARK: - Stored properties

    /// The start of every such swap's label: its staged names end
    /// `-shadow-<pid>-<id>-new` and `-orig`.
    static let labelPrefix: String = "shadow"

    /// The folder in the list's folder that holds the notes.
    static let folderName: String = "shadow-staged"

    // MARK: - Types

    /// One swap's targets and label, under the process that made it.
    struct Note: Codable, Equatable {

        // MARK: - Stored properties

        let process: UndoProcess

        /// The swap's own label (the second review of U3a, LOW 2: one label
        /// shared by every process let a dead process's note remove a LIVE
        /// process's staged or kept files for the same page).
        let label: String

        /// Each target's absolute path.
        let targets: [String]
    }

    // MARK: - Functions

    /// A label no other swap has: this process and a fresh id.
    static func newLabel(for journal: UndoJournal) -> String {
        let id: String = String(UUID().uuidString.prefix(8)).lowercased()
        return "\(labelPrefix)-\(journal.process.pid)-\(id)"
    }

    /// `UndoSwap.swap` under a label of its own, noted first. A swap a test
    /// stopped keeps its note, as a process that died there would; so does
    /// one that could not be put back (`notPutBack`, the second review of
    /// U3a, MEDIUM c), so its leftovers are found once this process is gone,
    /// and the kept originals among them are kept (`tidyLeftovers`).
    /// `places` are where an external op of the swap is set (U3b's
    /// rollover, a step with moves and a deploy set for later).
    static func swap(
        _ targets: [UndoSwapTarget], noting journal: UndoJournal, places: UndoExternalPlaces = UndoAppPreferences()
    ) -> UndoSwapResult {
        let label: String = newLabel(for: journal)
        let noteURL: URL? = writeNote(for: targets, label: label, in: journal)
        let result: UndoSwapResult = UndoSwap.swap(targets, label: label, places: places)
        switch result {
        case .stoppedByATest, .notPutBack:
            return result
        case .swapped, .refused:
            if let noteURL {
                try? FileManager.default.removeItem(at: noteURL)
            }
            return result
        }
    }

    /// The note's place, or nil when it could not be written.
    static func writeNote(for targets: [UndoSwapTarget], label: String, in journal: UndoJournal) -> URL? {
        var paths: [String] = []
        for target in targets {
            paths.append(target.url.standardizedFileURL.path)
        }
        let folder: URL = journal.folderURL.appendingPathComponent(folderName, isDirectory: true)
        let noteURL: URL = folder.appendingPathComponent("\(label).json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data: Data = try JSONEncoder().encode(Note(process: journal.process, label: label, targets: paths))
            try data.write(to: noteURL, options: .atomic)
            return noteURL
        } catch {
            return nil
        }
    }

    /// Removes the staged files every note of a process that is gone names,
    /// then the note, keeping a kept original that is the only copy of its
    /// page's earlier content. A note whose staged file could not be removed
    /// (held, made immutable) is kept for the next tidy. Returns how many
    /// staged files were removed.
    @discardableResult
    static func tidyLeftovers(of journal: UndoJournal) -> Int {
        let folder: URL = journal.folderURL.appendingPathComponent(folderName, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return 0
        }
        var removed: Int = 0
        for name in names where name.hasSuffix(".json") {
            let noteURL: URL = folder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: noteURL),
                  let note = try? JSONDecoder().decode(Note.self, from: data) else {
                continue
            }
            if journal.processIsAlive(note.process) {
                continue
            }
            var everyOneGone: Bool = true
            for path in note.targets {
                let target: URL = URL(fileURLWithPath: path)
                for role in ["new", "orig"] {
                    let stagedURL: URL = UndoSwap.besideURL(for: target, label: note.label, role: role)
                    if UndoItem.read(at: stagedURL) == .absent {
                        continue
                    }
                    // A kept original that differs from its page is the only
                    // copy of what the page held: kept, never tidied away
                    // (the second review of U3a, MEDIUM c).
                    if role == "orig" && !UndoSwap.isACopyOfItsPlace(stagedURL, place: target) {
                        continue
                    }
                    if UndoSwap.removeStaged(stagedURL) {
                        removed += 1
                    } else {
                        everyOneGone = false
                    }
                }
            }
            if everyOneGone {
                try? FileManager.default.removeItem(at: noteURL)
            }
        }
        return removed
    }
}
