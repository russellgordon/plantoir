import XCTest
@testable import QuartzTeachers

/// What an assistant window does with the `course` and `section` the MODEL
/// filled in.
///
/// The window is opened for one section of one course. The SECTION is taken
/// back from whatever the model answered — a fact the app already knows is not
/// worth asking a model for, and "Unpublish Unit 4, Day 12" read as section 4
/// is the failure that bought the rule. The COURSE is not taken back: doing
/// that meant "publish MCV4U's class", typed in an ICS3U window, quietly
/// succeeding on ICS3U, which is a failure that reports success. It is refused
/// instead, before anything can run.
///
/// **The trap this file is written around.** A test that drives the agent with
/// a SENTENCE proves nothing if that sentence is a card phrasing: those are
/// answered in code and never reach the model or the binder at all. Six
/// Windows tests passed that way while testing nothing. So every test here
/// asserts that its sentence matches NO card, and that the scripted reply was
/// actually taken off the wire.
@MainActor
final class AssistWindowBindingTests: XCTestCase {

    // MARK: - Types

    /// The replies these tests serve. Built rather than pasted, the same shape
    /// `AssistCutOffAnswerTests.Canned` uses — a finished tool call, which is
    /// the only kind that reaches the binder.
    private enum Canned {

        static func finished(tool: String, arguments: String) -> String {
            let escaped: String = escape(arguments)
            return #"{"choices":[{"finish_reason":"tool_calls","message":"#
                + #"{"role":"assistant","content":"","tool_calls":["#
                + #"{"id":"call-1","type":"function","function":"#
                + #"{"name":"\#(tool)","arguments":"\#(escaped)"}}]}}],"#
                + #""usage":{"completion_tokens":48}}"#
        }

        /// Plain words, with no tool call at all.
        ///
        /// Served as the SECOND reply wherever the scripted tool is a READ.
        /// A read hands back to the model, and the stub's last reply answers
        /// every request after it — so a regression that let a refused read
        /// run would meet the same tool call again, for ever. Measured while
        /// proving the must-fail rows: the suite hung rather than failing,
        /// which reads as a broken machine rather than as the regression it
        /// is. With a plain answer waiting, the same regression fails on
        /// `requestCount` in under a second.
        static func text(_ said: String) -> String {
            return #"{"choices":[{"finish_reason":"stop","message":"#
                + #"{"role":"assistant","content":"\#(escape(said))"}}],"#
                + #""usage":{"completion_tokens":4}}"#
        }

        private static func escape(_ text: String) -> String {
            var escaped: String = text.replacingOccurrences(of: "\\", with: "\\\\")
            escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
            return escaped
        }
    }

    // MARK: - The section is this window's

    /// The section the model named is replaced by the window's — and all
    /// three things that carry it downstream carry the window's.
    ///
    /// Plan mode is ON, which is what a teacher has, so the one call produces
    /// all three: the plan twin runs on the bound arguments, the approval card
    /// holds them while the teacher decides, and `approvePending` hands the
    /// very same call to the act.
    ///
    /// The plan twin's carrier is proved rather than read: a twin asked about
    /// Section 4 of a course that has only Section 1 answers with a REFUSAL,
    /// and a refusal is not offered a Go button. So a plan question in the
    /// transcript is only possible if the twin ran on Section 1.
    ///
    /// Not a must-fail row: the old binder also bound the section. It is the
    /// regression guard for the half of the rule that is unchanged.
    func testTheSectionTheModelNamedIsReplacedByThisWindows() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(
            tool: "publish_pages",
            arguments: #"{"course": "ICS3U", "section": 4, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        let sentence: String = "Please put Unit 1, Day 1 in front of my students"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)

        XCTAssertEqual(engine.requestCount, 1, "The scripted reply was never consumed.")

        // Carrier one: the plan twin. It could only have produced a plan by
        // locating Section 1.
        XCTAssertTrue(
            transcript(of: agent).contains(AssistWording.planQuestion),
            "The plan twin refused, which is what Section 4 would have done:\n\(transcript(of: agent))"
        )
        // Carrier two: the card the teacher is about to answer.
        let waiting: AssistAgent.PendingApproval = try XCTUnwrap(agent.pendingApproval)
        XCTAssertEqual(waiting.call.argumentValues["section"] as? Int, 1)
        XCTAssertEqual(waiting.call.argumentValues["course"] as? String, "ICS3U")

        // Carrier three: what actually runs on Go.
        await agent.approvePending()
        let onDisk: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(onDisk.contains("publish: true"), "The act ran against a different section.")
    }

