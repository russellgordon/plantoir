using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// shared-rules.json → linksChecklist.publishCases (#392 / #399 / #405), run
/// through the sheet MODEL and the publisher on a laid-out course, as
/// howThePublishCasesRun says.
/// </summary>
[Collection(SharedActivityState.Name)]
public class LinksChecklistPublishContractTests : IDisposable
{
    private const string Course = "ICS3U";
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-links-checklist").FullName;
    private string CourseDir => Path.Combine(_folder, "courses", Course);

    public LinksChecklistPublishContractTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        Directory.CreateDirectory(CourseDir);
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"), $$"""
            { "course_code": "{{Course}}", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonArray CaseList =>
        ContractLoader.LoadJson("shared-rules.json")!["linksChecklist"]!["publishCases"]!.AsArray();

    public static IEnumerable<object[]> Cases() => CaseList.Select(c => new object[] { c!["name"]!.ToString() });

    [Theory]
    [MemberData(nameof(Cases))]
    public void Case_MatchesContract(string name)
    {
        var c = CaseList.First(x => x!["name"]!.ToString() == name)!;
        var paths = Lay(c["pages"]!.AsArray());
        string front = Path.Combine(CourseDir, "section1", "index.md");
        File.WriteAllText(front, "---\npublish: true\n---\n## Most Recent Class\n\n![[Unit 1, Day 1]]\n");
        string frontBefore = File.ReadAllText(front);
        var offer = Offer(c["offer"]!.AsArray());
        var workspace = new AssistWorkspace(_folder, new FakeLauncher());

        if (c["answer"]?.ToString() == "notNow")
        {
            var untick = Titles(c, "untick");
            LinksChecklist.WriteAnswered(CourseDir, 1, offer.Rows.Select(r => r.Place), untick, DateTime.UtcNow);
            var (answered, _) = LinksChecklist.ReadAnswered(CourseDir, 1);
            Assert.Equal(c["expectOfferedAgainBeforeTheNewPage"]!.GetValue<bool>(), LinksChecklist.HoldsSomethingNew(offer, answered));
            var also = Row(c["thenOfferAlso"]!.AsObject());
            var grown = offer with { Rows = offer.Rows.Append(also).ToList() };
            Assert.Equal(c["expectOfferedAgainAfter"]!.GetValue<bool>(), LinksChecklist.HoldsSomethingNew(grown, answered));
            Lay(new JsonArray(new JsonObject { ["title"] = Path.GetFileName(also.Place), ["kind"] = "page", ["visible"] = false, ["date"] = "2026-02-01" }));
            var again = workspace.OpenLinksChecklist(grown);
            foreach (string place in Titles(c, "expectStartsUnticked"))
                Assert.False(again.Ticks[LinksChecklist.Key(place)], $"{place} should start unticked.");
            return;
        }

        foreach (string title in Titles(c, "deletedSince")) File.Delete(paths[title]);
        foreach (string title in Titles(c, "madeVisibleSince")) MakeVisible(paths[title]);

        var sheet = workspace.OpenLinksChecklist(offer);
        if (c["expectOffered"] is JsonArray offered)
            Assert.Equal(offered.Select(p => p!.ToString()).Order(), sheet.Rows.Select(r => r.Place).Order());

        var ticked = Titles(c, "tick").Select(LinksChecklist.Key).ToHashSet();
        foreach (var row in sheet.Rows) sheet.Ticks[LinksChecklist.Key(row.Place)] = ticked.Contains(LinksChecklist.Key(row.Place));

        if (c["expectLocked"] is JsonArray locked)
            Assert.Equal(locked.Select(p => p!.ToString()).Order(), sheet.Locked.Order());
        if (c["expectPublishCount"] is { } count)
            Assert.Equal(count.GetValue<int>(), sheet.ShownTicked.Count);
        if (c["expectComesWith"] is JsonObject comes)
            Assert.Equal(comes.Select(p => $"{p.Key}:{p.Value}").Order(), sheet.ComingWith.Select(p => $"{p.Key}:{p.Value}").Order());
        foreach (var (place, parts) in c["expectSecondLines"] as JsonObject ?? new JsonObject())
        {
            string line = sheet.SecondLine(sheet.Rows.Single(r => r.Place == place));
            foreach (var part in parts!.AsArray()) Assert.Contains(Part(part!), line);
        }
        foreach (var (place, parts) in c["expectSecondLinesLack"] as JsonObject ?? new JsonObject())
        {
            string line = sheet.SecondLine(sheet.Rows.Single(r => r.Place == place));
            foreach (var part in parts!.AsArray()) Assert.DoesNotContain(Part(part!), line);
        }

        foreach (string title in Titles(c, "madeVisibleAfterOpening")) MakeVisible(paths[title]);
        var published = workspace.PublishLinksChecklist(sheet);

        foreach (var (title, want) in c["expect"] as JsonObject ?? new JsonObject())
        {
            string text = File.ReadAllText(paths[title]);
            bool local = paths[title].Contains(Path.Combine(CourseDir, "section1"));
            Assert.True(want!["visible"]!.GetValue<bool>() == (PageFrontmatter.Visibility(text, 1) == PageVisibility.Visible),
                $"{name}: “{title}” visibility.");
            Assert.Equal(want["date"]!.ToString(), PageFrontmatter.CreatedOn(text, 1, local)?.ToString("yyyy-MM-dd"));
        }
        if (c["expectFrontPageUnchanged"]?.GetValue<bool>() == true) Assert.Equal(frontBefore, File.ReadAllText(front));

        var remembered = c["expectRememberedUnticked"] is JsonArray r ? r.Select(x => x!.ToString()).ToList()
                       : c["expectLeftHidden"] is JsonArray lh && c["expectLeftWithTheirPage"] is null ? lh.Select(x => x!.ToString()).ToList()
                       : null;
        if (remembered is not null) Assert.Equal(remembered.Order(), published.RememberedUnticked.Order());
        if (c["expectLeftWithTheirPage"] is JsonArray with)
            Assert.Equal(with.Select(x => x!.ToString()).Order(), published.LeftWithTheirPage.Order());
        if (c["expectLeftHidden"] is JsonArray left)
            Assert.Equal(left.Select(x => x!.ToString()).Order(), published.RememberedUnticked.Concat(published.LeftWithTheirPage).Order());
        if (c["expectChangedSince"] is JsonArray changed)
            Assert.Equal(changed.Select(x => x!.ToString()).Order(), published.ChangedSince.Order());
        if (c["expectCameWithAClass"] is { } came)
            Assert.Equal(came.GetValue<int>(), published.CameWithAClass);
    }

    /// <summary>The press records places and counts, never what a page says; the answer is remembered.</summary>
    [Fact]
    public void PublishingRecordsPlacesNeverContentAndRemembersTheUnticked()
    {
        string trail = Path.Combine(_folder, "activity.txt");
        Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(trail);
        try
        {
            var c = CaseList.First(x => x!["name"]!.ToString().StartsWith("iv-e."))!;
            Lay(c["pages"]!.AsArray());
            var workspace = new AssistWorkspace(_folder, new FakeLauncher());
            var sheet = workspace.OpenLinksChecklist(Offer(c["offer"]!.AsArray()));
            sheet.Ticks[LinksChecklist.Key("Concepts/Hub")] = false;
            AssistWorkspace.NoteOffered(sheet, "from the menu");
            workspace.PublishAndRemember(sheet);

            string written = File.ReadAllText(trail);
            Assert.Contains("offered to publish pages that links lead to, from the menu", written);
            Assert.Contains("Concepts/Glossary", written);
            Assert.Contains("(1 with the page they come under)", written);
            Assert.DoesNotContain("A sentence.", written);
            var (_, left) = LinksChecklist.ReadAnswered(CourseDir, 1);
            Assert.Equal(new[] { "Concepts/Hub" }, left.ToArray());
        }
        finally { Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath); }
    }

