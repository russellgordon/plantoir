import Foundation

/// Where each working folder's copy of the app's tools stands (#476 — the
/// mac's half of Windows' #473): not started, being copied, ready, or failed.
///
/// **The one record of a folder's toolchain state.** Until #476 there were
/// two process-wide sets keyed by the folder's typed path (fresh, and —
/// briefly — failed) and the copy ran synchronously on the main actor inside
/// `reloadCourses()`, holding the window back for 0.9–3.9 s on an M4 Pro
/// (measured, `documentation/09-mac-app.md`) and for two minutes on the
/// Windows PC that raised it. Now one entry per folder, keyed the way every
/// other per-folder fact is (`FolderIdentity.canonicalPath`, #189), holds
/// the state AND the running copy, so two windows on the same folder share
/// one copy and one answer, and the window reads it to grey Preview, Deploy
/// and New Course and to show its banner while the copy runs off the main
/// actor.
///
/// **What this registry cannot see** is another PROCESS copying into the
/// same folder — `Plantoir --mcp-stdio` runs its own copy, and so does a
/// second copy of the app. Windows wrote a `toolchain-copying.<pid>` marker
/// for that; the mac does not, on purpose: every file is written atomically
/// from the same bundle, so two copies at once write the same bytes and the
/// worse outcome is wasted work, not a broken recipe.
@MainActor
@Observable
final class ToolchainReadiness {

    // MARK: - Types

    /// What a folder's copy is doing.
    enum State: Equatable {
        /// No copy has been asked for in this run of the app.
        case notStarted
        /// The copy is running. `hasWritten` turns true at the first file it
        /// writes or removes — the banner's cue — and stays false for the
        /// ordinary launch that compares every file and changes nothing.
        case copying(hasWritten: Bool)
        /// The last copy finished with nothing failed — the old "fresh".
        case ready
        /// The last copy could not finish; `message` is what a teacher reads
        /// (`ToolchainReadinessWording.couldNotGetReady`), kept until File ▸
        /// Reload Courses or a newly pointed window tries again.
        case failed(message: String)
    }

    // MARK: - Stored properties

    /// The one registry, process-wide.
    static let shared: ToolchainReadiness = ToolchainReadiness()

    /// Each folder's state, by canonical path. Observed by the views.
    private(set) var states: [String: State] = [:]

    /// The running copy per folder, for whoever must wait for it.
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    // MARK: - Computed properties

    /// Whether any folder's copy is running — asked at quit, which waits.
    var anyCopyIsRunning: Bool {
        return !tasks.isEmpty
    }

    // MARK: - Functions: reading

    /// The folder's state — `notStarted` for one nobody has asked about.
    func state(of workspaceURL: URL) -> State {
        return states[FolderIdentity.canonicalPath(workspaceURL.path)] ?? .notStarted
    }

    /// Whether Preview, Deploy and New Course must wait: a copy under way,
    /// or one that failed and has not been retried.
    func isGettingReady(_ workspaceURL: URL) -> Bool {
        return reasonToWait(workspaceURL) != nil
    }

    /// The sentence to refuse with, or nil when nothing stands in the way.
    func reasonToWait(_ workspaceURL: URL) -> String? {
        switch state(of: workspaceURL) {
        case .copying:
            return ToolchainReadinessWording.gettingReadyMessage
        case .failed(let message):
            return message
        case .notStarted, .ready:
            return nil
        }
    }

    /// Whether the banner is shown: a copy that has started WRITING, or a
    /// failure. Not a timer (the plan review's finding 9): the ordinary
    /// launch compares every file for most of a second and writes nothing,
    /// so a banner on a clock would flash on every launch on a slower Mac,
    /// while a copy after an update writes within its first moments.
    nonisolated static func showsBanner(for state: State) -> Bool {
        switch state {
        case .copying(let hasWritten):
            return hasWritten
        case .failed:
            return true
        case .notStarted, .ready:
            return false
        }
    }

    // MARK: - Functions: the copy

    /// Brings the folder's `.toolchain/` up to date if it needs it, OFF the
    /// main actor, and answers the running copy so a caller that must not
    /// start before it ends (the assistant's server, a headless rebuild or
    /// deploy, the quit) can wait. Nil when there is nothing to do.
    ///
    /// `synchronously` keeps the old behaviour — the copy on the calling
    /// thread, the state settled when this returns — for the tests, which
    /// assert what lands on disk and would otherwise race a detached task
    /// writing into a folder they are deleting; and for a folder being set
    /// up by the synchronous `initializeWorkspace()`, which exists for them.
    @discardableResult
    func ensure(_ workspaceURL: URL, synchronously: Bool = WorkspaceModel.isRunningTests) -> Task<Void, Never>? {
        let key: String = FolderIdentity.canonicalPath(workspaceURL.path)
        if let running = tasks[key] {
            return running
        }
        if !WorkspaceModel.shouldMirrorToolchain(into: workspaceURL) {
            return nil
        }
        states[key] = .copying(hasWritten: false)
        let startedAt: Date = Date()
        if synchronously {
            let outcome: WorkspaceModel.MirrorOutcome = WorkspaceModel.copyToolchainFiles(into: workspaceURL)
            apply(outcome, to: workspaceURL, startedAt: startedAt)
            return nil
        }
        let task: Task<Void, Never> = Task.detached(priority: .userInitiated) {
            let outcome: WorkspaceModel.MirrorOutcome = WorkspaceModel.copyToolchainFiles(
                into: workspaceURL,
                firstChange: {
                    Task { @MainActor in
                        ToolchainReadiness.shared.noteWriting(workspaceURL)
                    }
                }
            )
            await MainActor.run {
                ToolchainReadiness.shared.apply(outcome, to: workspaceURL, startedAt: startedAt)
            }
        }
        tasks[key] = task
        return task
    }

