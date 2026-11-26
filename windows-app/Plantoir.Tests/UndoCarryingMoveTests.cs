using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>opKinds.wholeOps</c>' one exception, on Windows (#899 W8-2): the one
/// comparison for "at or inside" (<see cref="UndoOp.PartInside"/>), and a
/// folder move's <c>listingSha</c>, which is never a blob
/// (<c>opKinds.move</c>: "The moved content is never a blob: the item itself
/// is what moves").
/// </summary>
public sealed class UndoCarryingMoveTests
{
    [Theory]
    [InlineData("courses/TST1O/renamed", "courses/TST1O/renamed", "")]
    [InlineData("courses/TST1O/renamed", "courses/TST1O/renamed/a.md", "a.md")]
    [InlineData("courses/TST1O/renamed", "courses/TST1O/Renamed/Sub/A.md", "Sub/A.md")]
    [InlineData("courses/tst1o/RENAMED", "courses/TST1O/renamed/a.md", "a.md")]
    public void PartInsideComparesEachPartWithoutRegardToCaseAndKeepsTheRestAsSpelled(string place, string path, string inside)
    {
        Assert.Equal(inside, UndoOp.PartInside(place, path));
    }

    [Theory]
    [InlineData("Media", "Mediahouse/a.md")]
    [InlineData("courses/TST1O/media", "courses/TST1O/mediahouse")]
    [InlineData("courses/TST1O/media/a.md", "courses/TST1O/media")]
    [InlineData("courses/TST1O/media", "courses/TST1O/other/media/a.md")]
    public void PartInsideIsNullForAPartThatOnlyBeginsAlikeOrAPathOutside(string place, string path)
    {
        Assert.Null(UndoOp.PartInside(place, path));
    }

    [Fact]
    public void PlacesOverlapIsPartInsideEitherWay()
    {
        Assert.True(UndoOp.PlacesOverlap("courses/TST1O/Media", "courses/TST1O/media/a.md"));
        Assert.True(UndoOp.PlacesOverlap("courses/TST1O/media/a.md", "courses/TST1O/MEDIA"));
        Assert.False(UndoOp.PlacesOverlap("courses/TST1O/Media", "courses/TST1O/Mediahouse/a.md"));
    }

    private static UndoTreeListing MediaListing() =>
        new(["sub"], [("a.md", UndoCheck.Sha(Encoding.UTF8.GetBytes("A\n"))), ("sub/b.md", UndoCheck.Sha(Encoding.UTF8.GetBytes("B\n")))]);

    [Fact]
    public void AFolderMovesListingIsNotOneOfItsBlobs()
    {
        UndoTreeListing listing = MediaListing();
        var op = new JsonObject { ["kind"] = "move", ["from"] = "courses/TST1O/media", ["to"] = "courses/TST1O/renamed", ["listingSha"] = listing.Sha };
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        UndoOp read = UndoFormat.ReadOp(document.RootElement);
        Assert.True(read.Readable);
        Assert.Empty(read.Blobs);
    }

    [Fact]
    public void ATreesListingIsStillOneOfItsBlobs()
    {
        UndoTreeListing listing = MediaListing();
        (JsonObject op, _) = UndoKindsForTheCases.Tree("createTree", "courses/TST1O/media", listing, []);
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        Assert.Contains(listing.Sha, UndoFormat.ReadOp(document.RootElement).Blobs);
    }

