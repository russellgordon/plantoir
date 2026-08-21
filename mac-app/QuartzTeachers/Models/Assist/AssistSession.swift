import Foundation
import Observation

/// One assistant window's worth of everything: the hardware decision, the
/// weights, the server, and the conversation.
@Observable
@MainActor
final class AssistSession {

    // MARK: - Types

    /// What stands between the teacher and a conversation, if anything.
    enum Readiness: Equatable {
        case checkingHardware
        case unsupported(reason: String)
        case needsDownload(tier: AssistModelTier)
        case downloading(fractionComplete: Double, receivedBytes: Int64, totalBytes: Int64)
        case starting
        case ready
        case failed(reason: String)
    }

    /// A restore, as the transcript records it.
    ///
    /// It is kept here rather than in `AssistAgent.entries` because a restore
    /// is not something either side of the conversation SAID — the model is
    /// never told about it, and should not be: it is the teacher stepping
    /// outside the conversation to undo it. `saidSoFar` is what puts the note
    /// back where it happened when the window lays the two together.
    struct RestoreNote: Identifiable, Equatable {
        let id: UUID = UUID()
        let text: String
        let isProblem: Bool

        /// How many lines the conversation had run to when this happened.
        let saidSoFar: Int
    }

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let workingFolder: URL

    /// What this Mac is allowed to give the assistant.
    let budget: AssistHardwareBudget

    /// The weights this window will use — the teacher's choice applied to
    /// this Mac, not simply what the Mac would have picked.
    let store: AssistModelStore

    /// The conversation, once there is something to have it with.
    private(set) var agent: AssistAgent?

    /// What the conversation can do, kept here as well as handed to the agent:
    /// the copy it saves before its first change is what a Restore goes back
    /// to, and the window has to be able to ask whether there is one.
    private(set) var toolRunner: AssistToolRunner?

    /// The restores done during this conversation, oldest first.
    private(set) var restoreNotes: [RestoreNote] = []

    /// Where the window is up to.
    private(set) var readiness: Readiness = .checkingHardware

    /// The engine.
    private var host: AssistServerHost?

    /// Whether the download in flight was started from THIS window.
    ///
    /// It decides what closing the window does. Cancelling on close is
    /// deliberate — a teacher who shuts the window has finished, and leaving
    /// gigabytes coming down behind their back is not a kindness. But since
    /// the stores became shared (`AssistModelStores`), the download this
    /// window can see may have been started in Settings, where the whole point
    /// was to fetch it ahead of time and get on with something else. Closing a
    /// window that merely WATCHED must not cancel that.
    private var startedTheDownload: Bool = false

    /// Whether the priming request has come BACK.
    ///
    /// Not whether it was sent — the distinction is the whole point. The
    /// window announces itself ready as soon as the engine answers `/health`,
    /// which is several seconds before the ~3,400-token warm-up has finished
    /// reading the tool definitions, and the engine serves one request at a
    /// time (`--parallel 1`). A first question sent into that gap does not go
    /// faster for having been sent early: it queues behind the warm-up on the
    /// server's single slot. Measured on an M-series Mac, 48 GB, the small
    /// assistant, the same question twice: **1.7 s** asked after the warm-up
    /// had returned, **3.1 s** asked the instant the field enabled.
    ///
    /// So the turn waits for this instead of racing it — see `canSend`.
    private(set) var hasFinishedWarmUp: Bool = false

    /// Everything waiting for the warm-up to come back.
    ///
    /// A teacher who presses Return during those few seconds must not have
    /// the keystroke swallowed — "a key that silently does nothing reads as a
    /// dropped keystroke" is already the rule the composer's arrow keys
    /// follow, and it applies just as much here. `waitUntilWarmedUp()` parks
    /// them here and they are resumed together the moment the warm-up ends.
    private var warmUpWaiters: [CheckedContinuation<Void, Never>] = []

    /// How many of the engine's own lines this conversation has put on the
    /// trail, against the cap below.
    private var engineLinesRecorded: Int = 0

    /// The loop that looks in on the engine's log while the window is open.
    private var engineWatch: Task<Void, Never>?

    // MARK: - Computed properties

