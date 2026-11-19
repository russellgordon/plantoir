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
/// The values live in the asset catalog (`StatusColours.xcassets`,
/// `StatusWarning` and `StatusBlocking`), each with Any, Dark, and High
/// Contrast variants of both, so the system picks the variant and redraws
/// when the teacher switches appearance or Increase Contrast (HIG, Dark
/// Mode: "When you need a custom color, add a Color Set asset to your app's
/// asset catalog"). A first version read the setting by hand and observed
/// nothing, so a change while the app ran was never shown.
///
/// Why not `.orange` and `.red`: the system orange measures 2.31:1 on a white
/// sheet in Light (1.98:1 measured on a real sheet), and the system red 3.57:1;
/// the minimum for text up to 17 points is 4.5:1 (HIG, Accessibility). The
/// system's Increase Contrast orange (R197 G83 B0) still measures only 3.74:1
/// on a sheet. So Light gets darker values of the same hues, with a darker
/// still variant for Increase Contrast ("If you define a custom color, make
/// sure to supply light and dark variants, and an increased contrast option
/// for each variant", HIG, Color). In Dark the orange is the system orange's
/// own published values (R255 G146 B48, and R255 G160 B86 with Increase
/// Contrast, from the HIG's Color page), which pass; the system red measures
/// 4.29:1 on a grouped Form row, so Dark gets a lighter red.
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

    /// The Color Set's name in `StatusColours.xcassets`.
    nonisolated var assetName: String {
        switch self {
        case .warning:
            return "StatusWarning"
        case .blocking:
            return "StatusBlocking"
        }
    }

    /// The colour as AppKit draws it; the asset catalog resolves it for the
    /// appearance and for Increase Contrast.
    var nsColor: NSColor {
        return NSColor(named: assetName) ?? NSColor.labelColor
    }

    /// The same colour for SwiftUI, for a place whose background never
    /// changes (a tint behind a band, say). Text and symbols use `style`.
    var color: Color {
        return Color(assetName)
    }

    /// The style a sentence or symbol wears: this colour, except on a
    /// selected row, where it takes the selected row's text colour as the
    /// row's words do (#994, D38: no orange or red reaches 3:1 on the blue
    /// selection).
    var style: StatusStyle {
        return StatusStyle(kind: self)
    }

    /// The symbol that says the same thing as the colour: a triangle for a
    /// caution (the one the sidebar and every caution label already wear), a
    /// stop sign for a problem that stops. One symbol per meaning, app-wide.
    var symbolName: String {
        switch self {
        case .warning:
            return "exclamationmark.triangle"
        case .blocking:
            return "xmark.octagon"
        }
    }

    /// The filled form, for a symbol that stands on its own (a badge, a
    /// console outcome).
    var filledSymbolName: String {
        return symbolName + ".fill"
    }

    // MARK: - Functions

    /// A sentence in this colour, led by this symbol, as ONE `Text`, so the
    /// modifiers each place already gives it (font, wrapping, identifier)
    /// keep working, and it wraps as a sentence does. VoiceOver hears the
    /// sentence alone, exactly as before. Not for text a teacher can select
    /// and copy: the symbol would be copied with it; use `StatusLine`.
    func sentence(_ words: String) -> Text {
        let symbol: Image = Image(systemName: symbolName)
        return Text("\(symbol) \(words)")
            .foregroundStyle(style)
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

    /// Whether a status colour gives way to the row's own text colour: on a
    /// selected row (increased background prominence) it does.
    nonisolated static func followsTheRow(prominence: BackgroundProminence) -> Bool {
        return prominence == .increased
    }
}

/// `StatusColour`'s style, resolved where it is drawn: the status colour,
/// or on a selected row the selected row's text colour.
struct StatusStyle: ShapeStyle {

    // MARK: - Stored properties

    let kind: StatusColour

    // MARK: - Functions

    nonisolated func resolve(in environment: EnvironmentValues) -> Color {
        if StatusColour.followsTheRow(prominence: environment.backgroundProminence) {
            return Color(nsColor: NSColor.alternateSelectedControlTextColor)
        }
        return Color(kind.assetName)
    }
}

/// A status sentence whose words can be selected and copied: the symbol
/// sits beside the words rather than inside them, so a copy carries the
/// words alone.
struct StatusLine: View {

    // MARK: - Stored properties

    let kind: StatusColour
    let words: String

    // MARK: - Computed properties

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: kind.symbolName)
                .foregroundStyle(kind.style)
                .accessibilityHidden(true)
            Text(words)
                .foregroundStyle(kind.style)
        }
        .accessibilityElement(children: .combine)
    }
}
