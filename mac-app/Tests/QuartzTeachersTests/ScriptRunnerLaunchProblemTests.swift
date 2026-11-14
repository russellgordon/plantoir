import XCTest
@testable import QuartzTeachers

/// What a teacher reads when a run could not start (#812's review). Since
/// #812 a preview that never started raises `launchProblem` in the
/// "Cannot Preview Yet" alert, so none of these sentences may carry the
/// system's own description of an error: the pseudo-terminal failure used
/// to read "(QuartzTeachers.PseudoTerminalError error 0.)", which names the
/// app's internal module and type (rule 1 of the repository's CLAUDE.md).
///
/// Every launch problem `ScriptRunner.run` can leave is walked: Plantoir
/// closing, the folder's tools still being copied or failed, the launcher
/// missing, and a launch the system refused, met for real by pointing the
/// shell at a program that is not there. The pseudo-terminal failure cannot
/// be caused from a test, so its sentence is checked as the constant both
/// failures share, beside the description it replaced.
@MainActor
final class ScriptRunnerLaunchProblemTests: XCTestCase {

    // MARK: - Stored properties

    /// Words that belong to the machinery, never to a teacher's sentence.
    static let machineryWords: [String] = [
        "QuartzTeachers",
        "Pseudo",
        "error 0",
        "Error",
        "NSCocoaErrorDomain",
        "couldn’t be completed",
        "bash",
    ]

    var folder: URL = URL(fileURLWithPath: "/")

    // MARK: - Functions

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-launch-problem-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        ScriptRunner.refusesNewRuns = false
        ScriptRunner.shell = URL(fileURLWithPath: "/bin/bash")
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    /// Every launch problem is a sentence with no machinery in it.
    func testNoLaunchProblemNamesTheMachinery() throws {
        var sentences: [String: String] = [:]

        // Plantoir closing.
        let closing: ScriptRunner = ScriptRunner()
        ScriptRunner.refusesNewRuns = true
        closing.run(scriptNamed: "preview.sh", arguments: [], workingDirectory: folder)
        ScriptRunner.refusesNewRuns = false
        sentences["closing"] = try XCTUnwrap(closing.launchProblem)
        XCTAssertNil(closing.launchProblemDetail)

        // The folder's tools still being copied, or failed to copy: the
        // sentences `ToolchainReadinessTests` pins the runner to.
        sentences["getting ready"] = ToolchainReadinessWording.gettingReadyMessage
        sentences["could not get ready"] = ToolchainReadinessWording.couldNotGetReady

        // The launcher is missing from the folder.
        let missing: ScriptRunner = ScriptRunner()
        missing.run(scriptNamed: "preview.sh", arguments: [], workingDirectory: folder)
        sentences["missing launcher"] = try XCTUnwrap(missing.launchProblem)
        XCTAssertNil(missing.launchProblemDetail)

        // The system refused to launch it: a real refusal, from a shell
        // that is not there.
        let script: URL = folder.appendingPathComponent("preview.sh")
        try "exit 0\n".write(to: script, atomically: true, encoding: .utf8)
        ScriptRunner.shell = folder.appendingPathComponent("no-such-shell").appendingPathComponent("bash")
        let refused: ScriptRunner = ScriptRunner()
        refused.run(scriptNamed: "preview.sh", arguments: [], workingDirectory: folder)
        ScriptRunner.shell = URL(fileURLWithPath: "/bin/bash")
        XCTAssertFalse(refused.isRunning)
        sentences["launch refused"] = try XCTUnwrap(refused.launchProblem)
        let detail: String = try XCTUnwrap(
            refused.launchProblemDetail,
            "what the system said is kept for the trail"
        )
        XCTAssertFalse(detail.isEmpty)

        // The pseudo-terminal failure shares the launch failure's sentence.
        sentences["no terminal"] = ScriptRunner.couldNotGetStarted
        XCTAssertEqual(refused.launchProblem, ScriptRunner.couldNotGetStarted)

        // The check itself sees what it is looking for: the description
        // the pseudo-terminal sentence used to carry is caught.
        let oldDescription: String = PseudoTerminalError.couldNotOpen.localizedDescription
        XCTAssertTrue(
            ScriptRunnerLaunchProblemTests.machineryWordsIn(oldDescription).count > 0,
            "the check must catch \(oldDescription)"
        )

        XCTAssertEqual(sentences.count, 6)
        for (name, sentence) in sentences {
            XCTAssertFalse(sentence.isEmpty, name)
            let found: [String] = ScriptRunnerLaunchProblemTests.machineryWordsIn(sentence)
            XCTAssertEqual(found, [], "\(name): \(sentence)")
        }
    }

    /// The machinery words a sentence carries.
    static func machineryWordsIn(_ sentence: String) -> [String] {
        var found: [String] = []
        for word in machineryWords {
            if sentence.contains(word) {
                found.append(word)
            }
        }
        return found
    }
}
