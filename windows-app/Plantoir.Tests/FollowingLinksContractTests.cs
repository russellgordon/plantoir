using System.Text.Json.Nodes;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The followingLinks case lists, run through a REAL publish or unpublish on a
/// course laid out from each case's <c>pages</c> (#203, #342, #359):
/// <c>shared-rules.json</c> → <c>followingLinks.stopsAtAClassPage.cases</c>,
/// <c>.publishing.cases</c>, <c>.unpublishing.cases</c>, and
/// <c>class-planning.json</c> → <c>datingPagesAClassBrings.reachStopsAtAClassPage.cases</c>.
/// </summary>
/// <remarks>
/// "Untouched" is asserted as BYTE-IDENTICAL, not merely still hidden: a page
/// that stayed hidden and was silently re-dated passes a visibility check and
/// is half of what the class-page stop is about. A synthetic page graph is not
/// used for the reason <c>SharedRulesContractTests</c> gives — it can be built
/// to agree with whatever it is asked.
/// </remarks>
public class FollowingLinksContractTests : IDisposable
{
    private const string Course = "ICS3U";
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-following").FullName;

    public FollowingLinksContractTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        string directory = Path.Combine(_folder, "courses", Course);
        Directory.CreateDirectory(Path.Combine(directory, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(directory, "course_config.json"), $$"""
            { "course_code": "{{Course}}", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonNode Following => ContractLoader.LoadJson("shared-rules.json")!["followingLinks"]!;
    private static JsonNode Wording => ContractLoader.LoadJson("assist-wording.json")!["wording"]!;

    public static IEnumerable<object[]> Lists() =>
        new[] { "stopsAtAClassPage", "publishing", "unpublishing" }
            .SelectMany(list => ContractLoader.LoadJson("shared-rules.json")!["followingLinks"]![list]!["cases"]!
                .AsArray().Select(c => new object[] { list, c!["name"]!.ToString() }));

    [Theory]
    [MemberData(nameof(Lists))]
    public async Task Case_MatchesContract(string list, string name)
    {
        var c = Following[list]!["cases"]!.AsArray().First(x => x!["name"]!.ToString() == name)!;
        var written = Lay(c["pages"]!.AsArray());
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));
        var progress = new Progress<ProgressNotificationValue>(_ => { });

        bool hiding = c["unpublish"] is not null;
        string[] named = (c[hiding ? "unpublish" : "publish"]!.AsArray()).Select(n => n!.ToString()).ToArray();

        string plan = (hiding
            ? tools.PlanUnpublishPages(Course, 1, includeLinked: true, pages: named)
            : tools.PlanPublishPages(Course, 1, includeLinked: true, pages: named)).Summary();
        var result = hiding
            ? await tools.UnpublishPages(Course, 1, true, progress, default, named, preview: false)
            : await tools.PublishPages(Course, 1, true, progress, default, named, preview: false);
        Assert.DoesNotContain("couldn", result.Summary());

        foreach (var title in Titles(c, "expectVisible")) Assert.True(Visible(title), $"{name}: “{title}” should be visible.");
        foreach (var title in Titles(c, "expectHidden")) Assert.False(Visible(title), $"{name}: “{title}” should be hidden.");
        foreach (var title in Titles(c, "expectUntouched"))
            Assert.True(File.ReadAllText(written[title]) == Bodies[title],
                $"{name}: “{title}” was rewritten; untouched means byte-identical.");

        // A publish changes whether students see a page, never what it says.
        if (list == "publishing")
            foreach (var (title, path) in written)
                Assert.Equal(BodyOf(Bodies[title]), BodyOf(File.ReadAllText(path)));

        foreach (var key in Titles(c, "expectPlanSays"))
            Assert.Contains(Rendered(key, c), plan);
        foreach (var key in Titles(c, "expectPlanDoesNotSay"))
            Assert.DoesNotContain(Rendered(key, c, mustFind: false), plan);
    }

    /// <summary>
    /// The class-page stop on the PUBLISH plan is said once, and only about a
    /// class students cannot certainly see (#203): about an already-published
    /// class, "publish it when you get to that class" would be false.
    /// </summary>
    [Theory]
    [InlineData(false, true)]
    [InlineData(true, false)]
    public void TheLeftAloneSentenceIsOnlyAboutAClassStudentsCannotSee(bool day4Visible, bool expected)
    {
        Lay(new JsonArray(
            Page("Unit 2, Day 3", true, false, "Unit 2, Day 4"),
            Page("Unit 2, Day 4", true, day4Visible)));
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));

        string plan = tools.PlanPublishPages(Course, 1, includeLinked: true, pages: new[] { "Unit 2, Day 3" }).Summary();

        Assert.Equal(expected, plan.Contains(AssistWording.LinkedClassWasLeftAlone(new[] { "Unit 2, Day 4" })));
    }

    // ---- class-planning.json → datingPagesAClassBrings.reachStopsAtAClassPage

    public static IEnumerable<object[]> DateCases() =>
        ContractLoader.LoadJson("class-planning.json")!["datingPagesAClassBrings"]!["reachStopsAtAClassPage"]!["cases"]!
            .AsArray().Select(c => new object[] { c!["name"]!.ToString() });

    [Theory]
    [MemberData(nameof(DateCases))]
    public async Task DateReach_MatchesContract(string name)
    {
        var c = ContractLoader.LoadJson("class-planning.json")!["datingPagesAClassBrings"]!["reachStopsAtAClassPage"]!
            ["cases"]!.AsArray().First(x => x!["name"]!.ToString() == name)!;
        var pages = new JsonArray();
        foreach (var cls in c["classes"]!.AsArray())
            pages.Add(Page(cls!["title"]!.ToString(), true, false,
                           cls["links"]!.AsArray().Select(l => l!.ToString()).ToArray(), cls["date"]!.ToString()));
        foreach (var page in c["pages"]!.AsArray())
            pages.Add(Page(page!["title"]!.ToString(), false, page["visible"]!.GetValue<bool>(),
                           Array.Empty<string>(), page["date"]!.ToString()));
        var written = Lay(pages);
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));

        string[] named = c["publish"]!.AsArray().Select(n => n!.ToString()).ToArray();
        await tools.PublishPages(Course, 1, true, new Progress<ProgressNotificationValue>(_ => { }), default,
                                 named, preview: false);

        foreach (var title in Titles(c, "expectNoMove"))
            Assert.Equal(DateOf(Bodies[title]), DateOf(File.ReadAllText(written[title])));
        if (c["expectMoves"] is JsonObject moves)
            foreach (var (title, date) in moves)
                Assert.Equal(date!.ToString(), DateOf(File.ReadAllText(written[title])));
    }

    // ---- The fixture ------------------------------------------------------

    private readonly Dictionary<string, string> Bodies = new();

    private static JsonObject Page(string title, bool isClass, bool visible, params string[] links) =>
        Page(title, isClass, visible, links, null);

    private static JsonObject Page(string title, bool isClass, bool visible, string[] links, string? date) => new()
    {
        ["title"] = title,
        ["isClassPage"] = isClass,
        ["visible"] = visible,
        ["links"] = new JsonArray(links.Select(l => (JsonNode)JsonValue.Create(l)!).ToArray()),
        ["date"] = date,
    };

    /// <summary>Writes each page; class pages in the class folder, the rest in the section.</summary>
    private Dictionary<string, string> Lay(JsonArray pages)
    {
        var paths = new Dictionary<string, string>();
        foreach (var page in pages)
        {
            string title = page!["title"]!.ToString();
            bool isClass = page["isClassPage"]?.GetValue<bool>() ?? false;
            if (page["links"] is not null && page["body"] is not null)
                throw new InvalidOperationException($"“{title}” carries both links and body; the harness must not choose.");

            string body = page["body"] is { } given
                ? given.ToString()
                : "A sentence.\n" + string.Concat(page["links"]!.AsArray().Select(l => $"\nSee [[{l}]].\n"));
            string date = page["date"]?.ToString() is { Length: > 0 } d ? d : "2026-09-08";
            string text = $"---\ntitle: {title}\npublish: {(page["visible"]!.GetValue<bool>() ? "true" : "false")}\n" +
                          $"created: {date}T07:00:00.000-0400\n---\n{body}";
            string path = Path.Combine(_folder, "courses", Course, "section1",
                                       isClass ? Path.Combine("All Classes", title + ".md") : title + ".md");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, text);
            paths[title] = path;
            Bodies[title] = text;
        }
        return paths;
    }

    private bool Visible(string title)
    {
        string path = Directory.EnumerateFiles(Path.Combine(_folder, "courses", Course), title + ".md",
                                               SearchOption.AllDirectories).Single();
        return PageFrontmatter.Visibility(File.ReadAllText(path), 1) == PageVisibility.Visible;
    }

    private static string BodyOf(string text)
    {
        int end = text.IndexOf("\n---\n", 4, StringComparison.Ordinal);
        return end < 0 ? text : text[(end + 5)..];
    }

    private static string? DateOf(string text) =>
        System.Text.RegularExpressions.Regex.Match(text, @"created: (\d{4}-\d{2}-\d{2})") is { Success: true } m
            ? m.Groups[1].Value : null;

    private static IEnumerable<string> Titles(JsonNode c, string key) =>
        c[key] is JsonArray list ? list.Select(t => t!.ToString()) : Enumerable.Empty<string>();

    /// <summary>
    /// A wording key's sentence, for the case: every key named here renders a
    /// page title, and a case with no page of that title must FAIL rather
    /// than pass by never matching.
    /// </summary>
    private static string Rendered(string key, JsonNode c, bool mustFind = true)
    {
        string sentence = Wording[key]!.ToString();
        var titles = c["pages"]!.AsArray().Select(p => p!["title"]!.ToString()).ToList();
        var quoted = System.Text.RegularExpressions.Regex.Matches(sentence, "“([^”]+)”")
            .Select(m => m.Groups[1].Value).ToList();
        if (mustFind)
            foreach (var title in quoted)
                Assert.True(titles.Contains(title), $"{key} renders “{title}”, which this case has no page called.");
        return sentence;
    }
}
