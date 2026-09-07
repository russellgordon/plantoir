using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Services;
using Plantoir.ViewModels;
using Plantoir.Views;
using Windows.Graphics;

namespace Plantoir;

public sealed partial class MainWindow : Window
{
    public WorkspaceViewModel Workspace { get; }

    /// <summary>The sidebar pane, reachable from sibling views.</summary>
    public Views.SidebarPane SidebarPane => Sidebar;

    /// <summary>Detail area presenter.</summary>
    public ContentPresenter DetailPresenter => DetailHost;

    public MainWindow(string? folderPath, RememberedWindow? frame)
    {
        App.LogDiagnostic("MainWindow ctor: starting InitializeComponent");
        InitializeComponent();
        App.LogDiagnostic("MainWindow ctor: InitializeComponent done");
        try { SystemBackdrop = new Microsoft.UI.Xaml.Media.MicaBackdrop(); } catch { }
        App.LogDiagnostic("MainWindow ctor: creating WorkspaceViewModel");
        Workspace = new WorkspaceViewModel(App.Settings);
        App.LogDiagnostic("MainWindow ctor: WorkspaceViewModel created");

        // A remembered window restores exactly; a first run opens at a share of
        // the display's work area, not a fixed pixel count. AppWindow sizes are
        // raw pixels, so a fixed 1100Ã—720 looks postage-stamp small on a 200%
        // display â€” a proportion of the work area is right at any scale. Clamped
        // so it never dwarfs a small screen or sprawls across a huge one.
        var workArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        int defaultWidth = Math.Clamp((int)(workArea.Width * 0.62), 1000, 2000);
        int defaultHeight = Math.Clamp((int)(workArea.Height * 0.72), 680, 1400);
        int width = frame is { Width: > 200 } ? (int)frame.Width : defaultWidth;
        int height = frame is { Height: > 200 } ? (int)frame.Height : defaultHeight;
        AppWindow.Resize(new SizeInt32(width, height));
        if (frame is { } f && f.X > -10000 && f.Y > -10000)
            AppWindow.Move(new PointInt32((int)f.X, (int)f.Y));
        else   // First run: sit centred on the work area rather than at (0,0).
            AppWindow.Move(new PointInt32(
                workArea.X + (workArea.Width - width) / 2,
                workArea.Y + (workArea.Height - height) / 2));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
            presenter.PreferredMinimumWidth = 900;
        if (AppWindow.Presenter is OverlappedPresenter minPresenter)
            minPresenter.PreferredMinimumHeight = 600;

        // Title-bar and Alt-Tab icon. The exe's ApplicationIcon covers
        // Explorer and pinned taskbar buttons; a live window wants its own.
        try { AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Plantoir.ico")); }
        catch { /* a missing icon must never stop the window */ }

        Picker.Attach(this);
        Sidebar.Attach(this);

        Activated += (_, args) =>
        {
            if (args.WindowActivationState != WindowActivationState.Deactivated)
            {
                Workspace.NoteBecameKey();
                // Subscribed before any SectionDetailView exists, so this runs
                // before that view's own OnWindowActivated on the SAME
                // activation â€” a scheduled deploy that finished overnight is
                // reflected in the " â€” Edited" marker the first time the
                // teacher looks, not one activation later. See
                // ScheduledDeployCompletion and WINDOWS-HANDOFF.md, "A
                // scheduled deploy needs its own path to the same record".
                _ = System.Threading.Tasks.Task.Run(ScheduledDeployCompletion.ConsumePending);
                // The sidebar's own clock badge (SidebarRow.ScheduledDeploy)
                // is read from schtasks, not stored anywhere of ours â€” a
                // deploy scheduled through the assistant, or in another
                // window on the same section, would otherwise sit invisible
                // here until something else happened to reload the tree.
                if (Workspace.State == WorkspaceState.Ready) Sidebar.Refresh();
            }
        };
        // Covers app launch itself, in case the window's first Activated
        // fires before this runs (or does not fire at all on some launch
        // paths) â€” cheap and idempotent when there is nothing pending.
        _ = System.Threading.Tasks.Task.Run(ScheduledDeployCompletion.ConsumePending);
        Closed += (_, _) => { IsClosed = true; Workspace.UnregisterWindow(); };

        // The Preview menu tracks whichever section is currently shown â€”
        // one callback registered once, rather than a refresh call threaded
        // through every place DetailHost.Content is assigned.
        DetailHost.RegisterPropertyChangedCallback(ContentPresenter.ContentProperty, (_, _) => TrackDetailForPreviewMenu());
        RefreshPreviewMenu();

        Workspace.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName is nameof(WorkspaceViewModel.State)
                or nameof(WorkspaceViewModel.WorkspacePath)
                or nameof(WorkspaceViewModel.WorkspaceProblem)) ApplyState();
            if (args.PropertyName is nameof(WorkspaceViewModel.Selection)
                or nameof(WorkspaceViewModel.Courses)) ShowDetailForSelection();
            // The selection is part of the window's memory (row 99).
            if (args.PropertyName is nameof(WorkspaceViewModel.Selection)) App.RememberOpenWindows();
        };

