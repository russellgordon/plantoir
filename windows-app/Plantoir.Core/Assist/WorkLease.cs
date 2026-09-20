using System.Diagnostics;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// A file saying "this course is being worked on right now, by me", written by
/// whichever process is doing the work and read by the other.
///
/// Plantoir and the MCP server are separate processes with separate memory.
/// Preview leases and publish records live inside the app; an assist session
/// lives inside the server. Neither can see the other, and both build into
/// the section's build folder (see <c>BuildOutputLocation</c>; NOT <c>.merged_output</c>, which Windows stopped writing to in row 290) — which the build CLEARS before
/// writing it. So the loser of a race serves a half-written site, or publishes
/// files the other just deleted.
///
/// The protocol is deliberately the simplest thing that survives a crash: one
/// file per piece of work, named for the course, the kind of work and the
/// process id that owns it, carrying that process's name. A reader treats a
/// lease whose process is gone as gone too, so a killed session or a crashed
/// app cannot leave a course locked — no cleanup pass, no timeout to tune, no
/// lock file to get stuck.
///
/// **This is the shared registry from research/ai-assist/HISTORY.md part 3 (the MCP proposal), phase 2**, and it is
/// deliberately format-first rather than API-first so the mac side can adopt
/// the same files rather than the same code.
/// </summary>
public static class WorkLease
{
    /// <summary>An assistant is holding the course through the MCP server.</summary>
    public const string Assisting = "assist";

    /// <summary>The app is building or serving a preview.</summary>
    public const string Previewing = "preview";

    /// <summary>The app is building and deploying.</summary>
    public const string Publishing = "publish";

    /// <summary>
    /// Somebody is running a BUILD of this course right now — the narrow thing
    /// that genuinely cannot happen twice at once.
    ///
    /// The other three kinds say what somebody is DOING; this one says what
    /// they are doing that clashes. Both a build and a rebuild write into
    /// the section's build folder (see <c>BuildOutputLocation</c>; NOT <c>.merged_output</c>, which Windows stopped writing to in row 290), which the build clears first,
    /// so two at once lose each other's work. Nothing else conflicts: editing
    /// Markdown does not touch that folder, and a preview SERVER only reads it.
    ///
    /// It is held for the build and released the moment the build is done —
    /// not for the life of the session or the life of the preview server.
    /// Holding it that long is what made a teacher choose between watching
    /// their preview and talking to the assistant about it, which is exactly
    /// the pairing the assistant exists for.
    /// </summary>
    public const string Building = "build";

    private static string Directory(string workspacePath) =>
        Path.Combine(Workspace.CoursesDirectory(workspacePath), ".internal", "activity");

    /// <summary>
    /// Claim a course for this process. Disposing releases it; so does the
    /// process ending, since a lease whose owner is gone is ignored.
    /// </summary>
    public static IDisposable Take(string workspacePath, string courseCode, string kind)
    {
        string path = Path.Combine(Directory(workspacePath),
            $"{courseCode.ToUpperInvariant()}.{kind}.{Environment.ProcessId}.lease");
        try
        {
            System.IO.Directory.CreateDirectory(Directory(workspacePath));
            File.WriteAllText(path,
                $"{Environment.ProcessId}\n{Process.GetCurrentProcess().ProcessName}\n{DateTime.UtcNow:O}\n");
        }
        catch { /* an unwritable folder must not stop the work itself */ }
        return new Release(path);
    }

    private sealed class Release(string path) : IDisposable
    {
        private bool _done;
        public void Dispose()
        {
            if (_done) return;
            _done = true;
            try { File.Delete(path); } catch { }
        }
    }

    /// <summary>
    /// What OTHER processes are currently doing to this course — "assist",
    /// "preview", "publish" — with duplicates removed. Empty means free.
    ///
    /// Our own leases are excluded: a process is never in its own way, and
    /// including them would have the app refuse its own publish.
    /// </summary>
    public static IReadOnlyList<string> HeldBy(string workspacePath, string courseCode)
    {
        var kinds = new List<string>();
        string prefix = courseCode.ToUpperInvariant() + ".";
        IEnumerable<string> files;
        try { files = System.IO.Directory.EnumerateFiles(Directory(workspacePath), "*.lease"); }
        catch { return kinds; }

        foreach (string file in files)
        {
            string name = Path.GetFileName(file);
            if (!name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) continue;

            // <COURSE>.<kind>.<pid>.lease
            string[] parts = name.Split('.');
            if (parts.Length < 4 || !int.TryParse(parts[^2], out int pid)) continue;
            if (pid == Environment.ProcessId) continue;

            if (!IsAlive(file, pid)) continue;
            string kind = parts[^3];
            if (!kinds.Contains(kind)) kinds.Add(kind);
        }
        return kinds;
    }

    public static bool IsHeld(string workspacePath, string courseCode, string kind) =>
        HeldBy(workspacePath, courseCode).Contains(kind);

    private static bool IsAlive(string file, int pid)
    {
        string[] lines;
        try { lines = File.ReadAllLines(file); }
        catch { return false; }
        if (lines.Length < 2) return false;

        try
        {
            var owner = Process.GetProcessById(pid);
            // A recycled process id is a different program: compare the name
            // too, so a dead session cannot be impersonated by whatever the
            // operating system handed the number to next.
            return !owner.HasExited &&
                   string.Equals(owner.ProcessName, lines[1].Trim(), StringComparison.OrdinalIgnoreCase);
        }
        catch (ArgumentException) { return false; }         // no such process: stale
        catch (InvalidOperationException) { return false; }  // exited while we looked: stale
        catch { return true; }                               // can't tell: assume busy
    }
}
