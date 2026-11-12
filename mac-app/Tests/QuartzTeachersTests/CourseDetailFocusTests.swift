import AppKit
import Observation
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// While the Planning tab covers the course's settings, no key can reach a
/// setting (#708, implementation review H1).
///
/// The review measured the fault in an offscreen window: a field focused on
/// Settings stayed the window's first responder after Planning was drawn
/// over it, and a Space and an "x" typed "on the plan" replaced the course's
/// name. This hosts the REAL form the same way (an `NSWindow` that is never
/// put on screen), focuses Course name, covers the form as `CourseDetailView`
/// does, and types.
///
/// To see it fail on the old code: delete the line `.disabled(isCovered)`
/// in `CourseSettingsView.body` (the code before this fix had no way to
/// disable the form at all), build for testing, and run this class: the
/// first responder is still the field's editor and the name changes.
@MainActor
final class CourseDetailFocusTests: XCTestCase {

    // MARK: - Types

    /// Whether the form is covered, flipped by the test as the tab would.
    @Observable
    final class Cover {

        // MARK: - Stored properties

        var isCovered: Bool = false
    }

    /// The form as `CourseDetailView` draws it, with the cover from the test.
    struct CoveredForm: View {

        // MARK: - Stored properties

        let course: Course
        let cover: Cover

        // MARK: - Body

        var body: some View {
            ZStack {
                CourseSettingsView(course: course, isCovered: cover.isCovered)
                if cover.isCovered {
                    Color.white
                }
            }
        }
    }

    // MARK: - Stored properties

    nonisolated(unsafe) private var rootURL: URL!

    // MARK: - Functions

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("course-detail-focus-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// Runs the main run loop until `condition` holds or `timeout` passes;
    /// answers whether it held. A wait for SwiftUI to apply a change, never
    /// a fixed pause.
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

    /// A few turns of the run loop, so a binding SwiftUI updates on the next
    /// pass has had its pass before the test reads it.
    private func turnTheRunLoop() {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    private func editableField(identifier: String, in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable, field.accessibilityIdentifier() == identifier {
            return field
        }
        for child in view.subviews {
            if let found = editableField(identifier: identifier, in: child) {
                return found
            }
        }
        return nil
    }

    private func firstEditableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        for child in view.subviews {
            if let found = firstEditableField(in: child) {
                return found
            }
        }
        return nil
    }

    // MARK: - Tests

    func testKeysPressedOnThePlanNeverReachAHiddenSetting() throws {
        let course: Course = try CourseSettingsGestureScript.makeCourse(in: try XCTUnwrap(rootURL))
        let nameBefore: String = course.configuration.courseName
        let cover: Cover = Cover()
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -5000, y: -5000, width: 700, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            window.close()
        }
        let host: NSHostingView<CoveredForm> = NSHostingView(rootView: CoveredForm(course: course, cover: cover))
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        var found: NSTextField? = nil
        _ = runUntil(timeout: 3) {
            found = editableField(identifier: "courseNameField", in: host) ?? firstEditableField(in: host)
            return found != nil
        }
        guard let field = found else {
            throw XCTSkip("The form drew no text field in a window that is not on screen.")
        }
        XCTAssertTrue(window.makeFirstResponder(field), "Course name takes the keyboard on Settings")
        XCTAssertTrue(runUntil(timeout: 2) { window.firstResponder is NSTextView }, "a field editor is editing Course name")

        cover.isCovered = true
        let letGo: Bool = runUntil(timeout: 3) {
            return !(window.firstResponder is NSTextView)
        }
        XCTAssertTrue(letGo, "covered, the form lets go of the keyboard: \(String(describing: window.firstResponder))")

        // Space to scroll the plan, then a letter, the way the review typed.
        if let editor = window.firstResponder as? NSTextView {
            editor.insertText(" ", replacementRange: editor.selectedRange())
            editor.insertText("x", replacementRange: editor.selectedRange())
        } else {
            window.firstResponder?.insertText(" ")
            window.firstResponder?.insertText("x")
        }
        turnTheRunLoop()
        XCTAssertEqual(course.configuration.courseName, nameBefore, "a key pressed on the plan edited a hidden setting")
        XCTAssertFalse(course.configuration.hasUnsavedChanges, "nothing for Save to write")

        // Tab cannot walk into the covered form either.
        window.selectNextKeyView(nil)
        turnTheRunLoop()
        XCTAssertFalse(window.firstResponder is NSTextView, "Tab walked into the covered form")
    }

    /// An edit made on Settings survives the cover and is still there,
    /// unsaved, when the form is uncovered: the half the review confirmed,
    /// kept by this fix.
    func testAnEditMadeOnSettingsSurvivesALookAtThePlan() throws {
        let course: Course = try CourseSettingsGestureScript.makeCourse(in: try XCTUnwrap(rootURL))
        let cover: Cover = Cover()
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -5000, y: -5000, width: 700, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            window.close()
        }
        window.contentView = NSHostingView(rootView: CoveredForm(course: course, cover: cover))
        course.configuration.courseName = "Edited on Settings"
        cover.isCovered = true
        turnTheRunLoop()
        cover.isCovered = false
        turnTheRunLoop()
        XCTAssertEqual(course.configuration.courseName, "Edited on Settings")
        XCTAssertTrue(course.configuration.hasUnsavedChanges)
    }
}
