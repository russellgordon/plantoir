using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;

namespace Plantoir.Tests;

/// <summary>
/// #660, the behaviour: what a run <c>plantoir-mcp</c> starts does with its
/// output. Every trail marker's contract example and one line of narration
/// go in; exactly the trail lines, one progress report and no machine line
/// in the progress text or the kept tail come out. Before #660 five of these
/// examples wrote nothing (MAPS, MY_PROGRESS, SWIFT, DATED, KEPT_OFF).
/// </summary>
[Collection(SharedActivityState.Name)]
public class LauncherRunnerCaptureTests : IDisposable
{
    private readonly string _trailPath = Path.Combine(Path.GetTempPath(), $"plantoir-trail-capture-{Guid.NewGuid():N}.txt");

    public LauncherRunnerCaptureTests() => ActivityTrail.SetCustomLogPathForTesting(_trailPath);

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trailPath); } catch { }
    }

    private sealed class Collect : IProgress<string>
    {
        public readonly List<string> Reports = new();
        public void Report(string value) { lock (Reports) Reports.Add(value); }
    }

    [Fact]
    public void EveryMarkerReachesTheTrailAndOnlyNarrationIsReported()
    {
        var examples = BuildMachineLinesTests.TrailExamples().Select(row => (string)row[1]).ToList();
        var shared = ContractLoader.LoadJson("shared-rules.json");
        string health = shared["siteHealth"]!["marker"]!["examples"]![0]!.GetValue<string>();
        string checklist = shared["linksChecklist"]!["marker"]!["example"]!.GetValue<string>();
        var progress = new Collect();
        var capture = new LauncherRunner.OutputCapture(progress);

        foreach (string line in examples) capture.Take(line);
        capture.Take(health);
        capture.Take(health);   // the same problem twice in one run is one problem
        capture.Take(checklist);
        capture.Take("PLANTOIR_SOMETHING_NEW: {}");
        capture.Take("🔨 Building ICS3U section 1…");

        string[] trail = File.ReadAllLines(_trailPath).Where(line => line.Length > 0).ToArray();
        Assert.Equal(examples.Count + 1, trail.Length);   // each example, and the finding once
        Assert.Equal(new[] { "🔨 Building ICS3U section 1…" }, progress.Reports);
        var (transcript, findings, links) = capture.Snapshot();
        Assert.Single(findings);
        Assert.NotNull(links);
        Assert.DoesNotContain("PLANTOIR_", transcript);
        Assert.Contains("Building ICS3U", transcript);
    }
}
