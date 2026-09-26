import XCTest
@testable import QuartzTeachers

/// A publish or a hide whose page list names no page it can find (#197).
///
/// **Why this file exists.** After listing a section, the smaller assistant
/// answered "Publish all of those." with `"pages": "all"` three times in three
/// on one real course, and this app answered that "Nothing needed changing."
/// — success, about a request that did nothing. The same was true of ANY list
/// whose every name matched no page, and plan mode offered a Go/Cancel card
/// over a plan that changed nothing. Confirmed by a throwaway test against
/// `dev` on 2026-09-26 before any of this was written.
///
/// Every case is read from `contracts/assist-cases.json` → `pagesNamingNoPage`,
/// which the Windows suite runs too. Nothing is typed here that could
/// disagree with it: the sentences are the contract's wording rendered with
/// the case's own fills.
@MainActor
final class AssistPagesNamingNoPageTests: XCTestCase {

    // MARK: - Stored properties

    /// Where the trail went before a test pointed it at its own folder.
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

    // MARK: - The cases

    /// Every case: what the teacher reads, whether it is a plan, whether the
    /// turn ends, and exactly which pages were written.
    func testEveryPagesNamingNoPageCaseBehavesAsTheContractSays() async throws {
        let family: [String: Any] = try AssistPagesNamingNoPageTests.family()
        let cases: [[String: Any]] = try XCTUnwrap(family["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 12, "a case was added or lost; the README census counts them")
        let wording: [String: String] = try AssistPagesNamingNoPageTests.wordingTable()

        for row in cases {
            let name: String = try XCTUnwrap(row["name"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(name) is in the contract for no stated reason")
            let expect: [String: Any] = try XCTUnwrap(row["expect"] as? [String: Any], name)

            let made = try AssistPagesNamingNoPageTests.section(for: row)
            defer { try? FileManager.default.removeItem(at: made.root) }
            ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))

            let before: [String: Data] = try AssistPagesNamingNoPageTests.pageBytes(of: row, in: made.course)
            var arguments: [String: Any] = try XCTUnwrap(row["arguments"] as? [String: Any], name)
            arguments["course"] = "ICS3U"
            arguments["section"] = 1
            let tool: String = try XCTUnwrap(row["tool"] as? String, name)
            let outcome: AssistToolOutcome = await AssistPagesNamingNoPageTests.run(made.runner, tool, arguments)

            // The kind of answer.
            let kind: String = try XCTUnwrap(expect["outcome"] as? String, name)
            XCTAssertEqual(outcome.isPlan, expect["isPlan"] as? Bool, "\(name): \(outcome.summary)")
            if kind == "couldNotRead" {
                XCTAssertTrue(outcome.shouldContinue, "\(name) ended the turn: \(outcome.summary)")
            } else {
                XCTAssertFalse(outcome.shouldContinue, "\(name) handed back: \(outcome.summary)")
            }

            // What the teacher reads.
            if let key = expect["wording"] as? String {
                let template: String = try XCTUnwrap(wording[key], "\(name) names wording.\(key), which is not there")
                var sentence: String = template
                    .replacingOccurrences(of: AssistContract.coursePlaceholder, with: "ICS3U")
                    .replacingOccurrences(of: AssistContract.sectionPlaceholder, with: "1")
                let fills: [String: String] = (expect["fills"] as? [String: String]) ?? [:]
                for (placeholder, value) in fills {
                    sentence = sentence.replacingOccurrences(of: "{\(placeholder)}", with: value)
                }
                XCTAssertFalse(sentence.contains("{"), "\(name) left a placeholder unfilled: \(sentence)")
                XCTAssertEqual(outcome.summary, sentence, name)
            } else if let refusal = expect["refusal"] as? String {
                XCTAssertEqual(refusal, "openEndedPublish", "\(name) names a refusal this test does not know")
                let from: CalendarDay = try XCTUnwrap(CalendarDay(text: arguments["onOrAfter"] as? String ?? ""))
                XCTAssertEqual(outcome.summary, AssistToolRefusal.openEndedPublish(from).message, name)
            } else {
                XCTAssertEqual(kind, "wrote", name)
                XCTAssertNotEqual(outcome.summary, "Nothing needed changing.", name)
            }

            // Exactly the pages the contract says were written.
            let after: [String: Data] = try AssistPagesNamingNoPageTests.pageBytes(of: row, in: made.course)
            var written: [String] = []
            for (title, bytes) in before where after[title] != bytes {
                written.append(title)
            }
            let expected: [String] = try XCTUnwrap(expect["writes"] as? [String], name)
            XCTAssertEqual(Set(written), Set(expected), "\(name): \(outcome.summary)")

            // One trail line for each refusal this piece added, none otherwise.
            let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
            var lines: Int = 0
            for line in trail.components(separatedBy: "\n") where line.contains("named no page while") {
                lines += 1
            }
            let isNewRefusal: Bool = kind != "wrote" && expect["wording"] is String
            XCTAssertEqual(lines, isNewRefusal ? 1 : 0, "\(name): \(trail)")
        }
    }

    /// The Swift list of every-page words IS the contract's, both directions.
    func testTheEveryPageWordsAreTheContractsOwn() throws {
        let words: [String] = try XCTUnwrap(
            try AssistPagesNamingNoPageTests.family()["everyPageWords"] as? [String]
        )
        XCTAssertEqual(Set(words), AssistToolRunner.everyPageWords)
        XCTAssertEqual(words.count, Set(words).count, "a word is listed twice")
        for word in words {
            XCTAssertEqual(word, word.lowercased(), "\(word) is compared case-folded, so it is written that way")
        }
    }

    // MARK: - The trail

    /// The line says which act and which shape — and never a page's name.
    func testTheNamedNoPageLineIsOnTheTrailWithoutTheNames() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        try AssistFixture.write(page: "Unit 3, Day 1", publish: "false", body: "One.", in: made.course)

        _ = await AssistPagesNamingNoPageTests.run(
            made.runner, "publish_pages",
            ["course": "ICS3U", "section": 1, "pages": "Unit 9, Day 9; Unit 9, Day 10"]
        )
        _ = await AssistPagesNamingNoPageTests.run(
            made.runner, "plan_unpublish_pages", ["course": "ICS3U", "section": 1, "pages": "Everything"]
        )

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("ICS3U/1 · " + ActivityTrail.namedNoPageLine(
            act: "publishing pages", everyPageWord: nil, unknownCount: 2
        )), trail)
        XCTAssertTrue(trail.contains("ICS3U/1 · " + ActivityTrail.namedNoPageLine(
            act: "hiding pages", everyPageWord: "everything", unknownCount: 0
        )), trail)
        for title in ["Unit 9, Day 9", "Unit 9, Day 10", "Unit 3, Day 1", "Unit 9"] {
            XCTAssertFalse(trail.contains(title), "the trail carries a page title: \(trail)")
        }
    }

