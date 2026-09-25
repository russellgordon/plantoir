import XCTest
@testable import QuartzTeachers

/// "What does Unit 2, Day 3 link to?" — answered in code, in full, and the end
/// of the turn (issue #167).
///
/// **Why this file exists.** Measured on 2026-09-25, both assistants, the
/// app's own flags, body and prompt: across six courses and fourteen dates,
/// one greedy trial per cell, the plainest phrasing reached `read_page` 0 times
/// in 84 on BOTH tiers, and on the smaller one "Which pages does Unit 2, Day 3
/// link to?" became a publish PLAN 31 times in 84
/// (`research/ai-assist/link-question-results.txt`).
///
/// Every sentence and every answer is read from `contracts/assist-cases.json`
/// → `linksQuestion`, which the Windows suite can run too; the only strings
/// typed here are ones the contract cannot carry — the mac's own rendering of
/// a list line, and the fixture's names.
@MainActor
final class LinksQuestionCardTests: XCTestCase {

    // MARK: - Stored properties

    /// Where the trail goes while a test drives the real agent, so nothing is
    /// written to the Mac's own activity log.
    private var previousStore: ProblemReportStore?

    // MARK: - Setting up

    override func setUp() async throws {
        try await super.setUp()
        previousStore = ActivityTrail.store
    }

    override func tearDown() async throws {
        if let previousStore {
            ActivityTrail.store = previousStore
        }
        try await super.tearDown()
    }

    // MARK: - The grammar

