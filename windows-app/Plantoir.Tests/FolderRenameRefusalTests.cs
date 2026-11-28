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
        ("Plantoir/Views/SectionDetailView.xaml.cs", "private async Task PressPreviewAsync(", One, "OfferTodaysClassAsync("),
        ("Plantoir/Views/SectionDetailView.xaml.cs", "private async Task<string?> DeployAsync(", One, "SectionRuns.Deploy("),
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
        var busyCall = new Regex(@"CourseActivity\.(?:IsPreviewingOrPublishing|AssistHoldRefusal)\(");
        var header = new Regex(@"^    (?:private|public|internal|protected)[^\n]*\(", RegexOptions.Multiline);
        foreach (string path in Directory.EnumerateFiles(Path.Combine(WindowsApp, "Plantoir", "Views"), "*.cs"))
        {
            string text = File.ReadAllText(path);
            foreach (Match found in busyCall.Matches(text))
            {
                Match? owner = null;
                foreach (Match candidate in header.Matches(text))
                    if (candidate.Index < found.Index) owner = candidate;
                Assert.NotNull(owner);
                bool listed = false;
                foreach (var entry in EntryPoints)
                    if (owner!.Value.Contains(entry.Method, StringComparison.Ordinal)) listed = true;
                Assert.True(listed, $"{Path.GetFileName(path)}: {owner!.Value.Trim()} refuses for a busy course but is not an entry point here");
            }
        }
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
