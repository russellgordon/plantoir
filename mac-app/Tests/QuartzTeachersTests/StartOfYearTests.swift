import XCTest
@testable import QuartzTeachers

/// "Get Ready for the Start of the Year" and check_section's third group
/// (#96): the contract's cases run through the real MCP pair on a course on
/// disk, the plan code, the undo, the trail, and the app's own act.
@MainActor
final class StartOfYearTests: XCTestCase {

    // MARK: - Stored properties

    private var previousTrail: ProblemReportStore = ActivityTrail.store
    private var trailFolder: URL = URL(fileURLWithPath: "/")

    // MARK: - Set up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
        trailFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("start-of-year-trail-\(UUID().uuidString)")
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
        StartOfYearUndoRegistry.shared.forgetAll()
    }

    override func tearDown() async throws {
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: trailFolder)
        StartOfYearUndoRegistry.shared.forgetAll()
        FakePreview.shared.forget()
        SectionWindowControllers.shared.forgetAll()
    }

    // MARK: - The contract: startOfYear.cases

    /// `shared-rules.json` → `startOfYear.cases`, each laid out as a real
    /// course and run through `plan_prepare_for_start_of_year` then
    /// `prepare_for_start_of_year` with the plan's code, over MCP.
    func testStartOfYearAsTheContractSays() async throws {
        let rules: [String: Any] = try StartOfYearTests.rules("startOfYear")
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 14)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let made = try AssistFixture.makeRunner(surface: .mcp)
            defer { try? FileManager.default.removeItem(at: made.root) }

            if let naming = testCase["naming"] as? [String: String] {
                made.course.configuration.unitWord = naming["word"] ?? "Unit"
                made.course.configuration.classPageScheme = ClassPageScheme.reading(naming["scheme"])
                made.course.configuration.classNoun = ClassNoun.reading(naming["noun"])
                try made.course.configuration.write(
                    to: made.course.directoryURL.appendingPathComponent("course_config.json")
                )
            }
            let pages: [[String: Any]] = try XCTUnwrap(testCase["pages"] as? [[String: Any]])
            let urls: [String: URL] = try StartOfYearTests.layOut(pages, in: made.course)
            var before: [String: String] = [:]
            for (title, url) in urls {
                before[title] = try String(contentsOf: url, encoding: .utf8)
            }

            let planned: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
                "plan_prepare_for_start_of_year", ["course": "ICS3U", "section": 1]
            ))
            let code: String = try XCTUnwrap(
                StartOfYearPlanner.planCode(in: planned.detail), "\(name): the plan carries no code"
            )
            if let fragment = testCase["expectIntroContains"] as? String {
                XCTAssertTrue(planned.detail.contains(fragment), "\(name): \(planned.detail)")
            }
            if let warnings = testCase["expectWarnings"] as? [String] {
                let plan: StartOfYearPlan = try StartOfYearTests.plan(made)
                for warning in warnings {
                    switch warning {
                    case "firstClassIsHidden":
                        XCTAssertTrue(plan.warnings().contains(StartOfYearWording.firstClassIsHidden(
                            first: plan.firstClass.displayTitle, noun: plan.noun.singular
                        )), "\(name): no \(warning) warning")
                    default:
                        XCTFail("\(name): a warning this runner does not know: \(warning)")
                    }
                }
            }

            _ = await made.runner.run(call: StartOfYearTests.call(
                "prepare_for_start_of_year", ["course": "ICS3U", "section": 1, "planCode": code]
            ))

            for title in testCase["expectDraft"] as? [String] ?? [] {
                let url: URL = try XCTUnwrap(urls[title], "\(name): no page \(title)")
                let after: String = try String(contentsOf: url, encoding: .utf8)
                XCTAssertEqual(
                    PageVisibilityReader.answer(in: after, forSection: 1), .hidden,
                    "\(name): “\(title)” should be in draft:\n\(after)"
                )
                XCTAssertEqual(
                    StartOfYearTests.body(after), StartOfYearTests.body(before[title] ?? ""),
                    "\(name): “\(title)” says something different now"
                )
                XCTAssertEqual(
                    StartOfYearTests.dateLines(after), StartOfYearTests.dateLines(before[title] ?? ""),
                    "\(name): “\(title)” was re-dated"
                )
            }
            for title in testCase["expectUntouched"] as? [String] ?? [] {
                let url: URL = try XCTUnwrap(urls[title], "\(name): no page \(title)")
                XCTAssertEqual(
                    try String(contentsOf: url, encoding: .utf8), before[title],
                    "\(name): “\(title)” was written to"
                )
            }
            if testCase["runTwice"] as? Bool == true {
                var once: [String: String] = [:]
                for (title, url) in urls {
                    once[title] = try String(contentsOf: url, encoding: .utf8)
                }
                let again: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
                    "plan_prepare_for_start_of_year", ["course": "ICS3U", "section": 1]
                ))
                let secondCode: String = try XCTUnwrap(StartOfYearPlanner.planCode(in: again.detail))
                let second: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
                    "prepare_for_start_of_year", ["course": "ICS3U", "section": 1, "planCode": secondCode]
                ))
                XCTAssertEqual(
                    second.summary,
                    StartOfYearWording.nothingToDo(first: "Unit 1, Day 1", nouns: "classes"),
                    name
                )
                for (title, url) in urls {
                    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), once[title], "\(name): \(title)")
                }
            }
        }
    }

    // MARK: - The contract: sectionCheck.cases

    /// `shared-rules.json` → `sectionCheck.cases`: the graph's three groups,
    /// and check_section's text naming each page under the right paragraph.
    func testSectionCheckGroupsAsTheContractSays() async throws {
        let rules: [String: Any] = try StartOfYearTests.rules("sectionCheck")
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let made = try AssistFixture.makeRunner(surface: .mcp)
            defer { try? FileManager.default.removeItem(at: made.root) }
            let pages: [[String: Any]] = try XCTUnwrap(testCase["pages"] as? [[String: Any]])
            _ = try StartOfYearTests.layOut(pages, in: made.course)

            let graph: AssistSectionGraph = AssistSectionGraph.read(
                forSection: 1, in: made.course, workspaceURL: made.root
            )
            let excluded: Set<String> = AssistSectionGraph.pagesNeverInTheAudit(of: graph, in: made.course)

            var links: [[String]] = []
            for link in graph.linksIntoHiddenPages() {
                var from: String = link.fromRelativePath
                for page in graph.pages where page.relativePath == link.fromRelativePath {
                    from = page.displayTitle
                }
                links.append([from, link.toTitle])
            }
            XCTAssertEqual(
                StartOfYearTests.sorted(links),
                StartOfYearTests.sorted(testCase["expectLinksIntoHidden"] as? [[String]] ?? []),
                "\(name): links into hidden pages"
            )
            var nowhere: [String] = []
            for page in graph.visiblePagesNothingLinksTo(leavingOut: excluded) {
                nowhere.append(page.displayTitle)
            }
            XCTAssertEqual(
                nowhere.sorted(), (testCase["expectLinkedFromNowhere"] as? [String] ?? []).sorted(),
                "\(name): linked from nowhere"
            )
            var missed: [String] = []
            for page in graph.visiblePagesLinkedButMissed(leavingOut: excluded) {
                missed.append(page.displayTitle)
            }
            XCTAssertEqual(
                missed.sorted(), (testCase["expectLinkedButMissed"] as? [String] ?? []).sorted(),
                "\(name): linked but missed"
            )

            // The text: each group's pages under its own paragraph.
            let checked: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
                "check_section", ["course": "ICS3U", "section": 1]
            ))
            let paragraphs: [String] = checked.detail.components(separatedBy: "\n\n")
            for page in graph.visiblePagesLinkedButMissed(leavingOut: excluded) {
                var found: Bool = false
                for paragraph in paragraphs where paragraph.contains("linked only from classes students cannot see") {
                    found = paragraph.contains("• " + page.relativePath)
                }
                XCTAssertTrue(found, "\(name): check_section did not name \(page.relativePath) as linked but missed")
            }
            for page in graph.visiblePagesNothingLinksTo(leavingOut: excluded) {
                var found: Bool = false
                for paragraph in paragraphs where paragraph.contains("linked from nowhere") {
                    found = paragraph.contains("• " + page.relativePath)
                }
                XCTAssertTrue(found, "\(name): check_section did not name \(page.relativePath) as linked from nowhere")
            }
            if (testCase["expectLinkedButMissed"] as? [String] ?? []).isEmpty {
                XCTAssertFalse(checked.detail.contains("linked only from classes"), "\(name): \(checked.detail)")
            }
        }
    }

    // MARK: - The sentences

    func testTheWordingIsTheContractsWording() throws {
        let rules: [String: Any] = try StartOfYearTests.rules("startOfYear")
        let wording: [String: String] = try XCTUnwrap(rules["wording"] as? [String: String])
        let ours: [String: String] = [
            "menuItem": StartOfYearWording.menuItem,
            "undoMenuItem": StartOfYearWording.undoMenuItem,
            "sheetTitle": StartOfYearWording.sheetTitle(course: "{course}", section: "{section}"),
            "intro": StartOfYearWording.intro(first: "{first}", noun: "{noun}", nouns: "{nouns}"),
            "classesHeading": StartOfYearWording.classesHeading(classes: "{classes}"),
            "pagesHeading": StartOfYearWording.pagesHeading(pages: "{pages}", nouns: "{nouns}"),
            "staysHeading": StartOfYearWording.staysHeading(pages: "{pages}"),
            "alreadyInDraft": StartOfYearWording.alreadyInDraft(classes: "{classes}"),
            "reasonLaterClass": StartOfYearWording.reasonLaterClass(first: "{first}"),
            "reasonFirstUsedIn": StartOfYearWording.reasonFirstUsedIn(page: "{page}"),
            "reasonOnlyHiddenPagesLink": StartOfYearWording.reasonOnlyHiddenPagesLink(page: "{page}"),
            "reasonOnlyAFolderLists": StartOfYearWording.reasonOnlyAFolderLists(page: "{page}"),
            "reasonNothingLinks": StartOfYearWording.reasonNothingLinks,
            "staysFirstClass": StartOfYearWording.staysFirstClass(first: "{first}", pages: "{pages}"),
            "staysKeyLinks": StartOfYearWording.staysKeyLinks(pages: "{pages}"),
            "staysEverythingElse": StartOfYearWording.staysEverythingElse,
            "linksLeftHeading": StartOfYearWording.linksLeftHeading,
            "linksLeftLine": StartOfYearWording.linksLeftLine(page: "{page}", links: "{links}"),
            "publishingFromNowOn": StartOfYearWording.publishingFromNowOn(noun: "{noun}"),
            "alreadyTaught": StartOfYearWording.alreadyTaught(classes: "{classes}"),
            "scheduledDeploy": StartOfYearWording.scheduledDeploy(moment: "{moment}"),
            "firstClassIsHidden": StartOfYearWording.firstClassIsHidden(first: "{first}", noun: "{noun}"),
            "goButton": StartOfYearWording.goButton,
            "nothingToDo": StartOfYearWording.nothingToDo(first: "{first}", nouns: "{nouns}"),
            "done": StartOfYearWording.done(pages: "{pages}"),
            "undoAvailable": StartOfYearWording.undoAvailable(backup: "{backup}"),
            "changedSinceShown": StartOfYearWording.changedSinceShown,
            "backupFailed": StartOfYearWording.backupFailed(course: "{course}"),
            "writeFailed": StartOfYearWording.writeFailed(backup: "{backup}"),
            "noFirstClass": StartOfYearWording.noFirstClass(course: "{course}", section: "{section}", noun: "{noun}"),
            "undoTitle": StartOfYearWording.undoTitle(course: "{course}", section: "{section}"),
            "undoIntro": StartOfYearWording.undoIntro(pages: "{pages}"),
            "undoSkipped": StartOfYearWording.undoSkipped(pages: "{pages}"),
            "undoButton": StartOfYearWording.undoButton,
            "undone": StartOfYearWording.undone(pages: "{pages}"),
            "undoLeftSome": StartOfYearWording.undoLeftSome(pages: "{pages}", backup: "{backup}"),
            "undoButtonAfterward": StartOfYearWording.undoButtonAfterward,
            "undoHasEnded": StartOfYearWording.undoHasEnded,
            "backupHoldsIt": StartOfYearWording.backupHoldsIt(backup: "{backup}"),
            "undoEndsWhenYouQuit": StartOfYearWording.undoEndsWhenYouQuit,
        ]
        XCTAssertEqual(ours.keys.sorted(), wording.keys.sorted(), "The app and the contract name different sentences")
        for (key, sentence) in ours {
            XCTAssertEqual(sentence, wording[key], key)
        }
        let planCode: [String: Any] = try XCTUnwrap(rules["planCode"] as? [String: Any])
        XCTAssertEqual(StartOfYearPlanner.planCodeLine("{code}"), planCode["line"] as? String)
    }

    /// Rule 1: no machinery words in anything this feature says.
    func testNoSentenceNamesTheMachinery() throws {
        let rules: [String: Any] = try StartOfYearTests.rules("startOfYear")
        let wording: [String: String] = try XCTUnwrap(rules["wording"] as? [String: String])
        for (key, sentence) in wording {
            for word in ["toolchain", "script", "docker", "container", "frontmatter", "mcp", "model"] {
                XCTAssertFalse(sentence.lowercased().contains(word), "\(key) says “\(word)”: \(sentence)")
            }
        }
    }

    // MARK: - The plan code over MCP

    func testNoCodeWritesNothingAndHandsBackThePlan() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let before: String = try String(contentsOf: made.day2, encoding: .utf8)

        let outcome: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
            "prepare_for_start_of_year", ["course": "ICS3U", "section": 1]
        ))
        XCTAssertEqual(outcome.summary, AssistWording.startOfYearNeedsItsPlan(course: "ICS3U", section: "1"))
        XCTAssertNotNil(StartOfYearPlanner.planCode(in: outcome.detail), outcome.detail)
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), before)
        XCTAssertTrue(StartOfYearTests.trail().contains("(missingPlanCode)"), StartOfYearTests.trail())
    }

    func testAPageChangedSinceThePlanWritesNothing() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let planned: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
            "plan_prepare_for_start_of_year", ["course": "ICS3U", "section": 1]
        ))
        let code: String = try XCTUnwrap(StartOfYearPlanner.planCode(in: planned.detail))

        // A page appears between the plan and the write.
        try AssistFixture.write(page: "Unit 1, Day 3", publish: "true", date: "2026-09-10",
                                body: "Three.", in: made.course)
        let day3: URL = AssistFixture.pageURL(of: "Unit 1, Day 3", in: made.course)
        let before: String = try String(contentsOf: made.day2, encoding: .utf8)

        let outcome: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
            "prepare_for_start_of_year", ["course": "ICS3U", "section": 1, "planCode": code]
        ))
        XCTAssertEqual(outcome.summary, AssistWording.startOfYearPlanHasChanged(course: "ICS3U", section: "1"))
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), before)
        XCTAssertEqual(PageVisibilityReader.answer(in: try String(contentsOf: day3, encoding: .utf8), forSection: 1), .visible)
        let fresh: String = try XCTUnwrap(StartOfYearPlanner.planCode(in: outcome.detail))
        XCTAssertNotEqual(fresh, code, "The new plan must carry a new code")
    }

    func testTheRightCodeWritesAndUndoPutsEveryFileBack() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let files: [URL] = [made.day1, made.day2, made.watt]
        var before: [URL: String] = [:]
        for url in files {
            before[url] = try String(contentsOf: url, encoding: .utf8)
        }
        let planned: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
            "plan_prepare_for_start_of_year", ["course": "ICS3U", "section": 1]
        ))
        let code: String = try XCTUnwrap(StartOfYearPlanner.planCode(in: planned.detail))
        let done: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
            "prepare_for_start_of_year", ["course": "ICS3U", "section": 1, "planCode": code]
        ))
        XCTAssertEqual(done.summary, StartOfYearWording.done(pages: "2 pages"))
        XCTAssertEqual(PageVisibilityReader.answer(in: try String(contentsOf: made.day2, encoding: .utf8), forSection: 1), .hidden)
        XCTAssertEqual(PageVisibilityReader.answer(in: try String(contentsOf: made.watt, encoding: .utf8), forSection: 1), .hidden)
        XCTAssertTrue(done.detail.contains("_assistant-section1"), "The backup is the assistant's: \(done.detail)")
        XCTAssertTrue(
            StartOfYearTests.trail().contains("made ready for the start of the year from an outside assistant — 1 class and 1 other page"),
            StartOfYearTests.trail()
        )

        _ = await made.runner.run(call: StartOfYearTests.call("undo_last_change"))
        for url in files {
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), before[url], url.lastPathComponent)
        }
        XCTAssertTrue(StartOfYearTests.trail().contains("undid getting ready for the start of the year from an outside assistant"))
    }

    func testAnUndoLeavesAPageEditedSinceAndNamesIt() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let planned: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
            "plan_prepare_for_start_of_year", ["course": "ICS3U", "section": 1]
        ))
        let code: String = try XCTUnwrap(StartOfYearPlanner.planCode(in: planned.detail))
        _ = await made.runner.run(call: StartOfYearTests.call(
            "prepare_for_start_of_year", ["course": "ICS3U", "section": 1, "planCode": code]
        ))
        let edited: String = try String(contentsOf: made.watt, encoding: .utf8) + "\nMore about watts."
        try edited.write(to: made.watt, atomically: true, encoding: .utf8)

        let undone: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call("undo_last_change"))
        XCTAssertTrue(undone.detail.contains("Watt.md"), undone.detail)
        XCTAssertEqual(try String(contentsOf: made.watt, encoding: .utf8), edited)
        XCTAssertTrue(StartOfYearTests.trail().contains("1 left as they are because they had changed since"))
    }

    // MARK: - The planner

    func testAnotherSectionsSettingsAndEveryBodyAndDateAreUntouched() throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "One.", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", body: "See [[Watt]].", in: made.course)
        let watt: URL = made.course.directoryURL.appendingPathComponent("Concepts/Watt.md")
        let text: String = "---\ntitle: Watt\npublishForSection1: true\ncreatedSection1: 2026-09-09T07:00:00.000-0400\n"
            + "publishForSection2: true\ncreatedSection2: 2026-09-10T07:00:00.000-0400\n---\n\nPower."
        try text.write(to: watt, atomically: true, encoding: .utf8)

        let plan: StartOfYearPlan = try StartOfYearTests.plan((made.root, made.course, made.runner, made.siteWork))
        _ = try StartOfYearPlanner.apply(plan, in: made.course)
        let after: String = try String(contentsOf: watt, encoding: .utf8)
        XCTAssertTrue(after.contains("publishForSection2: true\ncreatedSection2: 2026-09-10T07:00:00.000-0400"), after)
        XCTAssertTrue(after.contains("createdSection1: 2026-09-09T07:00:00.000-0400"), after)
        XCTAssertTrue(after.hasSuffix("\n---\n\nPower."), after)
        XCTAssertEqual(PageVisibilityReader.answer(in: after, forSection: 1), .hidden)
    }

    func testNoNumberedClassIsRefused() async throws {
        let made = try AssistFixture.makeRunner(surface: .mcp)
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Field Trip", publish: "true", body: "Out.", in: made.course)
        let outcome: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
            "prepare_for_start_of_year", ["course": "ICS3U", "section": 1, "planCode": "x"]
        ))
        XCTAssertEqual(outcome.summary, StartOfYearWording.noFirstClass(course: "ICS3U", section: "1", noun: "class"))
        XCTAssertTrue(StartOfYearTests.trail().contains("(noFirstClass)"))
    }

    func testTheWarningsAndTheLinksLeftPointingAtHiddenPages() throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-01",
                                body: "See [[Marks]].", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-02",
                                body: "See [[Watt]] and [[Volt]].", in: made.course)
        for concept in ["Watt", "Volt"] {
            try StartOfYearTests.writeCoursePage(concept, links: [], in: made.course)
        }
        try StartOfYearTests.writeCoursePage("Marks", links: ["Watt", "Volt"], in: made.course)

        let moment: Date = Date(timeIntervalSince1970: 1_800_000_000)
        guard case .success(let plan) = StartOfYearPlanner.plan(
            forSection: 1, in: made.course, workspaceURL: made.root,
            today: CalendarDay(year: 2026, month: 9, day: 8)!, scheduledDeploy: moment
        ) else {
            return XCTFail("no plan")
        }
        let warnings: [String] = plan.warnings()
        XCTAssertTrue(warnings.contains(StartOfYearWording.alreadyTaught(classes: "1 class")), "\(warnings)")
        XCTAssertTrue(warnings.contains(StartOfYearWording.scheduledDeploy(
            moment: ScheduledDeploy.dayAndTimeText(moment)
        )))
        XCTAssertEqual(plan.danglingSources.count, 1)
        XCTAssertEqual(plan.danglingSources.first?.page.title, "Marks")
        XCTAssertEqual(plan.danglingSources.first?.hiddenTargets.count, 2)
        XCTAssertTrue(plan.describe().contains(StartOfYearWording.linksLeftLine(page: "Marks", links: "2 links")))
    }

    func testAFlagThatCannotBeReadIsWrittenAndAPageWithNoRoomIsNamed() throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "One.", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", body: "See [[Odd]] and [[Listy]].", in: made.course)
        let concepts: URL = made.course.directoryURL.appendingPathComponent("Concepts")
        // A value on the line below the key: the reader will not guess.
        try "---\ntitle: Odd\npublishForSection1:\n  true\n---\n\nOdd.".write(
            to: concepts.appendingPathComponent("Odd.md"), atomically: true, encoding: .utf8
        )
        // Settings written as a list: no column-0 place for a new key.
        try "---\n- a\n- b\n---\n\nListy.".write(
            to: concepts.appendingPathComponent("Listy.md"), atomically: true, encoding: .utf8
        )
        let plan: StartOfYearPlan = try StartOfYearTests.plan((made.root, made.course, made.runner, made.siteWork))
        var changing: [String] = []
        for change in plan.publishPlan.changes {
            changing.append(change.page.title)
        }
        XCTAssertTrue(changing.contains("Odd"), "\(changing)")
        XCTAssertFalse(changing.contains("Listy"), "\(changing)")
        var declined: [String] = []
        for page in plan.publishPlan.noRoomForAKey {
            declined.append(page.title)
        }
        XCTAssertEqual(declined, ["Listy"])
        XCTAssertTrue(plan.describe().contains("Listy"))
        XCTAssertEqual(plan.changeCount, 2, "Day 2 and Odd; Listy is not counted")
    }

    func testTwoPagesWithOneNameAreEachDecidedAsThemselves() throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "See [[Notes]].", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", body: "Two.", in: made.course)
        // Two files named Notes: the one links reach (Concepts, first in path
        // order) and one in a later folder nothing can reach.
        try StartOfYearTests.writeCoursePage("Notes", links: [], in: made.course)
        let other: URL = made.course.directoryURL.appendingPathComponent("Zeta")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let otherNotes: URL = other.appendingPathComponent("Notes.md")
        try "---\ntitle: Notes\npublishForSection1: true\n---\n\nOther.".write(
            to: otherNotes, atomically: true, encoding: .utf8
        )
        let reached: URL = made.course.directoryURL.appendingPathComponent("Concepts/Notes.md")
        let reachedBefore: String = try String(contentsOf: reached, encoding: .utf8)

        let plan: StartOfYearPlan = try StartOfYearTests.plan((made.root, made.course, made.runner, made.siteWork))
        _ = try StartOfYearPlanner.apply(plan, in: made.course)
        XCTAssertEqual(try String(contentsOf: reached, encoding: .utf8), reachedBefore,
                       "The Notes Day 1 links to must stay as it is")
        XCTAssertEqual(
            PageVisibilityReader.answer(in: try String(contentsOf: otherNotes, encoding: .utf8), forSection: 1),
            .hidden, "The Notes no link can reach goes into draft"
        )
    }

    // MARK: - check_section's third group, beside the planner

    /// The audit is not the planner's own predicate (plan review H2): a
    /// planner that skipped step 2 leaves pages the audit then flags.
    func testTheAuditFlagsWhatALeakyRuleWouldLeave() throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "One.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 1", publish: "false", body: "See [[Ohm's Law]].", in: made.course)
        try StartOfYearTests.writeCoursePage("Ohm's Law", links: [], in: made.course)
        try StartOfYearTests.writeCoursePage("How Marks Work", links: ["Ohm's Law"], in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "See [[How Marks Work]].", in: made.course)

        let graph: AssistSectionGraph = AssistSectionGraph.read(forSection: 1, in: made.course, workspaceURL: made.root)
        var missed: [String] = []
        for page in graph.visiblePagesLinkedButMissed(leavingOut: []) {
            missed.append(page.title)
        }
        XCTAssertEqual(missed, ["Ohm's Law"])
    }

    // MARK: - The app's act

    func testGoMakesTheTeachersBackupStopsAndStartsThePreviewAndHoldsTheUndo() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        FakePreview.shared.register(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1, running: true)

        let model: StartOfYearSheetModel = StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady,
            today: { return CalendarDay(year: 2026, month: 9, day: 8)! }
        )
        model.load()
        await model.goAhead()
        guard case .done(let done) = model.stage else {
            return XCTFail("not done: \(model.stage)")
        }
        XCTAssertTrue(done.backupFileName.hasPrefix("ICS3U_backup_"))
        XCTAssertFalse(done.backupFileName.contains("_assistant"), "The teacher pressed the button: \(done.backupFileName)")
        XCTAssertEqual(FakePreview.shared.events, ["stop-begins", "stop-ends", "start"])
        XCTAssertEqual(PageVisibilityReader.answer(in: try String(contentsOf: made.day2, encoding: .utf8), forSection: 1), .hidden)
        XCTAssertTrue(StartOfYearTests.trail().contains("from the app"), StartOfYearTests.trail())
        XCTAssertTrue(StartOfYearTests.trail().contains("preview rebuilt"))

        // The same folder spelled another way finds the same undo.
        let otherSpelling: String = FolderIdentity.canonicalPath(made.root.path)
        XCTAssertNotNil(StartOfYearUndoRegistry.shared.entry(
            folderPath: otherSpelling, courseCode: "ics3u", sectionNumber: 1
        ))
    }

    func testNoPreviewRunningIsNeitherStoppedNorStarted() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        FakePreview.shared.register(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1, running: false)
        let model: StartOfYearSheetModel = StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady
        )
        model.load()
        await model.goAhead()
        XCTAssertEqual(FakePreview.shared.events, [])
    }

    func testAFailedBackupChangesNothing() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let before: String = try String(contentsOf: made.day2, encoding: .utf8)
        let model: StartOfYearSheetModel = StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady,
            backUp: { _, _ in throw CocoaError(.fileWriteNoPermission) }
        )
        model.load()
        await model.goAhead()
        guard case .problem(let sentence) = model.stage else {
            return XCTFail("not refused: \(model.stage)")
        }
        XCTAssertEqual(sentence, StartOfYearWording.backupFailed(course: "ICS3U"))
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), before)
        XCTAssertTrue(StartOfYearTests.trail().contains("(backupFailed)"))
    }

    func testAChangeAfterThePlanWasShownWritesNothingAndShowsTheNewPlan() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let model: StartOfYearSheetModel = StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady
        )
        model.load()
        try AssistFixture.write(page: "Unit 1, Day 3", publish: "true", body: "Three.", in: made.course)
        let before: String = try String(contentsOf: made.day2, encoding: .utf8)
        await model.goAhead()
        guard case .ready(let fresh) = model.stage else {
            return XCTFail("not re-planned: \(model.stage)")
        }
        XCTAssertEqual(model.notice, StartOfYearWording.changedSinceShown)
        XCTAssertEqual(fresh.classChangeCount, 2)
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), before)
        XCTAssertTrue(StartOfYearTests.trail().contains("(changedSinceShown)"))
    }

    func testTheUndoSheetPutsEverythingBack() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let before: String = try String(contentsOf: made.day2, encoding: .utf8)
        let go: StartOfYearSheetModel = StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady
        )
        go.load()
        await go.goAhead()

        let back: StartOfYearSheetModel = StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .undo
        )
        back.load()
        guard case .undoReady(_, let putBack, let skipped) = back.stage else {
            return XCTFail("no undo offered: \(back.stage)")
        }
        XCTAssertEqual(skipped.count, 0)
        XCTAssertGreaterThanOrEqual(putBack.count, 2)
        await back.undo()
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), before)
        XCTAssertNil(StartOfYearUndoRegistry.shared.entry(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1))
        XCTAssertTrue(StartOfYearTests.trail().contains("undid getting ready for the start of the year from the app"))
    }

    func testADeployEndsTheUndo() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let go: StartOfYearSheetModel = StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady
        )
        go.load()
        await go.goAhead()
        XCTAssertNotNil(StartOfYearUndoRegistry.shared.entry(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1))
        CourseActivity.beginPublish(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1)
        CourseActivity.endPublish(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertNil(StartOfYearUndoRegistry.shared.entry(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1))
    }

    func testAVisibilityChangeSinceEndsTheUndo() async throws {
        let made = try StartOfYearTests.aSmallYear()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let go: StartOfYearSheetModel = StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady
        )
        go.load()
        await go.goAhead()
        // Day 2 published again, by hand.
        let hidden: String = try String(contentsOf: made.day2, encoding: .utf8)
        try hidden.replacingOccurrences(of: "publish: false", with: "publish: true")
            .write(to: made.day2, atomically: true, encoding: .utf8)

        let back: StartOfYearSheetModel = StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .undo
        )
        back.load()
        guard case .problem(let sentence) = back.stage else {
            return XCTFail("undo still offered: \(back.stage)")
        }
        XCTAssertTrue(sentence.hasPrefix(StartOfYearWording.undoHasEnded), sentence)
        XCTAssertNil(StartOfYearUndoRegistry.shared.entry(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1))
    }

    func testAScheduledDeployWhoseMomentHasPassedEndsTheUndo() {
        let change: AssistChange = AssistChange(
            whatHappened: "x", courseCode: "ICS3U", sectionNumber: 1, rebuildsThePreview: true, files: []
        )
        let moment: Date = Date(timeIntervalSince1970: 1_000)
        StartOfYearUndoRegistry.shared.record(
            StartOfYearUndoRegistry.Entry(change: change, backupFileName: "b.zip", visibilityAfter: "", scheduledDeploy: moment),
            folderPath: "/tmp/somewhere", courseCode: "ICS3U", sectionNumber: 1
        )
        XCTAssertNotNil(StartOfYearUndoRegistry.shared.entry(
            folderPath: "/tmp/somewhere", courseCode: "ICS3U", sectionNumber: 1, now: Date(timeIntervalSince1970: 999)
        ))
        XCTAssertNil(StartOfYearUndoRegistry.shared.entry(
            folderPath: "/tmp/somewhere", courseCode: "ICS3U", sectionNumber: 1, now: Date(timeIntervalSince1970: 1_001)
        ))
    }

    // MARK: - Fixtures

    /// Unit 1, Day 1 (visible), Unit 1, Day 2 (visible, links Watt), and the
    /// course-level concept Watt (visible).
    static func aSmallYear() throws -> (root: URL, course: Course, runner: AssistToolRunner,
                                        day1: URL, day2: URL, watt: URL) {
        let made = try AssistFixture.makeRunner(surface: .mcp)
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08",
                                body: "One.", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-09",
                                body: "See [[Watt]].", in: made.course)
        try writeCoursePage("Watt", links: [], in: made.course)
        return (
            made.root, made.course, made.runner,
            AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course),
            AssistFixture.pageURL(of: "Unit 1, Day 2", in: made.course),
            made.course.directoryURL.appendingPathComponent("Concepts/Watt.md")
        )
    }

    static func writeCoursePage(_ title: String, links: [String], in course: Course) throws {
        var body: String = "About \(title)."
        for target in links {
            body += "\n\nSee [[\(target)]]."
        }
        let folder: URL = course.directoryURL.appendingPathComponent("Concepts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\ntitle: \(title)\npublishForSection1: true\ncreatedSection1: 2026-09-08T07:00:00.000-0400\n---\n\n\(body)"
            .write(to: folder.appendingPathComponent(title + ".md"), atomically: true, encoding: .utf8)
    }

    static func plan(_ made: AssistFixture.Made) throws -> StartOfYearPlan {
        switch StartOfYearPlanner.plan(
            forSection: 1, in: made.course, workspaceURL: made.root,
            today: CalendarDay(year: 2026, month: 9, day: 8)!
        ) {
        case .failure(let problem):
            throw problem
        case .success(let plan):
            return plan
        }
    }

    /// One contract case's pages, laid out where their kind belongs —
    /// `startOfYear.howToRunACase`.
    static func layOut(_ pages: [[String: Any]], in course: Course) throws -> [String: URL] {
        let fileManager: FileManager = FileManager.default
        var urls: [String: URL] = [:]
        for page in pages {
            let title: String = try XCTUnwrap(page["title"] as? String)
            let kind: String = page["kind"] as? String ?? "page"
            let visible: Bool = page["visible"] as? Bool ?? true
            let links: [String] = page["links"] as? [String] ?? []
            let date: String = page["date"] as? String ?? "2026-09-08"
            let undated: Bool = page["undated"] as? Bool ?? false
            var body: String = "About \(title)."
            for target in links {
                body += "\n\nSee [[\(target)]]."
            }
            let flag: String = visible ? "true" : "false"
            let url: URL
            var frontmatter: [String] = ["title: \(title)"]
            switch kind {
            case "class":
                url = ClassPages.folderURL(forSection: 1, in: course).appendingPathComponent(title + ".md")
                frontmatter.append("publish: \(flag)")
                if page["strayPublishForSection"] as? Bool == true {
                    frontmatter.append("publishForSection1: true")
                }
                if !undated {
                    frontmatter.append("created: \(date)T07:00:00.000-0400")
                }
            case "keyLinks":
                url = course.sectionDirectoryURL(forSection: 1).appendingPathComponent(title + ".md")
                frontmatter.append("publish: \(flag)")
            case "sectionFrontPage":
                url = SectionIndexPointer.indexURL(forSection: 1, in: course)
                frontmatter.append("publish: \(flag)")
            case "folderIndex":
                url = course.directoryURL.appendingPathComponent(title).appendingPathComponent("index.md")
                frontmatter.append("publishForSection1: \(flag)")
            case "curriculum":
                url = course.directoryURL.appendingPathComponent("Curriculum").appendingPathComponent(title + ".md")
                frontmatter.append("publishForSection1: \(flag)")
            default:
                url = course.directoryURL.appendingPathComponent("Concepts").appendingPathComponent(title + ".md")
                frontmatter.append("publishForSection1: \(flag)")
                if !undated {
                    frontmatter.append("createdSection1: \(date)T07:00:00.000-0400")
                }
            }
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text: String = "---\n" + frontmatter.joined(separator: "\n") + "\n---\n\n" + body
            try text.write(to: url, atomically: true, encoding: .utf8)
            urls[title] = url
        }
        return urls
    }

    static func call(_ name: String, _ arguments: [String: Any] = [:]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(name: name, arguments: String(decoding: encoded, as: UTF8.self))
        )
    }

    static func rules(_ key: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[key] as? [String: Any], "shared-rules.json has no \(key)")
    }

    static func trail() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    static func body(_ text: String) -> String {
        guard text.hasPrefix("---\n"), let closing = text.dropFirst(4).range(of: "\n---\n") else {
            return text
        }
        return String(text.dropFirst(4)[closing.upperBound...])
    }

    static func dateLines(_ text: String) -> [String] {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") where line.hasPrefix("created") {
            lines.append(line)
        }
        return lines
    }

    static func sorted(_ pairs: [[String]]) -> [String] {
        var joined: [String] = []
        for pair in pairs {
            joined.append(pair.joined(separator: " → "))
        }
        joined.sort()
        return joined
    }
}
