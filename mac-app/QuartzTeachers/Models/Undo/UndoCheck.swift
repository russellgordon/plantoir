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

    /// Where an op stands in a file's current content. A move, a tree or an
    /// external op is judged on the disk as a whole (`wholeState`), never
    /// here.
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
        case .replaceText:
            return UndoHunk.state(of: op, in: item)
        case .editJSON:
            return UndoJSONMember.state(of: op, in: item)
        case .recompute:
            return .after
        case .move, .createTree, .removeTree, .external, .none:
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
    /// Ops on one file are applied to that file's text in turn (in reverse
    /// for an undo), so several lines on one page make one staged file. A
    /// move, a tree or an external op is judged on its own against what is
    /// there now (`wholeState`), and becomes one change of its own.
    static func plan(
        _ ops: [UndoOp],
        direction: UndoDirection,
        root: URL,
        journal: UndoJournal,
        places: UndoExternalPlaces = UndoAppPreferences()
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
        var recomputes: [UndoOp] = []
        var wholeTargets: [UndoSwapTarget] = []

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
            if op.isWhole {
                let state: UndoOpState = UndoCheck.wholeState(of: op, root: root, places: places)
                let verdict: UndoCheckVerdict = UndoCheck.verdict(for: state, direction: direction)
                if verdict == .alreadyBack || verdict == .alreadyRedone {
                    continue
                }
                if verdict == .changedSince {
                    if !inTheWay.contains(op.placeName) {
                        inTheWay.append(op.placeName)
                    }
                    continue
                }
                guard let target = UndoCheck.wholeTarget(op, direction: direction, root: root, journal: journal) else {
                    if missingContentPath == nil {
                        missingContentPath = op.placeName
                    }
                    continue
                }
                wholeTargets.append(target)
                continue
            }
            guard let path = op.path else {
                return .refused(.notReadable)
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
                // A blob the list no longer holds. The check goes on, so
                // every page in the way is reported first.
                if missingContentPath == nil {
                    missingContentPath = path
                }
                continue
            }
            working[path] = moved
        }

        if let first = inTheWay.first {
            return .refused(.changedSince(firstPath: first, others: inTheWay.count - 1))
        }
        if let missingContentPath {
            return .refused(.contentMissing(path: missingContentPath))
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
        for target in wholeTargets {
            targets.append(target)
        }
        return .ready(targets: targets, recomputes: recomputes)
    }

    /// The content after moving one op one way, or nil when a blob it needs
    /// is missing or the text cannot be read or placed.
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
        case .replaceText:
            return UndoHunk.moved(op, from: item, direction: direction)
        case .editJSON:
            return UndoJSONMember.moved(op, from: item, direction: direction)
        case .recompute, .move, .createTree, .removeTree, .external, .none:
            return item
        }
    }

    /// The one change a move, a tree or an external op makes going this
    /// way, or nil when content it needs is missing from the list.
    static func wholeTarget(_ op: UndoOp, direction: UndoDirection, root: URL, journal: UndoJournal) -> UndoSwapTarget? {
        switch op.knownKind {
        case .move:
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
            if !makes {
                return UndoSwapTarget(url: url, relativePath: path, change: .takeTree(listingSha: listingSha))
            }
            guard let listingData = journal.readBlob(sha: listingSha),
                  let listing = UndoTreeListing.parse(listingData), listing.sha == listingSha else {
                return nil
            }
            var contents: [String: Data] = [:]
            for file in listing.files {
                guard let data = journal.readBlob(sha: file.sha) else {
                    return nil
                }
                contents[file.path] = data
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

/// What a check found.
nonisolated enum UndoPlan: Equatable, Sendable {
    case ready(targets: [UndoSwapTarget], recomputes: [UndoOp])
    case refused(UndoRefusal)
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

    // MARK: - Initializer

    init(url: URL, relativePath: String, expected: Data?, replacement: Data?) {
        self.url = url
        self.relativePath = relativePath
        self.expected = expected
        self.replacement = replacement
        self.change = .file
    }

    init(url: URL, relativePath: String, change: UndoSwapChange) {
        self.url = url
        self.relativePath = relativePath
        self.expected = nil
        self.replacement = nil
        self.change = change
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
/// is set last of all, after every file has gone in, and re-read first.
nonisolated enum UndoSwap {

    // MARK: - Stored properties

    /// The part of a staged file's name that says it is Plantoir's.
    static let stagedMarker: String = ".plantoir-undo-"

    // MARK: - Functions

    static func swap(
        _ targets: [UndoSwapTarget],
        label: String,
        places: UndoExternalPlaces = UndoAppPreferences()
    ) -> UndoSwapResult {
        var staged: [URL?] = []
        var originals: [URL?] = []
        var swapsMade: Int = 0

        func tidy() {
            for url in staged {
                if let url {
                    _ = UndoSwap.removeStaged(url)
                }
            }
            for url in originals {
                if let url {
                    _ = UndoSwap.removeStaged(url)
                }
            }
        }

        func reverse() {
            var index: Int = swapsMade - 1
            while index >= 0 {
                let target: UndoSwapTarget = targets[index]
                switch target.change {
                case .file:
                    if let original = originals[index] {
                        _ = UndoSwap.rename(original, onto: target.url)
                        originals[index] = nil
                    } else {
                        try? FileManager.default.removeItem(at: target.url)
                    }
                case .moveHere(let from, _, _):
                    _ = UndoSwap.renameExclusively(target.url, onto: from)
                case .makeTree:
                    // Back under its staged name, removed with the rest.
                    let stagedURL: URL = UndoSwap.besideURL(for: target.url, label: label, role: "new")
                    if UndoSwap.renameExclusively(target.url, onto: stagedURL) {
                        staged[index] = stagedURL
                    }
                case .takeTree:
                    // Never removed by the tidy that follows: put back, or,
                    // if even that fails, left aside under its staged name.
                    if let original = originals[index] {
                        _ = UndoSwap.renameExclusively(original, onto: target.url)
                        originals[index] = nil
                    }
                case .setExternal(let externalTarget, let expected, _):
                    _ = places.write(externalTarget, expected)
                }
                index -= 1
            }
        }

        // 1. Stage every new content beside its target.
        var stagingIndex: Int = 0
        for target in targets {
            let targetIndex: Int = stagingIndex
            stagingIndex += 1
            originals.append(nil)
            if case .makeTree(let listing, let contents) = target.change {
                let stagedURL: URL = UndoSwap.besideURL(for: target.url, label: label, role: "new")
                try? FileManager.default.createDirectory(
                    at: target.url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                _ = UndoSwap.removeStaged(stagedURL)
                let failsHere: Bool = UndoKillPoints.stagingWriteFailsAt?(targetIndex) == true
                if failsHere || !UndoTreeReading.make(listing, contents: contents, at: stagedURL) {
                    _ = UndoSwap.removeStaged(stagedURL)
                    staged.append(nil)
                    tidy()
                    return .refused(.couldNotWrite(path: target.relativePath))
                }
                staged.append(stagedURL)
                continue
            }
            guard case .file = target.change, let replacement = target.replacement else {
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
                if UndoKillPoints.stagingWriteFailsAt?(targetIndex) == true {
                    // As a full disk does: the exclusive create makes the
                    // file, then writing into it fails.
                    try UndoFiles.writeDurably(Data(), to: stagedURL, mode: mode)
                    throw UndoJournalError.couldNotStoreContent(ENOSPC)
                }
                try UndoFiles.writeDurably(replacement, to: stagedURL, mode: mode)
                staged.append(stagedURL)
            } catch {
                // The exclusive create may have made the file before the
                // write failed (the Fable sweep of U1, F1): it is this
                // swap's own, so it goes with every other staged file.
                // Staging writes a NEW file, which no other program can be
                // holding, so this is never `fileIsInUse`: the disk is full
                // or the folder will not take a new file.
                _ = UndoSwap.removeStaged(stagedURL)
                staged.append(nil)
                tidy()
                return .refused(.couldNotWrite(path: target.relativePath))
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
            var refusal: UndoRefusal? = nil
            switch target.change {
            case .file:
                refusal = UndoSwap.swapAFile(target, index: index, label: label, staged: &staged, originals: &originals)
            case .moveHere(let from, _, let op):
                // The pair once more, just before the rename: the content at
                // the place it leaves, nothing where it goes.
                if UndoMoveSide.read(op, at: from) != .holdsTheContent || UndoMoveSide.read(op, at: target.url) != .free {
                    refusal = .changedSince(firstPath: target.relativePath, others: 0)
                } else {
                    try? FileManager.default.createDirectory(
                        at: target.url.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    if !UndoSwap.renameExclusively(from, onto: target.url) {
                        refusal = .fileIsInUse(path: target.relativePath)
                    }
                }
            case .makeTree:
                if UndoTreeReading.read(at: target.url) != .absent {
                    refusal = .changedSince(firstPath: target.relativePath, others: 0)
                } else if let stagedURL = staged[index], UndoSwap.renameExclusively(stagedURL, onto: target.url) {
                    staged[index] = nil
                } else {
                    refusal = .fileIsInUse(path: target.relativePath)
                }
            case .takeTree(let listingSha):
                if UndoTreeReading.read(at: target.url).listingSha != listingSha {
                    refusal = .changedSince(firstPath: target.relativePath, others: 0)
                } else {
                    let asideURL: URL = UndoSwap.besideURL(for: target.url, label: label, role: "orig")
                    _ = UndoSwap.removeStaged(asideURL)
                    if UndoSwap.renameExclusively(target.url, onto: asideURL) {
                        originals[index] = asideURL
                    } else {
                        refusal = .fileIsInUse(path: target.relativePath)
                    }
                }
            case .setExternal(let externalTarget, let expected, let value):
                if !UndoCheck.externalMatches(places.read(externalTarget), expected) {
                    refusal = .changedSince(firstPath: target.relativePath, others: 0)
                } else if !places.write(externalTarget, value) {
                    refusal = .couldNotWrite(path: target.relativePath)
                }
            }
            if let refusal {
                reverse()
                tidy()
                return .refused(refusal)
            }
            swapsMade += 1
            index += 1
        }

        // 3. Every swap went in: the kept originals are no longer needed.
        tidy()
        for target in targets {
            if case .setExternal = target.change {
                continue
            }
            UndoFiles.syncFolder(target.url.deletingLastPathComponent())
        }
        return .swapped
    }

    /// One file's swap: re-read, keep the original, rename the new content
    /// in (or remove the file). The refusal, or nil when it went in.
    private static func swapAFile(
        _ target: UndoSwapTarget,
        index: Int,
        label: String,
        staged: inout [URL?],
        originals: inout [URL?]
    ) -> UndoRefusal? {
        let now: UndoItem = UndoItem.read(at: target.url)
        if now.data != target.expected || (target.expected == nil && now != .absent) {
            return .changedSince(firstPath: target.relativePath, others: 0)
        }
        if now != .absent {
            let originalURL: URL = UndoSwap.besideURL(for: target.url, label: label, role: "orig")
            try? FileManager.default.removeItem(at: originalURL)
            if !UndoSwap.keep(target.url, as: originalURL) {
                return .fileIsInUse(path: target.relativePath)
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
            return .fileIsInUse(path: target.relativePath)
        }
        return nil
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

    /// Removes what a swap for this label left beside these files. True
    /// when nothing of it is left (a file another program holds, or one
    /// made immutable, stays until a later try).
    @discardableResult
    static func tidyLeftovers(label: String, beside urls: [URL]) -> Bool {
        var allGone: Bool = true
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
                let stagedURL: URL = folder.appendingPathComponent(name)
                if UndoSwap.isAFolderSetAside(stagedURL) {
                    // A teacher's folder a dead process renamed aside (a
                    // tree taken out, U2): never deleted here. Put back
                    // where it was when that place is free, so recovery
                    // judges it as the work found it; otherwise left aside.
                    let suffix: String = stagedMarker + label + "-orig"
                    var original: String = name
                    if original.hasSuffix(suffix) {
                        original = String(original.dropLast(suffix.count))
                    }
                    if original.hasPrefix(".") {
                        original = String(original.dropFirst())
                    }
                    let originalURL: URL = folder.appendingPathComponent(original)
                    if original.isEmpty || !UndoSwap.renameExclusively(stagedURL, onto: originalURL) {
                        allGone = false
                    }
                    continue
                }
                if !UndoSwap.removeStaged(stagedURL) {
                    allGone = false
                }
            }
        }
        return allGone
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
        do {
            found = try withLock { writer -> UndoAvailability in
                UndoRecovery.run(writer, mode: .live, resolveRoot: resolveRoot, places: places)
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
        guard let root = UndoCheck.root(of: record.step, resolveRoot: resolveRoot) else {
            return .notAvailable
        }
        // Never undone or redone with its re-derivation skipped: until the
        // app registers a maintainer's runner, its steps are not available.
        if !UndoMaintainers.canRun(record.step.ops) {
            return .notAvailable
        }

        // 2. Check every op, writing nothing.
        let plan: UndoPlan = UndoCheck.plan(record.step.ops, direction: direction, root: root, journal: self, places: places)
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
        switch UndoSwap.swap(targets, label: label, places: places) {
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
        if UndoKillPoints.stopsHere(direction == .backward ? .beforeUndone : .beforeRedone) {
            return .stoppedByATest
        }
        // After the swaps: a process that dies between them and this leaves
        // the front page stale, and recovery re-derives it when it settles
        // the step (`undo.laterPieces.U2`, recoveryCases).
        UndoMaintainers.rederive(recomputes, root: root)
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
        case .fileIsInUse, .couldNotWrite, .notReadable:
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
