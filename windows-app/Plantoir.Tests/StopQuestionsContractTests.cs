using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #1009 (the mac's #988): the two stop questions, their Don't ask again
/// boxes and Settings ▸ Deploying ▸ Stopping, against
/// <c>contracts/shared-rules.json</c> → <c>stopQuestions</c>: every word,
/// every case played through <see cref="StopQuestionAsking"/>, the trail line
/// <c>activityTrail.mustRecord</c> shows, and by source scan that the panel's
/// key is a <c>KeyboardAccelerator</c> on the visible Cancel and that the
/// question says the contract's words with Stop Deploy as its default.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class StopQuestionsContractTests : IDisposable
{
    private static JsonNode Contract => ContractLoader.LoadJson("shared-rules.json")["stopQuestions"]!;

    private static string AppSource(params string[] parts) =>
        File.ReadAllText(Path.Combine(new[] { ContractLoader.RepositoryRoot, "windows-app", "Plantoir" }.Concat(parts).ToArray()))
            .Replace("\r\n", "\n");

    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-1009-" + Guid.NewGuid().ToString("N")[..8]);
    private readonly string? _settingsPathBefore = AppSettings.PathOverride;

    public StopQuestionsContractTests()
    {
        Directory.CreateDirectory(_folder);
        AppSettings.PathOverride = Path.Combine(_folder, "settings.json");
    }

    public void Dispose()
    {
        AppSettings.PathOverride = _settingsPathBefore;
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    // ---- the words ---------------------------------------------------------------

    [Fact]
    public void EveryWordIsTheContracts()
    {
        var deploy = Contract["questions"]!["deploy"]!;
        Assert.Equal(deploy["title"]!.ToString(), StopQuestionWording.Title(StopQuestion.Deploy));
        Assert.Equal(deploy["message"]!.ToString(), StopQuestionWording.Message(StopQuestion.Deploy));
        Assert.Equal(deploy["stopButton"]!.ToString(), StopQuestionWording.StopButton(StopQuestion.Deploy));
        Assert.Equal(deploy["cancelButton"]!.ToString(), StopQuestionWording.CancelButton);
        Assert.Equal(deploy["settingLabel"]!.ToString(), StopQuestionWording.SettingLabel(StopQuestion.Deploy));

        var share = Contract["questions"]!["share"]!;
        Assert.Equal(share["title"]!.ToString(), StopQuestionWording.Title(StopQuestion.Share));
        Assert.Equal(share["message"]!.ToString(), StopQuestionWording.Message(StopQuestion.Share));
        Assert.Equal(share["stopButton"]!.ToString(), StopQuestionWording.StopButton(StopQuestion.Share));
        Assert.Equal(share["cancelButton"]!.ToString(), StopQuestionWording.CancelButton);
        Assert.Equal(share["settingLabel"]!.ToString(), StopQuestionWording.SettingLabel(StopQuestion.Share));

        var wording = Contract["wording"]!;
        Assert.Equal(wording["dontAskAgain"]!.ToString(), StopQuestionWording.DontAskAgain);
        Assert.Equal(wording["sectionHeader"]!.ToString(), StopQuestionWording.SectionHeader);
        // Windows has no Command-Period: its footer is windowsWording's.
        Assert.Equal(Contract["windowsWording"]!["footer"]!.ToString(), StopQuestionWording.Footer);
        Assert.DoesNotContain("Command", StopQuestionWording.Footer);
        Assert.Contains("Command-Period", wording["footer"]!.ToString());
    }

    [Fact]
    public void TheTrailLinesAreTheContractsAndTheMustRecordExample()
    {
        var trail = Contract["trail"]!;
        Assert.Equal("stop question setting changed", trail["event"]!.ToString());
        Assert.Equal("stop question setting changed", Plantoir.Core.Scripting.ActivityTrail.KeyFor(Plantoir.Core.Scripting.ActivityTrail.Event.StopQuestionSettingChanged));
        foreach (var question in new[] { StopQuestion.Deploy, StopQuestion.Share })
        {
            foreach (bool asked in new[] { true, false })
            {
                string onOrOff = trail["onOrOff"]![asked ? "true" : "false"]!.ToString();
                string label = StopQuestionWording.SettingLabel(question);
                Assert.Equal(trail["fromSettings"]!.ToString().Replace("{settingLabel}", label).Replace("{onOrOff}", onOrOff),
                             StopQuestionWording.TrailLine(question, asked, StopQuestionChangedFrom.Settings));
                Assert.Equal(trail["fromDontAskAgain"]!.ToString().Replace("{settingLabel}", label).Replace("{onOrOff}", onOrOff)
                                 .Replace("{title}", StopQuestionWording.Title(question)),
                             StopQuestionWording.TrailLine(question, asked, StopQuestionChangedFrom.DontAskAgain));
            }
        }
        var mustRecord = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(entry => entry!["event"]!.ToString() == "stop question setting changed")!;
        Assert.Null(mustRecord["appliesOn"]);
        Assert.Equal(mustRecord["line"]!.ToString(),
                     StopQuestionWording.TrailLine(StopQuestion.Deploy, false, StopQuestionChangedFrom.DontAskAgain));
    }

    // ---- the cases ---------------------------------------------------------------

    [Fact]
    public void EveryCaseHolds()
    {
        var cases = Contract["cases"]!.AsArray();
        Assert.True(cases.Count >= 14, $"only {cases.Count} stopQuestions cases");
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var before = c["settingsBefore"]!;
            var settings = new AppSettings
            {
                AsksBeforeStoppingADeploy = before["deploy"]!.GetValue<bool>(),
                AsksBeforeStoppingAShare = before["share"]!.GetValue<bool>(),
            };
            StopQuestion? question = c["question"]?.ToString() switch
            {
                null => null,
                "deploy" => StopQuestion.Deploy,
                "share" => StopQuestion.Share,
                var other => throw new Xunit.Sdk.XunitException($"{name}: unknown question {other}"),
            };
            var written = new List<string>();
            var asking = new StopQuestionAsking(question, settings, written.Add);
            bool running = c["taskRunning"]!.GetValue<bool>();
            var steps = c["steps"]!.AsArray();
            for (int index = 0; index < steps.Count; index++)
            {
                string step = steps[index]!.ToString();
                bool stops = false;
                switch (step)
                {
                    case "pressCancel": stops = asking.PressCancel(running); break;
                    case "tickDontAskAgain": asking.DontAskAgain = true; break;
                    case "chooseStop": asking.ChooseStop(); stops = true; break;
                    case "chooseCancel": asking.ChooseCancel(); break;
                    case "taskEnded": asking.TaskEnded(); break;
                    case "settingsTurnOn": StopQuestionWording.SetAsked(question!.Value, true, settings, StopQuestionChangedFrom.Settings, written.Add); break;
                    case "settingsTurnOff": StopQuestionWording.SetAsked(question!.Value, false, settings, StopQuestionChangedFrom.Settings, written.Add); break;
                    default: throw new Xunit.Sdk.XunitException($"{name}: unknown step {step}");
                }
                Assert.True(c["stopsAfterStep"]![index]!.GetValue<bool>() == stops, $"{name}, step {index + 1} ({step}): stops {stops}");
                Assert.True(c["asksAfterStep"]![index]!.GetValue<bool>() == asking.IsAsking, $"{name}, step {index + 1} ({step}): asking {asking.IsAsking}");
            }
            var after = c["settingsAfter"]!;
            Assert.True(after["deploy"]!.GetValue<bool>() == settings.AsksBeforeStoppingADeploy, $"{name}: the deploy's setting");
            Assert.True(after["share"]!.GetValue<bool>() == settings.AsksBeforeStoppingAShare, $"{name}: the share's setting");
            Assert.Equal(c["trail"]!.AsArray().Select(line => line!.ToString()).ToList(), written);
        }
    }

    [Fact]
    public void BothQuestionsAreAskedUntilTheTeacherSaysOtherwise_AndTheAnswerIsKept()
    {
        var fresh = new AppSettings();
        Assert.True(fresh.AsksBeforeStoppingADeploy);
        Assert.True(fresh.AsksBeforeStoppingAShare);
        Assert.True(fresh.ChangeAsksBeforeStopping(StopQuestion.Deploy, false));
        Assert.False(fresh.ChangeAsksBeforeStopping(StopQuestion.Deploy, false));
        var loaded = AppSettings.Load();
        Assert.False(loaded.AsksBeforeStoppingADeploy);
        Assert.True(loaded.AsksBeforeStoppingAShare);
    }

    [Fact]
    public void TheEscapeKeyIsDecidedAsItArrives()
    {
        Assert.True(StopKey.GoesToCancel(cancelIsShown: true, taskIsRunning: true, aDialogIsOpen: false, anEditableTextBoxHasTheFocus: false));
        Assert.False(StopKey.GoesToCancel(cancelIsShown: true, taskIsRunning: true, aDialogIsOpen: false, anEditableTextBoxHasTheFocus: true));
        Assert.False(StopKey.GoesToCancel(cancelIsShown: false, taskIsRunning: true, aDialogIsOpen: false, anEditableTextBoxHasTheFocus: false));
        Assert.False(StopKey.GoesToCancel(cancelIsShown: true, taskIsRunning: false, aDialogIsOpen: false, anEditableTextBoxHasTheFocus: false));
        Assert.False(StopKey.GoesToCancel(cancelIsShown: true, taskIsRunning: true, aDialogIsOpen: true, anEditableTextBoxHasTheFocus: false));
    }

    // ---- the panel, by source ------------------------------------------------------

    [Fact]
    public void TheKeyIsAnAcceleratorOnTheVisibleCancel_AndNothingElseCatchesEscape()
    {
        string panel = AppSource("Views", "TaskProgressView.xaml.cs");
        Assert.Contains("TaskCancelButton.KeyboardAccelerators.Add(escape);", panel);
        Assert.Contains("new KeyboardAccelerator { Key = VirtualKey.Escape }", panel);
        // No key handler of its own: no KeyDown on the panel, and one
        // PreviewKeyDown only, on the open stop question, which swallows
        // nothing but a held Escape's repeats (#1009's first review).
        Assert.Single(System.Text.RegularExpressions.Regex.Matches(panel, @"PreviewKeyDown \+="));
        Assert.Contains("dialog.PreviewKeyDown += (_, args) =>\n        {\n            if (args.Key == VirtualKey.Escape && args.KeyStatus.WasKeyDown) args.Handled = true;\n        };", panel);
        Assert.DoesNotContain("this.KeyDown", panel);
        // A click and an accessibility press reach the same path, with no box check.
        Assert.Contains("private void TaskCancel_Click(object sender, RoutedEventArgs e) => _ = PressCancelAsync();", panel);
        string xaml = AppSource("Views", "TaskProgressView.xaml");
        Assert.Contains("x:Name=\"TaskCancelButton\" Content=\"Cancel\"", xaml);
        // Only a section's panel holds the key; the wizard's keeps Escape for its dialog (#979).
        Assert.Contains("Progress.GiveCancelTheEscapeKey();", AppSource("Views", "SectionDetailView.xaml.cs"));
        Assert.DoesNotContain("GiveCancelTheEscapeKey", AppSource("Views", "NewCourseDialog.cs"));
        Assert.Contains("stopQuestion: StopQuestion.Deploy", AppSource("Views", "SectionDetailView.xaml.cs"));
        // The preview's site drawn over the console holds no key (the mac's progressPanelTakesTheCancelKeys).
        Assert.Contains("Progress.IsCovered = Preview.Visibility == Visibility.Visible;", AppSource("Views", "SectionDetailView.xaml.cs"));
        Assert.Contains("cancelIsShown: !IsCovered && IsOnScreen(TaskCancelButton),", panel);
        // Once per run: the accelerator repeats while Escape is held.
        Assert.Contains("_stopSentTo = (runner, runner.StartedAt);", panel);
    }

    [Fact]
    public void TheQuestionSaysTheContractsWords_WithStopAsTheDefault()
    {
        string panel = AppSource("Views", "TaskProgressView.xaml.cs");
        int from = panel.IndexOf("private async System.Threading.Tasks.Task AskBeforeStoppingAsync(", StringComparison.Ordinal);
        Assert.True(from >= 0, "the stop question is not where this test looks");
        string question = panel.Substring(from, panel.IndexOf("ShowAsync()", from, StringComparison.Ordinal) - from);
        Assert.Contains("Title = StopQuestionWording.Title(question),", question);
        Assert.Contains("PrimaryButtonText = StopQuestionWording.StopButton(question),", question);
        Assert.Contains("CloseButtonText = StopQuestionWording.CancelButton,", question);
        Assert.Contains("DefaultButton = ContentDialogButton.Primary,", question);
        Assert.Contains("new CheckBox { Content = StopQuestionWording.DontAskAgain, IsChecked = false", question);
        Assert.DoesNotContain("Destructive", question);
        // The box is read only with Stop.
        string after = panel.Substring(panel.IndexOf("ShowAsync()", from, StringComparison.Ordinal));
        int stop = after.IndexOf("asking.ChooseStop();", StringComparison.Ordinal);
        int read = after.IndexOf("asking.DontAskAgain = dontAskAgain.IsChecked == true;", StringComparison.Ordinal);
        int cancel = after.IndexOf("asking.ChooseCancel();", StringComparison.Ordinal);
        Assert.True(read >= 0 && read < stop && stop < cancel, "the box is read somewhere other than just before Stop");
    }

    [Fact]
    public void SettingsDeployingOpensWithStopping_InTheContractsWords()
    {
        string pane = AppSource("Views", "DeployingSettingsPane.cs");
        int stopping = pane.IndexOf("AddStoppingSection(panel, settings);", StringComparison.Ordinal);
        int cloudflare = pane.IndexOf("SectionHeaderWithCaption(\"Cloudflare Pages\"", StringComparison.Ordinal);
        Assert.True(stopping >= 0 && stopping < cloudflare, "Stopping is not the first section of Settings ▸ Deploying");
        Assert.Contains("StopQuestionWording.SectionHeader", pane);
        Assert.Contains("StopQuestionWording.SettingLabel(question)", pane);
        Assert.Contains("StopQuestionWording.Footer", pane);
        Assert.Contains("StopQuestionWording.SetAsked(question, true, settings, StopQuestionChangedFrom.Settings)", pane);
        Assert.Contains("StopQuestionWording.SetAsked(question, false, settings, StopQuestionChangedFrom.Settings)", pane);
    }

    // ---- one "under way" rule, and every route asks (#1009's first review) ------

    [Fact]
    public void ARunBetweenItsBuildAndItsDeployIsUnderWay_AndAPressThereAsks()
    {
        var runner = new ScriptRunner();
        Assert.False(runner.IsUnderWay);
        runner.IsBetweenPhases = true;
        Assert.False(runner.IsRunning);
        Assert.True(runner.IsUnderWay, "a run between its build and its deploy is not under way");
        var asking = new StopQuestionAsking(StopQuestion.Deploy, new AppSettings(), note: _ => { });
        Assert.False(asking.PressCancel(runner.IsUnderWay), "a press in the gap stopped at once");
        Assert.True(asking.IsAsking, "a press in the gap asked nothing");
    }

    [Fact]
    public void ACancelInTheGapMarksTheRunCancelled_SoTheDeployNeverStarts()
    {
        var runner = new ScriptRunner { IsBetweenPhases = true };
        runner.CancelByUser();
        Assert.True(runner.WasCancelled);
        string multi = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Scripting", "MultiDestinationDeployRunner.cs"))
            .Replace("\r\n", "\n");
        Assert.Contains("if (CurrentLeg is { Runner.IsUnderWay: true } leg) leg.Runner.CancelByUser();", multi);
        // RunAsync's own check after the build then reads the runner's mark.
        Assert.Contains("bool built = await runner.WaitUntilFinished();\n                    if (runner.WasCancelled || runner.WasStoppedByUser)", multi);
        // The run is never out of the way between the two: Run clears
        // IsBetweenPhases only once the deploy is running.
        string script = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Scripting", "ScriptRunner.cs"))
            .Replace("\r\n", "\n");
        Assert.Contains("IsRunning = true;\n        IsBetweenPhases = false;", script);
    }

    [Fact]
    public void ThePanelDecidesEveryStopByOneUnderWayRule_AndTheConsolesStopAsksToo()
    {
        string panel = AppSource("Views", "TaskProgressView.xaml.cs");
        Assert.Contains("private bool TaskIsUnderWay => MultiDestinationDeployRunner.ShownTaskIsUnderWay(_runner, _multiRunner);", panel);
        Assert.Contains("taskIsRunning: TaskIsUnderWay,", panel);
        Assert.Contains("if (asking.PressCancel(TaskIsUnderWay))", panel);
        Assert.Contains("if (TaskIsUnderWay) StopTheTask();", panel);
        // The question comes down by the same rule, on a runner's change and
        // when the section shows the panel again (the whole run ending).
        Assert.Contains("if (TaskIsUnderWay || _openStopQuestion is not { } stopQuestion) return;", panel);
        Assert.Equal(3, CountOf(panel, "TakeDownTheStopQuestionIfTheTaskEnded()"));
        Assert.DoesNotContain("!runner.IsUnderWay", panel);
        Assert.Contains("RunningActionsRow.Visibility = TaskIsUnderWay ?", panel);
        int from = panel.IndexOf("// ---- Stopping, by click", StringComparison.Ordinal);
        Assert.True(from >= 0, "the stopping code is not where this test looks");
        Assert.DoesNotContain("IsRunning: true", panel.Substring(from));
        // The console's own Stop goes the way Cancel goes: it asks, it is swept, it reads "Cancelled".
        Assert.Contains("private void ConsoleStop_Click(object sender, RoutedEventArgs e) => _ = PressCancelAsync();", panel);
        Assert.DoesNotContain("Terminate()", panel);
    }

    private static int CountOf(string text, string part)
    {
        int count = 0;
        int at = text.IndexOf(part, StringComparison.Ordinal);
        while (at >= 0)
        {
            count += 1;
            at = text.IndexOf(part, at + part.Length, StringComparison.Ordinal);
        }
        return count;
    }

    // ---- between two destinations, and a stuck mark (#1009's second review) ------

    [Fact]
    public void BetweenTwoDestinationsTheDeployIsUnderWay_AndAPressThereAsks()
    {
        // Destination 1's runner has stopped; the run has not yet moved on.
        var finishedLeg = new ScriptRunner();
        var run = new MultiDestinationDeployRunner();
        run.SetStateForTests(running: true, startedAt: DateTime.UtcNow);
        Assert.False(finishedLeg.IsUnderWay);
        Assert.True(MultiDestinationDeployRunner.ShownTaskIsUnderWay(finishedLeg, run),
                    "the gap between two destinations read as the deploy having ended");
        var asking = new StopQuestionAsking(StopQuestion.Deploy, new AppSettings(), note: _ => { });
        Assert.False(asking.PressCancel(MultiDestinationDeployRunner.ShownTaskIsUnderWay(finishedLeg, run)),
                     "a press between two destinations stopped at once");
        Assert.True(asking.IsAsking, "a press between two destinations asked nothing");

        // Cancelled, or over, it can no longer be stopped; with no run, the runner alone decides.
        run.Cancel();
        Assert.False(MultiDestinationDeployRunner.ShownTaskIsUnderWay(finishedLeg, run), "a cancelled run still reads as under way");
        var over = new MultiDestinationDeployRunner();
        over.SetStateForTests(running: false, startedAt: DateTime.UtcNow);
        Assert.False(MultiDestinationDeployRunner.ShownTaskIsUnderWay(finishedLeg, over));
        Assert.False(MultiDestinationDeployRunner.ShownTaskIsUnderWay(finishedLeg, null));
        Assert.True(MultiDestinationDeployRunner.ShownTaskIsUnderWay(new ScriptRunner { IsBetweenPhases = true }, null));
    }

    /// <summary>A course in a working folder whose launchers are stand-ins: each deploy adds a line to <c>deploys.txt</c>.</summary>
    private Course StandInCourse(string code, out string deploysLog)
    {
        string course = Path.Combine(_folder, "courses", code);
        Directory.CreateDirectory(Path.Combine(course, "section1"));
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            $$"""{"course_code":"{{code}}","section_numbers":[1],"num_sections":1,"deploy_target":"local_folder","deploy_folder_path":"C:\sites"}""");
        File.WriteAllText(Path.Combine(course, "section1", "index.md"), "# Section 1\n");
        deploysLog = Path.Combine(_folder, "deploys.txt");
        // preview.ps1 is also what makes the folder a working folder (Workspace.MarkerLauncher).
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "exit 0\r\n");
        File.WriteAllText(Path.Combine(_folder, DeployCommand.ScriptName),
            $"Add-Content -LiteralPath '{deploysLog.Replace("'", "''")}' -Value deployed\r\nexit 0\r\n");
        foreach (var found in Workspace.DiscoverCourses(_folder))
        {
            if (found.Code == code) return found;
        }
        throw new InvalidOperationException($"the stand-in course {code} was not found");
    }

    private static int LinesIn(string path) => File.Exists(path) ? File.ReadAllLines(path).Length : 0;

    /// <summary>Runs <see cref="MultiDestinationDeployRunner.RunAsync"/> on a one-thread context, as the window's thread runs it.</summary>
    private static async Task RunOn(SingleThreadContext context, Func<Task> run)
    {
        var finished = new TaskCompletionSource();
        context.Post(async _ =>
        {
            try { await run(); finished.SetResult(); }
            catch (Exception error) { finished.SetException(error); }
        }, null);
        await finished.Task.WaitAsync(TimeSpan.FromMinutes(2));
    }

    [Fact]
    public async Task ACancelBetweenTwoDestinationsAsks_AndStartsNoLaterDestination()
    {
        var course = StandInCourse("GAPTWO", out string deploysLog);
        var destinations = new[]
        {
            new CourseConfiguration.DeployDestination("local_folder", Path.Combine(_folder, "site-one")),
            new CourseConfiguration.DeployDestination("local_folder", Path.Combine(_folder, "site-two")),
            new CourseConfiguration.DeployDestination("local_folder", Path.Combine(_folder, "site-three")),
        };
        using var context = new SingleThreadContext();
        var run = new MultiDestinationDeployRunner(context);
        bool hooked = false;
        bool? underWayInTheGap = null;
        bool? askedInTheGap = null;
        run.PropertyChanged += (_, changed) =>
        {
            if (hooked || changed.PropertyName != nameof(MultiDestinationDeployRunner.IsRunning) || !run.IsRunning) return;
            hooked = true;
            var first = run.Legs[0].Runner;
            first.PropertyChanged += (_, firstChanged) =>
            {
                // Destination 1 has just ended, on the window's thread: RunAsync
                // has not yet seen it (its poll is queued behind this), so this
                // is the gap between two destinations.
                if (firstChanged.PropertyName != nameof(ScriptRunner.IsRunning) || first.IsRunning || first.LastExitCode is null) return;
                if (underWayInTheGap is not null) return;
                underWayInTheGap = MultiDestinationDeployRunner.ShownTaskIsUnderWay(first, run);
                var asking = new StopQuestionAsking(StopQuestion.Deploy, new AppSettings(), note: _ => { });
                askedInTheGap = !asking.PressCancel(underWayInTheGap == true) && asking.IsAsking;
                // Stop Deploy, chosen in the gap: the panel's StopTheTask → the section's CancelDeploy.
                run.Cancel();
            };
        };
        await RunOn(context, () => run.RunAsync(course, 1, destinations, "", _folder, buildReason: null));

        Assert.True(underWayInTheGap == true, "the gap between two destinations was never reached, or read as ended");
        Assert.True(askedInTheGap == true, "a press between two destinations did not ask");
        Assert.True(run.WasCancelled);
        Assert.False(run.IsRunning);
        Assert.Equal(1, LinesIn(deploysLog));
        Assert.Null(run.Legs[1].Runner.StartedAt);
        Assert.Null(run.Legs[2].Runner.StartedAt);
    }

    [Fact]
    public async Task AnExceptionBetweenTheBuildAndTheDeployLeavesNoRunBetweenPhases()
    {
        var course = StandInCourse("GAPTHROW", out string deploysLog);
        var destinations = new[] { new CourseConfiguration.DeployDestination("local_folder", Path.Combine(_folder, "site-one")) };
        using var context = new SingleThreadContext();
        var run = new MultiDestinationDeployRunner(context);
        bool hooked = false;
        run.PropertyChanged += (_, changed) =>
        {
            if (hooked || changed.PropertyName != nameof(MultiDestinationDeployRunner.IsRunning) || !run.IsRunning) return;
            hooked = true;
            var leg = run.Legs[0].Runner;
            leg.PropertyChanged += (_, legChanged) =>
            {
                // The deploy's Run beginning, after the build: anything that
                // throws here is an exception between the build and the deploy.
                if (legChanged.PropertyName == nameof(ScriptRunner.IsRunning) && leg.IsBetweenPhases && leg.LastExitCode is null)
                    throw new InvalidOperationException("thrown between the build and the deploy");
            };
        };
        var thrown = await Assert.ThrowsAsync<InvalidOperationException>(
            () => RunOn(context, () => run.RunAsync(course, 1, destinations, "", _folder, buildReason: BuildFreshness.ReasonPages)));
        Assert.Equal("thrown between the build and the deploy", thrown.Message);
        Assert.False(run.IsRunning);
        Assert.False(run.Legs[0].Runner.IsBetweenPhases, "the run ended with its leg still marked between the build and the deploy");
        Assert.False(MultiDestinationDeployRunner.ShownTaskIsUnderWay(run.Legs[0].Runner, run), "the panel would still ask about a run that has ended");
        Assert.Equal(0, LinesIn(deploysLog));
    }

    /// <summary>One thread, one queue: what the window's thread is to RunAsync and to a runner's posted endings.</summary>
    private sealed class SingleThreadContext : SynchronizationContext, IDisposable
    {
        private readonly System.Collections.Concurrent.BlockingCollection<(SendOrPostCallback Callback, object? State)> _queue = new();

        public SingleThreadContext()
        {
            var thread = new Thread(() =>
            {
                SetSynchronizationContext(this);
                foreach (var (callback, state) in _queue.GetConsumingEnumerable()) callback(state);
            }) { IsBackground = true };
            thread.Start();
        }

        public override void Post(SendOrPostCallback d, object? state) => _queue.Add((d, state));

        public override void Send(SendOrPostCallback d, object? state)
        {
            using var done = new ManualResetEventSlim();
            _queue.Add((_ => { try { d(state); } finally { done.Set(); } }, null));
            done.Wait();
        }

        public void Dispose() => _queue.CompleteAdding();
    }

    [Fact]
    public void AChangedQuestionIsAnnounced_OncePerChange_SoAnOpenSettingsShowsIt()
    {
        var settings = new AppSettings();
        var heard = new List<StopQuestion>();
        settings.StopQuestionSettingChanged += question => heard.Add(question);
        var asking = new StopQuestionAsking(StopQuestion.Deploy, settings, note: _ => { });
        asking.PressCancel(taskCanStillBeStopped: true);
        asking.DontAskAgain = true;
        asking.ChooseStop();
        Assert.Equal(new[] { StopQuestion.Deploy }, heard);
        StopQuestionWording.SetAsked(StopQuestion.Deploy, false, settings, StopQuestionChangedFrom.Settings, _ => { });
        Assert.Single(heard);
        string pane = AppSource("Views", "DeployingSettingsPane.cs");
        Assert.Contains("settings.StopQuestionSettingChanged += ShowStored;", pane);
        Assert.Contains("box.Unloaded += (_, _) => settings.StopQuestionSettingChanged -= ShowStored;", pane);
    }
}