    /// Waits for the folder's copy, if one is running. The app's own robots
    /// — the assistant's server, a headless rebuild or deploy — wait here
    /// instead of being refused by `ScriptRunner`'s backstop for a copy the
    /// app itself started (Windows' rule under #473).
    func waitUntilReady(_ workspaceURL: URL) async {
        // A copy that FAILED is tried again here when this process has no
        // File menu to retry it from — the assistant's server — so a client
        // is not refused for ever with a sentence that names a menu it
        // cannot see. A window's robots leave the failure to the menu.
        if AssistMCPServer.isServing, case .failed = state(of: workspaceURL) {
            forgetFailure(workspaceURL)
            ensure(workspaceURL)
        }
        if let running = tasks[FolderIdentity.canonicalPath(workspaceURL.path)] {
            await running.value
        }
    }

    /// Waits for every running copy — the quit path (#476): a copy killed
    /// part-way leaves a recipe half old and half new for a scheduled run or
    /// a command-line launcher to hash and build from.
    func waitForAllCopies() async {
        for running in Array(tasks.values) {
            await running.value
        }
    }

    /// Forgets a FAILURE, so the next mirror can try again: a window newly
    /// pointed at the folder, and File ▸ Reload Courses. A folder that is
    /// ready or copying is left alone — the routine reloads must not start
    /// the compare again (0.9 s even with nothing to do), which is what the
    /// once-per-run rule has protected since row 279.
    func forgetFailure(_ workspaceURL: URL) {
        let key: String = FolderIdentity.canonicalPath(workspaceURL.path)
        if case .failed = states[key] {
            states.removeValue(forKey: key)
        }
    }

    /// A folder being set up from nothing has no toolchain yet, whatever an
    /// earlier folder of the same path in this run may have had (row 279).
    func forgetEverything(about workspaceURL: URL) {
        states.removeValue(forKey: FolderIdentity.canonicalPath(workspaceURL.path))
    }

    /// Only for tests: every folder forgotten.
    func reset() {
        states = [:]
        tasks = [:]
    }

    /// Only for tests: a state set by hand, with no copy behind it.
    func noteCopyingForTests(_ workspaceURL: URL) {
        states[FolderIdentity.canonicalPath(workspaceURL.path)] = .copying(hasWritten: false)
    }

    func noteReadyForTests(_ workspaceURL: URL) {
        states[FolderIdentity.canonicalPath(workspaceURL.path)] = .ready
    }

    func noteFailedForTests(_ workspaceURL: URL) {
        states[FolderIdentity.canonicalPath(workspaceURL.path)] = .failed(message: ToolchainReadinessWording.couldNotGetReady)
    }

    // MARK: - Functions: what the copy reports back

    private func noteWriting(_ workspaceURL: URL) {
        let key: String = FolderIdentity.canonicalPath(workspaceURL.path)
        if case .copying = states[key] {
            states[key] = .copying(hasWritten: true)
        }
    }

    /// Settles the state from the copy's outcome, and writes the trail line
    /// Windows writes for the same copy (#473): once per copy that changed
    /// or failed something, never for the pass that finds nothing to do.
    private func apply(_ outcome: WorkspaceModel.MirrorOutcome, to workspaceURL: URL, startedAt: Date) {
        let key: String = FolderIdentity.canonicalPath(workspaceURL.path)
        tasks.removeValue(forKey: key)
        let seconds: String = String(format: "%.1f", Date().timeIntervalSince(startedAt))
        if outcome.failed == 0 {
            states[key] = .ready
        } else {
            states[key] = .failed(message: ToolchainReadinessWording.couldNotGetReady)
            AppLog.interface.error("could not refresh .toolchain in \(LogRedactor.redacting(workspaceURL.path), privacy: .public): \(outcome.failed) file(s) failed, \(outcome.changed) written")
        }
        if outcome.changed > 0 {
            AppLog.interface.info("refreshed .toolchain in \(LogRedactor.redacting(workspaceURL.path), privacy: .public): \(outcome.changed) file(s) in \(seconds, privacy: .public)s")
        }
        if outcome.changed > 0 || outcome.failed > 0 {
            var sentence: String
            if outcome.failed == 0 {
                sentence = "got the working folder ready: \(outcome.changed) file(s) brought up to date in \(seconds) s"
            } else {
                sentence = "could not finish getting the working folder ready: \(outcome.failed) file(s) could not be copied or removed, \(outcome.changed) brought up to date, in \(seconds) s"
                if let firstFailure = outcome.firstFailure {
                    sentence += " — first: \(firstFailure)"
                }
            }
            ActivityTrail.note(.workingFolderToolsCopied, sentence + " (\(workspaceURL.path))")
        }
    }
}

/// What a teacher reads while a folder is getting ready (#476) — word for
/// word Windows' `ToolchainReadiness` constants (#473), so the two platforms
/// say the same thing. Rule 1: nothing about tools, scripts or containers;
/// "Deploy" because that is the button's caption (#443). Not in the contract:
/// a window's mechanics are not shared (`contracts/README.md`), which is what
/// Windows decided for its half; `ToolchainReadinessTests` pins the rule the
/// words follow.
nonisolated enum ToolchainReadinessWording {

    // MARK: - Stored properties

    /// The banner's title.
    static let gettingReadyTitle: String = "Getting this folder ready…"

    /// The banner, the greyed buttons' help, and the refusal while copying.
    static let gettingReadyMessage: String = "Plantoir is copying what it needs into this folder. Preview and Deploy will work in a moment."

    /// The error banner, the help and the refusal after a failure.
    static let couldNotGetReady: String = "Plantoir couldn’t finish getting this folder ready. Choose Reload Courses from the File menu to try again."
}