        // Decide the folder BEFORE first paint so the picker never flashes.
        // The sidebar memory seeds first, so the very first Refresh builds
        // the tree the way this window left it (row 99).
        Workspace.ExpandedCourseCodes = WindowMemoryCodec.ParseExpandedCourses(frame?.ExpandedCourses);
        Workspace.IsShowingArchived = frame?.ShowsArchived ?? false;
        Workspace.IsShowingBackups = frame?.ShowsBackups ?? false;
        if (folderPath is not null && Directory.Exists(folderPath))
        {
            App.LogDiagnostic($"MainWindow ctor: AdoptRestoredPath('{folderPath}') starting");
            Workspace.AdoptRestoredPath(folderPath);
            App.LogDiagnostic("MainWindow ctor: AdoptRestoredPath done");
            ShowSyncNoticeIfNeeded();
        }
        App.LogDiagnostic("MainWindow ctor: ApplyState starting");
        ApplyState();
        App.LogDiagnostic("MainWindow ctor: ApplyState done; RestoreRememberedSelection starting");
        RestoreRememberedSelection(frame?.Selection);
        App.LogDiagnostic("MainWindow ctor: RestoreRememberedSelection done; RunAutomationHooks starting");
        RunAutomationHooks();
        App.LogDiagnostic("MainWindow ctor: complete");
    }


    /// <summary>
    /// Test hooks: "--auto-select CODE N" selects a section on launch;
    /// "--auto-preview" additionally presses Preview â€” the same code path
    /// as the button, so smoke tests exercise the real flow.
    /// </summary>
    private void RunAutomationHooks()
    {
        string[] args = Environment.GetCommandLineArgs();

        // --auto-course CODE : open a course's settings.  --auto-wizard : the
        // New Course dialog.  --auto-addsection CODE : the Add Section dialog.
        int courseIndex = Array.IndexOf(args, "--auto-course");
        if (courseIndex >= 0 && courseIndex + 1 < args.Length)
        {
            string courseCode = args[courseIndex + 1];
            DispatcherQueue.TryEnqueue(async () =>
            {
                await System.Threading.Tasks.Task.Delay(1500);
                Workspace.Selection = new SidebarSelection.CourseItem(courseCode);
            });
            return;
        }
        if (args.Contains("--auto-wizard"))
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                await System.Threading.Tasks.Task.Delay(1500);
                await Sidebar.OpenNewCourseWizard();
            });
            return;
        }
        int createIndex = Array.IndexOf(args, "--auto-createcourse");
        if (createIndex >= 0 && createIndex + 1 < args.Length)
        {
            string createCode = args[createIndex + 1];
            string? createSections = createIndex + 2 < args.Length && !args[createIndex + 2].StartsWith("--")
                ? args[createIndex + 2] : null;
            DispatcherQueue.TryEnqueue(async () =>
            {
                await System.Threading.Tasks.Task.Delay(1500);
                await Sidebar.OpenNewCourseWizard(createCode, createSections);
            });
            return;
        }
        int addIndex = Array.IndexOf(args, "--auto-addsection");
        if (addIndex >= 0 && addIndex + 1 < args.Length)
        {
            string addCode = args[addIndex + 1];
            DispatcherQueue.TryEnqueue(async () =>
            {
                await System.Threading.Tasks.Task.Delay(1500);
                if (Workspace.Courses.FirstOrDefault(c => c.Code == addCode) is { } course)
                    await Sidebar.OpenAddSectionDialog(course);
            });
            return;
        }

        int index = Array.IndexOf(args, "--auto-select");
        if (index < 0) index = Array.IndexOf(args, "--auto-preview");
        if (index < 0) index = Array.IndexOf(args, "--auto-deploy");
        if (index < 0 || index + 2 >= args.Length) return;
        string code = args[index + 1];
        if (!int.TryParse(args[index + 2], out int section)) return;
        bool preview = args.Contains("--auto-preview");
        bool deploy = args.Contains("--auto-deploy");
        DispatcherQueue.TryEnqueue(async () =>
        {
            await System.Threading.Tasks.Task.Delay(1500);
            Workspace.Selection = new SidebarSelection.SectionItem(code, section);
            if (DetailHost.Content is not SectionDetailView detail) return;
            if (preview) detail.StartPreviewForAutomation();
            else if (deploy) detail.StartDeployForAutomation();
            if (args.Contains("--details"))
            {
                await System.Threading.Tasks.Task.Delay(3000);
                detail.ShowDetailsForAutomation();
            }
        });
    }

    /// <summary>True once this window has closed; a closed window cannot show anything.</summary>
    public bool IsClosed { get; private set; }

    /// <summary>
    /// Bring this window onto the screen ONLY if it is not already there â€”
    /// minimised, or hidden. A window the teacher can already see is left
    /// exactly as it is, and in particular is NOT activated: the assistant is
    /// a separate window they may still be typing in, and stealing keyboard
    /// focus mid-sentence to show them a build that was already in view is a
    /// worse trade than the mac's unconditional bring-to-front (row 300).
    ///
    /// <para>"Not already there" is decided by two cheap, honest tests â€”
    /// <c>OverlappedPresenter.State == Minimized</c>, and
    /// <c>AppWindow.IsVisible</c> being false. A window fully covered by
    /// another window is NOT detected: there is no cheap answer to occlusion
    /// on WinUI, and guessing wrong would steal focus. Recorded in
    /// MAC-HANDOFF.md as a chosen divergence rather than an oversight.</para>
    /// </summary>
    private void ComeForwardIfHidden()
    {
        bool minimised = AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized };
        if (!minimised && AppWindow.IsVisible) return;
        if (minimised && AppWindow.Presenter is OverlappedPresenter presenter) presenter.Restore();
        if (!AppWindow.IsVisible) AppWindow.Show();
        Activate();
    }

    /// <summary>
    /// Bring a section's preview onto the screen, for the assistant.
    ///
    /// The assistant's tools build the section's site, and a build nobody can
    /// see might as well not have happened â€” a teacher approved a rebuild,
    /// watched it finish, and had nothing to look at. So after a tool that
    /// leaves a fresh build behind, the assistant's window asks this one to
    /// select the section and start its preview. If a preview is already
    /// serving, starting is skipped â€” live reload is showing the change. The
    /// window comes forward only when it is minimised or hidden
    /// (<see cref="ComeForwardIfHidden"/>); one the teacher can already see is
    /// not activated, so the assistant window keeps keyboard focus. Until
    /// 2026-09-07 nothing here activated at all, and this comment described
    /// a behaviour that had never been built. May be called from any thread.
    /// </summary>
    public void ShowPreviewFor(string courseCode, int section)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            try
            {
                if (DetailHost.Content is not SectionDetailView existing ||
                    !string.Equals(existing.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase) ||
                    existing.SectionNumber != section)
                {
                    Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
                }
                if (DetailHost.Content is SectionDetailView detail) detail.StartPreviewIfIdle();
                ComeForwardIfHidden();
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"ShowPreviewFor exception: {ex}");
            }
        });
    }

    /// <summary>
    /// Deploy a section through this window's own flow â€” console, milestones,
    /// needs-rebuild decision and all â€” for the assistant. The assistant
    /// automates Plantoir; it does not deploy behind its back.
    /// </summary>
    public void DeployFor(string courseCode, int section)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            try
            {
                if (DetailHost.Content is not SectionDetailView existing ||
                    !string.Equals(existing.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase) ||
                    existing.SectionNumber != section)
                {
                    Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
                }
                if (DetailHost.Content is SectionDetailView detail) detail.StartDeployForAutomation();
                ComeForwardIfHidden();
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"DeployFor exception: {ex}");
            }
        });
    }

    /// <summary>
    /// Deploy through the section's own flow and AWAIT the real outcome â€”
    /// success, failure, or a multi-destination partial â€” rather than only
    /// the moment the click was dispatched. Returns null if no section view
    /// was open to deploy through, or an exception struck before the deploy
    /// even started; callers word that as "did not finish", never as
    /// success.
    /// </summary>
    public async Task<string?> DeployForAsync(string courseCode, int section)
    {
        var tcs = new TaskCompletionSource<string?>();
        DispatcherQueue.TryEnqueue(() => _ = RunOnUIThreadAsync());

        async Task RunOnUIThreadAsync()
        {
            try
            {
                if (DetailHost.Content is not SectionDetailView existing ||
                    !string.Equals(existing.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase) ||
                    existing.SectionNumber != section)
                {
                    Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
                }
                ComeForwardIfHidden();
                if (DetailHost.Content is SectionDetailView detail)
                {
                    string? outcome = await detail.StartDeployForAutomationAsync();
                    tcs.TrySetResult(outcome);
                }
                else
                {
                    tcs.TrySetResult(null);
                }
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"DeployForAsync exception: {ex}");
                tcs.TrySetResult(null);
            }
        }

        return await tcs.Task;
    }

    public bool IsSectionBusy(string courseCode, int section)
    {
        // Busy, to the caller asking before a DEPLOY, means "a deploy is
        // already running" â€” not "a preview is up". The Deploy path stops a
        // running preview itself and waits for it (deploy-during-preview
        // port, mac commit "Allow Deploy button to stop active preview
        // before publishing"), so reporting a preview as busy here made the
        // assistant refuse â€” and say so â€” while the deploy went ahead.
        if (DetailHost.Content is SectionDetailView detail)
        {
            return detail.IsDeploying;
        }
        return false;
    }

    /// <summary>
    /// Stop a section's preview, for the assistant â€” the first half of
    /// stop, edit, start again. No Activate: a stop is not the moment to
    /// pull the teacher away from the conversation.
    /// </summary>
    public void StopPreviewFor(string courseCode, int section)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            try
            {
                if (DetailHost.Content is not SectionDetailView existing ||
                    !string.Equals(existing.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase) ||
                    existing.SectionNumber != section)
                {
                    Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
                }
                if (DetailHost.Content is SectionDetailView detail) detail.StopPreviewIfRunning();
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"StopPreviewFor exception: {ex}");
            }
        });
    }

    public async Task StopPreviewForAsync(string courseCode, int section)
    {
        var tcs = new TaskCompletionSource();
        DispatcherQueue.TryEnqueue(async () =>
        {
            try
            {
                if (DetailHost.Content is not SectionDetailView existing ||
                    !string.Equals(existing.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase) ||
                    existing.SectionNumber != section)
                {
                    Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
                }

                if (DetailHost.Content is SectionDetailView detail)
                {
                    await detail.StopPreviewIfRunningAsync();
                }

                if (Workspace.WorkspacePath is { } wp)
                {
                    await PreviewStopper.StopSectionProcessesAsync(wp, courseCode, section);
                    PreviewLeases.Release(wp, courseCode, section);
                }
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"StopPreviewForAsync exception: {ex}");
            }
            finally
            {
                tcs.TrySetResult();
            }
        });
        await tcs.Task;
    }

    /// <summary>
    /// Restore the remembered selection â€” but only when its target still
    /// exists, so a course removed between sessions never greets the teacher
    /// with "Course Not Found". Unrecognized stored forms restore none.
    /// </summary>
    private void RestoreRememberedSelection(string? stored)
    {
        switch (SidebarSelection.Parse(stored))
        {
            case SidebarSelection.CourseItem(var code)
                when Workspace.Courses.Any(c => c.Code == code):
                Workspace.Selection = new SidebarSelection.CourseItem(code);
                break;
            case SidebarSelection.SectionItem(var code, var number)
                when Workspace.Courses.FirstOrDefault(c => c.Code == code)?.SectionNumbers.Contains(number) == true:
                Workspace.Selection = new SidebarSelection.SectionItem(code, number);
                break;
            case SidebarSelection.ArchivedEntry(var id)
                when Workspace.ArchivedItems.Any(a => a.Id == id):
                Workspace.Selection = new SidebarSelection.ArchivedEntry(id);
                break;
            case SidebarSelection.BackupEntry(var id)
                when Workspace.BackupItems.Any(b => b.Id == id):
                Workspace.Selection = new SidebarSelection.BackupEntry(id);
                break;
        }
    }

    public RememberedWindow? RememberedEntry()
    {
        if (Workspace.WorkspacePath is null) return null;
        var position = AppWindow.Position;
        var size = AppWindow.Size;
        return new RememberedWindow(Workspace.WorkspacePath, position.X, position.Y, size.Width, size.Height,
            WindowMemoryCodec.EncodeExpandedCourses(Workspace.ExpandedCourseCodes),
            Workspace.IsShowingArchived,
            Workspace.Selection?.Serialized,
            Workspace.IsShowingBackups);
    }

    // ---- State switching -------------------------------------------------

    public void ApplyState()
    {
        bool ready = Workspace.State == WorkspaceState.Ready && Workspace.WorkspaceProblem is null;
        Picker.Visibility = ready ? Visibility.Collapsed : Visibility.Visible;
        SplitView.Visibility = ready ? Visibility.Visible : Visibility.Collapsed;
        PathBar.Visibility = Workspace.WorkspacePath is null ? Visibility.Collapsed : Visibility.Visible;
        if (!ready) Picker.Refresh();
        else
        {
            Sidebar.Refresh();
            ShowDetailForSelection();
        }
        RefreshPathBar();
        RestoreFromArchiveItem.IsEnabled = Workspace.SelectedArchivedItem is not null;
        App.RememberOpenWindows();
    }

    private void RefreshPathBar()
    {
        if (Workspace.WorkspacePath is null) return;
        var crumbs = FolderCrumb.ForPath(Workspace.WorkspacePath).ConvertAll(c => new PathBarCrumb(c));
        FolderCrumbs.ItemsSource = crumbs;
        _ = LoadCrumbIconsAsync(crumbs);
    }

    /// <summary>Populates each crumb's shell icon after the bar is already
    /// showing names â€” a slow shell lookup should never delay the bar
    /// itself, only fill in the icon once it arrives.</summary>
    private static async Task LoadCrumbIconsAsync(List<PathBarCrumb> crumbs)
    {
        foreach (var crumb in crumbs)
        {
            crumb.Icon = await FolderIcons.ForPathAsync(crumb.Path);
        }
    }

    /// <summary>Matches the mac's own path bar: a plain click selects
    /// nothing. Revealing and opening are deliberately gated behind the
    /// gestures a teacher already knows from their file manager â€” double-
    /// click to open, right-click to reveal â€” not a bare click
    /// (contracts/shared-rules.json -> workingFolderPathBar).</summary>
    private void FolderCrumbs_ItemClicked(BreadcrumbBar sender, BreadcrumbBarItemClickedEventArgs args)
    {
    }

    private void CrumbShowInExplorer_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: PathBarCrumb crumb })
        {
            FolderActions.ShowInFileExplorer(crumb.Path);
        }
    }

    private void CrumbOpenFolder_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: PathBarCrumb crumb })
        {
            FolderActions.OpenFolder(crumb.Path);
        }
    }

    private void Crumb_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: PathBarCrumb crumb })
        {
            FolderActions.OpenFolder(crumb.Path);
        }
    }

    // ---- Detail routing --------------------------------------------------

    public void ShowDetailForSelection()
    {
        RestoreFromArchiveItem.IsEnabled = Workspace.SelectedArchivedItem is not null;
        switch (Workspace.Selection)
        {
            case SidebarSelection.SectionItem(var code, var number)
                when Workspace.Courses.FirstOrDefault(c => c.Code == code) is { } course:
                if (DetailHost.Content is SectionDetailView current &&
                    string.Equals(current.CourseCode, code, StringComparison.OrdinalIgnoreCase) &&
                    current.SectionNumber == number)
                {
                    break;
                }
                // Fresh identity per selection: preview runners and local
                // state must never leak between sections.
                DetailHost.Content = new SectionDetailView(this, course, number);
                break;
            case SidebarSelection.CourseItem(var code)
                when Workspace.Courses.FirstOrDefault(c => c.Code == code) is { } course:
                if (DetailHost.Content is CourseSettingsView currentSettings &&
                    string.Equals(currentSettings.CourseCode, code, StringComparison.OrdinalIgnoreCase))
                {
                    break;
                }
                DetailHost.Content = new CourseSettingsView(this, course);
                break;
            case SidebarSelection.ArchivedEntry(var id)
                when Workspace.ArchivedItems.FirstOrDefault(a => a.Id == id) is { } item:
                DetailHost.Content = EmptyState(item.Title,
                    $"{item.Subtitle}. It is not part of your courses until you restore it.",
                    "Restoreâ€¦", () => Sidebar.ConfirmRestore(item));
                break;
            case SidebarSelection.BackupEntry(var backupId)
                when Workspace.BackupItems.FirstOrDefault(b => b.Id == backupId) is { } backup:
                DetailHost.Content = EmptyState(backup.Title,
                    $"{backup.Subtitle}. Restoring puts {backup.CourseCode} back to exactly this " +
                    "moment â€” the current version is archived first, and the backup is kept.",
                    "Restoreâ€¦", () => Sidebar.ConfirmRestoreBackup(backup));
                break;
            case null when Workspace.Courses.Count == 0:
                DetailHost.Content = EmptyState("No Courses Yet",
                    "Add your first course, or start from the example course to see how everything fits together.",
                    "Add a Courseâ€¦", () => _ = SidebarPane.OpenNewCourseWizard());
                break;
            case null:
                DetailHost.Content = EmptyState("Select a Course or Section",
                    "Choose a course to edit its settings, or a section to preview and deploy its website.",
                    null, null);
                break;
            default:
                DetailHost.Content = EmptyState("Course Not Found",
                    "Reload courses from the File menu, or choose a different working folder.", null, null);
                break;
        }
    }

    private static UIElement EmptyState(string title, string description, string? actionLabel, Action? action)
    {
        var panel = new StackPanel
        {
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Spacing = 8,
            MaxWidth = 460,
        };
        panel.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 22,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        panel.Children.Add(new TextBlock
        {
            Text = description,
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = TextAlignment.Center,
            Opacity = 0.7,
        });
        if (actionLabel is not null && action is not null)
        {
            var button = new Button
            {
                Content = actionLabel,
                HorizontalAlignment = HorizontalAlignment.Center,
                Style = Application.Current.Resources["AccentButtonStyle"] as Style,
                Margin = new Thickness(0, 8, 0, 0),
            };
            button.Click += (_, _) => action();
            panel.Children.Add(button);
        }
        return panel;
    }

    // ---- Menu commands ---------------------------------------------------

    public async void OpenWorkingFolder_Click(object sender, RoutedEventArgs e)
    {
        // Looped, because "Choose a Different Folderâ€¦" in the synced-folder
        // note reopens the OS picker rather than stranding the teacher on the
        // picker view: they have already said what they want.
        while (true)
        {
            var picker = new Windows.Storage.Pickers.FolderPicker();
            WinRT.Interop.InitializeWithWindow.Initialize(picker,
                WinRT.Interop.WindowNative.GetWindowHandle(this));
            picker.FileTypeFilter.Add("*");
            var folder = await picker.PickSingleFolderAsync();
            if (folder is null) return;

            switch (await SyncedFolderChoiceAsync(folder.Path))
            {
                case SyncedFolderChoice.GoAhead:
                    Workspace.ChooseWorkspace(folder.Path);
                    ShowSyncNoticeIfNeeded();   // the re-chosen open folder takes the notice form
                    return;
                case SyncedFolderChoice.ChooseAnother:
                    continue;
            }
        }
    }

    // ---- A working folder a cloud service keeps in sync -------------------
    //
    // Explained, never refused â€” contracts/shared-rules.json ->
    // cloudSyncedFolders. Two moments: a choice at the picker for a folder
    // just chosen (a dialog, two buttons, neither the default), and a quiet
    // notice for a folder the window restored (the InfoBar above the path
    // bar). Going ahead from either is remembered for that folder.

    private enum SyncedFolderChoice { GoAhead, ChooseAnother }

    /// <summary>
    /// Folders already shown a note in THIS process, keyed by resolved path,
    /// so a second window on the same folder does not repeat it before the
    /// teacher has answered. The remembered answer itself is in
    /// <see cref="AppSettings.AcceptedSyncedFolders"/>.
    /// </summary>
    private static readonly HashSet<string> _syncNoticedThisProcess = new(StringComparer.OrdinalIgnoreCase);

    private static string ResolvedFolder(string path)
    {
        try { return Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar); }
        catch { return path; }
    }

    private bool IsTheOpenFolder(string path) =>
        Workspace.WorkspacePath is { } open &&
        string.Equals(ResolvedFolder(open), ResolvedFolder(path), StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// The picker moment. Nothing to ask when the folder is not synced, was
    /// already accepted, cannot be used anyway (neither a working folder nor
    /// empty â€” the teacher is about to choose again, and a note about a folder
    /// they cannot use is noise), or is the folder this window already shows
    /// (a restore, not a choice: the notice form, so their courses are not
    /// hidden behind the picker).
    /// </summary>
    private async Task<SyncedFolderChoice> SyncedFolderChoiceAsync(string path)
    {
        if (CloudSyncedFolder.ServiceFor(path) is not { } service) return SyncedFolderChoice.GoAhead;
        if (App.Settings.HasAcceptedSyncFor(path)) return SyncedFolderChoice.GoAhead;
        if (IsTheOpenFolder(path)) return SyncedFolderChoice.GoAhead;
        if (Plantoir.Core.Models.Workspace.Classify(path) == WorkspaceState.Unrecognized) return SyncedFolderChoice.GoAhead;

        ActivityTrail.Note(ActivityTrail.Event.SyncedFolderNoticed,
            $"noticed that the folder just chosen is kept in sync with {service}");
        _syncNoticedThisProcess.Add(ResolvedFolder(path));

        // The path FIRST: the sentences say "this folder", and a teacher reads
        // that and looks for which folder.
        var body = new StackPanel { Spacing = 10 };
        body.Children.Add(new TextBlock { Text = path, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        body.Children.Add(new TextBlock { Text = CloudSyncWording.Summary, TextWrapping = TextWrapping.Wrap });
        foreach (string paragraph in CloudSyncWording.Explanation(service))
            body.Children.Add(new TextBlock { Text = paragraph, TextWrapping = TextWrapping.Wrap, Opacity = 0.85 });

        var dialog = new ContentDialog
        {
            Title = CloudSyncWording.Headline(service),
            Content = new ScrollViewer { Content = body, MaxHeight = 420 },
            PrimaryButtonText = CloudSyncWording.UseAnywayButton,
            CloseButtonText = CloudSyncWording.ChooseDifferentFolderButton,
            // Neither button is the default: this is the one moment the choice
            // is free, and a Return pressed out of habit must not decide it.
            DefaultButton = ContentDialogButton.None,
            XamlRoot = Content.XamlRoot,
        };
        AutomationProperties.SetAutomationId(dialog, "syncedFolderChoice");
        ContentDialogResult answer;
        try { answer = await dialog.ShowAsync(); }
        catch (Exception ex)
        {
            // A dialog that could not be shown must not block the folder:
            // the rule is "explained, never refused".
            App.LogDiagnostic($"synced-folder dialog: {ex.Message}");
            return SyncedFolderChoice.GoAhead;
        }
        if (answer != ContentDialogResult.Primary) return SyncedFolderChoice.ChooseAnother;

        RememberSyncAccepted(path, service, "chose to use the folder anyway");
        return SyncedFolderChoice.GoAhead;
    }

    private void RememberSyncAccepted(string path, string service, string how)
    {
        App.Settings.RememberAcceptedSyncFor(path);
        try { App.Settings.Save(); } catch (Exception ex) { App.LogDiagnostic($"settings: {ex.Message}"); }
        ActivityTrail.Note(ActivityTrail.Event.SyncedFolderAccepted,
            $"{how} â€” a folder kept in sync with {service}");
    }

    private string? _syncNoticeService;

    /// <summary>
    /// The restored moment: the headline, the one-line summary, a way to open
    /// the full explanation in place, and a button to dismiss it â€” once per
    /// folder, in this window or any other. Called whenever a working folder
    /// is adopted, because folders move into cloud services after they are
    /// made and the check costs nothing.
    /// </summary>
    public void ShowSyncNoticeIfNeeded()
    {
        SyncNotice.IsOpen = false;
        _syncNoticeService = null;
        if (Workspace.WorkspacePath is not { } path) return;
        if (CloudSyncedFolder.ServiceFor(path) is not { } service) return;
        if (App.Settings.HasAcceptedSyncFor(path)) return;
        if (!_syncNoticedThisProcess.Add(ResolvedFolder(path))) return;

        ActivityTrail.Note(ActivityTrail.Event.SyncedFolderNoticed,
            $"noticed that the working folder is kept in sync with {service}");
        _syncNoticeService = service;
        SyncNotice.Title = CloudSyncWording.Headline(service);
        SyncNotice.Message = CloudSyncWording.Summary;
        SyncNoticeDetails.Children.Clear();
        foreach (string paragraph in CloudSyncWording.Explanation(service))
            SyncNoticeDetails.Children.Add(new TextBlock { Text = paragraph, TextWrapping = TextWrapping.Wrap });
        var gotIt = new Button { Content = CloudSyncWording.DismissNoticeButton, HorizontalAlignment = HorizontalAlignment.Left };
        AutomationProperties.SetAutomationId(gotIt, "syncedFolderNoticeDismiss");
        gotIt.Click += (_, _) => SyncNotice.IsOpen = false;
        SyncNoticeDetails.Children.Add(gotIt);
        SyncNoticeDetails.Visibility = Visibility.Collapsed;
        SyncNoticeDetailsButton.Content = CloudSyncWording.ShowDetailsButton;
        SyncNotice.IsOpen = true;
    }

    private void SyncNoticeDetails_Click(object sender, RoutedEventArgs e)
    {
        bool showing = SyncNoticeDetails.Visibility == Visibility.Visible;
        SyncNoticeDetails.Visibility = showing ? Visibility.Collapsed : Visibility.Visible;
        SyncNoticeDetailsButton.Content = showing ? CloudSyncWording.ShowDetailsButton : CloudSyncWording.HideDetailsButton;
    }

    /// <summary>Dismissing IS going ahead: remembered for the folder, so it is not shown again.</summary>
    private void SyncNotice_Closed(InfoBar sender, InfoBarClosedEventArgs args)
    {
        if (_syncNoticeService is not { } service || Workspace.WorkspacePath is not { } path) return;
        _syncNoticeService = null;
        RememberSyncAccepted(path, service, "dismissed the note about the working folder");
    }

    private void NewWindow_Click(object sender, RoutedEventArgs e) => App.OpenNewWindow();

    private void ReloadCourses_Click(object sender, RoutedEventArgs e)
    {
        Workspace.Reload();
        ApplyState();
    }

    private void RestoreFromArchive_Click(object sender, RoutedEventArgs e)
    {
        if (Workspace.SelectedArchivedItem is { } item) Sidebar.ConfirmRestore(item);
    }

    private async void ReportProblem_Click(object sender, RoutedEventArgs e)
    {
        var store = ProblemReportStore.Standard;
        if (!store.HasAnythingToReport)
        {
            var emptyDialog = new ContentDialog
            {
                Title = "Nothing to report yet",
                Content = "Plantoir has not run any tasks or recorded any actions on this computer yet, so there is nothing to gather.",
                CloseButtonText = "OK",
                DefaultButton = ContentDialogButton.Close,
                XamlRoot = Content.XamlRoot,
            };
            await emptyDialog.ShowAsync();
            return;
        }

        var contentPanel = new StackPanel { Spacing = 12 };
        contentPanel.Children.Add(new TextBlock
        {
            Text = "This gathers what Plantoir did on the last few things you asked it to do, so somebody can see what went wrong.\n\n" +
                   "It includes the messages Plantoir showed you while it worked, your course codes and section numbers, " +
                   "the names of your pages, and what kind of Windows this is. It leaves out what you have written on your pages, " +
                   "your sign-in details for Netlify or Cloudflare, and your name.\n\n" +
                   "Save the report, then send it â€” with the file attached â€” to:",
            TextWrapping = TextWrapping.Wrap,
        });

        var emailButton = new HyperlinkButton
        {
            Content = ProblemReportBuilder.SupportEmail,
            NavigateUri = ProblemReportBuilder.SupportMailUri,
            Padding = new Thickness(0),
        };
        contentPanel.Children.Add(emailButton);

        CheckBox? promptCheckbox = null;
        if (store.HasAssistantPrompts)
        {
            promptCheckbox = new CheckBox
            {
                Content = ProblemReportBuilder.IncludePromptsLabel,
                IsChecked = false,
            };
            contentPanel.Children.Add(promptCheckbox);
        }

        var dialog = new ContentDialog
        {
            Title = "Send a report about a problem",
            Content = contentPanel,
            PrimaryButtonText = "Save Reportâ€¦",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = Content.XamlRoot,
        };

        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

        bool includePrompts = promptCheckbox?.IsChecked == true;

        var picker = new Windows.Storage.Pickers.FileSavePicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker,
            WinRT.Interop.WindowNative.GetWindowHandle(this));
        picker.SuggestedStartLocation = Windows.Storage.Pickers.PickerLocationId.Desktop;
        picker.FileTypeChoices.Add("Zip Archive", new List<string> { ".zip" });
        picker.SuggestedFileName = ProblemReportBuilder.SuggestedFileName(DateTime.Now).Replace(".zip", "");

        var file = await picker.PickSaveFileAsync();
        if (file is null) return;

        var builder = new ProblemReportBuilder(store);
        if (builder.BuildZip(file.Path, includePrompts))
        {
            FolderActions.ShowInFileExplorer(file.Path);
        }
        else
        {
            var errDialog = new ContentDialog
            {
                Title = "Could not save report",
                Content = "Plantoir could not gather the report files to save.",
                CloseButtonText = "OK",
                XamlRoot = Content.XamlRoot,
            };
            await errDialog.ShowAsync();
        }
    }

    private async void Settings_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new AssistantSettingsDialog(Workspace.Settings) { XamlRoot = Content.XamlRoot };
        try
        {
            await dialog.ShowAsync();
        }
        finally
        {
            // Normally a no-op â€” Closed already did this â€” but if ShowAsync
            // never got the dialog on screen at all (WinUI allows only one
            // ContentDialog at a time), Closed never fires, and without this
            // the dialog stays subscribed to the app-lifetime
            // AssistModelStores registry forever.
            dialog.DetachFromStores();
        }
    }

    private async void About_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new AboutDialog { XamlRoot = Content.XamlRoot };
        await dialog.ShowAsync();
    }

    private void OpenWorkingFolderAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        OpenWorkingFolder_Click(sender, null!);
        args.Handled = true;
    }

    private void NewWindowAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        App.OpenNewWindow();
        args.Handled = true;
    }

    private void ReloadCoursesAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        Workspace.Reload();
        ApplyState();
        args.Handled = true;
    }

    // ---- Preview menu ------------------------------------------------
    //
    // Mirrors mac's PreviewCommands (mac-app/QuartzTeachers/App/PreviewCommands.swift):
    // a top-level Back/Forward/Reload menu that tracks whichever section's
    // preview is currently shown, discoverable even though the same actions
    // already have working keyboard shortcuts scoped to SectionDetailView.

    private SectionDetailView? _previewMenuTrackedDetail;

    private void TrackDetailForPreviewMenu()
    {
        if (_previewMenuTrackedDetail is { } previous)
            previous.PreviewChromeChanged -= PreviewChromeChanged_RefreshMenu;

        _previewMenuTrackedDetail = DetailHost.Content as SectionDetailView;

        if (_previewMenuTrackedDetail is { } current)
            current.PreviewChromeChanged += PreviewChromeChanged_RefreshMenu;

        RefreshPreviewMenu();
    }

    private void PreviewChromeChanged_RefreshMenu(object? sender, EventArgs e) => RefreshPreviewMenu();

    private void RefreshPreviewMenu()
    {
        var detail = DetailHost.Content as SectionDetailView;
        PreviewBackItem.IsEnabled = detail?.CanGoBack == true;
        PreviewForwardItem.IsEnabled = detail?.CanGoForward == true;
        PreviewReloadItem.IsEnabled = detail?.HasPreview == true;
    }

    private void PreviewBack_Click(object sender, RoutedEventArgs e) =>
        (DetailHost.Content as SectionDetailView)?.PreviewGoBack();

    private void PreviewForward_Click(object sender, RoutedEventArgs e) =>
        (DetailHost.Content as SectionDetailView)?.PreviewGoForward();

    private void PreviewReload_Click(object sender, RoutedEventArgs e) =>
        (DetailHost.Content as SectionDetailView)?.PreviewReload();

    // Global counterparts to SectionDetailView's own scoped BackAccelerator/
    // ForwardAccelerator/ReloadAccelerator â€” see the comment on Root's
    // KeyboardAccelerators in MainWindow.xaml for why both scopes exist.
    private void PreviewBackAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        (DetailHost.Content as SectionDetailView)?.PreviewGoBack();
        args.Handled = true;
    }

    private void PreviewForwardAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        (DetailHost.Content as SectionDetailView)?.PreviewGoForward();
        args.Handled = true;
    }

    private void PreviewReloadAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        (DetailHost.Content as SectionDetailView)?.PreviewReload();
        args.Handled = true;
    }
}
