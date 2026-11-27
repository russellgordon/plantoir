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
        // U3c's (W4c)
        "keptOriginalLeft", "foreignKeptOriginalUntouched", "keptWhatItReplacedLines", "why",
        // U4b2-2's (W8-1)
        "refusalNamed",
        // U4b's (W8-2)
        "movedFolder",
        // U4b2-10's (W8-4)
        "madeFolder", "foldersInside",
        // U4b part C's (W8-5)
        "caseOnlyFolder",
        // U4b2-14's (W8-6)
        "linkedFolder",
        // U4b2-4's (W8-9)
        "keptWhatItReplacedSays",
        // U4a review 1, LOW 4's (W8-10)
        "keptBesideThePage",
    };

    /// <summary>Every case but those that lay a symbolic link (<see cref="LinkCases"/>).</summary>
    public static IEnumerable<object[]> Cases() =>
        UndoContract.Undo.GetProperty("stackCases").EnumerateArray()
            .Where(stackCase => !LaysASymbolicLink(stackCase))
            .Select(stackCase => new object[] { stackCase.GetProperty("name").GetString()! });

    /// <summary>
    /// The cases whose calls lay a symbolic link holding <c>../library</c> as
    /// written (<c>moveALinkToAFolder</c>, U4b2-14; #899 W8-6): run where this
    /// account may make one, SKIPPED saying why where it may not (the VMs).
    /// </summary>
    public static IEnumerable<object[]> LinkCases() =>
        UndoContract.Undo.GetProperty("stackCases").EnumerateArray()
            .Where(LaysASymbolicLink)
            .Select(stackCase => new object[] { stackCase.GetProperty("name").GetString()! });

    private static bool LaysASymbolicLink(JsonElement stackCase) =>
        stackCase.GetProperty("calls").EnumerateArray().Any(call => call.GetString() == "moveALinkToAFolder");

    [Fact]
    public void TheContractHoldsTheStackCases()
    {
        // 46 when W1 was written; a count that falls is a contract change to read, never a silent pass.
        Assert.True(UndoContract.Undo.GetProperty("stackCases").GetArrayLength() >= 46);
        Assert.Equal(UndoContract.Undo.GetProperty("stackCases").GetArrayLength(), Cases().Count() + LinkCases().Count());
    }

    /// <summary>Every case held open by name is a case the contract still has (none since W6).</summary>
    [Fact]
    public void EveryHeldStackCaseIsStillInTheContract() =>
        NamedGapLedger.StillNamed(NamedGapLedger.UndoStackCases, Cases().Concat(LinkCases()).Select(row => (string)row[0]));

    /// <summary>
    /// Every case, asserted in full, U2's calls and keys included (W6). A case
    /// the ledger holds open (a call or a key a later piece brings) must still
    /// stop at that call or key, and goes from the ledger the day it passes.
    /// </summary>
    [Theory]
    [MemberData(nameof(Cases))]
    public void EveryStackCase(string name) => RunAsTheLedgerSays(name, NamedGapLedger.All, () => WalkTheCase(name));

    /// <summary><see cref="EveryStackCase"/> for the cases that lay a symbolic link.</summary>
    [SymbolicLinkTheory]
    [MemberData(nameof(LinkCases))]
    public void EveryLinkStackCase(string name) => RunAsTheLedgerSays(name, NamedGapLedger.All, () => WalkTheCase(name));

    /// <summary>
    /// One case, walked by <paramref name="walk"/>, held or not as
    /// <paramref name="entries"/> say. <see cref="EveryStackCase"/> passes the
    /// real walk; a held case that plays through fails as its gap closing.
    /// </summary>
    private static void RunAsTheLedgerSays(string name, IEnumerable<NamedGapLedger.Entry> entries, Action walk)
    {
        if (NamedGapLedger.Holding(NamedGapLedger.UndoStackCases, name, entries) is { } held)
        {
            NamedGapLedger.HeldCaseStillStopsAtItsGap(held, walk, "this replay does not know", "this replay does not check",
                                                      "is not built on Windows yet");
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
        using var denials = new UndoDenials();
        var replay = new StackReplay(scribe, denials);
        foreach (JsonElement call in stackCase.GetProperty("calls").EnumerateArray()) replay.Call(call.GetString()!);
        // Every deny entry goes before the checks read the disk.
        denials.Dispose();

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
        if (stackCase.TryGetProperty("movedFolder", out JsonElement movedFolder))
            Assert.Equal(movedFolder.GetString(), replay.MovedFolder());
        if (stackCase.TryGetProperty("linkedFolder", out JsonElement linkedFolder))
            Assert.Equal(linkedFolder.GetString(), replay.LinkedFolder());
        if (stackCase.TryGetProperty("caseOnlyFolder", out JsonElement caseOnlyFolder))
            Assert.Equal(caseOnlyFolder.GetString(), replay.CaseOnlyFolder());
        if (stackCase.TryGetProperty("madeFolder", out JsonElement madeFolder))
            Assert.Equal(madeFolder.GetString(), replay.MadeFolder());
        if (stackCase.TryGetProperty("foldersInside", out JsonElement foldersInside))
            Assert.Equal(foldersInside.GetString(), replay.FoldersInside());
        if (stackCase.TryGetProperty("refusalNamed", out JsonElement refusalNamed))
            Assert.Equal(refusalNamed.GetString(), replay.RefusalNamed);
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
        // U3c's keys (W4c).
        if (stackCase.TryGetProperty("keptWhatItReplacedLines", out JsonElement keptLines))
        {
            int said;
            lock (scribe.TrailLines) said = scribe.TrailLines.Count(line => line.Event == Plantoir.Core.Scripting.ActivityTrail.Event.UndoKeptWhatItReplaced);
            Assert.Equal(keptLines.GetInt32(), said);
        }
        if (stackCase.TryGetProperty("keptWhatItReplacedSays", out JsonElement keptSays))
        {
            UndoTrailLine? last = null;
            lock (scribe.TrailLines)
            {
                foreach (UndoTrailLine line in scribe.TrailLines)
                {
                    if (line.Event == Plantoir.Core.Scripting.ActivityTrail.Event.UndoKeptWhatItReplaced) last = line;
                }
            }
            Assert.NotNull(last);
            Assert.Equal(keptSays.GetString(), AsTheTrailWritesIt(last!));
        }
        if (stackCase.TryGetProperty("keptBesideThePage", out JsonElement keptBeside))
            CheckTheFilesKeptBesideThePage(keptBeside.GetInt32(), replay.KeptBesideP1());
        if (stackCase.TryGetProperty("foreignKeptOriginalUntouched", out JsonElement untouched) && untouched.GetBoolean())
        {
            Assert.NotNull(replay.ForeignKept);
            Assert.True(scribe.Page("A", replay.ForeignKept!.Value.Relative) is { } foreign && foreign.AsSpan().SequenceEqual(replay.ForeignKept.Value.Bytes),
                        "the other list's kept original was changed or removed");
        }
        // No case leaves a staged file anywhere in the working folder
        // (stackCasesHow), but a kept original where keptOriginalLeft says so.
        List<string> leftovers = scribe.StagedLeftovers("A");
        bool keptOriginalLeft = stackCase.TryGetProperty("keptOriginalLeft", out JsonElement keptLeft) && keptLeft.GetBoolean();
        foreach (string leftover in leftovers)
            Assert.True(keptOriginalLeft && leftover.EndsWith("-orig", StringComparison.Ordinal), "a staged file left behind: " + leftover);
        if (stackCase.TryGetProperty("keptOriginalLeft", out _))
            Assert.Equal(keptOriginalLeft, leftovers.Count > 0);
    }

    /// <summary>
    /// <c>keptBesideThePage</c>: how many files are kept beside p1. When there
    /// are more than wanted and some hold a content another of them holds, the
    /// failure names the gap it is: kept copies are not yet thinned to one per
    /// content per page on Windows (the mac's
    /// <c>UndoRecovery.removeSupersededKeptCopies</c>; #899 W8-10 left it for a
    /// piece of its own). The piece that builds the thinning takes that branch
    /// out, so only the plain count is left.
    /// </summary>
    private static void CheckTheFilesKeptBesideThePage(int wanted, List<string> kept)
    {
        if (kept.Count == wanted) return;
        var contents = new HashSet<string>(StringComparer.Ordinal);
        foreach (string file in kept) contents.Add(UndoCheck.Sha(File.ReadAllBytes(file)));
        if (kept.Count > wanted && contents.Count < kept.Count)
            Assert.Fail($"{kept.Count} files kept beside the page, not {wanted}: they hold {contents.Count} contents, and the thinning " +
                        "of kept copies to one per content per page is not built on Windows yet");
        Assert.Fail($"{kept.Count} files kept beside the page, not {wanted}");
    }

    /// <summary>
    /// A line as the activity trail writes it after its stamp, course and
    /// section first (<see cref="UndoTrail.ToTheActivityTrail"/>, through
    /// <see cref="Plantoir.Core.Scripting.ActivityTrail.Place"/>):
    /// <c>keptWhatItReplacedSays</c> is the whole line.
    /// </summary>
    private static string AsTheTrailWritesIt(UndoTrailLine line)
    {
        if (string.IsNullOrEmpty(line.Course)) return line.Words;
        if (line.Section is { } section and >= 0 and <= int.MaxValue)
            return Plantoir.Core.Scripting.ActivityTrail.Place(line.Course, (int)section) + line.Words;
        return line.Course + " · " + line.Words;
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

        private readonly UndoDenials _denials;

        internal StackReplay(UndoScribe scribe, UndoDenials denials)
        {
            _scribe = scribe;
            _denials = denials;
            var fixture = UndoContract.Fixture;
            _p1 = fixture.Single(page => page.Id == "p1").Path;
            _p2 = fixture.Single(page => page.Id == "p2").Path;
            scribe.WriteFixture("A");
            scribe.WriteFixture("B");
        }

        internal string? Last { get; private set; }

        /// <summary>The first place the last undo or redo's changedSince refusal named (<c>refusalNamed</c>); null when it was not so refused.</summary>
        internal string? RefusalNamed { get; private set; }

        /// <summary>Where <c>linkItsOldFolderOutside</c> points: a folder beside the working folder.</summary>
        internal string Outside => _scribe.FullPath("A", "").TrimEnd(Path.DirectorySeparatorChar) + "-outside";
        internal List<(string Reason, long Seq)> Clearings { get; } = [];
        internal int? LinesWrittenByTheDeploy { get; private set; }
        internal string? ForeignBlob { get; private set; }
        internal (string Relative, byte[] Bytes)? ForeignKept { get; private set; }

        /// <summary>The newest step's writeFile op on p1, for the U3c calls.</summary>
        private (long Seq, UndoOp Op) HeadWriteFileOnP1() => HeadWriteFileOn(_p1);

        /// <summary>The two pages of <c>wholeFileStepOnTwoPagesNamedIndex</c> (stackCasesHow, U4b2-4).</summary>
        private static readonly string[] TwoIndexes = ["courses/TST1O/Section 1/Classes/index.md", "courses/TST1O/Section 2/Classes/index.md"];

        /// <summary>The newest step's writeFile op on <paramref name="path"/>.</summary>
        private (long Seq, UndoOp Op) HeadWriteFileOn(string path)
        {
            UndoFoldedStep head = _scribe.Offer().Head ?? throw new InvalidOperationException("no step on the list");
            foreach (UndoOp op in head.Step.Ops)
            {
                if (op.Kind == UndoOp.WriteFile && op.Path == path) return (head.Seq, op);
            }
            throw new InvalidOperationException("no whole-file step on " + path);
        }

        /// <summary>One content gone from the list, and the list's folder that held it taking no new file.</summary>
        private void TakeAwayContent(string sha)
        {
            string blob = _scribe.Journal.BlobPath(sha);
            File.Delete(blob);
            _denials.FolderTakesNothingNew(Path.GetDirectoryName(blob)!);
        }

        /// <summary>
        /// Every file kept beside p1 under a staged name ending <c>-orig</c>,
        /// of any step, in p1's own folder (<c>keptBesideThePage</c>,
        /// stackCasesHow, U4a review 1, LOW 4): its full paths.
        /// </summary>
        internal List<string> KeptBesideP1()
        {
            string page = _scribe.FullPath("A", _p1);
            string prefix = "." + Path.GetFileName(page) + UndoSwap.StagedMarker;
            var kept = new List<string>();
            foreach (string entry in Directory.EnumerateFileSystemEntries(Path.GetDirectoryName(page)!))
            {
                string name = Path.GetFileName(entry);
                if (name.StartsWith(prefix, StringComparison.Ordinal) && name.EndsWith("-orig", StringComparison.Ordinal)) kept.Add(entry);
            }
            return kept;
        }

        /// <summary>Every kept original beside p1, as their relative paths.</summary>
        private List<string> KeptOriginalsBesideP1()
        {
            var kept = new List<string>();
            foreach (string staged in _scribe.StagedLeftovers("A"))
            {
                if (staged.EndsWith("-orig", StringComparison.Ordinal)) kept.Add(staged);
            }
            return kept;
        }

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
                    RefusalNamed = outcome.Name == "changedSince" ? outcome.Page : null;
                    if (outcome.Cleared is { } reason) Clearings.Add((reason, outcome.ClearedSeq!.Value));
                    return;
                }
                case "redo":
                {
                    UndoScribe.Outcome outcome = _scribe.Redo();
                    Last = outcome.Name;
                    RefusalNamed = outcome.Name == "changedSince" ? outcome.Page : null;
                    return;
                }
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
                case "wholeFileStepOnTwoPagesNamedIndex":
                {
                    // Two pages named index.md in two sections, each written
                    // whole by one step of TST1O, section 1 (stackCasesHow, U4b2-4).
                    var changes = new List<(string Path, byte[]? After)>();
                    foreach (string page in TwoIndexes)
                    {
                        _scribe.WritePage("A", page, Encoding.UTF8.GetBytes($"What {page} held before the step.\n"));
                        changes.Add((page, Encoding.UTF8.GetBytes($"What the step left in {page}.\n")));
                    }
                    long seq = _scribe.Step("A", changes)!.Value;
                    foreach (UndoOp op in _scribe.Fold().Steps[seq].Step.Ops) Assert.Equal(UndoOp.WriteFile, op.Kind);
                    Last = "applied";
                    return;
                }
                case "firstIndexAfterContentGoneAndCannotBeStored":
                    TakeAwayContent(HeadWriteFileOn(TwoIndexes[0]).Op.AfterSha!);
                    return;
                case "secondIndexBeforeContentGoneAndCannotBeStored":
                    TakeAwayContent(HeadWriteFileOn(TwoIndexes[1]).Op.BeforeSha!);
                    return;
                case "keepTheOriginalOfTheSecondIndex":
                {
                    // What the second page held before, beside it as the newest
                    // step's kept original. Its content is gone from the list,
                    // so it is written from what the first call wrote there.
                    (long seq, _) = HeadWriteFileOn(TwoIndexes[1]);
                    File.WriteAllBytes(UndoSwap.BesidePath(_scribe.FullPath("A", TwoIndexes[1]), $"{seq}-apply", "orig"),
                                       Encoding.UTF8.GetBytes($"What {TwoIndexes[1]} held before the step.\n"));
                    return;
                }
                case "afterContentGone":
                {
                    // Only the newest step's content for what p1 holds after
                    // it is gone from the list; the list still takes a new
                    // file unless contentCannotBeStored follows (U4a review 1,
                    // LOW 4). The blob's own folder goes too when that leaves
                    // it empty, as on the mac, so a sealed content folder
                    // cannot take the blob again.
                    string blob = _scribe.Journal.BlobPath(HeadWriteFileOnP1().Op.AfterSha!);
                    Assert.True(File.Exists(blob), "no after content of p1's newest whole-file step in the list to take away");
                    File.Delete(blob);
                    string prefixFolder = Path.GetDirectoryName(blob)!;
                    if (!Directory.EnumerateFileSystemEntries(prefixFolder).Any()) Directory.Delete(prefixFolder);
                    return;
                }
                case "removeContent": _scribe.RemoveContent(); return;
                case "contentCannotBeStored":
                    // The list's content folder, there and taking no new file
                    // (a full or read-only disk, as far as the list can tell).
                    _denials.FolderTakesNothingNew(Path.Combine(_scribe.JournalFolder, "content"));
                    return;
                case "beforeContentGoneAndCannotBeStored":
                {
                    // Only the newest step's content for what p1 held before
                    // is gone, and its folder in the list takes no new file.
                    TakeAwayContent(HeadWriteFileOnP1().Op.BeforeSha!);
                    return;
                }
                case "keepTheOriginal":
                {
                    // The newest step's kept original of p1, as a swap whose
                    // tidy could not remove it leaves it: what p1 held before.
                    (long seq, UndoOp op) = HeadWriteFileOnP1();
                    byte[] before = _scribe.Journal.Blob(op.BeforeSha!)!;
                    File.WriteAllBytes(UndoSwap.BesidePath(_scribe.FullPath("A", _p1), $"{seq}-apply", "orig"), before);
                    return;
                }
                case "foreignKeptOriginal":
                {
                    // A kept original left under the next step's own label by
                    // another computer or an earlier list.
                    long next = _scribe.Fold().NextSeq;
                    string foreign = UndoSwap.BesidePath(_scribe.FullPath("A", _p1), $"{next}-apply", "orig");
                    byte[] bytes = "What another computer's list kept.\n"u8.ToArray();
                    File.WriteAllBytes(foreign, bytes);
                    ForeignKept = (Path.GetRelativePath(_scribe.FullPath("A", ""), foreign).Replace('\\', '/'), bytes);
                    return;
                }
                case "makeTheKeptOriginalUnreadable":
                    foreach (string kept in KeptOriginalsBesideP1()) _denials.FileCannotBeRead(kept);
                    return;
                case "changeTheKeptOriginal":
                    foreach (string kept in KeptOriginalsBesideP1()) File.AppendAllText(kept, "A line added to the kept original.\n");
                    return;
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
                case "linkItsOldFolderOutside": LinkOutside("courses/TST1O/old"); return;
                // U4b2-2 (W8-1): the folder the page was moved into, replaced
                // by a junction to the same folder outside.
                case "linkItsNewFolderOutside": LinkOutside("courses/TST1O/new"); return;
                case "moveThePageIntoAFolder": MoveThePage("courses/TST1O/b.md", "courses/TST1O/new/b.md"); return;
                case "moveThePageBetweenFolders": MoveThePage("courses/TST1O/old/c.md", "courses/TST1O/new/c.md"); return;
                // U4b (W8-2): a folder move carrying an edit of a page inside it.
                case "moveAFolderWithAPageEditedInside":
                {
                    if (_scribe.Page("A", MediaFolder + "/a.md") is null && _scribe.Page("A", RenamedFolder + "/a.md") is null)
                    {
                        _scribe.WritePage("A", MediaFolder + "/a.md", "Intro.\nLine one: old.\nEnd.\n"u8.ToArray());
                        _scribe.WritePage("A", MediaFolder + "/b.md", "B\n"u8.ToArray());
                    }
                    Ops(new JsonArray(MoveTheMediaFolder(), EditInside(RenamedFolder + "/a.md")), []);
                    return;
                }
                // U4b2-10 (W8-4): a carried edit makes a folder inside the moved folder.
                case "moveAFolderWithAFileMadeInANewFolderInside":
                    MakeTheMediaFolder(withAnEmptySub: false);
                    MoveCarrying(("sub/x.md", "X\n"));
                    return;
                case "addAFolderInsideTheMadeFolder": _scribe.WritePage("A", RenamedFolder + "/sub/mine/y.md", "Y\n"u8.ToArray()); return;
                case "moveAFolderHoldingAnEmptyFolderAndMakingAFolderInIt":
                    MakeTheMediaFolder(withAnEmptySub: true);
                    MoveCarrying(("sub/deeper/x.md", "X\n"));
                    return;
                case "moveAFolderHoldingAnEmptyFolderAndMakingFilesInItAndBesideIt":
                    MakeTheMediaFolder(withAnEmptySub: true);
                    MoveCarrying(("sub/x.md", "X\n"), ("new/y.md", "Y\n"));
                    return;
                case "finderRecordsAWindowInTheMadeFolder":
                    File.WriteAllBytes(_scribe.FullPath("A", RenamedFolder + "/sub/" + UndoTreeListing.IgnoredName), "Finder"u8.ToArray());
                    return;
                // U4b part C (W8-5): a capitalisation-only rename carrying an edit inside.
                case "renameAFolderInCaseOnly":
                {
                    if (CaseOnlySpellingListed() is null)
                    {
                        _scribe.WritePage("A", CaseOnlyOld + "/a.md", "Intro.\nLine one: old.\nEnd.\n"u8.ToArray());
                        _scribe.WritePage("A", CaseOnlyOld + "/b.md", "B\n"u8.ToArray());
                    }
                    string listingSha = UndoTreeReading.Read(_scribe.FullPath("A", CaseOnlyOld)).ListingSha!;
                    var move = new JsonObject { ["kind"] = "move", ["from"] = CaseOnlyOld, ["to"] = MediaFolder, ["listingSha"] = listingSha };
                    Ops(new JsonArray(move, EditInside(MediaFolder + "/a.md")), []);
                    return;
                }
                // U4b2-14 (W8-6): a symbolic link to a folder moved as itself.
                case "moveALinkToAFolder":
                {
                    string media = _scribe.FullPath("A", LinkPlace);
                    if (UndoLinks.Look(media) == UndoLinks.What.Nothing && UndoLinks.Look(_scribe.FullPath("A", LinkRenamed)) == UndoLinks.What.Nothing)
                    {
                        _scribe.WritePage("A", LinkLibrary + "/a.md", "A"u8.ToArray());
                        _scribe.WritePage("A", LinkLibrary + "/pictures/b.md", "B"u8.ToArray());
                        _libraryListing = UndoTreeReading.Read(_scribe.FullPath("A", LinkLibrary)).ListingSha;
                        Directory.CreateDirectory(Path.GetDirectoryName(media)!);
                        Directory.CreateSymbolicLink(media, LinkTarget);
                    }
                    Ops(new JsonArray(TheLinksMove()), []);
                    return;
                }
                // Review 1 of U4b2-14: that link's move with an edit inside its new place, changing nothing.
                case "stepEditingInsideALinksMove":
                {
                    long seq = _scribe.Fold().NextSeq;
                    _scribe.Append(_scribe.BeginLine(seq, new JsonArray(TheLinksMove(), EditInside(LinkRenamed + "/a.md")), "A"));
                    _scribe.Finish(seq);
                    return;
                }
                case "spellTheFolderAnotherWay":
                    Assert.Equal(0, UndoSwap.Rename(_scribe.FullPath("A", MediaFolder), _scribe.FullPath("A", "courses/TST1O/MEDIA"), replace: false));
                    return;
                case "addAFileInsideTheMovedFolder": _scribe.WritePage("A", RenamedFolder + "/c.md", "C\n"u8.ToArray()); return;
                case "editThePageInsideByHand": _scribe.WritePage("A", RenamedFolder + "/a.md", "Hand.\n"u8.ToArray()); return;
                // U4b, M1 (W8-3): the newest step's own kept original from an
                // undo, beside a.md wherever the folder is now, an only copy.
                case "leaveAKeptCopyInsideTheMovedFolder":
                {
                    string folder = Directory.Exists(_scribe.FullPath("A", RenamedFolder)) ? RenamedFolder : MediaFolder;
                    long seq = _scribe.Fold().NextSeq - 1;
                    File.WriteAllBytes(UndoSwap.BesidePath(_scribe.FullPath("A", folder + "/a.md"), $"{seq}-undo", "orig"), "Kept.\n"u8.ToArray());
                    return;
                }
                case "stepEditingInsideAMovesFrom":
                {
                    long seq = _scribe.Fold().NextSeq;
                    _scribe.Append(_scribe.BeginLine(seq, new JsonArray(MoveTheMediaFolder(), EditInside(MediaFolder + "/a.md")), "A"));
                    _scribe.Finish(seq);
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

        private const string MediaFolder = "courses/TST1O/media";
        private const string RenamedFolder = "courses/TST1O/renamed";

        private JsonObject MoveTheMediaFolder() => UndoKindsForTheCases.MoveTheMediaFolder(_scribe);

        private static JsonObject EditInside(string path) => UndoKindsForTheCases.EditInside(path);

        /// <summary>courses/TST1O/media as <c>moveAFolderWithAPageEditedInside</c> makes it (and an empty sub inside it), when neither it nor renamed is there.</summary>
        private void MakeTheMediaFolder(bool withAnEmptySub)
        {
            if (Directory.Exists(_scribe.FullPath("A", MediaFolder)) || Directory.Exists(_scribe.FullPath("A", RenamedFolder))) return;
            _scribe.WritePage("A", MediaFolder + "/a.md", "Intro.\nLine one: old.\nEnd.\n"u8.ToArray());
            _scribe.WritePage("A", MediaFolder + "/b.md", "B\n"u8.ToArray());
            if (withAnEmptySub) Directory.CreateDirectory(_scribe.FullPath("A", MediaFolder + "/sub"));
        }

        /// <summary>ONE step: the media folder's move, the edit of a.md, then a writeFile of each new file, inside the folder at its new place.</summary>
        private void MoveCarrying(params (string Inside, string Text)[] made)
        {
            var ops = new JsonArray(MoveTheMediaFolder(), EditInside(RenamedFolder + "/a.md"));
            var blobs = new List<byte[]>();
            foreach ((string inside, string text) in made)
            {
                byte[] bytes = Encoding.UTF8.GetBytes(text);
                ops.Add(_scribe.OpsFor(RenamedFolder + "/" + inside, null, bytes)[0]!.DeepClone());
                blobs.Add(bytes);
            }
            Ops(ops, blobs);
        }

        private const string CaseOnlyOld = "courses/TST1O/Media";

        private const string LinkPlace = "courses/TST1O/section1/media";
        private const string LinkRenamed = "courses/TST1O/section1/renamed";
        private const string LinkLibrary = "courses/TST1O/library";
        private const string LinkTarget = "../library";
        private string? _libraryListing;

        /// <summary>The link's move from section1/media to section1/renamed, its linkSha the SHA-256 of <c>../library</c> as written.</summary>
        private static JsonObject TheLinksMove() => new()
        {
            ["kind"] = "move", ["from"] = LinkPlace, ["to"] = LinkRenamed,
            ["linkSha"] = UndoCheck.Sha(Encoding.UTF8.GetBytes(LinkTarget)),
        };

        /// <summary><c>linkedFolder</c>: which place holds the link (renamed, media, both or neither), the target the link there holds (<c>notALink</c>), then whether the library holds what the call made.</summary>
        internal string LinkedFolder()
        {
            string renamedFull = _scribe.FullPath("A", LinkRenamed);
            string mediaFull = _scribe.FullPath("A", LinkPlace);
            bool renamed = UndoLinks.Look(renamedFull) == UndoLinks.What.Link;
            bool media = UndoLinks.Look(mediaFull) == UndoLinks.What.Link;
            string place = renamed && media ? "both" : renamed ? "renamed" : media ? "media" : "neither";
            string at = renamed ? renamedFull : mediaFull;
            string target = UndoLinks.Look(at) == UndoLinks.What.Link ? new DirectoryInfo(at).LinkTarget ?? "notALink" : "notALink";
            string library = _libraryListing is not null && UndoTreeReading.Read(_scribe.FullPath("A", LinkLibrary)).ListingSha == _libraryListing ? "untouched" : "changed";
            return place + ", " + target + ", " + library;
        }

        /// <summary>The spelling courses/TST1O lists for the media folder, as spelled, or null when it lists none.</summary>
        private string? CaseOnlySpellingListed()
        {
            string course = _scribe.FullPath("A", "courses/TST1O");
            if (!Directory.Exists(course)) return null;
            foreach (string entry in Directory.EnumerateFileSystemEntries(course))
            {
                string name = Path.GetFileName(entry);
                if (string.Equals(name.ToLowerInvariant(), "media", StringComparison.Ordinal)) return name;
            }
            return null;
        }

        /// <summary><c>caseOnlyFolder</c>: the spelling courses/TST1O lists for the folder (Media, media, MEDIA or none), then what its a.md holds, as <c>movedFolder</c> says it.</summary>
        internal string CaseOnlyFolder()
        {
            string? spelled = CaseOnlySpellingListed();
            string? text = spelled is null ? null : UndoKindsForTheCases.Text(_scribe.Page("A", "courses/TST1O/" + spelled + "/a.md"));
            return (spelled ?? "none") + ", " + Holds(text);
        }

        private static string Holds(string? text) => UndoKindsForTheCases.Holds(text);

        /// <summary>Where the moved folder is now: renamed if it is there, else media.</summary>
        private string MovedFolderNow() => Directory.Exists(_scribe.FullPath("A", RenamedFolder)) ? RenamedFolder : MediaFolder;

        private static string InByteOrder(List<string> names)
        {
            names.Sort((first, second) => Encoding.UTF8.GetBytes(first).AsSpan().SequenceCompareTo(Encoding.UTF8.GetBytes(second)));
            return string.Join(", ", names);
        }

        /// <summary><c>madeFolder</c>: what sub holds wherever the moved folder is now, every name counted, <c>empty</c>, or <c>none</c>.</summary>
        internal string MadeFolder()
        {
            string sub = _scribe.FullPath("A", MovedFolderNow() + "/sub");
            if (!Directory.Exists(sub)) return "none";
            List<string> names = Directory.EnumerateFileSystemEntries(sub).Select(entry => Path.GetFileName(entry)).ToList();
            return names.Count == 0 ? "empty" : InByteOrder(names);
        }

        /// <summary><c>foldersInside</c>: every folder below the moved folder wherever it is now, as paths inside it, or <c>none</c>.</summary>
        internal string FoldersInside()
        {
            string folder = _scribe.FullPath("A", MovedFolderNow());
            List<string> paths = Directory.EnumerateDirectories(folder, "*", SearchOption.AllDirectories)
                .Select(entry => Path.GetRelativePath(folder, entry).Replace(Path.DirectorySeparatorChar, '/')).ToList();
            return paths.Count == 0 ? "none" : InByteOrder(paths);
        }

        /// <summary><c>movedFolder</c>: which place holds the folder (renamed, media, both or neither), then what its a.md holds (new, old, byHand, none).</summary>
        internal string MovedFolder() => UndoKindsForTheCases.MovedFolder(_scribe);

        /// <summary>
        /// The folder <paramref name="folder"/> replaced by a junction to
        /// <see cref="Outside"/>, a folder beside the working folder
        /// (<c>linkItsOldFolderOutside</c>, <c>linkItsNewFolderOutside</c>).
        /// </summary>
        private void LinkOutside(string folder)
        {
            string place = _scribe.FullPath("A", folder);
            if (Directory.Exists(place)) Directory.Delete(place, recursive: true);
            Directory.CreateDirectory(Outside);
            UndoKindsForTheCases.MakeAJunction(place, Outside);
        }

        /// <summary>One <c>move</c> of the page at <paramref name="from"/> to <paramref name="to"/>, the page made first holding <c>page</c> when neither place holds it.</summary>
        private void MoveThePage(string from, string to)
        {
            if (_scribe.Page("A", from) is null && _scribe.Page("A", to) is null)
                _scribe.WritePage("A", from, "page\n"u8.ToArray());
            Ops(new JsonArray(UndoKindsForTheCases.MoveFile(from, to, _scribe.Page("A", from) ?? "page\n"u8.ToArray())), []);
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
