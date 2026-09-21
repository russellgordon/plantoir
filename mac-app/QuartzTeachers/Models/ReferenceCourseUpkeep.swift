import Foundation

/// Keeping a reference course the way it says it is — asserted, verified, and
/// RE-ASSERTED.
///
/// Two things are true of a reference course and have to stay true whatever
/// else happened to the folder since Plantoir last saw it: its pages are
/// locked, and nothing is set to deploy it on its own.
///
/// **Neither can be assumed once, and both are measured rather than argued.**
/// A working folder kept in iCloud Drive comes back from a second Mac with no
/// locks at all — the file provider models the locked bit itself, does not
/// store it, and clears it locally about a second after an upload starts. A
/// restored backup comes back unlocked too, because a zip round trip carries
/// the mode and not the flag. And a course can be marked by hand, in an editor,
/// while an alarm it set last term is still sitting in `~/Library/LaunchAgents`.
///
/// So this runs whenever a working folder is read, and again whenever a
/// reference course is made. It is quiet when there is nothing to do, which is
/// the ordinary case; it leaves a line on the trail only when it actually did
/// something, and that line is how "my reference course let me edit a page"
/// gets explained months later.
///
/// **No timers and no waiting.** Where the lock does not take — which is what
/// a folder mid-upload does — the file is left for the next pass rather than
/// retried after a guessed delay. A delay chosen to let something settle is a
/// guess that stops working on a slower machine.
@MainActor
enum ReferenceCourseUpkeep {

    // MARK: - Functions

    /// The whole upkeep, with the LOCK WALK off the main actor.
    ///
    /// What stays on the main actor is what must: reading the courses, and
    /// the scheduled-deploy cancel, which touches `launchctl` through an
    /// injected runner a test replaces. The walk — a `stat` per file, ~24 ms
    /// with nothing to do and ~80 ms on a full pass — is what a teacher would
    /// otherwise wait for after every sheet, and it goes to the pool.
    ///
    /// The synchronous version below is kept for the copier, which locks as
    /// its LAST step and must know it happened, and for the tests.
    static func bringUpToDateInBackground(
        _ courses: [Course],
        inWorkingFolder workingFolderURL: URL?,
        runner: LaunchControlRunning = LaunchControl()
    ) {
        for course in courses where course.isKeptForReference {
            ReferenceLock.ensureLockedInBackground(course)
            guard let workingFolderURL else {
                continue
            }
            let agents: [ScheduledDeploy.Agent] = ScheduledDeployCleanup.agentsOwnedBy(
                courseCode: course.code, sectionNumber: nil, inWorkingFolder: workingFolderURL
            )
            if agents.isEmpty {
                continue
            }
            ScheduledDeployCleanup.cancel(
                agents: agents, because: .theCourseIsKeptForReference, runner: runner
            )
        }
    }

    // MARK: - Functions

    /// Brings every reference course among these back to what it claims to
    /// be, and reports what it had to do.
    @discardableResult
    static func bringUpToDate(
        _ courses: [Course],
        inWorkingFolder workingFolderURL: URL?,
        runner: LaunchControlRunning = LaunchControl()
    ) -> ReferenceLock.Outcome {
        var lockedInAll: Int = 0
        var didNotTakeInAll: Int = 0
        var walkedInAll: Int = 0
        var lockedAfterwardsInAll: Int = 0

        for course in courses where course.isKeptForReference {
            let outcome: ReferenceLock.Outcome = ReferenceLock.ensureLocked(course)
            lockedInAll += outcome.locked
            didNotTakeInAll += outcome.didNotTake
            walkedInAll += outcome.walked
            lockedAfterwardsInAll += outcome.lockedAfterwards
            if !outcome.isQuiet {
                ActivityTrail.note(
                    .referenceCoursePagesLockedAgain,
                    ReferenceCourseUpkeep.trailLine(for: outcome, course: course.displayCode)
                )
            }

            guard let workingFolderURL else {
                continue
            }
            // Asked of the AGENTS rather than of the course, for the reason
            // `agentsOwnedBy` gives: a section removed on an earlier build can
            // have left one behind that the settings no longer mention.
            let agents: [ScheduledDeploy.Agent] = ScheduledDeployCleanup.agentsOwnedBy(
                courseCode: course.code,
                sectionNumber: nil,
                inWorkingFolder: workingFolderURL
            )
            if agents.isEmpty {
                continue
            }
            ScheduledDeployCleanup.cancel(
                agents: agents, because: .theCourseIsKeptForReference, runner: runner
            )
        }

        return ReferenceLock.Outcome(
            locked: lockedInAll,
            didNotTake: didNotTakeInAll,
            walked: walkedInAll,
            lockedAfterwards: lockedAfterwardsInAll
        )
    }

    /// The line the trail carries when a pass really did something.
    ///
    /// Says the count, because the count is the whole diagnostic value: "37
    /// pages" after a restore is a backup coming back unlocked, and a handful
    /// that would not take, over and over, is a folder that syncs.
    static func trailLine(for outcome: ReferenceLock.Outcome, course displayCode: String) -> String {
        var line: String = ""
        if outcome.locked > 0 {
            let pages: String = outcome.locked == 1 ? "1 page" : "\(outcome.locked) pages"
            line = "locked \(pages) of \(displayCode) again — it is kept for reference"
        } else {
            line = "checked that \(displayCode)’s pages are locked — it is kept for reference"
        }
        if outcome.didNotTake > 0 {
            let pages: String = outcome.didNotTake == 1 ? "1 page" : "\(outcome.didNotTake) pages"
            // The COUNT and nothing else. This used to name a cause — "which
            // is what a folder kept in iCloud Drive does while it is
            // uploading" — and that is a confident wrong diagnosis on the one
            // other case that produces the same count: a volume with no
            // support for the flag at all, where NOTHING can ever be locked.
            // Say what happened; let whoever reads the report work out why.
            line += "; \(pages) would not stay locked this time"
        }
        return line
    }
}
