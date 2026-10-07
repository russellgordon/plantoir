using System.Text.Json.Nodes;
using ModelContextProtocol;
using Plantoir.Core.Assist;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #436 item 4 (mac #425): naming two same-named pages on a publish plan.
/// Runs <c>shared-rules.json → publishPlanNaming.cases</c> as its
/// <c>howToRunACase</c> says — the mac's counterpart has the same name.
/// </summary>
public class PublishPlanNamingContractTests : IDisposable
{
    private const string Course = "ICS3U";
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-naming").FullName;

    public PublishPlanNamingContractTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        Directory.CreateDirectory(CourseDir);
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    private string CourseDir => Path.Combine(_folder, "courses", Course);

    private static JsonObject Contract => ContractLoader.LoadJson("shared-rules.json")["publishPlanNaming"]!.AsObject();

    public static IEnumerable<object[]> Cases() =>
        Contract["cases"]!.AsArray().Select(c => new object[] { c!["name"]!.ToString(), c.ToJsonString() });

    [Fact]
    public void TheContractStillHasItsFourCases() => Assert.True(Contract["cases"]!.AsArray().Count >= 4);

    [Theory]
    [MemberData(nameof(Cases))]
    public async Task EachCaseIsTheContracts(string name, string json)
    {
        var c = JsonNode.Parse(json)!.AsObject();
        var files = new Dictionary<string, string>();   // folder/file → full path
        foreach (var page in c["pages"]!.AsArray())
        {
            string file = page!["file"]!.ToString();
            string folder = page["folder"]!.ToString() == "classes" ? "section1/All Classes" : page["folder"]!.ToString();
            string full = Path.Combine(CourseDir, folder.Replace('/', Path.DirectorySeparatorChar), file + ".md");
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            string title = page["shownAs"] is { } shown ? $"title: {shown}\n" : "";
            string key = folder.StartsWith("section", StringComparison.Ordinal) ? "publish" : "publishForSection1";
            File.WriteAllText(full, $"---\n{title}{key}: false\n---\nBody.\n");
            files[$"{page["folder"]}/{file}"] = full;
        }
        var before = files.ToDictionary(pair => pair.Key, pair => File.ReadAllText(pair.Value));

        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));
        string[] asked = { c["pagesArgument"]!.ToString() };
        // The plan's text is read BEFORE any publish, which would make it
        // "already published"; both halves, whichever carries it.
        var planned = tools.PlanPublishPages(Course, 1, pages: asked);
        string plan = planned.Summary() + "\n" + planned.Detail();
        string said = c["asked"]!.ToString() == "publish_pages"
            ? (await tools.PublishPages(Course, 1, new Progress<ProgressNotificationValue>(_ => { }), default, asked,
                                        preview: false)).Summary()
            : planned.Summary();

        var expect = c["expect"]!.AsObject();
        if (expect["asks"]!.GetValue<bool>())
        {
            string opening = AssistWording.MorePagesThanOneAreCalled(Course, "1", expect["name"]!.ToString());
            var lines = expect["lines"]!.AsArray().Select(l => l!.ToString());
            Assert.Equal(opening + "\n" + string.Join("\n", lines), said);
        }
        else
        {
            foreach (var named in expect["planNames"]!.AsArray())
                Assert.True(plan.Contains(named + " will become visible", StringComparison.Ordinal),
                    $"{name}: the plan does not name {named}: {plan}");
        }

        // Only the files expect.written names changed — and only for a publish.
        var written = expect["written"]!.AsArray().Select(w => w!.ToString()).ToHashSet(StringComparer.Ordinal);
        foreach (var (key, full) in files)
        {
            bool changed = File.ReadAllText(full) != before[key];
            bool shouldChange = c["asked"]!.ToString() == "publish_pages" && written.Contains(key);
            Assert.True(changed == shouldChange, $"{name}: {key} changed was {changed}.");
        }
    }
}
