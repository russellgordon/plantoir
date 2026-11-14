import Foundation

/// Where one op stands in the working folder now, judged by content alone.
nonisolated enum UndoOpState: String, Equatable, Sendable {
    /// As the step left it.
    case after
    /// As it was before the step (already back, for an undo).
    case before
    /// Neither: changed since, missing, a folder, or not readable as text.
    case neither
}

/// What the contract's `undo.checkCases` call a verdict.
nonisolated enum UndoCheckVerdict: String, Equatable, Sendable {
    case canUndo
    case alreadyBack
    case changedSince
    case canRedo
    case alreadyRedone
}

/// Which way a step is being moved.
nonisolated enum UndoDirection: Sendable {
    /// From before to after: making the step, or redoing it.
    case forward
    /// From after to before: undoing it.
    case backward
}

/// What is at a path, read once.
nonisolated enum UndoItem: Equatable, Sendable {
    case absent
    case file(Data)
    /// A folder, a link, or a file that cannot be read.
    case notAFile

    static func read(at url: URL) -> UndoItem {
        var information: stat = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return lstat(path, &information)
        }
        if result != 0 {
            if errno == ENOENT || errno == ENOTDIR {
                return .absent
            }
            return .notAFile
        }
        if (information.st_mode & S_IFMT) != S_IFREG {
            return .notAFile
        }
        guard let data = try? Data(contentsOf: url) else {
            return .notAFile
        }
        return .file(data)
    }

    var data: Data? {
        if case .file(let data) = self {
            return data
        }
        return nil
    }
}

