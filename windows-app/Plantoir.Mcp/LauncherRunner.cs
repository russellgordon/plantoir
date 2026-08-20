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
        var tail = new Queue<string>();
        var gate = new object();

        void Capture(string? line)
        {
            if (string.IsNullOrWhiteSpace(line)) return;
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
        lock (gate) transcript = string.Join("\n", tail);

        return process.ExitCode == 0
            ? new LaunchOutcome(true, transcript)
            : new LaunchOutcome(false, Explain(process.ExitCode, transcript));
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
