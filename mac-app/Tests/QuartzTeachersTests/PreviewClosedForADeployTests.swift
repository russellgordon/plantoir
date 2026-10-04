import XCTest
@testable import QuartzTeachers

/// A preview ended by ANOTHER program's deploy — an outside assistant's
/// `deploy_section`, whose build ends that section's serving preview
/// (`build_site.stop_preview_serving`), or a publish set for later — is shown
/// as "Closed for a deploy", not as a failure (#433's stack review, item 6:
/// the teacher asked for that deploy). Traced before the fix: the killed
/// server made the Python parent raise, `preview.sh` exited non-zero, and the
/// window's console said "Something went wrong" in red and opened the raw
/// output.
@MainActor
final class PreviewClosedForADeployTests: XCTestCase {

    // MARK: - Stored properties

    var folder: URL = URL(fileURLWithPath: "/")

    var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Setting up

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("closed-for-deploy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A stand-in for a serving preview whose server was killed.
        try Data("exit 1\n".utf8).write(to: folder.appendingPathComponent("preview.sh"))
        previousTrail = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folder.appendingPathComponent("trail"))
    }

    override func tearDown() async throws {
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Tests

    /// MUST FAIL without the check in `finishRun`.
    func testAPreviewEndedWhileAnotherProgramBuildsIsClosedNotFailed() async {
        let runner: ScriptRunner = ScriptRunner()
        runner.endedForAnotherProgramsBuild = {
            return true
        }
        runner.run(scriptNamed: "preview.sh", arguments: ["ICS3U", "1"], workingDirectory: folder)
        _ = await runner.waitUntilFinished()
        XCTAssertEqual(runner.lastExitCode, 1)
        XCTAssertTrue(runner.wasClosedForADeploy)
        XCTAssertEqual(
            ScriptRunner.outcomeDescription(
                exitCode: 1, wasStoppedByUser: false, wasCancelled: false, wasClosedForADeploy: true
            ),
            ScriptRunner.closedForADeployOutcome
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(ScriptRunner.closedForADeployOutcome.lowercased()), trail)
    }

    /// The control: with nothing building elsewhere, a preview that ends
    /// non-zero is still a failure.
    func testAPreviewEndedWithNothingBuildingElsewhereIsStillAFailure() async {
        let runner: ScriptRunner = ScriptRunner()
        runner.endedForAnotherProgramsBuild = {
            return false
        }
        runner.run(scriptNamed: "preview.sh", arguments: ["ICS3U", "1"], workingDirectory: folder)
        _ = await runner.waitUntilFinished()
        XCTAssertFalse(runner.wasClosedForADeploy)
        XCTAssertEqual(
            ScriptRunner.outcomeDescription(exitCode: 1, wasStoppedByUser: false, wasCancelled: false),
            "Failed (exit 1)"
        )
    }

    /// The section window wires the check for its preview, from the leases.
    func testTheSectionWindowAsksTheLeasesWhenItsPreviewEnds() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/Views/Section/SectionDetailView.swift")
        let source: String = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("previewRunner.endedForAnotherProgramsBuild = {"))
    }
}
