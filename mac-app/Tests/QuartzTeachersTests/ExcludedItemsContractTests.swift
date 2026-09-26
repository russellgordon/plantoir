import XCTest
@testable import QuartzTeachers

/// `contracts/shared-rules.json` → `excludedItems` (#152): how a name in
/// `excluded_items` is matched, and when a removal or an add-back is written
/// on the breadcrumb trail.
@MainActor
final class ExcludedItemsContractTests: XCTestCase {

    // MARK: - Functions

    private static func rule(_ name: String) throws -> [String: Any] {
        return try WorkLeaseLivenessTests.sharedRules(["excludedItems", name])
    }

    /// `excludedItems.matching`, played through `CourseConfiguration.isExcluded`:
    /// every name in a case's lists is excluded in its scope exactly when the
    /// case's `expectLists` leaves it out. The build runs the same cases
    /// through preflight and its give-up path
    /// (`scripts/test_preflight_exclusions.py`); this pins that the app keeps
    /// asking EXACTLY, case included, which is what the build does.
    func testAnExcludedNameIsMatchedAsTheContractSays() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try ExcludedItemsContractTests.rule("matching")["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5, "the contract lost excluded-item matching cases")

        let listsByScope: [(key: String, scope: String)] = [
            ("shared_folders", "shared"), ("shared_files", "shared"),
            ("per_section_folders", "per_section"), ("per_section_files", "per_section"),
        ]
        var casesAsked: Int = 0
        for testCase in cases {
            let caseName: String = testCase["name"] as? String ?? "unnamed"
            // Discovery from disk is the build's question; the app's is
            // whether a LISTED name is excluded.
            if testCase["onDisk"] != nil {
                continue
            }
            let lists: [String: [String]] = try XCTUnwrap(testCase["lists"] as? [String: [String]], caseName)
            let expectLists: [String: [String]] = try XCTUnwrap(testCase["expectLists"] as? [String: [String]], caseName)
            let excluded: [String: [String]] = try XCTUnwrap(testCase["excludedItems"] as? [String: [String]], caseName)
            let configuration: CourseConfiguration = CourseConfiguration(
                values: ["excluded_items": excluded], lastSavedData: Data()
            )
            for entry in listsByScope {
                let listed: [String] = lists[entry.key] ?? []
                let kept: [String] = expectLists[entry.key] ?? []
                for name in listed {
                    let expectedExcluded: Bool = !kept.contains(name)
                    XCTAssertEqual(
                        configuration.isExcluded(name, inScope: entry.scope), expectedExcluded,
                        caseName + ": " + entry.key + " → " + name
                    )
                }
            }
            casesAsked += 1
        }
        XCTAssertGreaterThanOrEqual(casesAsked, 4)
    }
}
