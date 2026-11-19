using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// The question dialogs' keys, pressed for real (#979, the Windows half of
/// the mac's #973 and #987). On a question where a teacher could lose work no
/// button is the default, so Enter must never go ahead; Escape is the
/// cancelling button; and the New Course wizard's Create Course is the default
/// once the form is complete, except while the code list is drawn, and
/// Escape does nothing while the course is being made (Russell, 2026-11-18).
/// </summary>
/// <remarks>
/// WinUI's ContentDialog gives its first focus to the first focusable control
/// in its content, then the default button, then the first focusable button
/// in its row, which is the go-ahead (Primary) one; a focused button takes
/// Enter. So a question with no default and nothing focusable in it opened
/// with the focus on Quit Anyway or Remove, and Enter pressed it.
/// <c>DialogButtons.AskWithNoDefault</c> puts the focus on Cancel instead.
/// Each press brings the app to the front first (see CopyAPageEscapeUiTests).
/// </remarks>
[Collection("drives the real app")]
public class QuestionDialogKeysUiTests
{
    private const string Code = "QKY2O";
    private static readonly TimeSpan Patience = TimeSpan.FromSeconds(10);

    private static void Press(DrivenApp app, VirtualKeyShort key)
    {
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Type(key);
        Thread.Sleep(600);
    }

