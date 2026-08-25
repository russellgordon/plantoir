import XCTest
@testable import QuartzTeachers

/// The in-app explanation of which folders Plantoir uses.
///
/// Two properties matter and neither is obvious from reading the view: it must
/// name the folders THIS course has rather than the rule that finds them, and
/// it must not describe the machinery.
@MainActor
final class SpecialFoldersHelpTests: XCTestCase {

    // MARK: - Functions

    private func makeCourse(
        shared: [String] = ["Concepts", "Tasks", "Ontario Curriculum"],
        perSection: [String] = ["All Classes"],
        graded: [String]? = nil,
        curriculum: String? = "Ontario Curriculum"
    ) throws -> (URL, Course) {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("folders-help-\(UUID().uuidString)")
        let courseURL: URL = root.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
        var configuration: [String: Any] = [
            "course_code": "ICS3U", "course_name": "Introduction to Computer Science",
            "section_numbers": [1], "num_sections": 1,
            "shared_folders": shared, "per_section_folders": perSection,
            "shared_files": [], "per_section_files": [],
        ]
        if let graded {
            configuration["graded_folders"] = graded
        }
        if let curriculum {
            configuration["curriculum_folder"] = curriculum
        }
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: configURL)
        return (root, Course(
            code: "ICS3U", directoryURL: courseURL,
            configuration: try CourseConfiguration(contentsOf: configURL)
        ))
    }

    /// The whole point: a teacher is told what THEIR folders are called.
    func testItNamesThisCoursesOwnFolders() throws {
        let (root, course) = try makeCourse(
            shared: ["Concepts", "Tests", "Expectations"],
            perSection: ["Lessons"],
            graded: ["Tests"],
            curriculum: "Expectations"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let text: String = SpecialFoldersHelpView(course: course).entries
            .map { entry in return entry.name }
            .joined(separator: "\n")

        XCTAssertTrue(text.contains("Lessons"), text)
        XCTAssertTrue(text.contains("Expectations"), text)
        XCTAssertTrue(text.contains("Tests"), text)
        XCTAssertFalse(text.contains("All Classes"),
                       "this course does not have a folder called All Classes")
    }

    /// A course that has never been asked is shown what the build currently
    /// counts, not a blank or a guess.
    func testACourseNeverAskedIsShownWhatCountsToday() throws {
        let (root, course) = try makeCourse(graded: nil)
        defer { try? FileManager.default.removeItem(at: root) }

        let view: SpecialFoldersHelpView = SpecialFoldersHelpView(course: course)
        XCTAssertEqual(view.gradedFolderNames, ["Tasks"])
    }

    /// Rule 1. This text is shown verbatim, and the whole reason the help
    /// documents CONFIGURED names is to avoid publishing the matching rule as
    /// if it were a promise.
    func testItNamesNoMachineryAndPublishesNoMatchingRule() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        var shown: String = ""
        for entry in SpecialFoldersHelpView(course: course).entries {
            shown += entry.name + " " + entry.what + " " + entry.why + " "
        }
        let forbidden: [String] = [
            "toolchain", "script", "docker", "container", "wsl", "python",
            "json", "quartz", "config", "repository", "substring", "regex",
            "case-insensitive", "segment",
        ]
        for word in forbidden {
            XCTAssertFalse(shown.lowercased().contains(word),
                           "the folders help says \"\(word)\" to a teacher")
        }
    }

    func testSeveralFoldersAreListedTheWayAPersonWouldSayThem() {
        XCTAssertEqual(SpecialFoldersHelpView.listed(["Tasks"]), "Tasks")
        XCTAssertEqual(SpecialFoldersHelpView.listed(["Tasks", "Tests"]), "Tasks and Tests")
        XCTAssertEqual(
            SpecialFoldersHelpView.listed(["Tasks", "Tests", "Quizzes"]),
            "Tasks, Tests and Quizzes"
        )
        XCTAssertEqual(SpecialFoldersHelpView.listed([]), "None chosen")
    }
}
