using System.Diagnostics;

namespace Plantoir.Tests;

/// <summary>
/// `windows-app/TestRunOutcome.ps1` decides whether a red run is a failing
/// test or a dead test host. A mistake in it is SILENT — it would go on saying
/// "FAILED" and everybody would go on re-running a bystander — so its own
/// checks run inside `dotnet test` rather than in a script somebody remembers.
///
/// <para>Same arrangement as
/// <see cref="TheLauncherMatcherAnswersTheContract"/>, and the pipe handling
/// below is copied from it deliberately: a sequential ReadToEnd on stdout then
/// stderr deadlocks if stderr fills its ~4 KB pipe first, and either
/// ReadToEnd blocks forever on a wedged child no matter what timeout
/// WaitForExit is given. A test that can hang the suite is worse than no
/// test.</para>
/// </summary>
public class TheTestRunReaderTellsACrashFromAFailure
{
    [Fact]
    public void ItsOwnChecksPass()
    {
        string? dir = AppContext.BaseDirectory;
        while (dir is not null && !File.Exists(Path.Combine(dir, "windows-app", "test_run_outcome.ps1")))
            dir = Path.GetDirectoryName(dir);
        Assert.True(dir is not null, "could not find windows-app/test_run_outcome.ps1 above the test binary");
        string script = Path.Combine(dir!, "windows-app", "test_run_outcome.ps1");

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

        var standardOutput = process!.StandardOutput.ReadToEndAsync();
        var standardError = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(60_000))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            Assert.Fail("windows-app/test_run_outcome.ps1 did not finish within 60 s");
        }
        string output = string.Concat(
            standardOutput.GetAwaiter().GetResult(),
            standardError.GetAwaiter().GetResult());

        // The COUNT is asserted as well as the exit code, for the same reason
        // the thing under test exists: a runner that checked nothing would also
        // exit 0, and this suite is about not believing a green that ran
        // nothing.
        //
        // The comma is load-bearing: "0 failed" alone is a substring of
        // "10 failed", so the bare form would read a run with ten failures as
        // a clean one. The script prints "<n> checks, 0 failed".
        Assert.Contains(", 0 failed", output);
        Assert.DoesNotContain("FAIL ", output);
        Assert.Equal(0, process.ExitCode);
    }
}
