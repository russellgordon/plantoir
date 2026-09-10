import XCTest
@testable import QuartzTeachers

/// The parts of the assistant that decide what the model is asked, and what
/// never reaches it at all. These are the pieces where a small change quietly
/// costs routing accuracy, so each test names the measurement behind it.
///
/// Main-actor throughout: the test target defaults to `nonisolated`, while the
/// app's types default to `MainActor`, so a test that touches them has to say
/// where it is running.
@MainActor
final class AssistAgentTests: XCTestCase {

    // MARK: - What the teacher said always reaches the trail

    /// The regression that got reported twice, from the real app.
    ///
    /// A phrasing matched in code returns from `say` early and never reaches
    /// the model — so a recording placed anywhere below that branch misses an
    /// entire class of input, and the problem report's checkbox then hides
    /// itself from a teacher who had plainly just used the assistant. The
    /// sentence must be recorded ABOVE every branch, at the moment the
    /// teacher's words are accepted.
    func testAFixedPhraseIsStillRecordedOnTheTrail() async throws {
        let made = try AssistFixture.makeRunner()
        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
        defer { ActivityTrail.store = previousStore }

        let agent: AssistAgent = AssistAgent(
            courseCode: "ICS3U",
            sectionNumber: 1,
            // Never contacted: a fixed phrase is answered without the model.
            client: AssistModelClient(baseURL: URL(string: "http://127.0.0.1:1")!),
            tools: made.runner,
            planMode: AssistPlanMode(tier: .small, settings: AppSettings(defaults: UserDefaults()))
        )
        await agent.say("Undo that")

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains(AssistTurnRecord.promptMarker + "Undo that"),
            "the teacher's sentence never reached the trail:\n\(trail)"
        )
        XCTAssertTrue(ActivityTrail.store.hasAssistantPrompts, trail)
        // And the trail says WHY the model was not consulted, which is the
        // only place that question is answered.
        XCTAssertTrue(trail.contains("matched in code"), trail)

