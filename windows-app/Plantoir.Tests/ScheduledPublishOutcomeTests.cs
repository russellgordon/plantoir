using System.Diagnostics;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// How a publish set to happen on its own turned out — the record, the
/// sentences, and the wrapper that writes them.
///
/// <para>The failure being closed (GitHub issues #92 and #130): a scheduled
/// deploy runs at half six with the app closed, so nothing it does is seen by
/// anybody. Before <c>--non-interactive</c> a question it could not ask either
/// made it WAIT — measured at 45 minutes, the launcher and its Python child
/// still at the prompt when they were swept up — or took a default silently and
/// published the teacher's site to an address nobody chose. Neither said
/// anything, ever. Nor did an ordinary failure, and nor did a run that worked:
/// read the same way round, a scheduled publish that leaves NO trace cannot be
/// told from one that never happened.</para>
/// </summary>
public class ScheduledPublishOutcomeTests : IDisposable
{
    private readonly string _dir =
        Path.Combine(Path.GetTempPath(), $"plantoir-outcome-{Guid.NewGuid():N}");

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

    public ScheduledPublishOutcomeTests() => Directory.CreateDirectory(_dir);

    public void Dispose()
    {
        foreach (string wrapper in _wrappers)
            try { File.Delete(wrapper); } catch { }
        try { Directory.Delete(_dir, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    private static string RecordPath(string dir, string course, int section) =>
        Path.Combine(dir, TaskScheduling.HealthRecordName(course, section));

    // ---- The record ------------------------------------------------------

    [Fact]
    public void NothingWaitingIsNotAProblem()
    {
        Assert.Null(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1));
    }

    [Theory]
    [InlineData(ScheduledPublishOutcome.Kind.NeededAnAnswer)]
    [InlineData(ScheduledPublishOutcome.Kind.DidNotFinish)]
    [InlineData(ScheduledPublishOutcome.Kind.Succeeded)]
    public void WhatWasRecordedIsWhatComesBack(ScheduledPublishOutcome.Kind kind)
    {
        ScheduledPublishOutcome.Record(_dir, "ICS3U", 1, kind, "Netlify");

        var result = ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1);

        Assert.NotNull(result);
        Assert.Equal(kind, result!.Outcome);
        Assert.Equal("Netlify", result.Destination);
    }

    /// <summary>
    /// A build that stopped for a question names no destination, and is still
    /// reportable.
    /// </summary>
    /// <remarks>
    /// The one kind with nothing to name: the build runs before any destination
    /// is contacted. A reader that threw away a record with an empty second
    /// line — which is right for the two destination-shaped failures, whose
    /// sentence has a hole in it without one — would silently swallow exactly
    /// this case.
    /// </remarks>
    [Fact]
    public void ABuildThatNeededAnAnswerIsReportedWithNoDestination()
    {
        ScheduledPublishOutcome.Record(
            _dir, "ICS3U", 1, ScheduledPublishOutcome.Kind.BuildNeededAnAnswer, "");

        var result = ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1);

        Assert.NotNull(result);
        Assert.Equal(ScheduledPublishOutcome.Kind.BuildNeededAnAnswer, result!.Outcome);
        Assert.Equal("", result.Destination);
    }

    /// <summary>
    /// Several destinations come back as a sentence, not as a list.
    /// </summary>
    /// <remarks>
    /// The wrapper writes them separated by "|" and the APP joins, because
    /// <c>MultiDestinationDeployRunner.JoinedWithAnd</c> is where this product
    /// already knows how to say a list out loud — the Deploy button uses it. A
    /// second copy of that rule inside generated PowerShell would be a copy
    /// nothing tests.
    /// </remarks>
    [Fact]
    public void SeveralDestinationsAreJoinedTheWayATeacherWouldSayThem()
    {
        ScheduledPublishOutcome.Record(
            _dir, "ICS3U", 1, ScheduledPublishOutcome.Kind.Succeeded,
            "Netlify|Cloudflare Pages");

        var result = ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1);

