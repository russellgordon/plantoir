import XCTest
@testable import QuartzTeachers

/// Unit planning (#707), the mac's share of it: reading each unit's
/// `plan.json` (`shared-rules.json` → `unitPlanning`), and the sentence the
/// two Revise doors end their greeting with (`app-rules.json` →
/// `outsideAgents.greetingUnitPlans`). Every case is read from the contract;
/// nothing here retypes a sentence.
@MainActor
final class UnitPlansTests: XCTestCase {

    // MARK: - Stored properties

    private var folder: URL!

    // MARK: - Functions

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-unit-plans-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func unitPlanning() throws -> [String: Any] {
        return try SharedRulesContractTests.section("unitPlanning")
    }

    private func greetingRules() throws -> [String: Any] {
        let url: URL = UnitPlansTests.repositoryRoot().appendingPathComponent("contracts/app-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["outsideAgents"] as? [String: Any])
    }

    /// Writes one unit folder under `course`'s planning folder, with
    /// `plan.json` holding exactly `file`, or no plan.json when it is nil.
    private func writeUnit(folderName: String, file: String?, course: URL) throws {
        let unitFolder: URL = course.appendingPathComponent(UnitPlans.folderPath, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: unitFolder, withIntermediateDirectories: true)
        if let file {
            try file.write(to: unitFolder.appendingPathComponent(UnitPlans.planFileName), atomically: true, encoding: .utf8)
        }
    }

    // MARK: - The plan file

    func testTheFolderAndTheRulesAreTheContracts() throws {
        let rules: [String: Any] = try unitPlanning()
        XCTAssertEqual(rules["folder"] as? String, "courses/<CODE>/" + UnitPlans.folderPath)
        let planFile: [String: Any] = try XCTUnwrap(rules["planFile"] as? [String: Any])
        XCTAssertEqual(planFile["name"] as? String, UnitPlans.planFileName)
        let slugRules: [String: Any] = try XCTUnwrap(rules["slugRules"] as? [String: Any])
        XCTAssertEqual(slugRules["pattern"] as? String, UnitPlans.slugPattern)
        XCTAssertEqual(rules["neverSlugs"] as? [String], UnitPlans.neverSlugs)
    }

    /// 707 plan review L3: a folder of an archive-excluded name anywhere under
    /// the planning folder is dropped from every backup, so the contract's
    /// list must BE the archiver's, and the never-slugs its names without a
    /// dot plus the stylesheets' own folder.
    func testTheNeverFolderNamesAreTheArchiveExclusions() throws {
        let rules: [String: Any] = try unitPlanning()
        let neverFolderNames: [String] = try XCTUnwrap(rules["neverFolderNames"] as? [String])
        XCTAssertEqual(neverFolderNames, CourseArchiver.excludedFromArchives)
        var expectedSlugs: [String] = ["assets"]
        for name in CourseArchiver.excludedFromArchives where !name.hasPrefix(".") {
            expectedSlugs.append(name)
        }
        XCTAssertEqual(Set(UnitPlans.neverSlugs), Set(expectedSlugs))
        XCTAssertEqual(UnitPlans.neverSlugs.count, expectedSlugs.count)
    }

    func testEveryPlanFileCaseHoldsAsTheContractSays() throws {
        let block: [String: Any] = try XCTUnwrap(try unitPlanning()["planFileCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)
        for (index, testCase) in cases.enumerated() {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let folderName: String = try XCTUnwrap(testCase["folder"] as? String)
            let expect: String = try XCTUnwrap(testCase["expect"] as? String)
            let course: URL = folder.appendingPathComponent("case-\(index)", isDirectory: true)
            try writeUnit(folderName: folderName, file: testCase["file"] as? String, course: course)

            let reading: UnitPlans.Reading = UnitPlans.read(courseDirectory: course)
            switch expect {
            case "read":
                XCTAssertEqual(reading.unreadable, 0, name)
                XCTAssertEqual(reading.plans.count, 1, name)
                let plan: UnitPlans.Plan = try XCTUnwrap(reading.plans.first, name)
                XCTAssertEqual(plan.slug, folderName, name)
                XCTAssertEqual(UnitPlans.nameInTheGreeting(plan), testCase["named"] as? String, name)
                XCTAssertEqual(plan.firstClass?.text, testCase["firstClass"] as? String, name)
            case "unreadable":
                XCTAssertEqual(reading.plans, [], name)
                XCTAssertEqual(reading.unreadable, 1, name)
            case "ignored":
                XCTAssertEqual(reading.plans, [], name)
                XCTAssertEqual(reading.unreadable, 0, name)
            default:
                XCTFail("\(name): the contract expects \"\(expect)\", which this test does not know")
            }
        }
    }

    func testACourseWithNoPlanningFolderHasNoPlansAndNothingUnreadable() {
        XCTAssertEqual(UnitPlans.read(courseDirectory: folder), UnitPlans.Reading(plans: [], unreadable: 0))
        let missing: URL = folder.appendingPathComponent("no-such-course", isDirectory: true)
        XCTAssertEqual(UnitPlans.read(courseDirectory: missing), UnitPlans.Reading(plans: [], unreadable: 0))
    }

    func testACourseKeptForReferenceIsToldNothing() throws {
        try writeUnit(folderName: "unit-3", file: "{\"unit\": \"Unit 3\"}", course: folder)
        XCTAssertNil(UnitPlans.toMention(courseDirectory: folder, isKeptForReference: true))
        XCTAssertEqual(UnitPlans.toMention(courseDirectory: folder, isKeptForReference: false)?.plans.count, 1)
    }

    // MARK: - The greeting

    func testTheSentencesAndBoundsAreTheContracts() throws {
        let words: [String: Any] = try XCTUnwrap(try greetingRules()["greetingUnitPlans"] as? [String: Any])
        XCTAssertEqual(words["none"] as? String, UnitPlans.noneSentence)
        XCTAssertEqual(words["one"] as? String, UnitPlans.oneSentence)
        XCTAssertEqual(words["some"] as? String, UnitPlans.someSentence)
        XCTAssertEqual(words["more"] as? String, UnitPlans.moreClause)
        XCTAssertEqual(words["unitNameMaxCharacters"] as? Int, UnitPlans.unitNameMaxCharacters)
        XCTAssertEqual(words["mostUnitsNamed"] as? Int, UnitPlans.mostUnitsNamed)
        let trail: [String: Any] = try XCTUnwrap(words["trail"] as? [String: Any])
        XCTAssertEqual(trail["separator"] as? String, UnitPlans.trailSeparator)
        XCTAssertEqual(trail["none"] as? String, UnitPlans.trailNone)
        XCTAssertEqual(trail["one"] as? String, UnitPlans.trailOne)
        XCTAssertEqual(trail["several"] as? String, UnitPlans.trailSeveral)
        XCTAssertEqual(trail["unreadable"] as? String, UnitPlans.trailUnreadable)
    }

    /// The Revise door's greeting for a course with no plan is the plain
    /// greeting with the contract's `none` sentence LAST, after one space:
    /// the opening instructions keep their order, and the golden that pins
    /// them (`ClaudeCodeLauncherTests.testTheGreetingIsExactlyThis`) is the
    /// part before it.
    func testTheSentenceComesLastAfterTheReferenceCourses() throws {
        let words: [String: Any] = try XCTUnwrap(try greetingRules()["greetingUnitPlans"] as? [String: Any])
        let none: String = try XCTUnwrap(words["none"] as? String)
        let plain: String = ClaudeCodeLauncher.greeting(courseCode: "ICS3U", courseName: "Grade 11 Computer Science")
        XCTAssertEqual(
            ClaudeCodeLauncher.greeting(courseCode: "ICS3U", courseName: "Grade 11 Computer Science", unitPlans: []),
            plain + " " + none
        )
        let withReference: String = ClaudeCodeLauncher.greeting(
            courseCode: "ICS3U", courseName: "Grade 11 Computer Science",
            referenceCourses: ["ICS3U-2025 (2025–26)"], unitPlans: []
        )
        let plainWithReference: String = ClaudeCodeLauncher.greeting(
            courseCode: "ICS3U", courseName: "Grade 11 Computer Science",
            referenceCourses: ["ICS3U-2025 (2025–26)"]
        )
        XCTAssertEqual(withReference, plainWithReference + " " + none)
    }

    /// Every `greetingUnitPlansCases` case, through BOTH doors'
    /// `prepareSession`: the sentence the written script carries, and the
    /// clause the trail line gains.
    func testTheUnitPlanSentenceFollowsTheContract() throws {
        let block: [String: Any] = try XCTUnwrap(try greetingRules()["greetingUnitPlansCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 16)

        let previousStore: ProblemReportStore = ActivityTrail.store
        defer {
            ActivityTrail.store = previousStore
        }

        for (index, testCase) in cases.enumerated() {
            // A store of its own per case, so one case's line can never
            // stand in for another's (707a review L3).
            let scratchTrail: URL = folder.appendingPathComponent("trail-\(index)", isDirectory: true)
            ActivityTrail.store = ProblemReportStore(folderURL: scratchTrail)
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let courseCode: String = try XCTUnwrap(testCase["course"] as? String)
            let isKeptForReference: Bool = try XCTUnwrap(testCase["referenceCourse"] as? Bool)
            let hasPlanningFolder: Bool = try XCTUnwrap(testCase["planningFolder"] as? Bool)
            let plans: [[String: Any]] = try XCTUnwrap(testCase["plans"] as? [[String: Any]])
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            let expectedTrail: String = try XCTUnwrap(expect["trail"] as? String)
            let expectedSentence: String? = expect["sentence"] as? String
            let today: CalendarDay = try XCTUnwrap(CalendarDay(text: try XCTUnwrap(testCase["today"] as? String)), name)

            let course: URL = folder.appendingPathComponent("course-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
            if hasPlanningFolder {
                try FileManager.default.createDirectory(
                    at: course.appendingPathComponent(UnitPlans.folderPath, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            for plan in plans {
                try writeUnit(
                    folderName: try XCTUnwrap(plan["folder"] as? String),
                    file: plan["file"] as? String, course: course
                )
            }

            let reading: UnitPlans.Reading? = UnitPlans.toMention(
                courseDirectory: course, isKeptForReference: isKeptForReference, today: today
            )
            let plain: String = ClaudeCodeLauncher.greeting(courseCode: courseCode, courseName: "")
            let greeting: String = ClaudeCodeLauncher.greeting(
                courseCode: courseCode, courseName: "", unitPlans: reading?.plans
            )
            if let expectedSentence {
                XCTAssertEqual(greeting, plain + " " + expectedSentence, name)
            } else {
                XCTAssertEqual(greeting, plain, name)
            }

            let claudeScript: String = try ClaudeCodeLauncher.prepareSession(
                workspacePath: folder.path, courseCode: courseCode, courseName: "",
                claudePath: "/usr/local/bin/claude", serverPath: "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
                unitPlans: reading
            )
            let codexScript: String = try CodexLauncher.prepareSession(
                workspacePath: folder.path, courseCode: courseCode, courseName: "",
                codexPath: "/opt/homebrew/bin/codex", serverPath: "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
                unitPlans: reading
            )
            defer {
                try? FileManager.default.removeItem(atPath: claudeScript)
                try? FileManager.default.removeItem(atPath: codexScript)
            }
            for script in [claudeScript, codexScript] {
                let written: String = try String(contentsOfFile: script, encoding: .utf8)
                XCTAssertTrue(written.contains(ClaudeCodeLauncher.escapeForShell(greeting)), "\(name): \(script)")
            }

            let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
            let claudeLine: String = ClaudeCodeLauncher.trailSentence(courseCode: courseCode) + expectedTrail
            let codexLine: String = CodexLauncher.trailSentence(courseCode: courseCode) + expectedTrail
            XCTAssertEqual(ClaudeCodeLauncher.trailSentence(courseCode: courseCode, unitPlans: reading), claudeLine, name)
            XCTAssertEqual(CodexLauncher.trailSentence(courseCode: courseCode, unitPlans: reading), codexLine, name)
            XCTAssertTrue(trail.contains(claudeLine), "\(name): \(claudeLine)\n\(trail)")
            XCTAssertTrue(trail.contains(codexLine), "\(name): \(codexLine)\n\(trail)")
            XCTAssertFalse(trail.contains(claudeLine + UnitPlans.trailSeparator), "\(name): a clause too many\n\(trail)")
            XCTAssertFalse(trail.contains(codexLine + UnitPlans.trailSeparator), "\(name): a clause too many\n\(trail)")
        }
    }

    /// Fix with Claude… / Fix with Codex… hand over their own message, which
    /// replaces the greeting: nothing about unit planning, on the script or
    /// the trail, even if a caller passed the plans (Russell's ruling 4).
    func testAFixWithMessageSaysNothingAboutUnitPlanning() throws {
        let scratchTrail: URL = folder.appendingPathComponent("trail-fix", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchTrail)
        defer {
            ActivityTrail.store = previousStore
        }
        let reading: UnitPlans.Reading = UnitPlans.Reading(plans: [], unreadable: 0)
        let script: String = try ClaudeCodeLauncher.prepareSession(
            workspacePath: folder.path, courseCode: "FIX_UNIT_PLANS_TEST", courseName: "",
            claudePath: "/usr/local/bin/claude", serverPath: "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
            unitPlans: reading, greeting: "Please fix one problem."
        )
        defer {
            try? FileManager.default.removeItem(atPath: script)
        }
        let written: String = try String(contentsOfFile: script, encoding: .utf8)
        XCTAssertFalse(written.contains(UnitPlans.noneSentence))
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(ClaudeCodeLauncher.trailSentence(courseCode: "FIX_UNIT_PLANS_TEST")))
        XCTAssertFalse(trail.contains(UnitPlans.trailNone))
    }
}
