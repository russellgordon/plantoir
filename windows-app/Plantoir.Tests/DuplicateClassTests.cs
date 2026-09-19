using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// "Duplicate Unit 3, Day 2 as my next class" — a sentence the prompt shelf
/// OFFERS and the contract pins, which until 2026-09-18 made a blank page.
///
/// <para>The argument was dropped by the MCP binder because
/// <c>add_next_class</c> did not declare it, so the request ran as though the
/// teacher had said "add the next class": an empty skeleton where they asked
/// for a copy of a lesson, and nothing anywhere reporting a fault. Issue
/// #149.</para>
///
/// <para>Two things are worth stating before reading the cases. The copy
/// becomes the SOURCE'S next day rather than landing after the last class of
/// the course — everything from there on shuffles, which is
/// <c>PlanInsertClasses</c>' job. And it starts HIDDEN however the source was,
/// because a page made by duplicating a published lesson is a draft of next
/// week's.</para>
/// </summary>
public sealed class DuplicateClassTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(),
        "plantoir-duplicate-" + Guid.NewGuid().ToString("N"));
    private readonly FakeLauncher _launcher = new();
    private readonly UndoHistory _history = new();

    public DuplicateClassTests()
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

    private AssistWorkspace Open() => new(_folder, _launcher, undo: _history);

    private string ClassPath(string title) =>
        Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", title + ".md");

    private void Write(string title, string text) => File.WriteAllText(ClassPath(title), text);

    /// <summary>A published lesson with real content in it.</summary>
    private void Lesson(string title, string date, string body = "The lesson.\n") =>
        Write(title, $"---\ntitle: {title}\npublish: true\ncreated: {date}T07:00:00.000-0400\n" +
                     $"tags:\n  - unit-1\n---\n\n{body}");

    /// <summary>Four classes: Unit 1 Days 1–2, Unit 2 Days 1–2, on consecutive meeting days.</summary>
    private void FourClasses()
    {
        var dates = new[] { "2026-09-08", "2026-09-10", "2026-09-12", "2026-09-14" };
        string[] titles = ["Unit 1, Day 1", "Unit 1, Day 2", "Unit 2, Day 1", "Unit 2, Day 2"];
        for (int i = 0; i < titles.Length; i++) Lesson(titles[i], dates[i], $"Body of {titles[i]}.\n");
    }

    // ---- Where the copy lands ---------------------------------------------

    [Fact]
    public void TheCopyBecomesTheSourcesOwnNextDay()
    {
        // NOT a page after the last class of the course. "Duplicate Unit 1,
        // Day 1 as my next class" means tomorrow's lesson is a copy of that
        // one, so it becomes Unit 1, Day 2 and everything from there shuffles.
        FourClasses();
        var workspace = Open();

        var plan = workspace.PlanDuplicateClass("ICS3U", 1, "Unit 1, Day 1");

        Assert.Equal("Unit 1, Day 2", plan.NewTitle);
        Assert.Equal(new DateOnly(2026, 9, 10), plan.NewDate);
        Assert.Equal(new[] { "Unit 1, Day 2 → Unit 1, Day 3" },
                     plan.Insertion.Renames.Select(r => $"{r.From} → {r.To}"));
    }

    [Fact]
    public void TheBodyIsCopiedWordForWordUnderTheNewTitleAndDate()
    {
        FourClasses();
        Lesson("Unit 2, Day 2", "2026-09-14", "## Agenda\n\n1. The thing we did.\n\nSee [[Unit 1, Day 1]].\n");
        var workspace = Open();

        workspace.ApplyDuplicateClass(workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2"));

        string copy = File.ReadAllText(ClassPath("Unit 2, Day 3"));
        Assert.Contains("1. The thing we did.", copy);
        Assert.Contains("See [[Unit 1, Day 1]].", copy);
        Assert.Contains("title: Unit 2, Day 3", copy);
        Assert.Contains("created: 2026-09-16", copy);
        // The source is untouched — it is still there, still published.
        Assert.Contains("publish: true", File.ReadAllText(ClassPath("Unit 2, Day 2")));
    }

    // ---- Hidden, however the source was ------------------------------------

    [Fact]
    public void ACopyOfAPublishedLessonStartsHidden()
    {
        FourClasses();
        var workspace = Open();

        workspace.ApplyDuplicateClass(workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2"));

        string copy = File.ReadAllText(ClassPath("Unit 2, Day 3"));
        Assert.True(PageFrontmatter.IsDraft(copy, 1));
        // The KEY, not only the answer. The per-section guard below would
        // hide the page even with this write missing, by adding a
        // publishForSection1 that a section-local page has no business
        // carrying — so asserting only "is it hidden" leaves the ordinary
        // path untested, which a mutation run proved.
        Assert.Contains("publish: false", copy);
        Assert.DoesNotContain("publishForSection1", copy);
    }

    [Fact]
    public void ASourceWithTheLegacyDraftKeyGivesAHiddenCopy()
    {
        // draft: false is the old spelling of publish: true, read but never
        // written. The copy migrates to the new key AND is hidden.
        FourClasses();
        Write("Unit 2, Day 2",
              "---\ntitle: Unit 2, Day 2\ndraft: false\ncreated: 2026-09-14T07:00:00.000-0400\n---\nOld page.\n");
        var workspace = Open();

        workspace.ApplyDuplicateClass(workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2"));

        string copy = File.ReadAllText(ClassPath("Unit 2, Day 3"));
        Assert.True(PageFrontmatter.IsDraft(copy, 1));
        Assert.Contains("publish: false", copy);
        Assert.DoesNotContain("draft:", copy);
    }

    [Fact]
    public void ASourceWithNoFrontmatterAtAllGivesAHiddenCopy()
    {
        FourClasses();
        Write("Unit 2, Day 2", "Just words, no frontmatter at all.\n");
        var workspace = Open();

        workspace.ApplyDuplicateClass(workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2"));

        string copy = File.ReadAllText(ClassPath("Unit 2, Day 3"));
        Assert.True(PageFrontmatter.IsDraft(copy, 1));
        Assert.Contains("Just words, no frontmatter at all.", copy);
    }

    [Fact]
    public void ASourceWrittenWithWindowsLineEndingsKeepsThem()
    {
        FourClasses();
        Write("Unit 2, Day 2",
              "---\r\ntitle: Unit 2, Day 2\r\npublish: true\r\ncreated: 2026-09-14T07:00:00.000-0400\r\n---\r\nBody.\r\n");
        var workspace = Open();

        workspace.ApplyDuplicateClass(workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2"));

        string copy = File.ReadAllText(ClassPath("Unit 2, Day 3"));
        Assert.True(PageFrontmatter.IsDraft(copy, 1));
        Assert.Contains("publish: false\r\n", copy);
        Assert.Contains("title: Unit 2, Day 3\r\n", copy);
    }

    [Fact]
    public void APerSectionPublishKeyRidingAlongCannotMakeTheCopyVisible()
    {
        // The hole worth guarding. A page carrying publishForSection1: true
        // beats the plain publish: false the copy is given
        // (PageFrontmatter.IsDraft reads the per-section key FIRST), so a copy
        // of a page that had one would appear on the site the instant it was
        // made — the one thing duplicating must never do.
        FourClasses();
        Write("Unit 2, Day 2",
              "---\ntitle: Unit 2, Day 2\npublishForSection1: true\ncreated: 2026-09-14T07:00:00.000-0400\n---\nShared.\n");
        var workspace = Open();

        workspace.ApplyDuplicateClass(workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2"));

        string copy = File.ReadAllText(ClassPath("Unit 2, Day 3"));
        Assert.True(PageFrontmatter.IsDraft(copy, 1));
        Assert.Contains("publishForSection1: false", copy);
    }

    // ---- Undo, and when it is deliberately not offered ---------------------

    [Fact]
    public void DuplicatingTheLastClassOfTheCourseCanBeUndone()
    {
        // Nothing else moves, so taking it back is whole rather than partial.
        FourClasses();
        var workspace = Open();

        var result = workspace.ApplyDuplicateClass(
            workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2"));

        var entry = Assert.Single(_history.Entries);
        Assert.Equal("duplicated “Unit 2, Day 2” as “Unit 2, Day 3”", entry.Description);
        Assert.Contains(AssistWording.ACreatedPageCanBeTakenBack, result.Message);

        var undone = _history.Undo();

        Assert.True(undone.Succeeded);
        Assert.Empty(undone.Skipped);
        Assert.False(File.Exists(ClassPath("Unit 2, Day 3")));
    }

    [Fact]
    public void ALaterUnitMovingItsDatesIsEnoughToWithholdTheUndo()
    {
        // THE case the mac gets wrong. Duplicating the last day of a unit
        // renames NOTHING — renames happen only within the unit being changed
        // — while every class of every later unit is re-dated. The mac keys
        // its undo on `renames.isEmpty` alone, so it offers an undo that takes
        // back the copy and leaves the rest of the year moved. Windows counts
        // date moves too.
        FourClasses();
        var workspace = Open();

        var plan = workspace.PlanDuplicateClass("ICS3U", 1, "Unit 1, Day 2");

        Assert.Empty(plan.Insertion.Renames);
        Assert.NotEmpty(plan.Insertion.Moves);
        Assert.True(plan.MovesOtherClasses);

        var result = workspace.ApplyDuplicateClass(plan);

        Assert.Empty(_history.Entries);
        Assert.Contains("will not take this back", result.Message);
        Assert.Contains(Path.GetFileName(result.BackupPath!), result.Message);
        Assert.DoesNotContain(AssistWording.ACreatedPageCanBeTakenBack, result.Message);
    }

    [Fact]
    public void WhenClassesAreRenamedTheUndoIsWithheldAndTheBackupIsNamed()
    {
        FourClasses();
        var workspace = Open();

        var result = workspace.ApplyDuplicateClass(
            workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 1"));

        Assert.Empty(_history.Entries);
        Assert.True(File.Exists(ClassPath("Unit 2, Day 3")));     // the old Day 2, renamed
        Assert.Contains("will not take this back", result.Message);
    }

    // ---- Refusals ----------------------------------------------------------

    [Fact]
    public void APageThatIsNotANumberedClassCannotBecomeTheNextDay()
    {
        FourClasses();
        Lesson("Field Trip", "2026-09-16", "Out for the day.\n");

        var refusal = Assert.Throws<AssistRefusal>(
            () => Open().PlanDuplicateClass("ICS3U", 1, "Field Trip"));

        Assert.Equal(ClassChangeWording.NotANumberedClassPage("Field Trip", "Unit"), refusal.Message);
    }

    [Fact]
    public void APageThatIsNotThereIsRefusedInTheWordsEveryOtherToolUses()
    {
        FourClasses();

        var refusal = Assert.Throws<AssistRefusal>(
            () => Open().PlanDuplicateClass("ICS3U", 1, "Unit 9, Day 9"));

        // The SAME sentence AssistWorkspace.Page gives everywhere else. A
        // second phrasing for one fact is how two wordings for one thing
        // start.
        Assert.Contains("There’s no page called “Unit 9, Day 9”", refusal.Message);
    }

    [Fact]
    public void ATimetableWithNoDayLeftRefusesRatherThanInventingOne()
    {
        FourClasses();
        TimetableMemory.Write(_folder, "ICS3U", 1,
            new[] { "2026-09-08", "2026-09-10", "2026-09-12", "2026-09-14" }.Select(DateOnly.Parse),
            "block H", new DateOnly(2026, 8, 14));

        var refusal = Assert.Throws<AssistRefusal>(
            () => Open().PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2"));

        Assert.Contains("class date", refusal.Message);
    }

    [Fact]
    public void WithoutATimetableItAsksForTheClassDates()
    {
        FourClasses();
        File.Delete(Path.Combine(_folder, "courses", "ICS3U", ".internal", "timetable", "section1.json"));

        var refusal = Assert.Throws<AssistRefusal>(
            () => Open().PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2"));

        Assert.Contains("remember_timetable", refusal.Message);
    }

    [Fact]
    public void ALessonStillSittingWhereTheCopyWouldGoIsNeverWrittenOver()
    {
        // ApplyInsertClasses SKIPS a rename whose destination already exists
        // rather than overwriting it — right in itself, but it leaves the page
        // the copy was meant to become holding a real class. The plan may be
        // minutes old and Obsidian is open in the other window, so this is
        // reachable rather than theoretical, and writing the copy there would
        // destroy a lesson.
        FourClasses();
        var workspace = Open();
        var plan = workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 1");

        // Between the plan and the apply, the teacher makes Unit 2, Day 3 —
        // so the rename that was to vacate Unit 2, Day 2 cannot happen.
        Lesson("Unit 2, Day 3", "2026-09-16", "A lesson written in Obsidian just now.\n");

        var refusal = Assert.Throws<AssistRefusal>(() => workspace.ApplyDuplicateClass(plan));

        Assert.Contains("will not write over a lesson", refusal.Message);
        Assert.Contains("Body of Unit 2, Day 2.", File.ReadAllText(ClassPath("Unit 2, Day 2")));
        Assert.Contains("written in Obsidian just now", File.ReadAllText(ClassPath("Unit 2, Day 3")));
        // And nothing half-recorded is left open to swallow the next change.
        Assert.Empty(_history.Entries);
    }

    // ---- What the teacher agrees to, and what they are told afterwards -----

    [Fact]
    public void ThePlanNamesThePageTheTitleTheDateAndThatItStartsHidden()
    {
        FourClasses();

        string described = Open().PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2").Describe();

        Assert.Contains("“Unit 2, Day 2” would be copied to “Unit 2, Day 3”", described);
        Assert.Contains("2026-09-16", described);
        Assert.Contains(ClassChangeWording.TheCopyStartsHidden, described);
    }

    [Fact]
    public void ThePlanSaysHowManyClassesMoveEvenWhenNothingIsRenamed()
    {
        // The half the mac's plan is silent about: duplicating the last day of
        // a unit renames nothing and re-dates every later unit, so a teacher
        // reading "renames: none" would agree to a plan much smaller than what
        // runs.
        FourClasses();

        var plan = Open().PlanDuplicateClass("ICS3U", 1, "Unit 1, Day 2");
        string described = plan.Describe();

        Assert.Empty(plan.Insertion.Renames);
        Assert.Equal(2, plan.OtherClassesMoving);
        Assert.Contains("2 later classes move onto a later class day", described);
        Assert.Contains("Their names do not change", described);
    }

    [Fact]
    public void ThePlanSaysTheLinksAreFollowedWhenPagesAreRenamed()
    {
        FourClasses();

        string described = Open().PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 1").Describe();

        Assert.Contains("a day along to make room", described);
        Assert.Contains("links that point at them are rewritten", described);
    }

    [Fact]
    public void TheReplySaysWhatWasCopiedWhereAndThatNobodyCanSeeItYet()
    {
        FourClasses();
        var workspace = Open();

        var result = workspace.ApplyDuplicateClass(
            workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 2"));

        Assert.StartsWith(
            ClassChangeWording.CopiedTo("Unit 2, Day 2", "Unit 2, Day 3", new DateOnly(2026, 9, 16)),
            result.Message);
    }

    // ---- Through the tool the card actually calls --------------------------

    [Fact]
    public void TheFixedPhrasingFillsTheArgumentAndBothHalvesOfTheToolTakeIt()
    {
        // The defect in one line: the card sets `duplicate`, and before this
        // the binder dropped it because neither half declared it.
        var matched = AssistCardCommand.Matching("Duplicate Unit 3, Day 2 as my next class.");

        Assert.NotNull(matched);
        Assert.Equal("add_next_class", matched.ToolName);
        Assert.Equal("Unit 3, Day 2", matched.Arguments["duplicate"]);

        foreach (string tool in new[] { "AddNextClass", "PlanAddNextClass" })
            Assert.Contains(typeof(Plantoir.Mcp.PlantoirTools).GetMethod(tool)!.GetParameters(),
                            p => p.Name == "duplicate");
    }

    [Fact]
    public void ThePlanTwinProposesTheCopyRatherThanAnOrdinaryNextClass()
    {
        // Plan mode is ON unless a teacher turned it off, so the card's
        // arguments reach the TWIN first. A twin that could not see
        // `duplicate` would propose "Unit 2, Day 3, a blank page" and the
        // teacher would press Go on something other than what runs.
        FourClasses();

        var proposed = new Plantoir.Mcp.PlantoirTools(Open())
            .PlanAddNextClass("ICS3U", 1, duplicate: "Unit 2, Day 2");

        Assert.Equal(true, proposed.Meta?[AssistToolAnswer.IsPlanKey]?.GetValue<bool>());
        Assert.Contains("would be copied to “Unit 2, Day 3”", proposed.Summary());
        // Nothing was written.
        Assert.False(File.Exists(ClassPath("Unit 2, Day 3")));
    }

    [Fact]
    public void TheToolMakesTheCopyAndSaysSoInOneLine()
    {
        FourClasses();

        var answer = new Plantoir.Mcp.PlantoirTools(Open())
            .AddNextClass("ICS3U", 1, duplicate: "Unit 2, Day 2");

        Assert.Equal(ClassChangeWording.Duplicated("Unit 2, Day 2", "Unit 2, Day 3"), answer.Summary());
        Assert.Contains("Body of Unit 2, Day 2.", File.ReadAllText(ClassPath("Unit 2, Day 3")));
    }

    [Fact]
    public void ARefusalFromTheTwinIsAnAnswerAndIsNeverOfferedForApproval()
    {
        FourClasses();

        var refused = new Plantoir.Mcp.PlantoirTools(Open())
            .PlanAddNextClass("ICS3U", 1, duplicate: "Unit 9, Day 9");

        Assert.Null(refused.Meta?[AssistToolAnswer.IsPlanKey]);
        Assert.Contains("There’s no page called", refused.Summary());
    }

    [Fact]
    public void WithoutTheArgumentTheToolStillAddsAnOrdinaryBlankNextClass()
    {
        // The branch must not swallow the tool's original job.
        FourClasses();

        new Plantoir.Mcp.PlantoirTools(Open()).AddNextClass("ICS3U", 1);

        string created = File.ReadAllText(ClassPath("Unit 2, Day 3"));
        Assert.Contains("## Agenda", created);
        Assert.DoesNotContain("Body of Unit 2, Day 2.", created);
    }
}
