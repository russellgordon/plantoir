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

    [Theory]
    [MemberData(nameof(Cases))]
    public void EveryStackCase(string name)
    {
        JsonElement stackCase = UndoContract.Undo.GetProperty("stackCases").EnumerateArray()
            .Single(candidate => candidate.GetProperty("name").GetString() == name);
        foreach (JsonProperty key in stackCase.EnumerateObject()) Assert.Contains(key.Name, KeysChecked);

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
        internal List<(string Reason, long Seq)> Clearings { get; } = [];
        internal int? LinesWrittenByTheDeploy { get; private set; }
        internal string? ForeignBlob { get; private set; }

        private byte[] Flipped(string folder, string path)
        {
            string text = UndoCheck.DecodeStrictly(_scribe.Page(folder, path)!)!;
            bool published = UndoEntries.ReadingOf("publish", text).Matches("publish: true");
            return Encoding.UTF8.GetBytes(UndoLineOps.SettingEntry("publish", published ? "publish: false" : "publish: true", text)!);
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
                    _scribe.WritePage("A", _p1, Encoding.UTF8.GetBytes(UndoLineOps.HandEdit("sameLine", text)!));
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
                        ["kind"] = "move", ["from"] = "courses/TST1O/a.md", ["to"] = "courses/TST1O/b.md",
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
                    if (_scribe.Clear("wentLive") is { } seq) Clearings.Add(("wentLive", seq));
                    _scribe.Prune();
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
                default: Assert.Fail("a variant this replay does not know: " + variant); break;
            }
            _scribe.Append(begin);
            _scribe.WritePage("A", _p1, after);
            _scribe.Finish(seq);
        }
    }
}
