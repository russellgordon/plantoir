import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Pins #994 (HIG findings D37, D38 and inconsistency 10): the orange a
/// caution wears and the red a stopping problem wears are readable in every
/// appearance, and no sentence in the app goes back to the system orange or
/// red, which are not.
///
/// The numbers are WCAG contrast ratios, the measure the HIG's Accessibility
/// page uses: at least 4.5:1 for text up to 17 points. No system setting is
/// changed: each of the four values (Light, Dark, and each with Increase
/// Contrast) is read from the Color Set in the asset catalog, which is what
/// ships, and the contrast is computed from it.
@MainActor
final class StatusColourTests: XCTestCase {

    // MARK: - Stored properties

    /// The minimum for text up to 17 points (HIG, Accessibility).
    let minimumRatio: Double = 4.5

    /// With Increase Contrast on, the HIG asks for "a significantly higher
    /// amount of visual differentiation"; the Dark Mode page's 7:1 "for
    /// custom foreground and background colors" is the bar used, on the
    /// plainest background.
    let increasedContrastRatio: Double = 7.0

    /// The lightest and darkest backgrounds a sentence sits on in Light: a
    /// white sheet, the grey of a sheet on glass (the inventory measured the
    /// system orange at 1.98:1 on one, which puts it near #ECECEC), and a
    /// grouped Form row's grey with margin to spare.
    let lightBackgrounds: [String] = ["FFFFFF", "ECECEC", "E0E0E0"]

    /// The same in Dark: the window background, a grouped Form row, and
    /// #3C3C3C, the lightest dark grey the app draws a sentence on (the
    /// review's figure, 2026-11-19).
    let darkBackgrounds: [String] = ["1E1E1E", "2D2D2D", "3C3C3C"]

    // MARK: - Contrast of every value that ships

    /// The caution orange: 4.5:1 or more on every background in all four
    /// variants, and 7:1 with Increase Contrast. The system orange it
    /// replaces measures 2.31:1 on white.
    func testTheCautionOrangeIsReadableInEveryVariant() throws {
        try assertReadable(StatusColour.warning)
    }

    /// The stopping red, the same. The system red measures 3.57:1 on white,
    /// and 3.31:1 on a dark Form row.
    func testTheStoppingRedIsReadableInEveryVariant() throws {
        try assertReadable(StatusColour.blocking)
    }

    /// The system colours fail the same check, so the tests above are not
    /// passing for a reason that has nothing to do with the values chosen.
    func testTheSystemColoursFailTheSameCheckInLight() {
        let light: NSAppearance = NSAppearance(named: .aqua)!
        let orange: String = StatusColourTests.hex(of: NSColor.systemOrange, in: light)
        let red: String = StatusColourTests.hex(of: NSColor.systemRed, in: light)
        let minimum: Double = minimumRatio
        let orangeRatio: Double = StatusColourTests.contrastRatio(orange, "FFFFFF")
        let redRatio: Double = StatusColourTests.contrastRatio(red, "FFFFFF")
        XCTAssertLessThan(orangeRatio, minimum, orange)
        XCTAssertLessThan(redRatio, minimum, red)
    }

    /// Increase Contrast has a value of its own in Light and in Dark, and in
    /// Light it is the stronger of the two.
    func testIncreaseContrastHasItsOwnStrongerValues() throws {
        for kind in [StatusColour.warning, StatusColour.blocking] {
            let values: [String: String] = try StatusColourTests.assetValues(of: kind)
            let kindName: String = "\(kind)"
            let light: String = try XCTUnwrap(values["light"], kindName)
            let lightIncreased: String = try XCTUnwrap(values["lightIncreasedContrast"], kindName)
            let dark: String = try XCTUnwrap(values["dark"], kindName)
            let darkIncreased: String = try XCTUnwrap(values["darkIncreasedContrast"], kindName)
            XCTAssertNotEqual(light, lightIncreased, kindName)
            XCTAssertNotEqual(dark, darkIncreased, kindName)
            let normalRatio: Double = StatusColourTests.contrastRatio(light, "FFFFFF")
            let increasedRatio: Double = StatusColourTests.contrastRatio(lightIncreased, "FFFFFF")
            XCTAssertGreaterThan(increasedRatio, normalRatio, kindName)
        }
    }

