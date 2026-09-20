import XCTest
@testable import QuartzTeachers

/// The page for the next class, and the timetable it takes its date from.
///
/// The chore this removes: a teacher finishing a lesson wants tomorrow's page
/// to exist, correctly numbered and correctly dated, without opening
/// frontmatter to work either out.
///
/// Two rules carry the whole feature, and they are separate on purpose:
///
/// * The NUMBER continues the unit being taught — Unit 3, Day 2 becomes
///   Unit 3, Day 3. Starting a new unit is a teacher's decision.
/// * The DATE comes from POSITION IN THE TIMETABLE. Count the section's class
///   pages, add one, take that date. Never from the unit and day numbering,
///   which is why the tests below deliberately set the two at odds.
final class NextClassTests: XCTestCase {

    // MARK: - Fixtures

    /// Runs nothing. Nothing here should reach Docker, and a preview rebuild
    /// that happened would be a failure worth seeing rather than waiting for.
    @MainActor
    final class StubSiteWork: AssistSiteWork {

        // MARK: - Stored properties

        private(set) var previewRebuilds: Int = 0
        private(set) var deploys: Int = 0

        // MARK: - Functions

        func rebuildPreview(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {
            previewRebuilds += 1
            return AssistSiteWorkResult(succeeded: true, message: "Rebuilt the preview.")
        }

        func deploy(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {
            deploys += 1
            return AssistSiteWorkResult(succeeded: true, message: "Deployed.")
        }
    }

    /// A working folder holding one course with one section, and — unless the
    /// caller asks for none — a remembered timetable of eight meeting days.
    @MainActor
    func makeWorkspace(
        meetingDates: [String] = [
            "2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16",
            "2026-09-18", "2026-09-22", "2026-09-24", "2026-09-28",
        ]
    ) throws -> (root: URL, course: Course, runner: AssistToolRunner, siteWork: StubSiteWork) {
        let fileManager: FileManager = FileManager.default
        let root: URL = fileManager.temporaryDirectory
            .appendingPathComponent("next-class-\(UUID().uuidString)")
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        // A working folder is recognised by its launchers; stubs are enough,
        // and nothing in these tests ever runs one.
        try "#!/bin/bash\n".write(
            to: root.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8
        )
        try "#!/bin/bash\n".write(
            to: root.appendingPathComponent("deploy.sh"), atomically: true, encoding: .utf8
        )

        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        let course: Course = try XCTUnwrap(workspace.courses.first)

        if !meetingDates.isEmpty {
            let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
                dates: meetingDates, source: "timetable.xlsx, block H", forSection: 1, in: course
            )
            try SectionTimetableStore.applyRememberTimetable(plan)
        }

        let siteWork: StubSiteWork = StubSiteWork()
        let runner: AssistToolRunner = AssistToolRunner(
            workspace: workspace,
            siteWork: siteWork,
            today: { return CalendarDay(year: 2026, month: 9, day: 8)! }
        )
        return (root, course, runner, siteWork)
    }

    @MainActor
    func writeClass(_ title: String, on date: String, body: String, in course: Course) throws {
        let page: String = """
        ---
        title: \(title)
        publish: true
        created: \(date)T07:00:00.000-0400
        ---

        \(body)
        """
        try page.write(
            to: ClassPages.folderURL(forSection: 1, in: course).appendingPathComponent(title + ".md"),
            atomically: true, encoding: .utf8
        )
    }

