import AppKit
import XCTest
@testable import QuartzTeachers

/// Preview at the page last viewed (#504): every case in
/// `contracts/shared-rules.json` → `previewStartPage`, run against the app's
/// own functions — deserialised, never retyped — plus what the contract
/// cannot carry: the controller's ledger telling the teacher's navigations
/// from the app's own loads, the setting and the remembered pages persisting
/// in injected preferences, and source scans of the wiring no unit test can
/// construct (the section window is never built in the suite).
@MainActor
final class PreviewStartPageTests: XCTestCase {

    // MARK: - Stored properties

    private var suiteName: String = ""
    private var defaults: UserDefaults!

    // MARK: - Functions

    override func setUpWithError() throws {
        suiteName = "plantoir-504-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func contract() throws -> [String: Any] {
        return try SharedRulesContractTests.section("previewStartPage")
    }

    private static func cases(_ value: Any?) throws -> [[String: Any]] {
        return try XCTUnwrap(value as? [[String: Any]])
    }

    /// A JSON string, or nil for `null` or a missing key.
    private static func text(_ value: Any?) -> String? {
        return value as? String
    }

    private static func setting(_ value: Any?) throws -> PreviewOpensAt {
        return try XCTUnwrap(PreviewOpensAt(rawValue: try XCTUnwrap(value as? String)))
    }

