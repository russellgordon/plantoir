using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

namespace Plantoir.Services;

/// <summary>
/// Reclaims a stopped preview's CONTAINER-side processes. Ending the host
/// launcher alone leaves the serve chain (python3 → npm exec quartz → node →
/// esbuild) running inside the container — idling servers hold node's RAM,
/// and an orphaned mid-flight build burns real CPU until it completes. The
/// working folder's preview launcher carries a --stop mode that kills the
/// section's processes by working directory and never starts anything; this
/// runs it fire-and-forget, output discarded, exactly as the mac app's
/// PreviewStopper does (row 105).
///
/// The sweep is NOT instantaneous, and it kills by WORKING DIRECTORY — so a
/// build started for the same section while a sweep is still in flight dies
/// with the processes the sweep was actually after. Anything about to start
/// a build must therefore await <see cref="WaitForStopsToFinish"/> first.
/// The wait is scoped to one section, as on the mac: waiting for every stop
/// everywhere would be safe but would let one window's Stop delay another
/// window's Preview for no reason.
/// </summary>
public static class PreviewStopper
{
    /// <summary>One sweep in flight, and which section it belongs to.</summary>
    private sealed record Sweep(string CourseCode, int SectionNumber, Task Finished);

    private static readonly object SweepGate = new();
    private static readonly List<Sweep> PendingSweeps = new();

    /// <summary>
    /// Waits until this section has no stop sweep still running, or the
    /// deadline passes — bounded, because a stop that hangs must not take
    /// the build waiting on it down too (parity with the mac's
    /// PreviewStopper.waitForStopsToFinish, 20 s). RE-POLLS the live list,
    /// as the mac does, so a sweep launched WHILE waiting extends the wait
    /// — a frozen snapshot would let that late sweep land mid-build.
    /// </summary>
    public static async Task WaitForStopsToFinish(string courseCode, int sectionNumber)
    {
        var deadline = DateTime.UtcNow.AddSeconds(20);
        while (DateTime.UtcNow < deadline)
        {
            bool stillGoing;
            lock (SweepGate)
            {
                PendingSweeps.RemoveAll(sweep => sweep.Finished.IsCompleted);
                stillGoing = PendingSweeps.Any(sweep =>
                    string.Equals(sweep.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase)
                    && sweep.SectionNumber == sectionNumber);
            }
            if (!stillGoing) return;
            await Task.Delay(120);
        }
    }

    public static void StopSectionProcesses(string workspacePath, string courseCode, int sectionNumber)
    {
        LaunchSweep(workspacePath, courseCode, sectionNumber);
    }

    /// <summary>
    /// Starts a sweep and waits for every sweep this section has in flight —
    /// this one included — to finish, within the same bounded deadline.
    /// </summary>
    public static async Task StopSectionProcessesAsync(string workspacePath, string courseCode, int sectionNumber)
    {
        LaunchSweep(workspacePath, courseCode, sectionNumber);
        await WaitForStopsToFinish(courseCode, sectionNumber);
    }

    /// <summary>
    /// Starts the launcher's --stop mode and records it as in flight. The
    /// recorded task completes when the sweep's process exits, or after 15
    /// seconds, so a wedged stop child can never hold a waiter forever.
    /// </summary>
    private static void LaunchSweep(string workspacePath, string courseCode, int sectionNumber)
    {
        try
        {
            string scriptPath = Path.Combine(workspacePath, "preview.ps1");
            if (!File.Exists(scriptPath)) return;
            var info = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                WorkingDirectory = workspacePath,
            };
            info.ArgumentList.Add("-NoLogo");
            info.ArgumentList.Add("-NoProfile");
            info.ArgumentList.Add("-ExecutionPolicy");
            info.ArgumentList.Add("Bypass");
            info.ArgumentList.Add("-File");
            info.ArgumentList.Add(scriptPath);
            info.ArgumentList.Add(courseCode);
            info.ArgumentList.Add(sectionNumber.ToString());
            info.ArgumentList.Add("--stop");

            var process = Process.Start(info);
            if (process is null) return;
            var exited = new TaskCompletionSource();
            // Drain and discard output so the pipes can never fill and block
            // the kill; the process object frees itself when the stop ends.
            process.OutputDataReceived += (_, _) => { };
            process.ErrorDataReceived += (_, _) => { };
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            process.EnableRaisingEvents = true;
            process.Exited += (sender, _) =>
            {
                exited.TrySetResult();
                (sender as Process)?.Dispose();
            };
            if (process.HasExited) exited.TrySetResult();

            // Recorded as finished only when the sweep's process actually
            // exits — no per-sweep cap. A cap here made the wait's promise a
            // lie: a sweep slower than the cap was reported done while its
            // kill was still coming. The 20 s deadline in
            // WaitForStopsToFinish is the one and only bound.
            lock (SweepGate)
            {
                PendingSweeps.RemoveAll(sweep => sweep.Finished.IsCompleted);
                PendingSweeps.Add(new Sweep(courseCode, sectionNumber, exited.Task));
            }
        }
        catch
        {
            // Best-effort: a failed cleanup must never break the stop itself.
        }
    }
}
