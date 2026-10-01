using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #217 (the mac's #215): "hide" is "unpublish", read in code; and a reply
/// that is only the teacher's request handed back is refused and wound back.
/// Both halves are run from <c>contracts/assist-cases.json</c> —
/// <c>hideIsUnpublish</c> and <c>echoedRequest</c> — not retyped here.
/// </summary>
[Collection(SharedActivityState.Name)]
public class HideAndEchoContractTests : IDisposable
{
    private readonly string _trail = Path.Combine(Path.GetTempPath(), "plantoir-echo-" + Guid.NewGuid().ToString("N") + ".txt");

    public HideAndEchoContractTests() => ActivityTrail.SetCustomLogPathForTesting(_trail);

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trail); } catch { }
        GC.SuppressFinalize(this);
    }

    private static JsonObject Cases(string key) => ContractLoader.LoadJson("assist-cases.json")[key]!.AsObject();

    // ---- hideIsUnpublish --------------------------------------------------

    [Fact]
    public void EveryAcceptedSpellingReachesUnpublishWithThePageBuiltInCapitals()
    {
        var accepted = Cases("hideIsUnpublish")["accepted"]!.AsArray();
        Assert.True(accepted.Count >= 13, "hideIsUnpublish.accepted has lost rows");
        foreach (var row in accepted)
        {
            string input = row!["input"]!.ToString();
            var matched = AssistCardCommand.Matching(input);
            Assert.True(matched is not null, $"“{input}” matched nothing: {row["why"]}");
            Assert.Equal(row["expectTool"]!.ToString(), matched!.ToolName);
            Assert.Equal(row["expectPages"]!.ToString(), matched.Arguments["pages"]);
        }
    }

    /// <summary>
    /// A refused row matches NO family at all — the TOLERANCE is asserted, not
    /// only the reference: "publish unit 4?" must not publish a whole unit
    /// with no model in the loop.
    /// </summary>
    [Fact]
    public void EveryRefusedSpellingMatchesNothing()
    {
        var refused = Cases("hideIsUnpublish")["refused"]!.AsArray();
        Assert.True(refused.Count >= 20, "hideIsUnpublish.refused has lost rows");
        var wrongly = refused
            .Select(row => row!["input"]!.ToString())
            .Where(input => AssistCardCommand.Matching(input) is not null)
            .ToList();
        Assert.True(wrongly.Count == 0, "matched in code, and the contract refuses: " + string.Join(" | ", wrongly));
    }

    // ---- echoedRequest ----------------------------------------------------

    [Fact]
    public void TheEchoRuleIsTheContracts()
    {
        var cases = Cases("echoedRequest")["cases"]!.AsArray();
        Assert.True(cases.Count >= 9, "echoedRequest has lost cases");
        foreach (var row in cases)
        {
            bool echo = AssistAgent.IsTheRequestBackAgain(
                row!["sent"]?.ToString(), row["typed"]?.ToString(),
                row["reply"]!.ToString(), row["hasToolCall"]!.GetValue<bool>());
            Assert.True(echo == row["expectEcho"]!.GetValue<bool>(), $"{row["why"]}");
        }
    }

    /// <summary>
    /// The measured fault, end to end: the echo is not shown, is recorded, and
    /// is taken back out — so the NEXT request is sent as if fresh, which is
    /// the measured cure (a fresh conversation routes it correctly).
    /// </summary>
    [Fact]
    public async Task AnEchoIsRefusedAndTheNextTurnIsSentFresh()
    {
        const string typed = "take Unit 4, Day 20 off the site for now";
        Assert.Null(AssistCardCommand.Matching(typed));
        var model = new WindowBindingContractTests.ScriptedModel();
        var agent = new AssistAgent(model, new WindowBindingContractTests.RecordingTools(),
            ContractLoader.LoadJson("assist-cases.json")["toolSchemas"]!["local"]!.DeepClone().AsArray(), "ICS3U", 1)
        {
            Today = () => new DateOnly(2026, 9, 19),
        };
        // The echo, verbatim: date line and all, with a capital on it.
        model.Then(new JsonObject { ["content"] = "Take Unit 4, Day 20 off the site for now (Today is 2026-09-19, a Saturday.)" });
        model.Then(new JsonObject { ["content"] = "Which page?" });

        var lines = await agent.Say(typed, CancellationToken.None);

        Assert.Equal(AssistWording.DidNotFollowThat, Assert.Single(lines).Text);
        Assert.DoesNotContain(lines, line => line.Text.Contains("Unit 4, Day 20"));
        Assert.Contains("repeated the request back", File.ReadAllText(_trail));

        await agent.Say("unpublish it please, the day 20 one", CancellationToken.None);
        string sent = model.Asked[^1].ToJsonString();
        Assert.DoesNotContain("off the site for now", sent);
    }

    /// <summary>A second lap that begins with a tool result has no request to echo.</summary>
    [Fact]
    public async Task ALapAfterAReadIsNeverAnEchoOfIt()
    {
        var model = new WindowBindingContractTests.ScriptedModel();
        var tools = new WindowBindingContractTests.RecordingTools();
        var agent = new AssistAgent(model, tools,
            ContractLoader.LoadJson("assist-cases.json")["toolSchemas"]!["local"]!.DeepClone().AsArray(), "ICS3U", 1);
        model.Then(new JsonObject
        {
            ["tool_calls"] = new JsonArray(new JsonObject
            {
                ["id"] = "call-0",
                ["function"] = new JsonObject { ["name"] = "list_pages", ["arguments"] = """{"course":"ICS3U","section":1}""" },
            }),
        });
        // The answer happens to equal the tool's own text: not an echo of the TEACHER.
        model.Then(new JsonObject { ["content"] = "Done." });

        var lines = await agent.Say("what is in this section at the moment", CancellationToken.None);

        Assert.Equal("Done.", lines[^1].Text);
    }
}
