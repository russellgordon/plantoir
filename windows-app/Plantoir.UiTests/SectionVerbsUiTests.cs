using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #489 through the real window: the assistant's functions run from the
/// Section menu with no assistant anywhere — the tools' own code behind a
/// <c>plantoir-mcp</c> the window starts for itself.
/// </summary>
[Collection("drives the real app")]
public class SectionVerbsUiTests
{
    private const string Code = "UIVERB";
    private static readonly TimeSpan LongEnoughToBuild = TimeSpan.FromMinutes(15);

    private readonly ITestOutputHelper _output;
    public SectionVerbsUiTests(ITestOutputHelper output) => _output = output;

    private static string Page(DrivenApp app, string title) =>
        Path.Combine(app.WorkspacePath, "courses", Code, "section1", "All Classes", title + ".md");

    private static AutomationElement WaitFor(DrivenApp app, string automationId, string what, TimeSpan? within = null) =>
        Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
                        within ?? TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result
        ?? throw new Xunit.Sdk.XunitException($"{what} never appeared ({automationId}).");

    private static void Press(DrivenApp app, string buttonId, string what)
    {
        var dialog = MenuBar.Dialog(app, what);
        var button = Retry.WhileNull(() => dialog.FindFirstDescendant(cf => cf.ByAutomationId(buttonId)),
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result
                     ?? throw new Xunit.Sdk.XunitException($"{what} has no {buttonId}");
        Assert.True(Retry.WhileFalse(() => button.IsEnabled, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"{what}: {buttonId} never became available");
        button.AsButton().Invoke();
    }

    private static string[] MenuCopies(DrivenApp app)
    {
        string backups = Path.Combine(app.WorkspacePath, "courses", "_backups", Code);
        return Directory.Exists(backups) ? Directory.GetFiles(backups, $"{Code}_backup_*_menu-section1.zip") : Array.Empty<string>();
    }

    [UiFact]
    public void PublishPagesTicksPlansAndPublishes_ThenUndoLastChangePutsItBack()
    {
        using var app = new DrivenApp(courses =>
        {
            EndToEnd.WriteCourse(courses, Code, "Section Menu Course", new[] { "Concepts" });
            EndToEnd.WritePage(Path.Combine(courses, Code, "section1", "All Classes", "Unit 1, Day 1.md"),
                               "title: Unit 1, Day 1\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400", "A class.");
        });
        string before = File.ReadAllText(Page(app, "Unit 1, Day 1"));
        Assert.Contains("publish: false", before);
        app.SelectSection(Code, 1);

        // Undo Last Change is greyed until a change has been made here.
        var items = MenuBar.Open(app, "Section", "sectionPublishPages");
        Assert.True(items["sectionPublishPages"].IsEnabled, "Section > Publish Pages… was greyed on a live section");
        Assert.False(items["sectionUndoLastChange"].IsEnabled, "Undo Last Change was live before any change");
        MenuBar.Close();

        // ---- Publish Pages…: tick, Continue, read the plan, Publish.
        EndToEnd.PressMenuBarItem(app, "Section", "sectionPublishPages");
        var box = WaitFor(app, "sectionVerbPage0", "the checklist's first page");
        Assert.Contains("Unit 1, Day 1", box.Name);
        box.AsCheckBox().Toggle();
        Press(app, "PrimaryButton", "Publish Pages… (Continue)");
        var plan = WaitFor(app, "sectionVerbPlan", "the plan");
        _output.WriteLine("plan: " + plan.Name);
        Press(app, "PrimaryButton", "Publish Pages… (Publish)");
        var result = WaitFor(app, "sectionVerbResult", "what Publish did");
        _output.WriteLine("result: " + result.Name);
        MenuBar.CloseDialog(app);

        string after = File.ReadAllText(Page(app, "Unit 1, Day 1"));
        Assert.NotEqual(before, after);
        Assert.DoesNotContain("publish: false", after);
        Assert.Single(MenuCopies(app));
        Assert.Contains($"{Code}/1 · Section ▸ Publish Pages… — carried out, 1 page ticked", MenuBar.Trail(app));
        // The copy's own line ("section menu backed up a course") is written
        // by the window's plantoir-mcp, which --state-dir does not reach
        // (AppDataRoot: it does not cross processes), so it lands in this PC's
        // own trail; SectionMenuServerTests pins it. The zip above is the proof here.

        // ---- Undo Last Change is live now, and puts the page back.
        var again = MenuBar.Open(app, "Section", "sectionUndoLastChange");
        Assert.True(again["sectionUndoLastChange"].IsEnabled, "Undo Last Change stayed greyed after a change made here");
        MenuBar.Close();
        EndToEnd.PressMenuBarItem(app, "Section", "sectionUndoLastChange");
        var undone = WaitFor(app, "sectionVerbResult", "what Undo Last Change did");
        Assert.StartsWith("Undone.", undone.Name);
        MenuBar.CloseDialog(app);
        Assert.Equal(before, File.ReadAllText(Page(app, "Unit 1, Day 1")));
        Assert.Contains($"{Code}/1 · Section ▸ Undo Last Change — took the last change back", MenuBar.Trail(app));
    }

    [UiFact]
    public void RebuildPreviewRebuildsAServingPreview()
    {
        string first = EndToEnd.Marker("Before");
        using var app = new DrivenApp(courses =>
            EndToEnd.WriteCourse(courses, Code, "Section Menu Course", new[] { "Concepts" },
                                 frontPage: $"---\ntitle: {Code}\n---\n# Front\n\n{first}\n"));
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);
        app.Find("previewButton", "the Preview button").AsButton().Invoke();
        string? url = null;
        Assert.True(app.WaitAnsweringDialogs(() => (url = EndToEnd.ServedFrontPage(first)) is not null, LongEnoughToBuild),
                    "the first preview never served its front page" + app.AnsweredSoFar);

        // The served site is a merged COPY: an edit is not seen until it is rebuilt.
        string second = EndToEnd.Marker("After");
        File.AppendAllText(Path.Combine(app.WorkspacePath, "courses", Code, "section1", "index.md"), $"\n\n{second}\n");
        var pressed = DateTime.Now;
        EndToEnd.PressMenuBarItem(app, "Section", "sectionRebuildPreview");
        Assert.True(app.WaitAnsweringDialogs(() => EndToEnd.ServedFrontPage(second) is not null, LongEnoughToBuild),
                    "Rebuild Preview never served the edit — a serving preview was not rebuilt" + app.AnsweredSoFar);
        _output.WriteLine($"rebuilt and served {(DateTime.Now - pressed).TotalSeconds:0} s after Rebuild Preview");
        Assert.Contains($"{Code}/1 · Section ▸ Rebuild Preview — rebuilt", MenuBar.Trail(app));
    }
}
