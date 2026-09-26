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

    /// What the window server says about the login session the test host
    /// runs in, which is all the lock check below needs to know (#315).
    struct SessionFacts {

        // MARK: - Stored properties

        let isScreenLocked: Bool
        let isOnTheConsole: Bool

        /// What "we could not tell" is read as: a session that is neither
        /// locked nor switched away, so an unreadable answer never causes
        /// a skip.
        static let unlockedOnTheConsole: SessionFacts = SessionFacts(isScreenLocked: false, isOnTheConsole: true)
    }

    // MARK: - Stored properties

    /// Set in the session dictionary while the screen is locked, and ABSENT
    /// (not false) while it is unlocked. Undocumented; measured on
    /// 2026-09-26, Darwin 25.6.
    static let screenIsLockedKey: String = "CGSSessionScreenIsLocked"

    /// 1 (or true) while this session owns the screen, 0 (or false) while
    /// another account is using it through fast user switching.
    /// Undocumented; measured on 2026-09-26, Darwin 25.6.
    static let onConsoleKey: String = "kCGSSessionOnConsoleKey"

    // MARK: - Functions

    /// Why a test that reads the window through the accessibility tree
    /// cannot check anything in this run, or nil when it can (#249, #315).
    ///
    /// Measured on 2026-09-25: when the test's window is on a Space that is
    /// not showing — a full-screen app or another desktop in front on its
    /// display — macOS leaves it out of the tree, and a walk finds only the
    /// menu bar. Being in the BACKGROUND does not do this: the suite runs
    /// with the app inactive every time, and the walk finds everything.
    /// A locked screen, or another account using the screen, empties the
    /// tree the same way (#315).
    ///
    /// The tree is asked FIRST, so the session and the Space can only ever
    /// explain a window that is already missing — never cause a skip while
    /// the window can be read. Only the test's OWN window counts. Another
    /// window of the app being off the showing Space says nothing about the
    /// one the test reads, and the test's window being gone altogether is a
    /// real fault — so both return nil and the test goes on to fail, as
    /// does a window that is on the showing Space, in an unlocked session,
    /// and still missing from the tree.
    ///
    /// The session is checked before the window's visibility on purpose:
    /// what AppKit says about visibility on a locked screen is not what the
    /// skip should rest on, and all the order can mask is a hidden-window
    /// fault during a locked run, which the next unlocked run catches.
    static func reasonTheWindowCannotBeRead(
        windows: [WindowFacts],
        testsWindowIsInTheTree: Bool,
        session: SessionFacts
    ) -> String? {
        if testsWindowIsInTheTree {
            return nil
        }
        var testsWindow: WindowFacts? = nil
        for window in windows {
            if window.isTheTestsWindow {
                testsWindow = window
            }
        }
        guard let testsWindow else {
            return nil
        }
        if session.isScreenLocked {
            return "The screen is locked, so macOS leaves this app's windows out of the accessibility tree and this test cannot see the controls it checks. Unlock the Mac and run it again (#315)."
        }
        if !session.isOnTheConsole {
            return "Another account is using the screen (fast user switching), so macOS leaves this session's windows out of the accessibility tree and this test cannot see the controls it checks. Switch back to this account and run it again (#315)."
        }
        if !testsWindow.isVisible {
            return nil
        }
        if testsWindow.isOnTheShowingSpace {
            return nil
        }
        return "The test window is on a Space that is not showing (a full-screen app or another desktop is in front on its display), so macOS leaves it out of the accessibility tree and this test cannot see the controls it checks. Show that desktop and run it again (#249)."
    }

    /// Reads the two session keys above out of a session dictionary. A nil
    /// dictionary or a missing key reads as unlocked and on the console,
    /// because "we could not tell" must never cause a skip. Each key is
    /// accepted as a Bool or as a number: the window server hands back
    /// OnConsole as the integer 1, not a Bool.
    static func sessionFacts(from dictionary: [String: Any]?) -> SessionFacts {
        guard let dictionary else {
            return SessionFacts.unlockedOnTheConsole
        }
        var isScreenLocked: Bool = false
        if let lockValue = dictionary[screenIsLockedKey] {
            if let answer = truthOf(lockValue) {
                isScreenLocked = answer
            }
        }
        var isOnTheConsole: Bool = true
        if let consoleValue = dictionary[onConsoleKey] {
            if let answer = truthOf(consoleValue) {
                isOnTheConsole = answer
            }
        }
        return SessionFacts(isScreenLocked: isScreenLocked, isOnTheConsole: isOnTheConsole)
    }

    /// True or false for a value that is a Bool or a number, nil for
    /// anything else.
    static func truthOf(_ value: Any) -> Bool? {
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
        if let flag = value as? Bool {
            return flag
        }
        return nil
    }

    /// The session the test host is running in, as the window server
    /// describes it right now.
    static func currentSessionFacts() -> SessionFacts {
        let dictionary: [String: Any]? = CGSessionCopyCurrentDictionary() as? [String: Any]
        return sessionFacts(from: dictionary)
    }

    /// Skips the calling test, with the reason above, when its window is on
    /// a Space that is not showing, the screen is locked, or another
    /// account is using the screen. Call it before EVERY walk of the tree —
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
        let session: SessionFacts = currentSessionFacts()
        if let reason = reasonTheWindowCannotBeRead(windows: windows, testsWindowIsInTheTree: testsWindowIsInTheTree, session: session) {
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
