using System;
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
/// </summary>
public static class PreviewStopper
{
    public static void StopSectionProcesses(string workspacePath, string courseCode, int sectionNumber)
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
            // Drain and discard output so the pipes can never fill and block
            // the kill; the process object frees itself when the stop ends.
            process.OutputDataReceived += (_, _) => { };
            process.ErrorDataReceived += (_, _) => { };
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            process.EnableRaisingEvents = true;
            process.Exited += (sender, _) => (sender as Process)?.Dispose();
        }
        catch
        {
            // Best-effort: a failed cleanup must never break the stop itself.
        }
    }

    public static async Task StopSectionProcessesAsync(string workspacePath, string courseCode, int sectionNumber)
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
            var tcs = new TaskCompletionSource();
            process.OutputDataReceived += (_, _) => { };
            process.ErrorDataReceived += (_, _) => { };
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            process.EnableRaisingEvents = true;
            process.Exited += (_, _) =>
            {
                tcs.TrySetResult();
                try { process.Dispose(); } catch { }
            };
            if (process.HasExited)
            {
                tcs.TrySetResult();
            }
            await Task.WhenAny(tcs.Task, Task.Delay(5000));
        }
        catch
        {
            // Best-effort: a failed cleanup must never break the stop itself.
        }
    }
}