    /// The model this window is running.
    ///
    /// Reads it off the STORE rather than recomputing it from the budget. The
    /// teacher can change the setting while a window is open, and a window
    /// that then described a different assistant than the one it had loaded
    /// would be lying about the very thing the setting exists to make visible.
    /// A window keeps the assistant it opened with; the next one picks up the
    /// change.
    var tier: AssistModelTier {
        return store.tier
    }

    /// Whether the teacher can type.
    ///
    /// True while the assistant is working, deliberately. Disabling the box
    /// mid-conversation does two unhelpful things: it takes the keyboard away
    /// — macOS moves focus to the next thing it can find, which was the first
    /// disclosure group in the shelf — and it stops a teacher writing their
    /// next message while they wait, which every messaging app they have ever
    /// used allows.
    ///
    /// What must not happen while it is busy is SENDING, and that is guarded
    /// separately by `canSend`.
    var canAcceptTyping: Bool {
        return readiness == .ready
    }

    /// Whether what is typed can be sent right now.
    ///
    /// The assistant runs one thing at a time — a second request arriving
    /// mid-run would interleave with the tool calls of the first — so the
    /// send waits even though the typing does not.
    var canSend: Bool {
        guard readiness == .ready, hasFinishedWarmUp, let agent else {
            return false
        }
        return !agent.isBusy
    }

    /// The gap between the window saying it is ready and the warm-up coming
    /// back — the only time `canSend` is false while `canAcceptTyping` is
    /// true, and the reason the send button shows a spinner rather than
    /// simply being dimmed for no visible reason.
    var isWarmingUp: Bool {
        return readiness == .ready && !hasFinishedWarmUp
    }

    /// Whether there is a way back to how this section was when the
    /// conversation started.
    ///
    /// False for a conversation that has only READ, which has saved no copy —
    /// and offering a Restore there would be offering to undo nothing.
    var canRestoreSection: Bool {
        guard let toolRunner else {
            return false
        }
        return toolRunner.hasConversationBackup
    }

    /// Where this window's courses live.
    var coursesDirectoryURL: URL {
        return workingFolder.appendingPathComponent("courses")
    }

    // MARK: - Initializer

    init(courseCode: String, sectionNumber: Int, workingFolder: URL) {
        self.courseCode = courseCode
        self.sectionNumber = sectionNumber
        self.workingFolder = workingFolder
        let budget: AssistHardwareBudget = AssistHardwareBudget.current()
        self.budget = budget
        let choice: AssistModelChoice = AppSettings.shared.assistantModelChoice
        self.store = AssistModelStores.store(for: choice.resolved(for: budget))
    }

    // MARK: - Functions

    /// The teacher pressed Download in this window.
    ///
    /// Goes through the session rather than straight to the store so that the
    /// window knows it owns this download — see `startedTheDownload`.
    func beginDownload() {
        startedTheDownload = true
        store.download()
    }

    /// The teacher pressed Stop in this window.
    ///
    /// An explicit stop is honoured wherever the download came from: they are
    /// looking at it and asking for it to end.
    func stopDownload() {
        startedTheDownload = false
        store.cancel()
    }

    /// Work out what this window can offer, and get as far towards a
    /// conversation as it can without asking the teacher anything.
    func prepare() async {
        // Claimed as the window opens, not when the engine is ready. A
        // teacher three minutes into a download has the assistant open as
        // far as they are concerned, and a second window started meanwhile
        // is exactly what this prevents.
        AssistActivity.begin(
            folderPath: workingFolder.path,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )

        guard budget.canRunAssistant else {
            readiness = .unsupported(reason:
                "The assistant needs an Apple silicon Mac. Everything else in Plantoir works as usual."
            )
            return
        }

        if !store.isReady {
            readiness = .needsDownload(tier: tier)
            await followDownload()
            if !store.isReady {
                return
            }
        }

        await startEngine()
    }

    /// Watch the download until it finishes or fails, mirroring its progress
    /// into this window's own state.
    ///
    /// The cancellation check is load-bearing. `try? await Task.sleep`
    /// swallows the cancellation error, so without it this loop keeps
    /// spinning every 200 ms after the window has closed — the enclosing
    /// `.task` is cancelled, nobody is watching, and the loop runs until the
    /// app quits.
    private func followDownload() async {
        while !Task.isCancelled {
            switch store.state {
            case .ready:
                return
            case .failed(let reason):
                readiness = .failed(reason: reason)
                return
            case .downloading(let fraction, let received, let total):
                readiness = .downloading(fractionComplete: fraction, receivedBytes: received, totalBytes: total)
            case .missing:
                // Waiting for the teacher to press the button.
                if case .downloading = readiness {
                    readiness = .needsDownload(tier: tier)
                }
            }
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
        }
    }

