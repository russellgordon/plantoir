import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The per-course-code example content: the catalog that says whether any
/// exists, and the wizard's answers about installing it.
final class ExampleContentTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testTheCatalogFindsTheBundledADA1OContent() {
        XCTAssertTrue(ExampleContentCatalog.hasContent(forCode: "ADA1O"))
        XCTAssertTrue(ExampleContentCatalog.hasContent(forCode: " ada1o "),
                      "Lookup is case-insensitive and trims, like every other code lookup")
    }

    @MainActor
    func testTheCatalogKnowsADA1OIncludesCurriculumPages() {
        XCTAssertTrue(ExampleContentCatalog.includesCurriculum(forCode: "ADA1O"))
    }

    @MainActor
    func testAnUnknownCodeHasNoContent() {
        XCTAssertFalse(ExampleContentCatalog.hasContent(forCode: "ZZZ9X"))
        XCTAssertFalse(ExampleContentCatalog.includesCurriculum(forCode: "ZZZ9X"))
        XCTAssertFalse(ExampleContentCatalog.hasContent(forCode: ""))
    }

    @MainActor
    func testTheWizardWritesBothFlagsForACodeWithContent() {
        let wizard: NewCourseWizardView = NewCourseWizardView()
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "ADA1O", name: "Drama"
        )
        XCTAssertEqual(configuration["prepopulate_example_content"] as? Bool, true)
        XCTAssertEqual(configuration["include_curriculum_pages"] as? Bool, true)
    }

    /// The coverage map reads the site's links to the curriculum pages, so
    /// it cannot survive those pages being declined — whatever the toggle
    /// was last left at. The rule is tested through the pure function
    /// rather than the view, because a `@State` property set on a view
    /// that is not on screen never takes.
    @MainActor
    func testTheCoverageMapFollowsTheCurriculumPages() {
        // Curriculum kept, map wanted.
        XCTAssertTrue(CourseConfiguration.curriculumCoverageEnabled(
            curriculumPagesOffered: true, includesCurriculumPages: true,
            includesCurriculumCoverage: true))

        // Curriculum declined: the map cannot exist, whatever its toggle says.
        XCTAssertFalse(CourseConfiguration.curriculumCoverageEnabled(
            curriculumPagesOffered: true, includesCurriculumPages: false,
            includesCurriculumCoverage: true))

        // Curriculum kept, map declined — allowed, and respected.
        XCTAssertFalse(CourseConfiguration.curriculumCoverageEnabled(
            curriculumPagesOffered: true, includesCurriculumPages: true,
            includesCurriculumCoverage: false))

        // No curriculum pages to be had: nothing to measure.
        XCTAssertFalse(CourseConfiguration.curriculumCoverageEnabled(
            curriculumPagesOffered: false, includesCurriculumPages: true,
            includesCurriculumCoverage: true))
    }

    /// Which courses may be offered the curriculum pages written for their
    /// code. Two starting points reach them since GitHub issue #251: the
    /// teacher taking the ready-made pages, and the teacher who declined
    /// them and kept the subject's skeleton.
    @MainActor
    func testWhichCoursesAreOfferedTheirCurriculumPages() {
        // Taking the ready-made pages — the case that has always worked.
        XCTAssertTrue(CourseConfiguration.curriculumPagesOffered(
            codeHasExampleContent: true, payloadIncludesCurriculum: true,
            prepopulatesExampleContent: true,
            skeletonIsOffered: false, startsFromSkeleton: false))

        // Declined, skeleton kept: the expectations still exist, so they
        // are still offered. This is the whole of issue #251.
        XCTAssertTrue(CourseConfiguration.curriculumPagesOffered(
            codeHasExampleContent: true, payloadIncludesCurriculum: true,
            prepopulatesExampleContent: false,
            skeletonIsOffered: true, startsFromSkeleton: true))

        // Declined, and the skeleton declined too: an empty course, and
        // nothing is poured into it.
        XCTAssertFalse(CourseConfiguration.curriculumPagesOffered(
            codeHasExampleContent: true, payloadIncludesCurriculum: true,
            prepopulatesExampleContent: false,
            skeletonIsOffered: true, startsFromSkeleton: false))

        // No payload for the code: its skeleton ships an empty Curriculum
        // folder, and there is nothing anywhere to fill it with — whatever
        // the skeleton toggle says. This is the ~1,900.
        for startsFromSkeleton in [true, false] {
            XCTAssertFalse(CourseConfiguration.curriculumPagesOffered(
                codeHasExampleContent: false, payloadIncludesCurriculum: false,
                prepopulatesExampleContent: false,
                skeletonIsOffered: true, startsFromSkeleton: startsFromSkeleton))
        }

        // A payload that carries no curriculum folder has no expectations
        // to give, taken or declined.
        XCTAssertFalse(CourseConfiguration.curriculumPagesOffered(
            codeHasExampleContent: true, payloadIncludesCurriculum: false,
            prepopulatesExampleContent: true,
            skeletonIsOffered: false, startsFromSkeleton: false))
        XCTAssertFalse(CourseConfiguration.curriculumPagesOffered(
            codeHasExampleContent: true, payloadIncludesCurriculum: false,
            prepopulatesExampleContent: false,
            skeletonIsOffered: true, startsFromSkeleton: true))
    }

    /// The two explanatory sections live ON the coverage page, so they
    /// cannot outlive it. Tested through the pure function for the same
    /// reason as the rule above.
    @MainActor
    func testTheCoverageNotesFollowTheCoverageMap() {
        // Map published, sections wanted.
        XCTAssertTrue(CourseConfiguration.coverageNotesEnabled(
            curriculumCoverageEnabled: true, includesCoverageNotes: true))

        // Map published, sections declined — allowed, and respected.
        XCTAssertFalse(CourseConfiguration.coverageNotesEnabled(
            curriculumCoverageEnabled: true, includesCoverageNotes: false))

        // No map: the sections have nowhere to live, whatever the toggle says.
        XCTAssertFalse(CourseConfiguration.coverageNotesEnabled(
            curriculumCoverageEnabled: false, includesCoverageNotes: true))
    }

    /// Turning the map off in course settings must take the sections with
    /// it, so that a saved config can never claim sections on a page that
    /// is not being written.
    @MainActor
    func testTurningTheMapOffInSettingsTakesTheSectionsWithIt() {
        let configuration: CourseConfiguration = CourseConfiguration(
            values: ["include_curriculum_coverage": true,
                     "include_coverage_notes": true],
            lastSavedData: Data()
        )
        XCTAssertTrue(configuration.includesCoverageNotes)

        configuration.includesCurriculumCoverage = false
        XCTAssertFalse(configuration.includesCoverageNotes)
        XCTAssertEqual(configuration.values["include_coverage_notes"] as? Bool, false)
    }

    /// The default answers a brand-new wizard hands over.
    @MainActor
    func testANewWizardDefaultsTheMapOnForACourseWithCurriculum() {
        let wizard: NewCourseWizardView = NewCourseWizardView()
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "ADA1O", name: "Drama"
        )
        XCTAssertEqual(configuration["include_curriculum_coverage"] as? Bool, true)
        XCTAssertEqual(configuration["include_coverage_notes"] as? Bool, true)
    }

    @MainActor
    func testTheFlagsAreFalseForACodeWithoutContent() {
        // The toggles default to on, but a stale on must mean nothing when
        // there is no content for the code being created.
        let wizard: NewCourseWizardView = NewCourseWizardView()
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "ZZZ9X", name: "Mystery Course"
        )
        XCTAssertEqual(configuration["prepopulate_example_content"] as? Bool, false)
        XCTAssertEqual(configuration["include_curriculum_pages"] as? Bool, false)
    }

    /// Every page in the bundled ADA1O payload uses the sentinel the real
    /// wizard replaces, never a literal timestamp — a literal would make
    /// every new course claim its pages were created on the author's date.
    func testTheBundledPayloadUsesTheCreatedSentinel() throws {
        let payloadURL: URL = try XCTUnwrap(
            Bundle.main.resourceURL?
                .appendingPathComponent("support/example_content/ADA1O")
        )
        let enumerator = FileManager.default.enumerator(
            at: payloadURL, includingPropertiesForKeys: nil
        )
        var pagesChecked: Int = 0
        while let entry = enumerator?.nextObject() as? URL {
            if entry.pathExtension != "md" {
                continue
            }
            let text: String = try String(contentsOf: entry, encoding: .utf8)
            if text.contains("created:") {
                // Regular pages use __CREATED__; class pages use
                // __CREATED_CLASS_K__ so the installer can spread real,
                // distinct dates across the semester (the All Classes
                // listing sorts by date).
                XCTAssertTrue(
                    text.contains("created: __CREATED"),
                    "\(entry.lastPathComponent) has a created: line without a sentinel"
                )
            }
            pagesChecked += 1
        }
        XCTAssertGreaterThan(pagesChecked, 40, "The ADA1O payload should be bundled and substantial")
    }
}
