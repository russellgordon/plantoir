using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Services;

namespace Plantoir.Views;

/// <summary>
/// One section: preview it in an embedded browser, publish it, watch either
/// as a layered progress task. Created fresh per selection so runners and
/// leases never leak between sections.
/// </summary>
public sealed partial class SectionDetailView : UserControl
{
    private readonly MainWindow _window;
    private readonly Course _course;
    private readonly int _sectionNumber;
    private readonly ScriptRunner _previewRunner = new(SynchronizationContext.Current);
    private readonly MultiDestinationDeployRunner _deployRunner = new(SynchronizationContext.Current);
    private PreviewLeases.Lease? _lease;

    // The on-disk half of the same claims. In-memory leases are invisible to
    // the MCP server, which is a different process entirely.
    private IDisposable? _previewWork;
    private IDisposable? _publishWork;
    private IDisposable? _publishActivity;

    /// <summary>
    /// Held only while a build is actually running, and dropped the moment the
    /// preview server answers. The preview lease beside it lasts as long as the
    /// SERVER does, which is a different question: serving is not a conflict,
    /// building is.
    /// </summary>
    private IDisposable? _buildWork;
    private Uri? _previewUrl;
    private Uri? _lastLoadedUrl;
    private bool _isWaitingForServer;
    private CancellationTokenSource? _serverWait;

    /// <summary>
    /// True for the span between Deploy being clicked and
    /// <see cref="MultiDestinationDeployRunner.RunAsync"/> actually taking
    /// over — <c>_deployRunner.IsRunning</c> alone stays false through that
    /// whole prep phase (stopping a running preview can take ~20s), which
    /// left the Deploy button clickable again the instant the phase
    /// started and let a second click race the first's own
    /// stop-preview-then-deploy sequence. Mirrors the mac's
    /// `SectionDetailView.isPreparingDeploy` (WINDOWS-HANDOFF.md item 8,
    /// row 318a).
    /// </summary>
    private bool _isPreparingDeploy;

    /// <summary>
    /// Guards <see cref="RefreshPublishedMarker"/> against an out-of-order
    /// result: several triggers (window activation, a run finishing) can
    /// fire in quick succession, and a walk started before a publish must
    /// not overwrite one started after it. Mirrors the mac's generation
    /// counter — see "The refresh triggers" in WINDOWS-HANDOFF.md.
    /// </summary>
    private int _publishMarkerGeneration;

    // ---- Folder problems --------------------------------------------------
    //
    // Held in view state rather than read off the runner when a dialog is
    // built, so a teacher who dismisses it and carries on editing does not
    // meet it again on the next redraw. A healthy course must see nothing at
    // all: the failure mode for this whole feature is nagging, and a warning
    // dismissed by habit is one that gets dismissed when it matters.

    /// <summary>True while a folder-problem dialog is on screen.</summary>
    private bool _healthDialogIsUp;

    /// <summary>
    /// Set the moment this view is taken off screen, so an operation that was
    /// awaiting something slow can tell that it is now working on behalf of a
    /// section nobody is looking at.
    ///
    /// <para><b>It is not earlier than <c>IsLoaded</c>, and an earlier comment
    /// here claimed it was.</b> Both change on <c>Unloaded</c>, which WinUI
    /// dispatches rather than raising the instant
    /// <c>DetailHost.Content</c> is reassigned — so a just-replaced view
    /// briefly reports itself loaded, and this flag does not close that
    /// window. What it buys is a signal that can be checked from a background
    /// continuation without touching a XAML property, and one place to put the
    /// reason. The window is a dispatcher tick against awaits measured in
    /// seconds, which is why it is left as it is rather than replaced with a
    /// visual-tree walk.</para>
    /// </summary>
    private bool _isTornDown;

    /// <summary>
    /// What is waiting to be shown and what has been shown already.
    ///
    /// <para>Findings are HELD, not dropped, while a dialog is up: never swap
    /// the contents of one that is already on screen — the title and the
    /// message would change under the teacher's cursor and what they were
    /// reading would vanish unacknowledged — but discarding them is not the
    /// alternative either, since a failed deploy can report while an earlier
    /// batch is still up.</para>
    /// </summary>
    private readonly FolderProblemQueue _healthQueue = new();

    /// <summary>
    /// True between a finding arriving and the dialog for it being built.
    ///
    /// <para>Presentation is posted to the dispatcher rather than run inside
    /// the notification, and that is load-bearing: <c>site_health.py</c> prints
    /// every finding in one burst, so they arrive in ONE pseudo-console flush
    /// and the runner announces them one after another on the same stack.
    /// Showing on the first announcement would put up a dialog naming one
    /// problem and then a second naming both. By the time a posted
    /// presentation runs, the whole flush has been collected.</para>
    /// </summary>
    private bool _healthPresentationQueued;

    public string CourseCode => _course.Code;
    public int SectionNumber => _sectionNumber;

    /// <summary>
    /// Raised whenever the browser-chrome state (back/forward/reload
    /// availability) may have changed, so the app's Preview menu — which
    /// tracks whichever section is currently shown — can refresh without
    /// polling. Mirrors mac's PreviewCommands, which reads the same state
    /// via @FocusedValue instead of an event.
    /// </summary>
    public event EventHandler? PreviewChromeChanged;

    /// <summary>Whether a preview is loaded at all — mirrors mac's disabling Reload when there is no controller.</summary>
    public bool HasPreview => _previewUrl is not null;
    public bool CanGoBack => HasPreview && Preview.CanGoBack;
    public bool CanGoForward => HasPreview && Preview.CanGoForward;

    /// <summary>Menu-bar equivalents of Back_Click/Forward_Click/Reload_Click, for the Preview menu.</summary>
    public void PreviewGoBack() { if (Preview.CanGoBack) Preview.GoBack(); }
    public void PreviewGoForward() { if (Preview.CanGoForward) Preview.GoForward(); }
    public void PreviewReload() { if (HasPreview) Preview.Reload(); }

    internal bool IsBusy => _previewRunner.IsRunning || _deployRunner.IsRunning;
    // What "busy" means to a DEPLOY since the deploy-during-preview port: a
    // running preview no longer stands in the way (Deploy stops it itself),
    // so only a deploy already running does. Mac parity: deployAndWait()'s
    // check is deployRunner.isRunning, evaluated after the stop.
    internal bool IsDeploying => _deployRunner.IsRunning;
    private string TitleText => $"{_course.Code}-S{_sectionNumber}";

