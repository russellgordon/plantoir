using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Models;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #1009 (the mac's #988), with real keys pressed in the real window: Escape
/// on a running preview stops it at once; Escape on a running deploy asks
/// "Stop the deploy?"; Enter or Space on the question's focused Cancel, and
/// Escape, keep the deploy running and remember nothing, the box included;
/// Enter with the question's own first focus is Stop Deploy, the default;
/// Stop Deploy with Don't ask again ticked turns the question off, and the
/// next Escape stops at once; while an editable text box has the focus,
/// Escape is the box's, and a UI Automation Invoke on Cancel still stops.
/// </summary>
/// <remarks>
/// Each key press brings the app to the front first (see
/// <see cref="CopyAPageEscapeUiTests"/>). Without the change, Escape does
/// nothing to a running task, so every test here fails at its first press.
/// The deploy is the real build and <c>deploy.ps1 --to-folder</c>, padded so
/// it outlasts the questions (as <see cref="ReturningToASectionMidDeployUiTests"/>).
/// </remarks>
[Collection("drives the real app")]
public class StopByKeyboardUiTests
{
    private const string Code = "STPKY";
    private static readonly TimeSpan Patience = TimeSpan.FromSeconds(15);
    private static readonly int PaddingPages =
        int.TryParse(Environment.GetEnvironmentVariable("PLANTOIR_UI_PADDING_PAGES"), out int pages) && pages > 0 ? pages : 600;

    private readonly ITestOutputHelper _output;
    public StopByKeyboardUiTests(ITestOutputHelper output) => _output = output;

