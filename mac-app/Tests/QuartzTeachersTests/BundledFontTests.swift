import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Every font family the wizard offers must be available for previews
/// after the app registers its bundled fonts at launch.
final class BundledFontTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testEveryCatalogFamilyIsAvailableAfterRegistration() {
        // The hosted app has already run its initializer, but registering
        // again must also be harmless.
        BundledFontList.registerFonts()

        var familiesToCheck: [String] = []
        for pairing in FontCatalog.pairings {
            if pairing.header != "Helvetica, Arial" {
                familiesToCheck.append(pairing.header)
                familiesToCheck.append(pairing.body)
            }
        }
        for codeFont in FontCatalog.codeFonts {
            familiesToCheck.append(codeFont)
        }

        for familyName in familiesToCheck {
            let descriptor: NSFontDescriptor = NSFontDescriptor(fontAttributes: [.family: familyName])
            let matched: NSFontDescriptor? = descriptor.matchingFontDescriptor(withMandatoryKeys: [.family])
            XCTAssertNotNil(matched, "Font family should be registered and available: \(familyName)")
        }
    }

    // MARK: - The system pairing (#629)

    /// A site with the system pairing shows the reader's own system font
    /// (San Francisco on a Mac, Segoe UI on Windows), never Helvetica, so
    /// neither the label nor the preview may say Helvetica.
    @MainActor
    func testTheSystemPairingIsNotLabelledOrPreviewedAsHelvetica() {
        let label: String = FontCatalog.pairingLabel(header: "Helvetica, Arial", body: "Helvetica, Arial")
        XCTAssertTrue(label.hasPrefix("System fonts"), label)
        XCTAssertFalse(label.contains("Helvetica"), label)
        XCTAssertFalse(label.contains("Arial"), label)
        XCTAssertEqual(FontChoiceEditorView.previewFont(family: "Helvetica, Arial", size: 13), Font.system(size: 13))
    }

    // MARK: - Sample headline

    @MainActor
    func testTheFontSampleShowsTheCourseNameOnceItHasOne() {
        XCTAssertEqual(FontChoiceEditorView.headlineSample(for: "Drama"), "Drama")
        XCTAssertEqual(FontChoiceEditorView.headlineSample(for: "  Principles of Mathematics  "),
                       "Principles of Mathematics")
    }

    @MainActor
    func testTheFontSampleFallsBackBeforeANameExists() {
        XCTAssertEqual(FontChoiceEditorView.headlineSample(for: ""), "Grade 11 Computer Science")
        XCTAssertEqual(FontChoiceEditorView.headlineSample(for: "   "), "Grade 11 Computer Science")
    }
}