    /// Start the server and build the agent.
    private func startEngine() async {
        readiness = .starting
        let startedAt: Date = Date()
        ActivityTrail.note(
            .assistantOpened,
            "opened the assistant (" + tier.displayName + ")",
            course: courseCode, section: sectionNumber
        )

        let host: AssistServerHost = AssistServerHost(modelURL: store.fileURL, budget: budget, tier: tier)
        self.host = host
        await host.start()

        switch host.state {
        case .ready:
            guard let baseURL = host.baseURL else {
                readiness = .failed(reason: "The assistant's engine started but gave no address.")
                finishWarmUp()
                return
            }
            ActivityTrail.note(
                .assistantReady,
                String(format: "the assistant was ready after %.1fs", Date().timeIntervalSince(startedAt)),
                course: courseCode, section: sectionNumber
            )
            await beginConversation(baseURL: baseURL)

        case .failed(let reason):
            readiness = .failed(reason: reason)
            finishWarmUp()
            ActivityTrail.note(
                .assistantWouldNotStart,
                "the assistant would not start — " + reason,
                course: courseCode, section: sectionNumber
            )
            recordWhatTheEngineSaid(keepingEverything: true)

        case .stopped, .starting:
            readiness = .failed(reason: "The assistant's engine did not become ready.")
            finishWarmUp()
            ActivityTrail.note(
                .assistantWouldNotStart,
                "the assistant did not become ready",
                course: courseCode, section: sectionNumber
            )
            recordWhatTheEngineSaid(keepingEverything: true)
        }
    }

    /// Build the conversation on an engine that is already answering, say so,
    /// and prime it — in that order, with the first turn held until the
    /// priming request has come back.
    ///
    /// **Split out of `startEngine()` because the ORDER is the behaviour.**
    /// `startEngine()` cannot be driven by a test without spawning a real
    /// `llama-server`, so the one thing worth pinning here — that a turn
    /// cannot start before the warm-up returns — would have been untestable
    /// where it lives. This takes an address instead of making one, so a test
    /// can hand it a stubbed endpoint that holds its answer and watch
    /// `canSend` stay false while it does.
    func beginConversation(baseURL: URL) async {
        // The assistant window is its own window, so it gets its own
        // workspace pointed at the same folder rather than reaching into
        // the main window's. The tools take the course and section as
        // arguments — the same shape the MCP server uses — so the runner
        // needs the folder, not this window's particular section.
        let workspace: WorkspaceModel = WorkspaceModel()
        workspace.adoptRestoredPath(workingFolder.path)
        let runner: AssistToolRunner = AssistToolRunner(workspace: workspace)
        self.toolRunner = runner
        let agent: AssistAgent = AssistAgent(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            client: AssistModelClient(baseURL: baseURL),
            tools: runner,
            planMode: AssistPlanMode(tier: tier)
        )
        self.agent = agent
        // Ready enough to TYPE into, deliberately, and not yet ready to send
        // from: the box has to accept the keyboard while the warm-up runs or
        // a teacher spends those seconds unable to start writing.
        readiness = .ready
        watchWhatTheEngineSays()
        await warmUp(client: AssistModelClient(baseURL: baseURL), runner: runner)
    }

    /// Wait until the priming request has come back. Returns at once once it
    /// has, so a caller never has to ask first.
    func waitUntilWarmedUp() async {
        if hasFinishedWarmUp {
            return
        }
        await withCheckedContinuation { continuation in
            warmUpWaiters.append(continuation)
        }
    }

    /// The warm-up is over — whether it answered, failed, or never ran.
    ///
    /// Called on every path out of starting up, including the failures.
    /// A window that gave up on its engine still has to release anybody
    /// waiting on this, or a Return pressed a moment earlier waits forever.
    private func finishWarmUp() {
        if hasFinishedWarmUp {
            return
        }
        hasFinishedWarmUp = true
        let waiting: [CheckedContinuation<Void, Never>] = warmUpWaiters
        warmUpWaiters = []
        for continuation in waiting {
            continuation.resume()
        }
    }

