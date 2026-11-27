import XCTest
@testable import QuartzTeachers

/// #1048b review 1: a shared lesson a numbered class owns is still a dated
/// lesson, its date the owner's, and is never written over.
///
/// - The contract's `firstClassKeepsASharedLessonCases` run through the
///   Mac's one rule (`ClassPages.filesTheNumberedClassesOwn`,
///   `isTheFirstClassLeadingToItsFile`), so the build's copy of the rule and
///   this one are pinned to one table and cannot drift (LOW 4).
/// - Publishing from the links checklist never writes another class's date
///   into a file a numbered class owns, whatever the offer says (HIGH 1).
@MainActor
final class FirstClassKeepsASharedLessonTests: XCTestCase {

    // MARK: - Stored properties

    var folders: [URL] = []

    // MARK: - Setting up

    override func tearDown() async throws {
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
        folders = []
        try await super.tearDown()
    }

    // MARK: - Functions

    static func contractCases() throws -> [[String: Any]] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("contracts/class-planning.json")
        let object: Any = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let planning: [String: Any] = try XCTUnwrap(object as? [String: Any])
        let dating: [String: Any] = try XCTUnwrap(planning["datingPagesAClassBrings"] as? [String: Any])
        let keys: [String: Any] = try XCTUnwrap(dating["frontmatterKey"] as? [String: Any])
        return try XCTUnwrap(keys["firstClassKeepsASharedLessonCases"] as? [[String: Any]])
    }

    /// A course with two sections and the case's files and class pages.
    func makeCourse(for testCase: [String: Any]) throws -> (course: Course, sections: [Int]) {
        let fileManager: FileManager = FileManager.default
        let root: URL = fileManager.temporaryDirectory
            .appendingPathComponent("first-class-\(UUID().uuidString)", isDirectory: true)
        folders.append(root)
        let courseURL: URL = root.appendingPathComponent("courses/TEST", isDirectory: true)
        try fileManager.createDirectory(at: courseURL, withIntermediateDirectories: true)
        let configuration: [String: Any] = [
            "course_code": "TEST",
            "course_name": "Test",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        let course: Course = Course(code: "TEST", directoryURL: courseURL, configuration: loaded)

        let files: [String: [String: String]] = try XCTUnwrap(testCase["files"] as? [String: [String: String]])
        for (place, keys) in files {
            let url: URL = courseURL.appendingPathComponent(place)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var text: String = "---\ntitle: \(url.deletingPathExtension().lastPathComponent)\n"
            for key in keys.keys.sorted() {
                text += "\(key): \(keys[key] ?? "")\n"
            }
            text += "---\nThe lesson.\n"
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        var sections: [Int] = []
        let classes: [[String: Any]] = try XCTUnwrap(testCase["classes"] as? [[String: Any]])
        for page in classes {
            let place: String = try XCTUnwrap(page["page"] as? String)
            let firstPart: String = String(place.split(separator: "/")[0])
            let section: Int = try XCTUnwrap(Int(firstPart.dropFirst("section".count)))
            if !sections.contains(section) {
                sections.append(section)
            }
            let url: URL = courseURL.appendingPathComponent(place)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let holds = page["linkHolds"] as? String {
                try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: holds)
                continue
            }
            let created: String = try XCTUnwrap(page["created"] as? String)
            let says: String = page["says"] as? String ?? ""
            let title: String = url.deletingPathExtension().lastPathComponent
            try "---\ntitle: \(title)\npublish: true\ncreated: \(created)\n---\n\(says)\n"
                .write(to: url, atomically: true, encoding: .utf8)
        }
        return (course: course, sections: sections)
    }

    /// The case's place of the class page that owns `file` in a section, or
    /// nil when no numbered class owns it.
    func owningClass(of file: URL, among classPages: [ClassPageSummary], in course: Course) -> String? {
        guard let resolved = ResolvedFile.throughLinks(at: file) else {
            return nil
        }
        let owned: [ResolvedFile] = ClassPages.filesTheNumberedClassesOwn(among: classPages)
        if !owned.contains(resolved) {
            return nil
        }
        let numbered: [ClassPageSummary] = ClassInsertionPlanner.numberedClasses(among: classPages)
        for summary in numbered {
            if ResolvedFile.throughLinks(at: summary.fileURL) != resolved {
                continue
            }
            if !ClassPages.isTheFirstClassLeadingToItsFile(summary.fileURL, among: classPages) {
                continue
            }
            // The place in the course, whichever spelling of the temporary
            // folder (`/var` or `/private/var`) the list read it by.
            let path: String = summary.fileURL.path
            let marker: String = "/courses/TEST/"
            if let found = path.range(of: marker) {
                return String(path[found.upperBound...])
            }
            return path
        }
        return nil
    }

    // MARK: - The contract's cases, through the Mac's rule

    func testTheContractsOwnerCasesAreTheMacsRule() throws {
        let cases: [[String: Any]] = try FirstClassKeepsASharedLessonTests.contractCases()
        XCTAssertGreaterThanOrEqual(cases.count, 9)
        for testCase in cases {
            let name: String = testCase["name"] as? String ?? "?"
            let owned: Bool = try XCTUnwrap(testCase["ownedByANumberedClass"] as? Bool, name)
            let owners: [String: String] = try XCTUnwrap(testCase["owningClass"] as? [String: String], name)
            let made: (course: Course, sections: [Int]) = try makeCourse(for: testCase)
            let files: [String: Any] = try XCTUnwrap(testCase["files"] as? [String: Any])
            for section in made.sections {
                let classPages: [ClassPageSummary] = ClassPages.list(forSection: section, in: made.course)
                for place in files.keys {
                    let file: URL = made.course.directoryURL.appendingPathComponent(place)
                    let owner: String? = owningClass(of: file, among: classPages, in: made.course)
                    XCTAssertEqual(owner != nil, owned, "\(name), section \(section): \(place) owned")
                    XCTAssertEqual(owner, owners["section\(section)"], "\(name), section \(section): the owner")
                }
            }
        }
    }

    // MARK: - The links checklist

    /// The review's case: Day 1 is visible and says [[Lesson]]; Day 2 is a
    /// link to the hidden shared lesson, so the lesson's date is Day 2's.
    /// An offer that dates the lesson from Day 1 (the build of c7c97ddd6
    /// wrote one; any stale offer may) must not move it.
    func testPublishingFromTheChecklistNeverWritesAnotherClassesDateIntoAnOwnedLesson() throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        let course: Course = made.course
        let fileManager: FileManager = FileManager.default
        let classes: URL = ClassPages.folderURL(forSection: 1, in: course)
        let shared: URL = course.directoryURL.appendingPathComponent("Shared", isDirectory: true)
        try fileManager.createDirectory(at: shared, withIntermediateDirectories: true)
        let lesson: URL = shared.appendingPathComponent("Lesson.md")
        try "---\ntitle: Lesson\npublishForSection1: false\ncreatedSection1: 2026-09-10T07:00:00.000-0400\n---\n\nThe lesson.\n"
            .write(to: lesson, atomically: true, encoding: .utf8)
        try "---\ntitle: Unit 1, Day 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\n\nSee [[Lesson]].\n"
            .write(to: classes.appendingPathComponent("Unit 1, Day 1.md"), atomically: true, encoding: .utf8)
        try fileManager.createSymbolicLink(
            atPath: classes.appendingPathComponent("Unit 1, Day 2.md").path,
            withDestinationPath: "../../Shared/Lesson.md"
        )
        let index: URL = SectionIndexPointer.indexURL(forSection: 1, in: course)
        try "---\ntitle: Home\npublish: true\n---\n\n![[Unit 1, Day 1]]\n"
            .write(to: index, atomically: true, encoding: .utf8)

        let offer: LinksChecklistOffer = try LinksChecklistTests.offer(from: [[
            "place": "Shared/Lesson", "group": "fromAClass", "ticked": true, "step": 1,
            "claimedBy": "section1/All Classes/Unit 1, Day 1", "date": "2026-09-08", "why": "dated",
            "linkedFrom": ["section1/All Classes/Unit 1, Day 1"], "dependsOn": [String](),
        ]])
        let graph: AssistSectionGraph = AssistSectionGraph.read(forSection: 1, in: course, workspaceURL: made.root)
        let planned: (plan: AssistPublishPlan, outcome: LinksChecklistPublisher.Outcome) = LinksChecklistPublisher.plan(
            offer: offer, ticked: ["Shared/Lesson"], graph: graph,
            classPages: ClassPages.list(forSection: 1, in: course),
            forSection: 1, in: course, shownComingWith: []
        )
        var publishesTheLesson: Bool = false
        for change in planned.plan.changes {
            if ResolvedFile.throughLinks(at: change.page.fileURL) == ResolvedFile.throughLinks(at: lesson) {
                publishesTheLesson = true
            }
        }
        XCTAssertTrue(publishesTheLesson, "the ticked lesson is not published, so this tests nothing")
        for move in planned.plan.dateMoves {
            XCTAssertNotEqual(
                ResolvedFile.throughLinks(at: move.page.fileURL), ResolvedFile.throughLinks(at: lesson),
                "the checklist moves the lesson Day 2 owns to \(move.to.text), Day 1's day"
            )
        }
        XCTAssertEqual(planned.outcome.datedFromAClass, 0, "an owned lesson is counted as dated from a class")
    }
}
