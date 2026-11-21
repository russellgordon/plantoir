using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;

namespace Plantoir.UiTests;

/// <summary>
/// #1020 and #1024 through the real window: what UI Automation hands a screen
/// reader and a keyboard for the boxes the mac named in #1012, the class-dates
/// box's keys (the mac's #997 ruling Q-C), and the whole course code on a row
/// that cuts it short (the mac's #997 D44). The boxes that need a running task
/// or the assistant (the console's and a question's answer box, the credential
/// field, the assistant's own box) are pinned by
/// <c>PlaceholderFieldNamesSourceTests</c> instead.
/// </summary>
[Collection("drives the real app")]
public class PlaceholderFieldNamesUiTests
{
    /// <summary>Twelve wide letters, the most a code may have: cut short in the 230-epx sidebar.</summary>
    private const string LongCode = "WWWWWWWWWWWW";

    /// <summary>A course that publishes to a folder, so its Folder box is drawn.</summary>
    private const string FolderCourse = "EXC2O";

    private static void WriteCourses(string courses)
    {
        CourseFixtures.WriteBoth(courses);
        EndToEnd.WriteCourse(courses, LongCode, "Wide Letters", new[] { "Tasks" });
        string siteFolder = Path.Combine(Path.GetDirectoryName(courses)!, "site-out");
        Directory.CreateDirectory(siteFolder);
        EndToEnd.WriteCourse(courses, FolderCourse, "Exploring Computers", new[] { "Tasks" }, EndToEnd.PublishesTo(siteFolder));
    }

    /// <summary>The element's automation Name, or "" when nothing names it (FlaUI's .Name throws then).</summary>
    private static string NameOf(AutomationElement element) => element.Properties.Name.ValueOrDefault ?? "";

    private static void AssertNamed(AutomationElement element, string name, string what) =>
        Assert.True(NameOf(element) == name, $"{what} is named \"{NameOf(element)}\", not \"{name}\"");