    /// Read the tool definitions once, before the teacher has typed anything.
    ///
    /// The prompt is mostly tool schemas — about 3,400 tokens — and reading it
    /// is a one-off cost per conversation. On the small model that is two
    /// seconds and on the large one about twelve; either way it is time the
    /// teacher would otherwise spend watching their first message sit there.
    /// Doing it while they are still reading the promise card and deciding
    /// what to type makes it free.
    ///
    /// Its FAILURE is fire-and-forget: if the priming request comes back an
    /// error, the first real message simply pays the cost itself, which is
    /// exactly what would have happened anyway. Nothing is shown to the
    /// teacher either way.
    ///
    /// Its TIMING is not. The first turn waits for this to return — see
    /// `hasFinishedWarmUp` — so `finishWarmUp()` runs on the way out however
    /// this ends, which is why it is in a `defer` rather than at the bottom.
    private func warmUp(client: AssistModelClient, runner: AssistToolRunner) async {
        defer { finishWarmUp() }
        var definitions: [AssistToolDefinition] = []
        for definition in runner.definitions {
            definitions.append(definition.namingTheRealCourse(courseCode))
        }
        let priming: [AssistMessage] = [
            AssistMessage.system(AssistAgent.systemPrompt(course: courseCode, section: sectionNumber)),
            AssistMessage.user("Say only: ready"),
        ]
        _ = try? await client.respond(messages: priming, tools: definitions)
    }

    // MARK: - What the engine itself said

    /// The most of the engine's own chatter one conversation may put on the
    /// trail.
    ///
    /// The trail is deliberately coarse — it is a record of what the TEACHER
    /// did, and its failure mode is that the one line that mattered ends up
    /// on page forty. A cap is what keeps a chatty engine from being that
    /// page forty. Twelve is enough for a model that will not load (the
    /// reason is in the last handful of lines) and nowhere near enough to
    /// bury a morning's work.
    private static let mostEngineLinesOnTheTrail: Int = 12

    /// How often to look in on the engine while the window is open.
    ///
    /// A poll rather than a reader, and that is the whole safety property:
    /// nothing reads on the ENGINE's timetable, so the engine can never block
    /// waiting for us. Fifteen seconds because the thing being caught — a
    /// context overflow, a slot error — is being read minutes or days later
    /// in a report, and the only deadline is "before the teacher sends it".
    private static let engineWatchInterval: Duration = .seconds(15)

