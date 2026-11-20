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
/// for every chunk of build output, and the old loop already paid for
/// joining the transcript once a second; the one line the wait needs from
/// it is collected as it arrives instead (`hasAnnouncedQuartzLaunch`).
enum ScriptRunnerWait {

    // MARK: - Functions

    /// Returns as soon as the run's standing changes (it starts or stops
    /// running, ends with a code, could not start, announces its address,
    /// says its server is launching, or is stopped by the teacher), or when
    /// `limit` has passed with no change, whichever comes first. `limit` is
    /// the caller's own bound on the whole wait (ten minutes for a first
    /// build), never a guess at when the change will come.
    ///
    /// Also returns if the waiting task is cancelled.
    static func untilTheRunChanges(_ runner: ScriptRunner, orAfter limit: Duration) async {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        withObservationTracking {
            ScriptRunnerWait.readTheRunsStanding(runner)
        } onChange: {
            continuation.finish()
        }
        let bound: Task<Void, Never> = Task {
            try? await Task.sleep(for: limit)
            continuation.finish()
        }
        for await _ in changes {
        }
        bound.cancel()
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
