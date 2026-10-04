import XCTest
@testable import QuartzTeachers

/// A publish or a hide (marking pages, not a deploy) that stops part way says
/// `AssistWording.publishStoppedPartWay` — never "Nothing was changed", which
/// the page-list path said until #412 although the pages before the failing
/// one were already written — and, in the in-app assistant with a copy saved
/// for the conversation, points at the banner's Restore Section button.
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

    let prefixForPages: String = AssistWording.publishStoppedPartWay(what: "the pages you named", problem: "")

    // MARK: - Tests

    /// MUST FAIL before #412: the page-list path said "Nothing was changed".
    func testAPageListThatStopsPartWayIsSaidAsPartlyChangedWithTheWayBack() async throws {
        let made: AssistFixture.Made = try makeLockedCourse(surface: .local)
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": "Unit 1, Day 1, Unit 1, Day 2"], on: made.runner
        )
        XCTAssertTrue(outcome.detail.hasPrefix(prefixForPages), outcome.detail)
        XCTAssertFalse(outcome.detail.contains("Nothing was changed"), outcome.detail)
        XCTAssertTrue(made.runner.hasConversationBackup, "The fixture's publish saves a copy first.")
        XCTAssertTrue(
            outcome.detail.hasSuffix(" " + AssistWording.restoreSectionPutsItBack(section: "1")),
            "MUST FAIL without the Restore Section pointer: \(outcome.detail)"
        )
    }

    /// A whole unit says the same key with the unit named.
    func testAWholeUnitThatStopsPartWayNamesTheUnit() async throws {
        let made: AssistFixture.Made = try makeLockedCourse(surface: .local)
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": "Unit 1"], on: made.runner
        )
        let prefix: String = AssistWording.publishStoppedPartWay(what: "Unit 1", problem: "")
        XCTAssertTrue(outcome.detail.hasPrefix(prefix), outcome.detail)
    }

    /// An outside assistant has no Restore Section button to press, so it is
    /// not pointed at one.
    func testAnOutsideAssistantIsNotPointedAtAButtonItCannotSee() async throws {
        let made: AssistFixture.Made = try makeLockedCourse(surface: .mcp)
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": "Unit 1, Day 1, Unit 1, Day 2"], on: made.runner
        )
        XCTAssertTrue(outcome.detail.hasPrefix(prefixForPages), outcome.detail)
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
