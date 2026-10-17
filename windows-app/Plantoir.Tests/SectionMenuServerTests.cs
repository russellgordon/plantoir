using ModelContextProtocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The Section menu's server (#489, the mac's #457 batch B): the same tools,
/// with <see cref="AssistSurface.Menu"/> — its voice (the <c>…FromTheMenu</c>
/// twins), its backups (a fresh <c>_menu-section&lt;N&gt;</c> copy before every
/// change, with a trail line) and pages named by their folder. The mac's
/// <c>MenuVoiceTests</c> and <c>SectionVerbsTests.testPagesAreNamedByTheirFolder</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public class SectionMenuServerTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-menu-server").FullName;
    private readonly string _trail;
    private readonly string _course;

    public SectionMenuServerTests()
    {
        _trail = Path.Combine(_folder, "trail.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        _course = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(_course);
        File.WriteAllText(Path.Combine(_course, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 2, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1, 2] }
            """);
        foreach (int section in new[] { 1, 2 })
        {
            int day = 8;
            foreach (string title in new[] { "Unit 1, Day 1", "Unit 1, Day 2", "Unit 1, Day 3" })
                Write(section, "All Classes", title, $"---\npublish: false\ncreated: 2026-09-{day++:00}T07:00:00.000-0400\n---\nBody.\n");
        }
        // Every shipped payload carries pages like these: the same name in
        // more than one folder, which a bare name refuses as ambiguous.
        Write(1, "_DUPLICATE ME", "Unit 1, Day 1", "---\npublish: false\n---\nTemplate.\n");
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private void Write(int section, string folder, string title, string text)
    {
        string full = Path.Combine(_course, $"section{section}", folder, title + ".md");
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, text);
    }

    private string Read(int section, string folder, string title) =>
        File.ReadAllText(Path.Combine(_course, $"section{section}", folder, title + ".md"));

    private AssistWorkspace Menu() =>
        new(_folder, new FakeLauncher(), undo: new UndoHistory()) { Surface = AssistSurface.Menu };

    private string[] MenuBackups() =>
        Directory.Exists(Path.Combine(_folder, "courses", "_backups", "ICS3U"))
            ? Directory.GetFiles(Path.Combine(_folder, "courses", "_backups", "ICS3U"), "*_menu-section1.zip")
            : Array.Empty<string>();

    private static readonly IProgress<ProgressNotificationValue> NoProgress = new Progress<ProgressNotificationValue>(_ => { });

    [Fact]
    public async Task APageNamedByItsFolderIsTheOneTicked_NotItsDuplicateTemplate()
    {
        var tools = new PlantoirTools(Menu());

        var answer = await tools.PublishPages("ICS3U", 1, NoProgress, default,
                                              new[] { "section1/_DUPLICATE ME/Unit 1, Day 1" }, preview: false);

        Assert.Contains("publish: true", Read(1, "_DUPLICATE ME", "Unit 1, Day 1"));
        Assert.Contains("publish: false", Read(1, "All Classes", "Unit 1, Day 1"));
        Assert.DoesNotContain("I ", answer.Summary());
    }

    [Fact]
    public void PageByFolder_ResolvesInsideTheCourse_AndRefusesAnotherSectionsPrefix()
    {
        var workspace = Menu();
        var course = workspace.Course("ICS3U");

        string found = workspace.Page(course, 1, "section1/_DUPLICATE ME/Unit 1, Day 1");
        Assert.Equal(Path.GetFullPath(Path.Combine(_course, "section1", "_DUPLICATE ME", "Unit 1, Day 1.md")),
                     Path.GetFullPath(found));

        // section2's page exists, but this is section 1: no page by that place here.
        Assert.Throws<AssistRefusal>(() => workspace.Page(course, 1, "section2/All Classes/Unit 1, Day 1"));
        // Never outside the course.
        Assert.ThrowsAny<Exception>(() => workspace.Page(course, 1, "../../preview"));
    }

    [Fact]
    public async Task EveryChangeSavesItsOwnMenuCopy_AndSaysSoOnTheTrail()
    {
        var tools = new PlantoirTools(Menu());

        await tools.PublishPages("ICS3U", 1, NoProgress, default, new[] { "section1/All Classes/Unit 1, Day 1" }, preview: false);
        // A second change in the SAME second must not reuse or overwrite the first copy.
        await tools.PublishPages("ICS3U", 1, NoProgress, default, new[] { "section1/All Classes/Unit 1, Day 2" }, preview: false);

        var copies = MenuBackups();
        Assert.Equal(2, copies.Length);
        Assert.All(copies, copy => Assert.IsType<BackupMaker.Menu>(BackupItem.From(copy, "ICS3U")!.Maker));
        Assert.Empty(Directory.GetFiles(Path.Combine(_folder, "courses", "_backups", "ICS3U"), "*_assistant-section*"));

        string trail = File.ReadAllText(_trail);
        Assert.Contains("ICS3U/1 · the Section menu backed up the course as ICS3U_backup_", trail);
        Assert.Contains("_menu-section1.zip (", trail);
    }

    [Fact]
    public async Task UndoSpeaksFromTheMenu_AndTheLastChangeIsPlaced()
    {
        var workspace = Menu();
        var tools = new PlantoirTools(workspace);

        Assert.Equal(AssistWording.NothingToUndoFromTheMenu, tools.UndoLastChange().Summary());

        var before = workspace.TopOfTheUndoList;
        await tools.PublishPages("ICS3U", 1, NoProgress, default, new[] { "section1/All Classes/Unit 1, Day 2" }, preview: false);
        workspace.NoteWhereTheLastChangeWasMade(before, "ics3u", 1);
        Assert.Equal("ICS3U/1", workspace.LastChangePlace);

        string undone = tools.UndoLastChange().Summary();
        Assert.StartsWith("Undone. Earlier, you ", undone);
        Assert.Contains("publish: false", Read(1, "All Classes", "Unit 1, Day 2"));
        Assert.Null(workspace.LastChangePlace);
    }

    [Fact]
    public async Task ANameNoLongerThereIsSaidInTheMenusWords_ByTheNameTicked()
    {
        var tools = new PlantoirTools(Menu());

        var answer = await tools.PublishPages("ICS3U", 1, NoProgress, default,
                                              new[] { "section1/All Classes/Unit 9, Day 9" }, preview: false);

        Assert.Equal(AssistWording.NoPageCalledFromTheMenu("Unit 9, Day 9", "ICS3U", "1"), answer.Summary());
    }

    [Fact]
    public async Task ADayWithNoClassIsSaidInTheMenusWords()
    {
        var tools = new PlantoirTools(Menu());

        var answer = await tools.PublishClassOn("ICS3U", 1, "2026-10-05", NoProgress, default, preview: false);

        Assert.Equal(AssistWording.NoClassOnFromTheMenu(new DateOnly(2026, 10, 5), "ICS3U", "1"), answer.Summary());
        Assert.Contains("Monday, 2026-10-05", answer.Summary());
    }

    [Fact]
    public async Task TheAssistantsServerIsUnchanged()
    {
        var window = new AssistWorkspace(_folder, new FakeLauncher(), undo: new UndoHistory()) { Surface = AssistSurface.LocalWindow };
        var tools = new PlantoirTools(window);

        Assert.Equal(AssistWording.NothingToUndo, tools.UndoLastChange().Summary());
        var answer = await tools.PublishClassOn("ICS3U", 1, "2026-10-05", NoProgress, default, preview: false);
        Assert.StartsWith("ICS3U Section 1 has no class on 2026-10-05.", answer.Summary());
        Assert.False(window.SpeaksFromTheMenu);
        Assert.True(window.ServesTheLocalWindow);
    }

    // ---- #548: the page plans carry their table, from the menu only ------------

    private static PlanTable? TableOf(ModelContextProtocol.Protocol.CallToolResult result) =>
        AssistToolAnswer.FromResult(result.Detail(), result.Meta).PlanTable;

    [Fact]
    public void ThePageAndDayPlansCarryATable_OnlyFromTheMenu()
    {
        File.WriteAllText(Path.Combine(_course, "Course Outline.md"), "---\npublishForSection1: false\n---\nOutline.\n");
        Write(1, "All Classes", "Seen", "---\npublish: true\n---\nUp.\n");
        string[] publishing = { "section1/All Classes/Unit 1, Day 2", "Course Outline" };
        string[] hiding = { "section1/All Classes/Seen" };

        var menu = new PlantoirTools(Menu());
        var published = TableOf(menu.PlanPublishPages("ICS3U", 1, publishing));
        var hidden = TableOf(menu.PlanUnpublishPages("ICS3U", 1, hiding));
        var day = TableOf(menu.PlanPublishClassOn("ICS3U", 1, "2026-09-08"));

        Assert.NotNull(published);
        Assert.Equal(new[] { ("Unit 1, Day 2", "section1/All Classes"), ("Course Outline", "ICS3U") },
                     published!.Rows.Select(row => (row.Title, row.Folder)));
        Assert.All(published.Rows, row => Assert.Equal(AssistWording.PlanWillBecomeVisible, row.WhatChanges));
        Assert.Equal(AssistWording.MenuPlanSummary(2, 0, publishing: true), published.Summary);
        Assert.Equal(PlanTable.Change.WillBecomeHidden, Assert.Single(hidden!.Rows).Change);
        Assert.Equal("Unit 1, Day 1", Assert.Single(day!.Rows).Title);

        // Not from the assistant's window, nor from outside: their answers are as they were.
        foreach (var surface in new[] { AssistSurface.LocalWindow, AssistSurface.Outside })
        {
            var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher(), undo: new UndoHistory()) { Surface = surface });
            Assert.Null(TableOf(tools.PlanPublishPages("ICS3U", 1, publishing)));
            Assert.Null(TableOf(tools.PlanUnpublishPages("ICS3U", 1, hiding)));
            Assert.Null(TableOf(tools.PlanPublishClassOn("ICS3U", 1, "2026-09-08")));
        }
    }

    [Fact]
    public void APlanWithNothingToDoCarriesNoTable()
    {
        Write(1, "All Classes", "Seen", "---\npublish: true\n---\nUp.\n");
        var menu = new PlantoirTools(Menu());
        var answer = menu.PlanPublishPages("ICS3U", 1, new[] { "section1/All Classes/Seen" });
        Assert.False(AssistToolAnswer.FromResult(answer.Detail(), answer.Meta).IsPlan);
        Assert.Null(TableOf(answer));
    }

    /// <summary>
    /// The model's bytes do not move: the text content of a page plan is the
    /// same from the menu as from the assistant's window, table or no table.
    /// (A plan with no menu-voice sentence in it — one with no declined pages.)
    /// </summary>
    [Fact]
    public void TheTextContentIsTheSameWithOrWithoutTheTable()
    {
        string[] pages = { "section1/All Classes/Unit 1, Day 2" };
        var fromTheMenu = new PlantoirTools(Menu()).PlanPublishPages("ICS3U", 1, pages);
        var fromTheWindow = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher(), undo: new UndoHistory())
            { Surface = AssistSurface.LocalWindow }).PlanPublishPages("ICS3U", 1, pages);

        Assert.NotNull(TableOf(fromTheMenu));
        Assert.Equal(fromTheWindow.Detail(), fromTheMenu.Detail());
    }

    [Theory]
    [InlineData("menu", null, AssistSurface.Menu)]
    [InlineData("MENU", "1", AssistSurface.Menu)]
    [InlineData(null, "1", AssistSurface.LocalWindow)]
    [InlineData(null, null, AssistSurface.Outside)]
    [InlineData("", "0", AssistSurface.Outside)]
    public void TheSurfaceIsReadFromTheServersVariables(string? surface, string? localWindow, AssistSurface expected) =>
        Assert.Equal(expected, AssistWorkspace.SurfaceFrom(surface, localWindow));
}
