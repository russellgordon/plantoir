import Foundation

/// Where each working folder's copy of the app's tools stands (#476 — the
/// mac's half of Windows' #473): not started, being copied, ready, or failed.
///
/// One entry per folder, keyed the way every other per-folder fact is
/// (`FolderIdentity.canonicalPath`), so two windows on the same folder share
/// one copy and one answer. The copy itself runs off the main actor; this
/// registry is main-actor state the window reads to grey Preview, Deploy and
/// New Course, and to show its banner, while the copy is under way.
@MainActor
@Observable
final class ToolchainReadiness {

    // MARK: - Types

    /// What a folder's copy is doing.
    enum State: Equatable {
        /// No copy has been asked for in this run of the app.
        case notStarted
        /// The copy is running; `since` is when it began, for the banner's
        /// one-second rule.
        case copying(since: Date)
        /// The last copy finished with nothing failed.
        case ready
        /// The last copy could not finish; `message` is what a teacher reads
        /// (`ToolchainReadinessWording.couldNotGetReady`), kept until File ▸
        /// Reload Courses or a newly pointed window tries again.
        case failed(message: String)
    }

    // MARK: - Stored properties

    /// The one registry, process-wide, like `foldersWithFreshToolchain`.
    static let shared: ToolchainReadiness = ToolchainReadiness()

    /// Each folder's state, by canonical path.
    private(set) var states: [String: State] = [:]

    // MARK: - Functions

    /// The folder's state — `notStarted` for one nobody has asked about.
    func state(of workspaceURL: URL) -> State {
        return states[FolderIdentity.canonicalPath(workspaceURL.path)] ?? .notStarted
    }

    /// Whether Preview, Deploy and New Course must wait: a copy under way,
    /// or one that failed and has not been retried.
    func isGettingReady(_ workspaceURL: URL) -> Bool {
        switch state(of: workspaceURL) {
        case .copying, .failed:
            return true
        case .notStarted, .ready:
            return false
        }
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

    func noteCopying(_ workspaceURL: URL, since: Date = Date()) {
        states[FolderIdentity.canonicalPath(workspaceURL.path)] = .copying(since: since)
    }

    func noteReady(_ workspaceURL: URL) {
        states[FolderIdentity.canonicalPath(workspaceURL.path)] = .ready
    }

    func noteFailed(_ workspaceURL: URL) {
        states[FolderIdentity.canonicalPath(workspaceURL.path)] = .failed(
            message: ToolchainReadinessWording.couldNotGetReady
        )
    }

    /// Forgets a failure, so the next mirror can try again.
    func forget(_ workspaceURL: URL) {
        states.removeValue(forKey: FolderIdentity.canonicalPath(workspaceURL.path))
    }

    /// Whether the banner is shown: a copy still running `delay` after it
    /// began, or a failure. The ordinary launch, with nothing to copy, still
    /// compares every file for most of a second, and a banner for that would
    /// flash on every launch — so the banner waits one second (Windows'
    /// `ToolchainReadiness.BannerDelay`), and the buttons are disabled for
    /// that second regardless.
    static let bannerDelay: TimeInterval = 1

    nonisolated static func showsBanner(for state: State, now: Date, delay: TimeInterval = bannerDelay) -> Bool {
        switch state {
        case .copying(let since):
            return now.timeIntervalSince(since) >= delay
        case .failed:
            return true
        case .notStarted, .ready:
            return false
        }
    }

    /// Only for tests: every folder forgotten.
    func reset() {
        states = [:]
    }
}

/// What a teacher reads while a folder is getting ready (#476) — word for
/// word Windows' `ToolchainReadiness` constants (#473), so the two platforms
/// say the same thing. Rule 1: nothing about tools, scripts or containers;
/// "Deploy" because that is the button's caption (#443). Not in the contract:
/// a window's mechanics are not shared (`contracts/README.md`), which is what
/// Windows decided for its half; a test pins the rule the words follow.
nonisolated enum ToolchainReadinessWording {

    // MARK: - Stored properties

    /// The banner's title.
    static let gettingReadyTitle: String = "Getting this folder ready…"

    /// The banner, the greyed buttons' help, and the refusal while copying.
    static let gettingReadyMessage: String = "Plantoir is copying what it needs into this folder. Preview and Deploy will work in a moment."

    /// The error banner, the help and the refusal after a failure.
    static let couldNotGetReady: String = "Plantoir couldn’t finish getting this folder ready. Choose Reload Courses from the File menu to try again."
}
