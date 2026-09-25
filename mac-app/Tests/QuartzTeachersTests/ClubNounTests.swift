import XCTest
@testable import QuartzTeachers

/// "meeting" in a club's assistant (#267), and the rule that makes it safe to
/// ship without a routing measurement: the course's noun reaches what the
/// TEACHER reads and never what the MODEL reads.
///
/// A tool's outcome has two audiences (`AssistToolOutcome`). The model is
/// given `detail`; the teacher is shown `summary`, `forTheCard` and the lines
/// the window writes itself. Everything here holds the first of those
/// byte-for-byte whatever the course calls its pages, and checks the second
/// says the course's own word.
@MainActor
final class ClubNounTests: XCTestCase {

    // MARK: - Stored properties

    /// The plan tools a club teacher reaches, with arguments that make each
    /// plan say every sentence it has in the course's noun.
    private let plans: [(String, [String: Any])] = [
        ("plan_make_room_for_classes", ["course": "ICS3U", "section": 1, "unit": 2]),
        ("plan_add_next_class", ["course": "ICS3U", "section": 1]),
        ("plan_add_next_class", ["course": "ICS3U", "section": 1, "duplicate": "Week 2"]),
        ("plan_publish_class_on", ["course": "ICS3U", "section": 1, "date": "2026-09-09"]),
        ("plan_publish_pages", ["course": "ICS3U", "section": 1, "pages": "Week 2"]),
        ("plan_re_date_classes", ["course": "ICS3U", "section": 1]),
    ]

    // MARK: - Functions

    /// A numbered course with four hidden weeks, Week 2 linking to Week 3,
    /// and a timetable the pages do not sit on — so re-dating moves them.
    private func makeClub(noun: ClassNoun) throws -> (root: URL, course: Course, runner: AssistToolRunner) {
        let made = try AssistFixture.makeRunner()
        try setNoun(noun, in: made.course)
        var day: Int = 8
        for title in ["Week 1", "Week 2", "Week 3", "Week 4"] {
            var body: String = "The words of \(title)."
            if title == "Week 2" {
                body += " Carry on in [[Week 3]]."
            }
            try AssistFixture.write(
                page: title, publish: "false",
                date: String(format: "2026-09-%02d", day),
                body: body, in: made.course
            )
            day += 1
        }
        try SectionTimetableStore.applyRememberTimetable(
            try SectionTimetableStore.planRememberTimetable(
                dates: ["2026-09-08", "2026-09-09", "2026-09-14", "2026-09-16", "2026-09-21",
                        "2026-09-23", "2026-09-28", "2026-09-30", "2026-10-05"],
                source: "timetable.xlsx, block H", forSection: 1, in: made.course
            )
        )
        return (made.root, made.course, made.runner)
    }

    /// Writes the course's naming to disk, which is where the runner reads it.
    private func setNoun(_ noun: ClassNoun, in course: Course) throws {
        course.configuration.unitWord = "Week"
        course.configuration.classPageScheme = .numbered
        course.configuration.classNoun = noun
        try course.configuration.write(
            to: course.directoryURL.appendingPathComponent("course_config.json")
        )
    }

    private func run(
        _ runner: AssistToolRunner, _ tool: String, _ arguments: [String: Any]
    ) async -> AssistToolOutcome {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return await runner.run(
            call: AssistToolCall(
                id: UUID().uuidString,
                type: "function",
                function: AssistToolCall.Function(
                    name: tool, arguments: String(decoding: encoded, as: UTF8.self)
                )
            )
        )
    }

