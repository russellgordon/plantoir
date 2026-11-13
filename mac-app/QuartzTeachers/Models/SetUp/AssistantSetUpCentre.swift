import Foundation
import Observation

/// The set-ups of outside assistants under way in this process, by the name a
/// teacher reads, for the quit question (#855, Russell 2026-11-13: quitting
/// part way through a set-up asks first). Process-wide and reset by the
/// tests that pin the quit rule, like `CourseActivity`'s records.
@MainActor
enum SetUpsUnderWay {

    // MARK: - Stored properties

    private(set) static var names: [String] = []

    // MARK: - Functions

    static func begin(_ name: String) {
        names.append(name)
    }

    static func end(_ name: String) {
        if let index = names.firstIndex(of: name) {
            names.remove(at: index)
        }
    }

    static func reset() {
        names = []
    }
}

/// Where a teacher opened the set-up from, for the trail (plan review L6).
nonisolated enum AssistantSetUpOpenedFrom: String, Sendable {
    case settings = "the Settings pane"
    case helpMenu = "the Help menu"
    case reviseWith = "Revise With"
}

/// What Settings ▸ Other Assistants shows and does (#855): one row per
/// assistant, each with what is true of it now and what can be done next.
///
/// Every decision is `AssistantSetUpState.decide`'s; this keeps the facts it
/// decides from (what the door finds, what the record says, what this
/// session has done) and runs the set-up, the sign-in window, the signed-in
/// question and Remove. Nothing here is offered or run unasked: a set-up
/// starts only from the confirmation's Download and Set Up, the signed-in
/// question is asked only after a set-up or a sign-in and on Check Again,
/// and Remove takes away only what the record says Plantoir added.
@Observable
@MainActor
final class AssistantSetUpCentre {

    // MARK: - Stored properties

    static let shared: AssistantSetUpCentre = AssistantSetUpCentre()

    /// Where the pane is about to be opened from, set by a menu item just
    /// before it opens Settings, read (and cleared) when the pane appears.
    /// Nil when the teacher chose the pane's tab themselves.
    static var pendingOpenedFrom: AssistantSetUpOpenedFrom?

    /// What the door finds, by key.
    private(set) var found: [String: Bool] = [:]
    /// What the record says, by key.
    private(set) var recorded: [String: SetUpRecordEntry.State] = [:]
    private(set) var activities: [String: AssistantSetUpState.Activity] = [:]
    private(set) var lastOutcomes: [String: SetUpOutcome] = [:]
    private(set) var signIns: [String: AssistantSetUpState.SignIn] = [:]
    private(set) var statuses: [String: AssistantSetUpState.Status] = [:]
    /// A Remove that could not take everything away, by key.
    private(set) var removalProblems: [String: Bool] = [:]

    @ObservationIgnored private var runners: [String: SetUpRunner] = [:]
    @ObservationIgnored var home: URL
    @ObservationIgnored var dependencies: SetUpDependencies
    /// Whether the door finds a program: the real search in the app.
    @ObservationIgnored var doorFinds: (String) -> Bool
    /// Hands a sign-in script to a window; LaunchServices in the app.
    @ObservationIgnored var openWindow: (String) -> Bool
    /// Where the sign-in scripts and their results go.
    @ObservationIgnored var windowFolder: () throws -> URL
    /// Told when a set-up or a Remove changes what the doors find.
    @ObservationIgnored var presenceChanged: () -> Void

    // MARK: - Initializer

    init(
        home: URL = RealHome.forFiles,
        dependencies: SetUpDependencies = .live,
        doorFinds: @escaping (String) -> Bool = AssistantSetUp.doorFindsIt,
        openWindow: @escaping (String) -> Bool = ClaudeCodeLauncher.launchTerminal,
        windowFolder: @escaping () throws -> URL = ClaudeCodeLauncher.supportDirectory,
        presenceChanged: @escaping () -> Void = { OutsideAssistantPresence.shared.refresh() }
    ) {
        self.home = home
        self.dependencies = dependencies
        self.doorFinds = doorFinds
        self.openWindow = openWindow
        self.windowFolder = windowFolder
        self.presenceChanged = presenceChanged
    }

    // MARK: - Functions

