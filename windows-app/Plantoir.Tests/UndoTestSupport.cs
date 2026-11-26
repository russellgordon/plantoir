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

    /// <summary>
    /// <c>undo-json-cases.json</c>: the editJSON byte cases, kept out of
    /// <c>shared-rules.json</c> because some hold keys that differ only by
    /// case, which Windows PowerShell 5.1 cannot read (#899 W6).
    /// </summary>
    internal static JsonElement JsonCases => JsonCasesDocument.Value.RootElement;

    private static readonly Lazy<JsonDocument> SharedRulesDocument = new(() => ContractLoader.LoadDocument("shared-rules.json"));
    private static readonly Lazy<JsonDocument> FileFormatsDocument = new(() => ContractLoader.LoadDocument("file-formats.json"));
    private static readonly Lazy<JsonDocument> TracesDocument = new(() => ContractLoader.LoadDocument("undo-traces.json"));
    private static readonly Lazy<JsonDocument> JsonCasesDocument = new(() => ContractLoader.LoadDocument("undo-json-cases.json"));

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
/// The test's harness round the REAL door (#899 W1, W2a, W2b): a temporary
/// folder of its own with a journal and two working folders (A and B), a clock
/// a test moves by hand, and the liveness of the processes a case names.
///
/// <para><b>Since W2b every step, undo, redo and the clearing at the flip go
/// through <see cref="UndoDoor"/></b>: the begin with its blobs in one hold, the
/// staged swap, the closing with pruning, refusals that clear or drop, so every
/// stack case and trace runs through the real door, lock, store and swap. Only
/// the calls that stand for ANOTHER process or another version still write their
/// lines raw, as the contract describes them (<c>begin:held</c>,
/// <c>finish:held</c>, <c>begin:dead@B</c>, <c>foreign*</c>,
/// <c>stepFromAnotherVersion:*</c>, <c>cleared:&lt;reason&gt;</c>, <c>note</c>),
/// through the real writer under the lock.</para>
/// </summary>
internal sealed class UndoScribe : IDisposable
{
    internal const string ThisCourse = "TST1O";
    private const string FolderPrefix = "plantoir-undo-w1-";

    private readonly string _root;
    private readonly HashSet<long> _alive = [];
    private readonly Dictionary<string, string> _folders = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _folderIds = new(StringComparer.Ordinal);

