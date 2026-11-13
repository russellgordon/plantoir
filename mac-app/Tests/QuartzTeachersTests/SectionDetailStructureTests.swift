import AppKit
import Observation
import SwiftUI
import WebKit
import XCTest
@testable import QuartzTeachers

/// A section's tabs are never layered (#793, the coverage plan review's H1):
/// with Coverage or Problems showing, the section's preview is not in the
/// window at all, so no key reaches it, and the browser commands are not
/// offered to it; a switch back finds the SAME web view with its page.
///
/// Each test draws the real `SectionTabContent` with the real
/// `WebPreviewView` and `WebPreviewController` in an `NSWindow` that is never
/// put on screen, and asserts on what is in its view tree. None depends on
/// the window being key. The stand-ins for Coverage and Problems are plain
/// colours: what is under test is that the preview is NOT there.
///
/// To see them fail on the layered shape: in `SectionTabContent.body`,
/// replace the `if … else if … else` with
/// `ZStack { website(); if showing == .coverage { coverage() }; if showing == .problems { problems() } }`.
/// `testWithCoverageShowingThePreviewIsNotInTheWindow` and
/// `testWithProblemsShowingThePreviewIsNotInTheWindow` then find the web
/// view, and `testTheKeyboardLeavesThePreviewWithIt` finds it still first
/// responder.
@MainActor
final class SectionDetailStructureTests: XCTestCase {

    // MARK: - Types

    /// Which tab is showing, flipped by the test as the switch would.
    @Observable
    final class Shown {

        // MARK: - Stored properties

        var tab: SectionTab = .website
    }

    /// `SectionTabContent` with the real preview on Website.
    struct Page: View {

        // MARK: - Stored properties

        let shown: Shown
        let controller: WebPreviewController
        let url: URL

        // MARK: - Body

        var body: some View {
            SectionTabContent(showing: shown.tab) {
                ZStack {
                    Color.white
                    WebPreviewView(controller: controller, url: url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } coverage: {
                Color.blue
            } problems: {
                Color.green
            }
        }
    }

    // MARK: - Functions

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

    /// Whether THIS web view, the preview's own instance, is in the tree.
    private func holds(_ webView: WKWebView, under view: NSView) -> Bool {
        for candidate in allViews(under: view) {
            if candidate === webView {
                return true
            }
        }
        return false
    }

    private func window(showing page: Page) -> (NSWindow, NSHostingView<Page>) {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -6000, y: -6000, width: 700, height: 500),
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

    private static let pageURL: URL = URL(string: "about:blank#the-page-the-teacher-left")!

    // MARK: - Tests

    func testWithCoverageShowingThePreviewIsNotInTheWindow() throws {
        let shown: Shown = Shown()
        let controller: WebPreviewController = WebPreviewController()
        let (window, host) = window(showing: Page(shown: shown, controller: controller, url: SectionDetailStructureTests.pageURL))
        defer {
            window.close()
        }
        XCTAssertTrue(runUntil(timeout: 5) { holds(controller.webView, under: host) }, "Website draws the preview")
        XCTAssertTrue(runUntil(timeout: 10) { controller.webView.url != nil && !controller.webView.isLoading }, "the page loaded")
        // As WebKit spells it once loaded (it writes the '#' of an
        // about:blank address percent-encoded).
        let loaded: URL? = controller.webView.url

        shown.tab = .coverage
        XCTAssertTrue(runUntil(timeout: 5) { !holds(controller.webView, under: host) },
                      "with Coverage showing, the preview is still in the window")

        shown.tab = .website
        XCTAssertTrue(runUntil(timeout: 5) { holds(controller.webView, under: host) }, "back on Website the SAME web view is there")
        XCTAssertEqual(controller.webView.url, loaded, "with the page it had")
        XCTAssertFalse(controller.webView.isLoading, "and nothing loading it again")
    }

    func testWithProblemsShowingThePreviewIsNotInTheWindow() throws {
        let shown: Shown = Shown()
        let controller: WebPreviewController = WebPreviewController()
        let (window, host) = window(showing: Page(shown: shown, controller: controller, url: SectionDetailStructureTests.pageURL))
        defer {
            window.close()
        }
        XCTAssertTrue(runUntil(timeout: 5) { holds(controller.webView, under: host) })
        shown.tab = .problems
        XCTAssertTrue(runUntil(timeout: 5) { !holds(controller.webView, under: host) },
                      "with Problems showing, the preview is still in the window")
    }

    /// The preview had the keyboard on Website; on Coverage it cannot,
    /// because it is not in the window, and a key sent to whatever has the
    /// keyboard goes nowhere near it.
    func testTheKeyboardLeavesThePreviewWithIt() throws {
        let shown: Shown = Shown()
        let controller: WebPreviewController = WebPreviewController()
        let (window, host) = window(showing: Page(shown: shown, controller: controller, url: SectionDetailStructureTests.pageURL))
        defer {
            window.close()
        }
        XCTAssertTrue(runUntil(timeout: 5) { holds(controller.webView, under: host) })
        XCTAssertTrue(window.makeFirstResponder(controller.webView), "the preview takes the keyboard on Website")

        shown.tab = .coverage
        XCTAssertTrue(runUntil(timeout: 5) { !holds(controller.webView, under: host) })
        XCTAssertFalse(window.firstResponder === controller.webView, "the hidden preview kept the keyboard")
        if let responder = window.firstResponder as? NSView {
            XCTAssertFalse(responder.isDescendant(of: controller.webView), "something inside the hidden preview kept the keyboard")
        }
    }

    // MARK: - The real page's wiring (the 793b review's M3)

    private func readSource(_ relativePath: String) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        return text.components(separatedBy: needle).count - 1
    }