    /// Looks again at what the doors find and what the record says.
    func refresh() {
        var newFound: [String: Bool] = [:]
        var newRecorded: [String: SetUpRecordEntry.State] = [:]
        for agent in AssistantSetUp.agents {
            newFound[agent.key] = doorFinds(agent.key)
        }
        for entry in SetUpRecord.load(home: home) where entry.kind == AssistantSetUp.recordKind {
            newRecorded[entry.key] = entry.state
        }
        if newFound != found {
            found = newFound
        }
        if newRecorded != recorded {
            recorded = newRecorded
        }
    }

    /// The row's state for `agent`.
    func state(of agent: AssistantSetUpAgent) -> AssistantSetUpState {
        return AssistantSetUpState.decide(
            found: found[agent.key] ?? false,
            recorded: recorded[agent.key],
            activity: activities[agent.key] ?? .idle,
            lastOutcome: lastOutcomes[agent.key],
            signIn: signIns[agent.key] ?? .notAsked,
            status: statuses[agent.key] ?? .notAsked,
            hasSignedInCheck: agent.signedInCheckArguments != nil
        )
    }

    /// The sentence the row shows.
    func line(for agent: AssistantSetUpAgent) -> String {
        if removalProblems[agent.key] == true {
            return AssistantSetUpWording.filled(AssistantSetUpWording.removeIncomplete, for: agent)
        }
        return AssistantSetUpWording.filled(AssistantSetUpWording.line(for: state(of: agent)), for: agent)
    }

    /// Whether Remove is offered: only for a set-up the record holds.
    func canRemove(_ agent: AssistantSetUpAgent) -> Bool {
        return recorded[agent.key] != nil && (activities[agent.key] ?? .idle) == .idle
    }

    /// Notes where the set-up was opened from.
    static func noteOpened(from place: AssistantSetUpOpenedFrom) {
        ActivityTrail.note(.outsideAssistantSetUpOpened, AssistantSetUpCentre.openedLine(from: place))
    }

    static func openedLine(from place: AssistantSetUpOpenedFrom) -> String {
        return "opened setting up another assistant (from \(place.rawValue))"
    }

    /// Runs the maker's set-up: only ever called from the confirmation's
    /// Download and Set Up.
    func setUp(_ agent: AssistantSetUpAgent) {
        if activities[agent.key] == .downloading || activities[agent.key] == .checking {
            return
        }
        if found[agent.key] == true && recorded[agent.key] == nil {
            // The teacher's own copy: never set up over it.
            return
        }
        lastOutcomes[agent.key] = nil
        removalProblems[agent.key] = nil
        signIns[agent.key] = nil
        statuses[agent.key] = nil
        activities[agent.key] = .downloading
        let runner: SetUpRunner = SetUpRunner(
            recipe: agent.recipe, home: home, kind: AssistantSetUp.recordKind, dependencies: dependencies
        )
        runners[agent.key] = runner
        SetUpsUnderWay.begin(agent.displayName)
        ActivityTrail.note(.outsideAssistantSetUpStarted, "started setting up \(agent.displayName)")
        let started: Date = Date()
        let key: String = agent.key
        let reporter: SetUpProgressReporter = SetUpProgressReporter(centre: self)
        Task { @MainActor [weak self] in
            let outcome: SetUpOutcome = await runner.perform(progress: { (phase: SetUpPhase) in
                Task { @MainActor in
                    reporter.centre?.moved(key, to: phase)
                }
            })
            self?.finished(agent, outcome: outcome, started: started)
        }
    }

    func moved(_ key: String, to phase: SetUpPhase) {
        if activities[key] == nil || activities[key] == .idle {
            return
        }
        activities[key] = phase == .checking ? .checking : .downloading
    }

    /// What happens once a set-up has ended, however it ended.
    func finished(_ agent: AssistantSetUpAgent, outcome: SetUpOutcome, started: Date) {
        runners[agent.key] = nil
        SetUpsUnderWay.end(agent.displayName)
        activities[agent.key] = .idle
        lastOutcomes[agent.key] = outcome
        let seconds: Int = Int(Date().timeIntervalSince(started).rounded())
        ActivityTrail.note(
            outcome == .finished ? .outsideAssistantSetUpFinished : .outsideAssistantSetUpFailed,
            AssistantSetUpCentre.finishedLine(agent: agent, outcome: outcome, seconds: seconds)
        )
        refresh()
        presenceChanged()
        if outcome == .finished && agent.signedInCheckArguments != nil {
            // A returning teacher may already be signed in (sign-ins are
            // kept on Remove): asked once, here, from the set-up itself.
            askWhetherSignedIn(agent)
        }
    }

