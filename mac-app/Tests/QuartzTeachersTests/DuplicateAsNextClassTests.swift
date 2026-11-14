import XCTest
@testable import QuartzTeachers

/// Section ▸ Add Class… (#897), which replaced Add Next Class: its sheet adds
/// the next class in this unit, the first class of a new unit, or a copy of
/// one of this section's classes. The last two were what only the built-in
/// assistant's window could do.
///
/// Three things are pinned here. The menu's duplicate does what
/// `class-planning.json` → `duplicatingAsTheNextClass` says (the copy is the
/// NEXT class, by file, hidden, one undo entry). The built-in assistant's
/// window behaves exactly as before: the menu's argument is read on `.menu`
/// only, and the window's `duplicate` and "start a new unit" go on as they
/// did (the plan review's amendment 1). And nothing the local model is shown
/// moves.
@MainActor
final class DuplicateAsNextClassTests: XCTestCase {

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        SectionSchedulePrompt.shared.stopAsking()
        SectionMenuActivity.reset()
        try await super.tearDown()
    }

    // MARK: - The contract

    /// Every `duplicatingAsTheNextClass` case, through the real tool on the
    /// menu's surface, with the undo asked for the way a teacher asks.
    func testTheMenusDuplicateMatchesTheContract() async throws {
        let section: [String: Any] = try DuplicateAsNextClassTests.contractSection()
        XCTAssertNotNil(section["rule"] as? String)
        XCTAssertNotNil(section["why"] as? String)
        let wording: [String: String] = try MenuVoiceTests.contractWording()
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let made = try AssistFixture.makeRunner(surface: .menu)
            defer {
                try? FileManager.default.removeItem(at: made.root)
            }
            try DuplicateAsNextClassTests.name(
                made.course, word: testCase["word"] as? String, scheme: testCase["scheme"] as? String
            )
            try DuplicateAsNextClassTests.rememberTimetable(
                try XCTUnwrap(testCase["timetable"] as? [String]), in: made.course
            )
            let source: String = try XCTUnwrap(testCase["source"] as? String)
            var extraLines: [String] = []
            if let lines = testCase["sourceExtraLines"] as? [String] {
                extraLines = lines
            }
            for existing in try XCTUnwrap(testCase["existingClasses"] as? [[String: String]]) {
                let title: String = try XCTUnwrap(existing["title"])
                let isTheSource: Bool = source.hasSuffix("/" + title + ".md")
                try DuplicateAsNextClassTests.writeClass(
                    title, on: try XCTUnwrap(existing["date"]),
                    extraLines: isTheSource ? extraLines : [], in: made.course
                )
            }
            if let others = testCase["otherPages"] as? [[String: String]] {
                for other in others {
                    let url: URL = made.course.directoryURL.appendingPathComponent(try XCTUnwrap(other["path"]))
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    try "---\ntitle: \(url.deletingPathExtension().lastPathComponent)\npublish: true\n---\n\n\(try XCTUnwrap(other["words"]))\n"
                        .write(to: url, atomically: true, encoding: .utf8)
                }
            }
            let before: [String: String] = DuplicateAsNextClassTests.everyPage(in: made.course)
            let depthBefore: Int = made.runner.changeCount

            let planned: AssistToolOutcome = await made.runner.run(call: SectionVerbs.duplicateAsNextClass(
                course: "ICS3U", section: 1, sourcePath: source, planning: true
            ))
            XCTAssertEqual(DuplicateAsNextClassTests.everyPage(in: made.course), before, "\(name): the plan wrote")
            let said: AssistToolOutcome = await made.runner.run(call: SectionVerbs.duplicateAsNextClass(
                course: "ICS3U", section: 1, sourcePath: source, planning: false
            ))
            let entries: Int = try XCTUnwrap(testCase["expectUndoEntries"] as? Int)
            XCTAssertEqual(made.runner.changeCount - depthBefore, entries, "\(name): undo entries — \(said.summary)")

            if let refusedKey = testCase["expectRefused"] as? String {
                XCTAssertFalse(planned.isPlan, "\(name): a refused duplicate was planned")
                XCTAssertTrue(said.summary.hasPrefix("“"), "\(name): \(said.summary)")
                // Checked against the committed sentence once the contract is
                // regenerated; until then, against the Swift one.
                let key: String = String(refusedKey.dropFirst("wording.".count))
                let shownName: String = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
                let expected: String = AssistWording.noPageCalledFromTheMenu(
                    page: shownName, course: "ICS3U", section: "1"
                )
                XCTAssertEqual(key, "noPageCalledFromTheMenu", name)
                XCTAssertEqual(said.summary, expected, name)
                if let committed = wording[key] {
                    XCTAssertTrue(committed.contains("is no longer in"), committed)
                }
                if testCase["expectNothingWritten"] as? Bool == true {
                    XCTAssertEqual(DuplicateAsNextClassTests.everyPage(in: made.course), before, "\(name): something was written")
                }
                continue
            }

            XCTAssertTrue(planned.isPlan, "\(name): \(planned.summary)")
            let newTitle: String = try XCTUnwrap(testCase["expectNewTitle"] as? String)
            let date: String = try XCTUnwrap(testCase["expectDate"] as? String)
            let copyOf: String = try XCTUnwrap(testCase["expectCopyOf"] as? String)
            XCTAssertTrue(
                planned.forTheCard.contains(AssistWording.wouldBeCopiedTo(page: copyOf, as: newTitle, on: date)),
                "\(name): \(planned.forTheCard)"
            )
            XCTAssertEqual(said.summary, AssistWording.duplicatedFromTheMenu(page: copyOf, as: newTitle, on: date), name)
            let copy: String = try XCTUnwrap(
                try? String(contentsOf: AssistFixture.pageURL(of: newTitle, in: made.course), encoding: .utf8),
                "\(name): no copy at \(newTitle)"
            )
            XCTAssertTrue(copy.contains("the words of \(copyOf)"), "\(name): not a copy — \(copy)")
            XCTAssertTrue(copy.contains("title: \(newTitle)"), "\(name): \(copy)")
            XCTAssertTrue(copy.contains("created: \(date)"), "\(name): dated wrongly — \(copy)")
            if let notCopied = testCase["expectNotCopied"] as? String {
                XCTAssertFalse(copy.contains(notCopied), "\(name): the wrong page was copied")
            }
            if testCase["expectHidden"] as? Bool == true {
                XCTAssertEqual(AssistPageVisibility.answer(in: copy, forSection: 1), .hidden, "\(name): \(copy)")
                XCTAssertFalse(copy.contains("publishForSection1"), "\(name): a per-section key came across")
            }
            // Nothing else moved: every page that was there is byte for byte
            // as it was, and exactly one page is new.
            let after: [String: String] = DuplicateAsNextClassTests.everyPage(in: made.course)
            for (path, text) in before {
                XCTAssertEqual(after[path], text, "\(name): \(path) changed")
            }
            XCTAssertEqual(after.count, before.count + 1, "\(name): one page is new")

            // One undo takes it away whole.
            _ = await made.runner.run(call: SectionVerbs.undoLastChange())
            XCTAssertEqual(DuplicateAsNextClassTests.everyPage(in: made.course), before, "\(name): the undo left something")
        }
    }

    // MARK: - The window is unchanged

    /// The menu's argument means nothing outside the menu: the window's runner
    /// given it does what it would do without it, which is to add a blank
    /// next class page. An outside assistant cannot reach the menu's
    /// behaviour by sending a key no schema shows.
    func testTheMenusArgumentIsIgnoredOutsideTheMenu() async throws {
        for surface in [AssistToolRunner.Surface.local, AssistToolRunner.Surface.mcp] {
            let made = try AssistFixture.makeRunner(surface: surface)
            defer {
                try? FileManager.default.removeItem(at: made.root)
            }
            try DuplicateAsNextClassTests.rememberTimetable(["2026-09-08", "2026-09-10", "2026-09-12"], in: made.course)
            try DuplicateAsNextClassTests.writeClass("Unit 1, Day 1", on: "2026-09-08", in: made.course)
            _ = await made.runner.run(call: SectionVerbs.duplicateAsNextClass(
                course: "ICS3U", section: 1, sourcePath: "section1/All Classes/Unit 1, Day 1.md", planning: false
            ))
            let made2: String = (try? String(
                contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 2", in: made.course), encoding: .utf8
            )) ?? ""
            XCTAssertFalse(made2.isEmpty, "\(surface): the plain add did not happen")
            XCTAssertFalse(made2.contains("the words of Unit 1, Day 1"), "\(surface) reached the menu's duplicate")
        }
    }

    /// The window's own duplicate (`duplicate`, by title) still lands on the
    /// source's next day and moves the class that was there, as
    /// `class-planning.json` → `duplication` says, on the menu's surface too:
    /// the new behaviour is reached only through the new argument.
    func testTheTitleNamedDuplicateIsUnchanged() async throws {
        for surface in [AssistToolRunner.Surface.local, AssistToolRunner.Surface.menu] {
            let made = try AssistFixture.makeRunner(surface: surface)
            defer {
                try? FileManager.default.removeItem(at: made.root)
            }
            try DuplicateAsNextClassTests.rememberTimetable(
                ["2026-09-08", "2026-09-10", "2026-09-12", "2026-09-14"], in: made.course
            )
            try DuplicateAsNextClassTests.writeClass("Unit 1, Day 1", on: "2026-09-08", in: made.course)
            try DuplicateAsNextClassTests.writeClass("Unit 1, Day 2", on: "2026-09-10", in: made.course)
            _ = await AssistFixture.run("add_next_class", with: ["duplicate": "Unit 1, Day 1"], on: made.runner)
            let day2: String = (try? String(
                contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 2", in: made.course), encoding: .utf8
            )) ?? ""
            let day3: String = (try? String(
                contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 3", in: made.course), encoding: .utf8
            )) ?? ""
            XCTAssertTrue(day2.contains("the words of Unit 1, Day 1"), "\(surface): \(day2)")
            XCTAssertTrue(day3.contains("the words of Unit 1, Day 2"), "\(surface): \(day3)")
        }
    }

    /// The window's "start a new unit" phrasing sends `unit: "next"`, and an
    /// unfinished unit-word rename does not stop it there: the menu's wait is
    /// the menu's alone.
    func testTheWindowsNewUnitIsNotHeldByTheRenameRecord() async throws {
        let made = try AssistFixture.makeRunner(surface: .local)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try DuplicateAsNextClassTests.layOutAnUnfinishedRename(in: made.course)
        let outcome: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.addNextClassInANewUnit(course: "ICS3U", section: 1)
        )
        XCTAssertNotEqual(outcome.summary, AssistWording.menuUnitWordRenameUnfinished(), outcome.summary)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: AssistFixture.pageURL(of: "Unit 4, Day 1", in: made.course).path),
            outcome.summary
        )
    }

    // MARK: - The menu's new unit

    /// Unit 3 is finished; the menu makes Unit 4, Day 1, hidden, dated for the
    /// next class day, as one undo entry.
    func testANewUnitFromTheMenuIsTheNextUnitsFirstDay() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try DuplicateAsNextClassTests.rememberTimetable(["2026-09-08", "2026-09-10", "2026-09-12"], in: made.course)
        try DuplicateAsNextClassTests.writeClass("Unit 3, Day 1", on: "2026-09-08", in: made.course)
        try DuplicateAsNextClassTests.writeClass("Unit 3, Day 2", on: "2026-09-10", in: made.course)
        let depth: Int = made.runner.changeCount
        let outcome: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.addNextClassInANewUnit(course: "ICS3U", section: 1)
        )
        XCTAssertEqual(outcome.summary, "Added Unit 4, Day 1, dated 2026-09-12.")
        XCTAssertEqual(made.runner.changeCount - depth, 1)
        let page: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 4, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertEqual(AssistPageVisibility.answer(in: page, forSection: 1), .hidden)
        XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(outcome.summary))
    }

    /// The fault that reports success: a rename from "Unit" to "Module" that
    /// stopped part way leaves "Module 3" pages the planner cannot read, so a
    /// new unit would be "Unit 3, Day 1" beside "Module 3, Day 2". The menu
    /// refuses both items, in its own words, and writes nothing.
    func testAnUnfinishedRenameHoldsBothItemsBack() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try DuplicateAsNextClassTests.layOutAnUnfinishedRename(in: made.course)
        let before: [String: String] = DuplicateAsNextClassTests.everyPage(in: made.course)

        let newUnit: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.addNextClassInANewUnit(course: "ICS3U", section: 1)
        )
        XCTAssertEqual(newUnit.summary, AssistWording.menuUnitWordRenameUnfinished())
        let duplicate: AssistToolOutcome = await made.runner.run(call: SectionVerbs.duplicateAsNextClass(
            course: "ICS3U", section: 1, sourcePath: "section1/All Classes/Unit 1, Day 1.md", planning: true
        ))
        XCTAssertEqual(duplicate.summary, AssistWording.menuUnitWordRenameUnfinished())
        XCTAssertEqual(DuplicateAsNextClassTests.everyPage(in: made.course), before)

        // And the sheet greys both ways on the cheap fact, while Add Class…
        // itself, and its next class in this unit, stay as Add Next Class was.
        let facts: SectionVerbs.ClassFacts = SectionVerbs.classFacts(forSection: 1, in: made.course)
        XCTAssertTrue(facts.unitWordRenameUnfinished)
        var situation: SubjectMenuRules.Situation = DuplicateAsNextClassTests.idleSection()
        situation.unitWordRenameUnfinished = facts.unitWordRenameUnfinished
        situation.hasAClassPage = facts.hasAClassPage
        XCTAssertEqual(SubjectMenuRules.addClassWays(situation), [.nextInThisUnit])
        XCTAssertTrue(SubjectMenuRules.enabledItems(situation).contains(.addClass))
    }

    // MARK: - The menu's duplicate, beyond the contract

    /// A copy that cannot be made certainly hidden — a tab used as
    /// indentation in the source's settings, which the build cannot read —
    /// is refused before anything is written: no blank page is left behind
    /// (the plan review's amendment 6), and no undo entry.
    func testACopyThatCannotBeMadeHiddenLeavesNothingBehind() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        // The refusal writes a trail line: into a scratch folder, never the
        // real trail.
        let scratchFolderURL: URL = made.root.appendingPathComponent("trail")
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer {
            ActivityTrail.store = previousStore
        }
        try DuplicateAsNextClassTests.rememberTimetable(["2026-09-08", "2026-09-10"], in: made.course)
        let source: URL = AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course)
        try "---\ntitle: Unit 1, Day 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\ntags:\n\t- lesson\n---\n\nThe lesson.\n"
            .write(to: source, atomically: true, encoding: .utf8)
        let before: [String: String] = DuplicateAsNextClassTests.everyPage(in: made.course)
        let depth: Int = made.runner.changeCount
        let outcome: AssistToolOutcome = await made.runner.run(call: SectionVerbs.duplicateAsNextClass(
            course: "ICS3U", section: 1, sourcePath: "section1/All Classes/Unit 1, Day 1.md", planning: false
        ))
        XCTAssertEqual(outcome.summary, AssistWording.theCopyCouldNotBeMadeHiddenFromTheMenu(page: "Unit 1, Day 1"))
        XCTAssertEqual(DuplicateAsNextClassTests.everyPage(in: made.course), before)
        XCTAssertEqual(made.runner.changeCount, depth)
    }

    /// The sheet's list: every page in this section's class folders, numbered
    /// or not, named by its path in the course; no course-level page.
    func testTheSheetOffersThisSectionsClassPagesByPath() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try DuplicateAsNextClassTests.writeClass("Unit 1, Day 1", on: "2026-09-08", in: made.course)
        try DuplicateAsNextClassTests.writeClass("Field Trip", on: "2026-09-10", in: made.course)
        try "---\ntitle: Unit 1, Day 1\n---\n\nNotes.\n".write(
            to: made.course.directoryURL.appendingPathComponent("Concepts/Unit 1, Day 1.md"),
            atomically: true, encoding: .utf8
        )
        var paths: [String] = []
        for row in SectionVerbSheetModel.sourceRows(course: made.course, sectionNumber: 1) {
            paths.append(row.path)
        }
        XCTAssertEqual(paths, ["section1/All Classes/Unit 1, Day 1.md", "section1/All Classes/Field Trip.md"])
    }

    // MARK: - The facts the menu greys on

    func testTheFactsAreReadFromTheCourse() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        XCTAssertEqual(SectionVerbs.classFacts(forSection: 1, in: made.course), SectionVerbs.ClassFacts())
        try DuplicateAsNextClassTests.writeClass("Unit 1, Day 1", on: "2026-09-08", in: made.course)
        XCTAssertTrue(SectionVerbs.classFacts(forSection: 1, in: made.course).hasAClassPage)
        try AssistFixture.setClubNaming(.meeting, in: made.course)
        XCTAssertTrue(SectionVerbs.classFacts(forSection: 1, in: made.course).classPagesAreNumbered)
    }

    /// Each item is on the trail by where it is in the menus, never by its
    /// raw name (`menuPath`'s `default:` returns the raw value).
    func testTheTrailNamesTheItemByItsPlaceInTheMenus() {
        XCTAssertEqual(SectionVerbs.menuPath(of: .addClass), "Section ▸ Add Class…")
    }

    /// `subjectMenus.addClassSheet`: the ways in the contract's order are
    /// the app's, each names a sentence, and every case offers exactly the
    /// ways it says — so a way added on one side alone fails here.
    func testTheAddClassWaysAreTheContracts() throws {
        let section: [String: Any] = try SubjectMenuRulesTests.section()
        let defaults: [String: Any] = try XCTUnwrap(section["situationDefaults"] as? [String: Any])
        let sheet: [String: Any] = try XCTUnwrap(section["addClassSheet"] as? [String: Any])
        var contractWays: [String] = []
        for way in try XCTUnwrap(sheet["ways"] as? [[String: Any]]) {
            contractWays.append(try XCTUnwrap(way["way"] as? String))
            XCTAssertTrue(try XCTUnwrap(way["wording"] as? String).hasPrefix("wording.menuAddClass"))
        }
        var appWays: [String] = []
        for way in SubjectMenuRules.AddClassWay.allCases {
            appWays.append(way.rawValue)
        }
        XCTAssertEqual(contractWays, appWays)
        let cases: [[String: Any]] = try XCTUnwrap(sheet["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5)
        for testCase in cases {
            let why: String = try XCTUnwrap(testCase["why"] as? String)
            let situation: SubjectMenuRules.Situation = try SubjectMenuRulesTests.situation(
                from: try XCTUnwrap(testCase["situation"] as? [String: Any]), defaults: defaults
            )
            var offered: [String] = []
            for way in SubjectMenuRules.addClassWays(situation) {
                offered.append(way.rawValue)
            }
            XCTAssertEqual(offered, try XCTUnwrap(testCase["ways"] as? [String]), why)
        }
    }

    /// Each way's line in the sheet, in the menu's voice, and a club's first
    /// way says no unit.
    func testEachWayHasItsLine() {
        for way in SubjectMenuRules.AddClassWay.allCases {
            for numbered in [false, true] {
                let line: String = SectionVerbSheet.label(of: way, noun: .meeting, numbered: numbered)
                XCTAssertFalse(line.isEmpty)
                XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(line), line)
            }
        }
        XCTAssertFalse(SectionVerbSheet.label(of: .nextInThisUnit, noun: .meeting, numbered: true).contains("unit"))
    }

    // MARK: - The surface the local model is shown

    /// Nothing the local model or an outside assistant is shown names the
    /// menu's argument, and `add_next_class` still shows only course and
    /// section to the local model. (`AssistContractTests.
    /// testTheCommittedCasesMatchTheToolSurface` pins every byte of both
    /// lists against the committed contract; this names the one key this
    /// piece added, so its failure says which.)
    func testTheMenusArgumentIsOnNoToolSurface() throws {
        var everyTool: [AssistToolDefinition] = AssistToolRunner.mcpTools
        for definition in AssistToolRunner.localTools {
            everyTool.append(definition)
        }
        for definition in everyTool {
            XCTAssertNil(definition.parameters[AssistToolRunner.menuDuplicateFileArgument], definition.name)
            XCTAssertFalse(definition.description.contains(AssistToolRunner.menuDuplicateFileArgument), definition.name)
            for (name, property) in definition.parameters {
                XCTAssertFalse(property.description.contains("FromTheMenu"), "\(definition.name).\(name)")
            }
        }
        var localAddNextClass: Int = 0
        for definition in AssistToolRunner.localTools where definition.name == "add_next_class" {
            var names: [String] = []
            for (name, _) in definition.parameters {
                names.append(name)
            }
            XCTAssertEqual(names.sorted(), ["course", "section"])
            localAddNextClass += 1
        }
        XCTAssertEqual(localAddNextClass, 1, "the local model is shown add_next_class once")
    }

    // MARK: - The menu's voice

    func testTheNewSentencesAreInTheMenusVoice() {
        let sentences: [String] = [
            AssistWording.menuAddClassTitle(course: "ICS3U", section: "1"),
            AssistWording.menuAddClassTitle(course: "ICS3U", section: "1", noun: .meeting),
            AssistWording.menuHowToAddAClass(),
            AssistWording.menuAddClassNextInThisUnit(),
            AssistWording.menuAddClassInANewUnit(),
            AssistWording.menuAddClassAsACopy(),
            AssistWording.menuAddButton,
            AssistWording.menuPickClassToDuplicate(),
            AssistWording.menuPickClassToDuplicate(noun: .meeting),
            AssistWording.menuDuplicateButton,
            AssistWording.duplicatedFromTheMenu(page: "A", as: "B", on: "2026-09-14"),
            AssistWording.theCopyCouldNotBeMadeHiddenFromTheMenu(page: "A"),
            AssistWording.menuTheNextPageIsAlreadyThere(page: "B"),
            AssistWording.menuUnitWordRenameUnfinished(),
            AssistWording.menuUnitWordRenameUnfinished(noun: .meeting),
        ]
        for sentence in sentences {
            XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(sentence), sentence)
            XCTAssertFalse(sentence.contains("Undo that"), sentence)
        }
        XCTAssertTrue(MenuVoiceTests.speaksAsAConversation(
            AssistWording.theCopyCouldNotBeMadeHidden(page: "A", as: "B", backupNamed: nil)
        ), "the conversation's sentence did not need a twin")
    }

    // MARK: - Helpers

    static func contractSection() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/class-planning.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["duplicatingAsTheNextClass"] as? [String: Any])
    }

    static func rememberTimetable(_ dates: [String], in course: Course) throws {
        try SectionTimetableStore.applyRememberTimetable(
            try SectionTimetableStore.planRememberTimetable(
                dates: dates, source: "timetable.xlsx, block H", forSection: 1, in: course
            )
        )
    }

    /// A published class page whose body names it: "the words of <title>".
    static func writeClass(_ title: String, on date: String, extraLines: [String] = [], in course: Course) throws {
        var frontmatter: String = "title: \(title)\npublish: true\ncreated: \(date)T07:00:00.000-0400\n"
        for line in extraLines {
            frontmatter += line + "\n"
        }
        try "---\n\(frontmatter)---\n\nthe words of \(title)\n".write(
            to: AssistFixture.pageURL(of: title, in: course), atomically: true, encoding: .utf8
        )
    }

    static func name(_ course: Course, word: String?, scheme: String?) throws {
        if word == nil && scheme == nil {
            return
        }
        if let word {
            course.configuration.unitWord = word
        }
        if let scheme {
            course.configuration.classPageScheme = ClassPageScheme.reading(scheme)
        }
        try course.configuration.write(to: course.directoryURL.appendingPathComponent("course_config.json"))
    }

    /// Every Markdown file in the course, by path, with its text.
    static func everyPage(in course: Course) -> [String: String] {
        var pages: [String: String] = [:]
        for url in ClassPages.markdownPages(under: course.directoryURL) {
            pages[SectionVerbs.coursePath(ofPageAt: url, in: course)] = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        return pages
    }

    /// A course whose word is still "Unit", with Unit 1 to 3 and a rename to
    /// "Module" recorded as started, and one page already moved to "Module".
    static func layOutAnUnfinishedRename(in course: Course) throws {
        try rememberTimetable(["2026-09-08", "2026-09-10", "2026-09-12", "2026-09-14"], in: course)
        try writeClass("Unit 1, Day 1", on: "2026-09-08", in: course)
        try writeClass("Unit 3, Day 1", on: "2026-09-10", in: course)
        try writeClass("Module 3, Day 2", on: "2026-09-12", in: course)
        try UnitWordRenamer.recordRenameStarting(from: "Unit", to: "Module", courseDirectory: course.directoryURL)
        XCTAssertEqual(UnitWordRenamer.interruptedRenameTarget(in: course), "Module", "the fixture's rename is not unfinished")
    }

    /// A live, idle section row, as `subjectMenus`'s idle case.
    static func idleSection() -> SubjectMenuRules.Situation {
        var situation: SubjectMenuRules.Situation = SubjectMenuRules.Situation()
        situation.hasFolder = true
        situation.obsidianInstalled = true
        situation.row = .section
        situation.previewButtonEnabled = true
        situation.deployButtonEnabled = true
        return situation
    }
}
