import AppKit
import ApplicationServices
import XCTest

/// What a window exposes to VoiceOver, read through the accessibility API
/// an assistive app uses (`AXUIElement`), on the test host's own process
/// (#993): each element's role, identifier, title, description (the name
/// an `.accessibilityLabel` sets) and value. A name that is missing, or a
/// control that says its name twice, fails a test that reads this; a test
/// that reads only the source cannot see either (a `Stepper` given a title
/// AND a label read "Section number, Section number" with every modifier
/// in place).
///
/// The tree belongs to this same process, so no permission is asked for
/// (as `AccessibilityInspector`). AppKit's own `NSAccessibility` methods on
/// the hosting view are no substitute: measured on 2026-11-19, a SwiftUI
/// hosting view answers them with one childless group until an assistive
/// client asks through the API. The first review of #993 read the same tree
/// from outside, in an isolated debug build
/// (`vm-tools/reference/993-review-1/ax993tools/axdump.swift`).
@MainActor
struct AccessibilityTree {

    // MARK: - Types

    /// One element, as VoiceOver is given it.
    struct Element {

        // MARK: - Stored properties

        let role: String
        let identifier: String
        let title: String
        let label: String
        let value: String

        /// The help tag a pointer shows (`.help`), as VoiceOver reads it
        /// after the name (#997).
        let help: String

        /// Where the element is, in screen points with the origin at the
        /// top left, as an assistive app is told (#997); `.null` where it
        /// does not say.
        let frame: CGRect

        /// "1" or "0" where the element says whether it is enabled; empty
        /// where it does not.
        let enabled: String

        /// The role of the element this one sits in.
        let parentRole: String

        /// The actions an assistive app can perform on the element
        /// ("AXPress" and the like): what VoiceOver and Full Keyboard
        /// Access use to activate it, with Keyboard Navigation on or off.
        let actions: [String]

        // MARK: - Computed properties

        /// Every name the element carries, in the order VoiceOver speaks
        /// them: its description (the label), then its title. Both are
        /// kept rather than merged, so a name said twice shows.
        var names: [String] {
            var spoken: [String] = []
            if !label.isEmpty {
                spoken.append(label)
            }
            if !title.isEmpty {
                spoken.append(title)
            }
            return spoken
        }
    }

    // MARK: - Stored properties

    /// Every element in the window, depth first, or none when the window
    /// is not in the tree.
    let elements: [Element]

    /// Whether the window was found in the tree at all.
    let foundTheWindow: Bool

    // MARK: - Initializer

    /// Reads the window whose title is `windowTitle` (give the window a
    /// title no other window has).
    init(ofWindowTitled windowTitle: String) {
        var found: [Element] = []
        var foundWindow: Bool = false
        let application: AXUIElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let windows: [AXUIElement] = AccessibilityTree.elementList(of: application, attribute: kAXWindowsAttribute)
        for window in windows {
            if AccessibilityTree.text(of: window, attribute: kAXTitleAttribute) == windowTitle {
                foundWindow = true
                AccessibilityTree.collect(window, parentRole: "", into: &found, depth: 0)
            }
        }
        elements = found
        foundTheWindow = foundWindow
    }

    // MARK: - Functions

    /// The elements with this identifier.
    func elements(identifiedAs identifier: String) -> [Element] {
        var matching: [Element] = []
        for element in elements {
            if element.identifier == identifier {
                matching.append(element)
            }
        }
        return matching
    }

    /// The one element with this identifier, or a failure that says how
    /// many there were and what the tree held.
    func element(identifiedAs identifier: String, file: StaticString = #filePath, line: UInt = #line) -> Element? {
        let matching: [Element] = elements(identifiedAs: identifier)
        if matching.count != 1 {
            XCTFail("\(matching.count) elements are identified as \(identifier); the window holds:\n\(described())", file: file, line: line)
            return nil
        }
        return matching[0]
    }

    /// The elements with this role.
    func elements(withRole role: String) -> [Element] {
        var matching: [Element] = []
        for element in elements {
            if element.role == role {
                matching.append(element)
            }
        }
        return matching
    }

    /// The roles of elements a person operates, each of which VoiceOver
    /// must be able to name.
    static let controlRoles: [String] = [
        "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioGroup", "AXRadioButton",
        "AXIncrementor", "AXPopUpButton", "AXMenuButton", "AXOutline", "AXTable", "AXBusyIndicator",
        "AXLink", "AXSlider", "AXComboBox",
    ]

