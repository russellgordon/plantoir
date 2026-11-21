import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Every place that makes a daily action's step on the main actor reads the
/// app's list OFF it first (`JournaledStep.readTheListAhead`; the director's
/// ruling 8 on U1's third round; the first review of U3a, LOW 6), seen
/// through `JournaledStep.readAheadHook` as each place really runs: the
/// sheets shown in a window, the questions put, the runner's tools. Replaces
/// a source-text search (the second review of U3a, LOW 4). Each MUST FAIL
/// with that place's read ahead taken out.
@MainActor
final class UndoReadAheadTests: XCTestCase {

    // MARK: - Stored properties

    var windows: [NSWindow] = []

    var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
    }

    override func tearDown() async throws {
        JournaledStep.readAheadHook = nil
        for window in windows {
            window.close()
        }
        windows = []
        ActivityTrail.store = previousTrail
    }

    // MARK: - Helpers

    /// An expectation fulfilled by the next read ahead.
    func expectingAReadAhead(_ what: String) -> XCTestExpectation {
        let readAhead: XCTestExpectation = expectation(description: "\(what) reads the list ahead")
        readAhead.assertForOverFulfill = false
        JournaledStep.readAheadHook = {
            readAhead.fulfill()
        }
        return readAhead
    }

    /// Shows a view in a window off the screen, as a sheet is shown.
    func show(_ view: some View) {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -6000, y: -6000, width: 640, height: 720),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host: NSHostingView = NSHostingView(rootView: AnyView(view))
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        windows.append(window)
    }

    func made() throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(surface: .local)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        return made
    }

    // MARK: - Tests

    func testTheLinksChecklistReadsAheadWhenItIsShown() async throws {
        let made: AssistFixture.Made = try made()
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root,
            offer: try LinksChecklistTests.offer(from: []), answered: nil, occasion: .afterAPreview
        )
        let readAhead: XCTestExpectation = expectingAReadAhead("the links checklist")
        show(LinksChecklistSheet(model: model))
        await fulfillment(of: [readAhead], timeout: 10)
    }

    func testTheClassDatesSheetReadsAheadWhenItIsShown() async throws {
        let made: AssistFixture.Made = try made()
        let readAhead: XCTestExpectation = expectingAReadAhead("the class dates sheet")
        show(SectionScheduleSheet(course: made.course, sectionNumber: 1))
        await fulfillment(of: [readAhead], timeout: 10)
    }

    func testCourseSettingsReadsAheadWhenItIsShown() async throws {
        let made: AssistFixture.Made = try made()
        let readAhead: XCTestExpectation = expectingAReadAhead("Course Settings")
        show(CourseSettingsView(course: made.course))
        await fulfillment(of: [readAhead], timeout: 10)
    }

    func testTheQuestionAboutLaterClassesReadsAhead() async throws {
        let made: AssistFixture.Made = try made()
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .publishPages, course: made.course, sectionNumber: 1, title: "", item: nil
        )
        let readAhead: XCTestExpectation = expectingAReadAhead("the question about later classes")
        model.ask(about: [], nextDay: nil)
        await fulfillment(of: [readAhead], timeout: 10)
    }

    func testTheQuestionAboutTodaysClassReadsAhead() async throws {
        let made: AssistFixture.Made = try made()
        let classes: [(title: String, created: String, publish: String)] = [
            ("Unit 2, Day 4", "2026-09-29T07:00:00.000-0400", "true"),
            ("Unit 2, Day 5", "2026-09-30T07:00:00.000-0400", "true"),
        ]
        for page in classes {
            try "---\ntitle: \(page.title)\npublish: \(page.publish)\ncreated: \(page.created)\n---\n"
                .write(to: AssistFixture.pageURL(of: page.title, in: made.course), atomically: true, encoding: .utf8)
        }
        try "---\ntitle: Section 1\npublish: true\n---\n# Most Recent Class\n\n![[Unit 2, Day 4]]\n"
            .write(to: SectionIndexPointer.indexURL(forSection: 1, in: made.course), atomically: true, encoding: .utf8)
        let readAhead: XCTestExpectation = expectingAReadAhead("the question about today's class")
        let day: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-30"))
        XCTAssertNotNil(TodaysClassOnTheFrontPage.offer(forSection: 1, in: made.course, today: day), "no question was put")
        await fulfillment(of: [readAhead], timeout: 10)
    }

    func testEveryToolOfTheRunnerReadsAhead() async throws {
        let made: AssistFixture.Made = try made()
        let readAhead: XCTestExpectation = expectingAReadAhead("the runner")
        _ = await AssistFixture.run("list_courses", with: [:], on: made.runner)
        await fulfillment(of: [readAhead], timeout: 10)
    }

    func testGettingReadyForTheStartOfTheYearReadsAhead() async throws {
        StartOfYearUndoRegistry.shared.forgetAll()
        defer {
            StartOfYearUndoRegistry.shared.forgetAll()
        }
        let made = try StartOfYearTests.aSmallYear()
        let model: StartOfYearSheetModel = StartOfYearSheetModel(
            course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady
        )
        model.load()
        let readAhead: XCTestExpectation = expectingAReadAhead("Get Ready for the Start of the Year")
        await model.goAhead()
        await fulfillment(of: [readAhead], timeout: 10)
    }
}
