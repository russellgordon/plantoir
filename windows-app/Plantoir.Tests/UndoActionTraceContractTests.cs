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
/// with no settings is left alone). A recorded step with <c>moves</c>,
/// <c>members</c> or <c>trees</c> is held by name in the ledger.
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
        foreach (string unmade in new[] { "moves", "members", "trees" })
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
        // A converted step's action is the REAL Windows action on the mac's
        // fixture (#899 W7b1), so each trace judges what Windows wrote; the
        // rest still make the recorded step's draft through the door.
        string stepName = recorded.GetProperty("name").GetString()!;
        bool byTheWindowsAction = WindowsActionsOnTheMacFixture.Converted.Contains(stepName)
                                  && !WindowsActionsOnTheMacFixture.WindowsOwnLine.ContainsKey(stepName)
                                  && !WindowsActionsOnTheMacFixture.WindowsOwnJson.ContainsKey(stepName);
        if (byTheWindowsAction) WindowsActionsOnTheMacFixture.Lay(scribe.FullPath("A", ""), recorded);
        // A new class page of this build carries the checkout's line endings
        // (WindowsActionsOnTheMacFixture.NewClassPageSteps, measured there to
        // the byte against the mac's after): the trace's hashes are the mac's
        // bytes, so on a CRLF build such a page is hashed with its CRLFs read
        // as the mac's LFs. Every other page, and every page of an LF build,
        // is hashed as it is.
        var checkoutLineEndings = new HashSet<string>(StringComparer.Ordinal);
        if (byTheWindowsAction && WindowsActionsOnTheMacFixture.RawLiteralsCarryCrLf
            && WindowsActionsOnTheMacFixture.NewClassPageSteps.Contains(stepName))
        {
            foreach (JsonElement file in files)
            {
                if (file.GetProperty("before").ValueKind == JsonValueKind.Null)
                    checkoutLineEndings.Add(file.GetProperty("path").GetString()!);
            }
        }

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
                        string answered = WindowsActionsOnTheMacFixture.Run(stepName, workspace);
                        made = NewestClosing(scribe);
                        Assert.True(made.Word != "", $"{where}: the Windows action made no step: {answered}");
                    }
                    else
                    {
                        UndoOutcome outcome = Door().Perform(Draft(scribe, recorded));
                        made = (outcome.Word, outcome.Seq);
                    }
                    Assert.True(call.GetProperty("expect").GetString() == made.Word, $"{where}: came to {made.Word}");
                    if (call.TryGetProperty("seq", out JsonElement seq)) Assert.True(seq.GetInt64() == made.Seq, where);
                    var expected = call.GetProperty("ops").EnumerateArray().Select(op => op.GetString()!).ToList();
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
                    Assert.True(recordedOrder.SequenceEqual(LastBeginsFilePaths(scribe)),
                                $"{where}: files in the order {string.Join(" | ", LastBeginsFilePaths(scribe))}");
                    break;
                }
                case "undo":
                case "redo":
                {
                    bool undo = call.GetProperty("call").GetString() == "undo";
                    UndoOutcome outcome = undo ? Door().Undo() : Door().Redo();
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
                    if (scribe.Page("A", path) is null) break;
                    if (kind == "deletePage")
                    {
                        scribe.WritePage("A", path, null);
                        break;
                    }
                    string? text = scribe.Page("A", path) is { } bytes ? UndoCheck.DecodeStrictly(bytes) : null;
                    string? edited = UndoTraceEdits.HandEdit(kind, text);
                    Assert.True(edited is not null, where + ": the trace's hand edit could not be made");
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

            UndoOffered offered = scribe.Offer();
            Assert.True(NullableSeq(call, "head") == offered.Head?.Seq, $"{where}: head {offered.Head?.Seq}");
            Assert.True(NullableSeq(call, "redo") == offered.Redo.Seq, $"{where}: redo {offered.Redo.Seq}");

            if (index == lastUndoOfTheClosingRun) afterUndoingAll = Hashes(scribe, paths, checkoutLineEndings);
        }

        Assert.Empty(scribe.StagedLeftovers("A"));
        Assert.NotNull(afterUndoingAll);
        AssertHashes(trace.GetProperty("afterUndoingAll"), afterUndoingAll!, name + " afterUndoingAll");
        AssertHashes(trace.GetProperty("final"), Hashes(scribe, paths, checkoutLineEndings), name + " final");
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

    private static Dictionary<string, string?> Hashes(UndoScribe scribe, IReadOnlyList<string> paths, IReadOnlySet<string> checkoutLineEndings)
    {
        var hashes = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (string path in paths)
        {
            byte[]? bytes = scribe.Page("A", path);
            if (bytes is not null && checkoutLineEndings.Contains(path))
                bytes = new UTF8Encoding(false).GetBytes(Encoding.UTF8.GetString(bytes).Replace("\r\n", "\n"));
            hashes[path] = bytes is null ? null : UndoCheck.Sha(bytes);
        }
        return hashes;
    }

    private static void AssertHashes(JsonElement expected, Dictionary<string, string?> actual, string where)
    {
        foreach (JsonProperty page in expected.EnumerateObject())
        {
            string? want = page.Value.ValueKind == JsonValueKind.Null ? null : page.Value.GetString();
            Assert.True(actual.ContainsKey(page.Name), $"{where}: {page.Name} is not a file of the step");
            Assert.True(want == actual[page.Name], $"{where}: {page.Name} is {actual[page.Name] ?? "absent"}, the trace's {want ?? "absent"}");
        }
    }

    private static long? NullableSeq(JsonElement element, string key) =>
        element.GetProperty(key).ValueKind == JsonValueKind.Null ? null : element.GetProperty(key).GetInt64();
}