    /// The trail's line for a set-up that ended.
    static func finishedLine(agent: AssistantSetUpAgent, outcome: SetUpOutcome, seconds: Int) -> String {
        if outcome == .finished {
            return "set up \(agent.displayName): in place and made by \(agent.maker), in \(seconds) s"
        }
        return "could not set up \(agent.displayName): \(outcome.trailWords), in \(seconds) s"
    }

    /// Stops a set-up under way.
    func stop(_ agent: AssistantSetUpAgent) {
        runners[agent.key]?.stop()
    }

    /// The names of the assistants being set up, for the quit question.
    var namesBeingSetUp: [String] {
        return SetUpsUnderWay.names
    }

    /// Stops every set-up under way, at quit. The record of each stays
    /// `installing`, and the next launch settles it.
    func stopEverySetUp() {
        for runner in runners.values {
            runner.stop()
        }
    }

    /// Opens the maker's own sign-in in a window of its own: the same
    /// LaunchServices route the doors use, because each maker's sign-in may
    /// ask something in the window (Claude Code's code to paste back).
    func signIn(_ agent: AssistantSetUpAgent) {
        let program: String = home.appendingPathComponent(agent.programPath).path
        do {
            let folder: URL = try windowFolder()
            let resultURL: URL = AssistantSetUpCentre.signInResultURL(for: agent, in: folder)
            try? FileManager.default.removeItem(at: resultURL)
            let script: String = AssistantSetUpCentre.signInScript(agent: agent, program: program, resultPath: resultURL.path)
            let scriptURL: URL = folder.appendingPathComponent("sign-in-\(agent.key).command")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            statuses[agent.key] = nil
            if openWindow(scriptURL.path) {
                signIns[agent.key] = .windowOpen
                ActivityTrail.note(.outsideAssistantSignInOpened, "opened \(agent.displayName)’s sign-in window")
            }
        } catch {
            signIns[agent.key] = .finished(-1)
        }
    }

    /// Where the sign-in window writes its exit code.
    static func signInResultURL(for agent: AssistantSetUpAgent, in folder: URL) -> URL {
        return folder.appendingPathComponent("sign-in-\(agent.key).result")
    }

    /// The window's script: a plain line, the maker's own sign-in, its exit
    /// code (and nothing else) written for Plantoir to read, and a closing
    /// line (plan review L5).
    static func signInScript(agent: AssistantSetUpAgent, program: String, resultPath: String) -> String {
        var command: String = ClaudeCodeLauncher.escapeForShell(program)
        for argument in agent.signInArguments {
            command += " " + ClaudeCodeLauncher.escapeForShell(argument)
        }
        let intro: String = AssistantSetUpWording.filled(AssistantSetUpWording.signInWindowIntro, for: agent)
        return """
        #!/bin/bash
        echo \(ClaudeCodeLauncher.escapeForShell(intro))
        echo
        \(command)
        status=$?
        printf '%s\\n' "$status" > \(ClaudeCodeLauncher.escapeForShell(resultPath))
        echo
        echo \(ClaudeCodeLauncher.escapeForShell(AssistantSetUpWording.signInWindowDone))
        """
    }

