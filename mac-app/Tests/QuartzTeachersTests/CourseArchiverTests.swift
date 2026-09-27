import XCTest
@testable import QuartzTeachers

/// Removing a course or section must ARCHIVE it, never destroy it.
final class CourseArchiverTests: XCTestCase {

    // MARK: - Functions

    /// Builds a courses/ directory holding one two-section course.
    @MainActor
    func makeCourse() throws -> (course: Course, coursesURL: URL) {
        let coursesURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cq4t-archive-\(UUID().uuidString)")
            .appendingPathComponent("courses")
        let courseURL: URL = coursesURL.appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: courseURL.appendingPathComponent("section2"), withIntermediateDirectories: true)
        try Data("# lesson\n".utf8).write(to: courseURL.appendingPathComponent("section1/index.md"))
        try Data("# lesson two\n".utf8).write(to: courseURL.appendingPathComponent("section2/index.md"))

        let values: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Intro to Comp Sci",
            "section_numbers": [1, 2],
            "num_sections": 2,
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: values)
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))

        let configuration: CourseConfiguration = CourseConfiguration(values: values, lastSavedData: data)
        let course: Course = Course(code: "ICS3U", directoryURL: courseURL, configuration: configuration)
        return (course: course, coursesURL: coursesURL)
    }

    @MainActor
    func testRemovingASectionArchivesItAndUpdatesTheCourse() async throws {
        let fixture = try makeCourse()
        let archiveURL: URL = try await CourseArchiver.archiveAndRemoveSection(
            2,
            from: fixture.course,
            coursesDirectoryURL: fixture.coursesURL
        )

        // Archived…
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path), "An archive should be written")
        XCTAssertTrue(archiveURL.path.contains("_backups/ICS3U"), "Archives live in _backups/<CODE>: \(archiveURL.path)")
        let archiveSize: Int = (try Data(contentsOf: archiveURL)).count
        XCTAssertGreaterThan(archiveSize, 0, "The archive should have contents")

        // …removed from the working folder…
        let sectionPath: String = fixture.course.sectionDirectoryURL(forSection: 2).path
        XCTAssertFalse(FileManager.default.fileExists(atPath: sectionPath), "The section folder should be gone")

        // …and no longer listed, on disk as well as in memory.
        XCTAssertEqual(fixture.course.sectionNumbers, [1])
        let savedData: Data = try Data(contentsOf: fixture.course.configFileURL)
        let saved: [String: Any] = (try JSONSerialization.jsonObject(with: savedData)) as? [String: Any] ?? [:]
        XCTAssertEqual(saved["num_sections"] as? Int, 1)

        // The other section is untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.course.sectionDirectoryURL(forSection: 1).path))
    }

    @MainActor
    func testRemovingACourseArchivesTheWholeFolder() async throws {
        let fixture = try makeCourse()
        let archiveURL: URL = try await CourseArchiver.archiveAndRemoveCourse(
            fixture.course,
            coursesDirectoryURL: fixture.coursesURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.course.directoryURL.path), "The course folder should be gone")

        // The archive must survive INSIDE the courses folder, so the
        // teacher can find it (and the scripts ignore _backups).
        XCTAssertTrue(archiveURL.path.contains("_backups"))
    }
}
