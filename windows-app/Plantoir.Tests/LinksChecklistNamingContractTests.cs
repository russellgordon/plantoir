using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>linksChecklist.naming</c> (#399 remainder, mac
/// #385): the two LAID-OUT cases, run as <c>howTheCaseRuns</c> says — the
/// course laid out on disk the way <c>startOfYear.howToRunACase</c> defines,
/// the offer written as the build would write it, and the sheet opened on it
/// through <see cref="AssistWorkspace.OpenLinksChecklist"/>.
/// </summary>
public sealed class LinksChecklistNamingContractTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("checklist-naming").FullName;
    private string Course => Path.Combine(_folder, "courses", "ICS3U");

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonNode Naming => ContractLoader.LoadJson("shared-rules.json")["linksChecklist"]!["naming"]!;

    public static IEnumerable<object[]> Cases() =>
        ContractLoader.LoadJson("shared-rules.json")["linksChecklist"]!["naming"]!["cases"]!.AsArray()
            .Select(c => new object[] { c!["name"]!.ToString() });

    private void LayOut(JsonNode c)
    {
        if (Directory.Exists(_folder)) Directory.Delete(_folder, recursive: true);
        Directory.CreateDirectory(Course);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(Course, "course_config.json"),
            "{\"course_code\":\"ICS3U\",\"course_name\":\"Test\",\"num_sections\":1,\"section_numbers\":[1]," +
            "\"shared_folders\":[\"Concepts\"],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[]}");
        foreach (var page in c["pages"]!.AsArray())
        {
            string title = page!["title"]!.ToString();
            string kind = page["kind"]!.ToString();
            bool visible = page["visible"]?.GetValue<bool>() ?? true;
            string relative = kind switch
            {
                "class" => Path.Combine("section1", "All Classes", title + ".md"),
                "folderIndex" => Path.Combine(title, "index.md"),
                _ => Path.Combine(page["folder"]?.ToString() ?? "Concepts", title + ".md"),
            };
            string full = Path.Combine(Course, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            bool local = kind == "class";
            var header = new List<string> { "---" };
            if (kind != "folderIndex") header.Add($"title: {page["shownAs"]?.ToString() ?? title}");
            header.Add($"{(local ? "created" : "createdForSection1")}: 2026-09-08T07:00:00.000-0400");
            header.Add(local ? $"publish: {(visible ? "true" : "false")}" : $"publishForSection1: {(visible ? "true" : "false")}");
            header.Add("---");
            var body = (page["links"] as JsonArray ?? new JsonArray()).Select(link => $"See [[{link}]].");
            File.WriteAllText(full, string.Join("\n", header) + "\n" + string.Join("\n\n", body) + "\n", new UTF8Encoding(false));
        }
    }

    private LinksChecklistSheet Open(JsonNode c, string? without)
    {
        var rows = new JsonArray();
        foreach (var row in c["offer"]!.AsArray())
        {
            if (row!["place"]!.ToString() == without) continue;
            var copy = JsonNode.Parse(row.ToJsonString())!.AsObject();
            copy["title"] = row["place"]!.ToString().Split('/')[^1];
            copy["linkedFrom"] = JsonNode.Parse(c["linkedFrom"]?.ToJsonString() ?? "[]");
            rows.Add(copy);
        }
        string path = LinksChecklistOffer.PathFor(Course, 1);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, new JsonObject
        {
            ["version"] = 1, ["course"] = "ICS3U", ["section"] = 1, ["buildId"] = "b", ["pages"] = rows,
        }.ToJsonString());
        var offer = LinksChecklistOffer.Read(path)!;
        return new AssistWorkspace(_folder, new FakeLauncher()).OpenLinksChecklist(offer);
    }

    private static string Expected(JsonNode spec) =>
        spec["plain"] is { } plain
            ? plain.ToString()
            : LinksChecklistWording.RowInFolder.Replace("{page}", spec["page"]!.ToString()).Replace("{folder}", spec["folder"]!.ToString());

    private static string Rendered(JsonNode part) => part["wording"]!.ToString() switch
    {
        "pageName" => StartOfYearWording.PageName(part["page"]!.ToString()),
        "firstUsedIn" => LinksChecklistWording.FirstUsedIn.Replace("{name}", StartOfYearWording.PageName(part["name"]!.ToString())),
        "linkedFromRow" => LinksChecklistWording.LinkedFromRow.Replace("{name}", StartOfYearWording.PageName(part["name"]!.ToString())),
        var key => throw new InvalidOperationException("a wording key this runner does not render: " + key),
    };

    [Theory]
    [MemberData(nameof(Cases))]
    public void TheSheetNamesPagesAsTheContractSays(string name)
    {
        var c = Naming["cases"]!.AsArray().First(x => x!["name"]!.ToString() == name)!;
        LayOut(c);
        var sheet = Open(c, without: null);
        Assert.Equal(c["offer"]!.AsArray().Count, sheet.Rows.Count);

        void RowTitlesHold(JsonNode? expect, LinksChecklistSheet on)
        {
            foreach (var (place, spec) in expect as JsonObject ?? new JsonObject())
            {
                string shown = on.RowTitles[LinksChecklist.Key(place)];
                Assert.Equal(Expected(spec!), shown);
            }
        }
        RowTitlesHold(c["expectRowTitles"], sheet);

        var seconds = sheet.Rows.ToDictionary(r => r.Place, sheet.SecondLine);
        foreach (var part in c["expectSecondLinesContain"]?.AsArray() ?? new JsonArray())
            foreach (var (place, line) in seconds)
                Assert.True(line.Contains(Rendered(part!), StringComparison.Ordinal), $"{place}: “{line}” lacks {Rendered(part!)}");
        foreach (var never in c["expectSecondLinesNeverContain"]?.AsArray() ?? new JsonArray())
            foreach (var (place, line) in seconds)
                Assert.False(line.Contains(never!.ToString(), StringComparison.Ordinal), $"{place}: “{line}” says {never}");
        foreach (var (place, parts) in c["expectSecondLines"] as JsonObject ?? new JsonObject())
            foreach (var part in parts!.AsArray())
                Assert.True(seconds[place].Contains(Rendered(part!), StringComparison.Ordinal),
                            $"{place}: “{seconds[place]}” lacks {Rendered(part!)}");

        if (c["thenWithout"] is { } without)
            RowTitlesHold(c["expectRowTitlesThen"], Open(c, without.ToString()));
    }
}
