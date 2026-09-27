import XCTest
@testable import QuartzTeachers

/// What the app WRITES about a course's curriculum folders (#128): the
/// setter behind the "Curriculum folders" checkboxes, and the new-course
/// wizard's file. Added on the #128 implementation review, where a mutant
/// that stopped the setter dropping the legacy key survived every suite.
@MainActor
final class CurriculumFoldersWritingTests: XCTestCase {

    // MARK: - Functions

    private func configuration(_ values: [String: Any]) -> CourseConfiguration {
        return CourseConfiguration(values: values, lastSavedData: Data())
    }

    // MARK: - The setter

    /// Unticking the folder the legacy key names must take it out of the
    /// union, or the box springs back ticked.
    func testUntickingTheLegacyFolderTakesItOutOfTheUnion() {
        let course: CourseConfiguration = configuration([
            "curriculum_folder": "Curriculum",
            "curriculum_folders": ["Curriculum", "College Board Curriculum"],
        ])
        course.curriculumFolders = ["College Board Curriculum"]
        XCTAssertEqual(course.curriculumFolders, ["College Board Curriculum"])
        XCTAssertEqual(course.values["curriculum_folder"] as? String, "College Board Curriculum",
                       "the legacy key names the new primary, for an older Plantoir")
    }

    func testTheListIsWrittenWithItsPrimaryInTheLegacyKey() {
        let course: CourseConfiguration = configuration([:])
        course.curriculumFolders = ["Ontario Curriculum", "College Board Curriculum"]
        XCTAssertEqual(course.values["curriculum_folders"] as? [String],
                       ["Ontario Curriculum", "College Board Curriculum"])
        XCTAssertEqual(course.values["curriculum_folder"] as? String, "Ontario Curriculum")
    }

    func testAnEmptyListRemovesBothKeys() {
        let course: CourseConfiguration = configuration([
            "curriculum_folder": "Curriculum", "curriculum_folders": ["Curriculum"],
        ])
        course.curriculumFolders = []
        XCTAssertNil(course.values["curriculum_folders"])
        XCTAssertNil(course.values["curriculum_folder"])
        XCTAssertEqual(course.curriculumFolders, [])
    }

    // MARK: - The wizard

    /// Untouched, the wizard writes neither key — setup records the payload's
    /// folder — so every earlier path writes the file it always wrote.
    func testAWizardWhoseListWasNotTouchedWritesNothing() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "ICS3U", sharedFolders: WizardDefaults.lcsSharedFolders
        )
        let written: [String: Any] = wizard.buildConfigurationDictionary(code: "ICS3U", name: "Computer Science")
        XCTAssertNil(written["curriculum_folders"])
        XCTAssertNil(written["curriculum_folder"])
    }

    /// Ticked: the list in the ticks' order, only folders the course keeps,
    /// and the primary in the legacy key.
    func testAWizardWithTicksWritesThemAndThePrimary() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            prepopulatesExampleContent: false,
            startsFromSkeleton: false,
            sharedFolders: WizardDefaults.lcsSharedFolders,
            curriculumFolderTicks: ["Ontario Curriculum", "College Board Curriculum", "A Folder Since Removed"]
        )
        let written: [String: Any] = wizard.buildConfigurationDictionary(code: "ZZZ9Z", name: "Test")
        XCTAssertEqual(written["curriculum_folders"] as? [String], ["Ontario Curriculum", "College Board Curriculum"])
        XCTAssertEqual(written["curriculum_folder"] as? String, "Ontario Curriculum")
    }
}
