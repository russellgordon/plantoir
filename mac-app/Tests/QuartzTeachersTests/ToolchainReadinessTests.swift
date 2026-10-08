import XCTest
@testable import QuartzTeachers

/// A folder getting ready after an update (#476; Windows' #473): what is
/// greyed, what refuses, what waits, and the words.
///
/// Touches `ToolchainReadiness.shared`, process-wide: safe only because the
/// scheme runs test classes one at a time.
@MainActor
final class ToolchainReadinessTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = URL(fileURLWithPath: "/")

    // MARK: - Set up

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("toolchain-readiness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "#!/bin/bash\nexit 0\n".write(to: root.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        ToolchainReadiness.shared.reset()
    }

    override func tearDown() async throws {
        ToolchainReadiness.shared.reset()
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Tests

    /// The states, and what each means for the buttons.
    func testOnlyACopyUnderWayOrAFailureHoldsTheButtons() {
        XCTAssertFalse(ToolchainReadiness.shared.isGettingReady(root), "nothing asked yet")
        ToolchainReadiness.shared.noteCopyingForTests(root)
        XCTAssertTrue(ToolchainReadiness.shared.isGettingReady(root))
        XCTAssertEqual(ToolchainReadiness.shared.reasonToWait(root), ToolchainReadinessWording.gettingReadyMessage)
        ToolchainReadiness.shared.noteReadyForTests(root)
        XCTAssertFalse(ToolchainReadiness.shared.isGettingReady(root))
        ToolchainReadiness.shared.noteFailedForTests(root)
        XCTAssertEqual(ToolchainReadiness.shared.reasonToWait(root), ToolchainReadinessWording.couldNotGetReady)
        // A READY folder is left alone by the retry; only a failure is forgotten.
        ToolchainReadiness.shared.forgetFailure(root)
        XCTAssertEqual(ToolchainReadiness.shared.state(of: root), .notStarted)
        ToolchainReadiness.shared.noteReadyForTests(root)
        ToolchainReadiness.shared.forgetFailure(root)
        XCTAssertEqual(ToolchainReadiness.shared.state(of: root), .ready)
    }

    /// The same folder spelled two ways is one entry (#189).
    func testTheFolderIsKeyedByItsCanonicalPath() {
        ToolchainReadiness.shared.noteCopyingForTests(root)
        let otherSpelling: URL = URL(fileURLWithPath: root.path.uppercased() == root.path ? root.path.lowercased() : root.path.uppercased())
        if FolderIdentity.isSameFolder(root.path, otherSpelling.path) {
            XCTAssertTrue(ToolchainReadiness.shared.isGettingReady(otherSpelling))
        }
    }

    /// The banner follows the first file written, or a failure — never a
    /// compare that changed nothing.
    func testTheBannerWaitsForAFileToBeWritten() {
        XCTAssertFalse(ToolchainReadiness.showsBanner(for: .notStarted))
        XCTAssertFalse(ToolchainReadiness.showsBanner(for: .copying(hasWritten: false)))
        XCTAssertTrue(ToolchainReadiness.showsBanner(for: .copying(hasWritten: true)))
        XCTAssertFalse(ToolchainReadiness.showsBanner(for: .ready))
        XCTAssertTrue(ToolchainReadiness.showsBanner(for: .failed(message: "x")))
    }

    /// `ScriptRunner` is the backstop: nothing starts from a folder that is
    /// copying or failed, and the problem is the same sentence the buttons
    /// show. An ordinary folder is untouched.
    func testTheRunnerRefusesWhileTheFolderGetsReady() async {
        let runner: ScriptRunner = ScriptRunner()
        ToolchainReadiness.shared.noteCopyingForTests(root)
        runner.run(scriptNamed: "preview.sh", arguments: [], workingDirectory: root)
        XCTAssertEqual(runner.launchProblem, ToolchainReadinessWording.gettingReadyMessage)
        XCTAssertFalse(runner.isRunning)
        XCTAssertNil(runner.lastExitCode, "no exit code: nothing ran, as the other refusals leave it")

        ToolchainReadiness.shared.noteFailedForTests(root)
        runner.run(scriptNamed: "preview.sh", arguments: [], workingDirectory: root)
        XCTAssertEqual(runner.launchProblem, ToolchainReadinessWording.couldNotGetReady)

        ToolchainReadiness.shared.noteReadyForTests(root)
        runner.run(scriptNamed: "preview.sh", arguments: [], workingDirectory: root)
        XCTAssertNil(runner.launchProblem)
        _ = await runner.waitUntilFinished()
    }

    /// The creator refuses BEFORE it writes `course_config.json` or the
    /// `course created` line — a half-made course blocks a retry.
    func testTheCreatorRefusesBeforeWritingAnything() throws {
        ToolchainReadiness.shared.noteCopyingForTests(root)
        let creator: NewCourseCreator = NewCourseCreator()
        creator.createCourse(configuration: ["course_code": "ICS3U", "course_name": "x"], workspaceURL: root)
        XCTAssertEqual(creator.preparationProblem, ToolchainReadinessWording.gettingReadyMessage)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("courses/ICS3U/course_config.json").path),
            "nothing may be written"
        )
        XCTAssertFalse(creator.isCreating)
        creator.installExampleCourse(workspaceURL: root)
        XCTAssertEqual(creator.preparationProblem, ToolchainReadinessWording.gettingReadyMessage)
        XCTAssertFalse(creator.isCreating)
    }

    /// Rule 1: the words name no machinery, and the button is "Deploy" (#443).
    func testTheWordsNameNoMachineryAndCallADeployADeploy() {
        for sentence in [ToolchainReadinessWording.gettingReadyTitle, ToolchainReadinessWording.gettingReadyMessage, ToolchainReadinessWording.couldNotGetReady] {
            for word in ["toolchain", "script", "docker", "container", "copy of the tools", "publish"] {
                XCTAssertFalse(sentence.lowercased().contains(word), "\(sentence) says \(word)")
            }
        }
        XCTAssertTrue(ToolchainReadinessWording.gettingReadyMessage.contains("Deploy"))
    }
}
