import AppKit
import Observation
import SwiftUI

/// Remembers that Cancel was pressed for one run of a task, so Cancel acts
/// once per run however it is pressed: a click, Escape, Command-Period, or a
/// held key repeating faster than the panel redraws (#988 review). A new run
/// (a different `startedAt`) can be cancelled again.
@Observable
final class CancelOncePerRun {

    // MARK: - Stored properties

    /// The run Cancel was pressed for, keyed by when it started. `nil`
    /// before any press. A runner with no start time (a test's) is keyed by
    /// `Date.distantPast`.
    var pressedForRunStartedAt: Date?

    // MARK: - Functions

    /// Whether Cancel has already been pressed for the run that started at
    /// `startedAt`.
    func hasBeenPressed(forRunStartedAt startedAt: Date?) -> Bool {
        let thisRun: Date = startedAt ?? Date.distantPast
        return pressedForRunStartedAt == thisRun
    }

    /// Records the press and says whether it is the first for this run.
    func pressOnce(forRunStartedAt startedAt: Date?) -> Bool {
        if hasBeenPressed(forRunStartedAt: startedAt) {
            return false
        }
        pressedForRunStartedAt = startedAt ?? Date.distantPast
        return true
    }
}

/// Answers `cancelOperation(_:)` for the progress panel's Cancel, from the
/// window's responder chain (#988, the HIG review's D6, reworked after its
/// second review).
///
/// Keyboards, https://developer.apple.com/design/human-interface-guidelines/keyboards:
/// "Esc: Cancel the current action or process"; "Command-Period: Cancel an
/// operation." AppKit turns both keys into one action message,
/// `cancelOperation(_:)`, sent to the window's first responder and passed up
/// the responder chain until something answers it. This object is not a
/// view and draws nothing.
///
/// Where it sits, measured on the second Mac on 2026-11-19 (`988-diag-3`):
/// `NSWindow` itself answers `cancelOperation(_:)` and does nothing with
/// it, so a responder AFTER the window never hears it. So this one sits
/// between the window's content view and the window, and hears the message
/// whenever focus is anywhere in the window's views and nothing nearer the
/// focus answered first. With focus nowhere (Keyboard Navigation off, the
/// macOS default) the window is its own first responder and the message
/// starts AT the window; so while the keys are live, this responder takes
/// the window's first-responder place whenever the window would hold it
/// itself, and gives it back when they are not. Every other key it is sent
/// goes on to the window, as before.
///
/// A text field being edited, a sheet, an alert or a popover keep Escape
/// for themselves: the field editor is then the first responder, sheets,
/// alerts and popovers are windows of their own, and
/// `somethingElseWantsTheKey(in:)` turns the message away in the cases that
/// let it pass (Command-Period in a field, for one).
///
/// Replaces `CancelKeyCatcher`, an invisible view that took the keys as a
/// key equivalent: the kind of hidden key-carrying control Russell rejected
/// on #973.
final class CancelOperationResponder: NSResponder {

    // MARK: - Stored properties

    /// False whenever the panel's Cancel is not showing, or something
    /// covers the panel (`TaskProgressView.takesTheCancelKeys`).
    var isEnabled: Bool = false {
        didSet {
            holdTheWindowsOwnPlaceIfLive()
        }
    }

    /// What Escape and Command-Period do: what clicking Cancel does.
    var pressCancel: (() -> Void)?

    /// The window whose chain this sits in, while it is in one.
    private(set) weak var window: NSWindow?

    /// The content view this sits after, while it is in a chain.
    private weak var contentView: NSView?

    /// Watches the window's first responder, so this can take the window's
    /// own place when focus leaves every view.
    private var firstResponderWatch: NSKeyValueObservation?

    // MARK: - Functions

    /// Puts this responder into `window`'s chain, between its content view
    /// and the window. Doing it twice for the same window changes nothing.
    func install(in window: NSWindow) {
        guard let content = window.contentView else {
            return
        }
        if self.window === window && contentView === content && content.nextResponder === self {
            return
        }
        uninstall()
        self.nextResponder = content.nextResponder
        content.nextResponder = self
        self.window = window
        self.contentView = content
        firstResponderWatch = window.observe(\.firstResponder, options: [.new]) { [weak self] (_: NSWindow, _: NSKeyValueObservedChange<NSResponder?>) in
            MainActor.assumeIsolated {
                self?.holdTheWindowsOwnPlaceIfLive()
            }
        }
        holdTheWindowsOwnPlaceIfLive()
    }

