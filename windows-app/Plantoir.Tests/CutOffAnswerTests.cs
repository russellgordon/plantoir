using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #196 (the mac's #166): a reply the engine stopped part way, or one whose
/// arguments cannot be read, runs NOTHING, says <c>wording.answerWasCutOff</c>,
/// records <c>assistant answer was cut off</c>, and takes the whole turn back
/// out of what the model is sent next.
/// </summary>
/// <remarks>
/// Every sentence here goes THROUGH the model — asserted, because a card
/// phrasing is answered in code and would never meet the gate.
/// </remarks>
[Collection(SharedActivityState.Name)]
public class CutOffAnswerTests : IDisposable
{
    private const string Request = "put up the things I mentioned for the class after this one";

    private readonly string _trail = Path.Combine(Path.GetTempPath(), "plantoir-cutoff-" + Guid.NewGuid().ToString("N") + ".txt");
    private readonly WindowBindingContractTests.ScriptedModel _model = new();
    private readonly WindowBindingContractTests.RecordingTools _tools = new();
    private readonly AssistAgent _agent;

    public CutOffAnswerTests()
    {
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        _agent = new AssistAgent(_model, _tools,
            ContractLoader.LoadJson("assist-cases.json")["toolSchemas"]!["local"]!.DeepClone().AsArray(), "ICS3U", 1)
        {
            ConfirmationMode = () => false,
            CoursesInTheFolder = () => new[] { "ICS3U" },
        };
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trail); } catch { }
        GC.SuppressFinalize(this);
    }

    private static JsonObject Calling(string tool, string arguments) => new()
    {
        ["tool_calls"] = new JsonArray(new JsonObject
        {
            ["id"] = "call-0",
            ["function"] = new JsonObject { ["name"] = tool, ["arguments"] = arguments },
        }),
    };

    private async Task<List<AssistAgent.Line>> Say(string text = Request)
    {
        Assert.Null(AssistCardCommand.Matching(text));
        int waiting = _model.Waiting;
        var lines = await _agent.Say(text, CancellationToken.None);
        Assert.True(_model.Waiting < waiting, "the scripted reply was never handed out");
        return lines;
    }

    private string Trail() => File.Exists(_trail) ? File.ReadAllText(_trail) : "";

    /// <summary>The measured 28-token case: stopped, and the arguments PARSE.</summary>
    [Fact]
    public async Task AStoppedReplyWhoseArgumentsParseRunsNothing()
    {
        _model.Then(Calling("deploy_section", """{"course": "ICS3U", "section": 1}"""), "length");

        var lines = await Say();

        Assert.Empty(_tools.Calls);
        Assert.False(_agent.IsAwaitingApproval, "a stopped reply put up a card");
        Assert.Equal(AssistWording.AnswerWasCutOff, Assert.Single(lines).Text);
        Assert.Contains("cut off part way through deploy section — nothing was run from it", Trail());
    }

    /// <summary>
    /// Cut before the tool name was written: no tool call, and a raw fragment
    /// in the content that must not reach the teacher.
    /// </summary>
    [Fact]
    public async Task AReplyCutBeforeItNamedAToolShowsNoFragment()
    {
        _model.Then(new JsonObject { ["content"] = "<tool_call>\n{\n\"name\": \"publi" }, "length");

        var lines = await Say();

        var line = Assert.Single(lines);
        Assert.Equal(AssistWording.AnswerWasCutOff, line.Text);
        Assert.DoesNotContain(lines, l => l.Text.Contains("tool_call"));
        Assert.Contains("cut off part way — nothing was run from it", Trail());
    }

    /// <summary>A call to a tool with no arguments at all would run on any parse check.</summary>
    [Fact]
    public async Task AStoppedUndoRunsNothing()
    {
        _model.Then(Calling("undo_last_change", ""), "length");
        await Say();
        Assert.Empty(_tools.Calls);
    }

    [Fact]
    public async Task AFinishedReplyWithUnreadableArgumentsRunsNothingAndSaysWhichKind()
    {
        _model.Then(Calling("publish_pages", """{"course": "ICS3U", "pages": "Unit 1, Day"""), "tool_calls");

        var lines = await Say();

        Assert.Empty(_tools.Calls);
        Assert.Equal(AssistWording.AnswerWasCutOff, Assert.Single(lines).Text);
        Assert.Contains("finished answering but what it wrote for publish pages could not be read", Trail());
    }

    /// <summary>The control: a WHOLE answer still runs.</summary>
    [Fact]
    public async Task AWholeAnswerStillRuns()
    {
        _model.Then(Calling("publish_pages", """{"course":"ICS3U","section":1,"pages":"Unit 1, Day 1"}"""), "tool_calls");
        await Say();
        Assert.Equal("publish_pages", Assert.Single(_tools.Calls).Name);
    }

    /// <summary>
    /// The retry the sentence asks for is sent WITHOUT the request that ran
    /// away — or the teacher meets the same wall until they close the window.
    /// </summary>
    [Fact]
    public async Task TheTurnIsTakenBackOutOfWhatTheModelIsSentNext()
    {
        _model.Then(Calling("publish_pages", """{"pages": "Unit 1, Day 1; Unit 1, Day 2; Unit 1, Da"""), "length");
        _model.Then(new JsonObject { ["content"] = "Which class?" });

        await Say();
        await Say("just the first one, please");

        string sent = _model.Asked[^1].ToJsonString();
        Assert.DoesNotContain("the things I mentioned", sent);
        Assert.DoesNotContain("Unit 1, Day 2", sent);
        Assert.Contains("just the first one", sent);
    }

    /// <summary>A second lap cut off after a READ ran takes the read back out too.</summary>
    [Fact]
    public async Task ASecondLapCutOffTakesTheReadOutWithIt()
    {
        _model.Then(Calling("list_pages", """{"course":"ICS3U","section":1}"""), "tool_calls");
        _model.Then(Calling("publish_pages", """{"pages": "Unit"""), "length");
        _model.Then(new JsonObject { ["content"] = "Sure." });

        var lines = await Say();
        Assert.Equal("list_pages", Assert.Single(_tools.Calls).Name);
        Assert.Equal(AssistWording.AnswerWasCutOff, lines[^1].Text);

        await Say("hello again");
        string sent = _model.Asked[^1].ToJsonString();
        Assert.DoesNotContain("list_pages", sent);
        Assert.DoesNotContain("the things I mentioned", sent);
    }

    /// <summary>An ENGINE failure is not wound back: the context is worth keeping.</summary>
    [Fact]
    public async Task AnEngineThatDidNotAnswerKeepsTheConversation()
    {
        _model.Then(null);
        _model.Then(new JsonObject { ["content"] = "Here." });

        await Say();
        await Say("try that again");

        Assert.Contains("the things I mentioned", _model.Asked[^1].ToJsonString());
    }

    // ---- #262: a finished reply that wrote NOTHING ---------------------------

    /// <summary>An empty publish has nothing to act on: refused, with its own sentence.</summary>
    [Theory]
    [InlineData("")]
    [InlineData("  ")]
    [InlineData("{}")]
    public async Task AnEmptyCallToAWriteThatNeedsMoreRunsNothing(string arguments)
    {
        _model.Then(Calling("publish_pages", arguments), "tool_calls");

        var lines = await Say();

        Assert.Empty(_tools.Calls);
        Assert.Equal(AssistWording.AnswerLeftOutWhatItWasFor, Assert.Single(lines).Text);
        Assert.Contains("wrote nothing for publish pages — nothing was run from it", Trail());
    }

    /// <summary>
    /// An empty call to a tool the window supplies in full RUNS — and the
    /// window's course and section are what it runs with.
    /// </summary>
    [Fact]
    public async Task AnEmptyCallTheWindowSuppliesRunsAsThisWindow()
    {
        _model.Then(Calling("check_section", ""), "tool_calls");
        _model.Then(new JsonObject { ["content"] = "All visible." });

        await Say();

        var call = Assert.Single(_tools.Calls);
        Assert.Equal("check_section", call.Name);
        Assert.Equal("ICS3U", call.Arguments["course"]!.ToString());
        Assert.Equal(1, call.Arguments["section"]!.GetValue<int>());
    }

    /// <summary>
    /// An empty add_next_class RUNS, as on the mac: its unit and days only
    /// extend a write with a default (fix round, ruling 2).
    /// </summary>
    [Fact]
    public async Task AnEmptyAddNextClassRunsAsOnTheMac()
    {
        var schemas = new JsonArray(new JsonObject
        {
            ["type"] = "function",
            ["function"] = new JsonObject
            {
                ["name"] = "add_next_class",
                ["parameters"] = new JsonObject
                {
                    ["properties"] = new JsonObject
                    {
                        ["course"] = new JsonObject(), ["section"] = new JsonObject(),
                        ["unit"] = new JsonObject(), ["days"] = new JsonObject(),
                    },
                    ["required"] = new JsonArray("course", "section"),
                },
            },
        });
        var model = new WindowBindingContractTests.ScriptedModel();
        model.Then(Calling("add_next_class", "{}"), "tool_calls");
        var tools = new WindowBindingContractTests.RecordingTools();
        var agent = new AssistAgent(model, tools, schemas, "ICS3U", 1) { ConfirmationMode = () => false };

        await agent.Say(Request, CancellationToken.None);

        Assert.Equal("add_next_class", Assert.Single(tools.Calls).Name);
    }

    [Fact]
    public void TheEngineSaysWhyItStoppedAndThatReachesTheAgent()
    {
        var stopped = LocalModel.ReadReply(
            """{"choices":[{"finish_reason":"length","message":{"role":"assistant","content":"<tool_call>"}}]}""");
        Assert.NotNull(stopped);
        Assert.True(stopped!.WasCutOff);

        var finished = LocalModel.ReadReply(
            """{"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","content":""}}]}""");
        Assert.False(finished!.WasCutOff);
    }
}
