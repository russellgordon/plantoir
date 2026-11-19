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
/// page uses: at least 4.5:1 for text up to 17 points. They are computed from
/// the colour values; no system setting is changed. Increase Contrast reaches
/// an app as the high-contrast appearance names, so each colour is resolved
/// under all four.
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

    /// The same in Dark: the window background, and a grouped Form row up to
    /// the lightest grey macOS draws one in.
    let darkBackgrounds: [String] = ["1E1E1E", "2D2D2D", "3A3A3A"]

    // MARK: - Contrast in every appearance

    /// The caution orange: 4.5:1 or more on every background, in all four
    /// appearances. The system orange it replaces measures 2.31:1 on white.
    func testTheCautionOrangeIsReadableInEveryAppearance() {
        assertReadable(StatusColour.warning)
    }

    /// The stopping red: 4.5:1 or more on every background, in all four
    /// appearances. The system red it replaces measures 3.57:1 on white,
    /// and 3.31:1 on a dark Form row.
    func testTheStoppingRedIsReadableInEveryAppearance() {
        assertReadable(StatusColour.blocking)
    }

    /// The system colours fail the same check, so the test above is not
    /// passing for a reason that has nothing to do with the values chosen.
    func testTheSystemColoursFailTheSameCheckInLight() {
        let light: NSAppearance = NSAppearance(named: .aqua)!
        let orange: String = StatusColourTests.hex(of: NSColor.systemOrange, in: light)
        let red: String = StatusColourTests.hex(of: NSColor.systemRed, in: light)
        XCTAssertLessThan(StatusColourTests.contrastRatio(orange, "FFFFFF"), minimumRatio, orange)
        XCTAssertLessThan(StatusColourTests.contrastRatio(red, "FFFFFF"), minimumRatio, red)
    }

    /// Increase Contrast must make a real difference in Light, where the
    /// default values are the ones nearest the minimum.
    func testIncreaseContrastIsDarkerStillInLight() {
        let light: NSAppearance = NSAppearance(named: .aqua)!
        let lightIncreased: NSAppearance = NSAppearance(named: .accessibilityHighContrastAqua)!
        for kind in [StatusColour.warning, StatusColour.blocking] {
            let normal: String = StatusColourTests.hex(of: kind.nsColor, in: light)
            let increased: String = StatusColourTests.hex(of: kind.nsColor, in: lightIncreased)
            XCTAssertNotEqual(normal, increased, "\(kind) has no Increase Contrast variant")
            XCTAssertGreaterThan(
                StatusColourTests.contrastRatio(increased, "FFFFFF"),
                StatusColourTests.contrastRatio(normal, "FFFFFF"),
                "\(kind): Increase Contrast must be the stronger of the two"
            )
        }
    }

    /// The four appearance names map to the four variants.
    func testEachAppearanceIsReadAsItsOwnVariant() {
        XCTAssertEqual(StatusColour.variant(of: NSAppearance(named: .aqua)!), .light)
        XCTAssertEqual(StatusColour.variant(of: NSAppearance(named: .darkAqua)!), .dark)
        XCTAssertEqual(
            StatusColour.variant(of: NSAppearance(named: .accessibilityHighContrastAqua)!), .lightIncreasedContrast
        )
        XCTAssertEqual(
            StatusColour.variant(of: NSAppearance(named: .accessibilityHighContrastDarkAqua)!), .darkIncreasedContrast
        )
    }

    // MARK: - Colour is never the only sign

    /// A caution and a stopping problem carry different symbols, so a
    /// teacher who cannot tell the two colours apart can still tell the two
    /// kinds apart (HIG, Color, "Inclusive color").
    func testTheTwoKindsCarryDifferentSymbols() {
        XCTAssertNotEqual(StatusColour.warning.symbolName, StatusColour.blocking.symbolName)
        XCTAssertNotNil(NSImage(systemSymbolName: StatusColour.warning.symbolName, accessibilityDescription: nil))
        XCTAssertNotNil(NSImage(systemSymbolName: StatusColour.blocking.symbolName, accessibilityDescription: nil))
    }

    // MARK: - The sidebar's stopped-deploy badge (D38)

    /// On a selected row the badge takes the row's own colour (white on the
    /// blue selection, 5.37:1), as the row's words do; the orange measured
    /// 1.45:1 there. On an unselected row it wears the caution orange.
    func testTheBadgeFollowsASelectedRow() {
        XCTAssertTrue(SidebarView.warningBadgeFollowsTheRow(prominence: .increased))
        XCTAssertFalse(SidebarView.warningBadgeFollowsTheRow(prominence: .standard))
    }

    // MARK: - Nothing goes back to the system orange or red

    /// Every sentence and caution symbol in the app's views takes its colour
    /// from `StatusColour`. A view that writes `.orange` or `.red` again is
    /// back below 4.5:1 in Light, so this fails on it. One use is left, and
    /// is named: the Assistant window's Deploy button tint, a button and not
    /// a sentence (reported with #994, not changed by it).
    func testNoViewUsesTheSystemOrangeOrRedForASentence() throws {
        let viewsFolder: URL = ActivityTrailWiringTests.productSourceFolderURL()
            .appendingPathComponent("Views", isDirectory: true)
        let files: [URL] = ActivityTrailWiringTests.swiftFiles(under: viewsFolder)
        XCTAssertGreaterThan(files.count, 50, "the scan found the views")
        let forbidden: [String] = [
            ".foregroundStyle(.orange)",
            ".foregroundStyle(.red)",
            "Color.orange",
            "Color.red",
            ".systemOrange",
            ".systemRed",
        ]
        var offences: [String] = []
        for file in files {
            if file.lastPathComponent == "StatusColour.swift" {
                continue
            }
            let text: String = try String(contentsOf: file, encoding: .utf8)
            var lineNumber: Int = 0
            for line in text.components(separatedBy: "\n") {
                lineNumber += 1
                for pattern in forbidden {
                    if line.contains(pattern) {
                        offences.append("\(file.lastPathComponent):\(lineNumber): \(pattern)")
                    }
                }
            }
        }
        XCTAssertEqual(offences, [], offences.joined(separator: "\n"))
    }

    // MARK: - Functions

    /// Fails for every background the colour is below the minimum on, in
    /// every appearance, naming the appearance, the value and the ratio.
    func assertReadable(_ kind: StatusColour, file: StaticString = #filePath, line: UInt = #line) {
        let cases: [(NSAppearance.Name, [String], Bool)] = [
            (.aqua, lightBackgrounds, false),
            (.accessibilityHighContrastAqua, lightBackgrounds, true),
            (.darkAqua, darkBackgrounds, false),
            (.accessibilityHighContrastDarkAqua, darkBackgrounds, true),
        ]
        for (name, backgrounds, isIncreased) in cases {
            let appearance: NSAppearance = NSAppearance(named: name)!
            let foreground: String = StatusColourTests.hex(of: kind.nsColor, in: appearance)
            for background in backgrounds {
                let ratio: Double = StatusColourTests.contrastRatio(foreground, background)
                XCTAssertGreaterThanOrEqual(
                    ratio, minimumRatio,
                    "\(kind) in \(name.rawValue): #\(foreground) on #\(background) is \(ratio)",
                    file: file, line: line
                )
            }
            if isIncreased {
                let plainest: String = backgrounds[0]
                let ratio: Double = StatusColourTests.contrastRatio(foreground, plainest)
                XCTAssertGreaterThanOrEqual(
                    ratio, increasedContrastRatio,
                    "\(kind) in \(name.rawValue): #\(foreground) on #\(plainest) is \(ratio)",
                    file: file, line: line
                )
            }
        }
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
