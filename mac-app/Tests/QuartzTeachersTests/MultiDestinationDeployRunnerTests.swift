import XCTest
@testable import QuartzTeachers

/// The pure decision logic a multi-destination deploy runs on: refusal
/// checks, milestone selection, and turning a finished run's outcome into
/// the sentence a teacher hears. None of this touches a real process — the
/// actual sequencing (`MultiDestinationDeployRunner.run`) needs Docker and
/// real network access, exactly like `deployAndWait()` always has, so it is
/// exercised by hand against the real app rather than here.
@MainActor
final class MultiDestinationDeployRunnerTests: XCTestCase {

    // MARK: - The build leg says whether it is a deploy's (#729)

    /// A deploy's build leg carries `--for-deploy`; the assistant's rebuild
    /// does not. The flag is what lets the other launchers' guards say
    /// "already being deployed" for one and "already being built" for the
    /// other (`shared-rules.json` → `deployWhileItsSectionDeploys`).
    func testOnlyADeploysBuildLegSaysForDeploy() {
        XCTAssertEqual(
            MultiDestinationDeployRunner.buildArguments(
                courseCode: "ICS4U", sectionNumber: 2, unattended: false, forADeploy: true
            ),
            ["ICS4U", "2", "--build-only", "--for-deploy"]
        )
        XCTAssertEqual(
            MultiDestinationDeployRunner.buildArguments(
                courseCode: "ICS4U", sectionNumber: 2, unattended: true, forADeploy: true
            ),
            ["ICS4U", "2", "--build-only", "--non-interactive", "--for-deploy"]
        )
        XCTAssertEqual(
            MultiDestinationDeployRunner.buildArguments(
                courseCode: "ICS4U", sectionNumber: 2, unattended: true, forADeploy: false
            ),
            ["ICS4U", "2", "--build-only", "--non-interactive"]
        )
    }

    /// The two callers pass what they are: the deploy's run says it is a
    /// deploy, the assistant's rebuild says it is not. Read from the source,
    /// because the run itself needs a real launcher.
    func testTheDeployAndTheRebuildEachSayWhatTheyAre() throws {
        let repository: URL = FolderIdentityTests.repositoryRoot()
        let runner: String = try String(
            contentsOf: repository.appendingPathComponent(
                "mac-app/QuartzTeachers/Scripting/MultiDestinationDeployRunner.swift"
            ),
            encoding: .utf8
        )
        let rebuild: String = try String(
            contentsOf: repository.appendingPathComponent("mac-app/QuartzTeachers/Models/Assist/AssistSiteWork.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(runner.components(separatedBy: "forADeploy: true").count - 1, 1)
        XCTAssertEqual(runner.components(separatedBy: "forADeploy: false").count - 1, 0)
        XCTAssertEqual(rebuild.components(separatedBy: "forADeploy: false").count - 1, 1)
        XCTAssertEqual(rebuild.components(separatedBy: "forADeploy: true").count - 1, 0)
    }

    // MARK: - Refusal, checked against every configured destination

    func testRefusesOnAnAdditionalCloudflareTargetWithNoAccountID() {
        let destinations: [CourseConfiguration.DeployDestination] = [
            CourseConfiguration.DeployDestination(type: "netlify", path: ""),
            CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: ""),
        ]
        let refusal: String? = MultiDestinationDeployRunner.refusalReason(
            destinations: destinations, cloudflareAccountID: ""
        )
        XCTAssertNotNil(refusal)
        XCTAssertTrue(refusal!.contains("Account ID"))
    }

    func testRefusesOnAnAdditionalFolderTargetWithNoValidPath() {
        let destinations: [CourseConfiguration.DeployDestination] = [
            CourseConfiguration.DeployDestination(type: "netlify", path: ""),
            CourseConfiguration.DeployDestination(type: "local_folder", path: ""),
        ]
        let refusal: String? = MultiDestinationDeployRunner.refusalReason(
            destinations: destinations, cloudflareAccountID: ""
        )
        XCTAssertNotNil(refusal)
        XCTAssertTrue(refusal!.contains("folder"))
    }

    func testNoRefusalWhenEveryDestinationIsUsable() {
        let destinations: [CourseConfiguration.DeployDestination] = [
            CourseConfiguration.DeployDestination(type: "netlify", path: ""),
            CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: ""),
            CourseConfiguration.DeployDestination(type: "local_folder", path: NSTemporaryDirectory()),
        ]
        XCTAssertNil(MultiDestinationDeployRunner.refusalReason(
            destinations: destinations, cloudflareAccountID: "0123456789abcdef0123456789abcdef"
        ))
    }

