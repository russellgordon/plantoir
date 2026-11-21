using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Plantoir.Core.Scripting;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #1022 item 1 and #928 item 5, in the window: a preview whose run cannot
/// start says so under "Cannot Preview Yet" in Plantoir's own words (no file,
/// no system text), the console keeps the sentence, and the wait, the build
/// record and the lease go back at once, so the next Preview starts. The run
/// is made not to start the nearest real way: the folder's launcher is moved
/// aside before the press, so the press's checks pass, the run is asked for,
/// and <c>ScriptRunner.Run</c> finds no launcher (its <c>LaunchProblem</c>,
/// no exit code). Before #1022 that press did nothing and said nothing.
/// </summary>
public class PreviewThatCannotStartUiTests
{
    private const string Code = "UINOSTART";
    private const string Title = "Cannot Preview Yet";
    private readonly ITestOutputHelper _output;

    public PreviewThatCannotStartUiTests(ITestOutputHelper output) => _output = output;

    private static bool PreviewRuns(DrivenApp app) => app.Find("previewButton", "the Preview button").Name == "Stop Preview";

    private static AutomationElement? TheAlert(DrivenApp app) =>
        app.OpenDialog() is { } dialog && dialog.Name == Title ? dialog : null;

    [UiFact]
    public void APreviewThatCannotStartSaysSo_AndTheNextPreviewStarts()
    {
        using var app = new DrivenApp(courses => EndToEnd.WriteCourse(courses, Code, "Cannot Start Course", new[] { "Concepts" }));
        app.SelectSection(Code, 1);
        string launcher = Path.Combine(app.WorkspacePath, "preview.ps1");
        string aside = launcher + ".aside";
        File.Move(launcher, aside);

        app.Find("previewButton", "the Preview button").AsButton().Invoke();
        Assert.True(app.WaitAnsweringDialogs(() => TheAlert(app) is not null, TimeSpan.FromSeconds(60), except: Title),
                    "no \"Cannot Preview Yet\" came up for a run that could not start" + app.AnsweredSoFar);
        var alert = TheAlert(app)!;
        var said = DrivenApp.TextsUnder(alert);
        _output.WriteLine("the alert said: " + string.Join(" | ", said));
        Assert.Contains(ScriptRunner.FolderIsMissingAPiece, said);
        foreach (string text in said)
            Assert.DoesNotContain(".ps1", text, StringComparison.OrdinalIgnoreCase);
        var ok = alert.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"));
        Assert.True(ok is not null && ok.Name == "OK", "the alert's button is not a real, named OK button");
        CaptureFor(app, "1022-cannot-preview-yet.png");
        MenuBar.CloseDialog(app);

        // The console keeps the sentence; nothing is waiting and the button reads Preview.
        Assert.Contains(ScriptRunner.FolderIsMissingAPiece, DrivenApp.TextsUnder(app.Window));
        Assert.False(PreviewRuns(app), "the Preview button reads Stop for a run that never started");
        string trail = MenuBar.Trail(app);
        Assert.Contains("preview could not start", trail);
        Assert.Contains("the working folder has no preview.ps1", trail);

        // The launcher is back: the next press is not swallowed.
        File.Move(aside, launcher);
        app.WillServe(Code, 1);
        app.Find("previewButton", "the Preview button").AsButton().Invoke();
        Assert.True(app.WaitAnsweringDialogs(() => PreviewRuns(app), TimeSpan.FromSeconds(60)),
                    "the Preview after a run that could not start did not start" + app.AnsweredSoFar);
        Assert.DoesNotContain("preview already starting", MenuBar.Trail(app));
    }

    /// <summary>A picture of the window with the alert up, for the review, in the temp folder's <c>plantoir-ui-captures</c>.</summary>
    private void CaptureFor(DrivenApp app, string fileName)
    {
        string folder = Path.Combine(Path.GetTempPath(), "plantoir-ui-captures");
        try
        {
            Directory.CreateDirectory(folder);
            FlaUI.Core.Capturing.Capture.Element(app.Window).ToFile(Path.Combine(folder, fileName));
            _output.WriteLine("captured " + Path.Combine(folder, fileName));
        }
        catch (Exception problem) { _output.WriteLine("no capture: " + problem.Message); }
    }
}
