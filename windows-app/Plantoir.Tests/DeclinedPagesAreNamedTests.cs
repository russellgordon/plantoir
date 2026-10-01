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
}