    /// The tests above draw `SectionTabContent` with stand-ins; this reads
    /// the real page's source, so a preview drawn OUTSIDE the chosen-tab
    /// switch, or a focused value that no longer asks which tab shows,
    /// fails here. To see it fail: in `SectionDetailView.sectionLayout`,
    /// wrap `SectionTabContent(…)` in `ZStack { websiteLayers; … }`, or
    /// delete `&& previewTakesCommands` from the focused value.
    func testThePagesPreviewIsDrawnOnlyThroughTheChosenTab() throws {
        let view: String = try readSource("QuartzTeachers/Views/Section/SectionDetailView.swift")
        let coverage: String = try readSource("QuartzTeachers/Views/Section/SectionDetailCoverage.swift")
        XCTAssertEqual(occurrences(of: "WebPreviewView(", in: view), 0, "the page draws no preview of its own")
        XCTAssertEqual(occurrences(of: "WebPreviewView(", in: coverage), 1, "one preview, in websiteLayers")
        let layers: Range<String.Index> = try XCTUnwrap(coverage.range(of: "var websiteLayers: some View {"))
        let problems: Range<String.Index> = try XCTUnwrap(coverage.range(of: "var coverageTab: some View {"))
        let preview: Range<String.Index> = try XCTUnwrap(coverage.range(of: "WebPreviewView("))
        XCTAssertTrue(preview.lowerBound > layers.lowerBound && preview.lowerBound < problems.lowerBound,
                      "the preview is inside websiteLayers")
        XCTAssertEqual(occurrences(of: "websiteLayers", in: view), 1, "websiteLayers is used once in the page")
        let content: Range<String.Index> = try XCTUnwrap(view.range(of: "SectionTabContent(showing: selectedTab) {\n                websiteLayers\n"),
                                                         "and only as the Website branch of SectionTabContent")
        XCTAssertFalse(view[view.startIndex..<content.lowerBound].hasSuffix("ZStack {\n            "), "not layered")
        XCTAssertEqual(occurrences(of: "ProblemsTableView(", in: view), 0, "Problems is drawn through problemsTab")
        XCTAssertTrue(view.contains(".focusedSceneValue(\\.previewController, previewURL != nil && previewTakesCommands ? previewController : nil)"),
                      "the browser commands reach the preview only on Website")
        XCTAssertEqual(occurrences(of: "|| !previewTakesCommands", in: view), 3, "Back, Forward and Reload are off when it is not shown")
    }

    /// The browser commands reach the preview only on Website: the rule the
    /// page's focused value and its toolbar's Back, Forward and Reload read.
    func testOnlyWebsiteOffersThePreviewTheBrowserCommands() {
        XCTAssertTrue(SectionTabs.previewTakesCommands(showing: .website))
        XCTAssertFalse(SectionTabs.previewTakesCommands(showing: .coverage))
        XCTAssertFalse(SectionTabs.previewTakesCommands(showing: .problems))
    }
}
