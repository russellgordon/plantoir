using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #1016, the Windows half of the mac's #998: the preview's wait, before the
/// launch line and the address, is woken by the run's own changes instead of
/// looking once a second, and a wait for a run to end ends the moment it
/// does instead of at its next 100 ms look.
///
/// <para>Every test here fails on the code before #1016 except
/// <c>WaitingForARunThatIsNotRunningReturnsAtOnce</c>, which pins what both
/// keep (the old loop also returned at once when nothing ran): the properties
/// and the watch did not exist (the wait searched the whole transcript each
/// second), and <see cref="ScriptRunner.WaitUntilFinished"/> was a loop of
/// 100 ms delays, so its task was still pending right after the run ended.
/// The tests under "A finish that belongs to an earlier run" and the
/// unfinished-line tests fail on this branch's first head (9b6728b67) too:
/// they are the first review's two findings.
/// Timings are asserted as "already complete" or "still pending" at a point
/// the code fixes, never as a measured duration, so a slow machine cannot
/// make them flaky.</para>
/// </summary>
/// <remarks>Serialized: a run ending writes a line to the activity trail, whose path is process-wide.</remarks>
[Collection(SharedActivityState.Name)]
public class PreviewWaitWakesOnTheRunTests : IDisposable
{
    private readonly string _trailPath;

    public PreviewWaitWakesOnTheRunTests()
    {
        _trailPath = Path.Combine(Path.GetTempPath(), $"plantoir-trail-{Guid.NewGuid():N}.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trailPath);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { File.Delete(_trailPath); } catch { }
    }

    // ---- The lines, collected as they arrive -----------------------------

    [Fact]
    public void TheLaunchLineWakesTheWatchAndOrdinaryOutputDoesNot()
    {
        var runner = new ScriptRunner();
        using var watch = runner.WatchTheStanding();

        runner.ReceiveOutput("Copying shared folders\nQuartz v4.5.0\nInstalling dependencies\n");
        Assert.False(watch.HasChanged.IsCompleted, "ordinary build output woke the wait: that is the poll again, faster");
        Assert.False(runner.HasAnnouncedQuartzLaunch);

        runner.ReceiveOutput("Launching Quartz preview\n");
        Assert.True(watch.HasChanged.IsCompleted, "the launch line did not wake the wait");
        Assert.True(runner.HasAnnouncedQuartzLaunch);
    }

    [Fact]
    public void TheLaunchLineIsFoundThroughColourCodesAndAcrossTwoReads()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput("\u001b[32mLaunching Qua");
        Assert.False(runner.HasAnnouncedQuartzLaunch);   // half a line is not yet a line
        runner.ReceiveOutput("rtz preview\u001b[0m\r\nmore\n");
        Assert.True(runner.HasAnnouncedQuartzLaunch);
    }

    [Fact]
    public void TheServerLineRecordsWhenItArrivedAndWakesTheWatch()
    {
        var runner = new ScriptRunner();
        using var watch = runner.WatchTheStanding();
        DateTime before = DateTime.UtcNow;

        runner.ReceiveOutput("Started a Quartz server listening at http://localhost:8080\n");

        Assert.True(watch.HasChanged.IsCompleted);
        Assert.NotNull(runner.ServerStartedAt);
        Assert.InRange(runner.ServerStartedAt!.Value, before, DateTime.UtcNow);
        DateTime first = runner.ServerStartedAt.Value;
        runner.ReceiveOutput("Started a Quartz server listening at http://localhost:8080\n");
        Assert.Equal(first, runner.ServerStartedAt);   // the FIRST arrival; the quiet bound counts from it
    }

    // ---- The preview's lines before their line ends (#1016 review) -------

    [Fact]
    public void TheServerLineCountsBeforeItsLineEnds()
    {
        // The last line before a quiet server; ConPTY can hold its end back
        // until the next drawing (#623, #661), so it may never end at all.
        var runner = new ScriptRunner();
        using var watch = runner.WatchTheStanding();
        runner.ReceiveOutput("Done processing 12 files in 3s\nStarted a Quartz server listening at http://localhost:8080");
        Assert.NotNull(runner.ServerStartedAt);
        Assert.True(watch.HasChanged.IsCompleted, "an unfinished server line did not wake the wait");
    }

