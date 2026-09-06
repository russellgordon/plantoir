using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// What a scheduled deploy leaves behind about a course's folders, and what
/// the app does with it in the morning.
///
/// <para>The scheduled run publishes ANYWAY — a slightly inaccurate curriculum
/// map is a paper cut, a site update the teacher was counting on that silently
/// did not happen is not — so everything here is about the "afterwards", and
/// about the wrapper's own ordering, which has no runner behind it.</para>
/// </summary>
[Collection(SharedActivityState.Name)]
public class ScheduledHealthFindingsTests : IDisposable
{
    private readonly string _trailPath;
    private readonly string _dir;

    public ScheduledHealthFindingsTests()
    {
        _trailPath = Path.Combine(Path.GetTempPath(), $"plantoir-trail-{Guid.NewGuid():N}.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trailPath);
        _dir = Path.Combine(Path.GetTempPath(), $"plantoir-sched-health-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_dir);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trailPath); } catch { }
        try { Directory.Delete(_dir, recursive: true); } catch { }
    }

    private string Trail() => File.Exists(_trailPath) ? File.ReadAllText(_trailPath) : "";

    private static string MarkerLine(string name, string course = "ICS3U", int section = 1) =>
        $"{SiteHealthFinding.Marker} {{\"name\": \"{name}\", \"sentence\": \"A sentence.\", " +
        $"\"detail\": \"Some detail.\", \"fixable\": true, \"course\": \"{course}\", \"section\": {section}}}";

    private void WriteRecord(string course, int section, params string[] lines) =>
        File.WriteAllLines(Path.Combine(_dir, TaskScheduling.HealthRecordName(course, section)), lines);

    // ---- Reading it back -------------------------------------------------

    [Fact]
    public void ANightThatFoundNothingLeavesNothingToRead()
    {
        Assert.Empty(ScheduledHealthFindings.TakeFrom(_dir, "ICS3U", 1));
        Assert.Equal("", Trail());
    }

    [Fact]
    public void TheRecordIsReadWithTheSameParserALiveBuildUses()
    {
        WriteRecord("ICS3U", 1, MarkerLine("mediaFolderMissing"), MarkerLine("noGradedFolders"));

        var found = ScheduledHealthFindings.TakeFrom(_dir, "ICS3U", 1);

        Assert.Equal(new[] { "mediaFolderMissing", "noGradedFolders" },
                     found.Select(f => f.Name).ToArray());
    }

    [Fact]
    public void ItIsReportedOnceRatherThanEveryMorning()
    {
        WriteRecord("ICS3U", 1, MarkerLine("mediaFolderMissing"));

        Assert.Single(ScheduledHealthFindings.TakeFrom(_dir, "ICS3U", 1));
        Assert.Empty(ScheduledHealthFindings.TakeFrom(_dir, "ICS3U", 1));
    }

    [Fact]
    public void OneSectionsRecordIsNotAnothersSection()
    {
        WriteRecord("ICS3U", 2, MarkerLine("mediaFolderMissing", section: 2));

        Assert.Empty(ScheduledHealthFindings.TakeFrom(_dir, "ICS3U", 1));
        Assert.Single(ScheduledHealthFindings.TakeFrom(_dir, "ICS3U", 2));
    }

    [Fact]
    public void ARecordThatCannotBeReadIsConsumedRatherThanRetriedForever()
    {
        WriteRecord("ICS3U", 1, "this is not a finding at all");

        Assert.Empty(ScheduledHealthFindings.TakeFrom(_dir, "ICS3U", 1));
        Assert.False(File.Exists(Path.Combine(_dir, TaskScheduling.HealthRecordName("ICS3U", 1))));
    }

    [Fact]
    public void TheTrailDatesItToTheNightItHappenedNotToThisMorning()
    {
        // A trail that dated an overnight problem to whenever somebody opened
        // the app would file it under the wrong night — and this line is the
        // ONLY record of it, since the run happened with the app closed.
        string path = Path.Combine(_dir, TaskScheduling.HealthRecordName("ICS3U", 1));
        File.WriteAllLines(path, new[] { MarkerLine("mediaFolderMissing") });
        var lastNight = DateTime.Now.AddHours(-9);
        File.SetLastWriteTime(path, lastNight);

        ScheduledHealthFindings.TakeFrom(_dir, "ICS3U", 1);

        Assert.Contains(lastNight.ToString("yyyy-MM-dd HH:mm"), Trail());
        Assert.Contains("(mediaFolderMissing)", Trail());
        Assert.Contains("ICS3U/1", Trail());
    }

    [Fact]
    public void TheWriterAndTheReaderAgreeOnTheFilename()
    {
        // The generated wrapper and this reader both call HealthRecordName.
        // A mismatch would fail in the quietest way available: written
        // faithfully every night, read never.
        Assert.EndsWith(TaskScheduling.HealthRecordName("ICS3U", 3),
                        ScheduledHealthFindings.SentinelPath("ICS3U", 3));
    }

    // ---- The wrapper's own ordering --------------------------------------

    private string GenerateWrapper()
    {
        string folder = Path.Combine(_dir, "work");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "deploy.ps1"), "# stub");
        File.WriteAllText(Path.Combine(folder, "preview.ps1"), "# stub");
        string? path = TaskScheduling.WriteWrapperScript(
            $"Plantoir-test-{Guid.NewGuid():N}", folder, Path.Combine(folder, "deploy.ps1"),
            "ICS3U", 1, Path.Combine(folder, "courses", "ICS3U"),
            Array.Empty<string>(),
            new[] { new CourseConfiguration.DeployDestination("local_folder", _dir) },
            "");
        Assert.NotNull(path);
        string script = File.ReadAllText(path!);
        try { File.Delete(path!); } catch { }
        return script;
    }

