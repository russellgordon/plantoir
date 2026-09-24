import Foundation
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Issue #266 redrew every folder and file list as a table and must not have
/// changed a byte of what is saved. The fixed script in
/// `ListGestureScript.swift` was run through the code as it WAS, before the
/// redraw, and captured into `Tests/Goldens/266-*.json`; this runs the same
/// script through the NEW entry points — each column's own binding in the
/// Sidebar Visibility table, `toggleMembership(of:)` (what Space and a click
/// do on the marks table), `requestRemoval(of:)` (what −, Delete and the
/// row's Remove do) and `add(typedName:)` (what the + popover's Add does) —
/// and asks for the same bytes.
@MainActor
final class ListTableGoldenTests: XCTestCase {

    // MARK: - Stored properties

    var trailFolderURL: URL?
    var previousStore: ProblemReportStore?
    var rootURL: URL?

    // MARK: - Set up

    override func setUp() async throws {
        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-table-golden-trail-\(UUID().uuidString)", isDirectory: true)
        trailFolderURL = folderURL
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-table-golden-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        if let previousStore {
            ActivityTrail.store = previousStore
        }
        if let trailFolderURL {
            try? FileManager.default.removeItem(at: trailFolderURL)
        }
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    // MARK: - Tests

    func testCourseSettingsSavesWhatItSavedBeforeTheTables() throws {
        let root: URL = try XCTUnwrap(rootURL)
        let course: Course = try CourseSettingsGestureScript.makeCourse(in: root)
        let view: CourseSettingsView = CourseSettingsView(course: course)
        CourseSettingsGestureScript.run(through: TableCourseSettingsGestures(view: view))
        let saved: String = try CourseSettingsGestureScript.savedFile(for: course, in: root)
        XCTAssertEqual(saved, try golden(named: "266-course-settings-gestures"))
    }

    func testTheWizardCreatesWhatItCreatedBeforeTheTables() throws {
        let state: WizardListState = WizardListState()
        WizardGestureScript.run(through: TableWizardGestures(state: state))
        XCTAssertEqual(try WizardGestureScript.createdFile(from: state), try golden(named: "266-wizard-gestures"))
    }

    /// A blocked name stays whichever way removal is asked for, and the
    /// teacher is told — the must-fail for a removal path that skips the
    /// list's protection.
    func testABlockedRemovalRemovesNothing() {
        let box: ListBox = ListBox(["All Classes", "Tasks"])
        let editor: StringListEditorView = StringListEditorView(
            title: "Per-section folders",
            items: box.binding,
            protection: { folder in
                if folder == "All Classes" {
                    return .blocked(reason: SpecialNames.classFolderBlocked)
                }
                return .ordinary
            }
        )
        let question: PendingRemoval? = editor.requestRemoval(of: "All Classes")
        XCTAssertNil(question)
        XCTAssertEqual(box.names, ["All Classes", "Tasks"], "A blocked folder was removed")
        XCTAssertTrue(trailText().contains("was told All Classes cannot be removed from Per-section folders — "))

        editor.requestRemoval(of: "Tasks")
        XCTAssertEqual(box.names, ["All Classes"])
    }

    /// A consequential removal asks first and removes nothing until
    /// answered.
    func testAConsequentialRemovalAsksFirst() {
        let box: ListBox = ListBox(["Tasks", "Tests"])
        let editor: StringListEditorView = StringListEditorView(
            title: "Shared folders",
            items: box.binding,
            protection: { folder in
                return .consequential(title: "Remove?", message: "Sure?")
            }
        )
        let question: PendingRemoval? = editor.requestRemoval(of: "Tests")
        XCTAssertEqual(question?.item, "Tests")
        XCTAssertEqual(box.names, ["Tasks", "Tests"], "Removed before the teacher answered")
    }

    /// The + popover's Add is enabled exactly when the name would be added.
    func testAddIsOfferedOnlyForANameThatWouldBeAdded() {
        let items: [String] = ["Tasks", "Notes.md"]
        XCTAssertNil(StringListEditorView.addableName("", to: items, appendingMarkdownExtension: false))
        XCTAssertNil(StringListEditorView.addableName("   ", to: items, appendingMarkdownExtension: false))
        XCTAssertNil(StringListEditorView.addableName("MEDIA", to: items, appendingMarkdownExtension: false))
        XCTAssertNil(StringListEditorView.addableName(" Tasks ", to: items, appendingMarkdownExtension: false))
        XCTAssertNil(StringListEditorView.addableName("Notes", to: items, appendingMarkdownExtension: true))
        XCTAssertEqual(StringListEditorView.addableName("Labs", to: items, appendingMarkdownExtension: false), "Labs")
        XCTAssertEqual(StringListEditorView.addableName("Labs", to: items, appendingMarkdownExtension: true), "Labs.md")
    }

    // MARK: - Functions

    func golden(named name: String) throws -> String {
        let goldenURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Goldens")
            .appendingPathComponent("\(name).json")
        return try String(contentsOf: goldenURL, encoding: .utf8)
    }

    func trailText() -> String {
        guard let trailFolderURL else {
            return ""
        }
        let fileURL: URL = trailFolderURL.appendingPathComponent("activity.txt")
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }
}

/// The gestures, through the tables as they are now.
@MainActor
final class TableCourseSettingsGestures: ListGestureAdapter {

