import Foundation

/// How a run of the toolchain ended.
struct AssistSiteWorkResult {

    // MARK: - Stored properties

    let succeeded: Bool

    /// What happened, in words meant to be read to a teacher.
    let message: String

    /// Whether what stopped it was the DESTINATION — no deploy folder, no
    /// Cloudflare account — rather than anything that happened while running.
    ///
    /// The section window shows these as an alert, because they are the one
    /// kind of refusal a teacher can go and fix in course settings, and the
    /// button that raised it has no other voice. Everything else the window
    /// says through its console, which is already on screen.
    let isAboutTheDestination: Bool

    /// Whether what stopped it was ANOTHER program building or previewing the
    /// same course (#156). The message is then
    /// `AssistWording.courseIsBeingBuiltElsewhere`; `AssistToolRunner` swaps
    /// it for `courseIsBusy` when the one asking is an assistant working from
    /// another app, since the program that is busy is the one it talks to.
    let wasBuiltElsewhere: Bool

    // MARK: - Initializer

    init(
        succeeded: Bool,
        message: String,
        isAboutTheDestination: Bool = false,
        wasBuiltElsewhere: Bool = false
    ) {
        self.succeeded = succeeded
        self.message = message
        self.isAboutTheDestination = isAboutTheDestination
        self.wasBuiltElsewhere = wasBuiltElsewhere
    }

    // MARK: - Functions

    /// The refusal for a build another program is in the way of — raised as
    /// the window's alert (`isAboutTheDestination`, the flag the window reads
    /// for "say this in an alert", as the reference-course refusal uses it:
    /// the console has nothing to show, because nothing ran).
    static func builtElsewhere(course: Course) -> AssistSiteWorkResult {
        return AssistSiteWorkResult(
            succeeded: false,
            message: AssistWording.courseIsBeingBuiltElsewhere(course: course.displayCode),
            isAboutTheDestination: true,
            wasBuiltElsewhere: true
        )
    }
}

/// The two acts that leave Swift and run the toolchain: building a section's
/// preview, and putting it on the web.
///
/// A seam rather than a call, for two reasons. The app already owns this work
/// — a preview takes a port lease and a web view, a deploy narrates itself into
/// the section's console — so the window is entitled to hand the assistant its
/// own way of doing it. And a test must be able to exercise "publish tomorrow's
/// class" without starting Docker.
@MainActor
protocol AssistSiteWork {

    // MARK: - Functions

