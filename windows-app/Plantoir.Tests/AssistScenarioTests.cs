using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;
using Plantoir.Core.Assist;
using Plantoir.Mcp;

namespace Plantoir.Tests;

/// <summary>
/// Runs the scenarios in <c>contracts/assist-cases.json</c> — the same file the
/// macOS suite runs, case for case.
///
/// <para><b>The tools are REAL, and that is the whole point of this rewrite.</b>
/// Until 2026-09-09 this runner answered every tool call with "Done." and read
/// neither <c>given.saying</c> nor <c>expectTranscriptContains</c>. The three
/// rollover cases carry only those two keys, so each ran a single turn with
/// every assert block skipped: they passed having checked nothing at all
/// (GitHub issue #141). A fixture that invents its own answers cannot assert
/// the product's sentences, so it stopped inventing them. What runs now is
/// <see cref="PlantoirTools"/> against a course on disk, which is the shape the
/// mac's <c>AssistFixture.makeRunner</c> has always had.</para>
///
/// <para><b>The one seam is the launcher</b>, for the same reason the mac stubs
/// <c>AssistSiteWork</c>: a deploy would otherwise build a Docker image.
/// <see cref="FakeLauncher"/> records what it was asked to run and reports
/// success, so <c>AssistWorkspace.Deploy</c> — every refusal it checks, every
/// destination, and the real <c>AssistWording.Deployed</c> at the end of it —
/// runs above it for real. Nothing here writes a contract sentence down a
/// second time.</para>
///
/// <para>Serialized with the other process-wide-state classes because of
/// <see cref="TaskScheduling.SchtasksForTests"/>, a static: without that seam,
/// cutting a section loose from last year's website runs
/// <c>schtasks /Delete /F</c> against the real Task Scheduler.</para>
/// </summary>
[Collection(SharedActivityState.Name)]
public class AssistScenarioTests : IDisposable
{
    // The mac's fixture course is ICS3U; this side has always used VVH2O, and
    // the contract names neither — every sentence it pins carries {course} and
    // {section} placeholders that each platform fills in for itself.
    private const string Course = "VVH2O";
    private const int SectionNumber = 1;

    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-scenario").FullName;
    private readonly FakeLauncher _launcher = new();
    private readonly FakeSectionWindow _window = new();

