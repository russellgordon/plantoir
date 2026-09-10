import XCTest
@testable import QuartzTeachers

/// Which folders the Marks checklist may OFFER — run from
/// `contracts/shared-rules.json` → `gradedFolders.choices` against a REAL
/// directory tree, because the rule is a walk and a walk over a fixture is not
/// a walk.
///
/// The failure being guarded is silent and permanent: the build counts a graded
/// folder at any depth, an absent `graded_folders` key means the historical rule
/// still applies, and the FIRST TICK freezes the pool. So a folder the checklist
/// fails to offer stops counting for marks from that tick onwards, and every
/// expectation it addressed reads as never evaluated.
///
/// Windows has run this same case list since 2026-09-06
/// (`Plantoir.Tests/GradedFolderChoicesTests.cs`); this side ran none of it
/// until now, which is what [issue #112] was for. A case proposed from either
/// platform now turns both suites red.
@MainActor
final class GradedFolderChoicesTests: XCTestCase {

    // MARK: - Stored properties

    /// One disposable root per test method, so two cases that both make a
    /// `Tasks` folder cannot see each other's tree.
    var root: URL = URL(fileURLWithPath: "/")

    // MARK: - Functions

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("graded-choices-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A course folder holding the given directories, and a configuration to
    /// go with it. Nothing here writes `course_config.json` into the course
    /// folder itself: a file is not a folder, and the walk must not offer one.
    @discardableResult
    private func makeCourse(
        named name: String,
        sharedFolders: [String] = [],
        perSectionFolders: [String] = [],
        gradedFolders: [String]? = nil,
        excludedItems: [String: [String]]? = nil,
        directories: [String] = []
    ) throws -> Course {
        let courseURL: URL = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
        for relative in directories {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent(relative), withIntermediateDirectories: true
            )
        }
        var values: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "shared_folders": sharedFolders,
            "per_section_folders": perSectionFolders,
        ]
        if let gradedFolders {
            values["graded_folders"] = gradedFolders
        }
        if let excludedItems {
            values["excluded_items"] = excludedItems
        }
        let configuration: CourseConfiguration = CourseConfiguration(values: values, lastSavedData: Data())
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: configuration)
    }

    private static func choicesRule() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let gradedFolders: [String: Any] = try XCTUnwrap(all["gradedFolders"] as? [String: Any])
        return try XCTUnwrap(gradedFolders["choices"] as? [String: Any])
    }

    // MARK: - The contract's own cases

    func testTheOfferedPoolMatchesTheContract() throws {
        let cases: [[String: Any]] = try XCTUnwrap(
            try GradedFolderChoicesTests.choicesRule()["cases"] as? [[String: Any]]
        )
        XCTAssertGreaterThanOrEqual(
            cases.count, 13,
            "The contract lost graded-folder-choice cases: \(cases.count) present, 13 expected at least."
        )

        var index: Int = 0
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let course: Course = try makeCourse(
                named: "case\(index)",
                sharedFolders: try XCTUnwrap(testCase["sharedFolders"] as? [String]),
                perSectionFolders: try XCTUnwrap(testCase["perSectionFolders"] as? [String]),
                excludedItems: testCase["excludedItems"] as? [String: [String]],
                directories: try XCTUnwrap(testCase["directories"] as? [String])
            )
            index += 1

            let offered: [String] = GradedFolderChoices.choices(
                for: course.configuration, courseDirectory: course.directoryURL
            )
            XCTAssertEqual(offered, try XCTUnwrap(testCase["expect"] as? [String]), name)
        }
    }

    /// The acceptance test the visible list alone would not have caught: what
    /// the teacher's first tick actually FREEZES is derived from the same list
    /// the checklist offers, so a nested folder survives it.
    func testTheFrozenPoolIsMaterialisedFromTheSameListTheChecklistOffers() throws {
        let course: Course = try makeCourse(
            named: "nested",
            sharedFolders: ["Concepts", "Portfolios"],
            perSectionFolders: ["All Classes"],
            directories: ["Concepts", "Portfolios", "Portfolios/Tasks"]
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        XCTAssertTrue(view.gradedFolderChoices.contains("Tasks"))
        XCTAssertNil(course.configuration.gradedFolders)
        XCTAssertTrue(view.gradedFoldersBinding.wrappedValue.contains("Tasks"))
    }

    /// The whole of issue #79, through the interface: a folder the teacher has
    /// REMOVED from the course does not come back into the Marks checklist on
    /// the next redraw, and the pool does not name it either.
    ///
    /// Both halves are needed and neither stands in for the other.
    /// `dropFromMarksPool` has always taken the name out of the pool; the
    /// folder was still sitting on disk, so the walk offered it back UNTICKED,
    /// and ticking it wrote a `graded_folders` naming a folder `excluded_items`
    /// tells the build to skip — a pool matching nothing the site publishes,
    /// while the settings claim something counts.
    ///
    /// The removal is played in the order Course Settings really does it:
    /// `exclude` first, then `dropFromMarksPool`. That order matters for a
    /// course that has NEVER been asked — by the time the pool is touched the
    /// folder is no longer among the choices, so nothing is materialised and
    /// the key stays absent, which is the right answer rather than an
    /// oversight. This course has been asked, so the drop is unambiguous.
    func testAFolderRemovedFromTheCourseLeavesTheChecklistAndThePool() throws {
        let course: Course = try makeCourse(
            named: "removed",
            sharedFolders: ["Concepts", "Tasks"],
            gradedFolders: ["Tasks"],
            directories: ["Concepts", "Tasks", "Tasks/Unit 1"]
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)
        XCTAssertEqual(view.gradedFolderChoices, ["Concepts", "Tasks", "Unit 1"])

        // What Course Settings does when the teacher confirms the removal: the
        // list editor's own binding takes the name out of `shared_folders`,
        // and its `onRemove` excludes it and drops it from the pool. The
        // folder itself stays on disk, which is the whole difficulty — before
        // this change the walk handed it straight back.
        var remaining: [String] = []
        for folder in course.configuration.sharedFolders where folder != "Tasks" {
            remaining.append(folder)
        }
        course.configuration.sharedFolders = remaining
        course.configuration.exclude("Tasks", inScope: FolderScope.shared.exclusionKey)
        view.dropFromMarksPool("Tasks")

        // Not offered back — and neither is anything inside it, because
        // nothing under a removed folder reaches the site either.
        XCTAssertEqual(view.gradedFolderChoices, ["Concepts"])
        XCTAssertEqual(course.configuration.gradedFolders, [])
    }

    // MARK: - The walk itself

    func testACourseFolderThatIsNotThereOffersOnlyWhatTheCourseDeclares() throws {
        let course: Course = try makeCourse(named: "declared-only", sharedFolders: ["Tasks"])
        let missing: URL = root.appendingPathComponent("not-there")

        XCTAssertEqual(GradedFolderChoices.nestedFolderNames(inCourseDirectory: missing), [])
        XCTAssertEqual(
            GradedFolderChoices.choices(for: course.configuration, courseDirectory: missing), ["Tasks"]
        )
    }

    func testFilesAreNotOfferedOnlyFolders() throws {
        let course: Course = try makeCourse(named: "files", directories: ["Tasks"])
        try Data("x".utf8).write(to: course.directoryURL.appendingPathComponent("Key Links.md"))
        try Data("x".utf8).write(
            to: course.directoryURL.appendingPathComponent("Tasks").appendingPathComponent("Quiz.md")
        )

        XCTAssertEqual(
            GradedFolderChoices.nestedFolderNames(inCourseDirectory: course.directoryURL), ["Tasks"]
        )
    }

    func testSectionFoldersAreRecognisedByNameAndNumberAlone() {
        XCTAssertTrue(GradedFolderChoices.isSectionFolder("section1"))
        XCTAssertTrue(GradedFolderChoices.isSectionFolder("section12"))
        XCTAssertTrue(GradedFolderChoices.isSectionFolder("SECTION3"))
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("section"))
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("sections"))
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("section1a"))
        // The digits are digits and nothing else: `Int("-1")` is not nil, so
        // the reading this replaced counted `section-1` as a section folder
        // and did not offer a teacher's own folder of that name.
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("section-1"))
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("section 1"))
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("Sectional Tasks"))
    }

    /// A folder marked hidden by the platform, rather than merely named with a
    /// dot. The contract asks for both; `.skipsHiddenFiles` is what covers the
    /// second, and a test is what keeps it there.
    func testAFolderHiddenByAttributeIsNotOffered() throws {
        let course: Course = try makeCourse(named: "hidden", directories: ["Tasks", "Bookkeeping"])
        var bookkeeping: URL = course.directoryURL.appendingPathComponent("Bookkeeping")
        var values: URLResourceValues = URLResourceValues()
        values.isHidden = true
        try bookkeeping.setResourceValues(values)

        XCTAssertEqual(
            GradedFolderChoices.nestedFolderNames(inCourseDirectory: course.directoryURL), ["Tasks"]
        )
    }

    /// A symbolic link is neither offered nor walked into: what it points at is
    /// not part of this course, and following one is how a walk finds its way
    /// into a loop.
    func testASymbolicLinkIsNotFollowed() throws {
        let course: Course = try makeCourse(named: "linked", directories: ["Tasks"])
        let away: URL = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(
            at: away.appendingPathComponent("Linked Tasks"), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: course.directoryURL.appendingPathComponent("Shortcut"), withDestinationURL: away
        )

        XCTAssertEqual(
            GradedFolderChoices.nestedFolderNames(inCourseDirectory: course.directoryURL), ["Tasks"]
        )
    }

    /// A teacher's own lowercase `media` is theirs, and is offered: the skip
    /// list is matched exactly, case included, on both platforms.
    func testATeachersOwnLowercaseMediaFolderIsStillOffered() throws {
        let course: Course = try makeCourse(named: "case-sensitive", directories: ["media"])

        XCTAssertEqual(
            GradedFolderChoices.nestedFolderNames(inCourseDirectory: course.directoryURL), ["media"]
        )
    }

    // MARK: - The numbers both apps must share

    func testTheDepthCapIsTheOneTheContractNames() throws {
        let walk: [String: Any] = try XCTUnwrap(
            try GradedFolderChoicesTests.choicesRule()["walk"] as? [String: Any]
        )
        XCTAssertEqual(walk["maxDepth"] as? Int, GradedFolderChoices.maxDepth)
    }

    func testTheSkippedFoldersAreTheOnesTheContractNames() throws {
        let walk: [String: Any] = try XCTUnwrap(
            try GradedFolderChoicesTests.choicesRule()["walk"] as? [String: Any]
        )
        let named: [String] = try XCTUnwrap(walk["skipped"] as? [String])
        XCTAssertEqual(Set(named), GradedFolderChoices.skippedFolders)
    }
}
