import AppKit
import SwiftUI
@testable import QuartzTeachers

/// Puts a SwiftUI view on screen — OFF screen, far outside any display, and
/// never made key or activated — so a test can reach the `NSTableView` a
/// SwiftUI `Table` becomes and click its cells as a teacher would.
///
/// Measured for issue #266 before being relied on: an in-process mouse click
/// sent through `NSWindow.sendEvent` at `frameOfCell(atColumn:row:)` of the
/// table ticks the box in that cell and writes the model, exactly as a real
/// click does; a key event sent the same way reaches `.onKeyPress` and
/// `.onDeleteCommand` once the table is first responder. The COMPONENT is
/// hosted, not the settings page: a grouped `Form` realises rows lazily and
/// a page-sized host would be testing the scroll position.
@MainActor
final class TableHost {

    // MARK: - Stored properties

    let window: NSWindow

    // MARK: - Initializer

    init<Content: View>(_ content: Content, size: NSSize = NSSize(width: 520, height: 600)) {
        window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -6000, y: -6000), size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content.frame(width: size.width, height: size.height, alignment: .top))
        window.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        window.orderFrontRegardless()
        pump()
    }

    // MARK: - Functions

    /// Lets SwiftUI and AppKit settle: layout, row realisation, bindings.
    func pump(_ seconds: Double = 0.3) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    /// Every table in the window, top first.
    func tables() -> [NSTableView] {
        var found: [NSTableView] = []
        if let content = window.contentView {
            collectTables(in: content, into: &found)
        }
        var ordered: [NSTableView] = []
        for table in found {
            var index: Int = 0
            let top: CGFloat = table.convert(table.bounds, to: nil).maxY
            while index < ordered.count && ordered[index].convert(ordered[index].bounds, to: nil).maxY >= top {
                index = index + 1
            }
            ordered.insert(table, at: index)
        }
        return ordered
    }

    func collectTables(in view: NSView, into found: inout [NSTableView]) {
        if let table = view as? NSTableView {
            found.append(table)
        }
        for subview in view.subviews {
            collectTables(in: subview, into: &found)
        }
    }

    /// Clicks near the LEADING edge of a cell — where a checkbox sits.
    func clickCell(of table: NSTableView, column: Int, row: Int) {
        let cell: NSRect = table.frameOfCell(atColumn: column, row: row)
        let inset: CGFloat = min(12, cell.width / 2)
        let point: NSPoint = table.convert(NSPoint(x: cell.minX + inset, y: cell.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, NSEvent.EventType.leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) {
                window.sendEvent(event)
            }
        }
        pump()
    }

    /// Selects a row the way arrow keys would, and makes the table the
    /// first responder so the next key goes to it.
    func select(row: Int, in table: NSTableView) {
        _ = window.makeFirstResponder(table)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        pump()
    }

    /// Sends one key press to the window.
    func press(keyCode: UInt16, characters: String) {
        for type in [NSEvent.EventType.keyDown, NSEvent.EventType.keyUp] {
            if let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode
            ) {
                window.sendEvent(event)
            }
        }
        pump()
    }

    func pressSpace() {
        press(keyCode: 49, characters: " ")
    }

    func pressDelete() {
        press(keyCode: 51, characters: "\u{7f}")
    }
}

/// A list held outside any view, so a hosted table can be bound to it and
/// the test can read what the table wrote.
@MainActor
@Observable
final class ListBox {

    // MARK: - Stored properties

    var names: [String]
    var secondNames: [String]

    // MARK: - Initializer

    init(_ names: [String], second secondNames: [String] = []) {
        self.names = names
        self.secondNames = secondNames
    }

    // MARK: - Computed properties

    var binding: Binding<[String]> {
        return Binding(
            get: { return self.names },
            set: { newValue in self.names = newValue }
        )
    }

    var secondBinding: Binding<[String]> {
        return Binding(
            get: { return self.secondNames },
            set: { newValue in self.secondNames = newValue }
        )
    }
}
