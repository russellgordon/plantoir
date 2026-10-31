using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #666: <c>shared-rules.json</c> → <c>machineLineLength</c>, the reader's
/// half. The shared Python keeps every machine line to <c>maxCharacters</c>
/// (<c>scripts/test_machine_line_length.py</c>, which this suite runs through
/// <c>PythonToolchainTests</c>); a shortened line carries <c>"count"</c> and
/// <c>"more"</c>, and each reader here must parse it as it parses a whole one
/// and say the TRUE count on the trail. The mac's readers owe the same.
/// </summary>
[Collection(SharedActivityState.Name)]
public class MachineLineLengthContractTests : IDisposable
{
    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["machineLineLength"]!;

    private readonly string _trailPath = Path.Combine(Path.GetTempPath(), $"plantoir-trail-length-{Guid.NewGuid():N}.txt");

    public MachineLineLengthContractTests() => ActivityTrail.SetCustomLogPathForTesting(_trailPath);

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trailPath); } catch { }
    }

    public static IEnumerable<object[]> ReaderExamples() =>
        Rule["readerExamples"]!.AsArray().Select(example => new object[] { example!.ToJsonString() });

    [Theory]
    [MemberData(nameof(ReaderExamples))]
    public void AShortenedLineIsReadWithItsTrueCount(string exampleJson)
    {
        var example = JsonNode.Parse(exampleJson)!;
        string line = example["line"]!.GetValue<string>();
        var expect = example["expect"]!;
        string course = expect["course"]!.GetValue<string>();
        int section = expect["section"]!.GetValue<int>();
        int shown = expect["shown"]!.GetValue<int>();
        string trailLine = expect["trailLine"]!.GetValue<string>();

        (string Course, int Section, int Shown, string Sentence) read =
            PagesDatedByTheBuild.Parse(line) is { } dated ? (dated.Course, dated.Section, dated.Pages.Count, dated.TrailSentence)
            : HowITeachKeptOffReport.Parse(line) is { } kept ? (kept.Course, kept.Section, kept.Pages.Count, kept.TrailSentence)
            : CoverageMapsBuilt.Parse(line) is { } maps ? (maps.Course, maps.Section, maps.Maps.Count, maps.TrailSentence)
            : throw new Xunit.Sdk.XunitException("no reader takes " + line);

        Assert.Equal(course, read.Course);
        Assert.Equal(section, read.Section);
        Assert.Equal(shown, read.Shown);
        Assert.Equal(trailLine, read.Sentence);
        Assert.Contains(expect["count"]!.GetValue<int>().ToString(), read.Sentence);

        // And through the one dispatch every reader uses (#660).
        Assert.True(BuildMachineLines.Record(line).WasMachineLine);
        Assert.Contains(trailLine, File.ReadAllText(_trailPath));
    }

    [Fact]
    public void EveryListTheRuleNamesHasAReaderExample()
    {
        var markers = Rule["readerExamples"]!.AsArray()
            .Select(example => example!["line"]!.GetValue<string>().Split(' ')[0]).ToHashSet();
        foreach (var (marker, _) in Rule["lists"]!.AsObject())
            Assert.Contains(marker, markers);
    }

    /// <summary>
    /// A character the Python counts once can be two UTF-16 units here or two
    /// cells in the console (machineLineLength.why), so twice the cap must fit
    /// the console reader's carry guard and the console's width.
    /// </summary>
    [Fact]
    public void TwiceTheCapFitsTheCarryAndTheConsole()
    {
        int cap = Rule["maxCharacters"]!.GetValue<int>();
        Assert.True(2 * cap <= ConPtyProcess.LauncherColumns, $"2 x {cap} > {ConPtyProcess.LauncherColumns} columns");
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Scripting", "ScriptRunner.cs"));
        var guard = System.Text.RegularExpressions.Regex.Match(source, @"_unscannedHealthOutput\.Length > (\d+)");
        Assert.True(guard.Success, "the carry guard has moved; pin its new shape here");
        Assert.True(2 * cap <= int.Parse(guard.Groups[1].Value), $"2 x {cap} > the carry guard's {guard.Groups[1].Value}");
    }

    [Fact]
    public void AWholeLineIsReadAsBefore()
    {
        var dated = PagesDatedByTheBuild.Parse(
            ContractLoader.LoadJson("shared-rules.json")["pagesDatedByTheBuild"]!["marker"]!["examples"]![0]!.GetValue<string>())!;
        Assert.Null(dated.Count);
        Assert.DoesNotContain("more", dated.TrailSentence);
    }
}
