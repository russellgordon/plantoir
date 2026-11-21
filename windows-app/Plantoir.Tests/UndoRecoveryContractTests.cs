using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>undo.recoveryCases</c>, every case,
/// through the REAL door, swap and recovery (#899 W3). A step publishing two
/// pages, <c>first</c> and <c>second</c> (or its undo or redo), is stopped at
/// the case's kill point by a door that names a process that is gone, as a
/// killed process would leave it; then recovery is run by this process
/// (<see cref="UndoDoor.Recover"/>, the app's recovery). A file in use during
/// recovery is a REAL holder (<c>FileShare.ReadWrite</c>, no delete: the
/// re-read succeeds, the put-back's rename is refused 32). The rows of U2b's
/// kinds (a move, a tree, a preference, who recovers) are W6's and held on the
/// ledger; each must still stop at the key it is held for.
/// </summary>
public sealed class UndoRecoveryContractTests
{
    private static readonly HashSet<string> KeysChecked = new(StringComparer.Ordinal)
    {
        "name", "work", "mode", "stopAt", "processAlive", "handEdit", "files", "phase", "head", "cleared", "pathsNamed",
        "undo", "moveFolderBeforeRecovery", "wholeFile", "contentRemovedBeforeRecovery", "fileInUseDuringRecovery",
        "anotherStepInFlight", "stepInFlight", "afterAnOrdinaryStep", "why",
    };

    private const string First = "courses/TST1O/Section 1/Classes/first.md";
    private const string Second = "courses/TST1O/Section 1/Classes/second.md";
    private const string Third = "courses/TST1O/Section 1/Classes/third.md";

    public static IEnumerable<object[]> Cases() =>
        UndoContract.Undo.GetProperty("recoveryCases").EnumerateArray()
            .Select(recoveryCase => new object[] { recoveryCase.GetProperty("name").GetString()! });

    [Fact]
    public void TheContractHoldsTheRecoveryCases()
    {
        // 41 when W3 was written (U1's 20 and U2b's 21); a count that falls is a contract change to read.
        Assert.True(UndoContract.Undo.GetProperty("recoveryCases").GetArrayLength() >= 41);
        Assert.Equal(UndoContract.Undo.GetProperty("recoveryCases").GetArrayLength(), Cases().Count());
    }

    /// <summary>Every case held open by name (U2b's kinds, W6) is a case the contract still has.</summary>
    [Fact]
    public void EveryHeldRecoveryCaseIsStillInTheContract() =>
        NamedGapLedger.StillNamed(NamedGapLedger.UndoRecoveryCases, Cases().Select(row => (string)row[0]));

    [Theory]
    [MemberData(nameof(Cases))]
    public void EveryRecoveryCase(string name)
    {
        if (NamedGapLedger.Holding(NamedGapLedger.UndoRecoveryCases, name) is { } held)
        {
            NamedGapLedger.HeldCaseStillStopsAtItsGap(held, () => Walk(name), "a key this replay does not check");
            return;
        }
        Walk(name);
    }

    private static string Page(string slug, bool published, bool wholeFile) =>
        $"---\ntitle: {slug}\npublish: {(published ? "true" : "false")}\n---\nThe lesson.\n" + (published && wholeFile ? "A line the step added.\n" : "");

    private static string PathOf(string name) => name switch
    {
        "first" => First,
        "second" => Second,
        _ => name,
    };

