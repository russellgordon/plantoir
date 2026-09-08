import XCTest
@testable import QuartzTeachers

/// Pointing a page at the curriculum expectations it covers.
///
/// Two things are pinned here and they matter for different reasons. The first
/// is the SHAPE OF THE SURFACE: these tools are served to the MCP client only,
/// because the local model's list is a measurement — routing accuracy was
/// counted against it — and every tool added to it spends some of a number
/// somebody else already paid for.
///
/// The second is WHERE THE TRANSCLUSIONS LAND. They go inside the
/// `%%curriculum-start%%` markers, always. A course installed without
/// curriculum pages has that whole block stripped when the site is built, so a
/// transclusion written outside the markers would survive the stripping and
/// leave a teacher's live site pointing at a page that does not exist.
final class AssistCurriculumMentionsTests: XCTestCase {

    // MARK: - The two surfaces

    /// The local model sees the narrowed surface, and the MCP client sees that
    /// surface plus the curriculum tools.
    ///
    /// **The number the local model is shown is the one that matters, and it
    /// has not moved.** The surface itself has grown — fifteen to twenty when
    /// the timetable and next-class tools arrived, then twenty-two with
    /// re-dating — while what the model is SHOWN has stayed at thirteen
    /// throughout, because every schema in the prompt costs a little router
    /// accuracy and none of those additions is something it has to name.
    ///
    /// The curriculum tools are on neither: which expectations fit a lesson is
    /// a judgement about meaning. Re-dating is off for a different reason —
    /// its phrasings are matched in code, and rewriting the date on every page
    /// in a section is too large a change to reach through a router that is
    /// right four times in five.
    @MainActor
    func testTheLocalModelSurfaceIsNarrowAndTheMcpSurfaceIsLarger() {
        XCTAssertEqual(AssistToolRunner.tools.count, 22)
        XCTAssertEqual(AssistToolRunner.localTools.count, 13,
                       "What the model is shown must not grow when the surface does")

        var shownToTheLocalModel: Set<String> = []
        for tool in AssistToolRunner.localTools {
            shownToTheLocalModel.insert(tool.name)
        }

        var localNames: Set<String> = []
        for tool in AssistToolRunner.tools {
            localNames.insert(tool.name)
        }
        var mcpNames: Set<String> = []
        for tool in AssistToolRunner.mcpTools {
            mcpNames.insert(tool.name)
        }

        // The MCP-only tools, and WHY each is not on the local list. The
        // curriculum three are a judgement about meaning; `list_courses` is
        // simply never needed there, because the window is scoped to one
        // section and `AssistAgent.systemPrompt` already names the course —
        // while a Claude Code session is handed a FOLDER and has no other way
        // to find out what is in it.
        // The MCP-only tools, and WHY each is not on the local list. The
        // curriculum three are a judgement about meaning; `list_courses` is
        // never needed there, because the window is scoped to one section and
        // `AssistAgent.systemPrompt` already names the course; and the
        // `add_classes` pair is a capability the local model reaches ANYWAY
        // through the "add five more days to Unit 4" phrasing, matched in code
        // — so publishing its schema would spend routing accuracy to buy the
        // model something it already has a deterministic route to.
        let added: Set<String> = [
            "list_courses",
            "plan_add_classes", "add_classes",
            "plan_make_room_for_classes", "make_room_for_classes",
            "explain_publishing", "back_up_course",
            "list_curriculum_expectations", "plan_curriculum_mentions", "add_curriculum_mentions",
        ]
        for name in added {
            XCTAssertFalse(localNames.contains(name), "\(name) must not reach the local model.")
            XCTAssertFalse(shownToTheLocalModel.contains(name),
                           "\(name) must not be shown to the local model.")
            XCTAssertTrue(mcpNames.contains(name), "\(name) is missing from the MCP surface.")
        }
        XCTAssertEqual(mcpNames.count, localNames.count + added.count)
        XCTAssertEqual(AssistToolRunner.mcpTools.count, mcpNames.count, "A tool is defined twice.")
    }

    /// The rules the fifteen live by hold on the longer surface too: a `plan_`
    /// twin in front of the write, nothing destructive anywhere, and no gate
    /// on anything but the two acts that reach students.
    @MainActor
    func testTheLongerSurfaceKeepsTheSameRules() {
        var names: Set<String> = []
        var needingApproval: Set<String> = []
        for tool in AssistToolRunner.mcpTools {
            names.insert(tool.name)
            if tool.needsApproval {
                needingApproval.insert(tool.name)
            }
            for word in ["delete", "remove", "rename", "archive", "erase", "destroy"] {
                XCTAssertFalse(
                    tool.name.contains(word),
                    "\(tool.name) contains “\(word)”, and nothing on this surface may destroy anything."
                )
            }
        }

        XCTAssertTrue(names.contains("plan_curriculum_mentions"))
        XCTAssertEqual(needingApproval, ["deploy_section", "schedule_deploy"])
    }

