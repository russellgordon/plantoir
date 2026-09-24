import Foundation
import Observation

/// The conversation loop: what the teacher said, what the model chose, what
/// ran, and what came back.
///
/// The safety rules do NOT live here. They live in the tools — which is what
/// lets the built-in assistant and Claude Code drive the same server without
/// the rules drifting between them. This type's job is to route, to hold the
/// gate open for the one act that needs a button, and to keep the transcript.
@Observable
@MainActor
final class AssistAgent {

    // MARK: - Types

    /// One line of the conversation as the teacher sees it.
    struct Entry: Identifiable, Equatable {
        let id: UUID = UUID()
        let speaker: Speaker
        let text: String

        /// What unfolding this line shows, when there is more worth showing.
        ///
        /// A count is not something a teacher can act on: "1 broken link"
        /// says something is wrong and nothing about where. The list is the
        /// answer, and it belongs behind a disclosure rather than in the flow
        /// of the conversation, which is why the line stays one line.
        var detail: String? = nil

        enum Speaker: Equatable {
            case teacher
            case assistant
            case toolResult(name: String)
            case problem
        }
    }

    /// A write waiting for the teacher to say yes.
    struct PendingApproval: Equatable {
        let call: AssistToolCall
        let explanation: String
    }

    /// What the agent is doing.
    enum Activity: Equatable {
        case idle
        case thinking
        case running(toolName: String)
        case waitingForApproval
    }

    // MARK: - Stored properties

    /// The conversation, oldest first.
    private(set) var entries: [Entry] = []

    /// What it is doing now.
    private(set) var activity: Activity = .idle

    /// The deploy waiting on a button, if any.
    private(set) var pendingApproval: PendingApproval?

    /// The course and section this window is about.
    let courseCode: String
    let sectionNumber: Int

    /// Where requests go.
    private let client: AssistModelClient

    /// What can be run.
    private let tools: AssistToolRunner

    /// Whether writes are shown before they happen.
    let planMode: AssistPlanMode

    /// The messages actually sent, including tool results.
    ///
    /// Readable from a test, not writable: two things about the user message
    /// are measured findings rather than preferences — the dateline goes on
    /// the END (prepending it cost 15 points of routing accuracy) and it
    /// carries the runner's day rather than a second reading of the clock —
    /// and neither could be asserted while this was private.
    private(set) var messages: [AssistMessage] = []

    /// How long `messages` was when the teacher's current turn began.
    ///
    /// The mark an abandoned turn is wound back to. Taken at the top of
    /// `say()` rather than beside the user message, so it is right for the
    /// fixed-phrase branch too — that one runs a tool without ever appending
    /// a user message, and the tool result it leaves behind belongs to the
    /// same turn.
    private var messageCountAtTheStartOfTheTurn: Int = 0

    /// What the teacher typed this turn, trimmed, BEFORE the date line was
    /// put on the end of it.
    ///
    /// Kept because nothing else keeps it: what goes into `messages` is the
    /// sentence and the date line together, and recomputing the date line to
    /// take it off again would read the clock a second time — the very thing
    /// `withTheDaySettled` exists to prevent. Read by
    /// `theReplyIsTheRequestBackAgain`, so that a model echoing the sentence
    /// WITHOUT the parenthetical is recognised as the same fault.
    private var sentenceThisTurnBeganWith: String = ""

    /// Where the record of each turn is written. Replaceable so a test can
    /// point it somewhere of its own.
    var reportStore: ProblemReportStore = ProblemReportStore.standard

    // MARK: - Computed properties

    /// The tool surface for this window, with the examples naming the real
    /// course rather than a placeholder.
    private var toolDefinitions: [AssistToolDefinition] {
        var named: [AssistToolDefinition] = []
        for definition in tools.definitions {
            named.append(definition.namingTheRealCourse(courseCode))
        }
        return named
    }

    /// Whether a teacher can type right now.
    var isBusy: Bool {
        return activity != .idle
    }

    /// Whether what is waiting is a DEPLOY rather than an ordinary plan.
    ///
    /// The two read differently to a teacher and should look different: a
    /// deploy puts work in front of students and cannot be taken back by us,
    /// while a plan is the assistant checking it understood.
    var pendingIsDeploy: Bool {
        guard let pending = pendingApproval else {
            return false
        }
        return tools.definition(named: pending.call.function.name)?.needsApproval ?? false
    }

    // MARK: - Initializer

    init(courseCode: String,
         sectionNumber: Int,
         client: AssistModelClient,
         tools: AssistToolRunner,
         planMode: AssistPlanMode) {
        self.courseCode = courseCode
        self.sectionNumber = sectionNumber
        self.client = client
        self.tools = tools
        self.planMode = planMode
        messages = [AssistMessage.system(AssistAgent.systemPrompt(course: courseCode, section: sectionNumber))]
        // So that winding a turn back can never reach past the system prompt,
        // even if something were ever to reach `think()` without `say()`.
        messageCountAtTheStartOfTheTurn = messages.count
    }

    // MARK: - Functions

    /// Take what the teacher typed and see it through.
    func say(_ text: String) async {
        // The settings window and this one are open at the same time, so the
        // answer is read fresh rather than remembered from when the
        // conversation started.
        planMode.followTheSetting()

        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return
        }
        // Where this turn starts, so a turn that has to be abandoned can be
        // wound back to exactly here. See `sayTheAnswerDidNotFinish`.
        messageCountAtTheStartOfTheTurn = messages.count
        sentenceThisTurnBeganWith = trimmed
        entries.append(Entry(speaker: .teacher, text: trimmed))

