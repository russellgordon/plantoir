import Foundation
import Observation

/// Which courses of one working folder another program holds right now, in
/// the way that would refuse a Deploy pressed here, kept up to date by events
/// (GitHub #729).
///
/// **What it answers.** For each course, the holding
/// `WorkLeaseFiles.blocking(among: heldElsewhere(…), asker: .aBuild, claim:
/// nil)` returns: exactly what `deployWillBeRefused` asks at the press. So the
/// Deploy button is grey for this reason if and only if a press would be
/// refused for it (`shared-rules.json` → `returningToASectionMidDeploy
/// .heldElsewhere.rule`). Another program's `build`, `publish` OR `preview`
/// lease counts, because a press is refused for each of them today.
///
/// **What makes it move: events, never a clock.**
/// - The activity folder (`courses/.internal/activity/`): a lease is written
///   with `Data.write(.atomic)` (a temporary file renamed into place) or by
///   `mv`, and removed with `unlink`, and each of those changes the folder's
///   entries, which is what a directory watch reports. A lease's information
///   is its NAME and its owner's liveness, so the 0-of-40 measurement behind
///   `ScheduledPublishWatcher` (a file growing in place raises no folder
///   event) is not the shape here. Measured for #729 (W1 to W12,
///   `documentation/09-mac-app.md` → "Deploy waits for another program
///   (#729)").
/// - While the activity folder does not exist yet, the nearest folder above
///   it that does (`courses/.internal`, then `courses/`) is watched instead,
///   and the watch moves down when it appears. Nothing is created here.
/// - Each holder's process: one `ProcessEnding.ends(of:)` per distinct process
///   id among the blocking leases. This is what un-greys the button when a
///   holder is killed or crashes and leaves its lease behind: its lease then
///   reads as stale, and no file event will ever come.
/// - `reread()` is also called by the section view when it appears, when the
///   app or its window comes to the front, and when the pointer enters the
///   Deploy button (the plan review's M4): a stuck grey is the harmful
///   failure, because a disabled button cannot be pressed, and those are the
///   moments the teacher reaches for it.
///
/// **What it cannot see.** A program that holds no lease (a `deploy.sh` typed
/// in Terminal). The press reaches the launcher's guard, which refuses in
/// words (`deployWhileItsSectionDeploys`). Not polled for: no event says a
/// process started.
///
/// `init` is inert, as `ScheduledPublishWatcher`'s is: a test that builds a
/// window touches no disk. `start()` is called by `LeaseWatchers` for the
/// folders the app's windows show, and never under the unit-test suite.
@MainActor
@Observable
final class LeaseWatcher {

    // MARK: - Stored properties

    /// For each course another live program holds in a way that would refuse
    /// a Deploy pressed here, the first holding that would refuse it. Keyed
    /// by the course code upper-cased, the way leases name it.
    private(set) var holdingElsewhere: [String: WorkLeaseFiles.Holding] = [:]

    /// Moves every time `holdingElsewhere` changes, and only then.
    private(set) var generation: Int = 0

    /// How many times the folder has been read. For the tests and the
    /// measurement; nothing a teacher sees depends on it.
    @ObservationIgnored private(set) var rereads: Int = 0

    /// How many events the folder watch has delivered. For the measurement.
    @ObservationIgnored private(set) var folderEvents: Int = 0

    /// The working folder's `courses/` folder.
    let coursesDirectory: URL

    /// This process, whose own leases never count.
    @ObservationIgnored private let ownPID: Int32

    /// The task reading the folder watch, or nil while the watch is deaf
    /// (nothing to open yet, or the watched folder went away and nothing
    /// could be opened in its place).
    @ObservationIgnored private var folderTask: Task<Void, Never>?

    /// One task per holder's process id, each waiting for it to end.
    @ObservationIgnored private var holderWatches: [Int32: Task<Void, Never>] = [:]

    /// True between `start()` and `stop()`.
    @ObservationIgnored private(set) var isStarted: Bool = false

    // MARK: - Computed properties

    /// `courses/.internal/activity/`.
    var activityDirectory: URL {
        return WorkLeaseFiles.activityDirectory(coursesDirectory: coursesDirectory)
    }

    /// How many holders' processes are being waited on. For the tests.
    var holderWatchCount: Int {
        return holderWatches.count
    }

