using System.Diagnostics;
using System.Text;
using Plantoir.Core.Assist;

namespace Plantoir.Mcp;

/// <summary>
/// Runs the working folder's own launchers — the same <c>preview</c> and
/// <c>deploy</c> scripts the GUI shells and a teacher can run by hand.
///
/// This is the whole reason the MCP server is a thin thing: publishing is
/// already a script that both apps call, so the server is just another caller
/// of it, exactly like the standalone-CLI use we already protect. Nothing here
/// reimplements a publish.
///
/// **stdin is closed deliberately.** deploy.ps1 prompts for a Netlify or
/// Cloudflare token when it cannot find one stored. A prompt nobody can answer
/// would hang the tool call for as long as the client is willing to wait, and
/// an assistant reports that as "still working" indefinitely. With stdin at
/// EOF the launcher fails immediately and we can say the useful thing instead:
/// publish once from Plantoir so the token gets stored.
/// </summary>
public sealed class LauncherRunner : ILauncherRunner
{
    /// <summary>Only the last of a long build is worth reporting back.</summary>
    private const int KeptLines = 12;

    public async Task<LaunchOutcome> Run(string launcher, IReadOnlyList<string> arguments,
                                         string workingFolder, IProgress<string>? progress,
                                         CancellationToken cancellation)
    {
        string script = Path.Combine(workingFolder, launcher + (OperatingSystem.IsWindows() ? ".ps1" : ".sh"));
        if (!File.Exists(script))
            return new LaunchOutcome(false, $"This working folder has no {Path.GetFileName(script)}.");

        var info = new ProcessStartInfo
        {
            WorkingDirectory = workingFolder,
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
        };
        // The MCP server ships beside the app, so the same bundled runtime
        // sits beside this executable too - point the launcher at it, or it
        // takes the container branch (see NativeRuntime).
        Plantoir.Core.Scripting.NativeRuntime.Apply(info);

        if (OperatingSystem.IsWindows())
        {
            info.FileName = "powershell.exe";
            foreach (string argument in new[] { "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script })
                info.ArgumentList.Add(argument);
        }
        else
        {
            info.FileName = "/bin/sh";
            info.ArgumentList.Add(script);
        }
        foreach (string argument in arguments) info.ArgumentList.Add(argument);

        using var process = new Process { StartInfo = info, EnableRaisingEvents = true };
        var running = new Running(process, workingFolder, launcher, arguments);
        lock (RunningGate) { RunningNow.Add(running); }
        try
        {
            return await RunStarted(process, script, progress, cancellation);
        }
        finally
        {
            lock (RunningGate) { RunningNow.Remove(running); }
        }
    }

    // ---- Leaving mid-build (#289) -----------------------------------------

    private sealed record Running(Process Process, string WorkingFolder, string Launcher, IReadOnlyList<string> Arguments);

    private static readonly object RunningGate = new();
    private static readonly List<Running> RunningNow = new();

    /// <summary>
    /// Stop every launcher this server started and is still waiting on, and
    /// then the section's own processes — BEFORE its leases are given back.
    /// </summary>
    /// <remarks>
    /// <para>#289 (mac #156, <c>AssistMCPServer.stopOwnWorkBeforeLeaving</c>).
    /// When the client closes stdin mid-build, the host shuts down, and the
    /// lease files go with it — telling Plantoir the course is free while a
    /// <c>--build-only</c> this process started is still writing the section's
    /// build folder. A Preview pressed in that moment would build over it.</para>
    ///
    /// <para>Killing the launcher's tree is not the whole job: the build's
    /// node and python children can outlive a <c>powershell.exe</c> killed from
    /// outside, which is why <c>preview.ps1 --stop</c> exists (it ends the
    /// section's processes by working directory). Each stop is waited for, up to
    /// fifteen seconds — the ceiling PreviewStopper uses — so a wedged stop
    /// cannot hold the exit for ever. A KILL of this process skips all of it,
    /// on both platforms; that is the known limit.</para>
    /// </remarks>
    public static void StopEverythingItStarted()
    {
        List<Running> running;
        lock (RunningGate) { running = RunningNow.ToList(); }

        foreach (var run in running)
        {
            try { if (!run.Process.HasExited) run.Process.Kill(entireProcessTree: true); } catch { }
        }

        foreach (var run in running.Where(run => run.Arguments.Count >= 2)
                                   .DistinctBy(run => (run.WorkingFolder, run.Arguments[0], run.Arguments[1])))
        {
            string script = Path.Combine(run.WorkingFolder, "preview.ps1");
            if (!OperatingSystem.IsWindows() || !File.Exists(script)) continue;
            try
            {
                var info = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    WorkingDirectory = run.WorkingFolder,
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };
                Plantoir.Core.Scripting.NativeRuntime.Apply(info);
                foreach (string argument in new[] { "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script,
                                                    run.Arguments[0], run.Arguments[1], "--stop" })
                    info.ArgumentList.Add(argument);
                using var stop = Process.Start(info);
                if (stop is null) continue;
                stop.OutputDataReceived += (_, _) => { };
                stop.ErrorDataReceived += (_, _) => { };
                stop.BeginOutputReadLine();
                stop.BeginErrorReadLine();
                if (!stop.WaitForExit(15_000)) { try { stop.Kill(entireProcessTree: true); } catch { } }
            }
            catch { /* leaving anyway: a stop that cannot start must not keep the server alive */ }
        }
    }

    private async Task<LaunchOutcome> RunStarted(Process process, string script, IProgress<string>? progress,
                                                 CancellationToken cancellation)
    {
        var tail = new Queue<string>();
        var gate = new object();
        var findings = new List<Plantoir.Core.Models.SiteHealthFinding>();
        var findingsSeen = new HashSet<string>(StringComparer.Ordinal);
        Plantoir.Core.Assist.LinksChecklistMarker? linksChecklist = null;

        void Capture(string? line)
        {
            if (string.IsNullOrWhiteSpace(line)) return;

            // A folder problem, not narration. Lifted out and NEVER passed on
            // as text: it is a JSON payload, and both the progress reports and
            // the kept tail are read by a teacher through the assistant
            // (CLAUDE.md rule 1). The human sentence it carries is reported
            // properly, by the caller, out of Findings — and site_health.py
            // prints its own sentence separately besides.
            // #395: deploy.py's PLANTOIR_CLOUDFLARE_REMADE: from a deploy this
            // server ran - the same trail line the app writes from its own runs.
            if (Plantoir.Core.Models.CloudflareProjectRemade.Parse(line) is { } remade)
            {
                Plantoir.Core.Scripting.ActivityTrail.Note(
                    Plantoir.Core.Scripting.ActivityTrail.Event.CloudflareProjectMadeAgain,
                    remade.TrailSentence, remade.Course, remade.Section);
                return;
            }

            // The links checklist's marker (#392): kept, so the assistant
            // can say the checklist WILL be offered only when this build made one.
            if (Plantoir.Core.Assist.LinksChecklistMarker.Parse(line) is { } checklist)
            {
                lock (gate) linksChecklist = checklist;
                return;
            }

            if (Plantoir.Core.Models.SiteHealthFinding.Parse(line) is { } finding)
            {
                lock (gate)
                {
                    // The same problem in one run is one problem, keyed the
                    // record's own way so this and ScriptRunner cannot drift
                    // into disagreeing about what a duplicate is.
                    if (findingsSeen.Add(finding.Identity))
                    {
                        findings.Add(finding);
                        // Recorded here rather than by whatever displays it,
                        // for the reason the trail exists: this process is
                        // headless, and a teacher who asks the assistant to
                        // publish leaves no console behind to look at.
                        Plantoir.Core.Scripting.ActivityTrail.Note(
                            Plantoir.Core.Scripting.ActivityTrail.Event.FolderProblemFound,
                            finding.TrailSentence, finding.Course, finding.Section);
                    }
                }
                return;
            }

            lock (gate)
            {
                tail.Enqueue(line);
                while (tail.Count > KeptLines) tail.Dequeue();
            }
            // The launchers narrate with emoji-led milestone lines; passing
            // them straight through means the assistant's progress messages
            // are the toolchain's own words, not a paraphrase of them.
            progress?.Report(line.Trim());
        }

        process.OutputDataReceived += (_, e) => Capture(e.Data);
        process.ErrorDataReceived += (_, e) => Capture(e.Data);

        try { process.Start(); }
        catch (Exception error) { return new LaunchOutcome(false, $"{Path.GetFileName(script)} could not be started: {error.Message}"); }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        process.StandardInput.Close();   // see the note above: no prompt may hang this

        try
        {
            await process.WaitForExitAsync(cancellation);
        }
        catch (OperationCanceledException)
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
            return new LaunchOutcome(false, "The publish was stopped before it finished.");
        }

        string transcript;
        Plantoir.Core.Models.SiteHealthFinding[] found;
        lock (gate)
        {
            transcript = string.Join("\n", tail);
            found = findings.ToArray();
        }

        return process.ExitCode == 0
            ? new LaunchOutcome(true, transcript, found, 0, linksChecklist)
            : new LaunchOutcome(false, Explain(process.ExitCode, transcript), found, process.ExitCode, linksChecklist);
    }

    /// <summary>
    /// Turn a non-zero exit into something a teacher can act on. The token
    /// case is worth naming explicitly because it is the one failure the
    /// server structurally cannot fix for itself.
    /// </summary>
    private static string Explain(int exitCode, string transcript)
    {
        var message = new StringBuilder();
        if (transcript.Contains("token", StringComparison.OrdinalIgnoreCase) ||
            transcript.Contains("log in", StringComparison.OrdinalIgnoreCase))
            message.Append("This looks like a missing publishing token. Publish this section once from Plantoir " +
                           "so the token is stored, then try again. ");
        message.Append($"(The launcher exited with code {exitCode}.)");
        if (transcript.Length > 0) message.Append("\n\nLast output:\n").Append(transcript);
        return message.ToString();
    }
}
