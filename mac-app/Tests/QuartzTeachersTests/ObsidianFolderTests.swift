import XCTest
@testable import QuartzTeachers

/// Open in Obsidian reveals ONE folder per row, whichever route asks — the
/// section window's toolbar button, the sidebar's context menu, or Course ▸ /
/// Section ▸ Open in Obsidian (#457: a menu item and the button beside it may
/// not disagree). Until the implementation review a section of a course kept
/// for reference revealed the COURSE folder from its row and the menu bar,
/// while its window's toolbar revealed the section.
@MainActor
final class ObsidianFolderTests: XCTestCase {

    // MARK: - Tests

    func testASectionRevealsItsOwnFolderEvenOnACourseKeptForReference() throws {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let courses: [Course] = try WorkspaceModel.discoverCourses(in: fixtureURL.appendingPathComponent("courses"))
        let course: Course = try XCTUnwrap(courses.first)
        course.configuration.keptForReference = true
        XCTAssertTrue(course.isKeptForReference, "the case is a course kept for reference")
        XCTAssertEqual(
            FolderActions.obsidianFolder(for: course, sectionNumber: 2),
            course.sectionDirectoryURL(forSection: 2)
        )
        XCTAssertEqual(FolderActions.obsidianFolder(for: course, sectionNumber: nil), course.directoryURL)
    }

    /// Every route asks the one function: the toolbar, and the sidebar's
    /// reference route (which also serves the menu bar and the context menu).
    func testEveryRouteAsksTheOneFunction() throws {
        let views: URL = TextFieldStyleScanTests.viewsURL()
        let detail: String = try String(
            contentsOf: views.appendingPathComponent("Section/SectionDetailView.swift"), encoding: .utf8
        )
        let sidebar: String = try String(contentsOf: views.appendingPathComponent("SidebarView.swift"), encoding: .utf8)
        XCTAssertTrue(detail.contains("revealing: FolderActions.obsidianFolder(for: course, sectionNumber: sectionNumber)"),
                      "the section window's toolbar button")
        let reference: String = try XCTUnwrap(
            sidebar.components(separatedBy: "func openReferenceCourseInObsidian(").dropFirst().first
        )
        XCTAssertTrue(reference.prefix(900).contains("FolderActions.obsidianFolder(for: course, sectionNumber: sectionNumber)"),
                      "a reference course's route, from its rows and the menu bar")
        let perform: String = try XCTUnwrap(sidebar.components(separatedBy: "case .courseOpenInObsidian, .sectionOpenInObsidian:").dropFirst().first)
        XCTAssertTrue(perform.prefix(700).contains("openReferenceCourseInObsidian(course, sectionNumber: sectionNumber)"))
        XCTAssertTrue(perform.prefix(700).contains("FolderActions.obsidianFolder(for: course, sectionNumber: sectionNumber)"))
    }
}
