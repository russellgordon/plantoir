using System.Text.RegularExpressions;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #565 (mac #560): the trail's first line of a session names the version a
/// teacher can see — "1.7.2", never "1.7 (2)" — and its last line says why
/// Plantoir closed, with the same pid, once.
/// </summary>
[Collection(SharedActivityState.Name)]
public class AppOpenedAndClosedTests
{
    /// <summary>The three-part version from Plantoir.csproj, then the build only when there is one.</summary>
    [Fact]
    public void TheOpenedLineCarriesTheThreePartVersion()
    {
        Assert.Equal("1.7.2", ProblemReportEnvironment.Spelled(new Version(1, 7, 2, 0)));
        Assert.Equal("1.7.2", ProblemReportEnvironment.Spelled(new Version(1, 7, 2)));
        Assert.Equal("1.8.0 (12)", ProblemReportEnvironment.Spelled(new Version(1, 8, 0, 12)));

        string csproj = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Plantoir.csproj"));
        string version = Regex.Match(csproj, @"<Version>([^<]+)</Version>").Groups[1].Value;
        Assert.Equal(version, ProblemReportEnvironment.Spelled(Version.Parse(version)));

        Assert.Matches(@"^Plantoir \d+\.\d+\.\d+( \(\d+\))? · pid \d+ · ", ProblemReportEnvironment.AppDescription);
    }

    /// <summary>The contract's own example line, and the other two reasons in the same shape.</summary>
    [Fact]
    public void TheClosedLineIsTheContractsShape()
    {
        var entry = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .First(e => e!["event"]!.ToString() == "app closed")!;
        Assert.Equal(entry["line"]!.ToString(), ActivityTrail.ClosedLine(QuitConfirmation.ClosingReason.ByTheTeacher, 4711));
        Assert.Equal("Plantoir closed — to install a new version · pid 4711",
                     ActivityTrail.ClosedLine(QuitConfirmation.ClosingReason.ToInstallANewVersion, 4711));
        Assert.Equal("Plantoir closed — asked to close by Windows · pid 4711",
                     ActivityTrail.ClosedLine(QuitConfirmation.ClosingReason.AskedByWindows, 4711));
        Assert.Contains("asked to close by Windows", entry["carries"]!.ToString());
    }

    /// <summary>
    /// Installing wins: the updater's own exit, or Restart Manager closing
    /// the app for the installer (ENDSESSION_CLOSEAPP). A sign-out, restart
    /// or shutdown without that bit is Windows'; anything else the teacher's.
    /// </summary>
    [Theory]
    [InlineData(false, false, 0L, QuitConfirmation.ClosingReason.ByTheTeacher)]
    [InlineData(true, false, 0L, QuitConfirmation.ClosingReason.ToInstallANewVersion)]
    [InlineData(false, true, 0x1L, QuitConfirmation.ClosingReason.ToInstallANewVersion)]
    [InlineData(false, true, 0L, QuitConfirmation.ClosingReason.AskedByWindows)]
    [InlineData(false, true, 0x80000000L, QuitConfirmation.ClosingReason.AskedByWindows)]
    [InlineData(false, false, 0x1L, QuitConfirmation.ClosingReason.ByTheTeacher)]
    public void TheReasonIsReadFromWhatTheAppKnew(bool updater, bool ending, long flags, QuitConfirmation.ClosingReason expected) =>
        Assert.Equal(expected, QuitConfirmation.ClosingReasonFor(updater, ending, flags));

    /// <summary>Once, after an opened line, with this process's pid; never without one.</summary>
    [Fact]
    public void TheClosedLineIsWrittenOnceAndOnlyAfterTheOpenedLine()
    {
        string scratch = Directory.CreateTempSubdirectory("plantoir-565").FullName;
        string trail = Path.Combine(scratch, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(trail);
        try
        {
            ActivityTrail.ResetOpenAndCloseForTests(opened: false);
            Assert.False(ActivityTrail.NoteClosed(QuitConfirmation.ClosingReason.ByTheTeacher));
            Assert.False(File.Exists(trail) && File.ReadAllText(trail).Contains("Plantoir closed"));

            ActivityTrail.NoteLaunch();
            Assert.True(ActivityTrail.NoteClosed(QuitConfirmation.ClosingReason.AskedByWindows, TimeSpan.FromMilliseconds(500)));
            Assert.False(ActivityTrail.NoteClosed(QuitConfirmation.ClosingReason.ByTheTeacher));

            var lines = File.ReadAllLines(trail);
            string opened = lines.Single(line => line.Contains("Plantoir opened — "));
            string closed = lines.Single(line => line.Contains("Plantoir closed — "));
            Assert.Contains($"· pid {Environment.ProcessId} ·", opened);
            Assert.EndsWith($"Plantoir closed — asked to close by Windows · pid {Environment.ProcessId}", closed);
            Assert.True(Array.IndexOf(lines, closed) > Array.IndexOf(lines, opened));
        }
        finally
        {
            ActivityTrail.ResetOpenAndCloseForTests(opened: false);
            ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
            try { Directory.Delete(scratch, recursive: true); } catch { }
        }
    }

    /// <summary>Both places a close can be heard write it: the last window's quit and the end of a session.</summary>
    [Fact]
    public void BothClosingPathsWriteTheLine()
    {
        string app = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");
        Assert.Contains("ActivityTrail.NoteClosed(Services.SessionEnding.ClosingReason(_installerStarted))",
                        File.ReadAllText(Path.Combine(app, "App.xaml.cs")));
        Assert.Contains("ActivityTrail.NoteClosed(", File.ReadAllText(Path.Combine(app, "Services", "SessionEnding.cs")));
    }
}
