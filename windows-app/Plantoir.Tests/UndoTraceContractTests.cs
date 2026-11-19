using System.Text;
using System.Text.Json;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/undo-traces.json</c>: the 20 seeded traces, every call,
/// replayed through the product's reader, fold, limits, pruning decisions and
/// all-or-nothing check (#899 piece W1). The pages start from the fixture's
/// <c>utf8Hex</c> bytes (never its <c>text</c>), each step sets its lines with
/// the traces' writer (<see cref="UndoLineOps.SettingEntry"/>, test-only until
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

    [Theory]
    [MemberData(nameof(Traces))]
    public void EveryCallOfEveryTrace(string name)
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
                        if (UndoLineOps.SettingEntry(set.GetProperty("key").GetString()!, set.GetProperty("line").GetString()!, text) is { } changed)
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
                    string? edited = UndoLineOps.HandEdit(kind, text);
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