    private static func sectionViewSource() throws -> String {
        let url: URL = UserFacingLabelWordsTests.macAppRoot()
            .appendingPathComponent("QuartzTeachers/Views/Section/SectionDetailView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func productSource(_ relativePath: String) throws -> String {
        let url: URL = UserFacingLabelWordsTests.macAppRoot()
            .appendingPathComponent("QuartzTeachers").appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The text from `signature` to the end of its braces.
    private static func body(of signature: String, in source: String) throws -> String {
        let start: Range<String.Index> = try XCTUnwrap(source.range(of: signature), signature)
        let rest: Substring = source[start.lowerBound...]
        var depth: Int = 0
        var sawOpening: Bool = false
        var result: String = ""
        for character in rest {
            result.append(character)
            if character == "{" {
                depth += 1
                sawOpening = true
            } else if character == "}" {
                depth -= 1
                if sawOpening && depth == 0 {
                    break
                }
            }
        }
        return result
    }

    // MARK: - Wording and titles

    func testTheWordsAreTheContracts() throws {
        let wording: [String: Any] = try XCTUnwrap(try PreviewStartPageTests.contract()["wording"] as? [String: Any])
        let ours: [String: String] = [
            "preview": PreviewStartPageWording.preview,
            "previewAtLastViewed": PreviewStartPageWording.previewAtLastViewed,
            "stopPreview": PreviewStartPageWording.stopPreview,
            "paneTitle": PreviewStartPageWording.paneTitle,
            "settingLabel": PreviewStartPageWording.settingLabel,
            "frontPageChoice": PreviewStartPageWording.frontPageChoice,
            "lastViewedChoice": PreviewStartPageWording.lastViewedChoice,
            "optionNote": PreviewStartPageWording.optionNote,
        ]
        XCTAssertEqual(Set(wording.keys), Set(ours.keys), "the contract and the app name the same words")
        for (key, words) in ours {
            XCTAssertEqual(wording[key] as? String, words, key)
        }
    }

    /// The one function behind the toolbar's title and Section ▸ Preview's.
    func testEveryTitleCaseRunsThroughTheOneFunction() throws {
        let contract: [String: Any] = try PreviewStartPageTests.contract()
        let wording: [String: Any] = try XCTUnwrap(contract["wording"] as? [String: Any])
        let titles: [String: Any] = try XCTUnwrap(contract["titles"] as? [String: Any])
        let cases: [[String: Any]] = try PreviewStartPageTests.cases(titles["cases"])
        XCTAssertEqual(cases.count, 6)
        for testCase in cases {
            let setting: PreviewOpensAt = try PreviewStartPageTests.setting(testCase["setting"])
            let held: Bool = try XCTUnwrap(testCase["modifierHeld"] as? Bool)
            let running: Bool = try XCTUnwrap(testCase["previewIsRunning"] as? Bool)
            let titleKey: String = try XCTUnwrap(testCase["title"] as? String)
            let expected: String = try XCTUnwrap(wording[titleKey] as? String, titleKey)
            XCTAssertEqual(
                PreviewStartPage.buttonTitle(setting: setting, optionHeld: held, previewIsRunning: running),
                expected,
                "\(testCase)"
            )
        }
    }

    /// The title says what the press does: the same XOR decides both.
    func testTheTitleAndThePressAgree() {
        for setting in PreviewOpensAt.allCases {
            for held in [false, true] {
                let opensAt: PreviewOpensAt = PreviewStartPage.opensAt(setting: setting, optionHeld: held)
                XCTAssertEqual(
                    PreviewStartPage.buttonTitle(setting: setting, optionHeld: held, previewIsRunning: false),
                    PreviewStartPage.title(for: opensAt)
                )
                XCTAssertEqual(opensAt == setting, !held, "Option gives the opposite, and only Option")
            }
        }
    }

    func testOnlyOptionCountsAsTheModifier() {
        XCTAssertTrue(PreviewStartPage.optionIsHeld([.option]))
        XCTAssertTrue(PreviewStartPage.optionIsHeld([.option, .shift]))
        XCTAssertFalse(PreviewStartPage.optionIsHeld([.shift, .command]))
        XCTAssertFalse(PreviewStartPage.optionIsHeld([]))
    }

    // MARK: - The setting

    func testTheSettingReadsAsTheContractSays() throws {
        let block: [String: Any] = try XCTUnwrap(try PreviewStartPageTests.contract()["setting"] as? [String: Any])
        var raw: [String] = []
        for choice in PreviewOpensAt.allCases {
            raw.append(choice.rawValue)
        }
        XCTAssertEqual(block["values"] as? [String], raw, "the persisted values are the contract's, in its order")
        XCTAssertEqual(block["default"] as? String, PreviewOpensAt.frontPage.rawValue)
        for testCase in try PreviewStartPageTests.cases(block["cases"]) {
            let stored: String? = PreviewStartPageTests.text(testCase["stored"])
            let reads: PreviewOpensAt = try PreviewStartPageTests.setting(testCase["reads"])
            XCTAssertEqual(PreviewStartPage.setting(fromStored: stored), reads, "\(testCase)")
        }
    }

    func testTheSettingIsKeptInThePreferencesItWasGiven() {
        XCTAssertEqual(AppSettings(defaults: defaults).previewOpensAt, .frontPage, "nothing stored is the front page")
        let settings: AppSettings = AppSettings(defaults: defaults)
        settings.previewOpensAt = .lastViewed
        XCTAssertEqual(defaults.string(forKey: AppSettings.previewOpensAtKey), "lastViewed")
        XCTAssertEqual(AppSettings(defaults: defaults).previewOpensAt, .lastViewed, "read back by a new copy")
        defaults.set("pageLeftOff", forKey: AppSettings.previewOpensAtKey)
        XCTAssertEqual(AppSettings(defaults: defaults).previewOpensAt, .frontPage, "a retired name is the front page")
    }

    func testTheSettingChangeTrailIsTheContracts() throws {
        let lines: [[String: Any]] = try PreviewStartPageTests.cases(
            try PreviewStartPageTests.contract()["settingChangedTrail"]
        )
        XCTAssertEqual(lines.count, PreviewOpensAt.allCases.count)
        for line in lines {
            let choice: PreviewOpensAt = try PreviewStartPageTests.setting(line["choice"])
            XCTAssertEqual(PreviewStartPage.settingChangedWords(choice), line["trail"] as? String)
        }
    }

    // MARK: - Remembering only the teacher's navigations

    /// Every `remembering` case, through the REAL controller: an app load is
    /// started with `showFreshBuild` (the call every fresh build makes), the
    /// address change is handed in the way the web view's observer hands it,
    /// and only a change the controller counted as the teacher's is measured
    /// against the root.
    func testRememberingCasesThroughTheController() throws {
        let block: [String: Any] = try XCTUnwrap(try PreviewStartPageTests.contract()["remembering"] as? [String: Any])
        let cases: [[String: Any]] = try PreviewStartPageTests.cases(block["cases"])
        XCTAssertGreaterThanOrEqual(cases.count, 12)
        for testCase in cases {
            let name: String = PreviewStartPageTests.text(testCase["name"]) ?? "?"
            let root: URL = try XCTUnwrap(URL(string: try XCTUnwrap(testCase["previewRoot"] as? String)))
            var page: URL?
            if let address = PreviewStartPageTests.text(testCase["page"]) {
                page = URL(string: address)
            }
            let appLoad: Bool = try XCTUnwrap(testCase["appLoadUnderWay"] as? Bool)
            let controller: WebPreviewController = WebPreviewController()
            if appLoad {
                controller.showFreshBuild(try XCTUnwrap(URL(string: "http://127.0.0.1:1/")))
            }
            let before: Int = controller.teacherNavigations
            controller.addressChanged(to: page)
            var remembered: String?
            if controller.teacherNavigations != before {
                remembered = PreviewStartPage.rememberedPath(page: controller.teacherPage, previewRoot: root)
            }
            XCTAssertEqual(remembered, PreviewStartPageTests.text(testCase["remember"]), name)
        }
    }

    /// The BLOCKER the plan review found, end to end in the controller:
    /// every load the app makes — a fresh build, Reload, Rebuild Preview —
    /// leaves what the teacher was reading alone, and the teacher's own
    /// navigation counts again once the app's load has ended.
    func testTheAppsOwnLoadsNeverMoveThePageLastViewed() throws {
        let root: URL = try XCTUnwrap(URL(string: "http://127.0.0.1:8091/"))
        let lesson: URL = try XCTUnwrap(URL(string: "http://127.0.0.1:8091/Unit-1/Lesson-3"))
        let controller: WebPreviewController = WebPreviewController()

        controller.showFreshBuild(root)
        XCTAssertTrue(controller.appLoadIsUnderWay)
        controller.addressChanged(to: root)
        XCTAssertEqual(controller.teacherNavigations, 0, "the first page of a build is the app's")

        controller.appLoadEnded()
        controller.addressChanged(to: lesson)
        XCTAssertEqual(controller.teacherNavigations, 1)
        XCTAssertEqual(controller.teacherPage, lesson)

        controller.reload()
        XCTAssertTrue(controller.appLoadIsUnderWay, "Reload is the app's load")
        controller.addressChanged(to: root)
        XCTAssertEqual(controller.teacherPage, lesson, "Reload never moves it")

        controller.appLoadEnded()
        controller.showFreshBuild(root)
        controller.addressChanged(to: root)
        XCTAssertEqual(controller.teacherNavigations, 1, "Rebuild Preview never moves it")
        XCTAssertEqual(controller.teacherPage, lesson)

        // A navigation that is not the app's ends nothing.
        controller.navigationEnded(nil)
        XCTAssertTrue(controller.appLoadIsUnderWay)
    }

    func testTheLedgerByItself() {
        var ledger: PreviewNavigationLedger = PreviewNavigationLedger()
        XCTAssertTrue(ledger.changeIsTheTeachers())
        ledger.appLoadBegan()
        XCTAssertFalse(ledger.changeIsTheTeachers())
        ledger.appLoadEnded()
        XCTAssertTrue(ledger.changeIsTheTeachers())
    }

    func testThePagesAreKeptPerSectionInThePreferencesTheyWereGiven() {
        let store: LastViewedPages = LastViewedPages(defaults: defaults)
        let one: String = LastViewedPages.key(folderPath: "/Users/t/Teaching", courseCode: "ICS3U", sectionNumber: 1)
        let two: String = LastViewedPages.key(folderPath: "/Users/t/Teaching", courseCode: "ICS3U", sectionNumber: 2)
        XCTAssertNil(store.page(forKey: one))
        store.remember("Unit-1/Lesson-3", forKey: one)
        store.remember("", forKey: two)
        let again: LastViewedPages = LastViewedPages(defaults: defaults)
        XCTAssertEqual(again.page(forKey: one), "Unit-1/Lesson-3", "kept across a quit")
        XCTAssertEqual(again.page(forKey: two), "", "the front page is a page too")
        XCTAssertNil(again.page(forKey: LastViewedPages.key(
            folderPath: "/Users/t/Moved", courseCode: "ICS3U", sectionNumber: 1
        )), "a moved folder starts with nothing")
    }

    // MARK: - Asking and the fallback

    func testEveryAnswerCaseAsksAsTheContractSays() async throws {
        let contract: [String: Any] = try PreviewStartPageTests.contract()
        let attempts: Int = try XCTUnwrap(contract["attempts"] as? Int)
        XCTAssertEqual(attempts, PreviewStartPage.attempts)
        XCTAssertEqual(contract["secondsPerAttempt"] as? Double, PreviewStartPage.secondsPerAttempt)
        XCTAssertEqual(contract["goneStatuses"] as? [Int], PreviewStartPage.goneStatuses)
        let block: [String: Any] = try XCTUnwrap(contract["answers"] as? [String: Any])
        let page: URL = try XCTUnwrap(URL(string: "http://127.0.0.1:8091/Unit-1/Lesson-3"))
        for testCase in try PreviewStartPageTests.cases(block["cases"]) {
            let raw: [Any] = try XCTUnwrap(testCase["statuses"] as? [Any])
            var statuses: [Int?] = []
            for value in raw {
                statuses.append(value as? Int)
            }
            let expected: PreviewStartPage.PageAnswer = try XCTUnwrap(
                PreviewStartPage.PageAnswer(rawValue: try XCTUnwrap(testCase["answer"] as? String))
            )
            let script: ScriptedStatuses = ScriptedStatuses(statuses)
            let answer: PreviewStartPage.PageAnswer = await PreviewStartPage.askWhetherThePageIsThere(
                page,
                attempts: attempts,
                fetch: { url in
                    return await script.next(url)
                },
                pause: {
                    await script.paused()
                }
            )
            XCTAssertEqual(answer, expected, "\(raw)")
            let asked: Int = await script.askedCount
            let pauses: Int = await script.pauseCount
            XCTAssertEqual(asked, statuses.count, "asks stop at the first answer that decides: \(raw)")
            XCTAssertEqual(pauses, max(0, asked - 1), "a pause between tries, none after the last")
            let addresses: [URL] = await script.asked
            for address in addresses {
                XCTAssertEqual(address, page)
            }
        }
    }

    /// Every case: where the preview opens and the trail's exact words.
    func testEveryDecisionCaseIsTheContracts() throws {
        for testCase in try PreviewStartPageTests.cases(try PreviewStartPageTests.contract()["cases"]) {
            let name: String = PreviewStartPageTests.text(testCase["name"]) ?? "?"
            let setting: PreviewOpensAt = try PreviewStartPageTests.setting(testCase["setting"])
            let held: Bool = try XCTUnwrap(testCase["modifierHeld"] as? Bool)
            let request: PreviewStartPage.Request = PreviewStartPage.Request(
                opensAt: PreviewStartPage.opensAt(setting: setting, optionHeld: held),
                frontPageWasJustChanged: try XCTUnwrap(testCase["frontPageWasJustChanged"] as? Bool)
            )
            let remembered: String? = PreviewStartPageTests.text(testCase["remembered"])
            var answer: PreviewStartPage.PageAnswer?
            if let raw = PreviewStartPageTests.text(testCase["answer"]) {
                answer = try XCTUnwrap(PreviewStartPage.PageAnswer(rawValue: raw), raw)
            }
            // The page is asked about exactly when the case gives an answer.
            XCTAssertEqual(PreviewStartPage.needsAsking(request, remembered: remembered), answer != nil, name)
            let decision: PreviewStartPage.Decision = PreviewStartPage.decide(request, remembered: remembered, answer: answer)
            let opens: String = try XCTUnwrap(testCase["opens"] as? String)
            XCTAssertEqual(decision.opensRememberedPage, opens == "rememberedPage", name)
            XCTAssertEqual(decision.trailWords, PreviewStartPageTests.text(testCase["trail"]), name)
        }
    }

    func testThePageIsAskedForOnThisRunsServerByPath() throws {
        let root: URL = try XCTUnwrap(URL(string: "http://127.0.0.1:8101/"))
        XCTAssertEqual(
            PreviewStartPage.pageAddress(root: root, path: "Unit%201/Lesson%203")?.absoluteString,
            "http://127.0.0.1:8101/Unit%201/Lesson%203",
            "the port is this run's; the path is kept encoded"
        )
        XCTAssertEqual(PreviewStartPage.pageAddress(root: root, path: "")?.absoluteString, "http://127.0.0.1:8101/")
    }

    // MARK: - Wiring the suite cannot construct

    /// The toolbar's press reads the keyboard at the moment it happens (the
    /// watcher only titles it); every way in that is not the teacher's press
    /// takes the front page; and what the teacher navigated to is measured
    /// against the ROOT, never the page being shown (504 plan review, 7).
    func testTheSectionWindowIsWiredAsTheRuleSays() throws {
        let view: String = try PreviewStartPageTests.sectionViewSource()
        XCTAssertTrue(view.contains("optionHeld: PreviewStartPage.optionIsHeld(NSEvent.modifierFlags)"),
                      "the press reads the keyboard when it happens")
        XCTAssertTrue(view.contains("optionHeld: OptionKeyWatcher.shared.optionIsHeld"),
                      "the title follows the watcher")
        XCTAssertTrue(view.contains("    func startPreview(at request: PreviewStartPage.Request = .frontPage) {"),
                      "every other way in opens the front page")

        // Only the press and the question's aftermath ask for anything else.
        var askers: Int = 0
        for line in view.components(separatedBy: "\n") {
            let code: String = line.trimmingCharacters(in: .whitespaces)
            if code.hasPrefix("//") || code.hasPrefix("func ") {
                continue
            }
            if code.contains("startPreview(at:") {
                askers += 1
            }
        }
        XCTAssertEqual(askers, 2, "pressPreview(opensAt:) and afterThePreviewAlert() only")

        let remember: String = try PreviewStartPageTests.body(of: "func rememberWhereTheTeacherIs()", in: view)
        XCTAssertTrue(remember.contains("previewRoot: previewRoot"))
        XCTAssertFalse(remember.contains("previewRoot: previewURL"))
        XCTAssertTrue(remember.contains("guard previewURL != nil"), "nothing is remembered while no site is showing")

        // previewRoot is cleared wherever previewURL is.
        let cleared: Int = view.components(separatedBy: "previewURL = nil").count - 1
        let rootCleared: Int = view.components(separatedBy: "previewRoot = nil").count - 1
        XCTAssertEqual(cleared, rootCleared)

        // A Show on Front Page that wrote the page opens the front page.
        let answer: String = try PreviewStartPageTests.body(of: "func answerTodaysClass(", in: view)
        XCTAssertTrue(answer.contains("pendingPreviewRequest.frontPageWasJustChanged = true"))
    }

    /// Every app load marks itself, and Section ▸ Preview has its alternate.
    func testTheControllerAndTheMenuAreWired() throws {
        let controller: String = try PreviewStartPageTests.productSource("Views/Section/WebPreviewController.swift")
        let load: String = try PreviewStartPageTests.body(of: "private func loadIgnoringEverythingCached(", in: controller)
        XCTAssertTrue(load.contains("ledger.appLoadBegan()"), "a fresh build and Reload are the app's loads")
        let reload: String = try PreviewStartPageTests.body(of: "func reload()", in: controller)
        XCTAssertTrue(reload.contains("ledger.appLoadBegan()"), "a reload with nothing requested is the app's too")

        let menus: String = try PreviewStartPageTests.productSource("App/SubjectMenus.swift")
        XCTAssertTrue(menus.contains(".modifierKeyAlternate(.option)"))
        XCTAssertTrue(menus.contains("previewItem(opensAt: previewSetting.opposite, enabled)"))
    }
}

/// Statuses handed out one per ask, recording what was asked.
actor ScriptedStatuses {

    // MARK: - Stored properties

    private var remaining: [Int?]
    private(set) var asked: [URL] = []
    private(set) var pauseCount: Int = 0

    // MARK: - Computed properties

    var askedCount: Int {
        return asked.count
    }

    // MARK: - Initializer

    init(_ statuses: [Int?]) {
        self.remaining = statuses
    }

    // MARK: - Functions

    func next(_ url: URL) -> Int? {
        asked.append(url)
        if remaining.isEmpty {
            return nil
        }
        return remaining.removeFirst()
    }

    func paused() {
        pauseCount += 1
    }
}
