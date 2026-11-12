import AppKit
import Observation
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The course page's two tabs are never layered (#708, 708 fix review H1):
/// with Planning showing, the settings form is not in the window at all, so
/// no setting can take a key; what the teacher typed lives in the course's
/// model and survives the switch; a switch clears Undo; and ⌘S on Planning
/// saves what was typed on Settings.
///
/// Each test draws the REAL page content (`CourseDetailContent`, with the
/// real `CourseSettingsView`) in an `NSWindow` that is never put on screen,
/// and asserts on what is in its view tree or its model. None depends on the
/// window being key.
///
/// To see them fail on the layered code: in `CourseDetailContent.body`,
/// replace the `if showsPlanning { … } else { … }` with
/// `ZStack { CourseSettingsView(course: course, session: session); if showsPlanning { planning() } }`.
/// `testWithPlanningShowingNoSettingsControlIsInTheWindow` then finds the
/// form's fields, box and tables, and `testTheFooterBoxTakesNoKeyOnPlanning`
/// sees the footer change. `testASwitchClearsUndo` fails when the
/// `removeAllActions()` line in `CourseDetailTabs.choose` is deleted, and
/// `testADraftSurvivesASwitchAndSaveOnPlanningWritesIt` when
/// `planningCommands`' `perform` stops calling the form's Save, and
/// `testASaveOnPlanningThatFailsTakesTheTeacherToSettings` when it stops
/// calling `showSettings` after `afterASave` says so.
@MainActor
final class CourseDetailStructureTests: XCTestCase {

    // MARK: - Types

    /// Which tab is showing, flipped by the test as the switch would.
    @Observable
    final class Shown {

        // MARK: - Stored properties

        var planning: Bool = false
    }

    /// `CourseDetailContent` with a plain stand-in for the Planning tab.
    struct Page: View {

        // MARK: - Stored properties

        let course: Course
        let session: CourseSettingsSession
        let shown: Shown

        // MARK: - Body

        var body: some View {
            CourseDetailContent(course: course, session: session, showsPlanning: shown.planning) {
                Color.white
            }
        }
    }

    // MARK: - Stored properties

    nonisolated(unsafe) private var rootURL: URL!

    /// The trail a Save writes to, kept out of the real one.
    nonisolated(unsafe) private var previousStore: ProblemReportStore?

    // MARK: - Functions

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("course-detail-structure-\(UUID().uuidString)", isDirectory: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail", isDirectory: true))
    }

