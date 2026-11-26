using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/undo-traces.json</c> → <c>actionTraces</c> (#899 W7a): the
/// daily page actions' traces, made from the Mac's recorded steps
/// (<c>undo-action-steps.json</c>), replayed through the REAL door as
/// <c>actionNote</c> says. Each starts in an empty working folder with an
/// empty list, every file the recorded step names written from its
/// <c>before</c>; an <c>action</c> call makes the recorded step through
/// <see cref="UndoDoor.Perform(UndoStepDraft)"/> (each file's before and
/// after, its ops worked out by the door's own rule, then the recompute ops)
/// and must come to <c>expect</c> with the op kinds <c>ops</c> in order;
/// undo, redo, hand edits by <c>path</c> and notes as in the seeded traces;
/// <c>afterUndoingAll</c> and <c>final</c> by path. The front page is
/// re-derived as the app does (<see cref="UndoSectionFrontPage"/>: a course
/// with no settings is left alone). A recorded step with <c>members</c> is
/// made as its recorded <c>editJSON</c> ops (#899 W8-11); one with
/// <c>trees</c> is made by its Windows action, each folder hashed by its
/// listing (#899 W8-13); one with <c>moves</c> or <c>folderMoves</c> is held
/// by name in the ledger.
/// </summary>
public sealed class UndoActionTraceContractTests
{
    // ---- Functions -----------------------------------------------------------------

    public static IEnumerable<object[]> ActionTraces() =>
        UndoContract.Traces.RootElement.GetProperty("actionTraces").EnumerateArray()
            .Select(trace => new object[] { trace.GetProperty("name").GetString()! });

    private static readonly Lazy<JsonDocument> StepsDocument =
        new(() => JsonDocument.Parse(File.ReadAllText(ContractLoader.GetContractPath("undo-action-steps.json"))));

    [Fact]
    public void TheContractHoldsTheActionTraces() =>
        Assert.True(ActionTraces().Count() >= 120);

    /// <summary>Every action trace held open by name is one the contract still has.</summary>
    [Fact]
    public void EveryHeldActionTraceIsStillInTheContract() =>
        NamedGapLedger.StillNamed(NamedGapLedger.UndoActionTraces, ActionTraces().Select(row => (string)row[0]));

    /// <summary>Every action trace, every call; a held one must still stop at its step.</summary>
    [Theory]
    [MemberData(nameof(ActionTraces))]
    public void EveryCallOfEveryActionTrace(string name)
    {
        if (NamedGapLedger.Holding(NamedGapLedger.UndoActionTraces, name) is { } held)
        {
            NamedGapLedger.HeldCaseStillStopsAtItsGap(held, () => ReplayTheActionTrace(name), "a step this replay does not make", "named ");
            return;
        }
        ReplayTheActionTrace(name);
    }

    private static JsonElement RecordedStep(string stepName) =>
        StepsDocument.Value.RootElement.GetProperty("steps").EnumerateArray()
            .Single(candidate => candidate.GetProperty("name").GetString() == stepName);

    private static byte[]? Bytes(JsonElement text) =>
        text.ValueKind == JsonValueKind.Null ? null : new UTF8Encoding(false).GetBytes(text.GetString()!);

    private static void ReplayTheActionTrace(string name)
    {
        JsonElement trace = UndoContract.Traces.RootElement.GetProperty("actionTraces").EnumerateArray()
            .Single(candidate => candidate.GetProperty("name").GetString() == name);
        JsonElement recorded = RecordedStep(trace.GetProperty("step").GetString()!);
        // A step with members is made as its recorded editJSON ops (#899
        // W8-11). Rename folder's steps hold members AND folderMoves: the
        // guard names folderMoves, so they still stop here rather than run
        // with no folder move made.
        // A step with trees (Add folder) is made by its Windows action since
        // W8-13, each folder hashed by its listing.
        foreach (string unmade in new[] { "moves", "folderMoves" })
        {
            if (recorded.TryGetProperty(unmade, out _))
                Assert.Fail($"{name}: a step this replay does not make yet ({unmade})");
        }

        using var scribe = new UndoScribe();
        var files = recorded.GetProperty("files").EnumerateArray().ToList();
        var paths = new List<string>();
        foreach (JsonElement file in files)
        {
            string path = file.GetProperty("path").GetString()!;
            paths.Add(path);
            scribe.WritePage("A", path, Bytes(file.GetProperty("before")));
        }
        // Each folder a step makes is judged by its path, hashed by its
        // listing, and absent before the action (#899 W8-13).
        if (recorded.TryGetProperty("trees", out JsonElement trees))
        {
            foreach (JsonElement tree in trees.EnumerateArray()) paths.Add(tree.GetProperty("path").GetString()!);
        }
        // A converted step's action is the REAL Windows action on the mac's
        // fixture (#899 W7b1), so each trace judges what Windows wrote; the
        // rest still make the recorded step's draft through the door.
        string stepName = recorded.GetProperty("name").GetString()!;
        bool byTheWindowsAction = WindowsActionsOnTheMacFixture.Converted.Contains(stepName);
        if (byTheWindowsAction) WindowsActionsOnTheMacFixture.Lay(scribe.FullPath("A", ""), recorded);
        // A step whose bytes are Windows' own, measured (#899 W7b2-10, review 1
        // L2), keyed by the dictionaries so that every entry a later piece adds
        // is covered: each state the trace names by the mac's hash is judged on
        // the hash of what Windows itself wrote for that state.
        var measured = new MeasuredStates(stepName, recorded, scribe);
        var calls = trace.GetProperty("calls").EnumerateArray().ToList();
        int closingRedos = 0;
        for (int index = calls.Count - 1; index >= 0 && calls[index].GetProperty("call").GetString() == "redo"; index--) closingRedos++;
        int lastUndoOfTheClosingRun = calls.Count - closingRedos - 1;
        Dictionary<string, string?>? afterUndoingAll = null;
        UndoDoor Door() => scribe.Door(maintainers: new UndoSectionFrontPage());

        for (int index = 0; index < calls.Count; index++)
        {
            JsonElement call = calls[index];
            string where = $"{name}, call {index + 1} ({call.GetProperty("call").GetString()})";
            switch (call.GetProperty("call").GetString())
            {
                case "action":
                {
                    (string Word, long? Seq) made;
                    if (byTheWindowsAction)
                    {
                        var workspace = new Plantoir.Core.Assist.AssistWorkspace(scribe.FullPath("A", ""), new FakeLauncher())
                        {
                            Surface = WindowsActionsOnTheMacFixture.SurfaceFor(recorded.GetProperty("madeBy").GetString()!),
                            UndoList = new UndoForThisProcess(scribe.JournalFolder, UndoMode.Live, null, scribe.Clock),
                            UndoDoorOfATest = Door(),
                        };
                        measured.BeforeTheAction();
                        string answered = WindowsActionsOnTheMacFixture.Run(stepName, workspace);
                        made = NewestClosing(scribe);
                        Assert.True(made.Word != "", $"{where}: the Windows action made no step: {answered}");
                        measured.AfterTheAction(where);
                    }
                    else
                    {
                        UndoOutcome outcome = recorded.TryGetProperty("members", out _)
                            ? Door().Perform(MembersDraft(scribe, recorded))
                            : Door().Perform(Draft(scribe, recorded));
                        made = (outcome.Word, outcome.Seq);
                    }
                    Assert.True(call.GetProperty("expect").GetString() == made.Word, $"{where}: came to {made.Word}");
                    if (call.TryGetProperty("seq", out JsonElement seq)) Assert.True(seq.GetInt64() == made.Seq, where);
                    var expected = call.GetProperty("ops").EnumerateArray().Select(op => op.GetString()!).ToList();
                    if (measured.OwnFile is { } ownOp)
                    {
                        int firstRecompute = expected.IndexOf(UndoOp.Recompute);
                        expected.Insert(firstRecompute < 0 ? expected.Count : firstRecompute, ownOp.Op);
                    }
                    Assert.True(expected.SequenceEqual(LastBeginsOpKinds(scribe)),
                                $"{where}: ops {string.Join(",", LastBeginsOpKinds(scribe))}");
                    // The files' ops in the order the step recorded them, as the
                    // mac's door takes them: an Undo checks them newest first,
                    // so this order decides which page a refusal names first.
                    var recordedOrder = new List<string>();
                    foreach (JsonElement file in files)
                    {
                        if (file.GetProperty("before").ToString() == file.GetProperty("after").ToString()
                            && file.GetProperty("before").ValueKind == file.GetProperty("after").ValueKind) continue;
                        recordedOrder.Add(file.GetProperty("path").GetString()!);
                    }
                    if (measured.OwnFile is { } ownPath) recordedOrder.Add(ownPath.Path);
                    if (recorded.TryGetProperty("trees", out JsonElement madeTrees))
                    {
                        foreach (JsonElement tree in madeTrees.EnumerateArray()) recordedOrder.Add(tree.GetProperty("path").GetString()!);
                    }
                    Assert.True(recordedOrder.SequenceEqual(LastBeginsFilePaths(scribe)),
                                $"{where}: files in the order {string.Join(" | ", LastBeginsFilePaths(scribe))}");
                    break;
                }
                case "undo":
                case "redo":
                {
                    bool undo = call.GetProperty("call").GetString() == "undo";
                    UndoOutcome outcome = undo ? Door().Undo() : Door().Redo();
                    measured.AfterUndoOrRedo(outcome.Word);
                    Assert.True(call.GetProperty("expect").GetString() == outcome.Word, $"{where}: came to {outcome.Word}");
                    if (call.TryGetProperty("seq", out JsonElement seq)) Assert.True(seq.GetInt64() == outcome.Seq, where);
                    if (outcome.Word == "changedSince")
                    {
                        Assert.True(call.GetProperty("path").GetString() == outcome.Refusal?.Path, $"{where}: named {outcome.Refusal?.Path}");
                        Assert.True(call.GetProperty("others").GetInt32() == (outcome.Refusal?.Others ?? 0), where);
                        Assert.True(call.TryGetProperty(undo ? "clearedTheList" : "droppedTheRedo", out JsonElement flag) && flag.GetBoolean(), where);
                    }
                    break;
                }
                case "handEdit":
                {
                    string path = call.GetProperty("path").GetString()!;
                    string kind = call.GetProperty("kind").GetString()!;
                    if (kind == "deletePage" && Directory.Exists(scribe.FullPath("A", path)))
                    {
                        // A folder the step made, removed by hand (#899 W8-13).
                        Directory.Delete(scribe.FullPath("A", path), recursive: true);
                        break;
                    }
                    if (scribe.Page("A", path) is null) break;
                    if (kind == "deletePage")
                    {
                        scribe.WritePage("A", path, null);
                        break;
                    }
                    string? text = scribe.Page("A", path) is { } bytes ? UndoCheck.DecodeStrictly(bytes) : null;
                    string? edited = UndoTraceEdits.HandEdit(kind, text);
                    Assert.True(edited is not null, where + ": the trace's hand edit could not be made");
                    measured.HandEdited(where, kind, scribe.Page("A", path)!, Encoding.UTF8.GetBytes(edited!));
                    scribe.WritePage("A", path, Encoding.UTF8.GetBytes(edited!));
                    break;
                }
                case "note":
                    scribe.Note();
                    break;
                default:
                    Assert.Fail(where + ": a call this replay does not know");
                    break;
            }

            measured.TheOwnFileIsWhereTheStepLeftIt(where);
            UndoOffered offered = scribe.Offer();
            Assert.True(NullableSeq(call, "head") == offered.Head?.Seq, $"{where}: head {offered.Head?.Seq}");
            Assert.True(NullableSeq(call, "redo") == offered.Redo.Seq, $"{where}: redo {offered.Redo.Seq}");

            if (index == lastUndoOfTheClosingRun) afterUndoingAll = Hashes(scribe, paths);
        }

        Assert.Empty(scribe.StagedLeftovers("A"));
        Assert.NotNull(afterUndoingAll);
        AssertHashes(trace.GetProperty("afterUndoingAll"), afterUndoingAll!, name + " afterUndoingAll", measured);
        AssertHashes(trace.GetProperty("final"), Hashes(scribe, paths), name + " final", measured);
    }

    /// <summary>The recorded step as an action hands it to the door: each file's before and after, then its recompute ops.</summary>
    private static UndoStepDraft Draft(UndoScribe scribe, JsonElement recorded)
    {
        var changes = new List<UndoFileChange>();
        foreach (JsonElement file in recorded.GetProperty("files").EnumerateArray())
        {
            string path = file.GetProperty("path").GetString()!;
            changes.Add(new UndoFileChange(path, scribe.Page("A", path), Bytes(file.GetProperty("after"))));
        }
        var recomputes = new List<JsonObject>();
        foreach (JsonElement recompute in recorded.GetProperty("recomputes").EnumerateArray())
        {
            recomputes.Add(new JsonObject
            {
                ["kind"] = UndoOp.Recompute,
                ["maintainer"] = recompute.GetProperty("maintainer").GetString(),
                ["path"] = recompute.GetProperty("path").GetString(),
                ["section"] = recompute.GetProperty("section").GetInt64(),
            });
        }
        return new UndoStepDraft
        {
            ActionKey = recorded.GetProperty("action").GetString()!,
            ActionArguments = new Dictionary<string, string>(StringComparer.Ordinal) { ["pageCount"] = changes.Count.ToString(System.Globalization.CultureInfo.InvariantCulture) },
            MadeBy = recorded.GetProperty("madeBy").GetString()!,
            WorkingFolder = scribe.FullPath("A", ""),
            Course = "ICS3U",
            Section = 1,
            Class = "A",
            Holds = "section",
            Changes = changes,
            Recomputes = recomputes,
        };
    }

    /// <summary>
    /// A recorded step with <c>members</c> as its action hands it to the door
    /// (#899 W8-11; the mac's <c>JournaledStep.makeAsOps</c>): each member as
    /// the recorded <c>editJSON</c> op, its key path, before and after (no
    /// before or after where the member was absent), in the recorded order,
    /// then its recompute ops, through the door that takes every kind. Never
    /// the file worked out by the door's line rule.
    /// </summary>
    private static UndoOpsDraft MembersDraft(UndoScribe scribe, JsonElement recorded)
    {
        var ops = new JsonArray();
        foreach (JsonElement member in recorded.GetProperty("members").EnumerateArray())
        {
            var op = new JsonObject
            {
                ["kind"] = UndoOp.EditJson,
                ["path"] = member.GetProperty("path").GetString(),
                ["keyPath"] = JsonNode.Parse(member.GetProperty("keyPath").GetRawText()),
            };
            if (member.TryGetProperty("before", out JsonElement before)) op["before"] = JsonNode.Parse(before.GetRawText());
            if (member.TryGetProperty("after", out JsonElement after)) op["after"] = JsonNode.Parse(after.GetRawText());
            ops.Add(op);
        }
        foreach (JsonElement recompute in recorded.GetProperty("recomputes").EnumerateArray())
        {
            ops.Add(new JsonObject
            {
                ["kind"] = UndoOp.Recompute,
                ["maintainer"] = recompute.GetProperty("maintainer").GetString(),
                ["path"] = recompute.GetProperty("path").GetString(),
                ["section"] = recompute.GetProperty("section").GetInt64(),
            });
        }
        return new UndoOpsDraft
        {
            ActionKey = recorded.GetProperty("action").GetString()!,
            ActionArguments = new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["pageCount"] = recorded.GetProperty("files").GetArrayLength().ToString(System.Globalization.CultureInfo.InvariantCulture),
            },
            MadeBy = recorded.GetProperty("madeBy").GetString()!,
            WorkingFolder = scribe.FullPath("A", ""),
            Course = "ICS3U",
            Class = "A",
            Holds = "course",
            Ops = ops,
        };
    }

    /// <summary>How the newest step on the list closed (its last line's event, <c>applied</c> when it went in) and its number; empty when the list holds no step.</summary>
    private static (string Word, long? Seq) NewestClosing(UndoScribe scribe)
    {
        JsonObject? last = null;
        foreach (string segment in Directory.EnumerateFiles(scribe.JournalFolder, "journal-*.jsonl").Order(StringComparer.Ordinal))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && read["seq"] is not null) last = read;
            }
        }
        return last is null ? ("", null) : ((string?)last["event"] ?? "", (long?)last["seq"]);
    }

    /// <summary>The op kinds of the newest begin line on the list, in order.</summary>
    private static List<string> LastBeginsOpKinds(UndoScribe scribe)
    {
        JsonObject? last = null;
        foreach (string segment in Directory.EnumerateFiles(scribe.JournalFolder, "journal-*.jsonl").Order(StringComparer.Ordinal))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && (string?)read["event"] == "begin") last = read;
            }
        }
        var kinds = new List<string>();
        if (last?["step"]?["ops"] is JsonArray ops)
        {
            foreach (JsonNode? op in ops) kinds.Add((string)op!["kind"]!);
        }
        return kinds;
    }

    /// <summary>Each file the newest begin line's ops change, once, in the order its ops name them (recompute ops left out).</summary>
    private static List<string> LastBeginsFilePaths(UndoScribe scribe)
    {
        JsonObject? last = null;
        foreach (string segment in Directory.EnumerateFiles(scribe.JournalFolder, "journal-*.jsonl").Order(StringComparer.Ordinal))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && (string?)read["event"] == "begin") last = read;
            }
        }
        var paths = new List<string>();
        if (last?["step"]?["ops"] is JsonArray ops)
        {
            foreach (JsonNode? op in ops)
            {
                if ((string?)op!["kind"] == UndoOp.Recompute) continue;
                string path = (string)op["path"]!;
                if (!paths.Contains(path)) paths.Add(path);
            }
        }
        return paths;
    }

    private static Dictionary<string, string?> Hashes(UndoScribe scribe, IReadOnlyList<string> paths)
    {
        var hashes = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (string path in paths)
        {
            // A folder is hashed by its listing (undo-traces.json, U4b2-12).
            if (Directory.Exists(scribe.FullPath("A", path)))
            {
                hashes[path] = UndoTreeReading.Read(scribe.FullPath("A", path)).ListingSha;
                continue;
            }
            byte[]? bytes = scribe.Page("A", path);
            hashes[path] = bytes is null ? null : UndoCheck.Sha(bytes);
        }
        return hashes;
    }

    private static void AssertHashes(JsonElement expected, Dictionary<string, string?> actual, string where, MeasuredStates measured)
    {
        foreach (JsonProperty page in expected.EnumerateObject())
        {
            string? want = page.Value.ValueKind == JsonValueKind.Null ? null : page.Value.GetString();
            want = measured.WindowsHashFor(want, $"{where}: {page.Name}");
            Assert.True(actual.ContainsKey(page.Name), $"{where}: {page.Name} is not a file of the step");
            Assert.True(want == actual[page.Name], $"{where}: {page.Name} is {actual[page.Name] ?? "absent"}, the trace's {want ?? "absent"}");
        }
    }

    private static long? NullableSeq(JsonElement element, string key) =>
        element.GetProperty(key).ValueKind == JsonValueKind.Null ? null : element.GetProperty(key).GetInt64();
}

