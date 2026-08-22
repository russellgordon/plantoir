import XCTest
@testable import QuartzTeachers

/// A multi-destination deploy's "Show details" console: every destination
/// that has produced output so far, concatenated in deploy order — not
/// just whichever leg happens to be running right now.
final class TaskConsoleViewTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testWithNoOtherLegsItFallsBackToThePlainRunnerTranscript() {
        let runner: ScriptRunner = ScriptRunner()
        runner.transcript.append(rawText: "Building…\r\n")

        XCTAssertEqual(
            TaskConsoleView.combinedTranscriptText(runner: runner, allLegs: nil),
            "Building…"
        )
    }

    @MainActor
    func testASingleLegListIsTreatedTheSameAsNilRatherThanAddingAHeading() {
        var leg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: "")
        )
        leg.runner.transcript.append(rawText: "Building…\r\n")

        XCTAssertEqual(
            TaskConsoleView.combinedTranscriptText(runner: leg.runner, allLegs: [leg]),
            "Building…",
            "The overwhelming majority of deploys — exactly one destination — must look byte-for-byte as they always have"
        )
    }

    @MainActor
    func testNothingHasRunYetShowsStarting() {
        let runner: ScriptRunner = ScriptRunner()
        let netlifyLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: "")
        )
        let cloudflareLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")
        )

        XCTAssertEqual(
            TaskConsoleView.combinedTranscriptText(runner: runner, allLegs: [netlifyLeg, cloudflareLeg]),
            "Starting…"
        )
    }

    /// The actual bug reported: once the second destination started, the
    /// first destination's own console output vanished from view — the
    /// combined text must keep BOTH, in the order they ran.
    @MainActor
    func testTheFirstLegsOutputSurvivesOnceTheSecondLegHasStarted() {
        let netlifyLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: "")
        )
        netlifyLeg.runner.transcript.append(rawText: "Deployed to Netlify.\r\n")

        let cloudflareLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")
        )
        cloudflareLeg.runner.transcript.append(rawText: "Uploading to Cloudflare…\r\n")

        let combined: String = TaskConsoleView.combinedTranscriptText(
            runner: cloudflareLeg.runner, allLegs: [netlifyLeg, cloudflareLeg]
        )

        XCTAssertTrue(combined.contains("Deployed to Netlify."), "The first destination's own output must not vanish")
        XCTAssertTrue(combined.contains("Uploading to Cloudflare…"))
        XCTAssertTrue(combined.contains("Netlify"), "Each section is headed by its own destination's name")
        XCTAssertTrue(combined.contains("Cloudflare Pages"))
        XCTAssertLessThan(
            try XCTUnwrap(combined.range(of: "Deployed to Netlify.")).lowerBound,
            try XCTUnwrap(combined.range(of: "Uploading to Cloudflare…")).lowerBound,
            "Sections stay in deploy order"
        )
    }

    /// A destination the run has not reached yet (stopped early by a
    /// cancel, or an earlier failed shared build) has no output — it must
    /// not appear as an empty, confusing section.
    @MainActor
    func testALegTheRunHasNotReachedYetIsLeftOutEntirely() {
        let netlifyLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: "")
        )
        netlifyLeg.runner.transcript.append(rawText: "Deployed to Netlify.\r\n")

        // Never reached.
        let folderLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "local_folder", path: NSTemporaryDirectory())
        )

        let combined: String = TaskConsoleView.combinedTranscriptText(
            runner: netlifyLeg.runner, allLegs: [netlifyLeg, folderLeg]
        )
        XCTAssertFalse(combined.contains(NSTemporaryDirectory()), "A leg with no output yet must not add its own empty heading")
    }
}
