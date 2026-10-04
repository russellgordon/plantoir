using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// The model half of a conversation: given the messages so far and the tool
/// schemas, one reply. LocalModel implements it over llama.cpp; the tests
/// implement it with a script, which is what lets every promised task be
/// exercised in milliseconds instead of a teacher's afternoon.
/// </summary>
public interface IChatModel
{
    /// <summary>
    /// One reply, and WHY the engine stopped writing it — or null when the
    /// engine could not be reached or timed out.
    /// </summary>
    Task<ModelReply?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation);
}

/// <summary>
/// What the model wrote, and the engine's <c>finish_reason</c> for stopping.
/// </summary>
/// <remarks>
/// <para><b>The reason is the only signal that tells a finished answer from a
/// fragment</b> (#196). Every request carries <c>max_tokens</c> 512, so a reply
/// can be stopped part way — and llama.cpp closes the arguments object before
/// the tool-call wrapper, so for a token or two a stopped call PARSES
/// perfectly (measured on the mac: cut at 28 tokens, <c>deploy_section
/// {course, section}</c>). <c>undo_last_change</c> takes no arguments at all,
/// so any parse check would pass a stopped call to it. Until 2026-09-30
/// <c>LocalModel.Ask</c> returned <c>choices[0].message</c> and dropped the
/// rest, so this app acted on a stopped reply as if it were finished.</para>
///
/// <para>A null <see cref="FinishReason"/> means the engine did not say, which
/// is read as finished — the scripted test models build replies that way.</para>
/// </remarks>
public sealed record ModelReply(JsonObject Message, string? FinishReason = null, int? CompletionTokens = null)
{
    /// <summary>The engine stopped because it reached the cap, not because the answer was done.</summary>
    public bool WasCutOff => string.Equals(FinishReason, "length", StringComparison.OrdinalIgnoreCase);

    /// <summary>A finished reply from a message alone; null stays null.</summary>
    public static implicit operator ModelReply?(JsonObject? message) => message is null ? null : new ModelReply(message);
}

/// <summary>
/// The tool half: run one tool, return what it said, narrate through
/// <paramref name="progress"/> along the way. McpClient implements it over
/// stdio to plantoir-mcp.
///
/// The answer comes back in two halves — see <see cref="AssistToolAnswer"/>.
/// It used to be one string, shown to the teacher and sent to the model both,
/// and that single fact is why this app's replies read longer than the mac's.
/// </summary>
public interface IToolServer
{
    Task<AssistToolAnswer> CallTool(string name, JsonObject arguments,
                                    Action<string>? progress = null,
                                    CancellationToken cancellation = default);
}

/// <summary>
/// The conversation loop: what the teacher said, what the model decided, what
/// the tools did, and back again.
///
/// The shape is dictated by one measured finding — **the model is a router,
/// not a planner**. Given fine-grained tools and asked to publish a class "and
/// everything it links to", it chose the publish tool and skipped the link
/// resolution eight times out of eight. Given one coarse tool that resolves
/// links itself, it was right eight times out of eight. So this loop is
/// deliberately thin: it does not decompose the request, does not plan, and
/// does not retry cleverly. It carries messages between a teacher and a set of
/// tools that already know how to do the work.
///
/// The safety rules are not enforced here either — they are enforced by the
/// tools, and by there being no destructive tool to reach for. What this loop
/// adds is the one thing tools cannot: **nothing deploys to students without
/// the teacher pressing a button.** Everything short of a deploy runs
/// freely, because the tools make it reversible — backed up, undoable, and
/// invisible to students until that button.
/// </summary>
public sealed class AssistAgent
{
    private readonly IChatModel _model;
    private readonly IToolServer _tools;
    private readonly JsonArray _schemas;
    private readonly JsonArray _messages = new();

    /// <summary>
    /// The tools the LOCAL model is shown, and only those.
    ///
    /// Measured, not guessed. On five tools the routing was 27/27; on the
    /// shipped surface it fell to 31/45, and the failures were exactly the
    /// phrasings a teacher uses — "put up Unit 3, Day 2", "take Unit 4, Day 5
    /// back down" both fell through to list_pages. There are 26 tools now, so
    /// it would be worse again, and the definitions come to some 6,200 tokens
    /// that must be re-read at 21 tokens a second whenever the cache is cold.
    ///
    /// Both problems have the same cause and the same fix. Fewer tools is
    /// better routing AND a shorter prompt: accuracy and speed are not a
    /// trade-off here, they are the same dial.
    ///
    /// So the local model gets the handful of things teachers actually ask for
    /// day to day. Everything else — rolling a course over, re-dating a term,
    /// making room in a unit, scheduling a deploy, curriculum matching — stays
    /// available to Claude Code, which drives the same server and has no
    /// trouble with 26 tools. Nothing is removed; this narrows one client's
    /// view.
    /// </summary>
    internal static readonly HashSet<string> ForTheLocalModel = new(StringComparer.OrdinalIgnoreCase)
    {
        // Finding your way about.
        "list_pages", "read_page", "check_section",
        // Publishing a class, which is the commonest request by a wide margin.
        "publish_class_on",
        // Publishing and unpublishing pages by name.
        "publish_pages", "unpublish_pages",
        // Seeing the result, and taking it back.
        "rebuild_preview", "undo_last_change",
        // Putting it in front of students, now or at half six tomorrow.
        //
        // Kept deliberately, against the pressure to trim. Deploying is the
        // act a teacher most wants help with at the moment they want it —
        // "the class starts in ten minutes" — and it was asked for by name.
        // The safety is not in withholding the tool: the approval gate stops
        // every one of these until a button is pressed, and the tool's own
        // description tells the assistant to send the teacher to the preview
        // first.
        "deploy_section", "schedule_deploy", "cancel_scheduled_deploy",
        // Timetable and next class.
        "read_remembered_timetable", "add_next_class",
    };

    /// <summary>
    /// Arguments the SERVER declares and the local model must not be shown,
    /// as <c>tool.argument</c>.
    ///
    /// <para><b>Why a tool can have an argument its own model may not see.</b>
    /// <c>duplicate</c> exists because Plantoir's window sends the card's
    /// arguments to this server over JSON-RPC and the binder DROPS a key the
    /// method does not declare — so "duplicate Unit 3, Day 2 as my next class"
    /// silently made a blank page until the parameter was added (issue #149).
    /// It is filled by <see cref="AssistCardCommand"/>, in code, from a
    /// sentence matched in code. No model fills it, and no model should:
    /// <c>add_next_class</c> IS one of the thirteen tools the local model
    /// routes to, and every extra argument on a tool it already picks is a
    /// chance to invent a page title for a request that named none.</para>
    ///
    /// <para>The mac has the same aim and reaches it differently, which is
    /// worth knowing before "fixing" either: there the card and the tool
    /// runner share a process, so no binder stands between them and
    /// <c>duplicate</c> is simply absent from the published schema. There is
    /// no schema to narrow because there is no schema.</para>
    ///
    /// <para>MIRRORED in <c>research/ai-assist/narrow-tools.py</c> and pinned
    /// by <c>NarrowToolsMirrorTests</c>, for the reason the tool list is: a
    /// routing score measured through a surface the app does not ship is worse
    /// than no score.</para>
    /// </summary>
    internal static readonly HashSet<string> CardOnlyArguments = new(StringComparer.Ordinal)
    {
        "add_next_class.duplicate",
        "plan_add_next_class.duplicate",
        // "What does <page> link to?" (#305 / mac #167): filled in code by
        // the links phrasing; the mac keeps answer: "links" out of every
        // schema, and this is that, on a server whose binder needs it declared.
        "read_page.answer",
        "read_page.asTyped",
        "read_page.onlyIfFound",
    };

    /// <summary>
    /// Narrow a tool list to what the local model should see.
    ///
    /// A tool NOT in the set is not hidden from the teacher — they can ask for
    /// it, and the assistant will say it cannot do that here rather than
    /// silently doing something else. That is the better failure: the tools it
    /// does have are the ones it routes to reliably.
    ///
    /// The schemas' example course becomes THIS window's course, because the
    /// model copies examples: asked to publish with no course named, it wrote
    /// the schema's "for example ICS3U" nine trials out of nine, ignoring the
    /// system prompt's answer — and once even blended the two into ICS2O.
    /// A router matches text; the only example it cannot get wrong is the
    /// right answer. Measured after the change: fifty-four trials, not one
    /// wrong course.
    /// </summary>
    public static JsonArray NarrowToLocal(JsonArray tools, string courseCode)
    {
        var kept = new JsonArray();
        foreach (var tool in tools)
        {
            if (tool?["function"]?["name"]?.GetValue<string>() is not { } name) continue;
            if (!ForTheLocalModel.Contains(name)) continue;

            var copy = tool.DeepClone();
            if (copy["function"]?["description"]?.GetValue<string>() is { } description)
                copy["function"]!["description"] =
                    (StillShortened.Contains(name) ? Briefly(description) : description).Replace(ExampleCourse, courseCode);
            MakeExamplesReal(copy["function"]?["parameters"], courseCode);
            HideCardOnlyArguments(copy["function"]?["parameters"], name);
            kept.Add(copy);
        }
        return kept;
    }

    /// <summary>
    /// Take the card-only arguments out of one tool's schema — from
    /// <c>properties</c> AND from <c>required</c>, since a required key that
    /// is not described is a schema no model can satisfy.
    /// </summary>
    private static void HideCardOnlyArguments(JsonNode? parameters, string toolName)
    {
        if (parameters is not JsonObject schema) return;

        foreach (string pair in CardOnlyArguments)
        {
            int dot = pair.IndexOf('.');
            if (dot < 0) continue;
            // Case-insensitively, because ForTheLocalModel matches tool names
            // that way and two answers to "is this that tool" is how an
            // argument stays visible to the router by accident.
            if (!string.Equals(pair[..dot], toolName, StringComparison.OrdinalIgnoreCase)) continue;
            string argument = pair[(dot + 1)..];

            if (schema["properties"] is JsonObject properties) properties.Remove(argument);
            if (schema["required"] is JsonArray required)
            {
                for (int i = required.Count - 1; i >= 0; i--)
                    if (required[i]?.GetValue<string>() == argument) required.RemoveAt(i);
            }
        }
    }

    /// <summary>The course code the server's schemas use in their examples.</summary>
    private const string ExampleCourse = "ICS3U";

    private static void MakeExamplesReal(JsonNode? node, string courseCode)
    {
        switch (node)
        {
            case JsonObject fields:
                if (fields["description"]?.GetValue<string>() is { } text &&
                    text.Contains(ExampleCourse, StringComparison.Ordinal))
                    fields["description"] = text.Replace(ExampleCourse, courseCode);
                // Snapshotted, because replacing a description mid-walk would
                // otherwise be mutation during enumeration.
                foreach (var field in fields.ToList()) MakeExamplesReal(field.Value, courseCode);
                break;
            case JsonArray items:
                foreach (var item in items) MakeExamplesReal(item, courseCode);
                break;
        }
    }

    /// <summary>
    /// The tools whose description the local model still reads SHORTENED
    /// (#352, 2026-10-01). Every other tool is shown its description as served,
    /// which since #352 is the contract's one description per tool
    /// (assist-cases.json → toolDescriptions) — measured before and after on
    /// this PC's tier with no regression and no polarity inversion
    /// (research/ai-assist/windows-description-convergence-results.txt).
    /// These two keep their Windows text, shortened. They were held first for
    /// behaviour (#352: Windows' includeLinked defaulted to false, so the
    /// contract's sentences were untrue here); #420 step (a) made the
    /// behaviour match on 2026-10-01, and step (b) then MEASURED the move to
    /// the contract text and it failed its pre-registered criteria on this
    /// PC's tier (an unpublish_pages trial lost on the hide-inversion probe,
    /// research/ai-assist/windows-description-convergence-results.txt, the
    /// #420 section). So they stay, recorded as contracts/assist-cases.json →
    /// toolDescriptions.measuredDepartures with those numbers — a PERMANENT
    /// measured departure by Russell's decision (2026-10-01; #420 closed). It
    /// changes only with a new pre-registered measurement. The held text's
    /// untrue "optionally" and its stray "section's website" fragment stay for
    /// the same reason.
    /// </summary>
    internal static readonly HashSet<string> StillShortened = new(StringComparer.Ordinal)
    {
        "publish_pages", "unpublish_pages",
    };