    /// <param name="segmentBytes">Where a new segment starts: 4 MiB as in the app, smaller where a test needs segments.</param>
    internal UndoScribe(long segmentBytes = UndoJournal.SegmentBytesInTheApp)
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
                                  step => UndoJournalChecks.FolderIsReachable(step, Clock), isLive: true, readRetry: TimeSpan.Zero,
                                  memory: new UndoProcessMemory(), segmentBytes: segmentBytes);
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

    private string BlobPath(string name) => Journal.BlobPath(name);

    /// <summary>A blob, stored by the real writer under the lock.</summary>
    internal string PutBlob(byte[] bytes) => Journal.WithLock(writer => writer.WriteBlob(bytes));

    // ---- The journal ------------------------------------------------------

    internal UndoFolded Fold()
    {
        UndoReading reading = Journal.Read();
        Assert.True(reading.IsFresh, "the scribe's own journal is never held");
        return reading.Folded;
    }

    internal UndoOffered Offer() => Journal.Offer(Fold());

    internal int LinesOnDisk => File.Exists(SegmentPath) ? File.ReadAllBytes(SegmentPath).Count(b => b == (byte)'\n') : 0;

    /// <summary>Appends one line already encoded (another version's), by the real writer under the lock.</summary>
    internal void AppendRaw(string json) => Journal.WithLock(writer => writer.AppendRaw(json));

    /// <summary>Appends one event by the real writer under the lock: keys sorted, <c>v</c> and <c>at</c> stamped, LF, no BOM.</summary>
    internal void Append(JsonObject line) => Journal.WithLock(writer => writer.Append(line));

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

    // ---- What a door does: the real door (W2b) ------------------------------

    /// <summary>The runner of the one maintainer U1 defines, standing in for the app's: it re-derives nothing and counts (the stack cases' <c>rederived</c>), and can be taken away (<c>forgetTheMaintainer</c>).</summary>
    internal sealed class FrontPageMaintainer : IUndoMaintainers
    {
        private int _rederived;
        internal int Rederived => _rederived;
        internal bool Forgotten { get; set; }
        public bool CanRun(string maintainer) => !Forgotten && maintainer == UndoOp.SectionFrontPage;
        public void Rederive(UndoOp op, string root) => Interlocked.Increment(ref _rederived);
        internal int Take() => Interlocked.Exchange(ref _rederived, 0);
    }

    /// <summary>The external places every door of this scribe reads and sets (<c>preference:…</c>, in memory).</summary>
    internal UndoMemoryPlaces Places { get; } = new();

    internal FrontPageMaintainer Maintainers { get; } = new();

    /// <summary>The trail lines every door of this scribe wrote (recovery's <c>undo rolled back</c>).</summary>
    internal List<UndoTrailLine> TrailLines { get; } = [];

    /// <summary>The real door on this scribe's journal, live, as this process (or as the process <paramref name="pid"/> names).</summary>
    internal UndoDoor Door(UndoSeams? seams = null, long? pid = null, UndoMode mode = UndoMode.Live, IUndoMaintainers? maintainers = null) =>
        new(Journal, mode, maintainers ?? Maintainers, seams, Process(pid ?? Environment.ProcessId), trail: line => { lock (TrailLines) TrailLines.Add(line); },
            places: Places);

    /// <summary>The draft of a step given as its ops (U2's kinds, through <c>Perform(UndoOpsDraft)</c>), in a working folder or in none.</summary>
    internal UndoOpsDraft OpsDraft(string? folder, JsonArray ops, IReadOnlyList<byte[]> blobs, string action = "rollOver") => new()
    {
        ActionKey = action,
        MadeBy = "menu",
        WorkingFolder = folder is null ? null : _folders[folder],
        Course = folder is null ? null : ThisCourse,
        Section = folder is null ? null : 1,
        Class = "A",
        Holds = folder is null ? null : "section",
        Ops = ops,
        Blobs = blobs,
    };

    /// <summary>
    /// Every staged file or folder (<c>.plantoir-undo-</c> in its name) anywhere
    /// in a working folder, never through a link (W8-6: a symbolic link holding
    /// <c>../library</c>, forward slash kept, cannot be followed on Windows,
    /// ERROR_INVALID_NAME, and what a link leads to is not the step's). A link
    /// is what <see cref="UndoLinks.Look"/> says it is, never the bare
    /// ReparsePoint attribute, which a OneDrive placeholder also carries
    /// (W8-7, the review of pieces 5 and 6, L2): a placeholder folder is
    /// walked like any other.
    /// </summary>
    internal List<string> StagedLeftovers(string folder)
    {
        var found = new List<string>();
        void Walk(string place)
        {
            foreach (string entry in Directory.EnumerateFileSystemEntries(place))
            {
                if (Path.GetFileName(entry).Contains(UndoSwap.StagedMarker, StringComparison.Ordinal)) found.Add(entry);
                if (UndoLinks.Look(entry) == UndoLinks.What.Folder) Walk(entry);
            }
        }
        Walk(_folders[folder]);
        return found;
    }

    /// <summary>The ops of one file's change, as the door works them out, with any whole-file blobs stored (for the calls that write another process's or version's lines raw).</summary>
    internal JsonArray OpsFor(string relative, byte[]? before, byte[]? after)
    {
        JsonArray ops = UndoLineOps.ForAFile(relative, before, after);
        bool whole = (string?)ops[0]!["kind"] == UndoOp.WriteFile;
        if (whole && before is not null) PutBlob(before);
        if (whole && after is not null) PutBlob(after);
        return ops;
    }

    /// <summary>The draft of a step in a working folder: what an action would hand the door.</summary>
    internal UndoStepDraft Draft(string folder, IReadOnlyList<(string Path, byte[]? After)> changes)
    {
        var files = new List<UndoFileChange>();
        foreach ((string path, byte[]? after) in changes) files.Add(new UndoFileChange(path, Page(folder, path), after));
        return new UndoStepDraft
        {
            ActionKey = "publishPages",
            ActionArguments = new Dictionary<string, string>(StringComparer.Ordinal) { ["pageCount"] = "1" },
            MadeBy = "menu",
            WorkingFolder = _folders[folder],
            Course = ThisCourse,
            Section = 1,
            Holds = "section",
            Changes = files,
        };
    }

    /// <summary>
    /// A step through the REAL door (begin, the staged swap, applied with the
    /// redo branch dropped, pruning). Returns its seq, or null for a change of
    /// nothing. <paramref name="daysAgo"/> sets the clock back for the step, as
    /// a step made that long ago was made.
    /// </summary>
    internal long? Step(string folder, IReadOnlyList<(string Path, byte[]? After)> changes, double daysAgo = 0)
    {
        TimeSpan shift = TimeSpan.FromDays(daysAgo);
        Clock.Advance(-shift);
        try
        {
            UndoOutcome outcome = Door().Perform(Draft(folder, changes));
            if (outcome.Kind == UndoOutcomeKind.ChangedNothing) return null;
            Assert.True(outcome.Kind == UndoOutcomeKind.Applied, "the door came to " + outcome.Word);
            return outcome.Seq;
        }
        finally
        {
            Clock.Advance(shift);
        }
    }

    /// <summary>The applied of a step ANOTHER process has in flight (the stack cases' <c>finish:held</c>): every undone step below it dropped first, then pruning.</summary>
    internal void Finish(long seq) => Journal.WithLock(writer =>
    {
        writer.DropTheRedoBranch(below: seq);
        writer.Append(new JsonObject { ["seq"] = seq, ["event"] = "applied" });
        Door().RecoverThenPrune(writer);
    });

    /// <summary>What pruning and deletion decide, carried out by the product inside the lock.</summary>
    internal void Prune() => Journal.WithLock(writer => Door().RecoverThenPrune(writer));

    /// <summary>The one clearing at the flip, through the door; the seq it wrote, or null when nothing was on the list.</summary>
    internal long? GoLive() => Door().ClearTheListAsTheSwitchGoesLive() ? Fold().LastClearing!.Value.Seq : null;

    internal sealed record Outcome(string Name, long? Seq = null, string? Page = null, int Others = 0, string? Cleared = null, long? ClearedSeq = null);

    internal string FolderOf(UndoStep step) =>
        _folders.First(pair => string.Equals(pair.Value, step.WorkingFolder?.PathAtTheTime, StringComparison.Ordinal)).Key;

    private Outcome OutcomeOf(UndoOutcome outcome)
    {
        if (outcome.ClearedTheList)
        {
            var clearing = Fold().LastClearing!.Value;
            return new Outcome(outcome.Word, outcome.Seq, outcome.Refusal?.Path, outcome.Refusal?.Others ?? 0, clearing.Reason, clearing.Seq);
        }
        return new Outcome(outcome.Word, outcome.Seq, outcome.Refusal?.Path, outcome.Refusal?.Others ?? 0);
    }

    /// <summary>Undo through the real door; <paramref name="afterTheCheck"/> runs once it has checked its ops.</summary>
    internal Outcome Undo(Action? afterTheCheck = null) => OutcomeOf(Door(new UndoSeams { AfterTheCheck = afterTheCheck }).Undo());

    /// <summary>Redo through the real door.</summary>
    internal Outcome Redo() => OutcomeOf(Door().Redo());

    internal void Note() => Event(Fold().Highest, "note", new JsonObject
    {
        ["about"] = "aThingNoReaderKnows",
        ["phase"] = "aPhaseNoReaderKnows",
        ["somethingNew"] = new JsonObject { ["nested"] = true },
    });

}

