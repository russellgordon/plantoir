using System.Diagnostics;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A publish set to happen on its own that stopped because it needed an answer
/// — the record, and the wrapper that writes it.
///
/// <para>The failure being closed (GitHub issue #92): a scheduled deploy runs
/// at half six with the app closed, so a question it could not ask is asked of
/// nobody. Before <c>--non-interactive</c> it either WAITED — measured at 45
/// minutes, the launcher and its Python child still at the prompt when they
/// were swept up — or took a default silently and published the teacher's site
/// to an address nobody chose. Neither said anything, ever.</para>
/// </summary>
public class ScheduledPublishQuestionTests : IDisposable
{
    private readonly string _dir =
        Path.Combine(Path.GetTempPath(), $"plantoir-unanswered-{Guid.NewGuid():N}");

    /// <summary>
    /// Wrapper scripts these tests generated, so they can be swept.
    /// </summary>
    /// <remarks>
    /// <b>Not tidiness.</b> <c>WriteWrapperScript</c> writes into
    /// <c>ScheduledScriptsDirectory()</c>, which resolves through
    /// <c>AppDataRoot</c> and is therefore the teacher's REAL
    /// <c>%LOCALAPPDATA%\Plantoir\scheduled\</c> — the same folder their own
    /// scheduled publishes live in. A first draft of this class left one
    /// script per test per run there; twenty had accumulated beside a real
    /// <c>Plantoir-deploy-ICD2O-section-1.ps1</c> before anybody looked.
    /// <c>ScheduledHealthFindingsTests</c> deletes its own for the same reason.
    /// </remarks>
    private readonly List<string> _wrappers = new();

    public ScheduledPublishQuestionTests() => Directory.CreateDirectory(_dir);