    /// <summary>
    /// A folder move is made through the door with no listing blob given or
    /// held (the mac's <c>JournaledWrite.vet</c> refused every one until U4b),
    /// and its Undo moves the folder back.
    /// </summary>
    [Fact]
    public void AFolderMoveIsMadeThroughTheDoorWithNoListingBlobAndUndone()
    {
        using var scribe = new UndoScribe();
        const string from = "courses/TST1O/media";
        const string to = "courses/TST1O/renamed";
        scribe.WritePage("A", from + "/a.md", Encoding.UTF8.GetBytes("A\n"));
        scribe.WritePage("A", from + "/sub/b.md", Encoding.UTF8.GetBytes("B\n"));
        UndoTreeListing listing = MediaListing();
        Assert.Equal(listing.Sha, UndoTreeReading.Read(scribe.FullPath("A", from)).ListingSha);
        var op = new JsonObject { ["kind"] = "move", ["from"] = from, ["to"] = to, ["listingSha"] = listing.Sha };

        UndoOutcome made = scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(op), []));

        Assert.Equal(UndoOutcomeKind.Applied, made.Kind);
        Assert.False(scribe.BlobIsThere(listing.Sha));
        Assert.Equal(listing.Sha, UndoTreeReading.Read(scribe.FullPath("A", to)).ListingSha);
        Assert.Equal("undone", scribe.Undo().Name);
        Assert.Equal(listing.Sha, UndoTreeReading.Read(scribe.FullPath("A", from)).ListingSha);
        Assert.IsType<UndoTreeReading.Absent>(UndoTreeReading.Read(scribe.FullPath("A", to)));
    }

    // ---- Readability (opKinds.wholeOps' one exception) --------------------------------

    private const string From = "courses/TST1O/media";
    private const string To = "courses/TST1O/renamed";

    private static UndoOp Op(JsonObject json)
    {
        using JsonDocument document = JsonDocument.Parse(json.ToJsonString());
        return UndoFormat.ReadOp(document.RootElement);
    }

    private static JsonObject FolderMove() =>
        new() { ["kind"] = "move", ["from"] = From, ["to"] = To, ["listingSha"] = MediaListing().Sha };

    private static JsonObject HunkAt(string path) => new()
    {
        ["kind"] = "replaceText", ["path"] = path, ["before"] = "old", ["after"] = "new",
        ["contextBefore"] = "Line one: ", ["contextAfter"] = ".\n",
    };

    [Fact]
    public void AnEditInsideAMovesToAfterTheMoveIsCarriedAndStands()
    {
        UndoOp move = Op(FolderMove());
        UndoOp edit = Op(HunkAt(To + "/a.md"));
        Assert.True(UndoOp.MoveCarries(move, edit));
        Assert.True(UndoStep.WholeOpsStandAlone([move, edit]));
        // Named with another case for a part: the same place on NTFS.
        Assert.True(UndoStep.WholeOpsStandAlone([move, Op(HunkAt("courses/TST1O/Renamed/a.md"))]));
    }

    [Fact]
    public void AnEditInsideAMovesToBeforeTheMoveIsABarrier()
    {
        Assert.False(UndoStep.WholeOpsStandAlone([Op(HunkAt(To + "/a.md")), Op(FolderMove())]));
    }

    [Fact]
    public void AnEditInsideAMovesFromIsABarrier()
    {
        UndoOp move = Op(FolderMove());
        UndoOp edit = Op(HunkAt(From + "/a.md"));
        Assert.False(UndoOp.MoveCarries(move, edit));
        Assert.False(UndoStep.WholeOpsStandAlone([move, edit]));
    }

    [Fact]
    public void AWholeOpInsideAMovesToIsStillABarrier()
    {
        UndoTreeListing listing = MediaListing();
        (JsonObject tree, _) = UndoKindsForTheCases.Tree("createTree", To + "/made", listing, []);
        UndoOp move = Op(FolderMove());
        Assert.False(UndoOp.MoveCarries(move, Op(tree)));
        Assert.False(UndoStep.WholeOpsStandAlone([move, Op(tree)]));
    }

    // ---- Through the real door ----------------------------------------------------------

    private static readonly byte[] OldA = Encoding.UTF8.GetBytes("Intro.\nLine one: old.\nEnd.\n");
    private static readonly byte[] NewA = Encoding.UTF8.GetBytes("Intro.\nLine one: new.\nEnd.\n");

    private static UndoScribe MediaFolder(out UndoTreeListing listing)
    {
        var scribe = new UndoScribe();
        scribe.WritePage("A", From + "/a.md", OldA);
        scribe.WritePage("A", From + "/b.md", Encoding.UTF8.GetBytes("B\n"));
        listing = ((UndoTreeReading.Tree)UndoTreeReading.Read(scribe.FullPath("A", From))).Listing;
        return scribe;
    }

    private static JsonObject MoveOf(UndoTreeListing listing) =>
        new() { ["kind"] = "move", ["from"] = From, ["to"] = To, ["listingSha"] = listing.Sha };

    /// <summary>Made, undone, redone and undone again: the edit after the move going forward, before it going back, and no staged file left.</summary>
    [Fact]
    public void ACarriedEditIsMadeUndoneRedoneAndUndoneAgainThroughTheDoor()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        UndoOutcome made = scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md")), []));
        Assert.Equal(UndoOutcomeKind.Applied, made.Kind);
        Assert.Equal(NewA, scribe.Page("A", To + "/a.md"));
        Assert.False(Directory.Exists(scribe.FullPath("A", From)));

        Assert.Equal("undone", scribe.Undo().Name);
        Assert.Equal(OldA, scribe.Page("A", From + "/a.md"));
        Assert.False(Directory.Exists(scribe.FullPath("A", To)));

        Assert.Equal("redone", scribe.Redo().Name);
        Assert.Equal(NewA, scribe.Page("A", To + "/a.md"));
        Assert.False(Directory.Exists(scribe.FullPath("A", From)));

        Assert.Equal("undone", scribe.Undo().Name);
        Assert.Equal(OldA, scribe.Page("A", From + "/a.md"));
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    /// <summary>A page the step made inside the moved folder: taken out before the move goes back (its kept original holds no handle on the folder then).</summary>
    [Fact]
    public void ACarriedNewPageIsTakenOutAndThenTheFolderMovedBack()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        byte[] made = Encoding.UTF8.GetBytes("Made.\n");
        JsonArray write = scribe.OpsFor(To + "/c.md", null, made);
        Assert.Equal(UndoOp.WriteFile, (string?)write[0]!["kind"]);
        UndoOutcome outcome = scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), write[0]!.DeepClone()), [made]));
        Assert.Equal(UndoOutcomeKind.Applied, outcome.Kind);
        Assert.Equal(made, scribe.Page("A", To + "/c.md"));

        Assert.Equal("undone", scribe.Undo().Name);
        Assert.Null(scribe.Page("A", From + "/c.md"));
        Assert.Equal(OldA, scribe.Page("A", From + "/a.md"));
        Assert.False(Directory.Exists(scribe.FullPath("A", To)));
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    /// <summary>A refused Undo of a carrying move names the folder where a teacher finds it now: its <c>to</c> (<c>placeAsFound</c>).</summary>
    [Fact]
    public void ARefusedUndoNamesTheMovedFolderWhereItIsNow()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md")), []));
        scribe.WritePage("A", To + "/c.md", Encoding.UTF8.GetBytes("C\n"));

        UndoScribe.Outcome undo = scribe.Undo();
        Assert.Equal("changedSince", undo.Name);
        Assert.Equal(To, undo.Page);
        Assert.Equal(NewA, scribe.Page("A", To + "/a.md"));
    }

    // W8-3 (U4b, M1): the step's own staged and kept files inside the moved
    // folder, from ANY of its swaps, are never the folder's content.

    private static readonly byte[] Kept = Encoding.UTF8.GetBytes("Kept.\n");

    /// <summary>A file named as step <paramref name="seq"/>'s kept original of a.md from an undo, beside a.md in <paramref name="folder"/>.</summary>
    private static string LeaveAKeptCopy(UndoScribe scribe, string folder, long seq)
    {
        string kept = UndoSwap.BesidePath(scribe.FullPath("A", folder + "/a.md"), $"{seq}-undo", "orig");
        File.WriteAllBytes(kept, Kept);
        return Path.GetFileName(kept);
    }

    /// <summary>Undone, the step's own kept copy left inside the folder at its old place, then redone: the copy moves with the folder and stays (an only copy).</summary>
    [Fact]
    public void AKeptCopyInsideTheFolderAtItsOldPlaceIsLeftOutOfTheRedo()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md")), []));
        Assert.Equal("undone", scribe.Undo().Name);
        string name = LeaveAKeptCopy(scribe, From, 1);

        Assert.Equal("redone", scribe.Redo().Name);
        Assert.Equal(NewA, scribe.Page("A", To + "/a.md"));
        Assert.False(Directory.Exists(scribe.FullPath("A", From)));
        Assert.Equal(Kept, scribe.Page("A", To + "/" + name));
    }

    /// <summary>Redone, the step's own kept copy left inside the folder at its new place, then undone.</summary>
    [Fact]
    public void AKeptCopyInsideTheFolderAtItsNewPlaceIsLeftOutOfTheUndo()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md")), []));
        Assert.Equal("undone", scribe.Undo().Name);
        Assert.Equal("redone", scribe.Redo().Name);
        string name = LeaveAKeptCopy(scribe, To, 1);

        Assert.Equal("undone", scribe.Undo().Name);
        Assert.Equal(OldA, scribe.Page("A", From + "/a.md"));
        Assert.False(Directory.Exists(scribe.FullPath("A", To)));
        Assert.Equal(Kept, scribe.Page("A", From + "/" + name));
    }

    /// <summary>Another step's staged file inside the folder is something else: the Undo is refused, naming the folder where it is.</summary>
    [Fact]
    public void AnotherStepsStagedFileInsideTheFolderIsNotLeftOut()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md")), []));
        LeaveAKeptCopy(scribe, To, 2);

        UndoScribe.Outcome undo = scribe.Undo();
        Assert.Equal("changedSince", undo.Name);
        Assert.Equal(To, undo.Page);
        Assert.Equal(NewA, scribe.Page("A", To + "/a.md"));
    }

    /// <summary>A teacher's file named like a staged file of step 11 is not step 1's (the marker is the whole number and its dash).</summary>
    [Fact]
    public void ATeachersFileNamedLikeAStagedFileOfAnotherSeqIsNotLeftOut()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md")), []));
        LeaveAKeptCopy(scribe, To, 11);

        Assert.Equal("changedSince", scribe.Undo().Name);
        Assert.Equal(NewA, scribe.Page("A", To + "/a.md"));
    }

    /// <summary>The kept original of a carried page whose blob the list no longer holds is looked for where the page is now: before a Redo, inside the folder at its old place.</summary>
    [Fact]
    public void TheKeptOriginalOfACarriedPageIsLookedForWhereThePageIsNow()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        byte[] made = Encoding.UTF8.GetBytes("Made.\n");
        var write = new JsonObject
        {
            ["kind"] = "writeFile", ["path"] = To + "/a.md", ["beforeSha"] = UndoCheck.Sha(OldA), ["afterSha"] = UndoCheck.Sha(made),
        };
        List<UndoOp> ops = [Op(MoveOf(listing)), Op(write)];
        string root = Path.GetDirectoryName(scribe.FullPath("A", "x"))!;
        var askedAt = new List<string>();

        UndoCheck.PlanResult plan = UndoCheck.Plan(ops, backward: false,
            relative => UndoCurrent.Read(scribe.FullPath("A", relative)), _ => null,
            whole: new UndoWholeReads(root, new UndoMemoryPlaces()),
            keptOriginal: (path, sha) => { askedAt.Add(path); return path == From + "/a.md" ? made : null; });

        Assert.Equal([From + "/a.md"], askedAt);
        Assert.IsType<UndoCheck.PlanResult.Ready>(plan);
    }

    /// <summary>A file added inside the moved folder between the check and the swap: the swap's own late refusal names the folder where it is now, as the plan's does (<c>placeAsFound</c>; W8-3's riding low).</summary>
    [Fact]
    public void ALateRefusalOfTheMoveNamesTheFolderWhereItIsNow()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md")), []));
        var seams = new UndoSeams { AfterTheCheck = () => scribe.WritePage("A", To + "/c.md", Encoding.UTF8.GetBytes("C\n")) };

        UndoOutcome undo = scribe.Door(seams).Undo();

        Assert.Equal(UndoOutcomeKind.Refused, undo.Kind);
        Assert.Equal(UndoRefusalKind.ChangedSince, undo.Refusal?.Kind);
        Assert.Equal(To, undo.Refusal?.Path);
        Assert.Equal(NewA, scribe.Page("A", To + "/a.md"));
    }

    /// <summary>The tidy of a carrying step looks where the folder is now: undone, a kept copy of a.md inside the folder at its old place is found and, a copy of its page, removed.</summary>
    [Fact]
    public void TheTidyFindsTheStepsOwnFilesWhereTheMovedFolderIsNow()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md")), []));
        Assert.Equal("undone", scribe.Undo().Name);
        string kept = UndoSwap.BesidePath(scribe.FullPath("A", From + "/a.md"), "1-undo", "orig");
        File.WriteAllBytes(kept, OldA);
        UndoStep step = scribe.Fold().Steps[1].Step;
        string root = Path.GetDirectoryName(scribe.FullPath("A", "x"))!;

        Assert.True(UndoSwap.TidyLeftovers(1, step.PathsToTidy, root, keepingOnlyCopies: true));
        Assert.False(File.Exists(kept));
    }

    // W8-4's riding lows (review 1 of window 1, LOWs 1 to 3).

    /// <summary>LOW 3: a folder made at a carried file's turn is followed when the swap is reversed: refused at that file's staging, the folder moved back holds no empty folder the swap made.</summary>
    [Fact]
    public void AFolderMadeForACarriedFileIsFollowedWhenTheSwapIsReversed()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        byte[] made = Encoding.UTF8.GetBytes("X\n");
        JsonArray write = scribe.OpsFor(To + "/sub/x.md", null, made);
        var seams = new UndoSeams { StagingWriteFailsAt = index => index == 2 };

        UndoOutcome outcome = scribe.Door(seams).Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md"), write[0]!.DeepClone()), [made]));

        Assert.Equal(UndoOutcomeKind.Refused, outcome.Kind);
        Assert.False(outcome.LeftPartWay);
        Assert.Equal(OldA, scribe.Page("A", From + "/a.md"));
        Assert.False(Directory.Exists(scribe.FullPath("A", To)));
        Assert.False(Directory.Exists(scribe.FullPath("A", From + "/sub")));
        Assert.Equal(listing.Sha, UndoTreeReading.Read(scribe.FullPath("A", From)).ListingSha);
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    /// <summary>LOW 2: a Redo whose carried page's staging fails after the folder has moved is reversed whole: the folder back at its from with its old a.md, nothing left part way, nothing staged left.</summary>
    [Fact]
    public void ARedoRefusedAfterItsCarryingMoveIsReversedWhole()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md")), []));
        Assert.Equal("undone", scribe.Undo().Name);

        UndoOutcome redo = scribe.Door(new UndoSeams { StagingWriteFailsAt = index => index == 1 }).Redo();

        Assert.Equal(UndoOutcomeKind.Refused, redo.Kind);
        Assert.Equal(UndoRefusalKind.CouldNotWrite, redo.Refusal?.Kind);
        Assert.False(redo.LeftPartWay);
        Assert.Equal(OldA, scribe.Page("A", From + "/a.md"));
        Assert.False(Directory.Exists(scribe.FullPath("A", To)));
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    /// <summary>LOW 1: the folder's rename refused (a file inside it held open by another program) names the place it leaves, as the mac's moveHere names it, never a destination that does not exist yet.</summary>
    [Fact]
    public void AFolderRenameThatFailsNamesThePlaceItLeaves()
    {
        using UndoScribe scribe = MediaFolder(out UndoTreeListing listing);
        scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(MoveOf(listing), HunkAt(To + "/a.md")), []));
        Assert.Equal("undone", scribe.Undo().Name);
        FileStream? held = null;
        var seams = new UndoSeams
        {
            BeforeEachSwap = (index, _) =>
            {
                if (index == 0) held ??= new FileStream(scribe.FullPath("A", From + "/b.md"), FileMode.Open, FileAccess.Read, FileShare.None);
            },
        };
        UndoOutcome redo;
        try { redo = scribe.Door(seams).Redo(); }
        finally { held?.Dispose(); }

        Assert.Equal(UndoOutcomeKind.Refused, redo.Kind);
        Assert.Equal(From, redo.Refusal?.Path);
        Assert.Equal(OldA, scribe.Page("A", From + "/a.md"));
        Assert.False(Directory.Exists(scribe.FullPath("A", To)));
    }
}
