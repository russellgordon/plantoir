using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>A clock a test moves by hand: the contract's <c>clock:+n</c>, never the wall clock.</summary>
internal sealed class UndoTestClock(DateTimeOffset start) : TimeProvider
{
    private DateTimeOffset _now = start;
    private readonly DateTimeOffset _start = start;

    public override DateTimeOffset GetUtcNow() => _now;

    /// <summary>Sets the clock this many days from where it started.</summary>
    internal void SetDaysFromStart(double days) => _now = _start + TimeSpan.FromDays(days);

    internal void Advance(TimeSpan by) => _now += by;
}

/// <summary>The undo keys of the contract, read from the files both suites run.</summary>
internal static class UndoContract
{
    internal static JsonElement Undo => SharedRules.RootElement.GetProperty("undo");
    internal static JsonElement Journal => FileFormats.RootElement.GetProperty("undoJournal");

    private static readonly Lazy<JsonDocument> SharedRulesDocument = new(() => ContractLoader.LoadDocument("shared-rules.json"));
    private static readonly Lazy<JsonDocument> FileFormatsDocument = new(() => ContractLoader.LoadDocument("file-formats.json"));
    private static readonly Lazy<JsonDocument> TracesDocument = new(() => ContractLoader.LoadDocument("undo-traces.json"));

    internal static JsonDocument SharedRules => SharedRulesDocument.Value;
    internal static JsonDocument FileFormats => FileFormatsDocument.Value;
    internal static JsonDocument Traces => TracesDocument.Value;

    /// <summary>The fixture's pages: id, path, exact bytes (from utf8Hex, never from text).</summary>
    internal static IReadOnlyList<(string Id, string Path, byte[] Bytes)> Fixture =>
        Traces.RootElement.GetProperty("fixture").EnumerateArray()
            .Select(page => (page.GetProperty("page").GetString()!, page.GetProperty("path").GetString()!,
                             Convert.FromHexString(page.GetProperty("utf8Hex").GetString()!)))
            .ToList();

    /// <summary>A verdict's or an outcome's name as the contract spells it: camelCase.</summary>
    internal static string Spelled<T>(T value) where T : Enum
    {
        string name = value.ToString();
        return char.ToLowerInvariant(name[0]) + name[1..];
    }
}

/// <summary>
/// A test-only stand-in for the door (W2), so the READING side of #899 can be
/// walked against the contract's stack cases and seeded traces in piece W1.
///
/// <para>It writes, into a temporary folder of its own, exactly the lines the
/// contract says a door writes (begin, applied with the redo branch dropped,
/// undoing/undone, redoing/redone, cleared, dropped, pruned, interrupted,
/// note), and every decision in it is the PRODUCT's: what Undo and Redo act on
/// (<see cref="UndoLimits.Offer"/>), whether a step can move
/// (<see cref="UndoCheck.Plan"/>), what pruning writes
/// (<see cref="UndoPruning.Decide"/>), what may be deleted
/// (<see cref="UndoPruning.Deletable"/>), and the next number
/// (<see cref="UndoFolded.NextSeq"/>). The journal is read back from the disk
/// by <see cref="UndoJournal.Read"/> after every line, so the format reader is
/// on every path. What it does NOT have is everything W2 owns: no lock, no
/// staged swap, no flush, one process. Pages are written whole with
/// <see cref="File.WriteAllBytes"/>.</para>
/// </summary>
internal sealed class UndoScribe : IDisposable
{
    internal const string ThisCourse = "TST1O";
    private const string FolderPrefix = "plantoir-undo-w1-";

    private static readonly UTF8Encoding Utf8 = new(false);

    private readonly string _root;
    private readonly HashSet<long> _alive = [];
    private readonly Dictionary<string, string> _folders = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _folderIds = new(StringComparer.Ordinal);