    public void Dispose()
    {
        foreach (string wrapper in _wrappers)
            try { File.Delete(wrapper); } catch { }
        try { Directory.Delete(_dir, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    // ---- The record ------------------------------------------------------

    [Fact]
    public void NothingWaitingIsNotAProblem()
    {
        Assert.Null(ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1));
    }

    [Fact]
    public void WhatWasRecordedIsWhatComesBack()
    {
        ScheduledPublishQuestion.Record(_dir, "ICS3U", 1, "Netlify");

        var stopped = ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1);

        Assert.NotNull(stopped);
        Assert.Equal("Netlify", stopped!.Destination);
    }

    /// <summary>
    /// Consumed as it is read, so a teacher is told once rather than every time
    /// they open the app.
    /// </summary>
    [Fact]
    public void ARecordIsReportedOnceAndThenGone()
    {
        ScheduledPublishQuestion.Record(_dir, "ICS3U", 1, "Netlify");

        Assert.NotNull(ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1));
        Assert.Null(ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1));
    }

    /// <summary>
    /// One section's record is not another's. The two are told apart by the
    /// filename, and a name that ignored the section would have every section
    /// of a course reading the first one's answer.
    /// </summary>
    [Fact]
    public void RecordsAreKeptPerSection()
    {
        ScheduledPublishQuestion.Record(_dir, "ICS3U", 1, "Netlify");

        Assert.Null(ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 2));
        Assert.Null(ScheduledPublishQuestion.TakeFrom(_dir, "MCV4U", 1));
        Assert.NotNull(ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1));
    }

    /// <summary>
    /// The moment reported is when the RUN wrote it, not when the app read it.
    /// </summary>
    /// <remarks>
    /// The trail line is dated from this. A trail that dated an overnight
    /// problem to whenever somebody happened to open the app would file it
    /// under the wrong night, which is the one thing a trail is read to settle.
    /// </remarks>
    [Fact]
    public void TheMomentIsWhenTheRunWroteIt()
    {
        ScheduledPublishQuestion.Record(_dir, "ICS3U", 1, "Netlify");
        var lastNight = DateTime.Now.AddHours(-9);
        File.SetLastWriteTime(
            Path.Combine(_dir, TaskScheduling.HealthRecordName("ICS3U", 1)), lastNight);

        var stopped = ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1);

        Assert.NotNull(stopped);
        Assert.True((lastNight - stopped!.When).Duration() < TimeSpan.FromSeconds(2),
            $"Expected roughly {lastNight}, got {stopped.When}.");
    }

    /// <summary>A run that gets through clears it, so an answered question stops being reported.</summary>
    [Fact]
    public void ClearingThrowsTheRecordAway()
    {
        ScheduledPublishQuestion.Record(_dir, "ICS3U", 1, "Netlify");
        ScheduledPublishQuestion.Clear(_dir, "ICS3U", 1);
        Assert.Null(ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1));
    }

    /// <summary>Clearing what is not there is ordinary, not an error.</summary>
    [Fact]
    public void ClearingNothingIsFine()
    {
        ScheduledPublishQuestion.Clear(_dir, "ICS3U", 1);
        ScheduledPublishQuestion.Clear(Path.Combine(_dir, "not-made"), "ICS3U", 1);
    }

    /// <summary>
    /// An empty record is consumed rather than reported.
    /// </summary>
    /// <remarks>
    /// Reporting it would put a sentence with a blank where the destination
    /// goes in front of a teacher; leaving it on disk would re-read it every
    /// time the app opened, for ever.
    /// </remarks>
    [Fact]
    public void AnEmptyRecordIsThrownAwayRatherThanReported()
    {
        string path = Path.Combine(_dir, TaskScheduling.HealthRecordName("ICS3U", 1));
        File.WriteAllText(path, "   \r\n");

        Assert.Null(ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1));
        Assert.False(File.Exists(path), "An unusable record must not be re-read every morning.");
    }

    /// <summary>
    /// The sentence names the section and the destination, and says what to do.
    /// </summary>
    /// <remarks>
    /// No machinery in it: not the exit code, not the flag, not the launcher.
    /// A teacher reading this at 8 a.m. needs to know which section did not go
    /// out and what to do about it before tonight.
    /// </remarks>
    [Fact]
    public void TheSentenceNamesTheSectionTheDestinationAndTheWayOut()
    {
        string said = ScheduledPublishQuestion.Sentence("ICS3U", 2, "Netlify");

        Assert.Contains("ICS3U", said);
        Assert.Contains("Section 2", said);
        Assert.Contains("Netlify", said);
        Assert.Contains("Publish this section once yourself", said);
        foreach (string machinery in new[]
                 { "exit", "--non-interactive", "deploy.py", "deploy.ps1", "stdin", "code 3" })
            Assert.DoesNotContain(machinery, said, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// A record put back is readable again, and keeps its ORIGINAL moment.
    /// </summary>
    /// <remarks>
    /// Consuming is not delivering: <see cref="ScheduledPublishQuestion.Take"/>
    /// deletes as it reads, so a reader that then cannot get the sentence on
    /// screen — WinUI allows one dialog at a time, and a folder-problem dialog
    /// may already be up — has destroyed the only thing that would have told
    /// the teacher tomorrow. The moment matters as much as the fact: the trail
    /// line and the sentence are dated from it, so a record put back with
    /// today's timestamp would file last night's problem under this morning.
    /// </remarks>
    [Fact]
    public void ARecordPutBackKeepsItsOriginalMoment()
    {
        ScheduledPublishQuestion.Record(_dir, "ICS3U", 1, "Netlify");
        var lastNight = DateTime.Now.AddHours(-9);
        File.SetLastWriteTime(Path.Combine(_dir, TaskScheduling.HealthRecordName("ICS3U", 1)), lastNight);

        var stopped = ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1);
        Assert.NotNull(stopped);
        Assert.Null(ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1));   // really consumed

        ScheduledPublishQuestion.PutBackIn(_dir, "ICS3U", 1, stopped!);

        var again = ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1);
        Assert.NotNull(again);
        Assert.Equal("Netlify", again!.Destination);
        Assert.True((lastNight - again.When).Duration() < TimeSpan.FromSeconds(2),
            $"Put back with {again.When}, which would file last night's problem under the wrong night.");
    }

    // ---- The wrapper the scheduler runs ----------------------------------

    /// <summary>
    /// Every deploy leg is passed the flag.
    /// </summary>
    /// <remarks>
    /// This is the whole fix. Without it on the command line, the leg reaches
    /// <c>deploy.py</c>'s site-name question and either blocks for ever or
    /// takes its default and publishes somewhere nobody chose.
    /// </remarks>
    [Fact]
    public void EveryDeployLegIsToldNobodyIsThere()
    {
        string script = File.ReadAllText(GenerateWrapper(
            new CourseConfiguration.DeployDestination("netlify", ""),
            new CourseConfiguration.DeployDestination("local_folder", _dir)));

        var legs = script.Split('\n')
            .Where(line => line.TrimStart().StartsWith("& ", StringComparison.Ordinal)
                           && line.Contains("deploy.ps1", StringComparison.OrdinalIgnoreCase))
            .ToList();

        Assert.Equal(2, legs.Count);
        foreach (string leg in legs)
            Assert.EndsWith("--non-interactive", leg.TrimEnd());
    }

    /// <summary>
    /// The record is cleared AFTER every destination has run, not inside the
    /// loop.
    /// </summary>
    /// <remarks>
    /// The bug this pins, found by writing it: a course publishing to two
    /// places whose Netlify leg stopped for a question and whose folder leg
    /// then succeeded would have had the note deleted by the second leg, and
    /// the teacher would never have been told why the first one did not go out.
    /// Asserted by POSITION, because that is what was wrong.
    /// </remarks>
    [Fact]
    public void TheRecordIsClearedOnlyAfterEveryDestinationHasRun()
    {
        string script = File.ReadAllText(GenerateWrapper(
            new CourseConfiguration.DeployDestination("netlify", ""),
            new CourseConfiguration.DeployDestination("local_folder", _dir)));

        int lastLeg = script.LastIndexOf("--non-interactive", StringComparison.Ordinal);
        int clear = script.IndexOf("Remove-Item -LiteralPath (Join-Path", StringComparison.Ordinal);

        Assert.True(clear > lastLeg,
            "The record must be cleared after the last destination, or a later leg that " +
            "succeeds deletes the note an earlier leg left.");
        Assert.Contains("if (-not $neededAnAnswer) {", script);
    }

    /// <summary>Exit 3 is told apart from every other non-zero code.</summary>
    [Fact]
    public void TheWrapperTellsNeedingAnAnswerApartFromFailing()
    {
        string script = File.ReadAllText(
            GenerateWrapper(new CourseConfiguration.DeployDestination("netlify", "")));

        Assert.Contains("if ($LASTEXITCODE -eq 3) {", script);
        Assert.Contains("} elseif ($LASTEXITCODE -ne 0) {", script);
    }

    // ---- Running the generated wrapper for real --------------------------

    /// <summary>
    /// The generated PowerShell really does write the record when a leg exits
    /// 3, and really does leave it alone when a later leg succeeds.
    /// </summary>
    /// <remarks>
    /// <para>Asserting the script's TEXT cannot see whether
    /// <c>$neededAnAnswer</c> survives the loop, whether <c>Set-Content</c> is
    /// in a scope that can see it, or whether the <c>try/catch</c> swallows the
    /// write. The wrapper has no runner — it is executed at 6 a.m. by Task
    /// Scheduler with nobody watching — so running it here is the only place
    /// any of that is checked.</para>
    ///
    /// <para><b>The baked directory is substituted before running.</b>
    /// <c>WriteWrapperScript</c> writes <c>AppDataRoot</c>'s real path into the
    /// script, and <c>AppDataRoot.RedirectTo</c> is process-wide with no way
    /// back — so redirecting it here would leave every later test in this
    /// process pointed at a scratch folder. Substituting one literal is
    /// contained, and what is under test is the branch structure rather than
    /// the path.</para>
    /// </remarks>
    [Fact]
    public void ARunThatNeededAnAnswerLeavesTheRecordEvenIfALaterDestinationSucceeds()
    {
        if (!PowerShellIsAvailable) return;

        string work = Path.Combine(_dir, "work with spaces");
        Directory.CreateDirectory(work);
        // The build must SUCCEED, or the wrapper's own guard exits before any
        // deploy leg runs and this would pass having tested nothing.
        File.WriteAllText(Path.Combine(work, "preview.ps1"), "Write-Host 'built'\nexit 0");
        // Netlify needs an answer; the folder leg then succeeds. That order is
        // the whole point.
        File.WriteAllText(Path.Combine(work, "deploy.ps1"), """
            if ($args -contains '--target') { Write-Host 'needs an answer'; exit 3 }
            Write-Host 'published to the folder'
            exit 0
            """);

        string script = GenerateWrapper(work,
            new CourseConfiguration.DeployDestination("cloudflare_pages", ""),
            new CourseConfiguration.DeployDestination("local_folder", _dir));
        string runnable = Path.Combine(_dir, "runnable.ps1");
        File.WriteAllText(runnable,
            File.ReadAllText(script).Replace(ScheduledPublishQuestion.Directory(), _dir));

        Run(runnable, work);

        var stopped = ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1);
        Assert.NotNull(stopped);
        Assert.Contains("Cloudflare", stopped!.Destination, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>A run where everything got through clears a record left by a previous night.</summary>
    [Fact]
    public void ARunThatGetsThroughClearsLastNightsRecord()
    {
        if (!PowerShellIsAvailable) return;

        ScheduledPublishQuestion.Record(_dir, "ICS3U", 1, "Netlify");

        string work = Path.Combine(_dir, "work ok");
        Directory.CreateDirectory(work);
        File.WriteAllText(Path.Combine(work, "preview.ps1"), "Write-Host 'built'\nexit 0");
        File.WriteAllText(Path.Combine(work, "deploy.ps1"), "Write-Host 'published'\nexit 0");

        string script = GenerateWrapper(work,
            new CourseConfiguration.DeployDestination("local_folder", _dir));
        string runnable = Path.Combine(_dir, "runnable-ok.ps1");
        File.WriteAllText(runnable,
            File.ReadAllText(script).Replace(ScheduledPublishQuestion.Directory(), _dir));

        Run(runnable, work);

        Assert.Null(ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1));
    }

    /// <summary>
    /// A run where a leg failed ORDINARILY does not clear last night's record.
    /// </summary>
    /// <remarks>
    /// Found by review, and it is the same mistake as the loop one made
    /// smaller. The clear used to be keyed on "nothing needed an answer",
    /// which is true of a run where every leg failed with exit 1 — so Monday
    /// stops for a question and leaves a note, Tuesday the token is revoked
    /// and every leg fails, Monday's note is deleted, and since nothing yet
    /// records an ordinary scheduled failure the teacher is told about neither
    /// night. Keyed on <c>$allSucceeded</c> now, which is the condition every
    /// sentence describing this already used.
    ///
    /// <para>Neither of the other two run tests can tell the two conditions
    /// apart: <c>if ($allSucceeded)</c> and <c>if (-not $neededAnAnswer)</c>
    /// both pass them.</para>
    /// </remarks>
    [Fact]
    public void AnOrdinaryFailureDoesNotClearLastNightsRecord()
    {
        if (!PowerShellIsAvailable) return;

        ScheduledPublishQuestion.Record(_dir, "ICS3U", 1, "Netlify");

        string work = Path.Combine(_dir, "work failing");
        Directory.CreateDirectory(work);
        File.WriteAllText(Path.Combine(work, "preview.ps1"), "Write-Host 'built'\nexit 0");
        // Exit 1, not 3: the token was revoked, the upload failed — an ordinary
        // failure, with nothing to do with a question.
        File.WriteAllText(Path.Combine(work, "deploy.ps1"), "Write-Host 'upload failed'\nexit 1");

        string script = GenerateWrapper(work,
            new CourseConfiguration.DeployDestination("local_folder", _dir));
        string runnable = Path.Combine(_dir, "runnable-failing.ps1");
        File.WriteAllText(runnable,
            File.ReadAllText(script).Replace(ScheduledPublishQuestion.Directory(), _dir));

        Run(runnable, work);

        Assert.NotNull(ScheduledPublishQuestion.TakeFrom(_dir, "ICS3U", 1));
    }

    // ---- Fixture ---------------------------------------------------------

    private static bool PowerShellIsAvailable =>
        OperatingSystem.IsWindows() && File.Exists(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "powershell.exe"));

    private string GenerateWrapper(params CourseConfiguration.DeployDestination[] destinations) =>
        GenerateWrapper(StubWorkFolder(), destinations);

    private string StubWorkFolder()
    {
        string folder = Path.Combine(_dir, "stub");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "deploy.ps1"), "# stub");
        File.WriteAllText(Path.Combine(folder, "preview.ps1"), "# stub");
        return folder;
    }

    /// <summary>The generated script's PATH, so a caller can read or rewrite it.</summary>
    private string GenerateWrapper(string folder, params CourseConfiguration.DeployDestination[] destinations)
    {
        string? path = TaskScheduling.WriteWrapperScript(
            $"Plantoir-unanswered-{Guid.NewGuid():N}", folder, Path.Combine(folder, "deploy.ps1"),
            "ICS3U", 1, Path.Combine(folder, "courses", "ICS3U"),
            Array.Empty<string>(), destinations, "");
        Assert.NotNull(path);
        _wrappers.Add(path!);
        return path!;
    }

    private static void Run(string script, string workingDirectory)
    {
        var info = new ProcessStartInfo("powershell.exe")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            WorkingDirectory = workingDirectory,
        };
        foreach (string a in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script })
            info.ArgumentList.Add(a);

        using var process = Process.Start(info)!;
        process.StandardOutput.ReadToEnd();
        process.StandardError.ReadToEnd();
        process.WaitForExit(120_000);
    }
}
