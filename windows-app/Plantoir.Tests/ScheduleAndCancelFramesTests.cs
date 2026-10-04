using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #424: "schedule a deploy …" and "cancel the scheduled deploy" answered in
/// code, from <c>contracts/assist-cases.json → scheduleAndCancel</c> (AUTHORED
/// from Windows; the mac implements it from the mac issue) — and the settler
/// that ends a reply the engine is still writing after 30 seconds.
/// </summary>
[Collection(SharedActivityState.Name)]
public class ScheduleAndCancelFramesTests : IDisposable
{
    private readonly string _trail = Path.Combine(Path.GetTempPath(), "plantoir-schedule-" + Guid.NewGuid().ToString("N") + ".txt");

    public ScheduleAndCancelFramesTests() => ActivityTrail.SetCustomLogPathForTesting(_trail);

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trail); } catch { }
        GC.SuppressFinalize(this);
    }

    private static JsonObject Rows => ContractLoader.LoadJson("assist-cases.json")["scheduleAndCancel"]!.AsObject();

    private static AssistAgent Agent(WindowBindingContractTests.ScriptedModel model, WindowBindingContractTests.RecordingTools tools) =>
        new(model, tools, ContractLoader.LoadJson("assist-cases.json")["toolSchemas"]!["local"]!.DeepClone().AsArray(), "ICS3U", 1);

    [Fact]
    public void EveryAcceptedRowReachesItsToolWithItsWhen()
    {
        var accepted = Rows["accepted"]!.AsArray();
        Assert.True(accepted.Count >= 7, "scheduleAndCancel.accepted has lost rows");
        foreach (var row in accepted)
        {
            string input = row!["input"]!.ToString();
            var matched = AssistCardCommand.Matching(input);
            Assert.True(matched is not null, $"“{input}” matched nothing: {row["why"]}");
            Assert.Equal(row["expectTool"]!.ToString(), matched!.ToolName);
            if (row["expectWhen"] is JsonValue when)
                Assert.Equal(when.ToString(), matched.Arguments["when"]);
        }
    }

    [Fact]
    public void EveryRefusedRowMatchesNothingAndAsksNothing()
    {
        var refused = Rows["refused"]!.AsArray();
        Assert.True(refused.Count >= 11, "scheduleAndCancel.refused has lost rows");
        var wrongly = refused.Select(row => row!["input"]!.ToString())
            .Where(input => AssistCardCommand.Matching(input) is not null || AssistCardCommand.AsksWhenToSchedule(input))
            .ToList();
        Assert.True(wrongly.Count == 0, "answered in code, and the contract refuses: " + string.Join(" | ", wrongly));
    }

    /// <summary>A schedule phrasing with no time is NEVER a deploy now: asked, in code, and the model is never sent it.</summary>
    [Fact]
    public async Task ASchedulePhrasingWithNoTimeIsAskedAndNothingRuns()
    {
        foreach (var row in Rows["asksForTheTime"]!.AsArray())
        {
            string input = row!["input"]!.ToString();
            Assert.Null(AssistCardCommand.Matching(input));
            var model = new WindowBindingContractTests.ScriptedModel();
            var tools = new WindowBindingContractTests.RecordingTools();
            var agent = Agent(model, tools);
            var lines = await agent.Say(input, CancellationToken.None);
            Assert.Equal(AssistWording.ScheduleADeployNeedsATime, Assert.Single(lines).Text);
            Assert.Empty(model.Asked);
            Assert.Empty(tools.Calls);
            Assert.False(agent.IsAwaitingApproval, $"“{input}” put up a card");
        }
    }

    /// <summary>The question names a sentence that schedules when typed back.</summary>
    [Fact]
    public void TheQuestionsExampleIsASentenceThatSchedules() =>
        Assert.Equal("schedule_deploy", AssistCardCommand.Matching("deploy tomorrow at 6:30 am")?.ToolName);

    /// <summary>Through the agent: a schedule is held behind the button; a cancel runs; the model is never asked.</summary>
    [Fact]
    public async Task TheAcceptedRowsNeverReachTheModel()
    {
        foreach (var row in Rows["accepted"]!.AsArray())
        {
            var model = new WindowBindingContractTests.ScriptedModel();
            var tools = new WindowBindingContractTests.RecordingTools();
            var agent = Agent(model, tools);
            await agent.Say(row!["input"]!.ToString(), CancellationToken.None);
            Assert.Empty(model.Asked);
            if (row["expectTool"]!.ToString() == "schedule_deploy")
            {
                Assert.True(agent.IsAwaitingApproval);
                Assert.Equal("schedule_deploy", agent.PendingTool);
                Assert.DoesNotContain(tools.Calls, call => call.Name == "deploy_section");
            }
            else
            {
                Assert.Contains(tools.Calls, call => call.Name == "cancel_scheduled_deploy");
            }
        }
    }

    /// <summary>Fix round 2, settler S1: a sentence with no later-time word behaves as before.</summary>
    [Theory]
    [InlineData("Deploy EXC2O section 1 at 6:30 tomorrow morning, before school starts.", true)]
    [InlineData("Put it online tomorrow", true)]
    [InlineData("deploy it on Friday", true)]
    [InlineData("send it out later", true)]
    [InlineData("deploy at 7 pm", true)]
    [InlineData("Push EXC2O section 1 live now - the site, not just the preview.", false)]
    [InlineData("Put it online", false)]
    [InlineData("Deploy this section now", false)]
    [InlineData("deploy the next section", false)]
    public void TheLaterTimeWordsAreShortAndExact(string typed, bool later) =>
        Assert.Equal(later, AssistAgent.SaysALaterTime(typed));

    /// <summary>Fix round 2, settler S2: a teacher who SAID "unit" keeps the model's unit "next".</summary>
    [Fact]
    public void ANewUnitTheTeacherAskedForIsKept()
    {
        var call = new JsonObject
        {
            ["function"] = new JsonObject
            {
                ["name"] = "add_next_class",
                ["arguments"] = """{"course":"ICS3U","section":1,"unit":"next","days":0}""",
            },
        };
        string Kept(string typed) => AssistAgent.WithoutAnUnaskedNewUnit(call, typed)["function"]!["arguments"]!.ToString();
        Assert.Contains("\"unit\":\"next\"", Kept("start the next unit please"));
        Assert.DoesNotContain("unit", Kept("Add the next class"));
        Assert.Contains("\"days\":0", Kept("Add the next class"));
    }

    /// <summary>
    /// #424 item 2: every request lets the engine write for 30 seconds at most,
    /// read by llama-server as t_max_predict_ms; the cap of 512 is unchanged.
    /// </summary>
    [Fact]
    public void EveryRequestCarriesTheWritingTimeLimit()
    {
        var body = LocalModel.Request(new JsonArray(), new JsonArray(), AssistModelTier.Small);
        Assert.Equal(30_000, body["t_max_predict_ms"]!.GetValue<int>());
        Assert.Equal(512, body["max_tokens"]!.GetValue<int>());
        // The larger tier was not measured: it keeps the cap alone (ruling 4).
        var larger = LocalModel.Request(new JsonArray(), new JsonArray(), AssistModelTier.Large);
        Assert.Null(larger["t_max_predict_ms"]);
        Assert.Equal(512, larger["max_tokens"]!.GetValue<int>());
    }
}