    internal UndoScribe()
    {
        _root = RunOwnedTempFolders.Create(FolderPrefix);
        Clock = new UndoTestClock(new DateTimeOffset(2026, 11, 14, 12, 0, 0, TimeSpan.Zero));
        _alive.Add(Environment.ProcessId);
        JournalFolder = Path.Combine(_root, "undo");
        Directory.CreateDirectory(JournalFolder);
        foreach (string key in new[] { "A", "B" })
        {
            string folder = Path.Combine(_root, key);
            Directory.CreateDirectory(Path.Combine(folder, "courses", ".internal"));
            _folders[key] = folder;
            _folderIds[key] = new FolderIdentityFile(Path.Combine(folder, "courses", ".internal", "folder-id"), Clock).ReadOrMake()!;
        }
        Journal = new UndoJournal(JournalFolder, Clock, process => process is not null && _alive.Contains(process.Pid),
                                  step => UndoJournalChecks.FolderIsReachable(step, Clock), isLive: true, readRetry: TimeSpan.Zero);
    }

    internal UndoTestClock Clock { get; }
    internal UndoJournal Journal { get; }
    internal string JournalFolder { get; }
    internal string SegmentPath => Path.Combine(JournalFolder, "journal-000001.jsonl");

    /// <summary>A process id the liveness check answers "running" for, standing in for another process.</summary>
    internal const long AnotherRunningProcess = 4_000_001;

    /// <summary>A process id the liveness check answers "gone" for.</summary>
    internal const long AProcessThatIsGone = 4_000_002;

    internal void MarkAlive(long pid) => _alive.Add(pid);

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    // ---- Pages ---------------------------------------------------------------

    internal string FullPath(string folder, string relative) => Path.Combine(_folders[folder], relative.Replace('/', Path.DirectorySeparatorChar));

    internal byte[]? Page(string folder, string relative)
    {
        string path = FullPath(folder, relative);
        return File.Exists(path) ? File.ReadAllBytes(path) : null;
    }