    /// Takes this responder out of its window's chain, leaving the chain
    /// joined up as it was, and gives the window back its own place.
    func uninstall() {
        firstResponderWatch?.invalidate()
        firstResponderWatch = nil
        if let window, window.firstResponder === self {
            _ = window.makeFirstResponder(nil)
        }
        if let contentView {
            var previous: NSResponder = contentView
            while let next = previous.nextResponder {
                if next === self {
                    previous.nextResponder = self.nextResponder
                    break
                }
                previous = next
            }
        }
        self.nextResponder = nil
        self.contentView = nil
    }

    /// While the keys are live and the window would be its own first
    /// responder, this takes that place, so the message starts below the
    /// window; otherwise it hands the place back.
    func holdTheWindowsOwnPlaceIfLive() {
        guard let window, contentView != nil else {
            return
        }
        if isEnabled {
            if window.firstResponder === window {
                _ = window.makeFirstResponder(self)
            }
        } else if window.firstResponder === self {
            _ = window.makeFirstResponder(nil)
        }
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    /// Whether `responder` sits in the chain after `window`'s content view.
    static func chain(of window: NSWindow, contains responder: NSResponder) -> Bool {
        var current: NSResponder? = window.contentView?.nextResponder
        while let found = current {
            if found === responder {
                return true
            }
            current = found.nextResponder
        }
        return false
    }

    /// Whether something in `window` other than the panel has a use for
    /// Escape right now: text being edited, a popover or other child window
    /// over it, or a sheet.
    static func somethingElseWantsTheKey(in window: NSWindow) -> Bool {
        if window.attachedSheet != nil {
            return true
        }
        if let children = window.childWindows {
            for child in children {
                if child.isVisible {
                    return true
                }
            }
        }
        if window.firstResponder is NSText {
            return true
        }
        return false
    }

    /// Whether this responder takes the message right now. Asked by
    /// `tryToPerform(_:with:)` as it walks the chain: answering no lets the
    /// message go on past this responder as though it were not there.
    func takesCancelOperation() -> Bool {
        guard isEnabled, pressCancel != nil, let window else {
            return false
        }
        return !CancelOperationResponder.somethingElseWantsTheKey(in: window)
    }

    /// `NSObject` declares this nonisolated. AppKit asks it on the main
    /// thread while it walks the chain for a key; asked anywhere else, the
    /// answer is no.
    nonisolated override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            if !Thread.isMainThread {
                return false
            }
            let takesIt: Bool = MainActor.assumeIsolated {
                return takesCancelOperation()
            }
            return takesIt
        }
        return super.responds(to: selector)
    }

    override func cancelOperation(_ sender: Any?) {
        if takesCancelOperation(), let pressCancel {
            // A held key repeats: it is the same press, never a second one.
            if let event = NSApp.currentEvent, event.type == .keyDown, event.isARepeat {
                return
            }
            pressCancel()
            return
        }
        if let next = nextResponder {
            next.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender)
        }
    }
}

/// Puts the panel's `CancelOperationResponder` into the chain of the window
/// the panel is in, and keeps it told what the keys do (#988).
///
/// It draws nothing, takes no clicks, is not an accessibility element and
/// carries no key: the keys reach the responder through AppKit's own
/// `cancelOperation(_:)`, not through this view. It exists because AppKit's
/// view life cycle is the one that says, exactly, when the panel joins and
/// leaves a window (`viewDidMoveToWindow`, `dismantleNSView`), and
/// `updateNSView` hands the responder the panel's current state on every
/// update. Measured: a responder kept in the panel's `@State` and installed
/// from `WindowAccessor` stayed in the chain after the panel had gone, and
/// Escape still stopped the task (`988-classes-6`).
struct CancelOperationInstaller: NSViewRepresentable {

    // MARK: - Stored properties

    /// Whether Escape and Command-Period press Cancel now.
    let isEnabled: Bool

    /// What they do: what clicking Cancel does.
    let pressCancel: () -> Void

    // MARK: - Functions

    func makeCoordinator() -> CancelOperationResponder {
        return CancelOperationResponder()
    }

    func makeNSView(context: Context) -> InstallerView {
        let view: InstallerView = InstallerView()
        view.responder = context.coordinator
        context.coordinator.pressCancel = pressCancel
        context.coordinator.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: InstallerView, context: Context) {
        context.coordinator.pressCancel = pressCancel
        context.coordinator.isEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: InstallerView, coordinator: CancelOperationResponder) {
        coordinator.isEnabled = false
        coordinator.pressCancel = nil
        coordinator.uninstall()
    }

    // MARK: - Types

    /// Joins the responder to its window's chain while it is in a window.
    final class InstallerView: NSView {

        // MARK: - Stored properties

        var responder: CancelOperationResponder?

        // MARK: - Functions

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let responder else {
                return
            }
            if let window {
                responder.install(in: window)
            } else {
                responder.uninstall()
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }

        override func isAccessibilityElement() -> Bool {
            return false
        }
    }
}