    private static AutomationElement InDialog(AutomationElement dialog, string automationId, string what) =>
        Retry.WhileNull(() => dialog.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
                        TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result
        ?? throw new Xunit.Sdk.XunitException($"the dialog has no {what} ({automationId})");

    private static string Focused(DrivenApp app)
    {
        try { return app.Window.Automation.FocusedElement()?.Properties.AutomationId.ValueOrDefault ?? ""; }
        catch { return ""; }
    }

    private static bool FocusArrivesAt(DrivenApp app, Func<string, bool> isThere) =>
        Retry.WhileFalse(() => isThere(Focused(app)), TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(100)).Result;

    [UiFact]
    public void EveryBoxThatShowedOnlyAPlaceholderHasANameOfItsOwn()
    {
        using var app = new DrivenApp(WriteCourses);

        AssertNamed(app.Find("courseFilterField", "the sidebar's filter"), "Filter", "the sidebar's filter");

        app.SelectCourse(CourseFixtures.Renamed);
        AssertNamed(app.Find("footerEditor", "Course Settings' footer box"), "Footer", "the footer box");
        app.Find("add:Shared folders (all sections)", "the shared folders' + button").AsButton().Invoke();
        AssertNamed(app.Find("addField:Shared folders (all sections)", "the shared folders' add field"),
                    "New folder name", "the list's add field");
        MenuBar.Close();

        EndToEnd.PressMenuBarItem(app, "Course", "courseRename");
        var rename = MenuBar.Dialog(app, "Course > Rename");
        AssertNamed(InDialog(rename, "renameField", "the code box"), "Course code", "the rename box");
        MenuBar.CloseDialog(app);

        app.SelectCourse(FolderCourse);
        AssertNamed(app.Find("deployFolderField", "the deploy folder box"), "Folder", "the deploy folder box");

        app.SelectSection(CourseFixtures.Renamed, 1);
        EndToEnd.PressMenuBarItem(app, "Section", "sectionClassDates");
        var dates = MenuBar.Dialog(app, "Section > Class Dates…");
        AssertNamed(InDialog(dates, "sectionScheduleTypedField", "the dates box"), "Class dates", "the dates box");
        AssertNamed(InDialog(dates, "sectionScheduleSourceField", "the source box"), "Where these came from", "the source box");
        var sheetRoute = dates.FindFirstDescendant(cf => cf.ByName("A Google Sheet").And(cf.ByControlType(ControlType.RadioButton)))
                         ?? throw new Xunit.Sdk.XunitException("the dialog offers no Google Sheet route");
        sheetRoute.Patterns.SelectionItem.Pattern.Select();
        AssertNamed(InDialog(dates, "sectionScheduleGoogleSheetField", "the sheet link box"), "Google Sheet address", "the sheet link box");
        MenuBar.CloseDialog(app);
    }

    /// <summary>
    /// The mac's <c>ClassDatesBoxKeyTests</c>: the sheet opens with the keyboard
    /// in the dates box; Tab goes on to "Where these came from" and types
    /// nothing; Shift-Tab from the box goes back to the route picker.
    /// </summary>
    [UiFact]
    public void TabLeavesTheDatesBoxAndTypesNothing()
    {
        using var app = new DrivenApp(WriteCourses);
        app.SelectSection(CourseFixtures.Renamed, 1);
        EndToEnd.PressMenuBarItem(app, "Section", "sectionClassDates");
        var dates = MenuBar.Dialog(app, "Section > Class Dates…");
        var box = InDialog(dates, "sectionScheduleTypedField", "the dates box");
        CopyAPageEscapeUiTests.Front(app);

        Assert.True(FocusArrivesAt(app, id => id == "sectionScheduleTypedField"),
                    $"the sheet opened with the keyboard on '{Focused(app)}', not in the dates box");

        Keyboard.Type("2026-09-08");
        Assert.True(Retry.WhileFalse(() => box.Patterns.Value.Pattern.Value.Value == "2026-09-08",
                                     TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(100)).Result,
                    "what was typed did not reach the dates box");
        Keyboard.Type(VirtualKeyShort.TAB);
        Assert.True(FocusArrivesAt(app, id => id == "sectionScheduleSourceField"),
                    $"Tab went to '{Focused(app)}', not to \"Where these came from\"");
        Assert.Equal("2026-09-08", box.Patterns.Value.Pattern.Value.Value);

        box.Focus();
        Assert.True(FocusArrivesAt(app, id => id == "sectionScheduleTypedField"), "the dates box would not take the focus back");
        Keyboard.TypeSimultaneously(VirtualKeyShort.SHIFT, VirtualKeyShort.TAB);
        Assert.True(Retry.WhileFalse(() =>
        {
            try { return app.Window.Automation.FocusedElement()?.ControlType == ControlType.RadioButton; }
            catch { return false; }
        }, TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(100)).Result,
                    $"Shift-Tab from the dates box went to '{Focused(app)}', not to the route picker");
        Assert.Equal("2026-09-08", box.Patterns.Value.Pattern.Value.Value);
        MenuBar.CloseDialog(app);
    }

    /// <summary>
    /// The mac's #997 D44: a course code cut short carries the whole code as
    /// its tooltip, read here as the text's help text, which the app sets with
    /// the tooltip; a code that fits carries none. The row's own name is the
    /// whole code either way.
    /// </summary>
    [UiFact]
    public void ACourseCodeCutShortShowsTheWholeCode()
    {
        using var app = new DrivenApp(WriteCourses);

        var longTitle = app.Find($"sidebar-{LongCode}-title", "the long code's text");
        Assert.True(Retry.WhileFalse(() => longTitle.Properties.HelpText.ValueOrDefault == LongCode,
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"the cut-short code's text carries \"{longTitle.Properties.HelpText.ValueOrDefault}\", not the whole code");
        Assert.Equal(LongCode, NameOf(app.Find($"sidebar-{LongCode}", "the long code's row")));

        // The text stays inside the sidebar, so nothing after it is pushed out
        // of sight: it ends no further right than the filter box, which runs to
        // the sidebar's own padding at the foot of the same column.
        var filter = app.Find("courseFilterField", "the sidebar's filter");
        var text = longTitle.BoundingRectangle;
        Assert.True(text.Right <= filter.BoundingRectangle.Right,
                    $"the long code's text ends at {text.Right}, past the sidebar's filter box at {filter.BoundingRectangle.Right}");

        var shortTitle = app.Find($"sidebar-{CourseFixtures.Renamed}-title", "a short code's text");
        Assert.Equal("", shortTitle.Properties.HelpText.ValueOrDefault ?? "");
    }
}
