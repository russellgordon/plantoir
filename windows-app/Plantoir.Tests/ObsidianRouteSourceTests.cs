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
            .Select(file => (Name: Path.GetFileName(file),
                             Count: File.ReadAllLines(file).Count(line => line.Contains("new ObsidianOpenRoute(", StringComparison.Ordinal))))
            .Where(pair => pair.Count > 0)
            .ToDictionary(pair => pair.Name, pair => pair.Count);
        Assert.Equal(1, callers.GetValueOrDefault("SidebarPane.Menus.cs"));
        Assert.Equal(1, callers.GetValueOrDefault("SectionDetailView.xaml.cs"));
        Assert.Equal(2, callers.Values.Sum());
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

    /// <summary>
    /// #681: a section's press reads the preview's address ONCE, in the one
    /// route, and resolves it against the build's list - so the page that
    /// opens and the page the assistant's reply names are the same answer.
    /// </summary>
    [Fact]
    public void TheSectionPressReadsTheAddressOnce()
    {
        string source = File.ReadAllText(Path.Combine(AppFolder, "Views", "SidebarPane.Menus.cs")).Replace("\r\n", "\n");
        int start = source.IndexOf("public Task<OpenInObsidianPress> OpenInObsidian(", StringComparison.Ordinal);
        Assert.True(start > 0);
        int end = source.IndexOf("\n    }\n", start, StringComparison.Ordinal);
        string press = source[start..end];
        Assert.Equal(1, press.Split("PreviewedAddressFor(").Length - 1);
        Assert.Contains("PreviewedPageSource.Resolve(", press);
        Assert.Contains(".Press(course, reveal, answer, section)", press);
    }

    /// <summary>
    /// #690: a course kept for reference's route that throws before opening is
    /// reported DidNotOpen by <c>Finishing</c>, never Opened from a finally.
    /// </summary>
    [Fact]
    public void TheReferenceRouteReportsDidNotOpenWhenItThrows()
    {
        string source = File.ReadAllText(Path.Combine(AppFolder, "Views", "SidebarPane.Menus.cs")).Replace("\r\n", "\n");
        int start = source.IndexOf("private static async Task Finishing(", StringComparison.Ordinal);
        Assert.True(start > 0);
        int end = source.IndexOf("\n    }\n", start, StringComparison.Ordinal);
        string finishing = source[start..end];
        int caught = finishing.IndexOf("catch", StringComparison.Ordinal);
        Assert.True(caught > 0);
        Assert.Contains("new OpenInObsidianPress.DidNotOpen()", finishing[caught..]);
        Assert.DoesNotContain("finally", finishing);
    }

    /// <summary>
    /// #690: a second press on a course kept for reference while its note is
    /// up is told it waits and returns BEFORE the trail line - so two presses
    /// leave one "page opened in Obsidian" line, not one per press - and the
    /// note marks the course asking for as long as it is up.
    /// </summary>
    [Fact]
    public void TheReferenceRoute_ASecondPressWhileTheNoteIsUpWritesNoSecondLine()
    {
        string source = File.ReadAllText(Path.Combine(AppFolder, "Views", "SidebarPane.Reference.cs")).Replace("\r\n", "\n");
        int start = source.IndexOf("private async Task OpenReferenceInObsidian(", StringComparison.Ordinal);
        Assert.True(start > 0);
        int end = source.IndexOf("\n    }\n", start, StringComparison.Ordinal);
        string route = source[start..end];
        int guard = route.IndexOf("ObsidianFigureAddOnsThisRun.Asking.Contains(course.DirectoryPath)", StringComparison.Ordinal);
        int noted = route.IndexOf("PreviewedPageSource.NoteThePress(", StringComparison.Ordinal);
        int asking = route.IndexOf("ObsidianFigureAddOnsThisRun.Asking.Add(course.DirectoryPath)", StringComparison.Ordinal);
        int shown = route.IndexOf("ShowDialogSafelyAsync(note)", StringComparison.Ordinal);
        Assert.True(guard > 0 && noted > guard, $"guard {guard}, trail line {noted}: the guard must come before the line");
        string turnedAway = route[guard..noted];
        Assert.Contains("report?.TrySetResult(new OpenInObsidianPress.WaitingForAnAnswer())", turnedAway);
        Assert.Contains("return;", turnedAway);
        Assert.Equal(1, route.Split("PreviewedPageSource.NoteThePress(").Length - 1);
        Assert.True(asking > noted && shown > asking, $"asking {asking}, note shown {shown}: the course is asking while the note is up");
        Assert.Contains("finally { ObsidianFigureAddOnsThisRun.Asking.Remove(course.DirectoryPath); }", route);
    }

    /// <summary>
    /// #690: the assistant's press goes through <c>AssistantsObsidianPress</c>,
    /// whose order is tested in Core - the window only supplies itself, and
    /// selects the section in <c>BringUp</c>, never before the wait.
    /// </summary>
    [Fact]
    public void TheAssistantsPressTakesTheTestedOrder()
    {
        string source = File.ReadAllText(Path.Combine(AppFolder, "MainWindow.xaml.cs")).Replace("\r\n", "\n");
        int start = source.IndexOf("public async Task<OpenInObsidianPress> PressOpenInObsidianFor(", StringComparison.Ordinal);
        Assert.True(start > 0);
        int end = source.IndexOf("\n    }\n", start, StringComparison.Ordinal);
        string press = source[start..end];
        Assert.Contains("AssistantsObsidianPress.RunAsync(", press);
        Assert.Contains("BringUp: ShowTheSection", press);
        Assert.DoesNotContain("Task.Delay", press);
        int run = press.IndexOf("AssistantsObsidianPress.RunAsync(", StringComparison.Ordinal);
        int selected = press.IndexOf("Workspace.Selection =", StringComparison.Ordinal);
        int shown = press.IndexOf("void ShowTheSection()", StringComparison.Ordinal);
        Assert.True(shown >= 0 && selected > shown && selected < run, "the section is selected only inside ShowTheSection");
    }

    /// <summary>
    /// #681: the address is WebView2's own, through the normaliser - never the
    /// page last viewed, which ignores the app's own loads (the contract's
    /// <c>obsidianOpensThePreviewedPage.rejected</c>).
    /// </summary>
    [Fact]
    public void ThePressReadsWebView2sSourceThroughTheNormaliser()
    {
        string source = File.ReadAllText(Path.Combine(AppFolder, "Views", "SectionDetailView.xaml.cs"));
        int start = source.IndexOf("internal string? PreviewedAddress()", StringComparison.Ordinal);
        Assert.True(start > 0);
        int end = source.IndexOf(";", start, StringComparison.Ordinal);
        string reader = source[start..end];
        Assert.Contains("CoreWebView2?.Source", reader);
        Assert.Contains("PreviewStartPage.Remember(", reader);
        Assert.DoesNotContain("LastViewedPages", reader);
    }
}
