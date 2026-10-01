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
            var naming = NamingOf(c, "term");

            if (naming.IsNumbered)
            {
                // A runner asserts the NUMBER, never a unit (#274).
                int? expectNumber = c["expectNumber"]?.GetValue<int>();
                Assert.Equal(expectNumber, naming.Parse(title)?.Day);
                continue;
            }

            var parsed = naming.Parse(title);
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

        var scheme = numberedOrder["numberedScheme"]!;
        var naming = NamingOf(scheme, "word");
        Assert.True(naming.IsNumbered);
        Assert.Equal(scheme["expectOrder"]!.AsArray().Select(x => x!.ToString()).ToList(),
                     NextClassPlanner.NumberedClasses(scheme["input"]!.AsArray().Select(x => x!.ToString()), naming));
    }

    /// <summary>The course's naming a case describes: <c>scheme</c> plus its word key.</summary>
    internal static ClassPageNaming NamingOf(JsonNode c, string wordKey) =>
        new(c[wordKey]?.ToString(),
            ClassPageSchemes.Reading(c["scheme"]?.ToString()));

    /// <summary>A course_config.json for the scratch course, numbered when the case says so.</summary>
    internal static string ConfigFor(ClassPageNaming naming) =>
        naming.IsNumbered
            ? $$"""
              {
                "course_code": "ICS3U",
                "course_name": "Introduction to Computer Science",
                "section_numbers": [1],
                "num_sections": 1,
                "per_section_folders": ["All Classes"],
                "per_section_files": [],
                "class_page_scheme": "numbered",
                "unit_word": "{{naming.Word}}",
                "class_noun": "meeting"
              }
              """
            : """
              {
                "course_code": "ICS3U",
                "course_name": "Introduction to Computer Science",
                "section_numbers": [1],
                "num_sections": 1,
                "per_section_folders": ["All Classes"],
                "per_section_files": []
              }
              """;

    /// <summary>A page, with a <c>created</c> only when the case gives a date.</summary>
    internal static string PageText(string title, string? date) =>
        date is null
            ? $"---\ntitle: {title}\npublish: true\n---\n\n{title}\n"
            : $"---\ntitle: {title}\npublish: true\ncreated: {date}T07:00:00.000-0400\n---\n\n{title}\n";

    [Fact]
    public void NextClass_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["nextClass"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            var naming = NamingOf(c, "word");

            if (c["existingClasses"] is JsonArray dated)
            {
                // The DATED form: through the real planner, title AND date.
                string folder = Directory.CreateTempSubdirectory("contract-next").FullName;
                try
                {
                    var workspace = ScratchCourse(folder, naming, dated,
                        c["timetable"]!.AsArray().Select(x => DateOnly.Parse(x!.ToString())).ToList());
                    var plan = workspace.PlanAddNextClass("ICS3U", 1);
                    Assert.Equal(naming.Title(1, c["expectNumber"]!.GetValue<int>()), plan.Classes.Single().Title);
                    Assert.Equal(DateOnly.Parse(c["expectDate"]!.ToString()), plan.Classes.Single().Date);
                }
                finally { try { Directory.Delete(folder, recursive: true); } catch { } }
                continue;
            }

            var existing = c["existing"]!.AsArray().Select(x => x!.ToString()).ToList();
            var next = NextClassPlanner.NextUnitAndDay(existing, naming);
            if (naming.IsNumbered)
            {
                Assert.Equal(c["expectNumber"]!.GetValue<int>(), next.Day);
                continue;
            }
            Assert.Equal(c["expectUnit"]!.GetValue<int>(), next.Unit);
            Assert.Equal(c["expectDay"]!.GetValue<int>(), next.Day);
        }
    }

    /// <summary>A scratch working folder holding ICS3U Section 1 with these classes and this timetable.</summary>
    internal static AssistWorkspace ScratchCourse(string folder, ClassPageNaming naming, JsonArray existingClasses,
                                                  IReadOnlyList<DateOnly>? timetable)
    {
        File.WriteAllText(Path.Combine(folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(folder, "deploy.ps1"), "# marker");
        string courseDir = Path.Combine(folder, "courses", "ICS3U");
        string classesDir = Path.Combine(courseDir, "section1", "All Classes");
        Directory.CreateDirectory(classesDir);
        File.WriteAllText(Path.Combine(courseDir, "course_config.json"), ConfigFor(naming));
        if (timetable is not null)
            TimetableMemory.Write(folder, "ICS3U", 1, timetable.ToList(), "contract test", new DateOnly(2026, 9, 1));
        foreach (var ex in existingClasses)
        {
            string title = ex!["title"]!.ToString();
            File.WriteAllText(Path.Combine(classesDir, title + ".md"), PageText(title, ex["date"]?.ToString()));
        }
        return new AssistWorkspace(folder, new FakeLauncher());
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
            var naming = NamingOf(c, "word");
            // A numbered case names ONE number; this planner holds it as unit 1.
            int unit = naming.IsNumbered ? 1 : c["insertAtUnit"]!.GetValue<int>();
            int day = naming.IsNumbered ? c["insertAtNumber"]!.GetValue<int>() : c["insertAtDay"]!.GetValue<int>();
            int count = c["count"]!.GetValue<int>();
            var timetable = c["timetable"]!.AsArray().Select(x => DateOnly.Parse(x!.ToString())).ToList();
            var expectRenames = c["expectRenamesInOrder"]!.AsArray().Select(x => x!.ToString()).ToList();

            string folder = Directory.CreateTempSubdirectory("contract-insert").FullName;
            try
            {
                var workspace = ScratchCourse(folder, naming, c["existingClasses"]!.AsArray(), timetable);
                var plan = workspace.PlanInsertClasses("ICS3U", 1, unit, day, count);

                var actualRenames = plan.Renames.Select(r => $"{r.From} → {r.To}").ToList();
                Assert.Equal(expectRenames, actualRenames);

                if (c["expectAddedOn"] is JsonObject addedOn)
                    foreach (var (title, date) in addedOn)
                        Assert.Equal(DateOnly.Parse(date!.ToString()), plan.Added.Single(a => a.Title == title).Date);

                if (c["expectMovedTo"] is JsonObject movedTo)
                    foreach (var (title, date) in movedTo)
                        Assert.True(plan.Moves.Any(m => m.Title == title && m.To == DateOnly.Parse(date!.ToString())),
                            $"“{name}”: {title} should move to {date}; moves were " +
                            string.Join(", ", plan.Moves.Select(m => $"{m.Title} → {DateText.Iso(m.To)}")));

                if (c["expectNotMoved"] is JsonArray notMoved)
                    foreach (var title in notMoved)
                        Assert.DoesNotContain(plan.Moves, m => m.Title == title!.ToString());

                if (c["expectNoMoves"]?.GetValue<bool>() == true)
                    Assert.True(plan.Moves.Count == 0, $"“{name}”: expected no moves, got " +
                        string.Join(", ", plan.Moves.Select(m => $"{m.Title} → {DateText.Iso(m.To)}")));

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

    /// <summary>
    /// Duplicating a lesson as the next class: where the copy lands, what else
    /// moves, and whether it can be taken back.
    ///
    /// <para>Pure planner data — a timetable, a list of classes, a page title
    /// — so it is portable, which is why it is in the contract rather than
    /// only in <c>DuplicateClassTests</c>. The mac has no runner for this key
    /// yet, and its second case is expected to fail there: its undo is keyed
    /// on renames alone.</para>
    /// </summary>
    [Fact]
    public void Duplication_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["duplication"]!["cases"]!.AsArray();
        Assert.NotEmpty(cases);

        foreach (var c in cases)
        {
            if (c is null) continue;
            string name = c["name"]!.ToString();
            var timetable = c["timetable"]!.AsArray().Select(x => DateOnly.Parse(x!.ToString())).ToList();
            var expectRenames = c["expectRenamesInOrder"]!.AsArray().Select(x => x!.ToString()).ToList();

            string folder = Directory.CreateTempSubdirectory("contract-duplicate").FullName;
            try
            {
                string classesDir = Path.Combine(folder, "courses", "ICS3U", "section1", "All Classes");
                var workspace = ScratchCourse(folder, NamingOf(c, "word"), c["existingClasses"]!.AsArray(), timetable);
                var plan = workspace.PlanDuplicateClass("ICS3U", 1, c["duplicate"]!.ToString());

                Assert.Equal(c["expectNewTitle"]!.ToString(), plan.NewTitle);
                Assert.Equal(DateOnly.Parse(c["expectDate"]!.ToString()), plan.NewDate);
                Assert.Equal(expectRenames, plan.Insertion.Renames.Select(r => $"{r.From} → {r.To}").ToList());

                bool undoOffered = c["expectUndoOffered"]!.GetValue<bool>();
                Assert.True(undoOffered != plan.MovesOtherClasses,
                    $"“{name}”: the contract says undo is " + (undoOffered ? "offered" : "withheld")
                    + $" and this app would {(plan.MovesOtherClasses ? "withhold" : "offer")} it — "
                    + $"{plan.Insertion.Renames.Count} renames, {plan.Insertion.Moves.Count} date moves.");

                // And the copy really is hidden, whatever the source was.
                if (doc["duplication"]!["forcedUnpublished"]!["value"]!.GetValue<bool>())
                {
                    workspace.ApplyDuplicateClass(plan);
                    string copy = File.ReadAllText(Path.Combine(classesDir, plan.NewTitle + ".md"));
                    Assert.True(Plantoir.Core.Models.PageFrontmatter.IsDraft(copy, 1),
                                $"“{name}”: the copy of a published lesson is visible to students.");
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
                if (c["scheme"] is not null) continue;   // the numbered cases run below, in a club
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

    /// <summary>
    /// The numbered refusals (#274): numbers start at 1, and a numbered course
    /// refuses "start a new unit" and "add days to Unit 1" with
    /// <c>noUnitsInANumberedCourse</c> BEFORE the dates are asked for — so the
    /// scratch club has NO timetable, and the refusal must still be that one.
    /// </summary>
    [Fact]
    public void Refusals_InANumberedCourse_MatchContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["refusals"]!["cases"]!.AsArray().Where(c => c?["scheme"] is not null).ToList();
        Assert.Equal(3, cases.Count);

        foreach (var c in cases)
        {
            string folder = Directory.CreateTempSubdirectory("contract-refuse-numbered").FullName;
            try
            {
                var naming = NamingOf(c!, "word");
                var week1 = new JsonArray(new JsonObject { ["title"] = naming.Title(1, 1), ["date"] = "2026-09-08" });
                string expected = c!["expectProblem"]!.ToString();
                var workspace = ScratchCourse(folder, naming, week1,
                    expected == "noUnitsInANumberedCourse" ? null : new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10) });

                AssistRefusal refusal = c["startANewUnit"]?.GetValue<bool>() == true
                    ? Assert.Throws<AssistRefusal>(() => workspace.PlanAddNextClass("ICS3U", 1, "next"))
                    : c["addDaysToUnit"] is { } toUnit
                        ? Assert.Throws<AssistRefusal>(() => workspace.PlanAddNextClass(
                            "ICS3U", 1, toUnit.ToString(), c["count"]!.GetValue<int>()))
                        : Assert.Throws<AssistRefusal>(() => workspace.PlanInsertClasses(
                            "ICS3U", 1, 1, c["insertAtNumber"]!.GetValue<int>(), c["count"]!.GetValue<int>()));

                if (expected == "noUnitsInANumberedCourse")
                    Assert.Equal(NextClassPlanner.NoUnitsInANumberedCourse("ICS3U", naming.Word), refusal.Message);
            }
            finally { try { Directory.Delete(folder, recursive: true); } catch { } }
        }
    }

    /// <summary>
    /// <c>wholeUnit</c> (#274): which request names a WHOLE unit. The critical
    /// case is "Week 1" in a numbered course → null, or "publish Week 1"
    /// publishes every meeting.
    /// </summary>
    [Fact]
    public void WholeUnit_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["wholeUnit"]!["cases"]!.AsArray();
        Assert.Equal(8, cases.Count);
        foreach (var c in cases)
        {
            var naming = NamingOf(c!, "term");
            int? expect = c!["expectUnit"]?.GetValue<int>();
            Assert.True(expect == PublishPlan.UnitNamed(c["title"]!.ToString(), naming),
                $"wholeUnit “{c["title"]}” ({naming.Scheme}, {naming.Word}): expected {expect?.ToString() ?? "null"}.");
        }
    }

    /// <summary><c>insertion.numberedPosition</c>: the frozen unit/atDay read into one number.</summary>
    [Fact]
    public void NumberedPosition_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        foreach (var c in doc["insertion"]!["numberedPosition"]!["cases"]!.AsArray())
        {
            int? unit = c!["unit"]?.GetValue<int>();
            int? atDay = c["atDay"]?.GetValue<int>();
            Assert.Equal(c["expect"]?.GetValue<int>(), AssistWorkspace.NumberedPosition(unit, atDay));
        }
    }

    /// <summary>
    /// <c>insertion.positionInSentences</c> (#268): the make-room plan and reply
    /// name the position the way the course names a page, through the real
    /// plan's <c>PositionTitle</c> and the two sentences built from it.
    /// </summary>
    [Fact]
    public void PositionInSentences_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        foreach (var c in doc["insertion"]!["positionInSentences"]!["cases"]!.AsArray())
        {
            var naming = NamingOf(c!, "term");
            var plan = new InsertPlan
            {
                CourseCode = "ICS3U", SectionNumber = 1, Naming = naming,
                Unit = c!["unit"]!.GetValue<int>(), AtDay = c["atDay"]!.GetValue<int>(),
                Added = new[] { new NewClass("x", "x.md", new DateOnly(2026, 9, 8), 1) },
                Renames = Array.Empty<Rename>(), Moves = Array.Empty<DateMove>(), LinksToRewrite = 0,
                Problems = Array.Empty<string>(),
            };
            string position = c["position"]!.ToString();
            Assert.Equal(position, plan.PositionTitle);
            Assert.Contains($" at {position} in ICS3U Section 1.", plan.Describe());
            Assert.Contains($" at {position}.", AssistWording.MadeRoom(1, plan.PositionTitle));
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