/// <summary>
/// The states of a converted step whose bytes are Windows' own, measured
/// (<see cref="WindowsActionsOnTheMacFixture.WindowsOwnJson"/>,
/// <see cref="WindowsActionsOnTheMacFixture.WindowsOwnFileInTheStep"/>), so its
/// traces judge what Windows wrote (#899 W7b2-10, review 1 L2). Each state
/// the replay reaches (the before, what the action wrote, each hand edit) is
/// recorded twice: the hash of Windows' bytes, and the hash of the mac's
/// bytes for the same state (the recorded before and after, the trace's hand
/// edit made to them). A trace's expected hash is turned into Windows' hash
/// of that state, and the file is compared with that; never with the mac's
/// bytes. The one file more is judged on Windows' own bytes alone: what the
/// action wrote while the step is done, its before while it is undone. A
/// file that is not Windows' own JSON must be the mac's bytes after the
/// action, so its hashes pass through unchanged.
/// </summary>
internal sealed class MeasuredStates
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _stepName;
    private readonly JsonElement _recorded;
    private readonly UndoScribe _scribe;
    private readonly bool _ownJson;
    private readonly string[] _sameMembers = [];
    private readonly Dictionary<string, string> _windowsHashOfMacHash = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _macTextOfMacHash = new(StringComparer.Ordinal);
    private byte[]? _ownBefore;
    private byte[]? _ownAfter;
    private bool _stepIsDone;

    /// <summary>The one file more Windows' step holds, or null.</summary>
    internal (string Path, string Op, string Why)? OwnFile { get; }

    // ---- Computed properties -------------------------------------------------------

    private bool IsMeasured => _ownJson || OwnFile is not null;

    // ---- Initializer ---------------------------------------------------------------

    internal MeasuredStates(string stepName, JsonElement recorded, UndoScribe scribe)
    {
        _stepName = stepName;
        _recorded = recorded;
        _scribe = scribe;
        if (WindowsActionsOnTheMacFixture.WindowsOwnJson.TryGetValue(stepName, out var json))
        {
            _ownJson = true;
            _sameMembers = json.SameMembers;
        }
        if (WindowsActionsOnTheMacFixture.WindowsOwnFileInTheStep.TryGetValue(stepName, out var own)) OwnFile = own;
    }

    // ---- Functions -----------------------------------------------------------------

    /// <summary>Records each file's before, as laid (the mac's bytes), and the one file more's before.</summary>
    internal void BeforeTheAction()
    {
        if (!IsMeasured) return;
        foreach (JsonElement file in _recorded.GetProperty("files").EnumerateArray())
        {
            byte[]? laid = _scribe.Page("A", file.GetProperty("path").GetString()!);
            byte[]? mac = WindowsActionsOnTheMacFixture.Bytes(file.GetProperty("before"));
            Assert.True(mac is null ? laid is null : laid is not null && mac.AsSpan().SequenceEqual(laid),
                        $"{_stepName}: the laid before is not the recorded before");
            if (mac is not null) Remember(mac, laid!);
        }
        if (OwnFile is { } own) _ownBefore = _scribe.Page("A", own.Path);
    }

    /// <summary>Records what Windows wrote for each file, checks the members that must be the mac's, and the one file more.</summary>
    internal void AfterTheAction(string where)
    {
        if (!IsMeasured) return;
        _stepIsDone = true;
        foreach (JsonElement file in _recorded.GetProperty("files").EnumerateArray())
        {
            string path = file.GetProperty("path").GetString()!;
            byte[]? written = _scribe.Page("A", path);
            byte[]? mac = WindowsActionsOnTheMacFixture.Bytes(file.GetProperty("after"));
            Assert.True((mac is null) == (written is null), $"{where}: {path} is {(written is null ? "absent" : "present")} where the mac's is not");
            if (mac is null) continue;
            if (_ownJson)
            {
                JsonNode macJson = JsonNode.Parse(mac)!;
                JsonNode windowsJson = JsonNode.Parse(written!)!;
                foreach (string member in _sameMembers)
                    Assert.True(JsonNode.DeepEquals(macJson[member], windowsJson[member]), $"{where}: {path}'s {member} is {windowsJson[member]?.ToJsonString()}, the mac's {macJson[member]?.ToJsonString()}");
            }
            else
            {
                Assert.True(mac.AsSpan().SequenceEqual(written), $"{where}: {path} is not the mac's after");
            }
            Remember(mac, written!);
        }
        if (OwnFile is { } own)
        {
            _ownAfter = _scribe.Page("A", own.Path);
            Assert.True(_ownAfter is not null, $"{where}: the action wrote no {own.Path}");
            JsonNode writtenDown = JsonNode.Parse(_ownAfter!)!;
            Assert.StartsWith("block ", (string?)writtenDown["source"]);
        }
    }

    /// <summary>An Undo or a Redo that went in moves the one file more with the step.</summary>
    internal void AfterUndoOrRedo(string word)
    {
        if (word == "undone") _stepIsDone = false;
        else if (word == "redone") _stepIsDone = true;
    }

    /// <summary>The trace's hand edit made to the mac's bytes of the same state, recorded beside Windows' edited bytes.</summary>
    internal void HandEdited(string where, string kind, byte[] windowsBefore, byte[] windowsEdited)
    {
        if (!_ownJson) return;
        string windowsHash = UndoCheck.Sha(windowsBefore);
        string? macHash = null;
        foreach (KeyValuePair<string, string> pair in _windowsHashOfMacHash)
        {
            if (pair.Value == windowsHash) macHash = pair.Key;
        }
        Assert.True(macHash is not null, $"{where}: the page holds a state the mac's step never reached");
        string? macEdited = UndoTraceEdits.HandEdit(kind, _macTextOfMacHash[macHash!]);
        Assert.True(macEdited is not null, $"{where}: the trace's hand edit could not be made to the mac's bytes");
        Remember(Encoding.UTF8.GetBytes(macEdited!), windowsEdited);
    }

    /// <summary>One state: the mac's bytes and Windows' bytes for it.</summary>
    private void Remember(byte[] mac, byte[] windows)
    {
        string macHash = UndoCheck.Sha(mac);
        _windowsHashOfMacHash[macHash] = UndoCheck.Sha(windows);
        _macTextOfMacHash[macHash] = Encoding.UTF8.GetString(mac);
    }

    /// <summary>The one file more holds Windows' own after while the step is done, its own before while it is undone.</summary>
    internal void TheOwnFileIsWhereTheStepLeftIt(string where)
    {
        if (OwnFile is not { } own || _ownAfter is null) return;
        byte[]? want = _stepIsDone ? _ownAfter : _ownBefore;
        byte[]? have = _scribe.Page("A", own.Path);
        Assert.True(want is null ? have is null : have is not null && want.AsSpan().SequenceEqual(have),
                    $"{where}: {own.Path} is not what the step {(_stepIsDone ? "wrote" : "found")}");
    }

    /// <summary>
    /// Windows' hash of the state a trace names by the mac's hash. A file
    /// that is not Windows' own JSON was checked to be the mac's bytes after
    /// the action, so its hashes pass through unchanged: a line edit undone
    /// or redone over a hand edit makes a state no table could hold
    /// (action-062), and the mac's hash of it is Windows' own.
    /// </summary>
    internal string? WindowsHashFor(string? macHash, string where)
    {
        if (!_ownJson || macHash is null) return macHash;
        Assert.True(_windowsHashOfMacHash.TryGetValue(macHash, out string? windowsHash), $"{where}: the trace names a state Windows never reached");
        return windowsHash;
    }
}
