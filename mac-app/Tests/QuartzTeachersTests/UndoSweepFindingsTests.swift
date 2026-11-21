import XCTest
@testable import QuartzTeachers

/// The U3 sweep's findings 2 to 5, fixed in U4a (#899):
///
/// 2. The `undo could not record a step` line said "The change went ahead"
///    before a write that could still refuse: it is now written from what
///    happened.
/// 3. With the switch off, a daily action whose page is a link is refused,
///    not written over the link (`undo.rule.shadow` now says so).
/// 4. Duplicate Class's copy refused, its room then refused too: the reply
///    said a blank page was waiting on that day.
/// 5. Sentences that were in Swift alone are `undo.wording`'s.
@MainActor
final class UndoSweepFindingsTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = FileManager.default.temporaryDirectory

    var previousTrail: ProblemReportStore = ActivityTrail.store

    var previousHook: ((String, String, Int?, UndoUnrecordedChange, String) -> Void)?

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
        previousHook = UndoTrailHook.couldNotRecordLine
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-sweep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        UndoTrailHook.couldNotRecordLine = previousHook
        JournaledStep.modeOverride = nil
        UndoJournalLocation.folderOverride = nil
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Findings 2 and 3

    /// With the switch off, a step whose page is a link cannot be named in a
    /// step; it is refused before anything changes, the link is left as it
    /// is, and the trail line says nothing was changed. MUST FAIL before
    /// the fix: the line said "The change went ahead" before the refusal.
    func testAShadowStepOnALinkIsRefusedAndTheLineSaysNothingWasChanged() throws {
        JournaledStep.modeOverride = .shadow
        let course: URL = root.appendingPathComponent("courses/ICS3U", isDirectory: true)
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        let real: URL = root.appendingPathComponent("elsewhere.md")
        try Data("---\npublish: false\n---\n".utf8).write(to: real)
        let link: URL = course.appendingPathComponent("Unit 1, Day 1.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        var said: [UndoUnrecordedChange] = []
        UndoTrailHook.couldNotRecordLine = { _, _, _, change, _ in
            said.append(change)
        }
        let step: JournaledStep = JournaledStep(
            courseCode: "ICS3U", courseDirectory: course, section: 1, maker: UndoStepMaker.sheet("publishPages")
        )
        step.write("---\npublish: true\n---\n", to: link)

        XCTAssertThrowsError(try step.make())

        XCTAssertEqual(said, [.nothingWasChanged])
        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8), "---\npublish: false\n---\n")
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: link.path), real.path, "the link is left as it is"
        )
        XCTAssertTrue(
            UndoTrail.couldNotRecordLine(action: "publishPages", course: "ICS3U", section: 1, change: .nothingWasChanged, why: "x")
                .hasSuffix(" Nothing was changed.")
        )
    }

    /// A step the list cannot take that is still made in shadow says it
    /// went ahead, once it has.
    func testAShadowStepTheListCannotTakeSaysItWentAheadOnceItHas() throws {
        JournaledStep.modeOverride = .shadow
        let broken: URL = root.appendingPathComponent("list-is-a-file")
        try Data("not a folder".utf8).write(to: broken)
        UndoJournalLocation.folderOverride = broken.appendingPathComponent("undo", isDirectory: true)
        let course: URL = root.appendingPathComponent("courses/ICS3U", isDirectory: true)
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        let page: URL = course.appendingPathComponent("a.md")
        try Data("one\n".utf8).write(to: page)
        let moved: URL = course.appendingPathComponent("b.md")
        var said: [UndoUnrecordedChange] = []
        UndoTrailHook.couldNotRecordLine = { _, _, _, change, _ in
            said.append(change)
        }
        let step: JournaledStep = JournaledStep(
            courseCode: "ICS3U", courseDirectory: course, section: 1, maker: UndoStepMaker.sheet("publishPages")
        )
        step.move(page, to: moved)

        try step.make()

        XCTAssertEqual(said, [.wentAhead])
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "one\n")
    }

    // MARK: - Finding 4

    /// A copy that cannot be made certainly hidden, and a room that then
    /// cannot be made either (live, the list cannot be written): the reply
    /// says nothing was changed, never that a blank page is waiting. MUST
    /// FAIL before the fix (`try?`): it said the blank page was waiting.
    func testACopyRefusedWhoseRoomCannotBeMadeSaysNothingWasChanged() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(surface: .local)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        try "---\ntitle: Unit 1, Day 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\ntags:\n\t- lesson\n---\n\nThe lesson.\n"
            .write(to: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), atomically: true, encoding: .utf8)
        try DuplicateAsNextClassTests.rememberTimetable(["2026-09-08", "2026-09-10", "2026-09-14"], in: made.course)
        let before: [String: Data] = UndoActionStepsTests.pages(of: made.course)
        JournaledStep.modeOverride = .live
        let broken: URL = root.appendingPathComponent("list-is-a-file")
        try Data("not a folder".utf8).write(to: broken)
        UndoJournalLocation.folderOverride = broken.appendingPathComponent("undo", isDirectory: true)

        let outcome: AssistToolOutcome = await AssistFixture.run(
            "add_next_class", with: ["duplicate": "Unit 1, Day 1"], on: made.runner
        )

        XCTAssertTrue(outcome.summary.hasPrefix("Nothing was changed"), outcome.summary)
        XCTAssertFalse(outcome.summary.contains("is waiting on that day"), outcome.summary)
        XCTAssertEqual(UndoActionStepsTests.pages(of: made.course), before)
    }

    // MARK: - Finding 5

    /// Each sentence is the contract's, placeholders and all. MUST FAIL with
    /// any one of them changed in Swift.
    func testTheUndoLinesSentencesAreTheContracts() throws {
        let rules: [String: Any] = try UndoContractReplay.contract("shared-rules.json")
        let undo: [String: Any] = try XCTUnwrap(rules["undo"] as? [String: Any])
        var wording: [String: String] = [:]
        for (key, value) in try XCTUnwrap(undo["wording"] as? [String: Any]) where key != "note" {
            wording[key] = value as? String
        }
        let ours: [String: String] = [
            "keptBesideIt": JournaledStepError.keptSentence(place: "{place}", kept: "{kept}"),
            "classDatesRememberedTitle": SectionTimetableStore.Problem.rememberedTitle("{code}", 0)
                .replacingOccurrences(of: "Section 0", with: "Section {number}"),
            "classDatesKeptLead": SectionTimetableStore.Problem.keptLead,
            "classDatesKeptBesideIt": SectionTimetableStore.Problem.keptSentence(place: "{place}", kept: "{kept}"),
            "rolloverNothingElseWasChanged": AssistToolRunner.RolloverStoppedAfterARecordMoved.nothingElseWasChanged("{said}"),
            "rolloverRecordStillMoved": AssistToolRunner.RolloverStoppedAfterARecordMoved.recordStillMoved(legacy: "{legacy}", place: "{place}"),
            "rolloverLeftoverStillMoved": AssistToolRunner.RolloverStoppedAfterARecordMoved.leftoverStillMoved(legacy: "{legacy}", place: "{place}"),
            "rolloverUnreadableStillMoved": AssistToolRunner.RolloverStoppedAfterARecordMoved.unreadableStillMoved(current: "{current}", aside: "{aside}"),
        ]
        XCTAssertEqual(ours, wording)
    }
}
