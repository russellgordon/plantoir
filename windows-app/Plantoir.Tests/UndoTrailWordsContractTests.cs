using System.Text.Json;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// U3c's four trail lines (#899 W4c), each against the example line
/// <c>contracts/shared-rules.json</c> → <c>activityTrail.mustRecord</c> gives
/// for its event, read from the JSON, never retyped: when the mac rewords a
/// line, this goes red here until Windows says the same.
/// </summary>
public sealed class UndoTrailWordsContractTests
{
    private const string Prefix = "ICS3U/1 · ";

    private static string ExampleLine(string eventName)
    {
        foreach (JsonElement row in UndoContract.SharedRules.RootElement.GetProperty("activityTrail").GetProperty("mustRecord").EnumerateArray())
        {
            if (row.TryGetProperty("event", out JsonElement name) && name.GetString() == eventName)
            {
                string line = row.GetProperty("line").GetString()!;
                Assert.StartsWith(Prefix, line);
                return line[Prefix.Length..];
            }
        }
        Assert.Fail("mustRecord has no event " + eventName);
        return "";
    }

    [Fact]
    public void CouldNotPutBackSaysWhatTheContractSays() =>
        Assert.Equal(ExampleLine("undo could not put back a change that stopped"),
                     UndoTrail.CouldNotPutBackWords(UndoPhase.Begin, 1, [".A.md.plantoir-undo-4-apply-orig"]));

    [Fact]
    public void KeptWhatAPageHeldSaysWhatTheContractSays() =>
        Assert.Equal(ExampleLine("undo kept what a page held"),
                     UndoTrail.KeptWhatAPageHeldWords(UndoPhase.Begin, [".A.md.plantoir-undo-4-apply-orig"], []));

    [Fact]
    public void KeptWhatItReplacedSaysWhatTheContractSays() =>
        Assert.Equal(ExampleLine("undo kept what it replaced"),
                     UndoTrail.KeptWhatItReplacedWords(true, [".A.md.plantoir-undo-4-undo-orig"], []));

    [Fact]
    public void RefusedForAChangeLeftPartWaySaysWhatTheContractSays() =>
        Assert.Equal(ExampleLine("undo refused for a change left part way"),
                     UndoTrail.LeftNewestWords(true, new UndoRefusal(UndoRefusalKind.FileIsInUse, "courses/ICS3U/Section 1/Classes/A.md")));
}
