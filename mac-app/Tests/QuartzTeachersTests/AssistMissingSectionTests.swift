import XCTest
@testable import QuartzTeachers

/// A call that names no section, or leaves out another required number, is
/// told what is missing rather than answered about a value nobody sent (#865).
///
/// Found in the Copilot trial (2026-11-13): an outside assistant called
/// `list_curriculum_expectations` without `section` and was told the course
/// "has no Section 0". `locate` read the missing section as 0 for every tool
/// that goes through it, which is every MCP tool that takes a section except
/// `back_up_course`. Every sentence here is named through `AssistToolRefusal`,
/// never quoted.
final class AssistMissingSectionTests: XCTestCase {

    // MARK: - Functions

    /// Every MCP tool that takes a section, called with none on a course with
    /// two, says a section is needed and names both, and never "Section 0".
    ///
    /// `back_up_course` is left out on purpose: it backs up the whole course,
    /// and its section only records who made the copy.
    @MainActor
    func testEveryToolThatTakesASectionSaysWhichOnesThereAre() async throws {
        let made = try AssistFixture.makeRunner(alsoCourse: "MPM2D", surface: .mcp)
        defer { try? FileManager.default.removeItem(at: made.root) }

        let wanted: String = AssistToolRefusal.noSectionNamed("MPM2D", [1, 2]).message
        let wrong: String = AssistToolRefusal.noSuchSection("MPM2D", 0).message

        var checked: [String] = []
        for tool in AssistToolRunner.mcpTools {
            if !tool.required.contains("section") || tool.name == "back_up_course" {
                continue
            }
            checked.append(tool.name)
            let outcome: AssistToolOutcome = await made.runner.run(
                call: call(tool.name, arguments: ["course": "MPM2D"])
            )
            let said: String = outcome.summary + "\n" + outcome.detail
            XCTAssertTrue(said.contains(wanted), "\(tool.name): \(said)")
            XCTAssertFalse(said.contains(wrong), "\(tool.name): \(said)")
        }
        // The tools measured for #865: thirty-three of the thirty-eight take
        // a section, and thirty-two of those refuse without one. A count, so a tool added later is checked too, and a
        // surface that lost them all cannot pass by checking nothing.
        XCTAssertGreaterThanOrEqual(checked.count, 32, "\(checked)")
        XCTAssertTrue(checked.contains("list_curriculum_expectations"), "\(checked)")
    }

    /// A course with exactly one section still has only one answer, so a
    /// call that names none is answered for that section, as before.
    @MainActor
    func testACourseWithOneSectionIsStillAnsweredForIt() async throws {
        let made = try AssistFixture.makeRunner(surface: .mcp)
        defer { try? FileManager.default.removeItem(at: made.root) }

        for name in ["list_pages", "list_curriculum_expectations", "check_section"] {
            let outcome: AssistToolOutcome = await made.runner.run(
                call: call(name, arguments: ["course": "ICS3U"])
            )
            let said: String = outcome.summary + "\n" + outcome.detail
            XCTAssertFalse(
                said.contains(AssistToolRefusal.noSectionNamed("ICS3U", [1]).message), "\(name): \(said)"
            )
            XCTAssertFalse(said.contains(AssistToolRefusal.noSuchSection("ICS3U", 0).message), "\(name): \(said)")
        }
    }

    /// A section that IS named and does not exist keeps its own refusal.
    @MainActor
    func testANamedSectionThatIsNotThereIsStillSaidByNumber() async throws {
        let made = try AssistFixture.makeRunner(alsoCourse: "MPM2D", surface: .mcp)
        defer { try? FileManager.default.removeItem(at: made.root) }

        let outcome: AssistToolOutcome = await made.runner.run(
            call: call("list_curriculum_expectations", arguments: ["course": "MPM2D", "section": 7])
        )
        let said: String = outcome.summary + "\n" + outcome.detail
        XCTAssertTrue(said.contains(AssistToolRefusal.noSuchSection("MPM2D", 7).message), said)
    }