        Assert.NotNull(result);
        Assert.Equal("Netlify and Cloudflare Pages", result!.Destination);
    }

    /// <summary>
    /// A one-line record — the shape written before 2026-09-09 — is still read,
    /// as the question it was.
    /// </summary>
    /// <remarks>
    /// <b>This is not politeness to old code.</b> A task SCHEDULED before that
    /// date points at a wrapper <c>.ps1</c> already on disk, and nothing
    /// rewrites it until the teacher schedules that section again. Reading only
    /// the new shape would make the first overnight run after an update silent
    /// — which is the exact bug this feature exists to close, reintroduced by
    /// the fix for it.
    /// </remarks>
    [Fact]
    public void TheOneLineRecordWrittenByAnOlderWrapperIsStillUnderstood()
    {
        File.WriteAllText(RecordPath(_dir, "ICS3U", 1), "Netlify" + Environment.NewLine);

        var result = ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1);

        Assert.NotNull(result);
        Assert.Equal(ScheduledPublishOutcome.Kind.NeededAnAnswer, result!.Outcome);
        Assert.Equal("Netlify", result.Destination);
    }

    /// <summary>
    /// The record STANDS until something clears it, rather than being consumed
    /// by whoever reads it first.
    /// </summary>
    /// <remarks>
    /// <para>It used to be deleted as it was read, so the teacher was told
    /// once. That is right for a dialog and wrong for a notice inside the
    /// section, and it had a cost that only became obvious once Dismiss
    /// existed: it made "not shown" and "shown and read" the same state, so a
    /// reader that then could not get the sentence on screen had destroyed the
    /// only thing that would have told the teacher tomorrow.</para>
    ///
    /// <para>It also has to survive being read TWICE on one launch, which it
    /// now is: the sidebar reads it to decide the warning badge, and the
    /// section reads it to show the sentence. Under the old rule whichever ran
    /// first would have eaten it.</para>
    /// </remarks>
    [Fact]
    public void ARecordStandsUntilSomethingClearsIt()
    {
        ScheduledPublishOutcome.Record(
            _dir, "ICS3U", 1, ScheduledPublishOutcome.Kind.NeededAnAnswer, "Netlify");

        Assert.NotNull(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1));
        Assert.NotNull(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1));
        Assert.NotNull(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1));
    }

    /// <summary>
    /// One section's record is not another's. The two are told apart by the
    /// filename, and a name that ignored the section would have every section
    /// of a course reading the first one's answer.
    /// </summary>
    [Fact]
    public void RecordsAreKeptPerSection()
    {
        ScheduledPublishOutcome.Record(
            _dir, "ICS3U", 1, ScheduledPublishOutcome.Kind.NeededAnAnswer, "Netlify");

        Assert.Null(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 2));
        Assert.Null(ScheduledPublishOutcome.ReadFrom(_dir, "MCV4U", 1));
        Assert.NotNull(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1));
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
        ScheduledPublishOutcome.Record(
            _dir, "ICS3U", 1, ScheduledPublishOutcome.Kind.NeededAnAnswer, "Netlify");
        var lastNight = DateTime.Now.AddHours(-9);
        File.SetLastWriteTime(RecordPath(_dir, "ICS3U", 1), lastNight);

        var result = ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1);

        Assert.NotNull(result);
        Assert.True((lastNight - result!.When).Duration() < TimeSpan.FromSeconds(2),
            $"Expected roughly {lastNight}, got {result.When}.");
    }

    /// <summary>A run that gets through clears it, so an answered question stops being reported.</summary>
    [Fact]
    public void ClearingThrowsTheRecordAway()
    {
        ScheduledPublishOutcome.Record(
            _dir, "ICS3U", 1, ScheduledPublishOutcome.Kind.NeededAnAnswer, "Netlify");
        ScheduledPublishOutcome.Clear(_dir, "ICS3U", 1);
        Assert.Null(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1));
    }

    /// <summary>Clearing what is not there is ordinary, not an error.</summary>
    [Fact]
    public void ClearingNothingIsFine()
    {
        ScheduledPublishOutcome.Clear(_dir, "ICS3U", 1);
        ScheduledPublishOutcome.Clear(Path.Combine(_dir, "not-made"), "ICS3U", 1);
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
        string path = RecordPath(_dir, "ICS3U", 1);
        File.WriteAllText(path, "   \r\n");

        Assert.Null(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1));
        Assert.False(File.Exists(path), "An unusable record must not be re-read every morning.");
    }

    /// <summary>
    /// A destination-shaped failure with no destination is unusable, and is
    /// thrown away rather than shown with a hole in the sentence.
    /// </summary>
    [Fact]
    public void AFailureWithNothingToNameIsThrownAway()
    {
        string path = RecordPath(_dir, "ICS3U", 1);
        File.WriteAllText(path, "needed-an-answer\r\n\r\n");

        Assert.Null(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1));
        Assert.False(File.Exists(path));
    }

    /// <summary>
    /// Dismiss throws the record away, and the mark saying its trail line has
    /// been written with it.
    /// </summary>
    /// <remarks>
    /// The sidecar has to go too. Left behind, the NEXT run's record — written
    /// within the same second, as it would be if a teacher dismissed one and
    /// re-ran the publish immediately — would be read as already said, and that
    /// night would get no trail line at all.
    /// </remarks>
    [Fact]
    public void DismissingTakesTheRecordAndTheNotedMarkWithIt()
    {
        ScheduledPublishOutcome.Record(
            _dir, "ICS3U", 1, ScheduledPublishOutcome.Kind.DidNotFinish, "Netlify");
        ScheduledPublishOutcome.NoteFinishedRunsOnTrailIn(_dir);

        string record = RecordPath(_dir, "ICS3U", 1);
        Assert.True(File.Exists(record + ".noted"), "the sweep did not mark it as said");

        ScheduledPublishOutcome.Clear(_dir, "ICS3U", 1);

        Assert.Null(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1));
        Assert.False(File.Exists(record + ".noted"));
    }

    // ---- The sentences, against the contract -----------------------------

    /// <summary>
    /// Every sentence is the contract's own, with the course, the section and
    /// the destination filled in.
    /// </summary>
    /// <remarks>
    /// Read from <c>shared-rules.json</c> rather than retyped, which is the
    /// whole reason that file exists: a literal here is the copy that keeps
    /// passing after the product's words change.
    /// </remarks>
    [Theory]
    [InlineData(ScheduledPublishOutcome.Kind.NeededAnAnswer, "neededAnAnswer", "Netlify")]
    [InlineData(ScheduledPublishOutcome.Kind.BuildNeededAnAnswer, "buildNeededAnAnswer", "")]
    [InlineData(ScheduledPublishOutcome.Kind.DidNotFinish, "didNotFinish", "Netlify")]
    [InlineData(ScheduledPublishOutcome.Kind.Succeeded, "succeeded", "Netlify")]
    public void EachSentenceIsTheContractsOwn(
        ScheduledPublishOutcome.Kind kind, string key, string destination)
    {
        var sentences = ContractLoader.LoadJson("shared-rules.json")
            ["scheduledPublishStopped"]!["sentences"]!;

        string expected = sentences[key]!.ToString()
            .Replace("{course}", "ICS3U")
            .Replace("{section}", "2")
            .Replace("{destination}", destination);

        string said = ScheduledPublishOutcome.Sentence(
            "ICS3U", 2, new ScheduledPublishOutcome.Result(kind, destination, DateTime.Now, "ICS3U", 2));

        Assert.Equal(expected, said);
    }

    /// <summary>
    /// Every kind the contract names is one this app can record, and the other
    /// way round.
    /// </summary>
    /// <remarks>
    /// The pairing that makes the contract load-bearing rather than
    /// descriptive: a kind added on the mac fails here by name, and one dropped
    /// here fails too. <c>buildNeededAnAnswer</c> went the other way — proposed
    /// from this side on 2026-09-09, so the mac is red on it until they adopt
    /// it (GitHub issue #133), which is the mechanism working.
    /// </remarks>
    [Fact]
    public void TheKindsAreExactlyTheOnesTheContractNames()
    {
        var kinds = ContractLoader.LoadJson("shared-rules.json")
            ["scheduledPublishStopped"]!["kinds"]!.AsObject();

        var named = kinds.Select(pair => pair.Key).ToHashSet(StringComparer.Ordinal);
        var served = Enum.GetValues<ScheduledPublishOutcome.Kind>()
            // The contract's keys are lower-camel; the file format's words are
            // hyphenated and the enum's are Pascal. Compared on the CONTRACT's
            // spelling, since that is the shared one.
            .Select(kind => char.ToLowerInvariant(kind.ToString()[0]) + kind.ToString()[1..])
            .ToHashSet(StringComparer.Ordinal);

        Assert.Equal(named, served);
    }

    /// <summary>
    /// The two failures ask for the teacher's attention; a success does not.
    /// </summary>
    /// <remarks>
    /// Deliberate asymmetry, recorded in the contract as
    /// <c>scheduledPublishStopped.attention</c>: a teacher who does not know
    /// WHICH section failed cannot open the right one, so a failure gets a
    /// warning beside its section as well as the sentence inside it — while a
    /// badge on every section that published fine overnight is a badge nobody
    /// reads by Wednesday.
    /// </remarks>
    [Fact]
    public void OnlyAFailureAsksForTheTeachersAttention()
    {
        Assert.True(ScheduledPublishOutcome.NeedsAttention(ScheduledPublishOutcome.Kind.NeededAnAnswer));
        Assert.True(ScheduledPublishOutcome.NeedsAttention(ScheduledPublishOutcome.Kind.BuildNeededAnAnswer));
        Assert.True(ScheduledPublishOutcome.NeedsAttention(ScheduledPublishOutcome.Kind.DidNotFinish));
        Assert.False(ScheduledPublishOutcome.NeedsAttention(ScheduledPublishOutcome.Kind.Succeeded));
    }

    /// <summary>
    /// Each kind leaves the trail event the contract names for it.
    /// </summary>
    /// <remarks>
    /// A build that stopped for a question is filed under "needed an answer"
    /// like any other: the event is about a question going unasked, which is
    /// what happened, and a fourth event would put a distinction on the trail
    /// that means nothing to the person reading it.
    /// </remarks>
    [Fact]
    public void EachKindLeavesTheTrailEventTheContractNames()
    {
        Assert.Equal("scheduled publish needed an answer",
            ActivityTrail.KeyFor(ScheduledPublishOutcome.EventFor(
                ScheduledPublishOutcome.Kind.NeededAnAnswer)));
        Assert.Equal("scheduled publish needed an answer",
            ActivityTrail.KeyFor(ScheduledPublishOutcome.EventFor(
                ScheduledPublishOutcome.Kind.BuildNeededAnAnswer)));
        Assert.Equal("scheduled publish did not finish",
            ActivityTrail.KeyFor(ScheduledPublishOutcome.EventFor(
                ScheduledPublishOutcome.Kind.DidNotFinish)));
        Assert.Equal("scheduled publish finished",
            ActivityTrail.KeyFor(ScheduledPublishOutcome.EventFor(
                ScheduledPublishOutcome.Kind.Succeeded)));
    }

    /// <summary>
    /// No sentence names the machinery a teacher never asked about.
    /// </summary>
    [Theory]
    [InlineData(ScheduledPublishOutcome.Kind.NeededAnAnswer)]
    [InlineData(ScheduledPublishOutcome.Kind.BuildNeededAnAnswer)]
    [InlineData(ScheduledPublishOutcome.Kind.DidNotFinish)]
    [InlineData(ScheduledPublishOutcome.Kind.Succeeded)]
    public void NoSentenceNamesTheMachinery(ScheduledPublishOutcome.Kind kind)
    {
        string said = ScheduledPublishOutcome.Sentence(
            "ICS3U", 2, new ScheduledPublishOutcome.Result(kind, "Netlify", DateTime.Now, "ICS3U", 2));

        Assert.Contains("ICS3U", said);
        Assert.Contains("Section 2", said);
        foreach (string machinery in new[]
                 { "exit", "--non-interactive", "deploy.py", "deploy.ps1", "preview.ps1",
                   "stdin", "code 3", "Task Scheduler", "script" })
            Assert.DoesNotContain(machinery, said, StringComparison.OrdinalIgnoreCase);
    }

    // ---- The wrapper the scheduler runs ----------------------------------

    /// <summary>
    /// Every deploy leg is passed the flag.
    /// </summary>
    /// <remarks>
    /// <para>This is the whole fix. Without it on the command line, the leg
    /// reaches <c>deploy.py</c>'s site-name question and either blocks for ever
    /// or takes its default and publishes somewhere nobody chose.</para>
    ///
    /// <para><b>Asserted by CONTAINMENT, not by position, and that changed on
    /// 2026-09-09.</b> The flag used to be pasted on the end of the line by the
    /// wrapper writer, so every leg ended with it; it now comes from
    /// <c>DeployCommand.Arguments(unattended: true)</c>, which puts it straight
    /// after the course and section — where <c>app-rules.json</c> →
    /// <c>deployArguments</c> says it goes — so a Cloudflare or folder leg
    /// carries destination flags after it. Where it sits in the line is the
    /// contract's business; what this test is for is that no leg is missing
    /// it.</para>
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
            Assert.Contains("--non-interactive", leg, StringComparison.Ordinal);
    }

    /// <summary>
    /// The BUILD leg is told too, which is the half that is easy to forget.
    /// </summary>
    /// <remarks>
    /// <para>A scheduled publish builds before it publishes, and the build runs
    /// <c>preview.ps1</c> — a launcher that asks two questions of its own. Told
    /// nothing, a <c>Read-Host</c> at half six reads end of input and returns
    /// empty, so the [Y/n] course-code guard takes its DEFAULT and the build
    /// retargets a different course code. The publish that follows then
    /// succeeds against the wrong course, which is worse than a refusal because
    /// nothing looks wrong.</para>
    ///
    /// <para>Both branches are checked because there are two: the captured one
    /// that runs the build through <c>Start-Process</c> to read its folder
    /// findings, and the plain fallback for when the capture could not be set
    /// up. The fallback is the one a change would forget.</para>
    /// </remarks>
    [Fact]
    public void TheBuildLegIsToldNobodyIsThereToo()
    {
        string script = File.ReadAllText(
            GenerateWrapper(new CourseConfiguration.DeployDestination("netlify", "")));

        var buildLines = script.Split('\n')
            .Where(line => line.Contains("preview.ps1", StringComparison.OrdinalIgnoreCase)
                           && line.Contains("--build-only", StringComparison.Ordinal))
            .ToList();

        Assert.Equal(2, buildLines.Count);
        foreach (string line in buildLines)
            Assert.Contains("--non-interactive", line, StringComparison.Ordinal);
    }

    /// <summary>
    /// The record is written AFTER every destination has run, not inside the
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
    public void TheGoodNewsIsWrittenOnlyAfterEveryDestinationHasRun()
    {
        string script = File.ReadAllText(GenerateWrapper(
            new CourseConfiguration.DeployDestination("netlify", ""),
            new CourseConfiguration.DeployDestination("local_folder", _dir)));

        int lastLeg = script.LastIndexOf("--non-interactive", StringComparison.Ordinal);
        int succeeded = script.IndexOf("Write-Outcome 'succeeded'", StringComparison.Ordinal);

        Assert.True(succeeded > lastLeg,
            "The success must be written after the last destination, or a later leg that " +
            "fails leaves the teacher told their publish went out.");
        Assert.Contains("if ($allSucceeded) {", script);
    }

    /// <summary>
    /// Exit 3 is told apart from every other non-zero code, on the deploy legs
    /// AND on the build.
    /// </summary>
    [Fact]
    public void TheWrapperTellsNeedingAnAnswerApartFromFailing()
    {
        string script = File.ReadAllText(
            GenerateWrapper(new CourseConfiguration.DeployDestination("netlify", "")));

        Assert.Contains("if ($LASTEXITCODE -eq 3) {", script);
        Assert.Contains("} elseif ($LASTEXITCODE -ne 0) {", script);
        Assert.Contains("if ($buildExit -eq 3) {", script);
        Assert.Contains("} elseif ($buildExit -ne 0) {", script);
    }

    // ---- Running the generated wrapper for real --------------------------

    /// <summary>
    /// The generated PowerShell really does write the record when a leg exits
    /// 3, and really does leave it alone when a later leg succeeds.
    /// </summary>
    /// <remarks>
    /// <para>Asserting the script's TEXT cannot see whether
    /// <c>$alreadyRecorded</c> survives the loop, whether <c>Write-Outcome</c>
    /// is in a scope that can see <c>$outcomeFile</c>, or whether the
    /// <c>try/catch</c> swallows the write. The wrapper has no runner — it is
    /// executed at 6 a.m. by Task Scheduler with nobody watching — so running
    /// it here is the only place any of that is checked.</para>
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
        // Cloudflare needs an answer; the folder leg then succeeds. That order
        // is the whole point.
        File.WriteAllText(Path.Combine(work, "deploy.ps1"), """
            if ($args -contains '--target') { Write-Host 'needs an answer'; exit 3 }
            Write-Host 'published to the folder'
            exit 0
            """);

        Run(Runnable(work, "runnable.ps1",
            new CourseConfiguration.DeployDestination("cloudflare_pages", ""),
            new CourseConfiguration.DeployDestination("local_folder", _dir)), work);

        var result = ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1);
        Assert.NotNull(result);
        Assert.Equal(ScheduledPublishOutcome.Kind.NeededAnAnswer, result!.Outcome);
        Assert.Contains("Cloudflare", result.Destination, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// A run where everything got through says SO, replacing a record left by a
    /// previous night.
    /// </summary>
    /// <remarks>
    /// Two properties in one run, because they are one property: the good news
    /// is written, and last night's bad news is gone. Until 2026-09-09 the
    /// second happened and the first did not, so a teacher could learn their
    /// publish had failed and never learn it had started working again.
    /// </remarks>
    [Fact]
    public void ARunThatGetsThroughSaysSoAndReplacesLastNightsRecord()
    {
        if (!PowerShellIsAvailable) return;

        ScheduledPublishOutcome.Record(
            _dir, "ICS3U", 1, ScheduledPublishOutcome.Kind.NeededAnAnswer, "Netlify");

        string work = Path.Combine(_dir, "work ok");
        Directory.CreateDirectory(work);
        File.WriteAllText(Path.Combine(work, "preview.ps1"), "Write-Host 'built'\nexit 0");
        File.WriteAllText(Path.Combine(work, "deploy.ps1"), "Write-Host 'published'\nexit 0");

        Run(Runnable(work, "runnable-ok.ps1",
            new CourseConfiguration.DeployDestination("local_folder", _dir)), work);

        var result = ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1);
        Assert.NotNull(result);
        Assert.Equal(ScheduledPublishOutcome.Kind.Succeeded, result!.Outcome);
        Assert.Equal(_dir, result.Destination);
    }

    /// <summary>
    /// A run where a leg failed ORDINARILY is recorded as that, and does not
    /// overwrite an earlier question.
    /// </summary>
    /// <remarks>
    /// <para>Two failures that were the same mistake made smaller. The record
    /// used to be cleared on "nothing needed an answer", which is true of a run
    /// where every leg failed with exit 1 — so Monday stopped for a question
    /// and left a note, Tuesday the token was revoked and every leg failed,
    /// Monday's note was deleted, and since nothing recorded an ordinary
    /// scheduled failure the teacher was told about neither night.</para>
    ///
    /// <para>Both halves are now closed: the clear is keyed on
    /// <c>$allSucceeded</c>, and an ordinary failure writes a record of its
    /// own. This asserts the SECOND one, which is what #130 asked for.</para>
    /// </remarks>
    [Fact]
    public void AnOrdinaryFailureIsRecordedRatherThanBeingSilent()
    {
        if (!PowerShellIsAvailable) return;

        string work = Path.Combine(_dir, "work failing");
        Directory.CreateDirectory(work);
        File.WriteAllText(Path.Combine(work, "preview.ps1"), "Write-Host 'built'\nexit 0");
        // Exit 1, not 3: the token was revoked, the upload failed — an ordinary
        // failure, with nothing to do with a question.
        File.WriteAllText(Path.Combine(work, "deploy.ps1"), "Write-Host 'upload failed'\nexit 1");

        Run(Runnable(work, "runnable-failing.ps1",
            new CourseConfiguration.DeployDestination("local_folder", _dir)), work);

        var result = ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1);
        Assert.NotNull(result);
        Assert.Equal(ScheduledPublishOutcome.Kind.DidNotFinish, result!.Outcome);
        Assert.Equal(_dir, result.Destination);
    }

    /// <summary>
    /// A BUILD that stopped for a question is recorded, and no destination is
    /// contacted.
    /// </summary>
    /// <remarks>
    /// The case <c>--non-interactive</c> on <c>preview.ps1</c> created: exit 3
    /// from the build means the course-code guard, or the section warning, was
    /// put to nobody. Before this, that run exited 1 saying nothing, so the
    /// teacher's site simply did not update and the trail was empty — which is
    /// the original bug, reached down a new path.
    /// </remarks>
    [Fact]
    public void ABuildThatStoppedForAQuestionIsRecordedAndNothingIsPublished()
    {
        if (!PowerShellIsAvailable) return;

        string work = Path.Combine(_dir, "work build asked");
        Directory.CreateDirectory(work);
        File.WriteAllText(Path.Combine(work, "preview.ps1"), "Write-Host 'needs an answer'\nexit 3");
        // Would create a file if it ever ran, which is how "nothing was
        // published" is checked rather than assumed.
        string proof = Path.Combine(_dir, "deployed.txt");
        File.WriteAllText(Path.Combine(work, "deploy.ps1"),
            $"Set-Content -LiteralPath '{proof}' -Value 'ran'\nexit 0");

        Run(Runnable(work, "runnable-build-asked.ps1",
            new CourseConfiguration.DeployDestination("local_folder", _dir)), work);

        var result = ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1);
        Assert.NotNull(result);
        Assert.Equal(ScheduledPublishOutcome.Kind.BuildNeededAnAnswer, result!.Outcome);
        Assert.False(File.Exists(proof), "Nothing may be published when the build did not happen.");
    }

    /// <summary>A build that failed ORDINARILY is recorded too, naming every destination.</summary>
    [Fact]
    public void ABuildThatFailedIsRecordedAgainstEveryDestination()
    {
        if (!PowerShellIsAvailable) return;

        string work = Path.Combine(_dir, "work build failed");
        Directory.CreateDirectory(work);
        File.WriteAllText(Path.Combine(work, "preview.ps1"), "Write-Host 'broken'\nexit 1");
        File.WriteAllText(Path.Combine(work, "deploy.ps1"), "exit 0");

        Run(Runnable(work, "runnable-build-failed.ps1",
            new CourseConfiguration.DeployDestination("netlify", ""),
            new CourseConfiguration.DeployDestination("cloudflare_pages", "")), work);

        var result = ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1);
        Assert.NotNull(result);
        Assert.Equal(ScheduledPublishOutcome.Kind.DidNotFinish, result!.Outcome);
        // Nothing went up at EITHER, so both are named — and joined the way a
        // teacher would say them.
        Assert.Equal("Netlify and Cloudflare Pages", result.Destination);
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
            $"Plantoir-outcome-{Guid.NewGuid():N}", folder, Path.Combine(folder, "deploy.ps1"),
            "ICS3U", 1, Path.Combine(folder, "courses", "ICS3U"),
            Array.Empty<string>(), destinations, "");
        Assert.NotNull(path);
        _wrappers.Add(path!);
        return path!;
    }

    /// <summary>
    /// A copy of the generated wrapper with the baked outcome folder pointed at
    /// this test's scratch directory, ready to run.
    /// </summary>
    private string Runnable(
        string work, string name, params CourseConfiguration.DeployDestination[] destinations)
    {
        string script = GenerateWrapper(work, destinations);
        string runnable = Path.Combine(_dir, name);
        File.WriteAllText(runnable,
            File.ReadAllText(script).Replace(ScheduledPublishOutcome.Directory(), _dir));
        return runnable;
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
