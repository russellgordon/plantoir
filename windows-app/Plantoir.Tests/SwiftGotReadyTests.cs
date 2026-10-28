using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #570: swift_windows_fetch.py's PLANTOIR_SWIFT: line read into the two
/// trail events the contract names (activityTrail.mustRecord → "Swift got
/// ready on this computer", "Swift could not be got ready"), from the
/// contract's own examples and words, by BOTH readers.
/// </summary>
public class SwiftGotReadyTests
{
    private static System.Text.Json.Nodes.JsonNode Marker =>
        ContractLoader.LoadJson("shared-rules.json")["codeRunnerBlocks"]!["swift"]!["windows"]!["marker"]!;

    private static System.Text.Json.Nodes.JsonNode EventNamed(string name) =>
        ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .First(e => e!["event"]!.ToString() == name)!;

    [Fact]
    public void TheContractsExamplesAreReadIntoTheContractsLines()
    {
        Assert.Equal(Marker["prefix"]!.ToString(), SwiftGotReady.Marker);
        var examples = Marker["examples"]!.AsArray().Select(e => e!.ToString()).ToList();

        var ready = SwiftGotReady.Parse(examples[0])!;
        Assert.True(ready.Ready);
        Assert.Equal(("ICS3U", 1, 92), (ready.Course, ready.Section, ready.Seconds));
        Assert.Equal(ActivityTrail.Event.SwiftGotReady, ready.Event);
        Assert.Equal("Swift got ready on this computer", ActivityTrail.KeyFor(ready.Event));
        string readyLine = EventNamed("Swift got ready on this computer")["line"]!.ToString();
        Assert.Equal(readyLine.Replace("{course}/{section} · ", "").Replace("{seconds}", "92").Replace("{gigabytes}", "2.3"),
                     ready.TrailSentence);

        var failed = SwiftGotReady.Parse(examples[1])!;
        Assert.False(failed.Ready);
        Assert.Equal(ActivityTrail.Event.SwiftCouldNotBeGotReady, failed.Event);
        Assert.Equal("Swift could not be got ready", ActivityTrail.KeyFor(failed.Event));
        var failedEvent = EventNamed("Swift could not be got ready");
        string template = failedEvent["line"]!.ToString().Replace("{course}/{section} · ", "");
        foreach (var (reason, words) in failedEvent["whyWords"]!.AsObject())
        {
            Assert.Equal(words!.ToString(), SwiftGotReady.WhyWords[reason]);
            Assert.Equal(template.Replace("{why}", words.ToString()),
                         new SwiftGotReady(false, 0, 0, reason, "ICS3U", 1).TrailSentence);
        }
        Assert.Equal(failedEvent["whyWords"]!.AsObject().Count, SwiftGotReady.WhyWords.Count);
    }

    [Fact]
    public void ALineThatIsNotTheMarkerIsNotRead()
    {
        Assert.Null(SwiftGotReady.Parse("✅ Swift is ready."));
        Assert.Null(SwiftGotReady.Parse("PLANTOIR_SWIFT: not json"));
        Assert.Null(SwiftGotReady.Parse("PLANTOIR_SWIFT: {\"ready\": false}"));
        var bare = SwiftGotReady.Parse("PLANTOIR_SWIFT: {\"ready\": false, \"reason\": \"offline\"}")!;
        Assert.Null(bare.Course);
    }

    [Fact]
    public void BothReadersAndTheWrappersScanKnowTheMarker()
    {
        string core = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core");
        // #660: all three readers go through BuildMachineLines, which knows
        // this marker, and the wrapper's scan is generated from its list.
        Assert.Contains(SwiftGotReady.Marker, Plantoir.Core.Scripting.BuildMachineLines.TrailMarkers);
        Assert.Contains(SwiftGotReady.Marker, Plantoir.Core.Scripting.BuildMachineLines.ScheduledRecordMarkers);
        Assert.Contains("BuildMachineLines.Record(", File.ReadAllText(Path.Combine(core, "Scripting", "ScriptRunner.cs")));
        Assert.Contains("BuildMachineLines.Record(", File.ReadAllText(Path.Combine(core, "Assist", "ScheduledHealthFindings.cs")));
        Assert.Contains("BuildMachineLines.ScheduledRecordMarkers", File.ReadAllText(Path.Combine(core, "Assist", "TaskScheduling.cs")));
    }
}
