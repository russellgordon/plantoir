using System.Reflection;
using System.Text.Json.Nodes;
using ModelContextProtocol.Server;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #720 (the mac's #689): one teacher action asks the local model at most
/// <c>shared-rules.json</c> → <c>assistantLapLimit</c> →
/// <c>mostModelRequestsPerTurn</c> times, and the turn that reaches it says
/// <c>wording.wentRoundWithoutFinishing</c> — "…so nothing was changed".
/// </summary>
/// <remarks>
/// <para><b>Why the write-tools tests come first.</b> "Nothing was changed"
/// is true on Windows only because a WRITE ends the turn:
/// <c>AssistToolRunner.Run</c> hands the turn back to the app for every
/// <see cref="AssistToolRunner.IsWriteTool"/> name (and for
/// <c>check_section</c> and <c>read_remembered_timetable</c>), so the only
/// calls that come before another lap are reads. A write missing from
/// <see cref="AssistToolRunner.WriteTools"/> would run, lap, and could then
/// reach the cap, and the sentence would be false. The mac's rule is
/// per-outcome (<c>shouldContinue</c>); this list is the same rule by name,
/// and it has been wrong before (<c>roll_over_course</c> for
/// <c>roll_over_section</c>, five writes missing — <c>AssistAgent.IsWriteTool</c>'s
/// comment).</para>
///
/// <para><b>What counts as a write</b> is the server's own annotation: a
/// <c>[McpServerTool]</c> without <c>ReadOnly = true</c>.</para>
///
/// <para><b>Which tools are in scope: every tool a LAP can run.</b> Only two
/// doors lead into <c>AssistAgent.Run()</c>, the loop that laps: a sentence
/// the model answers (<c>Say</c>), where the model can name only
/// <c>ForTheLocalModel</c> (anything else it was not offered is refused before
/// it runs), and Go (<c>Approve</c>), which runs the call that was held and
/// laps only if that call was not handed back. A card's DIRECT run
/// (<c>RunCommand</c> → <c>RunTool</c>) never laps; a card held for approval
/// reaches <c>Run()</c> only through <c>Approve</c>, with a tool already in
/// scope — <c>NeedsApproval</c> (<c>DeploysToStudents</c>) or a key of
/// <c>PlanTwins</c>. That is why <c>explain_publishing</c>, a card that is not
/// annotated ReadOnly and writes nothing, is not in scope.</para>
///
/// <para><b>A known difference, unchanged:</b> <c>check_section</c> ends the
/// turn here and laps on the mac. The contract's scenario uses
/// <c>list_pages</c>, which laps on both.</para>
/// </remarks>
[Collection(SharedActivityState.Name)]
public class AssistLapCapTests : IDisposable
{
    private readonly string _trail = Path.Combine(Path.GetTempPath(), $"plantoir-lapcap-{Guid.NewGuid():N}.txt");

