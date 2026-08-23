using System;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Windows.System;
using Windows.UI;

namespace Plantoir.Views;

/// <summary>
/// Layered progress: a determinate bar with milestone labels by default, the
/// raw output one click away behind "Show details", questions asked in a
/// native dialog, and outcomes that distinguish Done / Stopped / Cancelled /
/// failed-with-explanation.
/// </summary>
public sealed partial class TaskProgressView : UserControl
{
    private readonly System.Collections.Generic.List<ScriptRunner> _registered = new();
    private ScriptRunner? _runner;
    private MultiDestinationDeployRunner? _multiRunner;
    private string _title = "";
    private bool _detailsOpen;
    private bool _questionDialogShowing;
    private long _renderedTranscriptVersion = -1;
    private readonly DispatcherTimer _tick;

    public TaskProgressView()
    {
        InitializeComponent();
        // Re-renders once a second while a task runs, so the "still working…"
        // timer keeps moving even when the script itself is momentarily quiet.
        _tick = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _tick.Tick += (_, _) => { if (_runner is { } r && (r.IsRunning || r.IsBetweenPhases)) Render(); };
        Unloaded += (_, _) => _tick.Stop();
    }

    private void EnsureTicking(bool on)
    {
        if (on && !_tick.IsEnabled) _tick.Start();
        else if (!on && _tick.IsEnabled) _tick.Stop();
    }

    /// <summary>
    /// Subscribe to a runner ONCE. Its question dialog fires whenever this
    /// runner awaits input — even when it is not the runner currently shown,
    /// so a background deploy's prompt is never missed.
    /// </summary>
    public void Register(ScriptRunner runner)
    {
        if (_registered.Contains(runner)) return;
        _registered.Add(runner);
        runner.PropertyChanged += (sender, e) => RunnerChanged((ScriptRunner)sender!, e);
    }

    public Action? OnCancel { get; set; }

    /// <summary>
    /// Choose which registered runner the panel displays.
    /// <paramref name="multiRunner"/>, when set and carrying more than one
    /// leg, adds the destination checklist, the combined console (every leg
    /// that has produced output, not just whichever is current — see
    /// WINDOWS-HANDOFF.md entry 308), and every succeeded leg's own link
    /// once the whole run is finished (entry 306). Left null — the default —
    /// for every caller with a single runner: the wizard's preview, and a
    /// single-destination deploy behave byte-for-byte as before.
    /// </summary>
    public void Show(ScriptRunner runner, string title, Action? onCancel = null, MultiDestinationDeployRunner? multiRunner = null)
    {
        Register(runner);
        if (!ReferenceEquals(_runner, runner)) _renderedTranscriptVersion = -1;
        _runner = runner;
        _multiRunner = multiRunner is { Legs.Count: > 1 } ? multiRunner : null;
        _title = title;
        OnCancel = onCancel;
        Render();
    }

    /// <summary>Single-runner callers (the wizard) register-and-show in one call.</summary>
    public void Bind(ScriptRunner runner, string title, Action? onCancel = null) => Show(runner, title, onCancel);