/// The content check and the staged, all-or-nothing change (plan 3.2).
nonisolated enum UndoCheck {

    // MARK: - Functions

    /// Where an op stands in a file's current content.
    static func state(of op: UndoOp, in item: UndoItem) -> UndoOpState {
        switch op.knownKind {
        case .writeFile:
            let currentSha: String?
            switch item {
            case .absent:
                currentSha = nil
            case .file(let data):
                currentSha = UndoHash.sha256(of: data)
            case .notAFile:
                return .neither
            }
            // Before wins when both match: then nothing need be written.
            if currentSha == op.beforeSha {
                return .before
            }
            if currentSha == op.afterSha {
                return .after
            }
            return .neither
        case .editLine:
            // A missing file is never "already back" for a line: the line's
            // page is gone, which is a change since (review 12).
            guard let data = item.data, let text = UndoText.decode(data), let key = op.key else {
                return .neither
            }
            let reading: UndoEntryReading = UndoLineOps.reading(key: key, in: text)
            if UndoLineOps.reading(reading, matches: op.before) {
                return .before
            }
            if UndoLineOps.reading(reading, matches: op.after) {
                return .after
            }
            return .neither
        case .recompute:
            return .after
        case .none:
            return .neither
        }
    }

    /// The contract's word for a state, for one direction.
    static func verdict(for state: UndoOpState, direction: UndoDirection) -> UndoCheckVerdict {
        switch (state, direction) {
        case (.after, .backward):
            return .canUndo
        case (.before, .backward):
            return .alreadyBack
        case (.before, .forward):
            return .canRedo
        case (.after, .forward):
            return .alreadyRedone
        case (.neither, _):
            return .changedSince
        }
    }

    /// Every file an undo (`.backward`) or a redo (`.forward`) of these ops
    /// would write, checked first and writing nothing: refused, naming the
    /// first page in the way and how many others, when ANY op's content is
    /// neither as the step left it nor already where it is going.
    ///
    /// Ops on one file are applied to that file's text in turn (in reverse
    /// for an undo), so several lines on one page make one staged file.
    static func plan(
        _ ops: [UndoOp],
        direction: UndoDirection,
        root: URL,
        journal: UndoJournal
    ) -> UndoPlan {
        var ordered: [UndoOp] = ops
        if direction == .backward {
            ordered = []
            var index: Int = ops.count - 1
            while index >= 0 {
                ordered.append(ops[index])
                index -= 1
            }
        }

        var pathsInOrder: [String] = []
        var original: [String: UndoItem] = [:]
        var working: [String: UndoItem] = [:]
        var inTheWay: [String] = []
        var recomputes: [UndoOp] = []

        for op in ordered {
            guard let kind = op.knownKind, let path = op.path else {
                // Never guessed at: a step this version cannot read is not
                // undone or redone (the director's ruling 1).
                return .refused(.notReadable)
            }
            if kind == .recompute {
                recomputes.append(op)
                continue
            }
            if original[path] == nil {
                let item: UndoItem = UndoItem.read(at: root.appendingPathComponent(path))
                original[path] = item
                working[path] = item
                pathsInOrder.append(path)
            }
            let current: UndoItem = working[path] ?? .absent
            let state: UndoOpState = UndoCheck.state(of: op, in: current)
            let verdict: UndoCheckVerdict = UndoCheck.verdict(for: state, direction: direction)
            if verdict == .alreadyBack || verdict == .alreadyRedone {
                continue
            }
            if verdict == .changedSince {
                if !inTheWay.contains(path) {
                    inTheWay.append(path)
                }
                continue
            }
            guard let moved = UndoCheck.moved(op, from: current, direction: direction, journal: journal) else {
                return .refused(.contentMissing(path: path))
            }
            working[path] = moved
        }

        if let first = inTheWay.first {
            return .refused(.changedSince(firstPath: first, others: inTheWay.count - 1))
        }

        var targets: [UndoSwapTarget] = []
        for path in pathsInOrder {
            let before: UndoItem = original[path] ?? .absent
            let after: UndoItem = working[path] ?? .absent
            if before == after {
                continue
            }
            targets.append(UndoSwapTarget(
                url: root.appendingPathComponent(path),
                relativePath: path,
                expected: before.data,
                replacement: after.data
            ))
        }
        return .ready(targets: targets, recomputes: recomputes)
    }

    /// The content after moving one op one way, or nil when a blob it needs
    /// is missing or the text cannot be read.
    static func moved(_ op: UndoOp, from item: UndoItem, direction: UndoDirection, journal: UndoJournal) -> UndoItem? {
        switch op.knownKind {
        case .writeFile:
            let wanted: String? = direction == .backward ? op.beforeSha : op.afterSha
            guard let wanted else {
                return .absent
            }
            guard let data = journal.readBlob(sha: wanted) else {
                return nil
            }
            return .file(data)
        case .editLine:
            guard let data = item.data, let text = UndoText.decode(data) else {
                return nil
            }
            let from: String? = direction == .backward ? op.after : op.before
            let to: String? = direction == .backward ? op.before : op.after
            guard let moved = UndoLineOps.moving(op, from: from, to: to, in: text) else {
                return nil
            }
            return .file(Data(moved.utf8))
        case .recompute, .none:
            return item
        }
    }
}

/// What a check found.
nonisolated enum UndoPlan: Equatable, Sendable {
    case ready(targets: [UndoSwapTarget], recomputes: [UndoOp])
    case refused(UndoRefusal)
}

/// One file to swap: what it must still hold, and what goes in its place
/// (nil: it is removed).
nonisolated struct UndoSwapTarget: Equatable, Sendable {

    // MARK: - Stored properties

    let url: URL

    let relativePath: String

    let expected: Data?

    let replacement: Data?
}

/// How a swap went.
nonisolated enum UndoSwapResult: Equatable, Sendable {
    case swapped
    case refused(UndoRefusal)
    /// A test stopped it at a kill point, leaving everything as it was.
    case stoppedByATest
}

