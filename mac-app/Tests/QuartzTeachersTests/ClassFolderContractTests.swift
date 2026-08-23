import XCTest
@testable import QuartzTeachers

/// The class-folder rule, run against the SHARED contract.
///
/// The cases are deserialised from `contracts/class-planning.json` →
/// `classFolder`, never retyped — the same data `scripts/test_class_folder.py`
/// and the Windows suite run against their own implementations. That is the
/// whole point: this rule used to exist four times and disagree, and the
/// build's disagreement silently changed the Curriculum Coverage map from
/// "pages the course teaches" to "every published page".
@MainActor
final class ClassFolderContractTests: XCTestCase {

    // MARK: - Stored properties

    private var contract: [String: Any] = [:]

    // MARK: - Functions

    override func setUpWithError() throws {
        // Located the way ClassPlanningContractTests locates the same file:
        // up from #filePath to the repository root.
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/class-planning.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        contract = try XCTUnwrap(all["classFolder"] as? [String: Any],
                                 "contracts/class-planning.json has no classFolder section")
    }

    func testNamingCasesFromTheContract() throws {
        let naming: [String: Any] = try XCTUnwrap(contract["naming"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(naming["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5, "the contract lost naming cases")
        for testCase in cases {
            let name: String = (testCase["name"] as? String) ?? "unnamed"
            let folders: [String] = (testCase["perSectionFolders"] as? [String]) ?? []
            let expected: String = try XCTUnwrap(testCase["expect"] as? String)
            XCTAssertEqual(
                ClassFolder.name(inPerSectionFolders: folders), expected,
                "\(name): \((testCase["why"] as? String) ?? "")"
            )
        }
    }

    func testIsClassPageCasesFromTheContract() throws {
        let rule: [String: Any] = try XCTUnwrap(contract["isClassPage"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 9, "the contract lost isClassPage cases")
        for testCase in cases {
            let name: String = (testCase["name"] as? String) ?? "unnamed"
            let path: String = try XCTUnwrap(testCase["path"] as? String)
            let folder: String = try XCTUnwrap(testCase["classFolder"] as? String)
            let expected: Bool = try XCTUnwrap(testCase["expect"] as? Bool)
            XCTAssertEqual(
                ClassFolder.isClassPage(relativePath: path, classFolder: folder), expected,
                "\(name): \((testCase["why"] as? String) ?? "")"
            )
        }
    }

    /// The two bugs the rule was written to close, asserted directly as well as
    /// through the case list — so deleting a contract case cannot quietly
    /// delete the protection with it.
    func testAShippedPageNamedForAClassIsNotALesson() {
        let pages: [String] = [
            "Setup/How This Class Works.md",
            "Setup/Our Classroom Norms.md",
            "Curriculum/B3. Connections Beyond the Classroom.md",
        ]
        for page in pages {
            XCTAssertFalse(
                ClassFolder.isClassPage(relativePath: page, classFolder: "All Classes"),
                "\(page) is not a lesson — it ships in the example content"
            )
        }
    }

    func testAWindowsPathSeparatorIsUnderstood() {
        XCTAssertTrue(ClassFolder.isClassPage(
            relativePath: "All Classes\\Unit 1, Day 1.md", classFolder: "All Classes"))
    }
}
