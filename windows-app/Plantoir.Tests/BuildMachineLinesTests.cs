using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #660: the ONE dispatch every reader of a build's output goes through
/// (<see cref="BuildMachineLines"/>) - the app's console, a run
/// <c>plantoir-mcp</c> starts, and a scheduled publish's record. Every
/// marker's own contract example (deserialised, never retyped) goes through
/// it and leaves exactly its trail line; and the three readers are pinned to
/// call it, so a marker cannot be known to one of them and not another.
/// </summary>
[Collection(SharedActivityState.Name)]
public class BuildMachineLinesTests : IDisposable
{
    private readonly string _trailPath = Path.Combine(Path.GetTempPath(), $"plantoir-trail-machine-{Guid.NewGuid():N}.txt");

    public BuildMachineLinesTests() => ActivityTrail.SetCustomLogPathForTesting(_trailPath);

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trailPath); } catch { }
    }

    private string[] TrailLines() =>
        File.Exists(_trailPath) ? File.ReadAllLines(_trailPath).Where(line => line.Length > 0).ToArray() : Array.Empty<string>();

    private static JsonNode Shared => ContractLoader.LoadJson("shared-rules.json");

    private static IEnumerable<string> Examples(JsonNode marker) =>
        marker["examples"]!.AsArray().Select(example => example!.GetValue<string>());

    /// <summary>The trail-only markers, each with the sentence its own reader words.</summary>
    public static IEnumerable<object[]> TrailExamples()
    {
        var shared = Shared;
        foreach (string line in Examples(shared["coverageMapsBuilt"]!["marker"]!))
            yield return new object[] { "MAPS", line, CoverageMapsBuilt.Parse(line)!.TrailSentence };
        foreach (string line in Examples(shared["myProgressBuilt"]!["marker"]!))
            yield return new object[] { "MY_PROGRESS", line, MyProgressBuilt.Parse(line)!.TrailSentence };
        foreach (string line in Examples(shared["pagesDatedByTheBuild"]!["marker"]!))
            yield return new object[] { "DATED", line, PagesDatedByTheBuild.Parse(line)!.TrailSentence };
        foreach (string line in Examples(shared["howITeachPage"]!["keptOffMarker"]!))
            yield return new object[] { "KEPT_OFF", line, HowITeachKeptOffReport.Parse(line)!.TrailSentence };
        foreach (string line in Examples(shared["buildRepairs"]!["marker"]!))
            yield return new object[] { "REPAIRED", line, BuildRepairReport.Parse(line)!.TrailSentence! };
        foreach (string line in Examples(shared["codeRunnerBlocks"]!["swift"]!["windows"]!["marker"]!))
            yield return new object[] { "SWIFT", line, "" };
        foreach (var entry in shared["activityTrail"]!["mustRecord"]!.AsArray())
        {
            if (entry!["marker"] is not JsonObject marker || marker["examples"] is not JsonArray examples) continue;
            foreach (var example in examples)
            {
                string line = example!.GetValue<string>();
                if (CloudflareProjectRemade.Parse(line) is { } remade)
                    yield return new object[] { "CLOUDFLARE_REMADE", line, remade.TrailSentence };
            }
        }
    }

    [Theory]
    [MemberData(nameof(TrailExamples))]
    public void EachMarkersExampleLeavesExactlyItsTrailLine(string kind, string line, string sentence)
    {
        var read = BuildMachineLines.Record(line);

        Assert.True(read.WasMachineLine, kind);
        Assert.Null(read.Finding);
        Assert.Null(read.Checklist);
        string[] trail = TrailLines();
        Assert.Single(trail);
        if (sentence.Length > 0) Assert.Contains(sentence, trail[0]);
        Assert.DoesNotContain("PLANTOIR_", trail[0]);
    }

    [Fact]
    public void EveryTrailMarkerHasAnExampleHere()
    {
        var kinds = TrailExamples().Select(row => "PLANTOIR_" + (string)row[0] + ":").ToHashSet();
        Assert.Equal(BuildMachineLines.TrailMarkers.OrderBy(m => m), kinds.OrderBy(m => m));
    }

    [Fact]
    public void AFindingAndTheChecklistAreHandedBackForTheCallerToKeep()
    {
        string health = Examples(Shared["siteHealth"]!["marker"]!).First();
        var read = BuildMachineLines.Record(health);
        Assert.NotNull(read.Finding);
        Assert.Empty(TrailLines());   // noted by AddFinding, once

        var seen = new HashSet<string>(StringComparer.Ordinal);
        Assert.True(BuildMachineLines.AddFinding(read.Finding!, seen));
        Assert.False(BuildMachineLines.AddFinding(BuildMachineLines.Record(health).Finding!, seen));
        Assert.Single(TrailLines());

        string checklist = Shared["linksChecklist"]!["marker"]!["example"]!.GetValue<string>();
        var offered = BuildMachineLines.Record(checklist);
        Assert.NotNull(offered.Checklist);
        Assert.True(offered.WasMachineLine);
        Assert.Single(TrailLines());
    }

    [Fact]
    public void AMarkerNobodyReadsIsStillMachineryAndWritesNothing()
    {
        var read = BuildMachineLines.Record("PLANTOIR_SOMETHING_NEW: {\"course\": \"ICS3U\"}");
        Assert.True(read.WasMachineLine);
        Assert.Null(read.Finding);
        Assert.Empty(TrailLines());

        var narration = BuildMachineLines.Record("🔨 Building ICS3U section 1…");
        Assert.False(narration.WasMachineLine);
        Assert.Empty(TrailLines());
    }

    [Fact]
    public void TheMomentIsPassedThroughForAScheduledRecord()
    {
        string line = Examples(Shared["pagesDatedByTheBuild"]!["marker"]!).First();
        BuildMachineLines.Record(line, new DateTime(2026, 3, 4, 5, 6, 7));
        Assert.StartsWith("2026-03-04 05:06:07", TrailLines().Single());
    }

    [Fact]
    public void TheCarryGuardKeepsAnyMarker()
    {
        Assert.True(BuildMachineLines.MayHoldOne(new string('x', 9000) + " PLANTOIR_SOMETHING_NEW: {"));
        Assert.False(BuildMachineLines.MayHoldOne(new string('x', 9000)));
    }

    [Fact]
    public void TheScheduledWrapperKeepsTheFindingsFirstAndEveryTrailMarkerButTheCloudflareOne()
    {
        var kept = BuildMachineLines.ScheduledRecordMarkers;
        Assert.Equal(SiteHealthFinding.Marker, kept[0]);
        foreach (string marker in BuildMachineLines.TrailMarkers)
        {
            if (marker == CloudflareProjectRemade.Marker) Assert.DoesNotContain(marker, kept);
            else Assert.Contains(marker, kept);
        }
        Assert.DoesNotContain(LinksChecklistMarker.Prefix, kept);
    }

    /// <summary>
    /// The three readers call the one dispatch, and none reads a trail
    /// marker by hand any more (#660). In <c>LauncherRunner</c> the dispatch
    /// comes before the machine-line drop, which comes before progress is
    /// reported (the behaviour itself: <c>LauncherRunnerCaptureTests</c>).
    /// </summary>
    [Fact]
    public void TheThreeReadersGoThroughTheOneDispatch()
    {
        string root = Path.Combine(ContractLoader.RepositoryRoot, "windows-app");
        string console = File.ReadAllText(Path.Combine(root, "Plantoir.Core", "Scripting", "ScriptRunner.cs"));
        string mcp = File.ReadAllText(Path.Combine(root, "Plantoir.Mcp", "LauncherRunner.cs"));
        string scheduled = File.ReadAllText(Path.Combine(root, "Plantoir.Core", "Assist", "ScheduledHealthFindings.cs"));
        string wrapper = File.ReadAllText(Path.Combine(root, "Plantoir.Core", "Assist", "TaskScheduling.cs"));
        foreach (var (name, source) in new[] { ("ScriptRunner", console), ("LauncherRunner", mcp), ("ScheduledHealthFindings", scheduled) })
        {
            Assert.True(source.Contains("BuildMachineLines.Record(", StringComparison.Ordinal), $"{name} does not read through BuildMachineLines.Record");
            foreach (string reader in new[] { "CoverageMapsBuilt", "MyProgressBuilt", "SwiftGotReady", "PagesDatedByTheBuild",
                                              "HowITeachKeptOffReport", "BuildRepairReport", "CloudflareProjectRemade", "SiteHealthFinding", "LinksChecklistMarker" })
            {
                Assert.False(source.Contains(reader + ".Parse(line)", StringComparison.Ordinal), $"{name} reads {reader} by hand");
                Assert.False(source.Contains(reader + ".ReportsIn(", StringComparison.Ordinal), $"{name} reads {reader} by hand");
            }
        }
        Assert.Contains("BuildMachineLines.ScheduledRecordMarkers", wrapper);

        int reads = mcp.IndexOf("BuildMachineLines.Record(line)", StringComparison.Ordinal);
        int drops = mcp.IndexOf("TranscriptBuilder.IsMachineLine(line)) return;", StringComparison.Ordinal);
        int reports = mcp.IndexOf("progress?.Report(line.Trim());", StringComparison.Ordinal);
        Assert.True(reads >= 0 && reads < drops, "the line must be read before machine lines are dropped");
        Assert.True(drops < reports, "machine lines must be dropped before progress is reported");
    }
}
