import AppKit
import Observation

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
/// view and draws nothing: it is put into the chain just after the window,
/// so it hears the message only when nothing nearer the focus answered it
/// first. A text field being edited, a sheet, an alert or a popover keep
/// Escape for themselves: the first three are their own key windows or
/// answer the message before it reaches here, and the checks in
/// `somethingElseWantsTheKey(in:)` catch the field editor and child windows
/// that let it pass (Command-Period in a field, for one).
///
/// Replaces `CancelKeyCatcher`, an invisible view that took the keys as a
/// key equivalent: the kind of hidden key-carrying control Russell rejected
/// on #973.
final class CancelOperationResponder: NSResponder {

    // MARK: - Stored properties

    /// False whenever the panel's Cancel is not showing, or something
    /// covers the panel (`TaskProgressView.takesTheCancelKeys`).
    var isEnabled: Bool = false

    /// What Escape and Command-Period do: what clicking Cancel does.
    var pressCancel: (() -> Void)?

    /// The window whose chain this sits in, while it is in one.
    private(set) weak var window: NSWindow?

    // MARK: - Functions

    /// Puts this responder into `window`'s chain, just after the window
    /// itself. Doing it twice for the same window changes nothing.
    func install(in window: NSWindow) {
        if self.window === window && CancelOperationResponder.chain(of: window, contains: self) {
            return
        }
        uninstall()
        self.nextResponder = window.nextResponder
        window.nextResponder = self
        self.window = window
    }

    /// Puts this responder back into the window it was last in, if that
    /// window is still there (the panel appeared again).
    func reinstall() {
        if let window {
            install(in: window)
        }
    }

    /// Takes this responder out of its window's chain, leaving the rest of
    /// the chain joined up as it was.
    func uninstall() {
        guard let window else {
            return
        }
        var previous: NSResponder = window
        while let next = previous.nextResponder {
            if next === self {
                previous.nextResponder = self.nextResponder
                break
            }
            previous = next
        }
        self.nextResponder = nil
    }

    /// Whether `responder` is somewhere in the chain after `window`.
    static func chain(of window: NSWindow, contains responder: NSResponder) -> Bool {
        var current: NSResponder? = window.nextResponder
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
