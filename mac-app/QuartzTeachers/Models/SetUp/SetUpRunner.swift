import Foundation
import Synchronization

/// How one set-up ended (#855). Each has its own sentence for the teacher
/// (`AssistantSetUpWording`) and its own trail line, because each arrives
/// later as the same report: "it said it couldn't set it up".
nonisolated enum SetUpOutcome: Equatable, Sendable {
    /// The program is in place and is the maker's.
    case finished
    /// A host the set-up needs did not answer: no connection, or a school
    /// network's filter. Nothing was run.
    case noConnection(host: String)
    /// The maker's set-up could not be fetched from the maker's own address:
    /// a refused redirect, or a page that was not a set-up.
    case couldNotFetch(reason: String)
    /// The set-up could not be started at all.
    case couldNotStart
    /// The set-up ran and stopped with this exit status (128 and above is a
    /// signal: a school's security software ending it, for one).
    case exited(status: Int32)
    /// The set-up said it finished, and a program it must leave is missing.
    case leftNothing(program: String)
    /// A program it left is not signed by the maker. Taken away again.
    case notFromMaker(program: String)
    /// The teacher pressed Stop, or quit and chose to quit anyway.
    case stopped
    /// It ran past `SetUpDependencies.longestRun` and was stopped.
    case tookTooLong
    /// The record could not be written, so nothing was run: a set-up
    /// Plantoir cannot record is one it could not remove.
    case couldNotRecord

    // MARK: - Computed properties

    /// The words after "could not set up {tool}: " on the trail. No path,
    /// no output, no account.
    var trailWords: String {
        switch self {
        case .finished:
            return "it finished"
        case .noConnection(let host):
            return "no connection to \(host)"
        case .couldNotFetch(let reason):
            return "its set-up could not be fetched (\(reason))"
        case .couldNotStart:
            return "its set-up could not be started"
        case .exited(let status):
            return "its set-up stopped with status \(status)"
        case .leftNothing(let program):
            return "it left no \(program)"
        case .notFromMaker(let program):
            return "\(program) was not signed by its maker, so it was taken away"
        case .stopped:
            return "it was stopped"
        case .tookTooLong:
            return "it took too long and was stopped"
        case .couldNotRecord:
            return "Plantoir could not write down what it was about to change, so nothing was run"
        }
    }
}

/// What a set-up reaches outside Plantoir, gathered so a test can stand in
/// for every piece of it: the network, the signature check, the account's
/// shell and the clock. The app always uses `live`.
nonisolated struct SetUpDependencies: Sendable {

    // MARK: - Types

    /// What fetching the maker's set-up produced.
    enum Fetched: Sendable {
        case script(Data)
        case refused(String)
    }

    // MARK: - Stored properties

    /// Whether `host` answers at all.
    var reach: @Sendable (String) async -> Bool
    /// The maker's set-up, fetched from `address` through `allowedAddresses` only.
    var fetch: @Sendable (_ address: URL, _ allowedAddresses: [String]) async -> Fetched
    var identity: any ProgramIdentityChecking
    /// The login shell from the account record, never `$SHELL` (review H3).
    var accountShell: String
    /// The account's short name.
    var userName: String
    /// The longest a set-up may run before it is stopped.
    var longestRun: Duration
    /// How long a stopped set-up is given to end before it is ended outright.
    var stopGrace: Duration

    // MARK: - Computed properties

    /// The app's own: the real network, the real signature check, the
    /// account record's shell, and the contract's limits.
    static var live: SetUpDependencies {
        return SetUpDependencies(
            reach: { (host: String) async -> Bool in
                return await SetUpNetwork.answers(host: host)
            },
            fetch: { (address: URL, allowedAddresses: [String]) async -> Fetched in
                return await SetUpNetwork.fetchSetUp(from: address, allowedAddresses: allowedAddresses)
            },
            identity: DeveloperIDCheck(),
            accountShell: SetUpRunner.accountShell(),
            userName: RealHome.accountName,
            longestRun: .seconds(SetUpRunner.longestRunMinutes * 60),
            stopGrace: .seconds(SetUpRunner.stopGraceSeconds)
        )
    }
}

