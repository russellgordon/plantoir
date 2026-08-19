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
/// The sweep is NOT instantaneous: the stop child takes several seconds to
/// start PowerShell, probe the engine, and kill by working directory — and
/// it kills by working directory, so a BUILD started in that window for the
/// same section dies with it. That is precisely what "stop the preview, then
/// deploy" does, since Deploy is only clickable once the preview is stopped.
/// Every in-flight sweep is therefore tracked, and anything about to start a
/// build for a section must await <see cref="WhenSweepsFinish"/> first.
/// </summary>
public static class PreviewStopper
{
    private static readonly object SweepGate = new();
    private static readonly List<Task> PendingSweeps = new();

    /// <summary>
    /// Completed once every sweep started so far has ended (or timed out).
    /// Await this before starting a preview or deploy build — a sweep that
    /// lands mid-build kills the build, and the failure it produces shows
    /// nothing but the launcher's first lines.
    /// </summary>
    public static Task WhenSweepsFinish()
    {
        Task[] snapshot;
        lock (SweepGate)
        {
            PendingSweeps.RemoveAll(sweep => sweep.IsCompleted);
            snapshot = PendingSweeps.ToArray();
        }
        return snapshot.Length == 0 ? Task.CompletedTask : Task.WhenAll(snapshot);
    }

    public static void StopSectionProcesses(string workspacePath, string courseCode, int sectionNumber)
    {
        LaunchSweep(workspacePath, courseCode, sectionNumber);
    }

    public static async Task StopSectionProcessesAsync(string workspacePath, string courseCode, int sectionNumber)
    {
        var sweep = LaunchSweep(workspacePath, courseCode, sectionNumber);
        if (sweep is not null) await Task.WhenAny(sweep, Task.Delay(5000));
    }

    /// <summary>
    /// Starts the launcher's --stop mode and returns a task that completes
    /// when the sweep ends — capped at 15 seconds so a wedged stop child can
    /// never hold up the deploys waiting on <see cref="WhenSweepsFinish"/>.
    /// Returns null when there was nothing to start.
    /// </summary>
    private static Task? LaunchSweep(string workspacePath, string courseCode, int sectionNumber)
    {
        try
        {
            string scriptPath = Path.Combine(workspacePath, "preview.ps1");
            if (!File.Exists(scriptPath)) return null;
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
            if (process is null) return null;
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

            var sweep = Task.WhenAny(exited.Task, Task.Delay(15000));
            lock (SweepGate)
            {
                PendingSweeps.RemoveAll(pending => pending.IsCompleted);
                PendingSweeps.Add(sweep);
            }
            return sweep;
        }
        catch
        {
            // Best-effort: a failed cleanup must never break the stop itself.
            return null;
        }
    }
}
