import XCTest
@testable import QuartzTeachers

/// What the app asks the engine for, and what it does when the engine stops
/// the model part way through answering.
///
/// The fault these pin was measured rather than imagined (issue #166). With no
/// cap on the wire, one ordinary request — "publish tomorrow's class, and make
/// sure every page it links to is published rather than left as a draft" —
/// made the smaller assistant write 5,435 tokens of a page list until the
/// context was full: 42 seconds, three trials in three, and an unusable answer
/// at the end of it. The app then RAN what it had been sent, with the
/// half-written arguments thrown away, and refused it with "There is no course
/// called "" in this working folder" — a sentence that reads as a complaint
/// about what the teacher typed.
///
/// Two halves, and both are needed. The cap bounds the wait. The gate decides
/// what an unfinished answer is worth, which is nothing.
@MainActor
final class AssistCutOffAnswerTests: XCTestCase {

    // MARK: - Types

    /// The replies this file serves, built rather than pasted, so a change to
    /// the shape is made in one place.
    private enum Canned {

        /// A tool call the model finished writing.
        static func finished(tool: String, arguments: String) -> String {
            return reply(finishReason: "tool_calls", tool: tool, arguments: arguments)
        }

        /// A tool call the ENGINE stopped part way through — whatever the
        /// arguments happen to look like.
        static func stopped(tool: String, arguments: String) -> String {
            return reply(finishReason: "length", tool: tool, arguments: arguments)
        }

        /// Plain words, with no tool call at all.
        static func text(_ said: String, finishReason: String) -> String {
            let escaped: String = escape(said)
            return #"{"choices":[{"finish_reason":"\#(finishReason)","message":"#
                + #"{"role":"assistant","content":"\#(escaped)"}}],"#
                + #""usage":{"completion_tokens":512}}"#
        }

        private static func reply(finishReason: String, tool: String, arguments: String) -> String {
            let escaped: String = escape(arguments)
            return #"{"choices":[{"finish_reason":"\#(finishReason)","message":"#
                + #"{"role":"assistant","content":"","tool_calls":["#
                + #"{"id":"call-1","type":"function","function":"#
                + #"{"name":"\#(tool)","arguments":"\#(escaped)"}}]}}],"#
                + #""usage":{"completion_tokens":512}}"#
        }

        private static func escape(_ text: String) -> String {
            var escaped: String = text.replacingOccurrences(of: "\\", with: "\\\\")
            escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
            escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
            return escaped
        }
    }

    // MARK: - Every request carries a cap

    /// The request body is built where a test can read it, for the same
    /// reason `AssistServerHost.serverArguments` is: a field that only exists
    /// inside the function that opens the socket cannot be checked without
    /// opening one, and this is a field whose silent loss costs 42 seconds a
    /// turn.
    func testEveryRequestCapsHowMuchTheModelMayWrite() throws {
        let client: AssistModelClient = AssistModelClient(
            baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1"))
        )
        let body: [String: Any] = try client.requestBody(
            messages: [AssistMessage.user("Publish tomorrow's class")], tools: []
        )

        XCTAssertEqual(
            body["max_tokens"] as? Int, AssistModelClient.mostTokensPerReply,
            "The request carries no cap, so a reply is bounded only by the context — 5,435 tokens and 42 seconds, measured."
        )
        XCTAssertEqual(
            AssistModelClient.mostTokensPerReply, 512,
            "512 is the number Windows already sends, and contracts/app-rules.json → modelTiers.requirements says neither app moves it alone."
        )
        // The rest of the body is unchanged, which is the other half of "a
        // cap changes where a generation stops, never what is asked for".
        XCTAssertEqual(body["temperature"] as? Int, 0)
        XCTAssertEqual(body["stream"] as? Bool, false)
    }

    /// And it reaches the wire. Guards against `reply` being changed back to
    /// building its own body, which would leave `requestBody` a function only
    /// the test above calls.
    func testTheCapReachesTheWire() async throws {
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.text("ready", finishReason: "stop"))

