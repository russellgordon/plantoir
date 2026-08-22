import Foundation
import Observation

/// Runs a deploy against every one of a course's configured destinations,
/// in sequence — real redundancy needs a second copy actually live, not a
/// manual switch after something breaks (see `CourseConfiguration.
/// additionalDeployTargets`). Both places a deploy can start —
/// `SectionDetailView.deployAndWait()` (the toolbar button, and the
/// assistant when a section window is open) and `AssistToolchainWork.
/// deploy()` (the assistant with no window on screen) — delegate the
/// actual sequencing HERE, so the two can never drift the way
/// `DeployCommand.arguments` itself once warned against: built twice, one
/// copy sent a Cloudflare course to Netlify.
///
/// For the overwhelming majority of courses — exactly one destination —
/// this behaves exactly like running a single `ScriptRunner` always did:
/// one leg, one console, one progress bar, one outcome.
@Observable
class MultiDestinationDeployRunner {

    // MARK: - Nested types

    /// One destination's own attempt: its own `ScriptRunner`, so its own
    /// console, progress, and published-site link stay correctly scoped
    /// to IT. Sharing one `ScriptRunner` across destinations would let the
    /// second destination's "Live URL:" line silently overwrite the
    /// first's, since `ScriptRunner`'s URL-parsing only ever looks at that
    /// runner's own transcript.
    struct Leg: Identifiable {
        let id: UUID = UUID()
        let destination: CourseConfiguration.DeployDestination
        var runner: ScriptRunner = ScriptRunner()
        var isFinished: Bool = false
        var succeeded: Bool = false
        /// True only when this leg's SHARED build step failed (attempted
        /// on the first leg only, and only when the site was stale) —
        /// kept distinct from a DEPLOY failure so the teacher hears
        /// "could not be built" rather than "did not finish", which would
        /// wrongly suggest the build was fine and only the upload failed.
        var buildFailed: Bool = false
    }

    // MARK: - Stored properties

    var legs: [Leg] = []
    var currentLegIndex: Int = 0
    var isRunning: Bool = false
    var startedAt: Date?
    var wasCancelled: Bool = false
    var wasStoppedByUser: Bool = false

    // MARK: - Computed properties

    var currentLeg: Leg? {
        guard legs.indices.contains(currentLegIndex) else {
            return nil
        }
        return legs[currentLegIndex]
    }

    /// The one runner to bind a `TaskProgressView` to: whichever leg is
    /// current, or the first leg before anything has started. For a
    /// course with exactly one destination this is indistinguishable from
    /// binding to a plain `ScriptRunner`, which is the point.
    var activeRunner: ScriptRunner {
        return currentLeg?.runner ?? legs.first?.runner ?? ScriptRunner()
    }

    /// True once anything at all has been shown for this run, across any
    /// leg — used to decide whether a console area should appear yet.
    var hasAnyOutput: Bool {
        for leg in legs where !leg.runner.transcript.lines.isEmpty {
            return true
        }
        return false
    }

    /// What actually happened, once every leg that ran has finished. A
    /// leg the run never reached (stopped early by a cancel or a failed
    /// shared build) is not counted as failed — it simply never ran.
    var outcome: Outcome {
        var failed: [CourseConfiguration.DeployDestination] = []
        var anySucceeded: Bool = false
        for leg in legs where leg.isFinished {
            if leg.succeeded {
                anySucceeded = true
            } else if !leg.buildFailed {
                failed.append(leg.destination)
            }
        }
        return Outcome(anySucceeded: anySucceeded, failedDestinations: failed)
    }

    struct Outcome {
        let anySucceeded: Bool
        let failedDestinations: [CourseConfiguration.DeployDestination]

        var allSucceeded: Bool {
            return anySucceeded && failedDestinations.isEmpty
        }
    }

    // MARK: - Functions

    /// Cancels whichever leg is currently running. The remaining,
    /// not-yet-started legs are simply never reached — `run()`'s own loop
    /// checks `wasCancelled` after every `waitUntilFinished()` and stops.
    func cancel() {
        wasCancelled = true
        if let leg = currentLeg, leg.runner.isRunning {
            leg.runner.cancelByUser()
        }
    }

    /// Refuses up front, against EVERY configured destination, rather than
    /// discovering a missing credential halfway through a redundancy run —
    /// exactly the surprise redundancy exists to prevent.
    static func refusalReason(
        destinations: [CourseConfiguration.DeployDestination],
        cloudflareAccountID: String
    ) -> String? {
        for destination in destinations {
            if destination.type == "local_folder" {
                if let folderProblem = CourseConfiguration.deployFolderProblem(forPath: destination.path) {
                    return "\(folderProblem) Fix it in this course’s settings, under Deploying, then deploy again."
                }
            }
            if destination.type == "cloudflare_pages" {
                if let accountProblem = CourseConfiguration.cloudflareAccountProblem(forID: cloudflareAccountID) {
                    return "\(accountProblem) Add it in this course’s settings, under Deploying, then deploy again."
                }
            }
        }
        return nil
    }

