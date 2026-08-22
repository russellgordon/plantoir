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
        guard readiness == .ready, let agent else {
            return false
        }
        return !agent.isBusy
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
    ///
    /// `openMainWindow` comes from `AssistWindowView`'s own `@Environment
    /// (\.openWindow)` — the one capability only the local in-app assistant
    /// has, letting a deploy or preview it starts put the section on screen
    /// itself rather than running silently. See `AssistToolRunner.
    /// revealSectionOnScreen`.
    func prepare(openMainWindow: @escaping @MainActor () -> Void) async {
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

        await startEngine(openMainWindow: openMainWindow)
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
    private func startEngine(openMainWindow: @escaping @MainActor () -> Void) async {
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
                return
            }
            // The assistant window is its own window, so it gets its own
            // workspace pointed at the same folder rather than reaching into
            // the main window's. The tools take the course and section as
            // arguments — the same shape the MCP server uses — so the runner
            // needs the folder, not this window's particular section.
            let workspace: WorkspaceModel = WorkspaceModel()
            workspace.adoptRestoredPath(workingFolder.path)
            let runner: AssistToolRunner = AssistToolRunner(
                workspace: workspace, openMainWindow: openMainWindow
            )
            self.toolRunner = runner
            let agent: AssistAgent = AssistAgent(
                courseCode: courseCode,
                sectionNumber: sectionNumber,
                client: AssistModelClient(baseURL: baseURL),
                tools: runner,
                planMode: AssistPlanMode(tier: tier)
            )
            self.agent = agent
            readiness = .ready
            ActivityTrail.note(
                .assistantReady,
                String(format: "the assistant was ready after %.1fs", Date().timeIntervalSince(startedAt)),
                course: courseCode, section: sectionNumber
            )
            await warmUp(client: AssistModelClient(baseURL: baseURL), runner: runner)

        case .failed(let reason):
            readiness = .failed(reason: reason)
            ActivityTrail.note(
                .assistantWouldNotStart,
                "the assistant would not start — " + reason,
                course: courseCode, section: sectionNumber
            )

        case .stopped, .starting:
            readiness = .failed(reason: "The assistant's engine did not become ready.")
            ActivityTrail.note(
                .assistantWouldNotStart,
                "the assistant did not become ready",
                course: courseCode, section: sectionNumber
            )
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
    /// It is deliberately fire-and-forget: if it fails, the first real message
    /// simply pays the cost itself, which is exactly what would have happened
    /// anyway. Nothing is shown to the teacher either way.
    private func warmUp(client: AssistModelClient, runner: AssistToolRunner) async {
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
        host?.stop()
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
