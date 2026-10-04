import XCTest
@testable import QuartzTeachers

/// A CLASS page whose file name is also a course-level page's — the shape of
/// `contracts/shared-rules.json` → `publishPlanNaming`'s "Notes" cases — is
/// published and hidden like any other class by the three paths that already
/// hold the class's file: a whole unit, `publish_class_on`, and the links
/// checklist's Publish (#425's stack review, item 1). Before the fix each
/// asked the planner by TITLE, the title fit two files, and the class was
/// dropped from the plan in silence: "Unit 1 was unpublished" with that class
/// still visible.
@MainActor
final class SameNamedClassPageTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL?

    var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
    }

    override func tearDown() async throws {
        ActivityTrail.store = previousTrail
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    // MARK: - Helpers

    /// A course with class "Unit 1, Day 1" (published as given) and a
    /// course-level page in Concepts with the SAME file name, hidden.
    func makeCourse(classPublished: String) throws -> (made: AssistFixture.Made, twin: URL, twinBefore: Data) {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        root = made.root
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        try AssistFixture.write(page: "Unit 1, Day 1", publish: classPublished, body: "The class.", in: made.course)
        let twin: URL = made.course.directoryURL.appendingPathComponent("Concepts/Unit 1, Day 1.md")
        try "---\ntitle: Unit 1, Day 1\npublishForSection1: false\n---\n\nA concept page.\n"
            .write(to: twin, atomically: true, encoding: .utf8)
        return (made, twin, try Data(contentsOf: twin))
    }

    func classIsVisible(in course: Course) throws -> Bool {
        let text: String = try String(contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: course), encoding: .utf8)
        return AssistPageVisibility.answer(in: text, forSection: 1) != .hidden
    }

    // MARK: - Tests

    /// MUST FAIL with the unit path asking by title: the class stays visible
    /// and the unit is reported hidden.
    func testHidingAWholeUnitHidesASameNamedClass() async throws {
        let built: (made: AssistFixture.Made, twin: URL, twinBefore: Data) = try makeCourse(classPublished: "true")
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "unpublish_pages", with: ["pages": ["Unit 1"]], on: built.made.runner
        )
        XCTAssertFalse(try classIsVisible(in: built.made.course), "Still visible after: \(outcome.detail)")
        XCTAssertEqual(try Data(contentsOf: built.twin), built.twinBefore, "The same-named concept page was touched.")
    }

    /// MUST FAIL with `planPublishingClass` asking by title: nothing published.
    func testPublishingTheClassOnADayPublishesASameNamedClass() async throws {
        let built: (made: AssistFixture.Made, twin: URL, twinBefore: Data) = try makeCourse(classPublished: "false")
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_class_on", with: ["date": "2026-09-08"], on: built.made.runner
        )
        XCTAssertTrue(try classIsVisible(in: built.made.course), "Not published after: \(outcome.detail)")
        XCTAssertEqual(try Data(contentsOf: built.twin), built.twinBefore, "The same-named concept page was touched.")
    }

    /// The links checklist's Publish, with the ticked class sharing its file
    /// name with a Concepts page (contract case iv-b plus the twin). MUST FAIL
    /// with the checklist asking the planner by title.
    func testTheLinksChecklistPublishesASameNamedTickedClass() throws {
        let testCase: [String: Any] = try LinksChecklistTests.publishCase("iv-b.")
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        root = made.root
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        let urls: [String: URL] = try LinksChecklistTests.layOut(testCase, made: made)
        let twin: URL = made.course.directoryURL.appendingPathComponent("Concepts/Unit 2, Day 5.md")
        try "---\ntitle: Unit 2, Day 5\npublishForSection1: false\n---\n\nA concept page.\n"
            .write(to: twin, atomically: true, encoding: .utf8)
        let twinBefore: Data = try Data(contentsOf: twin)
        let offer: LinksChecklistOffer = try LinksChecklistTests.offer(
            from: try XCTUnwrap(testCase["offer"] as? [[String: Any]])
        )
        let result: LinksChecklistPublisher.Result = LinksChecklistPublisher.publish(
            offer: offer, ticked: ["section1/All Classes/Unit 2, Day 5"], course: made.course,
            sectionNumber: 1, workspaceURL: made.root, shownComingWith: []
        )
        guard case .published = result else {
            XCTFail("Publish did not publish: \(result)")
            return
        }
        XCTAssertTrue(try LinksChecklistTests.visible(try XCTUnwrap(urls["Unit 2, Day 5"])),
                      "The ticked class was not published.")
        XCTAssertTrue(try LinksChecklistTests.visible(try XCTUnwrap(urls["Class Notes"])),
                      "The class did not bring its page.")
        XCTAssertEqual(try Data(contentsOf: twin), twinBefore, "The same-named concept page was touched.")
    }
}
