using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8-13 (the mac's U4a, <c>CourseSettingsView.createFoldersOnDisk</c>
/// and <c>FolderScaffold.planPages</c>): Add folder is ONE step, made by
/// <c>sheet</c>, held by the course: one <c>createTree</c> per folder made
/// (the folder and its two scaffold pages), the highest missing folder of its
/// path the tree's root, all or none. The folder list's own change is Save's.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class UndoAddFolderStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-add-folder-");
    private const string Created = "2026-09-08T07:00:00.000-0400";

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string CourseFolder => Path.Combine(Folder, "courses", "ICS3U");

    // ---- Initializer ---------------------------------------------------------------

    public UndoAddFolderStepTests()
    {
        Directory.CreateDirectory(Path.Combine(CourseFolder, "section1"));
        Directory.CreateDirectory(Path.Combine(CourseFolder, "section2"));
        File.WriteAllText(Path.Combine(Folder, Workspace.MarkerLauncher), "");
    }

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static string Template() => "---\ntitle: _DUPLICATE ME\n---\nA page to copy.\n";

    private FolderScaffold.Outcome Add(string name, FolderScope scope, UndoSeams? seams = null)
    {
        var list = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null);
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, seams, trail: list.Trail);
        return SpecialFolderRenamer.CreateFoldersOnDisk(name, scope, CourseFolder, new[] { 1, 2 }, Template(), null, Created, list, door);
    }

    private List<JsonObject> AppliedSteps()
    {
        var steps = new List<JsonObject>();
        foreach (JsonObject begin in WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder)) steps.Add(begin["step"]!.AsObject());
        return steps;
    }

    private static List<JsonObject> Ops(JsonObject step)
    {
        var ops = new List<JsonObject>();
        foreach (JsonNode? op in step["ops"]!.AsArray()) ops.Add(op!.AsObject());
        return ops;
    }

    private static string ListingText(JsonObject op, string listFolder)
    {
        string sha = (string)op["listingSha"]!;
        byte[]? bytes = new UndoForThisProcess(listFolder, UndoMode.Shadow, null).Journal.Blob(sha);
        Assert.NotNull(bytes);
        return Encoding.UTF8.GetString(bytes!);
    }

    [Fact]
    public void APerSectionFolderInTwoSectionsIsOneStepOfTwoTrees()
    {
        var outcome = Add("Labs", FolderScope.PerSection);

        Assert.Equal(new FolderScaffold.Outcome(2, 2, 2), outcome);
        var steps = AppliedSteps();
        Assert.Single(steps);
        Assert.Equal("addFolder", (string)steps[0]["action"]!["key"]!);
        Assert.Equal("sheet", (string)steps[0]["madeBy"]!);
        Assert.Equal("course", (string)steps[0]["holds"]!);
        var ops = Ops(steps[0]);
        Assert.Equal(2, ops.Count);
        Assert.All(ops, op => Assert.Equal("createTree", (string)op["kind"]!));
        Assert.Equal("courses/ICS3U/section1/Labs", (string)ops[0]["path"]!);
        Assert.Equal("courses/ICS3U/section2/Labs", (string)ops[1]["path"]!);
        foreach (int section in new[] { 1, 2 })
        {
            Assert.True(File.Exists(Path.Combine(CourseFolder, $"section{section}", "Labs", "index.md")));
            Assert.True(File.Exists(Path.Combine(CourseFolder, $"section{section}", "Labs", FolderScaffold.TemplateFileName)));
        }
    }

    [Fact]
    public void EveryListedFileIsOneOfTheTreesBlobs()
    {
        Add("Labs", FolderScope.Shared);

        JsonObject op = Ops(AppliedSteps()[0])[0];
        var named = new List<string>();
        foreach (JsonNode? blob in op["blobs"]!.AsArray()) named.Add((string)blob!);
        Assert.Contains((string)op["listingSha"]!, named);
        string listing = ListingText(op, ListFolder);
        foreach (string line in listing.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            string sha = line["file ".Length..line.IndexOf(' ', "file ".Length)];
            Assert.Contains(sha, named);
        }
        Assert.Contains("index.md\n", listing);
        Assert.Contains(FolderScaffold.TemplateFileName + "\n", listing);
    }

    [Fact]
    public void APathWhoseParentIsMissingIsOneTreeRootedAtTheHighestMissingFolder()
    {
        Directory.Delete(Path.Combine(CourseFolder, "section2"));

        var outcome = Add("Labs", FolderScope.PerSection);

        Assert.Equal(2, outcome.FoldersCreated);
        var ops = Ops(AppliedSteps()[0]);
        Assert.Equal(2, ops.Count);
        Assert.Equal("courses/ICS3U/section1/Labs", (string)ops[0]["path"]!);
        Assert.Equal("courses/ICS3U/section2", (string)ops[1]["path"]!);
        string listing = ListingText(ops[1], ListFolder);
        Assert.StartsWith("folder Labs\n", listing);
        Assert.Contains(" Labs/index.md\n", listing);
        Assert.True(File.Exists(Path.Combine(CourseFolder, "section2", "Labs", "index.md")));
    }

    [Fact]
    public void APageThatCannotBeWrittenChangesNothing()
    {
        // The second section's tree fails as it is staged, as a full disk
        // does: neither section's folder is made, and no step is applied.
        var outcome = Add("Labs", FolderScope.PerSection, new UndoSeams { StagingWriteFailsAt = index => index == 1 });

        Assert.Equal(new FolderScaffold.Outcome(), outcome);
        Assert.False(Directory.Exists(Path.Combine(CourseFolder, "section1", "Labs")));
        Assert.False(Directory.Exists(Path.Combine(CourseFolder, "section2", "Labs")));
        Assert.Empty(AppliedSteps());
    }

    [Fact]
    public void TheFolderCreatedTrailLineSaysWhatItSaysToday()
    {
        var outcome = Add("Labs", FolderScope.Shared);

        Assert.Equal(new FolderScaffold.Outcome(1, 1, 1), outcome);
        Assert.Equal("created the folder Labs in ICS3U (shared_folders), with its index page and a page to duplicate",
            FolderScaffold.FolderCreatedTrailLine("Labs", "ICS3U", FolderScope.Shared, outcome));
    }

    [Fact]
    public void ReAddingAFolderThatIsThereMakesNoStep()
    {
        Directory.CreateDirectory(Path.Combine(CourseFolder, "Labs"));

        Assert.Equal(new FolderScaffold.Outcome(), Add("Labs", FolderScope.Shared));
        Assert.Empty(AppliedSteps());
    }
}