    /// Whether `text` says "class" or "classes" as a word of its own.
    private func saysClass(_ text: String) -> Bool {
        return text.range(of: #"\b[Cc]lass(es)?\b"#, options: .regularExpression) != nil
    }

    // MARK: - The model reads the same bytes

    /// THE rule. Every plan a club teacher reaches gives the model exactly
    /// the text it would give in a course that says "class" — and the card
    /// the teacher reads says "meeting" instead.
    func testTheNounNeverReachesWhatTheModelReads() async throws {
        let club = try makeClub(noun: .meeting)
        defer { try? FileManager.default.removeItem(at: club.root) }

        for (tool, arguments) in plans {
            try setNoun(.class, in: club.course)
            let asClass: AssistToolOutcome = await run(club.runner, tool, arguments)
            try setNoun(.meeting, in: club.course)
            let asMeeting: AssistToolOutcome = await run(club.runner, tool, arguments)

            XCTAssertTrue(asClass.isPlan, "\(tool): \(asClass.summary)")
            XCTAssertEqual(asMeeting.detail, asClass.detail, "\(tool): the model was given the noun")
            XCTAssertEqual(asMeeting.summary, asClass.summary, "\(tool)")
            XCTAssertNotEqual(asMeeting.forTheCard, asClass.forTheCard, "\(tool): the card did not change")
            XCTAssertTrue(asMeeting.forTheCard.contains("meeting"), "\(tool): \(asMeeting.forTheCard)")
            XCTAssertFalse(
                saysClass(asMeeting.forTheCard), "\(tool) still says class:\n\(asMeeting.forTheCard)"
            )
            XCTAssertFalse(asMeeting.detail.contains("meeting"), "\(tool): \(asMeeting.detail)")
        }
    }

    /// The writes: the line the teacher reads says "meeting", the model's
    /// copy does not.
    func testAWriteTellsTheTeacherInTheCoursesNounAndTheModelInTheOrdinaryOne() async throws {
        let writes: [(String, [String: Any], String)] = [
            ("publish_class_on", ["course": "ICS3U", "section": 1, "date": "2026-09-09"],
             AssistWording.publishedTheClassOn("2026-09-09", noun: .meeting)),
            ("make_room_for_classes", ["course": "ICS3U", "section": 1, "unit": 2],
             AssistWording.madeRoom(count: 1, at: "Week 2", noun: .meeting)),
            ("re_date_classes", ["course": "ICS3U", "section": 1], "meetings"),
        ]
        for (tool, arguments, expected) in writes {
            let club = try makeClub(noun: .meeting)
            defer { try? FileManager.default.removeItem(at: club.root) }

            let outcome: AssistToolOutcome = await run(club.runner, tool, arguments)
            XCTAssertTrue(outcome.summary.contains(expected), "\(tool): \(outcome.summary)")
            XCTAssertFalse(saysClass(outcome.summary), "\(tool): \(outcome.summary)")
            XCTAssertFalse(outcome.detail.contains("meeting"), "\(tool): \(outcome.detail)")
        }
    }

    /// "When are my next meetings?" — the answer the teacher reads is in the
    /// course's noun, and the copy the model keeps in its history is not.
    func testTheDatesAnswerIsInTheCoursesNounForTheTeacherOnly() async throws {
        let club = try makeClub(noun: .meeting)
        defer { try? FileManager.default.removeItem(at: club.root) }
        let arguments: [String: Any] = ["course": "ICS3U", "section": 1]

        try setNoun(.class, in: club.course)
        let asClass: AssistToolOutcome = await run(club.runner, "read_remembered_timetable", arguments)
        try setNoun(.meeting, in: club.course)
        let asMeeting: AssistToolOutcome = await run(club.runner, "read_remembered_timetable", arguments)

        XCTAssertEqual(asMeeting.detail, asClass.detail)
        XCTAssertEqual(asClass.summary, asClass.detail)
        XCTAssertTrue(asMeeting.summary.contains("meeting"), asMeeting.summary)
        XCTAssertFalse(saysClass(asMeeting.summary), asMeeting.summary)
    }

    /// A course that says nothing hears exactly what it heard before #267.
    func testAnOrdinaryCourseHearsTheSameSentences() {
        XCTAssertEqual(
            AssistWording.otherClassesWouldMove(moving: 2, renaming: 1),
            "2 later classes move a day along to make room, and the links that point at them are "
            + "rewritten to match."
        )
        XCTAssertEqual(AssistWording.mayIAskForYourDates(for: .class), AssistWording.mayIAskForYourDates)
        XCTAssertEqual(AssistWording.datesNotGivenYet(for: .class), AssistWording.datesNotGivenYet)
    }

    // MARK: - The contract

    /// Every `…ForAMeeting` key has its "class" twin, says "meeting", and
    /// never says "class"; the twin says "class".
    func testEveryMeetingKeyHasItsClassTwin() throws {
        let wording: [String: Any] = try XCTUnwrap(AssistContract.wording()["wording"] as? [String: Any])
        var meetingKeys: [String] = []
        for key in wording.keys where key.hasSuffix("ForAMeeting") {
            meetingKeys.append(key)
        }
        XCTAssertGreaterThanOrEqual(meetingKeys.count, 20)
        for key in meetingKeys {
            let twinKey: String = String(key.dropLast("ForAMeeting".count))
            let meeting: String = try XCTUnwrap(wording[key] as? String, key)
            let twin: String = try XCTUnwrap(wording[twinKey] as? String, "\(key) has no \(twinKey)")
            XCTAssertTrue(meeting.contains("meeting"), "\(key): \(meeting)")
            XCTAssertFalse(saysClass(meeting), "\(key): \(meeting)")
            XCTAssertFalse(meeting.contains(", Day "), "\(key): \(meeting)")
            XCTAssertTrue(saysClass(twin), "\(twinKey): \(twin)")
        }
    }

    // MARK: - What the window offers a club

    /// The sentence the declined-dates answer tells a club to say is one the
    /// matcher understands.
    func testTheSentenceAClubIsToldToSayIsMatched() throws {
        let said: String = AssistWording.datesNotGivenYet(for: .meeting)
        let quoted: String = try XCTUnwrap(
            said.components(separatedBy: "“").last?.components(separatedBy: "”").first
        )
        XCTAssertEqual(AssistCardCommand.matching(quoted)?.toolName, "read_remembered_timetable")
    }

    /// Every card on a club's shelf is answered in code, apart from the one
    /// deploy card already measured on the model — so the club shelf
    /// promises nothing no routing measurement has seen.
    func testEveryCardOnAClubsShelfIsMatchedInCode() {
        let naming: ClassPageNaming = ClassPageNaming(word: "Week", scheme: .numbered)
        for noun in [ClassNoun.meeting, ClassNoun.class] {
            var seen: Int = 0
            for (_, phrasings) in AssistPromptShelfView.groups(naming: naming, noun: noun) {
                for phrasing in phrasings {
                    seen += 1
                    if phrasing == "Cancel scheduled deploy" {
                        continue
                    }
                    XCTAssertNotNil(AssistCardCommand.matching(phrasing), "“\(phrasing)” goes to the model")
                    XCTAssertFalse(phrasing.contains("Unit"), phrasing)
                    XCTAssertFalse(phrasing.contains(", Day"), phrasing)
                    if noun == .meeting {
                        XCTAssertFalse(saysClass(phrasing), phrasing)
                    }
                }
            }
            XCTAssertGreaterThan(seen, 10)
        }
    }

    /// An ordinary course's shelf is the shelf it always had.
    func testAnOrdinaryCourseKeepsItsShelf() {
        let shelf: [(String, [String])] = AssistPromptShelfView.groups(
            naming: ClassPageNaming.standard, noun: .class
        )
        XCTAssertEqual(shelf.count, AssistPromptShelfView.groups.count)
        for index in 0..<shelf.count {
            XCTAssertEqual(shelf[index].0, AssistPromptShelfView.groups[index].0)
            XCTAssertEqual(shelf[index].1, AssistPromptShelfView.groups[index].1)
        }
    }

    /// "Make room for a meeting at Week 5": one number, into `unit`, the
    /// slot both kinds of course read safely.
    func testMakeRoomAtOneNumberIsReadIntoTheUnitSlot() {
        let command: AssistCardCommand? = AssistCardCommand.matching("Make room for one meeting at Week 5")
        XCTAssertEqual(command?.toolName, "make_room_for_classes")
        XCTAssertEqual(command?.arguments, ["unit": "5", "howMany": "1"])

        XCTAssertEqual(
            AssistCardCommand.matching("make room for two meetings at week 3")?.arguments,
            ["unit": "3", "howMany": "2"]
        )
        XCTAssertNil(AssistCardCommand.matching("make room for one meeting at day 5"))
        // The shipped near-miss: "at Unit 3" names no day and goes to the model.
        XCTAssertNil(AssistCardCommand.matching("make room for a class at Unit 3"))
        XCTAssertNil(AssistCardCommand.matching("make room for two meeting at week 5"))
        XCTAssertNil(AssistCardCommand.matching("make room for one meeting at 5 5"))
        // The two-number shape is untouched.
        XCTAssertEqual(
            AssistCardCommand.matching("make room for two classes at Unit 3, Day 4")?.arguments,
            ["unit": "3", "atDay": "4", "howMany": "2"]
        )
    }

    /// In a Unit/Day course the one-number shape is a QUESTION, never a
    /// rename: a unit with no day asks which day.
    func testTheOneNumberShapeInAnOrdinaryCourseAsksRatherThanGuesses() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let command: AssistCardCommand = try XCTUnwrap(
            AssistCardCommand.matching("make room for one class at week 5")
        )
        var arguments: [String: Any] = ["course": "ICS3U", "section": 1]
        for (key, value) in command.arguments {
            arguments[key] = value
        }
        let outcome: AssistToolOutcome = await run(made.runner, "plan_make_room_for_classes", arguments)
        XCTAssertFalse(outcome.isPlan)
        XCTAssertTrue(outcome.detail.contains("Which day"), outcome.detail)
    }

    /// "Duplicate Week 2 as my next meeting" is the duplicate family.
    func testDuplicateAsMyNextMeetingIsMatched() {
        let command: AssistCardCommand? = AssistCardCommand.matching("Duplicate Week 2 as my next meeting")
        XCTAssertEqual(command?.toolName, "add_next_class")
        XCTAssertEqual(command?.arguments, ["duplicate": "Week 2"])
    }
}