    [Fact]
    public void TheServerLineCountsWhenItArrivesInPiecesWithNoEnd()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput("\u001b[36mStarted a Quartz se");
        Assert.Null(runner.ServerStartedAt);   // the words are not all there yet
        runner.ReceiveOutput("rver listening at http://localhost:8080/\u001b[39m");
        Assert.NotNull(runner.ServerStartedAt);
    }

    [Fact]
    public void TheServerLineCountsAfterALoneCarriageReturn()
    {
        var runner = new ScriptRunner();
        runner.ReceiveOutput("Done processing 12 files in 3s\rStarted a Quartz server listening at http://localhost:8080\r");
        Assert.NotNull(runner.ServerStartedAt);
        var second = new ScriptRunner();
        second.ReceiveOutput("Done processing 12 files in 3s\r");
        second.ReceiveOutput("Started a Quartz server listening at http://localhost:8080");
        Assert.NotNull(second.ServerStartedAt);
    }

    [Fact]
    public void TheBuildersRealLaunchLineCountsWithAndWithoutItsEnd()
    {
        // build_site.py: print(f"\n🚀 Launching Quartz preview on http://localhost:{port}\n")
        var ended = new ScriptRunner();
        ended.ReceiveOutput("\n🚀 Launching Quartz preview on http://localhost:8081\n\n");
        Assert.True(ended.HasAnnouncedQuartzLaunch);
        var unended = new ScriptRunner();
        unended.ReceiveOutput("\r\n🚀 Launching Quartz preview on http://localhost:8081");
        Assert.True(unended.HasAnnouncedQuartzLaunch);
        Assert.Null(unended.ServerStartedAt);   // the launch line is not the server line
    }

    [Fact]
    public void QuartzLaunchLineIsTheContractsMarkerAndWhatTheBuilderPrints()
    {
        var origins = ContractLoader.LoadJson("app-rules.json")["markerOrigins"]!["origins"]!.AsObject();
        Assert.True(origins.ContainsKey(ScriptRunner.QuartzLaunchLine),
            "ScriptRunner.QuartzLaunchLine is not a key of app-rules.json → markerOrigins.origins");
        Assert.Equal("shared-python", origins[ScriptRunner.QuartzLaunchLine]!.ToString());
        string builder = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "scripts", "build_site.py"));
        Assert.Contains("print(f\"\\n🚀 " + ScriptRunner.QuartzLaunchLine + " on http://", builder);
    }

    [Fact]
    public void TheAnnouncedAddressWakesTheWatchOnlyWhenItChanges()
    {
        var runner = new ScriptRunner();
        using (var watch = runner.WatchTheStanding())
        {
            runner.ReceiveOutput(OutputParsers.PreviewAnnouncementMarker + "http://localhost:8081/\n");
            Assert.True(watch.HasChanged.IsCompleted);
        }
        using (var again = runner.WatchTheStanding())
        {
            runner.ReceiveOutput(OutputParsers.PreviewAnnouncementMarker + "http://localhost:8081/\n");
            Assert.False(again.HasChanged.IsCompleted, "the same address announced twice is not a change");
        }
        Assert.Equal(new Uri("http://127.0.0.1:8081/"), runner.PreviewAddress);   // localhost is read as 127.0.0.1 (#278)
    }

    [Fact]
    public void AStopWakesTheWatch()
    {
        var runner = new ScriptRunner();
        using var watch = runner.WatchTheStanding();
        runner.StopByUser();
        Assert.True(watch.HasChanged.IsCompleted);
    }

    [Fact]
    public async Task TheBoundAndTheCancelEachEndTheWaitWithoutAChange()
    {
        var runner = new ScriptRunner();
        using (var watch = runner.WatchTheStanding())
            Assert.False(await watch.UntilItChangesAsync(TimeSpan.Zero, CancellationToken.None));

        using var cancel = new CancellationTokenSource();
        using var unbounded = runner.WatchTheStanding();
        Task<bool> waiting = unbounded.UntilItChangesAsync(null, cancel.Token);
        Assert.False(waiting.IsCompleted, "a wait with no bound ended by itself");
        cancel.Cancel();
        Assert.False(await waiting);
    }

    [Fact]
    public async Task AChangeBeforeTheAwaitIsNotLost()
    {
        var runner = new ScriptRunner();
        using var watch = runner.WatchTheStanding();
        runner.ReceiveOutput("Launching Quartz preview\n");   // lands between the reading and the await
        Task<bool> waiting = watch.UntilItChangesAsync(null, CancellationToken.None);
        Assert.True(waiting.IsCompleted);
        Assert.True(await waiting);
    }

    // ---- The quiet bound --------------------------------------------------

    [Fact]
    public void TheQuietBoundIsNoneBeforeTheServerLineAndWhatIsLeftAfter()
    {
        DateTime now = new(2026, 11, 20, 3, 0, 0, DateTimeKind.Utc);
        Assert.Null(PreviewReachability.UntilTheQuietRunsOut(null, now, now));
        Assert.Equal(TimeSpan.FromSeconds(45), PreviewReachability.UntilTheQuietRunsOut(now, now.AddSeconds(-5), now));
        // Output after the server line moves the bound.
        Assert.Equal(TimeSpan.FromSeconds(35), PreviewReachability.UntilTheQuietRunsOut(now.AddSeconds(-20), now.AddSeconds(-10), now));
        Assert.Equal(TimeSpan.Zero, PreviewReachability.UntilTheQuietRunsOut(now.AddSeconds(-60), now.AddSeconds(-50), now));
        // Where the bound reaches zero, NextStep gives up: the two agree.
        DateTime started = now.AddSeconds(-45);
        Assert.Equal(TimeSpan.Zero, PreviewReachability.UntilTheQuietRunsOut(started, started, now));
        Assert.Equal(PreviewReachability.Step.GiveUpSilence,
                     PreviewReachability.NextStep(false, new Uri("http://localhost:8081/"), started, started, now));
    }

    // ---- A wait for the run to end ----------------------------------------

    [Fact]
    public async Task WaitingForTheRunEndsTheMomentItEnds()
    {
        var runner = new ScriptRunner();
        runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), "building\n");
        Task<bool> finished = runner.WaitUntilFinished();
        Assert.False(finished.IsCompleted);

        // The only way to end a run with no process: the bounded wait's own
        // force-finish, with a bound of nothing.
        await runner.WaitUntilFinishedOrKill(0);

        Assert.True(finished.IsCompleted, "the wait was still pending after the run ended: a look-again loop");
        Assert.False(await finished);   // ended by the force-finish: exit -1
        Assert.False(runner.IsRunning);
        Assert.Equal(-1, runner.LastExitCode);
    }

    [Fact]
    public async Task WaitingForARunThatIsNotRunningReturnsAtOnce()
    {
        var runner = new ScriptRunner();
        Task<bool> finished = runner.WaitUntilFinished();
        Assert.True(finished.IsCompleted);
        Assert.False(await finished);   // no run, no exit code: not a success
        Assert.True(runner.WaitUntilFinishedOrKill(60_000).IsCompleted);
    }

    // ---- A finish that belongs to an earlier run (#1016 review) ---------

    /// <summary>
    /// The build-then-deploy case: the build's reader and exit watcher each
    /// post a finish; the first ends the build and the deploy leg starts on
    /// the same runner; the second, arriving late, must not end the deploy.
    /// </summary>
    [Fact]
    public void AFinishFromAnEarlierRunDoesNotEndTheNextOne()
    {
        var runner = new ScriptRunner();
        runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), "building\n");
        int buildRun = runner.CurrentRunNumber;
        runner.FinishRunNumber(buildRun, 0);        // the reader's finish
        Assert.False(runner.IsRunning);

        runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), "deploying\n");
        Task<bool> deployFinished = runner.WaitUntilFinished();
        runner.FinishRunNumber(buildRun, 0);        // the exit watcher's, late

        Assert.True(runner.IsRunning, "a finish posted by the build ended the deploy");
        Assert.False(deployFinished.IsCompleted, "the deploy's wait ended on the build's finish");

        runner.FinishRunNumber(runner.CurrentRunNumber, 3);
        Assert.False(runner.IsRunning);
        Assert.Equal(3, runner.LastExitCode);
    }

    [Fact]
    public async Task AHandlerThatStartsTheNextRunDoesNotStrandTheWaiters()
    {
        var runner = new ScriptRunner();
        runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), "building\n");
        Task<bool> buildFinished = runner.WaitUntilFinished();
        bool startedTheNext = false;
        runner.PropertyChanged += (sender, change) =>
        {
            if (change.PropertyName == nameof(ScriptRunner.IsRunning) && !runner.IsRunning && !startedTheNext)
            {
                startedTheNext = true;
                runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), "deploying\n");
            }
        };

        runner.FinishRunNumber(runner.CurrentRunNumber, 0);

        Assert.True(startedTheNext);
        Assert.True(buildFinished.IsCompleted, "the build's waiters were stranded by the run their own finish started");
        Assert.True(await buildFinished);
        Assert.True(runner.IsRunning);
        Assert.False(runner.WaitUntilFinished().IsCompleted, "the next run's wait was completed by the build's finish");
    }

    [Fact]
    public async Task TheBoundedWaitNeverEndsARunStartedAfterIt()
    {
        var runner = new ScriptRunner();
        runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), "stopping\n");
        Task<bool> waiting = runner.WaitUntilFinishedOrKill(60_000);
        runner.FinishRunNumber(runner.CurrentRunNumber, 0);
        runner.StageAsRunningForCapture(Array.Empty<TaskMilestone>(), "the next run\n");
        Assert.True(await waiting);
        Assert.True(runner.IsRunning, "the bounded wait for the first run force-finished the second");
    }

    /// <summary>
    /// The reader and the exit watcher need a real process, so how they post
    /// is pinned by the source: each carries its run's number, and the exit
    /// watcher joins its own run's reader, not whatever the field holds.
    /// </summary>
    [Fact]
    public void TheReaderAndTheExitWatcherPostTheirOwnRunsFinish()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Scripting", "ScriptRunner.cs"));
        int start = source.IndexOf("private void ReadLoop(", StringComparison.Ordinal);
        int end = source.IndexOf("private int BeginRunNumber()", start, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start, "ReadLoop and ExitWatch were not found");
        string body = source[start..end];
        Assert.Equal(2, CountOf(body, "Post(() => FinishRunNumber(runNumber, exitCode))"));
        Assert.DoesNotContain("Post(() => FinishRun(", body);
        Assert.DoesNotContain("_readerThread", body);
    }

    private static int CountOf(string text, string part)
    {
        int count = 0;
        int at = text.IndexOf(part, StringComparison.Ordinal);
        while (at >= 0)
        {
            count += 1;
            at = text.IndexOf(part, at + part.Length, StringComparison.Ordinal);
        }
        return count;
    }

    // ---- The view's wait uses them (source rule) ------------------------

    /// <summary>
    /// <c>SectionDetailView</c> is WinUI and cannot be built into this suite,
    /// so its wait is pinned by its source: it watches the run's standing and
    /// reads the collected lines, and never searches the transcript again.
    /// The behaviour end to end is <c>PreviewStartPageUiTests</c>' (a real
    /// preview opening its page).
    /// </summary>
    [Fact]
    public void ThePreviewsWaitWatchesTheRunAndNeverSearchesTheTranscript()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SectionDetailView.xaml.cs"));
        int start = source.IndexOf("private async Task WaitForPreviewServer(", StringComparison.Ordinal);
        Assert.True(start >= 0, "WaitForPreviewServer was not found");
        int end = source.IndexOf("private async Task GiveUpOnThePreview(", start, StringComparison.Ordinal);
        string body = source[start..end];
        Assert.Contains("WatchTheStanding()", body);
        Assert.Contains("UntilItChangesAsync(", body);
        Assert.Contains("HasAnnouncedQuartzLaunch", body);
        Assert.Contains("ServerStartedAt", body);
        Assert.DoesNotContain("DisplayText", body);
        Assert.DoesNotContain("\"Launching Quartz preview\"", body);
    }
}
