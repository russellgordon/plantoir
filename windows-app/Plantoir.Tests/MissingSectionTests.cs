using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Mcp;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// #885 (the mac's #865): what <c>plantoir-mcp</c> answers a call that names
/// no section, or an <c>add_classes</c> call with no unit or count, through
/// <see cref="MissingArguments"/>, the filter Program.cs runs before any tool.
/// Named by refusal case, after the mac's <c>AssistMissingSectionTests</c>;
/// every sentence is <see cref="AssistWording"/>'s, pinned to
/// <c>assist-wording.json</c> by key. No stdio drive here (a server left
/// behind holds <c>Plantoir.Core.dll</c> open): that was measured once and is
/// recorded in the issue's closing comment.
/// </summary>
public sealed class MissingSectionTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-missing-section").FullName;
    private readonly ITestOutputHelper _output;

    public MissingSectionTests(ITestOutputHelper output)
    {
        _output = output;
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "exit 0\n");
        Course("MPM2D", 1, 2);
        Course("ICS3U", 1);
        Course("SNC2D");
        Course("ENG4U", 1, 2, 3);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private void Course(string code, params int[] sections)
    {
        string directory = Directory.CreateDirectory(Path.Combine(_folder, "courses", code)).FullName;
        File.WriteAllText(Path.Combine(directory, "course_config.json"),
            new JsonObject
            {
                ["course_name"] = code + " course", ["course_code"] = code,
                ["section_numbers"] = new JsonArray(sections.Select(n => (JsonNode)n).ToArray()),
            }.ToJsonString());
    }

    private AssistWorkspace Workspace() => new(_folder, new FakeLauncher());

    private static Dictionary<string, JsonElement> Args(object values) =>
        JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(JsonSerializer.Serialize(values))!;

    private static IReadOnlyDictionary<string, IReadOnlySet<string>> Served => MissingArguments.RequiredBy(typeof(PlantoirTools));

    /// <summary>Every argument a tool requires, with section left out (and unit/howMany given, so section is what is missing).</summary>
    private static Dictionary<string, JsonElement> WithoutASection(string tool, string course)
    {
        var values = new Dictionary<string, object> { ["course"] = course };
        if (Served[tool].Contains("unit")) values["unit"] = 1;
        if (Served[tool].Contains("howMany")) values["howMany"] = 2;
        return Args(values);
    }

    private static IEnumerable<string> ToolsThatRequireASection() =>
        Served.Where(pair => pair.Value.Contains("section")).Select(pair => pair.Key).OrderBy(n => n, StringComparer.Ordinal);

    [Fact]
    public void TheFourSentencesAreTheContracts()
    {
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!;
        Assert.Equal(wording["noSectionNamed"]!.ToString(), AssistWording.NoSectionNamed("{course}", "{sections}"));
        Assert.Equal(wording["noSectionNamedAndNoSections"]!.ToString(), AssistWording.NoSectionNamedAndNoSections("{course}"));
        Assert.Equal(wording["addClassesNeedsAUnit"]!.ToString(), AssistWording.AddClassesNeedsAUnit);
        Assert.Equal(wording["addClassesNeedsACount"]!.ToString(), AssistWording.AddClassesNeedsACount);
    }

    /// <summary>The sections phrase the contract names, "Sections 1 and 2" or "Sections 1, 2 and 3".</summary>
    [Fact]
    public void TheSectionsAreNamedAsTheMacNamesThem()
    {
        Assert.Equal("Sections 1 and 2", MissingArguments.SectionsPhrase(new[] { 1, 2 }));
        Assert.Equal("Sections 1, 2 and 3", MissingArguments.SectionsPhrase(new[] { 1, 2, 3 }));
    }

    /// <summary>
    /// Every tool that requires a section, called on a two-section course with
    /// none, answers <c>noSectionNamed</c> naming both, and runs nothing. The
    /// count is reported (the mac's is 32 of 33; Windows serves 43 tools).
    /// </summary>
    [Fact]
    public void EveryToolThatRequiresASectionSaysWhichOnesThereAre()
    {
        var workspace = Workspace();
        var tools = ToolsThatRequireASection().ToList();
        _output.WriteLine($"{tools.Count} of {Served.Count} served tools require a section: {string.Join(", ", tools)}");
        Assert.True(tools.Count >= 30, tools.Count.ToString());
        Assert.Contains("list_curriculum_expectations", tools);
        foreach (string tool in tools)
        {
            var outcome = MissingArguments.For(tool, WithoutASection(tool, "MPM2D"), workspace);
            Assert.True(AssistWording.NoSectionNamed("MPM2D", MissingArguments.SectionsPhrase(new[] { 1, 2 })) == outcome.Refusal,
                        $"{tool}: {outcome.Refusal}");
        }
        foreach (string tool in tools)
            Assert.Equal(AssistWording.NoSectionNamed("ENG4U", MissingArguments.SectionsPhrase(new[] { 1, 2, 3 })),
                         MissingArguments.For(tool, WithoutASection(tool, "ENG4U"), workspace).Refusal);
    }

    /// <summary>A course with no sections says so; a course with one is answered for it, the section supplied.</summary>
    [Fact]
    public void ACourseWithNoneOrOneSection()
    {
        var workspace = Workspace();
        foreach (string tool in ToolsThatRequireASection())
        {
            Assert.Equal(AssistWording.NoSectionNamedAndNoSections("SNC2D"),
                         MissingArguments.For(tool, WithoutASection(tool, "SNC2D"), workspace).Refusal);

            var asked = WithoutASection(tool, "ICS3U");
            var outcome = MissingArguments.For(tool, asked, workspace);
            Assert.True(outcome.Refusal is null, $"{tool}: {outcome.Refusal}");
            Assert.Equal(1, outcome.Arguments!["section"].GetInt32());
            Assert.False(asked.ContainsKey("section"), "the call's own arguments were changed in place");
        }
    }

    /// <summary>A named section is untouched, one that is not there included (its own sentence, from the tool), and so is a null-free call that names it.</summary>
    [Fact]
    public void ANamedSectionIsLeftAsItWas()
    {
        var workspace = Workspace();
        foreach (string tool in ToolsThatRequireASection())
            foreach (int section in new[] { 1, 3, 0 })
            {
                var asked = WithoutASection(tool, "MPM2D");
                asked["section"] = JsonSerializer.SerializeToElement(section);
                var outcome = MissingArguments.For(tool, asked, workspace);
                Assert.Null(outcome.Refusal);
                Assert.Same(asked, outcome.Arguments);
            }
    }

    /// <summary>A JSON null is a section nobody named.</summary>
    [Fact]
    public void ANullSectionIsMissing()
    {
        var asked = Args(new { course = "MPM2D", section = (int?)null });
        Assert.Equal(AssistWording.NoSectionNamed("MPM2D", MissingArguments.SectionsPhrase(new[] { 1, 2 })),
                     MissingArguments.For("list_pages", asked, Workspace()).Refusal);
    }

    /// <summary>The course comes first, in its own words: none named, or one that is not here.</summary>
    [Fact]
    public void TheCourseIsFoundFirst()
    {
        var workspace = Workspace();
        Assert.Equal(AssistWording.NoCourseNamed, MissingArguments.For("list_pages", Args(new { }), workspace).Refusal);
        Assert.Equal(AssistWording.NoCourseNamed, MissingArguments.For("list_pages", Args(new { course = "  " }), workspace).Refusal);
        string expected;
        try { workspace.Course("ZZZ9Z"); expected = ""; }
        catch (AssistRefusal refusal) { expected = refusal.Message; }
        Assert.NotEqual("", expected);
        Assert.Equal(expected, MissingArguments.For("list_pages", Args(new { course = "ZZZ9Z" }), workspace).Refusal);
        // A call that names its section and no course is left to the tool, as before.
        var named = Args(new { section = 1 });
        Assert.Same(named, MissingArguments.For("list_pages", named, workspace).Arguments);
        Assert.Null(MissingArguments.For("list_pages", named, workspace).Refusal);
    }

    /// <summary>The <c>add_classes</c> pair asks for the unit, then the count, after the course and section are found; with both it runs.</summary>
    [Fact]
    public void AddClassesWithoutAUnitOrACountAsks()
    {
        var workspace = Workspace();
        foreach (string tool in MissingArguments.AddClassesTools)
        {
            Assert.Contains(tool, Served.Keys);
            Assert.Equal(AssistWording.AddClassesNeedsAUnit,
                         MissingArguments.For(tool, Args(new { course = "MPM2D", section = 1, howMany = 2 }), workspace).Refusal);
            Assert.Equal(AssistWording.AddClassesNeedsACount,
                         MissingArguments.For(tool, Args(new { course = "MPM2D", section = 1, unit = 1 }), workspace).Refusal);
            Assert.Equal(AssistWording.AddClassesNeedsAUnit,
                         MissingArguments.For(tool, Args(new { course = "MPM2D", section = 1 }), workspace).Refusal);
            // The section is asked about before the count.
            Assert.Equal(AssistWording.NoSectionNamed("MPM2D", MissingArguments.SectionsPhrase(new[] { 1, 2 })),
                         MissingArguments.For(tool, Args(new { course = "MPM2D", unit = 1 }), workspace).Refusal);
            // A one-section course is answered for its section, and then asked for the count.
            Assert.Equal(AssistWording.AddClassesNeedsACount,
                         MissingArguments.For(tool, Args(new { course = "ICS3U", unit = 1 }), workspace).Refusal);
            var both = Args(new { course = "MPM2D", section = 1, unit = 1, howMany = 2 });
            Assert.Null(MissingArguments.For(tool, both, workspace).Refusal);
            Assert.Same(both, MissingArguments.For(tool, both, workspace).Arguments);
        }
        // Another tool that requires a unit keeps the SDK's answer (rule 3 is the add_classes pair's only).
        foreach (var (tool, needs) in Served.Where(p => p.Value.Contains("unit") && !MissingArguments.AddClassesTools.Contains(p.Key)))
        {
            var asked = Args(new { course = "MPM2D", section = 1 });
            Assert.Null(MissingArguments.For(tool, asked, workspace).Refusal);
        }
    }

    /// <summary>
    /// What the filter reads as REQUIRED is what <c>tools/list</c> says is
    /// required (the generated <c>toolSchemas.mcp</c>), for every tool on both,
    /// so it can never answer for an argument a schema calls optional.
    /// </summary>
    [Fact]
    public void WhatTheFilterReadsAsRequiredIsTheSchemas()
    {
        var mcp = ContractLoader.LoadJson("assist-cases.json")["toolSchemas"]!["mcp"]!.AsArray();
        int compared = 0;
        foreach (var schema in mcp)
        {
            string name = schema!["function"]!["name"]!.ToString();
            if (!Served.TryGetValue(name, out var needs)) continue;
            var required = schema["function"]!["parameters"]!["required"]?.AsArray().Select(r => r!.ToString()).ToHashSet() ?? new HashSet<string>();
            foreach (string argument in new[] { "course", "section", "unit", "howMany" })
                Assert.True(required.Contains(argument) == needs.Contains(argument), $"{name}.{argument}");
            compared++;
        }
        Assert.True(compared >= 30, compared.ToString());
    }

    /// <summary>
    /// The built-in assistant never meets these answers: its local tools do
    /// not include the <c>add_classes</c> pair, and its window writes course
    /// and section into every call whose tool declares them
    /// (<c>AssistAgent.BoundToThisWindow</c>, pinned here by source).
    /// </summary>
    [Fact]
    public void TheBuiltInAssistantNeverMeetsThem()
    {
        var local = ContractLoader.LoadJson("assist-cases.json")["toolSchemas"]!["local"]!.AsArray()
            .Select(t => t!["function"]!["name"]!.ToString()).ToList();
        Assert.NotEmpty(local);
        foreach (string tool in MissingArguments.AddClassesTools) Assert.DoesNotContain(tool, local);
        string agent = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Assist", "AssistAgent.cs"));
        Assert.Contains("bool section = Declares(name, \"section\");", agent);
        Assert.Contains("arguments[\"section\"] = _section;", agent);
    }

    /// <summary>The server runs the filter, before the reference gate and with what it supplied (review L1): a source rule, as ReferenceRefusalTests pins the gate.</summary>
    [Fact]
    public void TheServerAsksTheFilterFirst()
    {
        string program = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Mcp", "Program.cs"));
        int filter = program.IndexOf("MissingArguments.For(", StringComparison.Ordinal);
        int gate = program.IndexOf("ReferenceWriteGate.Refusal(", StringComparison.Ordinal);
        Assert.True(filter > 0 && gate > filter, "MissingArguments.For must be called before ReferenceWriteGate.Refusal");
        Assert.Contains("calling.Arguments = arguments;", program);
    }
}
