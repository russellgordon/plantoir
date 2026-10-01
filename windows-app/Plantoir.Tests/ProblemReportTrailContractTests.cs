using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>problemReportTrail</c> (GitHub issue #316, the
/// mac's #301): the trail read back into a problem report, from real files
/// written byte for byte.
/// </summary>
public class ProblemReportTrailContractTests : IDisposable
{
    private readonly string _logs = Path.Combine(Path.GetTempPath(), "plantoir-tests", "report-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try { Directory.Delete(_logs, recursive: true); } catch { }
    }

    private static JsonNode Trail => ContractLoader.LoadJson("shared-rules.json")["problemReportTrail"]!;

    [Fact]
    public void TheTwoNotesAreTheContractsAndInItsOrder()
    {
        Assert.Equal(Trail["promptsLeftOutNote"]!.ToString(), ProblemReportStore.PromptsLeftOutNote);
        Assert.Equal(Trail["unreadableCharactersNote"]!.ToString(), ProblemReportStore.UnreadableCharactersNoteTemplate);
        Assert.Equal(new[] { "promptsLeftOutNote", "unreadableCharactersNote" },
            Trail["noteOrder"]!.AsArray().Select(n => n!.ToString()));
    }

    [Fact]
    public void EveryCaseIsReadBackAsTheContractSays()
    {
        var cases = Trail["cases"]!.AsArray();
        Assert.True(cases.Count >= 12, $"problemReportTrail lost cases: {cases.Count} (12 when this was written)");

        Directory.CreateDirectory(_logs);
        var store = new ProblemReportStore(_logs);
        var failures = new List<string>();
        foreach (var c in cases)
        {
            File.WriteAllBytes(store.ActivityFile, Bytes(c!["input"]!.ToString()));
            bool including = c["includingPrompts"]!.GetValue<bool>();
            var expected = c["expectLines"]!.AsArray().Select(n => Expand(n!.ToString())).ToList();
            var actual = store.ActivityText(including).Split('\n').ToList();
            if (!expected.SequenceEqual(actual))
                failures.Add($"{c["name"]}: expected [{string.Join(" | ", expected)}], got [{string.Join(" | ", actual)}]");
            if (c["expectSomethingToReport"]?.GetValue<bool>() is bool something && something != store.HasAnythingToReport)
                failures.Add($"{c["name"]}: something to report should be {something}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    /// <summary>{XX} is one raw byte; everything else is UTF-8.</summary>
    private static byte[] Bytes(string input)
    {
        var bytes = new List<byte>();
        int at = 0;
        foreach (Match match in Regex.Matches(input, "\\{([0-9A-F]{2})\\}"))
        {
            bytes.AddRange(Encoding.UTF8.GetBytes(input[at..match.Index]));
            bytes.Add(byte.Parse(match.Groups[1].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture));
            at = match.Index + match.Length;
        }
        bytes.AddRange(Encoding.UTF8.GetBytes(input[at..]));
        return bytes.ToArray();
    }

    private static string Expand(string line)
    {
        if (line == "{promptsLeftOutNote}") return ProblemReportStore.PromptsLeftOutNote;
        var note = Regex.Match(line, "^\\{unreadableCharactersNote:(\\d+)\\}$");
        return note.Success ? ProblemReportStore.UnreadableCharactersNote(int.Parse(note.Groups[1].Value, CultureInfo.InvariantCulture)) : line;
    }
}
