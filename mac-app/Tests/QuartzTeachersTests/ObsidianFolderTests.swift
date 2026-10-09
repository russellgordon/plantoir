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

    /// Every route asks the one function, `WorkspaceModel.openInObsidian`:
    /// nothing outside it (and the note's own "Open in Obsidian") calls
    /// `FolderActions.openInObsidian` directly. Until the HIG sweep (#457)
    /// the section window's toolbar did, and so skipped the reference
    /// course's re-lock and its locked-pages note — one command, two
    /// behaviours.
    func testEveryRouteAsksTheOneFunction() throws {
        let source: URL = UserFacingLabelWordsTests.macAppRoot().appendingPathComponent("QuartzTeachers")
        var callers: [String] = []
        for file in UserFacingLabelWordsTests.swiftFiles(under: source) {
            let code: String = TextFieldStyleScanTests.codeWithoutComments(try String(contentsOf: file, encoding: .utf8))
            let count: Int = SaveEnablesTests.occurrences(of: "FolderActions.openInObsidian(", in: code)
            if count > 0 {
                callers.append(file.lastPathComponent + " x" + String(count))
            }
        }
        XCTAssertEqual(callers, ["OpenInObsidianRoute.swift x2"], "Open in Obsidian goes through WorkspaceModel.openInObsidian from every route")
        let detail: String = try String(
            contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent("Section/SectionDetailView.swift"), encoding: .utf8
        )
        XCTAssertTrue(detail.contains("workspace.openInObsidian(course: course, sectionNumber: sectionNumber)"),
                      "the section window's toolbar button")
    }

    /// The toolbar's route, on a section of a course kept for reference:
    /// the note is asked for FIRST, with the section's own folder, and
    /// Obsidian is not opened yet.
    func testTheToolbarRouteOnAReferenceSectionAsksTheNoteFirst() throws {
        LockedPagesNote.defaults = TestDefaults.make()
        defer { LockedPagesNote.defaults = PlantoirDefaults.shared }
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let courses: [Course] = try WorkspaceModel.discoverCourses(in: fixtureURL.appendingPathComponent("courses"))
        let course: Course = try XCTUnwrap(courses.first)
        course.configuration.keptForReference = true
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        var lockedAgain: [String] = []
        let opened: Bool = workspace.openInObsidian(course: course, sectionNumber: 2) { asked in
            lockedAgain.append(asked.code)
        }
        XCTAssertFalse(opened, "Obsidian waits for the note")
        XCTAssertEqual(lockedAgain, [course.code], "the pages are locked again before Obsidian opens")
        let request: LockedPagesNoteRequest = try XCTUnwrap(workspace.lockedPagesNoteRequest)
        XCTAssertEqual(request.course.code, course.code)
        XCTAssertEqual(request.folder, course.sectionDirectoryURL(forSection: 2), "the section's own folder, as the toolbar reveals")
    }
}