    func testNetlifyNeedsNoCredentialAsEitherPrimaryOrAdditional() {
        // Netlify's token lives in Keychain, injected by the launcher —
        // there is nothing for the app itself to check.
        let destinations: [CourseConfiguration.DeployDestination] = [
            CourseConfiguration.DeployDestination(type: "local_folder", path: NSTemporaryDirectory()),
            CourseConfiguration.DeployDestination(type: "netlify", path: ""),
        ]
        XCTAssertNil(MultiDestinationDeployRunner.refusalReason(
            destinations: destinations, cloudflareAccountID: ""
        ))
    }

    // MARK: - Milestones stay destination-accurate and never mention the wrong host

    func testDeployOnlyMilestonesNeverMentionNetlifyForOtherDestinations() {
        for milestone in MultiDestinationDeployRunner.deployOnlyMilestones(forDestinationType: "cloudflare_pages") {
            XCTAssertFalse(milestone.label.contains("Netlify"))
        }
        for milestone in MultiDestinationDeployRunner.deployOnlyMilestones(forDestinationType: "local_folder") {
            XCTAssertFalse(milestone.label.contains("Netlify"))
        }
    }

    func testBuildAndDeployMilestonesMatchDeployOnlyMilestonesForTheSameType() {
        // Every leg after the first always uses the deploy-only list,
        // because the build (if one happened) already ran on leg one —
        // both lists still have to agree about which HOST they name.
        for type in CourseConfiguration.knownDeployTargetTypes {
            let buildAndDeploy: [TaskMilestone] = MultiDestinationDeployRunner.buildAndDeployMilestones(forDestinationType: type)
            let deployOnly: [TaskMilestone] = MultiDestinationDeployRunner.deployOnlyMilestones(forDestinationType: type)
            XCTAssertEqual(buildAndDeploy.last?.marker, deployOnly.last?.marker,
                           "Both must end on the same 'finished' marker for \(type)")
        }
    }

    // MARK: - Joining destination names

    func testJoinedWithAndHandlesEveryCount() {
        XCTAssertEqual(MultiDestinationDeployRunner.joinedWithAnd([]), "")
        XCTAssertEqual(MultiDestinationDeployRunner.joinedWithAnd(["Netlify"]), "Netlify")
        XCTAssertEqual(MultiDestinationDeployRunner.joinedWithAnd(["Netlify", "Cloudflare Pages"]),
                       "Netlify and Cloudflare Pages")
        XCTAssertEqual(
            MultiDestinationDeployRunner.joinedWithAnd(["Netlify", "Cloudflare Pages", "/Users/teacher/Sites"]),
            "Netlify, Cloudflare Pages and /Users/teacher/Sites"
        )
    }

    // MARK: - Turning an outcome into the sentence a teacher hears

    /// A course with exactly one destination — the overwhelming majority —
    /// must use the UNCHANGED single-destination wording, word for word,
    /// whatever `outcome` says. Multi-destination sentences must never
    /// appear for a teacher who never opted into redundancy.
    func testASingleDestinationCourseAlwaysUsesTheUnchangedWording() {
        let succeeded: Outcome = Outcome(anySucceeded: true, failedDestinations: [])
        let succeededResult: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
            course: "ICS3U", section: "1", destinationCount: 1, outcome: succeeded
        )
        XCTAssertEqual(succeededResult.message, AssistWording.deployed(course: "ICS3U", section: "1"))

