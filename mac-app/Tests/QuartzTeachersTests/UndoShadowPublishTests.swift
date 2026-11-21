import XCTest
@testable import QuartzTeachers

/// The one action U1 records: publishing and hiding pages
/// (`AssistToolRunner.carryOut`), written to the app-wide list in SHADOW
/// beside today's history (#899).
///
/// What matters most is what must NOT change: the teacher's action, its
/// result, its sentences, the built-in assistant's own undo. A list that
/// cannot be written must leave all of that exactly as it is (plan 4.9).
@MainActor
final class UndoShadowPublishTests: XCTestCase {

    // MARK: - Stored properties

    var roots: [URL] = []

    var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
    }

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        ActivityTrail.store = previousTrail
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
        roots = []
    }

    // MARK: - Helpers

    /// A fixture course with two unpublished classes, its trail and its
    /// list in folders of its own. `listFolder` nil: a list that cannot be
    /// written (a FILE where its folder would go).
    func makeCourse(surface: AssistToolRunner.Surface, writableList: Bool) throws -> (made: AssistFixture.Made, list: URL) {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(surface: surface)
        roots.append(made.root)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "false", body: "Two.", in: made.course)
        let list: URL = made.root.appendingPathComponent("list-\(UUID().uuidString)", isDirectory: true)
        if writableList {
            UndoJournalLocation.folderOverride = list
        } else {
            try Data("a file, not a folder".utf8).write(to: list)
            UndoJournalLocation.folderOverride = list.appendingPathComponent("undo", isDirectory: true)
        }
        return (made: made, list: list)
    }

    func pageTexts(in course: Course) throws -> [String] {
        var texts: [String] = []
        for title in ["Unit 1, Day 1", "Unit 1, Day 2"] {
            let url: URL = ClassPages.folderURL(forSection: 1, in: course).appendingPathComponent(title + ".md")
            texts.append(try String(contentsOf: url, encoding: .utf8))
        }
        return texts
    }

    func trailLines() -> [String] {
        var lines: [String] = []
        for line in ActivityTrail.store.activityText(includingPrompts: true).components(separatedBy: "\n") {
            if line.contains(ActivityTrail.Event.undoCouldNotRecordAStep.rawValue) || line.contains("the undo list") {
                lines.append(line)
            }
        }
        return lines
    }

    // MARK: - Tests

    /// A publish leaves one step on the list, applied, with a line op for the
    /// page and the front page as a recompute: and the window's own history
    /// gains its entry exactly as before.
    func testAPublishIsRecordedInShadow() async throws {
        let course: (made: AssistFixture.Made, list: URL) = try makeCourse(surface: .local, writableList: true)
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": ["Unit 1, Day 1"]], on: course.made.runner
        )
        XCTAssertTrue(outcome.detail.contains("Done:"), outcome.detail)
        XCTAssertEqual(course.made.runner.changeCount, 1)

        let fold: UndoFold = try UndoJournal(folderURL: course.list).read()
        XCTAssertEqual(fold.records.count, 1)
        let record: UndoStepRecord = try XCTUnwrap(fold.records[1])
        XCTAssertEqual(record.phase, .done)
        XCTAssertEqual(record.step.action?.key, "publishPages")
        XCTAssertEqual(record.step.course, "ICS3U")
        XCTAssertEqual(record.step.section, 1)
        let madeBy: String = record.step.madeBy ?? ""
        XCTAssertTrue(madeBy.hasPrefix("builtInAssistant:"), madeBy)
        var kinds: [String] = []
        for op in record.step.ops {
            kinds.append(op.kind)
        }
        XCTAssertEqual(kinds, ["editLine", "recompute"])
        XCTAssertEqual(record.step.ops[0].key, "publish")
        XCTAssertEqual(trailLines(), [])
    }

    /// The menu and an outside assistant are named as themselves.
    func testWhoMadeItIsTheSurface() async throws {
        let menu: (made: AssistFixture.Made, list: URL) = try makeCourse(surface: .menu, writableList: true)
        _ = await AssistFixture.run("publish_pages", with: ["pages": ["Unit 1, Day 1"]], on: menu.made.runner)
        XCTAssertEqual(try UndoJournal(folderURL: menu.list).read().records[1]?.step.madeBy, "menu")

        let outside: (made: AssistFixture.Made, list: URL) = try makeCourse(surface: .mcp, writableList: true)
        _ = await AssistFixture.run("publish_pages", with: ["pages": ["Unit 1, Day 1"]], on: outside.made.runner)
        let madeBy: String = try XCTUnwrap(try UndoJournal(folderURL: outside.list).read().records[1]?.step.madeBy ?? nil)
        XCTAssertTrue(madeBy.hasPrefix("outsideAssistant::"), madeBy)
    }

    /// THE guard of plan 4.9: with a list that cannot be written, the same
    /// publish gives the same answer, the same pages and the same history as
    /// with one that can, and leaves one trail line saying the change went
    /// ahead. Run for both directions, publish then hide.
    func testAListThatCannotBeWrittenChangesNothingAboutTheAction() async throws {
        let working: (made: AssistFixture.Made, list: URL) = try makeCourse(surface: .local, writableList: true)
        let publishedWell: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": ["Unit 1, Day 1", "Unit 1, Day 2"]], on: working.made.runner
        )
        let hiddenWell: AssistToolOutcome = await AssistFixture.run(
            "unpublish_pages", with: ["pages": ["Unit 1, Day 2"]], on: working.made.runner
        )
        let wellTexts: [String] = try pageTexts(in: working.made.course)
        let wellChanges: Int = working.made.runner.changeCount
        XCTAssertEqual(trailLines(), [])

        let broken: (made: AssistFixture.Made, list: URL) = try makeCourse(surface: .local, writableList: false)
        let publishedBroken: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": ["Unit 1, Day 1", "Unit 1, Day 2"]], on: broken.made.runner
        )
        let hiddenBroken: AssistToolOutcome = await AssistFixture.run(
            "unpublish_pages", with: ["pages": ["Unit 1, Day 2"]], on: broken.made.runner
        )

        XCTAssertEqual(publishedBroken.summary, publishedWell.summary)
        XCTAssertEqual(publishedBroken.detail, publishedWell.detail)
        XCTAssertEqual(hiddenBroken.summary, hiddenWell.summary)
        XCTAssertEqual(hiddenBroken.detail, hiddenWell.detail)
        XCTAssertEqual(try pageTexts(in: broken.made.course), wellTexts)
        XCTAssertEqual(broken.made.runner.changeCount, wellChanges)

        let lines: [String] = trailLines()
        XCTAssertEqual(lines.count, 2, lines.joined(separator: "\n"))
        for line in lines {
            XCTAssertTrue(line.contains("The change went ahead"), line)
        }

        // And the window's own undo still takes the hide back.
        let undone: AssistToolOutcome = await AssistFixture.run("undo_last_change", with: [:], on: broken.made.runner)
        XCTAssertEqual(broken.made.runner.changeCount, wellChanges - 1, undone.detail)
    }

    /// The built-in assistant's undo neither reads nor writes the list in U1:
    /// "undo that" leaves the journal exactly as the publish left it.
    ///
    /// **Flips at U7.** Ruling 15, as given finally, makes the window's "undo
    /// that" the app's Edit > Undo, so U7 turns this into the opposite test:
    /// the window's undo undoes the list's head, whoever made it.
    func testTheWindowsUndoDoesNotTouchTheList() async throws {
        let course: (made: AssistFixture.Made, list: URL) = try makeCourse(surface: .local, writableList: true)
        _ = await AssistFixture.run("publish_pages", with: ["pages": ["Unit 1, Day 1"]], on: course.made.runner)
        let segment: URL = UndoJournal(folderURL: course.list).segmentURL(number: 1)
        let before: Data = try Data(contentsOf: segment)
        _ = await AssistFixture.run("undo_last_change", with: [:], on: course.made.runner)
        XCTAssertEqual(try Data(contentsOf: segment), before)
        XCTAssertEqual(course.made.runner.changeCount, 0)
    }

    /// The switch is off: nothing is offered from the list.
    func testTheSwitchIsOff() {
        XCTAssertFalse(UndoSwitch.undoJournalIsLive)
        XCTAssertEqual(UndoSwitch.currentMode, .shadow)
    }

    /// The trail lines name codes and counts, never a page.
    func testTheTrailLinesSayWhatHappened() {
        XCTAssertEqual(
            UndoTrail.couldNotRecordLine(action: "publishPages", course: "ICS3U", section: 1, mode: .shadow, why: "the list was busy"),
            "ICS3U/1 · the undo list could not record publishPages: the list was busy. The change went ahead (the list is not in use yet)."
        )
        XCTAssertEqual(
            UndoTrail.rolledBackLine(course: "ICS3U", section: 1, phase: .begin, files: 2),
            "ICS3U/1 · the undo list put back 2 files left part way by a change that stopped"
        )
        XCTAssertEqual(
            UndoTrail.interruptedLine(course: "ICS3U", section: 1, phase: .begin, putBack: 2, inTheWay: 1),
            "ICS3U/1 · the undo list put back 2 files left part way by a change that stopped, found 1 file changed by hand since, and cleared the list"
        )
    }

    /// U3c's two lines are exactly the examples the contract's
    /// `activityTrail.mustRecord` rows give for them (read, never retyped).
    func testTheKeptOriginalAndLeftNewestLinesAreTheContractsExamples() throws {
        let rules: [String: Any] = try UndoContractReplay.contract("shared-rules.json")
        let trail: [String: Any] = rules["activityTrail"] as? [String: Any] ?? [:]
        var examples: [String: String] = [:]
        for row in trail["mustRecord"] as? [[String: Any]] ?? [] {
            if let event = row["event"] as? String, let line = row["line"] as? String {
                examples[event] = line
            }
        }
        XCTAssertEqual(
            UndoTrail.couldNotPutBackLine(
                course: "ICS3U", section: 1, phase: .begin, leftPartWay: 1,
                keptOriginals: [".A.md.plantoir-undo-4-apply-orig"]
            ),
            examples[ActivityTrail.Event.undoCouldNotPutBack.rawValue]
        )
        XCTAssertEqual(
            UndoTrail.leftNewestLine(
                course: "ICS3U", section: 1, isUndo: true,
                refusal: .fileIsInUse(path: "courses/ICS3U/Section 1/Classes/A.md")
            ),
            examples[ActivityTrail.Event.undoRefusedForAChangeLeftPartWay.rawValue]
        )
        XCTAssertEqual(
            UndoTrail.keptAnOriginalLine(
                course: "ICS3U", section: 1, phase: .begin,
                keptOriginals: [".A.md.plantoir-undo-4-apply-orig"]
            ),
            examples[ActivityTrail.Event.undoKeptAnOriginal.rawValue]
        )
        XCTAssertEqual(
            UndoTrail.keptWhatItReplacedLine(
                course: "ICS3U", section: 1, isUndo: true,
                keptOriginals: [".A.md.plantoir-undo-4-undo-orig"]
            ),
            examples[ActivityTrail.Event.undoKeptWhatItReplaced.rawValue]
        )
    }

    /// A kept original whose bytes are exactly what the list recorded is
    /// said as kept because the list no longer holds a copy of it, never as
    /// differing from what the list recorded: the reason the contract's row
    /// carries (the first review of U3c, LOW 2). After a Redo, the line says
    /// nothing is withheld or cleared, since nothing is (the second review,
    /// LOW 1, and Russell's ruling of 2026-11-20, night).
    func testTheKeptLinesSayWhatIsTrueInEachCase() throws {
        let rules: [String: Any] = try UndoContractReplay.contract("shared-rules.json")
        let trail: [String: Any] = rules["activityTrail"] as? [String: Any] ?? [:]
        var carries: [String: String] = [:]
        for row in trail["mustRecord"] as? [[String: Any]] ?? [] {
            if let event = row["event"] as? String, let said = row["carries"] as? String {
                carries[event] = said
            }
        }
        let recorded: String = UndoTrail.keptAnOriginalLine(
            course: "ICS3U", section: 1, phase: .begin,
            keptOriginals: [".A.md.plantoir-undo-4-apply-orig"],
            noLongerInTheList: [".A.md.plantoir-undo-4-apply-orig"]
        )
        XCTAssertFalse(recorded.contains("differs"), recorded)
        let reason: String = "because the list no longer holds a copy of it"
        XCTAssertTrue(recorded.hasSuffix(", " + reason + "."), recorded)
        XCTAssertTrue(carries[ActivityTrail.Event.undoKeptAnOriginal.rawValue]?.contains(reason) == true)
        let afterARedo: String = UndoTrail.keptWhatItReplacedLine(
            course: "ICS3U", section: 1, isUndo: false,
            keptOriginals: [".A.md.plantoir-undo-4-redo-orig"]
        )
        XCTAssertTrue(afterARedo.hasPrefix("ICS3U/1 · Redo put back “A.md”"), afterARedo)
        // Nothing is withheld or cleared at the move (Russell's ruling of
        // 2026-11-20, night; the second review of U3c, LOW 1), so the line
        // never says so; a kept original the list would not take is named
        // as what the page holds now (the second review's MEDIUM).
        XCTAssertFalse(afterARedo.contains("not offered"), afterARedo)
        XCTAssertFalse(afterARedo.contains("cleared"), afterARedo)
        XCTAssertTrue(afterARedo.contains("the next Undo or Redo of this change uses it."), afterARedo)
        let holdingNow: String = UndoTrail.keptWhatItReplacedLine(
            course: "ICS3U", section: 1, isUndo: true,
            keptOriginals: [], keptOfWhatItHoldsNow: [".A.md.plantoir-undo-4-apply-orig"]
        )
        XCTAssertTrue(
            holdingNow.hasSuffix(" What “A.md” holds now is kept beside it as the hidden file “.A.md.plantoir-undo-4-apply-orig”."),
            holdingNow
        )
        XCTAssertTrue(holdingNow.hasPrefix("ICS3U/1 · Undo put back “A.md”"), holdingNow)
    }
}
