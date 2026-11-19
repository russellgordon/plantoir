import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// What a SwiftUI alert and a sheet's Cancel do with Escape and Return,
/// measured on the buttons AppKit draws (#987), because two of #987's
/// decisions rest on it:
///
/// - **In a SwiftUI `.alert`, a plain button beside a Cancel takes Return,
///   whatever is written on it.** `.keyboardShortcut(nil)` does not take it
///   away, nor does `.keyboardShortcut(.cancelAction)` on the Cancel. Only
///   the destructive role leaves the go-ahead with no key. So an alert cannot
///   have both "not red" and "no default button", which is why the alerts
///   for deliberately chosen actions (Remove, Delete, Cancel It, Stop
///   Sharing) keep their red and are a question for Russell on #987, while
///   `FactsQuestionSheet`, a sheet, has both.
///
/// Whether a picker field's open list still gets the first Escape once its
/// sheet's Cancel carries `.cancelAction` cannot be measured here: a window
/// in a test is never the key window of an active application, so AppKit
/// never offers it the key equivalent first. That was measured in a run of
/// the app instead (`documentation/09-mac-app.md`, #987).
@MainActor
final class AlertKeysTests: XCTestCase {

    // MARK: - Types

    /// The buttons an alert is given.
    enum Layout: CaseIterable {
        case plainAction
        case plainActionWithNoShortcut
        case plainActionWithCancelKey
        case destructiveAction
    }

    /// An alert with one of the layouts, showing at once.
    struct AlertPage: View {

        // MARK: - Stored properties

        let layout: Layout

        @State var showing: Bool = true

        // MARK: - Body

        var body: some View {
            Color.white
                .alert("Remove it?", isPresented: $showing) {
                    switch layout {
                    case .plainAction:
                        Button("Cancel", role: .cancel) {
                        }
                        Button("Remove") {
                        }
                    case .plainActionWithNoShortcut:
                        Button("Cancel", role: .cancel) {
                        }
                        Button("Remove") {
                        }
                        .keyboardShortcut(nil)
                    case .plainActionWithCancelKey:
                        Button("Cancel", role: .cancel) {
                        }
                        .keyboardShortcut(.cancelAction)
                        Button("Remove") {
                        }
                    case .destructiveAction:
                        Button("Cancel", role: .cancel) {
                        }
                        .keyboardShortcut(.cancelAction)
                        Button("Remove", role: .destructive) {
                        }
                    }
                } message: {
                    Text("A question.")
                }
        }
    }

    // MARK: - Functions

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

    private func allViews(in view: NSView?) -> [NSView] {
        guard let view else {
            return []
        }
        var found: [NSView] = [view]
        for child in view.subviews {
            found.append(contentsOf: allViews(in: child))
        }
        return found
    }

    private func window(showing view: some View) -> NSWindow {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: 700, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(runUntil(timeout: 5) { window.attachedSheet != nil }, "the sheet opened")
        _ = runUntil(timeout: 0.8) { false }
        return window
    }

    private func close(_ window: NSWindow) {
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Each button the alert draws, with its key.
    private func keys(of layout: Layout) -> [String: String] {
        let shown: NSWindow = window(showing: AlertPage(layout: layout))
        var keys: [String: String] = [:]
        for view in allViews(in: shown.attachedSheet?.contentView) {
            if let button = view as? NSButton, !button.title.isEmpty {
                keys[button.title] = button.keyEquivalent
            }
        }
        close(shown)
        return keys
    }

    // MARK: - Tests

    func testInASwiftUIAlertOnlyTheDestructiveRoleKeepsReturnOffTheAction() {
        for layout in Layout.allCases {
            let found: [String: String] = keys(of: layout)
            XCTAssertEqual(found["Cancel"], "\u{1b}", "\(layout): Cancel answers Escape (\(found))")
            if layout == .destructiveAction {
                XCTAssertEqual(found["Remove"], "", "\(layout): a destructive Remove takes no key (\(found))")
            } else {
                XCTAssertEqual(found["Remove"], "\r", "\(layout): a plain Remove takes Return (\(found)); if this fails, an alert can now be both not red and without a default, and #987's question about the alerts can be answered without moving them to sheets")
            }
        }
    }
}
