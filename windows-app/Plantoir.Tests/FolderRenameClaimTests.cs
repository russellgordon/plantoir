using Plantoir.Core.Models;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8b-19a1 (the mac's <c>CourseActivity.beginFolderRename</c>,
/// <c>folderRenameSwapBegins</c>, <c>endFolderRename</c>,
/// <c>courseIsRenamingAFolder</c>, <c>folderRenameIsSwapping</c>, and
/// <c>FolderRenameRun.swapBegins</c>'s restore half): a Rename folder holds
/// its course by ONE claim, keyed by working folder and course code, from the
/// click until the rename ends however it ends. A second rename of a claimed
/// course is refused at its click with <c>undo.wording.renameFolderUnderWay</c>;
/// a whole-course restore holding the course refuses the rename's swap.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class FolderRenameClaimTests : IDisposable
{
    // MARK: - Stored properties

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-folder-rename-claim-");

    private const string Settings =
        "{\"course_code\":\"ICS3U\",\"num_sections\":2,\"section_numbers\":[1,2],\"per_section_folders\":[\"All Classes\",\"Tasks\"],"
        + "\"shared_folders\":[\"Concepts\"],\"hidden\":[],\"expandable\":[\"Concepts\",\"Tasks\"]}";

    // MARK: - Computed properties

    private string Folder => Path.Combine(_root, "wf");
    private string OtherFolder => Path.Combine(_root, "other");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string CourseFolder => Path.Combine(Folder, "courses", "ICS3U");
    private string ConfigPath => Path.Combine(CourseFolder, "course_config.json");

    // MARK: - Initializer

    public FolderRenameClaimTests()
    {
        CourseActivity.Reset();
        CourseRestorer.WhileRestoringTheWholeCourse = null;
        Directory.CreateDirectory(CourseFolder);
        File.WriteAllText(Path.Combine(Folder, Workspace.MarkerLauncher), "");
        File.WriteAllText(ConfigPath, Settings);
        Write("section1/Tasks/Quiz 1.md", "See [[Tasks/Quiz 2]].\n");
        Write("section1/index.md", "Start with [[Tasks/Quiz 1]].\n");
        Write("section2/Tasks/Quiz 2.md", "Quiz two.\n");
    }

    // MARK: - Functions

    public void Dispose()
    {
        CourseActivity.Reset();
        CourseRestorer.WhileRestoringTheWholeCourse = null;
        string index = Path.Combine(CourseFolder, "section1", "index.md");
        if (File.Exists(index)) File.SetAttributes(index, FileAttributes.Normal);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private void Write(string relative, string text)
    {
        string full = Path.Combine(CourseFolder, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, text);
    }

    private static string Wording(string key) =>
        ContractLoader.LoadJson("shared-rules.json")["undo"]!["wording"]![key]!.ToString();

    /// <summary>Every folder and file under the working folder, with its bytes, leaving out the door's own <c>courses/.internal</c>.</summary>
    private SortedDictionary<string, string?> Tree()
    {
        var tree = new SortedDictionary<string, string?>(StringComparer.Ordinal);
        foreach (string entry in Directory.EnumerateFileSystemEntries(Folder, "*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(Folder, entry).Replace('\\', '/');
            if (UndoOp.PartInside("courses/.internal", relative) is not null) continue;
            tree[relative] = Directory.Exists(entry) ? null : Convert.ToBase64String(File.ReadAllBytes(entry));
        }
        return tree;
    }

    /// <summary>The rename as the sheet runs it, through a test's own list and door, asking the claim's swap question.</summary>
    private RenameOutcome RenameAsTheSheetDoes(CourseActivity.FolderRenameClaim claim, UndoSeams? seams = null)
    {
        var list = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null);
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, seams, trail: list.Trail);
        var configuration = CourseConfiguration.Load(ConfigPath);
        var settings = SpecialFolderRenamer.RenamingTheSettings(configuration, ConfigPath, "Tasks", "Assessments", FolderScope.PerSection, CourseFolder);
        return SpecialFolderRenamer.Rename("Tasks", "Assessments", FolderScope.PerSection, CourseFolder, new[] { 1, 2 },
                                           settings, false, list, door, () => CourseActivity.RenameSwapBegins(claim));
    }

    private void NothingIsClaimed()
    {
        Assert.False(CourseActivity.CourseIsRenamingAFolder(Folder, "ICS3U"), "the claim was given back");
        Assert.False(CourseActivity.FolderRenameIsSwapping(Folder, "ICS3U"));
    }

    // 1. A claim taken.

    [Fact]
    public void AClaimHoldsItsCourseOnlyAndSaysWhenItsSwapBegins()
    {
        using var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U");

        Assert.NotNull(claim);
        Assert.True(CourseActivity.CourseIsRenamingAFolder(Folder, "ICS3U"));
        Assert.True(CourseActivity.CourseIsRenamingAFolder(Folder + Path.DirectorySeparatorChar, "ICS3U"), "one folder however it is spelled");
        Assert.False(CourseActivity.CourseIsRenamingAFolder(Folder, "ICS4U"), "another code");
        Assert.False(CourseActivity.CourseIsRenamingAFolder(OtherFolder, "ICS3U"), "another working folder");
        Assert.False(CourseActivity.FolderRenameIsSwapping(Folder, "ICS3U"), "still planning");

        Assert.True(CourseActivity.FolderRenameSwapBegins(claim!));

        Assert.True(CourseActivity.FolderRenameIsSwapping(Folder, "ICS3U"));
        Assert.False(CourseActivity.FolderRenameIsSwapping(Folder, "ICS4U"));
    }

    // 2. One at a time per course.

    [Fact]
    public void ASecondClaimOnAClaimedCourseIsRefusedAndAnotherCoursesIsTaken()
    {
        using var first = CourseActivity.BeginFolderRename(Folder, "ICS3U");

        Assert.Null(CourseActivity.BeginFolderRename(Folder, "ICS3U"));
        using var other = CourseActivity.BeginFolderRename(Folder, "ICS4U");
        Assert.NotNull(other);
        using var elsewhere = CourseActivity.BeginFolderRename(OtherFolder, "ICS3U");
        Assert.NotNull(elsewhere);
    }

    [Fact]
    public void AnEndedClaimNeverBeginsItsSwap()
    {
        var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;
        claim.Dispose();
        claim.Dispose();

        Assert.False(CourseActivity.FolderRenameSwapBegins(claim));
        NothingIsClaimed();
    }

    // 3. Given back on every ending.

    [Fact]
    public async Task AWholeRenameGivesTheClaimBack()
    {
        bool heldDuring = false;
        var outcome = await SpecialFolderRenamer.RenameHoldingTheCourse(Folder, "ICS3U", claim =>
        {
            heldDuring = CourseActivity.CourseIsRenamingAFolder(Folder, "ICS3U");
            return Task.FromResult(RenameAsTheSheetDoes(claim));
        });

        Assert.True(heldDuring);
        Assert.Equal(2, outcome.FoldersMoved);
        NothingIsClaimed();
    }

    [Fact]
    public async Task ARefusedRenameGivesTheClaimBack()
    {
        Directory.CreateDirectory(Path.Combine(CourseFolder, "section2", "Assessments"));

        await Assert.ThrowsAsync<SpecialFolderRenamer.RenameException>(() =>
            SpecialFolderRenamer.RenameHoldingTheCourse(Folder, "ICS3U", claim => Task.FromResult(RenameAsTheSheetDoes(claim))));

        NothingIsClaimed();
    }

    [Fact]
    public async Task ARenameLeftPartWayGivesTheClaimBack()
    {
        // Section 1's index will not take its relink, and no page can be put
        // back: the door's step stops part way.
        File.SetAttributes(Path.Combine(CourseFolder, "section1", "index.md"), FileAttributes.ReadOnly);

        var refused = await Assert.ThrowsAsync<SpecialFolderRenamer.RenameException>(() =>
            SpecialFolderRenamer.RenameHoldingTheCourse(Folder, "ICS3U", claim =>
                Task.FromResult(RenameAsTheSheetDoes(claim, new UndoSeams { PutBackFailsAt = _ => true }))));

        Assert.DoesNotContain("nothing was changed", refused.Message);
        NothingIsClaimed();
    }

    [Fact]
    public async Task ARenameCancelledBeforeItsSwapChangesNothingAndGivesTheClaimBack()
    {
        SortedDictionary<string, string?> before = Tree();

        var refused = await Assert.ThrowsAsync<SpecialFolderRenamer.RenameException>(() =>
            SpecialFolderRenamer.RenameHoldingTheCourse(Folder, "ICS3U", claim =>
            {
                // The caller ends it before the swap (Cancel, 20a's).
                claim.Dispose();
                return Task.FromResult(RenameAsTheSheetDoes(claim));
            }));

        Assert.Equal(SpecialFolderRenamer.NothingWasChanged("Tasks", new OperationCanceledException().Message), refused.Message);
        Assert.Equal(before, Tree());
        NothingIsClaimed();
    }

    [Fact]
    public async Task AnUnexpectedExceptionGivesTheClaimBack()
    {
        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            SpecialFolderRenamer.RenameHoldingTheCourse(Folder, "ICS3U", _ => throw new InvalidOperationException("planning bug")));

        NothingIsClaimed();
    }

    // 4. Refused at its click while the course is claimed.

    [Fact]
    public async Task ARenameOfAClaimedCourseIsRefusedAtItsClickWithTheContractsSentence()
    {
        using var first = CourseActivity.BeginFolderRename(Folder, "ICS3U");
        SortedDictionary<string, string?> before = Tree();
        bool ran = false;

        var refused = await Assert.ThrowsAsync<SpecialFolderRenamer.RenameException>(() =>
            SpecialFolderRenamer.RenameHoldingTheCourse(Folder, "ICS3U", claim =>
            {
                ran = true;
                return Task.FromResult(RenameAsTheSheetDoes(claim));
            }));

        Assert.Equal(Wording("renameFolderUnderWay").Replace("{course}", "ICS3U"), refused.Message);
        Assert.False(ran, "no plan, no step");
        Assert.Equal(before, Tree());
        first!.Dispose();
        NothingIsClaimed();
    }

    [Fact]
    public void TheUnderWaySentenceIsTheContractsOwnByKey()
    {
        Assert.Equal(Wording("renameFolderUnderWay"), SpecialNames.RenameFolderUnderWay);
        Assert.Equal(Wording("renameFolderUnderWay").Replace("{course}", "MPM2D"), CourseActivity.FolderRenameIsUnderWay("MPM2D"));
    }

    // 5. A whole-course restore holding the course refuses the swap.

    [Fact]
    public async Task ARestoreHoldingTheCourseRefusesTheSwapAndNothingIsWritten()
    {
        SortedDictionary<string, string?> before = Tree();
        using var restore = CourseActivity.BeginRestore(Folder, "ICS3U");
        bool swapAnswer = true;

        var refused = await Assert.ThrowsAsync<SpecialFolderRenamer.RenameException>(() =>
            SpecialFolderRenamer.RenameHoldingTheCourse(Folder, "ICS3U", claim =>
            {
                swapAnswer = CourseActivity.RenameSwapBegins(claim);
                return Task.FromResult(RenameAsTheSheetDoes(claim));
            }));

        Assert.False(swapAnswer, "the swap question answers false while a restore holds the course");
        Assert.Equal(SpecialFolderRenamer.NothingWasChanged("Tasks", new OperationCanceledException().Message), refused.Message);
        Assert.Equal(before, Tree());
        Assert.False(File.Exists(SpecialFolderRenamer.RenameRecordPath(CourseFolder)), "nothing started, nothing recorded");
        NothingIsClaimed();
    }

    [Fact]
    public void ARestoreOfAnotherCourseLeavesTheSwapFree()
    {
        using var restore = CourseActivity.BeginRestore(Folder, "ICS4U");
        using var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;

        Assert.True(CourseActivity.RenameSwapBegins(claim));
    }

    // 6. RestoreWholeCourse holds the restore claim for its run.

    [Fact]
    public void RestoreWholeCourseHoldsTheCourseForItsRunAndGivesItBackWhenItThrows()
    {
        string coursesDirectory = Workspace.CoursesDirectory(Folder);
        bool heldDuring = false;
        CourseRestorer.WhileRestoringTheWholeCourse = () => heldDuring = CourseActivity.CourseIsBeingRestored(Folder, "ICS3U");
        var missing = new BackupItem("ICS3U", DateTime.Now, Path.Combine(_root, "no such backup.zip"));

        Assert.ThrowsAny<Exception>(() => CourseRestorer.RestoreWholeCourse(missing, null, coursesDirectory));

        Assert.True(heldDuring, "held while it ran");
        Assert.False(CourseActivity.CourseIsBeingRestored(Folder, "ICS3U"), "given back when it threw");
    }
}
