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
        // by the window's plantoir-mcp, which the window hands its
        // --state-dir since #641, so it lands in this run's trail too.
        Assert.Contains($"{Code}/1 · the Section menu backed up the course as ", MenuBar.Trail(app));

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

    /// <summary>With <c>PLANTOIR_UI_CAPTURE_DIR</c> set, a picture of the screen for the hand-back; otherwise nothing.</summary>
    private static void CaptureIfAsked(string fileName)
    {
        if (Environment.GetEnvironmentVariable("PLANTOIR_UI_CAPTURE_DIR") is not { Length: > 0 } folder) return;
        Directory.CreateDirectory(folder);
        FlaUI.Core.Capturing.Capture.Screen().ToFile(Path.Combine(folder, fileName));
    }

    private static DrivenApp ACourseWithTwoClasses()
    {
        var app = new DrivenApp(courses =>
        {
            EndToEnd.WriteCourse(courses, Code, "Section Menu Course", new[] { "Concepts" });
            EndToEnd.WritePage(Path.Combine(courses, Code, "section1", "All Classes", "Unit 1, Day 1.md"),
                               "title: Unit 1, Day 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400", "The first lesson.");
            EndToEnd.WritePage(Path.Combine(courses, Code, "section1", "All Classes", "Unit 1, Day 2.md"),
                               "title: Unit 1, Day 2\npublish: false\ncreated: 2026-09-10T07:00:00.000-0400", "The second lesson.");
        });
        var dates = new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10), new DateOnly(2026, 9, 14), new DateOnly(2026, 9, 16) };
        Assert.True(Plantoir.Core.Assist.TimetableMemory.Write(app.WorkspacePath, Code, 1, dates, "test", new DateOnly(2026, 9, 1)));
        app.SelectSection(Code, 1);
        return app;
    }

    /// <summary>
    /// #927 (the mac's #897 piece A), end to end through the window and its
    /// own <c>plantoir-mcp</c>: Classes ▸ Add Class… opens the dialog with the
    /// three ways, the first chosen, and Add adds the next class in this unit,
    /// hidden. #990's "name the real menu": the copy saved first is the
    /// Classes menu's (<c>_classes-section1</c>) and the trail says
    /// "Classes ▸ Add Class…" with the way. MUST FAIL with Add Next Class in
    /// the menu (no classesAddClass) or the way left out of the trail's counts.
    /// </summary>
    [UiFact]
    public void AddClassAddsTheNextClassInThisUnit_AndSavesTheClassesMenusCopy()
    {
        using var app = ACourseWithTwoClasses();

        EndToEnd.PressMenuBarItem(app, "Classes", "classesAddClass");
        var next = WaitFor(app, "sectionVerbAddClassWay-nextInThisUnit", "the first way");
        Assert.True(next.AsRadioButton().IsChecked, "the first way was not chosen when the dialog opened");
        Assert.Equal(Plantoir.Core.Assist.AssistWording.MenuAddClassNextInThisUnit, next.Name);
        Assert.True(WaitFor(app, "sectionVerbAddClassWay-inANewUnit", "the second way").IsEnabled);
        Assert.True(WaitFor(app, "sectionVerbAddClassWay-asACopyOfAClass", "the third way").IsEnabled);
        Assert.Equal(Plantoir.Core.Assist.AssistWording.MenuAddButton,
                     MenuBar.Dialog(app, "Add Class…").FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))?.Name);
        CaptureIfAsked("windows-add-class-dialog.png");
        Press(app, "PrimaryButton", "Add Class… (Add)");
        var result = WaitFor(app, "sectionVerbResult", "what Add Class… did");
        _output.WriteLine("result: " + result.Name);
        MenuBar.CloseDialog(app);

        Assert.Contains("publish: false", File.ReadAllText(Page(app, "Unit 1, Day 3")));
        string backups = Path.Combine(app.WorkspacePath, "courses", "_backups", Code);
        Assert.Single(Directory.GetFiles(backups, $"{Code}_backup_*_classes-section1.zip"));
        Assert.Empty(MenuCopies(app));
        Assert.Contains($"{Code}/1 · the Classes menu backed up the course as ", MenuBar.Trail(app));
        Assert.Contains($"{Code}/1 · Classes ▸ Add Class… — carried out, the next class in this unit", MenuBar.Trail(app));
    }

    /// <summary>
    /// #927, as a copy: the copy list (Page and Date), a class chosen,
    /// Continue, the plan, Duplicate. The copy is the section's NEXT class,
    /// hidden however the source was, and nothing else moves
    /// (<c>class-planning.json</c> → <c>duplicatingAsTheNextClass</c>). MUST
    /// FAIL with the copy put after its source (the assistant's duplicate).
    /// </summary>
    [UiFact]
    public void AddClassAsACopyMakesTheNextClassHidden_AndMovesNothingElse()
    {
        using var app = ACourseWithTwoClasses();
        string second = File.ReadAllText(Page(app, "Unit 1, Day 2"));

        EndToEnd.PressMenuBarItem(app, "Classes", "classesAddClass");
        WaitFor(app, "sectionVerbAddClassWay-asACopyOfAClass", "the copy's way").AsRadioButton().IsChecked = true;
        var source = WaitFor(app, "sectionVerbSource0", "the first class to copy");
        Assert.StartsWith("Unit 1, Day 1", source.Name);
        Assert.Equal(Plantoir.Core.Assist.AssistWording.MenuContinueButton,
                     MenuBar.Dialog(app, "Add Class…").FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))?.Name);
        source.AsListBoxItem().Select();
        CaptureIfAsked("windows-add-class-copy.png");
        Press(app, "PrimaryButton", "Add Class… (Continue)");
        var plan = WaitFor(app, "sectionVerbPlan", "the copy's plan");
        Assert.Contains("“Unit 1, Day 1” would be copied to “Unit 1, Day 3”, dated 2026-09-14.", plan.Name);
        CaptureIfAsked("windows-add-class-copy-plan.png");
        Press(app, "PrimaryButton", "Add Class… (Duplicate)");
        var result = WaitFor(app, "sectionVerbResult", "what the copy did");
        Assert.Equal(Plantoir.Core.Assist.AssistWording.DuplicatedFromTheMenu("Unit 1, Day 1", "Unit 1, Day 3", "2026-09-14"), result.Name);
        MenuBar.CloseDialog(app);

        string copy = File.ReadAllText(Page(app, "Unit 1, Day 3"));
        Assert.Contains("The first lesson.", copy);
        Assert.Contains("publish: false", copy);
        Assert.Equal(second, File.ReadAllText(Page(app, "Unit 1, Day 2")));
        Assert.Contains($"{Code}/1 · Classes ▸ Add Class… — carried out, as a copy of a class", MenuBar.Trail(app));
    }

    /// <summary>
    /// #954 (the mac's #897 piece B), end to end: Classes ▸ Roll Over to a New
    /// Year… on a deployed section shows the dates on file, says they have
    /// passed, and asks the website question with NOTHING chosen and Continue
    /// dimmed; Keep, Continue, the plan's own website and record lines, Roll
    /// Over: the second class re-dated, a copy saved first (the Classes
    /// menu's), the marker kept, the trail's counts saying which way the
    /// website went. MUST FAIL with an answer chosen when the dialog
    /// opens, or Continue live before one is.
    /// </summary>
    [UiFact]
    public void RollOverAsksAboutTheWebsiteWithNothingChosen_ThenKeepsIt()
    {
        using var app = ACourseWithTwoClasses();
        string marker = Path.Combine(app.WorkspacePath, "courses", Code, ".netlify_sites", "section1.json");
        Directory.CreateDirectory(Path.GetDirectoryName(marker)!);
        File.WriteAllText(marker, """{"name": "uiverb-s1-2025-gordon"}""");

        EndToEnd.PressMenuBarItem(app, "Classes", "classesRollOverToANewYear");
        var startNew = WaitFor(app, "sectionVerbRollOverWebsite-new", "the new-website answer");
        var keep = WaitFor(app, "sectionVerbRollOverWebsite-same", "the keep-the-website answer");
        Assert.Equal(Plantoir.Core.Assist.AssistWording.MenuRollOverNewWebsite, startNew.Name);
        Assert.False(startNew.AsRadioButton().IsChecked, "an answer was chosen when the dialog opened");
        Assert.False(keep.AsRadioButton().IsChecked, "an answer was chosen when the dialog opened");
        WaitFor(app, "sectionVerbRollOverDatesAreOld", "the line saying the dates have passed");
        var dialog = MenuBar.Dialog(app, "Roll Over to a New Year…");
        var primary = dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"));
        Assert.Equal(Plantoir.Core.Assist.AssistWording.MenuContinueButton, primary?.Name);
        Assert.False(primary!.IsEnabled, "Continue was live before the website question had an answer");
        CaptureIfAsked("windows-roll-over-dialog.png");

        keep.AsRadioButton().IsChecked = true;
        Press(app, "PrimaryButton", "Roll Over to a New Year… (Continue)");
        var plan = WaitFor(app, "sectionVerbPlan", "the rollover's plan");
        Assert.Contains(Plantoir.Core.Assist.AssistWording.MenuRollOverPlanKeepsTheWebsite, plan.Name);
        Assert.Contains(Plantoir.Core.Assist.AssistWording.MenuRollOverPlanSetsTheRecordAside, plan.Name);
        Assert.Equal(Plantoir.Core.Assist.AssistWording.MenuRollOverButton,
                     MenuBar.Dialog(app, "Roll Over (plan)").FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))?.Name);
        CaptureIfAsked("windows-roll-over-plan.png");
        Press(app, "PrimaryButton", "Roll Over to a New Year… (Roll Over)");
        var result = WaitFor(app, "sectionVerbResult", "what the rollover did");
        _output.WriteLine("result: " + result.Name);
        Assert.Contains(Plantoir.Core.Assist.AssistWording.RolloverKeptTheSameWebsite, result.Name);
        MenuBar.CloseDialog(app);

        Assert.True(File.Exists(marker), "keeping the website moved its marker");
        string backups = Path.Combine(app.WorkspacePath, "courses", "_backups", Code);
        Assert.Single(Directory.GetFiles(backups, $"{Code}_backup_*_classes-section1.zip"));
        string trail = MenuBar.Trail(app);
        Assert.Contains($"{Code}/1 · Classes ▸ Roll Over to a New Year… — ", trail);
        Assert.Contains("website: kept", trail);
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
