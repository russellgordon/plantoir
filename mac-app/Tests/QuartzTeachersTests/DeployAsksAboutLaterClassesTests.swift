import XCTest
@testable import QuartzTeachers

/// #475 at Deploy: where the question about classes dated after the next
/// class is asked, and in what order (`shared-rules.json` →
/// `classesDatedLater.order`). A section window cannot be hosted in a unit
/// test, so the decision is a pure function and the wiring is pinned in the
/// source — the #397 shape (`TodaysClassOnTheFrontPageTests.
/// testOnlyThePreviewButtonAsks`).
@MainActor
final class DeployAsksAboutLaterClassesTests: XCTestCase {

    // MARK: - The decision

    func testARefusalComesFirstThenTheQuestion() {
        XCTAssertEqual(
            SectionDetailView.whatDeployDoesFirst(willBeRefused: true, flagged: 3, somethingIsUp: false),
            .goStraightOn, "a deploy that will be refused is refused with no question, and nothing hidden"
        )
        XCTAssertEqual(
            SectionDetailView.whatDeployDoesFirst(willBeRefused: false, flagged: 0, somethingIsUp: true),
            .goStraightOn, "nothing to ask: the deploy goes on, whatever is up"
        )
        XCTAssertEqual(
            SectionDetailView.whatDeployDoesFirst(willBeRefused: false, flagged: 2, somethingIsUp: true),
            .cannotAsk, "the director's ruling: never wait on a window that has something up"
        )
        XCTAssertEqual(
            SectionDetailView.whatDeployDoesFirst(willBeRefused: false, flagged: 2, somethingIsUp: false),
            .ask
        )
    }

    // MARK: - The wiring

    /// The Deploy button (and Section ▸ Deploy…, which presses it) asks
    /// before it deploys; the in-app assistant's window hands the same
    /// question to the runner; and the runner asks BEFORE it stops the
    /// preview.
    func testEveryDeployFromTheAppAsksAndInOrder() throws {
        let view: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift"
        ))
        let start: String = try DeployAsksAboutLaterClassesTests.body(of: "    func startDeploy() {", in: view)
        let asks: Range<String.Index> = try XCTUnwrap(start.range(of: "askAboutClassesDatedLater(route: \"Deploy\")"))
        let deploys: Range<String.Index> = try XCTUnwrap(start.range(of: "deployAndWait(pressedByTheAssistant: false)"))
        XCTAssertLessThan(asks.lowerBound, deploys.lowerBound, "the Deploy button asks before it deploys")
        XCTAssertTrue(view.contains("askAboutClassesDatedLater: { await askAboutClassesDatedLater(route: \"the assistant's deploy\") }"),
                      "the window hands the question to the in-app assistant")

        let verbs: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift"
        ))
        let ask: String = try DeployAsksAboutLaterClassesTests.body(of: "    func askAboutClassesDatedLater(route: String)", in: verbs)
        XCTAssertTrue(ask.contains("willBeRefused: deployWillBeRefused()"), "the deploy's own refusals come first")

        let runner: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Models/Assist/AssistToolRunner.swift"
        ))
        let deploy: String = try DeployAsksAboutLaterClassesTests.body(of: "    private func deploySection(", in: runner)
        let held: Range<String.Index> = try XCTUnwrap(deploy.range(of: "classesDatedLaterHoldTheDeploy(located)"))
        let stops: Range<String.Index> = try XCTUnwrap(deploy.range(of: "stopThePreviewBeforeWriting("))
        XCTAssertLessThan(held.lowerBound, stops.lowerBound, "asked before the preview is stopped")
    }

    /// A scheduled deploy goes out as it is and records the places: the line
    /// is the trail's shape, and the run calls it.
    func testAScheduledDeployRecordsTheClassesItSent() throws {
        let pages: [ClassesDatedLater.Flagged] = [
            ClassesDatedLater.Flagged(place: "section1/All Classes/Unit 2, Day 5", title: "Unit 2, Day 5",
                                      date: CalendarDay(year: 2026, month: 10, day: 14)!),
        ]
        XCTAssertEqual(
            ClassesDatedLater.wentOutLine(pages),
            "deployed with classes dated after the next class: section1/All Classes/Unit 2, Day 5"
        )
        XCTAssertNil(ClassesDatedLater.wentOutLine([]))
        var many: [ClassesDatedLater.Flagged] = []
        for day in 1...12 {
            many.append(ClassesDatedLater.Flagged(place: "p\(day)", title: "P\(day)", date: CalendarDay(year: 2026, month: 11, day: day)!))
        }
        XCTAssertTrue(try XCTUnwrap(ClassesDatedLater.wentOutLine(many)).hasSuffix("; and 2 more"))

        let scheduled: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Models/ScheduledDeploy.swift"
        ))
        let run: String = try XCTUnwrap(scheduled.components(separatedBy: "case .run:").dropFirst().first)
        let firstLines: String = String(run.prefix(400))
        XCTAssertTrue(firstLines.contains("noteClassesDatedLaterGoingOut(section: section)"),
                      "a scheduled run records the classes it sends, and is not held up for them")
    }

    // MARK: - Helpers

    static func source(_ path: String) throws -> String {
        let root: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The text of a function, from its signature to the next `    func `.
    static func body(of signature: String, in source: String) throws -> String {
        let start: Range<String.Index> = try XCTUnwrap(source.range(of: signature), signature)
        let rest: Substring = source[start.upperBound...]
        var end: String.Index = rest.endIndex
        for terminator in ["\n    func ", "\n    private func "] {
            if let next = rest.range(of: terminator), next.lowerBound < end {
                end = next.lowerBound
            }
        }
        return String(rest[..<end])
    }

    /// The source without its comment lines.
    static func codeOnly(_ source: String) -> String {
        var kept: [String] = []
        for line in source.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }
}
