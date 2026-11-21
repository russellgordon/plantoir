import Foundation

/// Who makes a step and what it is called: the step's `madeBy` and its
/// action key (`undoJournal.stepKeys`). The menu, a sheet, the built-in
/// window and an outside assistant each pass their own; a planner called
/// with none is a sheet's.
nonisolated struct UndoStepMaker: Equatable, Sendable {

    // MARK: - Stored properties

    /// `menu`, `sheet`, `builtInAssistant:<id>` or `outsideAssistant:<client>:<id>`.
    let madeBy: String

    /// The action's wording key (U7 names the words): `publishPages`,
    /// `makeRoomForClasses` and the rest (documentation 09, "U3").
    let actionKey: String

    // MARK: - Initializer

    init(madeBy: String, action actionKey: String) {
        self.madeBy = madeBy
        self.actionKey = actionKey
    }

    // MARK: - Functions

    /// A sheet's step: what a planner records when its caller names nobody.
    static func sheet(_ actionKey: String) -> UndoStepMaker {
        return UndoStepMaker(madeBy: "sheet", action: actionKey)
    }

    /// The same maker, for another action.
    func making(_ actionKey: String) -> UndoStepMaker {
        return UndoStepMaker(madeBy: madeBy, action: actionKey)
    }
}

/// Why an action's step did not go in. Each says what a failed write of
/// the action said before U3 (Foundation's "could not be saved"), so a
/// teacher reads the same sentence on the same failure: the difference is
/// that nothing of the step was written (`undo.rule.stagedThenSwapped`).
nonisolated enum JournaledStepError: Error, LocalizedError, Equatable {

    /// The door refused: a page in the way, a file in use, no room.
    case refused(UndoRefusal, fileName: String)

    /// Live only: the list could not be written, so nothing changed.
    case couldNotRecordTheStep

    /// Live only: a step left part way must be settled first.
    case anotherChangeIsUnderWay

    /// A test stopped the step at a kill point, as a process that died.
    case stoppedByATest

    /// Refused PART WAY: a file could not be put back after the step was
    /// refused, so it holds the new content while what it held before is
    /// kept beside it under each name in `keptOriginals` (hidden, in the
    /// page's own folder, never tidied away while it differs from the page).
    /// Never said as "Nothing was changed": a caller says only part was
    /// (`AssistWording.publishStoppedPartWay`).
    case leftPartWay(UndoRefusal, fileName: String, keptOriginals: [String])

    // MARK: - Computed properties

    var errorDescription: String? {
        switch self {
        case .refused(_, let fileName):
            return CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileName]).localizedDescription
        case .leftPartWay(_, let fileName, let keptOriginals):
            var said: String = CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileName]).localizedDescription
            for kept in keptOriginals {
                said += " " + JournaledStepError.keptSentence(place: JournaledStepError.placeName(ofKept: kept), kept: kept)
            }
            return said
        case .couldNotRecordTheStep, .anotherChangeIsUnderWay:
            return CocoaError(.fileWriteUnknown).localizedDescription
        case .stoppedByATest:
            return "stopped by a test"
        }
    }

    // MARK: - Functions

    /// One kept original, said after a step refused part way:
    /// `shared-rules.json` → `undo.wording.keptBesideIt` (the U3 sweep,
    /// finding 5). `place` is already quoted.
    static func keptSentence(place: String, kept: String) -> String {
        return "What \(place) held before is kept beside it as the hidden file “\(kept)”."
    }

    /// The page a kept original stands beside, quoted: “Unit 1, Day 2.md”.
    static func placeName(ofKept name: String) -> String {
        return "“" + (UndoSwap.placeOfStagedName(name) ?? name) + "”"
    }
}

