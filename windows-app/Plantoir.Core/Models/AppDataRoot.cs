using System;
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
/// It does NOT reach other processes — <c>plantoir-mcp.exe</c> and the
/// scheduled-task wrapper each resolve their own.</para>
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

    public static string Combine(params string[] parts)
    {
        string path = Current;
        foreach (string part in parts) path = Path.Combine(path, part);
        return path;
    }
}
