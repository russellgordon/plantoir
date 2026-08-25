import XCTest
@testable import QuartzTeachers

/// The class-folder rule, run against the SHARED contract.
///
/// The cases are deserialised from `contracts/class-planning.json` →
/// `classFolder`, never retyped — the same data `scripts/test_class_folder.py`
/// and the Windows suite run against their own implementations. That is the
/// whole point: this rule used to exist four times and disagree, and the
/// build's disagreement silently changed the Curriculum Coverage map from
/// "pages the course teaches" to "every published page".
@MainActor
final class ClassFolderContractTests: XCTestCase {

    // MARK: - Stored properties

    private var contract: [String: Any] = [:]

    // MARK: - Functions

    override func setUpWithError() throws {
        // Located the way ClassPlanningContractTests locates the same file:
        // up from #filePath to the repository root.
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/class-planning.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        contract = try XCTUnwrap(all["classFolder"] as? [String: Any],
                                 "contracts/class-planning.json has no classFolder section")
    }

    func testNamingCasesFromTheContract() throws {
        let naming: [String: Any] = try XCTUnwrap(contract["naming"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(naming["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5, "the contract lost naming cases")
        for testCase in cases {
            let name: String = (testCase["name"] as? String) ?? "unnamed"
            let folders: [String] = (testCase["perSectionFolders"] as? [String]) ?? []
            let expected: String = try XCTUnwrap(testCase["expect"] as? String)
            XCTAssertEqual(
                ClassFolder.name(inPerSectionFolders: folders), expected,
                "\(name): \((testCase["why"] as? String) ?? "")"
            )
        }
    }

    func testIsClassPageCasesFromTheContract() throws {
        let rule: [String: Any] = try XCTUnwrap(contract["isClassPage"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12, "the contract lost isClassPage cases")
        for testCase in cases {
            let name: String = (testCase["name"] as? String) ?? "unnamed"
            let path: String = try XCTUnwrap(testCase["path"] as? String)
            let folders: [String] = try XCTUnwrap(testCase["classFolders"] as? [String])
            let expected: Bool = try XCTUnwrap(testCase["expect"] as? Bool)
            XCTAssertEqual(
                ClassFolder.isClassPage(relativePath: path, classFolders: folders), expected,
                "\(name): \((testCase["why"] as? String) ?? "")"
            )
        }
    }

    func testMembershipCasesFromTheContract() throws {
        let rule: [String: Any] = try XCTUnwrap(contract["membership"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 4, "the contract lost membership cases")
        for testCase in cases {
            let name: String = (testCase["name"] as? String) ?? "unnamed"
            let folders: [String] = (testCase["perSectionFolders"] as? [String]) ?? []
            let expected: [String] = try XCTUnwrap(testCase["expect"] as? [String])
            XCTAssertEqual(
                ClassFolder.names(inPerSectionFolders: folders), expected,
                "\(name): \((testCase["why"] as? String) ?? "")"
            )
        }
    }

    /// Defence in depth, and labelled as such: under segment EQUALITY these
    /// could not match anyway. The test exists so a future change to prefix or
    /// substring matching fails here rather than quietly reclassifying content
    /// that ships in the example payloads.
    func testAPageIsNeverALessonBecauseOfItsName() {
        let pages: [String] = [
            "Setup/How This Class Works.md",
            "Setup/Our Classroom Norms.md",
            "Curriculum/B3. Connections Beyond the Classroom.md",
            "All Classes.md",
        ]
        for page in pages {
            XCTAssertFalse(
                ClassFolder.isClassPage(relativePath: page, classFolders: ["All Classes"]),
                "\(page) is not a lesson — a page is never one because of its NAME"
            )
        }
    }

    /// The bug an adversarial review found still live on THIS platform.
    ///
    /// `AssistSectionPage.relativePath` is relative to the working folder — and
    /// is the FULL ABSOLUTE PATH when `workspaceURL` is nil, which
    /// `SectionIndexPointer.repointIndex` passes. Asking the class-page
    /// question of that string meant a teacher whose working folder was named
    /// for classes made every page in every course a lesson.
    ///
    /// The rule itself is a pure segment matcher and cannot know what sits
    /// above the content root, so what protects it is the page carrying
    /// `pathWithinSection`. That is what this exercises — a working folder
    /// called "All Classes", which under the old code made every page a class
    /// page.
    func testAWorkingFolderNamedForClassesCannotMakeEveryPageALesson() throws {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("All Classes")
            .appendingPathComponent("class-folder-\(UUID().uuidString)")
        let courseURL: URL = root.appendingPathComponent("courses/ICS3U")
        let sectionURL: URL = courseURL.appendingPathComponent("section1")
        try FileManager.default.createDirectory(
            at: sectionURL.appendingPathComponent("Concepts"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration: [String: Any] = [
            "course_code": "ICS3U", "course_name": "Introduction to Computer Science",
            "section_numbers": [1], "num_sections": 1,
            "per_section_folders": ["All Classes"], "per_section_files": [],
        ]
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: configURL)
        let course: Course = Course(
            code: "ICS3U", directoryURL: courseURL,
            configuration: try CourseConfiguration(contentsOf: configURL)
        )

        let lesson: URL = sectionURL.appendingPathComponent("Concepts/Loops.md")
        let within: String = AssistSectionGraph.pathWithinSection(
            of: lesson, forSection: 1, in: course
        )
        XCTAssertEqual(within, "Concepts/Loops.md",
                       "everything above the section folder must be stripped")
        XCTAssertFalse(
            ClassFolder.isClassPage(relativePath: within, classFolders: ClassFolder.names(for: course)),
            "a working folder named 'All Classes' must not make Loops.md a lesson"
        )

        let realClass: URL = sectionURL.appendingPathComponent("All Classes/Unit 1, Day 1.md")
        XCTAssertTrue(ClassFolder.isClassPage(
            relativePath: AssistSectionGraph.pathWithinSection(of: realClass, forSection: 1, in: course),
            classFolders: ClassFolder.names(for: course)
        ))
    }

    func testAWindowsPathSeparatorIsUnderstood() {
        XCTAssertTrue(ClassFolder.isClassPage(
            relativePath: "All Classes\\Unit 1, Day 1.md", classFolders: ["All Classes"]))
    }
}
