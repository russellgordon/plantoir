import XCTest
@testable import QuartzTeachers

/// Answering "what courses do I have?".
///
/// The tool exists for the client that cannot see a sidebar: a Claude Code
/// session is handed a working FOLDER, the mac's MCP server answers only
/// `initialize`, `tools/list` and `tools/call`, and nothing in that tells it
/// what is in the folder — so its first move is to guess a course code, which
/// reaches the wrong course silently.
final class ListCoursesTests: XCTestCase {

    // MARK: - Which client is shown it

    /// MCP-only, and that is the whole reason it costs nothing.
    ///
    /// Routing accuracy is measured against the thirteen the local model is
    /// shown. A tool it is never shown cannot degrade that, which is what
    /// makes this addition free — and the local model does not need it: its
    /// window is scoped to one section and `AssistAgent.systemPrompt` names
    /// the course already.
    @MainActor
    func testTheLocalModelIsNotShownIt() throws {
        var shown: Set<String> = []
        for tool in AssistToolRunner.localTools {
            shown.insert(tool.name)
        }
        XCTAssertFalse(
            shown.contains("list_courses"),
            "Showing it to the local model spends routing accuracy on a question it cannot have."
        )

        var overMCP: Set<String> = []
        for tool in AssistToolRunner.mcpTools {
            overMCP.insert(tool.name)
        }
        XCTAssertTrue(overMCP.contains("list_courses"), "Claude Code has no other way to ask.")
    }

    /// A teacher can still reach it, by a phrasing matched in code.
    ///
    /// **MCP-only means the MODEL is not shown it, not that the app cannot do
    /// it.** A fixed phrasing never reaches the model, so this costs the
    /// router nothing and still answers a teacher looking at one section who
    /// wants to know what else is in the folder.
    @MainActor
    func testATeacherCanAskForItWithoutTheModel() throws {
        for phrasing in ["what courses do I have?", "list my courses"] {
            let command: AssistCardCommand? = AssistCardCommand.matching(phrasing)
            XCTAssertEqual(command?.toolName, "list_courses", phrasing)
            XCTAssertEqual(command?.arguments, [:], "It takes no arguments.")
        }
    }

    /// It reads nothing and changes nothing.
    @MainActor
    func testItIsReadOnlyAndNeedsNoApproval() throws {
        let tool: AssistToolDefinition = try XCTUnwrap(
            AssistToolRunner.mcpTools.first(where: { $0.name == "list_courses" })
        )
        XCTAssertTrue(tool.readOnly)
        XCTAssertFalse(tool.needsApproval)
        XCTAssertTrue(tool.parameters.isEmpty, "There is nothing to ask for — it lists the folder.")
        XCTAssertTrue(tool.required.isEmpty)
    }

    // MARK: - What it answers

    /// The code, the name, the sections and where it publishes.
    ///
    /// **All four, because leaving any out costs a round trip.** A caller with
    /// only codes has to call `check_section` to learn whether section 2
    /// exists, and cannot warn a teacher that the course they just asked to
    /// publish goes somewhere they did not expect.
    @MainActor
    func testItNamesTheCourseItsSectionsAndWhereItPublishes() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let said: String = await run(made.runner)

        XCTAssertTrue(said.contains("ICS3U"), said)
        XCTAssertTrue(said.contains("sections:"), said)
        XCTAssertTrue(said.contains("publishes to:"), said)
        XCTAssertTrue(
            said.contains("Netlify"),
            "The fixture course has no destination configured, so it reads as the default: \(said)"
        )
    }

    /// A folder with nothing in it says so, and says what to do next.
    ///
    /// Named rather than typed, so the sentence has one home and Windows can
    /// assert the same one.
    @MainActor
    func testAnEmptyWorkingFolderSaysSoInTheProductsWords() async throws {
        // A REAL empty working folder, not a runner with its list emptied:
        // "no courses" should be what the app concludes from the folder, which
        // is the state a teacher is actually in on their first run.
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-courses-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("courses"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        XCTAssertTrue(workspace.courses.isEmpty, "The folder was meant to be empty.")

        let runner: AssistToolRunner = AssistToolRunner(
            workspace: workspace,
            siteWork: StubSiteWork(),
            today: { return CalendarDay(year: 2026, month: 9, day: 8)! },
            launchControl: SilentLaunchControl()
        )
        let said: String = await run(runner)

        XCTAssertEqual(said, AssistWording.noCoursesYet)
    }

    /// Rule 1: no machinery in anything a teacher reads.
    @MainActor
    func testItSaysNothingAboutTheMachinery() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let said: String = await run(made.runner)
        for word in ["container", "docker", "toolchain", "json", "config", "quartz"] {
            XCTAssertFalse(
                said.lowercased().contains(word),
                "“\(word)” is machinery a teacher is not the audience for: \(said)"
            )
        }
    }

    // MARK: - Helpers

    @MainActor
    private func run(_ runner: AssistToolRunner) async -> String {
        let outcome: AssistToolOutcome = await runner.run(
            call: AssistToolCall(
                id: UUID().uuidString,
                type: "function",
                function: AssistToolCall.Function(name: "list_courses", arguments: "{}")
            )
        )
        return outcome.detail
    }
}