    /// <summary>
    /// The part of a tool description a ROUTER needs, and no more. Since #352
    /// applied only to <see cref="StillShortened"/>.
    ///
    /// The descriptions are written for Claude Code, and most of their length
    /// is instruction: plan before you write, tell the teacher what it said,
    /// wait for them to agree, this takes several minutes. None of that is
    /// guidance the local model has to be trusted to follow, because none of
    /// it is enforced by the model — the approval gate in this class holds
    /// every write until the teacher presses a button, whatever the model
    /// believes it is doing.
    ///
    /// What a router does need is WHEN to pick this tool. So: the phrasings
    /// teachers use, and the first sentence saying what it does. Measured, the
    /// full surface was some 9,000 tokens of definitions; this and the tool
    /// list together bring what the local model reads down to a fraction of
    /// that, and the prompt is what makes a cold first answer slow.
    /// </summary>
    private static string Briefly(string description)
    {
        var kept = new List<string>();

        // The trigger phrasings, which are the most useful line for routing
        // and are deliberately written first.
        int endOfPhrasings = description.IndexOf("\". ", StringComparison.Ordinal);
        if (description.StartsWith("TEACHERS SAY:", StringComparison.Ordinal) && endOfPhrasings > 0)
        {
            kept.Add(description[..(endOfPhrasings + 2)]);
            description = description[(endOfPhrasings + 3)..];
        }

        // Then one sentence of what it actually does.
        int firstStop = description.IndexOf(". ", StringComparison.Ordinal);
        kept.Add(firstStop > 0 ? description[..(firstStop + 1)] : description);

        return string.Join(" ", kept).Trim();
    }

    /// <summary>
    /// Whether this call has to be shown to the teacher before it runs.
    ///
    /// Only deploying waits for a button, because deploying is the only act
    /// students ever notice. Everything else the assistant can reach is
    /// reversible by construction — validated against the working folder,
    /// backed up before it writes, behind undo_last_change — and a publish
    /// flag changes nothing a student can see until a deploy. Gating every
    /// one of those turned a conversation into a row of button presses, and
    /// the teacher asked for it to stop.
    ///
    /// A SCHEDULED deploy is approved when it is scheduled — that yes is what
    /// the button collects. The firing itself asks nobody, which is the whole
    /// point of scheduling it.
    /// </summary>
    internal static readonly HashSet<string> DeploysToStudents = new(StringComparer.OrdinalIgnoreCase)
    {
        "deploy_section", "schedule_deploy",
    };

    /// <summary>
    /// Whether this call waits for a button. Public because the WINDOW asks
    /// it too: a deploy's card offers "Deploy" where a plan's offers "Go",
    /// and a deploy set for half six tomorrow is still a deploy.
    /// </summary>
    public static bool NeedsApproval(string name) => DeploysToStudents.Contains(name);

    /// <summary>
    /// The <c>plan_</c> twin of each write the assistant can reach — what it
    /// runs, and reads out, before it does the thing itself.
    ///
    /// This is the CONFIRMATION setting's machinery. Deploying always waits
    /// for a button; everything else waits only while the teacher has "ask
    /// before changing" on, which it is by default. What they see is the
    /// PLAN, in words — "publishing Unit 2, Day 3 would also publish the four
    /// pages it links to" — never a tool name and a blob of arguments. The
    /// model is not asked a second time: the arguments it chose are carried
    /// through to the real call, so what runs on Go is exactly what was
    /// described.
    ///
    /// Four writes have no twin, deliberately: <c>rebuild_preview</c> changes
    /// no page, <c>undo_last_change</c> IS the remedy, <c>deploy_section</c>
    /// waits on its own button whatever this setting says, and a cancelled
    /// scheduled deploy is remedied by scheduling it again.
    ///
    /// <para><b>"The local model can reach" is the wrong test, and reading it
    /// that way left a hole.</b> A FIXED PHRASING reaches a tool no model is
    /// shown — <c>AssistCardCommand</c> matches the sentence in code and
    /// <c>RunCommand</c> consults this map exactly as a routed call does. So
    /// <c>make_room_for_classes</c> belongs here even though it is MCP-only:
    /// it is the most dangerous tool on the surface, renaming pages a
    /// teacher's links point at, and without the entry it would have been the
    /// ONE card that ran with no plan shown first. The mac never had this gap
    /// because it derives twins from its tool surface rather than listing
    /// them; a hand-written list has to be told.</para>
    /// </summary>
    internal static readonly Dictionary<string, string> PlanTwins = new(StringComparer.OrdinalIgnoreCase)
    {
        ["publish_pages"] = "plan_publish_pages",
        ["unpublish_pages"] = "plan_unpublish_pages",
        ["publish_class_on"] = "plan_publish_class_on",
        ["add_next_class"] = "plan_add_next_class",
        ["remember_timetable"] = "plan_remember_timetable",
        ["re_date_classes"] = "plan_re_date_classes",
        ["make_room_for_classes"] = "plan_make_room_for_classes",
        // Irregular, as the mac's AssistToolDefinition.irregularPlanTwins says:
        // the twin is NOT plan_ + the write's name, and deriving it that way is
        // how add_curriculum_mentions ran with no plan on the mac (#327 / #350).
        ["add_curriculum_mentions"] = "plan_curriculum_mentions",
    };

    /// <summary>
    /// How many tool calls one turn may make before the loop stops.
    ///
    /// A small model that has lost the thread repeats itself rather than
    /// stopping, and a runaway loop against a teacher's course is the failure
    /// nobody would forgive. Reading, planning and then acting is three.
    /// </summary>
    private const int MostStepsPerTurn = 6;

    private readonly string _courseCode;

    /// <summary>
    /// The window's course's page word when that course is NUMBERED (a club's
    /// "Week"), else null — so the numbered make-room phrasing matches only
    /// there (#274). Set by the window, which has the course.
    /// </summary>
    public string? NumberedPageWord { get; init; }
    private readonly int _section;

    public AssistAgent(IChatModel model, IToolServer tools, JsonArray schemas, string courseCode, int section)
    {
        _model = model;
        _tools = tools;
        _schemas = schemas;
        _courseCode = courseCode;
        _section = section;
        _messages.Add(new JsonObject
        {
            ["role"] = "system",
            ["content"] = SystemPrompt(courseCode, section),
        });
    }

    /// <summary>
    /// The system prompt, exposed because it is part of the cached prefix:
    /// the window fingerprints it alongside the schemas, so a wording change
    /// here retires stale caches honestly instead of restoring a prefix no
    /// conversation will match.
    ///
    /// It no longer says plan-first-and-wait. Publishing and unpublishing run
    /// without ceremony now — backed up, undoable, and invisible to students
    /// until a deploy — and the deploy gate is a button this class enforces,
    /// not a behaviour the model has to be trusted to follow.
    /// </summary>
    public static string SystemPrompt(string courseCode, int section) =>
        $"You are Plantoir's assistant, helping a teacher with {courseCode} section {section}. " +
        "Choose exactly one tool at a time and fill in its arguments from what the teacher said. " +
        "Publishing and unpublishing are safe to do straight away — every change is backed up " +
        "and undo_last_change takes it back — so do what was asked without asking permission first. " +
        "Never guess a course, a section, a page title " +
        "or a date — if you are not certain, look it up or ask. " +
        "If no tool fits, say so plainly instead of inventing one. " +
        // Measured 2026-08-24 (research/ai-assist/conversational-residue-results.txt):
        // without these two sentences the model routed "I posted X by mistake, make
        // it a draft again" to undo_last_change instead of unpublish (undo is for the
        // ASSISTANT's own last action, not something the teacher did earlier), and
        // "hide tomorrow's class again — the page is X" sometimes declined outright.
        // Adding both sentences fixed both clusters and raised conversational routing
        // accuracy from 85% to 91-94% across two runs, with no new misses elsewhere.
        // A version that also named cancel_scheduled_deploy explicitly (to fix the
        // still-unsolved "delete the X folder" probe) made two unrelated cases regress
        // — kept out for exactly the reason AssistToolRunner.localTools's doc comment
        // gives: a small model reads an extra clause as new signal, not a boundary.
        "undo_last_change reverses only the assistant's own most recent action — a " +
        "teacher describing something THEY did earlier, even calling it a mistake, is " +
        "asking to publish or unpublish, not to undo. There is no tool to delete, " +
        "remove or rename a page or a folder — if asked for that, say so plainly " +
        "instead of choosing a tool that does something else.\n" +
        // Two words that sound alike and are not. The teacher gets this
        // explained once per section by explain_publishing; the model
        // needs it every turn, because it is the distinction it is
        // likeliest to collapse.
        "PUBLISHING a page decides whether students can see it in the site. " +
        "DEPLOYING sends the whole site to the web. They are different acts. " +
        "After a change, Plantoir opens the preview by itself so the teacher can look it over. " +
        "Do not offer to deploy unless they ask; when they do ask, say plainly that " +
        "deploying puts the change in front of students immediately and that reviewing " +
        "the preview first is the safer order — then do as they decide.";

    /// <summary>
    /// A throwaway exchange shaped EXACTLY like a real one, for warming the
    /// prompt cache.
    ///
    /// The system message has to be in it. Warming with just the tools and a
    /// stray "Say ready" primes a prefix no real turn ever uses: llama.cpp
    /// renders the tools and the system prompt into the same leading block, so
    /// a conversation that carries a system message diverges from that warm-up
    /// almost at the first token and re-reads everything.
    ///
    /// That is not a small waste. It is the difference between the three
    /// minutes buying every later answer, and buying nothing at all — measured
    /// as a 75-second wait for the word "Hi" AFTER a warm-up had finished.
    ///
    /// Called before any real turn, so this is the system message alone plus
    /// one short user line, which is the shortest thing shaped like the real
    /// prefix.
    /// </summary>
    public JsonArray PrimingMessages()
    {
        var priming = new JsonArray();
        foreach (var message in _messages)
            if (message is not null) priming.Add(message.DeepClone());
        priming.Add(new JsonObject { ["role"] = "user", ["content"] = "Hello." });
        return priming;
    }

    /// <summary>
    /// What "assistant chose a tool" carries (#164; <c>shared-rules.json</c> →
    /// <c>activityTrail.mustRecord</c>): the tool, the argument NAMES, the
    /// seconds, the completion tokens and whether it waited for the button.
    /// NAMES, never values: which tool with which arguments filled in answers
    /// the routing question completely, and the values are a teacher's page
    /// titles. The names are what tell "duplicate Unit 3, Day 2 as my next
    /// class" from a plain "add the next class" — the same tool either way.
    /// </summary>
    internal static string ChoseAToolLine(string tool, JsonObject call, TimeSpan took, int? tokens, bool waited) =>
        $"the assistant chose {tool.Replace('_', ' ')} {WithArguments(ArgumentsOf(call).Select(pair => pair.Key))}, " +
        "in " + took.TotalSeconds.ToString("0.0", CultureInfo.InvariantCulture) + " s, " +
        (tokens is { } n ? n.ToString(CultureInfo.InvariantCulture) + " tokens" : "tokens not reported") + ", " +
        (waited ? "waiting for the teacher's button" : "without waiting for a button");

    /// <summary>"with course, section, pages" — argument names only, in the order given.</summary>
    internal static string WithArguments(IEnumerable<string> names)
    {
        var listed = names.ToList();
        return listed.Count == 0 ? "with no arguments" : "with " + string.Join(", ", listed);
    }

    /// <summary>
    /// Whether a word is a course code that EXISTS in the shipped course
    /// lists (Ontario and British Columbia). Set by the window from the same
    /// catalogs the New Course wizard reads; used only to tell "in SPH3U" (a
    /// course) from "in Lab01" (part of a page's name) in a links question.
    /// </summary>
    public Func<string, bool>? IsACourseCode { get; set; }

