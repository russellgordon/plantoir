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
        // #473: Plantoir is copying its tools into this folder right now (the
        // first window after an update does, in the background), so a build
        // started here would read a half-copied folder. The app's marker file
        // says so; a marker whose program is gone counts for nothing.
        if (Plantoir.Core.Models.ToolchainReadiness.AnotherProgramIsGettingReady(workingFolder))
            return new LaunchOutcome(false, Plantoir.Core.Models.ToolchainReadiness.GettingReadyMessage);

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
        // takes the container branch (see NativeRuntime) - and hand it this
        // server's own trail folder (#682): the window's server, started
        // with --state-dir, keeps the launcher's lines in the redirected
        // trail; one Claude Code or Codex started hands over the real one.
        Plantoir.Core.Scripting.LauncherEnvironment.Apply(info);

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
                Plantoir.Core.Scripting.LauncherEnvironment.Apply(info);
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
        var capture = new OutputCapture(progress);

        process.OutputDataReceived += (_, e) => capture.Take(e.Data);
        process.ErrorDataReceived += (_, e) => capture.Take(e.Data);

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
            return new LaunchOutcome(false, "This was stopped before it finished.");
        }

        var (transcript, found, linksChecklist) = capture.Snapshot();

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
            message.Append("This looks like a missing deploy token. Deploy this section once from Plantoir " +
                           "so the token is stored, then try again. ");
        message.Append($"(The launcher exited with code {exitCode}.)");
        if (transcript.Length > 0) message.Append("\n\nLast output:\n").Append(transcript);
        return message.ToString();
    }

    /// <summary>
    /// What a run's output becomes (#660): every line through the one
    /// dispatch, the folder problems and the links checklist kept, the last
    /// lines of narration kept for the outcome, and narration - never a
    /// machine line - reported as progress. Its own type so a test can feed
    /// it lines (<c>LauncherRunnerCaptureTests</c>).
    /// </summary>
    internal sealed class OutputCapture
    {
        private readonly IProgress<string>? _progress;
        private readonly object _gate = new();
        private readonly Queue<string> _tail = new();
        private readonly List<Plantoir.Core.Models.SiteHealthFinding> _findings = new();
        private readonly HashSet<string> _findingsSeen = new(StringComparer.Ordinal);
        private Plantoir.Core.Assist.LinksChecklistMarker? _linksChecklist;

        internal OutputCapture(IProgress<string>? progress) => _progress = progress;

        internal void Take(string? line)
        {
            if (string.IsNullOrWhiteSpace(line)) return;

            // Every machine line goes through the ONE dispatch the app's
            // console and the scheduled record use (#660), which writes the
            // build's trail lines itself (the maps, My Progress, Swift, the
            // dated pages, a How I Teach page kept off, a repair, a remade
            // Cloudflare project) - before #660 this door read four of the
            // nine and a build the assistant started left the other five
            // nowhere. Kept here: the links checklist (#392), so the
            // assistant can say the checklist WILL be offered only when this
            // build made one, and the folder problems, which the caller
            // reports out of Findings. Recorded here rather than by whatever
            // displays them, because this process is headless and a teacher
            // who asks the assistant to publish leaves no console behind.
            var read = Plantoir.Core.Scripting.BuildMachineLines.Record(line);
            if (read.Checklist is { } checklist)
            {
                lock (_gate) _linksChecklist = checklist;
                return;
            }
            if (read.Finding is { } finding)
            {
                lock (_gate)
                {
                    // The same problem in one run is one problem, keyed the
                    // record's own way, as ScriptRunner keys it.
                    if (Plantoir.Core.Scripting.BuildMachineLines.AddFinding(finding, _findingsSeen))
                        _findings.Add(finding);
                }
                return;
            }

            // Any machine line - one read above, or a marker the shared
            // Python adds tomorrow - is JSON, not narration, and NEVER reaches
            // the assistant's progress text or the kept tail: both are read
            // by a teacher through the assistant (CLAUDE.md rule 1,
            // transcriptStripping.machineLines' one rule, as the app's
            // console applies it).
            if (read.WasMachineLine || Plantoir.Core.Scripting.TranscriptBuilder.IsMachineLine(line)) return;

            lock (_gate)
            {
                _tail.Enqueue(line);
                while (_tail.Count > KeptLines) _tail.Dequeue();
            }
            // The launchers narrate with emoji-led milestone lines; passing
            // them straight through means the assistant's progress messages
            // are the toolchain's own words, not a paraphrase of them.
            _progress?.Report(line.Trim());
        }

        internal (string Transcript, Plantoir.Core.Models.SiteHealthFinding[] Findings,
                  Plantoir.Core.Assist.LinksChecklistMarker? LinksChecklist) Snapshot()
        {
            lock (_gate) return (string.Join("\n", _tail), _findings.ToArray(), _linksChecklist);
        }
    }
}