    /// The colour the app draws is the Color Set's: resolved in Light and
    /// in Dark it gives the catalog's Light and Dark values. (Increase
    /// Contrast is the system's to apply to an asset colour; on current
    /// macOS an appearance made as `.accessibilityHighContrastAqua` reports
    /// itself as plain Aqua, so the high-contrast values are checked from
    /// the catalog above, not by resolving here.)
    func testTheAppDrawsTheColorSetsValues() throws {
        for kind in [StatusColour.warning, StatusColour.blocking] {
            let values: [String: String] = try StatusColourTests.assetValues(of: kind)
            let kindName: String = "\(kind)"
            let colour: NSColor = try XCTUnwrap(NSColor(named: kind.assetName), "\(kindName) is in the asset catalog")
            let drawnLight: String = StatusColourTests.hex(of: colour, in: NSAppearance(named: .aqua)!)
            let drawnDark: String = StatusColourTests.hex(of: colour, in: NSAppearance(named: .darkAqua)!)
            XCTAssertEqual(drawnLight, values["light"], kindName)
            XCTAssertEqual(drawnDark, values["dark"], kindName)
        }
    }

    /// The caution stays orange in every variant, and the stop stays red:
    /// their hues are far apart, so the two read as two kinds. (The darkest
    /// orange, Light with Increase Contrast, is #983C00: the brightest
    /// orange that reaches 7:1 on white. It is dark, so its symbol carries
    /// the kind as much as its hue.)
    func testTheCautionStaysOrangeAndTheStopStaysRed() throws {
        let orange: [String: String] = try StatusColourTests.assetValues(of: .warning)
        let red: [String: String] = try StatusColourTests.assetValues(of: .blocking)
        for (variant, value) in orange {
            let hue: Double = StatusColourTests.hue(of: value)
            XCTAssertTrue(hue >= 18 && hue <= 40, "orange \(variant) #\(value) has hue \(hue)")
        }
        for (variant, value) in red {
            let hue: Double = StatusColourTests.hue(of: value)
            XCTAssertTrue(hue >= 340 || hue <= 4, "red \(variant) #\(value) has hue \(hue)")
        }
    }

    // MARK: - Colour is never the only sign

    /// A caution and a stopping problem carry different symbols, so a
    /// teacher who cannot tell the two colours apart can still tell the two
    /// kinds apart (HIG, Color, "Inclusive color").
    func testTheTwoKindsCarryDifferentSymbols() {
        let cautionSymbol: String = StatusColour.warning.symbolName
        let stopSymbol: String = StatusColour.blocking.symbolName
        XCTAssertNotEqual(cautionSymbol, stopSymbol)
        for name in [cautionSymbol, stopSymbol, StatusColour.warning.filledSymbolName, StatusColour.blocking.filledSymbolName] {
            let image: NSImage? = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            XCTAssertNotNil(image, name)
        }
    }

    // MARK: - On a selected row (D38)

    /// On a selected row a status colour gives way to the row's own text
    /// colour (white on the blue selection, 5.37:1), as the row's words do;
    /// the orange measured 1.45:1 there in the sidebar and 1.13:1 in the
    /// documents table.
    func testAStatusColourFollowsASelectedRow() {
        let followsWhenSelected: Bool = StatusColour.followsTheRow(prominence: .increased)
        let followsWhenNot: Bool = StatusColour.followsTheRow(prominence: .standard)
        XCTAssertTrue(followsWhenSelected)
        XCTAssertFalse(followsWhenNot)
    }

    /// The documents table is AppKit: its caution symbol follows the row
    /// through the cell's background style, which AppKit sets as the row's
    /// selection changes.
    func testTheTableCellsSymbolFollowsASelectedRow() {
        let cell: StatusTintedTableCellView = StatusTintedTableCellView()
        let image: NSImageView = NSImageView()
        cell.imageView = image
        cell.backgroundStyle = .emphasized
        let light: NSAppearance = NSAppearance(named: .aqua)!
        let selectedTint: NSColor = image.contentTintColor ?? NSColor.clear
        cell.backgroundStyle = .normal
        let plainTint: NSColor = image.contentTintColor ?? NSColor.clear
        let selectedHex: String = StatusColourTests.hex(of: selectedTint, in: light)
        let plainHex: String = StatusColourTests.hex(of: plainTint, in: light)
        let whiteHex: String = StatusColourTests.hex(of: NSColor.alternateSelectedControlTextColor, in: light)
        let orangeHex: String = StatusColourTests.hex(of: StatusColour.warning.nsColor, in: light)
        XCTAssertEqual(selectedHex, whiteHex)
        XCTAssertEqual(plainHex, orangeHex)
        XCTAssertNotEqual(selectedHex, plainHex)
    }

