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
[Collection(SharedActivityState.Name)]
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
        // Kept for reference, showing MPM2D, with two sections; and a course
        // whose settings file cannot be read (batch review M1).
        Course("MPM2D-2024", 1, 2);
        string kept = Path.Combine(_folder, "courses", "MPM2D-2024", "course_config.json");
        var values = JsonNode.Parse(File.ReadAllText(kept))!.AsObject();
        values["course_code"] = "MPM2D";
        values["kept_for_reference"] = true;
        values["reference_school_year"] = 2024;
        File.WriteAllText(kept, values.ToJsonString());
        string bad = Directory.CreateDirectory(Path.Combine(_folder, "courses", "BAD1X")).FullName;
        File.WriteAllText(Path.Combine(bad, "course_config.json"), "{ this is not json");
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

    /// <summary>
    /// The order, by source (batch review M1): Program.cs asks
    /// <see cref="MissingArguments.InFrontOfTheTool"/> and puts what it
    /// supplied into the request BEFORE returning its refusal; that function
    /// supplies first, then asks the reference gate, then the outside-change
    /// gate, and only then says the filter's own sentence.
    /// </summary>
    [Fact]
    public void TheServerSuppliesFirstThenAsksTheGatesThenTheFilter()
    {
        string program = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Mcp", "Program.cs"));
        int front = program.IndexOf("MissingArguments.InFrontOfTheTool(", StringComparison.Ordinal);
        int supplied = program.IndexOf("calling.Arguments = arguments;", StringComparison.Ordinal);
        int refused = program.IndexOf("front.Refusal is { } refusal", StringComparison.Ordinal);
        Assert.True(front > 0 && supplied > front && refused > supplied, "Program.cs: InFrontOfTheTool, then the supplied arguments, then the refusal");
        Assert.DoesNotContain("MissingArguments.For(", program);

        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Mcp", "MissingArguments.cs"));
        string body = source[source.IndexOf("public static Outcome InFrontOfTheTool(", StringComparison.Ordinal)..];
        int missing = body.IndexOf("For(tool, arguments, workspace)", StringComparison.Ordinal);
        int reference = body.IndexOf("ReferenceWriteGate.Refusal(tool, runWith, workspace)", StringComparison.Ordinal);
        int outside = body.IndexOf("OutsideChangeGate.Refusal(tool, runWith, workspace)", StringComparison.Ordinal);
        int own = body.IndexOf("?? missing.Refusal", StringComparison.Ordinal);
        Assert.True(missing > 0 && reference > missing && outside > reference && own > outside,
                    "InFrontOfTheTool: supply, the reference gate, the outside-change gate, then its own refusal");
    }

    /// <summary>A course kept for reference, two sections, none named: a writing tool gets the reference refusal, not a question about which section (batch review M1).</summary>
    [Fact]
    public void AReferenceCourseIsRefusedAsOneBeforeASectionIsAskedFor()
    {
        var workspace = Workspace();
        foreach (string tool in new[] { "publish_pages", "deploy_section", "schedule_deploy", "unpublish_pages" })
        {
            var named = WithoutASection(tool, "MPM2D-2024");
            named["section"] = JsonSerializer.SerializeToElement(1);
            string? gate = ReferenceWriteGate.Refusal(tool, named, workspace);
            Assert.True(gate is not null, $"{tool}: the reference gate let it through");
            var outcome = MissingArguments.InFrontOfTheTool(tool, WithoutASection(tool, "MPM2D-2024"), workspace);
            Assert.Equal(gate, outcome.Refusal);
        }
        // A tool that only reads is not gated, so it is asked which section.
        Assert.Equal(AssistWording.NoSectionNamed("MPM2D-2024", MissingArguments.SectionsPhrase(new[] { 1, 2 })),
                     MissingArguments.InFrontOfTheTool("list_pages", Args(new { course = "MPM2D-2024" }), workspace).Refusal);
    }

    /// <summary>A course whose settings file cannot be read keeps the gate's fail-safe sentence, never "there's no course called" (batch review M1).</summary>
    [Fact]
    public void AnUnreadableSettingsFileKeepsItsFailSafeSentence()
    {
        var workspace = Workspace();
        var named = Args(new { course = "BAD1X", section = 1, pages = "Day 1" });
        string? failSafe = ReferenceWriteGate.Refusal("publish_pages", named, workspace);
        Assert.True(failSafe is not null, "the reference gate did not refuse an unreadable settings file");
        Assert.Equal(failSafe, MissingArguments.InFrontOfTheTool("publish_pages", Args(new { course = "BAD1X", pages = "Day 1" }), workspace).Refusal);
    }

    /// <summary>For an ordinary course the four sentences still answer through the whole front of the tool, and the one section is supplied.</summary>
    [Fact]
    public void TheFourSentencesStillAnswerThroughTheFrontOfTheTool()
    {
        var workspace = Workspace();
        Assert.Equal(AssistWording.NoSectionNamed("MPM2D", MissingArguments.SectionsPhrase(new[] { 1, 2 })),
                     MissingArguments.InFrontOfTheTool("deploy_section", Args(new { course = "MPM2D" }), workspace).Refusal);
        Assert.Equal(AssistWording.NoSectionNamedAndNoSections("SNC2D"),
                     MissingArguments.InFrontOfTheTool("publish_pages", Args(new { course = "SNC2D", pages = "x" }), workspace).Refusal);
        Assert.Equal(AssistWording.AddClassesNeedsAUnit,
                     MissingArguments.InFrontOfTheTool("add_classes", Args(new { course = "MPM2D", section = 1, howMany = 2 }), workspace).Refusal);
        Assert.Equal(AssistWording.AddClassesNeedsACount,
                     MissingArguments.InFrontOfTheTool("add_classes", Args(new { course = "MPM2D", section = 1, unit = 1 }), workspace).Refusal);
        var one = MissingArguments.InFrontOfTheTool("list_pages", Args(new { course = "ICS3U" }), workspace);
        Assert.Null(one.Refusal);
        Assert.Equal(1, one.Arguments!["section"].GetInt32());
    }

    /// <summary>A count of 0 or less is asked for, as the mac's addClassesQuestion asks (no contract case covers it); a positive count runs.</summary>
    [Fact]
    public void ACountOfZeroOrLessIsAskedFor()
    {
        var workspace = Workspace();
        foreach (string tool in MissingArguments.AddClassesTools)
        {
            foreach (object count in new object[] { 0, -1, "0" })
                Assert.Equal(AssistWording.AddClassesNeedsACount,
                             MissingArguments.For(tool, Args(new Dictionary<string, object> { ["course"] = "MPM2D", ["section"] = 1, ["unit"] = 1, ["howMany"] = count }), workspace).Refusal);
            Assert.Null(MissingArguments.For(tool, Args(new { course = "MPM2D", section = 1, unit = 1, howMany = 1 }), workspace).Refusal);
        }
    }
}
