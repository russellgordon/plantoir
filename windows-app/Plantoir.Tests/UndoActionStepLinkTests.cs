using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8b-21a6 (the mac's U4b3 door-6, <c>JournaledStep</c>): an action step
/// that moves a link (<see cref="UndoActionStep.MoveLink"/>) hands the place
/// it leaves over. The step reads that place as free (no file, no text) until
/// it plans a write there; it plans such a write as a NEW file at that place,
/// never through the leaving link; it reads and writes the link's NEW place
/// (same folder) as the file the link leads to, even where the step removes
/// the page the link moves over; and it makes its ops, recorded or not, so
/// each place is left before it is filled (<see cref="UndoOp.PlaceLeftBy"/>,
/// <see cref="UndoOp.PlaceFilledBy"/>, <see cref="UndoOp.HandsOverAsAMove"/>).
/// The shape is Insert Class's at a linked later class (W8b piece 22): Day 4
/// is renamed to Day 5, the link at Day 3 moves to Day 4 with its date
/// written into the file it leads to, and a new Day 3 is written. Each test
/// runs with the link's target as Windows writes it (backslashes) and as the
/// mac writes it (<c>../library/…</c>), which Windows does not open.
/// </summary>
public sealed class UndoActionStepLinkTests : IDisposable
{
    private const string Section = "courses/TST1O/section1";
    private const string LibraryPage = "courses/TST1O/library/Day 2.md";

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-step-link-");
    private readonly List<UndoTrailLine> _trail = [];

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");

    private static string Day(int number) => Section + "/Unit 1, Day " + number + ".md";

    private string Full(string relative) => UndoDoor.FullPath(Folder, relative);

    private void Write(string relative, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(relative))!);
        File.WriteAllText(Full(relative), text);
    }

    /// <summary>Day 3 a link to the library's Day 2 (its target as given), Day 4 a plain page.</summary>
    private void ACourse(string target)
    {
        Directory.CreateDirectory(Path.Combine(Folder, "courses", "TST1O"));
        File.WriteAllText(Path.Combine(Folder, Plantoir.Core.Models.Workspace.MarkerLauncher), "");
        Write("courses/TST1O/course_config.json", "{\"course_code\":\"TST1O\"}");
        Write(LibraryPage, "Two.\n");
        Write(Day(4), "Four.\n");
        File.CreateSymbolicLink(Full(Day(3)), target);
    }

    private UndoForThisProcess List() => new(ListFolder, UndoMode.Shadow, _trail.Add);

    private UndoActionStep Step(UndoForThisProcess list, string? workingFolder) =>
        new(new UndoStepMaker("sheet", "insertClass"), workingFolder, "TST1O", 1, undo: list);

    /// <summary>Every entry under the working folder but courses/.internal: a link by the target it holds, a file by its bytes, a folder by null.</summary>
    private SortedDictionary<string, string?> Tree()
    {
        var tree = new SortedDictionary<string, string?>(StringComparer.Ordinal);
        foreach (string entry in Directory.EnumerateFileSystemEntries(Folder, "*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(Folder, entry).Replace('\\', '/');
            if (UndoOp.PartInside("courses/.internal", relative) is not null) continue;
            if (UndoLinks.Look(entry) == UndoLinks.What.Link) tree[relative] = "link " + new FileInfo(entry).LinkTarget;
            else tree[relative] = Directory.Exists(entry) ? null : Convert.ToBase64String(File.ReadAllBytes(entry));
        }
        return tree;
    }

    private List<JsonObject> Begins()
    {
        var begins = new List<JsonObject>();
        if (!Directory.Exists(ListFolder)) return begins;
        foreach (string segment in Directory.EnumerateFiles(ListFolder, "journal-*.jsonl").Order(StringComparer.Ordinal))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && (string?)read["event"] == "begin") begins.Add(read);
            }
        }
        return begins;
    }

    /// <summary>Each op's place (a move's as "from -> to"), one entry for a run of ops at the same place.</summary>
    private static List<string> PlacesInOrder(JsonArray ops)
    {
        var places = new List<string>();
        foreach (JsonNode? op in ops)
        {
            string place = (string?)op!["path"] ?? (string)op["from"]! + " -> " + (string)op["to"]!;
            if (places.Count == 0 || places[^1] != place) places.Add(place);
        }
        return places;
    }

    /// <summary>
    /// Insert Class's plan at a linked Day 3, highest first: Day 4 renamed to
    /// Day 5 (written there, removed here), the link moved from Day 3 to Day 4
    /// and its date written at Day 4, then the new Day 3. What the step reads
    /// on the way is checked as it goes.
    /// </summary>
    private static void PlanInsertClassAtALinkedDay3(UndoActionStep step, Func<string, string> full)
    {
        step.Write(full(Day(5)), "Four.\n");
        step.Remove(full(Day(4)));
        step.MoveLink(full(Day(3)), full(Day(4)));
        // The place the link leaves is free: no file, no text.
        Assert.False(step.Exists(full(Day(3))));
        Assert.Null(step.ReadTextIfAny(full(Day(3))));
        Assert.Throws<FileNotFoundException>(() => step.ReadText(full(Day(3))));
        // The link's new place is the file it leads to, though the step removes Day 4.
        Assert.True(step.Exists(full(Day(4))));
        Assert.Equal("Two.\n", step.ReadText(full(Day(4))));
        Assert.Equal("Two.\n", step.ReadTextIfAny(full(Day(4))));
        step.Write(full(Day(4)), "Two, dated.\n");
        Assert.Equal("Two, dated.\n", step.ReadText(full(Day(4))));
        step.Write(full(Day(3)), "New.\n");
        Assert.False(step.WasThereWhenPlanned(full(Day(3))));
        Assert.True(step.Exists(full(Day(3))));
        Assert.Equal("New.\n", step.ReadText(full(Day(3))));
    }

    private void AssertTheEndTree(string target)
    {
        Assert.Equal(UndoLinks.What.File, UndoLinks.Look(Full(Day(3))));
        Assert.Equal("New.\n", File.ReadAllText(Full(Day(3))));
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(Full(Day(4))));
        Assert.Equal(target, new FileInfo(Full(Day(4))).LinkTarget);
        Assert.Equal("Two, dated.\n", File.ReadAllText(Full(LibraryPage)));
        Assert.Equal("Four.\n", File.ReadAllText(Full(Day(5))));
    }

    [SymbolicLinkTheory]
    [InlineData("..\\library\\Day 2.md")]
    [InlineData("../library/Day 2.md")]
    public void ALinkMovedOverARemovedPageHandsItsPlaceToANewPageInOneStepUndoneAndRedoneExactly(string target)
    {
        ACourse(target);
        SortedDictionary<string, string?> before = Tree();
        UndoForThisProcess list = List();
        UndoActionStep step = Step(list, Folder);

        PlanInsertClassAtALinkedDay3(step, Full);
        step.Make();

        AssertTheEndTree(target);
        JsonObject made = Assert.Single(Begins())["step"]!.AsObject();
        JsonArray ops = made["ops"]!.AsArray();
        // Each place left before it is filled: Day 4's page removed, then the
        // link moved onto it, then the new page where the link was.
        Assert.Equal([LibraryPage, Day(4), Day(3) + " -> " + Day(4), Day(3), Day(5)], PlacesInOrder(ops));
        JsonObject newPage = ops.Single(op => (string?)op!["path"] == Day(3))!.AsObject();
        Assert.Equal("writeFile", (string?)newPage["kind"]);
        Assert.Null(newPage["beforeSha"]);
        Assert.Equal(UndoCheck.Sha(Encoding.UTF8.GetBytes("New.\n")), (string?)newPage["afterSha"]);
        Assert.Equal(UndoLinkMoveTests.ShaOfTarget(target), (string?)ops.Single(op => (string?)op!["kind"] == "move")!["linkSha"]);
        Assert.Empty(_trail);
        SortedDictionary<string, string?> after = Tree();

        Assert.Equal(UndoOutcomeKind.Undone, list.Door().Undo().Kind);
        Assert.Equal(before, Tree());
        Assert.Equal(UndoOutcomeKind.Redone, list.Door().Redo().Kind);
        Assert.Equal(after, Tree());
    }

    [SymbolicLinkTheory]
    [InlineData("..\\library\\Day 2.md")]
    [InlineData("../library/Day 2.md")]
    public void UnrecordedTheSameStepIsMadeInHandingOverOrderToTheSameEndTree(string target)
    {
        ACourse(target);
        UndoActionStep recorded = Step(List(), Folder);
        PlanInsertClassAtALinkedDay3(recorded, Full);
        recorded.Make();
        SortedDictionary<string, string?> recordedTree = Tree();
        Directory.Delete(Folder, recursive: true);
        ACourse(target);
        _trail.Clear();
        int beginsBefore = Begins().Count;

        // No working folder: the list cannot take the step, and with the
        // switch off it is made plainly, all or none.
        UndoActionStep plain = Step(List(), null);
        PlanInsertClassAtALinkedDay3(plain, Full);
        plain.Make();

        AssertTheEndTree(target);
        Assert.Equal(recordedTree, Tree());
        Assert.Equal(beginsBefore, Begins().Count);
        Assert.Single(_trail);
    }

    /// <summary>A step with no handed-over place keeps its order: the folder's move, then the pages in the one page order.</summary>
    [Fact]
    public void AStepWithNoHandedOverPlaceKeepsItsOrder()
    {
        Directory.CreateDirectory(Path.Combine(Folder, "courses", "TST1O"));
        File.WriteAllText(Path.Combine(Folder, Plantoir.Core.Models.Workspace.MarkerLauncher), "");
        Write("courses/TST1O/media/a.md", "A\n");
        Write("courses/TST1O/media/sub/b.md", "B\n");
        UndoActionStep step = Step(List(), Folder);

        step.MoveFolder(Full("courses/TST1O/media"), Full("courses/TST1O/renamed"));
        step.Remove(Full("courses/TST1O/renamed/sub/b.md"));
        step.Write(Full("courses/TST1O/renamed/c.md"), "C\n");
        step.Make();

        JsonArray ops = Assert.Single(Begins())["step"]!["ops"]!.AsArray();
        Assert.Equal(["courses/TST1O/media -> courses/TST1O/renamed", "courses/TST1O/renamed/c.md", "courses/TST1O/renamed/sub/b.md"],
                     PlacesInOrder(ops));
    }

    /// <summary>A link moved to ANOTHER folder leads elsewhere from its new place: a write there is refused, cannotTellNow, before anything changes (the mac's <c>refusesAWrite</c>).</summary>
    [SymbolicLinkFact]
    public void AWriteAtALinkMovedToAnotherFolderIsRefusedAndNothingChanges()
    {
        ACourse("..\\library\\Day 2.md");
        UndoActionStep step = Step(List(), Folder);
        string elsewhere = "courses/TST1O/section2/Unit 1, Day 3.md";
        Directory.CreateDirectory(Path.GetDirectoryName(Full(elsewhere))!);
        SortedDictionary<string, string?> before = Tree();

        step.MoveLink(Full(Day(3)), Full(elsewhere));
        var refused = Assert.Throws<UndoStepRefusedException>(() => step.Write(Full(elsewhere), "Two, dated.\n"));

        Assert.Equal(UndoRefusalKind.CannotTellNow, refused.Refusal.Kind);
        Assert.Equal(before, Tree());
        Assert.Empty(Begins());
    }
}
