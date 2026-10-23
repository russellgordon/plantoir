using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Assist;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #634 (the mac's #608, #621, #622) through the real window: Publish
/// Pages…'s picker is a table whose tick rules are the mac's — a click on a
/// box ticks it, selecting ticks nothing, Space ticks the selected row exactly
/// once, Space typed in Find a Page ticks nothing, Return and Escape still
/// reach Continue and Cancel with a row selected — its height does not move
/// while the teacher searches; the plan folds the pages already right until a
/// checkbox is ticked, without the dialog growing when they are shown (#655);
/// the answer after Go is fitted to its sentence (#655); and the dialog
/// follows a wider window.
/// Expected words come from <see cref="AssistWording"/>, never typed. Real
/// keys go to whatever is in front, so each press is preceded by
/// <see cref="CopyAPageEscapeUiTests.Front"/>, and a row is FOCUSED before a
/// real Space (UI Automation's Select() does not move the keyboard focus).
/// </summary>
[Collection("drives the real app")]
public class PageTablesUiTests
{
    private const string Code = "UITICK";
    private const int Seen = 4;

    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);

    private readonly ITestOutputHelper _output;
    public PageTablesUiTests(ITestOutputHelper output) => _output = output;

    private static string ClassPath(string courses, string title) => Path.Combine(courses, Code, "section1", "All Classes", title + ".md");
    private static string ConceptPath(string courses, string title) => Path.Combine(courses, Code, "Concepts", title + ".md");

    /// <summary>
    /// Three hidden classes dated in the past (so #475's question is never
    /// asked) and a hidden concept page: four pages offered, fewer than the
    /// twelve rows the picker shows at most. The first class links four
    /// concept pages already visible, so its plan is 1 change + 4 already
    /// visible: a plan under the five-row floor.
    /// </summary>
    private static void WriteCourse(string courses)
    {
        EndToEnd.WriteCourse(courses, Code, "Tick Table Course", new[] { "Concepts" });
        string links = string.Join("\n", Enumerable.Range(1, Seen).Select(i => $"- [[Seen {i}]]"));
        EndToEnd.WritePage(ClassPath(courses, "Unit 1, Day 1"),
                           "title: Unit 1, Day 1\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400", $"A class.\n\n{links}");
        EndToEnd.WritePage(ClassPath(courses, "Unit 1, Day 2"),
                           "title: Unit 1, Day 2\npublish: false\ncreated: 2026-09-09T07:00:00.000-0400", "A class.");
        EndToEnd.WritePage(ClassPath(courses, "Unit 1, Day 3"),
                           "title: Unit 1, Day 3\npublish: false\ncreated: 2026-09-10T07:00:00.000-0400", "A class.");
        EndToEnd.WritePage(ConceptPath(courses, "Idea A"), "title: Idea A\npublishForSection1: false", "An idea.");
        for (int i = 1; i <= Seen; i++)
            EndToEnd.WritePage(ConceptPath(courses, $"Seen {i}"), $"title: Seen {i}\npublishForSection1: true", "Already up.");
    }

    private static AutomationElement WaitFor(DrivenApp app, string automationId, string what) =>
        Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
                        TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result
        ?? throw new Xunit.Sdk.XunitException($"{what} never appeared ({automationId}).");

    private AutomationElement OpenThePicker(DrivenApp app, string item = "sectionPublishPages")
    {
        app.SelectSection(Code, 1);
        // The menus re-read what is live when the pointer enters a title or the
        // menu bar takes the focus (MainWindow.Menus); a dialog greys them all
        // (#457), and UI Automation's Expand does neither, so after a dialog the
        // pointer is moved over the Section title first, as a teacher's is.
        var started = DateTime.Now;
        for (int attempt = 1; ; attempt++)
        {
            if (app.Window.FindFirstDescendant(cf => cf.ByName("Section").And(cf.ByControlType(FlaUI.Core.Definitions.ControlType.MenuItem))) is { } title)
            {
                app.BringToFront();
                Mouse.MoveTo(DrivenApp.MiddleOf(title, app.Window.BoundingRectangle));
                Thread.Sleep(300);
            }
            try
            {
                EndToEnd.PressMenuBarItem(app, "Section", item);
                break;
            }
            catch (FlaUI.Core.Exceptions.ElementNotEnabledException) when (DateTime.Now - started < TimeSpan.FromSeconds(30))
            {
                MenuBar.Close();
                Thread.Sleep(500);
            }
        }
        if (DateTime.Now - started > TimeSpan.FromSeconds(2))
            _output.WriteLine($"{item} was greyed for {(DateTime.Now - started).TotalSeconds:0.0} s after the last dialog");
        return WaitFor(app, "sectionVerbPickerTable", "the picker's table");
    }

    private static bool Ticked(DrivenApp app, int index) => WaitFor(app, $"sectionVerbPage{index}", $"box {index}").AsCheckBox().IsChecked == true;

    /// <summary>
    /// One Space: down AND up. FlaUI's <c>Keyboard.Press</c> is the key going
    /// DOWN only — measured 2026-10-22, <c>GetAsyncKeyState(VK_SPACE)</c> still
    /// read down 400 ms after it — so two Presses are a HELD Space to the app
    /// (the second arrives with <c>KeyStatus.WasKeyDown</c>), and the table
    /// rightly ignores it as a repeat.
    /// </summary>
    private static void Space(DrivenApp app)
    {
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Type(VirtualKeyShort.SPACE);
        Thread.Sleep(400);
    }

    /// <summary>A held Space: what the keyboard sends while the key is held — more downs, no up — then the release.</summary>
    private static void HeldSpace(DrivenApp app)
    {
        CopyAPageEscapeUiTests.Front(app);
        try
        {
            for (int down = 0; down < 6; down++)
            {
                Keyboard.Press(VirtualKeyShort.SPACE);
                Thread.Sleep(down == 0 ? 500 : 33);
            }
        }
        finally { Keyboard.Release(VirtualKeyShort.SPACE); }
        Thread.Sleep(400);
    }

    /// <summary>Select a row AND give it the keyboard focus.</summary>
    private static AutomationElement SelectAndFocus(DrivenApp app, string rowId)
    {
        var row = WaitFor(app, rowId, rowId);
        row.Patterns.SelectionItem.Pattern.Select();
        row.Focus();
        Thread.Sleep(300);
        return row;
    }

    /// <summary>A measurement, to the test's output and to %TEMP%\plantoir-634-measured.txt (a passing test's output is not shown).</summary>
    private void Note(string line)
    {
        _output.WriteLine(line);
        try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "plantoir-634-measured.txt"), $"{DateTime.Now:yyyy-MM-dd HH:mm} {line}{Environment.NewLine}"); }
        catch (IOException) { }
    }

    /// <summary>A picture of the window for judging the banding, into %TEMP% (never the site's images).</summary>
    private void Picture(DrivenApp app, string name)
    {
        // Only when asked: a full-screen picture on every run is litter.
        if (Environment.GetEnvironmentVariable("PLANTOIR_634_PICTURES") != "1") return;
        Thread.Sleep(500);
        string theme = Environment.GetEnvironmentVariable("PLANTOIR_634_THEME") ?? "system";
        string path = Path.Combine(Path.GetTempPath(), $"plantoir-634-{name}-{theme}.png");
        // The whole screen in REAL pixels: this process is not DPI-aware, so
        // FlaUI's captures come out a quarter of the screen at 200%. The thread
        // is made per-monitor aware for the capture alone, then put back.
        IntPtr previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        try
        {
            int width = GetSystemMetrics(0), height = GetSystemMetrics(1);
            using var bitmap = new System.Drawing.Bitmap(width, height);
            using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
                graphics.CopyFromScreen(0, 0, 0, 0, new System.Drawing.Size(width, height));
            bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            _output.WriteLine($"picture: {path} ({width} x {height})");
        }
        catch (Exception error) { _output.WriteLine("no picture: " + error.Message); }
        finally { SetThreadDpiAwarenessContext(previous); }
    }

    private static string Status(AutomationElement row) => row.Properties.ItemStatus.ValueOrDefault ?? "";

    [UiFact]
    public void SelectingTicksNothing_SpaceTicksTheSelectedRowOnce_AndAClickOnTheBoxTicks()
    {
        using var app = new DrivenApp(WriteCourse);
        OpenThePicker(app);

        // Selecting is not ticking.
        var row = SelectAndFocus(app, "sectionVerbPageRow1");
        Assert.True(row.Patterns.SelectionItem.Pattern.IsSelected.Value, "the row did not take the selection");
        Assert.False(Ticked(app, 1), "selecting a row ticked it");
        Assert.Equal("not ticked", Status(row));

        // Space ticks the selected row, once; again unticks it.
        Space(app);
        Assert.True(Ticked(app, 1), "Space on the selected row did not tick it");
        Assert.Equal("ticked", Status(WaitFor(app, "sectionVerbPageRow1", "row 1")));
        Space(app);
        Assert.False(Ticked(app, 1), "a second Space did not untick it (or the first flipped it twice)");
        Assert.False(Ticked(app, 0) || Ticked(app, 2) || Ticked(app, 3), "Space ticked a row that was not selected");

        // A held Space ticks once: its repeats never flicker the box.
        HeldSpace(app);
        Assert.True(Ticked(app, 1), "a held Space did not tick the row exactly once (its repeats flipped it back)");
        Space(app);
        Assert.False(Ticked(app, 1), "Space after a held Space did not untick it");

        // A click on the box ticks it — then Space, with the focus ON the box,
        // flips it exactly once (a box clicks on key-up; the table takes both).
        var box = WaitFor(app, "sectionVerbPage2", "box 2");
        app.ClickMiddleOf(box);
        Thread.Sleep(400);
        Assert.True(Ticked(app, 2), "a click on the box did not tick it");
        Space(app);
        Assert.False(Ticked(app, 2), "Space after the click did not flip the box exactly once");
        MenuBar.CloseDialog(app);
    }

    [UiFact]
    public void SpaceInFindAPageTicksNothing_AndTheTableKeepsItsHeight()
    {
        using var app = new DrivenApp(WriteCourse);
        var table = OpenThePicker(app);
        int before = table.BoundingRectangle.Height;
        _output.WriteLine($"picker table {before} tall for 4 pages offered");
        // The chrome PageTableLayout.PickerChrome estimates: the dialog's box
        // (title top − 24 to the buttons' bottom + 24, as PlanTableUiTests reads
        // it) less the table's border-box.
        var box = MenuBar.Dialog(app, "Publish Pages…");
        var title = box.FindFirstDescendant(cf => cf.ByName(AssistWording.MenuPublishPagesTitle(Code, "1")))?.BoundingRectangle;
        var continueButton = box.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.BoundingRectangle;
        if (title is { } t)
            Note($"MEASURED picker: dialog box {continueButton.Bottom + 24 - (t.Top - 24)} tall, table {before}, " +
                              $"chrome {continueButton.Bottom + 24 - (t.Top - 24) - before} (PickerChrome {PageTableLayout.PickerChrome}); " +
                              $"window {app.Window.BoundingRectangle.Width}x{app.Window.BoundingRectangle.Height}; table width {table.BoundingRectangle.Width}");
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 4, TimeSpan.FromSeconds(5)).Result,
                    "the picker does not show the four pages offered");

        var find = WaitFor(app, "sectionVerbFind", "Find a page");
        app.ClickMiddleOf(find);
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Type("Day 1 ");
        Thread.Sleep(600);
        Assert.Equal("Day 1 ", find.AsTextBox().Text);
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 1, TimeSpan.FromSeconds(5)).Result,
                    "the search did not leave one row");
        Assert.False(Ticked(app, 0), "Space typed in Find a Page ticked the row the search left");
        Assert.Equal(before, table.BoundingRectangle.Height);

        Picture(app, "picker-searched");
        // The search cleared: every row back, none ticked, the height unmoved.
        find.AsTextBox().Text = "";
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 4, TimeSpan.FromSeconds(5)).Result,
                    "clearing the search did not bring the four rows back");
        Assert.False(Enumerable.Range(0, 4).Any(i => Ticked(app, i)), "Space typed in Find a Page ticked a page");
        Assert.Equal(before, table.BoundingRectangle.Height);
        Picture(app, "picker");
        MenuBar.CloseDialog(app);
    }

    /// <summary>
    /// Return with a row selected reaches Continue (the list keeps Return for
    /// itself, so the table passes it on). Each key in an app of its own: UI
    /// Automation's Expand does not make the menus re-read what is live (a
    /// real click or Alt does), and after a dialog Publish Pages… was measured
    /// greyed for 30 s that way.
    /// </summary>
    [UiFact]
    public void ReturnContinues_WithARowSelected()
    {
        using var app = new DrivenApp(WriteCourse);
        OpenThePicker(app);
        WaitFor(app, "sectionVerbPage1", "box 1").AsCheckBox().Toggle();
        SelectAndFocus(app, "sectionVerbPageRow1");
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Press(VirtualKeyShort.RETURN);
        WaitFor(app, "sectionVerbPlanTable", "the plan, after Return with a row selected");
        MenuBar.CloseDialog(app);
    }

    [UiFact]
    public void EscapeCancels_WithARowSelected()
    {
        using var app = new DrivenApp(WriteCourse);
        OpenThePicker(app);
        SelectAndFocus(app, "sectionVerbPageRow0");
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(10)).Result,
                    "Escape with a row selected did not cancel the picker");
    }

    /// <summary>
    /// A plan of 1 change and 4 pages already visible: the table is five rows
    /// tall with the checkbox unticked (the floor), shows the one row, and
    /// ticking the checkbox adds the four to the SAME table without moving
    /// the table's or the dialog's edges; a second click takes them out
    /// (#655, the mac's #654: a CHECKBOX, not a disclosure, which promised a
    /// fold below it that never appeared).
    /// </summary>
    [UiFact]
    public void ThePlanFoldsThePagesAlreadyRightUntilTheCheckboxIsTicked()
    {
        using var app = new DrivenApp(WriteCourse);
        OpenThePicker(app);
        var dialog = MenuBar.Dialog(app, "Publish Pages…");
        dialog.FindAllDescendants(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.CheckBox))
              .First(element => element.Name == "Unit 1, Day 1").AsCheckBox().Toggle();
        dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.AsButton().Invoke();
        var table = WaitFor(app, "sectionVerbPlanTable", "the plan's table");

        var fold = WaitFor(app, "sectionVerbPlanAlreadyRight", "the checkbox");
        Assert.Equal(AssistWording.MenuPlanShowAlready(Seen, publishing: true), fold.Name);
        Assert.Equal(FlaUI.Core.Definitions.ControlType.CheckBox, fold.ControlType);
        Assert.Equal(FlaUI.Core.Definitions.ToggleState.Off, fold.Patterns.Toggle.Pattern.ToggleState.Value);
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 1, TimeSpan.FromSeconds(5)).Result,
                    $"closed, the table draws {table.FindAllChildren().Length} rows, not the one to read");
        var tableBefore = table.BoundingRectangle;
        var publish = MenuBar.Dialog(app, "the plan").FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!;
        var publishBefore = publish.BoundingRectangle;
        var pitch = WaitFor(app, "sectionVerbPlanRow0", "the row to read").BoundingRectangle.Height;
        _output.WriteLine($"closed: table {tableBefore.Height} tall (row {pitch}); Publish at {publishBefore.Top}");
        Assert.InRange(tableBefore.Height, 5 * 31, 5 * 33 + 2);           // five rows' worth, one drawn

        // The line PlanTableLayout reserves must hold the checkbox and its gap,
        // or a fit counted with it comes out short and clips the buttons.
        int foldLine = fold.BoundingRectangle.Bottom - tableBefore.Bottom;
        Note($"MEASURED fold: checkbox {fold.BoundingRectangle.Height} tall, its top {fold.BoundingRectangle.Top - tableBefore.Bottom} under the table " +
             $"({foldLine} in all; FoldHeight {PlanTableLayout.FoldHeight} counts both)");
        Assert.True(foldLine <= PlanTableLayout.FoldHeight,
                    $"the checkbox and its gap take {foldLine} epx; PlanTableLayout.FoldHeight reserves {PlanTableLayout.FoldHeight}");
        fold.AsCheckBox().Click();
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 1 + Seen, TimeSpan.FromSeconds(5)).Result,
                    $"open, the table draws {table.FindAllChildren().Length} rows, not {1 + Seen}");
        Assert.Equal(FlaUI.Core.Definitions.ToggleState.On, fold.Patterns.Toggle.Pattern.ToggleState.Value);
        Assert.Equal(tableBefore, table.BoundingRectangle);
        Assert.Equal(publishBefore, publish.BoundingRectangle);
        Picture(app, "plan-open");
        Assert.EndsWith(AssistWording.MenuPlanAlreadyVisible, WaitFor(app, $"sectionVerbPlanRow{Seen}", "the last row").Name);

        fold.AsCheckBox().Click();
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 1, TimeSpan.FromSeconds(5)).Result,
                    "a second click on the checkbox did not take the rows out again");
        Assert.Equal(FlaUI.Core.Definitions.ToggleState.Off, fold.Patterns.Toggle.Pattern.ToggleState.Value);
        Assert.Equal(tableBefore, table.BoundingRectangle);
        MenuBar.CloseDialog(app);
    }

    /// <summary>
    /// #655 (the mac's #654): after Go the dialog shows one sentence over OK
    /// and is FITTED to it — shorter than the plan, the same width — while
    /// Working keeps the height of the stage before it, so the dialog changes
    /// size once. The dialog's BOX is not in the UI Automation tree (its
    /// element is the whole overlay), and the elements inside it did not help:
    /// MEASURED 2026-10-23, the title's and the buttons' rectangles read the
    /// same at the plan and at the answer while a picture of the screen showed
    /// the box centred and shrunk. So the box is read from the size the app
    /// laid it out at (the "Section menu dialog at …" lines in its own
    /// startup.log, its template's <c>BackgroundElement</c>), and OK is checked
    /// to be inside the window. Publish (1 change, 4 folded) and Hide (1 change).
    /// </summary>
    [UiFact]
    public void TheAnswerAfterAPublishPlanIsFittedToItsSentence() => TheAnswerAfterAPlanIsFittedToItsSentence(publishing: true);

    /// <summary>The same for Hide Pages…: a plan of one page to hide.</summary>
    [UiFact]
    public void TheAnswerAfterAHidePlanIsFittedToItsSentence() => TheAnswerAfterAPlanIsFittedToItsSentence(publishing: false);

    private static readonly System.Text.RegularExpressions.Regex BoxLine =
        new(@"Section menu dialog at (\w+): box (\d+)x(\d+)", System.Text.RegularExpressions.RegexOptions.Compiled);

    /// <summary>Every box the app laid the dialog out at, in order: (stage, width, height).</summary>
    private static List<(string Stage, int Width, int Height)> Boxes(DrivenApp app)
    {
        var boxes = new List<(string, int, int)>();
        try
        {
            using var stream = new FileStream(Path.Combine(app.StateDirectory, "startup.log"), FileMode.Open, FileAccess.Read,
                                              FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(stream);
            foreach (string line in reader.ReadToEnd().Split('\n'))
                if (BoxLine.Match(line) is { Success: true } match)
                    boxes.Add((match.Groups[1].Value, int.Parse(match.Groups[2].Value), int.Parse(match.Groups[3].Value)));
        }
        catch (IOException) { }
        return boxes;
    }

    private void TheAnswerAfterAPlanIsFittedToItsSentence(bool publishing)
    {
        using var app = new DrivenApp(WriteCourse);
        OpenThePicker(app, publishing ? "sectionPublishPages" : "sectionHidePages");
        var dialog = MenuBar.Dialog(app, publishing ? "Publish Pages…" : "Hide Pages…");
        string pick = publishing ? "Unit 1, Day 1" : "Seen 1";
        dialog.FindAllDescendants(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.CheckBox))
              .First(element => element.Name == pick).AsCheckBox().Toggle();
        dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.AsButton().Invoke();
        WaitFor(app, "sectionVerbPlanTable", "the plan's table");
        Thread.Sleep(600);
        Picture(app, publishing ? "655-publish-plan" : "655-hide-plan");
        var go = MenuBar.Dialog(app, "the plan").FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!;
        go.AsButton().Invoke();
        var result = WaitFor(app, "sectionVerbResult", "the answer");
        Thread.Sleep(800);
        Picture(app, publishing ? "655-publish-answer" : "655-hide-answer");

        var boxes = Boxes(app);
        Note($"MEASURED answer ({(publishing ? "Publish" : "Hide")}): window {app.Window.BoundingRectangle.Width}x{app.Window.BoundingRectangle.Height} epx; " +
             $"the dialog's box by stage: {string.Join(", ", boxes.Select(box => $"{box.Stage} {box.Width}x{box.Height}"))}; answer \"{result.Name}\"");
        int planAt = boxes.FindLastIndex(box => box.Stage == "Plan");
        Assert.True(planAt >= 0, "the app never logged the plan's box");
        var plan = boxes[planAt];
        var after = boxes.Skip(planAt + 1).ToList();
        var working = after.Where(box => box.Stage == "Working").ToList();
        var answers = after.Where(box => box.Stage == "Result").ToList();
        Assert.NotEmpty(working);
        Assert.NotEmpty(answers);
        // Working keeps the plan's height: the dialog changes size once.
        Assert.All(working, box => Assert.InRange(box.Height, plan.Height - 1, plan.Height + 1));
        var answer = answers[^1];
        Assert.True(answer.Height < plan.Height - 32, $"the answer kept the plan's height: plan {plan.Height}, answer {answer.Height}");
        Assert.Equal(plan.Width, answer.Width);   // the width is kept
        var ok = MenuBar.Dialog(app, "the answer").FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.BoundingRectangle;
        Assert.True(ok.Height > 0 && ok.Bottom <= app.Window.BoundingRectangle.Bottom, "OK is not inside the window");
        MenuBar.CloseDialog(app);
    }

    /// <summary>
    /// The window is the dialog's resize handle: widened, the plan's dialog is
    /// wider (up to 300 epx more), and the Page column takes the width.
    /// </summary>
    [UiFact]
    public void TheDialogFollowsAWiderWindow()
    {
        using var app = new DrivenApp(WriteCourse);
        var window = app.Window;
        window.Patterns.Transform.Pattern.Resize(900, window.BoundingRectangle.Height);
        Thread.Sleep(800);
        OpenThePicker(app);
        var dialog = MenuBar.Dialog(app, "Publish Pages…");
        dialog.FindAllDescendants(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.CheckBox))
              .First(element => element.Name == "Unit 1, Day 1").AsCheckBox().Toggle();
        dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.AsButton().Invoke();
        var table = WaitFor(app, "sectionVerbPlanTable", "the plan's table");
        int narrowTable = table.BoundingRectangle.Width;
        int narrowWindow = window.BoundingRectangle.Width;

        window.Patterns.Transform.Pattern.Resize(narrowWindow + 400, window.BoundingRectangle.Height);
        Assert.True(Retry.WhileFalse(() => table.BoundingRectangle.Width > narrowTable, TimeSpan.FromSeconds(5),
                                     TimeSpan.FromMilliseconds(200)).Result,
                    $"the window widened ({narrowWindow} -> {window.BoundingRectangle.Width}) and the table stayed {narrowTable} wide");
        int wideTable = table.BoundingRectangle.Width;
        Note($"MEASURED width: window {narrowWindow} -> {window.BoundingRectangle.Width}; table {narrowTable} -> {wideTable}");
        Assert.True(wideTable - narrowTable <= 300 * 2 + 4, "the dialog grew past its cap");   // pixels or epx, at up to 200%
        try
        {
            foreach (string line in File.ReadAllLines(Path.Combine(app.StateDirectory, "startup.log"))
                                        .Where(line => line.Contains("Plan table:")).TakeLast(2))
                Note("the app's own sizing: " + line);
        }
        catch (IOException) { }
        MenuBar.CloseDialog(app);
    }
}
