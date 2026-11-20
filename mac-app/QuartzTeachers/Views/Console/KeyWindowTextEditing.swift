import AppKit

/// Whether a box in a window is being typed in (#988): the window's first
/// responder is editable text, the field editor every text field and search
/// field edits through, or an editable text view.
///
/// Read by the progress panel's Cancel (`CancelKeyNSButton`) at the moment a
/// cancel key arrives, so while a teacher is typing in a box, Escape and
/// Command-Period are the box's (the Filter field clears, a rename backs
/// out), including in a text view that has no use for Escape (Russell's
/// ruling on #988, 2026-11-19 evening).
///
/// Only EDITABLE text counts. Text a teacher can only select, such as the
/// console's output (`TaskConsoleView`, `.textSelection(.enabled)`), is not
/// a box anybody types in, so a click to select some of it leaves the keys
/// with Cancel (the fifth #988 review).
///
/// This draws nothing, takes no key and is not a view: it reads one window
/// when asked. (Until the fifth review it watched the key window's first
/// responder by key-value observing, for a SwiftUI shortcut that could only
/// be changed by redrawing; the button reads the window itself now.)
enum KeyWindowTextEditing {

    // MARK: - Functions

    /// Whether `window`'s first responder is text being edited.
    @MainActor
    static func isEditingText(in window: NSWindow?) -> Bool {
        guard let window else {
            return false
        }
        guard let text = window.firstResponder as? NSText else {
            return false
        }
        return text.isEditable
    }
}
