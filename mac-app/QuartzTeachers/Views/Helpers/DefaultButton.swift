import SwiftUI

/// A sheet's main button: Return presses it and it wears the accent — but
/// ONLY while it can be pressed.
///
/// macOS draws a button carrying `.keyboardShortcut(.defaultAction)` in the
/// accent colour whether or not it is enabled; a disabled one is merely
/// dimmed, and a dim blue button reads as one that can be pressed. Measured
/// in the HIG sweep (#457): Copy a Page's Copy, disabled with "There is no
/// other course to copy into yet", was drawn dim blue, and so was Schedule a
/// Deploy's Schedule, which carried `.borderedProminent` and no Return at
/// all. #364 fixed the same confusion for Course Settings' Save by swapping
/// the style on the same predicate that enables it; this is that rule made
/// one modifier, so every sheet follows it the same way.
///
/// So while the button cannot be pressed it is a plain grey push button with
/// no key equivalent, and the moment it can be, it is the default button.
/// `SheetConventionScanTests.testNoDisabledButtonWearsTheDefaultLook` pins
/// that no button writes the default look and `.disabled(` side by side.
struct DefaultButtonModifier: ViewModifier {

    // MARK: - Stored properties

    let isEnabled: Bool

    /// False for a button that must not be pressed by a Return typed out of
    /// habit — going ahead with a synced working folder is a decision.
    var isTheDefault: Bool = true

    // MARK: - Functions

    func body(content: Content) -> some View {
        // Written as the dialog key it is (Return or nothing), so
        // `KeyEquivalentPlacementScanTests` reads it as one.
        let takesReturn: Bool = DefaultButtonModifier.shortcut(isEnabled: isEnabled, isTheDefault: isTheDefault) != nil
        content
            .keyboardShortcut(takesReturn ? .defaultAction : nil)
            .disabled(!isEnabled)
    }

    /// Return while the button can be pressed; nothing otherwise, so the
    /// system does not draw it as the default.
    static func shortcut(isEnabled: Bool, isTheDefault: Bool = true) -> KeyboardShortcut? {
        if isEnabled && isTheDefault {
            return .defaultAction
        }
        return nil
    }
}

extension View {

    /// See `DefaultButtonModifier`.
    func defaultButton(isEnabled: Bool, isTheDefault: Bool = true) -> some View {
        return modifier(DefaultButtonModifier(isEnabled: isEnabled, isTheDefault: isTheDefault))
    }

    /// See `ProminentButtonModifier`.
    func prominentButton(isEnabled: Bool) -> some View {
        return modifier(ProminentButtonModifier(isEnabled: isEnabled))
    }
}

/// A button that wears the accent WITHOUT taking Return — an empty state's
/// main action, say — and, like `DefaultButtonModifier`, only while it can
/// be pressed: `.borderedProminent` draws a disabled button dim blue.
struct ProminentButtonModifier: ViewModifier {

    // MARK: - Stored properties

    let isEnabled: Bool

    // MARK: - Functions

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .buttonStyle(.borderedProminent)
        } else {
            content
                .buttonStyle(.bordered)
                .disabled(true)
        }
    }
}
