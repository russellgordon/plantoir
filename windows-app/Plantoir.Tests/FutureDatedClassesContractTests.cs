using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>class-planning.json</c> → <c>futureDatedClasses</c> (#475, the mac's
/// <c>FutureDatedClassesTests</c>): every case laid out as REAL files, as
/// <c>howTheCasesRun</c> says, and run through this app's real readers —
/// <see cref="ClassesDatedLater.FlaggedIn"/>, the class-folder rule, the build's
/// visibility reader and <see cref="LaterClassesKept"/>. Plus the kept record's
/// own shape against <c>file-formats.json</c> → <c>laterClassesKept</c>.
/// </summary>
public sealed class FutureDatedClassesContractTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("future-dated").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonNode Rule => ContractLoader.LoadJson("class-planning.json")["futureDatedClasses"]!;

    public static IEnumerable<object[]> Cases() =>
        Rule["cases"]!.AsArray().Select(c => new object[] { c!["name"]!.ToString(), c.ToJsonString() });

    [Fact]
    public void TheContractStillHasItsCases() => Assert.True(Rule["cases"]!.AsArray().Count >= 24);

    [Theory]
    [MemberData(nameof(Cases))]
    public void EachCaseIsTheContracts(string name, string json)
    {
        var c = JsonNode.Parse(json)!;
        var today = DateOnly.Parse(c["today"]!.ToString(), System.Globalization.CultureInfo.InvariantCulture);
        string root = Path.Combine(_folder, Guid.NewGuid().ToString("N")[..8]);
        string courseDirectory = Path.Combine(root, "courses", "ICS3U");
        Directory.CreateDirectory(courseDirectory);
        File.WriteAllText(Path.Combine(root, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(root, "deploy.ps1"), "# marker");
        int section = c["section"]?.GetValue<int>() ?? 1;

        // The sections the pages live in, so a page in section 2 is a real
        // section's page rather than a stray folder.
        var sections = new SortedSet<int> { section };
        foreach (var page in c["pages"]!.AsArray()) sections.Add(page!["section"]?.GetValue<int>() ?? section);
        var numbers = new JsonArray();
        foreach (int number in sections) numbers.Add(number);
        var config = new JsonObject
        {
            ["course_code"] = "ICS3U", ["course_name"] = "Test", ["num_sections"] = sections.Count,
            ["section_numbers"] = numbers,
            ["shared_folders"] = new JsonArray(), ["shared_files"] = new JsonArray(),
            ["per_section_folders"] = new JsonArray("All Classes", "Concepts"), ["per_section_files"] = new JsonArray(),
            ["class_folder"] = "All Classes",
        };
        if (c["unitWord"] is { } word) config["unit_word"] = word.ToString();
        if (c["classPageScheme"] is { } scheme) config["class_page_scheme"] = scheme.ToString();
        if (c["noun"] is { } noun) config["class_noun"] = noun.ToString();
        File.WriteAllText(Path.Combine(courseDirectory, "course_config.json"), config.ToJsonString());

        foreach (var page in c["pages"]!.AsArray())
        {
            int pageSection = page!["section"]?.GetValue<int>() ?? section;
            string full = Path.Combine(courseDirectory, $"section{pageSection}",
                                       page["path"]!.ToString().Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            string created = page["created"] is JsonValue date ? $"created: {date}\n" : "";
            File.WriteAllText(full,
                $"---\ntitle: {Path.GetFileNameWithoutExtension(full)}\n{page["flag"]}\n{created}---\n",
                new UTF8Encoding(false));
        }

        if (c["kept"] is JsonArray kept)
        {
            string path = LaterClassesKept.PathFor(courseDirectory, section);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, new JsonObject
            {
                ["version"] = 1,
                ["answeredAt"] = "2026-10-07T20:00:00Z",
                ["kept"] = kept.DeepClone(),
            }.ToJsonString());
        }

        var course = Workspace.DiscoverCourses(root).Single(found => found.Code == "ICS3U");
        var flagged = ClassesDatedLater.FlaggedIn(course, section, today).Select(page => page.Place).ToList();
        var expected = c["expectFlagged"]!.AsArray().Select(place => place!.ToString()).ToList();
        Assert.True(expected.SequenceEqual(flagged),
            $"{name}: expected [{string.Join(" | ", expected)}], flagged [{string.Join(" | ", flagged)}]");
    }

    /// <summary>The record as written: the contract's path and keys, one row per place, the newer date winning.</summary>
    [Fact]
    public void TheKeptRecordIsTheFormatsShape()
    {
        var format = ContractLoader.LoadJson("file-formats.json")["laterClassesKept"]!;
        string courseDirectory = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(courseDirectory);

        string path = LaterClassesKept.PathFor(courseDirectory, 2);
        string expectedPath = format["path"]!.ToString().Replace("courses/<CODE>/", "").Replace("<N>", "2");
        Assert.Equal(Path.Combine(courseDirectory, expectedPath.Replace('/', Path.DirectorySeparatorChar)), path);

        var day5 = new ClassesDatedLater.Page("section2/All Classes/Unit 2, Day 5", "Unit 2, Day 5", new DateOnly(2026, 10, 14), true);
        Assert.True(LaterClassesKept.Keep(courseDirectory, 2, new[] { day5 }, new DateTime(2026, 10, 8, 23, 5, 9, DateTimeKind.Utc)));
        Assert.True(LaterClassesKept.Keep(courseDirectory, 2, new[] { day5 with { Date = new DateOnly(2026, 10, 16) } },
                                          new DateTime(2026, 10, 9, 1, 0, 0, DateTimeKind.Utc)));

        var written = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        var keys = format["keys"]!.AsObject().Select(pair => pair.Key).OrderBy(k => k, StringComparer.Ordinal);
        Assert.Equal(keys, written.Select(pair => pair.Key).OrderBy(k => k, StringComparer.Ordinal));
        Assert.Equal("2026-10-09T01:00:00Z", written["answeredAt"]!.ToString());
        var row = Assert.Single(written["kept"]!.AsArray());
        Assert.Equal("section2/All Classes/Unit 2, Day 5", row!["place"]!.ToString());
        Assert.Equal("2026-10-16", row["date"]!.ToString());
        Assert.Equal(new[] { new LaterClassesKept.Row("section2/All Classes/Unit 2, Day 5", "2026-10-16") },
                     LaterClassesKept.Read(courseDirectory, 2));
    }

    /// <summary>Released on rollover, with the links checklist's answer — and an undo writes it back.</summary>
    [Fact]
    public void TheKeptRecordGoesOnRollover_UnderTheSameUndo()
    {
        string courseDirectory = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(courseDirectory);
        var day5 = new ClassesDatedLater.Page("section1/All Classes/Unit 2, Day 5", "Unit 2, Day 5", new DateOnly(2026, 10, 14), true);
        LaterClassesKept.Keep(courseDirectory, 1, new[] { day5 });
        string path = LaterClassesKept.PathFor(courseDirectory, 1);
        string before = File.ReadAllText(path);

        var undo = new UndoHistory();
        undo.Begin("rolled over");
        LinksChecklist.ReleasePublishedPages(courseDirectory, 1, new DateTime(2027, 1, 30, 7, 0, 0), undo);
        undo.End();

        Assert.False(File.Exists(path));
        undo.Undo();
        Assert.Equal(before, File.ReadAllText(path));
    }
}
