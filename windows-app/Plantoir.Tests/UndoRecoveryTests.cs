using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// Recovery (#899 W3, <c>undo.rule.recovery</c>) beyond the contract's rows:
/// the refused-swap schedule, a step this process abandoned, recovery before
/// every prune, re-derivation on settle, the closed-step tidy of a folder that
/// was away, a recovery that is itself stopped and run again, and the trail
/// line. Each was seen to fail with its behaviour taken out
/// (vm-tools/guest/899-w3-mustfail.json).
/// </summary>
public sealed class UndoRecoveryTests
{
    private const string First = "courses/TST1O/Section 1/Classes/first.md";
    private const string Second = "courses/TST1O/Section 1/Classes/second.md";
    private const string Third = "courses/TST1O/Section 1/Classes/third.md";
    private const string FrontPage = "courses/TST1O/Section 1/index.md";

    private static byte[] Old(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: false\n---\nThe lesson.\n");
    private static byte[] New(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: true\n---\nThe lesson.\n");

    private static UndoScribe Scribe(string folder = "A")
    {
        var scribe = new UndoScribe();
        foreach (string path in new[] { First, Second, Third }) scribe.WritePage(folder, path, Old(path));
        return scribe;
    }

    private static UndoSeams StopAt(string point, int index = -1) =>
        new() { StopsHere = (at, where) => at == point && (index < 0 || where == index) };

    /// <summary>A two-page step made by a process that is then gone, stopped with its first page swapped in.</summary>
    private static long StopAStepHalfWay(UndoScribe scribe, string folder = "A", UndoStepDraft? draft = null)
    {
        UndoOutcome stopped = scribe.Door(StopAt("beforeSwap", 1), UndoScribe.AProcessThatIsGone)
            .Perform(draft ?? scribe.Draft(folder, [(First, New(First)), (Second, New(Second))]));
        Assert.Equal(UndoOutcomeKind.StoppedByATest, stopped.Kind);
        long seq = scribe.Fold().Steps.Keys.Max();
        Assert.Equal(New(First), scribe.Page(folder, First));
        Assert.Equal(Old(Second), scribe.Page(folder, Second));
        return seq;
    }

    private static bool Same(byte[]? a, byte[]? b) => a is null ? b is null : b is not null && a.AsSpan().SequenceEqual(b);

    // ---- The schedule -----------------------------------------------------------

    /// <summary>"one minute after a refusal, doubling, never more than an hour apart", per process (<c>rule.recovery</c>).</summary>
    [Fact]
    public void ARefusedPutBackIsTriedAgainAfterAMinuteThenDoublingToAnHour()
    {
        string rule = UndoContract.Undo.GetProperty("rule").GetProperty("recovery").GetString()!;
        Assert.Contains("one minute after a refusal, doubling, never more than an hour apart", rule);
        var memory = new UndoProcessMemory();
        var start = new DateTimeOffset(2026, 11, 20, 12, 0, 0, TimeSpan.Zero);
        Assert.True(memory.RefusedSwapIsDue("k", start));   // at the process's first lock
        TimeSpan[] waits = [TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(2), TimeSpan.FromMinutes(4), TimeSpan.FromMinutes(8),
                            TimeSpan.FromMinutes(16), TimeSpan.FromMinutes(32), TimeSpan.FromHours(1), TimeSpan.FromHours(1)];
        DateTimeOffset now = start;
        foreach (TimeSpan wait in waits)
        {
            memory.NoteARefusedSwap("k", now);
            Assert.False(memory.RefusedSwapIsDue("k", now + wait - TimeSpan.FromSeconds(1)));
            Assert.True(memory.RefusedSwapIsDue("k", now + wait));
            now += wait;
        }
        memory.ForgetTheRefusedSwap("k");
        Assert.True(memory.RefusedSwapIsDue("k", now));
    }

    /// <summary>
    /// On the ordinary path a refused put-back waits for its time, and an
    /// Undo tries it at once (the director's ruling 5 on U1's third round).
    /// Through the real door, with a real holder and the scribe's clock.
    /// </summary>
    [Fact]
    public void TheOrdinaryPathWaitsItsTurnAndAnUndoTriesAtOnce()
    {
        using UndoScribe scribe = Scribe();
        long seq = StopAStepHalfWay(scribe);
        using (new FileStream(scribe.FullPath("A", First), FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        {
            Assert.Empty(scribe.Door().Recover().Settled);
        }
        Assert.Equal(UndoStepState.Begun, scribe.Fold().Steps[seq].State);
        // Within the minute the ordinary path does not try it.
        Assert.NotNull(scribe.Step("A", [(Third, New(Third))]));
        Assert.Equal(UndoStepState.Begun, scribe.Fold().Steps[seq].State);
        Assert.Equal(New(First), scribe.Page("A", First));
        // After the minute it does.
        scribe.Clock.Advance(TimeSpan.FromMinutes(1));
        scribe.Prune();
        Assert.Equal(UndoStepState.RolledBack, scribe.Fold().Steps[seq].State);
        Assert.Equal(Old(First), scribe.Page("A", First));
    }

    [Fact]
    public void AnUndoTriesARefusedPutBackAtOnce()
    {
        using UndoScribe scribe = Scribe();
        long seq = StopAStepHalfWay(scribe);
        using (new FileStream(scribe.FullPath("A", First), FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        {
            Assert.Empty(scribe.Door().Recover().Settled);
        }
        Assert.Equal("nothingToUndo", scribe.Undo().Name);
        Assert.Equal(UndoStepState.RolledBack, scribe.Fold().Steps[seq].State);
        Assert.Equal(Old(First), scribe.Page("A", First));
        Assert.Empty(UndoStepContractTests.StagedFilesUnder(scribe.FullPath("A", "")));
    }

    // ---- Recovery before every prune (W2b's review, LOW 7) ---------------------------

    [Fact]
    public void PruningRefusesAHoldWhereRecoveryHasNotRun()
    {
        using UndoScribe scribe = Scribe();
        Assert.Throws<InvalidOperationException>(() => scribe.Journal.WithLock(writer => scribe.Journal.Prune(writer)));
        scribe.Journal.WithLock(writer => scribe.Door().RecoverThenPrune(writer));
    }

    /// <summary>
    /// A step that died mid-swap and is then past the limits is offered to
    /// recovery at once, so it is settled whole (its pages put back from its
    /// kept content) rather than closed <c>unsettled</c> with its originals
    /// removed, even when its put-back was refused within the minute.
    /// </summary>
    [Fact]
    public void AStepPruningWouldCloseIsTriedAtOnceAndSettledWhole()
    {
        using UndoScribe scribe = Scribe();
        long seq = StopAStepHalfWay(scribe);
        using (new FileStream(scribe.FullPath("A", First), FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        {
            Assert.Empty(scribe.Door().Recover().Settled);
        }
        // 50 more steps on the third page, the clock never moving: the dead
        // step is past the limits at the last one, within the minute.
        for (int step = 0; step < 50; step++)
        {
            byte[] now = scribe.Page("A", Third)!;
            Assert.NotNull(scribe.Step("A", [(Third, Same(now, New(Third)) ? Old(Third) : New(Third))]));
        }
        Assert.Equal(UndoStepState.RolledBack, scribe.Fold().Steps[seq].State);
        Assert.Equal(Old(First), scribe.Page("A", First));
        Assert.Equal(Old(Second), scribe.Page("A", Second));
    }

    // ---- A step this process abandoned (W2b's review, LOW 1) ----------------------

    /// <summary>
    /// A swap refused at its second page whose reversal of the first is ALSO
    /// refused (the first page held, no delete sharing, between its swap and
    /// the reversal) is half applied: the step is left in flight, never closed
    /// <c>failed</c>, and recovery settles it by content at the next lock
    /// although this process is alive.
    /// </summary>
    [Fact]
    public void AReversalThatDoesNotGoInLeavesTheStepInFlightAndRecoverySettlesIt()
    {
        using UndoScribe scribe = Scribe();
        var holders = new List<FileStream>();
        UndoOutcome outcome;
        try
        {
            var seams = new UndoSeams
            {
                BeforeEachSwap = (index, path) =>
                {
                    if (index != 1) return;
                    holders.Add(new FileStream(scribe.FullPath("A", First), FileMode.Open, FileAccess.Read, FileShare.ReadWrite));
                    holders.Add(new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite));
                },
            };
            outcome = scribe.Door(seams).Perform(scribe.Draft("A", [(First, New(First)), (Second, New(Second))]));
        }
        finally
        {
            foreach (FileStream holder in holders) holder.Dispose();
        }
        Assert.Equal("fileIsInUse", outcome.Word);
        long seq = outcome.Seq!.Value;
        Assert.Equal(UndoStepState.Begun, scribe.Fold().Steps[seq].State);
        Assert.Equal(New(First), scribe.Page("A", First));
        Assert.Equal(Old(Second), scribe.Page("A", Second));

        UndoRecoveryRun run = scribe.Door().Recover();
        Assert.Equal(UndoRecoveryOutcome.RolledBack, Assert.Single(run.Settled).Outcome);
        Assert.Equal(UndoStepState.RolledBack, scribe.Fold().Steps[seq].State);
        Assert.Equal(Old(First), scribe.Page("A", First));
        Assert.Empty(UndoStepContractTests.StagedFilesUnder(scribe.FullPath("A", "")));
    }

    /// <summary>Another process never settles a living process's step it was not told is abandoned; a pid that cannot be a process is never settled (the W1 review's low).</summary>
    [Fact]
    public void ARunningProcessesStepAndAnUnidentifiableProcessesStepAreLeft()
    {
        using UndoScribe scribe = Scribe();
        scribe.MarkAlive(UndoScribe.AnotherRunningProcess);
        Assert.Equal(UndoOutcomeKind.StoppedByATest, scribe.Door(StopAt("beforeSwap", 1), UndoScribe.AnotherRunningProcess)
            .Perform(scribe.Draft("A", [(First, New(First)), (Second, New(Second))])).Kind);
        foreach (long pid in new long[] { 0, -7 })
        {
            long seq = scribe.Fold().NextSeq;
            scribe.Append(scribe.BeginLine(seq, scribe.OpsFor(Third, Old(Third), New(Third)), "A", pid: pid));
        }
        Assert.Empty(scribe.Door().Recover().Settled);
        foreach (UndoFoldedStep step in scribe.Fold().Steps.Values) Assert.Equal(UndoStepState.Begun, step.State);
    }

    // ---- Re-derivation, and the doors that cannot re-derive --------------------------

    private static UndoStepDraft WithTheFrontPage(UndoScribe scribe) => scribe.Draft("A", [(First, New(First)), (Second, New(Second))]) with
    {
        Recomputes = [new JsonObject { ["kind"] = "recompute", ["maintainer"] = UndoOp.SectionFrontPage, ["path"] = FrontPage, ["section"] = 1 }],
    };

    /// <summary>
    /// A step that keeps the front page true, stopped after its swaps: a
    /// plain write on its course is refused, the step left for a recovery
    /// that re-derives; that recovery completes it and runs the maintainer
    /// once (<c>rule.recovery</c>; the mac's U2b reviews).
    /// </summary>
    [Fact]
    public void AStepThatKeepsAFileTrueIsSettledOnlyByARecoveryThatRederives()
    {
        using UndoScribe scribe = Scribe();
        Assert.Equal(UndoOutcomeKind.StoppedByATest, scribe.Door(StopAt("beforeApplied"), UndoScribe.AProcessThatIsGone).Perform(WithTheFrontPage(scribe)).Kind);
        long seq = scribe.Fold().Steps.Keys.Max();
        Assert.Equal(UndoOutcomeKind.AnotherChangeIsUnderWay, scribe.Door().Perform(scribe.Draft("A", [(Third, New(Third))])).Kind);
        Assert.Equal(UndoStepState.Begun, scribe.Fold().Steps[seq].State);
        Assert.Equal(0, scribe.Maintainers.Rederived);

        UndoRecoveryRun run = scribe.Door().Recover();
        Assert.Equal(UndoRecoveryOutcome.Completed, Assert.Single(run.Settled).Outcome);
        Assert.Equal(UndoStepState.Done, scribe.Fold().Steps[seq].State);
        Assert.Equal(1, scribe.Maintainers.Rederived);
    }

    /// <summary>With no runner for its maintainer, such a step is never settled, and Undo is not available rather than under way for ever.</summary>
    [Fact]
    public void WithNoRunnerTheStepWaitsAndUndoIsNotAvailable()
    {
        using UndoScribe scribe = Scribe();
        Assert.Equal(UndoOutcomeKind.StoppedByATest, scribe.Door(StopAt("beforeApplied"), UndoScribe.AProcessThatIsGone).Perform(WithTheFrontPage(scribe)).Kind);
        long seq = scribe.Fold().Steps.Keys.Max();
        var none = new NoRunner();
        Assert.Empty(scribe.Door(maintainers: none).Recover().Settled);
        Assert.Equal(UndoOutcomeKind.NotAvailable, scribe.Door(maintainers: none).Undo().Kind);
        Assert.Equal(UndoStepState.Begun, scribe.Fold().Steps[seq].State);
    }

    private sealed class NoRunner : IUndoMaintainers
    {
        public bool CanRun(string maintainer) => false;
        public void Rederive(UndoOp op, string root) => throw new InvalidOperationException("no runner");
    }

    // ---- Kept originals the list gives (W4c) ------------------------------------------

    /// <summary>
    /// A step that died with every page swapped and its swap's tidy cut short
    /// is completed, and a kept original whose bytes are exactly what the list
    /// gives for its page (the line op undone from what the page holds now)
    /// is not the only copy of anything: the settled tidy removes it, and no
    /// "undo kept what a page held" line names it (the mac's listHolds, U3c).
    /// </summary>
    // W7a part two, review 1, LOW 3: once with the kept original marked
    // Hidden, as the swap leaves one; the tidy finds it all the same.
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ACompletedStepsKeptOriginalThatTheListGivesIsTidied(bool hidden)
    {
        using UndoScribe scribe = Scribe();
        scribe.WritePage("A", First, Old(First));
        long seq = scribe.Fold().NextSeq;
        scribe.Append(scribe.BeginLine(seq, scribe.OpsFor(First, Old(First), New(First)), "A", pid: UndoScribe.AProcessThatIsGone));
        scribe.WritePage("A", First, New(First));
        string kept = UndoSwap.BesidePath(scribe.FullPath("A", First), $"{seq}-apply", "orig");
        File.WriteAllBytes(kept, Old(First));
        if (hidden) File.SetAttributes(kept, FileAttributes.Hidden | FileAttributes.Archive);

        scribe.Door().Recover();

        Assert.Equal(UndoStepState.Done, scribe.Fold().Steps[seq].State);
        Assert.False(File.Exists(kept), "a kept original the list gives was left beside its page");
        lock (scribe.TrailLines)
            Assert.DoesNotContain(scribe.TrailLines, line => line.Event == Plantoir.Core.Scripting.ActivityTrail.Event.UndoKeptWhatAPageHeld);
    }

    // ---- The closed-step tidy -----------------------------------------------------------

    /// <summary>
    /// A step closed <c>unsettled</c> while its folder was away keeps its
    /// staged files until the first recovery that reaches the folder removes
    /// them (<c>knownLimits.stagedFilesOfAFolderAway</c>, ruling 6).
    /// </summary>
    [Fact]
    public void AStepClosedWhileItsFolderWasAwayIsTidiedByTheFirstRecoveryThatReachesIt()
    {
        using UndoScribe scribe = Scribe();
        foreach (string path in new[] { First, Second }) scribe.WritePage("B", path, Old(path));
        long seq = StopAStepHalfWay(scribe, "B");
        Assert.NotEmpty(UndoStepContractTests.StagedFilesUnder(scribe.FullPath("B", "")));
        scribe.MoveFolderAway("B");
        for (int step = 0; step < 51; step++)
        {
            byte[] now = scribe.Page("A", Third)!;
            Assert.NotNull(scribe.Step("A", [(Third, Same(now, New(Third)) ? Old(Third) : New(Third))]));
        }
        Assert.Equal(UndoStepState.Interrupted, scribe.Fold().Steps[seq].State);
        scribe.PutFolderBack("B");
        Assert.NotEmpty(UndoStepContractTests.StagedFilesUnder(scribe.FullPath("B", "")));
        scribe.Door().Recover();
        // Everything staged goes but a kept original that differs from its
        // page: the only copy of what the page held (W4c, the mac's U3c).
        List<string> left = UndoStepContractTests.StagedFilesUnder(scribe.FullPath("B", "")).ToList();
        Assert.NotEmpty(left);
        foreach (string staged in left)
        {
            Assert.EndsWith("-orig", staged);
            // LOW 3 of W7a part two's review 1: what the closed-step tidy met
            // and kept is a kept original the swap marked Hidden.
            Assert.True(File.GetAttributes(staged).HasFlag(FileAttributes.Hidden), "the kept original the tidy met was not Hidden: " + staged);
            string place = Path.Combine(Path.GetDirectoryName(staged)!, UndoSwap.PlaceOfStagedName(Path.GetFileName(staged))!);
            Assert.False(UndoSwap.IsACopyOfItsPlace(staged, place), "a copy of its page was left: " + staged);
        }
    }

    // ---- A recovery that is itself stopped ---------------------------------------------

    /// <summary>
    /// A recovery stopped at each of its own kill points, then run again,
    /// leaves the same pages and the same list as one that was never stopped
    /// (the step off the list, every page as before, nothing staged left).
    /// </summary>
    [Theory]
    [InlineData("afterRecoveryTidied")]
    [InlineData("recoveryBeforeSwap")]
    [InlineData("recoveryBeforeWriting")]
    public void ARecoveryStoppedPartWayAndRunAgainComesToTheSameAnswer(string point)
    {
        using UndoScribe scribe = Scribe();
        long seq = StopAStepHalfWay(scribe);
        UndoRecoveryRun stopped = scribe.Door(StopAt(point, point == "recoveryBeforeSwap" ? 0 : -1)).Recover();
        Assert.True(stopped.StoppedByATest);
        Assert.True(scribe.Fold().Steps[seq].IsInFlight);
        scribe.Door().Recover();
        UndoFolded folded = scribe.Fold();
        Assert.False(folded.Steps[seq].IsOnTheList);
        Assert.Contains(folded.Steps[seq].State, new[] { UndoStepState.RolledBack, UndoStepState.Failed });
        Assert.Null(scribe.Journal.Offer(folded).Head);
        Assert.Equal(Old(First), scribe.Page("A", First));
        Assert.Equal(Old(Second), scribe.Page("A", Second));
        Assert.Empty(UndoStepContractTests.StagedFilesUnder(scribe.FullPath("A", "")));
    }

    // ---- The trail ------------------------------------------------------------------------

    /// <summary>The <c>undo rolled back</c> line, in the mac's words, for a put-back and for a hand edit in the way.</summary>
    [Fact]
    public void RecoveryWritesTheRolledBackLine()
    {
        using UndoScribe scribe = Scribe();
        StopAStepHalfWay(scribe);
        scribe.Door().Recover();
        UndoTrailLine line = Assert.Single(scribe.TrailLines);
        Assert.Equal(Plantoir.Core.Scripting.ActivityTrail.Event.UndoRolledBack, line.Event);
        Assert.Equal(("TST1O", (long?)1), (line.Course, line.Section));
        Assert.Equal("the undo list put back 1 file left part way by a change that stopped", line.Words);

        using UndoScribe edited = Scribe();
        StopAStepHalfWay(edited);
        edited.WritePage("A", Second, Encoding.UTF8.GetBytes("Changed by hand.\n"));
        edited.Door().Recover();
        Assert.Equal("the undo list put back 1 file left part way by a change that stopped, found 1 file changed by hand since, and cleared the list",
                     Assert.Single(edited.TrailLines).Words);
    }

    // ---- The door's W2b review LOWs 5 and 6 -------------------------------------------------

    /// <summary>A blob an ops step names as held, pruned between the vet and the begin, refuses the step before anything is written (W2b's review, LOW 5).</summary>
    [Fact]
    public void ABlobPrunedBeforeTheBeginRefusesTheStep()
    {
        using UndoScribe scribe = Scribe();
        byte[] after = [.. New(First), .. Encoding.UTF8.GetBytes("A line the step added.\n")];
        string before = scribe.PutBlob(Old(First));
        string made = scribe.PutBlob(after);
        var ops = new JsonArray(new JsonObject
        {
            ["kind"] = "writeFile", ["path"] = First, ["beforeSha"] = before, ["afterSha"] = made, ["blobs"] = new JsonArray(before, made),
        });
        var seams = new UndoSeams { BeforeTheBegin = () => File.Delete(scribe.Journal.BlobPath(made)) };
        UndoOutcome outcome = scribe.Door(seams).Perform(new UndoOpsDraft
        {
            ActionKey = "publishPages", MadeBy = "menu", WorkingFolder = scribe.FullPath("A", "").TrimEnd('\\'), Course = UndoScribe.ThisCourse, Ops = ops,
        });
        Assert.Equal("notReadable", outcome.Word);
        Assert.Empty(scribe.Fold().Steps);
        Assert.Equal(Old(First), scribe.Page("A", First));
    }

    /// <summary>A step given as ops with no working folder is refused, never an exception (W2b's review, LOW 6).</summary>
    [Fact]
    public void AnOpsStepWithNoWorkingFolderIsRefused()
    {
        using UndoScribe scribe = Scribe();
        UndoOutcome outcome = scribe.Door().Perform(new UndoOpsDraft
        {
            ActionKey = "setAPreference", MadeBy = "menu", WorkingFolder = null,
            Ops = new JsonArray(new JsonObject { ["kind"] = "writeFile", ["path"] = First }),
        });
        Assert.Equal("notReadable", outcome.Word);
        Assert.Empty(scribe.Fold().Steps);
    }
}
