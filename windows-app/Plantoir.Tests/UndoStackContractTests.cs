using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>undo.stackCases</c>, every case,
/// walked through the product's reader, fold, limits, pruning decisions and
/// check (#899 piece W1). The lines are written by <see cref="UndoScribe"/>,
/// the test's stand-in for W2's door; every decision it acts on is the
/// product's. W2 replaces the scribe with the real door, under the lock, and
/// this test is then run through it.
/// </summary>
public sealed class UndoStackContractTests
{
    /// <summary>Every key a case may carry; a new one is a request this replay must learn to check, not something to pass over.</summary>
    private static readonly HashSet<string> KeysChecked = new(StringComparer.Ordinal)
    {
        "name", "calls", "head", "redo", "onTheList", "onTheListCount", "oldestOnTheList", "expectLast", "cleared",
        "clearedSeq", "linesWritten", "onTheDisk", "physicallyPruned", "blobKept", "interrupted",
        "markers", "folderKept", "rederived", "nothingMovedOutside",
    };

    public static IEnumerable<object[]> Cases() =>
        UndoContract.Undo.GetProperty("stackCases").EnumerateArray()
            .Select(stackCase => new object[] { stackCase.GetProperty("name").GetString()! });

    [Fact]
    public void TheContractHoldsTheStackCases()
    {
        // 46 when W1 was written; a count that falls is a contract change to read, never a silent pass.
        Assert.True(UndoContract.Undo.GetProperty("stackCases").GetArrayLength() >= 46);
        Assert.Equal(UndoContract.Undo.GetProperty("stackCases").GetArrayLength(), Cases().Count());
    }

    /// <summary>Every case held open by name is a case the contract still has (none since W6).</summary>
    [Fact]
    public void EveryHeldStackCaseIsStillInTheContract() =>
        NamedGapLedger.StillNamed(NamedGapLedger.UndoStackCases, Cases().Select(row => (string)row[0]));

    /// <summary>
    /// Every case, asserted in full, U2's calls and keys included (W6). A case
    /// the ledger holds open (a call or a key a later piece brings) must still
    /// stop at that call or key, and goes from the ledger the day it passes.
    /// </summary>
    [Theory]
    [MemberData(nameof(Cases))]
    public void EveryStackCase(string name) => RunAsTheLedgerSays(name, NamedGapLedger.All, () => WalkTheCase(name));

    /// <summary>
    /// One case, walked by <paramref name="walk"/>, held or not as
    /// <paramref name="entries"/> say. <see cref="EveryStackCase"/> passes the
    /// real walk; a held case that plays through fails as its gap closing.
    /// </summary>
    private static void RunAsTheLedgerSays(string name, IEnumerable<NamedGapLedger.Entry> entries, Action walk)
    {
        if (NamedGapLedger.Holding(NamedGapLedger.UndoStackCases, name, entries) is { } held)
        {
            NamedGapLedger.HeldCaseStillStopsAtItsGap(held, walk, "this replay does not know", "this replay does not check");
            return;
        }
        walk();
    }