    /// Look in on the engine every so often, so a report made while the
    /// window is still open carries what it said.
    ///
    /// Sampling only at teardown would have been simpler and would have
    /// missed the case this exists for: a teacher whose assistant is
    /// misbehaving RIGHT NOW, filing a report without closing anything.
    ///
    /// The loop ends itself once the cap is reached, so a badly behaved
    /// engine costs a fixed amount of work rather than a permanent one.
    private func watchWhatTheEngineSays() {
        engineWatch?.cancel()
        engineWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                self.recordWhatTheEngineSaid(keepingEverything: false)
                if self.engineLinesRecorded >= AssistSession.mostEngineLinesOnTheTrail {
                    return
                }
                do {
                    try await Task.sleep(for: AssistSession.engineWatchInterval)
                } catch {
                    return
                }
            }
        }
    }

    /// Put what the engine has said since the last look onto the trail.
    ///
    /// `keepingEverything` is for the one case where the ordinary filter is
    /// wrong: an engine that never became ready. There, every line is the
    /// diagnosis — including the perfectly ordinary ones it got through
    /// before it stopped.
    private func recordWhatTheEngineSaid(keepingEverything: Bool) {
        guard let host else {
            return
        }
        var worthKeeping: [String] = []
        for line in host.engineLinesSinceLastLook() {
            if keepingEverything || AssistSession.readsLikeATrouble(line) {
                worthKeeping.append(line)
            }
        }
        // The LAST few, not the first: when an engine gives up, the reason is
        // at the bottom of what it wrote.
        var index: Int = max(0, worthKeeping.count - AssistSession.mostEngineLinesOnTheTrail)
        while index < worthKeeping.count {
            if engineLinesRecorded >= AssistSession.mostEngineLinesOnTheTrail {
                return
            }
            engineLinesRecorded += 1
            ActivityTrail.note(
                .assistantEngineSaid,
                "the assistant's engine said: " + AssistSession.shortened(worthKeeping[index]),
                course: courseCode, section: sectionNumber
            )
            index += 1
        }
    }

    /// Whether a line the engine wrote is worth a teacher's trail.
    ///
    /// **Measured against a real engine rather than guessed** (llama.cpp
    /// build b10435, 2026-08-20). Its lines carry a severity letter as their
    /// second field — `0.46.018.667 E srv send_error: …` — so `E` is the
    /// signal to key off. Warnings deliberately are NOT: a perfectly healthy
    /// start prints six of them, five being a CORS block that cannot matter
    /// on a server bound to 127.0.0.1 with no key, and one a token-type
    /// quirk in the weights. Recording those would spend the whole budget on
    /// noise before the teacher had asked anything.
    ///
    /// The word test beside it is the belt to that braces: the severity field
    /// is this build's format and a future build could drop it, while a line
    /// naming an error or an exception says so in any format. It is what
    /// catches `W srv operator(): got exception: …`, a warning that is
    /// genuinely worth having.
    static func readsLikeATrouble(_ line: String) -> Bool {
        var firstTwoFields: [Substring] = []
        for field in line.split(separator: " ", omittingEmptySubsequences: true) {
            firstTwoFields.append(field)
            if firstTwoFields.count == 2 {
                break
            }
        }
        if firstTwoFields.count == 2 && firstTwoFields[1] == "E" {
            return true
        }
        let lowered: String = line.lowercased()
        for word in ["error", "exception", "failed", "failure"] {
            if lowered.contains(word) {
                return true
            }
        }
        return false
    }

    /// One line, cut to something a trail can hold.
    static func shortened(_ line: String, to longest: Int = 200) -> String {
        if line.count <= longest {
            return line
        }
        return String(line.prefix(longest)) + "…"
    }

    /// Put this section back to how it was when the conversation started, and
    /// record in the transcript that it happened.
    ///
    /// The teacher has already been asked — see
    /// `AssistSectionRestore.confirmationMessage` — so this does not ask
    /// again. What it does do is write down the outcome either way: a restore
    /// that quietly failed would leave a teacher believing their section had
    /// gone back when it had not.
    func restoreSection() {
        let saidSoFar: Int = agent?.entries.count ?? 0
        do {
            try AssistSectionRestore.restore(
                backupURL: toolRunner?.conversationBackupURL,
                courseCode: courseCode,
                sectionNumber: sectionNumber,
                coursesDirectoryURL: coursesDirectoryURL
            )
        } catch {
            restoreNotes.append(RestoreNote(
                text: "Nothing was put back: \(error.localizedDescription)",
                isProblem: true,
                saidSoFar: saidSoFar
            ))
            return
        }
        restoreNotes.append(RestoreNote(
            text: AssistSectionRestore.doneMessage(
                courseCode: courseCode, sectionNumber: sectionNumber
            ),
            isProblem: false,
            saidSoFar: saidSoFar
        ))
    }

    /// The window is closing. Stop the server — a model holding several
    /// gigabytes of a teacher's RAM after they have finished with it is the
    /// sort of thing that gets an app uninstalled.
    func finish() {
        if startedTheDownload {
            store.cancel()
        }
        // Anybody still parked on the warm-up is let go here rather than left
        // waiting on a window that has gone. `canSend` is false from this
        // point on regardless, so nothing they were waiting to do can happen.
        finishWarmUp()
        engineWatch?.cancel()
        engineWatch = nil
        // The last look comes BEFORE the log is thrown away, and `stop()`
        // deliberately leaves the file behind so this order is possible.
        recordWhatTheEngineSaid(keepingEverything: false)
        host?.stop()
        host?.discardEngineLog()
        host = nil
        agent = nil
        toolRunner = nil
        // Released unconditionally: if this does not run, the feature stays
        // locked out until the app restarts — a far worse failure than
        // briefly allowing a second window.
        AssistActivity.end(
            folderPath: workingFolder.path,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
    }
}
