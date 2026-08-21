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
}

private typealias Outcome = MultiDestinationDeployRunner.Outcome
