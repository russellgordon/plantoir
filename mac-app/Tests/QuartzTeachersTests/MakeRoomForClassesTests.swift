import XCTest
@testable import QuartzTeachers

/// Making room part-way through a unit.
///
/// **The most dangerous thing on this surface, by its own engine's admission.**
/// `ClassInsertionPlanner` renames the later days of a unit and rewrites every
/// wikilink that pointed at them, so these tests care as much about what a
/// teacher is TOLD as about what happens: once other classes have moved,
/// "undo that" cannot take it back, and a reply that did not say so would send
/// somebody looking for an undo that is not there.
final class MakeRoomForClassesTests: XCTestCase {

    // MARK: - Which client is shown it

    @MainActor
    func testItIsMCPOnlyAndHasItsPlanTwin() throws {
        var shown: Set<String> = []
        for tool in AssistToolRunner.localTools {
            shown.insert(tool.name)
        }
        var overMCP: Set<String> = []
        for tool in AssistToolRunner.mcpTools {
            overMCP.insert(tool.name)
        }
        for name in ["make_room_for_classes", "plan_make_room_for_classes"] {
            XCTAssertFalse(shown.contains(name), "\(name) must never reach the local model.")
            XCTAssertTrue(overMCP.contains(name), "\(name) is missing from the MCP surface.")
        }

        let write: AssistToolDefinition = try XCTUnwrap(
            AssistToolRunner.mcpTools.first(where: { $0.name == "make_room_for_classes" })
        )
        XCTAssertEqual(write.planTwinName, "plan_make_room_for_classes")
        XCTAssertFalse(write.needsApproval, "Only the two acts that reach students are gated.")
    }

    // MARK: - The phrasing a teacher can type

    /// Parity with the MCP tool: the same three things can be said.
    @MainActor
    func testThePhrasingCarriesTheUnitTheDayAndTheCount() throws {
        let one: AssistCardCommand = try XCTUnwrap(
            AssistCardCommand.matching("make room for a class at Unit 3, Day 4")
        )
        XCTAssertEqual(one.toolName, "make_room_for_classes")
        XCTAssertEqual(one.arguments, ["unit": "3", "atDay": "4", "howMany": "1"])

        let several: AssistCardCommand = try XCTUnwrap(
            AssistCardCommand.matching("make room for two classes at Unit 3, Day 4")
        )
        XCTAssertEqual(several.arguments, ["unit": "3", "atDay": "4", "howMany": "2"])

        let digits: AssistCardCommand = try XCTUnwrap(
            AssistCardCommand.matching("make room for 2 classes at Unit 3, Day 4")
        )
        XCTAssertEqual(digits.arguments["howMany"], "2")
    }

    /// A sentence that only LOOKS like the shape must go to the model.
    ///
    /// The table's own rule: a loose match answers the wrong question with
    /// total confidence, which is worse than routing it.
    @MainActor
    func testNearMissesAreNotSwallowed() throws {
        let notThese: [String] = [
            "make room for a class",                              // no place
            "make room for a class at Unit 3",                    // no day
            "make room for two class at Unit 3, Day 4",           // count and noun disagree
            "make room for a classes at Unit 3, Day 4",           // the reverse
            "make room for a class at Unit three, Day 4",         // unit not a number
            "make room for zero classes at Unit 3, Day 4",        // nothing to add
            "make room for a class at Unit 3, Day 4 next week",   // extra meaning
        ]
        for sentence in notThese {
            XCTAssertNotEqual(
                AssistCardCommand.matching(sentence)?.toolName, "make_room_for_classes",
                "“\(sentence)” is not this shape and must reach the model instead."
            )
        }
    }

    // MARK: - What it does, and what it says

    @MainActor
    func testItMakesRoomAndSaysTheNewPagesAreHidden() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try seedAUnit(in: made.course)

        let said: String = await run(
            made.runner, "make_room_for_classes",
            ["course": "ICS3U", "section": 1, "unit": 1, "atDay": 2]
        )