    public SectionDetailView(MainWindow window, Course course, int sectionNumber)
    {
        InitializeComponent();
        _window = window;
        _course = course;
        _sectionNumber = sectionNumber;
        SectionTitle.Text = TitleText;
        ObsidianButton.IsEnabled = FolderActions.ObsidianIsInstalled;

        // The empty-state invitation follows the course's destination —
        // "to Netlify" would be wrong twice over for a folder-publishing course.
        NoPreviewDetail.Text = course.Configuration.DeploysToLocalFolder
            ? "Click Preview to build this section's website and see it here, or Deploy to copy it to your deploy folder."
            : "Click Preview to build this section's website and see it here, or Deploy to put it online.";

        // Each runner is bound to the progress view exactly once — its
        // question dialog and outcome states follow whichever runner the
        // view is currently showing, chosen in RefreshChrome via Show().
        // _deployRunner's own leg runners are registered lazily, as each
        // becomes active — see RefreshChrome's Progress.Show call, which
        // registers idempotently. Only one leg is ever running at a time,
        // so there is never a moment a question from an un-registered leg
        // could be missed.
        Progress.Register(_previewRunner);
        _previewRunner.PropertyChanged += (_, args) =>
        {
            RefreshChrome();
            if (args.PropertyName == nameof(_previewRunner.IsRunning) && !_previewRunner.IsRunning)
                _ = RefreshPublishedMarker();
            // A new build asks the question again, so a problem it still finds
            // is told again — "show it once" means once per BUILD, not once
            // for the life of this view.
            if (args.PropertyName == nameof(_previewRunner.IsRunning) && _previewRunner.IsRunning)
                _healthQueue.ForgetShown();
            // As the build reports them. preview.ps1 does not exit while it is
            // serving, so waiting for this runner to FINISH would hold the
            // dialog until the teacher pressed Stop.
            if (args.PropertyName == nameof(_previewRunner.HealthFindings))
                NoteHealthFindings(_previewRunner);
        };
        _deployRunner.PropertyChanged += (_, args) =>
        {
            RefreshChrome();
            if (args.PropertyName == nameof(_deployRunner.IsRunning) && !_deployRunner.IsRunning)
                _ = RefreshPublishedMarker();
        };
        Preview.NavigationCompleted += (_, _) => RefreshChrome();
        _window.Activated += OnWindowActivated;
        // Anything last night's scheduled deploy found. It ran with the app
        // closed, so this is the first moment there is anywhere to say it.
        // On Loaded rather than in the constructor: presenting needs a
        // XamlRoot, and the view has none until it is in the tree.
        Loaded += (_, _) => TakeAnythingTheScheduledDeployFound();
        Unloaded += (_, _) => { _isTornDown = true; StopPreview(); _window.Activated -= OnWindowActivated; };
        RefreshChrome();
        _ = RefreshPublishedMarker();
    }

    // ---- The " — Edited" marker -------------------------------------------

    private void OnWindowActivated(object sender, WindowActivatedEventArgs args)
    {
        if (args.WindowActivationState == WindowActivationState.Deactivated) return;
        _ = RefreshPublishedMarker();
        // Also here, not only on Loaded. A teacher who leaves Plantoir open
        // overnight — which the scheduled-deploy feature itself suggests, to
        // keep the machine awake — keeps the SAME view instance on the same
        // section, so Loaded never fires again and last night's findings would
        // wait until they clicked away and back. It is a File.Exists when
        // nothing is waiting.
        TakeAnythingTheScheduledDeployFound();
    }

    /// <summary>
    /// Recomputes whether this section has unpublished edits and, if so,
    /// appends " — Edited" to the in-pane section header — the closest
    /// Windows equivalent of the mac's per-section window title bar, since
    /// this app shows one section at a time inside a single MainWindow
    /// rather than one OS window per section. Never touches
    /// <see cref="TitleText"/> itself: that bare name is used everywhere a
    /// sentence NAMES the section (deploy progress, dialogs), and the marker
    /// must never leak into one of those — a real report read "Deploying
    /// ICS3U-S1 — Edited" as though "Edited" were being published.
    ///
    /// Runs the file walk off the UI thread so a course on a slow network
    /// volume cannot stutter the window coming to the front, and applies the
    /// result only if this is still the most recent request.
    /// </summary>
    private async Task RefreshPublishedMarker()
    {
        int generation = ++_publishMarkerGeneration;
        string courseDirectory = _course.DirectoryPath;
        int sectionNumber = _sectionNumber;
        var excluded = SectionPublishState.SelfPublishingSubpaths(
            courseDirectory, _course.Configuration.AllDeployDestinations);

        bool edited;
        try
        {
            edited = await Task.Run(() =>
                SectionPublishState.HasUnpublishedEdits(courseDirectory, sectionNumber, excluded));
        }
        catch { return; } // never let this stand in for a real failure elsewhere

        if (generation != _publishMarkerGeneration) return; // superseded by a newer refresh
        SectionTitle.Text = SectionPublishState.WindowTitle(TitleText, edited);
    }

    // ---- Chrome state ----------------------------------------------------

    private void RefreshChrome()
    {
        bool previewShown = _previewUrl is not null;
        BackButton.IsEnabled = previewShown && Preview.CanGoBack;
        ForwardButton.IsEnabled = previewShown && Preview.CanGoForward;
        ReloadButton.IsEnabled = previewShown;
        BrowserButton.IsEnabled = previewShown;

        // Previewing DURING a conversation is the point of the assistant, not
        // a conflict with it: the teacher reads the preview to judge the change
        // they just asked for. So a session being open changes nothing here.
        // Only a build actually in flight stands in the way, and only for the
        // seconds it runs, because two builds clear the same output folder.
        bool building = _window.Workspace.WorkspacePath is { } folder &&
                        CourseActivity.IsBuildingElsewhere(folder, _course.Code);
        // Deploying WHILE a preview runs is allowed (parity with the mac,
        // commit "Allow Deploy button to stop active preview before
        // publishing"): Deploy_Click stops the preview itself and waits for
        // the stop — sweep included — before building. Only a deploy already
        // running disables the button.
        DeployButton.IsEnabled = !_deployRunner.IsRunning && !_isPreparingDeploy && !building;
        if (building)
            ToolTipService.SetToolTip(DeployButton, $"Available in a moment — {_course.Code} is being built");

        bool running = _previewRunner.IsRunning;
        PreviewLabel.Text = running ? "Stop Preview" : "Preview";
        PreviewIcon.Glyph = running ? Glyphs.Stop : Glyphs.Play;
        ToolTipService.SetToolTip(PreviewButton,
            running ? "Stop previewing this section"
            : building ? $"Available in a moment — {_course.Code} is being built"
            : "Preview this section's website");
        // Stopping a preview already under way is always allowed.
        PreviewButton.IsEnabled = running || (!IsBusy && !building);

        // Which task owns the console: the running one, else the most recent.
        // Bind ONCE per runner (in the constructor) and only swap which is
        // shown here — re-subscribing on every event could swallow the
        // IsAwaitingInput transition that raises the question dialog.
        bool showDeploy = !_previewRunner.IsRunning &&
            (_deployRunner.IsRunning || _isPreparingDeploy ||
             (_deployRunner.StartedAt ?? DateTime.MinValue) > (_previewRunner.StartedAt ?? DateTime.MinValue));
        if (showDeploy)
        {
            // _isPreparingDeploy: nothing is running on _deployRunner yet —
            // ActiveRunner would either be blank (a fresh leg has never
            // rendered) or the PREVIOUS deploy's stale outcome. Neither is
            // what is actually happening right now (row 318a).
            if (_isPreparingDeploy && !_deployRunner.IsRunning)
            {
                Progress.ShowPreparing($"Deploying {TitleText}");
            }
            else
            {
                // Multi-destination courses get a leg count in the title, so a
                // teacher watching the progress bar knows it is running a
                // sequence rather than a single deploy that is unusually slow.
                string title = _deployRunner.Legs.Count > 1
                    ? $"Deploying {TitleText} — destination {Math.Min(_deployRunner.CurrentLegIndex + 1, _deployRunner.Legs.Count)} of {_deployRunner.Legs.Count}"
                    : $"Deploying {TitleText}";
                Progress.Show(_deployRunner.ActiveRunner, title, onCancel: CancelDeploy, multiRunner: _deployRunner);
            }
        }
        else
            Progress.Show(_previewRunner,
                _previewRunner.IsRunning || _isWaitingForServer
                    ? $"Preparing the preview of {TitleText}"
                    : $"Preview of {TitleText}",
                onCancel: CancelPreview);

        bool anyOutput = _previewRunner.Transcript.Lines.Count > 0 || _deployRunner.HasAnyOutput
                         || _previewRunner.Transcript.CurrentLine.Length > 0;
        bool showConsole = _isWaitingForServer || IsBusy || _isPreparingDeploy || anyOutput;
        Progress.Visibility = showConsole ? Visibility.Visible : Visibility.Collapsed;
        NoPreviewState.Visibility = showConsole ? Visibility.Collapsed : Visibility.Visible;
        Preview.Visibility = previewShown ? Visibility.Visible : Visibility.Collapsed;

        PreviewChromeChanged?.Invoke(this, EventArgs.Empty);
    }

