import Foundation

/// What running one tool produced.
///
/// Two audiences, deliberately kept apart. `summary` is the line the teacher
/// sees in the transcript — one sentence, no paths, no counts they did not ask
/// for. `detail` is what goes back to the model, and can be as long as the
/// answer needs to be.
///
/// `shouldContinue` is the whole turn-taking rule in one flag. A READ hands
/// back so the model can answer the question it was reading for. A WRITE is the
/// end of the turn: the teacher asked for something, it happened, and another
/// lap round the model can only invent a follow-up nobody asked for. That
/// applies to a write that REFUSED, too — a refusal the model can retry from is
/// a refusal it can retry forever.
struct AssistToolOutcome: Sendable, Equatable {

    // MARK: - Stored properties

    /// One line for the transcript, in the teacher's language.
    let summary: String

    /// What the model is told, at whatever length it needs.
    let detail: String

    /// Whether the model gets another turn after this.
    let shouldContinue: Bool

    /// A longer answer written FOR the teacher, shown by unfolding the result
    /// in the transcript — or nil when the one-line summary is the whole of
    /// what a teacher needs.
    ///
    /// Deliberately not `detail`. That is written for the model and often ends
    /// with instructions addressed to it; showing it would be the same leak
    /// `forTheCard` exists to prevent. Only a tool whose long answer is a
    /// TEACHER's answer fills this in — `check_section`'s list of what is
    /// broken and what is stranded, which is useless as a count and useful as
    /// a list.
    ///
    /// It also gets to be LONGER than what the model sees: the model's copy is
    /// capped so a list of ninety pages does not fill the context before the
    /// question is considered, while the teacher's copy is the whole list,
    /// because a truncated list of what is broken cannot be acted on.
    let teacherDetail: String?

    /// Whether this outcome really IS a plan — something that would happen if
    /// the teacher agreed.
    ///
    /// A plan twin can come back with a refusal instead: the page was not
    /// found, the section does not exist. Those used to be shown with "Shall I
    /// go ahead?" and two buttons underneath, which asks a teacher to approve
    /// an explanation of why nothing can be done — and in the transcript that
    /// prompted this, four times in a row.
    let isPlan: Bool

    /// What a Go/Cancel card shows the teacher.
    ///
    /// The same as `detail` for everything except a PLAN, where `detail` ends
    /// with a sentence addressed to the model — "Nothing has been changed.
    /// Show this to the teacher and ask before going ahead." That sentence is
    /// right where it goes: over MCP, Claude Code has no plan mode and has to
    /// be told to ask. It was WRONG on the card, where it appeared directly
    /// above the Go and Cancel buttons that are the asking, addressed a
    /// teacher as though they were the model, and described machinery.
    ///
    /// The two audiences were always meant to be apart; the card simply reused
    /// the wrong one of them.
    let forTheCard: String

    // MARK: - Initializer

    init(summary: String,
         detail: String,
         shouldContinue: Bool,
         forTheCard: String? = nil,
         teacherDetail: String? = nil,
         isPlan: Bool = false) {
        self.summary = summary
        self.detail = detail
        self.shouldContinue = shouldContinue
        self.forTheCard = forTheCard ?? detail
        self.teacherDetail = teacherDetail
        self.isPlan = isPlan
    }

    // MARK: - Functions

    /// A read: the same words to both, and the model gets to answer.
    ///
    /// `showingTheTeacher` is the longer answer a teacher can unfold in the
    /// transcript, when there is one worth unfolding.
    static func read(_ summary: String,
                     detail: String,
                     showingTheTeacher teacherDetail: String? = nil) -> AssistToolOutcome {
        return AssistToolOutcome(
            summary: summary,
            detail: detail,
            shouldContinue: true,
            teacherDetail: teacherDetail
        )
    }

    /// A PLAN: what would happen if this went ahead, and nothing done yet.
    ///
    /// The plan itself is written for the teacher, because the teacher is who
    /// decides. Only the instruction to ask is added for the model, and only
    /// on its way out — see `forTheCard`.
    ///
    /// `card` is the same plan in the course's own noun (#267) — "meeting"
    /// where a club says it — and goes ONLY on the card. The model reads
    /// `plan`, rendered with "class" whatever the course says, so a club
    /// changes nothing the model is given; nil means the two are the same.
    static func planned(_ summary: String, plan: String, card: String? = nil) -> AssistToolOutcome {
        return AssistToolOutcome(
            summary: summary,
            detail: plan + "\n\n" + AssistToolOutcome.askBeforeGoingAhead,
            shouldContinue: true,
            forTheCard: card ?? plan,
            isPlan: true
        )
    }

    /// Addressed to whatever is reading a plan on a surface with no Go and
    /// Cancel of its own — which means Claude Code over MCP, and never the
    /// teacher.
    static let askBeforeGoingAhead: String =
        "Nothing has been changed. Show this to the teacher and ask before going ahead."

    /// A read answered IN FULL, in code: the teacher has the answer, and the
    /// turn is over (#167).
    ///
    /// Only for a read the model was never asked for. A code-matched turn never
    /// puts the teacher's sentence into the model's conversation, so handing
    /// back would give the model a tool result with no question in front of it
    /// — and on the smaller assistant, the lap that followed is where a
    /// read-only question turned into a publish plan.
    static func answered(_ summary: String, detail: String) -> AssistToolOutcome {
        return AssistToolOutcome(summary: summary, detail: detail, shouldContinue: false)
    }

    /// A write: it happened, and the turn is over.
    static func wrote(_ summary: String, detail: String) -> AssistToolOutcome {
        return AssistToolOutcome(summary: summary, detail: detail, shouldContinue: false)
    }

    /// A write that did not go ahead. The reason is an answer, not a crash:
    /// the teacher reads it and says what to do instead.
    static func refused(_ reason: String) -> AssistToolOutcome {
        return AssistToolOutcome(summary: reason, detail: reason, shouldContinue: false)
    }

    /// A read that could not be answered. Reads hand back either way, so the
    /// model can say plainly what was missing rather than inventing it.
    ///
    /// **Never return this from a tool that has already written anything.**
    /// `shouldContinue: true` is what lets a turn take another lap, and a lap
    /// that comes back cut off winds the whole turn out of the conversation
    /// (`AssistAgent.sayTheAnswerDidNotFinish`) — including this outcome's own
    /// tool result. That is safe today only because a lap can never follow a
    /// write: every write answers `wrote` or `refused`, and the two
    /// `couldNotRead` returns that live inside write-shaped functions
    /// (`backUpCourse`, `makeRoomForClasses`) are pre-write guards. Return it
    /// after a write and the model would lose the record of a change that
    /// really happened, which is exactly what the design promises cannot
    /// occur.
    static func couldNotRead(_ reason: String) -> AssistToolOutcome {
        return AssistToolOutcome(summary: reason, detail: reason, shouldContinue: true)
    }
}
