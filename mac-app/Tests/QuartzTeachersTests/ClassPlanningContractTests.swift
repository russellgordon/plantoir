import XCTest
@testable import QuartzTeachers

/// Runs `contracts/class-planning.json` — naming, numbering, and making room
/// for a class in the middle of a unit.
///
/// **The highest-stakes data in these contracts.** Everything else describes a
/// sentence or an order of events; this describes renaming the files a
/// teacher's lessons live in. The rename ORDER in particular looks like an
/// implementation detail and is the difference between a course that survives
/// and one that loses a lesson, so it is written down where both platforms
/// read it rather than in a comment one of them will never see.
@MainActor
final class ClassPlanningContractTests: XCTestCase {

    // MARK: - Which titles carry numbers

    func testTitlesAreNumberedOrLeftAloneAsTheContractSays() throws {
        for testCase in try ClassPlanningContractTests.cases(in: "pageNaming") {
            let title: String = try XCTUnwrap(testCase["title"] as? String)
            // A case with no `term` uses the default word, which is what a
            // course says when `unit_word` is absent from its configuration.
            let term: String = ClassPageTerm.cleaned(testCase["term"] as? String)
            let numbers: UnitDay? = UnitDay(pageTitle: title, term: term)
            XCTAssertEqual(numbers?.unit, testCase["expectUnit"] as? Int, "\(term): \(title)")
            XCTAssertEqual(numbers?.day, testCase["expectDay"] as? Int, "\(term): \(title)")
        }
    }

