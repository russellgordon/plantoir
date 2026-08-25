using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// What a RUN does with the health lines its build printed: collect them in
/// order, count a repeat as one problem, and leave a line on the activity
/// trail. Nothing on Windows displays findings yet, so the trail line is the
/// whole of what a teacher's build currently leaves behind.
///
/// <para>Driven through <see cref="ScriptRunner.ReceiveOutput"/>, which is the
/// same door the real pseudo console feeds — including the chunk boundaries,
/// which is where the interesting bug lives.</para>
/// </summary>
public class SiteHealthRunnerTests : IDisposable
{
    private readonly string _trailPath;

    public SiteHealthRunnerTests()
    {
        _trailPath = Path.Combine(Path.GetTempPath(), $"plantoir-trail-{Guid.NewGuid():N}.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trailPath);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(null);
        try { File.Delete(_trailPath); } catch { }
    }

    private string Trail() => File.Exists(_trailPath) ? File.ReadAllText(_trailPath) : "";

    private static string HealthLine(string name, string course = "ICS3U", int section = 1) =>
        $"{SiteHealthFinding.Marker} {{\"name\": \"{name}\", \"sentence\": \"A sentence.\", " +
        $"\"detail\": \"Some detail.\", \"fixable\": false, \"course\": \"{course}\", \"section\": {section}}}";

    [Fact]
    public void ABuildsFindingsAreCollectedInOrder()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput("Building ICS3U Section 1...\r\n");
        runner.ReceiveOutput(HealthLine("noGradedFolders") + "\r\n");
        runner.ReceiveOutput("...more output\r\n");
        runner.ReceiveOutput(HealthLine("mediaFolderMissing") + "\r\n");

        Assert.Equal(
            new[] { "noGradedFolders", "mediaFolderMissing" },
            runner.HealthFindings.Select(f => f.Name).ToArray());
    }

    /// <summary>
    /// The case that would have been silent: a pseudo console hands over
    /// whatever bytes are ready, so a health line arrives in two pieces. A
    /// per-chunk scan drops it — and drops it only sometimes, which is worse
    /// than dropping it always.
    /// </summary>
    [Fact]
    public void AFindingSplitAcrossTwoChunksIsStillFound()
    {
        string line = HealthLine("noGradedFolders");
        int middle = line.Length / 2;

        var runner = new ScriptRunner();
        runner.ReceiveOutput(line[..middle]);
        runner.ReceiveOutput(line[middle..] + "\r\n");

        Assert.Single(runner.HealthFindings);
        Assert.Equal("noGradedFolders", runner.HealthFindings[0].Name);
    }

    [Fact]
    public void AFindingWithNoTrailingNewlineYetIsNotReportedEarly()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput(HealthLine("noGradedFolders"));
        Assert.Empty(runner.HealthFindings);

        runner.ReceiveOutput("\r\n");
        Assert.Single(runner.HealthFindings);
    }

    [Fact]
    public void TheSameProblemPrintedTwiceIsOneProblem()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput(HealthLine("mediaFolderMissing") + "\r\n");
        runner.ReceiveOutput(HealthLine("mediaFolderMissing") + "\r\n");

        Assert.Single(runner.HealthFindings);
    }

    [Fact]
    public void TheSameCheckInAnotherSectionIsAnotherProblem()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput(HealthLine("sectionIndexMissing", section: 1) + "\r\n");
        runner.ReceiveOutput(HealthLine("sectionIndexMissing", section: 2) + "\r\n");

        Assert.Equal(2, runner.HealthFindings.Count);
    }

    [Fact]
    public void OrdinaryBuildOutputCollectsNothing()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput("Building...\r\nCopying pages...\r\nDone.\r\n");
        Assert.Empty(runner.HealthFindings);
        Assert.DoesNotContain("folder problem found", Trail());
    }

    /// <summary>
    /// Recorded when the build reports it. The trail's job is to answer "what
    /// was happening when it went wrong", and on this platform there is
    /// nothing else at all: no dialog shows these findings yet.
    /// </summary>
    [Fact]
    public void AFindingLeavesALineOnTheTrail()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput(HealthLine("noGradedFolders") + "\r\n");

        string trail = Trail();
        Assert.Contains("ICS3U/1", trail);
        Assert.Contains("noGradedFolders", trail);
    }

    /// <summary>
    /// The line carries the stable check NAME, never the sentence a teacher
    /// read — the wording gets reworded, the name is what somebody searching
    /// the trail months later can match against the contract.
    /// </summary>
    [Fact]
    public void TheTrailLineDoesNotCarryTheProductWording()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput(HealthLine("noGradedFolders") + "\r\n");

        Assert.DoesNotContain("A sentence.", Trail());
        Assert.DoesNotContain("Some detail.", Trail());
    }

    [Fact]
    public void ARepeatedProblemLeavesOneTrailLine()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput(HealthLine("mediaFolderMissing") + "\r\n");
        runner.ReceiveOutput(HealthLine("mediaFolderMissing") + "\r\n");

        int lines = Trail().Split('\n').Count(l => l.Contains("mediaFolderMissing"));
        Assert.Equal(1, lines);
    }

    /// <summary>
    /// A finding carried across a very long unterminated stretch of output
    /// survives the carry buffer's own trimming.
    ///
    /// <para>The first version trimmed the carry to its TAIL, copying the
    /// milestone scanner's sliding window. That is inverted for a line buffer:
    /// after the newline loop the carry is the HEAD of one line, so the marker
    /// is at the front and a tail-trim throws it away. Found by adversarial
    /// review, not by any test that existed.</para>
    /// </summary>
    [Fact]
    public void AVeryLongUnterminatedLineDoesNotLoseItsMarker()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput(HealthLine("noGradedFolders").Replace(
            "Some detail.", "Some detail. " + new string('x', 12000)));
        Assert.Empty(runner.HealthFindings);   // no newline yet

        runner.ReceiveOutput("\r\n");
        Assert.Single(runner.HealthFindings);
        Assert.Equal("noGradedFolders", runner.HealthFindings[0].Name);
    }

    /// <summary>
    /// ...while output that can never become a finding is still dropped, so
    /// the carry cannot grow without bound on a spinner or a progress bar that
    /// prints no newline for minutes.
    /// </summary>
    [Fact]
    public void OutputThatCannotBecomeAFindingIsNotHoardedForever()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput(new string('.', 20000));
        runner.ReceiveOutput(HealthLine("mediaFolderMissing") + "\r\n");

        Assert.Single(runner.HealthFindings);
    }

    /// <summary>
    /// The property hands out a snapshot: a caller holding the answer is not
    /// emptied under them when the next run starts.
    /// </summary>
    [Fact]
    public void TheFindingsHandedOutAreASnapshot()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput(HealthLine("noGradedFolders") + "\r\n");
        var held = runner.HealthFindings;

        runner.ReceiveOutput(HealthLine("mediaFolderMissing") + "\r\n");

        Assert.Single(held);
        Assert.Equal(2, runner.HealthFindings.Count);
    }

    [Fact]
    public void AnsiColouringAroundAFindingDoesNotHideIt()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput("\x1b[33m" + HealthLine("noGradedFolders") + "\x1b[0m\r\n");

        Assert.Single(runner.HealthFindings);
    }
}
