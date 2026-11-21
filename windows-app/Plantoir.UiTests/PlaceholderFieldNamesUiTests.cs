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

        // Three of these boxes have a placeholder that is exactly their name
        // (the filter's "Filter", the list's "New folder name", the deploy
        // box's "Folder"), and WinUI hands a TextBox's placeholder over as
        // its automation Name when nothing else names it (measured, notes).
        // So those three assertions show what a screen reader is told, not
        // that the fix is there: PlaceholderFieldNamesSourceTests pins their
        // SetName calls and is their guard.
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
        EndToEnd.PressMenuBarItem(app, "Classes", "classesClassDates");
        var dates = MenuBar.Dialog(app, "Classes > Class Dates…");
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
        EndToEnd.PressMenuBarItem(app, "Classes", "classesClassDates");
        var dates = MenuBar.Dialog(app, "Classes > Class Dates…");
        var box = InDialog(dates, "sectionScheduleTypedField", "the dates box");
        CopyAPageEscapeUiTests.Front(app);

        Assert.True(FocusArrivesAt(app, id => id == "sectionScheduleTypedField"),
                    $"the sheet opened with the keyboard on '{Focused(app)}', not in the dates box");
        CaptureIfAsked("1024-class-dates-opens-in-the-box.png");

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
    /// The review's M1 (#1024): the dialog sends only its own first placement
    /// of the focus to the dates box. A focus move made afterwards by UI
    /// Automation, the way Narrator moves focus with its cursor and Voice
    /// Access moves it to a control, stays where it was sent, with no key
    /// pressed first. Measured, such a move arrives as Programmatic, the same
    /// as the dialog's own placement.
    /// </summary>
    [UiFact]
    public void FocusSentByAssistiveTechnologyStaysWhereItWasSent()
    {
        using var app = new DrivenApp(WriteCourses);
        app.SelectSection(CourseFixtures.Renamed, 1);
        EndToEnd.PressMenuBarItem(app, "Classes", "classesClassDates");
        var dates = MenuBar.Dialog(app, "Classes > Class Dates…");
        var source = InDialog(dates, "sectionScheduleSourceField", "the source box");
        var cancel = InDialog(dates, "CloseButton", "the Cancel button");
        var aFile = dates.FindFirstDescendant(cf => cf.ByName("A file").And(cf.ByControlType(ControlType.RadioButton)))
                    ?? throw new Xunit.Sdk.XunitException("the dialog offers no file route");
        CopyAPageEscapeUiTests.Front(app);
        Assert.True(FocusArrivesAt(app, id => id == "sectionScheduleTypedField"),
                    $"the sheet opened with the keyboard on '{Focused(app)}', not in the dates box");

        source.Focus();
        Assert.True(FocusArrivesAt(app, id => id == "sectionScheduleSourceField"),
                    $"focus sent to \"Where these came from\" went to '{Focused(app)}'");
        aFile.Focus();
        Assert.True(Retry.WhileFalse(() =>
        {
            try { return app.Window.Automation.FocusedElement()?.ControlType == ControlType.RadioButton; }
            catch { return false; }
        }, TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(100)).Result,
                    $"focus sent to the route picker went to '{Focused(app)}'");
        cancel.Focus();
        Assert.True(FocusArrivesAt(app, id => id == "CloseButton"), $"focus sent to Cancel went to '{Focused(app)}'");
        source.Focus();
        Assert.True(FocusArrivesAt(app, id => id == "sectionScheduleSourceField"),
                    $"focus sent back to \"Where these came from\" went to '{Focused(app)}'");
        MenuBar.CloseDialog(app);
    }

    /// <summary>
    /// The review's L1 (#1024): opened from the keyboard (the menu walked
    /// with Down and the item pressed with Enter), the sheet starts in the
    /// dates box too, and the Enter types nothing there. Measured on the
    /// fix's first version, three keyboard opens in six started on the
    /// route picker, because the dialog's placement then reaches only
    /// FocusManager's event; each open here is a placement of its own.
    /// </summary>
    [UiFact]
    public void OpenedFromTheKeyboardTheSheetStartsInTheDatesBox()
    {
        using var app = new DrivenApp(WriteCourses);
        app.SelectSection(CourseFixtures.Renamed, 1);
        for (int open = 1; open <= 3; open++)
        {
            CopyAPageEscapeUiTests.Front(app);
            PressClassDatesFromTheKeyboard(app);
            var dates = MenuBar.Dialog(app, "Classes > Class Dates…");
            var box = InDialog(dates, "sectionScheduleTypedField", "the dates box");
            Assert.True(FocusArrivesAt(app, id => id == "sectionScheduleTypedField"),
                        $"opened from the keyboard (open {open}), the sheet started on '{Focused(app)}', not in the dates box");
            Assert.Equal("", box.Patterns.Value.Pattern.Value.Value);
            // Review 2's L6: the focus STAYS in the box, not merely passes
            // through it. A key typed now reaches the box once the window has
            // handled everything queued before it, so a second placement made
            // by then has moved the focus, and the box still holding it after
            // the typed key is the check. The retry waits on the typed text,
            // an event, not on a time.
            Keyboard.Type("9");
            Assert.True(Retry.WhileFalse(() => box.Patterns.Value.Pattern.Value.Value == "9",
                                         TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(100)).Result,
                        $"opened from the keyboard (open {open}), a key typed in the dates box did not reach it; the focus is on '{Focused(app)}'");
            Assert.True(Focused(app) == "sectionScheduleTypedField",
                        $"opened from the keyboard (open {open}), the focus left the dates box for '{Focused(app)}'");
            MenuBar.CloseDialog(app);
        }
    }

    /// <summary>Open Classes, walk it with Down to Class Dates… and press Enter.</summary>
    private static void PressClassDatesFromTheKeyboard(DrivenApp app)
    {
        var top = app.Window.FindFirstDescendant(cf => cf.ByName("Classes").And(cf.ByControlType(ControlType.MenuItem)))
                  ?? throw new Xunit.Sdk.XunitException("the menu bar has no Classes menu");
        top.Patterns.ExpandCollapse.Pattern.Expand();
        Assert.True(Retry.WhileFalse(() => Focused(app).StartsWith("classes"), TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(100)).Result,
                    $"the Classes menu opened with the focus on '{Focused(app)}'");
        // Down at most once per item the menu holds: past that it has wrapped.
        int items = app.Desktop.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem)).Length;
        for (int press = 0; press < items && Focused(app) != "classesClassDates"; press++)
        {
            string before = Focused(app);
            Keyboard.Type(VirtualKeyShort.DOWN);
            Retry.WhileFalse(() => Focused(app) != before, TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(100));
        }
        Assert.Equal("classesClassDates", Focused(app));
        Keyboard.Type(VirtualKeyShort.ENTER);
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
        // With the row back to a horizontal StackPanel the text never trims,
        // so this fails there too (measured, must-fail 3): a bound on the
        // text's rectangle passed either way and was taken out.
        Assert.True(Retry.WhileFalse(() => longTitle.Properties.HelpText.ValueOrDefault == LongCode,
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"the cut-short code's text carries \"{longTitle.Properties.HelpText.ValueOrDefault}\", not the whole code");
        Assert.Equal(LongCode, NameOf(app.Find($"sidebar-{LongCode}", "the long code's row")));

        var shortTitle = app.Find($"sidebar-{CourseFixtures.Renamed}-title", "a short code's text");
        Assert.Equal("", shortTitle.Properties.HelpText.ValueOrDefault ?? "");

        // What a person sees: the real pointer rested on the cut-short code
        // draws the tooltip, and it holds the whole code. The harness's own
        // glide (FixWithButtonsUiTests): a placed cursor opens no WinUI tooltip.
        string pictures = Environment.GetEnvironmentVariable("PLANTOIR_UI_CAPTURE_DIR") ?? "";
        Assert.True(FixWithButtonsUiTests.RestThePointerOn(app, longTitle, LongCode, pictures, "1024-cut-short-code-tooltip"),
                    "resting the pointer on the cut-short code drew no tooltip holding the whole code");
    }

    /// <summary>With <c>PLANTOIR_UI_CAPTURE_DIR</c> set, a picture of the screen for the hand-back; otherwise nothing.</summary>
    private static void CaptureIfAsked(string fileName)
    {
        if (Environment.GetEnvironmentVariable("PLANTOIR_UI_CAPTURE_DIR") is not { Length: > 0 } folder) return;
        Directory.CreateDirectory(folder);
        FlaUI.Core.Capturing.Capture.Screen().ToFile(Path.Combine(folder, fileName));
    }
}
