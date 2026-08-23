import XCTest
@testable import QuartzTeachers

/// The province-tagged catalog the New Course wizard's code picker
/// searches and browses.
final class CourseCatalogTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testBothProvinceCatalogsLoadFromBundle() {
        XCTAssertGreaterThan(CourseCatalog.ontarioEntries.count, 1000, "The Ontario catalog should be bundled and loaded")
        XCTAssertGreaterThan(CourseCatalog.britishColumbiaEntries.count, 50, "The British Columbia catalog should be bundled and loaded")
    }

    @MainActor
    func testEntriesForProvinceReturnsTheRightList() {
        XCTAssertEqual(CourseCatalog.entries(forProvince: "ON").count, CourseCatalog.ontarioEntries.count)
        XCTAssertEqual(CourseCatalog.entries(forProvince: "BC").count, CourseCatalog.britishColumbiaEntries.count)
        // Anything else defaults to Ontario, same as the rest of the app.
        XCTAssertEqual(CourseCatalog.entries(forProvince: "").count, CourseCatalog.ontarioEntries.count)
    }

    @MainActor
    func testProvinceNameMatchesTheCode() {
        XCTAssertEqual(CourseCatalog.provinceName(forCode: "ON"), "Ontario")
        XCTAssertEqual(CourseCatalog.provinceName(forCode: "BC"), "British Columbia")
    }

    @MainActor
    func testEmptyQueryBrowsesAlphabeticallyByCode() {
        let results: [CourseCatalogEntry] = CourseCatalog.matching("", inProvince: "ON", limit: 10)
        XCTAssertEqual(results.count, 10)
        for index in 1..<results.count {
            XCTAssertLessThan(results[index - 1].code, results[index].code)
        }
    }

    @MainActor
    func testCodePrefixMatchesLeadResults() {
        // "SCH" is a code prefix for SCH3U/SCH4U, so both should appear
        // ahead of any course whose NAME merely mentions chemistry.
        let results: [CourseCatalogEntry] = CourseCatalog.matching("SCH", inProvince: "ON", limit: 40)
        XCTAssertFalse(results.isEmpty)
        for entry in results.prefix(while: { $0.code.hasPrefix("SCH") }) {
            XCTAssertTrue(entry.code.hasPrefix("SCH"))
        }
        XCTAssertTrue(results.contains { $0.code == "SCH3U" })
    }

    @MainActor
    func testSearchingByNameFindsTheCourse() {
        // Typing what the course is called, not its code, is the whole
        // point of the picker.
        let results: [CourseCatalogEntry] = CourseCatalog.matching("chem", inProvince: "ON", limit: 40)
        XCTAssertTrue(results.contains { $0.code == "SCH3U" })
    }

    @MainActor
    func testSearchIsCaseInsensitive() {
        let lower: [CourseCatalogEntry] = CourseCatalog.matching("chem", inProvince: "ON", limit: 40)
        let upper: [CourseCatalogEntry] = CourseCatalog.matching("CHEM", inProvince: "ON", limit: 40)
        XCTAssertEqual(lower.map { $0.code }, upper.map { $0.code })
    }

    @MainActor
    func testUnmatchedQueryReturnsNoResults() {
        let results: [CourseCatalogEntry] = CourseCatalog.matching("ZZZNOTACOURSE", inProvince: "ON", limit: 40)
        XCTAssertTrue(results.isEmpty)
    }

    @MainActor
    func testResultsAreCappedAtTheLimit() {
        // An empty query against Ontario's ~1,900 codes would otherwise
        // return them all.
        let results: [CourseCatalogEntry] = CourseCatalog.matching("", inProvince: "ON", limit: 5)
        XCTAssertEqual(results.count, 5)
    }

    @MainActor
    func testHasExampleContentReflectsTheBundledPayload() {
        let entries: [CourseCatalogEntry] = CourseCatalog.entries(forProvince: "ON")
        guard let ics3u = entries.first(where: { $0.code == "ICS3U" }) else {
            XCTFail("ICS3U should be in the Ontario catalog")
            return
        }
        XCTAssertTrue(ics3u.hasExampleContent)

        guard let noExample = entries.first(where: { !ExampleContentCatalog.hasContent(forCode: $0.code) }) else {
            XCTFail("Expected at least one Ontario code without example content")
            return
        }
        XCTAssertFalse(noExample.hasExampleContent)
    }

    @MainActor
    func testBritishColumbiaExampleContentMarker() {
        let entries: [CourseCatalogEntry] = CourseCatalog.entries(forProvince: "BC")
        guard let mcmpr11 = entries.first(where: { $0.code == "MCMPR11" }) else {
            XCTFail("MCMPR11 should be in the British Columbia catalog")
            return
        }
        XCTAssertTrue(mcmpr11.hasExampleContent)
    }
}
