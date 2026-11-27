using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7a: <c>rule.recovery</c>'s U3 sentence on Windows. In shadow,
/// recovery writes nothing of the teacher's, but a shadow step is staged
/// beside its pages like a live one, so the journal's own staged new content
/// of a step closed <c>interrupted</c> goes when every op of the step changes
/// a file in place or moves a file or folder whole (since W8-7, the mac's
/// <c>changesOnlyFilesAndMoves</c>); a step that sets a folder aside or makes
/// or removes a tree is left for a live recovery. A kept original that
/// differs from its page stays (the only copy of what the page held). The
/// mac's <c>tidyClosedSteps(onlyStepsOfFiles:)</c>.
/// </summary>
public sealed class UndoShadowClosedStepTidyTests
{
    // ---- Stored properties ---------------------------------------------------------

    private const string First = "courses/TST1O/Section 1/a.md";
    private const string Second = "courses/TST1O/Section 1/b.md";

    // ---- Functions -----------------------------------------------------------------

    private static byte[] Old(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: false\n---\nThe lesson.\n");
    private static byte[] New(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: true\n---\nThe lesson.\n");

    private static UndoSeams StopAt(string point, int index) =>
        new() { StopsHere = (at, where) => at == point && where == index };

    /// <summary>
    /// A shadow publish of two pages killed after the first went in: recovery
    /// in shadow leaves both pages as the kill left them (each whole), closes
    /// the step, removes the staged new content, and keeps the first page's
    /// earlier content beside it.
    /// </summary>
    [Fact]
    public void AShadowStepOfFilesClosedInterruptedLeavesNoStagedNewContent()
    {
        using var scribe = new UndoScribe();
        scribe.WritePage("A", First, Old(First));
        scribe.WritePage("A", Second, Old(Second));
        Assert.Equal(UndoOutcomeKind.StoppedByATest,
            scribe.Door(StopAt("beforeSwap", 1), UndoScribe.AProcessThatIsGone, UndoMode.Shadow)
                  .Perform(scribe.Draft("A", [(First, New(First)), (Second, New(Second))])).Kind);
        Assert.Contains(scribe.StagedLeftovers("A"), entry => entry.EndsWith("-new", StringComparison.Ordinal));

        scribe.Door(mode: UndoMode.Shadow).Recover();

        // Nothing of the teacher's written: each page whole, as the kill left it.
        Assert.Equal(New(First), scribe.Page("A", First));
        Assert.Equal(Old(Second), scribe.Page("A", Second));
        Assert.False(scribe.Fold().Steps[scribe.Fold().Steps.Keys.Max()].IsInFlight);
        // The journal's own staged new content is gone; the only copy of what
        // the first page held stays beside it.
        var left = scribe.StagedLeftovers("A");
        Assert.DoesNotContain(left, entry => entry.EndsWith("-new", StringComparison.Ordinal));
        string kept = Assert.Single(left);
        Assert.EndsWith("-orig", kept, StringComparison.Ordinal);
        Assert.Equal(Old(First), File.ReadAllBytes(kept));
    }

    /// <summary>
    /// A shadow publish of two pages killed before its first swap: recovery
    /// closes it as nothing took effect, leaves both pages as they were, and
    /// removes the staged new content of both (the harness's
    /// <c>w7-publish-kill</c>, shadow <c>beforeSwap@0</c>).
    /// </summary>
    [Fact]
    public void AShadowStepOfFilesKilledBeforeItsFirstSwapLeavesNoStagedNewContent()
    {
        using var scribe = new UndoScribe();
        scribe.WritePage("A", First, Old(First));
        scribe.WritePage("A", Second, Old(Second));
        Assert.Equal(UndoOutcomeKind.StoppedByATest,
            scribe.Door(StopAt("beforeSwap", 0), UndoScribe.AProcessThatIsGone, UndoMode.Shadow)
                  .Perform(scribe.Draft("A", [(First, New(First)), (Second, New(Second))])).Kind);
        Assert.Contains(scribe.StagedLeftovers("A"), entry => entry.EndsWith("-new", StringComparison.Ordinal));

        scribe.Door(mode: UndoMode.Shadow).Recover();

        Assert.Equal(Old(First), scribe.Page("A", First));
        Assert.Equal(Old(Second), scribe.Page("A", Second));
        UndoFoldedStep step = scribe.Fold().Steps[scribe.Fold().Steps.Keys.Max()];
        Assert.False(step.IsInFlight);
        Assert.Equal(UndoStepState.Failed, step.State);
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    /// <summary>
    /// The mac's U4b part four, L3 (#899 W8-7): a closed shadow step of files
    /// and moves (Rename folder's kind) is tidied too: a move sets nothing
    /// aside, so all the tidy removes is the step's own staged files beside its
    /// pages (<c>changesOnlyFilesAndMoves</c>).
    /// </summary>
    [Fact]
    public void AShadowStepWithAMoveIsTidied()
    {
        using var scribe = new UndoScribe();
        scribe.WritePage("A", First, Old(First));
        long seq = scribe.Fold().NextSeq;
        JsonArray ops = scribe.OpsFor(First, Old(First), New(First));
        ops.Add(new JsonObject { ["kind"] = UndoOp.Move, ["from"] = "courses/TST1O/x.json", ["to"] = "courses/TST1O/y.json", ["sha"] = UndoCheck.Sha(Old(Second)) });
        scribe.Append(scribe.BeginLine(seq, ops, "A", pid: UndoScribe.AProcessThatIsGone));
        string staged = UndoSwap.BesidePath(scribe.FullPath("A", First), $"{seq}-apply", "new");
        File.WriteAllBytes(staged, New(First));

        scribe.Door(mode: UndoMode.Shadow).Recover();

        Assert.False(scribe.Fold().Steps[seq].IsInFlight);
        Assert.False(File.Exists(staged), "the shadow tidy left a staged file of a step of files and moves");
        Assert.Equal(Old(First), scribe.Page("A", First));
    }

    /// <summary>
    /// Part three, review 1, LOW 4, as it stands since W8-7: a closed shadow
    /// step that takes out a folder (a <c>removeTree</c>) is left alone by the
    /// shadow tidy: its staged files stay where the dead process left them,
    /// for a live recovery (the mac's <c>onlyStepsOfFiles</c>).
    /// </summary>
    [Fact]
    public void AShadowStepWithATreeIsLeftAloneByTheTidy()
    {
        using var scribe = new UndoScribe();
        scribe.WritePage("A", First, Old(First));
        foreach ((string path, string text) in UndoKindsForTheCases.ExtraFiles)
            scribe.WritePage("A", UndoKindsForTheCases.ExtraFolder + "/" + path, System.Text.Encoding.UTF8.GetBytes(text));
        var tree = (UndoTreeReading.Tree)UndoTreeReading.Read(scribe.FullPath("A", UndoKindsForTheCases.ExtraFolder), keepingContents: true);
        (JsonObject treeOp, List<byte[]> treeBlobs) = UndoKindsForTheCases.Tree("removeTree", UndoKindsForTheCases.ExtraFolder, tree.Listing, tree.Contents.Values);
        foreach (byte[] blob in treeBlobs) scribe.PutBlob(blob);
        long seq = scribe.Fold().NextSeq;
        JsonArray ops = scribe.OpsFor(First, Old(First), New(First));
        ops.Add(treeOp);
        scribe.Append(scribe.BeginLine(seq, ops, "A", pid: UndoScribe.AProcessThatIsGone));
        string staged = UndoSwap.BesidePath(scribe.FullPath("A", First), $"{seq}-apply", "new");
        File.WriteAllBytes(staged, New(First));

        scribe.Door(mode: UndoMode.Shadow).Recover();

        Assert.False(scribe.Fold().Steps[seq].IsInFlight);
        Assert.True(File.Exists(staged), "the shadow tidy removed a staged file of a step that takes out a folder");
        Assert.Equal(Old(First), scribe.Page("A", First));
    }
}
