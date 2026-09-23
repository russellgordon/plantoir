import Foundation

/// A scheduled deploy must not outlive the course it was set for.
///
/// **The fault.** Removing a course, or one of its sections, archived the
/// folder and left the alarm standing. The plist is outside the working folder,
/// addressed by the course code, and `StartCalendarInterval` carries no year —
/// so it was loaded again at the next login and came due on the same date the
/// following year, against whatever was in the folder by then. Usually that
/// ends in `deploy.sh` refusing ("Course folder not found on host"); the edge
/// that does not is a teacher who removes last year's ICS3U and creates this
/// year's with the same code, which is the ordinary September sequence.
/// Measured, and worse than the issue said: a course that deploys to a FOLDER
/// or to Cloudflare Pages does not refuse at all — it builds the NEW course and
/// reports success.
///
/// **Why the orchestration is here and not in the sidebar.** The cancel has to
/// be somewhere a test can drive: no test in the suite constructs `SidebarView`
/// — every reference to it is to a static member — so a cancel living in the
/// view could be proved only by proving the helper it calls, and a later edit
/// that dropped the call would leave the suite green.
///
/// **Why it is not inside `CourseArchiver`.** `CourseArchiverTests` and
/// `CourseRestorerTests` build an ICS3U fixture and set no
/// `launchAgentsDirectoryOverride`. A cancel inside the archiver, with the real
/// `LaunchControl` as its default, would boot out and delete a REAL ICS3U
/// schedule on the machine running the suite. So the runner is injected here
/// and the archiver stays as it is.
///
/// **The order is CANCEL FIRST, then remove**, which is the opposite of the
/// rename's. A rename that cancelled before a failed move would silently drop a
/// deploy for a course still sitting there under its old name; a REMOVAL that
/// archives before a failed cancel leaves the very thing this exists to
/// prevent — a course that is gone with a live alarm still addressed to it. So
/// a cancel that fails stops the removal, and the teacher is told plainly.
/// If the removal then fails, the deploy stays cancelled and the sentence says
/// so.
///
/// **Everything here is scoped to ONE working folder** by the plist's
/// `WorkingDirectory` — see `ScheduledDeploy.agents(inWorkingFolder:)` for what
/// goes wrong without that.
@MainActor
enum ScheduledDeployCleanup {

    // MARK: - Types

    /// Why a scheduled deploy was turned off, in the words the trail uses.
    ///
    /// One trail event with several reasons rather than one event each: a
    /// teacher reading the trail wants to know their overnight deploy was
    /// turned off and by what, and the difference between two ways of removing
    /// something means nothing to them. Three when this was written; four
    /// since a course could be kept for reference.
    nonisolated enum Reason {

        /// The whole course was removed from the sidebar.
        case courseWasRemoved

        /// One section was removed from the sidebar.
        case sectionWasRemoved

        /// The moment it was set for had gone by, by more than the course
        /// allows.
        case theDayItWasSetForHadGoneBy

        /// The course is kept for reference now, so it is never deployed —
        /// and an alarm set before that is an alarm for a deploy that will be
        /// refused at half six with nobody there to read the refusal.
        case theCourseIsKeptForReference

        // MARK: - Computed properties

        /// The end of the trail line: "turned off a scheduled deploy …".
        var trailPhrase: String {
            switch self {
            case .courseWasRemoved:
                return "because the course was removed"
            case .sectionWasRemoved:
                return "because that section was removed"
            case .theDayItWasSetForHadGoneBy:
                return "because the day it was set for had gone by"
            case .theCourseIsKeptForReference:
                return "because the course is kept for reference"
            }
        }
    }

    /// What turning scheduled deploys off actually managed.
    struct Outcome: Equatable {

        // MARK: - Stored properties

        /// Sections whose scheduled deploy was turned off.
        let stopped: [Int]

        /// Sections whose scheduled deploy could not be turned off — rare, and
        /// never swallowed, because one of those may still try to run.
        let unstopped: [Int]

        // MARK: - Computed properties

        /// True when nothing happened that anybody needs telling about.
        var isQuiet: Bool {
            return stopped.isEmpty && unstopped.isEmpty
        }
    }

    /// What a removal did, for the view to turn into an alert or into nothing.
    struct RemovalResult {

        // MARK: - Stored properties

        /// Sections whose scheduled deploy was turned off on the way.
        let stoppedSections: [Int]

