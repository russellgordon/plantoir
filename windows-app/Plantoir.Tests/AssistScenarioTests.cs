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

        public Task<string> CallTool(string name, JsonObject arguments,
                                     Action<string>? progress = null,
                                     CancellationToken cancellation = default)
        {
            if (name == "deploy_section")
            {
                Events.Add("runLauncherDirectly");
                return Task.FromResult(AssistWording.Deployed("VVH2O", "1"));
            }
            else if (name == "unpublish_pages" || name == "publish_pages" || name == "publish_class_on")
            {
                Events.Add("write");
            }
            return Task.FromResult(Result);
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
            string toolReply = await agent.RunTool(call, resultLines, CancellationToken.None);
            resultLines.Add(new AssistAgent.Line("assistant", toolReply));
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
