using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

public class ClassPlanningContractTests
{
    [Fact]
    public void PageNaming_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["pageNaming"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string title = c["title"]!.ToString();
            int? expectUnit = c["expectUnit"]?.GetValue<int>();
            int? expectDay = c["expectDay"]?.GetValue<int>();
            // A case with no `term` uses the DEFAULT word — which is what a
            // course says when `unit_word` is absent, and what every course
            // made before 2026-09-01 says. Read with a default rather than
            // treated as a new shape, or every pre-existing case breaks.
            string? term = c["term"]?.ToString();

            var parsed = UnitDay.Parse(title, term);
            if (expectUnit is null)
            {
                Assert.Null(parsed);
            }
            else
            {
                Assert.NotNull(parsed);
                Assert.Equal(expectUnit.Value, parsed.Value.Unit);
                Assert.Equal(expectDay!.Value, parsed.Value.Day);
            }
        }
    }

    [Fact]
    public void NumberedClassOrder_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var numberedOrder = doc["numberedClassOrder"]!.AsObject();
        var input = numberedOrder["input"]!.AsArray().Select(x => x!.ToString()).ToList();
        var expected = numberedOrder["expectOrder"]!.AsArray().Select(x => x!.ToString()).ToList();

        var actual = NextClassPlanner.NumberedClasses(input);
        Assert.Equal(expected, actual);
    }

    [Fact]
    public void NextClass_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["nextClass"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            var existing = c["existing"]!.AsArray().Select(x => x!.ToString()).ToList();
            int expectUnit = c["expectUnit"]!.GetValue<int>();
            int expectDay = c["expectDay"]!.GetValue<int>();

            var next = NextClassPlanner.NextUnitAndDay(existing);
            Assert.Equal(expectUnit, next.Unit);
            Assert.Equal(expectDay, next.Day);
        }
    }

    [Fact]
    public void NextClassPlanner_Date_OverflowsOntoLastDate()
    {
        var dates = new List<DateOnly>
        {
            new(2026, 9, 8),
            new(2026, 9, 10),
            new(2026, 9, 12),
        };

        Assert.Equal(new DateOnly(2026, 9, 8), NextClassPlanner.Date(0, dates, "ICS3U", 1));
        Assert.Equal(new DateOnly(2026, 9, 10), NextClassPlanner.Date(1, dates, "ICS3U", 1));
        Assert.Equal(new DateOnly(2026, 9, 12), NextClassPlanner.Date(2, dates, "ICS3U", 1));
        // Overflow past timetable count
        Assert.Equal(new DateOnly(2026, 9, 12), NextClassPlanner.Date(3, dates, "ICS3U", 1));
        Assert.Equal(new DateOnly(2026, 9, 12), NextClassPlanner.Date(10, dates, "ICS3U", 1));
    }

    [Fact]
    public void NextClassPlanner_Date_EmptyTimetable_RefusesWithInquiry()
    {
        var dates = new List<DateOnly>();
        var ex = Assert.Throws<AssistRefusal>(() => NextClassPlanner.Date(0, dates, "ICS3U", 1));
        Assert.Contains(AssistWording.MayIAskForYourDates, ex.Message);
        Assert.Contains("ICS3U Section 1", ex.Message);
    }

    [Fact]
    public void Insertion_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["insertion"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string name = c["name"]!.ToString();
            int unit = c["insertAtUnit"]!.GetValue<int>();
            int day = c["insertAtDay"]!.GetValue<int>();
            int count = c["count"]!.GetValue<int>();
            var timetable = c["timetable"]!.AsArray().Select(x => DateOnly.Parse(x!.ToString())).ToList();
            var expectRenames = c["expectRenamesInOrder"]!.AsArray().Select(x => x!.ToString()).ToList();

            string folder = Directory.CreateTempSubdirectory("contract-insert").FullName;
            try
            {
                File.WriteAllText(Path.Combine(folder, "preview.ps1"), "# marker");
                File.WriteAllText(Path.Combine(folder, "deploy.ps1"), "# marker");
                string courseDir = Path.Combine(folder, "courses", "ICS3U");
                string classesDir = Path.Combine(courseDir, "section1", "All Classes");
                Directory.CreateDirectory(classesDir);

                string configJson = """
                {
                  "course_code": "ICS3U",
                  "course_name": "Introduction to Computer Science",
                  "section_numbers": [1],
                  "num_sections": 1,
                  "per_section_folders": ["All Classes"],
                  "per_section_files": []
                }
                """;
                File.WriteAllText(Path.Combine(courseDir, "course_config.json"), configJson);

                TimetableMemory.Write(folder, "ICS3U", 1, timetable, "contract test", new DateOnly(2026, 9, 1));

                var existingClasses = c["existingClasses"]!.AsArray();
                foreach (var ex in existingClasses)
                {
                    string title = ex!["title"]!.ToString();
                    string date = ex["date"]!.ToString();
                    File.WriteAllText(
                        Path.Combine(classesDir, title + ".md"),
                        $"---\ntitle: {title}\npublish: true\ncreated: {date}T07:00:00.000-0400\n---\n\n{title}\n");
                }

                var workspace = new AssistWorkspace(folder, new FakeLauncher());
                var plan = workspace.PlanInsertClasses("ICS3U", 1, unit, day, count);

                var actualRenames = plan.Renames.Select(r => $"{r.From} → {r.To}").ToList();
                Assert.Equal(expectRenames, actualRenames);

                if (c["expectDateMoves"] is JsonArray expectedDateMoves)
                {
                    var movedTitles = plan.Moves.Select(m => m.Title).ToHashSet();
                    foreach (var exp in expectedDateMoves)
                    {
                        Assert.Contains(exp!.ToString(), movedTitles);
                    }
                }

                if (c["expectProblemMentions"] is JsonNode mentionsNode)
                {
                    string mentions = mentionsNode.ToString();
                    string allProblems = string.Join(" ", plan.Problems);
                    Assert.Contains(mentions, allProblems);
                }
            }
            finally
            {
                try { Directory.Delete(folder, recursive: true); } catch { }
            }
        }
    }

    [Fact]
    public void Refusals_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["refusals"]!["cases"]!.AsArray();

        string folder = Directory.CreateTempSubdirectory("contract-refuse").FullName;
        try
        {
            File.WriteAllText(Path.Combine(folder, "preview.ps1"), "# marker");
            File.WriteAllText(Path.Combine(folder, "deploy.ps1"), "# marker");
            string courseDir = Path.Combine(folder, "courses", "ICS3U");
            string classesDir = Path.Combine(courseDir, "section1", "All Classes");
            Directory.CreateDirectory(classesDir);

            string configJson = """
            {
              "course_code": "ICS3U",
              "course_name": "Introduction to Computer Science",
              "section_numbers": [1],
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": []
            }
            """;
            File.WriteAllText(Path.Combine(courseDir, "course_config.json"), configJson);

            File.WriteAllText(
                Path.Combine(classesDir, "Unit 1, Day 1.md"),
                "---\ntitle: Unit 1, Day 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\n\nUnit 1, Day 1\n");

            var workspace = new AssistWorkspace(folder, new FakeLauncher());

            foreach (var c in cases)
            {
                if (c is null) continue;
                int unit = c["insertAtUnit"]!.GetValue<int>();
                int day = c["insertAtDay"]!.GetValue<int>();
                int count = c["count"]!.GetValue<int>();

                Assert.Throws<AssistRefusal>(() => workspace.PlanInsertClasses("ICS3U", 1, unit, day, count));
            }
        }
        finally
        {
            try { Directory.Delete(folder, recursive: true); } catch { }
        }
    }

    [Fact]
    public void DatingPagesAClassBrings_FrontmatterKeys_MatchContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var keys = doc["datingPagesAClassBrings"]!["frontmatterKey"]!.AsObject();

        Assert.Equal(keys["sectionLocalPage"]!.ToString(), PageFrontmatter.CreatedKeyFor(1, isSectionLocal: true));
        string courseLevelTemplate = keys["courseLevelPage"]!.ToString();

        foreach (int section in new[] { 1, 2, 7 })
        {
            string expected = courseLevelTemplate.Replace("<N>", section.ToString());
            Assert.Equal(expected, PageFrontmatter.CreatedKeyFor(section, isSectionLocal: false));
        }
    }

    [Fact]
    public void DatingNonClassPages_ContractExistsAndIsDocumented()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var section = doc["datingNonClassPages"]!.AsObject();

        Assert.NotNull(section["note"]);
        var appliesTo = section["appliesTo"]!.AsArray();
        Assert.NotEmpty(appliesTo);
        Assert.NotNull(section["dateInherited"]);
        Assert.NotNull(section["why"]);
    }
}