    /// Check Again: reads what the sign-in window wrote, and for Claude Code
    /// and Codex asks the maker's own signed-in question.
    func checkAgain(_ agent: AssistantSetUpAgent) {
        refresh()
        if let folder = try? windowFolder() {
            let resultURL: URL = AssistantSetUpCentre.signInResultURL(for: agent, in: folder)
            if let text = try? String(contentsOf: resultURL, encoding: .utf8),
               let code = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                signIns[agent.key] = .finished(code)
            }
        }
        let signIn: AssistantSetUpState.SignIn = signIns[agent.key] ?? .notAsked
        if agent.signedInCheckArguments == nil {
            if case .finished(let code) = signIn {
                ActivityTrail.note(
                    .outsideAssistantSignInChecked,
                    AssistantSetUpCentre.checkedLine(agent: agent, signIn: signIn, statusCode: nil, signedIn: code == 0)
                )
            }
            return
        }
        if case .finished(let code) = signIn, code != 0 {
            ActivityTrail.note(
                .outsideAssistantSignInChecked,
                AssistantSetUpCentre.checkedLine(agent: agent, signIn: signIn, statusCode: nil, signedIn: false)
            )
            return
        }
        askWhetherSignedIn(agent)
    }

    /// Runs the maker's signed-in question and keeps its exit code only:
    /// never its output, which names the account.
    func askWhetherSignedIn(_ agent: AssistantSetUpAgent) {
        guard let arguments = agent.signedInCheckArguments else {
            return
        }
        let program: String = home.appendingPathComponent(agent.programPath).path
        let runner: SetUpRunner = SetUpRunner(
            recipe: agent.recipe, home: home, kind: AssistantSetUp.recordKind,
            dependencies: AssistantSetUpCentre.questionDependencies(from: dependencies)
        )
        let signIn: AssistantSetUpState.SignIn = signIns[agent.key] ?? .notAsked
        let homePath: String = home.path
        Task { @MainActor [weak self] in
            let code: Int32 = await AssistantSetUpCentre.exitCode(
                of: runner, program: program, arguments: arguments, homePath: homePath
            )
            let signedIn: Bool = code == agent.signedInExitCode
            self?.statuses[agent.key] = signedIn ? .signedIn : .notSignedIn
            ActivityTrail.note(
                .outsideAssistantSignInChecked,
                AssistantSetUpCentre.checkedLine(agent: agent, signIn: signIn, statusCode: code, signedIn: signedIn)
            )
        }
    }

    /// The signed-in question gets thirty seconds, not the set-up's half hour.
    nonisolated static func questionDependencies(from dependencies: SetUpDependencies) -> SetUpDependencies {
        var shorter: SetUpDependencies = dependencies
        shorter.longestRun = .seconds(30)
        return shorter
    }

    /// The question's exit code, off the main actor.
    @concurrent
    nonisolated static func exitCode(
        of runner: SetUpRunner,
        program: String,
        arguments: [String],
        homePath: String
    ) async -> Int32 {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-sign-in-check-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let environment: [String: String] = SetUpRunner.childEnvironment(
            home: homePath,
            user: runner.dependencies.userName,
            shell: runner.dependencies.accountShell,
            temporaryFolder: folder.path,
            extra: [:]
        )
        var every: [String] = [program]
        for argument in arguments {
            every.append(argument)
        }
        let ended: SetUpRunner.SetUpExit = await runner.run(
            executable: program, arguments: every, environment: environment, workingFolder: folder.path
        )
        switch ended {
        case .exited(let code):
            return code
        case .timedOut, .couldNotStart:
            return -1
        }
    }

    /// The trail's line for a sign-in checked: exit codes only.
    static func checkedLine(
        agent: AssistantSetUpAgent,
        signIn: AssistantSetUpState.SignIn,
        statusCode: Int32?,
        signedIn: Bool
    ) -> String {
        var line: String = "checked \(agent.displayName)’s sign-in: "
        if let statusCode {
            line += signedIn ? "signed in" : "not confirmed (the check answered \(statusCode))"
        } else if case .finished(let code) = signIn {
            line += code == 0 ? "the sign-in finished" : "not confirmed (the sign-in ended with \(code))"
        } else {
            line += "not confirmed"
        }
        return line
    }

    /// Takes away what the record says Plantoir's set-up added, and nothing
    /// else, then forgets it.
    func remove(_ agent: AssistantSetUpAgent) {
        guard let entry = SetUpRecord.entry(for: agent.key, home: home) else {
            return
        }
        let removal: SetUpRemoval = SetUpRecord.takeAway(entry, recipe: agent.recipe, home: home)
        if removal.finishedCleanly {
            try? SetUpRecord.forget(agent.key, home: home)
            removalProblems[agent.key] = nil
        } else {
            removalProblems[agent.key] = true
        }
        ActivityTrail.note(.outsideAssistantRemoved, AssistantSetUpCentre.removedLine(agent: agent, removal: removal))
        lastOutcomes[agent.key] = nil
        signIns[agent.key] = nil
        statuses[agent.key] = nil
        refresh()
        presenceChanged()
    }

    /// The trail's line for a Remove: counts only.
    static func removedLine(agent: AssistantSetUpAgent, removal: SetUpRemoval) -> String {
        var line: String = "removed the copy of \(agent.displayName) Plantoir set up "
        line += "(\(removal.removedPaths + removal.removedFolders) items, \(removal.profileBlocksRemoved) start-up blocks"
        if removal.profileBlocksNotFound > 0 {
            line += ", \(removal.profileBlocksNotFound) left because the teacher had changed them"
        }
        if !removal.finishedCleanly {
            line += ", not everything could be taken away"
        }
        return line + ")"
    }

    /// At launch: a set-up the record still calls `installing` was cut short
    /// by a quit, a crash or a power cut. If what it needed is there and is
    /// the maker's, the record is completed; otherwise what it added is
    /// taken away and the record forgotten. Off the main actor for the
    /// signature check, and only when such a record exists.
    func settleInterruptedSetUps() async {
        let entries: [SetUpRecordEntry] = SetUpRecord.load(home: home)
        for entry in entries where entry.state == .installing && entry.kind == AssistantSetUp.recordKind {
            guard let agent = AssistantSetUp.agent(forKey: entry.key) else {
                continue
            }
            let finishedNow: Bool = await AssistantSetUpCentre.settle(
                entry, recipe: agent.recipe, home: home, dependencies: dependencies
            )
            ActivityTrail.note(
                .outsideAssistantSetUpSettled,
                AssistantSetUpCentre.settledLine(agent: agent, finished: finishedNow)
            )
        }
        refresh()
        presenceChanged()
    }

    static func settledLine(agent: AssistantSetUpAgent, finished: Bool) -> String {
        if finished {
            return "finished a set-up of \(agent.displayName) that was cut short: it was in place and made by \(agent.maker)"
        }
        return "finished a set-up of \(agent.displayName) that was cut short: it was not complete, and what it had added was taken away"
    }

    /// One interrupted entry, settled. True when it is now a finished set-up.
    @concurrent
    nonisolated static func settle(
        _ entry: SetUpRecordEntry,
        recipe: SetUpRecipe,
        home: URL,
        dependencies: SetUpDependencies
    ) async -> Bool {
        guard let before = entry.before else {
            try? SetUpRecord.forget(entry.key, home: home)
            return false
        }
        let changes = SetUpRecord.changes(of: recipe, since: before, home: home)
        let thisRun: SetUpRecordEntry = SetUpRecordEntry(
            key: entry.key, kind: entry.kind, state: .installed, started: entry.started, finished: Date(), before: nil,
            created: changes.created, createdFolders: changes.createdFolders,
            profileChanges: changes.profileChanges, changedInPlace: changes.changedInPlace
        )
        let checker: SetUpRunner = SetUpRunner(recipe: recipe, home: home, kind: entry.kind, dependencies: dependencies)
        // What an earlier, finished set-up recorded is kept in the entry's
        // lists, as `SetUpRunner.perform` wrote them.
        let previous: SetUpRecordEntry? = entry.created.isEmpty && entry.profileChanges.isEmpty
            ? nil
            : SetUpRecordEntry(
                key: entry.key, kind: entry.kind, state: .installed, started: entry.started, finished: nil,
                before: nil, created: entry.created, createdFolders: entry.createdFolders,
                profileChanges: entry.profileChanges, changedInPlace: entry.changedInPlace
            )
        if checker.checkPrograms() == .finished {
            try? SetUpRecord.store(SetUpRunner.merging(thisRun, into: previous), home: home)
            return true
        }
        _ = SetUpRecord.takeAway(thisRun, recipe: recipe, home: home)
        if let previous {
            try? SetUpRecord.store(previous, home: home)
        } else {
            try? SetUpRecord.forget(entry.key, home: home)
        }
        return false
    }
}

/// Carries the centre to the set-up's progress, weakly, across the hop off
/// and back onto the main actor.
final class SetUpProgressReporter: Sendable {

    // MARK: - Stored properties

    weak let centre: AssistantSetUpCentre?

    // MARK: - Initializer

    init(centre: AssistantSetUpCentre) {
        self.centre = centre
    }
}
