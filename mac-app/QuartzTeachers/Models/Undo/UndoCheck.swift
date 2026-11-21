import Foundation

/// Where one op stands in the working folder now, judged by content alone.
nonisolated enum UndoOpState: String, Equatable, Sendable {
    /// As the step left it.
    case after
    /// As it was before the step (already back, for an undo).
    case before
    /// Neither: changed since, missing, a folder, or not readable as text.
    case neither
    /// The teacher's file is there and could not be read just now (no
    /// permission, a disk error, a cloud file not downloaded yet): cannot
    /// tell now. Never "changed since": only content that was read and
    /// differs is (the director's ruling on U2b's review). Refused without
    /// clearing the list, to be tried again.
    case cannotTell
}

/// What the contract's `undo.checkCases` call a verdict.
nonisolated enum UndoCheckVerdict: String, Equatable, Sendable {
    case canUndo
    case alreadyBack
    case changedSince
    case canRedo
    case alreadyRedone
    /// A file it must read could not be read now (`UndoOpState.cannotTell`).
    case cannotTell
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
    /// A folder or a link: something that is not a file.
    case notAFile
    /// Something is there and could not be read (EACCES, EIO, a file a
    /// cloud service has not downloaded): cannot tell now.
    case unreadable

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
            return .unreadable
        }
        if (information.st_mode & S_IFMT) != S_IFREG {
            return .notAFile
        }
        guard let data = try? Data(contentsOf: url) else {
            return .unreadable
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

    /// Where an op stands in a file's current content. A move, a tree or an
    /// external op is judged on the disk as a whole (`wholeState`), never
    /// here.
    static func state(of op: UndoOp, in item: UndoItem) -> UndoOpState {
        if item == .unreadable && op.knownKind != .recompute {
            return .cannotTell
        }
        switch op.knownKind {
        case .writeFile:
            let currentSha: String?
            switch item {
            case .absent:
                currentSha = nil
            case .file(let data):
                currentSha = UndoHash.sha256(of: data)
            case .notAFile, .unreadable:
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
        case .replaceText:
            return UndoHunk.state(of: op, in: item)
        case .editJSON:
            return UndoJSONMember.state(of: op, in: item)
        case .recompute:
            return .after
        case .move, .moveApart, .setAside, .createTree, .removeTree, .external, .none:
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
        case (.cannotTell, _):
            return .cannotTell
        }
    }

    /// The folder a step's paths are under, or nil when it cannot be
    /// reached. A step none of whose ops names a path (an `external` op
    /// alone) needs no folder: it is answered with the file system's root,
    /// which no op of it reads.
    static func root(of step: UndoStep, resolveRoot: (UndoWorkingFolder) -> URL?) -> URL? {
        var needsAFolder: Bool = false
        for op in step.ops where !op.pathsNamed.isEmpty {
            needsAFolder = true
        }
        if !needsAFolder {
            return URL(fileURLWithPath: "/", isDirectory: true)
        }
        guard let folder = step.workingFolder else {
            return nil
        }
        return resolveRoot(folder)
    }

    /// Every file an undo (`.backward`) or a redo (`.forward`) of these ops
    /// would write, checked first and writing nothing: refused, naming the
    /// first page in the way and how many others, when ANY op's content is
    /// neither as the step left it nor already where it is going, or is a
    /// line, a hunk or a member that cannot be placed. Only when no page is
    /// in the way is a blob missing from the list reported, as
    /// `contentMissing`.
    ///
    /// `keptOriginal`, given a page's path and the hash of the whole content
    /// a `writeFile` op wants there, answers that content from a kept
    /// original the step's own swap left beside the page (`-orig`) when its
    /// hash matches, for a blob the list no longer holds (Russell's ruling
    /// of 2026-11-20, 15:20, `undo.rule.recovery`): the page is put back
    /// from it instead of being refused `contentMissing`. Each such use is
    /// told to `keptOriginalUsed`, with what the page holds at that op (the
    /// content the other direction needs, which the swap is about to set
    /// aside), so the caller can write both back into the list before
    /// anything is swapped (the first review of U3c, MEDIUM).
    ///
    /// Ops on one file are applied to that file's text in turn (in reverse
    /// for an undo), so several lines on one page make one staged file. A
    /// move, a tree or an external op is judged on its own against what is
    /// there now (`wholeState`), and becomes one change of its own.
    ///
    /// `leavesApart` is true for an Undo or a Redo (never for making a step,
    /// nor for recovery): an op that stands apart (`UndoOp.standsApart`)
    /// and is found changed since, or an external op that cannot be set
    /// back now, is then LEFT where it is and named in `leftApart` instead
    /// of refusing the step, and the rest goes ahead (Russell's ruling of
    /// 2026-11-19 on Q3; #959; #897 piece B, seams 2 and 4).
    ///
    /// The step's `moveApart` ops (a section's website records) move as a
    /// GROUP (the director's decision of 2026-11-20, on #899): when any one
    /// of them is changed since (one host's deploy filled its place and
    /// another's did not), every one is left apart, so a section is never
    /// split across two websites (`groupStaysApart`).
    static func plan(
        _ ops: [UndoOp],
        direction: UndoDirection,
        root: URL,
        journal: UndoJournal,
        places: UndoExternalPlaces = UndoAppPreferences(),
        keptOriginal: ((_ path: String, _ sha: String) -> Data?)? = nil,
        keptOriginalUsed: ((UndoKeptOriginalUse) -> Void)? = nil,
        leavesApart: Bool = false
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
        var missingContentPath: String? = nil
        // Paths whose content is missing from the list: a later op on one
        // cannot be judged, because what the earlier op would have left
        // there is unknown (the review of U2a, LOW 2).
        var pathsWithMissingContent: Set<String> = []
        var recomputes: [UndoOp] = []
        var wholeTargets: [UndoSwapTarget] = []
        var cannotTellPath: String? = nil
        var leftApart: [String] = []
        let groupStaysApart: Bool = leavesApart && UndoCheck.aWebsiteRecordIsChangedSince(
            ordered, direction: direction, root: root, places: places
        )
        // U4b (opKinds.wholeOps' order): each edit named inside a move's new
        // place, after the move in the step, is carried by that move. Going
        // forward it is judged where the file is before the move and made
        // after it; going back it is taken back first, and the move is
        // judged as if it were.
        let carriers: [String: UndoOp] = UndoCheck.carriers(in: ops)
        var movingNow: Set<String> = []
        var stagedAtItsTurn: Set<String> = []
        var leadingTargets: [UndoSwapTarget] = []

        for op in ordered {
            guard let kind = op.knownKind else {
                // Never guessed at: a step this version cannot read is not
                // undone or redone (the director's ruling 1).
                return .refused(.notReadable)
            }
            if kind == .recompute {
                recomputes.append(op)
                continue
            }
            // Every place it names still inside the working folder, links
            // resolved: a folder on its path replaced by a link to outside
            // since the step was made is a change since, judged here before
            // anything is read through it (the second hard review of U2b,
            // MEDIUM 2). changedSince rather than cannotTell: the place was
            // read, and it is no longer the teacher's folder.
            var leavesTheFolder: Bool = false
            for place in op.pathsNamed where !UndoPlaces.staysInside(root, place) {
                leavesTheFolder = true
            }
            if leavesTheFolder {
                if !inTheWay.contains(op.placeName) {
                    inTheWay.append(op.placeName)
                }
                continue
            }
            if op.isWhole {
                var overridingTo: [String: UndoItem] = [:]
                var carriesEdits: Bool = false
                if let to = op.to {
                    for (path, carrier) in carriers where carrier == op {
                        carriesEdits = true
                        if direction == .backward, let item = working[path] {
                            let inside: String = path.count == to.count ? "" : String(path.dropFirst(to.count + 1))
                            overridingTo[inside] = item
                        }
                    }
                }
                let state: UndoOpState = UndoCheck.wholeState(of: op, root: root, places: places, overridingTo: overridingTo)
                let verdict: UndoCheckVerdict = UndoCheck.verdict(for: state, direction: direction)
                if verdict == .alreadyBack || verdict == .alreadyRedone {
                    continue
                }
                if verdict == .cannotTell {
                    if cannotTellPath == nil {
                        cannotTellPath = op.placeName
                    }
                    continue
                }
                if groupStaysApart && kind == .moveApart {
                    leftApart.append(op.placeName)
                    continue
                }
                var cannotGoBack: Bool = verdict == .changedSince
                if !cannotGoBack, op.knownKind == .external, let target = op.target {
                    let wanted: UndoJSON? = direction == .backward ? op.valueBefore : op.valueAfter
                    cannotGoBack = !places.canSet(target, wanted)
                }
                if cannotGoBack {
                    if leavesApart && op.standsApart {
                        leftApart.append(op.placeName)
                        continue
                    }
                    if !inTheWay.contains(op.placeName) {
                        inTheWay.append(op.placeName)
                    }
                    continue
                }
                let wholeOrNil: UndoSwapTarget?
                do {
                    wholeOrNil = try UndoCheck.wholeTarget(op, direction: direction, root: root, journal: journal)
                } catch {
                    return .listUnreadable
                }
                guard let target = wholeOrNil else {
                    if missingContentPath == nil {
                        missingContentPath = op.placeName
                    }
                    continue
                }
                if carriesEdits && direction == .forward, let to = op.to {
                    movingNow.insert(to)
                    leadingTargets.append(target)
                    continue
                }
                wholeTargets.append(target)
                continue
            }
            guard let path = op.path else {
                return .refused(.notReadable)
            }
            if original[path] == nil {
                var readPath: String = path
                if let carrier = carriers[path], let from = carrier.from, let to = carrier.to, movingNow.contains(to) {
                    readPath = UndoOp.placeBeforeTheMove(path, from: from, to: to)
                    stagedAtItsTurn.insert(path)
                }
                let item: UndoItem = UndoItem.read(at: root.appendingPathComponent(readPath))
                original[path] = item
                working[path] = item
                pathsInOrder.append(path)
            }
            if pathsWithMissingContent.contains(path) {
                continue
            }
            let current: UndoItem = working[path] ?? .absent
            let state: UndoOpState = UndoCheck.state(of: op, in: current)
            let verdict: UndoCheckVerdict = UndoCheck.verdict(for: state, direction: direction)
            if verdict == .alreadyBack || verdict == .alreadyRedone {
                continue
            }
            if verdict == .cannotTell {
                if cannotTellPath == nil {
                    cannotTellPath = path
                }
                pathsWithMissingContent.insert(path)
                continue
            }
            if verdict == .changedSince {
                if !inTheWay.contains(path) {
                    inTheWay.append(path)
                }
                continue
            }
            let movedOrNil: UndoItem?
            do {
                movedOrNil = try UndoCheck.moved(op, from: current, direction: direction, journal: journal)
            } catch {
                // Content that is there and cannot be read: the list is
                // unreadable for this attempt, never content missing.
                return .listUnreadable
            }
            guard let moved = movedOrNil else {
                if kind != .writeFile {
                    // As the step left it, yet it cannot be placed (the
                    // front matter block a line lives in is gone, a hunk or
                    // a member that cannot be put back exactly): the page
                    // was changed by hand since, never content missing from
                    // the list (ruling 13; the Fable sweep of U1, F2).
                    if !inTheWay.contains(path) {
                        inTheWay.append(path)
                    }
                    continue
                }
                // A blob the list no longer holds: put back from the kept
                // original beside the page when its hash is the one wanted.
                let wanted: String? = direction == .backward ? op.beforeSha : op.afterSha
                if let wanted, let kept = keptOriginal?(path, wanted) {
                    let otherSha: String? = direction == .backward ? op.afterSha : op.beforeSha
                    keptOriginalUsed?(UndoKeptOriginalUse(path: path, kept: kept, otherSha: otherSha, outgoing: current))
                    working[path] = .file(kept)
                    continue
                }
                // None matches. The check goes on, so every page in the way
                // is reported first.
                if missingContentPath == nil {
                    missingContentPath = path
                }
                pathsWithMissingContent.insert(path)
                continue
            }
            working[path] = moved
        }

        if let first = inTheWay.first {
            return .refused(.changedSince(firstPath: first, others: inTheWay.count - 1))
        }
        if let cannotTellPath {
            return .refused(.cannotTellNow(path: cannotTellPath))
        }
        if let missingContentPath {
            return .refused(.contentMissing(path: missingContentPath))
        }

        // Going forward, a move that carries edits goes in before them.
        var targets: [UndoSwapTarget] = leadingTargets
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
                replacement: after.data,
                stagesAtItsTurn: stagedAtItsTurn.contains(path)
            ))
        }
        for target in wholeTargets {
            targets.append(target)
        }
        return .ready(targets: targets, recomputes: recomputes, leftApart: leftApart)
    }

    /// Each edit's path a move of the step carries (`UndoOp.moveCarries`,
    /// the edit after the move), with that move.
    static func carriers(in ops: [UndoOp]) -> [String: UndoOp] {
        var found: [String: UndoOp] = [:]
        var index: Int = 0
        while index < ops.count {
            let move: UndoOp = ops[index]
            var later: Int = index + 1
            while later < ops.count {
                let edit: UndoOp = ops[later]
                if let path = edit.path, UndoOp.moveCarries(move, edit) {
                    found[path] = move
                }
                later += 1
            }
            index += 1
        }
        return found
    }

    /// Whether any `moveApart` op of a step (a website record) is changed
    /// since, judged as `plan` judges it: the one test that leaves the whole
    /// group apart.
    static func aWebsiteRecordIsChangedSince(
        _ ops: [UndoOp], direction: UndoDirection, root: URL, places: UndoExternalPlaces
    ) -> Bool {
        for op in ops where op.knownKind == .moveApart {
            var leavesTheFolder: Bool = false
            for place in op.pathsNamed where !UndoPlaces.staysInside(root, place) {
                leavesTheFolder = true
            }
            if leavesTheFolder {
                continue
            }
            let state: UndoOpState = UndoCheck.wholeState(of: op, root: root, places: places)
            if UndoCheck.verdict(for: state, direction: direction) == .changedSince {
                return true
            }
        }
        return false
    }

    /// The content after moving one op one way, or nil when a blob it needs
    /// is missing or the text cannot be read or placed.
    /// Throws when a blob it needs is there and cannot be read.
    static func moved(_ op: UndoOp, from item: UndoItem, direction: UndoDirection, journal: UndoJournal) throws -> UndoItem? {
        switch op.knownKind {
        case .writeFile:
            let wanted: String? = direction == .backward ? op.beforeSha : op.afterSha
            guard let wanted else {
                return .absent
            }
            guard let data = try journal.blobContent(sha: wanted) else {
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
        case .replaceText:
            return UndoHunk.moved(op, from: item, direction: direction)
        case .editJSON:
            return UndoJSONMember.moved(op, from: item, direction: direction)
        case .recompute, .move, .moveApart, .setAside, .createTree, .removeTree, .external, .none:
            return item
        }
    }

    /// The one change a move, a tree or an external op makes going this
    /// way, or nil when content it needs is missing from the list. Throws
    /// when content it needs is there and cannot be read.
    static func wholeTarget(_ op: UndoOp, direction: UndoDirection, root: URL, journal: UndoJournal) throws -> UndoSwapTarget? {
        switch op.knownKind {
        case .move, .moveApart, .setAside:
            guard let from = op.from, let to = op.to else {
                return nil
            }
            let source: String = direction == .backward ? to : from
            let destination: String = direction == .backward ? from : to
            return UndoSwapTarget(
                url: root.appendingPathComponent(destination),
                relativePath: destination,
                change: .moveHere(from: root.appendingPathComponent(source), fromPath: source, op: op)
            )
        case .createTree, .removeTree:
            guard let path = op.path, let listingSha = op.listingSha else {
                return nil
            }
            let makes: Bool = (op.knownKind == .createTree) == (direction == .forward)
            let url: URL = root.appendingPathComponent(path)
            // Whether the folder is made or taken out, the list must hold
            // everything needed to make it: a folder is never taken out
            // unless the list can put it back (the hard review of U2b, HIGH 2).
            guard let listingData = try journal.blobContent(sha: listingSha),
                  let listing = UndoTreeListing.parse(listingData), listing.sha == listingSha else {
                return nil
            }
            var contents: [String: Data] = [:]
            for file in listing.files {
                guard let data = try journal.blobContent(sha: file.sha) else {
                    return nil
                }
                contents[file.path] = data
            }
            if !makes {
                return UndoSwapTarget(url: url, relativePath: path, change: .takeTree(listingSha: listingSha))
            }
            return UndoSwapTarget(url: url, relativePath: path, change: .makeTree(listing, contents: contents))
        case .external:
            guard let target = op.target else {
                return nil
            }
            let expected: UndoJSON? = direction == .backward ? op.valueAfter : op.valueBefore
            let wanted: UndoJSON? = direction == .backward ? op.valueBefore : op.valueAfter
            return UndoSwapTarget(
                url: URL(fileURLWithPath: "/"),
                relativePath: target,
                change: .setExternal(target: target, expected: expected, value: wanted)
            )
        default:
            return nil
        }
    }
}

