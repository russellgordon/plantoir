using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// #790 items 2 and 3: <c>app-rules.json</c> → <c>outsideAgents.greetingUnitPlansCases</c>
/// walked through BOTH Revise doors' <see cref="ClaudeCodeLauncher.Prepare"/>
/// and <see cref="CodexLauncher.Prepare"/>, each case on its own disk and its
/// own <c>today</c>: the greeting's last sentence, and what the "assistant
/// opened" line gains. Nothing here retypes a sentence; the contract's are
/// compared. The mac's twin is <c>UnitPlansTests.testEveryGreetingCaseHolds</c>.
/// </summary>
/// <remarks>
/// <b>Not wired yet</b> (790a): the sidebar's Revise doors still pass no
/// plans, so a teacher's greeting is unchanged until the Planning tab the
/// sentence names lands (790b). These tests prove the functions that call
/// site will use.
/// </remarks>
public sealed class UnitPlansGreetingTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-unit-greeting-" + Guid.NewGuid().ToString("N"));
    private readonly ITestOutputHelper _output;

    public UnitPlansGreetingTests(ITestOutputHelper output)
    {
        _output = output;
        Directory.CreateDirectory(_root);
    }

    public void Dispose() => ReferenceFixtures.Remove(_root);

    private static JsonNode OutsideAgents() => ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!;

    public static IEnumerable<object[]> CaseNames() =>
        OutsideAgents()["greetingUnitPlansCases"]!["cases"]!.AsArray().Select(c => new object[] { c!["name"]!.ToString() });

    private static string TrailLineOf(string agent, string course) =>
        OutsideAgents()["agents"]!.AsArray().Single(a => a!["key"]!.ToString() == agent)!["trailLine"]!.ToString()
            .Replace("{course}", course);

    private const string Server = @"C:\Program Files\Plantoir\plantoir-mcp.exe";
    private const string Config = @"C:\Users\teacher\AppData\Local\Plantoir\assist\mcp-SNC2D.json";

    [Fact]
    public void ThereAreAtLeastTheEighteenCases() => Assert.True(CaseNames().Count() >= 18);

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void TheUnitPlanSentenceFollowsTheContract(string name)
    {
        var testCase = OutsideAgents()["greetingUnitPlansCases"]!["cases"]!.AsArray().Single(c => c!["name"]!.ToString() == name)!;
        string code = testCase["course"]!.ToString();
        string course = Path.Combine(_root, code);
        Directory.CreateDirectory(course);
        if (testCase["planningFolder"]!.GetValue<bool>())
        {
            string planning = UnitPlans.PlanningFolder(course);
            Directory.CreateDirectory(planning);
            foreach (var plan in testCase["plans"]!.AsArray())
            {
                string unit = Path.Combine(planning, plan!["folder"]!.ToString());
                Directory.CreateDirectory(unit);
                File.WriteAllText(Path.Combine(unit, UnitPlans.PlanFileName), plan["file"]!.ToString(), new UTF8Encoding(false));
            }
        }
        var today = DateOnly.ParseExact(testCase["today"]!.ToString(), "yyyy-MM-dd", CultureInfo.InvariantCulture);
        var reading = UnitPlans.ToMention(course, testCase["referenceCourse"]!.GetValue<bool>(), today);
        string? sentence = testCase["expect"]!["sentence"]?.ToString();
        string trail = testCase["expect"]!["trail"]!.ToString();

        // The greeting with nothing about unit planning, which every case starts with.
        string plain = ClaudeCodeLauncher.Greeting(code, code);
        string expected = sentence is null ? plain : plain + " " + sentence;

        var claude = ClaudeCodeLauncher.Prepare(Config, code, code, reading, openingMessage: null);
        Assert.Equal(expected, claude.Arguments[^1]);
        Assert.Equal(TrailLineOf("claude", code) + trail, claude.TrailText);

        var codex = CodexLauncher.Prepare(Server, _root, code, code, reading, openingMessage: null);
        Assert.Equal(expected, codex.Arguments[^1]);
        Assert.Equal(TrailLineOf("codex", code) + trail, codex.TrailText);
    }

    /// <summary>The sentence comes last, after How I Teach and the plan-first sentence (<c>greetingUnitPlans.where</c>).</summary>
    [Fact]
    public void TheSentenceIsTheLastOne()
    {
        var reading = new UnitPlans.Reading(Array.Empty<UnitPlans.Plan>(), 0);
        string greeting = ClaudeCodeLauncher.Greeting("SNC2D", "Grade 10 Science", reading);
        int howITeach = greeting.IndexOf(ClaudeCodeLauncher.HowITeachSentence, StringComparison.Ordinal);
        int agree = greeting.IndexOf("wait for me to agree.", StringComparison.Ordinal);
        int unit = greeting.IndexOf(UnitPlans.NoneSentence, StringComparison.Ordinal);
        Assert.True(howITeach >= 0 && agree > howITeach && unit > agree, greeting);
        Assert.EndsWith(" " + UnitPlans.NoneSentence, greeting);
    }

    /// <summary>
    /// Fix with's message (and Plan a Unit's) REPLACES the greeting: neither
    /// the sentence nor the trail clause rides along (<c>greetingUnitPlans.where</c>,
    /// Russell's ruling 4, 2026-11-01).
    /// </summary>
    [Fact]
    public void AnOpeningMessageGainsNeitherTheSentenceNorTheClause()
    {
        var reading = new UnitPlans.Reading(new[] { new UnitPlans.Plan("unit-1", "Unit 1", "Matter", null, null, Array.Empty<string>()) }, 2);
        const string message = "I'm a teacher working on SNC2D in Plantoir. Fix this.";

        var claude = ClaudeCodeLauncher.Prepare(Config, "SNC2D", "Science", reading, message);
        Assert.Equal(message, claude.Arguments[^1]);
        Assert.Equal(TrailLineOf("claude", "SNC2D"), claude.TrailText);

        var codex = CodexLauncher.Prepare(Server, _root, "SNC2D", "Science", reading, message);
        Assert.Equal(message, codex.Arguments[^1]);
        Assert.Equal(TrailLineOf("codex", "SNC2D"), codex.TrailText);
    }

    /// <summary>No reading at all (the call site of 790a, and a reference course) is today's greeting exactly.</summary>
    [Fact]
    public void NoReadingIsTheGreetingAsItWas()
    {
        var claude = ClaudeCodeLauncher.Prepare(Config, "SNC2D", "Science", unitPlans: null, openingMessage: null);
        Assert.Equal(ClaudeCodeLauncher.Greeting("SNC2D", "Science"), claude.Arguments[^1]);
        Assert.EndsWith("wait for me to agree.", claude.Arguments[^1]);
        Assert.Equal(TrailLineOf("claude", "SNC2D"), claude.TrailText);
    }

    /// <summary>The names in the sentence and the trail never carry a line break, a tab or a double quote.</summary>
    [Fact]
    public void ANameIsOneLineWithNoDoubleQuote()
    {
        var plan = UnitPlans.PlanFrom("unit-1", "{\"unit\": \"Unit\\r\\n1\", \"title\": \"The \\\"Big\\\"\\tBang\"}")!;
        string greeting = ClaudeCodeLauncher.Greeting("SNC2D", "", new UnitPlans.Reading(new[] { plan }, 0));
        Assert.DoesNotContain("\n", greeting);
        Assert.DoesNotContain("\r", greeting);
        Assert.DoesNotContain("\t", greeting);
        Assert.DoesNotContain("\"", greeting);
        Assert.Contains("Unit 1: The 'Big' Bang", greeting);
    }

    /// <summary>
    /// Plan review L4: the bound is cmd's 8,191 UTF-16 units, and a name is cut
    /// in TEXT ELEMENTS, so the worst case is six names of 60 elements that are
    /// each a ZWJ family emoji (11 UTF-16 units), "and N more", the longest
    /// course name the greeting keeps, the How I Teach sentence, and a shim in
    /// a 240-character folder (the doc's measured worst) for both doors, with a
    /// 240-character working folder for Codex's argv.
    /// </summary>
    [Fact]
    public void TheWorstSentenceStillFitsBothDoorsCommandLines()
    {
        const string family = "\U0001F468\u200D\U0001F469\u200D\U0001F467\u200D\U0001F466";
        Assert.Equal(11, family.Length);
        string longName = string.Concat(Enumerable.Repeat(family, 70));
        var plans = Enumerable.Range(1, 9)
            .Select(i => new UnitPlans.Plan($"unit-{i}", "", longName, null, null, Array.Empty<string>()))
            .ToList();
        string courseName = string.Concat(Enumerable.Repeat(family, 90));
        string shimFolder = @"C:\" + new string('n', 240 - 3);
        string folder = @"C:\" + new string('w', 240 - 3);
        var reading = new UnitPlans.Reading(plans, 3);

        var claude = ClaudeCodeLauncher.Prepare(Config, "SNC2D", courseName, reading, null);
        string claudeShim = Path.Combine(shimFolder, "claude.cmd");
        int claudeLength = OutsideDoor.LineLength(claudeShim, claude.Arguments);
        var codex = CodexLauncher.Prepare(Server, folder, "SNC2D", courseName, reading, null);
        string codexShim = Path.Combine(shimFolder, "codex.cmd");
        int codexLength = OutsideDoor.LineLength(codexShim, codex.Arguments);
        _output.WriteLine($"greeting {claude.Arguments[^1].Length} UTF-16 units; " +
                          $"Claude shim line {claudeLength} of {OutsideDoor.LimitFor(claudeShim)}; " +
                          $"Codex shim line {codexLength} of {OutsideDoor.LimitFor(codexShim)}");
        Assert.True(OutsideDoor.WithinCommandLineLimit(claudeShim, claude.Arguments), $"Claude: {claudeLength}");
        Assert.True(OutsideDoor.WithinCommandLineLimit(codexShim, codex.Arguments), $"Codex: {codexLength}");
        Assert.Contains(", and 3 more", claude.Arguments[^1]);
    }
}
