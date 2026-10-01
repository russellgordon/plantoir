namespace Plantoir.Core.Assist;

/// <summary>
/// ONE watch, for the whole app, on the folder the scheduled runs leave their
/// records in (#218, mac #216) — so a teacher who stays on a section while its
/// publish set for later runs is told, rather than only when they next click
/// away and back.
/// </summary>
/// <remarks>
/// <para><b>What was measured first (the CHECK #218 asked for).</b> On Windows
/// the section's band and the sidebar's badge were re-read when a window is
/// ACTIVATED (<c>SectionDetailView.OnWindowActivated</c>,
/// <c>MainWindow</c>'s <c>Activated</c>) and when a section opens — never
/// while the app simply stays in front. The commonest return (coming back the
/// next morning) was covered; a teacher watching the run finish was not. Same
/// gap as the mac's, narrower.</para>
///
/// <para><b>One watcher, not one per window</b>: the folder is per user, not per
/// working folder, so a watcher per window would be several watchers for one
/// truth. <see cref="RecordsChanged"/> is raised on a pool thread; every
/// subscriber MARSHALS to its own UI thread. A dismissal in this process
/// (<see cref="ScheduledPublishOutcome.Changed"/>) raises it too, so the band
/// and the badge move together in both directions.</para>
///
/// <para><b>The trap, and why this one is not inert.</b> A watch on a directory
/// fires when an entry is created, and the mac measured a record written in two
/// steps as EMPTY at that instant (0 of 40 readable). Two things close it here:
/// every record this app's code writes is assembled outside the folder and moved
/// in (<see cref="ScheduledPublishOutcome.Record"/> and the wrapper's
/// <c>Write-Outcome</c>), and Windows' watcher also reports a file that GROWS
/// (<c>NotifyFilters.Size | LastWrite</c>), which the mac's vnode directory
/// watch does not — so a wrapper written by an older build, which still writes
/// in place, is re-read when its content lands. Measured numbers are in
/// documentation/07 → "The notice has to arrive while the teacher is looking".
/// Polling was rejected, as on the mac: a guessed interval for something that
/// is directly observable.</para>
/// </remarks>
public static class ScheduledPublishWatcher
{
    /// <summary>A record appeared, changed or went. Raised on a pool thread.</summary>
    public static event Action? RecordsChanged;

    private static readonly object Gate = new();
    private static FileSystemWatcher? _watcher;

    /// <summary>Start watching (idempotent). A folder that cannot be watched leaves the old behaviour.</summary>
    public static void Start(string? directory = null)
    {
        lock (Gate)
        {
            if (_watcher is not null) return;
            try
            {
                string folder = directory ?? ScheduledPublishOutcome.Directory();
                Directory.CreateDirectory(folder);
                var watcher = new FileSystemWatcher(folder, "*.txt")
                {
                    NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
                    IncludeSubdirectories = false,
                };
                watcher.Created += (_, _) => Raise();
                watcher.Changed += (_, _) => Raise();
                watcher.Deleted += (_, _) => Raise();
                watcher.Renamed += (_, _) => Raise();
                watcher.EnableRaisingEvents = true;
                _watcher = watcher;
                ScheduledPublishOutcome.Changed += Raise;
            }
            catch { _watcher = null; }
        }
    }

    /// <summary>Stop watching — for tests, and a process that is leaving.</summary>
    public static void Stop()
    {
        lock (Gate)
        {
            ScheduledPublishOutcome.Changed -= Raise;
            _watcher?.Dispose();
            _watcher = null;
        }
    }

    private static void Raise()
    {
        try { RecordsChanged?.Invoke(); } catch { /* a subscriber's fault must not stop the watch */ }
    }
}