    private static AutomationElement CloseButtonOf(AutomationElement dialog) =>
        dialog.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))
        ?? throw new Xunit.Sdk.XunitException("the question has no Close button");

    private static void AssertTheFocusStartsOnCancel(AutomationElement dialog, string question)
    {
        var close = CloseButtonOf(dialog);
        bool focused = Retry.WhileFalse(() => close.Properties.HasKeyboardFocus.ValueOrDefault,
                                        TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        string where = "";
        try { where = dialog.Automation.FocusedElement()?.Properties.AutomationId.ValueOrDefault ?? ""; } catch { }
        Assert.True(focused, $"{question} opened with the focus on \"{where}\", not on its Cancel");
    }

    // ---- The quit question (quittingWhileWorkIsUnderWay.buttons: default null, escape keepWorking) ----

    private static AutomationElement? QuitQuestion(DrivenApp app)
    {
        var dialog = app.OpenDialog();
        if (dialog is null) return null;
        var keep = dialog.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"));
        return keep?.Name == QuitConfirmation.KeepWorking ? dialog : null;
    }

    private static AutomationElement AskToQuit(DrivenApp app)
    {
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.TypeSimultaneously(VirtualKeyShort.ALT, VirtualKeyShort.F4);
        var quit = Retry.WhileNull(() => QuitQuestion(app), Patience).Result;
        Assert.True(quit is not null, "closing the window with a preview under way asked nothing");
        return quit!;
    }

    [UiFact]
    public void TheQuitQuestionOpensOnCancel_EnterAndEscapeBothKeepWorking()
    {
        using var app = new DrivenApp(courses => EndToEnd.WriteCourse(courses, Code, "Question Keys Course", new[] { "Concepts" }));
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);
        app.Find("previewButton", "the Preview button").AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => app.Find("previewButton", "the Preview button").Name == "Stop Preview",
                                     TimeSpan.FromSeconds(20)).Result, "the preview never started");

        var quit = AskToQuit(app);
        AssertTheFocusStartsOnCancel(quit, "the quit question");
        Press(app, VirtualKeyShort.RETURN);
        Assert.True(Retry.WhileFalse(() => QuitQuestion(app) is null, Patience).Result,
                    "Enter left the quit question up");
        Thread.Sleep(1500);
        Assert.True(app.Window.IsAvailable, "Enter on the quit question quit the app");

        AskToQuit(app);
        Press(app, VirtualKeyShort.ESCAPE);
        Assert.True(Retry.WhileFalse(() => QuitQuestion(app) is null, Patience).Result,
                    "Escape left the quit question up");
        Thread.Sleep(1500);
        Assert.True(app.Window.IsAvailable, "Escape on the quit question quit the app");

        string trail = MenuBar.Trail(app);
        int keptWorking = trail.Split("the teacher " + QuitConfirmation.ChoseToKeepWorking).Length - 1;
        Assert.True(keptWorking >= 2, $"the trail says the teacher kept working {keptWorking} times, not 2");
    }

    // ---- Remove a course (the mac's destructive alert: Return does nothing, Escape is Cancel) ----

    [UiFact]
    public void RemoveOpensOnCancel_AndNeitherEnterNorEscapeRemovesTheCourse()
    {
        using var app = new DrivenApp(ReferenceCourseUiTests.WriteCourses);
        foreach (var key in new[] { VirtualKeyShort.RETURN, VirtualKeyShort.ESCAPE })
        {
            app.SelectCourse("ICS3U");
            Press(app, VirtualKeyShort.DELETE);
            var asked = Retry.WhileNull(() => app.OpenDialog(), Patience, TimeSpan.FromMilliseconds(200)).Result;
            Assert.True(asked is not null, "Delete on a course row asked nothing");
            Assert.Equal("Remove ICS3U?", asked!.Name);
            AssertTheFocusStartsOnCancel(asked, "Remove ICS3U?");

            Press(app, key);
            Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, Patience, TimeSpan.FromMilliseconds(200)).Result,
                        $"{key} left Remove ICS3U? up");
            Thread.Sleep(1000);
            Assert.True(app.FindOrNull("sidebar-ICS3U", TimeSpan.FromSeconds(3)) is not null, $"{key} removed ICS3U");
        }
    }

    // ---- The New Course wizard (the mac's D32, the #987 review, and Russell's 2026-11-18 ruling) ----

    private const string FreshCode = "MFM2P";

    [UiFact]
    public void EnterWithTheCodeListDrawnMakesNothing_AndOnACompleteFormCreatesTheCourse()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        NewCourseWizardUiTests.OpenWizard(app);
        var box = app.Find("newCourseCodeBox", "the course-code picker");
        var edit = Retry.WhileNull(() => box.FindFirstDescendant(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.Edit)),
                                   Patience, TimeSpan.FromMilliseconds(200)).Result!;
        Assert.True(Retry.WhileFalse(() => edit.Properties.HasKeyboardFocus.ValueOrDefault, TimeSpan.FromSeconds(5),
                                     TimeSpan.FromMilliseconds(200)).Result,
                    "the wizard did not open with the cursor in Course code");
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Type(FreshCode);
        Assert.True(Retry.WhileFalse(() => CopyAPageEscapeUiTests.ListIsDrawn(app), TimeSpan.FromSeconds(5),
                                     TimeSpan.FromMilliseconds(200)).Result, "typing a code drew no list");
        var create = app.Find("PrimaryButton", "the wizard's Create button");
        Assert.True(Retry.WhileFalse(() => create.IsEnabled, TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result,
                    $"Create never became available for {FreshCode}");
        var name = app.Find("newCourseNameBox", "the course name box");
        Assert.True(Retry.WhileFalse(() => (name.Patterns.Value.Pattern.Value.Value ?? "").Trim().Length > 0,
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    "the course name was never filled in for " + FreshCode);

        // The list is drawn: Enter belongs to the field, never to Create Course.
        Assert.True(CopyAPageEscapeUiTests.ListIsDrawn(app), "the code list was put away before Enter was pressed");
        Press(app, VirtualKeyShort.RETURN);
        Thread.Sleep(1500);
        Assert.True(app.FindOrNull("taskPhaseLabel", TimeSpan.FromMilliseconds(500)) is null,
                    "Enter with the code list drawn created the course");
        Assert.NotNull(app.FindOrNull("newCourseDialog", TimeSpan.FromSeconds(1)));

        // The form is complete and no list is drawn: Enter in the name box is Create Course.
        if (CopyAPageEscapeUiTests.ListIsDrawn(app)) Press(app, VirtualKeyShort.ESCAPE);
        Assert.False(CopyAPageEscapeUiTests.ListIsDrawn(app), "the code list stayed drawn");
        name.Focus();
        Assert.True(Retry.WhileFalse(() => name.Properties.HasKeyboardFocus.ValueOrDefault, TimeSpan.FromSeconds(5),
                                     TimeSpan.FromMilliseconds(200)).Result, "the name box never took the focus");
        Press(app, VirtualKeyShort.RETURN);
        NewCourseWizardUiTests.WaitForTheWorkToFinish(app);
        Assert.True(File.Exists(Path.Combine(app.WorkspacePath, "courses", FreshCode, "course_config.json")),
                    "Enter on the complete form made no course");
    }

    [UiFact]
    public void EscapeWhileTheCourseIsBeingMadeDoesNothing_AndClosesTheWizardOnceItIsMade()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        NewCourseWizardUiTests.OpenWizard(app);
        NewCourseWizardUiTests.PutCodeIn(app, FreshCode);
        var create = app.Find("PrimaryButton", "the wizard's Create button");
        Assert.True(Retry.WhileFalse(() => create.IsEnabled, TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result,
                    $"Create never became available for {FreshCode}");
        create.AsButton().Invoke();
        Assert.True(Retry.WhileNull(() => app.FindOrNull("taskPhaseLabel", TimeSpan.FromMilliseconds(300)),
                                    TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(100)).Result is not null,
                    "Create was pressed but the wizard never started work");

        bool stillMaking = !app.Find("PrimaryButton", "the wizard's closing button").IsEnabled;
        Press(app, VirtualKeyShort.ESCAPE);
        Assert.True(stillMaking, "the course was made before Escape could be pressed, so this run proves nothing");
        Assert.True(app.FindOrNull("newCourseDialog", TimeSpan.FromSeconds(1)) is not null,
                    "Escape while the course was being made closed the wizard");
        NewCourseWizardUiTests.WaitForTheWorkToFinish(app);
        Assert.True(File.Exists(Path.Combine(app.WorkspacePath, "courses", FreshCode, "section1", "index.md")),
                    "Escape while the course was being made stopped it");

        Press(app, VirtualKeyShort.ESCAPE);
        Assert.True(Retry.WhileFalse(() => app.FindOrNull("newCourseDialog", TimeSpan.FromMilliseconds(300)) is null,
                                     Patience, TimeSpan.FromMilliseconds(200)).Result,
                    "Escape once the course was made did not close the wizard");
    }
}
