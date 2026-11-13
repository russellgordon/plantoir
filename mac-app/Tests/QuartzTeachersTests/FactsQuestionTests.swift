import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The facts sheet's shape (#834), measured on the laid-out sheet: every
/// row fits without scrolling, a long backup name included, and the message
/// comes before the rows. And the Reference Courses heading's button opens
/// exactly the heading's menu.
@MainActor
final class FactsQuestionTests: XCTestCase {

    // MARK: - Functions

    func allViews(in view: NSView) -> [NSView] {
        var found: [NSView] = [view]
        for child in view.subviews {
            found.append(contentsOf: allViews(in: child))
        }
        return found
    }

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

    /// The question as Replace It… asks it, with a backup name as long as a
    /// real one gets.
    static func replaceQuestion(folder: String, date: String?) -> FactsQuestion {
        return FactsQuestion(
            title: ReferenceReplaceWording.title(course: "ICS3U", group: "2025–26"),
            message: ReferenceReplaceWording.message,
            rows: ReferenceReplaceWording.rows(
                sections: "3 sections", pages: "140 pages", size: "467 MB", date: date, folder: folder
            ),
            action: ReferenceReplaceWording.confirmButton,
            cancel: ReferenceReplaceWording.cancelButton
        )
    }

    /// Lays the sheet out in a window off the screen and reports, for the
    /// form's scroll view, the height it shows and the height of what it
    /// holds.
    func formHeights(of question: FactsQuestion) throws -> (shown: CGFloat, content: CGFloat) {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: 600, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let sheet: FactsQuestionSheet = FactsQuestionSheet(question: question, identifier: "test", goAhead: {}, cancel: {})
        let host: NSHostingView<FactsQuestionSheet> = NSHostingView(rootView: sheet)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        defer {
            window.contentView = nil
            window.close()
        }
        _ = runUntil(timeout: 0.5) { false }
        host.layoutSubtreeIfNeeded()
        var scroller: NSScrollView?
        for view in allViews(in: host) {
            if let found = view as? NSScrollView {
                scroller = found
            }
        }
        let form: NSScrollView = try XCTUnwrap(scroller, "the form's scroll view was not found")
        let content: CGFloat = form.documentView?.frame.height ?? 0
        return (shown: form.contentView.bounds.height, content: content)
    }

    // MARK: - Tests

    func testEveryRowFitsWithoutScrolling() throws {
        let questions: [(String, FactsQuestion)] = [
            ("Replace It…", FactsQuestionTests.replaceQuestion(folder: "ICS3U-2025", date: "12 November 2026")),
            ("Replace It…, no date", FactsQuestionTests.replaceQuestion(folder: "ICS3U-2025", date: nil)),
            ("Replace It…, a long folder", FactsQuestionTests.replaceQuestion(folder: "SPH4U-Physics-Section-Two-2025-26", date: "12 November 2026")),
            ("Remove Group", ReferenceGroupWording.removeGroupQuestion(group: "Electives", courseCount: 12)),
            ("Start the Groups Again", ReferenceGroupWording.startAgainQuestion),
        ]
        for (what, question) in questions {
            let heights: (shown: CGFloat, content: CGFloat) = try formHeights(of: question)
            XCTAssertGreaterThan(heights.content, 0, what)
            XCTAssertGreaterThanOrEqual(
                heights.shown + 0.5, heights.content,
                "\(what): the form shows \(heights.shown) points of \(heights.content), so a row is cut off"
            )
        }
    }

    /// VoiceOver order: the title, then the message, then the rows; each row
    /// is one element, read as "label, value".
    func testTheMessageComesBeforeTheRowsAndEachRowIsOneElement() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/Views/Helpers/FactsQuestionSheet.swift")
        let text: String = try String(contentsOf: url, encoding: .utf8)
        XCTAssertNotNil(text.range(of: ".sheetTitle(question.title, identifier: \"\\(identifier)Title\", explanation: {\n            Text(question.message)"))
        XCTAssertNotNil(text.range(of: "LabeledContent(row.label)"))
        XCTAssertNotNil(text.range(of: ".accessibilityElement(children: .combine)"))
        XCTAssertNotNil(text.range(of: ".defaultButton(isEnabled: true)"), "Cancel is the default")
        XCTAssertNotNil(text.range(of: ".onExitCommand {\n            cancel()"), "Escape is Cancel")
    }

    /// The heading's button opens exactly what the right-click offers,
    /// because both draw `ReferenceShelfHeadingMenu`; measured on the button
    /// AppKit draws for it.
    func testTheHeadingButtonOpensTheHeadingsMenu() throws {
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: 280, height: 60),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let host: NSHostingView<AnyView> = NSHostingView(rootView: AnyView(ReferenceShelfHeading().environment(workspace)))
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        _ = runUntil(timeout: 0.5) { false }
        host.layoutSubtreeIfNeeded()
        var button: NSPopUpButton?
        for view in allViews(in: host) {
            if let found = view as? NSPopUpButton {
                button = found
            }
        }
        let shown: NSPopUpButton = try XCTUnwrap(button, "no menu button on the heading")
        let frame: NSRect = shown.convert(shown.bounds, to: nil)
        XCTAssertTrue(host.convert(host.bounds, to: nil).contains(frame), "the button is outside the heading \(frame)")
        XCTAssertTrue(shown.isEnabled, "the button is never disabled")
        // Its items are filled in only as it opens, which a test cannot do
        // without the screen; what it holds is pinned by the source below.
        let source: String = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("QuartzTeachers/Views/ReferenceShelfHeading.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(source.components(separatedBy: "ReferenceShelfHeadingMenu()").count - 1, 2, "the button and the right-click draw one list")
        let heading: String = String(source[source.startIndex..<(source.range(of: "struct ReferenceShelfHeadingMenu")?.lowerBound ?? source.endIndex)])
        XCTAssertNil(heading.range(of: ".disabled("), "the button itself is never disabled")
        XCTAssertNotNil(heading.range(of: ".accessibilityLabel(ReferenceGroupWording.headingMenuLabel)"))
        XCTAssertNotNil(heading.range(of: ".menuStyle(.borderlessButton)"), "the sidebar's own borderless control")
    }
}
