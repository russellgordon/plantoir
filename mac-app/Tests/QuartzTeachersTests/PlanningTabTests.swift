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
        XCTAssertGreaterThanOrEqual(tabCases.count, 8)
        var sawCopilotAlone: Bool = false
        for testCase in tabCases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let claude: Bool = try XCTUnwrap(testCase["claude"] as? Bool)
            let codex: Bool = try XCTUnwrap(testCase["codex"] as? Bool)
            let copilot: Bool = try XCTUnwrap(testCase["copilot"] as? Bool, "\(name): copilot (#783)")
            let reference: Bool = try XCTUnwrap(testCase["referenceCourse"] as? Bool)
            let shown: Bool = PlanningTab.isShown(
                claudeIsInstalled: claude,
                codexIsInstalled: codex,
                copilotIsInstalled: copilot,
                courseIsKeptForReference: reference
            )
            XCTAssertEqual(shown ? "shown" : "absent", testCase["expect"] as? String, name)
            if copilot && !claude && !codex && !reference {
                sawCopilotAlone = true
            }
        }
        // #783: GitHub Copilot alone is enough for the tabs. MUST FAIL if
        // `isShown` ignores `copilotIsInstalled`.
        XCTAssertTrue(sawCopilotAlone, "a case with GitHub Copilot the only assistant installed")
    }

    // MARK: - The unit popup

    func testThePopupOffersAndStartsAsTheContractSays() throws {
        let choiceCases: [[String: Any]] = try cases("choiceCases")
        XCTAssertGreaterThanOrEqual(choiceCases.count, 21)
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
            "cannotShowTitle": PlanningWording.cannotShowTitle,
            "cannotShowDescription": PlanningWording.cannotShowDescription,
            "revertOnPlanning": PlanningWording.revertOnPlanning,
            "openInBrowser": PlanInTheBrowser.buttonTitle,
            "openInBrowserHelp": PlanInTheBrowser.help,
            "openInBrowserNothingToOpen": PlanInTheBrowser.nothingToOpen,
            "openInBrowserOutsideThePlan": PlanInTheBrowser.outsideThePlan,
            "openInBrowserPageIsGone": PlanInTheBrowser.pageIsGone,
            "openInBrowserCouldNotOpenTitle": PlanInTheBrowser.couldNotOpenTitle,
            "openInBrowserCouldNotOpen": PlanInTheBrowser.couldNotOpen,
            "openInBrowserNotAPage": PlanInTheBrowser.notAPage,
            "openInBrowserNoBrowser": PlanInTheBrowser.noBrowser,
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
        let copilotScript: String = try CopilotLauncher.prepareSession(
            workspacePath: folder.path, courseCode: courseCode, courseName: "Grade 10 Science",
            copilotPath: "/opt/homebrew/bin/copilot", serverPath: "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
            greeting: message
        )
        defer {
            try? FileManager.default.removeItem(atPath: claudeScript)
            try? FileManager.default.removeItem(atPath: codexScript)
            try? FileManager.default.removeItem(atPath: copilotScript)
            if let support = try? ClaudeCodeLauncher.supportDirectory() {
                try? FileManager.default.removeItem(at: support.appendingPathComponent("mcp-\(courseCode).json"))
                try? FileManager.default.removeItem(at: support.appendingPathComponent("mcp-\(courseCode)-copilot.json"))
            }
        }
        for script in [claudeScript, codexScript, copilotScript] {
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

    /// The window's course branch uses the tabbed page, and the page never
    /// uses a `TabView`. Whether the two tabs are layered is proved by
    /// drawing them (`CourseDetailStructureTests`), not by reading this file.
    func testTheCourseBranchUsesTheTabbedPage() throws {
        let page: String = try PlanningTabTests.readSource("QuartzTeachers/Views/CourseSettings/CourseDetailView.swift")
        // SwiftUI's TabView, never the name inside `PlanningTabView`.
        XCTAssertNil(page.range(of: #"(?<![A-Za-z])TabView\s*[({]"#, options: .regularExpression), "no TabView")
        // The page's own wiring, which no drawn test reaches without a
        // window model (708 fix review 2, L5): the switch goes through the
        // binding that clears Undo, Planning publishes its own Save, and
        // Open in Obsidian is on the page's toolbar.
        XCTAssertTrue(page.contains("selection: tabBinding,"), "the tabs switch through tabBinding")
        XCTAssertFalse(page.contains("selection: $selectedTab"), "never around it")
        XCTAssertTrue(page.contains(".focusedSceneValue(\\.courseSettingsMenu, planningCommands)"), "Planning publishes its Save")
        XCTAssertTrue(page.contains("CourseDetailTabs.planningCommands(course: course, session: settingsSession, showSettings:"))
        XCTAssertTrue(page.contains("accessibilityIdentifier(\"openCourseInObsidianButton\")"), "Open in Obsidian is on the page")
        let main: String = try PlanningTabTests.readSource("QuartzTeachers/Views/MainWindowView.swift")
        XCTAssertTrue(main.contains("CourseDetailView(course: course)"))
        XCTAssertFalse(main.contains("CourseSettingsView(course: course)"), "the course branch uses the tabbed page")
    }

    /// No timed refresh anywhere in the tab's views (CLAUDE.md: a delay
    /// would paper over a race). The web view's guards are proved by
    /// running it, in `PlanWebViewGuardTests`, not by reading it.
    func testThePlanViewWaitsOnNothing() throws {
        let folderURL: URL = PlanningTabTests.repositoryRoot().appendingPathComponent("mac-app/QuartzTeachers/Views/Planning")
        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
        XCTAssertGreaterThanOrEqual(files.count, 2)
        for file in files {
            let text: String = try String(contentsOf: folderURL.appendingPathComponent(file), encoding: .utf8)
            for forbidden in ["Timer", "asyncAfter", "Task.sleep", "DispatchQueue"] {
                XCTAssertFalse(text.contains(forbidden), "\(file) uses \(forbidden)")
            }
        }
    }

    // MARK: - The popup follows the page

    func testThePopupFollowsThePageAsTheContractSays() throws {
        let block: [String: Any] = try XCTUnwrap(try tab()["followsThePage"] as? [String: Any])
        let followCases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(followCases.count, 7)
        let planning: URL = folder.appendingPathComponent("course/.internal/planning", isDirectory: true)
        for testCase in followCases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var choices: [PlanningTab.Choice] = []
            for written in try XCTUnwrap(testCase["choices"] as? [String]) {
                if written == "allPlans" {
                    choices.append(.allPlans)
                } else {
                    choices.append(.unit(String(written.dropFirst("unit:".count))))
                }
            }
            let page: URL = planning.appendingPathComponent(try XCTUnwrap(testCase["page"] as? String))
            let followed: PlanningTab.Choice? = PlanningTab.choice(forPage: page, planningFolder: planning, choices: choices)
            XCTAssertEqual(PlanningTabTests.written(followed), testCase["expect"] as? String, name)
        }
    }

    // MARK: - The tab's own trail lines

    private func lookedAtEntry() throws -> [String: Any] {
        let activityTrail: [String: Any] = try SharedRulesContractTests.section("activityTrail")
        for entry in try XCTUnwrap(activityTrail["mustRecord"] as? [[String: Any]]) {
            if (entry["event"] as? String) == ActivityTrail.Event.lookedAtUnitPlans.rawValue {
                return entry
            }
        }
        XCTFail("the event is in activityTrail.mustRecord")
        return [:]
    }

    /// "looked at a course's unit plans": the lines are the contract's, and
    /// none carries a plan's title.
    func testTheTabsTrailLinesAreTheContractsAndNameNoPlan() throws {
        let entry: [String: Any] = try lookedAtEntry()
        let what: [String: Any] = try XCTUnwrap(entry["what"] as? [String: Any])
        XCTAssertEqual(entry["line"] as? String, "{course}" + UnitPlans.trailSeparator + PlanningTrail.opened)
        XCTAssertEqual(what["one"] as? String, PlanningTrail.oneUnitPlan)
        XCTAssertEqual(what["several"] as? String, PlanningTrail.unitPlans)
        XCTAssertEqual(what["listOnly"] as? String, PlanningTrail.listOnly)
        XCTAssertEqual(what["none"] as? String, PlanningTrail.nothingToShow)
        XCTAssertEqual(entry["couldNotShowLine"] as? String, "{course}" + UnitPlans.trailSeparator + PlanningTrail.couldNotShow)
        XCTAssertEqual(
            entry["couldNotRefreshTheLookLine"] as? String,
            "{course}" + UnitPlans.trailSeparator + PlanningTrail.couldNotRefreshTheLook
        )

        XCTAssertEqual(
            PlanningTab.openedTrailText(courseCode: "SNC2D", choices: [.allPlans, .unit("unit-1"), .unit("unit-2")]),
            "SNC2D · opened the Planning tab: 2 unit plans to choose from"
        )
        XCTAssertEqual(
            PlanningTab.openedTrailText(courseCode: "SNC2D", choices: [.unit("unit-1")]),
            "SNC2D · opened the Planning tab: 1 unit plan to choose from"
        )
        XCTAssertEqual(
            PlanningTab.openedTrailText(courseCode: "SNC2D", choices: [.allPlans]),
            "SNC2D · opened the Planning tab: only the list of plans"
        )
        XCTAssertEqual(
            PlanningTab.openedTrailText(courseCode: "SNC2D", choices: []),
            "SNC2D · opened the Planning tab: nothing to show yet, offered to plan a unit"
        )
        XCTAssertEqual(
            PlanningTrail.couldNotRefreshTheLookText(courseCode: "SNC2D", failed: 3),
            "SNC2D · the Planning tab could not bring the plan's look up to date: 3 file(s) could not be copied"
        )
    }

    /// The mirror never works through a link: it removes extra files, and
    /// through a linked planning folder it would remove them somewhere that
    /// is not the plan's (review L2).
    func testTheRefreshLeavesALinkedPlanningFolderAlone() throws {
        let elsewhere: URL = folder.appendingPathComponent("elsewhere", isDirectory: true)
        let elsewhereAssets: URL = elsewhere.appendingPathComponent(PlanningAssets.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhereAssets, withIntermediateDirectories: true)
        let photo: URL = elsewhereAssets.appendingPathComponent("photo.jpg")
        try "a picture".write(to: photo, atomically: true, encoding: .utf8)
        let internalFolder: URL = folder.appendingPathComponent("course/.internal", isDirectory: true)
        try FileManager.default.createDirectory(at: internalFolder, withIntermediateDirectories: true)
        let planning: URL = internalFolder.appendingPathComponent("planning", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: planning, withDestinationURL: elsewhere)

        XCTAssertNil(PlanningAssets.refresh(planningFolder: planning, from: templateAssetsInTheRepository()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: photo.path), "a file behind the link was removed")

        let realPlanning: URL = folder.appendingPathComponent("other/.internal/planning", isDirectory: true)
        try FileManager.default.createDirectory(at: realPlanning, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: realPlanning.appendingPathComponent(PlanningAssets.folderName), withDestinationURL: elsewhereAssets
        )
        XCTAssertNil(PlanningAssets.refresh(planningFolder: realPlanning, from: templateAssetsInTheRepository()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: photo.path), "a file behind a linked assets folder was removed")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: elsewhereAssets.appendingPathComponent("plan.css").path),
            "the copy wrote through the link"
        )
    }

    // MARK: - Open in Browser (#803)

    /// Makes one `openInBrowser` case's planning folder, and answers it.
    private func planningFolderFor(openCase testCase: [String: Any], index: Int) throws -> URL {
        let course: URL = folder.appendingPathComponent("open-\(index)", isDirectory: true)
        let planning: URL = course.appendingPathComponent(UnitPlans.folderPath, isDirectory: true)
        try FileManager.default.createDirectory(at: planning, withIntermediateDirectories: true)
        try "{}".write(to: course.appendingPathComponent("course_config.json"), atomically: true, encoding: .utf8)
        for made in try XCTUnwrap(testCase["made"] as? [String]) {
            let file: URL = planning.appendingPathComponent(made).standardizedFileURL
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "made".write(to: file, atomically: true, encoding: .utf8)
        }
        if let links = testCase["links"] as? [String: String] {
            for (at, pointsTo) in links {
                let link: URL = planning.appendingPathComponent(at)
                try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: pointsTo)
            }
        }
        return planning
    }

    /// A case's `onScreen` or `chosen`: a path resolved against the planning
    /// folder as a browser resolves it, or an address with its own scheme,
    /// where `{planning}` stands for the planning folder's absolute path.
    private static func address(_ written: Any?, planningFolder: URL) throws -> URL? {
        guard let written = written as? String else {
            return nil
        }
        let text: String = written.replacingOccurrences(of: "{planning}", with: planningFolder.path)
        let base: URL = URL(fileURLWithPath: planningFolder.path, isDirectory: true)
        return try XCTUnwrap(URL(string: text, relativeTo: base)?.absoluteURL, text)
    }

    func testOpenInBrowserOpensAsTheContractSays() throws {
        let block: [String: Any] = try XCTUnwrap(try tab()["openInBrowser"] as? [String: Any])
        let openCases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(openCases.count, 23)
        for (index, testCase) in openCases.enumerated() {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let planning: URL = try planningFolderFor(openCase: testCase, index: index)
            let onScreen: URL? = try PlanningTabTests.address(testCase["onScreen"], planningFolder: planning)
            let chosen: URL? = try PlanningTabTests.address(testCase["chosen"], planningFolder: planning)
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])

            let answer: PlanInTheBrowser.Answer = PlanInTheBrowser.pageToOpen(
                onScreen: onScreen, chosen: chosen, planningFolder: planning
            )
            if let opens = expect["opens"] as? String {
                let expected: URL? = try PlanningTabTests.address(opens, planningFolder: planning)
                XCTAssertEqual(answer.page?.absoluteString, expected?.absoluteString, name)
                XCTAssertNil(answer.refusal, name)
                if let page = answer.page {
                    XCTAssertEqual(
                        PlanInTheBrowser.kind(of: page, planningFolder: planning).rawValue, expect["kind"] as? String, name
                    )
                }
                XCTAssertEqual(PlanInTheBrowser.helpText(for: answer), PlanInTheBrowser.help, name)
            } else {
                XCTAssertNil(answer.page, name)
                XCTAssertEqual(answer.refusal?.rawValue, expect["refusal"] as? String, name)
                if let refusal = answer.refusal {
                    XCTAssertEqual(PlanInTheBrowser.helpText(for: answer), PlanInTheBrowser.sentence(for: refusal), name)
                }
            }
        }
    }

    /// The action, with a browser that records what it is handed: a page
    /// outside the planning folder never reaches it and writes nothing; a
    /// page inside does, once, and the trail says which kind of page; a Mac
    /// that could not open it says that instead.
    func testOpenInBrowserHandsTheBrowserOnlyAPageOfThePlan() throws {
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folder.appendingPathComponent("trail", isDirectory: true))
        defer {
            ActivityTrail.store = previousStore
        }
        let course: URL = folder.appendingPathComponent("course", isDirectory: true)
        let planning: URL = course.appendingPathComponent(UnitPlans.folderPath, isDirectory: true)
        let unit: URL = planning.appendingPathComponent("unit-1", isDirectory: true)
        try FileManager.default.createDirectory(at: unit, withIntermediateDirectories: true)
        let settings: URL = course.appendingPathComponent("course_config.json")
        try "{}".write(to: settings, atomically: true, encoding: .utf8)
        let correlation: URL = unit.appendingPathComponent(PlanInTheBrowser.correlationPageName)
        try "<html></html>".write(to: correlation, atomically: true, encoding: .utf8)

        var handed: [URL] = []
        var answers: [PlanInTheBrowser.Opening] = []
        var browserSays: PlanInTheBrowser.Opening = .opened
        let opener: @MainActor (URL, @escaping @MainActor (PlanInTheBrowser.Opening) -> Void) -> Void = {
            (page: URL, done: @escaping @MainActor (PlanInTheBrowser.Opening) -> Void) in
            handed.append(page)
            done(browserSays)
        }
        let finished: @MainActor (PlanInTheBrowser.Opening) -> Void = { (opening: PlanInTheBrowser.Opening) in
            answers.append(opening)
        }

        let outside: PlanInTheBrowser.Answer = PlanInTheBrowser.open(
            onScreen: settings, chosen: correlation, planningFolder: planning,
            courseCode: "SNC2D", opener: opener, finished: finished
        )
        XCTAssertEqual(outside.refusal, .outsideThePlan)
        let web: PlanInTheBrowser.Answer = PlanInTheBrowser.open(
            onScreen: URL(string: "https://example.com/"), chosen: nil, planningFolder: planning,
            courseCode: "SNC2D", opener: opener, finished: finished
        )
        XCTAssertEqual(web.refusal, .outsideThePlan)
        let script: URL = unit.appendingPathComponent("run.command")
        try "echo".write(to: script, atomically: true, encoding: .utf8)
        let notAPage: PlanInTheBrowser.Answer = PlanInTheBrowser.open(
            onScreen: script, chosen: correlation, planningFolder: planning,
            courseCode: "SNC2D", opener: opener, finished: finished
        )
        XCTAssertEqual(notAPage.refusal, .notAPage)
        XCTAssertEqual(handed, [], "nothing outside the planning folder, and nothing but a page, reaches the browser")
        XCTAssertFalse(ActivityTrail.store.activityText(includingPrompts: true).contains("in the browser"))

        PlanInTheBrowser.open(
            onScreen: correlation, chosen: nil, planningFolder: planning,
            courseCode: "SNC2D", opener: opener, finished: finished
        )
        XCTAssertEqual(handed, [correlation])
        XCTAssertEqual(answers, [.opened])
        browserSays = .couldNotOpen
        PlanInTheBrowser.open(
            onScreen: correlation, chosen: nil, planningFolder: planning,
            courseCode: "SNC2D", opener: opener, finished: finished
        )
        XCTAssertEqual(answers, [.opened, .couldNotOpen])

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        let opened: String = PlanInTheBrowser.trailText(courseCode: "SNC2D", kind: .correlation)
        let couldNot: String = PlanInTheBrowser.couldNotOpenTrailText(courseCode: "SNC2D", kind: .correlation)
        XCTAssertEqual(trail.components(separatedBy: opened).count - 1, 1, trail)
        XCTAssertEqual(trail.components(separatedBy: couldNot).count - 1, 1, trail)
        XCTAssertFalse(trail.contains("unit-1"), "the trail never names the unit's folder")
    }

    /// "opened a unit plan in the browser": the lines are the contract's.
    func testOpenInBrowsersTrailLinesAreTheContracts() throws {
        let activityTrail: [String: Any] = try SharedRulesContractTests.section("activityTrail")
        var entry: [String: Any] = [:]
        for candidate in try XCTUnwrap(activityTrail["mustRecord"] as? [[String: Any]]) {
            if (candidate["event"] as? String) == ActivityTrail.Event.openedAUnitPlanInTheBrowser.rawValue {
                entry = candidate
            }
        }
        XCTAssertEqual(entry["line"] as? String, "{course}" + UnitPlans.trailSeparator + PlanInTheBrowser.trailLine)
        XCTAssertEqual(
            entry["couldNotOpenLine"] as? String, "{course}" + UnitPlans.trailSeparator + PlanInTheBrowser.couldNotOpenTrailLine
        )
        let what: [String: Any] = try XCTUnwrap(entry["what"] as? [String: Any])
        let kinds: [PlanInTheBrowser.Kind] = [.allPlans, .plan, .correlation, .file]
        XCTAssertEqual(what.count, kinds.count)
        for kind in kinds {
            XCTAssertEqual(what[kind.rawValue] as? String, PlanInTheBrowser.what(kind), kind.rawValue)
        }
        XCTAssertEqual(
            PlanInTheBrowser.trailText(courseCode: "SNC2D", kind: .plan),
            "SNC2D · opened a unit's plan in the browser"
        )
    }

    /// The button is on the plan's bar beside Reload, and the click goes
    /// through `PlanInTheBrowser.open` with the web view's own address.
    func testOpenInBrowserIsBesideReloadAndGoesThroughTheRule() throws {
        let view: String = try PlanningTabTests.readSource("QuartzTeachers/Views/Planning/PlanningTabView.swift")
        let reload: Range<String.Index> = try XCTUnwrap(view.range(of: "accessibilityIdentifier(\"planningReload\")"))
        let button: Range<String.Index> = try XCTUnwrap(view.range(of: "accessibilityIdentifier(\"planningOpenInBrowser\")"))
        XCTAssertLessThan(reload.lowerBound, button.lowerBound)
        XCTAssertTrue(view.contains("PlanInTheBrowser.open("))
        XCTAssertTrue(view.contains("onScreen: model.controller?.webView.url,"))
        XCTAssertFalse(view.contains("NSWorkspace"), "the view opens nothing itself")
    }

    /// With no default browser the opener opens NOTHING (#803 review L3):
    /// the Mac's own app for a file's type would run a script. Read from the
    /// source, because no test can unset the Mac's browser.
    func testWithNoBrowserNothingIsOpened() throws {
        let source: String = try PlanningTabTests.readSource("QuartzTeachers/Views/Planning/PlanWebView.swift")
        let start: Range<String.Index> = try XCTUnwrap(source.range(of: "enum PlanBrowserOpener {"))
        let end: Range<String.Index> = try XCTUnwrap(source.range(of: "struct PlanWebView", range: start.upperBound..<source.endIndex))
        let opener: String = String(source[start.upperBound..<end.lowerBound])
        XCTAssertTrue(opener.contains("done(.noBrowser)"))
        XCTAssertFalse(opener.contains("NSWorkspace.shared.open(page)"), "never the file's own app")
        XCTAssertTrue(opener.contains("withApplicationAt: browser"))
    }
}
