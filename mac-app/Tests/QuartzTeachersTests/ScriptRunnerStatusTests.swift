import XCTest
@testable import QuartzTeachers

/// The friendly progress presentation: phase labels derived from output
/// markers, and the stalled-prompt detection behind the "a question
/// needs your attention" notice.
final class ScriptRunnerStatusTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testPhaseLabelFollowsTheLatestMarker() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput( "⬇️  Image not found locally. Pulling rwhgrwhg/teaching-quartz …\n")
        XCTAssertEqual(runner.friendlyPhase, "Downloading components (first time can take a few minutes)…")

        runner.receiveOutput( "📦 Installing dependencies...\n")
        XCTAssertEqual(runner.friendlyPhase, "Preparing your site (first time can take a few minutes)…")

        runner.receiveOutput( "🚀 Launching Quartz preview on http://localhost:8081\n")
        XCTAssertEqual(runner.friendlyPhase, "Starting the preview…")
    }

    /// The launchers' "Starting Colima…" became "Starting the website
    /// builder…" (#228). If the marker here had not moved with it, the phase
    /// would fall back to whatever came before — silently.
    @MainActor
    func testStartingTheWebsiteBuilderIsAPhase() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput( "🐳 Setting up this Mac…\n")
        runner.receiveOutput( "▶️  Starting the website builder…\n")
        XCTAssertEqual(runner.friendlyPhase, "Starting up (first time can take a few minutes)…")
    }

    @MainActor
    func testDefaultPhaseIsWorking() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput( "some unremarkable output\n")
        XCTAssertEqual(runner.friendlyPhase, "Working…")
    }

    @MainActor
    func testPublishedSiteLinkIsFoundInDeployOutput() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(" Netlify site created.\n")
        runner.receiveOutput(" Admin: https://app.netlify.com/sites/ics3u-s1-2026-gordon\n")
        runner.receiveOutput(" Live URL: https://ics3u-s1-2026-gordon.netlify.app\n")
        runner.receiveOutput("✅ Deploy complete.\n")
        XCTAssertEqual(runner.publishedSiteURL?.absoluteString, "https://ics3u-s1-2026-gordon.netlify.app", "The teacher's site should be offered, not Netlify's admin page")
    }

    @MainActor
    func testRepeatPublishOfAnExistingSiteStillOffersTheLink() {
        // A site that already exists is quoted from its saved record,
        // which holds a plain-http address rather than the ssl one.
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(" Using existing Netlify site for this section.\n")
        runner.receiveOutput(" Site: http://ics3u-s1-2025-gordon.netlify.app\n")
        runner.receiveOutput(" Netlify requires 3 file(s) for this deploy.\n")
        runner.receiveOutput("✅ Delta deploy created (production).\n")
        runner.receiveOutput(" Site URL: http://ics3u-s1-2025-gordon.netlify.app\n")
        XCTAssertEqual(runner.publishedSiteURL?.absoluteString, "https://ics3u-s1-2025-gordon.netlify.app")
    }

    @MainActor
    func testACustomAddressIsOfferedWhenAnnounced() {
        let found = ScriptRunner.publishedSiteURL(in: " Site URL: https://cs.example.com\n✅ Deploy complete.")
        XCTAssertEqual(found?.absoluteString, "https://cs.example.com", "A site on its own domain is still the site")
    }

    @MainActor
    func testTheDashboardIsNeverOfferedAsTheSite() {
        let found = ScriptRunner.publishedSiteURL(in: " Admin: https://app.netlify.com/projects/ics3u-s1-2025-gordon\n")
        XCTAssertNil(found)
    }

    @MainActor
    func testNoSiteLinkWhenNothingWasPublished() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("Building your site\n")
        XCTAssertNil(runner.publishedSiteURL)
    }

    @MainActor
    func testDefaultAnswerMovesOutOfTheQuestion() {
        let asked = ScriptRunner.separateDefaultAnswer(from: "Enter Netlify site name [ics3u-s3-2026-gordon]:")
        XCTAssertEqual(asked.question, "Enter Netlify site name:")
        XCTAssertEqual(asked.suggestedAnswer, "ics3u-s3-2026-gordon")
    }

    @MainActor
    func testLabelledDefaultAnswerMovesOutOfTheQuestion() {
        let asked = ScriptRunner.separateDefaultAnswer(from: "Your name [Default: Russell Gordon]:")
        XCTAssertEqual(asked.question, "Your name:")
        XCTAssertEqual(asked.suggestedAnswer, "Russell Gordon")
    }

    @MainActor
    func testRetryPromptDropsTheTypistsEscapeHatch() {
        let asked = ScriptRunner.separateDefaultAnswer(from: "Choose a different Netlify site name (or 'q' to cancel) [ics3u-s3-2026-gordon-01]:")
        XCTAssertEqual(asked.question, "Choose a different Netlify site name:")
        XCTAssertEqual(asked.suggestedAnswer, "ics3u-s3-2026-gordon-01")
    }

    @MainActor
    func testTheScriptsOwnCancelKeyIsRemembered() {
        let asked = ScriptRunner.separateDefaultAnswer(from: "Choose a different Netlify site name (or 'q' to cancel) [ics3u-s3-2026-gordon-01]:")
        XCTAssertEqual(asked.cancelToken, "q", "The key the script accepts must survive being hidden from the wording")
    }

    @MainActor
    func testNoCancelKeyWhenTheScriptOffersNone() {
        let asked = ScriptRunner.separateDefaultAnswer(from: "Enter your Netlify access token:")
        XCTAssertEqual(asked.cancelToken, "")
    }

    @MainActor
    func testCancellingWithoutAWayOutStopsTheTask() {
        let runner: ScriptRunner = ScriptRunner()
        runner.isAwaitingInput = true
        runner.pendingCancelToken = ""
        runner.cancelPendingQuestion()
        XCTAssertFalse(runner.isAwaitingInput)
        XCTAssertTrue(runner.wasCancelled, "Cancel must always mean the task stops")
    }

    @MainActor
    func testStoppingOnPurposeIsNotAFailure() {
        let runner: ScriptRunner = ScriptRunner()
        runner.isRunning = true
        runner.stopByUser()
        XCTAssertTrue(runner.wasStoppedByUser, "A preview the teacher stopped exits non-zero by design")
        XCTAssertFalse(runner.wasCancelled, "Stopping is not the same as backing out of a question")
    }

    @MainActor
    func testCancellingMarksTheTaskAsCancelled() {
        let runner: ScriptRunner = ScriptRunner()
        runner.isAwaitingInput = true
        runner.pendingCancelToken = "q"
        runner.cancelPendingQuestion()
        XCTAssertTrue(runner.wasCancelled)
        XCTAssertFalse(runner.isAwaitingInput)
    }

    @MainActor
    func testInformativeParentheticalsSurvive() {
        let asked = ScriptRunner.separateDefaultAnswer(from: "Overwrite the existing folder (y/n)?")
        XCTAssertEqual(asked.question, "Overwrite the existing folder (y/n)?")
    }

    @MainActor
    func testChoicesStayInTheQuestion() {
        let asked = ScriptRunner.separateDefaultAnswer(from: "Continue? [Y/n]")
        XCTAssertEqual(asked.question, "Continue? [Y/n]")
        XCTAssertEqual(asked.suggestedAnswer, "")
    }

    @MainActor
    func testQuestionWithoutADefaultIsUnchanged() {
        let asked = ScriptRunner.separateDefaultAnswer(from: "Enter your Netlify access token:")
        XCTAssertEqual(asked.question, "Enter your Netlify access token:")
        XCTAssertEqual(asked.suggestedAnswer, "")
    }

    @MainActor
    func testQuestionShapesAreRecognised() {
        XCTAssertTrue(ScriptRunner.looksLikeQuestion("Enter Netlify site name [ics3u-s1-2026-gordon]:"))
        XCTAssertTrue(ScriptRunner.looksLikeQuestion("Install the Example Course now? (y/n) [Default: n]"))
        XCTAssertTrue(ScriptRunner.looksLikeQuestion(">"))
        XCTAssertFalse(ScriptRunner.looksLikeQuestion("Emitting files"))
        XCTAssertFalse(ScriptRunner.looksLikeQuestion("Uploaded 42 files"))
    }

    @MainActor
    func testSendingAnAnswerClearsTheQuestion() {
        let runner: ScriptRunner = ScriptRunner()
        runner.isAwaitingInput = true
        runner.pendingQuestion = "Enter Netlify site name:"
        runner.send(line: "my-site")
        XCTAssertFalse(runner.isAwaitingInput, "Answering should dismiss the question")
    }

    @MainActor
    func testNewOutputMeansTheScriptIsNoLongerWaiting() {
        let runner: ScriptRunner = ScriptRunner()
        runner.isRunning = true
        runner.isAwaitingInput = true
        runner.receiveOutput("Uploading your pages\n")
        XCTAssertFalse(runner.isAwaitingInput, "Fresh output means it is working again")
    }

    @MainActor
    func testStalledPromptIsDetectedOnlyWhenQuietAndPromptShaped() {
        let runner: ScriptRunner = ScriptRunner()
        runner.isRunning = true
        runner.receiveOutput( "Paste Netlify token: ")

        // Fresh output: not yet a stall.
        runner.lastOutputAt = Date()
        XCTAssertFalse(runner.mayBeWaitingForInput(asOf: Date()))

        // Quiet for five seconds at a prompt-shaped line: stall.
        runner.lastOutputAt = Date(timeIntervalSinceNow: -5)
        XCTAssertTrue(runner.mayBeWaitingForInput(asOf: Date()))

        // Quiet but mid-build (no prompt shape): not a stall.
        runner.receiveOutput( "\nEmitting files")
        runner.lastOutputAt = Date(timeIntervalSinceNow: -5)
        XCTAssertFalse(runner.mayBeWaitingForInput(asOf: Date()))

        // Not running: never a stall.
        runner.isRunning = false
        XCTAssertFalse(runner.mayBeWaitingForInput(asOf: Date()))
    }

    @MainActor
    func testDefaultAnswerPromptCountsAsPromptShape() {
        let runner: ScriptRunner = ScriptRunner()
        runner.isRunning = true
        runner.receiveOutput( "Install the Example Course now? (y/n) [Default: n]")
        runner.lastOutputAt = Date(timeIntervalSinceNow: -5)
        XCTAssertTrue(runner.mayBeWaitingForInput(asOf: Date()))
    }
}

