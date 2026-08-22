import XCTest
@testable import QuartzTeachers

/// Which task the console area is about.
final class ConsoleFocusTests: XCTestCase {

    // MARK: - Stored properties

    let earlier: Date = Date(timeIntervalSince1970: 1_000)
    let later: Date = Date(timeIntervalSince1970: 2_000)

    // MARK: - Functions

    @MainActor
    func testAPreviewStartedAfterAPublishTakesTheSpace() {
        let showsDeploy: Bool = SectionDetailView.showsDeployProgress(
            previewIsRunning: true,
            deployIsRunning: false,
            previewStartedAt: later,
            deployStartedAt: earlier
        )
        XCTAssertFalse(showsDeploy, "A finished publish must not linger while a preview is being prepared")
    }

    @MainActor
    func testAFinishedPublishStaysUntilSomethingElseStarts() {
        let showsDeploy: Bool = SectionDetailView.showsDeployProgress(
            previewIsRunning: false,
            deployIsRunning: false,
            previewStartedAt: earlier,
            deployStartedAt: later
        )
        XCTAssertTrue(showsDeploy, "The publish's result — including the link to the live site — is still the news")
    }

    @MainActor
    func testARunningPublishWins() {
        let showsDeploy: Bool = SectionDetailView.showsDeployProgress(
            previewIsRunning: false,
            deployIsRunning: true,
            previewStartedAt: later,
            deployStartedAt: earlier
        )
        XCTAssertTrue(showsDeploy)
    }

    @MainActor
    func testDeployRunningWhilePreviewIsStoppedShowsDeploy() {
        let showsDeploy: Bool = SectionDetailView.showsDeployProgress(
            previewIsRunning: false,
            deployIsRunning: true,
            previewStartedAt: earlier,
            deployStartedAt: later
        )
        XCTAssertTrue(showsDeploy, "A deploy running after preview stopped must take the console area")
    }

    @MainActor
    func testThePreviewPanelStopsClaimingToBePreparingOne() {
        XCTAssertEqual(
            SectionDetailView.previewTaskTitle(isPreparing: true, sectionName: "ICS3U-S5"),
            "Preparing the preview of ICS3U-S5"
        )
        XCTAssertEqual(
            SectionDetailView.previewTaskTitle(isPreparing: false, sectionName: "ICS3U-S5"),
            "Preview of ICS3U-S5"
        )
    }

    @MainActor
    func testNothingRunYetShowsThePreviewSide() {
        let showsDeploy: Bool = SectionDetailView.showsDeployProgress(
            previewIsRunning: false,
            deployIsRunning: false,
            previewStartedAt: nil,
            deployStartedAt: nil
        )
        XCTAssertFalse(showsDeploy)
    }

    // MARK: - deployProgressTitle — the destination-name suffix must not
    // outlive the run it describes, once more than one destination exists.

    @MainActor
    func testASingleDestinationDeployNeverNamesADestination() {
        XCTAssertEqual(
            SectionDetailView.deployProgressTitle(
                sectionName: "MCV4U-S1",
                isRunning: true,
                legCount: 1,
                currentDestinationDescription: "Netlify"
            ),
            "Deploying MCV4U-S1"
        )
    }

    @MainActor
    func testARunningMultiDestinationDeployNamesTheCurrentOne() {
        XCTAssertEqual(
            SectionDetailView.deployProgressTitle(
                sectionName: "MCV4U-S1",
                isRunning: true,
                legCount: 2,
                currentDestinationDescription: "Cloudflare Pages"
            ),
            "Deploying MCV4U-S1 — Cloudflare Pages"
        )
    }

    @MainActor
    func testAFinishedMultiDestinationDeployDropsTheLastDestinationsName() {
        // The actual bug reported: the title kept naming Cloudflare (the
        // destination that happened to run last) even after Netlify had
        // ALSO deployed successfully — reading as though only one
        // destination had been published to. The checklist above already
        // names each destination with its own checkmark, and
        // DeployDestinationLinks lists every live link, so the finished
        // title should not single one out.
        XCTAssertEqual(
            SectionDetailView.deployProgressTitle(
                sectionName: "MCV4U-S1",
                isRunning: false,
                legCount: 2,
                currentDestinationDescription: "Cloudflare Pages"
            ),
            "Deploying MCV4U-S1"
        )
    }
}