        /// True when the course or section really was archived and removed.
        let didRemove: Bool

        /// What to tell the teacher, or nil when it all went through.
        ///
        /// Nothing is said about a cancel that WORKED: the confirmation
        /// already said it would happen, and a second alert saying it did is
        /// noise. The rename shows one because a rename's confirmation never
        /// mentions the schedule.
        let problem: String?
    }

    // MARK: - Stored properties

    /// The sentences a teacher reads.
    ///
    /// Retyped from `contracts/shared-rules.json` →
    /// `scheduledDeployCancellation.wording` and pinned against it by
    /// `ScheduledDeployCleanupTests`, the same arrangement
    /// `ScheduledPublishOutcome.sentence(for:course:section:)` uses. They are
    /// NOT in `AssistWording`: the assistant says none of this, and a sentence
    /// belongs beside the act that produces it.
    ///
    /// The singular and plural renderings are separate strings rather than one
    /// string with a verb placeholder, for the reason
    /// `AssistWording.linkedClassesWereLeftAlone` is a pair: one rendering
    /// cannot show both branches, and a contract holding half a sentence is a
    /// contract the other platform has to finish by guessing.
    static func warningForRemovingASection(sectionNumber: Int) -> String {
        return "Section \(sectionNumber) is set to deploy on its own. Removing it turns that off."
    }

    static func warningForRemovingACourse(courseCode: String, sections: [Int]) -> String {
        let listed: String = CourseRenamer.listed(sections)
        if sections.count == 1 {
            return "\(listed) of \(courseCode) is set to deploy on its own. "
                + "Removing \(courseCode) turns that off."
        }
        return "\(listed) of \(courseCode) are set to deploy on their own. "
            + "Removing \(courseCode) turns that off."
    }

    static func couldNotTurnItOff(courseCode: String, sections: [Int]) -> String {
        let listed: String = CourseRenamer.listed(sections)
        if sections.count == 1 {
            return "\(listed) of \(courseCode) is set to deploy on its own, and Plantoir could not "
                + "turn that off — so nothing has been removed. Turn off the scheduled deploy from "
                + "the section’s menu, then try again."
        }
        return "\(listed) of \(courseCode) are set to deploy on their own, and Plantoir could not "
            + "turn that off — so nothing has been removed. Turn off the scheduled deploys from "
            + "the section’s menu, then try again."
    }

    static func removalFailedAfterTurningItOff(
        courseCode: String, sections: [Int], reason: String
    ) -> String {
        let listed: String = CourseRenamer.listed(sections)
        if sections.count == 1 {
            return "\(listed) of \(courseCode) will no longer deploy on its own — that was turned "
                + "off first. Removing it then failed: \(reason)"
        }
        return "\(listed) of \(courseCode) will no longer deploy on their own — that was turned "
            + "off first. Removing it then failed: \(reason)"
    }

    // MARK: - Functions

    /// The scheduled deploys THIS working folder holds for one course, or for
    /// one of its sections.
    ///
    /// Asked of the agents themselves rather than of the course's section
    /// list, which is what `CourseRenamer.sectionsWithAScheduledPublish` used
    /// to do: a section removed on an earlier build left an alarm behind and
    /// took its number out of the settings, so a walk over the settings cannot
    /// see it. A teacher can also delete an agent in Finder without telling
    /// us, and acting on a list of our own is how a removal ends up reporting
    /// that it turned off something that was never on.
    static func agentsOwnedBy(
        courseCode: String,
        sectionNumber: Int?,
        inWorkingFolder workingFolderURL: URL
    ) -> [ScheduledDeploy.Agent] {
        let wanted: String = ScheduledDeploy.sanitizedCode(courseCode)
        var result: [ScheduledDeploy.Agent] = []
        for agent in ScheduledDeploy.agents(inWorkingFolder: workingFolderURL) {
            // Both sides sanitised, never raw: a plist written before v1.2.0
            // has no course code of its own, so its code comes back out of the
            // LABEL in sanitised form, and a raw comparison would miss it.
            if ScheduledDeploy.sanitizedCode(agent.courseCode) != wanted {
                continue
            }
            if let sectionNumber, agent.sectionNumber != sectionNumber {
                continue
            }
            result.append(agent)
        }
        return result
    }

