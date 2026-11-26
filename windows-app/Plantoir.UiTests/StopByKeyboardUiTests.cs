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
/// Escape is the box's, and a UI Automation Invoke on Cancel still reaches
/// the stop.
/// </summary>
/// <remarks>
/// Each key press brings the app to the front first (see
/// <see cref="CopyAPageEscapeUiTests"/>). Without the change, Escape does
/// nothing to a running task, so every test here fails at its first press.
/// The deploy is the real build and <c>deploy.ps1 --to-folder</c>, padded so
/// it outlasts the questions (as <see cref="ReturningToASectionMidDeployUiTests"/>),
/// or, where a test must not depend on how long the work takes, sent to a
/// folder the test holds (<see cref="HeldDestination"/>).
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

    /// <summary>
    /// A destination folder the deploy cannot finish until the test lets it
    /// go (#1009's fourth review, in place of a guessed amount of work): its
    /// section's <c>index.html</c>, left "by an earlier deploy", is held open
    /// with no sharing, so <c>robocopy /MIR</c> cannot replace it and waits to
    /// try again for as long as the file is held. The test waits on events
    /// only: the leg's start on the trail, then the stop it makes.
    /// </summary>
    private sealed class HeldDestination : IDisposable
    {
        private readonly FileStream _held;

        public HeldDestination(string folder)
        {
            Folder = folder;
            string section = Path.Combine(folder, "section1");
            Directory.CreateDirectory(section);
            string page = Path.Combine(section, "index.html");
            File.WriteAllText(page, LeftByAnEarlierDeploy);
            _held = new FileStream(page, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        }

        public const string LeftByAnEarlierDeploy = "left by an earlier deploy";

        public string Folder { get; }

        /// <summary>What the held page holds now, read through the test's own handle.</summary>
        public string HeldPage()
        {
            _held.Position = 0;
            var reader = new StreamReader(_held, leaveOpen: true);
            return reader.ReadToEnd();
        }

        public void Dispose() => _held.Dispose();
    }

    private static void WriteCourse(string courses, out string published) => WriteCourse(courses, out published, out _, padded: true);

    /// <summary>
    /// The course every deploy test here uses. Every destination is a folder
    /// in the test's own temp tree (#1009's third review): a host destination
    /// would make deploy.ps1 read this machine's real credential and publish
    /// for real, so no test in this class can reach an account on any machine.
    /// <paramref name="moreFolders"/> are destinations 2, 3 and on, after the
    /// first, <paramref name="published"/>.
    /// </summary>
    private static void WriteCourse(string courses, out string published, out string courseDirectory,
                                    bool padded, params string[] moreFolders)
    {
        published = PublishedFolder(courses);
        Directory.CreateDirectory(published);
        var toTheFolder = EndToEnd.PublishesTo(published);
        string dir = EndToEnd.WriteCourse(courses, Code, "Stop By Keyboard", new[] { "Concepts" }, config =>
        {
            toTheFolder(config);
            if (moreFolders.Length == 0) return;
            var targets = new System.Text.Json.Nodes.JsonArray();
            foreach (string folder in moreFolders)
                targets.Add(new System.Text.Json.Nodes.JsonObject { ["type"] = "local_folder", ["path"] = folder });
            config["additional_deploy_targets"] = targets;
        });
        courseDirectory = dir;
        if (!padded) return;
        for (int page = 1; page <= PaddingPages; page++)
            EndToEnd.WritePage(Path.Combine(dir, "Concepts", $"Padding {page:0000}.md"),
                $"title: Padding {page:0000}\npublish: true", $"A page to make the build take a while ({page}).");
    }

    /// <summary>A folder beside the test's working folder, in its own temp tree.</summary>
    private static string BesideTheWorkingFolder(string courses, string name) =>
        Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(courses)!)!, name);

    private static string PublishedFolder(string courses) => BesideTheWorkingFolder(courses, "published");

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

    private static bool PreviewRuns(DrivenApp app) => app.Find("previewButton", "the Preview button").Name == "Stop Preview";

    /// <summary>
    /// One preview per test: measured in the VM (2026-11-20), a second preview
    /// started straight after a stopped one ended by itself with "Something
    /// went wrong", so a second start in one run cannot carry an assertion.
    /// </summary>
    private static DrivenApp StartAPreview()
    {
        var app = new DrivenApp(courses => EndToEnd.WriteCourse(courses, Code, "Stop By Keyboard", new[] { "Concepts" }));
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);
        app.Find("previewButton", "the Preview button").AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => PreviewRuns(app) && CancelShows(app), TimeSpan.FromSeconds(30), TimeSpan.FromMilliseconds(250)).Result,
                    "the preview never started" + app.AnsweredSoFar);
        return app;
    }

    /// <summary>The trail's lines about preview.ps1, for a failure message.</summary>
    private static string PreviewTrailLines(DrivenApp app)
    {
        var lines = new List<string>();
        foreach (string line in MenuBar.Trail(app).Split('\n'))
        {
            if (line.Contains("preview.ps1", StringComparison.Ordinal)) lines.Add(line.Trim());
        }
        return lines.Count == 0 ? "none" : string.Join(" / ", lines);
    }

    private static void AssertStopped(DrivenApp app, string after)
    {
        // The phase, or the trail: the console of a preview stopped before it
        // wrote anything goes away with it, taking its phase along, and the
        // trail's line waits for the launcher to end. "Cancelled" is shown
        // only for a stop the teacher asked for (ScriptRunner.CancelByUser).
        Assert.True(Retry.WhileFalse(() => Phase(app) is "Stopped" or "Cancelled"
                                           || MenuBar.Trail(app).Contains("finished preview.ps1 — stopped by the teacher"),
                                     TimeSpan.FromSeconds(30), TimeSpan.FromMilliseconds(250)).Result,
                    $"{after} did not stop the running preview (phase \"{Phase(app)}\", Preview button \"{app.Find("previewButton", "the Preview button").Name}\", the trail's preview lines: {PreviewTrailLines(app)})");
        Assert.False(PreviewRuns(app), $"the preview still runs after {after}");
        Assert.Null(app.OpenDialog());
    }

    [UiFact]
    public void EscapeStopsARunningPreviewAtOnce()
    {
        using var app = StartAPreview();
        app.Find("previewButton", "the Preview button").Focus();
        Thread.Sleep(400);
        Assert.True(PreviewRuns(app) && CancelShows(app), $"the preview ended by itself before Escape (phase \"{Phase(app)}\")");
        Press(app, VirtualKeyShort.ESCAPE);
        AssertStopped(app, "Escape");
    }

    /// <summary>
    /// While an editable text box has the focus, Escape is the box's; a UI
    /// Automation Invoke on Cancel still reaches the stop (for a deploy, its
    /// question, and Stop Deploy then stops it). Run on a deploy held by the
    /// test (<see cref="HeldDestination"/>), where no site is ever drawn
    /// (#1009's fourth review). It used to run on a preview, and failed in
    /// the VM: measured there (2026-11-20, scratch test), the answer box kept
    /// the focus when the preview's site was drawn (no focus taken from it),
    /// but the site drew about 35 s after the start, inside the test's
    /// presses, so a press could land after it: the site then covers the
    /// console (Escape there is never Cancel's, so the box rule went
    /// untested), and a stop of a serving preview ends without the "stopped by
    /// the teacher" line the test waited for (the run's line then read
    /// "succeeded", because preview.ps1 exits 0 on Control-C; since the fifth
    /// review the outcome is "stopped by the teacher" whatever the exit code,
    /// ScriptRunner.FinishedOutcome). A deploy held on its destination cannot
    /// end, or draw anything, until the test stops it.
    /// </summary>
    [UiFact]
    public void EscapeInAFocusedTextBoxIsTheBoxs_AndInvokeOnCancelStillStops()
    {
        string published = "";
        HeldDestination? held = null;
        using var app = new DrivenApp(courses =>
        {
            held = new HeldDestination(PublishedFolder(courses));
            WriteCourse(courses, out published, out _, padded: false);
        });
        using var release = held!;
        app.SelectSection(Code, 1);
        StartDeploy(app, 1);
        // The deploy itself has begun, and cannot finish while the folder is held.
        Assert.True(Retry.WhileFalse(() => DeployStarts(app) >= 1, TimeSpan.FromMinutes(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"the deploy never reached its destination (phase \"{Phase(app)}\")");
        app.Find("taskDetailsDisclosure", "Show details").AsButton().Invoke();
        var answerBox = app.Find("consoleInputField", "the console's answer box");
        app.ClickMiddleOf(answerBox);
        Assert.True(Retry.WhileFalse(() => answerBox.Properties.HasKeyboardFocus.ValueOrDefault, TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(100)).Result,
                    "the console's answer box did not take the focus");
        Assert.True(CancelShows(app), $"the deploy is not shown running before Escape (phase \"{Phase(app)}\")");
        Press(app, VirtualKeyShort.ESCAPE);
        AssertStillDeploying(app, "Escape in a focused text box");
        Assert.Null(app.OpenDialog());

        Assert.True(answerBox.Properties.HasKeyboardFocus.ValueOrDefault, "the answer box lost the focus before the Invoke");
        app.Find("taskCancelButton", "the panel's Cancel").AsButton().Invoke();
        Asked(app, "Invoke on Cancel with a text box focused")
            .FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.AsButton().Invoke();
        AssertGone(app, "Stop Deploy after Invoke on Cancel");
        AssertCancelled(app, "Invoke on Cancel with a text box focused, then Stop Deploy");
        Assert.Equal(HeldDestination.LeftByAnEarlierDeploy, held!.HeldPage());
    }

    // ---- #1009's first review: every route asks, one "under way" rule, a held Escape ----

    private static bool DeployPhaseStarted(DrivenApp app) => MenuBar.Trail(app).Contains($"started deploy.ps1 {Code} 1");

    private void AssertNotPublished(string published, string after) =>
        Assert.False(File.Exists(Path.Combine(published, "section1", "index.html")), $"{after}: the deploy finished, so it was never stopped");

    /// <summary>
    /// The console's own Stop, beside its answer box, asks as Cancel does, and
    /// Stop Deploy then ends the deploy "Cancelled" (the section's sweep, as
    /// Cancel's). Before the change it killed the deploy with no question.
    /// </summary>
    [UiFact]
    public void TheConsolesStopOnADeployAsks_AndStopDeployCancelsIt()
    {
        string published = "";
        using var app = new DrivenApp(courses => WriteCourse(courses, out published));
        app.SelectSection(Code, 1);
        StartDeploy(app, 1);
        app.Find("taskDetailsDisclosure", "Show details").AsButton().Invoke();
        var stop = app.Find("consoleStopButton", "the console's Stop");
        stop.AsButton().Invoke();
        var asked = Asked(app, "the console's Stop on a running deploy");
        Thread.Sleep(400);
        AssertStillDeploying(app, "the console's Stop with the question up");
        asked.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.AsButton().Invoke();
        AssertGone(app, "Cancel on the question");
        AssertStillDeploying(app, "Cancel on the question the console's Stop opened");

        app.Find("consoleStopButton", "the console's Stop").AsButton().Invoke();
        Asked(app, "the console's Stop, again").FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.AsButton().Invoke();
        AssertGone(app, "Stop Deploy");
        AssertCancelled(app, "Stop Deploy after the console's Stop");
        AssertNotPublished(published, "the console's Stop");
    }

    /// <summary>
    /// A held Escape: the first press opens the question; the key's repeats
    /// must not answer it (Microsoft: an accelerator repeats while the key is
    /// held, and a ContentDialog closes on Escape).
    /// </summary>
    [UiFact]
    public void AHeldEscapeOpensTheQuestion_AndItsRepeatsDoNotAnswerIt()
    {
        string published = "";
        using var app = new DrivenApp(courses => WriteCourse(courses, out published));
        app.SelectSection(Code, 1);
        StartDeploy(app, 1);
        // A held key, as the keyboard sends it: one press, then after the
        // repeat delay a key-down about every 33 ms with no key-up between
        // (SendInput of a key already down is a repeat: its previous-state
        // bit is set). Holding the key with one SendInput sends no repeats.
        // Measured: a repeat closed the question in 1 run of 3 at first, so
        // the hold is tried with four repeat delays, each from a fresh press.
        var closedBy = new List<int>();
        foreach (int delay in new[] { 250, 400, 500, 650 })
        {
            CopyAPageEscapeUiTests.Front(app);
            bool openBeforeTheRepeats = false;
            HeldKeys.HoldWithRepeats(VirtualKeyShort.ESCAPE, firstDelayMs: delay, repeats: 45, repeatMs: 33,
                whileHeld: () => openBeforeTheRepeats = OpenStopQuestion(app) is not null);
            Thread.Sleep(700);
            bool open = OpenStopQuestion(app) is not null;
            Measured($"a held Escape (repeats after {delay} ms, 45 of them): question {(openBeforeTheRepeats ? "open" : "not yet open")} before the repeats, {(open ? "still open" : "gone")} after, phase \"{Phase(app)}\"");
            if (!open) closedBy.Add(delay);
            AssertStillDeploying(app, $"a held Escape (repeats after {delay} ms)");
            if (open)
            {
                // A fresh Escape, after the release, is the question's Cancel as before.
                Press(app, VirtualKeyShort.ESCAPE);
                AssertGone(app, "Escape after a held Escape");
            }
        }
        Assert.True(closedBy.Count == 0, $"a held Escape opened the question and its repeats closed it (repeats after {string.Join(", ", closedBy)} ms)");
        Press(app, VirtualKeyShort.ESCAPE);
        Press(app, VirtualKeyShort.RETURN);
        AssertCancelled(app, "Enter (Stop Deploy) after a held Escape");
        AssertNotPublished(published, "a held Escape");
    }

    /// <summary>
    /// A deploy that builds first runs both halves on one runner, with a gap
    /// between: the question opened during the build stays up across the
    /// change to the deploy, and Stop Deploy then stops the deploy. Before the
    /// change the question was taken down when the build finished.
    /// </summary>
    [UiFact]
    public void TheQuestionStaysAcrossTheBuildToDeployChange_AndStopDeployStopsTheDeploy()
    {
        string published = "";
        using var app = new DrivenApp(courses => WriteCourse(courses, out published));
        app.SelectSection(Code, 1);
        StartDeploy(app, 1);
        Assert.False(DeployPhaseStarted(app), "the deploy half began before the build was seen; nothing here tests the change");
        Press(app, VirtualKeyShort.ESCAPE);
        var asked = Asked(app, "Escape during the build");
        var started = DateTime.Now;
        Assert.True(Retry.WhileFalse(() => DeployPhaseStarted(app), TimeSpan.FromMinutes(10), TimeSpan.FromMilliseconds(200)).Result,
                    "the build never reached the deploy");
        Measured($"the build ended {(DateTime.Now - started).TotalSeconds:0.0} s after the question opened; question {(OpenStopQuestion(app) is null ? "gone" : "open")}");
        Assert.True(OpenStopQuestion(app) is not null, "the question was taken down when the build finished, though the deploy went on");
        asked.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.AsButton().Invoke();
        AssertGone(app, "Stop Deploy across the change");
        AssertCancelled(app, "Stop Deploy across the change");
        AssertNotPublished(published, "Stop Deploy across the change");
    }

    private static int DeployStarts(DrivenApp app)
    {
        string trail = MenuBar.Trail(app);
        string started = $"started deploy.ps1 {Code} 1";
        int count = 0;
        int at = trail.IndexOf(started, StringComparison.Ordinal);
        while (at >= 0)
        {
            count += 1;
            at = trail.IndexOf(started, at + started.Length, StringComparison.Ordinal);
        }
        return count;
    }

    /// <summary>
    /// #1009's second review: a course that deploys to several folders runs a
    /// leg each, and between two of them the shown leg's runner has stopped
    /// before the run moves on. The question opened during destination 1
    /// stays up across the change to destination 2, and Stop Deploy then
    /// stops the deploy. Its fourth review: three folders, stopped during the
    /// second, so a later leg is left that could start (two legs stopped
    /// during the second had none, and that half could never fail); and
    /// destinations 1 and 2 are held by the test (<see cref="HeldDestination"/>)
    /// instead of a padded build and files to remove, so neither can end
    /// before the test lets it, whatever the machine's speed: the question is
    /// opened while destination 1 is held, destination 1 is let go, and the
    /// stop lands while destination 2 is held. The stopped deploy writes no
    /// published stamp, so the section keeps its " — Edited" (the third review).
    /// </summary>
    [UiFact]
    public void TheQuestionStaysAcrossTheChangeOfDestination_AndStopDeployStartsNoLaterOne()
    {
        string published = "";
        string courseDirectory = "";
        string thirdFolder = "";
        HeldDestination? first = null;
        HeldDestination? second = null;
        using var app = new DrivenApp(courses =>
        {
            first = new HeldDestination(PublishedFolder(courses));
            second = new HeldDestination(BesideTheWorkingFolder(courses, "published-second"));
            thirdFolder = BesideTheWorkingFolder(courses, "published-third");
            // A folder destination must exist to be deployed to.
            Directory.CreateDirectory(thirdFolder);
            WriteCourse(courses, out published, out courseDirectory, padded: false, second.Folder, thirdFolder);
        });
        // Let go before the app's own clean-up, which deletes the temp tree.
        using var releaseTheSecond = second!;
        using var releaseTheFirst = first!;
        app.SelectSection(Code, 1);
        StartDeploy(app, 1);
        Assert.True(Retry.WhileFalse(() => DeployStarts(app) >= 1, TimeSpan.FromMinutes(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"the deploy never reached destination 1 (phase \"{Phase(app)}\")");
        Press(app, VirtualKeyShort.ESCAPE);
        var asked = Asked(app, "Escape during destination 1");
        Assert.True(DeployStarts(app) == 1, $"the question opened after destination 1 ({DeployStarts(app)} deploys started)");

        // Destination 1 let go: it finishes, and the run moves on to destination 2.
        var released = DateTime.Now;
        first!.Dispose();
        Assert.True(Retry.WhileFalse(() => DeployStarts(app) >= 2, TimeSpan.FromMinutes(3), TimeSpan.FromMilliseconds(200)).Result,
                    $"the deploy never reached destination 2 (deploys started: {DeployStarts(app)}, phase \"{Phase(app)}\")");
        bool openAtTheChange = OpenStopQuestion(app) is not null;
        int startsAtTheStop = DeployStarts(app);
        Measured($"destination 2 began {(DateTime.Now - released).TotalSeconds:0.0} s after destination 1 was let go; question {(openAtTheChange ? "open" : "gone")}, phase \"{Phase(app)}\", deploys started {startsAtTheStop}");
        Assert.NotEqual(HeldDestination.LeftByAnEarlierDeploy, File.ReadAllText(Path.Combine(published, "section1", "index.html")));
        Assert.True(openAtTheChange, "the question was taken down when destination 1 finished, though the deploy went on to destination 2");
        Assert.True(startsAtTheStop == 2, $"the stop is not during destination 2 ({startsAtTheStop} deploys started)");
        Assert.Equal(HeldDestination.LeftByAnEarlierDeploy, second!.HeldPage());

        asked.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))!.AsButton().Invoke();
        AssertGone(app, "Stop Deploy during destination 2");
        AssertCancelled(app, "Stop Deploy during destination 2");
        // The run's own end, an event: Deploy is offered again only once it has ended.
        Assert.True(Retry.WhileFalse(() => app.Find("deployButton", "the Deploy button").IsEnabled, TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result,
                    "the deploy run never ended after Stop Deploy");
        Assert.True(DeployStarts(app) == startsAtTheStop, $"destination 3 started after Stop Deploy ({startsAtTheStop} deploys started at the stop, {DeployStarts(app)} after)");
        Assert.False(File.Exists(Path.Combine(thirdFolder, "section1", "index.html")), "destination 3 got the site after Stop Deploy");
        Assert.False(CancelShows(app), "Cancel still shows after the deploy was stopped");
        // The stopped outcome (#1009's third review): no stamp, so the section keeps its " — Edited".
        Assert.False(File.Exists(SectionPublishState.StampPath(courseDirectory, 1)),
                     "the deploy stopped during destination 2 of 3 stamped the section as published");
    }

    /// <summary>
    /// The console's own Stop in the New Course wizard (no stop question
    /// there): it stops the wizard's work at once, as the teacher's stop,
    /// so it ends "Cancelled" (<c>ScriptRunner.CancelByUser</c>). Before
    /// #1009's first review it killed the process (<c>Terminate</c>), which
    /// read as "Something went wrong".
    /// </summary>
    [UiFact]
    public void TheConsolesStopInTheNewCourseWizardStopsAtOnce_AsTheTeachersStop()
    {
        using var app = new DrivenApp(courses => EndToEnd.WriteCourse(courses, Code, "Stop By Keyboard", new[] { "Concepts" }));
        NewCourseWizardUiTests.OpenWizard(app);
        NewCourseWizardUiTests.PutCodeIn(app, "STPWZ");
        var create = app.Find("PrimaryButton", "the wizard's Create button");
        Assert.True(Retry.WhileFalse(() => create.IsEnabled, TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result,
                    "Create never became available");
        create.AsButton().Invoke();
        Assert.True(Retry.WhileNull(() => app.FindOrNull("taskPhaseLabel", TimeSpan.FromSeconds(1)),
                                    TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(200)).Result is not null,
                    "Create was pressed but the wizard never started work");
        app.Find("taskDetailsDisclosure", "Show details").AsButton().Invoke();
        var stop = Retry.WhileNull(() => app.FindOrNull("consoleStopButton", TimeSpan.FromMilliseconds(300)) is { IsOffscreen: false } shown ? shown : null,
                                   TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result;
        Assert.True(stop is not null, $"the wizard's console shows no Stop while it works (phase \"{Phase(app)}\")");
        string before = Phase(app);
        Measured($"the wizard's work, phase \"{before}\" before its console's Stop");
        Assert.True(before is not "Done" and not "Cancelled" and not "Something went wrong", $"the wizard's work ended before its Stop was pressed (phase \"{before}\")");
        stop!.AsButton().Invoke();
        Assert.Null(OpenStopQuestion(app));
        Assert.True(Retry.WhileFalse(() => Phase(app) == "Cancelled", TimeSpan.FromSeconds(30), TimeSpan.FromMilliseconds(250)).Result,
                    $"the console's Stop did not end the wizard's work as the teacher's stop (phase \"{Phase(app)}\")");
        Assert.Null(OpenStopQuestion(app));
    }

    private static bool AMenuIsOpen(DrivenApp app)
    {
        try { return app.Window.FindFirstDescendant(cf => cf.ByControlType(ControlType.Menu)) is { IsOffscreen: false }; }
        catch (System.Runtime.InteropServices.COMException) { return false; }
    }

    /// <summary>
    /// Measured for documentation 12: Escape with the menu bar's File menu
    /// open, with a sidebar row's context menu open, and with a ComboBox
    /// focused (the main window has one only in a course's settings, which
    /// replace the section's panel). Each control keeps its own Escape; none
    /// asks or stops the deploy.
    /// </summary>
    [UiFact]
    public void EscapeWithAMenuOpenOrAComboBoxFocusedIsTheirs()
    {
        string published = "";
        using var app = new DrivenApp(courses => WriteCourse(courses, out published));
        app.SelectSection(Code, 1);
        StartDeploy(app, 1);

        // The File menu, open.
        var file = app.Find("appMenuBar", "the menu bar").FindFirstDescendant(cf => cf.ByName("File"));
        Assert.True(file is not null, "the menu bar has no File");
        app.ClickMiddleOf(file!);
        Assert.True(Retry.WhileFalse(() => AMenuIsOpen(app), TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result, "File did not open");
        Press(app, VirtualKeyShort.ESCAPE);
        bool menuOpen = AMenuIsOpen(app);
        bool asked = OpenStopQuestion(app) is not null;
        Measured($"Escape with File open: menu {(menuOpen ? "still open" : "closed")}, question {(asked ? "opened" : "not asked")}, phase \"{Phase(app)}\"");
        Assert.False(asked, "Escape with the File menu open asked to stop the deploy");
        AssertStillDeploying(app, "Escape with the File menu open");
        if (menuOpen) Press(app, VirtualKeyShort.ESCAPE);

        // A sidebar row's context menu, open.
        var row = app.Find($"sidebar-{Code}-section1", "the section's sidebar row");
        app.RightClickMiddleOf(row);
        Assert.True(Retry.WhileFalse(() => AMenuIsOpen(app), TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result, "the row's menu did not open");
        Press(app, VirtualKeyShort.ESCAPE);
        menuOpen = AMenuIsOpen(app);
        asked = OpenStopQuestion(app) is not null;
        Measured($"Escape with a row's context menu open: menu {(menuOpen ? "still open" : "closed")}, question {(asked ? "opened" : "not asked")}");
        Assert.False(asked, "Escape with a row's context menu open asked to stop the deploy");
        AssertStillDeploying(app, "Escape with a row's context menu open");
        if (menuOpen) Press(app, VirtualKeyShort.ESCAPE);

        // A ComboBox focused, then open: only a course's settings have one.
        app.SelectCourse(Code);
        var combo = Retry.WhileNull(() => app.Window.FindFirstDescendant(cf => cf.ByControlType(ControlType.ComboBox)),
                                    TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result;
        if (combo is null)
        {
            Measured("no ComboBox in the course's settings to focus");
        }
        else
        {
            combo.Focus();
            Thread.Sleep(400);
            Press(app, VirtualKeyShort.ESCAPE);
            Measured($"Escape with a ComboBox focused (\"{combo.Name}\"): question {(OpenStopQuestion(app) is null ? "not asked" : "opened")}");
            Assert.Null(OpenStopQuestion(app));
            try { combo.Patterns.ExpandCollapse.Pattern.Expand(); } catch { }
            Thread.Sleep(600);
            bool expanded = combo.Patterns.ExpandCollapse.PatternOrDefault?.ExpandCollapseState.ValueOrDefault == ExpandCollapseState.Expanded;
            Press(app, VirtualKeyShort.ESCAPE);
            bool stillExpanded = combo.Patterns.ExpandCollapse.PatternOrDefault?.ExpandCollapseState.ValueOrDefault == ExpandCollapseState.Expanded;
            Measured($"Escape with a ComboBox open (opened: {expanded}): {(stillExpanded ? "still open" : "closed")}, question {(OpenStopQuestion(app) is null ? "not asked" : "opened")}");
            Assert.Null(OpenStopQuestion(app));
        }
        app.SelectSection(Code, 1);
        Assert.Null(OpenStopQuestion(app));
        Measured($"back on the section after the ComboBox: phase \"{Phase(app)}\"");
    }
}
