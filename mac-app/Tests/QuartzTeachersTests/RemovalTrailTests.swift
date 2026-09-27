import XCTest
@testable import QuartzTeachers

/// The trail line a blocked removal leaves (GitHub issue #171): it names the
/// course, and says whether the refusal came in the New Course wizard or in
/// Course Settings, in Windows' words.
@MainActor
final class RemovalTrailTests: XCTestCase {

    // MARK: - Tests

    func testCourseSettingsNamesTheCourse() {
        let trail: RemovalTrail = RemovalTrail.inCourseSettings(courseCode: "SNC4M", list: .sharedFolders)
        XCTAssertEqual(
            trail.line(item: "Tasks", reason: "Tasks holds the coverage map."),
            "SNC4M: could not remove “Tasks” from the shared folders — Tasks holds the coverage map."
        )
    }

    func testTheWizardSaysTheCourseIsBeingMade() {
        let trail: RemovalTrail = RemovalTrail.inNewCourse(typedCode: "SNC4M", list: .sharedFolders)
        XCTAssertEqual(
            trail.line(item: "Tasks", reason: "Tasks holds the coverage map."),
            "new course SNC4M: could not remove “Tasks” from the shared folders — Tasks holds the coverage map."
        )
    }

    /// Trimmed and uppercased as the wizard does when it creates the course,
    /// so the line names the course the folder will be called.
    func testTheWizardNamesTheCodeAsItWillBeCreated() {
        let trail: RemovalTrail = RemovalTrail.inNewCourse(typedCode: "  snc4m ", list: .marks)
        XCTAssertEqual(trail.courseCode, "SNC4M")
        XCTAssertTrue(trail.line(item: "Tasks", reason: "r").hasPrefix("new course SNC4M: "))
    }

    func testBeforeACodeIsTypedTheWizardSaysSo() {
        let trail: RemovalTrail = RemovalTrail.inNewCourse(typedCode: "   ", list: .perSectionFiles)
        XCTAssertEqual(
            trail.line(item: "Key Links.md", reason: "r"),
            "new course " + RemovalTrail.codeNotTypedYet + ": could not remove “Key Links.md” from the per-section files — r"
        )
    }

    func testEveryListIsNamedInWindowsWords() {
        let expected: [(RemovalTrail.List, String)] = [
            (.sharedFolders, "the shared folders"),
            (.sharedFiles, "the shared files"),
            (.perSectionFolders, "the per-section folders"),
            (.perSectionFiles, "the per-section files"),
            (.marks, "the marks list"),
            (.curriculumFolders, "the curriculum folders"),
        ]
        for (list, words) in expected {
            XCTAssertEqual(list.words, words)
            let line: String = RemovalTrail.inCourseSettings(courseCode: "SNC4M", list: list)
                .line(item: "Tasks", reason: "r")
            XCTAssertEqual(line, "SNC4M: could not remove “Tasks” from " + words + " — r")
        }
    }

    /// The line carries the code, the item, the list and the reason — no path.
    func testTheLineCarriesNoPath() {
        let line: String = RemovalTrail.inCourseSettings(courseCode: "SNC4M", list: .sharedFolders)
            .line(item: "Tasks", reason: "It is needed.")
        XCTAssertFalse(line.contains("/"), line)
    }

    /// The wizard's own function — what its five lists are built with —
    /// names the course being made, not an existing one.
    func testTheWizardNamesTheCourseItIsMaking() {
        let wizard: NewCourseWizardView = NewCourseWizardView(courseCode: " snc4m ")
        let trail: RemovalTrail = wizard.removalTrail(for: .perSectionFolders)
        XCTAssertEqual(trail, RemovalTrail.inNewCourse(typedCode: "SNC4M", list: .perSectionFolders))
        XCTAssertEqual(trail.place, .newCourse)
        XCTAssertEqual(trail.courseCode, "SNC4M")
    }
}