    [Fact]
    public void TheHealthScanRunsBeforeTheBuildFailureGuard()
    {
        // THE test in this class. Since 2026-09-01 a section with no index.md
        // exits NON-ZERO from --build-only, and that is precisely the run whose
        // findings the teacher most needs in the morning. A scan placed after
        // the guard would say nothing about the one failure that explains
        // itself — and nothing would notice, because the wrapper has no runner
        // and is executed at 6 a.m. with nobody watching.
        string script = GenerateWrapper();

        // Anchored on the COMMAND, not on the marker string: the marker also
        // appears in the comment above the build, which sits before the guard
        // whatever the real ordering is. Written the naive way first, and a
        // mutation — moving the guard above the scan — passed, which is how
        // this was caught.
        int scan = script.IndexOf("Select-String -LiteralPath $buildLog", StringComparison.Ordinal);
        int guard = script.IndexOf("if ($buildExit -ne 0)", StringComparison.Ordinal);

        Assert.True(scan >= 0, "the wrapper does not scan for findings at all");
        Assert.True(guard >= 0, "the wrapper does not guard on the build's exit code");
        Assert.True(scan < guard, "the scan must come BEFORE the build-failure guard");
    }

    [Fact]
    public void TheBuildsExitCodeIsSavedBeforeAnythingElseRuns()
    {
        // Everything between the build and the guard runs commands of its own,
        // and $LASTEXITCODE is whatever ran last. The guard that decides
        // whether anything is published must test THIS build's code.
        string script = GenerateWrapper();

        int build = script.IndexOf("--build-only", StringComparison.Ordinal);
        int save = script.IndexOf("$buildExit = $LASTEXITCODE", StringComparison.Ordinal);
        int scan = script.IndexOf("Select-String", StringComparison.Ordinal);

        Assert.True(build >= 0 && save > build, "the exit code is not saved after the build");
        Assert.True(save < scan, "the exit code must be saved BEFORE the scan runs its own commands");
        // And nothing may re-read the raw $LASTEXITCODE to make that decision.
        Assert.DoesNotContain("if ($LASTEXITCODE -ne 0) {\n  Write-Host 'Could not build", script);
    }

    [Fact]
    public void ACleanRunClearsWhatAnEarlierRunLeft()
    {
        // A problem the teacher has since put right must stop being reported.
        string script = GenerateWrapper();
        Assert.Contains("Remove-Item -LiteralPath $healthFile", script);
    }

    [Fact]
    public void ACaptureThatCannotBeSetUpStillPublishes()
    {
        // Losing the findings is a pity; losing the publish is not acceptable.
        string script = GenerateWrapper();

        Assert.Contains("if ($buildLog) {", script);
        Assert.Contains("} else {", script);
        // The plain, uncaptured invocation is present as the fallback.
        Assert.Contains("--build-only\n", script.Replace("\r\n", "\n"));
    }

    [Fact]
    public void NoJsonIsInterpretedInPowerShell()
    {
        // The lines are copied verbatim and parsed in C#. A shell that parsed
        // them would be a second implementation to keep in step.
        string script = GenerateWrapper();

        Assert.Contains("-SimpleMatch 'PLANTOIR_HEALTH:'", script);
        Assert.DoesNotContain("ConvertFrom-Json", script);
    }
}
