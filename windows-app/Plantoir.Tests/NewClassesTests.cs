using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// Laying down the class pages for a unit nobody has written yet, on the days
/// the section actually meets.
/// </summary>
public sealed class NewClassesTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(),
        "plantoir-newclasses-" + Guid.NewGuid().ToString("N"));
    private readonly FakeLauncher _launcher = new();

    public NewClassesTests()
    {
        Directory.CreateDirectory(Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes"));
        // What makes a folder a Plantoir working folder, as far as the
        // workspace is concerned.
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
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private AssistWorkspace Open() => new(_folder, _launcher);

    private static readonly DateOnly Today = new(2026, 8, 14);

    /// <summary>Ten meeting dates, every second day from 8 September.</summary>
    private void RememberTenDates() =>
        TimetableMemory.Write(_folder, "ICS3U", 1,
            Enumerable.Range(0, 10).Select(i => new DateOnly(2026, 9, 8).AddDays(i * 2)),
            "block H", Today);

    private string ClassPath(string title) =>
        Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", title + ".md");

    /// <summary>A class page already on disk, dated, shown to students or not.</summary>
    private void Written(string title, string date, bool published) =>
        File.WriteAllText(ClassPath(title),
            $"---\ntitle: {title}\npublish: {(published ? "true" : "false")}\n" +
            $"created: {date}T07:00:00.000-0400\n---\nBody.\n");

    // ---- Refusing for a good reason --------------------------------------

    [Fact]
    public void WithoutATimetableItAsksForOneRatherThanGuessing()
    {
        var refusal = Assert.Throws<AssistRefusal>(() => Open().PlanAddClasses("ICS3U", 1, 2, 1, 3));

        // Inventing dates for a class it knows nothing about is the one thing
        // it must not do — a whole unit landing on the wrong days is worse
        // than being asked a question.
        Assert.Contains("ICS3U Section 1", refusal.Message);
        Assert.Contains(AssistWording.MayIAskForYourDates, refusal.Message);
    }

    // ---- Dating from the section's own timetable --------------------------

    [Fact]
    public void ClassesLandOnTheDaysTheSectionActuallyMeets()
    {
        RememberTenDates();

        var plan = Open().PlanAddClasses("ICS3U", 1, 2, firstDay: 1, count: 3);

        Assert.Equal(3, plan.Classes.Count);
        Assert.Equal(new DateOnly(2026, 9, 8), plan.Classes[0].Date);
        Assert.Equal(new DateOnly(2026, 9, 10), plan.Classes[1].Date);
        Assert.Equal(new DateOnly(2026, 9, 12), plan.Classes[2].Date);
        Assert.Equal("Unit 2, Day 1", plan.Classes[0].Title);
        Assert.Equal("Unit 2, Day 3", plan.Classes[2].Title);
    }

    [Fact]
    public void DatesAlreadySpokenForAreSkipped()
    {
        RememberTenDates();
        // A class already sits on the 8th and the 10th.
        File.WriteAllText(ClassPath("Unit 1, Day 1"),
            "---\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\nBody.\n");
        File.WriteAllText(ClassPath("Unit 1, Day 2"),
            "---\npublish: true\ncreated: 2026-09-10T07:00:00.000-0400\n---\nBody.\n");

        var plan = Open().PlanAddClasses("ICS3U", 1, 2, firstDay: 1, count: 2);

        // So the new unit starts on the 12th, not back at the start of term.
        Assert.Equal(new DateOnly(2026, 9, 12), plan.Classes[0].Date);
        Assert.Equal(new DateOnly(2026, 9, 14), plan.Classes[1].Date);
    }

    [Fact]
    public void ADayRangeCanStartPartWayThroughAUnit()
    {
        RememberTenDates();

        // "Add Unit 2 Days 4 through 6" — the first three already exist
        // elsewhere in the teacher's head, or are being written by hand.
        var plan = Open().PlanAddClasses("ICS3U", 1, 2, firstDay: 4, count: 3);

        Assert.Equal(new[] { "Unit 2, Day 4", "Unit 2, Day 5", "Unit 2, Day 6" },
                     plan.Classes.Select(c => c.Title));
    }

    // ---- Never writing over a teacher's work ------------------------------

    [Fact]
    public void AnExistingPageIsLeftAloneAndSaidSo()
    {
        RememberTenDates();
        File.WriteAllText(ClassPath("Unit 2, Day 2"), "---\npublish: true\n---\nA real lesson.\n");

        var plan = Open().PlanAddClasses("ICS3U", 1, 2, firstDay: 1, count: 3);

        Assert.Equal(new[] { "Unit 2, Day 1", "Unit 2, Day 3" }, plan.Classes.Select(c => c.Title));
        Assert.Equal("Unit 2, Day 2", Assert.Single(plan.AlreadyThere));
        Assert.Contains("already exist", plan.Describe());
    }

    [Fact]
    public async Task ApplyingNeverOverwrites()
    {
        RememberTenDates();
        var workspace = Open();
        var plan = workspace.PlanAddClasses("ICS3U", 1, 2, firstDay: 1, count: 2);

        // The page appears between planning and applying, as a teacher typing
        // in Obsidian could easily manage.
        File.WriteAllText(ClassPath("Unit 2, Day 1"), "Written by hand.");
        workspace.ApplyAddClasses(plan);

        Assert.Equal("Written by hand.", await File.ReadAllTextAsync(ClassPath("Unit 2, Day 1")));
    }

    // ---- Running out of dates --------------------------------------------

    [Fact]
    public void AskingForMoreClassesThanThereAreDaysSaysSo()
    {
        TimetableMemory.Write(_folder, "ICS3U", 1,
            new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10) }, "block H", Today);

        var plan = Open().PlanAddClasses("ICS3U", 1, 2, firstDay: 1, count: 5);

        // What it CAN do, it plans; overflow classes land on the final date
        Assert.Equal(5, plan.Classes.Count);
        Assert.Equal(3, plan.SharingTheLastDay);
        Assert.Equal(new DateOnly(2026, 9, 10), plan.Classes[2].Date);
        Assert.Equal(new DateOnly(2026, 9, 10), plan.Classes[3].Date);
        Assert.Equal(new DateOnly(2026, 9, 10), plan.Classes[4].Date);
        Assert.Contains("share", plan.Describe());
        Assert.Equal(0, plan.SpareDatesLeft);
    }

    // ---- What gets written ------------------------------------------------

    [Fact]
    public void TheNewPagesFollowTheShapeEveryClassPageTakes()
    {
        RememberTenDates();
        // An existing class fixes the time of day and the offset.
        File.WriteAllText(ClassPath("Unit 1, Day 1"),
            "---\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\nBody.\n");

        var workspace = Open();
        var plan = workspace.PlanAddClasses("ICS3U", 1, 3, firstDay: 1, count: 2);
        var result = workspace.ApplyAddClasses(plan);

        Assert.True(result.Succeeded);
        string page = File.ReadAllText(ClassPath("Unit 3, Day 1"));

        Assert.Contains("title: Unit 3, Day 1", page);
        Assert.Contains("transcludeTitleSize: h2", page);
        Assert.Contains("enableToc: false", page);
        Assert.Contains("excludeBacklinks: true", page);
        Assert.Contains("  - unit-3", page);
        Assert.Contains("## Agenda", page);
        Assert.Contains("## Things to do before our next class", page);

        // The section's own time of day, so it sorts beside its siblings
        // rather than at midnight.
        Assert.Contains("created: 2026-09-10T07:00:00.000-0400", page);
    }

    [Fact]
    public void NewPagesStartUnpublished()
    {
        RememberTenDates();
        var workspace = Open();
        var plan = workspace.PlanAddClasses("ICS3U", 1, 2, firstDay: 1, count: 1);
        workspace.ApplyAddClasses(plan);

        // A page nobody has written has no business in the site. The plan
        // says so too, because a teacher who cannot find their new pages in
        // the preview will reasonably think this went wrong.
        Assert.Contains("publish: false", File.ReadAllText(ClassPath("Unit 2, Day 1")));
        Assert.Contains("They start unpublished", plan.Describe());
    }

    [Fact]
    public void ApplyingBacksUpFirst()
    {
        RememberTenDates();
        var workspace = Open();
        var plan = workspace.PlanAddClasses("ICS3U", 1, 2, firstDay: 1, count: 2);

        var result = workspace.ApplyAddClasses(plan);

        Assert.NotNull(result.BackupPath);
        Assert.True(File.Exists(result.BackupPath));
    }

    [Fact]
    public void ThePlanNamesEveryPageAndItsDay()
    {
        RememberTenDates();
        string described = Open().PlanAddClasses("ICS3U", 1, 4, firstDay: 1, count: 2).Describe();

        Assert.Contains("Add 2 class pages to Unit 4 of ICS3U Section 1", described);
        Assert.Contains("Unit 4, Day 1  (2026-09-08 Tuesday)", described);
        Assert.Contains("8 more class dates are spare", described);
    }

    [Fact]
    public void NonsenseIsRefusedBeforeAnythingIsRead()
    {
        RememberTenDates();
        Assert.Contains("unit number starts at 1",
            Assert.Throws<AssistRefusal>(() => Open().PlanAddClasses("ICS3U", 1, 0, 1, 1)).Message);
        Assert.Contains("at least one class",
            Assert.Throws<AssistRefusal>(() => Open().PlanAddClasses("ICS3U", 1, 1, 1, 0)).Message);
    }

    // ---- Where a unit carries on from ------------------------------------

    /// <summary>
    /// Asking for five more days on a unit that already has three gives FIVE.
    /// </summary>
    /// <remarks>
    /// <para>The story behind dropping <c>add_classes</c>' <c>firstDay</c>
    /// argument (issue #70). It defaulted to 1 and was described as "1 unless
    /// the earlier days already exist" — a question the caller could only
    /// answer by going and looking. Left at its default this planned Days 1–5,
    /// reported three of them as already there, and created TWO pages for a
    /// teacher who asked for five.</para>
    ///
    /// <para>Counted from the pages on disk, published or NOT: a class a
    /// teacher has written and not yet shown anybody is still a day of the
    /// course, and numbering over it would collide with a real file.</para>
    /// </remarks>
    [Fact]
    public void AddingMoreDaysCarriesOnFromTheDaysTheUnitAlreadyHas()
    {
        RememberTenDates();
        Written("Unit 2, Day 1", "2026-09-08", published: true);
        Written("Unit 2, Day 2", "2026-09-10", published: true);
        Written("Unit 2, Day 3", "2026-09-12", published: false);   // written, not yet shown

        var workspace = Open();
        Assert.Equal(4, workspace.DayToCarryOnFrom("ICS3U", 1, unit: 2));

        var plan = workspace.PlanAddClasses("ICS3U", 1, 2,
            workspace.DayToCarryOnFrom("ICS3U", 1, unit: 2), count: 5);

        Assert.Equal(new[] { "Unit 2, Day 4", "Unit 2, Day 5", "Unit 2, Day 6",
                             "Unit 2, Day 7", "Unit 2, Day 8" },
                     plan.Classes.Select(c => c.Title));
        Assert.Empty(plan.AlreadyThere);
    }

    /// <summary>A unit with no pages yet starts at Day 1.</summary>
    [Fact]
    public void AUnitWithNoPagesStartsAtDayOne()
    {
        Written("Unit 2, Day 1", "2026-09-08", published: true);

        Assert.Equal(1, Open().DayToCarryOnFrom("ICS3U", 1, unit: 7));
    }
}
