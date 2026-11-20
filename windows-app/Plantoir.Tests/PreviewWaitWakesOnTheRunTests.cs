using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #1016, the Windows half of the mac's #998: the preview's wait, before the
/// launch line and the address, is woken by the run's own changes instead of
/// looking once a second, and a wait for a run to end ends the moment it
/// does instead of at its next 100 ms look.
///
/// <para>Every test here fails on the code before #1016: the properties and
/// the watch did not exist (the wait searched the whole transcript each
/// second), and <see cref="ScriptRunner.WaitUntilFinished"/> was a loop of
/// 100 ms delays, so its task was still pending right after the run ended.
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
        Assert.Equal(new Uri("http://localhost:8081/"), runner.PreviewAddress);
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