    // MARK: - The sentences

    /// The new sentences are the teacher's: no tool, no argument, no model.
    func testTheNewSentencesNameNothingOfTheMachinery() {
        let sentences: [String] = [
            AssistWording.everyPageIsNotAPageToPublish(example: "Publish Unit 3"),
            AssistWording.everyPageIsNotAPageToHide(example: "Hide Unit 3"),
            AssistWording.noPagesCalled(pages: "“a” or “b”", course: "ICS3U", section: "1"),
        ]
        for sentence in sentences {
            for word in ["list_pages", "publish_pages", "unpublish_pages", "argument", "model", "tool",
                         "toolchain", "script"] {
                XCTAssertFalse(
                    sentence.lowercased().contains(word),
                    "\"\(sentence)\" names \(word)"
                )
            }
        }
    }

    /// "or", never "and": one page does not have two names.
    func testTwoOrMoreNamesAreJoinedWithOr() {
        XCTAssertEqual(AssistPublishPlan.listingEither(["a"]), "“a”")
        XCTAssertEqual(AssistPublishPlan.listingEither(["a", "b"]), "“a” or “b”")
        XCTAssertEqual(AssistPublishPlan.listingEither(["a", "b", "c"]), "“a”, “b” or “c”")
        XCTAssertEqual(AssistPublishPlan.listingEither(["a", "b", "c", "d"]), "“a”, “b”, “c” or 1 other")
        XCTAssertEqual(AssistPublishPlan.listingEither(["a", "b", "c", "d", "e"]), "“a”, “b”, “c” or 2 others")
    }

