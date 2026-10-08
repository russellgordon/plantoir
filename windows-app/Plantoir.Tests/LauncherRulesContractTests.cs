using System;
using System.Diagnostics;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The shared contract's launcher cases, run against the REAL functions in
/// <c>preview.ps1</c> and <c>deploy.ps1</c> by
/// <c>windows-app/test_launcher_rules.ps1</c>: the forty-block port walk
/// (#286, <c>previewPorts.hostBlockCases</c>), the refusal to preview a
/// section being deployed (#386, <c>previewWhileItsSectionDeploys.launcherCases</c>,
/// translated row by row to the Windows shape of the same evidence),
/// <c>Test-CarriesLiveReload</c> (#272, <c>buildFreshness.previewBuild.cases</c>),
/// and the refusal to deploy a section still being deployed (#467,
/// <c>deployWhileItsSectionDeploys.launcherCases</c>, against each launcher's
/// copy of the shared block).
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

    // ---- #467: the block both launchers carry ---------------------------------

    private const string BlockStart = "# >>> DEPLOY WHILE ITS SECTION DEPLOYS BLOCK >>>";
    private const string BlockEnd = "# <<< DEPLOY WHILE ITS SECTION DEPLOYS BLOCK <<<";

    private static string Launcher(string name) =>
        File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, name)).Replace("\r\n", "\n");

    private static string BlockOf(string source)
    {
        int start = source.IndexOf(BlockStart, StringComparison.Ordinal);
        int end = source.IndexOf(BlockEnd, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start, "the launcher no longer carries the marked block");
        Assert.Equal(start, source.LastIndexOf(BlockStart, StringComparison.Ordinal));
        return source[start..(end + BlockEnd.Length)];
    }

    /// <summary>
    /// One reader of the process table, two copies: <c>deploy.ps1</c> and
    /// <c>preview.ps1</c> must carry the SAME block, byte for byte once line
    /// endings are set aside (the mac's <c>scripts/test_port_blocks.py</c>
    /// precedent). A dot-sourced module was rejected: the app mirrors named
    /// launchers into each working folder, and a launcher typed in a folder
    /// missing the module would break.
    /// </summary>
    [Fact]
    public void TheDeployGuardBlockIsTheSameInBothLaunchers()
    {
        Assert.Equal(BlockOf(Launcher("deploy.ps1")), BlockOf(Launcher("preview.ps1")));
    }

    /// <summary>
    /// The look trusts nothing left on disk: no lease, no outcome record, no
    /// job file, no remembered process id - so nothing a crash leaves behind
    /// can refuse a deploy for ever (the mac's
    /// <c>test_the_look_trusts_no_remembered_process_id</c>). And it cannot
    /// hang: a wedged WMI service is "cannot be read", which lets it through.
    /// </summary>
    [Fact]
    public void TheDeployGuardReadsOnlyTheLiveProcessTable()
    {
        string block = BlockOf(Launcher("deploy.ps1"));
        foreach (string forbidden in new[] { ".lease", "unanswered", ".job.json", ".pid", "Get-Content" })
            Assert.DoesNotContain(forbidden, block, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Get-CimInstance Win32_Process -OperationTimeoutSec 30 -ErrorAction Stop", block);
    }

    /// <summary>
    /// Where each launcher asks: deploy.ps1 once, for every run that deploys
    /// (not --reset-token or --logout), AFTER the Open-code question and the
    /// reference-course refusal and BEFORE anything is changed; preview.ps1
    /// once, for a --build-only run that is not --stop, before the section is
    /// checked against the course.
    /// </summary>
    [Fact]
    public void EachLauncherAsksOnceAndBeforeAnythingChanges()
    {
        string deploy = Launcher("deploy.ps1");
        const string deployCall = "if (-not $RESET_TOKEN) { Stop-WhileThisSectionDeploys $COURSE_CODE ([string]$SECTION_NUM) 'deploy' }";
        Assert.Single(Occurrences(deploy, "Stop-WhileThisSectionDeploys $"));
        int at = deploy.IndexOf(deployCall, StringComparison.Ordinal);
        Assert.True(at > 0, "deploy.ps1 no longer asks for every run that deploys");
        Assert.True(at > deploy.IndexOf("$REFERENCE_COURSE_REFUSAL)", StringComparison.Ordinal), "asked before the reference-course refusal");
        Assert.True(at > deploy.IndexOf("$COURSE_CODE = $suggested", StringComparison.Ordinal), "asked before the Open-code question");
        Assert.True(at < deploy.IndexOf("function Resolve-PublishFolder", StringComparison.Ordinal), "asked after the publish folder is worked out");
        Assert.True(at < deploy.IndexOf("$py = Enter-NativeRuntime", StringComparison.Ordinal), "asked after the runtime is entered");

        string preview = Launcher("preview.ps1");
        const string previewCall = "if ($BUILD_ONLY -and -not $STOP_MODE) {\n    Stop-WhileThisSectionDeploys $COURSE ([string]$SECTION) 'build'\n}";
        Assert.Single(Occurrences(preview, "Stop-WhileThisSectionDeploys $"));
        int build = preview.IndexOf(previewCall, StringComparison.Ordinal);
        Assert.True(build > 0, "preview.ps1 no longer asks on a --build-only run");
        Assert.True(build > preview.IndexOf("if ($NATIVE_RUNTIME -and $STOP_MODE) {", StringComparison.Ordinal), "asked before --stop has gone its own way");
        Assert.True(build < preview.IndexOf("# ---- Validate SECTION against course_config.json ----", StringComparison.Ordinal), "asked after the section is checked");
    }

    private static List<int> Occurrences(string text, string needle)
    {
        var found = new List<int>();
        for (int i = text.IndexOf(needle, StringComparison.Ordinal); i >= 0; i = text.IndexOf(needle, i + 1, StringComparison.Ordinal))
            found.Add(i);
        return found;
    }

    /// <summary>
    /// #467's first finding: the launchers built the wrapper's name the way
    /// the app built it BEFORE #309, so no current wrapper ever matched and
    /// #386's "a deploy set for later" half was dead - and the runner, which
    /// built its expected name with the launcher's own function, could not
    /// see it. So the names are checked here against the APP's
    /// (<see cref="TaskScheduling.NameFor"/>, <c>OldNameFor</c>,
    /// <c>WrapperScriptPath</c>), and the launcher's <c>$WORKDIR_ID</c>,
    /// computed by its own lines in a real folder, against
    /// <see cref="FolderContainers.FolderIdentifier"/>: no third copy of
    /// either is kept anywhere.
    /// </summary>
    [Fact]
    public void TheWrapperNamesAndTheFolderIdAreTheAppsOwn()
    {
        string folder = Path.Combine(Path.GetTempPath(), "plantoir 467 " + Guid.NewGuid().ToString("N")[..6]);
        Directory.CreateDirectory(folder);
        string probe = Path.Combine(Path.GetTempPath(), "plantoir-467-names-" + Guid.NewGuid().ToString("N") + ".ps1");
        try
        {
            File.WriteAllText(probe, ProbeScript);
            var info = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            foreach (string argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", probe, "-Repo", ContractLoader.RepositoryRoot, "-Folder", folder })
                info.ArgumentList.Add(argument);
            using var process = Process.Start(info);
            Assert.NotNull(process);
            var standardOutput = process!.StandardOutput.ReadToEndAsync();
            var standardError = process.StandardError.ReadToEndAsync();
            Assert.True(process.WaitForExit(60_000), "the name probe did not finish within 60 s");
            string output = standardOutput.GetAwaiter().GetResult();
            Assert.True(process.ExitCode == 0, output + standardError.GetAwaiter().GetResult());

            string id = FolderContainers.FolderIdentifier(folder);
            string[] tasks = { TaskScheduling.NameFor("ap calc", 2, folder), TaskScheduling.OldNameFor("ap calc", 2) };
            foreach (string launcher in new[] { "deploy.ps1", "preview.ps1" })
            {
                string[] lines = output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Where(line => line.StartsWith(launcher + "|", StringComparison.Ordinal)).ToArray();
                Assert.Equal(new[] { $"{launcher}|id|{id}" }, lines.Where(l => l.Contains("|id|")).ToArray());
                Assert.Equal(tasks.Select(t => $"{launcher}|task|{t}").ToArray(), lines.Where(l => l.Contains("|task|")).ToArray());
                Assert.Equal(tasks.Select(t => $"{launcher}|script|{Path.GetFileName(TaskScheduling.WrapperScriptPath(t))}").ToArray(),
                             lines.Where(l => l.Contains("|script|")).ToArray());
            }
        }
        finally
        {
            try { File.Delete(probe); } catch { }
            try { Directory.Delete(folder, recursive: true); } catch { }
        }
    }

    // Runs each launcher's OWN lines - the Add-Type for the physical path, the
    // path and id assignments, the two name functions - lifted out with the
    // parser (never dot-sourcing the launcher, which would run it).
    private const string ProbeScript = """
        param([string]$Repo, [string]$Folder)
        $ErrorActionPreference = 'Stop'
        foreach ($launcher in @('deploy.ps1', 'preview.ps1')) {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo $launcher), [ref]$tokens, [ref]$errors)
            $wanted = $ast.EndBlock.Statements | Where-Object {
                ($_ -is [System.Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.Contains("PSTypeName]'Plantoir.PathApi'")) -or
                ($_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and @('Get-PhysicalPath', 'Get-ScheduledDeployTaskNames', 'Get-ScheduledDeployScriptNames') -contains $_.Name) -or
                ($_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and @('$WORKDIR_PHYSICAL', '$WORKDIR_ID') -contains $_.Left.Extent.Text)
            }
            Set-Location -LiteralPath $Folder
            . ([scriptblock]::Create((@($wanted | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine)))
            "$launcher|id|$WORKDIR_ID"
            foreach ($n in @(Get-ScheduledDeployTaskNames 'ap calc' '2' $WORKDIR_ID)) { "$launcher|task|$n" }
            foreach ($n in @(Get-ScheduledDeployScriptNames 'ap calc' '2' $WORKDIR_ID)) { "$launcher|script|$n" }
        }
        """;
}
