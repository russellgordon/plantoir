using System.Text.Json.Nodes;

namespace Plantoir.Core.Assist;

/// <summary>
/// What running one tool produced, for its two audiences.
///
/// <para><see cref="Summary"/> is the line the teacher reads in the transcript
/// — one sentence, no paths, no counts they did not ask for.
/// <see cref="Detail"/> is what goes back to the model, and can be as long as
/// the answer needs to be.</para>
///
/// <para><b>Why this exists.</b> Until it did, a Windows tool returned ONE
/// string and it was shown to the teacher and fed to the model both. So "read
/// Unit 2, Day 3" put the page's entire Markdown in the chat, "what pages are
/// in this section" put sixty file paths there, and a plan ended with "Show
/// this to the teacher and ask before going ahead" — a sentence addressed to
/// the model, read by the teacher. macOS has never done that: its
/// <c>AssistToolOutcome</c> has carried the two apart since the assistant
/// shipped, which is the whole reason its replies are short. This is that
/// type, in C#.</para>
///
/// <para><b>How the summary travels.</b> The tools run in
/// <c>plantoir-mcp</c>, a separate process, and MCP has one text channel. The
/// summary rides in the result's <c>_meta</c> — the protocol's own extension
/// slot — under <see cref="TeacherSummaryKey"/>. The text content is left
/// exactly as it was, so Claude Code, which reads the detail and writes its
/// own summary, sees no change at all. A tool that says the same thing to
/// both audiences sends no <c>_meta</c>, and the absence IS the answer:
/// <see cref="Same"/> is what a client builds when nothing is there.</para>
/// </summary>
/// <param name="Summary">One line for the transcript, in the teacher's language.</param>
/// <param name="Detail">What the model is told, at whatever length it needs.</param>
/// <param name="IsPlan">
/// Whether this really IS a plan — something that WOULD happen if the teacher
/// agreed.
///
/// A <c>plan_</c> tool can come back with a refusal instead: the page was not
/// found, the section does not exist. Those must not be shown with "Shall I go
/// ahead?" and two buttons underneath, which asks a teacher to approve an
/// explanation of why nothing can be done — and in the mac transcript that
/// prompted the rule, four times in a row.
/// </param>
public sealed record AssistToolAnswer(string Summary, string Detail, bool IsPlan = false,
                                      string? ConversationBackupPath = null, bool NoPageFound = false)
{
    /// <summary>
    /// The <c>_meta</c> key carrying the copy saved before this conversation's
    /// first change. The tools run in a separate process from the window that
    /// shows "Restore Section N…", and the answers are the one channel between
    /// them; every answer after the first change carries it, so the window
    /// can offer the way back without a tool of its own to ask.
    /// </summary>
    public const string ConversationBackupKey = "plantoir.app/conversationBackup";

    /// <summary>
    /// The <c>_meta</c> key the teacher's line travels under. Prefixed with
    /// the product's own domain, as the protocol asks, so it can never
    /// collide with a key some other server or client means something else by.
    /// </summary>
    public const string TeacherSummaryKey = "plantoir.app/teacherSummary";

    /// <summary>
    /// The <c>_meta</c> key saying this answer is a proposal rather than a
    /// report. Sent only when true, because a refusal from a <c>plan_</c> tool
    /// is an ANSWER and must not get Go and Cancel underneath it.
    /// </summary>
    public const string IsPlanKey = "plantoir.app/isPlan";

    /// <summary>
    /// A links question asked about "the quiz" found no page called that, so
    /// it is not answered in code: the window hands the sentence to the model,
    /// which has the conversation to read it against (#305).
    /// </summary>
    public const string NoPageFoundKey = "plantoir.app/noPageFound";

    /// <summary>
    /// The <c>_meta</c> key carrying where a PLAIN "add the next class" would
    /// land (#440): its unit and day, the course's unit word, whether it is
    /// numbered, and its noun — <see cref="AssistNextClassReading.ToJson"/>.
    /// Sent by <c>plan_add_next_class</c> only when it was asked with course
    /// and section alone and could plan; a refusal (no dates, course gone)
    /// carries none. Settler S3 reads it to judge a model's add_next_class
    /// against the teacher's sentence, so the window never parses a sentence
    /// written for the model, and no second planner exists in the window.
    /// </summary>
    public const string NextClassKey = "plantoir.app/nextClass";

    /// <summary>What <see cref="NextClassKey"/> carried, or null. See there.</summary>
    public AssistNextClassReading? NextClass { get; init; }

    /// <summary>The same words to both, which is most tools.</summary>
    public static AssistToolAnswer Same(string both) => new(both, both);

    /// <summary>
    /// An answer from what an MCP result carries: its text (the
    /// <paramref name="detail"/>) and its <c>_meta</c>. ONE reader of every
    /// key above, shared by the window's <c>McpClient</c> and the tests'
    /// in-process servers, so a key added here cannot be read by one and
    /// missed by the other (stack-2 plan review, M1).
    /// </summary>
    public static AssistToolAnswer FromResult(string detail, JsonNode? meta)
    {
        bool isPlan = meta?[IsPlanKey]?.GetValue<bool>() == true;
        string? summary = meta?[TeacherSummaryKey]?.GetValue<string>();
        string? backup = meta?[ConversationBackupKey]?.GetValue<string>();
        bool noPage = meta?[NoPageFoundKey]?.GetValue<bool>() == true;
        var nextClass = AssistNextClassReading.FromJson(meta?[NextClassKey]);
        return string.IsNullOrWhiteSpace(summary)
            ? Same(detail) with { IsPlan = isPlan, ConversationBackupPath = backup, NoPageFound = noPage, NextClass = nextClass }
            : new AssistToolAnswer(summary, detail, isPlan, backup, noPage) { NextClass = nextClass };
    }
}
