using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using Plantoir.Core.Models;
using Plantoir.Services;

namespace Plantoir.ViewModels;

// SidebarSelection now lives in Plantoir.Core.Models (WorkingFolderSelection.cs),
// beside the rule that clears it — Plantoir.Tests cannot reference this
// assembly, so nothing here can be gated by a test. See #162.

/// <summary>
/// One window's state: its working folder, discovered courses, archived
/// items, and selection. Every window is fully independent — this is
/// per-window, never a singleton.
/// </summary>
public sealed class WorkspaceViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    private static readonly List<WorkspaceViewModel> _windowModels = new();
    private static string? _mostRecentKeyFolderPath;
    public static bool IsTerminating { get; set; }

    public AppSettings Settings { get; }

    /// <summary>
    /// The folder this window is pointed at, what it has selected, and the
    /// sidebar memory that survives a folder change — all in Core, so the
    /// rule about what a folder change lets go of can be tested.
    /// </summary>
    private readonly WindowFolderState _state = new();

    public string? WorkspacePath => _state.FolderPath;

    public WorkspaceState? State { get; private set; }
    public string? WorkspaceProblem { get; private set; }
    public List<Course> Courses { get; private set; } = new();
    public List<ArchivedItem> ArchivedItems { get; private set; } = new();
    public List<BackupItem> BackupItems { get; private set; } = new();

    public SidebarSelection? Selection
    {
        get => _state.Selection;
        set { _state.Selection = value; Notify(); Notify(nameof(SelectedCourse)); Notify(nameof(SelectedArchivedItem)); }
    }

    // ---- Per-window sidebar memory (row 99) -------------------------------
    // null means "every course open" — the Windows fallback for brand-new
    // windows and for entries remembered before this state existed (the mac
    // restores all-collapsed here; Windows deliberately does not).
    public HashSet<string>? ExpandedCourseCodes
    {
        get => _state.ExpandedCourseCodes;
        set => _state.ExpandedCourseCodes = value;
    }

    public bool IsShowingArchived
    {
        get => _state.IsShowingArchived;
        set => _state.IsShowingArchived = value;
    }

    public bool IsShowingBackups
    {
        get => _state.IsShowingBackups;
        set => _state.IsShowingBackups = value;
    }

    public bool IsCourseExpanded(string code) => ExpandedCourseCodes?.Contains(code) ?? true;

    public void SetCourseExpanded(string code, bool expanded)
    {
        // First explicit toggle materializes the all-open fallback so the
        // OTHER courses keep their current openness.
        ExpandedCourseCodes ??= Courses.Select(c => c.Code).ToHashSet(StringComparer.Ordinal);
        if (expanded) ExpandedCourseCodes.Add(code);
        else ExpandedCourseCodes.Remove(code);
    }

    public string FilterText
    {
        get => _state.FilterText;
        set { _state.FilterText = value; Notify(); Notify(nameof(FilteredCourses)); Notify(nameof(ShowsNoFilterMatches)); }
    }

    public List<Course> FilteredCourses => Workspace.Filter(Courses, _state.FilterText);

    public bool ShowsNoFilterMatches =>
        Workspace.ShowsNoFilterMatches(_state.FilterText, Courses.Count, FilteredCourses.Count);

    public Course? SelectedCourse => Selection switch
    {
        SidebarSelection.CourseItem(var code) => Courses.FirstOrDefault(c => c.Code == code),
        SidebarSelection.SectionItem(var code, _) => Courses.FirstOrDefault(c => c.Code == code),
        _ => null,
    };

    public ArchivedItem? SelectedArchivedItem => Selection is SidebarSelection.ArchivedEntry(var id)
        ? ArchivedItems.FirstOrDefault(a => a.Id == id)
        : null;

    public BackupItem? SelectedBackupItem => Selection is SidebarSelection.BackupEntry(var id)
        ? BackupItems.FirstOrDefault(b => b.Id == id)
        : null;

    public WorkspaceViewModel(AppSettings settings)
    {
        Settings = settings;
        _windowModels.Add(this);
    }

    public string CoursesDirectory() =>
        Workspace.CoursesDirectory(_state.FolderPath ?? throw new InvalidOperationException("No working folder."));

    // ---- Folder lifecycle ------------------------------------------------

    /// <summary>
    /// The teacher chose a folder. Everything a folder change DECIDES happens
    /// in <see cref="PointAtFolder"/>; what is left here is this route's own
    /// business — remembering the choice, saying so on the trail, and giving
    /// back the folder that was left.
    /// </summary>
    public void ChooseWorkspace(string path)
    {
        Settings.WorkspacePath = path;
        Settings.Save();
        Plantoir.Core.Scripting.ActivityTrail.Note(
            Plantoir.Core.Scripting.ActivityTrail.Event.WorkingFolderOpened,
            $"working folder opened — {path}");
        string? leftBehind = PointAtFolder(path);
        MarkBuildsFolder();
        if (leftBehind is not null) ReleaseFolderIfUnused(leftBehind);
        NoteBecameKey();
        Notify(nameof(WorkspacePath));
    }

    /// <summary>
    /// The app restored a folder this window had open last time, or a new
    /// window inherited one. Same funnel, deliberately: a rule that only one
    /// of the two routes obeys is a rule the other quietly breaks.
    ///
    /// <para>Nothing here records the choice or releases a folder — a restored
    /// window must not write "working folder opened" twice, and it has left no
    /// folder to give back.</para>
    /// </summary>
    public void AdoptRestoredPath(string path)
    {
        App.LogDiagnostic($"AdoptRestoredPath called with '{path}'");
        if (string.IsNullOrEmpty(path) || !Directory.Exists(path)
            || WorkingFolder.IsTheSame(path, WorkspacePath))
        {
            App.LogDiagnostic($"AdoptRestoredPath early return: empty/not exists/already path");
            return;
        }
        Plantoir.Core.Scripting.ActivityTrail.Note(
            Plantoir.Core.Scripting.ActivityTrail.Event.WorkingFolderOpened,
            $"working folder opened — {path}");
        App.LogDiagnostic("AdoptRestoredPath calling PointAtFolder()");
        PointAtFolder(path);
        MarkBuildsFolder();
        App.LogDiagnostic("AdoptRestoredPath Reload() finished, calling Notify(WorkspacePath)");
        Notify(nameof(WorkspacePath));
        App.LogDiagnostic("AdoptRestoredPath Notify(WorkspacePath) finished");
    }

    /// <summary>
    /// The ONE funnel both ways of adopting a folder go through: let go of
    /// whatever named a course in the folder being left, point at the new one,
    /// load it, and tell the window. Returns the folder left behind, or null.
    ///
    /// <para><c>Notify(nameof(Selection))</c> is load-bearing twice over, and
    /// AFTER the reload. It re-renders the sidebar and detail pane with the
    /// selection gone — without it the pane keeps greeting the teacher with
    /// "Course Not Found" about a folder they have only just arrived in — and
    /// it is what drives <c>App.RememberOpenWindows()</c>, so without it the
    /// remembered frame still names the old folder's course and the whole
    /// defect comes back on the next launch.</para>
    /// </summary>
    private string? PointAtFolder(string path)
    {
        string? leftBehind = _state.PointAt(path);
        Reload();
        // Only when a folder was actually left, so a window adopting its
        // FIRST folder still notifies exactly what it always did — that one
        // runs mid-construction, before the window has finished building
        // itself, and it has nothing to let go of anyway.
        if (leftBehind is not null)
        {
            Notify(nameof(Selection));
            Notify(nameof(SelectedCourse));
            Notify(nameof(SelectedArchivedItem));
        }
        return leftBehind;
    }

    /// <summary>
    /// Names this folder's builds folder — only once the folder is known to
    /// be a WORKING folder. Marking on every open would create a builds
    /// folder for a Downloads picked by mistake, one the sweep could never
    /// remove because the folder still exists: litter from the anti-litter
    /// change. The mac writes its marker when a build folder is made; this is
    /// the nearest moment the app has.
    /// </summary>
    private void MarkBuildsFolder()
    {
        if (_state.FolderPath is { } path && State == WorkspaceState.Ready)
            BuildOutputLocation.WriteWorkingFolderMarker(path);
    }

    /// <summary>New window inherits the key window's folder; first window shows the picker.</summary>
    public void AdoptFolderForNewWindow()
    {
        if (_state.FolderPath is not null) return;
        var others = _windowModels.Where(m => m != this && m.WorkspacePath is not null)
                                  .Select(m => m.WorkspacePath!).ToList();
        string? inherited = Workspace.FolderForNewWindow(others, _mostRecentKeyFolderPath);
        if (inherited is not null) AdoptRestoredPath(inherited);
    }

    public void NoteBecameKey()
    {
        if (_state.FolderPath is not null) _mostRecentKeyFolderPath = _state.FolderPath;
    }

    public void UnregisterWindow()
    {
        if (IsTerminating) return;   // the quit path records the list itself
        _windowModels.Remove(this);
        if (_state.FolderPath is not null) ReleaseFolderIfUnused(_state.FolderPath);
    }

    /// <summary>
    /// Stop a folder's container once no window still holds it.
    ///
    /// <para>The match is <see cref="WorkingFolder.IsTheSame"/>, not string
    /// equality: a window holding <c>C:\work</c> holds <c>C:\Work</c> too,
    /// and answering otherwise here does not merely miss a cleanup — it stops
    /// the container of a folder that IS still open, taking a running preview
    /// with it.</para>
    /// </summary>
    private static void ReleaseFolderIfUnused(string path)
    {
        if (WorkingFolder.AnyWindowStillHolds(_windowModels.Select(m => m.WorkspacePath), path)) return;
        FolderContainers.StopContainer(path);
    }

    public static IReadOnlyList<WorkspaceViewModel> WindowModels => _windowModels;

    public static List<string> OpenFolderPaths() =>
        _windowModels.Where(m => m.WorkspacePath is not null).Select(m => m.WorkspacePath!)
                     .Distinct(WorkingFolder.Comparer).ToList();

    // ---- Loading ---------------------------------------------------------

    public void Reload()
    {
        App.LogDiagnostic("WorkspaceViewModel.Reload starting");
        Courses = new List<Course>();
        ArchivedItems = new List<ArchivedItem>();
        BackupItems = new List<BackupItem>();
        WorkspaceProblem = null;
        State = null;
        if (_state.FolderPath is null) { NotifyLoaded(); return; }

        App.LogDiagnostic("WorkspaceViewModel.Reload: RefreshWorkspace starting");
        BundledToolchain.RefreshWorkspace(_state.FolderPath);
        App.LogDiagnostic("WorkspaceViewModel.Reload: RefreshWorkspace finished, Classify starting");
        State = Workspace.Classify(_state.FolderPath);
        App.LogDiagnostic($"WorkspaceViewModel.Reload: State is {State}");
        if (State == WorkspaceState.Ready)
        {
            if (!Directory.Exists(Workspace.CoursesDirectory(_state.FolderPath)))
                WorkspaceProblem = "There are no courses in this folder yet. Click New Course to create your first one.";
            else
            {
                App.LogDiagnostic("WorkspaceViewModel.Reload: DiscoverCourses starting");
                Courses = Workspace.DiscoverCourses(_state.FolderPath);
                App.LogDiagnostic($"WorkspaceViewModel.Reload: DiscoverCourses found {Courses.Count} courses");
                ArchivedItems = Workspace.FindArchivedItems(_state.FolderPath);
                BackupItems = Workspace.FindBackups(_state.FolderPath);
            }
        }
        App.LogDiagnostic("WorkspaceViewModel.Reload: calling NotifyLoaded()");
        NotifyLoaded();
        App.LogDiagnostic("WorkspaceViewModel.Reload: NotifyLoaded() done");
    }


    public async Task InitializeWorkspaceAsync()
    {
        if (_state.FolderPath is null) return;
        try
        {
            await Task.Run(() => ToolchainMirror.InitializeWorkspace(_state.FolderPath, BundledToolchain.Root));
        }
        catch (Exception error)
        {
            WorkspaceProblem = error is InvalidOperationException
                ? error.Message
                : $"Could not set up this folder: {error.Message}";
            Notify(nameof(WorkspaceProblem));
            return;
        }
        Reload();
    }

    public void InitializeWorkspace()
    {
        if (_state.FolderPath is null) return;
        try
        {
            ToolchainMirror.InitializeWorkspace(_state.FolderPath, BundledToolchain.Root);
        }
        catch (Exception error)
        {
            WorkspaceProblem = error is InvalidOperationException
                ? error.Message
                : $"Could not set up this folder: {error.Message}";
            Notify(nameof(WorkspaceProblem));
            return;
        }
        Reload();
    }

    private void NotifyLoaded()
    {
        Notify(nameof(State));
        Notify(nameof(WorkspaceProblem));
        Notify(nameof(Courses));
        Notify(nameof(FilteredCourses));
        Notify(nameof(ArchivedItems));
        Notify(nameof(ShowsNoFilterMatches));
    }

    private void Notify([CallerMemberName] string? property = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
}
