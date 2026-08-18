using System;
using System.IO;
using System.Linq;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
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
        // raw pixels, so a fixed 1100×720 looks postage-stamp small on a 200%
        // display — a proportion of the work area is right at any scale. Clamped
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
                Workspace.NoteBecameKey();
        };
        Closed += (_, _) => Workspace.UnregisterWindow();

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
    /// "--auto-preview" additionally presses Preview — the same code path
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

    /// <summary>
    /// Bring a section's preview onto the screen, for the assistant.
    ///
    /// The assistant's tools build the section's site, and a build nobody can
    /// see might as well not have happened — a teacher approved a rebuild,
    /// watched it finish, and had nothing to look at. So after a tool that
    /// leaves a fresh build behind, the assistant's window asks this one to
    /// select the section and start its preview. If a preview is already
    /// serving, starting is skipped — live reload is showing the change — but
    /// the window still comes forward so the teacher actually sees it.
    /// May be called from any thread.
    /// </summary>
    public void ShowPreviewFor(string courseCode, int section)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            try
            {
                Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
                if (DetailHost.Content is SectionDetailView detail) detail.StartPreviewIfIdle();
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"ShowPreviewFor exception: {ex}");
            }
        });
    }

    /// <summary>
    /// Deploy a section through this window's own flow — console, milestones,
    /// needs-rebuild decision and all — for the assistant. The assistant
    /// automates Plantoir; it does not deploy behind its back.
    /// </summary>
    public void DeployFor(string courseCode, int section)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            try
            {
                Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
                if (DetailHost.Content is SectionDetailView detail) detail.StartDeployForAutomation();
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"DeployFor exception: {ex}");
            }
        });
    }

    public async Task DeployForAsync(string courseCode, int section)
    {
        var tcs = new TaskCompletionSource();
        DispatcherQueue.TryEnqueue(() =>
        {
            try
            {
                Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
                if (DetailHost.Content is SectionDetailView detail) detail.StartDeployForAutomation();
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"DeployForAsync exception: {ex}");
            }
            finally
            {
                tcs.TrySetResult();
            }
        });
        await tcs.Task;
    }

    public bool IsSectionBusy(string courseCode, int section)
    {
        if (DetailHost.Content is SectionDetailView detail)
        {
            return detail.IsBusy;
        }
        return false;
    }

    /// <summary>
    /// Stop a section's preview, for the assistant — the first half of
    /// stop, edit, start again. No Activate: a stop is not the moment to
    /// pull the teacher away from the conversation.
    /// </summary>
    public void StopPreviewFor(string courseCode, int section)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            try
            {
                Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
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
                Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
                if (DetailHost.Content is SectionDetailView detail)
                {
                    await detail.StopPreviewIfRunningAsync();
                }
            }
            finally
            {
                tcs.TrySetResult();
            }
        });
        await tcs.Task;
    }

    /// <summary>
    /// Restore the remembered selection — but only when its target still
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
        FolderCrumbs.ItemsSource = FolderCrumb.ForPath(Workspace.WorkspacePath);
    }

    private void FolderCrumbs_ItemClicked(BreadcrumbBar sender, BreadcrumbBarItemClickedEventArgs args)
    {
        if (args.Item is FolderCrumb crumb) FolderActions.ShowInFileExplorer(crumb.Path);
    }

    private void CrumbShowInExplorer_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: FolderCrumb crumb })
        {
            FolderActions.ShowInFileExplorer(crumb.Path);
        }
    }

    private void CrumbOpenFolder_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: FolderCrumb crumb })
        {
            FolderActions.OpenFolder(crumb.Path);
        }
    }

    private void Crumb_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: FolderCrumb crumb })
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
                // Fresh identity per selection: preview runners and local
                // state must never leak between sections.
                DetailHost.Content = new SectionDetailView(this, course, number);
                break;
            case SidebarSelection.CourseItem(var code)
                when Workspace.Courses.FirstOrDefault(c => c.Code == code) is { } course:
                DetailHost.Content = new CourseSettingsView(this, course);
                break;
            case SidebarSelection.ArchivedEntry(var id)
                when Workspace.ArchivedItems.FirstOrDefault(a => a.Id == id) is { } item:
                DetailHost.Content = EmptyState(item.Title,
                    $"{item.Subtitle}. It is not part of your courses until you restore it.",
                    "Restore…", () => Sidebar.ConfirmRestore(item));
                break;
            case SidebarSelection.BackupEntry(var backupId)
                when Workspace.BackupItems.FirstOrDefault(b => b.Id == backupId) is { } backup:
                DetailHost.Content = EmptyState(backup.Title,
                    $"{backup.Subtitle}. Restoring puts {backup.CourseCode} back to exactly this " +
                    "moment — the current version is archived first, and the backup is kept.",
                    "Restore…", () => Sidebar.ConfirmRestoreBackup(backup));
                break;
            case null when Workspace.Courses.Count == 0:
                DetailHost.Content = EmptyState("No Courses Yet",
                    "Add your first course, or start from the example course to see how everything fits together.",
                    "Add a Course…", () => _ = SidebarPane.OpenNewCourseWizard());
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
        var picker = new Windows.Storage.Pickers.FolderPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker,
            WinRT.Interop.WindowNative.GetWindowHandle(this));
        picker.FileTypeFilter.Add("*");
        var folder = await picker.PickSingleFolderAsync();
        if (folder is not null) Workspace.ChooseWorkspace(folder.Path);
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
                   "Save the report, then send it — with the file attached — to:",
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
            PrimaryButtonText = "Save Report…",
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
        await dialog.ShowAsync();
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
}
