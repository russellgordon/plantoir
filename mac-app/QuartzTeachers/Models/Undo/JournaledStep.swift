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

    // MARK: - Computed properties

    var errorDescription: String? {
        switch self {
        case .refused(_, let fileName):
            return CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileName]).localizedDescription
        case .couldNotRecordTheStep, .anotherChangeIsUnderWay:
            return CocoaError(.fileWriteUnknown).localizedDescription
        case .stoppedByATest:
            return "stopped by a test"
        }
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
/// read) cannot be named in a step: in shadow those files are written as the
/// action always wrote them, with one trail line; live, the step is refused
/// before anything changes, because an unrecorded change above the head
/// would be passed over by the next Undo.
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

    /// Each planned file that was not there when first planned: never
    /// written over, even by `writePlainly` (a page that appeared since).
    private var absentWhenPlanned: Set<String> = []

    /// Files kept true by a rule, re-derived after the step
    /// (`undoJournal.opKinds.recompute`).
    private(set) var recomputeURLs: [(url: URL, maintainer: String, section: Int?)] = []

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
        return plannedOrder.isEmpty
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

    /// Plans the file at `url` to be removed.
    func remove(_ url: URL) {
        plan(nil, at: url)
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
    /// runner before every tool and by the sheets before their planners.
    /// What is left on the main actor is the lock (at most 50 ms in shadow)
    /// and one flush (4 ms on the M4 Pro), measured in documentation 09.
    @concurrent
    static func readTheListAhead() async {
        let journal: UndoJournal = UndoJournalLocation.standardJournal()
        _ = try? journal.read()
    }

    /// Makes the step through the door: written down first (in shadow, when
    /// the list can take it), then every planned file staged and swapped in
    /// together. Throws, having written nothing, when the door refuses.
    func make() throws {
        if plannedOrder.isEmpty {
            return
        }
        let currentMode: UndoMode = mode
        guard let root = workingFolderURL, let changes = recordableChanges(under: root) else {
            if currentMode == .live {
                throw JournaledStepError.couldNotRecordTheStep
            }
            UndoTrailHook.couldNotRecordLine?(
                maker.actionKey, courseCode, section, .shadow, "a file it writes cannot be named in a step"
            )
            try writePlainly()
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
        case .couldNotRecordTheStep:
            throw JournaledStepError.couldNotRecordTheStep
        case .anotherChangeIsUnderWay:
            throw JournaledStepError.anotherChangeIsUnderWay
        case .stoppedByATest:
            throw JournaledStepError.stoppedByATest
        }
    }

    /// Every planned file as a change inside the working folder, its before
    /// the disk's bytes now; nil when any cannot be named in a step.
    func recordableChanges(under root: URL) -> [UndoFileChange]? {
        var result: [UndoFileChange] = []
        for key in plannedOrder {
            guard let url = plannedURL[key], let after = plannedAfter[key] else {
                continue
            }
            guard let relative = UndoFolderPlaces.relativePath(of: url, under: root) else {
                return nil
            }
            let before: Data?
            switch UndoItem.read(at: url) {
            case .absent:
                before = nil
            case .file(let data):
                before = data
            case .notAFile, .unreadable:
                return nil
            }
            result.append(UndoFileChange(relativePath: relative, before: before, after: after))
        }
        return result
    }

    /// The files written as the actions wrote them before U3: in shadow,
    /// for a step that cannot be named. Each file whole and in place
    /// (`.atomic`), its folder made first; a removal of a file that is
    /// already gone is not a failure.
    func writePlainly() throws {
        for key in plannedOrder {
            guard let url = plannedURL[key], let after = plannedAfter[key] else {
                continue
            }
            if let after {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                if absentWhenPlanned.contains(key) && FileManager.default.fileExists(atPath: url.path) {
                    throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
                }
                try after.write(to: url, options: .atomic)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Functions: helpers

    private func plan(_ data: Data?, at url: URL) {
        let key: String = JournaledStep.key(of: url)
        if plannedURL[key] == nil {
            plannedOrder.append(key)
            plannedURL[key] = url
            if case .absent = UndoItem.read(at: url) {
                absentWhenPlanned.insert(key)
            }
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
