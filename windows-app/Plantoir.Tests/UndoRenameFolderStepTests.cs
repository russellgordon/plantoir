using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.Win32.SafeHandles;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8b-15b (the mac's U4b, <c>SpecialFolderRenamer.plan</c>, <c>apply</c>
/// and <c>CourseSettingsView.renameFolder</c>): Rename folder is ONE step,
/// key <c>renameFolder</c>, made by <c>sheet</c>, held by the course: one
/// <c>move</c> per place of the folder, then each relinked page named at its
/// place after the move, in the one page order, then one <c>editJSON</c> per
/// changed member of <c>course_config.json</c>. The page walk never goes
/// through a link; any other reparse point is walked as the folder it is.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class UndoRenameFolderStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-rename-folder-");
    private string? _syncRoot;

    /// <summary>The settings, spelled as no serializer spells them, so a second whole write after the step shows.</summary>
    private const string Settings =
        "{\"course_code\":\"ICS3U\",\"num_sections\" :   2,\"section_numbers\":[1,2],\"per_section_folders\":[\"All Classes\",\"Tasks\"],"
        + "\"shared_folders\":[\"Concepts\"],\"hidden\":[\"Tasks\"],\"expandable\":[\"Concepts\",\"Tasks\"]}";

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string CourseFolder => Path.Combine(Folder, "courses", "ICS3U");
    private string ConfigPath => Path.Combine(CourseFolder, "course_config.json");

    // ---- Initializer ---------------------------------------------------------------

    public UndoRenameFolderStepTests()
    {
        Directory.CreateDirectory(CourseFolder);
        File.WriteAllText(Path.Combine(Folder, Workspace.MarkerLauncher), "");
        File.WriteAllText(ConfigPath, Settings);
    }

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        if (_syncRoot is not null) UndoCloudPlaceholders.Unregister(_syncRoot);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private void Write(string relative, string text)
    {
        string full = Path.Combine(CourseFolder, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, text);
    }

    private string Read(string relative) => File.ReadAllText(Path.Combine(CourseFolder, relative.Replace('/', Path.DirectorySeparatorChar)));

    /// <summary>The mac's <c>renameCourse</c>: two sections, each with <c>Tasks</c>, a page in section 1's linking within it, and section 1's index linking into it.</summary>
    private void TheCourse()
    {
        Write("section1/Tasks/Quiz 1.md", "See [[Tasks/Quiz 2]].\n");
        Write("section1/index.md", "Start with [[Tasks/Quiz 1]].\n");
        Write("section2/Tasks/Quiz 2.md", "Quiz two.\n");
    }

    /// <summary>The list the last <see cref="Rename"/> made its step on, for an Undo and a Redo after it.</summary>
    private UndoForThisProcess? _list;

    private RenameOutcome Rename(bool finishing = false, UndoSeams? seams = null)
    {
        var list = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null);
        _list = list;
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, seams, trail: list.Trail);
        var configuration = CourseConfiguration.Load(ConfigPath);
        var settings = SpecialFolderRenamer.RenamingTheSettings(configuration, ConfigPath, "Tasks", "Assessments", FolderScope.PerSection, CourseFolder);
        return SpecialFolderRenamer.Rename("Tasks", "Assessments", FolderScope.PerSection, CourseFolder, new[] { 1, 2 },
                                           settings, finishing, list, door);
    }

    private List<JsonObject> AppliedSteps()
    {
        var steps = new List<JsonObject>();
        foreach (JsonObject begin in WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder)) steps.Add(begin["step"]!.AsObject());
        return steps;
    }

    /// <summary>Each op as its kind and the place it names: a path, or from and to.</summary>
    private static List<string> Ops(JsonObject step)
    {
        var ops = new List<string>();
        foreach (JsonNode? op in step["ops"]!.AsArray())
        {
            string kind = (string)op!["kind"]!;
            if (kind == UndoOp.Move) ops.Add(kind + " " + (string)op["from"]! + " -> " + (string)op["to"]!);
            else if (kind == UndoOp.EditJson) ops.Add(kind + " " + (string)op["path"]! + " " + op["keyPath"]!.ToJsonString());
            else ops.Add(kind + " " + (string)op["path"]!);
        }
        return ops;
    }

    /// <summary>Every folder and file under the working folder, with its bytes: the teacher's tree, not the door's own <c>courses/.internal</c>.</summary>
    private SortedDictionary<string, string?> Tree()
    {
        var tree = new SortedDictionary<string, string?>(StringComparer.Ordinal);
        foreach (string entry in Directory.EnumerateFileSystemEntries(Folder, "*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(Folder, entry).Replace('\\', '/');
            if (UndoOp.PartInside("courses/.internal", relative) is not null) continue;
            // A link as itself, by the target it holds, never read through.
            if (UndoLinks.Look(entry) == UndoLinks.What.Link)
            {
                FileSystemInfo link = File.GetAttributes(entry).HasFlag(FileAttributes.Directory) ? new DirectoryInfo(entry) : new FileInfo(entry);
                tree[relative] = "link " + (link.LinkTarget ?? "that cannot be read");
                continue;
            }
            tree[relative] = Directory.Exists(entry) ? null : Convert.ToBase64String(File.ReadAllBytes(entry));
        }
        return tree;
    }

    [Fact]
    public void APerSectionRenameIsOneStepOfItsMovesThenItsPagesThenItsMembersAndNoSecondWrite()
    {
        TheCourse();

        var outcome = Rename();

        Assert.Equal(2, outcome.FoldersMoved);
        Assert.Equal(2, outcome.PagesRelinked);
        List<JsonObject> steps = AppliedSteps();
        Assert.Single(steps);
        Assert.Equal("renameFolder", (string?)steps[0]["action"]!["key"]);
        Assert.Equal("sheet", ((string)steps[0]["madeBy"]!).Split(':')[0]);
        Assert.Equal(
            new[]
            {
                "move courses/ICS3U/section1/Tasks -> courses/ICS3U/section1/Assessments",
                "move courses/ICS3U/section2/Tasks -> courses/ICS3U/section2/Assessments",
                "writeFile courses/ICS3U/section1/Assessments/Quiz 1.md",
                "writeFile courses/ICS3U/section1/index.md",
                "editJSON courses/ICS3U/course_config.json [\"expandable\"]",
                "editJSON courses/ICS3U/course_config.json [\"hidden\"]",
                "editJSON courses/ICS3U/course_config.json [\"per_section_folders\"]",
            },
            Ops(steps[0]));
        Assert.Equal("See [[Assessments/Quiz 2]].\n", Read("section1/Assessments/Quiz 1.md"));
        Assert.Equal("Start with [[Assessments/Quiz 1]].\n", Read("section1/index.md"));
        Assert.False(Directory.Exists(Path.Combine(CourseFolder, "section2", "Tasks")));
        // Only the three members moved: every other member keeps its own
        // spelling, which a second whole write of the settings would re-spell.
        string settings = File.ReadAllText(ConfigPath);
        Assert.Contains("\"num_sections\" :   2,", settings);
        JsonNode written = JsonNode.Parse(settings)!;
        Assert.Equal("[\"All Classes\",\"Assessments\"]", written["per_section_folders"]!.ToJsonString());
        Assert.Equal("[\"Assessments\"]", written["hidden"]!.ToJsonString());
        Assert.Equal("[\"Concepts\",\"Assessments\"]", written["expandable"]!.ToJsonString());
    }

    [Fact]
    public void TheFinishingRunIsOneStepOfItsPagesInTheOnePageOrderThenItsMembersAndNoMove()
    {
        // An interrupted rename: the folders already moved, the settings and
        // the links still name the old folder. "_Intro" comes before "index"
        // in the one page order (lowercased, ordinal) and after it in a
        // case-blind sort, which uppercases.
        Write("section1/Assessments/Quiz 1.md", "Quiz one.\n");
        Write("section2/Assessments/Quiz 2.md", "Quiz two.\n");
        Write("section1/index.md", "Start with [[Tasks/Quiz 1]].\n");
        Write("section1/_Intro.md", "Begin at [[Tasks/Quiz 1]].\n");

        var outcome = Rename(finishing: true);

        Assert.Equal(0, outcome.FoldersMoved);
        Assert.Equal(2, outcome.PagesRelinked);
        Assert.False(outcome.NothingWasThere);
        Assert.Equal(SpecialFolderRenamer.DoneMessage("Tasks", "Assessments", 2), outcome.Message);
        List<JsonObject> steps = AppliedSteps();
        Assert.Single(steps);
        Assert.Equal(
            new[]
            {
                "writeFile courses/ICS3U/section1/_Intro.md",
                "writeFile courses/ICS3U/section1/index.md",
                "editJSON courses/ICS3U/course_config.json [\"expandable\"]",
                "editJSON courses/ICS3U/course_config.json [\"hidden\"]",
                "editJSON courses/ICS3U/course_config.json [\"per_section_folders\"]",
            },
            Ops(steps[0]));
        Assert.Equal("Begin at [[Assessments/Quiz 1]].\n", Read("section1/_Intro.md"));
    }

    [Fact]
    public void AStepRefusedAtTheMakeChangesNothing()
    {
        TheCourse();
        SortedDictionary<string, string?> before = Tree();

        // The second staged file fails as it is written, as a full disk does.
        var refused = Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => Rename(seams: new UndoSeams { StagingWriteFailsAt = index => index == 1 }));

        Assert.False(string.IsNullOrWhiteSpace(refused.Message));
        Assert.Equal(before, Tree());
        Assert.Empty(AppliedSteps());
    }

    // ---- A place of the folder that is a link (#899 W8b-21) --------------------

    private const string LinkFrom = "courses/ICS3U/section2/Tasks";
    private const string LinkTo = "courses/ICS3U/section2/Assessments";

    /// <summary>Section 1's real Tasks folder and its index, both linking into it; section 2 holds only what the test lays at Tasks.</summary>
    private void TheCourseWithSectionTwosTasksToLay()
    {
        Write("section1/Tasks/Quiz 1.md", "See [[Tasks/Quiz 2]].\n");
        Write("section1/index.md", "Start with [[Tasks/Quiz 1]].\n");
        Directory.CreateDirectory(Path.Combine(CourseFolder, "section2"));
    }

    private string SectionTwosTasks => Path.Combine(CourseFolder, "section2", "Tasks");
    private string SectionTwosAssessments => Path.Combine(CourseFolder, "section2", "Assessments");

    /// <summary>A library the link leads to: a page naming the old folder (never relinked through the link) and one in a folder.</summary>
    private static string ALibrary(string library)
    {
        Directory.CreateDirectory(Path.Combine(library, "pictures"));
        File.WriteAllText(Path.Combine(library, "Quiz 2.md"), "See [[Tasks/Quiz 1]].\n");
        File.WriteAllText(Path.Combine(library, "pictures", "b.md"), "B\n");
        return library;
    }

    /// <summary>
    /// The one step a rename makes when section 2's Tasks is a link: section
    /// 1's folder moved by its listing, then the LINK moved by its target as
    /// stored (<c>linkSha</c>, no <c>listingSha</c>, from named as the link's
    /// own place), then section 1's two pages, then the three members.
    /// </summary>
    private void TheStepMovesTheLinkAsItself(string target)
    {
        JsonObject step = Assert.Single(AppliedSteps());
        Assert.Equal(
            new[]
            {
                "move courses/ICS3U/section1/Tasks -> courses/ICS3U/section1/Assessments",
                "move " + LinkFrom + " -> " + LinkTo,
                "writeFile courses/ICS3U/section1/Assessments/Quiz 1.md",
                "writeFile courses/ICS3U/section1/index.md",
                "editJSON courses/ICS3U/course_config.json [\"expandable\"]",
                "editJSON courses/ICS3U/course_config.json [\"hidden\"]",
                "editJSON courses/ICS3U/course_config.json [\"per_section_folders\"]",
            },
            Ops(step));
        JsonObject linkMove = step["ops"]!.AsArray()[1]!.AsObject();
        Assert.Equal(UndoLinkMoveTests.ShaOfTarget(target), (string?)linkMove["linkSha"]);
        Assert.Null(linkMove["listingSha"]);
        Assert.Null(linkMove["blobs"]);
        Assert.NotNull(step["ops"]!.AsArray()[0]!["listingSha"]);
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(SectionTwosTasks));
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(SectionTwosAssessments));
        Assert.Equal(target, new DirectoryInfo(SectionTwosAssessments).LinkTarget);
    }

    /// <summary>
    /// A place of the folder that is a JUNCTION (to a folder inside the
    /// course) is renamed by moving the junction itself, one op of the one
    /// step; what it leads to keeps its listing and every file's identity,
    /// through the rename, its Undo and its Redo.
    /// </summary>
    [Fact]
    public void AJunctionPlaceIsRenamedAsItselfUndoneAndRedoneWhatItLeadsToUntouched()
    {
        TheCourseWithSectionTwosTasksToLay();
        string library = ALibrary(Path.Combine(CourseFolder, "library-of-tasks"));
        File.WriteAllText(Path.Combine(library, "Quiz 2.md"), "Quiz two.\n");
        UndoKindsForTheCases.MakeAJunction(SectionTwosTasks, library);
        string target = new DirectoryInfo(SectionTwosTasks).LinkTarget!;
        string untouched = UndoLinkMoveTests.Untouched(library);

        var outcome = Rename();

        Assert.Equal(2, outcome.FoldersMoved);
        Assert.Equal(2, outcome.PagesRelinked);
        TheStepMovesTheLinkAsItself(target);
        Assert.Equal(untouched, UndoLinkMoveTests.Untouched(library));
        Assert.Equal(UndoOutcomeKind.Undone, _list!.Door().Undo().Kind);
        Assert.Equal(target, new DirectoryInfo(SectionTwosTasks).LinkTarget);
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(SectionTwosAssessments));
        Assert.Equal(untouched, UndoLinkMoveTests.Untouched(library));
        Assert.Equal(UndoOutcomeKind.Redone, _list.Door().Redo().Kind);
        Assert.Equal(target, new DirectoryInfo(SectionTwosAssessments).LinkTarget);
        Assert.Equal(untouched, UndoLinkMoveTests.Untouched(library));
    }

    /// <summary>A folder symbolic link holding a RELATIVE target (<c>..\library-of-tasks</c>): renamed as itself, the target as written, what it leads to untouched.</summary>
    [SymbolicLinkFact]
    public void ARelativeSymbolicLinkPlaceIsRenamedAsItselfItsTargetAsWritten()
    {
        TheCourseWithSectionTwosTasksToLay();
        string library = ALibrary(Path.Combine(CourseFolder, "library-of-tasks"));
        File.WriteAllText(Path.Combine(library, "Quiz 2.md"), "Quiz two.\n");
        Directory.CreateSymbolicLink(SectionTwosTasks, "..\\library-of-tasks");
        string untouched = UndoLinkMoveTests.Untouched(library);

        var outcome = Rename();

        Assert.Equal(2, outcome.FoldersMoved);
        TheStepMovesTheLinkAsItself("..\\library-of-tasks");
        Assert.Equal(untouched, UndoLinkMoveTests.Untouched(library));
    }

    /// <summary>
    /// 15b's branch-only stop turned round: a symbolic link leading OUT of
    /// the working folder is renamed as itself. The page behind it names the
    /// old folder and is never relinked (the walk never goes through a link),
    /// and what it leads to is untouched.
    /// </summary>
    [SymbolicLinkFact]
    public void APlaceOfTheFolderThatIsALinkLeadingOutIsRenamedAsTheLinkAndThePageBehindItIsNotRelinked()
    {
        TheCourseWithSectionTwosTasksToLay();
        string library = ALibrary(Path.Combine(_root, "library"));
        Directory.CreateSymbolicLink(SectionTwosTasks, library);
        string untouched = UndoLinkMoveTests.Untouched(library);

        var outcome = Rename();

        Assert.Equal(2, outcome.FoldersMoved);
        Assert.Equal(2, outcome.PagesRelinked);
        TheStepMovesTheLinkAsItself(library);
        Assert.Equal("See [[Tasks/Quiz 1]].\n", File.ReadAllText(Path.Combine(library, "Quiz 2.md")));
        Assert.Equal(untouched, UndoLinkMoveTests.Untouched(library));
    }

    /// <summary>The same with a junction leading out of the working folder (runs where no symbolic link can be made).</summary>
    [Fact]
    public void AJunctionLeadingOutIsRenamedAsItselfAndThePageBehindItIsNotRelinked()
    {
        TheCourseWithSectionTwosTasksToLay();
        string library = ALibrary(Path.Combine(_root, "library"));
        UndoKindsForTheCases.MakeAJunction(SectionTwosTasks, library);
        string target = new DirectoryInfo(SectionTwosTasks).LinkTarget!;
        string untouched = UndoLinkMoveTests.Untouched(library);

        var outcome = Rename();

        Assert.Equal(2, outcome.PagesRelinked);
        TheStepMovesTheLinkAsItself(target);
        Assert.Equal("See [[Tasks/Quiz 1]].\n", File.ReadAllText(Path.Combine(library, "Quiz 2.md")));
        Assert.Equal(untouched, UndoLinkMoveTests.Untouched(library));
    }

    /// <summary>
    /// A link to a folder that leads NOWHERE (its folder taken away) is still
    /// a link to a folder by its own attributes, and is renamed as itself:
    /// nothing is made where it points.
    /// </summary>
    [Fact]
    public void AJunctionLeadingNowhereIsRenamedAsItselfAndNothingIsMadeWhereItPoints()
    {
        TheCourseWithSectionTwosTasksToLay();
        string gone = ALibrary(Path.Combine(_root, "gone"));
        UndoKindsForTheCases.MakeAJunction(SectionTwosTasks, gone);
        string target = new DirectoryInfo(SectionTwosTasks).LinkTarget!;
        Directory.Delete(gone, recursive: true);

        var outcome = Rename();

        Assert.Equal(2, outcome.FoldersMoved);
        TheStepMovesTheLinkAsItself(target);
        Assert.False(Directory.Exists(gone) || File.Exists(gone), "nothing is made where the link points");
        Assert.Equal(UndoOutcomeKind.Undone, _list!.Door().Undo().Kind);
        Assert.Equal(target, new DirectoryInfo(SectionTwosTasks).LinkTarget);
        Assert.False(Directory.Exists(gone) || File.Exists(gone), "nothing is made where the link points");
    }

    /// <summary>A link whose target cannot be read (WSL's own) refuses the rename <c>cannotTellNow</c>: nothing changed, nothing recorded.</summary>
    [ReparsePointFact]
    public void ALinkWhoseTargetCannotBeReadRefusesTheRenameCannotTellNowAndChangesNothing()
    {
        TheCourseWithSectionTwosTasksToLay();
        Assert.Null(UndoReparsePoints.Make(SectionTwosTasks, UndoReparsePoints.WslLink, UndoReparsePoints.WslLinkData("../library")));
        SortedDictionary<string, string?> before = Tree();

        var refused = Assert.Throws<SpecialFolderRenamer.RenameException>(() => Rename());

        Assert.Contains("Tasks", refused.Message);
        Assert.Equal(before, Tree());
        Assert.Empty(AppliedSteps());
        Assert.False(File.Exists(SpecialFolderRenamer.RenameRecordPath(CourseFolder)), "nothing started, nothing recorded");
    }

    /// <summary>
    /// A place of the folder that is a OneDrive-style placeholder (a reparse
    /// point that is NOT a name surrogate) is the teacher's own folder, not a
    /// link: moved whole, by its listing, never as a link (the one link test,
    /// <see cref="UndoLinks.Look"/>, never the bare reparse-point attribute).
    /// </summary>
    [CloudPlaceholderFact]
    public void APlaceThatIsAOneDriveStylePlaceholderIsMovedAsTheFolderItIs()
    {
        TheCourseWithSectionTwosTasksToLay();
        Write("section2/Tasks/Quiz 2.md", "Quiz two.\n");
        _syncRoot = Path.Combine(CourseFolder, "section2");
        Assert.Null(UndoCloudPlaceholders.Make(_syncRoot, SectionTwosTasks));
        Assert.True(File.GetAttributes(SectionTwosTasks).HasFlag(FileAttributes.ReparsePoint), "the placeholder carries a reparse point");

        var outcome = Rename();

        Assert.Equal(2, outcome.FoldersMoved);
        JsonObject step = Assert.Single(AppliedSteps());
        JsonObject move = step["ops"]!.AsArray()[1]!.AsObject();
        Assert.Equal(LinkFrom, (string?)move["from"]);
        Assert.NotNull(move["listingSha"]);
        Assert.Null(move["linkSha"]);
        Assert.Equal("Quiz two.\n", Read("section2/Assessments/Quiz 2.md"));
    }

    /// <summary>A link to something that is not a folder is skipped, as a file at that place is: left as it is, and section 1 alone is renamed.</summary>
    [SymbolicLinkFact]
    public void ALinkToAFileAtThePlaceIsSkippedAsAFileIs()
    {
        TheCourseWithSectionTwosTasksToLay();
        Write("Tasks list.md", "A list.\n");
        File.CreateSymbolicLink(SectionTwosTasks, "..\\Tasks list.md");

        var outcome = Rename();

        Assert.Equal(1, outcome.FoldersMoved);
        JsonObject step = Assert.Single(AppliedSteps());
        Assert.Contains("move courses/ICS3U/section1/Tasks -> courses/ICS3U/section1/Assessments", Ops(step));
        foreach (string op in Ops(step)) Assert.DoesNotContain("section2", op);
        Assert.Equal("..\\Tasks list.md", new FileInfo(SectionTwosTasks).LinkTarget);
        Assert.Equal("A list.\n", Read("Tasks list.md"));
    }

    [SymbolicLinkFact]
    public void ALinkInsideTheCourseIsNotWalked()
    {
        TheCourse();
        string outside = Path.Combine(_root, "outside");
        Directory.CreateDirectory(outside);
        File.WriteAllText(Path.Combine(outside, "Reading.md"), "Read [[Tasks/Quiz 1]].\n");
        Directory.CreateSymbolicLink(Path.Combine(CourseFolder, "Library"), outside);

        var outcome = Rename();

        Assert.Equal(2, outcome.PagesRelinked);
        Assert.Equal("Read [[Tasks/Quiz 1]].\n", File.ReadAllText(Path.Combine(outside, "Reading.md")));
        List<JsonObject> steps = AppliedSteps();
        Assert.Single(steps);
        foreach (string op in Ops(steps[0])) Assert.DoesNotContain("Library", op);
    }

    /// <summary>
    /// A OneDrive placeholder folder is a reparse point that is NOT a name
    /// surrogate (a cloud tag, <c>0x9000x01A</c>): it is walked as the folder
    /// it is, and a page in it is relinked. Made with the Cloud Files API
    /// under a sync root of the test's own, the folder converted to a
    /// placeholder, fully populated, so no provider is ever asked.
    /// </summary>
    [CloudPlaceholderFact]
    public void AOneDriveStylePlaceholderFolderIsWalkedAsTheFolderItIs()
    {
        TheCourse();
        _syncRoot = Path.Combine(CourseFolder, "Cloud");
        string notes = Path.Combine(_syncRoot, "Notes");
        Directory.CreateDirectory(notes);
        File.WriteAllText(Path.Combine(notes, "Week 1.md"), "Do [[Tasks/Quiz 1]].\n");
        Assert.Null(UndoCloudPlaceholders.Make(_syncRoot, notes));
        Assert.True(File.GetAttributes(notes).HasFlag(FileAttributes.ReparsePoint), "the placeholder carries a reparse point");
        Assert.Equal(UndoLinks.What.Folder, UndoLinks.Look(notes));

        var outcome = Rename();

        Assert.Equal(3, outcome.PagesRelinked);
        Assert.Equal("Do [[Assessments/Quiz 1]].\n", File.ReadAllText(Path.Combine(notes, "Week 1.md")));
        List<JsonObject> steps = AppliedSteps();
        Assert.Single(steps);
        Assert.Contains("writeFile courses/ICS3U/Cloud/Notes/Week 1.md", Ops(steps[0]));
    }
}