        let client: AssistModelClient = AssistModelClient(baseURL: engine.baseURL)
        _ = try await client.reply(messages: [AssistMessage.user("Hello")], tools: [])

        let sent: [String: Any] = try XCTUnwrap(engine.requestBodies.first)
        XCTAssertEqual(sent["max_tokens"] as? Int, 512, "What the app actually put on the socket.")
    }

    // MARK: - A reply the engine stopped is marked as such

    func testAReplyStoppedPartWayIsMarkedAsCutOff() async throws {
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        let client: AssistModelClient = AssistModelClient(baseURL: engine.baseURL)

        engine.serve(Canned.stopped(tool: "deploy_section", arguments: #"{"course": "ICS3U""#))
        let stopped: AssistReply = try await client.reply(
            messages: [AssistMessage.user("Publish everything")], tools: []
        )
        XCTAssertTrue(stopped.wasCutOff)

        engine.serve(Canned.finished(tool: "deploy_section", arguments: #"{"course": "ICS3U"}"#))
        let finished: AssistReply = try await client.reply(
            messages: [AssistMessage.user("Publish everything")], tools: []
        )
        XCTAssertFalse(finished.wasCutOff)

        // An engine that reports no finish reason at all is taken at its word
        // rather than guessed about: refusing every reply from a server that
        // does not send the field would break the assistant outright.
        engine.serve(
            #"{"choices":[{"message":{"role":"assistant","content":"done"}}],"usage":{"completion_tokens":3}}"#
        )
        let silent: AssistReply = try await client.reply(
            messages: [AssistMessage.user("Publish everything")], tools: []
        )
        XCTAssertFalse(silent.wasCutOff)
    }

    // MARK: - Nothing is run from an answer that did not finish

    /// **The one that matters**, and the shape it uses is the measured one.
    ///
    /// The arguments here are COMPLETE and parse perfectly, and the turn still
    /// ended on `length`. That is not a contrived case: llama.cpp closes the
    /// arguments object before the `</tool_call>` wrapper, so sweeping the cap
    /// across an ordinary request found a window one or two tokens wide where
    /// a stopped generation parses — `deploy_section {"course": "VVH2O",
    /// "section": 1}` at a cap of 28. What the model was about to write next
    /// is unknowable, so a parse check cannot be the gate.
    ///
    /// Plan mode is OFF, deliberately. On (which is what a teacher has) the
    /// write is held behind a plan and the page survives for a reason that has
    /// nothing to do with this fix — so the on-disk assertion would pass
    /// against the old code and prove nothing.
    func testAnAnswerCutOffPartWayRunsNothingAndSaysSo() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.stopped(
            tool: "publish_pages",
            arguments: #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say("Publish tomorrow's class and everything it links to")

        // The strongest form of "nothing ran", and the one that survives a
        // refactor of the transcript.
        let onDisk: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(
            onDisk.contains("publish: false"),
            "The page was published from an answer the engine stopped part way through writing."
        )

        XCTAssertTrue(
            transcript(of: agent).contains(AssistWording.answerWasCutOff),
            "The teacher was not told the answer did not finish."
        )
        XCTAssertEqual(toolResults(in: agent), [], "A tool ran.")
        XCTAssertEqual(made.siteWork.previewRebuilds, 0)
        XCTAssertEqual(agent.activity, .idle)
        XCTAssertNil(agent.pendingApproval, "An unfinished answer was put in front of a button.")
        XCTAssertEqual(
            engine.requestCount, 1,
            "The unfinished answer was handed back to the model for another lap."
        )
        // The dropped reply leaves no dangling tool call in the history: a
        // `tool_calls` message that no `tool` message ever answers is a
        // conversation some chat templates reject outright.
        for message in agent.messages {
            XCTAssertNil(message.toolCalls, "The cut-off reply was kept in the conversation.")
        }
    }

    /// The retry the wording asks for must not carry the request that ran
    /// away.
    ///
    /// The sentence a teacher reads here is "Ask me again — a shorter
    /// sentence, or fewer pages at a time", and that advice is unfollowable
    /// if the runaway request is still in the conversation: the next turn
    /// would be sent with both. So the whole turn is wound back out of
    /// `messages` — and the transcript keeps the teacher's sentence, because
    /// what they can SEE is a different thing from what goes to the model.
    func testAnAbandonedTurnIsNotCarriedIntoTheNextRequest() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve([
            Canned.stopped(
                tool: "publish_pages",
                arguments: #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"}"#
            ),
            Canned.text("All right.", finishReason: "stop"),
        ])

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        let runaway: String = "Publish tomorrow's class and every single page it links to, all of them"
        await agent.say(runaway)

        let afterTheAbandonedTurn: Int = agent.messages.count
        XCTAssertEqual(
            afterTheAbandonedTurn, 1,
            "An abandoned turn left something behind — only the system prompt should remain."
        )

        await agent.say("Publish Unit 1, Day 1")

        // Exactly one new message: the retry, and nothing of the turn that
        // was abandoned.
        var sentences: [String] = []
        for message in agent.messages where message.role == "user" {
            sentences.append(message.content ?? "")
        }
        XCTAssertEqual(sentences.count, 1, "The abandoned sentence was sent again with the retry.")
        XCTAssertTrue(try XCTUnwrap(sentences.first).hasPrefix("Publish Unit 1, Day 1"))

        // And the SECOND request on the wire carries the same thing, which is
        // the claim that actually matters.
        let secondRequest: [String: Any] = try XCTUnwrap(engine.requestBodies.last)
        let sent: [[String: Any]] = try XCTUnwrap(secondRequest["messages"] as? [[String: Any]])
        var sentByTheTeacher: [String] = []
        for message in sent where (message["role"] as? String) == "user" {
            sentByTheTeacher.append((message["content"] as? String) ?? "")
        }
        XCTAssertEqual(sentByTheTeacher.count, 1, "The runaway request was sent to the model a second time.")
        XCTAssertFalse(
            try XCTUnwrap(sentByTheTeacher.first).contains("every single page it links to"),
            "The retry was sent with the request that ran away still in front of it."
        )

        // What the teacher can see is untouched: their own sentence is still
        // in the transcript, above the answer.
        XCTAssertTrue(transcript(of: agent).contains(runaway))
    }

    /// A cut-off `deploy_section` must not put a Go button in front of a
    /// teacher.
    ///
    /// Unreachable by construction — the approval branch is inside
    /// `run(call:)`, below the gate — and named anyway, because "it offered to
    /// publish to students from an answer it never finished" is the sentence
    /// somebody will look for in this file.
    func testACutOffDeployNeverReachesTheApprovalButton() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(hasDeployedBefore: true)
        defer { try? FileManager.default.removeItem(at: made.root) }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        // The measured shape: stopped at 28 tokens, and the arguments parse.
        engine.serve(Canned.stopped(
            tool: "deploy_section", arguments: #"{"course": "ICS3U", "section": 1}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say("Put section 1 in front of the students this evening please")

        XCTAssertNil(agent.pendingApproval, "A deploy nobody finished asking for was offered a Go button.")
        XCTAssertFalse(agent.pendingIsDeploy)
        XCTAssertEqual(made.siteWork.deploys, 0)
        XCTAssertEqual(agent.activity, .idle)
        XCTAssertTrue(transcript(of: agent).contains(AssistWording.answerWasCutOff))
    }

    /// The same, with plan mode ON — which is what a teacher actually has.
    ///
    /// Not a duplicate: on this path the old code reached `showPlan` rather
    /// than `execute`, so what a teacher saw was a plan twin's refusal instead
    /// of an honest sentence, and the transcript is the assertion.
    func testAnAnswerCutOffPartWayIsRefusedWithPlansTurnedOnToo() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.stopped(
            tool: "publish_pages",
            arguments: #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        await agent.say("Publish tomorrow's class and everything it links to")

        XCTAssertTrue(transcript(of: agent).contains(AssistWording.answerWasCutOff))
        XCTAssertNil(agent.pendingApproval, "A plan was offered for an answer that never finished.")
        XCTAssertEqual(agent.activity, .idle)
    }

    /// Cut off BEFORE the tool name was written, the same measurement found a
    /// raw `<tool_call>` fragment sitting in the message content — which the
    /// plain-words branch would have printed straight into the transcript.
    /// Machinery in front of a teacher, and an answer besides.
    func testACutOffAnswerWithNoToolCallIsNotReadOutToTheTeacher() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.text("<tool_call>\n{\n\"name\": \"publi", finishReason: "length"))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say("Publish tomorrow's class and everything it links to")

        let said: String = transcript(of: agent)
        XCTAssertTrue(said.contains(AssistWording.answerWasCutOff))
        XCTAssertFalse(said.contains("tool_call"), "A half-written reply was shown to the teacher verbatim.")
        XCTAssertEqual(agent.activity, .idle)
    }

    /// The other cause, which has nothing to do with the cap: a small model
    /// writing arguments that are simply not JSON, with the turn finishing
    /// normally. Same answer, because running a call whose arguments were lost
    /// means running it against no course at all.
    func testACallWhoseArgumentsCannotBeReadRunsNothing() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(
            tool: "publish_pages",
            arguments: #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say("Publish tomorrow's class and everything it links to")

        let onDisk: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(onDisk.contains("publish: false"))
        XCTAssertTrue(transcript(of: agent).contains(AssistWording.answerWasCutOff))
        XCTAssertEqual(toolResults(in: agent), [])
    }

    /// A FINISHED answer that names a tool needing arguments and writes none
    /// runs nothing either (issue #198). Before, an empty string was readable
    /// for every tool, so this reached `publish_pages` bound to the window's
    /// section with no pages and no dates, and the teacher — who had named a
    /// page — was answered as though they had named nothing. Plans are left
    /// ON, because that is the path a teacher meets by default.
    func testAFinishedAnswerThatWroteNothingForAToolThatNeedsSomethingRunsNothing() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrote-nothing-trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: folderURL)
        }

        for written in ["", "   ", "{}"] {
            let engine: StubEngine = try StubEngine()
            defer { engine.stop() }
            engine.serve(Canned.finished(tool: "publish_pages", arguments: written))

            let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
            await agent.say("Publish tomorrow's class and everything it links to")
            XCTAssertGreaterThan(engine.requestCount, 0, "The sentence was answered in code; the model was never asked")

            let onDisk: String = try String(
                contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
            )
            XCTAssertTrue(onDisk.contains("publish: false"), "\"\(written)\" changed a page")
            XCTAssertTrue(
                transcript(of: agent).contains(AssistWording.answerWasCutOff),
                "\"\(written)\": the teacher was not told the answer did not come through: \(transcript(of: agent))"
            )
            XCTAssertEqual(toolResults(in: agent), [], "\"\(written)\" reached a tool")
            XCTAssertNil(agent.pendingApproval, "\"\(written)\" put a card up")
        }

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("finished answering but wrote nothing for publish pages"),
            "The trail does not say the assistant wrote nothing:\n\(trail)"
        )
    }

    /// And the tool that genuinely takes nothing still runs on nothing:
    /// llama.cpp sends an empty string for `undo_last_change`, and "Undo that"
    /// is the tool a card reaches most. Refusing every empty call was the
    /// cheap fix, and this is why it was rejected.
    func testAFinishedAnswerThatWroteNothingForAToolThatNeedsNothingStillRuns() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        for written in ["", "{}"] {
            let engine: StubEngine = try StubEngine()
            defer { engine.stop() }
            engine.serve(Canned.finished(tool: "undo_last_change", arguments: written))

            let agent: AssistAgent = AssistFixture.makeAgent(
                tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
            )
            await agent.say("Please put back whatever you changed a moment ago")
            XCTAssertGreaterThan(engine.requestCount, 0, "The sentence was answered in code; the model was never asked")

            XCTAssertFalse(
                transcript(of: agent).contains(AssistWording.answerWasCutOff),
                "\"\(written)\" for undo was refused as though it were not an answer"
            )
        }
    }

    /// The teacher hears the same sentence for both causes — from their side
    /// an answer that ran out of room and one that came out garbled are the
    /// same event. The TRAIL has to tell them apart, because whoever reads a
    /// report cannot: one is a question about how much the model was asked to
    /// write, the other about the model itself.
    func testTheTrailTellsTheTwoCausesApart() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cut-off-trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: folderURL)
        }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(
            tool: "publish_pages",
            arguments: #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say("Publish tomorrow's class and everything it links to")

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("finished answering but what it wrote for publish pages could not be read"),
            "The trail says the answer was cut off, when the engine did not cut it off:\n\(trail)"
        )
        XCTAssertTrue(trail.contains("nothing was run from it"), trail)
    }

    /// A second lap can be cut off too, and the gate has to be in the loop
    /// rather than at its entrance: a read hands back to the model, and the
    /// model's next answer is a fresh chance to run away.
    func testAnAnswerCutOffOnASecondLapRunsNothing() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        // Lap one is a READ, which hands back to the model; lap two is the
        // write, stopped part way.
        engine.serve([
            Canned.finished(tool: "list_pages", arguments: #"{"course": "ICS3U", "section": 1}"#),
            Canned.stopped(
                tool: "publish_pages",
                arguments: #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"}"#
            ),
        ])

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say("What is in section 1, and publish all of it")

        XCTAssertEqual(engine.requestCount, 2, "The read did not hand back to the model.")
        XCTAssertEqual(toolResults(in: agent), ["list_pages"], "The write ran after all.")
        let onDisk: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(onDisk.contains("publish: false"))
        XCTAssertTrue(transcript(of: agent).contains(AssistWording.answerWasCutOff))
        XCTAssertEqual(agent.activity, .idle)
        // The read that DID run goes back with the rest of the turn. The turn
        // was abandoned, and nothing in it changed a page.
        XCTAssertEqual(
            agent.messages.count, 1,
            "A second lap's read exchange was left in the conversation of an abandoned turn."
        )
    }

    // MARK: - A whole answer still runs

    /// The control, and the regression this fix could plausibly cause. Without
    /// it, a gate that refused everything would pass every test above.
    func testAWholeAnswerStillRuns() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(
            tool: "publish_pages",
            arguments: #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say("Publish Unit 1, Day 1")

        let onDisk: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(onDisk.contains("publish: true"), "A finished answer must still do what it says.")
        XCTAssertEqual(toolResults(in: agent), ["publish_pages"])
        XCTAssertFalse(transcript(of: agent).contains(AssistWording.answerWasCutOff))
    }

    // MARK: - The trail says so

    /// A teacher's side of this is a long wait and then the assistant
    /// declining, which is indistinguishable from a misroute. The trail line
    /// is the only place the difference is written down.
    func testTheTrailRecordsThatTheAnswerWasCutOff() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cut-off-trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: folderURL)
        }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.stopped(
            tool: "publish_pages",
            arguments: #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say("Publish tomorrow's class and everything it links to")

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        // The sentence a teacher would recognise, naming the tool the model
        // had BEGUN to name in words rather than as a function.
        XCTAssertTrue(
            trail.contains("the assistant's answer was cut off part way through publish pages"),
            "Nothing on the trail says the answer was cut off:\n\(trail)"
        )
        XCTAssertTrue(trail.contains("nothing was run from it"), trail)
        // And never what it had begun to write, which is the teacher's own
        // page titles.
        XCTAssertFalse(trail.contains("Unit 1, Day 1"), trail)
    }

    // MARK: - Helpers

    private func transcript(of agent: AssistAgent) -> String {
        var lines: [String] = []
        for entry in agent.entries {
            lines.append(entry.text)
        }
        return lines.joined(separator: "\n")
    }

    /// The names of the tools whose results reached the transcript.
    private func toolResults(in agent: AssistAgent) -> [String] {
        var names: [String] = []
        for entry in agent.entries {
            if case .toolResult(let name) = entry.speaker {
                names.append(name)
            }
        }
        return names
    }
}
