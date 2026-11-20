import AppKit
import SwiftUI

/// The progress panel's visible Cancel (#988): a real `NSButton`, drawn as
/// the push button SwiftUI's `.bordered` style draws on the Mac, that holds
/// Escape and Command-Period itself.
///
/// Why AppKit and not a SwiftUI `Button` with `.keyboardShortcut`: whether a
/// key is a box's or Cancel's has to be decided at the moment the key
/// arrives, from the window as it is then. A SwiftUI shortcut is taken up or
/// let go of only when SwiftUI next updates the view, so a click in a box
/// and Escape already waiting together in the event queue met a Cancel that
/// still held the key (run `988-n2`). The fix that followed read
/// `NSApp.currentEvent` inside the button's action to tell a key from a
/// click (the fifth #988 review): that is the last event taken off the
/// queue, not the one that pressed the button, so a VoiceOver, Voice Control
/// or Switch Control press, which has no event of its own, coming after a
/// key typed in a box was taken for that key and stopped nothing.
///
/// Here the key is decided in `performKeyEquivalent(with:)`, which AppKit
/// calls with the key itself, before the focused box sees it: while text is
/// being edited in the window the button refuses the key, and the box gets
/// it as it would with no button there. The box's own `cancelOperation`
/// coming back to the window reaches this button the same way and is
/// refused again, so nothing loops. A click and an accessibility press reach
/// the action with nothing to inspect, and always stop the task (Russell's
/// ruling on #988, 2026-11-19 evening: while a box has the focus both keys
/// are the box's; a click on Cancel still stops the task).
///
/// Visible, the size of the SwiftUI button it replaced (measured by
/// `TaskCancelButtonTests`), named "Cancel" to VoiceOver, and in the key view
/// loop with Keyboard Navigation on, as any push button is. Not a key
/// catcher: it is the visible Cancel, and the only keys it takes are the two
/// the HIG gives cancelling (Keyboards: "Esc: Cancel the current action or
/// process"; "Command-Period: Cancel an operation").
struct TaskCancelButton: NSViewRepresentable {

    // MARK: - Stored properties

    /// The button's title, which VoiceOver reads too.
    let title: String

    /// Identifies the button to the UI tests.
    let accessibilityIdentifier: String

    /// Whether the button holds Escape and Command-Period now: everything
    /// `TaskProgressView.cancelKeysAreLive` reads except typing in a box,
    /// which the button reads itself when a key arrives.
    let holdsTheCancelKeys: Bool

    /// What a click, a key or an accessibility press does.
    let action: () -> Void

    // MARK: - Functions

    func makeNSView(context: Context) -> CancelKeyNSButton {
        let button: CancelKeyNSButton = CancelKeyNSButton(frame: .zero)
        button.title = title
        button.bezelStyle = .push
        button.controlSize = .regular
        button.target = context.coordinator
        button.action = #selector(Coordinator.pressed)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        button.holdsTheCancelKeys = holdsTheCancelKeys
        return button
    }

    func updateNSView(_ button: CancelKeyNSButton, context: Context) {
        context.coordinator.action = action
        if button.title != title {
            button.title = title
        }
        button.holdsTheCancelKeys = holdsTheCancelKeys
    }

    /// The button's own size, as AppKit measures a push button with this
    /// title, never stretched by the row it sits in.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CancelKeyNSButton, context: Context) -> CGSize? {
        return nsView.intrinsicContentSize
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(action: action)
    }

    // MARK: - Types

    /// The button's target: runs the panel's action.
    final class Coordinator: NSObject {

        // MARK: - Stored properties

        var action: () -> Void

        // MARK: - Initializer

        init(action: @escaping () -> Void) {
            self.action = action
        }

        // MARK: - Functions

        @objc func pressed() {
            action()
        }
    }
}

/// The push button behind `TaskCancelButton`.
final class CancelKeyNSButton: NSButton {

    // MARK: - Stored properties

    /// Whether the button holds the cancel keys, apart from typing in a box.
    ///
    /// Deliberately NOT written into `keyEquivalent`: measured on the main
    /// Mac (run `988-n4`, Keyboard Navigation on), a button whose
    /// `keyEquivalent` is Escape made AppKit keep Escape from a focused
    /// field even when the button refused it (the field's own Escape never
    /// ran). AppKit offers every key to every view's
    /// `performKeyEquivalent(with:)` whatever its `keyEquivalent`, so the
    /// button decides there and nowhere else.
    var holdsTheCancelKeys: Bool = false

    /// Escape, as AppKit spells a key equivalent.
    static let escape: String = "\u{1b}"

    // MARK: - Functions

    /// Whether `event` is Escape or Command-Period: Escape with no Command,
    /// Option or Control, or Period with Command alone.
    static func isACancelKey(_ event: NSEvent) -> Bool {
        if event.type != .keyDown {
            return false
        }
        let modifiers: NSEvent.ModifierFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key: String = event.charactersIgnoringModifiers ?? ""
        if key == CancelKeyNSButton.escape || event.keyCode == 53 {
            return modifiers.isEmpty
        }
        if key == "." {
            return modifiers == .command
        }
        return false
    }

    /// Whether the button takes a cancel key that has just arrived: it holds
    /// the keys, its window is the key window, and no text is being edited
    /// there (`KeyWindowTextEditing.isEditingText(in:)`, read now).
    static func takesTheCancelKey(holdsTheCancelKeys: Bool, windowIsKey: Bool, textIsBeingEdited: Bool) -> Bool {
        if !holdsTheCancelKeys || !windowIsKey {
            return false
        }
        return !textIsBeingEdited
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if !CancelKeyNSButton.isACancelKey(event) {
            return super.performKeyEquivalent(with: event)
        }
        let takesIt: Bool = CancelKeyNSButton.takesTheCancelKey(
            holdsTheCancelKeys: holdsTheCancelKeys,
            windowIsKey: window?.isKeyWindow ?? false,
            textIsBeingEdited: KeyWindowTextEditing.isEditingText(in: window)
        )
        if !takesIt {
            return false
        }
        // Drawn pressed, then the action, as a click on it is.
        performClick(nil)
        return true
    }
}
