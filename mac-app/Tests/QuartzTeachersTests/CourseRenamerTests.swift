import XCTest
@testable import QuartzTeachers

/// Renaming a course, beyond what `contracts/course-management.json`
/// already pins.
///
/// The contract carries the RULE (what a code may be) and the EFFECTS (what
/// renaming touches and what it refuses to touch), because both apps have to
/// agree on those. What is here is the mac's own care: the failures that
/// must leave nothing half-done, and the sentence a teacher reads when
/// renaming had a consequence beyond itself.
@MainActor
final class CourseRenamerTests: XCTestCase {

    // MARK: - Stored properties

    var coursesURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Functions

    override func setUp() {
        super.setUp()
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("renamer-\(UUID().uuidString)")
        coursesURL = root.appendingPathComponent("courses")
        try? FileManager.default.createDirectory(at: coursesURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A course on disk with one section, ready to be renamed.
    func makeCourse(code: String) throws -> Course {
        let courseURL: URL = coursesURL.appendingPathComponent(code)
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        let values: [String: Any] = [
            "course_code": code,
            "course_name": "A Course",
            "section_numbers": [1],
            "num_sections": 1,
        ]
        try JSONSerialization.data(withJSONObject: values).write(to: configURL)
        return Course(
            code: code,
            directoryURL: courseURL,
            configuration: try CourseConfiguration(contentsOf: configURL)
        )
    }

    // MARK: - Refusals

    /// The folder is checked, not just the list of courses the app knows
    /// about. A folder with no settings in it is invisible to the sidebar
    /// but very much in the way of a move.
    func testRenamingOntoAFolderThatIsAlreadyThereIsRefused() throws {
        let course: Course = try makeCourse(code: "ICS3U")
        try FileManager.default.createDirectory(
            at: coursesURL.appendingPathComponent("ICS4U"), withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try CourseRenamer.rename(
                course, to: "ICS4U", coursesDirectoryURL: coursesURL, existingCodes: ["ICS3U"],
                runner: SilentLaunchControl()
            )
        ) { error in
            XCTAssertEqual(
                (error as? CourseRenamer.Problem)?.errorDescription,
                "There is already something called ICS4U in this working folder."
            )
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: course.directoryURL.path),
            "a refused rename leaves the course exactly where it was"
        )
        XCTAssertEqual(course.configuration.courseCode, "ICS3U", "and its settings untouched")
    }

    /// A code the rule refuses never reaches the file system, and the reason
    /// a teacher reads is the rule's own sentence rather than a second one
    /// written here.
    ///
    /// The refused example is `ICS4U!` rather than the `ICS-4U` it used to
    /// be: dashes became legal on 2026-08-23, because British Columbia's
    /// course codes contain them. What this test is actually about is that
    /// the reason a teacher reads comes off `CourseCodeRule` rather than
    /// being written a second time here, so any still-refused character
    /// serves.
    func testAnUnusableCodeIsRefusedInTheRulesOwnWords() throws {
        let course: Course = try makeCourse(code: "ICS3U")

        XCTAssertThrowsError(
            try CourseRenamer.rename(
                course, to: "ICS4U!", coursesDirectoryURL: coursesURL, existingCodes: ["ICS3U"],
                runner: SilentLaunchControl()
            )
        ) { error in
            XCTAssertEqual(
                (error as? CourseRenamer.Problem)?.errorDescription,
                CourseCodeRule.problem("ICS4U!", existingCodes: ["ICS3U"])
            )
        }
    }

    /// Pressing Return without changing anything, or changing only the
    /// capitalisation, is a teacher changing their mind — not an error, and
    /// not a move.
    func testRenamingToTheSameCodeDoesNothingAtAll() throws {
        let course: Course = try makeCourse(code: "ICS3U")

        for typed in ["ICS3U", "ics3u", "  ICS3U  ", ""] {
            let outcome: CourseRenamer.Outcome = try CourseRenamer.rename(
                course, to: typed, coursesDirectoryURL: coursesURL, existingCodes: ["ICS3U"],
                runner: SilentLaunchControl()
            )
            XCTAssertEqual(outcome.newCode, "ICS3U", "typed “\(typed)”")
            XCTAssertTrue(outcome.isQuiet, "typed “\(typed)”")
            XCTAssertTrue(FileManager.default.fileExists(atPath: course.directoryURL.path))
        }
    }

    // MARK: - What the teacher is told

    /// Nothing at all, in the ordinary case. A teacher who has just watched
    /// the row change does not need an alert to confirm it.
    func testAnOrdinaryRenameSaysNothing() {
        let outcome = CourseRenamer.Outcome(
            newCode: "ICS4U", stoppedScheduledSections: [], unstoppedScheduledSections: []
        )
        XCTAssertNil(CourseRenamer.noticeAfterRenaming(outcome))
    }

    func testTheNoticeNamesTheSectionsAndReadsAsEnglish() {
        let one = CourseRenamer.Outcome(
            newCode: "ICS4U", stoppedScheduledSections: [1], unstoppedScheduledSections: []
        )
        let notice: CourseRenamer.Notice = try! XCTUnwrap(CourseRenamer.noticeAfterRenaming(one))
        XCTAssertEqual(notice.title, "Scheduled publishing was turned off")
        XCTAssertTrue(notice.message.hasPrefix("Section 1 of ICS4U was set to publish on its own."), notice.message)

        let several = CourseRenamer.Outcome(
            newCode: "ICS4U", stoppedScheduledSections: [1, 2, 4], unstoppedScheduledSections: []
        )
        let plural: CourseRenamer.Notice = try! XCTUnwrap(CourseRenamer.noticeAfterRenaming(several))
        XCTAssertTrue(
            plural.message.hasPrefix("Sections 1, 2 and 4 of ICS4U were set to publish on their own."),
            plural.message
        )
    }

    /// A scheduled publish that could NOT be turned off is a warning rather
    /// than news, and the title says so — an alert headed "Renamed" would be
    /// true of both cases and useful for neither.
    func testAScheduledPublishThatSurvivesIsHeadedAsAWarning() {
        let outcome = CourseRenamer.Outcome(
            newCode: "ICS4U", stoppedScheduledSections: [], unstoppedScheduledSections: [2]
        )
        let notice: CourseRenamer.Notice = try! XCTUnwrap(CourseRenamer.noticeAfterRenaming(outcome))
        XCTAssertEqual(notice.title, "A scheduled publish may still run")
        XCTAssertTrue(notice.message.contains("may still try to publish under the old name"), notice.message)
    }

    func testSectionsAreListedTheWayEnglishListsThem() {
        XCTAssertEqual(CourseRenamer.listed([1]), "Section 1")
        XCTAssertEqual(CourseRenamer.listed([1, 2]), "Sections 1 and 2")
        XCTAssertEqual(CourseRenamer.listed([1, 2, 4]), "Sections 1, 2 and 4")
    }
}
