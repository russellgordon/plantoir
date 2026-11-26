import Foundation
import Observation

/// Waits for a run to change, rather than looking at it once a second (#998).
///
/// The preview's wait for its server used to sleep a second at a time while
/// it waited for the run to say "Launching Quartz preview", to announce its
/// address, or to end. All three are things the runner already knows the
/// moment they happen, and it is `@Observable`, so the wait now asks to be
/// woken by the change itself: Observation calls back as one of the
/// properties below is about to change, and the wait goes on as soon as the
/// change has been made.
///
/// What is NOT read here is the transcript. Reading it would wake the wait
/// for every chunk of build output; the one line the wait needs from it is
/// collected as it arrives instead (`hasAnnouncedQuartzLaunch`).
///
/// **One registration at a time, per wait.** A registration made with
/// `withObservationTracking` cannot be withdrawn (the `Observations`
/// sequence that can be cancelled needs macOS 26, and Plantoir supports 15);
/// it is released when it fires, at the runner's next change. So a wait that
/// ends at its bound keeps its registration for the next wait rather than
/// making another: a ten-minute wait read once a second holds one, not six
/// hundred. Whatever is still registered is released when the run ends,
/// which changes `isRunning` and `lastExitCode`.
@MainActor
final class ScriptRunnerWait {

    // MARK: - Stored properties

    let runner: ScriptRunner

    /// True while a registration is waiting for the runner's next change.
    private(set) var registrationIsLive: Bool = false

    /// The wait in progress, if any, to be ended by a change.
    private var currentWait: AsyncStream<Void>.Continuation?

    /// A change that came while nothing was waiting: the next wait returns
    /// at once, so the caller looks again.
    private var changedWhileNotWaiting: Bool = false

    // MARK: - Initializer

    init(_ runner: ScriptRunner) {
        self.runner = runner
    }

    // MARK: - Functions

    /// Returns as soon as the run's standing changes (it starts or stops
    /// running, ends with a code, could not start, announces its address,
    /// says its server is launching, or is stopped by the teacher), or when
    /// `limit` has passed with no change, whichever comes first. `limit` is
    /// the caller's own bound or pace, never a guess at when the change will
    /// come. Also returns if the waiting task is cancelled.
    func untilTheRunChanges(orAfter limit: Duration) async {
        if changedWhileNotWaiting {
            changedWhileNotWaiting = false
            return
        }
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        currentWait = continuation
        if !registrationIsLive {
            registrationIsLive = true
            withObservationTracking {
                ScriptRunnerWait.readTheRunsStanding(runner)
            } onChange: { [weak self] in
                // Called on the main actor, as the runner is about to change.
                MainActor.assumeIsolated {
                    self?.runnerIsChanging()
                }
            }
        }
        let bound: Task<Void, Never> = Task {
            try? await Task.sleep(for: limit)
            continuation.finish()
        }
        for await _ in changes {
        }
        bound.cancel()
        currentWait = nil
    }

    private func runnerIsChanging() {
        registrationIsLive = false
        if let currentWait {
            currentWait.finish()
        } else {
            changedWhileNotWaiting = true
        }
    }

    /// Reads, and so observes, everything the preview's wait decides on.
    static func readTheRunsStanding(_ runner: ScriptRunner) {
        _ = runner.isRunning
        _ = runner.lastExitCode
        _ = runner.launchProblem
        _ = runner.previewAddress
        _ = runner.hasAnnouncedQuartzLaunch
        _ = runner.wasStoppedByUser
        _ = runner.startedAt
    }
}