    /// A call that named NEITHER argument is filled in rather than lost.
    ///
    /// No tool reads an absent section as "every section", so a call like this
    /// used to reach the tool with nothing to locate and come back with "There
    /// is no course called """ — a complaint that reads as though the
    /// teacher's sentence were the problem. **A must-fail row:** the old
    /// binder only wrote either argument when one of them was already there.
    func testArgumentsTheModelLeftOutAreFilledInFromTheWindow() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(tool: "publish_pages", arguments: #"{"pages": "Unit 1, Day 1"}"#))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        let sentence: String = "Let the students see Unit 1, Day 1 now"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)

        XCTAssertEqual(engine.requestCount, 1, "The scripted reply was never consumed.")
        let onDisk: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(
            onDisk.contains("publish: true"),
            "A call with no course and no section was lost instead of being bound to this window."
        )
    }

    /// The same course in another casing is not another course.
    ///
    /// It runs — and it runs in the WINDOW's spelling, which is the half a
    /// teacher can see: `schedule_deploy`'s approval card prints the code
    /// verbatim, so leaving the model's casing would put "deploy ics3u
    /// Section 1" in front of somebody about to press Go. A regression guard
    /// rather than a must-fail row: the old binder normalised it too, by
    /// overwriting everything.
    func testTheSameCourseInAnotherCasingRunsInThisWindowsSpelling() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(hasDeployedBefore: true)
        defer { try? FileManager.default.removeItem(at: made.root) }
        // The scheduled card reads whether a deploy is already set for the
        // section (issue #195); it must read a folder this test owns, never
        // the real ~/Library/LaunchAgents of whoever runs the suite.
        let launchAgents: URL = made.root.appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = launchAgents
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            launchAgents.deletingLastPathComponent().appendingPathComponent("scheduled")
        defer {
            ScheduledDeploy.launchAgentsDirectoryOverride = nil
            ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(
            tool: "schedule_deploy",
            arguments: #"{"course": "ics3u", "section": 1, "when": "06:30"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        let sentence: String = "Send my section out to the students early tomorrow morning"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)

        XCTAssertEqual(engine.requestCount, 1, "The scripted reply was never consumed.")
        let waiting: AssistAgent.PendingApproval = try XCTUnwrap(
            agent.pendingApproval, "A course this window IS for was refused."
        )
        XCTAssertEqual(waiting.call.argumentValues["course"] as? String, "ICS3U")
        XCTAssertTrue(waiting.explanation.contains("ICS3U Section 1"), waiting.explanation)
        XCTAssertFalse(
            waiting.explanation.contains("ics3u"),
            "The model's casing reached the card a teacher reads: \(waiting.explanation)"
        )
    }

    /// A tool whose schema declares NEITHER argument is left alone.
    ///
    /// `undo_last_change` takes nothing, so nothing here is the window's to
    /// take back and there is nothing to refuse — even with a stray course
    /// from another world on it. The gate is the tool's own schema rather than
    /// a list of tool names, and the second assertion is the gate's own input:
    /// a list of twelve would agree with the schema today, which is exactly
    /// when a list looks harmless.
    ///
    /// Not a must-fail row, and worth saying why rather than leaving it to be
    /// re-derived: the old binder DID rewrite both arguments here, but the
    /// tool reads neither, so the difference cannot be observed from outside.
    /// What this pins is that the guard does not fire.
    func testAToolThatDeclaresNeitherArgumentIsNotRefusedAndNotRewritten() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(alsoCourse: "MCV4U")
        defer { try? FileManager.default.removeItem(at: made.root) }

        let declared: [String: AssistSchemaProperty] = try XCTUnwrap(
            made.runner.definition(named: "undo_last_change")?.parameters
        )
        XCTAssertTrue(declared.isEmpty, "undo_last_change now declares arguments; the gate reads the schema.")

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(
            tool: "undo_last_change", arguments: #"{"course": "MCV4U", "section": 9}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        let sentence: String = "That was not what I wanted, put it back the way it was"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)

        XCTAssertEqual(engine.requestCount, 1, "The scripted reply was never consumed.")
        XCTAssertEqual(toolResults(in: agent), ["undo_last_change"], "The tool did not run.")
        XCTAssertFalse(
            transcript(of: agent).contains(
                AssistWording.askedAboutAnotherCourse(course: "ICS3U", otherCourse: "MCV4U")
            ),
            "A tool that declares no course was refused over one."
        )
    }

    // MARK: - The course is this window's, or the turn is refused

    /// A course that IS in this working folder, and is not this window's.
    ///
    /// **The must-fail row this whole piece exists for.** The old binder wrote
    /// this window's course over MCV4U and published an ICS3U class, reporting
    /// success — the one failure a teacher cannot catch.
    func testACallNamingAnotherCourseInThisFolderIsRefusedAndNothingRuns() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(alsoCourse: "MCV4U")
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("another-course-trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: folderURL)
        }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        // The model's own spelling is `mcv4u`, deliberately: the two halves of
        // this answer disagree about it ON PURPOSE, and asserting both here is
        // what stops the trail being "tidied up" into the sentence's spelling.
        engine.serve(Canned.finished(
            tool: "publish_pages",
            arguments: #"{"course": "mcv4u", "section": 1, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        let sentence: String = "Put my calculus lesson in front of the students for me"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)

        XCTAssertEqual(engine.requestCount, 1, "The refused turn was handed back to the model for another lap.")

        // The sentence a teacher reads, named rather than typed.
        XCTAssertTrue(
            transcript(of: agent).contains(
                AssistWording.askedAboutAnotherCourse(course: "ICS3U", otherCourse: "MCV4U")
            ),
            transcript(of: agent)
        )
        // Nothing ran, in every sense there is.
        let onDisk: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(onDisk.contains("publish: false"), "A page was published from a refused turn.")
        XCTAssertEqual(toolResults(in: agent), [], "A tool ran.")
        XCTAssertNil(agent.pendingApproval, "A refused turn was put in front of a button.")
        XCTAssertEqual(made.siteWork.previewRebuilds, 0)
        XCTAssertEqual(made.siteWork.deploys, 0)
        XCTAssertEqual(agent.activity, .idle)

        // The turn is wound back out of the conversation: at temperature 0, a
        // sentence left in front of the model produces the same refusal again.
        XCTAssertEqual(
            agent.messages.count, 1,
            "A refused turn was left in the conversation — only the system prompt should remain."
        )
        // What the teacher can SEE keeps their own words, as on every path.
        XCTAssertTrue(transcript(of: agent).contains(sentence))

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        // The TRAIL keeps what the MODEL wrote; the SENTENCE above names the
        // course the way the working folder spells it. Both are asserted,
        // because the divergence is a rule — `contracts/shared-rules.json` →
        // `activityTrail.mustRecord` says so — and a normalised line would
        // throw away the only record that the model spelt it oddly.
        XCTAssertTrue(
            trail.contains("the assistant was asked about mcv4u in this window, which is for ICS3U"),
            "Nothing on the trail says the request named another course, in the model's own spelling:\n\(trail)"
        )
        XCTAssertFalse(
            trail.contains("MCV4U"),
            "The trail was normalised to the folder's spelling, losing what the model actually wrote:\n\(trail)"
        )
        XCTAssertTrue(trail.contains("nothing was run from it"), trail)
        XCTAssertTrue(trail.contains("publish pages"), trail)
        // Never the argument values, which are the teacher's page titles.
        XCTAssertFalse(trail.contains("Unit 1, Day 1"), trail)
    }

    /// A code that names NO course here — a typo, or one the model invented.
    ///
    /// **Refused too, and this is the decision worth a test of its own.**
    /// Binding it to this window looks harmless, because a code matching
    /// nothing cannot reach another course — and it would publish an ICS3U
    /// class off "publish MCV4's class", which is the fault being fixed
    /// arriving through the one door left open. A second sentence, because the
    /// first one tells the teacher to go and open that course and there is no
    /// such course to open.
    ///
    /// **A must-fail row:** the old binder published the page.
    func testACallNamingNoCourseHereIsRefusedWithASentenceThatDoesNotSendThemLooking() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(alsoCourse: "MCV4U")
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(
            tool: "publish_pages",
            arguments: #"{"course": "ZZZ9Z", "section": 1, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        let sentence: String = "Show the students that lesson from my other class please"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)

        XCTAssertEqual(engine.requestCount, 1, "The refused turn was handed back to the model for another lap.")
        XCTAssertTrue(
            transcript(of: agent).contains(
                AssistWording.askedAboutACourseThatIsNotHere(course: "ICS3U", otherCourse: "ZZZ9Z")
            ),
            transcript(of: agent)
        )
        // And NOT the sentence that would send them looking for a course that
        // is not in the sidebar.
        XCTAssertFalse(
            transcript(of: agent).contains(
                AssistWording.askedAboutAnotherCourse(course: "ICS3U", otherCourse: "ZZZ9Z")
            ),
            transcript(of: agent)
        )
        let onDisk: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(onDisk.contains("publish: false"), "A page was published from a refused turn.")
        XCTAssertEqual(toolResults(in: agent), [], "A tool ran.")
        XCTAssertNil(agent.pendingApproval)
        XCTAssertEqual(agent.messages.count, 1)
        XCTAssertEqual(agent.activity, .idle)
    }

    /// A READ of another course is refused in the same words.
    ///
    /// **Allowing reads was rejected.** A teacher cannot tell which tool the
    /// model picked, so a rule that held only for writes would read as random
    /// — and it is the rule Windows' own course lock already applies to
    /// everything.
    func testAReadOfAnotherCourseIsRefusedToo() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(alsoCourse: "MCV4U")
        defer { try? FileManager.default.removeItem(at: made.root) }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve([
            Canned.finished(tool: "list_pages", arguments: #"{"course": "MCV4U", "section": 1}"#),
            Canned.text("All right."),
        ])

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        let sentence: String = "What lessons does my calculus class have so far?"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)

        XCTAssertEqual(engine.requestCount, 1, "The refused turn was handed back to the model for another lap.")
        XCTAssertTrue(
            transcript(of: agent).contains(
                AssistWording.askedAboutAnotherCourse(course: "ICS3U", otherCourse: "MCV4U")
            ),
            transcript(of: agent)
        )
        XCTAssertEqual(toolResults(in: agent), [], "A read of another course ran.")
        XCTAssertEqual(agent.activity, .idle)
    }

    /// A course code with a stray newline on it is still this window's course.
    ///
    /// The guard compares the way the tools compare — `locate` reads the value
    /// through `text(_:in:)`, which trims whitespace AND newlines — because a
    /// guard that trims less refuses a turn the tool would have run: a lost
    /// turn on the teacher's own course, and told about in words that name a
    /// course sitting in their sidebar.
    func testACourseCodeWithAStrayNewlineIsStillThisWindowsCourse() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(alsoCourse: "MCV4U")
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "A class.", in: made.course)

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(
            tool: "publish_pages",
            arguments: #"{"course": "ICS3U\n", "section": 1, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        let sentence: String = "Let my students see that first lesson now please"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)

        XCTAssertEqual(engine.requestCount, 1, "The scripted reply was never consumed.")
        let onDisk: String = try String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), encoding: .utf8
        )
        XCTAssertTrue(
            onDisk.contains("publish: true"),
            "This window's own course was refused over a trailing newline."
        )
        XCTAssertEqual(toolResults(in: agent), ["publish_pages"])
    }

    /// And a stray newline on ANOTHER course's code does not turn that course
    /// into one the folder has never heard of.
    ///
    /// The same trim, the other way round: untrimmed, `MCV4U\n` matches no
    /// course, and the teacher reads "there is no course called MCV4U here"
    /// about a course sitting in their sidebar — the exact lie the second
    /// sentence exists to avoid, arriving from the other direction.
    func testAnotherCourseWithAStrayNewlineIsStillThatCourse() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(alsoCourse: "MCV4U")
        defer { try? FileManager.default.removeItem(at: made.root) }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(
            tool: "publish_pages",
            arguments: #"{"course": "MCV4U\n", "section": 1, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        let sentence: String = "Put my calculus lesson in front of the students"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)

        XCTAssertEqual(engine.requestCount, 1, "The scripted reply was never consumed.")
        XCTAssertTrue(
            transcript(of: agent).contains(
                AssistWording.askedAboutAnotherCourse(course: "ICS3U", otherCourse: "MCV4U")
            ),
            transcript(of: agent)
        )
        XCTAssertEqual(toolResults(in: agent), [], "A tool ran.")
    }

    /// The refusal names the other course the way the FOLDER spells it.
    ///
    /// A teacher told to open "mcv4u" is being sent to look for something
    /// their sidebar does not show. The window's own code already gets this
    /// courtesy on the approval card; the course being refused gets it here.
    func testTheRefusalNamesTheOtherCourseTheWayTheFolderSpellsIt() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(alsoCourse: "MCV4U")
        defer { try? FileManager.default.removeItem(at: made.root) }

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve(Canned.finished(
            tool: "publish_pages",
            arguments: #"{"course": "mcv4u", "section": 1, "pages": "Unit 1, Day 1"}"#
        ))

        let agent: AssistAgent = AssistFixture.makeAgent(
            tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
        )
        let sentence: String = "Publish the lesson in my other class for me"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)

        XCTAssertEqual(engine.requestCount, 1, "The scripted reply was never consumed.")
        XCTAssertTrue(
            transcript(of: agent).contains(
                AssistWording.askedAboutAnotherCourse(course: "ICS3U", otherCourse: "MCV4U")
            ),
            transcript(of: agent)
        )
        XCTAssertFalse(
            transcript(of: agent).contains("mcv4u"),
            "The model's spelling reached the teacher:\n\(transcript(of: agent))"
        )
        // The TRAIL keeps what the model wrote, deliberately: it is evidence
        // about the model rather than a sentence a teacher is sent to act on.
        XCTAssertEqual(toolResults(in: agent), [], "A tool ran.")
    }

    // MARK: - The MCP path is untouched

    /// A client driving the tools over `--mcp-stdio` chooses its own course
    /// and section, and this change did not take that away.
    ///
    /// The runner here is built the way `AssistMCPServer.serve` builds it — a
    /// workspace and nothing else — and the call is made the way its
    /// `tools/call` branch makes one: straight to `runner.run(call:)`, with no
    /// settling and no binding in between. **That construction IS the claim.**
    /// The guard lives in `AssistAgent`, and there is no `AssistAgent` in
    /// this test, exactly as there is none in that file; a guard moved into
    /// the runner would refuse the call below and this would go red.
    ///
    /// The contrast is the other half: the SAME course and section, asked for
    /// through a window, is refused two tests above.
    func testTheMCPPathHonoursAnyCourseAndSectionAsGiven() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(alsoCourse: "MCV4U")
        defer { try? FileManager.default.removeItem(at: made.root) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: made.root)
        let server: AssistToolRunner = AssistToolRunner(workspace: workspace)

        let call: AssistToolCall = AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(
                name: "check_section",
                arguments: #"{"course": "MCV4U", "section": 2}"#
            )
        )
        let outcome: AssistToolOutcome = await server.run(call: call)

        XCTAssertTrue(
            outcome.detail.contains("MCV4U Section 2"),
            "A caller's own course and section were not honoured over MCP:\n\(outcome.detail)"
        )
        XCTAssertFalse(
            outcome.detail.contains("ICS3U"),
            "The MCP path answered about a different course:\n\(outcome.detail)"
        )
        XCTAssertFalse(
            outcome.detail.contains("Section 1"),
            "The MCP path answered about a different section:\n\(outcome.detail)"
        )
    }

    // MARK: - The card path cannot reach the guard

    /// No phrasing answered in code carries a `course` argument of its own.
    ///
    /// Belt and braces: the guard is in `think()`, which the card path never
    /// enters — `say()` runs a matched card straight through
    /// `run(settledCall:)`. This makes that structural fact into something
    /// that fails if a card phrasing ever starts naming a course.
    func testNoPhrasingAnsweredInCodeNamesACourseOfItsOwn() {
        for shape in AssistCardCommand.everyFixedShape {
            XCTAssertNil(
                shape.command.arguments["course"],
                "The fixed phrasing “\(shape.phrasing)” names a course of its own."
            )
        }
        for shape in AssistCardCommand.everyParsedShape {
            XCTAssertNil(
                shape.fills["course"],
                "The parsed shape “\(shape.shape)” fills in a course of its own."
            )
        }
    }

    // MARK: - The contract's own cases

    /// Every case in `contracts/assist-cases.json` → `windowBinding`, run
    /// against the real agent.
    ///
    /// The rule is DATA because it can be: a window, the arguments the model
    /// wrote, and either the arguments that run or the refusal a teacher
    /// reads. The tests above say WHY each answer is the right one; this says
    /// that the file and the app agree, so the other platform can run the
    /// identical list rather than a description of it.
    ///
    /// Plan mode is ON throughout, which is what a teacher has, and it is what
    /// makes the answer readable: a write stops at the approval card holding
    /// exactly the arguments that would run.
    func testTheWindowBindingCasesInTheContractAreFollowed() async throws {
        let binding: [String: Any] = try AssistWindowBindingTests.windowBinding()
        let window: [String: Any] = try XCTUnwrap(binding["window"] as? [String: Any])
        XCTAssertEqual(window["course"] as? String, "ICS3U", "The fixture is not the window the cases describe.")
        XCTAssertEqual(window["section"] as? Int, 1)
        XCTAssertEqual(
            binding["coursesInTheFolder"] as? [String], ["ICS3U", "MCV4U"],
            "The fixture's working folder is not the one the cases describe."
        )

        let cases: [[String: Any]] = try XCTUnwrap(binding["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty, "The contract lists no cases at all.")
        for entry in cases {
            try await playOut(entry)
        }
    }

    /// One contract case, end to end.
    private func playOut(_ entry: [String: Any]) async throws {
        let tool: String = try XCTUnwrap(entry["tool"] as? String)
        let said: [String: Any] = try XCTUnwrap(entry["said"] as? [String: Any])
        let written: String = String(
            data: try JSONSerialization.data(withJSONObject: said), encoding: .utf8
        ) ?? "{}"

        let made: AssistFixture.Made = try AssistFixture.makeRunner(alsoCourse: "MCV4U")
        defer { try? FileManager.default.removeItem(at: made.root) }
        try AssistFixture.write(
            page: "Unit 1, Day 1", publish: "false", date: "2026-09-08",
            body: "A class.", in: made.course
        )

        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        // A plain answer behind the scripted call, because one of these cases
        // names a READ — see `Canned.text`.
        engine.serve([Canned.finished(tool: tool, arguments: written), Canned.text("All right.")])

        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        let sentence: String = "Have a look at that lesson of mine and sort it out"
        XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
        await agent.say(sentence)
        XCTAssertEqual(engine.requestCount, 1, "\(tool): the scripted reply was never consumed.")

        if let refusal = entry["refusedWith"] as? String {
            // The other course is named the way the WORKING FOLDER spells it
            // wherever the folder has it, so a case may pin a spelling that
            // is not the one the model wrote.
            var naming: String = try XCTUnwrap(said["course"] as? String)
            if let spelling = entry["namesTheCourseAs"] as? String {
                naming = spelling
            }
            let expected: String = try AssistWindowBindingTests.sentence(
                named: refusal, otherCourse: naming
            )
            XCTAssertTrue(
                transcript(of: agent).contains(expected),
                "\(tool): the wrong refusal, or the wrong spelling of \(naming):\n\(transcript(of: agent))"
            )
            XCTAssertNil(agent.pendingApproval, "\(tool): a refused turn was put in front of a button.")
            XCTAssertEqual(toolResults(in: agent), [], "\(tool): a tool ran on a refused turn.")
            XCTAssertEqual(agent.messages.count, 1, "\(tool): a refused turn stayed in the conversation.")
            return
        }

        let runs: [String: Any] = try XCTUnwrap(entry["runs"] as? [String: Any])
        // A tool with a plan twin stops at the card, which holds the very
        // arguments the act would be given. One case names a tool with no
        // twin and no card — `undo_last_change`, which declares neither
        // argument — and there the only thing to see from outside is that the
        // turn was not refused and the tool ran, because that tool reads
        // neither argument.
        guard agent.pendingApproval != nil else {
            XCTAssertEqual(toolResults(in: agent), [tool], "\(tool): the turn was refused or lost.")
            return
        }
        let waiting: AssistToolCall = try XCTUnwrap(agent.pendingApproval).call
        let actual: [String: Any] = waiting.argumentValues
        for (key, expected) in runs {
            if let wanted = expected as? String {
                XCTAssertEqual(actual[key] as? String, wanted, "\(tool): \(key)")
            } else if let wanted = expected as? Int {
                XCTAssertEqual(actual[key] as? Int, wanted, "\(tool): \(key)")
            } else {
                XCTFail("\(tool): the contract's \(key) is neither a string nor a number.")
            }
        }
    }

    /// The sentence a wording key names, with both courses filled in.
    ///
    /// A switch rather than a lookup, so a key in the contract that no
    /// sentence answers fails here instead of being skipped.
    private static func sentence(named key: String, otherCourse: String) throws -> String {
        switch key {
        case "askedAboutAnotherCourse":
            return AssistWording.askedAboutAnotherCourse(course: "ICS3U", otherCourse: otherCourse)
        case "askedAboutACourseThatIsNotHere":
            return AssistWording.askedAboutACourseThatIsNotHere(course: "ICS3U", otherCourse: otherCourse)
        default:
            throw WindowBindingProblem.noSentenceCalled(key)
        }
    }

    /// Read from the repository, not from the test bundle: the contract's
    /// whole point is that it is committed and reviewable.
    private static func windowBinding() throws -> [String: Any] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(contentsOf: repository
            .appendingPathComponent("contracts")
            .appendingPathComponent("assist-cases.json"))
        let cases: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try XCTUnwrap(cases["windowBinding"] as? [String: Any])
    }

    private enum WindowBindingProblem: Error {
        case noSentenceCalled(String)
    }

    // MARK: - A tool the model was not offered (#327)

    /// A model that names a tool from outside the list it was shown is
    /// refused, and nothing runs — for a write with a twin, a write whose
    /// twin was once named wrong, and a plan twin named directly.
    ///
    /// **A must-fail row:** before #327 `re_date_classes` was planned and
    /// `add_curriculum_mentions` RAN, changing the page with no plan at all,
    /// because the runner can run all thirty-two tools and nothing in the
    /// agent asked whether this model had been offered the one it named.
    func testAToolTheModelWasNotOfferedIsRefusedAndNothingRuns() async throws {
        let cases: [(tool: String, arguments: String)] = [
            ("re_date_classes", #"{"course": "ICS3U", "section": 1}"#),
            ("add_curriculum_mentions",
             #"{"course": "ICS3U", "section": 1, "page": "Loops", "codes": "A1.1"}"#),
            ("plan_publish_pages", #"{"course": "ICS3U", "section": 1, "pages": "Unit 1, Day 2"}"#),
        ]
        for scripted in cases {
            let made: AssistFixture.Made = try AssistFixture.makeRichSection(for: self)
            defer { try? FileManager.default.removeItem(at: made.root) }
            var offered: [String] = []
            for definition in made.runner.definitions {
                offered.append(definition.name)
            }
            XCTAssertFalse(offered.contains(scripted.tool), "\(scripted.tool) is offered, so nothing was tested.")

            let folderURL: URL = FileManager.default.temporaryDirectory
                .appendingPathComponent("not-offered-trail-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let previousStore: ProblemReportStore = ActivityTrail.store
            ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
            defer {
                ActivityTrail.store = previousStore
                try? FileManager.default.removeItem(at: folderURL)
            }

            let engine: StubEngine = try StubEngine()
            defer { engine.stop() }
            engine.serve([
                Canned.finished(tool: scripted.tool, arguments: scripted.arguments),
                Canned.text("Done."),
            ])
            let loopsBefore: String = try String(
                contentsOf: made.course.directoryURL.appendingPathComponent("Concepts/Loops.md"),
                encoding: .utf8
            )

            // Plan mode OFF: the harder case, where nothing else stands
            // between the model's choice and the write.
            let agent: AssistAgent = AssistFixture.makeAgent(
                tools: made.runner, engineAt: engine.baseURL, asksBeforeChanging: false
            )
            let sentence: String = "Sort out whatever needs sorting in this section for me"
            XCTAssertNil(AssistCardCommand.matching(sentence), "The sentence is answered in code, so nothing was tested.")
            await agent.say(sentence)

            XCTAssertEqual(engine.requestCount, 1, "\(scripted.tool): the refused turn went back for another lap.")
            XCTAssertEqual(agent.entries.last?.text, AssistWording.didNotFollowThat, scripted.tool)
            XCTAssertEqual(toolResults(in: agent), [], "\(scripted.tool) ran.")
            XCTAssertNil(agent.pendingApproval, "\(scripted.tool) was put in front of a button.")
            XCTAssertEqual(agent.activity, .idle)
            XCTAssertEqual(agent.messages.count, 1, "The refused turn was left in the conversation.")
            let loopsAfter: String = try String(
                contentsOf: made.course.directoryURL.appendingPathComponent("Concepts/Loops.md"),
                encoding: .utf8
            )
            XCTAssertEqual(loopsAfter, loopsBefore, "\(scripted.tool) changed a page.")

            let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
            XCTAssertTrue(
                trail.contains(AssistAgent.namedAToolItWasNotOfferedLine(tool: scripted.tool)),
                "Nothing on the trail says the model reached past its list:\n\(trail)"
            )
            XCTAssertFalse(trail.contains("Unit 1, Day 2"), trail)
        }
    }

    /// A name that exists NOWHERE is not this refusal: it is still answered
    /// "There is no tool by that name." to the model, which then gets another
    /// lap — documented behaviour #327 deliberately left as it was.
    func testANameThatExistsNowhereStillGoesBackToTheModel() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRichSection(for: self)
        defer { try? FileManager.default.removeItem(at: made.root) }
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        engine.serve([
            Canned.finished(tool: "tidy_the_section", arguments: #"{"course": "ICS3U", "section": 1}"#),
            Canned.text("I can't do that."),
        ])
        let agent: AssistAgent = AssistFixture.makeAgent(tools: made.runner, engineAt: engine.baseURL)
        await agent.say("Sort out whatever needs sorting in this section for me")
        XCTAssertEqual(engine.requestCount, 2, "An unknown name was refused instead of being answered.")
        XCTAssertNotEqual(agent.entries.last?.text, AssistWording.didNotFollowThat)
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
