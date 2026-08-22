import XCTest
@testable import QuartzTeachers

/// The bundled Ontario course lookup must behave like the wizard's:
/// same file, same names, case-insensitive on the code.
final class CourseNameCatalogTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testCatalogLoadsFromBundle() {
        XCTAssertGreaterThan(CourseNameCatalog.entries.count, 1000, "The Ontario course lookup should be bundled and loaded")
    }

    @MainActor
    func testKnownCodeReturnsBothNames() {
        let names: CourseNames? = CourseNameCatalog.names(forCode: "ICS3U")
        XCTAssertEqual(names?.formal, "Introduction to Computer Science, Grade 11, U")
        XCTAssertEqual(names?.short, "Intro to Comp Sci")
    }

    @MainActor
    func testLookupIsCaseInsensitiveAndTrimsWhitespace() {
        let names: CourseNames? = CourseNameCatalog.names(forCode: "  ics3u ")
        XCTAssertEqual(names?.short, "Intro to Comp Sci")
    }

    @MainActor
    func testBritishColumbiaCodeReturnsBothNames() {
        let names: CourseNames? = CourseNameCatalog.names(forCode: "MCMPR11")
        XCTAssertEqual(names?.formal, "Computer Programming 11")
        XCTAssertEqual(names?.short, "Computer Programming")
    }

    @MainActor
    func testUnknownAndClubCodesReturnNil() {
        XCTAssertNil(CourseNameCatalog.names(forCode: "CODING"))
        XCTAssertNil(CourseNameCatalog.names(forCode: ""))
    }
}
