import XCTest
@testable import QuartzTeachers

/// The wizard's factory defaults are school-neutral, and since #891 (2.0.0)
/// there is no switch that offers one school's own folder and file names
/// instead. A course made with that switch keeps the names in its settings:
/// nothing reads `use_lcs_terminology` after set-up, and the app's config
/// writer keeps keys it does not own.
final class TerminologyTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testTheNeutralDefaultsCarryNoSchoolTerms() {
        XCTAssertFalse(WizardDefaults.sharedFolders.contains("College Board Curriculum"))
        XCTAssertFalse(WizardDefaults.sharedFiles.contains("SIC Drop-In Sessions.md"))
        XCTAssertFalse(WizardDefaults.sharedFiles.contains("Grove Time.md"))
        XCTAssertTrue(WizardDefaults.sharedFiles.contains("Extra Help.md"))
    }

    @MainActor
    func testHiddenDefaultsStillCoverTheEarlierNames() {
        for name in ["Extra Help.md", "Grove Time.md", "SIC Drop-In Sessions.md", "College Board Curriculum"] {
            XCTAssertTrue(WizardDefaults.hiddenItems.contains(name), "\(name) missing from hidden defaults")
        }
    }

    /// Must fail on the code before #891, which wrote the key into every new
    /// course's file.
    @MainActor
    func testANewCourseRecordsNoTerminologyChoice() {
        let wizard: NewCourseWizardView = NewCourseWizardView()
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "ICS3U", name: "Computer Science"
        )
        XCTAssertNil(configuration["use_lcs_terminology"],
                     "The switch is gone, so a new course records no choice")
    }

    /// The wizard's source holds no switch: a scan, because a control left
    /// in the view with nothing behind it is what a model test cannot see.
    func testTheWizardHasNoTerminologySwitch() throws {
        let source: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/Views/Wizard/NewCourseWizardView.swift")
        let text: String = try String(contentsOf: source, encoding: .utf8)
        XCTAssertFalse(text.contains("Terminology"), "NewCourseWizardView still names a terminology switch")
        XCTAssertFalse(text.contains("use_lcs_terminology"), "NewCourseWizardView still writes the key")
    }

    /// An earlier course's file keeps the key when the app saves a change to
    /// another setting, so
    /// nothing about that course changes behind the teacher's back.
    @MainActor
    func testAnEarlierCoursesKeySurvivesASave() throws {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("terminology-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file: URL = folder.appendingPathComponent("course_config.json")
        let earlier: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Computer Science",
            "num_sections": 1,
            "section_numbers": [1],
            "shared_files": ["SIC Drop-In Sessions.md", "Grove Time.md", "Learning Goals.md"],
            "use_lcs_terminology": true,
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: earlier, options: [.prettyPrinted])
        try data.write(to: file)

        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: file)
        configuration.setColourSchemeID("coastal-breeze", forSection: 1)
        try configuration.write(to: file)

        let saved: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: file)) as? [String: Any]
        )
        XCTAssertEqual(saved["use_lcs_terminology"] as? Bool, true)
        XCTAssertEqual(saved["shared_files"] as? [String], ["SIC Drop-In Sessions.md", "Grove Time.md", "Learning Goals.md"])
    }
}
