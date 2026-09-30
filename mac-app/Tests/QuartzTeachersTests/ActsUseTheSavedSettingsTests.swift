import XCTest
@testable import QuartzTeachers

/// Deploying, and setting a deploy, from a section window use the course's
/// settings as SAVED in its file at that moment — never the window's copy,
/// which may hold Course Settings edits nobody has saved (GitHub #335).
///
/// The Deploy button, the local assistant pressing it, and the schedule sheet
/// all took the destination from the window's in-memory copy, while the
/// launcher's deploy read everything else from the file and, since #322, the
/// approval card named the saved destination. So a teacher could be shown
/// Netlify and get a folder, from a publish half built from each. The
/// contract is `shared-rules.json` → `actsUseTheSavedSettings`.
@MainActor
final class ActsUseTheSavedSettingsTests: XCTestCase {

    // MARK: - Types

    /// A working folder with ICS3U in it, a model of the folder standing in
    /// for a window, and that window's copy of the course.
    struct World {
        let root: URL
        let workspace: WorkspaceModel
        let window: Course
        let folder: URL
    }

    // MARK: - Stored properties

    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var roots: [URL] = []

    /// A moment far enough ahead that the sheet never refuses it as past.
    private let later: Date = Date().addingTimeInterval(60 * 60 * 24 * 30)

    // MARK: - Set up

