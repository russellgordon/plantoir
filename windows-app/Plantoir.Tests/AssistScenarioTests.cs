using System.Text.Json.Nodes;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

public class AssistScenarioTests
{
    private sealed class ScriptedModel : IChatModel
    {
        public Task<JsonObject?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation)
        {
            return Task.FromResult<JsonObject?>(null);
        }
    }

    private sealed class RecordingTools : IToolServer
    {
        public readonly List<string> Events;
        public string Result = "Done.";

        public RecordingTools(List<string> events)
        {
            Events = events;
        }

        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments,
                                               Action<string>? progress = null,
                                               CancellationToken cancellation = default)
        {
            if (name == "deploy_section")
            {
                Events.Add("runLauncherDirectly");
                return Task.FromResult(AssistToolAnswer.Same(AssistWording.Deployed("VVH2O", "1")));
            }
            else if (name == "unpublish_pages" || name == "publish_pages" || name == "publish_class_on")
            {
                Events.Add("write");
            }
            return Task.FromResult(AssistToolAnswer.Same(Result));
        }
    }

    public static IEnumerable<object[]> GetScenarioCases()
    {
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var cases = doc["scenarios"]!["cases"]!.AsArray();
        foreach (var c in cases)
        {
            if (c is not null)
            {
                yield return new object[] { c["name"]!.ToString(), c.ToJsonString() };
            }
        }
    }

    [Theory]
    [MemberData(nameof(GetScenarioCases))]
    public async Task AssistCases_Scenario_MatchesContract(string scenarioName, string caseJson)
    {
        Assert.NotEmpty(scenarioName);
        var c = JsonNode.Parse(caseJson)!.AsObject();
        var given = c["given"]?.AsObject();
        string when = c["when"]!.ToString();

        const string courseCode = "VVH2O";
        const int sectionNumber = 1;

        bool previewRunning = given?["previewRunning"]?.GetValue<bool>() ?? false;
        bool sectionWindowOpen = given?["sectionWindowOpen"]?.GetValue<bool>() ?? true;
        bool sectionBusy = given?["sectionBusy"]?.GetValue<bool>() ?? false;
        string? pending = given?["pending"]?.ToString();

        var events = new List<string>();
        var model = new ScriptedModel();
        var tools = new RecordingTools(events);

        var agent = new AssistAgent(model, tools, new JsonArray(), courseCode, sectionNumber)
        {
            PreviewIsShowing = () => previewRunning,
            SectionIsBusy = () => sectionBusy,
        };

        if (sectionWindowOpen)
        {
            agent.ShowPreviewInApp = () => events.Add("startPreview");
            agent.StartDeployInApp = () => events.Add("deploy");
            agent.StopPreviewInAppAsync = async () =>
            {
                events.Add("stopPreview.begins");
                await Task.Yield();
                events.Add("stopPreview.ends");
                previewRunning = false;
            };
            agent.StopPreviewInApp = () =>
            {
                events.Add("stopPreview.begins");
                events.Add("stopPreview.ends");
                previewRunning = false;
            };
        }

        List<AssistAgent.Line> resultLines = new();

        if (pending is not null)
        {
            agent.AskFirst("User prompt", pending, new JsonObject());
        }

        if (when == "approve")
        {
            resultLines = await agent.Approve(CancellationToken.None);
        }
        else if (when == "decline")
        {
            resultLines = await agent.Decline(CancellationToken.None);
        }
        else
        {
            var call = new JsonObject
            {
                ["id"] = "call-1",
                ["function"] = new JsonObject
                {
                    ["name"] = when,
                    ["arguments"] = "{}",
                },
            };
            var toolReply = await agent.RunTool(call, resultLines, CancellationToken.None);
            // The teacher's half: what the transcript actually shows.
            resultLines.Add(new AssistAgent.Line("assistant", toolReply.Summary));
        }

        // Assert events if specified
        if (c["expectEvents"] is JsonArray expectedEvents)
        {
            var expectedList = expectedEvents.Select(e => e!.ToString()).ToList();
            Assert.Equal(expectedList, events);
        }

        // Assert reply if specified
        if (c["expectReply"] is JsonNode expectReplyNode)
        {
            string expectReplyKey = expectReplyNode.ToString();
            string expectedText = ResolveWordingKey(expectReplyKey, courseCode, sectionNumber);
            Assert.Contains(resultLines, l => l.Text.Contains(expectedText));
        }

        // Assert transcript if specified
        if (c["expectTranscript"] is JsonArray expectTranscript)
        {
            var transcriptItems = expectTranscript.Select(t => t!.ToString()).ToList();
            foreach (string item in transcriptItems)
            {
                var parts = item.Split(":", 2, StringSplitOptions.TrimEntries);
                string role = parts[0];
                string wordingKey = parts[1];
                string expectedText = ResolveWordingKey(wordingKey, courseCode, sectionNumber);

                if (role == "teacher")
                {
                    if (when == "approve")
                    {
                        string expectedTeacher = pending == "deploy_section" ? AssistWording.DeployAccepted : AssistWording.PlanAccepted;
                        Assert.Equal(expectedText, expectedTeacher);
                    }
                    else if (when == "decline")
                    {
                        Assert.Equal(expectedText, AssistWording.Cancelled);
                    }
                }
                else if (role == "assistant")
                {
                    Assert.Contains(resultLines, l => l.Speaker == "assistant" && l.Text == expectedText);
                }
            }
        }
    }

    // ---- StartDeployInAppAsync: the assistant must say the REAL outcome ---
    //
    // WINDOWS-HANDOFF.md / TODO.md item: DeployForAsync used to resolve the
    // instant the click was dispatched, so RunTool always answered with the
    // unconditional AssistWording.Deployed — success or not. These wire the
    // production seam itself (StartDeployInAppAsync), not a stand-in for it,
    // the gap AssistScenarioTests.cs:80 left: that fixture only ever sets
    // the SYNC StartDeployInApp, so it never exercised this delegate at all.

    [Fact]
    public async Task DeploySection_SucceedsWhenAsyncSeamReportsSuccess()
    {
        var events = new List<string>();
        var agent = new AssistAgent(new ScriptedModel(), new RecordingTools(events), new JsonArray(), "VVH2O", 1)
        {
            SectionIsBusy = () => false,
            PreviewIsShowing = () => false,
            StartDeployInAppAsync = () => Task.FromResult<string?>(AssistWording.Deployed("VVH2O", "1")),
        };

        var call = new JsonObject
        {
            ["id"] = "call-1",
            ["function"] = new JsonObject { ["name"] = "deploy_section", ["arguments"] = "{}" },
        };
        var answer = await agent.RunTool(call, new List<AssistAgent.Line>(), CancellationToken.None);

        Assert.Equal(AssistWording.Deployed("VVH2O", "1"), answer.Summary);
    }

    [Fact]
    public async Task DeploySection_ReportsFailureWhenAsyncSeamReportsFailure()
    {
        var events = new List<string>();
        var agent = new AssistAgent(new ScriptedModel(), new RecordingTools(events), new JsonArray(), "VVH2O", 1)
        {
            SectionIsBusy = () => false,
            PreviewIsShowing = () => false,
            // The deploy actually ran and failed — the outcome the old,
            // unconditional wording could never produce.
            StartDeployInAppAsync = () => Task.FromResult<string?>(AssistWording.DeployDidNotFinish("VVH2O", "1")),
        };

        var call = new JsonObject
        {
            ["id"] = "call-1",
            ["function"] = new JsonObject { ["name"] = "deploy_section", ["arguments"] = "{}" },
        };
        var answer = await agent.RunTool(call, new List<AssistAgent.Line>(), CancellationToken.None);

        Assert.Equal(AssistWording.DeployDidNotFinish("VVH2O", "1"), answer.Summary);
        Assert.DoesNotContain("is deployed", answer.Summary);
    }

    [Fact]
    public async Task DeploySection_FallsBackToDidNotFinishWhenAsyncSeamReturnsNull()
    {
        // Null means "the deploy never actually ran" (refused, already
        // busy, an exception before it started) — the fallback must never
        // be the success wording, which is exactly the bug being closed.
        var events = new List<string>();
        var agent = new AssistAgent(new ScriptedModel(), new RecordingTools(events), new JsonArray(), "VVH2O", 1)
        {
            SectionIsBusy = () => false,
            PreviewIsShowing = () => false,
            StartDeployInAppAsync = () => Task.FromResult<string?>(null),
        };

        var call = new JsonObject
        {
            ["id"] = "call-1",
            ["function"] = new JsonObject { ["name"] = "deploy_section", ["arguments"] = "{}" },
        };
        var answer = await agent.RunTool(call, new List<AssistAgent.Line>(), CancellationToken.None);

        Assert.Equal(AssistWording.DeployDidNotFinish("VVH2O", "1"), answer.Summary);
    }

    private static string ResolveWordingKey(string key, string course, int section)
    {
        return key switch
        {
            "wording.deployed" => AssistWording.Deployed(course, section.ToString()),
            "wording.sectionIsBusy" => AssistWording.SectionIsBusy(course, section.ToString()),
            "wording.deployAccepted" => AssistWording.DeployAccepted,
            "wording.planAccepted" => AssistWording.PlanAccepted,
            "wording.cancelled" => AssistWording.Cancelled,
            "wording.deployWasCancelled" => AssistWording.DeployWasCancelled,
            "wording.planWasCancelled" => AssistWording.PlanWasCancelled,
            _ => key,
        };
    }
}
