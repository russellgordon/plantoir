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

/// Gives the progress panel's Cancel Escape and Command-Period, but only
/// when the key is not wanted by whatever has focus (#988, the HIG review's
/// D6, and its review).
///
/// Keyboards, https://developer.apple.com/design/human-interface-guidelines/keyboards:
/// "Esc: Cancel the current action or process"; "Command-Period: Cancel an
/// operation." The current action is the one the teacher is in: typing in
/// the Filter field or renaming a course, Escape backs out of THAT (the
/// field's own use), and only with focus nowhere that wants the key does it
/// stop the running preview or deploy.
///
/// Why a key-equivalent view and not `.keyboardShortcut(.cancelAction)` on
/// the button: a SwiftUI shortcut is a key equivalent the window offers
/// before the focused field sees the key, so Escape typed in a text field
/// stopped the deploy and the field never saw it (measured by the #988
/// review). This view is offered the key at the same moment, and declines
/// it whenever the window's first responder is text being edited (`NSText`:
/// every text field, search field and text view edits through one), or a
/// popover or other child window is showing over the window, or a sheet is
/// attached. Declined, the key goes on to the focused control as usual.
/// Not `.onExitCommand`, which fires only while something in the panel holds
/// the keys, and with Keyboard Navigation off nothing here does (#973).
///
/// It draws nothing and is not an accessibility element: it is a key
/// handler for the visible Cancel, not a control of its own.
struct CancelKeyCatcher: NSViewRepresentable {

    // MARK: - Stored properties

    /// False while something else covers the panel (`TaskProgressView.takesTheCancelKeys`).
    let isEnabled: Bool

    /// Presses Cancel.
    let pressCancel: () -> Void

    // MARK: - Functions

    func makeNSView(context: Context) -> CatcherView {
        let view: CatcherView = CatcherView()
        view.isEnabled = isEnabled
        view.pressCancel = pressCancel
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.pressCancel = pressCancel
    }

    /// Whether `event` is Escape or Command-Period.
    static func isACancelKey(_ event: NSEvent) -> Bool {
        let modifiers: NSEvent.ModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let withoutCapsLock: NSEvent.ModifierFlags = modifiers.subtracting([.capsLock, .numericPad, .function])
        if event.keyCode == 53 && withoutCapsLock.isEmpty {
            return true
        }
        if event.charactersIgnoringModifiers == "." && withoutCapsLock == [.command] {
            return true
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

    // MARK: - Types

    final class CatcherView: NSView {

        // MARK: - Stored properties

        var isEnabled: Bool = true
        var pressCancel: (() -> Void)?

        // MARK: - Functions

        override func isAccessibilityElement() -> Bool {
            return false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isEnabled, event.type == .keyDown, CancelKeyCatcher.isACancelKey(event) else {
                return false
            }
            guard let window, !CancelKeyCatcher.somethingElseWantsTheKey(in: window) else {
                return false
            }
            // A held key repeats: it is the same press, never a second Cancel.
            if !event.isARepeat {
                pressCancel?()
            }
            return true
        }
    }
}