    /// The milestones for one leg's OWN `deploy.sh` — always the
    /// deploy-only list, never the build-and-deploy list. The build (when
    /// one is needed) happens exactly once, before the first leg, as its
    /// own step; every leg's `deploy.sh` invocation always finds the site
    /// already current.
    static func deployOnlyMilestones(forDestinationType type: String) -> [TaskMilestone] {
        if type == "local_folder" {
            return TaskMilestones.deployToFolder
        }
        if type == "cloudflare_pages" {
            return TaskMilestones.deployToCloudflare
        }
        return TaskMilestones.deploy
    }

    /// The milestones for the FIRST leg, when the site also has to be
    /// rebuilt first — one task from the teacher's point of view, so one
    /// progress bar covers the build and that leg's own deploy together.
    static func buildAndDeployMilestones(forDestinationType type: String) -> [TaskMilestone] {
        if type == "local_folder" {
            return TaskMilestones.buildAndDeployToFolder
        }
        if type == "cloudflare_pages" {
            return TaskMilestones.buildAndDeployToCloudflare
        }
        return TaskMilestones.buildAndDeploy
    }

    /// Runs the whole sequence: an optional shared build, then each
    /// destination's own `deploy.sh`, one after another.
    ///
    /// A destination FAILING does not stop the others — that is the whole
    /// point of redundancy: "if one host is down or having trouble, the
    /// others still go out." A destination being CANCELLED, or the shared
    /// build failing, stops the whole run — a failed build would just
    /// publish the same stale content to every remaining destination,
    /// which is not redundancy, it is the same mistake published twice.
    func run(
        course: Course,
        sectionNumber: Int,
        destinations: [CourseConfiguration.DeployDestination],
        cloudflareAccountID: String,
        workingDirectory: URL,
        needsBuild: Bool
    ) async {
        legs = []
        for destination in destinations {
            legs.append(Leg(destination: destination))
        }
        currentLegIndex = 0
        isRunning = true
        startedAt = Date()
        wasCancelled = false
        wasStoppedByUser = false
        defer { isRunning = false }

        /// The content as it stood when the run BEGAN — recorded only if
        /// every destination then succeeded.
        ///
        /// Taken before anything runs, rather than at the end, because a
        /// publish takes minutes and the build is the longest part of it:
        /// a page the teacher edits while it runs may or may not have been
        /// read, and stamping the finishing state would mark that edit
        /// published. An early fingerprint costs a needless publish; a
        /// late one costs a class that never saw the page, so this errs
        /// early on purpose.
        ///
        /// It is taken before the BUILD too, which has one visible
        /// consequence worth knowing: `build_site.py`'s preflight appends
        /// newly discovered folders to `course_config.json`, so a publish
        /// that discovers one ends with the section still marked edited.
        /// That is correct — the teacher did add a folder — and it clears
        /// itself at the next publish, when there is nothing left to
        /// discover. The alternative, fingerprinting after the build,
        /// hides a real edit, and this feature must not fail in that
        /// direction.
        var publishedFingerprint: String?

        for index in legs.indices {
            currentLegIndex = index
            let destination: CourseConfiguration.DeployDestination = legs[index].destination
            let runner: ScriptRunner = legs[index].runner
            // Each destination wears ONLY its own custom domain — a
            // domain meant for Netlify must never leak onto the Cloudflare
            // leg's own link just because they deployed together.
            let domainForThisDestination: String = CourseConfiguration.normalizedCustomDomain(
                course.configuration.customDomain(forSection: sectionNumber, destinationType: destination.type)
            )
            runner.customDomainForLinks = domainForThisDestination.isEmpty ? nil : domainForThisDestination

            if publishedFingerprint == nil {
                publishedFingerprint = SectionPublishState.fingerprint(
                    courseDirectory: course.directoryURL,
                    sectionNumber: sectionNumber,
                    excludingRelativePaths: SectionPublishState.selfPublishingSubpaths(
                        courseDirectory: course.directoryURL,
                        destinations: destinations
                    )
                )
            }

            let buildsFirst: Bool = index == 0 && needsBuild
            if buildsFirst {
                runner.milestones = MultiDestinationDeployRunner.buildAndDeployMilestones(forDestinationType: destination.type)
                runner.run(
                    scriptNamed: "preview.sh",
                    arguments: [course.code, String(sectionNumber), "--build-only"],
                    workingDirectory: workingDirectory
                )
                if runner.launchProblem != nil {
                    legs[index].isFinished = true
                    legs[index].buildFailed = true
                    break
                }
                let built: Bool = await runner.waitUntilFinished()
                if runner.wasCancelled || runner.wasStoppedByUser {
                    wasCancelled = runner.wasCancelled
                    wasStoppedByUser = runner.wasStoppedByUser
                    legs[index].isFinished = true
                    break
                }
                if !built {
                    legs[index].isFinished = true
                    legs[index].buildFailed = true
                    break
                }
            } else {
                runner.milestones = MultiDestinationDeployRunner.deployOnlyMilestones(forDestinationType: destination.type)
            }

            let arguments: [String] = DeployCommand.arguments(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                destination: destination,
                cloudflareAccountID: cloudflareAccountID
            )
            runner.run(
                scriptNamed: DeployCommand.scriptName,
                arguments: arguments,
                workingDirectory: workingDirectory,
                keepingTranscript: buildsFirst
            )
            if runner.launchProblem != nil {
                legs[index].isFinished = true
                continue
            }
            let deployed: Bool = await runner.waitUntilFinished()
            legs[index].isFinished = true
            legs[index].succeeded = deployed
            if runner.wasCancelled || runner.wasStoppedByUser {
                wasCancelled = wasCancelled || runner.wasCancelled
                wasStoppedByUser = wasStoppedByUser || runner.wasStoppedByUser
                break
            }
        }

        recordWhatWentOut(course: course, sectionNumber: sectionNumber, fingerprint: publishedFingerprint)
    }

