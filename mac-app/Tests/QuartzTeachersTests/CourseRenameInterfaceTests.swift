import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Renaming as a teacher meets it: the row turning into a field, and the
/// sidebar keeping its place afterwards.
///
/// **Why the row is tested in a hosting view rather than through the
/// accessibility tree**, unlike `RemovalButtonTests` next door. A sidebar
/// row is a `DisclosureGroup` label inside a `List`, and macOS collapses
/// that whole row into a single `AXHeading` whose value does not follow the
/// row's content — an unconditional change to the label's text does not
/// change it. So accessibility can confirm the − button exists but cannot
/// see whether this row is showing a label or a field. Hosting the row view
/// on its own answers exactly that question, and answers it the same way
/// every run.
final class CourseRenameInterfaceTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func settle(seconds: Double = 0.8) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Every AppKit view class inside a hosted SwiftUI view, so a test can
    /// ask what was actually built rather than what was intended.
    @MainActor
    func viewClasses(inside view: NSView) -> [String] {
        var found: [String] = [String(describing: type(of: view))]
        for subview in view.subviews {
            for name in viewClasses(inside: subview) {
                found.append(name)
            }
        }
        return found
    }

    @MainActor
    func hostedRow(course: Course, isBeingRenamed: Bool, workspace: WorkspaceModel) -> [String] {
        let hosting: NSHostingView = NSHostingView(
            rootView: CourseRowLabel(course: course, isBeingRenamed: isBeingRenamed)
                .environment(workspace)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 60)
        hosting.layoutSubtreeIfNeeded()
        return viewClasses(inside: hosting)
    }

    // MARK: - The row becomes a field, and only while renaming

    @MainActor
    func testTheRowTurnsIntoAFieldWhileRenamingAndBackAfterwards() async throws {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        guard let workspace = WorkspaceModel.windowModels.first else {
            XCTFail("No window model registered; the interface is not on screen")
            return
        }
        workspace.chooseWorkspace(at: fixtureURL)
        await settle()
        let course: Course = try XCTUnwrap(workspace.courses.first)

        let resting: [String] = hostedRow(course: course, isBeingRenamed: false, workspace: workspace)
        var restingHasField: Bool = false
        for name in resting where name.contains("TextField") {
            restingHasField = true
        }
        XCTAssertFalse(restingHasField, "An ordinary row is a label, not a field: \(resting)")

        let renaming: [String] = hostedRow(course: course, isBeingRenamed: true, workspace: workspace)
        var renamingHasField: Bool = false
        for name in renaming where name.contains("TextField") {
            renamingHasField = true
        }
        XCTAssertTrue(renamingHasField, "The row should have become a text field: \(renaming)")

        try? FileManager.default.removeItem(at: fixtureURL)
    }

    // MARK: - Through the real window

    @MainActor
    func testRenamingMovesTheCourseAndTheSidebarFollowsIt() async throws {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        guard let workspace = WorkspaceModel.windowModels.first else {
            XCTFail("No window model registered; the interface is not on screen")
            return
        }

        workspace.chooseWorkspace(at: fixtureURL)
        await settle()
        XCTAssertFalse(workspace.courses.isEmpty, "Fixture should contain a course")

        let originalCode: String = workspace.courses[0].code
        workspace.selection = SidebarSelection.section(originalCode, 2)
        workspace.expandedCourseCodes.insert(originalCode)
        await settle()

        // What Edit ▸ Rename Course does, and what Return in the sidebar
        // does — both land here.
        XCTAssertNotNil(
            workspace.courseThatCanBeRenamed,
            "A section's row means the course it belongs to — there is nothing else in it to rename"
        )
        workspace.beginRenamingSelectedCourse()
        XCTAssertEqual(workspace.renamingCourseCode, originalCode)

        let course: Course = try XCTUnwrap(workspace.courseThatCanBeRenamed)
        workspace.rename(course, to: "exc3o")
        await settle()

        XCTAssertNil(workspace.renameProblem, workspace.renameProblem ?? "")
        XCTAssertNil(workspace.renamingCourseCode, "The field goes away once the rename lands")

        var renamedCodes: [String] = []
        for loaded in workspace.courses {
            renamedCodes.append(loaded.code)
        }
        XCTAssertTrue(renamedCodes.contains("EXC3O"), "typed lower case, stored upper: \(renamedCodes)")
        XCTAssertFalse(renamedCodes.contains(originalCode), "and the old code is gone: \(renamedCodes)")

        XCTAssertEqual(
            workspace.selection, SidebarSelection.section("EXC3O", 2),
            "the same section stays selected, under the new code"
        )
        XCTAssertTrue(
            workspace.expandedCourseCodes.contains("EXC3O"),
            "and the sections the teacher had unfolded stay unfolded"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixtureURL.appendingPathComponent("courses/EXC3O/section2").path
            ),
            "the folder really moved, contents and all"
        )

        try? FileManager.default.removeItem(at: fixtureURL)
    }

    /// A busy course is not renamed out from under its own preview, and the
    /// Return key and the menu item are refused together — both ask the
    /// model the same question.
    @MainActor
    func testACourseThatIsPreviewingIsNotRenamed() async throws {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        guard let workspace = WorkspaceModel.windowModels.first else {
            XCTFail("No window model registered; the interface is not on screen")
            return
        }
        workspace.chooseWorkspace(at: fixtureURL)
        await settle()
        let course: Course = try XCTUnwrap(workspace.courses.first)
        workspace.selection = SidebarSelection.course(course.code)

        PreviewLeases.reset()
        _ = try PreviewLeases.lease(
            folderPath: try XCTUnwrap(workspace.workspaceURL).path,
            courseCode: course.code,
            sectionNumber: 1
        )
        defer { PreviewLeases.reset() }

        XCTAssertNotNil(workspace.renameIsUnavailableReason, "the menu item says why it is dimmed")
        workspace.beginRenamingSelectedCourse()
        XCTAssertNil(workspace.renamingCourseCode, "and no field opens")

        // And the commit path refuses too, in case a preview starts while
        // the field is already open.
        workspace.rename(course, to: "EXC3O")
        await settle()
        XCTAssertEqual(
            workspace.renameProblem,
            "\(course.code) is previewing or deploying right now. Stop that first, then rename."
        )
        workspace.renameProblem = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: course.directoryURL.path))

        try? FileManager.default.removeItem(at: fixtureURL)
    }

    /// A code the rule refuses never gets as far as the file system, and its
    /// reason is shown under the field rather than in an alert.
    ///
    /// **No `await` between opening the field and the last assertion, on
    /// purpose (#293).** This test used to select the course, open the
    /// field in the same turn, and then wait. Waiting hands the turn to two
    /// things that both want the keyboard: the field, which takes focus as
    /// it appears, and the sidebar, which takes it back one turn after a
    /// selection change. When the test host was the frontmost app, the field
    /// lost focus, committed the unchanged code and closed (2 of 2 runs);
    /// with another app in front it could not commit and the test passed
    /// (4 of 4). So it read as a flake that came and went with whatever was
    /// frontmost. Asserting in the same turn leaves nothing for either to
    /// do, and pressing Return through `renameFromTheField` checks what the
    /// test always claimed — that Return is refused — rather than only that
    /// the field survived a wait.
    @MainActor
    func testAnUnusableCodeIsShownUnderTheFieldRatherThanInAnAlert() async throws {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        guard let workspace = WorkspaceModel.windowModels.first else {
            XCTFail("No window model registered; the interface is not on screen")
            return
        }

        workspace.chooseWorkspace(at: fixtureURL)
        await settle()
        let course: Course = try XCTUnwrap(workspace.courses.first)
        let tooLong: String = "MUCH TOO LONG A CODE"

        // From here to the end of the assertions: no suspension point.
        workspace.selection = SidebarSelection.course(course.code)
        workspace.beginRenamingSelectedCourse()
        XCTAssertEqual(workspace.renamingCourseCode, course.code, "the field opened")

        XCTAssertNotNil(
            workspace.renameFieldProblem(course, typed: tooLong),
            "the field shows a reason under itself — the same function it draws"
        )
        let renamed: Bool = workspace.renameFromTheField(course, typed: tooLong)
        XCTAssertFalse(renamed, "Return is refused")
        XCTAssertNil(workspace.renameProblem, "and nothing has gone wrong that needs an alert")
        XCTAssertEqual(workspace.renamingCourseCode, course.code, "the field is still open")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: course.directoryURL.path),
            "the course's folder has not moved"
        )
        let normalizedTooLong: String = CourseCodeRule.normalized(tooLong)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixtureURL.appendingPathComponent("courses").appendingPathComponent(normalizedTooLong).path
            ),
            "and nothing was made under the refused code"
        )

        workspace.renamingCourseCode = nil
        try? FileManager.default.removeItem(at: fixtureURL)
    }

    // MARK: - The Return key

    /// Only a bare Return or keypad Enter. Everything else belongs to
    /// somebody else, and a monitor that swallowed ⌘-Return would break a
    /// key the teacher pressed on purpose somewhere else in the window.
    @MainActor
    func testOnlyABareReturnIsAnswered() throws {
        func press(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            return try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: keyCode
            ))
        }

        XCTAssertTrue(SidebarReturnKey.isPlainReturn(try press(36, [])), "Return")
        XCTAssertTrue(SidebarReturnKey.isPlainReturn(try press(76, [.numericPad])), "keypad Enter")
        XCTAssertFalse(SidebarReturnKey.isPlainReturn(try press(36, [.command])))
        XCTAssertFalse(SidebarReturnKey.isPlainReturn(try press(36, [.shift])))
        XCTAssertFalse(SidebarReturnKey.isPlainReturn(try press(0, [])), "not a Return at all")
    }

    /// The list is found by the identifier the sidebar gives it, which is
    /// the same constant the sidebar applies — so the two cannot drift into
    /// a feature that silently does nothing.
    @MainActor
    func testTheCoursesListIsFoundByTheSidebarsOwnIdentifier() throws {
        let root: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let middle: NSView = NSView()
        let list: NSView = NSView()
        list.setAccessibilityIdentifier(SidebarView.listIdentifier)
        middle.addSubview(list)
        root.addSubview(middle)

        XCTAssertTrue(
            SidebarReturnKey.view(in: root, identified: SidebarView.listIdentifier) === list,
            "found however deep it sits"
        )
        XCTAssertNil(SidebarReturnKey.view(in: root, identified: "somethingElse"))
    }
}