    // MARK: - Reading the expectations out

    /// The wording, not just the code — the whole point is that whoever is
    /// driving can tell whether an expectation fits the lesson. Strand
    /// headings and the folder's index are not expectations and are left out.
    @MainActor
    func testTheExpectationsComeBackWithTheirWording() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "list_curriculum_expectations", arguments: ["course": "ICS3U", "section": 1]
        ))
        XCTAssertTrue(outcome.shouldContinue)
        XCTAssertTrue(outcome.detail.contains("A1.1  use a variety of problem-solving strategies"))
        XCTAssertTrue(outcome.detail.contains("A2.2"))
        XCTAssertFalse(outcome.detail.contains("A1. The Creative Process"))
        XCTAssertFalse(outcome.detail.contains("About These Expectations"))
        // The block anchor is not part of what the expectation says.
        XCTAssertFalse(outcome.detail.contains("^text"))

        let narrowed: AssistToolOutcome = await made.runner.run(call: call(
            "list_curriculum_expectations",
            arguments: ["course": "ICS3U", "section": 1, "matching": "debugging"]
        ))
        XCTAssertTrue(narrowed.detail.contains("A2.2"))
        XCTAssertFalse(narrowed.detail.contains("A1.1"))

        let nothing: AssistToolOutcome = await made.runner.run(call: call(
            "list_curriculum_expectations",
            arguments: ["course": "ICS3U", "section": 1, "matching": "photosynthesis"]
        ))
        XCTAssertTrue(nothing.detail.contains("No curriculum expectation in ICS3U matches"))
    }

    // MARK: - Where the transclusions land

    /// Inside the markers the page already has, and nowhere else.
    @MainActor
    func testATransclusionLandsInsideTheMarkersAlreadyThere() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Debugging", body: """
        Reading an error message is a skill.

        %%curriculum-start%%
        ## Curriculum connection

        ![[A1.1]]
        %%curriculum-end%%
        """, in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_curriculum_mentions",
            arguments: ["course": "ICS3U", "section": 1, "page": "Debugging", "codes": "A2.2"]
        ))
        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertTrue(outcome.summary.contains("Added 1 curriculum expectation to “Debugging”."))

        let text: String = self.text(ofPage: "Debugging", in: made.course)
        let start: String.Index = try XCTUnwrap(text.range(of: "%%curriculum-start%%")?.lowerBound)
        let added: String.Index = try XCTUnwrap(text.range(of: "![[A2.2]]")?.lowerBound)
        let end: String.Index = try XCTUnwrap(text.range(of: "%%curriculum-end%%")?.lowerBound)
        XCTAssertTrue(start < added, "The transclusion landed outside the markers.")
        XCTAssertTrue(added < end, "The transclusion landed outside the markers.")

        // The one that was already there is untouched, and there is still only
        // one block on the page.
        XCTAssertTrue(text.contains("![[A1.1]]"))
        XCTAssertEqual(occurrences(of: "%%curriculum-start%%", in: text), 1)
        XCTAssertEqual(occurrences(of: "%%curriculum-end%%", in: text), 1)
        XCTAssertTrue(text.contains("![[A1.1]]\n\n![[A2.2]]"), "Transclusions are blank-line separated.")
    }

    /// A page with no markers gets the whole block, in the shape the payloads
    /// use — markers, the `## Curriculum connection` heading, blank-line
    /// separated transclusions.
    @MainActor
    func testAPageWithNoMarkersGetsAWellFormedBlock() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Loops", body: "A loop repeats work you would not want to write twice.",
                  in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_curriculum_mentions",
            arguments: ["course": "ICS3U", "section": 1, "page": "Loops", "codes": "A1.1, A2.2"]
        ))
        XCTAssertTrue(outcome.summary.contains("Added 2 curriculum expectations"))

        let text: String = self.text(ofPage: "Loops", in: made.course)
        XCTAssertTrue(text.contains("""
        %%curriculum-start%%
        ## Curriculum connection

        ![[A1.1]]

        ![[A2.2]]
        %%curriculum-end%%
        """))
        // The lesson is still there, and the block did not swallow it.
        XCTAssertTrue(text.contains("A loop repeats work"))
    }

    /// The curriculum note belongs with the lesson, not after the homework.
    @MainActor
    func testANewBlockGoesInFrontOfTheThingsToDoList() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Arrays", body: """
        An array holds many values under one name.

        ## Things to do before our next class

        Finish the practice set.
        """, in: made.course)

        _ = await made.runner.run(call: call(
            "add_curriculum_mentions",
            arguments: ["course": "ICS3U", "section": 1, "page": "Arrays", "codes": "A1.1"]
        ))

        let text: String = self.text(ofPage: "Arrays", in: made.course)
        let block: String.Index = try XCTUnwrap(text.range(of: "%%curriculum-start%%")?.lowerBound)
        let homework: String.Index = try XCTUnwrap(
            text.range(of: "## Things to do before our next class")?.lowerBound
        )
        XCTAssertTrue(block < homework)
        XCTAssertTrue(text.contains("Finish the practice set."))
    }

    /// An expectation the page already points at is left alone, and said so.
    @MainActor
    func testAnExpectationAlreadyThereIsNotDuplicated() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Debugging", body: """
        %%curriculum-start%%
        ## Curriculum connection

        ![[A1.1]]
        %%curriculum-end%%
        """, in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_curriculum_mentions",
            arguments: ["course": "ICS3U", "section": 1, "page": "Debugging", "codes": "A1.1"]
        ))
        XCTAssertTrue(outcome.summary.contains("Nothing needed adding."))
        XCTAssertTrue(outcome.detail.contains("already points at A1.1"))

        let text: String = self.text(ofPage: "Debugging", in: made.course)
        XCTAssertEqual(occurrences(of: "![[A1.1]]", in: text), 1)
    }

    /// A code that matches no expectation is NAMED rather than dropped: it
    /// usually means a typo, and saying nothing would leave the teacher
    /// believing it was added.
    @MainActor
    func testACodeThatMatchesNothingIsNamed() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Loops", body: "A loop repeats work.", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "plan_curriculum_mentions",
            arguments: ["course": "ICS3U", "section": 1, "page": "Loops", "codes": "A1.1, Z9.9"]
        ))
        XCTAssertTrue(outcome.detail.contains("Z9.9 is not an expectation in ICS3U"))
        XCTAssertTrue(outcome.detail.contains("A1.1"))
    }

    // MARK: - The plan changes nothing

    @MainActor
    func testThePlanTwinChangesNothingOnDisk() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Loops", body: "A loop repeats work you would not want to write twice.",
                  in: made.course)
        let before: String = text(ofPage: "Loops", in: made.course)

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "plan_curriculum_mentions",
            arguments: ["course": "ICS3U", "section": 1, "page": "Loops", "codes": "A1.1, A2.2"]
        ))
        XCTAssertTrue(outcome.shouldContinue, "A plan hands back so its reasoning can be read out.")
        XCTAssertTrue(outcome.detail.contains("Add 2 curriculum expectations to “Loops”"))
        // The WORDING, quoted, so a teacher can tell whether it fits without
        // going and looking the code up.
        XCTAssertTrue(outcome.detail.contains("use a variety of problem-solving strategies"))
        XCTAssertTrue(outcome.detail.contains("Nothing has been changed."))

        XCTAssertEqual(text(ofPage: "Loops", in: made.course), before, "The plan wrote to the page.")

        // And nothing was recorded to undo, because nothing happened.
        let undo: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))
        XCTAssertEqual(undo.summary, AssistWording.nothingToUndo)
    }

    // MARK: - Taking it back

    /// The write goes through the same backup-and-remember path every other
    /// write uses, so "undo that" takes it straight back off.
    @MainActor
    func testUndoTakesTheCurriculumBlockBackOff() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        try write(page: "Loops", body: "A loop repeats work.", in: made.course)
        let before: String = text(ofPage: "Loops", in: made.course)

        _ = await made.runner.run(call: call(
            "add_curriculum_mentions",
            arguments: ["course": "ICS3U", "section": 1, "page": "Loops", "codes": "A2.2"]
        ))
        XCTAssertNotEqual(text(ofPage: "Loops", in: made.course), before)

        let undo: AssistToolOutcome = await made.runner.run(call: call("undo_last_change"))
        // Named rather than quoted — and the sentence it names is a sentence:
        // "Earlier, you added 1 curriculum expectation to “Loops”. Then you
        // asked me to undo that, and I have done so."
        XCTAssertEqual(
            undo.summary,
            AssistWording.undid("added 1 curriculum expectation to “Loops”")
        )
        XCTAssertEqual(text(ofPage: "Loops", in: made.course), before)
    }

    /// A page nobody has is a sentence, not a stack trace.
    @MainActor
    func testAPageThatIsNotThereIsRefusedInWords() async throws {
        let made = try makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let outcome: AssistToolOutcome = await made.runner.run(call: call(
            "add_curriculum_mentions",
            arguments: ["course": "ICS3U", "section": 1, "page": "Recursion", "codes": "A1.1"]
        ))
        XCTAssertTrue(outcome.detail.contains("No page in ICS3U Section 1 is called “Recursion”"))
    }

    // MARK: - Fixtures

    @MainActor
    private func makeRunner() throws -> (root: URL, course: Course, runner: AssistToolRunner) {
        let fileManager: FileManager = FileManager.default
        let root: URL = fileManager.temporaryDirectory
            .appendingPathComponent("assist-curriculum-\(UUID().uuidString)")
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("Concepts"), withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("Curriculum"), withIntermediateDirectories: true
        )
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

        // The curriculum folder as a payload writes it: leaf expectations
        // coded A1.1, a strand heading and an explainer that are not
        // expectations at all.
        try writeExpectation(
            "A1.1",
            wording: "use a variety of problem-solving strategies to solve programming problems",
            in: courseURL
        )
        try writeExpectation(
            "A2.2",
            wording: "use debugging techniques to identify and correct errors in a program",
            in: courseURL
        )
        try writeCurriculumPage(
            "A1. The Creative Process", body: "The expectations in this strand.", in: courseURL
        )
        try writeCurriculumPage(
            "About These Expectations", body: "Where these came from.", in: courseURL
        )

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        let course: Course = try XCTUnwrap(workspace.courses.first)

        let runner: AssistToolRunner = AssistToolRunner(
            workspace: workspace,
            siteWork: SilentSiteWork(),
            today: CalendarDay(year: 2026, month: 9, day: 8)!,
            launchControl: SilentLaunchControl()
        )
        return (root, course, runner)
    }

    /// Never starts Docker, and is never asked to: adding a transclusion
    /// changes a file and nothing a student can see.
    @MainActor
    final class SilentSiteWork: AssistSiteWork {

        // MARK: - Functions

        func rebuildPreview(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {
            return AssistSiteWorkResult(succeeded: true, message: "Rebuilt the preview.")
        }

        func deploy(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {
            return AssistSiteWorkResult(succeeded: true, message: "Deployed.")
        }
    }

    struct SilentLaunchControl: LaunchControlRunning {
        func bootstrap(plistURL: URL) -> String? {
            return nil
        }

        func bootOut(label: String) {
        }
    }

    private func call(_ name: String, arguments: [String: Any] = [:]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(
                name: name, arguments: String(decoding: encoded, as: UTF8.self)
            )
        )
    }

    /// An expectation page, exactly as a payload writes one: the wording, and
    /// the block anchor a transclusion points at.
    private func writeExpectation(_ code: String, wording: String, in courseURL: URL) throws {
        let text: String = """
        ---
        transcludeTitleSize: h4
        tags:
          - \(code.prefix(2))
        ---
        \(wording) ^text
        """
        try text.write(
            to: courseURL.appendingPathComponent("Curriculum").appendingPathComponent(code + ".md"),
            atomically: true, encoding: .utf8
        )
    }

    private func writeCurriculumPage(_ title: String, body: String, in courseURL: URL) throws {
        try "---\ntitle: \(title)\n---\n\n\(body)\n".write(
            to: courseURL.appendingPathComponent("Curriculum").appendingPathComponent(title + ".md"),
            atomically: true, encoding: .utf8
        )
    }

    @MainActor
    private func write(page title: String, body: String, in course: Course) throws {
        let text: String = """
        ---
        title: \(title)
        publishForSection1: true
        createdSection1: 2026-09-08T07:00:00.000-0400
        ---

        \(body)
        """
        try text.write(to: pageURL(of: title, in: course), atomically: true, encoding: .utf8)
    }

    @MainActor
    private func text(ofPage title: String, in course: Course) -> String {
        return (try? String(contentsOf: pageURL(of: title, in: course), encoding: .utf8)) ?? ""
    }

    @MainActor
    private func pageURL(of title: String, in course: Course) -> URL {
        return course.directoryURL.appendingPathComponent("Concepts")
            .appendingPathComponent(title + ".md")
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        var count: Int = 0
        var searchFrom: String.Index = text.startIndex
        while let found = text.range(of: needle, range: searchFrom..<text.endIndex) {
            count += 1
            searchFrom = found.upperBound
        }
        return count
    }
}