    /// <summary>What a run measured, also in <c>%TEMP%\plantoir-1009-measurement.txt</c>, since a passing test's output is not printed.</summary>
    private void Measured(string what)
    {
        _output.WriteLine("measured: " + what);
        try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "plantoir-1009-measurement.txt"), $"{DateTime.Now:s} {what}{Environment.NewLine}"); } catch { }
    }

    private static void Press(DrivenApp app, VirtualKeyShort key)
    {
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Type(key);
        Thread.Sleep(700);
    }

    private static string Phase(DrivenApp app) => app.FindOrNull("taskPhaseLabel", TimeSpan.FromMilliseconds(300))?.Name ?? "";

    private static bool CancelShows(DrivenApp app) => app.FindOrNull("taskCancelButton", TimeSpan.FromMilliseconds(300)) is { IsOffscreen: false };

    private static AutomationElement? OpenStopQuestion(DrivenApp app) =>
        app.OpenDialog() is { } dialog && dialog.Name == StopQuestionWording.DeployTitle ? dialog : null;

    private static AutomationElement Asked(DrivenApp app, string after)
    {
        var dialog = Retry.WhileNull(() => OpenStopQuestion(app), Patience, TimeSpan.FromMilliseconds(200)).Result;
        Assert.True(dialog is not null, $"{after} asked nothing: no \"{StopQuestionWording.DeployTitle}\"");
        return dialog!;
    }

    private static void AssertGone(DrivenApp app, string after) =>
        Assert.True(Retry.WhileFalse(() => OpenStopQuestion(app) is null, Patience, TimeSpan.FromMilliseconds(200)).Result,
                    $"{after} left the question up");

    private void AssertStillDeploying(DrivenApp app, string after)
    {
        Thread.Sleep(1500);
        Assert.True(CancelShows(app) && Phase(app) != "Cancelled", $"{after} stopped the deploy (phase \"{Phase(app)}\")");
    }

    private static void AssertCancelled(DrivenApp app, string after) =>
        Assert.True(Retry.WhileFalse(() => Phase(app) == "Cancelled", TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result,
                    $"{after} did not stop the deploy (phase \"{Phase(app)}\")");

    private static string Focused(AutomationElement dialog)
    {
        try
        {
            var focused = dialog.Automation.FocusedElement();
            return $"{focused?.Properties.AutomationId.ValueOrDefault} \"{focused?.Name}\"";
        }
        catch { return "(unread)"; }
    }

    private static bool AskedSetting(DrivenApp app)
    {
        string text = File.ReadAllText(Path.Combine(app.StateDirectory, "settings.json"));
        return !text.Replace(" ", "").Contains("\"AsksBeforeStoppingADeploy\":false");
    }

    private void StartDeploy(DrivenApp app, int which)
    {
        app.Find("deployButton", "the Deploy button").AsButton().Invoke();
        Assert.True(app.WaitAnsweringDialogs(() => CancelShows(app), TimeSpan.FromSeconds(90)),
                    $"deploy {which} never showed its Cancel" + app.AnsweredSoFar);
        // The Deploy button keeps the focus after Invoke; Escape must not depend on where it is.
        Measured($"deploy {which} running, phase \"{Phase(app)}\"");
    }

    private static void WriteCourse(string courses, out string published)
    {
        published = Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(courses)!)!, "published");
        Directory.CreateDirectory(published);
        string dir = EndToEnd.WriteCourse(courses, Code, "Stop By Keyboard", new[] { "Concepts" }, EndToEnd.PublishesTo(published));
        for (int page = 1; page <= PaddingPages; page++)
            EndToEnd.WritePage(Path.Combine(dir, "Concepts", $"Padding {page:0000}.md"),
                $"title: Padding {page:0000}\npublish: true", $"A page to make the build take a while ({page}).");
    }

    [UiFact]
    public void EscapeOnADeployAsks_CancelKeepsItRunning_AndDontAskAgainCountsOnlyWithStop()
    {
        string published = "";
        using var app = new DrivenApp(courses => WriteCourse(courses, out published));
        app.SelectSection(Code, 1);

        // ---- Deploy 1: the question, and every way of backing out.
        StartDeploy(app, 1);
        Press(app, VirtualKeyShort.ESCAPE);
        var asked = Asked(app, "Escape on a running deploy");
        Measured($"the question opened with the focus on {Focused(asked)}");
        Assert.Equal(StopQuestionWording.DeployStopButton, asked.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))?.Name);
        Assert.Equal(StopQuestionWording.CancelButton, asked.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))?.Name);
        Assert.Contains(StopQuestionWording.DeployMessage, DrivenApp.TextsUnder(asked));
        var box = asked.FindFirstDescendant(cf => cf.ByAutomationId("stopQuestionDontAskAgain"))?.AsCheckBox();
        Assert.True(box is not null, "the question has no Don't ask again box");
        Assert.Equal(StopQuestionWording.DontAskAgain, box!.Name);
        Assert.False(box.IsChecked == true, "Don't ask again opened ticked");

        // Enter, then Space, on the focused Cancel: the deploy runs on.
        foreach (var key in new[] { VirtualKeyShort.RETURN, VirtualKeyShort.SPACE })
        {
            var dialog = OpenStopQuestion(app) ?? Asked(app, "Escape on a running deploy");
            dialog.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.Focus();
            Thread.Sleep(400);
            Press(app, key);
            AssertGone(app, $"{key} on the focused Cancel");
            AssertStillDeploying(app, $"{key} on the focused Cancel");
            Press(app, VirtualKeyShort.ESCAPE);
            Asked(app, $"Escape after {key} on Cancel");
        }

        // Ticked and then Escape (the question's Cancel): nothing remembered.
        var withBox = Asked(app, "Escape");
        withBox.FindFirstDescendant(cf => cf.ByAutomationId("stopQuestionDontAskAgain"))!.AsCheckBox().Toggle();
        Thread.Sleep(400);
        Press(app, VirtualKeyShort.ESCAPE);
        AssertGone(app, "Escape on the question");
        AssertStillDeploying(app, "Escape on the question");
        Assert.True(AskedSetting(app), "Don't ask again ticked with Cancel was remembered");

        // Asked again, the box unticked; Enter with the question's own first focus is Stop Deploy.
        Press(app, VirtualKeyShort.ESCAPE);
        var again = Asked(app, "Escape after Cancel with the box ticked");
        Assert.False(again.FindFirstDescendant(cf => cf.ByAutomationId("stopQuestionDontAskAgain"))!.AsCheckBox().IsChecked == true,
                     "the box kept its tick from the last time");
        Measured($"asked again, the focus is on {Focused(again)}");
        Press(app, VirtualKeyShort.RETURN);
        AssertGone(app, "Enter on the question");
        AssertCancelled(app, "Enter (Stop Deploy, the default)");
        Assert.True(AskedSetting(app), "Stop Deploy with the box unticked turned the question off");

        // ---- Deploy 2: Stop Deploy with the box ticked turns the question off.
        StartDeploy(app, 2);
        Press(app, VirtualKeyShort.ESCAPE);
        var ticked = Asked(app, "Escape on deploy 2");
        ticked.FindFirstDescendant(cf => cf.ByAutomationId("stopQuestionDontAskAgain"))!.AsCheckBox().Toggle();
        Thread.Sleep(400);
        ticked.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.AsButton().Invoke();
        AssertGone(app, "Stop Deploy");
        AssertCancelled(app, "Stop Deploy");
        Assert.False(AskedSetting(app), "Stop Deploy with Don't ask again ticked left the question on");
        string line = StopQuestionWording.TrailLine(StopQuestion.Deploy, false, StopQuestionChangedFrom.DontAskAgain);
        Assert.True(Retry.WhileFalse(() => MenuBar.Trail(app).Contains(line), TimeSpan.FromSeconds(5)).Result,
                    $"the trail has no \"{line}\"");

        // ---- Deploy 3: with the question off, Escape stops at once.
        StartDeploy(app, 3);
        Press(app, VirtualKeyShort.ESCAPE);
        AssertCancelled(app, "Escape with the question off");
        Assert.Null(OpenStopQuestion(app));
        Assert.False(File.Exists(Path.Combine(published, "section1", "index.html")), "a deploy finished, so it was never stopped");
    }

    [UiFact]
    public void EscapeStopsAPreviewAtOnce_ButNotFromAFocusedTextBox_WhereInvokeOnCancelStillStops()
    {
        using var app = new DrivenApp(courses => EndToEnd.WriteCourse(courses, Code, "Stop By Keyboard", new[] { "Concepts" }));
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);

        bool PreviewRuns() => app.Find("previewButton", "the Preview button").Name == "Stop Preview";
        void StartPreview()
        {
            app.Find("previewButton", "the Preview button").AsButton().Invoke();
            Assert.True(Retry.WhileFalse(() => PreviewRuns() && CancelShows(app), TimeSpan.FromSeconds(30), TimeSpan.FromMilliseconds(250)).Result,
                        "the preview never started" + app.AnsweredSoFar);
        }

        // ---- Escape in the console's answer box is the box's.
        StartPreview();
        app.Find("taskDetailsDisclosure", "Show details").AsButton().Invoke();
        var answerBox = app.Find("consoleInputField", "the console's answer box");
        app.ClickMiddleOf(answerBox);
        Thread.Sleep(400);
        Assert.True(answerBox.Properties.HasKeyboardFocus.ValueOrDefault, "the console's answer box did not take the focus");
        Press(app, VirtualKeyShort.ESCAPE);
        Thread.Sleep(1500);
        Assert.True(PreviewRuns(), "Escape in a focused text box stopped the preview");
        Assert.Null(app.OpenDialog());

        // ---- An Invoke on Cancel stops it, the box still focused.
        app.Find("taskCancelButton", "the panel's Cancel").AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => !PreviewRuns(), Patience, TimeSpan.FromMilliseconds(250)).Result,
                    "Invoke on Cancel did not stop the preview while a text box had the focus");
        Assert.Null(app.OpenDialog());

        // ---- Escape anywhere else stops a preview at once, with no question.
        StartPreview();
        app.Find("previewButton", "the Preview button").Focus();
        Thread.Sleep(400);
        Press(app, VirtualKeyShort.ESCAPE);
        Assert.True(Retry.WhileFalse(() => !PreviewRuns(), Patience, TimeSpan.FromMilliseconds(250)).Result,
                    "Escape did not stop the running preview");
        Assert.Null(app.OpenDialog());
    }
}