/// One page a check puts back from a kept original (`UndoCheck.plan`'s
/// `keptOriginalUsed`): the content taken from it, and what the page holds
/// at that op, which the swap sets aside and the other direction needs.
nonisolated struct UndoKeptOriginalUse: Equatable, Sendable {

    // MARK: - Stored properties

    /// The page, relative to the working folder.
    let path: String

    /// The kept original's bytes, which hash to what this direction wants.
    let kept: Data

    /// The hash the other direction wants there (nil: no file).
    let otherSha: String?

    /// What the page holds at this op, before the kept original goes in.
    let outgoing: UndoItem
}

/// What a put-back from kept originals could not write back into the list
/// (`UndoRecovery.storeWhatKeptOriginalsGive`).
nonisolated struct UndoWhatTheListCouldNotTake: Equatable, Sendable {

    // MARK: - Stored properties

    /// The pages whose outgoing content (what the other direction needs)
    /// the list did not take: the swap keeps it beside them.
    let outgoingOf: [String]

    /// The hashes of kept originals' bytes the list did not take: no tidy
    /// removes a kept original holding them, even once its page holds the
    /// same bytes (the second review of U3c, MEDIUM).
    let keptOriginalsHolding: Set<String>

    // MARK: - Computed properties

    /// Whether the list took everything.
    var isEmpty: Bool {
        return outgoingOf.isEmpty && keptOriginalsHolding.isEmpty
    }
}

