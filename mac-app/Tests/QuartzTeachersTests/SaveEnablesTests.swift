import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// What enables Course Settings' Save and Revert (#364, #373), run from
/// `contracts/shared-rules.json` → `savingSettings.whatEnablesSave`.
///
/// #364 and #373 were filed as one comparison wrong in both directions, and
/// measured right in both: a fresh course reads clean, and every per-section
/// change enables Save. These tests pin both directions so the comparison
/// cannot regress, the destination rule that was the likeliest real #373, and
/// the accent Save wears only when it can be pressed.
///
/// Every real-window test has a MODEL half that never skips and an
/// accessibility half that skips when the window cannot be read (a locked
/// screen, another Space, another account). The skip is thrown at the END, so
/// the model half has always run by then; read the skip count.
@MainActor
final class SaveEnablesTests: XCTestCase {

    // MARK: - Stored properties

    var scratchURL: URL!

    // MARK: - Set up

    override func setUp() async throws {
        scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveEnables-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: scratchURL.appendingPathComponent("existing folder"), withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratchURL)
    }

    // MARK: - The rule, as pure functions

    func testTheTruthTable() {
        let problem: SaveEnablement.DestinationProblem = SaveEnablement.DestinationProblem(
            sentence: "That folder doesn’t exist.", check: .deployFolder
        )
        // Nothing unsaved: neither button, and no accent.
        XCTAssertFalse(SaveEnablement.saveIsEnabled(hasUnsavedChanges: false, holdingProblem: nil))
        XCTAssertFalse(SaveEnablement.revertIsEnabled(hasUnsavedChanges: false))
        XCTAssertFalse(SaveEnablement.saveWearsTheAccent(hasUnsavedChanges: false, holdingProblem: nil))
        XCTAssertFalse(SaveEnablement.saveIsHeldBack(hasUnsavedChanges: false, holdingProblem: problem))
        // Unsaved, nothing holding it back: Save, Revert and the accent.
        XCTAssertTrue(SaveEnablement.saveIsEnabled(hasUnsavedChanges: true, holdingProblem: nil))
        XCTAssertTrue(SaveEnablement.revertIsEnabled(hasUnsavedChanges: true))
        XCTAssertTrue(SaveEnablement.saveWearsTheAccent(hasUnsavedChanges: true, holdingProblem: nil))
        // Unsaved and held back: Revert only, no accent, and the reason said.
        XCTAssertFalse(SaveEnablement.saveIsEnabled(hasUnsavedChanges: true, holdingProblem: problem))
        XCTAssertFalse(SaveEnablement.saveWearsTheAccent(hasUnsavedChanges: true, holdingProblem: problem))
        XCTAssertTrue(SaveEnablement.saveIsHeldBack(hasUnsavedChanges: true, holdingProblem: problem))
        // A destination problem holds Save back only when the destination moved.
        XCTAssertNil(SaveEnablement.holdingProblem(destinationProblem: problem, destinationsChanged: false))
        XCTAssertEqual(SaveEnablement.holdingProblem(destinationProblem: problem, destinationsChanged: true), problem)
        // The trail: once, on the change into the state.
        XCTAssertTrue(SaveEnablement.shouldNoteHeldBack(wasHeldBack: false, isHeldBack: true, alreadyNoted: false))
        XCTAssertFalse(SaveEnablement.shouldNoteHeldBack(wasHeldBack: false, isHeldBack: true, alreadyNoted: true))
        XCTAssertFalse(SaveEnablement.shouldNoteHeldBack(wasHeldBack: true, isHeldBack: true, alreadyNoted: false))
        XCTAssertFalse(SaveEnablement.shouldNoteHeldBack(wasHeldBack: true, isHeldBack: false, alreadyNoted: false))
    }

    /// Save's accent is drawn in ONE place, inside the branch that only an
    /// enabled Save takes (#364). A second `.borderedProminent` anywhere in
    /// the form is how a disabled Save comes to look pressable again.
    func testSaveWearsTheAccentOnlyWhenItCanBePressed() throws {
        let source: String = try String(
            contentsOf: UserFacingLabelWordsTests.macAppRoot()
                .appendingPathComponent("QuartzTeachers/Views/CourseSettings/CourseSettingsView.swift"),
            encoding: .utf8
        )
        let start: Range<String.Index> = try XCTUnwrap(source.range(of: "var saveButton: some View {"))
        let rest: Substring = source[start.upperBound...]
        let branchStart: Range<Substring.Index> = try XCTUnwrap(rest.range(of: "if SaveEnablement.saveWearsTheAccent("))
        let elseStart: Range<Substring.Index> = try XCTUnwrap(rest.range(of: "} else {"))
        let accentBranch: Substring = rest[branchStart.lowerBound..<elseStart.lowerBound]
        XCTAssertEqual(SaveEnablesTests.occurrences(of: ".borderedProminent", in: String(accentBranch)), 1)
        XCTAssertEqual(
            SaveEnablesTests.occurrences(of: ".borderedProminent", in: source), 1,
            "CourseSettingsView.swift draws .borderedProminent outside Save's enabled branch"
        )
    }

    /// Every per-section key the rule lists is one the file format documents.
    func testEveryPerSectionKeyIsInTheFileFormatsContract() throws {
        let block: [String: Any] = try SaveEnablesTests.block()
        let keys: [String] = try XCTUnwrap(block["perSectionKeys"] as? [String])
        XCTAssertEqual(keys.count, 6)
        let formats: [String: Any] = try FileFormatsContractTests.section("courseConfigKeys")
        var documented: Set<String> = []
        for entry in try XCTUnwrap(formats["keys"] as? [[String: Any]]) {
            if let key = entry["key"] as? String {
                documented.insert(key)
            }
        }
        for key in keys {
            let topLevel: String = String(key.split(separator: ".")[0])
            XCTAssertTrue(documented.contains(topLevel), "\(topLevel) is not in file-formats.json → courseConfigKeys")
        }
    }

    // MARK: - Direction 1: a freshly opened course has nothing to save

    /// Model half, no window: each shape reads clean the moment it is loaded.
    func testEveryFreshOpenShapeLoadsClean() throws {
        let block: [String: Any] = try SaveEnablesTests.block()
        let cases: [[String: Any]] = try XCTUnwrap(block["freshOpenCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8, "freshOpenCases has shrunk")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let fileURL: URL = try writeConfiguration(for: testCase, code: "EXC2O", into: scratchURL.appendingPathComponent(UUID().uuidString))
            let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
            XCTAssertFalse(configuration.hasUnsavedChanges, name)
            // Every section's emoji is ONE emoji as read, so the field has
            // nothing to settle and nothing to write (finding 11).
            for section in configuration.sectionNumbers {
                let emoji: String = configuration.emoji(forSection: section)
                XCTAssertEqual(emoji.count, 1, name + ": section \(section)'s emoji reads as \(emoji)")
            }
        }
    }

    /// The real window: each shape is opened, its settings shown and left to
    /// settle, and nothing has been written — the check that catches a child
    /// view writing on draw. Then Save and Revert are read through
    /// accessibility, and so are the Class Pages rows (#376: an ordinary
    /// course shows none of them, a club all three).
    func testEveryFreshOpenShapeHasNothingToSaveInTheRealWindow() async throws {
        let block: [String: Any] = try SaveEnablesTests.block()
        let cases: [[String: Any]] = try XCTUnwrap(block["freshOpenCases"] as? [[String: Any]])
        let workspace: WorkspaceModel = try XCTUnwrap(WorkspaceModel.windowModels.first, "No window model; the interface is not on screen")
        var accessibilityWasRead: Bool = false
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let course: Course = try await openInTheRealWindow(testCase, workspace: workspace)
            XCTAssertFalse(
                course.configuration.hasUnsavedChanges,
                name + ": the form wrote something on open: " + SaveEnablesTests.differingKeys(course.configuration, fileURL: course.configFileURL).joined(separator: ", ")
            )
            if SaveEnablesTests.windowCanBeRead(workspace) {
                accessibilityWasRead = true
                XCTAssertEqual(SaveEnablesTests.enabledState("saveButton"), "disabled", name)
                XCTAssertEqual(SaveEnablesTests.enabledState("revertButton"), "disabled", name)
                let isClub: Bool = (testCase["set"] as? [String: Any])?["class_noun"] != nil
                if isClub {
                    XCTAssertNotNil(AccessibilityInspector.frame(forIdentifier: "pageNamingValue"), name)
                    XCTAssertNotNil(AccessibilityInspector.frame(forIdentifier: "frontPageHeadingValue"), name)
                    XCTAssertNotNil(AccessibilityInspector.frame(forIdentifier: "classNounValue"), name)
                } else {
                    XCTAssertNil(AccessibilityInspector.frame(forIdentifier: "pageNamingValue"), name)
                    XCTAssertFalse(AccessibilityInspector.collectAllLabels().contains("Class Pages"), name)
                }
            }
            workspace.selection = nil
            await settle(seconds: 0.4)
        }
        if !accessibilityWasRead {
            throw XCTSkip("The model half ran; the window could not be read, so Save and Revert were not checked through accessibility.")
        }
    }

    // MARK: - Direction 2: a change made only on a section's page enables Save

    /// Model half: each change is made through the section's own binding,
    /// Save is enabled, and Save writes it — and nothing else in that map.
    func testEveryPerSectionEditEnablesSave() throws {
        let block: [String: Any] = try SaveEnablesTests.block()
        let cases: [[String: Any]] = try XCTUnwrap(block["perSectionEditCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7, "perSectionEditCases has shrunk")
        var keysCovered: Set<String> = []
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let fileURL: URL = try writeConfiguration(for: testCase, code: "EXC2O", into: scratchURL.appendingPathComponent(UUID().uuidString))
            let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
            XCTAssertFalse(configuration.hasUnsavedChanges, name + " (before)")

            let change: [String: Any] = try XCTUnwrap(testCase["change"] as? [String: Any])
            keysCovered.insert(try XCTUnwrap(change["key"] as? String))
            try SaveEnablesTests.apply(change, to: configuration, placeholders: placeholders())

            let holding: SaveEnablement.DestinationProblem? = SaveEnablement.holdingProblem(
                destinationProblem: SaveEnablement.destinationProblem(for: configuration, cloudflareAccountID: ""),
                destinationsChanged: configuration.deployDestinationsDifferFromSaved
            )
            XCTAssertTrue(configuration.hasUnsavedChanges, name)
            XCTAssertTrue(SaveEnablement.saveIsEnabled(hasUnsavedChanges: configuration.hasUnsavedChanges, holdingProblem: holding), name)
            XCTAssertTrue(SaveEnablement.revertIsEnabled(hasUnsavedChanges: configuration.hasUnsavedChanges), name)

            try configuration.write(to: fileURL)
            let written: [String: Any] = try SaveEnablesTests.readJSON(fileURL)
            for expectation in try XCTUnwrap(testCase["written"] as? [[String: Any]]) {
                let path: [String] = try XCTUnwrap(expectation["path"] as? [String])
                XCTAssertTrue(SaveEnablesTests.sameJSON(SaveEnablesTests.value(at: path, in: written), expectation["value"]), name + ": " + path.joined(separator: "."))
            }
            for expectation in try XCTUnwrap(testCase["unchanged"] as? [[String: Any]]) {
                let path: [String] = try XCTUnwrap(expectation["path"] as? [String])
                XCTAssertTrue(SaveEnablesTests.sameJSON(SaveEnablesTests.value(at: path, in: written), expectation["value"]), name + ": " + path.joined(separator: ".") + " changed")
            }
            XCTAssertFalse(configuration.hasUnsavedChanges, name + " (after Save)")
        }
        let listed: [String] = try XCTUnwrap(block["perSectionKeys"] as? [String])
        XCTAssertEqual(keysCovered, Set(listed), "every per-section key has a case")
    }

    /// The real window: the section's own toggle, pressed through
    /// accessibility, enables Save and Revert (#373's report, done the way a
    /// teacher does it).
    func testASectionTogglePressedInTheRealWindowEnablesSave() async throws {
        let workspace: WorkspaceModel = try XCTUnwrap(WorkspaceModel.windowModels.first, "No window model; the interface is not on screen")
        let course: Course = try await openInTheRealWindow(["name": "base", "set": [String: Any](), "remove": [String]()], workspace: workspace)
        XCTAssertFalse(course.configuration.hasUnsavedChanges)
        guard SaveEnablesTests.windowCanBeRead(workspace) else {
            // The model half of this direction is testEveryPerSectionEditEnablesSave.
            course.configuration.setShowsGradeInTitle(false, forSection: 2)
            XCTAssertTrue(course.configuration.hasUnsavedChanges)
            try course.configuration.revertToFile(at: course.configFileURL)
            workspace.selection = nil
            throw XCTSkip("The window could not be read, so the toggle was not pressed through accessibility.")
        }
        XCTAssertTrue(AccessibilityInspector.press(identifier: "gradeInTitleToggle-section2"), "the section's toggle could not be pressed")
        await settle(seconds: 0.8)
        XCTAssertTrue(course.configuration.hasUnsavedChanges)
        XCTAssertFalse(course.configuration.showsGradeInTitle(forSection: 2))
        XCTAssertEqual(SaveEnablesTests.enabledState("saveButton"), "enabled")
        XCTAssertEqual(SaveEnablesTests.enabledState("revertButton"), "enabled")
        try course.configuration.revertToFile(at: course.configFileURL)
        workspace.selection = nil
        await settle(seconds: 0.4)
    }

    // MARK: - The destination rule, and saying why

    func testTheHeldBackCases() throws {
        let block: [String: Any] = try SaveEnablesTests.block()
        let wording: [String: Any] = try SharedRulesContractTests.section("courseSettingsWording")
        let template: String = try XCTUnwrap(wording["saveHeldBack"] as? String)
        let cases: [[String: Any]] = try XCTUnwrap(block["heldBackCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7, "heldBackCases has shrunk")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let fileURL: URL = try writeConfiguration(for: testCase, code: "EXC2O", into: scratchURL.appendingPathComponent(UUID().uuidString))
            let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
            for change in try XCTUnwrap(testCase["changes"] as? [[String: Any]]) {
                try SaveEnablesTests.apply(change, to: configuration, placeholders: placeholders())
            }
            let accountID: String = try XCTUnwrap(testCase["cloudflareAccountIDOnThisMac"] as? String)
            let holding: SaveEnablement.DestinationProblem? = SaveEnablement.holdingProblem(
                destinationProblem: SaveEnablement.destinationProblem(for: configuration, cloudflareAccountID: accountID),
                destinationsChanged: configuration.deployDestinationsDifferFromSaved
            )
            let dirty: Bool = configuration.hasUnsavedChanges
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            XCTAssertEqual(SaveEnablement.saveIsEnabled(hasUnsavedChanges: dirty, holdingProblem: holding), expect["saveEnabled"] as? Bool, name)
            XCTAssertEqual(SaveEnablement.revertIsEnabled(hasUnsavedChanges: dirty), expect["revertEnabled"] as? Bool, name)
            XCTAssertEqual(SaveEnablement.saveIsHeldBack(hasUnsavedChanges: dirty, holdingProblem: holding), expect["heldBack"] as? Bool, name)
            if let check = expect["check"] as? String {
                XCTAssertEqual(holding?.check.rawValue, check, name)
                let reason: String = try XCTUnwrap(expect["reason"] as? String)
                XCTAssertEqual(holding?.sentence, reason, name)
                XCTAssertEqual(
                    CourseSettingsWording.saveHeldBack(reason: reason),
                    template.replacingOccurrences(of: "{reason}", with: reason), name
                )
            }
        }
    }

    /// The real window: an edit that moves the course to a folder that does
    /// not exist holds Save back, the reason is said beside Save, and the
    /// trail says so ONCE however many further edits follow.
    func testAHeldBackEditSaysWhyBesideSaveAndOnTheTrailOnce() async throws {
        let trailFolder: URL = scratchURL.appendingPathComponent("trail")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
        defer {
            ActivityTrail.store = previousStore
        }
        let workspace: WorkspaceModel = try XCTUnwrap(WorkspaceModel.windowModels.first, "No window model; the interface is not on screen")
        let course: Course = try await openInTheRealWindow(["name": "base", "set": [String: Any](), "remove": [String]()], workspace: workspace)

        course.configuration.deployTarget = "local_folder"
        course.configuration.deployFolderPath = scratchURL.appendingPathComponent("no such folder").path
        await settle(seconds: 0.8)
        course.configuration.setColourSchemeID("coastal-breeze", forSection: 2)
        await settle(seconds: 0.5)
        course.configuration.setEmoji("🔬", forSection: 1)
        await settle(seconds: 0.5)

        let trail: String = ActivityTrail.store.activityText(includingPrompts: false)
        XCTAssertEqual(
            SaveEnablesTests.occurrences(of: "could not save the settings for EXC2O yet (deploy folder)", in: trail), 1,
            "the held-back line should be on the trail exactly once: \(trail)"
        )
        XCTAssertFalse(trail.contains("no such folder"), "the trail must never carry the path")

        var accessibilityWasRead: Bool = false
        if SaveEnablesTests.windowCanBeRead(workspace) {
            accessibilityWasRead = true
            XCTAssertEqual(SaveEnablesTests.enabledState("saveButton"), "disabled")
            XCTAssertEqual(SaveEnablesTests.enabledState("revertButton"), "enabled")
            XCTAssertNotNil(AccessibilityInspector.frame(forIdentifier: "saveHeldBackReason"), "the reason is not beside Save")
            let expected: String = CourseSettingsWording.saveHeldBack(
                reason: "That folder doesn’t exist — use Choose… to pick or create one."
            )
            XCTAssertTrue(AccessibilityInspector.collectAllLabels().contains(expected), "the sentence beside Save is not the contract's")
        }
        try course.configuration.revertToFile(at: course.configFileURL)
        workspace.selection = nil
        await settle(seconds: 0.4)
        if !accessibilityWasRead {
            throw XCTSkip("The model and trail halves ran; the window could not be read, so the sentence beside Save was not checked.")
        }
    }

    // MARK: - Helpers

    func settle(seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    func placeholders() -> [String: String] {
        return [
            "{missingFolder}": scratchURL.appendingPathComponent("missing folder").path,
            "{anotherMissingFolder}": scratchURL.appendingPathComponent("another missing folder").path,
            "{existingFolder}": scratchURL.appendingPathComponent("existing folder").path,
        ]
    }

    /// Writes the case's configuration — baseShape with `set` and `remove`
    /// applied, placeholders filled, the code replaced — and returns its URL.
    func writeConfiguration(for testCase: [String: Any], code: String, into folder: URL) throws -> URL {
        let block: [String: Any] = try SaveEnablesTests.block()
        var values: [String: Any] = try XCTUnwrap(block["baseShape"] as? [String: Any])
        if let set = testCase["set"] as? [String: Any] {
            for (key, value) in set {
                values[key] = value
            }
        }
        if let remove = testCase["remove"] as? [String] {
            for key in remove {
                values.removeValue(forKey: key)
            }
        }
        values["course_code"] = code
        for (key, value) in values {
            if let text = value as? String {
                values[key] = SaveEnablesTests.filled(text, placeholders())
            }
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL: URL = folder.appendingPathComponent("course_config.json")
        let data: Data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL)
        return fileURL
    }

    /// Opens a fresh fixture working folder in the real window with this
    /// case's configuration, shows the course's settings and lets them settle.
    func openInTheRealWindow(_ testCase: [String: Any], workspace: WorkspaceModel) async throws -> Course {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        let courseFolder: URL = fixtureURL.appendingPathComponent("courses/EXC2O")
        _ = try writeConfiguration(for: testCase, code: "EXC2O", into: courseFolder)
        workspace.chooseWorkspace(at: fixtureURL)
        await settle(seconds: 1.0)
        let course: Course = try XCTUnwrap(workspace.courses.first)
        workspace.selection = SidebarSelection.course(course.code)
        await settle(seconds: 1.5)
        return course
    }

    static func block() throws -> [String: Any] {
        let saving: [String: Any] = try SharedRulesContractTests.section("savingSettings")
        return try XCTUnwrap(saving["whatEnablesSave"] as? [String: Any])
    }

    /// Makes one change the way the form makes it.
    static func apply(_ change: [String: Any], to configuration: CourseConfiguration, placeholders: [String: String]) throws {
        if let setting = change["setting"] as? String {
            switch setting {
            case "deployTarget":
                configuration.deployTarget = try XCTUnwrap(change["value"] as? String)
            case "deployFolderPath":
                configuration.deployFolderPath = filled(try XCTUnwrap(change["value"] as? String), placeholders)
            case "addAdditionalDestination":
                let type: String = try XCTUnwrap(change["type"] as? String)
                configuration.setAdditionalDeployTarget(true, ofType: type)
                configuration.setAdditionalDeployTargetPath(filled(try XCTUnwrap(change["path"] as? String), placeholders), ofType: type)
            default:
                XCTFail("unknown setting \(setting)")
            }
            return
        }
        let section: Int = try XCTUnwrap(change["section"] as? Int)
        let key: String = try XCTUnwrap(change["key"] as? String)
        let view: SectionSettingsView = SectionSettingsView(configuration: configuration, sectionNumber: section)
        switch key {
        case "emojis.sections.section<N>":
            view.emojiBinding.wrappedValue = try XCTUnwrap(change["value"] as? String)
        case "color_schemes.section<N>":
            view.schemeBinding.wrappedValue = try XCTUnwrap(change["value"] as? String)
        case "fonts.sections.section<N>":
            view.fontBinding.wrappedValue = FontChoice(dictionary: try XCTUnwrap(change["value"] as? [String: Any]))
        case "show_section_marker.sections.section<N>":
            view.markerBinding.wrappedValue = try XCTUnwrap(change["value"] as? Bool)
        case "show_grade_in_title.sections.section<N>":
            view.gradeInTitleBinding.wrappedValue = try XCTUnwrap(change["value"] as? Bool)
        case "custom_domains.sections.section<N>":
            let destination: String = try XCTUnwrap(change["destinationType"] as? String)
            view.customDomainBinding(forDestinationType: destination).wrappedValue = try XCTUnwrap(change["value"] as? String)
        default:
            XCTFail("unknown per-section key \(key)")
        }
    }

    static func filled(_ text: String, _ placeholders: [String: String]) -> String {
        var result: String = text
        for (placeholder, value) in placeholders {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result
    }

    static func readJSON(_ url: URL) throws -> [String: Any] {
        let data: Data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func value(at path: [String], in dictionary: [String: Any]) -> Any? {
        var current: Any? = dictionary
        for step in path {
            guard let map = current as? [String: Any] else {
                return nil
            }
            current = map[step]
        }
        return current
    }

    static func sameJSON(_ first: Any?, _ second: Any?) -> Bool {
        guard let first, let second else {
            return first == nil && second == nil
        }
        let wrapped: NSArray = [first]
        return wrapped.isEqual(to: [second])
    }

    static func occurrences(of needle: String, in text: String) -> Int {
        return text.components(separatedBy: needle).count - 1
    }

    /// The keys where this copy and the file disagree, for a failure message.
    static func differingKeys(_ configuration: CourseConfiguration, fileURL: URL) -> [String] {
        let onDisk: [String: Any] = (try? readJSON(fileURL)) ?? [:]
        var keys: Set<String> = []
        for key in configuration.values.keys {
            keys.insert(key)
        }
        for key in onDisk.keys {
            keys.insert(key)
        }
        var result: [String] = []
        for key in keys.sorted() {
            if !sameJSON(configuration.values[key], onDisk[key]) {
                result.append(key)
            }
        }
        return result
    }

    static func windowCanBeRead(_ workspace: WorkspaceModel) -> Bool {
        do {
            try AccessibilityInspector.skipUnlessTheWindowCanBeRead(workspace.window)
            return true
        } catch {
            return false
        }
    }

    /// "enabled", "disabled" or "not found", read through accessibility.
    static func enabledState(_ identifier: String) -> String {
        let application: AXUIElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        guard let element = findElement(application, identifier, 0) else {
            return "not found"
        }
        var enabled: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
        if let isEnabled = enabled as? Bool, isEnabled {
            return "enabled"
        }
        return "disabled"
    }

    static func findElement(_ element: AXUIElement, _ identifier: String, _ depth: Int) -> AXUIElement? {
        if depth > 70 {
            return nil
        }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &value) == .success,
           let found = value as? String, found == identifier {
            return element
        }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let list = children as? [AXUIElement] {
            for child in list {
                if let hit = findElement(child, identifier, depth + 1) {
                    return hit
                }
            }
        }
        return nil
    }
}
