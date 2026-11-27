using System.Text;
using System.Text.Json.Nodes;
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

    /// <summary>The begin line of a step of these ops, made by a process that is gone, as a step that died in flight leaves it.</summary>
    private static long AStepThatDied(UndoScribe scribe, params JsonArray[] opsOfEachPage)
    {
        var ops = new JsonArray();
        foreach (JsonArray pageOps in opsOfEachPage)
        {
            foreach (JsonNode? op in pageOps) ops.Add(op!.DeepClone());
        }
        long seq = scribe.Fold().NextSeq;
        scribe.Append(scribe.BeginLine(seq, ops, "A", pid: UndoScribe.AProcessThatIsGone));
        return seq;
    }

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

    /// <summary>
    /// The cause W8b-21c2 found for the contract's two kept-original-named
    /// rows: a page op's place that holds a symbolic link is not a file, so
    /// it is judged neither, as the mac's <c>UndoItem.read</c> (lstat) calls
    /// a link <c>notAFile</c>, and what the link leads to is never read as
    /// the page. Read through the link, a link the mac writes
    /// (<c>../library/Day 2.md</c>, forward slashes) was cannot tell, so
    /// recovery left the step in flight for good and the removed page stayed
    /// hidden; a link Windows writes was judged by its target's bytes (here
    /// the op's after). MUST FAIL with the link followed
    /// (<see cref="UndoCurrent.ReadWithoutFollowingALink"/> reading through it).
    /// </summary>
    [Theory]
    [InlineData("../library/Day 2.md")]
    [InlineData("..\\library\\Day 2.md")]
    public void APagesPlaceHoldingALinkIsNotAFileAndIsNeverReadThroughIt(string target)
    {
        using var scribe = new UndoScribe();
        const string Day2 = "courses/TST1O/section1/Unit 1, Day 2.md";
        byte[] two = Encoding.UTF8.GetBytes("Two.\n");
        scribe.WritePage("A", "courses/TST1O/library/Day 2.md", two);
        long seq = AStepThatDied(scribe, scribe.OpsFor(Day2, null, two));
        string place = scribe.FullPath("A", Day2);
        Directory.CreateDirectory(Path.GetDirectoryName(place)!);
        File.CreateSymbolicLink(place, target);

        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(place));
        Assert.IsType<UndoCurrent.NotAFile>(UndoCurrent.ReadWithoutFollowingALink(place));
        (string judged, UndoOpState state) = Assert.Single(UndoRecovery.FileStates(scribe.Fold().Steps[seq].Step, scribe.FullPath("A", "")));
        Assert.Equal(Day2, judged);
        Assert.Equal(UndoOpState.Neither, state);
    }

    /// <summary>
    /// Review 3 of the 21a line, LOW 1: a place whose reparse tag cannot be
    /// read (<see cref="UndoLinks.What.CannotLook"/>, here by the seam on
    /// the look) is CANNOT READ NOW, never read through: what it leads to
    /// would otherwise be judged as the page, or called a copy of a kept
    /// original (the mac's failing <c>lstat</c>, <c>.unreadable</c>). MUST
    /// FAIL with the <c>CannotLook</c> arm removed.
    /// </summary>
    [Fact]
    public void APlaceThatCannotBeLookedAtIsCannotReadNowAndNeverReadThrough()
    {
        string place = Path.Combine(RunOwnedTempFolders.Create("plantoir-undo-cannot-look-"), "Unit 1, Day 2.md");
        File.WriteAllText(place, "Two.\n");

        UndoCurrent read = UndoCurrent.ReadWithoutFollowingALink(place, look: _ => UndoLinks.What.CannotLook);

        Assert.IsType<UndoCurrent.CannotReadNow>(read);
        Assert.IsType<UndoCurrent.Bytes>(UndoCurrent.ReadWithoutFollowingALink(place, look: _ => UndoLinks.What.File));
        Directory.Delete(Path.GetDirectoryName(place)!, recursive: true);
    }

    /// <summary>
    /// Through recovery: a step that died with Day 3's page removed and Day 5
    /// changed, the list's content gone and Day 5's kept original no longer
    /// what it held, so Day 5 cannot be put back (couldNotPutBack), and
    /// someone's page now at Day 3. The removed page is kept under its
    /// visible name, and the trail says so BEFORE the couldNotPutBack line,
    /// which then names only what is still hidden. MUST FAIL with the keep
    /// after the couldNotPutBack line.
    /// </summary>
    [Fact]
    public void ThePageKeptUnderAVisibleNameIsSaidBeforeTheCouldNotPutBackLine()
    {
        using var scribe = new UndoScribe();
        const string Day5 = "courses/TST1O/section1/Unit 1, Day 5.md";
        byte[] five = Encoding.UTF8.GetBytes("Five.\n");
        byte[] fiveChanged = Encoding.UTF8.GetBytes("Five, changed.\n");
        scribe.WritePage("A", PagePath, Three);
        scribe.WritePage("A", Day5, fiveChanged);
        long seq = AStepThatDied(scribe, scribe.OpsFor(PagePath, Three, null), scribe.OpsFor(Day5, five, fiveChanged));
        // As the step left them: Day 3's page under its kept name, Day 5
        // changed, its kept original since changed too; then the content gone.
        string page = scribe.FullPath("A", PagePath);
        string keptThree = UndoSwap.BesidePath(page, $"{seq}-apply", "orig");
        File.Move(page, keptThree);
        string keptFive = UndoSwap.BesidePath(scribe.FullPath("A", Day5), $"{seq}-apply", "orig");
        File.WriteAllBytes(keptFive, Encoding.UTF8.GetBytes("Five, and a line added.\n"));
        scribe.RemoveContent();
        scribe.WritePage("A", PagePath, SomeoneElses);
        lock (scribe.TrailLines) scribe.TrailLines.Clear();

        UndoRecoveryRun run = scribe.Door().Recover();

        Assert.False(run.StoppedByATest);
        Assert.Equal(UndoStepState.Interrupted, scribe.Fold().Steps[seq].State);
        Assert.Equal(Three, scribe.Page("A", FirstVisible));
        Assert.Equal(SomeoneElses, scribe.Page("A", PagePath));
        Assert.False(File.Exists(keptThree), "the removed page is still hidden");
        List<UndoTrailLine> said;
        lock (scribe.TrailLines) said = scribe.TrailLines.ToList();
        int kept = said.FindIndex(line => ActivityTrail.KeyFor(line.Event) == TheEvent);
        int couldNot = said.FindIndex(line => line.Event == ActivityTrail.Event.UndoCouldNotPutBack);
        Assert.True(kept >= 0, "no line for the page kept under a visible name");
        Assert.True(couldNot >= 0, "no couldNotPutBack line: the case did not reach it");
        Assert.True(kept < couldNot, "the page kept under a visible name was said after the couldNotPutBack line");
        Assert.Equal(new List<string> { Path.GetFileName(keptFive) }, said[couldNot].Kept?.ToList());
    }

    /// <summary>
    /// Review 2 of window D, MEDIUM 1: a step removed Day 3's page and died;
    /// then a link in Windows' own form (backslashes) was made at Day 3,
    /// leading to a shared library file that holds the same bytes as the
    /// kept original. A link at the place is never a copy (the mac's
    /// <c>isACopyOfItsPlace</c> reads both sides by lstat, <c>UndoItem.read</c>),
    /// so the tidy never removes the only kept original, and the page is kept
    /// as <c>Unit 1, Day 3 (kept by Undo).md</c> with its line; the link and
    /// the file it leads to are untouched. MUST FAIL with
    /// <see cref="UndoSwap.IsACopyOfItsPlace"/> reading the place through the link.
    /// </summary>
    [SymbolicLinkFact]
    public void ALinkAtThePlaceLeadingToTheSameBytesIsNeverACopySoThePageIsKeptVisibly()
    {
        using var scribe = new UndoScribe();
        const string LibraryPage = "courses/TST1O/library/Day 3.md";
        scribe.WritePage("A", PagePath, Three);
        scribe.WritePage("A", LibraryPage, Three);
        long seq = AStepThatDied(scribe, scribe.OpsFor(PagePath, Three, null));
        // As the step left it: Day 3's page under its kept name; then a link
        // at Day 3 to the library file, which holds the same bytes.
        string page = scribe.FullPath("A", PagePath);
        string keptThree = UndoSwap.BesidePath(page, $"{seq}-apply", "orig");
        File.Move(page, keptThree);
        File.CreateSymbolicLink(page, "..\\library\\Day 3.md");
        lock (scribe.TrailLines) scribe.TrailLines.Clear();

        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(page));
        Assert.False(UndoSwap.IsACopyOfItsPlace(keptThree, page), "a link at the place was called a copy");

        UndoRecoveryRun run = scribe.Door().Recover();

        Assert.False(run.StoppedByATest);
        Assert.Equal(Three, scribe.Page("A", FirstVisible));
        Assert.False(File.Exists(keptThree), "the removed page is still hidden");
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(page));
        Assert.Equal("..\\library\\Day 3.md", new FileInfo(page).LinkTarget);
        Assert.Equal(Three, scribe.Page("A", LibraryPage));
        List<UndoTrailLine> said;
        lock (scribe.TrailLines) said = scribe.TrailLines.ToList();
        UndoTrailLine kept = Assert.Single(said, line => ActivityTrail.KeyFor(line.Event) == TheEvent);
        Assert.Equal($"the undo list keeps the page {PagePath}, removed or moved away by a change that stopped, as {FirstVisible}, because something else now holds {PagePath}", kept.Words);
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