    func rebuildPreview(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult

    func deploy(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult
}

/// The real thing: the same `preview.sh` and `deploy.sh` a teacher would run in
/// Terminal, through the same `ScriptRunner` the section's own buttons use.
///
/// The app never re-implements toolchain behaviour, and the assistant is not an
/// exception to that.
@MainActor
final class AssistToolchainWork: AssistSiteWork {

    // MARK: - Stored properties

    /// Read at call time rather than kept, so an assistant window whose folder
    /// changed under it refuses rather than working in the old one.
    private let workspace: WorkspaceModel

    /// The runner in use, so a caller can watch the output if it wants to.
    private(set) var runner: ScriptRunner = ScriptRunner()

    /// Runs a deploy against every one of the course's configured
    /// destinations — the same `MultiDestinationDeployRunner`
    /// `SectionDetailView.deployAndWait()` uses, so this headless path and
    /// the real Deploy button can never drift the way `DeployCommand.
    /// arguments` itself once warned against.
    private(set) var deployRunner: MultiDestinationDeployRunner = MultiDestinationDeployRunner()

    // MARK: - Initializer

    init(workspace: WorkspaceModel) {
        self.workspace = workspace
    }

    // MARK: - Functions

    /// Builds the section's site.
    ///
    /// `--build-only`, deliberately. Serving the preview and putting it on
    /// screen is the section window's job: it holds the port lease and the web
    /// view, and a second server started behind its back would take a port it
    /// then could not have. So the assistant brings the built site up to date
    /// and tells the teacher where to look at it.
    func rebuildPreview(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {
        guard let workspaceURL = workspace.workspaceURL else {
            return AssistSiteWorkResult(
                succeeded: false, message: AssistToolRefusal.noWorkingFolder.message
            )
        }

        // Recorded for ⌘Q (issue #232): the delegate cannot see this runner,
        // and a quit in the middle of it is a quit through a preview build.
        // Recorded HERE and not inside `ScriptRunner`, because a publish's own
        // `--build-only` wears the same launcher's name and is already counted
        // as the publish it belongs to. The `defer` covers every return below.
        CourseActivity.beginPreviewBuild(
            folderPath: workspaceURL.path, courseCode: course.code, sectionNumber: sectionNumber
        )
        defer {
            CourseActivity.endPreviewBuild(
                folderPath: workspaceURL.path, courseCode: course.code, sectionNumber: sectionNumber
            )
        }

        // Taken, THEN checked (#156): the `build` lease is on disk from the
        // line above, and only a lease another program took before it counts,
        // so two that ask at once cannot both go ahead or both back off. The
        // backstop on this path, whatever the caller checked first.
        if let holding = WorkLeaseRegistry.whatBlocksABuild(
            folderPath: workspaceURL.path, courseCode: course.code, afterTaking: true
        ) {
            WorkLeaseRegistry.noteDeclined(
                act: WorkLeaseRegistry.assistantsAct("rebuild"), courseCode: course.code,
                sectionNumber: sectionNumber, holding: holding
            )
            return AssistSiteWorkResult.builtElsewhere(course: course)
        }

        runner = ScriptRunner()
        runner.milestones = TaskMilestones.preview
        runner.run(
            scriptNamed: "preview.sh",
            arguments: [course.code, String(sectionNumber), "--build-only"],
            workingDirectory: workspaceURL
        )
        if let problem = runner.launchProblem {
            return AssistSiteWorkResult(succeeded: false, message: problem)
        }
        let built: Bool = await runner.waitUntilFinished()

        if !built {
            return AssistSiteWorkResult(
                succeeded: false,
                message: AssistWording.previewDidNotBuild(
                    course: course.code, section: String(sectionNumber)
                )
            )
        }
        return AssistSiteWorkResult(
            succeeded: true,
            message: SiteHealthFinding.appending(
                to: AssistWording.rebuiltForACallerWithNoWindow(
                    course: course.code, section: String(sectionNumber)
                ),
                from: runner
            )
        )
    }

    /// Publishes the section, building first when the built site is out of
    /// date — so what goes to students is always current.
    ///
    /// **This is the path for callers with no window.** Claude Code over MCP,
    /// and a deploy set for half six in the morning. When a section window IS
    /// open the assistant presses ITS Deploy instead, so the output lands in
    /// the console the teacher is looking at — `AssistToolRunner.deploySection`
    /// decides which, and this runs when nothing is on screen to press.
    func deploy(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {
        // The backstop on the headless path — what an MCP client and a
        // scheduled deploy take. The runner refuses first; this is here
        // because a deploy that reports success on a course kept for
        // reference is the worst direction this can fail in, and one guard in
        // one function is one edit away from being gone.
        if course.isKeptForReference {
            return AssistSiteWorkResult(
                succeeded: false,
                message: AssistWording.deployRefusedForAReferenceCourse(course: course.displayCode)
            )
        }
        guard let workspaceURL = workspace.workspaceURL else {
            return AssistSiteWorkResult(
                succeeded: false, message: AssistToolRefusal.noWorkingFolder.message
            )
        }
        if CourseActivity.busyDescription(folderPath: workspaceURL.path, courseCode: course.code) != nil {
            // A whole sentence, not the menu fragment `busyDescription`
            // returns. That string is written to sit under a greyed-out menu
            // item — "Available once preview completed" — and read out on its
            // own in a conversation it says nothing about what was asked for
            // or what to do about it. This refusal is the last word of a turn.
            return AssistSiteWorkResult(
                succeeded: false,
                message: AssistWording.courseIsBusy(course: course.code)
            )
        }

        let destinations: [CourseConfiguration.DeployDestination] = course.configuration.allDeployDestinations
        let needsBuild: Bool = BuildFreshness.needsRebuild(course: course, sectionNumber: sectionNumber)
        CourseActivity.beginPublish(
            folderPath: workspaceURL.path, courseCode: course.code, sectionNumber: sectionNumber
        )
        defer {
            CourseActivity.endPublish(
                folderPath: workspaceURL.path, courseCode: course.code, sectionNumber: sectionNumber
            )
        }

        // The same take-then-check as the rebuild above (#156). Synchronous
        // from the busy check to here, so nothing of this process's own can
        // have started in between.
        if let holding = WorkLeaseRegistry.whatBlocksABuild(
            folderPath: workspaceURL.path, courseCode: course.code, afterTaking: true
        ) {
            WorkLeaseRegistry.noteDeclined(
                act: WorkLeaseRegistry.assistantsAct("deploy"), courseCode: course.code,
                sectionNumber: sectionNumber, holding: holding
            )
            return AssistSiteWorkResult.builtElsewhere(course: course)
        }

        // The same sequencer the Deploy button uses. Built separately
        // here once, this path sent a Cloudflare course to Netlify —
        // `--target` and `--account` were never passed, and `deploy.sh`
        // defaults to Netlify because every course written before
        // Cloudflare existed relies on that. Nothing failed; the site
        // simply went to the wrong web host.
        deployRunner = MultiDestinationDeployRunner()
        await deployRunner.run(
            course: course,
            sectionNumber: sectionNumber,
            destinations: destinations,
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID,
            workingDirectory: workspaceURL,
            needsBuild: needsBuild
        )

        if deployRunner.legs.first?.buildFailed == true {
            // The findings travel even when the build failed: a missing
            // curriculum or Media folder is a likely CAUSE of the failure, and
            // over stdio there is no other way to mention it.
            var message: String = AssistWording.couldNotBuildBeforeDeploying(
                course: course.code, section: String(sectionNumber)
            )
            if let runner = deployRunner.legs.first?.runner {
                message = SiteHealthFinding.appending(to: message, from: runner)
            }
            return AssistSiteWorkResult(succeeded: false, message: message)
        }

        let outcome: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
            course: course.code,
            section: String(sectionNumber),
            destinationCount: destinations.count,
            outcome: deployRunner.outcome
        )
        guard let runner = deployRunner.legs.first?.runner else {
            return outcome
        }
        // Taken from the FIRST leg: every destination publishes the same built
        // site, so a second leg only repeats the same findings.
        return AssistSiteWorkResult(
            succeeded: outcome.succeeded,
            message: SiteHealthFinding.appending(to: outcome.message, from: runner),
            isAboutTheDestination: outcome.isAboutTheDestination
        )
    }
}
