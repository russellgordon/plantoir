using System;
using System.Collections.Generic;
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
    Task<JsonObject?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation);
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
                copy["function"]!["description"] = Briefly(description).Replace(ExampleCourse, courseCode);
            MakeExamplesReal(copy["function"]?["parameters"], courseCode);
            kept.Add(copy);
        }
        return kept;
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
    /// The part of a tool description a ROUTER needs, and no more.
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
    /// The <c>plan_</c> twin of each write the local model can reach — what
    /// the assistant runs, and reads out, before it does the thing itself.
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
    /// </summary>
    internal static readonly Dictionary<string, string> PlanTwins = new(StringComparer.OrdinalIgnoreCase)
    {
        ["publish_pages"] = "plan_publish_pages",
        ["unpublish_pages"] = "plan_unpublish_pages",
        ["publish_class_on"] = "plan_publish_class_on",
        ["add_next_class"] = "plan_add_next_class",
        ["remember_timetable"] = "plan_remember_timetable",
        ["re_date_classes"] = "plan_re_date_classes",
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
        "If no tool fits, say so plainly instead of inventing one.\n" +
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
    /// console on screen and the preview in front of the teacher. So
    /// rebuild_preview and deploy_section never reach the server from here:
    /// they press Plantoir's own buttons. The server keeps those tools for
    /// the clients that have no window — Claude Code, and deploys scheduled
    /// for half six in the morning.
    /// </summary>
    public Action? ShowPreviewInApp { get; set; }

    /// <summary>Deploy through the main window's own flow, console and all. Any thread.</summary>
    public Action? StartDeployInApp { get; set; }

    /// <summary>Async version of StartDeployInApp.</summary>
    public Func<Task>? StartDeployInAppAsync { get; set; }

    /// <summary>Check if the section is currently busy.</summary>
    public Func<bool>? SectionIsBusy { get; set; }

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

    /// <summary>Invoked whenever a pending plan/write action is accepted by the teacher.</summary>
    public Action? OnPlanAccepted { get; set; }

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
    };

    /// <summary>The page-editing tools that accept a preview flag to decline the server's build.</summary>
    private static readonly HashSet<string> TakesPreviewFlag = new(StringComparer.OrdinalIgnoreCase)
    {
        "publish_pages", "unpublish_pages", "publish_class_on",
    };

    private JsonObject? _awaiting;      // a write the teacher has not agreed to yet

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

        var today = DateTime.Now;
        _dateline = $" (Today is {today:yyyy-MM-dd}, a {today.DayOfWeek}.)";
        _messages.Add(new JsonObject
        {
            ["role"] = "user",
            ["content"] = text + _dateline,
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
        if (AssistCardCommand.Matching(text) is { } match)
        {
            ActivityTrail.Note(
                ActivityTrail.Event.AssistantMatchedAFixedPhrase,
                "matched in code, not sent to the model — ran " + match.ToolName,
                _courseCode,
                _section);

            if (match.ToolName.Equals("deploy_section", StringComparison.OrdinalIgnoreCase))
            {
                return AskFirst(text, "deploy_section", match.ToJsonObject(_courseCode, _section));
            }
            if (match.ToolName.Equals("rebuild_preview", StringComparison.OrdinalIgnoreCase) && ShowPreviewInApp is not null)
            {
                ShowPreviewInApp.Invoke();
                const string said = "The preview is opening in Plantoir's main window — the build shows its progress there.";
                _messages.Add(new JsonObject { ["role"] = "user", ["content"] = text });
                _messages.Add(new JsonObject { ["role"] = "assistant", ["content"] = said });
                return new List<Line> { new("assistant", said) };
            }

            return await RunCommand(text, match.ToolName, match.ToJsonObject(_courseCode, _section), cancellation);
        }

        string request = text.Trim().TrimEnd('.', '!');

        var withLinks = System.Text.RegularExpressions.Regex.Match(request,
            @"^(?<verb>publish|unpublish)\s+(?<title>.+?),?\s+and everything it links to$",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        var named = System.Text.RegularExpressions.Regex.Match(request,
            @"^(?<verb>publish|unpublish)\s+(?<title>unit\s+\d+,\s*day\s+\d+)$",
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
            return await RunCommand(text, tool, PageArguments(withLinks.Groups["title"].Value, includeLinked: true),
                                    cancellation);
        }
        if (named.Success)
        {
            string tool = named.Groups["verb"].Value.StartsWith("un", StringComparison.OrdinalIgnoreCase)
                ? "unpublish_pages" : "publish_pages";
            return await RunCommand(text, tool, PageArguments(named.Groups["title"].Value, includeLinked: false),
                                    cancellation);
        }
        if (planned.Success && !Dated(planned.Groups["title"].Value))
            return await RunCommand(text, "plan_publish_pages",
                                    PageArguments(planned.Groups["title"].Value, includeLinked: true),
                                    cancellation);
        if (scheduled.Success)
        {
            int hour = int.Parse(scheduled.Groups["hour"].Value);
            int minute = scheduled.Groups["minute"].Success ? int.Parse(scheduled.Groups["minute"].Value) : 0;
            if (scheduled.Groups["half"].Value.Equals("pm", StringComparison.OrdinalIgnoreCase) && hour < 12) hour += 12;
            if (scheduled.Groups["half"].Value.Equals("am", StringComparison.OrdinalIgnoreCase) && hour == 12) hour = 0;
            string when = $"{DateTime.Now.AddDays(1):yyyy-MM-dd} {hour:00}:{minute:00}";
            return AskFirst(text, "schedule_deploy", new JsonObject
            {
                ["course"] = _courseCode,
                ["section"] = _section,
                ["when"] = when,
            });
        }
        return null;
    }

    private JsonObject PageArguments(string title, bool includeLinked) => new()
    {
        ["course"] = _courseCode,
        ["section"] = _section,
        ["includeLinked"] = includeLinked,
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
        return new List<Line>
        {
            new("assistant", Explain(call)),
            new("assistant", AssistWording.DeployQuestion, NeedsApproval: true, Pending: tool),
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
        string moment = DateTime.TryParse(when, out var parsed)
            ? parsed.ToString("dddd d MMMM, h:mm tt")
            : when;
        string destination = DestinationProvider?.Invoke() ?? "the web";
        return $"Set this computer to deploy {_courseCode} Section {_section} to {destination} at {moment}. " +
               "It has to be on and awake then — plugged in if it is a laptop, lid open. " +
               "Plantoir cannot wake it up.";
    }

    /// <summary>A tool call's arguments, which arrive as a JSON string.</summary>
    private static JsonObject ArgumentsOf(JsonObject call)
    {
        if (call["function"]?["arguments"]?.GetValue<string>() is not { } raw) return new JsonObject();
        try { return JsonNode.Parse(raw) as JsonObject ?? new JsonObject(); }
        catch { return new JsonObject(); }
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

        ShowPreviewInApp.Invoke();
        const string said = "The preview is opening in Plantoir's main window — the build shows its progress there.";
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

    private async Task<List<Line>> Run(CancellationToken cancellation)
    {
        var lines = new List<Line>();

        for (int step = 0; step < MostStepsPerTurn; step++)
        {
            var reply = await _model.Ask(_messages, _schemas, cancellation);
            if (reply is null)
            {
                lines.Add(new Line("assistant", "The assistant didn’t answer. Try again in a moment."));
                return lines;
            }
            _messages.Add(reply.DeepClone()!);

            var calls = reply["tool_calls"] as JsonArray;
            bool acting = calls is { Count: > 0 };

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

            string name = call["function"]?["name"]?.GetValue<string>() ?? "";
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
        if (name.Equals("rebuild_preview", StringComparison.OrdinalIgnoreCase) && ShowPreviewInApp is not null)
        {
            ShowPreviewInApp.Invoke();
            _handedToApp = true;
            return Answer(call, AssistWording.PreviewIsRebuilding(_courseCode, _section.ToString()));
        }
        if (name.Equals("deploy_section", StringComparison.OrdinalIgnoreCase) && StartDeployInApp is not null)
        {
            if (SectionIsBusy?.Invoke() == true)
            {
                StartDeployInApp.Invoke();
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
                await StartDeployInAppAsync.Invoke();
            }
            else
            {
                StartDeployInApp.Invoke();
            }
            _handedToApp = true;
            return Answer(call, AssistWording.Deployed(_courseCode, _section.ToString()));
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
        if (edits && hadPreview && ShowPreviewInApp is not null)
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
