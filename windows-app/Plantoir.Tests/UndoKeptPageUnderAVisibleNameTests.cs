using System.Text;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// U4b3 kept-original-named on Windows (#899 W8b-21c; the mac's
/// <c>UndoRecovery.keepPagesWhosePlaceIsTaken</c> and
/// <c>UndoSwap.renameToAVisibleName</c>): a page a step removed or moved away,
/// kept only in its hidden original while something else holds its place, is
/// renamed, never over anything, to the first free visible name beside it,
/// the words before the extension; the trail line is written just before the
/// rename; a place that cannot be read leaves it hidden and says nothing; a
/// kept original beside its own page (a page changed in place) is left alone.
/// The folder's name and the page's come from ONE function.
/// </summary>
public sealed class UndoKeptPageUnderAVisibleNameTests
{
    // MARK: - Stored properties

    private const string PagePath = "courses/TST1O/section1/Unit 1, Day 3.md";
    private const string FirstVisible = "courses/TST1O/section1/Unit 1, Day 3 (kept by Undo).md";
    private const string SecondVisible = "courses/TST1O/section1/Unit 1, Day 3 (kept by Undo 2).md";
    private const string TheEvent = "undo kept a page under a visible name";

    private static readonly byte[] Three = Encoding.UTF8.GetBytes("Three.\n");
    private static readonly byte[] SomeoneElses = Encoding.UTF8.GetBytes("Someone else's.\n");
    private static readonly byte[] Earlier = Encoding.UTF8.GetBytes("earlier\n");

    // MARK: - Functions

    /// <summary>A removed page's step, its kept original laid beside the place, and someone's page now at it.</summary>
    private static (UndoStep Step, string Root, string Kept) ARemovedPageWhosePlaceIsTaken(UndoScribe scribe)
    {
        scribe.WritePage("A", PagePath, Three);
        long seq = scribe.Step("A", [(PagePath, null)])!.Value;
        string page = scribe.FullPath("A", PagePath);
        string kept = UndoSwap.BesidePath(page, $"{seq}-apply", "orig");
        File.WriteAllBytes(kept, Three);
        scribe.WritePage("A", PagePath, SomeoneElses);
        return (scribe.Fold().Steps[seq].Step, scribe.FullPath("A", ""), kept);
    }

    /// <summary>
    /// The first visible name taken: kept as <c>(kept by Undo 2)</c>, the
    /// taken file untouched, nothing written over the page at the place, and
    /// the one trail line said while the page was still hidden (the intent
    /// first). MUST FAIL with MOVEFILE_REPLACE_EXISTING passed, with the line
    /// after the rename, and with a page name of its own (not VisibleName's).
    /// </summary>
    [Fact]
    public void ANameTakenIsSkippedNeverReplacedAndTheLineComesFirst()
    {
        using var scribe = new UndoScribe();
        (UndoStep step, string root, string kept) = ARemovedPageWhosePlaceIsTaken(scribe);
        scribe.WritePage("A", FirstVisible, Earlier);
        var lines = new List<(UndoTrailLine Line, bool StillHidden)>();

        Assert.True(UndoRecovery.KeepPagesWhosePlaceIsTaken(step, root, line => lines.Add((line, File.Exists(kept)))));

        Assert.Equal(Three, scribe.Page("A", SecondVisible));
        Assert.Equal(Earlier, scribe.Page("A", FirstVisible));
        Assert.Equal(SomeoneElses, scribe.Page("A", PagePath));
        Assert.False(File.Exists(kept), "the page is still hidden");
        (UndoTrailLine said, bool stillHidden) = Assert.Single(lines);
        Assert.Equal(TheEvent, ActivityTrail.KeyFor(said.Event));
        Assert.True(stillHidden, "the line was written after the rename");
        Assert.Equal($"the undo list keeps the page {PagePath}, removed or moved away by a change that stopped, as {SecondVisible}, because something else now holds {PagePath}", said.Words);
    }

