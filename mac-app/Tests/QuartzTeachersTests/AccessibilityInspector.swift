import AppKit
import ApplicationServices
import XCTest

/// Walks the app's own accessibility tree (the one VoiceOver and XCUITest
/// read) and collects every piece of text it exposes. Because the tree
/// belongs to this same process, no automation permission is needed.
enum AccessibilityInspector {

    /// What AppKit says about one of the app's windows, which is all the
    /// Space check below needs to know about it.
    struct WindowFacts {

        // MARK: - Stored properties

        /// True for the window the calling test drives — the one its
        /// `WorkspaceModel` lives in — and false for every other window
        /// the app has open (the assistant, Settings, About).
        let isTheTestsWindow: Bool
        let isVisible: Bool
        let isOnTheShowingSpace: Bool
    }

    // MARK: - Functions

    /// Why a test that reads the window through the accessibility tree
    /// cannot check anything in this run, or nil when it can (#249).
    ///
    /// Measured on 2026-09-25: when the test's window is on a Space that is
    /// not showing — a full-screen app or another desktop in front on its
    /// display — macOS leaves it out of the tree, and a walk finds only the
    /// menu bar. Being in the BACKGROUND does not do this: the suite runs
    /// with the app inactive every time, and the walk finds everything.
    ///
    /// Only the test's OWN window counts. Another window of the app being
    /// off the showing Space says nothing about the one the test reads, and
    /// the test's window being gone altogether is a real fault — so both
    /// return nil and the test goes on to fail, as does a window that is on
    /// the showing Space and still missing from the tree.
    static func reasonTheWindowCannotBeRead(
        windows: [WindowFacts],
        testsWindowIsInTheTree: Bool
    ) -> String? {
        if testsWindowIsInTheTree {
            return nil
        }
        for window in windows {
            if window.isTheTestsWindow {
                if !window.isVisible {
                    return nil
                }
                if window.isOnTheShowingSpace {
                    return nil
                }
                return "The test window is on a Space that is not showing (a full-screen app or another desktop is in front on its display), so macOS leaves it out of the accessibility tree and this test cannot see the controls it checks. Show that desktop and run it again (#249)."
            }
        }
        return nil
    }

