using System.IO;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// The whole-window folder picker. Four states: choosing (header + button),
/// empty-folder confirmation, silent non-workspace (an unfinished choice is
/// NOT an error), and genuine problems in red.
/// </summary>
public sealed partial class WorkspacePickerView : UserControl
{
    private MainWindow _window = null!;

    public WorkspacePickerView() => InitializeComponent();

    public void Attach(MainWindow window) => _window = window;

    public void Refresh()
    {
        var workspace = _window.Workspace;
        bool offerInitialize = workspace.State == WorkspaceState.CanBeInitialized
                               && workspace.WorkspaceProblem is null;

        Header.Visibility = offerInitialize ? Visibility.Collapsed : Visibility.Visible;
        InitializeOffer.Visibility = offerInitialize ? Visibility.Visible : Visibility.Collapsed;
        InitializeButton.Visibility = offerInitialize ? Visibility.Visible : Visibility.Collapsed;
        ChooseButton.Content = offerInitialize ? "Choose a Different Folder…" : "Choose Folder…";

        if (offerInitialize && workspace.WorkspacePath is { } path)
        {
            // Wrapped as the main window wraps its own, so the icons arrive
            // after the names are already showing.
            var crumbs = FolderCrumb.ForPath(path).ConvertAll(c => new PathBarCrumb(c));
            ChosenCrumbs.ItemsSource = crumbs;
            _ = LoadCrumbIconsAsync(crumbs);
        }

        ProblemText.Text = workspace.WorkspaceProblem ?? "";
        ProblemText.Visibility = workspace.WorkspaceProblem is null ? Visibility.Collapsed : Visibility.Visible;
        // WorkspaceState.Unrecognized deliberately shows the choosing state
        // with no message: the guidance above already says what to pick.
    }

    private static async System.Threading.Tasks.Task LoadCrumbIconsAsync(System.Collections.Generic.List<PathBarCrumb> crumbs)
    {
        foreach (var crumb in crumbs) crumb.Icon = await FolderIcons.ForPathAsync(crumb.Path);
    }

    /// <summary>A plain click does nothing here either — the main bar's rule (item 6). Walking up the tree would be the picker's obvious reading, and is recommended rather than shipped.</summary>
    private void ChosenCrumbs_ItemClicked(BreadcrumbBar sender, BreadcrumbBarItemClickedEventArgs args) { }

    private void CrumbShowInExplorer_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: PathBarCrumb crumb }) FolderActions.ShowInFileExplorer(crumb.Path);
    }

    private void CrumbOpenFolder_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: PathBarCrumb crumb }) FolderActions.OpenFolder(crumb.Path);
    }

    private void Crumb_DoubleTapped(object sender, Microsoft.UI.Xaml.Input.DoubleTappedRoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: PathBarCrumb crumb }) FolderActions.OpenFolder(crumb.Path);
    }

    private void Choose_Click(object sender, RoutedEventArgs e) =>
        _window.OpenWorkingFolder_Click(sender, e);

    private async void Initialize_Click(object sender, RoutedEventArgs e)
    {
        InitializeButton.IsEnabled = false;
        ChooseButton.IsEnabled = false;
        InitializeButton.Content = "Setting up…";
        try
        {
            await _window.Workspace.InitializeWorkspaceAsync();
            _window.SyncNoticeAnsweredBySetUp();
            _window.ApplyState();
            if (_window.Workspace.State == WorkspaceState.Ready && _window.Workspace.WorkspaceProblem is null)
                _ = _window.SidebarPane.OpenNewCourseWizard();
        }
        finally
        {
            InitializeButton.IsEnabled = true;
            ChooseButton.IsEnabled = true;
            InitializeButton.Content = "Set Up This Folder";
        }
    }
}
