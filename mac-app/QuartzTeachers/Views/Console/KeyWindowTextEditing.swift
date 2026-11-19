import AppKit
import Observation

/// Whether text is being edited in the key window: a text field, search
/// field or text view has the field editor (`NSText`) as the window's first
/// responder (#988).
///
/// The progress panel's Cancel holds Escape and Command-Period
/// (`.keyboardShortcut(.cancelAction)`). While a teacher is typing in a box,
/// Cancel lets go of the key, so Escape is always the box's (the Filter
/// field clears, a rename backs out), including in a text view that has no
/// use for Escape and would otherwise pass it on to the button. Measured on
/// the main Mac (`988-r4-sabotage-text`): through `NSApp.sendEvent` a text
/// FIELD is offered Escape before any button, so for a field this rule is a
/// second guard, not the only one.
///
/// This draws nothing, takes no key and is not a view: it watches
/// `NSWindow.firstResponder` (key-value observing) on whichever window is
/// key, and moves to the new key window when another becomes key.
@MainActor
@Observable
final class KeyWindowTextEditing {

    // MARK: - Stored properties

    /// The one watch the app needs: there is one key window at a time.
    static let shared: KeyWindowTextEditing = KeyWindowTextEditing()

    /// True while the key window's first responder is text being edited.
    private(set) var isEditingText: Bool = false

    /// The window being watched: the key window, when there is one.
    @ObservationIgnored
    private weak var watchedWindow: NSWindow?

    @ObservationIgnored
    private var firstResponderWatch: NSKeyValueObservation?

    @ObservationIgnored
    private var keyWindowWatches: [NSObjectProtocol] = []

    // MARK: - Initializer

    init() {
        let center: NotificationCenter = NotificationCenter.default
        let becameKey: NSObjectProtocol = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let window: NSWindow? = notification.object as? NSWindow
            MainActor.assumeIsolated {
                self?.watch(window)
            }
        }
        let resignedKey: NSObjectProtocol = center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.watch(NSApp.keyWindow)
            }
        }
        keyWindowWatches = [becameKey, resignedKey]
        watch(NSApp.keyWindow)
    }

    // MARK: - Functions

    /// Watches `window`'s first responder, and only that window's.
    func watch(_ window: NSWindow?) {
        if window === watchedWindow && firstResponderWatch != nil {
            readNow()
            return
        }
        firstResponderWatch?.invalidate()
        firstResponderWatch = nil
        watchedWindow = window
        if let window {
            firstResponderWatch = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.readNow()
                }
            }
        }
        readNow()
    }

    /// Reads the watched window's first responder now.
    func readNow() {
        let editing: Bool = KeyWindowTextEditing.isEditingText(in: watchedWindow)
        if editing != isEditingText {
            isEditingText = editing
        }
    }

    /// Whether `window`'s first responder is text being edited. The field
    /// editor every text field and search field edits through is an
    /// `NSTextView`, and so is a text view itself: both are `NSText`.
    static func isEditingText(in window: NSWindow?) -> Bool {
        guard let window else {
            return false
        }
        return window.firstResponder is NSText
    }
}
