import XCTest
@testable import QuartzTeachers

/// The Section menu's voice (#457 batch B). The assistant's functions run
/// from the menu bar say what happened in sentences that are not a
/// conversation: nobody said "undo that", and there is no "me" to ask again.
/// Every sentence the eight tools can say in the first person, or about
/// asking, on a path the menu reaches, has a `…FromTheMenu` twin chosen by
/// the runner's surface — and the conversation's own sentences, and every
/// byte the model reads, are unchanged.
@MainActor
final class MenuVoiceTests: XCTestCase {

    // MARK: - Stored properties

    /// What the menu's voice may never say: the first person, an invitation
    /// to ask, or the conversation's own way out. From the plan review's
    /// finding 7, plus "Undo that" and "Restore Section" (the plan's own).
    static let conversational: NSRegularExpression = try! NSRegularExpression(
        pattern: "\\bI\\b|I’|I'|\\bme\\b|\\bmy\\b|[Ss]ay “|[Aa]sk (me|again)|“Undo that”|Restore Section"
    )

    /// Every sentence twinned for the menu, by its contract key: the
    /// conversation's, then the menu's. The test below holds the pair to the
    /// rule — the first speaks as a conversation, the second never does — so
    /// a twin that drifts back into the first person fails here.
    static let twins: [(conversation: String, menu: String)] = [
        ("undid", "undidFromTheMenu"),
        ("undidPartly", "undidPartlyFromTheMenu"),
        ("couldNotUndo", "couldNotUndoFromTheMenu"),
        ("undoIsStillAvailable", "undoIsStillAvailableFromTheMenu"),
        ("nothingToUndo", "nothingToUndoFromTheMenu"),
        ("changedWhileSavingACopy", "changedWhileSavingACopyFromTheMenu"),
        ("pagesWhoseSettingsCannotBeAddedTo", "pagesWhoseSettingsCannotBeAddedToFromTheMenu"),
        ("pagesWhoseSettingsCannotBeAddedToNamingSeveral", "pagesWhoseSettingsCannotBeAddedToFromTheMenuNamingSeveral"),
        ("pageWhoseNewDateCouldNotBeSet", "pageWhoseNewDateCouldNotBeSetFromTheMenu"),
        ("pagesWhoseNewDatesCouldNotBeSet", "pagesWhoseNewDatesCouldNotBeSetFromTheMenu"),
        ("noPageCalled", "noPageCalledFromTheMenu"),
        ("noPagesCalled", "noPagesCalledFromTheMenu"),
        ("courseIsBeingCopied", "courseIsBeingCopiedFromTheMenu"),
        ("restoreSectionPutsItBack", "restoreFromBackupPutsItBack"),
        ("makingRoomCannotBeUndone", "makingRoomCannotBeUndoneFromTheMenu"),
        ("whatPublishingMeans", "publishingAndDeployingExplained"),
    ]

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        SectionSchedulePrompt.shared.stopAsking()
        SectionMenuActivity.reset()
        try await super.tearDown()
    }

    // MARK: - The enumeration

    /// Each conversational sentence speaks as a conversation (so it really
    /// needed a twin), and each twin does not.
    func testEveryTwinIsInTheMenusVoice() throws {
        let wording: [String: String] = try MenuVoiceTests.contractWording()
        for pair in MenuVoiceTests.twins {
            let original: String = try XCTUnwrap(wording[pair.conversation], pair.conversation)
            let twin: String = try XCTUnwrap(wording[pair.menu], pair.menu)
            if pair.conversation != "whatPublishingMeans" {
                XCTAssertTrue(MenuVoiceTests.speaksAsAConversation(original), "\(pair.conversation) did not need a twin")
            }
            XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(twin), "\(pair.menu): “\(twin)”")
        }
        // `whatPublishingMeans` was twinned for "the teacher", in an alert
        // the teacher reads (#457's plan review, note 14).
        XCTAssertTrue(try XCTUnwrap(wording["whatPublishingMeans"]).contains("the teacher"))
        XCTAssertFalse(try XCTUnwrap(wording["publishingAndDeployingExplained"]).contains("the teacher"))
    }

    /// Every sentence the menu's sheets show is in the menu's voice — the
    /// titles, the intros, the buttons, and #475's question.
    func testEveryMenuSentenceIsInTheMenusVoice() throws {
        let wording: [String: String] = try MenuVoiceTests.contractWording()
        var checked: Int = 0
        for (key, sentence) in wording
        where key.hasPrefix("menu") || key.hasSuffix("FromTheMenu") || key.contains("FromTheMenu")
            || key.hasPrefix("laterClasses") || key.hasPrefix("publishingAndDeploying") {
            XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(sentence), "\(key): “\(sentence)”")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 40)
    }

    // MARK: - The runner chooses by surface

    /// Undo Last Change, on each surface: the menu's twin from the menu, the
    /// conversation's sentence in a conversation.
    func testUndoSpeaksInTheVoiceOfWhoAsked() async throws {
        for surface in [AssistToolRunner.Surface.menu, AssistToolRunner.Surface.local] {
            let made = try AssistFixture.makeRunner(surface: surface)
            defer {
                try? FileManager.default.removeItem(at: made.root)
            }
            let nothing: AssistToolOutcome = await made.runner.run(call: SectionVerbs.undoLastChange())
            try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
            _ = await made.runner.run(call: SectionVerbs.publishPages(
                course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: false
            ))
            let undone: AssistToolOutcome = await made.runner.run(call: SectionVerbs.undoLastChange())
            if surface == .menu {
                XCTAssertEqual(nothing.summary, AssistWording.nothingToUndoFromTheMenu)
                XCTAssertTrue(undone.summary.hasPrefix("Undone."), undone.summary)
                XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(nothing.summary))
                XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(undone.summary), undone.summary)
            } else {
                XCTAssertEqual(nothing.summary, AssistWording.nothingToUndo)
                XCTAssertTrue(undone.summary.contains("asked me to undo"), undone.summary)
            }
        }
    }

    /// An undo that can put nothing back, because the page was edited since:
    /// the menu's refusal and its pointer to the menu item, never "ask me".
    func testAnUndoThatPutsNothingBackSaysSoInTheMenusVoice() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        _ = await made.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: false
        ))
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "Edited since.", in: made.course)
        let refused: AssistToolOutcome = await made.runner.run(call: SectionVerbs.undoLastChange())
        XCTAssertTrue(refused.summary.contains(AssistWording.undoIsStillAvailableFromTheMenu), refused.summary)
        XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(refused.summary), refused.summary)
    }

    /// A page the list offered and the press did not find, and a day with no
    /// class: the menu's sentences, naming the page as the teacher ticked it.
    func testRefusalsAreInTheMenusVoice() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        let gone: AssistToolOutcome = await made.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 9, Day 9"], planning: false
        ))
        XCTAssertEqual(
            gone.summary,
            AssistWording.noPageCalledFromTheMenu(page: "Unit 9, Day 9", course: "ICS3U", section: "1")
        )
        let noClass: AssistToolOutcome = await made.runner.run(call: SectionVerbs.publishClass(
            course: "ICS3U", section: 1, on: try XCTUnwrap(CalendarDay(text: "2026-09-20")), planning: false
        ))
        XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(noClass.summary), noClass.summary)
        XCTAssertTrue(noClass.summary.contains("Section ▸ Publish Pages…"), noClass.summary)
        // And no request for class dates was left for the assistant's window
        // to find (#457's plan review, blocker 1): the menu never offers.
        XCTAssertNil(SectionSchedulePrompt.shared.offer, "the menu left an offer only the assistant's window shows")
        XCTAssertNil(SectionSchedulePrompt.shared.request)
    }

    /// A dateless section's Add Next Class from the menu refuses without
    /// leaving an offer behind, where the assistant's call does leave one.
    func testTheMenuNeverLeavesARequestForClassDates() async throws {
        let menu = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: menu.root)
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "One.", in: menu.course)
        _ = await menu.runner.run(call: SectionVerbs.addNextClass(course: "ICS3U", section: 1))
        XCTAssertNil(SectionSchedulePrompt.shared.offer)

        let local = try AssistFixture.makeRunner(surface: .local)
        defer {
            try? FileManager.default.removeItem(at: local.root)
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", body: "One.", in: local.course)
        _ = await local.runner.run(call: SectionVerbs.addNextClass(course: "ICS3U", section: 1))
        XCTAssertNotNil(SectionSchedulePrompt.shared.offer, "the guard passes vacuously: the assistant no longer offers either")
    }

    /// Make Room for Classes…'s plan, when other classes move, points at the
    /// menu item rather than at "Undo that".
    func testMakeRoomsPlanPointsAtTheMenu() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try MenuVoiceTests.layOutAUnitWithDates(in: made.course)
        let plan: AssistToolOutcome = await made.runner.run(call: SectionVerbs.makeRoom(
            course: "ICS3U", section: 1, unit: 1, atDay: 2, howMany: 1, planning: true
        ))
        XCTAssertTrue(plan.isPlan, plan.summary)
        XCTAssertTrue(plan.forTheCard.contains(AssistWording.makingRoomCannotBeUndoneFromTheMenu()), plan.forTheCard)
        XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(plan.forTheCard), plan.forTheCard)
        // The model's copy is the conversation's, byte for byte.
        XCTAssertTrue(plan.detail.contains(AssistWording.makingRoomCannotBeUndone()), plan.detail)
    }

    /// The declined-page sentence, both ways.
    func testTheDeclinedPageSentenceHasTheMenusVoice() {
        let menu: String = AssistPublishPlan.sayingPagesWithNoRoomForAKey(named: ["Unit 2, Day 4"], fromTheMenu: true)
        let conversation: String = AssistPublishPlan.sayingPagesWithNoRoomForAKey(named: ["Unit 2, Day 4"])
        XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(menu), menu)
        XCTAssertTrue(MenuVoiceTests.speaksAsAConversation(conversation), conversation)
        let redated: String = AssistPublishPlan.sayingPagesWhoseNewDateCouldNotBeSet(named: ["A", "B"], fromTheMenu: true)
        XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(redated), redated)
    }

    // MARK: - Helpers

    static func speaksAsAConversation(_ sentence: String) -> Bool {
        let whole: NSRange = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
        return conversational.firstMatch(in: sentence, range: whole) != nil
    }

    /// Unit 1, Days 1 to 3, and class dates from 2026-09-08 on.
    static func layOutAUnitWithDates(in course: Course) throws {
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "One.", in: course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "false", date: "2026-09-09", body: "Two.", in: course)
        try AssistFixture.write(page: "Unit 1, Day 3", publish: "false", date: "2026-09-10", body: "Three.", in: course)
        var dates: [String] = []
        for day in 8...30 {
            dates.append(String(format: "2026-09-%02d", day))
        }
        let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: dates, source: "typed in by hand", forSection: 1, in: course,
            today: try XCTUnwrap(CalendarDay(text: "2026-09-08"))
        )
        try SectionTimetableStore.applyRememberTimetable(plan)
    }

    static func contractWording() throws -> [String: String] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/assist-wording.json")
        let object: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(object["wording"] as? [String: String])
    }
}