    internal void WritePage(string folder, string relative, byte[]? bytes)
    {
        string path = FullPath(folder, relative);
        if (bytes is null) { if (File.Exists(path)) File.Delete(path); return; }
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, bytes);
    }

    internal void WriteFixture(string folder)
    {
        foreach ((_, string path, byte[] bytes) in UndoContract.Fixture) WritePage(folder, path, bytes);
    }

    internal void MoveFolderAway(string folder) => Directory.Move(_folders[folder], _folders[folder] + "-away");
    internal void PutFolderBack(string folder) => Directory.Move(_folders[folder] + "-away", _folders[folder]);

    internal void RemoveContent()
    {
        string content = Path.Combine(JournalFolder, "content");
        if (Directory.Exists(content)) Directory.Delete(content, recursive: true);
    }

    internal bool BlobIsThere(string name) => File.Exists(BlobPath(name));

    private string BlobPath(string name) => Path.Combine(JournalFolder, "content", name[..2], name);

    internal string PutBlob(byte[] bytes)
    {
        string name = UndoCheck.Sha(bytes);
        string path = BlobPath(name);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        if (!File.Exists(path)) File.WriteAllBytes(path, bytes);
        return name;
    }

    // ---- The journal ------------------------------------------------------

    internal UndoFolded Fold()
    {
        UndoReading reading = Journal.Read();
        Assert.True(reading.IsFresh, "the scribe's own journal is never held");
        return reading.Folded;
    }

    internal UndoOffered Offer() => Journal.Offer(Fold());

    internal int LinesOnDisk => File.Exists(SegmentPath) ? File.ReadAllBytes(SegmentPath).Count(b => b == (byte)'\n') : 0;

    /// <summary>Appends one line as written: LF, UTF-8 with no byte-order mark.</summary>
    internal void AppendRaw(string json) => File.AppendAllText(SegmentPath, json + "\n", Utf8);

    internal void Append(JsonObject line)
    {
        line["v"] ??= 1;
        line["at"] ??= UndoMoment.Format(Clock.GetUtcNow());
        AppendRaw(line.ToJsonString());
    }

    internal JsonObject Process(long pid) => new()
    {
        ["host"] = "test-host",
        ["pid"] = pid,
        ["name"] = "plantoir-mcp",
        ["started"] = "1.000000",
    };

    internal JsonObject WorkingFolder(string folder) => new()
    {
        ["id"] = _folderIds[folder],
        ["pathAtTheTime"] = _folders[folder],
    };

    /// <summary>The begin line of a step, with every key U1 writes.</summary>
    internal JsonObject BeginLine(long seq, JsonArray ops, string folder, double daysAgo = 0, long? pid = null)
    {
        var step = new JsonObject
        {
            ["seq"] = seq,
            ["madeAt"] = UndoMoment.Format(Clock.GetUtcNow() - TimeSpan.FromDays(daysAgo)),
            ["madeBy"] = "menu",
            ["holds"] = "section",
            ["course"] = ThisCourse,
            ["section"] = 1,
            ["action"] = new JsonObject { ["key"] = "publishPages", ["arguments"] = new JsonObject { ["pageCount"] = "1" } },
            ["workingFolder"] = WorkingFolder(folder),
            ["ops"] = ops,
        };
        return new JsonObject { ["seq"] = seq, ["event"] = "begin", ["step"] = step, ["process"] = Process(pid ?? Environment.ProcessId) };
    }

    internal void Event(long seq, string name, JsonObject? extra = null)
    {
        var line = new JsonObject { ["seq"] = seq, ["event"] = name };
        if (extra is not null)
        {
            foreach (var pair in extra.ToList())
            {
                extra.Remove(pair.Key);
                line[pair.Key] = pair.Value;
            }
        }
        Append(line);
    }

    // ---- What a door does, from the product's decisions ---------------------

    /// <summary>The ops of one file's change: one editLine per entry where the line model reproduces it both ways, else one writeFile.</summary>
    internal JsonArray OpsFor(string relative, byte[]? before, byte[]? after)
    {
        string? beforeText = before is null ? null : UndoCheck.DecodeStrictly(before);
        string? afterText = after is null ? null : UndoCheck.DecodeStrictly(after);
        if (beforeText is not null && afterText is not null && UndoLineOps.For(relative, beforeText, afterText) is { } lineOps)
            return lineOps;
        var op = new JsonObject { ["kind"] = "writeFile", ["path"] = relative };
        var blobs = new JsonArray();
        if (before is not null) { string name = PutBlob(before); op["beforeSha"] = name; blobs.Add(name); }
        if (after is not null) { string name = PutBlob(after); op["afterSha"] = name; blobs.Add(name); }
        op["blobs"] = blobs;
        return new JsonArray(op);
    }

    /// <summary>A step: begin, the pages written, the redo branch dropped, applied, pruning. Returns its seq, or null for a change of nothing.</summary>
    internal long? Step(string folder, IReadOnlyList<(string Path, byte[]? After)> changes, double daysAgo = 0,
                        Action<JsonObject>? beforeWriting = null)
    {
        var ops = new JsonArray();
        foreach ((string path, byte[]? after) in changes.OrderBy(change => change.Path, StringComparer.Ordinal))
        {
            byte[]? before = Page(folder, path);
            if (Same(before, after)) continue;
            foreach (JsonNode? op in OpsFor(path, before, after)) ops.Add(op!.DeepClone());
        }
        if (ops.Count == 0) return null;
        long seq = Fold().NextSeq;
        JsonObject begin = BeginLine(seq, ops, folder, daysAgo);
        beforeWriting?.Invoke(begin);
        Append(begin);
        foreach ((string path, byte[]? after) in changes) WritePage(folder, path, after);
        Finish(seq);
        return seq;
    }

    /// <summary>The applied of a step in flight: every undone step below it dropped first, then pruning.</summary>
    internal void Finish(long seq)
    {
        foreach (UndoFoldedStep below in Fold().Steps.Values)
        {
            if (below.State == UndoStepState.Undone && below.Seq < seq)
                Event(below.Seq, "dropped", new JsonObject { ["reason"] = "newStep" });
        }
        Event(seq, "applied");
        Prune();
    }

    /// <summary>What pruning and deletion decide, carried out.</summary>
    internal void Prune()
    {
        UndoFolded folded = Fold();
        foreach (UndoPruneAction action in Journal.Pruning(folded))
        {
            switch (action)
            {
                case UndoPruneAction.Pruned pruned:
                    Event(pruned.Seq, "pruned", new JsonObject { ["reason"] = pruned.Reason });
                    break;
                case UndoPruneAction.ClosedUnsettled closed:
                    Event(closed.Seq, "interrupted", new JsonObject
                    {
                        ["phase"] = closed.Phase.ToString().ToLowerInvariant(),
                        ["reason"] = "unsettled",
                        ["paths"] = new JsonArray(closed.Paths.Select(path => (JsonNode)path).ToArray()),
                    });
                    break;
            }
        }
        UndoDeletion deletion = UndoPruning.Deletable(Fold(), Journal.Segments().Select(s => s.Number).ToList(), Journal.BlobsOnDisk(), Clock.GetUtcNow());
        foreach (string blob in deletion.Blobs) File.Delete(BlobPath(blob));
    }

    /// <summary>One `cleared` line with the highest seq, written only when something is on the list.</summary>
    internal long? Clear(string reason)
    {
        UndoFolded folded = Fold();
        if (!folded.Steps.Values.Any(step => step.IsOnTheList)) return null;
        Event(folded.Highest, "cleared", new JsonObject { ["reason"] = reason });
        return folded.Highest;
    }

    internal sealed record Outcome(string Name, long? Seq = null, string? Page = null, int Others = 0, string? Cleared = null, long? ClearedSeq = null);

    private UndoCheck.PlanResult PlanFor(UndoFoldedStep step, bool backward)
    {
        string folder = FolderOf(step.Step);
        return UndoCheck.Plan(step.Step.Ops, backward,
            relative => UndoCurrent.Read(FullPath(folder, relative)),
            Journal.Blob);
    }

    internal string FolderOf(UndoStep step) =>
        _folders.First(pair => string.Equals(pair.Value, step.WorkingFolder?.PathAtTheTime, StringComparison.Ordinal)).Key;

    internal Outcome Undo(Action? afterTheCheck = null)
    {
        UndoOffered offered = Offer();
        switch (offered.Undo.Kind)
        {
            case UndoAnswerKind.Nothing: return new Outcome("nothingToUndo");
            case UndoAnswerKind.AnotherChangeIsUnderWay: return new Outcome("anotherChangeIsUnderWay");
            case UndoAnswerKind.NotAvailable: return new Outcome("notAvailable");
        }
        UndoFoldedStep step = offered.Undo.Step!;
        UndoCheck.PlanResult plan = PlanFor(step, backward: true);
        afterTheCheck?.Invoke();
        switch (plan)
        {
            case UndoCheck.PlanResult.ChangedSince changed:
            {
                long? cleared = Clear("changedSince");
                Prune();
                return new Outcome("changedSince", step.Seq, changed.First, changed.Others, cleared is null ? null : "changedSince", cleared);
            }
            case UndoCheck.PlanResult.ContentMissing missing:
            {
                long? cleared = Clear("contentMissing");
                Prune();
                return new Outcome("contentMissing", step.Seq, missing.Path, 0, cleared is null ? null : "contentMissing", cleared);
            }
            case UndoCheck.PlanResult.FileIsInUse inUse:
                return new Outcome("fileIsInUse", step.Seq, inUse.Path);
            case UndoCheck.PlanResult.Ready ready:
            {
                string folder = FolderOf(step.Step);
                Event(step.Seq, "undoing", new JsonObject { ["process"] = Process(Environment.ProcessId) });
                foreach ((string path, byte[]? bytes) in ready.Changes) WritePage(folder, path, bytes);
                Event(step.Seq, "undone");
                Prune();
                return new Outcome("undone", step.Seq);
            }
            default:
                return new Outcome("notAvailable");
        }
    }

    internal Outcome Redo()
    {
        UndoOffered offered = Offer();
        switch (offered.Redo.Kind)
        {
            case UndoAnswerKind.Nothing: return new Outcome("nothingToRedo");
            case UndoAnswerKind.AnotherChangeIsUnderWay: return new Outcome("anotherChangeIsUnderWay");
            case UndoAnswerKind.NotAvailable: return new Outcome("notAvailable");
        }
        UndoFoldedStep step = offered.Redo.Step!;
        UndoCheck.PlanResult plan = PlanFor(step, backward: false);
        switch (plan)
        {
            case UndoCheck.PlanResult.ChangedSince or UndoCheck.PlanResult.ContentMissing:
            {
                // Ruling 20: refused once, then only the redo branch goes.
                foreach (UndoFoldedStep other in Fold().Steps.Values)
                {
                    if (other.State == UndoStepState.Undone && other.Seq >= step.Seq)
                        Event(other.Seq, "dropped", new JsonObject { ["reason"] = "redoRefused" });
                }
                return plan is UndoCheck.PlanResult.ChangedSince changed
                    ? new Outcome("changedSince", step.Seq, changed.First, changed.Others)
                    : new Outcome("contentMissing", step.Seq, ((UndoCheck.PlanResult.ContentMissing)plan).Path);
            }
            case UndoCheck.PlanResult.FileIsInUse inUse:
                return new Outcome("fileIsInUse", step.Seq, inUse.Path);
            case UndoCheck.PlanResult.Ready ready:
            {
                string folder = FolderOf(step.Step);
                Event(step.Seq, "redoing", new JsonObject { ["process"] = Process(Environment.ProcessId) });
                foreach ((string path, byte[]? bytes) in ready.Changes) WritePage(folder, path, bytes);
                Event(step.Seq, "redone");
                Prune();
                return new Outcome("redone", step.Seq);
            }
            default:
                return new Outcome("notAvailable");
        }
    }

    internal void Note() => Event(Fold().Highest, "note", new JsonObject
    {
        ["about"] = "aThingNoReaderKnows",
        ["phase"] = "aPhaseNoReaderKnows",
        ["somethingNew"] = new JsonObject { ["nested"] = true },
    });

    private static bool Same(byte[]? a, byte[]? b) =>
        a is null ? b is null : b is not null && a.AsSpan().SequenceEqual(b);
}