    private static string Part(JsonNode part)
    {
        string key = part["wording"]!.ToString();
        string template = (string)typeof(LinksChecklistWording).GetField(char.ToUpperInvariant(key[0]) + key[1..])!.GetValue(null)!;
        return LinksChecklistWording.Fill(template, new Dictionary<string, string> { ["name"] = $"“{part["name"]}”" });
    }

    // ---- The fixture ------------------------------------------------------

    private Dictionary<string, string> Lay(JsonArray pages)
    {
        var paths = new Dictionary<string, string>();
        foreach (var page in pages)
        {
            string title = page!["title"]!.ToString();
            bool isClass = page["kind"]!.ToString() == "class";
            bool visible = page["visible"]!.GetValue<bool>();
            string date = page["date"]?.ToString() ?? "2026-02-01";
            string links = string.Concat((page["links"] as JsonArray ?? new JsonArray()).Select(l => $"\nSee [[{l}]].\n"));
            string path = isClass
                ? Path.Combine(CourseDir, "section1", "All Classes", title + ".md")
                : Path.Combine(CourseDir, "Concepts", title + ".md");
            string front = isClass
                ? $"publish: {(visible ? "true" : "false")}\ncreated: {date}T07:00:00.000-0400"
                : $"publishForSection1: {(visible ? "true" : "false")}\ncreatedSection1: {date}T07:00:00.000-0400";
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, $"---\n{front}\n---\nA sentence.\n{links}");
            paths[title] = path;
        }
        return paths;
    }

    private static void MakeVisible(string path) =>
        File.WriteAllText(path, File.ReadAllText(path).Replace(": false", ": true"));

    private static LinksChecklistRow Row(JsonObject r) => new(
        r["place"]!.ToString(), r["group"]!.ToString(), r["ticked"]!.GetValue<bool>(),
        (r["dependsOn"] as JsonArray ?? new JsonArray()).Select(d => d!.ToString()).ToList(),
        Path.GetFileName(r["place"]!.ToString()), r["date"]?.ToString(), r["why"]?.ToString(), r["firstUsedIn"]?.ToString());

    private static LinksChecklistOffer Offer(JsonArray rows) =>
        new(Course, 1, "build-1", rows.Select(r => Row(r!.AsObject())).ToList());

    private static List<string> Titles(JsonNode c, string key) =>
        (c[key] as JsonArray ?? new JsonArray()).Select(x => x!.ToString()).ToList();
}