        // Recorded HERE — the moment the teacher's words are accepted, before
        // ANY branch below can decide what happens to them.
        //
        // This sat lower down, just before the message went to the model, and
        // that was wrong twice over. A sentence matching a fixed shape returns
        // early and never reaches the model at all, so a whole class of input
        // left no trace; and an engine that failed, or one still thinking when
        // the teacher gave up, lost the sentence that caused the trouble. The
        // rule the two share: **record what the teacher did where they did it,
        // above every branch, not at any later point that can be skipped.**
        ActivityTrail.note(
            .assistantAsked,
            AssistTurnRecord.askedLines(
                prompt: trimmed,
                courseCode: courseCode,
                sectionNumber: sectionNumber,
                at: Date()
            ),
            wholeLine: true
        )

        // The fixed shapes never reach the model — see AssistCardCommand for
        // the measurement that decided this.
        if let command = AssistCardCommand.matching(trimmed) {
            // Built and SETTLED before the line is written, and then run
            // without being settled again. The order is the whole point: the
            // matcher is clock-free, so "deploy at 6:30 am" arrives here as
            // "06:30" and the day it means does not exist until the settler
            // has run. Writing the line first would record a time with no day
            // on it; settling twice would read the clock twice, which is the
            // bug `withTheDaySettled` exists to prevent.
            let call: AssistToolCall = settled(AssistToolCall(
                id: UUID().uuidString,
                type: "function",
                function: AssistToolCall.Function(
                    name: command.toolName,
                    arguments: encode(command.arguments)
                )
            ))
            // Worth its own line: "why did it not think about what I said?"
            // is answered by this and by nothing else in the trail.
            ActivityTrail.note(
                .assistantMatchedAFixedPhrase,
                AssistAgent.matchedInCodeLine(for: call),
                course: courseCode,
                section: sectionNumber
            )
            await run(settledCall: call)
            return
        }

