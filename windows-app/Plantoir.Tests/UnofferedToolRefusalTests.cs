using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A model that answers from a script and records every request it was sent.
/// Shared by the bundle-5b tests; <c>AssistAgentTests</c> keeps its own.
/// </summary>
internal sealed class ScriptModel : IChatModel
{
    private readonly Queue<JsonObject?> _replies = new();
    public readonly List<JsonArray> Asked = new();

    public ScriptModel Calls(string tool, string argumentsJson = "{}")
    {
        _replies.Enqueue(new JsonObject
        {
            ["tool_calls"] = new JsonArray(new JsonObject
            {
                ["id"] = $"call-{_replies.Count}",
                ["function"] = new JsonObject { ["name"] = tool, ["arguments"] = argumentsJson },
            }),
        });
        return this;
    }

    public ScriptModel Says(string content)
    {
        _replies.Enqueue(new JsonObject { ["content"] = content });
        return this;
    }

    public Task<ModelReply?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation)
    {
        Asked.Add((JsonArray)messages.DeepClone());
        return Task.FromResult<ModelReply?>(_replies.Count > 0 ? _replies.Dequeue() : null);
    }
}

/// <summary>A tool server that records calls and answers each with a canned line.</summary>
internal sealed class CannedTools : IToolServer
{
    public readonly List<(string Name, JsonObject Arguments)> Calls = new();
    public Func<string, JsonObject, AssistToolAnswer> Answer =
        (name, _) => name.StartsWith("plan_", StringComparison.Ordinal)
            ? new AssistToolAnswer("This would change one page.", "This would change one page.", IsPlan: true)
            : AssistToolAnswer.Same("Done.");

    public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments,
                                           Action<string>? progress = null,
                                           CancellationToken cancellation = default)
    {
        Calls.Add((name, (JsonObject)arguments.DeepClone()));
        return Task.FromResult(Answer(name, arguments));
    }
}

/// <summary>
/// #350 / mac #327: a tool the model names that exists but was NOT on the list
/// it was shown is refused — nothing runs, no plan, no button, the turn is
/// wound back out of the model's conversation, and the trail says so.
/// </summary>
[Collection(SharedActivityState.Name)]
public class UnofferedToolRefusalTests : IDisposable
{
    private readonly string _trail = Path.Combine(Path.GetTempPath(), $"plantoir-unoffered-{Guid.NewGuid():N}.txt");

    public UnofferedToolRefusalTests() => ActivityTrail.SetCustomLogPathForTesting(_trail);

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trail); } catch { }
    }

    /// <summary>What the window shows the model: the narrowed list.</summary>
    private static JsonArray Offered(params string[] names) => new(
        names.Select(name => (JsonNode)new JsonObject
        {
            ["type"] = "function",
            ["function"] = new JsonObject { ["name"] = name, ["description"] = name },
        }).ToArray());

    private static readonly string[] Served =
    {
        "list_pages", "read_page", "publish_pages", "plan_publish_pages", "unpublish_pages",
        "re_date_classes", "plan_re_date_classes", "add_curriculum_mentions", "plan_curriculum_mentions",
    };

    [Theory]
    [InlineData("re_date_classes")]
    [InlineData("add_curriculum_mentions")]
    [InlineData("plan_publish_pages")]
    public void AToolTheModelWasNotOfferedIsRefusedAndNothingRuns(string tool)
    {
        var model = new ScriptModel().Calls(tool, "{\"course\":\"VVH2O\",\"section\":1}");
        var tools = new CannedTools();
        var agent = new AssistAgent(model, tools, Offered("list_pages", "publish_pages", "unpublish_pages"), "VVH2O", 1)
        {
            ServedTools = Served,
            ConfirmationMode = () => false,
        };

        var lines = agent.Say("move every class a week later", CancellationToken.None).GetAwaiter().GetResult();

        Assert.Single(model.Asked);                 // one request on the wire
        Assert.Empty(tools.Calls);                  // nothing ran, not even a plan
        Assert.False(agent.IsAwaitingApproval);     // and no button
        Assert.Equal(AssistWording.DidNotFollowThat, Assert.Single(lines).Text);
        Assert.Contains("assistant named " + tool.Replace('_', ' '), File.ReadAllText(_trail));
        Assert.DoesNotContain("move every class", File.ReadAllText(_trail).Split('\n')
            .Where(line => line.Contains("not offered")).Single());
    }

    [Fact]
    public void TheRefusedTurnIsWoundBackOutOfWhatTheModelReadsNext()
    {
        var model = new ScriptModel().Calls("re_date_classes").Says("Sure.");
        var agent = new AssistAgent(model, new CannedTools(), Offered("list_pages"), "VVH2O", 1)
        {
            ServedTools = Served,
        };

        agent.Say("move every class a week later", CancellationToken.None).GetAwaiter().GetResult();
        agent.Say("hello", CancellationToken.None).GetAwaiter().GetResult();

        string next = model.Asked[1].ToJsonString();
        Assert.DoesNotContain("move every class", next);
        Assert.DoesNotContain("re_date_classes", next);
    }

    [Fact]
    public void ANameThatExistsNowhereStillGoesBackToTheModel()
    {
        var model = new ScriptModel().Calls("delete_everything").Says("There is no such tool.");
        var tools = new CannedTools { Answer = (_, _) => AssistToolAnswer.Same("There is no tool by that name.") };
        var agent = new AssistAgent(model, tools, Offered("list_pages"), "VVH2O", 1) { ServedTools = Served };

        agent.Say("delete it", CancellationToken.None).GetAwaiter().GetResult();

        Assert.Equal("delete_everything", Assert.Single(tools.Calls).Name);
    }

    [Fact]
    public void AnOfferedToolStillRuns()
    {
        var model = new ScriptModel().Calls("list_pages").Says("Here they are.");
        var tools = new CannedTools();
        var agent = new AssistAgent(model, tools, Offered("list_pages"), "VVH2O", 1) { ServedTools = Served };

        agent.Say("what pages are there", CancellationToken.None).GetAwaiter().GetResult();

        Assert.Equal("list_pages", Assert.Single(tools.Calls).Name);
    }

    [Fact]
    public void EveryPlanToolIsExactlyOneWritesTwin()
    {
        var contract = ContractLoader.LoadJson("assist-cases.json")!["tools"]!["planTwins"]!.AsObject();
        foreach (var (write, twin) in AssistAgent.PlanTwins)
            if (contract[write] is { } named)
                Assert.Equal(named.ToString(), twin);
        Assert.Equal("plan_curriculum_mentions", AssistAgent.PlanTwins["add_curriculum_mentions"]);
        Assert.Equal(AssistAgent.PlanTwins.Count, AssistAgent.PlanTwins.Values.Distinct().Count());
    }
}