    @MainActor
    func text(ofClass title: String, in course: Course) -> String {
        let url: URL = ClassPages.folderURL(forSection: 1, in: course)
            .appendingPathComponent(title + ".md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @MainActor
    func pageCount(in course: Course) -> Int {
        return ClassPages.list(forSection: 1, in: course).count
    }

    func call(_ name: String, arguments: [String: Any] = [:]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(
                name: name, arguments: String(decoding: encoded, as: UTF8.self)
            )
        )
    }

    // MARK: - The number continues the unit

    /// Unit 3, Day 2 becomes Unit 3, Day 3. The highest unit, then the highest
    /// day INSIDE that unit — a new unit is a teacher's decision, not a tool's.
    @MainActor
    func testTheNextClassContinuesTheHighestUnit() async throws {
        let made = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try writeClass("Unit 2, Day 1", on: "2026-09-08", body: "arrays", in: made.course)
        try writeClass("Unit 3, Day 1", on: "2026-09-10", body: "files", in: made.course)
        try writeClass("Unit 3, Day 2", on: "2026-09-14", body: "more files", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertFalse(outcome.shouldContinue, "A write is the end of the turn.")
        XCTAssertTrue(outcome.summary.contains("Unit 3, Day 3"), outcome.summary)

        let created: String = text(ofClass: "Unit 3, Day 3", in: made.course)
        XCTAssertTrue(created.contains("title: Unit 3, Day 3"))
        XCTAssertTrue(created.contains("publish: false"),
                      "A page nobody has written yet has no business on the site")
        XCTAssertTrue(created.contains("- unit-3"), "It joins the unit it continues")
        XCTAssertEqual(made.siteWork.previewRebuilds, 0,
                       "An unpublished page changes nothing on the site, so nothing is rebuilt")
    }

    /// A section with no numbered class at all starts at Unit 1, Day 1 rather
    /// than guessing.
    @MainActor
    func testASectionWithNoNumberedClassStartsAtUnitOneDayOne() async throws {
        let made = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(outcome.summary.contains("Unit 1, Day 1"), outcome.summary)
        XCTAssertTrue(text(ofClass: "Unit 1, Day 1", in: made.course).contains("created: 2026-09-08"),
                      "The first class takes the first date in the timetable")
    }

    // MARK: - The date comes from the timetable, not from the numbering

    /// Two units of three, so the sixteenth-date rule and the day-number rule
    /// give different answers — and the timetable wins.
    ///
    /// Unit 2, Day 4 is the NAME. Six class pages exist, so the date is the
    /// seventh recorded one. Reading the date off the day number would put the
    /// new class on the fourth date, which another class is already teaching.
    @MainActor
    func testTheDateIsTheNextTimetableEntryRatherThanTheDayNumber() async throws {
        let made = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "one", in: made.course)
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "two", in: made.course)
        try writeClass("Unit 1, Day 3", on: "2026-09-14", body: "three", in: made.course)
        try writeClass("Unit 2, Day 1", on: "2026-09-16", body: "four", in: made.course)
        try writeClass("Unit 2, Day 2", on: "2026-09-18", body: "five", in: made.course)
        try writeClass("Unit 2, Day 3", on: "2026-09-22", body: "six", in: made.course)

        let plan: PlaceholderClassPlan = try NextClassPlanner.plan(forSection: 1, in: made.course)
        XCTAssertEqual(plan.classes.count, 1)
        XCTAssertEqual(plan.classes[0].title, "Unit 2, Day 4")
        XCTAssertEqual(plan.classes[0].date.text, "2026-09-24",
                       "Six class pages, so the seventh recorded date")
        XCTAssertNotEqual(plan.classes[0].date.text, "2026-09-16",
                          "Day 4 must not be read as the fourth date — that day is already taught")
        XCTAssertEqual(plan.spareDatesLeft, 1)
        XCTAssertTrue(plan.description.contains("Unit 2, Day 4  (2026-09-24 Thursday)"),
                      "The plan reads the day of the week out, because that is how a teacher checks a date")
    }

    /// Pages named some other way still COUNT, even though they carry no
    /// numbers. A field trip took a class day; the next lesson is the day
    /// after it, not the day the numbering would suggest.
    @MainActor
    func testPagesWithNoUnitAndDayStillTakeUpADate() async throws {
        let made = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "one", in: made.course)
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "two", in: made.course)
        try writeClass("Field Trip", on: "2026-09-14", body: "the museum", in: made.course)