        XCTAssertTrue(said.lowercased().contains("hidden"), "A teacher must know it is not live: \(said)")
        let names: [String] = try pageNames(in: made.course)
        XCTAssertTrue(names.contains("Unit 1, Day 3.md"), "The later day should have been renumbered: \(names)")
    }

    /// The undo caveat is said whenever other classes moved.
    ///
    /// Taking this back page by page would leave a section half-renumbered —
    /// worse than no undo — so nothing goes on the undo list, and the reply has
    /// to say where the way out actually is.
    @MainActor
    func testItSaysUndoWillNotTakeItBackWhenClassesMoved() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try seedAUnit(in: made.course)

        let said: String = await run(
            made.runner, "make_room_for_classes",
            ["course": "ICS3U", "section": 1, "unit": 1, "atDay": 2]
        )

        XCTAssertTrue(said.contains("Undo that"), said)
        XCTAssertTrue(said.contains("Backups"), "It must say where the way out is: \(said)")

        // Asked through the tool rather than by reading the list, because what
        // matters is what a teacher who says "undo that" actually gets.
        let undone: String = await run(made.runner, "undo_last_change", [:])
        XCTAssertEqual(
            undone, AssistWording.nothingToUndo,
            "Nothing may be undoable here: a half-undone renumbering is worse than none."
        )
        XCTAssertTrue(
            try pageNames(in: made.course).contains("Unit 1, Day 3.md"),
            "The undo must not have half-reversed the renumbering."
        )
    }

    /// The plan changes nothing and warns about the same thing.
    @MainActor
    func testThePlanWritesNothingAndWarnsFirst() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try seedAUnit(in: made.course)

        let before: [String] = try pageNames(in: made.course)
        let said: String = await run(
            made.runner, "plan_make_room_for_classes",
            ["course": "ICS3U", "section": 1, "unit": 1, "atDay": 2]
        )
        XCTAssertEqual(try pageNames(in: made.course), before, "A plan must write nothing.")
        XCTAssertTrue(
            said.contains("Undo that"),
            "The warning belongs in the PLAN, where a teacher can still say no: \(said)"
        )
    }

    /// A missing day is asked for rather than guessed.
    @MainActor
    func testItAsksRatherThanGuessingWhereToMakeRoom() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try seedAUnit(in: made.course)

        let said: String = await run(
            made.runner, "make_room_for_classes", ["course": "ICS3U", "section": 1, "unit": 1]
        )
        XCTAssertTrue(said.lowercased().contains("which day"), said)
        XCTAssertEqual(
            try pageNames(in: made.course).count, 2, "Nothing may be written when the ask is incomplete."
        )
    }


    /// A timetable that has run out is REFUSED, not reported as success.
    ///
    /// The engine reports this by returning a plan that adds nothing rather
    /// than by throwing, so the apply path answered "Nothing needed moving."
    /// under a summary saying room had been made — and threw away the one
    /// actionable sentence, which names how many more dates are needed.
    @MainActor
    func testItRefusesWhenTheTimetableHasRunOut() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try seedAUnit(in: made.course)

        // Far more classes than there are class dates left.
        let said: String = await run(
            made.runner, "make_room_for_classes",
            ["course": "ICS3U", "section": 1, "unit": 1, "atDay": 2, "howMany": 50]
        )

        XCTAssertFalse(
            said.lowercased().contains("nothing needed moving"),
            "That reads as success over a summary saying room was made: \(said)"
        )
        XCTAssertTrue(
            said.lowercased().contains("class dates") || said.lowercased().contains("timetable"),
            "It must say what is actually wrong, and what to do: \(said)"
        )
        XCTAssertEqual(try pageNames(in: made.course).count, 2, "Nothing may have been written.")
    }

    /// Moving later classes counts as "other classes moved", even when nothing
    /// inside the unit was renamed.
    ///
    /// Making room in a SHORT unit renames nothing in it and re-dates every
    /// class of every later unit — so a warning keyed on renames alone stayed
    /// silent in exactly the case that moves a teacher's whole year.
    @MainActor
    func testItWarnsWhenLaterUNITSMoveEvenWithNoRenames() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try seedAUnit(in: made.course)
        // A second unit, so there is something after the one being widened.
        try AssistFixture.write(
            page: "Unit 2, Day 1", publish: "false", date: "2026-09-15", body: "three", in: made.course
        )

        // The day AFTER the last day of unit 1: nothing in unit 1 is renamed.
        let said: String = await run(
            made.runner, "make_room_for_classes",
            ["course": "ICS3U", "section": 1, "unit": 1, "atDay": 3]
        )

        XCTAssertTrue(
            said.contains("Undo that"),
            "Later classes moved, so the teacher must be told the undo will not help: \(said)"
        )
    }

    // MARK: - Helpers

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
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
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