        try? FileManager.default.removeItem(at: folderURL)
        try? FileManager.default.removeItem(at: made.root)
    }

    /// The other half: an ordinary sentence, which does go to the model, is
    /// recorded before the request is made rather than after a reply.
    func testAnOrdinarySentenceIsRecordedBeforeTheModelIsAsked() async throws {
        let made = try AssistFixture.makeRunner()
        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
        defer { ActivityTrail.store = previousStore }

        let agent: AssistAgent = AssistAgent(
            courseCode: "ICS3U",
            sectionNumber: 1,
            // Unreachable on purpose: the request FAILS, and the sentence must
            // survive that. Tying the record to a reply lost exactly this case.
            client: AssistModelClient(baseURL: URL(string: "http://127.0.0.1:1")!),
            tools: made.runner,
            planMode: AssistPlanMode(tier: .small, settings: AppSettings(defaults: UserDefaults()))
        )
        await agent.say("Hide the page about loops")

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains(AssistTurnRecord.promptMarker + "Hide the page about loops"),
            "a sentence was lost because the engine did not answer:\n\(trail)"
        )
        XCTAssertTrue(trail.contains("could not answer"), trail)

        try? FileManager.default.removeItem(at: folderURL)
        try? FileManager.default.removeItem(at: made.root)
    }

    // MARK: - The fixed shapes

    /// The card phrasings the window offers are matched in code. Measured on
    /// the Windows side: the model misrouted five of the eleven in EVERY
    /// trial while filling arguments perfectly.
    func testCardPhrasingsAreMatchedRatherThanRouted() {
        XCTAssertEqual(AssistCardCommand.matching("Undo that")?.toolName, "undo_last_change")
        XCTAssertEqual(AssistCardCommand.matching("Rebuild the preview")?.toolName, "rebuild_preview")
        XCTAssertEqual(AssistCardCommand.matching("Deploy this section now")?.toolName, "deploy_section")
        XCTAssertEqual(
            AssistCardCommand.matching("What would students see in this section right now?")?.toolName,
            "check_section"
        )
    }

    /// Case and trailing punctuation vary with how a teacher types; the
    /// phrasing does not.
    func testMatchingToleratesCaseAndTrailingPunctuation() {
        XCTAssertEqual(AssistCardCommand.matching("  undo that.  ")?.toolName, "undo_last_change")
        XCTAssertEqual(AssistCardCommand.matching("DEPLOY THIS SECTION NOW!")?.toolName, "deploy_section")
    }

    /// The important half. A request that only LOOKS like a card phrasing
    /// must go to the model — matching it here would answer a different
    /// question with total confidence, which is worse than routing it.
    func testANearMissIsNotMatched() {
        XCTAssertNil(AssistCardCommand.matching("Undo that change to Unit 2, Day 3"))
        XCTAssertNil(AssistCardCommand.matching("Deploy this section now, but only the published pages"))
        XCTAssertNil(AssistCardCommand.matching("Publish tomorrow's class, but not the linked pages"))
        XCTAssertNil(AssistCardCommand.matching(""))
    }

    /// The one card phrasing that carries an argument still carries it.
    func testPublishTomorrowCarriesItsArgument() {
        let command: AssistCardCommand? = AssistCardCommand.matching("Publish tomorrow's class")
        XCTAssertEqual(command?.toolName, "publish_class_on")
        XCTAssertEqual(command?.arguments["when"], "tomorrow")
    }

    // MARK: - What the model is told

    /// Without a date, "tomorrow" became the schema's example date. With one
    /// PREPENDED, routing lost 15 points. The position is the finding.
    func testTheDatelineIsShapedTheWayItWasMeasured() throws {
        // Pinned to a known day rather than compared against `Date()`: a test
        // that formats today and then looks for today in the answer is a
        // function of the wall clock and cannot fail.
        let tuesday: CalendarDay = try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 8))
        XCTAssertEqual(
            AssistAgent.dateline(on: tuesday), "(Today is 2026-09-08, a Tuesday.)",
            "The measured form is '(Today is <ISO date>, a <weekday>.)'"
        )
    }

    /// The two acts share a word in ordinary speech, and the model will
    /// conflate them unless told plainly that they are different.
    func testTheSystemPromptSeparatesPublishingFromDeploying() {
        let prompt: String = AssistAgent.systemPrompt(course: "ICS3U", section: 2)
        XCTAssertTrue(prompt.contains("ICS3U"))
        XCTAssertTrue(prompt.contains("section 2"))
        XCTAssertTrue(prompt.contains("PUBLISHING"))
        XCTAssertTrue(prompt.contains("DEPLOYING"))
        XCTAssertTrue(prompt.contains("different acts"))
        XCTAssertTrue(prompt.contains("one tool at a time"))
    }

    // MARK: - The schema examples

    /// With `for example ICS3U` left in the examples, a request naming no
    /// course copied ICS3U out of them 9 times out of 9.
    func testTheRealCourseReplacesThePlaceholderEverywhere() {
        let definition: AssistToolDefinition = AssistToolDefinition(
            name: "list_pages",
            description: "List the pages in one section of a course, for example ICS3U.",
            parameters: [
                "course": AssistSchemaProperty(kind: .string, description: "The course code, for example ICS3U."),
                "section": AssistSchemaProperty(kind: .integer, description: "The section number, for example 1."),
            ],
            required: ["course", "section"],
            readOnly: true,
            needsApproval: false
        )

        let renamed: AssistToolDefinition = definition.namingTheRealCourse("ADA1O")
        XCTAssertFalse(renamed.description.contains("ICS3U"), "The description still names the placeholder")
        XCTAssertTrue(renamed.description.contains("ADA1O"))
        XCTAssertFalse(
            renamed.parameters["course"]?.description.contains("ICS3U") ?? true,
            "PARAMETER descriptions are where the model actually reads the example from"
        )
        XCTAssertTrue(renamed.parameters["course"]?.description.contains("ADA1O") ?? false)

        XCTAssertEqual(renamed.needsApproval, definition.needsApproval, "Renaming must not change the gate")
        XCTAssertEqual(renamed.readOnly, definition.readOnly)
        XCTAssertEqual(renamed.required, definition.required)
    }

    /// The schema the model receives has to be a valid JSON Schema object.
    func testParametersSerialiseAsAJSONSchemaObject() {
        let definition: AssistToolDefinition = AssistToolDefinition(
            name: "read_page",
            description: "Read one page.",
            parameters: ["page": AssistSchemaProperty(kind: .string, description: "The page title.")],
            required: ["page"],
            readOnly: true,
            needsApproval: false
        )

        let schema: [String: Any] = definition.parametersJSON
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["required"] as? [String], ["page"])

        let properties: [String: Any]? = schema["properties"] as? [String: Any]
        let page: [String: Any]? = properties?["page"] as? [String: Any]
        XCTAssertEqual(page?["type"] as? String, "string")

        XCTAssertTrue(JSONSerialization.isValidJSONObject(schema), "The model is sent this verbatim")
    }
}
