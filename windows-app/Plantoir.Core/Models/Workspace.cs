namespace Plantoir.Core.Models;

/// <summary>How a chosen folder reads as a prospective working folder.</summary>
public enum WorkspaceState
{
    /// <summary>Has the launchers: a real working folder.</summary>
    Ready,
    /// <summary>Empty (ignoring shell droppings): offer to set it up.</summary>
    CanBeInitialized,
    /// <summary>Non-empty, no launchers: an unfinished choice, NOT an error.</summary>
    Unrecognized,
}

/// <summary>
/// Pure workspace logic: folder classification, course discovery, filtering.
/// The window's view-model drives this; nothing here touches UI.
/// </summary>
public static class Workspace
{
    /// <summary>The launcher whose presence marks a working folder.</summary>
    public const string MarkerLauncher = "preview.ps1";

    /// <summary>Files that do not stop a folder being "effectively empty".</summary>
    private static readonly string[] IgnorableEntries = { ".DS_Store", "desktop.ini", "Thumbs.db" };

    public static WorkspaceState Classify(string folderPath)
    {
        if (File.Exists(Path.Combine(folderPath, MarkerLauncher))) return WorkspaceState.Ready;
        return IsEffectivelyEmpty(folderPath) ? WorkspaceState.CanBeInitialized : WorkspaceState.Unrecognized;
    }

    public static bool IsEffectivelyEmpty(string folderPath)
    {
        try
        {
            return !Directory.EnumerateFileSystemEntries(folderPath)
                .Any(entry => !IgnorableEntries.Contains(Path.GetFileName(entry), StringComparer.OrdinalIgnoreCase));
        }
        catch { return false; }
    }

    public static string CoursesDirectory(string workspacePath) => Path.Combine(workspacePath, "courses");

    /// <summary>
    /// Courses = subfolders of courses/ holding a course_config.json, sorted
    /// by code. A malformed config is skipped silently — it must not hide
    /// every other course.
    /// </summary>
    public static List<Course> DiscoverCourses(string workspacePath)
    {
        var courses = new List<Course>();
        string coursesDir = CoursesDirectory(workspacePath);
        IEnumerable<string> entries;
        try { entries = Directory.EnumerateDirectories(coursesDir); }
        catch { return courses; }
        foreach (string dir in entries)
        {
            string name = Path.GetFileName(dir);
            if (name.StartsWith('.') || name.StartsWith('_')) continue;
            string configPath = Path.Combine(dir, "course_config.json");
            if (!File.Exists(configPath)) continue;
            try { courses.Add(new Course(name, dir, CourseConfiguration.Load(configPath))); }
            catch { }
        }
        courses.Sort((a, b) => string.CompareOrdinal(a.Code, b.Code));
        return courses;
    }

    /// <summary>
    /// Archives live under courses/_backups/&lt;CODE&gt;/; only names shaped like
    /// removals count (the wizard's timestamp-only backups never appear).
    /// Newest first.
    /// </summary>
    public static List<ArchivedItem> FindArchivedItems(string workspacePath)
    {
        var items = new List<ArchivedItem>();
        string backupsRoot = Path.Combine(CoursesDirectory(workspacePath), "_backups");
        IEnumerable<string> courseDirs;
        try { courseDirs = Directory.EnumerateDirectories(backupsRoot); }
        catch { return items; }
        foreach (string courseDir in courseDirs)
        {
            string code = Path.GetFileName(courseDir);
            IEnumerable<string> files;
            try { files = Directory.EnumerateFiles(courseDir); }
            catch { continue; }
            foreach (string file in files)
                if (ArchivedItem.From(file, code) is { } item) items.Add(item);
        }
        items.Sort((a, b) => b.ArchivedAt.CompareTo(a.ArchivedAt));
        return items;
    }

    /// <summary>
    /// Backups live beside archives under courses/_backups/&lt;CODE&gt;/; only
    /// names shaped like &lt;CODE&gt;_backup_&lt;timestamp&gt;.zip count (row 106).
    /// Newest first.
    /// </summary>
    public static List<BackupItem> FindBackups(string workspacePath)
    {
        var items = new List<BackupItem>();
        string backupsRoot = Path.Combine(CoursesDirectory(workspacePath), "_backups");
        IEnumerable<string> courseDirs;
        try { courseDirs = Directory.EnumerateDirectories(backupsRoot); }
        catch { return items; }
        foreach (string courseDir in courseDirs)
        {
            string code = Path.GetFileName(courseDir);
            IEnumerable<string> files;
            try { files = Directory.EnumerateFiles(courseDir); }
            catch { continue; }
            foreach (string file in files)
                if (BackupItem.From(file, code) is { } item) items.Add(item);
        }
        items.Sort((a, b) => b.BackedUpAt.CompareTo(a.BackedUpAt));
        return items;
    }

    /// <summary>Case-insensitive match against code OR name; blank shows all.</summary>
    public static List<Course> Filter(IReadOnlyList<Course> courses, string filterText)
    {
        string query = filterText.Trim();
        if (query.Length == 0) return courses.ToList();
        return courses.Where(c =>
            c.Code.Contains(query, StringComparison.CurrentCultureIgnoreCase) ||
            c.Configuration.CourseName.Contains(query, StringComparison.CurrentCultureIgnoreCase)).ToList();
    }

    /// <summary>
    /// The no-matches message appears only when there was something to hide —
    /// an empty workspace is the window's empty state's business.
    /// </summary>
    public static bool ShowsNoFilterMatches(string filterText, int courseCount, int matchCount) =>
        filterText.Trim().Length > 0 && courseCount > 0 && matchCount == 0;

    /// <summary>
    /// New-window folder rule: no other windows → nothing (show the picker);
    /// else the most recently key folder if still open; else the first open.
    ///
    /// <para>"Still open" is <see cref="WorkingFolder.IsTheSame"/> rather than
    /// a string match, and the OPEN window's spelling is what comes back — the
    /// remembered key path and the window holding that folder can be spelled
    /// differently, and a new window inheriting a second spelling of a folder
    /// already open is how one folder comes to look like two.</para>
    /// </summary>
    public static string? FolderForNewWindow(IReadOnlyList<string> otherOpenFolderPaths, string? mostRecentKeyPath)
    {
        if (otherOpenFolderPaths.Count == 0) return null;
        if (mostRecentKeyPath is not null
            && otherOpenFolderPaths.FirstOrDefault(open => WorkingFolder.IsTheSame(open, mostRecentKeyPath))
               is { } stillOpen)
            return stillOpen;
        return otherOpenFolderPaths[0];
    }
}