    override func setUpWithError() throws {
        previousStore = ActivityTrail.store
        let trail: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("saved-settings-trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: trail, withIntermediateDirectories: true)
        roots.append(trail)
        ActivityTrail.store = ProblemReportStore(folderURL: trail)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        ScheduledDeploy.launchAgentsDirectoryOverride = nil
        ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
        roots = []
    }

    // MARK: - The contract

    func testActsUseTheSavedSettingsAsTheContractSays() async throws {
        let section: [String: Any] = try sharedRulesSection("actsUseTheSavedSettings")
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 8)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let act: String = try XCTUnwrap(testCase["act"] as? String)
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            let world: World = try makeWorld(
                saved: try XCTUnwrap(testCase["saved"] as? [String: Any]),
                deployedBefore: testCase["savedDeployedBefore"] as? [String] ?? []
            )
            applyUnsaved(testCase["unsavedInWindow"] as? [String: Any] ?? [:], to: world)
            if testCase["savedFileIsNotJSON"] as? Bool == true {
                try "this is not what a settings file looks like".write(
                    to: world.window.configFileURL, atomically: true, encoding: .utf8
                )
            }
            let anyCopyUnsaved: Bool = world.window.configuration.hasUnsavedChanges
            let expectedNotice: String? = try sentence(named: expect["notice"] as? String)

            if act == "scheduleSheet" {
                let shown: (plan: ScheduledDeployPlan?, unreadable: String?, notice: String?) =
                    ScheduleDeploySheet.whatTheSheetShows(
                        windowCourse: world.window, sectionNumber: 1, when: later, now: Date(),
                        cloudflareAccountID: "", workspaceURL: world.root, anyCopyUnsaved: anyCopyUnsaved
                    )
                let plan: ScheduledDeployPlan = try XCTUnwrap(shown.plan, name)
                XCTAssertEqual(plan.isSchedulable, expect["schedulable"] as? Bool, "\(name): \(plan.description)")
                if expect["refusal"] as? String == "neverDeployed" {
                    let destination: String = try XCTUnwrap(expect["refusalNames"] as? String)
                    XCTAssertEqual(
                        plan.problem,
                        ScheduledDeployWording.neverDeployed(course: "ICS3U", section: 1, destination: destination),
                        name
                    )
                }
                // Every destination the sheet names, in order, by the words
                // it uses for each — the SAVED list, not the window's (#396).
                if let destinations = expect["destinations"] as? [String] {
                    XCTAssertEqual(plan.destinations, describing(destinations, folder: world.folder), name)
                }
                XCTAssertEqual(shown.notice, expectedNotice, name)
                continue
            }

            let uses: (
                course: Course?, destinations: [CourseConfiguration.DeployDestination], refusal: String?, notice: String?
            ) = SectionDetailView.whatADeployUses(
                windowCourse: world.window, anyCopyUnsaved: anyCopyUnsaved, cloudflareAccountID: ""
            )
            XCTAssertEqual(destinationTypes(uses.destinations), expect["destinations"] as? [String] ?? [], name)
            if expect["refusal"] as? String == "settingsCouldNotBeReadToDeploy" {
                XCTAssertNil(uses.course, "\(name): the window's copy was used in the file's place")
                XCTAssertEqual(uses.refusal, SpecialNames.settingsCouldNotBeReadToDeploy(course: "ICS3U"), name)
            } else {
                XCTAssertNil(uses.refusal, name)
            }
            XCTAssertEqual(uses.notice, expectedNotice, name)

            // What the caller is told. Case 2 is the assistant pressing the
            // window's button: the sentence is ADDED to what it reads out.
            // The button's own result is never changed.
            let result: AssistSiteWorkResult = AssistSiteWorkResult(succeeded: true, message: "Deployed.")
            let told: AssistSiteWorkResult = SectionDetailView.whatTheAssistantIsTold(
                result, notice: uses.notice, pressedByTheAssistant: act == "assistantDeployThroughWindow"
            )
            if act == "assistantDeployThroughWindow", let expectedNotice {
                XCTAssertEqual(told.message, "Deployed.\n\n" + expectedNotice, name)
            } else {
                XCTAssertEqual(told.message, "Deployed.", name)
            }

        }
    }

    // MARK: - Deploying

    func testADeployUsesTheSavedDestinationNotTheUnsavedOne() throws {
        let world: World = try makeWorld(saved: ["deploy_target": "netlify"], deployedBefore: ["netlify"])
        applyUnsaved(["deploy_target": "local_folder", "deploy_folder_path": "{folder}"], to: world)

        let uses = SectionDetailView.whatADeployUses(
            windowCourse: world.window, anyCopyUnsaved: true, cloudflareAccountID: ""
        )

        XCTAssertEqual(destinationTypes(uses.destinations), ["netlify"])
        XCTAssertEqual(uses.course?.configuration.deployTarget, "netlify")
        XCTAssertEqual(world.window.configuration.deployTarget, "local_folder", "the window keeps its edit")
    }

    func testAnUnreadableSettingsFileRefusesAndNeverFallsBack() throws {
        let world: World = try makeWorld(
            saved: ["deploy_target": "local_folder", "deploy_folder_path": "{folder}"], deployedBefore: []
        )
        try "{ not json".write(to: world.window.configFileURL, atomically: true, encoding: .utf8)
        let refusal: String = SpecialNames.settingsCouldNotBeReadToDeploy(course: "ICS3U")

        let uses = SectionDetailView.whatADeployUses(
            windowCourse: world.window, anyCopyUnsaved: false, cloudflareAccountID: ""
        )
        XCTAssertNil(uses.course)
        XCTAssertEqual(uses.destinations.count, 0)
        XCTAssertEqual(uses.refusal, refusal)

        let shown = ScheduleDeploySheet.whatTheSheetShows(
            windowCourse: world.window, sectionNumber: 1, when: later, now: Date(),
            cloudflareAccountID: "", workspaceURL: world.root, anyCopyUnsaved: false
        )
        XCTAssertNil(shown.plan, "the sheet planned from the window's copy")
        XCTAssertEqual(shown.unreadable, refusal)

        let launchControl: FakeLaunchControl = FakeLaunchControl()
        XCTAssertEqual(
            ScheduleDeploySheet.scheduleFromTheSavedSettings(
                windowCourse: world.window, sectionNumber: 1, when: later, workspaceURL: world.root,
                cloudflareAccountID: "", anyCopyUnsaved: false, runner: launchControl
            ),
            refusal
        )
        XCTAssertEqual(launchControl.bootstrappedURLs.count, 0, "a deploy was set from the window's copy")
    }

    func testANoticeOnlyWhenSomethingIsUnsaved() throws {
        let world: World = try makeWorld(saved: ["deploy_target": "netlify"], deployedBefore: ["netlify"])
        let nothing = SectionDetailView.whatADeployUses(
            windowCourse: world.window,
            anyCopyUnsaved: world.window.configuration.hasUnsavedChanges,
            cloudflareAccountID: ""
        )
        XCTAssertNil(nothing.notice)

        applyUnsaved(["footer_html": "<p>An unsaved footer</p>"], to: world)
        let footerOnly = SectionDetailView.whatADeployUses(
            windowCourse: world.window,
            anyCopyUnsaved: world.window.configuration.hasUnsavedChanges,
            cloudflareAccountID: ""
        )
        XCTAssertEqual(footerOnly.notice, SpecialNames.deployUsesSavedSettings, "any unsaved setting is said")
        XCTAssertEqual(destinationTypes(footerOnly.destinations), ["netlify"])
    }

    func testAsSavedNowNeverTouchesTheWindowsCopy() throws {
        let world: World = try makeWorld(saved: ["deploy_target": "netlify"], deployedBefore: [])
        applyUnsaved(["deploy_target": "local_folder", "deploy_folder_path": "{folder}"], to: world)

        let saved: Course = try world.window.asSavedNow()

        XCTAssertFalse(saved === world.window)
        XCTAssertEqual(saved.configuration.deployTarget, "netlify")
        XCTAssertEqual(world.window.configuration.deployTarget, "local_folder")
        XCTAssertTrue(world.window.configuration.hasUnsavedChanges)
        XCTAssertEqual(saved.code, world.window.code)
        XCTAssertEqual(saved.directoryURL, world.window.directoryURL)
    }

    // MARK: - Scheduling

    func testTheScheduleSheetShowsAndRefusesFromTheSavedSettings() throws {
        let refusing: World = try makeWorld(saved: ["deploy_target": "netlify"], deployedBefore: [])
        applyUnsaved(["deploy_target": "local_folder", "deploy_folder_path": "{folder}"], to: refusing)
        let refused = ScheduleDeploySheet.whatTheSheetShows(
            windowCourse: refusing.window, sectionNumber: 1, when: later, now: Date(),
            cloudflareAccountID: "", workspaceURL: refusing.root, anyCopyUnsaved: true
        )
        XCTAssertEqual(refused.plan?.isSchedulable, false, "an unsaved folder is not what the run would use")
        XCTAssertEqual(refused.notice, SpecialNames.schedulingUsesSavedSettings)

        let allowing: World = try makeWorld(
            saved: ["deploy_target": "local_folder", "deploy_folder_path": "{folder}"], deployedBefore: []
        )
        applyUnsaved(["deploy_target": "netlify"], to: allowing)
        let allowed = ScheduleDeploySheet.whatTheSheetShows(
            windowCourse: allowing.window, sectionNumber: 1, when: later, now: Date(),
            cloudflareAccountID: "", workspaceURL: allowing.root, anyCopyUnsaved: true
        )
        XCTAssertEqual(allowed.plan?.isSchedulable, true, allowed.plan?.description ?? "")
        XCTAssertEqual(allowed.plan?.destinations, [allowing.folder.path])
    }

    /// A Save can land between drawing the sheet and pressing Schedule: what
    /// is written is what the file says at the PRESS.
    func testSchedulingAtThePressReadsTheFileAgain() throws {
        let world: World = try makeWorld(saved: ["deploy_target": "netlify"], deployedBefore: ["netlify"])
        let unsavedFolder: URL = world.root.appendingPathComponent("typed-but-not-saved")
        try FileManager.default.createDirectory(at: unsavedFolder, withIntermediateDirectories: true)
        applyUnsaved(["deploy_target": "local_folder", "deploy_folder_path": unsavedFolder.path], to: world)

        let drawn = ScheduleDeploySheet.whatTheSheetShows(
            windowCourse: world.window, sectionNumber: 1, when: later, now: Date(),
            cloudflareAccountID: "", workspaceURL: world.root, anyCopyUnsaved: true
        )
        XCTAssertEqual(drawn.plan?.destinations, ["Netlify"])

        // Course Settings in another window saves a folder.
        let otherCopy: CourseConfiguration = try CourseConfiguration(contentsOf: world.window.configFileURL)
        otherCopy.deployTarget = "local_folder"
        otherCopy.deployFolderPath = world.folder.path
        try otherCopy.write(to: world.window.configFileURL)

        let launchControl: FakeLaunchControl = FakeLaunchControl()
        XCTAssertNil(ScheduleDeploySheet.scheduleFromTheSavedSettings(
            windowCourse: world.window, sectionNumber: 1, when: later, workspaceURL: world.root,
            cloudflareAccountID: "", anyCopyUnsaved: true, runner: launchControl
        ))
        let plistURL: URL = try XCTUnwrap(launchControl.bootstrappedURLs.first)
        let plist: [String: Any] = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: try Data(contentsOf: plistURL), format: nil)
                as? [String: Any]
        )
        let environment: [String: String] = try XCTUnwrap(plist["EnvironmentVariables"] as? [String: String])
        let recorded: String = try XCTUnwrap(environment[ScheduledDeploy.scheduledToKey])
        let scheduledTo: [String] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(recorded.utf8)) as? [String]
        )
        XCTAssertEqual(scheduledTo, [world.folder.path], "not what was saved at the press")

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("ICS3U/1 · set a deploy for "), trail)
        XCTAssertTrue(trail.contains("used the settings as last saved (a folder)"), trail)
        XCTAssertFalse(trail.contains(world.folder.path), "a path on the trail: \(trail)")
    }

    // MARK: - The trail line

    func testTheTrailLineSaysWhetherTheDestinationDifferedByKindOnly() throws {
        let world: World = try makeWorld(saved: ["deploy_target": "netlify"], deployedBefore: ["netlify"])
        applyUnsaved(["deploy_target": "local_folder", "deploy_folder_path": "{folder}"], to: world)
        let saved: Course = try world.window.asSavedNow()
        XCTAssertTrue(SettingsSaveNotice.unsavedDestinationDiffers(from: saved, windowCourse: world.window, in: []))

        SettingsSaveNotice.noteDeployUsedTheSavedSettings(
            act: "deployed from the section window", saved: saved, windowCourse: world.window, sectionNumber: 1
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(
            "ICS3U/1 · deployed from the section window while Course Settings had changes nobody saved — "
                + "used the settings as last saved (Netlify); the unsaved changes named somewhere else to deploy"
        ), trail)
        XCTAssertFalse(trail.contains(world.folder.path), trail)

        let sameKind: World = try makeWorld(saved: ["deploy_target": "netlify"], deployedBefore: ["netlify"])
        applyUnsaved(["footer_html": "<p>x</p>"], to: sameKind)
        XCTAssertFalse(SettingsSaveNotice.unsavedDestinationDiffers(
            from: try sameKind.window.asSavedNow(), windowCourse: sameKind.window, in: []
        ))
    }

    // MARK: - The source

    /// `deployAndWait` reads destinations only from the saved course, and sets
    /// the notice AFTER stopping the preview — whose stop clears it.
    func testDeployAndWaitReadsDestinationsOnlyFromTheSavedCourse() throws {
        let body: String = try codeLines(
            of: "SectionDetailView.swift", from: "func deployAndWait(", to: "func openInBrowser("
        )
        XCTAssertFalse(body.contains("course.configuration.allDeployDestinations"), "the window's destinations")
        XCTAssertFalse(body.contains("course: course,"), "the window's course handed to an act")
        XCTAssertTrue(body.contains("SectionDetailView.whatADeployUses("))
        let whole: String = try codeLines(of: "SectionDetailView.swift", from: "struct SectionDetailView", to: nil)
        XCTAssertFalse(whole.contains("var deployRefusalReason"), "the instance property that read the window's copy is back")

        let stop: Range<String.Index> = try XCTUnwrap(body.range(of: "await stopPreviewAndWait()"))
        let notice: Range<String.Index> = try XCTUnwrap(body.range(of: "unsavedSettingsNotice = uses.notice"))
        XCTAssertTrue(stop.lowerBound < notice.lowerBound, "the notice is set before the preview stop that clears it")

        let sheet: String = try codeLines(of: "ScheduleDeploySheet.swift", from: "struct ScheduleDeploySheet", to: nil)
        XCTAssertFalse(sheet.contains("course: course,"), "the sheet hands the window's course to an act")
        XCTAssertFalse(sheet.contains("course: course\n"), "the sheet hands the window's course to an act")
    }

    // MARK: - What the assistant is told, and whose sentence the banner is

    /// The implementation review's F2: nothing pinned the assistant's copy of
    /// the sentence. Both paths add it through ONE function, and the window's
    /// every return after the sentence is set goes through `said(`.
    func testTheAssistantIsToldTheSentenceOnBothPaths() throws {
        let result: AssistSiteWorkResult = AssistSiteWorkResult(
            succeeded: false, message: "Could not.", isAboutTheDestination: true
        )
        let told = SectionDetailView.whatTheAssistantIsTold(
            result, notice: SpecialNames.deployUsesSavedSettings, pressedByTheAssistant: true
        )
        XCTAssertEqual(told.message, "Could not.\n\n" + SpecialNames.deployUsesSavedSettings)
        XCTAssertFalse(told.succeeded)
        XCTAssertTrue(told.isAboutTheDestination)
        XCTAssertEqual(
            SectionDetailView.whatTheAssistantIsTold(
                result, notice: SpecialNames.deployUsesSavedSettings, pressedByTheAssistant: false
            ).message,
            "Could not.",
            "the button's own result gains nothing: the window already shows the sentence"
        )
        XCTAssertEqual(
            SectionDetailView.whatTheAssistantIsTold(result, notice: nil, pressedByTheAssistant: true).message,
            "Could not."
        )
        XCTAssertEqual(SettingsSaveNotice.addingTheNotice(nil, to: "x"), "x")

        let window: String = try codeLines(of: "SectionDetailView.swift", from: "struct SectionDetailView", to: nil)
        XCTAssertTrue(
            window.contains("deploy: { await deployAndWait(pressedByTheAssistant: true) }"),
            "the window controller the assistant presses no longer says it is the assistant"
        )
        let body: String = try codeLines(
            of: "SectionDetailView.swift", from: "func deployAndWait(", to: "func openInBrowser("
        )
        let noticeSet: Range<String.Index> = try XCTUnwrap(body.range(of: "unsavedSettingsNotice = uses.notice"))
        var returnsAfter: Int = 0
        for line in body[noticeSet.upperBound...].components(separatedBy: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("return ") && !trimmed.hasPrefix("return SectionDetailView.whatTheAssistantIsTold(") {
                returnsAfter += 1
                XCTAssertTrue(trimmed.hasPrefix("return said("), "a result that skips the sentence: \(trimmed)")
            }
        }
        XCTAssertGreaterThanOrEqual(returnsAfter, 3)

        let headless: String = try codeLines(
            of: "AssistSiteWork.swift",
            from: "    func deploy(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {",
            to: nil
        )
        XCTAssertEqual(
            headless.components(separatedBy: "SettingsSaveNotice.addingTheNotice(notice, to: message)").count - 1, 2,
            "the headless deploy's failure and success results must both carry the sentence"
        )
    }

    /// The implementation review's F3: a preview's wait loop can end the
    /// preview after a deploy has set its own sentence. A state decides what
    /// that clears, not the order the two happen in.
    func testAPreviewEndingNeverTakesAwayADeploysSentence() throws {
        XCTAssertFalse(SectionDetailView.previewEndClearsTheNotice(owner: .deploy))
        XCTAssertTrue(SectionDetailView.previewEndClearsTheNotice(owner: .preview))
        XCTAssertTrue(SectionDetailView.previewEndClearsTheNotice(owner: nil))

        let release: String = try codeLines(
            of: "SectionDetailView.swift", from: "func releasePreviewLease()", to: "static func refusalForAReferenceCourse"
        )
        XCTAssertTrue(release.contains("SectionDetailView.previewEndClearsTheNotice(owner: unsavedSettingsNoticeOwner)"))
        let body: String = try codeLines(
            of: "SectionDetailView.swift", from: "func deployAndWait(", to: "func openInBrowser("
        )
        XCTAssertTrue(body.contains("unsavedSettingsNoticeOwner = uses.notice == nil ? nil : .deploy"))
    }

    // MARK: - Helpers

    private func makeWorld(saved: [String: Any], deployedBefore: [String]) throws -> World {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("saved-settings-\(UUID().uuidString)", isDirectory: true)
        roots.append(root)
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        try "#!/bin/bash\n".write(to: root.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        try "#!/bin/bash\n".write(to: root.appendingPathComponent("deploy.sh"), atomically: true, encoding: .utf8)
        let folder: URL = root.appendingPathComponent("published-here")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let agents: URL = root.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = agents
        ScheduledDeploy.scheduledScriptsDirectoryOverride = root.appendingPathComponent("scheduled")

        var values: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        for (key, value) in saved {
            values[key] = substituting(value, folder: folder)
        }
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
        for type in deployedBefore {
            let marker: String = type == "cloudflare_pages" ? ".cloudflare_sites" : ".netlify_sites"
            let markerFolder: URL = courseURL.appendingPathComponent(marker)
            try FileManager.default.createDirectory(at: markerFolder, withIntermediateDirectories: true)
            try "{}".write(
                to: markerFolder.appendingPathComponent("section1.json"), atomically: true, encoding: .utf8
            )
        }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        var window: Course? = nil
        for candidate in workspace.courses where candidate.code == "ICS3U" {
            window = candidate
        }
        return World(root: root, workspace: workspace, window: try XCTUnwrap(window), folder: folder)
    }

    /// Edits in the window's copy that nobody has saved, the way Course
    /// Settings holds them.
    private func applyUnsaved(_ changes: [String: Any], to world: World) {
        for (key, value) in changes {
            world.window.configuration.values[key] = substituting(value, folder: world.folder)
        }
    }

    /// `{folder}` replaced wherever it appears — at the top level, or inside
    /// `additional_deploy_targets`' entries (#396's case), where a literal
    /// "{folder}" would be refused as a folder that does not exist and the
    /// case would silently test a refusal.
    private func substituting(_ value: Any, folder: URL) -> Any {
        if let text = value as? String, text == "{folder}" {
            return folder.path
        }
        if let list = value as? [Any] {
            var substituted: [Any] = []
            for item in list {
                substituted.append(substituting(item, folder: folder))
            }
            return substituted
        }
        if let entry = value as? [String: Any] {
            var substituted: [String: Any] = [:]
            for (key, item) in entry {
                substituted[key] = substituting(item, folder: folder)
            }
            return substituted
        }
        return value
    }

    /// Destination types as the schedule sheet names them: "Netlify",
    /// "Cloudflare Pages", or the folder's path.
    private func describing(_ types: [String], folder: URL) -> [String] {
        var names: [String] = []
        for type in types {
            if type == "local_folder" {
                names.append(folder.path)
            } else if type == "cloudflare_pages" {
                names.append("Cloudflare Pages")
            } else {
                names.append("Netlify")
            }
        }
        return names
    }

    private func destinationTypes(_ destinations: [CourseConfiguration.DeployDestination]) -> [String] {
        var types: [String] = []
        for destination in destinations {
            types.append(destination.type)
        }
        return types
    }

    private func sentence(named key: String?) throws -> String? {
        guard let key else {
            return nil
        }
        let sentences: [String: String] = [
            "deployUsesSavedSettings": SpecialNames.deployUsesSavedSettings,
            "schedulingUsesSavedSettings": SpecialNames.schedulingUsesSavedSettings,
            "previewUsesSavedSettings": SpecialNames.previewUsesSavedSettings,
        ]
        return try XCTUnwrap(sentences[key], "no sentence named \(key)")
    }

    private func sharedRulesSection(_ name: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[name] as? [String: Any], "No \(name) in shared-rules.json")
    }

    /// The code of one product file between two markers, comment lines left
    /// out so a comment naming the old way cannot fail or pass the test.
    private func codeLines(of fileName: String, from start: String, to end: String?) throws -> String {
        var text: String = ""
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: ActivityTrailWiringTests.productSourceFolderURL()) {
            if fileURL.lastPathComponent == fileName {
                text = try String(contentsOf: fileURL, encoding: .utf8)
            }
        }
        let from: Range<String.Index> = try XCTUnwrap(text.range(of: start), "\(fileName) has no \(start)")
        var upTo: String.Index = text.endIndex
        if let end, let found = text.range(of: end, range: from.upperBound..<text.endIndex) {
            upTo = found.lowerBound
        }
        var kept: [String] = []
        for line in text[from.lowerBound..<upTo].components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }
}