    /// <summary>
    /// "What does &lt;page&gt; link to?", answered in code and in full (#305 /
    /// mac #167). TRANSCRIPT ONLY: a code-matched turn never puts the
    /// teacher's sentence into the model's conversation, so handing the
    /// answer back would give the model a tool result with no question in
    /// front of it, which is the lap on which the smaller assistant turned
    /// this read-only question into a publish plan. Every branch ends the
    /// turn; the one exception is "the quiz" when no page is called that,
    /// which goes to the model as the sentence it was.
    /// </summary>
    private async Task<List<Line>?> LinksQuestion(string text, CancellationToken cancellation)
    {
        if (AssistCardCommand.LinksQuestion(text, _courseCode, _section, IsACourseCode) is not { } asked) return null;

        if (asked.OtherCourse is { } other)
        {
            ActivityTrail.Note(ActivityTrail.Event.AssistantWasAskedAboutAnotherCourse,
                $"matched in code, not sent to the model \u2014 asked what a page links to in {other} in this " +
                $"{_courseCode} window; nothing was read", _courseCode, _section);
            string? here = CoursesInTheFolder()
                .FirstOrDefault(code => code.Equals(other, StringComparison.OrdinalIgnoreCase));
            string? kept = ReferenceCourseNamed(other);
            return new List<Line>
            {
                new("assistant", kept is not null ? AssistWording.AskedAboutAReferenceCourse(_courseCode, kept)
                    : here is not null
                    ? AssistWording.AskedAboutAnotherCourse(_courseCode, here)
                    : AssistWording.AskedAboutACourseThatIsNotHere(_courseCode, other)),
            };
        }

        var arguments = new JsonObject
        {
            ["course"] = _courseCode,
            ["section"] = _section,
            ["page"] = asked.Page,
            ["answer"] = "links",
        };
        if (asked.AsTyped is { } typed) arguments["asTyped"] = typed;
        if (asked.OnlyIfAPageIsCalled) arguments["onlyIfFound"] = "yes";

        var answer = await _tools.CallTool("read_page", arguments, OnToolProgress, cancellation);
        if (answer.NoPageFound) return null;   // "the quiz": the model has the conversation to read it against

        ActivityTrail.Note(ActivityTrail.Event.AssistantMatchedAFixedPhrase,
            "matched in code, not sent to the model \u2014 ran read_page " + WithArguments(arguments.Select(pair => pair.Key)),
            _courseCode, _section);
        return new List<Line> { new("tools", answer.Summary) };
    }

    /// <summary>A line for the transcript.</summary>
    public sealed record Line(string Speaker, string Text, bool NeedsApproval = false, string? Pending = null);

    /// <summary>
    /// The promise card — what the window tells a teacher this assistant is
    /// good at, in the wordings that work. It lives HERE, beside the loop
    /// that keeps the promises, because the tests pin the two together:
    /// every task on this card has a test proving the loop does its part.
    /// Each line is a shape the local model routes reliably, and naming the
    /// page ("Unit 2, Day 3") is what keeps it from having to guess — so the
    /// examples all show it.
    /// </summary>
    public const string ExampleRequests =
        "Here's what I'm good at. These wordings work well — copy one and change the details:\n\n" +
        "**Publishing a class**\n" +
        "  • Publish Unit 2, Day 3, and everything it links to\n" +
        "  • Publish tomorrow's class\n\n" +
        "**Taking something back down**\n" +
        "  • Unpublish Unit 2, Day 3\n" +
        "  • I published Unit 4, Day 1 by mistake — unpublish it\n\n" +
        "**Looking before you leap**\n" +
        "  • What would publishing Unit 3, Day 1 change?\n" +
        "  • What would students see in this section right now?\n\n" +
        "**Afterwards**\n" +
        "  • Rebuild the preview\n" +
        "  • Undo that\n\n" +
        "**Putting it in front of students**\n" +
        "  • Deploy this section now\n" +
        "  • Deploy tomorrow's class at 6:30 AM\n" +
        "  • Cancel that scheduled deploy\n\n" +
        "Deploying is the one that students actually notice, so I'll always ask you to look at the " +
        "preview first — and you press the button, not me.\n\n" +
        "Name the page if you can — “Unit 2, Day 3” rather than “tomorrow's one” — and I'll be quicker " +
        "and more certain. Bigger jobs — re-dating a term, rolling a course over, adding a unit's worth " +
        "of pages — are beyond me, and want one of the more capable assistants in the same right-click " +
        "menu.";

    /// <summary>
    /// Where a running tool's own narration goes — the toolchain's milestone
    /// lines, relayed by the server as progress. A rebuild can spend minutes
    /// recreating its container and reinstalling the toolchain before it
    /// builds anything; without these lines that time is indistinguishable
    /// from a hang. May be called from any thread.
    /// </summary>
    public Action<string>? OnToolProgress { get; set; }

    /// <summary>
    /// The app, not the server, owns building and deploying — the assistant
    /// AUTOMATES Plantoir rather than duplicating it.
    ///
    /// The first live test did it the other way: rebuild_preview built in the
    /// server's own container run, invisible, while the chat showed dots —
    /// and finished with the result sitting on disk where nobody could see
    /// it. The main window already knows how to build a section with its
    /// console on screen and the preview in view — and, on Windows, it comes
    /// forward only when it was minimised or hidden, because the teacher may
    /// still be typing in the assistant's own window (a chosen divergence
    /// from the mac; see MainWindow.ComeForwardIfHidden). So rebuild_preview
    /// and deploy_section never reach the server from here: they press
    /// Plantoir's own buttons. The server keeps those tools for
    /// the clients that have no window — Claude Code, and deploys scheduled
    /// for half six in the morning.
    /// </summary>
    public Action? ShowPreviewInApp { get; set; }

    /// <summary>Deploy through the main window's own flow, console and all. Any thread.</summary>
    public Action? StartDeployInApp { get; set; }

    /// <summary>
    /// Async version of StartDeployInApp that AWAITS the deploy's real
    /// outcome and returns the sentence to say — success, failure, or a
    /// multi-destination partial — computed by
    /// <see cref="MultiDestinationDeployRunner.Result"/> from what actually
    /// happened. A null return means the deploy never actually ran (refused,
    /// already busy, or an exception before it started) — RunTool falls back
    /// to <see cref="AssistWording.DeployDidNotFinish"/>, never to the
    /// unconditional "Deployed" this replaced, because reporting success by
    /// default is exactly the bug this delegate exists to close.
    /// </summary>
    public Func<Task<string?>>? StartDeployInAppAsync { get; set; }

    /// <summary>Check if the section is currently busy.</summary>
    public Func<bool>? SectionIsBusy { get; set; }

    /// <summary>
    /// Whether THIS copy of the app is deploying this very section (#386 /
    /// mac #381, layer <c>assistant</c>): asked before the assistant opens a
    /// preview, so the conversation never says the preview is on its way
    /// while the window refuses it. Answered with
    /// <see cref="AssistWording.SectionIsBeingDeployed"/>.
    /// </summary>
    public Func<bool>? SectionIsBeingDeployed { get; set; }

    private bool ThisSectionIsBeingDeployed() => SectionIsBeingDeployed?.Invoke() == true;

    private string SectionIsBeingDeployedSentence =>
        AssistWording.SectionIsBeingDeployed(_courseCode, _section.ToString());

    /// <summary>
    /// Whether this section's preview is on screen right now, asked of the
    /// window. It decides what a page edit must do about the preview: the
    /// served site is a COPY, merged at build time, so a running preview
    /// never notices an edit to the course folder on its own — the teacher
    /// unpublished a page, watched the preview, and nothing changed.
    /// </summary>
    public Func<bool>? PreviewIsShowing { get; set; }

    /// <summary>
    /// Stop the section's preview in the main window. A page edit does what
    /// a person would do: stop the preview, change the files, start the
    /// preview again. No server-side build, no live-reload cleverness — the
    /// served site is a merged COPY that never notices course-folder edits,
    /// so the only honest preview is a restarted one.
    /// </summary>
    public Action? StopPreviewInApp { get; set; }

    /// <summary>Async version of StopPreviewInApp.</summary>
    public Func<Task>? StopPreviewInAppAsync { get; set; }

    /// <summary>
    /// Whether the assistant asks before changing anything. Defaults to true.
    /// Read fresh every turn so a change in Settings takes effect immediately.
    /// </summary>
    public Func<bool> ConfirmationMode { get; set; } = () => true;

    /// <summary>
    /// This class's ONE clock: today, read when it is needed rather than
    /// stored.
    /// </summary>
    /// <remarks>
    /// <para>A function rather than a date because a window stays open longer
    /// than a calendar day, and a stored "today" would answer "publish
    /// tomorrow's class" against the day the conversation BEGAN — a wrong day
    /// that reports success. <c>PlantoirTools.Today</c> on the server is the
    /// same shape for the same reason.</para>
    ///
    /// <para><b>One clock, not two.</b> Everything in this class that needs a
    /// day asks this: the dateline the model reasons from, the scheduled
    /// deploy a card sets up, the card's own relative word, and
    /// <see cref="WithTheDaySettled"/>. Two clocks in one conversation is two
    /// answers to what today is, differing on one night in a thousand, with no
    /// test able to pin the one a teacher's request actually used — the mac
    /// met exactly that in an earlier draft of its own settler.</para>
    /// </remarks>
    public Func<DateOnly> Today { get; init; } = () => DateOnly.FromDateTime(DateTime.Now);

    /// <summary>
    /// The wall clock, for the one thing a day cannot answer: whether a time
    /// of day is still to come TODAY (#193). Read only by
    /// <see cref="WithTheMomentSettled"/>, together with <see cref="Today"/>.
    /// </summary>
    public Func<DateTime> Now { get; init; } = () => DateTime.Now;

    /// <summary>The zone the wall clock is in — the machine's own, unless a test says otherwise.</summary>
    public TimeZoneInfo TimeZone { get; init; } = TimeZoneInfo.Local;

    /// <summary>Invoked whenever a pending plan/write action is accepted by the teacher.</summary>
    public Action? OnPlanAccepted { get; set; }

    /// <summary>
    /// The copy saved before this conversation's first change, the moment an
    /// answer first names it. The window shows "Restore Section N…" from
    /// then on. Any thread.
    /// </summary>
    public Action<string>? OnConversationBackup { get; set; }

    /// <summary>
    /// Given the moment a scheduled card asks for, when the deploy it would
    /// REPLACE is set for — or null when there is none to mention (#261).
    /// The window answers it from <c>TaskScheduling.MomentItWouldReplace</c>,
    /// which reads by task name across the whole computer.
    /// </summary>
    public Func<DateTime, DateTime?>? ScheduleDeployItWouldReplace { get; set; }

    /// <summary>Provides the human-readable destination for publishing/deploying (e.g. "Netlify", "Cloudflare Pages", "a folder on this computer").</summary>
    public Func<string>? DestinationProvider { get; set; }

    /// <summary>
    /// Tools that change pages. They run on the server as pure file edits —
    /// <c>preview: false</c>, so the server builds nothing — and then the
    /// app's own preview is put on screen to show what changed.
    /// </summary>
    private static readonly HashSet<string> EditsPages = new(StringComparer.OrdinalIgnoreCase)
    {
        "publish_pages", "unpublish_pages", "publish_class_on", "undo_last_change",
        "re_date_classes", "roll_over_section", "sync_page_dates",
        "add_next_class", "add_classes", "make_room_for_classes", "add_curriculum_mentions",
    };

    /// <summary>
    /// Tools that must always start a preview in Plantoir after finishing their work,
    /// even if a preview was not previously active.
    /// </summary>
    private static readonly HashSet<string> AlwaysStartsPreview = new(StringComparer.OrdinalIgnoreCase)
    {
        "re_date_classes", "roll_over_section",
    };

    /// <summary>The page-editing tools that accept a preview flag to decline the server's build.</summary>
    private static readonly HashSet<string> TakesPreviewFlag = new(StringComparer.OrdinalIgnoreCase)
    {
        "publish_pages", "unpublish_pages", "publish_class_on",
    };

    private JsonObject? _awaiting;      // a write the teacher has not agreed to yet

