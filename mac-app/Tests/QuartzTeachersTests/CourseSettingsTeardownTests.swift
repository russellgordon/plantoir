import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Leaving a course's settings while its folder tables are on screen, in the
/// real window (issue #266).
///
/// **The fault this pins.** With the settings page showing, simply choosing
/// nothing in the sidebar — or another working folder, or one of the
/// course's sections — aborted the whole app with SwiftUI's "precondition
/// failure: no subgraph". The measured trigger was a table CELL calling the
/// list's `protection` closure while it was drawn: the marks table's tick
/// cell called it (the closure reads the course's configuration and walks
/// its folders). Measured by bisecting on 2026-09-24: only the marks table
/// crashed; a plain cell, a cell given the same answer worked out BEFORE the
/// table, a cell reading the list's binding, and the other tables all
/// survived, while the Shared folders table crashed too the moment its cells
/// called the marks table's question. WHY is not known. The rule that fixed
/// it — every per-row protection is worked out in the list's own body and
/// handed to the cell as a value — is written up in
/// `documentation/09-mac-app.md`.
///
/// **Why the real window and not `TableHost`.** Hosting `CourseSettingsView`
/// on its own and removing it did NOT crash, in any of five variants tried
/// (tall and short windows, with and without an animation, with and without
/// a change to the course in the same moment). The detail pane of the
/// window's split view is what rebuilds the rows before removing them, so
/// only the window reproduces it.
final class CourseSettingsTeardownTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func settle(seconds: Double = 0.8) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Every table in the app's windows, so a test can confirm the settings
    /// page's tables really were on screen before it was taken away — without
    /// that, a test that never showed them would pass for the wrong reason.
    @MainActor
    func tableCount() -> Int {
        var count: Int = 0
        for window in NSApp.windows {
            if let contentView = window.contentView {
                count = count + tables(inside: contentView)
            }
        }
        return count
    }

    @MainActor
    func tables(inside view: NSView) -> Int {
        var count: Int = 0
        if view is NSTableView {
            count = count + 1
        }
        for subview in view.subviews {
            count = count + tables(inside: subview)
        }
        return count
    }

    /// Opens a fresh working folder in the real window and shows its first
    /// course's settings, tables and all.
    @MainActor
    func showSettingsOfTheFirstCourse() async throws -> (workspace: WorkspaceModel, course: Course, fixtureURL: URL) {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        let workspace: WorkspaceModel = try XCTUnwrap(
            WorkspaceModel.windowModels.first,
            "No window model registered; the interface is not on screen"
        )
        workspace.chooseWorkspace(at: fixtureURL)
        await settle()
        let course: Course = try XCTUnwrap(workspace.courses.first)
        XCTAssertFalse(course.isKeptForReference, "the settings page, not the reference summary, has to be showing")

        let tablesBefore: Int = tableCount()
        workspace.selection = SidebarSelection.course(course.code)
        await settle()
        XCTAssertGreaterThan(
            tableCount(), tablesBefore,
            "the settings page's folder tables should be on screen before the page is taken away"
        )
        return (workspace, course, fixtureURL)
    }

    // MARK: - Tests

    /// Choosing nothing in the sidebar — the simplest way to leave the page.
    @MainActor
    func testLeavingCourseSettingsForNothingDoesNotCrash() async throws {
        let shown = try await showSettingsOfTheFirstCourse()

        shown.workspace.selection = nil
        await settle()

        XCTAssertNil(shown.workspace.selection, "the page was left, and the app is still here to say so")
        try? FileManager.default.removeItem(at: shown.fixtureURL)
    }

    /// Clicking one of the course's own sections: the path a teacher takes
    /// most often.
    @MainActor
    func testLeavingCourseSettingsForASectionDoesNotCrash() async throws {
        let shown = try await showSettingsOfTheFirstCourse()
        let sectionNumber: Int = try XCTUnwrap(shown.course.sectionNumbers.first)

        shown.workspace.selection = SidebarSelection.section(shown.course.code, sectionNumber)
        await settle()

        XCTAssertEqual(shown.workspace.selection, SidebarSelection.section(shown.course.code, sectionNumber))
        shown.workspace.selection = nil
        await settle()
        try? FileManager.default.removeItem(at: shown.fixtureURL)
    }

    /// Opening another working folder, which lets go of the selection — how
    /// the crash was first seen, in `CourseRenameInterfaceTests`.
    @MainActor
    func testOpeningAnotherWorkingFolderFromCourseSettingsDoesNotCrash() async throws {
        let shown = try await showSettingsOfTheFirstCourse()
        let otherFixtureURL: URL = try FixtureWorkspace.materialize()

        shown.workspace.chooseWorkspace(at: otherFixtureURL)
        await settle()

        XCTAssertNil(shown.workspace.selection, "a different folder starts with nothing selected")
        try? FileManager.default.removeItem(at: shown.fixtureURL)
        try? FileManager.default.removeItem(at: otherFixtureURL)
    }
}
