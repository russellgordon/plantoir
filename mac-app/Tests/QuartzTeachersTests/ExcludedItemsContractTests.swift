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

    /// `excludedItems.recordedOnSave`, played through `ExclusionTrail.changes`
    /// — the comparison `CourseConfiguration.write(to:)` makes of the file
    /// before a write with what it wrote. No case has anything on disk, so
    /// no course folder is given.
    func testWhatAWriteRecordsMatchesTheContract() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try ExcludedItemsContractTests.rule("recordedOnSave")["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8, "the contract lost recorded-on-save cases")
        for testCase in cases {
            let caseName: String = testCase["name"] as? String ?? "unnamed"
            let before: [String: Any] = try XCTUnwrap(testCase["before"] as? [String: Any], caseName)
            let written: [String: Any] = try XCTUnwrap(testCase["written"] as? [String: Any], caseName)
            let expected: [[String: String]] = try XCTUnwrap(testCase["expect"] as? [[String: String]], caseName)

            var described: [[String: String]] = []
            for change in ExclusionTrail.changes(before: before, written: written) {
                var scope: String = "shared"
                if change.scope == FolderScope.perSection {
                    scope = "per_section"
                }
                described.append([
                    "event": change.event.rawValue, "scope": scope,
                    "kind": change.kind.rawValue, "name": change.name,
                ])
            }
            XCTAssertEqual(described, expected, caseName)
        }
    }

    /// The kind of a name in neither list comes from the disk: a folder added
    /// and then removed before saving was made by Course Settings
    /// (`createFoldersOnDisk`), so the line still says "folder" (the plan
    /// review's finding 10).
    func testANameInNeitherListTakesItsKindFromTheDisk() throws {
        let courseURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("exclusion-kind-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: courseURL) }
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("Field Trips"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1/Labs"), withIntermediateDirectories: true
        )
        try Data("# notes".utf8).write(to: courseURL.appendingPathComponent("section1/Notes.md"))

        let written: [String: Any] = [
            "excluded_items": ["shared": ["Field Trips", "Drafts"], "per_section": ["Labs", "Notes.md"]],
        ]
        let changes: [ExclusionTrail.Change] = ExclusionTrail.changes(
            before: [:], written: written, courseDirectory: courseURL
        )
        var kinds: [String] = []
        for change in changes {
            kinds.append(change.name + "=" + change.kind.rawValue)
        }
        XCTAssertEqual(kinds, ["Field Trips=folder", "Drafts=item", "Labs=folder", "Notes.md=file"])
        XCTAssertEqual(
            ExclusionTrail.line(for: changes[3], courseCode: "ICS3U"),
            "excluded per-section file Notes.md in ICS3U"
        )
    }
}
