using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7a: <c>rule.recovery</c>'s U3 sentence on Windows. In shadow,
/// recovery writes nothing of the teacher's, but a shadow step is staged
/// beside its pages like a live one, so the journal's own staged new content
/// of a step closed <c>interrupted</c> goes when every op of the step changes
/// a file in place; a kept original that differs from its page stays (the
/// only copy of what the page held). The mac's
/// <c>tidyClosedSteps(onlyStepsOfFiles:)</c>.
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
    /// Part three, review 1, LOW 4: a closed shadow step that holds an op other
    /// than a file changed in place (here a <c>move</c>) is left alone by the
    /// shadow tidy: its staged files stay where the dead process left them
    /// (the mac's <c>onlyStepsOfFiles</c>).
    /// </summary>
    [Fact]
    public void AShadowStepWithAMoveIsLeftAloneByTheTidy()
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
        Assert.True(File.Exists(staged), "the shadow tidy removed a staged file of a step that is not only files");
        Assert.Equal(Old(First), scribe.Page("A", First));
    }
}
