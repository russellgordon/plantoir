using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// A restore sets aside, per file, every step in flight it replaced files of
/// (#899 W8c-3a, the mac's <c>UndoRestoreSetAside</c> and its tests): the
/// list's side, called as the restore will call it, inside the lock. A step
/// wholly inside is closed <c>interrupted</c>, <c>setAsideByARestore</c>,
/// every file, no clearing; a step partly inside gets
/// <c>filesReplacedByARestore</c> and stays in flight, and recovery then
/// never writes a set-aside file and settles the rest. Each was seen to fail
/// with its behaviour taken out (vm-tools/guest/899-w8c-3a-mustfail.json).
/// </summary>
public sealed class UndoRestoreSetAsideTests
{
    private const string Course = "courses/TST1O";
    private const string SectionOne = "courses/TST1O/Section 1";
    private const string First = "courses/TST1O/Section 1/Classes/first.md";
    private const string Second = "courses/TST1O/Section 1/Classes/second.md";
    private const string FrontPage = "courses/TST1O/index.md";
    private const string Shared = "courses/TST1O/shared.md";

    private static byte[] Old(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: false\n---\nThe lesson.\n");
    private static byte[] New(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: true\n---\nThe lesson.\n");

    private static UndoScribe Scribe()
    {
        var scribe = new UndoScribe();
        foreach (string path in new[] { First, Second, FrontPage, Shared }) scribe.WritePage("A", path, Old(path));
        return scribe;
    }

    private static UndoWorkingFolder Here(UndoScribe scribe, string folder = "A")
    {
        JsonObject named = scribe.WorkingFolder(folder);
        return new UndoWorkingFolder((string?)named["id"], (string?)named["pathAtTheTime"]);
    }

    private static IReadOnlyList<long> SetAside(UndoScribe scribe, string[] replaced, UndoWorkingFolder? folder = null) =>
        scribe.Journal.WithLock(writer => UndoRestoreSetAside.SetAsideSteps(replaced, folder ?? Here(scribe), writer,
                                                                             line => { lock (scribe.TrailLines) scribe.TrailLines.Add(line); }));

    /// <summary>A step of the given pages made by a process that is then gone, stopped before its swap of the page at <paramref name="stopBefore"/>.</summary>
    private static long StopAStep(UndoScribe scribe, string[] paths, int stopBefore)
    {
        var changes = new List<(string, byte[]?)>();
        foreach (string path in paths) changes.Add((path, New(path)));
        UndoOutcome stopped = scribe.Door(new UndoSeams { StopsHere = (at, where) => at == "beforeSwap" && where == stopBefore },
                                          UndoScribe.AProcessThatIsGone).Perform(scribe.Draft("A", changes));
        Assert.Equal(UndoOutcomeKind.StoppedByATest, stopped.Kind);
        return scribe.Fold().Steps.Keys.Max();
    }

    /// <summary>A step in flight written as its begin line alone (no door, so no recovery runs before the set-aside).</summary>
    private static long BeginARawStep(UndoScribe scribe, string path, string folder = "A")
    {
        long seq = scribe.Fold().NextSeq;
        scribe.Append(scribe.BeginLine(seq, scribe.OpsFor(path, Old(path), New(path)), folder, pid: UndoScribe.AProcessThatIsGone));
        return seq;
    }

    private static List<JsonObject> Lines(UndoScribe scribe)
    {
        var lines = new List<JsonObject>();
        foreach (string text in File.ReadAllLines(scribe.SegmentPath)) lines.Add(JsonNode.Parse(text)!.AsObject());
        return lines;
    }

    private static List<string> Strings(JsonNode? array)
    {
        var found = new List<string>();
        foreach (JsonNode? item in array!.AsArray()) found.Add((string)item!);
        return found;
    }

    private static bool Same(byte[]? a, byte[]? b) => a is null ? b is null : b is not null && a.AsSpan().SequenceEqual(b);

    // ---- A step wholly inside -------------------------------------------------

    /// <summary>
    /// Every file inside what the restore replaced: closed <c>interrupted</c>,
    /// reason <c>setAsideByARestore</c>, every file it names, and NO clearing
    /// (as pruning closes a step it can never settle); never on the list; its
    /// staged new content gone, a kept original that is the only copy kept;
    /// one trail line.
    /// </summary>
    [Fact]
    public void AStepWhollyInsideIsClosedInterruptedWithEveryFileAndNoClearing()
    {
        using UndoScribe scribe = Scribe();
        long seq = StopAStep(scribe, [First, Second], stopBefore: 1);
        int linesBefore = Lines(scribe).Count;

        IReadOnlyList<long> setAside = SetAside(scribe, [Course]);

        Assert.Equal([seq], setAside);
        List<JsonObject> written = Lines(scribe).Skip(linesBefore).ToList();
        JsonObject closing = Assert.Single(written);
        Assert.Equal("interrupted", (string?)closing["event"]);
        Assert.Equal("begin", (string?)closing["phase"]);
        Assert.Equal(UndoRestoreSetAside.Reason, (string?)closing["reason"]);
        Assert.Equal([First, Second], Strings(closing["paths"]));
        Assert.Null(scribe.Fold().LastClearing);
        UndoFoldedStep step = scribe.Fold().Steps[seq];
        Assert.Equal(UndoStepState.Interrupted, step.State);
        Assert.False(step.IsOnTheList);
        Assert.Null(scribe.Offer().Head);
        // The staged new content of the page not yet swapped is gone; the
        // kept original of the page swapped in differs from it, the only copy.
        List<string> left = scribe.StagedLeftovers("A");
        Assert.DoesNotContain(left, path => path.EndsWith("-new", StringComparison.Ordinal));
        string kept = Assert.Single(left);
        Assert.True(Same(Old(First), File.ReadAllBytes(kept)), "the only copy of what first.md held is kept");
        UndoTrailLine line = Assert.Single(scribe.TrailLines);
        Assert.Equal(Plantoir.Core.Scripting.ActivityTrail.Event.UndoSetAsideByARestore, line.Event);
        Assert.Equal("the undo list set aside a change that stopped part way (2 files), because a restore replaced its files; it is not judged again", line.Words);
        Assert.Equal(UndoScribe.ThisCourse, line.Course);
    }

    // ---- A step partly inside -------------------------------------------------

    /// <summary>
    /// A step with a file outside what the restore replaced: the event
    /// <c>filesReplacedByARestore</c> naming only the files inside, and the
    /// step stays in flight with them set aside; nothing closed, nothing cleared.
    /// </summary>
    [Fact]
    public void AStepPartlyInsideGetsTheEventAndStaysInFlight()
    {
        using UndoScribe scribe = Scribe();
        long seq = StopAStep(scribe, [FrontPage, Shared, First], stopBefore: 1);
        int linesBefore = Lines(scribe).Count;

        SetAside(scribe, [SectionOne]);

        JsonObject line = Assert.Single(Lines(scribe).Skip(linesBefore));
        Assert.Equal("filesReplacedByARestore", (string?)line["event"]);
        Assert.Equal(seq, (long)line["seq"]!);
        Assert.Equal(UndoRestoreSetAside.Reason, (string?)line["reason"]);
        Assert.Equal([First], Strings(line["paths"]));
        UndoFoldedStep step = scribe.Fold().Steps[seq];
        Assert.Equal(UndoStepState.Begun, step.State);
        Assert.Equal([First], step.SetAsidePaths);
        Assert.Null(scribe.Fold().LastClearing);
        UndoTrailLine said = Assert.Single(scribe.TrailLines);
        Assert.Equal("the undo list set aside 1 file of a change that stopped part way, because a restore replaced them; 2 other files of it will be settled as before", said.Words);
    }

    /// <summary>
    /// Then recovery: the restored page is never written (every byte
    /// compared; the backup holds what the stopped change was writing, so a
    /// recovery that judged it would put it back), the other files are put
    /// back by content, and the step is closed <c>interrupted</c>,
    /// <c>setAsideByARestore</c>, naming the file set aside, no clearing,
    /// never on the list.
    /// </summary>
    [Fact]
    public void RecoveryNeverWritesARestoredPageAndSettlesTheRest()
    {
        using UndoScribe scribe = Scribe();
        long seq = StopAStep(scribe, [FrontPage, Shared, First], stopBefore: 1);
        Assert.True(Same(New(FrontPage), scribe.Page("A", FrontPage)));
        SetAside(scribe, [SectionOne]);
        // The restore puts the backup's first.md in place.
        byte[] restored = New(First);
        scribe.WritePage("A", First, restored);

        UndoRecoveryRun run = scribe.Door().Recover();

        Assert.Contains(run.Settled, result => result.Seq == seq);
        Assert.True(Same(restored, scribe.Page("A", First)), "recovery wrote into the restored first.md");
        Assert.True(Same(Old(FrontPage), scribe.Page("A", FrontPage)), "index.md was not put back");
        Assert.True(Same(Old(Shared), scribe.Page("A", Shared)));
        JsonObject closing = Lines(scribe).Last(line => (long?)line["seq"] == seq);
        Assert.Equal("interrupted", (string?)closing["event"]);
        Assert.Equal(UndoRestoreSetAside.Reason, (string?)closing["reason"]);
        Assert.Equal([First], Strings(closing["paths"]));
        Assert.Null(scribe.Fold().LastClearing);
        UndoFoldedStep step = scribe.Fold().Steps[seq];
        Assert.Equal(UndoStepState.Interrupted, step.State);
        Assert.False(step.IsOnTheList);
        Assert.Null(scribe.Offer().Head);
    }

    /// <summary>The other files all made: settled as made, closed off the list all the same, the restored page untouched.</summary>
    [Fact]
    public void ARestOfTheStepThatWasMadeIsClosedOffTheListNotApplied()
    {
        using UndoScribe scribe = Scribe();
        long seq = StopAStep(scribe, [FrontPage, First], stopBefore: 1);
        SetAside(scribe, [SectionOne]);
        byte[] restored = Encoding.UTF8.GetBytes("the backup's first.md\n");
        scribe.WritePage("A", First, restored);

        scribe.Door().Recover();

        Assert.True(Same(restored, scribe.Page("A", First)));
        Assert.True(Same(New(FrontPage), scribe.Page("A", FrontPage)), "a made file stays made");
        UndoFoldedStep step = scribe.Fold().Steps[seq];
        Assert.Equal(UndoStepState.Interrupted, step.State);
        Assert.DoesNotContain(Lines(scribe), line => (string?)line["event"] == "applied");
        Assert.Null(scribe.Fold().LastClearing);
    }

    // ---- Which steps --------------------------------------------------------------

    /// <summary>Another course's step is never touched, a course whose name only begins the same way included (compared part by part).</summary>
    [Fact]
    public void AnotherCoursesStepIsUntouched()
    {
        using UndoScribe scribe = Scribe();
        long other = BeginARawStep(scribe, "courses/OTHER1/Section 1/a.md");
        long longer = BeginARawStep(scribe, "courses/TST1OX/Section 1/a.md");
        int linesBefore = Lines(scribe).Count;

        Assert.Empty(SetAside(scribe, [Course]));

        Assert.Equal(linesBefore, Lines(scribe).Count);
        Assert.Equal(UndoStepState.Begun, scribe.Fold().Steps[other].State);
        Assert.Equal(UndoStepState.Begun, scribe.Fold().Steps[longer].State);
        Assert.Empty(scribe.TrailLines);
    }

    /// <summary>A step made in another working folder (its identifier) is never touched, though it names the same path.</summary>
    [Fact]
    public void AStepOfAnotherWorkingFolderIsUntouched()
    {
        using UndoScribe scribe = Scribe();
        long elsewhere = BeginARawStep(scribe, First, folder: "B");
        long here = BeginARawStep(scribe, First, folder: "A");

        IReadOnlyList<long> setAside = SetAside(scribe, [Course]);

        Assert.Equal([here], setAside);
        Assert.Equal(UndoStepState.Begun, scribe.Fold().Steps[elsewhere].State);
        Assert.Empty(scribe.Fold().Steps[elsewhere].SetAsidePaths);
        Assert.Equal(UndoStepState.Interrupted, scribe.Fold().Steps[here].State);
    }

    /// <summary>The identifier is compared without regard to case.</summary>
    [Fact]
    public void TheIdentifierIsComparedWithoutRegardToCase()
    {
        using UndoScribe scribe = Scribe();
        long here = BeginARawStep(scribe, First);
        UndoWorkingFolder folder = Here(scribe);

        SetAside(scribe, [Course], folder with { Id = folder.Id!.ToUpperInvariant() });

        Assert.Equal(UndoStepState.Interrupted, scribe.Fold().Steps[here].State);
    }

    /// <summary>A second call sets aside nothing new: no line, no trail line, for a step closed or one only partly set aside.</summary>
    [Fact]
    public void ASecondCallSetsAsideNothingNew()
    {
        using UndoScribe scribe = Scribe();
        long partly = StopAStep(scribe, [FrontPage, First], stopBefore: 1);
        long wholly = BeginARawStep(scribe, Second);
        Assert.Equal([partly, wholly], SetAside(scribe, [SectionOne]));
        int lines = Lines(scribe).Count;
        int said = scribe.TrailLines.Count;

        Assert.Empty(SetAside(scribe, [SectionOne]));

        Assert.Equal(lines, Lines(scribe).Count);
        Assert.Equal(said, scribe.TrailLines.Count);
        Assert.Equal([First], scribe.Fold().Steps[partly].SetAsidePaths);
    }

    // ---- The fold ---------------------------------------------------------------

    private const string At = "2026-11-14T12:00:00Z";

    private static string Begin(long seq) =>
        $"{{\"v\":1,\"seq\":{seq},\"event\":\"begin\",\"at\":\"{At}\",\"process\":{{\"host\":\"h\",\"pid\":1,\"name\":\"n\",\"started\":\"s\"}}," +
        $"\"step\":{{\"seq\":{seq},\"madeAt\":\"{At}\",\"ops\":[]}}}}";

    private static string Plain(long seq, string name) => $"{{\"v\":1,\"seq\":{seq},\"event\":\"{name}\",\"at\":\"{At}\"}}";

    private static string Replaced(long seq, string paths) =>
        $"{{\"v\":1,\"seq\":{seq},\"event\":\"filesReplacedByARestore\",\"reason\":\"setAsideByARestore\",\"at\":\"{At}\",\"paths\":{paths}}}";

    private static UndoFolded Fold(params string[] lines)
    {
        var read = new List<UndoLine>();
        for (int place = 0; place < lines.Length; place++) read.Add(UndoFormat.Parse(lines[place], 1, place));
        return UndoFold.Fold(read);
    }

    /// <summary>
    /// The row <c>in flight --filesReplacedByARestore--&gt; (no move: its paths
    /// join the step's files set aside)</c>: begun, undoing and redoing keep
    /// where they stand and gather the union of the paths; a step not in
    /// flight ignores it.
    /// </summary>
    [Fact]
    public void TheFoldRowAddsThePathsToAStepInFlightAndMovesNothing()
    {
        Assert.Contains(UndoFold.Moves, move => move.On == "filesReplacedByARestore");
        UndoFolded begun = Fold(Begin(1), Replaced(1, "[\"a.md\",\"b.md\"]"), Replaced(1, "[\"b.md\",\"c.md\"]"));
        Assert.Equal(UndoStepState.Begun, begun.Steps[1].State);
        Assert.Equal(["a.md", "b.md", "c.md"], begun.Steps[1].SetAsidePaths);
        // A copy keeps them (a writer folds its own lines into one).
        Assert.Equal(["a.md", "b.md", "c.md"], begun.Copy().Steps[1].SetAsidePaths);

        UndoFolded undoing = Fold(Begin(1), Plain(1, "applied"), Plain(1, "undoing"), Replaced(1, "[\"a.md\"]"));
        Assert.Equal(UndoStepState.Undoing, undoing.Steps[1].State);
        Assert.Equal(["a.md"], undoing.Steps[1].SetAsidePaths);

        UndoFolded redoing = Fold(Begin(1), Plain(1, "applied"), Plain(1, "undoing"), Plain(1, "undone"), Plain(1, "redoing"), Replaced(1, "[\"a.md\"]"));
        Assert.Equal(UndoStepState.Redoing, redoing.Steps[1].State);
        Assert.Equal(["a.md"], redoing.Steps[1].SetAsidePaths);

        UndoFolded done = Fold(Begin(1), Plain(1, "applied"), Replaced(1, "[\"a.md\"]"));
        Assert.Equal(UndoStepState.Done, done.Steps[1].State);
        Assert.Empty(done.Steps[1].SetAsidePaths);
        Assert.Empty(done.Barriers);
    }

    /// <summary>
    /// A reader that does not know the event stops at it, a barrier, never
    /// passes over it (an older reader's view: the same line with an event
    /// this version does not know); and a <c>filesReplacedByARestore</c> line
    /// whose <c>paths</c> this version cannot read is a barrier too, never
    /// read as naming no file. Either way Undo is not available.
    /// </summary>
    [Fact]
    public void AReaderThatCannotReadTheEventStopsAtIt()
    {
        UndoFolded known = Fold(Begin(1), Plain(1, "applied"), Begin(2), Replaced(2, "[\"a.md\"]"));
        Assert.Empty(known.Barriers);

        string unknown = Replaced(2, "[\"a.md\"]").Replace("filesReplacedByARestore", "filesReplacedByALaterRestore", StringComparison.Ordinal);
        foreach (string line in new[] { unknown, Replaced(2, "\"a.md\""), Replaced(2, "[1]"), Replaced(2, "[]").Replace(",\"paths\":[]", "", StringComparison.Ordinal) })
        {
            UndoFolded folded = Fold(Begin(1), Plain(1, "applied"), line);
            UndoBarrier barrier = Assert.Single(folded.Barriers);
            Assert.Equal(2, barrier.Seq);
            UndoOffered offered = UndoLimits.Offer(folded, DateTimeOffset.Parse(At), _ => false, _ => true);
            Assert.Equal(UndoAnswerKind.NotAvailable, offered.Undo.Kind);
        }
        UndoOffered clear = UndoLimits.Offer(Fold(Begin(1), Plain(1, "applied")), DateTimeOffset.Parse(At), _ => false, _ => true);
        Assert.Equal(UndoAnswerKind.Step, clear.Undo.Kind);
    }
}