/// <summary>
/// The traces' hand edits (<c>hand_edit_path</c> in <c>scripts/make_undo_traces.py</c>),
/// in the test only. The traces' writer and the op derivation moved into the
/// product in W2b (<see cref="JournaledSetting"/>, <see cref="UndoLineOps"/>).
/// </summary>
internal static class UndoTraceEdits
{
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

/// <summary>An external place in memory, for the cases (the mac's <c>UndoMemoryPlaces</c>): one dictionary, safe from any thread.</summary>
internal sealed class UndoMemoryPlaces : IUndoExternalPlaces
{
    private readonly Dictionary<string, UndoJson> _values = new(StringComparer.Ordinal);

    public UndoExternalReading Read(string target)
    {
        lock (_values) return _values.TryGetValue(target, out UndoJson? value) ? UndoExternalReading.Holding(value) : UndoExternalReading.Unset;
    }

    public bool Write(string target, UndoJson? value)
    {
        lock (_values)
        {
            if (value is null) _values.Remove(target);
            else _values[target] = value;
        }
        return true;
    }
}

/// <summary>What the U2 cases share (the mac's <c>UndoContractKinds</c>): the places their calls name and how each kind's op is written.</summary>
internal static class UndoKindsForTheCases
{
    internal const string MarkerFrom = "courses/TST1O/.netlify_sites/section1.json";
    internal const string MarkerTo = "courses/TST1O/.netlify_sites/section1.previous.json";
    internal const string OldMarker = "{\"site_id\": \"aaa-111\"}\n";
    internal const string NewMarker = "{\"site_id\": \"bbb-222\"}\n";
    internal const string ExtraFolder = "courses/TST1O/extra";
    internal static readonly (string Path, string Text)[] ExtraFiles = [("a.md", "A\n"), ("sub/b.md", "B\n")];
    internal const string Settings = "courses/TST1O/settings.json";
    internal const string Notes = "courses/TST1O/notes.md";
    internal const string Preference = "preference:undoCasesPreference";
    internal const string AsidePage = "courses/TST1O/old/a.md";
    internal const string AsidePageMoved = "courses/TST1O/a.md";
    internal const string FrontPage = "courses/TST1O/Section 1/index.md";

