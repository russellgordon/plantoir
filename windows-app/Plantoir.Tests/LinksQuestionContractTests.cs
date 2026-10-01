using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>assist-cases.json</c> → <c>linksQuestion</c> (#305 / mac #167): "What
/// does &lt;page&gt; link to?" answered in code. The phrasing rows run against
/// the contract's window; the answering rows run against a real section
/// written from <c>answering.section</c> and <c>answering.sectionFiles</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public class LinksQuestionContractTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-links-question").FullName;
    private readonly string _trail;

    public LinksQuestionContractTests()
    {
        _trail = Path.Combine(_folder, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonNode Contract => ContractLoader.LoadJson("assist-cases.json")!["linksQuestion"]!;
    private static string WindowCourse => Contract["window"]!["course"]!.ToString();
    private static int WindowSection => Contract["window"]!["section"]!.GetValue<int>();

    private static readonly Lazy<HashSet<string>> Codes = new(() =>
    {
        var codes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string file in new[] { "ontario_secondary_courses.json", "british_columbia_secondary_courses.json" })
        {
            var catalog = Plantoir.Core.Catalogs.CourseNameCatalog.Load(ContractLoader.GetSupportPath(file));
            foreach (var (code, _) in catalog.AllEntries()) codes.Add(code);
        }
        return codes;
    });

    private static LinksQuestionMatch? Read(string input) =>
        AssistCardCommand.LinksQuestion(input, WindowCourse, WindowSection, code => Codes.Value.Contains(code));

    // ---- The phrasing ------------------------------------------------------

    [Fact]
    public void Accepted()
    {
        foreach (var row in Contract["accepted"]!.AsArray())
        {
            string input = row!["input"]!.ToString();
            var read = Read(input);
            Assert.True(read is { Page: not null, OtherCourse: null, OnlyIfAPageIsCalled: false },
                $"“{input}” should be answered in code ({row["why"]}).");
            Assert.Equal(row["expectPage"]!.ToString(), read!.Page);
            Assert.Equal(row["expectAsTyped"]?.ToString(), read.AsTyped);
        }
    }

    [Fact]
    public void AnotherCourseIsRefusedInCodeAndNothingIsRead()
    {
        foreach (var row in Contract["anotherCourse"]!.AsArray())
        {
            string input = row!["input"]!.ToString();
            var read = Read(input);
            Assert.True(read is { OtherCourse: not null }, $"“{input}” names another course ({row["why"]}).");
            Assert.Equal(row["expectCourse"]!.ToString(), read!.OtherCourse);
        }
    }

    [Fact]
    public void OnlyIfAPageIsCalled()
    {
        foreach (var row in Contract["onlyIfAPageIsCalled"]!.AsArray())
        {
            string input = row!["input"]!.ToString();
            var read = Read(input);
            Assert.True(read is { OnlyIfAPageIsCalled: true }, $"“{input}” is answered only if a page is called that.");
            Assert.Equal(row["expectPage"]!.ToString(), read!.Page);
        }
    }

    [Fact]
    public void RefusedGoesToTheModel()
    {
        foreach (var row in Contract["refused"]!.AsArray())
        {
            string input = row!["input"]!.ToString();
            Assert.True(Read(input) is null, $"“{input}” must go to the model: {row["why"]}");
        }
    }

    [Fact]
    public void WithNoWindowOnlySentencesNamingNoPlaceMatch()
    {
        Assert.NotNull(AssistCardCommand.LinksQuestion("What does Unit 2, Day 3 link to?"));
        Assert.Null(AssistCardCommand.LinksQuestion("What does Unit 2, Day 3 in ICS3U section 1 link to?"));
    }

    // ---- The answer --------------------------------------------------------

    private AssistWorkspace Section(string? bodyOfTheFirstPage = null)
    {
        string course = Path.Combine(_folder, "courses", WindowCourse);
        Directory.CreateDirectory(course);
        File.WriteAllText(Path.Combine(course, "course_config.json"), $$"""
            { "course_code": "{{WindowCourse}}", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [{{WindowSection}}] }
            """);
        string section = Path.Combine(course, $"section{WindowSection}");
        bool first = true;
        foreach (var page in Contract["answering"]!["section"]!.AsArray())
        {
            string path = Path.Combine(section, page!["path"]!.ToString().Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            string body = first && bodyOfTheFirstPage is not null ? bodyOfTheFirstPage : "Body.";
            File.WriteAllText(path,
                $"---\ntitle: {page["title"]}\npublish: {(page["publish"]!.GetValue<bool>() ? "true" : "false")}\n---\n{body}\n");
            first = false;
        }
        foreach (var file in Contract["answering"]!["sectionFiles"]!.AsArray())
        {
            string path = Path.Combine(section, file!.ToString().Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, "x");
        }
        return new AssistWorkspace(_folder, new FakeLauncher());
    }

    public static IEnumerable<object[]> AnsweringCases() =>
        ContractLoader.LoadJson("assist-cases.json")!["linksQuestion"]!["answering"]!["cases"]!.AsArray()
            .Select(c => new object[] { c!["name"]!.ToString() });

    [Theory]
    [MemberData(nameof(AnsweringCases))]
    public void Answering_MatchesContract(string name)
    {
        var c = Contract["answering"]!["cases"]!.AsArray().First(x => x!["name"]!.ToString() == name)!;
        string asked = Contract["answering"]!["section"]![0]!["title"]!.ToString();
        var workspace = Section(c["body"]!.ToString());

        string said = workspace.LinksAnswer(WindowCourse, WindowSection, asked, null, onlyIfFound: false)!;

        var expected = c["expect"]!.AsArray().Select(e =>
        {
            string shown = e!["shown"]!.ToString();
            return e["mark"] is { } mark ? $"• {shown} — {Wording(mark.ToString())}" : $"• {shown}";
        }).ToList();
        if (expected.Count == 0)
        {
            Assert.Equal(AssistWording.PageLinksToNothing(asked), said);
            return;
        }
        var lines = said.Split('\n');
        Assert.Equal(AssistWording.PageLinksTo(asked), lines[0]);
        Assert.Equal(expected, lines.Skip(1).ToList());
    }

    [Fact]
    public void Lookup_MatchesContract()
    {
        var workspace = Section();
        foreach (var row in Contract["answering"]!["lookup"]!.AsArray())
        {
            string ask = row!["ask"]!.ToString();
            string said = workspace.LinksAnswer(WindowCourse, WindowSection, ask, row["asTyped"]?.ToString(), false)!;
            switch (row["expect"]!.ToString())
            {
                case "found":
                    Assert.True(said.Contains("links to:") || said.Contains("link to any other page"),
                        $"“{ask}” should be found: {said}");
                    break;
                case "noPageCalled":
                    Assert.Equal(AssistWording.NoPageCalled(WindowCourse, WindowSection.ToString(), ask), said);
                    break;
                case "morePagesThanOneAreCalled":
                    Assert.StartsWith(AssistWording.MorePagesThanOneAreCalled(WindowCourse, WindowSection.ToString(), ask), said);
                    Assert.Contains("Review A", said);
                    Assert.Contains("Review B", said);
                    break;
                default:
                    Assert.Fail("Unknown expect " + row["expect"]);
                    break;
            }
        }
    }

    [Fact]
    public void OnlyIfFoundAndNothingIsCalledThatHandsTheSentenceOn()
    {
        var workspace = Section();
        Assert.Null(workspace.LinksAnswer(WindowCourse, WindowSection, "the quiz", null, onlyIfFound: true));
        Assert.NotNull(workspace.LinksAnswer(WindowCourse, WindowSection, "The Water Cycle", null, onlyIfFound: true));
    }

    // ---- The turn ----------------------------------------------------------

    /// <summary>
    /// The damaging direction: the answer must NOT reach the model's
    /// conversation, and the model must not be asked — on this turn or the
    /// next one's history.
    /// </summary>
    [Fact]
    public void TheAnswerEndsTheTurnAndNeverReachesTheModel()
    {
        var workspace = Section("Next: [[Unit 1, Day 2]]");
        var model = new ScriptModel().Says("Hello.");
        var agent = new AssistAgent(model, new ToolsOver(new PlantoirTools(workspace)), new JsonArray(),
                                    WindowCourse, WindowSection);

        var lines = agent.Say("What does Unit 1, Day 1 link to?", CancellationToken.None).GetAwaiter().GetResult();
        Assert.Empty(model.Asked);
        Assert.Contains(AssistWording.LinkedPageIsADraft, Assert.Single(lines).Text);

        agent.Say("hello there", CancellationToken.None).GetAwaiter().GetResult();
        string sent = model.Asked.Single().ToJsonString();
        Assert.DoesNotContain("link to", sent);
        Assert.DoesNotContain("draft, so students", sent);
        Assert.Contains("ran read_page with", File.ReadAllText(_trail));
    }

    [Fact]
    public void AnotherCourseSaysSoAndReadsNothing()
    {
        Section();
        var tools = new CannedTools();
        var agent = new AssistAgent(new ScriptModel(), tools, new JsonArray(), WindowCourse, WindowSection)
        {
            IsACourseCode = code => Codes.Value.Contains(code),
            CoursesInTheFolder = () => new[] { WindowCourse, "SPH3U" },
        };

        var lines = agent.Say("What does Unit 2, Day 3 in SPH3U link to?", CancellationToken.None).GetAwaiter().GetResult();

        Assert.Empty(tools.Calls);
        Assert.Equal(AssistWording.AskedAboutAnotherCourse(WindowCourse, "SPH3U"), Assert.Single(lines).Text);
        Assert.Contains("asked what a page links to in SPH3U", File.ReadAllText(_trail), StringComparison.Ordinal);
    }

    private static string Wording(string key) =>
        ContractLoader.LoadJson("assist-wording.json")!["wording"]![key]!.ToString();

    /// <summary>The real tools, reached directly — the scenario runner's RealTools, for one tool.</summary>
    private sealed class ToolsOver(PlantoirTools tools) : IToolServer
    {
        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments, Action<string>? progress = null,
                                               CancellationToken cancellation = default)
        {
            Assert.Equal("read_page", name);
            var result = tools.ReadPage(arguments["course"]!.ToString(), arguments["section"]!.GetValue<int>(),
                                        arguments["page"]!.ToString(), arguments["answer"]?.ToString() ?? "",
                                        arguments["asTyped"]?.ToString() ?? "", arguments["onlyIfFound"]?.ToString() ?? "");
            bool noPage = result.Meta?[AssistToolAnswer.NoPageFoundKey]?.GetValue<bool>() == true;
            return Task.FromResult(AssistToolAnswer.Same(result.Detail()) with { NoPageFound = noPage });
        }
    }
}
