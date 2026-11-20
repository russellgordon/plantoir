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
        // U2b's (W6)
        "withAMove", "deployBeforeRecovery", "markers", "rederived", "withATree", "withAPreference", "folderKept", "preference",
        "recoveredBy", "changeTheFolderSetAside", "keptAside", "somethingInItsPlace", "nextWrite", "ordinaryWriteOn",
        "halfDeleteTheGoneFolder", "visibleNameTaken", "recoveryStopsAfterTheTidy", "keptVisibleAs", "folderLines",
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

        // U2b (W6): the same two pages, plus a rollover's marker moved aside
        // and the front page kept by its rule, or a folder removed and the
        // marker moved, or a preference set: one step through the door for ops.
        bool withAMove = Flag(recoveryCase, "withAMove");
        bool withATree = Flag(recoveryCase, "withATree");
        bool withAPreference = Flag(recoveryCase, "withAPreference");
        bool byOps = withAMove || withATree || withAPreference;
        scribe.Places.Write(UndoKindsForTheCases.Preference, new UndoJson.Text("a"));
        JsonArray? ops = null;
        var blobs = new List<byte[]>();
        if (byOps)
        {
            ops = new JsonArray();
            foreach (string path in new[] { First, Second })
            {
                foreach (JsonNode? op in scribe.OpsFor(path, Before(path), After(path))) ops.Add(op!.DeepClone());
            }
            if (withAPreference) ops.Add(UndoKindsForTheCases.External(UndoKindsForTheCases.Preference, "a", "b"));
            if (withATree)
            {
                foreach ((string path, string text) in UndoKindsForTheCases.ExtraFiles)
                    scribe.WritePage("A", UndoKindsForTheCases.ExtraFolder + "/" + path, Encoding.UTF8.GetBytes(text));
                var tree = (UndoTreeReading.Tree)UndoTreeReading.Read(scribe.FullPath("A", UndoKindsForTheCases.ExtraFolder), keepingContents: true);
                (JsonObject treeOp, List<byte[]> treeBlobs) = UndoKindsForTheCases.Tree("removeTree", UndoKindsForTheCases.ExtraFolder, tree.Listing, tree.Contents.Values);
                ops.Add(treeOp);
                blobs.AddRange(treeBlobs);
            }
            if (withAMove || withATree)
            {
                scribe.WritePage("A", UndoKindsForTheCases.MarkerFrom, Encoding.UTF8.GetBytes(UndoKindsForTheCases.OldMarker));
                ops.Add(UndoKindsForTheCases.MoveFile(UndoKindsForTheCases.MarkerFrom, UndoKindsForTheCases.MarkerTo, Encoding.UTF8.GetBytes(UndoKindsForTheCases.OldMarker)));
            }
            if (withAMove) ops.Add(UndoKindsForTheCases.FrontPageRecompute());
        }
        UndoOutcome MakeTheStep(UndoDoor door) => byOps ? door.Perform(scribe.OpsDraft("A", (JsonArray)ops!.DeepClone(), blobs)) : door.Perform(draft);

        UndoOutcome stopped;
        long seq;
        if (work == "step")
        {
            stopped = MakeTheStep(scribe.Door(stopping, workPid, undoMode));
            seq = scribe.Fold().Steps.Keys.Max();
        }
        else
        {
            Assert.True(work is "undo" or "redo", "a work this replay does not know: " + work);
            Assert.Equal(UndoOutcomeKind.Applied, MakeTheStep(scribe.Door(mode: undoMode)).Kind);
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
        if (Flag(recoveryCase, "changeTheFolderSetAside"))
        {
            // A file saved into the teacher's folder while the stopped work had it set aside.
            string aside = UndoSwap.BesidePath(scribe.FullPath("A", UndoKindsForTheCases.ExtraFolder), $"{seq}-apply", "orig");
            File.WriteAllText(Path.Combine(aside, "new.md"), "saved while it was aside\n");
        }
        if (Flag(recoveryCase, "somethingInItsPlace"))
            scribe.WritePage("A", UndoKindsForTheCases.ExtraFolder + "/other.md", "someone else's\n"u8.ToArray());
        if (Flag(recoveryCase, "halfDeleteTheGoneFolder"))
        {
            // As a delete that died part way leaves the folder it renamed to its -gone name: one of its files already gone.
            string parent = Path.GetDirectoryName(scribe.FullPath("A", UndoKindsForTheCases.ExtraFolder))!;
            string gone = Assert.Single(Directory.EnumerateDirectories(parent).Where(folder => folder.EndsWith("-gone", StringComparison.Ordinal)));
            File.Delete(Path.Combine(gone, "a.md"));
        }
        if (Flag(recoveryCase, "visibleNameTaken"))
            scribe.WritePage("A", UndoKindsForTheCases.ExtraFolder + " (kept by Undo)/earlier.md", "earlier\n"u8.ToArray());
        if (Flag(recoveryCase, "deployBeforeRecovery"))
            scribe.WritePage("A", UndoKindsForTheCases.MarkerFrom, Encoding.UTF8.GetBytes(UndoKindsForTheCases.NewMarker));
        scribe.Maintainers.Take();
        lock (scribe.TrailLines) scribe.TrailLines.Clear();

        // Recovery, by this process, which sees the work's process as gone:
        // the app's recovery (the default), the next write through the door
        // for ops, or a write through the plain door (recoveredBy).
        string recoveredBy = recoveryCase.TryGetProperty("recoveredBy", out JsonElement by) ? by.GetString()! : "recovery";
        var holders = new List<FileStream>();
        UndoRecoveryRun? run = null;
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
            if (recoveredBy == "theNextWrite")
            {
                scribe.WritePage("A", Third, Before(Third));
                var next = new JsonArray(UndoKindsForTheCases.MoveFile(Third, Third + ".moved", Before(Third)));
                scribe.Door(mode: undoMode).Perform(scribe.OpsDraft("A", next, []));
            }
            else if (recoveredBy == "anOrdinaryWrite")
            {
                string onPage = recoveryCase.TryGetProperty("ordinaryWriteOn", out JsonElement on) && on.GetString() == "first" ? First : Third;
                if (onPage == Third) scribe.WritePage("A", Third, Before(Third));
                string text = UndoCheck.DecodeStrictly(scribe.Page("A", onPage)!)!;
                byte[] written = Encoding.UTF8.GetBytes(JournaledSetting.SettingEntry("title", "title: Written over", text)!);
                UndoOutcome wrote = scribe.Door(mode: undoMode).Perform(scribe.Draft("A", [(onPage, written)]));
                if (recoveryCase.TryGetProperty("nextWrite", out JsonElement nextWrite)) Assert.Equal(nextWrite.GetString(), wrote.Word);
            }
            else
            {
                Assert.Equal("recovery", recoveredBy);
                if (Flag(recoveryCase, "recoveryStopsAfterTheTidy"))
                {
                    // A recovery that dies once it has tidied, before it writes to the list; then the next one.
                    UndoRecoveryRun first = scribe.Door(new UndoSeams { StopsHere = (at, _) => at == "afterRecoveryTidied" }, mode: undoMode).Recover();
                    Assert.True(first.StoppedByATest);
                    Assert.NotEqual(UndoStepState.Interrupted, scribe.Fold().Steps[seq].State);
                }
                run = scribe.Door(mode: undoMode).Recover();
            }
        }
        finally
        {
            foreach (FileStream holder in holders) holder.Dispose();
        }
        if (run is not null) Assert.False(run.StoppedByATest);

        // U2b's keys.
        if (recoveryCase.TryGetProperty("rederived", out JsonElement rederived))
            Assert.Equal(rederived.GetInt32(), scribe.Maintainers.Take());
        if (recoveryCase.TryGetProperty("markers", out JsonElement markers))
            Assert.Equal(markers.GetString(), UndoKindsForTheCases.Markers(scribe));
        if (recoveryCase.TryGetProperty("folderKept", out JsonElement folderKept))
            Assert.Equal(folderKept.GetBoolean(), UndoKindsForTheCases.FolderIsThere(scribe));
        if (recoveryCase.TryGetProperty("preference", out JsonElement preference))
            Assert.True(scribe.Places.Read(UndoKindsForTheCases.Preference).Matches(new UndoJson.Text(preference.GetString()!)));
        if (recoveryCase.TryGetProperty("keptVisibleAs", out JsonElement keptVisibleAs))
            Assert.True(File.Exists(Path.Combine(scribe.FullPath("A", keptVisibleAs.GetString()!), "a.md")), "the folder is not kept as " + keptVisibleAs.GetString());
        if (recoveryCase.TryGetProperty("folderLines", out JsonElement folderLines))
        {
            int said;
            lock (scribe.TrailLines) said = scribe.TrailLines.Count(line => line.Event == Plantoir.Core.Scripting.ActivityTrail.Event.UndoFoundAFolderSetAside);
            Assert.Equal(folderLines.GetInt32(), said);
        }
        List<string> leftovers = away ? [] : scribe.StagedLeftovers("A");
        if (recoveryCase.TryGetProperty("keptAside", out JsonElement keptAside))
            Assert.True(keptAside.GetBoolean() == leftovers.Count > 0, "a folder kept aside: " + string.Join(", ", leftovers));
        else if (withATree)
            Assert.Empty(leftovers);

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
        if (!folded.Steps[seq].IsInFlight && !shadow && !away && !recoveryCase.TryGetProperty("keptAside", out _))
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