    /// <summary>
    /// Every tool the SERVER serves — the full surface, not the narrowed list
    /// the model is shown. Set by the window from the server's own listing.
    ///
    /// <para>It exists for one refusal (#350 / mac #327): a name that is on
    /// this list and NOT on the list the model was shown is refused, nothing
    /// runs and the turn is wound back. The server answers Claude Code as
    /// well, so it serves every tool either client may call; before this, a
    /// model that named <c>re_date_classes</c> — kept off its list because
    /// re-dating a whole section is too big for a router right four times in
    /// five — simply had it run. Null (the tests' default) means "not told",
    /// and then nothing is refused, because a refusal decided from a list the
    /// agent was never given would be a guess.</para>
    ///
    /// <para>A name that exists NOWHERE is unchanged: it goes to the server
    /// and comes back as "no tool by that name", for the model to read.
    /// Refusing those too was rejected on the mac — it changes documented
    /// behaviour for no failure anyone has seen. Fixed phrasings never come
    /// through here, so a tool only a card reaches keeps working.</para>
    /// </summary>
    public IReadOnlyCollection<string>? ServedTools { get; set; }

    /// <summary>The names on the list the model was shown.</summary>
    private HashSet<string> OfferedTools() => new(
        _schemas.Select(tool => tool?["function"]?["name"]?.GetValue<string>())
                .Where(name => name is not null)!,
        StringComparer.OrdinalIgnoreCase);

    /// <summary>Whether <paramref name="name"/> exists here but was not shown to the model.</summary>
    internal bool WasNotOffered(string name) =>
        ServedTools is { } served &&
        served.Contains(name, StringComparer.OrdinalIgnoreCase) &&
        !OfferedTools().Contains(name);

    public bool IsAwaitingApproval => _awaiting is not null;
    public string? PendingTool => _awaiting?["function"]?["name"]?.GetValue<string>();

    /// <summary>
    /// Say something to the assistant and get back everything that happened.
    ///
    /// The date rides along on every user turn, because the model has no
    /// other way to know it and "publish tomorrow's class" is the request
    /// this window exists for — without it, every trial fabricated a date
    /// from the schema's examples (2023-09-15, in 2026).
    ///
    /// APPENDED, not prepended, and not in the system prompt. Prepended, the
    /// date crowds out the request: measured routing fell from 91% to 76%,
    /// with "deploy at 6:30 tomorrow" answered by a publish tool. In the
    /// system prompt it would sit ahead of the tool definitions and
    /// invalidate the saved prompt cache every midnight. Appended, routing
    /// measured 94% and every date came out right.
    ///
    /// Only what the MODEL sees carries it; the window shows the teacher
    /// their own words.
    /// </summary>
    public async Task<List<Line>> Say(string text, CancellationToken cancellation)
    {
        ActivityTrail.NotePrompt(text, _courseCode, _section);

        if (PreviewAskedForPlainly(text) is { } handled) return handled;
        if (await CardCommand(text, cancellation) is { } commanded) return commanded;

        // "deploy at 6:30" — morning or evening, and nobody can tell which
        // (#281). Asked in code; and "deploy at 6.30 pm" — a time the family
        // reads but does not set — answered with the spelling to use (#288).
        // Both go into the TRANSCRIPT ONLY. Appending either to the model's
        // conversation "for context" passes every wording test and lets the
        // model act on the time a turn later: measured, every such sentence
        // reached deploy_section 10 of 10 on the smaller assistant. Nothing is
        // set and nothing waits; the sentence named matches in code next turn.
        if (AssistCardCommand.MorningOrEvening(text) is { } question)
        {
            ActivityTrail.Note(ActivityTrail.Event.AssistantMatchedAFixedPhrase,
                "matched in code, not sent to the model — asked whether the time was morning or evening; nothing was set",
                _courseCode, _section);
            return new List<Line> { new("assistant", AssistWording.MorningOrEvening(question)) };
        }
        // "schedule a deploy" with no time (#424): never a deploy now, and
        // never the model, which sent this shape of sentence to deploy_section
        // 10 of 10 on this PC. Asked in code, transcript only, as above.
        if (AssistCardCommand.AsksToScheduleWithNoTime(text))
        {
            ActivityTrail.Note(ActivityTrail.Event.AssistantMatchedAFixedPhrase,
                "matched in code, not sent to the model — asked what time to schedule the deploy for; nothing was set",
                _courseCode, _section);
            return new List<Line> { new("assistant", AssistWording.ScheduleADeployNeedsATime) };
        }
        if (AssistCardCommand.TimeToSayAs(text) is { } respelling)
        {
            ActivityTrail.Note(ActivityTrail.Event.AssistantMatchedAFixedPhrase,
                "matched in code, not sent to the model — asked for the time in a spelling it can set; nothing was set",
                _courseCode, _section);
            return new List<Line> { new("assistant", AssistWording.SayTheTimeAs(respelling)) };
        }

        // InvariantCulture, and this class's one clock. A machine whose
        // default calendar is not Gregorian renders "yyyy" in ITS year —
        // 2569 for Thai Buddhist — so an affected teacher's assistant would
        // be told the wrong year on every single message, in the one sentence
        // it does all its date arithmetic from. Byte-identical on a Gregorian
        // machine, which is what keeps the routing measurements standing.
        // (The writer half of that trap is issue #144.) DayOfWeek is an enum
        // name and carries no culture of its own.
        _turnBeganAt = _messages.Count;
        _typedThisTurn = text;
        var today = Today();
        _dateline = string.Create(CultureInfo.InvariantCulture,
            $" (Today is {today:yyyy-MM-dd}, a {today.DayOfWeek}.)");
        _sentThisTurn = text + _dateline;
        _messages.Add(new JsonObject
        {
            ["role"] = "user",
            ["content"] = _sentThisTurn,
        });
        return await Run(cancellation);
    }

