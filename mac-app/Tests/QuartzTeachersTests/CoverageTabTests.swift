import XCTest
@testable import QuartzTeachers

/// The Coverage tab on a section's page (#793, 793b): every case in
/// `contracts/shared-rules.json` → `coverageTab.tab` and
/// `coverageTab.mapOfThisBuild`, deserialised and run, never retyped; every
/// sentence pinned by its key; the refresh's state across the events that
/// drive it; and a click through Open in Obsidian's own route with every
/// door to Obsidian faked.
///
/// To see each fail:
/// - `testEveryTabCase`: in `SectionTabs.shown`, append `.coverage` whatever
///   `hasCurriculum` and `recordHasMaps` say;
/// - `testEveryStateCase`: delete the `.pages` branch in
///   `CoverageTabDisplay.display` (the changed-since case fails), or the
///   `refresh == .pending` clause;
/// - `testEveryItemCase`: drop the `recorded == link.buildId` check in
///   `CoverageItem.resolve` (the older-page case opens), or the `..` refusal;
/// - `testEveryNavigationCase`: return `.handToTheApp` without `byALinkClick`;
/// - `testTheWordsAreTheContracts`: change one word in `CoverageTabWording`;
/// - `testAClickOpensThroughTheRouteAndAReferenceCourseAsksFirst`: open the
///   page with `obsidianOpening.openPage` directly instead of the route.
@MainActor
final class CoverageTabTests: XCTestCase {

    // MARK: - Stored properties

    nonisolated(unsafe) private var rootURL: URL!
    nonisolated(unsafe) private var previousStore: ProblemReportStore?

    // MARK: - Setting up

