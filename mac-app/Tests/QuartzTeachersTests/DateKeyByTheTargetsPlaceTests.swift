import XCTest
@testable import QuartzTeachers

/// #1048: when a class page of Section N is a link, the class's date lives in
/// the file the link leads to, under the key that FILE's place calls for:
/// `createdSection<N>` for a course-level page, plain `created` only inside
/// the section's own folder. Every reader and writer decides it through ONE
/// function, `ClassPages.dateKey`. And (Russell on #899, 2026-11-26) a shared
/// lesson several classes of one section link to keeps the date of the
/// FIRST of them, "Always", whatever order a writer writes in.
@MainActor
final class DateKeyByTheTargetsPlaceTests: XCTestCase {

    // MARK: - Stored properties

    var folders: [URL] = []

    // MARK: - Setting up

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
        folders = []
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// One course, one section, six remembered meeting days, and Unit 1,
    /// Day 1 to Day 3 as plain pages on the first three.
    func makeCourse() throws -> (root: URL, course: Course, classes: URL) {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("date-key-\(UUID().uuidString)", isDirectory: true)
        folders.append(root)
        let courseURL: URL = root.appendingPathComponent("courses/ICS3U", isDirectory: true)
        let classes: URL = courseURL.appendingPathComponent("section1/All Classes", isDirectory: true)
        try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("elsewhere", isDirectory: true), withIntermediateDirectories: true
        )
        UndoJournalLocation.folderOverride = root.appendingPathComponent("list", isDirectory: true)
        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        let course: Course = Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
        let dates: [String] = ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16", "2026-09-18", "2026-09-22"]
        try SectionTimetableStore.applyRememberTimetable(
            try SectionTimetableStore.planRememberTimetable(
                dates: dates, source: "timetable.xlsx, block H", forSection: 1, in: course
            )
        )
        let days: [(day: Int, date: String)] = [(1, "2026-09-08"), (2, "2026-09-10"), (3, "2026-09-14")]
        for entry in days {
            let title: String = "Unit 1, Day \(entry.day)"
            let text: String = "---\ntitle: \(title)\npublish: true\ncreated: \(entry.date)T07:00:00.000-0400\n---\n\nDay.\n"
            try text.write(to: classes.appendingPathComponent(title + ".md"), atomically: true, encoding: .utf8)
        }
        return (root: root, course: course, classes: classes)
    }

    /// A course-level page every section shares, with a line for each of
    /// the two sections.
    func sharedLesson(section1: String, section2: String = "2026-10-01") -> String {
        return "---\ntitle: Shared lesson\npublish: true\ncreatedSection1: \(section1)T07:00:00.000-0400\n"
            + "createdSection2: \(section2)T07:00:00.000-0400\n---\n\nShared.\n"
    }

    /// Writes `text` at `elsewhere/Shared.md` and turns each class page in
    /// `titles` into a link to it. Returns the shared file.
    @discardableResult
    func linkClasses(_ titles: [String], toASharedLesson text: String,
                     in made: (root: URL, course: Course, classes: URL)) throws -> URL {
        let file: URL = made.course.directoryURL.appendingPathComponent("elsewhere/Shared.md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        for title in titles {
            let place: URL = made.classes.appendingPathComponent(title + ".md")
            try FileManager.default.removeItem(at: place)
            try FileManager.default.createSymbolicLink(atPath: place.path, withDestinationPath: "../../elsewhere/Shared.md")
        }
        return file
    }

    func dateOfClass(_ title: String, in made: (root: URL, course: Course, classes: URL)) -> CalendarDay? {
        for summary in ClassPages.list(forSection: 1, in: made.course) where summary.title == title {
            return summary.date
        }
        return nil
    }

    func stepCount() throws -> Int {
        let fold: UndoFold = try UndoJournalLocation.standardJournal().read()
        return fold.records.count
    }

    /// Every file and link under the working folder, never followed.
    func everything(under made: (root: URL, course: Course, classes: URL)) -> [String: String] {
        var result: [String: String] = [:]
        guard let walker = FileManager.default.enumerator(atPath: made.root.path) else {
            return result
        }
        while let relative = walker.nextObject() as? String {
            if relative.hasPrefix("list") || relative.hasPrefix("courses/.internal") || relative.hasSuffix("course_config.json") {
                continue
            }
            let url: URL = made.root.appendingPathComponent(relative)
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
                result[relative] = "-> " + target
                continue
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                continue
            }
            result[relative] = (try? String(contentsOf: url, encoding: .utf8)) ?? "(unreadable)"
        }
        return result
    }

    /// Undo of the newest step returns the folder to `before` exactly.
    /// Re-date keeps the section's front page true by a rule, so its step is
    /// undone with that rule re-derived, as the app does.
    func checkUndoReturns(_ before: [String: String], in made: (root: URL, course: Course, classes: URL)) async throws {
        let journal: UndoJournal = try UndoJournalLocation.standardJournal()
        let root: URL = made.root
        UndoMaintainers.registerTheAppsFrontPage()
        let undone: UndoOutcome = await journal.undoNewestAndRederive(resolveRoot: { _ in root })
        guard case .undone = undone else {
            return XCTFail("Undo came to \(undone)")
        }
        XCTAssertEqual(everything(under: made), before, "Undo puts back exactly what was there")
    }

    func reDate(in made: (root: URL, course: Course, classes: URL)) throws {
        let plan: SectionReDatePlan = try SectionReDatePlanner.plan(forSection: 1, in: made.course, workspaceURL: nil)
        _ = try SectionReDatePlanner.apply(plan, forSection: 1, in: made.course)
    }

    func makeRoom(atDay day: Int, in made: (root: URL, course: Course, classes: URL)) throws -> ClassInsertionPlan {
        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: day, count: 1, forSection: 1, in: made.course
        )
        _ = try ClassInsertionPlanner.apply(plan, in: made.course)
        return plan
    }

    // MARK: - Tests: the one rule

    /// The shared function, case by case: the key is the place of the FILE
    /// the page is, through every link; a broken link has none.
    func testTheKeyIsDecidedByThePlaceOfTheFileThePageIs() throws {
        let made = try makeCourse()
        let courseURL: URL = made.course.directoryURL
        let sectionNotes: URL = courseURL.appendingPathComponent("section1/Notes.md")
        try "---\ntitle: Notes\n---\n".write(to: sectionNotes, atomically: true, encoding: .utf8)
        let shared: URL = courseURL.appendingPathComponent("elsewhere/Shared.md")
        try sharedLesson(section1: "2026-09-14").write(to: shared, atomically: true, encoding: .utf8)
        let inBetween: URL = courseURL.appendingPathComponent("section1/In between.md")
        try FileManager.default.createSymbolicLink(atPath: inBetween.path, withDestinationPath: "../elsewhere/Shared.md")

        let cases: [(name: String, title: String, target: String?, expected: String?)] = [
            ("a link inside the section's folder", "Unit 1, Day 4", "../Notes.md", "created"),
            ("a link to a course-level page", "Unit 1, Day 5", "../../elsewhere/Shared.md", "createdSection1"),
            ("a link through an in-between link", "Unit 1, Day 6", "../In between.md", "createdSection1"),
            ("a broken link", "Unit 1, Day 7", "../../elsewhere/Nothing here.md", nil),
            ("a class page that is not a link", "Unit 1, Day 1", nil, "created"),
        ]
        for entry in cases {
            let place: URL = made.classes.appendingPathComponent(entry.title + ".md")
            if let target = entry.target {
                try FileManager.default.createSymbolicLink(atPath: place.path, withDestinationPath: target)
            }
            XCTAssertEqual(
                ClassPages.dateKey(ofPageAt: place, forSection: 1, in: made.course), entry.expected, entry.name
            )
        }
    }

    /// The same rule as data both apps run: `class-planning.json` →
    /// `datingPagesAClassBrings.frontmatterKey.linkedClassPageCases`.
    func testTheKeyCasesInTheContract() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/class-planning.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let section: [String: Any] = try XCTUnwrap(all["datingPagesAClassBrings"] as? [String: Any])
        let keys: [String: Any] = try XCTUnwrap(section["frontmatterKey"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(keys["linkedClassPageCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5)
        for entry in cases {
            let made = try makeCourse()
            let name: String = (entry["name"] as? String) ?? "?"
            let sectionNumber: Int = (entry["section"] as? Int) ?? 1
            let courseURL: URL = made.course.directoryURL
            let files: [String] = (entry["files"] as? [String]) ?? []
            for path in files {
                let file: URL = courseURL.appendingPathComponent(path)
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try "---\ntitle: A page\n---\n".write(to: file, atomically: true, encoding: .utf8)
            }
            let links: [String: String] = (entry["links"] as? [String: String]) ?? [:]
            for (path, holds) in links {
                try FileManager.default.createSymbolicLink(
                    atPath: courseURL.appendingPathComponent(path).path, withDestinationPath: holds
                )
            }
            let folder: URL = courseURL.appendingPathComponent(try XCTUnwrap(entry["classFolder"] as? String))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let place: URL = folder.appendingPathComponent("Unit 1, Day 9.md")
            if let holds = entry["linkHolds"] as? String {
                try FileManager.default.createSymbolicLink(atPath: place.path, withDestinationPath: holds)
            } else {
                try "---\ntitle: Unit 1, Day 9\n---\n".write(to: place, atomically: true, encoding: .utf8)
            }
            XCTAssertEqual(
                ClassPages.dateKey(ofPageAt: place, forSection: sectionNumber, in: made.course),
                entry["expectKey"] as? String, name
            )
        }
    }

    // MARK: - Tests: readers

    /// The sweep's concrete case: a shared file holding `createdSection1`
    /// AND a stale `created`. The class list reads this section's key.
    /// MUST FAIL on d334a288e, which read plain `created` (the 14th).
    func testTheClassListReadsThisSectionsKeyThroughALink() throws {
        let made = try makeCourse()
        let text: String = "---\ncreatedSection1: 2026-09-16T07:00:00.000-0400\ntitle: Unit 1, Day 3\npublish: true\n"
            + "created: 2026-09-14T07:00:00.000-0400\n---\n\nThree.\n"
        try linkClasses(["Unit 1, Day 3"], toASharedLesson: text, in: made)

        XCTAssertEqual(dateOfClass("Unit 1, Day 3", in: made), CalendarDay(text: "2026-09-16"))
    }

    /// A shared file with only section lines: the class is dated, not
    /// undated. MUST FAIL on d334a288e (no date at all).
    func testTheClassListReadsASharedLessonWithOnlySectionLines() throws {
        let made = try makeCourse()
        try linkClasses(["Unit 1, Day 3"], toASharedLesson: sharedLesson(section1: "2026-09-14"), in: made)

        XCTAssertEqual(dateOfClass("Unit 1, Day 3", in: made), CalendarDay(text: "2026-09-14"))
    }

    /// The assistant's graph (and so Re-date and publishing) reads the
    /// same key. MUST FAIL on d334a288e.
    func testTheAssistantsGraphReadsThisSectionsKeyThroughALink() throws {
        let made = try makeCourse()
        try linkClasses(["Unit 1, Day 3"], toASharedLesson: sharedLesson(section1: "2026-09-14"), in: made)

        let graph: AssistSectionGraph = AssistSectionGraph.read(forSection: 1, in: made.course, workspaceURL: nil)
        let page: AssistSectionPage? = graph.page(titled: "Unit 1, Day 3")
        XCTAssertEqual(page?.date, CalendarDay(text: "2026-09-14"))
        XCTAssertEqual(page?.dateKey, "createdSection1")
        XCTAssertEqual(page?.isSectionLocal, true, "visibility still follows the link's own place")
    }

    // MARK: - Tests: Re-date

    /// Re-date of a class linked to a shared page changes only this
    /// section's line; no plain `created` is added; Undo returns exactly.
    /// MUST FAIL on d334a288e, which added `created:` and left
    /// `createdSection1` (the line the build reads) as it was.
    func testReDateWritesOnlyThisSectionsLineThroughALink() async throws {
        let made = try makeCourse()
        let laid: String = sharedLesson(section1: "2026-09-20")
        let file: URL = try linkClasses(["Unit 1, Day 3"], toASharedLesson: laid, in: made)
        let before: [String: String] = everything(under: made)

        try reDate(in: made)

        let expected: String = laid.replacingOccurrences(of: "createdSection1: 2026-09-20", with: "createdSection1: 2026-09-14")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), expected)
        XCTAssertEqual(dateOfClass("Unit 1, Day 3", in: made), CalendarDay(text: "2026-09-14"))
        try await checkUndoReturns(before, in: made)
    }

    /// Two classes linked to one shared lesson, the first moving: the file
    /// ends with the FIRST class's day, in one step, undone exactly.
    /// MUST FAIL on d334a288e.
    func testReDateOfTwoLinkedClassesKeepsTheFirstClassesDate() async throws {
        let made = try makeCourse()
        let file: URL = try linkClasses(
            ["Unit 1, Day 2", "Unit 1, Day 3"], toASharedLesson: sharedLesson(section1: "2026-09-20"), in: made
        )
        let before: [String: String] = everything(under: made)
        let stepsBefore: Int = try stepCount()

        try reDate(in: made)

        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("createdSection1: 2026-09-10T"))
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("\ncreated:"))
        XCTAssertEqual(try stepCount() - stepsBefore, 1, "one step")
        try await checkUndoReturns(before, in: made)
    }

    /// Three classes linked to one shared lesson, the first already on its
    /// day: nothing a later class plans may move it. MUST FAIL on
    /// d334a288e, which wrote a later class's day.
    func testReDateOfThreeLinkedClassesLeavesTheFirstClassesDate() throws {
        let made = try makeCourse()
        let laid: String = sharedLesson(section1: "2026-09-08")
        let file: URL = try linkClasses(
            ["Unit 1, Day 1", "Unit 1, Day 2", "Unit 1, Day 3"], toASharedLesson: laid, in: made
        )

        try reDate(in: made)

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), laid)
    }

    // MARK: - Tests: Insert Class

    /// Two classes linked to one lesson, room made at the first: the file
    /// takes the day the first class is given, one step, undone exactly.
    func testInsertClassMovingTheFirstOfTwoLinkedClassesWritesItsDate() async throws {
        let made = try makeCourse()
        let file: URL = try linkClasses(
            ["Unit 1, Day 2", "Unit 1, Day 3"], toASharedLesson: sharedLesson(section1: "2026-09-10"), in: made
        )
        let before: [String: String] = everything(under: made)
        let stepsBefore: Int = try stepCount()

        let plan: ClassInsertionPlan = try makeRoom(atDay: 2, in: made)

        var firstClassesDay: CalendarDay? = nil
        for move in plan.moves where move.fileURL.lastPathComponent == "Unit 1, Day 2.md" {
            firstClassesDay = move.to
        }
        let expected: String = (firstClassesDay ?? CalendarDay(text: "2026-09-10")!).text
        let after: String = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(after.contains("createdSection1: \(expected)T"), "the first class's day, \(expected): \(after)")
        XCTAssertEqual(try stepCount() - stepsBefore, 1, "one step")
        try await checkUndoReturns(before, in: made)
    }

    /// Two classes linked to one lesson, room made between them: the later
    /// one moves and the first does not, so the file keeps the first
    /// class's day. MUST FAIL on d334a288e, which wrote the later day.
    func testInsertClassMovingOnlyTheLaterLinkedClassLeavesTheFile() async throws {
        let made = try makeCourse()
        let laid: String = sharedLesson(section1: "2026-09-10")
        let file: URL = try linkClasses(["Unit 1, Day 2", "Unit 1, Day 3"], toASharedLesson: laid, in: made)
        let before: [String: String] = everything(under: made)

        _ = try makeRoom(atDay: 3, in: made)

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), laid)
        try await checkUndoReturns(before, in: made)
    }

    /// Three classes linked to one lesson, room made at the second: the
    /// first class does not move, so neither does the file.
    func testInsertClassWithThreeLinkedClassesKeepsTheFirstClassesDate() throws {
        let made = try makeCourse()
        let laid: String = sharedLesson(section1: "2026-09-08")
        let file: URL = try linkClasses(
            ["Unit 1, Day 1", "Unit 1, Day 2", "Unit 1, Day 3"], toASharedLesson: laid, in: made
        )

        _ = try makeRoom(atDay: 2, in: made)

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), laid)
    }
}