        let failed: Outcome = Outcome(anySucceeded: false, failedDestinations: [
            CourseConfiguration.DeployDestination(type: "netlify", path: ""),
        ])
        let failedResult: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
            course: "ICS3U", section: "1", destinationCount: 1, outcome: failed
        )
        XCTAssertEqual(failedResult.message, AssistWording.deployDidNotFinish(course: "ICS3U", section: "1"))
    }

    func testAllDestinationsSucceeding() {
        let outcome: Outcome = Outcome(anySucceeded: true, failedDestinations: [])
        let result: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
            course: "ICS3U", section: "1", destinationCount: 2, outcome: outcome
        )
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.message, AssistWording.deployedToMultipleDestinations(
            course: "ICS3U", section: "1", destinationCount: 2
        ))
    }

    func testSomeDestinationsFailingNamesWhichOnes() {
        let outcome: Outcome = Outcome(anySucceeded: true, failedDestinations: [
            CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: ""),
        ])
        let result: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
            course: "ICS3U", section: "1", destinationCount: 2, outcome: outcome
        )
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, AssistWording.deployPartiallySucceeded(
            course: "ICS3U", section: "1", failedDestinations: "Cloudflare Pages"
        ))
    }

    func testEveryDestinationFailing() {
        let outcome: Outcome = Outcome(anySucceeded: false, failedDestinations: [
            CourseConfiguration.DeployDestination(type: "netlify", path: ""),
            CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: ""),
        ])
        let result: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
            course: "ICS3U", section: "1", destinationCount: 2, outcome: outcome
        )
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, AssistWording.deployToMultipleDestinationsDidNotFinish(course: "ICS3U", section: "1"))
    }

    // MARK: - The outcome computed property, against hand-built legs

    @MainActor
    func testOutcomeCountsOnlyFinishedLegsAndExcludesBuildFailures() {
        let runner: MultiDestinationDeployRunner = MultiDestinationDeployRunner()
        var netlifyLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: "")
        )
        netlifyLeg.isFinished = true
        netlifyLeg.succeeded = true

        var cloudflareLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")
        )
        cloudflareLeg.isFinished = true
        cloudflareLeg.succeeded = false

        // Never actually reached — a cancel or an earlier build failure
        // stopped the run before this leg's turn came.
        let folderLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "local_folder", path: NSTemporaryDirectory())
        )

        runner.legs = [netlifyLeg, cloudflareLeg, folderLeg]

        let outcome: MultiDestinationDeployRunner.Outcome = runner.outcome
        XCTAssertTrue(outcome.anySucceeded)
        XCTAssertEqual(outcome.failedDestinations, [
            CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: ""),
        ])
        XCTAssertFalse(outcome.allSucceeded)
    }

    @MainActor
    func testABuildFailureIsNeverCountedAsAFailedDestination() {
        // A build failure means no destination was ever actually
        // attempted — it must not show up in "failedDestinations" (which
        // would wrongly claim Netlify itself rejected the upload).
        let runner: MultiDestinationDeployRunner = MultiDestinationDeployRunner()
        var leg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: "")
        )
        leg.isFinished = true
        leg.buildFailed = true
        runner.legs = [leg]

        let outcome: MultiDestinationDeployRunner.Outcome = runner.outcome
        XCTAssertFalse(outcome.anySucceeded)
        XCTAssertTrue(outcome.failedDestinations.isEmpty)
    }

    @MainActor
    func testActiveRunnerFallsBackSafelyWithNoLegs() {
        let runner: MultiDestinationDeployRunner = MultiDestinationDeployRunner()
        // Must not crash — a fresh orchestrator with nothing run yet.
        _ = runner.activeRunner
        XCTAssertFalse(runner.hasAnyOutput)
    }

    // MARK: - DeployDestinationLinks.succeeded(from:) — the fix for
    // "only Cloudflare, the second deploy target, is visible" once a
    // multi-destination deploy finishes.

    @MainActor
    func testSucceededKeepsOnlyFinishedAndSucceededLegs() {
        var netlifyLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: "")
        )
        netlifyLeg.isFinished = true
        netlifyLeg.succeeded = true

        var cloudflareLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")
        )
        cloudflareLeg.isFinished = true
        cloudflareLeg.succeeded = false

        // Never reached — a cancel or an earlier build failure stopped the
        // run before this leg's turn came.
        let folderLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "local_folder", path: NSTemporaryDirectory())
        )

        let succeeded: [MultiDestinationDeployRunner.Leg] = DeployDestinationLinks.succeeded(
            from: [netlifyLeg, cloudflareLeg, folderLeg]
        )
        XCTAssertEqual(destinationTypes(of: succeeded), ["netlify"])
    }

    @MainActor
    func testSucceededListsEveryDestinationThatActuallyPublished() {
        // The exact bug reported: after a successful deploy to BOTH
        // Netlify and Cloudflare, only the last one to run was visible —
        // this is the property that must hold once both have finished.
        var netlifyLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: "")
        )
        netlifyLeg.isFinished = true
        netlifyLeg.succeeded = true

        var cloudflareLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")
        )
        cloudflareLeg.isFinished = true
        cloudflareLeg.succeeded = true

        let succeeded: [MultiDestinationDeployRunner.Leg] = DeployDestinationLinks.succeeded(
            from: [netlifyLeg, cloudflareLeg]
        )
        XCTAssertEqual(destinationTypes(of: succeeded), ["netlify", "cloudflare_pages"])
    }
}

/// Named after what it produces, not how — used only to keep the
/// assertions above readable without reaching for `.map`.
@MainActor
private func destinationTypes(of legs: [MultiDestinationDeployRunner.Leg]) -> [String] {
    var types: [String] = []
    for leg in legs {
        types.append(leg.destination.type)
    }
    return types
}

private typealias Outcome = MultiDestinationDeployRunner.Outcome
