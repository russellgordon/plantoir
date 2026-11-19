import Foundation

/// Loads the bundled copy of `colour_schemes.json` (the repository's
/// `support/colour_schemes.json`, included as an app resource).
enum ColourSchemeCatalog {

    // MARK: - Stored properties

    static let schemes: [ColourScheme] = loadSchemes()

    // MARK: - Functions

    static func scheme(withID schemeID: String) -> ColourScheme? {
        for scheme in schemes {
            if scheme.id == schemeID {
                return scheme
            }
        }
        return nil
    }

    /// The schemes a picker offers a section whose stored scheme id is
    /// `sectionSchemeID`, in the file's order (shared-rules.json →
    /// colourSchemePicker, #891). Every listed scheme is offered. An
    /// unlisted one is offered only when it is the section's own scheme,
    /// and then it takes the place of the listed scheme it is the same as,
    /// so the picker selects it and shows its name once. Nothing is
    /// written by showing the list.
    static func schemesToList(forSectionSchemeID sectionSchemeID: String, in candidates: [ColourScheme]) -> [ColourScheme] {
        var ownUnlistedScheme: ColourScheme? = nil
        for scheme in candidates {
            if scheme.id == sectionSchemeID && !scheme.isListed {
                ownUnlistedScheme = scheme
            }
        }
        var result: [ColourScheme] = []
        for scheme in candidates {
            if scheme.isListed {
                if let ownUnlisted = ownUnlistedScheme, ownUnlisted.sameAs == scheme.id {
                    continue
                }
                result.append(scheme)
            } else if scheme.id == sectionSchemeID {
                result.append(scheme)
            }
        }
        return result
    }

    private static func loadSchemes() -> [ColourScheme] {
        guard let url = Bundle.main.url(forResource: "colour_schemes", withExtension: "json") else {
            return []
        }
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        // The file is either a bare array or {"schemes": [...]}.
        var rawSchemes: [Any] = []
        if let dictionary = decoded as? [String: Any] {
            if let inner = dictionary["schemes"] as? [Any] {
                rawSchemes = inner
            }
        } else if let array = decoded as? [Any] {
            rawSchemes = array
        }

        var result: [ColourScheme] = []
        for rawScheme in rawSchemes {
            guard let schemeDictionary = rawScheme as? [String: Any] else {
                continue
            }
            guard let schemeID = schemeDictionary["id"] as? String else {
                continue
            }
            var name: String = schemeID
            if let storedName = schemeDictionary["name"] as? String {
                name = storedName
            }
            var isListed: Bool = true
            if let storedListed = schemeDictionary["listed"] as? Bool {
                isListed = storedListed
            }
            let sameAs: String? = schemeDictionary["sameAs"] as? String
            var lightModeColors: [String: String] = [:]
            var darkModeColors: [String: String] = [:]
            if let colors = schemeDictionary["colors"] as? [String: Any] {
                if let lightMode = colors["lightMode"] as? [String: String] {
                    lightModeColors = lightMode
                }
                if let darkMode = colors["darkMode"] as? [String: String] {
                    darkModeColors = darkMode
                }
            }
            let scheme: ColourScheme = ColourScheme(
                id: schemeID,
                name: name,
                isListed: isListed,
                sameAs: sameAs,
                lightModeColors: lightModeColors,
                darkModeColors: darkModeColors
            )
            result.append(scheme)
        }
        return result
    }
}
