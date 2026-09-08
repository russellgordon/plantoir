import XCTest
@testable import QuartzTeachers

/// The last two of the six: saying what publishing means, and taking a copy.
///
/// Both exist for the same client and the same reason. A Claude Code session
/// driving `--mcp-stdio` is told nothing at startup — the server sends no
/// `instructions` — so it never learned that publishing and deploying are
/// different acts, and nothing backs up the files it edits with its OWN tools
/// rather than through these.
final class ExplainAndBackUpTests: XCTestCase {

    // MARK: - Which client is shown them

    @MainActor
    func testBothAreMCPOnlyAndReachableByAPhrasing() throws {
        var shown: Set<String> = []
        for tool in AssistToolRunner.localTools {
            shown.insert(tool.name)
        }
        var overMCP: Set<String> = []
        for tool in AssistToolRunner.mcpTools {
            overMCP.insert(tool.name)
        }
        for name in ["explain_publishing", "back_up_course"] {
            XCTAssertFalse(shown.contains(name), "\(name) must not cost the local model anything.")
            XCTAssertTrue(overMCP.contains(name), "\(name) is missing from the MCP surface.")
        }

        XCTAssertEqual(
            AssistCardCommand.matching("what does publishing mean?")?.toolName, "explain_publishing"
        )
        XCTAssertEqual(
            AssistCardCommand.matching("back up this course")?.toolName, "back_up_course"
        )
    }

    /// A backup is a write with nothing to plan, like rebuilding the preview.
    ///
    /// `AssistAgent` checks whether a twin EXISTS before offering a plan and
    /// executes directly when there is none, so this is a supported shape
    /// rather than a hole — and "shall I plan to take a copy?" would be a card
    /// with no decision in it.
    @MainActor
    func testTheBackupNeedsNoPlanAndNoApproval() throws {
        let tool: AssistToolDefinition = try XCTUnwrap(
            AssistToolRunner.mcpTools.first(where: { $0.name == "back_up_course" })
        )
        XCTAssertFalse(tool.readOnly, "It has a side effect, so it is not read-only.")
        XCTAssertFalse(tool.needsApproval)
        XCTAssertNil(
            AssistToolRunner.mcpTools.first(where: { $0.name == "plan_back_up_course" }),
            "There is nothing to plan: a copy takes nothing away."
        )
    }

    // MARK: - Explaining

    /// The explanation names both acts and says they are different.
    @MainActor
    func testItExplainsBothActsAndSaysTheyDiffer() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let said: String = await run(
            made.runner, "explain_publishing", ["course": "ICS3U", "section": 1]
        )
        XCTAssertEqual(said, AssistWording.whatPublishingMeans)
        XCTAssertTrue(said.lowercased().contains("publishing"), said)
        XCTAssertTrue(said.lowercased().contains("deploying"), said)
        XCTAssertTrue(said.lowercased().contains("different acts"), said)
    }

    /// Asked twice for the same section, it says so instead of repeating.
    ///
    /// The failure this prevents is a session that re-explains before every
    /// action, which reads as an assistant that cannot remember what it just
    /// said.
    @MainActor
    func testItAnswersOncePerSection() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        _ = await run(made.runner, "explain_publishing", ["course": "ICS3U", "section": 1])
        let again: String = await run(
            made.runner, "explain_publishing", ["course": "ICS3U", "section": 1]
        )

        XCTAssertNotEqual(again, AssistWording.whatPublishingMeans, "It repeated itself.")
        XCTAssertEqual(
            again,
            AssistWording.publishingAlreadyExplained(course: "ICS3U", section: "1")
        )
    }

    /// It changes nothing.
    @MainActor
    func testExplainingIsReadOnly() throws {
        let tool: AssistToolDefinition = try XCTUnwrap(
            AssistToolRunner.mcpTools.first(where: { $0.name == "explain_publishing" })
        )
        XCTAssertTrue(tool.readOnly)
        XCTAssertNil(tool.planTwinName, "A read needs no plan.")
    }

    // MARK: - Backing up

    /// It makes a real copy and names where it went.
    @MainActor
    func testItBacksTheCourseUpAndSaysWhereItWent() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let said: String = await run(made.runner, "back_up_course", ["course": "ICS3U"])

        XCTAssertTrue(said.contains("ICS3U"), said)
        XCTAssertTrue(said.contains(".zip"), "It must name the copy: \(said)")
        XCTAssertTrue(
            said.contains("Backups"),
            "A teacher needs to know where to restore it from: \(said)"
        )

        // `courses/_backups/<CODE>/`, beside the courses rather than beside
        // the working folder — the same place the setup wizard writes to.
        let backups: URL = made.root.appendingPathComponent("courses/_backups/ICS3U")
        let madeFiles: [String] = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []
        XCTAssertFalse(madeFiles.isEmpty, "No copy was actually written to \(backups.path).")
    }

    /// A course code that is not here is said plainly, not guessed at.
    @MainActor
    func testAnUnknownCourseIsRefusedRatherThanGuessed() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let said: String = await run(made.runner, "back_up_course", ["course": "NOPE1"])
        XCTAssertTrue(said.contains("NOPE1"), said)
        XCTAssertTrue(said.lowercased().contains("no course"), said)
    }

    /// The code is matched the way every other tool matches one.
    @MainActor
    func testTheCourseCodeIsMatchedWithoutRegardToCase() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let said: String = await run(made.runner, "back_up_course", ["course": "ics3u"])
        XCTAssertTrue(said.contains("ICS3U"), "Lower case should reach the same course: \(said)")
    }

    // MARK: - Helpers

    @MainActor
    private func run(
        _ runner: AssistToolRunner, _ tool: String, _ arguments: [String: Any]
    ) async -> String {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        let outcome: AssistToolOutcome = await runner.run(
            call: AssistToolCall(
                id: UUID().uuidString,
                type: "function",
                function: AssistToolCall.Function(
                    name: tool, arguments: String(decoding: encoded, as: UTF8.self)
                )
            )
        )
        return outcome.detail
    }
}
