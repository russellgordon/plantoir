using System;
using System.Diagnostics;
using System.IO;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The shared contract's launcher cases, run against the REAL functions in
/// <c>preview.ps1</c> and <c>deploy.ps1</c> by
/// <c>windows-app/test_launcher_rules.ps1</c>: the forty-block port walk
/// (#286, <c>previewPorts.hostBlockCases</c>), the refusal to preview a
/// section being deployed (#386, <c>previewWhileItsSectionDeploys.launcherCases</c>,
/// translated row by row to the Windows shape of the same evidence), and
/// <c>Test-CarriesLiveReload</c> (#272, <c>buildFreshness.previewBuild.cases</c>).
/// The runner deserialises every list; nothing is retyped here.
/// </summary>
public class LauncherRulesContractTests
{
    [Fact]
    public void TheContractCasesPassAgainstTheLaunchers()
    {
        string script = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "test_launcher_rules.ps1");
        var info = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = ContractLoader.RepositoryRoot,
        };
        foreach (string argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script })
            info.ArgumentList.Add(argument);

        using var process = Process.Start(info);
        Assert.NotNull(process);
        // Both pipes read asynchronously and the PROCESS waited on (see
        // ReclaimedProcessesTests for why a sequential read can hang).
        var standardOutput = process!.StandardOutput.ReadToEndAsync();
        var standardError = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(180_000))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            Assert.Fail("the launcher rules runner did not finish within 180 s");
        }
        string output = string.Concat(standardOutput.GetAwaiter().GetResult(), standardError.GetAwaiter().GetResult());

        Assert.Contains(" 0 failed", output);
        Assert.DoesNotContain("FAIL", output);
        // A runner that skipped everything would also say "0 failed".
        Assert.Matches(@"(\d{2,}) passed", output);
        Assert.Equal(0, process.ExitCode);
    }
}
