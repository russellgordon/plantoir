using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>opKinds.wholeOps</c> (U4b2-10, with its review 1; #899 W8-4): a folder
/// inside a moved folder that holds only files a carried edit made (and
/// folders so left out) is left out of the move's judgement with those files,
/// each such folder decided on its own (every set that leaves a folder out
/// only with every candidate below it, up to eight; beyond eight all or
/// none), and removed, when empty, once the folder has moved and the swap's
/// own files are tidied; a lone regular <c>.DS_Store</c> goes first, a link
/// of that name never; never on a refusal.
/// </summary>
public sealed class UndoMadeFoldersTests
{
    private const string From = "courses/TST1O/media";
    private const string To = "courses/TST1O/renamed";

    private static readonly byte[] OldA = Encoding.UTF8.GetBytes("Intro.\nLine one: old.\nEnd.\n");
    private static readonly byte[] NewA = Encoding.UTF8.GetBytes("Intro.\nLine one: new.\nEnd.\n");
    private static readonly byte[] X = Encoding.UTF8.GetBytes("X\n");

    /// <summary>media holding a.md, b.md and an empty folder of its own for each of <paramref name="emptyFolders"/>.</summary>
    private static UndoScribe MediaFolder(params string[] emptyFolders)
    {
        var scribe = new UndoScribe();
        scribe.WritePage("A", From + "/a.md", OldA);
        scribe.WritePage("A", From + "/b.md", Encoding.UTF8.GetBytes("B\n"));
        foreach (string folder in emptyFolders) Directory.CreateDirectory(scribe.FullPath("A", From + "/" + folder));
        return scribe;
    }

    /// <summary>ONE step: media's move to renamed, a.md's edit, and a new file X at each of <paramref name="made"/> inside renamed.</summary>
    private static UndoOutcome StepMaking(UndoScribe scribe, params string[] made)
    {
        string listingSha = UndoTreeReading.Read(scribe.FullPath("A", From)).ListingSha!;
        var ops = new JsonArray(
            new JsonObject { ["kind"] = "move", ["from"] = From, ["to"] = To, ["listingSha"] = listingSha },
            new JsonObject
            {
                ["kind"] = "replaceText", ["path"] = To + "/a.md", ["before"] = "old", ["after"] = "new",
                ["contextBefore"] = "Line one: ", ["contextAfter"] = ".\n",
            });
        var blobs = new List<byte[]>();
        foreach (string inside in made)
        {
            ops.Add(scribe.OpsFor(To + "/" + inside, null, X)[0]!.DeepClone());
            blobs.Add(X);
        }
        return scribe.Door().Perform(scribe.OpsDraft("A", ops, blobs));
    }

    private static string[] Numbered(string prefix, int count) =>
        Enumerable.Range(1, count).Select(number => prefix + number).ToArray();

    /// <summary>Two empty folders of the content's own and seven the step made, each given a file: nine candidates, so only all or none is tried and neither matches. Refused as changed since; nothing taken back.</summary>
    [Fact]
    public void NineCandidatesSomeTheContentsOwnAreRefusedAsChangedSinceAndNothingIsTakenBack()
    {
        string[] own = Numbered("own", 2);
        string[] made = Numbered("made", 7);
        using UndoScribe scribe = MediaFolder(own);
        string[] files = own.Concat(made).Select(folder => folder + "/x.md").ToArray();
        Assert.Equal(UndoOutcomeKind.Applied, StepMaking(scribe, files).Kind);

        Assert.Equal("changedSince", scribe.Undo().Name);

        Assert.Equal(NewA, scribe.Page("A", To + "/a.md"));
        foreach (string file in files) Assert.Equal(X, scribe.Page("A", To + "/" + file));
        Assert.False(Directory.Exists(scribe.FullPath("A", From)));
    }

    /// <summary>One empty folder of the content's own and seven the step made: eight candidates, every set tried; the step's seven are left out and removed, the content's own kept.</summary>
    [Fact]
    public void EightCandidatesAreDecidedOneByOne()
    {
        string[] made = Numbered("made", 7);
        using UndoScribe scribe = MediaFolder("own1");
        string[] files = new[] { "own1" }.Concat(made).Select(folder => folder + "/x.md").ToArray();
        Assert.Equal(UndoOutcomeKind.Applied, StepMaking(scribe, files).Kind);

        Assert.Equal("undone", scribe.Undo().Name);

        Assert.Equal(OldA, scribe.Page("A", From + "/a.md"));
        Assert.False(Directory.Exists(scribe.FullPath("A", To)));
        Assert.True(Directory.Exists(scribe.FullPath("A", From + "/own1")));
        Assert.Empty(Directory.EnumerateFileSystemEntries(scribe.FullPath("A", From + "/own1")));
        foreach (string folder in made) Assert.False(Directory.Exists(scribe.FullPath("A", From + "/" + folder)), folder);
        Assert.Empty(scribe.StagedLeftovers("A"));

        Assert.Equal("redone", scribe.Redo().Name);
        foreach (string file in files) Assert.Equal(X, scribe.Page("A", To + "/" + file));
    }

    /// <summary>A link put inside the folder a carried edit made: never left out (a listing holds no link, so the folder is not the content), and the Undo is refused with the link and what it leads to untouched.</summary>
    [Fact]
    public void AMadeFolderHoldingALinkIsNeverLeftOut()
    {
        using UndoScribe scribe = MediaFolder();
        Assert.Equal(UndoOutcomeKind.Applied, StepMaking(scribe, "sub/x.md").Kind);
        string outside = scribe.FullPath("A", "courses/elsewhere");
        Directory.CreateDirectory(outside);
        File.WriteAllBytes(Path.Combine(outside, "z.md"), X);
        string link = scribe.FullPath("A", To + "/sub/link");
        UndoKindsForTheCases.MakeAJunction(link, outside);

        Assert.Equal("changedSince", scribe.Undo().Name);

        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(link));
        Assert.Equal(X, File.ReadAllBytes(Path.Combine(outside, "z.md")));
        Assert.Equal(X, scribe.Page("A", To + "/sub/x.md"));
        Assert.Equal(NewA, scribe.Page("A", To + "/a.md"));
    }

    // ---- The tidy of one folder left out -------------------------------------------------

    private static string AFolder()
    {
        string folder = Path.Combine(Path.GetTempPath(), "plantoir-w8-4-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        return folder;
    }

    [Fact]
    public void AnEmptyFolderLeftOutIsRemoved()
    {
        string folder = AFolder();
        UndoSwap.RemoveAFolderLeftOut(folder);
        Assert.False(Directory.Exists(folder));
    }

    [Fact]
    public void AFolderLeftOutHoldingOnlyARegularDsStoreIsRemovedWithIt()
    {
        string folder = AFolder();
        File.WriteAllBytes(Path.Combine(folder, UndoTreeListing.IgnoredName), "Finder"u8.ToArray());
        UndoSwap.RemoveAFolderLeftOut(folder);
        Assert.False(Directory.Exists(folder));
    }

    /// <summary>Something put inside since the last look keeps the folder and all it holds: never a recursive delete.</summary>
    [Fact]
    public void AFolderLeftOutHoldingAnythingElseIsKeptWithAllItHolds()
    {
        string folder = AFolder();
        Directory.CreateDirectory(Path.Combine(folder, "mine"));
        File.WriteAllBytes(Path.Combine(folder, "mine", "y.md"), X);
        File.WriteAllBytes(Path.Combine(folder, UndoTreeListing.IgnoredName), "Finder"u8.ToArray());
        UndoSwap.RemoveAFolderLeftOut(folder);
        Assert.Equal(X, File.ReadAllBytes(Path.Combine(folder, "mine", "y.md")));
        Assert.True(File.Exists(Path.Combine(folder, UndoTreeListing.IgnoredName)));
        Directory.Delete(folder, recursive: true);
    }

    /// <summary>A <c>.DS_Store</c> that is a link is not deleted, and its folder stays.</summary>
    [Fact]
    public void ADsStoreThatIsALinkIsNotDeleted()
    {
        string folder = AFolder();
        string target = Path.Combine(AFolder(), "finder.txt");
        File.WriteAllBytes(target, "Finder"u8.ToArray());
        string record = Path.Combine(folder, UndoTreeListing.IgnoredName);
        File.CreateSymbolicLink(record, target);
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(record));

        UndoSwap.RemoveAFolderLeftOut(folder);

        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(record));
        Assert.Equal("Finder"u8.ToArray(), File.ReadAllBytes(target));
        File.Delete(record);
        Directory.Delete(folder);
    }

    /// <summary>
    /// A refusal after the move went in (a second folder's move, put back
    /// after it, finds its place taken by hand): the swap is reversed, and no
    /// folder the move's last look left out is tidied.
    /// </summary>
    [Fact]
    public void TheTidyOfFoldersLeftOutNeverRunsOnARefusal()
    {
        using UndoScribe scribe = MediaFolder();
        const string other = "courses/TST1O/other";
        const string otherMoved = "courses/TST1O/other2";
        scribe.WritePage("A", other + "/o.md", X);
        string otherSha = UndoTreeReading.Read(scribe.FullPath("A", other)).ListingSha!;
        string listingSha = UndoTreeReading.Read(scribe.FullPath("A", From)).ListingSha!;
        // Taken back in the other order: the media folder's move first, then the other's.
        var ops = new JsonArray(
            new JsonObject { ["kind"] = "move", ["from"] = other, ["to"] = otherMoved, ["listingSha"] = otherSha },
            new JsonObject { ["kind"] = "move", ["from"] = From, ["to"] = To, ["listingSha"] = listingSha },
            scribe.OpsFor(To + "/sub/x.md", null, X)[0]!.DeepClone());
        Assert.Equal(UndoOutcomeKind.Applied, scribe.Door().Perform(scribe.OpsDraft("A", ops, [X])).Kind);
        var removing = new List<string>();
        var swapped = new List<string>();
        string otherFull = Path.GetFullPath(scribe.FullPath("A", other));
        var seams = new UndoSeams
        {
            BeforeEachSwap = (_, fullPath) =>
            {
                swapped.Add(Path.GetFullPath(fullPath));
                if (Path.GetFullPath(fullPath) == otherFull) scribe.WritePage("A", other + "/hand.md", X);
            },
            RemovingAFolderLeftOut = removing.Add,
        };

        UndoOutcome undo = scribe.Door(seams).Undo();

        Assert.Equal(UndoOutcomeKind.Refused, undo.Kind);
        Assert.Equal(UndoRefusalKind.ChangedSince, undo.Refusal?.Kind);
        Assert.False(undo.LeftPartWay);
        // The media folder's move went in (and named sub) before the other's was refused.
        Assert.Equal([Path.GetFullPath(scribe.FullPath("A", From)), otherFull], swapped.Where(path => path == otherFull || path == Path.GetFullPath(scribe.FullPath("A", From))).ToList());
        Assert.Empty(removing);
        Assert.Equal(X, scribe.Page("A", To + "/sub/x.md"));
        Assert.Equal(OldA, scribe.Page("A", To + "/a.md"));
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    /// <summary>The same step undone with nothing in the way names sub to the tidy, which removes it.</summary>
    [Fact]
    public void TheTidyOfFoldersLeftOutRunsOnceEverySwapIsIn()
    {
        using UndoScribe scribe = MediaFolder();
        Assert.Equal(UndoOutcomeKind.Applied, StepMaking(scribe, "sub/x.md").Kind);
        var removing = new List<string>();

        Assert.Equal(UndoOutcomeKind.Undone, scribe.Door(new UndoSeams { RemovingAFolderLeftOut = removing.Add }).Undo().Kind);

        Assert.Equal([Path.GetFullPath(scribe.FullPath("A", From + "/sub"))], removing.Select(folder => Path.GetFullPath(folder)).ToList());
        Assert.False(Directory.Exists(scribe.FullPath("A", From + "/sub")));
        Assert.Empty(scribe.StagedLeftovers("A"));
    }
}
