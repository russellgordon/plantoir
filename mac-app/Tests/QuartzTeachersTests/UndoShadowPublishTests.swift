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
    }
}