        // The date goes on the END of the message. Prepended, the same line
        // cost 15 points of routing accuracy on the Windows measurements —
        // the position really is the finding, not the presence.
        messages.append(AssistMessage.user("\(trimmed) \(AssistAgent.dateline(on: tools.today))"))
        await think()
    }

    /// The teacher declined to give their class dates. Said back in the
    /// transcript, so a conversation reads as one somebody took part in.
    func noteDatesDeclined() {
        entries.append(Entry(speaker: .teacher, text: AssistWording.cancelled))
        entries.append(Entry(speaker: .assistant, text: AssistWording.datesNotGivenYet))
    }

    /// Approve the waiting deploy.
    func approvePending() async {
        guard let pending = pendingApproval else {
            return
        }
        // What the teacher chose is part of the history, in their own bubble.
        // Reading back a conversation where the assistant asked and nothing
        // answered — but something plainly happened — is worse than not being
        // able to read it back at all.
        entries.append(Entry(
            speaker: .teacher,
            text: pendingIsDeploy ? AssistWording.deployAccepted : AssistWording.planAccepted
        ))
        pendingApproval = nil
        planMode.recordAccepted()
        await execute(call: pending.call)
    }

    /// Decline the waiting deploy.
    func declinePending() {
        guard let pending = pendingApproval else {
            return
        }
        // Read before the pending call is cleared, because the answer depends
        // on which of the two things was being asked about.
        let wasDeploy: Bool = pendingIsDeploy
        entries.append(Entry(speaker: .teacher, text: AssistWording.cancelled))
        pendingApproval = nil
        activity = .idle
        // A Cancel resets the run of accepted plans. Somebody who has just
        // stopped the assistant doing the wrong thing should not then be
        // asked whether they would like it to stop asking.
        planMode.recordCancelled()
        messages.append(AssistMessage.toolResult(
            callID: pending.call.id,
            name: pending.call.function.name,
            text: "The teacher decided not to. Nothing was done."
        ))
        // A cancelled DEPLOY is answered with the fact and nothing else.
        // "Left as it was — nothing was changed." is true and reassuring about
        // a thing nobody was worried about: a teacher who has just pressed
        // Cancel knows nothing was changed, and being reassured of it reads as
        // the assistant explaining itself. A cancelled PLAN keeps that wording,
        // because there the reassurance is the answer — the plan described
        // changes to pages, and "nothing was changed" is the part in doubt.
        entries.append(Entry(
            speaker: .assistant,
            text: wasDeploy ? AssistWording.deployWasCancelled : AssistWording.planWasCancelled
        ))
    }

    /// Ask the model what to do next, then do it.
    private func think() async {
        activity = .thinking
        let askedAt: Date = Date()
        do {
            let answer: AssistReply = try await client.reply(
                messages: messages, tools: toolDefinitions
            )
            let reply: AssistMessage = answer.message

            // Recorded whatever happens to the turn below: the count of what
            // the model wrote is the evidence that it ran away, and a turn
            // thrown away is exactly the turn somebody reading a problem
            // report needs to see.
            recordTurn(reply: answer, askedAt: askedAt)

            // ABOVE the tool-call branch, because a reply the engine stopped
            // part way is not an instruction and is not something to read out
            // either.
            //
            // What the model was about to write next is unknowable, and for a
            // tool that changes pages the difference between "the four pages
            // you named" and the first four of forty is the whole of what was
            // asked. **Parsing is not the check.** Measured on this Mac
            // (llama.cpp b10435, the smaller assistant): the arguments object
            // is closed before the `</tool_call>` wrapper, so there is a
            // window one or two tokens wide where a generation was stopped
            // short and its arguments nevertheless parse perfectly — a
            // `deploy_section` call cut off at 28 tokens parsed as
            // `{"course": "VVH2O", "section": 1}`. And `undo_last_change`
            // takes no arguments at all, so a call to it cut off before it
            // wrote anything is readable by any check and would simply RUN.
            // The reason the turn ended is the only thing that catches those.
            //
            // The other branch matters just as much: cut off before the tool
            // name was parseable, the same measurement put a raw
            // `<tool_call>\n{\n"name": "publi` fragment in `content`, which
            // the plain-text branch below would print into the transcript.
            if answer.wasCutOff {
                sayTheAnswerDidNotFinish(
                    tool: reply.toolCalls?.first?.function.name, stoppedByTheEngine: true
                )
                return
            }

            if let calls = reply.toolCalls, let first = calls.first {
                // Arguments that cannot be read, with the turn finishing
                // normally: a small model writing bad JSON of its own accord.
                // Same answer — running a call whose arguments were lost means
                // running it against no course, which used to produce a
                // refusal reading as though the teacher's sentence was the
                // problem.
                if !first.argumentsAreReadable {
                    sayTheAnswerDidNotFinish(
                        tool: first.function.name, stoppedByTheEngine: false
                    )
                    return
                }

                // A COURSE that is not this window's, with the answer
                // otherwise perfect: refused here, above everything, so that
                // "no plan twin, no approval card, no tool ran" is true by
                // construction rather than by inspection. Everything that
                // acts on a call is downstream of the line below —
                // `run(call:)` settles it, the approval card holds it, the
                // plan twin runs on it — and a `return` from here reaches
                // none of them.
                //
                // BELOW the two gates above, deliberately. A reply the engine
                // stopped part way can carry a half-written course code (#166
                // measured a `deploy_section` cut off at 28 tokens whose
                // arguments parsed cleanly), and lecturing a teacher about a
                // course the model never finished naming would be a sentence
                // about the wrong thing entirely.
                if let other = courseTheModelNamedInsteadOfThisOne(in: first) {
                    sayTheRequestNamedAnotherCourse(other, tool: first.function.name)
                    return
                }
                messages.append(reply)
                // One tool at a time, on purpose: a model that batches has
                // decided an order, and the order is exactly the reasoning
                // we are trying not to leave with it.
                await run(call: first)
                return
            }

            // The reply IS the question, handed back. Below the tool-call
            // branch by definition — an echo is a reply with no tool call in
            // it — and above the append, because the whole point is that this
            // reply must not reach the history.
            if theReplyIsTheRequestBackAgain(reply) {
                sayItDidNotFollow()
                return
            }

            messages.append(reply)
            let text: String = (reply.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(Entry(
                speaker: .assistant, text: text.isEmpty ? AssistWording.nothingToDo : text
            ))
            activity = .idle
        } catch {
            entries.append(Entry(speaker: .problem, text: error.localizedDescription))
            ActivityTrail.note(
                .assistantCouldNotAnswer,
                "the local AI assistant could not answer — " + error.localizedDescription,
                course: courseCode,
                section: sectionNumber
            )
            activity = .idle
        }
    }

    /// Throw an unfinished answer away, and say so.
    ///
    /// **The whole TURN is wound back, not just the reply.** The reply is not
    /// added to `messages` — a cut-off reply carrying a `tool_call` that no
    /// `tool` message ever answers is a conversation some chat templates
    /// reject outright — and the teacher's sentence goes with it, back to
    /// `messageCountAtTheStartOfTheTurn`.
    ///
    /// Dropping only the reply was the first version, and it made the
    /// assistant's own advice unfollowable. The sentence a teacher reads here
    /// asks them to try again with "a shorter sentence, or fewer pages at a
    /// time" — and the request that ran away was still sitting in the
    /// conversation, so the retry would have been sent with the runaway
    /// sentence still in front of it. The stated reason for dropping the
    /// reply is that it "leaves the history exactly as if the model had not
    /// answered, which is the truth"; that is not what the history says while
    /// the question is still in it. A second lap's read exchange goes too,
    /// which is the same answer: the turn was abandoned, and nothing it did
    /// changed a page (see `AssistWording.answerWasCutOff` for why that is
    /// true on every path that reaches here).
    ///
    /// **The `catch` path below is deliberately NOT wound back**, and has
    /// never been: an engine that could not be reached, or one that timed
    /// out, leaves the teacher's sentence in the conversation. Three reasons
    /// to leave it that way rather than "tidy it up" here. Nothing is being
    /// retried on our advice — that path says the engine failed rather than
    /// asking the teacher to rephrase. The failure is usually the engine
    /// rather than the sentence, so dropping the sentence would lose context
    /// the next turn wants. And `RelativeDayFreshnessTests` reads
    /// `messages` after exactly that path to pin the dateline's POSITION,
    /// which is a measured finding worth 15 points of routing accuracy; the
    /// place that finding is asserted should not be quietly removed by a
    /// change about something else.
    ///
    /// The TEACHER is told the same thing either way — from their side an
    /// answer that ran out of room and one that came out garbled are the same
    /// event, and both are mended by asking again. The TRAIL tells them apart,
    /// because whoever reads a report cannot: an answer stopped at the cap is
    /// a question about how much the model was asked to write, and a finished
    /// answer whose arguments will not parse is a question about the model
    /// itself. Same event, different sentence.
    private func sayTheAnswerDidNotFinish(tool: String?, stoppedByTheEngine: Bool) {
        windTheTurnBack()
        entries.append(Entry(speaker: .assistant, text: AssistWording.answerWasCutOff))
        // The tool it had BEGUN to name, in the words a teacher would
        // recognise rather than the function's own: "it ran away trying to
        // publish" and "it ran away trying to deploy" are different reports.
        // Never what it had begun to WRITE — that is the teacher's page
        // titles.
        var said: String = "the assistant's answer was cut off"
        if stoppedByTheEngine {
            if let name = tool {
                said += " part way through " + AssistAgent.inWords(name)
            } else {
                said += " before it named a tool"
            }
        } else {
            said = "the assistant finished answering but what it wrote for "
                + AssistAgent.inWords(tool ?? "that") + " could not be read"
        }
        ActivityTrail.note(
            .assistantAnswerWasCutOff,
            said + " — nothing was run from it",
            course: courseCode,
            section: sectionNumber
        )
        activity = .idle
    }

    /// Whether the model's whole answer was the teacher's own sentence, given
    /// back to them.
    ///
    /// **Measured, and it is worse than it looks** (issue #215, 2026-09-19,
    /// Qwen2.5-1.5B with the app's own flags and request body, temperature 0,
    /// replayed on two courses and two pages). "hide unit 4, day 21" came back
    /// word for word with the date line still on it and no tool chosen. The
    /// echoed reply was then KEPT in the conversation, and the model copied
    /// the pattern it could see — user says X, assistant says X — so the very
    /// next sentence echoed too, including "Unpublish Unit 4, Day 20", which
    /// the same model answers correctly every time in a fresh window. One
    /// unrecognised phrase made the assistant useless until the window was
    /// closed and opened again.
    ///
    /// **Compared against the message at the START of this turn, not against
    /// the last user message anywhere.** That is what makes a card-matched
    /// second lap safe by construction: on that path the turn begins with a
    /// TOOL RESULT, so this sees no user message and can never fire. Searching
    /// backwards for the most recent user message — the obvious
    /// implementation, and the one a reader of `windTheTurnBack` would reach
    /// for — would compare a read's narration against a sentence from some
    /// earlier turn.
    ///
    /// **Both spellings of the question are compared**: the message as SENT
    /// (with the date line on the end, which is what the measured echo carried)
    /// and the sentence the teacher actually typed. A model that trims the
    /// parenthetical is not a different fault.
    ///
    /// **Exact, modulo case and edge punctuation.** An echo with a preamble
    /// ("Sure: hide unit 4, day 21"), a partial echo, and a reply that poisons
    /// the history some other way all get through. Each of those would need a
    /// similarity measure, and a fuzzy rule that fires on a legitimate answer
    /// is worse than the fault it fixes: it would throw a real answer away and
    /// tell the teacher it did not follow. The one corner this leaves is a
    /// teacher typing a content-free token — "ok", "thanks" — to which the
    /// model replies with the same token. They then read one honest sentence
    /// instead of "ok", and a turn carrying nothing is wound out of a history
    /// it was adding nothing to. Nothing can be lost that way: everything with
    /// state in it (a plan, a deploy, the dates sheet) is a button or a sheet
    /// rather than free text, and `entries` keeps the teacher's own words on
    /// every path.
    private func theReplyIsTheRequestBackAgain(_ reply: AssistMessage) -> Bool {
        guard messageCountAtTheStartOfTheTurn < messages.count else {
            return false
        }
        let began: AssistMessage = messages[messageCountAtTheStartOfTheTurn]
        guard began.role == "user", let asked = began.content else {
            return false
        }
        return AssistAgent.isTheRequestBackAgain(
            sent: asked,
            typed: sentenceThisTurnBeganWith,
            reply: reply.content ?? "",
            hasToolCall: reply.toolCalls?.isEmpty == false
        )
    }

    /// The rule itself, as a pure function of what was sent, what the teacher
    /// typed, what came back, and whether the reply chose a tool.
    ///
    /// Separated from the message bookkeeping above so the contract's own
    /// cases (`assist-cases.json` → `echoedRequest`) can be run straight
    /// against it, on either platform, without a conversation to set up. The
    /// history question — WHICH message counts as "what was sent" — is the
    /// part that is not portable, and it stays above.
    ///
    /// `hasToolCall` is taken rather than assumed, although `think()` only
    /// asks about replies that have none: a reply choosing a tool is an
    /// instruction whatever its text says, and the text beside a tool call is
    /// often the model narrating the request back. A later caller that forgot
    /// that would quietly throw work away.
    static func isTheRequestBackAgain(
        sent: String, typed: String, reply: String, hasToolCall: Bool
    ) -> Bool {
        if hasToolCall {
            return false
        }
        let said: String = forComparing(reply)
        if said.isEmpty {
            return false
        }
        if said == forComparing(sent) {
            return true
        }
        let asTyped: String = forComparing(typed)
        return !asTyped.isEmpty && said == asTyped
    }

    /// Two pieces of text reduced to what they have to share to be the same
    /// sentence.
    ///
    /// Case-folded because the measured echo capitalised the first letter
    /// ("hide…" came back as "Hide…"), and stripped of the punctuation a model
    /// adds or drops at either end. Nothing else is normalised — the date line
    /// ends in a bracket, which neither side touches, so the symmetry holds.
    static func forComparing(_ text: String) -> String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Say that it did not follow, and take the turn back.
    ///
    /// The wind-back is the half that cures the fault rather than reporting
    /// it: the measured failure is not one dead turn, it is every turn after
    /// it. The next request then meets the conversation the model gets right.
    ///
    /// The echoed text is never shown. Handing a teacher their own sentence
    /// back is the fault; repeating it inside an apology would be the same
    /// fault, politely.
    private func sayItDidNotFollow() {
        windTheTurnBack()
        entries.append(Entry(speaker: .assistant, text: AssistWording.didNotFollowThat))
        ActivityTrail.note(
            .assistantRepeatedTheRequestBack,
            "the assistant repeated the request back instead of answering it — nothing was run, "
            + "and the turn was taken back out of the conversation",
            course: courseCode,
            section: sectionNumber
        )
        activity = .idle
    }

    /// Take the whole turn back out of the conversation, down to where it
    /// began.
    ///
    /// Shared by the three places that abandon a turn — an answer that did
    /// not finish, a request that named another course, and a reply that was
    /// the request back again — because they make the same claim about the
    /// history and the three must not drift. What the teacher can SEE is
    /// untouched: `entries` keeps their sentence on every path.
    ///
    /// Two reasons it is the whole turn rather than the reply alone, and both
    /// were learned rather than assumed. A reply carrying a `tool_call` that
    /// no `tool` message ever answers is a conversation some chat templates
    /// reject outright, so the reply cannot stay. And the sentence cannot
    /// stay either once the reply has gone: the model runs at temperature 0,
    /// so a next turn sent with the same sentence still in front of it gets
    /// the same answer, and an assistant that reliably repeats its own
    /// refusal is worse than the fault it replaced.
    private func windTheTurnBack() {
        if messages.count > messageCountAtTheStartOfTheTurn {
            messages.removeLast(messages.count - messageCountAtTheStartOfTheTurn)
        }
    }

    /// The course the model named, when the tool declares one and the code is
    /// not this window's.
    ///
    /// Nil covers four different things, all of which mean "there is nothing
    /// to refuse here": the tool's own schema does not declare `course` (so
    /// the course is not the window's to take back — `undo_last_change`
    /// declares neither argument and is untouched by all of this); the tool
    /// is not one that exists, so there is no schema to ask, and the call
    /// falls through to `run(settledCall:)`'s "There is no tool by that
    /// name."; the model left `course` out; or it wrote something that is not
    /// a non-empty string — a number, a null, an object. The last is the
    /// reason this reads the value ONCE, here, for both the guard and the
    /// fill: `AssistToolRunner.text` reads an `NSNumber` back as a string, so
    /// a `"course": 1` that one function calls absent and another calls
    /// present is a value that survives into a call. Absent, of whatever
    /// kind, means the binder writes this window's code over it.
    private func courseTheModelNamedInsteadOfThisOne(in call: AssistToolCall) -> String? {
        if !theToolDeclares("course", in: call) {
            return nil
        }
        guard let written = call.argumentValues["course"] as? String else {
            return nil
        }
        // `whitespacesAndNewlines`, exactly as `AssistToolRunner.text(_:in:)`
        // trims before `locate` ever sees the value. Trimming less here would
        // refuse `"ICS3U\n"` in an ICS3U window — a lost turn on the
        // teacher's own course, and told about in the wrong words.
        let named: String = written.trimmingCharacters(in: .whitespacesAndNewlines)
        if named.isEmpty || named.lowercased() == courseCode.lowercased() {
            return nil
        }
        return named
    }

    /// Whether this tool's OWN schema declares that argument.
    ///
    /// The one question both the guard and the binder ask, asked in one
    /// place. Gating on the schema rather than on a list of tool names is
    /// what keeps the next tool added from silently getting the wrong rule —
    /// today the schema and a hand-kept list of twelve would agree, which is
    /// exactly when a list looks harmless.
    private func theToolDeclares(_ argument: String, in call: AssistToolCall) -> Bool {
        guard let definition = tools.definition(named: call.function.name) else {
            return false
        }
        return definition.parameters[argument] != nil
    }

    /// Refuse a request that named another course, and say so.
    ///
    /// Nothing ran and nothing can: this is reached from `think()` above the
    /// line that hands the call on, so the plan twin, the approval card and
    /// the tool itself are all downstream of a `return` from here.
    ///
    /// Two sentences, chosen on ONE question — is that code a course in this
    /// working folder? A course that is here can be opened, and the teacher
    /// is told to; a code naming nothing cannot be, and telling them to open
    /// it would send them looking in the sidebar for something that is not
    /// there. Both are refusals either way: binding an invented code to this
    /// window would publish this window's class and report success, which is
    /// the fault the guard exists to remove.
    ///
    /// **`planMode`'s counters are deliberately not touched.** A refusal is
    /// neither an accepted plan nor a cancelled one — nothing was proposed —
    /// so neither `recordAccepted` nor `recordCancelled` belongs here, and
    /// saying so stops it being added later as an oversight.
    private func sayTheRequestNamedAnotherCourse(_ otherCourse: String, tool: String) {
        windTheTurnBack()
        // Named as the FOLDER spells it when the folder has it — a teacher
        // sent to open "mcv4u" is being sent to look for something their
        // sidebar does not show. When the folder does not have it there is
        // nothing else to show, so the model's own text stands (already
        // trimmed), and the other sentence is careful not to tell them to go
        // and open it.
        var said: String = AssistWording.askedAboutACourseThatIsNotHere(
            course: courseCode, otherCourse: otherCourse
        )
        if let known = tools.knownCourseCode(matching: otherCourse) {
            said = AssistWording.askedAboutAnotherCourse(course: courseCode, otherCourse: known)
        }
        entries.append(Entry(speaker: .assistant, text: said))
        // Both course codes and the tool, in the words a teacher would
        // recognise. Never their sentence — `assistantAsked` already has
        // that, on its own marked line — and never the argument values.
        //
        // What the MODEL wrote, deliberately, where the sentence above says
        // what the FOLDER calls it: the trail is evidence about the model, so
        // a code it spelt oddly is worth keeping as it spelt it.
        ActivityTrail.note(
            .assistantWasAskedAboutAnotherCourse,
            "the assistant was asked about " + otherCourse + " in this window, which is for "
                + courseCode + " — nothing was run from it, and it had chosen "
                + AssistAgent.inWords(tool),
            course: courseCode,
            section: sectionNumber
        )
        activity = .idle
    }

    /// A tool's name as somebody reading the trail would say it.
    private static func inWords(_ toolName: String) -> String {
        return toolName.replacingOccurrences(of: "_", with: " ")
    }

    /// Keeps a note of what the model was asked and what it chose.
    ///
    /// Only what the model DECIDED: the tool's name, the names of the
    /// arguments it filled in, how long it took and how many tokens it
    /// wrote. The argument values are the teacher's page titles and are not
    /// part of the routing question.
    private func recordTurn(reply: AssistReply, askedAt: Date) {
        var toolName: String?
        var argumentNames: [String] = []
        var stoppedAtGate: Bool = false
        if let call = reply.message.toolCalls?.first {
            toolName = call.function.name
            argumentNames = AssistTurnRecord.argumentNames(inJSON: call.function.arguments)
            stoppedAtGate = tools.definition(named: call.function.name)?.needsApproval ?? false
        }
        let record: AssistTurnRecord = AssistTurnRecord(
            at: askedAt,
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            toolName: toolName,
            argumentNames: argumentNames,
            seconds: Date().timeIntervalSince(askedAt),
            completionTokens: reply.completionTokens,
            stoppedAtGate: stoppedAtGate
        )
        // Through the trail's own entry point, so this event is named like
        // every other and cannot be the one nobody accounted for.
        ActivityTrail.note(.assistantChoseATool, record.lines, wholeLine: true)
    }

    /// Run a tool, stopping at the gate when it needs one.
    /// The same call, about THIS window's section — and about this window's
    /// course, or the turn was refused before it ever reached here.
    ///
    /// The window is opened for one section and its title says so, yet the
    /// tools take `course` and `section` as arguments and the model fills them
    /// in — which is a question it should never have been asked. Every wrong
    /// answer is a lost turn, and one wrong answer in particular is common
    /// enough to have been reported twice: **"Unpublish Unit 4, Day 12" gets
    /// read as section 4**, and the teacher is told their course has no
    /// Section 4. It is a perfectly reasonable misreading of a page name that
    /// begins with a number, and no amount of describing the argument will
    /// stop it happening on the next page name that does.
    ///
    /// So the SECTION is taken back, present or absent. This is the same
    /// principle as the coarse tools and the boolean-free surface: a fact the
    /// app already knows is not a fact worth asking a model for. It cannot
    /// cost routing accuracy either, since it changes nothing the model reads
    /// — only what is done with what it said. Absent counts, and that is a
    /// change: none of the twelve local tools that take a section reads an
    /// omission as "every section", so a call that left it out used to be
    /// refused by the runner with a complaint that read as though the
    /// teacher's own sentence were the problem.
    ///
    /// **The COURSE is not taken back, and the difference is the point.**
    /// Rewriting it too meant "publish MCV4U's class", typed in an ICS3U
    /// window, succeeding on ICS3U — a failure that reports success, and the
    /// one kind a teacher cannot catch. A call naming a different course is
    /// refused up in `think()` and never arrives here, so by the time this
    /// runs the only course in play is this window's; writing it in is then a
    /// fill rather than an overwrite, and it is written in THIS WINDOW'S
    /// SPELLING so that the approval card a teacher reads before pressing Go
    /// says ICS3U rather than whatever casing the model chose.
    ///
    /// Gated on the TOOL'S OWN SCHEMA, never on a list of tool names: a tool
    /// declaring neither argument — `undo_last_change` — is left exactly as
    /// it came, and so is any future tool, without anybody having to remember
    /// a list.
    ///
    /// Done HERE rather than in the runner, because the runner also answers
    /// Claude Code over MCP, where the course and section are genuinely the
    /// caller's to choose. It is this WINDOW that is about one section.
    private func boundToThisSection(_ call: AssistToolCall) -> AssistToolCall {
        var arguments: [String: Any] = call.argumentValues
        if theToolDeclares("section", in: call) {
            arguments["section"] = sectionNumber
        }
        if theToolDeclares("course", in: call) {
            arguments["course"] = courseCode
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let rewritten = String(data: data, encoding: .utf8) else {
            return call
        }
        return AssistToolCall(
            id: call.id,
            type: call.type,
            function: AssistToolCall.Function(name: call.function.name, arguments: rewritten)
        )
    }

    /// The same call, with "tomorrow" already turned into the date it means.
    ///
    /// **Here, and once.** Everything below reads these arguments more than
    /// once: plan mode runs the `plan_` twin on them, the card holds them
    /// while the teacher decides, and `approvePending` hands the very same
    /// call to `execute`. A relative WORD carried through all of that is read
    /// again at each step, against a clock that has moved — so a plan shown at
    /// 23:59 and agreed to at 00:01 publishes a class the plan never
    /// described. The runner used to be safe from that by freezing its idea of
    /// today when it was built, which bought the agreement and cost the
    /// freshness: a window left open across midnight then resolved "tomorrow"
    /// against the day the conversation BEGAN. Settling the word once, here,
    /// buys both.
    ///
    /// **Against the RUNNER's clock, not the machine's.** A second reading
    /// here would be a second clock in the process — two answers to what
    /// "today" is, differing on one night in a thousand, and no test able to
    /// pin the one the teacher's request actually used.
    ///
    /// This covers the model-routed path as well as the card's. The model is
    /// told to work the date out itself and a small one sometimes sends
    /// `date: "tomorrow"` anyway; it costs no routing accuracy to be ready
    /// for that, because the model sees nothing of what happens here.
    private func withTheDaySettled(_ call: AssistToolCall) -> AssistToolCall {
        guard let definition = tools.definition(named: call.function.name) else {
            return call
        }
        let settled: [String: Any] = AssistToolRunner.settlingTheClassDay(
            in: call.argumentValues, forTool: definition, today: tools.today
        )
        guard let data = try? JSONSerialization.data(withJSONObject: settled),
              let rewritten = String(data: data, encoding: .utf8) else {
            return call
        }
        // The id and the type are the call's identity, not its content: the
        // tool result is matched back to the model's request by `id`.
        return AssistToolCall(
            id: call.id,
            type: call.type,
            function: AssistToolCall.Function(name: call.function.name, arguments: rewritten)
        )
    }

    /// The same call, with a bare clock time turned into the whole moment it
    /// means.
    ///
    /// The sibling of `withTheDaySettled`, and here for the same reason:
    /// the card holds these arguments while the teacher decides, and
    /// `approvePending` hands the very same object to `execute`. The runner's
    /// own clock supplies the DAY, and `Date()` is read in exactly one place —
    /// here — so a card shown at 06:29 and agreed to at 06:31 still names the
    /// minute it named.
    ///
    /// **This covers the model's path too, quietly**, the way the day settler
    /// already does: a model that answers `when: "06:30"` used to meet the
    /// runner's "I could not read that time" and now gets the same reading a
    /// card gets. A model that answers `"6:30"` still meets the refusal — the
    /// settler reads an exact `HH:mm` and nothing looser.
    private func withTheMomentSettled(_ call: AssistToolCall) -> AssistToolCall {
        guard let definition = tools.definition(named: call.function.name) else {
            return call
        }
        let settled: [String: Any] = AssistToolRunner.settlingTheDeployMoment(
            in: call.argumentValues, forTool: definition, today: tools.today, now: Date()
        )
        guard let data = try? JSONSerialization.data(withJSONObject: settled),
              let rewritten = String(data: data, encoding: .utf8) else {
            return call
        }
        return AssistToolCall(
            id: call.id,
            type: call.type,
            function: AssistToolCall.Function(name: call.function.name, arguments: rewritten)
        )
    }

    /// A call ready to be run: bound to this window's section, with a relative
    /// day and a bare clock time already resolved.
    ///
    /// One function rather than three calls in a row at each site, because
    /// "settled" is a state the rest of the agent depends on and a caller that
    /// forgot one of the three would look exactly like a caller that had not.
    ///
    /// Nothing here decides whether a call may run at all: a model call naming
    /// a course that is not this window's is refused in `think()`, above the
    /// line that reaches this, so a settled call is one that was already
    /// allowed.
    private func settled(_ rawCall: AssistToolCall) -> AssistToolCall {
        return withTheMomentSettled(withTheDaySettled(boundToThisSection(rawCall)))
    }

    /// The trail line for a sentence answered in code, naming the tool — and
    /// the MOMENT, when the sentence carried one.
    ///
    /// Named rather than typed where it is asserted, the way every sentence a
    /// teacher reads is. The moment is on the line because it is a guess made
    /// in code: "at 6:30" with no day on it becomes tomorrow morning, and a
    /// teacher who writes in saying "it went out on Saturday, I meant Friday"
    /// leaves a trail that otherwise records their sentence and the tool but
    /// not the day the app chose. The conversation is not on the trail, so
    /// this is the only place the choice is recoverable.
    ///
    /// Only a WHOLE moment is ever added — a value `moment(named:)` can read —
    /// so nothing a teacher wrote, and no half-settled word, can arrive here.
    static func matchedInCodeLine(for call: AssistToolCall) -> String {
        let line: String = "matched in code, not sent to the model — ran " + call.function.name
        guard let when = call.argumentValues["when"] as? String,
              AssistToolRunner.moment(named: when) != nil else {
            return line
        }
        return line + " for " + when
    }

    private func run(call rawCall: AssistToolCall) async {
        await run(settledCall: settled(rawCall))
    }

    /// The question put under an approval card, chosen by the tool the card
    /// is for (issue #184).
    ///
    /// A scheduled deploy gets its own question, because the immediate one
    /// reads as "now" under a card that has just named a later moment. Every
    /// OTHER tool that waits for approval gets `deployQuestion` — chosen by
    /// name rather than by `needsApproval`, so a third approval tool added
    /// later lands on the reading that is safe for anything that deploys:
    /// that it happens now.
    static func approvalQuestion(forToolNamed name: String) -> String {
        if name == "schedule_deploy" {
            return AssistWording.scheduleQuestion
        }
        return AssistWording.deployQuestion
    }

    private func run(settledCall call: AssistToolCall) async {
        guard let definition = tools.definition(named: call.function.name) else {
            messages.append(AssistMessage.toolResult(
                callID: call.id, name: call.function.name,
                text: "There is no tool by that name."
            ))
            await think()
            return
        }

        // Deploying ALWAYS waits for a button: it puts something in front of
        // students immediately and Plantoir cannot take it back for them.
        if definition.needsApproval {
            let explanation: String = tools.explain(call: call)
            entries.append(Entry(speaker: .assistant, text: explanation))
            entries.append(Entry(
                speaker: .assistant,
                text: AssistAgent.approvalQuestion(forToolNamed: call.function.name)
            ))
            pendingApproval = PendingApproval(call: call, explanation: explanation)
            activity = .waitingForApproval
            return
        }

        // In plan mode, so does anything else that changes a page — but the
        // teacher is shown the PLAN rather than the tool's name. Every write
        // has a `plan_` twin that works the change out and changes nothing,
        // so this is the assistant answering "what would that do?" in words
        // before it does it.
        // The twin has to actually exist. Four writes are their own reversal
        // and have none — rebuild_preview changes no page, undo_last_change
        // IS the undo, deploy_section already waits on its own button, and
        // cancelling a scheduled deploy is remedied by scheduling it again.
        // Asking the surface rather than assuming keeps that list in ONE
        // place: without this check, plan mode would ask for a tool that is
        // not there and show the teacher an error where their plan should be.
        if planMode.isOn,
           let twinName = definition.planTwinName,
           tools.definition(named: twinName) != nil {
            await showPlan(twinName: twinName, before: call)
            return
        }

        await execute(call: call)
    }

    /// Run the `plan_` twin and hold the real call behind it.
    ///
    /// The plan is written to be read aloud, so what a teacher sees is
    /// "publishing Unit 2, Day 3 would also publish the four pages it links
    /// to" rather than a tool name and a JSON blob. The model is not asked
    /// again: the same arguments it chose are carried through to the real
    /// call, so what runs on Go is exactly what was described.
    private func showPlan(twinName: String, before call: AssistToolCall) async {
        activity = .running(toolName: twinName)
        let planCall: AssistToolCall = AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(
                name: twinName,
                arguments: call.function.arguments
            )
        )
        let outcome: AssistToolOutcome = await tools.run(call: planCall)

        // The plan is SAID, not shown on a card that is taken away again.
        //
        // It used to live only in the approval card, which meant that the
        // moment a teacher pressed Go or Cancel the description of what they
        // had just agreed to disappeared — and with it the context for
        // everything after. A conversation you cannot scroll back through is
        // not a conversation. So the plan goes into the transcript like any
        // other thing the assistant says, and the card below it is reduced to
        // the two buttons.
        //
        // `forTheCard`, not `detail`: the detail ends with a sentence written
        // for whatever reads a plan on a surface with no Go and Cancel of its
        // own, and this surface has them.
        // A plan twin can come back with a REFUSAL — no such page, no such
        // section — and a refusal is an answer, not a proposal. Asking "Shall
        // I go ahead?" underneath one invites a teacher to approve an
        // explanation of why nothing can be done, which the transcript that
        // prompted this shows them declining four times in a row.
        if !outcome.isPlan {
            entries.append(Entry(speaker: .assistant, text: outcome.summary))
            messages.append(AssistMessage.toolResult(
                callID: call.id, name: call.function.name, text: outcome.detail
            ))
            activity = .idle
            return
        }

        entries.append(Entry(speaker: .assistant, text: outcome.forTheCard))
        // The question is a message too, so the card below can be nothing but
        // the two buttons. A card that carries its own heading is a second
        // voice in a conversation that already has two.
        entries.append(Entry(speaker: .assistant, text: AssistWording.planQuestion))
        pendingApproval = PendingApproval(call: call, explanation: outcome.forTheCard)
        activity = .waitingForApproval
    }

    /// Actually run it, and hand the result back to the model.
    private func execute(call: AssistToolCall) async {
        activity = .running(toolName: call.function.name)
        let outcome: AssistToolOutcome = await tools.run(call: call)

        entries.append(Entry(
            speaker: .toolResult(name: call.function.name),
            text: outcome.summary,
            detail: outcome.teacherDetail
        ))
        messages.append(AssistMessage.toolResult(
            callID: call.id, name: call.function.name, text: outcome.detail
        ))

        // A read hands back to the model so it can answer the question it was
        // reading for. A write is the end of the turn: the teacher asked for
        // something, it happened, and another lap round the model can only
        // invent a follow-up nobody asked for.
        if outcome.shouldContinue {
            await think()
        } else {
            activity = .idle
        }
    }

    private func encode(_ arguments: [String: String]) -> String {
        var payload: [String: Any] = [
            "course": courseCode,
            "section": sectionNumber,
        ]
        for (key, value) in arguments {
            payload[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// Today, in the form the model reads best.
    ///
    /// **Given the day rather than reading one.** This is the other half of
    /// what the model needs to answer "publish the class tomorrow please" —
    /// it does that arithmetic itself, from this sentence — so a dateline
    /// built from its own reading of the clock would be the second clock in
    /// the process that `withTheDaySettled` above says there is not. One
    /// reading, `tools.today`, for both.
    ///
    /// Built from a `CalendarDay` rather than by formatting a `Date`, which
    /// also takes the locale out of it: the previous version asked
    /// `DateFormatter` for `EEEE` with no locale pinned, so a French-locale
    /// Mac would have told the model "a mardi", and a Thai-locale one would
    /// have dated it in the Buddhist calendar — 2569 for 2026. `CalendarDay`
    /// is three integers and `String(format:)`, and its `weekdayName` pins
    /// `en_US_POSIX`. The sentence is unchanged on an English machine, which
    /// is what the routing measurements were made against.
    nonisolated static func dateline(on day: CalendarDay) -> String {
        return "(Today is \(day.text), a \(day.weekdayName).)"
    }

    /// What the model is told it is.
    ///
    /// The publish/deploy paragraph is not padding. The two acts share a word
    /// in ordinary speech and the model will happily conflate them; saying
    /// plainly that they are different is what stops "publish tomorrow's
    /// class" turning into a live site.
    nonisolated static func systemPrompt(course: String, section: Int) -> String {
        return """
        You are Plantoir's assistant, helping a teacher with \(course) section \(section). \
        Choose exactly one tool at a time and fill in its arguments from what the teacher said. \
        Publishing and unpublishing are safe to do straight away — every change is backed up \
        and undo_last_change takes it back — so do what was asked without asking permission first. \
        Never guess a course, a section, a page title or a date — if you are not certain, look it \
        up or ask. If no tool fits, say so plainly instead of inventing one. \
        undo_last_change reverses only the assistant's own most recent action — a \
        teacher describing something THEY did earlier, even calling it a mistake, is \
        asking to publish or unpublish, not to undo. There is no tool to delete, \
        remove or rename a page or a folder — if asked for that, say so plainly \
        instead of choosing a tool that does something else.
        PUBLISHING a page decides whether students can see it in the site. \
        DEPLOYING sends the whole site to the web. They are different acts. \
        After a change, Plantoir opens the preview by itself so the teacher can look it over. \
        Do not offer to deploy unless they ask; when they do ask, say plainly that deploying puts \
        the change in front of students immediately and that reviewing the preview first is the \
        safer order — then do as they decide.
        """
    }
}
