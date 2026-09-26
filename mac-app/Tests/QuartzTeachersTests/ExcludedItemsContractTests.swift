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

    /// `excludedItems.recordedOnClick`, every case played through Course
    /// Settings itself: each list's own editor (`CourseSettingsGestureScript`),
    /// the Revert button's `revertToFile()`, `save()`, and `SectionAdder` for
    /// a section added from the sidebar. The trail is read back and every
    /// exclusion line turned into the contract's event, scope, kind, name or
    /// count — the words are this app's own (Russell's decision of 2026-09-06,
    /// overnight/issues/09-item-excluded-trail-on-click.md; #152).
    func testWhenAnExclusionIsWrittenOnTheTrailMatchesTheContract() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try ExcludedItemsContractTests.rule("recordedOnClick")["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 9, "the contract lost recorded-on-click cases")

        var index: Int = 0
        for testCase in cases {
            let caseName: String = testCase["name"] as? String ?? "unnamed"
            let root: URL = FileManager.default.temporaryDirectory
                .appendingPathComponent("recorded-on-click-\(index)-\(UUID().uuidString)")
            index += 1
            let previousStore: ProblemReportStore = ActivityTrail.store
            ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent(".trail"))
            defer {
                ActivityTrail.store = previousStore
                try? FileManager.default.removeItem(at: root)
            }

            let course: Course = try ExcludedItemsContractTests.makeCourse(in: root, from: testCase)
            let view: CourseSettingsView = CourseSettingsView(course: course)
            let steps: [[String: Any]] = try XCTUnwrap(testCase["steps"] as? [[String: Any]], caseName)
            for step in steps {
                if let removal = step["remove"] as? [String: String] {
                    let editor: StringListEditorView = CourseSettingsGestureScript.editor(
                        for: try ExcludedItemsContractTests.gestureList(removal["list"]), of: view
                    )
                    editor.removeItem(named: try XCTUnwrap(removal["name"], caseName))
                } else if let addition = step["add"] as? [String: String] {
                    let editor: StringListEditorView = CourseSettingsGestureScript.editor(
                        for: try ExcludedItemsContractTests.gestureList(addition["list"]), of: view
                    )
                    editor.add(typedName: try XCTUnwrap(addition["name"], caseName))
                } else if step["revert"] != nil {
                    view.revertToFile()
                } else if step["save"] != nil {
                    view.save()
                } else if let section = step["addSection"] as? Int {
                    try SectionAdder.addSection(section, to: course)
                } else {
                    XCTFail(caseName + ": an unknown step " + String(describing: step))
                }
            }

            let expected: [[String: AnyHashable]] = try XCTUnwrap(testCase["expect"] as? [[String: AnyHashable]], caseName)
            XCTAssertEqual(ExcludedItemsContractTests.exclusionEventsOnTheTrail(), expected, caseName)
        }
    }

    // MARK: - Helpers

    private static func gestureList(_ key: String?) throws -> GestureList {
        switch key {
        case "shared_folders":
            return .sharedFolders
        case "per_section_folders":
            return .perSectionFolders
        case "shared_files":
            return .sharedFiles
        case "per_section_files":
            return .perSectionFiles
        default:
            throw NSError(domain: "ExcludedItemsContractTests", code: 1)
        }
    }

    /// A one-section course with a real course_config.json, its folder
    /// lists' folders on disk and its file lists' pages there too.
    private static func makeCourse(in root: URL, from testCase: [String: Any]) throws -> Course {
        let courseURL: URL = root.appendingPathComponent("ICS3U")
        let sharedFolders: [String] = testCase["sharedFolders"] as? [String] ?? []
        let perSectionFolders: [String] = testCase["perSectionFolders"] as? [String] ?? []
        let sharedFiles: [String] = testCase["sharedFiles"] as? [String] ?? []
        let perSectionFiles: [String] = testCase["perSectionFiles"] as? [String] ?? []
        for folder in sharedFolders {
            try FileManager.default.createDirectory(at: courseURL.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for folder in perSectionFolders {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent("section1").appendingPathComponent(folder), withIntermediateDirectories: true
            )
        }
        for file in sharedFiles {
            try Data("# page".utf8).write(to: courseURL.appendingPathComponent(file))
        }
        for file in perSectionFiles {
            try Data("---\ntitle: page\n---\n".utf8).write(to: courseURL.appendingPathComponent("section1").appendingPathComponent(file))
        }
        let values: [String: Any] = [
            "course_code": "ICS3U", "course_name": "Recorded on click", "section_numbers": [1], "num_sections": 1,
            "shared_folders": sharedFolders, "per_section_folders": perSectionFolders,
            "shared_files": sharedFiles, "per_section_files": perSectionFiles,
        ]
        let fileURL: URL = courseURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]).write(to: fileURL)
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: try CourseConfiguration(contentsOf: fileURL))
    }

    /// The trail's exclusion lines as the contract describes them.
    private static func exclusionEventsOnTheTrail() -> [[String: AnyHashable]] {
        var events: [[String: AnyHashable]] = []
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        for line in trail.components(separatedBy: "\n") {
            guard let separator = line.range(of: " · ") else {
                continue
            }
            let text: String = String(line[separator.upperBound...])
            let words: [String] = text.components(separatedBy: " ")
            if text.hasPrefix("reverted ") && text.contains("unsaved exclusion change") && words.count > 1 {
                events.append(["event": "exclusions reverted", "count": Int(words[1]) ?? -1])
                continue
            }
            var event: String = ""
            if text.hasPrefix("excluded ") {
                event = "item excluded"
            } else if text.hasPrefix("re-included ") {
                event = "item re-included"
            } else {
                continue
            }
            // "<verb> <scope> <kind> <name…> in <code>"
            guard words.count >= 6, let inIndex = words.lastIndex(of: "in") else {
                continue
            }
            var scope: String = "shared"
            if words[1] == "per-section" {
                scope = "per_section"
            }
            let name: String = words[3..<inIndex].joined(separator: " ")
            events.append(["event": event, "scope": scope, "kind": words[2], "name": name])
        }
        return events
    }
}
