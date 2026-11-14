import Foundation

/// One named colour scheme from `colour_schemes.json` — the same file the
/// setup wizard's terminal picker reads (bundled with the app).
struct ColourScheme: Identifiable, Equatable {

    // MARK: - Stored properties

    let id: String
    let name: String

    /// False for an entry kept only so courses that stored its id keep
    /// their colours (`"listed": false` in the file, #891). A picker shows
    /// it only to a section whose own scheme it is.
    let isListed: Bool

    /// For an unlisted entry, the id of the listed entry with the same name
    /// and colours (`sameAs`). A picker shows the unlisted entry in that
    /// one's place, so the name appears once.
    let sameAs: String?

    /// Quartz theme colour names → hex strings for light mode.
    let lightModeColors: [String: String]

    /// Quartz theme colour names → hex strings for dark mode.
    let darkModeColors: [String: String]

    // MARK: - Computed properties

    /// A few representative light-mode colours for a swatch preview,
    /// in a stable order.
    var swatchHexValues: [String] {
        let preferredKeys: [String] = ["secondary", "tertiary", "dark", "light"]
        var result: [String] = []
        for key in preferredKeys {
            if let hex = lightModeColors[key] {
                result.append(hex)
            }
        }
        return result
    }
}
