using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The agent's half of #193, #260, #281 and #288: what is answered in code
/// stays in the TRANSCRIPT, and what is scheduled is settled once.
/// </summary>
/// <remarks>
/// The damaging direction these exist for: appending the teacher's "deploy at
/// 6:30" or the question about it to the model's conversation "for context"
/// passes every wording test — and the model then acts on "6:30" a turn later,
/// measured as an immediate deploy_section 10 trials of 10.
/// </remarks>
[Collection(SharedActivityState.Name)]
public class TimeAskedInCodeTests : IDisposable
{
    private readonly string _trail = Path.Combine(Path.GetTempPath(), "plantoir-time-" + Guid.NewGuid().ToString("N") + ".txt");
    private readonly WindowBindingContractTests.ScriptedModel _model = new();
    private readonly WindowBindingContractTests.RecordingTools _tools = new();
    private readonly AssistAgent _agent;

    public TimeAskedInCodeTests()
    {
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        _agent = new AssistAgent(_model, _tools,
            ContractLoader.LoadJson("assist-cases.json")["toolSchemas"]!["local"]!.DeepClone().AsArray(), "ICS3U", 1)
        {
            Today = () => new DateOnly(2026, 9, 19),
            Now = () => new DateTime(2026, 9, 19, 9, 0, 0),
            TimeZone = TimeZoneInfo.Utc,
        };
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trail); } catch { }
        GC.SuppressFinalize(this);
    }

    [Theory]
    [InlineData("deploy at 6:30")]
    [InlineData("deploy at 6.30 pm")]
    public async Task ATimeAnsweredInCodeNeverReachesTheModelThisTurnOrTheNext(string said)
    {
        var lines = await _agent.Say(said, CancellationToken.None);
        string reply = Assert.Single(lines).Text;
        Assert.Contains("Nothing is set yet", reply);
        Assert.Empty(_model.Asked);
        Assert.False(_agent.IsAwaitingApproval);

        _model.Then(new JsonObject { ["content"] = "Hello." });
        await _agent.Say("what can you help me with today", CancellationToken.None);

        string sent = Assert.Single(_model.Asked).ToJsonString();
        Assert.DoesNotContain("6:30", sent);
        Assert.DoesNotContain("6.30", sent);
        Assert.DoesNotContain("Nothing is set yet", sent);
        // The trail line carries NO clock: the clock is something the teacher wrote.
        string trail = File.ReadAllText(_trail);
        Assert.Contains("matched in code, not sent to the model", trail);
        Assert.DoesNotContain("6:30 ", trail.Replace("asked: " + said, ""));
    }

    /// <summary>
    /// The card settles the moment ONCE; the card, the trail line and the act
    /// carry the same one — and the question is the SCHEDULED one (#260).
    /// </summary>
    [Fact]
    public async Task TheCardsMomentIsSettledOnceAndAskedAboutAsAMoment()
    {
        var lines = await _agent.Say("deploy at 6:30 am", CancellationToken.None);

        Assert.Empty(_model.Asked);
        Assert.Equal(AssistWording.ScheduleQuestion, lines[^1].Text);
        Assert.Equal("schedule_deploy", _agent.PendingTool);
        Assert.Contains("ran schedule_deploy for 2026-09-20 06:30", File.ReadAllText(_trail));

        await _agent.Approve(CancellationToken.None);
        var act = Assert.Single(_tools.Calls);
        Assert.Equal("2026-09-20 06:30", act.Arguments["when"]!.ToString());
    }

    /// <summary>The immediate card still asks the immediate question.</summary>
    [Fact]
    public async Task TheImmediateCardStillAsksTheImmediateQuestion()
    {
        var lines = await _agent.Say("deploy this section now", CancellationToken.None);
        Assert.Equal(AssistWording.DeployQuestion, lines[^1].Text);
        Assert.Equal(AssistWording.DeployApproval, lines[^2].Text);
    }

    /// <summary>
    /// The trap #193 named in the server: <c>ReadTheMoment</c> reads a bare
    /// "06:30" as TODAY at 06:30, silently. The server refuses it loudly, as
    /// the mac's <c>--mcp-stdio</c> does; the app's own calls arrive settled.
    /// </summary>
    [Fact]
    public void TheServerRefusesABareTimeRatherThanReadingItAsToday()
    {
        string folder = Directory.CreateTempSubdirectory("plantoir-bare-time").FullName;
        try
        {
            RelativeDayFreshnessTests.ACourseThatHasDeployedBefore(folder);
            var tools = new Plantoir.Mcp.PlantoirTools(new AssistWorkspace(folder, new FakeLauncher()));
            string planned = tools.PlanScheduledDeploy("ICS3U", 1, "23:59").Detail();
            Assert.Contains("isn't a time I can read", planned);
            Assert.DoesNotContain(DateTime.Now.ToString("dddd d MMMM"), planned);
        }
        finally
        {
            try { Directory.Delete(folder, recursive: true); } catch { }
        }
    }

    /// <summary>A bare time the MODEL wrote is the same trap, and is settled the same way.</summary>
    [Fact]
    public async Task ABareTimeTheModelWroteIsSettledToo()
    {
        _model.Then(new JsonObject
        {
            ["tool_calls"] = new JsonArray(new JsonObject
            {
                ["id"] = "call-0",
                ["function"] = new JsonObject
                {
                    ["name"] = "schedule_deploy",
                    ["arguments"] = """{"course":"ICS3U","section":1,"when":"06:30"}""",
                },
            }),
        });

        await _agent.Say("put it out early tomorrow before first period", CancellationToken.None);
        await _agent.Approve(CancellationToken.None);

        Assert.Equal("2026-09-20 06:30", Assert.Single(_tools.Calls).Arguments["when"]!.ToString());
    }
}
