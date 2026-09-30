using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// #218: the notice arrives while the teacher is looking. One app-wide watch
/// on the records' folder, and records that are whole the instant they exist.
/// No sleeps as timing: each wait is on an event, with a ceiling only so a
/// broken watch fails rather than hangs.
/// </summary>
[Collection(SharedActivityState.Name)]
public class ScheduledPublishWatcherTests : IDisposable
{
    private readonly string _dir = Directory.CreateTempSubdirectory("plantoir-watch").FullName;

    public ScheduledPublishWatcherTests() => ScheduledPublishWatcher.Stop();

    public void Dispose()
    {
        ScheduledPublishWatcher.Stop();
        try { Directory.Delete(_dir, true); } catch { }
    }

    /// <summary>
    /// A record the run writes is readable at the FIRST event, forty times out
    /// of forty — the property that made the mac's first watcher inert (0 of 40
    /// when the record was written in place).
    /// </summary>
    [Fact]
    public void ARecordIsWholeAtTheFirstEventItRaises()
    {
        const int Trials = 40;
        int readableAtFirst = 0;
        ScheduledPublishWatcher.Start(_dir);
        for (int trial = 0; trial < Trials; trial++)
        {
            string folder = Path.Combine(_dir, $"work {trial}");
            var first = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            void OnChange()
            {
                if (first.Task.IsCompleted) return;
                first.TrySetResult(ScheduledPublishOutcome.ReadFrom(_dir, "ICS3U", 1, folder) is not null);
            }
            ScheduledPublishWatcher.RecordsChanged += OnChange;
            try
            {
                ScheduledPublishOutcome.Record(_dir, "ICS3U", 1, ScheduledPublishOutcome.Kind.DidNotFinish, "Netlify", folder);
                Assert.True(first.Task.Wait(TimeSpan.FromSeconds(10)), $"trial {trial}: no event at all");
                if (first.Task.Result) readableAtFirst++;
            }
            finally { ScheduledPublishWatcher.RecordsChanged -= OnChange; }
        }
        Assert.Equal(Trials, readableAtFirst);
    }

    [Fact]
    public void DismissingInThisProcessMovesEveryReaderToo()
    {
        ScheduledPublishWatcher.Start(_dir);
        var raised = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnChange() => raised.TrySetResult();
        ScheduledPublishWatcher.RecordsChanged += OnChange;
        try
        {
            ScheduledPublishOutcome.Dismiss("NOSUCHCOURSE", 1, _dir);
            Assert.True(raised.Task.Wait(TimeSpan.FromSeconds(10)));
        }
        finally { ScheduledPublishWatcher.RecordsChanged -= OnChange; }
    }
}
