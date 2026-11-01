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
        XCTAssertTrue(view.contains("await askAboutClassesDatedLater(route: \"the assistant's deploy\", askedByTheAssistant: true)"),
                      "the window hands the question to the in-app assistant, saying it is the assistant's")

        let verbs: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift"
        ))
        let ask: String = try DeployAsksAboutLaterClassesTests.body(of: "    func askAboutClassesDatedLater(route: String", in: verbs)
        XCTAssertTrue(ask.contains("willBeRefused: deployWillBeRefused()"), "the deploy's own refusals come first")

        let runner: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Models/Assist/AssistToolRunner.swift"
        ))
        let deploy: String = try DeployAsksAboutLaterClassesTests.body(of: "    private func deploySection(", in: runner)
        let held: Range<String.Index> = try XCTUnwrap(deploy.range(of: "classesDatedLaterHoldTheDeploy(located)"))
        let stops: Range<String.Index> = try XCTUnwrap(deploy.range(of: "stopThePreviewBeforeWriting("))
        XCTAssertLessThan(held.lowerBound, stops.lowerBound, "asked before the preview is stopped")
    }

    /// #532: the held-back line is the contract's `line`, nobody named —
    /// `activityTrail.mustRecord` → "a deploy was held back for classes
    /// dated after the next class", which Windows writes too. MUST FAIL with
    /// ", asked for by …" on the end.
    func testAHeldBackDeployIsTheContractsLine() throws {
        let events: [[String: Any]] = try XCTUnwrap(
            try SharedRulesContractTests.section("activityTrail")["mustRecord"] as? [[String: Any]])
        var example: String = ""
        for event in events where event["event"] as? String == ActivityTrail.Event.laterClassesHeldADeployBack.rawValue {
            example = (event["line"] as? String) ?? ""
        }
        XCTAssertFalse(example.isEmpty, "the contract names the event")
        XCTAssertEqual(
            example.replacingOccurrences(of: "{N}", with: "1 class"),
            "{course}/{section} · " + ClassesDatedLater.heldBackLine(count: 1)
        )
        XCTAssertEqual(
            example.replacingOccurrences(of: "{N}", with: "2 classes"),
            "{course}/{section} · " + ClassesDatedLater.heldBackLine(count: 2)
        )
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
        let firstLines: String = String(run.prefix(500))
        XCTAssertTrue(firstLines.contains("classesDatedLaterGoingOut = classesDatedLaterLine(section: section)"),
                      "a scheduled run reads the classes it sends, and is not held up for them")
        // …and writes "deployed with" only once it HAS deployed: tested by
        // running the real wrapper, `ScheduledPublishOutcomeTests.
        // testTheClassesDatedLaterLineFollowsADeployThatWentOut`. Here, only
        // that the run records through that one function.
        XCTAssertTrue(scheduled.contains("recordTheRun(\n                label: label, section: section, fingerprint: fingerprintBeforeRunning"))
    }

    // MARK: - Publish Pages… never asks (#694)

    /// Section ▸ Publish Pages… goes straight from its choice to its plan:
    /// publishing changes only the preview, so the question is asked at
    /// Deploy and only there, and nothing is recorded as kept. The window
    /// cannot be hosted, so the wiring is pinned in the source. MUST FAIL
    /// with the old `.choosing` question or `flagged(ifPublishing:)` back.
    func testPublishPagesNeverAsks() throws {
        let verbs: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift"
        ))
        let press: String = try DeployAsksAboutLaterClassesTests.body(of: "    func pressDefault(in model:", in: verbs)
        XCTAssertFalse(press.contains("ask(about:"), "Publish Pages… asks nothing about classes dated later")
        XCTAssertFalse(press.contains("ClassesDatedLater.keep"), "Publish Pages… records nothing as kept")
        XCTAssertEqual(
            verbs.components(separatedBy: "model.ask(about:").count - 1, 1,
            "the question is put in one place: askAboutClassesDatedLater, at Deploy"
        )
        let rule: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Models/ClassesDatedLater.swift"
        ))
        XCTAssertFalse(rule.contains("ifPublishing"), "no question about pages about to be published")
    }

    /// The contract says the same (#694): Publish Pages… moved from
    /// `askedFrom` to `neverAskedFrom`, and the deploy-time-only exclusion
    /// is recorded as rejected (Russell's ruling 2). MUST FAIL on the old
    /// shared-rules.json.
    func testTheContractAsksOnlyAtDeploy() throws {
        let rules: [String: Any] = try SharedRulesContractTests.section("classesDatedLater")
        let askedFrom: String = try XCTUnwrap(rules["askedFrom"] as? String)
        let neverAskedFrom: String = try XCTUnwrap(rules["neverAskedFrom"] as? String)
        XCTAssertFalse(askedFrom.contains("Publish Pages"), "Publish Pages... is not where it is asked")
        XCTAssertTrue(neverAskedFrom.contains("Section > Publish Pages..."), "Publish Pages... is where it never is")
        let rejected: [String] = try XCTUnwrap(rules["rejected"] as? [String])
        var namesTheDeployOnlyExclusion: Bool = false
        for reason in rejected where reason.contains("preview") && reason.contains("drift") {
            namesTheDeployOnlyExclusion = true
        }
        XCTAssertTrue(namesTheDeployOnlyExclusion, "the deploy-time-only exclusion is recorded as rejected, with its reason")
    }

    /// A GUARD rather than a must-fail (the tool never asked, before #694 or
    /// after): the Section menu's own publish of a class dated later
    /// publishes it, writes no kept record, and leaves it flagged — so the
    /// next Deploy still asks about it.
    func testAClassPublishedFromTheMenuIsStillAskedAboutAtDeploy() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 2, Day 3", publish: "true", date: "2026-09-08", body: "Today.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 4", publish: "true", date: "2026-09-09", body: "Next.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 5", publish: "false", date: "2026-09-11", body: "Later.", in: made.course)
        let today: CalendarDay = CalendarDay(year: 2026, month: 9, day: 8)!
        XCTAssertEqual(ClassesDatedLater.flagged(forSection: 1, in: made.course, today: today), [], "hidden: nothing flagged yet")
        _ = await made.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 2, Day 5"], planning: false
        ))
        let kept: URL = ClassesDatedLater.KeptRecord.fileURL(courseDirectory: made.course.directoryURL, section: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.path), "publishing records nothing as kept")
        var places: [String] = []
        for page in ClassesDatedLater.flagged(forSection: 1, in: made.course, today: today) {
            places.append(page.place)
        }
        XCTAssertEqual(places, ["section1/All Classes/Unit 2, Day 5"], "published, and still asked about at Deploy")
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