/// One set-up of one program, from the press of the button to the record
/// (#855). Nothing here knows about assistants. The handout programs planned
/// after #855 reuse the process handling (`run`, `stopNow`, the limit), the
/// child environment and the record, and must add their own
/// download-verify-unpack step beside `perform`'s "run the maker's set-up"
/// (`SetUpRecipe`'s comment says what exactly).
///
/// The steps, in order:
/// 1. Ask every host the set-up needs (review M2), so "no connection" is
///    told apart from every other failure without reading any output.
/// 2. Fetch the maker's own set-up from the maker's own address, following
///    redirects only to the hosts the recipe names (review L4).
/// 3. Look at the home folder and write the record BEFORE anything runs
///    (`SetUpRecord`, review M3 and H4).
/// 4. Run it with an environment Plantoir builds from nothing, no terminal,
///    and in a session of its own (review H3): with a controlling terminal,
///    two of the three set-ups ask a question on it and wait for ever
///    (measured 2026-11-13 with a stand-in of their prompt: a plain spawn
///    under a terminal was still waiting after 5 s; a new session went on
///    at once, finding no terminal).
/// 5. Look again, check every program it left is the maker's, and complete
///    the record; or take away exactly what it added.
nonisolated final class SetUpRunner: Sendable {

    // MARK: - Stored properties

    /// The contract's `setUp.longestRunMinutes`: far longer than the 7.5 s
    /// the longest of the three took on a fast connection, and long enough
    /// for Claude Code's 344 MB on a slow school network.
    static let longestRunMinutes: Int64 = 30

    /// The contract's `setUp.stopGraceSeconds`.
    static let stopGraceSeconds: Int64 = 5

    /// The search path the set-up gets: the Dock's, with nothing a teacher's
    /// own shell added, so a set-up never finds a second copy of anything.
    static let childSearchPath: String = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// The names the child's environment is built from, in order. Nothing
    /// else is passed: not `PREFIX`, `VERSION` or `GITHUB_TOKEN` (Copilot's
    /// set-up reads all three, and sends the last as a header), not the
    /// `CODEX_*` settings Codex's set-up reads, not `ZDOTDIR`, and not an
    /// inherited `SHELL`, which picks the start-up file Codex writes.
    static let childEnvironmentNames: [String] = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "PATH", "SHELL"]

    static let childLanguage: String = "en_US.UTF-8"

    let recipe: SetUpRecipe
    let home: URL
    let kind: String
    let dependencies: SetUpDependencies

    private let childProcess: Mutex<pid_t> = Mutex(0)
    private let reaped: Mutex<Bool> = Mutex(false)
    private let stopWasAsked: Mutex<Bool> = Mutex(false)

    // MARK: - Initializer

    init(recipe: SetUpRecipe, home: URL, kind: String, dependencies: SetUpDependencies) {
        self.recipe = recipe
        self.home = home
        self.kind = kind
        self.dependencies = dependencies
    }

    // MARK: - Functions

    /// The login shell the account record names (`RealHome.accountShell`).
    static func accountShell() -> String {
        return RealHome.accountShell
    }

    /// The child's whole environment, built from nothing.
    static func childEnvironment(
        home: String,
        user: String,
        shell: String,
        temporaryFolder: String,
        extra: [String: String]
    ) -> [String: String] {
        var environment: [String: String] = [
            "HOME": home,
            "USER": user,
            "LOGNAME": user,
            "TMPDIR": temporaryFolder,
            "LANG": childLanguage,
            "PATH": childSearchPath,
            "SHELL": shell
        ]
        for (name, value) in extra {
            environment[name] = value
        }
        return environment
    }

    /// Asks the set-up to stop: the whole group of programs it started, with
    /// time to tidy, then outright. Safe to call from the main actor at
    /// quit, and before or after the set-up has started.
    func stop() {
        stopWasAsked.withLock { (asked: inout Bool) in
            asked = true
        }
        signalTheGroup(SIGTERM)
        let grace: Duration = dependencies.stopGrace
        // A grace period that is the intended behaviour (time for the
        // set-up to tidy), not a wait for something else to settle.
        Task { [self] in
            try? await Task.sleep(for: grace)
            self.signalTheGroup(SIGKILL)
        }
    }

    /// Stops the set-up AT ONCE, for a quit: asks it to end, gives it at
    /// most `quitGraceMilliseconds` (polling whether it has gone), then ends
    /// the whole group outright, before returning. `stop()`'s later outright
    /// end is a task that a quitting app never lives to run, so a set-up
    /// that ignored the request outlived the quit (review finding 4).
    func stopNow() {
        stopWasAsked.withLock { (asked: inout Bool) in
            asked = true
        }
        signalTheGroup(SIGTERM)
        var waited: Int = 0
        while waited < SetUpRunner.quitGraceMilliseconds && !isReaped {
            usleep(20_000)
            waited += 20
        }
        // The whole group, leader reaped or not: what it started in the
        // background goes with it, as `run` does once a set-up ends.
        let group: pid_t = childProcess.withLock { (pid: inout pid_t) -> pid_t in
            return pid
        }
        // Only while the leader is unreaped: once `run` has reaped it, it
        // has already ended the group itself, and the number may since
        // belong to something else (`signalTheGroup`'s rule).
        if group > 0 && !isReaped {
            killpg(group, SIGKILL)
        }
    }

    /// How long a set-up is given to end on its own at a quit.
    static let quitGraceMilliseconds: Int = 500

    /// Whether the set-up has ended and been reaped.
    var isReaped: Bool {
        return reaped.withLock { (value: inout Bool) -> Bool in
            return value
        }
    }

    /// Whether Stop has been asked for.
    var wasStopped: Bool {
        return stopWasAsked.withLock { (asked: inout Bool) -> Bool in
            return asked
        }
    }

    /// Sends `signal` to the set-up's process group, unless it has already
    /// been reaped (its number may since belong to something else).
    private func signalTheGroup(_ signal: Int32) {
        let group: pid_t = childProcess.withLock { (pid: inout pid_t) -> pid_t in
            return pid
        }
        let isReaped: Bool = reaped.withLock { (value: inout Bool) -> Bool in
            return value
        }
        if group > 0 && !isReaped {
            kill(-group, signal)
        }
    }

    /// The whole set-up. Off the main actor (`@concurrent`): the reach, the
    /// fetch, the wait and the signature check of a 344 MB program all take
    /// time a window must not spend.
    /// - Parameter progress: told when the download is done and checking
    ///   begins.
    @concurrent
    func perform(progress: @escaping @Sendable (SetUpPhase) -> Void) async -> SetUpOutcome {
        var hosts: [String] = [recipe.installerHost]
        for host in recipe.reachabilityHosts where !hosts.contains(host) {
            hosts.append(host)
        }
        for host in hosts {
            if wasStopped {
                return .stopped
            }
            if !(await dependencies.reach(host)) {
                return .noConnection(host: host)
            }
        }
        if wasStopped {
            return .stopped
        }

        let fetched: SetUpDependencies.Fetched = await dependencies.fetch(recipe.installerAddress, recipe.allowedAddresses)
        let script: Data
        switch fetched {
        case .script(let data):
            script = data
        case .refused(let reason):
            return .couldNotFetch(reason: reason)
        }
        if wasStopped {
            return .stopped
        }

        let workFolder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-set-up-\(recipe.key)-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: workFolder)
        }
        let scriptURL: URL = workFolder.appendingPathComponent("set-up.sh")
        do {
            try FileManager.default.createDirectory(
                at: workFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            try script.write(to: scriptURL)
        } catch {
            return .couldNotStart
        }

        // The record first, holding what is here now.
        let previous: SetUpRecordEntry? = SetUpRecord.entry(for: recipe.key, home: home)
        let before: SetUpSnapshot = SetUpRecord.snapshot(of: recipe, home: home)
        var entry: SetUpRecordEntry = SetUpRecordEntry(
            key: recipe.key, kind: kind, state: .installing, started: Date(), finished: nil, before: before,
            created: previous?.created ?? [], createdFolders: previous?.createdFolders ?? [],
            profileChanges: previous?.profileChanges ?? [], changedInPlace: previous?.changedInPlace ?? []
        )
        do {
            try SetUpRecord.store(entry, home: home)
        } catch {
            return .couldNotRecord
        }

        let environment: [String: String] = SetUpRunner.childEnvironment(
            home: home.path,
            user: dependencies.userName,
            shell: dependencies.accountShell,
            temporaryFolder: workFolder.path,
            extra: recipe.extraEnvironment
        )
        var status: SetUpExit = .couldNotStart
        if !wasStopped {
            status = await run(
                executable: recipe.interpreter,
                arguments: [recipe.interpreter, scriptURL.path],
                environment: environment,
                workingFolder: workFolder.path
            )
        }

        progress(.checking)
        let changes = SetUpRecord.changes(of: recipe, since: before, home: home)
        let thisRun: SetUpRecordEntry = SetUpRecordEntry(
            key: recipe.key, kind: kind, state: .installed, started: entry.started, finished: Date(), before: nil,
            created: changes.created, createdFolders: changes.createdFolders,
            profileChanges: changes.profileChanges, changedInPlace: changes.changedInPlace
        )

        var outcome: SetUpOutcome = .finished
        if wasStopped {
            outcome = .stopped
        } else {
            switch status {
            case .exited(let code):
                if code != 0 {
                    outcome = .exited(status: code)
                }
            case .timedOut:
                outcome = .tookTooLong
            case .couldNotStart:
                outcome = .couldNotStart
            }
        }
        if outcome == .finished {
            outcome = checkPrograms()
        }

        if outcome != .finished {
            // Take away exactly what this run added, and put the record back
            // as it was before it.
            _ = SetUpRecord.takeAway(thisRun, recipe: recipe, home: home)
            if let previous {
                try? SetUpRecord.store(previous, home: home)
            } else {
                try? SetUpRecord.forget(recipe.key, home: home)
            }
            return outcome
        }

        entry = SetUpRunner.merging(thisRun, into: previous)
        do {
            try SetUpRecord.store(entry, home: home)
        } catch {
            _ = SetUpRecord.takeAway(thisRun, recipe: recipe, home: home)
            return .couldNotRecord
        }
        return .finished
    }

    /// A finished run's changes added to what an earlier set-up of the same
    /// program recorded, so Remove still takes away both.
    static func merging(_ run: SetUpRecordEntry, into previous: SetUpRecordEntry?) -> SetUpRecordEntry {
        guard let previous else {
            return run
        }
        var merged: SetUpRecordEntry = run
        merged.started = previous.started
        for path in previous.created where !merged.created.contains(path) {
            merged.created.append(path)
        }
        for folder in previous.createdFolders where !merged.createdFolders.contains(folder) {
            merged.createdFolders.append(folder)
        }
        for change in previous.profileChanges where !merged.profileChanges.contains(change) {
            merged.profileChanges.append(change)
        }
        for path in previous.changedInPlace where !merged.changedInPlace.contains(path) {
            merged.changedInPlace.append(path)
        }
        return merged
    }

    /// Every program the recipe names: there, and the maker's.
    func checkPrograms() -> SetUpOutcome {
        for program in recipe.programs {
            let path: String = home.appendingPathComponent(program.path).path
            let isThere: Bool = FileManager.default.isExecutableFile(atPath: path)
            if !isThere {
                if program.required {
                    return .leftNothing(program: (program.path as NSString).lastPathComponent)
                }
                continue
            }
            if !dependencies.identity.isSigned(atPath: path, identifier: program.identifier, team: program.team) {
                return .notFromMaker(program: (program.path as NSString).lastPathComponent)
            }
        }
        return .finished
    }

    /// How the child ended.
    enum SetUpExit: Equatable, Sendable {
        case exited(Int32)
        case timedOut
        case couldNotStart
    }

    /// Starts `executable` in a session of its own, with `environment` and
    /// nothing else, no terminal, its input from `/dev/null` and its output
    /// discarded, and waits for it, for at most `longestRun`.
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingFolder: String
    ) async -> SetUpExit {
        guard let pid = SetUpRunner.spawnInItsOwnSession(
            executable: executable, arguments: arguments, environment: environment, workingFolder: workingFolder
        ) else {
            return .couldNotStart
        }
        childProcess.withLock { (stored: inout pid_t) in
            stored = pid
        }
        // A Stop pressed in the instant before the number was known.
        if wasStopped {
            signalTheGroup(SIGTERM)
        }

        let limit: Duration = dependencies.longestRun
        let grace: Duration = dependencies.stopGrace
        let ended: SetUpExit = await withTaskGroup(of: SetUpExit?.self) { (group: inout TaskGroup<SetUpExit?>) -> SetUpExit in
            group.addTask { [self] in
                let status: Int32 = await self.waitForExit(pid)
                return .exited(SetUpRunner.exitCode(fromWaitStatus: status))
            }
            group.addTask {
                do {
                    try await Task.sleep(for: limit)
                } catch {
                    return nil
                }
                return .timedOut
            }
            var answer: SetUpExit = .couldNotStart
            var timedOut: Bool = false
            while let next = await group.next() {
                guard let next else {
                    continue
                }
                if next == .timedOut {
                    timedOut = true
                    self.signalTheGroup(SIGTERM)
                    group.addTask { [self] in
                        try? await Task.sleep(for: grace)
                        self.signalTheGroup(SIGKILL)
                        return nil
                    }
                    continue
                }
                answer = timedOut ? .timedOut : next
                group.cancelAll()
            }
            return answer
        }
        // The whole group, once the set-up itself is gone: a download it
        // started in the background must not outlive it. A number is not
        // given to a new process while a group of that number still has a
        // member, so this reaches only what the set-up left.
        killpg(pid, SIGKILL)
        return ended
    }

    /// An exit status, or 128 plus the signal that ended it, from what
    /// `waitpid` reports (the `WIFEXITED` family, which Swift cannot import).
    static func exitCode(fromWaitStatus status: Int32) -> Int32 {
        let signal: Int32 = status & 0x7f
        if signal == 0 {
            return (status >> 8) & 0xff
        }
        return 128 + signal
    }

    /// Waits for `pid` on a thread of its own, so no thread of the shared
    /// pool is held for the minutes a download can take.
    func waitForExit(_ pid: pid_t) async -> Int32 {
        let status: Int32 = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let waiter: Thread = Thread {
                var status: Int32 = 0
                var result: pid_t = waitpid(pid, &status, 0)
                while result == -1 && errno == EINTR {
                    result = waitpid(pid, &status, 0)
                }
                continuation.resume(returning: status)
            }
            waiter.name = "Plantoir set-up wait"
            waiter.start()
        }
        reaped.withLock { (value: inout Bool) in
            value = true
        }
        return status
    }

    /// `posix_spawn` with a new session (`POSIX_SPAWN_SETSID`, so there is no
    /// controlling terminal for a prompt to open), every inherited file
    /// closed, default signal handling and an empty mask, and the three
    /// standard files on `/dev/null`. Returns the child's number (also its
    /// group's and session's), or nil.
    static func spawnInItsOwnSession(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingFolder: String
    ) -> pid_t? {
        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawnattr_destroy(&attributes)
        }
        let flags: Int32 = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        var everySignal: sigset_t = sigset_t()
        sigfillset(&everySignal)
        posix_spawnattr_setsigdefault(&attributes, &everySignal)
        var noSignals: sigset_t = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)

        var fileActions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fileActions)
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
        }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addchdir_np(&fileActions, workingFolder)

        var argumentPointers: [UnsafeMutablePointer<CChar>?] = []
        for argument in arguments {
            argumentPointers.append(strdup(argument))
        }
        argumentPointers.append(nil)
        var environmentPointers: [UnsafeMutablePointer<CChar>?] = []
        for name in environment.keys.sorted() {
            environmentPointers.append(strdup("\(name)=\(environment[name] ?? "")"))
        }
        environmentPointers.append(nil)
        defer {
            for pointer in argumentPointers {
                free(pointer)
            }
            for pointer in environmentPointers {
                free(pointer)
            }
        }

        var pid: pid_t = 0
        let result: Int32 = posix_spawn(&pid, executable, &fileActions, &attributes, argumentPointers, environmentPointers)
        if result != 0 {
            return nil
        }
        return pid
    }
}

