using System.Text;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// The guidance question (#496) and the quit question meeting in one window
/// (the batch 5B implementation review's H-1): with the guidance question up
/// and a preview building, closing the window must bring up the quit
/// question — not the guidance question again, inside the quit question's
/// waits — and Keep Working must leave the guidance question to come back on
/// its own. Written 2026-10-15 with the desktop LOCKED: UNPROVEN until its
/// first run on an unlocked desktop.
/// </summary>
[Collection("drives the real app")]
public class GuidanceQuestionAndTheQuitQuestionUiTests
{
    private const string Code = "GDQ2O";
    private const string Own = "# My own notes for Claude\n\nAlways use British spelling.\n";
    private static readonly TimeSpan Patience = TimeSpan.FromSeconds(60);

    [UiFact]
    public void ClosingWithTheGuidanceQuestionUpAsksAboutTheWorkAndKeepWorkingBringsTheQuestionBack()
    {
        // The guidance question is asked when the folder's tools are copied,
        // which is before a preview can be started. So the FIRST pass is made
        // to fail — CLAUDE.md held open, unreadable — and the second, after a
        // preview has begun, finds it: a failed pass is tried again on the
        // next copy, and a recipe gone from disk is copied again on Reload.
        FileStream? held = null;
        using var app = new DrivenApp(
            courses => EndToEnd.WriteCourse(courses, Code, "Guidance Course", new[] { "Concepts" }),
            beforeLaunch: folder =>
            {
                string claude = Path.Combine(folder, "CLAUDE.md");
                File.WriteAllText(claude, Own, new UTF8Encoding(false));
                held = new FileStream(claude, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            });
        try
        {
            app.SelectSection(Code, 1);
            app.WillServe(Code, 1);
            app.Find("previewButton", "the Preview button").AsButton().Invoke();
            Assert.True(Retry.WhileFalse(() => app.Find("previewButton", "the Preview button").Name == "Stop Preview",
                                         TimeSpan.FromSeconds(20)).Result, "the preview never started");
        }
        finally { held?.Dispose(); }

        // The second pass: the recipe gone, File ▸ Reload Courses copies it again.
        File.Delete(Path.Combine(app.WorkspacePath, ".toolchain", ToolchainMirror.RecipeRootFiles[0]));
        EndToEnd.PressMenuBarItem(app, "File", "fileReloadCourses");
        Assert.NotNull(Retry.WhileNull(() => app.FindOrNull("guidanceAskDialog"), Patience).Result);

        app.BringToFront();
        Keyboard.TypeSimultaneously(VirtualKeyShort.ALT, VirtualKeyShort.F4);

        // The quit question, and only it: the guidance question did not come back inside its waits.
        var quit = Retry.WhileNull(() => QuitQuestion(app), TimeSpan.FromSeconds(10)).Result;
        Assert.NotNull(quit);
        Assert.Null(app.FindOrNull("guidanceAskDialog", TimeSpan.Zero));
        quit!.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton")).AsButton().Invoke();   // Keep Working

        Assert.True(Retry.WhileFalse(() => QuitQuestion(app) is null, TimeSpan.FromSeconds(5)).Result,
                    "the quit question did not go after Keep Working");
        Assert.True(app.Window.IsAvailable, "Keep Working closed the window");
        // Taken down unanswered, so it comes back — on the timer, after the quit question has gone.
        Assert.NotNull(Retry.WhileNull(() => app.FindOrNull("guidanceAskDialog"), TimeSpan.FromSeconds(15)).Result);
        Assert.Contains(QuitConfirmation.KeepWorking, MenuBar.Trail(app));
    }

    private static AutomationElement? QuitQuestion(DrivenApp app)
    {
        var dialog = app.OpenDialog();
        if (dialog is null) return null;
        return DrivenApp.TextsUnder(dialog).Any(text => text == QuitConfirmation.KeepWorking) ? dialog : null;
    }
}