    public AssistLapCapTests() => ActivityTrail.SetCustomLogPathForTesting(_trail);

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trail); } catch { }
    }

    private static JsonNode LapLimit => ContractLoader.LoadJson("shared-rules.json")["assistantLapLimit"]!;

    private static int TheContractsCap => LapLimit["mostModelRequestsPerTurn"]!.GetValue<int>();

    private const string ListPages = "{\"course\":\"VVH2O\",\"section\":1}";

    /// <summary>An agent with no cards in the way: the sentence goes to the model.</summary>
    private static AssistAgent Agent(ScriptModel model, CannedTools tools) =>
        new(model, tools, new JsonArray(), "VVH2O", 1) { ConfirmationMode = () => false };

    private static ScriptModel Reading(int times, ScriptModel? model = null)
    {
        model ??= new ScriptModel();
        for (int i = 0; i < times; i++) model.Calls("list_pages", ListPages);
        return model;
    }

    private static List<AssistAgent.Line> Say(AssistAgent agent, string text) =>
        agent.Say(text, CancellationToken.None).GetAwaiter().GetResult();

    // ---- The number and the sentence are the contract's ----------------------

    [Fact]
    public void TheCapIsTheContractsNumber()
    {
        Assert.Equal(TheContractsCap, AssistAgent.MostStepsPerTurn);
        string key = LapLimit["wording"]!.ToString();
        Assert.Equal("wording.wentRoundWithoutFinishing", key);
        string sentence = ContractLoader.LoadJson("assist-wording.json")["wording"]![key["wording.".Length..]]!.ToString();
        Assert.Equal(sentence, AssistWording.WentRoundWithoutFinishing);
        Assert.Equal(LapLimit["trailEvent"]!.ToString(),
                     ActivityTrail.KeyFor(ActivityTrail.Event.AssistantWentRoundWithoutFinishing));
    }

    // ---- What the cap does ---------------------------------------------------

    [Fact]
    public void ATurnThatAnswersOnTheSixthRequestIsAnswered()
    {
        var model = Reading(TheContractsCap - 1).Says("Here is what is in the section.");
        var lines = Say(Agent(model, new CannedTools()), "look round the section for me");

        Assert.Equal(TheContractsCap, model.Asked.Count);
        Assert.Equal("Here is what is in the section.", lines[^1].Text);
        Assert.DoesNotContain(lines, line => line.Text == AssistWording.WentRoundWithoutFinishing);
        Assert.False(File.Exists(_trail) && File.ReadAllText(_trail).Contains("went round", StringComparison.Ordinal));
    }

    [Fact]
    public void TheTurnIsWoundBackOutOfWhatTheModelReadsNext()
    {
        var model = Reading(TheContractsCap).Says("Hello.");
        var tools = new CannedTools();
        var agent = Agent(model, tools);

        var first = Say(agent, "look round the section for me");
        // The conversation before turn one: its first request less the sentence.
        int before = model.Asked[0].Count - 1;
        Assert.Equal(TheContractsCap, model.Asked.Count);   // the seventh request was never sent
        Assert.Equal(TheContractsCap, tools.Calls.Count);    // and the sixth chosen tool ran
        Assert.Equal(AssistWording.WentRoundWithoutFinishing, first[^1].Text);
        // The transcript keeps the turn's tool lines; only the model's copy goes.
        Assert.Equal(TheContractsCap, first.Count(line => line.Speaker == "tools"));

        Say(agent, "hello");
        var next = model.Asked[TheContractsCap];
        Assert.DoesNotContain("look round the section", next.ToJsonString());
        Assert.DoesNotContain("list_pages", next.ToJsonString());
        Assert.DoesNotContain(next, message => message?["role"]?.ToString() == "tool");
        Assert.Equal(before + 1, next.Count);
    }

    [Fact]
    public void TheTrailSaysHowManyTimesAndWhatItKeptChoosing()
    {
        var model = new ScriptModel();
        for (int i = 0; i < TheContractsCap; i++)
            model.Calls("read_page", "{\"course\":\"VVH2O\",\"section\":1,\"page\":\"Secret Lesson Title\"}");

        Say(Agent(model, new CannedTools()), "go through my private notes");

        // The line is "<stamp> · VVH2O/1 · <what>", and <what> is the helper's
        // sentence exactly: the count, the tool in words, stopped, taken back.
        string trail = File.ReadAllText(_trail);
        string line = Assert.Single(trail.Split('\n'), l => l.Contains("went round", StringComparison.Ordinal));
        const string where = " · VVH2O/1 · ";
        Assert.Contains(where, line);
        Assert.Equal(AssistAgent.WentRoundWithoutFinishingLine(TheContractsCap, "read_page"),
                     line[(line.IndexOf(where, StringComparison.Ordinal) + where.Length)..].TrimEnd('\r'));
        Assert.Contains("last choosing read page", line);
        // Never the teacher's sentence, never an argument value.
        Assert.DoesNotContain("private notes", line);
        Assert.DoesNotContain("Secret Lesson Title", trail);
    }

    [Fact]
    public void EachSentenceStartsTheCountAgain()
    {
        // Two turns of three reads and an answer: eight requests in all, more
        // than the cap, and neither turn reaches it. (The mac found that two
        // reads and an answer per turn passed even with the reset deleted.)
        var model = Reading(3).Says("First answer.");
        Reading(3, model).Says("Second answer.");
        var agent = Agent(model, new CannedTools());

        var first = Say(agent, "look round the section for me");
        var second = Say(agent, "and look round it again");

        Assert.Equal(8, model.Asked.Count);
        Assert.Equal("First answer.", first[^1].Text);
        Assert.Equal("Second answer.", second[^1].Text);
    }

    // ---- Every write a lap can run ends the turn ----------------------------

    /// <summary>Every tool the MCP server serves, by name, with whether it is annotated ReadOnly.</summary>
    private static Dictionary<string, bool> ServedReadOnly()
    {
        var served = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        foreach (var method in typeof(PlantoirTools).GetMethods(BindingFlags.Public | BindingFlags.Instance))
        {
            var attribute = method.GetCustomAttribute<McpServerToolAttribute>();
            if (attribute is null) continue;
            served[attribute.Name ?? method.Name] = attribute.ReadOnly;
        }
        return served;
    }

    /// <summary>The tools a lap of the in-app assistant can run (see the remarks above).</summary>
    private static IReadOnlyCollection<string> ALapCanRun() =>
        AssistAgent.ForTheLocalModel
            .Concat(AssistAgent.DeploysToStudents)
            .Concat(AssistAgent.PlanTwins.Keys)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

    [Fact]
    public void EveryWriteALapCanRunIsAWriteTool()
    {
        var served = ServedReadOnly();
        Assert.True(served.Count >= 40, $"the reflection found {served.Count} tools; it is not reading the server");

        var missing = new List<string>();
        foreach (string tool in ALapCanRun())
        {
            Assert.True(served.ContainsKey(tool), $"{tool} can be run by a lap but the server does not serve it");
            if (!served[tool] && !AssistToolRunner.IsWriteTool(tool)) missing.Add(tool);
        }
        Assert.True(missing.Count == 0,
            "These tools write (no ReadOnly on their [McpServerTool]) and a lap can run them, but they are not in " +
            "AssistToolRunner.WriteTools, so they would not end the turn — and the lap cap's \"nothing was changed\" " +
            "would be false: " + string.Join(", ", missing));
    }

    [Fact]
    public void EveryWriteToolNamesAServedWrite()
    {
        var served = ServedReadOnly();
        foreach (string tool in AssistToolRunner.WriteTools)
        {
            Assert.True(served.ContainsKey(tool), $"WriteTools names {tool}, which the server does not serve (a misspelt name ends no turn)");
            Assert.False(served[tool], $"WriteTools names {tool}, which the server annotates ReadOnly");
        }
    }
}
