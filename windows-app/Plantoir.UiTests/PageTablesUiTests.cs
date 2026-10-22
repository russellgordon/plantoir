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
/// while the teacher searches; the plan folds the pages already right without
/// the dialog growing when it opens; and the dialog follows a wider window.
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

    private static AutomationElement OpenThePicker(DrivenApp app)
    {
        app.SelectSection(Code, 1);
        EndToEnd.PressMenuBarItem(app, "Section", "sectionPublishPages");
        return WaitFor(app, "sectionVerbPickerTable", "the picker's table");
    }

    private static bool Ticked(DrivenApp app, int index) => WaitFor(app, $"sectionVerbPage{index}", $"box {index}").AsCheckBox().IsChecked == true;

    private static void Space(DrivenApp app)
    {
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Press(VirtualKeyShort.SPACE);
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
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 4, TimeSpan.FromSeconds(5)).Result,
                    "the picker does not show the four pages offered");

        var find = WaitFor(app, "sectionVerbFind", "Find a page");
        app.ClickMiddleOf(find);
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Type("Day 1 ");
        Thread.Sleep(600);
        Assert.Equal("Day 1 ", find.AsTextBox().Text);
        Assert.False(Enumerable.Range(0, 4).Any(i => Ticked(app, i)), "Space typed in Find a Page ticked a page");
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 1, TimeSpan.FromSeconds(5)).Result,
                    "the search did not leave one row");
        Assert.Equal(before, table.BoundingRectangle.Height);
        MenuBar.CloseDialog(app);
    }

    [UiFact]
    public void ReturnContinuesAndEscapeCancels_WithARowSelected()
    {
        using var app = new DrivenApp(WriteCourse);
        OpenThePicker(app);
        WaitFor(app, "sectionVerbPage1", "box 1").AsCheckBox().Toggle();
        SelectAndFocus(app, "sectionVerbPageRow1");
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Press(VirtualKeyShort.RETURN);
        WaitFor(app, "sectionVerbPlanTable", "the plan, after Return with a row selected");
        MenuBar.CloseDialog(app);

        OpenThePicker(app);
        SelectAndFocus(app, "sectionVerbPageRow0");
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(10)).Result,
                    "Escape with a row selected did not cancel the picker");
    }

    /// <summary>
    /// A plan of 1 change and 4 pages already visible: the table is five rows
    /// tall with the disclosure closed (the floor), shows the one row, and
    /// opening the disclosure adds the four to the SAME table without moving
    /// the table's or the dialog's edges.
    /// </summary>
    [UiFact]
    public void ThePlanFoldsThePagesAlreadyRight_AndOpeningDoesNotGrowTheDialog()
    {
        using var app = new DrivenApp(WriteCourse);
        OpenThePicker(app);
        var dialog = MenuBar.Dialog(app, "Publish Pages…");
        dialog.FindAllDescendants(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.CheckBox))
              .First(element => element.Name == "Unit 1, Day 1").AsCheckBox().Toggle();
        dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.AsButton().Invoke();
        var table = WaitFor(app, "sectionVerbPlanTable", "the plan's table");

        var fold = WaitFor(app, "sectionVerbPlanAlreadyRight", "the disclosure");
        Assert.Equal(AssistWording.MenuPlanShowAlready(Seen, publishing: true), fold.Name);
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 1, TimeSpan.FromSeconds(5)).Result,
                    $"closed, the table draws {table.FindAllChildren().Length} rows, not the one to read");
        var tableBefore = table.BoundingRectangle;
        var publish = MenuBar.Dialog(app, "the plan").FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!;
        var publishBefore = publish.BoundingRectangle;
        var pitch = WaitFor(app, "sectionVerbPlanRow0", "the row to read").BoundingRectangle.Height;
        _output.WriteLine($"closed: table {tableBefore.Height} tall (row {pitch}); Publish at {publishBefore.Top}");
        Assert.InRange(tableBefore.Height, 5 * 31, 5 * 33 + 2);           // five rows' worth, one drawn

        fold.Patterns.Toggle.Pattern.Toggle();
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 1 + Seen, TimeSpan.FromSeconds(5)).Result,
                    $"open, the table draws {table.FindAllChildren().Length} rows, not {1 + Seen}");
        Assert.Equal(FlaUI.Core.Definitions.ToggleState.On, fold.Patterns.Toggle.Pattern.ToggleState.Value);
        Assert.Equal(tableBefore, table.BoundingRectangle);
        Assert.Equal(publishBefore, publish.BoundingRectangle);
        Assert.EndsWith(AssistWording.MenuPlanAlreadyVisible, WaitFor(app, $"sectionVerbPlanRow{Seen}", "the last row").Name);

        fold.Patterns.Toggle.Pattern.Toggle();
        Assert.True(Retry.WhileFalse(() => table.FindAllChildren().Length == 1, TimeSpan.FromSeconds(5)).Result,
                    "closing the disclosure did not fold the rows again");
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
        _output.WriteLine($"window {narrowWindow} -> {window.BoundingRectangle.Width}; table {narrowTable} -> {wideTable}");
        Assert.True(wideTable - narrowTable <= 300 * 2 + 4, "the dialog grew past its cap");   // pixels or epx, at up to 200%
        try
        {
            foreach (string line in File.ReadAllLines(Path.Combine(app.StateDirectory, "startup.log"))
                                        .Where(line => line.Contains("Plan table:")).TakeLast(2))
                _output.WriteLine("the app's own sizing: " + line);
        }
        catch (IOException) { }
        MenuBar.CloseDialog(app);
    }
}
