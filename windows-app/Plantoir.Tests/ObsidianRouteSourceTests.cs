namespace Plantoir.Tests;

/// <summary>
/// Open in Obsidian is ONE route (#491 item 4; #488's SidebarPane.OpenInObsidian):
/// every button and menu item goes through the sidebar, which — for a course
/// kept for reference — locks the pages again and shows the calm note the
/// first time, BEFORE Obsidian opens. The mac's toolbar skipped both until its
/// #457; this keeps a direct call from creeping back in on Windows. Read from
/// the source, since the views cannot be loaded here (the mac's
/// <c>ObsidianFolderTests</c> holds <c>FolderActions.openInObsidian</c> the same way).
/// </summary>
public class ObsidianRouteSourceTests
{
    private static string AppFolder => Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");

    [Fact]
    public void OnlyTheSidebar_OpensObsidian_ExceptTheHowITeachPage()
    {
        var callers = Directory.EnumerateFiles(AppFolder, "*.cs", SearchOption.AllDirectories)
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                           && !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
            .Select(file => (Name: Path.GetFileName(file),
                             Count: File.ReadAllLines(file).Count(line => line.Contains("FolderActions.OpenInObsidian(", StringComparison.Ordinal))))
            .Where(pair => pair.Count > 0)
            .ToDictionary(pair => pair.Name, pair => pair.Count);

        // The sidebar's route: the live course (Menus, through #581's ObsidianOpenRoute,
        // whose world is the one place that opens it) and the reference course (Reference).
        Assert.Equal(0, callers.GetValueOrDefault("SidebarPane.Menus.cs"));
        Assert.Contains("new ObsidianOpenRoute(new ObsidianWorld(", File.ReadAllText(Path.Combine(AppFolder, "Views", "SidebarPane.Menus.cs")));
        Assert.Equal(1, callers.GetValueOrDefault("ObsidianWorld.cs"));
        Assert.Equal(1, callers.GetValueOrDefault("SidebarPane.Reference.cs"));
        // The named exception: Course Settings' How I Teach row opens a PAGE of
        // a LIVE course (a reference course has no such row), not the course.
        Assert.Equal(1, callers.GetValueOrDefault("CourseSettingsView.xaml.cs"));
        Assert.Equal(3, callers.Values.Sum());
    }

    /// <summary>
    /// #581's route is built in two places only: Open in Obsidian (the
    /// sidebar, every route) and the preview trigger (no question asked). A
    /// third caller would be a second way in nobody reviewed.
    /// </summary>
    [Fact]
    public void TheAddOnsRouteIsBuiltOnlyBySidebarAndPreview()
    {
        var callers = Directory.EnumerateFiles(AppFolder, "*.cs", SearchOption.AllDirectories)
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                           && !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
            .Where(file => File.ReadAllText(file).Contains("new ObsidianOpenRoute(", StringComparison.Ordinal))
            .Select(Path.GetFileName).OrderBy(name => name, StringComparer.Ordinal).ToList();
        Assert.Equal(new[] { "SectionDetailView.xaml.cs", "SidebarPane.Menus.cs" }, callers);
    }

    /// <summary>The reference branch locks again before the note, and records it on the trail when it did anything.</summary>
    [Fact]
    public void TheReferenceRoute_LocksAgainBeforeTheNote()
    {
        string source = File.ReadAllText(Path.Combine(AppFolder, "Views", "SidebarPane.Reference.cs"));
        int start = source.IndexOf("private async Task OpenReferenceInObsidian(", StringComparison.Ordinal);
        Assert.True(start > 0);
        int locked = source.IndexOf("ReferenceLock.EnsureLocked(course)", start, StringComparison.Ordinal);
        int noted = source.IndexOf("Event.ReferenceCoursePagesLockedAgain", start, StringComparison.Ordinal);
        int note = source.IndexOf("NoteWasShown(course)", start, StringComparison.Ordinal);
        int opened = source.IndexOf("FolderActions.OpenInObsidian(", start, StringComparison.Ordinal);
        Assert.True(locked > start && noted > locked && note > noted && opened > note,
            $"lock {locked}, trail {noted}, note {note}, open {opened}: the pages must be locked again before the note and before Obsidian");
    }

    /// <summary>The section window's and Course Settings' toolbars go through the sidebar.</summary>
    [Theory]
    [InlineData("SectionDetailView.xaml.cs", "_window.SidebarPane.OpenInObsidian(_course, _sectionNumber)")]
    [InlineData("CourseSettingsView.xaml.cs", "_window.SidebarPane.OpenInObsidian(_course, null)")]
    public void TheToolbars_TakeTheOneRoute(string file, string call) =>
        Assert.Contains(call, File.ReadAllText(Path.Combine(AppFolder, "Views", file)));
}
