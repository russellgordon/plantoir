import XCTest
@testable import QuartzTeachers

/// Section ▸ Roll Over to a New Year… (#897 piece B): the rollover the
/// built-in assistant's window asks about in words, run from the Section
/// menu through the same tool call, its website question asked in the sheet.
///
/// What is pinned here, beside the window's own rollover tests
/// (`RolloverWebsiteTests`, which stay on `.local` and unchanged):
/// - the website rule, from the contract (`subjectMenus.rollOverSheet`);
/// - the sheet cannot be sent with the question unanswered, and sends only
///   "new" or "same";
/// - from the menu the whole rollover is ONE undo entry, in both branches,
///   with a copy of the course saved first in both (the plan review's
///   amendments 10 and 11), while the window keeps its two entries;
/// - every marker goes with "new" and stays with "same";
/// - the menu's sentences where the window's speak as a conversation or call
///   a folder a website (amendments 12 and 13).
@MainActor
final class RollOverFromTheMenuTests: XCTestCase {

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        SectionMenuActivity.reset()
        try await super.tearDown()
    }

    // MARK: - The contract

    /// Every case of `subjectMenus.rollOverSheet`: which website line the
    /// sheet draws, and what the call carries.
    func testTheWebsiteRuleIsTheContracts() throws {
        let section: [String: Any] = try SubjectMenuRulesTests.section()
        let sheet: [String: Any] = try XCTUnwrap(section["rollOverSheet"] as? [String: Any])
        let websites: [String: Any] = try XCTUnwrap(sheet["websites"] as? [String: Any])
        var appWebsites: Set<String> = []
        for website in RollOverFromTheMenu.Website.allCases {
            appWebsites.insert(website.rawValue)
        }
        XCTAssertEqual(Set(websites.keys), appWebsites)
        let cases: [[String: Any]] = try XCTUnwrap(sheet["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        for contractCase in cases {
            let why: String = try XCTUnwrap(contractCase["why"] as? String)
            let facts: [String: Bool] = try XCTUnwrap(contractCase["facts"] as? [String: Bool], why)
            let website: RollOverFromTheMenu.Website = RollOverFromTheMenu.website(
                sectionIsPinned: try XCTUnwrap(facts["sectionIsPinned"], why),
                hasAHostedDestination: try XCTUnwrap(facts["hasAHostedDestination"], why)
            )
            XCTAssertEqual(website.rawValue, contractCase["website"] as? String, why)
            var answer: RollOverFromTheMenu.Answer? = nil
            if let spelled = contractCase["answer"] as? String {
                answer = try XCTUnwrap(RollOverFromTheMenu.Answer(rawValue: spelled), why)
            }
            let sent: String? = RollOverFromTheMenu.websiteSent(website, answer: answer)
            XCTAssertEqual(sent, contractCase["websiteSent"] as? String, why)
        }
    }

    /// The item is live exactly where Re-date Classes… is, in every case of
    /// the menu's contract.
    func testTheItemIsLiveWhereReDateIs() throws {
        let section: [String: Any] = try SubjectMenuRulesTests.section()
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        var checked: Int = 0
        for contractCase in cases {
            let enabled: [String] = try XCTUnwrap(contractCase["enabled"] as? [String])
            XCTAssertEqual(
                enabled.contains("rollOverToANewYear"), enabled.contains("reDateClasses"),
                contractCase["why"] as? String ?? ""
            )
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 20)
        XCTAssertEqual(SectionVerbs.menuPath(of: .rollOverToANewYear), "Section ▸ Roll Over to a New Year…")
    }

    // MARK: - The sheet

    /// Asked and unanswered: Continue cannot be pressed. Answered: the call
    /// carries exactly the answer, as a rollover.
    func testTheSheetSendsNothingUntilTheQuestionIsAnswered() throws {
        let made = try AssistFixture.makeRunner(hasDeployedBefore: true, surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .rollOver, course: made.course, sectionNumber: 1, title: "", item: .rollOverToANewYear
        )
        model.rollOver = RollOverFromTheMenu.choice(
            forSection: 1, in: made.course, today: try XCTUnwrap(CalendarDay(text: "2026-09-08"))
        )
        XCTAssertEqual(model.rollOver.website, .asked)
        XCTAssertNil(model.rollOver.answer, "the question guesses neither answer")
        XCTAssertFalse(model.defaultButtonIsEnabled)
        for answer in RollOverFromTheMenu.Answer.allCases {
            model.rollOver.answer = answer
            XCTAssertTrue(model.defaultButtonIsEnabled)
            let website: String = try XCTUnwrap(model.rollOver.websiteSent)
            XCTAssertEqual(website, answer.rawValue)
            let call: AssistToolCall = SectionVerbs.rollOver(course: "ICS3U", section: 1, website: website, planning: false)
            let arguments: [String: Any] = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(call.function.arguments.utf8)) as? [String: Any]
            )
            XCTAssertEqual(call.function.name, "re_date_classes")
            XCTAssertEqual(arguments["rollover"] as? String, "yes")
            XCTAssertEqual(arguments["website"] as? String, answer.rawValue)
        }
    }

    /// No marker on a web host: no question, and "new". Only a folder: no
    /// question, and "same" (amendment 12: never "had not been deployed").
    func testNoWebsiteMeansNoQuestion() throws {
        let made = try AssistFixture.makeRunner(hasDeployedBefore: false, surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-08"))
        var choice: RollOverFromTheMenu.Choice = RollOverFromTheMenu.choice(forSection: 1, in: made.course, today: today)
        XCTAssertEqual(choice.website, .notDeployedYet)
        XCTAssertEqual(choice.websiteSent, "new")

        let folderCourse: Course = try RollOverFromTheMenuTests.deployingToAFolder(made.course)
        choice = RollOverFromTheMenu.choice(forSection: 1, in: folderCourse, today: today)
        XCTAssertEqual(choice.website, .deploysToAFolder)
        XCTAssertEqual(choice.websiteSent, "same")

        // The legacy marker alone pins the section: asked, never cut loose unasked.
        try RollOverFromTheMenuTests.writeLegacyMarker(in: folderCourse)
        XCTAssertTrue(DeployCommand.sectionIsPinned(forSection: 1, in: folderCourse))
        choice = RollOverFromTheMenu.choice(forSection: 1, in: folderCourse, today: today)
        XCTAssertEqual(choice.website, .asked)
        XCTAssertNil(choice.websiteSent)
    }

    /// The dates line, and the line when they have all passed.
    func testTheDatesLineSaysWhenTheDatesAreOld() throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: .menu, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let early: RollOverFromTheMenu.Choice = RollOverFromTheMenu.choice(
            forSection: 1, in: made.course, today: try XCTUnwrap(CalendarDay(text: "2026-09-08"))
        )
        XCTAssertEqual(early.datesLine, AssistWording.menuRollOverDates(first: "2026-09-08", last: "2026-09-10"))
        XCTAssertFalse(early.datesAreOld)
        XCTAssertTrue(RollOverFromTheMenu.datesAreOld(
            last: try XCTUnwrap(CalendarDay(text: "2026-09-10")), today: try XCTUnwrap(CalendarDay(text: "2026-09-11"))
        ))
    }

    // MARK: - One change, from the menu

    /// "new" from the menu, with a Netlify, a Cloudflare and a legacy marker
    /// and a deploy scheduled from this folder: every marker moved aside, the
    /// schedule turned off, a copy saved first, and ONE undo entry, which
    /// one Undo Last Change takes back whole (the dates and the markers).
    /// Red before #897 piece B: two entries, and one undo left the dates.
    func testANewWebsiteFromTheMenuIsOneChange() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: .menu, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let copies: CopiesSaved = RollOverFromTheMenuTests.countCopies(of: made)
        let markers: [URL] = try RollOverFromTheMenuTests.writeEveryMarker(in: made.course)
        let plistURL: URL = ScheduledDeploy.plistURL(courseCode: made.course.code, sectionNumber: 1, inWorkingFolder: made.root)
        try RolloverWebsiteTests.writeAgent(
            courseCode: made.course.code, sectionNumber: 1, workingFolder: made.root, at: plistURL
        )
        let page: URL = made.course.directoryURL.appendingPathComponent("section1/All Classes/Unit 1, Day 1.md")
        let pageBefore: String = try String(contentsOf: page, encoding: .utf8)

        let changesBefore: Int = made.runner.changeCount
        let outcome: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "new", planning: false)
        )
        XCTAssertEqual(made.runner.changeCount, changesBefore + 1, "one rollover, one undo entry: \(outcome.summary)")
        XCTAssertEqual(copies.count, 1)
        for marker in markers {
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), marker.path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path), "the schedule must really be off")
        XCTAssertNotEqual(try String(contentsOf: page, encoding: .utf8), pageBefore, "the page was not re-dated")
        XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(outcome.summary), outcome.summary)

        _ = await made.runner.run(call: SectionVerbs.undoLastChange())
        XCTAssertEqual(made.runner.changeCount, changesBefore)
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), pageBefore, "one undo takes the dates back too")
        for marker in markers {
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "one undo puts \(marker.lastPathComponent) back")
        }
    }

    /// "same" from the menu: every marker stays where it is.
    func testKeepingTheWebsiteFromTheMenuLeavesEveryMarker() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: .menu, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        _ = RollOverFromTheMenuTests.countCopies(of: made)
        let markers: [URL] = try RollOverFromTheMenuTests.writeEveryMarker(in: made.course)
        let outcome: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "same", planning: false)
        )
        XCTAssertTrue(outcome.summary.contains(AssistWording.rolloverKeptTheSameWebsite), outcome.summary)
        for marker in markers {
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), marker.path)
        }
    }

    /// Dates already right (the teacher ran Re-date Classes… first): a copy
    /// is still saved first, and the record and the website are one entry
    /// (amendments 10 and 11). Red before: no copy, and two entries.
    func testARolloverWhoseDatesAreAlreadyRightSavesACopyAndIsOneChange() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: .menu, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let copies: CopiesSaved = RollOverFromTheMenuTests.countCopies(of: made)
        _ = await made.runner.run(call: SectionVerbs.reDateClasses(course: "ICS3U", section: 1, planning: false))
        XCTAssertEqual(copies.count, 1)
        try RollOverFromTheMenuTests.writePublishedRecord(in: made.course)

        let changesBefore: Int = made.runner.changeCount
        let outcome: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "new", planning: false)
        )
        XCTAssertTrue(
            outcome.summary.contains(AssistWording.everyPageIsAlreadyOnItsDay(course: "ICS3U", section: 1)), outcome.summary
        )
        XCTAssertEqual(copies.count, 2, "a copy of the course is saved before this change too")
        XCTAssertEqual(made.runner.changeCount, changesBefore + 1)
        XCTAssertEqual(PublishedPagesRecord.places(courseDirectory: made.course.directoryURL, section: 1), [])

        _ = await made.runner.run(call: SectionVerbs.undoLastChange())
        XCTAssertEqual(PublishedPagesRecord.places(courseDirectory: made.course.directoryURL, section: 1), ["Concepts/Worksheet"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: made.course.directoryURL.appendingPathComponent(".netlify_sites/section1.json").path
        ))
    }

    /// The window's rollover keeps its two entries (amendment 1): the menu's
    /// fold is the menu's.
    func testTheWindowsRolloverIsUnchanged() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let changesBefore: Int = made.runner.changeCount
        _ = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "new", planning: false)
        )
        XCTAssertEqual(made.runner.changeCount, changesBefore + 2)
    }

    // MARK: - The menu's sentences

    /// A section that deploys to a folder keeps it, and is told so in a
    /// sentence that does not call a folder a website (amendment 12).
    func testAFolderSectionIsToldItsFolderIsUnchanged() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: false, surface: .menu, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        _ = RollOverFromTheMenuTests.countCopies(of: made)
        _ = try RollOverFromTheMenuTests.deployingToAFolder(made.course)
        let plan: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "same", planning: true)
        )
        XCTAssertTrue(plan.isPlan, plan.summary)
        XCTAssertTrue(plan.forTheCard.contains(AssistWording.menuRollOverDeploysToAFolder), plan.forTheCard)
        XCTAssertTrue(plan.forTheCard.contains(AssistWording.menuRollOverPlanSetsTheRecordAside), plan.forTheCard)
        let outcome: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "same", planning: false)
        )
        XCTAssertTrue(outcome.summary.contains(AssistWording.rolloverDeploysToAFolderFromTheMenu), outcome.summary)
        XCTAssertFalse(outcome.summary.contains(AssistWording.rolloverKeptTheSameWebsite), outcome.summary)
    }

    /// A marker that cannot be read: the section is still pinned, said in the
    /// menu's voice (amendment 13).
    func testAMarkerThatCannotBeMovedIsSaidInTheMenusVoice() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: .menu, for: self)
        let marker: URL = made.course.directoryURL.appendingPathComponent(".netlify_sites/section1.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: marker.path)
            try? FileManager.default.removeItem(at: made.root)
        }
        _ = RollOverFromTheMenuTests.countCopies(of: made)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: marker.path)
        XCTAssertTrue(DeployCommand.sectionIsPinned(forSection: 1, in: made.course))
        let outcome: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "new", planning: false)
        )
        XCTAssertTrue(outcome.summary.contains(
            AssistWording.rolloverCouldNotStartANewWebsiteFromTheMenu(stillPinned: ".netlify_sites/section1.json")
        ), outcome.summary)
        XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(outcome.summary), outcome.summary)
    }

    /// The menu's plan for "same" says what it does to the website, which
    /// the window's card for that answer does not (amendment 14).
    func testThePlanForTheSameWebsiteSaysSo() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: .menu, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let plan: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "same", planning: true)
        )
        XCTAssertTrue(plan.isPlan, plan.summary)
        XCTAssertTrue(plan.forTheCard.contains(AssistWording.menuRollOverPlanKeepsTheWebsite), plan.forTheCard)
        XCTAssertTrue(plan.forTheCard.contains(AssistWording.menuRollOverPlanSetsTheRecordAside), plan.forTheCard)
        XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(plan.forTheCard), plan.forTheCard)
    }

    // MARK: - Functions

    /// How many copies the runner saved before a change.
    final class CopiesSaved {
        var count: Int = 0
    }

    /// Counts the copies the runner saves before a change, without zipping.
    static func countCopies(of made: AssistFixture.Made) -> CopiesSaved {
        let copies: CopiesSaved = CopiesSaved()
        made.runner.backUpACourse = { (course: Course, coursesDirectoryURL: URL, maker: BackupMaker) in
            copies.count += 1
            let saved: URL = coursesDirectoryURL.appendingPathComponent("_backups")
                .appendingPathComponent("\(course.code)-\(UUID().uuidString).zip")
            try FileManager.default.createDirectory(
                at: saved.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data().write(to: saved)
            return saved
        }
        return copies
    }

    /// A Netlify, a Cloudflare and a legacy marker for Section 1.
    static func writeEveryMarker(in course: Course) throws -> [URL] {
        var written: [URL] = []
        for folder in [".netlify_sites", ".cloudflare_sites"] {
            let marker: URL = course.directoryURL.appendingPathComponent(folder).appendingPathComponent("section1.json")
            try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "{\"site\":\"last-year\"}".write(to: marker, atomically: true, encoding: .utf8)
            written.append(marker)
        }
        written.append(try writeLegacyMarker(in: course))
        return written
    }

    @discardableResult
    static func writeLegacyMarker(in course: Course) throws -> URL {
        let marker: URL = DeployCommand.legacyMarkerURL(forSection: 1, in: course)
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{\"site_id\":\"last-year\"}".write(to: marker, atomically: true, encoding: .utf8)
        return marker
    }

    static func writePublishedRecord(in course: Course) throws {
        let folder: URL = PublishedPagesRecord.folderURL(courseDirectory: course.directoryURL, section: 1)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "{\"places\": [\"Concepts/Worksheet\"]}".write(
            to: folder.appendingPathComponent("20260601T120000Z-netlify.json"), atomically: true, encoding: .utf8
        )
    }

    /// The course, saved as deploying only to a folder, and read back.
    static func deployingToAFolder(_ course: Course) throws -> Course {
        let configURL: URL = course.directoryURL.appendingPathComponent("course_config.json")
        var values: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: configURL)) as? [String: Any]
        )
        values["deploy_target"] = "local_folder"
        values["deploy_folder_path"] = course.directoryURL.deletingLastPathComponent().path + "/deployed"
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted]).write(to: configURL)
        return Course(code: course.code, directoryURL: course.directoryURL, configuration: try CourseConfiguration(contentsOf: configURL))
    }
}