/// <summary>
/// A folder made a OneDrive-style placeholder through the Cloud Files API
/// (<c>cldapi.dll</c>): a sync root registered at a folder of the test's own,
/// population and hydration always full (so the filter never asks a
/// provider), and the folder converted in sync. The process is set to see
/// placeholders as they are (<c>PHCM_EXPOSE_PLACEHOLDERS</c>).
/// </summary>
internal static class UndoCloudPlaceholders
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SyncRegistration
    {
        public uint StructSize;
        public string ProviderName;
        public string ProviderVersion;
        public IntPtr SyncRootIdentity;
        public uint SyncRootIdentityLength;
        public IntPtr FileIdentity;
        public uint FileIdentityLength;
        public Guid ProviderId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SyncPolicies
    {
        public uint StructSize;
        public ushort HydrationPrimary;
        public ushort HydrationModifier;
        public ushort PopulationPrimary;
        public ushort PopulationModifier;
        public uint InSync;
        public uint HardLink;
        public uint PlaceholderManagement;
    }

    [DllImport("cldapi.dll", CharSet = CharSet.Unicode)]
    private static extern int CfRegisterSyncRoot(string syncRootPath, ref SyncRegistration registration, ref SyncPolicies policies, uint flags);

    [DllImport("cldapi.dll", CharSet = CharSet.Unicode)]
    private static extern int CfUnregisterSyncRoot(string syncRootPath);

    [DllImport("cldapi.dll")]
    private static extern int CfConvertToPlaceholder(SafeFileHandle file, byte[] identity, uint identityLength, uint flags, out long usn, IntPtr overlapped);

    [DllImport("cldapi.dll")]
    private static extern int CfRevertPlaceholder(SafeFileHandle file, uint flags, IntPtr overlapped);

    [DllImport("ntdll.dll")]
    private static extern sbyte RtlSetProcessPlaceholderCompatibilityMode(sbyte mode);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    private const uint GenericReadWrite = 0x80000000 | 0x40000000;
    private const uint ShareAll = 0x1 | 0x2 | 0x4;
    private const uint OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000;
    private const sbyte ExposePlaceholders = 2;
    private const ushort AlwaysFull = 3;
    private const uint MarkInSync = 0x1;

    private static readonly Lazy<string?> WhyNot = new(Probe);

    internal static string? CannotBeMade => WhyNot.Value;

    /// <summary>Registers <paramref name="syncRoot"/> and makes <paramref name="folder"/> inside it a placeholder; null when done, else why not.</summary>
    internal static string? Make(string syncRoot, string folder)
    {
        if (!OperatingSystem.IsWindows()) return "Windows only";
        try
        {
            RtlSetProcessPlaceholderCompatibilityMode(ExposePlaceholders);
            var registration = new SyncRegistration
            {
                StructSize = (uint)Marshal.SizeOf<SyncRegistration>(),
                ProviderName = "Plantoir test",
                ProviderVersion = "1.0",
                ProviderId = new Guid("6c1e0d3a-5b39-4b8e-9f43-2f1d7a1c0b15"),
            };
            var policies = new SyncPolicies
            {
                StructSize = (uint)Marshal.SizeOf<SyncPolicies>(),
                HydrationPrimary = AlwaysFull,
                PopulationPrimary = AlwaysFull,
            };
            int registered = CfRegisterSyncRoot(syncRoot, ref registration, ref policies, 0);
            if (registered < 0) return $"the Cloud Files API would not register a sync root here (0x{registered:X8})";
            using SafeFileHandle handle = CreateFileW(folder, GenericReadWrite, ShareAll, IntPtr.Zero, OpenExisting, BackupSemantics, IntPtr.Zero);
            if (handle.IsInvalid) return "the folder could not be opened to convert: " + new Win32Exception(Marshal.GetLastWin32Error()).Message;
            int converted = CfConvertToPlaceholder(handle, [1], 1, MarkInSync, out _, IntPtr.Zero);
            if (converted < 0) return $"the Cloud Files API would not make the folder a placeholder (0x{converted:X8})";
            if (!File.GetAttributes(folder).HasFlag(FileAttributes.ReparsePoint)) return "the placeholder shows no reparse point to this process";
            return null;
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException or IOException or UnauthorizedAccessException)
        {
            return "the Cloud Files API is not available: " + error.Message;
        }
    }

    /// <summary>Reverts every placeholder folder under the sync root and unregisters it, so the folder can be removed.</summary>
    internal static void Unregister(string syncRoot)
    {
        if (!OperatingSystem.IsWindows()) return;
        try
        {
            foreach (string folder in Directory.EnumerateDirectories(syncRoot, "*", SearchOption.AllDirectories))
            {
                using SafeFileHandle handle = CreateFileW(folder, GenericReadWrite, ShareAll, IntPtr.Zero, OpenExisting, BackupSemantics, IntPtr.Zero);
                if (!handle.IsInvalid) CfRevertPlaceholder(handle, 0, IntPtr.Zero);
            }
        }
        catch { }
        try { CfUnregisterSyncRoot(syncRoot); } catch { }
    }

    private static string? Probe()
    {
        string root = Path.Combine(Path.GetTempPath(), "plantoir-undo-cloud-probe-" + Guid.NewGuid().ToString("N"));
        string folder = Path.Combine(root, "inside");
        try
        {
            Directory.CreateDirectory(folder);
            if (Make(root, folder) is { } why) return why;
            File.WriteAllText(Path.Combine(folder, "probe.md"), "probe\n");
            if (Directory.GetFiles(folder).Length != 1) return "a placeholder folder made here cannot be listed";
            return null;
        }
        catch (Exception error)
        {
            return "a placeholder folder made here cannot hold a file: " + error.Message;
        }
        finally
        {
            Unregister(root);
            try { Directory.Delete(root, recursive: true); } catch { }
        }
    }
}

/// <summary>A fact that needs a OneDrive-style placeholder folder: SKIPPED, saying why, where this computer cannot make one.</summary>
public sealed class CloudPlaceholderFactAttribute : FactAttribute
{
    public CloudPlaceholderFactAttribute()
    {
        if (UndoCloudPlaceholders.CannotBeMade is { } why) Skip = why;
    }
}