    /// The extra sentence the removal confirmation carries, or nil when there
    /// is nothing scheduled and the teacher gets the ordinary wording.
    static func warningForConfirmation(
        courseCode: String,
        sectionNumber: Int?,
        inWorkingFolder workingFolderURL: URL
    ) -> String? {
        let agents: [ScheduledDeploy.Agent] = agentsOwnedBy(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            inWorkingFolder: workingFolderURL
        )
        if agents.isEmpty {
            return nil
        }
        if let sectionNumber, agents.count == 1 {
            return warningForRemovingASection(sectionNumber: sectionNumber)
        }
        var sections: [Int] = []
        for agent in agents {
            sections.append(agent.sectionNumber)
        }
        return warningForRemovingACourse(courseCode: courseCode, sections: sections)
    }

    /// Turns these scheduled deploys off, and leaves a line for each.
    ///
    /// The runner is taken explicitly so no test can reach the real
    /// `launchctl`; see the note on the type for what that would cost.
    @discardableResult
    static func cancel(
        agents: [ScheduledDeploy.Agent],
        because reason: Reason,
        runner: LaunchControlRunning
    ) -> Outcome {
        var stopped: [Int] = []
        var unstopped: [Int] = []
        for agent in agents {
            let problem: String? = ScheduledDeploy.cancelScheduledDeploy(
                courseCode: agent.courseCode,
                sectionNumber: agent.sectionNumber,
                // The agent's own answer, so the backstop inside the cancel
                // cannot disagree with the list this was chosen from.
                inWorkingFolder: URL(fileURLWithPath: agent.workingFolderPath),
                runner: runner
            )
            if problem == nil {
                stopped.append(agent.sectionNumber)
                ActivityTrail.note(
                    .scheduledDeployTurnedOff,
                    "turned off a scheduled deploy " + reason.trailPhrase,
                    course: agent.courseCode,
                    section: agent.sectionNumber
                )
            } else {
                unstopped.append(agent.sectionNumber)
            }
        }
        return Outcome(stopped: stopped, unstopped: unstopped)
    }

    /// Removes a whole course: its scheduled deploys first, then the folder.
    ///
    /// The ONE function per removal kind that the sidebar calls, so a later
    /// piece adding a step to a removal — unlocking a reference course, say —
    /// adds it here rather than in the view.
    static func removeCourse(
        _ course: Course,
        coursesDirectoryURL: URL,
        runner: LaunchControlRunning = LaunchControl()
    ) -> RemovalResult {
        let workingFolderURL: URL = coursesDirectoryURL.deletingLastPathComponent()
        let agents: [ScheduledDeploy.Agent] = agentsOwnedBy(
            courseCode: course.code,
            sectionNumber: nil,
            inWorkingFolder: workingFolderURL
        )
        let outcome: Outcome = cancel(agents: agents, because: .courseWasRemoved, runner: runner)
        if !outcome.unstopped.isEmpty {
            return RemovalResult(
                stoppedSections: outcome.stopped,
                didRemove: false,
                problem: couldNotTurnItOff(courseCode: course.code, sections: outcome.unstopped)
            )
        }
        // A reference course's pages are locked, and `FileManager.removeItem`
        // refuses a locked tree outright ("Operation not permitted"). Unlocked
        // AFTER the cancel and BEFORE the archive, so the one thing that can
        // still stop a removal is the cancel — and so a course whose removal
        // fails for some other reason is left unlocked rather than half
        // frozen; the next folder read locks it again.
        //
        // The teacher is told nothing about this. A delete confirmation that
        // mentioned the lock would be the app talking about its own plumbing.
        if course.isKeptForReference {
            ReferenceLock.unlock(courseDirectory: course.directoryURL)
        }
        do {
            try CourseArchiver.archiveAndRemoveCourse(
                course, coursesDirectoryURL: coursesDirectoryURL
            )
        } catch {
            return RemovalResult(
                stoppedSections: outcome.stopped,
                didRemove: false,
                problem: removalProblemSentence(
                    courseCode: course.code,
                    stopped: outcome.stopped,
                    reason: error.localizedDescription
                )
            )
        }
        return RemovalResult(stoppedSections: outcome.stopped, didRemove: true, problem: nil)
    }