    /// <summary>
    /// The promise card's shapes, answered as COMMANDS rather than routing
    /// questions.
    ///
    /// Measured against the card, word for word, the model failed five of
    /// its eleven promises outright — "Publish Unit 2, Day 3, and everything
    /// it links to" went to the publish-by-date tool three trials out of
    /// three, "Deploy this section now" never once reached the deploy tool,
    /// and bare "Undo that" was declined every time. These phrasings are the
    /// ones the window itself tells teachers to use; a promise the router
    /// keeps three times out of four is not a promise. Each fixed shape is
    /// matched here and the tool call synthesised exactly — same gates, same
    /// stop-edit-offer flow, and instant, because no model is consulted.
    /// The model keeps everything these patterns do not match, which is
    /// everything genuinely conversational.
    /// </summary>
    private async Task<List<Line>?> CardCommand(string text, CancellationToken cancellation)
    {
        if (await LinksQuestion(text, cancellation) is { } answered) return answered;

        // The links family is answered ONLY by LinksQuestion above, which reads
        // the window. When that declined — another section, a title that is
        // this window's own place, "the quiz" with no such page — the sentence
        // belongs to the model; Matching's window-free reading of the same
        // sentence must not run it as a card, or the answer (and a tool call)
        // lands in the model's conversation (review finding, 2026-09-30).
        if (AssistCardCommand.Matching(text, NumberedPageWord) is { } match && !match.IsALinksQuestion)
        {
            var cardArguments = match.ToJsonObject(_courseCode, _section, Today());
            // "deploy at 6:30 am" carries a time of day, never a date: the
            // moment is settled HERE, once, so the card, the trail line and
            // the act all carry the same one (#193).
            string? moment = SettleTheMoment(cardArguments);
            ActivityTrail.Note(
                ActivityTrail.Event.AssistantMatchedAFixedPhrase,
                "matched in code, not sent to the model — ran " + match.ToolName +
                (moment is null ? "" : " for " + moment) +
                " " + WithArguments(match.Arguments.Keys),
                _courseCode,
                _section);

            if (match.ToolName.Equals("deploy_section", StringComparison.OrdinalIgnoreCase) ||
                match.ToolName.Equals("schedule_deploy", StringComparison.OrdinalIgnoreCase))
            {
                // No card for a deploy that cannot happen (#241): the refusal
                // is said instead of a question it would then take back.
                if (CourseIsKeptForReference())
                {
                    string refused = AssistWording.DeployRefusedForAReferenceCourse(_courseCode);
                    _messages.Add(new JsonObject { ["role"] = "user", ["content"] = text });
                    _messages.Add(new JsonObject { ["role"] = "assistant", ["content"] = refused });
                    return new List<Line> { new("assistant", refused) };
                }
                return AskFirst(text, match.ToolName, cardArguments);
            }
            if (match.ToolName.Equals("rebuild_preview", StringComparison.OrdinalIgnoreCase) && ShowPreviewInApp is not null)
            {
                string said = ThisSectionIsBeingDeployed()
                    ? SectionIsBeingDeployedSentence
                    : "The preview is opening in Plantoir's main window — the build shows its progress there.";
                if (!ThisSectionIsBeingDeployed()) ShowPreviewInApp.Invoke();
                _messages.Add(new JsonObject { ["role"] = "user", ["content"] = text });
                _messages.Add(new JsonObject { ["role"] = "assistant", ["content"] = said });
                return new List<Line> { new("assistant", said) };
            }

            // The card settles its own relative word at match time, and it is
            // handed this class's clock to settle it against rather than
            // reading one of its own.
            return await RunCommand(text, match.ToolName,
                                    match.ToJsonObject(_courseCode, _section, Today()), cancellation);
        }

        string request = text.Trim().TrimEnd('.', '!');

        var withLinks = System.Text.RegularExpressions.Regex.Match(request,
            @"^(?<verb>publish|unpublish)\s+(?<title>.+?),?\s+and everything it links to$",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        var planned = System.Text.RegularExpressions.Regex.Match(request,
            @"^what would publishing\s+(?<title>.+?)\s+change\??$",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        var scheduled = System.Text.RegularExpressions.Regex.Match(request,
            @"^deploy tomorrow'?s class at\s+(?<hour>\d{1,2})(:(?<minute>\d{2}))?\s*(?<half>am|pm)$",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);

        static bool Dated(string title) =>
            title.Contains("tomorrow", StringComparison.OrdinalIgnoreCase) ||
            title.Contains("today", StringComparison.OrdinalIgnoreCase);

        if (withLinks.Success && !Dated(withLinks.Groups["title"].Value))
        {
            string tool = withLinks.Groups["verb"].Value.StartsWith("un", StringComparison.OrdinalIgnoreCase)
                ? "unpublish_pages" : "publish_pages";
            // "…and everything it links to" is what every publish does since
            // #420; the phrasing is still answered, with the same call.
            return await RunCommand(text, tool, PageArguments(withLinks.Groups["title"].Value),
                                    cancellation);
        }
        // The old "publish|unpublish Unit N, Day M" shape lived here and was
        // deleted in bundle 5a's fix round. It was LOOSER than the contract:
        // measured against hideIsUnpublish.refused (#432) it took four refused
        // spellings ("publish unit 4,day 3", doubled spaces in three places).
        // Both verbs are AssistCardCommand's now — HideOrUnpublish, and
        // UnitAndDay for the exact "publish unit N, day M" (#411/#432).
        if (planned.Success && !Dated(planned.Groups["title"].Value))
            return await RunCommand(text, "plan_publish_pages",
                                    PageArguments(planned.Groups["title"].Value),
                                    cancellation);
        if (scheduled.Success)
        {
            int hour = int.Parse(scheduled.Groups["hour"].Value);
            int minute = scheduled.Groups["minute"].Success ? int.Parse(scheduled.Groups["minute"].Value) : 0;
            if (scheduled.Groups["half"].Value.Equals("pm", StringComparison.OrdinalIgnoreCase) && hour < 12) hour += 12;
            if (scheduled.Groups["half"].Value.Equals("am", StringComparison.OrdinalIgnoreCase) && hour == 12) hour = 0;
            // Same clock and same culture as the dateline above: this one is a
            // date the app WRITES, into a scheduled deploy that fires while
            // nobody is watching.
            string when = string.Create(CultureInfo.InvariantCulture,
                $"{Today().AddDays(1):yyyy-MM-dd} {hour:00}:{minute:00}");
            return AskFirst(text, "schedule_deploy", new JsonObject
            {
                ["course"] = _courseCode,
                ["section"] = _section,
                ["when"] = when,
            });
        }
        return null;
    }

    private JsonObject PageArguments(string title) => new()
    {
        ["course"] = _courseCode,
        ["section"] = _section,
        ["pages"] = new JsonArray(JsonValue.Create(TidyTitle(title))),
    };

    /// <summary>Quotes off, "Unit 2, Day 3" capitalised the way pages are titled.</summary>
    private static string TidyTitle(string title)
    {
        title = title.Trim().Trim('"', '“', '”', '\'');
        return System.Text.RegularExpressions.Regex.Replace(title, @"^unit\s+(\d+),\s*day\s+(\d+)$",
            m => $"Unit {m.Groups[1].Value}, Day {m.Groups[2].Value}",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
    }

    /// <summary>
    /// A synthesised tool call, recorded in the transcript exactly as if the
    /// model had made it — the assistant message carries the call, the tool
    /// message carries the result — so a later, genuinely conversational
    /// turn reads a history that makes sense.
    /// </summary>
    private JsonObject Synthesise(string userText, string tool, JsonObject arguments)
    {
        var call = new JsonObject
        {
            ["id"] = $"command-{_messages.Count}",
            ["type"] = "function",
            ["function"] = new JsonObject
            {
                ["name"] = tool,
                ["arguments"] = arguments.ToJsonString(),
            },
        };
        _messages.Add(new JsonObject { ["role"] = "user", ["content"] = userText });
        _messages.Add(new JsonObject
        {
            ["role"] = "assistant",
            ["tool_calls"] = new JsonArray(call.DeepClone()),
        });
        return call;
    }

    private async Task<List<Line>> RunCommand(string userText, string tool, JsonObject arguments,
                                              CancellationToken cancellation)
    {
        var call = Synthesise(userText, tool, arguments);

        // A fixed phrasing skips the MODEL, not the teacher's confirmation.
        // "Publish Unit 2, Day 3, and everything it links to" is matched in
        // code because the router gets it wrong, which is not a reason to
        // stop showing what it would do.
        if (ConfirmationMode() && PlanTwins.TryGetValue(tool, out string? twin))
            return await ShowPlan(twin, call, cancellation);

        var lines = new List<Line>();
        var answer = await RunTool(call, lines, cancellation);
        lines.Add(new Line("tools", answer.Summary));
        TurnEnded(lines);   // the offer, when the command edited pages
        return lines;
    }

    internal List<Line> AskFirst(string userText, string tool, JsonObject arguments)
        => AskFirst(Synthesise(userText, tool, arguments));

    /// <summary>
    /// Hold a deploy behind the button, saying first what it is a deploy OF.
    ///
    /// A scheduled deploy used to get the bare question and nothing else — a
    /// teacher was asked "Shall I go ahead?" about a time and a section
    /// neither of them had said out loud. It gets the same treatment the
    /// immediate deploy has always had: the fact, then the question.
    /// </summary>
    private List<Line> AskFirst(JsonObject call)
    {
        _awaiting = call;
        string tool = call["function"]?["name"]?.GetValue<string>() ?? "";
        // Chosen by the tool's NAME, not by "needs approval" (#260): a
        // scheduled card names a moment that is not now, and "Shall I
        // deploy?" reads as now. A third approval tool falls to the "now"
        // question, which is the safe reading for a deploy.
        string question = tool.Equals("schedule_deploy", StringComparison.OrdinalIgnoreCase)
            ? AssistWording.ScheduleQuestion
            : AssistWording.DeployQuestion;
        return new List<Line>
        {
            new("assistant", Explain(call)),
            new("assistant", question, NeedsApproval: true, Pending: tool),
        };
    }

    /// <summary>
    /// Explain what an approval card is asking for.
    ///
    /// Neither of these restates the request. The act itself is named by the
    /// question that follows, and the section is on the window's own title
    /// bar; a card that describes a tool is a card describing machinery.
    /// </summary>
    private string Explain(JsonObject call)
    {
        string tool = call["function"]?["name"]?.GetValue<string>() ?? "";
        if (!tool.Equals("schedule_deploy", StringComparison.OrdinalIgnoreCase))
            return AssistWording.DeployApproval;

        var arguments = ArgumentsOf(call);
        string when = arguments["when"]?.GetValue<string>() ?? "";
        // ONE reader, shared with the server that actually schedules it —
        // see ScheduledDeploy.ReadTheMoment. This card and that tool read
        // the same string, and a card that names a different moment than
        // the thing it authorises is worse than a card that says nothing.
        string moment = ScheduledDeploy.ReadTheMoment(when) is { } parsed
            ? parsed.ToString("dddd d MMMM, h:mm tt")
            : when;
        string destination = DestinationProvider?.Invoke() ?? "the web";
        // #261: scheduling a section that already has one REPLACES it, and
        // until now nothing said so before or after.
        string replaces = ScheduleDeployItWouldReplace?.Invoke(ScheduledDeploy.ReadTheMoment(when) ?? DateTime.MinValue)
            is { } was
            ? " " + AssistWording.ScheduleReplaces(was.ToString("dddd d MMMM, h:mm tt"))
            : "";
        return $"Set this computer to deploy {_courseCode} Section {_section} to {destination} at {moment}. " +
               "It has to be on and awake then — plugged in if it is a laptop, lid open. " +
               "Plantoir cannot wake it up." + replaces;
    }

    /// <summary>A tool call's arguments, which arrive as a JSON string.</summary>
    private static JsonObject ArgumentsOf(JsonObject call)
    {
        if (call["function"]?["arguments"]?.GetValue<string>() is not { } raw) return new JsonObject();
        try { return JsonNode.Parse(raw) as JsonObject ?? new JsonObject(); }
        catch { return new JsonObject(); }
    }

    // ---- Rewriting what the model filled in ------------------------------

    /// <summary>
    /// Let <paramref name="rewrite"/> change one tool call's arguments, and
    /// put them back on the call.
    /// </summary>
    /// <remarks>
    /// <para>The round trip every rewrite at this seam needs, written once:
    /// the arguments are a JSON STRING inside the call, so changing one means
    /// parse, edit, re-serialise. <see cref="WithTheDaySettled"/> is the first
    /// of these and is not expected to be the last — binding the model's
    /// <c>course</c> and <c>section</c> to the window's own is the next
    /// (issue #180), and it belongs here beside it rather than parsing the
    /// same string a second time.</para>
    ///
    /// <para>Anything it cannot read it leaves exactly as it arrived: a small
    /// model sends malformed JSON often enough that <see cref="ArgumentsOf"/>
    /// and <c>RunTool</c> both already defend against it, and a rewrite is
    /// the last place that should be the one to throw.</para>
    ///
    /// <para>The call is changed IN PLACE and returned, for chaining. That is
    /// safe: the message history holds its own deep clone of the model's
    /// reply, taken before this runs, so nothing rewrites what the model is
    /// shown next turn.</para>
    ///
    /// <para><b><paramref name="rewrite"/> returns whether it changed
    /// anything, and nothing is written back when it did not.</b> So a call
    /// this leaves alone is byte-for-byte the string the model sent, rather
    /// than a re-serialisation of it, and "untouched" means untouched in a
    /// test as well as in meaning. A rewrite that changes something and says
    /// it did not would have that change dropped — which is the trade for
    /// that property, and is why the flag is the rewrite's own business
    /// rather than a comparison made out here.</para>
    ///
    /// <para><b>A rewrite that DOES change something re-serialises the
    /// whole object</b>, and a JSON round trip is not text-preserving:
    /// whitespace goes, key order follows the object, and non-ASCII escapes
    /// (a page title's curly quotes become <c>\uXXXX</c>). Harmless, because
    /// every consumer parses the string rather than reading it — but a test
    /// that compares arguments TEXTUALLY after a rewrite will differ, and
    /// should compare the parsed values instead.</para>
    /// </remarks>
    private static JsonObject WithArgumentsRewritten(JsonObject call, Func<JsonObject, bool> rewrite)
    {
        if (call["function"] is not JsonObject function) return call;
        if (function["arguments"] is not JsonValue raw || !raw.TryGetValue(out string? json)) return call;

        // Blank arguments are an EMPTY call, not an unreadable one: the
        // window supplies course and section, and whether an empty call may
        // run at all is decided before this (#262).
        JsonObject? arguments;
        if (string.IsNullOrWhiteSpace(json)) arguments = new JsonObject();
        else
        {
            try { arguments = JsonNode.Parse(json) as JsonObject; }
            catch { return call; }
        }
        if (arguments is null) return call;

        if (rewrite(arguments)) function["arguments"] = arguments.ToJsonString();
        return call;
    }

    /// <summary>
    /// Turn a relative day the MODEL filled in — <c>date: "tomorrow"</c> —
    /// into the date it means, ONCE, where the call is created.
    /// </summary>
    /// <remarks>
    /// <para>The card path settles its own word at match time
    /// (<c>AssistCardCommand.ToJsonObject</c>). This is the other path: a
    /// <c>date</c> the model wrote itself, which <c>ClassDateHelp</c> tells it
    /// not to write relatively and which a small model does anyway. One call
    /// object is then read three times — the approval card, the <c>plan_</c>
    /// twin, and the act the teacher presses Go on — and each of those used to
    /// reach the server's <c>DayFor</c>, which reads the clock per call. A plan
    /// shown at 23:59 and agreed to at 00:01 described one class and published
    /// the next. Settled here, the three carry the same argument BY
    /// CONSTRUCTION, and the clock may then be read as freely as it likes.</para>
    ///
    /// <para><b>The gate asks the tool surface, and what it really tracks is
    /// WHAT CONSULTS THE CLOCK.</b> A tool is touched only if its own schema
    /// declares a <c>date</c> property, so a list kept beside this code cannot
    /// fall behind the tools. Today that is exactly <c>publish_class_on</c>,
    /// whose <c>date</c> goes to <c>PlantoirTools.DayFor</c> — the one place a
    /// relative word is read against the clock. <c>schedule_deploy</c>'s
    /// <c>when</c> is a day AND a time and declares no <c>date</c>, so it is
    /// excluded by construction rather than by being remembered.
    /// <c>publish_pages</c> and <c>unpublish_pages</c> take <c>before</c> and
    /// <c>onOrAfter</c>, which reach <c>ParseDate</c> — strict, invariant, and
    /// it REFUSES "tomorrow" — so they consult no clock and want no settling.
    /// The trap to know: a future forgiving parser behind one of those names
    /// would reopen this hole with the gate shut, because the gate is spelled
    /// <c>date</c> and the exposure is not. <c>TheSettlerTouchesExactlyTheToolsDeclaringADate</c>
    /// makes that at least a visible decision.</para>
    ///
    /// <para>A word the reader cannot make a day of — "next monday", which is
    /// refused rather than guessed — passes through untouched, so the tool
    /// answers with its own sentence about it. An absolute date settles to
    /// itself. A <c>date</c> that is not a string at all (a model that sends
    /// <c>20260920</c> as a number) passes through untouched too, rather than
    /// throwing where nothing would catch it.</para>
    ///
    /// <para>Nothing the model SEES changes: no schema, no description, no
    /// <c>ClassDateHelp</c>. It has already chosen the tool by the time this
    /// runs, so no routing re-measurement is owed.</para>
    /// </remarks>
    private JsonObject WithTheDaySettled(JsonObject call)
    {
        if (call["function"]?["name"]?.ToString() is not { } name) return call;
        if (!DeclaresAClassDay(name)) return call;

        return WithArgumentsRewritten(call, arguments =>
        {
            if (arguments["date"] is not JsonValue given || !given.TryGetValue(out string? word)) return false;
            if (SectionScheduleSource.ReadRelativeDay(word, Today()) is not { } day) return false;

            // InvariantCulture: the tool must not be sent looking for a class
            // on a day no course has — see the dateline above.
            string settled = day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            if (settled == word) return false;

            arguments["date"] = settled;
            return true;
        });
    }

    /// <summary>
    /// The same settling for a <c>when</c> the MODEL wrote — "06:30" from a
    /// model is the same trap as "06:30" from a card (#193): read as today,
    /// silently, by the server's lenient reader. Gated on the tool declaring
    /// <c>when</c>. A whole moment, or anything the settler cannot read, is
    /// left exactly as the model wrote it.
    /// </summary>
    private JsonObject WithTheMomentSettled(JsonObject call)
    {
        if (call["function"]?["name"]?.ToString() is not { } name || !Declares(name, "when")) return call;
        return WithArgumentsRewritten(call, arguments => SettleTheMoment(arguments) is not null);
    }

    /// <summary>
    /// Settle <c>arguments["when"]</c> in place against this class's clock, and
    /// return the whole moment — or null when there was none to settle. A
    /// moment that was already whole is returned too, untouched.
    /// </summary>
    private string? SettleTheMoment(JsonObject arguments)
    {
        if (arguments["when"] is not JsonValue given || !given.TryGetValue(out string? when)) return null;
        if (ScheduledMoment.Settle(when, Today(), Now(), TimeZone) is { } settled)
        {
            arguments["when"] = settled;
            return settled;
        }
        return null;
    }

    /// <summary>
    /// Whether the tool the model chose declares a <c>date</c> — asked of the
    /// schemas this conversation was built with, which are the ones the model
    /// was shown.
    /// </summary>
    internal bool DeclaresAClassDay(string tool) => Declares(tool, "date");

    /// <summary>
    /// Whether the tool's own schema - the one the model was shown -
    /// declares <paramref name="argument"/>. Every rewrite at this seam is
    /// gated this way rather than on a list of tool names, so a list kept
    /// beside the code cannot fall behind the tools.
    /// </summary>
    internal bool Declares(string tool, string argument) =>
        SchemaOf(tool)?["parameters"]?["properties"]?[argument] is not null;

    /// <summary>The <c>function</c> half of the named tool's schema, or null.</summary>
    private JsonObject? SchemaOf(string tool)
    {
        foreach (var schema in _schemas)
        {
            if (schema?["function"] is not JsonObject function) continue;
            if (function["name"]?.ToString() is not { } named) continue;
            if (named.Equals(tool, StringComparison.OrdinalIgnoreCase)) return function;
        }
        return null;
    }

    // ---- Binding the model's call to this window (#180) -------------------

    /// <summary>
    /// The course codes in this window's working folder, as the folder spells
    /// them. Asked only when the model names a course that is not this
    /// window's, to tell "another course that is here" from "no such
    /// course" - two different sentences, because "open MCV4U" is false
    /// advice for a code that names nothing.
    /// </summary>
    public Func<IReadOnlyList<string>> CoursesInTheFolder { get; init; } = () => Array.Empty<string>();

    /// <summary>
    /// The code a teacher reads when <c>name</c> — as the model or the
    /// teacher wrote it — names a course KEPT FOR REFERENCE and no course
    /// being taught; otherwise null (#241). Such a course is answered with
    /// <see cref="AssistWording.AskedAboutAReferenceCourse"/>, never with the
    /// #180 sentence's "open it and ask me there": the assistant is not offered
    /// on a reference course at all.
    /// </summary>
    public Func<string, string?> ReferenceCourseNamed { get; init; } = _ => null;

    /// <summary>
    /// Whether this window's course is, NOW, kept for reference (#241, doors
    /// 2–4). Asked first in the deploy hand-back, BEFORE a preview is stopped:
    /// a refusal any later kills a preview the teacher was reading, for nothing.
    /// </summary>
    public Func<bool> CourseIsKeptForReference { get; init; } = () => false;

    /// <summary>
    /// For a call the MODEL made in this window, <c>course</c> and
    /// <c>section</c> are this window's - or the turn is refused.
    /// </summary>
    /// <remarks>
    /// <para><b>The section is always the window's</b>, present or absent:
    /// "Unpublish Unit 4, Day 12" was read by the small assistant as section
    /// 4, and changed the wrong section's pages while reporting success. No
    /// tool reads an omitted section as "every section", so an absent one is
    /// bound too.</para>
    ///
    /// <para><b>The course is the window's or nothing runs.</b> Rebinding a
    /// different course to this window would publish an ICS3U class off
    /// "publish MCV4U's class" and say so - the one failure a teacher cannot
    /// catch. Russell decided 2026-09-19 that refusing is right on both
    /// platforms (#208). The same code in another casing is not another
    /// course: it runs, with the WINDOW's spelling, because the approval card
    /// prints the code verbatim. Whitespace and newlines are trimmed before
    /// comparing, as the tools trim.</para>
    ///
    /// <para><b>In the agent, not the tool server.</b> <c>plantoir-mcp</c>
    /// also serves an outside client that legitimately names any course its
    /// lock allows; this window is the only thing that knows which section
    /// the teacher is looking at. Gated on the tool's own schema declaring
    /// each argument, never on a list - <c>undo_last_change</c> declares
    /// neither and is left exactly as the model wrote it.</para>
    ///
    /// <para>Nothing the model SEES changes, so no routing re-measurement is
    /// owed.</para>
    /// </remarks>
    /// <returns>The sentence to say when the turn is refused; null when it runs.</returns>
    private string? BoundToThisWindow(JsonObject call)
    {
        if (call["function"]?["name"]?.ToString() is not { } name) return null;
        bool course = Declares(name, "course");
        bool section = Declares(name, "section");
        if (!course && !section) return null;

        string? refusal = null;
        WithArgumentsRewritten(call, arguments =>
        {
            bool changed = false;
            if (course)
            {
                string? wrote = arguments["course"] switch
                {
                    null => null,
                    JsonValue value when value.TryGetValue(out string? text) => text,
                    var other => other.ToJsonString(),
                };
                string trimmed = wrote?.Trim() ?? "";
                if (trimmed.Length > 0 && !trimmed.Equals(_courseCode, StringComparison.OrdinalIgnoreCase))
                {
                    refusal = RefuseAnotherCourse(name, wrote!, trimmed);
                    return false;
                }
                if (wrote != _courseCode)
                {
                    arguments["course"] = _courseCode;
                    changed = true;
                }
            }
            if (section && !(arguments["section"] is JsonValue given &&
                             given.TryGetValue(out int number) && number == _section))
            {
                arguments["section"] = _section;
                changed = true;
            }
            return changed;
        });
        return refusal;
    }

    private string RefuseAnotherCourse(string tool, string asTheModelWroteIt, string trimmed)
    {
        // The trail keeps the MODEL's spelling - it is evidence about the
        // model, and normalising it throws away the only record it spelt the
        // code oddly. The sentence names the folder's spelling instead.
        ActivityTrail.Note(ActivityTrail.Event.AssistantWasAskedAboutAnotherCourse,
            $"the assistant named {asTheModelWroteIt.Trim()} for {tool.Replace('_', ' ')} in this " +
            $"{_courseCode} window - nothing was run from it",
            _courseCode, _section);

        if (ReferenceCourseNamed(trimmed) is { } kept)
            return AssistWording.AskedAboutAReferenceCourse(_courseCode, kept);
        string? here = CoursesInTheFolder()
            .FirstOrDefault(code => code.Equals(trimmed, StringComparison.OrdinalIgnoreCase));
        return here is not null
            ? AssistWording.AskedAboutAnotherCourse(_courseCode, here)
            : AssistWording.AskedAboutACourseThatIsNotHere(_courseCode, trimmed);
    }

    /// <summary>
    /// Run the <c>plan_</c> twin and hold the real call behind it.
    ///
    /// The plan is SAID, not shown on a card that is then taken away. It used
    /// to live only in the approval card on the mac, which meant that the
    /// moment a teacher pressed Go or Cancel the description of what they had
    /// just agreed to disappeared — and with it the context for everything
    /// after. A conversation you cannot scroll back through is not a
    /// conversation. So the plan goes into the transcript like anything else
    /// the assistant says, and the card below it is nothing but two buttons.
    ///
    /// Nothing is written to the message history here. The model's tool call
    /// stays unanswered until the teacher decides, and then Approve or Decline
    /// answers it — so the history never claims something happened that has
    /// not.
    /// </summary>
    private async Task<List<Line>> ShowPlan(string twinName, JsonObject call, CancellationToken cancellation)
    {
        var answer = await _tools.CallTool(twinName, ArgumentsOf(call), OnToolProgress, cancellation);
        if (answer.ConversationBackupPath is { } savedCopy) OnConversationBackup?.Invoke(savedCopy);

        // A plan twin can come back with a REFUSAL — no such page, no such
        // section — and a refusal is an answer, not a proposal. "Shall I go
        // ahead?" underneath one invites a teacher to approve an explanation
        // of why nothing can be done.
        if (!answer.IsPlan)
        {
            _messages.Add(new JsonObject
            {
                ["role"] = "tool",
                ["tool_call_id"] = call["id"]?.DeepClone(),
                ["content"] = answer.Detail,
            });
            return new List<Line> { new("assistant", answer.Summary) };
        }

        _awaiting = call;
        return new List<Line>
        {
            new("assistant", answer.Summary),
            // The question is a line too, so the card below can be nothing but
            // the buttons. A card carrying its own heading is a second voice
            // in a conversation that already has two.
            new("assistant", AssistWording.PlanQuestion, NeedsApproval: true,
                Pending: call["function"]?["name"]?.GetValue<string>()),
        };
    }

    /// <summary>
    /// Refuse a reply that cannot be acted on: run nothing, say so, record
    /// why, and take the turn back out of what the model is sent — so the
    /// shorter retry the sentence asks for is not sent with the request that
    /// ran away still in front of it (#196).
    /// </summary>
    private List<Line> NothingRanFromIt(List<Line> lines, string said, string trailLine)
    {
        ActivityTrail.Note(ActivityTrail.Event.AssistantAnswerWasCutOff, trailLine, _courseCode, _section);
        WindTheTurnBack();
        lines.Add(new Line("assistant", said));
        return lines;
    }

    private static string Spaced(string tool) => tool.Replace('_', ' ');

    /// <summary>The teacher's message as SENT this turn (date line and all), or null for a lap that began with a tool result.</summary>
    private string? _sentThisTurn;

    /// <summary>
    /// What the teacher TYPED this turn, before the date line — kept in a
    /// field rather than recomputed, because recomputing the date line means
    /// reading the clock a second time.
    /// </summary>
    private string? _typedThisTurn;

    /// <summary>
    /// Whether a reply is the teacher's request handed back (#217) —
    /// <c>assist-cases.json</c> → <c>echoedRequest</c>.
    /// </summary>
    /// <remarks>
    /// <para>Compared against the message the TURN BEGAN WITH, never the last
    /// user message anywhere: a lap that began with a tool result has none,
    /// which is what makes a second lap safe by construction. A reply that
    /// chooses a tool is an instruction whatever its text says, so
    /// <paramref name="hasToolCall"/> is an argument rather than an
    /// assumption.</para>
    ///
    /// <para>Exact after folding, deliberately not fuzzy: an echo with a
    /// preamble ("Sure: hide unit 4, day 21") gets through, because a rule
    /// that fires on a legitimate answer throws a real reply away.</para>
    /// </remarks>
    internal static bool IsTheRequestBackAgain(string? sent, string? typed, string reply, bool hasToolCall)
    {
        if (hasToolCall) return false;
        string said = ForComparing(reply);
        if (said.Length == 0) return false;
        if (sent is not null && said == ForComparing(sent)) return true;
        return !string.IsNullOrEmpty(typed) && said == ForComparing(typed);
    }

    /// <summary>Whitespace and newlines off, . ! ? off both ends, whitespace again, lower-cased.</summary>
    private static string ForComparing(string text) =>
        text.Trim().Trim('.', '!', '?').Trim().ToLowerInvariant();

    /// <summary>What a finished tool call's arguments amount to.</summary>
    internal enum WhatTheModelWrote
    {
        /// <summary>Something to act on — however little; binding and the tool's own refusals decide the rest.</summary>
        Readable,
        /// <summary>Not a JSON object: bad JSON, or a fragment.</summary>
        Unreadable,
        /// <summary>Nothing at all, for a tool that needs more than the window supplies (#262).</summary>
        NothingForWhatItNeeds,
    }

    /// <summary>The two arguments the section window supplies on its own.</summary>
    private static readonly HashSet<string> TheWindowSupplies = new(StringComparer.Ordinal) { "course", "section" };

    /// <summary>
    /// Optional arguments that only EXTEND a write that already has a sensible
    /// default, as <c>tool.argument</c> — so they do not make an empty call
    /// "need more" (bundle 5a fix round, ruling 2). Windows' local
    /// <c>add_next_class</c> declares <c>unit</c> and <c>days</c> where the
    /// mac's declares only course and section; counted, they refused an empty
    /// call the mac runs — an unchosen difference. Named rather than inferred
    /// from "optional", because <c>publish_pages</c>' <c>pages</c> is optional
    /// too and an empty publish must still be refused.
    /// </summary>
    internal static readonly HashSet<string> OptionalExtras = new(StringComparer.OrdinalIgnoreCase)
    {
        "add_next_class.unit", "add_next_class.days",
    };

    /// <summary>
    /// Judge a call's arguments against the tool's own schema —
    /// <c>app-rules.json</c> → <c>modelTiers.requirements</c> → "A finished
    /// reply that wrote nothing runs a tool only when the window supplies
    /// everything that tool needs", whose cases this is tested against.
    /// </summary>
    /// <remarks>
    /// <para>Nothing written — an empty string, only whitespace, or an object
    /// with no keys — runs only when the window can supply everything. A tool
    /// needs more when its schema REQUIRES anything besides course and section
    /// (a date, a page, a time), or when it CHANGES PAGES and declares anything
    /// besides them (which pages, which dates): a write told only its section
    /// has nothing to act on. A schema with no <c>required</c> key requires
    /// nothing.</para>
    ///
    /// <para><b>The trap, either way round:</b> keying on <c>required</c>
    /// alone. Refusing every tool with a required list refuses rebuild and
    /// deploy, which the window supplies in full; running whenever the
    /// required arguments are window-supplied runs an empty
    /// <c>publish_pages</c>, whose real content is optional in its schema.</para>
    /// </remarks>
    internal static WhatTheModelWrote Judge(string? arguments, IEnumerable<string> required,
                                            IEnumerable<string> properties, bool readOnly)
    {
        if (!string.IsNullOrWhiteSpace(arguments))
        {
            JsonNode? parsed;
            try { parsed = JsonNode.Parse(arguments); }
            catch (System.Text.Json.JsonException) { return WhatTheModelWrote.Unreadable; }
            if (parsed is not JsonObject written) return WhatTheModelWrote.Unreadable;
            if (written.Count > 0) return WhatTheModelWrote.Readable;
        }

        bool needsMore = required.Any(name => !TheWindowSupplies.Contains(name)) ||
                         (!readOnly && properties.Any(name => !TheWindowSupplies.Contains(name)));
        return needsMore ? WhatTheModelWrote.NothingForWhatItNeeds : WhatTheModelWrote.Readable;
    }

    /// <summary>
    /// <see cref="Judge"/> for a call the model made, asked of the schema it
    /// was shown. "Changes pages" is this app's own list of writes, since the
    /// schemas the server hands out carry no read-only flag.
    /// </summary>
    private WhatTheModelWrote WhatTheModelWroteFor(JsonObject call)
    {
        string name = call["function"]?["name"]?.ToString() ?? "";
        string? arguments = call["function"]?["arguments"] is JsonValue raw && raw.TryGetValue(out string? text)
            ? text
            : call["function"]?["arguments"]?.ToJsonString();
        var parameters = SchemaOf(name)?["parameters"];
        var required = (parameters?["required"] as JsonArray)?.Select(item => item?.ToString() ?? "") ?? Enumerable.Empty<string>();
        var properties = ((parameters?["properties"] as JsonObject)?.Select(pair => pair.Key) ?? Enumerable.Empty<string>())
            .Where(property => !OptionalExtras.Contains($"{name}.{property}"));
        return Judge(arguments, required, properties, readOnly: !IsWriteTool(name));
    }

    /// <summary>
    /// How many messages the conversation held when this turn began - the
    /// mark <see cref="WindTheTurnBack"/> returns to.
    /// </summary>
    private int _turnBeganAt = 1;

    /// <summary>
    /// Take the whole turn back out of what the MODEL is sent: the teacher's
    /// sentence, the model's reply, and any read a second lap made.
    /// </summary>
    /// <remarks>
    /// <para>The transcript the teacher reads is not touched - it is the
    /// window's, not this list - so their sentence stays above the answer.
    /// Only the model's copy goes. Safe because no lap can follow a write:
    /// a turn comes back to the model only after a read or a refusal made
    /// before anything was written.</para>
    ///
    /// <para>Not called on an engine failure (unreachable, timed out): that
    /// path reports the engine rather than asking for a rephrase, and the
    /// context is worth keeping.</para>
    /// </remarks>
    private void WindTheTurnBack()
    {
        while (_messages.Count > _turnBeganAt) _messages.RemoveAt(_messages.Count - 1);
    }

    /// <summary>This turn's date note, remembered so a parroting reply can have it stripped.</summary>
    private string _dateline = "";

    /// <summary>
    /// The commonest command, answered without the model.
    ///
    /// Measured, after the routing cue for it was already in place: "Preview
    /// the site" still went to check_section three trials out of four — "the
    /// site" pulls toward that tool's own wording — and the teacher got a
    /// statistics lecture instead of a preview, after a twenty-second wait.
    /// Every phrase in this set means exactly one thing, so ordinary string
    /// matching answers it: instantly, every time, with the model never
    /// consulted. The model still handles anything that carries more than
    /// the command itself.
    /// </summary>
    private static readonly HashSet<string> PreviewCommands = new()
    {
        "preview", "preview the site", "preview my site", "preview the section", "preview it",
        "show me the preview", "show the preview", "open the preview", "start the preview",
        "launch the preview", "rebuild the preview", "refresh the preview", "update the preview",
    };

    private List<Line>? PreviewAskedForPlainly(string text)
    {
        if (ShowPreviewInApp is null || !PreviewCommands.Contains(Plainly(text))) return null;

        bool deploying = ThisSectionIsBeingDeployed();
        if (!deploying) ShowPreviewInApp.Invoke();
        string said = deploying
            ? SectionIsBeingDeployedSentence
            : "The preview is opening in Plantoir's main window — the build shows its progress there.";
        // The exchange still goes in the transcript the model sees, so a
        // follow-up question knows the preview is already on screen.
        _messages.Add(new JsonObject { ["role"] = "user", ["content"] = text });
        _messages.Add(new JsonObject { ["role"] = "assistant", ["content"] = said });
        return new List<Line> { new("assistant", said) };
    }

    /// <summary>Lower-cased, letters only, courtesy words trimmed — the command underneath.</summary>
    private static string Plainly(string text)
    {
        var letters = new System.Text.StringBuilder();
        foreach (char c in text.ToLowerInvariant())
            letters.Append(char.IsLetter(c) ? c : ' ');
        string plain = string.Join(' ', letters.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
        foreach (string opener in new[] { "please ", "can you ", "could you ", "would you " })
            while (plain.StartsWith(opener, StringComparison.Ordinal)) plain = plain[opener.Length..];
        if (plain.EndsWith(" please", StringComparison.Ordinal)) plain = plain[..^" please".Length];
        return plain;
    }

    /// <summary>
    /// The teacher agreed to the write that was waiting. Run it, then carry on.
    /// </summary>
    public async Task<List<Line>> Approve(CancellationToken cancellation)
    {
        if (_awaiting is not { } call) return new List<Line>();
        _awaiting = null;

        OnPlanAccepted?.Invoke();

        var lines = new List<Line>();
        var answer = await RunTool(call, lines, cancellation);
        lines.Add(new Line("tools", answer.Summary));
        if (TurnEnded(lines)) return lines;
        // A lap after an approved call begins at its result: winding back
        // past it would erase a call that has already run. It begins with a
        // TOOL RESULT and no message from the teacher, so there is nothing for
        // a reply to echo.
        _turnBeganAt = _messages.Count;
        _sentThisTurn = null;
        _typedThisTurn = null;
        return lines.Concat(await Run(cancellation)).ToList();
    }

    /// <summary>The teacher said no. Cancel the waiting action.</summary>
    public Task<List<Line>> Decline(CancellationToken cancellation)
    {
        if (_awaiting is not { } call) return Task.FromResult(new List<Line>());
        string toolName = call["function"]?["name"]?.GetValue<string>() ?? "";
        _awaiting = null;

        // The model asked for a tool and is still waiting to hear what came
        // of it. Answering as the TOOL rather than as the assistant is what
        // keeps the history honest: a dangling call left unanswered is a hole
        // the next turn reads across.
        _messages.Add(new JsonObject
        {
            ["role"] = "tool",
            ["tool_call_id"] = call["id"]?.DeepClone(),
            ["content"] = "The teacher decided not to. Nothing was done.",
        });

        // A cancelled DEPLOY is answered with the fact and nothing else.
        // "Left as it was — nothing was changed." is true, and reassuring
        // about a thing nobody was worried about: somebody who has just
        // pressed Cancel knows nothing was changed, and being told so reads
        // as the assistant explaining itself. A cancelled PLAN keeps that
        // wording, because there the reassurance IS the answer — the plan
        // described changes to pages, and "nothing was changed" is the part
        // in doubt.
        bool wasDeploy = DeploysToStudents.Contains(toolName);
        string said = wasDeploy ? AssistWording.DeployWasCancelled : AssistWording.PlanWasCancelled;
        return Task.FromResult(new List<Line> { new("assistant", said) });
    }

    /// <summary>
    /// The window's fire-and-forget warm-up, if one is still running. The
    /// first turn AWAITS it rather than racing it: both share the model's
    /// single slot, so a question sent mid-warm-up queued until it timed
    /// out — and the warmed prompt cache makes the awaited question fast.
    /// </summary>
    public Task? Priming { get; set; }

    private async Task<List<Line>> Run(CancellationToken cancellation)
    {
        var lines = new List<Line>();

        if (Priming is { } priming)
        {
            Priming = null;
            try { await priming.WaitAsync(cancellation); } catch { /* warm-up is best-effort */ }
        }

        for (int step = 0; step < MostStepsPerTurn; step++)
        {
            var asking = System.Diagnostics.Stopwatch.StartNew();
            var modelAnswer = await _model.Ask(_messages, _schemas, cancellation);
            asking.Stop();
            if (modelAnswer?.Message is not { } reply)
            {
                // An ENGINE failure, and deliberately not wound back: the
                // sentence is usually not the cause, and the context is worth
                // keeping for the next turn (#196).
                ActivityTrail.Note(ActivityTrail.Event.AssistantCouldNotAnswer,
                    "the assistant did not answer", _courseCode, _section);
                lines.Add(new Line("assistant", "The assistant didn’t answer. Try again in a moment."));
                return lines;
            }

            var calls = reply["tool_calls"] as JsonArray;
            bool acting = calls is { Count: > 0 };
            string begun = (acting ? calls![0]?["function"]?["name"]?.ToString() : null) ?? "";

            // ABOVE the tool-call branch, and whether or not a tool was named
            // (#196). A reply cut before the tool name was written arrives
            // with NO tool call and a raw fragment in its content, which the
            // branch below would show to the teacher; one cut a token after
            // its arguments closed parses perfectly. The finish reason is the
            // only signal that tells either from a finished answer.
            if (modelAnswer.WasCutOff)
            {
                return NothingRanFromIt(lines, AssistWording.AnswerWasCutOff, begun.Length > 0
                    ? $"the assistant's answer was cut off part way through {Spaced(begun)} — nothing was run from it"
                    : "the assistant's answer was cut off part way — nothing was run from it");
            }
            // Below the cut-off gate and above the readability and course
            // gates (the mac's order), and BEFORE the reply joins the
            // conversation: a tool that exists but was not offered is
            // refused, the turn is wound back, and nothing runs — no plan, no
            // button (#350 / mac #327).
            if (acting && calls![0]?["function"]?["name"]?.GetValue<string>() is { } named &&
                WasNotOffered(named))
            {
                WindTheTurnBack();
                ActivityTrail.Note(ActivityTrail.Event.AssistantNamedAToolItWasNotOffered,
                    $"the assistant named {named.Replace('_', ' ')}, which it was not offered; nothing ran",
                    _courseCode, _section);
                lines.Add(new Line("assistant", AssistWording.DidNotFollowThat));
                return lines;
            }

            if (acting && calls![0] is JsonObject chosen)
            {
                switch (WhatTheModelWroteFor(chosen))
                {
                    case WhatTheModelWrote.Unreadable:
                        // A finished answer whose arguments are not JSON: the
                        // model wrote bad JSON of its own accord. Same sentence,
                        // its own line — whoever reads a report needs to tell
                        // the two apart.
                        return NothingRanFromIt(lines, AssistWording.AnswerWasCutOff,
                            $"the assistant finished answering but what it wrote for {Spaced(begun)} could not be read — nothing was run from it");
                    case WhatTheModelWrote.NothingForWhatItNeeds:
                        // #262: it wrote NOTHING, and this tool needs more than
                        // the window supplies. Not answerWasCutOff, whose advice
                        // is about the teacher's request.
                        return NothingRanFromIt(lines, AssistWording.AnswerLeftOutWhatItWasFor,
                            $"the assistant finished answering but wrote nothing for {Spaced(begun)} — nothing was run from it");
                }
            }
            // #217: BELOW the tool-call branch (an echo is by definition a
            // reply with no tool call) and ABOVE the append — the whole point
            // is that it must not get into the history, because the model
            // copies the pattern it can see: measured, after one echo even a
            // sentence it answers correctly in a fresh conversation echoed.
            if (!acting && IsTheRequestBackAgain(_sentThisTurn, _typedThisTurn,
                                                 reply["content"]?.ToString() ?? "", hasToolCall: false))
            {
                // Never show the echoed text, not even inside an apology.
                ActivityTrail.Note(ActivityTrail.Event.AssistantRepeatedTheRequestBack,
                    "the assistant repeated the request back — nothing was run, and the turn was taken back out of the conversation",
                    _courseCode, _section);
                WindTheTurnBack();
                lines.Add(new Line("assistant", AssistWording.DidNotFollowThat));
                return lines;
            }
            _messages.Add(reply.DeepClone()!);

            // Content alongside a tool call is almost always the request
            // parroted back — measured as "Unpublishing Unit 4, Day 5
            // (Today is 2026-08-14, a Friday.)", dateline and all, shown to
            // the teacher who had just typed it. The tool's own result says
            // what happened; the parrot adds nothing, so it is not shown.
            // The dateline is stripped from what IS shown, for the same
            // reason: it was written for the model, not the teacher.
            string said = reply["content"]?.GetValue<string>() ?? "";
            if (_dateline.Length > 0) said = said.Replace(_dateline, "");
            if (!acting)
            {
                string trimmed = said.Trim();
                lines.Add(new Line("assistant", string.IsNullOrEmpty(trimmed) ? AssistWording.NothingToDo : trimmed));
                return lines;
            }

            // One at a time, so a teacher reading the transcript can follow it.
            var call = calls![0] as JsonObject;
            if (call is null) return lines;

            // Where the model's call is made is where its arguments are put
            // right — once, before the card, the plan twin and the act each
            // read this same object. Today that is the relative day; a
            // section binding belongs beside it.
            call = WithTheDaySettled(call);
            call = WithTheMomentSettled(call);
            if (BoundToThisWindow(call) is { } refused)
            {
                // Nothing runs: no plan, no card, no tool. The turn comes back
                // out of what the model is sent, so its next answer is not
                // made in front of a request it was refused.
                WindTheTurnBack();
                lines.Add(new Line("assistant", refused));
                return lines;
            }

            string name = call["function"]?["name"]?.GetValue<string>() ?? "";
            ActivityTrail.Note(ActivityTrail.Event.AssistantChoseATool,
                ChoseAToolLine(name, call, asking.Elapsed, modelAnswer.CompletionTokens,
                               waited: NeedsApproval(name) || (ConfirmationMode() && PlanTwins.ContainsKey(name))),
                _courseCode, _section);
            if (NeedsApproval(name))
            {
                // The one rule this loop owns whatever the settings say. A
                // plan the teacher has not read is not a confirmation, and the
                // measurements say the model will occasionally reach for the
                // opposite of what was asked.
                lines.AddRange(AskFirst(call));
                return lines;
            }

            // In confirmation mode, every other write is shown as a PLAN
            // first — see PlanTwins.
            if (ConfirmationMode() && PlanTwins.TryGetValue(name, out string? twin))
            {
                lines.AddRange(await ShowPlan(twin, call, cancellation));
                return lines;
            }

            var answer = await RunTool(call, lines, cancellation);
            lines.Add(new Line("tools", answer.Summary));
            if (TurnEnded(lines)) return lines;
        }

        lines.Add(new Line("assistant",
            "I’ve gone round several times without finishing. Tell me what you’d like me to do next."));
        return lines;
    }

    /// <summary>
    /// The tools that END a turn.
    ///
    /// A READ hands back to the model, so it can answer the question it was
    /// reading for. A WRITE is the end: the teacher asked for something, it
    /// happened, and another lap round the model can only invent a follow-up
    /// nobody asked for. macOS decides this per outcome; this list is the
    /// same rule by name, and every write the server offers has to be on it.
    ///
    /// It has been wrong twice in the way a list is wrong — <c>roll_over_course</c>
    /// was here for a tool actually called <c>roll_over_section</c>, and five
    /// other writes were simply missing. Neither shows up as an error: the
    /// write happens, the model gets a lap it should not have had, and the
    /// teacher reads a paragraph restating the sentence above it.
    /// </summary>
    private static readonly HashSet<string> WriteTools = new(StringComparer.OrdinalIgnoreCase)
    {
        "publish_pages", "unpublish_pages", "publish_class_on", "undo_last_change",
        "add_next_class", "add_classes", "make_room_for_classes",
        "schedule_deploy", "cancel_scheduled_deploy",
        "rebuild_preview", "deploy_section", "re_date_classes", "roll_over_section",
        "remember_timetable", "sync_page_dates", "add_curriculum_mentions",
        "back_up_course",
    };

    private static bool IsWriteTool(string name) => WriteTools.Contains(name);

    private bool _handedToApp;

    private bool TakeHandedToApp()
    {
        bool handed = _handedToApp;
        _handedToApp = false;
        return handed;
    }

    /// <summary>
    /// Close out a turn whose last tool finished work.
    /// </summary>
    private bool TurnEnded(List<Line> lines)
    {
        return TakeHandedToApp();
    }

    internal async Task<AssistToolAnswer> RunTool(JsonObject call, List<Line> lines, CancellationToken cancellation)
    {
        string name = call["function"]?["name"]?.GetValue<string>() ?? "";
        var arguments = new JsonObject();
        if (call["function"]?["arguments"]?.GetValue<string>() is { } raw)
        {
            try { arguments = JsonNode.Parse(raw) as JsonObject ?? new JsonObject(); }
            catch { /* a malformed call is answered, not crashed on */ }
        }

        // Building and deploying are done by pressing Plantoir's own buttons,
        // once, where the teacher can watch — never by the server in a hidden
        // container run whose transcript lands in this chat.
        // These answers appear in the transcript word for word, so they are
        // written for the teacher — and they END the turn. Asked "what next?"
        // after reading one of these, a small model restates it, and the
        // teacher saw the same sentence twice. There is nothing next: the
        // main window has the work.
        if (name.Equals("rebuild_preview", StringComparison.OrdinalIgnoreCase) && ThisSectionIsBeingDeployed())
        {
            // Before a window is opened, a preview stopped or a no-window
            // rebuild run (#386): the same publish record the window asks.
            _handedToApp = true;
            return Answer(call, SectionIsBeingDeployedSentence);
        }
        if (name.Equals("rebuild_preview", StringComparison.OrdinalIgnoreCase) && ShowPreviewInApp is not null)
        {
            ShowPreviewInApp.Invoke();
            _handedToApp = true;
            return Answer(call, AssistWording.PreviewIsRebuilding(_courseCode, _section.ToString()));
        }
        if ((name.Equals("deploy_section", StringComparison.OrdinalIgnoreCase)
             || name.Equals("schedule_deploy", StringComparison.OrdinalIgnoreCase))
            && CourseIsKeptForReference())
        {
            _handedToApp = true;
            return Answer(call, AssistWording.DeployRefusedForAReferenceCourse(_courseCode));
        }
        if (name.Equals("deploy_section", StringComparison.OrdinalIgnoreCase) &&
            (StartDeployInApp is not null || StartDeployInAppAsync is not null))
        {
            if (SectionIsBusy?.Invoke() == true)
            {
                if (StartDeployInApp is not null) StartDeployInApp.Invoke();
                else if (StartDeployInAppAsync is not null) _ = StartDeployInAppAsync.Invoke();
                _handedToApp = true;
                return Answer(call, AssistWording.SectionIsBusy(_courseCode, _section.ToString()));
            }

            if (PreviewIsShowing?.Invoke() == true)
            {
                if (StopPreviewInAppAsync is not null)
                {
                    await StopPreviewInAppAsync.Invoke();
                }
                else
                {
                    StopPreviewInApp?.Invoke();
                }
            }

            if (StartDeployInAppAsync is not null)
            {
                string? outcome = await StartDeployInAppAsync.Invoke();
                _handedToApp = true;
                return Answer(call, outcome ?? AssistWording.DeployDidNotFinish(_courseCode, _section.ToString()));
            }
            else
            {
                StartDeployInApp?.Invoke();
                _handedToApp = true;
                // No async wiring available means no way to await the real
                // outcome — the caller pressed the button and this is all
                // that can honestly be said about it.
                return Answer(call, AssistWording.Deployed(_courseCode, _section.ToString()));
            }
        }

        // A page edit does what a person would do: stop the preview, change
        // the files, start the preview again. The server never builds
        // (preview declined), so the work happens once, in the main window.
        bool edits = EditsPages.Contains(name);
        if (TakesPreviewFlag.Contains(name)) arguments["preview"] = false;
        bool hadPreview = PreviewIsShowing?.Invoke() == true;
        if (edits && hadPreview)
        {
            if (StopPreviewInAppAsync is not null)
            {
                await StopPreviewInAppAsync.Invoke();
            }
            else
            {
                StopPreviewInApp?.Invoke();
            }
        }

        var answer = await _tools.CallTool(name, arguments, OnToolProgress, cancellation);
        if (answer.ConversationBackupPath is { } savedCopy) OnConversationBackup?.Invoke(savedCopy);
        // The MODEL is given the long half; the teacher's line is added by
        // whoever called this, from the short one.
        _messages.Add(new JsonObject
        {
            ["role"] = "tool",
            ["tool_call_id"] = call["id"]?.DeepClone(),
            ["content"] = answer.Detail,
        });
        if (IsWriteTool(name) || name.Equals("check_section", StringComparison.OrdinalIgnoreCase) || name.Equals("read_remembered_timetable", StringComparison.OrdinalIgnoreCase))
        {
            _handedToApp = true;
        }
        if (edits && (hadPreview || AlwaysStartsPreview.Contains(name)) && ShowPreviewInApp is not null &&
            !ThisSectionIsBeingDeployed())
        {
            ShowPreviewInApp.Invoke();
        }
        return answer;
    }

    /// <summary>
    /// Record a tool's answer without having called the server.
    ///
    /// These are <c>AssistWording</c> sentences, written for the teacher and
    /// short enough for the model to read as they stand — so the two halves
    /// are the same words, deliberately.
    /// </summary>
    private AssistToolAnswer Answer(JsonObject call, string text)
    {
        _messages.Add(new JsonObject
        {
            ["role"] = "tool",
            ["tool_call_id"] = call["id"]?.DeepClone(),
            ["content"] = text,
        });
        return AssistToolAnswer.Same(text);
    }
}