    /// A Module course's example says "Module", because following it has to
    /// find the unit (#268's lesson).
    func testTheExampleIsInTheCoursesOwnWord() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        made.course.configuration.unitWord = "Module"
        try made.course.configuration.write(
            to: made.course.directoryURL.appendingPathComponent("course_config.json")
        )
        try AssistFixture.write(page: "Module 2, Day 1", publish: "false", body: "One.", in: made.course)
        try AssistFixture.write(page: "Module 5, Day 1", publish: "false", body: "Two.", in: made.course)

        let outcome: AssistToolOutcome = await AssistPagesNamingNoPageTests.run(
            made.runner, "publish_pages", ["course": "ICS3U", "section": 1, "pages": "all"]
        )
        XCTAssertEqual(outcome.summary, AssistWording.everyPageIsNotAPageToPublish(example: "Publish Module 2"))
    }

    // MARK: - In the window

    /// Plan mode, the setting a teacher has: the model's `"pages": "all"`
    /// is answered with the sentence, no Go/Cancel card appears, and the turn
    /// ENDS — the model is asked once and gets no second lap to run away in
    /// (the plan's risk R4, which a scripted lap on the smaller assistant
    /// showed would be a text reply cut off at the cap, 3 times in 3).
    func testInPlanModeTheTeacherReadsTheSentenceAndNoCardAppears() async throws {
        let made = try AssistFixture.makeRunner()
        let engine: StubEngine = try StubEngine()
        defer {
            engine.stop()
            try? FileManager.default.removeItem(at: made.root)
        }
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        try AssistFixture.write(page: "Unit 3, Day 1", publish: "false", body: "One.", in: made.course)
        let arguments: String = #"{"course": "ICS3U", "section": 1, "pages": "all"}"#
        let escaped: String = arguments.replacingOccurrences(of: "\"", with: "\\\"")
        engine.serve(#"{"choices":[{"finish_reason":"tool_calls","message":"#
            + #"{"role":"assistant","content":"","tool_calls":["#
            + #"{"id":"call-1","type":"function","function":"#
            + #"{"name":"publish_pages","arguments":"\#(escaped)"}}]}}],"#
            + #""usage":{"completion_tokens":40}}"#)

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        await agent.say("Publish all of those.")

        XCTAssertEqual(engine.requestCount, 1, "the refusal handed the model another lap")
        XCTAssertNil(agent.pendingApproval, "a card offered to go ahead with nothing")
        XCTAssertEqual(agent.activity, .idle)
        let last: AssistAgent.Entry = try XCTUnwrap(agent.entries.last)
        XCTAssertEqual(last.text, AssistWording.everyPageIsNotAPageToPublish(example: "Publish Unit 3"))
        XCTAssertFalse(AssistPagesNamingNoPageTests.isPublished("Unit 3, Day 1", in: made.course))
    }

    // MARK: - "Publish all the classes in Unit 2." (answered in code)

    /// Every spelling the contract accepts is a whole-unit publish, answered
    /// in code, carrying no course or section of its own.
    func testEverySentenceForAWholeUnitTheContractAcceptsIsAnsweredInCode() throws {
        for row in try AssistPagesNamingNoPageTests.unitRows(named: "accepted") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is accepted for no stated reason")
            let command: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(input), "\"\(input)\" is accepted by the contract and matches nothing"
            )
            XCTAssertEqual(command.toolName, row["expectTool"] as? String, input)
            XCTAssertEqual(command.arguments["pages"], row["expectPages"] as? String, input)
            XCTAssertNil(command.arguments["course"], input)
            XCTAssertNil(command.arguments["section"], input)
        }
    }

    /// And every one it refuses goes to the model — the half that stops the
    /// publish direction widening past what was measured.
    func testEverySentenceForAWholeUnitTheContractRefusesGoesToTheModel() throws {
        for row in try AssistPagesNamingNoPageTests.unitRows(named: "refused") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is refused for no stated reason")
            XCTAssertNil(AssistCardCommand.matching(input), "\"\(input)\" was answered in code")
        }
    }

    /// The measured sentence, through the real agent: the unit is published
    /// and the model is never asked — so it cannot publish today's class.
    func testTheMeasuredSentencePublishesTheUnitWithoutTheModel() async throws {
        let made = try AssistFixture.makeRunner()
        let engine: StubEngine = try StubEngine()
        defer {
            engine.stop()
            try? FileManager.default.removeItem(at: made.root)
        }
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        engine.serve(#"{"choices":[{"message":{"role":"assistant","content":"Done."}}],"usage":{"completion_tokens":2}}"#)
        // Today's class is in Unit 1; the unit asked for is Unit 2.
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-08", body: "Today.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 1", publish: "false", date: "2026-09-20", body: "A.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 2", publish: "false", date: "2026-09-21", body: "B.", in: made.course)

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say("Publish all the classes in Unit 2.")

        XCTAssertEqual(engine.requestCount, 0, "the model was asked about a sentence answered in code")
        XCTAssertTrue(AssistPagesNamingNoPageTests.isPublished("Unit 2, Day 1", in: made.course))
        XCTAssertTrue(AssistPagesNamingNoPageTests.isPublished("Unit 2, Day 2", in: made.course))
        XCTAssertFalse(
            AssistPagesNamingNoPageTests.isPublished("Unit 1, Day 1", in: made.course),
            "today's class was published for a request about a unit"
        )
    }

    // MARK: - Helpers

    private static func run(
        _ runner: AssistToolRunner, _ tool: String, _ arguments: [String: Any]
    ) async -> AssistToolOutcome {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return await runner.run(
            call: AssistToolCall(
                id: UUID().uuidString,
                type: "function",
                function: AssistToolCall.Function(name: tool, arguments: String(decoding: encoded, as: UTF8.self))
            )
        )
    }

    private static func isPublished(_ title: String, in course: Course) -> Bool {
        let text: String = (try? String(
            contentsOf: AssistFixture.pageURL(of: title, in: course), encoding: .utf8
        )) ?? ""
        return AssistPageVisibility.publishes(in: text, forSection: 1)
    }

    /// The section a case describes, on disk.
    private static func section(for row: [String: Any]) throws -> AssistFixture.Made {
        let made = try AssistFixture.makeRunner()
        if (row["course"] as? String) == "numbered" {
            made.course.configuration.unitWord = try XCTUnwrap(row["pageWord"] as? String)
            made.course.configuration.classPageScheme = .numbered
            try made.course.configuration.write(
                to: made.course.directoryURL.appendingPathComponent("course_config.json")
            )
        }
        let pages: [[String: Any]] = try XCTUnwrap(row["pages"] as? [[String: Any]])
        for page in pages {
            let title: String = try XCTUnwrap(page["title"] as? String)
            let published: Bool = try XCTUnwrap(page["published"] as? Bool)
            try AssistFixture.write(
                page: title, publish: published ? "true" : "false",
                date: try XCTUnwrap(page["date"] as? String),
                body: "The words of \(title).", in: made.course
            )
        }
        return made
    }

    private static func pageBytes(of row: [String: Any], in course: Course) throws -> [String: Data] {
        var bytes: [String: Data] = [:]
        let pages: [[String: Any]] = try XCTUnwrap(row["pages"] as? [[String: Any]])
        for page in pages {
            let title: String = try XCTUnwrap(page["title"] as? String)
            bytes[title] = try Data(contentsOf: AssistFixture.pageURL(of: title, in: course))
        }
        return bytes
    }

    private static func family() throws -> [String: Any] {
        let family: [String: Any] = try XCTUnwrap(
            contract(named: AssistContract.casesFileName)["pagesNamingNoPage"] as? [String: Any],
            "contracts/assist-cases.json has no pagesNamingNoPage"
        )
        XCTAssertNotNil(family["note"] as? String)
        return family
    }

    private static func unitRows(named key: String) throws -> [[String: Any]] {
        let unit: [String: Any] = try XCTUnwrap(family()["everythingInAUnit"] as? [String: Any])
        XCTAssertNotNil(unit["note"] as? String)
        let rows: [[String: Any]] = try XCTUnwrap(unit[key] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty, "\(key) has been emptied out")
        return rows
    }

    private static func wordingTable() throws -> [String: String] {
        return try XCTUnwrap(
            contract(named: AssistContract.wordingFileName)["wording"] as? [String: String]
        )
    }

    private static func contract(named name: String) throws -> [String: Any] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(
            contentsOf: repository.appendingPathComponent("contracts").appendingPathComponent(name)
        )
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