    // MARK: - Nothing goes back to the system orange or red

    /// Every orange or red the app target draws comes from `StatusColour`.
    /// The scan covers every Swift file under `QuartzTeachers/` and every
    /// way a system orange or red is written: `.orange` and `.red` wherever
    /// they appear (`.foregroundStyle(.red)`, `.tint(.orange)`,
    /// `return … .red`, `.fill(.orange)`, `.foregroundColor(.red)`,
    /// `Color.orange`, `NSColor.red`), and `systemOrange` and `systemRed`.
    /// Comment lines are skipped. The exemptions are named below, each with
    /// its reason, and an exemption that no longer matches fails too.
    func testNothingInTheAppUsesTheSystemOrangeOrRed() throws {
        let productFolder: URL = ActivityTrailWiringTests.productSourceFolderURL()
        let files: [URL] = ActivityTrailWiringTests.swiftFiles(under: productFolder)
        XCTAssertGreaterThan(files.count, 100, "the scan found the app's sources")
        let systemColour: NSRegularExpression = try NSRegularExpression(
            pattern: "(^|[^A-Za-z0-9_])\\.(orange|red)\\b|system(Orange|Red)\\b"
        )
        // File name, then a piece of the line, then why it is allowed.
        let exemptions: [(String, String, String)] = [
            ("AssistWindowView.swift", ".tint(isDeploy ? .orange : .accentColor)",
             "the Deploy button's tint: a button, not a status; its contrast (2.31:1) is a separate issue"),
            ("TaskProgressView.swift", "Label(\"Cancelled\"",
             "a status, not a problem: kept as it was (review of #994)"),
            ("TaskProgressView.swift", "Label(\"Waiting for your answer…\"",
             "a status, not a problem: kept as it was (review of #994)"),
            ("TaskProgressView.swift", "Label(\"Cancelling…\"",
             "a status, not a problem: kept as it was (review of #994)"),
        ]
        var exemptionsUsed: Set<Int> = []
        var offences: [String] = []
        for file in files {
            let text: String = try String(contentsOf: file, encoding: .utf8)
            let lines: [String] = text.components(separatedBy: "\n")
            var lineNumber: Int = 0
            for line in lines {
                lineNumber += 1
                let trimmed: String = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") {
                    continue
                }
                let range: NSRange = NSRange(line.startIndex..<line.endIndex, in: line)
                if systemColour.firstMatch(in: line, range: range) == nil {
                    continue
                }
                var exempted: Bool = false
                var index: Int = 0
                for (fileName, piece, _) in exemptions {
                    if file.lastPathComponent == fileName && StatusColourTests.line(lineNumber, of: lines, orTheTwoAboveContain: piece) {
                        exempted = true
                        exemptionsUsed.insert(index)
                    }
                    index += 1
                }
                if !exempted {
                    offences.append("\(file.lastPathComponent):\(lineNumber): \(trimmed)")
                }
            }
        }
        let report: String = offences.joined(separator: "\n")
        XCTAssertEqual(offences, [], report)
        var index: Int = 0
        for (fileName, piece, _) in exemptions {
            let used: Bool = exemptionsUsed.contains(index)
            XCTAssertTrue(used, "the exemption for \(fileName) (\(piece)) matches nothing now; remove it")
            index += 1
        }
    }

    // MARK: - Functions

    /// Fails for every background a value is below the minimum on, in every
    /// variant, naming the variant, the value and the ratio.
    func assertReadable(_ kind: StatusColour, file: StaticString = #filePath, line: UInt = #line) throws {
        let values: [String: String] = try StatusColourTests.assetValues(of: kind)
        let kindName: String = "\(kind)"
        let minimum: Double = minimumRatio
        let increasedMinimum: Double = increasedContrastRatio
        let cases: [(String, [String], Bool)] = [
            ("light", lightBackgrounds, false),
            ("lightIncreasedContrast", lightBackgrounds, true),
            ("dark", darkBackgrounds, false),
            ("darkIncreasedContrast", darkBackgrounds, true),
        ]
        for (variant, backgrounds, isIncreased) in cases {
            let foreground: String = try XCTUnwrap(values[variant], "\(kindName) has no \(variant) value")
            for background in backgrounds {
                let ratio: Double = StatusColourTests.contrastRatio(foreground, background)
                XCTAssertGreaterThanOrEqual(
                    ratio, minimum,
                    "\(kindName) \(variant): #\(foreground) on #\(background) is \(ratio)",
                    file: file, line: line
                )
            }
            if isIncreased {
                let plainest: String = backgrounds[0]
                let ratio: Double = StatusColourTests.contrastRatio(foreground, plainest)
                XCTAssertGreaterThanOrEqual(
                    ratio, increasedMinimum,
                    "\(kindName) \(variant): #\(foreground) on #\(plainest) is \(ratio)",
                    file: file, line: line
                )
            }
        }
    }

    /// Whether a line, or one of the two above it, contains a piece of text
    /// (a modifier usually sits a line or two under the view it colours).
    static func line(_ number: Int, of lines: [String], orTheTwoAboveContain piece: String) -> Bool {
        var index: Int = number - 1
        let lowest: Int = max(0, number - 3)
        while index >= lowest {
            if lines[index].contains(piece) {
                return true
            }
            index -= 1
        }
        return false
    }

    /// The four values of a Color Set, as six hex digits keyed by variant
    /// ("light", "lightIncreasedContrast", "dark", "darkIncreasedContrast"),
    /// read from the asset catalog's source.
    static func assetValues(of kind: StatusColour) throws -> [String: String] {
        let url: URL = ActivityTrailWiringTests.productSourceFolderURL()
            .appendingPathComponent("StatusColours.xcassets", isDirectory: true)
            .appendingPathComponent(kind.assetName + ".colorset", isDirectory: true)
            .appendingPathComponent("Contents.json")
        let data: Data = try Data(contentsOf: url)
        let root: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let colours: [[String: Any]] = try XCTUnwrap(root["colors"] as? [[String: Any]])
        var result: [String: String] = [:]
        for entry in colours {
            var isDark: Bool = false
            var isHigh: Bool = false
            for appearance in (entry["appearances"] as? [[String: String]]) ?? [] {
                if appearance["appearance"] == "luminosity" && appearance["value"] == "dark" {
                    isDark = true
                }
                if appearance["appearance"] == "contrast" && appearance["value"] == "high" {
                    isHigh = true
                }
            }
            let colour: [String: Any] = try XCTUnwrap(entry["color"] as? [String: Any])
            let components: [String: String] = try XCTUnwrap(colour["components"] as? [String: String])
            var hex: String = ""
            for channel in ["red", "green", "blue"] {
                let written: String = try XCTUnwrap(components[channel])
                hex += written.replacingOccurrences(of: "0x", with: "").uppercased()
            }
            var key: String = isDark ? "dark" : "light"
            if isHigh {
                key += "IncreasedContrast"
            }
            result[key] = hex
        }
        return result
    }

    /// The hue, in degrees, of six hex digits.
    static func hue(of hex: String) -> Double {
        let characters: [Character] = Array(hex)
        let red: Double = Double(Int(String(characters[0...1]), radix: 16) ?? 0) / 255.0
        let green: Double = Double(Int(String(characters[2...3]), radix: 16) ?? 0) / 255.0
        let blue: Double = Double(Int(String(characters[4...5]), radix: 16) ?? 0) / 255.0
        let colour: NSColor = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
        return Double(colour.hueComponent) * 360.0
    }

    /// The colour as six hex digits, resolved in an appearance.
    static func hex(of colour: NSColor, in appearance: NSAppearance) -> String {
        var result: String = ""
        appearance.performAsCurrentDrawingAppearance {
            let resolved: NSColor = colour.usingColorSpace(.sRGB) ?? colour
            let red: Int = Int((resolved.redComponent * 255.0).rounded())
            let green: Int = Int((resolved.greenComponent * 255.0).rounded())
            let blue: Int = Int((resolved.blueComponent * 255.0).rounded())
            result = String(format: "%02X%02X%02X", red, green, blue)
        }
        return result
    }

    /// The WCAG contrast ratio between two colours given as hex digits.
    static func contrastRatio(_ first: String, _ second: String) -> Double {
        let firstLuminance: Double = relativeLuminance(first)
        let secondLuminance: Double = relativeLuminance(second)
        let lighter: Double = max(firstLuminance, secondLuminance)
        let darker: Double = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// WCAG relative luminance of six hex digits.
    static func relativeLuminance(_ hex: String) -> Double {
        let characters: [Character] = Array(hex)
        let red: Double = linear(String(characters[0...1]))
        let green: Double = linear(String(characters[2...3]))
        let blue: Double = linear(String(characters[4...5]))
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// One channel, from two hex digits to linear light.
    static func linear(_ channel: String) -> Double {
        let value: Double = Double(Int(channel, radix: 16) ?? 0) / 255.0
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }
}