/// ONE action's writes, gathered and then made through the door as ONE step
/// (#899, U3). The action plans every file it will write here instead of
/// writing it; it reads through this too, so a page it renamed or rewrote a
/// moment ago reads as it will be (`readText`, `fileExists`). `make()` then
/// hands the whole step to `JournaledWrite.perform`, which writes it down
/// first and then stages every file beside its target and swaps them in
/// together: all of them or none (`undo.rule.stagedThenSwapped`).
///
/// While the switch is off the step is recorded in SHADOW: the files are
/// written exactly as the action planned them whether or not the list could
/// take the step (a busy list leaves one trail line), and nothing is ever
/// offered back. A course that is not inside a working folder (no `courses`
/// folder above it), a file outside its working folder through a link, or a
/// target that is not a plain file (a link, a folder, a file that cannot be
/// read) cannot be named in a step: in shadow those files are staged and
/// swapped in together without the list (`writePlainly`), with one trail
/// line; live, the step is refused before anything changes, because an
/// unrecorded change above the head would be passed over by the next Undo.
///
/// Each file's `before` is what it held when it was FIRST planned, never a
/// second read at `make()`: a file another program changed in between
/// refuses the step instead of being written over.
nonisolated final class JournaledStep {

    // MARK: - Stored properties

    /// A test runs the door live while the app's switch is off, to prove
    /// what a live step leaves when it is killed part way. Nil in the app.
    nonisolated(unsafe) static var modeOverride: UndoMode?

    let courseCode: String

    let courseDirectory: URL

    let section: Int?

    let maker: UndoStepMaker

    /// `section` or `course`: which lease an undo of it takes.
    let holds: String

    /// Each planned file's place, in the order first planned.
    private(set) var plannedOrder: [String] = []

    private var plannedURL: [String: URL] = [:]

    /// The bytes each planned file is left holding (nil: removed).
    private var plannedAfter: [String: Data?] = [:]

    /// What each planned file held when it was FIRST planned: the bytes the
    /// action's plan was built from. They are the step's `before`, so a file
    /// another program changed between planning and `make()` (an Obsidian
    /// edit, a page that appeared at a new page's place) refuses the step
    /// (`changedSince`) instead of being written over; a file that was not
    /// there is never written over either, even by `writePlainly`.
    private var plannedBefore: [String: UndoItem] = [:]

    /// Each file planned with `writeNew`: recorded as absent before, so the
    /// door refuses rather than replaces one that is there.
    private var mustBeNew: Set<String> = []

    /// Files kept true by a rule, re-derived after the step
    /// (`undoJournal.opKinds.recompute`).
    private(set) var recomputeURLs: [(url: URL, maintainer: String, section: Int?)] = []

    /// Each file planned to be MOVED (U3b: the rollover's record fragments
    /// and markers), in the order planned: where it is, where it goes, the
    /// SHA-256 of its bytes when planned, and the kind of op it is: `move`,
    /// `moveApart` (a website record a deploy reads, which stands apart from
    /// the rest of the step with the other records, as a group: Russell's
    /// ruling of 2026-11-19 on Q3, the director's decision of 2026-11-20),
    /// or `setAside` (a leftover no deploy reads, which stands apart ALONE).
    private(set) var plannedMoves: [(from: URL, to: URL, sha: String, kind: UndoOpKind)] = []

    /// Each `external` op planned (U3b: the deploy set for later a rollover
    /// removes), in order.
    private(set) var plannedExternals: [UndoOp] = []

    /// Where the step's `external` ops read and write: the app's
    /// preferences and, given the action's launchd runner, its deploys set
    /// for later (`UndoAppPlaces`).
    var places: UndoExternalPlaces = UndoAppPreferences()

    /// Each JSON file planned MEMBER BY MEMBER (U4a: `course_config.json`),
    /// by its key: the `editJSON` ops' key paths and values, in order. The
    /// file is still in `plannedOrder` with the bytes the members leave it
    /// holding (`plannedAfter`), so a step that cannot be recorded writes
    /// those bytes whole, all or none, exactly as the ops would have.
    private var plannedMembers: [String: [(keyPath: [String], before: UndoJSON?, after: UndoJSON?)]] = [:]

    /// Each folder planned to be MADE with what is in it (U4a: Add folder's
    /// folder and its two pages), as one `createTree`, in the order planned.
    private(set) var plannedTrees: [(url: URL, listing: UndoTreeListing, contents: [String: Data])] = []


    // MARK: - Computed properties

    /// The mode the step is made in.
    var mode: UndoMode {
        if let override = JournaledStep.modeOverride {
            return override
        }
        return UndoSwitch.currentMode
    }

    /// Whether nothing has been planned.
    var isEmpty: Bool {
        return plannedOrder.isEmpty && plannedMoves.isEmpty && plannedExternals.isEmpty && plannedTrees.isEmpty
    }

    /// Whether the step holds a move, an external op, a JSON file planned
    /// member by member or a folder to make, and so is made as ops
    /// (`JournaledWrite.perform(ops:)`) rather than as files.
    var isMixed: Bool {
        return !plannedMoves.isEmpty || !plannedExternals.isEmpty || !plannedMembers.isEmpty || !plannedTrees.isEmpty
    }

    /// The working folder: the folder holding the course's `courses` folder,
    /// or nil when the course is not inside one.
    var workingFolderURL: URL? {
        let coursesFolder: URL = courseDirectory.standardizedFileURL.deletingLastPathComponent()
        if coursesFolder.lastPathComponent != "courses" {
            return nil
        }
        return coursesFolder.deletingLastPathComponent()
    }

    // MARK: - Initializer

    init(courseCode: String, courseDirectory: URL, section: Int?, maker: UndoStepMaker, holds: String = "section") {
        self.courseCode = courseCode
        self.courseDirectory = courseDirectory
        self.section = section
        self.maker = maker
        self.holds = holds
    }

    @MainActor
    convenience init(course: Course, section: Int?, maker: UndoStepMaker, holds: String = "section") {
        self.init(
            courseCode: course.code, courseDirectory: course.directoryURL,
            section: section, maker: maker, holds: holds
        )
    }

    /// A step for a course known only by a file inside it: the course's
    /// folder is the one named `courseCode` under a `courses` folder above
    /// the file, or the file's own folder when there is none (and the step
    /// then cannot be named: `workingFolderURL` is nil).
    convenience init(courseCode: String, fileInside url: URL, section: Int?, maker: UndoStepMaker, holds: String = "section") {
        var courseDirectory: URL = url.deletingLastPathComponent()
        var folder: URL = url.standardizedFileURL.deletingLastPathComponent()
        while folder.path != "/" {
            if folder.lastPathComponent == courseCode && folder.deletingLastPathComponent().lastPathComponent == "courses" {
                courseDirectory = folder
                break
            }
            folder = folder.deletingLastPathComponent()
        }
        self.init(courseCode: courseCode, courseDirectory: courseDirectory, section: section, maker: maker, holds: holds)
    }

    // MARK: - Functions: planning

    /// Called as each read ahead starts, so a test can see that a sheet
    /// reads ahead (the second review of U3a, LOW 4). Nil in the app.
    nonisolated(unsafe) static var readAheadHook: (@Sendable () -> Void)?

    /// The step being planned right now, while `whilePlanning` runs: the
    /// readers a plan is built from (`AssistSectionGraph.read`,
    /// `ClassPages.list`) read a page through it, so an action that plans
    /// several times in one step (a whole unit published class by class)
    /// sees what it planned a moment ago, as it saw what it had written
    /// before U3. Nil otherwise; on the main actor, where the actions run.
    nonisolated(unsafe) static var planning: JournaledStep?

    /// Runs `body` with this step as the one being planned.
    func whilePlanning<Result>(_ body: () throws -> Result) rethrows -> Result {
        let previous: JournaledStep? = JournaledStep.planning
        JournaledStep.planning = self
        defer {
            JournaledStep.planning = previous
        }
        return try body()
    }

    /// A page's text as the step being planned will leave it, or the disk's
    /// when no step is being planned (`String(contentsOf:encoding:)`).
    static func textAsPlanned(at url: URL) -> String? {
        if let planning {
            return planning.readText(url)
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Plans the file at `url` to hold `text`, as `String.write` encodes it.
    func write(_ text: String, to url: URL) {
        write(Data(text.utf8), to: url)
    }

    /// Plans the file at `url` to hold these bytes.
    func write(_ data: Data, to url: URL) {
        plan(data, at: url)
    }

    /// Plans a NEW file at `url`: one that must not be there when the step
    /// is made (`.withoutOverwriting`). A file that is there by then, even
    /// one that appeared after this was planned, refuses the step
    /// (`changedSince`), so it is never written over.
    func writeNew(_ data: Data, to url: URL) {
        plan(data, at: url)
        mustBeNew.insert(JournaledStep.key(of: url))
    }

    /// Plans the file at `url` to be removed.
    func remove(_ url: URL) {
        plan(nil, at: url)
    }

    /// Plans the file at `from` to be MOVED to `to` (one rename that never
    /// replaces, made with the rest of the step), judged as a pair by its
    /// bytes now. False, planning nothing, when it cannot be read now. A
    /// move that `standsApart` is left as it is by an Undo or a Redo that
    /// finds the pair changed since, and the rest of the step goes ahead.
    @discardableResult
    func move(_ from: URL, to: URL, standsApart: Bool = false) -> Bool {
        return planAMove(from, to: to, kind: standsApart ? .moveApart : .move)
    }

    /// Plans a LEFTOVER no deploy reads to be set aside (`setAside`, #899
    /// U3b): moved as `move` is, standing apart on its own, never one of the
    /// group of website records (`moveApart`), so a leftover that is changed
    /// or missing since is left as it is and named by an Undo or a Redo,
    /// and never decides where the section's records go (the review of U3b's
    /// fixes, LOW 3). False, planning nothing, when it cannot be read now.
    @discardableResult
    func setAside(_ from: URL, to: URL) -> Bool {
        return planAMove(from, to: to, kind: .setAside)
    }

    /// Plans one move of the given kind, judged by its bytes now.
    private func planAMove(_ from: URL, to: URL, kind: UndoOpKind) -> Bool {
        guard case .file(let data) = UndoItem.read(at: from) else {
            return false
        }
        plannedMoves.append((from: from, to: to, sha: UndoHash.sha256(of: data), kind: kind))
        return true
    }

    /// Plans one `external` op: the target set from `before` to `after`
    /// (nil: not set), made after the step's files and moves.
    func setExternal(_ target: String, from before: UndoJSON?, to after: UndoJSON?) {
        plannedExternals.append(UndoOp.external(target: target, before: before, after: after))
    }

    /// Takes an external op back out of the plan (a rollover whose schedule
    /// could not be removed makes the rest of its step without it).
    func forgetExternal(_ target: String) {
        var kept: [UndoOp] = []
        for op in plannedExternals where op.target != target {
            kept.append(op)
        }
        plannedExternals = kept
    }

    /// Plans a JSON file's change as one `editJSON` per member it changes
    /// (#899 U4a), from the bytes the caller's plan was built from (`read`,
    /// the step's `before` for the file: read when planned, never at
    /// `make()`, the U3a trap) to the bytes those members leave it holding
    /// (`after`, which the caller worked out with `UndoJSONMember.moved`).
    /// Made, each member is moved in the file as it is THEN, so a member
    /// another window or a build changed meanwhile is kept, and one of this
    /// step's members changed meanwhile refuses the step (`changedSince`).
    /// A file already planned in this step is planned whole instead.
    func editJSON(
        at url: URL, read: Data, members: [(keyPath: [String], before: UndoJSON?, after: UndoJSON?)], leaving after: Data
    ) {
        let key: String = JournaledStep.key(of: url)
        if plannedURL[key] != nil {
            plan(after, at: url)
            return
        }
        plannedOrder.append(key)
        plannedURL[key] = url
        plannedBefore[key] = .file(read)
        plannedAfter[key] = after
        if !members.isEmpty {
            plannedMembers[key] = members
        }
    }

    /// Plans a NEW folder at `url` holding exactly these folders and files
    /// (paths inside it, forward slashes), made whole as one `createTree`
    /// (#899 U4a): built beside its place and renamed in, never over
    /// anything, so a place taken by the time the step is made refuses it.
    func makeTree(at url: URL, folders: [String], files: [String: Data]) {
        var listed: [UndoTreeListing.File] = []
        var paths: [String] = []
        for (path, _) in files {
            paths.append(path)
        }
        paths.sort { first, second in
            return first.utf8.lexicographicallyPrecedes(second.utf8)
        }
        for path in paths {
            if let data = files[path] {
                listed.append(UndoTreeListing.File(path: path, sha: UndoHash.sha256(of: data)))
            }
        }
        plannedTrees.append((url: url, listing: UndoTreeListing(folders: folders, files: listed), contents: files))
    }

    /// Records that a file kept true by a rule (`sectionFrontPage`) follows
    /// this step: written by its maintainer after the step, never as content.
    func keepsTheFrontPageTrue(of sectionNumber: Int, at url: URL) {
        for kept in recomputeURLs where kept.url.standardizedFileURL == url.standardizedFileURL {
            return
        }
        recomputeURLs.append((url: url, maintainer: "sectionFrontPage", section: sectionNumber))
    }

    // MARK: - Functions: reading through the plan

    /// The file's bytes as the step will leave them: planned, or on the disk.
    func readData(_ url: URL) -> Data? {
        let key: String = JournaledStep.key(of: url)
        if let planned = plannedAfter[key] {
            return planned
        }
        return try? Data(contentsOf: url)
    }

    /// The file's text as the step will leave it, read the way the actions
    /// read a page (`String(contentsOf:encoding:)`, which drops a leading
    /// byte-order mark) when it is still the disk's.
    func readText(_ url: URL) -> String? {
        let key: String = JournaledStep.key(of: url)
        if let planned = plannedAfter[key] {
            guard let data = planned else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// `readText`, throwing as `String(contentsOf:)` does when the disk's
    /// file cannot be read.
    func readTextOrThrow(_ url: URL) throws -> String {
        let key: String = JournaledStep.key(of: url)
        if let planned = plannedAfter[key] {
            guard let data = planned, let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
            }
            return text
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Whether a file will be there once the step is made.
    func fileExists(_ url: URL) -> Bool {
        let key: String = JournaledStep.key(of: url)
        if let planned = plannedAfter[key] {
            return planned != nil
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// The `.md` files under a folder, at any depth, once the step is made:
    /// the disk's (`onDisk`, as a lister found them), without those the step
    /// removes, with those it makes, sorted by path as the listers sort.
    func markdownFiles(under folderURL: URL, onDisk: [URL]) -> [URL] {
        var result: [URL] = []
        var seen: Set<String> = []
        for url in onDisk {
            let key: String = JournaledStep.key(of: url)
            if let planned = plannedAfter[key], planned == nil {
                continue
            }
            seen.insert(key)
            result.append(url)
        }
        let folderPrefix: String = JournaledStep.key(of: folderURL) + "/"
        for key in plannedOrder where !seen.contains(key) && key.hasPrefix(folderPrefix) {
            guard let url = plannedURL[key], let planned = plannedAfter[key], planned != nil else {
                continue
            }
            if url.pathExtension.lowercased() != "md" {
                continue
            }
            result.append(url)
        }
        result.sort { first, second in
            return first.path.lowercased() < second.path.lowercased()
        }
        return result
    }

    // MARK: - Functions: making it

    /// Reads the app's list OFF the main actor, so the step an action makes
    /// next, on the main actor, reads on from there instead of reading the
    /// whole list (100 to 380 ms at a year's 2 to 6 MB, the core review of
    /// U1's second round; `UndoFoldCache`). The director's ruling 8 on U1's
    /// third round: the window is never held for that read. Called by the
    /// runner before every tool, by Get Ready before its write, and by every
    /// sheet that makes a step while the teacher reads it (the links
    /// checklist, today's class and Not Today, the classes dated later, the
    /// class dates, Course Settings for How I Teach), unawaited, so the
    /// order of effects is unchanged. What is left on the main actor is the
    /// lock (at most 50 ms to begin and 50 ms to finish in shadow; live up to
    /// 2 s and 10 s, for U7 to settle) and one flush (4 ms on the M4 Pro),
    /// measured in documentation 09. Also tidies what a shadow swap without
    /// the list left when its process died (`UndoShadowStaging`).
    @concurrent
    static func readTheListAhead() async {
        JournaledStep.readAheadHook?()
        let journal: UndoJournal = UndoJournalLocation.standardJournal()
        _ = try? journal.read()
        UndoShadowStaging.tidyLeftovers(of: journal)
    }

    /// Makes the step through the door: written down first (in shadow, when
    /// the list can take it), then every planned file staged and swapped in
    /// together. Throws, having written nothing, when the door refuses.
    func make() throws {
        if isMixed {
            try makeAsOps()
            return
        }
        if plannedOrder.isEmpty {
            return
        }
        let currentMode: UndoMode = mode
        guard let root = workingFolderURL, let changes = recordableChanges(under: root) else {
            if currentMode == .live {
                throw JournaledStepError.couldNotRecordTheStep
            }
            // The trail says what became of it once that is known (the U3
            // sweep, finding 2).
            try UndoTrailHook.couldNotRecord(
                action: maker.actionKey, course: courseCode, section: section,
                why: "a file it writes cannot be named in a step", after: { try writePlainly() }
            )
            return
        }
        var recomputes: [UndoOp] = []
        for kept in recomputeURLs {
            if let path = UndoFolderPlaces.relativePath(of: kept.url, under: root) {
                recomputes.append(UndoOp.recompute(path: path, maintainer: kept.maintainer, section: kept.section))
            }
        }
        var changedFiles: Int = 0
        for change in changes where change.before != change.after {
            changedFiles += 1
        }
        let draft: UndoStepDraft = UndoStepDraft(
            action: UndoAction(key: maker.actionKey, arguments: ["pageCount": String(changedFiles)]),
            madeBy: maker.madeBy,
            workingFolderURL: root,
            workingFolderPath: FolderIdentity.canonicalPath(root.path),
            course: courseCode,
            section: section,
            actionClass: "A",
            holds: holds,
            changes: changes,
            recomputes: recomputes
        )
        let journal: UndoJournal = UndoJournalLocation.standardJournal()
        let outcome: JournaledWriteOutcome = JournaledWrite.perform(draft, in: journal, mode: currentMode)
        switch outcome {
        case .applied, .appliedWithoutARecord, .changedNothing:
            return
        case .refused(let refusal):
            throw JournaledStepError.refused(refusal, fileName: JournaledStep.fileName(in: refusal))
        case .leftPartWay(let refusal, let keptOriginals):
            throw JournaledStepError.leftPartWay(
                refusal, fileName: JournaledStep.fileName(in: refusal), keptOriginals: keptOriginals
            )
        case .couldNotRecordTheStep:
            throw JournaledStepError.couldNotRecordTheStep
        case .anotherChangeIsUnderWay:
            throw JournaledStepError.anotherChangeIsUnderWay
        case .stoppedByATest:
            throw JournaledStepError.stoppedByATest
        }
    }

    /// The action, its `pageCount` counting every file the step changes
    /// or moves. (A rollover's legacy marker is brought into the working
    /// folder before its step, `DeployCommand.moveTheLegacyMarkerIn`, so no
    /// argument says a marker was moved outside the step.)
    private func action(changedFiles: Int) -> UndoAction {
        return UndoAction(key: maker.actionKey, arguments: ["pageCount": String(changedFiles)])
    }

    /// A step holding moves or external ops (U3b), made through the door
    /// that takes every kind (`JournaledWrite.perform(ops:)`): its files as
    /// `editLine` or `writeFile` ops by the door's own rule, then its moves,
    /// then its external ops, then its `recompute` ops, under ONE begin, and
    /// all of it or none (the door plans the ops forward and swaps them in
    /// together, setting back what went in when a later change cannot).
    ///
    /// In shadow, a list that cannot take the step leaves one trail line and
    /// the change is still made all or none, unrecorded
    /// (`makeWithoutARecord`); a step that cannot be named (no working
    /// folder, a place through a link out of it) is the same. Live, either
    /// refuses before anything changes.
    private func makeAsOps() throws {
        let currentMode: UndoMode = mode
        guard let root = workingFolderURL,
              let changes = recordableChanges(under: root),
              let moveOps = recordableMoves(under: root),
              let treeOps = recordableTrees(under: root) else {
            if currentMode == .live {
                throw JournaledStepError.couldNotRecordTheStep
            }
            try UndoTrailHook.couldNotRecord(
                action: maker.actionKey, course: courseCode, section: section,
                why: "a file it writes cannot be named in a step", after: { try makeWithoutARecord() }
            )
            return
        }
        var ops: [UndoOp] = []
        var blobs: [Data] = []
        var changedFiles: Int = 0
        var changeIndex: Int = -1
        for change in changes {
            changeIndex += 1
            if change.before == change.after {
                continue
            }
            changedFiles += 1
            // A JSON file planned member by member: its `editJSON` ops, and
            // no blob (U4a).
            if let members = plannedMembers[plannedOrder[changeIndex]] {
                for member in members {
                    ops.append(UndoOp.editJSON(
                        path: change.relativePath, keyPath: member.keyPath, before: member.before, after: member.after
                    ))
                }
                continue
            }
            for op in JournaledWrite.ops(for: change) {
                ops.append(op)
                if op.knownKind != .writeFile {
                    continue
                }
                if let before = change.before {
                    blobs.append(before)
                }
                if let after = change.after {
                    blobs.append(after)
                }
            }
        }
        for op in moveOps {
            ops.append(op)
            changedFiles += 1
        }
        for tree in treeOps {
            ops.append(tree.op)
            changedFiles += 1
            for blob in tree.blobs {
                blobs.append(blob)
            }
        }
        for op in plannedExternals {
            ops.append(op)
        }
        for kept in recomputeURLs {
            if let path = UndoFolderPlaces.relativePath(of: kept.url, under: root) {
                ops.append(UndoOp.recompute(path: path, maintainer: kept.maintainer, section: kept.section))
            }
        }
        let draft: UndoOpsDraft = UndoOpsDraft(
            action: action(changedFiles: changedFiles),
            madeBy: maker.madeBy,
            workingFolderURL: root,
            workingFolderPath: FolderIdentity.canonicalPath(root.path),
            course: courseCode,
            section: section,
            actionClass: "A",
            holds: holds,
            ops: ops,
            blobs: blobs
        )
        let journal: UndoJournal = UndoJournalLocation.standardJournal()
        let outcome: JournaledWriteOutcome = JournaledWrite.perform(ops: draft, in: journal, mode: currentMode, places: places)
        switch outcome {
        case .applied, .appliedWithoutARecord, .changedNothing:
            return
        case .refused(let refusal):
            throw JournaledStepError.refused(refusal, fileName: JournaledStep.fileName(in: refusal))
        case .leftPartWay(let refusal, let keptOriginals):
            throw JournaledStepError.leftPartWay(
                refusal, fileName: JournaledStep.fileName(in: refusal), keptOriginals: keptOriginals
            )
        case .couldNotRecordTheStep:
            if currentMode == .live {
                throw JournaledStepError.couldNotRecordTheStep
            }
            try UndoTrailHook.couldNotRecord(
                action: maker.actionKey, course: courseCode, section: section,
                why: "the list could not take the step", after: { try makeWithoutARecord() }
            )
        case .anotherChangeIsUnderWay:
            throw JournaledStepError.anotherChangeIsUnderWay
        case .stoppedByATest:
            throw JournaledStepError.stoppedByATest
        }
    }

    /// The moves as ops inside the working folder, each place's path
    /// relative to it; nil when any cannot be named in a step.
    func recordableMoves(under root: URL) -> [UndoOp]? {
        var result: [UndoOp] = []
        for planned in plannedMoves {
            guard let from = UndoFolderPlaces.relativePath(of: planned.from, under: root),
                  let to = UndoFolderPlaces.relativePath(of: planned.to, under: root) else {
                return nil
            }
            switch planned.kind {
            case .moveApart:
                result.append(UndoOp.moveFileApart(from: from, to: to, sha: planned.sha))
            case .setAside:
                result.append(UndoOp.setFileAside(from: from, to: to, sha: planned.sha))
            default:
                result.append(UndoOp.moveFile(from: from, to: to, sha: planned.sha))
            }
        }
        return result
    }

    /// Each folder to make as a `createTree` op inside the working folder,
    /// with the blobs it needs (its listing and every file's bytes); nil
    /// when any cannot be named in a step.
    func recordableTrees(under root: URL) -> [(op: UndoOp, blobs: [Data])]? {
        var result: [(op: UndoOp, blobs: [Data])] = []
        for tree in plannedTrees {
            guard let path = UndoFolderPlaces.relativePath(of: tree.url, under: root) else {
                return nil
            }
            var blobs: [Data] = [tree.listing.data]
            for file in tree.listing.files {
                if let data = tree.contents[file.path] {
                    blobs.append(data)
                }
            }
            result.append((op: UndoOp.tree(.createTree, path: path, listing: tree.listing), blobs: blobs))
        }
        return result
    }

    /// A step with moves or external ops made in shadow with no record:
    /// every change staged and swapped in together by `UndoSwap`, all or
    /// none, exactly as the door would have made it, so a sentence saying
    /// nothing was changed is true when this throws. Whether every place is
    /// inside the working folder was settled before this is reached (or
    /// cannot be, for a step that cannot be named), so the swap is given no
    /// root to check against.
    func makeWithoutARecord() throws {
        var targets: [UndoSwapTarget] = []
        for key in plannedOrder {
            guard let url = plannedURL[key], let after = plannedAfter[key] else {
                continue
            }
            // The bytes the plan read, so a file another program changed
            // after the plan read it is refused, never written over.
            var before: Data? = nil
            if !mustBeNew.contains(key) {
                switch plannedBefore[key] ?? UndoItem.read(at: url) {
                case .absent:
                    before = nil
                case .file(let data):
                    before = data
                case .notAFile, .unreadable:
                    let refusal: UndoRefusal = .cannotTellNow(path: url.path)
                    throw JournaledStepError.refused(refusal, fileName: JournaledStep.fileName(in: refusal))
                }
            }
            if before == after {
                continue
            }
            targets.append(UndoSwapTarget(url: url, relativePath: url.lastPathComponent, expected: before, replacement: after))
        }
        for planned in plannedMoves {
            let op: UndoOp = UndoOp.moveFile(from: planned.from.path, to: planned.to.path, sha: planned.sha)
            targets.append(UndoSwapTarget(
                url: planned.to, relativePath: planned.to.lastPathComponent,
                change: .moveHere(from: planned.from, fromPath: planned.from.lastPathComponent, op: op)
            ))
        }
        for tree in plannedTrees {
            targets.append(UndoSwapTarget(
                url: tree.url, relativePath: tree.url.lastPathComponent,
                change: .makeTree(tree.listing, contents: tree.contents)
            ))
        }
        for op in plannedExternals {
            guard let target = op.target else {
                continue
            }
            targets.append(UndoSwapTarget(
                url: URL(fileURLWithPath: "/"), relativePath: target,
                change: .setExternal(target: target, expected: op.valueBefore, value: op.valueAfter)
            ))
        }
        switch UndoShadowStaging.swap(targets, noting: UndoJournalLocation.standardJournal(), places: places) {
        case .swapped:
            return
        case .refused(let refusal):
            throw JournaledStepError.refused(refusal, fileName: JournaledStep.fileName(in: refusal))
        case .notPutBack(let refusal, let keptOriginals):
            throw JournaledStepError.leftPartWay(
                refusal, fileName: JournaledStep.fileName(in: refusal), keptOriginals: keptOriginals
            )
        case .stoppedByATest:
            throw JournaledStepError.stoppedByATest
        }
    }

    /// Every planned file as a change inside the working folder, its before
    /// the bytes it held when it was FIRST planned (`plannedBefore`, never a
    /// second read now); nil when any cannot be named in a step.
    func recordableChanges(under root: URL) -> [UndoFileChange]? {
        var result: [UndoFileChange] = []
        for key in plannedOrder {
            guard let url = plannedURL[key], let after = plannedAfter[key] else {
                continue
            }
            guard let relative = UndoFolderPlaces.relativePath(of: url, under: root) else {
                return nil
            }
            if mustBeNew.contains(key) {
                result.append(UndoFileChange(relativePath: relative, before: nil, after: after))
                continue
            }
            // As it was when planned, never re-read here (the first review
            // of U3a, MEDIUM 2): re-reading at `make()` took in whatever
            // another program wrote meanwhile as the step's before, and the
            // door then wrote over it.
            switch plannedBefore[key] ?? UndoItem.read(at: url) {
            case .absent:
                result.append(UndoFileChange(relativePath: relative, before: nil, after: after))
            case .file(let data):
                result.append(UndoFileChange(relativePath: relative, before: data, after: after))
            case .notAFile, .unreadable:
                return nil
            }
        }
        return result
    }

    /// The files of a step that cannot be named, in shadow: written as the
    /// door writes a step, all of them or none, without the list (the first
    /// review of U3a, LOW 3: file by file, a failure part way left half an
    /// action while the reply said "Nothing was changed"). Every new content
    /// is staged beside its target and the files are swapped in together
    /// (`UndoSwap`, label `shadow`, its staged names noted for a tidy after a
    /// kill: `UndoShadowStaging`); each must still hold what it held when it
    /// was planned, and one that was absent must still be absent. A target
    /// that was a link, a folder or a file that could not be read when it was
    /// planned is refused before anything is written, as a live step is: its
    /// content cannot be checked, and writing over a link replaced the
    /// teacher's link with a copy.
    func writePlainly() throws {
        var targets: [UndoSwapTarget] = []
        for key in plannedOrder {
            guard let url = plannedURL[key], let after = plannedAfter[key] else {
                continue
            }
            let expected: Data?
            switch mustBeNew.contains(key) ? UndoItem.absent : (plannedBefore[key] ?? UndoItem.read(at: url)) {
            case .absent:
                expected = nil
            case .file(let data):
                expected = data
            case .notAFile, .unreadable:
                let refusal: UndoRefusal = .cannotTellNow(path: url.path)
                throw JournaledStepError.refused(refusal, fileName: JournaledStep.fileName(in: refusal))
            }
            if expected == after {
                continue
            }
            targets.append(UndoSwapTarget(url: url, relativePath: url.path, expected: expected, replacement: after))
        }
        if targets.isEmpty {
            return
        }
        let journal: UndoJournal = UndoJournalLocation.standardJournal()
        switch UndoShadowStaging.swap(targets, noting: journal) {
        case .swapped:
            return
        case .refused(let refusal):
            throw JournaledStepError.refused(refusal, fileName: JournaledStep.fileName(in: refusal))
        case .notPutBack(let refusal, let keptOriginals):
            throw JournaledStepError.leftPartWay(
                refusal, fileName: JournaledStep.fileName(in: refusal), keptOriginals: keptOriginals
            )
        case .stoppedByATest:
            throw JournaledStepError.stoppedByATest
        }
    }

    // MARK: - Functions: helpers

    private func plan(_ data: Data?, at url: URL) {
        let key: String = JournaledStep.key(of: url)
        if plannedURL[key] == nil {
            plannedOrder.append(key)
            plannedURL[key] = url
            plannedBefore[key] = UndoItem.read(at: url)
        }
        plannedAfter[key] = data
    }

    /// One spelling per place, so a page planned twice is one file.
    static func key(of url: URL) -> String {
        return url.standardizedFileURL.path
    }

    /// The last part of the path a refusal names.
    static func fileName(in refusal: UndoRefusal) -> String {
        let path: String
        switch refusal {
        case .changedSince(let firstPath, _):
            path = firstPath
        case .fileIsInUse(let named), .cannotTellNow(let named), .couldNotWrite(let named), .contentMissing(let named):
            path = named
        case .notReadable:
            path = ""
        }
        return (path as NSString).lastPathComponent
    }
}

/// A place inside a working folder, as a step names it.
nonisolated enum UndoFolderPlaces {

    // MARK: - Functions

    /// The path inside the working folder, with forward slashes, or nil.
    /// Both sides have their links resolved the same way, so a folder
    /// reached through `/var` or a linked folder is still the same folder
    /// (the core review of U1: a differently spelled root recorded nothing).
    static func relativePath(of url: URL, under root: URL) -> String? {
        let rootPath: String = canonicalPath(of: root) + "/"
        let path: String = canonicalPath(of: url)
        if !path.hasPrefix(rootPath) {
            return nil
        }
        return String(path.dropFirst(rootPath.count))
    }

    /// A path with every link resolved, for a file that may not exist yet:
    /// its deepest existing folder is resolved by `realpath`, and the parts
    /// below it are added back as written. Foundation's
    /// `resolvingSymlinksInPath` resolves nothing in a path that does not
    /// exist, so a section whose front page is not there yet, reached
    /// through a linked folder, fell outside its own working folder and its
    /// `recompute` op was not recorded (measured in U1's third round).
    static func canonicalPath(of url: URL) -> String {
        var existing: URL = url.standardizedFileURL
        var below: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path) && existing.path != "/" {
            below.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var resolved: String = existing.path
        if let real = realpath(existing.path, nil) {
            resolved = String(cString: real)
            free(real)
        }
        for part in below {
            resolved = resolved.hasSuffix("/") ? resolved + part : resolved + "/" + part
        }
        return resolved
    }
}

/// A file kept true by a rule (`undoJournal.opKinds.recompute`), written by
/// its maintainer: the section's front page, repointed at its newest visible
/// class after a publish, a re-date or the start of the year. Never content
/// of a step: the step that set it off names it as a `recompute` op, and an
/// Undo or a Redo re-derives it from the pages as they then stand
/// (`UndoSectionFrontPage`), so its write is the rule's, through here.
nonisolated enum UndoKeptFiles {

    // MARK: - Functions

    /// Writes the maintainer's text in place, as the front page was always
    /// written (`String.write`, atomically).
    static func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
