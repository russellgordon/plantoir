using System.Diagnostics;
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
// Writes to the activity trail, which is process-wide state: xUnit
// parallelises test CLASSES, so a class that reads the trail file before and
// after an action needs every other trail-writing class held off. CLAUDE.md
// names this explicitly for Windows.
[Collection(SharedActivityState.Name)]
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
        // Counts THIS course's lines rather than comparing the whole file:
        // a whole-file comparison fails if anything else writes a line in
        // the same instant, which is a flake rather than a finding.
        int Lines() => File.Exists(path)
            ? File.ReadAllLines(path).Count(l => l.Contains("VVH2Q/9"))
            : 0;
        int before = Lines();
        ReclaimedProcesses.Note("ERROR: This copy of Plantoir is missing its website builder.",
                                "VVH2Q", 9);
        Assert.Equal(before, Lines());
    }

    [Fact]
    public void TheLineCarriesTheCourseTheSectionAndTheCount()
    {
        ReclaimedProcesses.Note("Stopped 3 process(es).", "VVH2O", 2);
        string written = File.ReadAllText(ActivityTrail.CurrentLogPath);
        Assert.Contains("VVH2O/2 · reclaimed 3 leftover website-builder processes", written);
    }
}

/// <summary>
/// Makes the launcher's own contract runner a GATE rather than a script
/// somebody remembers to run.
///
/// `windows-app/test_stop_preview.ps1` runs the shared stopPreview cases
/// against `preview.ps1`'s matcher — the second implementation of the rule on
/// this platform, and the one nothing else can reach. It was written, it
/// passed, and nothing ran it: not `dotnet test`, and not `verify.sh`, which
/// does not run on Windows at all. A check nobody runs is a check that stops
/// being true.
/// </summary>
public class TheLauncherMatcherAnswersTheContract
{
    [Fact]
    public void TheContractCasesPassAgainstPreviewPs1()
    {
        string? dir = AppContext.BaseDirectory;
        while (dir is not null && !File.Exists(Path.Combine(dir, "windows-app", "test_stop_preview.ps1")))
            dir = Path.GetDirectoryName(dir);
        Assert.True(dir is not null, "could not find windows-app/test_stop_preview.ps1 above the test binary");
        string script = Path.Combine(dir!, "windows-app", "test_stop_preview.ps1");

        var info = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = dir!,
        };
        foreach (string argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script })
            info.ArgumentList.Add(argument);

        using var process = Process.Start(info);
        Assert.NotNull(process);
        string output = process!.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(120_000), "the launcher's contract runner did not finish");

        // The count is asserted as well as the exit code: a runner that
        // skipped everything would also exit 0.
        Assert.Contains("0 failed", output);
        Assert.DoesNotContain("FAIL", output);
        Assert.Equal(0, process.ExitCode);
    }
}
