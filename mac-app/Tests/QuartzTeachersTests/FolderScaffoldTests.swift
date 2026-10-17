import XCTest
@testable import QuartzTeachers

/// A folder added in Course Settings after the course was made starts with
/// its `index.md` and a `_DUPLICATE ME.md`, the way a folder made with the
/// course does (GitHub issue #506).
///
/// The texts themselves are `contracts/course-management.json` →
/// `foldersAddedLater`, run by
/// `CourseManagementContractTests.testEveryFolderAddedLaterCase`. These tests
/// go through the page's own seam, `noticeAfterFolderChange`, so they check
/// what a teacher's click does: which folders get pages, which do not, and
/// what the trail says.
@MainActor
final class FolderScaffoldTests: XCTestCase {

    // MARK: - Stored properties

    /// Where this test's trail lines go, and the store that was there before,
    /// so an added folder's line does not land in the real trail.
    var trailFolderURL: URL?
    var previousTrailStore: ProblemReportStore?

    /// The course folder each test makes, removed afterwards.
    var rootURL: URL?

    // MARK: - Functions

    override func setUp() async throws {
        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder-scaffold-trail-\(UUID().uuidString)", isDirectory: true)
        trailFolderURL = folderURL
        previousTrailStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder-scaffold-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        if let previousTrailStore {
            ActivityTrail.store = previousTrailStore
        }
        if let trailFolderURL {
            try? FileManager.default.removeItem(at: trailFolderURL)
        }
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    /// A two-section course with a curriculum folder holding `curriculumPages`.
    private func makeCourse(curriculumPages: [String]) throws -> Course {
        let root: URL = try XCTUnwrap(rootURL)
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        let fileManager: FileManager = FileManager.default
        for folder in ["section1", "section2", "Concepts", "Curriculum"] {
            try fileManager.createDirectory(
                at: courseURL.appendingPathComponent(folder), withIntermediateDirectories: true
            )
        }
        for page in curriculumPages {
            try Data("---\ntitle: \(page)\n---\n".utf8).write(
                to: courseURL.appendingPathComponent("Curriculum").appendingPathComponent(page)
            )
        }
        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "shared_folders": ["Concepts", "Curriculum"],
            "per_section_folders": ["All Classes"],
            "per_section_files": ["index.md"],
            "curriculum_folders": ["Curriculum"],
            "include_curriculum_coverage": true,
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
    }

    private func text(at url: URL) -> String? {
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - A shared folder

    /// Must fail on the code before #506: the folder was made EMPTY.
    func testASharedFolderAddedInSettingsGetsItsIndexAndAPageToDuplicate() throws {
        let course: Course = try makeCourse(curriculumPages: ["A1.1.md", "A1.2.md"])
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let notice: String? = view.noticeAfterFolderChange("Labs", change: .added, scope: .shared)

        XCTAssertEqual(notice, SpecialNames.addCreatesTheFolderMessage(name: "Labs"))
        let folder: URL = course.directoryURL.appendingPathComponent("Labs")
        let index: String = try XCTUnwrap(text(at: folder.appendingPathComponent("index.md")), "no index.md")
        XCTAssertTrue(index.hasPrefix("---\ntitle: Labs\ncreatedSection1: "), index)
        XCTAssertTrue(index.contains("\npublishForSection1: true\n"), index)
        XCTAssertTrue(index.contains("\npublishForSection2: true\n"), index)
        XCTAssertTrue(index.contains("This is the **Labs** folder."), index)

        let template: String = try XCTUnwrap(
            text(at: folder.appendingPathComponent("_DUPLICATE ME.md")), "no _DUPLICATE ME.md"
        )
        XCTAssertTrue(template.contains("\npublishForSection1: false\n"), template)
        XCTAssertTrue(template.contains("\npublishForSection2: false\n"), template)
        XCTAssertFalse(template.contains("__CREATED__"), "the date was not filled in")
        XCTAssertFalse(template.contains("\npublish: false\n"), "a shared template keeps one key per section")
        XCTAssertTrue(template.contains("![[A1.1]]"), "the course has A1.1, so the connection stays")
        XCTAssertFalse(template.contains("%%curriculum-start%%"), "the markers go")

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("created the folder Labs in ICS3U (shared_folders), with its index page and a page to duplicate"),
            trail
        )
    }

    /// A folder already on disk is the teacher's: re-adding its name puts
    /// nothing in it, and is not reported as a folder made.
    func testReAddingAFolderThatIsAlreadyThereWritesNothingInIt() throws {
        let course: Course = try makeCourse(curriculumPages: [])
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let notice: String? = view.noticeAfterFolderChange("Concepts", change: .added, scope: .shared)

        XCTAssertNil(notice)
        let contents: [String] = try FileManager.default.contentsOfDirectory(
            atPath: course.directoryURL.appendingPathComponent("Concepts").path
        )
        XCTAssertEqual(contents, [], "nothing is put into a folder that was already there")
    }

    /// No specific expectation in the curriculum folder: the connection would
    /// embed a page that is not there, so it goes whole.
    func testWithNoExpectationPagesTheCurriculumConnectionGoes() throws {
        let course: Course = try makeCourse(curriculumPages: ["index.md", "A1.md"])
        let view: CourseSettingsView = CourseSettingsView(course: course)

        _ = view.noticeAfterFolderChange("Readings", change: .added, scope: .shared)

        let template: String = try XCTUnwrap(text(at: course.directoryURL
            .appendingPathComponent("Readings").appendingPathComponent("_DUPLICATE ME.md")))
        XCTAssertFalse(template.contains("Curriculum connection"), template)
        XCTAssertFalse(template.contains("[[A1.1]]"), template)
    }

    // MARK: - A per-section folder

    /// Each section that did not have the folder gets both pages, with plain
    /// keys; a section that already had it is left exactly as it was.
    func testAPerSectionFolderGetsItsPagesOnlyWhereItWasMade() throws {
        let course: Course = try makeCourse(curriculumPages: ["D1.1.md", "D1.2.md"])
        let teachersFolder: URL = course.directoryURL
            .appendingPathComponent("section2").appendingPathComponent("Exit Tickets")
        try FileManager.default.createDirectory(at: teachersFolder, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: teachersFolder.appendingPathComponent("Monday.md"))
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let notice: String? = view.noticeAfterFolderChange("Exit Tickets", change: .added, scope: .perSection)

        XCTAssertEqual(notice, SpecialNames.addCreatesTheFolderMessage(name: "Exit Tickets"))
        let made: URL = course.directoryURL
            .appendingPathComponent("section1").appendingPathComponent("Exit Tickets")
        let index: String = try XCTUnwrap(text(at: made.appendingPathComponent("index.md")), "no index.md")
        XCTAssertTrue(index.hasPrefix("---\ntitle: Exit Tickets\ncreated: "), index)
        XCTAssertTrue(index.contains("\npublish: true\n---\n"), index)
        let template: String = try XCTUnwrap(text(at: made.appendingPathComponent("_DUPLICATE ME.md")))
        XCTAssertTrue(template.contains("\npublish: false\ncreated: "), template)
        XCTAssertTrue(template.contains("![[D1.1]]"), "no A1.1 here, so the embed points at the first expectation")

        let untouched: [String] = try FileManager.default.contentsOfDirectory(atPath: teachersFolder.path)
        XCTAssertEqual(untouched, ["Monday.md"], "a section that already had the folder gets nothing")
    }

    // MARK: - What the trail says

    /// The "folder created" line names what was put inside the folder, and
    /// only that — including the template written alone, when the folder's
    /// `index.md` appeared between the folder being made and the pages being
    /// written (#506's review, N2).
    func testTheTrailLineNamesWhatWasWritten() {
        let base: String = "created the folder Labs in ICS3U (shared_folders)"
        let expectations: [(outcome: FolderScaffold.Outcome, ending: String)] = [
            (FolderScaffold.Outcome(foldersCreated: 1, indexPagesWritten: 1, templatesWritten: 1),
             ", with its index page and a page to duplicate"),
            (FolderScaffold.Outcome(foldersCreated: 1, indexPagesWritten: 1, templatesWritten: 0),
             ", with its index page"),
            (FolderScaffold.Outcome(foldersCreated: 1, indexPagesWritten: 0, templatesWritten: 1),
             ", with a page to duplicate"),
            (FolderScaffold.Outcome(foldersCreated: 1, indexPagesWritten: 0, templatesWritten: 0),
             ""),
        ]
        for expectation in expectations {
            XCTAssertEqual(
                CourseSettingsView.folderCreatedTrailLine(
                    name: "Labs", courseCode: "ICS3U", scope: .shared, outcome: expectation.outcome
                ),
                base + expectation.ending
            )
        }
    }

    /// A folder whose name YAML would misread gets a quoted title, so the
    /// build can read its index page (#506's review, S1).
    func testAFolderNamedWithAColonGetsAQuotedTitle() throws {
        let course: Course = try makeCourse(curriculumPages: [])
        let view: CourseSettingsView = CourseSettingsView(course: course)

        _ = view.noticeAfterFolderChange("Unit: One", change: .added, scope: .shared)

        let index: String = try XCTUnwrap(text(at: course.directoryURL
            .appendingPathComponent("Unit: One").appendingPathComponent("index.md")))
        XCTAssertTrue(index.hasPrefix("---\ntitle: \"Unit: One\"\n"), index)
    }

    // MARK: - The template is every skeleton's

    /// The template a folder added later gets is the generic family's, and
    /// that is only right while every skeleton family carries the SAME page.
    /// All of them, in the repository and in the bundle, byte for byte the
    /// `foldersAddedLater.templateSource` file.
    func testEveryBundledSkeletonTemplateIsTheContractsTemplateSource() throws {
        let repository: URL = FolderIdentityTests.repositoryRoot()
        let contractURL: URL = repository.appendingPathComponent("contracts/course-management.json")
        let contract: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: contractURL)) as? [String: Any]
        )
        let section: [String: Any] = try XCTUnwrap(contract["foldersAddedLater"] as? [String: Any])
        let source: String = try XCTUnwrap(section["templateSource"] as? String)
        let expected: Data = try Data(contentsOf: repository.appendingPathComponent(source))

        let bundledSkeletons: URL = try XCTUnwrap(Bundle.main.resourceURL)
            .appendingPathComponent("support/skeletons")
        let repositorySkeletons: URL = repository.appendingPathComponent("support/skeletons")
        var counts: [Int] = []
        for root in [repositorySkeletons, bundledSkeletons] {
            var count: Int = 0
            let enumerator: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil
            )
            while let url = enumerator?.nextObject() as? URL {
                if url.lastPathComponent != FolderScaffold.templateFileName {
                    continue
                }
                count += 1
                XCTAssertEqual(try Data(contentsOf: url), expected, "\(url.path) is not the template source")
            }
            counts.append(count)
        }
        XCTAssertGreaterThan(counts[0], 0, "no skeleton templates found in the repository")
        XCTAssertEqual(counts[1], counts[0], "the bundle carries a different number of templates")
        let appsTemplate: String = try XCTUnwrap(FolderScaffold.bundledTemplate(), "the app finds no template")
        XCTAssertEqual(Data(appsTemplate.utf8), expected, "the app's own template is not the template source")
    }
}
