import XCTest
@testable import QuartzTeachers

/// The course page's Planning tab (#708): `shared-rules.json` →
/// `unitPlanning.tab` (`tabCases`, `choiceCases`, `navigationCases`,
/// `words`) and `app-rules.json` → `outsideAgents.planAUnit`, each walked
/// as data through the real functions. Nothing here retypes a sentence.
@MainActor
final class PlanningTabTests: XCTestCase {

    // MARK: - Stored properties

    /// Set up and torn down by XCTest outside the main actor.
    nonisolated(unsafe) private var folder: URL!

    // MARK: - Functions

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-planning-tab-\(UUID().uuidString)", isDirectory: true)
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

    private func tab() throws -> [String: Any] {
        let unitPlanning: [String: Any] = try SharedRulesContractTests.section("unitPlanning")
        return try XCTUnwrap(unitPlanning["tab"] as? [String: Any], "unitPlanning.tab")
    }

    private func planAUnit() throws -> [String: Any] {
        let url: URL = PlanningTabTests.repositoryRoot().appendingPathComponent("contracts/app-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let outsideAgents: [String: Any] = try XCTUnwrap(all["outsideAgents"] as? [String: Any])
        return try XCTUnwrap(outsideAgents["planAUnit"] as? [String: Any], "outsideAgents.planAUnit")
    }

    private func cases(_ key: String) throws -> [[String: Any]] {
        let block: [String: Any] = try XCTUnwrap(try tab()[key] as? [String: Any], key)
        return try XCTUnwrap(block["cases"] as? [[String: Any]], key)
    }

    /// `allPlans` or `unit:<folder>`, as the contract writes a choice.
    private static func written(_ choice: PlanningTab.Choice?) -> String? {
        guard let choice else {
            return nil
        }
        switch choice {
        case .allPlans:
            return "allPlans"
        case .unit(let slug):
            return "unit:" + slug
        }
    }

    // MARK: - When the tabs are there

    func testTheTabsAreThereAsTheContractSays() throws {
        let tabCases: [[String: Any]] = try cases("tabCases")
        XCTAssertGreaterThanOrEqual(tabCases.count, 6)
        for testCase in tabCases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let shown: Bool = PlanningTab.isShown(
                claudeIsInstalled: try XCTUnwrap(testCase["claude"] as? Bool),
                codexIsInstalled: try XCTUnwrap(testCase["codex"] as? Bool),
                courseIsKeptForReference: try XCTUnwrap(testCase["referenceCourse"] as? Bool)
            )
            XCTAssertEqual(shown ? "shown" : "absent", testCase["expect"] as? String, name)
        }
    }

    // MARK: - The unit popup

    func testThePopupOffersAndStartsAsTheContractSays() throws {
        let choiceCases: [[String: Any]] = try cases("choiceCases")
        XCTAssertGreaterThanOrEqual(choiceCases.count, 14)
        for (index, testCase) in choiceCases.enumerated() {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let course: URL = folder.appendingPathComponent("course-\(index)", isDirectory: true)
            let planning: URL = course.appendingPathComponent(UnitPlans.folderPath, isDirectory: true)
            try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
            if try XCTUnwrap(testCase["planningFolder"] as? Bool) {
                try FileManager.default.createDirectory(at: planning, withIntermediateDirectories: true)
            }
            if try XCTUnwrap(testCase["coursePage"] as? Bool) {
                try "<html></html>".write(to: planning.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            }
            for plan in try XCTUnwrap(testCase["plans"] as? [[String: Any]]) {
                let unit: URL = planning.appendingPathComponent(try XCTUnwrap(plan["folder"] as? String), isDirectory: true)
                try FileManager.default.createDirectory(at: unit, withIntermediateDirectories: true)
                let file: String = try XCTUnwrap(plan["file"] as? String)
                try file.write(to: unit.appendingPathComponent(UnitPlans.planFileName), atomically: true, encoding: .utf8)
                if try XCTUnwrap(plan["page"] as? Bool) {
                    try "<html></html>".write(to: unit.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
                }
            }
            let today: CalendarDay = try XCTUnwrap(CalendarDay(text: try XCTUnwrap(testCase["today"] as? String)), name)
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])

            let look: PlanningTab.Look = PlanningTab.look(in: planning, courseDirectory: course)
            var offered: [String] = []
            for choice in look.choices {
                offered.append(PlanningTabTests.written(choice) ?? "")
            }
            XCTAssertEqual(offered, try XCTUnwrap(expect["choices"] as? [String]), name)
            let starting: PlanningTab.Choice? = PlanningTab.startingChoice(
                plans: look.plans, choices: look.choices, today: today
            )
            XCTAssertEqual(PlanningTabTests.written(starting), expect["startsOn"] as? String, name)
        }
    }

