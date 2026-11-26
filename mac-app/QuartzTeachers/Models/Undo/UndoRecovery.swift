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
/// Content a put-back needs that the list no longer holds is taken from the
/// step's own kept original beside the page (`-orig`) when its hash is the
/// one the journal recorded, and the step is rolled back (Russell's ruling
/// of 2026-11-20, 15:20). A put-back that still cannot be planned (no kept
/// original matches, or a file it must move is in the way) can never
/// succeed later either: the step is closed `interrupted` (reason
/// `couldNotPutBack`, naming the files left part way) and the list
/// cleared, and every kept original that differs from its page is left
/// beside it, the only copy of what it held, named on the trail. A swap
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
/// A step closed `interrupted` leaves nothing of the journal's in a course
/// but the kept originals that are the only copy of what a page held: its
/// staged files are removed when it is closed, and when its folder could
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
        resolveRoot: (UndoWorkingFolder) -> URL?,
        places: UndoExternalPlaces = UndoAppPreferences(),
        leavingStepsThatRederive: Bool = true
    ) -> [UndoRecoveryResult] {
        writer.recoveredInThisHold = true
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
            guard let root = UndoCheck.root(of: record.step, resolveRoot: resolveRoot) else {
                continue
            }
            // A step that keeps a file true by a rule is held open until a
            // runner for its maintainer exists: never settled with its
            // re-derivation skipped (the hard review of U2b, MEDIUM 5).
            if !UndoMaintainers.canRun(record.step.ops) {
                continue
            }
            // A live step that keeps a file true by a rule is settled only by
            // a recovery that will re-derive what it settles
            // (`recoverAndRederive`); a recovery run inside another write's
            // lock, which drops its results, leaves it in flight for that
            // one (the second hard review of U2b, MEDIUM 1).
            if leavingStepsThatRederive && mode == .live && UndoRecovery.keepsAFileTrue(record.step) {
                continue
            }
            let key: String = UndoRefusedSwaps.key(for: record, in: writer.journal)
            if !trySwapsNow && !UndoRefusedSwaps.isDue(key, now: now) {
                continue
            }
            var swapRefused: Bool = false
            var leftFor: UndoRefusal? = nil
            if let result = settle(record, root: root, writer: writer, mode: mode, places: places, swapRefused: &swapRefused, leftFor: &leftFor) {
                UndoRefusedSwaps.forget(key)
                results.append(result)
            } else if swapRefused {
                UndoRefusedSwaps.noteARefusal(key, now: now)
                if let leftFor {
                    writer.leftByRecovery[record.step.seq] = leftFor
                }
            }
        }
        // In shadow too, since U3: a shadow step is now staged beside its
        // pages like a live one, so one closed interrupted would otherwise
        // leave its dot-files in the course until the switch flips. Shadow
        // removes only the journal's own staged FILES, never a folder set
        // aside (steps that make or take out folders are left to a live
        // recovery; a step that moves them whole sets none aside, U4b), so
        // it still writes nothing of the teacher's.
        tidyClosedSteps(writer, resolveRoot: resolveRoot, onlyStepsOfFiles: mode == .shadow, mode: mode)
        // And what a shadow swap without the list left when its process
        // died (`UndoShadowStaging`; the first review of U3a, LOW 8).
        UndoShadowStaging.tidyLeftovers(of: writer.journal)
        return results
    }

    /// Recovery under the lock, then, with the lock released, the
    /// re-derivation of every step it settled (`UndoMaintainers`). The
    /// runner is awaited on its own actor, so the main actor is never
    /// blocked while the lock is held, and the lock never waits on it.
    @concurrent
    static func recoverAndRederive(
        _ journal: UndoJournal,
        resolveRoot: @escaping @Sendable (UndoWorkingFolder) -> URL?,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) async {
        var settled: [UndoRecoveryResult] = []
        do {
            settled = try journal.withLock { writer -> [UndoRecoveryResult] in
                return UndoRecovery.run(writer, mode: .live, resolveRoot: resolveRoot, places: places, leavingStepsThatRederive: false)
            }
        } catch {
            return
        }
        for result in settled where result.outcome != .leftAlone {
            await UndoMaintainers.rederive(stepNumbered: result.seq, in: journal, resolveRoot: resolveRoot)
        }
    }

    /// Removes the staged files of every step closed `interrupted` that this
    /// process has not yet tidied and whose folder it can reach. Each is
    /// tidied once per process, a few folder listings for the rare step that
    /// was closed; one whose file could not be removed (held, or made
    /// immutable) is looked for again at the next lock. A kept original
    /// that differs from its page is kept, live and in shadow: the step is
    /// closed, so nothing will put its page back from the list, whose
    /// content for it is pruned with it (the third review of U3a, LOW 1).
    static func tidyClosedSteps(
        _ writer: UndoJournalWriter,
        resolveRoot: (UndoWorkingFolder) -> URL?,
        onlyStepsOfFiles: Bool = false,
        mode: UndoMode = .live
    ) {
        for seq in writer.fold.orderedSeqs {
            guard let record = writer.fold.records[seq], record.phase == .interrupted else {
                continue
            }
            if onlyStepsOfFiles && !UndoRecovery.changesOnlyFilesAndMoves(record.step) {
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
            // Closed `interrupted`: the step did not settle, so a kept
            // original that is the only copy of its page's earlier content
            // stays beside the page (the second review of U3a, MEDIUM b).
            if !tidyStagedFiles(of: record.step, root: root, keepingOnlyCopies: true) {
                // Something held or locked: looked for again at the next lock.
                continue
            }
            tidiedLock.lock()
            tidied.insert(key)
            tidiedLock.unlock()
        }
    }

    /// Whether every op of the step changes a file in place (`writeFile`,
    /// `editLine`, `replaceText`, `editJSON`) or is a `recompute`: nothing
    /// it stages is a folder or a moved item.
    /// Whether a step changes only files and moves files or folders whole
    /// (U4b: Rename folder): the steps whose staged files shadow tidies. A
    /// move sets nothing aside, so all its tidy removes is the step's own
    /// staged files beside its pages, at each page's place and, for a page a
    /// move carries, at its place before the move; a kept original that
    /// differs from its page stays (part four's review, L3: with the switch
    /// off a killed rename's dot-files stayed until the switch flipped).
    /// A step that makes or takes out a folder, or stands apart, is still
    /// left to a live recovery.
    static func changesOnlyFilesAndMoves(_ step: UndoStep) -> Bool {
        for op in step.ops {
            switch op.knownKind {
            case .writeFile, .editLine, .replaceText, .editJSON, .recompute, .move:
                continue
            default:
                return false
            }
        }
        return true
    }

    static func changesOnlyFiles(_ step: UndoStep) -> Bool {
        for op in step.ops {
            switch op.knownKind {
            case .writeFile, .editLine, .replaceText, .editJSON, .recompute:
                continue
            default:
                return false
            }
        }
        return true
    }

    /// Every staged file a step's apply, undo, redo or recovery left beside
    /// the files it names. True when none is left. `keepingOnlyCopies`, for
    /// a step that did not settle: a kept original that differs from its
    /// page is left where it is (`UndoSwap.isACopyOfItsPlace`).
    @discardableResult
    static func tidyStagedFiles(
        of step: UndoStep, root: URL, keepingOnlyCopies: Bool = false, unlessTheListHoldsFrom journal: UndoJournal? = nil,
        keepingCopiesHolding notInTheList: Set<String> = []
    ) -> Bool {
        let urls: [URL] = UndoRecovery.placesStagedBeside(of: step, root: root)
        var listHolds: ((URL, URL) -> Bool)? = nil
        if let journal {
            listHolds = UndoRecovery.listHolds(step, root: root, from: journal)
        }
        var allGone: Bool = true
        for work in ["apply", "undo", "redo"] {
            if !UndoSwap.tidyLeftovers(
                label: "\(step.seq)-\(work)", beside: urls, asideListings: asideListings(of: step, root: root),
                onAside: { found in UndoRecovery.noteAnAsideFolder(found, of: step, root: root, journal: nil) },
                root: root, keepingOnlyCopies: keepingOnlyCopies,
                unlessTheListHolds: listHolds, keepingCopiesHolding: notInTheList
            ) {
                allGone = false
            }
        }
        return allGone
    }

    /// Whether a kept original's bytes are exactly what the list gives for
    /// its page, so it is not the only copy of what it holds: what the
    /// step's ops on that page come to, undone or redone, from what the page
    /// holds now (a whole file by its recorded hash, whose content the list
    /// must still hold; a line, a hunk or a member derived from the page).
    /// Never true for a kept original that holds anything else, such as an
    /// in-place edit that raced the swap into the original's inode (the
    /// third review of U3a, LOW 1: the old test only asked whether the
    /// step's blobs were there, and a key edit needs none).
    static func listHolds(_ step: UndoStep, root: URL, from journal: UndoJournal) -> (_ kept: URL, _ place: URL) -> Bool {
        return { keptURL, place in
            guard case .file(let kept) = UndoItem.read(at: keptURL) else {
                return false
            }
            let wanted: String = place.standardizedFileURL.path
            var opsOnThePlace: [UndoOp] = []
            var indicesOnThePlace: [Int] = []
            let carriers: [String: UndoOp] = UndoCheck.carriers(in: step.ops)
            var opIndex: Int = 0
            for op in step.ops {
                let index: Int = opIndex
                opIndex += 1
                guard op.knownKind != .recompute, !op.isWhole, let path = op.path else {
                    continue
                }
                if root.appendingPathComponent(path).standardizedFileURL.path == wanted {
                    opsOnThePlace.append(op)
                    indicesOnThePlace.append(index)
                } else if let carrier = carriers[path], let from = carrier.from, let to = carrier.to {
                    // A carried page whose folder has moved back (U4b): the
                    // same op, judged at its old place.
                    let oldPlace: String = UndoOp.placeBeforeTheMove(path, from: from, to: to)
                    if root.appendingPathComponent(oldPlace).standardizedFileURL.path == wanted {
                        var atTheOldPlace: UndoOp = op
                        atTheOldPlace.path = oldPlace
                        opsOnThePlace.append(atTheOldPlace)
                        indicesOnThePlace.append(index)
                    }
                }
            }
            // U4b3 door-3: a page at a handed-over place is planned with the
            // other op of its pair, in the step's order, so the plan judges
            // the place as handed over (the write at a place a link leaves,
            // judged alone against the link still there, is never ready).
            var partners: [Int] = []
            for handover in UndoCheck.handovers(in: step.ops) {
                if indicesOnThePlace.contains(handover.leaverIndex) && !indicesOnThePlace.contains(handover.fillerIndex) {
                    partners.append(handover.fillerIndex)
                }
                if indicesOnThePlace.contains(handover.fillerIndex) && !indicesOnThePlace.contains(handover.leaverIndex) {
                    partners.append(handover.leaverIndex)
                }
            }
            if !partners.isEmpty {
                var together: [(index: Int, op: UndoOp)] = []
                var position: Int = 0
                while position < opsOnThePlace.count {
                    together.append((index: indicesOnThePlace[position], op: opsOnThePlace[position]))
                    position += 1
                }
                for partner in partners {
                    together.append((index: partner, op: step.ops[partner]))
                }
                together.sort { first, second in
                    first.index < second.index
                }
                opsOnThePlace = []
                for entry in together {
                    opsOnThePlace.append(entry.op)
                }
            }
            if opsOnThePlace.isEmpty {
                return false
            }
            for direction in [UndoDirection.backward, UndoDirection.forward] {
                let plan: UndoPlan = UndoCheck.plan(opsOnThePlace, direction: direction, root: root, journal: journal)
                guard case .ready(let targets, _, _) = plan else {
                    continue
                }
                for target in targets where target.url.standardizedFileURL.path == wanted && target.replacement == kept {
                    return true
                }
            }
            return false
        }
    }

    /// What a step's own swap kept beside a page as its original (`-orig`,
    /// any of the step's labels: its apply, undo, redo or a recovery's),
    /// answered for a page's path and the hash of the whole content wanted
    /// there only when a kept original's bytes hash to exactly that: the
    /// journal's record of what the page held (Russell's ruling of
    /// 2026-11-20, 15:20). Nil when none matches; a kept original that does
    /// not match is never used, and never removed for not matching.
    ///
    /// A kept original that is there and cannot be read just now (a cloud
    /// placeholder not downloaded, a permission) is told to `couldNotRead`
    /// with its page's path when none matches: it may be the one, so the
    /// caller answers "cannot tell now", never "no kept original matches"
    /// (the first review of U3c, LOW 5).
    static func keptOriginal(
        of step: UndoStep, root: URL, couldNotRead: ((_ path: String) -> Void)? = nil
    ) -> (_ path: String, _ sha: String) -> Data? {
        // A page inside a folder the step moves is looked for where the
        // page is now (`placeNow`): after an Undo its kept copies are under
        // the move's `from` (the part-two review's M1, second layer).
        let carriers: [String: UndoOp] = UndoCheck.carriers(in: step.ops)
        return { path, sha in
            var placePath: String = path
            if let carrier = carriers[path] {
                placePath = UndoRecovery.placeNow(of: path, carriedBy: carrier, root: root)
            }
            let place: URL = root.appendingPathComponent(placePath)
            var unreadable: Bool = false
            for kept in UndoRecovery.keptOriginalFiles(of: step, beside: place) {
                let item: UndoItem = UndoItem.read(at: kept)
                if item == .unreadable {
                    unreadable = true
                    continue
                }
                guard case .file(let data) = item else {
                    continue
                }
                if UndoHash.sha256(of: data) == sha {
                    return data
                }
            }
            if unreadable {
                couldNotRead?(path)
            }
            return nil
        }
    }

    /// Writes back into the list what a put-back from kept originals takes
    /// and sets aside (the first review of U3c, MEDIUM): each kept original's
    /// bytes as the blob its hash names, and what the page holds now as the
    /// other direction's blob when it hashes to the recorded other hash, so
    /// the swap's tidy removes no only copy and the step's other direction
    /// can still be made. Inside the lock, before the swap. The pages whose
    /// other direction's content could not be made whole (the list would
    /// not take it, or the page does not hash to what was recorded): their
    /// outgoing bytes must be kept beside them, never tidied.
    ///
    /// A kept original whose own bytes the list will not take is never
    /// ignored (the second review of U3c, MEDIUM): once the page holds them
    /// it is a copy of its page, and the next move the other way would leave
    /// them in no file at all. Its hash is told back, and no tidy removes a
    /// kept original holding it (`keepingCopiesHolding`).
    static func storeWhatKeptOriginalsGive(_ uses: [UndoKeptOriginalUse], _ writer: UndoJournalWriter) -> UndoWhatTheListCouldNotTake {
        var notWhole: [String] = []
        var keptNotStored: Set<String> = []
        for use in uses {
            if (try? writer.writeBlob(use.kept)) == nil {
                keptNotStored.insert(UndoHash.sha256(of: use.kept))
            }
            guard let otherSha = use.otherSha else {
                // The other direction wants no file there: nothing to keep.
                continue
            }
            if writer.journal.readBlob(sha: otherSha) != nil {
                continue
            }
            var stored: Bool = false
            if case .file(let outgoing) = use.outgoing, UndoHash.sha256(of: outgoing) == otherSha {
                stored = (try? writer.writeBlob(outgoing)) != nil
            }
            if !stored && !notWhole.contains(use.path) {
                notWhole.append(use.path)
            }
        }
        return UndoWhatTheListCouldNotTake(outgoingOf: notWhole, keptOriginalsHolding: keptNotStored)
    }

    /// What an Undo or a Redo's swap is about to take off each page, into
    /// the list as a blob when the step's OTHER direction needs it and the
    /// list does not hold it (U3c review 3, LOW 3, fixed in U4a): a page
    /// whose content for the Redo (or the Undo) was gone from the list had
    /// its only copy deleted by the swap's tidy, and that Redo then came to
    /// `contentMissing`. By the line's first invariant an only copy is never
    /// deleted: the bytes go into the list, and when the list will not take
    /// them the page is named here, so the swap keeps them beside it
    /// (`keepingTheOriginalsOf`) and the other direction is made from that
    /// kept file, as a put-back from a kept original is. Inside the lock,
    /// before the swap.
    ///
    /// Bytes a kept original of the step already holds beside the page need
    /// nothing more: that file is the copy the other direction is made from
    /// (U3c's put-back keeps it, `keepingCopiesHolding`).
    static func storeWhatTheOtherDirectionNeeds(
        _ targets: [UndoSwapTarget], of step: UndoStep, direction: UndoDirection, root: URL, _ writer: UndoJournalWriter
    ) -> [String] {
        var notStored: [String] = []
        for target in targets {
            guard case .file = target.change, let outgoing = target.expected else {
                continue
            }
            let outgoingSha: String = UndoHash.sha256(of: outgoing)
            var needed: Bool = false
            for op in step.ops where op.knownKind == .writeFile && op.path == target.relativePath {
                let otherSha: String? = direction == .backward ? op.afterSha : op.beforeSha
                if otherSha == outgoingSha {
                    needed = true
                }
            }
            if !needed || writer.journal.readBlob(sha: outgoingSha) != nil {
                continue
            }
            var alreadyKept: Bool = false
            for kept in UndoRecovery.keptOriginalFiles(of: step, beside: root.appendingPathComponent(target.relativePath)) {
                if case .file(let data) = UndoItem.read(at: kept), UndoHash.sha256(of: data) == outgoingSha {
                    alreadyKept = true
                }
            }
            if alreadyKept {
                continue
            }
            if (try? writer.writeBlob(outgoing)) == nil && !notStored.contains(target.relativePath) {
                notStored.append(target.relativePath)
            }
        }
        return notStored
    }

    /// Thins the kept originals of this step beside each of these pages to
    /// ONE per content (U3c review 3, LOW 1, fixed in U4a): with both
    /// contents gone and the list taking no new file, every Undo and Redo
    /// kept its outgoing bytes under a new name and nothing removed them, so
    /// the copies piled up, alternating between two contents. A kept copy
    /// whose bytes another kept copy of the same step and page holds too is
    /// superseded: no offer rests on it, since an offer rests on content,
    /// and that content stays beside the page. The copy this move just made
    /// (`newestLabel`) is the one kept for its content; otherwise the first
    /// by name. A copy that cannot be read is never removed, and nothing but
    /// this step's own kept copies is touched.
    static func removeSupersededKeptCopies(of step: UndoStep, root: URL, paths: [String], newestLabel: String) {
        for path in paths {
            let place: URL = root.appendingPathComponent(path)
            var keptFor: [String: URL] = [:]
            var others: [(url: URL, sha: String)] = []
            for kept in UndoRecovery.keptOriginalFiles(of: step, beside: place) {
                guard case .file(let data) = UndoItem.read(at: kept) else {
                    continue
                }
                let sha: String = UndoHash.sha256(of: data)
                if UndoSwap.isStaged(kept.lastPathComponent, label: newestLabel), let earlier = keptFor[sha] {
                    others.append((url: earlier, sha: sha))
                    keptFor[sha] = kept
                    continue
                }
                if keptFor[sha] == nil {
                    keptFor[sha] = kept
                } else {
                    others.append((url: kept, sha: sha))
                }
            }
            for superseded in others where keptFor[superseded.sha] != superseded.url {
                _ = UndoSwap.removeStaged(superseded.url)
            }
        }
    }

    /// Every kept original (`-orig`, a file) of this step's beside one
    /// place, by name order.
    static func keptOriginalFiles(of step: UndoStep, beside place: URL) -> [URL] {
        let folder: URL = place.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        let prefix: String = "." + place.lastPathComponent + UndoSwap.stagedMarker + "\(step.seq)-"
        var found: [URL] = []
        for name in names.sorted() where name.hasPrefix(prefix) && name.hasSuffix("-orig") {
            if UndoSwap.placeOfStagedName(name) != place.lastPathComponent {
                continue
            }
            let url: URL = folder.appendingPathComponent(name)
            if UndoSwap.isAFolderSetAside(url) {
                continue
            }
            found.append(url)
        }
        return found
    }

    /// Of these kept originals' hidden names, those whose bytes hash to what
    /// the journal recorded for their page (a `writeFile` op's before or
    /// after): kept because the list no longer holds that content, never
    /// because they differ from it (the first review of U3c, LOW 2).
    static func keptOriginalsOfWhatWasRecorded(_ names: [String], of step: UndoStep, root: URL) -> [String] {
        var recorded: [String] = []
        for op in step.ops where op.knownKind == .writeFile {
            guard let path = op.path else {
                continue
            }
            for kept in UndoRecovery.keptOriginalFiles(of: step, beside: root.appendingPathComponent(path)) {
                let name: String = kept.lastPathComponent
                if !names.contains(name) || recorded.contains(name) {
                    continue
                }
                guard case .file(let data) = UndoItem.read(at: kept) else {
                    continue
                }
                let sha: String = UndoHash.sha256(of: data)
                if sha == op.beforeSha || sha == op.afterSha {
                    recorded.append(name)
                }
            }
        }
        return recorded
    }

    /// The hidden name of every kept original of this step still beside the
    /// files it names, each once, in the order the step names its files.
    static func keptOriginalsLeft(of step: UndoStep, root: URL) -> [String] {
        var names: [String] = []
        for op in step.ops {
            for path in op.pathsNamed {
                for kept in UndoRecovery.keptOriginalFiles(of: step, beside: root.appendingPathComponent(path)) {
                    if !names.contains(kept.lastPathComponent) {
                        names.append(kept.lastPathComponent)
                    }
                }
            }
        }
        return names
    }

    /// The trail line for a teacher's folder found set aside, written
    /// before it is renamed (the intent first): being put back changed
    /// (what changed, counted against the step's record when the list
    /// still holds it), or kept under a visible name beside its place
    /// because something else holds that place (both named). A folder put
    /// back as recorded needs no line.
    static func noteAnAsideFolder(_ found: UndoAsideFolder, of step: UndoStep, root: URL, journal: UndoJournal?) {
        if found.putBack && found.matched {
            return
        }
        let place: String = UndoRecovery.insideTheFolder(found.place, root: root)
        var keptAs: String? = nil
        if let keptURL = found.keptAs {
            keptAs = UndoRecovery.insideTheFolder(keptURL, root: root)
        }
        var changes: String = ""
        if found.putBack {
            changes = UndoRecovery.whatChanged(at: found.foundAt, against: step, place: place, journal: journal)
        }
        UndoTrailHook.foundAFolderSetAsideLine?(step.course ?? "", step.section, place, found.hiddenName, keptAs, changes)
    }

    /// A place's path inside the working folder, or its last name when it
    /// is not inside it.
    static func insideTheFolder(_ url: URL, root: URL) -> String {
        let rootPath: String = root.standardizedFileURL.path + "/"
        let full: String = url.standardizedFileURL.path
        if full.hasPrefix(rootPath) {
            return String(full.dropFirst(rootPath.count))
        }
        return url.lastPathComponent
    }

    /// "1 file added, 2 changed" against the step's recorded listing, or
    /// "changed" when the list no longer holds it.
    static func whatChanged(at url: URL, against step: UndoStep, place: String, journal: UndoJournal?) -> String {
        var recordedSha: String? = nil
        for op in step.ops where op.path == place {
            recordedSha = op.listingSha
        }
        guard let journal, let recordedSha, let data = try? journal.blobContent(sha: recordedSha),
              let recorded = UndoTreeListing.parse(data),
              case .tree(let now, _) = UndoTreeReading.read(at: url) else {
            return "changed"
        }
        var before: [String: String] = [:]
        for file in recorded.files {
            before[file.path] = file.sha
        }
        var added: Int = 0
        var changed: Int = 0
        var seen: Set<String> = []
        for file in now.files {
            seen.insert(file.path)
            if let sha = before[file.path] {
                if sha != file.sha {
                    changed += 1
                }
            } else {
                added += 1
            }
        }
        var removed: Int = 0
        for (path, _) in before where !seen.contains(path) {
            removed += 1
        }
        var parts: [String] = []
        if added > 0 {
            parts.append(added == 1 ? "1 file added" : "\(added) files added")
        }
        if changed > 0 {
            parts.append(changed == 1 ? "1 changed" : "\(changed) changed")
        }
        if removed > 0 {
            parts.append(removed == 1 ? "1 removed" : "\(removed) removed")
        }
        return parts.isEmpty ? "changed" : parts.joined(separator: ", ")
    }

    /// Every tree op's folder of this step that a staged `-orig` name still
    /// holds beside it, by its place, with the hidden name.
    static func foldersKeptAside(of step: UndoStep, root: URL) -> [String: String] {
        var kept: [String: String] = [:]
        for op in step.ops where op.knownKind == .createTree || op.knownKind == .removeTree {
            guard let path = op.path else {
                continue
            }
            let place: URL = root.appendingPathComponent(path)
            let folder: URL = place.deletingLastPathComponent()
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
                continue
            }
            for name in names where name.hasPrefix("." + place.lastPathComponent + UndoSwap.stagedMarker + "\(step.seq)-") {
                if UndoSwap.placeOfStagedName(name) == place.lastPathComponent && UndoSwap.isAFolderSetAside(folder.appendingPathComponent(name)) {
                    kept[path] = name
                }
            }
        }
        return kept
    }

    /// The number of a step a dead process left in flight that keeps a file
    /// true by a rule, on this course (any course when none is given): the
    /// plain doors refuse while one waits, because only a recovery that
    /// re-derives may settle it (the third hard review of U2b, LOW 1).
    static func deadStepThatKeepsAFileTrue(_ writer: UndoJournalWriter, course: String?) -> Int? {
        for record in writer.fold.inFlight where UndoRecovery.keepsAFileTrue(record.step) {
            guard let process = record.process, !writer.journal.processIsAlive(process) else {
                continue
            }
            if let course, let stepCourse = record.step.course, course != stepCourse {
                continue
            }
            return record.step.seq
        }
        return nil
    }

    /// Whether a step holds a `recompute` op.
    static func keepsAFileTrue(_ step: UndoStep) -> Bool {
        for op in step.ops where op.knownKind == .recompute {
            return true
        }
        return false
    }

    /// The listing each tree op of a step recorded, by its folder's path:
    /// what a folder set aside must still be for recovery to put it back.
    static func asideListings(of step: UndoStep, root: URL) -> [String: String] {
        var listings: [String: String] = [:]
        for op in step.ops where op.knownKind == .createTree || op.knownKind == .removeTree {
            if let path = op.path, let listingSha = op.listingSha {
                listings[root.appendingPathComponent(path).standardizedFileURL.path] = listingSha
            }
        }
        return listings
    }

    /// Where each file of a step stands: before, after or neither.
    ///
    /// A move, a tree or an external op is one place of its own, named by
    /// `placeName` and judged whole (`UndoCheck.wholeState`): a move by its
    /// pair, never by one side.
    ///
    /// U4b (opKinds.wholeOps' order): an edit a move of the step carries is
    /// read where its folder is now (`placeNow`), and the move is judged as
    /// if the step's edits inside it were taken back, without the step's own
    /// staged files and kept originals inside it (`carryingMoveState`), so a
    /// step killed between its move and its edits settles whole, by content.
    static func fileStates(
        of step: UndoStep,
        root: URL,
        places: UndoExternalPlaces = UndoAppPreferences(),
        journal: UndoJournal? = nil
    ) -> [(path: String, state: UndoOpState)] {
        var order: [String] = []
        var states: [String: UndoOpState] = [:]
        var items: [String: UndoItem] = [:]
        let carriers: [String: UndoOp] = UndoCheck.carriers(in: step.ops)
        var carryingMoves: [UndoOp] = []
        for (_, carrier) in carriers where !carryingMoves.contains(carrier) {
            carryingMoves.append(carrier)
        }
        // Each page is read once, where it is now.
        for op in step.ops where !op.isWhole {
            guard let kind = op.knownKind, kind != .recompute, let path = op.path, items[path] == nil else {
                continue
            }
            var readPath: String = path
            if let carrier = carriers[path] {
                readPath = UndoRecovery.placeNow(of: path, carriedBy: carrier, root: root)
            }
            items[path] = UndoItem.read(at: root.appendingPathComponent(readPath))
        }
        // U4b3 door-3: a handed-over place's two ops are judged together
        // (`UndoCheck.handovers`, the one rule the plan uses too). The
        // leaver is judged with the place free once its filler stands on
        // its after side there; the filler with the place absent while its
        // leaver still stands on its before side there. So a step stopped
        // before, between or after the pair's swaps is all before, part
        // way or all after; a place holding something neither op recorded
        // leaves both `.neither`. Judged again until nothing changes, for
        // a chain of places (two links in a row).
        let handovers: [UndoHandover] = UndoCheck.handovers(in: step.ops)
        var freeFrom: [Bool] = Array(repeating: false, count: step.ops.count)
        var freeTo: [Bool] = Array(repeating: false, count: step.ops.count)
        var absentHere: [Bool] = Array(repeating: false, count: step.ops.count)
        func judge(_ index: Int) -> UndoOpState? {
            let op: UndoOp = step.ops[index]
            if op.isWhole {
                if carryingMoves.contains(op) {
                    return UndoRecovery.carryingMoveState(op, of: step, carriers: carriers, root: root, places: places, journal: journal)
                }
                return UndoCheck.wholeState(
                    of: op, root: root, places: places,
                    toIsHandedOver: freeTo[index], fromIsHandedOver: freeFrom[index]
                )
            }
            guard let kind = op.knownKind, kind != .recompute, let path = op.path else {
                return nil
            }
            if absentHere[index] {
                return UndoCheck.state(of: op, in: .absent)
            }
            return UndoCheck.state(of: op, in: items[path] ?? .absent)
        }
        var opStates: [UndoOpState?] = []
        var opIndex: Int = 0
        while opIndex < step.ops.count {
            opStates.append(judge(opIndex))
            opIndex += 1
        }
        var round: Int = 0
        while !handovers.isEmpty && round <= step.ops.count {
            var changed: Bool = false
            for handover in handovers {
                let leaver: Int = handover.leaverIndex
                let filler: Int = handover.fillerIndex
                if opStates[filler] == .after && !freeFrom[leaver] && !absentHere[leaver] {
                    if step.ops[leaver].isWhole {
                        freeFrom[leaver] = true
                    } else {
                        absentHere[leaver] = true
                    }
                    opStates[leaver] = judge(leaver)
                    changed = true
                }
                if opStates[leaver] == .before && !freeTo[filler] && !absentHere[filler] {
                    if step.ops[filler].isWhole {
                        freeTo[filler] = true
                    } else {
                        absentHere[filler] = true
                    }
                    opStates[filler] = judge(filler)
                    changed = true
                }
            }
            if !changed {
                break
            }
            round += 1
        }
        let movesHandingOver: Set<Int> = UndoRecovery.movesHandingOver(handovers, in: step.ops)
        var pathsSeen: Set<String> = []
        opIndex = 0
        while opIndex < step.ops.count {
            let op: UndoOp = step.ops[opIndex]
            let judged: UndoOpState? = opStates[opIndex]
            let index: Int = opIndex
            opIndex += 1
            if op.isWhole {
                let place: String = UndoRecovery.placeJudged(of: op, at: index, movesHandingOver: movesHandingOver)
                if states[place] == nil {
                    order.append(place)
                }
                states[place] = judged ?? .neither
                continue
            }
            guard let state = judged, let path = op.path else {
                continue
            }
            if !pathsSeen.contains(path) {
                pathsSeen.insert(path)
                order.append(path)
            }
            if let earlier = states[path] {
                if earlier == .cannotTell || state == .cannotTell {
                    states[path] = .cannotTell
                } else if earlier != state {
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

    /// U4b3 door-3: the step's moves that leave or fill a handed-over
    /// place, by their index in the step.
    static func movesHandingOver(_ handovers: [UndoHandover], in ops: [UndoOp]) -> Set<Int> {
        var found: Set<Int> = []
        for handover in handovers {
            if ops[handover.leaverIndex].isWhole {
                found.insert(handover.leaverIndex)
            }
            if ops[handover.fillerIndex].isWhole {
                found.insert(handover.fillerIndex)
            }
        }
        return found
    }

    /// The name `fileStates` judges a whole op under: its `placeName`, but
    /// for a move that hands a place over, its two places ("from → to"),
    /// since its `from` (its `placeName`) is the path of the file op it
    /// shares the place with, and the two are judged apart (U4b3 door-3).
    /// `settle` picks the ops to put back by the same name.
    static func placeJudged(of op: UndoOp, at index: Int, movesHandingOver: Set<Int>) -> String {
        if movesHandingOver.contains(index), let from = op.from, let to = op.to {
            return from + " → " + to
        }
        return op.placeName
    }

    /// Whether the folder (or file) a move carries edits with is at its old
    /// place now: nothing at `to` and something at `from`.
    static func isAtItsOldPlace(_ move: UndoOp, root: URL) -> Bool {
        guard let from = move.from, let to = move.to else {
            return false
        }
        let atTo: UndoItem = UndoItem.read(at: root.appendingPathComponent(to))
        let atFrom: UndoItem = UndoItem.read(at: root.appendingPathComponent(from))
        return atTo == .absent && atFrom != .absent
    }

    /// Where an edit named inside a move's new place is on the disk now:
    /// under the move's `from` while the folder is still (or again) there,
    /// otherwise where it is named (U4b).
    static func placeNow(of path: String, carriedBy move: UndoOp, root: URL) -> String {
        guard let from = move.from, let to = move.to, UndoRecovery.isAtItsOldPlace(move, root: root) else {
            return path
        }
        return UndoOp.placeBeforeTheMove(path, from: from, to: to)
    }

    /// A move that carries edits (U4b), judged on whichever side its folder
    /// is: each carried page as it is once the step's edits on it are taken
    /// back, and the step's own staged files and kept originals inside the
    /// folder left out, as the swap judges it (`ownFilesInside`). A carried
    /// page that is neither as the step left it nor as before is left as it
    /// is, so the move is then a change since too.
    static func carryingMoveState(
        _ move: UndoOp, of step: UndoStep, carriers: [String: UndoOp], root: URL,
        places: UndoExternalPlaces, journal: UndoJournal?
    ) -> UndoOpState {
        guard let from = move.from, let to = move.to else {
            return .neither
        }
        let atItsOldPlace: Bool = UndoRecovery.isAtItsOldPlace(move, root: root)
        let side: URL = root.appendingPathComponent(atItsOldPlace ? from : to)
        var overriding: [String: UndoItem] = [:]
        let ownMarker: String = UndoSwap.stagedMarker + "\(step.seq)-"
        if let walker = FileManager.default.enumerator(atPath: side.path) {
            while let inside = walker.nextObject() as? String {
                if (inside as NSString).lastPathComponent.contains(ownMarker) {
                    overriding[inside] = .absent
                }
            }
        }
        var index: Int = step.ops.count - 1
        while index >= 0 {
            let edit: UndoOp = step.ops[index]
            index -= 1
            guard let path = edit.path, edit.isWhole == false, let carrier = carriers[path], carrier == move else {
                continue
            }
            guard let inside = UndoOp.partInside(to, of: path) else {
                continue
            }
            let place: URL = inside.isEmpty ? side : side.appendingPathComponent(inside)
            let current: UndoItem = overriding[inside] ?? UndoItem.read(at: place)
            guard UndoCheck.state(of: edit, in: current) == .after, let journal else {
                continue
            }
            let takenBack: UndoItem? = (try? UndoCheck.moved(edit, from: current, direction: .backward, journal: journal)) ?? nil
            if let takenBack {
                overriding[inside] = takenBack
            }
        }
        if move.isCaseOnlyMove {
            // One place under two spellings: the same files either way.
            return UndoCheck.wholeState(of: move, root: root, places: places, overridingTo: overriding, overridingFrom: overriding)
        }
        if atItsOldPlace {
            return UndoCheck.wholeState(of: move, root: root, places: places, overridingFrom: overriding)
        }
        return UndoCheck.wholeState(of: move, root: root, places: places, overridingTo: overriding)
    }

    /// Every place a step's staged files can be beside: each path its ops
    /// name, and for an edit a move carries, the same page under the move's
    /// `from`, where the folder takes its kept originals when it moves back
    /// (U4b).
    static func placesStagedBeside(of step: UndoStep, root: URL) -> [URL] {
        var urls: [URL] = []
        for op in step.ops {
            for path in op.pathsNamed {
                urls.append(root.appendingPathComponent(path))
            }
        }
        for (path, carrier) in UndoCheck.carriers(in: step.ops) {
            if let from = carrier.from, let to = carrier.to {
                urls.append(root.appendingPathComponent(UndoOp.placeBeforeTheMove(path, from: from, to: to)))
            }
        }
        return urls
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
            case .neither, .cannotTell:
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
        places: UndoExternalPlaces = UndoAppPreferences(),
        swapRefused: inout Bool,
        leftFor: inout UndoRefusal?
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
        let urls: [URL] = UndoRecovery.placesStagedBeside(of: step, root: root)
        if mode == .live {
            // Before the plan is known to settle, every kept original that
            // differs from its page stays, even one whose bytes the list
            // gives (the Windows recovery review's 15; the first review of
            // U3c, LOW 1: a page the list holds may still be left part way
            // and the list cleared when ANOTHER page cannot be put back, and
            // then the kept original is the only copy). Those the list holds
            // are tidied only once the step has settled, below.
            UndoSwap.tidyLeftovers(
                label: label, beside: urls, asideListings: asideListings(of: step, root: root),
                onAside: { found in UndoRecovery.noteAnAsideFolder(found, of: step, root: root, journal: writer.journal) },
                root: root, keepingOnlyCopies: true
            )
            if UndoKillPoints.stopsHere(.afterRecoveryTidied) {
                return nil
            }
        }

        // Which state the work was moving FROM, and TO.
        let startedFromBefore: Bool = phase == .begin || phase == .redoing
        let startState: UndoOpState = startedFromBefore ? .before : .after
        var files: [(path: String, state: UndoOpState)] = fileStates(of: step, root: root, places: places, journal: writer.journal)
        // A teacher's folder still set aside after the tidying (its place
        // could not be read, or a rename failed) is IN THE WAY: never
        // settled as if the folder were gone (the second hard review of
        // U2b, MEDIUM 3), and a place that cannot be read stays "cannot
        // tell now", tried again, never a change since (the fourth review,
        // LOW 3).
        let keptAside: [String: String] = UndoRecovery.foldersKeptAside(of: step, root: root)
        if !keptAside.isEmpty {
            var judged: [(path: String, state: UndoOpState)] = []
            for file in files {
                if keptAside[file.path] != nil && file.state != .cannotTell {
                    judged.append((path: file.path, state: .neither))
                } else {
                    judged.append(file)
                }
            }
            files = judged
        }
        // A file that could not be read now is never judged changed by hand:
        // the step is left as it is and tried again on the schedule, as for
        // a file in use (the director's ruling on U2b's review).
        for file in files where file.state == .cannotTell {
            swapRefused = true
            leftFor = .cannotTellNow(path: file.path)
            return nil
        }
        var atStart: Int = 0
        var atEnd: Int = 0
        var inTheWay: [String] = []
        var endPaths: Set<String> = []
        // An `interrupted` line names files inside the working folder: an
        // external op's target is no path, so it is never named there.
        var externalTargets: Set<String> = []
        for op in step.ops where op.knownKind == .external {
            externalTargets.insert(op.placeName)
        }
        func pathsOnly(_ places: [String]) -> [String] {
            var result: [String] = []
            for place in places where !externalTargets.contains(place) {
                result.append(place)
            }
            return result
        }
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
        // Kept originals' bytes a put-back took that the list would not take
        // just now: no tidy removes a kept original holding them (the second
        // review of U3c, MEDIUM).
        var keptNotTaken: Set<String> = []
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
                let movesHandingOver: Set<Int> = UndoRecovery.movesHandingOver(UndoCheck.handovers(in: step.ops), in: step.ops)
                var opIndex: Int = 0
                for op in step.ops {
                    let place: String = op.isWhole
                        ? UndoRecovery.placeJudged(of: op, at: opIndex, movesHandingOver: movesHandingOver)
                        : op.placeName
                    if op.knownKind != .recompute && endPaths.contains(place) {
                        opsToPutBack.append(op)
                    }
                    opIndex += 1
                }
                let back: UndoDirection = startedFromBefore ? .backward : .forward
                // Content the list no longer holds is taken from the step's
                // own kept original beside the page when its hash is the one
                // recorded (Russell's ruling of 2026-11-20, 15:20): the first
                // tidy above left every such original for this.
                var keptOriginalNotRead: String? = nil
                var uses: [UndoKeptOriginalUse] = []
                let plan: UndoPlan = UndoCheck.plan(
                    opsToPutBack, direction: back, root: root, journal: writer.journal, places: places,
                    keptOriginal: UndoRecovery.keptOriginal(of: step, root: root, couldNotRead: { path in
                        if keptOriginalNotRead == nil {
                            keptOriginalNotRead = path
                        }
                    }),
                    keptOriginalUsed: { use in uses.append(use) },
                    ownSeq: step.seq
                )
                if case .refused(.contentMissing) = plan, let keptOriginalNotRead {
                    // A kept original that cannot be read just now may be the
                    // one: cannot tell now, so the step is left for the next
                    // recovery, never closed and the list never cleared (the
                    // first review of U3c, LOW 5).
                    swapRefused = true
                    leftFor = .cannotTellNow(path: keptOriginalNotRead)
                    return nil
                }
                if plan == .listUnreadable {
                    // Content it needs cannot be read just now: never
                    // closed for it, tried again on the schedule, as for a
                    // swap that was refused.
                    swapRefused = true
                    return nil
                }
                guard case .ready(let targets, _, _) = plan else {
                    // It can never be put back (no kept original matches
                    // what the list no longer holds): closed, never left in
                    // flight.
                    var leftPartWay: [String] = Array(endPaths).sorted()
                    for path in inTheWay where !leftPartWay.contains(path) {
                        leftPartWay.append(path)
                    }
                    let closing: [UndoEventLine] = [
                        UndoEventLine(seq: step.seq, event: .interrupted, phase: phase, reason: "couldNotPutBack", paths: pathsOnly(leftPartWay)),
                        UndoEventLine(seq: step.seq, event: .cleared, reason: UndoClearing.interrupted.rawValue),
                    ]
                    if !UndoRecovery.write(closing, step: step, writer) {
                        return nil
                    }
                    // Nothing that is an only copy is deleted: a kept
                    // original that differs from its page stays beside it
                    // under its hidden name (the list cannot put the page
                    // back, so `tidyClosedSteps` keeps it too). Only the
                    // staged new content and copies go.
                    UndoSwap.tidyLeftovers(label: label, beside: urls, root: root, keepingOnlyCopies: true)
                    UndoSwap.tidyLeftovers(label: label + "-recover", beside: urls, root: root, keepingOnlyCopies: true)
                    // Said after the tidy, so it names what is on the disk.
                    UndoTrailHook.couldNotPutBackLine?(
                        step.course ?? "", step.section, phase, leftPartWay.count,
                        UndoRecovery.keptOriginalsLeft(of: step, root: root)
                    )
                    return UndoRecoveryResult(seq: step.seq, phase: phase, outcome: .interrupted(filesInTheWay: leftPartWay.count, filesPutBack: 0))
                }
                // What the kept originals give, and what the pages hold now,
                // into the list before the swap (the first review of U3c,
                // MEDIUM). A step that stays on the list (an undo or a redo
                // put back to where it began) needs the content the swap sets
                // aside for its next Undo or Redo: kept beside its page when
                // the list will not take it. A change rolled back leaves the
                // list, and what it set aside is its own new content.
                // The plan is ready, so the list will put these pages back:
                // only now does a kept original whose bytes the list gives
                // go (the first review of U3c, LOW 1). One a put-back takes
                // from a kept original is not among them, its content not
                // in the list yet.
                UndoSwap.tidyLeftovers(
                    label: label, beside: urls, root: root, keepingOnlyCopies: true,
                    unlessTheListHolds: UndoRecovery.listHolds(step, root: root, from: writer.journal)
                )
                let notTaken: UndoWhatTheListCouldNotTake = UndoRecovery.storeWhatKeptOriginalsGive(uses, writer)
                var keepingTheOriginalsOf: Set<String> = []
                if phase != .begin {
                    keepingTheOriginalsOf = Set(notTaken.outgoingOf)
                    keptNotTaken = notTaken.keptOriginalsHolding
                }
                switch UndoSwap.swap(
                    targets, label: label + "-recover", places: places, root: root,
                    keepingTheOriginalsOf: keepingTheOriginalsOf
                ) {
                case .swapped:
                    break
                case .refused(let refusal), .notPutBack(let refusal, _):
                    // A file in use: tried again on the schedule.
                    swapRefused = true
                    leftFor = refusal
                    return nil
                case .stoppedByATest:
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
                events.append(UndoEventLine(seq: step.seq, event: .interrupted, phase: phase, reason: "partlyTookEffect", paths: pathsOnly(Array(endPaths).sorted())))
                events.append(UndoEventLine(seq: step.seq, event: .cleared, reason: UndoClearing.interrupted.rawValue))
            } else {
                outcome = .interrupted(filesInTheWay: inTheWay.count, filesPutBack: putBack)
                events.append(UndoEventLine(seq: step.seq, event: .interrupted, phase: phase, reason: "changedByHand", paths: pathsOnly(inTheWay)))
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
        // Settled (made, nothing taken effect, or put back): its kept
        // originals are needed no more. An `interrupted` or shadow outcome
        // keeps them (`tidyClosedSteps`, keeping only copies).
        switch outcome {
        case .completed, .nothingTookEffect, .rolledBack:
            if mode == .live {
                // Except a kept original whose bytes the list does not hold
                // (an edit that raced the swap): the only copy of it, kept
                // beside its page and named on the trail (the third review
                // of U3a, LOW 1).
                let listHolds: (URL, URL) -> Bool = UndoRecovery.listHolds(step, root: root, from: writer.journal)
                UndoSwap.tidyLeftovers(
                    label: label, beside: urls, root: root, keepingOnlyCopies: true,
                    unlessTheListHolds: listHolds, keepingCopiesHolding: keptNotTaken
                )
                UndoSwap.tidyLeftovers(
                    label: label + "-recover", beside: urls, root: root, keepingOnlyCopies: true,
                    unlessTheListHolds: listHolds, keepingCopiesHolding: keptNotTaken
                )
                let kept: [String] = UndoRecovery.keptOriginalsLeft(of: step, root: root)
                if !kept.isEmpty {
                    UndoTrailHook.keptAnOriginalLine?(
                        step.course ?? "", step.section, phase, kept,
                        UndoRecovery.keptOriginalsOfWhatWasRecorded(kept, of: step, root: root)
                    )
                }
            }
        case .interrupted, .leftAlone:
            break
        }
        // The files kept true by a rule are re-derived, whichever way the
        // step was settled, by `recoverAndRederive` once the lock is
        // released (re-deriving is idempotent): judged by its content ops
        // alone, a step that died after its swaps and before its
        // re-derivation would otherwise be left with its front page stale
        // (`undo.laterPieces.U2`; the Fable sweep of U1, T5).
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
        // Recovery runs before every prune, in the same hold (the Windows
        // recovery review's 14): a dead step past the limits would otherwise
        // be closed `unsettled`, its original tidied and its content deleted,
        // though a recovery could still have settled it.
        if !writer.recoveredInThisHold {
            return
        }
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
                    for path in op.pathsNamed where !paths.contains(path) {
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
                // Closed unsettled: a kept original that is the only copy of
                // its page's earlier content stays (the Windows recovery
                // review's 14).
                if mode == .live, let folder = record.step.workingFolder, let root = resolveRoot(folder) {
                    UndoRecovery.tidyStagedFiles(of: record.step, root: root, keepingOnlyCopies: true)
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
