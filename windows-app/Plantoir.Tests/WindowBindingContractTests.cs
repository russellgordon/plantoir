using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/assist-cases.json</c> → <c>windowBinding</c>: given an
/// assistant window (one course, one section) and the arguments the MODEL
/// wrote on its tool call, what actually runs — or which refusal the teacher
/// reads instead (#180, the mac's half in #208).
/// </summary>
/// <remarks>
/// <para><b>Every case reaches the agent through the model</b>, never through a
/// card phrasing. A card is answered in code and never meets the binder, so a
/// test driven by one passes having checked nothing — six of #159's tests did
/// exactly that. So each case asserts, in the test, that its sentence matches
/// no card and that the scripted reply was actually consumed.</para>
///
/// <para><b>A plain answer stands behind every scripted call.</b> A refused
/// READ that handed back to the model would otherwise meet a stub whose queue
/// is empty — and if the guard ever regressed into a loop, a hung suite is
/// worse than a red one (#208 §5).</para>
/// </remarks>
[Collection(SharedActivityState.Name)]
public class WindowBindingContractTests : IDisposable
{
    private const string Sentence = "sort that out for me in the way we discussed";

    private readonly string _trail = Path.Combine(Path.GetTempPath(), "plantoir-window-binding-" + Guid.NewGuid().ToString("N") + ".txt");

    public WindowBindingContractTests() => ActivityTrail.SetCustomLogPathForTesting(_trail);

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trail); } catch { }
        GC.SuppressFinalize(this);
    }

    private static JsonObject Binding() => ContractLoader.LoadJson("assist-cases.json")["windowBinding"]!.AsObject();

    public static IEnumerable<object[]> Cases()
    {
        int index = 0;
        foreach (var item in Binding()["cases"]!.AsArray())
            yield return new object[] { index++, item!["tool"]!.ToString() };
    }

    [Fact]
    public void TheContractStillHasItsEightCases() =>
        Assert.True(Binding()["cases"]!.AsArray().Count >= 8, "windowBinding has lost cases");

    [Theory]
    [MemberData(nameof(Cases))]
    public async Task ACallTheModelMadeRunsAsThisWindowOrIsRefused(int index, string tool)
    {
        var binding = Binding();
        var item = binding["cases"]!.AsArray()[index]!.AsObject();
        var folder = binding["coursesInTheFolder"]!.AsArray().Select(c => c!.ToString()).ToList();
        string window = folder[0];
        const int section = 1;

        Assert.Null(AssistCardCommand.Matching(Sentence));
        var model = new ScriptedModel();
        model.Then(Calling(tool, item["said"]!.ToJsonString()));
        model.Then(new JsonObject { ["content"] = "All done." });
        var tools = new RecordingTools();
        var agent = new AssistAgent(model, tools, LocalSchemas(), window, section)
        {
            CoursesInTheFolder = () => folder,
            ConfirmationMode = () => true,
        };

        var lines = await agent.Say(Sentence, CancellationToken.None);
        Assert.True(model.Asked.Count >= 1, "the scripted call was never asked for, so the binder never ran");

        if (item["refusedWith"]?.ToString() is { } key)
        {
            Assert.Empty(tools.Calls);
            Assert.False(agent.IsAwaitingApproval, "a refused call put up a card");
            string said = item["said"]!["course"]!.ToString();
            string other = item["namesTheCourseAs"]?.ToString()
                ?? folder.FirstOrDefault(c => c.Equals(said.Trim(), StringComparison.OrdinalIgnoreCase))
                ?? said.Trim();
            string expected = Wording(key).Replace("{course}", window).Replace("{otherCourse}", other);
            Assert.Contains(lines, line => line.Text == expected);
            // One question only: the refusal ends the turn rather than going
            // back to the model with it.
            Assert.Single(model.Asked);
            // The trail keeps the MODEL's spelling, never the teacher's sentence.
            string trail = File.ReadAllText(_trail);
            Assert.Contains($"named {said.Trim()} for {tool.Replace('_', ' ')}", trail);
            Assert.DoesNotContain(Sentence, trail.Replace(ActivityTrail.PromptPrefix + Sentence, ""));
            return;
        }

        // It RAN: the first thing to reach the tools — the plan twin, or the
        // tool itself — carries the window's values.
        var first = Assert.Single(tools.Calls.Take(1));
        var runs = item["runs"]!.AsObject();
        foreach (var (name, value) in runs)
            Assert.True(JsonNode.DeepEquals(value, first.Arguments[name]),
                $"{item["why"]}: {name} ran as {first.Arguments[name]?.ToJsonString()}, the contract says {value!.ToJsonString()}");
        foreach (var (name, _) in first.Arguments)
            Assert.True(runs.ContainsKey(name) || name == "preview",
                $"{tool} ran with {name}, which the contract's `runs` does not carry");
    }

    /// <summary>
    /// The refused turn is taken back out of what the model is sent next, so
    /// its next answer is not made in front of the request it was refused.
    /// </summary>
    [Fact]
    public async Task ARefusedTurnIsNotInFrontOfTheModelNextTime()
    {
        var model = new ScriptedModel();
        model.Then(Calling("list_pages", """{"course":"MCV4U","section":1}"""));
        model.Then(new JsonObject { ["content"] = "Here they are." });
        var agent = new AssistAgent(model, new RecordingTools(), LocalSchemas(), "ICS3U", 1)
        {
            CoursesInTheFolder = () => new[] { "ICS3U", "MCV4U" },
        };

        await agent.Say(Sentence, CancellationToken.None);
        await agent.Say("and the other thing", CancellationToken.None);

        string sent = model.Asked[^1].ToJsonString();
        Assert.DoesNotContain("MCV4U", sent);
        Assert.DoesNotContain(Sentence, sent);
        Assert.Contains("and the other thing", sent);
    }

    // ---- Fakes ---------------------------------------------------------------

    private static string Wording(string key) =>
        ContractLoader.LoadJson("assist-wording.json")["wording"]![key]!.ToString();

    private static JsonArray LocalSchemas() =>
        ContractLoader.LoadJson("assist-cases.json")["toolSchemas"]!["local"]!.DeepClone().AsArray();

    private static JsonObject Calling(string tool, string argumentsJson) => new()
    {
        ["tool_calls"] = new JsonArray(new JsonObject
        {
            ["id"] = "call-0",
            ["function"] = new JsonObject { ["name"] = tool, ["arguments"] = argumentsJson },
        }),
    };

    internal sealed class ScriptedModel : IChatModel
    {
        private readonly Queue<JsonObject?> _replies = new();
        public readonly List<JsonArray> Asked = new();

        public void Then(JsonObject? reply) => _replies.Enqueue(reply);

        public Task<JsonObject?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation)
        {
            Asked.Add((JsonArray)messages.DeepClone());
            return Task.FromResult(_replies.Count > 0 ? _replies.Dequeue() : null);
        }
    }

    internal sealed class RecordingTools : IToolServer
    {
        public readonly List<(string Name, JsonObject Arguments)> Calls = new();

        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments,
                                               Action<string>? progress = null,
                                               CancellationToken cancellation = default)
        {
            Calls.Add((name, (JsonObject)arguments.DeepClone()));
            return Task.FromResult(name.StartsWith("plan_", StringComparison.Ordinal)
                ? new AssistToolAnswer("This would do one thing.", "This would do one thing.", IsPlan: true)
                : AssistToolAnswer.Same("Done."));
        }
    }
}
