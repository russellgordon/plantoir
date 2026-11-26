using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// A refusal because a place of a move no longer stays inside the working
/// folder names the FIRST of the op's places that leads out, in the order
/// path, from, to, never the other side of the move (#899 W8-1, the mac's
/// U4b2-2 and its review 1, MEDIUM 1). The stack cases prove it at the plan;
/// these make the link AFTER the plan, so that only the check made again just
/// before the change can see it: at the staging check (<c>AfterTheCheck</c>)
/// and at the swap check (<c>beforeSwap</c>, index 0). The Windows twins of
/// the mac's four <c>UndoDoorGuardTests</c> <c>...AtTheStagingCheck...</c>
/// and <c>...AtTheSwapCheck...</c> tests.
/// </summary>
public sealed class UndoLeavingPlaceNamedTests
{
    /// <summary>Undo, the link made after the plan, before the staging, taking only the move's new place out: the new place is named, never the old.</summary>
    [Fact]
    public void UndoRefusedAtTheStagingCheckNamesTheNewPlaceThatLeadsOut() =>
        Assert.Equal("courses/TST1O/new/b.md", RefusedBetweenThePlanAndTheChange(redo: false, atTheSwap: false));

    /// <summary>The same, the link made just before the swap.</summary>
    [Fact]
    public void UndoRefusedAtTheSwapCheckNamesTheNewPlaceThatLeadsOut() =>
        Assert.Equal("courses/TST1O/new/b.md", RefusedBetweenThePlanAndTheChange(redo: false, atTheSwap: true));

    /// <summary>Redo, the link made after the plan, before the staging, taking only the move's old place out (where a Redo takes the page from): it is named, never the new place, which is as the Undo left it.</summary>
    [Fact]
    public void RedoRefusedAtTheStagingCheckNamesTheOldPlaceThatLeadsOut() =>
        Assert.Equal("courses/TST1O/old/a.md", RefusedBetweenThePlanAndTheChange(redo: true, atTheSwap: false));

    /// <summary>Redo, the link made just before the swap.</summary>
    [Fact]
    public void RedoRefusedAtTheSwapCheckNamesTheOldPlaceThatLeadsOut() =>
        Assert.Equal("courses/TST1O/old/a.md", RefusedBetweenThePlanAndTheChange(redo: true, atTheSwap: true));

    /// <summary>
    /// For an Undo, a move of courses/TST1O/b.md into courses/TST1O/new,
    /// undone with <c>new</c> replaced by a junction to outside after the
    /// plan; for a Redo, a move of courses/TST1O/old/a.md to courses/TST1O/a.md,
    /// undone and then redone with <c>old</c> replaced so. The page is then
    /// reached only through the junction, and nothing is moved through it.
    /// Returns the first place the changed-since refusal names.
    /// </summary>
    private static string? RefusedBetweenThePlanAndTheChange(bool redo, bool atTheSwap)
    {
        using var scribe = new UndoScribe();
        string from = redo ? "courses/TST1O/old/a.md" : "courses/TST1O/b.md";
        string to = redo ? "courses/TST1O/a.md" : "courses/TST1O/new/b.md";
        string linkedFolder = redo ? "courses/TST1O/old" : "courses/TST1O/new";
        string pageName = redo ? "a.md" : "b.md";
        byte[] page = Encoding.UTF8.GetBytes("page\n");
        scribe.WritePage("A", from, page);
        UndoOutcome made = scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(UndoKindsForTheCases.MoveFile(from, to, page)), []));
        Assert.Equal(UndoOutcomeKind.Applied, made.Kind);
        if (redo) Assert.Equal("undone", scribe.Undo().Name);
        // Where the page is now: the place the junction will take out.
        string movesTo = redo ? to : from;
        string outside = scribe.FullPath("A", "").TrimEnd(Path.DirectorySeparatorChar) + "-outside";

        bool linked = false;
        void LinkOutside()
        {
            if (linked) return;
            linked = true;
            string folder = scribe.FullPath("A", linkedFolder);
            Directory.Delete(folder, recursive: true);
            Directory.CreateDirectory(outside);
            UndoKindsForTheCases.MakeAJunction(folder, outside);
            // The page went with the folder; it is reached through the junction now.
            File.WriteAllBytes(Path.Combine(outside, pageName), page);
        }
        UndoSeams seams = atTheSwap
            ? new UndoSeams { StopsHere = (point, index) => { if (point == "beforeSwap" && index == 0) LinkOutside(); return false; } }
            : new UndoSeams { AfterTheCheck = LinkOutside };

        UndoOutcome outcome = redo ? scribe.Door(seams).Redo() : scribe.Door(seams).Undo();

        Assert.True(linked, "the junction was made " + (atTheSwap ? "before the swap" : "after the check"));
        Assert.Equal([pageName], Directory.EnumerateFileSystemEntries(outside).Select(Path.GetFileName));
        Assert.False(File.Exists(scribe.FullPath("A", movesTo)), "nothing was moved through the junction");
        Assert.Equal(UndoOutcomeKind.Refused, outcome.Kind);
        Assert.Equal(UndoRefusalKind.ChangedSince, outcome.Refusal?.Kind);
        return outcome.Refusal?.Path;
    }
}