/// What a check found.
nonisolated enum UndoPlan: Equatable, Sendable {
    /// `leftApart`: the places of ops that stand apart and are left where
    /// they are (`UndoCheck.plan`'s `leavesApart`), in the order judged.
    case ready(targets: [UndoSwapTarget], recomputes: [UndoOp], leftApart: [String])
    case refused(UndoRefusal)
    /// Content the step needs is there and cannot be read (a failing disk):
    /// refused for this attempt, the list left as it is.
    case listUnreadable
}

/// One change to make: a file's content swapped (what it must still hold,
/// and what goes in its place; nil: it is removed), or one of a whole op's
/// changes.
nonisolated struct UndoSwapTarget: Equatable, Sendable {

    // MARK: - Stored properties

    let url: URL

    let relativePath: String

    let expected: Data?

    let replacement: Data?

    let change: UndoSwapChange

    /// A file inside a folder this same swap moves in first (U4b): staged at
    /// its turn, once the move has gone in, never beforehand, when its
    /// folder is not there yet.
    let stagesAtItsTurn: Bool

    // MARK: - Initializer

    init(url: URL, relativePath: String, expected: Data?, replacement: Data?, stagesAtItsTurn: Bool = false) {
        self.url = url
        self.relativePath = relativePath
        self.expected = expected
        self.replacement = replacement
        self.change = .file
        self.stagesAtItsTurn = stagesAtItsTurn
    }

    init(url: URL, relativePath: String, change: UndoSwapChange) {
        self.url = url
        self.relativePath = relativePath
        self.expected = nil
        self.replacement = nil
        self.change = change
        self.stagesAtItsTurn = false
    }
}

/// The kinds of change a swap makes.
nonisolated enum UndoSwapChange: Equatable, Sendable {
    /// A file's content swapped: staged beside it, then renamed in.
    case file
    /// The item at `from` renamed onto the target, which must be free: one
    /// rename that never replaces (a move, either way). Re-checked as a pair
    /// first.
    case moveHere(from: URL, fromPath: String, op: UndoOp)
    /// A folder made with every file in it: built beside its place under a
    /// staged name, then renamed in, never over anything.
    case makeTree(UndoTreeListing, contents: [String: Data])
    /// A folder whose listing must still be this taken out: renamed aside
    /// under a staged name (its content is in the list), removed once every
    /// change has gone in.
    case takeTree(listingSha: String)
    /// An external target set (nil: removed), which must still hold
    /// `expected`.
    case setExternal(target: String, expected: UndoJSON?, value: UndoJSON?)
}

