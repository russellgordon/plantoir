using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// Making room part-way through a unit that is already built out — the change
/// that renames pages a teacher's links point at, and so the one that has to
/// say exactly what it will do before it does it.
/// </summary>
public sealed class InsertClassesTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(),
        "plantoir-insert-" + Guid.NewGuid().ToString("N"));
    private readonly FakeLauncher _launcher = new();

    public InsertClassesTests()
    {
        Directory.CreateDirectory(Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes"));
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "courses", "ICS3U", "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "Computer Science",
              "deploy_target": "netlify",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1]
            }
            """);

        TimetableMemory.Write(_folder, "ICS3U", 1,
            Enumerable.Range(0, 12).Select(i => new DateOnly(2026, 9, 8).AddDays(i * 2)),
            "block H", new DateOnly(2026, 8, 14));
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private AssistWorkspace Open() => new(_folder, _launcher);

    private string ClassPath(string title) =>
        Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", title + ".md");

    /// <summary>Four classes: Unit 1 Days 1-2, Unit 2 Days 1-2, on consecutive meeting days.</summary>
    private void FourClasses()
    {
        var dates = new[] { "2026-09-08", "2026-09-10", "2026-09-12", "2026-09-14" };
        string[] titles = ["Unit 1, Day 1", "Unit 1, Day 2", "Unit 2, Day 1", "Unit 2, Day 2"];
        for (int i = 0; i < titles.Length; i++)
            File.WriteAllText(ClassPath(titles[i]),
                $"---\ntitle: {titles[i]}\npublish: true\ncreated: {dates[i]}T07:00:00.000-0400\n---\nBody.\n");
    }

    // ---- Reaching it from a fixed phrasing --------------------------------

    /// <summary>
    /// The plan twin's answer is MARKED as a plan, so the window offers Go.
    /// </summary>
    /// <remarks>
    /// <para>This is the half a unit test could not see until it was asked to.
    /// <c>plan_make_room_for_classes</c> returned a bare string, and every
    /// caller that only reads the WORDS — Claude Code, and every test — was
    /// perfectly happy with it. Plantoir's own window is not:
    /// <c>AssistAgent.ShowPlan</c> reads an unmarked answer as a REFUSAL,
    /// prints it and never offers Go. So the moment "make room for a class at
    /// Unit 3, Day 4" became a fixed phrasing with a plan twin, the tool
    /// became unrunnable from the app — a plan a teacher could read and never
    /// accept, with nothing in any suite going red.</para>
    /// </remarks>
    [Fact]
    public void ThePlanTwinsAnswerIsMarkedAsAPlan()
    {
        FourClasses();

        var planned = new Plantoir.Mcp.PlantoirTools(Open())
            .PlanMakeRoomForClasses("ICS3U", 1, unit: 2, atDay: 1, howMany: 1);

        Assert.NotEqual(true, planned.IsError);
        Assert.Equal(true, planned.Meta?[AssistToolAnswer.IsPlanKey]?.GetValue<bool>());
    }

    /// <summary>
    /// A plan that would change NOTHING is an answer, not a proposal — and so
    /// is a REFUSAL. Both reach the window unmarked.
    /// </summary>
    /// <remarks>
    /// <para>"Shall I go ahead?" under an explanation of why nothing can be
    /// done invites a teacher to approve a dead end, so the mark is withheld
    /// and the window says the sentence instead of offering Go.</para>
    ///
    /// <para>The two arrive by different routes and both are checked, because
    /// the first version of this test only THOUGHT it covered the first one: a
    /// section with no classes throws <c>AssistRefusal</c> long before a plan
    /// exists, so it was exercising the refusal path under the other one's
    /// name. Emptying the timetable instead is what actually reaches
    /// <c>InsertPlan.ChangesNothing</c> — every later class has to move onto a
    /// later meeting day, and there are none left to move onto.</para>
    /// </remarks>
    [Fact]
    public void NeitherARefusalNorANoOpIsOfferedForApproval()
    {
        var tools = new Plantoir.Mcp.PlantoirTools(Open());

        // A REFUSAL: no pages named "Unit N, Day N", so there is nothing to
        // make room in.
        var refused = tools.PlanMakeRoomForClasses("ICS3U", 1, unit: 2, atDay: 1, howMany: 1);
        Assert.Null(refused.Meta?[AssistToolAnswer.IsPlanKey]);

        // A NO-OP: four classes and exactly four class days, so the class that
        // would be pushed along has nowhere to go and the plan adds, renames
        // and moves nothing.
        FourClasses();
        TimetableMemory.Write(_folder, "ICS3U", 1,
            new[] { "2026-09-08", "2026-09-10", "2026-09-12", "2026-09-14" }
                .Select(DateOnly.Parse),
            "block H", new DateOnly(2026, 8, 14));

        var noop = new Plantoir.Mcp.PlantoirTools(Open())
            .PlanMakeRoomForClasses("ICS3U", 1, unit: 2, atDay: 1, howMany: 1);

        Assert.Null(noop.Meta?[AssistToolAnswer.IsPlanKey]);
        Assert.Contains("Nothing would change", TextOf(noop));
    }

    private static string TextOf(ModelContextProtocol.Protocol.CallToolResult result) =>
        string.Join(" ", result.Content
            .OfType<ModelContextProtocol.Protocol.TextContentBlock>()
            .Select(block => block.Text));

    /// <summary>
    /// The fixed phrasing routes to the tool, fills the three numbers, and is
    /// gated behind the plan the teacher can still say no to.
    /// </summary>
    [Fact]
    public void TheFixedPhrasingCarriesTheNumbersAndIsGatedBehindItsPlan()
    {
        var matched = AssistCardCommand.Matching("Make room for a class at Unit 3, Day 4.");

        Assert.NotNull(matched);
        Assert.Equal("make_room_for_classes", matched.ToolName);
        Assert.Equal("3", matched.Arguments["unit"]);
        Assert.Equal("4", matched.Arguments["atDay"]);
        Assert.Equal("1", matched.Arguments["howMany"]);

        // Without this entry the riskiest tool on the surface would be the one
        // card that ran with nothing shown first.
        Assert.Equal("plan_make_room_for_classes", AssistAgent.PlanTwins["make_room_for_classes"]);
    }

    // ---- What it plans ----------------------------------------------------

    [Fact]
    public void LaterDaysOfTheSameUnitAreRenamed()
    {
        FourClasses();

        var plan = Open().PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1);

        // Unit 2 renumbers; Unit 1 is untouched.
        Assert.Equal(new[] { ("Unit 2, Day 2", "Unit 2, Day 3"), ("Unit 2, Day 1", "Unit 2, Day 2") },
                     plan.Renames.Select(r => (r.From, r.To)));
    }

    [Fact]
    public void RenamesRunHighestDayFirstSoTheyNeverCollide()
    {
        FourClasses();

        var plan = Open().PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1);

        // Renaming Day 1 -> Day 2 before Day 2 -> Day 3 would overwrite a
        // real lesson. Order is part of the plan, not an implementation detail.
        Assert.Equal("Unit 2, Day 2", plan.Renames[0].From);
    }

    [Fact]
    public void ALaterUnitKeepsItsNameButMovesToALaterDay()
    {
        FourClasses();

        var plan = Open().PlanInsertClasses("ICS3U", 1, unit: 1, atDay: 2, count: 1);

        // Unit 2's classes are still Unit 2's classes; they just happen later.
        Assert.DoesNotContain(plan.Renames, r => r.From.StartsWith("Unit 2"));
        Assert.Contains(plan.Moves, m => m.Title == "Unit 2, Day 1");
    }

    [Fact]
    public void ItCountsTheLinksThatWouldFollowARename()
    {
        FourClasses();
        File.WriteAllText(ClassPath("Unit 1, Day 1"),
            "---\ntitle: Unit 1, Day 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\n" +
            "See [[Unit 2, Day 2]] and again [[Unit 2, Day 2|the task day]].\n");

        var plan = Open().PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1);

        // The number a teacher cannot check without opening every page.
        Assert.Equal(2, plan.LinksToRewrite);
        Assert.Contains("2 links point at those names", plan.Describe());
    }

    [Fact]
    public void RunningOutOfClassDaysChangesNothingAndSaysHowManyAreNeeded()
    {
        FourClasses();
        TimetableMemory.Write(_folder, "ICS3U", 1,
            new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10),
                    new DateOnly(2026, 9, 12), new DateOnly(2026, 9, 14) },
            "block H", new DateOnly(2026, 8, 14));

        var plan = Open().PlanInsertClasses("ICS3U", 1, unit: 1, atDay: 1, count: 3);

        Assert.True(plan.ChangesNothing);
        Assert.Contains(plan.Problems, p => p.Contains("Add 3 more class dates"));
    }

    [Fact]
    public void PagesNotNamedUnitAndDayAreLeftAloneAndSaidSo()
    {
        FourClasses();
        File.WriteAllText(ClassPath("Field Trip"),
            "---\ntitle: Field Trip\npublish: true\ncreated: 2026-09-16T07:00:00.000-0400\n---\nOut.\n");

        var plan = Open().PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1);

        Assert.Contains(plan.Problems, p => p.Contains("not named"));
        Assert.DoesNotContain(plan.Renames, r => r.From == "Field Trip");
        Assert.DoesNotContain(plan.Moves, m => m.Title == "Field Trip");
    }

    // ---- What it does -----------------------------------------------------

    [Fact]
    public void ApplyingRenamesTheFilesAndTheirTitles()
    {
        FourClasses();
        var workspace = Open();
        var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1);

        workspace.ApplyInsertClasses(plan);

        Assert.True(File.Exists(ClassPath("Unit 2, Day 3")));
        // The title inside must follow the file name, or the site shows one
        // name and the sidebar another.
        Assert.Contains("title: Unit 2, Day 3", File.ReadAllText(ClassPath("Unit 2, Day 3")));
        Assert.Contains("title: Unit 2, Day 2", File.ReadAllText(ClassPath("Unit 2, Day 2")));
    }

    [Fact]
    public void ApplyingFollowsTheLinks()
    {
        FourClasses();
        File.WriteAllText(ClassPath("Unit 1, Day 1"),
            "---\ntitle: Unit 1, Day 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\n" +
            "Next: [[Unit 2, Day 2]] and ![[Unit 2, Day 2]] and [[Unit 2, Day 2|the task day]].\n");

        var workspace = Open();
        var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1);
        workspace.ApplyInsertClasses(plan);

        string text = File.ReadAllText(ClassPath("Unit 1, Day 1"));
        Assert.Contains("[[Unit 2, Day 3]]", text);
        Assert.Contains("![[Unit 2, Day 3]]", text);
        // The alias is the teacher's own words and stays exactly as written.
        Assert.Contains("[[Unit 2, Day 3|the task day]]", text);
        Assert.DoesNotContain("Unit 2, Day 2]]", text);
    }

    [Fact]
    public void EveryLinkFormObsidianWritesSurvivesTheRename()
    {
        // Obsidian rewrites links itself when IT does the rename — but this
        // rename happens on disk from another process, which Obsidian sees as
        // a delete and a create and leaves links alone, and it may not even be
        // running. So Plantoir has to handle every form Obsidian can write.
        FourClasses();
        File.WriteAllText(ClassPath("Unit 1, Day 1"),
            "---\ntitle: Unit 1, Day 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\n" +
            "Plain [[Unit 2, Day 2]]\n" +
            "Alias [[Unit 2, Day 2|the task day]]\n" +
            "Embed ![[Unit 2, Day 2]]\n" +
            "Heading [[Unit 2, Day 2#Agenda]]\n" +
            "Block [[Unit 2, Day 2#^abc123]]\n" +
            "Heading with alias [[Unit 2, Day 2#Agenda|what we did]]\n");

        var workspace = Open();
        var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1);
        workspace.ApplyInsertClasses(plan);

        string text = File.ReadAllText(ClassPath("Unit 1, Day 1"));
        Assert.Contains("Plain [[Unit 2, Day 3]]", text);
        Assert.Contains("Alias [[Unit 2, Day 3|the task day]]", text);
        Assert.Contains("Embed ![[Unit 2, Day 3]]", text);
        // The heading and block anchors point INSIDE the page and must survive
        // untouched — only the page name changed.
        Assert.Contains("Heading [[Unit 2, Day 3#Agenda]]", text);
        Assert.Contains("Block [[Unit 2, Day 3#^abc123]]", text);
        Assert.Contains("Heading with alias [[Unit 2, Day 3#Agenda|what we did]]", text);
        // And nothing still points at the old name.
        Assert.DoesNotContain("Unit 2, Day 2", text);
    }

    [Fact]
    public void ApplyingCreatesTheNewClassUnpublished()
    {
        FourClasses();
        var workspace = Open();
        var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1);

        workspace.ApplyInsertClasses(plan);

        string created = File.ReadAllText(ClassPath("Unit 2, Day 1"));
        Assert.Contains("publish: false", created);
        Assert.Contains("## Agenda", created);
    }

    [Fact]
    public void ApplyingMovesTheDatesOntoRealClassDays()
    {
        FourClasses();
        var workspace = Open();
        var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1);

        workspace.ApplyInsertClasses(plan);

        // The new class takes 12 September; what was there moves to the 14th
        // and the 16th — both real meeting days, not "the next day".
        Assert.Contains("created: 2026-09-12", File.ReadAllText(ClassPath("Unit 2, Day 1")));
        Assert.Contains("created: 2026-09-14", File.ReadAllText(ClassPath("Unit 2, Day 2")));
        Assert.Contains("created: 2026-09-16", File.ReadAllText(ClassPath("Unit 2, Day 3")));
        // And the classes before the insertion point never moved.
        Assert.Contains("created: 2026-09-08", File.ReadAllText(ClassPath("Unit 1, Day 1")));
    }

    [Fact]
    public void ApplyingBacksUpFirst()
    {
        FourClasses();
        var workspace = Open();
        var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1);

        var result = workspace.ApplyInsertClasses(plan);

        Assert.True(result.Succeeded);
        Assert.NotNull(result.BackupPath);
        Assert.True(File.Exists(result.BackupPath));
    }

    [Fact]
    public void WithoutATimetableItAsksRatherThanGuessing()
    {
        FourClasses();
        File.Delete(Path.Combine(_folder, "courses", "ICS3U", ".internal", "timetable", "section1.json"));

        var refusal = Assert.Throws<AssistRefusal>(
            () => Open().PlanInsertClasses("ICS3U", 1, 2, 1, 1));

        Assert.Contains("remember_timetable", refusal.Message);
    }
}
