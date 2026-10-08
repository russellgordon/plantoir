using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
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

    /// <summary>
    /// #438 (the mac's #407): the two lines a deploy prints when it has to
    /// rebuild a preview's site say what deploy.sh says, word for word — "before
    /// it is deployed" and "Nothing was deployed", because publishing marks a
    /// page for the website and this step is the deploy. Read from deploy.sh
    /// rather than retyped. Only the ellipsis character may differ (deploy.ps1
    /// prints ASCII only, so it says "..."), and deploy.sh's leading "❌ ",
    /// which deploy.ps1 leaves off. Since #441 (v1.4.4) the other three
    /// rebuild lines are pinned the same way; every other line in deploy.ps1
    /// that meant a deploy moved to "deploy" with them, and
    /// scripts/test_deploy_words.py now reads deploy.ps1 for the old phrases.
    /// </summary>
    [Theory]
    [InlineData("Rebuilding it before it is deployed")]
    [InlineData("Nothing was deployed, rather than deploying pages")]
    [InlineData("before deploying it: it needed an answer")]
    [InlineData("Could not rebuild this site before deploying it.")]
    [InlineData("The rebuilt site has not appeared")]
    public void TheRebuildLinesAreDeploySHsWordForWord(string anchor)
    {
        string Echoed(string file, string prefix) =>
            File.ReadAllLines(Path.Combine(ContractLoader.RepositoryRoot, file))
                .Select(line => line.Trim())
                .Where(line => line.StartsWith(prefix, StringComparison.Ordinal) && line.Contains(anchor, StringComparison.Ordinal))
                .Select(line => line[(line.IndexOf('"') + 1)..line.LastIndexOf('"')].Trim().TrimStart('❌', ' ').Replace("…", "..."))
                .Single();
        string shLine = Echoed("deploy.sh", "echo ");
        string psLine = Echoed("deploy.ps1", "Write-Host ");
        Assert.Equal(shLine, psLine);
    }
}