/// How a swap went.
nonisolated enum UndoSwapResult: Equatable, Sendable {
    case swapped
    case refused(UndoRefusal)
    /// Refused, and the swaps already made could not all be reversed: a
    /// file may hold the new content while its original sits beside it
    /// under a staged name. Never closed `failed`: the step is left IN
    /// FLIGHT, so recovery settles it from the content once this process is
    /// gone (`undo.rule.recovery`; the Windows W3 review's finding, matched
    /// here). The refusal is the one that stopped the swap; no new word.
    /// `keptOriginals` names each kept original left beside its page (its
    /// staged name, in the page's own folder): the only copy of what that
    /// page held, which no tidy removes while it differs from the page.
    case notPutBack(UndoRefusal, keptOriginals: [String])
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
///
/// U2's whole ops fit the same shape: a folder to make is built beside its
/// place and renamed in; a folder to take out is renamed aside and removed
/// at the end; a move is one rename that never replaces; an external target
/// goes in with them, after every file's content and in the step's order,
/// re-read just before it is set.
nonisolated enum UndoSwap {

    // MARK: - Stored properties

    /// The part of a staged file's name that says it is Plantoir's.
    static let stagedMarker: String = ".plantoir-undo-"

    // MARK: - Functions

    ///
    /// `leaveApart` is given by an Undo or a Redo only (never by making a
    /// step, nor by recovery): an external target that stands apart (a
    /// deploy set for later) and that cannot be set at the swap, because
    /// launchd refused it, the write was off the main thread, or it no
    /// longer holds what the check saw, is then LEFT as it is and handed to
    /// `leaveApart`, and the rest of the swap goes on, exactly as a marker
    /// is left apart (the review of U3b, LOW 3): one label that stays
    /// loaded must never block its step, and every step under it, for good.
    static func swap(
        _ targets: [UndoSwapTarget],
        label: String,
        places: UndoExternalPlaces = UndoAppPreferences(),
        root: URL? = nil,
        keepingTheOriginalsOf keptPaths: Set<String> = [],
        leaveApart: ((String) -> Void)? = nil,
        startsAtTheNextLogin: ((String) -> Void)? = nil
    ) -> UndoSwapResult {
        var staged: [URL?] = []
        var originals: [URL?] = []
        var swapsMade: Int = 0
        // The externals left apart at the swap: nothing of theirs to reverse.
        var leftApartAt: Set<Int> = []
        // Each folder this swap made for a place that had none (a moved
        // record's kept folder, a new page's folder), deepest last: removed
        // again, when empty, by a swap that is refused (the review of U3b,
        // LOW 4: a refused step left an empty kept folder behind).
        var foldersMade: [URL] = []

        /// Makes the folder a place goes in, noting each level it made.
        func makeTheFolder(for url: URL) {
            var missing: [URL] = []
            var folder: URL = url.deletingLastPathComponent()
            while folder.path != "/" && !FileManager.default.fileExists(atPath: folder.path) {
                missing.append(folder)
                folder = folder.deletingLastPathComponent()
            }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var index: Int = missing.count - 1
            while index >= 0 {
                if FileManager.default.fileExists(atPath: missing[index].path) {
                    foldersMade.append(missing[index])
                }
                index -= 1
            }
        }

        /// Removes every folder `makeTheFolder` made that is still empty,
        /// deepest first. `rmdir` never removes a folder with anything in it.
        func removeTheFoldersMade() {
            var index: Int = foldersMade.count - 1
            while index >= 0 {
                _ = foldersMade[index].withUnsafeFileSystemRepresentation { path in
                    guard let path else {
                        return Int32(-1)
                    }
                    return rmdir(path)
                }
                index -= 1
            }
            foldersMade = []
        }

        /// Writes a file's new content beside it under this swap's staged
        /// name: the staged URL, or nil (with anything part-made removed)
        /// when the disk is full or the folder will not take a new file.
        func stageAFile(_ target: UndoSwapTarget, at targetIndex: Int, replacement: Data) -> URL? {
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
                makeTheFolder(for: target.url)
                try FileManager.default.createDirectory(
                    at: target.url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? FileManager.default.removeItem(at: stagedURL)
                if UndoKillPoints.stagingWriteFailsAt?(targetIndex) == true {
                    // As a full disk does: the exclusive create makes the
                    // file, then writing into it fails.
                    try UndoFiles.writeDurably(Data(), to: stagedURL, mode: mode)
                    throw UndoJournalError.couldNotStoreContent(ENOSPC)
                }
                try UndoFiles.writeDurably(replacement, to: stagedURL, mode: mode)
                return stagedURL
            } catch {
                // The exclusive create may have made the file before the
                // write failed (the Fable sweep of U1, F1): it is this
                // swap's own, so it goes with every other staged file.
                // Staging writes a NEW file, which no other program can be
                // holding, so this is never `fileIsInUse`: the disk is full
                // or the folder will not take a new file.
                _ = UndoSwap.removeStaged(stagedURL)
                return nil
            }
        }

        /// What this swap has made or kept inside the place `folder`
        /// (staged files and kept originals), relative to it, as absent:
        /// a move's pair is judged without them (U4b).
        func ownFilesInside(_ folder: URL) -> [String: UndoItem] {
            var found: [String: UndoItem] = [:]
            let prefix: String = folder.path + "/"
            for url in staged + originals {
                if let url, url.path.hasPrefix(prefix) {
                    found[String(url.path.dropFirst(prefix.count))] = .absent
                }
            }
            return found
        }

        /// After a folder moved from `old` to `new`: every staged file and
        /// kept original of this swap inside it is named at its new place.
        func followTheMove(from old: URL, to new: URL) {
            let prefix: String = old.path + "/"
            var position: Int = 0
            while position < staged.count {
                if let url = staged[position], url.path.hasPrefix(prefix) {
                    staged[position] = URL(fileURLWithPath: new.path + "/" + String(url.path.dropFirst(prefix.count)))
                }
                position += 1
            }
            position = 0
            while position < originals.count {
                if let url = originals[position], url.path.hasPrefix(prefix) {
                    originals[position] = URL(fileURLWithPath: new.path + "/" + String(url.path.dropFirst(prefix.count)))
                }
                position += 1
            }
        }

        /// True when a test stopped it while a folder taken out was being
        /// removed, as a process that died there would stop.
        @discardableResult
        func tidy() -> Bool {
            for url in staged {
                if let url {
                    _ = UndoSwap.removeStaged(url)
                }
            }
            var originalIndex: Int = 0
            for url in originals {
                let index: Int = originalIndex
                originalIndex += 1
                guard let url else {
                    continue
                }
                // What a page held before a put-back from a kept original,
                // which the list could not take: the only copy of the
                // content the step's other direction needs, kept beside its
                // page under this swap's name (the first review of U3c,
                // MEDIUM).
                if index < targets.count, case .file = targets[index].change, keptPaths.contains(targets[index].relativePath) {
                    continue
                }
                if UndoSwap.isAFolderSetAside(url) {
                    // A folder taken out is renamed to a name recovery never
                    // puts back BEFORE it is deleted, so a delete cut short
                    // is finished, never mistaken for the teacher's folder
                    // (the fourth review of U2b, MEDIUM).
                    if UndoSwap.removeAFolderTakenOut(url) {
                        return true
                    }
                    continue
                }
                _ = UndoSwap.removeStaged(url)
            }
            return false
        }

        /// The kept originals of files still swapped: what a reversal that
        /// could not complete leaves beside its pages.
        func originalsLeft() -> [String] {
            var names: [String] = []
            var index: Int = 0
            while index < targets.count && index < originals.count {
                if case .file = targets[index].change, let original = originals[index] {
                    names.append(original.lastPathComponent)
                }
                index += 1
            }
            return names
        }

        /// Puts back every swap already made, newest first. False when any
        /// could not be put back (the result was ignored until the Windows
        /// W3 review: the step was then closed `failed` with a page left new
        /// and its original hidden beside it, recorded nowhere).
        func reverse() -> Bool {
            var everyOnePutBack: Bool = true
            var index: Int = swapsMade - 1
            while index >= 0 {
                let target: UndoSwapTarget = targets[index]
                let failsHere: Bool = UndoKillPoints.putBackFailsAt?(index) == true
                if leftApartAt.contains(index) {
                    index -= 1
                    continue
                }
                switch target.change {
                case .file:
                    if let original = originals[index] {
                        if !failsHere && UndoSwap.rename(original, onto: target.url) {
                            originals[index] = nil
                        } else {
                            everyOnePutBack = false
                        }
                    } else if failsHere {
                        everyOnePutBack = false
                    } else if UndoItem.read(at: target.url) != .absent {
                        if (try? FileManager.default.removeItem(at: target.url)) == nil {
                            everyOnePutBack = false
                        }
                    }
                case .moveHere(let from, _, _):
                    if failsHere || !UndoSwap.renameExclusively(target.url, onto: from) {
                        everyOnePutBack = false
                    } else {
                        followTheMove(from: target.url, to: from)
                    }
                case .makeTree:
                    // Back under its staged name, removed with the rest.
                    let stagedURL: URL = UndoSwap.besideURL(for: target.url, label: label, role: "new")
                    if !failsHere && UndoSwap.renameExclusively(target.url, onto: stagedURL) {
                        staged[index] = stagedURL
                    } else {
                        everyOnePutBack = false
                    }
                case .takeTree:
                    // Never removed by the tidy that follows: put back, or,
                    // if even that fails, left aside under its staged name.
                    if let original = originals[index] {
                        if !failsHere && UndoSwap.renameExclusively(original, onto: target.url) {
                            originals[index] = nil
                        } else {
                            everyOnePutBack = false
                        }
                    }
                case .setExternal(let externalTarget, let expected, _):
                    if failsHere || !places.write(externalTarget, expected) {
                        everyOnePutBack = false
                    }
                }
                index -= 1
            }
            return everyOnePutBack
        }

        /// A refusal once swaps may have been made: reversed and tidied, or,
        /// when the reversal could not complete, left exactly as it stands
        /// (every kept original where recovery's tidy will find it) for
        /// recovery to settle.
        func refusedAfterSwapping(_ refusal: UndoRefusal) -> UndoSwapResult {
            if !reverse() {
                return .notPutBack(refusal, keptOriginals: originalsLeft())
            }
            tidy()
            removeTheFoldersMade()
            return .refused(refusal)
        }

        // 1. Stage every new content beside its target.
        var stagingIndex: Int = 0
        for target in targets {
            let targetIndex: Int = stagingIndex
            stagingIndex += 1
            originals.append(nil)
            // Nothing is staged through a link that leaves the working folder
            // (the third hard review of U2b, LOW 3).
            if let root, !UndoSwap.staysInside(target, root: root) {
                staged.append(nil)
                tidy()
                removeTheFoldersMade()
                return .refused(.changedSince(firstPath: target.relativePath, others: 0))
            }
            if case .makeTree(let listing, let contents) = target.change {
                let stagedURL: URL = UndoSwap.besideURL(for: target.url, label: label, role: "new")
                makeTheFolder(for: target.url)
                _ = UndoSwap.removeStaged(stagedURL)
                let failsHere: Bool = UndoKillPoints.stagingWriteFailsAt?(targetIndex) == true
                if failsHere || !UndoTreeReading.make(listing, contents: contents, at: stagedURL) {
                    _ = UndoSwap.removeStaged(stagedURL)
                    staged.append(nil)
                    tidy()
                    removeTheFoldersMade()
                    return .refused(.couldNotWrite(path: target.relativePath))
                }
                staged.append(stagedURL)
                continue
            }
            guard case .file = target.change, let replacement = target.replacement, !target.stagesAtItsTurn else {
                staged.append(nil)
                continue
            }
            guard let stagedURL = stageAFile(target, at: targetIndex, replacement: replacement) else {
                staged.append(nil)
                tidy()
                removeTheFoldersMade()
                return .refused(.couldNotWrite(path: target.relativePath))
            }
            staged.append(stagedURL)
        }

        // 2. Swap them in, checking each target first.
        var index: Int = 0
        while index < targets.count {
            let target: UndoSwapTarget = targets[index]
            if UndoKillPoints.stopsHere(.beforeSwap(index)) {
                return .stoppedByATest
            }
            if UndoKillPoints.fileInUseAtSwap?(index) == true {
                return refusedAfterSwapping(.fileIsInUse(path: target.relativePath))
            }
            var refusal: UndoRefusal? = nil
            // Inside the working folder, its links resolved, at the moment of
            // the change (the second hard review of U2b, MEDIUM 2): a folder
            // on the path replaced by a link since the check is a change
            // since, and nothing moves through it.
            if let root, !UndoSwap.staysInside(target, root: root) {
                refusal = .changedSince(firstPath: target.relativePath, others: 0)
            }
            switch target.change {
            case _ where refusal != nil:
                break
            case .file:
                if target.stagesAtItsTurn, let replacement = target.replacement {
                    guard let stagedURL = stageAFile(target, at: index, replacement: replacement) else {
                        return refusedAfterSwapping(.couldNotWrite(path: target.relativePath))
                    }
                    staged[index] = stagedURL
                }
                var putBack: Bool = true
                refusal = UndoSwap.swapAFile(
                    target, index: index, label: label, staged: &staged, originals: &originals, putBack: &putBack
                )
                if let fileRefusal = refusal, !putBack {
                    // This file's own swap could not be put back: nothing
                    // more is reversed or tidied, recovery settles it.
                    _ = reverse()
                    return .notPutBack(fileRefusal, keptOriginals: originalsLeft())
                }
            case .moveHere(let from, _, let op):
                // The pair once more, just before the rename: the content at
                // the place it leaves, nothing where it goes.
                let atFrom: UndoMoveSide = UndoMoveSide.read(op, at: from, overriding: ownFilesInside(from))
                let atTarget: UndoMoveSide = UndoMoveSide.read(op, at: target.url)
                if atFrom == .cannotRead || atTarget == .cannotRead {
                    refusal = .cannotTellNow(path: target.relativePath)
                } else if atFrom != .holdsTheContent || atTarget != .free {
                    refusal = .changedSince(firstPath: target.relativePath, others: 0)
                } else {
                    makeTheFolder(for: target.url)
                    if !UndoSwap.renameExclusively(from, onto: target.url) {
                        refusal = .fileIsInUse(path: target.relativePath)
                    } else {
                        followTheMove(from: from, to: target.url)
                    }
                }
            case .makeTree:
                let there: UndoTreeReading = UndoTreeReading.read(at: target.url)
                if there == .cannotRead {
                    refusal = .cannotTellNow(path: target.relativePath)
                } else if there != .absent {
                    refusal = .changedSince(firstPath: target.relativePath, others: 0)
                } else if let stagedURL = staged[index], UndoSwap.renameExclusively(stagedURL, onto: target.url) {
                    staged[index] = nil
                } else {
                    refusal = .fileIsInUse(path: target.relativePath)
                }
            case .takeTree(let listingSha):
                // Renamed aside FIRST, then its listing checked where nobody
                // else writes into it: a file added while the folder was
                // being walked can no longer go aside unseen and be deleted
                // with it (the hard review of U2b, MEDIUM 4). A folder that
                // differs is put back as it is and the take-out refused.
                // The next free name, as for a file's kept original: one
                // that is taken is never this swap's own, so it is never
                // reused or refused for good (the first review of U3c,
                // LOW 3).
                guard let asideURL = UndoSwap.freeKeptName(for: target.url, label: label) else {
                    return refusedAfterSwapping(.couldNotWrite(path: target.relativePath))
                }
                if !UndoSwap.renameExclusively(target.url, onto: asideURL) {
                    if UndoTreeReading.read(at: target.url).listingSha != listingSha {
                        refusal = .changedSince(firstPath: target.relativePath, others: 0)
                    } else {
                        refusal = .fileIsInUse(path: target.relativePath)
                    }
                } else if UndoTreeReading.read(at: asideURL).listingSha != listingSha {
                    // Put back as it is: a change since. If its place was taken
                    // in that instant it stays aside, hidden and whole, never
                    // deleted, and the refusal is cannotTellNow, which never
                    // clears the list (the second hard review, MEDIUM 3).
                    if UndoSwap.renameExclusively(asideURL, onto: target.url) {
                        refusal = .changedSince(firstPath: target.relativePath, others: 0)
                    } else {
                        refusal = .cannotTellNow(path: target.relativePath)
                    }
                } else {
                    originals[index] = asideURL
                }
            case .setExternal(let externalTarget, let expected, let value):
                if !UndoCheck.externalMatches(places.read(externalTarget), expected) {
                    refusal = .changedSince(firstPath: target.relativePath, others: 0)
                } else {
                    switch places.writeSaying(externalTarget, value) {
                    case .written:
                        break
                    case .notWritten:
                        refusal = .couldNotWrite(path: target.relativePath)
                    case .startsAtTheNextLogin:
                        // Set back, and launchd would not load it now: it
                        // starts at the next login. Named on its own, never
                        // as left apart (the re-review of U3b's fixes, LOW 2).
                        startsAtTheNextLogin?(target.relativePath)
                    }
                }
                if refusal != nil, let leaveApart, externalTarget.hasPrefix(UndoOp.scheduledDeployFamily + ":") {
                    // Left as it is and named, the rest goes on: an Undo or
                    // a Redo only (see `leaveApart`).
                    leaveApart(target.relativePath)
                    leftApartAt.insert(index)
                    refusal = nil
                }
            }
            if let refusal {
                return refusedAfterSwapping(refusal)
            }
            swapsMade += 1
            index += 1
        }

        // 3. Every swap went in: the kept originals are no longer needed.
        if tidy() {
            return .stoppedByATest
        }
        for target in targets {
            if case .setExternal = target.change {
                continue
            }
            UndoFiles.syncFolder(target.url.deletingLastPathComponent())
        }
        return .swapped
    }

    /// Whether every place a change touches is still inside the working
    /// folder, links resolved.
    static func staysInside(_ target: UndoSwapTarget, root: URL) -> Bool {
        switch target.change {
        case .setExternal:
            return true
        case .moveHere(_, let fromPath, _):
            return UndoPlaces.staysInside(root, fromPath) && UndoPlaces.staysInside(root, target.relativePath)
        default:
            return UndoPlaces.staysInside(root, target.relativePath)
        }
    }

    /// One file's swap: re-read, keep the original, rename the new content
    /// in (or remove the file). The refusal, or nil when it went in.
    ///
    /// After the rename the kept original is read back (the Windows W2b
    /// review's finding, matched here; documentation 12, W2b). Another
    /// program that edited the file IN PLACE between the re-read and the
    /// rename wrote into the inode the original is a hard link to, so its
    /// edit is there and nowhere else: the tidy would have deleted it. When
    /// the original no longer holds what the check saw, it is put back over
    /// the new content and the swap is refused `changedSince` (the edit is
    /// the teacher's, kept whole); when it cannot be read back, it is put
    /// back too and the swap is refused `cannotTellNow`. `putBack` is false
    /// when that put-back itself failed. A volume without hard links keeps a
    /// COPY (`keep`), which an edit after the copy never reaches: there the
    /// race is not seen, as before.
    private static func swapAFile(
        _ target: UndoSwapTarget,
        index: Int,
        label: String,
        staged: inout [URL?],
        originals: inout [URL?],
        putBack: inout Bool
    ) -> UndoRefusal? {
        let now: UndoItem = UndoItem.read(at: target.url)
        if now == .unreadable {
            return .cannotTellNow(path: target.relativePath)
        }
        if now.data != target.expected || (target.expected == nil && now != .absent) {
            return .changedSince(firstPath: target.relativePath, others: 0)
        }
        if now != .absent {
            // A name nothing holds. One that is taken is not this swap's own
            // (it has kept nothing yet), so it is never removed: it may be
            // the only copy of what the page once held, kept by an earlier
            // undo of this same step whose edit raced it, by another Mac
            // syncing this folder, or by a list since started again, whose
            // step numbers can be the same as this one's (the third review
            // of U3a, LOW 6). The next free name, `-2-orig`, `-3-orig` and
            // on, still reads as this label's kept original.
            // Kept only under a name this swap makes itself, never over a
            // file that appeared there after the name was found free: then
            // the next free name is taken (the first review of U3c, LOW 4).
            var originalURL: URL = UndoSwap.besideURL(for: target.url, label: label, role: "orig")
            var keptFailure: Int32? = nil
            var tries: Int = 0
            while true {
                tries += 1
                guard tries <= 1000, let freeURL = UndoSwap.freeKeptName(for: target.url, label: label) else {
                    return .couldNotWrite(path: target.relativePath)
                }
                originalURL = freeURL
                UndoKillPoints.beforeKeepingTheOriginal?(index, originalURL)
                keptFailure = UndoKillPoints.keepingTheOriginalFails?(index)
                if keptFailure == nil {
                    keptFailure = UndoSwap.keep(target.url, as: originalURL)
                }
                if keptFailure != EEXIST {
                    break
                }
            }
            if let keptFailure {
                // Only what this swap made: `keep` never makes a file over
                // one that is there, so this is a part-made copy of its own.
                _ = UndoSwap.removeStaged(originalURL)
                // On a volume without hard links the original is COPIED,
                // and a copy can fail for room or permission: the same word
                // as a staging write that fails (the review of U2a, LOW 1).
                if UndoSwap.isRoomOrPermission(keptFailure) {
                    return .couldNotWrite(path: target.relativePath)
                }
                return .fileIsInUse(path: target.relativePath)
            }
            originals[index] = originalURL
        }
        UndoKillPoints.beforeTheRename?(index, target.url)
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
            return .fileIsInUse(path: target.relativePath)
        }
        guard let originalURL = originals[index] else {
            return nil
        }
        let keptNow: UndoItem = UndoItem.read(at: originalURL)
        if keptNow.data == target.expected && keptNow.data != nil {
            return nil
        }
        let refusal: UndoRefusal = keptNow == .unreadable
            ? .cannotTellNow(path: target.relativePath)
            : .changedSince(firstPath: target.relativePath, others: 0)
        if UndoKillPoints.putBackFailsAt?(index) != true && UndoSwap.rename(originalURL, onto: target.url) {
            originals[index] = nil
        } else {
            putBack = false
        }
        return refusal
    }

    /// A rename that never replaces what is at the destination
    /// (`RENAME_EXCL`): false when anything is there, or it failed.
    static func renameExclusively(_ from: URL, onto to: URL) -> Bool {
        let result: Int32 = from.withUnsafeFileSystemRepresentation { fromPath in
            return to.withUnsafeFileSystemRepresentation { toPath in
                guard let fromPath, let toPath else {
                    return -1
                }
                return renamex_np(fromPath, toPath, UInt32(RENAME_EXCL))
            }
        }
        return result == 0
    }

    /// `.<name>.plantoir-undo-<label>-<role>` in the target's own folder:
    /// a dot file, so Obsidian and the website builder pass over it.
    static func besideURL(for target: URL, label: String, role: String) -> URL {
        let name: String = "." + target.lastPathComponent + stagedMarker + label + "-" + role
        return target.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// The place a staged name stands beside: the name between its leading
    /// dot and its LAST `.plantoir-undo-`, or nil.
    static func placeOfStagedName(_ name: String) -> String? {
        guard name.hasPrefix("."), let marker = name.range(of: stagedMarker, options: .backwards) else {
            return nil
        }
        let place: String = String(name[name.index(after: name.startIndex)..<marker.lowerBound])
        return place.isEmpty ? nil : place
    }

    /// The staged name a folder taken out is renamed to before it is
    /// deleted: its `-orig` role becomes `-gone`, which `isAFolderSetAside`
    /// never matches, so recovery finishes the delete of whatever is left
    /// under it as it does any staged file.
    static func goneURL(for asideURL: URL) -> URL {
        let name: String = asideURL.lastPathComponent
        let stem: String = name.hasSuffix("-orig") ? String(name.dropLast("-orig".count)) : name
        return asideURL.deletingLastPathComponent().appendingPathComponent(stem + "-gone")
    }

    /// Deletes a folder a swap took out, once every change has gone in: one
    /// rename to its `-gone` name (atomic: the folder is wholly the teacher's
    /// set-aside folder or wholly a leftover to finish deleting), then the
    /// recursive delete, which is not atomic. If the rename fails the folder
    /// is left whole under its `-orig` name, never deleted in place. True
    /// only when a test stopped it between the rename and the end of the
    /// delete (`UndoKillPoint.whileDeletingAFolder`).
    static func removeAFolderTakenOut(_ asideURL: URL) -> Bool {
        let goneURL: URL = UndoSwap.goneURL(for: asideURL)
        if FileManager.default.fileExists(atPath: goneURL.path) {
            // An earlier delete under this label cut short: finished first.
            try? FileManager.default.removeItem(at: goneURL)
        }
        if !UndoSwap.renameExclusively(asideURL, onto: goneURL) {
            return false
        }
        if UndoKillPoints.stopsHere(.whileDeletingAFolder) {
            return true
        }
        _ = UndoSwap.removeStaged(goneURL)
        return false
    }

    /// The first name nothing holds for this label's kept original beside
    /// a place: `-orig`, then `-2-orig`, `-3-orig` and on, for a file's
    /// original and a folder set aside alike. Nil after a thousand.
    static func freeKeptName(for place: URL, label: String) -> URL? {
        var keptURL: URL = UndoSwap.besideURL(for: place, label: label, role: "orig")
        var number: Int = 2
        while UndoSwap.somethingIsAt(keptURL) {
            if number > 1000 {
                return nil
            }
            keptURL = UndoSwap.besideURL(for: place, label: label, role: "\(number)-orig")
            number += 1
        }
        return keptURL
    }

    /// Whether anything (a file, a folder, a link, even a broken one) holds
    /// this name.
    static func somethingIsAt(_ url: URL) -> Bool {
        var information: stat = stat()
        let found: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return lstat(path, &information)
        }
        return found == 0
    }

    /// Whether a staged item is a folder kept aside as an original (`-orig`):
    /// a folder a tree op took out, which holds the teacher's files.
    static func isAFolderSetAside(_ url: URL) -> Bool {
        if !url.lastPathComponent.hasSuffix("-orig") {
            return false
        }
        var information: stat = stat()
        let found: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return lstat(path, &information)
        }
        return found == 0 && (information.st_mode & S_IFMT) == S_IFDIR
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

    /// Whether an error number says the disk is full or the folder will not
    /// take a new file, rather than that a file is held.
    static func isRoomOrPermission(_ failure: Int32) -> Bool {
        return failure == ENOSPC || failure == EDQUOT || failure == EROFS || failure == EACCES || failure == EPERM
    }

    /// Keeps the original under a second name: a hard link where the volume
    /// has them, a copy (data, mode, extended attributes) where it does not.
    /// Nil when it was kept, otherwise the error number of the last try.
    static func keep(_ url: URL, as keptURL: URL) -> Int32? {
        let linked: Int32 = url.withUnsafeFileSystemRepresentation { fromPath in
            return keptURL.withUnsafeFileSystemRepresentation { toPath in
                guard let fromPath, let toPath else {
                    return -1
                }
                return link(fromPath, toPath) == 0 ? 0 : errno
            }
        }
        if linked == 0 {
            return nil
        }
        if linked == EEXIST {
            // Something appeared at the name: never copied over, never this
            // swap's to remove.
            return EEXIST
        }
        return UndoSwap.keepByCopying(url, as: keptURL)
    }

    /// The copy a volume without hard links keeps an original as: data,
    /// mode and extended attributes, and EXCLUSIVE, so a file that appears
    /// at the name in this instant is never overwritten (the first review of
    /// U3c, LOW 4; `EEXIST` then). Nil when it was kept.
    static func keepByCopying(_ url: URL, as keptURL: URL) -> Int32? {
        let flags: copyfile_flags_t = copyfile_flags_t(COPYFILE_DATA | COPYFILE_SECURITY | COPYFILE_XATTR | COPYFILE_EXCL)
        let copied: Int32 = url.withUnsafeFileSystemRepresentation { fromPath in
            return keptURL.withUnsafeFileSystemRepresentation { toPath in
                guard let fromPath, let toPath else {
                    return -1
                }
                let result: Int32 = copyfile(fromPath, toPath, nil, flags)
                return result == 0 ? 0 : errno
            }
        }
        if copied == 0 {
            return nil
        }
        return copied
    }

    /// Whether a kept original's bytes hash to one of these.
    static func holdsAnyOf(_ shas: Set<String>, _ keptURL: URL) -> Bool {
        if shas.isEmpty {
            return false
        }
        guard case .file(let kept) = UndoItem.read(at: keptURL) else {
            return false
        }
        return shas.contains(UndoHash.sha256(of: kept))
    }

    /// Whether a kept original is NOT the only copy of what it holds: its
    /// place holds a file with the same bytes (the original was kept and the
    /// new content never went in, or recovery put it back). A kept original
    /// that differs from its place, or whose place is gone, is the only copy
    /// of what the page held before, and of an edit that raced the swap
    /// (the second review of U3a, MEDIUM b).
    static func isACopyOfItsPlace(_ keptURL: URL, place: URL) -> Bool {
        guard case .file(let kept) = UndoItem.read(at: keptURL) else {
            return false
        }
        guard case .file(let there) = UndoItem.read(at: place) else {
            return false
        }
        return kept == there
    }

    /// Removes one of the swap's OWN staged files. A kept original copied
    /// from a file marked immutable carries the mark (copyfile keeps it:
    /// measured in U1's third round, the copy was `uchg` and could not be
    /// removed), so a removal that is refused clears the file's flags and
    /// tries once more. Only ever a staged file, and only one with a single
    /// link: a kept original that is a hard link shares its flags with the
    /// teacher's page (a reference course's lock, plan 2.6), and those are
    /// never touched.
    static func removeStaged(_ url: URL) -> Bool {
        if (try? FileManager.default.removeItem(at: url)) != nil {
            return true
        }
        var information: stat = stat()
        let cleared: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            if lstat(path, &information) != 0 || information.st_nlink != 1 || (information.st_mode & S_IFMT) != S_IFREG {
                return -1
            }
            return chflags(path, 0)
        }
        if cleared != 0 {
            return false
        }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    /// The visible name a folder set aside is kept under when something
    /// else holds its place: `<name> (kept by Undo)`, then `(kept by Undo
    /// 2)`, `(kept by Undo 3)` and on, the first that nothing holds.
    static func visibleName(for place: String, number: Int) -> String {
        if number <= 1 {
            return place + " (kept by Undo)"
        }
        return place + " (kept by Undo \(number))"
    }

    /// Renames a folder set aside to the first visible name beside its
    /// place that nothing holds, never over anything. True when it went.
    static func keepUnderAVisibleName(
        _ stagedURL: URL,
        place: URL,
        hiddenName: String,
        matched: Bool,
        onAside: ((UndoAsideFolder) -> Void)?
    ) -> Bool {
        var number: Int = 1
        while number <= 1000 {
            let keptURL: URL = place.deletingLastPathComponent().appendingPathComponent(
                UndoSwap.visibleName(for: place.lastPathComponent, number: number)
            )
            number += 1
            if UndoTreeReading.read(at: keptURL) != .absent {
                continue
            }
            onAside?(UndoAsideFolder(place: place, hiddenName: hiddenName, foundAt: stagedURL, keptAs: keptURL, matched: matched))
            if UndoSwap.renameExclusively(stagedURL, onto: keptURL) {
                return true
            }
            if UndoTreeReading.read(at: keptURL) == .absent {
                // Not taken in that instant: the rename itself failed.
                return false
            }
        }
        return false
    }

    /// Removes what a swap for this label left beside these files. True
    /// when nothing of it is left (a file another program holds, or one
    /// made immutable, stays until a later try).
    ///
    /// A FOLDER set aside (`-orig`, a tree taken out) is the teacher's own
    /// and is never deleted here. Whenever its place is free it is renamed
    /// back into it, whatever its listing; whether its listing is the one
    /// `asideListings` records for that place decides what recovery makes
    /// of the step, not where the folder goes (the director's rule after
    /// U2b's third review). When something else holds its place it is
    /// renamed to a visible name beside it, `<name> (kept by Undo)`, or
    /// `(kept by Undo 2)` and on when that is taken too, so nothing of the
    /// teacher's stays hidden and nothing is merged or overwritten
    /// (Russell's ruling of 2026-11-19). Both renames never replace, so
    /// either happened or did not, and a death after one leaves nothing to
    /// redo. `onAside` is told BEFORE the rename (the intent first: a death
    /// between the rename and the trail line would lose it, the fourth
    /// review's LOW 4). When its place cannot be read now, it is left as it
    /// is for a later try and nothing is said (LOW 3). Its place is read
    /// from the name itself, up to the LAST marker, so a recovery's own
    /// `-recover-orig` is read as the same place. A `-gone` folder is a
    /// delete cut short (`removeAFolderTakenOut`) and is finished here.
    @discardableResult
    static func tidyLeftovers(
        label: String,
        beside urls: [URL],
        asideListings: [String: String] = [:],
        onAside: ((UndoAsideFolder) -> Void)? = nil,
        root: URL? = nil,
        keepingOnlyCopies: Bool = false,
        unlessTheListHolds listHolds: ((_ kept: URL, _ place: URL) -> Bool)? = nil,
        keepingCopiesHolding notInTheList: Set<String> = []
    ) -> Bool {
        var allGone: Bool = true
        var folders: [URL] = []
        for url in urls {
            let folder: URL = url.deletingLastPathComponent()
            if !folders.contains(folder) {
                folders.append(folder)
            }
        }
        for folder in folders {
            // Never tidied through a link that leaves the working folder (the
            // third hard review of U2b, LOW 3).
            if let root, let rootReal = UndoPlaces.resolved(root.path),
               let folderReal = UndoPlaces.resolved(folder.path),
               folderReal != rootReal && !folderReal.hasPrefix(rootReal + "/") {
                continue
            }
            let names: [String]
            do {
                names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            } catch CocoaError.fileReadNoSuchFile {
                // The folder is gone, and whatever was staged in it.
                continue
            } catch {
                // Not known to be tidied: a later try looks again.
                allGone = false
                continue
            }
            for name in names where UndoSwap.isStaged(name, label: label) {
                let stagedURL: URL = folder.appendingPathComponent(name)
                if UndoSwap.isAFolderSetAside(stagedURL) {
                    // A teacher's folder a dead process renamed aside.
                    guard let original = UndoSwap.placeOfStagedName(name) else {
                        allGone = false
                        continue
                    }
                    let originalURL: URL = folder.appendingPathComponent(original)
                    let recorded: String? = asideListings[originalURL.standardizedFileURL.path]
                    let matched: Bool = recorded != nil && UndoTreeReading.read(at: stagedURL).listingSha == recorded
                    let inItsPlace: UndoTreeReading = UndoTreeReading.read(at: originalURL)
                    if inItsPlace == .cannotRead {
                        // Not known to be free or taken: a later try looks again.
                        allGone = false
                        continue
                    }
                    if inItsPlace == .absent {
                        onAside?(UndoAsideFolder(place: originalURL, hiddenName: name, foundAt: stagedURL, keptAs: nil, matched: matched))
                        if !UndoSwap.renameExclusively(stagedURL, onto: originalURL) {
                            allGone = false
                        }
                        continue
                    }
                    if !UndoSwap.keepUnderAVisibleName(stagedURL, place: originalURL, hiddenName: name, matched: matched, onAside: onAside) {
                        allGone = false
                    }
                    continue
                }
                // A step that did not settle keeps a kept original that is
                // the only copy of what its page held (the second review of
                // U3a, MEDIUM b, and the Windows recovery review's 15): never
                // tidied away, left beside its page under its staged name.
                // With `listHolds`, a kept original whose bytes are exactly
                // what the list gives for its page (by the recorded hash, or
                // derived from what the page holds now) is not the only copy,
                // so it is tidied; one that holds anything else (an edit that
                // raced the swap, a hand edit) is kept (the third review of
                // U3a, LOW 1).
                if keepingOnlyCopies && name.hasSuffix("-orig"), let place = UndoSwap.placeOfStagedName(name) {
                    let placeURL: URL = folder.appendingPathComponent(place)
                    let theListHoldsIt: Bool = listHolds?(stagedURL, placeURL) ?? false
                    if !UndoSwap.isACopyOfItsPlace(stagedURL, place: placeURL) && !theListHoldsIt {
                        continue
                    }
                    // A copy of its page whose bytes the list would not take
                    // just now: the step's next move the other way would
                    // leave them in no file, so it stays (the second review
                    // of U3c, MEDIUM).
                    if UndoSwap.holdsAnyOf(notInTheList, stagedURL) {
                        continue
                    }
                }
                if !UndoSwap.removeStaged(stagedURL) {
                    allGone = false
                }
            }
        }
        return allGone
    }
}