    /// Skips the calling test, with the reason above, when its window is on
    /// a Space that is not showing. Call it before EVERY walk of the tree —
    /// the desktop can change part-way through a test.
    @MainActor
    static func skipUnlessTheWindowCanBeRead(_ testsWindow: NSWindow?) throws {
        var windows: [WindowFacts] = []
        for window in NSApp.windows {
            let facts: WindowFacts = WindowFacts(
                isTheTestsWindow: window === testsWindow,
                isVisible: window.isVisible,
                isOnTheShowingSpace: window.isOnActiveSpace
            )
            windows.append(facts)
        }
        var testsWindowIsInTheTree: Bool = false
        if let testsWindow {
            testsWindowIsInTheTree = treeHoldsWindow(matching: testsWindow)
        }
        if let reason = reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: testsWindowIsInTheTree) {
            throw XCTSkip(reason)
        }
    }

    /// True when the tree's list of windows has one with this window's
    /// frame. The tree measures from the top of the main display, AppKit
    /// from the bottom, hence the flip.
    @MainActor
    static func treeHoldsWindow(matching window: NSWindow) -> Bool {
        guard let mainDisplay = NSScreen.screens.first else {
            return false
        }
        let appKitFrame: CGRect = window.frame
        let expectedTop: CGFloat = mainDisplay.frame.height - appKitFrame.origin.y - appKitFrame.height

        let applicationElement: AXUIElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windowsValue: CFTypeRef?
        let windowsResult: AXError = AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute as CFString, &windowsValue)
        if windowsResult != .success {
            return false
        }
        guard let treeWindows = windowsValue as? [AXUIElement] else {
            return false
        }
        for treeWindow in treeWindows {
            if let rectangle = frameOf(treeWindow) {
                let sameLeft: Bool = abs(rectangle.origin.x - appKitFrame.origin.x) < 2
                let sameTop: Bool = abs(rectangle.origin.y - expectedTop) < 2
                let sameWidth: Bool = abs(rectangle.width - appKitFrame.width) < 2
                let sameHeight: Bool = abs(rectangle.height - appKitFrame.height) < 2
                if sameLeft && sameTop && sameWidth && sameHeight {
                    return true
                }
            }
        }
        return false
    }

    /// Every title/value/description string in the app's current UI.
    @MainActor
    static func collectAllLabels() -> [String] {
        let applicationElement: AXUIElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var labels: [String] = []
        collectLabels(from: applicationElement, into: &labels, depth: 0)
        return labels
    }

    /// The on-screen rectangle of the element with this identifier — what a
    /// teacher can actually click, rather than what was drawn.
    @MainActor
    static func frame(forIdentifier identifier: String) -> CGRect? {
        let applicationElement: AXUIElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        return findFrame(from: applicationElement, identifier: identifier, depth: 0)
    }

    /// Presses the element with this identifier, the way a click would —
    /// through the accessibility action, so a disabled or missing control
    /// cannot be pressed and the press reports failure instead.
    @MainActor
    static func press(identifier: String) -> Bool {
        let applicationElement: AXUIElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        guard let element = findElement(from: applicationElement, identifier: identifier, depth: 0) else {
            return false
        }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private static func findElement(from element: AXUIElement, identifier: String, depth: Int) -> AXUIElement? {
        if depth > 60 {
            return nil
        }
        var identifierValue: CFTypeRef?
        let identifierResult: AXError = AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue)
        if identifierResult == .success, let found = identifierValue as? String, found == identifier {
            return element
        }
        var childrenValue: CFTypeRef?
        let childrenResult: AXError = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let foundElement = findElement(from: child, identifier: identifier, depth: depth + 1) {
                    return foundElement
                }
            }
        }
        return nil
    }

    private static func findFrame(from element: AXUIElement, identifier: String, depth: Int) -> CGRect? {
        if depth > 60 {
            return nil
        }

        var identifierValue: CFTypeRef?
        let identifierResult: AXError = AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue)
        if identifierResult == .success, let found = identifierValue as? String, found == identifier {
            if let rectangle = frameOf(element) {
                return rectangle
            }
        }

        var childrenValue: CFTypeRef?
        let childrenResult: AXError = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let rectangle = findFrame(from: child, identifier: identifier, depth: depth + 1) {
                    return rectangle
                }
            }
        }
        return nil
    }

    private static func frameOf(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionResult: AXError = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult: AXError = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        if positionResult != .success || sizeResult != .success {
            return nil
        }
        var origin: CGPoint = .zero
        var size: CGSize = .zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private static func collectLabels(from element: AXUIElement, into labels: inout [String], depth: Int) {
        if depth > 60 {
            return
        }

        let textAttributes: [String] = [
            kAXTitleAttribute as String,
            kAXValueAttribute as String,
            kAXDescriptionAttribute as String,
            // A text field's placeholder (e.g. "Filter") lives here.
            kAXPlaceholderValueAttribute as String,
        ]
        for attributeName in textAttributes {
            var attributeValue: CFTypeRef?
            let result: AXError = AXUIElementCopyAttributeValue(element, attributeName as CFString, &attributeValue)
            if result == .success {
                if let text = attributeValue as? String {
                    if !text.isEmpty {
                        labels.append(text)
                    }
                }
            }
        }

        var childrenValue: CFTypeRef?
        let childrenResult: AXError = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        if childrenResult != .success {
            return
        }
        guard let children = childrenValue as? [AXUIElement] else {
            return
        }
        for child in children {
            collectLabels(from: child, into: &labels, depth: depth + 1)
        }
    }
}
