import XCTest
@testable import QuartzTeachers

/// A new unit, a unit or day other than the next one, and several pages —
/// asked of an add_next_class that carries only a course and a section
/// (#440). Answered in code where the sentence is a fixed frame; stopped and
/// pointed (settler S3) where the model answered it with the plain call.
///
/// **Why this file exists.** Measured 2026-10-07 on the smaller assistant
/// (M4 Pro, b10435): ten such sentences reached add_next_class 50 of 50 with
/// only a course and a section, each adding ONE page in the current unit and
/// reporting success. #411 measured giving the tool `unit` and `days`
/// instead, and both models then started a new unit on a plain "add the next
/// class".
///
/// Every row is read from `contracts/assist-cases.json` → `nextClassUnits`,
/// so Windows reads the same sentences. Nothing typed here could disagree
/// with it, apart from the course fixtures the pointer is run against.
@MainActor
final class NextClassUnitsTests: XCTestCase {

    // MARK: - Stored properties

    private var roots: [URL] = []
    private var previousStore: ProblemReportStore?

    // MARK: - Functions

    override func tearDown() async throws {
        if let previousStore {
            ActivityTrail.store = previousStore
        }
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
        try await super.tearDown()
    }

    // MARK: - The frames, row by row

    /// Every accepted row is answered in code with the arguments it names.
    func testEveryAcceptedRowIsAnsweredInCode() throws {
        let rows: [[String: Any]] = try NextClassUnitsTests.rows(named: "accepted")
        XCTAssertGreaterThanOrEqual(rows.count, 10, "accepted rows have gone missing")
        for row in rows {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is accepted for no stated reason")
            let command: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(input),
                "\"\(input)\" is in the contract as answered in code and matches nothing"
            )
            XCTAssertEqual(command.toolName, row["expectTool"] as? String, input)
            XCTAssertEqual(command.arguments, row["expectArguments"] as? [String: String], input)
        }
    }

    /// Every not-this row falls through to the model.
    func testEveryNotThisRowFallsThroughToTheModel() throws {
        let rows: [[String: Any]] = try NextClassUnitsTests.rows(named: "notThis")
        XCTAssertGreaterThanOrEqual(rows.count, 10, "notThis rows have gone missing")
        for row in rows {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is refused for no stated reason")
            XCTAssertNil(AssistCardCommand.matching(input), "\"\(input)\" matched a card")
        }
    }

    // MARK: - Settler S3, row by row

    /// Every pointed row reaches the model (no card matches — review F6, so
    /// the measurement can never quietly score a card) and is pointed for
    /// the reason the row names.
    func testEveryPointedRowReachesTheModelAndIsPointed() throws {
        let rows: [[String: Any]] = try NextClassUnitsTests.rows(named: "pointed")
        XCTAssertGreaterThanOrEqual(rows.count, 15, "pointed rows have gone missing")
        var kindsSeen: Set<String> = []
        for row in rows {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is pointed for no stated reason")
            XCTAssertEqual(row["reachesModel"] as? Bool, true, input)
            let given: [String: Any] = try XCTUnwrap(row["given"] as? [String: Any], input)
            XCTAssertNil(
                AssistCardCommand.matching(input, numberedPageWord: NextClassUnitsTests.numberedWord(given)),
                "\"\(input)\" is marked as reaching the model and matches a card"
            )
            let expected: String = try XCTUnwrap(row["kind"] as? String, input)
            kindsSeen.insert(expected)
            let kind: AssistNextClassUnits.Kind? = AssistNextClassUnits.kind(
                of: input, reading: try NextClassUnitsTests.reading(from: given)
            )
            XCTAssertEqual(kind?.rawValue, expected, "\"\(input)\"")
        }
        XCTAssertEqual(kindsSeen, ["a", "b", "c"])
    }

    /// Every runs row is left alone by S3 — the deterministic sweep of
    /// ruling 5: every add_next_class sentence on record that reaches the
    /// model is here, and none of them is stopped. `reachesModel` is pinned
    /// both ways.
    func testEveryRunsRowRuns() throws {
        let rows: [[String: Any]] = try NextClassUnitsTests.rows(named: "runs")
        XCTAssertGreaterThanOrEqual(rows.count, 15, "runs rows have gone missing")
        var controls: Int = 0
        for row in rows {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) runs for no stated reason")
            let given: [String: Any] = try XCTUnwrap(row["given"] as? [String: Any], input)
            let reachesModel: Bool = try XCTUnwrap(row["reachesModel"] as? Bool, input)
            let card: AssistCardCommand? = AssistCardCommand.matching(
                input, numberedPageWord: NextClassUnitsTests.numberedWord(given)
            )
            XCTAssertEqual(card == nil, reachesModel, "\"\(input)\": reachesModel says \(reachesModel)")
            XCTAssertNil(
                AssistNextClassUnits.kind(of: input, reading: try NextClassUnitsTests.reading(from: given)),
                "\"\(input)\" is a runs row and S3 stops it"
            )
            if row["measuredAsControl"] as? Bool == true {
                XCTAssertTrue(reachesModel, "\(input): a measured control must reach the model")
                controls += 1
            }
        }
        XCTAssertGreaterThanOrEqual(controls, 5)
    }

    /// Nothing at all without a reading: no dates, no S3 (ruling 7).
    func testWithoutAReadingNothingIsStopped() {
        XCTAssertNil(AssistNextClassUnits.kind(of: "Start a new unit for the next class", reading: nil))
        XCTAssertNil(AssistNextClassUnits.kind(of: "Add the next two classes", reading: nil))
    }

    // MARK: - The pointer (ruling 1)

    /// The generated wording is the function's own output, and every sentence
    /// each pointer quotes, typed back in that kind of course, is a card that
    /// does what it says there — a Unit course, a Module course and a
    /// numbered one. This is the dead-end test of review F1 and F2.
    func testEveryQuotedSentenceIsACardThatWorksInThatCourse() async throws {
        let rows: [[String: Any]] = try NextClassUnitsTests.rows(named: "pointerSentences")
        XCTAssertEqual(rows.count, 3)
        let wording: [String: String] = try NextClassUnitsTests.generatedWording()
        for row in rows {
            let key: String = try XCTUnwrap(row["wording"] as? String)
            let given: [String: Any] = try XCTUnwrap(row["given"] as? [String: Any], key)
            let reading: AssistNextClassReading = try XCTUnwrap(try NextClassUnitsTests.reading(from: given))
            let sentence: String = AssistWording.nextClassNeedsItsOwnPhrasing(
                unitWord: reading.unitWord, isNumbered: reading.isNumbered, noun: reading.noun
            )
            XCTAssertEqual(wording[key], sentence, "\(key) is stale in assist-wording.json")
            let quoted: [String] = NextClassUnitsTests.quotedSentences(in: sentence)
            XCTAssertFalse(quoted.isEmpty, key)
            for typedBack in quoted {
                let card: AssistCardCommand = try XCTUnwrap(
                    AssistCardCommand.matching(typedBack, numberedPageWord: NextClassUnitsTests.numberedWord(given)),
                    "\(key) tells the teacher to say “\(typedBack)”, and that is not answered in code"
                )
                XCTAssertEqual(card.toolName, "add_next_class", typedBack)
                XCTAssertNil(
                    AssistNextClassUnits.kind(of: typedBack, reading: nil),
                    "a card never meets S3, but nothing should depend on that"
                )
                try await assertTheCardAddsAPage(card, typedBack: typedBack, reading: reading)
            }
        }
    }

    // MARK: - The agent

    /// The model answers "Add the next two classes" with a plain
    /// add_next_class: nothing added, no card, the turn wound back, the
    /// pointer said, and the trail's line written.
    func testAPointedSentenceAddsNothingAndLeavesALine() async throws {
        let made = try prepare()
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(NextClassUnitsTests.addNextClassReply(#"{"course":"ICS3U","section":1}"#))
        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        let messagesBefore: Int = agent.messages.count
        let pagesBefore: [String] = try NextClassUnitsTests.classPages(in: made.course)

        await agent.say("Add the next two classes")

        XCTAssertEqual(engine.requestCount, 1)
        XCTAssertNil(agent.pendingApproval, "a plan card went up for a sentence S3 stops")
        XCTAssertEqual(agent.messages.count, messagesBefore, "the turn was not wound back")
        XCTAssertEqual(
            agent.entries.last?.text,
            AssistWording.nextClassNeedsItsOwnPhrasing(unitWord: "Unit", isNumbered: false, noun: .class)
        )
        XCTAssertEqual(try NextClassUnitsTests.classPages(in: made.course), pagesBefore)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(AssistAgent.nextClassPointedLine(.several)), trail)
    }

    /// The runner's reading: nil without dates, the plain next page with them.
    func testTheRunnersReading() throws {
        let made = try prepare(withDates: false)
        XCTAssertNil(made.runner.nextClassReading(forCourse: "ICS3U", section: 1))
        try NextClassUnitsTests.rememberDates(in: made.course)
        let reading: AssistNextClassReading = try XCTUnwrap(
            made.runner.nextClassReading(forCourse: "ICS3U", section: 1)
        )
        XCTAssertEqual(reading.plainNextUnit, 1)
        XCTAssertEqual(reading.plainNextDay, 2)
        XCTAssertFalse(reading.isNumbered)
        XCTAssertNil(made.runner.nextClassReading(forCourse: "SPH3U", section: 1))
    }

    // MARK: - Helpers

    /// Runs the card on a fixture course of the reading's kind and checks a
    /// page was added — never refused.
    private func assertTheCardAddsAPage(
        _ card: AssistCardCommand, typedBack: String, reading: AssistNextClassReading
    ) async throws {
        let made: AssistFixture.Made
        if reading.isNumbered {
            made = try AssistFixture.makeClub(noun: reading.noun)
        } else {
            made = try AssistFixture.makeRunner()
            made.course.configuration.unitWord = reading.unitWord
            try made.course.configuration.write(
                to: made.course.directoryURL.appendingPathComponent("course_config.json")
            )
            try AssistFixture.write(
                page: reading.unitWord + " 1, Day 1", publish: "false", body: "one", in: made.course
            )
            try NextClassUnitsTests.rememberDates(in: made.course)
        }
        roots.append(made.root)
        let before: [String] = try NextClassUnitsTests.classPages(in: made.course)
        _ = await AssistFixture.run(card.toolName, with: card.arguments, on: made.runner)
        let after: [String] = try NextClassUnitsTests.classPages(in: made.course)
        XCTAssertGreaterThan(after.count, before.count, "“\(typedBack)” added nothing in this course")
    }

    private func prepare(withDates: Bool = true) throws -> AssistFixture.Made {
        let made = try AssistFixture.makeRunner()
        roots.append(made.root)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(
            folderURL: made.root.appendingPathComponent("trail", isDirectory: true)
        )
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "one", in: made.course)
        if withDates {
            try NextClassUnitsTests.rememberDates(in: made.course)
        }
        return made
    }

    private static func rememberDates(in course: Course) throws {
        try SectionTimetableStore.applyRememberTimetable(
            try SectionTimetableStore.planRememberTimetable(
                dates: ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16", "2026-09-21", "2026-09-23"],
                source: "typed in by hand", forSection: 1, in: course
            )
        )
    }

    private static func classPages(in course: Course) throws -> [String] {
        let folder: URL = ClassPages.folderURL(forSection: 1, in: course)
        var names: [String] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix(".md") {
            names.append(name)
        }
        return names.sorted()
    }

    /// The text between each pair of curly quotes.
    private static func quotedSentences(in sentence: String) -> [String] {
        var found: [String] = []
        var current: String? = nil
        for character in sentence {
            if character == "\u{201C}" {
                current = ""
            } else if character == "\u{201D}" {
                if let current {
                    found.append(current)
                }
                current = nil
            } else if current != nil {
                current?.append(character)
            }
        }
        return found
    }

    /// The reading a row's `given` describes; nil when `plainNext` is null.
    private static func reading(from given: [String: Any]) throws -> AssistNextClassReading? {
        guard let plainNext = given["plainNext"] as? String else {
            return nil
        }
        let unitWord: String = try XCTUnwrap(given["unitWord"] as? String)
        let isNumbered: Bool = try XCTUnwrap(given["isNumbered"] as? Bool)
        let noun: ClassNoun = ClassNoun.reading(given["noun"] as? String)
        var numbers: [Int] = []
        for word in AssistNextClassUnits.words(of: plainNext) {
            if let number = Int(word) {
                numbers.append(number)
            }
        }
        let unit: Int = try XCTUnwrap(numbers.first, plainNext)
        let day: Int = numbers.count > 1 ? numbers[1] : 0
        return AssistNextClassReading(
            unitWord: unitWord, isNumbered: isNumbered, noun: noun, plainNextUnit: unit, plainNextDay: day
        )
    }

    private static func numberedWord(_ given: [String: Any]) -> String? {
        guard given["isNumbered"] as? Bool == true else {
            return nil
        }
        return given["unitWord"] as? String
    }

    private static func addNextClassReply(_ arguments: String) -> String {
        var escaped: String = ""
        for character in arguments {
            if character == "\"" {
                escaped.append("\\\"")
            } else {
                escaped.append(character)
            }
        }
        return #"{"choices":[{"finish_reason":"tool_calls","message":"#
            + #"{"role":"assistant","content":"","tool_calls":["#
            + #"{"id":"call-1","type":"function","function":"#
            + #"{"name":"add_next_class","arguments":""# + escaped + #""}}]}}],"#
            + #""usage":{"completion_tokens":30}}"#
    }

    private static func contractFile(named name: String) throws -> [String: Any] {
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

    private static func generatedWording() throws -> [String: String] {
        let file: [String: Any] = try contractFile(named: AssistContract.wordingFileName)
        return try XCTUnwrap(file["wording"] as? [String: String])
    }

    private static func rows(named key: String) throws -> [[String: Any]] {
        let contract: [String: Any] = try contractFile(named: AssistContract.casesFileName)
        let family: [String: Any] = try XCTUnwrap(
            contract["nextClassUnits"] as? [String: Any],
            "contracts/assist-cases.json has no nextClassUnits"
        )
        XCTAssertNotNil(family["note"] as? String)
        return try XCTUnwrap(family[key] as? [[String: Any]], "nextClassUnits has no \(key)")
    }
}