    internal static JsonObject MoveFile(string from, string to, byte[] content) => new()
    {
        ["kind"] = "move", ["from"] = from, ["to"] = to, ["sha"] = UndoCheck.Sha(content),
    };

    /// <summary>A createTree or removeTree op and the blobs it needs: its listing and every file's content.</summary>
    internal static (JsonObject Op, List<byte[]> Blobs) Tree(string kind, string path, UndoTreeListing listing, IEnumerable<byte[]> contents)
    {
        var names = new JsonArray(listing.Sha);
        var blobs = new List<byte[]> { listing.Bytes };
        var seen = new HashSet<string>(StringComparer.Ordinal) { listing.Sha };
        foreach ((_, string sha) in listing.Files)
        {
            if (seen.Add(sha)) names.Add(sha);
        }
        blobs.AddRange(contents);
        return (new JsonObject { ["kind"] = kind, ["path"] = path, ["listingSha"] = listing.Sha, ["blobs"] = names }, blobs);
    }

    internal static JsonObject External(string target, JsonNode? before, JsonNode? after, bool hasBefore = true)
    {
        var op = new JsonObject { ["kind"] = "external", ["target"] = target };
        if (hasBefore) op["before"] = before;
        op["after"] = after;
        return op;
    }

    internal static JsonObject FrontPageRecompute() => new()
    {
        ["kind"] = "recompute", ["path"] = FrontPage, ["maintainer"] = "sectionFrontPage", ["section"] = 1,
    };

    /// <summary>What a working folder's two marker places hold (the cases' <c>markers</c>).</summary>
    internal static string Markers(UndoScribe scribe, string folder = "A")
    {
        string? from = Text(scribe.Page(folder, MarkerFrom));
        string? to = Text(scribe.Page(folder, MarkerTo));
        if (from is null && to == OldMarker) return "moved";
        if (from == OldMarker && to is null) return "movedBack";
        if (from == NewMarker && to == OldMarker) return "bothKept";
        return $"from {from ?? "nothing"}, to {to ?? "nothing"}";
    }

    internal static string? Text(byte[]? bytes) => bytes is null ? null : Encoding.UTF8.GetString(bytes);

    // ---- U4b's carrying move (stackCases' moveAFolderWithAPageEditedInside, recoveryCases' withAMovedFolder) ----

    internal const string MediaFolder = "courses/TST1O/media";
    internal const string RenamedFolder = "courses/TST1O/renamed";
    internal const string MediaPageOld = "Intro.\nLine one: old.\nEnd.\n";
    internal const string MediaPageNew = "Intro.\nLine one: new.\nEnd.\n";

    /// <summary>courses/TST1O/media with a.md (<see cref="MediaPageOld"/>) and b.md (<c>B</c>).</summary>
    internal static void LayTheMediaFolder(UndoScribe scribe)
    {
        scribe.WritePage("A", MediaFolder + "/a.md", Encoding.UTF8.GetBytes(MediaPageOld));
        scribe.WritePage("A", MediaFolder + "/b.md", "B\n"u8.ToArray());
    }

