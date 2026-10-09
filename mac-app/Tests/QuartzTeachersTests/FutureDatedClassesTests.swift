import XCTest
@testable import QuartzTeachers

/// #475: class pages students can see that are dated after the next class
/// day. The cases are `contracts/class-planning.json` → `futureDatedClasses.
/// cases`, run through the real readers on real files in a temporary course —
/// never retyped here — and the kept record is `file-formats.json` →
/// `laterClassesKept`.
@MainActor
final class FutureDatedClassesTests: XCTestCase {

    // MARK: - Stored properties

    private var roots: [URL] = []

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
        roots = []
        try await super.tearDown()
    }

    // MARK: - The contract's cases

    /// Every case flags exactly the places the contract lists, in its order.
    func testEveryCaseFlagsWhatTheContractSays() throws {
        let section: [String: Any] = try FutureDatedClassesTests.contractSection()
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 24, "the contract lost cases")
        var flaggingCases: Int = 0
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let course: Course = try makeCourse(from: testCase)
            let today: CalendarDay = try XCTUnwrap(CalendarDay(text: try XCTUnwrap(testCase["today"] as? String)))
            let flagged: [ClassesDatedLater.Flagged] = ClassesDatedLater.flagged(
                forSection: 1, in: course, today: today
            )
            var places: [String] = []
            for page in flagged {
                places.append(page.place)
            }
            XCTAssertEqual(places, try XCTUnwrap(testCase["expectFlagged"] as? [String]), name)
            if !places.isEmpty {
                flaggingCases += 1
            }
        }
        XCTAssertGreaterThanOrEqual(flaggingCases, 10, "the contract lost the cases that flag something")
    }

    /// The pieces the cases and the other platform lean on are there.
    func testTheContractSaysTheRuleAndWhatWasRejected() throws {
        let section: [String: Any] = try FutureDatedClassesTests.contractSection()
        for key in ["note", "rule", "today", "howTheCasesRun"] {
            XCTAssertNotNil(section[key] as? String, key)
        }
        let rule: String = try XCTUnwrap(section["rule"] as? String)
        XCTAssertTrue(rule.contains("NEXT CLASS DAY"))
        XCTAssertTrue(rule.contains("strictly after today"))
        XCTAssertGreaterThanOrEqual((section["rejected"] as? [String])?.count ?? 0, 5)
    }

    // MARK: - The rule itself

    /// The next class day is counted over every class page, hidden ones too,
    /// and is the earliest date strictly after today.
    func testTheNextClassDayIsTheEarliestClassAfterToday() throws {
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-10-08"))
        let pages: [ClassesDatedLater.Page] = [
            ClassesDatedLater.Page(place: "a", title: "A", isVisible: true, date: CalendarDay(text: "2026-10-08")),
            ClassesDatedLater.Page(place: "b", title: "B", isVisible: false, date: CalendarDay(text: "2026-10-12")),
            ClassesDatedLater.Page(place: "c", title: "C", isVisible: true, date: CalendarDay(text: "2026-10-14")),
            ClassesDatedLater.Page(place: "d", title: "D", isVisible: true, date: nil),
        ]
        XCTAssertEqual(ClassesDatedLater.nextClassDay(after: today, among: pages), CalendarDay(text: "2026-10-12"))
        var places: [String] = []
        for page in ClassesDatedLater.flagged(classPages: pages, today: today, kept: []) {
            places.append(page.place)
        }
        XCTAssertEqual(places, ["c"])
        XCTAssertNil(ClassesDatedLater.nextClassDay(
            after: try XCTUnwrap(CalendarDay(text: "2026-10-14")), among: pages
        ))
    }

    // MARK: - The kept record

    /// Written in the keys the file format names, at the path it names, and
    /// a later answer about the same place replaces the older date.
    func testTheKeptRecordIsTheFileFormatsShape() throws {
        let course: Course = try makeCourse(from: try FutureDatedClassesTests.caseNamed("a class published a week early is asked about"))
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-10-08"))
        let flagged: [ClassesDatedLater.Flagged] = ClassesDatedLater.flagged(forSection: 1, in: course, today: today)
        XCTAssertEqual(flagged.count, 1)
        ClassesDatedLater.keep(flagged, forSection: 1, in: course)
        XCTAssertEqual(ClassesDatedLater.flagged(forSection: 1, in: course, today: today), [], "asked again after Keep")

        let fileURL: URL = ClassesDatedLater.KeptRecord.fileURL(courseDirectory: course.directoryURL, section: 1)
        XCTAssertEqual(fileURL.lastPathComponent, "section1.later-classes-kept.json")
        XCTAssertEqual(fileURL.deletingLastPathComponent().lastPathComponent, ".publish_state")
        let object: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: fileURL)) as? [String: Any]
        )
        let formats: [String: Any] = try FutureDatedClassesTests.contract("file-formats.json")
        let format: [String: Any] = try XCTUnwrap(formats["laterClassesKept"] as? [String: Any])
        let keys: [String: Any] = try XCTUnwrap(format["keys"] as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(keys.keys))
        XCTAssertEqual(
            "courses/<CODE>/.publish_state/section<N>.later-classes-kept.json", format["path"] as? String
        )
        let rows: [[String: Any]] = try XCTUnwrap(object["kept"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["place"] as? String, "section1/All Classes/Unit 2, Day 5")
        XCTAssertEqual(rows.first?["date"] as? String, "2026-10-14")
        let answeredAt: String = try XCTUnwrap(object["answeredAt"] as? String)
        XCTAssertTrue(answeredAt.hasSuffix("Z"), answeredAt)
        XCTAssertEqual(answeredAt.count, 20, answeredAt)

        // Re-dated, the same place is asked about again; kept once more, the
        // record holds the place once, at its new date.
        let moved: ClassesDatedLater.Flagged = ClassesDatedLater.Flagged(
            place: "section1/All Classes/Unit 2, Day 5", title: "Unit 2, Day 5",
            date: try XCTUnwrap(CalendarDay(text: "2026-10-15"))
        )
        let record: ClassesDatedLater.KeptRecord = ClassesDatedLater.KeptRecord.adding(
            [moved], to: ClassesDatedLater.KeptRecord.read(courseDirectory: course.directoryURL, section: 1)
        )
        XCTAssertEqual(record.kept, [ClassesDatedLater.Kept(place: "section1/All Classes/Unit 2, Day 5", date: "2026-10-15")])
    }

    /// Removed on rollover, with the links checklist's answers, and put back
    /// by the rollover's undo (`laterClassesKept.writtenBy`).
    func testTheKeptRecordIsReleasedOnRollover() throws {
        let course: Course = try makeCourse(from: try FutureDatedClassesTests.caseNamed("a class published a week early is asked about"))
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-10-08"))
        ClassesDatedLater.keep(ClassesDatedLater.flagged(forSection: 1, in: course, today: today), forSection: 1, in: course)
        let fileURL: URL = ClassesDatedLater.KeptRecord.fileURL(courseDirectory: course.directoryURL, section: 1)
        let before: String = try String(contentsOf: fileURL, encoding: .utf8)
        let released: [AssistSavedFile] = PublishedPagesRecord.release(courseDirectory: course.directoryURL, section: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        var putBack: Bool = false
        for file in released where file.fileURL == fileURL && file.before == before && file.after == nil {
            putBack = true
        }
        XCTAssertTrue(putBack, "the rollover's undo can put the record back")
        XCTAssertEqual(ClassesDatedLater.flagged(forSection: 1, in: course, today: today).count, 1)
    }

    // MARK: - Publish Pages…

    /// The question asked of hidden pages about to be published: only the
    /// picked ones, judged against the section's own next class day.
    func testPickedHiddenPagesAreJudgedAsIfPublished() throws {
        let course: Course = try makeCourse(from: [
            "today": "2026-10-08",
            "pages": [
                ["path": "All Classes/Unit 2, Day 4.md", "flag": "publish: false", "created": "2026-10-09T07:00:00.000-0400"],
                ["path": "All Classes/Unit 2, Day 5.md", "flag": "publish: false", "created": "2026-10-14T07:00:00.000-0400"],
                ["path": "All Classes/Unit 2, Day 6.md", "flag": "publish: false", "created": "2026-10-15T07:00:00.000-0400"],
            ],
        ])
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-10-08"))
        let folder: URL = ClassPages.folderURL(forSection: 1, in: course)
        let picked: [URL] = [
            folder.appendingPathComponent("Unit 2, Day 4.md"),
            folder.appendingPathComponent("Unit 2, Day 5.md"),
        ]
        var places: [String] = []
        for page in ClassesDatedLater.flagged(ifPublishing: picked, forSection: 1, in: course, today: today) {
            places.append(page.place)
        }
        XCTAssertEqual(places, ["section1/All Classes/Unit 2, Day 5"], "tomorrow's class is not asked about; Day 6 was not picked")
    }

    // MARK: - Helpers

    private func makeCourse(from testCase: [String: Any]) throws -> Course {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("later-classes-\(UUID().uuidString)")
        roots.append(root)
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("TEST")
        var sections: Set<Int> = [1]
        for page in try XCTUnwrap(testCase["pages"] as? [[String: Any]]) {
            sections.insert((page["section"] as? Int) ?? 1)
        }
        var sectionList: [Int] = []
        for number in sections.sorted() {
            sectionList.append(number)
            for folder in ["All Classes", "Concepts"] {
                try FileManager.default.createDirectory(
                    at: courseURL.appendingPathComponent("section\(number)/\(folder)"), withIntermediateDirectories: true
                )
            }
        }
        var configuration: [String: Any] = [
            "course_code": "TEST",
            "course_name": "A Test Course",
            "section_numbers": sectionList,
            "num_sections": sectionList.count,
            "per_section_folders": ["All Classes", "Concepts"],
            "per_section_files": []
        ]
        if let word = testCase["unitWord"] as? String {
            configuration["unit_word"] = word
        }
        if let scheme = testCase["classPageScheme"] as? String {
            configuration["class_page_scheme"] = scheme
        }
        if let noun = testCase["noun"] as? String {
            configuration["class_noun"] = noun
        }
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        let course: Course = Course(code: "TEST", directoryURL: courseURL, configuration: loaded)

        for page in try XCTUnwrap(testCase["pages"] as? [[String: Any]]) {
            let path: String = try XCTUnwrap(page["path"] as? String)
            let number: Int = (page["section"] as? Int) ?? 1
            let fileURL: URL = course.sectionDirectoryURL(forSection: number).appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let title: String = fileURL.deletingPathExtension().lastPathComponent
            var text: String = "---\ntitle: \(title)\n" + (try XCTUnwrap(page["flag"] as? String)) + "\n"
            if let created = page["created"] as? String {
                text += "created: \(created)\n"
            }
            text += "---\n\nThe words of \(title).\n"
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        if let kept = testCase["kept"] as? [[String: Any]] {
            var rows: [ClassesDatedLater.Kept] = []
            for row in kept {
                rows.append(ClassesDatedLater.Kept(
                    place: try XCTUnwrap(row["place"] as? String), date: try XCTUnwrap(row["date"] as? String)
                ))
            }
            try ClassesDatedLater.KeptRecord(answeredAt: "2026-10-01T12:00:00Z", kept: rows)
                .write(courseDirectory: courseURL, section: 1)
        }
        return course
    }

    private static func caseNamed(_ name: String) throws -> [String: Any] {
        for testCase in try XCTUnwrap(contractSection()["cases"] as? [[String: Any]]) where testCase["name"] as? String == name {
            return testCase
        }
        XCTFail("no case called \(name)")
        return [:]
    }

    private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    static func contract(_ name: String) throws -> [String: Any] {
        let url: URL = repositoryRoot().appendingPathComponent("contracts").appendingPathComponent(name)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
    }

    private static func contractSection() throws -> [String: Any] {
        return try XCTUnwrap(try contract("class-planning.json")["futureDatedClasses"] as? [String: Any])
    }
}
