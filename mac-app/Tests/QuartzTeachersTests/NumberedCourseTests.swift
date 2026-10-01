import XCTest
@testable import QuartzTeachers

/// A numbered course (#267) — a club whose pages are "Week 1", "Week 2" —
/// through the REAL tools and planners.
///
/// The contract cases in `class-planning.json` pin the rules as data; these
/// are the end-to-end half, and the one that matters most is the first: a
/// numbered course has NO whole-unit path, so "publish Week 1" acts on one
/// page. Before the fix it published every meeting in the section.
@MainActor
final class NumberedCourseTests: XCTestCase {

    // MARK: - Functions

    /// A fixture runner whose course is numbered, with these pages hidden or
    /// shown, a day apart.
    private func makeClub(
        pages: [String], published: Bool
    ) throws -> (root: URL, course: Course, runner: AssistToolRunner) {
        let made = try AssistFixture.makeRunner()
        made.course.configuration.unitWord = "Week"
        made.course.configuration.classPageScheme = .numbered
        try made.course.configuration.write(
            to: made.course.directoryURL.appendingPathComponent("course_config.json")
        )
        var day: Int = 8
        for title in pages {
            try AssistFixture.write(
                page: title, publish: published ? "true" : "false",
                date: String(format: "2026-09-%02d", day),
                body: "The words of \(title).", in: made.course
            )
            day += 1
        }
        return (made.root, made.course, made.runner)
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

    private func isPublished(_ title: String, in course: Course) -> Bool {
        let text: String = (try? String(
            contentsOf: AssistFixture.pageURL(of: title, in: course), encoding: .utf8
        )) ?? ""
        return AssistPageVisibility.publishes(in: text, forSection: 1)
    }

    private func rememberTimetable(_ dates: [String], in course: Course) throws {
        try SectionTimetableStore.applyRememberTimetable(
            try SectionTimetableStore.planRememberTimetable(
                dates: dates, source: "timetable.xlsx, block H", forSection: 1, in: course
            )
        )
    }

    // MARK: - No whole-unit path

    /// THE case: "publish Week 1" in a club publishes Week 1 and nothing else.
    func testPublishingWeekOnePublishesOnlyThatPage() async throws {
        let weeks: [String] = ["Week 1", "Week 2", "Week 3", "Week 4"]
        let club = try makeClub(pages: weeks, published: false)
        defer { try? FileManager.default.removeItem(at: club.root) }

        _ = await run(club.runner, "publish_pages", ["course": "ICS3U", "section": 1, "pages": "Week 1"])

        var published: [String] = []
        for title in weeks where isPublished(title, in: club.course) {
            published.append(title)
        }
        XCTAssertEqual(published, ["Week 1"], "publishing Week 1 must move exactly one page")
    }

    /// The plan card for it says one page, not a unit.
    func testThePlanForWeekOneIsAboutOnePage() async throws {
        let club = try makeClub(pages: ["Week 1", "Week 2", "Week 3", "Week 4"], published: false)
        defer { try? FileManager.default.removeItem(at: club.root) }

        let planned: AssistToolOutcome = await run(
            club.runner, "plan_publish_pages", ["course": "ICS3U", "section": 1, "pages": "Week 1"]
        )
        XCTAssertFalse(planned.forTheCard.contains("Unit"), planned.forTheCard)
        XCTAssertFalse(planned.forTheCard.contains("Week 2"), planned.forTheCard)
    }

    /// Hiding is the same: one page comes down.
    func testHidingWeekOneHidesOnlyThatPage() async throws {
        let weeks: [String] = ["Week 1", "Week 2", "Week 3", "Week 4"]
        let club = try makeClub(pages: weeks, published: true)
        defer { try? FileManager.default.removeItem(at: club.root) }

        _ = await run(club.runner, "unpublish_pages", ["course": "ICS3U", "section": 1, "pages": "Week 1"])

        var hidden: [String] = []
        for title in weeks where !isPublished(title, in: club.course) {
            hidden.append(title)
        }
        XCTAssertEqual(hidden, ["Week 1"], "hiding Week 1 must move exactly one page")
    }

    /// "Week 3" was read as unit 3, found nothing, and was refused. It is a
    /// page, and it is published.
    func testPublishingWeekThreePublishesThePage() async throws {
        let club = try makeClub(pages: ["Week 1", "Week 2", "Week 3"], published: false)
        defer { try? FileManager.default.removeItem(at: club.root) }

        _ = await run(club.runner, "publish_pages", ["course": "ICS3U", "section": 1, "pages": "Week 3"])

        XCTAssertTrue(isPublished("Week 3", in: club.course))
        XCTAssertFalse(isPublished("Week 1", in: club.course))
    }

    /// The contract's `wholeUnit` cases, against the reading the tools use.
    func testWhichTitlesNameAWholeUnitMatchesTheContract() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/class-planning.json")
        let root: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        let section: [String: Any] = try XCTUnwrap(root["wholeUnit"] as? [String: Any])
        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let title: String = try XCTUnwrap(testCase["title"] as? String)
            let naming: ClassPageNaming = ClassPageNaming(
                word: ClassPageTerm.cleaned(testCase["term"] as? String),
                scheme: ClassPageScheme.reading(testCase["scheme"] as? String)
            )
            XCTAssertEqual(
                AssistPublishPlanner.unitNamed(title, naming: naming),
                testCase["expectUnit"] as? Int,
                "\(naming.word) (\(naming.scheme.rawValue)): \(title)"
            )
        }
    }

    // MARK: - No unit is ever started, and no Day is ever written

    func testStartingANewUnitIsRefusedBeforeDatesAreAskedFor() async throws {
        let club = try makeClub(pages: ["Week 1"], published: true)
        defer { try? FileManager.default.removeItem(at: club.root) }

        // No timetable on purpose: the refusal must come first.
        let said: AssistToolOutcome = await run(
            club.runner, "add_next_class", ["course": "ICS3U", "section": 1, "unit": "next"]
        )
        XCTAssertTrue(
            said.detail.contains(
                NextClassPlanner.Problem.noUnitsInANumberedCourse("ICS3U", "Week").errorDescription ?? "—"
            ),
            said.detail
        )
    }

    /// Every planner that NAMES a page, in a numbered course: one number,
    /// never a Day. The review's point about a missed site writing
    /// "Week 1, Day 10" is answered by the compiler (no default naming); this
    /// is the behavioural half.
    func testNoPlannerWritesADayInANumberedCourse() async throws {
        let club = try makeClub(pages: ["Week 1", "Week 2", "Week 3"], published: true)
        defer { try? FileManager.default.removeItem(at: club.root) }
        try rememberTimetable(
            ["2026-09-08", "2026-09-09", "2026-09-10", "2026-09-14", "2026-09-15", "2026-09-16"],
            in: club.course
        )

        let next: PlaceholderClassPlan = try NextClassPlanner.plan(forSection: 1, in: club.course)
        XCTAssertEqual(next.classes.first?.title, "Week 4")
        XCTAssertFalse(next.description.contains("Unit"), next.description)

        let room: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: club.course
        )
        var titles: [String] = []
        for added in room.added {
            titles.append(added.title)
        }
        for rename in room.renames {
            titles.append(rename.to)
        }
        for move in room.moves {
            titles.append(move.title)
        }
        titles.append(room.positionTitle)
        XCTAssertFalse(titles.isEmpty)
        for title in titles {
            XCTAssertFalse(title.contains("Day"), "a numbered course got \(title)")
        }
        XCTAssertTrue(room.description.contains("at Week 2 in"), room.description)

        let placeholder: PlaceholderClassPlan = try PlaceholderClassPlanner.plan(
            unit: 1, firstDay: 5, count: 1, forSection: 1, in: club.course
        )
        XCTAssertEqual(placeholder.classes.first?.title, "Week 5")

        let body: String = ClassPages.skeleton(
            title: "Week 4", unit: 1, naming: club.course.configuration.classPageNaming,
            folderName: "All Meetings", date: try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 14)),
            howMany: 1, tail: ""
        )
        XCTAssertFalse(body.contains("unit-1"), "a numbered page must carry no unit tag")
        XCTAssertTrue(body.contains("All Meetings"), body)
    }

    /// "Make room at Week 5" arriving as a Unit/Day habit's `unit: 5,
    /// atDay: 1` makes room at Week 5 — not at the first meeting — and the
    /// card says so in the course's own words.
    func testMakeRoomReadsTheOneNumberAndSaysItInTheCoursesWords() async throws {
        let club = try makeClub(
            pages: ["Week 1", "Week 2", "Week 3", "Week 4", "Week 5", "Week 6"], published: true
        )
        defer { try? FileManager.default.removeItem(at: club.root) }
        try rememberTimetable(
            ["2026-09-08", "2026-09-09", "2026-09-10", "2026-09-11", "2026-09-12",
             "2026-09-13", "2026-09-14", "2026-09-15"],
            in: club.course
        )

        let planned: AssistToolOutcome = await run(
            club.runner, "plan_make_room_for_classes",
            ["course": "ICS3U", "section": 1, "unit": 5, "atDay": 1]
        )
        XCTAssertTrue(planned.forTheCard.contains("at Week 5 in"), planned.forTheCard)
        XCTAssertFalse(planned.forTheCard.contains("Day"), planned.forTheCard)

        let ambiguous: AssistToolOutcome = await run(
            club.runner, "plan_make_room_for_classes",
            ["course": "ICS3U", "section": 1, "unit": 3, "atDay": 5]
        )
        XCTAssertTrue(ambiguous.detail.contains("Which week"), ambiguous.detail)
    }

    // MARK: - The same sentences, fixed for a Module course (#268)

    /// "Make room … at Unit 3, Day 4" reached a Module course, because the
    /// sentence spelled "Unit" by hand.
    func testAModuleCourseHearsItsOwnWordWhenRoomIsMade() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        made.course.configuration.unitWord = "Module"
        try made.course.configuration.write(
            to: made.course.directoryURL.appendingPathComponent("course_config.json")
        )
        var day: Int = 8
        for number in 1...3 {
            try AssistFixture.write(
                page: "Module 1, Day \(number)", publish: "true",
                date: String(format: "2026-09-%02d", day), body: "Day \(number).", in: made.course
            )
            day += 1
        }
        try rememberTimetable(
            ["2026-09-08", "2026-09-09", "2026-09-10", "2026-09-11"], in: made.course
        )

        let room: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: made.course
        )
        XCTAssertTrue(room.description.contains("at Module 1, Day 2 in"), room.description)
        XCTAssertFalse(room.description.contains("Unit"), room.description)

        let applied: ClassChangeOutcome = try ClassInsertionPlanner.apply(room, in: made.course)
        XCTAssertTrue(applied.message.contains("at Module 1, Day 2."), applied.message)
    }
}
