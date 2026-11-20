using System.Text;
using System.Text.Json;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/undo-traces.json</c>: the 20 seeded traces, every call,
/// replayed through the product's reader, fold, limits, pruning decisions and
/// all-or-nothing check (#899 piece W1). The pages start from the fixture's
/// <c>utf8Hex</c> bytes (never its <c>text</c>), each step sets its lines with
/// the traces' writer (<see cref="JournaledSetting.SettingEntry"/>, test-only until
/// W2's <c>JournaledSetting</c>), and the journal lines are the scribe's
/// (<see cref="UndoScribe"/>). After every call the folded list must answer the
/// trace's <c>head</c> and <c>redo</c>, every call must come to its
/// <c>expect</c> (the page named and how many others for a refusal), and the
/// pages' hashes must be <c>afterUndoingAll</c> once the closing undos stop and
/// <c>final</c> at the end.
///
/// <para>What W2 adds on top: the same traces through the real door (the
/// lock, the staged swap, the flush), and from U3 the ~120 traces of the real
/// action code.</para>
/// </summary>
public sealed class UndoTraceContractTests
{
    public static IEnumerable<object[]> Traces() =>
        UndoContract.Traces.RootElement.GetProperty("traces").EnumerateArray()
            .Select(trace => new object[] { trace.GetProperty("name").GetString()! });

    [Fact]
    public void TheContractHoldsTwentyTracesOf612Calls()
    {
        var traces = UndoContract.Traces.RootElement.GetProperty("traces").EnumerateArray().ToList();
        Assert.True(traces.Count >= 20);
        Assert.True(traces.Sum(trace => trace.GetProperty("calls").GetArrayLength()) >= 612);
    }

    [Fact]
    public void TheFixturePagesAreTheirBytes()
    {
        JsonElement hashes = UndoContract.Traces.RootElement.GetProperty("fixtureHashes");
        var fixture = UndoContract.Fixture;
        Assert.Equal(8, fixture.Count);
        foreach ((string id, _, byte[] bytes) in fixture)
            Assert.Equal(hashes.GetProperty(id).GetString(), UndoCheck.Sha(bytes));
        // p6's byte-order mark is in the bytes, where a JSON reader of `text` may drop it.
        Assert.Equal([0xEF, 0xBB, 0xBF], fixture.Single(page => page.Id == "p6").Bytes[..3]);
    }

    /// <summary>Every trace held open by name (it holds U2's <c>move</c>, which W6 brings) is a trace the contract still has.</summary>
    [Fact]
    public void EveryHeldTraceIsStillInTheContract() =>
        NamedGapLedger.StillNamed(NamedGapLedger.UndoTraces, Traces().Select(row => (string)row[0]));

    /// <summary>
    /// Every trace, every call. A trace the ledger holds open is replayed and
    /// asserted call by call exactly as any other up to its first call this
    /// replay does not know, and must still stop there; it goes from the
    /// ledger the day it plays through.
    /// </summary>
    [Theory]
    [MemberData(nameof(Traces))]
    public void EveryCallOfEveryTrace(string name) => ReplayAsTheLedgerSays(name, NamedGapLedger.All, () => ReplayTheTrace(name));

    /// <summary>
    /// One trace, replayed by <paramref name="replay"/>, held or not as
    /// <paramref name="entries"/> say. <see cref="EveryCallOfEveryTrace"/>
    /// passes the real replay; <see cref="TheDayAHeldTracePlaysThroughItFails"/>
    /// passes W6's, to prove that a held trace does not outlive its gap.
    /// </summary>
    private static void ReplayAsTheLedgerSays(string name, IEnumerable<NamedGapLedger.Entry> entries, Action replay)
    {
        if (NamedGapLedger.Holding(NamedGapLedger.UndoTraces, name, entries) is { } held)
        {
            // It must stop exactly at its first move: every call before that is asserted in full.
            NamedGapLedger.HeldCaseStillStopsAtItsGap(held, replay, $"{name}, call {FirstMoveOf(name)} (move): a call this replay does not know");
            return;
        }
        replay();
    }

    /// <summary>The 1-based number of the trace's first <c>move</c> call, the call a held trace stops at.</summary>
    private static int FirstMoveOf(string name)
    {
        JsonElement trace = UndoContract.Traces.RootElement.GetProperty("traces").EnumerateArray()
            .Single(candidate => candidate.GetProperty("name").GetString() == name);
        int number = 0;
        foreach (JsonElement call in trace.GetProperty("calls").EnumerateArray())
        {
            number++;
            if (call.GetProperty("call").GetString() == "move") return number;
        }
        Assert.Fail($"\"{name}\" is held for its move, and it has none: the gap it was held for is gone");
        return 0;
    }

    /// <summary>
    /// Proves, on a real held trace, that a held trace does not outlive its
    /// gap: as it stands it is asserted call by call to its first
    /// <c>move</c> and stops there; replayed to the end (as W6's replay will)
    /// it fails as the gap closing; stopped by anything else (a call before
    /// the move that comes out wrong) it fails as a real failure.
    /// </summary>
    [Fact]
    public void TheDayAHeldTracePlaysThroughItFails()
    {
        const string name = "trace-003";
        Assert.NotNull(NamedGapLedger.Holding(NamedGapLedger.UndoTraces, name));

        ReplayAsTheLedgerSays(name, NamedGapLedger.All, () => ReplayTheTrace(name));
        var playedThrough = Assert.ThrowsAny<Exception>(() => ReplayAsTheLedgerSays(name, NamedGapLedger.All, () => { }));
        Assert.Contains("now EXISTS on this side", playedThrough.Message);
        var otherReason = Assert.ThrowsAny<Exception>(() => ReplayAsTheLedgerSays(name, NamedGapLedger.All, () => Assert.Fail("trace-003, call 9 (undo): head 3, expected 2")));
        Assert.Contains("failed for another reason", otherReason.Message);
    }

