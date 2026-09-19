import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The progress view must never demand more height than it is given.
/// When it did, the window's SwiftUI content grew past the window and
/// slid out of view — a responsive app drawing a blank window.
///
/// Since issue #211 this file also covers every OTHER panel the section's
/// detail column can put above its console — the finished-deploy result
/// panels and the scheduled-publish notice — because the same fault, in the
/// same column, blanks the same window whichever of them is showing. The two
/// halves measure differently on purpose, and the second half says why.
///
/// The failure class, its four occurrences and the fixes that do NOT work are
/// written up in `documentation/09-mac-app.md` → "A blank window: when a child
/// claims a size the window cannot give".
final class ProgressViewSizeTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func makeRunnerWithOutput(lineCount: Int) -> ScriptRunner {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.deploy
        runner.isRunning = true
        for lineNumber in 1...lineCount {
            runner.receiveOutput("  …uploaded \(lineNumber)/\(lineCount) required files to the site\n")
        }
        return runner
    }

    /// Lays the view out at a fixed window size and reports the height
    /// its content actually claims.
    @MainActor
    func measuredHeight(of view: some View, width: CGFloat, height: CGFloat) -> CGFloat {
        // NOTE: do NOT force a frame on the view itself — that would
        // clamp the very thing under test. Give the HOST a window-sized
        // frame and ask what height the content claims.
        let hostingView: NSHostingView = NSHostingView(rootView: AnyView(view))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    @MainActor
    func testCollapsedProgressViewFitsItsWindow() {
        let runner: ScriptRunner = makeRunnerWithOutput(lineCount: 3000)
        let measured: CGFloat = measuredHeight(
            of: TaskProgressView(runner: runner, title: "Deploying"),
            width: 800,
            height: 720
        )
        XCTAssertLessThanOrEqual(measured, 721, "Collapsed, the progress view claimed \(measured) points in a 720-point window")
    }

    /// Deploy is the only step that PAUSES for input, which shows the
    /// "a question needs your attention" notice. That notice must not
    /// make the header balloon.
    @MainActor
    func testWaitingForInputNoticeDoesNotBalloonTheHeader() {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.deploy
        runner.isRunning = true
        runner.receiveOutput("Enter Netlify site name [ics3u-s4-2026-gordon]: ")
        runner.lastOutputAt = Date(timeIntervalSinceNow: -10)
        XCTAssertTrue(runner.mayBeWaitingForInput(asOf: Date()), "The notice should be showing for this test to mean anything")

        let measured: CGFloat = measuredHeight(
            of: TaskProgressView(runner: runner, title: "Deploying ICS3U-S4"),
            width: 800,
            height: 720
        )
        XCTAssertLessThanOrEqual(measured, 721, "While waiting for input, the header claimed \(measured) points in a 720-point window")
    }

    /// The header must not balloon even if it is briefly offered a
    /// narrow width — long text wrapping in a vertically fixed-size
    /// container is what made the content taller than the window.
    @MainActor
    func testHeaderDoesNotBalloonAtNarrowWidths() {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.deploy
        runner.isRunning = true
        runner.receiveOutput("Enter Netlify site name [ics3u-s4-2026-gordon]: ")
        runner.lastOutputAt = Date(timeIntervalSinceNow: -10)

        let measured: CGFloat = measuredHeight(
            of: TaskProgressView(runner: runner, title: "Deploying ICS3U-S4"),
            width: 120,
            height: 720
        )
        XCTAssertLessThanOrEqual(measured, 721, "At a narrow width the header claimed \(measured) points")
    }

    @MainActor
    func testExpandedDetailsFitTheirWindow() {
        let runner: ScriptRunner = makeRunnerWithOutput(lineCount: 3000)
        let measured: CGFloat = measuredHeight(
            of: TaskProgressView(runner: runner, title: "Deploying", showingDetailsForTesting: true),
            width: 800,
            height: 720
        )
        XCTAssertLessThanOrEqual(measured, 721, "With details open, the progress view claimed \(measured) points in a 720-point window")
    }

    // MARK: - Squeezed, the way a split view measures a column

    /// The most height any of these panels may claim when it is squeezed.
    ///
    /// Chosen from measurement rather than from taste: with the fault present
    /// the folder panel claimed 1,907 points and the scheduled-publish notice
    /// over 1,800, while every panel here answers a squeeze in well under 200
    /// once its text is allowed to respect the proposal. 300 is clear of both
    /// numbers by a wide margin, so a panel that grows an honest extra line
    /// does not turn this suite red and a panel that goes rigid again cannot
    /// slip past it.
    static let squeezedHeightBound: CGFloat = 300

    /// Proposes a narrow width and NO height — which is how a split view
    /// measures a column — and reports the height the view claims.
    ///
    /// Deliberately NOT `fittingSize`, which `measuredHeight(of:width:height:)`
    /// above uses: that asks for the ideal size with no width PROPOSED, so no
    /// sentence ever wraps and a text whose height has been made rigid cannot
    /// show up in it. That is exactly why the folder result panel passed every
    /// test in this file while blanking the whole window the moment a folder
    /// publish said "Done" (issue #211). `CloudSyncNoticeLayoutTests` is the
    /// same measurement, made for the same failure, a release earlier.
    @MainActor
    func heightClaimedWhenSqueezed(of view: some View, width: CGFloat = 1) -> CGFloat {
        let controller: NSHostingController = NSHostingController(rootView: AnyView(view))
        return controller.sizeThatFits(in: NSSize(width: width, height: 0)).height
    }

    /// A deploy that has finished, having published to a folder on this Mac.
    @MainActor
    func makeFinishedFolderDeployRunner() -> ScriptRunner {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.deploy
        runner.receiveOutput("PUBLISHED_FOLDER=/Users/pat/Sites/ics3u/section1\n")
        runner.isRunning = false
        runner.lastExitCode = 0
        return runner
    }

    /// A deploy that has finished, having published to a site online.
    @MainActor
    func makeFinishedSiteDeployRunner() -> ScriptRunner {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.deploy
        runner.receiveOutput("Website is live at: https://ics3u-s1-2026-gordon.netlify.app\n")
        runner.isRunning = false
        runner.lastExitCode = 0
        return runner
    }

    /// The panel that blanked the window: "Your website was deployed to a
    /// folder…", its render note, and Show in Finder.
    @MainActor
    func testTheFolderResultPanelDoesNotBalloonWhenSqueezed() {
        let runner: ScriptRunner = makeFinishedFolderDeployRunner()
        XCTAssertNotNil(runner.publishedFolderURL, "The folder panel must actually be showing for this test to mean anything")
        let claimed: CGFloat = heightClaimedWhenSqueezed(
            of: TaskProgressView(runner: runner, title: "Deploying ADA1O-S1")
        )
        XCTAssertLessThanOrEqual(
            claimed,
            ProgressViewSizeTests.squeezedHeightBound,
            "Squeezed, the folder result panel claimed \(claimed) points — the window's content will grow past the window and the whole interface, sidebar included, slides out of view"
        )
    }

    /// The Netlify / Cloudflare panel, which was safe when #211 was found.
    /// Pinned so it stays that way.
    @MainActor
    func testTheSiteLinkPanelDoesNotBalloonWhenSqueezed() {
        let runner: ScriptRunner = makeFinishedSiteDeployRunner()
        XCTAssertNotNil(runner.publishedSiteURL, "The site-link panel must actually be showing for this test to mean anything")
        let claimed: CGFloat = heightClaimedWhenSqueezed(
            of: TaskProgressView(runner: runner, title: "Deploying ADA1O-S1")
        )
        XCTAssertLessThanOrEqual(
            claimed,
            ProgressViewSizeTests.squeezedHeightBound,
            "Squeezed, the site-link panel claimed \(claimed) points"
        )
    }

    /// The multi-destination panel — every succeeded destination's own link,
    /// in the same spot and the same column.
    @MainActor
    func testTheMultiDestinationLinksDoNotBalloonWhenSqueezed() {
        var siteLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: "")
        )
        siteLeg.runner = makeFinishedSiteDeployRunner()
        siteLeg.isFinished = true
        siteLeg.succeeded = true

        var folderLeg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "local_folder", path: "/Users/pat/Sites/ics3u/section1")
        )
        folderLeg.runner = makeFinishedFolderDeployRunner()
        folderLeg.isFinished = true
        folderLeg.succeeded = true

        let claimed: CGFloat = heightClaimedWhenSqueezed(
            of: DeployDestinationLinks(legs: [siteLeg, folderLeg])
        )
        XCTAssertLessThanOrEqual(
            claimed,
            ProgressViewSizeTests.squeezedHeightBound,
            "Squeezed, the multi-destination links claimed \(claimed) points"
        )
    }

    /// The notice a scheduled publish leaves behind, in the state Russell
    /// photographed on 2026-09-19: it worked, it went to two destinations,
    /// and the sentence naming both of them is the longest this notice says.
    @MainActor
    func testTheScheduledPublishSuccessNoticeDoesNotBalloonWhenSqueezed() {
        let outcome: ScheduledPublishOutcome.Stopped = ScheduledPublishOutcome.Stopped(
            kind: .succeeded,
            destination: "Netlify, Cloudflare Pages",
            when: Date(timeIntervalSince1970: 1_758_297_000)
        )
        let claimed: CGFloat = heightClaimedWhenSqueezed(
            of: ScheduledPublishNoticeView(outcome: outcome, course: "ICS4U", sectionNumber: 1, dismiss: {})
        )
        XCTAssertLessThanOrEqual(
            claimed,
            ProgressViewSizeTests.squeezedHeightBound,
            "Squeezed, the scheduled-publish success notice claimed \(claimed) points — a teacher opening that section is shown a blank window"
        )
    }

    /// The same notice in the state it was written for: an overnight publish
    /// that did not get through, whose sentence is longer still.
    @MainActor
    func testTheScheduledPublishStoppedNoticeDoesNotBalloonWhenSqueezed() {
        let outcome: ScheduledPublishOutcome.Stopped = ScheduledPublishOutcome.Stopped(
            kind: .neededAnAnswer,
            destination: "Netlify",
            when: Date(timeIntervalSince1970: 1_758_297_000)
        )
        let claimed: CGFloat = heightClaimedWhenSqueezed(
            of: ScheduledPublishNoticeView(outcome: outcome, course: "ICS4U", sectionNumber: 1, dismiss: {})
        )
        XCTAssertLessThanOrEqual(
            claimed,
            ProgressViewSizeTests.squeezedHeightBound,
            "Squeezed, the stopped scheduled-publish notice claimed \(claimed) points"
        )
    }

    /// Proposes a real column width and a whole window's height, and reports
    /// the height the view actually RENDERS in — as opposed to the minimum
    /// `heightClaimedWhenSqueezed` asks for.
    @MainActor
    func heightRendered(of view: some View, width: CGFloat) -> CGFloat {
        let controller: NSHostingController = NSHostingController(rootView: AnyView(view))
        return controller.sizeThatFits(in: NSSize(width: width, height: 850)).height
    }

    /// Removing the rigidity must not have cost the teacher the sentence.
    /// At a NARROW but real column width the panel has to render TALLER than
    /// at a wide one — that is what wrapping in full looks like. A
    /// `lineLimit` "fix" would make these two numbers the same, and half a
    /// sentence with an ellipsis explains nothing. Measured on 2026-09-19:
    /// 187 points at 420 wide, 156 at 700, 141 at 900 and at 1300.
    @MainActor
    func testTheFolderRenderNoteStillWrapsInFullAtRealWidths() {
        let wideRunner: ScriptRunner = makeFinishedFolderDeployRunner()
        let atNineHundred: CGFloat = heightRendered(
            of: TaskProgressView(runner: wideRunner, title: "Deploying ADA1O-S1"),
            width: 900
        )
        let narrowRunner: ScriptRunner = makeFinishedFolderDeployRunner()
        let atFourTwenty: CGFloat = heightRendered(
            of: TaskProgressView(runner: narrowRunner, title: "Deploying ADA1O-S1"),
            width: 420
        )
        XCTAssertGreaterThan(
            atFourTwenty,
            atNineHundred,
            "The panel rendered \(atFourTwenty) points at 420 wide and \(atNineHundred) at 900 — the note is not wrapping, so it is being truncated"
        )
        XCTAssertLessThanOrEqual(
            atFourTwenty,
            ProgressViewSizeTests.squeezedHeightBound,
            "At 420 points wide the folder panel rendered \(atFourTwenty) points"
        )
    }

    /// The same, for the scheduled-publish notice. Measured on 2026-09-19:
    /// 137 points at 420 wide, 73 at 900 and at 1300.
    @MainActor
    func testTheScheduledPublishNoticeStillWrapsInFullAtRealWidths() {
        let outcome: ScheduledPublishOutcome.Stopped = ScheduledPublishOutcome.Stopped(
            kind: .neededAnAnswer,
            destination: "Netlify",
            when: Date(timeIntervalSince1970: 1_758_297_000)
        )
        let atNineHundred: CGFloat = heightRendered(
            of: ScheduledPublishNoticeView(outcome: outcome, course: "ICS4U", sectionNumber: 1, dismiss: {}),
            width: 900
        )
        let atFourTwenty: CGFloat = heightRendered(
            of: ScheduledPublishNoticeView(outcome: outcome, course: "ICS4U", sectionNumber: 1, dismiss: {}),
            width: 420
        )
        XCTAssertGreaterThan(
            atFourTwenty,
            atNineHundred,
            "The notice rendered \(atFourTwenty) points at 420 wide and \(atNineHundred) at 900 — its sentence is not wrapping, so it is being truncated"
        )
        XCTAssertLessThanOrEqual(
            atFourTwenty,
            ProgressViewSizeTests.squeezedHeightBound,
            "At 420 points wide the notice rendered \(atFourTwenty) points"
        )
    }

    // MARK: - Where the notice sits in the window

    /// Proposes a whole window and reports the height the content claims of it.
    ///
    /// This is the measurement that says whether something FILLS: the detail
    /// column is a `ZStack`, and a `ZStack` centres a child that claims less
    /// height than it offered. A base layer that claims all of it has nothing
    /// left to be centred by, so what is at the top of that layer — the
    /// scheduled-publish notice — is at the top of the window.
    @MainActor
    func heightClaimedOfAWholeWindow(of view: some View, width: CGFloat, height: CGFloat) -> CGFloat {
        let controller: NSHostingController = NSHostingController(rootView: AnyView(view))
        return controller.sizeThatFits(in: NSSize(width: width, height: height)).height
    }

    /// Nothing running, and a notice from last night's scheduled publish: the
    /// notice belongs under the toolbar, not floating in the middle.
    ///
    /// Russell photographed the middle on 2026-09-19 — the band's top edge
    /// about 470 points down a 1,254-point window, with nothing above it. The
    /// cause was that the base layer hugged its content: measured here with the
    /// fault in place, it claimed **246 points** of the 720 offered (189 of them
    /// the placeholder's), so the `ZStack` centred it and put 237 points of
    /// nothing above the notice.
    ///
    /// What this CAN pin is the filling, which is the structural cause; where
    /// the pixels land is confirmed by eye against the real app, and by the
    /// screenshot in the write-up. The console branch of the same layer has
    /// always filled — `consoleArea` ends in a `Spacer(minLength: 0)` — which
    /// is why the notice sat correctly whenever anything was running.
    @MainActor
    func testTheEmptySectionFillsItsWindowSoTheNoticeSitsAtTheTop() {
        let outcome: ScheduledPublishOutcome.Stopped = ScheduledPublishOutcome.Stopped(
            kind: .succeeded,
            destination: "Netlify, Cloudflare Pages",
            when: Date(timeIntervalSince1970: 1_758_297_000)
        )
        let baseLayer = VStack(spacing: 0) {
            ScheduledPublishNoticeView(
                outcome: outcome, course: "ICS4U", sectionNumber: 1, dismiss: {}
            )
            NoPreviewPlaceholderView(deploysToLocalFolder: false)
        }
        let claimed: CGFloat = heightClaimedOfAWholeWindow(of: baseLayer, width: 800, height: 720)
        XCTAssertGreaterThanOrEqual(
            claimed,
            719,
            "Offered a 720-point window, the section's base layer claimed only \(claimed) points, so the stack around it centres the notice instead of leaving it under the toolbar"
        )
    }

    /// The placeholder is what does the filling, and it must keep doing it.
    @MainActor
    func testThePlaceholderFillsTheHeightItIsOffered() {
        let claimed: CGFloat = heightClaimedOfAWholeWindow(
            of: NoPreviewPlaceholderView(deploysToLocalFolder: true), width: 800, height: 720
        )
        XCTAssertGreaterThanOrEqual(
            claimed,
            719,
            "The 'No Preview Running' placeholder claimed \(claimed) points of the 720 it was offered"
        )
    }

    /// Filling must not mean RIGID — that is the #211 failure class, and this
    /// is the same squeeze the notices above are measured under.
    @MainActor
    func testThePlaceholderDoesNotBalloonWhenSqueezed() {
        let claimed: CGFloat = heightClaimedWhenSqueezed(
            of: NoPreviewPlaceholderView(deploysToLocalFolder: false)
        )
        XCTAssertLessThanOrEqual(
            claimed,
            ProgressViewSizeTests.squeezedHeightBound,
            "Squeezed, the 'No Preview Running' placeholder claimed \(claimed) points"
        )
    }
}
