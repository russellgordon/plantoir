using System.Diagnostics;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Runs the GENERATED wrapper, rather than reading it.
///
/// <para>Everything else about the scheduled path is asserted against the
/// script's text, and text assertions cannot see the failure that matters:
/// <c>preview.ps1</c> sets <c>$ErrorActionPreference = 'Stop'</c>, and in
/// Windows PowerShell 5.1 merging a native command's stderr into the pipeline
/// turns the first stderr LINE into a terminating error that propagates out of
/// the callee and kills its caller. A wrapper that captured output through a
/// pipeline therefore died at the first byte of npm's noise: no exit code, no
/// scan, no deploy, nothing said — and every text assertion still passed.</para>
///
/// <para>These tests are skipped where PowerShell is not present, so the suite
/// still runs on a machine without it.</para>
/// </summary>
public class ScheduledWrapperRunTests : IDisposable
{
    private readonly string _root;

    public ScheduledWrapperRunTests()
    {
        _root = Path.Combine(Path.GetTempPath(), $"plantoir-wraprun-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static bool PowerShellIsAvailable =>
        OperatingSystem.IsWindows() && File.Exists(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "powershell.exe"));

    /// <summary>
    /// A stand-in for <c>preview.ps1</c> that behaves the way the real one
    /// does where it matters: the same error preference, a native command
    /// writing to stderr (npm and node both do), a finding on stdout, and a
    /// non-zero exit — the missing-front-page case.
    /// </summary>
    private const string LauncherStub = """
        $ErrorActionPreference = 'Stop'
        Write-Host "building..."
        & cmd.exe /c "echo npm noise on stderr 1>&2"
        Write-Host "PLANTOIR_HEALTH: {""name"": ""sectionIndexMissing"", ""sentence"": ""S"", ""detail"": ""D"", ""fixable"": true, ""course"": ""ICS3U"", ""section"": 1}"
        Write-Host "Nothing to publish."
        exit 1
        """;

    /// <summary>The task name of the most recent <see cref="RunWrapper"/>, which the capture files are named after.</summary>
    private string _lastTaskName = "";

    private (int ExitCode, string Output) RunWrapper(string launcherBody, string? workFolderName = null)
    {
        // "work with spaces" by DEFAULT, deliberately. Every fixture here used
        // a space-free temp path at first, and that hid a real defect: the
        // launcher was handed to Start-Process as an argument ARRAY, which
        // quotes nothing, so a path with a space in it was split and the build
        // never ran. Russell's own working folder is called "scheduled deploy
        // test". A fixture that cannot reproduce the machine is not a fixture.
        string work = Path.Combine(_root, workFolderName ?? "work with spaces");
        Directory.CreateDirectory(work);
        File.WriteAllText(Path.Combine(work, "preview.ps1"), launcherBody);
        File.WriteAllText(Path.Combine(work, "deploy.ps1"), "Write-Host 'DEPLOY RAN'\nexit 0");

        _lastTaskName = $"Plantoir-wraprun-{Guid.NewGuid():N}";
        string? script = TaskScheduling.WriteWrapperScript(
            _lastTaskName, work, Path.Combine(work, "deploy.ps1"),
            "ICS3U", 1, Path.Combine(work, "courses", "ICS3U"),
            Array.Empty<string>(),
            new[] { new CourseConfiguration.DeployDestination("local_folder", _root) },
            "");
        Assert.NotNull(script);

        var info = new ProcessStartInfo("powershell.exe")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            WorkingDirectory = work,
        };
        // The wrapper is RUN, so it writes wherever it was told to write — and
        // WriteWrapperScript bakes AppDataRoot's real path in, which in a test
        // process is the teacher's own %LOCALAPPDATA%\Plantoir. Before the
        // scheduled outcome record existed this was harmless here, because the
        // wrapper only wrote one on exit 3 and nothing in this class produces
        // one. It now writes a record on EVERY path, so an unsubstituted run
        // leaves "succeeded / <a temp folder> / ICS3U / 1" in the teacher's
        // state — and the next time Plantoir opens, the startup sweep puts a
        // trail line about a publish that never happened in front of them and
        // ICS3U section 1 shows a green notice saying last night went out.
        //
        // Substituting the one baked literal is what ScheduledPublishOutcomeTests
        // does and for the same reason. AppDataRoot.RedirectTo is NOT the
        // answer: it is process-wide with no way back, so it would point every
        // later test in this process at a scratch folder.
        string runnable = Path.Combine(_root, Path.GetFileName(script!));
        File.WriteAllText(runnable,
            File.ReadAllText(script!).Replace(ScheduledPublishOutcome.Directory(), _root));

        foreach (string a in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", runnable })
            info.ArgumentList.Add(a);

        using var process = Process.Start(info)!;
        string output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
        process.WaitForExit(120_000);
        try { File.Delete(script!); } catch { }
        return (process.ExitCode, output);
    }

    [Fact]
    public void ABuildThatWritesToStderrDoesNotKillTheWrapper()
    {
        if (!PowerShellIsAvailable) return;

        var (_, output) = RunWrapper(LauncherStub);

        // The wrapper's own words, printed AFTER the build and its scan. If a
        // terminating NativeCommandError propagated out of the launcher, the
        // wrapper never reaches this line and the overnight run publishes
        // nothing while saying nothing.
        Assert.Contains("Could not build this section", output);
        Assert.DoesNotContain("NativeCommandError", output);
    }

    [Fact]
    public void AFailingBuildStillLeavesItsFindingsBehind()
    {
        if (!PowerShellIsAvailable) return;

        // The record for the stub's course lives in the real per-user
        // location, so take it the way the app does and put nothing back.
        ScheduledHealthFindings.Take("ICS3U", 1);

        RunWrapper(LauncherStub);
        var found = ScheduledHealthFindings.Take("ICS3U", 1);

        // The whole point of scanning before the failure guard: this build
        // FAILED, and the finding is the reason it failed.
        Assert.Single(found);
        Assert.Equal("sectionIndexMissing", found[0].Name);
    }

    [Fact]
    public void AFailedBuildPublishesNothing()
    {
        if (!PowerShellIsAvailable) return;

        var (exitCode, output) = RunWrapper(LauncherStub);

        Assert.Equal(1, exitCode);
        Assert.DoesNotContain("DEPLOY RAN", output);
    }

    [Fact]
    public void AGoodBuildDeploysAndLeavesNoRecord()
    {
        if (!PowerShellIsAvailable) return;

        ScheduledHealthFindings.Take("ICS3U", 1);

        var (exitCode, output) = RunWrapper("""
            $ErrorActionPreference = 'Stop'
            Write-Host "building..."
            & cmd.exe /c "echo npm noise on stderr 1>&2"
            Write-Host "Static build complete."
            exit 0
            """);

        Assert.Equal(0, exitCode);
        Assert.Contains("DEPLOY RAN", output);
        // A clean run clears anything an earlier one left.
        Assert.Empty(ScheduledHealthFindings.Take("ICS3U", 1));
    }

    [Fact]
    public void AWorkingFolderWithSpacesInItsNameStillBuilds()
    {
        if (!PowerShellIsAvailable) return;

        // The defect this was written for: Start-Process joins an argument
        // ARRAY with spaces and quotes nothing, so the launcher's path was
        // split and powershell.exe answered "Processing -File 'C:\...\work'
        // failed because the file does not have a '.ps1' extension" — exit
        // -196608, no build, no findings, no deploy, every night, silently.
        ScheduledHealthFindings.Take("ICS3U", 1);

        var (exitCode, output) = RunWrapper(LauncherStub, "a folder with spaces");

        Assert.DoesNotContain("does not have a '.ps1' extension", output);
        Assert.Equal(1, exitCode);                       // the stub's own code, not a launch failure
        Assert.Single(ScheduledHealthFindings.Take("ICS3U", 1));
    }

    [Fact]
    public void TheCaptureFilesAreNotLeftBehind()
    {
        if (!PowerShellIsAvailable) return;

        RunWrapper(LauncherStub);

        // Scoped to THIS run's own capture files, by the task name they are
        // named after. The directory is a real per-user one shared with every
        // other scheduled task on the machine, and asserting it is empty
        // wholesale fails on somebody else's litter — which it did, on debris
        // from a hand-run diagnostic.
        string dir = ScheduledHealthFindings.Directory();
        Assert.Empty(Directory.Exists(dir)
            ? Directory.GetFiles(dir, _lastTaskName + "*")
            : Array.Empty<string>());
        ScheduledHealthFindings.Take("ICS3U", 1);
    }
}
