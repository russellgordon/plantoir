import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` → `colourSchemePicker` against the
/// list the mac's colour-scheme picker shows (#891). Grove Colours is kept
/// under two ids: the listed `grove-colours`, and the id courses stored
/// before 2.0.0, kept unlisted so those courses look the same and are never
/// rewritten. The old id is read from the bundled scheme list, never typed
/// here.
final class ColourSchemePickerTests: XCTestCase {

    // MARK: - Stored properties

    private let groveID: String = "grove-colours"

    // MARK: - Tests

    func testTheBundledListHoldsGroveColoursTwiceAndOffersItOnce() throws {
        let schemes: [ColourScheme] = ColourSchemeCatalog.schemes
        let grove: ColourScheme = try XCTUnwrap(ColourSchemeCatalog.scheme(withID: groveID))
        XCTAssertTrue(grove.isListed)
        let twin: ColourScheme = try XCTUnwrap(unlistedTwin(of: groveID, in: schemes))
        XCTAssertEqual(twin.name, grove.name)
        XCTAssertEqual(twin.lightModeColors, grove.lightModeColors)
        XCTAssertEqual(twin.darkModeColors, grove.darkModeColors)
    }

    func testTheContractCases() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("colourSchemePicker")
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5, "colourSchemePicker.cases has shrunk")
        let schemes: [ColourScheme] = ColourSchemeCatalog.schemes

        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var storedID: String = ""
            var expectedSelection: String = ""
            var placeTakenBy: String? = nil
            var placeTaken: String? = nil
            if let twinOf = testCase["sectionSchemeIsTheUnlistedTwinOf"] as? String {
                let twin: ColourScheme = try XCTUnwrap(unlistedTwin(of: twinOf, in: schemes), name)
                storedID = twin.id
                expectedSelection = twin.id
                placeTakenBy = twin.id
                placeTaken = testCase["twinTakesThePlaceOf"] as? String
            } else {
                storedID = try XCTUnwrap(testCase["sectionScheme"] as? String, name)
                expectedSelection = try XCTUnwrap(testCase["selected"] as? String, name)
            }

            var expectedIDs: [String] = []
            for scheme in schemes {
                if !scheme.isListed {
                    continue
                }
                if let taken = placeTaken, let takenBy = placeTakenBy, scheme.id == taken {
                    expectedIDs.append(takenBy)
                } else {
                    expectedIDs.append(scheme.id)
                }
            }

            let shown: [ColourScheme] = ColourSchemeCatalog.schemesToList(
                forSectionSchemeID: storedID,
                in: schemes
            )
            var shownIDs: [String] = []
            var shownNames: [String] = []
            for scheme in shown {
                shownIDs.append(scheme.id)
                shownNames.append(scheme.name)
            }
            XCTAssertEqual(shownIDs, expectedIDs, name)
            XCTAssertEqual(Set(shownNames).count, shownNames.count, "\(name): a name is shown twice")

            // The picker's selection is the stored id itself: a listed id
            // or the twin is in the list, so it is shown chosen; an empty or
            // unknown id is left as it is, and nothing is written.
            if placeTakenBy != nil || expectedIDs.contains(expectedSelection) {
                XCTAssertTrue(shownIDs.contains(expectedSelection), "\(name): the section's own scheme is not in the list")
            }
        }
    }

    func testANewCourseIsNeverOfferedTheOldID() throws {
        let schemes: [ColourScheme] = ColourSchemeCatalog.schemes
        let twin: ColourScheme = try XCTUnwrap(unlistedTwin(of: groveID, in: schemes))
        let storedIDs: [String] = ["", "quartz-standard", groveID]
        for storedID in storedIDs {
            let shown: [ColourScheme] = ColourSchemeCatalog.schemesToList(forSectionSchemeID: storedID, in: schemes)
            for scheme in shown {
                XCTAssertNotEqual(scheme.id, twin.id, "offered the old id to a section on \"\(storedID)\"")
            }
        }
    }

    // MARK: - Functions

    private func unlistedTwin(of listedID: String, in schemes: [ColourScheme]) -> ColourScheme? {
        for scheme in schemes {
            if !scheme.isListed && scheme.sameAs == listedID {
                return scheme
            }
        }
        return nil
    }
}