    /// <summary>The media folder's move to renamed, its listingSha the folder's as it is (or as it was, once moved).</summary>
    internal static JsonObject MoveTheMediaFolder(UndoScribe scribe)
    {
        string folder = Directory.Exists(scribe.FullPath("A", MediaFolder)) ? MediaFolder : RenamedFolder;
        string listingSha = UndoTreeReading.Read(scribe.FullPath("A", folder)).ListingSha ?? new UndoTreeListing([], []).Sha;
        return new JsonObject { ["kind"] = "move", ["from"] = MediaFolder, ["to"] = RenamedFolder, ["listingSha"] = listingSha };
    }

    /// <summary>The replaceText that turns a.md's <c>Line one: old.</c> into <c>new</c>, named at <paramref name="path"/>.</summary>
    internal static JsonObject EditInside(string path) => new()
    {
        ["kind"] = "replaceText", ["path"] = path, ["before"] = "old", ["after"] = "new",
        ["contextBefore"] = "Line one: ", ["contextAfter"] = ".\n",
    };

    /// <summary>
    /// What a.md holds, as <c>movedFolder</c> says it: new (it holds the line
    /// <c>Line one: new.</c>), old (<c>Line one: old.</c>), byHand (anything
    /// else: <c>Hand.</c>, or <c>Line one: by hand.</c>), none (no a.md), as
    /// the mac's <c>UndoContractKinds.movedFolder</c> reads it.
    /// </summary>
    internal static string Holds(string? text) =>
        text is null ? "none"
        : text.Contains("Line one: new.", StringComparison.Ordinal) ? "new"
        : text.Contains("Line one: old.", StringComparison.Ordinal) ? "old"
        : "byHand";

    /// <summary>
    /// <c>recoveryCasesHow</c>' <c>handEdit: carried</c> (U4b2-13): a.md inside
    /// the moved folder, wherever the folder is now (renamed if it is there,
    /// else media), every line starting <c>Line one: </c> set to
    /// <c>Line one: by hand.</c> (the mac's <c>editTheCarriedPageByHand</c>).
    /// False when there is no such page or no such line.
    /// </summary>
    internal static bool EditTheCarriedPageByHand(UndoScribe scribe)
    {
        string folder = Directory.Exists(scribe.FullPath("A", RenamedFolder)) ? RenamedFolder : MediaFolder;
        if (Text(scribe.Page("A", folder + "/a.md")) is not { } text) return false;
        string[] lines = text.Split('\n');
        bool changed = false;
        for (int index = 0; index < lines.Length; index++)
        {
            if (!lines[index].StartsWith("Line one: ", StringComparison.Ordinal)) continue;
            lines[index] = "Line one: by hand.";
            changed = true;
        }
        if (!changed) return false;
        scribe.WritePage("A", folder + "/a.md", Encoding.UTF8.GetBytes(string.Join('\n', lines)));
        return true;
    }

    /// <summary><c>movedFolder</c>: which place holds the folder (renamed, media, both or neither), then what its a.md holds.</summary>
    internal static string MovedFolder(UndoScribe scribe)
    {
        bool renamed = Directory.Exists(scribe.FullPath("A", RenamedFolder));
        bool media = Directory.Exists(scribe.FullPath("A", MediaFolder));
        string place = renamed && media ? "both" : renamed ? "renamed" : media ? "media" : "neither";
        return place + ", " + Holds(Text(scribe.Page("A", (renamed ? RenamedFolder : MediaFolder) + "/a.md")));
    }

    /// <summary>Whether the folder makeAFolder makes is there, as a folder.</summary>
    internal static bool FolderIsThere(UndoScribe scribe, string folder = "A") =>
        UndoTreeReading.Read(scribe.FullPath(folder, ExtraFolder)) is UndoTreeReading.Tree;

    /// <summary>The listing of the extra folder as the cases make it, and its contents.</summary>
    internal static (UndoTreeListing Listing, List<byte[]> Contents) ExtraListing()
    {
        var files = new List<(string, string)>();
        var contents = new List<byte[]>();
        foreach ((string path, string text) in ExtraFiles)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(text);
            files.Add((path, UndoCheck.Sha(bytes)));
            contents.Add(bytes);
        }
        return (new UndoTreeListing(["sub"], files), contents);
    }

