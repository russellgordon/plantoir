import XCTest
@testable import QuartzTeachers

/// Filling out a unit: "add five more days to Unit 4".
///
/// **The engine already shipped; only the door was missing.** That sentence has
/// reached `NextClassPlanner.plan(addingDays:toUnit:)` for as long as the card
/// phrasing has existed — through `unit` and `days`, keys deliberately absent
/// from `add_next_class`' schema. So a teacher could ask and a Claude Code
/// session could not. `add_classes` publishes the same capability under a name
/// of its own, which is how Windows has it.
final class AddClassesTests: XCTestCase {

    // MARK: - Which client is shown it

    /// MCP-only, and for a reason particular to this pair.
    ///
    /// The local model reaches this capability ANYWAY, through a phrasing
    /// matched in code that never consults it. Publishing the schema would
    /// spend routing accuracy — measured against the thirteen it is shown — to
    /// buy the model something it already has a deterministic route to.
    @MainActor
    func testTheLocalModelIsNotShownEitherHalf() throws {
        var shown: Set<String> = []
        for tool in AssistToolRunner.localTools {
            shown.insert(tool.name)
        }
        var overMCP: Set<String> = []
        for tool in AssistToolRunner.mcpTools {
            overMCP.insert(tool.name)
        }
        for name in ["add_classes", "plan_add_classes"] {
            XCTAssertFalse(shown.contains(name), "\(name) must not cost the local model anything.")
            XCTAssertTrue(overMCP.contains(name), "\(name) is missing from the MCP surface.")
        }
    }

    /// A write must have a plan twin, or plan mode dead-ends.
    ///
    /// `planTwinName` derives `plan_<name>` for anything not read-only, and
    /// `AssistAgent.showPlan` returns early when the twin hands back something
    /// that is not a plan. A write whose twin does not exist is a write plan
    /// mode cannot carry out — which is on by default, so it would be the
    /// ordinary case rather than the edge one.
    @MainActor
    func testTheWriteHasItsPlanTwin() throws {
        let write: AssistToolDefinition = try XCTUnwrap(
            AssistToolRunner.mcpTools.first(where: { $0.name == "add_classes" })
        )
        XCTAssertFalse(write.readOnly)
        XCTAssertEqual(write.planTwinName, "plan_add_classes")

        let twin: AssistToolDefinition = try XCTUnwrap(
            AssistToolRunner.mcpTools.first(where: { $0.name == "plan_add_classes" })
        )
        XCTAssertTrue(twin.readOnly, "A plan must change nothing.")
        XCTAssertNil(twin.planTwinName, "A plan needs no plan of its own.")
    }

    /// The teacher's phrasing and the published tool ask for the same things.
    ///
    /// Russell's rule: a card phrasing has all the same functionality the MCP
    /// surface offers. Course and section come from the window, so the two
    /// things left to say are the unit and how many days — which is exactly
    /// what the phrasing carries.
    @MainActor
    func testThePhrasingAndTheToolAskForTheSameThings() throws {
        let command: AssistCardCommand = try XCTUnwrap(
            AssistCardCommand.matching("add five more days to unit 4")
        )
        XCTAssertEqual(command.toolName, "add_next_class")
        XCTAssertEqual(command.arguments["unit"], "4")
        XCTAssertEqual(command.arguments["days"], "5")

        let tool: AssistToolDefinition = try XCTUnwrap(
            AssistToolRunner.mcpTools.first(where: { $0.name == "add_classes" })
        )
        XCTAssertEqual(Set(tool.required), ["course", "section", "unit", "howMany"])
    }

    /// No `firstDay`, deliberately — the mac works it out.
    ///
    /// Windows takes one, defaulting to 1 and described as "1 unless the
    /// earlier days already exist", which is a question the caller answers by
    /// looking. The mac's planner continues from the last day that EXISTS in
    /// that unit, published or not, so there is nothing to get wrong.
    @MainActor
    func testItAsksForNoFirstDayBecauseItWorksThatOut() throws {
        let tool: AssistToolDefinition = try XCTUnwrap(
            AssistToolRunner.mcpTools.first(where: { $0.name == "add_classes" })
        )
        XCTAssertNil(tool.parameters["firstDay"], "The planner continues from what already exists.")
    }

    // MARK: - What it does

    /// It adds the days, named and dated by the same engine the phrasing uses.
    @MainActor
    func testItAddsThatManyDaysToThatUnit() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try seedAUnit(in: made.course)

        let said: String = await run(
            made.runner, "add_classes", ["course": "ICS3U", "section": 1, "unit": 1, "howMany": 2]
        )

        XCTAssertTrue(said.contains("Unit 1, Day 3"), said)
        XCTAssertTrue(said.contains("Unit 1, Day 4"), said)
    }

    /// The plan changes nothing.
    @MainActor
    func testThePlanWritesNoPages() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try seedAUnit(in: made.course)

        let before: [String] = try pageNames(in: made.course)
        _ = await run(
            made.runner, "plan_add_classes", ["course": "ICS3U", "section": 1, "unit": 1, "howMany": 2]
        )
        XCTAssertEqual(try pageNames(in: made.course), before, "A plan must write nothing.")
    }

    /// `howMany` reaches the engine, whatever the client sends it as.
    ///
    /// An MCP client sends JSON numbers and the card phrasing sends strings.
    /// The published name is `howMany` and the engine reads `days`, so the
    /// translation is the one place this could silently do nothing.
    @MainActor
    func testTheCountReachesTheEngineAsAStringOrANumber() async throws {
        for count in [2 as Any, "2" as Any] {
            let made = try AssistFixture.makeRunner()
            defer { try? FileManager.default.removeItem(at: made.root) }
            try seedAUnit(in: made.course)

            let said: String = await run(
                made.runner, "add_classes",
                ["course": "ICS3U", "section": 1, "unit": 1, "howMany": count]
            )
            XCTAssertTrue(
                said.contains("Unit 1, Day 4"),
                "Sent as \(type(of: count)), the count did not reach the planner: \(said)"
            )
        }
    }

    // MARK: - Helpers

    /// A section with class dates on file and a unit already part-written, so
    /// "add more days to it" has something to continue from.
    @MainActor
    private func seedAUnit(in course: Course) throws {
        let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2026-09-08", "2026-09-10", "2026-09-15", "2026-09-17", "2026-09-22"],
            source: "timetable.xlsx, block H", forSection: 1, in: course
        )
        try SectionTimetableStore.applyRememberTimetable(plan)
        try AssistFixture.write(
            page: "Unit 1, Day 1", publish: "false", date: "2026-09-08", body: "one", in: course
        )
        try AssistFixture.write(
            page: "Unit 1, Day 2", publish: "false", date: "2026-09-10", body: "two", in: course
        )
    }

    @MainActor
    private func pageNames(in course: Course) throws -> [String] {
        let folder: URL = course.directoryURL.appendingPathComponent("section1/All Classes")
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted()
    }

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
