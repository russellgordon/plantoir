import XCTest
@testable import QuartzTeachers

/// What the app does when the assistant's whole reply is the teacher's own
/// sentence, handed back.
///
/// **The fault these pin was measured, and it is worse than one dead turn**
/// (issue #215, 2026-09-19; Qwen2.5-1.5B Q4_K_M, the app's own server flags,
/// request body and system prompt, temperature 0, the date line on every user
/// message). Asked to "hide unit 4, day 20", the smaller assistant chose no
/// tool and replied with the sentence it had just been given, date line and
/// all. That echo was then KEPT in the conversation, and the model copied the
/// pattern it could see — so the next request echoed too, including "Unpublish
/// Unit 4, Day 20", which the same model answers correctly every time in a
/// FRESH conversation. Replayed on ICD2O and ICS4U, two pages: identical in
/// all four. One unrecognised phrase made the window useless until it was
/// closed and opened again.
///
/// So there are two halves here, and the second is the cure. The app says one
/// honest sentence — never the echoed text — and winds the whole turn back out
/// of `messages`, which is what makes the NEXT request meet the conversation
/// the model gets right.
@MainActor
final class AssistEchoedReplyTests: XCTestCase {

    // MARK: - Types

    /// The replies this file serves. `Canned` is private per file on purpose
    /// — see `AssistCutOffAnswerTests` — so this is its own copy.
    private enum Canned {

        static func text(_ said: String, finishReason: String = "stop") -> String {
            let escaped: String = escape(said)
            return #"{"choices":[{"finish_reason":"\#(finishReason)","message":"#
                + #"{"role":"assistant","content":"\#(escaped)"}}],"#
                + #""usage":{"completion_tokens":24}}"#
        }

        /// Plain words AND a finished tool call in the same reply — which is
        /// what the model does when it narrates the request back beside a call
        /// it genuinely chose.
        static func textAndCall(_ said: String, tool: String, arguments: String) -> String {
            return #"{"choices":[{"finish_reason":"tool_calls","message":"#
                + #"{"role":"assistant","content":"\#(escape(said))","tool_calls":["#
                + #"{"id":"call-1","type":"function","function":"#
                + #"{"name":"\#(tool)","arguments":"\#(escape(arguments))"}}]}}],"#
                + #""usage":{"completion_tokens":24}}"#
        }

        static func finished(tool: String, arguments: String) -> String {
            return textAndCall("", tool: tool, arguments: arguments)
        }

        private static func escape(_ text: String) -> String {
            var escaped: String = text.replacingOccurrences(of: "\\", with: "\\\\")
            escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
            escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
            return escaped
        }
    }

    /// A sentence no fixed phrasing and no parsed family takes, so it really
    /// does reach the model. Asserted rather than assumed in every test that
    /// uses it — a sentence that quietly became a card phrasing would turn
    /// these into tests of nothing.
    private static let goesToTheModel: String = "please take tomorrow's class down off the site"

    // MARK: - One echo

    /// The teacher is told, nothing runs, and the turn leaves no trace.
    func testAnEchoedReplyIsRefusedAndSaidPlainly() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        XCTAssertNil(
            AssistCardCommand.matching(AssistEchoedReplyTests.goesToTheModel),
            "The sentence this test sends is matched in code, so it never reached the model at all."
        )

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        // The measured shape: the sentence back, with the date line still on
        // it and the first letter capitalised.
        let asked: String = AssistEchoedReplyTests.goesToTheModel
        let dateline: String = AssistAgent.dateline(on: made.runner.today)
        engine.serve(Canned.text(
            "Please take tomorrow's class down off the site \(dateline)"
        ))
        await agent.say(asked)