    private XamlRoot? EffectiveXamlRoot => XamlRoot ?? _window.Content?.XamlRoot;

    private async Task<ContentDialogResult?> ShowDialogSafelyAsync(ContentDialog dialog)
    {
        if (EffectiveXamlRoot is { } root)
        {
            dialog.XamlRoot = root;
            try
            {
                return await dialog.ShowAsync();
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"ShowDialogSafelyAsync for '{dialog.Title}' exception: {ex.Message}");
                return null;
            }
        }
        else
        {
            App.LogDiagnostic($"Cannot show dialog '{dialog.Title}': No XamlRoot available.");
            return null;
        }
    }

    // ---- Folder problems -------------------------------------------------

    /// <summary>
    /// Put a run's folder problems in front of the teacher.
    ///
    /// <para>Called when the build REPORTS them, never when a preview finishes
    /// — and that distinction is the whole reason this feature reaches anybody.
    /// <c>preview.ps1</c> does not exit while it is serving, so a runner on the
    /// preview path stays running until the teacher presses Stop; and a section
    /// missing its <c>index.md</c> makes every request 404, so the server wait
    /// never succeeds either. Gating on either one would hide the dialog behind
    /// a preview that the very problem it reports prevents from completing: the
    /// worse the course, the less likely the teacher was to be told.</para>
    ///
    /// <para>A healthy course reports nothing and sees nothing.</para>
    /// </summary>
    /// <summary>
    /// Read out whatever last night's scheduled deploy left for this section.
    ///
    /// <para>Marked as having come from a PUBLISH, because it did: the overnight
    /// run went out to students, so a repair made now is not on their site
    /// until the teacher publishes again, and that is the sentence they need.</para>
    ///
    /// <para><b>Guarded BEFORE consuming</b>, which is the mac's lesson and was
    /// nearly not taken. The record is DELETED as it is read, and the queue
    /// holding what it cannot show yet is ALMOST enough — but that queue is a
    /// field of this view, and the view is discarded when the teacher selects
    /// another section. So a batch consumed while a dialog was up, whose own
    /// dialog then never got on screen, would live only in an object about to
    /// be thrown away. Not consuming at all in that state costs one morning;
    /// consuming and losing it costs the record for ever.</para>
    /// </summary>
    private void TakeAnythingTheScheduledDeployFound()
    {
        if (_healthDialogIsUp || _healthQueue.PendingCount > 0) return;
        try
        {
            var waiting = ScheduledHealthFindings.Take(_course.Code, _sectionNumber);
            if (waiting.Count > 0) NoteHealthFindings(waiting, cameFromPublishing: true);
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"TakeAnythingTheScheduledDeployFound exception: {ex}");
        }
    }

    private void NoteHealthFindings(ScriptRunner? runner, bool cameFromPublishing = false)
    {
        if (runner is null) return;
        NoteHealthFindings(runner.HealthFindings, cameFromPublishing);
    }

    private void NoteHealthFindings(IReadOnlyList<SiteHealthFinding> findings, bool cameFromPublishing)
    {
        if (_healthQueue.Note(findings, cameFromPublishing)) QueueHealthPresentation();
    }

    private void QueueHealthPresentation()
    {
        if (_healthPresentationQueued || _healthDialogIsUp) return;
        _healthPresentationQueued = true;
        bool accepted = DispatcherQueue.TryEnqueue(async () =>
        {
            _healthPresentationQueued = false;
            await PresentPendingHealthFindingsAsync();
        });
        // A refused enqueue (the dispatcher is shutting down) would otherwise
        // leave the flag set forever, and every later finding would be dropped
        // by the guard above rather than shown.
        if (!accepted) _healthPresentationQueued = false;
    }

    /// <summary>
    /// Show what is waiting, then whatever arrived while it was on screen.
    /// </summary>
    private async Task PresentPendingHealthFindingsAsync()
    {
        if (_healthDialogIsUp) return;
        if (_healthQueue.TakeNext() is not { } next) return;
        var findings = next.Findings;
        bool cameFromPublishing = next.CameFromPublishing;

        _healthDialogIsUp = true;
        bool putBack = false;
        try
        {
            var choice = await ShowHealthDialogAsync(FolderProblemsDialog.Findings(findings));
            if (choice is null)
            {
                // It never got on screen — another dialog held the one slot
                // WinUI allows, for longer than the retries covered. Hand the
                // batch back rather than losing it: TakeNext marked it shown,
                // and a dialog nobody saw has told nobody anything.
                _healthQueue.PutBack(findings, cameFromPublishing);
                putBack = true;
            }
            else if (choice == ContentDialogResult.Primary)
            {
                var outcome = SiteHealthRepair.OutcomeOfRepairing(
                    findings, _course,
                    cameFromPublishing
                        ? SiteHealthRepair.Occasion.Publishing
                        : SiteHealthRepair.Occasion.Building);
                // The marker is refreshed because a repair CHANGES the
                // section's content on the teacher's behalf, and nothing else
                // would: RefreshPublishedMarker runs when the section stops
                // being busy and on window activation, and the section stopped
                // being busy before this dialog appeared while a dialog does
                // not make the window active again.
                _ = RefreshPublishedMarker();
                if (outcome is not null)
                {
                    // Shown only AFTER the dialog it was asked for from has
                    // gone — contracts/shared-rules.json ->
                    // siteHealth.repair.oneAlertAtATime.
                    if (outcome.CanRebuild && WhyTheRepairCannotBePreviewedNow() is { } instead)
                        outcome = instead;
                    await PresentRepairOutcomeAsync(outcome);
                }
            }
        }
        finally
        {
            _healthDialogIsUp = false;
        }

        if (putBack)
        {
            // Try again once whatever is holding the slot has had time to go,
            // rather than recursing straight back into the same refusal. It
            // stops of its own accord: the batch is presented the first time
            // the slot is free.
            await Task.Delay(2000);
            // Not onto a section nobody is looking at. EffectiveXamlRoot falls
            // back to the WINDOW's root, so a replaced view would go on
            // retrying and eventually put a dialog about the old section over
            // whatever the teacher switched to.
            if (_isTornDown || !IsLoaded) return;
            QueueHealthPresentation();
            return;
        }

        await PresentPendingHealthFindingsAsync();
    }

    private async Task PresentRepairOutcomeAsync(SiteHealthRepair.Outcome outcome)
    {
        var choice = await ShowHealthDialogAsync(FolderProblemsDialog.RepairOutcome(outcome));
        if (choice == ContentDialogResult.Primary) await PreviewAgainAfterRepairAsync();
    }

    /// <summary>
    /// Why "Preview Again" would not work just now, or null when it would.
    ///
    /// <para>Say so rather than swallowing the press. Every other gated control
    /// here disables itself or explains; a button that quietly does nothing is
    /// the silence this whole feature exists to remove, arriving in the button
    /// meant to end it.</para>
    ///
    /// <para>The publish question is asked of <see cref="CourseActivity"/>, not
    /// of this view's own deploy runner: the assistant publishes the same
    /// section in the same process and is invisible to it. And it says "this
    /// course", not "this section", because the check matches on the folder and
    /// the course code and deliberately ignores the section number — publishing
    /// section 2 would otherwise be reported as section 1 publishing.</para>
    /// </summary>
    private SiteHealthRepair.Outcome? WhyTheRepairCannotBePreviewedNow()
    {
        if (_window.Workspace.WorkspacePath is not { } workspacePath) return null;

        // Said in the same shape as the other two rather than through
        // TheAssistantIsBuilding()'s own dialog: that one is a second
        // ContentDialog raised while the outcome dialog is still closing,
        // which WinUI refuses — and its refusal is swallowed, so the press
        // would do nothing and say nothing. Silence, in the button meant to
        // end silence.
        if (CourseActivity.IsBuildingElsewhere(workspacePath, _course.Code))
        {
            return new SiteHealthRepair.Outcome(
                $"{_course.Code} is being built just now.",
                "The assistant is rebuilding this course, and building it here at the same time " +
                "would clash. You can preview it again once that has finished, and the change " +
                "will be there.",
                false);
        }

        if (_lease is null && PreviewLeases.Active.Any(
                lease => lease.FolderPath == workspacePath
                         && lease.CourseCode == _course.Code
                         && lease.SectionNumber == _sectionNumber))
        {
            return new SiteHealthRepair.Outcome(
                "This section is open in another window.",
                "Preview it from there to see the change.",
                false);
        }

        if (_deployRunner.IsRunning || _isPreparingDeploy
            || CourseActivity.IsPublishing(workspacePath, _course.Code))
        {
            return new SiteHealthRepair.Outcome(
                "Plantoir is publishing this course just now.",
                // Deliberately not "press Preview Again": this is the outcome
                // whose button is withheld, and naming a button that is not on
                // screen is worse than saying nothing.
                "You can preview it again once that has finished, and the change will be there.",
                false);
        }
        return null;
    }

    /// <summary>
    /// Build the site again after a repair, so the teacher can see it.
    ///
    /// <para>A preview that is already up is stopped and started again rather
    /// than left alone: <c>content/</c> is a one-off copy made during the
    /// build, and the only watcher in preview mode syncs the built site out to
    /// this PC — nothing carries a folder restored on disk into a preview that
    /// is already serving. Live reload does not cover this.</para>
    ///
    /// <para>The LEASE decides whether to stop, not the window's appearance: a
    /// preview whose wait timed out has cleared <c>_isWaitingForServer</c> and
    /// never set <c>_previewUrl</c> while still holding the port, so asking
    /// those two would skip the stop and then be refused the lease — raising a
    /// refusal dialog out of a repair.</para>
    ///
    /// <para>One consequence worth knowing: a preview build is never
    /// deploy-fresh (<c>app-rules.json</c> -&gt; <c>buildFreshness</c>), so
    /// previewing after a successful publish means the NEXT publish rebuilds.
    /// Correct rather than unfortunate, and largely moot — the repair puts
    /// content back, which forces a rebuild anyway.</para>
    /// </summary>
    private async Task PreviewAgainAfterRepairAsync()
    {
        try
        {
            // Asked AGAIN, at the press. The button was offered when the
            // outcome dialog was built, and a teacher reads for as long as
            // they like — a publish can start in that time, from the assistant
            // as easily as from this window, and starting a build into a
            // course being published is the race DeployAsync spends thirty
            // lines avoiding. Withheld here means saying so, in the same
            // dialog shape, rather than swallowing the press.
            if (WhyTheRepairCannotBePreviewedNow() is { } instead)
            {
                await PresentRepairOutcomeAsync(instead);
                return;
            }

            if (_lease is not null || _previewRunner.IsRunning) await StopPreviewAsync();

            // The stop can take ~20 seconds with the dialog already gone, and
            // the teacher is free to click another section meanwhile — which
            // replaces this view. Starting a preview from a view nobody can
            // see leaves a running preview.ps1 on a runner with no window and
            // a lease that refuses the section's own Preview button
            // afterwards.
            if (_isTornDown || !IsLoaded) return;

            // Asked AGAIN after the stop, for the reason DeployAsync gives at
            // the same point in its own sequence: the leases came off with the
            // preview and the stop takes long enough for somebody else to
            // start. WorkLease is an announcement, not a refusal, so nothing
            // downstream would stop a build landing on top of the assistant's.
            if (WhyTheRepairCannotBePreviewedNow() is { } nowInstead)
            {
                await PresentRepairOutcomeAsync(nowInstead);
                return;
            }
            StartAutomatedPreview();
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"PreviewAgainAfterRepairAsync exception: {ex}");
        }
    }

    /// <summary>
    /// <see cref="ShowDialogSafelyAsync"/>, but it does not give up on the
    /// first refusal.
    ///
    /// <para>WinUI allows one <c>ContentDialog</c> on screen at a time, and
    /// <c>ShowAsync</c> completes when the dialog BEGINS closing rather than
    /// when it has gone — so asking for the outcome report immediately after
    /// the findings dialog can be refused. Swallowing that (which
    /// <see cref="ShowDialogSafelyAsync"/> does, correctly, for one-off
    /// dialogs) would lose exactly the report the teacher just pressed a
    /// button for, which is the failure path this feature exists to close.</para>
    /// </summary>
    private async Task<ContentDialogResult?> ShowHealthDialogAsync(ContentDialog dialog)
    {
        for (int attempt = 0; attempt < 5; attempt++)
        {
            if (EffectiveXamlRoot is not { } root)
            {
                App.LogDiagnostic($"Cannot show '{dialog.Title}': no XamlRoot available.");
                return null;
            }
            dialog.XamlRoot = root;
            try
            {
                return await dialog.ShowAsync();
            }
            catch (Exception ex)
            {
                // Once per batch, not once per attempt: a teacher reading
                // another dialog would otherwise fill the log with five lines
                // every couple of seconds for as long as they take.
                if (attempt == 0)
                    App.LogDiagnostic($"Folder-problem dialog refused, retrying: {ex.Message}");
                await Task.Delay(150);
            }
        }
        return null;
    }

    // ---- Preview ---------------------------------------------------------

    /// <summary>Smoke-test entry: the same path the Preview button takes.</summary>
    public void StartPreviewForAutomation() => PreviewOrStop_Click(this, new RoutedEventArgs());

    /// <summary>
    /// Start the preview if nothing is currently previewing. If a preview
    /// is already serving, starting is skipped — live reload will catch the
    /// edit on its own, and starting again would tear down and rebuild the
    /// very thing the teacher was being shown.
    /// </summary>
    public void StartPreviewIfIdle()
    {
        try
        {
            if (_previewRunner.IsRunning || _isWaitingForServer || _previewUrl is not null) return;
            StartAutomatedPreview();
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"StartPreviewIfIdle exception: {ex}");
        }
    }

    private async void StartAutomatedPreview()
    {
        try
        {
            if (_previewRunner.IsRunning) { StopPreview(); return; }
            if (_window.Workspace.WorkspacePath is not { } workspacePath) return;

            // Clear any prior lease for this section before starting anew
            PreviewLeases.Release(workspacePath, _course.Code, _sectionNumber);
            _lease = null;

            try
            {
                _lease = PreviewLeases.Take(workspacePath, _course.Code, _sectionNumber);
                _previewWork = WorkLease.Take(workspacePath, _course.Code, WorkLease.Previewing);
                _buildWork = WorkLease.Take(workspacePath, _course.Code, WorkLease.Building);
            }
            catch (PreviewLeases.LeaseRefusedException refusal)
            {
                App.LogDiagnostic($"StartAutomatedPreview refused for {_course.Code} Section {_sectionNumber}: {refusal.Message}");
                return;
            }

            // The same stop-sweep race the deploy path guards against: a
            // just-stopped preview's sweep would kill this one's build.
            await PreviewStopper.WaitForStopsToFinish(_course.Code, _sectionNumber);

            _previewUrl = null;
            _lastLoadedUrl = null;
            _isWaitingForServer = true;
            _previewRunner.Milestones = TaskMilestones.Preview;
            _previewRunner.Run("preview.ps1",
                new[] { _course.Code, _sectionNumber.ToString(), "--port", _lease.Port.ToString() },
                workspacePath);
            RefreshChrome();
            await WaitForPreviewServer(_lease.Port);
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"StartAutomatedPreview exception: {ex}");
        }
    }

    /// <summary>Stop the preview if one is up — the assistant's half of stop, edit, start again.</summary>
    public void StopPreviewIfRunning()
    {
        if (_previewRunner.IsRunning || _isWaitingForServer || _previewUrl is not null || _lease is not null)
        {
            StopPreview();
        }
    }

    /// <summary>Asynchronously stop the preview if running, awaiting container process termination.</summary>
    public async Task StopPreviewIfRunningAsync()
    {
        if (_previewRunner.IsRunning || _isWaitingForServer || _previewUrl is not null || _lease is not null)
        {
            await StopPreviewAsync();
        }
    }

    /// <summary>Smoke-test entry: open the console details pane.</summary>
    public void ShowDetailsForAutomation() => Progress.ExpandDetailsForAutomation();

    /// <summary>Smoke-test entry: the same path the Deploy button takes.</summary>
    public void StartDeployForAutomation() => Deploy_Click(this, new RoutedEventArgs());

    /// <summary>
    /// The assistant's entry point: the same path as the Deploy button, but
    /// AWAITS the real outcome instead of returning the moment the click was
    /// dispatched. Returns <see cref="DeployAsync"/>'s own return value
    /// directly — deliberately NOT correlated through a shared field, so a
    /// second call in flight at the same time (the busy branch in
    /// <c>AssistAgent.RunTool</c> fires one of these even while a deploy is
    /// already running, to nudge the app forward) gets its OWN outcome and
    /// can never steal or orphan another caller's pending await.
    /// </summary>
    public Task<string?> StartDeployForAutomationAsync() => DeployAsync();

    /// <summary>
    /// Refuse to start a build while the assistant is running one.
    ///
    /// Checked at the CLICK, not just when the buttons were last drawn: a
    /// build can start at any moment in the other process, and the chrome only
    /// redraws when a runner or the browser says something. The disabled
    /// button is the courtesy; this is the guarantee.
    ///
    /// Both would otherwise build into
    /// <c>.merged_output/section&lt;N&gt;/</c>, which the build clears before
    /// writing — so the loser serves a half-written site, or deploys files
    /// the other just deleted.
    ///
    /// It waits on a BUILD, never on the conversation. Waiting on the whole
    /// session made a teacher choose between watching their preview and
    /// talking about it, and those two things belong together.
    /// </summary>
    private async Task<bool> TheAssistantIsBuilding()
    {
        if (_window.Workspace.WorkspacePath is not { } folder) return false;
        if (!CourseActivity.IsBuildingElsewhere(folder, _course.Code)) return false;

        var dialog = new ContentDialog
        {
            Title = $"{_course.Code} is being built",
            Content = "The assistant is rebuilding this course right now, and building it here at the " +
                      "same time would clash — both write to the same place. This usually takes a few " +
                      "seconds; try again when it finishes.",
            CloseButtonText = "OK",
        };
        await ShowDialogSafelyAsync(dialog);
        RefreshChrome();
        return true;
    }

    private async void PreviewOrStop_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (_previewRunner.IsRunning) { StopPreview(); return; }
            if (await TheAssistantIsBuilding()) return;
            if (_window.Workspace.WorkspacePath is not { } workspacePath) return;

            try
            {
                _lease = PreviewLeases.Take(workspacePath, _course.Code, _sectionNumber);
                // Say so on disk as well as in memory: an assistant is a separate
                // process and cannot see the in-memory lease.
                _previewWork = WorkLease.Take(workspacePath, _course.Code, WorkLease.Previewing);
                // Dropped as soon as the server answers — see ReleaseBuildClaim.
                _buildWork = WorkLease.Take(workspacePath, _course.Code, WorkLease.Building);
            }
            catch (PreviewLeases.LeaseRefusedException refusal)
            {
                App.LogDiagnostic($"Preview refused for {_course.Code} Section {_sectionNumber}: {refusal.Message}");
                var dialog = new ContentDialog
                {
                    Title = "Cannot Preview Yet",
                    Content = refusal.Message,
                    CloseButtonText = "OK",
                };
                await ShowDialogSafelyAsync(dialog);
                return;
            }

            // The same stop-sweep race the deploy path guards against: a
            // just-stopped preview's sweep would kill this one's build.
            await PreviewStopper.WaitForStopsToFinish(_course.Code, _sectionNumber);

            _previewUrl = null;
            _lastLoadedUrl = null;
            _isWaitingForServer = true;
            _previewRunner.Milestones = TaskMilestones.Preview;
            _previewRunner.Run("preview.ps1",
                new[] { _course.Code, _sectionNumber.ToString(), "--port", _lease.Port.ToString() },
                workspacePath);
            RefreshChrome();
            await WaitForPreviewServer(_lease.Port);
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"PreviewOrStop_Click exception: {ex}");
        }
    }

    /// <summary>
    /// Phase 1: never trust the port until THIS run announces its launch —
    /// a stale server from a previous preview answers first. Phase 2: poll
    /// until HTTP 200. Ten minutes total, because a first-ever build pulls
    /// the image and installs dependencies.
    /// </summary>
    private async Task WaitForPreviewServer(int containerPort)
    {
        _serverWait?.Cancel();
        var cancel = new CancellationTokenSource();
        _serverWait = cancel;
        Uri serverUrl = new($"http://127.0.0.1:{containerPort}/");
        const int budgetSeconds = 600;
        int elapsed = 0;

        try
        {
            while (elapsed < budgetSeconds)
            {
                if (cancel.IsCancellationRequested) return;
                if (!_previewRunner.IsRunning && _previewRunner.LastExitCode is not null)
                {
                    AbandonWait();
                    return;
                }
                if (_previewRunner.PreviewAddress is { } announced) serverUrl = announced;
                if (_previewRunner.Transcript.DisplayText.Contains("Launching Quartz preview")) break;
                await Task.Delay(1000);
                elapsed++;
            }

            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
            while (elapsed < budgetSeconds)
            {
                if (cancel.IsCancellationRequested) return;
                if (!_previewRunner.IsRunning && _previewRunner.LastExitCode is not null)
                {
                    AbandonWait();
                    return;
                }
                try
                {
                    var response = await client.GetAsync(serverUrl);
                    if (response.IsSuccessStatusCode)
                    {
                        // The site is up, so the build is over: the assistant
                        // may build again from here on, while this preview
                        // stays on screen for the teacher to read.
                        _isWaitingForServer = false;
                        ReleaseBuildClaim();
                        _previewUrl = serverUrl;
                        LoadIfNeeded(serverUrl);
                        RefreshChrome();
                        return;
                    }
                }
                catch { }
                await Task.Delay(1000);
                elapsed++;
            }
            // The server never answered. The build is over either way, so the
            // claim must not outlive it.
            _isWaitingForServer = false;
            ReleaseBuildClaim();
            RefreshChrome();
        }
        finally
        {
            if (_serverWait == cancel) _serverWait = null;
        }
    }

    private void AbandonWait()
    {
        _isWaitingForServer = false;
        ReleaseLease();
        RefreshChrome();
    }

    /// <summary>Interface updates must never yank the teacher back from a page they navigated to.</summary>
    private void LoadIfNeeded(Uri url)
    {
        if (_lastLoadedUrl == url) return;
        _lastLoadedUrl = url;
        Preview.Source = url;
    }

    private void CancelPreview()
    {
        if (_previewRunner.IsRunning && _window.Workspace.WorkspacePath is { } workspacePath)
            PreviewStopper.StopSectionProcesses(workspacePath, _course.Code, _sectionNumber);
        _previewRunner.CancelByUser();
        _previewUrl = null;
        _isWaitingForServer = false;
        ReleaseLease();
        RefreshChrome();
    }

    private void CancelDeploy()
    {
        if (_deployRunner.IsRunning && _window.Workspace.WorkspacePath is { } workspacePath)
            PreviewStopper.StopSectionProcesses(workspacePath, _course.Code, _sectionNumber);
        _deployRunner.Cancel();
    }

    private void StopPreview()
    {
        // Whenever a preview was actually running (or still building),
        // reclaim its container-side processes too — ending the host
        // launcher alone leaves the serve chain alive inside the container.
        // The sweep launches BEFORE the runner is told to stop (mac order):
        // registering it at the first instant of the stop is what lets
        // WaitForStopsToFinish in every other caller see it — registered
        // late, a deploy could honestly find nothing to wait for and start
        // a build the sweep then kills.
        bool hadPreview = _previewRunner.IsRunning || _isWaitingForServer || _previewUrl is not null;
        _serverWait?.Cancel();
        if (hadPreview && _window.Workspace.WorkspacePath is { } workspacePath)
            PreviewStopper.StopSectionProcesses(workspacePath, _course.Code, _sectionNumber);
        if (_previewRunner.IsRunning) _previewRunner.StopByUser();
        _previewUrl = null;
        _lastLoadedUrl = null;
        _isWaitingForServer = false;
        ReleaseLease();
        RefreshChrome();
    }

    public async Task StopPreviewAsync()
    {
        bool hadPreview = _previewRunner.IsRunning || _isWaitingForServer || _previewUrl is not null;
        _serverWait?.Cancel();
        // Sweep first, registered synchronously, THEN stop the host runner
        // (mac order — see StopPreview). A second sweep after the runner
        // dies catches whatever the first missed while the server was still
        // spawning, and the awaited wait covers both.
        if (hadPreview && _window.Workspace.WorkspacePath is { } workspacePath)
            PreviewStopper.StopSectionProcesses(workspacePath, _course.Code, _sectionNumber);
        if (_previewRunner.IsRunning)
        {
            _previewRunner.StopByUser();
            // Bounded, and force-finished past the deadline: the process was
            // just told to die, so hanging here is the only failure left.
            await _previewRunner.WaitUntilFinishedOrKill(5000);
        }
        if (hadPreview && _window.Workspace.WorkspacePath is { } workspacePathAgain)
        {
            await PreviewStopper.StopSectionProcessesAsync(workspacePathAgain, _course.Code, _sectionNumber);
        }
        _previewUrl = null;
        _lastLoadedUrl = null;
        _isWaitingForServer = false;
        ReleaseLease();
        RefreshChrome();
    }

    /// <summary>
    /// Give up the build claim. Safe to call twice, and called on every path
    /// that stops waiting — a claim left behind would lock the assistant out
    /// of building for as long as Plantoir stayed open.
    /// </summary>
    private void ReleaseBuildClaim()
    {
        _buildWork?.Dispose();
        _buildWork = null;
    }

    private void ReleaseLease()
    {
        ReleaseBuildClaim();
        _previewWork?.Dispose();
        _previewWork = null;
        if (_lease is { } lease) PreviewLeases.Release(lease);
        if (_window.Workspace.WorkspacePath is { } wp)
        {
            PreviewLeases.Release(wp, _course.Code, _sectionNumber);
        }
        _lease = null;
    }

    // ---- Deploy ----------------------------------------------------------

    private async void Deploy_Click(object sender, RoutedEventArgs e) => await DeployAsync();

    /// <summary>
    /// The whole Deploy flow, returning the sentence that describes what
    /// actually happened. Every CALL gets its own return value — nothing is
    /// shared across concurrent invocations — so <see cref="Deploy_Click"/>
    /// (fire-and-forget, for the button and for the assistant's mere
    /// "bring it forward" nudge) and
    /// <see cref="StartDeployForAutomationAsync"/> (awaited for the real
    /// outcome) can safely both be in flight at once without one starving
    /// or stealing the other's answer.
    /// </summary>
    private async Task<string?> DeployAsync()
    {
        // Overwritten only on the path that actually calls RunAsync and
        // gets a real outcome back — every early return and the catch block
        // below leave this as "did not finish", which is true of all of
        // them: refused, already deploying, the assistant is building, or
        // an exception before the deploy started.
        string? outcomeMessage = AssistWording.DeployDidNotFinish(_course.Code, _sectionNumber.ToString());
        try
        {
            // _isPreparingDeploy closes a real window, not just a display
            // one: _deployRunner.IsRunning alone stays false through this
            // whole prep phase (stopping any preview, waiting for the stop
            // sweep) — a second click there would race its own
            // stop-preview-then-deploy sequence against the first's
            // (row 318a).
            if (_deployRunner.IsRunning || _isPreparingDeploy) return outcomeMessage;
            if (await TheAssistantIsBuilding()) return outcomeMessage;
            if (_window.Workspace.WorkspacePath is not { } workspacePath) return outcomeMessage;

            var destinations = _course.Configuration.AllDeployDestinations;
            string cloudflareAccount = _window.Workspace.Settings.CloudflareAccountId.Trim();

            // Refuses up front, against EVERY configured destination, rather
            // than discovering a missing credential halfway through a
            // redundancy run — exactly the surprise redundancy exists to
            // prevent (row 305's RefusalReason).
            if (MultiDestinationDeployRunner.RefusalReason(destinations, cloudflareAccount) is { } problem)
            {
                var problemDialog = new ContentDialog
                {
                    Title = "This section can't be deployed yet",
                    Content = problem,
                    CloseButtonText = "OK",
                };
                await ShowDialogSafelyAsync(problemDialog);
                return outcomeMessage;
            }

            // Claim the console for the deploy panel BEFORE touching the
            // preview runner below. Stopping a running preview sets its own
            // WasStoppedByUser and flips IsRunning false without touching
            // _deployRunner.StartedAt — until ClaimConsole() gives it a real
            // timestamp, RefreshChrome's showDeploy comparison kept picking
            // the just-stopped preview panel, flashing "Stopped" for a beat
            // before the deploy panel took over (row 317). _isPreparingDeploy
            // covers what the timestamp alone does not: _deployRunner.Legs
            // still holds the PREVIOUS deploy's runners until RunAsync
            // replaces them with fresh ones a little further down.
            _deployRunner.ClaimConsole();
            _isPreparingDeploy = true;
            RefreshChrome();

            // Stop any running or building preview before deploying, and
            // wait for the container-side stop sweep to finish so it cannot
            // kill or race the deploy build (the sweep kills by WORKING
            // DIRECTORY, the same one the quiet build works in). Mac parity:
            // deployAndWait() in SectionDetailView.swift does exactly this.
            if (_previewRunner.IsRunning)
                await StopPreviewAsync();
            else
                await PreviewStopper.WaitForStopsToFinish(_course.Code, _sectionNumber);

            // Said AFTER the stop, as on the mac: a deploy that began while
            // we were waiting is the one thing that still stands in the way.
            if (_deployRunner.IsRunning) return outcomeMessage;
            // The stop can take up to ~20 s, and the leases came off with the
            // preview — long enough for the assistant to begin a build of its
            // own. The click-time answer is stale; ask again.
            if (await TheAssistantIsBuilding()) return outcomeMessage;

            // Where THIS working folder's built websites are kept. The app
            // has to be able to name that path to answer the question at all;
            // until 2026-09-06 nothing in the app could, so this asked about
            // <course>\.merged_output, which Windows stopped writing to when
            // builds moved out of the working folder.
            bool needsBuild = BuildFreshness.NeedsRebuild(
                _course, _sectionNumber, BuildOutputLocation.BuildsRootFor(workspacePath));

            // The publish is on the books for its WHOLE life — the quiet build
            // included — and comes off them on every exit path: the normal
            // end and the catch.
            _publishActivity?.Dispose();
            _publishActivity = CourseActivity.BeginPublish(workspacePath, _course.Code, _sectionNumber);
            _publishWork = WorkLease.Take(workspacePath, _course.Code, WorkLease.Publishing);
            // A deploy builds and then uploads, and both end together, so the
            // build claim can simply run its whole length.
            _buildWork = WorkLease.Take(workspacePath, _course.Code, WorkLease.Building);

            // The real progress panel takes over from here — RunAsync is
            // about to give _deployRunner.Legs fresh runners of its own and
            // start reporting real progress on them. No RefreshChrome() call
            // belongs between this line and RunAsync: _deployRunner.Legs
            // still holds the PREVIOUS deploy's (finished, stale-outcome)
            // runners until RunAsync's own synchronous prefix replaces them,
            // so a refresh sandwiched here would repaint that stale outcome
            // for exactly the beat this whole fix exists to close — RunAsync
            // sets IsRunning and notifies synchronously, before its first
            // await, and that notification is what calls RefreshChrome (see
            // the constructor's _deployRunner.PropertyChanged subscription).
            _isPreparingDeploy = false;

            // This build asks the folder question again, and its answer is the
            // one carrying the sentence about what students can see — so a
            // finding a preview already reported must not be suppressed here
            // as "already shown".
            _healthQueue.ForgetShown();

            // The whole sequence — an optional shared build, then each
            // destination's own deploy — happens inside RunAsync, which
            // also resolves each leg's own milestones and custom domain.
            // For the overwhelming majority of courses (one destination)
            // this behaves exactly as a single deploy always did.
            await _deployRunner.RunAsync(_course, _sectionNumber, destinations, cloudflareAccount,
                workspacePath, needsBuild);
            // The single place that decides which sentence a teacher (or the
            // assistant, relaying it) hears — success, all-destinations,
            // partial, or every-destination-failed — from what actually
            // happened, not from having reached this line.
            outcomeMessage = MultiDestinationDeployRunner.Result(
                _course.Code, _sectionNumber.ToString(), destinations.Count, _deployRunner.CurrentOutcome).Message;
            EndPublishActivity();

            // What the build said about this course's folders, taken from the
            // FIRST leg: every destination publishes the same built site, so a
            // second leg only repeats the findings. A deploy that skipped the
            // build (nothing had changed) reports none, which is correct — the
            // checks run inside the build.
            //
            // AFTER EndPublishActivity, deliberately: the publish is off the
            // books by now, so "Preview Again" is not refused on account of
            // this view's own publish having just finished. And NOT awaited —
            // the assistant awaits DeployAsync for its answer, and it must not
            // wait on a teacher reading a dialog.
            NoteHealthFindings(_deployRunner.Legs.FirstOrDefault()?.Runner, cameFromPublishing: true);
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"Deploy_Click exception: {ex}");
            // An exception between BeginPublish and the normal end would
            // otherwise leave the course registered as publishing — holding
            // the publish and build claims — until the view is torn down.
            EndPublishActivity();
        }
        finally
        {
            // A safety net for every early-return path above (the refusal
            // dialog, "already deploying", "the assistant is building",
            // an exception before the flag was cleared): _isPreparingDeploy
            // must never survive past this method, or the Deploy button and
            // the console stay stuck showing "Preparing to deploy…" forever.
            if (_isPreparingDeploy)
            {
                _isPreparingDeploy = false;
                RefreshChrome();
            }
        }
        return outcomeMessage;
    }

    private void EndPublishActivity()
    {
        _publishActivity?.Dispose();
        _publishActivity = null;
        _publishWork?.Dispose();
        _publishWork = null;
        ReleaseBuildClaim();
    }

    // ---- Browser chrome --------------------------------------------------

    private void Back_Click(object sender, RoutedEventArgs e) { if (Preview.CanGoBack) Preview.GoBack(); }
    private void Forward_Click(object sender, RoutedEventArgs e) { if (Preview.CanGoForward) Preview.GoForward(); }
    private void Reload_Click(object sender, RoutedEventArgs e) => Preview.Reload();

    private void ReloadAccelerator(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender,
        Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args)
    { if (_previewUrl is not null) { Preview.Reload(); args.Handled = true; } }

    private void BackAccelerator(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender,
        Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args)
    { if (Preview.CanGoBack) { Preview.GoBack(); args.Handled = true; } }

    private void ForwardAccelerator(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender,
        Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args)
    { if (Preview.CanGoForward) { Preview.GoForward(); args.Handled = true; } }

    private void OpenInBrowser_Click(object sender, RoutedEventArgs e)
    {
        // The page currently shown, not the site root; localhost is rewritten
        // to 127.0.0.1 (browsers try IPv6 first; the container is IPv4 only).
        Uri? current = Preview.Source ?? _previewUrl;
        if (current is null) return;
        var builder = new UriBuilder(current);
        if (builder.Host == "localhost") builder.Host = "127.0.0.1";
        try
        {
            Process.Start(new ProcessStartInfo(builder.Uri.AbsoluteUri) { UseShellExecute = true });
        }
        catch { }
    }

    private void Obsidian_Click(object sender, RoutedEventArgs e) =>
        _ = FolderActions.OpenInObsidian(_course.SectionDirectory(_sectionNumber), _course.DirectoryPath,
            BundledToolchain.SupportPath("obsidian_defaults/.obsidian"));

    public void StagePreviewForCapture(ElementTheme theme, string? siteImagePath = null)
    {
        _previewUrl = new Uri("http://localhost:8081");
        PreviewLabel.Text = "Stop Preview";
        PreviewIcon.Glyph = Glyphs.Stop;
        BackButton.IsEnabled = true;
        ReloadButton.IsEnabled = true;
        BrowserButton.IsEnabled = true;
        DeployButton.IsEnabled = true;

        NoPreviewState.Visibility = Visibility.Collapsed;
        Progress.Visibility = Visibility.Collapsed;

        if (!string.IsNullOrEmpty(siteImagePath) && File.Exists(siteImagePath))
        {
            try
            {
                var bitmap = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(Path.GetFullPath(siteImagePath)));
                var img = new Image
                {
                    Source = bitmap,
                    Stretch = Stretch.UniformToFill,
                    HorizontalAlignment = HorizontalAlignment.Left,
                    VerticalAlignment = VerticalAlignment.Top
                };
                BaseLayer.Children.Clear();
                BaseLayer.Children.Add(img);
                return;
            }
            catch { }
        }

        var isDark = theme == ElementTheme.Dark;
        var siteBg = isDark
            ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 22, 22, 24))     // #161618 Quartz dark
            : new SolidColorBrush(Windows.UI.Color.FromArgb(255, 250, 248, 245)); // #FAF8F5 Quartz light
        var textPrimary = isDark
            ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 236, 239, 244))
            : new SolidColorBrush(Windows.UI.Color.FromArgb(255, 43, 43, 43));
        var textSecondary = isDark
            ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 160, 170, 185))
            : new SolidColorBrush(Windows.UI.Color.FromArgb(255, 110, 110, 110));
        var accentColor = isDark
            ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 136, 192, 208))
            : new SolidColorBrush(Windows.UI.Color.FromArgb(255, 40, 75, 99));
        var cardBg = isDark
            ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 30, 30, 34))
            : new SolidColorBrush(Windows.UI.Color.FromArgb(255, 240, 236, 230));

        var siteRoot = new Grid { Background = siteBg };
        siteRoot.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(240) });
        siteRoot.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var navBar = new StackPanel { Padding = new Thickness(24, 28, 16, 20), Spacing = 14 };
        var siteHeader = new TextBlock
        {
            Text = "ENG2D: Grade 10 English",
            FontSize = 15,
            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
            Foreground = textPrimary
        };
        var searchBox = new Border
        {
            Background = cardBg,
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(10, 6, 10, 6),
            Child = new TextBlock { Text = "Search (Ctrl+K)", FontSize = 12, Foreground = textSecondary }
        };
        var treeHeader = new TextBlock
        {
            Text = "EXPLORER",
            FontSize = 11,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = textSecondary,
            Margin = new Thickness(0, 10, 0, 0)
        };
        var unit1 = new TextBlock
        {
            Text = "▼ Unit 1: The Short Story",
            FontSize = 13,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = textPrimary
        };
        var day1 = new TextBlock
        {
            Text = "• Day 1: Course Intro",
            FontSize = 13,
            Foreground = accentColor,
            Margin = new Thickness(14, 2, 0, 0)
        };
        var day2 = new TextBlock
        {
            Text = "• Day 2: Narrative Arc",
            FontSize = 13,
            Foreground = textSecondary,
            Margin = new Thickness(14, 2, 0, 0)
        };
        var unit2 = new TextBlock
        {
            Text = "▶ Unit 2: The Novel Study",
            FontSize = 13,
            Foreground = textSecondary,
            Margin = new Thickness(0, 6, 0, 0)
        };

        navBar.Children.Add(siteHeader);
        navBar.Children.Add(searchBox);
        navBar.Children.Add(treeHeader);
        navBar.Children.Add(unit1);
        navBar.Children.Add(day1);
        navBar.Children.Add(day2);
        navBar.Children.Add(unit2);

        var navBorder = new Border
        {
            Child = navBar,
            BorderBrush = new SolidColorBrush(isDark ? Windows.UI.Color.FromArgb(40, 255, 255, 255) : Windows.UI.Color.FromArgb(25, 0, 0, 0)),
            BorderThickness = new Thickness(0, 0, 1, 0)
        };
        Grid.SetColumn(navBorder, 0);
        siteRoot.Children.Add(navBorder);

        var mainContent = new ScrollViewer { Padding = new Thickness(36, 28, 48, 28) };
        var article = new StackPanel { Spacing = 14, MaxWidth = 680, HorizontalAlignment = HorizontalAlignment.Left };

        var title = new TextBlock
        {
            Text = "Unit 1, Day 1: Course Introduction & Syllabus",
            FontSize = 24,
            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
            Foreground = textPrimary
        };
        var dateTag = new TextBlock
        {
            Text = "September 8, 2026",
            FontSize = 12,
            Foreground = textSecondary,
            Margin = new Thickness(0, -6, 0, 8)
        };
        var intro = new TextBlock
        {
            Text = "Welcome to Grade 10 Academic English. In this course, we will explore short fiction, dramatic literature, and analytical writing. All class notes, daily agendas, and assignment guidelines will be published here daily.",
            FontSize = 14,
            TextWrapping = TextWrapping.Wrap,
            LineHeight = 22,
            Foreground = textPrimary
        };
        var callout = new Border
        {
            Background = cardBg,
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(16, 12, 16, 12),
            Margin = new Thickness(0, 8, 0, 8),
            BorderBrush = accentColor,
            BorderThickness = new Thickness(3, 0, 0, 0)
        };
        var calloutStack = new StackPanel { Spacing = 4 };
        calloutStack.Children.Add(new TextBlock { Text = "Key Dates & Materials", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = textPrimary });
        calloutStack.Children.Add(new TextBlock { Text = "• Bring course notebook and writer's journal each day\n• Diagnostic writing sample: Friday, Sept 11", FontSize = 13, Foreground = textSecondary });
        callout.Child = calloutStack;

        article.Children.Add(title);
        article.Children.Add(dateTag);
        article.Children.Add(intro);
        article.Children.Add(callout);
        mainContent.Content = article;

        Grid.SetColumn(mainContent, 1);
        siteRoot.Children.Add(mainContent);

        BaseLayer.Children.Clear();
        BaseLayer.Children.Add(siteRoot);
    }
}