/// Reading the preview's announced address.
final class PreviewAddressTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testTheAnnouncedAddressIsRead() {
        let output: String = "🌐 Preview will be available at: http://localhost:8091/\n"
        XCTAssertEqual(ScriptRunner.previewAddress(in: output)?.absoluteString, "http://127.0.0.1:8091/")
    }

    @MainActor
    func testTheLastAnnouncementWins() {
        let output: String = """
        🌐 Preview will be available at: http://localhost:8081/
        🌐 Preview will be available at: http://localhost:8092/
        """
        XCTAssertEqual(ScriptRunner.previewAddress(in: output)?.port, 8092)
    }

    @MainActor
    func testOrdinaryOutputAnnouncesNothing() {
        XCTAssertNil(ScriptRunner.previewAddress(in: "🚀 Starting container if needed...\n"))
    }

    // MARK: - Slow-step reassurance

    @MainActor
    func testAQuietStepShowsALiveStillWorkingTimer() {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.courseCreation
        runner.isRunning = true
        let now: Date = Date()

        // Fresh output: the plain label, no timer.
        runner.lastOutputAt = now
        XCTAssertFalse(runner.milestoneText(asOf: now).contains("still working"))

        // Quiet for eight seconds: the timer appears and counts.
        runner.lastOutputAt = now.addingTimeInterval(-8)
        XCTAssertTrue(runner.milestoneText(asOf: now).hasSuffix("still working… (8s)"),
                      "got: \(runner.milestoneText(asOf: now))")
    }

    @MainActor
    func testTheTimerStartsFromTheTaskNotFromTheRunnersBirth() throws {
        // A runner is built when its sheet or window appears, which can be
        // minutes before the teacher presses the button — the whole time
        // spent filling in the wizard, for instance. The quiet timer must
        // measure silence from THIS task's start, or the very first step
        // opens at "still working… (35s)" and reads like a stall.
        let fileManager: FileManager = FileManager.default
        let folder: URL = fileManager.temporaryDirectory
            .appendingPathComponent("runner-timer-\(UUID().uuidString)")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: folder) }
        try Data("exit 0\n".utf8).write(to: folder.appendingPathComponent("setup.sh"))

        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.courseCreation
        // Stand in for a wizard that sat open for a while before Create.
        runner.lastOutputAt = Date(timeIntervalSinceNow: -35)

        runner.run(scriptNamed: "setup.sh", arguments: [], workingDirectory: folder)

        XCTAssertNil(runner.launchProblem, "the stand-in script should launch")
        XCTAssertLessThan(
            Date().timeIntervalSince(runner.lastOutputAt), 2,
            "starting a task resets the quiet clock"
        )
        XCTAssertFalse(
            runner.milestoneText(asOf: Date()).contains("still working"),
            "a task that just started is not a stalled task"
        )
        runner.terminate()
    }

    @MainActor
    func testAStepWithItsOwnCountNeverShowsTheTimer() {
        // A step reporting "3 of 8" IS visibly moving — the count wins.
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.courseCreation
        runner.isRunning = true
        runner.stepDetail = "3 of 8"
        let now: Date = Date()
        runner.lastOutputAt = now.addingTimeInterval(-30)
        let text: String = runner.milestoneText(asOf: now)
        XCTAssertTrue(text.hasSuffix("3 of 8"))
        XCTAssertFalse(text.contains("still working"))
    }

    @MainActor
    func testAFinishedTaskShowsNoTimerHoweverQuiet() {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.courseCreation
        runner.isRunning = false
        let now: Date = Date()
        runner.lastOutputAt = now.addingTimeInterval(-120)
        XCTAssertFalse(runner.milestoneText(asOf: now).contains("still working"))
    }

    // MARK: - Published folder

    @MainActor
    func testThePublishedFolderIsReadFromTheOutput() {
        let output: String = """
        ✅ Published: 3 file(s) updated.
           Folder: /Users/pat/Sites/ics3u/section1
        PUBLISHED_FOLDER=/Users/pat/Sites/ics3u/section1
        """
        XCTAssertEqual(ScriptRunner.publishedFolderURL(in: output)?.path,
                       "/Users/pat/Sites/ics3u/section1")
    }

    @MainActor
    func testANetlifyDeployAnnouncesNoFolder() {
        XCTAssertNil(ScriptRunner.publishedFolderURL(in: "Site URL: https://example.netlify.app"))
    }

    // MARK: - Cancellation by user

    @MainActor
    func testCancelByUserSetsCancellationFlagsAndRunsCleanup() {
        let runner: ScriptRunner = ScriptRunner()
        var cleanupRan: Bool = false

        XCTAssertFalse(runner.wasCancelled)
        XCTAssertFalse(runner.wasStoppedByUser)

        runner.cancelByUser(onCleanup: {
            cleanupRan = true
        })

        XCTAssertTrue(runner.wasCancelled, "Cancelling by user must mark the run as cancelled")
        XCTAssertTrue(runner.wasStoppedByUser, "Cancelling by user must mark the run as stopped by user")
        XCTAssertTrue(cleanupRan, "The cleanup closure must be executed on cancel")
    }
}
