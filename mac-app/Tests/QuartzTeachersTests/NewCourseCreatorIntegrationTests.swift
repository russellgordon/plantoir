import XCTest
@testable import QuartzTeachers

/// Creates a throwaway course through the app's New Course flow — which
/// runs the REAL ./setup.sh — and verifies the wizard scaffolds it exactly
/// as a command-line run would.
///
/// The end-to-end test requires INTEGRATION_WORKSPACE (see
/// ScriptRunnerIntegrationTests): a working folder INSIDE the home folder,
/// because the launchers refuse to mount anything the Colima VM cannot see
/// (#221). What it adds is the app's answer-pumping and the real image. Which
/// keys a new course's pages are written with is checked without Docker by
/// scripts/test_page_visibility.py → NewCourseIsWrittenInTheCurrentKeys, and
/// the check this test makes of them runs in every suite through
/// `testTheScaffoldingCheckAcceptsTheCurrentKeyAndRejectsTheLegacyOne` —
/// until #139 it asserted the retired `draftSection1` key and, never running,
/// agreed with nothing.
final class NewCourseCreatorIntegrationTests: XCTestCase {

    // MARK: - Stored properties

    /// A code unlikely to collide with real courses; cleaned up afterwards.
    let throwawayCode: String = "ZZT2O"

    // MARK: - Functions

    var integrationWorkspacePath: String? {
        let environment: [String: String] = ProcessInfo.processInfo.environment
        return environment["INTEGRATION_WORKSPACE"]
    }

    @MainActor
    func testWizardDrivenCourseCreationMatchesCommandLine() async throws {
        guard let workspacePath = integrationWorkspacePath else {
            throw XCTSkip(
                "Set INTEGRATION_WORKSPACE to a working folder inside your home folder to run the wizard end to end "
                    + "through setup.sh; which keys a new course is written with is checked without it by "
                    + "scripts/test_page_visibility.py."
            )
        }
        let workspaceURL: URL = URL(fileURLWithPath: workspacePath)
        let courseDirectoryURL: URL = workspaceURL
            .appendingPathComponent("courses")
            .appendingPathComponent(throwawayCode)

        // Clean slate.
        try? FileManager.default.removeItem(at: courseDirectoryURL)

        // The configuration the wizard form would assemble.
        let configuration: [String: Any] = [
            "course_code": throwawayCode,
            "course_name": "Wizard Equivalence Test",
            "custom_short_name": "",
            "locale": "en-US",
            "emojis": ["sections": ["section1": "🧪"]],
            "num_sections": 1,
            "section_numbers": [1],
            "shared_folders": ["Concepts", "Exercises"],
            "shared_files": ["Learning Goals.md"],
            "per_section_folders": ["All Classes"],
            "per_section_files": ["Key Links.md"],
            "hidden": ["Media", "Learning Goals.md", "Key Links.md"],
            "expandable": ["Concepts", "Exercises"],
            "expandOnFolderClick": false,
            "footer_html": "",
            "show_reading_time": false,
            "fonts": [
                "default": ["header": "Helvetica, Arial", "body": "Helvetica, Arial", "code": "IBM Plex Mono"],
                "sections": ["section1": ["header": "Helvetica, Arial", "body": "Helvetica, Arial", "code": "IBM Plex Mono"]],
            ],
            "show_section_marker": ["sections": ["section1": true]],
            "color_schemes": ["section1": "quartz-standard"],
        ]

        let creator: NewCourseCreator = NewCourseCreator()
        creator.createCourse(configuration: configuration, workspaceURL: workspaceURL)
        XCTAssertNil(creator.preparationProblem)

        // The wizard walks many prompts and scaffolds the course;
        // allow up to five minutes.
        var waited: Double = 0
        while creator.isCreating && waited < 300 {
            try await Task.sleep(for: .seconds(2))
            waited += 2
        }
        XCTAssertFalse(creator.isCreating, "setup.sh should finish; output:\n\(creator.runner.transcript.displayText.suffix(3000))")
        XCTAssertEqual(creator.runner.lastExitCode, 0, "setup.sh should succeed; output:\n\(creator.runner.transcript.displayText.suffix(3000))")

        // Now verify the scaffolding the REAL wizard created — the same
        // artifacts a command-line run produces.
        let fileManager: FileManager = FileManager.default
        let expectedPaths: [String] = [
            "course_config.json",
            "Media",
            ".obsidian/app.json",
            "Concepts/index.md",
            "Exercises/index.md",
            "Learning Goals.md",
            "section1/index.md",
            "section1/All Classes/index.md",
            "section1/Key Links.md",
        ]
        for expectedPath in expectedPaths {
            let fullPath: String = courseDirectoryURL.appendingPathComponent(expectedPath).path
            XCTAssertTrue(fileManager.fileExists(atPath: fullPath), "Wizard should have created \(expectedPath)")
        }

        // The wizard re-writes course_config.json itself at the end; it
        // must round-trip our answers (section markers, scheme, fonts…).
        let finalConfigURL: URL = courseDirectoryURL.appendingPathComponent("course_config.json")
        let finalConfiguration: CourseConfiguration = try CourseConfiguration(contentsOf: finalConfigURL)
        XCTAssertEqual(finalConfiguration.courseName, "Wizard Equivalence Test")
        XCTAssertEqual(finalConfiguration.sectionNumbers, [1])
        XCTAssertEqual(finalConfiguration.emoji(forSection: 1), "🧪")
        XCTAssertEqual(finalConfiguration.colourSchemeID(forSection: 1), "quartz-standard")
        XCTAssertEqual(finalConfiguration.sharedFolders, ["Concepts", "Exercises"])

        // A shared index.md must carry the per-section frontmatter keys the
        // multi-section publishing system depends on.
        let conceptsIndexURL: URL = courseDirectoryURL.appendingPathComponent("Concepts/index.md")
        let conceptsIndexText: String = try String(contentsOf: conceptsIndexURL, encoding: .utf8)
        let keyProblem: String? = try NewCourseCreatorIntegrationTests.courseLevelKeyProblem(
            in: conceptsIndexText,
            sections: [1]
        )
        XCTAssertNil(keyProblem, keyProblem ?? "")

        // Clean up the throwaway course (and its automatic backup).
        try? fileManager.removeItem(at: courseDirectoryURL)
        let backupURL: URL = workspaceURL.appendingPathComponent("courses/_backups/\(throwawayCode)")
        try? fileManager.removeItem(at: backupURL)
    }