    override func tearDown() async throws {
        if let previousStore {
            ActivityTrail.store = previousStore
        }
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// Runs the main run loop until `condition` holds or `timeout` passes:
    /// a wait for SwiftUI to apply a change, never a fixed pause.
    private func runUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end: Date = Date(timeIntervalSinceNow: timeout)
        while Date() < end {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }

    private func allViews(under view: NSView) -> [NSView] {
        var found: [NSView] = [view]
        for child in view.subviews {
            found.append(contentsOf: allViews(under: child))
        }
        return found
    }

    /// Every control in the tree that a key could edit or act on.
    private func settingsControls(under view: NSView) -> [String] {
        var found: [String] = []
        for candidate in allViews(under: view) {
            if let text = candidate as? NSTextView, text.isEditable {
                found.append("NSTextView")
            } else if let field = candidate as? NSTextField, field.isEditable {
                found.append("NSTextField")
            } else if candidate is NSTableView {
                found.append(String(describing: type(of: candidate)))
            } else if let control = candidate as? NSControl, control.isEnabled, control.acceptsFirstResponder {
                found.append(String(describing: type(of: control)))
            }
        }
        return found
    }

    private func editableTextView(under view: NSView, holding text: String) -> NSTextView? {
        for candidate in allViews(under: view) {
            if let textView = candidate as? NSTextView, textView.isEditable, textView.string == text {
                return textView
            }
        }
        return nil
    }

    /// The Course name field, found by what it shows. Not by its
    /// identifier: measured on the first real run, SwiftUI puts
    /// `courseNameField` on the field's accessibility element, not on the
    /// `NSTextField`, so a lookup by the view's identifier found nothing.
    private func courseNameField(under view: NSView, showing name: String) -> NSTextField? {
        for candidate in allViews(under: view) {
            if let field = candidate as? NSTextField, field.isEditable, field.stringValue == name {
                return field
            }
        }
        return nil
    }

    private func window(showing page: Page) -> (NSWindow, NSHostingView<Page>) {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -6000, y: -6000, width: 700, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host: NSHostingView<Page> = NSHostingView(rootView: page)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    // MARK: - Tests

    func testWithPlanningShowingNoSettingsControlIsInTheWindow() throws {
        let course: Course = try CourseSettingsGestureScript.makeCourse(in: try XCTUnwrap(rootURL))
        let shown: Shown = Shown()
        let (window, host) = window(showing: Page(course: course, session: CourseSettingsSession(), shown: shown))
        defer {
            window.close()
        }
        let name: String = course.configuration.courseName
        XCTAssertTrue(runUntil(timeout: 5) { courseNameField(under: host, showing: name) != nil }, "Settings draws its form")
        let onSettings: [String] = settingsControls(under: host)
        XCTAssertTrue(onSettings.contains("NSTextView"), "the probe sees the footer box: \(onSettings)")
        XCTAssertTrue(onSettings.contains("NSTextField"), "the probe sees the fields: \(onSettings)")

        shown.planning = true
        let gone: Bool = runUntil(timeout: 5) {
            return settingsControls(under: host).isEmpty
        }
        XCTAssertTrue(gone, "with Planning showing the tree still holds: \(settingsControls(under: host))")
    }

    func testTheFooterBoxTakesNoKeyOnPlanning() throws {
        let course: Course = try CourseSettingsGestureScript.makeCourse(in: try XCTUnwrap(rootURL))
        course.configuration.footerHTML = "Footer text"
        let shown: Shown = Shown()
        let (window, host) = window(showing: Page(course: course, session: CourseSettingsSession(), shown: shown))
        defer {
            window.close()
        }
        var box: NSTextView? = nil
        XCTAssertTrue(runUntil(timeout: 5) {
            box = editableTextView(under: host, holding: "Footer text")
            return box != nil
        }, "Settings draws the footer box")
        let footer: NSTextView = try XCTUnwrap(box)
        XCTAssertTrue(window.makeFirstResponder(footer), "the footer box takes the keyboard on Settings")
        footer.insertText("km", replacementRange: footer.selectedRange())
        XCTAssertTrue(runUntil(timeout: 2) { course.configuration.footerHTML == "Footer textkm" }, "typing on Settings edits it")

        var tab: CourseDetailTab = .settings
        CourseDetailTabs.choose(.planning, current: &tab, undoManager: window.undoManager)
        shown.planning = true
        XCTAssertTrue(runUntil(timeout: 5) { editableTextView(under: host, holding: "Footer textkm") == nil })

        // A Space to scroll the plan, and a paste, to whatever has the keyboard.
        window.firstResponder?.insertText(" ")
        window.firstResponder?.insertText("PASTED")
        if let editor = window.firstResponder as? NSTextView {
            editor.insertText(" PASTED", replacementRange: editor.selectedRange())
        }
        XCTAssertEqual(course.configuration.footerHTML, "Footer textkm", "a key on Planning edited the hidden footer")
        XCTAssertFalse(window.undoManager?.canUndo ?? false, "Undo on Planning would act on Settings")

        CourseDetailTabs.choose(.settings, current: &tab, undoManager: window.undoManager)
        shown.planning = false
        XCTAssertTrue(runUntil(timeout: 5) { editableTextView(under: host, holding: "Footer textkm") != nil },
                      "back on Settings the box shows the draft as it was left")
        XCTAssertFalse(window.firstResponder is NSTextView, "and nothing in particular has the keyboard")
    }

    func testASwitchClearsUndo() {
        let undo: UndoManager = UndoManager()
        undo.groupsByEvent = false
        let target: NSObject = NSObject()
        undo.beginUndoGrouping()
        undo.registerUndo(withTarget: target) { (_: NSObject) in
        }
        undo.endUndoGrouping()
        var tab: CourseDetailTab = .settings
        CourseDetailTabs.choose(.settings, current: &tab, undoManager: undo)
        XCTAssertTrue(undo.canUndo, "choosing the tab already showing changes nothing")
        CourseDetailTabs.choose(.planning, current: &tab, undoManager: undo)
        XCTAssertEqual(tab, .planning)
        XCTAssertFalse(undo.canUndo, "a switch leaves nothing to undo")
    }

    func testADraftSurvivesASwitchAndSaveOnPlanningWritesIt() throws {
        let root: URL = try XCTUnwrap(rootURL)
        let course: Course = try CourseSettingsGestureScript.makeCourse(in: root)
        let session: CourseSettingsSession = CourseSettingsSession()
        let shown: Shown = Shown()
        let (window, host) = window(showing: Page(course: course, session: session, shown: shown))
        defer {
            window.close()
        }
        var found: NSTextField? = nil
        XCTAssertTrue(runUntil(timeout: 5) {
            found = courseNameField(under: host, showing: course.configuration.courseName)
            return found != nil
        })
        let field: NSTextField = try XCTUnwrap(found)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor: NSTextView = try XCTUnwrap(window.firstResponder as? NSTextView, "a field editor edits Course name")
        editor.selectAll(nil)
        editor.insertText("Typed on Settings", replacementRange: editor.selectedRange())
        XCTAssertTrue(runUntil(timeout: 2) { course.configuration.courseName == "Typed on Settings" })

        var tab: CourseDetailTab = .settings
        CourseDetailTabs.choose(.planning, current: &tab, undoManager: window.undoManager)
        shown.planning = true
        XCTAssertTrue(runUntil(timeout: 5) { courseNameField(under: host, showing: "Typed on Settings") == nil }, "the form left the window")
        XCTAssertEqual(course.configuration.courseName, "Typed on Settings", "the draft outlives the form")
        XCTAssertTrue(course.configuration.hasUnsavedChanges)

        // Course ▸ Save on the Planning tab.
        var sentToSettings: Int = 0
        let commands: CourseSettingsCommands = CourseDetailTabs.planningCommands(
            course: course, session: session, showSettings: {
                sentToSettings += 1
            }
        )
        XCTAssertTrue(commands.maySave)
        XCTAssertFalse(commands.mayRevert, "Revert is not offered out of sight")
        XCTAssertEqual(commands.revertNote, PlanningWording.revertOnPlanning, "and says why")
        commands.perform(.saveCourseSettings)
        // Read at once, before anything waits: "Saved ✓" fades on a clock
        // of its own (708 fix review 2, L4).
        XCTAssertTrue(session.didJustSave, "the Planning tab says Saved")
        XCTAssertNil(session.saveProblem, "the Save on Planning reported no problem")
        XCTAssertEqual(sentToSettings, 0, "a Save that worked stays on Planning")
        let saved: CourseConfiguration = try CourseConfiguration(contentsOf: course.configFileURL)
        XCTAssertEqual(saved.courseName, "Typed on Settings", "Save on Planning wrote what was typed on Settings")
        XCTAssertFalse(course.configuration.hasUnsavedChanges)

        CourseDetailTabs.choose(.settings, current: &tab, undoManager: window.undoManager)
        shown.planning = false
        var back: NSTextField? = nil
        XCTAssertTrue(runUntil(timeout: 5) {
            back = courseNameField(under: host, showing: "Typed on Settings")
            return back != nil
        })
        XCTAssertEqual(back?.stringValue, "Typed on Settings")
    }

    /// `unitPlanning.tab.saveOnPlanning.cases`, through the rule.
    func testWhatASaveOnPlanningDoesIsTheContracts() throws {
        let unitPlanning: [String: Any] = try SharedRulesContractTests.section("unitPlanning")
        let tab: [String: Any] = try XCTUnwrap(unitPlanning["tab"] as? [String: Any])
        let block: [String: Any] = try XCTUnwrap(tab["saveOnPlanning"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 4)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let session: CourseSettingsSession = CourseSettingsSession()
            if try XCTUnwrap(testCase["problem"] as? Bool) {
                session.saveProblem = "a reason"
            }
            if try XCTUnwrap(testCase["notice"] as? Bool) {
                session.saveNotice = SettingsSaveNotice(sentences: ["a notice"], sectionsToPreviewAgain: [])
            }
            XCTAssertEqual(CourseDetailTabs.afterASave(session).rawValue, testCase["expect"] as? String, name)
        }
    }

    /// A Save on Planning that fails is never silent: the page goes to
    /// Settings, where the form's own sentence is (708 fix review 2, L3).
    /// The course's folder is made read-only, so the write fails at once.
    func testASaveOnPlanningThatFailsTakesTheTeacherToSettings() throws {
        let course: Course = try CourseSettingsGestureScript.makeCourse(in: try XCTUnwrap(rootURL))
        course.configuration.courseName = "Typed on Settings"
        let session: CourseSettingsSession = CourseSettingsSession()
        let folder: String = course.directoryURL.path
        let file: String = course.configFileURL.path
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file)
        }
        var sentToSettings: Int = 0
        let commands: CourseSettingsCommands = CourseDetailTabs.planningCommands(
            course: course, session: session, showSettings: {
                sentToSettings += 1
            }
        )
        commands.perform(.saveCourseSettings)
        XCTAssertNotNil(session.saveProblem, "the write failed and the form has its sentence")
        XCTAssertFalse(session.didJustSave)
        XCTAssertEqual(sentToSettings, 1, "and the teacher is taken to Settings to read it")
    }
}
