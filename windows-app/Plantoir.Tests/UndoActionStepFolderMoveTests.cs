using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8b-15a: an action step moves a folder through the door as ONE
/// <c>move</c> op <c>{from, to, listingSha}</c> (the mac's
/// <c>JournaledStep.moveFolder</c>, U4b), the listing taken when planned, and
/// every read or write it plans inside that folder named, read and judged at
/// the folder's NEW place (the mac's <c>placeOnDiskNow</c>). Ops: the folder
/// moves first, then the pages in the one page order, then the
/// <c>editJSON</c> members in the order planned. Unrecorded, the move is
/// made by the swap's own rename, never <c>Directory.Move</c>.
/// </summary>
public sealed class UndoActionStepFolderMoveTests : IDisposable
{
    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-step-folder-move-");
    private readonly List<UndoTrailLine> _trail = [];

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");

    private const string Media = "courses/TST1O/media";
    private const string Renamed = "courses/TST1O/renamed";
    private const string Notes = "courses/TST1O/notes";
    private const string Zeta = "courses/TST1O/zeta";
    private const string Config = "courses/TST1O/course_config.json";

    private string Full(string relative) => UndoDoor.FullPath(Folder, relative);

    private void Write(string relative, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(relative))!);
        File.WriteAllText(Full(relative), text);
    }

    private void ACourse()
    {
        Directory.CreateDirectory(Path.Combine(Folder, "courses", "TST1O"));
        File.WriteAllText(Path.Combine(Folder, Plantoir.Core.Models.Workspace.MarkerLauncher), "");
        Write(Config, "{\"course_code\":\"TST1O\",\"expandable\":[\"media\"]}");
        Write(Media + "/a.md", "A\n");
        Write(Media + "/sub/b.md", "B\n");
    }

    private UndoForThisProcess List(UndoMode mode = UndoMode.Shadow) => new(ListFolder, mode, _trail.Add);

    private UndoActionStep Step(UndoForThisProcess list) =>
        new(new UndoStepMaker("sheet", "renameFolder"), Folder, "TST1O", null, holds: "course", undo: list);

    /// <summary>
    /// Every folder and file under the working folder, by its path there, with
    /// its bytes (null for a folder): the teacher's tree, so not the working
    /// folder's identity the door keeps in <c>courses/.internal</c> once it
    /// has named a step there.
    /// </summary>
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

    private static (string Kind, string Place) KindAndPlace(JsonNode? op) =>
        ((string)op!["kind"]!, (string?)op["path"] ?? (string)op["from"]! + " -> " + (string)op["to"]!);

    [Fact]
    public void AFolderMoveAndAnEditInsideItAreOneStepNamedAtTheNewPlaceAndUndoneAndRedoneByteForByte()
    {
        ACourse();
        string listingWhenPlanned = UndoTreeReading.Read(Full(Media)).ListingSha!;
        SortedDictionary<string, string?> before = Tree();
        UndoForThisProcess list = List();
        UndoActionStep step = Step(list);

        step.MoveFolder(Full(Media), Full(Renamed));
        // Read through the step at the new place: what the old place holds.
        Assert.True(step.Exists(Full(Renamed + "/a.md")));
        Assert.Equal("A\n", step.ReadText(Full(Renamed + "/a.md")));
        step.Write(Full(Renamed + "/a.md"), "A, edited\n");
        step.Make();

        Assert.False(Directory.Exists(Full(Media)));
        Assert.Equal("A, edited\n", File.ReadAllText(Full(Renamed + "/a.md")));
        Assert.Equal("B\n", File.ReadAllText(Full(Renamed + "/sub/b.md")));
        JsonObject made = Assert.Single(Begins())["step"]!.AsObject();
        JsonArray ops = made["ops"]!.AsArray();
        Assert.Equal(2, ops.Count);
        Assert.Equal("move", (string?)ops[0]!["kind"]);
        Assert.Equal(Media, (string?)ops[0]!["from"]);
        Assert.Equal(Renamed, (string?)ops[0]!["to"]);
        Assert.Equal(listingWhenPlanned, (string?)ops[0]!["listingSha"]);
        Assert.Null(ops[0]!["blobs"]);
        Assert.Equal("writeFile", (string?)ops[1]!["kind"]);
        Assert.Equal(Renamed + "/a.md", (string?)ops[1]!["path"]);
        Assert.Equal(UndoCheck.Sha(Encoding.UTF8.GetBytes("A\n")), (string?)ops[1]!["beforeSha"]);
        Assert.Equal("2", (string?)made["action"]!["arguments"]!["pageCount"]);
        Assert.Empty(_trail);
        SortedDictionary<string, string?> after = Tree();

        Assert.Equal(UndoOutcomeKind.Undone, list.Door().Undo().Kind);
        Assert.Equal(before, Tree());
        Assert.Equal(UndoOutcomeKind.Redone, list.Door().Redo().Kind);
        Assert.Equal(after, Tree());
    }

    [Fact]
    public void TwoFoldersMoveFirstThenThePagesInTheOnePageOrderThenTheMembersAsPlanned()
    {
        ACourse();
        Write(Media + "/B.md", "Bee\n");
        Write(Notes + "/c.md", "C\n");
        UndoForThisProcess list = List();
        UndoActionStep step = Step(list);

        step.MoveFolder(Full(Media), Full(Renamed));
        step.MoveFolder(Full(Notes), Full(Zeta));
        // The course's settings planned first, and the pages in neither the
        // page order nor the order of the bytes as spelled.
        byte[] config = File.ReadAllBytes(Full(Config));
        UndoJson before = UndoJson.From(JsonDocument.Parse("[\"media\"]").RootElement)!;
        UndoJson after = UndoJson.From(JsonDocument.Parse("[\"renamed\"]").RootElement)!;
        var member = new UndoMemberChange(["expandable"], before, after);
        byte[] configAfter = UndoJsonMember.Moved(UndoLineOps.Read(member.Op(Config)), config, backward: false)!;
        step.EditJson(Full(Config), config, [member], configAfter);
        step.Write(Full(Zeta + "/c.md"), "C, edited\n");
        step.Write(Full(Renamed + "/B.md"), "Bee, edited\n");
        step.Write(Full(Renamed + "/a.md"), "A, edited\n");
        step.Make();

        JsonArray ops = Assert.Single(Begins())["step"]!["ops"]!.AsArray();
        var seen = new List<(string, string)>();
        foreach (JsonNode? op in ops) seen.Add(KindAndPlace(op));
        Assert.Equal(
            [
                ("move", Media + " -> " + Renamed),
                ("move", Notes + " -> " + Zeta),
                ("writeFile", Renamed + "/a.md"),
                ("writeFile", Renamed + "/B.md"),
                ("writeFile", Zeta + "/c.md"),
                ("editJSON", Config),
            ],
            seen);
        Assert.Equal(configAfter, File.ReadAllBytes(Full(Config)));
        Assert.Equal("C, edited\n", File.ReadAllText(Full(Zeta + "/c.md")));
    }

    /// <summary>
    /// The settings planned WHOLE (the fallback when their members cannot be
    /// moved one by one) keep the place they were planned in, after the
    /// pages: only the pages are put in the one page order (window A fixes,
    /// review 1 L4; the mac keeps the planned order).
    /// </summary>
    [Fact]
    public void ASettingsFilePlannedWholeKeepsItsPlannedPlaceAfterThePages()
    {
        ACourse();
        UndoForThisProcess list = List();
        UndoActionStep step = Step(list);

        step.MoveFolder(Full(Media), Full(Renamed));
        step.Write(Full(Renamed + "/sub/b.md"), "B, edited\n");
        step.Write(Full(Renamed + "/a.md"), "A, edited\n");
        byte[] config = File.ReadAllBytes(Full(Config));
        byte[] whole = Encoding.UTF8.GetBytes("{\"course_code\":\"TST1O\",\"expandable\":[\"renamed\"]}");
        step.EditJson(Full(Config), config, [], whole);
        step.Make();

        JsonArray ops = Assert.Single(Begins())["step"]!["ops"]!.AsArray();
        var seen = new List<(string, string)>();
        foreach (JsonNode? op in ops) seen.Add(KindAndPlace(op));
        Assert.Equal(
            [
                ("move", Media + " -> " + Renamed),
                ("writeFile", Renamed + "/a.md"),
                ("writeFile", Renamed + "/sub/b.md"),
                ("writeFile", Config),
            ],
            seen);
        Assert.Equal(whole, File.ReadAllBytes(Full(Config)));
    }

    [Fact]
    public void TheOnePageOrderIsTheLowercasedPathThenTheBytesAsSpelled()
    {
        var pages = new List<string> { "x/b.md", "x/C.md", "x/B.md", "x/a.md" };
        pages.Sort(UndoActionStep.ComparePageOrder);
        Assert.Equal(["x/a.md", "x/B.md", "x/b.md", "x/C.md"], pages);
    }

    [Fact]
    public void AFolderEditedByHandBetweenThePlanAndTheMakeRefusesTheStepAndNothingChanges()
    {
        ACourse();
        UndoActionStep step = Step(List());
        step.MoveFolder(Full(Media), Full(Renamed));
        step.Write(Full(Renamed + "/a.md"), "A, edited\n");
        // Another program adds a page to the folder after the plan.
        Write(Media + "/new.md", "New\n");
        SortedDictionary<string, string?> handEdited = Tree();

        var refused = Assert.Throws<UndoStepRefusedException>(step.Make);

        Assert.Equal(UndoRefusalKind.ChangedSince, refused.Refusal.Kind);
        Assert.Equal(handEdited, Tree());
    }

    [SymbolicLinkFact]
    public void AFolderThatIsALinkIsRefusedCannotTellNowAndNothingChanges()
    {
        ACourse();
        string library = Path.Combine(_root, "library");
        Directory.CreateDirectory(library);
        File.WriteAllText(Path.Combine(library, "l.md"), "L\n");
        Directory.CreateSymbolicLink(Full(Notes), library);
        SortedDictionary<string, string?> before = Tree();
        UndoActionStep step = Step(List());

        var refused = Assert.Throws<UndoStepRefusedException>(() => step.MoveFolder(Full(Notes), Full(Zeta)));

        Assert.Equal(UndoRefusalKind.CannotTellNow, refused.Refusal.Kind);
        Assert.Equal(before, Tree());
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(Full(Notes)));
        Assert.Equal(["l.md"], Directory.GetFileSystemEntries(library).Select(Path.GetFileName));
        Assert.Equal("L\n", File.ReadAllText(Path.Combine(library, "l.md")));
        Assert.Empty(Begins());
    }

    /// <summary>
    /// A folder gone before the plan is refused <c>cannotTellNow</c> by the
    /// one link test (<see cref="UndoLinks.Look"/>, which answers Nothing),
    /// never an exception of the file system's, and nothing changes.
    /// (A folder with a reparse point that is not a link, as OneDrive's, is
    /// not testable on the PC: measured in run w8b-15a-c, a folder carrying
    /// tag 0x80000013 without its filter cannot be listed or hold a file.)
    /// </summary>
    [Fact]
    public void AFolderGoneBeforeThePlanIsRefusedCannotTellNowAndNothingChanges()
    {
        ACourse();
        SortedDictionary<string, string?> before = Tree();
        UndoActionStep step = Step(List());

        var refused = Assert.Throws<UndoStepRefusedException>(() => step.MoveFolder(Full(Notes), Full(Zeta)));

        Assert.Equal(UndoRefusalKind.CannotTellNow, refused.Refusal.Kind);
        Assert.Equal(before, Tree());
        Assert.Empty(Begins());
    }

    [Fact]
    public void UnrecordedTheFolderIsMovedPlainlyAndTheEndTreeIsTheSame()
    {
        ACourse();
        // Recorded, for the end tree to compare with.
        UndoActionStep recorded = Step(List());
        recorded.MoveFolder(Full(Media), Full(Renamed));
        recorded.Write(Full(Renamed + "/a.md"), "A, edited\n");
        recorded.Make();
        SortedDictionary<string, string?> recordedTree = Tree();
        Directory.Delete(Folder, recursive: true);
        ACourse();
        _trail.Clear();
        int beginsBefore = Begins().Count;

        // No working folder: the step cannot be named, and in shadow it is made plainly.
        var plain = new UndoActionStep(new UndoStepMaker("sheet", "renameFolder"), null, "TST1O", null, holds: "course", undo: List());
        plain.MoveFolder(Full(Media), Full(Renamed));
        Assert.Equal("A\n", plain.ReadText(Full(Renamed + "/a.md")));
        plain.Write(Full(Renamed + "/a.md"), "A, edited\n");
        plain.Make();

        Assert.Equal(recordedTree, Tree());
        Assert.Equal(beginsBefore, Begins().Count);
        Assert.Single(_trail);
    }

    [Fact]
    public void UnrecordedAFolderEditedByHandBetweenThePlanAndTheMakeIsRefusedAndNothingChanges()
    {
        ACourse();
        var plain = new UndoActionStep(new UndoStepMaker("sheet", "renameFolder"), null, "TST1O", null, holds: "course", undo: List());
        plain.MoveFolder(Full(Media), Full(Renamed));
        plain.Write(Full(Renamed + "/a.md"), "A, edited\n");
        Write(Media + "/new.md", "New\n");
        SortedDictionary<string, string?> handEdited = Tree();

        var refused = Assert.Throws<UndoStepRefusedException>(plain.Make);

        Assert.Equal(UndoRefusalKind.ChangedSince, refused.Refusal.Kind);
        Assert.Equal(handEdited, Tree());
    }

    // ---- A link moved as itself (#899 W8b-21) ------------------------------------

    /// <summary>The library a link leads to, outside the working folder: a.md and pictures/b.md.</summary>
    private string ALibraryOutside()
    {
        string library = Path.Combine(_root, "library");
        Directory.CreateDirectory(Path.Combine(library, "pictures"));
        File.WriteAllText(Path.Combine(library, "a.md"), "A\n");
        File.WriteAllText(Path.Combine(library, "pictures", "b.md"), "B\n");
        return library;
    }

    /// <summary>
    /// <see cref="UndoActionStep.MoveLink"/> plans ONE <c>move {from, to, linkSha}</c>
    /// (the mac's <c>JournaledStep.moveLink</c>, U4b2-15), the target read as
    /// stored when planned, never followed: no <c>listingSha</c>, no blob, and
    /// what it leads to keeps its listing and the identity of every file. Undo
    /// and Redo move the link again as itself.
    /// </summary>
    [Fact]
    public void ALinkToAFolderIsOneMoveByItsLinkShaUndoneAndRedoneAndWhatItLeadsToIsUntouched()
    {
        ACourse();
        string library = ALibraryOutside();
        UndoKindsForTheCases.MakeAJunction(Full(Notes), library);
        string target = new DirectoryInfo(Full(Notes)).LinkTarget!;
        string untouched = UndoLinkMoveTests.Untouched(library);
        UndoForThisProcess list = List();
        UndoActionStep step = Step(list);

        step.MoveLink(Full(Notes), Full(Zeta));
        step.Make();

        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(Full(Notes)));
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(Full(Zeta)));
        Assert.Equal(target, new DirectoryInfo(Full(Zeta)).LinkTarget);
        JsonObject made = Assert.Single(Begins())["step"]!.AsObject();
        JsonObject move = Assert.Single(made["ops"]!.AsArray())!.AsObject();
        Assert.Equal("move", (string?)move["kind"]);
        Assert.Equal(Notes, (string?)move["from"]);
        Assert.Equal(Zeta, (string?)move["to"]);
        Assert.Equal(UndoLinkMoveTests.ShaOfTarget(target), (string?)move["linkSha"]);
        Assert.Null(move["listingSha"]);
        Assert.Null(move["blobs"]);
        Assert.Empty(_trail);
        Assert.Equal(untouched, UndoLinkMoveTests.Untouched(library));

        Assert.Equal(UndoOutcomeKind.Undone, list.Door().Undo().Kind);
        Assert.Equal(target, new DirectoryInfo(Full(Notes)).LinkTarget);
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(Full(Zeta)));
        Assert.Equal(UndoOutcomeKind.Redone, list.Door().Redo().Kind);
        Assert.Equal(target, new DirectoryInfo(Full(Zeta)).LinkTarget);
        Assert.Equal(untouched, UndoLinkMoveTests.Untouched(library));
    }

    /// <summary>The same function moves a link to a FILE as itself (W8b-22 and 21a6 use it): its target as written, the file it leads to untouched.</summary>
    [SymbolicLinkFact]
    public void ALinkToAFileIsMovedAsItselfTheFileItLeadsToUntouched()
    {
        ACourse();
        string page = "courses/TST1O/page.md";
        string moved = "courses/TST1O/moved.md";
        File.CreateSymbolicLink(Full(page), "media\\a.md");
        byte[] leadsTo = File.ReadAllBytes(Full(Media + "/a.md"));
        var identity = UndoFileIdentity.OfPlace(Full(Media + "/a.md"));
        UndoForThisProcess list = List();
        UndoActionStep step = Step(list);

        step.MoveLink(Full(page), Full(moved));
        step.Make();

        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(Full(page)));
        Assert.Equal("media\\a.md", new FileInfo(Full(moved)).LinkTarget);
        JsonObject move = Assert.Single(Assert.Single(Begins())["step"]!["ops"]!.AsArray())!.AsObject();
        Assert.Equal(UndoLinkMoveTests.ShaOfTarget("media\\a.md"), (string?)move["linkSha"]);
        Assert.Equal(leadsTo, File.ReadAllBytes(Full(Media + "/a.md")));
        Assert.Equal(identity, UndoFileIdentity.OfPlace(Full(Media + "/a.md")));
        Assert.Equal(UndoOutcomeKind.Undone, list.Door().Undo().Kind);
        Assert.Equal("media\\a.md", new FileInfo(Full(page)).LinkTarget);
    }

    /// <summary>Unrecorded (no working folder), the link is moved by the swap's own rename, as itself, never followed.</summary>
    [Fact]
    public void UnrecordedALinkIsMovedAsItselfAndWhatItLeadsToIsUntouched()
    {
        ACourse();
        string library = ALibraryOutside();
        UndoKindsForTheCases.MakeAJunction(Full(Notes), library);
        string target = new DirectoryInfo(Full(Notes)).LinkTarget!;
        string untouched = UndoLinkMoveTests.Untouched(library);

        var plain = new UndoActionStep(new UndoStepMaker("sheet", "renameFolder"), null, "TST1O", null, holds: "course", undo: List());
        plain.MoveLink(Full(Notes), Full(Zeta));
        plain.Make();

        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(Full(Notes)));
        Assert.Equal(target, new DirectoryInfo(Full(Zeta)).LinkTarget);
        Assert.Equal(untouched, UndoLinkMoveTests.Untouched(library));
        Assert.Empty(Begins());
        Assert.Single(_trail);
    }

    /// <summary>A link whose target cannot be read (WSL's own) is not planned: <c>cannotTellNow</c>, nothing changed.</summary>
    [ReparsePointFact]
    public void ALinkWhoseTargetCannotBeReadIsRefusedCannotTellNowAndNothingChanges()
    {
        ACourse();
        Assert.Null(UndoReparsePoints.Make(Full(Notes), UndoReparsePoints.WslLink, UndoReparsePoints.WslLinkData("../library")));
        UndoActionStep step = Step(List());

        var refused = Assert.Throws<UndoStepRefusedException>(() => step.MoveLink(Full(Notes), Full(Zeta)));

        Assert.Equal(UndoRefusalKind.CannotTellNow, refused.Refusal.Kind);
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(Full(Notes)));
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(Full(Zeta)));
        Assert.Empty(Begins());
    }
}
