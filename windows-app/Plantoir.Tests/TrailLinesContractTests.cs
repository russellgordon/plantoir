using System.Globalization;
using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// How a trail line is shaped, cleaned and redacted, and how a course's name
/// is cleaned where it is read, every case walked from
/// <c>contracts/shared-rules.json</c>: <c>activityTrail.lineShape.placeCases</c>
/// (#946, the mac's <c>ActivityTrailPlaceTests</c>) and
/// <c>courseNameCharacters</c> with its <c>trailLines</c> (#821, the mac's
/// <c>CourseNameCharactersTests</c>). Nothing here retypes a case.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class TrailLinesContractTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-tests", "trail-lines-" + Guid.NewGuid().ToString("N"));
    private readonly string _trail;

    public TrailLinesContractTests()
    {
        Directory.CreateDirectory(_folder);
        _trail = Path.Combine(_folder, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static JsonNode Rules() => ContractLoader.LoadJson("shared-rules.json");

    private static JsonNode CourseNameCharacters() => Rules()["courseNameCharacters"]!;

    /// <summary>The trail's lines: each entry ends in the platform's line end,
    /// and the prompt record carries one line feed of its own inside it.</summary>
    private string[] TrailLines()
    {
        if (!File.Exists(_trail)) return Array.Empty<string>();
        var lines = new List<string>();
        foreach (string piece in File.ReadAllText(_trail).Split('\n'))
        {
            string line = piece.EndsWith('\r') ? piece[..^1] : piece;
            if (line.Length > 0) lines.Add(line);
        }
        return lines.ToArray();
    }

    // ---- placeCases (#946 item 1) ---------------------------------------------

    /// <summary>
    /// The five <c>placeCases</c> against <see cref="ActivityTrail.Place"/>,
    /// and against a line <see cref="ActivityTrail.Note(ActivityTrail.Event, string, string, int, DateTime?)"/>
    /// and <see cref="ActivityTrail.NotePrompt"/> really write: the place sits
    /// between the stamp's <c>" · "</c> and the sentence, and never
    /// <c>{course}/0</c>.
    /// </summary>
    [Fact]
    public void EveryPlaceCaseIsThePlaceOfAWrittenLine()
    {
        var cases = Rules()["activityTrail"]!["lineShape"]!["placeCases"]!["cases"]!.AsArray();
        Assert.Equal(5, cases.Count);
        var moment = new DateTime(2026, 11, 21, 9, 0, 0);
        string stamp = DateText.Stamp(moment);
        foreach (var testCase in cases)
        {
            string name = testCase!["name"]!.ToString();
            string course = testCase["course"]!.ToString();
            int section = testCase["section"]!.GetValue<int>();
            string place = testCase["place"]!.ToString();
            Assert.True(place == ActivityTrail.Place(course, section), name);

            File.Delete(_trail);
            ActivityTrail.Note(ActivityTrail.Event.TaskStarted, "started preview.ps1", course, section, moment);
            ActivityTrail.NotePrompt("publish tomorrow", course, section, moment);
            string[] lines = TrailLines();
            Assert.Equal(3, lines.Length);
            Assert.True($"{stamp} · {place}started preview.ps1" == lines[0], name + ": " + lines[0]);
            Assert.True($"{stamp} · {place}asked a question" == lines[1], name + ": " + lines[1]);
            Assert.True(ActivityTrail.PromptPrefix + "publish tomorrow" == lines[2], name + ": " + lines[2]);
        }
    }

    // ---- courseNameCharacters (#821 item 1) -----------------------------------

    /// <summary>
    /// The 41 <c>cases</c>, compared code unit by code unit, and the rule
    /// applied twice gives what it gave once (<c>idempotent</c>).
    /// </summary>
    [Fact]
    public void EveryCourseNameCaseIsCleanedAsTheContractSays()
    {
        var cases = CourseNameCharacters()["cases"]!.AsArray();
        Assert.Equal(41, cases.Count);
        Assert.True(CourseNameCharacters()["idempotent"]!.GetValue<bool>());
        foreach (var testCase in cases)
        {
            string name = testCase!["name"]!.ToString();
            string raw = testCase["raw"]!.ToString();
            string expect = testCase["expect"]!.ToString();
            string cleaned = OneLineText.CourseName(raw);
            Assert.True(expect.ToCharArray().SequenceEqual(cleaned.ToCharArray()), $"{name}: {Units(cleaned)} is not {Units(expect)}");
            Assert.True(cleaned == OneLineText.CourseName(cleaned), name + ": not idempotent");
        }
    }

    /// <summary>
    /// <c>spacedOut</c> and <c>removed</c> pinned against
    /// <see cref="OneLineText.IsSpacedOut"/> and <see cref="OneLineText.IsRemoved"/>
    /// over every code unit U+0000 to U+FFFF, and each unit on its own cleaned
    /// to one space, nothing, or itself.
    /// </summary>
    [Fact]
    public void TheSpacedOutAndRemovedSetsAreTheContracts()
    {
        var spacedOut = Ranges(CourseNameCharacters()["spacedOut"]!);
        var removed = Ranges(CourseNameCharacters()["removed"]!);
        for (int value = 0; value <= 0xFFFF; value++)
        {
            char unit = (char)value;
            bool spaced = InAny(spacedOut, value);
            bool gone = InAny(removed, value);
            Assert.True(spaced == OneLineText.IsSpacedOut(unit), $"U+{value:X4} spaced out");
            Assert.True(gone == OneLineText.IsRemoved(unit), $"U+{value:X4} removed");
            string expected = spaced ? " " : gone ? "" : unit.ToString();
            Assert.True(expected == OneLineText.Cleaned(unit.ToString()), $"U+{value:X4} cleaned");
        }
    }

    /// <summary>
    /// <c>CourseConfiguration.CourseName</c> reads and sets the name cleaned,
    /// and a Save writes it cleaned though nothing edited it (the per-key merge
    /// would otherwise keep the file's raw name): every <c>cases</c> entry.
    /// </summary>
    [Fact]
    public void ACourseNameIsCleanedWhereItIsReadSetAndSaved()
    {
        string path = Path.Combine(_folder, "course_config.json");
        foreach (var testCase in CourseNameCharacters()["cases"]!.AsArray())
        {
            string name = testCase!["name"]!.ToString();
            string raw = testCase["raw"]!.ToString();
            string expect = testCase["expect"]!.ToString();
            var onDisk = new JObject { ["course_code"] = "ICS3U", ["course_name"] = raw, ["course_term"] = "Fall" };
            File.WriteAllText(path, onDisk.ToString());

            var config = CourseConfiguration.Load(path);
            Assert.True(expect == config.CourseName, name + ": read");

            config.Write(path);
            Assert.True(expect == (string?)JObject.Parse(File.ReadAllText(path))["course_name"], name + ": saved unedited");

            var set = CourseConfiguration.Load(path);
            set.CourseName = raw;
            Assert.True(expect == set.CourseName, name + ": set");
        }
    }

    /// <summary>
    /// A unit plan's name is put on one line with the course-name rule first,
    /// as the mac's is (<see cref="UnitPlans.OneLine"/>): every <c>cases</c>
    /// entry gives its <c>expect</c> with white space runs made one space and
    /// the ends trimmed.
    /// </summary>
    [Fact]
    public void AUnitPlansNameIsCleanedByTheSameRuleFirst()
    {
        foreach (var testCase in CourseNameCharacters()["cases"]!.AsArray())
        {
            string expect = UnitPlans.OneLine(testCase!["expect"]!.ToString());
            Assert.True(expect == UnitPlans.OneLine(testCase["raw"]!.ToString()), testCase["name"]!.ToString());
        }
    }

    // ---- trailLines (#821 items 2 and 4) --------------------------------------

    /// <summary>
    /// The 14 <c>trailLines.cases</c> through <see cref="ActivityTrail.SafeTrailLine"/>,
    /// the one clean-and-redact function every writer in ActivityTrail.cs
    /// uses, both leak shapes included; <c>written</c> is the result split at
    /// its line breaks. <c>knownLimits</c> is named in that function's
    /// comment and is not tested as passing.
    /// </summary>
    [Fact]
    public void EveryTrailLineCaseIsWrittenAsTheContractSays()
    {
        var cases = CourseNameCharacters()["trailLines"]!["cases"]!.AsArray();
        Assert.Equal(14, cases.Count);
        foreach (var testCase in cases)
        {
            string name = testCase!["name"]!.ToString();
            string line = testCase["line"]!.ToString();
            bool keeps = testCase["keepsLineBreaks"]!.GetValue<bool>();
            var written = testCase["written"]!.AsArray().Select(x => x!.ToString()).ToArray();
            string safe = ActivityTrail.SafeTrailLine(line, keeps);
            Assert.True(written.SequenceEqual(safe.Split('\n')), $"{name}: {Units(safe)}");
        }
    }

    /// <summary>
    /// The trail-line cases that keep no line breaks, written for real by
    /// <see cref="ActivityTrail.Note(ActivityTrail.Event, string, DateTime?)"/>:
    /// the file holds exactly the case's line after the stamp.
    /// </summary>
    [Fact]
    public void AWrittenLineIsCleanedAndRedacted()
    {
        var moment = new DateTime(2026, 11, 21, 9, 0, 0);
        string stamp = DateText.Stamp(moment);
        foreach (var testCase in CourseNameCharacters()["trailLines"]!["cases"]!.AsArray())
        {
            if (testCase!["keepsLineBreaks"]!.GetValue<bool>()) continue;
            File.Delete(_trail);
            ActivityTrail.Note(ActivityTrail.Event.TaskStarted, testCase["line"]!.ToString(), moment);
            string[] lines = TrailLines();
            string expected = stamp + " · " + testCase["written"]!.AsArray()[0]!.ToString();
            Assert.True(lines.Length == 1 && lines[0] == expected, testCase["name"]!.ToString() + ": " + string.Join(" | ", lines));
        }
    }

    /// <summary>
    /// The two <c>promptCases</c>: the teacher's sentence is put on ONE line
    /// before it goes behind the prefix; the record's own line break between
    /// its two lines stays.
    /// </summary>
    [Fact]
    public void APromptIsOneLineBehindItsPrefix()
    {
        var cases = CourseNameCharacters()["trailLines"]!["promptCases"]!.AsArray();
        Assert.Equal(2, cases.Count);
        var moment = new DateTime(2026, 11, 21, 9, 0, 0);
        foreach (var testCase in cases)
        {
            string name = testCase!["name"]!.ToString();
            File.Delete(_trail);
            ActivityTrail.NotePrompt(testCase["prompt"]!.ToString(), "ICS3U", 1, moment);
            string[] lines = TrailLines();
            Assert.True(lines.Length == 2, name + ": " + string.Join(" | ", lines));
            Assert.True($"{DateText.Stamp(moment)} · ICS3U/1 · asked a question" == lines[0], name + ": " + lines[0]);
            Assert.True(testCase["askedLine"]!.ToString() == lines[1], name + ": " + Units(lines[1]));
        }
    }

    /// <summary>
    /// The teacher's sentence goes through <c>trailLines.order</c> on its RAW
    /// text, like every other line (lane E review 1, M1): each
    /// <c>trailLines.cases</c> line that keeps no line breaks, asked as a
    /// prompt, is written behind the prefix exactly as the case says. Cleaning
    /// the sentence first wrote the tail of a token with a NUL, ESC or DEL
    /// inside it; redacting only once let an isolate inside a label hide it.
    /// </summary>
    [Fact]
    public void APromptIsRedactedOnItsRawTextAsEveryLineIs()
    {
        var moment = new DateTime(2026, 11, 21, 9, 0, 0);
        int asked = 0;
        foreach (var testCase in CourseNameCharacters()["trailLines"]!["cases"]!.AsArray())
        {
            if (testCase!["keepsLineBreaks"]!.GetValue<bool>()) continue;
            string name = testCase["name"]!.ToString();
            File.Delete(_trail);
            ActivityTrail.NotePrompt(testCase["line"]!.ToString(), "ICS3U", 1, moment);
            string[] lines = TrailLines();
            string expected = ActivityTrail.PromptPrefix + testCase["written"]!.AsArray()[0]!.ToString().Trim();
            Assert.True(lines.Length == 2 && lines[1] == expected, name + ": " + string.Join(" | ", lines));
            asked++;
        }
        Assert.Equal(13, asked);
    }

    /// <summary>
    /// A secret split three ways inside a sentence: by a NUL (taken whole), by
    /// an isolate inside its label (found by the second pass), and by a line
    /// break, which is white space to the redactor (<c>knownLimits</c>: its
    /// tail is not pinned here, only that the record stays two lines and the
    /// token's head is removed).
    /// </summary>
    [Fact]
    public void ASecretSplitInsideAPromptDoesNotGetPast()
    {
        var moment = new DateTime(2026, 11, 21, 9, 0, 0);

        File.Delete(_trail);
        ActivityTrail.NotePrompt("use Bearer abc123\u0000SECRETTAIL please", "ICS3U", 1, moment);
        string[] nul = TrailLines();
        Assert.True(nul.Length == 2 && nul[1] == "  asked: use Bearer [removed: token] please", "NUL: " + Units(string.Join(" | ", nul)));

        File.Delete(_trail);
        ActivityTrail.NotePrompt("set CLOUDFLARE_API_⁦TOKEN=abc123XYZ_secret please", "ICS3U", 1, moment);
        string[] bidi = TrailLines();
        Assert.True(bidi.Length == 2 && bidi[1] == "  asked: set CLOUDFLARE_API_TOKEN=[removed: token] please", "bidi: " + Units(string.Join(" | ", bidi)));

        File.Delete(_trail);
        ActivityTrail.NotePrompt("use Bearer abc123\nSECRETTAIL please", "ICS3U", 1, moment);
        string[] newline = TrailLines();
        Assert.True(newline.Length == 2 && newline[1].StartsWith("  asked: use Bearer [removed: token]", StringComparison.Ordinal)
                    && !newline[1].Contains("abc123", StringComparison.Ordinal), "newline: " + Units(string.Join(" | ", newline)));
    }

    // ---- Helpers -------------------------------------------------------------

    private static List<(int First, int Last)> Ranges(JsonNode node)
    {
        var ranges = new List<(int, int)>();
        foreach (var pair in node.AsArray())
            ranges.Add((int.Parse(pair![0]!.ToString(), NumberStyles.HexNumber, CultureInfo.InvariantCulture),
                        int.Parse(pair[1]!.ToString(), NumberStyles.HexNumber, CultureInfo.InvariantCulture)));
        Assert.NotEmpty(ranges);
        return ranges;
    }

    private static bool InAny(List<(int First, int Last)> ranges, int value) =>
        ranges.Any(range => value >= range.First && value <= range.Last);

    private static string Units(string text) =>
        string.Join(" ", text.Select(unit => unit < 0x20 || unit > 0x7E ? $"U+{(int)unit:X4}" : unit.ToString()));
}