    /// Each entry is labelled as the greeting names the plan, and All Plans
    /// by its word.
    func testThePopupLabelsAreTheGreetingsNames() throws {
        let plan: UnitPlans.Plan = UnitPlans.Plan(
            slug: "unit-3", unit: "Unit 3", title: "Chemical Reactions",
            firstClass: nil, lastClass: nil, sections: []
        )
        XCTAssertEqual(PlanningTab.title(for: .unit("unit-3"), plans: [plan]), UnitPlans.nameInTheGreeting(plan))
        XCTAssertEqual(PlanningTab.title(for: .allPlans, plans: [plan]), PlanningWording.allPlans)
    }

    // MARK: - Where a link may go

    func testEveryNavigationIsDecidedAsTheContractSays() throws {
        let navigationCases: [[String: Any]] = try cases("navigationCases")
        XCTAssertGreaterThanOrEqual(navigationCases.count, 23)
        for (index, testCase) in navigationCases.enumerated() {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let course: URL = folder.appendingPathComponent("nav-\(index)", isDirectory: true)
            let planning: URL = course.appendingPathComponent(UnitPlans.folderPath, isDirectory: true)
            for made in ["unit/pdfs", "unit-2", "assets"] {
                try FileManager.default.createDirectory(
                    at: planning.appendingPathComponent(made, isDirectory: true), withIntermediateDirectories: true
                )
            }
            try "{}".write(to: course.appendingPathComponent("course_config.json"), atomically: true, encoding: .utf8)
            if let links = testCase["links"] as? [String: String] {
                for (at, pointsTo) in links {
                    try FileManager.default.createSymbolicLink(
                        atPath: planning.appendingPathComponent(at).path, withDestinationPath: pointsTo
                    )
                }
            }
            let page: URL = planning.appendingPathComponent(try XCTUnwrap(testCase["page"] as? String))
            let href: String = try XCTUnwrap(testCase["href"] as? String)
            let url: URL = try XCTUnwrap(URL(string: href, relativeTo: page)?.absoluteURL, name)
            let decision: PlanNavigation.Decision = PlanNavigation.decide(
                url: url,
                isNewWindow: try XCTUnwrap(testCase["newWindow"] as? Bool),
                byALinkClick: try XCTUnwrap(testCase["click"] as? Bool),
                planningFolder: planning
            )
            XCTAssertEqual(decision.rawValue, testCase["expect"] as? String, "\(name): \(url.absoluteString)")
        }
    }

    // MARK: - The words

    func testTheWordsAreTheContracts() throws {
        let words: [String: Any] = try XCTUnwrap(try tab()["words"] as? [String: Any])
        let mine: [String: String] = [
            "tabSettings": PlanningWording.tabSettings,
            "tabPlanning": PlanningWording.tabPlanning,
            "allPlans": PlanningWording.allPlans,
            "unitPopup": PlanningWording.unitPopup,
            "back": PlanningWording.back,
            "forward": PlanningWording.forward,
            "reload": PlanningWording.reload,
            "emptyTitle": PlanningWording.emptyTitle,
            "emptyDescription": PlanningWording.emptyDescription,
        ]
        XCTAssertEqual(Set(words.keys), Set(mine.keys), "every word in the contract has a constant, and only those")
        for (key, value) in mine {
            XCTAssertEqual(words[key] as? String, value, key)
        }
    }

    // MARK: - Plan a Unit

    func testThePlanAUnitWordsAreTheContracts() throws {
        let block: [String: Any] = try planAUnit()
        XCTAssertEqual(block["message"] as? String, PlanAUnit.message)
        XCTAssertEqual(block["trailLine"] as? String, "{course}" + UnitPlans.trailSeparator + PlanAUnit.trailLine)
        let buttons: [[String: Any]] = try XCTUnwrap(block["buttons"] as? [[String: Any]])
        XCTAssertEqual(buttons.count, FixWithAssistant.Assistant.allCases.count)
        for button in buttons {
            let assistant: FixWithAssistant.Assistant = try XCTUnwrap(
                FixWithAssistant.Assistant(rawValue: try XCTUnwrap(button["assistant"] as? String))
            )
            XCTAssertEqual(button["title"] as? String, PlanAUnit.buttonTitle(for: assistant))
        }
    }

