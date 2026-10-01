using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// <c>class-planning.json</c> → <c>todaysClassOnTheFrontPage</c> (#406, mac
/// #397): every case through this app's REAL readers on real files, as
/// <c>howTheCasesRun</c> says; the seven sentences; the Not Today record; and
/// the rule that only the section window's Preview button asks.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class TodaysClassContractTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("todays-class").FullName;
    private readonly string _trail;

    public TodaysClassContractTests()
    {
        _trail = Path.Combine(_folder, "trail.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(null);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonNode Rule => ContractLoader.LoadJson("class-planning.json")["todaysClassOnTheFrontPage"]!;

    private (AssistWorkspace Workspace, string Index, int Section) LayOut(JsonNode c, string name)
    {
        string root = Path.Combine(_folder, name.GetHashCode().ToString("x8"));
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Combine(root, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(root, "deploy.ps1"), "# marker");
        int section = c["section"]?.GetValue<int>() ?? 1;
        string course = Path.Combine(root, "courses", "ICS3U");
        var config = new JsonObject
        {
            ["course_code"] = "ICS3U", ["course_name"] = "Test", ["num_sections"] = 1,
            ["section_numbers"] = new JsonArray(section),
            ["shared_folders"] = new JsonArray(), ["shared_files"] = new JsonArray(),
            ["per_section_folders"] = new JsonArray("All Classes"), ["per_section_files"] = new JsonArray(),
        };
        if (c["unitWord"] is { } word) config["unit_word"] = word.ToString();
        if (c["classPageScheme"] is { } scheme) config["class_page_scheme"] = scheme.ToString();
        if (c["frontPageHeading"] is { } heading) config["front_page_heading"] = heading.ToString();
        if (c["noun"] is { } noun) config["class_noun"] = noun.ToString();
        Directory.CreateDirectory(course);
        File.WriteAllText(Path.Combine(course, "course_config.json"), config.ToJsonString());

        foreach (var k in c["classes"]!.AsArray())
        {
            string folder = k!["folder"]?.ToString() ?? "All Classes";
            string dir = Path.Combine(course, $"section{section}", folder);
            Directory.CreateDirectory(dir);
            var publish = k["publish"]!;
            string publishLine = publish.GetValueKind() == System.Text.Json.JsonValueKind.String
                ? "publish: \"true"                    // "unreadable": the unclosed quote
                : $"publish: {(publish.GetValue<bool>() ? "true" : "false")}";
            string created = k["created"] is { } date ? $"created: {date}\n" : "";
            File.WriteAllText(Path.Combine(dir, k["title"] + ".md"),
                $"---\ntitle: {k["title"]}\n{publishLine}\n{created}---\n", new UTF8Encoding(false));
        }
        string index = Path.Combine(course, $"section{section}", "index.md");
        File.WriteAllText(index, c["indexText"]!.ToString(), new UTF8Encoding(false));
        if (c["declined"] is JsonObject declined)
        {
            Directory.CreateDirectory(Path.Combine(course, ".publish_state"));
            File.WriteAllText(Path.Combine(course, ".publish_state", $"section{section}.front-page-not-today.json"),
                new JsonObject { ["version"] = "1", ["day"] = declined["day"]!.ToString(), ["class"] = declined["class"]!.ToString() }.ToJsonString());
        }
        return (new AssistWorkspace(root, new FakeLauncher()), index, section);
    }

    [Fact]
    public void EveryCaseIsAskedAndAnsweredAsTheContractSays()
    {
        var cases = Rule["cases"]!.AsArray();
        Assert.True(cases.Count >= 42, $"todaysClassOnTheFrontPage.cases lost cases: {cases.Count}");
        var failures = new List<string>();
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var (workspace, index, section) = LayOut(c, name);
            var today = DateOnly.Parse(c["today"]!.ToString());
            var offer = workspace.TodaysClassOffer("ICS3U", section, today);
            var expect = c["expectAsk"];
            if (expect is null)
            {
                if (offer is not null) failures.Add($"{name}: asked about {offer.Show}, expected no question");
                continue;
            }
            if (offer is null) { failures.Add($"{name}: not asked, expected {expect["show"]} for {expect["shows"]}"); continue; }
            if (offer.Show != expect["show"]!.ToString() || offer.Shows != expect["shows"]!.ToString())
            {
                failures.Add($"{name}: offered {offer.Show} for {offer.Shows}, expected {expect["show"]} for {expect["shows"]}");
                continue;
            }
            if (c["expectAfterYes"] is not JsonObject after) continue;
            var outcome = workspace.ShowTodaysClass("ICS3U", section, today, offer);
            string written = File.ReadAllText(index);
            if (outcome != TodaysClassOnTheFrontPage.Outcome.Written) failures.Add($"{name}: Yes gave {outcome}");
            if (Body(written) != after["body"]!.ToString())
                failures.Add($"{name}: body\n  expected {System.Text.Json.JsonSerializer.Serialize(after["body"]!.ToString())}\n  got      {System.Text.Json.JsonSerializer.Serialize(Body(written))}");
            if (CreatedDay(written) != after["createdDay"]!.ToString())
                failures.Add($"{name}: created {CreatedDay(written)}, expected {after["createdDay"]}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void NotTodayIsRememberedForThatDayAndClassAndSaid()
    {
        var c = Rule["cases"]!.AsArray().First(k => k!["name"]!.ToString().StartsWith("the ordinary morning"))!;
        var (workspace, _, section) = LayOut(c, "not today");
        var today = DateOnly.Parse(c["today"]!.ToString());
        var offer = workspace.TodaysClassOffer("ICS3U", section, today)!;
        workspace.DeclineTodaysClass("ICS3U", section, today, offer);
        Assert.Null(workspace.TodaysClassOffer("ICS3U", section, today));
        Assert.NotNull(workspace.TodaysClassOffer("ICS3U", section, today.AddDays(1)) ?? offer);   // another day is a new question (no class then: nothing)
        Assert.Contains("left the front page as it was — Not Today: Unit 2, Day 5 offered, it showed Unit 2, Day 4", File.ReadAllText(_trail));
    }

    [Fact]
    public void AnAnswerAfterTheClassChangedWritesNothing()
    {
        var c = Rule["cases"]!.AsArray().First(k => k!["name"]!.ToString().StartsWith("the ordinary morning"))!;
        var (workspace, index, section) = LayOut(c, "changed");
        var today = DateOnly.Parse(c["today"]!.ToString());
        var offer = workspace.TodaysClassOffer("ICS3U", section, today)!;
        string before = File.ReadAllText(index);
        // After midnight: decided again for the day ASKED, still Yes-able —
        // but answered as if for tomorrow, no class is today's, nothing written.
        Assert.Equal(TodaysClassOnTheFrontPage.Outcome.NoLongerOffered,
                     workspace.ShowTodaysClass("ICS3U", section, today.AddDays(3), offer));
        Assert.Equal(before, File.ReadAllText(index));
    }

    [Fact]
    public void TheSentencesAreTheContracts()
    {
        var w = Rule["wording"]!;
        Assert.Equal(w["question"]!.ToString().Replace("{class}", "X"), TodaysClassOnTheFrontPage.Question("X"));
        Assert.Equal(w["because"]!.ToString().Replace("{noun}", "meeting").Replace("{shown}", "Y"),
                     TodaysClassOnTheFrontPage.Because(ClassNoun.Meeting, "Y"));
        Assert.Equal(w["show"]!.ToString(), TodaysClassOnTheFrontPage.Show);
        Assert.Equal(w["notToday"]!.ToString(), TodaysClassOnTheFrontPage.NotToday);
        Assert.Equal(w["notChangedTitle"]!.ToString(), TodaysClassOnTheFrontPage.NotChangedTitle);
        Assert.Equal(w["noLongerOffered"]!.ToString().Replace("{noun}", "class"), TodaysClassOnTheFrontPage.NoLongerOffered(ClassNoun.Class));
        Assert.Equal(w["couldNotSave"]!.ToString().Replace("{shown}", "Y"), TodaysClassOnTheFrontPage.CouldNotSave("Y"));
    }

    /// <summary>
    /// Asked from the section window's Preview button and NOTHING else: no
    /// file but the section window and the workspace wrapper names the offer.
    /// The mac pins the same with a source test on <c>startPreview()</c>.
    /// </summary>
    [Fact]
    public void OnlyThePreviewButtonAsks()
    {
        string repo = ContractLoader.RepositoryRoot;
        var callers = Directory.GetFiles(Path.Combine(repo, "windows-app"), "*.cs", SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")
                        && !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                        && !f.Contains("Plantoir.Tests") && !f.Contains("Plantoir.UiTests"))
            .Where(f => File.ReadAllText(f).Contains("TodaysClassOffer(", StringComparison.Ordinal))
            .Select(Path.GetFileName)
            .OrderBy(n => n)
            .ToList();
        Assert.Equal(new[] { "AssistWorkspace.cs", "SectionDetailView.xaml.cs" }, callers);
    }

    private static string Body(string page)
    {
        if (!page.StartsWith("---", StringComparison.Ordinal)) return page;
        int end = page.IndexOf("\n---", 3, StringComparison.Ordinal);
        int after = page.IndexOf('\n', end + 1);
        return after < 0 ? "" : page[(after + 1)..];
    }

    private static string? CreatedDay(string page)
    {
        foreach (string raw in page.Split('\n').Skip(1))
        {
            string line = raw.TrimEnd('\r');
            if (line.Trim() == "---") break;
            if (line.StartsWith("created:", StringComparison.Ordinal))
            {
                string value = line["created:".Length..].Trim().Trim('"', '\'');
                return value.Length >= 10 ? value[..10] : value;
            }
        }
        return null;
    }
}