    /// <summary>
    /// A dedicated placeholder for the span between a deploy being clicked
    /// and <c>MultiDestinationDeployRunner.RunAsync</c> actually taking
    /// over — there is no runner to bind to yet that is not either blank
    /// (a brand-new <see cref="ScriptRunner"/> renders neither the running
    /// branch nor the outcome branch of <see cref="Render"/>) or stale (the
    /// PREVIOUS deploy's finished leg, still sitting in
    /// <c>MultiDestinationDeployRunner.ActiveRunner</c> until <c>RunAsync</c>
    /// replaces <c>Legs</c> with fresh ones) — neither is what is actually
    /// happening right now. Mirrors the mac's
    /// `preparingToDeployPlaceholder` (WINDOWS-HANDOFF.md item 8, row 318a).
    /// Sets the currently-shown runner to null (not unregistered — a
    /// runner, once <see cref="Register"/>ed, stays registered for its own
    /// question dialog for the life of this view) so a stray notification
    /// from a leftover leg runner cannot re-render over the placeholder:
    /// <see cref="RunnerChanged"/> only calls <see cref="Render"/> when the
    /// notifying runner is reference-equal to the one currently shown.
    /// </summary>
    public void ShowPreparing(string title)
    {
        _runner = null;
        _multiRunner = null;
        OnCancel = null;
        EnsureTicking(false);

        TitleText.Text = title;
        DestinationChecklist.Visibility = Visibility.Collapsed;
        OutcomeIcon.Visibility = Visibility.Collapsed;
        PhaseText.Text = "Preparing to deploy…";
        PhaseText.Foreground = Secondary();
        Bar.IsIndeterminate = true;
        Bar.Visibility = Visibility.Visible;
        MilestoneText.Visibility = Visibility.Collapsed;
        OutcomeDetail.Visibility = Visibility.Collapsed;
        LiveLink.Visibility = Visibility.Collapsed;
        FolderResult.Visibility = Visibility.Collapsed;
        DestinationLinks.Visibility = Visibility.Collapsed;
        RunningActionsRow.Visibility = Visibility.Collapsed;
        AwaitingNotice.Visibility = Visibility.Collapsed;
        LaunchProblemText.Visibility = Visibility.Collapsed;
        ConsoleInputRow.Visibility = Visibility.Collapsed;
    }