    func testThePlanAUnitMessageIsTheContractsForEveryCase() throws {
        let block: [String: Any] = try planAUnit()
        let messageCases: [[String: Any]] = try XCTUnwrap(block["messageCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(messageCases.count, 6)
        for testCase in messageCases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let text: String = PlanAUnit.openingMessage(
                courseCode: try XCTUnwrap(testCase["course"] as? String),
                courseName: try XCTUnwrap(testCase["courseName"] as? String)
            )
            XCTAssertEqual(text, testCase["text"] as? String, name)
            XCTAssertFalse(text.contains(";"), name)
            XCTAssertFalse(text.contains("\""), name)
            XCTAssertFalse(text.contains("\n"), name)
        }
    }

    /// Both doors' scripts carry the message in place of the greeting, so no
    /// unit-planning reminder rides along; the door's own line is plain; and
    /// the Plan a Unit line, written once, is the contract's.
    func testBothDoorsCarryTheMessageAndTheTrailLineIsWrittenOnce() throws {
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folder.appendingPathComponent("trail", isDirectory: true))
        defer {
            ActivityTrail.store = previousStore
        }
        let courseCode: String = "PLAN_A_UNIT_TEST"
        let message: String = PlanAUnit.openingMessage(courseCode: courseCode, courseName: "Grade 10 Science")
        let claudeScript: String = try ClaudeCodeLauncher.prepareSession(
            workspacePath: folder.path, courseCode: courseCode, courseName: "Grade 10 Science",
            claudePath: "/usr/local/bin/claude", serverPath: "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
            greeting: message
        )
        let codexScript: String = try CodexLauncher.prepareSession(
            workspacePath: folder.path, courseCode: courseCode, courseName: "Grade 10 Science",
            codexPath: "/opt/homebrew/bin/codex", serverPath: "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
            greeting: message
        )
        defer {
            try? FileManager.default.removeItem(atPath: claudeScript)
            try? FileManager.default.removeItem(atPath: codexScript)
        }
        for script in [claudeScript, codexScript] {
            let written: String = try String(contentsOfFile: script, encoding: .utf8)
            XCTAssertTrue(written.contains(ClaudeCodeLauncher.escapeForShell(message)), script)
            XCTAssertFalse(written.contains(UnitPlans.noneSentence), script)
        }

        PlanAUnit.noteOnTheTrail(courseCode: courseCode, assistant: .codex)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        let line: String = PlanAUnit.trailText(courseCode: courseCode, assistant: .codex)
        XCTAssertEqual(trail.components(separatedBy: line).count - 1, 1, trail)
        XCTAssertTrue(trail.contains(ClaudeCodeLauncher.trailSentence(courseCode: courseCode)), trail)
        XCTAssertFalse(trail.contains(UnitPlans.trailNone), trail)

        let activityTrail: [String: Any] = try SharedRulesContractTests.section("activityTrail")
        var template: String = ""
        for entry in try XCTUnwrap(activityTrail["mustRecord"] as? [[String: Any]]) {
            if (entry["event"] as? String) == ActivityTrail.Event.askedAnAssistantToPlanAUnit.rawValue {
                template = try XCTUnwrap(entry["line"] as? String)
            }
        }
        XCTAssertFalse(template.isEmpty, "the event is in activityTrail.mustRecord")
        XCTAssertEqual(
            template.replacingOccurrences(of: "{course}", with: courseCode).replacingOccurrences(of: "{assistant}", with: "Codex"),
            line
        )
    }

    // MARK: - The plan's assets

    private func templateAssetsInTheRepository() -> URL {
        return PlanningTabTests.repositoryRoot()
            .appendingPathComponent("support/agent_guidance")
            .appendingPathComponent(PlanningAssets.templateAssetsPath, isDirectory: true)
    }

    private static func relativeFiles(under root: URL) -> [String: Data] {
        var files: [String: Data] = [:]
        let walker: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        )
        while let file = walker?.nextObject() as? URL {
            let isFile: Bool = (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isFile, let relative = WorkspaceModel.relativePath(of: file, under: root),
               let data = try? Data(contentsOf: file) {
                files[relative] = data
            }
        }
        return files
    }

    /// The app reads the template's `assets/` from its own bundle, the same
    /// place `writeGuidance` copies the skills from, and the bundle's copy
    /// is the repository's byte for byte (a Release bundle without it would
    /// make the refresh a quiet no-op).
    func testTheBundledAssetsAreTheTemplates() throws {
        let bundled: URL = try XCTUnwrap(PlanningAssets.bundledTemplateAssets)
        let fromTheBundle: [String: Data] = PlanningTabTests.relativeFiles(under: bundled)
        let fromTheRepository: [String: Data] = PlanningTabTests.relativeFiles(under: templateAssetsInTheRepository())
        XCTAssertGreaterThanOrEqual(fromTheRepository.count, 22)
        XCTAssertEqual(fromTheBundle, fromTheRepository)
        XCTAssertTrue(bundled.path.hasPrefix(try XCTUnwrap(ToolchainReadiness.bundledGuidanceURL).path))
    }