    private static void Walk(string name)
    {
        JsonElement recoveryCase = UndoContract.Undo.GetProperty("recoveryCases").EnumerateArray()
            .Single(candidate => candidate.GetProperty("name").GetString() == name);
        foreach (JsonProperty key in recoveryCase.EnumerateObject())
            Assert.True(KeysChecked.Contains(key.Name), "a key this replay does not check: " + key.Name);

        string work = recoveryCase.GetProperty("work").GetString()!;
        string stopAt = recoveryCase.GetProperty("stopAt").GetString()!;
        bool shadow = recoveryCase.TryGetProperty("mode", out JsonElement mode) && mode.GetString() == "shadow";
        bool wholeFile = Flag(recoveryCase, "wholeFile");
        UndoMode undoMode = shadow ? UndoMode.Shadow : UndoMode.Live;

        using var scribe = new UndoScribe();
        byte[] Before(string path) => Encoding.UTF8.GetBytes(Page(Path.GetFileNameWithoutExtension(path), false, wholeFile));
        byte[] After(string path) => Encoding.UTF8.GetBytes(Page(Path.GetFileNameWithoutExtension(path), true, wholeFile));
        foreach (string path in new[] { First, Second, Third }) scribe.WritePage("A", path, Before(path));

        // anotherStepInFlight: a RUNNING process begins a step on the third
        // page before the work, so the work's step is number 2.
        long? otherSeq = null;
        if (Flag(recoveryCase, "anotherStepInFlight"))
        {
            otherSeq = scribe.Fold().NextSeq;
            scribe.MarkAlive(UndoScribe.AnotherRunningProcess);
            scribe.Append(scribe.BeginLine(otherSeq.Value, scribe.OpsFor(Third, Before(Third), After(Third)), "A", pid: UndoScribe.AnotherRunningProcess));
        }

        // The work, made by a process that is then gone (or still running).
        long workPid = UndoScribe.AProcessThatIsGone;
        if (Flag(recoveryCase, "processAlive"))
        {
            workPid = UndoScribe.AnotherRunningProcess;
            scribe.MarkAlive(workPid);
        }
        (string point, int index) = stopAt.Contains(':')
            ? (stopAt[..stopAt.IndexOf(':')], int.Parse(stopAt[(stopAt.IndexOf(':') + 1)..], System.Globalization.CultureInfo.InvariantCulture))
            : (stopAt, -1);
        var stopping = new UndoSeams { StopsHere = (at, where) => at == point && (index < 0 || where == index) };
        UndoStepDraft draft = scribe.Draft("A", [(First, After(First)), (Second, After(Second))]);
        UndoOutcome stopped;
        long seq;
        if (work == "step")
        {
            stopped = scribe.Door(stopping, workPid, undoMode).Perform(draft);
            seq = scribe.Fold().Steps.Keys.Max();
        }
        else
        {
            Assert.True(work is "undo" or "redo", "a work this replay does not know: " + work);
            Assert.Equal(UndoOutcomeKind.Applied, scribe.Door(mode: undoMode).Perform(draft).Kind);
            seq = scribe.Fold().Steps.Keys.Max();
            if (work == "redo") Assert.Equal(UndoOutcomeKind.Undone, scribe.Door(mode: undoMode).Undo().Kind);
            stopped = work == "undo" ? scribe.Door(stopping, workPid, undoMode).Undo() : scribe.Door(stopping, workPid, undoMode).Redo();
        }
        Assert.True(stopped.Kind == UndoOutcomeKind.StoppedByATest, $"the work did not stop at {stopAt}: {stopped.Word}");
        if (otherSeq is { } other) Assert.Equal(other + 1, seq);
        Assert.True(scribe.Fold().Steps[seq].IsInFlight);
        var asLeft = new Dictionary<string, byte[]?> { [First] = scribe.Page("A", First), [Second] = scribe.Page("A", Second) };

        if (recoveryCase.TryGetProperty("handEdit", out JsonElement handEdit))
        {
            string edited = PathOf(handEdit.GetString()!);
            string text = UndoCheck.DecodeStrictly(scribe.Page("A", edited)!)!;
            scribe.WritePage("A", edited, Encoding.UTF8.GetBytes(UndoTraceEdits.HandEdit("sameLine", text)!));
        }
        var edits = new Dictionary<string, byte[]?> { [First] = scribe.Page("A", First), [Second] = scribe.Page("A", Second) };
        if (Flag(recoveryCase, "contentRemovedBeforeRecovery")) scribe.RemoveContent();
        bool away = Flag(recoveryCase, "moveFolderBeforeRecovery");
        if (away) scribe.MoveFolderAway("A");

        // Recovery, by this process, which sees the work's process as gone.
        var holders = new List<FileStream>();
        UndoRecoveryRun run;
        try
        {
            if (Flag(recoveryCase, "fileInUseDuringRecovery"))
            {
                // Every swap recovery makes is refused as a file in use, for
                // this recovery only: a real holder that shares reading and
                // writing but not delete, as Word does.
                foreach (string path in new[] { First, Second })
                    holders.Add(new FileStream(scribe.FullPath("A", path), FileMode.Open, FileAccess.Read, FileShare.ReadWrite));
            }
            run = scribe.Door(mode: undoMode).Recover();
        }
        finally
        {
            foreach (FileStream holder in holders) holder.Dispose();
        }
        Assert.False(run.StoppedByATest);

        // stepInFlight: the running process finishes its step after recovery.
        if (otherSeq is { } finishing)
        {
            scribe.WritePage("A", Third, After(Third));
            scribe.Finish(finishing);
        }
        if (recoveryCase.TryGetProperty("afterAnOrdinaryStep", out JsonElement afterAStep))
        {
            byte[] retitled = Encoding.UTF8.GetBytes(Page("third", true, false));
            Assert.Equal(UndoOutcomeKind.Applied, scribe.Door(mode: undoMode).Perform(scribe.Draft("A", [(Third, retitled)])).Kind);
            Assert.Equal(afterAStep.GetString(), UndoContract.Spelled(scribe.Fold().Steps[seq].State));
        }

        // The pages.
        string files = recoveryCase.GetProperty("files").GetString()!;
        if (files != "unchecked")
        {
            (byte[]? first, byte[]? second) = files switch
            {
                "before" => (Before(First), Before(Second)),
                "after" => (After(First), After(Second)),
                "asLeft" => (asLeft[First], asLeft[Second]),
                "firstBeforeSecondEdited" => (Before(First), edits[Second]),
                "secondAfterFirstEdited" => (edits[First], After(Second)),
                _ => throw new InvalidOperationException("a files value this replay does not know: " + files),
            };
            Assert.True(Same(first, scribe.Page("A", First)), $"first is not {files}");
            Assert.True(Same(second, scribe.Page("A", Second)), $"second is not {files}");
        }

        // The list.
        UndoFolded folded = scribe.Fold();
        Assert.Equal(recoveryCase.GetProperty("phase").GetString(), UndoContract.Spelled(folded.Steps[seq].State));
        if (recoveryCase.TryGetProperty("head", out JsonElement head))
        {
            long? expected = head.ValueKind == JsonValueKind.Null ? null : head.GetInt64();
            Assert.Equal(expected, scribe.Journal.Offer(folded).Head?.Seq);
        }
        if (recoveryCase.TryGetProperty("cleared", out JsonElement cleared))
        {
            Assert.NotNull(folded.LastClearing);
            Assert.Equal(cleared.GetString(), folded.LastClearing!.Value.Reason);
        }
        else
        {
            Assert.Null(folded.LastClearing);
        }
        if (recoveryCase.TryGetProperty("pathsNamed", out JsonElement pathsNamed))
        {
            var expected = pathsNamed.EnumerateArray().Select(path => PathOf(path.GetString()!)).ToList();
            Assert.Equal(expected, InterruptedPaths(scribe, seq));
        }
        if (recoveryCase.TryGetProperty("stepInFlight", out JsonElement stepInFlight))
            Assert.Equal(stepInFlight.GetString(), UndoContract.Spelled(folded.Steps[otherSeq!.Value].State));

        // Nothing of the journal's is left in a course once the step is
        // closed (in shadow recovery never writes into a working folder).
        if (!folded.Steps[seq].IsInFlight && !shadow && !away)
            Assert.Empty(UndoStepContractTests.StagedFilesUnder(scribe.FullPath("A", "")));

        if (recoveryCase.TryGetProperty("undo", out JsonElement undo))
            Assert.Equal(undo.GetString(), scribe.Door(mode: undoMode).Undo().Word);
        if (away) scribe.PutFolderBack("A");
    }

    /// <summary>The paths the step's <c>interrupted</c> line names, read from the segment as written.</summary>
    internal static List<string> InterruptedPaths(UndoScribe scribe, long seq)
    {
        foreach (string text in File.ReadAllLines(scribe.SegmentPath))
        {
            JsonObject line = JsonNode.Parse(text)!.AsObject();
            if ((string?)line["event"] == "interrupted" && line["seq"]!.GetValue<long>() == seq)
                return line["paths"]!.AsArray().Select(path => path!.GetValue<string>()).ToList();
        }
        Assert.Fail("no interrupted line for step " + seq);
        return [];
    }

    private static bool Flag(JsonElement element, string key) => element.TryGetProperty(key, out JsonElement value) && value.GetBoolean();

    private static bool Same(byte[]? a, byte[]? b) => a is null ? b is null : b is not null && a.AsSpan().SequenceEqual(b);
}
