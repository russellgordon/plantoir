import AppKit
import SwiftUI

/// The two colours a sentence about a problem wears (#994, HIG findings D37,
/// D38 and inconsistency 10), and the symbol that goes with each.
///
/// Russell's ruling, 2026-11-18: **red for a problem that stops the teacher
/// going ahead** (a name already taken, a form that will not submit, an act
/// that failed), **orange for a caution they can go past** (dates before
/// today). Each carries a symbol as well, so colour is never the only sign
/// (HIG, Color: "Avoid relying solely on color to differentiate between
/// objects, indicate interactivity, or communicate essential information").
///
/// Why not `.orange` and `.red`: the system orange measures 2.31:1 on a white
/// sheet in Light (1.98:1 measured on a real sheet), and the system red 3.57:1;
/// the minimum for text up to 17 points is 4.5:1 (HIG, Accessibility). The
/// system's Increase Contrast orange (R197 G83 B0) still measures only 3.74:1
/// on a sheet. So Light gets darker values of the same hues, with a darker
/// still variant for Increase Contrast ("If you define a custom color, make
/// sure to supply light and dark variants, and an increased contrast option
/// for each variant", HIG, Color). In Dark the system orange already passes
/// (7.47:1 on the window background) and is used as it is; the system red
/// measures 4.29:1 on a grouped Form row, so Dark gets a lighter red.
///
/// Every value is checked by `StatusColourTests` against the lightest and
/// darkest backgrounds a sentence sits on, in all four variants.
enum StatusColour {

    // MARK: - Stored properties

    /// Orange for a caution the teacher can go past.
    case warning

    /// Red for a problem that stops the teacher going ahead.
    case blocking

    // MARK: - Computed properties

    /// The colour as AppKit draws it, resolved for the appearance it is
    /// drawn in, Increase Contrast included.
    var nsColor: NSColor {
        switch self {
        case .warning:
            return StatusColour.warningNSColor
        case .blocking:
            return StatusColour.blockingNSColor
        }
    }

    /// The same colour for SwiftUI.
    var color: Color {
        return Color(nsColor: nsColor)
    }

    /// The symbol that says the same thing as the colour: a triangle for a
    /// caution (the one the sidebar and every caution label already wear), a
    /// stop sign for a problem that stops.
    var symbolName: String {
        switch self {
        case .warning:
            return "exclamationmark.triangle"
        case .blocking:
            return "xmark.octagon"
        }
    }

    // MARK: - Functions

    /// A sentence in this colour, led by this symbol, as ONE `Text`, so the
    /// modifiers each place already gives it (font, wrapping, identifier)
    /// keep working, and it wraps as a sentence does. VoiceOver hears the
    /// sentence alone, exactly as before: the words already say what kind of
    /// problem it is, and the symbol's own name would only get in the way.
    func sentence(_ words: String) -> Text {
        let symbol: Image = Image(systemName: symbolName)
        return Text("\(symbol) \(words)")
            .foregroundStyle(color)
            .accessibilityLabel(Text(words))
    }

    /// A sentence that is a caution or a stopping problem only some of the
    /// time: in that kind's colour and symbol when there is one, plain
    /// otherwise.
    static func sentence(_ words: String, wornAs kind: StatusColour?) -> Text {
        if let kind {
            return kind.sentence(words)
        }
        return Text(words)
    }

    /// The caution orange, resolved for the appearance it is drawn in and
    /// for Increase Contrast.
    static let warningNSColor: NSColor = NSColor(
        name: "plantoirWarning",
        dynamicProvider: StatusColour.resolvedWarning(for:)
    )

    /// The stopping red, resolved the same way.
    static let blockingNSColor: NSColor = NSColor(
        name: "plantoirBlocking",
        dynamicProvider: StatusColour.resolvedBlocking(for:)
    )

    /// This kind's value in one of the four variants.
    func value(for variant: AppearanceVariant) -> NSColor {
        switch self {
        case .warning:
            return StatusColour.warningValue(for: variant)
        case .blocking:
            return StatusColour.blockingValue(for: variant)
        }
    }

    /// The providers AppKit calls. They, and everything they call, are
    /// `nonisolated` because AppKit asks a dynamic colour for its value
    /// wherever it draws, not only on the main actor.
    nonisolated static func resolvedWarning(for appearance: NSAppearance) -> NSColor {
        return warningValue(for: variant(of: appearance, increasedContrast: systemIncreasesContrast()))
    }

    nonisolated static func resolvedBlocking(for appearance: NSAppearance) -> NSColor {
        return blockingValue(for: variant(of: appearance, increasedContrast: systemIncreasesContrast()))
    }

    /// The caution orange's four values. Light values are darker versions
    /// of the system orange's hue.
    nonisolated static func warningValue(for variant: AppearanceVariant) -> NSColor {
        switch variant {
        case .light:
            return NSColor(srgbRed: 168.0 / 255.0, green: 67.0 / 255.0, blue: 0.0, alpha: 1.0)
        case .lightIncreasedContrast:
            return NSColor(srgbRed: 122.0 / 255.0, green: 48.0 / 255.0, blue: 0.0, alpha: 1.0)
        case .dark, .darkIncreasedContrast:
            // The system orange passes in Dark, and carries its own
            // Increase Contrast variant (R255 G160 B86, lighter still).
            return NSColor.systemOrange
        }
    }

    /// The stopping red's four values.
    nonisolated static func blockingValue(for variant: AppearanceVariant) -> NSColor {
        switch variant {
        case .light:
            return NSColor(srgbRed: 191.0 / 255.0, green: 0.0, blue: 25.0 / 255.0, alpha: 1.0)
        case .lightIncreasedContrast:
            return NSColor(srgbRed: 158.0 / 255.0, green: 0.0, blue: 20.0 / 255.0, alpha: 1.0)
        case .dark:
            return NSColor(srgbRed: 1.0, green: 125.0 / 255.0, blue: 127.0 / 255.0, alpha: 1.0)
        case .darkIncreasedContrast:
            return NSColor(srgbRed: 1.0, green: 148.0 / 255.0, blue: 150.0 / 255.0, alpha: 1.0)
        }
    }

    /// Which of the four applies. Light or Dark comes from the appearance.
    /// Increase Contrast does NOT: on current macOS an appearance named
    /// `.accessibilityHighContrastAqua` reports itself as plain `.aqua`
    /// (measured 2026-11-19, `bestMatch(from:)` and `name` alike), so the
    /// setting is read from the system instead.
    nonisolated static func variant(of appearance: NSAppearance, increasedContrast: Bool) -> AppearanceVariant {
        let match: NSAppearance.Name? = appearance.bestMatch(from: [.aqua, .darkAqua])
        let isDark: Bool = match == .darkAqua
        if isDark && increasedContrast {
            return .darkIncreasedContrast
        }
        if isDark {
            return .dark
        }
        if increasedContrast {
            return .lightIncreasedContrast
        }
        return .light
    }

    /// Whether the teacher has Increase Contrast turned on.
    nonisolated static func systemIncreasesContrast() -> Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// The four appearances a colour must work in (HIG, Color: "Make sure
    /// all your app's colors work well in light, dark, and increased contrast
    /// contexts").
    nonisolated enum AppearanceVariant {
        case light
        case lightIncreasedContrast
        case dark
        case darkIncreasedContrast
    }
}