/// Note 8b of batch B's review: the in-app assistant's question about classes
/// dated later is put on the section's window, which is brought to the front
/// first — the assistant's own window is usually in front of it.
@MainActor
final class LaterClassesQuestionComesForwardTests: XCTestCase {

    // MARK: - Tests

    func testTheAssistantsQuestionBringsItsWindowForward() throws {
        XCTAssertTrue(SectionDetailView.bringsItsWindowForward(askedByTheAssistant: true))
        XCTAssertFalse(SectionDetailView.bringsItsWindowForward(askedByTheAssistant: false),
                       "a teacher who pressed Deploy is already looking at this window")
        let verbs: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift"
        ))
        let ask: String = try DeployAsksAboutLaterClassesTests.body(of: "    func askAboutClassesDatedLater(route: String", in: verbs)
        let forward: Range<String.Index> = try XCTUnwrap(ask.range(of: "bringThisWindowForward()"))
        let question: Range<String.Index> = try XCTUnwrap(ask.range(of: "verbSheet = model"))
        XCTAssertLessThan(forward.lowerBound, question.lowerBound, "brought forward BEFORE the question goes up")
        XCTAssertTrue(ask.contains("if SectionDetailView.bringsItsWindowForward(askedByTheAssistant: askedByTheAssistant)"))
        let bring: String = try DeployAsksAboutLaterClassesTests.body(of: "    func bringThisWindowForward()", in: verbs)
        XCTAssertTrue(bring.contains("makeKeyAndOrderFront"))
    }
}