    /// True while a folder watch is armed. For the tests.
    var folderIsWatched: Bool {
        return folderTask != nil
    }

    // MARK: - Initializer

    init(coursesDirectory: URL, ownPID: Int32 = getpid()) {
        self.coursesDirectory = coursesDirectory
        self.ownPID = ownPID
    }

    // MARK: - Functions

    /// What another program holds on a course that would refuse a Deploy
    /// pressed here, or nil.
    func holding(forCourse courseCode: String) -> WorkLeaseFiles.Holding? {
        return holdingElsewhere[courseCode.uppercased()]
    }

    /// Begin watching. Calling it again does nothing.
    ///
    /// The folder watch is ARMED before the first read, so a lease written
    /// in between is seen by one or the other.
    func start() {
        if isStarted {
            return
        }
        isStarted = true
        armTheFolderWatch()
        reread()
    }

    /// Stop watching and let go of every descriptor and process watch.
    func stop() {
        isStarted = false
        folderTask?.cancel()
        folderTask = nil
        for (pid, task) in holderWatches {
            task.cancel()
            holderWatches.removeValue(forKey: pid)
        }
    }

    /// Read the leases again, and say so on `generation` if the answer
    /// changed. Re-arms a deaf folder watch first, so every outside event
    /// (a section appearing, the app coming to the front, the pointer on the
    /// button) is also a chance to start watching again. Each attempt is
    /// caused by an event; there is no timer here.
    ///
    /// `rearming: false` is for the folder watch's own last read: a watch
    /// that could not be opened ends at once, and re-arming from there would
    /// open, fail and end again without anything having happened, which is
    /// a spin.
    func reread(rearming: Bool = true) {
        if rearming && isStarted && folderTask == nil {
            armTheFolderWatch()
        }
        rereads += 1
        let everyLease: [(course: String, holding: WorkLeaseFiles.Holding)] =
            WorkLeaseFiles.everyLeaseHeldElsewhere(coursesDirectory: coursesDirectory, ownPID: ownPID)
        let answer: (holdings: [String: WorkLeaseFiles.Holding], holders: Set<Int32>) =
            LeaseWatcher.whatRefusesADeploy(among: everyLease)
        if answer.holdings != holdingElsewhere {
            holdingElsewhere = answer.holdings
            generation += 1
        }
        if isStarted {
            followTheHolders(answer.holders)
        }
    }

    /// The rule, with nothing read from disk: for each course, what
    /// `WorkLeaseFiles.blocking` says would refuse a build asked with no
    /// claim (a press, before anything is taken), and the process ids of
    /// every holder whose lease is of a kind that refuses one.
    nonisolated static func whatRefusesADeploy(
        among everyLease: [(course: String, holding: WorkLeaseFiles.Holding)]
    ) -> (holdings: [String: WorkLeaseFiles.Holding], holders: Set<Int32>) {
        var byCourse: [String: [WorkLeaseFiles.Holding]] = [:]
        var holders: Set<Int32> = []
        for entry in everyLease {
            let course: String = entry.course.uppercased()
            var list: [WorkLeaseFiles.Holding] = byCourse[course] ?? []
            list.append(entry.holding)
            byCourse[course] = list
            if WorkLeaseFiles.kindsThatBlockABuild.contains(entry.holding.kind.lowercased()) {
                holders.insert(entry.holding.pid)
            }
        }
        var holdings: [String: WorkLeaseFiles.Holding] = [:]
        for (course, list) in byCourse {
            if let blocking = WorkLeaseFiles.blocking(among: list, asker: .aBuild, claim: nil) {
                holdings[course] = blocking
            }
        }
        return (holdings: holdings, holders: holders)
    }

    /// Wait on every holder's process that is not waited on yet, and stop
    /// waiting on those no longer listed.
    private func followTheHolders(_ holders: Set<Int32>) {
        for (pid, task) in holderWatches where !holders.contains(pid) {
            task.cancel()
            holderWatches.removeValue(forKey: pid)
        }
        for pid in holders where holderWatches[pid] == nil {
            // Armed here, before the task runs: `ProcessEnding.ends` arms its
            // source in the stream's build closure and only then asks whether
            // the process still exists, so an ending in between is not lost.
            let ending: AsyncStream<Void> = ProcessEnding.ends(of: pid)
            holderWatches[pid] = Task { [weak self] in
                for await _ in ending {
                    break
                }
                if Task.isCancelled {
                    return
                }
                self?.holderEnded(pid)
            }
        }
    }