    func testNumberedClassesSortByUnitThenDay() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("numberedClassOrder")
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        for title in try XCTUnwrap(section["input"] as? [String]) {
            try writeClass(title, on: "2026-09-08", in: course)
        }
        let sorted: [ClassPageSummary] = ClassInsertionPlanner.numberedClasses(
            among: ClassPages.list(forSection: 1, in: course)
        )
        var titles: [String] = []
        for page in sorted {
            titles.append(page.title)
        }
        XCTAssertEqual(titles, try XCTUnwrap(section["expectOrder"] as? [String]))
    }

    // MARK: - What the next class would be called

    func testTheNextClassIsNamedAsTheContractSays() throws {
        for testCase in try ClassPlanningContractTests.cases(in: "nextClass") {
            let (root, _, course) = try makeWorkspace()
            defer { try? FileManager.default.removeItem(at: root) }

            for title in try XCTUnwrap(testCase["existing"] as? [String]) {
                try writeClass(title, on: "2026-09-08", in: course)
            }
            let next: UnitDay = NextClassPlanner.nextUnitAndDay(
                after: ClassPages.list(forSection: 1, in: course)
            )
            let what: String = (try XCTUnwrap(testCase["existing"] as? [String])).joined(separator: " / ")
            XCTAssertEqual(next.unit, testCase["expectUnit"] as? Int, "after [\(what)]")
            XCTAssertEqual(next.day, testCase["expectDay"] as? Int, "after [\(what)]")
        }
    }

    // MARK: - Making room

    func testInsertionPlansMatchTheContract() throws {
        for testCase in try ClassPlanningContractTests.cases(in: "insertion") {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let (root, _, course) = try makeWorkspace(
                meetingDates: try XCTUnwrap(testCase["timetable"] as? [String])
            )
            defer { try? FileManager.default.removeItem(at: root) }

            for existing in try XCTUnwrap(testCase["existingClasses"] as? [[String: String]]) {
                try writeClass(
                    try XCTUnwrap(existing["title"]), on: try XCTUnwrap(existing["date"]), in: course
                )
            }

            let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
                unit: try XCTUnwrap(testCase["insertAtUnit"] as? Int),
                atDay: try XCTUnwrap(testCase["insertAtDay"] as? Int),
                count: try XCTUnwrap(testCase["count"] as? Int),
                forSection: 1,
                in: course
            )

            // The order is the assertion. Highest day first, so every
            // destination has been vacated before it is needed.
            var renames: [String] = []
            for rename in plan.renames {
                renames.append("\(rename.from) → \(rename.to)")
            }
            XCTAssertEqual(
                renames, try XCTUnwrap(testCase["expectRenamesInOrder"] as? [String]),
                "\(name): renames, in order"
            )

            if let expected = testCase["expectDateMoves"] as? [String] {
                var moved: [String] = []
                for move in plan.moves {
                    moved.append(move.title)
                }
                for title in expected {
                    XCTAssertTrue(moved.contains(title), "\(name): \(title) should have moved date")
                }
            }

            if let mentions = testCase["expectProblemMentions"] as? String {
                let said: String = plan.problems.joined(separator: " ")
                XCTAssertTrue(
                    said.contains(mentions),
                    "\(name): the plan must warn about pages it left alone — it said \"\(said)\""
                )
            }
        }
    }

    func testTheRefusalsAreTheOnesTheContractNames() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeClass("Unit 1, Day 1", on: "2026-09-08", in: course)

        for testCase in try ClassPlanningContractTests.cases(in: "refusals") {
            let expected: String = try XCTUnwrap(testCase["expectProblem"] as? String)
            do {
                _ = try ClassInsertionPlanner.plan(
                    unit: try XCTUnwrap(testCase["insertAtUnit"] as? Int),
                    atDay: try XCTUnwrap(testCase["insertAtDay"] as? Int),
                    count: try XCTUnwrap(testCase["count"] as? Int),
                    forSection: 1,
                    in: course
                )
                XCTFail("Should have been refused as \(expected)")
            } catch let problem as ClassInsertionPlanner.Problem {
                XCTAssertEqual(ClassPlanningContractTests.name(of: problem), expected)
            }
        }
    }

    // MARK: - Private

    private static func name(of problem: ClassInsertionPlanner.Problem) -> String {
        switch problem {
        case .unitOutOfRange:
            return "unitOutOfRange"
        case .dayOutOfRange:
            return "dayOutOfRange"
        case .countOutOfRange:
            return "countOutOfRange"
        case .noTimetable:
            return "noTimetable"
        case .noNumberedClasses:
            return "noNumberedClasses"
        default:
            return "other"
        }
    }

    private func makeWorkspace(
        meetingDates: [String] = ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16",
                                  "2026-09-18", "2026-09-22"]
    ) throws -> (root: URL, coursesURL: URL, course: Course) {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("class-planning-contract-\(UUID().uuidString)")
        let coursesURL: URL = root.appendingPathComponent("courses")
        let courseURL: URL = coursesURL.appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
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
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        let course: Course = Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
        if !meetingDates.isEmpty {
            let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
                dates: meetingDates, source: "timetable.xlsx, block H", forSection: 1, in: course
            )
            try SectionTimetableStore.applyRememberTimetable(plan)
        }
        return (root, coursesURL, course)
    }

    private func writeClass(_ title: String, on date: String, in course: Course) throws {
        let page: String = """
        ---
        title: \(title)
        publish: true
        created: \(date)T07:00:00.000-0400
        ---

        \(title)
        """
        try page.write(
            to: ClassPages.folderURL(forSection: 1, in: course).appendingPathComponent(title + ".md"),
            atomically: true, encoding: .utf8
        )
    }

    // MARK: - Dating the pages a class brings

    /// The frontmatter key, which differs by where the page lives.
    ///
    /// A page inside the section's own folder carries `created`; a course-level
    /// page shared between sections carries one key PER SECTION. Getting this
    /// wrong dates the page for a section the teacher was not talking about.
    func testTheDateKeyIsTheOneTheContractNames() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("datingPagesAClassBrings")
        let keys: [String: Any] = try XCTUnwrap(section["frontmatterKey"] as? [String: Any])

        XCTAssertEqual(
            PageFrontmatter.createdKey(forSection: 1, isSectionLocal: true),
            keys["sectionLocalPage"] as? String
        )
        let shared: String = try XCTUnwrap(keys["courseLevelPage"] as? String)
        for number in [1, 2, 7] {
            XCTAssertEqual(
                PageFrontmatter.createdKey(forSection: number, isSectionLocal: false),
                shared.replacingOccurrences(of: "<N>", with: "\(number)")
            )
        }
    }

    /// The rule itself, run against the real planner: what moves, what does
    /// not, and which class claims a page several of them bring.
    @MainActor
    func testPagesAClassBringsMoveExactlyAsTheContractSays() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("datingPagesAClassBrings")

        let earlier: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-10-06"))
        let later: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-12-01"))
        let old: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-08-01"))

        func page(_ title: String, visible: Bool, day: CalendarDay?,
                  links: [String], folder: String) -> AssistSectionPage {
            return AssistSectionPage(
                title: title,
                displayTitle: title,
                fileURL: URL(fileURLWithPath: "/courses/ICS3U/\(folder)/\(title).md"),
                relativePath: "courses/ICS3U/\(folder)/\(title).md",
                isSectionLocal: folder.contains("Classes"),
                isVisibleToStudents: visible,
                date: day,
                linkedTitles: links.map { $0.lowercased() },
                classFolderNames: ["All Classes"],
                pathWithinSection: "\(folder)/\(title).md"
            )
        }

        let graph: AssistSectionGraph = AssistSectionGraph(
            courseCode: "ICS3U", sectionNumber: 1,
            pages: [
                page("Unit 2, Day 3", visible: false, day: earlier,
                     links: ["never seen", "already out"], folder: "section1/All Classes"),
                page("Unit 4, Day 2", visible: false, day: later,
                     links: ["never seen"], folder: "section1/All Classes"),
                page("never seen", visible: false, day: old, links: [], folder: "Concepts"),
                page("already out", visible: true, day: old, links: [], folder: "Concepts"),
            ]
        )
        func summary(_ title: String, _ day: CalendarDay) -> ClassPageSummary {
            return ClassPageSummary(
                title: title,
                fileURL: URL(fileURLWithPath: "/courses/ICS3U/section1/All Classes/\(title).md"),
                date: day
            )
        }
        let classes: [ClassPageSummary] = [
            summary("Unit 2, Day 3", earlier),
            summary("Unit 4, Day 2", later),
        ]

        // Named LATEST first — the earliest must still claim the shared page.
        let moves: [AssistPublishDateMove] = AssistPublishPlanner.dateMovesFollowingClasses(
            titles: ["Unit 4, Day 2", "Unit 2, Day 3"], graph: graph, classPages: classes
        )

        var moved: [String: String] = [:]
        for move in moves {
            moved[move.page.lowercasedTitle] = move.to.text
        }

        if (section["sharedPagesMoveToo"] as? [String: Any])?["value"] as? Bool == true {
            XCTAssertEqual(moved["never seen"], "2026-10-06",
                           "A never-seen page did not take the earliest class's date")
        }
        XCTAssertNil(moved["already out"],
                     "A page students can already see was re-dated underneath them")
        XCTAssertNil(moved["unit 2, day 3"], "A class was moved off its own day")
        XCTAssertNil(moved["unit 4, day 2"], "A class was moved off its own day")
    }

    // MARK: - Dating non-class pages

    func testNonClassPagesContractExistsAndIsDocumented() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("datingNonClassPages")
        XCTAssertNotNil(section["note"])
        let appliesTo: [String] = try XCTUnwrap(section["appliesTo"] as? [String])
        XCTAssertFalse(appliesTo.isEmpty)
        XCTAssertNotNil(section["dateInherited"])
        XCTAssertNotNil(section["why"])
    }

    private static func section(_ name: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/class-planning.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[name] as? [String: Any], "No \(name) in class-planning.json")
    }

    private static func cases(in name: String) throws -> [[String: Any]] {
        return try XCTUnwrap(section(name)["cases"] as? [[String: Any]])
    }
}
