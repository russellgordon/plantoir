using System;
using System.Diagnostics;
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
    private readonly ScriptRunner _deployRunner = new(SynchronizationContext.Current);
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

    internal bool IsBusy => _previewRunner.IsRunning || _deployRunner.IsRunning;
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
            ? "Click Preview to build this section's website and see it here, or Deploy to copy it to your publishing folder."
            : "Click Preview to build this section's website and see it here, or Deploy to put it online.";

        // Each runner is bound to the progress view exactly once — its
        // question dialog and outcome states follow whichever runner the
        // view is currently showing, chosen in RefreshChrome via Show().
        Progress.Register(_previewRunner);
        Progress.Register(_deployRunner);
        _previewRunner.PropertyChanged += (_, _) => RefreshChrome();
        _deployRunner.PropertyChanged += (_, _) => RefreshChrome();
        Preview.NavigationCompleted += (_, _) => RefreshChrome();
        Unloaded += (_, _) => StopPreview();
        RefreshChrome();
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
        DeployButton.IsEnabled = !IsBusy && !building;
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
            (_deployRunner.IsRunning ||
             (_deployRunner.StartedAt ?? DateTime.MinValue) > (_previewRunner.StartedAt ?? DateTime.MinValue));
        if (showDeploy)
            Progress.Show(_deployRunner, $"Deploying {TitleText}");
        else
            Progress.Show(_previewRunner,
                _previewRunner.IsRunning || _isWaitingForServer
                    ? $"Preparing the preview of {TitleText}"
                    : $"Preview of {TitleText}");

        bool anyOutput = _previewRunner.Transcript.Lines.Count > 0 || _deployRunner.Transcript.Lines.Count > 0
                         || _previewRunner.Transcript.CurrentLine.Length > 0;
        bool showConsole = _isWaitingForServer || IsBusy || anyOutput;
        Progress.Visibility = showConsole ? Visibility.Visible : Visibility.Collapsed;
        NoPreviewState.Visibility = showConsole ? Visibility.Collapsed : Visibility.Visible;
        Preview.Visibility = previewShown ? Visibility.Visible : Visibility.Collapsed;
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

    // ---- Preview ---------------------------------------------------------

    /// <summary>Smoke-test entry: the same path the Preview button takes.</summary>
    public void StartPreviewForAutomation() => PreviewOrStop_Click(this, new RoutedEventArgs());

    /// <summary>
    /// Start this section's preview unless one is already serving — the
    /// assistant's "come and look" path. Guarded, because the click handler
    /// is a toggle: calling it blind against a running preview would STOP the
    /// very thing the teacher was being shown.
    /// </summary>
    public void StartPreviewIfIdle()
    {
        try
        {
            if (_previewRunner.IsRunning) return;
            PreviewOrStop_Click(this, new RoutedEventArgs());
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"StartPreviewIfIdle exception: {ex}");
        }
    }

    /// <summary>Stop the preview if one is up — the assistant's half of stop, edit, start again.</summary>
    public void StopPreviewIfRunning()
    {
        if (_previewRunner.IsRunning || _lease is not null) StopPreview();
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

    private void StopPreview()
    {
        // Whenever a preview was actually running (or still building),
        // reclaim its container-side processes too — ending the host
        // launcher alone leaves the serve chain alive inside the container.
        bool hadPreview = _previewRunner.IsRunning || _isWaitingForServer || _previewUrl is not null;
        _serverWait?.Cancel();
        if (_previewRunner.IsRunning) _previewRunner.StopByUser();
        if (hadPreview && _window.Workspace.WorkspacePath is { } workspacePath)
            PreviewStopper.StopSectionProcesses(workspacePath, _course.Code, _sectionNumber);
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
        if (_previewRunner.IsRunning)
        {
            _previewRunner.StopByUser();
            await _previewRunner.WaitUntilFinished();
        }
        if (hadPreview && _window.Workspace.WorkspacePath is { } workspacePath)
        {
            await PreviewStopper.StopSectionProcessesAsync(workspacePath, _course.Code, _sectionNumber);
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
        _lease = null;
    }

    // ---- Deploy ----------------------------------------------------------

    private async void Deploy_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (IsBusy) return;
            if (await TheAssistantIsBuilding()) return;
            if (_window.Workspace.WorkspacePath is not { } workspacePath) return;

            // Folder publishing (rows 101–102): the save gate keeps the folder
            // valid, but a hand-edited config could still slip a bad one in —
            // decline plainly rather than let the launcher discover it.
            bool toFolder = _course.Configuration.DeploysToLocalFolder;
            string deployFolder = _course.Configuration.DeployFolderPath.Trim();
            if (toFolder && CourseConfiguration.DeployFolderProblem(deployFolder) is { } folderProblem)
            {
                var problemDialog = new ContentDialog
                {
                    Title = "The deploy folder needs attention",
                    Content = folderProblem + " Fix it in this course's settings, then deploy again.",
                    CloseButtonText = "OK",
                };
                await ShowDialogSafelyAsync(problemDialog);
                return;
            }

            // Cloudflare needs the teacher's account, and the launcher's console
            // prompt for it can never be answered from here — so decline plainly
            // and point at the setting that fixes it.
            bool toCloudflare = _course.Configuration.DeploysToCloudflare;
            string cloudflareAccount = _window.Workspace.Settings.CloudflareAccountId.Trim();
            if (toCloudflare && CourseConfiguration.CloudflareAccountProblem(cloudflareAccount) is { } accountProblem)
            {
                var accountDialog = new ContentDialog
                {
                    Title = "Cloudflare needs your Account ID",
                    Content = accountProblem + " Add it in this course's settings, under Deploying, then deploy again.",
                    CloseButtonText = "OK",
                };
                await ShowDialogSafelyAsync(accountDialog);
                return;
            }

            bool needsBuild = BuildFreshness.NeedsRebuild(_course, _sectionNumber);
            _deployRunner.Milestones = toFolder
                ? (needsBuild ? TaskMilestones.BuildAndDeployToFolder : TaskMilestones.DeployToFolder)
                : toCloudflare
                    ? (needsBuild ? TaskMilestones.BuildAndDeployToCloudflare : TaskMilestones.DeployToCloudflare)
                    : (needsBuild ? TaskMilestones.BuildAndDeploy : TaskMilestones.Deploy);
            string customDomain = CourseConfiguration.NormalizedCustomDomain(
                _course.Configuration.CustomDomain(_sectionNumber));
            _deployRunner.CustomDomainForLinks = customDomain.Length == 0 ? null : customDomain;

            // The publish is on the books for its WHOLE life — the quiet build
            // included — and comes off them on every exit path (EndPublish runs
            // from the runner-stopped transition in RefreshChrome).
            _publishActivity?.Dispose();
            _publishActivity = CourseActivity.BeginPublish(workspacePath, _course.Code, _sectionNumber);
            _publishWork = WorkLease.Take(workspacePath, _course.Code, WorkLease.Publishing);
            // A deploy builds and then uploads, and both end together, so the
            // build claim can simply run its whole length.
            _buildWork = WorkLease.Take(workspacePath, _course.Code, WorkLease.Building);

            if (needsBuild)
            {
                // Build quietly first; a failed build stops before publishing —
                // the failure and its output are already on screen.
                _deployRunner.Run("preview.ps1",
                    new[] { _course.Code, _sectionNumber.ToString(), "--build-only" }, workspacePath);
                RefreshChrome();
                if (!await _deployRunner.WaitUntilFinished()) { EndPublishActivity(); return; }
            }
            var deployArguments = toFolder
                ? new[] { _course.Code, _sectionNumber.ToString(), "--to-folder", deployFolder }
                : toCloudflare
                    ? new[] { _course.Code, _sectionNumber.ToString(), "--target", "cloudflare", "--account", cloudflareAccount }
                    : new[] { _course.Code, _sectionNumber.ToString() };
            _deployRunner.Run("deploy.ps1", deployArguments, workspacePath,
                keepTranscript: needsBuild);
            RefreshChrome();
            await _deployRunner.WaitUntilFinished();   // outcome already on screen
            EndPublishActivity();
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"Deploy_Click exception: {ex}");
        }
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