    /// A holder's process has ended: forget its watch and read again.
    private func holderEnded(_ pid: Int32) {
        holderWatches.removeValue(forKey: pid)
        reread()
    }

    /// Arm a watch on the activity folder, or on the nearest folder above it
    /// that exists while it does not. Leaves the watch deaf when none of them
    /// exists (no `courses/` at all): the next outside event tries again.
    private func armTheFolderWatch() {
        let candidates: [URL] = [
            activityDirectory,
            activityDirectory.deletingLastPathComponent(),
            coursesDirectory
        ]
        var watched: URL? = nil
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                watched = candidate
                break
            }
        }
        guard let watched else {
            return
        }
        let watchingTheFolderItself: Bool = watched == activityDirectory
        let changes: AsyncStream<ScheduledPublishWatcher.Change> = ScheduledPublishWatcher.changes(
            at: watched, watching: [.write, .delete, .rename]
        )
        folderTask = Task { [weak self] in
            await self?.watchTheFolder(changes, watchingTheFolderItself: watchingTheFolderItself)
        }
        // Arm first, look second: a folder above it that is watched because
        // the activity folder did not exist may have gained it between the
        // look above and the arm. Moving down now costs one more watch.
        if !watchingTheFolderItself && activityDirectoryExists() {
            folderTask?.cancel()
            folderTask = nil
            armTheFolderWatch()
        }
    }

    /// Read every change the watch delivers; move the watch when what it is
    /// on went away, or when the activity folder appears under a folder above
    /// it.
    private func watchTheFolder(
        _ changes: AsyncStream<ScheduledPublishWatcher.Change>,
        watchingTheFolderItself: Bool
    ) async {
        var moveTheWatch: Bool = false
        for await change in changes {
            folderEvents += 1
            if change == .theWatchedThingWentAway {
                moveTheWatch = true
                break
            }
            if !watchingTheFolderItself && activityDirectoryExists() {
                moveTheWatch = true
                break
            }
            reread()
        }
        if Task.isCancelled {
            return
        }
        folderTask = nil
        if moveTheWatch && isStarted {
            // Caused by an event, so this cannot spin: a watch that could not
            // be opened ends WITHOUT one, and is left deaf for the next
            // outside event to re-arm.
            armTheFolderWatch()
        }
        reread(rearming: false)
    }

    /// Whether the activity folder is there now.
    private func activityDirectoryExists() -> Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(
            atPath: activityDirectory.path, isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }
}

/// The lease watchers for the working folders the app's windows show: one per
/// folder however many windows show it, started when the first window points
/// at it and stopped when the last one leaves (#729).
///
/// Process-wide and observable, so a section view that drew before its
/// folder's watcher existed draws again when it appears. Never started under
/// the unit-test suite (`WorkspaceModel.isRunningTests`): tests build real
/// windows on pretend folders, and must touch no disk this way.
@MainActor
@Observable
final class LeaseWatchers {

    // MARK: - Stored properties

    /// The one the app uses.
    static let shared: LeaseWatchers = LeaseWatchers()

    /// The watchers, keyed by `FolderIdentity.canonicalPath` of the folder.
    private(set) var watchers: [String: LeaseWatcher] = [:]

    // MARK: - Functions

    /// The watcher for a folder, or nil when none is running for it.
    func watcher(forFolder folder: URL) -> LeaseWatcher? {
        return watchers[FolderIdentity.canonicalPath(folder.path)]
    }

    /// Start a watcher for every folder in `folders` that has none, and stop
    /// those whose folder is no longer in it.
    func follow(_ folders: [URL]) {
        var wanted: [String: URL] = [:]
        for folder in folders {
            wanted[FolderIdentity.canonicalPath(folder.path)] = folder
        }
        for (path, watcher) in watchers where wanted[path] == nil {
            watcher.stop()
            watchers.removeValue(forKey: path)
        }
        for (path, folder) in wanted where watchers[path] == nil {
            let watcher: LeaseWatcher = LeaseWatcher(
                coursesDirectory: folder.appendingPathComponent("courses", isDirectory: true)
            )
            watchers[path] = watcher
            watcher.start()
        }
    }
}
