using System.Runtime.InteropServices;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Assist;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #548 (the mac's #524) through the real window: Section ▸ Publish Pages…
/// shows its plan as a table of EVERY page, sized to the window so Cancel,
/// Publish and the notes stay on screen, and Return and Escape still mean
/// Publish and Cancel while the table has focus. Expected words are built from
/// <see cref="AssistWording"/>, never typed.
/// </summary>
/// <remarks>
/// The fixture is the mac's drive: a class linking sixteen hidden concept
/// pages and one visible one, plus a hidden class it also links (left as it
/// is, so there is a note under the table) — 17 pages to change, 19 rows.
/// Real keys go to whatever is in front, so each press is preceded by
/// <see cref="CopyAPageEscapeUiTests.Front"/>.
/// </remarks>
[Collection("drives the real app")]
public class PlanTableUiTests
{
    private const string Code = "UIPLAN";
    private const int Ideas = 16;

    private readonly ITestOutputHelper _output;
    public PlanTableUiTests(ITestOutputHelper output) => _output = output;

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);

    private static void WriteCourse(string courses)
    {
        EndToEnd.WriteCourse(courses, Code, "Plan Table Course", new[] { "Concepts" });
        string links = string.Join("\n", Enumerable.Range(1, Ideas).Select(i => $"- [[Idea {i:00}]]"));
        EndToEnd.WritePage(ClassPath(courses, "Unit 1, Day 1"),
                           "title: Unit 1, Day 1\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400",
                           $"A class.\n\n{links}\n- [[Seen]]\n- [[Unit 1, Day 2]]");
        EndToEnd.WritePage(ClassPath(courses, "Unit 1, Day 2"),
                           "title: Unit 1, Day 2\npublish: false\ncreated: 2026-09-09T07:00:00.000-0400", "The next class.");
        for (int i = 1; i <= Ideas; i++)
            EndToEnd.WritePage(ConceptPath(courses, $"Idea {i:00}"), $"title: Idea {i:00}\npublishForSection1: false", "An idea.");
        EndToEnd.WritePage(ConceptPath(courses, "Seen"), "title: Seen\npublishForSection1: true", "Already up.");
    }

    private static string ClassPath(string courses, string title) => Path.Combine(courses, Code, "section1", "All Classes", title + ".md");
    private static string ConceptPath(string courses, string title) => Path.Combine(courses, Code, "Concepts", title + ".md");
    private static string Courses(DrivenApp app) => Path.Combine(app.WorkspacePath, "courses");

    private static string[] MenuCopies(DrivenApp app)
    {
        string backups = Path.Combine(app.WorkspacePath, "courses", "_backups", Code);
        return Directory.Exists(backups) ? Directory.GetFiles(backups, $"{Code}_backup_*_menu-section1.zip") : Array.Empty<string>();
    }

    private static AutomationElement WaitFor(DrivenApp app, string automationId, string what) =>
        Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
                        TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result
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

    /// <summary>Section ▸ Publish Pages…, tick "Unit 1, Day 1", Continue; the plan's table.</summary>
    private AutomationElement OpenThePlan(DrivenApp app)
    {
        app.SelectSection(Code, 1);
        EndToEnd.PressMenuBarItem(app, "Section", "sectionPublishPages");
        WaitFor(app, "sectionVerbPage0", "the checklist");
        var dialog = MenuBar.Dialog(app, "Publish Pages…");
        var box = dialog.FindAllDescendants(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.CheckBox))
                        .FirstOrDefault(element => element.Name == "Unit 1, Day 1")
                  ?? throw new Xunit.Sdk.XunitException("the checklist offers no \"Unit 1, Day 1\"");
        box.AsCheckBox().Toggle();
        Press(app, "PrimaryButton", "Publish Pages… (Continue)");
        // Both classes are dated in the past, so #475's question about classes
        // dated after the next class is never asked here.
        return WaitFor(app, "sectionVerbPlanTable", "the plan's table");
    }

    /// <summary>Tab until the focus is inside the table; fail saying so if it never gets there.</summary>
    private void TabIntoTheTable(DrivenApp app, AutomationElement table)
    {
        for (int press = 0; press < 12; press++)
        {
            if (FocusIsIn(app, table)) return;
            var at = app.Window.Automation.FocusedElement();
            _output.WriteLine($"tab {press}: focus on {at?.ControlType} \"{at?.Name}\" ({at?.Properties.AutomationId.ValueOrDefault})");
            CopyAPageEscapeUiTests.Front(app);
            Keyboard.Press(VirtualKeyShort.TAB);
            Thread.Sleep(250);
        }
        Assert.True(FocusIsIn(app, table), "Tab never put the focus on the plan's table");
    }

    private bool FocusIsIn(DrivenApp app, AutomationElement table)
    {
        var focused = app.Window.Automation.FocusedElement();
        if (focused is null) return false;
        var walker = app.Window.Automation.TreeWalkerFactory.GetControlViewWalker();
        for (var at = focused; at is not null; at = walker.GetParent(at))
        {
            if (at.Properties.AutomationId.ValueOrDefault == "sectionVerbPlanTable")
            {
                _output.WriteLine($"focus: {focused.ControlType} \"{focused.Name}\" ({focused.Properties.AutomationId.ValueOrDefault})");
                return true;
            }
            if (at.Equals(app.Window)) break;
        }
        return false;
    }

    private static bool AllPublished(DrivenApp app) =>
        !File.ReadAllText(ClassPath(Courses(app), "Unit 1, Day 1")).Contains("publish: false")
        && Enumerable.Range(1, Ideas).All(i => !File.ReadAllText(ConceptPath(Courses(app), $"Idea {i:00}")).Contains("publishForSection1: false"));

    private static bool NoneChanged(DrivenApp app) =>
        File.ReadAllText(ClassPath(Courses(app), "Unit 1, Day 1")).Contains("publish: false")
        && File.ReadAllText(ClassPath(Courses(app), "Unit 1, Day 2")).Contains("publish: false")
        && Enumerable.Range(1, Ideas).All(i => File.ReadAllText(ConceptPath(Courses(app), $"Idea {i:00}")).Contains("publishForSection1: false"));

    /// <summary>
    /// Everything on the plan stage that must be inside the window: the
    /// table's bottom edge, the last note, Cancel and Publish. Returns the
    /// measurements for the doc.
    /// </summary>
    private string AssertItAllFits(DrivenApp app, AutomationElement table)
    {
        var dialog = MenuBar.Dialog(app, "the plan");
        var window = app.Window.BoundingRectangle;
        double scale = GetDpiForWindow(app.Window.Properties.NativeWindowHandle.Value) / 96.0;
        var title = dialog.FindFirstDescendant(cf => cf.ByName(AssistWording.MenuPublishPagesTitle(Code, "1")))?.BoundingRectangle;
        var row0 = WaitFor(app, "sectionVerbPlanRow0", "the first row").BoundingRectangle;
        var row1 = WaitFor(app, "sectionVerbPlanRow1", "the second row").BoundingRectangle;
        var box = table.BoundingRectangle;
        int pitch = row1.Top - row0.Top;
        var notes = dialog.FindAllDescendants(cf => cf.ByAutomationId("sectionVerbPlanNote0"));
        var lastNote = Assert.Single(notes).BoundingRectangle;
        var notesArea = dialog.FindFirstDescendant(cf => cf.ByAutomationId("sectionVerbPlanNotes"))?.BoundingRectangle;
        var publish = dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.BoundingRectangle;
        var cancel = dialog.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.BoundingRectangle;
        // UI Automation hands this test process (not DPI-aware) 96-dpi
        // coordinates, so every number here is in epx: a row reads 32, its
        // ListViewItem.MinHeight. The window's own DPI is reported beside them.
        // The dialog's box is not in the tree (its element is the whole
        // overlay), so its height is read from the title's top to Publish's
        // bottom plus the template's 24 epx of padding at each end.
        int? boxHeight = title is { } t ? publish.Bottom + 24 - (t.Top - 24) : null;
        int? chrome = boxHeight - box.Height - (notesArea?.Height + 8 ?? 0);
        string measured =
            $"window DPI scale {scale:0.##}; window {window.Width}x{window.Height} epx; " +
            $"row pitch {pitch} epx, row height {row0.Height}; " +
            $"table {box.Height} epx ({(double)(box.Height - 2) / pitch:0.#} rows), bottom {window.Bottom - box.Bottom} above the window's; " +
            $"notes area {notesArea?.Height}; last note bottom {window.Bottom - lastNote.Bottom} above; Publish bottom {window.Bottom - publish.Bottom} above; " +
            $"dialog box {boxHeight} tall (chrome outside the rows and notes {chrome})";
        _output.WriteLine("#548 measurement, " + DateTime.Now.ToString("yyyy-MM-dd HH:mm") + ": " + measured);
        try
        {
            string said = File.ReadAllLines(Path.Combine(app.StateDirectory, "startup.log")).LastOrDefault(line => line.Contains("Plan table:")) ?? "";
            _output.WriteLine("the app's own sizing: " + said);
        }
        catch (IOException) { }

        Assert.True(pitch > 0, "the rows do not stack: " + measured);
        Assert.True(box.Bottom <= window.Bottom, "the table runs past the window's bottom edge: " + measured);
        Assert.True(lastNote.Height > 0 && lastNote.Bottom <= window.Bottom && lastNote.Top >= box.Bottom,
                    "the note under the table is cut off or not under it: " + measured);
        Assert.True(publish.Height > 0 && publish.Bottom <= window.Bottom, "Publish is not inside the window: " + measured);
        Assert.True(cancel.Height > 0 && cancel.Bottom <= window.Bottom, "Cancel is not inside the window: " + measured);
        return measured;
    }

    [UiFact]
    public void ThePlanIsATableOfEveryPage_AndEscapeWithTheTableFocusedCancels()
    {
        using var app = new DrivenApp(WriteCourse);
        var table = OpenThePlan(app);

        var summary = WaitFor(app, "sectionVerbPlan", "the plan's summary");
        Assert.Equal(AssistWording.MenuPlanSummary(Ideas + 1, 1, publishing: true), summary.Name);
        Assert.Equal($"Unit 1, Day 1, section1/All Classes, {AssistWording.PlanWillBecomeVisible}",
                     WaitFor(app, "sectionVerbPlanRow0", "the first row").Name);
        string measured = AssertItAllFits(app, table);

        // Scrolls inside itself, and lists every page — no "…and N more".
        Assert.True(table.Patterns.Scroll.IsSupported && table.Patterns.Scroll.Pattern.VerticallyScrollable.Value,
                    "the table does not scroll: " + measured);
        table.Patterns.Scroll.Pattern.SetScrollPercent(-1, 100);
        Thread.Sleep(500);
        var last = WaitFor(app, $"sectionVerbPlanRow{Ideas + 2}", "the last row");
        Assert.EndsWith(AssistWording.MenuPlanAlreadyVisible, last.Name);
        Assert.EndsWith(AssistWording.MenuPlanStaysAsItIs, WaitFor(app, $"sectionVerbPlanRow{Ideas + 1}", "the left-alone row").Name);

        TabIntoTheTable(app, table);
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        app.AssertAbsent("sectionVerbDialog", "the Publish Pages… dialog, after Escape with the table focused");

        Assert.True(NoneChanged(app), "Escape at the plan changed a page");
        Assert.Empty(MenuCopies(app));
        Assert.Contains($"{Code}/1 · Section ▸ Publish Pages… — cancelled at the plan, 1 page ticked", MenuBar.Trail(app));
    }

    [UiFact]
    public void ReturnWithTheTableFocusedPublishesEveryPage()
    {
        using var app = new DrivenApp(WriteCourse);
        var table = OpenThePlan(app);
        TabIntoTheTable(app, table);

        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Press(VirtualKeyShort.RETURN);
        var result = WaitFor(app, "sectionVerbResult", "what Publish did, after Return with the table focused");
        _output.WriteLine("result: " + result.Name);
        MenuBar.CloseDialog(app);

        Assert.True(AllPublished(app), "Return at the plan did not publish the 17 pages");
        Assert.True(File.ReadAllText(ClassPath(Courses(app), "Unit 1, Day 2")).Contains("publish: false"),
                    "the linked class was published, though the plan said it stays as it is");
        // Once, not twice: a key handled by the table AND the dialog would run it again.
        Assert.Single(MenuCopies(app));
        string trail = MenuBar.Trail(app);
        string carriedOut = $"{Code}/1 · Section ▸ Publish Pages… — carried out, 1 page ticked";
        Assert.Equal(1, trail.Split('\n').Count(line => line.Contains(carriedOut)));
    }

    /// <summary>
    /// The headers sort (plan order first), and on a window dragged to the
    /// smallest it allows the table still fits with the note and the buttons.
    /// (Measured 2026-10-16: that minimum is 900 × 600 epx, TALLER than the
    /// default window on a 1920 × 1080 screen at 150%, 793 × 483 — so the
    /// default, in the test above, is the short case.)
    /// </summary>
    [UiFact]
    public void PressingAHeaderSorts_AndAWindowDraggedToItsMinimumStillFitsIt()
    {
        using var app = new DrivenApp(WriteCourse);
        var window = app.Window;
        // Asked for less than the window allows, so it stops at its own minimum.
        int before = window.BoundingRectangle.Height;
        window.Patterns.Transform.Pattern.Resize(window.BoundingRectangle.Width, 300);
        Retry.WhileFalse(() => window.BoundingRectangle.Height < before, TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200));
        Thread.Sleep(800);
        var table = OpenThePlan(app);
        AssertItAllFits(app, table);

        var sort = WaitFor(app, "sectionVerbPlanSortChange", "the What changes header");
        Assert.Equal(AssistWording.MenuPlanChangeColumn, sort.Name.Replace("Sort by ", ""));
        sort.AsButton().Invoke();
        Thread.Sleep(400);
        // Ascending by the cell's words: "already visible" first, derived rather than typed.
        string first = new[] { AssistWording.MenuPlanAlreadyVisible, AssistWording.MenuPlanStaysAsItIs, AssistWording.PlanWillBecomeVisible }
            .OrderBy(words => words, StringComparer.CurrentCultureIgnoreCase).First();
        Assert.EndsWith(first, FirstRow(table).Name);
        sort.AsButton().Invoke();
        Thread.Sleep(400);
        _output.WriteLine("after the second press: " + string.Join(" | ", table.FindAllChildren().Take(4).Select(child => child.Name)));
        Assert.Contains(", " + AssistWording.PlanWillBecomeVisible, FirstRow(table).Name);
        MenuBar.CloseDialog(app);
    }

    private static AutomationElement FirstRow(AutomationElement table) =>
        table.FindAllChildren().FirstOrDefault(child => child.Properties.AutomationId.ValueOrDefault?.StartsWith("sectionVerbPlanRow") == true)
        ?? throw new Xunit.Sdk.XunitException("the table has no rows");
}
