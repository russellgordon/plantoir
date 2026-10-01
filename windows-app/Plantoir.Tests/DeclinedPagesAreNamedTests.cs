using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #308 (the mac's #186): a page whose settings have no column-0 place for a
/// new line is DECLINED by the writer — and every caller then NAMES it, on the
/// plan and in the reply, rather than promising it, counting it as done, or
/// answering "already hidden" about it. The trail records the count.
/// </summary>
/// <remarks>
/// The shape used throughout is the contract's own (<c>file-formats.json</c> →
/// <c>pageVisibility.writingCases</c>, <c>expectOutcome: noRoomForAKey</c>): a
/// settings block whose first line is indented, so a new key has nowhere to go.
/// </remarks>
[Collection(SharedActivityState.Name)]
public sealed class DeclinedPagesAreNamedTests : IDisposable
{
    private const string NoRoom = "---\n  a: 1\n---\nBody.\n";

    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-declined-" + Guid.NewGuid().ToString("N"));
    private readonly string _trail;
    private readonly FakeLauncher _launcher = new();

    public DeclinedPagesAreNamedTests()
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
        _trail = Path.Combine(_folder, "trail.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private AssistWorkspace Open() => new(_folder, _launcher);

    private string ClassPath(string title) =>
        Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", title + ".md");

    private void Class(string title, string date) =>
        File.WriteAllText(ClassPath(title), $"---\ntitle: {title}\npublish: true\ncreated: {date}T07:00:00.000-0400\n---\nBody.\n");

    private string TrailText => File.Exists(_trail) ? File.ReadAllText(_trail) : "";

    [Fact]
    public async Task HidingAPageWithNoRoomForAKeyNamesItOnThePlanAndInTheReplyAndWritesNothing()
    {
        Class("Unit 1, Day 1", "2026-09-08");
        File.WriteAllText(ClassPath("Unit 1, Day 2"), NoRoom);
        string sentence = AssistWording.PagesWhoseSettingsCannotBeAddedTo(new[] { "Unit 1, Day 2" });

        var workspace = Open();
        var plan = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" }, includeLinked: false, draft: true, publishes: false);

        Assert.Equal(new[] { "Unit 1, Day 2" }, plan.CannotBeAddedTo.Select(p => p.Title));
        Assert.Empty(plan.Changes);
        Assert.Null(plan.NothingToDoSentence);              // never "already hidden" about it
        Assert.Contains(sentence, plan.Describe());
        Assert.DoesNotContain("No page's visibility would change", plan.Describe());

        var result = await workspace.Apply(plan, preview: false);
        Assert.Equal(sentence, result.Message);
        Assert.Equal(NoRoom, File.ReadAllText(ClassPath("Unit 1, Day 2")));
        Assert.Contains(ActivityTrail.PageSettingsLeftAsTheyWereLine("hiding pages", 1), TrailText);
    }

    [Fact]
    public async Task APageThatCanBeWrittenIsWrittenAndTheDeclinedOneIsNamedBesideIt()
    {
        Class("Unit 1, Day 1", "2026-09-08");
        File.WriteAllText(ClassPath("Unit 1, Day 2"), NoRoom);

        var workspace = Open();
        var plan = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1", "Unit 1, Day 2" },
            includeLinked: false, draft: true, publishes: false);
        var result = await workspace.Apply(plan, preview: false);

        Assert.Contains("Unpublished “Unit 1, Day 1”.", result.Message);
        Assert.EndsWith(AssistWording.PagesWhoseSettingsCannotBeAddedTo(new[] { "Unit 1, Day 2" }), result.Message);
        Assert.True(Plantoir.Core.Models.PageFrontmatter.IsDraft(File.ReadAllText(ClassPath("Unit 1, Day 1")), 1));
    }

    [Fact]
    public async Task AWholeUnitNeverSaysAlreadyHiddenAboutPagesItDeclined()
    {
        File.WriteAllText(ClassPath("Unit 3, Day 1"), NoRoom);
        File.WriteAllText(ClassPath("Unit 3, Day 2"), NoRoom);
        string sentence = AssistWording.PagesWhoseSettingsCannotBeAddedTo(new[] { "Unit 3, Day 2", "Unit 3, Day 1" });

        var workspace = Open();
        var planned = workspace.PlanWholeUnit("ICS3U", 1, 3, publishing: false);
        Assert.Equal(0, planned.MovingCount);
        Assert.Equal(sentence, planned.AlreadyDoneSentence);

        var result = await workspace.ApplyWholeUnit("ICS3U", 1, 3, publishing: false, preview: false);
        Assert.Equal(sentence, result.Message);
        Assert.Equal(NoRoom, File.ReadAllText(ClassPath("Unit 3, Day 1")));
    }

