using System.Diagnostics;
using FlaUI.Core.Tools;
using Plantoir.Core.Assist;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #464, MEASURED: dismissing a scheduled deploy's band in the app takes the
/// notification about it out of Notification Center, although the
/// notification was posted by a DIFFERENT process.
/// </summary>
/// <remarks>
/// <para><b>Why it has to be measured.</b> The scheduled run is Plantoir.exe
/// started with <c>--run-scheduled-deploy</c> and no window. It posts the toast
/// and exits. The withdrawal happens later, in the app's own process, through
/// <c>AppNotificationManager.RemoveByTagAndGroupAsync</c>. That reaches the
/// other process's toast only if both register the same unpackaged identity.
/// A unit test with a stand-in poster cannot show that.</para>
///
/// <para><b>How.</b> A job set thirty days in the past is run by the x64 Debug
/// build exactly as Task Scheduler runs it (same executable, same arguments,
/// this run's <c>--state-dir</c>), so it stands down as too late: it writes the
/// section's record and posts its toast without deploying anything. The test
/// reads the toast out of the notification database Notification Center reads
/// (<c>%LOCALAPPDATA%\Microsoft\Windows\Notifications\wpndatabase.db</c>,
/// copied first because the system holds it open), opens the section in the
/// app, presses the band's Dismiss, and reads the database again. Python reads
/// the database (it is on PATH wherever this suite runs), since the test
/// project carries no SQLite library. It leaves nothing behind: the toast it
/// posts is the one it withdraws, the measurement goes to the test output
/// only, and the run's folders go with <c>DrivenApp</c>.</para>
/// </remarks>
[Collection("drives the real app")]
public class ScheduledToastWithdrawalUiTests
{
    private readonly ITestOutputHelper _output;

    public ScheduledToastWithdrawalUiTests(ITestOutputHelper output) => _output = output;

    [UiFact]
    public void DismissingTheBandWithdrawsTheNotificationTheScheduledRunPosted()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        var target = new ScheduledPublishToast.Target(CourseFixtures.Renamed, 1, app.WorkspacePath);
        string tag = ScheduledRunAnnouncement.TagFor(target);

        // The scheduled run, as Task Scheduler starts it, in a process of its own.
        string jobPath = Path.Combine(app.Scratch("proof-464"), "proof.job.json");
        File.WriteAllText(jobPath, ScheduledRun.WriteJob(new ScheduledRun.Job(
            $"Plantoir proof 464 {Guid.NewGuid():N}", app.WorkspacePath, CourseFixtures.Renamed, 1,
            DateTimeOffset.Now.AddDays(-30), new List<string>())));
        var started = DateTime.Now;
        using (var run = Process.Start(new ProcessStartInfo(DrivenApp.ExecutablePath)
               {
                   ArgumentList = { "--state-dir", app.StateDirectory, "--run-scheduled-deploy", jobPath },
                   UseShellExecute = false,
                   CreateNoWindow = true,
               })!)
        {
            Assert.True(run.WaitForExit(120_000), "the scheduled run did not end within two minutes");
            Assert.Equal(0, run.ExitCode);
        }

        string? postedUnder = null;
        Retry.WhileFalse(() => (postedUnder = OnShowUnder(tag)) is not null, TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(500));
        Assert.True(postedUnder is not null,
            $"the scheduled run posted no notification tagged {tag} in group {ScheduledRunAnnouncement.ToastGroup}, so this proves nothing");

        app.SelectSection(CourseFixtures.Renamed, 1);
        // The control: still on show once the section is open, so what follows is the Dismiss and nothing else.
        Assert.True(OnShowUnder(tag) is not null, $"the notification tagged {tag} went before Dismiss was pressed, so this proves nothing");
        app.ClickMiddleOf(app.Find("scheduledPublishNoticeDismiss", "the scheduled deploy band's Dismiss button"));

        var gone = Retry.WhileFalse(() => OnShowUnder(tag) is null, TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(500)).Result;
        string measured = $"{started:yyyy-MM-dd HH:mm}: posted by a separate Plantoir.exe process under {postedUnder}, tag {tag}; " +
                          (gone ? "gone from the notification database after Dismiss in the app" : "STILL THERE 20 s after Dismiss in the app");
        _output.WriteLine("#464 measurement, " + measured);
        Assert.True(gone, measured);
    }

    /// <summary>The handler (app identity) a toast with this tag and the scheduled group is filed under, or null.</summary>
    private static string? OnShowUnder(string tag)
    {
        const string script = """
            import os, shutil, sqlite3, sys, tempfile
            src = os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\Windows\Notifications\wpndatabase.db")
            d = tempfile.mkdtemp()
            for ext in ("", "-wal", "-shm"):
                if os.path.exists(src + ext):
                    shutil.copy(src + ext, os.path.join(d, "w.db" + ext))
            c = sqlite3.connect(os.path.join(d, "w.db"))
            rows = c.execute("select h.PrimaryId from Notification n join NotificationHandler h on n.HandlerId = h.RecordId "
                             "where n.Tag = ? and n.'Group' = ?", (sys.argv[1], sys.argv[2])).fetchall()
            c.close()
            shutil.rmtree(d, ignore_errors=True)
            print(rows[0][0] if rows else "")
            """;
        string file = Path.Combine(Path.GetTempPath(), $"plantoir-464-read-{Guid.NewGuid():N}.py");
        File.WriteAllText(file, script);
        try
        {
            using var python = Process.Start(new ProcessStartInfo("python")
            {
                ArgumentList = { "-I", file, tag, ScheduledRunAnnouncement.ToastGroup },
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true,
            })!;
            string said = python.StandardOutput.ReadToEnd().Trim();
            python.WaitForExit(30_000);
            return said.Length > 0 ? said : null;
        }
        finally { try { File.Delete(file); } catch { } }
    }
}