        let plan: PlaceholderClassPlan = try NextClassPlanner.plan(forSection: 1, in: made.course)
        XCTAssertEqual(plan.classes[0].title, "Unit 1, Day 3",
                       "The field trip has no number, so it does not move the numbering on")
        XCTAssertEqual(plan.classes[0].date.text, "2026-09-16",
                       "But it did take up a class day, so the date moves on for it")
    }

    // MARK: - Refusals a teacher can act on

    /// No timetable is a sentence naming what to do about it, not a shrug.
    @MainActor
    func testASectionWithNoTimetableIsRefusedWithSomethingToDoAboutIt() async throws {
        let made = try makeWorkspace(meetingDates: [])
        defer { try? FileManager.default.removeItem(at: made.root) }

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertFalse(outcome.shouldContinue, "A refused write is still the end of the turn.")
        XCTAssertTrue(outcome.summary.contains("don’t know when ICS3U Section 1 meets"), outcome.summary)
        XCTAssertFalse(outcome.summary.contains("remember_timetable"),
                       "The local model cannot see that tool, so being sent to it is a dead end")
        XCTAssertTrue(outcome.summary.contains(AssistWording.mayIAskForYourDates),
                      "The refusal asks for what is missing rather than describing it")
        XCTAssertEqual(pageCount(in: made.course), 0, "And nothing was written")

        // The way out is the SHEET, and this OFFERS it. Left unwired, the
        // assistant would refuse for ever: the tool that records dates is off
        // the local surface, so nothing else can ask. Offered rather than
        // opened, because a form that arrives on top of the sentence
        // explaining it is a demand.
        XCTAssertNil(SectionSchedulePrompt.shared.request,
                     "A form appeared before the teacher had read the request")
        let asked = try XCTUnwrap(SectionSchedulePrompt.shared.offer,
                                  "Nothing asked the teacher for the dates")
        XCTAssertEqual(asked.courseCode, "ICS3U")
        XCTAssertEqual(asked.sectionNumber, 1)
        SectionSchedulePrompt.shared.stopAsking()

        // The plan twin says the same thing rather than crashing on the way to
        // showing a plan that cannot exist.
        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(planned.detail.contains("don’t know when ICS3U Section 1 meets"))
    }

    /// A timetable that has run out says how many classes and how many dates,
    /// because "index out of range" tells a teacher nothing they can act on.
    ///
    /// **It no longer refuses.** Running out of dates used to mean no page at
    /// all, on the reasoning that a page with a made-up date is worse than
    /// none — but that is not the choice a teacher faces. They have just
    /// finished teaching and want tomorrow's page to write into; being sent
    /// away to record dates first costs them the ten minutes they had. The
    /// page is made on the LAST class date, where it sits beside the final
    /// class and cannot be missed, and the plan says it is sharing.
    @MainActor
    func testAClassPastTheEndOfTheTimetableIsMadeOnTheLastDay() async throws {
        let made = try makeWorkspace(meetingDates: ["2026-09-08", "2026-09-10"])
        defer { try? FileManager.default.removeItem(at: made.root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "one", in: made.course)
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "two", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertEqual(pageCount(in: made.course), 3, "The teacher was sent away instead of helped")
        XCTAssertTrue(text(ofClass: "Unit 1, Day 3", in: made.course).contains("2026-09-10"),
                      "It should share the last class date")
        XCTAssertTrue(outcome.detail.contains("shares the last day"), outcome.detail)
        XCTAssertFalse(outcome.summary.contains("remember_timetable"), outcome.summary)
        // The class that was already there is untouched.
        XCTAssertTrue(text(ofClass: "Unit 1, Day 2", in: made.course).contains("two"))
    }

    // MARK: - Nothing is ever written over

    /// A page with the wanted name may be a lesson written months ago. It is
    /// never written over, and that is checked TWICE — Obsidian is open in the
    /// other window, and a page can appear between the plan and the yes.
    @MainActor
    func testAnExistingPageIsNeverWrittenOver() async throws {
        let made = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "written in July", in: made.course)

        let plan: PlaceholderClassPlan = try NextClassPlanner.plan(forSection: 1, in: made.course)
        XCTAssertEqual(plan.classes[0].title, "Unit 1, Day 2")

        // The teacher starts the page themselves while they are deciding.
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "started in Obsidian just now",
                       in: made.course)

        let outcome: ClassChangeOutcome = try PlaceholderClassPlanner.apply(plan, in: made.course)
        XCTAssertTrue(outcome.message.contains("appeared while you were deciding"), outcome.message)
        XCTAssertTrue(text(ofClass: "Unit 1, Day 2", in: made.course).contains("started in Obsidian just now"),
                      "The page written between the plan and the yes survives untouched")
        XCTAssertTrue(text(ofClass: "Unit 1, Day 1", in: made.course).contains("written in July"))

        // And asked again, the tool moves on rather than insisting.
        let again: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(again.summary.contains("Unit 1, Day 3"), again.summary)
        XCTAssertTrue(text(ofClass: "Unit 1, Day 2", in: made.course).contains("started in Obsidian just now"))
    }

    /// The plan twin changes nothing on disk — which is the whole promise a
    /// teacher is being asked to read a plan on the strength of.
    @MainActor
    func testThePlanTwinChangesNothingOnDisk() async throws {
        let made = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "one", in: made.course)

        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(planned.shouldContinue, "A plan is a read.")
        XCTAssertTrue(planned.detail.contains("Unit 1, Day 2  (2026-09-10 Thursday)"))
        XCTAssertTrue(planned.detail.contains("unpublished"))
        XCTAssertTrue(planned.detail.contains("Nothing has been changed."))

        XCTAssertEqual(pageCount(in: made.course), 1, "Planning wrote no page")
        XCTAssertEqual(text(ofClass: "Unit 1, Day 2", in: made.course), "")

        // And the plan really was the plan: the write lands where it said.
        let done: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(done.summary.contains("Unit 1, Day 2, dated 2026-09-10"), done.summary)
        XCTAssertTrue(text(ofClass: "Unit 1, Day 2", in: made.course).contains("created: 2026-09-10"))
    }

    // MARK: - The remembered timetable

    /// A section with nothing recorded says so plainly, rather than answering
    /// with an empty list a model would read as "no classes".
    @MainActor
    func testReadingATimetableThatIsNotThereSaysSoPlainly() async throws {
        let made = try makeWorkspace(meetingDates: [])
        defer { try? FileManager.default.removeItem(at: made.root) }

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "read_remembered_timetable", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertFalse(outcome.shouldContinue, "A read finishes turn immediately without looping into LLM.")
        XCTAssertTrue(outcome.summary.contains("don't know when"), outcome.summary)
        XCTAssertFalse(outcome.detail.contains("remember_timetable"),
                       "That tool is off the local surface; naming it is a remedy the model cannot reach")
        // ASKS rather than opening. The sheet used to appear on top of the
        // sentence explaining why it had appeared.
        XCTAssertTrue(outcome.summary.contains(AssistWording.mayIAskForYourDates), outcome.summary)
        XCTAssertNil(SectionSchedulePrompt.shared.request,
                     "A form appeared before the teacher had read the request")
        XCTAssertNotNil(SectionSchedulePrompt.shared.offer, "Reading an empty timetable asks for one")
        SectionSchedulePrompt.shared.stopAsking()
    }

    /// Recorded, then read back with WHERE THEY CAME FROM — which is how a
    /// teacher recognises a stale answer and replaces it.
    @MainActor
    func testRememberingDatesAndReadingThemBackWithTheirSource() async throws {
        let made = try makeWorkspace(meetingDates: [])
        defer { try? FileManager.default.removeItem(at: made.root) }

        // The plan first, which writes nothing.
        let planned: AssistToolOutcome = await made.runner.run(call: call(
            "plan_remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; 2026-09-10; 2026-09-14",
                        "source": "timetable.xlsx, block H"]
        ))
        XCTAssertTrue(planned.shouldContinue)
        XCTAssertTrue(planned.detail.contains("Remember 3 class dates"))
        XCTAssertNil(try SectionTimetableStore.read(forSection: 1, in: made.course),
                     "A plan records nothing")

        let done: AssistToolOutcome = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; 2026-09-10; 2026-09-14",
                        "source": "timetable.xlsx, block H"]
        ))
        XCTAssertFalse(done.shouldContinue)
        XCTAssertTrue(done.summary.contains("Remembered 3 class dates"), done.summary)

        let stored: SectionTimetable = try XCTUnwrap(
            try SectionTimetableStore.read(forSection: 1, in: made.course)
        )
        XCTAssertEqual(stored.datesText, ["2026-09-08", "2026-09-10", "2026-09-14"])

        let read: AssistToolOutcome = await made.runner.run(call: call(
            "read_remembered_timetable", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(read.detail.contains("timetable.xlsx, block H"))
        XCTAssertTrue(read.detail.contains("2026-09-08"))
        XCTAssertTrue(read.detail.contains("next class would fall on 2026-09-08"),
                      "Reading it back says what it is for")

        // And the dates it just recorded really do date the next class.
        let added: AssistToolOutcome = await made.runner.run(call: call(
            "add_next_class", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(added.summary.contains("dated 2026-09-08"), added.summary)
    }

    /// A half-readable list is refused WHOLE and nothing is stored. A
    /// half-remembered timetable does not announce itself — it gets trusted,
    /// and then dates the wrong classes.
    @MainActor
    func testAListWithAnUnreadableDateIsRefusedWhole() async throws {
        let made = try makeWorkspace(meetingDates: [])
        defer { try? FileManager.default.removeItem(at: made.root) }

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "remember_timetable",
            arguments: ["course": "ICS3U", "section": 1,
                        "dates": "2026-09-08; next Tuesday; 2026-09-14", "source": "typed in by hand"]
        ))
        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(outcome.summary.contains("“next Tuesday”"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains("the whole list is refused"), outcome.summary)
        XCTAssertNil(try SectionTimetableStore.read(forSection: 1, in: made.course),
                     "Nothing at all is stored from a list that was refused")
    }

    // MARK: - The rules the surface lives by

    /// The five new tools obey the same rules as the rest: a `plan_` twin in
    /// front of every write, nothing destructive, and no gate on anything but
    /// the two acts that reach students.
    @MainActor
    func testTheNewToolsKeepTheSurfaceRules() throws {
        let added: [String] = [
            "read_remembered_timetable", "plan_remember_timetable", "remember_timetable",
            "plan_add_next_class", "add_next_class",
        ]

        var byName: [String: AssistToolDefinition] = [:]
        for tool in AssistToolRunner.tools {
            byName[tool.name] = tool
        }

        for name in added {
            let definition: AssistToolDefinition = try XCTUnwrap(byName[name], "\(name) is not on the surface")
            XCTAssertFalse(definition.needsApproval,
                           "Only deploying and scheduling a deploy wait for a button")
            for word in ["delete", "remove", "rename", "archive", "erase", "destroy", "move"] {
                XCTAssertFalse(definition.name.contains(word),
                               "\(name) contains “\(word)”, and nothing on this surface may destroy anything")
            }
            if definition.readOnly {
                continue
            }
            let twin: String = try XCTUnwrap(definition.planTwinName)
            XCTAssertNotNil(byName[twin], "\(name) changes things but has no \(twin) to show first")
            XCTAssertEqual(byName[twin]?.readOnly, true, "\(twin) must change nothing")
        }

        // The three reads really are reads.
        XCTAssertEqual(byName["read_remembered_timetable"]?.readOnly, true)
        XCTAssertEqual(byName["plan_remember_timetable"]?.readOnly, true)
        XCTAssertEqual(byName["plan_add_next_class"]?.readOnly, true)
    }

    /// `add_next_class` asks for nothing but the course and the section. The
    /// numbering and the date are the two things a teacher does by hand today,
    /// so a tool that asked for either would have removed no chore at all.
    @MainActor
    func testAddingTheNextClassAsksForNoDateAndNoUnit() throws {
        var found: AssistToolDefinition? = nil
        for tool in AssistToolRunner.tools where tool.name == "add_next_class" {
            found = tool
        }
        let definition: AssistToolDefinition = try XCTUnwrap(found)
        XCTAssertEqual(Set(definition.parameters.keys), ["course", "section"])
        XCTAssertEqual(Set(definition.required), ["course", "section"])
    }
}