/// Where a set-up has got to, for the progress line.
nonisolated enum SetUpPhase: Sendable {
    case downloading
    case checking
}

/// The two network questions a set-up asks, through `URLSession` so the
/// Mac's own proxy settings apply.
nonisolated enum SetUpNetwork {

    // MARK: - Functions

    /// Whether `host` answers over HTTPS at all: ANY response counts (a 403
    /// or 404 at the root is still an answer); only a failure to connect
    /// does not.
    static func answers(host: String) async -> Bool {
        guard let address = URL(string: "https://\(host)/") else {
            return false
        }
        var request: URLRequest = URLRequest(url: address)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        let session: URLSession = URLSession(configuration: .ephemeral)
        defer {
            session.finishTasksAndInvalidate()
        }
        do {
            let (_, response): (Data, URLResponse) = try await session.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    /// The maker's set-up, or why it was refused: a redirect to a host
    /// `allowedAddresses` does not name, an answer other than 200, or something
    /// far larger than any of the three (each under 100 KB, 2026-11-13).
    static func fetchSetUp(from address: URL, allowedAddresses: [String]) async -> SetUpDependencies.Fetched {
        let guardian: SetUpRedirectGuard = SetUpRedirectGuard(allowedAddresses: allowedAddresses)
        let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let session: URLSession = URLSession(configuration: configuration)
        defer {
            session.finishTasksAndInvalidate()
        }
        do {
            let (data, response): (Data, URLResponse) = try await session.data(from: address, delegate: guardian)
            guard let http = response as? HTTPURLResponse else {
                return .refused("no answer")
            }
            if http.statusCode != 200 {
                return .refused("answer \(http.statusCode)")
            }
            if !SetUpRedirectGuard.follows(http.url, allowedAddresses: allowedAddresses) {
                return .refused("answered from another host")
            }
            if data.isEmpty || data.count > 2_000_000 {
                return .refused("not a set-up")
            }
            return .script(data)
        } catch {
            return .refused("the download failed")
        }
    }
}

/// Follows a redirect only to an HTTPS address the recipe names, down to the
/// path.
nonisolated final class SetUpRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {

    // MARK: - Stored properties

    let allowedAddresses: [String]

    // MARK: - Initializer

    init(allowedAddresses: [String]) {
        self.allowedAddresses = allowedAddresses
    }

    // MARK: - Functions

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // The completion-handler form: the async form of this delegate
        // method crashed the Swift 6 compiler in SILGen (Xcode 27, measured
        // 2026-11-13).
        if SetUpRedirectGuard.follows(request.url, allowedAddresses: allowedAddresses) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }

    /// The rule, apart from a session, for a test.
    static func follows(_ address: URL?, allowedAddresses: [String]) -> Bool {
        guard let address, address.scheme == "https", address.host != nil else {
            return false
        }
        // Dot segments resolved first, so `/github/copilot-cli/../../x/`
        // is compared as the address it really names (fix review 8).
        let text: String = address.standardized.absoluteString
        for prefix in allowedAddresses where text.hasPrefix(prefix) {
            return true
        }
        return false
    }
}
