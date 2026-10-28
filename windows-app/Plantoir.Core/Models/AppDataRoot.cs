using System;
using System.Collections.Generic;
using System.IO;

namespace Plantoir.Core.Models;

/// <summary>
/// The one folder everything Plantoir keeps on this PC hangs from —
/// <c>%LOCALAPPDATA%\Plantoir</c>, unless a run has been told to keep its
/// state somewhere else.
///
/// <para><b>Why this is one place rather than eleven.</b> Settings, the
/// breadcrumb trail, the startup log, downloaded models, built websites,
/// scheduled-deploy wrappers and their finished sentinels each used to
/// compute that path for themselves. Redirecting a run therefore meant
/// remembering all of them, and the first attempt redirected two — which left
/// a UI test consuming the teacher's REAL pending scheduled-deploy sentinels
/// on launch and writing publish state into their REAL course folders, while
/// the trail line explaining it went to the redirected trail where nobody
/// would look. An isolation you have to remember to extend is one that leaks
/// at the next thing somebody adds.</para>
///
/// <para><b>Redirecting %LOCALAPPDATA% itself does not work</b>, and was tried
/// first: <c>Environment.GetFolderPath</c> asks Windows for the known folder
/// and ignores the environment variable entirely.</para>
///
/// <para>Set once, from <c>--state-dir</c>, before anything reads anything.
/// <b>It does NOT reach other processes on its own.</b> The window's own
/// <c>plantoir-mcp.exe</c> is handed it (<c>McpClient</c> passes
/// <c>--state-dir</c> when <see cref="IsRedirected"/>, #641), so the server's
/// trail, settings and build-output root follow the window's. The UI-test
/// harness redirects ITS OWN process as well, because it sets working folders
/// up in-process and that copy writes a trail line. The LAUNCHERS are the sharp edge and are worth
/// naming separately: <c>preview.ps1</c> and <c>deploy.ps1</c> compute the
/// builds root from the environment themselves (only their TRAIL lines follow
/// the redirect, since #682: <see cref="Scripting.LauncherEnvironment"/> hands
/// them PLANTOIR_TRAIL_DIR), and the scheduled-task
/// wrapper bakes the same into the script it registers. So a redirected run
/// that PREVIEWED would look for its build where the launcher did not put it,
/// and one that SCHEDULED a deploy would register a REAL Task Scheduler task
/// whose sentinels land in the teacher's real pending folder. Since bundle 11
/// the UI suite DOES preview and publish (into the real builds root, which
/// <c>DrivenApp</c> deletes afterwards); no test schedules a deploy. An
/// <c>plantoir-mcp.exe</c> started by an outside door (Claude Code, Codex)
/// resolves its own, from the real folder.</para>
/// </summary>
public static class AppDataRoot
{
    private static string? _redirected;

    /// <summary>Where this run keeps its state.</summary>
    public static string Current =>
        _redirected ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir");

    /// <summary>
    /// Keep this run's state somewhere else. Resolved to a full path, because
    /// a relative one would land wherever the working directory happened to
    /// be — which the app changes at startup.
    /// </summary>
    public static void RedirectTo(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        _redirected = Path.GetFullPath(path);
        Directory.CreateDirectory(_redirected);
    }

    /// <summary>Whether this run is keeping its state somewhere of its own —
    /// so a caller can SAY so rather than leave a reader guessing.</summary>
    public static bool IsRedirected => _redirected is not null;

    /// <summary>The flag that carries a redirect on a command line.</summary>
    public const string StateDirFlag = "--state-dir";

    /// <summary>
    /// The folder a command line asks for: the argument after the first
    /// <c>--state-dir</c>, or null. PURE. The space-separated form only;
    /// <c>--state-dir=&lt;dir&gt;</c> is NOT accepted, by the app or by
    /// <c>plantoir-mcp</c>, because nothing writes it and a second spelling
    /// is a second thing to keep in step.
    /// </summary>
    public static string? StateDirFrom(IReadOnlyList<string> args)
    {
        for (int i = 0; i < args.Count - 1; i++)
            if (args[i] == StateDirFlag) return args[i + 1];
        return null;
    }

    /// <summary>
    /// What a child process of OURS (the window's <c>plantoir-mcp</c>, #641)
    /// is handed so it keeps its state where this run does: the flag and the
    /// folder when <paramref name="redirectedTo"/> is set, nothing otherwise.
    /// PURE; <see cref="ArgumentsToHandOn"/> is this run's answer.
    /// </summary>
    public static IReadOnlyList<string> HandOnArguments(string? redirectedTo) =>
        redirectedTo is null ? Array.Empty<string>() : new[] { StateDirFlag, redirectedTo };

    /// <summary>This run's <see cref="HandOnArguments"/>.</summary>
    public static IReadOnlyList<string> ArgumentsToHandOn => HandOnArguments(_redirected);

    public static string Combine(params string[] parts)
    {
        string path = Current;
        foreach (string part in parts) path = Path.Combine(path, part);
        return path;
    }
}
