using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8b-19a2 (the mac's U4b2-6): while a Rename folder holds a course,
/// every act on that course is refused at its click, before anything is asked
/// or written, with <c>undo.wording.renameFolderUnderWay</c>, through ONE
/// refusal function (<see cref="CourseActivity.FolderRenameRefusal"/>); and
/// the contract row <c>backups.restoreWholeCourse.refusalCases</c> "a Rename
/// folder of the course is under way…" is replayed by name.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class FolderRenameRefusalTests : IDisposable
{
    // MARK: - Stored properties

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-folder-rename-refusal-");

    private const string RowName = "a Rename folder of the course is under way in a window, planning or swapping";

    /// <summary>
    /// Every entry point whose refusal is decided in a view: the file, the
    /// method's opening, the call it must make, and the first thing the act
    /// asks or writes, which the call must come before.
    /// </summary>
    private static readonly (string File, string Method, string Call, string Before)[] EntryPoints =
    [
        ("Plantoir/Views/CourseSettingsView.xaml.cs", "private async void Save_Click(", One, "SaveCourseSettings("),
        ("Plantoir/Views/SidebarPane.xaml.cs", "public async Task OpenRenameCourseDialog(", One, "IsPreviewingOrPublishing("),
        ("Plantoir/Views/SidebarPane.xaml.cs", "public async Task OpenAddSectionDialog(", One, "IsPreviewingOrPublishing("),
        ("Plantoir/Views/SidebarPane.xaml.cs", "private async Task ConfirmRemove(", One, "new ContentDialog"),
        ("Plantoir/Views/SidebarPane.xaml.cs", "AskWhichRestore(BackupItem item)", "CourseRestorer.WholeCourseRefusalFactsNow(", "new ContentDialog"),
        ("Plantoir/Views/SidebarPane.xaml.cs", "private async Task RestoreOneSection(", One, "IsPreviewingOrPublishing("),
        ("Plantoir/Views/SidebarPane.xaml.cs", "public async void ConfirmRestore(ArchivedItem item)", One, "new ContentDialog"),
        ("Plantoir/Views/SidebarPane.xaml.cs", "private async void AskWhenToDeploy(", One, "new CalendarDatePicker"),
        ("Plantoir/Views/SectionDetailView.xaml.cs", "private async Task PressPreviewAsync(", One, "AnotherProgramStandsInTheWay("),
        ("Plantoir/Views/SectionDetailView.xaml.cs", "private async Task<string?> DeployAsync(", One, "AnotherProgramStandsInTheWay("),
        ("Plantoir/Views/SectionDetailView.xaml.cs", "public async Task<string?> RebuildPreviewAsync(", One, "StopPreviewIfRunningAsync("),
        ("Plantoir/Views/SectionDetailView.xaml.cs", "private async void RunTheAutomatedStart(", One, "StopPreview();"),
        ("Plantoir/Views/SectionDetailView.xaml.cs", "private SiteHealthRepair.Outcome? WhyTheRepairCannotBePreviewedNow(", One, "WorkLease.InTheWay("),
        ("Plantoir/Views/SectionDetailView.xaml.cs", "private async Task PreviewAgainAfterRepairAsync(", "WhyTheRepairCannotBePreviewedNow(", "PreviewAgainPresses.CarryOutAsync("),
        ("Plantoir/Views/SectionDetailView.xaml.cs", "private void StartPreviewAgainAfterTheStop(", "WhyTheRepairCannotBePreviewedNow(", "StartAutomatedPreview("),
        ("Plantoir/Views/CourseSettingsView.xaml.cs", "private async void PreviewAgain_Click(", One, "StopPreviewForAsync("),
    ];

    /// <summary>
    /// Methods that ask whether a course is busy (or reach a preview or a
    /// deploy through #473's check) but are not an entry point above: each
    /// says where its refusal is decided instead, so a new method that asks
    /// is listed on purpose or goes red. Keyed by file name and method name.
    /// </summary>
    private static readonly (string File, string Method, string Why)[] NotEntryPoints =
    [
        ("MainWindow.Menus.cs", "SituationFor", "greys the menus (19b), refuses nothing"),
        ("MainWindow.Verbs.cs", "MenuRunner", "wires the runner's delegates; the start refuses in RebuildPreviewAsync"),
        ("MainWindow.Verbs.cs", "RebuildPreviewFor", "reaches RebuildPreviewAsync, which refuses before its stop"),
        ("MainWindow.xaml.cs", "ShowPreviewFor", "reaches StartPreviewIfIdle, then RunTheAutomatedStart, which refuses"),
        ("MainWindow.xaml.cs", "DeployFor", "reaches Deploy_Click, then DeployAsync, which refuses"),
        ("MainWindow.xaml.cs", "DeployForAsync", "reaches DeployAsync, which refuses"),
        ("MainWindow.xaml.cs", "RefusedWhileTheFolderIsGettingReady", "#473's check itself"),
        ("SectionDetailView.xaml.cs", "RefusedWhileThisSectionDeploys", "#386's check itself"),
        ("SectionDetailView.xaml.cs", "RaiseTheProblemsAlertIfDueAsync", "decides whether Preview Again is offered; the press refuses"),
        ("SectionDetailView.xaml.cs", "RepairFromTheProblemsTabAsync", "decides whether Preview Again is offered; the press refuses"),
        ("AssistWindow.xaml.cs", "Begin", "the assistant's (19a3)"),
        ("CopyAPageDialog.cs", "CopyNow", "not among this piece's acts"),
        ("CourseSettingsView.xaml.cs", "OpenRenameUnitWordDialog", "not among this piece's acts"),
        ("LinksChecklistDialog.cs", "OfferAsync", "not among this piece's acts"),
        ("StartOfYearDialog.cs", "OfferAsync", "Restore Course's press refuses in StartOfYearRestoreOffer"),
        ("StartOfYearDialog.cs", "Go", "not among this piece's acts"),
        ("StartOfYearDialog.cs", "UndoAsync", "not among this piece's acts"),
    ];

    private const string One = "CourseActivity.FolderRenameRefusal(";

    // MARK: - Computed properties

    private string Folder => Path.Combine(_root, "wf");
    private string CourseFolder => Path.Combine(Folder, "courses", "ICS3U");

    private static string WindowsApp => Path.Combine(ContractLoader.RepositoryRoot, "windows-app");

    private static string Sentence(string course) =>
        ContractLoader.LoadJson("shared-rules.json")["undo"]!["wording"]!["renameFolderUnderWay"]!.ToString().Replace("{course}", course);

    // MARK: - Initializer

    public FolderRenameRefusalTests()
    {
        CourseActivity.Reset();
        CourseRestorer.WhileRestoringTheWholeCourse = null;
        Directory.CreateDirectory(CourseFolder);
        File.WriteAllText(Path.Combine(Folder, Workspace.MarkerLauncher), "");
        File.WriteAllText(Path.Combine(CourseFolder, "course_config.json"), "{\"course_code\":\"ICS3U\",\"section_numbers\":[1]}");
    }

    // MARK: - Functions

    public void Dispose()
    {
        CourseActivity.Reset();
        CourseRestorer.WhileRestoringTheWholeCourse = null;
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private SortedDictionary<string, string?> Tree()
    {
        var tree = new SortedDictionary<string, string?>(StringComparer.Ordinal);
        foreach (string entry in Directory.EnumerateFileSystemEntries(Folder, "*", SearchOption.AllDirectories))
            tree[Path.GetRelativePath(Folder, entry)] = Directory.Exists(entry) ? null : Convert.ToBase64String(File.ReadAllBytes(entry));
        return tree;
    }

    // 1. The one refusal function.

    [Fact]
    public void TheOneRefusalSaysTheContractsSentenceWhileAClaimHoldsAndNothingOnceItEnds()
    {
        Assert.Null(CourseActivity.FolderRenameRefusal(Folder, "ICS3U"));
        var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;

        Assert.Equal(Sentence("ICS3U"), CourseActivity.FolderRenameRefusal(Folder, "ICS3U"));
        Assert.Null(CourseActivity.FolderRenameRefusal(Folder, "MPM2D"));
        Assert.Null(CourseActivity.FolderRenameRefusal(Path.Combine(_root, "other"), "ICS3U"));

        claim.Dispose();
        Assert.Null(CourseActivity.FolderRenameRefusal(Folder, "ICS3U"));
    }

    public static TheoryData<string> Endings => new() { "finished", "refused", "cancelled", "unexpected" };

    [Theory]
    [MemberData(nameof(Endings))]
    public async Task TheOneRefusalIsNullAfterEachOfTheRenamesEndings(string ending)
    {
        string? during = null;
        try
        {
            await SpecialFolderRenamer.RenameHoldingTheCourse(Folder, "ICS3U", _ =>
            {
                during = CourseActivity.FolderRenameRefusal(Folder, "ICS3U");
                return ending switch
                {
                    "finished" => Task.FromResult<RenameOutcome>(null!),
                    "refused" => throw new SpecialFolderRenamer.RenameException("refused"),
                    "cancelled" => throw new OperationCanceledException(),
                    _ => throw new InvalidOperationException("unexpected"),
                };
            });
        }
        catch (Exception) when (ending != "finished") { }

        Assert.Equal(Sentence("ICS3U"), during);
        Assert.Null(CourseActivity.FolderRenameRefusal(Folder, "ICS3U"));
    }

    // 2. The whole-course restore: the contract row replayed by name, and the run refused, writing nothing.

    [Fact]
    public void TheRefusalCasesRowForARenameUnderWayIsReplayedByName()
    {
        var rows = ContractLoader.LoadJson("course-management.json")["backups"]!["restoreWholeCourse"]!["refusalCases"]!.AsArray();
        var matching = new List<JsonNode>();
        foreach (var row in rows)
            if (row!["name"]!.ToString().StartsWith(RowName, StringComparison.Ordinal)) matching.Add(row);
        var only = Assert.Single(matching);
        var facts = only["facts"]!;

        var replayed = new CourseRestorer.WholeCourseRefusalFacts(
            FolderRenameUnderWay: facts["folderRenameUnderWay"]?.GetValue<bool>() ?? false,
            BusyHere: facts["busyHere"]?.GetValue<bool>() ?? false,
            RevisingAssistant: facts["revisingAssistant"] is not null);

        Assert.Equal(only["refusal"]!.ToString(), CourseRestorer.ContractNameOf(CourseRestorer.FirstWholeCourseRefusal(replayed)));
    }

    [Fact]
    public void WhileAClaimHoldsTheWholeCourseRestoresFirstRefusalIsTheRenameSaidWithItsSentence()
    {
        Assert.False(CourseRestorer.WholeCourseRefusalFactsNow(Folder, "ICS3U").FolderRenameUnderWay);
        using var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;

        var facts = CourseRestorer.WholeCourseRefusalFactsNow(Folder, "ICS3U");
        Assert.True(facts.FolderRenameUnderWay);
        Assert.Equal(CourseRestorer.WholeCourseRefusal.FolderRenameUnderWay, CourseRestorer.FirstWholeCourseRefusal(facts));
    }

    [Fact]
    public void TheWholeCourseRestoreRunIsRefusedWithTheSentenceAndWritesNothingWhileARenameHolds()
    {
        var before = Tree();
        using var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;
        var missing = new BackupItem("ICS3U", DateTime.Now, Path.Combine(_root, "no such backup.zip"));

        var refused = Assert.Throws<CourseRestorer.RestoreException>(
            () => CourseRestorer.RestoreWholeCourse(missing, null, Workspace.CoursesDirectory(Folder)));

        Assert.Equal(Sentence("ICS3U"), refused.Message);
        Assert.Equal(before, Tree());
        Assert.False(CourseActivity.CourseIsBeingRestored(Folder, "ICS3U"), "the restore's own claim is given back");
    }

    // 3. Get Ready's Restore Course: refused in the press's own turn, the offer staying open.

    [Fact]
    public void RestoreCoursesPressIsHeldBackWhileARenameHoldsAndTheOfferStaysOpen()
    {
        var backup = new BackupItem("ICS3U", DateTime.Now, Path.Combine(_root, "ICS3U.zip"));
        var offer = new StartOfYearRestoreOffer(new StartOfYearStoppedPartWay(1, "ICS3U", backup, 0), () => false, Folder);
        var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;

        Assert.Equal(RestoreCoursePress.HeldBackByARename, offer.RestoreCourseIsPressed());
        Assert.Equal(Sentence("ICS3U"), offer.HeldBackSentence);

        claim.Dispose();
        Assert.Equal(RestoreCoursePress.Closes, offer.RestoreCourseIsPressed());
    }

    // 4. The acts whose refusal is decided in a view: each asks the one function first.

    [Fact]
    public void EveryEntryPointAsksTheOneRefusalBeforeItAsksOrWrites()
    {
        foreach (var (file, method, call, before) in EntryPoints)
        {
            string body = MethodBody(File.ReadAllText(Path.Combine(WindowsApp, file)), method, file);
            int asked = body.IndexOf(call, StringComparison.Ordinal);
            int acts = body.IndexOf(before, StringComparison.Ordinal);
            Assert.True(asked >= 0, $"{method} in {file} does not call {call}");
            Assert.True(acts >= 0, $"{method} in {file} no longer holds {before}: update this table");
            Assert.True(asked < acts, $"{method} in {file} calls {call} only after {before}");
        }
    }

    [Fact]
    public void EveryViewMethodThatRefusesForABusyCourseIsAnEntryPointAbove()
    {
        // Widened after review 1 (LOW 1): every busy check a view or the main
        // window makes, #473's and #386's included, since every way into a
        // preview or a deploy asks #473's; and the owner is matched by its
        // method NAME (the old test compared header text, and a header with
        // a tuple return type never matched its entry).
        var busyCall = new Regex(@"(?<![A-Za-z])(?:CourseActivity\.(?:IsPreviewingOrPublishing|AssistHoldRefusal|IsPublishing|IsPublishingSection)|RefusedWhileThisSectionDeploys|RefusedWhileTheFolderIsGettingReady|WhyTheRepairCannotBePreviewedNow)\(");
        var header = new Regex(@"^    (?:private|public|internal|protected)[^\n]*?\s(?<name>\w+)(?:<[^>\n]*>)?\(", RegexOptions.Multiline);
        var paths = new List<string>();
        paths.AddRange(Directory.EnumerateFiles(Path.Combine(WindowsApp, "Plantoir", "Views"), "*.cs"));
        paths.AddRange(Directory.EnumerateFiles(Path.Combine(WindowsApp, "Plantoir"), "*.cs"));
        int found = 0;
        foreach (string path in paths)
        {
            string text = File.ReadAllText(path);
            string fileName = Path.GetFileName(path);
            foreach (Match call in busyCall.Matches(text))
            {
                Match? owner = null;
                foreach (Match candidate in header.Matches(text))
                    if (candidate.Index < call.Index) owner = candidate;
                Assert.NotNull(owner);
                string name = owner!.Groups["name"].Value;
                bool listed = false;
                foreach (var entry in EntryPoints)
                    if (fileName == Path.GetFileName(entry.File) && NameOf(entry.Method) == name) listed = true;
                foreach (var other in NotEntryPoints)
                    if (fileName == other.File && other.Method == name) listed = true;
                Assert.True(listed, $"{fileName}: {name} refuses for a busy course but is neither an entry point here nor listed as not one");
                found++;
            }
        }
        Assert.True(found >= 30, $"only {found} busy checks found: the scan has lost its files");
    }

    // 5. Review 1's MEDIUM 1: the three preview starts that still went ahead.

    [Theory]
    [InlineData("Plantoir/Views/SectionDetailView.xaml.cs", "public async Task<string?> RebuildPreviewAsync(", One, "StopPreviewIfRunningAsync(", "StartAutomatedPreview(")]
    [InlineData("Plantoir/Views/CourseSettingsView.xaml.cs", "private async void PreviewAgain_Click(", One, "StopPreviewForAsync(", "ShowPreviewFor(")]
    [InlineData("Plantoir/Views/SectionDetailView.xaml.cs", "private async Task PreviewAgainAfterRepairAsync(", "WhyTheRepairCannotBePreviewedNow(", "PreviewAgainPresses.CarryOutAsync(", "PreviewAgainPresses.CarryOutAsync(")]
    public void APreviewStartAsksTheOneRefusalBeforeAnythingIsStoppedOrStarted(string file, string method, string call, string stop, string start)
    {
        string body = MethodBody(File.ReadAllText(Path.Combine(WindowsApp, file)), method, file);
        int asked = body.IndexOf(call, StringComparison.Ordinal);
        int stopped = body.IndexOf(stop, StringComparison.Ordinal);
        int started = body.IndexOf(start, StringComparison.Ordinal);
        Assert.True(asked >= 0, $"{method} does not ask {call}");
        Assert.True(stopped > asked, $"{method} stops a preview before it asks {call}");
        Assert.True(started > asked, $"{method} starts a preview before it asks {call}");
        if (call != One)
        {
            // The repair's question asks the one function first of all.
            string why = MethodBody(File.ReadAllText(Path.Combine(WindowsApp, file)), "private SiteHealthRepair.Outcome? " + call, file);
            int renaming = why.IndexOf(One, StringComparison.Ordinal);
            Assert.True(renaming >= 0, $"{call} does not ask {One}");
            Assert.True(renaming < why.IndexOf("WorkLease.InTheWay(", StringComparison.Ordinal), $"{call} asks {One} after another program's build");
        }
    }

    private static string NameOf(string method)
    {
        string beforeParenthesis = method.Substring(0, method.IndexOf('('));
        int space = beforeParenthesis.LastIndexOf(' ');
        return beforeParenthesis.Substring(space + 1);
    }

    private static string MethodBody(string text, string method, string file)
    {
        int start = text.IndexOf(method, StringComparison.Ordinal);
        Assert.True(start >= 0, $"{method} is not in {file}");
        int end = text.IndexOf("\n    }\n", start, StringComparison.Ordinal);
        if (end < 0) end = text.IndexOf("\n    }\r\n", start, StringComparison.Ordinal);
        Assert.True(end > start, $"{method} in {file} has no end");
        return text.Substring(start, end - start);
    }
}
