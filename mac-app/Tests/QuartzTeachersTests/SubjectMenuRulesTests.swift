import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` → `subjectMenus` against
/// `SubjectMenuRules.enabledItems` (#457): which File, Course, Section and
/// View items can be used, in every situation the contract names.
@MainActor
final class SubjectMenuRulesTests: XCTestCase {

    // MARK: - Functions

    static func section() throws -> [String: Any] {
        return try SharedRulesContractTests.section("subjectMenus")
    }

    /// The contract's situation, over its defaults.
    static func situation(from values: [String: Any], defaults: [String: Any]) throws -> SubjectMenuRules.Situation {
        var merged: [String: Any] = defaults
        for (key, value) in values {
            XCTAssertNotNil(defaults[key], "subjectMenus names a situation key with no default: \(key)")
            merged[key] = value
        }
        var situation: SubjectMenuRules.Situation = SubjectMenuRules.Situation()
        situation.hasFolder = try XCTUnwrap(merged["hasFolder"] as? Bool)
        situation.folderGettingReady = try XCTUnwrap(merged["folderGettingReady"] as? Bool)
        situation.sheetIsUp = try XCTUnwrap(merged["sheetIsUp"] as? Bool)
        let rowName: String = try XCTUnwrap(merged["row"] as? String)
        situation.row = try XCTUnwrap(SubjectMenuRules.Row(rawValue: rowName), "Unknown row \(rowName)")
        situation.keptForReference = try XCTUnwrap(merged["keptForReference"] as? Bool)
        situation.structuralHold = try XCTUnwrap(merged["structuralHold"] as? Bool)
        situation.busy = try XCTUnwrap(merged["busy"] as? Bool)
        situation.copying = try XCTUnwrap(merged["copying"] as? Bool)
        situation.deploying = try XCTUnwrap(merged["deploying"] as? Bool)
        situation.hasSchedule = try XCTUnwrap(merged["hasSchedule"] as? Bool)
        situation.hasStartOfYearUndo = try XCTUnwrap(merged["hasStartOfYearUndo"] as? Bool)
        situation.hasLinksOffer = try XCTUnwrap(merged["hasLinksOffer"] as? Bool)
        var blocked: Set<SubjectMenuRules.ReviseTarget> = []
        for name in try XCTUnwrap(merged["reviseBlocked"] as? [String]) {
            blocked.insert(try XCTUnwrap(SubjectMenuRules.ReviseTarget(rawValue: name), "Unknown revise target \(name)"))
        }
        situation.reviseBlocked = blocked
        situation.obsidianInstalled = try XCTUnwrap(merged["obsidianInstalled"] as? Bool)
        situation.settingsMaySave = try XCTUnwrap(merged["settingsMaySave"] as? Bool)
        situation.settingsMayRevert = try XCTUnwrap(merged["settingsMayRevert"] as? Bool)
        situation.previewButtonEnabled = try XCTUnwrap(merged["previewButtonEnabled"] as? Bool)
        situation.deployButtonEnabled = try XCTUnwrap(merged["deployButtonEnabled"] as? Bool)
        situation.previewIsShowing = try XCTUnwrap(merged["previewIsShowing"] as? Bool)
        situation.canGoBack = try XCTUnwrap(merged["canGoBack"] as? Bool)
        situation.canGoForward = try XCTUnwrap(merged["canGoForward"] as? Bool)
        return situation
    }

    // MARK: - Tests

    func testEveryCaseEnablesWhatTheContractSays() throws {
        let section: [String: Any] = try SubjectMenuRulesTests.section()
        let defaults: [String: Any] = try XCTUnwrap(section["situationDefaults"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 17)
        for testCase in cases {
            let why: String = try XCTUnwrap(testCase["why"] as? String)
            let values: [String: Any] = try XCTUnwrap(testCase["situation"] as? [String: Any])
            let situation: SubjectMenuRules.Situation = try SubjectMenuRulesTests.situation(from: values, defaults: defaults)
            var expected: Set<String> = []
            for name in try XCTUnwrap(testCase["enabled"] as? [String]) {
                expected.insert(name)
            }
            var actual: Set<String> = []
            for item in SubjectMenuRules.enabledItems(situation) {
                actual.insert(item.rawValue)
            }
            XCTAssertEqual(actual.subtracting(expected).sorted(), [], "enabled but the contract says greyed — \(why)")
            XCTAssertEqual(expected.subtracting(actual).sorted(), [], "greyed but the contract says enabled — \(why)")
        }
    }

    /// The contract's item list and the app's are the same list, so a new
    /// item cannot be added to one side alone.
    func testTheContractNamesEveryItemAndNoOthers() throws {
        let section: [String: Any] = try SubjectMenuRulesTests.section()
        var contractItems: [String] = []
        for name in try XCTUnwrap(section["items"] as? [String]) {
            contractItems.append(name)
        }
        var appItems: [String] = []
        for item in SubjectMenuRules.Item.allCases {
            appItems.append(item.rawValue)
        }
        XCTAssertEqual(contractItems, appItems)

        let keys: [String: Any] = try XCTUnwrap(section["situationKeys"] as? [String: Any])
        let defaults: [String: Any] = try XCTUnwrap(section["situationDefaults"] as? [String: Any])
        XCTAssertEqual(Set(keys.keys), Set(defaults.keys), "every situation key is explained, and has a default")
    }

    /// A sheet greys everything, whatever else is true — the guard behind
    /// "a key equivalent cannot act behind a sheet".
    func testASheetGreysEveryItemInEverySituation() {
        for row in SubjectMenuRules.Row.allCases {
            var situation: SubjectMenuRules.Situation = SubjectMenuRules.Situation()
            situation.hasFolder = true
            situation.row = row
            situation.obsidianInstalled = true
            situation.previewButtonEnabled = true
            situation.deployButtonEnabled = true
            situation.previewIsShowing = true
            situation.settingsMaySave = true
            situation.settingsMayRevert = true
            situation.sheetIsUp = true
            XCTAssertEqual(SubjectMenuRules.enabledItems(situation), [], "row \(row.rawValue)")
        }
    }

    /// The shared key equivalent (⇧⌘O on Open in Obsidian in both menus) is
    /// never live in both at once — the plan review's finding 3, as a rule.
    func testTheTwoOpenInObsidianItemsAreNeverBothEnabled() {
        for row in SubjectMenuRules.Row.allCases {
            for kept in [false, true] {
                var situation: SubjectMenuRules.Situation = SubjectMenuRules.Situation()
                situation.hasFolder = true
                situation.row = row
                situation.keptForReference = kept
                situation.obsidianInstalled = true
                let enabled: Set<SubjectMenuRules.Item> = SubjectMenuRules.enabledItems(situation)
                XCTAssertFalse(
                    enabled.contains(.courseOpenInObsidian) && enabled.contains(.sectionOpenInObsidian),
                    "row \(row.rawValue)"
                )
                XCTAssertFalse(
                    enabled.contains(.courseShowInFinder) && enabled.contains(.sectionShowInFinder),
                    "row \(row.rawValue)"
                )
            }
        }
    }
}