/// <summary>
/// The traces' writer and the line model's op derivation, in the test only
/// (W2 moves the writer into the product as <c>JournaledSetting</c>): the rules
/// of <c>scripts/make_undo_traces.py</c> (<c>setting_entry</c>,
/// <c>line_ops</c>, <c>verified</c>, <c>hand_edit_path</c>), the reference
/// both suites agree on. The ops are verified both ways through the PRODUCT's
/// <see cref="UndoEntries.Move"/>, as the contract says an editLine is chosen.
/// </summary>
internal static class UndoLineOps
{
    /// <summary>JournaledWrite.settingEntry's rule; null when the page is left alone (the key there twice).</summary>
    internal static string? SettingEntry(string key, string line, string text)
    {
        if (text.StartsWith('﻿')) text = text[1..];
        if (UndoEntries.LayoutOf(text) is not { } layout) return "---\n" + line + "\n---\n" + text;
        var found = layout.EntriesFor(key).ToList();
        if (found.Count > 1) return null;
        var lines = layout.Lines.ToList();
        if (found.Count == 1)
        {
            var entry = found[0];
            string replacement = line;
            if (lines[entry.Start].EndsWith('\r') && !line.EndsWith('\r')) replacement += "\r";
            lines.RemoveRange(entry.Start, entry.End - entry.Start);
            lines.Insert(entry.Start, replacement);
            return string.Join("\n", lines);
        }
        string inserted = line;
        if (lines[layout.Open].EndsWith('\r') && !line.EndsWith('\r')) inserted += "\r";
        lines.Insert(layout.Open + 1, inserted);
        return string.Join("\n", lines);
    }

