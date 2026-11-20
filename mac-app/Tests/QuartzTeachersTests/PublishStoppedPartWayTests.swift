import XCTest
@testable import QuartzTeachers

/// A publish or a hide (marking pages, not a deploy) whose pages cannot all
/// be written. Since U3 of #899 the pages are ONE step through the door,
/// staged and swapped in together or not at all
/// (`undo.rule.stagedThenSwapped`), so a failure writes nothing and the
/// teacher is told "Nothing was changed: …" with the reason — never
/// `AssistWording.publishStoppedPartWay` ("Only part of … was changed"),
/// which #412 said while the write went page by page and which is false of
/// a disk where nothing was written (the first review of U3a, MEDIUM 1). No
/// pointer at a copy is added either: there is nothing to put back.
///
/// The write is made to fail by taking write permission off the section's
/// class folder after the course is laid out (restored in teardown).
@MainActor
final class PublishStoppedPartWayTests: XCTestCase {

    // MARK: - Stored properties

    var lockedFolder: URL?

    var root: URL?

    var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
    }

    override func tearDown() async throws {
        if let lockedFolder {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedFolder.path)
        }
        lockedFolder = nil
        ActivityTrail.store = previousTrail
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    // MARK: - Helpers

    func makeLockedCourse(surface: AssistToolRunner.Surface) throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(surface: surface)
        root = made.root
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "false", body: "Two.", in: made.course)
        let folder: URL = ClassPages.folderURL(forSection: 1, in: made.course)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        lockedFolder = folder
        return made
    }

    /// Both pages, as they were laid out.
    func pagesAsLaidOut(in course: Course) throws -> [String] {
        var texts: [String] = []
        for title in ["Unit 1, Day 1", "Unit 1, Day 2"] {
            texts.append(try String(contentsOf: AssistFixture.pageURL(of: title, in: course), encoding: .utf8))
        }
        return texts
    }

    let prefixForPages: String = AssistWording.publishStoppedPartWay(what: "the pages you named", problem: "")

    // MARK: - Tests

    /// A page list none of whose pages could be written is said as nothing
    /// changed, with the reason, and with no pointer at a copy. MUST FAIL on
    /// U3a's first round, which said `publishStoppedPartWay` with the
    /// Restore Section pointer.
    func testAPageListThatCannotBeWrittenIsSaidAsNothingChanged() async throws {
        let made: AssistFixture.Made = try makeLockedCourse(surface: .local)
        let before: [String] = try pagesAsLaidOut(in: made.course)
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": ["Unit 1, Day 1", "Unit 1, Day 2"]], on: made.runner
        )
        XCTAssertTrue(outcome.detail.hasPrefix("Nothing was changed: "), outcome.detail)
        XCTAssertFalse(outcome.detail.hasPrefix(prefixForPages), outcome.detail)
        XCTAssertFalse(outcome.detail.contains("Restore Section"), outcome.detail)
        XCTAssertEqual(try pagesAsLaidOut(in: made.course), before, "a page was written")
    }

    /// A whole unit says the same, and names no unit as part changed. MUST
    /// FAIL on U3a's first round.
    func testAWholeUnitThatCannotBeWrittenIsSaidAsNothingChanged() async throws {
        let made: AssistFixture.Made = try makeLockedCourse(surface: .local)
        let before: [String] = try pagesAsLaidOut(in: made.course)
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": "Unit 1"], on: made.runner
        )
        XCTAssertTrue(outcome.detail.hasPrefix("Nothing was changed: "), outcome.detail)
        XCTAssertFalse(
            outcome.detail.hasPrefix(AssistWording.publishStoppedPartWay(what: "Unit 1", problem: "")), outcome.detail
        )
        XCTAssertEqual(try pagesAsLaidOut(in: made.course), before, "a page of the unit was written")
    }

    /// An outside assistant hears the same, and is pointed at no button.
    func testAnOutsideAssistantIsToldNothingChanged() async throws {
        let made: AssistFixture.Made = try makeLockedCourse(surface: .mcp)
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": ["Unit 1, Day 1", "Unit 1, Day 2"]], on: made.runner
        )
        XCTAssertTrue(outcome.detail.hasPrefix("Nothing was changed: "), outcome.detail)
        XCTAssertFalse(outcome.detail.contains("Restore Section"), outcome.detail)
    }

    /// The pointer names the banner's own button.
    func testThePointerNamesTheBannersButton() {
        XCTAssertTrue(
            AssistWording.restoreSectionPutsItBack(section: "2")
                .contains(AssistSectionRestore.buttonTitle(sectionNumber: 2))
        )
    }

    /// The open-ended refusal is the key, not a literal of its own.
    func testTheOpenEndedRefusalIsTheKey() throws {
        let day: CalendarDay = try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 8))
        XCTAssertEqual(
            AssistToolRefusal.openEndedPublish(day).message,
            AssistWording.openEndedPublishRefused(day: day.text)
        )
    }
}
