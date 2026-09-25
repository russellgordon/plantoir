import XCTest
@testable import QuartzTeachers

final class FinderPathBarTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testAncestorPathsWalkFromRootToFolder() {
        let url: URL = URL(fileURLWithPath: "/Users/jordanteacher/Desktop/Class Websites")
        let paths: [String] = FinderPathBarView.ancestorPaths(for: url)
        XCTAssertEqual(paths, [
            "/",
            "/Users",
            "/Users/jordanteacher",
            "/Users/jordanteacher/Desktop",
            "/Users/jordanteacher/Desktop/Class Websites",
        ])
    }

    @MainActor
    func testRootDisplayNameIsTheVolumeName() {
        // Finder's path bar starts at the volume ("Macintosh HD"), which
        // is how FileManager names "/".
        let rootName: String = FileManager.default.displayName(atPath: "/")
        XCTAssertFalse(rootName.isEmpty)
        XCTAssertNotEqual(rootName, "/")
    }
}