    /// Marks the section up to date, so its window stops saying
    /// " — Edited". Only when EVERY destination succeeded: a course
    /// publishing to two hosts, one of which failed, has not published.
    func recordWhatWentOut(course: Course, sectionNumber: Int, fingerprint: String?) {
        guard let fingerprint, outcome.allSucceeded else {
            return
        }
        var destinations: [String] = []
        var names: [String] = []
        for leg in legs where leg.succeeded {
            destinations.append(leg.destination.type)
            names.append(DeployCommand.destinationDescription(for: leg.destination))
        }
        let recorded: Bool = SectionPublishState.recordPublish(
            courseDirectory: course.directoryURL,
            sectionNumber: sectionNumber,
            fingerprint: fingerprint,
            destinations: destinations
        )
        // The failure branch is recorded too, and matters MORE than the
        // success: the marker is derived, so a section that stayed
        // "Edited" because the stamp could not be written looks exactly
        // like one that was never published. Without this line the report
        // "it still says Edited after I published" has nothing to read.
        let destinationNames: String = MultiDestinationDeployRunner.joinedWithAnd(names)
        var sentence: String = "marked this section\u{2019}s pages as published to " + destinationNames
        if !recorded {
            sentence = "published to " + destinationNames
                + ", but could not note it down — the window will still say Edited"
        }
        ActivityTrail.note(
            .sectionContentMarkedPublished,
            sentence,
            course: course.code,
            section: sectionNumber
        )
    }

    // MARK: - Turning an outcome into words

    /// Joins destination names the way a teacher would say them out loud:
    /// "Cloudflare Pages", or "Cloudflare Pages and your folder" — never
    /// assembled inside `AssistWording` itself, which holds only whole
    /// sentences.
    static func joinedWithAnd(_ items: [String]) -> String {
        if items.isEmpty {
            return ""
        }
        if items.count == 1 {
            return items[0]
        }
        var result: String = ""
        for index in items.indices {
            if index == 0 {
                result = items[index]
            } else if index == items.count - 1 {
                result += " and " + items[index]
            } else {
                result += ", " + items[index]
            }
        }
        return result
    }

    /// The final `AssistSiteWorkResult` for a finished run — the single
    /// place that decides which sentence a teacher hears, whether that is
    /// the unchanged single-destination wording (`destinationCount <= 1`,
    /// true for the overwhelming majority of courses) or one of the
    /// multi-destination sentences.
    static func result(
        course: String,
        section: String,
        destinationCount: Int,
        outcome: Outcome
    ) -> AssistSiteWorkResult {
        if destinationCount <= 1 {
            if outcome.anySucceeded {
                return AssistSiteWorkResult(
                    succeeded: true, message: AssistWording.deployed(course: course, section: section)
                )
            }
            return AssistSiteWorkResult(
                succeeded: false, message: AssistWording.deployDidNotFinish(course: course, section: section)
            )
        }
        if outcome.allSucceeded {
            return AssistSiteWorkResult(
                succeeded: true,
                message: AssistWording.deployedToMultipleDestinations(
                    course: course, section: section, destinationCount: destinationCount
                )
            )
        }
        if outcome.anySucceeded {
            var failedNames: [String] = []
            for destination in outcome.failedDestinations {
                failedNames.append(DeployCommand.destinationDescription(for: destination))
            }
            return AssistSiteWorkResult(
                succeeded: false,
                message: AssistWording.deployPartiallySucceeded(
                    course: course, section: section,
                    failedDestinations: MultiDestinationDeployRunner.joinedWithAnd(failedNames)
                )
            )
        }
        return AssistSiteWorkResult(
            succeeded: false,
            message: AssistWording.deployToMultipleDestinationsDidNotFinish(course: course, section: section)
        )
    }
}
