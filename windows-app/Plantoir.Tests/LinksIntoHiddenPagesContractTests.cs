using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>siteHealth.linksIntoHiddenPages.cases</c>,
/// run through this app's own check_section (#359 / mac #333): the build's
/// site-health finding, the mac's section graph and Windows must name the
/// same (from, to) pairs, or a teacher is told two different things about
/// one site.
/// </summary>
public class LinksIntoHiddenPagesContractTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-hidden-links").FullName;

    public LinksIntoHiddenPagesContractTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonArray CaseList =>
        ContractLoader.LoadJson("shared-rules.json")!["siteHealth"]!["linksIntoHiddenPages"]!["cases"]!.AsArray();

    public static IEnumerable<object[]> Cases() => CaseList.Select(c => new object[] { c!["name"]!.ToString() });

    [Theory]
    [MemberData(nameof(Cases))]
    public void Case_MatchesContract(string name)
    {
        var c = CaseList.First(x => x!["name"]!.ToString() == name)!;
        string course = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(course);
        File.WriteAllText(Path.Combine(course, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        foreach (var page in c["pages"]!.AsArray())
        {
            string path = Path.Combine(course, page!["path"]!.ToString().Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            string flag = page["visible"]!.GetValue<bool>() ? "" : "publish: false\n";
            File.WriteAllText(path, $"---\n{flag}---\n{page["body"]}");
        }

        var workspace = new AssistWorkspace(_folder, new FakeLauncher());
        var found = workspace.Course("ICS3U");
        var (graph, isHidden) = workspace.Inspect(found, 1);
        string Place(string full) =>
            Path.GetRelativePath(course, full).Replace('\\', '/') is var relative && relative.EndsWith(".md")
                ? relative[..^3] : Path.GetRelativePath(course, full).Replace('\\', '/');
        var pairs = graph.DanglingLinks(isHidden).Select(link => (Place(link.From), Place(link.To))).ToList();
        var expected = c["expect"]!.AsArray()
            .Select(pair => (pair![0]!.ToString(), pair[1]!.ToString())).ToList();
        Assert.Equal(expected, pairs);

        // And what the teacher reads: ten named, the rest counted.
        string said = new PlantoirTools(workspace).CheckSection("ICS3U", 1);
        if (c["expectDetailNames"] is { } named)
        {
            int listed = said.Split('\n').Count(line => line.StartsWith("\u2022 ", StringComparison.Ordinal) && line.Contains("(hidden)"));
            Assert.Equal(named.GetValue<int>(), listed);
            Assert.Contains($"\u2026and {c["expectAndMore"]!.GetValue<int>()} more.", said);
        }
        foreach (var (_, to) in expected.Take(10))
            Assert.Contains(to.Split('/')[^1] + "  (hidden)", said);
    }
}