    func testTheRefreshMirrorsTheTemplateAndRemovesAStrayFile() throws {
        let planning: URL = folder.appendingPathComponent("course/.internal/planning", isDirectory: true)
        let assets: URL = planning.appendingPathComponent(PlanningAssets.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try "an old sheet".write(to: assets.appendingPathComponent("plan.css"), atomically: true, encoding: .utf8)
        try "not the app's".write(to: assets.appendingPathComponent("stray.css"), atomically: true, encoding: .utf8)
        let source: URL = templateAssetsInTheRepository()

        let outcome: WorkspaceModel.MirrorOutcome = try XCTUnwrap(PlanningAssets.refresh(planningFolder: planning, from: source))
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(PlanningTabTests.relativeFiles(under: assets), PlanningTabTests.relativeFiles(under: source))

        let again: WorkspaceModel.MirrorOutcome = try XCTUnwrap(PlanningAssets.refresh(planningFolder: planning, from: source))
        XCTAssertEqual(again.changed, 0, "a second refresh changes nothing")
    }

    func testTheRefreshNeverMakesAPlanningFolder() throws {
        let planning: URL = folder.appendingPathComponent("course/.internal/planning", isDirectory: true)
        XCTAssertNil(PlanningAssets.refresh(planningFolder: planning, from: templateAssetsInTheRepository()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: planning.path))
    }

    // MARK: - The views, by their source

    private static func readSource(_ relativePath: String) throws -> String {
        return try String(
            contentsOf: repositoryRoot().appendingPathComponent("mac-app").appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    /// The course page keeps its settings mounted: Planning is drawn in a
    /// `ZStack` AFTER `CourseSettingsView`, never in a `TabView`, and the
    /// window's course branch uses that page.
    func testThePlanningTabIsDrawnOverTheSettingsNeverInsteadOfThem() throws {
        let page: String = try PlanningTabTests.readSource("QuartzTeachers/Views/CourseSettings/CourseDetailView.swift")
        let stack: Range<String.Index> = try XCTUnwrap(page.range(of: "ZStack {"))
        let settings: Range<String.Index> = try XCTUnwrap(page.range(of: "CourseSettingsView(course: course)"))
        let planning: Range<String.Index> = try XCTUnwrap(page.range(of: "PlanningTabView(course: course"))
        XCTAssertTrue(stack.lowerBound < settings.lowerBound)
        XCTAssertTrue(settings.lowerBound < planning.lowerBound)
        XCTAssertFalse(page.contains("TabView {"))
        XCTAssertFalse(page.contains("TabView("))

        let main: String = try PlanningTabTests.readSource("QuartzTeachers/Views/MainWindowView.swift")
        XCTAssertTrue(main.contains("CourseDetailView(course: course)"))
        XCTAssertFalse(main.contains("CourseSettingsView(course: course)"), "the course branch uses the tabbed page")
    }

    /// No timed refresh anywhere in the tab's views (CLAUDE.md: a delay
    /// would paper over a race), and the web view reads the PLANNING folder
    /// alone, with scripts off and the local-only rule list.
    func testThePlanViewWaitsOnNothingAndReadsOnlyThePlanningFolder() throws {
        let folderURL: URL = PlanningTabTests.repositoryRoot().appendingPathComponent("mac-app/QuartzTeachers/Views/Planning")
        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
        XCTAssertGreaterThanOrEqual(files.count, 2)
        for file in files {
            let text: String = try String(contentsOf: folderURL.appendingPathComponent(file), encoding: .utf8)
            for forbidden in ["Timer", "asyncAfter", "Task.sleep", "DispatchQueue"] {
                XCTAssertFalse(text.contains(forbidden), "\(file) uses \(forbidden)")
            }
        }
        let web: String = try PlanningTabTests.readSource("QuartzTeachers/Views/Planning/PlanWebView.swift")
        XCTAssertTrue(web.contains("allowsContentJavaScript = false"))
        XCTAssertTrue(web.contains("WKWebsiteDataStore.nonPersistent()"))
        XCTAssertTrue(web.contains("userContentController.add(list)"))
        XCTAssertEqual(web.components(separatedBy: "allowingReadAccessTo: planningFolder").count - 1, 2)
        XCTAssertEqual(web.components(separatedBy: "allowingReadAccessTo: folder)").count - 1, 1)
        XCTAssertFalse(web.contains("load(URLRequest"))
    }
}