    /// <summary>
    /// Makes a link at <paramref name="place"/> (never followed by the check):
    /// a symbolic link where this account may make one, else a junction to a
    /// folder of the test's own; either is a name-surrogate reparse point,
    /// which is what the check reads as "a link".
    /// </summary>
    internal static void MakeALink(string place, string scratch)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(place)!);
        string target = Path.Combine(scratch, "link-target-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(target);
        File.WriteAllText(Path.Combine(target, "x.md"), "outside\n");
        try
        {
            File.CreateSymbolicLink(place, Path.Combine(target, "x.md"));
            return;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        MakeAJunction(place, target);
    }

    /// <summary>A junction (a mount point: no privilege needed) from <paramref name="place"/> to <paramref name="target"/>.</summary>
    internal static void MakeAJunction(string place, string target)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(place)!);
        var start = new System.Diagnostics.ProcessStartInfo("cmd.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (string argument in new[] { "/c", "mklink", "/J", place, target }) start.ArgumentList.Add(argument);
        using var made = System.Diagnostics.Process.Start(start)!;
        made.StandardOutput.ReadToEnd();
        made.StandardError.ReadToEnd();
        made.WaitForExit();
        Assert.True(Directory.Exists(place), "the junction was not made at " + place);
    }
}

/// <summary>
/// A real refusal on the disk for the kept-original rows (#899 W4c, the mac's
/// U3c): a deny entry for this user on a folder (it takes no new file or
/// folder: a full or read-only disk, as far as the list can tell) or on a file
/// (it cannot be read just now: a permission, as a cloud placeholder not
/// downloaded cannot). Each is taken away again by <see cref="Dispose"/>.
/// </summary>
#pragma warning disable CA1416 // every deny entry is made only on Windows (checked in Deny), where the tests run
internal sealed class UndoDenials : IDisposable
{
    private readonly List<Action> _restores = [];

    /// <summary>The folder takes no new file or folder; made first if it is not there.</summary>
    internal void FolderTakesNothingNew(string folder)
    {
        Directory.CreateDirectory(folder);
        Deny(new DirectoryInfo(folder), System.Security.AccessControl.FileSystemRights.CreateFiles | System.Security.AccessControl.FileSystemRights.CreateDirectories);
    }

    /// <summary>The file cannot be read just now.</summary>
    internal void FileCannotBeRead(string file) => Deny(new FileInfo(file), System.Security.AccessControl.FileSystemRights.ReadData);

    private void Deny(FileSystemInfo item, System.Security.AccessControl.FileSystemRights rights)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("a deny entry is Windows'");
        // On a folder, inherited by what is made inside it: measured on the PC
        // (2026-11-20), a deny of CreateFiles and CreateDirectories on a folder
        // alone still let a folder be made inside it, and the list writes each
        // blob into a folder of its own (content\ab\…).
        var rule = item is DirectoryInfo
            ? new System.Security.AccessControl.FileSystemAccessRule(
                System.Security.Principal.WindowsIdentity.GetCurrent().User!, rights,
                System.Security.AccessControl.InheritanceFlags.ContainerInherit | System.Security.AccessControl.InheritanceFlags.ObjectInherit,
                System.Security.AccessControl.PropagationFlags.None, System.Security.AccessControl.AccessControlType.Deny)
            : new System.Security.AccessControl.FileSystemAccessRule(
                System.Security.Principal.WindowsIdentity.GetCurrent().User!, rights, System.Security.AccessControl.AccessControlType.Deny);
        if (item is DirectoryInfo folder)
        {
            System.Security.AccessControl.DirectorySecurity security = folder.GetAccessControl();
            security.AddAccessRule(rule);
            folder.SetAccessControl(security);
            _restores.Add(() =>
            {
                System.Security.AccessControl.DirectorySecurity now = folder.GetAccessControl();
                now.RemoveAccessRule(rule);
                folder.SetAccessControl(now);
            });
            return;
        }
        var file = (FileInfo)item;
        System.Security.AccessControl.FileSecurity fileSecurity = file.GetAccessControl();
        fileSecurity.AddAccessRule(rule);
        file.SetAccessControl(fileSecurity);
        _restores.Add(() =>
        {
            System.Security.AccessControl.FileSecurity now = file.GetAccessControl();
            now.RemoveAccessRule(rule);
            file.SetAccessControl(now);
        });
    }

    public void Dispose()
    {
        if (!OperatingSystem.IsWindows()) return;
        for (int index = _restores.Count - 1; index >= 0; index--)
        {
            try { _restores[index](); } catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
        _restores.Clear();
    }
}
#pragma warning restore CA1416