    public AssistScenarioTests()
    {
        // A working folder is recognised by its launchers; a marker is enough,
        // and FakeLauncher means not one of them is ever run.
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");

        string directory = Path.Combine(_folder, "courses", Course);
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "course_config.json"),
            $$"""
            {
              "course_code": "{{Course}}",
              "course_name": "A course",
              "deploy_target": "netlify",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": ["Key Links.md"],
              "section_numbers": [{{SectionNumber}}]
            }
            """);

        // The marker deploy.py leaves the first time a section goes out.
        // Without it a deploy is REFUSED — the first one asks what to call the
        // website, which only Plantoir can answer — and a rollover needs a
        // website to be cut loose from.
        string sites = Path.Combine(directory, ".netlify_sites");
        Directory.CreateDirectory(sites);
        File.WriteAllText(Path.Combine(sites, $"section{SectionNumber}.json"),
            $$"""{"name": "{{Course}}-s1-2026-gordon"}""".ToLowerInvariant());

        // Every /Query answers "no such task", so nothing is scheduled and no
        // /Delete can reach the real Task Scheduler.
        TaskScheduling.SchtasksForTests = _ => (1, "ERROR: The system cannot find the file specified.");
    }

    public void Dispose()
    {
        TaskScheduling.SchtasksForTests = null;
        try { Directory.Delete(_folder, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    // ---- The contract's cases --------------------------------------------

    public static IEnumerable<object[]> GetScenarioCases()
    {
        foreach (var scenario in Cases())
            yield return new object[] { scenario!["name"]!.ToString(), scenario.ToJsonString() };
    }

    private static JsonArray Cases() =>
        ContractLoader.LoadJson("assist-cases.json")["scenarios"]!["cases"]!.AsArray();

    /// <summary>
    /// The contract still HAS its scenarios. A theory over an empty list is a
    /// suite that passes having run nothing — which is the thing this file was
    /// rewritten for being an example of.
    /// </summary>
    [Fact]
    public void TheContractHasNotLostItsScenarios()
    {
        Assert.True(Cases().Count >= 8, $"The contract has lost scenarios: {Cases().Count} left.");
    }

    [Theory]
    [MemberData(nameof(GetScenarioCases))]
    public async Task AssistCases_Scenario_MatchesContract(string scenarioName, string caseJson)
    {
        Assert.NotEmpty(scenarioName);
        var scenario = JsonNode.Parse(caseJson)!.AsObject();
        var given = scenario["given"]?.AsObject();
        string when = scenario["when"]!.ToString();

        bool previewRunning = given?["previewRunning"]?.GetValue<bool>() ?? false;
        // Absent means NO window, as it does on the mac. The cases that need
        // one say so; a card scenario has none, so its deploy runs the launcher
        // rather than pressing a button that is not there.
        bool sectionWindowOpen = given?["sectionWindowOpen"]?.GetValue<bool>() ?? false;
        bool sectionBusy = given?["sectionBusy"]?.GetValue<bool>() ?? false;
        string? pending = given?["pending"]?.ToString();

        SetUpWhatThisCaseNeeds(when, pending);

        // ONE workspace and one tool server for the whole case, because that is
        // what the window holds for a conversation: the backup taken before the
        // first change is per-server, so a fresh one per call would back the
        // course up again on every turn.
        var tools = new RealTools(new AssistWorkspace(_folder, _launcher, undo: new UndoHistory()));
        var agent = new AssistAgent(new ScriptedModel(), tools, new JsonArray(), Course, SectionNumber)
        {
            PreviewIsShowing = () => previewRunning,
            SectionIsBusy = () => sectionBusy,
        };

        if (sectionWindowOpen)
        {
            agent.ShowPreviewInApp = () => _window.Note("startPreview");
            agent.StopPreviewInAppAsync = async () =>
            {
                // Two events with a real suspension between them, so a caller
                // that does not AWAIT the stop is told apart from one that
                // does. The real stop reaches into the container and takes
                // time; not waiting for it starts a build the stop then kills.
                _window.Note("stopPreview.begins");
                await Task.Delay(60);
                previewRunning = false;
                _window.Note("stopPreview.ends");
            };
            // The ASYNC seam, which is the one the app wires in production. The
            // window answers with the real sentence; the busy refusal is this
            // platform's AGENT to make rather than its window's, which is where
            // it differs from the mac — see AssistAgent.RunTool.
            agent.StartDeployInAppAsync = () =>
            {
                _window.Note("deploy");
                return Task.FromResult<string?>(AssistWording.Deployed(Course, SectionNumber.ToString()));
            };
        }

        var transcript = new List<string>();
        AssistToolAnswer? toolAnswer = null;

        if (when is "approve" or "decline" or "say")
        {
            await RunConversation(agent, tools, transcript, given, when, pending);
        }
        else
        {
            toolAnswer = await RunOneTool(agent, tools, transcript, when);
        }

        AssertEvents(scenario, scenarioName);
        AssertReply(scenario, toolAnswer, transcript);
        AssertTranscript(scenario, scenarioName, transcript);
    }

    // ---- What a case needs on disk ---------------------------------------

    /// <summary>
    /// The mac's <c>run</c> and <c>runApproval</c> do this same setup, and each
    /// piece of it is here for a refusal it prevents.
    /// </summary>
    private void SetUpWhatThisCaseNeeds(string when, string? pending)
    {
        if (when == "unpublish_pages")
        {
            // A page edit needs a page to edit, published so that unpublishing
            // it is a real change — and WATCHED, so the write lands in the
            // event sequence at the moment it actually happens on disk.
            Class("Unit 1, Day 1", "2026-09-08", published: true);
            _window.Watch(PagePath("Unit 1, Day 1"));
        }

        if (pending == "publish_class_on")
        {
            // A plan needs something real to plan about. The card phrasing is
            // "publish tomorrow's class", and the card reads TOMORROW off the
            // real clock — this app pins no date the way the mac's fixture does
            // — so the page has to be dated from the same clock.
            Class("Unit 1, Day 1", DateTime.Now.AddDays(1).ToString("yyyy-MM-dd"), published: false);
        }

        if (pending == "re_date_classes")
        {
            // A rollover needs three things or it refuses before reaching
            // anything worth asserting, and each refusal looks like a different
            // bug: with no class dates on file it offers the schedule sheet
            // instead ("I don't know when this section meets"), with no class
            // pages there is nothing to move, and with no site marker the
            // release reports "had no website yet" and the interesting branch
            // never runs. The marker is written in the constructor.
            //
            // Two classes on the SAME day against a two-meeting timetable, so
            // the first turn has something real to move — and the second turn
            // arrives with the dates already right, which is the state the
            // website answer is really given in, and the one that was broken.
            Class("Unit 1, Day 1", "2026-09-08", published: false);
            Class("Unit 1, Day 2", "2026-09-08", published: false);
            TimetableMemory.Write(_folder, Course, SectionNumber,
                new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10) },
                "typed in by hand", new DateOnly(2026, 9, 8));
        }
    }

    private string PagePath(string title) =>
        Path.Combine(_folder, "courses", Course, $"section{SectionNumber}", "All Classes", title + ".md");

    private void Class(string title, string date, bool published)
    {
        string full = PagePath(title);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full,
            $"---\ndraft: {(published ? "false" : "true")}\ncreated: {date}T07:00:00.000-0400\n---\nBody of {title}.\n");
    }

    // ---- Running one case ------------------------------------------------

    /// <summary>
    /// A CONVERSATION, not a single turn.
    ///
    /// <para><c>given.saying</c> lists what the teacher types, in order, each
    /// one settled before the next — because some behaviour exists only ACROSS
    /// turns. A rollover asks about the website on the first turn and is
    /// answered on the second, and that answer was a no-op for a while
    /// precisely because nothing exercised two turns in a row. When
    /// <c>saying</c> is absent, one turn is run using whichever fixed phrasing
    /// reaches <c>given.pending</c>.</para>
    /// </summary>
    private async Task RunConversation(AssistAgent agent, RealTools tools, List<string> transcript,
                                       JsonObject? given, string when, string? pending)
    {
        var conversation = new List<string>();
        if (given?["saying"] is JsonArray saying)
        {
            foreach (var line in saying) conversation.Add(line!.ToString());
        }
        else
        {
            Assert.NotNull(pending);
            conversation.Add(PhrasingReaching(pending!));
        }

        for (int turn = 0; turn < conversation.Count; turn++)
        {
            string phrasing = conversation[turn];
            bool isLastTurn = turn == conversation.Count - 1;

            // The window puts the teacher's own words in the transcript before
            // the agent answers; the agent's lines carry only its half.
            transcript.Add("teacher: " + phrasing);
            Render(tools, transcript, await agent.Say(phrasing, CancellationToken.None));

            if (!agent.IsAwaitingApproval)
            {
                Assert.False(isLastTurn && when == "approve",
                    $"nothing is waiting to be agreed to after “{phrasing}”");
                continue;
            }

            // "say" means the last turn is ANSWERED rather than proposed, and a
            // card there is the failure it exists to catch: a Go button on a
            // turn where pressing it would change nothing.
            Assert.False(isLastTurn && when == "say",
                $"“{phrasing}” put up a card, and this case says it is answered");

            if (isLastTurn && when == "decline")
            {
                transcript.Add("teacher: " + AssistWording.Cancelled);
                Render(tools, transcript, await agent.Decline(CancellationToken.None));
            }
            else
            {
                // The word on the button, chosen by the product's own rule
                // rather than by a copy of that rule kept here.
                transcript.Add("teacher: " + (AssistAgent.NeedsApproval(agent.PendingTool ?? "")
                    ? AssistWording.DeployAccepted : AssistWording.PlanAccepted));
                Render(tools, transcript, await agent.Approve(CancellationToken.None));
            }
        }
    }

    private async Task<AssistToolAnswer> RunOneTool(AssistAgent agent, RealTools tools,
                                                    List<string> transcript, string when)
    {
        var arguments = new JsonObject { ["course"] = Course, ["section"] = SectionNumber };
        if (when == "unpublish_pages") arguments["pages"] = new JsonArray("Unit 1, Day 1");

        var call = new JsonObject
        {
            ["id"] = "call-1",
            ["function"] = new JsonObject
            {
                ["name"] = when,
                ["arguments"] = arguments.ToJsonString(),
            },
        };

        var lines = new List<AssistAgent.Line>();
        var answer = await agent.RunTool(call, lines, CancellationToken.None);
        Render(tools, transcript, lines);
        // The teacher's half: what the transcript actually shows.
        Render(tools, transcript, new List<AssistAgent.Line> { new("tools", answer.Summary) });
        return answer;
    }

    // ---- What the transcript says ----------------------------------------

    /// <summary>Agent lines, rendered the way the contract writes a transcript line.</summary>
    /// <remarks>
    /// The contract's <c>tool(name)</c> speaker carries the tool that answered,
    /// and this app's <see cref="AssistAgent.Line"/> does not — the window
    /// renders every tool result the same way. <see cref="RealTools"/> is asked
    /// instead, being the one place that knows.
    /// </remarks>
    private static void Render(RealTools tools, List<string> transcript, List<AssistAgent.Line> lines)
    {
        foreach (var line in lines)
        {
            transcript.Add(line.Speaker == "tools"
                ? $"tool({tools.NameFor(line.Text)}): {line.Text}"
                : $"{line.Speaker}: {line.Text}");
        }
    }

    private void AssertEvents(JsonObject scenario, string scenarioName)
    {
        if (scenario["expectEvents"] is not JsonArray expected) return;

        var wanted = new List<string>();
        bool runsTheLauncherItself = false;
        foreach (var name in expected)
        {
            if (name!.ToString() == "runLauncherDirectly") { runsTheLauncherItself = true; continue; }
            wanted.Add(name.ToString());
        }

        Assert.Equal(wanted, _window.Events);

        // The ORDER is the assertion above; this is the other half of it —
        // whether the launcher was run here or a button was pressed instead.
        int deploys = _launcher.Runs.Count(run => run.Launcher == "deploy");
        if (runsTheLauncherItself)
            Assert.True(deploys == 1,
                $"{scenarioName}: with no window to press, the launcher is run directly — it ran {deploys} times");
        else
            Assert.True(deploys == 0,
                $"{scenarioName}: a window was open, so the window's own Deploy is what runs — " +
                $"the launcher ran {deploys} times");
    }

    private static void AssertReply(JsonObject scenario, AssistToolAnswer? toolAnswer, List<string> transcript)
    {
        if (scenario["expectReply"] is not JsonNode expectReply) return;
        string expected = Sentence(expectReply.ToString());

        if (toolAnswer is not null)
        {
            Assert.Equal(expected, toolAnswer.Summary);
            return;
        }
        // An approval case names its reply through the transcript instead.
        // Asserted rather than skipped: a skipped assertion is what #141 was.
        Assert.Contains(transcript, line => line.Contains(expected, StringComparison.Ordinal));
    }

    /// <summary>Both ordered transcript checks, so a case can use either.</summary>
    private static void AssertTranscript(JsonObject scenario, string scenarioName, List<string> transcript)
    {
        if (scenario["expectTranscriptContains"] is JsonArray contains)
        {
            int searchedFrom = 0;
            foreach (var entry in contains)
            {
                var (speaker, wanted) = SpeakerAndSentence(entry!.ToString());
                int found = -1;
                for (int i = searchedFrom; i < transcript.Count && found < 0; i++)
                {
                    if (transcript[i].StartsWith(speaker, StringComparison.Ordinal) &&
                        transcript[i].Contains(wanted, StringComparison.Ordinal))
                        found = i;
                }
                Assert.True(found >= 0,
                    $"{scenarioName}: no line in the transcript contains “{wanted}” — it says " +
                    string.Join(" | ", transcript));
                // The SAME line may satisfy the next expectation too, which is
                // the whole point of matching by contains: one reply composes
                // several named sentences — the question, how to answer it, and
                // what has NOT changed — and they are one bubble to a teacher.
                searchedFrom = found;
            }
        }

        if (scenario["expectTranscript"] is not JsonArray expected) return;

        // The named lines must appear IN THIS ORDER — not necessarily next to
        // each other, and not necessarily last. Order is portable; adjacency is
        // not: this app renders tool results differently from the mac and
        // should not be held to its arrangement.
        int from = 0;
        foreach (var entry in expected)
        {
            string wanted = ResolveLine(entry!.ToString());
            int found = -1;
            for (int i = from; i < transcript.Count && found < 0; i++)
                if (transcript[i] == wanted) found = i;
            Assert.True(found >= 0,
                $"{scenarioName}: the transcript never says “{wanted}” — it says " +
                string.Join(" | ", transcript));
            from = found + 1;
        }
    }

    // ---- The contract's names, mapped onto this platform ------------------

    /// <summary>
    /// A phrasing that reaches the named tool without the model — which is what
    /// lets an approval scenario run with no server anywhere near it. Read from
    /// the contract rather than from a list kept here, so the two cannot drift.
    /// </summary>
    private static string PhrasingReaching(string tool)
    {
        foreach (var match in ContractLoader.LoadJson("assist-cases.json")["cardPhrasings"]!["matches"]!.AsArray())
        {
            if (match!["tool"]!.ToString() == tool) return match["phrasing"]!.ToString();
        }
        throw new InvalidOperationException($"No card phrasing reaches {tool}; this scenario needs a model.");
    }

    private static readonly Lazy<JsonObject> AllWording = new(() =>
        JsonNode.Parse(File.ReadAllText(ContractLoader.GetContractPath("assist-wording.json")))!
            ["wording"]!.AsObject());

    /// <summary>"wording.deployed" to the real sentence, placeholders filled in.</summary>
    private static string Sentence(string named)
    {
        string key = named.StartsWith("wording.", StringComparison.Ordinal) ? named["wording.".Length..] : named;
        var found = AllWording.Value[key]
            ?? throw new InvalidOperationException($"No sentence called {key} in assist-wording.json");
        return found.GetValue<string>()
            .Replace("{course}", Course, StringComparison.Ordinal)
            .Replace("{section}", SectionNumber.ToString(), StringComparison.Ordinal);
    }

    /// <summary>
    /// "assistant: wording.deployWasCancelled" split into who said it and what
    /// they said, with a <c>wording.</c> name resolved to the real sentence.
    /// </summary>
    /// <remarks>
    /// The speaker is matched as a PREFIX and the sentence as a substring,
    /// SEPARATELY — the trailing ": " stays with the speaker. Resolving the
    /// whole thing and asking whether the line contains it would demand that
    /// the sentence follow the speaker immediately, which is exactly what a
    /// composed reply does not do: "tool(x): Re-dated 1 class.\n\nShould this
    /// be a new website…" contains the sentence, and does not contain
    /// "tool(x): Should this be a new website…".
    /// </remarks>
    private static (string Speaker, string Sentence) SpeakerAndSentence(string line)
    {
        int split = line.IndexOf(": ", StringComparison.Ordinal);
        if (split < 0) return ("", line);
        string speaker = line[..(split + 2)];
        string rest = line[(split + 2)..];
        // A literal that is not a `wording.` name is matched AS WRITTEN, which
        // is how a case anchors later expectations to a particular TURN.
        return (speaker, rest.StartsWith("wording.", StringComparison.Ordinal) ? Sentence(rest) : rest);
    }

    private static string ResolveLine(string line)
    {
        int split = line.IndexOf(": ", StringComparison.Ordinal);
        if (split < 0) return line;
        string rest = line[(split + 2)..];
        return rest.StartsWith("wording.", StringComparison.Ordinal)
            ? line[..(split + 2)] + Sentence(rest)
            : line;
    }

    // ---- The world one case runs in --------------------------------------

    /// <summary>
    /// A stand-in for a section window, which records the ORDER of what the
    /// assistant did to it — its preview, and its Deploy.
    /// </summary>
    /// <remarks>
    /// The order is the point. Stopping, writing and starting can all happen
    /// and still be wrong: a preview stopped AFTER the pages were rewritten was
    /// serving a half-changed site in between, and the teacher's next refresh
    /// is a race they cannot see they are in. So a "write" is noted the moment
    /// the watched page changes on disk, and a case reads the events back as a
    /// sequence rather than as a set.
    /// </remarks>
    private sealed class FakeSectionWindow
    {
        public List<string> Events { get; } = new();

        private string? _watchedPath;
        private string? _textWhenWatched;

        /// <summary>Watch a page, so a change to it lands in the sequence as "write".</summary>
        public void Watch(string path)
        {
            _watchedPath = path;
            _textWhenWatched = Read(path);
        }

        public void Note(string name)
        {
            NoteWriteIfItHappened();
            Events.Add(name);
        }

        private void NoteWriteIfItHappened()
        {
            if (_watchedPath is null || Events.LastOrDefault() == "write") return;
            string? now = Read(_watchedPath);
            if (now == _textWhenWatched) return;
            _textWhenWatched = now;
            Events.Add("write");
        }

        private static string? Read(string path)
        {
            try { return File.ReadAllText(path); } catch { return null; }
        }
    }

    /// <summary>Never answers: every message a scenario sends is a card phrasing, matched in code.</summary>
    private sealed class ScriptedModel : IChatModel
    {
        public Task<JsonObject?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation)
            => Task.FromResult<JsonObject?>(null);
    }

    /// <summary>
    /// The REAL tools, reached the way <c>plantoir-mcp</c> reaches them.
    /// </summary>
    /// <remarks>
    /// <para>Reflection over <see cref="PlantoirTools"/> rather than starting
    /// the server and speaking JSON-RPC to it: driving <c>plantoir-mcp</c> over
    /// stdio works and leaves a process holding <c>Plantoir.Core.dll</c> open if
    /// anything goes wrong, which then fails the NEXT build with a lock error
    /// that reads as "the app is open" when the app is not open at all. The
    /// same trade <see cref="AssistSurfaceContractTests"/> makes, for the same
    /// reason.</para>
    ///
    /// <para>An argument the tool does not declare is DROPPED, as the SDK's own
    /// binder drops it — <c>AssistAgent.RunTool</c> sets <c>preview</c> on tools
    /// that do not all take it. An argument that IS declared and cannot be
    /// converted throws instead of being dropped, because a runner that quietly
    /// drops one is the failure #141 was about.</para>
    /// </remarks>
    private sealed class RealTools : IToolServer
    {
        private readonly PlantoirTools _tools;
        private readonly Dictionary<string, MethodInfo> _served = new(StringComparer.Ordinal);
        private readonly Dictionary<string, string> _nameBySummary = new(StringComparer.Ordinal);
        private string _lastCalled = "";

        public RealTools(AssistWorkspace workspace)
        {
            _tools = new PlantoirTools(workspace);
            foreach (var method in typeof(PlantoirTools).GetMethods(BindingFlags.Public | BindingFlags.Instance))
            {
                var attribute = method.GetCustomAttribute<McpServerToolAttribute>();
                if (attribute is null) continue;
                // The SDK falls back to the method name when the attribute
                // gives none, and matching that keeps a tool declared without a
                // Name reachable rather than silently missing.
                _served[attribute.Name ?? method.Name] = method;
            }
        }

        /// <summary>Which tool produced a given answer, for the transcript's speaker.</summary>
        public string NameFor(string summary) =>
            _nameBySummary.TryGetValue(summary, out string? name) ? name : _lastCalled;

        public async Task<AssistToolAnswer> CallTool(string name, JsonObject arguments,
                                                     Action<string>? progress = null,
                                                     CancellationToken cancellation = default)
        {
            if (!_served.TryGetValue(name, out var method))
                throw new InvalidOperationException(
                    $"The contract asks for a tool this server does not serve: {name}");

            object? returned;
            try { returned = method.Invoke(_tools, Bind(method, arguments, cancellation)); }
            catch (TargetInvocationException wrapped) when (wrapped.InnerException is not null)
            {
                throw wrapped.InnerException;
            }

            if (returned is Task running)
            {
                await running;
                returned = running.GetType().GetProperty("Result")?.GetValue(running);
            }

            var answer = returned switch
            {
                CallToolResult result => Answer(result),
                string said => AssistToolAnswer.Same(said),
                null => throw new InvalidOperationException(
                    $"{name} answered with nothing this runner can read."),
                _ => throw new InvalidOperationException(
                    $"{name} answers with {returned.GetType().Name}, which this runner cannot read."),
            };

            // A plan twin's answer is spoken by the ASSISTANT and never shown as
            // a tool result, so it is not recorded here — a plain in-order queue
            // of calls would put the plan's name on the write's line.
            if (!name.StartsWith("plan_", StringComparison.Ordinal))
            {
                _lastCalled = name;
                _nameBySummary[answer.Summary] = name;
            }
            return answer;
        }

        /// <summary>The two halves, read apart exactly as <c>McpClient</c> reads them.</summary>
        private static AssistToolAnswer Answer(CallToolResult result)
        {
            var text = new System.Text.StringBuilder();
            foreach (var block in result.Content)
                if (block is TextContentBlock piece) text.AppendLine(piece.Text);
            string detail = text.ToString().TrimEnd();

            var meta = result.Meta;
            bool isPlan = meta?[AssistToolAnswer.IsPlanKey]?.GetValue<bool>() == true;
            string? summary = meta?[AssistToolAnswer.TeacherSummaryKey]?.GetValue<string>();
            string? backup = meta?[AssistToolAnswer.ConversationBackupKey]?.GetValue<string>();

            return string.IsNullOrWhiteSpace(summary)
                ? AssistToolAnswer.Same(detail) with { IsPlan = isPlan, ConversationBackupPath = backup }
                : new AssistToolAnswer(summary, detail, isPlan, backup);
        }

        private static object?[] Bind(MethodInfo method, JsonObject arguments, CancellationToken cancellation)
        {
            var parameters = method.GetParameters();
            var bound = new object?[parameters.Length];
            for (int i = 0; i < parameters.Length; i++)
            {
                var parameter = parameters[i];
                if (parameter.ParameterType == typeof(CancellationToken))
                {
                    bound[i] = cancellation;
                    continue;
                }
                if (parameter.ParameterType == typeof(IProgress<ProgressNotificationValue>))
                {
                    bound[i] = new Progress<ProgressNotificationValue>();
                    continue;
                }

                JsonNode? given = null;
                foreach (var (key, value) in arguments)
                    if (string.Equals(key, parameter.Name, StringComparison.OrdinalIgnoreCase)) given = value;

                if (given is null)
                {
                    bound[i] = parameter.HasDefaultValue ? parameter.DefaultValue
                        : parameter.ParameterType.IsValueType ? Activator.CreateInstance(parameter.ParameterType)
                        : null;
                    continue;
                }

                try { bound[i] = given.Deserialize(parameter.ParameterType); }
                catch (JsonException error)
                {
                    throw new InvalidOperationException(
                        $"{method.Name} takes {parameter.Name} as {parameter.ParameterType.Name}, " +
                        $"and the call sent {given.ToJsonString()}: {error.Message}");
                }
            }
            return bound;
        }
    }

    // ---- StartDeployInAppAsync: the assistant must say the REAL outcome ---
    //
    // documentation/12-windows-app.md: DeployForAsync used to resolve the
    // instant the click was dispatched, so RunTool always answered with the
    // unconditional AssistWording.Deployed — success or not. These wire the
    // production seam itself, with no tool server in reach: deploy_section is
    // answered by the window, and NoTools proves it never falls through.

    /// <summary>Reached only by a bug: these three cases never call a tool.</summary>
    private sealed class NoTools : IToolServer
    {
        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments,
                                               Action<string>? progress = null,
                                               CancellationToken cancellation = default)
            => throw new InvalidOperationException($"The window should have answered this, not {name}.");
    }

    [Fact]
    public async Task DeploySection_SucceedsWhenAsyncSeamReportsSuccess()
    {
        var agent = new AssistAgent(new ScriptedModel(), new NoTools(), new JsonArray(), Course, SectionNumber)
        {
            SectionIsBusy = () => false,
            PreviewIsShowing = () => false,
            StartDeployInAppAsync = () => Task.FromResult<string?>(
                AssistWording.Deployed(Course, SectionNumber.ToString())),
        };

        var answer = await agent.RunTool(DeployCall(), new List<AssistAgent.Line>(), CancellationToken.None);

        Assert.Equal(AssistWording.Deployed(Course, SectionNumber.ToString()), answer.Summary);
    }

    [Fact]
    public async Task DeploySection_ReportsFailureWhenAsyncSeamReportsFailure()
    {
        var agent = new AssistAgent(new ScriptedModel(), new NoTools(), new JsonArray(), Course, SectionNumber)
        {
            SectionIsBusy = () => false,
            PreviewIsShowing = () => false,
            // The deploy actually ran and failed — the outcome the old,
            // unconditional wording could never produce.
            StartDeployInAppAsync = () => Task.FromResult<string?>(
                AssistWording.DeployDidNotFinish(Course, SectionNumber.ToString())),
        };

        var answer = await agent.RunTool(DeployCall(), new List<AssistAgent.Line>(), CancellationToken.None);

        Assert.Equal(AssistWording.DeployDidNotFinish(Course, SectionNumber.ToString()), answer.Summary);
        Assert.DoesNotContain("is deployed", answer.Summary);
    }

    [Fact]
    public async Task DeploySection_FallsBackToDidNotFinishWhenAsyncSeamReturnsNull()
    {
        // Null means "the deploy never actually ran" (refused, already busy, an
        // exception before it started) — the fallback must never be the success
        // wording, which is exactly the bug being closed.
        var agent = new AssistAgent(new ScriptedModel(), new NoTools(), new JsonArray(), Course, SectionNumber)
        {
            SectionIsBusy = () => false,
            PreviewIsShowing = () => false,
            StartDeployInAppAsync = () => Task.FromResult<string?>(null),
        };

        var answer = await agent.RunTool(DeployCall(), new List<AssistAgent.Line>(), CancellationToken.None);

        Assert.Equal(AssistWording.DeployDidNotFinish(Course, SectionNumber.ToString()), answer.Summary);
    }

    private static JsonObject DeployCall() => new()
    {
        ["id"] = "call-1",
        ["function"] = new JsonObject { ["name"] = "deploy_section", ["arguments"] = "{}" },
    };
}