    private static void WalkTheCase(string name)
    {
        JsonElement stackCase = UndoContract.Undo.GetProperty("stackCases").EnumerateArray()
            .Single(candidate => candidate.GetProperty("name").GetString() == name);
        foreach (JsonProperty key in stackCase.EnumerateObject())
            Assert.True(KeysChecked.Contains(key.Name), "a key this replay does not check: " + key.Name);

        using var scribe = new UndoScribe();
        var replay = new StackReplay(scribe);
        foreach (JsonElement call in stackCase.GetProperty("calls").EnumerateArray()) replay.Call(call.GetString()!);

        UndoFolded folded = scribe.Fold();
        UndoOffered offered = scribe.Journal.Offer(folded);
        Assert.Equal(NullableSeq(stackCase, "head"), offered.Head?.Seq);
        Assert.Equal(NullableSeq(stackCase, "redo"), offered.Redo.Seq);
        var listed = offered.Offered.Select(step => step.Seq).ToList();
        if (stackCase.TryGetProperty("onTheList", out JsonElement onTheList))
            Assert.Equal(Seqs(onTheList), listed);
        if (stackCase.TryGetProperty("onTheListCount", out JsonElement count))
        {
            Assert.Equal(count.GetInt32(), listed.Count);
            Assert.Equal(stackCase.GetProperty("oldestOnTheList").GetInt64(), listed[0]);
        }
        if (stackCase.TryGetProperty("onTheDisk", out JsonElement onTheDisk))
            Assert.Equal(Seqs(onTheDisk), folded.OnTheList.Select(step => step.Seq).ToList());
        if (stackCase.TryGetProperty("physicallyPruned", out JsonElement pruned))
            Assert.Equal(Seqs(pruned), folded.Steps.Values.Where(step => step.State == UndoStepState.Pruned).Select(step => step.Seq).ToList());
        if (stackCase.TryGetProperty("interrupted", out JsonElement interrupted))
            Assert.Equal(Seqs(interrupted), folded.Steps.Values.Where(step => step.State == UndoStepState.Interrupted).Select(step => step.Seq).ToList());
        if (stackCase.TryGetProperty("expectLast", out JsonElement expectLast))
            Assert.Equal(expectLast.GetString(), replay.Last);
        if (stackCase.TryGetProperty("cleared", out JsonElement cleared))
            Assert.Contains(cleared.GetString(), replay.Clearings.Select(clearing => clearing.Reason));
        if (stackCase.TryGetProperty("clearedSeq", out JsonElement clearedSeq))
            Assert.Equal(clearedSeq.GetInt64(), replay.Clearings[^1].Seq);
        if (stackCase.TryGetProperty("linesWritten", out JsonElement linesWritten))
            Assert.Equal(linesWritten.GetInt32(), replay.LinesWrittenByTheDeploy);
        if (stackCase.TryGetProperty("blobKept", out JsonElement blobKept))
        {
            Assert.NotNull(replay.ForeignBlob);
            Assert.Equal(blobKept.GetBoolean(), scribe.BlobIsThere(replay.ForeignBlob!));
        }
        if (stackCase.TryGetProperty("markers", out JsonElement markers))
            Assert.Equal(markers.GetString(), UndoKindsForTheCases.Markers(scribe));
        if (stackCase.TryGetProperty("folderKept", out JsonElement folderKept))
            Assert.Equal(folderKept.GetBoolean(), UndoKindsForTheCases.FolderIsThere(scribe));
        if (stackCase.TryGetProperty("rederived", out JsonElement rederived))
            Assert.Equal(rederived.GetInt32(), scribe.Maintainers.Rederived);
        if (stackCase.TryGetProperty("nothingMovedOutside", out JsonElement nothingMoved) && nothingMoved.GetBoolean())
            Assert.Empty(Directory.EnumerateFileSystemEntries(replay.Outside));
        // No case leaves a staged file anywhere in the working folder (stackCasesHow).
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    private static long? NullableSeq(JsonElement element, string key) =>
        element.GetProperty(key).ValueKind == JsonValueKind.Null ? null : element.GetProperty(key).GetInt64();

    private static List<long> Seqs(JsonElement array) => array.EnumerateArray().Select(seq => seq.GetInt64()).ToList();

    /// <summary>The calls of <c>stackCasesHow</c>, one each.</summary>
    private sealed class StackReplay
    {
        private readonly UndoScribe _scribe;
        private readonly string _p1;
        private readonly string _p2;
        private readonly Stack<(long Seq, byte[] After)> _held = new();

        internal StackReplay(UndoScribe scribe)
        {
            _scribe = scribe;
            var fixture = UndoContract.Fixture;
            _p1 = fixture.Single(page => page.Id == "p1").Path;
            _p2 = fixture.Single(page => page.Id == "p2").Path;
            scribe.WriteFixture("A");
            scribe.WriteFixture("B");
        }

        internal string? Last { get; private set; }

        /// <summary>Where <c>linkItsOldFolderOutside</c> points: a folder beside the working folder.</summary>
        internal string Outside => _scribe.FullPath("A", "").TrimEnd(Path.DirectorySeparatorChar) + "-outside";
        internal List<(string Reason, long Seq)> Clearings { get; } = [];
        internal int? LinesWrittenByTheDeploy { get; private set; }
        internal string? ForeignBlob { get; private set; }

        private byte[] Flipped(string folder, string path)
        {
            string text = UndoCheck.DecodeStrictly(_scribe.Page(folder, path)!)!;
            bool published = UndoEntries.ReadingOf("publish", text).Matches("publish: true");
            return Encoding.UTF8.GetBytes(JournaledSetting.SettingEntry("publish", published ? "publish: false" : "publish: true", text)!);
        }

        private void OneStep(string folder, string path, double daysAgo = 0)
        {
            long? seq = _scribe.Step(folder, [(path, Flipped(folder, path))], daysAgo);
            Last = seq is null ? "changedNothing" : "applied";
        }

        internal void Call(string call)
        {
            switch (call)
            {
                case "step": OneStep("A", _p1); return;
                case "stepOn:p2": OneStep("A", _p2); return;
                case "step@B": OneStep("B", _p1); return;
                case "undo":
                {
                    UndoScribe.Outcome outcome = _scribe.Undo();
                    Last = outcome.Name;
                    if (outcome.Cleared is { } reason) Clearings.Add((reason, outcome.ClearedSeq!.Value));
                    return;
                }
                case "redo": Last = _scribe.Redo().Name; return;
                case "editTheLineByHand":
                {
                    string text = UndoCheck.DecodeStrictly(_scribe.Page("A", _p1)!)!;
                    _scribe.WritePage("A", _p1, Encoding.UTF8.GetBytes(UndoTraceEdits.HandEdit("sameLine", text)!));
                    return;
                }
                case "deploy":
                {
                    // What a deploy does to a course: a fragment of the
                    // published-pages record, and nothing to the list.
                    int before = _scribe.LinesOnDisk;
                    string record = _scribe.FullPath("A", "courses/TST1O/.internal/published-pages/section1/20261114T120000Z-netlify.json");
                    Directory.CreateDirectory(Path.GetDirectoryName(record)!);
                    File.WriteAllText(record, "{\"places\":[]}\n");
                    LinesWrittenByTheDeploy = _scribe.LinesOnDisk - before;
                    return;
                }
                case "note": _scribe.Note(); return;
                case "moveFolder:B": _scribe.MoveFolderAway("B"); return;
                case "restoreFolder:B": _scribe.PutFolderBack("B"); return;
                case "foreignLine":
                {
                    long seq = _scribe.Fold().NextSeq;
                    _scribe.AppendRaw($"{{\"v\":2,\"seq\":{seq},\"event\":\"somethingNew\",\"at\":\"{UndoMoment.Format(_scribe.Clock.GetUtcNow())}\"}}");
                    return;
                }
                case "foreignStep":
                {
                    long seq = _scribe.Fold().NextSeq;
                    ForeignBlob = _scribe.PutBlob(Encoding.UTF8.GetBytes("a listing a newer version kept\n"));
                    var ops = new JsonArray(new JsonObject
                    {
                        ["kind"] = "aKindNobodyKnows", ["from"] = "courses/TST1O/a.md", ["to"] = "courses/TST1O/b.md",
                        ["blobs"] = new JsonArray(ForeignBlob),
                    });
                    _scribe.Append(_scribe.BeginLine(seq, ops, "A"));
                    _scribe.Event(seq, "applied");
                    return;
                }
                case "foreignBlobLine":
                {
                    long seq = _scribe.Fold().NextSeq;
                    ForeignBlob = _scribe.PutBlob(Encoding.UTF8.GetBytes("content a newer version needs\n"));
                    string at = UndoMoment.Format(_scribe.Clock.GetUtcNow());
                    _scribe.AppendRaw($"{{\"v\":2,\"seq\":{seq},\"event\":\"begin\",\"at\":\"{at}\",\"step\":{{\"seq\":{seq},\"ops\":[{{\"kind\":\"somethingNew\",\"blobs\":[\"{ForeignBlob}\"]}}]}}}}");
                    _scribe.AppendRaw($"{{\"v\":2,\"seq\":{seq},\"event\":\"applied\",\"at\":\"{at}\"}}");
                    _scribe.Prune();
                    return;
                }
                case "goLive":
                {
                    if (_scribe.GoLive() is { } seq) Clearings.Add(("wentLive", seq));
                    return;
                }
                case "wholeFileStep":
                {
                    byte[] after = [.. Flipped("A", _p1), .. Encoding.UTF8.GetBytes("A line the step added.\n")];
                    long seq = _scribe.Step("A", [(_p1, after)])!.Value;
                    Assert.Equal(UndoOp.WriteFile, _scribe.Fold().Steps[seq].Step.Ops.Single().Kind);
                    Last = "applied";
                    return;
                }
                case "removeContent": _scribe.RemoveContent(); return;
                case "begin:held": BeginHeld(); return;
                case "finish:held":
                {
                    (long seq, byte[] after) = _held.Pop();
                    _scribe.WritePage("A", _p1, after);
                    _scribe.Finish(seq);
                    return;
                }
                case "undoWhileAStepBegins":
                {
                    // Another process begins a step after this undo has checked
                    // its ops and before it answers.
                    UndoScribe.Outcome outcome = _scribe.Undo(afterTheCheck: BeginHeld);
                    Last = outcome.Name;
                    if (outcome.Cleared is { } reason) Clearings.Add((reason, outcome.ClearedSeq!.Value));
                    return;
                }
                case "moveTheMarker":
                {
                    if (_scribe.Page("A", UndoKindsForTheCases.MarkerFrom) is null && _scribe.Page("A", UndoKindsForTheCases.MarkerTo) is null)
                        _scribe.WritePage("A", UndoKindsForTheCases.MarkerFrom, Encoding.UTF8.GetBytes(UndoKindsForTheCases.OldMarker));
                    byte[] content = _scribe.Page("A", UndoKindsForTheCases.MarkerFrom) ?? [];
                    Ops(new JsonArray(UndoKindsForTheCases.MoveFile(UndoKindsForTheCases.MarkerFrom, UndoKindsForTheCases.MarkerTo, content)), []);
                    return;
                }
                case "deployANewMarker":
                    // What a deploy after a rollover onto a new website does: a
                    // new marker in the place the rollover emptied, nothing in the list.
                    _scribe.WritePage("A", UndoKindsForTheCases.MarkerFrom, Encoding.UTF8.GetBytes(UndoKindsForTheCases.NewMarker));
                    return;
                case "makeAFolder":
                {
                    (UndoTreeListing listing, List<byte[]> contents) = UndoKindsForTheCases.ExtraListing();
                    (JsonObject op, List<byte[]> blobs) = UndoKindsForTheCases.Tree("createTree", UndoKindsForTheCases.ExtraFolder, listing, contents);
                    Ops(new JsonArray(op), blobs, "newFolder");
                    return;
                }
                case "addAFileToTheFolder":
                    _scribe.WritePage("A", UndoKindsForTheCases.ExtraFolder + "/c.md", "C\n"u8.ToArray());
                    return;
                case "removeTheFolder":
                {
                    if (UndoTreeReading.Read(_scribe.FullPath("A", UndoKindsForTheCases.ExtraFolder), keepingContents: true) is not UndoTreeReading.Tree tree)
                    {
                        Last = "noFolderToRemove";
                        return;
                    }
                    (JsonObject op, List<byte[]> blobs) = UndoKindsForTheCases.Tree("removeTree", UndoKindsForTheCases.ExtraFolder, tree.Listing, tree.Contents.Values);
                    Ops(new JsonArray(op), blobs, "removeFolder");
                    return;
                }
                case "editTheSettings":
                {
                    if (_scribe.Page("A", UndoKindsForTheCases.Settings) is null)
                        _scribe.WritePage("A", UndoKindsForTheCases.Settings, "{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n"u8.ToArray());
                    UndoJsonMember.Reading reading = UndoJsonMember.ReadingOf(["school_year"], _scribe.Page("A", UndoKindsForTheCases.Settings)!);
                    var op = new JsonObject { ["kind"] = "editJSON", ["path"] = UndoKindsForTheCases.Settings, ["keyPath"] = new JsonArray("school_year") };
                    string after = "2026-2027";
                    if (reading.Value is UndoJson.Text text)
                    {
                        op["before"] = text.Value;
                        if (text.Value == "2026-2027") after = "2025-2026";
                    }
                    op["after"] = after;
                    Ops(new JsonArray(op), [], "setSchoolYear");
                    return;
                }
                case "editTheSettingsByHand":
                    _scribe.WritePage("A", UndoKindsForTheCases.Settings, "{\"course_name\": \"Test\", \"school_year\": \"2030-2031\"}\n"u8.ToArray());
                    return;
                case "editAHunk":
                {
                    if (_scribe.Page("A", UndoKindsForTheCases.Notes) is null)
                        _scribe.WritePage("A", UndoKindsForTheCases.Notes, "Intro.\nLine one: old.\nEnd.\n"u8.ToArray());
                    bool isNew = UndoKindsForTheCases.Text(_scribe.Page("A", UndoKindsForTheCases.Notes))!.Contains("Line one: new.", StringComparison.Ordinal);
                    var op = new JsonObject
                    {
                        ["kind"] = "replaceText", ["path"] = UndoKindsForTheCases.Notes, ["before"] = isNew ? "new" : "old", ["after"] = isNew ? "old" : "new",
                        ["contextBefore"] = "Line one: ", ["contextAfter"] = ".\n",
                    };
                    Ops(new JsonArray(op), [], "editPage");
                    return;
                }
                case "setAPreference":
                {
                    UndoExternalReading now = _scribe.Places.Read(UndoKindsForTheCases.Preference);
                    JsonObject op = now.Value is UndoJson.Text text
                        ? UndoKindsForTheCases.External(UndoKindsForTheCases.Preference, text.Value, text.Value == "b" ? "a" : "b")
                        : UndoKindsForTheCases.External(UndoKindsForTheCases.Preference, null, "b", hasBefore: false);
                    Last = _scribe.Door().Perform(_scribe.OpsDraft(null, new JsonArray(op), [], "setPreference")).Word;
                    return;
                }
                case "changeThePreferenceByHand":
                    _scribe.Places.Write(UndoKindsForTheCases.Preference, new UndoJson.Text("z"));
                    return;
                case "forgetTheMaintainer":
                    _scribe.Maintainers.Forgotten = true;
                    return;
                case "moveThePageAside":
                {
                    if (_scribe.Page("A", UndoKindsForTheCases.AsidePage) is null)
                        _scribe.WritePage("A", UndoKindsForTheCases.AsidePage, "page\n"u8.ToArray());
                    Ops(new JsonArray(UndoKindsForTheCases.MoveFile(UndoKindsForTheCases.AsidePage, UndoKindsForTheCases.AsidePageMoved, "page\n"u8.ToArray())), []);
                    return;
                }
                case "linkItsOldFolderOutside":
                {
                    // The folder the page was moved out of, replaced by a
                    // junction to a folder outside the working folder.
                    string old = _scribe.FullPath("A", "courses/TST1O/old");
                    if (Directory.Exists(old)) Directory.Delete(old, recursive: true);
                    Directory.CreateDirectory(Outside);
                    UndoKindsForTheCases.MakeAJunction(old, Outside);
                    return;
                }
                case "begin:dead@B":
                {
                    byte[] after = Flipped("B", _p1);
                    long seq = _scribe.Fold().NextSeq;
                    JsonArray ops = _scribe.OpsFor(_p1, _scribe.Page("B", _p1), after);
                    _scribe.Append(_scribe.BeginLine(seq, ops, "B", pid: UndoScribe.AProcessThatIsGone));
                    return;
                }
            }

            if (call.StartsWith("step:", StringComparison.Ordinal) && call.EndsWith("daysAgo", StringComparison.Ordinal))
            {
                OneStep("A", _p1, double.Parse(call["step:".Length..^"daysAgo".Length], System.Globalization.CultureInfo.InvariantCulture));
                return;
            }
            if (call.StartsWith("steps:", StringComparison.Ordinal))
            {
                int count = int.Parse(call["steps:".Length..], System.Globalization.CultureInfo.InvariantCulture);
                for (int index = 0; index < count; index++) OneStep("A", _p1);
                return;
            }
            if (call.StartsWith("clock:", StringComparison.Ordinal))
            {
                _scribe.Clock.SetDaysFromStart(double.Parse(call["clock:".Length..], System.Globalization.CultureInfo.InvariantCulture));
                return;
            }
            if (call.StartsWith("cleared:", StringComparison.Ordinal))
            {
                string reason = call["cleared:".Length..];
                long highest = _scribe.Fold().Highest;
                _scribe.Event(highest, "cleared", new JsonObject { ["reason"] = reason });
                Clearings.Add((reason, highest));
                return;
            }
            if (call.StartsWith("stepFromAnotherVersion:", StringComparison.Ordinal))
            {
                StepFromAnotherVersion(call["stepFromAnotherVersion:".Length..]);
                return;
            }
            Assert.Fail("a call this replay does not know: " + call);
        }

        /// <summary>A step given as its ops, through the door that plans it forward as a Redo would (<c>Perform(UndoOpsDraft)</c>).</summary>
        private void Ops(JsonArray ops, IReadOnlyList<byte[]> blobs, string action = "rollOver") =>
            Last = _scribe.Door().Perform(_scribe.OpsDraft("A", ops, blobs, action)).Word;

        private void BeginHeld()
        {
            byte[] after = Flipped("A", _p1);
            long seq = _scribe.Fold().NextSeq;
            JsonArray ops = _scribe.OpsFor(_p1, _scribe.Page("A", _p1), after);
            _scribe.MarkAlive(UndoScribe.AnotherRunningProcess);
            _scribe.Append(_scribe.BeginLine(seq, ops, "A", pid: UndoScribe.AnotherRunningProcess));
            _held.Push((seq, after));
        }

        private void StepFromAnotherVersion(string variant)
        {
            byte[] after = Flipped("A", _p1);
            long seq = _scribe.Fold().NextSeq;
            JsonArray ops = _scribe.OpsFor(_p1, _scribe.Page("A", _p1), after);
            JsonObject begin = _scribe.BeginLine(seq, ops, "A");
            JsonObject step = begin["step"]!.AsObject();
            step["class"] = "A";
            var front = new JsonObject { ["kind"] = "recompute", ["path"] = "courses/TST1O/Section 1/index.md", ["section"] = 1 };
            switch (variant)
            {
                case "theFrontPageMaintainer": front["maintainer"] = "sectionFrontPage"; ops.Add(front); break;
                case "aMaintainerNobodyKnows": front["maintainer"] = "aMaintainerNobodyKnows"; ops.Add(front); break;
                case "aHoldsNobodyKnows": step["holds"] = "workingFolder"; break;
                case "openStrings":
                    step["madeBy"] = "outsideAssistant:A client: with colons:session-7";
                    step["class"] = "Z";
                    step["action"] = new JsonObject { ["key"] = "aKeyNobodyKnows", ["arguments"] = new JsonObject() };
                    Assert.Equal(new UndoMadeBy("outsideAssistant", "A client: with colons", "session-7"),
                                 UndoMadeBy.Split(step["madeBy"]!.GetValue<string>()));
                    break;
                case "aKeyOnAKnownOp": ops[0]!["onlyWhen"] = "aConditionNobodyKnows"; break;
                case "twoWholeOpsOnOnePlace":
                {
                    // Breaks opKinds.wholeOps: a folder made inside another
                    // folder the same step makes.
                    var empty = new UndoTreeListing([], []);
                    foreach (string path in new[] { "courses/TST1O/made", "courses/TST1O/made/inner" })
                        ops.Add(new JsonObject { ["kind"] = "createTree", ["path"] = path, ["listingSha"] = empty.Sha, ["blobs"] = new JsonArray(empty.Sha) });
                    break;
                }
                default: Assert.Fail("a variant this replay does not know: " + variant); break;
            }
            _scribe.Append(begin);
            _scribe.WritePage("A", _p1, after);
            _scribe.Finish(seq);
        }
    }
}
