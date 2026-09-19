using System.Globalization;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A relative day the MODEL filled in, settled once where its call is made.
///
/// <para>Issue #159, the second half of #143 and the one place the two apps
/// still differed on relative days. The card path has settled its own word
/// since #116 (<see cref="PublishTomorrowsClassTests"/>); this is the other
/// path — <c>date: "tomorrow"</c> written by the model itself, which
/// <c>ClassDateHelp</c> tells it not to write and which a small model writes
/// anyway. One call object is read three times, by the approval card, by the
/// <c>plan_</c> twin and by the act, and each of those used to reach the
/// server's <c>DayFor</c>, which reads the clock per call. A conversation open
/// across midnight could plan one day and publish another, silently, reporting
/// success.</para>
///
/// <para><b>The schemas are not optional here.</b> The settler asks the TOOL
/// SURFACE which argument carries a class day, so an agent built with an empty
/// schema array — which every other rig in this suite passes, because nothing
/// else in the loop reads them — makes every test below pass vacuously. These
/// deserialise <c>contracts/assist-cases.json</c> → <c>toolSchemas.local</c>,
/// the same surface the window narrows to and the same one the local model is
/// shown.</para>
///
/// <para>WHICH day a word names is not asserted here: that is
/// <c>contracts/schedule-rules.json</c> → <c>relativeDays</c>, run by both
/// platforms. What is asserted here is WHEN it is decided.</para>
/// </summary>
public class RelativeDayFreshnessTests
{
    /// <summary>A Tuesday — the day the contract's relative-day cases count from.</summary>
    private static readonly DateOnly Tuesday = new(2026, 9, 8);

    // ---- The fakes -------------------------------------------------------

    /// <summary>A model that answers with prepared replies, handed back as-is.</summary>
    /// <remarks>
    /// The reply object is NOT cloned on the way out, deliberately: a test
    /// keeps its own handle on it and reads the arguments string back
    /// afterwards, which is the only way to see that a call was left exactly
    /// as it arrived.
    /// </remarks>
    private sealed class ScriptedModel : IChatModel
    {
        private readonly Queue<JsonObject?> _replies = new();
        public readonly List<JsonArray> Asked = new();

        /// <summary>Replies prepared and not yet handed out.</summary>
        public int Waiting => _replies.Count;

        public void Then(JsonObject? reply) => _replies.Enqueue(reply);