    private static void ReplayTheTrace(string name)
    {
        JsonElement trace = UndoContract.Traces.RootElement.GetProperty("traces").EnumerateArray()
            .Single(candidate => candidate.GetProperty("name").GetString() == name);
        var fixture = UndoContract.Fixture;
        var paths = fixture.ToDictionary(page => page.Id, page => page.Path, StringComparer.Ordinal);
        string PageId(string path) => paths.First(pair => pair.Value == path).Key;

        using var scribe = new UndoScribe();
        scribe.WriteFixture("A");

        var calls = trace.GetProperty("calls").EnumerateArray().ToList();
        int closingRedos = 0;
        for (int index = calls.Count - 1; index >= 0 && calls[index].GetProperty("call").GetString() == "redo"; index--) closingRedos++;
        int lastUndoOfTheClosingRun = calls.Count - closingRedos - 1;
        Dictionary<string, string?>? afterUndoingAll = null;

        for (int index = 0; index < calls.Count; index++)
        {
            JsonElement call = calls[index];
            string where = $"{name}, call {index + 1} ({call.GetProperty("call").GetString()})";
            switch (call.GetProperty("call").GetString())
            {
                case "step":
                {
                    var changes = new List<(string, byte[]?)>();
                    var pages = new Dictionary<string, string?>(StringComparer.Ordinal);
                    foreach (JsonElement set in call.GetProperty("set").EnumerateArray())
                    {
                        string path = paths[set.GetProperty("page").GetString()!];
                        if (!pages.ContainsKey(path))
                            pages[path] = scribe.Page("A", path) is { } bytes ? UndoCheck.DecodeStrictly(bytes) : null;
                        if (pages[path] is not { } text) continue;   // the page is gone: left alone
                        if (JournaledSetting.SettingEntry(set.GetProperty("key").GetString()!, set.GetProperty("line").GetString()!, text) is { } changed)
                            pages[path] = changed;
                    }
                    foreach ((string path, string? text) in pages)
                        if (text is not null) changes.Add((path, Encoding.UTF8.GetBytes(text)));
                    long? seq = scribe.Step("A", changes);
                    Assert.True(call.GetProperty("expect").GetString() == (seq is null ? "changedNothing" : "applied"), where);
                    if (seq is not null) Assert.True(call.GetProperty("seq").GetInt64() == seq, where);
                    break;
                }
                case "undo":
                case "redo":
                {
                    bool undo = call.GetProperty("call").GetString() == "undo";
                    UndoScribe.Outcome outcome = undo ? scribe.Undo() : scribe.Redo();
                    Assert.True(call.GetProperty("expect").GetString() == outcome.Name, $"{where}: came to {outcome.Name}");
                    if (call.TryGetProperty("seq", out JsonElement seq)) Assert.True(seq.GetInt64() == outcome.Seq, where);
                    if (outcome.Name == "changedSince")
                    {
                        Assert.True(call.GetProperty("page").GetString() == PageId(outcome.Page!), where);
                        Assert.True(call.GetProperty("others").GetInt32() == outcome.Others, where);
                        Assert.True(call.TryGetProperty(undo ? "clearedTheList" : "droppedTheRedo", out JsonElement flag) && flag.GetBoolean(), where);
                    }
                    break;
                }
                case "handEdit":
                {
                    string path = paths[call.GetProperty("page").GetString()!];
                    string kind = call.GetProperty("kind").GetString()!;
                    if (kind == "deletePage")
                    {
                        Assert.NotNull(scribe.Page("A", path));
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

            if (index == lastUndoOfTheClosingRun) afterUndoingAll = Hashes(scribe, fixture);
        }

        Assert.NotNull(afterUndoingAll);
        AssertHashes(trace.GetProperty("afterUndoingAll"), afterUndoingAll!, name + " afterUndoingAll");
        AssertHashes(trace.GetProperty("final"), Hashes(scribe, fixture), name + " final");
    }

    private static Dictionary<string, string?> Hashes(UndoScribe scribe, IReadOnlyList<(string Id, string Path, byte[] Bytes)> fixture) =>
        fixture.ToDictionary(page => page.Id, page => scribe.Page("A", page.Path) is { } bytes ? UndoCheck.Sha(bytes) : null, StringComparer.Ordinal);

    private static void AssertHashes(JsonElement expected, Dictionary<string, string?> actual, string where)
    {
        foreach (JsonProperty page in expected.EnumerateObject())
        {
            string? want = page.Value.ValueKind == JsonValueKind.Null ? null : page.Value.GetString();
            Assert.True(want == actual[page.Name], $"{where}: {page.Name}");
        }
    }

    private static long? NullableSeq(JsonElement element, string key) =>
        element.GetProperty(key).ValueKind == JsonValueKind.Null ? null : element.GetProperty(key).GetInt64();
}