    /// <summary>
    /// A file that appears at the visible name in the instant before the
    /// rename (after the line is said) is never overwritten: the next free
    /// name is taken. MUST FAIL with MOVEFILE_REPLACE_EXISTING passed.
    /// </summary>
    [Fact]
    public void ANameTakenInTheInstantBeforeTheRenameIsNeverOverwritten()
    {
        using var scribe = new UndoScribe();
        (UndoStep step, string root, string kept) = ARemovedPageWhosePlaceIsTaken(scribe);
        var lines = new List<UndoTrailLine>();

        Assert.True(UndoRecovery.KeepPagesWhosePlaceIsTaken(step, root, line =>
        {
            if (lines.Count == 0) scribe.WritePage("A", FirstVisible, Earlier);
            lines.Add(line);
        }));

        Assert.Equal(Earlier, scribe.Page("A", FirstVisible));
        Assert.Equal(Three, scribe.Page("A", SecondVisible));
        Assert.False(File.Exists(kept), "the page is still hidden");
    }

    /// <summary>One naming function: a folder's words after its whole name, a page's before its extension.</summary>
    [Fact]
    public void TheFolderAndThePageAreNamedByOneFunction()
    {
        Assert.Equal("extra (kept by Undo)", UndoSwap.VisibleName("extra", 1));
        Assert.Equal("extra (kept by Undo 2)", UndoSwap.VisibleName("extra", 2));
        Assert.Equal("Unit 1, Day 3 (kept by Undo).md", UndoSwap.VisibleName("Unit 1, Day 3.md", 1, isAPage: true));
        Assert.Equal("Unit 1, Day 3 (kept by Undo 3).md", UndoSwap.VisibleName("Unit 1, Day 3.md", 3, isAPage: true));
    }

    /// <summary>
    /// A place that cannot be read now is neither free nor taken: the page
    /// stays hidden, nothing is said, and the answer is false, so the tidy is
    /// tried again. MUST FAIL with a place that cannot be read taken as taken.
    /// </summary>
    [Fact]
    public void APlaceThatCannotBeReadLeavesThePageHiddenAndSilent()
    {
        using var scribe = new UndoScribe();
        (UndoStep step, string root, string kept) = ARemovedPageWhosePlaceIsTaken(scribe);
        string place = scribe.FullPath("A", PagePath);
        var lines = new List<UndoTrailLine>();

        bool named = UndoRecovery.KeepPagesWhosePlaceIsTaken(step, root, lines.Add,
            lookAt: path => path == place ? UndoLinks.What.CannotLook : UndoLinks.Look(path));

        Assert.False(named);
        Assert.True(File.Exists(kept), "the page left its hidden name");
        Assert.Null(scribe.Page("A", FirstVisible));
        Assert.Empty(lines);
    }

    /// <summary>
    /// A kept original beside its own page (a page changed in place: no op
    /// leaves or fills it whole) stays under its hidden name, as U3a and U3c
    /// keep it; and one whose place is free, or holds the same bytes, is not
    /// renamed either.
    /// </summary>
    [Fact]
    public void AKeptOriginalBesideItsOwnPageOrAFreePlaceIsLeftAlone()
    {
        using var scribe = new UndoScribe();
        scribe.WritePage("A", PagePath, Three);
        long seq = scribe.Step("A", [(PagePath, SomeoneElses)])!.Value;
        string kept = UndoSwap.BesidePath(scribe.FullPath("A", PagePath), $"{seq}-apply", "orig");
        File.WriteAllBytes(kept, Three);
        var lines = new List<UndoTrailLine>();
        Assert.True(UndoRecovery.KeepPagesWhosePlaceIsTaken(scribe.Fold().Steps[seq].Step, scribe.FullPath("A", ""), lines.Add));
        Assert.True(File.Exists(kept), "a kept original beside its own page was renamed");
        Assert.Empty(lines);

        using var freeScribe = new UndoScribe();
        (UndoStep step, string root, string removedKept) = ARemovedPageWhosePlaceIsTaken(freeScribe);
        File.Delete(freeScribe.FullPath("A", PagePath));
        Assert.True(UndoRecovery.KeepPagesWhosePlaceIsTaken(step, root, lines.Add));
        Assert.True(File.Exists(removedKept), "a kept original whose place is free was renamed");
        freeScribe.WritePage("A", PagePath, Three);
        Assert.True(UndoRecovery.KeepPagesWhosePlaceIsTaken(step, root, lines.Add));
        Assert.True(File.Exists(removedKept), "a kept original that is a copy of its place was renamed");
        Assert.Empty(lines);
    }
}
