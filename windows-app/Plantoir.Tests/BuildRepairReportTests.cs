using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #645 (mac #584): the build's PLANTOIR_REPAIRED: line — a section front
/// page's title it put quotes around in the teacher's own page — read from
/// the contract's own marker and trail line (<c>shared-rules.json</c> →
/// <c>buildRepairs</c>) and written on the trail as
/// <c>folder problem repaired</c>, from a run the app starts. The scheduled
/// record and the wrapper's real scan are pinned in
/// <c>ScheduledHealthFindingsTests.TheWrappersScanKeepsTheDatedLineAndItReachesTheTrail</c>.
/// The mac's tests are <c>BuildRepairReportTests</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public class BuildRepairReportTests : IDisposable
{
    private static System.Text.Json.Nodes.JsonNode Rule =>
        ContractLoader.LoadJson("shared-rules.json")["buildRepairs"]!;

    private readonly string _trailPath = Path.Combine(Path.GetTempPath(), $"plantoir-trail-repair-{Guid.NewGuid():N}.txt");

    public BuildRepairReportTests() => ActivityTrail.SetCustomLogPathForTesting(_trailPath);

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trailPath); } catch { }
    }

    private string Trail() => File.Exists(_trailPath) ? File.ReadAllText(_trailPath) : "";

    private static string Example => Rule["marker"]!["examples"]![0]!.ToString();

    private static string TrailLineFor(string page) =>
        Rule[BuildRepairReport.FrontPageTitleQuoted]!["trailLine"]!.ToString().Replace("{page}", page);

    [Fact]
    public void TheContractsExampleIsReadAndWordedAsTheContractSays()
    {
        Assert.Equal(Rule["marker"]!["prefix"]!.ToString(), BuildRepairReport.Marker);
        Assert.NotNull(Rule[BuildRepairReport.FrontPageTitleQuoted]);

        var report = BuildRepairReport.Parse(Example)!;
        Assert.Equal(("SPH4U", 1, "frontPageTitleQuoted", "section1/index"),
                     (report.Course, report.Section, report.Repair, report.Page));
        Assert.Equal(TrailLineFor("section1/index"), report.TrailSentence);
    }

    [Fact]
    public void AMarkerGluedAfterOtherTextIsReadFromThePrefixOnward()
    {
        var report = BuildRepairReport.Parse("progress… " + Example);
        Assert.NotNull(report);
        Assert.Equal("section1/index", report!.Page);
    }

    [Fact]
    public void ALineThatIsNotACompleteMarkerIsNotRead()
    {
        Assert.Null(BuildRepairReport.Parse("Put quotes around the title of the front page of SPH4U Section 1"));
        Assert.Null(BuildRepairReport.Parse("PLANTOIR_REPAIRED: not json"));
        Assert.Null(BuildRepairReport.Parse("PLANTOIR_REPAIRED: {\"course\": \"SPH4U\", \"section\": 1, \"repair\": \"frontPageTitleQuoted\"}"));
        Assert.Null(BuildRepairReport.Parse("PLANTOIR_REPAIRED: {\"course\": \"SPH4U\", \"section\": 1, \"repair\": \"frontPageTitleQuoted\", \"page\": \"\"}"));
    }

    /// <summary><c>buildRepairs.marker.rule</c>: "A reader that meets a repair key it does not know records nothing."</summary>
    [Fact]
    public void ARepairThisAppDoesNotKnowWritesNothing()
    {
        var report = BuildRepairReport.Parse("PLANTOIR_REPAIRED: {\"course\": \"SPH4U\", \"section\": 1, \"repair\": \"somethingNewer\", \"page\": \"section1/index\"}");
        Assert.NotNull(report);
        Assert.Null(report!.TrailSentence);
        report.Record();
        Assert.Equal("", Trail());
    }

    [Fact]
    public void ARunTheAppStartsWritesTheRepairAndKeepsTheLineOutOfTheConsole()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput("Building\r\n" + Example + "\r\nDone\r\n");

        string trail = Trail();
        Assert.Contains("SPH4U/1 · " + TrailLineFor("section1/index"), trail);
        Assert.DoesNotContain(BuildRepairReport.Marker, runner.Transcript.DisplayText);
        Assert.Contains("Done", runner.Transcript.DisplayText);
    }

    /// <summary>
    /// The third reader: a run <c>plantoir-mcp</c> starts. Its capture is
    /// private to a process-running method, so the source is pinned — that it
    /// reads the line, and that no machine line reaches the assistant's
    /// progress text (<c>transcriptStripping.machineLines</c>).
    /// </summary>
    [Fact]
    public void TheMcpServersCaptureReadsTheLineAndPassesNoMachineLineOn()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Mcp", "LauncherRunner.cs"));
        int reads = source.IndexOf("BuildRepairReport.Parse(line)", StringComparison.Ordinal);
        int drops = source.IndexOf("TranscriptBuilder.IsMachineLine(line)) return;", StringComparison.Ordinal);
        int health = source.IndexOf("SiteHealthFinding.Parse(line)", StringComparison.Ordinal);
        int reports = source.IndexOf("progress?.Report(line.Trim());", StringComparison.Ordinal);
        Assert.True(reads >= 0, "LauncherRunner must read PLANTOIR_REPAIRED:");
        Assert.True(health >= 0, "LauncherRunner must read PLANTOIR_HEALTH:");
        Assert.True(reads < drops, "the repair must be read before machine lines are dropped");
        Assert.True(health < drops, "folder problems must be read before machine lines are dropped");
        Assert.True(drops >= 0 && drops < reports, "machine lines must be dropped before progress is reported");
    }
}
