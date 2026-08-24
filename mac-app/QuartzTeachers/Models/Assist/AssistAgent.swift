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
    private var messages: [AssistMessage] = []

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
            // Worth its own line: "why did it not think about what I said?"
            // is answered by this and by nothing else in the trail.
            ActivityTrail.note(
                .assistantMatchedAFixedPhrase,
                "matched in code, not sent to the model — ran " + command.toolName,
                course: courseCode,
                section: sectionNumber
            )
            await run(call: AssistToolCall(
                id: UUID().uuidString,
                type: "function",
                function: AssistToolCall.Function(
                    name: command.toolName,
                    arguments: encode(command.arguments)
                )
            ))
            return
        }

        // The date goes on the END of the message. Prepended, the same line
        // cost 15 points of routing accuracy on the Windows measurements —
        // the position really is the finding, not the presence.
        messages.append(AssistMessage.user("\(trimmed) \(AssistAgent.dateline())"))
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
            messages.append(reply)
            recordTurn(reply: answer, askedAt: askedAt)

            if let calls = reply.toolCalls, let first = calls.first {
                // One tool at a time, on purpose: a model that batches has
                // decided an order, and the order is exactly the reasoning
                // we are trying not to leave with it.
                await run(call: first)
                return
            }

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
    /// The same call, but about THIS window's course and section whatever the
    /// model said.
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
    /// So the argument is taken back. This is the same principle as the coarse
    /// tools and the boolean-free surface: a fact the app already knows is not
    /// a fact worth asking a model for. It cannot cost routing accuracy either,
    /// since it changes nothing the model reads — only what is done with what
    /// it said.
    ///
    /// Done HERE rather than in the runner, because the runner also answers
    /// Claude Code over MCP, where the course and section are genuinely the
    /// caller's to choose. It is this WINDOW that is about one section.
    private func boundToThisSection(_ call: AssistToolCall) -> AssistToolCall {
        var arguments: [String: Any] = call.argumentValues
        if arguments["course"] != nil || arguments["section"] != nil {
            arguments["course"] = courseCode
            arguments["section"] = sectionNumber
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

    private func run(call rawCall: AssistToolCall) async {
        let call: AssistToolCall = boundToThisSection(rawCall)
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
            entries.append(Entry(speaker: .assistant, text: AssistWording.deployQuestion))
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
    nonisolated static func dateline() -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let day: DateFormatter = DateFormatter()
        day.dateFormat = "EEEE"
        let now: Date = Date()
        return "(Today is \(formatter.string(from: now)), a \(day.string(from: now)).)"
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
