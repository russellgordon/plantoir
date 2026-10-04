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
///
/// <para><b>Serialised with the rest of the process-wide and machine-wide
/// state, for two reasons rather than one.</b> The record these tests write and
/// read lives in the real
/// <c>%LOCALAPPDATA%\Plantoir\scheduled\folder-problems</c> under ICS3U section
/// 1 — <c>$healthDir</c> resolves <c>$env:LOCALAPPDATA</c> inside the wrapper at
/// RUN time, so no substitution can move it — and
/// <see cref="ScheduledPublishOutcomeTests"/> runs wrappers for the same course
/// and section whose stub build finds nothing, which DELETES that record. That
/// is the flake seen on 2026-09-18: <c>Assert.Single</c> on an empty list in
/// <c>AWorkingFolderWithSpacesInItsNameStillBuilds</c>, green alone and on
/// re-run. And <c>Take</c> leaves <c>folder problem found</c> on the activity
/// trail, whose path is process-wide: the classes that REDIRECT it are all in
/// this collection, so a class writing trail lines from outside it can land
/// them in another class's scratch trail while that class is asserting on what
/// is in it.</para>
/// </summary>
[Collection(SharedActivityState.Name)]
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
        // The FOLDER-PROBLEM record, which the wrapper writes into the real
        // %LOCALAPPDATA% and this class cannot substitute away.
        //
        // The outcome record is redirected (see RunWrapper), but $healthDir and
        // $pendingDir resolve $env:LOCALAPPDATA at RUN time rather than being
        // baked, so the stub launcher's PLANTOIR_HEALTH: line really does land
        // in the teacher's own scheduled\folder-problems. It came out empty
        // only because one test in this class happens to call Take afterwards
        // and two others do not — so whether the machine is left clean depended
        // on which tests ran and in what order, which is not something to leave
        // to luck. Found by review 2026-09-09.
        try { ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder()); } catch { }
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

    /// <summary>The working folder a run is given — its records are filed under its id (#309).</summary>
    private string WorkFolder(string? name = null) => Path.Combine(_root, name ?? "work with spaces");

    private (int ExitCode, string Output) RunWrapper(string launcherBody, string? workFolderName = null,
                                                     string deployBody = "Write-Host 'DEPLOY RAN'\nexit 0",
                                                     string destinationType = "local_folder")
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
        File.WriteAllText(Path.Combine(work, "deploy.ps1"), deployBody);

        _lastTaskName = $"Plantoir-wraprun-{Guid.NewGuid():N}";
        string? script = TaskScheduling.WriteWrapperScript(
            _lastTaskName, work, Path.Combine(work, "deploy.ps1"),
            "ICS3U", 1, Path.Combine(work, "courses", "ICS3U"),
            Array.Empty<string>(),
            new[] { new CourseConfiguration.DeployDestination(destinationType, _root) },
            "");
        Assert.NotNull(script);

        var info = new ProcessStartInfo("powershell.exe")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            WorkingDirectory = work,
        };
        // #179: the wrapper's $healthDir and $pendingDir follow this in the CHILD only.
        info.Environment[TaskScheduling.TestStateDirVariable] = AppDataRoot.Current;
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
        ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder());

        RunWrapper(LauncherStub);
        var found = ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder());

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

    /// <summary>
    /// #395: an overnight Cloudflare publish whose project had to be made
    /// again leaves 'cloudflare project made again' on the trail, read from
    /// the captured deploy leg into the section's record. The exit code still
    /// decides the outcome (the leg runs captured, not plainly).
    /// </summary>
    [Fact]
    public void ACloudflareProjectRemadeOvernightReachesTheTrail()
    {
        if (!PowerShellIsAvailable) return;
        ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder());
        string trail = Path.Combine(_root, "trail.txt");
        Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(trail);
        try
        {
            var (exitCode, output) = RunWrapper("Write-Host 'Static build complete.'\nexit 0",
                deployBody: "Write-Host 'Made the project again.'\n" +
                            "Write-Host 'PLANTOIR_CLOUDFLARE_REMADE: ICS3U/1 ics3u-s1-2026 ics3u-s1-2026-x7.pages.dev'\n" +
                            "Write-Host 'DEPLOY RAN'\nexit 0",
                destinationType: "cloudflare_pages");
            Assert.Equal(0, exitCode);
            ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder());
            Assert.Contains("ICS3U/1 \u00b7 the Cloudflare project ics3u-s1-2026 was not in this Cloudflare account, so it was made again; " +
                            "the website is now at ics3u-s1-2026-x7.pages.dev", File.ReadAllText(trail));
        }
        finally { Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath); }
    }

    [Fact]
    public void ACloudflareLegThatFailsIsStillRecordedAsAFailure()
    {
        if (!PowerShellIsAvailable) return;
        ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder());
        RunWrapper("Write-Host 'Static build complete.'\nexit 0",
            deployBody: "Write-Host 'nope'\nexit 1", destinationType: "cloudflare_pages");

        var outcome = ScheduledPublishOutcome.ReadFrom(_root, "ICS3U", 1, WorkFolder());
        Assert.NotNull(outcome);
        Assert.Equal(ScheduledPublishOutcome.Kind.DidNotFinish, outcome!.Outcome);
        ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder());
    }

    [Fact]
    public void AGoodBuildDeploysAndLeavesNoRecord()
    {
        if (!PowerShellIsAvailable) return;

        ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder());

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
        Assert.Empty(ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder()));
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
        ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder("a folder with spaces"));

        var (exitCode, output) = RunWrapper(LauncherStub, "a folder with spaces");

        Assert.DoesNotContain("does not have a '.ps1' extension", output);
        Assert.Equal(1, exitCode);                       // the stub's own code, not a launch failure
        Assert.Single(ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder("a folder with spaces")));
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
        ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder());
    }

    // ---- #179: the wrapper's run-time folders stay out of the real state ---

    /// <summary>What a TEACHER's wrapper runs when the test variable is absent:
    /// the same LOCALAPPDATA folder as before #179.</summary>
    [Fact]
    public void WithoutTheTestVariableTheWrapperWritesWhereItAlwaysDid()
    {
        string expression = TaskScheduling.StateDirExpression(Path.Combine("scheduled", "folder-problems"));
        Assert.Contains("else { Join-Path $env:LOCALAPPDATA 'Plantoir" + Path.DirectorySeparatorChar + "scheduled" + Path.DirectorySeparatorChar + "folder-problems' }", expression);
        Assert.Contains("$env:TEMP", expression);
    }

    /// <summary>Run for real with the variable set: the run's folder-problem
    /// record lands in this test's scratch folder, and the teacher's real
    /// scheduled\folder-problems gains nothing named after this task.</summary>
    [Fact]
    public void ARunUnderTheSuiteLeavesTheRealFolderProblemsFolderAlone()
    {
        if (!PowerShellIsAvailable) return;
        string real = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir", "scheduled", "folder-problems");

        string record = TaskScheduling.HealthRecordName("ICS3U", 1, WorkFolder());
        var before = Directory.Exists(real) ? Directory.GetFiles(real).ToHashSet(StringComparer.OrdinalIgnoreCase) : new HashSet<string>();

        RunWrapper(LauncherStub);

        string[] leaked = (Directory.Exists(real) ? Directory.GetFiles(real) : Array.Empty<string>())
            .Where(f => !before.Contains(f))
            .Where(f => Path.GetFileName(f).Contains(record, StringComparison.OrdinalIgnoreCase)
                     || Path.GetFileName(f).StartsWith(_lastTaskName, StringComparison.OrdinalIgnoreCase))
            .ToArray();
        Assert.True(leaked.Length == 0, "The wrapper wrote into the teacher's real folder: " + string.Join(", ", leaked));
        Assert.True(ScheduledHealthFindings.Take("ICS3U", 1, WorkFolder()).Count > 0,
            "The run left no finding where the app (redirected) reads it, so this test proved nothing.");
    }
}