    // MARK: - Stored properties

    let view: CourseSettingsView

    // MARK: - Initializer

    init(view: CourseSettingsView) {
        self.view = view
    }

    // MARK: - Functions

    /// The Sidebar Visibility table exactly as Course Settings builds it.
    func sidebarTable() -> SidebarVisibilityTableView {
        let configuration: CourseConfiguration = view.course.configuration
        return SidebarVisibilityTableView(
            allItems: configuration.allSidebarItems,
            hidden: Binding(
                get: { return configuration.hiddenItems },
                set: { newValue in configuration.hiddenItems = newValue }
            ),
            expandable: Binding(
                get: { return configuration.expandableItems },
                set: { newValue in configuration.expandableItems = newValue }
            )
        )
    }

    func setHidden(_ item: String, to isHidden: Bool) {
        let box: Binding<Bool> = sidebarTable().hideBinding(for: item)
        if box.wrappedValue != isHidden {
            box.wrappedValue = isHidden
        }
    }

    func setExpandable(_ item: String, to isExpandable: Bool) {
        let box: Binding<Bool> = sidebarTable().expandableBinding(for: item)
        if box.wrappedValue != isExpandable {
            box.wrappedValue = isExpandable
        }
    }

    func setCountsForMarks(_ folder: String, to counts: Bool) {
        if view.gradedFoldersBinding.wrappedValue.contains(folder) == counts {
            return
        }
        let list: MembershipToggleListView = MembershipToggleListView(
            title: GradedFolderWording.listTitle,
            allItems: view.gradedFolderChoices,
            members: view.gradedFoldersBinding,
            protection: view.gradedFolderProtection
        )
        list.toggleMembership(of: folder)
    }

    func remove(_ item: String, from list: GestureList) {
        let editor: StringListEditorView = CourseSettingsGestureScript.editor(for: list, of: view)
        if let question = editor.requestRemoval(of: item) {
            // The alert's Remove.
            editor.removeItem(named: question.item)
        }
    }

    func add(typing typedName: String, to list: GestureList) {
        CourseSettingsGestureScript.editor(for: list, of: view).add(typedName: typedName)
    }
}

/// The wizard's gestures, through the tables as they are now.
@MainActor
final class TableWizardGestures: ListGestureAdapter {

    // MARK: - Stored properties

    let state: WizardListState

    // MARK: - Initializer

    init(state: WizardListState) {
        self.state = state
    }

    // MARK: - Functions

    /// The wizard has no Sidebar Visibility table.
    func setHidden(_ item: String, to isHidden: Bool) {}

    func setExpandable(_ item: String, to isExpandable: Bool) {}

    func setCountsForMarks(_ folder: String, to counts: Bool) {
        if state.gradedFolders.contains(folder) == counts {
            return
        }
        let list: MembershipToggleListView = MembershipToggleListView(
            title: GradedFolderWording.listTitle,
            allItems: state.wizard().gradedFolderChoices,
            members: state.gradedFoldersBinding,
            protection: { folder in return self.state.wizard().wizardGradedFolderProtection(for: folder) }
        )
        list.toggleMembership(of: folder)
    }

    func remove(_ item: String, from list: GestureList) {
        let editor: StringListEditorView = state.editor(for: list)
        if let question = editor.requestRemoval(of: item) {
            editor.removeItem(named: question.item)
        }
    }

    func add(typing typedName: String, to list: GestureList) {
        state.editor(for: list).add(typedName: typedName)
    }
}
