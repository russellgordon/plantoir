import XCTest
@testable import QuartzTeachers

/// Putting right the folder problems that can be put right.
@MainActor
final class SiteHealthRepairTests: XCTestCase {

    // MARK: - Functions

    private func makeCourse() throws -> (URL, Course) {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("health-repair-\(UUID().uuidString)")
        let courseURL: URL = root.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
        let configuration: [String: Any] = [
            "course_code": "ICS3U", "course_name": "Introduction to Computer Science",
            "section_numbers": [1], "num_sections": 1,
            "shared_folders": [], "per_section_folders": ["All Classes"],
            "shared_files": [], "per_section_files": [],
        ]
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: configURL)
        return (root, Course(
            code: "ICS3U", directoryURL: courseURL,
            configuration: try CourseConfiguration(contentsOf: configURL)
        ))
    }

    private func finding(_ name: String, fixable: Bool, section: Int = 1) -> SiteHealthFinding {
        return SiteHealthFinding(
            name: name, sentence: "Something is wrong.", detail: "More about it.",
            fixable: fixable, course: "ICS3U", section: section
        )
    }

    /// The line that matters most: a fix must restore the FEATURE, not merely
    /// satisfy the check. Recreating an empty curriculum folder would silence
    /// the warning and leave the map missing.
    func testTheUnfixableFindingsAreNeverOffered() {
        for name in ["curriculumCoverageFoundNothing", "courseTeachesNothing",
                     "handWrittenCoveragePage"] {
            XCTAssertFalse(
                SiteHealthRepair.canRepair(finding(name, fixable: true)),
                "\(name) must never grow a fix button, even if the toolchain calls it fixable"
            )
        }
        XCTAssertNil(SiteHealthRepair.buttonTitle(
            for: [finding("curriculumCoverageFoundNothing", fixable: true)]
        ))
    }

    func testAMissingMediaFolderIsPutBack() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        let media: URL = course.directoryURL.appendingPathComponent("Media")
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.path))

        let repaired: [String] = SiteHealthRepair.repair(
            [finding("mediaFolderMissing", fixable: true)], in: course
        )
        XCTAssertEqual(repaired, ["mediaFolderMissing"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.path))
    }

    func testAMissingFrontPageIsPutBackWithATitle() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        SiteHealthRepair.repair([finding("sectionIndexMissing", fixable: true)], in: course)

        let index: URL = course.sectionDirectoryURL(forSection: 1)
            .appendingPathComponent("index.md")
        let written: String = try String(contentsOf: index, encoding: .utf8)
        XCTAssertTrue(written.contains("title: Introduction to Computer Science"), written)
    }

    /// Pressing it twice, or pressing it after fixing the problem in Obsidian,
    /// must change nothing — a repair that overwrote would destroy the very
    /// page the teacher had just written.
    func testARepairNeverOverwritesWhatIsAlreadyThere() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        let index: URL = course.sectionDirectoryURL(forSection: 1)
            .appendingPathComponent("index.md")
        try FileManager.default.createDirectory(
            at: index.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "---\ntitle: My own front page\n---\nWelcome!\n"
            .write(to: index, atomically: true, encoding: .utf8)

        let repaired: [String] = SiteHealthRepair.repair(
            [finding("sectionIndexMissing", fixable: true)], in: course
        )
        XCTAssertTrue(repaired.isEmpty, "there was nothing to repair")
        XCTAssertTrue(
            try String(contentsOf: index, encoding: .utf8).contains("Welcome!"),
            "the teacher's own page must survive"
        )
    }
}
