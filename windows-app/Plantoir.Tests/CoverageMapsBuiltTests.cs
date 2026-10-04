using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>coverageMapsBuilt</c> (#345): the build's
/// PLANTOIR_MAPS: line read into one trail sentence, from the contract's own
/// examples, and read from BOTH places it can arrive.
/// </summary>
public class CoverageMapsBuiltTests
{
    private static System.Text.Json.Nodes.JsonNode Rule =>
        ContractLoader.LoadJson("shared-rules.json")["coverageMapsBuilt"]!;

    [Fact]
    public void TheContractsExamplesAreRead()
    {
        Assert.Equal(Rule["marker"]!["prefix"]!.ToString(), CoverageMapsBuilt.Marker);
        var examples = Rule["marker"]!["examples"]!.AsArray().Select(e => e!.ToString()).ToList();
        Assert.True(examples.Count >= 2);

        var two = CoverageMapsBuilt.Parse(examples[0])!;
        Assert.Equal("ICS3U", two.Course);
        Assert.Equal(1, two.Section);
        Assert.Equal(
            "the build made 2 curriculum maps: Curriculum Coverage from Ontario Curriculum (42 expectations), " +
            "College Board Curriculum Coverage from College Board Curriculum (18 expectations)",
            two.TrailSentence);

        var none = CoverageMapsBuilt.Parse(examples[1])!;
        Assert.Equal(2, none.Section);
        Assert.Equal("the build made no curriculum map: no curriculum folder holds an expectation page", none.TrailSentence);
    }

    [Fact]
    public void ALineThatIsNotTheMarkerIsNotRead()
    {
        Assert.Null(CoverageMapsBuilt.Parse("🗺️  Curriculum Coverage (Ontario Curriculum): 42 expectations"));
        Assert.Null(CoverageMapsBuilt.Parse("PLANTOIR_MAPS: not json"));
    }

    /// <summary>
    /// Read from a run the app starts AND from a scheduled publish's record —
    /// and the scheduled wrapper's scan keeps the line, or the second reader
    /// never sees it.
    /// </summary>
    [Fact]
    public void BothReadersAndTheWrappersScanKnowTheMarker()
    {
        string core = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core");
        Assert.Contains("CoverageMapsBuilt.Parse(line)", File.ReadAllText(Path.Combine(core, "Scripting", "ScriptRunner.cs")));
        Assert.Contains("CoverageMapsBuilt.ReportsIn(lines)", File.ReadAllText(Path.Combine(core, "Assist", "ScheduledHealthFindings.cs")));
        Assert.Contains("'PLANTOIR_MAPS:'", File.ReadAllText(Path.Combine(core, "Assist", "TaskScheduling.cs")));
    }
}