    /// Every control in the window that has no name, or says one name
    /// twice, as one line each. The arrows of a stepper are left out:
    /// AppKit draws them as unnamed buttons inside the named stepper, and
    /// VoiceOver reads them as the stepper's increment and decrement.
    func controlsNotNamedOnce() -> [String] {
        var faults: [String] = []
        for element in elements {
            if !AccessibilityTree.controlRoles.contains(element.role) {
                continue
            }
            if element.role == "AXButton" && element.parentRole == "AXIncrementor" {
                continue
            }
            let names: [String] = element.names
            let shown: String = "\(element.role) id=[\(element.identifier)] names=\(names)"
            if names.isEmpty {
                faults.append("no name: " + shown)
            } else if AccessibilityTree.saysAPartTwice(names) {
                faults.append("named twice: " + shown)
            }
        }
        return faults
    }

    /// True when the same words come twice among an element's names.
    /// SwiftUI joins a control's own title and a label given to it into one
    /// description with ", " (measured 2026-11-19: "Section number, Section
    /// number"), so each name is split there too.
    static func saysAPartTwice(_ names: [String]) -> Bool {
        var parts: [String] = []
        for name in names {
            for part in name.components(separatedBy: ", ") {
                if parts.contains(part) {
                    return true
                }
                parts.append(part)
            }
        }
        return false
    }

    /// The tree as one line per element, for a failure message.
    func described() -> String {
        var lines: [String] = []
        for element in elements {
            lines.append("\(element.role) id=[\(element.identifier)] title=[\(element.title)] label=[\(element.label)] value=[\(element.value)] enabled=[\(element.enabled)]")
        }
        return lines.joined(separator: "\n")
    }

    /// The element that has the keyboard focus in this process, as an
    /// assistive app is told it (#997): the text field being typed in, not
    /// the field editor AppKit lends it. Nil when nothing has the focus.
    static func focusedElement() -> Element? {
        let application: AXUIElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value) != .success {
            return nil
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        let focused: AXUIElement = value as! AXUIElement
        return element(of: focused, parentRole: "")
    }

    /// One element's own attributes, without its children.
    static func element(of node: AXUIElement, parentRole: String) -> Element {
        return Element(
            role: text(of: node, attribute: kAXRoleAttribute),
            identifier: text(of: node, attribute: kAXIdentifierAttribute),
            title: text(of: node, attribute: kAXTitleAttribute),
            label: text(of: node, attribute: kAXDescriptionAttribute),
            value: text(of: node, attribute: kAXValueAttribute),
            help: text(of: node, attribute: kAXHelpAttribute),
            frame: frame(of: node),
            enabled: text(of: node, attribute: kAXEnabledAttribute),
            parentRole: parentRole,
            actions: actionNames(of: node)
        )
    }

    static func collect(_ node: AXUIElement, parentRole: String, into found: inout [Element], depth: Int) {
        if depth > 60 {
            return
        }
        let role: String = text(of: node, attribute: kAXRoleAttribute)
        found.append(Element(
            role: role,
            identifier: text(of: node, attribute: kAXIdentifierAttribute),
            title: text(of: node, attribute: kAXTitleAttribute),
            label: text(of: node, attribute: kAXDescriptionAttribute),
            value: text(of: node, attribute: kAXValueAttribute),
            help: text(of: node, attribute: kAXHelpAttribute),
            frame: frame(of: node),
            enabled: text(of: node, attribute: kAXEnabledAttribute),
            parentRole: parentRole,
            actions: actionNames(of: node)
        ))
        for child in elementList(of: node, attribute: kAXChildrenAttribute) {
            collect(child, parentRole: role, into: &found, depth: depth + 1)
        }
    }

    /// The element's position and size, or `.null` when either is missing.
    static func frame(of element: AXUIElement) -> CGRect {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) != .success {
            return CGRect.null
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) != .success {
            return CGRect.null
        }
        guard let positionValue, let sizeValue else {
            return CGRect.null
        }
        if CFGetTypeID(positionValue) != AXValueGetTypeID() || CFGetTypeID(sizeValue) != AXValueGetTypeID() {
            return CGRect.null
        }
        var position: CGPoint = CGPoint.zero
        var size: CGSize = CGSize.zero
        let positionAXValue: AXValue = positionValue as! AXValue
        let sizeAXValue: AXValue = sizeValue as! AXValue
        if !AXValueGetValue(positionAXValue, .cgPoint, &position) || !AXValueGetValue(sizeAXValue, .cgSize, &size) {
            return CGRect.null
        }
        return CGRect(origin: position, size: size)
    }

    static func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        let result: AXError = AXUIElementCopyActionNames(element, &names)
        if result != .success {
            return []
        }
        if let list = names as? [String] {
            return list
        }
        return []
    }

    static func elementList(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        let result: AXError = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result != .success {
            return []
        }
        if let list = value as? [AXUIElement] {
            return list
        }
        return []
    }

    static func text(of element: AXUIElement, attribute: String) -> String {
        var value: CFTypeRef?
        let result: AXError = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result != .success {
            return ""
        }
        guard let value else {
            return ""
        }
        if let words = value as? String {
            return words
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }
}