/// A teacher's folder recovery found set aside by a dead process, as it is
/// about to be put back or kept under a visible name.
nonisolated struct UndoAsideFolder: Equatable, Sendable {

    // MARK: - Stored properties

    /// Where it belongs.
    let place: URL

    /// The hidden name it was found under.
    let hiddenName: String

    /// Where it is as it is reported: under its hidden name, since the
    /// report comes before the rename.
    let foundAt: URL

    /// Nil when it is being put back in its place; otherwise the visible
    /// name beside it that it is being kept under, because something else
    /// holds its place.
    let keptAs: URL?

    /// Whether its listing was the one the step recorded.
    let matched: Bool

    // MARK: - Computed properties

    /// True when it is being put back in its place.
    var putBack: Bool {
        return keptAs == nil
    }
}

/// How an undo or a redo went.
nonisolated enum UndoOutcome: Equatable, Sendable {
    /// `leftApart`: what stands apart from the step and was left where it
    /// is (a rollover's marker after a deploy filled its place, a deploy set
    /// for later whose moment has gone by), by place, for U7 to say once
    /// (Russell's ruling of 2026-11-19 on Q3). Empty for every other step.
    ///
    /// `startsAtTheNextLogin`: the deploys set for later this put back
    /// whose plist is in LaunchAgents and which launchd would not load now,
    /// by target: each starts the next time the teacher logs in, and will
    /// not run at its moment unless they log out and in before it
    /// (`AssistWording.undoScheduleStartsAtTheNextLogin`; the re-review of U3b's
    /// fixes, LOW 2). Empty for every other step.
    case undone(seq: Int, leftApart: [String] = [], startsAtTheNextLogin: [String] = [])
    case redone(seq: Int, leftApart: [String] = [], startsAtTheNextLogin: [String] = [])
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
    ///
    /// `places` are where an `external` op reads and writes (the app's own
    /// preferences; a test passes its own). Each `recompute` op is run by its
    /// maintainer's registered runner after the swaps (`UndoMaintainers`).
    func undoNewest(
        resolveRoot: (UndoWorkingFolder) -> URL? = UndoReach.root,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) -> UndoOutcome {
        return move(.backward, resolveRoot: resolveRoot, places: places)
    }

    /// Undo, then the re-derivation of every file the undone step keeps true
    /// by a rule, awaited on whatever actor each maintainer's runner needs
    /// (the front page's is the main actor), AFTER the journal's work and
    /// outside its lock. Any step recovery settled first is re-derived too.
    /// This is the entry point the app uses (U7); `undoNewest` alone never
    /// re-derives.
    @concurrent
    func undoNewestAndRederive(
        resolveRoot: @escaping @Sendable (UndoWorkingFolder) -> URL? = UndoReach.root,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) async -> UndoOutcome {
        await UndoRecovery.recoverAndRederive(self, resolveRoot: resolveRoot, places: places)
        let outcome: UndoOutcome = undoNewest(resolveRoot: resolveRoot, places: places)
        if case .undone(let seq, _, _) = outcome {
            await UndoMaintainers.rederive(stepNumbered: seq, in: self, resolveRoot: resolveRoot)
        }
        return outcome
    }

    /// Redo, then the re-derivation, as `undoNewestAndRederive`.
    @concurrent
    func redoNewestAndRederive(
        resolveRoot: @escaping @Sendable (UndoWorkingFolder) -> URL? = UndoReach.root,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) async -> UndoOutcome {
        await UndoRecovery.recoverAndRederive(self, resolveRoot: resolveRoot, places: places)
        let outcome: UndoOutcome = redoNewest(resolveRoot: resolveRoot, places: places)
        if case .redone(let seq, _, _) = outcome {
            await UndoMaintainers.rederive(stepNumbered: seq, in: self, resolveRoot: resolveRoot)
        }
        return outcome
    }

    /// Redoes the most recently undone step.
    func redoNewest(
        resolveRoot: (UndoWorkingFolder) -> URL? = UndoReach.root,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) -> UndoOutcome {
        return move(.forward, resolveRoot: resolveRoot, places: places)
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
        places: UndoExternalPlaces
    ) -> UndoOutcome {
        // 1. Find the step, inside the lock, with recovery run first.
        let found: UndoAvailability
        var leftNewest: UndoRefusal? = nil
        do {
            (found, leftNewest) = try withLock { writer -> (UndoAvailability, UndoRefusal?) in
                UndoRecovery.run(writer, mode: .live, resolveRoot: resolveRoot, places: places)
                let offer: UndoOffer = writer.fold.offer(now: now())
                let answer: UndoAvailability = direction == .backward ? offer.undo : offer.redo
                var left: UndoRefusal? = nil
                if case .anotherChangeIsUnderWay(let busy) = answer {
                    left = writer.leftByRecovery[busy.step.seq]
                }
                return (answer, left)
            }
        } catch {
            return .listUnavailable
        }
        // The newest step is a gone process's, and recovery has just tried
        // it at once and left it (a file in use, a page it cannot read now):
        // nothing is under way, so the answer is that refusal, naming the
        // file, with the list kept and tried again at the next Undo or Redo,
        // and one trail line (the W3 review's LOW 4, matched from Windows).
        if case .anotherChangeIsUnderWay(let busy) = found, let leftNewest {
            UndoTrailHook.leftNewestLine?(busy.step.course ?? "", busy.step.section, direction == .backward, leftNewest)
            return .refused(leftNewest, clearedTheList: false)
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
                // Nothing is under way: a dead step that keeps a file true
                // by a rule waits for a recovery that re-derives it (or for a
                // runner to exist), which this plain path is not. Not
                // available, never "under way" for ever (the third hard
                // review of U2b, LOW 2).
                if UndoRecovery.keepsAFileTrue(busy.step) {
                    return .notAvailable
                }
            }
            return .anotherChangeIsUnderWay
        case .step(let step):
            record = step
        }
        let seq: Int = record.step.seq
        guard let root = UndoCheck.root(of: record.step, resolveRoot: resolveRoot) else {
            return .notAvailable
        }
        // Never undone or redone with its re-derivation skipped: until the
        // app registers a maintainer's runner, its steps are not available.
        if !UndoMaintainers.canRun(record.step.ops) {
            return .notAvailable
        }

        // 2. Check every op, writing nothing. Content the list no longer
        // holds is taken from a kept original of the step's own whose hash
        // matches, as recovery does (`undo.rule.recovery`).
        // A kept original that cannot be read just now may be the one: then
        // the answer is "cannot tell now", the list kept, never content
        // missing, which clears it (the first review of U3c, LOW 5).
        var keptOriginalNotRead: String? = nil
        let keptOriginal: (String, String) -> Data? = UndoRecovery.keptOriginal(
            of: record.step, root: root,
            couldNotRead: { path in
                if keptOriginalNotRead == nil {
                    keptOriginalNotRead = path
                }
            }
        )
        var uses: [UndoKeptOriginalUse] = []
        let plan: UndoPlan = UndoCheck.plan(
            record.step.ops, direction: direction, root: root, journal: self, places: places,
            keptOriginal: keptOriginal,
            keptOriginalUsed: { use in uses.append(use) },
            leavesApart: true
        )
        if UndoKillPoints.stopsHere(.afterTheCheck) {
            return .stoppedByATest
        }
        guard case .ready(let targets, let recomputes, let leftApart) = plan else {
            if case .refused(let refusal) = plan {
                if refusal == .notReadable {
                    return .notAvailable
                }
                if case .contentMissing = refusal, let keptOriginalNotRead {
                    return .refused(.cannotTellNow(path: keptOriginalNotRead), clearedTheList: false)
                }
                return .refused(refusal, clearedTheList: answerARefusal(refusal, of: seq, direction: direction))
            }
            return .listUnavailable
        }

        // 3. Say it is under way, as long as it is still the one to move.
        let starting: UndoEventKind = direction == .backward ? .undoing : .redoing
        let ending: UndoEventKind = direction == .backward ? .undone : .redone
        let phase: UndoPhase = direction == .backward ? .undoing : .redoing
        var notTaken: UndoWhatTheListCouldNotTake = UndoWhatTheListCouldNotTake(outgoingOf: [], keptOriginalsHolding: [])
        do {
            try withLock { writer in
                let offer: UndoOffer = writer.fold.offer(now: now())
                let stillTheOne: UndoAvailability = direction == .backward ? offer.undo : offer.redo
                guard case .step(let current) = stillTheOne, current.step.seq == seq else {
                    throw UndoJournalError.notTheNewestStep(seq)
                }
                // What the kept originals give, and what the swap sets aside
                // for the other direction, into the list first (the first
                // review of U3c, MEDIUM).
                notTaken = UndoRecovery.storeWhatKeptOriginalsGive(uses, writer)
                // And what any other page's swap takes off it, when the
                // other direction needs it and the list lacks it: never an
                // only copy deleted (U3c review 3, LOW 3).
                var outgoingOf: [String] = notTaken.outgoingOf
                for path in UndoRecovery.storeWhatTheOtherDirectionNeeds(targets, of: record.step, direction: direction, root: root, writer) {
                    if !outgoingOf.contains(path) {
                        outgoingOf.append(path)
                    }
                }
                notTaken = UndoWhatTheListCouldNotTake(outgoingOf: outgoingOf, keptOriginalsHolding: notTaken.keptOriginalsHolding)
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
        // What the check left apart, then what the swap could not set and
        // left apart (a deploy set for later launchd refused).
        var everyPlaceLeftApart: [String] = leftApart
        var everyScheduleStartingAtTheNextLogin: [String] = []
        let swapped: UndoSwapResult = UndoSwap.swap(
            targets, label: label, places: places, root: root,
            keepingTheOriginalsOf: Set(notTaken.outgoingOf),
            leaveApart: { place in
                everyPlaceLeftApart.append(place)
            },
            startsAtTheNextLogin: { place in
                everyScheduleStartingAtTheNextLogin.append(place)
            }
        )
        switch swapped {
        case .refused(let refusal):
            JournaledWrite.finish(seq: seq, with: .failed, phase: phase, reason: "refused", in: self, mode: .live)
            // Caught at the swap rather than the check: the same hand edit,
            // so the same answer (rulings 13 and 20; the core review's M2).
            return .refused(refusal, clearedTheList: answerARefusal(refusal, of: seq, direction: direction))
        case .notPutBack(let refusal, _):
            // Left IN FLIGHT (`undoing` or `redoing` with no closing event),
            // never `failed` and never a clearing: recovery settles it from
            // the content once this process is gone (`undo.rule.recovery`).
            return .refused(refusal, clearedTheList: false)
        case .stoppedByATest:
            return .stoppedByATest
        case .swapped:
            break
        }
        if UndoKillPoints.stopsHere(direction == .backward ? .beforeUndone : .beforeRedone) {
            return .stoppedByATest
        }
        // The files kept true by a rule are re-derived by the caller once
        // this answers, outside the lock and off this thread
        // (`undoNewestAndRederive`, `UndoMaintainers`).
        _ = recomputes
        if !uses.isEmpty {
            // The kept original it was put back from is now a copy of its
            // page, and its bytes are in the list: nothing of the step's is
            // left beside it but what the list could not take. A kept
            // original whose bytes the list would not take stays, though its
            // page holds the same: the next move the other way would leave
            // them in no file (the second review of U3c, MEDIUM).
            UndoRecovery.tidyStagedFiles(
                of: record.step, root: root, keepingOnlyCopies: true,
                keepingCopiesHolding: notTaken.keptOriginalsHolding
            )
        }
        JournaledWrite.finish(seq: seq, with: ending, phase: nil, reason: nil, in: self, mode: .live)
        if !notTaken.outgoingOf.isEmpty {
            // One kept copy per content per page, never a pile (U3c review
            // 3, LOW 1).
            UndoRecovery.removeSupersededKeptCopies(of: record.step, root: root, paths: notTaken.outgoingOf, newestLabel: label)
        }
        if !notTaken.isEmpty {
            // The list could not take all the step needs. The step stays on
            // the list with the other direction offered, resting on what is
            // kept beside its pages, as recovery's does (Russell's ruling of
            // 2026-11-20, night): if that file is gone or changed by then,
            // that Undo or Redo is refused then, with its true sentence, and
            // the list answers that refusal as any other. Nothing is dropped
            // or cleared here, so this line is written from one state.
            var keptOfWhatItHeld: [String] = []
            var keptOfWhatItHoldsNow: [String] = []
            var pathsOfTheStep: [String] = []
            for op in record.step.ops {
                if let path = op.path, !pathsOfTheStep.contains(path) {
                    pathsOfTheStep.append(path)
                }
            }
            for path in pathsOfTheStep {
                let place: URL = root.appendingPathComponent(path)
                for keptURL in UndoRecovery.keptOriginalFiles(of: record.step, beside: place) {
                    let name: String = keptURL.lastPathComponent
                    if keptOfWhatItHeld.contains(name) || keptOfWhatItHoldsNow.contains(name) {
                        continue
                    }
                    if notTaken.outgoingOf.contains(path) && UndoSwap.isStaged(name, label: label) {
                        keptOfWhatItHeld.append(name)
                    } else if UndoSwap.holdsAnyOf(notTaken.keptOriginalsHolding, keptURL) {
                        keptOfWhatItHoldsNow.append(name)
                    }
                }
            }
            // Page by page: "from what was kept beside it" only of a page a
            // use names (U4b part one's review, LOW 1).
            var putBackFromAKeptOriginal: [String] = []
            for use in uses {
                let page: String = (use.path as NSString).lastPathComponent
                if !putBackFromAKeptOriginal.contains(page) {
                    putBackFromAKeptOriginal.append(page)
                }
            }
            UndoTrailHook.keptWhatItReplacedLine?(
                record.step.course ?? "", record.step.section, direction == .backward, keptOfWhatItHeld, keptOfWhatItHoldsNow,
                putBackFromAKeptOriginal
            )
        }
        // Only now, the whole swap in and the step closed, the trail says a
        // schedule put back starts at the next login (round four, LOW 4).
        for place in everyScheduleStartingAtTheNextLogin {
            places.noteItStartsAtTheNextLogin(place)
        }
        if direction == .backward {
            return .undone(seq: seq, leftApart: everyPlaceLeftApart, startsAtTheNextLogin: everyScheduleStartingAtTheNextLogin)
        }
        return .redone(seq: seq, leftApart: everyPlaceLeftApart, startsAtTheNextLogin: everyScheduleStartingAtTheNextLogin)
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
        case .fileIsInUse, .couldNotWrite, .notReadable, .cannotTellNow:
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
            UndoRecovery.run(writer, mode: .live, trySwapsNow: false, resolveRoot: UndoReach.root)
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
            UndoRecovery.run(writer, mode: .live, trySwapsNow: false, resolveRoot: UndoReach.root)
            UndoPruning.prune(writer)
            return true
        }
    }
}
