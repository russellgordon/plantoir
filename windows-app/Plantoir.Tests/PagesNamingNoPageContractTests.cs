using System.Text.Json.Nodes;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>assist-cases.json</c> → <c>pagesNamingNoPage</c> (#352 / mac #197): a
/// publish or hide whose page list names no page does nothing and SAYS so.
/// Run through the server's own tools, because the rule lives where both the
/// window's model and an MCP client pass (<c>AssistWorkspace.PlanPublish</c>).
/// </summary>
[Collection(SharedActivityState.Name)]
public class PagesNamingNoPageContractTests : IDisposable
{
    private const string Course = "ICS3U";
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-no-page").FullName;
    private readonly string _trail;

    public PagesNamingNoPageContractTests()
    {
        _trail = Path.Combine(_folder, "activity.txt");
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonNode Contract => ContractLoader.LoadJson("assist-cases.json")!["pagesNamingNoPage"]!;

    public static IEnumerable<object[]> Cases() =>
        ContractLoader.LoadJson("assist-cases.json")!["pagesNamingNoPage"]!["cases"]!.AsArray()
            .Select(c => new object[] { c!["name"]!.ToString() });

    /// <summary>
    /// A 'numbered' course names its pages "&lt;pageWord&gt; N" — clubs and
    /// numbered schemes (#274, mac #267), which this app does not have yet.
    /// Counted, so the skip cannot quietly grow.
    /// </summary>
    private static bool NeedsANumberedCourse(JsonNode c) => c["course"]!.ToString() == "numbered";

    [Fact]
    public void OnlyTheNumberedCasesWaitForClubs()
    {
        int waiting = Contract["cases"]!.AsArray().Count(c => NeedsANumberedCourse(c!));
        Assert.True(waiting <= 2, $"{waiting} pagesNamingNoPage cases now need a numbered course; #274 owns them.");
    }

    [Theory]
    [MemberData(nameof(Cases))]
    public async Task Case_MatchesContract(string name)
    {
        var c = Contract["cases"]!.AsArray().First(x => x!["name"]!.ToString() == name)!;
        if (NeedsANumberedCourse(c)) return;   // #274

        AddCourse(c["pages"]!.AsArray());
        var before = Snapshot();
        var wording = ContractLoader.LoadJson("assist-wording.json")!["wording"]!;

        var arguments = c["arguments"]!;
        string[] pages = arguments["pages"]!.ToString().Split(';', StringSplitOptions.TrimEntries);
        string onOrAfter = arguments["onOrAfter"]?.ToString() ?? "";
        string beforeDate = arguments["before"]?.ToString() ?? "";
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));
        var progress = new Progress<ProgressNotificationValue>(_ => { });

        CallToolResult result = c["tool"]!.ToString() switch
        {
            "publish_pages" => await tools.PublishPages(Course, 1, false, progress, default, pages, onOrAfter, beforeDate, preview: false),
            "unpublish_pages" => await tools.UnpublishPages(Course, 1, false, progress, default, pages, onOrAfter, beforeDate, preview: false),
            "plan_publish_pages" => tools.PlanPublishPages(Course, 1, false, pages, onOrAfter, beforeDate),
            "plan_unpublish_pages" => tools.PlanUnpublishPages(Course, 1, false, pages, onOrAfter, beforeDate),
            var other => throw new InvalidOperationException("No runner for " + other),
        };

        var expect = c["expect"]!;
        bool isPlan = result.Meta?[AssistToolAnswer.IsPlanKey]?.GetValue<bool>() == true;
        Assert.Equal(expect["isPlan"]!.GetValue<bool>(), isPlan);

        var changed = Snapshot().Where(pair => !before.TryGetValue(pair.Key, out var was) || was != pair.Value)
                                .Select(pair => pair.Key).OrderBy(t => t).ToList();
        var writes = expect["writes"]!.AsArray().Select(w => w!.ToString()).OrderBy(t => t).ToList();
        Assert.Equal(writes, changed);

        string trail = File.Exists(_trail) ? File.ReadAllText(_trail) : "";
        if (expect["wording"] is JsonValue key)
        {
            string sentence = wording[key.ToString()]!.ToString()
                .Replace("{course}", Course).Replace("{section}", "1");
            if (expect["fills"] is JsonObject fills)
                foreach (var (fill, value) in fills)
                    sentence = sentence.Replace("{" + fill + "}", value!.ToString());
            Assert.Equal(sentence, result.Summary());
            Assert.Contains("named no page it could find", trail);
            foreach (string page in pages)
                if (!AssistWorkspace.EveryPageWords.Contains(page.ToLowerInvariant()))
                    Assert.DoesNotContain(page, trail);
        }
        else if (expect["refusal"] is not null)
        {
            // This platform's own open-ended refusal: nothing written, not a
            // plan, and not the no-page line.
            Assert.DoesNotContain("named no page it could find", trail);
        }
    }

    [Fact]
    public void TheEveryPageWordsAreTheContractsOwn() =>
        Assert.Equal(Contract["everyPageWords"]!.AsArray().Select(w => w!.ToString()), AssistWorkspace.EveryPageWords);

    [Fact]
    public void EverythingInAUnit_AcceptedAndRefused()
    {
        foreach (var row in Contract["everythingInAUnit"]!["accepted"]!.AsArray())
        {
            string input = row!["input"]!.ToString();
            var match = AssistCardCommand.Matching(input);
            Assert.True(match is not null, $"“{input}” should be answered in code.");
            Assert.Equal(row["expectTool"]!.ToString(), match!.ToolName);
            Assert.Equal(row["expectPages"]!.ToString(), match.Arguments["pages"]);
            Assert.False(match.Arguments.ContainsKey("course"));
            Assert.False(match.Arguments.ContainsKey("section"));
        }
        foreach (var row in Contract["everythingInAUnit"]!["refused"]!.AsArray())
        {
            string input = row!["input"]!.ToString();
            Assert.True(AssistCardCommand.Matching(input) is null,
                $"“{input}” must reach the model: {row["why"]}");
        }
    }

    // ---- The fixture ------------------------------------------------------

    private void AddCourse(JsonArray pages)
    {
        string directory = Path.Combine(_folder, "courses", Course);
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "course_config.json"),
            $$"""
            {
              "course_code": "{{Course}}",
              "course_name": "A course",
              "deploy_target": "netlify",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1]
            }
            """);
        foreach (var page in pages)
        {
            string title = page!["title"]!.ToString();
            string full = Path.Combine(directory, "section1", "All Classes", title + ".md");
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            bool published = page["published"]!.GetValue<bool>();
            File.WriteAllText(full,
                $"---\npublish: {(published ? "true" : "false")}\ncreated: {page["date"]}T07:00:00.000-0400\n---\nBody.\n");
        }
    }

    private Dictionary<string, string> Snapshot() =>
        Directory.EnumerateFiles(Path.Combine(_folder, "courses", Course), "*.md", SearchOption.AllDirectories)
                 .ToDictionary(path => Path.GetFileNameWithoutExtension(path), File.ReadAllText);
}
