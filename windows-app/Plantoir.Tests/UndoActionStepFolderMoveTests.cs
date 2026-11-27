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

    /// <summary>Every folder and file under the working folder, by its path there, with its bytes (null for a folder).</summary>
    private SortedDictionary<string, string?> Tree()
    {
        var tree = new SortedDictionary<string, string?>(StringComparer.Ordinal);
        foreach (string entry in Directory.EnumerateFileSystemEntries(Folder, "*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(Folder, entry).Replace('\\', '/');
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

    /// <summary>A folder carrying a reparse point that is NOT a link (as a OneDrive folder does) is the teacher's own folder: moved like any other, never refused as a link.</summary>
    [ReparsePointFact]
    public void AFolderWithAReparsePointThatIsNotALinkIsMovedLikeAnyOther()
    {
        ACourse();
        Directory.CreateDirectory(Full(Notes));
        Assert.Null(UndoReparsePoints.MakeOnAFolder(Full(Notes), UndoReparsePoints.NotALink, new byte[16]));
        Write(Notes + "/c.md", "C\n");
        Assert.True(File.GetAttributes(Full(Notes)).HasFlag(FileAttributes.ReparsePoint));
        Assert.Equal(UndoLinks.What.Folder, UndoLinks.Look(Full(Notes)));
        UndoActionStep step = Step(List());

        step.MoveFolder(Full(Notes), Full(Zeta));
        step.Make();

        Assert.False(Directory.Exists(Full(Notes)));
        Assert.Equal("C\n", File.ReadAllText(Full(Zeta + "/c.md")));
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
}
