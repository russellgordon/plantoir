import AppKit
import SwiftUI
@testable import QuartzTeachers

/// Puts a SwiftUI view on screen — OFF screen, far outside any display, and
/// never made key or activated — so a test can reach the `NSTableView` a
/// SwiftUI `Table` becomes and click its cells as a teacher would.
///
/// **Off screen did not hold until v1.8.6, and this is why.** MEASURED on
/// macOS 26.6 (#621): a titled `NSWindow` made at (-5608, -4900) came back
/// from its initializer at (1112, 92), on the main display; `setFrameOrigin`
/// moved it off again; and `orderFrontRegardless()` put it straight back at
/// (0, 0). AppKit calls `constrainFrameRect(_:to:)` whenever a titled window
/// is placed on screen, and for a window on no display it constrains to the
/// main one. So every window this host made sat at the bottom-left of the
/// screen while its test ran. Now the host's window is an
/// `OffScreenWindow`, which refuses that constraint and any move onto a
/// display, and "outside any display" is worked out from the displays this
/// Mac has (`offScreenOrigin(for:)`) rather than a fixed -6000.
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
        let origin: NSPoint = TableHost.offScreenOrigin(for: size)
        window = OffScreenWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: content.frame(width: size.width, height: size.height, alignment: .top))
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
        pump()
    }

    // MARK: - Functions

    /// A point at which a window of `size` overlaps no display of this Mac:
    /// beyond the bottom-left corner of all of them together, with room to
    /// spare for a sheet hung under it and for growing.
    static func offScreenOrigin(for size: NSSize) -> NSPoint {
        var left: CGFloat = 0
        var bottom: CGFloat = 0
        for screen in NSScreen.screens {
            if screen.frame.minX < left {
                left = screen.frame.minX
            }
            if screen.frame.minY < bottom {
                bottom = screen.frame.minY
            }
        }
        let margin: CGFloat = 4000
        return NSPoint(x: left - size.width - margin, y: bottom - size.height - margin)
    }

    /// Whether any part of `frame` is on a display of this Mac.
    static func isOnAScreen(_ frame: NSRect) -> Bool {
        for screen in NSScreen.screens where screen.frame.intersects(frame) {
            return true
        }
        return false
    }

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

    // MARK: - Initializer

    init(_ names: [String], second secondNames: [String] = []) {
        self.names = names
        self.secondNames = secondNames
    }
}

/// A window that stays off every display (#621).
///
/// MEASURED on macOS 26.6, two ways AppKit moved a test window placed
/// beyond every display back onto the main one:
/// - ordering in a titled window constrains it to a display through
///   `constrainFrameRect(_:to:)`: from (-5608, -4900) to (0, 0) on
///   `orderFrontRegardless()`. So every `TableHost` window sat at the
///   bottom-left of the screen while its test ran;
/// - presenting a sheet from it, `NSSheetMoveHelper`'s `_configureFinalState`
///   calls `setFrameOrigin` on the PARENT so that the sheet lands on a
///   display: the parent went to (-320, -239) and the sheet to (0, 0).
/// So this answers "where it is" to the first, and puts any frame that
/// would overlap a display back beyond them all, which answers the second.
final class OffScreenWindow: NSWindow {

    // MARK: - Functions

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override func setFrameOrigin(_ point: NSPoint) {
        let kept: NSRect = OffScreenWindow.keptOffTheScreens(NSRect(origin: point, size: frame.size))
        super.setFrameOrigin(kept.origin)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(OffScreenWindow.keptOffTheScreens(frameRect), display: flag)
    }

    /// `frame`, or the same size beyond every display if it overlaps one.
    static func keptOffTheScreens(_ frame: NSRect) -> NSRect {
        if TableHost.isOnAScreen(frame) {
            return NSRect(origin: TableHost.offScreenOrigin(for: frame.size), size: frame.size)
        }
        return frame
    }
}
