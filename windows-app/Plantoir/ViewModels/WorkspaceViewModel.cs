using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using Plantoir.Core.Models;
using Plantoir.Services;

namespace Plantoir.ViewModels;

/// <summary>What the sidebar has selected.</summary>
public abstract record SidebarSelection
{
    public sealed record CourseItem(string Code) : SidebarSelection;
    public sealed record SectionItem(string Code, int Number) : SidebarSelection;
    public sealed record ArchivedEntry(string Id) : SidebarSelection;
    public sealed record BackupEntry(string Id) : SidebarSelection;

    /// <summary>The stored string form for per-window restore (row 99).</summary>
    public string Serialized => this switch
    {
        CourseItem(var code) => WindowMemoryCodec.EncodeCourse(code),
        SectionItem(var code, var number) => WindowMemoryCodec.EncodeSection(code, number),
        ArchivedEntry(var id) => WindowMemoryCodec.EncodeArchived(id),
        BackupEntry(var id) => WindowMemoryCodec.EncodeBackup(id),
        _ => "",
    };

    /// <summary>Unrecognized or empty stored forms restore no selection.</summary>
    public static SidebarSelection? Parse(string? stored) =>
        WindowMemoryCodec.ParseSelection(stored) switch
        {
            { Kind: "course" } d => new CourseItem(d.Code),
            { Kind: "section" } d => new SectionItem(d.Code, d.Section),
            { Kind: "archived" } d => new ArchivedEntry(d.Id),
            { Kind: "backup" } d => new BackupEntry(d.Id),
            _ => null,
        };
}

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

    private string? _workspacePath;
    public string? WorkspacePath => _workspacePath;

    public WorkspaceState? State { get; private set; }
    public string? WorkspaceProblem { get; private set; }
    public List<Course> Courses { get; private set; } = new();
    public List<ArchivedItem> ArchivedItems { get; private set; } = new();
    public List<BackupItem> BackupItems { get; private set; } = new();

    private SidebarSelection? _selection;
    public SidebarSelection? Selection
    {
        get => _selection;
        set { _selection = value; Notify(); Notify(nameof(SelectedCourse)); Notify(nameof(SelectedArchivedItem)); }
    }

    // ---- Per-window sidebar memory (row 99) -------------------------------
    // null means "every course open" — the Windows fallback for brand-new
    // windows and for entries remembered before this state existed (the mac
    // restores all-collapsed here; Windows deliberately does not).
    public HashSet<string>? ExpandedCourseCodes { get; set; }
    public bool IsShowingArchived { get; set; }
    public bool IsShowingBackups { get; set; }

    public bool IsCourseExpanded(string code) => ExpandedCourseCodes?.Contains(code) ?? true;

    public void SetCourseExpanded(string code, bool expanded)
    {
        // First explicit toggle materializes the all-open fallback so the
        // OTHER courses keep their current openness.
        ExpandedCourseCodes ??= Courses.Select(c => c.Code).ToHashSet(StringComparer.Ordinal);
        if (expanded) ExpandedCourseCodes.Add(code);
        else ExpandedCourseCodes.Remove(code);
    }

    private string _filterText = "";
    public string FilterText
    {
        get => _filterText;
        set { _filterText = value; Notify(); Notify(nameof(FilteredCourses)); Notify(nameof(ShowsNoFilterMatches)); }
    }

    public List<Course> FilteredCourses => Workspace.Filter(Courses, _filterText);

    public bool ShowsNoFilterMatches =>
        Workspace.ShowsNoFilterMatches(_filterText, Courses.Count, FilteredCourses.Count);

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
        Workspace.CoursesDirectory(_workspacePath ?? throw new InvalidOperationException("No working folder."));

    // ---- Folder lifecycle ------------------------------------------------

    public void ChooseWorkspace(string path)
    {
        string? previous = _workspacePath;
        _workspacePath = path;
        Settings.WorkspacePath = path;
        Settings.Save();
        Reload();
        if (previous is not null && previous != path) ReleaseFolderIfUnused(previous);
        NoteBecameKey();
        Notify(nameof(WorkspacePath));
    }

    public void AdoptRestoredPath(string path)
    {
        App.LogDiagnostic($"AdoptRestoredPath called with '{path}'");
        if (string.IsNullOrEmpty(path) || !Directory.Exists(path) || path == _workspacePath)
        {
            App.LogDiagnostic($"AdoptRestoredPath early return: empty/not exists/already path");
            return;
        }
        _workspacePath = path;
        App.LogDiagnostic("AdoptRestoredPath calling Reload()");
        Reload();
        App.LogDiagnostic("AdoptRestoredPath Reload() finished, calling Notify(WorkspacePath)");
        Notify(nameof(WorkspacePath));
        App.LogDiagnostic("AdoptRestoredPath Notify(WorkspacePath) finished");
    }

    /// <summary>New window inherits the key window's folder; first window shows the picker.</summary>
    public void AdoptFolderForNewWindow()
    {
        if (_workspacePath is not null) return;
        var others = _windowModels.Where(m => m != this && m.WorkspacePath is not null)
                                  .Select(m => m.WorkspacePath!).ToList();
        string? inherited = Workspace.FolderForNewWindow(others, _mostRecentKeyFolderPath);
        if (inherited is not null) AdoptRestoredPath(inherited);
    }

    public void NoteBecameKey()
    {
        if (_workspacePath is not null) _mostRecentKeyFolderPath = _workspacePath;
    }

    public void UnregisterWindow()
    {
        if (IsTerminating) return;   // the quit path records the list itself
        _windowModels.Remove(this);
        if (_workspacePath is not null) ReleaseFolderIfUnused(_workspacePath);
    }

    private static void ReleaseFolderIfUnused(string path)
    {
        if (_windowModels.Any(m => m.WorkspacePath == path)) return;
        FolderContainers.StopContainer(path);
    }

    public static IReadOnlyList<WorkspaceViewModel> WindowModels => _windowModels;

    public static List<string> OpenFolderPaths() =>
        _windowModels.Where(m => m.WorkspacePath is not null).Select(m => m.WorkspacePath!).Distinct().ToList();

    // ---- Loading ---------------------------------------------------------

    public void Reload()
    {
        App.LogDiagnostic("WorkspaceViewModel.Reload starting");
        Courses = new List<Course>();
        ArchivedItems = new List<ArchivedItem>();
        BackupItems = new List<BackupItem>();
        WorkspaceProblem = null;
        State = null;
        if (_workspacePath is null) { NotifyLoaded(); return; }

        App.LogDiagnostic("WorkspaceViewModel.Reload: RefreshWorkspace starting");
        BundledToolchain.RefreshWorkspace(_workspacePath);
        App.LogDiagnostic("WorkspaceViewModel.Reload: RefreshWorkspace finished, Classify starting");
        State = Workspace.Classify(_workspacePath);
        App.LogDiagnostic($"WorkspaceViewModel.Reload: State is {State}");
        if (State == WorkspaceState.Ready)
        {
            if (!Directory.Exists(Workspace.CoursesDirectory(_workspacePath)))
                WorkspaceProblem = "There are no courses in this folder yet. Click New Course to create your first one.";
            else
            {
                App.LogDiagnostic("WorkspaceViewModel.Reload: DiscoverCourses starting");
                Courses = Workspace.DiscoverCourses(_workspacePath);
                App.LogDiagnostic($"WorkspaceViewModel.Reload: DiscoverCourses found {Courses.Count} courses");
                ArchivedItems = Workspace.FindArchivedItems(_workspacePath);
                BackupItems = Workspace.FindBackups(_workspacePath);
            }
        }
        App.LogDiagnostic("WorkspaceViewModel.Reload: calling NotifyLoaded()");
        NotifyLoaded();
        App.LogDiagnostic("WorkspaceViewModel.Reload: NotifyLoaded() done");
    }


    public async Task InitializeWorkspaceAsync()
    {
        if (_workspacePath is null) return;
        try
        {
            await Task.Run(() => ToolchainMirror.InitializeWorkspace(_workspacePath, BundledToolchain.Root));
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
        if (_workspacePath is null) return;
        try
        {
            ToolchainMirror.InitializeWorkspace(_workspacePath, BundledToolchain.Root);
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