        public Task<JsonObject?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation)
        {
            Asked.Add((JsonArray)messages.DeepClone());
            return Task.FromResult(_replies.Count > 0 ? _replies.Dequeue() : null);
        }
    }

    /// <summary>A tool server that records what it was handed.</summary>
    private sealed class RecordingTools : IToolServer
    {
        public readonly List<(string Name, JsonObject Arguments)> Calls = new();

        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments,
                                               Action<string>? progress = null,
                                               CancellationToken cancellation = default)
        {
            Calls.Add((name, (JsonObject)arguments.DeepClone()));

            if (name.StartsWith("plan_", StringComparison.Ordinal))
                return Task.FromResult(new AssistToolAnswer("This would publish one page.",
                                                            "This would publish one page.", IsPlan: true));
            return Task.FromResult(AssistToolAnswer.Same("Done."));
        }
    }

    /// <summary>An agent wired as the window wires it, with a clock a test can move.</summary>
    private sealed class Rig
    {
        public readonly ScriptedModel Model = new();
        public readonly RecordingTools Tools = new();

        /// <summary>The one clock. Move it to walk the conversation over midnight.</summary>
        public DateOnly Today = Tuesday;

        public bool Confirming = true;

        public readonly AssistAgent Agent;

        public Rig()
        {
            Agent = new AssistAgent(Model, Tools, LocalSchemas(), "ICS3U", 1)
            {
                ConfirmationMode = () => Confirming,
                Today = () => this.Today,
            };
        }

        public List<AssistAgent.Line> Say(string text) =>
            Agent.Say(text, CancellationToken.None).GetAwaiter().GetResult();

        /// <summary>
        /// Say something that must reach the MODEL, and prove that it did.
        /// </summary>
        /// <remarks>
        /// <para>Every test of the settler needs this, and an adversarial
        /// review is what found out why: six of the tests here first said
        /// "publish tomorrow's class", which is one of the eight FIXED CARD
        /// PHRASINGS. <c>Say</c> answers those in code and never asks the
        /// model at all, so the prepared reply was never handed out, the
        /// settler never ran, and every assertion about the call the model
        /// had "sent" was made about an object nothing had touched. They
        /// passed, and they pinned nothing.</para>
        ///
        /// <para>So the sentence is checked against the card matcher HERE,
        /// as an assertion rather than as a comment: if a phrasing used by
        /// one of these tests is ever adopted as a card, the test says so
        /// instead of quietly going hollow. And the reply must have been
        /// taken, which is the other half of the same proof.</para>
        /// </remarks>
        public List<AssistAgent.Line> SayThroughTheModel(string text)
        {
            Assert.True(AssistCardCommand.Matching(text) is null,
                $"“{text}” is a fixed card phrasing, so it is answered in code and the model — " +
                "and the settler with it — never sees this call. Pick a sentence no card matches.");

            int waiting = Model.Waiting;
            var lines = Say(text);

            Assert.NotEmpty(Model.Asked);
            Assert.True(Model.Waiting < waiting,
                "the prepared reply was never handed out, so nothing under test ran.");
            return lines;
        }

        public List<AssistAgent.Line> Approve() =>
            Agent.Approve(CancellationToken.None).GetAwaiter().GetResult();
    }

    /// <summary>The tools the local model is shown, from the contract both apps run.</summary>
    private static JsonArray LocalSchemas() =>
        ContractLoader.LoadJson("assist-cases.json")["toolSchemas"]!["local"]!.DeepClone().AsArray();

    /// <summary>A model reply that calls one tool, with the arguments spelled out.</summary>
    private static JsonObject Calling(string tool, string argumentsJson) => new()
    {
        ["tool_calls"] = new JsonArray(new JsonObject
        {
            ["id"] = "call-0",
            ["function"] = new JsonObject { ["name"] = tool, ["arguments"] = argumentsJson },
        }),
    };

    /// <summary>The arguments string as it stands on a reply the agent has seen.</summary>
    private static string ArgumentsOn(JsonObject reply) =>
        reply["tool_calls"]![0]!["function"]!["arguments"]!.ToString();

    // ---- The day the plan named is the day that runs ---------------------

    /// <summary>
    /// A plan shown before midnight and agreed to after it publishes the class
    /// the plan described.
    /// </summary>
    /// <remarks>
    /// The three readers of this one call are the plan twin, the approval card
    /// and the act. The card holds the very object the act is run from — that
    /// is what <c>Approve</c> hands to <c>RunTool</c> — so the act's arguments
    /// below are the card's arguments, and settling once covers all three.
    /// </remarks>
    [Fact]
    public void ThePlanAndTheActNameTheSameDayAcrossMidnight()
    {
        var rig = new Rig();
        rig.Model.Then(Calling("publish_class_on",
            """{"course": "ICS3U", "section": 1, "date": "tomorrow"}"""));

        rig.SayThroughTheModel("publish tomorrow's class for me");

        var twin = Assert.Single(rig.Tools.Calls);
        Assert.Equal("plan_publish_class_on", twin.Name);
        Assert.Equal("2026-09-09", twin.Arguments["date"]!.ToString());
        Assert.True(rig.Agent.IsAwaitingApproval);

        // The teacher reads the plan, and midnight passes before they press Go.
        rig.Today = new DateOnly(2026, 9, 9);
        rig.Approve();

        Assert.Equal(2, rig.Tools.Calls.Count);
        var act = rig.Tools.Calls[1];
        Assert.Equal("publish_class_on", act.Name);
        Assert.Equal("2026-09-09", act.Arguments["date"]!.ToString());
    }

    /// <summary>
    /// A word the reader refuses is passed on as it arrived, so the tool
    /// answers with its own sentence about it.
    /// </summary>
    /// <remarks>
    /// "next monday" can mean the coming Monday or the one after, people
    /// disagree, and a date guessed wrong dates a class wrong in silence —
    /// <c>contracts/schedule-rules.json</c> → <c>relativeDays</c> pins the
    /// refusal. A settler that invented a day here would be worse than one
    /// that never ran.
    /// </remarks>
    [Fact]
    public void AWordThatCannotBeReadIsLeftForTheToolToAnswer()
    {
        var rig = new Rig();
        var reply = Calling("publish_class_on",
            """{"course": "ICS3U", "section": 1, "date": "next monday"}""");
        rig.Model.Then(reply);

        rig.SayThroughTheModel("publish next monday's class");

        Assert.Equal("next monday", Assert.Single(rig.Tools.Calls).Arguments["date"]!.ToString());
        Assert.Contains("next monday", ArgumentsOn(reply));
    }

    /// <summary>An absolute date is already a day, and settles to itself.</summary>
    [Fact]
    public void AnAbsoluteDateIsLeftAsTheDayItAlreadyIs()
    {
        var rig = new Rig();
        rig.Model.Then(Calling("publish_class_on",
            """{"course": "ICS3U", "section": 1, "date": "2026-10-01"}"""));

        rig.SayThroughTheModel("publish the class on the first of October");

        Assert.Equal("2026-10-01", Assert.Single(rig.Tools.Calls).Arguments["date"]!.ToString());
    }

    /// <summary>
    /// <c>schedule_deploy</c>'s <c>when</c> is untouched, and by construction
    /// rather than by being remembered.
    /// </summary>
    /// <remarks>
    /// It is a day AND a time, and the tool declares no <c>date</c> at all, so
    /// the gate never opens for it.
    ///
    /// <para>Note what this does NOT catch: widening the gate leaves
    /// <c>when</c> alone anyway, because the rewrite only ever reads and
    /// writes <c>date</c>. The sweep below is what goes red if the gate stops
    /// asking the surface. What this pins is the other half — that <c>when</c>
    /// is never renamed, never settled and never joined by a <c>date</c> the
    /// tool would not know what to do with.</para>
    /// </remarks>
    [Fact]
    public void AScheduledDeploysWhenIsNotTouched()
    {
        var rig = new Rig();
        var reply = Calling("schedule_deploy",
            """{"course": "ICS3U", "section": 1, "when": "tomorrow 06:30"}""");
        rig.Model.Then(reply);

        rig.SayThroughTheModel("deploy at half six tomorrow");
        Assert.True(rig.Agent.IsAwaitingApproval);
        rig.Approve();

        var act = Assert.Single(rig.Tools.Calls);
        Assert.Equal("schedule_deploy", act.Name);
        Assert.Equal("tomorrow 06:30", act.Arguments["when"]!.ToString());
        Assert.False(act.Arguments.ContainsKey("date"));
        Assert.DoesNotContain("2026-09-09", ArgumentsOn(reply));
    }

    // ---- What a small model sends when it is having a bad day ------------

    /// <summary>
    /// A <c>date</c> that is not a string is passed through rather than thrown
    /// on.
    /// </summary>
    /// <remarks>
    /// A model that answers <c>"date": 20260920</c> — or <c>null</c>, or an
    /// object — is exactly what <c>ArgumentsOf</c> and <c>RunTool</c> already
    /// defend against, and nothing wraps the loop's call handling. A rewrite
    /// is the last place that should be the one to throw.
    /// </remarks>
    [Theory]
    [InlineData("""{"course": "ICS3U", "section": 1, "date": 20260920}""")]
    [InlineData("""{"course": "ICS3U", "section": 1, "date": true}""")]
    [InlineData("""{"course": "ICS3U", "section": 1, "date": null}""")]
    [InlineData("""{"course": "ICS3U", "section": 1, "date": {"day": "tomorrow"}}""")]
    [InlineData("""{"course": "ICS3U", "section": 1, "date": ["tomorrow"]}""")]
    public void ADateThatIsNotAStringIsPassedThroughUntouched(string argumentsJson)
    {
        var rig = new Rig();
        var reply = Calling("publish_class_on", argumentsJson);
        rig.Model.Then(reply);

        rig.SayThroughTheModel("put tomorrow's class up for me, please");

        Assert.Equal(argumentsJson, ArgumentsOn(reply));
        Assert.Single(rig.Tools.Calls);
    }

    /// <summary>Arguments that are not JSON at all are left exactly as they came.</summary>
    [Fact]
    public void ArgumentsThatAreNotJsonAreLeftAlone()
    {
        const string nonsense = """{"course": "ICS3U", "date": "tomorrow" """;
        var rig = new Rig();
        var reply = Calling("publish_class_on", nonsense);
        rig.Model.Then(reply);

        rig.SayThroughTheModel("put tomorrow's class up for me, please");

        Assert.Equal(nonsense, ArgumentsOn(reply));
    }

    // ---- The gate, swept across the whole surface ------------------------

    /// <summary>
    /// The tools THIS rewrite touches are exactly the tools whose schema
    /// declares a <c>date</c>.
    /// </summary>
    /// <remarks>
    /// <para>Asked of the surface, never of a list kept beside the settling
    /// code, because a list is how the next tool with a date gets quietly left
    /// out. What the gate really tracks is WHAT CONSULTS THE CLOCK:
    /// <c>publish_class_on</c>'s <c>date</c> reaches <c>PlantoirTools.DayFor</c>,
    /// while <c>publish_pages</c> and <c>unpublish_pages</c> take <c>before</c>
    /// and <c>onOrAfter</c> to a strict invariant parser that REFUSES
    /// "tomorrow". A forgiving parser behind one of those names would reopen
    /// the hole with this gate shut — which is why this sweep exists: to make
    /// the next such argument a visible decision rather than an oversight.</para>
    ///
    /// <para>Scoped to the DAY rewrite on purpose. Another rewrite at this
    /// seam — binding the model's course and section to this window's, issue
    /// #180 — touches every call and must not turn this red.</para>
    /// </remarks>
    [Fact]
    public void TheDaySettlerTouchesExactlyTheToolsThatDeclareADate()
    {
        var declaring = new SortedSet<string>(StringComparer.Ordinal);
        var settled = new SortedSet<string>(StringComparer.Ordinal);

        foreach (var schema in LocalSchemas())
        {
            string tool = schema!["function"]!["name"]!.ToString();
            if (schema["function"]!["parameters"]?["properties"]?["date"] is not null) declaring.Add(tool);

            var rig = new Rig();
            var reply = Calling(tool, """{"course": "ICS3U", "section": 1, "date": "tomorrow"}""");
            rig.Model.Then(reply);

            rig.SayThroughTheModel("do the thing");
            if (rig.Agent.IsAwaitingApproval) rig.Approve();

            // Read as VALUES rather than as text: a rewrite re-serialises the
            // whole object, so comparing strings here would be comparing
            // formatting as much as meaning.
            var after = JsonNode.Parse(ArgumentsOn(reply))!.AsObject();
            if (after["date"]!.ToString() == "2026-09-09") settled.Add(tool);
        }

        Assert.NotEmpty(declaring);
        Assert.Equal(declaring, settled);
    }

    // ---- The dateline, from the same clock and in one calendar -----------

    /// <summary>
    /// The sentence the model does its own date arithmetic from is built from
    /// this class's clock, not a second reading of the machine's.
    /// </summary>
    [Fact]
    public void TheDatelineIsBuiltFromTheOneClock()
    {
        var rig = new Rig();
        rig.Model.Then(new JsonObject { ["content"] = "Nothing to do." });

        rig.Say("what day is it?");

        string userTurn = rig.Model.Asked[0][^1]!["content"]!.ToString();
        Assert.Equal("what day is it? (Today is 2026-09-08, a Tuesday.)", userTurn);
    }

    /// <summary>
    /// A machine whose default calendar is not Gregorian is told the same year
    /// as everybody else.
    /// </summary>
    /// <remarks>
    /// <para>Measured for issue #144: <c>ToString("yyyy-MM-dd")</c> with no
    /// culture renders <c>2569-09-09</c> on a Thai-locale Windows machine. The
    /// dateline rides on every model-routed message, so an affected teacher's
    /// assistant was being told the wrong year on every turn — and the
    /// scheduled deploy below is a date the app WRITES, which is the half that
    /// lasts.</para>
    ///
    /// <para>The third assertion is the same trap met from the READING end.
    /// The card's sentence parses the moment back out of the string the app
    /// has just written, and a lenient <c>DateTime.TryParse</c> reads 2026 in
    /// the machine's calendar — Buddhist 2026, which is 1483 — so the card
    /// named a weekday five centuries out while the deploy itself fired on the
    /// right day. The DATE is checked through the culture's own rendering of
    /// the moment that is correct, so what is compared is which moment the
    /// card describes rather than how Thai writes a Wednesday.</para>
    /// </remarks>
    [Fact]
    public void ANonGregorianMachineIsToldTheSameYearAsEverybodyElse()
    {
        var was = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("th-TH");

            var rig = new Rig();
            rig.Model.Then(new JsonObject { ["content"] = "Nothing to do." });
            rig.Say("what day is it?");

            string userTurn = rig.Model.Asked[0][^1]!["content"]!.ToString();
            Assert.Equal("what day is it? (Today is 2026-09-08, a Tuesday.)", userTurn);

            var scheduling = new Rig();
            var asked = scheduling.Say("Deploy tomorrow's class at 6:30 AM");

            string card = asked[0].Text;
            Assert.Contains(new DateTime(2026, 9, 9, 6, 30, 0).ToString("dddd d MMMM, h:mm tt"), card);

            scheduling.Approve();

            Assert.Equal("2026-09-09 06:30",
                Assert.Single(scheduling.Tools.Calls).Arguments["when"]!.ToString());
        }
        finally
        {
            CultureInfo.CurrentCulture = was;
        }
    }
}