    private void RunnerChanged(ScriptRunner runner, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ScriptRunner.IsAwaitingInput) && runner.IsAwaitingInput)
            _ = AskQuestion(runner);
        if (e.PropertyName == nameof(ScriptRunner.LastExitCode) && !runner.IsRunning
            && ReferenceEquals(runner, _runner))
            AutoExpandOnUnexplainedFailure();
        if (ReferenceEquals(runner, _runner)) Render();
    }

    private void Render()
    {
        if (_runner is null) return;
        TitleText.Text = _title;
        RenderDestinationChecklist();

        bool hasMilestones = _runner.Milestones.Count > 0;
        // IsBetweenPhases: this runner has already finished the build half
        // of a build-then-deploy leg (IsRunning is false) but the deploy
        // half is about to start on it — rendering the outcome branch here
        // would flash "Done"/a failure for the gap the caller's polling
        // wait takes to notice the deploy is still queued up on it. See
        // ScriptRunner.IsBetweenPhases (row 318b).
        if (_runner.IsRunning || _runner.IsBetweenPhases)
        {
            OutcomeIcon.Visibility = Visibility.Collapsed;
            PhaseText.Text = hasMilestones ? _runner.StepDescription : "Working…";
            Bar.IsIndeterminate = !hasMilestones;
            if (hasMilestones) Bar.Value = _runner.ProgressFraction * 100;
            Bar.Visibility = Visibility.Visible;
            string detail = _runner.StepDetail;
            string label = _runner.CurrentMilestoneLabel;
            if (detail.Length > 0)
                MilestoneText.Text = $"{label} {detail}";
            else
            {
                // When a step reports its own count (uploads, build steps) that
                // count IS the movement. Otherwise, if a step has gone quiet for
                // a few seconds — long npm installs are the usual culprit — show
                // a live "still working…" timer so it never looks frozen.
                int quiet = (int)(DateTime.UtcNow - _runner.LastOutputAt).TotalSeconds;
                MilestoneText.Text = quiet >= 4 ? $"{label} still working… ({quiet}s)" : label;
            }
            MilestoneText.Visibility = hasMilestones ? Visibility.Visible : Visibility.Collapsed;
            OutcomeDetail.Visibility = Visibility.Collapsed;
            LiveLink.Visibility = Visibility.Collapsed;
            FolderResult.Visibility = Visibility.Collapsed;
            EnsureTicking(true);
        }
        else if (_runner.LastExitCode is { } exitCode)
        {
            Bar.IsIndeterminate = false;
            Bar.Value = _runner.WasCancelled || _runner.WasStoppedByUser ? Bar.Value : 100;
            MilestoneText.Visibility = Visibility.Collapsed;

            if (_multiRunner is { } multi)
            {
                // The badge reflects the WHOLE run's outcome, not just
                // whichever leg happened to run last — a course whose FIRST
                // destination failed and second succeeded must never read
                // as "Done" just because the last leg to run was fine.
                var outcome = multi.CurrentOutcome;
                if (_runner.WasCancelled) Outcome("Cancelled", Glyphs.Cancel, Caution(), $"{_title} was cancelled.");
                else if (_runner.WasStoppedByUser) Outcome("Stopped", Glyphs.Stop, Secondary(), null);
                else if (outcome.AllSucceeded) Outcome("Done", Glyphs.CheckMark, Success(), null);
                else if (outcome.AnySucceeded)
                {
                    var failedNames = outcome.FailedDestinations.Select(DeployCommand.DestinationDescription).ToList();
                    Outcome("Some destinations failed", Glyphs.Cancel, Critical(),
                        $"Deployed to some destinations, but not {MultiDestinationDeployRunner.JoinedWithAnd(failedNames)}.");
                }
                else Outcome("Something went wrong", Glyphs.Cancel, Critical(), _runner.FailureExplanation);

                LiveLink.Visibility = Visibility.Collapsed;
                FolderResult.Visibility = Visibility.Collapsed;
                RenderDestinationLinks(outcome);
            }
            else
            {
                // An ending the teacher asked for is not a fault.
                if (_runner.WasCancelled) Outcome("Cancelled", Glyphs.Cancel, Caution(), $"{_title} was cancelled.");
                else if (_runner.WasStoppedByUser) Outcome("Stopped", Glyphs.Stop, Secondary(), null);
                else if (exitCode == 0) Outcome("Done", Glyphs.CheckMark, Success(), null);
                else Outcome("Something went wrong", Glyphs.Cancel, Critical(), _runner.FailureExplanation);

                DestinationLinks.Visibility = Visibility.Collapsed;

                if (exitCode == 0 && !_runner.WasCancelled && _runner.PublishedFolder is { } folder)
                {
                    // Folder publishing ends at a folder, not a live link.
                    FolderResult.Visibility = Visibility.Visible;
                    _publishedFolder = folder;
                }
                else if (exitCode == 0 && !_runner.WasCancelled && _runner.PublishedSiteUrl is { } url)
                {
                    LiveLink.Visibility = Visibility.Visible;
                    LiveLinkButton.Content = url.AbsoluteUri;
                    LiveLinkButton.NavigateUri = url;
                }
            }
        }
        else
        {
            DestinationLinks.Visibility = Visibility.Collapsed;
        }

        if (!_runner.IsRunning) EnsureTicking(false);

        RunningActionsRow.Visibility = (_runner.IsRunning && !_runner.WasCancelled) ? Visibility.Visible : Visibility.Collapsed;
        AwaitingNotice.Visibility = _runner.IsAwaitingInput ? Visibility.Visible : Visibility.Collapsed;
        LaunchProblemText.Text = _runner.LaunchProblem ?? "";
        LaunchProblemText.Visibility = _runner.LaunchProblem is null ? Visibility.Collapsed : Visibility.Visible;
        ConsoleInputRow.Visibility = _runner.IsRunning ? Visibility.Visible : Visibility.Collapsed;

        long combinedVersion = _multiRunner is { } forVersion
            ? forVersion.Legs.Sum(leg => leg.Runner.Transcript.Version)
            : _runner.Transcript.Version;
        if (_detailsOpen && combinedVersion != _renderedTranscriptVersion)
        {
            _renderedTranscriptVersion = combinedVersion;
            // Terminal behaviour: keep the newest line in view as older lines
            // scroll up out of the frame — but only while the reader is already
            // at the bottom. Judge that against the extent BEFORE the text
            // grows, so scrolling up to read back is never yanked away.
            bool follow = ConsoleScroll.ScrollableHeight - ConsoleScroll.VerticalOffset <= BottomThreshold;
            string text = CombinedTranscriptText();
            ConsoleText.Text = text.Length == 0 ? "Starting…" : text;
            if (follow) ScrollConsoleToEnd();
        }
    }

    /// <summary>
    /// The console text to show: a single runner's own transcript, or —
    /// for a multi-destination deploy — every leg that has produced any
    /// output so far, each under its own heading, joined in deploy order.
    /// Without this, the moment a second destination started, the FIRST
    /// destination's own console output was simply gone — not scrolled
    /// past, gone (WINDOWS-HANDOFF.md entry 308). A leg the run never
    /// reached (stopped by a cancel, or an earlier failed shared build) is
    /// filtered out rather than shown as an empty, confusing section.
    /// </summary>
    private string CombinedTranscriptText()
    {
        if (_multiRunner is not { } multi) return _runner!.Transcript.DisplayText;
        var sections = multi.Legs
            .Where(leg => leg.Runner.Transcript.Lines.Count > 0 || leg.Runner.Transcript.CurrentLine.Length > 0)
            .Select(leg => $"── {DeployCommand.DestinationDescription(leg.Destination)} ──\n{leg.Runner.Transcript.DisplayText}");
        return string.Join("\n\n", sections);
    }

    /// <summary>
    /// One row per configured destination, with a symbol showing whether it
    /// is still to come, currently running, done, or failed — shown only
    /// for a multi-destination deploy, so a teacher can see the whole
    /// sequence rather than a bar that looks stuck between legs.
    /// </summary>
    private void RenderDestinationChecklist()
    {
        if (_multiRunner is not { } multi)
        {
            DestinationChecklist.Visibility = Visibility.Collapsed;
            return;
        }
        DestinationChecklist.Children.Clear();
        for (int index = 0; index < multi.Legs.Count; index++)
        {
            var leg = multi.Legs[index];
            string symbol = leg.IsFinished
                ? (leg.Succeeded ? "✓" : "✗")   // ✓ / ✗
                : index == multi.CurrentLegIndex && multi.IsRunning ? "•" : "○";   // • / ○
            DestinationChecklist.Children.Add(new TextBlock
            {
                Text = $"{symbol} {DeployCommand.DestinationDescription(leg.Destination)}",
                FontSize = 13,
                Opacity = leg.IsFinished || (index == multi.CurrentLegIndex) ? 1.0 : 0.6,
            });
        }
        DestinationChecklist.Visibility = Visibility.Visible;
    }

    /// <summary>
    /// Every SUCCEEDED destination's own link (or "Show in File Explorer"
    /// button, for a folder), once the whole run is finished — occupying
    /// the same slot a single destination's own link would. A destination
    /// the run never reached, or that failed, is simply not listed here;
    /// its absence is already explained by the checklist above and the
    /// outcome line.
    /// </summary>
    private void RenderDestinationLinks(MultiDestinationDeployRunner.Outcome outcome)
    {
        DestinationLinks.Children.Clear();
        if (_multiRunner is not { IsRunning: false } multi || !outcome.AnySucceeded)
        {
            DestinationLinks.Visibility = Visibility.Collapsed;
            return;
        }
        foreach (var leg in multi.Legs.Where(l => l.Succeeded))
        {
            var block = new StackPanel { Spacing = 2 };
            block.Children.Add(new TextBlock
            {
                Text = DeployCommand.DestinationDescription(leg.Destination),
                FontSize = 12,
                Opacity = 0.7,
            });
            if (leg.Runner.PublishedFolder is { } folder)
            {
                var button = new Button { Content = "Show in File Explorer" };
                button.Click += (_, _) => FolderActions.ShowInFileExplorer(folder);
                block.Children.Add(button);
            }
            else if (leg.Runner.PublishedSiteUrl is { } url)
            {
                var link = new HyperlinkButton { Content = url.AbsoluteUri, NavigateUri = url, Padding = new Thickness(0) };
                block.Children.Add(link);
            }
            else continue;
            DestinationLinks.Children.Add(block);
        }
        DestinationLinks.Visibility = DestinationLinks.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private const double BottomThreshold = 24;

    /// <summary>
    /// Pin the console to its last line. The immediate call handles the common
    /// case; the deferred one covers the moment right after the text grows,
    /// when the ScrollViewer has not yet recomputed ScrollableHeight and an
    /// immediate ChangeView would stop short of the newest line.
    /// </summary>
    private void ScrollConsoleToEnd()
    {
        ConsoleScroll.UpdateLayout();
        ConsoleScroll.ChangeView(null, ConsoleScroll.ScrollableHeight, null, disableAnimation: true);
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
            ConsoleScroll.ChangeView(null, ConsoleScroll.ScrollableHeight, null, disableAnimation: true));
    }

    private void Outcome(string label, string glyph, Brush brush, string? detail)
    {
        OutcomeIcon.Glyph = glyph;
        OutcomeIcon.Foreground = brush;
        OutcomeIcon.Visibility = Visibility.Visible;
        PhaseText.Text = label;
        PhaseText.Foreground = brush;
        OutcomeDetail.Text = detail ?? "";
        OutcomeDetail.Visibility = detail is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private Brush Caution() => (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
    private Brush Critical() => (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"];
    private Brush Success() => (Brush)Application.Current.Resources["SystemFillColorSuccessBrush"];
    private Brush Secondary() => (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];

    /// <summary>Only fall back to the raw output when the app has nothing better to say.</summary>
    private void AutoExpandOnUnexplainedFailure()
    {
        if (_runner is null || _runner.LastExitCode is not { } exitCode) return;
        if (exitCode != 0 && !_runner.WasCancelled && !_runner.WasStoppedByUser
            && _runner.FailureExplanation is null && !_detailsOpen)
            ToggleDetails(open: true);
    }

    // ---- Question dialog -------------------------------------------------

    private async System.Threading.Tasks.Task AskQuestion(ScriptRunner runner)
    {
        if (_questionDialogShowing || XamlRoot is null) return;
        _questionDialogShowing = true;
        try
        {
            var req = Plantoir.Core.Scripting.CredentialRequests.MatchPrompt(runner.PendingQuestion);
            bool richDialogShown = false;
            if (req is not null)
            {
                try
                {
                    Plantoir.Core.Scripting.ActivityTrail.Note(
                        Plantoir.Core.Scripting.ActivityTrail.Event.AskedForACredential,
                        $"asked for the {req.FieldLabel}");
                    var panel = CredentialRequestPanel.Build(req);

                    // The label above the field says what it is; the field's
                    // own placeholder says what to do, rather than repeating
                    // the label back (mac parity: CredentialRequestSheet).
                    var fieldColumn = new StackPanel { Spacing = 4 };
                    fieldColumn.Children.Add(new TextBlock { Text = req.FieldLabel });
                    string placeholder = req.FieldPlaceholder.Length > 0 ? req.FieldPlaceholder : req.FieldLabel;
                    Control inputControl;
                    Func<string> getAnswer;
                    if (req.IsSecret)
                    {
                        var pw = new PasswordBox
                        {
                            PlaceholderText = placeholder,
                            Password = runner.SuggestedAnswer
                        };
                        inputControl = pw;
                        getAnswer = () => pw.Password;
                    }
                    else
                    {
                        var tb = new TextBox
                        {
                            PlaceholderText = placeholder,
                            Text = runner.SuggestedAnswer
                        };
                        inputControl = tb;
                        getAnswer = () => tb.Text;
                    }
                    fieldColumn.Children.Add(inputControl);
                    panel.Children.Add(fieldColumn);

                    var dialog = new ContentDialog
                    {
                        Title = req.Title,
                        Content = panel,
                        PrimaryButtonText = "Save and continue",
                        CloseButtonText = "Cancel",
                        DefaultButton = ContentDialogButton.Primary,
                        XamlRoot = XamlRoot,
                    };
                    inputControl.Loaded += (_, _) => inputControl.Focus(FocusState.Programmatic);
                    richDialogShown = true;
                    var result = await dialog.ShowAsync();
                    if (result == ContentDialogResult.Primary) runner.SendLine(getAnswer());
                    else runner.CancelPendingQuestion();
                }
                catch (Exception ex) when (!richDialogShown)
                {
                    // A presentation bug must degrade to the plain dialog,
                    // never to NO dialog: the script is sitting on its
                    // question either way, and a teacher who sees nothing
                    // can only cancel the whole task. (This is exactly what
                    // an unguarded new Uri("") did to the surname dialog.)
                    App.LogDiagnostic($"Credential dialog failed to build, falling back: {ex}");
                    req = null;
                }
            }
            if (req is null)
            {
                var answerBox = new TextBox
                {
                    Text = runner.SuggestedAnswer,   // agreeing is one keystroke
                    PlaceholderText = "Your answer",
                };
                var panel = new StackPanel { Spacing = 12 };
                panel.Children.Add(new TextBlock { Text = runner.PendingQuestion, TextWrapping = TextWrapping.Wrap });
                panel.Children.Add(answerBox);
                var dialog = new ContentDialog
                {
                    // Neutral title: a task may ask several questions in a row.
                    Title = "Input required",
                    Content = panel,
                    PrimaryButtonText = "Send",
                    CloseButtonText = "Cancel",
                    DefaultButton = ContentDialogButton.Primary,
                    XamlRoot = XamlRoot,
                };
                answerBox.Loaded += (_, _) => { answerBox.Focus(FocusState.Programmatic); answerBox.SelectAll(); };
                var result = await dialog.ShowAsync();
                if (result == ContentDialogResult.Primary) runner.SendLine(answerBox.Text);
                else runner.CancelPendingQuestion();   // the script's own clean-up runs
            }
        }
        finally { _questionDialogShowing = false; }
    }

    // ---- Details disclosure ----------------------------------------------

    /// <summary>Smoke-test entry: open the details pane the way the button does.</summary>
    public void ExpandDetailsForAutomation() => ToggleDetails(true);

    private void Disclosure_Click(object sender, RoutedEventArgs e) => ToggleDetails(!_detailsOpen);

    private void ToggleDetails(bool open)
    {
        _detailsOpen = open;
        ConsolePane.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
        DisclosureChevron.Glyph = open ? Glyphs.ChevronDown : Glyphs.ChevronRight;
        DisclosureLabel.Text = open ? "Hide details" : "Show details";
        _renderedTranscriptVersion = -1;
        Render();
    }

    private void ConsoleSend_Click(object sender, RoutedEventArgs e) => SendConsoleInput();

    private void ConsoleInput_KeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter) { SendConsoleInput(); e.Handled = true; }
    }

    private void SendConsoleInput()
    {
        _runner?.SendLine(ConsoleInput.Text);
        ConsoleInput.Text = "";
    }

    private void ConsoleStop_Click(object sender, RoutedEventArgs e) => _runner?.Terminate();

    private string? _publishedFolder;

    private void TaskCancel_Click(object sender, RoutedEventArgs e)
    {
        if (OnCancel is not null)
        {
            OnCancel.Invoke();
        }
        else
        {
            _runner?.CancelByUser();
        }
    }

    private void FolderResult_Click(object sender, RoutedEventArgs e)
    {
        if (_publishedFolder is { } folder) FolderActions.ShowInFileExplorer(folder);
    }
}