    /// The sentence names every section there is, and a course with none.
    func testTheRefusalNamesEverySection() {
        let three: String = AssistToolRefusal.noSectionNamed("MPM2D", [1, 2, 3]).message
        for number in ["1", "2", "3"] {
            XCTAssertTrue(three.contains(number), three)
        }
        XCTAssertFalse(three.contains("Section 0"), three)

        let none: String = AssistToolRefusal.noSectionNamed("MPM2D", []).message
        XCTAssertTrue(none.contains("MPM2D"), none)
        XCTAssertNotEqual(none, three)
    }

    /// The schedule card names the section the deploy will go to: the only
    /// one when none was named, and none at all when there is a choice. It
    /// said "Section 0" for both.
    @MainActor
    func testTheScheduleCardNeverSaysSectionZero() throws {
        let one = try AssistFixture.makeRunner(alsoCourse: "MPM2D")
        defer { try? FileManager.default.removeItem(at: one.root) }

        let onlySection: String = one.runner.explain(call: call("schedule_deploy", arguments: ["course": "ICS3U"]))
        XCTAssertTrue(onlySection.contains("ICS3U Section 1"), onlySection)
        XCTAssertFalse(onlySection.contains("Section 0"), onlySection)

        let twoSections: String = one.runner.explain(call: call("schedule_deploy", arguments: ["course": "MPM2D"]))
        XCTAssertFalse(twoSections.contains("Section 0"), twoSections)

        let named: String = one.runner.explain(
            call: call("schedule_deploy", arguments: ["course": "MPM2D", "section": 2])
        )
        XCTAssertTrue(named.contains("MPM2D Section 2"), named)
    }

    /// `add_classes` and its plan with no count, or no unit, ask for it and
    /// write nothing. A missing `howMany` used to become 0 and send the call
    /// down the "next class" path, which planned one class after the last.
    @MainActor
    func testAddClassesWithoutACountOrAUnitAsksAndWritesNothing() async throws {
        let shapes: [[String: Any]] = [
            ["course": "ICS3U", "section": 1, "unit": 1],
            ["course": "ICS3U", "section": 1, "unit": 1, "howMany": 0],
            ["course": "ICS3U", "section": 1, "howMany": 2],
        ]
        for arguments in shapes {
            for name in ["plan_add_classes", "add_classes"] {
                let made = try AssistFixture.makeRunner(surface: .mcp)
                defer { try? FileManager.default.removeItem(at: made.root) }
                try seedAUnit(in: made.course)
                let before: [String] = pageNames(in: made.course)

                let outcome: AssistToolOutcome = await made.runner.run(call: call(name, arguments: arguments))
                let said: String = outcome.summary + "\n" + outcome.detail

                XCTAssertEqual(pageNames(in: made.course), before, "\(name) \(arguments) wrote: \(said)")
                XCTAssertFalse(said.contains("Unit 1, Day 3"), "\(name) \(arguments): \(said)")
                XCTAssertFalse(said.contains("Unit 2, Day 1"), "\(name) \(arguments): \(said)")
            }
        }
    }

    /// With both given, nothing changes: the count still reaches the planner.
    @MainActor
    func testAddClassesWithBothStillPlansThem() async throws {
        let made = try AssistFixture.makeRunner(surface: .mcp)
        defer { try? FileManager.default.removeItem(at: made.root) }
        try seedAUnit(in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "plan_add_classes", arguments: ["course": "ICS3U", "section": 1, "unit": 1, "howMany": 2]
        ))
        XCTAssertTrue(outcome.detail.contains("Unit 1, Day 4"), outcome.detail)
    }

    // MARK: - Helpers

    private func call(_ name: String, arguments: [String: Any]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(
                name: name, arguments: String(decoding: encoded, as: UTF8.self)
            )
        )
    }

    /// Class dates on file and a unit with two days, as `AddClassesTests`
    /// sets one up, so adding days has something to continue from.
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
    private func pageNames(in course: Course) -> [String] {
        let folder: URL = course.directoryURL.appendingPathComponent("section1/All Classes")
        var names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        names.sort()
        return names
    }
}