    override func setUp() async throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("coverage-tab-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail", isDirectory: true))
        SectionCoverage.shared.reset()
        ObsidianFigureAddOnsThisRun.forget()
    }

    override func tearDown() async throws {
        if let previousStore {
            ActivityTrail.store = previousStore
        }
        SectionCoverage.shared.reset()
        ObsidianFigureAddOnsThisRun.forget()
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func coverageTab() throws -> [String: Any] {
        return try SharedRulesContractTests.section("coverageTab")
    }

    private static func tab() throws -> [String: Any] {
        return try XCTUnwrap(try coverageTab()["tab"] as? [String: Any])
    }

    private func trail() -> String {
        return ActivityTrail.store.activityText(includingPrompts: false)
    }

    // MARK: - The tabs

    func testEveryTabCase() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try CoverageTabTests.tab()["tabCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let shown: [SectionTab] = SectionTabs.shown(
                hasCurriculum: try XCTUnwrap(testCase["hasCurriculum"] as? Bool),
                recordHasMaps: try XCTUnwrap(testCase["recordHasMaps"] as? Bool),
                hasProblems: try XCTUnwrap(testCase["hasProblems"] as? Bool)
            )
            var shownNames: [String] = []
            for tab in shown {
                shownNames.append(tab.rawValue)
            }
            XCTAssertEqual(shownNames, try XCTUnwrap(testCase["expectShown"] as? [String]), name)
            let chosen: SectionTab = try XCTUnwrap(SectionTab(rawValue: try XCTUnwrap(testCase["chosen"] as? String)))
            XCTAssertEqual(SectionTabs.showing(chosen: chosen, shown: shown).rawValue, testCase["expectShowing"] as? String, name)
        }
    }

    /// The preview takes the browser commands only on Website, and what a
    /// build raises waits only on Coverage.
    func testOnlyWebsiteReachesThePreviewAndOnlyCoverageHoldsTheAlerts() {
        XCTAssertTrue(SectionTabs.previewTakesCommands(showing: .website))
        XCTAssertFalse(SectionTabs.previewTakesCommands(showing: .coverage))
        XCTAssertFalse(SectionTabs.previewTakesCommands(showing: .problems))
        XCTAssertTrue(SectionTabs.alertsWait(showing: .coverage))
        XCTAssertFalse(SectionTabs.alertsWait(showing: .website))
        XCTAssertFalse(SectionTabs.alertsWait(showing: .problems))
    }

    // MARK: - The record

    /// `mapOfThisBuild`, the cases the Python's `coverage_tab_map_state` runs.
    func testEveryMapOfThisBuildCase() throws {
        let block: [String: Any] = try XCTUnwrap(try CoverageTabTests.coverageTab()["mapOfThisBuild"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 9)
        for (index, testCase) in cases.enumerated() {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let folder: URL = rootURL.appendingPathComponent("map-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let recordURL: URL = folder.appendingPathComponent(CoverageTab.recordName)
            if let text = testCase["recordText"] as? String {
                try Data(text.utf8).write(to: recordURL)
            } else if let record = testCase["record"] as? [String: Any] {
                try JSONSerialization.data(withJSONObject: record).write(to: recordURL)
            }
            for page in (testCase["pagesOnDisk"] as? [String]) ?? [] {
                try Data("<p>map</p>".utf8).write(to: folder.appendingPathComponent(page))
            }
            let state: CoverageTab.MapState = CoverageTab.mapState(folder: folder, buildId: testCase["buildId"] as? String)
            XCTAssertEqual(state.rawValue, testCase["expect"] as? String, name)
        }
    }

    /// The tab's own reading: another version and no curriculum are told
    /// apart from no record, and the counts come through.
    func testTheReadingTellsTheEmptyKindsApart() throws {
        let folder: URL = rootURL.appendingPathComponent("kinds", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let recordURL: URL = folder.appendingPathComponent(CoverageTab.recordName)
        XCTAssertEqual(CoverageTab.read(folder: folder, buildId: "b").kind, .noRecord)
        try JSONSerialization.data(withJSONObject: ["version": 2, "buildId": "b", "page": "m.html"]).write(to: recordURL)
        XCTAssertEqual(CoverageTab.read(folder: folder, buildId: "b").kind, .otherVersion)
        try JSONSerialization.data(withJSONObject: ["version": 1, "buildId": "b", "page": NSNull(), "maps": []]).write(to: recordURL)
        XCTAssertEqual(CoverageTab.read(folder: folder, buildId: "b").kind, .noMaps)
        try Data("<p>map</p>".utf8).write(to: folder.appendingPathComponent("m.html"))
        try JSONSerialization.data(withJSONObject: [
            "version": 1, "buildId": "b", "page": "m.html", "startedNs": 1_763_000_000_000_000_000,
            "maps": [["title": "Curriculum Coverage", "folder": "Curriculum", "expectations": 57,
                      "notYetAddressed": 12, "pages": ["A1.1": "Curriculum/A1.1.md"]]],
        ]).write(to: recordURL)
        let reading: CoverageTab.Reading = CoverageTab.read(folder: folder, buildId: "b")
        XCTAssertEqual(reading.kind, .thisBuild)
        XCTAssertTrue(reading.hasMaps)
        let record: CoverageTabRecord = try XCTUnwrap(reading.record)
        XCTAssertEqual(record.startedNs, 1_763_000_000_000_000_000)
        XCTAssertEqual(record.startedAt?.timeIntervalSince1970 ?? 0, 1_763_000_000, accuracy: 0.001)
        XCTAssertEqual(record.maps.first?.pages["A1.1"], "Curriculum/A1.1.md")
        XCTAssertEqual(CoverageTab.read(folder: folder, buildId: nil).kind, .anotherBuild, "no .build-id: never this build's")
    }

    // MARK: - What the tab shows

    func testEveryStateCase() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try CoverageTabTests.tab()["stateCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 20)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let given: [String: Any] = try XCTUnwrap(testCase["facts"] as? [String: Any])
            var facts: CoverageTabDisplay.Facts = CoverageTabDisplay.Facts()
            facts.record = try XCTUnwrap(CoverageTab.RecordKind(rawValue: try XCTUnwrap(given["record"] as? String)), name)
            switch try XCTUnwrap(given["refresh"] as? String) {
            case "starting":
                facts.refresh = .starting
            case "pending":
                facts.refresh = .pending
            case "didNotFinish":
                facts.refresh = .didNotFinish
            case "refused":
                facts.refresh = .refused("a reason")
            default:
                facts.refresh = .none
            }
            facts.ownBuildBeforeItsMap = try XCTUnwrap(given["ownBuildBeforeItsMap"] as? Bool)
            facts.ownBuildRunning = try XCTUnwrap(given["ownBuildRunning"] as? Bool)
            facts.deploying = try XCTUnwrap(given["deploying"] as? Bool)
            facts.elsewhere = try XCTUnwrap(given["elsewhere"] as? Bool)
            facts.otherWindow = try XCTUnwrap(given["otherWindow"] as? Bool)
            facts.changed = try XCTUnwrap(CoverageChange(rawValue: try XCTUnwrap(given["changed"] as? String)), name)
            facts.rulesCompiled = try XCTUnwrap(given["rulesCompiled"] as? Bool)
            facts.obsidianInstalled = try XCTUnwrap(given["obsidianInstalled"] as? Bool)

            let expected: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            let shown: CoverageTabDisplay.Display = CoverageTabDisplay.display(facts)
            XCTAssertEqual(shown.kind.rawValue, expected["kind"] as? String, name)
            XCTAssertEqual(shown.lines, try XCTUnwrap(expected["lines"] as? [String]), name)
            XCTAssertEqual(shown.button, expected["button"] as? String, name)
            XCTAssertEqual(shown.buttonEnabled, expected["buttonEnabled"] as? Bool, name)
            XCTAssertEqual(shown.description, expected["description"] as? String, name)
        }
    }

    /// Every key a state can show is a sentence in `words`.
    func testEveryLineAStateShowsIsAWord() throws {
        let words: [String: Any] = try XCTUnwrap(try CoverageTabTests.tab()["words"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(try CoverageTabTests.tab()["stateCases"] as? [[String: Any]])
        for testCase in cases {
            let expected: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            var keys: [String] = try XCTUnwrap(expected["lines"] as? [String])
            if let button = expected["button"] as? String {
                keys.append(button)
            }
            if let description = expected["description"] as? String {
                keys.append(description)
            }
            for key in keys where key != "refusedReason" {
                XCTAssertNotNil(words[key], "\(key) is not in coverageTab.tab.words")
            }
        }
    }

    // MARK: - Where a click may go

    func testEveryNavigationCase() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try CoverageTabTests.tab()["navigationCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)
        let folder: URL = rootURL.appendingPathComponent("section1/.coverage-tab", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let text: String = try XCTUnwrap(testCase["url"] as? String).replacingOccurrences(of: "{folder}", with: folder.path)
            let url: URL = try XCTUnwrap(URL(string: text), name)
            let decision: PlanNavigation.Decision = CoverageNavigation.decide(
                url: url,
                isNewWindow: try XCTUnwrap(testCase["isNewWindow"] as? Bool),
                byALinkClick: try XCTUnwrap(testCase["byALinkClick"] as? Bool),
                coverageFolder: folder
            )
            XCTAssertEqual(decision.rawValue, testCase["expect"] as? String, name)
        }
    }

    func testEveryLinkCase() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try CoverageTabTests.tab()["linkCases"] as? [[String: Any]])
        for testCase in cases {
            let text: String = try XCTUnwrap(testCase["text"] as? String)
            var parsed: CoverageLink? = nil
            if let url = URL(string: text) {
                parsed = CoverageLink.parse(url)
            }
            if let expected = testCase["expect"] as? [String: Any] {
                let link: CoverageLink = try XCTUnwrap(parsed, text)
                XCTAssertEqual(link.buildId, expected["buildId"] as? String, text)
                XCTAssertEqual(link.map, expected["map"] as? Int, text)
                XCTAssertEqual(link.code, expected["code"] as? String, text)
            } else {
                XCTAssertNil(parsed, text)
            }
        }
    }

    /// The link the build writes (`coverageTab.link.cases`) is a link here.
    func testEveryLinkTheBuildWritesIsRead() throws {
        let block: [String: Any] = try XCTUnwrap(try CoverageTabTests.coverageTab()["link"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        for testCase in cases {
            let text: String = try XCTUnwrap(testCase["expect"] as? String)
            let url: URL = try XCTUnwrap(URL(string: text), text)
            let link: CoverageLink = try XCTUnwrap(CoverageLink.parse(url), text)
            XCTAssertEqual(link.buildId, testCase["buildId"] as? String)
            XCTAssertEqual(link.map, testCase["map"] as? Int)
            XCTAssertEqual(link.code, testCase["code"] as? String)
        }
    }

    // MARK: - What a click opens

    /// `itemLayout` under a temporary root, and the course folder in it.
    private func layOutTheItems() throws -> URL {
        let layout: [String: Any] = try XCTUnwrap(try CoverageTabTests.tab()["itemLayout"] as? [String: Any])
        let root: URL = rootURL.appendingPathComponent("items", isDirectory: true)
        for file in try XCTUnwrap(layout["files"] as? [String]) {
            let url: URL = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("A page.\n".utf8).write(to: url)
        }
        for folder in try XCTUnwrap(layout["folders"] as? [String]) {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let links: [String: Any] = try XCTUnwrap(layout["links"] as? [String: Any])
        for (place, target) in links {
            let url: URL = root.appendingPathComponent(place)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: try XCTUnwrap(target as? String))
        }
        return root.appendingPathComponent("course", isDirectory: true)
    }

    private func itemRecord() throws -> CoverageTabRecord {
        let given: [String: Any] = try XCTUnwrap(try CoverageTabTests.tab()["itemRecord"] as? [String: Any])
        var object: [String: Any] = given
        object["version"] = 1
        object["page"] = "map.html"
        let data: Data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(CoverageTabRecord.parse(data))
    }

    func testEveryItemCase() throws {
        let course: URL = try layOutTheItems()
        let record: CoverageTabRecord = try itemRecord()
        let cases: [[String: Any]] = try XCTUnwrap(try CoverageTabTests.tab()["itemCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let click: [String: Any] = try XCTUnwrap(testCase["click"] as? [String: Any])
            let link: CoverageLink = CoverageLink(
                buildId: try XCTUnwrap(click["buildId"] as? String),
                map: try XCTUnwrap(click["map"] as? Int),
                code: try XCTUnwrap(click["code"] as? String)
            )
            let outcome: CoverageItem.Outcome = CoverageItem.resolve(link, record: record, courseFolder: course)
            let expected: String = try XCTUnwrap(testCase["expect"] as? String)
            switch outcome {
            case .open(let file, let place):
                XCTAssertEqual("open", expected, name)
                XCTAssertEqual(place, testCase["place"] as? String, name)
                XCTAssertTrue(file.path.hasPrefix(course.path + "/"), "\(name): \(file.path)")
            case .reload:
                XCTAssertEqual("reload", expected, name)
            case .notListed:
                XCTAssertEqual("notListed", expected, name)
            case .gone:
                XCTAssertEqual("gone", expected, name)
            case .outside:
                XCTAssertEqual("outside", expected, name)
            }
        }
        let noRecord: CoverageItem.Outcome = CoverageItem.resolve(
            CoverageLink(buildId: "x", map: 0, code: "A1.1"), record: nil, courseFolder: course
        )
        XCTAssertEqual(noRecord, .reload, "no record: nothing opens")
    }

    // MARK: - The words

    func testTheWordsAreTheContracts() throws {
        let words: [String: Any] = try XCTUnwrap(try CoverageTabTests.tab()["words"] as? [String: Any])
        let mine: [String: String] = [
            "tabCoverage": CoverageTabWording.tabCoverage,
            "asOf": CoverageTabWording.asOf,
            "asOfNoTime": CoverageTabWording.asOfNoTime,
            "olderMap": CoverageTabWording.olderMap,
            "olderMapNoTime": CoverageTabWording.olderMapNoTime,
            "making": CoverageTabWording.making,
            "couldNotMakeAgain": CoverageTabWording.couldNotMakeAgain,
            "couldNotMake": CoverageTabWording.couldNotMake,
            "changedSince": CoverageTabWording.changedSince,
            "mayBeOutOfDate": CoverageTabWording.mayBeOutOfDate,
            "deploying": CoverageTabWording.deploying,
            "elsewhere": CoverageTabWording.elsewhere,
            "otherWindow": CoverageTabWording.otherWindow,
            "clickHint": CoverageTabWording.clickHint,
            "noObsidian": CoverageTabWording.noObsidian,
            "pageGone": CoverageTabWording.pageGone,
            "pageOutside": CoverageTabWording.pageOutside,
            "makeTheMap": CoverageTabWording.makeTheMap,
            "makeTheMapAgain": CoverageTabWording.makeTheMapAgain,
            "makeHelp": CoverageTabWording.makeHelp,
            "emptyTitle": CoverageTabWording.emptyTitle,
            "emptyDescription": CoverageTabWording.emptyDescription,
            "emptyOtherVersion": CoverageTabWording.emptyOtherVersion,
            "emptyNoCurriculum": CoverageTabWording.emptyNoCurriculum,
            "cannotShowTitle": CoverageTabWording.cannotShowTitle,
            "cannotShowDescription": CoverageTabWording.cannotShowDescription,
        ]
        XCTAssertEqual(Set(words.keys), Set(mine.keys), "every word in the contract is one the tab has, and no more")
        for (key, sentence) in mine {
            XCTAssertEqual(words[key] as? String, sentence, key)
            // Rule 1: plain words only.
            for machinery in ["toolchain", "script", "Docker", "container", "Quartz", "HTML", "JSON"] {
                XCTAssertFalse(sentence.contains(machinery), "\(key) mentions \(machinery)")
            }
            // Every key the view asks for is one `sentence` knows.
            XCTAssertFalse(CoverageTabWording.sentence(key).isEmpty, key)
        }
        XCTAssertEqual(
            CoverageTabWording.sentence("noObsidian"),
            CoverageTabWording.noObsidian.replacingOccurrences(of: "{machine}", with: "Mac"),
            "the machine's word is filled in"
        )
        XCTAssertEqual(SectionProblemsWording.tabWebsite, "Website")
    }

    func testTheTrailWordsAreTheContracts() throws {
        let words: [String: Any] = try XCTUnwrap(try CoverageTabTests.tab()["trailWords"] as? [String: Any])
        let mine: [String: String] = [
            "looked": CoverageTabTrail.looked,
            "oneMap": CoverageTabTrail.oneMap,
            "maps": CoverageTabTrail.maps,
            "counts": CoverageTabTrail.counts,
            "changedSince": CoverageTabTrail.changedSince,
            "notThisBuild": CoverageTabTrail.notThisBuild,
            "noMapYet": CoverageTabTrail.noMapYet,
            "otherVersion": CoverageTabTrail.otherVersion,
            "noCurriculum": CoverageTabTrail.noCurriculum,
            "couldNotShow": CoverageTabTrail.couldNotShow,
            "asked": CoverageTabTrail.asked,
            "madeAgain": CoverageTabTrail.madeAgain,
            "didNotFinish": CoverageTabTrail.didNotFinish,
            "refused": CoverageTabTrail.refused,
            "opened": CoverageTabTrail.opened,
            "didNotOpen": CoverageTabTrail.didNotOpen,
            "whyGone": CoverageTabTrail.whyGone,
            "whyOutside": CoverageTabTrail.whyOutside,
            "whyOlder": CoverageTabTrail.whyOlder,
            "whyNotListed": CoverageTabTrail.whyNotListed,
            "whyNoObsidian": CoverageTabTrail.whyNoObsidian,
        ]
        XCTAssertEqual(Set(words.keys), Set(mine.keys))
        for (key, sentence) in mine {
            XCTAssertEqual(words[key] as? String, sentence, key)
        }
    }

    /// The looked-at line carries counts and states, never an
    /// expectation's words or a path.
    func testTheLookedAtLineCarriesCountsOnly() throws {
        let record: CoverageTabRecord = try XCTUnwrap(CoverageTabRecord.parse(try JSONSerialization.data(withJSONObject: [
            "version": 1, "buildId": "b", "page": "m.html", "startedNs": NSNull(),
            "maps": [
                ["title": "Curriculum Coverage", "folder": "Curriculum", "expectations": 57, "notYetAddressed": 12,
                 "pages": ["A1.1": "Curriculum/A1.1 Secret Words.md"]],
                ["title": "College Board Coverage", "folder": "College Board", "expectations": 10, "notYetAddressed": 1,
                 "pages": [:]],
            ],
        ])))
        let reading: CoverageTab.Reading = CoverageTab.Reading(
            kind: .anotherBuild, record: record, page: nil, folder: rootURL
        )
        let line: String = CoverageTabTrail.lookedText(reading: reading, changed: .pages, rulesCompiled: true)
        XCTAssertEqual(
            line,
            "looked at the Coverage tab: 2 maps, 67 expectations, 13 not yet addressed if every page were published; "
                + "made at an unknown time; pages have changed since; the latest build did not make it again"
        )
        XCTAssertFalse(line.contains("Secret"), "never a page's name or words")
        XCTAssertEqual(
            CoverageTabTrail.lookedText(reading: reading, changed: .none, rulesCompiled: false),
            CoverageTabTrail.filled(CoverageTabTrail.couldNotShow)
        )
        let none: CoverageTab.Reading = CoverageTab.Reading(kind: .noRecord, record: nil, page: nil, folder: rootURL)
        XCTAssertEqual(CoverageTabTrail.lookedText(reading: none, changed: .none, rulesCompiled: true),
                       "looked at the Coverage tab: no map made yet")
    }

    /// `changedSince`'s answer in the tab's words: #768's reasons, no other.
    func testTheChangeIsBuildFreshnesssOwnRule() throws {
        XCTAssertEqual(SectionCoverage.change(for: nil), .none)
        XCTAssertEqual(SectionCoverage.change(for: .pages), .pages)
        XCTAssertEqual(SectionCoverage.change(for: .clock), .clock)
        let course: URL = rootURL.appendingPathComponent("fresh", isDirectory: true)
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        try Data("page".utf8).write(to: course.appendingPathComponent("Lesson.md"))
        let now: Date = Date()
        XCTAssertEqual(BuildFreshness.changedSince(reference: now.addingTimeInterval(3600), courseFolder: course, now: now), .clock)
        XCTAssertEqual(BuildFreshness.changedSince(reference: now.addingTimeInterval(-3600), courseFolder: course, now: now), .pages)
        XCTAssertNil(BuildFreshness.changedSince(reference: now.addingTimeInterval(60), courseFolder: course, now: now.addingTimeInterval(120)))
    }

    // MARK: - The refresh, across the events that drive it

    /// A course in the fixture workspace, with its section 1's built output
    /// reachable through `.merged_output`.
    private func fixtureCourse() throws -> (folder: URL, course: Course) {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fixtureURL)
        }
        let courses: [Course] = try WorkspaceModel.discoverCourses(in: fixtureURL.appendingPathComponent("courses"))
        let course: Course = try XCTUnwrap(courses.first)
        let output: URL = CoverageTab.sectionOutput(courseFolder: course.directoryURL, sectionNumber: 1)
        try? FileManager.default.removeItem(at: course.directoryURL.appendingPathComponent(BuildOutputLocation.linkName))
        try FileManager.default.createDirectory(at: output.appendingPathComponent(CoverageTab.folderName), withIntermediateDirectories: true)
        return (folder: fixtureURL, course: course)
    }

    /// A build of section 1 starting (`.build-id`) and, when `withMap`,
    /// writing its map and record.
    private func build(_ id: String, course: Course, withMap: Bool) throws {
        let output: URL = CoverageTab.sectionOutput(courseFolder: course.directoryURL, sectionNumber: 1)
        try Data((id + "\n").utf8).write(to: output.appendingPathComponent(CoverageTab.buildIdName))
        if !withMap {
            return
        }
        let folder: URL = output.appendingPathComponent(CoverageTab.folderName)
        try Data("<p>map</p>".utf8).write(to: folder.appendingPathComponent("map-\(id).html"))
        try JSONSerialization.data(withJSONObject: [
            "version": 1, "buildId": id, "page": "map-\(id).html", "startedNs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1_000_000_000)),
            "maps": [["title": "Curriculum Coverage", "folder": "Curriculum", "expectations": 3, "notYetAddressed": 1, "pages": [:]]],
        ]).write(to: folder.appendingPathComponent(CoverageTab.recordName))
    }

    func testARefreshIsMadeAgainWhenItsBuildWritesItsMap() throws {
        let made: (folder: URL, course: Course) = try fixtureCourse()
        let store: SectionCoverage = SectionCoverage.shared
        try build("b1", course: made.course, withMap: true)
        store.reload(folder: made.folder, course: made.course, sectionNumber: 1)
        let key: String = store.key(folder: made.folder, course: made.course, sectionNumber: 1)
        XCTAssertEqual(store.entry(key).reading?.kind, .thisBuild)
        XCTAssertTrue(store.showsTheTab(key), "a record naming a map shows the tab")

        store.noteRefreshAsked(folder: made.folder, course: made.course, sectionNumber: 1)
        XCTAssertEqual(store.entry(key).refresh, .pending)
        // The build starts: the old map is now another build's, and still making.
        try build("b2", course: made.course, withMap: false)
        store.reload(folder: made.folder, course: made.course, sectionNumber: 1)
        XCTAssertEqual(store.entry(key).reading?.kind, .anotherBuild)
        XCTAssertEqual(store.entry(key).refresh, .pending, "a reading mid-build settles nothing")
        // The map is written, then the problems line.
        try build("b2", course: made.course, withMap: true)
        store.reload(folder: made.folder, course: made.course, sectionNumber: 1, afterAMarker: true)
        XCTAssertEqual(store.entry(key).reading?.kind, .thisBuild)
        XCTAssertEqual(store.entry(key).refresh, CoverageRefresh.none, "made again, in place")
        XCTAssertTrue(trail().contains(CoverageTabTrail.asked), trail())
        XCTAssertTrue(trail().contains(CoverageTabTrail.madeAgain), trail())
    }

    func testARefreshWhoseBuildMakesNoMapDidNotFinish() throws {
        let made: (folder: URL, course: Course) = try fixtureCourse()
        let store: SectionCoverage = SectionCoverage.shared
        try build("b1", course: made.course, withMap: true)
        store.reload(folder: made.folder, course: made.course, sectionNumber: 1)
        let key: String = store.key(folder: made.folder, course: made.course, sectionNumber: 1)
        store.noteRefreshAsked(folder: made.folder, course: made.course, sectionNumber: 1)
        try build("b2", course: made.course, withMap: false)
        store.reload(folder: made.folder, course: made.course, sectionNumber: 1, afterAMarker: true)
        XCTAssertEqual(store.entry(key).refresh, .didNotFinish, "its map step ran and made no map")
        XCTAssertTrue(trail().contains(CoverageTabTrail.didNotFinish), trail())
        // A later build's own map clears it.
        try build("b3", course: made.course, withMap: true)
        store.reload(folder: made.folder, course: made.course, sectionNumber: 1)
        XCTAssertEqual(store.entry(key).refresh, CoverageRefresh.none)
    }

    /// A switch of section (or Stop) ends the run before the map: settled
    /// from what is on disk, never left waiting.
    func testARunThatEndsBeforeTheMapIsSettledAndOneThatEndsAfterIsNot() throws {
        let made: (folder: URL, course: Course) = try fixtureCourse()
        let store: SectionCoverage = SectionCoverage.shared
        try build("b1", course: made.course, withMap: true)
        store.reload(folder: made.folder, course: made.course, sectionNumber: 1)
        let key: String = store.key(folder: made.folder, course: made.course, sectionNumber: 1)

        store.noteRefreshAsked(folder: made.folder, course: made.course, sectionNumber: 1)
        store.noteOwnRunEnded(folder: made.folder, course: made.course, sectionNumber: 1)
        XCTAssertEqual(store.entry(key).refresh, .didNotFinish, "stopped before .build-id moved")

        store.noteRefreshAsked(folder: made.folder, course: made.course, sectionNumber: 1)
        try build("b2", course: made.course, withMap: true)
        store.noteOwnRunEnded(folder: made.folder, course: made.course, sectionNumber: 1)
        XCTAssertEqual(store.entry(key).refresh, CoverageRefresh.none, "the map was written before the run ended")

        store.noteRefreshAsked(folder: made.folder, course: made.course, sectionNumber: 1)
        store.noteRefreshRefused(folder: made.folder, course: made.course, sectionNumber: 1, reason: "A reason.")
        XCTAssertEqual(store.entry(key).refresh, .refused("A reason."))
        XCTAssertTrue(trail().contains(CoverageTabTrail.refused), trail())
    }

    // MARK: - A click, through Open in Obsidian's own route

    @MainActor
    final class OpenLog {
        var openedPages: [String] = []
        var openedFolders: [String] = []
    }

    private func workspace(log: OpenLog) -> WorkspaceModel {
        let settings: AppSettings = AppSettings(defaults: TestDefaults.make())
        settings.obsidianFigureAddOns = .no
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        var opening: ObsidianOpening = ObsidianOpening()
        opening.settings = settings
        opening.isInstalled = { return true }
        opening.isRunning = { return false }
        opening.registryData = { return nil }
        opening.open = { folder, _ in
            log.openedFolders.append(folder.path)
        }
        opening.openPage = { page, _ in
            log.openedPages.append(page.path)
        }
        opening.quitAndWait = {}
        opening.reopen = { _ in }
        opening.previewedAddress = { _, _, _ in
            return nil
        }
        workspace.obsidianOpening = opening
        return workspace
    }

    func testAClickOpensThroughTheRouteAndAReferenceCourseAsksFirst() throws {
        let made: (folder: URL, course: Course) = try fixtureCourse()
        let page: URL = made.course.directoryURL.appendingPathComponent("Curriculum/A1.1.md")
        try FileManager.default.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("A1.1\n".utf8).write(to: page)
        let words: String = CoverageTabTrail.clickText(.open(file: page, place: "Curriculum/A1.1"), code: "A1.1")

        let log: OpenLog = OpenLog()
        let workspace: WorkspaceModel = workspace(log: log)
        let pressed: OpenInObsidianPressed = workspace.openExpectationInObsidian(
            course: made.course, sectionNumber: 1, page: page, trailWords: words
        ) { _ in }
        XCTAssertTrue(pressed.opened)
        XCTAssertEqual(log.openedPages, [page.path], "the record's file, through the route's one door")
        XCTAssertEqual(log.openedFolders, [])
        XCTAssertTrue(trail().contains("\(made.course.code)/1 · " + words), trail())
        XCTAssertFalse(trail().contains("not a page of the preview"), "the click's own line, not the preview's")

        // A reference course asks for its note first, carrying the page.
        LockedPagesNote.defaults = TestDefaults.make()
        defer { LockedPagesNote.defaults = PlantoirDefaults.shared }
        let referenceLog: OpenLog = OpenLog()
        let reference: WorkspaceModel = self.workspace(log: referenceLog)
        made.course.configuration.keptForReference = true
        let asked: OpenInObsidianPressed = reference.openExpectationInObsidian(
            course: made.course, sectionNumber: 1, page: page, trailWords: words
        ) { _ in }
        XCTAssertFalse(asked.opened)
        let request: LockedPagesNoteRequest = try XCTUnwrap(reference.lockedPagesNoteRequest)
        XCTAssertEqual(request.page?.path, page.path)
        reference.openInObsidianAfterTheNote(request)
        XCTAssertEqual(referenceLog.openedPages, [page.path])
    }

    /// The trail line for each click that opens nothing names the code and
    /// why, never the path, built from the contract's keys; and the line
    /// for a click that goes ahead says what was ASKED of Obsidian, not that
    /// it opened, which nothing here can confirm (#721).
    func testAClickThatOpensNothingSaysWhy() throws {
        let words: [String: Any] = try XCTUnwrap(try CoverageTabTests.tab()["trailWords"] as? [String: Any])
        func line(_ code: String, _ whyKey: String) throws -> String {
            let template: String = try XCTUnwrap(words["didNotOpen"] as? String)
            let why: String = try XCTUnwrap(words[whyKey] as? String)
            return template.replacingOccurrences(of: "{code}", with: code).replacingOccurrences(of: "{why}", with: why)
        }
        XCTAssertEqual(CoverageTabTrail.clickText(.gone, code: "A1.2"), try line("A1.2", "whyGone"))
        XCTAssertEqual(CoverageTabTrail.clickText(.outside, code: "A1.3"), try line("A1.3", "whyOutside"))
        XCTAssertEqual(CoverageTabTrail.clickText(.reload, code: "A1.1"), try line("A1.1", "whyOlder"))
        XCTAssertEqual(CoverageTabTrail.clickText(.notListed, code: "C9.9"), try line("C9.9", "whyNotListed"))
        let opened: String = CoverageTabTrail.clickText(.open(file: rootURL, place: "Curriculum/A1.1"), code: "A1.1")
        XCTAssertFalse(opened.hasPrefix("opened"), "a click cannot confirm Obsidian opened: \(opened)")
        let noObsidian: String = CoverageTabTrail.didNotOpenText(code: "A1.1", why: CoverageTabTrail.whyNoObsidian)
        XCTAssertFalse(noObsidian.contains("{machine}"), noObsidian)
        XCTAssertTrue(noObsidian.hasSuffix("on this Mac"), noObsidian)
        XCTAssertFalse(CoverageTabTrail.lookedText(
            reading: CoverageTab.Reading(kind: .noRecord, record: nil, page: nil, folder: rootURL),
            changed: .none, rulesCompiled: false
        ).contains("{machine}"))
    }

    /// `"version": true` is not version 1: JSON's true bridges to a number
    /// that reads as 1 (the 793b review's LOW 6).
    func testATrueVersionIsNotVersionOne() throws {
        let data: Data = try JSONSerialization.data(withJSONObject: ["version": true, "buildId": "b", "page": NSNull(), "maps": []])
        XCTAssertNil(CoverageTabRecord.parse(data))
        XCTAssertFalse(CoverageTabRecord.isAnotherVersion(data))
        let one: Data = try JSONSerialization.data(withJSONObject: ["version": 1, "buildId": "b", "page": NSNull(), "maps": []])
        XCTAssertNotNil(CoverageTabRecord.parse(one))
    }

    /// Only the tab's own refresh has its refusal said in the tab; the
    /// teacher's own Preview press is answered as ever (the 793b review's M2).
    func testOnlyTheTabsOwnRefreshHasItsRefusalSaidInTheTab() {
        XCTAssertTrue(SectionTabs.refusalIsTheTabs(refresh: .starting))
        XCTAssertTrue(SectionTabs.refusalIsTheTabs(refresh: .pending))
        XCTAssertFalse(SectionTabs.refusalIsTheTabs(refresh: .none))
        XCTAssertFalse(SectionTabs.refusalIsTheTabs(refresh: .didNotFinish))
        XCTAssertFalse(SectionTabs.refusalIsTheTabs(refresh: .refused("a reason")))
    }

    /// A map's web view is kept while its section is shown and released when
    /// no window shows it (the 793b review's LOW 2).
    func testAMapsWebViewGoesWithItsSection() {
        let store: SectionCoverage = SectionCoverage.shared
        store.noteShown("one")
        store.noteShown("one")
        _ = store.controller("one", open: { (_: URL) in }, cannotShow: {})
        store.noteShown("two")
        _ = store.controller("two", open: { (_: URL) in }, cannotShow: {})
        XCTAssertEqual(store.keptWebViews, ["one", "two"])
        store.noteGone("one")
        XCTAssertEqual(store.keptWebViews, ["one", "two"], "a second window still shows section one")
        store.noteGone("one")
        store.noteGone("two")
        XCTAssertEqual(store.keptWebViews, [])
    }

    // MARK: - The press, its stop and its start (the 793b review's H1)

    /// What the steps did: how often they stopped and started.
    @MainActor
    final class Counted {

        // MARK: - Stored properties

        var stops: Int = 0
        var starts: Int = 0
        var stateDuringTheStop: CoverageRefresh?
    }

    /// `sequenceCases`, through the real steps. The stop the test hands in
    /// does the case's "during the stop" steps itself, which is exactly the
    /// moment between the press and the start, with no window, no run loop
    /// and no delay. To see it fail: in `SectionCoverage.makeAgain`, call
    /// `noteRefreshAsked` after the stop instead of `beginRefresh` before
    /// it (the code the review found), and the second-press, leave and quit
    /// cases start a build.
    func testEverySequenceCase() async throws {
        let cases: [[String: Any]] = try XCTUnwrap(try CoverageTabTests.tab()["sequenceCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        let made: (folder: URL, course: Course) = try fixtureCourse()
        try build("b1", course: made.course, withMap: true)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let store: SectionCoverage = SectionCoverage.shared
            store.reset()
            ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail-\(UUID().uuidString)", isDirectory: true))
            store.reload(folder: made.folder, course: made.course, sectionNumber: 1)
            let key: String = store.key(folder: made.folder, course: made.course, sectionNumber: 1)
            let counted: Counted = Counted()
            let refused: Bool = (testCase["startRefused"] as? Bool) ?? false
            let previewRunning: Bool = try XCTUnwrap(testCase["previewRunning"] as? Bool)
            let duringTheStop: [String] = try XCTUnwrap(testCase["duringTheStop"] as? [String])
            func press(stopSteps: [String]) async {
                await SectionCoverage.makeAgain(
                    store: store, folder: made.folder, course: made.course, sectionNumber: 1,
                    previewIsRunning: previewRunning,
                    stop: {
                        counted.stops += 1
                        counted.stateDuringTheStop = store.entry(key).refresh
                        for step in stopSteps {
                            switch step {
                            case "press":
                                await press(stopSteps: [])
                            case "ownRunEnded":
                                store.noteOwnRunEnded(folder: made.folder, course: made.course, sectionNumber: 1)
                            case "leave":
                                store.abandonRefresh(folder: made.folder, course: made.course, sectionNumber: 1)
                            case "quit":
                                store.abandonEveryRefresh()
                            default:
                                XCTFail("\(name): no step \(step)")
                            }
                        }
                    },
                    start: {
                        counted.starts += 1
                        return !refused
                    }
                )
            }
            await press(stopSteps: duringTheStop)
            if previewRunning {
                XCTAssertEqual(counted.stateDuringTheStop, .starting, "\(name): recorded at the press, before the stop")
            }
            for step in try XCTUnwrap(testCase["afterTheStart"] as? [String]) where step == "press" {
                await press(stopSteps: [])
            }
            let expected: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            XCTAssertEqual(counted.stops, expected["stops"] as? Int, name)
            XCTAssertEqual(counted.starts, expected["starts"] as? Int, name)
            XCTAssertEqual(store.entry(key).refresh.name, expected["refresh"] as? String, name)
            let lines: [String] = ActivityTrail.store.activityText(includingPrompts: false).components(separatedBy: "\n")
            var asked: Int = 0
            for line in lines where line.contains(CoverageTabTrail.asked) {
                asked += 1
            }
            XCTAssertEqual(asked, expected["askedLines"] as? Int, name)
        }
    }
}