    /// The check the end-to-end test makes of a scaffolded course-level page,
    /// run on its own in every suite so it can never again agree with nothing.
    /// The page text is what `Concepts/index.md` was measured to contain for a
    /// new course on 2026-09-26 (setup_course.py, plain scaffold).
    @MainActor
    func testTheScaffoldingCheckAcceptsTheCurrentKeyAndRejectsTheLegacyOne() throws {
        let currentPage: String = """
            ---
            title: Concepts
            createdSection1: 2026-09-26T16:34:18.000-0400
            publishForSection1: true
            createdSection2: 2026-09-26T16:34:18.000-0400
            publishForSection2: true
            ---
            This is the **Concepts** folder.
            """
        XCTAssertNil(try NewCourseCreatorIntegrationTests.courseLevelKeyProblem(in: currentPage, sections: [1, 2]))

        let legacyPage: String = """
            ---
            title: Concepts
            createdSection1: 2026-09-26T16:34:18.000-0400
            draftSection1: false
            ---
            This is the **Concepts** folder.
            """
        XCTAssertNotNil(try NewCourseCreatorIntegrationTests.courseLevelKeyProblem(in: legacyPage, sections: [1]))

        let oneSectionMissing: String = """
            ---
            title: Concepts
            createdSection1: 2026-09-26T16:34:18.000-0400
            publishForSection1: true
            ---
            """
        XCTAssertNotNil(
            try NewCourseCreatorIntegrationTests.courseLevelKeyProblem(in: oneSectionMissing, sections: [1, 2]),
            "section 2 says nothing, so the page is not scaffolded for it"
        )
    }

    /// A sentence saying what is wrong with a scaffolded course-level page, or
    /// nil when every section has its `createdSection<N>` and its CURRENT
    /// visibility key set to true, and no section has the legacy key. The two
    /// key names are read from contracts/file-formats.json →
    /// pageVisibility.keys.courseLevelPage, never typed here.
    @MainActor
    static func courseLevelKeyProblem(in pageText: String, sections: [Int]) throws -> String? {
        let pageVisibility: [String: Any] = try FileFormatsContractTests.section("pageVisibility")
        let keys: [String: Any] = try XCTUnwrap(pageVisibility["keys"] as? [String: Any])
        let courseLevelPage: [String: String] = try XCTUnwrap(keys["courseLevelPage"] as? [String: String])
        let currentPattern: String = try XCTUnwrap(courseLevelPage["current"])
        let legacyPattern: String = try XCTUnwrap(courseLevelPage["legacy"])

        var lines: [String] = []
        for line in pageText.components(separatedBy: "\n") {
            lines.append(line.trimmingCharacters(in: .whitespaces))
        }

        for section in sections {
            let currentKey: String = currentPattern.replacingOccurrences(of: "<N>", with: String(section))
            let legacyKey: String = legacyPattern.replacingOccurrences(of: "<N>", with: String(section))
            var hasCreated: Bool = false
            var hasCurrentTrue: Bool = false
            for line in lines {
                if line.hasPrefix("createdSection\(section):") {
                    hasCreated = true
                }
                if line == "\(currentKey): true" {
                    hasCurrentTrue = true
                }
                if line.hasPrefix("\(legacyKey):") {
                    return "The page carries the retired key \(legacyKey)."
                }
            }
            if !hasCreated {
                return "The page carries no createdSection\(section)."
            }
            if !hasCurrentTrue {
                return "The page does not say \(currentKey): true."
            }
        }
        return nil
    }
}
