using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The count a stop sweep reports, and the line it leaves on the trail.
///
/// The count is the whole point of the event: a teacher reporting a publish
/// that stopped halfway is choosing between "there was nothing left to stop"
/// and "a build was still going and was ended", and nothing else on either
/// platform's trail can tell those apart.
/// </summary>
public class ReclaimedProcessesTests
{
    [Theory]
    [InlineData("Stopped 3 process(es).", 3)]
    [InlineData("Stopped 0 process(es).", 0)]
    [InlineData("Stopped 1 process(es).", 1)]
    [InlineData("Stopped 12 process(es).", 12)]
    // The shared module's own spelling, which leads with an emoji: the same
    // sentence has to be readable whichever side of the toolchain printed it.
    [InlineData("✅ Stopped 2 process(es).", 2)]
    // Real output has the sweep's own chatter above the count.
    [InlineData("Stopping preview processes for ADA1O section 1 ...\nStopped 4 process(es).\n", 4)]
    public void TheCountIsReadOffTheLauncherSentence(string printed, int expected)
    {
        Assert.Equal(expected, ReclaimedProcesses.Count(printed));
    }

    [Theory]
    [InlineData("")]
    [InlineData("Stopping preview processes for ADA1O section 1 ...")]
    [InlineData("ERROR: This copy of Plantoir is missing its website builder.")]
    // No digits after the word: not a count, and guessing one would be worse
    // than staying quiet.
    [InlineData("Stopped some process(es).")]
    public void NothingCountableMeansNoCount(string printed)
    {
        Assert.Null(ReclaimedProcesses.Count(printed));
    }

    [Fact]
    public void ANullOutputIsNotACrash()
    {
        Assert.Null(ReclaimedProcesses.Count(null!));
    }

    [Fact]
    public void TheSentenceIsTheOneATeacherWouldRecognise()
    {
        // Never the launcher's own "Stopped 3 process(es)", and never a
        // function name - CLAUDE.md rule 5.
        Assert.Equal("reclaimed 1 leftover website-builder process", ReclaimedProcesses.Wording(1));
        Assert.Equal("reclaimed 3 leftover website-builder processes", ReclaimedProcesses.Wording(3));
        Assert.Equal("reclaimed 0 leftover website-builder processes", ReclaimedProcesses.Wording(0));
        foreach (int count in new[] { 0, 1, 2, 17 })
        {
            string wording = ReclaimedProcesses.Wording(count);
            Assert.DoesNotContain("process(es)", wording);
            Assert.DoesNotContain("Stopped", wording);
        }
    }

    [Fact]
    public void TheEventIsTheOneTheContractNames()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var named = doc["activityTrail"]!["mustRecord"]!.AsArray()
            .Select(e => e!["event"]!.ToString());
        Assert.Contains("section processes reclaimed", named);
        Assert.Equal("section processes reclaimed",
                     ActivityTrail.KeyFor(ActivityTrail.Event.SectionProcessesReclaimed));
    }

    [Fact]
    public void ASweepThatSaidNothingCountableLeavesNoLine()
    {
        // A sweep that never RAN must not leave a line claiming zero: that
        // line would be indistinguishable from a sweep that ran and found
        // nothing, which is the exact distinction this event exists to make.
        string path = ActivityTrail.CurrentLogPath;
        string before = File.Exists(path) ? File.ReadAllText(path) : "";
        ReclaimedProcesses.Note("ERROR: This copy of Plantoir is missing its website builder.",
                                "VVH2O", 1);
        string after = File.Exists(path) ? File.ReadAllText(path) : "";
        Assert.Equal(before, after);
    }

    [Fact]
    public void TheLineCarriesTheCourseTheSectionAndTheCount()
    {
        ReclaimedProcesses.Note("Stopped 3 process(es).", "VVH2O", 2);
        string written = File.ReadAllText(ActivityTrail.CurrentLogPath);
        Assert.Contains("VVH2O/2 · reclaimed 3 leftover website-builder processes", written);
    }
}
