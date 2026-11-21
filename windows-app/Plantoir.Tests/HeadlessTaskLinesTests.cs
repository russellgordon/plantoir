using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #774: a deploy or build <c>plantoir-mcp.exe</c> runs writes
/// <c>task started</c> and <c>task finished</c> (<c>activityTrail.mustRecord</c>),
/// in the window's words, with the course and section through
/// <see cref="ActivityTrail.Place"/>, and with the arguments redacted. A stub
/// <c>deploy.ps1</c> exits with the code each test names; the account ID is
/// made up (32 hex characters, the shape of a Cloudflare Account ID).
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class HeadlessTaskLinesTests : IDisposable
{
    private const string MadeUpAccountID = "0123456789abcdef0123456789abcdef";

    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-tests", "headless-task-" + Guid.NewGuid().ToString("N"));
    private readonly string _trail;

    public HeadlessTaskLinesTests()
    {
        Directory.CreateDirectory(Path.Combine(_folder, "trail"));
        _trail = Path.Combine(_folder, "trail", "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private async Task<string[]> RunStubDeploy(int exitCode, IReadOnlyList<string> arguments)
    {
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), $"Write-Output 'stub deploy'\r\nexit {exitCode}\r\n");
        var outcome = await new LauncherRunner().Run("deploy", arguments, _folder, null, CancellationToken.None);
        Assert.Equal(exitCode, outcome.ExitCode ?? 0);
        return File.ReadAllLines(_trail).Where(line => line.Length > 0).ToArray();
    }

    private static string AfterStamp(string line) => line[(line.IndexOf(" · ", StringComparison.Ordinal) + 3)..];

    [Fact]
    public async Task ADeployThatStopsAtAQuestionWritesBothLinesWithItsPlaceAndNoAccountID()
    {
        string[] lines = await RunStubDeploy(3, new[] { "ICS3U", "2", "--non-interactive", "--account", MadeUpAccountID });

        Assert.Equal(2, lines.Length);
        foreach (string line in lines) Assert.DoesNotContain(MadeUpAccountID, line);
        Assert.StartsWith(ActivityTrail.Place("ICS3U", 2) + "started deploy.ps1 ICS3U 2 --non-interactive --account ", AfterStamp(lines[0]));
        Assert.StartsWith(ActivityTrail.Place("ICS3U", 2) + "finished deploy.ps1 — " + ActivityTrail.StoppedAtAQuestionNobodyCouldAnswer + " after ",
                          AfterStamp(lines[1]));
    }

    [Fact]
    public async Task ADeployThatSucceedsOrFailsSaysSoInTheWindowsWords()
    {
        string[] succeeded = await RunStubDeploy(0, new[] { "ICS3U", "1", "--non-interactive" });
        Assert.Equal(2, succeeded.Length);
        Assert.Equal(ActivityTrail.Place("ICS3U", 1) + "started deploy.ps1 ICS3U 1 --non-interactive", AfterStamp(succeeded[0]));
        Assert.StartsWith(ActivityTrail.Place("ICS3U", 1) + "finished deploy.ps1 — "
                          + ScriptRunner.FinishedOutcome(0, false, false, false) + " after ", AfterStamp(succeeded[1]));

        File.Delete(_trail);
        string[] failed = await RunStubDeploy(1, new[] { "ICS3U", "1", "--non-interactive" });
        Assert.StartsWith(ActivityTrail.Place("ICS3U", 1) + "finished deploy.ps1 — "
                          + ScriptRunner.FinishedOutcome(1, false, false, false) + " after ", AfterStamp(failed[1]));
    }

    [Fact]
    public async Task ALauncherThatIsNotThereIsWrittenAsNotStarted()
    {
        var outcome = await new LauncherRunner().Run("preview", new[] { "ICS3U", "1", "--build-only" }, _folder, null, CancellationToken.None);
        Assert.False(outcome.Succeeded);
        string[] lines = File.ReadAllLines(_trail).Where(line => line.Length > 0).ToArray();
        Assert.Single(lines);
        Assert.Equal(ActivityTrail.Place("ICS3U", 1) + "could not start preview.ps1 — " + outcome.Message, AfterStamp(lines[0]));
    }

    [Fact]
    public void ThePlaceIsReadFromTheLaunchersFirstTwoArguments()
    {
        Assert.Equal(("ICS3U", 2), ActivityTrail.PlaceOfLauncherArguments(new[] { "ICS3U", "2", "--build-only" }));
        Assert.Equal(("ICS3U", 0), ActivityTrail.PlaceOfLauncherArguments(new[] { "ICS3U", "--stop" }));
        Assert.Equal(("", 0), ActivityTrail.PlaceOfLauncherArguments(new[] { "--stop" }));
        Assert.Equal(("", 0), ActivityTrail.PlaceOfLauncherArguments(Array.Empty<string>()));
    }
}