    private static JsonObject EditLine(string path, string key, string? before, string? after, string? afterKey, bool created)
    {
        var op = new JsonObject { ["kind"] = "editLine", ["path"] = path, ["key"] = key, ["before"] = before, ["after"] = after, ["afterKey"] = afterKey };
        if (created) op["createdTheBlock"] = true;
        return op;
    }

    private static UndoOp Read(JsonObject op)
    {
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        return UndoFormat.ReadOp(document.RootElement);
    }

    private static JsonArray? Verified(List<JsonObject> ops, string before, string after)
    {
        string? forward = before;
        foreach (JsonObject op in ops)
        {
            UndoOp read = Read(op);
            forward = UndoEntries.Move(read, read.Before, read.After, forward);
            if (forward is null) return null;
        }
        if (!string.Equals(forward, after, StringComparison.Ordinal)) return null;
        string? backward = after;
        foreach (JsonObject op in Enumerable.Reverse(ops))
        {
            UndoOp read = Read(op);
            backward = UndoEntries.Move(read, read.After, read.Before, backward);
            if (backward is null) return null;
        }
        if (!string.Equals(backward, before, StringComparison.Ordinal)) return null;
        return new JsonArray(ops.Select(op => (JsonNode)op).ToArray());
    }

    /// <summary>The line ops of one file's change, or null when the line model cannot reproduce it both ways.</summary>
    internal static JsonArray? For(string path, string before, string after)
    {
        if (string.Equals(before, after, StringComparison.Ordinal)) return [];
        if (UndoEntries.LayoutOf(after) is not { } afterLayout) return null;
        var result = new List<JsonObject>();
        if (UndoEntries.LayoutOf(before) is not { } beforeLayout)
        {
            if (afterLayout.Entries.Count != 1) return null;
            var entry = afterLayout.Entries[0];
            result.Add(EditLine(path, entry.Key, null, afterLayout.TextOf(entry), null, true));
            return Verified(result, before, after);
        }
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in afterLayout.Entries)
        {
            if (!seen.Add(entry.Key)) return null;
            var inBefore = beforeLayout.EntriesFor(entry.Key).ToList();
            if (inBefore.Count > 1) return null;
            string afterText = afterLayout.TextOf(entry);
            string? beforeText = inBefore.Count == 1 ? beforeLayout.TextOf(inBefore[0]) : null;
            if (string.Equals(beforeText, afterText, StringComparison.Ordinal)) continue;
            result.Add(EditLine(path, entry.Key, beforeText, afterText, afterLayout.KeyBefore(entry), false));
        }
        foreach (var entry in beforeLayout.Entries)
        {
            if (seen.Contains(entry.Key)) continue;
            if (beforeLayout.EntriesFor(entry.Key).Count() > 1) return null;
            seen.Add(entry.Key);
            result.Add(EditLine(path, entry.Key, beforeLayout.TextOf(entry), null, beforeLayout.KeyBefore(entry), false));
        }
        if (result.Count == 0) return null;
        return Verified(result, before, after);
    }

    /// <summary>The traces' hand edits (<c>hand_edit_path</c>); null when that edit cannot be made to this page.</summary>
    internal static string? HandEdit(string kind, string? text)
    {
        if (text is null) return null;
        if (kind == "body") return text + "A line the teacher wrote in Obsidian.\n";
        if (UndoEntries.LayoutOf(text) is not { } layout) return null;
        string key = kind == "otherKey" ? "title" : "publish";
        var found = layout.EntriesFor(key).ToList();
        if (found.Count != 1) return null;
        var lines = layout.Lines.ToList();
        string old = lines[found[0].Start];
        string ending = old.EndsWith('\r') ? "\r" : "";
        string bare = old.EndsWith('\r') ? old[..^1] : old;
        lines[found[0].Start] = kind == "otherKey" ? bare + " (edited)" + ending : bare + " # checked" + ending;
        return string.Join("\n", lines);
    }
}
