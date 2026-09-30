using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>class-planning.json → renamingTheUnitWord</c> (#158): the seven plan
/// cases, each on a course built on disk, and the six link cases; plus the
/// sheet's sentences against <c>specialNames.renameUnitWord</c> and a real
/// rename carried out end to end in the contract's order.
/// </summary>
public sealed class UnitWordRenameContractTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-unitword-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonNode Rules => ContractLoader.LoadJson("class-planning.json")["renamingTheUnitWord"]!;

    private UnitWordRenameCourseFacts Build(string name, JsonArray pages, IEnumerable<int> sections)
    {
        string course = Path.Combine(_root, name.GetHashCode().ToString("X"), "courses", "ICS3U");
        foreach (int section in sections)
            Directory.CreateDirectory(Path.Combine(course, $"section{section}", "All Classes"));
        foreach (var page in pages)
        {
            string path = Path.Combine(course, $"section{page!["section"]!.GetValue<int>()}", "All Classes",
                page["title"]!.ToString() + ".md");
            File.WriteAllText(path, $"---\ntitle: {page["title"]}\n---\nBody.\n");
        }
        return new UnitWordRenameCourseFacts("ICS3U", course, sections.ToList(), new[] { "All Classes" }, "");
    }

    [Fact]
    public void EveryPlanCaseIsFollowed()
    {
        var cases = Rules["cases"]!.AsArray();
        Assert.True(cases.Count >= 7, $"{cases.Count} renamingTheUnitWord cases; 7 were there on 2026-09-10.");
        var failures = new List<string>();
        foreach (var testCase in cases)
        {
            var pages = testCase!["pages"]!.AsArray();
            var sections = pages.Select(p => p!["section"]!.GetValue<int>()).Distinct().OrderBy(n => n).ToList();
            string from = testCase["from"]!.ToString();
            var facts = Build(testCase["name"]!.ToString(), pages, sections) with { CurrentWord = from };
            var plan = UnitWordRenamer.Plan(from, testCase["to"]!.ToString(), facts);
            string name = testCase["name"]!.ToString();

            if (testCase["expectRefused"]?.GetValue<bool>() == true)
            {
                if (plan.Renames.Count != 0 || plan.Problems.Count == 0) failures.Add($"{name}: not refused");
                continue;
            }
            var expected = testCase["expectRenames"]!.AsArray()
                .Select(r => $"{r!["section"]}:{r["from"]}→{r["to"]}").OrderBy(x => x, StringComparer.Ordinal).ToList();
            var actual = plan.Renames.Select(r => $"{r.Section}:{r.From}→{r.To}").OrderBy(x => x, StringComparer.Ordinal).ToList();
            if (!expected.SequenceEqual(actual))
                failures.Add($"{name}: renames [{string.Join(", ", actual)}], expected [{string.Join(", ", expected)}]");
            var expectedSections = testCase["expectSections"]!.AsArray().Select(n => n!.GetValue<int>()).ToList();
            if (!expectedSections.SequenceEqual(plan.SectionsTouched))
                failures.Add($"{name}: sections [{string.Join(", ", plan.SectionsTouched)}]");
            if (testCase["expectLinkMap"] is JsonObject map)
            {
                var want = map.Select(pair => $"{pair.Key}→{pair.Value}").OrderBy(x => x, StringComparer.Ordinal);
                var got = plan.LinkMap.Select(pair => $"{pair.Key}→{pair.Value}").OrderBy(x => x, StringComparer.Ordinal);
                if (!want.SequenceEqual(got)) failures.Add($"{name}: link map [{string.Join(", ", got)}]");
            }
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void EveryLinkCaseIsFollowed()
    {
        var cases = Rules["linkCases"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 6, $"{cases.Count} link cases; 6 were there when #339 was filed.");
        var failures = new List<string>();
        foreach (var testCase in cases)
        {
            string from = testCase!["from"]!.ToString(), to = testCase["to"]!.ToString();
            var map = testCase["pageTitles"]!.AsArray().Select(t => t!.ToString())
                .ToDictionary(t => t, t => UnitDay.Parse(t, from)!.Value.TitleIn(to));
            string actual = WikiLinks.Rewriting(testCase["text"]!.ToString(), map);
            if (actual != testCase["expect"]!.ToString()) failures.Add($"{testCase["name"]}: {actual}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void TheSheetsSentencesAreTheContracts()
    {
        var words = ContractLoader.LoadJson("shared-rules.json")["specialNames"]!["renameUnitWord"]!;
        var problems = words["problems"]!;
        var preview = words["preview"]!;
        Assert.Equal(words["fieldLabel"]!.ToString(), UnitWordRenameWording.FieldLabel);
        Assert.Equal(words["renameButton"]!.ToString(), UnitWordRenameWording.RenameButton);
        Assert.Equal(words["sheetTitle"]!.ToString(), UnitWordRenameWording.SheetTitle("{word}"));
        Assert.Equal(words["rowCaption"]!.ToString(), UnitWordRenameWording.RowCaption("{word}"));
        Assert.Equal(words["proseIsLeftAlone"]!.ToString(), UnitWordRenameWording.ProseIsLeftAlone);
        Assert.Equal(words["lookingOver"]!.ToString(), UnitWordRenameWording.LookingOver);
        Assert.Equal(problems["empty"]!.ToString(), UnitWordRenameWording.ProblemEmpty);
        Assert.Equal(problems["unchanged"]!.ToString(), UnitWordRenameWording.ProblemUnchanged);
        Assert.Equal(problems["mustFinishFirst"]!.ToString(), UnitWordRenameWording.ProblemMustFinishFirst("{target}"));
        Assert.Equal(problems["pageInTheWay"]!.ToString().Replace("{n}", "7"), UnitWordRenameWording.ProblemPageInTheWay("{code}", 7, "{name}"));
        Assert.Equal(problems["pageUnreadable"]!.ToString().Replace("{n}", "7"), UnitWordRenameWording.ProblemPageUnreadable("{code}", 7, "{name}"));
        Assert.Equal(problems["recordNotWritten"]!.ToString(), UnitWordRenameWording.ProblemRecordNotWritten("{reason}"));
        Assert.Equal(problems["busy"]!.ToString(), UnitWordRenameWording.ProblemBusy("{code}"));
        Assert.Equal(preview["pagesNone"]!.ToString(), UnitWordRenameWording.Pages(0, new[] { 1 }, "{code}", "{old}", "{new}"));
        Assert.Equal(preview["pagesOne"]!.ToString().Replace("{sections}", "Section 1"),
            UnitWordRenameWording.Pages(1, new[] { 1 }, "{code}", "{old}", "{new}"));
        Assert.Equal(preview["pagesMany"]!.ToString().Replace("{pages}", "4").Replace("{sections}", "Sections 1, 2 and 4"),
            UnitWordRenameWording.Pages(4, new[] { 1, 2, 4 }, "{code}", "{old}", "{new}"));
        Assert.Equal(preview["linksNone"]!.ToString(), UnitWordRenameWording.Links(0));
        Assert.Equal(preview["linksOne"]!.ToString(), UnitWordRenameWording.Links(1));
        Assert.Equal(preview["linksMany"]!.ToString().Replace("{count}", "3"), UnitWordRenameWording.Links(3));
        Assert.Equal(words["donePublish"]!.ToString(), UnitWordRenameWording.DonePublish);
        Assert.Equal(words["doneBackup"]!.ToString(), UnitWordRenameWording.DoneBackup);
        Assert.Equal(words["interruptedRename"]!["message"]!.ToString(), UnitWordRenameWording.InterruptedRename("{old}", "{new}"));
        Assert.Equal(words["halfDone"]!.ToString().Replace("{renamed}", "2").Replace("{total}", "5"),
            UnitWordRenameWording.HalfDone(2, 5, "{name}", "{reason}"));
        Assert.Equal(words["settingsNotWritten"]!.ToString(), UnitWordRenameWording.SettingsNotWritten("{new}", "{reason}"));

        var outcome = new UnitWordRenameOutcome(3, 2, 1, new[] { 1 }, "b.zip");
        Assert.Equal(
            string.Join(" ", words["done"]!.ToString().Replace("{old}", "Unit").Replace("{new}", "Module"),
                words["donePagesMany"]!.ToString().Replace("{pages}", "3"),
                words["doneLinksMany"]!.ToString().Replace("{links}", "2"),
                words["doneLinksNotWrittenOne"]!.ToString(),
                words["donePublish"]!.ToString(), words["doneBackup"]!.ToString()),
            UnitWordRenameWording.Done("Unit", "Module", outcome));
    }

    [Fact]
    public void ARenameRunsInTheContractsOrderAndFinishesAnInterruptedOne()
    {
        var pages = new JsonArray(
            new JsonObject { ["section"] = 1, ["title"] = "Unit 1, Day 1" },
            new JsonObject { ["section"] = 1, ["title"] = "Unit 1, Day 2" });
        var facts = Build("order", pages, new[] { 1 }) with { CurrentWord = "Unit" };
        string day2 = Path.Combine(facts.DirectoryPath, "section1", "All Classes", "Unit 1, Day 2.md");
        File.WriteAllText(day2, "---\ntitle:\n  Unit 1, Day 2\n---\nSee [[Unit 1, Day 1]] and `[[Unit 1, Day 1]]`.\n");

        var plan = UnitWordRenamer.Plan("Unit", "Module", facts);
        var outcome = UnitWordRenamer.CarryOut(plan, UnitWordRenamer.ReadEveryPage(plan), facts, "backup.zip");

        string moved = File.ReadAllText(Path.Combine(facts.DirectoryPath, "section1", "All Classes", "Module 1, Day 2.md"));
        Assert.Equal("---\ntitle: Module 1, Day 2\n---\nSee [[Module 1, Day 1]] and `[[Unit 1, Day 1]]`.\n", moved);
        Assert.False(File.Exists(day2));
        Assert.Equal(2, outcome.PagesRenamed);
        Assert.Equal(1, outcome.LinksRewritten);
        // The record is still there until the settings are written: an
        // interrupted rename is recognised and finished by running it again.
        Assert.Equal("Module", UnitWordRenamer.InterruptedRenameTarget(facts));
        Assert.Equal(UnitWordRenameWording.ProblemMustFinishFirst("Module"), UnitWordRenamer.Problem("Unit", "Thread", "Module"));
        Assert.Null(UnitWordRenamer.Problem("Unit", "Module", "Module"));
        var again = UnitWordRenamer.Plan("Unit", "Module", facts);
        Assert.Empty(again.Renames);
        Assert.Equal("Module 1, Day 1", again.LinkMap["Unit 1, Day 1"]);
    }
}
