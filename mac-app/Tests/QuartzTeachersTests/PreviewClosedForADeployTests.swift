import XCTest
@testable import QuartzTeachers

/// A preview ended by ANOTHER program's deploy — an outside assistant's
/// `deploy_section`, or a publish set for later, whose build kills that
/// section's serving preview (`build_site.stop_preview_serving`) — is shown as
/// "Closed for a deploy", not as a failure (#433's stack review, item 6), and
/// ONLY then (the bb8fbe12 ruling): it had been serving, its output shows the
/// server killed that way, and another program holds a build lease on the
/// course. Every other end is a failure, as before.
@MainActor
final class PreviewClosedForADeployTests: XCTestCase {

    // MARK: - Stored properties

    var folder: URL = URL(fileURLWithPath: "/")

    var previousTrail: ProblemReportStore = ActivityTrail.store

    var other: Process?

    let killedOutput: String = "Traceback (most recent call last):\n"
        + "subprocess.CalledProcessError: Command '['node', 'bootstrap-cli.mjs']' died with <Signals.SIGKILL: 9>.\n"

    // MARK: - Setting up

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("closed-for-deploy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("courses"), withIntermediateDirectories: true)
        previousTrail = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folder.appendingPathComponent("trail"))
        CourseActivity.reset()
        PreviewLeases.reset()
        WorkLeaseRegistry.reset()
    }

    override func tearDown() async throws {
        if let other, other.isRunning {
            other.terminate()
            other.waitUntilExit()
        }
        other = nil
        CourseActivity.reset()
        PreviewLeases.reset()
        WorkLeaseRegistry.reset()
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Helpers

    /// A lease another live program (a real `/bin/sleep`) holds on ICS3U.
    func writeOthersLease(kind: String) throws {
        if other == nil {
            let process: Process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["60"]
            try process.run()
            other = process
        }
        let pid: Int32 = try XCTUnwrap(other).processIdentifier
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: folder.appendingPathComponent("courses"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let when: String = ProcessLiveness.leaseMomentText(Date().addingTimeInterval(-1))
        let start: String = ProcessLiveness.startTime(ofProcess: pid) ?? ""
        try Data("\(pid)\nsleep\n\(when)\n\(start)\n".utf8).write(
            to: directory.appendingPathComponent(WorkLeaseFiles.fileName(courseCode: "ICS3U", kind: kind, pid: pid))
        )
    }

    func decide(hasBeenServing: Bool, output: String, building: Bool) -> Bool {
        return ScriptRunner.endIsAClosingForADeploy(
            exitCode: 1, wasStoppedByUser: false, wasCancelled: false,
            hasBeenServing: hasBeenServing, output: output, anotherProgramIsBuilding: building
        )
    }

    // MARK: - The decision

    func testServingKilledAndAnotherProgramBuildingIsClosedForADeploy() {
        XCTAssertTrue(decide(hasBeenServing: true, output: killedOutput, building: true))
    }

    /// A preview that ends while still BUILDING is a failed build. MUST FAIL
    /// without the serving condition.
    func testEndingWhileStillBuildingIsAFailure() {
        XCTAssertFalse(decide(hasBeenServing: false, output: killedOutput, building: true))
    }

    /// Served, but ended some other way (not the deploy's kill). MUST FAIL
    /// without the output condition.
    func testEndingAnotherWayIsAFailure() {
        XCTAssertFalse(decide(hasBeenServing: true, output: "Error: listen EADDRINUSE\n", building: true))
    }

    func testNothingBuildingElsewhereIsAFailure() {
        XCTAssertFalse(decide(hasBeenServing: true, output: killedOutput, building: false))
        XCTAssertFalse(ScriptRunner.endIsAClosingForADeploy(
            exitCode: 0, wasStoppedByUser: false, wasCancelled: false,
            hasBeenServing: true, output: killedOutput, anotherProgramIsBuilding: true
        ))
    }

    // MARK: - What "another program building" reads from the leases

    /// Another program only SERVING a preview is not a deploy. MUST FAIL if
    /// the check is widened to count a served lease.
    func testAnotherProgramOnlyServingIsNotBuilding() throws {
        try writeOthersLease(kind: "preview")
        XCTAssertFalse(WorkLeaseRegistry.anotherProgramIsBuilding(folderPath: folder.path, courseCode: "ICS3U"))
    }

    func testAnotherProgramDeployingIsBuilding() throws {
        try writeOthersLease(kind: "build")
        try writeOthersLease(kind: "publish")
        XCTAssertTrue(WorkLeaseRegistry.anotherProgramIsBuilding(folderPath: folder.path, courseCode: "ICS3U"))
        XCTAssertFalse(WorkLeaseRegistry.anotherProgramIsBuilding(folderPath: folder.path, courseCode: "MPM2D"),
                       "Another course's build is not this course's.")
    }

    /// The app's OWN build is never "another program".
    func testTheAppsOwnBuildIsNotAnotherProgram() {
        CourseActivity.beginPublish(folderPath: folder.path, courseCode: "ICS3U", sectionNumber: 2)
        XCTAssertFalse(WorkLeaseRegistry.anotherProgramIsBuilding(folderPath: folder.path, courseCode: "ICS3U"))
        CourseActivity.endPublish(folderPath: folder.path, courseCode: "ICS3U", sectionNumber: 2)
    }

    // MARK: - A real run

    /// End to end through `finishRun`: the flag, the output kept, and the
    /// trail's own line. MUST FAIL without the check in `finishRun`.
    func testARealServingPreviewKilledDuringADeployIsClosedAndSaysSo() async throws {
        try Data(("cat <<'EOF'\n" + killedOutput + "EOF\nexit 1\n").utf8)
            .write(to: folder.appendingPathComponent("preview.sh"))
        let runner: ScriptRunner = ScriptRunner()
        runner.endedForAnotherProgramsBuild = {
            return true
        }
        runner.run(scriptNamed: "preview.sh", arguments: ["ICS3U", "1"], workingDirectory: folder)
        runner.hasBeenServing = true
        _ = await runner.waitUntilFinished()
        XCTAssertEqual(runner.lastExitCode, 1)
        XCTAssertTrue(runner.wasClosedForADeploy, runner.transcript.displayText)
        XCTAssertTrue(runner.transcript.displayText.contains(ScriptRunner.killedServerMarker),
                      "The output stays there to read.")
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("ICS3U/1 · the preview closed — another program on this Mac was building"), trail)
        XCTAssertTrue(trail.contains(ScriptRunner.closedForADeployOutcome.lowercased()), trail)
    }

    /// The same run, never serving: a failure, and no closing line.
    func testARealPreviewThatNeverServedIsAFailure() async throws {
        try Data(("cat <<'EOF'\n" + killedOutput + "EOF\nexit 1\n").utf8)
            .write(to: folder.appendingPathComponent("preview.sh"))
        let runner: ScriptRunner = ScriptRunner()
        runner.endedForAnotherProgramsBuild = {
            return true
        }
        runner.run(scriptNamed: "preview.sh", arguments: ["ICS3U", "1"], workingDirectory: folder)
        _ = await runner.waitUntilFinished()
        XCTAssertFalse(runner.wasClosedForADeploy)
        XCTAssertFalse(ActivityTrail.store.activityText(includingPrompts: true).contains("the preview closed"))
    }
}