    [Fact]
    public void ReDatingNamesTheClassItCouldNotDate()
    {
        Class("Unit 1, Day 1", "2026-09-01");
        File.WriteAllText(ClassPath("Unit 1, Day 2"), NoRoom);

        var workspace = Open();
        var remembered = TimetableMemory.Read(workspace.FolderPath, "ICS3U", 1)!;
        var plan = workspace.PlanReDate("ICS3U", 1, Timetable.FromDates(remembered.Dates, remembered.Source),
            Array.Empty<string>(), Array.Empty<int>());
        var result = workspace.ApplyReDate(plan);

        Assert.Contains(AssistWording.PageWhoseNewDateCouldNotBeSet("Unit 1, Day 2"), result.Message);
        Assert.Equal(NoRoom, File.ReadAllText(ClassPath("Unit 1, Day 2")));
        Assert.Contains(ActivityTrail.PageSettingsLeftAsTheyWereLine("re-dating classes", 1), TrailText);
    }

    [Fact]
    public void MakingRoomNamesTheClassItCouldNotDateByItsNewName()
    {
        Class("Unit 1, Day 1", "2026-09-08");
        Class("Unit 1, Day 2", "2026-09-10");
        File.WriteAllText(ClassPath("Unit 1, Day 3"), NoRoom);

        var workspace = Open();
        var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 1, atDay: 2, count: 1);
        var result = workspace.ApplyInsertClasses(plan);

        // Unit 1, Day 3 became Unit 1, Day 4 and could not be given a date.
        Assert.Contains(AssistWording.PageWhoseNewDateCouldNotBeSet("Unit 1, Day 4"), result.Message);
        Assert.Contains(ActivityTrail.PageSettingsLeftAsTheyWereLine("making room for a class", 1), TrailText);
    }

    /// <summary>
    /// Review N-a: a class the writer declines stays as it is, so the plan works
    /// the section's front page out from its CURRENT state. Measured here in the
    /// hide direction. The publish direction is reachable too (bundle 9 fix
    /// review, note 1: a section-local class page whose first settings line is
    /// indented and which carries a top-level <c>publishForSection1: false</c>
    /// reads certainly hidden, and publishing it is declined because its write
    /// key <c>publish</c> has nowhere to go); the same exclusion covers it, but
    /// no test here exercises it.
    /// </summary>
    [Fact]
    public void ADeclinedClassIsNeverPlannedOntoTheFrontPage()
    {
        Class("Unit 1, Day 1", "2026-09-08");
        // No top-level place for a new key (its first line is indented), but a
        // date this app reads, later than Day 1's.
        File.WriteAllText(ClassPath("Unit 1, Day 2"), "---\n  a: 1\ncreated: 2026-09-10T07:00:00.000-0400\n---\nBody.\n");
        File.WriteAllText(Path.Combine(_folder, "courses", "ICS3U", "section1", "index.md"),
            "---\ntitle: Home\n---\n# Most Recent Class\n![[Unit 1, Day 2]]\n");

        // A HIDE of the newest class, which the writer declines: Day 2 stays
        // visible, so the front page must not be planned back onto Day 1.
        var plan = Open().PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 2" }, includeLinked: false, draft: true, publishes: false);

        Assert.Equal(new[] { "Unit 1, Day 2" }, plan.CannotBeAddedTo.Select(p => p.Title));
        Assert.True(plan.Index is null || plan.Index.ToClass == "Unit 1, Day 2",
            $"the front page was planned away from a class that stays visible: {plan.Index?.Describe()}");
    }

    /// <summary>
    /// Review F1: "moved N onto later class days" counts what was WRITTEN, as
    /// the mac counts — never a class it declined or a write that failed.
    /// </summary>
    [Fact]
    public void MakingRoomCountsOnlyTheClassesItActuallyMoved()
    {
        Class("Unit 1, Day 1", "2026-09-08");
        Class("Unit 1, Day 2", "2026-09-10");
        File.WriteAllText(ClassPath("Unit 1, Day 3"), NoRoom);       // declined at the write
        Class("Unit 2, Day 1", "2026-09-14");
        string locked = ClassPath("Unit 2, Day 1");
        File.SetAttributes(locked, FileAttributes.ReadOnly);         // its write fails
        try
        {
            var workspace = Open();
            var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 1, atDay: 2, count: 1);
            Assert.Contains(plan.Moves, m => m.Title == "Unit 1, Day 4");
            Assert.Contains(plan.Moves, m => m.Title == "Unit 2, Day 1");
            var result = workspace.ApplyInsertClasses(plan);

            Assert.Contains($"moved {plan.Moves.Count - 2} onto later class days", result.Message);
        }
        finally { File.SetAttributes(locked, FileAttributes.Normal); }
    }
}