    /// Removes one section: its scheduled deploy first, then the folder.
    static func removeSection(
        _ sectionNumber: Int,
        from course: Course,
        coursesDirectoryURL: URL,
        runner: LaunchControlRunning = LaunchControl()
    ) -> RemovalResult {
        // A reference course is frozen, and removing a section CHANGES it —
        // so this is refused rather than unlocked. The sidebar does not offer
        // the item at all, which is where a teacher meets this; the refusal
        // is here so that no other caller can get past it, and so that what
        // they read is a sentence rather than the file system's own words
        // about an operation not being permitted.
        //
        // Removing the WHOLE course is a different act and is allowed: it is
        // the teacher putting the shelf away, not changing what is on it.
        if course.isKeptForReference {
            return RemovalResult(
                stoppedSections: [],
                didRemove: false,
                problem: ReferenceWording.staysAsItIs(course: course.displayCode)
            )
        }
        let workingFolderURL: URL = coursesDirectoryURL.deletingLastPathComponent()
        let agents: [ScheduledDeploy.Agent] = agentsOwnedBy(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            inWorkingFolder: workingFolderURL
        )
        let outcome: Outcome = cancel(agents: agents, because: .sectionWasRemoved, runner: runner)
        if !outcome.unstopped.isEmpty {
            return RemovalResult(
                stoppedSections: outcome.stopped,
                didRemove: false,
                problem: couldNotTurnItOff(courseCode: course.code, sections: outcome.unstopped)
            )
        }
        do {
            try CourseArchiver.archiveAndRemoveSection(
                sectionNumber, from: course, coursesDirectoryURL: coursesDirectoryURL
            )
        } catch {
            return RemovalResult(
                stoppedSections: outcome.stopped,
                didRemove: false,
                problem: removalProblemSentence(
                    courseCode: course.code,
                    stopped: outcome.stopped,
                    reason: error.localizedDescription
                )
            )
        }
        return RemovalResult(stoppedSections: outcome.stopped, didRemove: true, problem: nil)
    }

    /// Clears this working folder's scheduled deploys whose moment has gone by
    /// by more than the course allows.
    ///
    /// **Provably harmless, and that is why it is only the overdue ones.** A
    /// job this far past its moment would stand itself down the next time it
    /// tried to fire (`ScheduledDeployLateness`), so removing it destroys
    /// nothing that could have run — it stops the sidebar and the teacher's
    /// `LaunchAgents` folder disagreeing with reality, and stops the annual
    /// repeat for a job on a Mac whose owner has not opened Plantoir since.
    ///
    /// **One-sided on purpose.** The run's own check is `abs(now − intended)`,
    /// which also allows a job firing EARLY after a time-zone move; the sweep
    /// asks only whether the moment has PASSED, so a deploy set three weeks
    /// ahead is never touched.
    ///
    /// **A job with no recorded moment is left alone**, whatever its age. The
    /// run fails open on one of those, so sweeping it would destroy a deploy
    /// that would otherwise still happen.
    ///
    /// A COURSE-ABSENCE sweep was considered and rejected; the reasons are in
    /// `documentation/07-deployment.md`.
    @discardableResult
    static func sweepDeploysThatAreTooLate(
        inWorkingFolder workingFolderURL: URL,
        now: Date = Date(),
        runner: LaunchControlRunning = LaunchControl()
    ) -> Outcome {
        var overdue: [ScheduledDeploy.Agent] = []
        for agent in ScheduledDeploy.agents(inWorkingFolder: workingFolderURL) {
            guard let moment = agent.scheduledFor else {
                continue
            }
            let allowedDays: Int = ScheduledDeployLateness.days(
                forCourseCode: agent.courseCode, inWorkingFolder: workingFolderURL
            )
            let lateBy: TimeInterval = now.timeIntervalSince(moment)
            if lateBy > ScheduledDeployLateness.allowedLateness(days: allowedDays) {
                overdue.append(agent)
            }
        }
        if overdue.isEmpty {
            return Outcome(stopped: [], unstopped: [])
        }
        return cancel(agents: overdue, because: .theDayItWasSetForHadGoneBy, runner: runner)
    }

    /// What a removal that failed AFTER the cancel had worked says.
    ///
    /// When nothing was scheduled there is nothing extra to say and the
    /// teacher gets the plain reason, exactly as they did before this existed.
    private static func removalProblemSentence(
        courseCode: String, stopped: [Int], reason: String
    ) -> String {
        if stopped.isEmpty {
            return reason
        }
        return removalFailedAfterTurningItOff(
            courseCode: courseCode, sections: stopped, reason: reason
        )
    }
}
