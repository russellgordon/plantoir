using System.Diagnostics;
using Plantoir.Mcp;

namespace Plantoir.Tests;

/// <summary>
/// #289 (mac #156): plantoir-mcp stops the launcher it started, and then the
/// section's own processes, before it gives its leases back — or the course
/// reads as free while a build it started is still writing the section.
/// </summary>
public class McpLeavingTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-tests",
        "mcp-leaving-" + Guid.NewGuid().ToString("N"));

    public McpLeavingTests()
    {
        Directory.CreateDirectory(_folder);
        // A stand-in preview.ps1: a build that would run for a minute, and a
        // --stop mode that leaves a mark saying it was asked for.
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"),
            "if ($args -contains '--stop') { Set-Content -LiteralPath (Join-Path $PSScriptRoot ('stopped-' + $args[0] + '-' + $args[1] + '.txt')) -Value 'stopped'; exit 0 }\n" +
            "Start-Sleep -Seconds 60\n");
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, true); } catch { }
    }

    [Fact]
    public async Task LeavingMidBuildStopsTheLauncherAndThenTheSection()
    {
        if (!OperatingSystem.IsWindows()) return;
        var runner = new LauncherRunner();
        var clock = Stopwatch.StartNew();
        var build = runner.Run("preview", new[] { "ICS3U", "1", "--build-only" }, _folder, null, CancellationToken.None);

        // Give powershell a moment to be the running launcher.
        await Task.Delay(1500);
        LauncherRunner.StopEverythingItStarted();

        var outcome = await build.WaitAsync(TimeSpan.FromSeconds(30));
        Assert.False(outcome.Succeeded);
        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(45), $"the build was not stopped: {clock.Elapsed}");
        Assert.True(File.Exists(Path.Combine(_folder, "stopped-ICS3U-1.txt")),
            "preview.ps1 --stop was never asked to end the section's processes");
    }
}