        let said: String = transcript(of: agent)
        XCTAssertTrue(
            said.contains(AssistWording.didNotFollowThat),
            "The teacher was not told the assistant did not follow them."
        )
        XCTAssertFalse(
            said.contains(dateline),
            "The echoed sentence was read back to the teacher, which is the fault itself."
        )
        XCTAssertEqual(toolResults(in: agent), [], "A tool ran.")
        XCTAssertNil(agent.pendingApproval)
        XCTAssertEqual(agent.activity, .idle)
        XCTAssertEqual(engine.requestCount, 1)
        // The whole turn is gone: only the system prompt is left, so the next
        // request meets the conversation that works.
        XCTAssertEqual(
            agent.messages.count, 1,
            "The echoed turn was left in the conversation, where it poisons every request after it."
        )
        // What the teacher can SEE is untouched.
        XCTAssertTrue(said.contains(asked))
    }

    // MARK: - The measured fault: one echo poisoning the next turn

    /// Two turns, which is where the fault actually lives.
    ///
    /// **The discriminator is the SECOND REQUEST BODY**, and it is worth
    /// naming: on the old code the scripted second reply still runs its tool,
    /// so "the page moved" passes either way. What fails against `dev` is that
    /// the second request carried TWO user messages — the echoed turn's
    /// sentence and the new one — which is exactly the history the model was
    /// measured copying.
    func testAnEchoedTurnIsNotCarriedIntoTheNextRequest() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(
            page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course
        )

        let echoed: String = AssistEchoedReplyTests.goesToTheModel
        // Both sentences must genuinely reach the model, or this test is about
        // the matcher instead. The second one is a near miss of a card
        // phrasing, which is precisely a sentence the contract says must
        // route.
        let secondRequest: String = "Publish tomorrow's class, but not the linked pages"
        XCTAssertNil(AssistCardCommand.matching(echoed))
        XCTAssertNil(AssistCardCommand.matching(secondRequest))

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve([
            Canned.text(echoed),
            Canned.finished(
                tool: "publish_pages",
                arguments: #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"}"#
            ),
        ])

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say(echoed)
        // The scripted echo really was consumed: this turn went to the model
        // and came back, rather than being answered by a card.
        XCTAssertEqual(engine.requestCount, 1, "The first sentence never reached the model.")
        XCTAssertTrue(transcript(of: agent).contains(AssistWording.didNotFollowThat))
        XCTAssertEqual(agent.messages.count, 1)

        await agent.say(secondRequest)

        let sent: [[String: Any]] = try XCTUnwrap(
            try XCTUnwrap(engine.requestBodies.last)["messages"] as? [[String: Any]]
        )
        var fromTheTeacher: [String] = []
        for message in sent where (message["role"] as? String) == "user" {
            fromTheTeacher.append((message["content"] as? String) ?? "")
        }
        XCTAssertEqual(
            fromTheTeacher.count, 1,
            "The echoed turn was sent to the model again in front of the next request."
        )
        XCTAssertTrue(try XCTUnwrap(fromTheTeacher.first).hasPrefix(secondRequest))
        // And nothing of the echoed turn is on the wire in any role.
        for message in sent {
            let text: String = (message["content"] as? String) ?? ""
            XCTAssertFalse(
                text.contains("take tomorrow's class down"),
                "The echoed turn reached the model a second time as \((message["role"] as? String) ?? "?")."
            )
        }
        // The second turn was answered normally, which is the other half of
        // the claim: the conversation was cleaned, not broken.
        XCTAssertEqual(toolResults(in: agent), ["publish_pages"])
    }

    // MARK: - What must still get through

    /// An ordinary plain-words reply still reaches the teacher, and stays in
    /// the conversation.
    ///
    /// The control. Without it, a guard that refused every plain reply would
    /// pass everything above.
    func testAPlainReplyThatIsNotAnEchoIsUnchanged() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.text("There is no page called Unit 9, Day 9 in this section."))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say(AssistEchoedReplyTests.goesToTheModel)

        let said: String = transcript(of: agent)
        XCTAssertTrue(said.contains("There is no page called Unit 9, Day 9"))
        XCTAssertFalse(said.contains(AssistWording.didNotFollowThat))
        XCTAssertEqual(
            agent.messages.count, 3,
            "An ordinary turn lost its place in the conversation: prompt, question, answer."
        )
    }

    /// A reply whose text IS the request but which chose a tool is an
    /// instruction, and it runs.
    ///
    /// The model narrating the request back beside a call it genuinely made is
    /// ordinary behaviour, and throwing that away would lose real work.
    func testAReplyThatEchoesButAlsoChoosesAToolStillRuns() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(
            page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course
        )

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.textAndCall(
            AssistEchoedReplyTests.goesToTheModel,
            tool: "publish_pages",
            arguments: #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say(AssistEchoedReplyTests.goesToTheModel)

        XCTAssertEqual(toolResults(in: agent), ["publish_pages"], "A real tool call was thrown away.")
        XCTAssertFalse(transcript(of: agent).contains(AssistWording.didNotFollowThat))
        let onDisk: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(onDisk.contains("publish: true"))
    }

    // MARK: - The second lap of a card-matched turn cannot fire it

    /// A card-matched turn begins with a TOOL RESULT, not a question — so the
    /// guard sees no user message and never fires, whatever the model then
    /// says.
    ///
    /// **This is aimed at one specific wrong implementation**: dropping the
    /// `role == "user"` check and comparing against whatever sits at the start
    /// of the turn. The reply served here is the tool result's own text, word
    /// for word, which is the only thing that would make that version fire.
    func testASecondLapReplyEqualToTheToolResultIsNotAnEcho() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        // Lap one: learn exactly what the read handed back to the model.
        let listening: StubEngine = try StubEngine()
        defer { listening.stop() }
        listening.serve(Canned.text("Two courses."))
        let first: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: listening.baseURL, asksBeforeChanging: false
        )
        await first.say("what courses do i have?")
        var handedBack: String = ""
        for message in first.messages where message.role == "tool" {
            handedBack = message.content ?? ""
        }
        XCTAssertFalse(handedBack.isEmpty, "The card phrasing ran no read, so this test proves nothing.")

        // Lap two, in a fresh conversation: the model answers with that text.
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.text(handedBack))
        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say("what courses do i have?")

        XCTAssertFalse(
            transcript(of: agent).contains(AssistWording.didNotFollowThat),
            "A card-matched turn fired the echo guard against its own tool result."
        )
        XCTAssertTrue(transcript(of: agent).contains(handedBack))
    }

    /// And the guard looks at the message this TURN began with, never at the
    /// last question asked at any point.
    ///
    /// **Aimed at the other wrong implementation**: searching backwards
    /// through `messages` for the most recent user message — the one a reader
    /// of `windTheTurnBack` would reach for. Turn one leaves a question in the
    /// conversation; turn two is a card phrasing whose second-lap reply
    /// happens to repeat that question. A backwards search fires; the real
    /// rule cannot.
    func testASecondLapCannotEchoAQuestionFromAnEarlierTurn() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let asked: String = AssistEchoedReplyTests.goesToTheModel
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve([
            // Turn one: an ordinary answer, which stays in the conversation.
            Canned.text("Nothing needs doing there."),
            // Turn two is a card phrasing that runs a read; the model's
            // second-lap reply repeats turn one's question word for word.
            Canned.text(asked),
        ])

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say(asked)
        XCTAssertFalse(transcript(of: agent).contains(AssistWording.didNotFollowThat))

        await agent.say("what courses do i have?")

        XCTAssertFalse(
            transcript(of: agent).contains(AssistWording.didNotFollowThat),
            "The guard compared a card-matched turn against a question from an earlier turn."
        )
        XCTAssertTrue(
            transcript(of: agent).contains(asked),
            "The teacher's own first sentence left the transcript."
        )
    }

    // MARK: - The trail says so

    /// A teacher's side of this is the assistant saying it did not follow,
    /// which is indistinguishable from an ordinary misroute. The trail line is
    /// the only place the difference is written down — and it carries no
    /// sentence and no page title.
    func testTheTrailRecordsThatTheRequestCameBackAgain() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: folderURL)
        }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        let asked: String = "hide the answers on Unit 4, Day 21"
        XCTAssertNil(AssistCardCommand.matching(asked))
        engine.serve(Canned.text(asked))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        await agent.say(asked)

        let trail: String = ActivityTrail.store.activityText(includingPrompts: false)
        XCTAssertTrue(
            trail.contains("the assistant repeated the request back instead of answering it"),
            "Nothing on the trail says the reply was the request again:\n\(trail)"
        )
        XCTAssertTrue(trail.contains("nothing was run"), trail)
        XCTAssertTrue(trail.contains("taken back out of the conversation"), trail)
        // Recorded once, not once per comparison.
        XCTAssertEqual(
            trail.components(separatedBy: "assistant repeated the request back").count - 1, 1, trail
        )
        // Never the teacher's own words, and never a page title: the marked
        // "assistant asked" line already carries the sentence, and this one is
        // read by whoever is handed a problem report.
        XCTAssertFalse(trail.contains("Unit 4, Day 21"), trail)
    }

    // MARK: - The rule, from the contract

    /// The predicate itself, walked from `assist-cases.json` → `echoedRequest`
    /// so that the mac and Windows answer the same question the same way.
    func testTheEchoRuleMatchesTheContract() throws {
        let family: [String: Any] = try XCTUnwrap(
            AssistEchoedReplyTests.contract()["echoedRequest"] as? [String: Any],
            "contracts/assist-cases.json has no echoedRequest"
        )
        XCTAssertNotNil(family["note"] as? String)
        let cases: [[String: Any]] = try XCTUnwrap(family["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)

        for row in cases {
            let sent: String = try XCTUnwrap(row["sent"] as? String)
            let typed: String = try XCTUnwrap(row["typed"] as? String)
            let reply: String = try XCTUnwrap(row["reply"] as? String)
            let hasToolCall: Bool = try XCTUnwrap(row["hasToolCall"] as? Bool)
            let expected: Bool = try XCTUnwrap(row["expectEcho"] as? Bool)
            XCTAssertNotNil(row["why"] as? String, "\(reply) is a case with no stated reason")

            XCTAssertEqual(
                AssistAgent.isTheRequestBackAgain(
                    sent: sent, typed: typed, reply: reply, hasToolCall: hasToolCall
                ),
                expected,
                "\(reply) — the contract says expectEcho \(expected)"
            )
        }
    }

    // MARK: - Helpers

    private static func contract() throws -> [String: Any] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(
            contentsOf: repository.appendingPathComponent("contracts")
                .appendingPathComponent(AssistContract.casesFileName)
        )
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func transcript(of agent: AssistAgent) -> String {
        var lines: [String] = []
        for entry in agent.entries {
            lines.append(entry.text)
        }
        return lines.joined(separator: "\n")
    }

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
