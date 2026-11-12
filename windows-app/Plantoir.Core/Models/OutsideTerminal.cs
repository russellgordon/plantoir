using System.Collections.Generic;

namespace Plantoir.Core.Models;

/// <summary>
/// How "Open in Terminal" starts a terminal at a course's folder, as data a
/// test can read (the view maps it to a <c>ProcessStartInfo</c>). A course's
/// folder is a path a teacher named, so it may carry <c>'</c>, <c>;</c>,
/// <c>&amp;</c> or a trailing <c>\</c>: it is ONLY ever the working
/// directory, never on a command line. Windows Terminal splits at every
/// <c>;</c> even in an argument vector, so <c>-d &lt;folder&gt;</c> as its own
/// argument would not help; <c>-d .</c> in the folder does.
/// </summary>
public static class OutsideTerminal
{
    /// <summary>A program, its argument vector, the directory to open in, and whether the shell runs it.</summary>
    public sealed record Launch(string File, IReadOnlyList<string> Arguments, string WorkingDirectory, bool UseShellExecute);

    /// <summary>Windows Terminal started IN the folder, told to open where it is (<c>-d .</c>).</summary>
    public static Launch WindowsTerminal(string path) =>
        new("wt.exe", new[] { "-d", "." }, path, UseShellExecute: false);

    /// <summary>The classic-console fallback: the folder is the working directory, and there is no <c>-Command</c> for a quote to break out of.</summary>
    public static Launch Fallback(string path) =>
        new("powershell.exe", new[] { "-NoExit" }, path, UseShellExecute: true);
}
