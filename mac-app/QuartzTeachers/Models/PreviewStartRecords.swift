import Foundation

/// The record-keeping half of a section window's preview start (#812): when
/// a start is already under way, and how a start's record and lease are
/// taken, in the order `SectionDetailView.startPreview` needs them.
///
/// **Why it is here and not in the view.** Nothing in the suite constructs a
/// section view, so the steps live where a test can run them against the
/// real `PreviewBuildWait`, `CourseActivity` and `PreviewLeases`
/// (`PreviewBuildRecordTests`, from `contracts/shared-rules.json` →
/// `quittingWhileWorkIsUnderWay.previewBuildRecord.pressCases`).
///
/// **The fault it closes.** `startPreview` records the build, takes the
/// lease, then waits for any stop to finish. The toolbar button reads
/// Preview, not Stop, during that wait, and the assistant and Course
/// Settings see no running preview either, so a second start could come in.
/// It ended the first start's record (a new `begin` ends the old wait), was
/// refused by the first start's own lease with a sentence about ANOTHER
/// window, and ended the record it had just written. The first start then
/// built with nothing recorded, and ⌘Q quit through it without asking.
@MainActor
enum PreviewStartRecords {

    // MARK: - Types

    /// How a start's record and lease came out.
    enum Outcome: Equatable {
        /// Recorded, and the lease is this start's.
        case began(PreviewLeases.Lease)
        /// The lease was refused; the sentence says why, and this start's
        /// own claim on the record has been ended (nobody else's).
        case refused(String)
    }

    /// Where a start's run stands while the window waits for its server to
    /// be announced.
    enum RunStanding: Equatable {
        /// Still going, or not yet heard from.
        case underWay
        /// It ran and it has ended, with an exit code.
        case ended
        /// It never started: the runner recorded why (a launch problem) and
        /// is not running. The sentence is the runner's own.
        case couldNotStart(String)
    }

    // MARK: - Functions

    /// Where the run stands, from what the runner says of itself.
    ///
    /// A run that never started is an ending too (#812's review). The
    /// runner's early returns (a missing launcher, a pseudo-terminal it
    /// could not open, a process that would not launch, the folder's tools
    /// still being copied) record a launch problem, leave it not running,
    /// and some of them leave no exit code at all. The wait used to look
    /// only for the exit code, so it went on for its full ten minutes with
    /// the lease and the record held: quitting asked about a build nobody
    /// was running, and every later Preview in the window did nothing,
    /// because a start still looked under way.
    static func howTheRunStands(isRunning: Bool, lastExitCode: Int32?, launchProblem: String?) -> RunStanding {
        if isRunning {
            return .underWay
        }
        // Asked before the exit code: a run that did start clears the
        // launch problem, so one recorded now is about this start, and an
        // exit code beside it is an earlier run's.
        if let problem = launchProblem {
            return .couldNotStart(problem)
        }
        if lastExitCode != nil {
            return .ended
        }
        return .underWay
    }

    /// Whether a start parked while old stops finished is still the
    /// window's own when it resumes, and so may run its launcher.
    ///
    /// Three ways it is not. The window's lease is no longer this start's
    /// (it was stopped, or the view went away: #793). A later start of the
    /// same window took a lease equal to this one in every field, which a
    /// comparison of leases alone cannot see, so each start carries its own
    /// id and only the latest may run (the review of #812 measured both
    /// reaching the launcher). Or the quit has gone ahead and is waiting on
    /// an update set aside: nothing new may begin then, as #793 and #813
    /// already settled for the Coverage refresh and Preview Again.
    static func theStartStillBelongs(
        heldLease: PreviewLeases.Lease?,
        lease: PreviewLeases.Lease,
        heldStart: UUID?,
        start: UUID,
        appIsQuitting: Bool
    ) -> Bool {
        if appIsQuitting {
            return false
        }
        if heldLease != lease {
            return false
        }
        return heldStart == start
    }

    /// Whether this window already has a start of its own under way: its
    /// wait is going and it holds its own lease. That is the start the
    /// teacher is waiting for, so a second one asked for now does nothing
    /// at all. Asked FIRST in `startPreview`, before anything is written.
    ///
    /// The lease is the real owner here, not a guess about timing: a start
    /// holds it from just after its record is written until it is stopped,
    /// cancelled or its run ends, and `PreviewBuildWait.isWaiting` is true
    /// from the press until the page first answers. Both together mean a
    /// start is waiting for a stop or still building. A preview that is
    /// showing (wait over) is not "already starting": a start asked for
    /// then goes on as it always has.
    static func aStartIsUnderWay(wait: PreviewBuildWait, heldLease: PreviewLeases.Lease?) -> Bool {
        return wait.isWaiting && heldLease != nil
    }

    /// Records the build, then takes the lease: the BUILD first, which is
    /// load-bearing (#156's review, M2; see `startPreview`). A refused lease
    /// ends this start's own claim and nothing else, so another window's
    /// start, or the assistant's rebuild, stays recorded (#812).
    static func begin(
        wait: PreviewBuildWait,
        folderPath: String,
        courseCode: String,
        sectionNumber: Int
    ) -> Outcome {
        wait.begin(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        do {
            let lease: PreviewLeases.Lease = try PreviewLeases.lease(
                folderPath: folderPath,
                courseCode: courseCode,
                sectionNumber: sectionNumber
            )
            return .began(lease)
        } catch {
            wait.end()
            return .refused(error.localizedDescription)
        }
    }
}
