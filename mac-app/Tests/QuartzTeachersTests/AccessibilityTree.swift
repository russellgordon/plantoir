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

        /// "1" or "0" where the element says whether it is enabled; empty
        /// where it does not.
        let enabled: String

        /// The words of the element AppKit names as this one's title
        /// (`AXTitleUIElement`): a printed label a `Form` row links to its
        /// control, which VoiceOver reads as the control's name (#1012).
        /// Empty where none is linked.
        let titleElementWords: String

        /// The role of the element this one sits in.
        let parentRole: String

        /// The actions an assistive app can perform on the element
        /// ("AXPress" and the like): what VoiceOver and Full Keyboard
        /// Access use to activate it, with Keyboard Navigation on or off.
        let actions: [String]

        // MARK: - Computed properties

        /// Every name the element carries, in the order VoiceOver speaks
        /// them: its description (the label), then its title. Both are
        /// kept rather than merged, so a name said twice shows. With
        /// neither, the words of a linked title element: a `Form` row's
        /// printed label, which names its field (measured 2026-11-20: Course
        /// Settings' "Folder" and "School name" fields carry no label or
        /// title of their own and are linked to their row's label).
        var names: [String] {
            var spoken: [String] = []
            if !label.isEmpty {
                spoken.append(label)
            }
            if !title.isEmpty {
                spoken.append(title)
            }
            if spoken.isEmpty && !titleElementWords.isEmpty {
                spoken.append(titleElementWords)
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
            lines.append("\(element.role) id=[\(element.identifier)] title=[\(element.title)] label=[\(element.label)] titleElement=[\(element.titleElementWords)] value=[\(element.value)] enabled=[\(element.enabled)]")
        }
        return lines.joined(separator: "\n")
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
            enabled: text(of: node, attribute: kAXEnabledAttribute),
            titleElementWords: titleElementWords(of: node),
            parentRole: parentRole,
            actions: actionNames(of: node)
        ))
        for child in elementList(of: node, attribute: kAXChildrenAttribute) {
            collect(child, parentRole: role, into: &found, depth: depth + 1)
        }
    }

    /// The value (or title) of the element linked as `element`'s title, or
    /// empty where none is.
    static func titleElementWords(of element: AXUIElement) -> String {
        var linked: CFTypeRef?
        let result: AXError = AXUIElementCopyAttributeValue(element, kAXTitleUIElementAttribute as CFString, &linked)
        if result != .success {
            return ""
        }
        guard let linked else {
            return ""
        }
        if CFGetTypeID(linked) != AXUIElementGetTypeID() {
            return ""
        }
        let titleElement: AXUIElement = linked as! AXUIElement
        let value: String = text(of: titleElement, attribute: kAXValueAttribute)
        if !value.isEmpty {
            return value
        }
        return text(of: titleElement, attribute: kAXTitleAttribute)
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