    /// Every sentence the contract accepts is answered in code, in the
    /// contract's window, and asks for the page it names — with the hidden
    /// `answer` argument and no course or section of its own.
    func testEverySentenceTheContractAcceptsIsAnsweredInCode() throws {
        let window: (course: String, section: Int) = try LinksQuestionCardTests.window()
        for row in try LinksQuestionCardTests.rows(named: "accepted") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is accepted for no stated reason")
            let command: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(input, windowCourse: window.course, windowSection: window.section),
                "\"\(input)\" is in the contract as answered in code and matches nothing"
            )
            XCTAssertEqual(command.toolName, "read_page", input)
            XCTAssertEqual(command.arguments["page"], row["expectPage"] as? String, input)
            XCTAssertEqual(command.arguments["answer"], AssistCardCommand.linksAnswer, input)
            XCTAssertEqual(
                command.arguments[AssistCardCommand.linksAsTypedArgument], row["expectAsTyped"] as? String, input
            )
            // A card binds this window's course and section itself, so a card
            // that carried one of its own would be answering a different
            // question with total confidence.
            XCTAssertNil(command.arguments["course"], input)
            XCTAssertNil(command.arguments["section"], input)
        }
    }

    /// Every sentence it refuses goes to the model — neither answered nor
    /// refused in code.
    func testEverySentenceTheContractRefusesGoesToTheModel() throws {
        let window: (course: String, section: Int) = try LinksQuestionCardTests.window()
        for row in try LinksQuestionCardTests.rows(named: "refused") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is refused for no stated reason")
            XCTAssertNil(
                AssistCardCommand.matching(input, windowCourse: window.course, windowSection: window.section),
                "\"\(input)\" is in the contract as one that goes to the model and was matched in code"
            )
            XCTAssertNil(
                AssistCardCommand.linksQuestion(input, windowCourse: window.course, windowSection: window.section),
                "\"\(input)\" goes to the model, and was read as a links question"
            )
        }
    }

    /// Every sentence naming another course is refused in code, naming that
    /// course as it was typed — and is never a card.
    func testEverySentenceNamingAnotherCourseIsRefusedInCode() throws {
        let window: (course: String, section: Int) = try LinksQuestionCardTests.window()
        for row in try LinksQuestionCardTests.rows(named: "anotherCourse") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            let named: String = try XCTUnwrap(row["expectCourse"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is refused for no stated reason")
            XCTAssertEqual(
                AssistCardCommand.linksQuestion(input, windowCourse: window.course, windowSection: window.section),
                .anotherCourse(named),
                input
            )
            XCTAssertNil(
                AssistCardCommand.matching(input, windowCourse: window.course, windowSection: window.section),
                "\"\(input)\" names another course and became a card for this one"
            )
        }
    }

    /// A phrase beginning "the" that is not "the <title> page" is never a card
    /// by itself: it is answered in code only when the section has a page
    /// called that, which the AGENT asks (#167 fix review F2).
    func testEveryPhraseThatIsATitleOnlyIfAPageIsCalledThatIsNeverACardByItself() throws {
        let window: (course: String, section: Int) = try LinksQuestionCardTests.window()
        for row in try LinksQuestionCardTests.rows(named: "onlyIfAPageIsCalled") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            let page: String = try XCTUnwrap(row["expectPage"] as? String)
            XCTAssertNotNil(row["why"] as? String, input)
            XCTAssertEqual(
                AssistCardCommand.linksQuestion(input, windowCourse: window.course, windowSection: window.section),
                .onlyIfAPageIsCalled(page),
                input
            )
            XCTAssertNil(
                AssistCardCommand.matching(input, windowCourse: window.course, windowSection: window.section),
                input
            )
        }
    }

    /// With no window, a sentence naming no place still matches — which is
    /// how the contract's parsed example is run on both platforms — and any
    /// place at all falls through, because there is nothing to compare it with.
    func testWithNoWindowOnlyASentenceNamingNoPlaceMatches() throws {
        let example: AssistCardCommand = try XCTUnwrap(
            AssistCardCommand.matching("what does Unit 2, Day 3 link to?")
        )
        XCTAssertEqual(example.toolName, "read_page")
        XCTAssertEqual(example.arguments["page"], "Unit 2, Day 3")

        for placed in ["What does \"Unit 2, Day 3\" in ICS3U section 1 link to?",
                       "What does Unit 2, Day 3 link to in this section?",
                       "What does Unit 2, Day 3 in SPH3U section 1 link to?"] {
            XCTAssertNil(AssistCardCommand.matching(placed), placed)
            XCTAssertNil(AssistCardCommand.linksQuestion(placed, windowCourse: nil, windowSection: nil), placed)
        }
    }

    // MARK: - The answer

    /// Every answering case in the contract, run through the real tool.
    ///
    /// The contract says what is SHOWN and which mark follows it; the line's
    /// arrangement — a bullet and a dash — is this platform's, and is the only
    /// thing written here.
    func testEveryAnsweringCaseInTheContractSaysWhatItShould() async throws {
        let answering: [String: Any] = try LinksQuestionCardTests.answering()
        let cases: [[String: Any]] = try XCTUnwrap(answering["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10, "The answering cases have been cut down")

        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let body: String = try XCTUnwrap(testCase["body"] as? String)
            let expected: [[String: Any]] = try XCTUnwrap(testCase["expect"] as? [[String: Any]])

            let made = try LinksQuestionCardTests.sectionFromTheContract(askedPageBody: body)
            defer {
                try? FileManager.default.removeItem(at: made.root)
            }
            let outcome: AssistToolOutcome = await made.runner.run(
                call: LinksQuestionCardTests.readLinks(of: "Unit 1, Day 1")
            )
            XCTAssertFalse(outcome.shouldContinue, "\(name): the turn must end with the answer")

            if expected.isEmpty {
                XCTAssertEqual(outcome.summary, AssistWording.pageLinksToNothing(page: "Unit 1, Day 1"), name)
                continue
            }
            var lines: [String] = [AssistWording.pageLinksTo(page: "Unit 1, Day 1")]
            for entry in expected {
                let shown: String = try XCTUnwrap(entry["shown"] as? String)
                var line: String = "• " + shown
                if let mark = entry["mark"] as? String {
                    line += " — " + (try LinksQuestionCardTests.markSentence(named: mark))
                }
                lines.append(line)
            }
            XCTAssertEqual(outcome.summary, lines.joined(separator: "\n"), name)
        }
    }

    /// The page ASKED about is found the way the contract's lookup cases say:
    /// by file name, by the name the sidebar shows, a landing page by its
    /// folder — and two pages sharing a shown name is a question, not a guess.
    func testThePageAskedAboutIsFoundTheWayTheContractSays() async throws {
        let answering: [String: Any] = try LinksQuestionCardTests.answering()
        let lookups: [[String: Any]] = try XCTUnwrap(answering["lookup"] as? [[String: Any]])
        let made = try LinksQuestionCardTests.sectionFromTheContract(askedPageBody: "[[Ohm's Law]]")
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }

        for lookup in lookups {
            let ask: String = try XCTUnwrap(lookup["ask"] as? String)
            let expect: String = try XCTUnwrap(lookup["expect"] as? String)
            let outcome: AssistToolOutcome = await made.runner.run(
                call: LinksQuestionCardTests.readLinks(of: ask, asTyped: lookup["asTyped"] as? String)
            )
            XCTAssertFalse(outcome.shouldContinue, "\(ask): the turn must end in every branch")
            XCTAssertFalse(outcome.summary.contains("list_pages"), "\(ask): a tool's name reached the teacher")

            let notFound: String = AssistWording.noPageCalled(page: ask, course: "ICS3U", section: "1")
            let several: String = AssistWording.morePagesThanOneAreCalled(page: ask, course: "ICS3U", section: "1")
            switch expect {
            case "found":
                XCTAssertNotEqual(outcome.summary, notFound, ask)
                XCTAssertFalse(outcome.summary.hasPrefix(several), ask)
            case "noPageCalled":
                XCTAssertEqual(outcome.summary, notFound, ask)
            case "morePagesThanOneAreCalled":
                XCTAssertTrue(outcome.summary.hasPrefix(several), "\(ask): \(outcome.summary)")
                XCTAssertTrue(outcome.summary.contains("Review A.md"), outcome.summary)
                XCTAssertTrue(outcome.summary.contains("Review B.md"), outcome.summary)
            default:
                XCTFail("\(ask): the contract expects something this test does not know: \(expect)")
            }
        }
    }

    /// Without `answer`, `read_page` is what it has always been — a read the
    /// model gets to answer from.
    func testWithoutTheAnswerArgumentReadPageIsUnchanged() async throws {
        let made = try LinksQuestionCardTests.sectionFromTheContract(askedPageBody: "[[Ohm's Law]]")
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let arguments: [String: Any] = ["course": "ICS3U", "section": 1, "page": "Unit 1, Day 1"]
        let encoded: Data = try JSONSerialization.data(withJSONObject: arguments)
        let outcome: AssistToolOutcome = await made.runner.run(call: AssistToolCall(
            id: "plain", type: "function",
            function: AssistToolCall.Function(name: "read_page", arguments: String(decoding: encoded, as: UTF8.self))
        ))
        XCTAssertTrue(outcome.shouldContinue, "A plain read hands back to the model, as it always has.")
        XCTAssertEqual(outcome.summary, "Read “Unit 1, Day 1”.")
        XCTAssertTrue(outcome.detail.contains("[[Ohm's Law]]"), outcome.detail)
    }

    /// The model is never shown the argument: no schema of either surface
    /// names it, so the surface routing was measured against has not moved.
    func testTheAnswerArgumentIsInNoSchema() throws {
        var every: [AssistToolDefinition] = []
        every.append(contentsOf: AssistToolRunner.localTools)
        every.append(contentsOf: AssistToolRunner.mcpTools)
        for definition in every {
            XCTAssertNil(definition.parameters["answer"], "\(definition.name) now declares `answer`")
        }
    }

    // MARK: - The whole turn, through the real agent

    /// The sentence is answered with the list, the model is never asked — on
    /// that turn or as a lap after it — and nothing is left waiting.
    func testTheQuestionIsAnsweredWithoutTheModelAndTheTurnEnds() async throws {
        let made = try LinksQuestionCardTests.sectionFromTheContract(
            askedPageBody: "See [[Ohm's Law]] and [[Unit 1, Day 2]]."
        )
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        let engine: StubEngine = try StubEngine()
        defer {
            engine.stop()
            try? FileManager.default.removeItem(at: made.root)
        }
        engine.serve(#"{"choices":[{"message":{"role":"assistant","content":"Here it is."}}],"usage":{"completion_tokens":4}}"#)

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        await agent.say("What does Unit 1, Day 1 link to?")

        XCTAssertEqual(engine.requestCount, 0, "the model was asked about a question answered in code")
        XCTAssertEqual(agent.activity, .idle)
        XCTAssertNil(agent.pendingApproval)
        for entry in agent.entries {
            XCTAssertNotEqual(entry.speaker, .problem, entry.text)
        }
        let last: AssistAgent.Entry = try XCTUnwrap(agent.entries.last)
        XCTAssertEqual(last.speaker, .toolResult(name: "read_page"))
        XCTAssertTrue(last.text.hasPrefix(AssistWording.pageLinksTo(page: "Unit 1, Day 1")), last.text)
        XCTAssertTrue(last.text.contains(AssistWording.linkedPageIsADraft), last.text)

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        let line: String = AssistAgent.matchedInCodeLine(for: LinksQuestionCardTests.readLinks(of: "Unit 1, Day 1"))
        XCTAssertTrue(trail.contains(line), trail)
    }

    /// Another course named, in a window for this one: refused in code with
    /// the sentence a model-named course gets, nothing read, no model asked —
    /// and the folder decides which of the two sentences.
    func testAnotherCourseIsRefusedInCodeWithTheExistingSentence() async throws {
        let made = try AssistFixture.makeRunner(alsoCourse: "SPH3U")
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        let engine: StubEngine = try StubEngine()
        defer {
            engine.stop()
            try? FileManager.default.removeItem(at: made.root)
        }
        engine.serve(#"{"choices":[{"message":{"role":"assistant","content":"Here it is."}}],"usage":{"completion_tokens":4}}"#)
        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)

        await agent.say("What does \"Unit 2, Day 3\" in SPH3U section 1 link to?")
        var last: AssistAgent.Entry = try XCTUnwrap(agent.entries.last)
        XCTAssertEqual(last.speaker, .assistant)
        XCTAssertEqual(last.text, AssistWording.askedAboutAnotherCourse(course: "ICS3U", otherCourse: "SPH3U"))

        await agent.say("What does Unit 2, Day 3 in MPM2D link to?")
        last = try XCTUnwrap(agent.entries.last)
        XCTAssertEqual(
            last.text, AssistWording.askedAboutACourseThatIsNotHere(course: "ICS3U", otherCourse: "MPM2D")
        )

        XCTAssertEqual(engine.requestCount, 0, "a refused question reached the model")
        for entry in agent.entries {
            if case .toolResult = entry.speaker {
                XCTFail("a tool ran for a question about another course: \(entry.text)")
            }
        }
        XCTAssertEqual(agent.activity, .idle)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains(AssistAgent.linksQuestionNamedAnotherCourseLine(otherCourse: "SPH3U", windowCourse: "ICS3U")),
            trail
        )
    }

    /// "What does The Water Cycle link to?" is answered in code when the
    /// section has that page, and "What does the quiz link to?" — with no
    /// page called that — goes to the model (#167 fix review F2).
    func testAPhraseBeginningTheIsAnsweredInCodeOnlyWhenAPageIsCalledThat() async throws {
        let made = try LinksQuestionCardTests.sectionFromTheContract(askedPageBody: "[[Ohm's Law]]")
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        let engine: StubEngine = try StubEngine()
        defer {
            engine.stop()
            try? FileManager.default.removeItem(at: made.root)
        }
        engine.serve(#"{"choices":[{"message":{"role":"assistant","content":"Here it is."}}],"usage":{"completion_tokens":4}}"#)
        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)

        await agent.say("What does The Water Cycle link to?")
        XCTAssertEqual(engine.requestCount, 0, "a page that exists was sent to the model")
        let last: AssistAgent.Entry = try XCTUnwrap(agent.entries.last)
        XCTAssertEqual(last.speaker, .toolResult(name: "read_page"))
        XCTAssertEqual(last.text, AssistWording.pageLinksToNothing(page: "The Water Cycle"))

        await agent.say("What does the quiz link to?")
        XCTAssertEqual(engine.requestCount, 1, "a description with no page by that name must go to the model")
    }

    // MARK: - Helpers

    /// A course laid out as `answering.section` says, with the page asked
    /// about ("Unit 1, Day 1") carrying `askedPageBody`.
    private static func sectionFromTheContract(askedPageBody: String) throws -> AssistFixture.Made {
        let made = try AssistFixture.makeRunner()
        let answering: [String: Any] = try answering()
        let sectionFolder: URL = made.course.sectionDirectoryURL(forSection: 1)
        for page in try XCTUnwrap(answering["section"] as? [[String: Any]]) {
            let path: String = try XCTUnwrap(page["path"] as? String)
            let title: String = try XCTUnwrap(page["title"] as? String)
            let publish: Bool = try XCTUnwrap(page["publish"] as? Bool)
            var body: String = "A page."
            if title == "Unit 1, Day 1" {
                body = askedPageBody
            }
            let url: URL = sectionFolder.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let text: String = "---\ntitle: \(title)\npublish: \(publish)\n"
                + "created: 2026-09-08T07:00:00.000-0400\n---\n\n\(body)\n"
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        for file in try XCTUnwrap(answering["sectionFiles"] as? [String]) {
            let url: URL = sectionFolder.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        }
        return made
    }

    private static func readLinks(of page: String, asTyped: String? = nil) -> AssistToolCall {
        var arguments: [String: Any] = [
            "course": "ICS3U", "section": 1, "page": page, "answer": AssistCardCommand.linksAnswer,
        ]
        if let asTyped {
            arguments[AssistCardCommand.linksAsTypedArgument] = asTyped
        }
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString, type: "function",
            function: AssistToolCall.Function(name: "read_page", arguments: String(decoding: encoded, as: UTF8.self))
        )
    }

    /// A mark named in the contract, as the sentence it stands for.
    private static func markSentence(named name: String) throws -> String {
        switch name {
        case "linkedPageIsADraft":
            return AssistWording.linkedPageIsADraft
        case "linkedPageIsMissing":
            return AssistWording.linkedPageIsMissing
        default:
            throw XCTSkip("The contract names a mark this test does not know: \(name)")
        }
    }

    // MARK: - Reading the contract

    private static func window() throws -> (course: String, section: Int) {
        let family: [String: Any] = try family()
        let window: [String: Any] = try XCTUnwrap(family["window"] as? [String: Any])
        return (try XCTUnwrap(window["course"] as? String), try XCTUnwrap(window["section"] as? Int))
    }

    private static func answering() throws -> [String: Any] {
        return try XCTUnwrap(family()["answering"] as? [String: Any])
    }

    private static func rows(named key: String) throws -> [[String: Any]] {
        let rows: [[String: Any]] = try XCTUnwrap(family()[key] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty, "\(key) has been emptied out")
        return rows
    }

    private static func family() throws -> [String: Any] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(
            contentsOf: repository.appendingPathComponent("contracts")
                .appendingPathComponent(AssistContract.casesFileName)
        )
        let cases: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let family: [String: Any] = try XCTUnwrap(
            cases["linksQuestion"] as? [String: Any], "contracts/assist-cases.json has no linksQuestion"
        )
        XCTAssertNotNil(family["note"] as? String)
        return family
    }
}
