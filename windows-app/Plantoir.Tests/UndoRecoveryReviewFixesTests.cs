using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W4 carries the LOW findings of W3's independent review that could be
/// fixed in this piece (the director's message of 2026-11-20), each with a test
/// that fails with its fix taken out. The final sweep's finding on the files
/// entry's recompute is in <see cref="UndoDoorTests"/>
/// (<c>AStepHoldingARecomputeIsUndoneOnlyWithARunnerForItsMaintainer</c>).
/// </summary>
public sealed class UndoRecoveryReviewFixesTests : IDisposable
{
    private const string First = "courses/TST1O/Section 1/a.md";
    private const string Second = "courses/TST1O/Section 1/b.md";
    private const string Third = "courses/TST1O/Section 1/c.md";
    private const string FrontPage = "courses/TST1O/Section 1/index.md";

    private static byte[] Old(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: false\n---\nThe lesson.\n");
    private static byte[] New(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: true\n---\nThe lesson.\n");

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-lows-");
    private readonly UndoTestClock _clock = new(new DateTimeOffset(2026, 11, 20, 12, 0, 0, TimeSpan.Zero));
    private readonly UndoProcessMemory _memory = new();

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static UndoScribe Scribe()
    {
        var scribe = new UndoScribe();
        foreach (string path in new[] { First, Second, Third }) scribe.WritePage("A", path, Old(path));
        return scribe;
    }

    private static UndoSeams StopAt(string point, int index = -1) =>
        new() { StopsHere = (at, where) => at == point && (index < 0 || where == index) };

    /// <summary>
    /// LOW 2: a gone process's step that keeps a file true (a recompute, with a
    /// runner) past the limits is never closed <c>unsettled</c> by the pruning
    /// of a hold that cannot re-derive (a plain step's closing, on another
    /// course): one more try can settle it, and the next recovery that
    /// re-derives does, re-deriving its front page.
    /// </summary>
    [Fact]
    public void AStepThatKeepsAFileTrueIsNeverClosedUnsettledWhileARederivingRecoveryCouldSettleIt()
    {
        using UndoScribe scribe = Scribe();
        UndoStepDraft withTheFrontPage = scribe.Draft("A", [(First, New(First)), (Second, New(Second))]) with
        {
            Recomputes = [new JsonObject { ["kind"] = "recompute", ["maintainer"] = UndoOp.SectionFrontPage, ["path"] = FrontPage, ["section"] = 1 }],
        };
        Assert.Equal(UndoOutcomeKind.StoppedByATest, scribe.Door(StopAt("beforeApplied"), UndoScribe.AProcessThatIsGone).Perform(withTheFrontPage).Kind);
        long seq = scribe.Fold().Steps.Keys.Max();
        scribe.Clock.SetDaysFromStart(31);

        UndoOutcome other = scribe.Door().Perform(scribe.Draft("A", [(Third, New(Third))]) with { Course = "ZZZ9O" });
        Assert.Equal(UndoOutcomeKind.Applied, other.Kind);
        Assert.Equal(UndoStepState.Begun, scribe.Fold().Steps[seq].State);
        Assert.Equal(0, scribe.Maintainers.Rederived);

        UndoRecoveryRun run = scribe.Door().Recover();
        Assert.Contains(run.Settled, settled => settled.Seq == seq && settled.Outcome == UndoRecoveryOutcome.Completed);
        Assert.Equal(1, scribe.Maintainers.Rederived);
    }

    /// <summary>
    /// LOW 3: a closing this process cannot write (the list in use by another
    /// program at that moment, so every reading is stale) is noted as given up
    /// without reading the list, so the next Undo's recovery settles it by
    /// content although this process is alive; the step is never left "another
    /// change under way" for the life of the process.
    /// </summary>
    [Fact]
    public void AStepWhoseClosingCannotBeWrittenIsGivenUpWithoutAReadingAndSettledAtTheNextUndo()
    {
        string folder = Path.Combine(_root, "wf");
        string page = UndoDoor.FullPath(folder, First);
        Directory.CreateDirectory(Path.GetDirectoryName(page)!);
        File.WriteAllBytes(page, Old(First));
        bool inUse = false;
        var journal = new UndoJournal(Path.Combine(_root, "undo"), _clock, process => process is not null && process.Pid == Environment.ProcessId,
            step => UndoJournalChecks.FolderIsReachable(step, _clock), isLive: true, memory: _memory, readRetry: TimeSpan.Zero,
            open: path => inUse
                ? throw new IOException("The process cannot access the file because it is being used by another process.", unchecked((int)0x80070020))
                : File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete));
        var draft = new UndoStepDraft
        {
            ActionKey = "publishPages", MadeBy = "menu", WorkingFolder = folder, Course = "TST1O", Section = 1, Holds = "section",
            Changes = [new UndoFileChange(First, Old(First), New(First))],
        };
        var door = new UndoDoor(journal, UndoMode.Live, seams: new UndoSeams
        {
            StopsHere = (point, _) =>
            {
                if (point == "beforeApplied") inUse = true;
                return false;
            },
        });
        UndoOutcome made = door.Perform(draft);
        Assert.Equal(New(First), File.ReadAllBytes(page));
        inUse = false;
        UndoFoldedStep step = journal.Read().Folded.Steps[made.Seq!.Value];
        Assert.Equal(UndoStepState.Begun, step.State);

        UndoOutcome undo = new UndoDoor(journal, UndoMode.Live).Undo();
        Assert.Equal(UndoOutcomeKind.Undone, undo.Kind);
        Assert.Equal(Old(First), File.ReadAllBytes(page));
    }

    /// <summary>
    /// LOW 4: the newest step is a gone process's, reachable, and recovery
    /// cannot settle it (its put-back refused by a file held without delete
    /// sharing). Undo answers the true refusal, the file in use, naming it,
    /// with the list unchanged, never "another change is under way" until
    /// the step ages out; once the file is let go, the next Undo settles it.
    /// </summary>
    [Fact]
    public void AnUndoBehindAGoneStepThatCannotBeSettledNowSaysWhichFileIsInUse()
    {
        using UndoScribe scribe = Scribe();
        Assert.Equal(UndoOutcomeKind.StoppedByATest,
            scribe.Door(StopAt("beforeSwap", 1), UndoScribe.AProcessThatIsGone).Perform(scribe.Draft("A", [(First, New(First)), (Second, New(Second))])).Kind);
        long seq = scribe.Fold().Steps.Keys.Max();
        UndoOutcome refused;
        using (new FileStream(scribe.FullPath("A", First), FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        {
            refused = scribe.Door().Undo();
        }
        Assert.Equal(UndoOutcomeKind.Refused, refused.Kind);
        Assert.Equal(UndoRefusalKind.FileIsInUse, refused.Refusal!.Kind);
        Assert.Equal(First, refused.Refusal.Path);
        Assert.False(refused.ClearedTheList);
        Assert.Equal(UndoStepState.Begun, scribe.Fold().Steps[seq].State);

        scribe.Door().Undo();
        Assert.Equal(UndoStepState.RolledBack, scribe.Fold().Steps[seq].State);
        Assert.Equal(Old(First), scribe.Page("A", First));
    }
}
