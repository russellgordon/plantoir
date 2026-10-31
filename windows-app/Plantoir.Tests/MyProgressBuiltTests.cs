using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #599 (mac #545): the build's PLANTOIR_MY_PROGRESS: line read into one
/// trail sentence from the contract's own examples and shapes, read from BOTH
/// places it can arrive; and the two <c>course_config.json</c> keys read as
/// <c>myProgress.config.cases</c> say.
/// </summary>
public class MyProgressBuiltTests
{
    private static System.Text.Json.Nodes.JsonNode Rule =>
        ContractLoader.LoadJson("shared-rules.json")["myProgressBuilt"]!;

    [Fact]
    public void TheContractsExamplesAreReadInTheContractsShapes()
    {
        Assert.Equal(Rule["marker"]!["prefix"]!.ToString(), MyProgressBuilt.Marker);
        var shapes = Rule["trailLine"]!["shapes"]!;
        Assert.Equal("my progress page built", Rule["trailLine"]!["event"]!.ToString());
        var examples = Rule["marker"]!["examples"]!.AsArray().Select(e => e!.ToString()).ToList();
        Assert.Equal(3, examples.Count);

        var built = MyProgressBuilt.Parse(examples[0])!;
        Assert.Equal(("ICS3U", 1, true, 12, "built"), (built.Course, built.Section, built.Built, built.Pages, built.Reason));
        Assert.Equal(shapes["built"]!.ToString().Replace("N page(s)", "12 pages"), built.TrailSentence);

        var none = MyProgressBuilt.Parse(examples[1])!;
        Assert.Equal(2, none.Section);
        Assert.Equal(shapes["noSuccessCriteria"]!.ToString(), none.TrailSentence);

        var own = MyProgressBuilt.Parse(examples[2])!;
        Assert.Equal(shapes["teachersOwnPage"]!.ToString(), own.TrailSentence);

        Assert.Equal(shapes["built"]!.ToString().Replace("N page(s)", "1 page"),
                     new MyProgressBuilt("ICS3U", 1, true, 1, "built").TrailSentence);
    }

    [Fact]
    public void ALineThatIsNotTheMarkerIsNotRead()
    {
        Assert.Null(MyProgressBuilt.Parse("My Progress: 12 pages with success criteria to tick"));
        Assert.Null(MyProgressBuilt.Parse("PLANTOIR_MY_PROGRESS: not json"));
        Assert.Null(MyProgressBuilt.Parse("PLANTOIR_MY_PROGRESS: {\"course\": \"ICS3U\", \"section\": 1}"));
        // A marker glued to the tail of somebody else's half line is still read.
        Assert.NotNull(MyProgressBuilt.Parse("…building PLANTOIR_MY_PROGRESS: {\"course\": \"ICS3U\", \"section\": 1, \"built\": true, \"pages\": 2, \"reason\": \"built\"}"));
    }

    /// <summary>Read from a run the app starts AND from a scheduled publish's record — and the scheduled wrapper's scan keeps the line.</summary>
    [Fact]
    public void BothReadersAndTheWrappersScanKnowTheMarker()
    {
        string core = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core");
        // #660: all three readers go through BuildMachineLines, which knows
        // this marker, and the wrapper's scan is generated from its list.
        Assert.Contains(MyProgressBuilt.Marker, Plantoir.Core.Scripting.BuildMachineLines.TrailMarkers);
        Assert.Contains(MyProgressBuilt.Marker, Plantoir.Core.Scripting.BuildMachineLines.ScheduledRecordMarkers);
        Assert.Contains("BuildMachineLines.Record(", File.ReadAllText(Path.Combine(core, "Scripting", "ScriptRunner.cs")));
        Assert.Contains("BuildMachineLines.Record(", File.ReadAllText(Path.Combine(core, "Assist", "ScheduledHealthFindings.cs")));
        Assert.Contains("BuildMachineLines.ScheduledRecordMarkers", File.ReadAllText(Path.Combine(core, "Assist", "TaskScheduling.cs")));
    }

    public static IEnumerable<object[]> ConfigCases() =>
        ContractLoader.LoadJson("shared-rules.json")["myProgress"]!["config"]!["cases"]!.AsArray()
            .Select(c => new object[] { c!["name"]!.ToString() });

    [Theory]
    [MemberData(nameof(ConfigCases))]
    public void EveryConfigCaseIsReadAsTheContractSays(string name)
    {
        var c = ContractLoader.LoadJson("shared-rules.json")["myProgress"]!["config"]!["cases"]!.AsArray()
            .First(x => x!["name"]!.ToString() == name)!;
        var config = CourseConfiguration.FromDictionary(JObject.Parse(c["config"]!.ToJsonString()));
        int section = c["section"]!.GetValue<int>();
        Assert.Equal(c["wanted"]!.GetValue<bool>(), config.IncludesMyProgress(section));
        Assert.Equal(c["headings"]!.AsArray().Select(h => h!.ToString()), config.SuccessCriteriaHeadings);
    }

    [Fact]
    public void TheDefaultHeadingsAreTheContracts() =>
        Assert.Equal(ContractLoader.LoadJson("shared-rules.json")["myProgress"]!["headings"]!["defaults"]!.AsArray()
                         .Select(h => h!.ToString()),
                     CourseConfiguration.DefaultSuccessCriteriaHeadings);
}