/// Staged, then swapped (plan 3.2, Windows' fact 5).
///
/// Every new content is written BESIDE its target first, under a name that
/// says which step it belongs to, and only when all are written are they
/// swapped in, one rename each. Before each swap the target is read again
/// and must still hold what the check saw; the original is kept under a
/// second name (a hard link, so its bytes, mode and owner are the original's
/// own) until every swap has gone in. If one cannot go in, the swaps already
/// made are reversed from those originals and nothing of the step is left.
/// A rename either happened or did not, so a process that dies part way
/// leaves each file wholly old or wholly new, and recovery settles the rest.
nonisolated enum UndoSwap {

    // MARK: - Stored properties

    /// The part of a staged file's name that says it is Plantoir's.
    static let stagedMarker: String = ".plantoir-undo-"

    // MARK: - Functions

    static func swap(_ targets: [UndoSwapTarget], label: String) -> UndoSwapResult {
        var staged: [URL?] = []
        var originals: [URL?] = []
        var swapsMade: Int = 0

        func tidy() {
            for url in staged {
                if let url {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            for url in originals {
                if let url {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }

        func reverse() {
            var index: Int = swapsMade - 1
            while index >= 0 {
                let target: UndoSwapTarget = targets[index]
                if let original = originals[index] {
                    _ = UndoSwap.rename(original, onto: target.url)
                    originals[index] = nil
                } else {
                    try? FileManager.default.removeItem(at: target.url)
                }
                index -= 1
            }
        }

        // 1. Stage every new content beside its target.
        for target in targets {
            originals.append(nil)
            guard let replacement = target.replacement else {
                staged.append(nil)
                continue
            }
            let stagedURL: URL = UndoSwap.besideURL(for: target.url, label: label, role: "new")
            var mode: mode_t = 0o644
            var information: stat = stat()
            let found: Int32 = target.url.withUnsafeFileSystemRepresentation { path in
                guard let path else {
                    return -1
                }
                return stat(path, &information)
            }
            if found == 0 {
                mode = information.st_mode & 0o7777
            }
            do {
                try FileManager.default.createDirectory(
                    at: target.url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? FileManager.default.removeItem(at: stagedURL)
                try UndoFiles.writeDurably(replacement, to: stagedURL, mode: mode)
                staged.append(stagedURL)
            } catch {
                staged.append(nil)
                tidy()
                return .refused(.fileIsInUse(path: target.relativePath))
            }
        }

        // 2. Swap them in, checking each target first.
        var index: Int = 0
        while index < targets.count {
            let target: UndoSwapTarget = targets[index]
            if UndoKillPoints.stopsHere(.beforeSwap(index)) {
                return .stoppedByATest
            }
            if UndoKillPoints.fileInUseAtSwap?(index) == true {
                reverse()
                tidy()
                return .refused(.fileIsInUse(path: target.relativePath))
            }
            let now: UndoItem = UndoItem.read(at: target.url)
            if now.data != target.expected || (target.expected == nil && now != .absent) {
                reverse()
                tidy()
                return .refused(.changedSince(firstPath: target.relativePath, others: 0))
            }
            if now != .absent {
                let originalURL: URL = UndoSwap.besideURL(for: target.url, label: label, role: "orig")
                try? FileManager.default.removeItem(at: originalURL)
                if !UndoSwap.keep(target.url, as: originalURL) {
                    reverse()
                    tidy()
                    return .refused(.fileIsInUse(path: target.relativePath))
                }
                originals[index] = originalURL
            }
            var wentIn: Bool = true
            if let stagedURL = staged[index] {
                wentIn = UndoSwap.rename(stagedURL, onto: target.url)
                if wentIn {
                    staged[index] = nil
                }
            } else {
                wentIn = (try? FileManager.default.removeItem(at: target.url)) != nil
            }
            if !wentIn {
                if let originalURL = originals[index] {
                    try? FileManager.default.removeItem(at: originalURL)
                    originals[index] = nil
                }
                reverse()
                tidy()
                return .refused(.fileIsInUse(path: target.relativePath))
            }
            swapsMade += 1
            index += 1
        }

        // 3. Every swap went in: the kept originals are no longer needed.
        tidy()
        for target in targets {
            UndoFiles.syncFolder(target.url.deletingLastPathComponent())
        }
        return .swapped
    }

    /// `.<name>.plantoir-undo-<label>-<role>` in the target's own folder:
    /// a dot file, so Obsidian and the website builder pass over it.
    static func besideURL(for target: URL, label: String, role: String) -> URL {
        let name: String = "." + target.lastPathComponent + stagedMarker + label + "-" + role
        return target.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Whether a file name is one a swap for this label left.
    static func isStaged(_ name: String, label: String) -> Bool {
        return name.hasPrefix(".") && name.contains(stagedMarker + label + "-")
    }

    static func rename(_ from: URL, onto to: URL) -> Bool {
        let result: Int32 = from.withUnsafeFileSystemRepresentation { fromPath in
            return to.withUnsafeFileSystemRepresentation { toPath in
                guard let fromPath, let toPath else {
                    return -1
                }
                return Darwin.rename(fromPath, toPath)
            }
        }
        return result == 0
    }

    /// Keeps the original under a second name: a hard link where the volume
    /// has them, a copy (data, mode, extended attributes) where it does not.
    static func keep(_ url: URL, as keptURL: URL) -> Bool {
        let linked: Int32 = url.withUnsafeFileSystemRepresentation { fromPath in
            return keptURL.withUnsafeFileSystemRepresentation { toPath in
                guard let fromPath, let toPath else {
                    return -1
                }
                return link(fromPath, toPath)
            }
        }
        if linked == 0 {
            return true
        }
        let flags: copyfile_flags_t = copyfile_flags_t(COPYFILE_DATA | COPYFILE_SECURITY | COPYFILE_XATTR)
        let copied: Int32 = url.withUnsafeFileSystemRepresentation { fromPath in
            return keptURL.withUnsafeFileSystemRepresentation { toPath in
                guard let fromPath, let toPath else {
                    return -1
                }
                return copyfile(fromPath, toPath, nil, flags)
            }
        }
        return copied == 0
    }

    /// Removes what a swap for this label left beside these files.
    static func tidyLeftovers(label: String, beside urls: [URL]) {
        var folders: [URL] = []
        for url in urls {
            let folder: URL = url.deletingLastPathComponent()
            if !folders.contains(folder) {
                folders.append(folder)
            }
        }
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
                continue
            }
            for name in names where UndoSwap.isStaged(name, label: label) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }
}

/// How an undo or a redo went.
nonisolated enum UndoOutcome: Equatable, Sendable {
    case undone(seq: Int)
    case redone(seq: Int)
    case nothingToUndo
    case nothingToRedo
    /// A newer step is still being made, undone or redone
    /// (`undo.wording.anotherChangeIsUnderWay`).
    case anotherChangeIsUnderWay
    /// The step's working folder cannot be reached, or the list holds at or
    /// above the head something this version cannot read: greyed, plain
    /// "Undo", nothing said (ruling 10; the director's ruling 1).
    case notAvailable
    /// Refused, nothing written to the pages. For an Undo whose page was
    /// changed by hand, or whose content is missing, `clearedTheList` is true
    /// (ruling 13; `UndoSwitch.undoRefusedForMissingContentClearsTheList`);
    /// for a Redo refused either way, only the redo branch is dropped
    /// (ruling 20) and it is false.
    case refused(UndoRefusal, clearedTheList: Bool)
    /// The list itself could not be read or written.
    case listUnavailable
    /// A test stopped it at a kill point.
    case stoppedByATest
}

/// Why the whole list was cleared: the `reason` of a `cleared` line.
///
/// The reasons this version WRITES. A reader never checks one: a `cleared`
/// line clears whatever its reason says, a reason no reader knows included
/// (the director's ruling 1 on U1's third round), so a later version can
/// clear for a reason of its own. A deploy and sharing unit plans are not
/// on the list and clear nothing (rulings 17 and 18, which replaced 14 and
/// 16): whether a step was deployed since is read from the published-pages
/// record when Undo is offered (`UndoWebsite`), never written into the
/// journal.
nonisolated enum UndoClearing: String, Sendable, CaseIterable {
    /// Undo refused the newest step because what it changed was changed by
    /// hand since (ruling 13).
    case changedSince
    /// A step's process died part way and recovery could not put the step
    /// wholly back (the director's ruling 7 on U1's first reviews, and 4 on
    /// its second).
    case interrupted
    /// Undo refused the newest step because content it needs is missing
    /// from the list, which can never come back: refused once with its
    /// reason, then the list is cleared, as ruling 13 does for a hand edit
    /// (held question M9, built behind
    /// `UndoSwitch.undoRefusedForMissingContentClearsTheList`).
    case contentMissing
    /// The switch went live (U7): one clearing at the flip, so a step
    /// recorded in shadow, while most writers were not yet journaled, is
    /// never offered (the director's ruling 1 on U1's third round).
    case wentLive
}

/// Undo, Redo and clearing, as the list does them.
nonisolated extension UndoJournal {

    // MARK: - Functions

    /// Undoes the newest step: the only one that can be (ruling 9).
    func undoNewest(
        resolveRoot: (UndoWorkingFolder) -> URL? = UndoReach.root,
        recompute: (UndoOp, URL) -> Void = { _, _ in }
    ) -> UndoOutcome {
        return move(.backward, resolveRoot: resolveRoot, recompute: recompute)
    }

    /// Redoes the most recently undone step.
    func redoNewest(
        resolveRoot: (UndoWorkingFolder) -> URL? = UndoReach.root,
        recompute: (UndoOp, URL) -> Void = { _, _ in }
    ) -> UndoOutcome {
        return move(.forward, resolveRoot: resolveRoot, recompute: recompute)
    }

    /// What Undo or Redo would act on now: for the menu, which greys the
    /// item for anything but a step.
    func availability(_ direction: UndoDirection) -> UndoAvailability {
        guard let offer = try? offer() else {
            return .notReadable
        }
        return direction == .backward ? offer.undo : offer.redo
    }

    private func move(
        _ direction: UndoDirection,
        resolveRoot: (UndoWorkingFolder) -> URL?,
        recompute: (UndoOp, URL) -> Void
    ) -> UndoOutcome {
        // 1. Find the step, inside the lock, with recovery run first.
        let found: UndoAvailability
        do {
            found = try withLock { writer -> UndoAvailability in
                UndoRecovery.run(writer, mode: .live, resolveRoot: resolveRoot)
                let offer: UndoOffer = writer.fold.offer(now: now())
                return direction == .backward ? offer.undo : offer.redo
            }
        } catch {
            return .listUnavailable
        }
        let record: UndoStepRecord
        switch found {
        case .nothing:
            return direction == .backward ? .nothingToUndo : .nothingToRedo
        case .notReadable:
            return .notAvailable
        case .anotherChangeIsUnderWay(let busy):
            // A dead process's step whose folder cannot be reached is not
            // "under way": it waits for its folder, and Undo is greyed.
            if let process = busy.process, !processIsAlive(process) {
                if let folder = busy.step.workingFolder, resolveRoot(folder) == nil {
                    return .notAvailable
                }
            }
            return .anotherChangeIsUnderWay
        case .step(let step):
            record = step
        }
        let seq: Int = record.step.seq
        guard let folder = record.step.workingFolder, let root = resolveRoot(folder) else {
            return .notAvailable
        }

        // 2. Check every op, writing nothing.
        let plan: UndoPlan = UndoCheck.plan(record.step.ops, direction: direction, root: root, journal: self)
        if UndoKillPoints.stopsHere(.afterTheCheck) {
            return .stoppedByATest
        }
        guard case .ready(let targets, let recomputes) = plan else {
            if case .refused(let refusal) = plan {
                if refusal == .notReadable {
                    return .notAvailable
                }
                return .refused(refusal, clearedTheList: answerARefusal(refusal, of: seq, direction: direction))
            }
            return .listUnavailable
        }

        // 3. Say it is under way, as long as it is still the one to move.
        let starting: UndoEventKind = direction == .backward ? .undoing : .redoing
        let ending: UndoEventKind = direction == .backward ? .undone : .redone
        let phase: UndoPhase = direction == .backward ? .undoing : .redoing
        do {
            try withLock { writer in
                let offer: UndoOffer = writer.fold.offer(now: now())
                let stillTheOne: UndoAvailability = direction == .backward ? offer.undo : offer.redo
                guard case .step(let current) = stillTheOne, current.step.seq == seq else {
                    throw UndoJournalError.notTheNewestStep(seq)
                }
                try writer.append(UndoEventLine(seq: seq, event: starting, process: process))
                try writer.sync()
            }
        } catch UndoJournalError.notTheNewestStep {
            return .anotherChangeIsUnderWay
        } catch {
            return .listUnavailable
        }
        if UndoKillPoints.stopsHere(direction == .backward ? .afterUndoing : .afterRedoing) {
            return .stoppedByATest
        }

        // 4. Swap, then re-derive the files kept true by a rule.
        let label: String = "\(seq)-" + (direction == .backward ? "undo" : "redo")
        switch UndoSwap.swap(targets, label: label) {
        case .refused(let refusal):
            JournaledWrite.finish(seq: seq, with: .failed, phase: phase, reason: "refused", in: self, mode: .live)
            // Caught at the swap rather than the check: the same hand edit,
            // so the same answer (rulings 13 and 20; the core review's M2).
            return .refused(refusal, clearedTheList: answerARefusal(refusal, of: seq, direction: direction))
        case .stoppedByATest:
            return .stoppedByATest
        case .swapped:
            break
        }
        for op in recomputes {
            recompute(op, root)
        }
        if UndoKillPoints.stopsHere(direction == .backward ? .beforeUndone : .beforeRedone) {
            return .stoppedByATest
        }
        JournaledWrite.finish(seq: seq, with: ending, phase: nil, reason: nil, in: self, mode: .live)
        return direction == .backward ? .undone(seq: seq) : .redone(seq: seq)
    }

    /// What a refusal that can never succeed does to the list. The page was
    /// changed by hand, or content the step needs is missing from the list:
    /// an Undo clears it (ruling 13, and for missing content
    /// `UndoSwitch.undoRefusedForMissingContentClearsTheList`), a Redo drops
    /// only the redo branch (ruling 20). A file in use leaves the list as it
    /// was, to be tried again. True when it cleared.
    private func answerARefusal(_ refusal: UndoRefusal, of seq: Int, direction: UndoDirection) -> Bool {
        let reason: UndoClearing
        switch refusal {
        case .changedSince:
            reason = .changedSince
        case .contentMissing:
            if direction == .backward && !UndoSwitch.undoRefusedForMissingContentClearsTheList {
                return false
            }
            reason = .contentMissing
        case .fileIsInUse, .notReadable:
            return false
        }
        if direction == .backward {
            return (try? clearAfterARefusal(of: seq, reason: reason)) == true
        }
        try? dropTheRedoBranchAfterARefusal(of: seq)
        return false
    }

    /// Ruling 20: the refused step is still the one Redo offers, so it and
    /// every undone step above it are dropped, and Redo has nothing until
    /// the next undo. Undo is untouched.
    private func dropTheRedoBranchAfterARefusal(of seq: Int) throws {
        try withLock { writer in
            guard writer.fold.offer(now: now()).redoCandidate?.step.seq == seq else {
                return
            }
            for record in writer.fold.stepsOnTheList where record.phase == .undone && record.step.seq >= seq {
                try writer.append(UndoEventLine(seq: record.step.seq, event: .dropped, reason: "redoRefused"))
            }
        }
    }

    /// Ruling 13: the refused step is still the head, so the list is cleared.
    private func clearAfterARefusal(of seq: Int, reason: UndoClearing) throws -> Bool {
        return try withLock { writer -> Bool in
            if writer.fold.offer(now: now()).head?.step.seq != seq {
                return false
            }
            try writer.append(UndoEventLine(seq: writer.fold.highestSeq, event: .cleared, reason: reason.rawValue))
            UndoPruning.prune(writer)
            return true
        }
    }

    /// The one clearing at the flip (U7 calls it once, at the first launch
    /// with `undoJournalIsLive` on): every step recorded in shadow leaves the
    /// list, because while it was off most writers were not journaled yet,
    /// and an Undo could otherwise pass over the teacher's newest change to
    /// take back an older one (the director's ruling 1 on U1's third round).
    /// Writes nothing when nothing is on the list. True when it cleared.
    @discardableResult
    func clearTheListAsTheSwitchGoesLive() throws -> Bool {
        return try withLock { writer -> Bool in
            if writer.fold.stepsOnTheList.isEmpty {
                return false
            }
            try writer.append(UndoEventLine(seq: writer.fold.highestSeq, event: .cleared, reason: UndoClearing.wentLive.rawValue))
            UndoPruning.prune(writer)
            return true
        }
    }
}
